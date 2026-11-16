# PROOF-COVERAGE-CHECK — the PROMPT-7 challenge round (2026-11-15)

An independent adversarial re-review of the corpus: re-derivations under a new namespace, a taint
ranking, the decision-sensitivity list, the dominated-alternatives table re-scored, and one fork.
Nothing in an existing proof or model was edited; `proof/fleet.py` gained an appended `[FORK-*]`
section; design text carries in-place notes marked **challenge:**.

**Verdict in one paragraph.** The arithmetic of the corpus holds: 59 independent re-derivations found
no load-bearing number that fails to reproduce from its inputs, and one ns-level print that does not
(§2, C3). What does not hold is part of the decision layer built on that arithmetic. The rank-1 fleet
plan (two 4-die instances with an int4 tier) is scored against a one-sequence baseline; at equal
demand the unchanged int8 chain beats it — for dense by plain batching on measured premises, for both
shapes by staggering sequences, which the corpus parked as "a runtime capability, not ours to build"
while measuring its mechanical premise three times for the plan it preferred (§7, DESIGN-FORK-PIPE.md).
Around that: a PROVED exactness row that is a wrap-arithmetic theorem on a part measured to saturate,
an attention layer still carrying a trip premise HW-MAP replaced 40-fold, an E40 bound overstated
1.8×, and a planner never compared with an end-to-end measurement.

## 1. Build status

| | |
|---|---|
| `proof/check.lean` | namespace `Chk`, **59 theorems**, core Lean 4.35 only, standalone (`lean proof/check.lean`) and under `lake build` (target `Check`); 0 `sorry` / `axiom` / `native_decide`; `#print axioms` on every theorem: none (35), or `propext` + `Quot.sound` (24, from `omega`) |
| `proof/check.py` | the independent model: imports nothing from the corpus models; prints `[CHK-A]` … `[CHK-Z]` (162 lines) with AGREE / DIFF against the corpus's printed numbers |
| `proof/fork.lean` | namespace `Fork`, **13 theorems**, same rules, target `Fork`; axioms: none (10) or `propext` + `Quot.sound` (3) |
| `proof/fleet.py` | `[FORK-*]` section appended (17 lines of output); **the first 694 output lines are byte-identical** to the pre-round output; `model.py`, `moe.py`, `attn.py`, `alt.py` outputs byte-identical (unchanged files) |
| `lake build` | 19 jobs, clean (`Model`, `Smoke`, `Moe`, `Fleet`, `Attn`, `Alt`, `Cheat` untouched; `Check`, `Fork` added to `lakefile.toml`) |
| method | re-derivations and every edit by the coordinating session; four read-only reviewer sub-sessions (problems 1+2, problem 3, problem 4, the cross-problem layer) swept the long documents. Each reviewer finding used below carries who verified it: **V** = re-derived here (theorem or `[CHK-*]` line), **T** = checked here against the cited text, **R** = reviewer-verified only, **S** = suspected, not demonstrated |

## 2. Verdicts

| Problem | Verdict | What drives it |
|---|---|---|
| 1 — dense decode matmul | **WEAKENED** | The headline gate is MET by measurement (174.6 GB/s ≥ 120, flat m ≤ 16). The flat m = 1..64 target fails on silicon (81 / 59 / 43 GB/s at m ≥ 24) and m = 64 sits above the low-figure compute ridge (N2); W4 ≥ 120 is dead (erratum 12); the numerics gate is certified only against a quantizer-sharing reference (R1); the banner quoted 137.8 GB/s and a retracted k = 64 anomaly as current |
| 2 — MoE grouped GEMM | **WEAKENED** | Scheme S is confirmed by M0 (165.8 GB/s) and its overflow count reproduces (M1). The region-difference exactness is proved in wrap arithmetic and from a zero start, on a part measured to saturate with no zero-init (Q1–Q3): exact only for a bounded launch state, which nothing bounds or measures. The W4 half is void (erratum 12 resolves E19 against) |
| 3 — decode attention | **WEAKENED** | Measured cells, drift bound, break-evens and the E40 lines all reproduce (I, J, K). The round-6 layer still carries the 0.087–0.22 % trip premise as current (measured: 8 % / 5.5 %); the retry share is unmeasured beyond 32k / t = 1 and plausible extrapolations cross the 64–65 % break-even at 1M (T1, T2); the E40 bound and gate ignore the per-step intercept of the corpus's own fit (U1, U2); the lever ranking omits K-int8 (V1) |
| 4 — fleet planner | **WEAKENED**, one decision cell **BROKEN** | `T_min_dies` is sound and stronger than stated (A2). Every round-7 cell reproduces (B, D, E, G, H). **Dense V3 ("+49 %", ranked 1st) is dominated by two batched rows on the chain** at every c ≤ 2 (S1) — broken as a ranking. MoE V3 is dominated at equal demand by two staggered sequences (fork), pending P1. `T7r_inst` and ledger row R7.4 prove the superseded 3.853 under V3's name; the instance fit omits the corpus's own page-waste term (C5); the spec line is stale at the round-7 anchors (H4); no cell is validated end to end (W1) |
| 5 — alternatives | **WEAKENED** | Stale-premise dismissals recur in the class the table once caught (sequence pipelining, expert-parallel across a card's dies, split-KV, rows-cliff); over-scores on the megakernel, two-tier pages, dense replication; one MEASURED label with no HW-MAP row (§6) |
| CHEAT layer | **WEAKENED** (number-moving) | "12.5 % of compute peak" is issue occupancy (N1); the ridge's 17.8 is the low end of a measured range and inconsistent by 2× with the MMA-issue row (N2, Y1); candidate #3's "1.04×" is a slowdown (Z1). Every guardrail's kill survives |

## 3. The `Chk` ledger

Each row: the corpus claim, the theorem that re-derives it by another route, the verdict.
**AGREE** = the corpus number reproduces; **STRONGER** = re-proved in a more general form;
**DIFF** = the corpus number does not reproduce; **NEW** = a cell the corpus does not carry;
**WEAKENS** = the number reproduces and the claim built on it does not.

| # | Corpus claim (theorem / label) | `Chk` theorem | Route here | Verdict |
|---|---|---|---|---|
| A | resident totals 386.72 / 363.00 GB (`T0_*`) | `A1_totals` | shape arithmetic from PROBLEM-4's parameters | AGREE |
| A | four dies cannot hold the model (`T_min_dies_dense_4`, `_moe_4`: whole-layer counts) | `A2_four_dies_any_split` | ∀ byte splits w0 + w1 + w2 + w3 = total — sub-layer, per-expert, per-row | **STRONGER** |
| A | five dies fit (`T_min_dies_5_*`) | `A3_five_dies` | iff over the unmeasured overhead: ≤ 5.72 GB dense / 7.75 GB MoE | STRONGER |
| B | round-7 MoE cells 1.956 / 1.926 / 1.935, 128k 1.233, 1M 0.276, realized 2.103 (`T7r_step_cells`, `_realized`) | `B1_inputs`, `B2_moe_cells` | the step rebuilt term by term (closed form, own exchange sum) | AGREE |
| B | dense 0.104 | `B3_dense_cell` | same | AGREE |
| B | — | `B4_composition` | MoE 32k layer: 53.8 % slabs, 22.5 % attention, 14.1 % launches at 91 µs | NEW |
| C | minimal int4 share 182 / 170 (`T3r_inst_fit_moe_32k`) | `C1_min_share` | ∀ x ≤ 1000, iff | AGREE |
| C | corrected two-instance cell 3.519 / 3.449, 3.502 / 3.432 (`[R7F-inst-moe-32k]`: a hard-coded print, no theorem) | `C2_instance_cells` | instance step from first principles | AGREE — first machine check in the repo |
| C | step 142 055 807 / 144 929 937 ns (same print) | `C3_printed_ns` | — | **DIFF**: the model gives 142 057 473 / 144 931 589; the print reproduces only at a 101 186 ns slab (the stale comment in `fleet.py`), 1 666 / 1 652 ns low. Cells unaffected at three decimals |
| C | replication > 1.926 iff c ≥ 1.095 / 1.118 (print) | `C4_concurrency` | ∀ c, iff | AGREE |
| C | instance fits at x = 170 (`T3r_instance_margin`) | `C5_page_waste` | with round 4's own page-waste term (29.3 MB per die at 256 KiB pages) | **WEAKENS**: 4.8 MB over at 170; minimal shares 182 / 171 |
| D | E29 at M0 = 14 642 880 ns; tie line 991 940 (`T7r_tie32k_iff`) | `D1_e29`, `D2_line` | — | AGREE |
| D | break-even 5.32 % of launches, margins +2.7 / +0.18 pt (`[R7F-breakeven-banked]`: a print) | `D3_breakeven` | ∀ p per 100 000, iff p ≤ 5 319 | AGREE — first machine check |
| D | "E29 #1 on both caps" | `D4_baseline` | the lever against DESIGN-2's other derived baselines: −1.22 ms (direct-serial), −2.80 ms (ping-pong) | **WEAKENS**: a measured delta ranked against a derived, never-built baseline; both levers banked — no decision rides on the sign |
| E | MoE-128k attention-bound iff G ≤ 168.3 / 178.9 / 189.4 by legs (`T3r_moe128k_lines`: 256 floored blocks) | `E1_weights`, `E2_lines` | one whole-stream extent × (16 + legs)/16, ∀ G | AGREE |
| E | the tie itself | `E3_superseded` | measured 128k cell vs the layer: +12.8 % (derived anchor) / +34.8 % (M0) | superseded by measurement; HW-MAP's E21 sentence still said weights-bound |
| E | HW-MAP E21 "by 0.8 % / by 0.5 %" beside "167.7" | `E4_margins` | — | **DIFF** (cosmetic): the margins belong to the 168.3 line |
| F | fits iff overhead ≤ 2 GiB + 24.5 MB; +23 ‰ per GB (`T3r_instance_margin`) | `F1_margin`, `F2_slope` | ∀ overhead, iff | AGREE (on the waste-free model — see C5); the margin is 284 ppm of the die on an assumed overhead |
| G | two instances win iff cold slab ≤ 1 406 404 ns (`T3r_inst_breakeven`) | `G1_form`, `G2_round3` | own instance step, ∀ Tc, iff | AGREE |
| G | — | `G3_form`, `G4_round7` | the same iff at the round-7 anchors: ≤ 1 198 895 ns (5.2× margin) | NEW |
| H | MoE spec loses iff α ≤ 0.854 (`T6r_spec6_thresholds`) | `H1_round6_steps`, `H2_round6_line` | verify step rebuilt (32 experts, draft, exchange at 4 rows) | AGREE |
| H | — | `H3_round7_steps`, `H4_round7_line` | at the M0 slabs (t = 1 and t ≥ 4): **0.824** | **NEW / stale**: the corpus still quotes 0.854 |
| H | dense spec pays at α = 0.7 iff v ≤ 31.09 ms (`T6r_spec_dense_line`) | `H5_dense` | ∀ v, iff | AGREE |
| I | drift 246 / 490 ppm at 1M (`T4r_drift_online`, `T5r_drift`) | `I1_cells` | chain lengths from the structure | AGREE |
| I | — | `I2_with_mma`, `I3_ship_line`, `I4_range` | charging the matrix unit's 127 internal adds: 253 ppm; ships for every context ≤ 4.28 M tokens | STRONGER |
| J | deferred beats legacy iff trip rate ≤ 65.253 % (`T6r_trip_breakeven`); rates 142.0 / 148.4 / 149.7 / 132.2 / 135.1 | `J1_breakeven`, `J2_rates` | ∀ p | AGREE |
| K | E40 bound 123.7 / 101.3 µs, gate φ ≤ 1 687 / 635 ns (`T40_prize_32k`, `T40_phi_gate`) | `K1_bound`, `K2_gate` | from the measured phases, ∀ φ | AGREE as arithmetic |
| U | the same bound | `U1_bound`, `U2_gate` | subtracting the 54 428 ns per-step intercept of `T6r_perblock`'s chord | **WEAKENS**: 69.3 / 46.9 µs (7.3 / 5.0 %); gate φ ≤ 1 082 ns; on F2 below the bounce removal |
| L | realized launch ≤ 36 µs (HW-MAP serving row) | `L1_realized` | 7.7 ms / 216 = 35.6 µs | AGREE; but the 7.7 ms is a residual of a byte-accounted GEMM — roof-robust form ≤ 45.8 µs → 2.069, not 2.103 |
| M | U_max = 32 / 18 (`T_overflow_umax`) | `M1_overflow` | ∀ u, iff | AGREE |
| Q | region difference "exact whatever the region held before" (`T_overflow_modular_diff`, `_region_exact`) | `Q1_counterexample`, `Q2_exact_iff`, `Q3_headroom` | saturating add, the MEASURED semantics | **WEAKENS**: exact iff b + sum stays inside the rail |
| N | "12.5 % occupancy" (HW-MAP); "12.5 % of compute peak" (CHEATSHEET) | `N1_occupancy` | — | AGREE as issue occupancy at the retired 487 µs stream (16.0 % at 174.6); DIFF as utilization (1.96 %) |
| N | 15 ns issue cost vs 17.8–26.6 TFLOPS/die | `N2_fragment_time` | a full fragment at those rates: 29.5–19.7 ns | **DIFF** between two HW-MAP rows (2×) |
| O | ridge 102–103, free rows 51 / 25 (`Cheat.ridge_die_bounds`, `free_rows_die`) | `O1_ridge` | ∀ m, iff; and at 26.6: 76 / 38 | AGREE given 17.8 |
| Y | "the die's MEASURED 17.8 T-OP/s" as the peak | `Y1_ridge_readings` | 17.8 = 128 FLOP/B × 80 % of the stream; 26.6 → 153; 15 ns/call → 201 | **WEAKENS**: the lowest of three readings |
| R | "relerr ≤ 1e-3 class" for per-token i8 activations (PROBLEM.md) | `R1_quantizer` | rint to 127 levels: rms error crest/440; uniform row exactly 1/254 | **WEAKENS** the gate: 4×–10× over on uniform–Gaussian rows |
| S | dense V3 "+49 %" | `S1_dense_batching` | two rows batched on the chain: 0.198 vs 0.149 / 0.140 | **BROKEN** as a ranking |
| T | 1M deferred vs legacy break-even 64.47 % | `T1_breakeven_1M` | ∀ p | AGREE |
| T | 128k / 1M cells quoted trip-free | `T2_independent_segments` | if trips were independent per 32k segment: flips at 3.2 %, measured 8 / 5.5 % | NEW (an assumption; the open measurement) |
| V | K-int8 | `V1_kint8` | on the measured stream phase and the 2.13× row: 192.7–204.5 µs per layer at 32k; MoE 2.010–2.015 / 1.380–1.390 / 0.341–0.346 | NEW: larger than E40 at every L |
| W | realized-launch reading | `W1_overhead` | the planner's terms on the measured stack: 32.0 / 16.0 ms vs 7.7 ms measured | **WEAKENS**: 4.2× / 2.1×; the quant pass is double-counted at the realized reading |
| X | megakernel pays iff c_sync ≤ 109.9 / 108.4 µs (`T3r_mega_threshold`) | `X1_lines`, `X2_launch_line` | ∀ c, ∀ T | AGREE at 91 µs; at 36 µs the lines are 41.2 / 42.4; at 20 µs crossings it pays iff the launch ≥ 19.1 / 17.3 µs — undecided |
| Z | CHEATSHEET #3 "capped ≈ 1.04×" | `Z1_kv4` | — | **DIFF** in sign: 1.04× slower |

Ten-theorem minimum of the brief: the suggested families are A (minimum dies), C / G (instance gain
and break-even), D (tie break-even), E (the legs-conditional tie), F (fit margin), H (spec
thresholds), I (drift), K / U (stage-overlap bound and gate), X (chain / launch cost lines).

## 4. Findings, ranked by what they move

IDs are this round's. Source: **own** = found while re-deriving; reviewer IDs in brackets.

**Decision-level**

- **C7-1 — V3 is ranked against a one-sequence baseline; at equal demand the unchanged chain wins.**
  DESIGN-4 §10, ALTERNATIVES rank #1. MoE: two staggered sequences 3.853 vs 3.519 / 3.449 at any equal
  c (`Fork.P4_dominates_v3`); dense: two batched rows 0.198 vs 0.149 / 0.140 at every c ≤ 2
  (`Chk.S1`). **V** (own; independently reported as P4-E1, P4-F1, P5-E8). → DESIGN-FORK-PIPE.md.
- **C7-2 — the pipelining gate is the wrong question.** H4 asks whether the runtime pipelines; HW-MAP
  measured that it batches, and measured the dies running concurrently from one process at
  1.000–1.001. ALTERNATIVES' "not ours to build" and DESIGN-4's "runtime capability" are stale. **T**.
- **C7-3 — region-difference exactness is proved for an accumulator the part does not have.** **V**
  (logic; reviewer P12-E1). Physical reachability **S**: needs max |region| at kernel start in the
  serving loop. Failure mode is silent wrong sums, not a rate.
- **C7-4 — the retry share decides the 1M kernel and is unmeasured there.** **V** arithmetic (own;
  P3-S1, P4-E5); the scaling law is an assumption.
- **C7-5 — the megakernel's go/no-go sits inside the measured launch band.** **V** (P5-E6, P4-E6).

**Number-moving**

- **C7-6** `T7r_inst` / R7.4 prove 3.853 under V3's name; the C-3 and C-1 corrections had no theorem;
  the printed ns are 1.7 µs off the model. **V** (own).
- **C7-7** the E40 bound and gate omit the per-step intercept. **V** (P3-E3).
- **C7-8** DESIGN-3's round-6 layer carries the retired trip premise as current; PROOF-COVERAGE-3 lists
  the amortized band as MEASURED though it is premise × re-run. **T** (P3-E1).
- **C7-9** the instance fit omits round 4's page-waste term. **V** (P4-E2, P5-E15).
- **C7-10** the MoE spec loss line at round-7 anchors is 0.824. **V** (own; P4-E3).
- **C7-11** the planner is self-consistent, not validated; its overhead terms are 2.1×–4.2× the measured
  non-GEMM share. **V** arithmetic (P4-E4); the transfer of that residual to the fleet shapes is an
  assumption.
- **C7-12** the numerics gate is certified against a quantizer-sharing reference. **V** for the
  quantizer arithmetic (P12-E2); the row distributions are an assumption.
- **C7-13** K-int8 outranks E40 on measured rows and is absent from the round-6 lever ranking. **V**
  (P3-F1); accuracy (E36) and the d = 128 timing are unmeasured.
- **C7-14** the roofline's compute figure: low end of a range, and 2× inconsistent with the issue row.
  **V** (own; P5-E1, P5-E2).
- **C7-15** DESIGN-2's W4 half is void; DESIGN.md's banner quoted 137.8 GB/s, a retracted k = 64 anomaly
  and "no f16 → i8 cast". **T** (P12-E6, P12-E8).
- **C7-16** CHEATSHEET #3's 1.04× is a slowdown. **V** (P5-E3).
- **C7-17** "E29 #1 on both caps" ranks against a derived baseline. **V** (own; P4-E10).
- **C7-18** ALTERNATIVES calls the cross-core sync "measured sub-µs"; HW-MAP has no such row. **T**
  (P5-E5).

**Reviewer-verified only (R) — reported, not re-derived here**

- P12-E3: DESIGN-2's Z8 "K-split never pays" assumes a serialized 91 µs launch; at ≤ 36 µs three cells
  flip against the G = 1 baseline (S with G = 2 stays ahead down to 22.2 µs).
- P12-E4: W-dyn's cross-core output reduction is never charged while K-split's is — strengthens S.
- P12-E7: the PROMPT-6 re-designation of m = 32 to 154.5 uses the PRIOR 64 KiB L0C; moot (silicon: 59).
- P5-E10: shared-prefix batched attention is a loss for dense under the round-3 chain (rows 256 go
  vector-bound) — `T_alt_prefix_iff` proves only that the KV-stream time shrinks.
- P5-E13: the "host-bounce retired" ruling contradicts its own arithmetic at λ = 12.2 µs (26.8 vs
  43.7 µs per pass); flips at λ_eff ≤ 20.66 µs.
- P5-E14: ERRATA-IMPACT A5 ("the measured kernel is causal-exact, so it does not use this form")
  predates the truncation finding (14 of 16 steps dropped tail cells; the tests were double-blind).
- P3-E6: the session-3 phase split is not an engine partition — the V stream inside the 344.9 µs PV
  phase would need 194.6 GB/s (arithmetic checked here: 67 108 864 B / 344.9 µs).

**Suspected (S)**

- P12-E10: at N_e = 512 the same-destination MMA spacing is 4 calls — below every measured-safe class
  (≥ 16 any depth; 8 with per-tile barriers). Erratum #16 is unaudited for DESIGN-2.
- P12-E11: HW-MAP's quantization row is not self-consistent at K = N = 8192 (43.7 µs = +12.2 % implies a
  358 µs base = 187 GB/s, above the 181 roof; arithmetic checked here).
- P3-E9: the measured 51 µs bounce matches 2 legs × 4 MiB (8 rows), not the modelled 16 rows — the
  bounce may double at t = 2.
- M0's "t = 1 uniform" selection may be a contiguous-stride arena (P12-T5).

## 5. Taint ranking (blast radius first)

For each INPUT: what stands on it, what measured it, whether the harness arena coincides with the
claim, and what a same-class bug would flip.

| # | INPUT (HW-MAP row) | Stands on it | Harness and coincidence | A same-class bug flips |
|---|---|---|---|---|
| 1 | deferred-guard cells 945.5 / 3 618.8 / 28 694 µs | the attention term of every cell (22 / 50 / 89 % of the MoE step at 32k / 128k / 1M), the lever ranks, both spec lines | kernel-side battery on a trips-0 profile; this kernel family met all five harness-deception classes, one rate cell was voided, and the timings predate three integration fixes (16-token truncation, output fence, arena stride) — "speeds stood" is plausible and not re-timed | nothing at 32k; the 1M guard choice through #2 |
| 2 | retry share 8 % / 5.5 % of launches | the amortized cell, the tie, every long-context reading | one model, 32k, single span, t = 1; HW-MAP's own other quotes of the same quantity reach 10–15 % of attention ms (τ up to 19 %); the previous premise was stale 30–40× | the 1M kernel choice (≥ 64.5 %), verify batches at t = 16, KV-int8 at μ = 0 |
| 3 | launch cost — 91 µs floor; ≤ 36 µs realized | 14 % of the MoE step, the whole megakernel prize, half the draft cost and so the spec lines | the floor is from a fill microbench; the realized bound is the residual of a byte-accounted GEMM on another model with the layer count bracketed 24–32, and it contains all non-launch work | megakernel on/off (line 17.3–19.1 µs; measured floor 17 µs) |
| 4 | concurrency 1.99× / 1.000–1.001 / 2.0× | the partition choice — V3 and the fork alike | pairs only; a "weight-streaming class" at solo 151 GB/s, not the 174.6 decode kernel, no layer-split chain, no bounces in flight | the plan's shape if c < 1.10 (V3) — the fork needs only c > 1.00 |
| 5 | M0 165.8 GB/s | 54 % of the MoE layer, E29, V3's hot tier | exact 20/20; the expert-set arena is not stated against 256 experts × 28 layers of residency | no decision (ratios invariant); −9 % on MoE cells at the 138.9 class |
| 6 | W8 kernel 174.6 GB/s | 92 % of every dense cell | K = 8192-class shapes, 64 MiB working sets — the plan runs K = 16 384 / 53 248 over 48 GB per die; partly corroborated by the serving accounting | none |
| 7 | i32 saturation probe | "U_max = 32 holds", the expert kernel's exactness | its own launch state was within 391 167 of zero: a benign arena for exactly the question C7-3 asks | silent wrong expert outputs |
| 8 | "fp64-exact ×20, relerr 1.07·10⁻⁷" | the numerics gate of problems 1 and 2 | the reference shares the activation quantizer | the gate as written (1e-3 class) |
| 9 | 86 GB usable; overhead 2 GiB + 64 MiB (no row) | every memory verdict | "86" is a two-figure row; the overhead is assumed; the vendor path once materialised 4.5 GiB per step | dense-1M KV-int8 feasibility (≤ 3.80 GB; 3.74 with page waste) |
| 10 | i4 unpack 5.3 GB/s/core; US → S1 250 GB/s/core | V3's cold tier | a pass-only vector-rate loop; the US → S1 figure is a rate with no content proof and its A-slot sibling is content-wrong (erratum 20); the chain is unbuilt | dense V3 below 2.74 GB/s/core — already dominated |
| 11 | MMA issue 15 ns; 17.8–26.6 TFLOPS | the roofline, the 12.5 % row, MMA terms at t ≥ 4 | the two rows disagree 2× | nothing at m ≤ 16 |
| 12 | K-int8 87.6 GB/s, 2.13× | the K-int8 lever, CHEATSHEET #1 / #3 | d = 64 on a 1 KB-tile diagnostic stream where the f16 arm runs 82.3 against 128–174 in production; "exact" is against its own integer reference | the K-int8 re-price (C7-13) |
| 13 | E21 c_pg | page-size guidance, two-tier pages | shuffle inside a contiguous per-core arena — a lower bound | nothing now that cells are measured |

## 6. Decision-sensitivity list — what flips a ranked decision

Ordered by the size of the decision. Thresholds are derived here unless marked (R).

| # | Unmeasured variable | Decision it flips | Threshold | Evidence today | Cheapest decisive experiment |
|---|---|---|---|---|---|
| 1 | per-die workers on staggered sequences | the fleet plan's shape: V3 → the chain at Π ≥ 2 | pipelining ≥ V3 iff its c ≥ 0.913 × V3's (MoE: 129.74 / 142.06 ms); ≥ the single chain iff c ≥ 1.001 | mechanism measured for independent streams; scheduler unbuilt | **P1** of DESIGN-FORK-PIPE.md: two contexts, two host threads, half a step apart, bit-identity vs solo — host only |
| 2 | retry share at 128k / 1M | the 1M softmax kernel (deferred vs legacy); the 128k / 1M cells | deferred loses at 1M iff τ ≥ 64.48 %; under independent 32k segments that is a segment rate ≥ 3.2 % | measured 8 % / 5.5 % at 32k only; trips cluster | count tripped launches by (layer, block) in the existing 32k run, then one 128k decode |
| 3 | retry share at t > 1 | spec-decode verify on the deferred kernel | independent rows: flips at t = 16 iff τ₁ ≥ 6.4 % | none at t ≥ 4 on the deferred kernel | trip counts on a real verify batch |
| 4 | launch cost, lower side | megakernel on/off | pays iff the launch it removes ≥ 19.1 µs (dense) / 17.3 µs (MoE) at 20 µs crossings | bounded above (26.7–36 µs), floor 17 µs | time N queued empty launches (H6) + one flag round (E31) |
| 5 | L0C launch state \|b\| | whether the expert kernel is exact in the serving loop | exact iff \|b\| ≤ 694 067 199 (D = 128) / 2 015 354 879 (D = 8) | probe arena benign; alternation with an f32 kernel untested | dump max \|region\| at kernel start after an attention launch; plant a near-rail lane as the positive control |
| 6 | φ, the cost of a barrier with vector work in flight | E40 go; E40 vs bounce removal | go iff φ < 1 082 ns (F1, k = 1); never above bounce removal on F2 | the measured crossing is 9.2×–18.5× above | E41 (re-time the session-5 phases) before E40a |
| 7 | expert overlap D(4) across verify rows | MoE spec go/no-go | at α = 0.7 spec pays iff D(4) ≤ 23 (uniform routing gives 32, Zipf(1.0) 25) | generator means only | H9: the routers on the host over ≥ 10⁵ tokens |
| 8 | K-int8 score accuracy; d = 128 tile rate | the attention-side lever order | relerr > 1e-3 kills it; the 2.13× must transfer | exact vs its own integer reference at d = 64 | E36 on real q / K, one production-tile timing |
| 9 | activation crest factor | the numerics gate | relerr ≈ crest / 440 — 1e-3 is unreachable; 1e-2 at crest 4.4 | none at model level | host replay of real activation rows + a task metric, W8A8 vs W8A16 |
| 10 | per-die overhead | dense 1M with KV-int8 | fits iff ≤ 3.80 GB (3.74 with page waste) | assumed 2 GiB | read free memory after load on the serving stack |
| 11 | quant-pass scaling in K and m | the integrated ≥ 120 gate below K = 8192 | at K = 4096 the gate needs c_q ≤ 43.72 µs — the measured 43.7: a tie | measured at K = 8192, m = 1 only | the pass at K = 2048 / 4096, rows 4 / 16 |
| 12 | the m ≥ 24 multi-strip wedge | flat m to 64; prefill (128-row chunks ride this curve) | — | 81 / 59 / 43 GB/s, cause unknown | E37 |
| 13 | same-step launches on several dies | member S of the fork (single-stream latency) | wall = max, not sum | unmeasured | S1 of DESIGN-FORK-PIPE.md |
| 14 | same-destination spacing 4 at N_e = 512 (S) | G ≥ 4 forced on small experts | corruption at spacing < 8 | unmeasured class | an E21-style oracle at spacing 4, depth 64–704 |
| 15 | two-client batching on the dense shape | dense V3 vs batching (already against V3) | V3 loses iff the aggregate ≥ 1.43–1.48× | measured 1.53× on another model | np = 2 on the dense-class image |

Not flipping, only moving numbers: λ, routing skew at t = 1, the legs count (superseded), M0, α for
dense spec (pays from α ≥ 0.15–0.20), the overhead for MoE V3 (moves x at +23 ‰ per GB).

## 7. The dominated-alternatives table, re-scored

Premise currency checked against today's HW-MAP. **V / T / R** as in §1.

| Family | Corpus verdict | Premise the verdict rests on | Still current? | Re-score | |
|---|---|---|---|---|---|
| **Sequence pipelining Π = 8** | "runtime-dependent … not ours to build"; gated on H4 | the runtime must pipeline | **No** — the stock runtime batches (measured), and the dies run concurrently from one process (measured) | **UNDER-SCORED → fork.** Host scheduling; Π = 2 already beats rank #1 | V |
| **#1 replication + int4 tier, dense** | +48.5 % | compared with one sequence on the chain | not like for like | **OVER-SCORED → dominated** by two batched rows (0.198 vs 0.149) | V |
| #1, MoE | +107.7 % | same; and a direct-path instance vs a serial-anchor baseline | the baseline double-counts rank #2 | **OVER-SCORED**: +82.7 % like for like (3.519 / 1.926); dominated at equal demand by Π = 2 | V |
| #3 megakernel | +12.5 % / +2.8 %, score 6.3 / 1.4; "pays iff c_sync ≤ 109 µs" | 91 µs serialized launch | **No** (≤ 36 µs realized) | **OVER-SCORED**: ≤ +2.6 % / +0.44 % at 36 µs, sign flips at the 17 µs floor | V |
| #5 two-tier pages | score 12 | baseline 64 KiB pages; c_pg bracket | **No** — the default is 256 KiB, where c_pg = 12 394 − 12 391 = 3 ns | **OVER-SCORED → ≈ 0** | T |
| #7 K-int8 / V-f16 | rank 7, +4.2 / +12.2 / +27.2 % | bytes × ¾ → time × ¾ | **Yes, and now measured** on the K side (2.13×) | AGREE on size; **UNDER-RANKED** against E40 in DESIGN-3 / -4 | V |
| #8 shared-prefix | dense +3.8 … +34.8 % | multi-fragment passes stay stream-bound | No under the round-3 chain | OVER-SCORED; dense becomes a loss | R |
| #13 rows-cliff repair | "real but outside the scored cells" | only B = 64 at 4k benefits | **No** — prefill runs at 128-row chunks on this curve | **UNDER-SCORED** | T |
| #18 expert-parallel across a card's dies | dead, −3.6 % | λ = 91 µs; "no concurrency, #11 fault" | **No** on both (12.2 µs; 1.000–1.001) | **UNDER-SCORED** — re-opened as fork member S; its theorem is x < x + c by construction | T |
| #21 flash-decoding split-KV | dominated ("H_kv = 8 = cores"), dead across dies | H_kv = 8; #11 | **No** for 4-kv-head models (HW-MAP names the split-KV-token core map a ~40 ms/step lever) | **UNDER-SCORED** | T |
| #2 direct-path expert kernel | banked | measured | yes (M0) | AGREE | V |
| #6 KV-int8 both halves | MoE 1M +75.3 % | attention fully stream-bound | partly (stream ≈ 81–86 % of the cell) | AGREE in direction, high in size | R |
| #4 quantizing epilogue; host-bounce sub-row | retired | the pass is cheaper than a bounce | not at λ = 12.2 µs | sub-row UNDER-SCORED (≤ 1.6 %) | R |
| #9, #12, #14–#17, #19, #20, weight-stationary, L2 carving, draft on host | void / dominated / dead | — | yes | AGREE | R |
| CHEATSHEET G1–G8 | kills | — | yes | AGREE (G3 stronger: prefill is nearer the ridge than stated) | R |
| CHEATSHEET #3 (KV 2–4 bit) | "capped ≈ 1.04×" | — | — | **OVER-SCORED**: a 4 % slowdown, memory-only here | V |
| CHEATSHEET #8 (spec trees ≤ 16 rows) | "verification ~free" | the flat m ≤ 16 region | true for dense bytes only | OVER-SCORED for MoE (routed bytes scale with rows; the corpus's own `T_spec_moe_loss`) | V |

The table's history note records one earlier stale-number catch. This round finds the same class
four more times (pipelining, expert-parallel, split-KV, rows-cliff), each a dismissal whose premise a
later HW-MAP row moved without the table being re-read.

## 8. The fork

**DESIGN-FORK-PIPE.md** — host-scheduled multi-die concurrency on the unchanged full-int8 chain.
Member P (sequence pipelining) is the claim; member S (one layer step on all dies) is carried with
weaker evidence. Headline (MoE 32k, tokens/s/card): chain 1.926; V3 3.519 / 3.449; **P at Π = 2
3.853, Π = 8 13.832**; S, one sequence, 6.556. Dense: 0.104; V3 0.149 / 0.140; batching 0.198; P
0.208 / 0.803; S 0.650. Labels `[FORK-*]`; theorems `Fork.P1` … `S3`; independent recomputation
`[CHK-P]`. Not ranked until P1 runs: a host-only experiment with a content oracle.

## 9. Corrections applied in place (all marked **challenge:**)

| File | Where | What |
|---|---|---|
| HW-MAP.md | E21 verdict sentence | margins belong to the 168.3 line; the cell is attention-bound by measurement |
| HW-MAP.md | MMA issue-cost row | 16.0 % at the shipped stream; inconsistent with the compute row |
| HW-MAP.md | production attention row | "VALIDATED" is total-only |
| DESIGN.md | banner | 174.6 measured; k = 64 retracted; the cast exists; targets met / not met; the numerics gate |
| DESIGN-2.md | banner | saturation vs the region difference; the W4 half void; the direct-path kernel measured |
| DESIGN-3.md | banner; §drift | the trip premise; E40 with the intercept; K-int8; ppb → ppm |
| DESIGN-4.md | after the round-7 banner; §10 table | seven numbered notes (V3's baseline, the fork, R7F, page waste, the spec line, trip-free long-context cells, validation) |
| PROOF-COVERAGE-4.md | R7.1, R7.4 | 5.32 % not 0.19 %; 3.853 is not V3 |
| ALTERNATIVES.md | megakernel adjudication; the expert-parallel row; the Π = 8 row | no measured sync; both premises stale; ours to build |
| CHEATSHEET.md | §0; candidate #3 | issue occupancy vs utilization; the sign of 1.04× |
| CHEAT-MATH.md | §B | 17.8 is the low end of a range |

**Deliberately not edited** (existing proofs and models stay as they are; each is a follow-up for the
owning round): `proof/fleet.lean` `T7r_inst` and its docstring (label, not arithmetic); the
`[R7F-inst-moe-32k]` print's ns values and the "101 186" comment in `proof/fleet.py`; `fleet.py`'s
`step7`, which subtracts the D = 8 slab constant for any B, t (correct only at B = t = 1 — the fork
section does not call it otherwise); `proof/attn.lean` `T6r_trip_premise` / `T6r_amort` and
PROOF-COVERAGE-3 row R6 listing the amortized band as MEASURED; `proof/alt.lean`
`T_dominated_expert_parallel`; `proof/cheat.lean`'s header, which still names `native_decide` as a
closer though none is used.
