# PROOF-COVERAGE-CHECK — the PROMPT-7 challenge rounds (append-only; newest round first)

> **CHALLENGE ROUND 4 (2026-11-15, HW-MAP 85a79d0 / ROUND-7 planner) — `proof/check.lean` namespace `Chk` (95 theorems after Mission B, core Lean
> 4.35, 0 axiom / sorry / native_decide; `lake build` target `Check`, 17 jobs clean), `proof/fleet.py` `[CHK-*]` (10) + `[FORK-EP-*]`
> (12) appended after `main7` (the first 692 output lines byte-identical), `DESIGN-FORK-EP8.md` (the fork), `challenge:` marks in
> DESIGN.md / DESIGN-2 / DESIGN-3 / DESIGN-4 / ALTERNATIVES / ERRATA-IMPACT / CHEATSHEET / CHEAT-MATH, README rows.** Three earlier
> challenge rounds exist as UNVERIFIED snapshot branches (`challenge-round`, `-2`, `-3`); this round did not read them (independence)
> and compares against their commit messages only in §9. Method: the coordinator re-derived the decision layer by hand and in Lean
> from the printed model numbers; six independent reviewers (one per problem, one for the cross-problem layer, one harness-taint
> auditor) read the corpus with no stake; a reviewer finding entered this ledger only after the coordinator re-verified it against the
> files (dates from `git log`, provenance by `grep`, arithmetic by `python3 -I` and `proof/check.lean`).

## 0. Verdicts

| Problem / document | Verdict | Evidence (finding numbers below) |
|---|---|---|
| P1 `DESIGN.md` | **SOUND as a superseded, bannered record**; WEAKENED in hygiene | every PROVED row re-derives; the live route is MEASURED end to end; the SILICON banner is two rounds stale (137.8, "k = 64 anomalous" — retracted) and HW-MAP rows 26 / 106 still list the i4 dequant path and the direct load as live / UNMEASURED against erratum 12 and row 105 (C-20); the m ≥ 24 cliff equals the flat rate ÷ strips (C-20) |
| P2 `DESIGN-2.md` | **WEAKENED** | the region-difference exactness license assumes WRAP and zero prior content; HW-MAP measured SATURATION with nondeterministic L0C content — U_max 32 → 16 at an f32-1.0 pattern, 0 at ≥ 0x7F000000 (C-14); the fleet's expert anchor M0 has no HW-MAP row (C-2); Z8 flips two cells at the realized launch, F = 8 µs contradicted by the M0 pair (C-21) |
| P3 `DESIGN-3.md` | **WEAKENED** (the shipped kernel and its measured cells stand) | E40's vector input (1.4–2.1 µs/block) contradicts HW-MAP's own 565 µs softmax phase (8.8 µs/block): at that frame E40 is dead for k ≤ 2 at any φ (C-12); the f16 P cast's 488 ppm is outside the drift theorems (C-11); E40's page-table prologue is O(L) (C-13); the cells were timed on the extent-truncating kernel — timing unaffected, the "causal-exact" ledger rows carry no erratum-32 mark (C-18); three retry-share statements disagree (C-19); the served 4-kv model runs 4 of 8 cores — §2.1's split unbuilt (C-23) |
| P4 `DESIGN-4.md` | **WEAKENED, three statements BROKEN** | "the 32k tie is SETTLED on both caps; break-even 0.19 %, 42×/29× over" — the line is the retired E29's; at the banked E29 the break-even is 5.32 % and the wide cap clears by 0.18 points (C-1); "two instances 3.853" doubles the 8-die chain — a 16-die configuration (C-3); dense V3 ranked first among no-runtime levers is dominated by chain batching at every N ≥ 2 (C-4); the cross-die split family is dismissed on erratum 11, a vendor-runtime property that season-h measurements no longer support (C-5); serialized 91 µs launches in every primary MoE cell against HW-MAP's own realized row (C-6); spec line and 1M headline not re-derived at the measured anchors (C-7, C-8); MoE-128k margin stated on the retired anchor (C-9) |
| P5 `ALTERNATIVES.md` | **BROKEN at rank 1 (dense half) and at two dominated rows; arithmetic SOUND** | rank 1 compares 2 sequences against 1 (C-4); rows "flash-decoding split-KV across dies" and "expert-parallel" are dismissed on the stale premise (C-5); ranks 3–5 scored on superseded inputs (C-6; two-tier at an unmeasured c_pg bracket while 38 ns is measured) |
| `ERRATA-IMPACT.md` | **SOUND** for #18–#31 | every moved cell re-derives; the megakernel "5.4× margin" is 2.1× at the realized launch and §5's rejected 40 µs reading sits at that line (C-6) |
| `CHEATSHEET.md` + `CHEAT-MATH.md` + `proof/cheat.lean` | **BROKEN** (§0, rows #1 / #3 / #4, the build claim); arithmetic layer WEAKENED | §0's "four independent agreements" are arithmetic on our own inlined constants and three of the four are not agreements (ridge 48 vs the die's 102; "4–8 %" vs the measured 12.5 %; "< 12 %" vs the measured 24 %; "KV parity 30k = our 32k flip" — the corpus has no attention-bound flip at 32k) (C-15); `crt_15_16` closes by `native_decide` — an axiom, against README and the commit's "0 axiom" (C-16); rows #1 / #3 / #4 quote gains the errata cap at ≈ 1.0–1.25× / 1.04× / 1× (C-17) |
| The proof corpus (`*.lean` / `*.py`) | **SOUND** | 81 independent re-derivations in `Chk.*` matched the printed numbers to the digit (§1); two exceptions: `T7r_inst` proves the wrong input (C-3) and `cheat.lean` carries an axiom (C-16) |

**Bottom line for the next round:** nothing MEASURED moved. What moved is the decision layer's reading of its own measurements:
the dominated-alternatives table and §5 of DESIGN-4 stand on erratum 11 as a silicon law when HW-MAP now measures one process
driving two dies of a card at 1.000–1.001 of their solo sum and two cards at 2.0×; on that measured primitive the cross-die split
family (`DESIGN-FORK-EP8.md`) dominates the chosen V3 route for MoE at every client count and dominates everything for dense, with
no int4 tier, no #19 merge and no E30 — gated on one UNMEASURED capability (8-die per-layer dispatch + host all-reduce, §5 F-1).

## 1. The `Chk.*` ledger — 81 theorems of Mission A (the 14 Mission-B theorems are in §11–§13), what each re-derives, and the corpus row it checks

Status words: **MATCH** = reproduces the corpus number to the digit from this file's own definitions; **CHALLENGE** = a finding
(the theorem states the corrected fact); **BOUND** = a structural inequality re-proved ∀. Printed labels are `proof/fleet.py`
`[CHK-*]` unless noted; the inputs are HW-MAP rows (M) or printed model numbers (D).

| # | Chk theorem | re-derives | corpus theorem / label | status |
|---|---|---|---|---|
| 1 | `tau3_cells` | τ(0.7, 3) = 2.533, τ(0.854) = 3.206, τ(0.855) = 3.211 | fleet `tau` | MATCH |
| 2 | `shapes`, `components` | the shapes' bytes; MoE layer GEMM 3 207 719 = 240 223 + 16 000 + 24 × 122 979; dense 18 256 993; heads | [F0], [F3-*-layer] | MATCH |
| 3 | `step_form` | the step's affine constants rebuilt from components: 115 956 899 / 2 289 788 669 | `T5r_step_form` [R5-step-*] | MATCH |
| 4 | `round2_cells` | 133 847 319 → 1.867 / 2 362 319 269 → 0.105 (attention = max of the three terms) | [F3] table | MATCH |
| 5 | `r7_inputs` | slab 101 189 / 98 573; E29 banked 14 642 880 vs derived 15 862 560; amortized 1 015 340 / 993 515 | `T7r_inputs` [R7-inputs] | MATCH |
| 6 | `r7_cells` | 127 788 019 → 1.956; 1.926; 1.935; 1.233; 0.276; dense 0.104 | `T7r_step_cells` [R7-step-*] | MATCH |
| 7 | `r7_launch` | 10.89 / 39.71 ms; 2.103 / 0.105 realized | `T7r_step_realized` [R7-launch-*] | MATCH |
| 8 | `r7_inst` | 2 × 1.926 = 3.853 / 3.834 | `T7r_inst` [R7-inst-moe-32k] | MATCH of the arithmetic — see C-3: the input is the 8-die chain |
| 9 | `tie32k_line` ∀ T | fusion ≥ / > E29 iff T ≤ 991 940 / 991 939 | `T7r_tie32k_iff` | MATCH |
| 10 | `tie32k_cells` | margins 23 400 / 1 575 ns per layer, 655 200 / 44 100 per token | [R7-tie-32k-*] | MATCH (fleet prints 1 576 / 23 401 with R = 873 000) |
| 11 | `tie_lines_other_L` | 128k / 1M lines 5 286 380 / 45 747 080 (derived E29), 5 329 940 / 45 790 640 (banked) | `T6r_tie_lines` | MATCH + extension |
| 12 | `challenge_breakeven_banked` ∀ p | fusion ≥ E29 iff the trip rate ≤ 5.3 % of launches at the banked E29 | HW-MAP:116, DESIGN-4:174, PC-4 R7.1 "0.19 %" | **CHALLENGE C-1** |
| 13 | `breakeven_derived_line` ∀ p | the 0.19 % is the derived-E29 line's break-even (0.18 %) | round-6 line 947 079 | CHALLENGE C-1 |
| 14 | `breakeven_ratios` | 1.50× / 1.03× over the banked line (the quoted 42× / 29× are over the retired line) | HW-MAP:116 | CHALLENGE C-1 |
| 15 | `trip_breakeven_legacy` ∀ p | deferred < legacy iff p ≤ 65 253 per 10⁵ steps | `T6r_trip_breakeven` [R6-trip-breakeven] | MATCH |
| 16 | `amort_band_premise` | 946 259 / 947 419 at the stale premise; R = 872 600 | `T6r_amort` [R6-amort] | MATCH (a two-point line, not a measurement) |
| 17 | `challenge_amort_1M` | the 1M cell at the measured 8 % trip rate: +7.6 % | [R6-amort-1M] "+0.08–0.21 %" | **CHALLENGE C-8** |
| 18 | `totals` | 386.7 / 363.0 GB > 4 × 86 | `T_min_dies_4_total` | MATCH |
| 19 | `min_dies_dense`, `min_dies_moe` ∀ n₀..n₃ | the pigeonhole: some die ≥ 30 / 7 layers > 86 GB | `T_min_dies` | MATCH (BOUND) |
| 20 | `five_dies_fit` | 24 layers + embed + overhead + KV(4k) = 81.2 GB; 95.6 / 90.4 GB | [F1-*-min-dies] | MATCH |
| 21 | `challenge_min_dies_int4` | at the int4 source size three dies hold either shape's weights | PROBLEM-4 band, T_min_dies | **CHALLENGE C-10** (what erratum 12 carries) |
| 22 | `t4_steps_from_components` | the t = 4 steps 456 819 203 / 2 356 301 528 rebuilt (draft token 22 129 841) | `T6r_spec6_steps`, `T6r_spec_dense_form` | MATCH |
| 23 | `spec_moe_loss_line` ∀ α | MoE spec loses iff α ≤ 0.854 | `T6r_spec6_thresholds` | MATCH |
| 24 | `spec_dense_line` ∀ v | dense spec pays iff v ≤ 31 092 727 | `T6r_spec_dense_line` | MATCH |
| 25 | `spec_dense_alpha`, `spec_dense_r2` ∀ α | α ≥ 0.146 / 0.024 | `T6r_spec_dense_thresholds`, `T_spec_dense_all_alpha` | MATCH |
| 26 | `challenge_spec_moe_r7` ∀ α | with E29 banked on both sides (t ≥ 4 slab) the line is 0.823 | round 7 kept 0.854 | **CHALLENGE C-7** (moves, no flip) |
| 27 | `challenge_spec_moe_t4_attention` ∀ a₄ | the verify step's attention is the t = 1 cell; for every a₄ ≥ it the loss region contains α ≤ 0.854 | E41 (t = 4 deferred cell U) | CHALLENGE C-7′ |
| 28 | `spec_moe_mechanism` | E1 = 82.64 ms; τ < 2.852 is a loss | `T_spec_moe_mechanism` | MATCH |
| 29 | `inst_fit_32k`, `inst_fit_1M` | minimal x = 182 / 170 / 170 / 182 and 827 / 816 / 816 / 827, iff | `T_alt_fit_minx_moe_32k`, `T3r_inst_fit` | MATCH |
| 30 | `inst_margin_32k`, `inst_margin_is_grid` | margins 40.3 / 24.5 MB < one x-step (45.1 MB) | `T3r_inst_margins` [ALT-P-margin] | MATCH (a grid remainder, honestly labelled) |
| 31 | `inst_dx_per_gb` | +23 ‰ per GB; x = 204 / 192 at +1 GB | [ALT-P-margin] | MATCH |
| 32 | `inst_cells` | the instance step re-implemented: 128.90 ms → 3.878; xch 749 135 | [ALT-2-moe-32768-*] | MATCH |
| 33 | `inst_breakeven_iff` ∀ Tc, `inst_breakeven_tps_cells` | two instances beat one iff T_cold ≤ 1 371 366 (exact) / 1 371 124 (floored tps — the printed line) | `T_instance_gain` [ALT-2-breakeven-moe-32k] | MATCH |
| 34 | `inst_margin_6_9x`, `inst_eta_line` ∀ η | 6.9×; η ≥ 0.482 | `T_instance_gain_h10` [ALT-P-h10] | MATCH |
| 35 | `attnLegs_forms`, `moe128k_legs_lines` ∀ G > 0 | attention-bound iff G ≤ 189.4 / 178.9 / 168.3 at legs 2 / 1 / 0 (no range bound needed) | `T3r_moe128k_tie` [R4-fleet-moe-128k-legs*] | MATCH |
| 36 | `moe128k_legs_cells`, `moe128k_measured` | 3 588 736 / 3 192 192 ns; +12.8 % on the anchored layer | `T6r_fleet_moe_128k` | MATCH |
| 37 | `challenge_moe128k_anchor` ∀ G > 0 | at the banked anchor (2 684 759) the cell is attention-bound by 34.7 %, iff G ≤ 226.5 GB/s — above the roof | DESIGN-3/4 banners "12.8 %" | **CHALLENGE C-9** |
| 38 | `drift_1M`, `drift_measured` | chains 2 052 / 2 062 → 246 ppm; 490; 125; 205× / 833× inside | `T4r_drift_online`, `T5r_drift` | MATCH |
| 39 | `challenge_f16_P_cast` | the f16 P cast: 488 ppm per weight, 2.0× inside the line | — (no theorem) | **CHALLENGE C-11** |
| 40 | `e40_floor_prize` | floors 821 800 / 844 216; prizes 123 700 (13.1 %) / 101 284 | `T40_floor`, `T40_prize_32k` | MATCH |
| 41 | `e40_phi_gate` ∀ φ | gates 1 687 / 635 / 966 / 241 | `T40_phi_gate` [E40-phi-*] | MATCH |
| 42 | `e40_dead_at_band` | dead at 10–20 µs crossings (5.9–11.9×) | [E40-phi-gate] | MATCH |
| 43 | `challenge_e40_V565` ∀ φ | at V = 8 828 ns/block (HW-MAP's 565 µs phase) E40 cannot win at k ≤ 2; k = 8 gate 241 ns | E40-3 "INPUT (sessions 3 and 5)" | **CHALLENGE C-12** |
| 44 | `challenge_e40_pagetable` | 16 KiB page table at 1M; US 213 056 B = 208 KiB + 64 B | `T_buffers_no_OL` premise | **CHALLENGE C-13** |
| 45 | `mega_lines`, `mega_dense_iff` ∀ c, `mega_dense_realized_iff` ∀ c | pays iff c ≤ 109 903 (dense) / 109 200 launch-only (MoE); 41 153 / 43 200 at the realized launch; 20 µs still pays | `T3r_mega_threshold`, `T_alt_mega_savings_realized` | MATCH + extension (C-6) |
| 46 | `tier_iff` ∀ c, `tier_38` | the two-tier page wins iff c_pg ≥ 1 ns; +1.1 % at 38 ns | `T_alt_tier_dominates`, `T_two_tier_measured` | MATCH |
| 47 | `overflow_umax` | U_max 32 / 31 / 18 | `T_overflow_umax`, `T_overflow_tight` | MATCH |
| 48 | `challenge_overflow_prior_content` | under saturation with prior content b: U_max 16 at 0x3F800000, 0 at ≥ 0x7F000000 | `T_overflow_modular_diff` (assumes wrap, b = 0) | **CHALLENGE C-14** |
| 49 | `dispatch_hide` ∀ σ, `vendor_floor` | σ_d ≤ 968 ns; 5.5× / 6.7× over the vendor op | `T_dispatch_hidden` | MATCH |
| 50 | `challenge_ksplit_realized` | Z8's (4,32) / (16,68) margins flip sign at 36 µs launches | `T_Z8_margins` | **CHALLENGE C-21** |
| 51 | `d7_1`, `loader_line` ∀ L, `ceiling_reread` | 398 193 ns → 168.5; L ≥ 21.8; the measured 174.6 = 97.8 % of the pure-read ceiling 178.5 | `T1_m1_*`, `T2_*` | MATCH + note (C-20) |
| 52 | `challenge_rows_cliff_strips` | 174.6 ÷ 2 / 3 / 4 = 87.3 / 58.2 / 43.6 vs the measured 81 / 59 / 43 | HW-MAP:108 "wedge unresolved" | **CHALLENGE C-20** |
| 53 | `crt_15_16_core` ∀ x y | the CRT fact in core Lean (omega) | `Cheat.crt_15_16` (native_decide) | **CHALLENGE C-16** |
| 54 | `ridge_as_stated`, `challenge_ridge_units`, `challenge_occupancy` | 48 < 8192/170 < 49 (as stated); the die's ridge 102; the lane budget 1 op/elem; unpack 24 %; occupancy 12.5 % | `Cheat.ridge_bounds`, `dequant_cap`, CHEATSHEET §0 | **CHALLENGE C-15** |
| 55–64 | `ForkEP.emax_8_8`, `tail_probs`, `ep_inputs`, `ep_cells_32k`, `ep_cells_L`, `ep_sync_line` ∀ s, `ep_worst_case` ∀ a s, `ep_memory`, `ep_gate_margin` | the fork's cells (§7, `DESIGN-FORK-EP8.md`): E[max] = 2.597 exactly; EP-A 2.932 / EP-B 4.667 at 32k; the orchestration line 1 640 102 ns; the worst routing = chain + sync; 63.6 GB per die | [FORK-EP-*] | DERIVED (new) |

(The remaining theorems are the component identities listed with their families above; `grep -c '^theorem' proof/check.lean` = 81 after Mission A (95 after Mission B — §13).)
Build: `lean proof/check.lean` standalone 3.2 s; `lake build` 16 jobs clean; `#print axioms` on every `challenge_*` theorem lists at
most `propext, Quot.sound` (omega's), none for the `decide` theorems.

## 2. Findings (C-1 … C-25), with evidence, decision impact and who found them independently

Sources: **K** = the coordinator's own re-derivation (`Chk.*`), **R1–R5** = the per-problem reviewers, **RT** = the taint auditor;
"branch n" = convergence with an earlier challenge round known only from its commit message (§9). FLIP = a ranked decision
changes; MOVE = a number changes; WORDING = a statement is wrong as written while its decision stands.

**C-1 — "The 32k tie is SETTLED: E29 #1 on both caps (break-even τ = 0.19 %; measured 42× / 29× over)" rests on the retired line.**
HW-MAP:116, DESIGN-4:174-176, PROOF-COVERAGE-4:577 (R7.1), fleet.out:682-683. The 0.19 % is the break-even of the ROUND-6 line
(947 079 ns, the DERIVED E29 of 15.86 ms against the session-3 legacy 1 513 600): `Chk.breakeven_derived_line` (0.18 %). Round 7
moved E29 to the banked 14.64 ms, so the line is 991 940 ns (`Chk.tie32k_line`, = `T7r_tie32k_iff`) and the break-even trip rate is
**5.32 % of launches** (`Chk.challenge_breakeven_banked`: iff p ≤ 53 in 0.1 % units). The measured 8.0 % / 5.5 % are 1.50× / 1.03× over
it (`Chk.breakeven_ratios`), the wide-cap margin is 1 575 ns per layer = 0.17 % of the cell = 0.18 points of a measured rate, inside
the documented session-3 → 5 base drift (−3.8 %, `T6r_base`) and inside M0's own ±0.06 % flip point (R2-F2: fusion wins at the wide
cap if M0 ≤ 165.7 GB/s). Verdict: settled at cap 3072 (2.7 points, 4.5 % of the lever), a measurement-resolution tie at cap 61440.
Impact: WORDING — both levers are banked, nothing is built differently; but the sentence is the headline of ROUND 7 and is wrong as
written. Found by K, R3 (F3), R4 (F5), R2 (F2 via M0), RT (row 6) — five independent derivations.

**C-2 — The planner's expert-kernel anchor M0 = 165.8 / 170.2 GB/s has no HW-MAP row.** `grep -c '165\.8' HW-MAP.md` = 0; the
number lives in fleet.py:1569 / DESIGN-4:170-171 / ALTERNATIVES:94-97 and commit 8715562; PROOF-COVERAGE-4:577 cites "HW-MAP rows"
for it. Shapes, D, dispatch mode, arena, reference and reps are unrecorded — the provenance class of the 25 750 merge figure that
"existed only in a commit message" (PROOF-COVERAGE-3). Every ROUND-7 MoE cell and E29's banked value scale with it. Impact: an
HW-MAP row is owed (harness, shape, D, t, reps, arena); until then every R7 cell is DERIVED from an unlogged measurement. Found by
R2 (F2), RT (row 7); verified by K.

**C-3 — `T7r_inst` / R7.4 "two instances at the card-scale 2.0× = 3.853" doubles the 8-die CHAIN step.** fleet.py:1633-1636: `xs`
(the per-die int4 shares) is computed and never used; `T1 = step7(M, 32768, "amort-cap3072")` is the 8-die chain (129 743 539 ns) and
`tps_card_inst` doubles it. Two full-int8 363 GB instances need ≥ 2 × 5 dies (`T_min_dies`) — not a configuration of this fleet. The
V3 cell at round-7 anchors (hot slab 101 189, amortized attention 1 015 340, the int4 tier at 197 844 / with the #19 merge 206 157 /
230 458, quant pass) is **3.544 / 3.519 / 3.449** tok/s/card (K, `python3 -I`, the `Chk` instance model; R4-F1 independently 3.57 /
3.52 / 3.45), and the die-scale gain it needs to beat the round-7 chain (1.926) is **c ≥ 1.095**, not the ledger's 0.978 (F6-14).
Impact: MOVE (+8–12 % overstated) and a PROVED label on the wrong quantity; the MoE instance verdict survives (+79–84 %). Found by
R4 (F1); verified by K from the code and re-computed.

**C-4 — Dense V3 ("two 4-die instances, +49 %, the largest gain that needs no runtime change", DESIGN-4:1046, 1387-1388;
ALTERNATIVES rank 1 dense half) is dominated by batching on the single chain at every sequence count N ≥ 2.** Two instances serve
two sequences; the like-for-like comparator is the chain at B = 2, and the planner's own step gives chain(B) = 2 290 + 113.5·B ms
vs 2 × inst(B/2) = 3 224 + 56.8·B — the chain wins for every B < 16.5, i.e. everywhere in the measured flat region: 0.199 vs 0.150 at
N = 2, 0.364 vs 0.273 at 4, 0.625 vs 0.462 at 8, 0.974 vs 0.707 at 16 (R4-F2; R5-F1 −23 … −28 %). Even on the small model's measured
batching curve (1.53× at 2 clients) the chain edges V3 (0.159 vs 0.150). The MoE half stands (instances parallelize the expert
stream: 3.52 vs 2.21 at N = 2) but its margin is +79–94 % at equal N, not +107.7 %. Impact: **FLIP** of the dense row of §10's
no-runtime table and of ALTERNATIVES rank 1's dense half; the int4 tier, H11 and E30 are never needed for dense. Found by R4 (F2),
R5 (F1); converges with branch 1 ("dense V3 dominated by batching").

**C-5 — The cross-die split family is dismissed on erratum 11, which the later concurrency rows no longer support.** ALTERNATIVES
§4 rows "flash-decoding split-KV across dies" (:562, "errata #11 fault; at Π = 1 a cross-die split cannot run concurrently") and
"expert-parallel across the card's two dies" (:564, "no concurrency (dies alternate) … = the measured runtime fault"), DESIGN-4 §1.2
(:337-339), §5 (:1018, :1035 "tensor-split worked … the runtime faults on it", :1051). Erratum 11 records the VENDOR runtime's
tensor-split op faulting and its layer-split loop alternating dies; HW-MAP:334-345 (season h) MEASURES one process driving both dies
of a card with custom streaming kernels at 1.000–1.001 of their solo sum, two cards at 2.0×, and custom kernels are mandatory for
any concurrent serving anyway (:349-351). `T_dominated_expert_parallel` (alt.lean:1153) proves "a loss for every λ > 0" by adding 2λ
per layer to the UNCHANGED serial step — it formalizes the Π = 1 premise, not the family (R5). Re-priced on the measured primitive
the family dominates V3 for MoE at every client count and dominates everything for dense — `DESIGN-FORK-EP8.md` (§7 below).
Impact: **FLIP** of two dominated verdicts and of the build order, gated on one UNMEASURED capability (8-die per-layer dispatch +
host all-reduce). Found by K, R5 (F2), R4 (F3), RT (row 2); converges with branch 2 (the card-pair TP2 fork, whose 2-way gate the
i4-class sync since measured and met).

**C-6 — Serialized 91 µs launches sit in every primary MoE cell (18.0 ms = 13.9 %) against HW-MAP's own realized row.** HW-MAP:120:
"a serialised 91 µs floor is incompatible with the serving accounting (≥ 19.7 ms ≫ 7.7 ms)"; DESIGN-4 keeps 91 µs serialized as the
primary and carries 36 µs only as a reading (2.103). Consequences: the V2 megakernel's rank (DESIGN-4:1045, :1385 "3rd"; [PA-mega-20us]
1.979) rests on a 12.4 ms launch prize that is 3.1 ms at the realized bound; V2 pays iff c_sync ≤ 42.4 µs (MoE) / 41.2 µs (dense)
there, not ≤ 108 µs (`Chk.mega_lines`, `mega_dense_realized_iff`) — ERRATA-IMPACT §5's rejected 40 µs reading sits AT the line; the
draft token's 11.0 of 22.1 ms is launches; ALTERNATIVES §1 row 3, §2.3 and the combos (2.367 / 4.291) keep the 91 µs basis while
its §0 item 3 already adjudicates at 36 µs. Impact: MOVE (V2 → E40's size class); a FLIP of V2's sign if E31 reads ≥ 42 µs.
Found by R4 (F4), R5 (F3, F17), R2 (F3, F7).

**C-7 — The MoE spec-decode line was not re-derived at the measured anchors, and its verify step prices attention at the t = 1
cell.** `T6r_spec6_thresholds` (loss iff α ≤ 0.854) uses the round-6 T1 / T4; with E29 banked on both sides (the t ≥ 4 slab 98 573:
65.6 ms off the verify step) the line is **0.823** (`Chk.challenge_spec_moe_r7`; R4-F6 0.829 / 0.834 with the amortized attention).
The verify step's attention is 28 × 945 500 (the t = 1 cell) while the only measured t = 4 cell is the legacy kernel's 2 695 600 ns —
the deferred t = 4 cell is UNMEASURED (E41); `Chk.challenge_spec_moe_t4_attention` proves the quoted line is a LOWER bound on the
loss region for every a₄ ≥ the t = 1 cell. The dense line (v ≤ 31 092 727) is parameterized and robust (32.8×). Impact: MOVE.
Found by K, R4 (F6).

**C-8 — The 1M amortization at the measured trip rate is +7.6 %, not +0.08–0.21 %.** [R6-amort-1M], DESIGN-3:872, :1202, R6-3 carry
the stale premise; at τ = 8 %: 28 694 000 + 0.08 × 27 306 000 = 30 878 480 ns (`Chk.challenge_amort_1M`); DESIGN-4's R7 1M headline
(0.276) uses the trip-free cell. Transfer of the 32k rate to 1M is itself an ASSUMPTION in the optimistic direction. Impact: MOVE
(−7 % class; attention-bound by 7×, no rank flip). Found by R3 (F8).

**C-9 — "MoE-128k attention-bound by 12.8 %" is on the retired anchor.** DESIGN-3:11-12, DESIGN-4:9-10, `T6r_fleet_moe_128k`
(tLayerMoe = 3 207 719). At the banked anchor the layer GEMM is 2 684 759 ns and the measured cell is attention-bound by **34.7 %**
(`Chk.challenge_moe128k_anchor`); the legs-conditional lines (189.4 / 178.9 / 168.3 — all reproduced, `Chk.moe128k_legs_lines`) are
moot: on that anchor the cell is attention-bound at every G ≤ 226.5 GB/s, above the DDR roof. Impact: WORDING; the verdict is
stronger than stated. Found by K, R3 (F9), R4 (F10).

**C-10 — Erratum 12 (W4 silicon-dead) was measured once, pre-#18 / #25, by the probe family whose k = 64 verdict was later
retracted; the whole 5-die / int4-tier / 320–400 GB band stands on it.** `git log -S`: erratum 12 entered HW-MAP in 7f53dce
(2026-11-04); erratum 18 (C-destination view offsets land in chunk 0) in 423d433 and erratum 25 (A-slot staging zeroes rows ≥ 2) in
62e8137 (both 2026-11-07); the k = 64 reader bug was retracted on 2026-11-11. "All-zero C via staged operands" is the #18 symptom
and "zeroed rows" is #25's; the tuple was never re-probed through the owned dump path. If i4×i4→i32 is alive at ≥ 120 GB/s: resident
bytes halve, three dies hold either shape's weights (`Chk.challenge_min_dies_int4`), T_min_dies 5 → 3, the V3 int4 tier is dominated
by plain W4, dense 1M fits with f16 KV headroom. Impact: a **potential FLIP** of the largest set of decisions in the corpus; the
re-probe (RT §5 item 2: one-hot identity operand maps, explicit byte-offset C tensors, offset-0 4 KiB A staging, two k-tiles, 20 reps,
fp64 oracle) is half a day. Found by RT (row 1); dates verified by K.

**C-11 — The drift family bounds the f32 accumulation only; the f16 cast of P is the dominant numerical term.** `T4r_drift_online`
/ `T5r_drift`: 246 ppm bound vs 1.2 ppm measured ("833× inside the ship line"). out = O/S with O from the f16-cast P (DESIGN-3 §3.2
step 5) and S from the f32 P: every weight carries ≤ 2⁻¹¹ = 488 ppm (`Chk.challenge_f16_P_cast`) — a bias, not drift, 2.0× inside
the 1e-3 line and in no theorem; the "bitwise-exact vs host" check is a shared-rounding reference (erratum-32 class) that cannot see
it, the f64 E27 reference can and did not fail (consistent with 488 ppm < 1e-3). Impact: WORDING (R5-15 should read "f32 chain 833×
inside; f16 P cast 2× inside"); the same term is the natural mechanism of the round-6 "random-profile out-verify floor". Found by R3 (F5).

**C-12 — E40's vector input contradicts HW-MAP's own softmax-phase figure; the k ≤ 2 schedule and the 966 ns gate are unsupported.**
[E40-vec]: V = 1 085 ns/block (session-3 unguarded softmax 69 500 / 64) + fold + merge ∈ [1 438, 2 107] ≤ 2d = 3 010; HW-MAP:116:
"'−59 µs' is the softmax-PHASE delta alone — 565 vs 624 µs". If 565 µs is the deferred kernel's softmax phase at 32k t = 1, V = 8 828
ns/block (5.9 × d) and E40 cannot beat the deferred kernel at k ≤ 2 for ANY φ; only k = 8 fits, with gate φ ≤ 241 ns = 41–83× under
erratum 29's band (`Chk.challenge_e40_V565`). It also means scores + PV (868.8 µs, session 3) cannot sit inside a 945.5 µs total
unless the deferred kernel is already partially overlapped — contradicting §7's "chain-serial reading carries over". If 565 / 624 are
NOT the 32k t = 1 phases, HW-MAP carries a phase number with no frame. Either way E40-3's "INPUT (sessions 3 and 5)" hides that the
V input is from a kernel the deferred one does not share. Impact: the E40 ladder gate ("φ ≤ 0.6–1.7 µs → E40b") is not the right gate
until E41 times the deferred kernel's phases — E41 before E40a's interpretation. Found by R3 (F4); converges with branch 1.

**C-13 — E40's prologue page-table fetch is O(L) US.** DESIGN-3:1060-1062 (rule 3, "≤ 16 KiB at 1M") vs the shipped 4 KiB window;
at mt = 4: 200 768 − 4 096 + 16 384 = 213 056 B = 208 KiB + 64 B (`Chk.challenge_e40_pagetable`) — the identical 64 B overrun round 2
corrected. Impact: none on a rank; E40b must keep the 4 KiB window (refills ≤ 8 at 1M ≈ 0.3–0.6 % of the cell). Found by R3 (F7).

**C-14 — The region-difference exactness license assumes WRAP semantics and zero prior content; HW-MAP measured SATURATION with
nondeterministic L0C content.** DESIGN-2:264-270 ("exact whatever the region held before, in modular i32 arithmetic"),
PROOF-COVERAGE-2:136-138 PROVED, `T_overflow_modular_diff` (assumes wrap), `T_overflow_region_exact` (no initial term); HW-MAP:118.
Under saturation the difference is exact iff |b| + Σ|S_i| < 2³¹: U_max = 32 at b = 0, **16** at b = 0x3F800000 (an f32 1.0 pattern,
what the preceding attention kernel's L0C chunks hold), **0** at b ≥ 0x7F000000 (`Chk.challenge_overflow_prior_content`). The design
needs 2 uses per region at the headline (safe for |b| ≤ 2.0e9) but 22 at D = 128 (t = 16 uniform): worst-case operands saturate for
any |b| > 0.69e9. At the A-magnitude the design assumes (~1e6 per expert, ASSUMPTION) the headroom is ~1 000 uses — safe in practice;
the "PROVED ∀ history" license is false as stated. Fix: a bounded-b contract or a per-launch region reset (≤ 1 041 constant-tile MMA
calls = 15.6 µs per region). Test: plant 0x7F000000 in all regions via a preceding launch, then run E15. Impact: exactness license,
not a rank. Found by R2 (F1).

**C-15 — CHEAT-MATH §B's roofline pairs ONE core-cycle's 8 192 OPs with the whole die's 170 B/ns; CHEATSHEET §0's "four
independent agreements with HW-MAP" are neither independent nor agreements.** `Cheat.ridge_bounds` (48·170 < 8192 < 49·170) is
true arithmetic on a wrong pairing: the die's MEASURED 17.8 TFLOPS against 173.8 GB/s is a ridge of **102 OPs/byte** (free rows ≤ 51
on W8; a 16-row tree is free on 4-bit weights too, so `tree16`'s conclusion is wrong on this machine); the lane budget is 8 × 43.2 =
345.6 G lane-ops/s per die against the 4-bit stream's 347.6 G elem/s — one lane-op per element — and the MEASURED 5-pass unpack
(42 GB/s = 84 G elem/s) is **24 %** of the stream, not "< 12 %" (`Chk.challenge_ridge_units`); HW-MAP's decode occupancy is 12.5 %
(`Chk.challenge_occupancy`), not "4–8 %"; "KV parity ~30k = our measured attention-bound flip at 32k" — MoE 32k is weights-bound
(attention 18.6 %), the flip is at 131 103 / ~97 k tokens, and the 2^15 parity is an 8B-class shape with a 4 GiB weight set; and the
research session had the machine profile inlined (PROMPT-8), so "before reading our numbers" is false. Impact: CHEATSHEET §0 is
BROKEN; no shipped decision reads a CHEATSHEET number. Found by K, R1 (F2), R5 (F6–F10), RT (§2 d).

**C-16 — `proof/cheat.lean` carries an axiom.** `crt_15_16` closes by `native_decide`; `#print axioms Cheat.crt_15_16` lists
`Cheat.crt_15_16._native.native_decide.ax_1_1`, against README ("no native_decide") and commit 85a79d0's "0 sorry/axiom"; the file's
own header lists native_decide as permitted. The fact is a core theorem: `Chk.crt_15_16_core` (omega, no axioms); `decide +kernel`
also closes the original in ~2 s (R5). Impact: the build claim is false; one-line fix owed to the steering (this round does not edit
existing proof files). Found by K, R5 (F5).

**C-17 — CHEATSHEET rows #1 / #3 / #4 are graded without the errata.** #1 "~30 % off EVERY f16 stream = ~1.4× effective wall": the
weight streams here are int8 (no exponent field); a vector-side unpack emits f16 at ≈ 1.0× the wall and the S1→L0B loader caps at
26.5 × 8 = 212 GB/s ≤ 1.25× even with a free unpack; the only f16 stream (KV) is dominated by the measured K-int8 (2.13×). #3 "KV 2–4
bit ×2–4 beyond KV-int8": erratum 12 — no i4 path; a 4-bit KV unpacked at ~42 GB/s int4 aggregate costs ≈ 1.04× KV-int8's time per
extent, not ×2–4. #4 "W4A8 … 3.5× validates our W4 route": W4 rides as int8 at load here (no stream-byte cut, 2× memory). Impact:
ranking of future work only. Found by R5 (F11–F13).

**C-18 — The deferred-guard cells were measured on the extent-truncating kernel; timing unaffected, the correctness ledger rows
are tainted and unannotated.** Dates (git): session-5 cells 3928d0e = 2026-11-08; erratum 32 (exclusive-of-self boundary) 2080e4c =
2026-11-10; the floor16 extent fix 081c36b = 2026-11-11. The sweep L ∈ {4 096, 32 768, 131 072, 1 048 576} are multiples of 16, so the
bytes streamed were identical and 945.5 / 3 618.8 / 28 694 µs stand as timing cells of the pre-fix kernel; the post-fix tail path
adds ≤ 0.5 % (U). But DESIGN-3:840 ("causal-exact end-to-end — 12/12 cells … bad 0"), :1577 ("E27′ — causal half CLOSED") and
PROOF-COVERAGE-3:253 (R5-20) are exactly the double-blind cells; neither file mentions erratum 32, 34 or the fix. Impact: no cell moves;
R5-20 / E27′ should read "CLOSED on the post-fix kernel by the serving-loop decode-step compares (HW-MAP:423-426)". Found by R3 (F1).

**C-19 — Three retry-share statements disagree, and the wide-cap prize is misquoted.** T(τ) = 945 500 + τ·872 600 gives 6.9 % /
4.8 % of attention ms at τ = 8 % / 5.5 %; HW-MAP:359-360 quotes "7–10 % / 5–8 %", HW-MAP:427 "10–15 %" (the pre-fix integration
reading); HW-MAP:116 "trips −45 % … ~−50 µs/layer" vs the same row's 1 015 → 993 µs = −21.8 µs/layer; "−567.5 … −568.6 amortized" is
at the stale premise (499.6 / 521.4 µs at the measured rates). Impact: WORDING; direction-safe for the E29 verdict. Found by R3 (F2).

**C-20 — P1 hygiene.** DESIGN.md:24-27's SILICON banner says R3 "has since run at 137.8" and "k = 64 is anomalous" — HW-MAP has
174.6 flat m = 1..16 and RETRACTS the k = 64 verdict; HW-MAP:26 and ISA:60-61 still list the i4→f16 dequant instruction as live against
erratum 12; HW-MAP:106 ("DDR → L0 direct load instructions … UNMEASURED, may be a silent no-op") contradicts row 105 (MEASURED
181.3); the m ≥ 24 cliff 81 / 59 / 43 equals the flat rate ÷ strips (87.3 / 58.2 / 43.6, `Chk.challenge_rows_cliff_strips`) — P1's
own dominated M-split (`T9_msplit` 43.1 at m = 64) to 0.2 %: the "unresolved wedge" is weights re-streamed per 16-row strip, a
kernel-structure diagnosis that E37 should carry as its expected signature. Found by R1 (F1, F3–F5); verified by K.

**C-21 — DESIGN-2 at the realized launch and the measured kernel.** Z8's K-split margins at 36 µs: (4,32) −9.2 and (16,68) −14.7 µs
flip to K-split (`Chk.challenge_ksplit_realized`; S-G2 still wins every cell); F = 8 µs per launch (ASSUMPTION) is contradicted by the
measured t = 1 / t ≥ 4 pair — an implied fixed cost of ~28 µs (R2-F4, consistent with erratum 29's dispatch crossing); erratum 16
(same-dst spacing) was never audited against the small-N_e loop (spacing 4 at N_e = 512 is unlicensed; G = 4 restores 16) (R2-F5);
`T_Z7_no_s_threshold` closes by `Iff.rfl` (vacuous) (R2-F6); the i4×i4 route is still "EMPIRICAL — E19" in the ledger against erratum
12 (R2-F11); fleet.py adds 2 F_MOE = 16 µs per layer on top of a whole-launch M0 rate that already embeds it (0.6 % conservative,
R2-F9). Impact: MOVE / hygiene.

**C-22 — "V3 needs c ≥ 0.978 of the measured 1.990" (F6-14, DESIGN-4 banner) is stale: 1.095 at round-7 anchors** (C-3's instance
cell against the 1.926 chain; K and R4). Measured 2.0 at card scale — other topology (single-device instances vs 2-card chains with
8 bounces per token); the 2-card inheritance (H10′) is still open (PROOF-COVERAGE-5:144). Impact: MOVE; the MoE instance verdict holds.

**C-23 — The served 4-kv-head model runs 4 of 8 cores; DESIGN-3 §2.1's 8 ∤ H_kv L-range split is unimplemented.** HW-MAP:405-408
names the split-KV-token core map as the measured ~40 ms/step lever (39 % of the 103 ms step at 9.7 tok/s); DESIGN-3's ladder ranks
E40 (≤ 8.6–13.1 % of the 32k cell) as the attention-side #1. The planner's shape (H_kv = 8) is unaffected; every serving-ladder
"kernel arm" cell at 4 kv heads is conservative by up to 2× on the attention side. Impact: lever ranking for the served model. Found by R3 (F6).

**C-24 — The instance fit margins are grid remainders, honestly labelled.** 1 ‰ of x = 45.1 MB (MoE) > the 24.5 / 40.3 MB margins
(`Chk.inst_margin_is_grid`); the hostage is H8 (2 GiB, never measured); +1 GB costs +23 ‰ x and 0.66 ms (0.5 %); no flip before ≈ +7.5 GB
(the MoE 1M instance at x = 827 ‰). Found by K, R4 (F9).

**C-25 — Two "validations" are weaker than their words.** "The choreography model is VALIDATED within 2.9 %" (HW-MAP:115) nets three
cancelling term errors each larger than the match (chain −97.7 µs, bounce +48.1, K/V +22.4 — the corpus says so at DESIGN-3:1247-1253)
and the word was placed in the steering prompt before the round ran (PROMPT-3R5:21-23); "the amortized band reproduces both ends
exactly" is a two-point line through two measured cells evaluated at a (stale) third point — the corpus labels it "not a third
measurement" and the ledger still marks the reproduction PROVED. Steering-injected numbers (−59 µs, −558 µs) that reproduce from no
cell were caught by the proof round — evidence that the prompts are a taint channel and that the ledger discipline works. Found by RT (§2 a, b, f).

## 3. Taint ranking — the INPUT rows the decisions stand on, by blast radius

"Arena" = what the harness exercised; "claim" = what the number asserts. Erratum 32's five harness-deception members: PA pattern-
aliasing, AC arena-coincidence, DR dump-reader offsets, PT shared-page-table clobber, PB probe-baseline cross-head aliasing; plus
E17 (rate loops elided) and E33 (stale binaries / context). Confidence is the auditor's, re-read by the coordinator.

| # | input (HW-MAP row) | harness / session | arena vs claim | stands on it | class | a same-class bug would … | conf. |
|---|---|---|---|---|---|---|---|
| 1 | **erratum 12: W4 silicon-dead** (:157-170) | raw probes ≤ 2026-11-04 (7f53dce), before #18 (423d433) and #25 (62e8137) were known; never re-probed | staged A / C addressed the pre-#18/#25 way; "all-zero C" is the #18 symptom, "zeroed rows" #25's | PROBLEM-4's 320–400 GB band, T_min_dies, the V3 int4 tier, T_instance_gain, DESIGN-2 §8.4, ALT rank 1, CHEATSHEET #4 | DR / AC | **FLIP**: 3 dies suffice, V3's tier dominated by plain W4, dense-1M fits with f16 KV (C-10) | right ≈ 60 % |
| 2 | **Π = 1 "dies alternate, no concurrent streaming"** (erratum 11, :152-156; "+1.4 %", :346-348) | vendor serving runtime, one sequence, small model | one sequence through a layer-split chain (a serial dependency) read as a fleet constraint; :334-345 measures the dies streaming concurrently | every DESIGN-4 throughput cell, the instance decision, §10's "H4 reverses V3", ALT §4 rows 562 / 564 | AC (scope) | **FLIP**: the split family (C-5, §7) and Π = 8 (7×); not a measurement error, a generalisation | Π = 1 as a hard limit: low–medium |
| 3 | **deferred-guard cells 945.5 / 3 618.8 / 28 694 µs; legacy 1 514.9; guard-off 902.9; canonical 1 818.1** (:116) | kernel session 5 (session 3 for the legacy sweep) | synthetic headline shape, static span, compact per-core arena (arena == span, erratum 34), single die, references sharing the kernel's causal convention until 11-11, the pre-fix extent (C-18) | ≈ 39 ledger rows / 36 theorems (PC-3 R6-*, PC-4 F6-* + R7.*): MoE-128k, the tie, the spec line, E40, §10‴ | AC (34), shared convention (32), one harness artifact already found (the session-4 fold misread) | cross-session base reproducibility is **3.8 %** (938.8 → 902.9) while the legacy arm reproduced to 0.1 %: any decision under 4 % is inside noise — the wide-cap tie is (C-1); MoE-128k (34.7 %) and MoE-32k weights-bound (18.6 %) survive | cells ±5 %: medium-high; as the planner's per-layer term: medium |
| 4 | **E21 G(P) = 169.2 / 167.0 / 153.8, c_pg = 38 ns** (:52-83) | season-v1 pack, one harness | 64 MiB contiguous per-core arenas, shuffle within the arena (a lower bound by its own statement); the direction was once read backwards | DESIGN-3 round-3 cells, the page verdict, two-tier "iff c_pg ≥ 1 ns", `T3r_moe128k_tie`, fleet R3 | AC by construction | two thresholds in plausible range for a fragmented cache: two-tier overtakes 256 KiB at c_pg ≥ 160 ns; MoE-128k at 64 KiB flips at ≥ 123 ns — moot at the M0 anchor (C-9); the 174–176 stream phase cross-checks the sequential rate, NOT c_pg | sequential high; c_pg as a real-cache number low–medium |
| 5 | **m ≥ 24 cliff 81 / 59 / 43** (:108) | the W8 kernel, one build, "wedge unresolved" | a kernel-structure artifact read as silicon: = 174.6 ÷ strips (C-20); the vendor f16 path is MEASURED flat to M = 128 (:29-30) | B·t ≤ 16 everywhere, "B = 16 excludes spec", CHEATSHEET #8 / §0's "free rows ≤ 24" | kernel defect as silicon | **FLIP for the batching cells** if the wedge is fixed (B = 32–64 open; ALT 4k ×3.2 / ×1.9) | cliff kernel-side: high |
| 6 | **the serial expert anchor 122 979 ns** used as E29's counterfactual (fleet.py:34, 1584; PC-4:579) | not a harness: a subtraction from the 137.8 dense cell at HW-MAP@a6d0ec0 (c_res 25.4 fitted); re-anchored to 24.4 at 138.9 (moe.out [M29]) but never propagated | a kernel that was never built | R7.3 / R7.5, ALT :94-97, §10‴ at MoE 32k / 128k | model-vs-measurement "gain" | **FLIP of the inert tie**: re-anchoring to c_res 24.4 shrinks the slab 1 024 ns → E29 13.96 ms → fusion #1 on both caps (RT); the margins are 975 / 66 ns per slab | arithmetic high; consequence low |
| 7 | **M0 165.8 / 170.2** | "expert-kernel dispatch cells, silicon 20/20" (fleet.py:1559-1571) | **no HW-MAP row** (C-2); shapes, D, mode, arena, reps unrecorded; PC-4 R7.1 cites "HW-MAP rows" falsely | every R7 cell, E29 banked | unauditable | moves every MoE cell ∝ M0; flips the wide-cap tie at ±0.06 % | provenance gap high; value plausible (99.2 % of the derived 167.1 — a genuine forecast) |
| 8 | **τ = 8 % / 5.5 %; R = 873 µs** (:116, :356-360) | serving remeasure, one model (32q/8kv, qk-norm), 32k single span; R from the synthetic canonical cell | one model, one context, "trips SKEWED"; the previous premise came from an A/B probe that compared the arm to itself (PB, erratum 32 member 5) and stood two rounds (30–40× stale); a second quote reads 10–15 % (C-19) | R7.2–R7.4, the amortized headline, the 1M cell (C-8) | PB (already happened to this input) | no ranked decision flips in 5–16 % (deferred > legacy up to 65 %; more trips widen E29); the wide-cap tie flips at −3.3 % relative | medium |
| 9 | **realized launch ≤ 36 µs** (:120) | DERIVED from the serving byte accounting (67 − 59.3 = 7.7 ms ÷ 32 × 9) on the small model | an 8B-class model, vendor loop; the planner model's graph is 28 × 7 launches | R7 "2.103", `T_alt_mega_savings_realized`, ALT §0 item 3; the fork's sync term | residual-as-measurement | V2's case was killed by this bound; at 91 µs on the planner model it returns to +12.5 % MoE (C-6) | medium |
| 10 | **MMA n caps at 16** (:461-463) | the parameter-sweep reader whose k = 64 verdict was RETRACTED (dump decoded at 16 KB spacing vs 1 KB chunks); k64x re-characterised k only, at n = 16 | columns 16+ reading as zero is also what a mis-offset reader shows | the 16-chunk (16,16,128) loop, 15 ns/call, every MMA-share cell, the (16,256,64) impossibility, CHEAT prefill 5.33× | DR — the retracted class | no decode decision (DDR-bound at m ≤ 16); moves prefill and t ≥ 4 cells | cap real: ≈ 50 % |
| 11 | **bridge ≈ 0.33 ms/layer + ≈ 85 µs/span** (:400-404, :386-390) | serving sessions, two dies, per step | the planner's step has NO per-step serving term; §10‴ ranks E40 (0.12 ms/layer) above the bounce while a MEASURED 0.33 ms/layer sits unranked | §10‴ "E40 is the attention-side #1" | static-span vs per-step coincidence | order E40 > bounce unchanged; the largest attention-side lever at 32k on the served model is the bridge / host Q-pack (and the 4-of-8-core map, C-23); MoE 32k 1.956 → ≈ 1.83 if the bridge transfers | medium-high |
| 12 | **E22 op set** (:32-50) | isolated chained 1 024-lane probes; erratum 17 found in the same pack | latency-bound calls composed into the round-3/4 chain; session 3 measured the unguarded softmax at 1 085 ns/block vs the chain's 3 317 (3.0× over-charged) | round-3/4 chain, S4 dead, rows* = 32, L_eq; superseded at t = 1 by cells | E17; composition | S4-dead holds ∀ merge; rows* and the verify-batch regime did not survive (already superseded) | per-call high; composition low |
| 13 | **serving ratios 1.31× / 1.80× / 2.00×, np4×32k 1.40×, 3.32×, 9.7 tok/s** (:374-417) | serving sessions, 8B-class models | outputs WRONG when first measured (arena-stride, shared page table — PT); a dead 4.5 GiB/step vendor op left in the kernel arm's graph until 11-15; erratum-33 traps | CHEATSHEET framing, the 36 µs bound, batching 3.26× | PT, E33 | np cells re-measured on correct attention (1.39 → 1.40: "speeds stand" verified for that class); no planner decision reads them directly | medium |
| 14 | **R_w4v 5.3 GB/s/core; serial piece 807 ns (D)** (:109) | one vector probe (5-pass), predating erratum 17's reps-scaling rule | an elided pass makes 5.3 OPTIMISTIC | T_instance_gain (6.9× margin), dense V3 serial cell | E17 | MoE verdict survives a 6.9× error; dense V3 already dominated (C-4) | medium-high |
| 15 | **86 GB usable + 2 GiB overhead (H8, A)** (:89) | runtime report / assumption | — | dense-1M KV-int8 fits at 84.3 (1.66 GB margin); instance x (+23 ‰ per GB) | — | dense-1M feasibility flips at +1.66 GB; T_min_dies does not | medium |
| 16 | **erratum 19** (:220-232) | session 1, the same session that found #18; firmware-invariant via the same reader | invariance ≠ independence (the k = 64 wrong read was also firmware-invariant) | fresh chunks (structural), cold tier +8–33 µs/slab, lazy-rescale VOID | DR / #18 class | no pessimistic flip (fresh chunks still work; if wrong, things get cheaper) | medium-high |
| 17 | **errata 29 / 31: crossing 10–20 µs; guard scan 574.8 µs** (:257-276) | sessions 3–4; 574.8 is a table difference of two kernels | the per-crossing constant is inferred; transfers to DDR-flag polls (megakernel 20 µs) and bounds E40's φ | deferred guard, V2, E40 gate, E39 killed | — | megakernel pays iff c_sync ≤ 42 µs at the realized launch (2.1× margin, C-6); E40 rides φ (U) | guard delta high; transfer medium |
| 18 | **t ≥ 4 "99.6–103.4 GB/s"** (:115) | session 3, per-16-row-fragment normalisation | reads as "verify batches stream KV faster"; raw 134 MB / 2 695.6 µs = 49.8 GB/s; the deferred t ≥ 4 cell is U (E41) | spec cells, the MoE loss line (C-7) | normalisation aliasing | dense spec 32.8× margin; MoE spec stays a loss at α = 0.7 | high |
| 19 | **c_q = 43.7 µs** (:110) | integration season, m = 1, K = 8 192 only | fixed vs proportional at rows > 1 is U (E38); the "+12.2 % over host-packed A" has no reproducible base (R1-F8) | every R3+ cell (0.9 % / 3.5 %), draft +23 % | #29 class at rows > 1 | none | high at m = 1 |
| 20 | **λ = 12.2 µs** (:119) | one probe, 4 KiB legs, idle = under D2D load | per-direction latency of every exchange; the multi-participant round of the fork is U | every R3+ cell (≤ 0.17 %); the fork's sync | — | none (≥ 78× margins); the fork's line is 13.6× its sync assumption | high |

Two provenance defects outside the table: HW-MAP:105 vs :106 (direct load MEASURED 181.3 vs "UNMEASURED, may be a silent no-op"
— a stale row); ALTERNATIVES:105 "rests on the measured sub-µs cross-core sync" while E31 is EMPIRICAL / unmeasured in every ledger
and HW-MAP has no such row (a prose-only measurement, 25 750-class).

**Measurement-reliability base rate (RT §3, re-counted by K from the 67-commit log).** ≈ 100 MEASURED claims in HW-MAP; ≈ 24
corrections / retractions / re-scopes recorded in 12 days, of which ≈ 10 are qualitative reversals (sign / existence / verdict:
erratum 3, k = 64 twice then retracted, exactly-full L0C, same-pair flags, f16×i8, the E21 direction, causal-exact, the trip premise,
"length edge") and ≈ 6 are ≥ 2× in magnitude (the 4k 390–422 VOID, −59 µs re-scoped 9.7×, trip premise 30–40×, launch 2.5×, the
32k serving 1.56×). Every correction hit a row measured ONCE by ONE harness or an interpretation of one; none hit a row with two
independent measurements (§8). Prior: a single-harness, un-cross-checked MEASURED row is wrong by a reversal or ≥ 2× with
P ≈ 20–30 % per month, a cross-checked row ≈ 3–5 %; conditional on flipping a ranked decision ≈ 10 % per row, but the thin-margin
decisions (the wide-cap tie 0.17 %, c_pg thresholds 3–4×, dense V3 serial −3.8 %, dense-1M fit 1.9 %, Π = 1) make P(at least one
standing ranked decision flips within the next two kernel sessions) ≈ 50 %.

**Measured once, one harness, no independent cross-check (the dangerous class):** erratum 12 · the n-cap 16 · E21 c_pg and the 16 KiB
penalty · the deferred 128k and 1M cells (32k has a legacy A/B and a cross-session base; 128k / 1M have neither) · τ = 8 % / 5.5 % ·
R = 873 µs · M0 · the 36 µs residual · the m ≥ 24 cliff · R_w4v · c_q · λ · K-int8 87.6 · i32 saturation and the s8-cast / Min-Max
semantics · erratum 19 · the batching curve · the bridge 0.33 ms · 86 GB usable; plus two A-class numbers carried as if measured:
the 2 GiB overhead (H8) and the 122 979 ns anchor.

**De-tainting experiments, by information per hour (RT §5, ordered by the coordinator):**
1. Rows 6 / 7 (the tie, the anchor, M0) — one hour, no silicon: restate the tie with the anchor as a hypothesis variable, bank E29
   with no counterfactual, add the HW-MAP row for M0 (harness, shapes, D, t, arena, reps), and either propagate `T_sync_reanchor`
   (c_res 24.4) to fleet.py or retire it.
2. Row 1 (W4 dead) — half a day: re-probe i4×i4→i32 and the dequant copy modes through the owned dump path with one-hot identity
   operand maps (the k64x protocol), explicit byte-offset C tensors (#18-safe), offset-0 4 KiB A staging (#25-safe), two k-tiles
   (initVal inversion visible), 20 reps, fp64 oracle. Failure modes: all-zero C with the one-hot control also zero = dead; exact =
   alive. Decides T_min_dies, V3 vs plain W4, PROBLEM-4's band.
3. Row 2 / the fork's gate — host-only afternoon (the fork's S1–S2, `DESIGN-FORK-EP8.md` §6): two threads, both dies of one card,
   the split kernels concurrent, outputs byte-exact vs the single-die kernel ×20; the per-layer all-reduce ×10³ with host checksums.
4. Row 4 (c_pg) — half a day: the production attention kernel over a KV cache allocated by the real serving allocator after 200+
   sequences of churn vs the same tokens in a compact arena; c_pg = ΔT / pages at 64 and 256 KiB.
5. Rows 3 / 8 / 11 — one day: the deferred kernel INSIDE the serving loop per layer at 32k on the real model, 1 000 steps, 3
   prompts: snapshot-differencing oracle per step, per-layer time distribution vs 945.5 µs + bridge, the trips-per-launch histogram
   (τ and its skew), the per-engine phases (E41).
6. Row 10 + row 5 — half a day: (16,256,128) with per-column-block one-hot B through the owned dump path; the W8 kernel at m = 24 /
   32 / 64 with a per-strip differencing oracle (expected signature: rate ∝ 1/strips = B re-fetched per strip).
7. Row 9 — two hours: N empty launches per layer (N = 0 / 4 / 8) in the serving loop → the realized per-launch cost as a slope.

## 4. Decision sensitivity — the UNMEASURED / ASSUMPTION variables whose adverse resolution FLIPS a ranked decision

| # | variable (tag) | threshold | the decision that flips | today's reading |
|---|---|---|---|---|
| 1 | **8-die per-layer dispatch + host all-reduce from one process** (U; measured at 2 dies / 2 cards) | the per-layer orchestration overhead < 1 640 102 ns at MoE 32k (`Chk.ForkEP.ep_sync_line`; 13.6× the λ-and-launch sum) | if it holds: the build order — V3 / int4 tier → the split family (`DESIGN-FORK-EP8.md`) for MoE at every N, and for dense everything; if it fails: the fork is dead and V3 (MoE) stands | sync assumed 120.8 µs; bracket top 500 µs still wins (2.607 vs 1.956) |
| 2 | **erratum 12 — i4×i4→i32 dead** (M once, pre-#18/#25) | alive at ≥ 120 GB/s | T_min_dies 5 → 3; the int4 tier retired; dense-1M f16-feasible; PROBLEM-4's band halves | dead (≈ 60 % confidence) |
| 3 | **H4 — the runtime pipelines independent sequences** (EMPIRICAL) | yes | every Π = 1 cell ×7, V3 undone (as DESIGN-4 §10 says) | open; batching is its measured substitute at ≤ 16 rows |
| 4 | **client count N** (frame, not a measurement) | N ≥ 2 | dense V3 (+49 %) → a loss at every N ≥ 2 (C-4) | already flipped on the planner's own model |
| 5 | **τ at the wide cap** (M, one model / span) | ≤ 5.32 % of launches | the #1 lever at MoE 32k on cap 61440 (fusion ← E29); inert, both banked (C-1) | 5.5 % (1.03× over) |
| 6 | **M0** (M, no HW-MAP row) | ≤ 165.7 GB/s (−0.06 %) | the same wide-cap flip; at the shipped cap M0 < 164.2 (−1 %) | 165.8 |
| 7 | **c — the two-card inheritance of the measured 2.0×** (U at the 2-card chain topology) | < 1.095 | MoE V3 loses to the round-7 chain (ledger: 0.978, stale — C-22) | 1.99 / 2.0 measured on other topologies |
| 8 | **c_sync** (E31, U) | ≥ 42.4 µs (MoE) / 41.2 µs (dense) at the realized launch (≥ 108 µs at 91 µs) | the megakernel V2 turns negative (C-6) | 20 µs primary (erratum 29) |
| 9 | **launch reading** (91 serialized vs 36 realized) | — | V2's rank (12.4 vs 3.1 ms prize); the 8-way split launch-bound or not; the draft token's 61 % | HW-MAP calls 91 serialized incompatible; the planner keeps it primary |
| 10 | **E30 — the cold tier's regime** (U) | serial (807 ns/piece) | dense V3 → a loss (moot after C-4); MoE V3 3.13 (holds) | overlapped assumed |
| 11 | **H9 — real routing skew** (U) | D(4) ≤ ~22 | MoE spec decode on/off (loss line 0.823 uniform → 0.65 Zipf 1.5); the fork's placement balance (hot-expert collisions need popularity-aware placement; worst case = the chain + sync) | synthetic generator |
| 12 | **H8 — per-die overhead** (A, 2 GiB) | +1.66 GB | dense-1M KV-int8 infeasible; +7.5 GB kills the MoE 1M instance fit | never measured |
| 13 | **c_pg at production scatter** (M lower bound 38 ns) | ≥ 123 ns (MoE-128k at 64 KiB) / ≥ 160 ns (two-tier) | moot at the M0 anchor for 128k; the two-tier page row | 38 ns in a contiguous arena |
| 14 | **E41 — the deferred kernel's t = 4 / 16 cells and 4k cell** (U) | a₄ ≥ 945 500 only widens the loss region | the MoE spec line (a lower bound today, C-7); the dense line has 32.8× margin | legacy t = 4: 2 695 600 |
| 15 | **φ (E40a) and the deferred kernel's V (E41)** (U) | E40 live iff φ ≤ 966 ns at k = 2 given V ≤ 3 010; iff φ ≤ 241 ns at k = 8 if V ≈ 8.8 µs (C-12) | whether E40b is built | erratum 29's band 10–20 µs |
| 16 | **the P-i8 numerics of full KV-int8** (E36, U) | relerr > 1e-3 | ALT rank 6 (+75 % at 1M) → rank 7 (+27 %) | K-side measured exact |
| 17 | **the 2-participant all-reduce under load** (U; one idle 4 KiB leg measured) | T_red ≤ 306 µs (MoE) for the 2-way split to beat replication at 2 clients; ≤ 1 556 µs for the 8-way | the fork's 2-way rung vs V3 | model 27–34 µs |

The round's single most valuable line: **#1** — one host-only afternoon (the fork's S1–S2) decides whether the corpus's #1
no-runtime lever is V3 (an int4 tier, the #19 merge, E30, H11) or a split that needs none of them.

## 5. The dominated-alternatives table and the ranked table, re-scored on the current HW-MAP

| row (ALTERNATIVES.md) | premise as written | premise now | re-score |
|---|---|---|---|
| §1 #1 replication + minimal W4 tier (54 / 24) | Π = 1 idles 3 of 4 cards; 2 instances × 1 client vs 1 × 1 | equal clients: MoE +79–94 % (model) / +36 % (measured batching curve); dense −23 … −28 % at every B ≤ 16 (C-4) | MoE 40–47; **dense 0**; both dominated by the split family (§7) which needs no W4 tier |
| §1 #2 direct-path expert kernel (21 / 12) | derived 167.1 | MEASURED M0 165.8 (99.2 %) — banked, now the baseline | — (done) |
| §1 #3 megakernel (6.3 / 1.4) | 91 µs per launch serialized | realized ≤ 36 µs: pays iff c_sync ≤ 42 µs; net 3.1 ms MoE (2.6 %) / 10.2 ms dense (0.44 %) at 20 µs | ≈ 1.3 / 0.2; sign decided by E31 (C-6) |
| §1 #4 quantizing epilogue (7.9 / 1.7) | magic-bias quantizer; host-bounce fallback at λ = 91 | mechanism retired by the measured pass; at λ = 12.2 the bounce (100–107 µs/layer) is cheaper than the pass | — ; E33 = fuse the pass (3.5 % MoE / 0.9 % dense recoverable) |
| §1 #5 two-tier pages (12) | c_pg ∈ {0.5, 2, 6} µs | MEASURED 38 ns → +1.1 %; the kernel's own choreography is page-size-insensitive (138.0–138.7) → ≈ 0 | ≤ 1 (stale number) |
| §1 #6 KV-int8 both halves (5.2 / 45) | K-side premise | MEASURED 87.6 GB/s, 2.13×; P-i8 numerics U (E36) | unchanged; at 1M the top ALT family (attention 87 % of the step) |
| §1 #7 K-int8 / V-f16 (3.4 / 22) | — | measured exact ×20 | band 0.8 → 0.9 |
| §1 #9 lazy rescale | VOID (#19) | tuple-conditional: on the i8×i8→i32 PV of #6 same-dst accumulation across barriers is the pattern E21 measured exact to depth 8 192 — a merge-free resident-O variant is legal and uncosted | unpriced upside on the 1M lever |
| §1 #10 head-aligned QKV (+0.9 / +1.9 %) | 91 µs | +0.4 / +0.75 % at the realized bound | halves |
| §4 split-K / stream-K; producer–consumer; weight-stationary; L2 carving; GQA packing; hot/cold on 8 dies; token dropping; grouped-GEMM variants; zero-copy / NUMA; draft on host; rows-cliff | — | premises current; arithmetic re-derived | unchanged (the rows-cliff row gains C-20's diagnosis: the cliff is strips, E37's expected signature) |
| §4 **flash-decoding split-KV across dies** ("errata #11 fault; cannot run concurrently at Π = 1") | erratum 11 | the vendor split op faults; custom kernels on both dies of a card from one process stream at 1.000–1.001 (HW-MAP:334-345); the split-KV-token core map is the measured ~40 ms/step lever (:405-407) | **under-scored on a stale premise** → the fork's EP-B rung |
| §4 **expert-parallel across the card's two dies** ("no concurrency, +2 λ = −3.6 %") | erratum 11 | re-priced with the measured concurrency and λ = 12.2: 2-way MoE 32k 3.618 at ONE client (+94 %; 4.295 at the realized launch), dense 0.205 (R5); 8-way per §7 | **dismissed on a stale premise** → the fork's EP-A rung; `T_dominated_expert_parallel` formalizes the premise, not the family |
| §4 command-graph capture ("= H6") | — | the realized-launch row says launches already overlap in the serving loop — H6 partly answered | — |
| §4 Π = 8 ("not ours to build") | runtime feature | the custom serving loop's continuous batching is its measured substitute at ≤ 16 rows; branch 1 drafted a host relay | — |

## 6. HW-MAP items flagged (not edited — the steering owns the measured record)

1. :116 "break-even τ = 0.19 %; measured 42× / 29× over" → the banked-E29 break-even is 5.32 %; 1.50× / 1.03× (C-1).
2. :116 "trips −45 % … ~−50 µs/layer" vs the row's own 1 015 → 993 µs = −21.8 µs/layer; "−567.5 … −568.6 amortized" at the stale premise (C-19).
3. :359-360 "7–10 % / 5–8 %" vs :427 "10–15 %" vs the row's 6.9 % (C-19).
4. :116 "the 32k tie line is NOT reached … E29 WINS outright at both caps" → at cap 61440 inside measurement resolution (C-1).
5. M0 = 165.8 / 170.2: no row — harness, shapes, D, t, arena, reps owed (C-2).
6. :26 and ISA:60-61: the i4→f16 dequant instruction "gate passes; rate UNMEASURED" against erratum 12 (C-20).
7. :106 "DDR → L0 direct load instructions … UNMEASURED, may be a silent no-op" against :105 MEASURED 181.3 (C-20).
8. :108 "m ≥ 24 … multi-strip wedge unresolved" → the cells equal 174.6 ÷ strips (C-20).
9. :115 "the choreography model is VALIDATED" → a cell-level coincidence of three cancelling terms (C-25).
10. :152-156 erratum 11 should say which runtime it describes; :334-345 is the measured counter-fact for custom kernels (C-5).
11. :418-426: the session-5 cells (:116) were timed pre-fix; the "causal-exact" ledger rows need the erratum-32 mark (C-18).
12. :405-408: the 4-of-8-core map is the largest attention-side lever on the served model and is unranked in DESIGN-3 / 4 (C-23).

## 7. The fork — `DESIGN-FORK-EP8.md` in five lines

Expert placement over the 8 dies (32 experts per die, 45.1 GB) with per-die custom launches and a host all-reduce per layer
(EP-A), then one KV head per die (EP-B): MoE 32k t = 1 **2.932 / 4.667** tok/s/card against the chain's 1.956 and V3's 1.76 per
sequence; 1M **1.659** against 0.276; batched EP-A 3.99 / 4.94 / 5.67 at B = 2 / 4 / 8 against V3's 3.52 at two sequences; no int4
tier, no #19 merge, no E30, no H11; the worst routing costs −2.6 %. Gated on EP-1 / EP-2 (8-die concurrency and the host round —
measured at 2 dies / 2 cards, UNMEASURED at 8) with a 13.6× margin on the orchestration term; decided by three host-only steps
(S1 → S2 → S4) before any kernel work. `Chk.ForkEP.*` (10 theorems), `[FORK-EP-*]` (12 labels).

## 8. Checked and found CORRECT (so the next round does not redo it)

Every number below was re-derived from the printed inputs by at least one reviewer and the coordinator and matched to the digit:
the step's affine constants and the round-2 cells (§1 #2–#4); the round-7 slab / E29 / amortized / step cells / launch deltas (#5–#8);
the tie line and both margins (#9–#11); the trip break-even vs legacy (65 253 per 10⁵) and the premise band (#15–#16); T_min_dies in
both forms and the 5-die fits (#18–#20); the t = 4 steps from components (draft token 22 129 841) and all four spec thresholds
(#22–#25); the instance fits, margins, +23 ‰ per GB, the instance step and the break-even to the ns (#29–#34); the MoE-128k legs
lines 189.4 / 178.9 / 168.3 and the +12.8 % on the anchored layer (#35–#36); the drift chains and ppm (#38); E40's floors, prizes
and every φ gate (#40–#42); the megakernel lines (#45); the two-tier iff and +1.1 % (#46); U_max 32 / 31 / 18, the 968 ns dispatch
line, the 5.5× vendor floor (#47, #49); P1's 398 193 ns / 168.5 / the loader line (#51). By the reviewers beyond `Chk`: the ALT-1
chain and rates (167.1 / 172.8, G = 2 +1.6 %), the #19 merge cells, the Zipf shares, the K-split / M-split / G2 cells of P1, the
whole DESIGN-2 §8.1 table and generator means, the Z7 crossover set and Z10 bracket, the pack bijection, the budgets, E22-derived
chains, the per-block legacy−deferred deltas and the deferred chord (13 923 / 13 992 ns per block), the fold bound (e⁸ < 3 072), the
E21 percentages, the bounce shares and the 960 105 ns 10 % line, the Π = 8 decomposition identity, the K-int8 row's self-consistency,
`python3 -I proof/alt.py` byte-identical to alt.out, and the theorem counts (model 172, moe 191, attn 386, fleet 351, alt 114, cheat 21).

Inputs with two independent measurements agreeing (the clean class): the DDR roof family (173.8 stream, 173–177 DDR→US, 180 DDR→S1,
181.3 direct, 174.6 kernel, 174–176 attention stream phase, 169 E21 sequential, 151.3/die two-die serving — five harnesses within
~4 %); the concurrency rows (1.99×, 1.000–1.001, 2.0×, the batching curve with a 1.00× positive control); the derived-167.1 →
measured-165.8 forecast; the legacy scan's 0.1 % cross-session reproducibility; i32 saturation predicted then measured; the drain
thresholds (17–44×); the drift bound vs the measured 1.2 ppm; the same-dst chain rule from three probes; the np cells re-measured after
the page-table fix (1.39 → 1.40); the off-32k reading rule tested against the measured 128k / 1M cells (1.3 / 2.7 % optimistic).

## 9. Convergence with the three earlier challenge rounds (branches not read; commit messages only)

Branch 1 (`challenge-round`, 144 `Chk` theorems, the Π = 8 stage-ring fork): converges with this round on C-4 (dense V3 vs batching),
C-12 (E40's V vs the 565 µs phase) and on the retry-share premise being stale (since measured and absorbed by ROUND 7); its fork
(host-relay pipelining) is the throughput counterpart of this round's split family (latency). Branch 2 (`challenge-round-2`, 106
theorems, the card-pair TP2 fork, ladder rows E-RET / E-LAUNCH / E-BATCH / E-TP-1..4): converges on C-5 — the 2-way split is the
first rung of `DESIGN-FORK-EP8.md`, and its gate E-TP-1 (card-pair concurrency ≥ 1.9×) was MEASURED and met in the i4-class sync;
E-LAUNCH was adjudicated (the realized 36 µs row). Branch 3 (`challenge-round-3`, 30 theorems, the wide-cap / K-int8-V-f16 fork):
its wide-cap premise was MEASURED (licensed, unflipped) and its K-i8 premise measured (87.6 GB/s); converges on the static-span /
compact-arena harness taint (C-18) and on the E29 tie flipping at the retry share (C-1). Three rounds and this one now agree on two
things the main branch has not absorbed: the dense instance cell is the wrong comparison, and the cross-die split family is the
largest no-runtime lever the corpus has not priced on its measured premises.

## 10. Build status, files, and what this round did not do

- `lean proof/check.lean` standalone: clean, 3.2 s; `lake build` (`Model, Smoke, Moe, Fleet, Attn, Alt, Cheat, Check`): 17 jobs clean.
  `#print axioms` over every `Chk` theorem: `propext` / `Quot.sound` at most (omega), none for the `decide` theorems — no `sorryAx`,
  no `native_decide` axiom. `grep -c '^theorem' proof/check.lean` = 81.
- `python3 proof/fleet.py`: 717 lines; the first 692 byte-identical to the ROUND-7 output (`diff` verified); `[CHK-*]` 10, `[FORK-EP-*]` 12.
  model / moe / attn / alt untouched.
- Files added: `proof/check.lean`, `PROOF-COVERAGE-CHECK.md`, `DESIGN-FORK-EP8.md`. Files changed (append-only or marked in place):
  `proof/fleet.py` (appended `main_chk`), `proof/lakefile.toml` (the `Check` target + the native_decide note), `README.md` (the
  challenge-round row), and the eight design / cross-problem documents (a round-4 banner each; inline **challenge:** marks at
  DESIGN-4 ×4, DESIGN-3 ×1, DESIGN-2 ×1, ALTERNATIVES ×3, CHEATSHEET ×1, CHEAT-MATH ×1). HW-MAP.md, ISA.md, the PROBLEM files, the
  earlier PROOF-COVERAGE ledgers and every existing proof file are byte-identical.
- Not done, by the round's rules: no edit to `proof/cheat.lean` (the one-line `native_decide` → `decide +kernel` fix is the steering's);
  no HW-MAP edits (§6 lists the twelve flags); no absorption of the fork into DESIGN-4 (append-only); the three prior branches were not
  read. Nothing was committed.

## 11. Mission B — the corrected cell for every flip-list row (`Chk.MissionB.*`, `[CHK-B-*]`, `[FORK-EP-*]`)

"The document is wrong" was §2's checkpoint; this section is the corrected number per row of §4, with the ranked decisions that
move, or the arithmetic that shows the correction cannot exist. Tags: M measured, D derived here, U unmeasured, A assumption.

| flip row | corrected number (D unless noted) | ranked decisions that move |
|---|---|---|
| 1 — 8-die dispatch + host all-reduce (U) | **decided in arithmetic**: at the most conservative composition of MEASURED constants — every leg of both per-layer host rounds serialized (16 × 12.2 µs) and both launches at the 91 µs floor = 377.2 µs/layer — EP-A is **2.704** tok/s/card at MoE 32k against the chain's 1.956 (+38 %); the kill line (1 640 µs/layer) is 4.3× above it (`Chk.MissionB.gate_decided`). S1 is the measured intra-card row's own class (one process, two dies, weight-streaming kernels); S2 at 8 participants fully serialized is 195 µs per round (`s2_bound`); the gate can fail only on a host-stack serialization that would also contradict the card-scale 2.0× row — i.e. on a NEW measurement, not on any standing one | the build order: V3 (int4 tier + #19 merge + E30 + H11) → EP-A; the no-runtime table's MoE row 3.72 (2 sequences) → EP-A 2.93 (1 sequence) / 3.99 (2) / EP-B 4.67 (1) |
| 2 — erratum 12, W4 dead (M once, pre-#18/#25) | the counterfactual if it fell (W4 streaming at the W8 kernel's per-byte rate): MoE 32k **1.956 → 2.715**, dense 32k **0.104 → 0.192**, minimum dies **5 → 3** (`w4_alive`); the int4 tier is then dominated by plain W4 and the fit hostage H8/H11 disappears | T_min_dies, the V3 tier, PROBLEM-4's 320–400 GB band, dense-1M feasibility; the re-probe (§3 item 2) is the highest-value silicon half-day in the corpus |
| 3 — H4 Π > 1 (EMPIRICAL) | the corpus's own 7.7× / 7.1×; this round adds the bound that supersedes it: pipelined EP (one sequence's attention overlapping another's expert phase on the other dies) is bounded by the per-die DDR time per token: **≤ 20.4 (EP-A) / 19.8 (EP-B) tok/s per card** (`epp_bound`), above the Π = 8 stage ring's 13.41 at a fraction of its latency — a bound, not a cell | the throughput plan: the stage ring (branch 1) is dominated by pipelined EP if EP-1/EP-2 hold |
| 4 — client count (frame) | dense: chain B = 2 **0.199** vs V3 0.150 (every B < 16.5); MoE: EP-A B = 2 **3.988**, EP-B B = 2 **7.091** (exact: E[max of 16] = 4.2014 by the 186 partitions, `emax_16_8`, `b2_cells`) vs V3 3.878 / chain 2.249 | dense V3 struck; MoE V3 ties EP-A at exactly two clients (3.88 vs 3.99) and loses at one (1.76 vs 2.93) and at ≥ 4 (3.94 vs 4.94) and at every L to EP-B |
| 5 / 6 — τ at the wide cap; M0 (M) | corrected statement: fusion ≥ E29 at cap 61440 iff τ ≤ 5.32 % (measured 5.5 %) or M0 ≤ 165.7 (measured 165.8) — a tie within resolution; **with K-int8 on the K half the tie disappears**: the K-i8 deferred cell ≈ 741 µs, fusion + K-i8 = 19.7 ms per token > E29's 14.64 on both caps (`ki8_tie`) | the #1 lever at MoE 32k: fusion + K-i8 (if E36's K-only numerics hold — the K side is measured exact ×20) |
| 7 — c, the two-card inheritance (U at that topology) | MoE V3 at round-7 anchors needs **c ≥ 1.095** (3.52 at c = 2.0); EP-A needs no c at all (its gain is from the dies' own DDR) | V3's robustness, now moot for the build order |
| 8 — c_sync (E31, U) | V2 pays iff **c_sync ≤ 42.4 µs (MoE) / 41.2 µs (dense)** at the realized launch; net prize 3.1 ms MoE (2.4 %) / 10.2 ms dense (0.4 %) at 20 µs | V2 falls from 3rd to E40's size class; under EP the launch term is per-die-concurrent and V2's prize shrinks further |
| 9 — launch reading | the MoE primary at the realized launch is **2.103** (chain) / **3.38** (EP-A, R4's figure; this round's model at sync 120.8 µs already prices launches at 36 µs) | nothing ranked beyond rows 8 / 14 |
| 10 — E30 cold-tier regime (U) | moot: EP needs no cold tier; if V3 is kept for MoE, the serial reading gives 3.13 (holds) | — |
| 11 — H9 routing skew (U) | **placement policy** (Monte Carlo, seed 0, 20 000 tokens, `[FORK-EP-zipf-*]`): rank round-robin placement holds E[max] at 2.27–2.57 under Zipf 1.5 / 1.0 / uniform; contiguous placement 6.6 / 4.9 / 2.6; random 2.5 — the H9 census is the fork's placement input, not a risk to its cells; MoE spec under EP-A: gain iff α ≥ 0.610 (t = 1 attention reading) / 0.762 (legacy t = 4 reading) | the placement table of EP; the spec verdict (row 14) |
| 12 — H8 overhead (A) | EP's per-die total is 63.6 GB at 1M (`ep_memory`): 22 GB of headroom — H8 stops being a hostage under EP; the chain's dense-1M KV-int8 fit (1.66 GB margin) stands as before | the dense-1M fit hostage moves from H8 to the TP-8 gate |
| 13 — c_pg at production scatter (M lower bound) | moot at the M0 anchor (MoE-128k attention-bound by 34.7 % at every G ≤ 226.5); the two-tier page row is +1.1 % at 38 ns and ≤ 5 % below 160 ns | nothing |
| 14 — E41, the deferred t = 4 cell (U) | **EP-S: MoE spec decode (k = 3) flips** — chain: loss iff α ≤ 0.823; EP-A: **gain iff α ≥ 0.610** with the verify attention at the t = 1 cell, **α ≥ 0.762** at the legacy t = 4 cell (`eps_flip`); at α = 0.7: 3.368 vs 2.932 (+14.8 %, `eps_cell`). E41 is now the decisive experiment for a ranked decision (spec on MoE), not a hygiene item | DESIGN-4 §6's "spec decode is a loss on MoE" becomes conditional on EP + E41 |
| 15 — φ (E40a) and V (E41) (U) | **K-int8-only outranks E40 at every L** with a MEASURED premise (2.13× on the K half, exact ×20): 5.72 / 22.9 / 183 ms per MoE token at 32k / 128k / 1M vs E40's bounds 3.46 / 9.28 / 67.1 (`ki8_lever`); it composes with E40 and needs no φ | DESIGN-4 §10‴ "E40 is the attention-side #1 on every cell" → K-i8 first, E40 second; at 128k K-i8 (22.9) also passes E29 (14.64) |
| 16 — P-i8 numerics (E36, U) | unchanged for the KV-int8-both-halves row; K-only needs only the measured K side + per-row q scales (+1 Mul per score ≈ 17 µs at 32k) | — |
| 17 — T_red at 8 participants (U) | bounded above by the serialized reading 195 µs per round (`s2_bound`); the 2-way rung's line (306 µs) and the 8-way's (1 556 µs) both clear it | — |

## 12. The doors tried — the chain-cost bound, the int4 tier, the packing identity, and what was invented

**The chain-cost bound (P3).** The deferred kernel sits 123.7 µs above its stream-plus-bounce floor at 32k (13.1 %); E40's whole
prize is that gap and needs φ ≤ 0.6–1.7 µs against a measured 10–20 µs crossing. No exact-class mechanism beats the floor; only bytes
do. The byte lever that is MEASURED is K-int8 (the K half at 2.13×): floor 821.8 → 617 µs, cell ≈ 741 µs — larger than E40 at every
L and composable with it (§11 row 15). Beyond it, KV-int8 both halves (ALT rank 6, gated on E36's P-i8 numerics) and EP-B's head split
(the fork). The vector chain itself (softmax, fold, merge ≈ 1.4–2.1 µs per block against 12 µs of stream) is not the binding engine on
the deferred kernel; a cheaper chain buys nothing. Door closed for new mechanisms; the ranking corrected.

**The int4 tier (P4 / P5).** Under erratum 12 the tier's only route is the vector unpack (5.3 GB/s/core); the tier exists only to fit two
4-die instances. Three ways out, all priced: (a) EP needs no tier (63.6 GB per die at 1M); (b) if erratum 12 falls, plain W4 at the MMA
(MoE 32k 2.715, dense 0.192, three dies); (c) a cheaper unpack cannot be derived without silicon (erratum 4's silent-no-op shifts, no u8
And) and even a FREE unpack lifts V3 only to 4.74 for two sequences — below EP-B's 7.09 at B = 2. Door closed: the tier is dominated on
every branch.

**The packing identity (CHEAT-MATH §C / CHEATSHEET #1).** Two int4 weights per byte through the i8 MMA return 16·S_hi + S_lo with |S_lo| up
to 127 · 15 · 128 = 243 840 ≫ 16: (S_hi, S_lo) = (0, 16) and (1, 0) collide, so no second call on the same B separates the two dot
products (`nibble_not_separable`); the f16 tuple mixes the same way. The vector route keeps pace with the 4-bit stream only at one
lane-op per element (345.6 vs 347.6 G/s) and the MEASURED 5-pass unpack is 24 % (`unpack_cap`); a 1-op unpack does not exist on this
part (no u8 And, shifts silently no-op, the i8→f16 cast yields one element per byte). The exact-class byte cut on the weight stream is
therefore capped at ~1/5 of the wall. Door closed with arithmetic; CHEATSHEET #1 cannot be rescued by a kernel.

**Invented under the license (every number D, every gate U and named):**
- **EP-S — speculative decoding on EP-A.** The verify batch's 32 experts spread over 8 dies (E[max] 7.05 vs the chain's 32 serial):
  the MoE spec verdict flips from "loss unless α ≥ 0.823" to "gain iff α ≥ 0.610 / 0.762" — and the UNMEASURED cell that decides it is
  E41's deferred t = 4 attention, which the corpus already lists as a follow-up. `eps_flip`, `eps_cell`, `[FORK-EP-S]`.
- **EP-P — pipelined EP.** Interleaved sequences hide one sequence's attention under another's expert phase; the fleet bound is
  1 / max-die DDR time per token = 20.4 / 19.8 tok/s per card (EP-A / EP-B), above the stage ring at lower latency. `epp_bound`, `[FORK-EP-P]`.
- **Rank round-robin placement.** With the H9 popularity census, placing experts round-robin by rank keeps E[max] at the uniform value
  under Zipf 1.0 / 1.5 (2.45 / 2.27) where contiguous placement gives 4.9 / 6.6 — the H9 experiment becomes the fork's placement input.
- **TP-8 dense on the measured primitive.** Column-split every GEMM 8-way with attention die-local: dense 32k **0.588** (realized launch) /
  0.570 (91 µs) against 0.104 — the corpus's own §5 what-if, now with its gate named (the 1 024-column / 256 KiB-per-core slab regime, U)
  instead of "the runtime faults". `tp8_dense`, `[FORK-TP8-dense-*]`.

**What this round did not find.** No exact-class mechanism below the stream floor for attention; no MMA route for packed int4; no
scheme that beats pipelined EP's per-die DDR bound (it is the fleet's weight-bandwidth roof minus imbalance). Those three doors are
closed by arithmetic above, not by belief.

## 13. Build status after Mission B

`proof/check.lean`: **95 theorems** (81 + 14 in `Chk.MissionB`), `lean` standalone 5.4 s, `lake build` 17 jobs clean, `#print axioms`
over all 95: at most `propext` / `Quot.sound`. `proof/fleet.py`: 738 lines — the first 717 (ROUND 7 + round-4 part 1) byte-identical;
`[CHK-B-*]` 6, `[FORK-EP-gate/S/B1..B16/P/zipf-*]` 11, `[FORK-TP8-dense-*]` 2. Documents: `DESIGN-FORK-EP8.md` §9–§13 appended;
Mission-B **challenge:** marks at DESIGN-4 §10‴ (K-i8 first; spec on EP), DESIGN-3 §5.1 round-6 note (K-i8 first), ALTERNATIVES §1
row 7 (K-int8 / V-f16 under-ranked). Nothing committed.
