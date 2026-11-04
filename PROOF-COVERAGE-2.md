# PROOF-COVERAGE-2 — ledger of every quantitative claim in DESIGN-2.md

How to read a row: **Claim** quotes or paraphrases the DESIGN-2.md statement (section numbers refer to the
corrected document); **Proof** names the theorem(s) in `proof/moe.lean` that fix the number; **moe.py** names
the label in `proof/moe.py` that prints it; **Status** is one of PROVED (follows arithmetically from the
constants table; "∀ x" marks a universally quantified result over the unmeasured quantity x), INPUT (a HW-MAP
measurement, PRIOR, ISA fact or erratum used as given), DEFINITION (true by construction of the cost model or
a structural choice with no number in it), EMPIRICAL — Ex (settled only by the named experiment of DESIGN-2.md
§9, or by the §9.3 generator `[Z]`; no theorem claims it), or ASSUMPTION (explicitly labelled A in the design,
measured by the named experiment; theorems that use it are "PROVED given the assumption").

Units in the proof files: rates in tenths of GB/s (1353 = 135.3), time in ns (floored), µs quoted
round-half-up (`usR`) or in tenths (`usT`), percentages in tenths of a percent (`pct`, 158 = 15.8 %) or
hundredths (`pctH`), the per-call residual c_res in tenths of ns (254 = 25.4 ns), the loader rate L in tenths
of GB/s/core. `rateT` rounds half-up at the 0.1 step, so thresholds over unmeasured rates are exact at 0.1.

## Build status

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (`leanprover/lean4:v4.35.0` in `proof/lean-toolchain`, elan), Lake 5.0.0 |
| `lean proof/moe.lean` standalone | **succeeds**, 0 errors, 0 warnings (no imports beyond Init; Mathlib/Batteries not used) |
| `cd proof && lake build` | **succeeds** (targets `Model` = model.lean, `Smoke` = smoke.lean, `Moe` = moe.lean) |
| Theorems in moe.lean | **189** (`grep -c '^theorem'`) |
| `axiom` / `sorry` / `native_decide` in moe.lean | 0 / 0 / 0 |
| `decide +kernel` | 1 (T_Z7_crossover_model: the 128-case exact-model crossover check evaluated by the kernel instead of the elaborator, whose recursion limit the 128 nested `max` terms exceed) |
| Leaf closers used | `decide`, `omega`, `rfl`, `simp only` with core lemmas (`Nat.mul_add`, `Nat.add_mul`, `Nat.mul_assoc`, `Nat.mul_comm`, `Nat.mul_left_comm`, `Nat.succ_mul`, `Nat.reduceMul/Div/Add` simprocs), `exact` of core lemmas (`Nat.le_div_iff_mul_le`, `Nat.div_lt_iff_lt_mul`, `Nat.lt_add_one_iff`, `Nat.mul_le_mul`, `Nat.le_of_mul_le_mul_right`, `Nat.add_le_add`, `Int.natAbs_mul`); structure: `unfold`, `rw`, `intro`, `constructor`, `refine`, `induction`, `rcases`, `subst`, `split`, `generalize` |
| `python3 -I proof/moe.py` | runs on Python ≥ 3.8, no dependencies; `--zipf` (2000 seeds × 9 configurations, 7 s) reproduces every §7.1 and §7.3 generator statistic quoted in the text |
| Measured namespace | 21 plain definitions, each with the HW-MAP row it comes from; none states a DESIGN-2.md conclusion |

## Corrections forced by formalization (round 1 → round 2)

| # | Where | Round 1 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §8.4, §10.2 | W4 on the i4×i4 route gives "the same tokens/s as W8" in the serial regime; "2× tokens/s" in ping-pong; "2× calls (31.6 % MMA)" | 96.7 % of W8's tokens/s (1 026 µs vs 992 µs per step: W4 is 3.4 % slower; 130.8 vs 135.3 W8-equivalent); parity would need c_res ≤ 21.2 ns, proved for every c_res; ping-pong 159.3 W4-GB/s = **1.86×** W8's 171.2; the doubled calls are 59.5 % of the W4 DDR time (31.7 % was the share of the W8 DDR time) | T_w4_ratio, T_w4_parity, T_w4_pp |
| 2 | §3.3 regression | +17.8 µs = 14.8 µs of A lifts + 3 µs of dispatch/tail; dispatch share 0.3 %; A fraction "3.1 % vs 1.5 %" | 14.8 + 3 = 17.8 only numerically: the extra A bytes are 256 KiB (8 × 64 KiB vs 2 × 128 KiB) = 9.9 µs, plus the full 8 µs of F, minus 0.05 µs of anchor rounding; dispatch share 0.2 %; dense A fraction 1.6 % | T_epilogue_regression |
| 3 | §3.2, Appendix row 20 | per-step vector epilogue 31.9 µs at t = 16, D = 128; Sub 190 ns | 30.3 µs — moe.py's `[M19]` charged 5 ops per routed pair while the text (correctly) lists 4; Sub = 8 192 lane-ops / 43.2 = 189 ns under the floor convention | T_epilogue_vector |
| 4 | §1.2, §7.3 Z7 | W-dyn "loses by 10–50 % everywhere else"; S wins "100 % at D = 4" | S wins elsewhere by 0.03 % (D = 55, just under the r = 7 crossover) up to 95 % (D = 4); 74 % at D = 9, 57 % at D = 10 | T_Z7_losses |
| 5 | §8.2 c_res row | "0: 171.2, 50: 162.7, 100: 155.0, 150: 148.0, 200: 141.6, 25.4 ns: 135.3, 30 ns: 130.4" | the first five labels were moe.py's tenths of ns (50 ns would give 112.5): 0 / 5 / 10 / 15 / 20 ns; row extended with the gate's edge (target met iff c_res ≤ 40.9 ns, ∀ c_res) | T_cres_rows, T_cres_target |
| 6 | §8.3 last row | (2048, 512, 4) with A resident in L0A: "25 % → 0", 97.4 → 110.0 | the one 32 KiB A lift per step remains (1.2 µs of a 43 µs step): A fraction 0.8 %, 97.4 → **106.6**; 110.0 was the zero-lift number | T8s_2048_512_4 |
| 7 | §3.2 P3 | U_max = ⌊(2³¹−1)/(127²·K)⌋ with |a|, |b| ≤ 127 taken for granted | the bound is a requirement on the quantizers: with −128 allowed, 128²·4096·32 = 2³¹ exactly and U_max(4096) drops to 31 (6 regions still cover D ≤ 186 ≥ 128; K = 7168 unchanged at 18). Stated in the text as an explicit premise | T_overflow_m128, T_overflow_tight |
| 8 | §7.3 Z3, §8.1 derivation, Z7 | "stepS(D) = F + D·T_S" and "stepW(D) = F + ⌈D/8⌉·T_W" as exact identities | exact only up to the floor rounding of the summed loader and residual terms: D·T_S ≤ chain(D) < D·T_S + 2D (991 842 vs 991 832 at D = 8) and ⌈D/8⌉·T_W ≤ chainW < ⌈D/8⌉·T_W + 2⌈D/8⌉; every µs-precision cell is unaffected; the crossover set is proved both in the affine form (∀ D) and under the exact model (D ≤ 128) | T_Z3_affine, T_Z3_rounding_8, T_Z7_W_affine, T_Z7_crossover_model |
| 9 | §7.3 Z8, Summary row 3 | partialBytes = 2·8·k·t·N_e·4 "written once, read once" | moe.py (and every quoted margin) always used 8·k·t·N_e·4: the read-back of the reduce launch. The write of the same bytes rides under the serial regime's DDR slack (6 µs of 208 µs at the headline, 97 µs of 3.4 ms at D = 128), now stated and proved; the margin identity holds up to the < 2D ns rounding of #8 | T_Z8_write_hidden, T_Z8_identity |
| 10 | §7.2 Z4 | "max/mean = … (2 at D = 9, 64/63 at D = 63)" | 8⌈D/8⌉/D = 16/9 at D = 9 (2 is max/min, not max/mean) | T_Z4_values |
| 11 | §6 | six shadows resident in US "≈ 317 KiB" | 162.5 − 32 (no staging buffer) + 192 = **322.5 KiB** (> 208 either way) | T_budget_us |
| 12 | §1.2 W-static | static-map hottest core "1.3–1.7× the mean at t = 16" | generator (2000 seeds): 16.73/12.75, 12.21/8.54, 8.90/5.68 = 1.3 / 1.4 / **1.6**× | `[Z]` (EMPIRICAL, reproduced) |
| 13 | §7.4 table | W-static floor 17.4 for Z(1.0) | the floor (min over t and D) is 17.3 for every family; 17.4 only at t ≥ 4 | T_floors_static, T_Z9_static |
| 14 | §9 E13 | accumulating-oracle total "≤ 9.6·10⁶ exact" | that was DESIGN.md's k = 64 shape; at (16,16,128) with 10 000 loads × 8 calls × 128 × 15 the bound is 1.5·10⁸ < 2³¹ — exact in i32 but above 2²⁴, so the region must be read as i32, never through f32 | T_overflow_e13 |
| 15 | §1.4 | "t·k ≤ 128 scalar iterations … ≤ 12.8 µs at σ_d = 100 ns, t = 16" | k ≤ 10 ⇒ t·k ≤ 160, ≤ 16 µs (12.8 µs is the k = 8 figure) | T_dispatch_iterations, T_dispatch_cells |
| 16 | §10.1 loader row | loader-bound rate "8·L·(16 MiB/16.5 MiB) → L = 20: 153.7" | that formula gives 155.2; 153.7 is the model's 128 MiB / (16.5 MiB/L + 8 µs); target met iff L ≥ 15.6 (∀ L) | T_risk_loader, T_pp_target |
| 17 | Appendix row 11 | D-independent DDR part "3 100 ns" | 3 110 ns; minimum slack 22 536 ns at D = 1, t = 16 | T_piece_slope, T_Z3_slack_tight |
| 18 | moe.py (no text change) | `[M5]` printed K-split 114.1 at D = 4 (k = 8 partials) while the text's 114.7 (k = 4) is right; `[M9]` printed a stale 66 KiB US budget; `[M11]` printed "17 842 = 14 838 + 8 000" | labels fixed; `[M21]`–`[M30]` and `[Z2]` added so that every number in the text has a label | moe.py |

Not a correction but a tightening found while proving: the general subtraction identity behind c_res reproduces
any per-core time T to within **≤ 410 ns** (two floors), not "< 410"; at T = 487 000 the residue is 25 ns
(T_anchor_identity, T_anchor_model).

## Ledger

### Constants table (DESIGN-2.md header)
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| R_ddr = 173.8 GB/s/die → 21.725 GB/s/core (21.7 remainder 2 tenths) | Measured.rDdr, T0_per_core_rates | R_DDR | PROVED from INPUT (HW-MAP card table) |
| R_stage = 180 GB/s/die = 22.5 GB/s/core | Measured.rStage, T0_per_core_rates | R_STAGE | PROVED from INPUT |
| L = 26.5 GB/s/core strict-serial (M); its overlap/ping-pong behaviour and granule dependence U | Measured.lSer; L universally quantified in T_pp_thresh, T_pp_rate_ddr_bound, T_pp_rate_loader_bound, T_pp_target | L_SER | INPUT; regime EMPIRICAL — E13 |
| c_mma = 15 ns per (16,16,128) call | Measured.cMma | C_MMA | INPUT |
| T_dense = 487 µs per core = the 137.8 GB/s dense kernel; HW-MAP's "12.5 % occupancy" is 12.6 % exact | Measured.tDense, Measured.rDense, T0_dense_row | T_DENSE | INPUT (HW-MAP@3eaf322) + PROVED self-consistency |
| c_res = (487 000 − 321 497 − 61 440) × 10 / 4096 = 25.4 ns, one consistent decomposition | T_anchor_loader, T_anchor_cres | [M0] | PROVED (E13 splits it) |
| R_vec = 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core | T0_rvec | R_VEC | PROVED from INPUT |
| T_launch ≈ 91 µs | Measured.tLaunch | T_LAUNCH | INPUT |
| L0A/L0B 64 KB, L0C 256 KB (full 256 KB hangs, errata 14) | Measured.l0a, Measured.l0b, Measured.l0c | L0A, L0B, L0C | INPUT |
| S1 ~1 MB = 976 KiB (P); US 256 KB, ≥ 208 KiB evidenced | T0_s1_us | — | INPUT (P) + PROVED unit conversion; sizes EMPIRICAL — E7-style |
| R_vendor = 24.6; gate 120 | T0_floor_gate | R_VENDOR | INPUT |
| MMA shapes (n ≤ 16; k ∈ {32, 128}; k = 64 wrong; init/align flags ignored); dtypes (i8×i8 verified, f16×i8 absent, no i4→f16, i4×i4 unverified) | — | — | INPUT (HW-MAP); i4×i4 EMPIRICAL — E19 |
| R_drain (L0C→US) U; σ_d U (budget 100 ns); ρ₁ U; i32 Sub U | rate kept as a parameter in T_epilogue_drain; σ_d universally quantified in T_dispatch_hidden; ρ₁ never enters (T_bytes_eighth) | — | EMPIRICAL — E12, E14, E18, E12 |
| F = 8 µs = 5 (fill) + 2 (exposed dispatch) + 1 (tail) | Design.fixed; sensitivity T_cres_F_rows | FIXED | ASSUMPTION — E14/E15 |
| headline shape: N_c = 512; 8 × 16 MiB = 128 MiB = 134.22 MB per step | T0_headline | [M1] | PROVED |
| the MMA consumes 2 KiB per 15 ns call = 136.5 GB/s/core if fed | T0_mma_feed | — | PROVED |

### Round-2 status banner (silicon note)
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| re-anchored to the current HW-MAP serial-fallback row 138.9: T_dense = 483 145 ns, c_res = 24.4 ns, headline 136.4 | T_sync_reanchor | [M29] | PROVED (sensitivity; the anchor choice itself is INPUT) |
| DDR-bound ceiling at the ~181 pure-read roof: 178.2 (171.2 at the 173.8 read+write roof); 174.6 ≤ 181.3 ≤ ~181 | T_sync_roof | [M29] | PROVED |
| a direct-path (DDR→L0B) MoE kernel is not modelled | — | — | DEFINITION (scope) |

### Summary and ranking
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| DDR bytes per die 134 889 472 = 128 MiB (W) + 512 KiB (8 A) + 128 KiB (scales) + 8 KiB (desc) + 8 KiB (y) = 8 × the 16 861 184 B each core streams | T1_ddr_bytes, T_bytes_headline | [M1] | PROVED |
| serial regime: loader 652.9 + MMA 122.9 + residual 208.1 = 983.8 µs, DDR 776.1 underneath, step 991.8 µs → 135.3 | T1_times, T1_serial, T1_us_cells | [M1] | PROVED |
| ping-pong: max(776.1, 652.9, 122.9) + 8 = 784.1 µs → 171.2 | T1_pp | [M1] | PROVED (regime EMPIRICAL — E13) |
| wall clock +91 µs: 1082.8 / 875.1 µs → 123.9 / 153.4 | T1_wall | [M1] | PROVED (launch pipelining EMPIRICAL — E17) |
| target 120 met at 113 % (112.8); vendor floor beaten 5.5× | T1_ratios | [M1] | PROVED |
| honest ceiling 173.8 × 128 MiB / (128 MiB + 0.64 MiB) = 172.9, minus F → 171.2 | T1_overhead, T1_pp | [M1] | PROVED |
| ranking row 1 (S): 135.3 / 171.2; k = 4: 134.2; D = 9 (t = 4): 135.4 | T1_serial, T1_pp, T8_ranking | [M5] | PROVED |
| row 1b (S, G = 2): 136.7 / 171.2 | T8_gknob | [M14] | PROVED |
| row 2 (W-dyn): 137.7 / 171.2 only when 8 \| D; k = 4: 68.9; D = 9: 77.8; its 256 KiB C slab = L0C → two slabs → 137.4 | T_Z4_rows, T_Z4_wdyn_slab, T1_pp_wdyn_same, T8_ranking | [M5][M18][M21] | PROVED |
| row 3 (K-split): 125.3; k = 4: 114.7; D = 9: 124.7; +T_launch and the partial read-back; below S on every §8 cell except (t = 16, D = 128) where S-G2 still wins | T_Z8_rates, T_Z8_margins, T8_ranking | [M5][M20][M22] | PROVED |
| rows 4–5: vector-only 70–78 (∝ 1/t), vendor 24.6 | — | — | INPUT (HW-MAP measured) |
| the one ranking-changing measurement is E11: without an exact reset, S needs ⌈D/6⌉ launches (2 at D = 8 → 124) and W-dyn (one region per core at D ≤ 8, 137.7) is #1 at t = 1 | T1_fallback_two_launches | [M21] | PROVED (which branch holds: EMPIRICAL — E11) |
| E13 moves S 135.3 → 171.2 (up to 36 GB/s) and W-dyn identically (same DDR bound) | T1_pp_wdyn_same, T_risk_slack | [M1] | PROVED |

### §1 Work decomposition and the three-axis design
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §1.1 unit = K·N_c = 2 MiB = 32 k-chunks of 128·N_c = 64 KiB (one errata-2-maximal COPY) | T_piece_sizes | [M10] | PROVED |
| §1.1 MMA 136.5 GB/s/core if fed; loader 26.5; DDR 21.7–22.5 per core → serial-loader-bound vs DDR-bound regimes | T0_mma_feed, T0_per_core_rates, T_pp_margins | [M1] | PROVED |
| §1.2 per-core bytes = D·K·N_c + A + scales/8 + desc + y/8, identical on all cores for every outcome; no ρ₁ | T_bytes_eighth_full, T_bytes_balanced, T_bytes_headline | [M1] | PROVED (∀ outcome, ∀ core) |
| §1.2 the scatter-add is local to the core; only a K-split needs a reduction; the 10.7 GB/s host bounce is cross-die | model structure; Measured.rHostBounce | — | DEFINITION / INPUT |
| §1.2 A-lift fraction 3.1 / 6.3 / 12.5 / 25 % at N_c = 512 / 256 / 128 / 64; 0 in the DDR-bound regime, 1.8 % serial vs a whole-expert scheme | T_epilogue_alift | [M6][M14] | PROVED |
| §1.2 W-dyn: 137.7 (A 0.4 %), 68.9 (D = 4), 86.4 (D = 10), 77.8 (D = 9); C slab 16 × 4096 × 4 = 256 KiB = L0C; two slabs → 137.4 | T_Z4_rows, T_Z4_wdyn_slab, T_Z4_bytes | [M5][M18][M21] | PROVED |
| §1.2 W-dyn beats S iff ⌈D/8⌉·T_W < D·T_S, i.e. on {8\|D} ∪ {63, 71, …, 127} ∪ {118, 126} by ≤ 1.8 %, and loses elsewhere by 0.03 % (D = 55) … 95 % (D = 4) | T_Z7_crossover_affine, T_Z7_crossover_model, T_Z7_margin_affine, T_Z7_margin_model, T_Z7_losses | [M27] | PROVED |
| §1.2 W-static: single-hot puts all D experts on one core → 17.3 GB/s | T_Z9_static, T_Z9_bytes | [M5] | PROVED |
| §1.2 W-static under the generator: hottest core 2.6× the mean at t = 1, 1.3–1.6× at t = 16 | — | [Z] | EMPIRICAL (generator, 2000 seeds; reproduced) |
| §1.2 K-split: partials 8·D·t·N_e·4 B = 1 MiB at the headline, +91 µs; 125.3 at D = 8, 114.7 at k = 4; below S except (t = 16, D = 128) by 0.6 %, which G = 2 returns to S | T_Z8_constants, T_Z8_rates, T_Z8_margins | [M20][M22] | PROVED |
| §1.3 one shared 16-row A serves every expert for t ≤ 16 (mFrag = 1); batching streams D slabs vs Σ m_e = k·t; the ratio is ≥ 1 | T_Z5_one_fragment, T_Z6_batching_never_worse, T_Z6_equality_iff | — | PROVED (∀ outcome) |
| §1.4 dispatch: t·k ≤ 160 iterations; ≤ 16 µs at σ_d = 100 ns, t = 16, k = 10 (12.8 at k = 8); host pre-pass 91 µs = 9.2 % of the headline step, 211 % of a (2048, 512, 4) step | T_dispatch_iterations, T_dispatch_cells, T_dispatch_host | [M16][M17][M30] | PROVED (σ_d EMPIRICAL — E14) |
| §1.5 the five MoE deltas | — | — | DEFINITION |

### §2 Weight slab packing
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §2.1 addr(e, k, n) and P1: (k, n') ↦ offset is a bijection of [0, K) × [0, N_c) onto [0, K·N_c) with the stated inverse, for N_c ∈ {64, 128, 256, 512} and 128 \| K (range, left inverse, right inverse, injectivity) | T_pack_range, T_pack_left_inverse, T_pack_right_inverse, T_pack_injective, T_pack_off_digits, T_pack_digit_chunk, T_pack_digit_inchunk, T_pack_digit_instrip, T_pack_digit_kl, T_pack_digit_infrag, T_pack_digit_f, T_pack_digit_g, T_pack_digit_n | — | PROVED (∀ K, k, n', o) |
| §2.1 every tile boundary is a multiple of the next smaller one (2 MiB / 64 KiB / 16 KiB / 2 KiB / 512 B / 32 B) | T_pack_boundaries | — | PROVED |
| §2.1 generic N_c: chunk 64 / 32 / 16 / 8 KiB; a 64 KiB COPY covers 1 / 2 / 4 / 8 chunks; a 16 KiB piece = 8 strips of one chunk or 2 chunks × 4 strips at N_c = 64 | T_pack_chunks | — | PROVED |
| §2.2 H-op (fragment order) and H-A (A operand geometry) | — | — | EMPIRICAL — E11(v)(vi) |
| §2.3 operands: x_q 64 KiB (K = 4096) / 112 KiB = 2 × 56 KiB (K = 7168) + 64 B; s_e 4·N_c = 2 KiB per core, 16 KiB per expert per die; descriptor ≤ 16 × 10 × 6 = 960 B; y f16 t × 8 KiB in 1 KiB runs | T_budget_operands, T_piece_sizes | [M10] | PROVED |
| §2.4 pack order = visit order: 32 sequential 64 KiB COPYs per 2 MiB region | T_piece_sizes | [M10] | PROVED (that the region-switch pattern reaches the per-core-slab rate: EMPIRICAL — E15, A-reg) |

### §3 Token gather / result scatter-add
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §3.1 x_q copy 64 KiB = 2.9 µs at 22.5 GB/s/core; A = 0.4 % of the DDR bytes; per-token quantization 3 lane-ops/element = 4.6 µs at t = 16, K = 4096 | T_epilogue_budget, T_piece_sizes | [M16] | PROVED (op count ASSUMPTION; row-max reduce EMPIRICAL) |
| §3.2 six 32 KiB regions (16 × N_c × 4 B); drain = 16 rows × 32 runs of 64 B at stride 1 024; diff = 16 × 512 lanes = 8 calls of 1 024 | T_budget_drain, T_overflow_umax | [M9] | PROVED |
| §3.2 P2: the i32 after−before difference equals the true sum S whatever the region held, iff −2³¹ ≤ S < 2³¹ | T_overflow_modular_diff | — | PROVED (Int, ∀ before, ∀ S) |
| §3.2 \|S_e\| ≤ 127²·K = 66 064 384 (K = 4096) under \|a\|, \|b\| ≤ 127; attained by all-127 operands | T_overflow_sum_bound, T_overflow_sum_tight | [M12] | PROVED (the operand bound is a quantizer requirement — correction 7) |
| §3.2 P3: U_max = 32 (K = 4096) → 6 regions cover D ≤ 192; 18 (K = 7168) → 7 regions, 224 KiB, cover D ≤ 126; regions total 192 / 224 KiB, never 256; every U ≤ U_max keeps the running sum inside i32; U_max + 1 can overflow | T_overflow_umax, T_overflow_sufficient, T_overflow_sufficient_7168, T_overflow_tight, T_overflow_running, T_overflow_region_exact | [M12][M25] | PROVED (∀ U, ∀ history) |
| §3.2 −128 caveat: 128²·4096·32 = 2³¹ → U_max = 31, 6 regions cover 186 ≥ 128; K = 7168 unchanged | T_overflow_m128 | [M25] | PROVED |
| §3.2 shadow swap: 2 × 32 KiB at 250 GB/s/core = 0.26 µs | T_epilogue_budget | — | PROVED (S1→US path EMPIRICAL — E12) |
| §3.2 costs: drain D × 32 KiB = 256 KiB (D = 8) / 4 MiB (D = 128); 3.3 µs per expert at 10 GB/s/core = 2.7 % if exposed; Sub 189 ns + 47 ns per routed pair → 30.3 µs per step at t = 16, D = 128 = 0.2 % | T_epilogue_drain, T_epilogue_vector | [M8][M15][M19] | PROVED (R_drain and overlap EMPIRICAL — E12/E16) |
| §3.2 branch (ii): f32 difference exact iff < 2²⁴ = 16 777 216, which 22 × 66 064 384 exceeds → A-mag | T_overflow_D128 | [M13] | PROVED (A-mag ASSUMPTION — E15) |
| §3.2 branch (iii): ⌈D/6⌉ launches, +91 µs each → 124 at D = 8 | T1_fallback_two_launches | [M21] | PROVED |
| §3.3 step budget: dispatch ≤ 0.8 µs at σ_d = 100 ns, exposed ≤ 2 µs; gather 2.9 µs; grouped GEMM 983.8 µs (DDR 776.1); scatter-add 8 × (3.3 + 0.24) = 28 µs; fill + tail 6 µs; step 991.8 µs → 135.3; +91 µs → 123.9 | T_dispatch_cells, T_epilogue_budget, T1_serial, T1_wall | [M1][M8][M16] | PROVED (exposed dispatch ASSUMPTION — E14; drain overlap EMPIRICAL — E16) |
| §3.3 regression vs two 8 MiB dense passes (974 µs): +17.8 µs = 9.9 (256 KiB of A lifts) + 8.0 (F) − 0.05 (anchor rounding); 1.8 %; dispatch share 0.2 %; A fraction 3.1 % vs 1.6 % | T_epilogue_regression | [M11] | PROVED |

### §4 Dispatch design
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §4.1 host pre-pass ≥ 91 µs = 9.2 % / 211.3 % | T_dispatch_host, T_Z8_launch_pct | [M16][M17] | PROVED |
| §4.1 dedicated tiny kernel: +91 µs if launches serialize | — | — | EMPIRICAL — E17 |
| §4.1 no cross-core sync or mailbox for hand-rolled kernels | ISA.md | — | INPUT |
| §4.1/§4.3 scan t·k·σ_d: σ_d = 10 / 50 / 100 / 250 ns → 0.08 / 0.4 / 0.8 / 2 µs at t = 1, 1.3 / 6.4 / 12.8 / 32 µs at t = 16 | T_dispatch_cells | [M16] | PROVED (σ_d EMPIRICAL — E14) |
| §4.2 CSR memory 512 + 512 + 128 × 16 × 5 = 11 KiB; descriptor ≤ 960 B | T_budget_operands | [M30] | PROVED |
| §4.3 the A copy (2.9 µs) is issued first; expert 0's 123 µs chain hides the ≤ 127 remaining iterations iff σ_d ≤ 968 ns | T_dispatch_hidden, T_piece_expert | [M30] | PROVED (∀ σ_d) |
| §4.3 exposed ≤ 2 µs inside F | — | — | ASSUMPTION — E14 |
| §4.3 at t = 1 the whole scan is smaller than one 64 KiB chunk time (3.0 µs at 21.725) | T_dispatch_small | [M16] | PROVED |

### §5 Loop nest, tiling, m_e-batching rule
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §5.1 shapes M-legal; calls per expert per core = 32 × 32 = 1 024, 8 192 per step → 122.9 µs = 15.8 % of 776.1 µs | T1_times, T1_ratios | [M1] | PROVED (shape legality INPUT) |
| §5.1 piece 16 KiB = 8 operands; L0B 3 × 16 = 48 of 64 KiB; L0A 2 × 2 KiB, or the whole A iff 16·K ≤ 48 KiB ⟺ K ≤ 3072; C region 32 KiB | T_budget_l0, T8s_resident_rule, T_overflow_umax | [M9] | PROVED |
| §5.2 loop nest | — | — | DEFINITION |
| §5.3 per 16 KiB piece: DDR share 754, loader 618, MMA 120, residual 203 → serial 941 ns = 17.4 GB/s/core of B; ping-pong hides the loader iff barriers ≤ 136 ns per piece | T_piece | [M4] | PROVED (barrier cost EMPIRICAL — E13) |
| §5.3 per expert: 81.6 + 41.4 = 123.0 µs vs 96.5 µs of DDR share; per step × 8 + F = 991.8 µs | T_piece_expert, T1_serial | [M15] | PROVED |
| §5.3 ping-pong: loader must sustain ≥ 17 MiB / 776.1 µs = 22.3 GB/s/core (16 % under 26.5); the MMA (122.9 µs; MMA + residual 331 µs) is off the critical path in both regimes; 22.3 vs the dense kernel's 21.8 | T_pp_thresh, T_pp_thresh_value, T_pp_margins | [M3] | PROVED (∀ L) |
| §5.4 batching rule: Z5 (one fragment for every m_e ≤ 16); Z6 (separate passes stream k·t slabs ≥ D, equality iff all pairs distinct, = t under H); idle experts add nothing; 47 ns per routed pair | T_Z5_one_fragment, T_Z6_separate, T_Z6_batching_never_worse, T_Z6_equality_iff, T_Z6_single_hot_D, T_Z6_single_hot_pairs, T_Z6_D_append, T_Z6_pairs_append, T_Z6_idle_D, T_Z6_idle_pairs, T_Z6_idle_experts, T_epilogue_vector | [M8] | PROVED (∀ outcome) |
| §5.4 tokens/s scale with t/D(t): 1.01 tokens/ms at every t under idealized uniform; 2.89 at Z(1.5), t = 16 | T8_single_hot, T8_row_t16_Z15 | [T8] | PROVED (Zipf D EMPIRICAL — [Z]) |
| §5.4 t > 16 out of scope | — | — | DEFINITION |
| §5.5 barriers B10–B13, queue depths 4/4, 2/2, 3/3, 2/2, 6/6; no queue-based L1 staging | — | — | DEFINITION / INPUT (errata 8, 9, 14) |
| §5.6 deltas versus DESIGN.md | — | — | DEFINITION / INPUT |
| §5.6 G knob: A fraction 3.1 % / G; 135.3 / 136.7 / 137.4 / 137.7 at G = 1 / 2 / 4 / 8; G = 2 is +1.0 %; G = 8 needs 8 × 32 KiB = 256 KiB = L0C | T8_gknob | [M14] | PROVED (A-reg2 DDR pattern EMPIRICAL — E15) |

### §6 Buffer budget (worst activated set)
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| B ring 4 × 64 KiB = 256 KiB; 2 chunks of lookahead = 5.8–6.0 µs | T_budget_s1, T_piece_sizes | [M9] | PROVED |
| x_q 64–112 KiB; S1 total 512–592 KiB incl. shadows ≤ 976 KiB; G = 2 adds 256 KiB → 768–848 | T_budget_s1 | [M9] | PROVED (S1 size P: EMPIRICAL — E7-style) |
| L0A 2 × 2 KiB (or 32 KiB resident at K = 2048); L0B 48 of 64; C regions 192 / 224 of 256 KiB | T_budget_l0 | [M9] | PROVED |
| US: desc ≤ 960 + 64 B, slot/act/cnt 3 × 512 B, tok/sc 10 KiB, y_acc 32 KiB, shadow staging 32 KiB, new/diff 64 KiB, s_e 4 KiB, row 2 KiB, y_out 16 KiB → 162.5 KiB ≤ 208 KiB | T_budget_us, T_budget_operands | [M9] | PROVED (US size EMPIRICAL — E7-style) |
| six shadows resident in US instead → 322 KiB > 208 | T_budget_us | [M9] | PROVED |
| shadows 6 × 32 KiB = 192 KiB in S1 | T_budget_drain | [M9] | PROVED |
| alternative (b): 4 regions cover D ≤ 128 at K ≤ 4096, D ≤ 72 at K = 7168 | T_overflow_four_regions | — | PROVED |
| W4 branch adds one 32 KiB group-drain buffer; (c) shadow routed rows only | — | — | DEFINITION |

### §7 Skew model
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §7.1 family definitions; D = k at t = 1 for every family (skew invisible at t = 1 for a per-step scheme) | T_Z6_single_hot_D, T_Z6_idle_experts (H); U by definition | — | DEFINITION / PROVED |
| §7.1 generator table: D means 8 / 30.5 [25, 32] / 102.0 [89, 115]; 25.0 [18, 31] / 68.3 [54, 84]; 19.6 [13, 26] / 45.4 [34, 58]; max m_e 1 / 1.8 / 3.3, 3.4 / 12.7, 4.0 / 15.9 | — | [Z] | EMPIRICAL (generator, 2000 seeds; reproduced) |
| §7.2 Z1: k ≤ D ≤ min(k·t, E) for every outcome with Σ m_e = k·t and m_e ≤ t | T_Z1_bounds, T_Z1_D_le_E, T_Z1_D_le_pairs, T_Z1_pairs_le | — | PROVED (∀ outcome) |
| §7.2 Z2: coreBytes_S has no c and no m_e; 8 × core bytes = the die's ddrBytes; column-slice bijection and Σ_c N_c = N_e | T_bytes_eighth, T_bytes_eighth_full, T_bytes_core, T_bytes_step, T_bytes_balanced, T_slice_bijection, T_slice_cols_closed, T_slice_cols_per_core, T_bytes_headline | [M1] | PROVED (∀ outcome, ∀ core; N_c ∈ {64, 128, 256, 512}) |
| §7.2 Z4: round-robin gives core c ⌈(D − c)/8⌉ experts: max ⌈D/8⌉, min ⌊D/8⌋; balanced iff 8 \| D; 16/9 at D = 9, 64/63 at D = 63, 1 unit for D < 8; max bytes ⌈D/8⌉·K·N_e + 16·K | T_Z4_countRR, T_Z4_max_min, T_Z4_balanced_iff, T_Z4_values, T_Z4_bytes | — | PROVED (∀ D) |
| §7.2 Z9: W-static hot core carries D·K·N_e + 16·K = 8 × the S per-core weight bytes | T_Z9_bytes, T_Z9_static | [M5] | PROVED |
| §7.2 Z5, Z6 | (as §5.4) | — | PROVED |
| §7.3 Z3: chain ≥ DDR for every D ≥ 1, t ≤ 16 with ≥ 22 536 ns slack (min at D = 1, t = 16); stepS affine up to < 2D ns rounding; rateS(4 / 8 / 128) = 134.2 / 135.3 / 136.4; limit B_x/T_S = 136.4; strictly increasing (unrounded) | T_Z3_chain_form, T_Z3_ddr_form, T_Z3_chain_dominates, T_Z3_slack_tight, T_Z3_affine, T_Z3_rounding_8, T_Z3_values, T_Z10_increasing, T_piece_slope | [M5][M15][M28] | PROVED (∀ D, ∀ t ≤ 16) |
| §7.3 Z10: rateS ∈ [135.3, 136.4] for every D ≥ 8 (hence every family, s, seed); 1.1 GB/s = 0.8 %; 15.7 ms (U) vs 5.5 ms (Z(1.5)) at t = 16, 2.8× fewer bytes | T_Z10_bracket, T_Z10_width, T_Z10_steps | [M5][T8] | PROVED (∀ D ≥ 8) |
| §7.3 Z7: T_W = 966 531, T_S = 122 979, ratio 0.9824; winning set {8\|D} ∪ {63, …, 127 ≡ 7} ∪ {118, 126} within 1..128 (affine ∀ D, and under the exact floor-rounded model); W-dyn's edge ≤ 1.8 % (1.8 at D = 8 and 128, 0.2 at 63); S wins elsewhere by 74 % (D = 9: 1.115 vs 1.941 ms), 95 % (D = 4), 57 % (D = 10), 0.03 % (D = 55); no threshold in s; G = 2: T_S' = 121 743, set = 8 \| D, edge ≤ 0.8 % | T_Z7_constants, T_Z7_W_form, T_Z7_W_affine, T_Z7_crossover_affine, T_Z7_crossover_model, T_Z7_margin_affine, T_Z7_margin_model, T_Z7_losses, T_Z7_no_s_threshold, T_Z7_G2_constant, T_Z7_G2_crossover, T_Z7_G2_margin | [M27] | PROVED |
| §7.3 Z7 generator statistics: winning set hit by 20 / 19 / 4 % (t = 4) and 25 / 26 / 12 % (t = 16); generator-mean W-dyn 132 / 121 / 115 and 134 / 132 / 129 vs 136 for S | — | [Z2] | EMPIRICAL (generator; reproduced) |
| §7.3 Z8: chainK 120 815, ΔA = 2 164 ns, partials 8·k·t·N_e·4 = 1 MiB → 6 033 ns; margins +79.7 / +45.8 / +71.8 / +40.3 / +90.1 / −89.6 µs; identity stepK − stepS = T_launch + partials − D·ΔA up to < 2D ns; 137.1 vs 136.4 at (16, 128) (0.6 %); S-G2 137.7 ≥ 137.1; K-split's C slab is the errata-14 size; the partial write rides under the DDR slack (6 033 ≤ 207 724; 96 531 ≤ slack at D = 128) | T_Z8_constants, T_Z8_margins, T_Z8_identity, T_Z8_rates, T_Z8_write_hidden | [M20][M22][M28] | PROVED |
| §7.3 Z9': static map under H_c → 17.3 at D = 8 | T_Z9_static | [M5] | PROVED |
| §7.4 floor table: S 135.3 / 136.1 / 136.4 (U), 135.3 / 136.1 / 136.3 (U_s), 135.3 / 135.9 / 136.3 (Z(1.0)), 135.3 / 135.7 / 136.2 (Z(1.5)), 135.3 (H); W-dyn 137.7 / 138.6 / 138.8, 108.3 (25) / 128.7 (89), 103.9 (18) / 123.5 (57), 98.1 (17) / 117.8 (34), 137.7; W-static 17.3 (17.3–17.4 on every cell); K-split 125.3 / 134.6 / 137.1, 133.4 / 136.4, 131.4 / 134.8, 128.8 / 132.6, 123.2 / 115.5 | T_floors_U, T_floors_Us, T_floors_Z10, T_floors_Z15, T_floors_H, T_floors_static | [M26] | PROVED (min and argmin over each range; the D ranges themselves EMPIRICAL — [Z]) |

### §8 Predicted step-time table
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| §8.1 nine rows: bytes, serial step µs, GB/s, tokens/ms, ping-pong step and GB/s, W4 bytes / step / W4-GB/s | T8_row_t1, T8_row_t4_U, T8_row_t4_Z10, T8_row_t4_Z15, T8_row_t16_U, T8_row_t16_Z10, T8_row_t16_Z15, T_w4_table | [T8] | PROVED (Zipf D values EMPIRICAL — [Z]) |
| §8.1 single-hot: 0.992 ms, 135.3, 16.13 tokens/ms at t = 16; the step formula F + D·T_S (up to < 2D ns); the ping-pong cell formula | T8_single_hot, T_Z3_affine, T_Z3_rounding_8, T8_pp_formula | [T8b] | PROVED |
| §8.2 c_res row (ns): 0 → 171.2, 5 → 162.7, 10 → 155.0, 15 → 148.0, 20 → 141.6, 25.4 → 135.3, 30 → 130.4, 40.9 → 120.0, 50 → 112.5; DDR-bound only at c = 0 (352 ns of slack), chain-bound for every c ≥ 0.1 ns; ≤ 171.2 for every c; target met iff c_res ≤ 40.9 ns | T_cres_rows, T_cres_regimes, T_cres_chain, T_cres_upper, T_cres_target | [M2][M24] | PROVED (∀ c_res) |
| §8.2 loader row: 15.0 → 115.6, 20.0 → 153.7, 22.0 → 168.9, ≥ 22.3 → 171.2; loader-bound form 17 MiB/L + 8 µs below 22.3; target iff L ≥ 15.6 | T_pp_rows, T_pp_rate_ddr_bound, T_pp_rate_loader_bound, T_pp_target_core, T_pp_target | [M3][M24] | PROVED (∀ L) |
| §8.2 G row: 135.3 / 136.7 / 137.4 / 137.7 | T8_gknob | [M14] | PROVED |
| §8.2 wall row: 123.9; 133.1 / 131.1 (t = 4); 135.6 / 134.0 (t = 16) | T8_wall_rows | [M1] | PROVED (pipelining EMPIRICAL — E17) |
| §8.2 F row: 0 → 136.4, 8 → 135.3, 20 → 133.7 | T_cres_F_rows | — | PROVED (F ASSUMPTION) |
| §8.3 seven shapes: N_c, calls, A/B fraction, serial, ping-pong, wall, W-dyn; step µs 992 / 2160 / 254 / 886 / 269 / 148 / 43; G = 4 variants 132.1 and 125.7; A-resident 106.6 (one 32 KiB lift = 1.2 µs); residency rule K ≤ 3072 | T8s_4096_4096_8, T8s_7168_4096_10, T8s_2048_4096_4, T8s_7168_2048_8, T8s_4096_1024_8, T8s_4096_512_8, T8s_2048_512_4, T8s_resident_rule, T8s_steps | [M6][M22] | PROVED |
| §8.3 small total bytes are launch-floor-bound: 31.3 on the wall clock at 4 MiB per step | T8s_2048_512_4, T_risk_small | [M17] | PROVED |
| §8.4 W4: DDR bytes 68.5 MiB; loader 9 MiB = 356 µs; 16 384 calls × 40.4 = 662 µs; chain 1 018 µs, step 1 026 µs → 65.4 W4-GB/s = 130.8 W8-equivalent = 96.7 % of W8 (3.4 % slower); parity iff c_res ≤ 21.2 ns; i4 operand 1 KiB per call; group scales K·N_e/32 | T_w4_cells, T_w4_ratio, T_w4_chain, T_w4_parity | [M7][M23] | PROVED (∀ c_res; the route itself EMPIRICAL — E19) |
| §8.4 ping-pong W4: DDR-bound 159.3 W4-GB/s = 1.86× W8's ping-pong tokens/s; the 2× calls are 59.5 % of the W4 DDR time; drain need 8.2 GB/s/core; c_res = 0 → 110.0 | T_w4_pp | [M7][M23] | PROVED (drain rate EMPIRICAL — E19) |
| §8.4 vector unpack route dead: 42 GB/s int4-effective = 84 W8-equivalent < 120 | T_w4_vector_dead | — | PROVED from INPUT |
| §8.4 decision rule (E19 passes all three, else requantize to i8) | — | — | EMPIRICAL — E19 |

### §9 Experiment ladder
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| harness: integer inputs with \|a\|, \|b\| ≤ 15 over 2 × 128 k-rows give sums ≤ 57 600 ≪ 2²⁴ | T_overflow_harness | [M19] | PROVED |
| E11(iv): a 127-valued oracle adds 127²·128 = 2 064 512 per call; the i32 range is exceeded at call 1 041, so 1 100 calls make wrap-vs-saturate observable | T_overflow_e11 | [M25] | PROVED |
| E12: a magnitude of 2²⁵ + 1 exposes a missing i32 Sub (> 2²⁴) | T_overflow_D128 | — | PROVED |
| E13(a): oracle total ≤ 1.5·10⁸ < 2³¹, exact in i32, above 2²⁴ | T_overflow_e13 | [M25] | PROVED |
| E13: the per-piece barrier budget 136 ns | T_piece | [M4] | PROVED |
| E15: every core's chunk count must equal D × 32 | T_piece_sizes | [M10] | PROVED (count; the check itself EMPIRICAL) |
| E17: 100 queued launches ≈ 100 × 91 µs if serialized | — | — | EMPIRICAL — E17 |
| E19: drain rate ≥ 8.2 GB/s/core | T_w4_pp | [M7] | PROVED (threshold) / EMPIRICAL — E19 |
| E11–E20 outcomes (reset mechanism, geometry, choreography, numerics, drain rate, pipelining, ρ₁, i4×i4) | — | — | EMPIRICAL — the ladder itself |
| §9.3 generator Z(E, k, t, s, seed) | — | [Z] | DEFINITION (specification) / EMPIRICAL (its statistics) |

### §10 Risk register and unlocks
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| no exact reset → ⌈D/6⌉ launches: 124 GB/s at D = 8; W-dyn #1 at t = 1 (137.7) | T1_fallback_two_launches | [M21] | PROVED (branch EMPIRICAL — E11) |
| K = 7168, D > 126 → cap D per launch at 7 × 18 = 126 | T_risk_7168, T_overflow_umax | [M12] | PROVED |
| c_res granule-bound: 16 KiB pieces could give up to 162.7 at 5 ns | T_cres_rows | [M2] | PROVED (which: EMPIRICAL — E13(a)) |
| loader < 22.3 at 16 KiB granules: 128 MiB/(16.5 MiB/L + 8 µs) → L = 20: 153.7; still > 120 for L ≥ 15.6 | T_risk_loader, T_pp_target, T_pp_rows | [M3][M24] | PROVED (∀ L) |
| dispatch latency > 2 µs or σ_d > 250 ns: +30 µs at t = 16 worst case = 0.2 % | T_dispatch_small | [M16] | PROVED |
| US cannot hold 162 KiB → shadows in S1 (already), shrink to 4 regions | T_budget_us, T_overflow_four_regions | [M9] | PROVED (US size EMPIRICAL) |
| S1 < 592 KiB → routed-row shadows, ring 3 × 64 KiB | T_budget_s1 | [M9] | PROVED (S1 size EMPIRICAL) |
| region-switch DDR pattern slower: invisible in the serial regime until it exceeds 983.8 µs (27 % slack) | T_risk_slack | [M1] | PROVED (pattern rate EMPIRICAL — E15) |
| drain not overlapped: +2.7 % serial (3.3 µs per expert at 10 GB/s/core); routed-row drains 4 KiB per pair | T_epilogue_drain | [M15] | PROVED (R_drain EMPIRICAL — E12/E16) |
| N_e ≤ 1024: A fraction 12.5–25 % → G = 4 knob (132.1 / 125.7) or A resident for K ≤ 3072 | T8s_4096_1024_8, T8s_4096_512_8, T8s_2048_512_4, T8s_resident_rule | [M22] | PROVED |
| small total bytes: 31 GB/s on the wall clock, 97 in-kernel → fuse launches | T_risk_small | [M17] | PROVED (pipelining EMPIRICAL — E17) |
| t > 16, f16 score precision, missing barriers, i4×i4 absent → fallbacks | — | — | DEFINITION / EMPIRICAL |
| §10.2: E11 reorders the ranking; E13 moves the number by up to 36 GB/s; R_drain 0 % vs 2.7 % and the 8.2 GB/s/core W4 need; i32 Sub; E17 31 → 97; σ_d ≤ 0.3 % either way; W4 1.86× (ping-pong) / 0.97× (serial); ρ₁ never enters | T_risk_slack, T_epilogue_drain, T_w4_pp, T_w4_ratio, T_risk_small, T_dispatch_small, T_bytes_eighth | [M23] | PROVED (numbers) / EMPIRICAL (which outcome) |
| the one measurement that changes the ranking: E11 | — | — | EMPIRICAL — E11 (the ranking consequence is the §3.2(iii) row above) |

### Appendix A (the round-1 claim ledger) and the anchor
| Claim | Proof | moe.py | Status |
|---|---|---|---|
| rows 1–2: c_res = 25.4 ns; the decomposition re-predicts 486 975 ns (25 ns under 487 000) and 137.8 exactly; the identity holds for every T to within 410 ns; the headline 135.3 follows; ± 0.1 ns of c_res moves it by 0.1 | T_anchor_loader, T_anchor_cres, T_anchor_model, T_anchor_dense, T_anchor_identity, T_anchor_headline, T_anchor_sensitivity | [M0] | PROVED (∀ T) |
| rows 3–8 (headline cells), 9 (22.3 ∀ L), 10 (piece), 11 (slope 96 626 + 3 110), 12 (bracket), 13 (crossover), 14 (W-dyn/W-static rows), 15–16 (K-split, S-G2), 17–18 (overflow, modular difference), 19 (pack bijection), 20–22 (epilogue, drain, regression), 23 (dispatch), 24–25 (A-lift, G knob), 26–27 (tables), 28 (W4), 29 (buffers), 31 (margins), 32 (sensitivity rows) | the theorems named in the section rows above | as above | PROVED |
| row 30: generator means and ranges | — | [Z] | EMPIRICAL |

## Coverage summary
| Metric | Value |
|---|---|
| Ledger rows (quantitative claims in DESIGN-2.md) | 145 |
| PROVED (theorem in moe.lean, incl. "PROVED from INPUT" and proofs with explicit premises / universally quantified unknowns) | 111 (77 %) |
| INPUT (HW-MAP / ISA measurement, PRIOR, or errata used as given) | 10 |
| DEFINITION (true by construction of the cost model, or a structural choice) | 11 |
| EMPIRICAL (only an experiment or the generator settles it) | 11 |
| ASSUMPTION (explicitly labelled, measured by the named experiment) | 2 |
| Theorems in moe.lean | 189 |
| Theorems cited by the ledger | 189 of 189 |
| Ledger theorem names not found in moe.lean | 0 |
| moe.lean theorems not cited in the ledger | 0 |
| moe.py labels cited that do not exist | 0 |

Every row's status is machine-checkable: PROVED rows name theorems that `lean proof/moe.lean` checks; moe.py
labels are grep-able in `proof/moe.py`'s output; EMPIRICAL rows name the experiment whose observable failure
mode is specified in DESIGN-2.md §9 (or the generator of §9.3, whose statistics `python3 -I proof/moe.py
--zipf` reproduces). Universally quantified results (over c_res, the loader rate L, σ_d, D, t ≤ 16, routing
outcomes, region histories, pack offsets) are stated as such; nothing about silicon behaviour is claimed by a
theorem. Claims that DESIGN-2.md does not make are not in this ledger.
