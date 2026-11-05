# ALTERNATIVES — pattern-matching the known solution families against the measured map (round 5)

Scope (PROMPT-5.md): take the solution families of acceleration engineering and match each against this device's
measured constraints and the four designs (DESIGN.md dense W8 GEMM at the measured 174.6; DESIGN-2.md MoE grouped
GEMM, 135.3 anchored to the serial-loader regime; DESIGN-3.md matrix-unit attention, 776 µs / 24.6 ms at 32k / 1M;
DESIGN-4.md fleet planner, 0.105 / 1.867 tokens/s/card at 32k), hunting for alternatives that beat, fuse or
dominate them. Everything derives from HW-MAP.md (f951a5c), ISA.md and the four designs' ledgered numbers; nothing
assumes a feature ISA.md does not list. Status tags: **M** measured (HW-MAP), **D** derived here by arithmetic
shown, **D2/D3/D4** a ledgered theorem of the named design used as input, **A** explicit assumption with the
experiment that measures it, **U** unmeasured and branched. Units: bytes binary, GB decimal, rates GB/s decimal,
times ns floored and quoted µs/ms round-half-up — the conventions of `proof/model.py`.

**Every number below is printed by `proof/alt.py`** (integer arithmetic; it imports `proof/fleet.py` and
`proof/attn.py` so that every "today" cell is the ledgered DESIGN-3/4 number and every alternative is the same cost
model with one term changed; label `[ALT-…]` in the text). Appendix A lists the claims in the established ledger
format with the theorem each one becomes.

## 0. What the pattern match found (the verdict in five lines)

1. **The fleet is serialization-bound, not bandwidth-bound** (DESIGN-4 T2: one die streams at a time, Π = 1). That
   inverts the kernel-level verdict on the dead W4 vector path: a weight path that is 2.06× *slower* per byte but
   halves memory lets the model fit on **4 dies**, and two 4-die instances double the fleet's useful bandwidth.
   With the smallest int4 share that closes the fit, MoE 32k goes **1.867 → 3.878 tokens/s/card (+107.7 %)** and
   dense 32k **0.105 → 0.156 (+48.5 %)** — robust to a 6.6× slower W4 path than measured (`[ALT-2-*]`).
2. **DESIGN-2 streams experts through the wrong path.** It is anchored to the S1-staged serial loader (135.3);
   the dense kernel's production path (DDR → L0B direct, 174.6 flat) carries the same per-core expert slices at
   **167.1 GB/s (A lift serialised) / 172.8 (overlapped)**, +23.5 % / +27.7 %, with every rate measured
   (`[ALT-1-*]`); fleet MoE 32k +13.4 %.
3. **The 91 µs launch floor is a megakernel problem, not a runtime problem.** One persistent launch per layer with
   a DDR-flag cross-core sync pays whenever a sync costs ≤ 109 µs (MoE) / 114 µs (dense) — a DDR round trip is µs
   class: MoE 32k +12.5 %, the draft token 18.1 → 9.3 ms (`[ALT-3-*]`). Combined with (2): MoE 32k +29.3 %;
   with (1) and (2): **+134 %** (`[ALT-2+3-moe-32k]`).
4. **The production chain has an unresolved pass**: per-token f16 → i8 activation quantization between GEMMs
   (ISA.md lists no f16 → i8 cast; the measured kernels used host-packed A). The fusion "quant + A-pack + GEMM
   epilogue" costs 19 µs per dense layer (0.1 %) if a magic-bias trick or an unlisted cast works; the fallback is a
   host bounce per GEMM: **−2.8 % dense, −13.2 % MoE, −49 % on the draft** (`[ALT-4-*]`).
5. **Our pages are the right size only if c_pg = 0.** Two-tier pages (1 MiB extents + 64 KiB tail pages, compacted
   every 4096 tokens at 46 ns per token-layer) dominate every fixed page size for every c_pg > 0: attention at 32k
   904 → 784 µs at c_pg = 0.5 µs, 1 288 → 808 at 2 µs, 2 313 → 872 on the "gather 3×" branch (`[ALT-5-*]`).

Dominated families, each shown dominated with arithmetic in §4: split-K/stream-K on the dense kernel (≤ +0.6 %
before a sync it cannot afford), producer–consumer core specialization (no inter-core SRAM path: ≤ 58.2 GB/s),
weight-stationary tiling (no reuse at m ≤ 16), L2-resident carving (no L2; S1 = 1 MB), flash-decoding split-KV
(H_kv = 8 = cores; across dies it is errata #11), expert-parallel across a card's two dies (−3.6 %), hot/cold
expert tiers on the same 8-die fleet (−8.5 %), capacity-factor dropping (a quality knob), zero-copy / NUMA / polling
(≤ 1.1 %, T_p2p_bound), command-graph capture (= DESIGN-4's H6 branch).

**Single highest-value experiment: H10** — do two serving-runtime instances, each layer-split over its own two
cards, stream concurrently (card power sensors as the witness, per-instance checksums as the pass)? It gates the
largest gain of this document (+48.5 % / +107.7 %) and is host-only; the kernel-side gate E30 (the W4 unpack chain
regime) only sizes the gain, because two instances beat one for every W4 slab time ≤ 1.37 ms per core-slab, 6.6×
the measured unpack time (`[ALT-2-breakeven-moe-32k]`).

---

## 1. The ranked alternative table (all four problems)

Score = expected gain on the named scored cell × feasibility band. Bands: **0.9** every path on the hot path is a
measured HW-MAP row and only the choreography is new; **0.6** one unmeasured mechanism, with a differencing probe;
**0.5** one unmeasured mechanism and one runtime capability check; **0.3** two unmeasured mechanisms; **0** dead by
errata. Gains are from `proof/alt.py` (label in the Gain column). "Cell" names the scored quantity: fleet =
tokens/s/card at L = 32k (DESIGN-4's 40 % cells), kernel = t = 1 GB/s, attn = t = 1 step time.

| # | Alternative (pattern family) | Problem | Cell improved | Gain (label) | Band | Score | Must survive | Decides |
|---|---|---|---|---|---|---|---|---|
| 1 | **Replication with a minimal W4 tier**: two 4-die instances, the smallest int4 share x per die that fits, cold experts / layers on the measured vector-unpack path (hot-expert residency tiers × model replication) | P4 (+P2) | fleet MoE 32k; fleet dense 32k | **+107.7 %** (3.878) uniform, +124.4 % Zipf(1.0) `[ALT-2-moe-32768-*]`; **+48.5 %** (0.156) dense `[ALT-2-dense-32768-*]`; MoE 128k +100.9 %, 1M +91.0 %; dense spec +48.4 % | 0.5 | **54 / 24** | #2, #3, #4/#6 (unpack passes), #8/#9/#14 (unpack → loader chain), #11 (two chains, no P2P), #12 (int4 only through the measured vector path), H8 memory margin 0.1 GB | **H10**, E30, H11 |
| 2 | **MoE expert kernel on the DDR → L0B direct path** (producer path reuse from DESIGN.md's production kernel) | P2 | kernel t = 1 GB/s; fleet MoE 32k | **135.3 → 167.1** (A lift serialised) / 172.8 (overlapped) `[ALT-1-rate]`; fleet +13.4 % / +15.6 % `[ALT-1-fleet-32768]`; B = 16: 2.357 → 2.772 | 0.9 | **21 / 12** | #14 (full barrier only fence; A L0LOAD after direct loads), #8, #9, errata-14 L0C full (6 × 32 KiB regions kept) | E29 |
| 3 | **Per-layer persistent megakernel** with a DDR-flag cross-core sync; head-aligned QKV column packing makes QKV → attention sync-free (whole-layer single launch; polling) | P1–P3 (+P4) | fleet MoE 32k; dense 32k; draft token | MoE **+12.5 %** at c_sync = 2 µs (+10.2 % at 20 µs) `[ALT-3-moe-*]`; dense +2.8 %; draft 18.1 → 9.3 ms (`[ALT-3-draft-24]`); pays iff c_sync ≤ 109.2 / 113.75 µs `[ALT-3-*-threshold]` | 0.5 | **6.3 / 1.4** | #1 (flag copy could be a no-op → sequence-numbered flags + content checksums), #8 (full barrier before the flag write), watchdog on long kernels, #9 | E31, E32 |
| 4 | **Quantizing epilogue** (f16 → i8 per-token A inside the producing GEMM's epilogue, no cast: f16 magic bias 1280 + low-byte extraction, tree row-max) (fusion quant + A-pack + GEMM) | P1–P2 (+P4) | production viability of every cell | protects **−13.2 % MoE / −2.8 % dense / −49 % draft** (host-bounce fallback) `[ALT-4-*]`; cost 19 / 8 µs per layer (0.1–0.2 %) | 0.6 | **7.9 / 1.7** | #1 (extraction copy), #3, #4 (no shifts used), #6 (rounding mode: magic bias needs round-to-nearest) | E33 |
| 5 | **Two-tier KV pages**: 1 MiB extents + 64 KiB tail pages, compaction every 4096 tokens (paged KV — the right size) | P3 (+P4) | attn 32k / 1M on the paged branches | 904 → 784 µs at c_pg = 0.5 µs (**−13.2 %**), 1 288 → 808 at 2 µs (−37.2 %), 2 313 → 872 at 6 µs (−62.3 %); 0 at c_pg = 0 `[ALT-5-step-*]`; waste ≤ 1 MiB per layer-sequence | 0.9 | **12** (0.5 µs branch) | #2 (extents read as 32 KiB tiles), #14 (unchanged fence), #7 (compaction via US) | E34 (extends E21) |
| 6 | **KV-int8, both halves** (DESIGN-3 1b / DESIGN-4 escape — known, re-ranked) | P3, P4 | fleet MoE 1M / 128k / 32k | **+75.3 % / +27.7 % / +8.7 %** `[ALT-6-fleet-moe-*]`; dense 32k +1.9 %; attn 32k 776 → 391 µs | 0.6 | 5.2 (32k) / 45 (1M) | #13 (i8×i8 only), #5, P-i8 numerics | E27, E36 |
| 7 | **K-int8 / V-f16** (new variant: no P quantization) | P3, P4 | fleet MoE 1M / 128k / 32k | +27.2 % / +12.2 % / +4.2 % `[ALT-6-fleet-moe-*]`; attn 32k 776 → 584 µs (−24.7 %) on the native corner, +2.9 % on the worst corner | 0.8 | 3.4 (32k) / 22 (1M) | #13, #5 | E36 |
| 8 | **Shared-prefix batched attention** (prefix/cache reuse across sequences) | P3, P4 | fleet B = 16 cells | dense +3.8 / +17.3 / +34.8 % at L_s = 4k / 16k / 28k of 32k `[ALT-7-dense-*]`; MoE +2.4 / +10.5 / +19.9 % | 0.8 | ≈ 10 (L_s = L/2) | #2, #9; passes = ⌈B·g/64⌉ | H12 |
| 9 | **Lazy-rescale online softmax**: O resident in L0C, no per-block merge, rescale only on a max jump > 8 (flash-decoding's merge removed) | P3 | attn t = 16, g = 8 (not a scored cell) | two-pass 1 554 → **787 µs** (−49.3 %), S4 1 032 → 787 `[ALT-8-32768-nat_nat-full]`; −23.7 % / −4.8 % on the tree / worst corners; dominates S4 and two-pass on every corner | 0.7 | — | #5 (P ≤ e⁸ ≪ 65 504), E24's exactly-full L0A/L0C | E35 |
| 10 | Head-aligned QKV column packing alone (fusion attention + QKV launch, no sync) | P1, P3 | fleet | dense +0.9 %, MoE +1.9 % `[ALT-3-headaligned-*]` | 0.95 | 1.8 | none new | — |
| 11 | DESIGN-2's expert-pair knob G = 2 on the direct path | P2 | kernel | 99 374 → 97 731 ns per expert (+1.7 %) `[ALT-1-chain]` | 0.9 | 1.5 | A-reg2 pattern (E15) | — |
| 12 | All-W4 replication (x = 1000, no tier) | P4 | fleet MoE 32k | 2.725 (+46 %) — **dominated** by the minimal-x tier (3.878) `[ALT-2-allw4-moe-32k]` | 0.5 | — | — | — |
| 13 | Rows-cliff repair (flat m-curve to 64) | P1, P4 | fleet 4k B = 64 | dense ×3.2 (5.314), MoE ×1.9 at 4k; **memory-infeasible at 32k** (L_max(64) = 8 613 / 30 090) `[ALT-9-rowscliff-*]` | 0.3 | — (4k only) | the unresolved multi-strip wedge | E37 |
| 14 | Capacity-factor token dropping (cap D at 64 of 128 at t = 16) | P2 | MoE B = 16 | ×1.9 per launch `[ALT-9-tokendrop]` at the price of 50 % of the routed pairs — a model-quality decision, unranked | — | — | — | — |
| 15 | Command-graph capture / pipelined launches | P4 | fleet | = DESIGN-4 H6 branch: +3 % dense / +16 % MoE; a runtime feature, not a design | — | — | — | H6 |
| 16 | Zero-copy host bounce, NUMA placement, polling vs interrupt | P4 | fleet | ≤ T_x = 1.48 / 1.50 ms per token = ≤ 1.1 % `[ALT-9-p2p]` (D4 T_p2p_bound) | 0.9 | ≤ 1 | — | H1/H3 |
| 17 | Hot/cold W4 tier on the same 8-die fleet (no replication) | P2, P4 | fleet MoE 32k | **−8.5 %** uniform / −1.7 % Zipf(1.0) `[ALT-9-hotcold-*]`: dominated | — | 0 | — | — |
| 18 | Expert-parallel across a card's two dies | P2, P4 | fleet MoE 32k | **−3.6 %** (+2λ per layer, no concurrency at Π = 1) `[ALT-9-expert-parallel]`; concurrent = errata #11 fault | 0 | 0 | #11 | — |
| 19 | Split-K / stream-K on the dense kernel | P1 | kernel m = 1 | A bytes −5 µs, partials +3 µs, net +2 µs = 0.6 % before a sync that costs ≥ 91 µs or c_sync `[ALT-9-ksplit]` | — | 0 | — | — |
| 20 | Producer–consumer core specialization (DMA cores) | P1–P3 | kernel | no inter-core SRAM path; via DDR = 3× bytes → ≤ 58.2 GB/s `[ALT-9-specialization]` | 0 | 0 | #7 | — |
| 21 | Weight-stationary tiling; L2-resident carving; flash-decoding split-KV; fused gather-GEMM-scatter; per-group tiles; draft on the host CPU | P1–P4 | — | no reuse at m ≤ 16 / no L2 / H_kv = cores / already fused / same N_e / ≤ 1 % — §4 | — | 0 | — | — |

Combinations (each a labelled row): #2 + #3 → MoE 32k 1.867 → 2.415 (+29.3 %, `[ALT-3+1-moe]`); #1 + #2 + #3 →
MoE 32k **4.369 (+134 %)**, dense 0.158 (+50.4 %) (`[ALT-2+3-*]`); #1 + #6 → MoE 1M 0.312 → 1.058 (+239 % over
the f16-KV cell, +93 % over the single KV-int8 instance), MoE 128k 3.294 (`[ALT-2+6-moe-*]`). DESIGN-4's own
runtime-dependent lever (Π = 8 pipelining, 7.7× / 7.1×) dominates everything here if H4 ever passes; #1 is the
Π = 1 way to recover 1.5–2.3× of it with no runtime change, and #1 must be *undone* if Π = 8 arrives (then every
die is busy and the slower W4 bytes cost throughput).

---

## 2. The top five: sketch, arithmetic, errata survival, experiment

### 2.1 Replication with a minimal W4 tier (rank 1) — `[ALT-2-*]`

**Pattern.** Hot-expert residency tiers × model replication, applied to the W4-death reality. DESIGN-4 proved
(T_min_dies) that full int8 residency needs 5 dies, so one model instance spans the fleet and, at Π = 1, streams
one die at a time (T2: tokens/s ≤ 174.6 / bytes per token, fleet-wide). HW-MAP's vector i4 → f16 unpack
(5.3 GB/s/core = 42.4 per die of int4 bytes, **M**) was rejected at the kernel level ("dead vs 120") — correctly
for a kernel, wrongly for the fleet: a byte served from int4 costs 2.06× its int8 time but halves its memory, and
memory is what pins the fleet to one instance.

**Design sketch.**
- *Instance* = 4 dies = 2 cards, chain c0.d1 → c0.d0 → c1.d1 → c1.d0 (d1 first, d0 last: DESIGN-4 T7's minimum
  class; 3 activation hops + logits + ids = **8 λ** instead of 16). Two instances on the 8 dies, each its own
  runtime process owning its two cards' links; nothing crosses between them (errata #11 untouched).
- *Layers per die*: dense 30 (embedding on position 0, lm_head on 3, the draft on 1); MoE 7.
- *The tier*: per die, the smallest share x of the candidate bytes stored as int4 such that
  weights(x) + KV(L) + 2 GiB + 64 MiB ≤ 86 GB (H8's overhead). Candidates: MoE expert slabs (the attention weights
  stay int8); dense: whole weight matrices in the order down, O, QKV, gate/up until x is reached (the time model is
  per byte, so the choice only decides which GEMMs run on which path). For MoE the int4 experts are the **coldest**
  by H9's popularity histogram, so under Zipf routing the int4 bytes are streamed less often than their share.
- *Hot path* (int8 bytes): DESIGN-2 scheme S on the direct path (§2.2, `[ALT-1-chain]`, 99 374 ns per core-slab),
  i8 A. *Cold path* (int4 bytes): host-packed i4 nibbles in the f16 fractal order → DDR → US plain copies
  (≤ 64 KiB, the measured 173–177 aggregate path) → the measured 5-pass unpack to f16 with per-group offset/scale →
  US → S1 (250 GB/s/core) → S1 → L0B loader (26.5 strict-serial) → f16×f16→f32 MMA (verified tuple) → the f32
  region-difference epilogue of DESIGN-3 §3.2. Same core, same column slice, hot experts first, then cold: no
  cross-core traffic, scheme S's balance theorem (Z2) holds per tier. Both A operands (x_q 64 KiB i8, x 128 KiB f16
  at K = 4096) are S1-resident for the step.
- *Fleet accounting*: tokens/s per card = 2 instances / (4 cards × T_inst).

**Arithmetic (MoE, L = 32k, t = 1, uniform routing; `[ALT-2-moe-32768-direct_ser-ovl-uniform]`).**
- Fit: x = 182 / 170 / 170 / 182 ‰ on positions 0–3 → weights 82.8 GB + KV 0.9 + 2.2 = 85.9 ≤ 86.0 on every die
  (`[ALT-2-fit-table-moe-32768]`).
- Per core-slab: int8 direct 99 374 ns; int4 vector 1 MiB / 5.3 GB/s = **197 844 ns** (`[ALT-0-w4v]`); streamed
  mix at x = 0.182 (uniform routing streams the tier in proportion): 24 slabs per layer → 3 × 8 × [(1 − x)·99 374
  + x·197 844]; attention GEMMs 240 223 ns + 2F; per die 7 layers; W = 88.60 ms, KV 21.52, launch 18.01,
  exchange 0.75 ms (8 λ + 28 µs) → **T_inst = 128.89 ms** (today's 8-die step: 133.84).
- tokens/s/card = 2 × 1000 / (4 × 128.89 ms) = **3.878** vs 1.867 (+107.7 %). Zipf(1.0) popularity with the
  coldest 18 % as int4 (they carry 3.2 % of the traffic, `[ALT-2-zipf-share]`): 119.31 ms → **4.190** (+124.4 %).
  With the serial-chain branch of the unpack (55.2 W8-equivalent GB/s, `[ALT-0-w4v]`): 141.59 ms → 3.531 (+89.1 %).
  With DESIGN-2's serial-loader hot kernel instead of §2.2: 3.521 (+88.5 %).
- Dense 32k: x = 376 / 358 / 332 / 376 ‰; W = 3 039 ms (0.65 of the bytes at 174.6, 0.35 at 84.8 W8-equivalent);
  T_inst = 3 197.94 ms → **0.156 (+48.5 %)**; with spec decode (k = 3, α = 0.7) 0.389 vs 0.262 (+48.4 %); the
  serial-chain branch +16.1 %. Per-sequence latency is +35 % worse for dense and 4 % *better* for MoE (128.89 <
  133.84: the direct-path hot tier and 8 fewer λ outweigh the int4 bytes).
- Long context: MoE 128k 2.530 (+100.9 %), 1M 0.596 (+91.0 %, x = 83 %); with full KV-int8 (#6) MoE 1M 1.058 and
  128k 3.294 (`[ALT-2+6-moe-*]`). Dense 128k 0.123 (+30.8 %); **dense 1M cannot replicate** (KV alone 128.8 GB f16
  / 64.4 GB int8 per 4-die position): the 8-die KV-int8 layout of DESIGN-4 stays.
- Robustness (`[ALT-2-breakeven-moe-32k]`): two instances beat one for every W4 core-slab time ≤ 1 371 124 ns,
  i.e. any unpack rate ≥ 0.8 GB/s/core — 6.6× below the measured 5.3 and 4.4× below the serial-chain branch (3.4).
  At 4.0 / 3.0 GB/s/core the cell is 3.662 / 3.405 (`[ALT-2-sens-w4rate-*]`).
- Memory margin: the minimal x leaves 0.1 GB per die at the assumed overhead; each GB of extra overhead needs
  Δx = 1 GB / (7 × 6.44 GB) = 2.2 % (MoE) / 1 GB / (30 × 1.59 GB) = 2.1 % (dense); each 1 % of x costs 0.66 ms of
  the MoE 32k step (24 × 985 ns × 28). Ship x + 3 % (1 GB margin): 130.9 ms → 3.82.
- Dominance: all-W4 replication (x = 1) gives 2.725 (`[ALT-2-allw4-moe-32k]`) — the minimal tier dominates it by
  42 %; a hot/cold tier on the single 8-die instance *loses* 8.5 % (`[ALT-9-hotcold-uniform]`): the gain is the
  second instance, and the tier is only the price of the fit.

**Errata survival.** #12: no i4 → f16 hardware path and the i4×i4 tuple is dead — the design uses neither; the
int4 bytes go through the *measured* 5-pass vector unpack, and nothing is assumed about its rate beyond HW-MAP's
5.3 (the serial-chain branch is carried). #2: every copy ≤ 64 KiB. #3: unpack reels of ≤ 1 024 lanes. #4/#6: the
unpack's shifts and rounding are inside the measured 5-pass routine — E30 re-verifies its exactness on the
fractal-ordered nibbles with power-of-two scales (a silent no-op pass shows as unchanged lanes). #8/#9/#14: the
unpack → US→S1 → loader → MMA chain is a four-engine pipeline with explicit pipe barriers and queue depth =
count; the loader regime (overlapped vs strict-serial) is the ovl/ser branch, not an assumption. #13: hot experts
on i8×i8 with i8 A (needs §2.4's quantizer or host A), cold on f16×f16 with f16 A. #11: two independent chains,
each layer-split inside its own runtime; no P2P, no tensor-split. #5: f32 accumulation everywhere. Thermal: four
cards at the measured 141 W sustained (DESIGN-4 T_power).

**Experiments.** **H10** (host-only, the gate): two runtime processes, each given one 2-card model (the stage-2
model of DESIGN-4 §7 fits), each fed an independent sequence; pass = both sequences' outputs equal their
single-instance runs *and* both cards' power sensors sit at the loaded level simultaneously (≥ 100 W each) for
≥ 100 steps — a runtime that serialises instances shows one card loaded at a time. Failure: either output
diverges (cross-talk), or throughput(2) = throughput(1). **E30** (kernel): the cold-expert chain — i4 pattern with
power-of-two scales and integer offsets through the fractal nibble order → f16 tiles content-compared to the host
(exact); differencing (a second i4 pattern through the same US/S1/L0B addresses); then the chain regime: 10⁴
pieces with an E13-style accumulating oracle (f32-exact small integers), the per-piece time classifies ovl (386 ns)
vs ser (596 ns); positive control with the US→S1 barrier removed must corrupt. **H11**: per-die fit at the chosen x
with H8's measured overhead (free memory after load ≥ KV(L) + 64 MiB); failure = the die refuses the allocation or
H5's KV slope exceeds 7 × 4 KiB per token.

### 2.2 MoE expert kernel on the DDR → L0B direct path (rank 2) — `[ALT-1-*]`

**Pattern.** Producer-path reuse: the dense production kernel streams B tiles DDR → L0B directly (181.3 direct,
174.6 flat m = 1..16 with one full barrier per 32 KiB tile, **M**); DESIGN-2 is anchored to the pre-sync S1-staged
serial loader (26.5 GB/s/core strict-serial → 135.3), and its own banner names the direct-path MoE kernel as the
missing round-3 exercise. Nothing in scheme S depends on the staging leg: the B operand of an expert slice is the
same 32 KiB fractal tile sequence as a dense slab's.

**Design sketch.** Scheme S unchanged (core c owns column slice c of every active expert, 2 MiB per core-slab at
the headline, flat 64 KiB chunk stream, six 32 KiB L0C regions with the region-difference reset, in-kernel
dispatch). Delta: the copy-in → S1 ring → loader → L0B leg is replaced by the measured direct choreography (two
32 KiB parity halves in L0B, full barrier per tile, 16 (16,16,128) calls per tile); the loader carries only the A
block (2 KiB per 128-k chunk, re-lifted per expert because each expert reuses it over N_c/16 = 32 strips).

**Arithmetic (`[ALT-1-chain]`, `[ALT-1-rate]`).** Per expert per core: B 2 MiB at the per-core share of 174.6
(21.825 GB/s) = **96 089 ns**; A lift 64 KiB at 26.5 = 2 473 ns + 32 calls × 25.4 ns residual = **3 285 ns**; MMA
1 024 × 15 = 15 360 ns (16.0 % of the DDR time, hidden). Two branches on the A lift: serialised with the barrier
cadence → 99 374 ns per expert; overlapped (the loader is a different engine and runs between barriers, as it does
at the dense kernel's 2 KiB-per-128 KiB cadence) → 96 089. Step = 8 × chain + F (8 µs): **802 992 ns → 167.1 GB/s
(+23.5 %)** / 776 712 → 172.8 (+27.7 %) against 135.3. The 32 KiB drain per expert is hidden for any R_drain ≥
0.3 GB/s/core (one expert's DDR time), so the E12/E16 drain question disappears. G = 2 (one A lift per expert
pair, DESIGN-2 §5.6): 97 731 ns (+1.7 %). Fleet (`[ALT-1-fleet-*]`): T_slab 122 979 → 99 374 ns gives MoE 32k
133.84 → **117.98 ms, 2.118 tokens/s/card (+13.4 %)**, 128k +8.7 %, 1M +1.9 % (KV-bound), B = 16 2.357 → 2.772.
DESIGN-4's "ping-pong regime" branch (116.39 ms, 2.147) is reproduced within 1.4 % by a measured path instead of
an unmeasured choreography.

**Errata survival.** #14: the full barrier is the only fence for direct loads — used, one per tile, exactly as
measured; the inert copy-in → matrix flag is not used; "some cross-engine handshakes fault after direct loads" is
the one new exposure: the A L0LOAD (S1 → L0A) issued between direct-load barriers at a 2 KiB-per-64 KiB cadence
(the dense kernel runs it at 2 KiB per 128 KiB) — E29 probes exactly that interleave with differencing on A. #9:
L0B 2/2, L0A 2/2, regions 6/6. #8: A3'-style edges as in DESIGN-2 §5.5. errata-14 L0C-full: 6 × 32 KiB = 192 KiB
of 256. #13: i8×i8→i32 only. The m ≥ 24 multi-strip wedge of the dense kernel does not apply (mt = 1 for t ≤ 16).

**Experiment E29** (the direct-path expert chain). Two experts' slices with distinct integer patterns through the
same L0B halves (DESIGN-2 E11's b_e), A = all-ones then one-hot rows (differencing on A through the same L0A slot:
the drained row must change from ΣW to a single row of W), 2 k-chunks minimum (initVal/accumulate semantics), 20
reps bit-identical and equal to the host; then 10⁴ tiles with the E13(a) accumulating oracle to time the chain
(the serialised vs overlapped A-lift branch reads off the per-tile cadence: 3 002 vs 3 105 ns per 64 KiB k-chunk, i.e. two tiles);
positive control: one full barrier removed must change the total or hang. Failure modes: stale A (wrong one-hot
row) = the handshake-after-direct-load fault; unchanged total = a silent no-op somewhere (bisect with E3/E5).

### 2.3 Per-layer persistent megakernel with a DDR-flag cross-core sync (rank 3) — `[ALT-3-*]`

**Pattern.** Persistent megakernel / whole-layer single launch, plus polling. The 91 µs floor is 13.5 % of the MoE
step (18.01 of 133.84 ms, 198 launches), 2.8 % of dense (722 launches), 61 % of a draft token (121 launches),
88 % of the attention step at 4k. ISA.md gives hand-rolled kernels no cross-core sync, which is why every design
uses the launch boundary as its only cross-core fence (DESIGN-2 §1.4, DESIGN-3 A13, DESIGN-4's 6–7 launches per
layer). The alternative is to build the fence: a sequence-numbered flag word in DDR, polled by plain 64 B copies.

**Design sketch.**
- *Head-aligned QKV packing (free, no sync)*: the fused QKV weight is column-permuted on the host so that core c's
  1/8 column slice is {Q columns of the g query heads of KV head c} ∪ {K, V columns of head c}. Core c then owns
  exactly the q, k, v its attention needs (DESIGN-3 is already one KV head per core): q stays in US in the
  A-fragment order (the prologue COPY_FRAC of DESIGN-3 §10.3 and the q round trip disappear), k goes into the
  fractal K page, v into V_tail — QKV → attention needs no cross-core data and no launch boundary
  (`[ALT-3-headaligned-*]`: dense +0.9 %, MoE +1.9 % on their own).
- *The two reductions per layer*: attention → O projection is a K-split over the heads (core c multiplies its
  g·d = 1 024 head-output values by W_o rows [1 024 c, 1 024 (c + 1)) × all d_model columns → partial y_c [rows,
  d_model] f32 = 64 KiB at rows = 1, d = 16 384); gate/up → down is a K-split over the FFN columns core c owns.
  Protocol per reduction: every core writes its partial (US → DDR, ≤ 64 KiB copies), issues a full barrier, writes
  flag[c] = {seq, checksum}; core c polls the 8 flags (64 B DDR → US copies in a scalar loop), reads the 1/8 column
  slice of every partial (8 × 8 KiB), reduces in f32, applies residual + norm (+ RoPE where relevant) and the
  §2.4 quantizer on its slice, writes the f16 and i8 slices, flags again; every core then reads the full x
  (32 KiB f16 + 16 KiB i8) for the next N-split GEMM. Two sync rounds per reduction → 4 syncs per dense layer;
  MoE adds the router: N-split router GEMM (2 MiB / 8 per core), one exchange of 256 logits (1 KiB), redundant
  top-k on every core (DESIGN-2 §4.2's dispatch) → 5 syncs per MoE layer.
- *Launch structure*: one launch per **layer** (not per die block), so a kernel runs ≤ 18.3 ms (dense layer) /
  3.3 ms (MoE) — far under the watchdog's "~seconds" class, which E32 measures anyway. Draft: one launch per
  layer (24) or one per token (1).

**Arithmetic (`[ALT-3-*]`).** Launch savings per token: dense (6 − 1) × 91 µs × 120 = **54.60 ms**; MoE (7 − 1) ×
91 × 28 = **15.28 ms**. Added DDR traffic per reduction = 8 partials written + 8 read + x slices written + x read
by 8 cores = 82 · rows · d_model B: dense 1.34 MB = 7.7 µs, two per layer → 1.84 ms per token; MoE 336 KB → 0.10
ms. Syncs: 480 (dense) / 140 (MoE) per token at c_sync each. Step: dense 2 362.31 → 2 310.52 ms at c_sync = 2 µs
(0.108, +2.8 %); MoE 133.84 → **118.94 ms (2.101, +12.5 %)**; at c_sync = 20 µs still +1.9 % / +10.2 %. Break-even
(T_mega_threshold, an iff): the megakernel pays iff c_sync ≤ (launches saved × 91 µs − reduction traffic) / syncs
= **109.9 µs (dense) / 108.4 µs (MoE)** — a DDR round trip is µs class, so the margin is ≥ 5×. Draft token
(`[ALT-3-draft-*]`): 18 092 µs → 9 265 (24 launches) / 7 172 (1 launch); verify step 54.27 → 27.79 / 21.51 ms;
dense spec 32k 0.262 → 0.264 / 0.265. Combined with §2.2: MoE 32k 133.84 → **103.50 ms, 2.415 (+29.3 %)**
(`[ALT-3+1-moe]`); with §2.1 as well: 4.369 (`[ALT-2+3-moe-32k]`).

**New sync surface (errata #8/#14 applies).** The flag protocol is a hand-managed cross-*core* readback, a class
HW-MAP never measured: (a) #1 — the 64 B flag copy or the partial's copy could be a silent no-op: the flag carries
a per-step sequence number and the partial's checksum; a consumer that sees seq but a stale checksum has caught a
visibility gap, a consumer that never sees seq hangs into the watchdog (observable); (b) #8 — the producer's full
barrier orders its partial write before its flag write on *its* engines; whether another core's DMA read observes
them in that order is the open question E31 answers with ≥ 20 reps × 10³ rounds and content checks (the fallback
protocol re-reads on checksum mismatch, bounded retries, then faults); (c) #9 — the poll loop uses one declared
buffer, depth 1; (d) #7 — partials leave the core through US (no S1/L0 → DDR path); (e) deadlock-freedom: every
core executes the same static schedule, so the flags form a barrier, not a lock.

**Experiments.** **E31** (the DDR flag): 8 cores run 10³ rounds of {write a 64 KiB pattern P(round, core); full
barrier; write flag = (round, checksum(P))}, then each core polls the other 7 flags and reads their patterns; pass =
every read pattern's checksum equals the flagged one for all rounds, 20 reps; the per-round time is c_sync
(expected µs class; the design needs ≤ 108 µs); positive controls: (i) the producer's full barrier removed —
must produce checksum mismatches (proves the detector sees reordering); (ii) a consumer polling a flag no one
writes — must hit the watchdog (proves a hang is observable, not silent). **E32** (watchdog): a kernel streaming
real tiles for 0.1 / 1 / 10 / 60 s, writing a heartbeat counter to DDR every 10 ms; failure = the heartbeat stops
before the programmed duration (the limit is then the maximum kernel length; one launch per layer needs ≥ 20 ms).

### 2.4 The quantizing epilogue (rank 4) — `[ALT-4-*]`

**Pattern.** Kernel fusion quant + A-pack + GEMM. The realised W8 route is i8×i8→i32 with per-token-quantized A
(errata #13); ISA.md's cast list is i8 → f16, i16 → f16, f32 ↔ f16 — **no f16 → i8**. The measured 174.6 / 137.8
kernels ran on host-packed A, and none of the four step models charges a quantization pass; DESIGN.md §7.5 and
DESIGN-2 §3.1 flag the gap without resolving it. In production the activation never visits the host, so every
GEMM's A operand must be quantized on the die, in the producing GEMM's epilogue, or the chain pays a host bounce.

**Design sketch.** After the epilogue's f32 row (or after the §2.3 reduction), per token row: absmax (elementwise
tree max over |x| — DESIGN-3 §3.2's 6-op tree with And(0x7FFF…) for |·| — plus a 16-lane scalar tail), scale
s = 127 / absmax (scalar), `y = Muls(x, s)`, then one of three extraction mechanisms, settled by E33:
(i) an unlisted quantizing cast if the toolchain has one (errata #12's wording "the vector cast table has only
the quantize direction" suggests f16 → i4/i8 casts exist for the dequant instruction's formats);
(ii) **f16 magic bias**: `y16 = Adds(Cast_f16(y), 1280.0)` — for every q = round(y) ∈ [−127, 127] the value q + 1280
lies in [1 024, 2 048), where the f16 ulp is 1, so the add rounds y to the nearest integer and the low byte of the
f16 word equals (q + 256) mod 256 = q in two's complement (checked exhaustively, `[ALT-4-magic]`; the theorem is a
`decide` over 255 cases); the i8 operand is then the low bytes at 2 B stride — a 2D copy with 1 B runs at stride
2 B into the S1 A-resident in the H-A fragment order (E5-class position pair, U);
(iii) the f32 form on the drained C before any cast: bias 1.5 · 2²³ = 12 582 912 puts q in [2²³, 2²⁴) where the
f32 ulp is 1 and the low byte of the word is q mod 256 — the same extraction at stride 4 B, saving the f16 cast.
Scale sx[τ] (f32) rides to the consumer's epilogue as the 64 B reel DESIGN-2 already carries.

**Arithmetic (`[ALT-4-*]`).** Elements per layer: dense 3 × 16 384 (QKV, O, gate/up inputs) + 53 248 (down) =
102 400; MoE 3 × 4 096 + 8 × 4 096 (the eight active experts' down inputs) = 45 056. At 8 lane-ops per element
(tree 6 + Muls + Adds; the extraction is a copy): 819 200 / 360 448 lane-ops = **19 / 8 µs per layer per core**,
redundant on all 8 cores → 0.1 % / 0.2 % of the 32k step. The stake if no mechanism works: a host bounce per GEMM
(4 per layer: D2H 32 KiB f16 at 27.3 + 2 λ + H2D 16 KiB i8 at 13.9 = 738 µs dense / 730 MoE) → dense 2 362.31 →
2 450.82 ms (**−2.8 %**), MoE 133.84 → 154.29 (**−13.2 %**), the draft +17.52 ms per token (**+97 %**, verify step
54 → 107 ms; dense spec 0.262 → 0.247 with both the main model and the draft bouncing, 0.256 draft-only). Without any bounce the only on-device route is f16 A × f16 W with the i8
weights vector-cast on the fly through the 26.5 GB/s/core loader: 106.0 GB/s-class (`[ALT-4-route1b]`), −39 % on
every weight stream.

**Errata survival.** #6 (rounding modes may silently no-op): the magic add relies on round-to-nearest; E33 feeds
y = n + 0.5 exactly (ties) and y = n + 0.25 — a truncating add returns n for both, a no-op returns the input bits.
#4 (16-bit shifts): none used. #3: 1 024-lane calls. #1: the extraction copy (1 B runs) could be a no-op →
differencing (two x patterns through the same A slot, the GEMM's result must change and match the host); the And
for |x| is the E22(c) check. #5: no f16 sums (the tree compares, it does not accumulate). Overflow: |y| ≤ 127 by
construction; the −128 code never occurs (DESIGN-2's U_max premise, T_overflow_m128, is preserved). The i8
quantization error (≤ 0.5/127 of the row's absmax per element) is the same per-token scheme the measured kernel's
host packer used (relerr ≤ 10⁻³ class, DESIGN.md E10).

**Experiment E33.** x rows with x·s integer-valued (so q is exact) and rows with exact ties; mechanisms (i)–(iii)
each run as: pack A into the S1 resident through the mechanism, run the E1/E11 oracle GEMM against a known B
(column sums exact in i32), 20 reps bit-identical, differencing on x; failure modes: all-zero or unchanged C (a
no-op copy/cast), off-by-one on the tie rows (truncating or no-op rounding, #6), a column permutation (the
extraction landed in the wrong fragment order — fix the 2D strides). Decides: which mechanism ships, or the host
bounce (and its −2.8 % / −13.2 % / −49 % in the fleet model).

### 2.5 Two-tier KV pages (rank 5) — `[ALT-5-*]`

**Pattern.** Paged/blocked KV — "are our pages the right size?" DESIGN-3 fixed 64 KiB pages (256 tokens at d =
128) because 64 KiB is the measured copy granule and the maximal legal transfer, and modelled the gather rate as
G(P) = 8·P / (P / 21.825 + c_pg) with c_pg unmeasured (0 / 0.5 / 2 µs bracket, "3× slower" = 6 µs). DESIGN-4
preallocates contiguous per-(layer, head) slabs at L_cap (c_pg = 0 structurally) — right for B = 1, impossible for
a serving runtime holding many sequences of unknown length. The two documents disagree, and both fixed sizes are
dominated: at every c_pg > 0 the 64 KiB page pays c_pg sixteen times per MiB, and a fixed 1 MiB page wastes up to
16 MiB per layer-sequence in unfilled tails (T1_tail_waste).

**Design sketch.** Pages of two sizes from the same die-local pool: **1 MiB extents** (4 096 tokens) for every
complete 4 096-token run of a stream and **64 KiB tail pages** for the remainder. The writer appends into tail
pages exactly as DESIGN-3 §1.2–1.3 (8 × 32 B K copies, V_tail + COPY_FRAC every 16 tokens); when 16 tail pages fill,
a compaction copies them into one extent (16 × (64 KiB DDR → US → 64 KiB US → DDR), measured position pairs,
≤ 64 KiB each) and frees them. The kernel's page-table walk reads two flat tables per stream (extents, then ≤ 15
tail pages); tiles never straddle a page (both sizes are multiples of 32 KiB). The runtime knob of DESIGN-3 §10.2
("page size") becomes "extent size", and the serving allocator keeps the 64 KiB granule it needs for many
sequences.

**Arithmetic (`[ALT-5-*]`).** G_tier(L, c_pg) with n_e = ⌊L/4096⌋ extents and n_t = ⌈(L mod 4096)/256⌉ tail pages:
t_core = n_e (1 MiB / 21.825 + c_pg) + n_t (64 KiB / 21.825 + c_pg). At L = 32k (4096 | L): **174.2 / 172.8 /
167.6 / 155.2 GB/s at c_pg = 0.1 / 0.5 / 2 / 6 µs** versus 64 KiB pages at 169.0 / 149.7 / 104.8 / 58.2; at
L = 34 768 (2 000 tail tokens): 173.6 / 171.0 / 161.6 / 141.1. Attention t = 1, native corner: 32k **904 → 784 µs
(−13.2 %)** at c_pg = 0.5 µs, 1 288 → 808 (−37.2 %) at 2 µs, 2 313 → 872 (−62.3 %) at 6 µs; 1M 28 698 → 24 862,
40 988 → 25 632, 73 803 → 27 680; at c_pg = 0 nothing changes (174.6 both). Compaction: 16 streams × 2 MiB per
4 096 tokens per layer = 46 ns per token-layer (5.5 µs per dense token, 0.0002 %). Tail waste ≤ 16 × 64 KiB =
1 MiB per layer-sequence — the same as 64 KiB pages and 16× less than 1 MiB pages (at B = 8 contexts on a dense
die: 15 layers × 8 × 1 MiB = 120 MiB instead of 1.9 GiB, which matters against the 1.66 GB margin of the 1M
KV-int8 layout). Dominance (T_tier_dom): for every c_pg ≥ 0, G_tier ≥ G(64 KiB) with equality iff c_pg = 0, and
G_tier ≤ G(1 MiB) with equality iff 4096 | L; the fleet cells move only on the paged branches (MoE 32k on the
page64k branch 1.819 → 1.864).

**Errata survival.** #2: extents are read as 32 × 32 KiB tiles (no transfer > 64 KiB); the compaction moves 64 KiB
pieces. #14: the fence per tile is unchanged; the walk is scalar (two table windows of 4 KiB in US). #7: compaction
goes DDR → US → DDR (no S1/L0 → DDR path needed). #1: a compaction copy that silently did nothing leaves the old
tail pages' content in the extent slot → E34 differences every compacted extent against the tail pages' sums.
Ordering: the compaction of stream s runs on the writer core of head s between steps (DESIGN-3 A13), never while a
decode step reads the stream.

**Experiment E34** (extends E21). The E21 probe with the two-tier walk: 2 048 extents + up to 15 tail pages per
core at pseudo-random 1 MiB-aligned / 64 KiB-aligned addresses in a 4 GiB arena, per-page integer patterns, the
drained C compared to the host's sum over the visited pages (a skipped, repeated or stale page changes it); the
time per page against 1/P gives c_pg at both sizes (the extent's c_pg may differ from the 64 KiB page's — the model
assumes equal; the fit tests it); then compaction: write 16 tail pages, compact, run the kernel over the extent,
differencing with a second content set. Decides: the extent size and whether c_pg is worth the second tier (iff
c_pg(64 KiB) > 0 at the measurement's resolution; at 0.1 µs it is already +3 %).

### 2.6 Three more that dominate something (ranks 6–9, briefly)

**Lazy-rescale online softmax (rank 9, `[ALT-8-*]`).** DESIGN-3's merge (7 000 lane-ops per block per fragment,
plus a C_o drain) exists because L0C cannot be rescaled. But softmax is invariant to the shift: fix m_r per row
after the first block (plus a margin μ = 8), accumulate every block's P·V **into one resident L0C region** (the
matrix unit accumulates; no drain, no α, no merge), and only if a later block's row max exceeds m_r + μ drain,
rescale once and continue (exp(μ) = 2 981 ≪ 65 504 keeps P representable in f16, errata #5 never bites; a
bounded-score contract is *not* assumed — the exception path exists). It dominates DESIGN-3's S4 variant and the
two-pass at every corner: t = 16, g = 8, 32k: two-pass 1 554 → **787 µs**, S4 1 032 → 787 on the native corner
(DDR-bound again: the 128-token S4 block is DDR-bound iff c_V ≤ 7 at ρ32 = 1, `[ALT-8-threshold]`); 1 558 → 1 187
on the (native exp, tree max) corner; 6 802 → 6 471 on the worst. At t = 1 it removes 8 KiB of drain and 162 ns of
vector per block (≈ 1 %). Not a scored cell (no fleet row runs a single sequence at t = 16); gated on E35 (drift
and exception rate with real q, K; the exactly-full L0C with one O region: 3 × 64 KiB C_s + 64 KiB O = 256 KiB).

**K-int8 / V-f16 (rank 7, `[ALT-6-*]`).** Full KV-int8 (both halves, P quantised to i8 — DESIGN-3 1b) is the
bigger lever (MoE 1M +75.3 %) but its accuracy rests on an i8 P with a fixed scale. Quantising only K (per-token
scale as a reel, +1 lane-op per score; q quantised per row) keeps P and V in f16 on the verified f16×f16 PV path:
bytes × 3/4 → attention 32k 776 → 584 µs (−24.7 %) on the native corner (the worst corner is vector-bound at
+2.9 %: DDR-bound iff c_V ≤ 45 / 21 at ρ32 = 1 / 2, `[ALT-6-threshold-*]`); fleet MoE 1M 0.312 → 0.397 (+27.2 %),
128k +12.2 %, 32k +4.2 %. It is dominated by full KV-int8 on every rate cell and dominates it on numerics risk; the
measurement that separates them is E27/E36's relerr on P-i8 — if full KV-int8 passes 10⁻³, K-only is dead.

**Shared-prefix batched attention (rank 8, `[ALT-7-*]`).** B sequences sharing an L_s-token prefix (system prompt)
stream the prefix KV once per pass with rows = B·g (passes = ⌈B·g / 64⌉) instead of B times: KV per layer = kv_tok ·
((L − L_s)·B + L_s·passes) / R. Dense B = 16 (g = 16 → 4 passes): +3.8 / +17.3 / +34.8 % at L_s = 4k / 16k / 28k
of 32k; MoE B = 16 (g = 4 → 1 pass): +2.4 / +10.5 / +19.9 %. Gain iff passes < B (T_prefix_iff); the lazy-rescale
variant raises rows per pass to 128 and doubles the dense gain. Workload-dependent: H12 (the scheduler's
prefix-sharing histogram) decides whether any cell moves.

---

## 3. The fusion map — which designs share streams, buffers and launches

### 3.1 Streams and the passes each fusion eliminates (new sync surface named; errata #8/#14 apply to every row)

| # | Stream / pass | Producer → consumer(s) | Designs sharing it | What the fusion eliminates | New sync surface |
|---|---|---|---|---|---|
| S1 | **Weight stream**: DDR → L0B direct, 32 KiB tiles, full barrier per tile, 16 (16,16,128) calls per tile | copy-in engine → matrix unit | DESIGN.md B tiles; §2.2 MoE expert slices; DESIGN-3 K/V tiles; §2.1 hot tier | for MoE: the S1 B ring (256 KiB) and the loader's B bytes (2 MiB per expert per core at 26.5) — the 135.3 → 167.1 of `[ALT-1-rate]` | none new (the measured choreography); the A L0LOAD interleave (E29) |
| S2 | **A-operand stream**: S1 → L0A loader | quantizing epilogue (§2.4) → S1 resident → loader → MMA | dense A (128 KiB i8 per launch), MoE x_q (64 KiB, re-lifted per expert), attention q / P (4 KiB·mt) | inside a megakernel: A's DDR round trip per GEMM (write f16/i8 x, read it back) and the host-bounce fallback (738 µs per layer) | B1/B2 pipe barriers (intra-core, DESIGN.md §4.2); cross-core only through the reduction flags |
| S3 | **QKV → attention** | QKV GEMM epilogue (core c, head-aligned slice) → attention on core c | DESIGN.md → DESIGN-3 | one launch (91 µs), q's DDR round trip (16 KiB·mt), the prologue COPY_FRAC (585 ns·mt); K/V appends unchanged | none cross-core; A11–A13 of DESIGN-3 become in-kernel pipe barriers |
| S4 | **attention → O projection** (K-split over heads) | attention epilogue → partial y_c [rows, d_model] f32 → reduction #1 | DESIGN-3 → DESIGN.md | one launch; the per-head out round trip (4 KiB·mt per core) | **reduction #1**: 8 partials (64 KiB each at d = 16 384) + flags, two rounds (`[ALT-3-*]`: 7.7 µs of traffic + 2 c_sync) |
| S5 | **O → residual + norm (+ RoPE) → gate/up** | reduction consumer's epilogue → quantizer → S2 | DESIGN-4's "norm/rope/residual" launch | one launch (DESIGN-4 §9: 6 → 4 per dense layer = 21.84 ms per token) | part of reduction #1's second round |
| S6 | **gate/up → down** (K-split over the FFN columns core c owns) | gate/up epilogue (act slice, quantised) → down partial → reduction #2 | DESIGN.md (dense) / DESIGN-2 (expert down slabs) | one launch; the act round trip (2·F/8 per core) | **reduction #2** (same protocol) |
| S7 | **Router → dispatch → experts** | router GEMM N-split (2 MiB / 8 per core) → 1 KiB logits exchange → redundant top-k (DESIGN-2 §4.2) → expert stream (hot tier §2.2, cold tier §2.1) | DESIGN-2, §2.1, §2.3 | the router launch and the descriptor's DDR latency (DESIGN-2 §4.3's 2 µs) | one logits exchange (flag round); the hot → cold phase boundary is intra-core (same core, same slice) |
| S8 | **KV write + compaction** | QKV epilogue → K page (8 × 32 B), V_tail (+ COPY_FRAC per 16 tokens) → §2.5 compaction every 4 096 tokens | DESIGN-3 §10.1, §2.5 | nothing (adds 46 ns per token-layer); replaces the fixed page size | A13 (launch boundary) stays the fence between a stream's writer and its readers |
| S9 | **KV stream, two consumers**: K tiles → scores, V tiles → PV (V lags K by two blocks) | copy-in → matrix (scores) / matrix (PV) | DESIGN-3 (already one stream); §2.6 lazy rescale removes the C_o drain consumer | with lazy rescale: the per-block C_o drain (8 KiB·mt) and merge (7 000·mt lane-ops) | A9/A10 edges vanish; one O region accumulates across blocks |
| S10 | **Prefix KV across B sequences** | one prefix stream → rows = B·g | §2.6 shared prefix on DESIGN-3's pipeline | (B − passes) re-reads of the prefix KV | none (rows are independent) |
| S11 | **Draft model** | its own die (DESIGN-4 §6); host sampling | DESIGN-4 | with §2.3: 97 of 121 launches per draft token (18.1 → 9.3 ms) | the per-layer flag rounds on the draft die |

### 3.2 Buffers shared across the designs (per core)

| Buffer | DESIGN.md | DESIGN-2 / §2.2 | DESIGN-3 | §2.1 cold tier | §2.3 / §2.4 |
|---|---|---|---|---|---|
| L0B ring | 2 × 32 KiB direct tiles | same (B ring in S1 removed) | same (K/V tiles) | 3 × 16 KiB f16 pieces via the loader (DESIGN-2's L0B plan) | — |
| L0C regions (region-difference reset everywhere; flags ignored) | 1 slab 64 KiB·mt | 6 × 32 KiB (U_max 32) | 3 C_s + 2 C_o (or 3 C_s + 1 O with lazy rescale) | 6 × 32 KiB f32 (DESIGN-3 drift bound) | — |
| S1 | A ring / resident 128 KiB | x_q 64 KiB resident; shadows 192 KiB | P ring, NegSnap (mt ≥ 2) | + x f16 128 KiB resident | A resident written by the quantizer |
| US | drain, s[n], y | drain / diff / shadow staging, y_acc 32 KiB | drained C_s, P staging, O, reels (208 KiB + 64 B at mt = 1 — the tightest) | unpack reels (≤ 1 024 lanes), 2 × 4 KiB f16 out | flag words (64 B), partial staging (≤ 64 KiB), quantizer reels |
| DDR, cross-core | — | — | KV pages / extents, tables | expert arena (int8 hot, int4 cold) | 8 partial slabs + 8 flags per reduction |

### 3.3 Launches per token (the 91 µs floor, serialised branch)

| | dense layer | MoE layer | attention 4k (standalone) | draft token |
|---|---|---|---|---|
| today (DESIGN-4) | 6 (722 per token = 65.70 ms) | 7 (198 = 18.01 ms) | 1 (91 of 194 µs wall) | 121 (11.0 of 18.1 ms) |
| + head-aligned QKV (S3) | 5 | 6 | fused | — |
| + epilogue norm/rope/residual (S5, DESIGN-4 §9) | 4 | 5 | — | — |
| + megakernel (§2.3) | **1** (122 per token = 11.1 ms) | **1** (30 = 2.73 ms) | — | 24 → 1 (2.2 → 0.09 ms) |

### 3.4 Layout reuse (one pack order per dtype, every problem)

- The settled i8 fragment [16 n × 32 k] column-major (HW-MAP): W8 tiles (DESIGN.md, DESIGN-2), KV-int8 K and V
  pages (§2.6), the i8 A operand (DESIGN-2's H-A) — and the quantizer's extraction copy writes it directly.
- The f16 fragment H-F16 [16 n × 16 k] (DESIGN-3 E23): f16 K/V pages, the cold tier's unpacked f16 tiles (the
  host packs the i4 nibbles in this order so the 5-pass unpack emits fractal lanes), the f16 A operands (q, P, x).
- Drained-C nesting = A nesting (DESIGN-3 §2.3): P feeds the PV call without rearrangement; the same identity lets
  the reduction consumer's f32 slice be quantised and packed in one pass.
- Head-aligned QKV columns (§2.3): a host-side column permutation of one weight matrix, free, that makes the
  QKV → attention edge core-local for both GQA shapes (g = 16 dense, g = 4 MoE) and for DESIGN-3's g = 8 headline.

---

## 4. Dominated and dead alternatives — shown dominated with arithmetic (`[ALT-9-*]`)

| Family | Matched against | Arithmetic | Verdict |
|---|---|---|---|
| **Split-K / stream-K** (dense) | DESIGN.md's 8-way N-split at m = 1, 8192² | K-split shrinks A per core 128 → 16 KiB: 896 KiB less DDR per die = 5 µs; adds 8 × 32 KiB f32 partials written + read = 3 µs; net **+2 µs = 0.6 %** of a 384 µs kernel *before* the cross-core sync it needs (≥ 91 µs as a launch, or c_sync × 2 rounds); stream-K fixes tile-count imbalance, and the N-split has none (8 equal 8 MiB regions). DESIGN.md T9_ksplit (m = 64: 112.4 < 115.9) and DESIGN-2 Z8 (K-split loses on every cell but one) already cover the larger shapes | dominated (≤ +0.6 %, negative with any sync cost) |
| **Producer–consumer core specialization** (DMA cores feeding compute cores) | 8 independent cores, DDR the only shared medium | no inter-core SRAM path (S1, US, L0 are per core; no S1/L0 → DDR copy, errata #7): a DMA core can only hand bytes over through DDR = read W + write W + read W = 3× the bytes → ≤ 174.6/3 = **58.2 GB/s**; inside a core the engines are already specialised (copy-in / loader / matrix / vector / copy-out) | dead |
| **Weight-stationary tiling** | output-stationary C in L0C (forced: no US → L0C write path, DESIGN.md §1.4) | at m ≤ 16 a B tile is used by one A fragment (reuse 1); keeping B resident would re-stream A per tile: A is 1.5 % of the bytes today, so the best case saves < 1.5 % and costs 8 MiB of B residency that no SRAM has | dominated |
| **L2-resident tile carving** | hierarchy: no L2; S1 ~1 MB/core | the smallest hot object (an expert slab, 16 MiB; a dense slab, 8 MiB per core) exceeds 8 × S1; DESIGN-2's only residency win (A in L0A at K ≤ 3 072) is already taken | dead |
| **Flash-decoding split-KV** | DESIGN-3: one KV head per core, H_kv = 8 = cores; H_kv ∤ 8 handled by the block-round-robin split + consumer merge (§9); across dies = tensor-split of one op (errata #11 fault) | no imbalance to fix at H_kv = 8 (±12 µs per block elsewhere); at Π = 1 a cross-die split cannot run concurrently and would add 2 λ per layer | dominated / dead across dies |
| **GQA head packing** | rows = t·g already (T_gqa_matrix) | the only loss is the 16-row padding at t = 1 (vector work ×2 on g = 8, ×4 on g = 4) — fixable only by a 2D row-selective drain (DESIGN-3 §9) | already done |
| **Expert-parallel across the card's two dies** | layer-split-only runtime, Π = 1 | no concurrency (dies alternate) and +2 λ per MoE layer = +5.1 ms: 133.84 → 138.94 ms (**−3.6 %**); concurrent streaming = the measured runtime fault | dead |
| **Hot/cold expert tiers on the same 8-die fleet** | §2.1 without replication | coldest 25 % of experts as int4: MoE 32k 133.84 → 146.42 ms (**−8.5 %**) uniform, −1.7 % Zipf(1.0): memory is not binding at 32k, so the tier only pays its 2.06× byte cost | dominated by §2.1 (the tier is worth paying only for the second instance) |
| **Capacity-factor token dropping** | DESIGN-2 Z3: step = F + D·T_S | capping D at 64 of 128 (t = 16, uniform) halves the step (15.74 → 7.87 ms, ×1.9) by discarding half the routed pairs — a model-quality decision outside this scoring | unranked |
| **Grouped-GEMM per-group tiles; fused gather-GEMM-scatter; expert-pair scheduling** | DESIGN-2 §1.3, §3, §5.6 | N_e is uniform (one tile shape); there is no gather (shared A fragment) and the scatter-add is core-local; pairs = the G knob (+1.0 %, +1.7 % on the direct path) | already done |
| **Command-graph capture / launch pipelining** | DESIGN-4's H6 branch | if the runtime pipelines launches: dense 2 296.61 ms (+3 %), MoE 115.82 (+16 %) — a host experiment, not a design; §2.3 obtains the same without the runtime and adds the in-kernel fusions | = H6 |
| **Zero-copy host bounce, NUMA-aware placement, polling vs interrupt** | DESIGN-4 T_p2p_bound: any exchange improvement ≤ T_x | ≤ 1 497 µs dense / 1 480 µs MoE per token = ≤ 0.06 % / 1.1 % (λ = 10 µs cells: 0.105 / 1.886) | dominated (≤ 1.1 %) |
| **Sequence pipelining Π = 8** | DESIGN-4 §5, H4 | 7.7× / 7.1× — the one lever above §2.1, runtime-dependent; §2.1 is its Π = 1 substitute (1.5–2.3×) and must be reverted if H4 passes | not ours to build |
| **Draft model on the host CPU** | DESIGN-4 §6.1 (launch-bound draft) | ≤ 54 ms per verify step = 2.3 % of the dense spec step; with §2.3 the draft is 27.8 ms anyway | dominated |
| **Rows-cliff repair** (flat m-curve to 64) | the unresolved m ≥ 24 multi-strip wedge (HW-MAP: 81/59/43) | would buy B = 64 at 4k only: dense 1.629 → 5.314 (×3.2), MoE 2.866 → 5.618 (×1.9); at 32k memory-infeasible (L_max(64) = 8 613 / 30 090); mechanism unknown — E37 bisects it (barrier count per strip vs L0A double-buffer vs loader cadence) | real but outside the scored cells |

---

## 5. Experiment ladder (continues DESIGN-3's E28 and DESIGN-4's H9; observable failure modes only)

Harness rules unchanged (DESIGN.md §8): sentinel-filled destinations, differencing through the same address,
integer-valued inputs with exact expectations, ≥ 20 reps bit-identical, timing recorded but never a pass criterion.

| # | Settles | Setup (summary; details in §2) | Observable failure | Decides |
|---|---|---|---|---|
| **H10** | **two runtime instances on disjoint card pairs stream concurrently** | two processes, each a 2-card layer-split model, independent sequences, ≥ 100 steps; outputs vs single-instance runs; card power sensors at 10 Hz | output mismatch (cross-talk); throughput(2) = throughput(1) or only one card loaded at a time (serialised) | §2.1 on/off: +48.5 % / +107.7 % |
| E29 | direct-path expert chain: A L0LOAD interleaved with direct-load barriers at 2 KiB per 64 KiB; serialised vs overlapped A lift | DESIGN-2 E11 patterns through the same L0B halves; one-hot A rows through the same L0A slot; 10⁴-tile accumulating oracle; positive control (barrier removed) | stale A row (handshake fault after direct loads); unchanged total (no-op); control passes (blind detector) | §2.2: 167.1 vs 172.8; the fleet's T_slab |
| E30 | the cold-tier chain: 5-pass unpack exactness on fractal-ordered nibbles with per-group offset/scale, US → S1 → loader → f16×f16 MMA, chain regime (ovl 386 ns vs ser 596 ns per 2 KiB i4) | power-of-two scales, integer offsets → exact f16; differencing on the i4 source; E13-style accumulating oracle over 10⁴ pieces | wrong/unchanged f16 lanes (a no-op pass, errata #4/#6/#1); regime read off the per-piece time; control (US → S1 barrier removed) must corrupt | §2.1's branch (3.878 vs 3.531); any rate ≥ 0.8 GB/s/core keeps the verdict |
| H11 | per-die fit at the chosen x | load the 4-die instance, read free memory, allocate KV(L) + 64 MiB | allocation refused; H5 slope > 7 × 4 KiB per token | the x margin (+2.2 % per GB of overhead) |
| E31 | DDR-flag cross-core sync: visibility, c_sync | 8 cores × 10³ rounds of pattern + full barrier + flag {seq, checksum}; polling consumers; controls: (i) barrier removed, (ii) never-written flag | checksum mismatch after seq seen (visibility gap); control (i) must mismatch; control (ii) must hit the watchdog | §2.3 on/off; c_sync ≤ 108 µs is the threshold |
| E32 | watchdog limit for long kernels | a tile-streaming kernel of 0.1 / 1 / 10 / 60 s with a 10 ms heartbeat to DDR | heartbeat stops before the programmed end | launch granularity of §2.3 (per layer needs ≥ 20 ms) |
| E33 | the quantizer mechanism: unlisted cast / f16 magic bias + 1 B-run 2D copy / f32 magic bias; rounding mode on ties | integer-valued x·s and exact-tie rows; E1/E11 oracle GEMM after each mechanism; differencing on x | all-zero / unchanged C (no-op cast or copy); off-by-one on ties (truncating or no-op rounding, errata #6); column permutation (wrong extraction strides) | §2.4: 0.1 % vs the host-bounce −2.8 % / −13.2 % |
| E34 | G at 1 MiB extents and 64 KiB tail pages, c_pg per size; compaction correctness | E21 with the two-tier walk, 2 048 extents + ≤ 15 tail pages per core, per-page patterns; compaction differencing | skipped / repeated / stale page changes the drained sum; a compaction that did nothing leaves the old sums | §2.5: extent size, whether the tier pays (iff c_pg > 0) |
| E35 | lazy rescale: exception rate and drift with real q, K; one O region accumulating across 2 048 blocks; exactly-full L0C (3 × 64 C_s + 64 O) | integer harness first (identity exp: exact), then f16 q, K, V at 32k / 1M vs f64, 20 reps; count max jumps > μ | relerr > 10⁻³; any rep-to-rep difference; exactly-full aliasing (E24-style) | §2.6 lazy rescale (787 vs 1 554 µs at t = 16) |
| E36 | K-int8 scores: per-token K scale reel, per-row q scale, i8×i8 scores + f16 PV; and full KV-int8's P-i8 | the E27 inputs on both variants | relerr > 10⁻³ on either | §2.6: K-only (+27 % at 1M) vs full (+75 %) |
| H12 | prefix sharing in the serving workload | scheduler log: per batch, the longest common prefix length histogram | — (informational) | whether §2.6 shared-prefix moves a B = 16 cell |
| E37 | the m ≥ 24 multi-strip wedge | the measured kernel at m = 16 / 24 / 32 with (a) one strip per barrier, (b) L0A ring depth 2 → 3, (c) A lifted once per tile; content-checked | rate ∝ 1/strips under every variant = structural; one variant restoring flatness = the cause | rows-cliff repair (4k B = 64 cells) |

Order: **H10 first** (an afternoon, host-only, gates the largest gain), E29 and E30 in parallel on two core sets
(E29 is the smaller delta on a measured kernel; E30 sizes §2.1), E33 (the production chain), E31/E32 (§2.3),
E34 (with E21), E35, E36, H11, H12, E37. **The single highest-value experiment is H10**: if two instances cannot
coexist, §2.1 is dead and the ranking's first row becomes §2.2 (+13.4 %); if they can, every W4 unpack rate above
0.8 GB/s/core (6.6× below the measured 5.3) keeps §2.1 the winner, so no kernel-side probe can reverse it.

---

## Appendix A — claims ledger (for the proof session: `proof/alt.py` labels and proposed theorem names)

Status: M = HW-MAP input; D2/D3/D4 = a ledgered theorem of DESIGN-2/3/4 used as input (fleet.lean / attn.lean);
D = derived here (theorem target, `decide`/`omega` over Nat with the unmeasured quantities as explicit arguments —
"∀ x" marks a result to be proved over the whole bracket with both endpoints); A = assumption measured by the named
experiment; U = empirical branch. Proposed names are for `proof/alt.lean`.

| # | claim | value | status | alt.py label / theorem |
|---|---|---|---|---|
| 1 | W4 vector path: 5.3 GB/s/core of int4 = 42.4 per die = 84.8 W8-equivalent; per core-slab (1 MiB int4) 197 844 ns; serial-chain piece 386 + 16 + 154 + 25 + 15 = 596 ns per 2 KiB → 305 152 ns per core-slab, 55.2 W8-equivalent per die | | M → D | [ALT-0-w4v] T_alt_w4_rates |
| 2 | direct-path expert chain per core: B 96 089 ns (2 MiB at 1746/8), A lift 2 473 + 812 = 3 285 ns, MMA 15 360 = 16.0 %; serialised 99 374, overlapped 96 089; G = 2: 97 731 | | D | [ALT-1-chain] T_alt_direct_chain |
| 3 | step 8 × chain + 8 000: 802 992 ns → 167.1 GB/s; 776 712 → 172.8; anchor 135.3; +23.5 % / +27.7 %; rate(a) for every A-lift cost a ∈ [0, 3 285] lies in [167.1, 172.8] | | D (∀ a) | [ALT-1-rate] T_alt_direct_rate, T_alt_direct_bracket |
| 4 | 32 KiB drain per expert hidden iff R_drain ≥ 0.3 GB/s/core | iff | D (∀ R_drain) | [ALT-1-rate] T_alt_direct_drain |
| 5 | fleet MoE t = 1 with T_slab = 99 374 / 96 089: 32k 117.98 / 115.77 ms → 2.118 / 2.159 (+13.4 / +15.6 %); 128k 1.369 / 1.386; 1M 0.318 / 0.319; B = 16 32k 2.772 | | D (D4 model) | [ALT-1-fleet-*] T_alt_direct_fleet |
| 6 | 4-die instance fit: minimal x (‰ of candidate bytes as int4) MoE 32k 182/170/170/182, 128k 244/232/232/244, 1M 827/816/816/827; dense 32k 376/358/332/376, 128k 629/610/585/629; dense 1M infeasible at x = 1000 (KV alone 128.8 / 64.4 GB per position); weights(x) is non-increasing in x, so the minimal x is an iff | | D (overhead A — H8) | [ALT-2-fit-*] [ALT-2-fit-table-*] T_alt_fit_minx, T_alt_fit_dense_1M_infeasible |
| 7 | per-die totals at the minimal x: 85.9 GB on every position (MoE 32k: weights 82.8 + KV 0.9 + 2.2); margin 0.1 GB; Δx per GB of overhead = 2.2 % (MoE) / 2.1 % (dense) | | D | [ALT-2-fit-table-*] T_alt_fit_margin |
| 8 | instance step, MoE 32k uniform, hot = direct serialised, cold = ovl: W 88.60 + KV 21.52 + launch 18.01 + xch 0.75 = 128.89 ms; 2 instances → 3.878 tokens/s/card = +107.7 % over 1.867; cold = ser 141.59 → 3.531 (+89.1 %); hot = anchor 141.97 → 3.521; Zipf(1.0) 119.31 → 4.190 | | D (D4 model; popularity U — H9) | [ALT-2-moe-32768-*] T_alt_rep_moe_32k |
| 9 | dense 32k: W 3 039.24 ms (0.65 of bytes at 174.6, 0.35 at 84.8), step 3 197.94 → 0.156 (+48.5 %); ser branch 4 069.94 → 0.122 (+16.1 %); KV-int8 0.163; spec k = 3 α = 0.7: 3 252.30 → 0.389 (+48.4 %) | | D | [ALT-2-dense-32768-*] [ALT-2-dense-32k-spec] T_alt_rep_dense_32k |
| 10 | long context: MoE 128k 2.530 (+100.9 %), 1M 0.596 (+91.0 %); dense 128k 0.123 (+30.8 %), ser −4.2 %; MoE B = 16 32k 4.084 (+73.2 %) | | D | [ALT-2-moe-131072-*] [ALT-2-moe-1048576-*] [ALT-2-dense-131072-*] [ALT-2-moe-32k-B16] T_alt_rep_cells |
| 11 | two instances beat one (MoE 32k, uniform) for every W4 core-slab time ≤ 1 371 124 ns (≥ 0.8 GB/s/core of int4); 6.6× below the measured 5.3; at 4.0 / 3.0 GB/s/core 3.662 / 3.405 | iff | D (∀ T_cold) | [ALT-2-breakeven-moe-32k] [ALT-2-sens-w4rate-*] T_alt_rep_breakeven |
| 12 | all-W4 replication 2.725 < minimal tier 3.878; the tier on the single 8-die instance loses: 146.42 ms (−8.5 %) uniform, 136.20 (−1.7 %) Zipf | | D | [ALT-2-allw4-moe-32k] [ALT-9-hotcold-*] T_alt_rep_dominates_allw4, T_alt_hotcold_loses |
| 13 | Zipf(1.0) popularity: the coldest 10 / 25 / 50 / 75 % of 256 experts carry 1.7 / 4.7 / 11.3 / 22.5 % of the traffic (harmonic-number ratio) | | D (rational; the family itself U — H9) | [ALT-2-zipf-share] T_alt_zipf_share (ℚ or scaled Nat) |
| 14 | combinations: §2.2 + §2.3 (c_sync 5 µs) MoE 32k 103.50 ms → 2.415 (+29.3 %); §2.1 + §2.2 + §2.3 → 114.41 ms → 4.369 (+134.0 %), dense 3 147.59 → 0.158 (+50.4 %); §2.1 + KV-int8: MoE 1M 472.40 → 1.058, 128k 151.78 → 3.294 | | D | [ALT-3+1-moe] [ALT-2+3-*] [ALT-2+6-moe-*] T_alt_combos |
| 15 | megakernel savings: (nlaunch − 1) × 91 µs × n_L = 54.60 ms (dense) / 15.28 (MoE); reduction traffic 82·rows·d B = 1 343 488 B → 7 694 ns dense (1.84 ms per token), 335 872 B MoE (0.10 ms); syncs 480 / 140 per token | | D | [ALT-3-*] T_alt_mega_savings |
| 16 | megakernel pays iff c_sync ≤ 113 750 / 109 200 ns (launch savings only) and ≤ 109 903 / 108 430 net of the reduction traffic (dense / MoE); step at c_sync = 2 / 5 / 20 µs: dense 2 310.52 / 2 311.96 / 2 319.16 ms (0.108 / 0.108 / 0.107), MoE 118.94 / 119.36 / 121.46 (2.101 / 2.094 / 2.058) | iff | D (∀ c_sync) | [ALT-3-*-threshold] [ALT-3-*-csync*] T_alt_mega_threshold, T_alt_mega_cells |
| 17 | draft token 18 092 / 9 265 / 7 172 µs at 121 / 24 / 1 launches; verify step 54.27 / 27.79 / 21.51 ms | | D | [ALT-3-draft-*] T_alt_draft_launches |
| 18 | head-aligned QKV packing alone: one launch per layer: dense 2 351.39 ms (+0.9 %), MoE 131.29 (+1.9 %); the attention of KV head c needs only core c's QKV slice (a column permutation of the fused weight) | | D / DEFINITION | [ALT-3-headaligned-*] T_alt_headaligned |
| 19 | f16 magic bias 1280: for every q ∈ [−127, 127], q + 1280 ∈ [1 024, 2 048) and (q + 1280 − 1024) mod 256 = q mod 256 (two's-complement byte) — exhaustively true; f32 analogue with bias 12 582 912 on [2²³, 2²⁴) | true | D (`decide` over 255 cases) | [ALT-4-magic] T_alt_magic_f16, T_alt_magic_f32 |
| 20 | quantizer cost: 102 400 / 45 056 elements per layer × 8 lane-ops = 819 200 / 360 448 = 19 / 8 µs per core per layer = 0.1 / 0.2 % of the 32k step | | D (op count A) | [ALT-4-dense] [ALT-4-moe] T_alt_quant_cost |
| 21 | host-quantization fallback: 4 bounces × (2 λ + 32 KiB at 27.3 + 16 KiB at 13.9) = 738 / 730 µs per layer → dense 2 450.82 ms (−2.8 %), MoE 154.29 (−13.2 %); draft +96 × 183 µs = +17.52 ms per token; Route-1b-class fallback 106.0 GB/s | | D (λ A) | [ALT-4-*] [ALT-4-route1b] T_alt_quant_fallback |
| 22 | two-tier G: at 32k (4096 \| L) 174.2 / 172.8 / 167.6 / 155.2 at c_pg = 0.1 / 0.5 / 2 / 6.005 µs vs 64 KiB pages 169.0 / 149.7 / 104.8 / 58.2; at 34 768: 173.6 / 171.0 / 161.6 / 141.1; at c_pg = 0 all 174.6 | | D (c_pg U — E34) | [ALT-5-G-cpg*] T_alt_tier_cells |
| 23 | G_tier(L, c_pg) ≥ G(64 KiB, c_pg) for every c_pg ≥ 0, L ≥ 1, with equality iff c_pg = 0; G_tier ≤ G(1 MiB, c_pg) with equality iff 4096 \| L | | D (∀ c_pg, ∀ L) | T_alt_tier_dominates |
| 24 | attention t = 1 native corner: 32k 904 → 784 µs (−13.2 %) at 0.5 µs, 1 288 → 808 (−37.2 %) at 2 µs, 2 313 → 872 (−62.3 %) at 6.005 µs; 1M 28 698 → 24 862, 40 988 → 25 632, 73 803 → 27 680 | | D (D3 model) | [ALT-5-step-*] T_alt_tier_steps |
| 25 | compaction 16 × 2 MiB per 4 096 tokens per layer = 46 ns per token-layer; tail waste ≤ 1 MiB per layer-sequence; ≤ 15 tail pages + 256 extents per 1M-token stream | | D | [ALT-5-compaction] T_alt_tier_overhead |
| 26 | K-int8/V-f16: t = 1 block DDR-bound iff c_V ≤ 45 (ρ32 = 1) / 21 (ρ32 = 2) at 3/4 bytes (block 9 008 ns); attention 32k 776 → 584 µs (−24.7 %), worst corner 851 → 876 (+2.9 %); 1M 24 606 → 18 456 | iff | D (∀ c_V) | [ALT-6-threshold-*] [ALT-6-attn-*] T_alt_k8_threshold, T_alt_k8_steps |
| 27 | fleet K-int8: dense 32k 0.106 (+0.9 %), 128k 0.098 (+4.2 %); MoE 32k 1.946 (+4.2 %), 128k 1.413 (+12.2 %), 1M 0.397 (+27.2 %); full KV-int8 0.107 / 0.101 / 2.031 / 1.609 / 0.547 (+75.3 % at 1M) | | D (D4 model) | [ALT-6-fleet-*] T_alt_k8_fleet |
| 28 | shared prefix: KV per layer = kv_tok·((L − L_s)·B + L_s·passes)/R with passes = ⌈B·g/64⌉; dense B = 16 (4 passes): 12 299 → 11 146 / 7 687 / 4 228 µs at L_s = 4k / 16k / 28k → 1.108 / 1.252 / 1.439 (+3.8 / +17.3 / +34.8 %); MoE (1 pass) 2.414 / 2.605 / 2.828; gain iff passes < B | | D (L_s U — H12) | [ALT-7-*] T_alt_prefix_cells, T_alt_prefix_iff |
| 29 | lazy rescale: S4 block (128 tokens, mt = 8) DDR-bound without the merge iff c_V ≤ 7 (ρ32 = 1) / 3 (ρ32 = 2); t = 16 32k: two-pass 1 554 / S4 1 032 / lazy 787 µs (native), 1 558 / 1 522 / 1 187 (native exp, tree), 6 802 / 7 140 / 6 471 (worst); 1M 49 209 / 32 388 / 24 611 …; lazy ≤ S4 and lazy ≤ two-pass on every corner | iff | D (∀ c_V; D3 model) | [ALT-8-*] T_alt_lazy_threshold, T_alt_lazy_dominates |
| 30 | lazy-rescale margin: P ≤ exp(μ) with μ = 8 → ≤ 2 981 < 65 504 (f16 max); L0C with one O region = 3 × 64 + 64 = 256 KiB at mt = 8 | | A (exp is transcendental: DEFINITION of μ; the L0C sum D) | T_alt_lazy_l0c |
| 31 | dominated: dense K-split net +2 µs (0.6 %) before any sync; specialization ≤ 58.2 GB/s (3× bytes); expert-parallel across dies −3.6 % (138.94 ms); zero-copy/NUMA/polling ≤ T_x = 1 497 / 1 480 µs; token dropping ×1.9 at 50 % pairs; rows-cliff B = 64 at 4k: dense 5.314 (×3.2), MoE 5.618 (×1.9), L_max(64) at 32k = 8 613 / 30 090 | | D | [ALT-9-*] T_alt_dom_ksplit, T_alt_dom_specialization, T_alt_dom_expert_parallel, T_alt_dom_p2p, T_alt_dom_rowscliff |
| 32 | the 8-die primary cells are unchanged by every alternative that is switched off (every alternative is the D4/D3 model with one term changed; the "today" columns reproduce fleet.lean / attn.lean's numbers exactly: 2362.31 / 133.84 ms, 776 / 24 606 µs) | identity | D | (all labels) T_alt_baseline_identity |

Hypothesis variables carried explicitly (both endpoints to be proved): the W4 core-slab time T_cold ∈ [197 844,
1 371 124] (ovl … break-even) and the unpack rate ∈ [8, 53] tenths; the A-lift cost a ∈ [0, 3 285] ns; c_sync ∈
[0, 108 430] ns; c_pg ∈ [0, 6 005] ns; c_V ∈ {7, 12, 28, 33}, ρ32 ∈ {1, 2}; the per-die runtime overhead (H8, 2 GiB
primary); λ = 91 µs (DESIGN-4's bracket 10 / 500 carries over: the instance exchange is 8 λ + 28 µs); the
popularity family (uniform / Zipf(1.0)); the prefix length L_s ∈ [0, L]; the quantizer op count 8; the W4 int4
share x ∈ [0, 1000] ‰ (the fit theorems are iffs in x).

**Formalizable for the Lean round (threshold or bound theorems):** rows 3, 4, 6, 11, 16, 19, 23, 26, 28, 29 are
iffs or ∀-bounds over a single explicit variable and close by `omega`/`decide` on the integer model (row 19 is a
255-case `decide`; row 13 needs ℚ or a scaled-Nat harmonic sum; row 30 defines μ rather than proving a
transcendental bound). Rows 5, 8–10, 14, 24, 27 are cell identities on the imported fleet/attn models (transcribe
`inst_step` and `fleet_k8` as functions of the same constants; their "today" values must match fleet.lean's
`T_step_*` theorems — row 32). Rows 1, 2, 15, 17, 18, 20, 21, 22, 25, 31 are closed-form arithmetic.
