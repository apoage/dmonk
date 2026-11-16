# DESIGN-FORK-PIPE — host-scheduled multi-die concurrency on the unchanged int8 chain

> **FORK DRAFT (PROMPT-7 challenge round, 2026-11-15; `proof/fleet.py` `[FORK-*]`, `proof/fork.lean`
> `Fork.*` — 13 theorems, core Lean, 0 axiom / sorry / native_decide; independent recomputation in
> `proof/check.py` `[CHK-P]`, `[CHK-S]`).** This document forks DESIGN-4's partition choice. It does not
> rank until the ladder in §8 runs: every cell below is the round-7 step's own terms re-arranged
> (DERIVED), taken at a concurrency `c` that is MEASURED for pairs of dies and pairs of cards and
> UNMEASURED beyond. Three claims:
>
> 1. **A dismissal rests on a premise that moved.** ALTERNATIVES files sequence pipelining under
>    "runtime-dependent … not ours to build" and DESIGN-4 gates it on H4 ("does the runtime pipeline
>    independent sequences"). HW-MAP has since measured the mechanical premise three times — two
>    instances on disjoint dies at 1.99×, one process with two threads on both dies of a card at
>    1.000–1.001 of solo-sum, two instances on disjoint cards at 2.0× — and measured that the stock
>    runtime batches one graph per step. So H4 as posed is answered (the stock runtime does not
>    pipeline) and is the wrong question: the dies do not serialize each other, and the scheduler that
>    exploits it is host code. The corpus's own rank-1 plan (V3) already runs on exactly this premise.
> 2. **At equal demand the unchanged chain beats V3.** Two sequences staggered along the full-int8
>    8-die chain give MoE 32k **3.853** tokens/s/card against V3's 3.519 / 3.449 (+9.4 % / +11.7 %) at
>    any equal `c`, with no int4 tier, no cold chain, no megabyte-margin fit, and 129.7 ms per token
>    instead of 142.1. Dense: 0.208 against 0.149 / 0.140 — and dense V3 also loses to two rows simply
>    batched on the chain (0.198). The same plan continues to Π = 8 without a reload: 13.832 / 0.803.
> 3. **The number that was retired as an error is this plan's cell.** Round-4 C-3 corrected the
>    `[R7-inst-moe-32k]` print (3.853) because it "ran the 8-die x = 0 step for the 4-die instance".
>    It did — and the 8-die x = 0 step at c = 2.000 is precisely two pipelined sequences on the chain.
>    `T7r_inst` is a true theorem about this fork, mislabelled as V3.

Number tags: **M** measured (HW-MAP row), **D** derived (label / theorem), **A** assumption,
**U** unmeasured. Anchors are round 7's: M0 slab 101 189 ns, deferred cell 945.5 µs trip-free and
1 015.34 µs at the measured 8 % retry share, λ = 12.2 µs, launch 91 µs primary / 36 µs realized.

## 0. The cells (32k, t = 1, tokens/s per card)

| plan | gate | MoE | dense | per-token latency (MoE) |
|---|---|---|---|---|
| one sequence on the 8-die chain (today) | none | 1.926 | 0.104 | 129.7 ms |
| **V3** — two 4-die instances, minimal int4 tier (DESIGN-4 §1.8) | H10 (2-card), H11, E30, E29 | 3.519 / 3.449 | 0.149 / 0.140 | 142.1 / 144.9 ms |
| two rows batched on the chain | none (M: batching works) | 2.210 | **0.198** | 226.2 ms per 2 tokens |
| **P, Π = 2** — two staggered sequences on the chain | P1 | **3.853** (3.834 at c = 1.990) | **0.208** | 129.7 ms |
| P, Π = 4 | P3 | 7.707 | 0.416 | 129.7 ms |
| P, Π = 8 | P4 | **13.832** (15.415 with a balanced split) | **0.803** | 129.7 ms |
| S — one sequence, each layer step on all 8 dies | S1–S4 | 6.556 | 0.650 | 38.1 ms |

Sources: `[FORK-pi-*]`, `[FORK-vs-v3-*]`, `[FORK-vs-batch-moe-32k]`, `[FORK-split-*]`;
`Fork.P3_cells_moe`, `P3_cells_dense`, `P4_cells`, `S1_cells`; V3 recomputed by the model in
`[FORK-v3-moe-32k]` and independently in `Chk.C2_instance_cells`. At the realized launch bound the P row
reads 2.103 / 4.206 / 8.413 / 15.121 (MoE) and S reads 9.178.

The comparison that DESIGN-4 §10 and ALTERNATIVES rank #1 make is V3's two sequences against the
chain's one. Like for like:

- **MoE.** `Fork.P4_dominates_v3`: for every `c`, tps(c, T_inst) ≤ tps(c, T_chain), because
  T_chain = 129 743 539 ns < T_inst = 142 057 473 ns — the int4 tier makes each instance token slower
  and both plans spend the same two streams. `Fork.P5_thresholds`: pipelining clears the single chain
  for any c ≥ 1.001; V3 needs c ≥ 1.095 / 1.118.
- **Dense.** V3's step is 3 337 ms against the chain's 2 403 ms, so replication needs an aggregate
  concurrency of 2.643 to reach what two batched rows give at 1.0 (`Chk.S1_dense_batching`). It is
  dominated at every reachable `c`, before pipelining enters.

## 1. Mechanism — member P (sequence pipelining)

The partition is DESIGN-4 §1 (a)–(f) unchanged: one full-int8 image over the 8-die chain
d1, d0, d1, d0, … with 7 inter-die boundaries. What changes is who advances it.

- **Workers.** One worker per die owns that die's layer block: its weights, and the KV of its layers
  for every sequence in flight (die-local, as today). Two build routes, both inside measured classes:
  **R1** — one process, one thread per die, each thread setting its own device context and launching
  the existing custom kernels (the intra-process row: solo 151.3 / 150.9 GB/s → 302.4 concurrent);
  **R2** — one runtime instance per die holding its layer sub-range as its own graph (the two-instance
  rows). R1 needs nothing the serving bridge does not already do per die; R2 needs a graph whose input
  and output are hidden states (U).
- **Shuttle.** A sequence's hidden state leaves die p and enters die p + 1 through the host — the same
  8 KiB (MoE) / 32 KiB (dense) and the same links as today's chain hop, at the measured 12.2 µs per
  direction. Logits leave the last die, the host samples, the id returns to die 0. Nothing crosses
  die-to-die; no op is split.
- **Schedule.** Π sequences are admitted a fraction of a step apart; each die serves its queue in
  order. A die holds one sequence for its block time (`[FORK-blocks-*]`: MoE 18.07 ms on the 4-layer
  dies, 13.56 ms on the 3-layer dies, 16.77 ms on the lm_head die; dense 298.9 ms, 311.1 ms with the
  head), and the blocks sum to the chain step exactly (`Fork.P1_blocks_*`). Up to seven sequences never
  want the same die at once — 7 × max block ≤ T_step < 8 × max block (`Fork.P2_collision_free`) — so
  throughput is Π / T_step; the eighth makes the slowest die the bottleneck and throughput is
  1 / max block. Hence `pipe = min(c / T_step, 1 / max block)`.
- **What stays as it is.** Per-sequence latency (the chain is still a serial dependency for one
  sequence — HW-MAP's "+1.4 %"), every kernel, every layout, the load image. Moving from Π = 2 to
  Π = 8 is a scheduler setting.

## 2. Errata map

| constraint | how member P meets it |
|---|---|
| #11 layer-split only; tensor-split faults; exchanges bounce through the host | whole layers per die; every hand-off is the existing host bounce; no op spans dies |
| #12 no int4 path | full int8 everywhere — the reason this plan needs no cold tier |
| #15 each thread must set its device context | R1's per-die threads each set one; this is a build rule, tested in P1 |
| #19 / #20 / #25 (f16 accumulate, US → S1 A-slot copy, A-staging offsets) | untouched: no new kernel path. V3's cold tier is exposed to all three (ERRATA-IMPACT §2) |
| #32 harness-deception class (shared-page-table clobber, arena coincidence) | each sequence owns its page tables and spans; P1's oracle plants distinct contexts so a cross-sequence read is visible, not self-consistent |
| #34 stride from the allocation, snapshot rather than share | KV arenas hold Π sequences per die: strides come from the allocation; the test reads snapshots |
| #33 / firmware note (stale binaries; enumeration order ≠ PCIe order) | every rung records binary mtime, a trace line and the PCIe identity of each die |
| stock vendor op path aborts on multi-sequence decode | irrelevant: each die's launch carries one sequence; custom kernels only |
| thermal (141 W per card sustained, 150 W class) | all eight dies streaming is the measured sustained load on every card (U at four cards at once — P4 logs it) |

## 3. Memory (`[FORK-mem-*]`, `Fork.P6_memory`)

Each die holds the KV of its layers for Π contexts. On the tightest dies the budget is
L × Π ≤ 1 925 823 tokens (MoE) / 551 253 (dense), f16 KV, at the assumed 2 GiB + 64 MiB overhead (A):

| | Π = 2 | Π = 8 | 1M context |
|---|---|---|---|
| MoE | L ≤ 962 911 | L ≤ 240 727 | Π = 1 only |
| dense | L ≤ 275 626 | L ≤ 68 906 | infeasible in f16 at any Π (as today) |

At 32k with eight contexts the tightest die keeps 27.2 GB (MoE) / 17.7 GB (dense) free. V3's fit
leaves 24.5 MB on the worst die, on an assumed overhead, before the round-4 page-waste term — and
that term (29.3 MB per 7-layer die at 256 KiB pages) already exceeds the margin (`Chk.C5_page_waste`).

## 4. What this plan does not do

- **It does nothing for one sequence.** With a single stream in flight member P is the chain. V3 has
  the same property (its second instance is idle); member S (§6) is the latency lever.
- **It needs Π sequences in flight.** The cells are throughput cells under demand, exactly as V3's,
  B = 16's and the spec cells are.
- **MoE blocks are unequal** (4 / 3 layers): Π = 8 loses 10.3 % against a balanced split (13.832 vs
  15.415). A sub-layer split would recover it and is not proposed here.
- **Long context narrows it.** The L × Π budget above; and the 128k / 1M cells are trip-free while the
  retry share is measured at 32k only (`[CHK-T]`).
- **It inherits the planner's absolute error.** No DESIGN-4 cell is validated against an end-to-end
  measurement, and on the one measured serving accounting the planner's launch + quant terms are
  2.1×–4.2× the measured non-GEMM share (`Chk.W1_overhead`). The ratios in §0 are robust to that — P,
  V3 and the chain share every term — the absolute tokens/s are not.

## 5. What is measured and what is not

| premise | status | row |
|---|---|---|
| two dies of one card stream concurrently from one process | **M** — 1.000–1.001 of solo-sum | HW-MAP concurrency section |
| two instances on disjoint dies / disjoint cards | **M** — 1.99× / 2.0× | same |
| the host bounce under load | **M** for one bounce under saturating D2D (12.2 µs, unchanged) | host-bounce row |
| continuous batching shares one graph per step | **M** — the stock runtime does not pipeline | same section |
| **the measured class is "weight-streaming", solo 151 GB/s** — not the 174.6 decode kernel, not a layer-split chain with bounces in flight | caveat on every M above | — |
| concurrency of 4 and 8 dies, c(4), c(8) | **U** | P3, P4 |
| per-die workers advancing different sequences of one image, bit-identically | **U** | P1 |
| the bounce with Π transfers in flight | **U** (trunk load is 0.84 % of 27.6 GB/s at Π = 8 by `T_pipelining_trunk`) | P2 |
| per-die overhead and workspace with Π contexts | **A** (2 GiB + 64 MiB; GiB of slack) | P1 logs free memory |
| a hidden-state-in / hidden-state-out graph per die (route R2 only) | **U** | P5 |

## 6. Member S — one layer step on all eight dies (the latency lever)

DESIGN-4 §5 already prices this as the "tensor-split worked" what-if and stops at "the runtime faults
on it". The fault is the runtime's op-split (#11). A host-level split is a different object: each die
holds an eighth of every layer (45.3 GB MoE / 48.3 GB dense — `Fork.S2_memory`), runs a complete
custom launch on its share (an N-split of each GEMM, a head-split of attention — no partial sums to
reduce, only slices to gather), and the host gathers and re-broadcasts the activation twice per layer
at the measured bounce.

On the round-7 anchors the model's own formula gives, for ONE sequence (`[FORK-split-*]`,
`Fork.S1_cells`): **MoE 38.1 ms → 6.556 tokens/s/card (3.4× the chain)**, launch-bound (47 % of the
step at 91 µs; 9.178 at the realized bound); **dense 384.3 ms → 0.650 (6.2×)**. With one sequence in
flight S is ahead of P; from four sequences up P is ahead (`Fork.S3_regimes`).

Member S stands on weaker evidence than P. HW-MAP measures independent streams running concurrently;
it does not measure several launches of the same layer step overlapping, nor a per-layer host round in
the serving loop (the bounce row is 12.2 µs; the serving row's H2D leg is 35.4 µs per step), nor
whether the #11 fault comes from op-splitting or from same-step multi-die scheduling. It is carried
here because its dismissal is the same stale premise, not because it is ready to rank.

## 7. What must be MEASURED before this can rank

1. **P1** — two staggered sequences on one card's two dies run at ≥ 1.9× one, and every token of both is
   bit-identical to its solo run. This single host-side experiment decides the shape of the plan.
2. c(4) and c(8), with the bounce in flight (P2–P4).
3. Free memory per die after load with Π contexts (replaces the 2 GiB + 64 MiB assumption).
4. For S only: same-step launches on two dies take max, not sum (S1).

Until 1 passes, V3 remains the corpus's Π = 1 fallback for MoE. Dense V3 does not need to wait: it is
dominated by batching on measured premises.

## 8. Experiment ladder (every rung has a content oracle; timing alone decides nothing)

| rung | what | oracle / observable failure | decides |
|---|---|---|---|
| **P0** | host only: from an existing serving trace, per-die busy intervals of one sequence | Σ blocks + λ against the measured step; a gap > 5 % means the block model mis-attributes time | whether `[FORK-blocks-*]` describes the stack |
| **P1** | the existing 2-die layer-split image, two decode contexts, two host threads (each sets its device context), sequence B admitted half a step after A | (i) every token of A and B bit-identical to its solo run, ×20 seeds, prompts planted with prime-period patterns longer than L (#21); (ii) each sequence's attention reads its own context — plant distinct contexts, a clobbered page table shows as B's text under A's prompt; (iii) aggregate ≥ 1.9× → pipelined, ≈ 1.0× → the dies serialize; (iv) card power at two-die load as the independent witness | **the fork** |
| **P2** | λ with 2 / 4 / 8 bounces in flight, 4 KiB sync legs | content-checked payloads; pass if λ ≤ 2 × 12.2 µs | the exchange term at Π > 1 |
| **P3** | two cards, four dies, Π = 4 | as P1, per sequence; PCIe identity pinned per die | c(4) |
| **P4** | four cards, Π = 2 … 8 | as P1; per-card power and hotspot logged against 141 W / 72 °C | c(8), thermal |
| **P5** | route R2 only, if R1 fails: a per-die graph of a layer sub-range | bit-identity of its output against the same layers inside the chain, differencing on the input | whether R2 exists |
| **S1** | two custom launches of the SAME expert-kernel step on a card's two dies (then the attention class) | i32 partial sums against a host oracle ×20, differencing on the operands; wall time = max (pass) or sum (dead) | member S at all |
| **S2–S4** | one MoE layer N-split over two dies; head-split attention at 32k; eight-way | bit-compare with the single-die layer; the attention exactness battery | member S's cells |

Order: P0, P1, P2, then P3 / P4 as cards are available; S1 in parallel with P2 (it is one afternoon on
one card). Build cost before P1: none on the device; the two-thread harness is the same class as the
one that produced the intra-process concurrency row.

## 9. Decision rule

- **P1 passes** → the plan is the single full-int8 chain with Π = min(sequences in flight, 8). V3, its
  int4 tier, the cold-chain kernel (E30) and the per-die fit (H11) are retired for both shapes; E29,
  the megakernel and every kernel lever keep their value (they shorten every block).
- **P1 fails by serialization** (aggregate ≈ 1.0×, outputs correct) → H4 is closed for good and V3
  stands as the MoE plan. Dense V3 stays dominated by batching.
- **P1 fails by content** (any token differs from solo) → a scheduler bug class (page tables, spans,
  contexts); fix and rerun — this is the failure mode the np-cell history already met once.
- **S1 passes** → S becomes the single-stream latency plan and a separate design round prices the
  per-layer host rounds; it does not replace P.

## 10. Risks

| risk | what would show it | consequence |
|---|---|---|
| the measured concurrency does not transfer from a weight-streaming class to the full decode stack | P1 (iii) below 1.9× | the cells scale by c; P stays ahead of V3 at any equal c (`Fork.P4_dominates_v3`) |
| c falls off beyond pairs (host threads, PCIe root, power) | P3 / P4 | Π saturates below 8; the plan is still ≥ V3 from Π = 2 |
| host bounce queues at Π = 8 | P2 | adds to every block; 0.84 % of a trunk says no, a measurement must |
| per-sequence state shared by accident | P1 (i), (ii) | wrong text with clean timing — the reason P1's oracle is content, not rate |
| demand is one sequence | — | P buys nothing; see member S |
| retry share grows with context or batch | `[CHK-T]`; a trip count at 128k | every long-context cell, in every plan, moves together |
