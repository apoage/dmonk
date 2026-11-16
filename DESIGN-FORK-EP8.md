# DESIGN-FORK-EP8 — expert and head placement across the 8 dies, with a host all-reduce per layer

> **CHALLENGE-ROUND-4 FORK DRAFT (2026-11-15; `PROOF-COVERAGE-CHECK.md` §7, `proof/check.lean` `Chk.ForkEP.*` (10 theorems),
> `proof/fleet.py` `[FORK-EP-*]`).** Append-only: this document does not change DESIGN-4; it is the family the dominated-
> alternatives table dismissed on a premise the measured record no longer supports. Every number is DERIVED (D) from HW-MAP rows (M)
> and the printed planner numbers; the four premises that must be MEASURED before it can rank are listed in §5 with the ladder in
> §6. Convergence: a 2-way card-pair variant of this family was drafted in challenge round 2 (branch `challenge-round-2`, "DESIGN-
> FORK-TP2", read here only through its commit message) and its gate — the card-pair ≥ 1.9× concurrency — has since been MEASURED
> and met (HW-MAP, season h); the cross-problem reviewer of this round arrived at the same family independently.

## 0. The premise that moved, in one paragraph

DESIGN-4 §5 prices "tensor-split worked" at 6.2× (dense) / 3.5× (MoE) for one sequence and dismisses it because "the runtime
faults on it"; ALTERNATIVES §4 kills "expert-parallel across the card's two dies" (−3.6 %: "no concurrency, dies alternate") and
"split-KV across dies" ("errata #11 fault") on the same reading. Erratum 11 (HW-MAP) records two facts about the **vendor serving
runtime**: its tensor-split of one op faults, and its layer-split loop alternates dies. Since then HW-MAP's concurrency rows measured
(M): two instances on disjoint dies at 1.99× ("no driver-level cross-process serialization"); **one process, two threads, both dies
of one card, weight-streaming class: 1.000–1.001 of the solo sum**; two cards at 2.0×; and custom kernels are mandatory for any
concurrent serving anyway (the vendor op path aborts on multi-sequence decode). Every cross-die exchange bounces through the host at
the measured λ = 12.2 µs per direction (unchanged under D2D load). So the split family needs no runtime feature: per-die custom
launches from per-die host threads (the measured pattern) and a host-side reduce of 8 × 8–64 KiB partials per layer — the same
class of host work the serving bridge already does per step. What is UNMEASURED is the 8-die generalisation (§5).

## 1. Mechanism — three rungs

**EP-A (experts placed; attention stays on the layer-split chain).** The 256 experts of every layer are placed over the 8 dies
(32 per die, round-robin by a host-side popularity census if available, else by index): 28 × 32 × 3 × 16 MiB = **45.1 GB** of
expert slabs per die (`Chk.ForkEP.ep_memory`). Attention (QKV, the attention kernel, W_o), the norms and the router stay where the
chain puts them (die p holds its 3–4 layers' attention weights and KV). Per layer: the owning die runs attention → the router → the
host gathers x (8 KiB) and the top-8 expert ids → the host dispatches x to the ≤ 8 dies owning the active experts → each of those
dies runs the expert kernel over ITS active experts (1–8 of them, the measured kernel at M0 is the 8-expert launch) → the host sums
the partial y's (≤ 8 × 8 KiB f32) → the next layer's die. Per-layer expert time = the MAX over dies of (active experts on that die)
× 3 slabs × 101 189 ns, instead of 8 × 3 × 101 189 serially.

**EP-B (+ one KV head per die).** The 8 KV heads (the planner's shape: H_kv = 8, d = 128, g = 4) are split one per die for ALL
layers: die h holds Q/K/V/W_o column slices of head h for every layer and the KV cache of head h (die-local K/V append, as erratum
11 requires; 120.2 GB / 8 = 15.0 GB at 1M), and runs head h's attention over its 8 cores with the split-KV-token core map (the
measured ~40 ms/step lever on the 4-kv serving model, there at 4 × 2 cores). Per layer: the host broadcasts the post-norm x (8 KiB),
each die projects its head's Q/K/V (1/8 of the attention GEMM bytes), appends K/V, runs attention, projects with its W_o slice; the
host sums the 8 W_o partials, adds the residual, norms, routes, and the expert phase of EP-A follows. Two host rounds per layer.

**TP-8 (the corpus's own what-if, re-read).** Column-split EVERY GEMM — including each active expert — 8-way so that every die
streams 1/8 of every byte: perfectly balanced, 8× the weight bandwidth, but with 2 MiB expert slabs cut to 256 KiB per core and
dense 8192-column slabs to 1024 — a tile regime the measured kernels have not run at (E21's measured 64–256 KiB pages are the
closest datum). DESIGN-4 §5′ already prices it at round-3 constants: dense 0.653 (6.2×), MoE 6.369 (3.5×) for one sequence; at the
realized launch and M0 the cross-problem reviewer's re-pricing is MoE 7.3 / 10.7, dense 0.69 / 0.78. It is the upper rung and the
one with the most unmeasured kernel work; EP-A and EP-B use only measured kernel shapes.

## 2. Errata mapping (a fork that ignores an erratum is dead on arrival)

| erratum / row | how the fork meets it |
|---|---|
| #11 cross-die exchanges bounce through the host; no P2P; tensor-split op faults | only host bounces are used (λ = 12.2 µs, M); no vendor split op; per-die launches of the existing custom kernels |
| #15 threads must set their device context; cold-pipe first handshake | one host thread per die (the measured intra-card two-thread pattern); warm launches |
| #25 A-slot staging: offset-0 4 KiB blocks or the 2 × 32 KiB legs | the broadcast x_q lands exactly as the expert kernel stages it today (the production route) |
| #20 vector-built A operands ride a DDR bounce | x arrives from the host into DDR: the proven DDR → S1 staging |
| #19 no f16 accumulate chains across barriers | untouched: the expert kernel is i8×i8→i32; EP-B's attention is the shipped kernel |
| #29 / #31 per-block scalar crossings; readback races | the reduce is on the HOST; no new in-kernel scalar path; the deferred guard's one end-of-step read is unchanged |
| #26 / #30 scalar-loop depth; nest boundaries | per-die nests are the production kernels'; the router's top-k stays behind a launch boundary or on the host |
| #16 same-dst spacing | the expert kernel's chains are the production class (≤ 64 deep, interleaved) — fewer experts per launch shortens them |
| #32 / #34 harness deception; arena stride from the allocation | the ladder's oracles compare against the SINGLE-DIE kernel's bytes on snapshotted inputs, never against a shared reference |
| the realized launch ≤ 36 µs (M, derived) / the 91 µs floor | carried as a bracket in the sync term (§3); the fork's line is 13.6× the sum |
| i32 saturation (M) | the [−127, 127] clamp is the production cast; partial sums of ≤ 8 experts are summed on the host in f32 |
| the 4-kv-head launch map (M) | EP-B is the 1-head / 8-core case of the split-KV-token map; UNMEASURED at that ratio (§5) |

## 3. The model and its cells (D; `proof/fleet.py` `[FORK-EP-*]`, `Chk.ForkEP.*`)

Inputs (all from the ROUND-7 planner and HW-MAP): the expert slab at M0 = 101 189 ns; the chain's step 127 788 019 ns at 32k
(1.956 tok/s/card); the deferred-guard cells 945.5 / 3 618.8 / 28 694 µs (the 4k cell is the legacy 213.5 µs — the deferred 4k
cell is U); the attention GEMMs 240 223 ns per layer; the head 3 008 800 ns; λ = 12.2 µs; the realized launch 36 µs.

**Load balance (D, uniform routing = A).** 8 active experts over 8 dies: the max per-die load has E = 680 849 / 262 144 = **2.597**
experts exactly (`Chk.ForkEP.emax_8_8` sums the 22 partitions of 8 with their multinomial weights to 8⁸); P(max ≥ 2 / 3 / 4) =
0.998 / 0.499 / 0.090; P(max = 8) = 8 / 8⁸. At B rows (D = 8B distinct experts, uniform): E[max] = 4.20 / 7.05 / 12.24 at B = 2 / 4 / 8
against the chain's 16 / 32 / 64. The worst case (all active experts on one die) is the chain's expert time (`ep_worst_case`).

**Orchestration (A, bracketed).** Per layer on the critical path: two host rounds (D2H + H2D at λ) + two launch latencies at the
realized bound = **120.8 µs**; the bracket top carries 500 µs (a serialized 8-leg round at 8 × 12.2 µs twice ≈ 195 µs sits inside it).
EP-A beats the chain at 32k iff the per-layer overhead is under **1 640 102 ns** (`ep_sync_line`; 13.6× the assumption).

| MoE, t = 1, tok/s per card | 4k | 32k | 128k | 1M |
|---|---|---|---|---|
| the ROUND-7 chain (trip-free) | 2.330 | **1.956** | 1.233 | 0.276 |
| **EP-A** (sync 120.8 µs / 500 µs) | 3.860 / 3.317 | **2.932** / 2.607 | 1.561 / 1.464 | 0.289 / 0.286 |
| **EP-B** (+ head split; attention ÷ 8, U) | 4.901 / 4.057 | **4.667** / 3.895 | 3.973 / 3.399 | 1.659 / 1.549 |
| worst routing (8 experts on one die) | 2.258 | 1.905 | 1.213 | 0.275 |
| batched EP-A at 32k, B = 2 / 4 / 8 | — | 3.988 / 4.938 / 5.673 (chain 2.249 / 2.431 / 2.534) | — | — |

Reading: EP-A is +50 % at 32k and +66 % at 4k with NO attention-kernel change and no new kernel shape beyond "fewer experts per
launch"; its downside under adversarial routing is −2.6 % (the sync). EP-B is the long-context lever: 3.2× at 128k and 6.0× at 1M,
where the chain is attention-bound on one die at a time. Against the corpus's chosen no-runtime route (V3, two 4-die instances with
the int4 tier: 3.52 tok/s/card for TWO sequences, i.e. 1.76 per sequence; dense 0.150 for two): EP-A at one sequence (2.93) beats V3
per sequence, EP-A at two rows (3.99) beats V3 at equal clients, EP-B dominates at every L, and the memory plan needs no int4 tier,
no erratum-19 merge, no E30, no H11 (63.6 GB per die at 1M, `ep_memory`).

## 4. Memory plan (D)

Per die: 45.1 GB of expert slabs (32 experts × 3 × 16 MiB × 28) + the chain's attention weights for its 3–4 layers (4 × 41.9 MB) +
embed / head (replicated or on dies 0 / 7: 2 × 0.53 GB) + KV/8 at 1M (15.0 GB) + 2 GiB runtime + 64 MiB workspace = **63.6 GB ≤ 86**
— 22 GB of headroom per die, enough to replicate the hottest experts (popularity-aware placement, H9) or to hold a draft model.
Dense under TP-8: 386.7 / 8 = 48.3 GB of weights per die + 1/8 of the model's KV (515.3 GB at 1M in f16 → 64.4 GB per die:
48.3 + 64.4 + 2.2 = 114.9 GB, infeasible, exactly as on the chain; KV-int8 257.6 / 8 = 32.2 GB → 82.7 GB ≤ 86: fits, as the
chain's KV-int8 escape does at 84.3).

## 5. What must be MEASURED on silicon before this fork can rank (the honest statement)

| gate | premise the cells assume | what is measured today | if it fails |
|---|---|---|---|
| **EP-1 — 8 dies stream concurrently from one host process** | each die's expert kernel at its solo rate while the other 7 stream | 2 dies of one card: 1.000–1.001 of the solo sum (one process, two threads); 2 cards: 2.0× (two processes); 8 dies × 4 cards: U | every EP-A/B cell collapses toward the chain; the 2-way card-pair rung (the round-2 fork) still stands on measured rows |
| **EP-2 — the host all-reduce round at 8 participants** | 2 rounds per layer at ≈ 2 λ + host sum; carried at 120.8 µs/layer with the 500 µs bracket | one 4 KiB leg: 12.2 µs per direction, unchanged under D2D load; 8 concurrent legs: U (a fully serialized round = 8 × 24.4 = 195 µs, inside the bracket) | EP-A dies only above 1 640 µs per layer (13.6× the assumption) — the gate is a measurement, not a hope |
| **EP-3 — the expert kernel at 1–4 experts per launch** | the per-slab time 101 189 ns holds when a launch carries E[max] ≈ 2.6 experts (fixed per-launch cost ≤ the chain's 8 µs + the launch itself) | M0 measured at 8 experts per launch (DESIGN-2's F = 8 µs is an ASSUMPTION the measured t = 1 / t ≥ 4 pair contradicts: ~28 µs implied) | +28 µs × 28 layers = 0.8 ms on an 85 ms step — inside the sync bracket |
| **EP-4 — the routing max-load on real traces** | uniform placement: E[max] = 2.597 of 8 | the generator families of DESIGN-2 (synthetic); H9 is UNMEASURED | adversarial collisions degrade toward the chain + sync (never below −2.6 % at 32k); popularity-aware placement and replication of the hottest experts (22 GB of headroom per die) are the levers |
| **EP-5 — EP-B's 1-head / 8-core token split** | attention time ÷ 8 per die at the deferred kernel's rate | the 4 × 2 split-KV-token map is the measured ~40 ms/step lever on the served 4-kv model; 1 head over 8 cores: U | EP-B falls back to EP-A (attention stays on the chain): 2.93 at 32k instead of 4.67 |

The cells are DERIVED at the planner's own constants; the fork is **not ranked** until EP-1 and EP-2 are measured. A fork that ignored
an erratum would be dead on arrival — §2 lists each one it meets; the one it RELIES on being a runtime property rather than silicon is
erratum 11's "no concurrent streaming", and that reliance is exactly what EP-1 tests.

## 6. The experiment ladder (observable failure modes only; continues ALTERNATIVES' H12 / E37)

| # | settles | setup | observable failure | decides |
|---|---|---|---|---|
| **S1** (host-only, one afternoon) | EP-1 at 2 dies with the split kernels | two threads, both dies of one card; each runs the expert kernel over a disjoint expert subset for the same token; outputs byte-exact vs the single-die 8-expert kernel on snapshotted x ×20 (differencing on x; prime-period patterns per erratum 21); per-die timers | output mismatch (cross-talk); the sum of per-die times > 1.02 × the solo sum (serialization) | whether the family lives at 2 dies — the rung the round-2 fork needs |
| **S2** (host-only, 2 hours) | EP-2 | the per-layer all-reduce ×10³ at 2, 4 and 8 participants with host checksums; distribution of the round time; controls: (i) one leg removed must change the checksum, (ii) a never-written partial must be caught | a round above 1 640 µs at 8 participants; a checksum that passes with a leg removed (blind reduce) | the sync term; the 8-way vs 2-way rung |
| **S3** (one kernel session) | EP-3 | the expert kernel at 1 / 2 / 4 / 8 experts per launch, 20 reps, the E13-style accumulating oracle | per-slab time at 1–2 experts > 110 µs (fixed cost ≫ 8 µs); any oracle miss | the per-launch cost in the model |
| **S4** (host + one kernel session) | EP-1 at 8 dies, one MoE layer | one layer's 256 experts placed over 8 dies (4 cards); the layer's expert phase for 1 000 tokens of a real routing trace vs the chain's serial layer, exact per token (snapshot oracle); per-die timers + the card power witness (both dies of every card busy inside one step window) | any token's y differs from the chain's; one card's dies idle while another's stream (serialization at the trunk) | EP-A's 32k cell: if S1–S4 pass, EP-A ranks above V3 for MoE and the int4 tier is never built |
| **S5** (kernel session) | EP-5 | the attention kernel with one KV head over 8 cores (the split-KV-token core map at 1 × 8), the causal battery of DESIGN-3 (post-fix references derived from the spec), t = 1..16 | relerr > 1e-3; any residue cell wrong; per-layer time > 1/8 × the chain cell + 20 µs | EP-B's cells (3.2× at 128k, 6.0× at 1M) |
| **S6** (trace analysis, no silicon) | EP-4 | the routing histogram of the target model on real prompts (H9); the per-layer max-load distribution under index placement vs popularity-aware placement | E[max] > 4 at index placement | the placement policy; whether to replicate the hottest experts |

Order: **S1 → S2 → S4** (three host-only / bridge-level steps that decide the fork before any kernel work), then S3, S6, S5.

## 7. Risk register and the kill criteria

| risk | consequence | kill criterion |
|---|---|---|
| the 8-die concurrency does not scale past a card (host DMA, the die-1 link transiting die 0) | EP-A degrades toward 2-way (MoE 32k 3.62 at one client per the cross-problem reviewer's 2-way pricing) | S4: a card's dies idle while another's stream |
| the all-reduce is serialized by the driver | sync 195–400 µs per layer; EP-A still +45 % at 32k | S2: a round > 1 640 µs |
| hot-expert collisions under real routing | per-layer max load → 4–8 on popular layers | S6: E[max] > 4 at index placement and no gain from popularity-aware placement |
| the expert kernel's fixed cost at small launches | +0.8–2 ms per token | S3: per-slab > 110 µs at 1 expert |
| the 1-head / 8-core attention split is slower than 1/8 | EP-B → EP-A | S5 |
| erratum 32-class deception in the ladder's own oracles | a wrong EP that matches a wrong reference | every oracle above compares against the SINGLE-DIE production kernel on snapshotted inputs, never against a reference that shares the split's arithmetic |

## 8. Claims ledger for a proof session (labels ↔ theorems)

| claim | `proof/fleet.py` | `proof/check.lean` | status |
|---|---|---|---|
| E[max load] of 8 experts over 8 dies = 680 849 / 262 144 = 2.597; P(max ≥ 2 / 3 / 4) = 0.998 / 0.499 / 0.090 | [FORK-EP-emax] | `Chk.ForkEP.emax_8_8`, `tail_probs` | PROVED (exhaustive over the 22 partitions, weights to 8⁸) |
| the orchestration term 120.8 µs; the line 1 640 102 ns | [FORK-EP-sync] | `ep_inputs`, `ep_sync_line` | ASSUMPTION (the term) / PROVED (the line) |
| MoE 32k: EP-A 2.932 / 2.607, EP-B 4.667 / 3.895, worst 1.905 | [FORK-EP-32k] | `ep_cells_32k` | PROVED on the model; EP-1/2/5 UNMEASURED |
| 4k / 128k / 1M cells | [FORK-EP-4k/128k/1M] | `ep_cells_L` | PROVED on the model (the 4k attention cell is the legacy 213.5 µs) |
| the worst routing = the chain + the sync | — | `ep_worst_case` | PROVED ∀ a, s |
| batched EP-A at B = 2 / 4 / 8: 3.988 / 4.938 / 5.673 | [FORK-EP-batch-B*] | — (E[max] at 16 / 32 / 64 balls computed by DP in fleet.py; a Lean proof would enumerate 231 / 2 … partitions — deferred) | DERIVED |
| memory 63.6 GB per die at 1M | [FORK-EP-mem] | `ep_memory` | PROVED |
| the gate margin 13.6× | — | `ep_gate_margin` | PROVED |

## 9. The gate, decided in arithmetic (Mission B; `Chk.MissionB.gate_decided`, `s2_bound`, `[FORK-EP-gate]`)

The three host-only steps of §6 bound the fork before they run:
- **S1** (two dies of a card, concurrent split kernels) asks for nothing the MEASURED intra-card row has not shown: one process, two
  threads, weight-streaming class, 1.000–1.001 of the solo sum. The expert kernel is weight-streaming on its own die's DDR; the only
  shared resources are the host link and the host CPU, which the kernel does not touch while it streams.
- **S2** (the host round at 8 participants) fully serialized is 8 × 2 × 12.2 = 195 µs; two rounds per layer = 390 µs; the EP-A kill line
  is 1 640 µs per layer (4.2× above).
- **S4** (8 dies, one layer) composes the two measured facts (intra-card 1.000, cross-card 2.0×) over 4 cards × 2 dies; the bytes per
  layer (8 × 8–64 KiB) are 0.1 % of one card's link; the host sum is microseconds.

The most conservative composition of MEASURED constants — every leg of both rounds serialized and both launches at the 91 µs floor,
377.2 µs per layer — still gives **EP-A = 2.704 tok/s/card at MoE 32k (+38 %)**, 4.3× inside the line. The gate can therefore fail only on
a host-stack serialization that no standing measurement shows and that would contradict the card-scale 2.0× row. That is the honest
statement: not "unmeasured, so unknown", but "unmeasured, and every measured constant says it passes with ≥ 4× margin".

## 10. EP-S — speculative decoding on EP-A flips the MoE spec verdict (`eps_flip`, `eps_cell`, `[FORK-EP-S]`)

The corpus's MoE spec loss (T_spec_moe_loss: k = 3 loses unless α ≥ 0.85 / 0.82) is a bytes mechanism — the verify batch's 32 distinct
experts quadruple the expert stream on one die. Under EP-A the 32 experts spread over 8 dies with E[max] = 7.05 (DP over 8³²
assignments), so the verify step's expert phase is 2.08 ms per layer instead of 9.46 ms. Result (k = 3, draft as the planner prices
it, verify attention at the t = 1 cell): **gain iff α ≥ 0.610**; at α = 0.7, **3.368 tok/s/card vs 2.932** without spec (+14.8 %). On the
pessimistic reading (verify attention at the legacy measured t = 4 cell, 2 695.6 µs) the line is α ≥ 0.762. The corpus's UNMEASURED
E41 cell (the deferred kernel at t = 4) is thus exactly the experiment that decides whether MoE spec decode pays at α = 0.7 — Mission
B's preferred shape: an existing unmeasured cell promoted to a decisive one. EP-B does not help spec (its t = 1 step is already short
and the verify expert bytes dominate it: line ≈ 0.80).

## 11. EP-P — pipelined EP and the throughput table (`epp_bound`, `emax_16_8`, `b2_cells`, `[FORK-EP-B*]`, `[FORK-EP-P]`)

| MoE 32k, tok/s per card | B = 1 | 2 | 4 | 8 | 16 |
|---|---|---|---|---|---|
| chain (ROUND 7) | 1.956 | 2.249 | 2.431 | 2.534 | 2.589 |
| V3 two instances (2 sequences) | — | 3.878 | — | — | — |
| **EP-A** | 2.932 | **3.988** (exact: E[max of 16] = 4.2014) | 4.938 | 5.673 | 6.187 |
| **EP-B** (head split, U) | 4.667 | **7.091** | 9.869 | 12.606 | 14.961 |
| Π = 8 stage ring (branch 1, 8 sequences) | — | — | — | 13.414 | — |
| **EP-P bound** (interleaved sequences) | ≤ 20.4 (EP-A) / ≤ 19.8 (EP-B) per card at any N ≥ 2 | | | | |

E[max] at B rows (DP, D): 4.20 / 7.05 / 12.24 / 21.91 of 16 / 32 / 64 / 128. Reading: at two clients EP-A ties V3 (3.99 vs 3.88) and EP-B
doubles it; at eight, EP-B (12.6) matches the stage ring (13.4) at one third of the latency; interleaving sequences (EP-P: one
sequence's attention on its layer die overlaps another's expert phase on the other seven) is bounded by the per-die DDR time per
token, 20.4 / 19.8 per card — the fleet's weight roof minus imbalance. These rows ride the t ≤ 16 contract and, for EP-B, the head-split
gate EP-5; they are cells of the model, not measurements.

## 12. TP-8 dense, and the placement policy under skew (`tp8_dense`, `[FORK-TP8-dense-*]`, `[FORK-EP-zipf-*]`)

**Dense.** Column-split every GEMM 8-way (W/8 per die, 48.3 GB), attention die-local by layer, two host rounds per layer: dense 32k
**0.588** tok/s per card at the realized launch / **0.570** at the 91 µs floor (chain 0.104; ×5.5–5.7); with head-split attention 0.768 /
0.738. This is DESIGN-4 §5's own "tensor-split worked" row with its gate restated: not "the runtime faults" but "the 1 024-column /
256 KiB-per-core slab regime is UNMEASURED" (E21's 64–256 KiB pages are the nearest datum; the expert kernel's measured tile is 2 MiB
per core). Dense 1M under TP-8 needs KV-int8 (82.7 GB per die) as the chain does.

**Placement under skew (Monte Carlo, seed 0, 20 000 tokens, 8 of 256 distinct experts, popularity ∝ rank^−s).** E[max load]: rank
round-robin placement 2.57 / 2.45 / 2.27 at s = 0 / 1.0 / 1.5; contiguous blocks 2.56 / 4.91 / 6.57; random 2.57 / 2.51 / 2.52. The H9
popularity census (UNMEASURED) is the fork's placement input: with it, skew IMPROVES the balance (popular experts are spread by
construction); without it, random placement costs ≤ 0.1 in E[max]; contiguous placement is the one policy to avoid.

## 13. Claims ledger additions (Mission B)

| claim | label | theorem | status |
|---|---|---|---|
| the gate at the serialized-legs, 91 µs-floor composition: 377.2 µs/layer, EP-A 2.704 (+38 %), 4.3× inside the line | [FORK-EP-gate] | `Chk.MissionB.gate_decided`, `s2_bound` | PROVED on measured constants |
| EP-S: MoE spec (k = 3) gains iff α ≥ 0.610 (t = 1 attention) / 0.762 (legacy t = 4); 3.368 at α = 0.7 | [FORK-EP-S] | `eps_steps`, `eps_flip`, `eps_cell` | PROVED on the model; E41 decides |
| E[max of 16] = 4.2014 exactly (186 partitions, weights to 8¹⁶); B = 2 cells 2.249 / 3.988 / 7.091 | [FORK-EP-B2] | `emax_16_8`, `b2_cells` | PROVED |
| B = 4 / 8 / 16 cells; E[max] 7.05 / 12.24 / 21.91 | [FORK-EP-B4/8/16] | — (DP in fleet.py) | DERIVED |
| the pipelined-EP bound 20.4 / 19.8 per card | [FORK-EP-P] | `epp_bound` | PROVED (a bound) |
| K-int8-only lever 5.72 / 22.9 / 183 ms per token; fusion + K-i8 beats E29 on both caps | [CHK-B-ki8-*] | `ki8_lever`, `ki8_tie` | PROVED on the measured 2.13× |
| the erratum-12 counterfactual 2.715 / 0.192 / 3 dies | [CHK-B-w4alive] | `w4_alive` | PROVED (counterfactual) |
| two nibbles per byte not separable through the MMA; the unpack cap 24 % | [CHK-B-nibble] | `nibble_not_separable`, `unpack_cap` | PROVED |
| TP-8 dense 0.588 / 0.570 / 0.768 | [FORK-TP8-dense-*] | `tp8_dense` | PROVED on the model; the slab regime U |
| placement E[max] under Zipf | [FORK-EP-zipf-*] | — | DERIVED (Monte Carlo) |
