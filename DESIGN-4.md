# DESIGN-4 — fleet partition planner (4 cards × 2 dies, no P2P, layer-split-only runtime)

Scope (PROBLEM-4.md): place one model (dense-GEMM shape and MoE shape, both parameterised so that the int8
residency lands inside the 320..400 GB band that errata #12 forces), its KV cache and a draft model on 8 dies
of 86 GB, choose the per-token exchange schedule through host memory, and predict tokens/s per card at
L ∈ {4k, 32k, 128k, 1M} with the binding constraint named per cell. Everything derives from HW-MAP.md (as of
commit f951a5c, the direct-load silicon sync), DESIGN.md (dense decode kernel: the per-die rate inputs),
DESIGN-2.md (MoE kernel: the per-expert chain and its two regimes) and PROBLEM-3.md (attention: the two
unmeasured rates G and E are carried as branches — no DESIGN-3.md exists, so the attention cost model is
stated here, minimal and branched). Status tags: **M** measured (HW-MAP), **D2** derived in DESIGN-2,
**D** derived here by arithmetic shown, **A** explicit assumption with the host experiment (H-number, §8)
that measures it, **U** unmeasured and branched.

Units: bytes binary where named KiB/MiB/GiB, memory totals in decimal GB (HW-MAP quotes 86 GB usable);
rates in GB/s decimal (1 B/ns = 1 GB/s); times in ns floored, quoted in ms/µs round-half-up; tokens/s to
three decimals. Every derived cell is printed by **`proof/fleet.py`** (integer arithmetic only, Python ≥ 3.8,
no dependencies; label `[Fx-…]` in the text) in the conventions of `proof/model.py` / `proof/moe.py`, so the
proof session can transcribe it into core Lean 1:1 — the theorem targets are listed in Appendix A.

**Definitions.** *Chain position* p ∈ 0..7 is the order in which a token visits the dies. *Π* is the number of
independent sequences in flight across the chain at once (the measured runtime behaviour is Π = 1: "dies
alternate, no concurrent streaming"). *B* is the number of sequences batched into one GEMM row block on a
die, *t* the query tokens per sequence per step (t = k + 1 for a verify batch with k draft tokens), *rows* =
B·t ≤ 16 (the flat regime). **tokens/s per card = fleet tokens/s ÷ 4** — one model instance spans the fleet.
L = 4k/32k/128k/1M means 4096 / 32 768 / 131 072 / 1 048 576 tokens.

## Constants used

| Symbol | Value | Status / origin |
|---|---|---|
| R_gemm | **174.6 GB/s** per die, full W8 decode kernel, flat m = 1..16; serial fallback 138.9; m ≥ 24 leaves the flat regime (81/59/43) | M (data-movement) |
| R_ddr / R_read | 173.8 r+w stream roof / ~181 pure read | M |
| Host links | die 0: 27.6 H2D / 27.3 D2H; die 1: 13.9 / 19.0, transiting die 0 | M (card table) |
| P2P | **refused by the runtime**; D2D copy via host 10.7 GB/s r+w | M (errata #11) |
| Runtime | layer-split works (+2 % at 2 dies, dies alternate, no concurrent streaming); **tensor-split of one op faults** | M (errata #11) |
| T_slab | **122 979 ns** per (active expert, 16 MiB slab) per core, MoE serial regime, anchored to the measured dense kernel; ping-pong regime 97 015 ns = (784 118 − 8 000)/8; F = 8 µs per launch | D2 ([M15], [M1]) |
| D(t) | active experts per step: uniform min(8t, 256); Zipf(1.0) 8/25/68 and Zipf(1.5) 8/20/45 at t = 1/4/16 | D2 (§7.1 generator means) |
| c_mma | 15 ns per (16,16,128) MMA call | M |
| R_vec | 40 lanes/cycle × 1.08 GHz × 8 cores = 345.6 G lane-ops/s per die | M |
| T_launch | 91 µs launch + queue floor, per kernel launch (serialised unless H6 shows pipelining) | M |
| Memory | 86 GB usable per die, 8 dies = 688 GB; L0/S1/US sizes per HW-MAP (not binding here) | M |
| Power | 141 W per card sustained all-core matrix load, 150 W TDP class, no throttle | M |
| G | KV read rate of the attention kernel: **stream** branch 174.6 (contiguous per-core head slabs, the pattern that measured 180/181); **gather3x** branch 58.2 (3× slower, PROBLEM-3's risk framing) | U — PROBLEM-3 E-gather; A-layout §1(c) |
| c_E | vector lane-ops per attention score incl. max-subtract, sum, rescale: **native** exp 4; **poly** (no exp instruction) 16 | U — PROBLEM-3 E-exp |
| λ | host-bounce latency per direction (bandwidths are measured, latency is not): **91 µs primary** (the only measured runtime floor of this class), bracket 10 / 500 µs | A — H3 |
| O_rt, WS | runtime overhead 2 GiB and workspace 64 MiB per die | A — H8 |
| α | draft acceptance per token: 0.5 / **0.7** / 0.9 | A — fleet-only (§8 H9) |
| Π | sequences in flight across the chain: **1 (measured)**; 8 is the §5 what-if | M / U — H4 |

**Shapes** (`[F0]`): both are the 2× int8 expansion of a 160..200 GB sub-8-bit source.

| | dense "D" (405B-class geometry) | MoE "M" (PROBLEM-2 headline slabs) |
|---|---|---|
| layers | 120 | 28 |
| d_model / FFN | 16 384 / 53 248 | 4 096 / experts |
| heads H_q / H_kv / d_h | 128 / 8 / 128 (g = 16) | 32 / 8 / 128 (g = 4) |
| per-layer resident int8 | 3 187 671 040 B (QKV 18432 + O + gate/up 106496 + down) | 41 943 040 B attention + 256 experts × 3 slabs × 4096² = 12 926 844 928 B |
| embed + lm_head | 2 × 2 101 346 304 B | 2 × 525 336 576 B |
| **total int8** | **386.7 GB** (int4 source 193.3) | **363.0 GB** (181.5) |
| streamed per token (t = 1, uniform) | 384.6 GB | 12.9 GB (8 experts × 48 MiB + attention per layer, + lm_head) |
| KV per token per layer (f16) | 4 096 B → 491 520 B per token | 4 096 B → 114 688 B per token |
| KV at L = 1M (f16) | **515.3 GB** | 120.2 GB |
| launches per layer | 6 (QKV, attention, O, gate-up, down, norm/rope/residual) | 7 (+ router, experts gate-up fused, experts down) |

Draft model: 1 GB int8, 24 layers, 121 launches per draft token, 4k-token sliding window of its own KV
(201 MB), k = 3 draft tokens per verify step (PROBLEM-4's "up to 3").

---

## 0. Summary — does any configuration close, and at what tokens/s

**Yes, both shapes run on the 8-die fleet as int8, and the fleet's size buys context, not speed.**

| Question | Answer | Where |
|---|---|---|
| Memory | dense 386.7 GB fits with f16 KV up to **L_max = 551 253** tokens (B = 1); **1M does not close with f16 KV** (515.3 GB of KV against 282.3 GB of room, `[F9-mem]`); it closes with the **KV-int8 escape at 84.3 of 86 GB** on the worst die (1.7 GB margin, hostage to the 2 GiB overhead assumption H8). MoE 363.0 GB fits with f16 KV to L_max = 1 925 823. Minimum fleet for either shape: 5 dies (3 cards). | §1, T3–T4 |
| tokens/s per card at L = 32k (primary branch) | **dense 0.105** (t = 1), 0.262 with spec decode (α = 0.7, k = 3), 1.067 at B = 16 sequences; **MoE 1.867** (t = 1), 2.357 at B = 16 uniform (4.765 under Zipf 1.5); **spec decode is a loss on MoE** (1.451) because the verify batch multiplies the active-expert set (T12). | §3, §6 |
| Binding constraint | in every Π = 1 cell the **weight stream of ONE die at a time** (layer-split serialises the dies: the fleet streams 174.6 GB/s, not 8 × 174.6); KV binds for MoE at 1M (86 % of the step) and for dense beyond L* = 778 240; host bounce is ≤ 1.1 %; the launch floor is 13.5 % of the MoE step; softmax never binds at t = 1. | §4 |
| 1M | MoE 0.312 tokens/s/card (KV-bound: 688.8 of 801.1 ms); dense 0.066 with KV-int8 (weights-bound; KV 1 475.9 of 3 746.0 ms); dense with f16 KV: infeasible. | §3 |
| What a runtime upgrade buys | P2P at any rate: ≤ 1.5 ms per token (≤ 1.1 %); D2D 10.7 → 50: nothing per token; tensor-split: 5.9× dense / 3.1× MoE (then launch-floor-bound); **pipelining Π = 8 independent sequences: 7.7× dense / 7.1× MoE throughput** at unchanged per-sequence latency. | §5 |
| The single measurement | **H4: does the runtime pipeline independent sequences through the layer-split chain?** It moves every cell by ~7×; no other unknown moves any cell by more than 1.3× (G 3× slower: −7 % dense / −24 % MoE; MoE ping-pong regime +15 %; launch pipelining +3 % / +16 %; λ 10 ↔ 500 µs: ±5 % MoE). | §10 |

Honest ceiling of any layer-split, single-stream plan on this fleet (T2): tokens/s ≤ R_gemm / bytes streamed
per token = 174.6 / 384.6 = **0.454 tokens/s fleet-wide for dense** (0.113 per card) and 174.6 / 12.9 ≈ 13.5
for MoE (3.4 per card) — the predicted 0.105 / 1.867 are 93 % / 55 % of those ceilings (MoE loses to the
serial-regime expert kernel 135.3 vs 174.6, the launch floor and the KV stream).

---

## 1. The partition (a)–(f)

### 1.1 (a) layer → die assignment (contiguous blocks, 7 boundaries)
Chain order puts a **die 1 first and a die 0 last**: the first position receives only token ids (4 B over
the 13.9 GB/s link), the last emits the logits (513 KB at t = 1) over the 27.3 GB/s link instead of 19.0
(`[F2-order]`: 18.8 vs 27.0 µs). Hop bandwidth cost is otherwise order-invariant (T7, §2).

| pos | card.die | dense layers (15 each) | MoE layers (4/3) | extras |
|---|---|---|---|---|
| 0 | c0.d1 | 0–14 | 0–3 | embedding table |
| 1 | c0.d0 | 15–29 | 4–6 | **dense draft model** (1 GB + 0.2 GB window) |
| 2 | c1.d1 | 30–44 | 7–10 | |
| 3 | c1.d0 | 45–59 | 11–13 | |
| 4 | c2.d1 | 60–74 | 14–17 | |
| 5 | c2.d0 | 75–89 | 18–20 | |
| 6 | c3.d1 | 90–104 | 21–24 | |
| 7 | c3.d0 | 105–119 | 25–27 | lm_head; **MoE draft model** (reserved, §6) |

Boundaries: dense after layers 14, 29, 44, 59, 74, 89, 104; MoE after 3, 6, 10, 13, 17, 20, 24. 28 MoE
layers do not divide by 8 (3.5 per die): the 4-layer dies take 4/3 of a 3-layer die's time, which is
invisible at Π = 1 (T1: the step is the sum) and costs 12.5 % at Π = 8 (§5; a sub-layer split — attention
block / expert block as separate runtime units, 56 units = 7 per die — would balance it exactly, contingent
on the runtime accepting sub-layer placement, H4).

Why contiguous blocks: every boundary is a host bounce on the critical path (§2); 7 is the minimum for 8
dies. Why 8 dies and not 5: T2 — under layer-split the step time Σ_layers T_layer is the same for any
partition (Σ_pos n_pos = n_L), so extra dies cost one hop each (≈ 2λ + 3 µs) and buy KV room: 5 dies hold
dense only to L ≈ 53k (24 layers = 76.5 GB per die, 78.6 with the embedding table, leaves 5.2 GB), 8 dies hold 551k.

### 1.2 (b) expert → die placement (MoE)
All 256 experts of a layer live on the layer's die: an expert-parallel split across dies would be a
tensor-split of one op (the measured runtime fault, errata #11) and would add 2 host reductions per layer.
Inside a die, DESIGN-2 scheme S: core c owns column slice c of every active expert (per-core bytes identical
under every routing outcome, DESIGN-2 Z2), 3 slabs per expert (gate+up fused into one launch of two slabs,
down in a second), region-difference accumulator reset. The 12.0 GB of expert slabs per layer are packed
per DESIGN-2 §2.1 at load.

### 1.3 (c) KV placement and growth policy
KV is die-local to its layers (errata #11). Per (layer, kv-head) one contiguous K slab and one V slab of
L_cap × 256 B each (f16, d_h = 128), **core c ↔ kv-head c** (8 heads = 8 cores): a decode step on a layer is 16
sequential per-core streams of L × 256 B, i.e. the "per-core slabs" access pattern of the measured 180/181
GB/s figures — this is what justifies the stream branch of G, and the gather3x branch is kept because the
attention kernel is unbuilt (PROBLEM-3). Append-only: the new token's K/V (8 KiB per layer at t = 1) is
written at offset L inside the attention launch; no paging, no reallocation. L_cap per die is fixed at load
from the memory table (T4): dense 551 253 (f16) / 1 102 506 (int8), MoE 1 925 823. Online softmax in 2048-key
blocks (scores 16 × 2048 × 4 B = 128 KiB in L0C, double-buffered; running max/sum per (query row, head):
O(t·H) state, never O(L)).

**KV-int8 variant** (the dense escape above 551k): K and V stored as per-token-quantised i8 (2 048 B per
token per layer), scores and PV on the i8×i8→i32 route the dense kernel already runs (errata #13's realised
path), P quantised per row to i8 for the PV pass — a numerics risk (§9), not a rate risk: the stream halves.

### 1.4 (d) draft placement — §6
Dense: position 1 (c0.d0), the die with the fewest extras (the binding die for L_max is position 0 with the
embedding table, so the draft costs no context: `[F1-dense-draftfree]` = `[F1-dense-Lmax]` = 551 253).
MoE: not deployed (T12); 1.2 GB reserved on position 7.

### 1.5 (e) exchange schedule — §2
Per token-step: 7 activation hops (rows × d_model × 2 B each), logits D2H from position 7, sampled ids H2D
to position 0; nothing else crosses a die boundary (KV never moves; draft tokens are ids).

### 1.6 (f) load policy / residency
Host expands the int4 source to int8 per 64 KiB chunk (errata #12's "host-side int4→int8 expansion at
load") into pinned buffers and streams per die; fully resident thereafter. Link-bound load time: 386.7 GB
over 4 card trunks at 27.6 GB/s = 3.5 s (`[F8-H7]`), far below any host-side expansion rate that matters.
No on-the-fly weight streaming: a byte served from the host costs 27.6 vs 174.6 GB/s = 6.3× its DDR time,
and a host-paged KV prefix costs the same ratio (§9, T10): both escapes are quantified there and rejected
for the baseline in favour of the KV-int8 escape, which costs no link bandwidth.

### 1.7 Memory feasibility per die (`[F10-mem-*]`, `[F1]`)
Totals = weights + extras + KV + 64 MiB workspace + 2 GiB runtime (A, H8); "fits" = ≤ 86.0 GB.

**Dense, L = 4k (f16 KV):**

| pos | card.die | layers | weights GB | extras | KV GB | ws+rt GB | total GB | fits |
|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 15 | 49.9 | embed | 0.2 | 2.2 | 52.3 | yes |
| 1 | c0.d0 | 15 | 49.0 | draft | 0.2 | 2.2 | 51.4 | yes |
| 2–6 | c1.d1 … c3.d1 | 15 | 47.8 | - | 0.2 | 2.2 | 50.2 | yes |
| 7 | c3.d0 | 15 | 49.9 | lm_head | 0.2 | 2.2 | 52.3 | yes |

**Dense, L = 1M, f16 KV: infeasible on every die** — 15 layers × 4 096 B × 2²⁰ = 64.4 GB of KV per die, totals
114.4–116.5 GB (`[F10-mem-dense-1M]`). **Dense, L = 1M, KV-int8:**

| pos | card.die | layers | weights GB | extras | KV GB | ws+rt GB | total GB | fits |
|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 15 | 49.9 | embed | 32.2 | 2.2 | **84.3** | yes |
| 1 | c0.d0 | 15 | 49.0 | draft | 32.2 | 2.2 | 83.4 | yes |
| 2–6 | c1.d1 … c3.d1 | 15 | 47.8 | - | 32.2 | 2.2 | 82.2 | yes |
| 7 | c3.d0 | 15 | 49.9 | lm_head | 32.2 | 2.2 | **84.3** | yes |

**MoE, L = 4k and L = 1M (f16 KV):**

| pos | card.die | layers | weights GB | extras | KV 4k | total 4k | KV 1M | total 1M | fits |
|---|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 4 | 52.2 | embed | 0.0 | 54.5 | 17.1 | 71.6 | yes |
| 1, 3, 5 | c0.d0, c1.d0, c2.d0 | 3 | 38.7 | - | 0.0 | 41.0 | 12.8 | 53.8 | yes |
| 2, 4, 6 | c1.d1, c2.d1, c3.d1 | 4 | 51.7 | - | 0.0 | 53.9 | 17.1 | 71.1 | yes |
| 7 | c3.d0 | 3 | 40.5 | lm_head + draft | 0.0 | 42.7 | 12.8 | 55.6 | yes |

**T4 (context capacity):** L_max = min_pos ⌊(86·10⁹ − 2 GiB − 64 MiB − W_pos) / (n_pos · kv_tok · B)⌋:
dense f16 **551 253** (B = 1), 137 813 (B = 4), 34 453 (B = 16); dense int8 1 102 506; MoE 1 925 823 /
481 455 / 120 363. Every GB of per-die overhead beyond the assumed 2 GiB costs 16 276 tokens of dense L_max
and 61 035 of MoE (`[F1-dLmax]`). The B = 16 throughput configuration of §3 is memory-feasible for dense
only to 34k and for MoE to 120k: the "MEM" cells of the regime map.

---

## 2. Per-token exchange traffic and its serialisation against compute

### 2.1 Traffic table (`[F10-xch-*]`, `[F2]`) — bandwidth terms at the measured link rates, latency λ separate
Activation per hop = rows × d_model × 2 B (f16): dense 32 KiB (t = 1) / 128 KiB (t = 4), MoE 8 / 32 KiB.
Logits = rows × 128 256 × 4 B (f32; the sampler runs on the host — on-device sampling is a runtime feature
not in HW-MAP, so the conservative path is costed).

| hop | from → to | dense bytes r=1 | link out / in GB/s | dense µs r=1 | dense µs r=4 | MoE bytes r=1 | MoE µs r=1 | MoE µs r=4 |
|---|---|---|---|---|---|---|---|---|
| 0 | pos0 c0.d1 → pos1 c0.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 1 | pos1 c0.d0 → pos2 c1.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 2 | pos2 c1.d1 → pos3 c1.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 3 | pos3 c1.d0 → pos4 c2.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 4 | pos4 c2.d1 → pos5 c2.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 5 | pos5 c2.d0 → pos6 c3.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 6 | pos6 c3.d1 → pos7 c3.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| L | pos7 c3.d0 logits → host | 513 024 | 27.3 / – | 18.8 | 75.2 | 513 024 | 18.8 | 75.2 |
| I | host ids → pos0 c0.d1 | 4 | – / 13.9 | 0.0 | 0.0 | 4 | 0.0 | 0.0 |
| **Σ bandwidth** | | | | **41.1** | **164.4** | | **24.4** | **97.5** |
| latencies | 7 hops × 2 + L + I = **16 λ** | | | | | | | |

Each hop is D2H (die → pinned host buffer) + H2D (host buffer → next die): the host touches nothing in
between for hops 0–6; for L/I the host samples (≤ 0.1 ms of CPU work at 128 256 logits, overlapped with
nothing — counted inside λ's bracket).

**Total per token-step** T_x = Σbw + 16λ (`[F2-*]`):

| λ (A, H3) | dense r=1 | dense r=4 | MoE r=1 | MoE r=4 |
|---|---|---|---|---|
| 10 µs | 201 µs | 324 µs | 184 µs | 257 µs |
| **91 µs (primary)** | **1 497 µs** | 1 620 µs | **1 480 µs** | 1 553 µs |
| 500 µs | 8 041 µs | 8 164 µs | 8 024 µs | 8 097 µs |

### 2.2 Serialisation analysis (Π = 1: every bounce is on the critical path, nothing overlaps it)
Layer-split with one sequence is inherently serial — layer ℓ+1 cannot start before layer ℓ's output has
bounced — so the exchange is modelled as **fully additive**, the worst case the prompt warns about: T_step =
Σ_layers T_layer + T_head + T_launch + T_x (+ T_draft). Shares at L = 32k, λ = 91 µs: dense 1.497 / 2 362 ms =
**0.06 %**, MoE 1.480 / 133.84 ms = **1.1 %** (`[F5-*-p2p]`).

**T8 (bounce threshold).** The bounce reaches a fraction x of the step iff λ ≥ (x·T_step − Σbw)/16:
10 % needs λ ≥ 14.8 ms (dense) / **835 µs (MoE)**; 50 % needs 73.8 ms / 4.18 ms (`[F9-*-lambda]`). The
measured "+2 % at 2 dies" (one boundary, on a model of unstated size) bounds nothing sharper than λ ≲ 1 % of
that model's step; H1/H3 measure λ directly.

**T7 (order invariance).** Every die receives the activation once and sends it once, so Σbw = Σ_dies
act·(10/H2D(die) + 10/D2H(die)) over the 7 hops is the same for every chain order; the only order-dependent
terms are the logits source (27.3 vs 19.0 GB/s: 18.8 vs 27.0 µs) and the id sink. The chosen order is
optimal by 8 µs per token and otherwise free.

### 2.3 The host bounce as a contended resource
- **Per-card trunk occupancy.** Die 1's link transits die 0, so each card's die-0 link carries its own
  hops plus die 1's: per token (dense r=1) 98 KiB, 128 KiB, 128 KiB and 597 KiB on the logits card
  (`[F2-dense-rows1]`); against a budget of 27.6 GB/s × T_step = 65 GB (dense) / 3.7 GB (MoE) per token the
  utilisation is < 0.02 %. **Bandwidth never binds; latency is the whole cost.**
- **Concurrent transfers.** At Π = 1 the only transfers that can coexist with a bounce are the draft's
  logits/ids (its die is idle otherwise) — no queueing. At Π = 8 (§5) up to 8 bounces per block time share
  the trunks: 8 × 128 KiB per 18.6 ms block (MoE) = 0.2 % utilisation; still no queueing.
- **Bulk traffic (load, re-partition KV moves, any host-paging escape) does queue ahead of a bounce.** With
  bulk chunk size C on the same link the added wait is ≤ C/R_link per direction (T-queue, `[F8-H3]`): 64 KiB →
  5 µs, 1 MiB → 75 µs, 16 MiB → 1.2 ms on the 13.9 GB/s die-1 link. Rule: bulk streams that overlap decode
  are chunked at ≤ 1 MiB; H3 measures the realised wait under exactly this contention and fails the
  rule if the wait exceeds C/R + λ.
- **Hop 1/3/5 (d0 → d1', H2D at 13.9) is the slowest hop** (3.6 µs at 32 KiB, 14.2 at 128 KiB); the 2.4 µs it
  loses to a d1 → d0 hop is below λ's bracket and is not worth re-ordering for (T7).

---

## 3. Predictive tokens/s/card model

### 3.1 The step (one sequence, B = 1, t query rows; every term integer in `proof/fleet.py`)
```
T_step(L, B, t)  = Σ_{layers} [ T_gemm + T_attn(L, B, t) ]  +  T_head  +  T_launch  +  T_x(rows)  +  T_draft(t)
T_gemm (dense)   = W_layer · 10 / 1746 ns                                   = 18 256 993 ns     [R_gemm, M]
T_gemm (MoE)     = W_attn · 10 / 1746  +  2·F + 3·D(rows)·T_slab            = 240 223 + 2 967 496 (serial) / 2 344 360 (pp)
T_attn           = max( KV, SM, MMA )                                       engines overlap as in the measured dense kernel
   KV            = kv_tok · L · B · 10 / G                                  kv_tok = 4096 (2048 int8)   [G: U]
   SM            = B · t · H_q · L · c_E · 10 / 3456                        [R_vec M, c_E: U]
   MMA           = B · 2 · H_kv · (L/16) · ⌈t·g/16⌉ · 15 / 8                [c_mma M; one kv-head per core]
T_head           = W_head · 10 / 1746                                       = 12 035 202 (dense) / 3 008 800 (MoE) ns
T_launch         = (n_L · launches_per_layer + 2) · 91 000                  = 65.70 ms (dense) / 18.01 ms (MoE)   [M; 0 if H6 shows pipelining]
T_x              = Σbw(rows) + 16 λ                                         §2
T_draft(t = k+1) = k · [ 10⁹·10/1746 + 201 MB·10/1746 + 121·91 000 + 513 KB·10/273 + 2λ ]   = 54.27 ms (k = 3; 21.24 if launches pipeline)
tokens per step  = B · τ(α, k),  τ(α, k) = Σ_{i=0..k} α^i  (1 at t = 1);  tokens/s/card = tokens per step / (4 · T_step)
```
Rows = B·t ≤ 16 always (T13: m ≥ 24 measured at 81 GB/s = 46 % of the flat rate). The per-layer attention
terms (`[F3-*-attn]`, ns, B = 1, t = 1):

| shape | L | KV (stream / gather3x) | softmax (native / poly) | MMA |
|---|---|---|---|---|
| dense | 4k | 96 089 / 288 268 | 6 068 / 24 272 | 7 680 |
| dense | 32k | 768 715 / 2 306 146 | 48 545 / 194 180 | 61 440 |
| dense | 128k | 3 074 862 / 9 224 586 | 194 180 / 776 722 | 245 760 |
| dense | 1M | 24 598 896 / 73 796 688 | 1 553 445 / 6 213 783 | 1 966 080 |
| MoE | 32k | 768 715 / 2 306 146 | 12 136 / 48 545 | 61 440 |
| MoE | 1M | 24 598 896 / 73 796 688 | 388 361 / 1 553 445 | 1 966 080 |

Softmax and MMA are 6–8 % of the KV stream at t = 1 on the stream branch: the attention step is a KV stream
with the vector and matrix units at ≤ 8 % occupancy — the "attention must stay a bounded fraction of the
GEMV step" target of PROBLEM-3 is met by the layout, not by a kernel trick (the fraction is KV/T_gemm:
4.2 % at 32k for dense, 24 % at 32k for MoE, §4).

### 3.2 The L × configuration table (primary branch: G stream, native exp, λ = 91 µs, launches serialised, MoE serial regime, uniform routing) — `[F3]`

| shape | L | config | feasible | T_step ms | W ms | KV ms | launch ms | bounce ms | draft ms | tokens/step | **tok/s/card** | binding |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense | 4k | B=1 t=1 | yes | 2281.60 | 2202.87 | 11.53 | 65.70 | 1.49 | 0.00 | 1.000 | **0.109** | W |
| dense | 4k | spec k=3 α=0.7 | yes | 2336.00 | 2202.87 | 11.53 | 65.70 | 1.62 | 54.27 | 2.533 | 0.271 | W |
| dense | 4k | B=16 t=1 | yes | 2455.18 | 2202.87 | 184.49 | 65.70 | 2.11 | 0.00 | 16.000 | 1.629 | W |
| dense | 32k | B=1 t=1 | yes | 2362.31 | 2202.87 | 92.24 | 65.70 | 1.49 | 0.00 | 1.000 | **0.105** | W |
| dense | 32k | spec k=3 α=0.7 | yes | 2416.71 | 2202.87 | 92.24 | 65.70 | 1.62 | 54.27 | 2.533 | 0.262 | W |
| dense | 32k | B=16 t=1 | yes | 3746.62 | 2202.87 | 1475.93 | 65.70 | 2.11 | 0.00 | 16.000 | 1.067 | W |
| dense | 128k | B=1 t=1 | yes | 2639.05 | 2202.87 | 368.98 | 65.70 | 1.49 | 0.00 | 1.000 | **0.094** | W |
| dense | 128k | spec k=3 α=0.7 | yes | 2693.45 | 2202.87 | 368.98 | 65.70 | 1.62 | 54.27 | 2.533 | 0.235 | W |
| dense | 128k | B=16 t=1 | **NO** | 8174.42 | 2202.87 | 5903.73 | 65.70 | 2.11 | 0.00 | 16.000 | – | MEM |
| dense | 1M | B=1 t=1, f16 KV | **NO** | 5221.94 | 2202.87 | 2951.86 | 65.70 | 1.49 | 0.00 | 1.000 | – | MEM |
| dense | 1M | B=1 t=1, **KV-int8** | yes | 3746.00 | 2202.87 | 1475.93 | 65.70 | 1.49 | 0.00 | 1.000 | **0.066** | W |
| dense | 1M | spec k=3 α=0.7, f16 KV | **NO** | 5276.34 | 2202.87 | 2951.86 | 65.70 | 1.62 | 54.27 | 2.533 | – | MEM |
| dense | 1M | spec k=3 α=0.7, KV-int8 | yes | 3800.40 | 2202.87 | 1475.93 | 65.70 | 1.62 | 54.27 | 2.533 | 0.166 | W |
| dense | 1M | B=16 t=1 | **NO** | 49500.57 | 2202.87 | 47229.88 | 65.70 | 2.11 | 0.00 | 16.000 | – | MEM |
| MoE | 4k | B=1 t=1 | yes | 115.01 | 92.82 | 2.69 | 18.01 | 1.48 | 0.00 | 1.000 | **2.173** | W |
| MoE | 4k | spec k=3 α=0.7 | yes | 417.28 | 340.75 | 2.69 | 18.01 | 1.55 | 54.27 | 2.533 | 1.517 | W |
| MoE | 4k | B=16 t=1 | yes | 1395.36 | 1332.45 | 43.04 | 18.01 | 1.84 | 0.00 | 16.000 | 2.866 | W |
| MoE | 32k | B=1 t=1 | yes | 133.84 | 92.82 | 21.52 | 18.01 | 1.48 | 0.00 | 1.000 | **1.867** | W |
| MoE | 32k | spec k=3 α=0.7 | yes | 436.12 | 340.75 | 21.52 | 18.01 | 1.55 | 54.27 | 2.533 | 1.451 | W |
| MoE | 32k | B=16 t=1 | yes | 1696.70 | 1332.45 | 344.38 | 18.01 | 1.84 | 0.00 | 16.000 | 2.357 | W |
| MoE | 128k | B=1 t=1 | yes | 198.41 | 92.82 | 86.09 | 18.01 | 1.48 | 0.00 | 1.000 | **1.259** | W |
| MoE | 128k | spec k=3 α=0.7 | yes | 500.69 | 340.75 | 86.09 | 18.01 | 1.55 | 54.27 | 2.533 | 1.264 | W |
| MoE | 128k | B=16 t=1 | **NO** | 2729.85 | 1332.45 | 1377.53 | 18.01 | 1.84 | 0.00 | 16.000 | – | MEM |
| MoE | 1M | B=1 t=1 | yes | 801.09 | 92.82 | 688.76 | 18.01 | 1.48 | 0.00 | 1.000 | **0.312** | KV |
| MoE | 1M | spec k=3 α=0.7 | yes | 1103.36 | 340.75 | 688.76 | 18.01 | 1.55 | 54.27 | 2.533 | 0.573 | KV |
| MoE | 1M | B=16 t=1 | **NO** | 12372.62 | 1332.45 | 11020.30 | 18.01 | 1.84 | 0.00 | 16.000 | – | MEM |

W = all weight streams (layers + lm_head; for MoE attention GEMMs + active experts). "binding" = the largest
additive term. The infeasible rows are printed for the arithmetic only (what the time would be if the memory
existed). The 40 %-scored cells are the bold t = 1 rows at 32k: **dense 0.105, MoE 1.867 tokens/s/card**;
the configuration the plan actually runs at 32k is dense with spec decode (0.262) and MoE at t = 1 (1.867).

### 3.3 Branches at L = 32k, B = 1, t = 1 (`[F3b]`) — one toggle at a time
| branch | dense ms → tok/s/card | MoE ms → tok/s/card |
|---|---|---|
| **primary** | 2362.31 → **0.105** | 133.84 → **1.867** |
| G = gather3x (KV 3× slower) | 2546.81 → 0.098 | 176.89 → 1.413 |
| c_E = poly (no exp instruction) | 2362.31 → 0.105 (softmax still < KV) | 133.84 → 1.867 |
| λ = 10 µs / 500 µs | 2361.02 → 0.105 / 2368.86 → 0.105 | 132.55 → 1.886 / 140.39 → 1.780 |
| launches pipelined (H6) | 2296.61 → 0.108 | 115.82 → 2.158 |
| MoE ping-pong regime (DESIGN-2 E13) | – | 116.39 → 2.147 |
| routing Zipf(1.5) at t = 1 | – | 133.84 → 1.867 (D(1) = 8 under every family) |
| **pessimistic** (gather3x + poly + λ 500) | 2553.35 → 0.097 | 183.43 → 1.362 |
| **optimistic** (λ 10 + launches pipelined + MoE pp) | 2295.32 → 0.108 | 97.08 → 2.575 |

The dense prediction is bracketed within −8 % / +3 % by every unmeasured quantity of the model; the MoE
prediction within −27 % / +38 % (the KV-stream branch and the two kernel-regime branches are each worth
15–25 % because MoE streams 30× fewer weight bytes per token than dense, so everything else is visible).

### 3.4 MoE at B = 16 by routing family (`[F3c]`; D(16) from DESIGN-2's generator)
| family | D(16) | T_step 32k | W | KV | tok/s/card 32k | 1M |
|---|---|---|---|---|---|---|
| uniform | 128 | 1696.70 ms | 1332.45 | 344.38 | 2.357 | MEM (KV 11.0 s if it fit) |
| Zipf(1.0) | 68 | 1076.88 | 712.63 | 344.38 | 3.714 | MEM |
| Zipf(1.5) | 45 | 839.29 | 475.04 | 344.38 | 4.765 | MEM |

Batching sequences on a MoE die amortises the attention GEMMs, lm_head and launch floor but not the expert
stream under uniform routing (D = 8·rows): the lever is routing overlap, exactly DESIGN-2 §5.4's "tokens/s
scale with t/D(t)". H9 (host-side routing histogram) decides which row applies.

---

## 4. Regime map and crossover theorems

### 4.1 Binding constraint per (shape, L, rows) — `[F4-regime]` (primary branch; share of the step in brackets)
| shape | L | rows = 1 (t = 1) | rows = 4 (verify, k = 3) | rows = 16 (B = 16, t = 1) |
|---|---|---|---|---|
| dense | 4k | W (96.5 %) | W (94.3 %) | W (89.7 %) |
| dense | 32k | W (93.3 %) | W (91.2 %) | W (58.8 %) — KV 39 % |
| dense | 128k | W (83.5 %) | W (81.8 %) | **MEM** (L_max(16) = 34 453) |
| dense | 1M | **MEM** f16 → W (58.8 %) with KV-int8, KV 39 % | **MEM** → W with KV-int8 | **MEM** |
| MoE | 4k | W (80.7 %) — launch 15.7 % | W (81.7 %) | W (95.5 %) |
| MoE | 32k | W (69.4 %) — KV 16 %, launch 13.5 % | W (78.1 %) | W (78.5 %) — KV 20 % |
| MoE | 128k | W (46.8 %) — KV 43.4 % | W (68.1 %) | **MEM** (L_max(16) = 120 363) |
| MoE | 1M | **KV (86.0 %)** | KV (62.4 %) | **MEM** |

Host bounce is nowhere above 1.1 %; softmax is nowhere binding at rows ≤ 4 on the native branch; "imbalance"
does not exist at Π = 1 (T1). The two regime changes inside the table are MoE's KV crossover between 128k
and 1M and dense's memory wall between 551k and 1M.

### 4.2 Crossover derivations (the Lean targets; all integers from `proof/fleet.py`)
**T5 — KV-bandwidth crossover.** Per layer, KV binds iff kv_tok·L·B·10/G ≥ T_w(rows), i.e.
L ≥ L* = ⌈T_w · G / (10 · kv_tok · B)⌉ (`[F4-*-Lkv-*]`):

| shape | G branch | T_w per layer (ns) | L* at B = 1 | B = 4 | B = 16 |
|---|---|---|---|---|---|
| dense | stream 174.6 | 18 256 993 | **778 240** (= W_layer / 4096 exactly, since W_layer = 778 240 · 4096) | 194 560 | 48 640 |
| dense | gather3x 58.2 | 18 256 993 | 259 414 | 64 854 | 16 214 |
| dense, KV-int8 | stream | 18 256 993 | 1 556 480 | – | – |
| MoE serial | stream | 3 207 719 | **136 736** | 34 184 | 8 546 |
| MoE ping-pong | stream | 2 584 583 | 110 173 | – | – |
| MoE serial | gather3x | 3 207 719 | 45 579 | 11 395 | 2 849 |

So at B = 1 dense is weights-bound at every feasible L on the stream branch (L* > L_max = 551 253 with f16 KV;
with KV-int8 L* = 1.56M > 1M) and KV-bound only on the gather3x branch beyond 259k; MoE is weights-bound at
4k/32k and KV-bound at 1M under every branch (128k sits 4 % under L* on the serial-stream branch and above it
on every other). Batching divides L* by B.

**T6 — softmax crossover is L-independent.** SM ≥ KV ⟺ B·t·H_q·c_E·10/3456 ≥ kv_tok·B·10/G: L and B cancel,
leaving t ≥ t* = ⌈kv_tok · 3456 / (G · H_q · c_E)⌉ (`[F4-*-tsm-*]`):

| shape | native (c_E = 4) stream / gather3x | poly (c_E = 16) stream / gather3x | KV-int8 native / poly (stream) |
|---|---|---|---|
| dense (H_q = 128) | 16 / 48 | **4** / 12 | 8 / 2 |
| MoE (H_q = 32) | 64 / 191 | 16 / 48 | – |

Consequence: a dense verify batch of t = 4 is softmax-bound **iff** there is no exp instruction (poly) and the
KV stream runs at the stream rate — and then only marginally (SM 776 722 vs KV 768 715 ns per layer at 32k:
+1 %); with KV-int8 the poly branch binds already at t = 2. The E-exp measurement (PROBLEM-3) therefore matters
for dense spec decode and for nothing else in this plan.

**T-MMA — matrix-unit attention bound.** Calls per layer = B·2·H_kv·(L/16)·⌈t·g/16⌉; per-layer MMA time /
KV time = 8.0 % (dense t = 1), 32.0 % (t = 4), **127.9 % (t = 16, a single-sequence 16-row verify: MMA-bound)**;
MoE (g = 4): 8.0 % / 8.0 % / 32.0 % (`[F4-*-mma-*]`). The plan never runs a single sequence at t > 8 (§6).

**T4 — memory boundary** (§1.7): L_max values; dense f16 1M infeasible by 515.3 − 282.3 = 233.0 GB fleet-wide.

**T8 — bounce boundary** (§2.2): λ ≥ 835 µs (MoE) / 14.8 ms (dense) for a 10 % share.

**T2 — the layer-split ceiling.** For any partition under Π = 1, T_step ≥ Σ_layers T_gemm = bytes streamed per
token / R_gemm: tokens/s ≤ 174.6 / 384.6 GB = 0.454 fleet-wide (dense), 0.113 per card. No layer→die map, no
die count, no exchange schedule beats it; the "+2 % at 2 dies" measurement is this theorem observed.

---

## 5. Sensitivity / what-if theorems (each a bound, `[F5]`, L = 32k, B = 1, t = 1, primary branch)

| what-if | bound | dense | MoE |
|---|---|---|---|
| **P2P link at any rate X** | saving ≤ T_x (the whole exchange) — at Π = 1 nothing else is on the link | ≤ 1.497 ms = **0.06 %** | ≤ 1.480 ms = **1.1 %** |
| **D2D 10.7 → 50 GB/s** | per-token traffic is 0 B (KV never moves) → 0 %; only a re-partition move changes: one die's KV at 128k (dense 8.0 GB, MoE 2.1 GB) | 753 → 161 ms per move | 201 → 43 ms |
| **tensor-split worked** (8 dies stream each layer concurrently, 2 host all-reduces per layer of a rows × d f32 partial: per card the trunk carries both dies' partials out and both results in + 2λ = 191 µs (dense d = 16384) / 184 µs (MoE)) | T_TS = Σ(W + KV)/8 + T_launch + 2·n_L·T_red | 398.52 ms = 273.85 + 11.53 + 65.70 + 45.93 → **0.627 tok/s/card (5.9×)**; λ = 10 µs: 359.64; launches pipelined: 332.82 | 43.02 ms = 11.61 + 2.69 + 18.01 + 10.32 → **5.810 (3.1×)**, launch-floor-bound (42 %); λ 10: 33.95; pipelined: 25.00 |
| **pipelined sequences Π = 8** (the runtime keeps every die busy on a different sequence; per-sequence latency unchanged) | fleet tokens/s = 1 / max_pos block(pos); block = n_pos·(T_gemm + T_attn + launches) + extras + its two bounce halves | blocks 293.66–305.99 ms (pos 7 carries lm_head) → 3.268 fleet = **0.817/card (7.7×)** | blocks 14.02 (3-layer) / 18.63 ms (4-layer) → 53.66 fleet = **13.414/card (7.1×)**; a sub-layer split (7 units per die) would reach 8× |
| **tensor-split + P2P** | the reductions leave the host: T_red → 8 · rows·d·4 B / X + λ_p2p; at X = 50 GB/s, λ_p2p = 10 µs: 20 µs (dense) / 13 µs (MoE) per reduction instead of 191 / 184 (`[F5-*-tsplit-p2p]`) | 357.50 ms → 0.699 (6.6×) | 33.41 ms → 7.482 (4.0×), launch-bound (54 %) |

Reading: on this runtime the only upgrade that pays is **pipelining independent sequences** (×7–8 throughput,
zero link bandwidth, zero kernel change — the exchange table of §2 at 8 tokens in flight uses 0.2 % of a
trunk). Tensor-split would be the latency lever (one sequence 5.9× faster for dense) but it needs the
runtime to stop faulting on split ops **and** converts the launch floor into the MoE wall (18 of 43 ms).
P2P is worth less than the measurement noise of this plan unless tensor-split exists too. D2D is irrelevant
to steady-state decode.

---

## 6. Draft model placement and the verify-batch schedule

### 6.1 Cost of a draft token (`[F6-draft]`)
| component | value | origin |
|---|---|---|
| draft weights 1 GB at R_gemm | 5 727 µs | M |
| draft window KV 201 MB at R_gemm | 1 153 µs | M + A (4k window) |
| 121 launches × 91 µs | 11 011 µs | M (0 if H6 shows pipelining) |
| logits D2H 513 KB at 27.3 + 2λ | 19 µs + 182 µs | M + A |
| **per draft token** | **18.1 ms** (7.1 ms pipelined) | |
| **per verify step, k = 3** | **54.27 ms** (21.24 pipelined) | |

The launch floor is 61 % of the draft's cost: a draft model on this part is launch-bound, not bandwidth-bound,
so its layer count matters more than its byte count (a 0.5 GB draft with the same 24 layers saves 2.9 ms of
18.1; a 12-layer 1 GB draft saves 5.5).

### 6.2 Placement
- **Dense: chain position 1 (c0.d0)**, 49.0 GB with the draft; the binding die for L_max is position 0 (the
  embedding table, 49.9 GB), so the draft costs zero context (`[F1-dense-draftfree]` = 551 253). Its logits
  leave on a 27.3 GB/s link; its ids go to position 0 over 13.9 GB/s (4 B). At Π = 1 the draft runs while
  the whole chain is idle (the three draft steps precede the verify step), so there is **no contention**: its
  cost is purely additive (54.27 ms). At Π = 8 the draft die loses 6.9 ms of DDR time per draft token to a
  running block (`[F6-contention]`) — then the draft belongs on the die with the smallest block (position 1
  is 293.76 ms like every middle die; nothing to gain, and the sub-layer-balanced MoE layout would give it a
  3-layer die).
- **MoE: reserved on position 7 (c3.d0, 40.5 GB with it), not deployed by default** (T12 below).
- The draft's own KV: a 4k sliding window (A — a model-quality choice outside HW-MAP; a full-context draft
  KV would cost 49 152 B per token = 10 % of the main model's, and 51.5 GB at 1M, which no die has).

### 6.3 Verify-batch schedule and the spec-decode theorem
Per verify step: 3 draft steps on the draft die (ids bounce to the host each), then one chain pass with
rows = t = 4 (the four candidate positions as 4 rows of every GEMM: free under the flat m-curve; the KV stream
is read once; softmax ×4; MMA ×4 fragments = 32 % of the KV time, T-MMA), logits for 4 positions D2H (75 µs),
host acceptance test, ids back. Tokens per step τ(α, k) = Σ_{i=0..k} α^i (`[F6-tau]`): α = 0.5 / 0.7 / 0.9 →
1.875 / 2.533 / 3.439 at k = 3.

| shape, L = 32k | t = 1 | spec k = 3: α 0.5 / 0.7 / 0.9 | best k at α = 0.7 (rows = k+1 ≤ 16) |
|---|---|---|---|
| dense | 0.105 | 0.193 / **0.262** / 0.355 (1.8× / 2.4× / 3.3×) | k = 7: 0.315 (`[F6-dense-k7]`; 0.571 at α = 0.9) |
| MoE, uniform routing | 1.867 | 1.074 / **1.451** / 1.971 (0.5× / 0.7× / 1.0×) | k = 1: 1.811 — still a loss |
| MoE, Zipf(1.5) routing | 1.867 | – / 2.028 / – (1.09×) | – |

**T12 (spec decode on MoE).** Under uniform routing D(t) = min(8t, 256), so the expert stream of a verify
step is (k+1)× that of a decode step: T(k+1) ≥ (k+1)·W_exp(1) + (everything else), while tokens per step
τ(α, k) < k+1 for every α < 1. Hence tokens/s(spec) < tokens/s(t = 1) whenever the expert stream dominates
— at 32k the break-even is τ(α, 3) ≥ 3.258 (`[F6-moe-uniform-t4]`), i.e. α ≥ 0.87; under Zipf(1.5) (D(4) = 20)
the break-even is τ ≥ 2.332, α ≥ 0.65. On dense the verify rows are free (W is flat in rows), so spec decode
is a pure gain: ×2.4 at α = 0.7 and ×3.0 with k = 7.

**Does spec decode change the partition?** Dense: no — 1.2 GB on a non-binding die, same boundaries, same
KV policy, L_max unchanged; the only schedule change is that each step carries 4 rows (bounce bytes ×4,
still ≤ 0.07 %). MoE: it changes the *decision*, not the partition: spec decode is off unless H9 measures
routing skew at Zipf(1.5)-class or better and the fleet-measured α clears 0.65; the reservation on position 7
costs 1.2 GB of a 42.7 GB die. The draft's own layers never contend with the main model's dies at Π = 1.

---

## 7. Rollout plan: 1 card → 2 cards → 4 cards without re-partitioning

**T15 (block invariance).** block(pos) depends only on (layers on pos, extras on pos, L): the per-die blocks
of the final layout are therefore measurable on a single card holding chain positions 0 and 1 with exactly
the final blocks, and every later stage adds positions without changing the ones already proven.

| stage | positions | dense layers | MoE layers | what it proves | predicted step at 4k / 32k / 128k (`[F7]`) |
|---|---|---|---|---|---|
| **1 card** (c0.d1 → c0.d0) | 0, 1 | 0–29 (15 + 15, embed on pos 0, draft on pos 1) | 0–6 (4 + 3) | layer-split through the runtime; the d1 → d0 hop (hop 0) and the d0 → host logits path; KV growth to 128k+ on a die holding its final 47.8–49.9 GB of weights (`[F8-H5]`: 61 440 B/token, 8.0 GB at 128k, room to 551k); the per-block timings that T15 extrapolates | dense 567.24 / 587.42 / 656.61 ms; MoE 27.85 / 32.56 / 48.71 ms |
| **2 cards** | 0–3 | 0–59 | 0–13 | the inter-card hop (hop 1: d0 → d1', H2D at 13.9, the slowest), trunk sharing (H2), two boundaries of each type | dense 1134.59 / 1174.95 / 1313.31; MoE 55.81 / 65.22 / 97.51 |
| **4 cards** | 0–7 | all | all | the full chain; lm_head on pos 7 | dense 2281.51 / 2362.22 / 2638.96; MoE 114.92 / 133.75 / 198.32 |

Re-partition steps: **none for the layer blocks** (the 15-layer / 4-3 blocks are final from stage 1). The
extras move: at stages 1 and 2 the chain ends on position 1 / 3, which temporarily hosts the stage's logits
exit (the prefix model has no lm_head: correctness is judged per layer, below); at stage 3 lm_head loads on
position 7. The draft is loaded at its final position from stage 1. KV of a prefix stage is not carried
forward (a stage's context is regenerated); if a live context must survive a stage change, moving one die's
KV costs 753 ms (dense, 128k) / 201 ms (MoE) at the measured 10.7 GB/s D2D rate (`[F5-*-d2d]`).

Correctness at every stage without a whole-model host reference (386.7 GB of int8 on a host is not
assumed): teacher-forced tokens, and a **per-layer host oracle** — the host holds one layer's weights at a time
(3.2 GB dense / 12.9 GB MoE), recomputes layer ℓ's output from the die's recorded input (f32), and compares
(relerr ≤ 10⁻³ class, as DESIGN.md E10); differencing: the same layer with a second weight set must change
the output. MoE stage 1 additionally checks per-core chunk counts = D × 32 per slab (DESIGN-2 E15) through the
runtime's profiler.

Scaling arithmetic the stages verify: T_full = Σ_pos block(pos) + bounces; stage 1's two blocks predict
the eight of stage 3 to within the lm_head term (12.0 ms dense / 3.0 MoE) and six more latency pairs
(12 λ ≈ 1.1 ms): the 4-card prediction is **4 × (stage-1 step) + 12λ + T_head** = 4 × 587.42 + 1.09 + 12.04 =
2362.8 ms at 32k against the direct 2362.31 (the 0.5 ms residual is the stage-1 chain ends — logits exit and
id entry — counted four times instead of once).

---

## 8. Experiment ladder — host only (the runtime API and the host clock; no custom NPU kernel)

Harness rules: every device buffer is pre-filled with a sentinel and every transfer is **content-checked** on
the receiving side (a transfer that "completes" without changing the destination is the host-side analogue
of errata #1); every timing is the median of ≥ 100 reps with the full distribution kept; pass/fail is never
timing alone. Expected values are `[F8-*]`.

| # | settles | setup | observable failure | decides |
|---|---|---|---|---|
| **H0** | host inventory: RAM, NUMA, pinned-memory limit, PCIe topology of the 4 cards, aggregate host DMA | allocate pinned buffers up to the limit; map each card's root port; 4-card concurrent H2D of 1 GiB each | aggregate < 4 × 27.6 = 110.4 GB/s → the cards share a host-side bottleneck (load and any host-paging escape are then slower than §1.6); pinned limit < 2 × 64 MiB → the load pipeline's chunking changes | load time; whether host paging is even on the table |
| **H1** | per-die link curves T(n) = λ + n·10/R for n ∈ {4 KiB, 64 KiB, 1 MiB, 64 MiB}, both directions, all 8 dies | pattern A then pattern B through the same device buffer; read back through the opposite direction; expected bandwidth terms: 64 KiB → 2.4 (d0) / 4.7 (d1) µs H2D, 2.4 / 3.4 D2H; 64 MiB → 2 431 / 4 828 and 2 458 / 3 532 µs | readback unchanged (silent no-op); R below the HW-MAP figures (27.6/27.3/13.9/19.0) by > 10 %; λ intercept is **the λ branch of §2** | λ (primary 91 µs or not), the per-hop table |
| **H2** | whether die 0's link is a shared trunk | concurrent H2D (and D2H) to both dies of one card, 64 MiB each, content-checked | sum 41.5 GB/s (independent) vs 27.6 (trunk); either die's checksum wrong under concurrency = a DMA ordering bug | stage-2 hop costs; the Π = 8 trunk model; load time |
| **H3** | host-bounce round trip λ_rt and its behaviour under contention | for all 56 ordered die pairs: D2H a counter-pattern buffer of {8, 32, 128, 512 KiB, 2 MiB} → host increments it → H2D to the other die; the receiver's buffer must equal sender + 1 in every rep; then repeat with a concurrent bulk H2D stream on the same card chunked at 64 KiB / 1 MiB / 16 MiB | stale receiver buffer (bounce re-ordered behind bulk); wait beyond C/R + λ_rt (5 µs / 75 µs / 1.2 ms on the 13.9 link, T-queue) | §2.3's chunking rule; λ |
| **H4** | **Π — does the runtime pipeline independent sequences through a layer-split chain?** (the §10 measurement) | a model that fits one die, split over 2 dies by the runtime; submit N = 1, 2, 4 independent sequences; log per-token completion timestamps per sequence; sample the card power sensor (idle 41 W, loaded 141 W) at 10 Hz | throughput(N) flat in N → Π = 1 (the measured "dies alternate"); ∝ N up to 2 → pipelined; outputs of any sequence differ from its single-sequence run → cross-talk bug; power never above one-die load while two are "busy" → the runtime serialises | 7.7× / 7.1× or nothing; the Π = 8 layout refinements of §5 |
| **H5** | KV growth trace: the runtime allocator's real bytes per token per die | the stage-1 model; query per-die free memory every 1k tokens to 128k and beyond; expected slope 61 440 B/token (dense 15-layer die), 16 384 / 12 288 (MoE 4-/3-layer die), 8.0 GB at 128k | slope above expected (allocator overhead → L_max shrinks by 16 276 tokens per GB), steps (preallocation granularity), non-monotone free memory (fragmentation) | L_max, T4's premise, whether the preallocated-slab policy of §1.3 is what the runtime does |
| **H6** | launch-floor serialisation through the runtime (DESIGN.md E0 from the host) | N = 1, 10, 100 queued tiny ops, each writing its index to slot i | missing/duplicate slots; T(N) ≈ N × 91 µs serialised vs ≈ 91 + N × small pipelined | the launch branch: 65.7 ms (dense) / 18.0 ms (MoE) per token, 11.0 ms per draft token |
| **H7** | load path: int4 → int8 expansion throughput and end-to-end load time | expand per 64 KiB chunk into pinned buffers, stream per die; per-die checksum over the loaded bytes vs the host's checksum of the expanded chunk stream; differencing: layer A then layer B into the same region must change the checksum | checksum mismatch (expansion or DMA error); load slower than 3.5 s link-bound (386.7 GB) by more than the expansion's own cost | §1.6; whether the expansion must be cached on disk |
| **H8** | per-die overhead after load (the 2 GiB assumption) | free memory reported by the runtime after loading a die's final block, minus the known weight bytes | overhead > 3.85 GiB → the dense 1M KV-int8 layout (84.3 GB) no longer fits; > 2 GiB → L_max falls per T4 | T3/T4 margins |
| **H9** | routing skew D(t) (host-side; the router is 2 MiB per layer) and — fleet-only — the draft's α | run the 28 routers on the host over a text sample of ≥ 10⁵ tokens; histogram of distinct experts per 4- and 16-token group; compare with DESIGN-2's generator columns | D(4) ≥ 30 → uniform rows of §3.4 and T12's loss apply; D(4) ≤ 20 → the Zipf(1.5) rows | spec decode on/off for MoE; which B = 16 row to expect |

Order: H0, H1, H2, H3, H6, H8, H5, H4, H7, H9. H1–H3 settle λ (the only exchange unknown) in an afternoon;
H4 is the one whose answer rewrites §5 from a what-if into the plan.

---

## 9. Risk register

| risk | trigger / evidence | impact (numbers from `proof/fleet.py`) | fallback |
|---|---|---|---|
| **Memory infeasibility at 1M (dense)** | T3: f16 KV = 120 layers × 4 096 B × 2²⁰ = 515.3 GB against 282.3 GB of fleet room after weights (T4) — infeasible by 233 GB, on every die (114.4–116.5 GB) | no dense 1M with f16 KV on 8 dies, under any partition (the weights alone leave 282.3 GB) | **KV-int8** (257.6 GB; 84.3 of 86 GB on positions 0 and 7, T3') at the i8×i8 attention route; or a host-paged KV prefix: 233 GB per token through 4 trunks at 27.6 = 2.1 s per card per token if perfectly overlapped — T_step ≥ max(chain, X_card/R_h2d) (T10) → ≥ 5.2 s, 0.048 tokens/s/card, and ≥ 233 GB of host RAM (H0); or fewer layers resident (host-streamed layers cost 6.3× their DDR time) |
| KV-int8 is the only dense 1M layout and it has 1.7 GB of margin on two dies | H8 (runtime overhead), H5 (allocator slope) | overhead > 3.85 GiB kills it; every GB above 2 GiB costs 16 276 tokens of L_max (T4) | move the embedding table to the host (a lookup; 32 KiB per token over the id link) → position 0 drops to 82.2 GB, but position 7 (lm_head) stays at 84.3: the margin grows only if lm_head also moves to the host (2.1 G MACs per token ≈ 0.1 s of CPU, 3 % of the 1M step) |
| KV-int8 numerics (i8 K, V and P) | fleet-only: relerr on attention outputs vs an f16 host reference on the stage-1 card | accuracy, not rate | keep f16 K and int8 V (386.4 GB of KV → still infeasible by 104 GB); or accept L_max = 551k |
| **Host bounce becomes the serial bottleneck** | H1/H3 λ; T8 | bounce = 10 % of the MoE step iff λ ≥ 835 µs; 50 % iff ≥ 4.18 ms; dense 14.8 / 73.8 ms. At λ = 500 µs the MoE step is 140.39 ms (−5 %) | nothing structural is left to remove (7 hops is the minimum for 8 dies); the lever is fewer dies (5 dies: 4 hops, 10 λ) at the cost of context: dense L_max on 5 dies ≈ 53k |
| **Layer-split's "+2 %" ceiling** (T2) | measured: dies alternate | single-stream tokens/s ≤ 174.6 GB/s ÷ bytes per token no matter how many dies: 0.113/card dense, 3.4/card MoE; the fleet's 1.4 TB/s is unreachable by any Π = 1 plan | batching sequences (B = 16: 10× dense throughput at 32k, memory-limited to 34k), spec decode (2.4× dense), or the Π = 8 runtime capability (H4, 7–8×) |
| Launch floor | H6; measured 91 µs per launch | 13.5 % of the MoE step (18.0 of 133.8 ms), 2.8 % of dense, 61 % of a draft token; 42 % of the tensor-split what-if | fuse launches (norm/rope into GEMM epilogues: 6 → 4 per dense layer saves 21.9 ms per token); H6 may show pipelining (then −18.0 ms MoE, −33 ms per verify step) |
| MoE kernel stays in the serial regime | DESIGN-2 E13 | 133.84 ms (serial) vs 116.39 (ping-pong): −13 % | ship the serial number (it is the anchored one) |
| KV gather 3× slower than stream (attention kernel unbuilt) | PROBLEM-3 E-gather | −7 % dense at 32k; −24 % MoE at 32k; MoE 1M 0.312 → 0.114 (`[F9-moe-1M-gather3x]`); L*_KV falls to 259k (dense) / 45.6k (MoE) | the per-core head-slab layout of §1.3 makes the read sequential; if the realised rate is still low, the attention kernel, not the plan, is the fix |
| No exp instruction (poly softmax) | PROBLEM-3 E-exp | only dense verify batches at t ≥ 4 (t* = 4, T6): +1 % per attention layer | reduce k to 2 for dense (t* not reached) |
| Rows cliff | measured m ≥ 24 at 81 GB/s (46 % of flat) | any config with B·t > 16 halves its weight rate | T13: B·t ≤ 16 enforced by the scheduler (B = 16 excludes spec; spec k = 3 allows B ≤ 4) |
| Dense kernel falls back to the serial regime (138.9) | per-launch regression (HW-MAP: multi-strip wedge unresolved for m ≥ 24 only) | 2362 → 2928.50 ms, 0.085/card (`[F9-dense-serial]`) | keep rows ≤ 16; the direct-load path is the production path |
| Runtime overhead / allocator fragmentation | H5, H8 | L_max −16 276 tokens per GB (dense), −61 035 (MoE) | preallocated slabs (§1.3) if the runtime exposes them |
| Trunk sharing (die 1 transits die 0) | H2 | at Π = 1 nothing (utilisation < 0.02 %); load 3.5 s vs 2.3 s; Π = 8 bounces still ≤ 0.2 % of a trunk | none needed |
| MoE expert imbalance across dies (4 vs 3 layers) | layout | 0 at Π = 1 (T1); −12.5 % at Π = 8 | sub-layer split (7 units per die) if the runtime allows placing attention and expert blocks separately (H4) |
| Spec decode on MoE is a loss | T12; H9 routing | 1.451 vs 1.867 at α = 0.7 under uniform routing | off by default; on only if H9 shows Zipf(1.5)-class skew and α ≥ 0.65 |
| Draft launch-bound | H6 | 54.27 ms per verify step (2.3 % of dense, 41 % of MoE) | fewer draft layers; pipelined launches → 21.24 ms |
| Host RAM for the int4 source and (paging escape) KV | H0 | 193.3 GB (dense source) must be host-resident or disk-streamed at load; the paging escape needs ≥ 233 GB more | stream the source from disk through the expansion pipeline (load time becomes disk-bound) |
| Thermal | measured 141 W sustained all-core per card, 150 W class, no throttle | Π = 1: one die streams at a time (one card at ≤ 141 W, three near 41 W idle); Π = 8: every card at the measured sustained load | none |
| Host sampling path | logits 513 KB per step (2 MB at t = 4, 8.2 MB at B = 16) at 27.3 GB/s = 19 / 75 / 301 µs + λ | ≤ 0.3 % | on-device argmax/top-k if the runtime exposes it (removes one λ and the logits bytes) |

---

## 10. The single measurement that most changes the plan

**H4 — whether the serving runtime pipelines independent sequences through the layer-split chain (Π > 1).**
Every other unknown moves a cell by at most 1.3× (G: 0.93× / 0.76×; MoE regime: 1.15×; launch pipelining:
1.03× / 1.16×; λ across its whole bracket: 1.0× / 0.95×; routing skew: 1× at t = 1). Π = 8 moves every cell
by **7.7× (dense) / 7.1× (MoE)** at unchanged per-sequence latency, with zero extra link bandwidth (0.2 % of a
trunk) and no kernel change — and it rewrites the plan: the partition objective becomes the per-die block
time (balance MoE at the sub-layer level, 7 units per die; put lm_head and the draft on the lightest
blocks), the draft starts contending for DDR (6.9 ms per draft token), the exchange schedule gains a queue
model (8 bounces in flight per trunk), and the memory plan must hold 8 contexts (B = 8 at L = 32k: dense
L_max(8) = 68 906 — still feasible, so the throughput plan at 32k is Π = 8 × B = 1, not B = 16). If H4 says
Π = 1 (the measured "dies alternate"), the plan is exactly §1–§3 and the fleet's aggregate bandwidth is
reachable only by batching (memory-limited) or by a runtime that stops faulting on tensor-split (§5). It is
a host-only experiment: two sequences, per-token timestamps, and the card power sensor as the independent
witness that both dies of a card are streaming at once.

---

## Appendix A — claim ledger (for the proof session: `proof/fleet.py` labels and proposed theorem names)

Status: M = HW-MAP input; D2 = DESIGN-2 derived input; D = derived here (theorem target, `decide`/`omega`
over Nat); A = assumption measured by the named host experiment; U = empirical branch.

| # | claim | value | status | fleet.py / theorem |
|---|---|---|---|---|
| 1 | dense resident int8 = 120 · 3 187 671 040 + 2 · 2 101 346 304 | 386 723 217 408 B | D | [F0-dense] F0_dense_bytes |
| 2 | MoE resident int8 = 28 · 12 926 844 928 + 2 · 525 336 576 | 363 002 331 136 B | D | [F0-moe] F0_moe_bytes |
| 3 | KV per token: 491 520 B (dense), 114 688 (MoE); at 2²⁰ tokens 515.3 / 120.2 GB | | D | [F0-kv1M] F0_kv |
| 4 | per-die totals at 4k: dense ≤ 52.3 GB, MoE ≤ 54.5 — all ≤ 86·10⁹ | feasible | D | [F10-mem-*-4k] T3_feasible_4k |
| 5 | dense 1M f16: every die ≥ 114.4 GB > 86 | infeasible | D | [F10-mem-dense-1M] T3_infeasible_1M_f16 |
| 6 | dense 1M KV-int8: max die 84.3 GB ≤ 86 | feasible | D | [F10-mem-dense-1M KV-i8] T3_feasible_1M_i8 |
| 7 | MoE 1M f16: max die 71.6 GB | feasible | D | [F10-mem-moe-1M] T3_feasible_moe_1M |
| 8 | L_max = min_pos ⌊room_pos / (n_pos·kv_tok·B)⌋: dense 551 253 / 137 813 / 34 453 (B = 1/4/16), int8 1 102 506; MoE 1 925 823 / 481 455 / 120 363 | | D | [F1-*-Lmax] T4_Lmax |
| 9 | ΔL_max per GB of overhead: 16 276 (dense), 61 035 (MoE) | | D | [F1-dLmax] T4_dLmax |
| 10 | minimum dies for either shape | 5 | D | [F1-*-Lmax] T4_min_dies |
| 11 | Σbw per token = 41 107 ns (dense r=1), 164 443 (r=4), 24 367 / 97 484 (MoE); 16 latencies | | D | [F2-*] T7_bw_sum |
| 12 | bandwidth sum is chain-order invariant; logits source 18.8 vs 27.0 µs | | D | [F2-order] T7_order_invariance |
| 13 | T_x(λ) at 10/91/500 µs: dense 201 / 1 497 / 8 041 µs; MoE 184 / 1 480 / 8 024 | | D (λ A) | [F2-*] T8_Tx |
| 14 | bounce ≥ 10 % of the 32k step iff λ ≥ 14 762 µs (dense) / 835 (MoE); 50 % iff 73 820 / 4 181 | | D | [F9-*-lambda] T8_threshold |
| 15 | per-card trunk bytes per token (dense r=1): 98 308 / 131 072 / 131 072 / 611 328 | | D | [F2-dense-rows1] T9_trunk |
| 16 | queueing bound behind bulk chunk C on the 13.9 link: 5 / 75 / 1 207 µs for 64 KiB / 1 MiB / 16 MiB | | D | [F8-H3] T_queue |
| 17 | per-layer times: dense GEMM 18 256 993 ns; MoE 240 223 + 2 967 496 (serial) / 2 344 360 (pp); heads 12 035 202 / 3 008 800; launches 546 000 / 637 000 | | D (D2) | [F3-*-layer] T1_layer |
| 18 | attention per layer (`[F3-*-attn]`): KV = 4096·L·10/G; SM = t·H_q·L·c_E·10/3456; MMA = 2·8·(L/16)·⌈t·g/16⌉·15/8 | table §3.1 | D (G, c_E U) | T1_attn |
| 19 | §3.2 table: 26 rows of T_step, components, tokens/s/card, binding | | D | [F3] T1_step_table |
| 20 | §3.3 branch table and brackets (dense −8 %/+3 %; MoE −27 %/+38 %) | | D | [F3b] T1_branches |
| 21 | MoE B = 16 by family: 2.357 / 3.714 / 4.765 at 32k | | D (D(16) U) | [F3c] T1_moe_families |
| 22 | L*_KV = ⌈T_w·G/(10·kv_tok·B)⌉: dense 778 240 (= W_layer/4096), 194 560, 48 640; gather3x 259 414; int8 1 556 480; MoE 136 736 / 34 184 / 8 546, pp 110 173, gather3x 45 579 | | D | [F4-*-Lkv-*] T5_Lstar_kv |
| 23 | t* = ⌈kv_tok·3456/(G·H_q·c_E)⌉, L-independent: dense 16 / 4 (native / poly), MoE 64 / 16; gather3x 48 / 12, 191 / 48; int8 8 / 2 | | D | [F4-*-tsm-*] T6_tstar_softmax |
| 24 | MMA share of KV time: dense 8.0 / 32.0 / 127.9 % at t = 1/4/16; MoE 8.0 / 8.0 / 32.0 | | D | [F4-*-mma-*] T_mma_share |
| 25 | regime map cells (§4.1) | | D | [F4-regime] T_regime |
| 26 | layer-split ceiling: tokens/s ≤ R_gemm / bytes per token = 0.454 fleet (dense) | | D | T2_ceiling |
| 27 | P2P saving ≤ T_x: 0.06 % / 1.1 % | | D | [F5-*-p2p] T9_p2p_bound |
| 28 | tensor-split: dense 398.52 ms (273.85 + 11.53 + 65.70 + 45.93), MoE 43.02 (11.61 + 2.69 + 18.01 + 10.32); per reduction 191 / 184 µs; with P2P 357.50 / 33.41 | | D | [F5-*-tsplit*] T10_tsplit |
| 29 | Π = 8: blocks 293.66–305.99 ms (dense), 14.02–18.63 (MoE); 1/max = 3.268 / 53.657 fleet tokens/s | | D | [F5-*-pipe] T11_pipeline |
| 30 | D2D: 0 B per token; KV move 753 → 161 ms (dense 128k), 201 → 43 (MoE) | | D | [F5-*-d2d] T_d2d |
| 31 | draft token 18.1 ms (5 727 + 1 153 + 11 011 + bounce); verify step 54.27 / 21.24 ms | | D (launch M, λ A) | [F6-draft] T14_draft |
| 32 | τ(α, k) = Σ α^i: 1.875 / 2.533 / 3.439 at k = 3 | | D | [F6-tau] T14_tau |
| 33 | spec on dense: 0.262 (k = 3), 0.315 (k = 7) at α = 0.7; on MoE uniform 1.451 < 1.867; break-even τ ≥ 3.258 (uniform) / 2.332 (Zipf 1.5) | | D (α A) | [F6-*] T12_spec_moe_loss |
| 34 | rollout: stage steps (§7 table); 4 × stage-1 + 12λ + T_head = 2362.8 vs 2362.31 ms | | D | [F7-*] T15_block_invariance |
| 35 | ladder expectations: link µs per size, trunk 41.5 vs 27.6, KV slopes 61 440 / 16 384 / 12 288 B per token, load 3.5 s | | D | [F8-*] T_ladder |
| 36 | rows cliff: 81/174.6 = 46.3 %; B·t ≤ 16 | | M/D | [F9-rows] T13_rows |
| 37 | dense serial fallback: 2928.50 ms → 0.085; MoE 1M gather3x: 2178.63 ms → 0.114 | | D | [F9-*] T_fallbacks |
| 38 | power: Π = 1 one card at ≤ 141 W; Π = 8 all at 141 < 150 | | M | [F9-power] — |
| 39 | A-fraction approximation: the measured 174.6 carries 1.5 % of A bytes; the dense down-projection (K = 53 248) streams 3.1 % → ≤ 0.4 % per layer, not modelled | | A (stated) | — |
