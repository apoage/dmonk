# PROOF-COVERAGE — ledger of every quantitative claim in DESIGN.md

How to read a row: **Claim** quotes or paraphrases the DESIGN.md statement; **Proof** names the
theorem(s) in `proof/model.lean` that fix the number (all close by `decide`/`omega`/`simp`, no
axioms); **model.py** names the label (and line) in `proof/model.py` that prints it; **Status** is
one of PROVED (follows arithmetically from the constants table), INPUT (a HW-MAP measurement,
PRIOR or ISA fact used as given), DEFINITION (true by construction of the cost model), or
EMPIRICAL — Ex (settled only by the named experiment in DESIGN.md §8; no theorem claims it).

Units in the proof files: rates in tenths of GB/s (1685 = 168.5), time in ns, τ in hundredths of
ns, percentages in tenths of a percent (304 = 30.4 %). `rateT` rounds half-up at the 0.1 step;
`timeNs` floors; thresholds on unmeasured rates are therefore stated at 0.1 granularity.

## Build status

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (elan, `leanprover/lean4:v4.35.0` in `proof/lean-toolchain`), Lake 5.0.0 |
| `cd proof && lake build` | **succeeds** (targets `Model` = model.lean, `Smoke` = smoke.lean) |
| `lean proof/model.lean` standalone | **succeeds** (no imports beyond Init; Mathlib/Batteries not used) |
| Theorems in model.lean | 172 (`grep -c '^theorem'`) |
| `axiom` / `sorry` / `native_decide` in model.lean | 0 / 0 / 0 |
| `python3 -I proof/model.py` | runs on Python ≥ 3.8, no dependencies; its 28 table rows appear verbatim in DESIGN.md §7.1–§7.4 (checked by string match) |
| Pre-existing `proof/smoke.lean` | did **not** compile on this toolchain as committed (its `omega` never unfolded `pack`); fixed with one line, `unfold pack at he`, nothing else touched |

## Corrections forced by formalization (round 1 → round 2)

| # | Where | Round 1 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §3.1 tile geometry | address formula with 16-column groups and bytes 0–15 of each 32 B block | not a bijection: byte 16 never written, last element at byte 32751 of a "16 KiB" tile. Replaced by the dense literal HW-MAP reading **G1c** (8 groups of 32) with G1a/G1b/G2 carried as hypotheses for E1; under G2 Route 1 falls to 85.6 and Route 1b becomes #1 | T7_old_misses_byte_16, T7_old_exceeds_tile, T7_g1c_*, T9_g2_rate |
| 2 | §6 K-split | 136 GB/s at m=64 (18 MiB extra traffic) | 112.4 (97.5 with the second launch): the 16 MiB reduction read-back was omitted; K-split is worse than N-split's 115.9 | T9_ksplit, T9_ksplit_worse_than_nsplit |
| 3 | §1.4 scheme P costs | 1 Mi f32 adds = 24 µs; 3 MiB US↔S1 = 12 µs | 196 608 adds = 4.6 µs; 2 MiB copies = 8.4 µs (the 1 MiB drain is a separate, unmeasured path) | T5_P_adds, T5_P_copies, T5_P_geometry |
| 4 | §9 L0C = 32 KiB row | m=16 → 164 (A re-streamed); m=64 → 8 slabs → 87 | m=16 stays 168.5 because A (256 KiB) is S1-resident under the design's own policy (163.6 only if S1 cannot hold it); m=64 needs n=128 tiles for 8 slabs → 86.9 | T5_l0c32_m16, T5_l0c32_m16_if_restreamed, T5_l0c32_m64 |
| 5 | §5 W4 ceiling | "~170 W4-GB/s" at D = 43.2 | dequant-bound 172.8, but DDR including the 2 MiB A stream caps at 163.6 (32/34 × 173.8) | T6_dequant_432, T6_w4_ddr_incl_A |
| 6 | all tables | mixed truncation (168.5 → "168") and rounding (163.6 → "164") | one decimal everywhere, round-half-up at 0.1 | T1_m1_ddr_bound_rate, T5_m32 |
| 7 | §0, §5, §7.3 thresholds | L ≥ 21.7, L ≥ 43.4, D ≥ 21.7; break-even 388 µs / 86 | exact crossover 173.8/8 = 21.725 lies between tenths: first DDR-bound tenth is 21.8; W4 break-even D ≥ 21.8 (385 µs → 87.2), L ≥ 43.5 | T2_crossover, T2_loader_threshold_roof, T6_w4_beats_w8, T6_dequant_218, T6_dequant_217 |
| 8 | §4.1 | chunk 2.9–3.1 µs; slab-end vector 0.4 µs; fill 1.3 % / 15 % | 3.0–3.1 µs (2.9 was B-only); Mul **and** Cast = 0.76 µs; fill budget labelled ASSUMED, 1.2 % / 15.6 % | T9_chunk, T1_epilogue_ns, T1_fill_pct, T9_chunk2 |
| 9 | §3.3 COPY_FRAC | 1.3 % of 373 µs; 5 % of a 24 µs 2048² | 1.2 % of 398 µs; at 2048², m=16 the slab is 8 KiB → 4.3 % of 27 µs | T7_frac_cost, T7_frac_cost_2048 |
| 10 | §6, §7.5, §0 | M-split 42; f16 round trip 43; vector arrange 69 W8-eq; route 4 115; R1b 52 % of 373 | 43.1; 43.5; 69.2; 115.2; 48.8 % of 398 | T9_msplit, T6_f16_roundtrip, T6_vector_arrange, T9_route4, T1_cast_pct |
| 11 | constants table | τ ≤ 3.46 derivation written as "4096 B / 18.5 = 221 ns / 8"; S1 "~1 MiB" | 512 B / 18.5 GB/s = 27.7 ns per 8 fragments = 3.46 ns; S1 "~1 MB" = 976 KiB, which is what makes the m=48 A block (768 + 256 KiB = 1 MiB) *not* fit | T3_tau_from_148, T0_units, T5_m48_not_resident |
| 12 | §7.4 | 4096² row 160 → 164 (round-1 self-fix) | 163.6 exact; 2048² "131–154" → 130.5–154.5 with the fill column marked ASSUMED | T9_4096, T9_2048 |

## Ledger

### Constants table (DESIGN.md header)
| Claim | Proof | model.py | Status |
|---|---|---|---|
| R_ddr = 173.8 GB/s/die | Measured.rDdr | R_DDR | INPUT (HW-MAP card table) |
| R_stage = 180 GB/s/die = 22.5 GB/s/core; 173.8/8 = 21.725/core | T0_per_core_rates, T2_crossover | R_STAGE, model.py L204 [D-const] | PROVED from INPUT |
| R_us→s1 = 250 GB/s/core | Measured.rUsS1 | R_US_S1 | INPUT |
| L (S1→L0 loader rate) unknown | universally quantified in T2_* | — | EMPIRICAL — E2 |
| τ_mma = 3.7 ns from 17.8 TFLOPS/8 cores; 2.46 ns from 26.6 | T0_tau_from_17_8, T0_tau_from_26_6 | TAU | PROVED from INPUT |
| τ ≤ 3.46 ns implied by the f16 library matmul flat at 148 GB/s to M=128 | T3_tau_from_148 | model.py L203 [D0-tau] | PROVED from INPUT (148 flat is HW-MAP) |
| c_mma (MMA issue cost) unknown | universally quantified in T3_* | — | EMPIRICAL — E1-sweep |
| R_vec = 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core | T0_rvec | R_VEC | PROVED from INPUT |
| D (dequant rate) unknown | universally quantified in T6_* | — | EMPIRICAL — E8 |
| T_launch ≈ 91 µs | Measured.tLaunch | T_LAUNCH | INPUT |
| COPY_FRAC = 7 GB/s/core | Measured.rFrac | R_FRAC | INPUT |
| S1 ~1 MB (P) modeled as 1 000 000 B = 976 KiB | T0_units | S1_P | INPUT (P) + modeling choice |
| US 256 KiB (≥ 208 evidenced) | — | — | INPUT (P/M); size itself EMPIRICAL — E4/E7 |
| L0A, L0B ≥ 32–64 KiB; L0C ≥ 64 KiB (P) | Measured.l0cP | L0C_P | INPUT (P); EMPIRICAL — E4 |
| 64 MiB = 67.11 MB | T0_units | — | PROVED |

### §0 Summary and ranking
| Claim | Proof | model.py | Status |
|---|---|---|---|
| m=1 (= m=16) DDR-bound rate 168.5 | T1_m1_ddr_bound_rate, T1_m16_same_as_m1, T1_m1_rate_is_64_66 | model.py L113 [D7.1-rate] | PROVED |
| m=32: 163.6 (A resident) / 154.5 (re-streamed) | T5_m32, T5_m32_restream | model.py L118 [D7.2] | PROVED |
| m=64: 115.9 at L0C = 64 KiB; 138.4–154.5 with scheme P | T5_m64, T5_m64_P_370, T5_m64_P_246 | model.py L118 [D7.2] | PROVED |
| loader-bound row: 8·L·64/66; L=18.5 → 143.5; L=15.5 → 120.2 | T2_at_185, T2_at_155, T2_table_w8 | model.py L147 [D7.3] | PROVED |
| DDR-bound iff L ≥ 21.8 (first 0.1 above 21.725) | T2_loader_threshold_roof, T2_crossover, T9_crossover_between | model.py L204 [D-const] | PROVED |
| wall-clock with unpipelined 91 µs floor: 137.2 | T1_wall_with_launch | model.py L155 [D7.4] | PROVED (floor itself INPUT; pipelining EMPIRICAL — E0) |
| honest ceiling 168.5 = 173.8 × 64/66; 174.5 at 180 | T1_m1_rate_is_64_66, T1_m1_rate_at_180 | model.py L113 [D7.1-rate] | PROVED |
| R1 168.5 needs L ≥ 21.8, f16×i8 oracle, geometry G1, L0B ≥ 32 KiB, L0C ≥ 64 KiB | T1_*, T2_loader_threshold_roof | — | PROVED (rate) / EMPIRICAL — E1, E2, E4 (premises) |
| R3 168.5: identical byte stream and fragment count | `ddrBytesDie`, `calls` carry no dtype parameter; T4_calls_8192 | — | DEFINITION |
| R3 integration gap: no f16→i8 vector cast | ISA.md cast list | — | INPUT (ISA) |
| R1b 168.5 iff L ≥ 43.5; target iff L ≥ 31.0; cast 194 µs = 48.8 % of 398 µs | T2_1b_threshold_roof, T2_1b_threshold_target, T1_cast_time, T1_cast_pct | model.py L114 [D7.1-rate-1b], model.py L200 [D9-g2] | PROVED (cast rate = 40 lanes/cycle is INPUT; cast op existence EMPIRICAL — E9) |
| R2 163.6 W4-GB/s iff D ≥ 43.5 ∧ L ≥ 86.9; target iff D ≥ 30 ∧ L ≥ 60 | T6_w4_ddr_incl_A, T6_w4_roof, T6_w4_target | model.py L164 [D5] | PROVED |
| R4 70–78 GB/s, ∝ 1/m; R5 4.2 GB/s | — | — | INPUT (HW-MAP measured) |
| ranking flips: L ≥ 86.9 ∧ D ≥ 43.5 → R2 #1; L < 15.5 → nothing MMA-based meets target | T6_w4_roof, T2_loader_threshold_target | — | PROVED |
| geometry G2 → R1 at 85.6, R1b #1 | T9_g2_rate, T2_1b_threshold_roof | model.py L200 [D9-g2] | PROVED (which geometry holds: EMPIRICAL — E1(v)) |
| "69 GB/s/core" = 256 B per i8 fragment / 3.7 ns = 69.2; DDR gives each core 21.7–22.5 | T8_e2_mask, T9_69_per_core, T0_per_core_rates | model.py L201 [D8-e2] | PROVED |

### §1 Loop nest + tiling
| Claim | Proof | model.py | Status |
|---|---|---|---|
| N_c = 1024 / 512 / 256 at N = 8192 / 4096 / 2048; K/64 = 128 chunks | T4_Nc | — | PROVED |
| tile 16 KiB, A block 2 KiB, C sub-slab 16 KiB | T7_tiles, T7_a_block, T9_budget_arith | — | PROVED |
| (n=256, k=64) is the only shape with silicon evidence | ISA.md | — | INPUT; legal shapes EMPIRICAL — E1-sweep |
| 64 fragments per call → 236.8 ns (3.7) / 157.4 ns (2.46) | T3_per_call_tenths, T3_per_call_246 | model.py L74 [D1.3-percall] | PROVED |
| slab widths 1024 / 512 / 256 / 256 for mt = 1..4 at L0C = 64 KiB | T5_slabs, T5_nslabs | model.py L118 [D7.2] | PROVED |
| initVal = ZERO exactly at chunk 0; inverted polarity keeps only the last chunk; one chunk cannot detect it, two can | T8_accumulate_eq, T8_accumulation_semantics, T8_inverted_keeps_last, T8_single_chunk_cannot_detect, T8_two_chunks_detect, T8_two_chunks_values | — | PROVED (integer model) |
| calls = 512·mt (8192), 128·mt (4096), 32·mt (2048); instances 512/512/1024/1536/2048 | T4_calls_8192, T4_calls_4096, T4_calls_2048, T4_instances_8192, T4_instances_4096, T4_instances_2048, T4_mt_values | model.py L72–72 [D1.3-calls-*] | PROVED |
| MMA busy 121 / 242 / 364 / 485 µs (3.7); 113/227/340/454 (3.46); 81/161/242/322 (2.46) | T4_mma_us_370, T4_mma_us_346, T4_mma_us_246 | model.py L84–84 [D1.3-mma-*] | PROVED |
| tile cadence 728 ns at 22.5 GB/s/core, 754 at 21.725 | T3_cadence_16KiB_at_22_5, T3_cadence_16KiB_at_21_725 | model.py L77 [D1.3-cadence] | PROVED |
| slack 491.2 ns; c_mma ≤ 491 hides, 492 does not | T3_slack_256x64, T3_mma_off_critical_path, T3_mma_exposed, T3_490_safe | model.py L79 [D1.3-slack] | PROVED for all c |
| c_mma = 1 µs caps at 106.0 GB/s | T3_cap_1000 | model.py L80 [D1.3-cap1000] | PROVED |
| (1024×64) tiles: slack 1.96 µs | T3_slack_1024x64 | model.py L82 [D1.3-slack1024] | PROVED |
| m=64: 485 µs > 373 µs B-only DDR; 8 MiB/485 µs = 17.3 GB/s/core = 138.4/die | T3_m64_mma_time, T3_ddr_373, T3_m64_core_rate, T3_m64_die_rate | model.py L85 [D1.3-m64], model.py L86 [D1.3-ddr373] | PROVED |
| scheme-P m=64 is MMA-bound iff τ > 3.31 ns | T5_m64_P_switch, T5_m64_P_switch_tight, T5_m64_P_ddr_bound_246 | — | PROVED for all τ |
| no US→L0C path → k must be inner | ISA.md ("readable only via staged reads") | — | INPUT (ISA) |
| k-outer would drain 128 × 64 KiB = 8 MiB·mt per core | T5_korder_cost | — | PROVED |
| A is 2 KiB of every 66 KiB (3.1 %) at mt=1, 12.5 % at mt=4 | T5_korder_cost | — | PROVED |
| pack order = visit order gives one contiguous 8 MiB region per core | T7_tiles | — | PROVED (that this pattern reaches 180 GB/s: INPUT, HW-MAP per-core slabs) |
| scheme P: A block 256 KiB; 1 MiB drain; A once = 12.5 %; 434 µs → 154.5, MMA-capped 138.4 / 148.0 | T5_P_geometry, T5_ddr_us, T5_m64_P_246, T5_m64_P_370, T5_m64_P_346 | model.py L118 [D7.2] | PROVED |
| scheme P drain 105 µs at 10 GB/s/core; needs ≥ ~10 to stay hidden | T5_P_drain | model.py L191 [D1.4-copies] | PROVED (drain rate EMPIRICAL — E6) |
| scheme P adds 196 608 lane-ops = 4.6 µs; US↔S1 2 MiB = 8.4 µs; S1 = 768 KiB | T5_P_adds, T5_P_copies, T5_P_s1 | model.py L190 [D1.4-adds], model.py L191 [D1.4-copies] | PROVED |

### §2 Buffer budget
| Claim | Proof | model.py | Status |
|---|---|---|---|
| B ring 4 × 64 = 256 KiB; A ring ≤ 32 KiB; L0A ≤ 16 KiB; L0B 32 KiB; L0C 64 KiB; s 4 KiB; y ≤ 32 KiB; drain 4–64 KiB | T9_budget_arith, T7_a_block | — | PROVED |
| 64 KiB = largest legal COPY; queue depth = buffer count | HW-MAP errata 2, 9 | — | INPUT |
| one chunk (66 KiB) = 3.0–3.1 µs; depth 4 keeps ≥ 2 chunks = 6.2 µs ahead | T9_chunk, T9_chunk2 | model.py L93 [D4.1-chunk] | PROVED (that this hides copy issue latency: EMPIRICAL — E0/E7) |
| A resident 256 KiB (mt=1), 512 KiB (mt=2); needs S1 ≥ 768 KiB; the 1 MiB at mt=3 does not fit 976 KiB | T5_a_bytes, T5_m32_resident, T5_m48_not_resident, T0_units | model.py L118 [D7.2] | PROVED (S1 size EMPIRICAL — E7) |
| L0B tile 2 × 32 KiB upgrade if L0B ≥ 64 KiB | — | — | EMPIRICAL — E4 |
| S1 totals 288 KiB / 800 KiB; US ≤ 100 KiB | T9_s1_budget, T9_budget_arith | — | PROVED |
| W4 US budget 164 KiB ≤ 208 | T6_us_budget | — | PROVED |

### §3 Layouts
| Claim | Proof | model.py | Status |
|---|---|---|---|
| HW-MAP fragment geometry F = [N/16][K][16], i8 block (i, r) at (i·Kb + r)·32 | — | — | INPUT (HW-MAP, silicon-verified) |
| G1c: (k, n') ↦ ((n' div 32)·64 + k)·32 + n' mod 32 is a bijection onto [0, 16384) and is HW-MAP's formula with Kb = 64, i < 8 | T7_g1c_range, T7_g1c_left_inverse, T7_g1c_right_inverse, T7_g1c_injective, T7_g1c_is_hwmap_formula, T7_g1c_groups | — | PROVED |
| G1a, G1b: bijections onto the 16 KiB tile | T7_g1a_range, T7_g1a_left_inverse, T7_g1a_right_inverse, T7_g1b_range, T7_g1b_left_inverse, T7_g1b_right_inverse | — | PROVED |
| G2: injective, tile = 32 KiB (2 B per element) | T7_g2_injective, T7_g2_tile_is_32KiB, T7_g2_range | — | PROVED |
| round-1 formula not onto: byte 16 never hit; last element at byte 32751 | T7_old_misses_byte_16, T7_old_exceeds_tile | — | PROVED |
| which geometry the silicon uses | — | — | EMPIRICAL — E1(v) pack probe |
| G2 ⇒ W8 stream 130 MiB → 85.6; Route 1b thresholds 43.5 / 31.0 | T9_g2_rate, T2_1b_threshold_roof, T2_1b_threshold_target | model.py L200 [D9-g2] | PROVED |
| T = 4/2/1 tiles per k-chunk; 16384 B per tile; 4 tiles per 64 KiB copy; per-core region 8 MiB / 2 MiB / 512 KiB | T7_tiles, T7_tiles_4096, T7_tiles_2048 | — | PROVED |
| A pack order [K/16][16 m][16 k] (P) | — | — | EMPIRICAL — E1(ii) one-hot probe |
| A blocks 2 KiB·mt contiguous per chunk | T7_a_block | — | PROVED |
| C layout [N_slab/16][16 m][16 n] f32 (P); row 0 drain = 4 KiB = 64 runs × 64 B at stride 1024 | T7_a_block, T9_budget_arith | — | geometry EMPIRICAL — E1/E6; byte counts PROVED |
| Mul of 1024 lanes = errata-3 limit | HW-MAP errata 3 | — | INPUT |
| 2D US→DDR copy is a real position pair | — | — | EMPIRICAL — E5 |
| COPY_FRAC fallback: 4.7 µs = 1.2 % of 8192²; 8 KiB at 2048², m=16 → 1.2 µs = 4.3 % of 27 µs | T7_frac_cost, T7_frac_cost_2048 | model.py L193 [D3.3-frac] | PROVED |
| f16 saturation at 65504; rounding-mode no-ops | HW-MAP errata 5, 6 | — | INPUT; EMPIRICAL — E9 |

### §4 Pipeline + sync
| Claim | Proof | model.py | Status |
|---|---|---|---|
| copy-in 66 KiB per chunk: 3.11 µs at 21.725, 3.00 at 22.5 | T9_chunk | model.py L93 [D4.1-chunk] | PROVED |
| loader needs 66 KiB per chunk / L → 21.725/L occupancy | DEFINITION (same bytes) | — | DEFINITION; L EMPIRICAL — E2 |
| MMA 0.947·mt µs per chunk → 30.5 / 60.9 / 91.4 / 121.8 % | T9_chunk2, T9_chunk_occupancy | model.py L96–96 [D4.1-occ-*] | PROVED |
| slab end: 32 768 lane-ops = 0.76 µs at mt=1 | T1_epilogue_ns | model.py L98 [D4.1-epilogue] | PROVED |
| fill + drain ≤ 5 µs | — | FILL_NS | ASSUMPTION — EMPIRICAL E7/E10 |
| 5 µs = 1.2 % at 8192², 15.6 % at 2048² | T1_fill_pct, T9_chunk2 | model.py L102 [D7.1], model.py L155 [D7.4] | PROVED (given the assumption) |
| nine barriers B1–B9; queue depths 4/4, 4/4, 2/2, 2/2 | structural; HW-MAP errata 9 | — | DEFINITION / INPUT |
| ~512 B corruption islands without barriers | HW-MAP errata 8 | — | INPUT |
| bit-identical reps detect a missing barrier (fixed accumulation order) | — | — | EMPIRICAL — E7 (positive control included) |

### §5 W4
| Claim | Proof | model.py | Status |
|---|---|---|---|
| 32 MiB per die; 8 Mi elements per core; 193 µs at 173.8; target = 280 µs | T6_elements_per_core, T6_w4_ddr_time | model.py L166 [D5-ddr] | PROVED |
| D = 43.2 → 194 µs → dequant-bound 172.8; DDR incl. A caps at 163.6 | T6_dequant_432, T6_w4_ddr_incl_A | model.py L169 [D5-dequant-432], model.py L166 [D5-ddr] | PROVED (D itself EMPIRICAL — E8) |
| D = 30 → 280 µs → 120.0 | T6_dequant_300 | model.py L169 [D5-dequant-300] | PROVED |
| break-even with W8 at the roof: D ≥ 21.8 (385 µs, 87.2); D = 21.7 → 86.8 short | T6_w4_beats_w8, T6_dequant_218, T6_dequant_217 | model.py L169 [D5-dequant-218], model.py L169 [D5-dequant-217] | PROVED for all D, L |
| loader f16 needs 86.9 GB/s/core at roof, 60 at target (4× the W8 requirement) | T6_w4_roof, T6_w4_target | model.py L170 [D5-loader] | PROVED |
| US→S1 at 250 GB/s/core suffices | Measured.rUsS1 | — | INPUT |
| f16 MMA consumption 138.4 GB/s/core; 62.8 % busy at 86.9 | T6_f16_consumption | model.py L174 [D5-mma] | PROVED |
| vector arrange ≈ 5 lane-ops/element | ISA.md op list (And, shift/Mul, cast, Adds, Mul) | — | ASSUMPTION (op count) |
| 971 µs → 34.6 W4-GB/s = 69.2 W8-equivalent | T6_vector_arrange | model.py L171 [D5-vector] | PROVED (given 5 ops) |
| errata 4/6 on the hot path; measured 22 GB/s vector W4 | HW-MAP | — | INPUT |
| f16 round trip: 772 µs → 43.5 W4-equivalent; = the measured 144–148 matmul | T6_f16_roundtrip | model.py L172 [D5-f16] | PROVED / INPUT |
| (d) 64 drains × 64 KiB·mt = 4 MiB·mt; viable only if drain ≥ ~50 GB/s/core | T6_drains | model.py L175 [D5-drains] | PROVED; threshold EMPIRICAL — E6 |
| group-scale semantics V1 / V2; loader transpose variant | — | — | EMPIRICAL — E8 |
| decision rule: beats W8 iff D ≥ 21.8 ∧ L ≥ 43.5; target iff D ≥ 30 ∧ L ≥ 60; roof iff D ≥ 43.5 ∧ L ≥ 86.9 | T6_w4_beats_w8, T6_w4_target, T6_w4_roof | model.py L204 [D-const] | PROVED for all D, L |

### §6 Cross-core partitioning
| Claim | Proof | model.py | Status |
|---|---|---|---|
| each core streams a disjoint 8 MiB region; A 2 MiB·mt total = 3.1 %·mt | T7_tiles, T5_korder_cost | — | PROVED |
| no cross-core sync available to hand-rolled kernels | ISA.md | — | INPUT |
| 180 GB/s was measured as 8 concurrent per-core slabs (fairness inside the figure) | HW-MAP | — | INPUT |
| aggregate = min(DDR, 8·L·64/66, 8 × MMA tile rate) | `predictedW8`, `mmaCap` | — | DEFINITION |
| K-split at m=64: 99 MiB → 112.4 (97.5 with +91 µs) < 115.9 | T9_ksplit, T9_ksplit_worse_than_nsplit | model.py L182 [D6-ksplit] | PROVED |
| M-split: 258 MiB → 43.1 | T9_msplit | model.py L184 [D6-msplit] | PROVED |
| QKV / gate-up fusion → 4 launches per layer instead of 7 | counting (Q,K,V,O,gate,up,down) | — | DEFINITION |
| 2048² standalone 35.5 wall; 8192² 137.2 wall | T9_2048, T1_wall_with_launch | model.py L155 [D7.4] | PROVED (launch pipelining EMPIRICAL — E0) |

### §7 Predicted performance
| Claim | Proof | model.py | Status |
|---|---|---|---|
| §7.1 table: 8 650 752 B/core, 398 µs, loader ≥ 21.8 / 15.5, MMA 121/81 µs = 30.4/20.2 %, vector 758 ns = 0.2 %, fill 1.2 % | T1_bytes_per_core, T1_m1_ddr_time, T1_m1_ddr_time_us, T2_loader_threshold_roof, T2_loader_threshold_target, T1_mma_time_370, T1_mma_time_246, T1_mma_occupancy_370, T1_mma_occupancy_246, T1_epilogue_ns, T1_epilogue_pct, T1_fill_pct | model.py L102 [D7.1] | PROVED |
| §7.1 168.5 at 173.8 (= 173.8 × 64/66); 174.5 at 180 | T1_m1_ddr_bound_rate, T1_m1_rate_is_64_66, T1_m1_rate_at_180, T1_m1_bytes | model.py L113 [D7.1-rate] | PROVED |
| §7.2 table rows (bytes, times, MMA columns, predictions, bound labels) | T5_slabs, T5_nslabs, T5_a_bytes, T5_ddr_bytes, T5_ddr_us, T4_mma_us_370, T4_mma_us_346, T4_mma_us_246, T5_m32, T5_m32_restream, T5_m48, T5_m64, T5_m64_P_370, T5_m64_P_346, T5_m64_P_246, T5_m64_bigL0C, T5_m64_bigL0C_slab, T5_m32_ddr_bound, T5_m48_ddr_bound, T5_m64_ddr_bound, T5_m64_P_mma_bound_370, T5_m64_P_mma_bound_346, T5_m64_P_ddr_bound_246, T5_rows_tau_independent | model.py L118 [D7.2] | PROVED |
| §7.2 scheme-P band MMA-bound for τ > 3.31 ns; m=64 is 3 % under target | T5_m64_P_switch, T5_m64_P_switch_tight, T5_m64_shortfall | — | PROVED |
| §7.3 predicted = min(168.5, 8·L·64/66); target iff L ≥ 15.5; DDR-bound iff L ≥ 21.8; loader-bound branch ≤ 168.3 | T2_loader_threshold_target, T2_loader_threshold_roof, T2_loader_bound_branch, T2_loader_rate_monotone | model.py L147 [D7.3] | PROVED for all L |
| §7.3 table (8 rows × 3 columns) | T2_table_w8, T2_table_loader, T2_table_1b, T2_at_100, T2_at_155, T2_at_185, T2_at_217, T2_at_220 | model.py L147 [D7.3] | PROVED |
| §7.3 inference: ≥ 18.5 GB/s/core on *some* L0 ingress path → ≥ 143.5 **if** it is S1→L0 | T2_inference_from_library (premise `L ≥ 185` explicit) | — | PROVED conditional; premise EMPIRICAL — E2/E3 |
| §7.4 table: 2048² (27 µs, 154.5 / 130.5 / 35.5), 4096² (103 µs, 163.6 / 156.0 / 86.7), 8192² (398 µs, 168.5 / 166.4 / 137.2) | T9_2048, T9_4096, T9_sizes_us, T1_m1_ddr_time_us, T1_m1_ddr_bound_rate, T1_with_fill, T1_wall_with_launch | model.py L155 [D7.4] | PROVED (fill column rests on the 5 µs ASSUMPTION) |
| §7.5 route 1 ceiling min(180, 8·L·64/66, 8·16 KiB/(236.8 + c_mma)); control cost linear in K·N | T1_*, T2_*, T3_cap_0, T3_cap_1000; `calls` is a product | — | PROVED / DEFINITION |
| §7.5 route 2 token-rate conditions | T6_w4_beats_w8, T6_w4_roof | — | PROVED |
| §7.5 route 3: 127²·8192 < 2³¹; same bytes and fragments | T8_i32_no_overflow; DEFINITION | — | PROVED / DEFINITION |
| §7.5 route 4: 43.2/3 = 14.4 G/s/core → 115.2 GB/s/die; m=16 → 4.4–4.9 | T9_route4, T9_route4_m16 | model.py L194 [D7.5-route4] | PROVED (70–78 INPUT) |
| §7.5 route 5: 60 ns × 128² = 983 µs per tile; 4.2 GB/s | T9_route5 | model.py L195 [D7.5-route5] | PROVED / INPUT |

### §8 Experiment ladder
| Claim | Proof | model.py | Status |
|---|---|---|---|
| E0–E10 outcomes (launch floor behaviour, numerics, loader rate, direct loads, L0 sizes, copy pairs, drain rate, barriers, dequant, rounding, final rate) | — | — | EMPIRICAL — the ladder itself |
| E1 oracle exactness (|b| ≤ 15, column sums exact in f32) and the ≥ 2-chunk rule | T8_e1_exact, T8_two_chunks_detect, T8_single_chunk_cannot_detect | — | PROVED |
| E2: 10 000 × 64 × 15 = 9.6e6 < 2²⁴; MMA cannot mask L below 69.2 | T8_e2_exact, T8_e2_mask | model.py L201 [D8-e2] | PROVED |
| E6 thresholds 10 / 50 GB/s/core | T5_P_drain | — | PROVED (10 → 105 µs); 50 is the §5(d) requirement, PROVED via T6_drains volume |

### §9 Risk register
| Claim | Proof | model.py | Status |
|---|---|---|---|
| L ≤ 21.7 → loader-bound 8·L·64/66; L ≥ 15.5 still meets target | T2_loader_bound_branch, T2_loader_threshold_target | model.py L147 [D7.3] | PROVED |
| L0C 32 KiB: m=16 → 2 slabs, A resident → 168.5 (163.6 if re-streamed); m=64 with n=128 → 8 slabs → 86.9 | T5_l0c32_m16, T5_l0c32_m16_if_restreamed, T5_l0c32_m64 | model.py L143 [D7.2-l0c32] | PROVED |
| L0B < 32 KiB: 16 KiB/L + 236.8 ns; L = 50 → 564.4 ns → 29.0 GB/s/core ≥ 21.8 | T9_l0b_single | model.py L197 [D9-l0b] | PROVED |
| S1 < 768 KiB: 163.6 → 154.5; rings fit 512 KiB | T5_m32, T5_m32_restream, T9_s1_budget | — | PROVED |
| 16³-only: 32 768·mt calls, 11.3 ns slack | T4_16cube_calls, T4_16cube_slack_tenths | model.py L198 [D9-16cube] | PROVED |
| c_mma > 491 ns → MMA-issue-bound at 8·16 KiB/(236.8 + c) | T3_mma_exposed, `mmaCap` | — | PROVED / DEFINITION |
| launch floor: 35.5 / 137.2 wall | T9_2048, T1_wall_with_launch | model.py L155 [D7.4] | PROVED |
| copy-in issue latency hidden up to 1.46 µs per call | T4_copyin_calls | model.py L199 [D9-copyin] | PROVED |
| geometry G2 → 85.6; Route 1b 168.5 if L ≥ 43.5, target iff L ≥ 31.0 | T9_g2_rate, T2_1b_threshold_roof, T2_1b_threshold_target | model.py L200 [D9-g2] | PROVED |
| remaining rows (oracle failures, dequant semantics, rounding no-op, missing barrier) | — | — | EMPIRICAL — E1, E8, E9, E7 |

### §10 Measurement wishlist
| Claim | Proof | model.py | Status |
|---|---|---|---|
| loader rate decides 168.5 vs 8·L·64/66 | T2_* | model.py L147 [D7.3] | PROVED |
| L0C: 64 KiB → 115.9; 128 KiB → 138.4–139.0; ≥ 256 KiB → 138.4–154.5 | T5_m64, T5_m64_l0c128, T5_m64_bigL0C | model.py L118 [D7.2] | PROVED |
| 491 ns slack margin | T3_slack_256x64 | model.py L79 [D1.3-slack] | PROVED |
| DDR→L0 direct at ≥ 21.7 GB/s/core would delete S1 staging | T0_per_core_rates | — | PROVED threshold; existence EMPIRICAL — E3 |
| dequant unlocks up to 2× tokens/s | T6_w4_beats_w8 | — | PROVED |
| drain rate unlocks scheme P 138.4–154.5 | T5_m64_P_* , T5_P_drain | — | PROVED |
| A residency at m=32 worth 9.1 GB/s | T5_m64_shortfall | — | PROVED |
| copy-in issue latency matters only above 1.46 µs | T4_copyin_calls | model.py L199 [D9-copyin] | PROVED |

## Coverage summary
| Metric | Value |
|---|---|
| Ledger rows (quantitative claims in DESIGN.md) | 140 |
| PROVED (theorem in model.lean, incl. "PROVED from INPUT" and conditional proofs with explicit premise) | 102 (72 %) |
| INPUT (HW-MAP / ISA measurement, PRIOR, or errata used as given) | 20 |
| DEFINITION (true by construction of the cost model) | 5 |
| EMPIRICAL (only an experiment settles it; cited by ladder ID) | 11 |
| ASSUMPTION (explicitly labelled, measured by the named experiment) | 2 |
| Theorems in model.lean | 172 |
| Theorems cited by the ledger | 172 of 172 |
| Ledger theorem names not found in model.lean | 0  |
| model.lean theorems not cited in the ledger | 0 |

Every row's status is machine-checkable: PROVED rows name theorems that `lake build` checks;
model.py labels are grep-able; EMPIRICAL rows name the experiment whose observable failure mode
is specified in DESIGN.md §8. Claims that DESIGN.md does **not** make are not in this ledger, and
the model.lean theorem that did not correspond to a DESIGN.md claim (a monotonicity lemma for the
MMA-issue cap) was removed during round 2 rather than kept as an orphan proof.
