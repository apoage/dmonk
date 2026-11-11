# PROOF-COVERAGE-5 — ledger of every quantitative claim in ALTERNATIVES.md

How to read a row: **Claim** quotes or paraphrases the ALTERNATIVES.md statement (Appendix A row numbers; section
numbers refer to the corrected document); **Proof** names the theorem(s) in `proof/alt.lean` that fix the number;
**alt.py** names the label in `proof/alt.py` that prints it; **Status** is one of PROVED (follows arithmetically from
the constants; "∀ x" marks a universally quantified result over the unmeasured or assumed quantity x — both bracket
endpoints are then proved as cells), INPUT (a HW-MAP measurement used as given), D2/D3/D4 (a ledgered theorem of
DESIGN-2/3/4 used as input — the round-2 fleet / attention models duplicated in alt.lean's `Fleet2` / `Attn2`),
DEFINITION (true by construction, no number), EMPIRICAL — Ex/Hx (settled only by the named experiment; no theorem
claims it), ASSUMPTION — Hx (carried as a hypothesis variable of the theorems that use it), SUPERSEDED (true
arithmetic whose premise the steering inputs retired), CORRECTED (the formalization changed the claim — see the
corrections table; the theorem fixes the corrected statement).

Units in the proof file: bytes (KiB/MiB/GiB binary, GB decimal); rates in tenths of GB/s (1746 = 174.6); time in ns
(floored), quoted µs round-half-up (`usR`) or hundredths of ms floored (`ms2`); tokens/s in thousandths per card
(`tpsCard tok T = tok·10⁹/(4·T)`; `tpsInst` = two instances on the four cards; `tpsInstEta` adds the concurrency
efficiency η in thousandths); percentages in tenths (`pct`, round-half-up) and signed changes in tenths floored
toward zero (`pcsUp` / `pcsDown`, alt.py's `pcs`); int4 shares x in thousandths; the W4 core-slab time `Tc`, the
A-lift cost `a`, `csync`, `cpg`, `cV`/`rho`, the overhead `ort`, the bounce latency `lam`, the prefix `Ls`, the
drain rate `R` and η are explicit arguments of the model.

## Build status

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (`leanprover/lean4:v4.35.0`, elan), Lake 5.0.0 |
| `lean proof/alt.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 14 s (no imports beyond Init; Mathlib/Batteries not used) |
| `cd proof && lake build` | **succeeds** (target `Alt` = alt.lean added to `lakefile.toml`; the other five targets unchanged) |
| Theorems in alt.lean | **104** (`grep -c '^theorem'`): 32 ledger rows + 13 re-derived rows + the four load-bearing umbrellas `T_instance_gain_umbrella`, `T_direct_path`, `T_megakernel`, `T_two_tier` + 9 unfolding / monotonicity lemmas (`instTotal_*`, `instW_moe`, `vecBlock_mono_merge`, `blockMax_mono_merge`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` on the umbrellas and the ∀-theorems reports only the standard `propext` / `Classical.choice` / `Quot.sound` that `omega` / `simp` emit; the cell theorems (`decide`) depend on no axiom |
| `decide +kernel` | 7 (the Zipf traffic shares over D = lcm(1..256), a 110-digit scaled natural; the 255-case Int magic-bias checks; the hot/cold cell) — the elaborator's recursion limit, not the kernel's |
| Leaf closers | `decide`, `omega`, `rfl`, `simp only` with core lemmas (`Nat.mul_one`, `Nat.add_mul`, `Nat.mul_add`, `Nat.mul_assoc`), `exact`/`apply` of core lemmas (`Nat.le_div_iff_mul_le`, `Nat.div_lt_iff_lt_mul`, `Nat.lt_succ_iff`, `Nat.lt_iff_add_one_le`, `Nat.div_le_div_right`, `Nat.mul_le_mul_left/right`, `Nat.sub_le_sub_left`, `Nat.le_mul_of_pos_right`, `Nat.mul_lt_mul_of_pos_left`, `Nat.mul_left_comm`, `Nat.mul_div_mul_left`, `Nat.div_eq_of_lt`, `Nat.mod_eq_of_lt`, `Nat.div_add_mod`, `Nat.add_lt_add_iff_right`); structure: `unfold`, `rw`, `generalize`, `cases`, `by_cases`, `refine`, `calc` |
| `python3 -I proof/alt.py` | runs, no dependencies; the 135 original label lines print **byte-identical** to commit dd5f84c; the proof round appended the `[ALT-P-*]` section (31 labels) |
| Model duplication | `Fleet2` = fleet.py `step` at its primary branch with the expert-slab time, launches per layer and λ explicit (`today` = the ledgered cell); `Attn2` = attn.py `step_ns` (drain hidden, R_drain 10 GB/s, merge 7 000) + `G_tier`; `T_alt_baseline_identity` proves the "today" cells equal fleet.lean's 2 362 319 269 / 133 847 319 ns (0.105 / 1.867) and attn.lean's 775 778 / 851 470 / 903 650 / 24 605 602 ns |

## Inputs applied by steering before proving (PROMPT-5P)

| Input | Where it enters | Effect |
|---|---|---|
| **f16 → i8 activation pass MEASURED**: 43.7 µs per pass at m = 1, K = 8192, rint-half-even saturating ±127 (HW-MAP 0915e22) | `Measured.cQ`, `quantTok s = n_L × 4 × 43.7 µs`, `quantDraft` | rows 19–21 re-derived (P5–P7); the instance / direct-path / megakernel cells restated with the pass on both sides (P8, P12); T_instance_gain_q, T_megakernel_moe_q |
| **H10 GREEN at die scale**: two instances on disjoint dies at 1.99× aggregate (HW-MAP fa2c24a) | `Measured.etaH10 = 995`, `tpsInstEta` | T_instance_gain_h10: the verdict needs only η ≥ 482 ‰ (P9); the two-card inheritance stays the hypothesis |

## Corrections forced by formalization (ALTERNATIVES dd5f84c → this round)

| # | Where | Round 1 said | Now | Caught by |
|---|---|---|---|---|
| 1 | row 1, §2.1 cold path, §2.1 arithmetic, §5 E30, rows 8–11 | serial-chain piece per 2 KiB i4 = 386 + 16 + 154 + 25 + 15 = **596 ns** (4 KiB f16 legs, one MMA call): 305 152 ns per core-slab, 55.2 W8-equivalent, 3.4 GB/s/core; ser cells MoE 32k 3.531 (+89.1 %), dense 32k 0.122 (+16.1 %), dense 128k −4.2 %, MoE 128k 2.328, 1M 0.556; break-even 4.4× below the ser branch | a 2 KiB int4 piece is 4 096 values = **8 KiB of f16 and two (16,16,128) calls**: 386 + 32 + 309 + 50 + 30 = **807 ns**, **413 184 ns** per core-slab, **40.8** W8-equivalent, **2.5** GB/s/core; ser cells **MoE 32k 3.239 (+73.4 %)**, **dense 32k 0.100 (−4.7 %, a loss)**, dense 128k **−25.5 %**, MoE 128k 2.155, 1M 0.522; break-even margin **3.3×** — dense replication needs the overlapped regime (E30), MoE survives on both | T_alt_w4_ser_corrected, T_alt_rep_moe_32k, T_alt_rep_dense_32k, T_alt_rep_cells, T_instance_gain_measured |
| 2 | §0 item 4, rank 4, §2.4, rows 19–21 | quantizer = 19 / 8 µs per layer (0.1 / 0.2 %) via a magic-bias trick; fallback = host bounce −2.8 % / −13.2 % / −49 % | the pass is measured: **174.8 µs per layer = 0.9 % dense (0.105 → 0.104), 3.5 % MoE (1.867 → 1.801), draft +4.20 ms (+23.1 %), spec 0.262 → 0.258**; the bounce fallback was priced at λ = 91 µs — at the measured 12.2 µs it would be **107 / 100 µs per layer, less than the pass** (0.105 / 1.829); magic bias retired as a mechanism (arithmetic still proved) | T_alt_quant_measured, T_alt_quant_bounce_measured_lambda, T_alt_quant_cost_written, T_alt_quant_fallback_written |
| 3 | row 4, §2.2 | "hidden iff R_drain ≥ 0.3 GB/s/core" | **iff R_drain ≥ 0.4** in tenths (exact threshold 0.341: at 0.3 the drain is 109 226 ns > 96 089; `rateT` rounded 3.41 to 3); the measured 152.8 is 382× above | T_alt_direct_drain (∀ R), T_alt_direct_drain_cells |
| 4 | row 23, §2.5 | "G_tier ≥ G(64 KiB) ∀ c_pg ≥ 0, L ≥ 1, with equality iff c_pg = 0; G_tier ≤ G(1 MiB) with equality iff 4096 \| L" | in the floored model the 1 MiB extent (48 044 ns) is **12 ns per MiB slower** than 16 pages (48 032) at c_pg = 0; with ≥ 1 extent **t_tier < t_64 iff c_pg ≥ 1 ns** (per extent 15·c_pg − 12 ns), identical below one extent; in tenths equal for c_pg ≤ 2 ns; the 1 MiB bound with "equality iff 4096 \| L" holds **for c_pg ≥ 1** (at 0 a floored tail page is 0.75 ns faster than its share of an extent); at the measured c_pg = 38 ns **+1.1 %** (174.4 vs 172.4, step 786 → 777 µs), at 114 ns **+3.5 %** | T_alt_tier_dominates (∀ L c), T_alt_tier_below_extent, T_alt_tier_le_1MiB, T_alt_tier_tenths, T_two_tier_measured |
| 5 | row 7, §2.1 memory margin | "the minimal x leaves 0.1 GB per die" | **24–40 MB (MoE 32k) / 3–45 MB (dense 32k) / 2–32 MB (MoE 1M)**: "0.1" was 86.0 − 85.9 in floored tenths; the x shift per GB is +22 ‰ (MoE) / +20–21 ‰ (dense) — the 2.2 % / 2.1 % slopes as stated | T_alt_fit_margin, T_alt_fit_dx_per_gb, T_alt_fit_overhead_moe/dense (∀ ort) |
| 6 | row 16, §2.3 | dense "pays iff c_sync ≤ 109.9 µs" as a strict iff | at exactly 109 903 ns the dense step **ties** (2 362 319 269 = today): pays (≤) iff c_sync ≤ 109 903, strictly iff ≤ 109 902; MoE 108 430 in both forms | T_megakernel_dense, T_alt_mega_threshold_cells |
| 7 | §2.2, table row 11, §4 | G = 2 knob "+1.7 %" | **+1.6 %** in the pcs convention (169.9 vs 167.1 GB/s; the real time ratio is 1.68 %) | T_alt_direct_g2 |
| 8 | §4 draft on the host | "≤ 54 ms per verify step = 2.3 %" | 54.28 / 2 416.72 ms = **2.2 %** | T_dominated_draft_host |

Tightenings that are not corrections: (a) "6.6× below the measured 5.3" is the rate ratio; in slab time the
measured 197 844 ns is 6.9× inside the break-even (T_instance_gain_measured); (b) the `[ALT-4-draft]` label's
"+17.52 ms" is 17 529 600 ns (T_alt_quant_fallback_written); (c) the Zipf traffic shares are proved exactly as
scaled naturals (D = lcm(1..256), every r ≤ 256 divides D — T_alt_zipf_divisible) rather than quoted to 0.1 %;
(d) the dense direct-path step is affine in the chain time (T_alt_direct_fleet_form), the MoE instance step affine
in the two cold-tier terms (T_instance_form) — the forms behind the iffs.

## Appendix A — the 32 rows

| # | Claim | Value | Status | alt.py label | Proof (alt.lean) |
|---|---|---|---|---|---|
| 1 | W4 vector path 5.3 GB/s/core of int4 = 42.4 per die = 84.8 W8-equivalent; 197 844 ns per 1 MiB core-slab; serial chain 596 ns per 2 KiB → 305 152 ns, 55.2 (as written) | 53 / 424 / 848 / 197 844 / 596 / 305 152 / 552; **corrected 807 / 413 184 / 408 / 2.5 GB/s** | INPUT (5.3) → PROVED; **CORRECTED** (ser branch) | [ALT-0-w4v] [ALT-P-w4ser] | T_alt_w4_rates, T_alt_w4_ser_corrected |
| 2 | direct-path chain per core: B 96 089, A lift 2 473 + 812 = 3 285, serialised 99 374 / overlapped 96 089, G = 2 97 731, MMA 15 360 = 16.0 % | as quoted | PROVED | [ALT-1-chain] | T_alt_direct_chain |
| 3 | step 8 × chain + F = 802 992 → 167.1 / 776 712 → 172.8 vs 135.3 (+23.5 / +27.7 %); rate(a) ∈ [167.1, 172.8] for every A-lift cost a ∈ [0, 3 285] | as quoted; G = 2 → 169.9 (+1.6 %) | PROVED (∀ a) | [ALT-1-rate] [ALT-P-g2] | T_alt_direct_rate, T_alt_direct_bracket, T_alt_direct_bracket_ends, T_alt_direct_g2, T_direct_path |
| 4 | 32 KiB drain hidden iff R_drain ≥ 0.3 GB/s/core | **iff ≥ 0.4** (tenths; exact 0.341) | PROVED (∀ R > 0); **CORRECTED** | [ALT-1-rate] [ALT-P-drain] | T_alt_direct_drain, T_alt_direct_drain_cells |
| 5 | fleet MoE t = 1 with T_slab 99 374 / 96 089: 32k 117.98 / 115.77 ms → 2.118 / 2.159 (+13.4 / +15.6 %), 128k 1.369 / 1.386, 1M 0.318 / 0.319, B = 16 2.772; ping-pong branch within 1.4 % | as quoted | PROVED (D4 model) | [ALT-1-fleet-*] | T_alt_direct_fleet, T_alt_direct_fleet_form |
| 6 | minimal int4 share per die: MoE 32k 182/170/170/182, 128k 244/232/232/244, 1M 827/816/816/827; dense 32k 376/358/332/376, 128k 629/610/585/629; KV-int8 variants; B = 16 494/482; dense 1M infeasible at x = 1000 (KV alone 128.8 / 64.4 GB); weights(x) non-increasing → the minimal x is an iff | as quoted | PROVED (∀ x: iff; dense 1M ∀ x ≤ 1000, ∀ ort) | [ALT-2-fit-*] [ALT-2-fit-table-*] [ALT-2-mindies] | T_alt_fit_monotone, T_alt_fit_minx_moe_32k, T_alt_fit_minx_dense_32k, T_alt_fit_minx_cells, T_alt_fit_dense_1M_infeasible, T_alt_fit_allw4 |
| 7 | per-die totals 85.9 GB on every position; margin 0.1 GB; Δx per GB = 2.2 % / 2.1 %; 1 % of x = 0.66 ms; ship x + 3 % → 130.9 ms / 3.82 | totals 85.9 ✓; **margin 24–40 / 3–45 MB**; +22 / +20–21 ‰ per GB; 661 724 ns per 1 %; 130.88 ms → 3.820 | PROVED (∀ ort, ∀ x); **CORRECTED** (margin) | [ALT-2-fit-table-*] [ALT-P-margin-*] | T_alt_fit_margin, T_alt_fit_overhead_moe, T_alt_fit_overhead_dense, T_alt_fit_dx_per_gb, T_alt_fit_ship_margin |
| 8 | instance step MoE 32k uniform: W 88.60 + KV 21.52 + launch 18.01 + xch 0.75 = 128.89 ms → 3.878 (+107.7 %); ser 141.59 → 3.531; anchor hot 141.97 → 3.521; Zipf(1.0) 119.31 → 4.190 | as quoted; **corrected ser 154.36 → 3.239 (+73.4 %)** | PROVED (D4 model; popularity family EMPIRICAL — H9, the Zipf arithmetic exact) | [ALT-2-moe-32768-*] [ALT-P-ser-moe-32768] | T_alt_rep_moe_32k, T_alt_rep_zipf |
| 9 | dense 32k: W 3 039.24, step 3 197.94 → 0.156 (+48.5 %); ser 4 069.94 → 0.122 (+16.1 %); KV-int8 0.163; spec k = 3 α = 0.7 3 252.30 → 0.389 (+48.4 %) | as quoted; **corrected ser 4 951.64 → 0.100 (−4.7 %)** | PROVED; **CORRECTED** (ser) | [ALT-2-dense-32768-*] [ALT-2-dense-32k-spec] [ALT-P-ser-dense-32768] | T_alt_rep_dense_32k |
| 10 | long context: MoE 128k 2.530 (+100.9 %), 1M 0.596 (+91.0 %); dense 128k 0.123 (+30.8 %), ser −4.2 %; MoE B = 16 4.084 (+73.2 %) | as quoted; corrected ser: dense 128k −25.5 %, MoE 128k 2.155, 1M 0.522 | PROVED; **CORRECTED** (ser) | [ALT-2-moe-131072-*] [ALT-2-moe-1048576-*] [ALT-2-dense-131072-*] [ALT-2-moe-32k-B16] [ALT-P-ser-*] | T_alt_rep_cells |
| 11 | two instances beat one for every W4 core-slab time ≤ 1 371 124 ns (≥ 0.8 GB/s/core); 6.6× below 5.3; 4.0 / 3.0 GB/s → 3.662 / 3.405 | **iff for every Tc** (1 868 vs 1 867 at the boundary); measured 197 844 instantiated (6.9× in time); corrected ser 3.3× inside; with the pass on both sides ≤ 1 412 631 ns (3.737 vs 1.801, +107.4 %); η ≥ 482 ‰ suffices (995 measured → 3.859) | PROVED (∀ Tc, ∀ η; H10 EMPIRICAL at card scale) | [ALT-2-breakeven-moe-32k] [ALT-2-sens-w4rate-*] [ALT-P-breakeven-q] [ALT-P-h10] [ALT-P-inst-*] | T_instance_form, T_instance_gain, T_instance_gain_measured, T_instance_gain_q, T_instance_gain_q_cells, T_instance_gain_h10, T_instance_gain_h10_cells, T_instance_gain_umbrella |
| 12 | all-W4 replication 2.725 < 3.878; hot/cold tier on the 8-die fleet loses: 146.42 ms (−8.5 %) uniform, 136.20 (−1.7 %) Zipf | as quoted (per-layer delta 449 190 ns) | PROVED | [ALT-2-allw4-moe-32k] [ALT-9-hotcold-*] | T_alt_rep_dominates_allw4, T_alt_hotcold_loses |
| 13 | Zipf(1.0): the coldest 10 / 25 / 50 / 75 % of 256 experts carry 1.7 / 4.7 / 11.3 / 22.5 % of the traffic | 17 / 47 / 113 / 225 tenths of a percent, exact over D = lcm(1..256); the shares at x = 182 / 170 ‰ are 3.2 / 3.0 % | PROVED (the family itself EMPIRICAL — H9) | [ALT-2-zipf-share] | T_alt_zipf_divisible, T_alt_zipf_share |
| 14 | combinations: §2.2 + §2.3 (5 µs) 103.50 ms → 2.415 (+29.3 %); §2.1 + §2.2 + §2.3 114.41 → 4.369 (+134.0 %), dense 3 147.59 → 0.158 (+50.4 %); §2.1 + KV-int8 MoE 1M 472.40 → 1.058, 128k 151.78 → 3.294 | as quoted | PROVED | [ALT-3+1-moe] [ALT-2+3-*] [ALT-2+6-moe-*] | T_alt_combos |
| 15 | megakernel savings (nlaunch − 1) × 91 µs × n_L = 54.60 / 15.28 ms; reduction traffic 1 343 488 B → 7 694 ns (1.84 ms per token), 335 872 B (0.10 ms); 480 / 140 syncs | as quoted at the conservative 91 µs primary; **ADJUDICATED at the realized ≤ 36 µs bound (HW-MAP realized-launch row): savings 21.60 / 6.048 ms, net prize ≤ 0.4 % dense / ≤ 2.7 % MoE at 20 µs crossings — the family's case rests on the measured sub-µs sync, not on serialization** | PROVED (both) | [ALT-3-*] | T_alt_mega_savings, T_alt_mega_savings_realized |
| 16 | pays iff c_sync ≤ 113 750 / 109 200 (launch only), ≤ 109 903 / 108 430 net (dense / MoE); cells at 2 / 5 / 20 µs: dense 0.108 / 0.108 / 0.107, MoE 2.101 / 2.094 / 2.058 | **iff for every c_sync, both directions**; dense ties at 109 903 (strict ≤ 109 902); MoE threshold invariant under the measured pass | PROVED (∀ c_sync); **CORRECTED** (dense tie) | [ALT-3-*-threshold] [ALT-3-*-csync*] [ALT-P-variants-q] | T_megakernel_dense, T_megakernel_moe, T_megakernel_moe_q, T_alt_mega_threshold_cells, T_alt_mega_cells, T_megakernel |
| 17 | draft token 18 092 / 9 265 / 7 172 µs at 121 / 24 / 1 launches; verify step 54.27 / 27.79 / 21.51 ms | as quoted (launch share 60.9 %) | PROVED | [ALT-3-draft-*] | T_alt_draft_launches |
| 18 | head-aligned QKV packing alone: dense 2 351.39 ms (+0.9 %), MoE 131.29 (+1.9 %); the attention of KV head c needs only core c's slice | cells as quoted; the slice property is a DEFINITION (a host-side column permutation, no number) | PROVED / DEFINITION | [ALT-3-headaligned-*] | T_alt_headaligned, T_alt_launch_table |
| 19 | f16 magic bias 1280: q + 1280 ∈ [1024, 2048) and low byte = q mod 256 for every q ∈ [−127, 127]; f32 analogue with bias 12 582 912 | true (exhaustive over 255 values; −128 also satisfies it) | PROVED (`decide +kernel` over 255 Int cases); **SUPERSEDED** as a mechanism (HW-MAP 0915e22: the cast exists) | [ALT-4-magic] | T_alt_magic_f16, T_alt_magic_f32, T_alt_magic_cells |
| 20 | quantizer cost 102 400 / 45 056 elements × 8 lane-ops = 19 / 8 µs per core per layer = 0.1 / 0.2 % | as written ✓ (18 962 / 8 343 ns); **RE-DERIVED: 4 × 43.7 µs = 174.8 µs per layer = 0.9 % / 3.5 %** (9× the estimate) | PROVED (as written, op count ASSUMPTION) → **CORRECTED** by the measured pass | [ALT-4-dense] [ALT-4-moe] [ALT-P-quant-*] | T_alt_quant_cost_written, T_alt_quant_measured |
| 21 | host-quantization fallback 738 / 730 µs per layer → dense 2 450.82 ms (−2.8 %), MoE 154.29 (−13.2 %); draft +17.52 ms; Route-1b 106.0 | as written ✓ (at λ = 91 µs); **RETIRED**: at the measured λ the bounce is 107 / 100 µs per layer (0.105 / 1.829), cheaper than the pass | PROVED (as written) → **CORRECTED** | [ALT-4-*] [ALT-4-route1b] [ALT-P-quant-*] | T_alt_quant_fallback_written, T_alt_quant_bounce_measured_lambda, T_alt_variants_q |
| 22 | two-tier G at 32k: 174.2 / 172.8 / 167.6 / 155.2 at c_pg = 0.1 / 0.5 / 2 / 6.005 µs vs 64 KiB 169.0 / 149.7 / 104.8 / 58.2; at 34 768: 173.6 / 171.0 / 161.6 / 141.1; at c_pg = 0 all 174.6 | as quoted (34 768 at c_pg = 0 is 174.3: the eight tail pages) | PROVED (c_pg EMPIRICAL — E34; measured lower bound 38 ns) | [ALT-5-G-cpg*] | T_alt_tier_cells |
| 23 | G_tier ≥ G(64 KiB) ∀ c_pg, L with equality iff c_pg = 0; G_tier ≤ G(1 MiB) with equality iff 4096 \| L | **restated**: t_tier < t_64 iff c_pg ≥ 1 ns (≥ 1 extent), identical below one extent, 1 MiB bound exact for c_pg ≥ 1 with equality iff 4096 \| L; tenths equal for c_pg ≤ 2; at 38 / 114 ns +1.1 / +3.5 % | PROVED (∀ L, ∀ c_pg); **CORRECTED** | [ALT-P-tier-floor] [ALT-P-tier-cpg*] [ALT-P-tier3-cpg*] | T_alt_tier_dominates, T_alt_tier_below_extent, T_alt_tier_le_1MiB, T_alt_tier_tenths, T_two_tier_measured, T_two_tier |
| 24 | attention t = 1 native corner: 32k 904 → 784 µs (−13.2 %) at 0.5 µs, 1 288 → 808 (−37.2 %) at 2 µs, 2 313 → 872 (−62.3 %) at 6.005 µs; 1M 28 698 → 24 862, 40 988 → 25 632, 73 803 → 27 680; at c_pg = 0 nothing moves | as quoted | PROVED (D3 model) | [ALT-5-step-*] | T_alt_tier_steps |
| 25 | compaction 16 × 2 MiB per 4 096 tokens per layer = 46 ns per token-layer; tail waste ≤ 1 MiB per layer-sequence; ≤ 15 tails + 256 extents per 1M | as quoted (192 178 ns per layer per 4 096 tokens) | PROVED | [ALT-5-compaction] | T_alt_tier_overhead |
| 26 | K-int8 / V-f16: t = 1 block DDR-bound iff c_V ≤ 45 (ρ32 = 1) / 21 (ρ32 = 2) at 3/4 bytes (9 008 ns); 32k 776 → 584 µs (−24.7 %), worst 851 → 876 (+2.9 %); 1M 24 606 → 18 456 | **iff for every c_V** (8 885 / 9 074 ns at 46 / 47; 8 667 / 9 047 at 22 / 23 with ρ32 = 2) | PROVED (∀ c_V) | [ALT-6-threshold-*] [ALT-6-attn-*] | T_alt_k8_threshold, T_alt_k8_threshold_cells, T_alt_k8_steps |
| 27 | fleet K-int8: dense 32k 0.106 (+0.9 %), 128k 0.098 (+4.2 %); MoE 32k 1.946 (+4.2 %), 128k 1.413 (+12.2 %), 1M 0.397 (+27.2 %); full KV-int8 0.107 / 0.101 / 2.031 / 1.609 / 0.547 (+75.3 %) | as quoted | PROVED (D4 model) | [ALT-6-fleet-*] | T_alt_k8_fleet |
| 28 | shared prefix: KV per layer = kv_tok·((L − L_s)·B + L_s·passes)/R, passes = ⌈B·g/64⌉; dense B = 16 (4 passes) 12 299 → 11 146 / 7 687 / 4 228 µs → 1.108 / 1.252 / 1.439 (+3.8 / +17.3 / +34.8 %); MoE (1 pass) 2.414 / 2.605 / 2.828; gain iff passes < B | cells as quoted; **iff for every L_s ≤ L**: the shared stream is strictly shorter iff L_s ≥ 1 (passes 4 < 16, 1 < 16), and at B = 1 (passes = B) nothing changes | PROVED (∀ L_s; L_s EMPIRICAL — H12) | [ALT-7-*] | T_alt_prefix_cells, T_alt_prefix_iff |
| 29 | lazy rescale: S4 block DDR-bound without the merge iff c_V ≤ 7 (ρ32 = 1) / 3 (ρ32 = 2); t = 16 32k two-pass 1 554 / S4 1 032 / lazy 787 µs (native), 1 558 / 1 522 / 1 187, 6 802 / 7 140 / 6 471; 1M 49 209 / 32 388 / 24 611 …; lazy ≤ S4 and lazy ≤ two-pass on every corner | **iff for every c_V**; the six corners × 2 lengths as quoted; **lazy ≤ S4 for every L, G, c_V, ρ** (monotone in the merge count); lazy ≤ two-pass at 32k for every c_V at ρ32 ∈ {1, 2} | PROVED (∀ c_V; ∀ L G ρ for lazy ≤ S4) | [ALT-8-*] | T_alt_lazy_threshold, T_alt_lazy_cells, T_alt_lazy_dominates_S4, T_alt_lazy_dominates_twopass (+ vecBlock_mono_merge, blockMax_mono_merge) |
| 30 | lazy margin μ = 8: P ≤ e⁸ = 2 981 < 65 504; L0C with one O region = 3 × 64 + 64 = 256 KiB at mt = 8 | L0C sum PROVED (262 144 B = 256 KiB); 2 981 < 65 504 PROVED as integers; e⁸ = 2 981 is the DEFINITION of μ (transcendental, not proved) | PROVED / DEFINITION | — | T_alt_lazy_l0c |
| 31 | dominated: K-split net +2 µs (0.6 %) before any sync; specialization ≤ 58.2 GB/s (3× bytes); expert-parallel across dies −3.6 % (138.94 ms); zero-copy/NUMA/polling ≤ T_x = 1 497 / 1 480 µs; token dropping ×1.9; rows-cliff B = 64 at 4k dense 5.314 (×3.2) / MoE 5.618 (×1.9), L_max(64) at 32k 8 613 / 30 090; weight-stationary ≤ 1.5 %; no L2 (8 MiB > 8 MB); GQA padding ×2 / ×4; draft on the host 2.3 % | all as BOUNDS: K-split gain ≤ 2 252 ns and negative for any sync > 2 252 ns (a launch is 91 000); 3·W bytes at 174.6 = W bytes at 58.2 for every W (the cap from the map, errata #7); +2 λ per MoE layer loses for every λ > 0; the exchange bound for every replacement cost x; 15 749 312 → 7 878 656 ns; rows-cliff cells + L_max; 1 MiB of A per 65 MiB = 1.5 %; 8 × 10⁶ < 8 MiB; 16/8 = 2, 16/4 = 4; **draft share 2.2 %** | PROVED (∀ sync, ∀ W, ∀ λ, ∀ x); **CORRECTED** (2.2 %) | [ALT-9-*] [ALT-P-draft-share] | T_dominated_ksplit, T_dominated_specialization, T_dominated_specialization_cell, T_dominated_weight_stationary, T_dominated_l2, T_dominated_expert_parallel, T_dominated_expert_parallel_cells, T_dominated_hotcold, T_dominated_p2p, T_dominated_tokendrop, T_dominated_rowscliff, T_dominated_draft_host, T_dominated_gqa_padding |
| 32 | the 8-die primary cells are unchanged by every alternative that is switched off: the "today" columns reproduce fleet.lean / attn.lean exactly (2 362.31 / 133.84 ms, 776 / 24 606 µs) | 2 362 319 269 / 133 847 319 ns (0.105 / 1.867); 198 419 435 / 801 092 387 / 2 639 056 909; spec 2 416 719 328; B = 16 1 696 701 747 / 3 746 623 921; KV-int8 2 316 196 309 / 456 707 843; attention 775 778 / 851 470 / 903 650 / 24 605 602 ns; the shape byte counts equal their formulas; `directStep` at 122 979 = `today` | PROVED (identity to fleet.lean `T_serial`/`T_spec_dense`/`T_serial_moe_afrac`, attn.lean `T4_t1_32k`/`T4_t1_1M`) | all labels | T_alt_shapes, T_alt_baseline_identity, T_alt_direct_fleet (last conjunct) |

## Re-derived rows (post-correction claims, `[ALT-P-*]`)

| # | Claim | Value | Status | alt.py label | Proof |
|---|---|---|---|---|---|
| P1 | serial-chain piece corrected: 2 KiB int4 = 4 096 values = 8 KiB f16, two (16,16,128) calls; 807 ns, 413 184 ns per core-slab, 40.8 W8-equivalent, 2.5 GB/s/core; the loader leg (309) still hides under the unpack (386) so the ovl branch is unchanged | as stated | PROVED; **CORRECTION 1** | [ALT-P-w4ser] | T_alt_w4_ser_corrected |
| P2 | corrected ser cells: MoE 32k 154.36 ms → 3.239 (+73.4 %), 128k 2.155 (+71.1 %), 1M 0.522 (+67.3 %); dense 32k 4 951.64 → 0.100 (−4.7 %), 128k 0.070 (−25.5 %), kvi8 32k 0.108, 128k 0.088 | as stated (ns: 154 368 451, 232 015 153, 957 736 765, 4 951 649 663, 7 044 311 063) | PROVED | [ALT-P-ser-*] | T_alt_rep_moe_32k, T_alt_rep_dense_32k, T_alt_rep_cells |
| P3 | drain iff in tenths: ≥ 0.4 (0.3: 109 226 > 96 089; 0.4: 81 920 ≤ 96 089); exact 0.341; measured 152.8 → 214 ns, 382× | as stated | PROVED (∀ R > 0) | [ALT-P-drain] | T_alt_direct_drain, T_alt_direct_drain_cells |
| P4 | G = 2 as a rate: 789 848 ns → 169.9 GB/s = +1.6 % (pcs) over 167.1; 1.68 % real | as stated | PROVED | [ALT-P-g2] | T_alt_direct_g2 |
| P5 | the measured pass: 4 × 43.7 = 174.8 µs per layer; per token dense 20.98 ms, MoE 4.89 ms, draft 4.20 ms; dense 2 383.29 ms → 0.104 (−0.9 %), MoE 138.74 → 1.801 (−3.5 %); draft 18.09 → 22.29 ms (+23.1 %); dense spec 0.262 → 0.258 | as stated | PROVED (c_q INPUT; the fixed-per-pass reading is E38's question) | [ALT-P-quant-pass] [ALT-P-quant-dense] [ALT-P-quant-moe] [ALT-P-quant-draft] | T_alt_quant_measured |
| P6 | the host-bounce counterfactual at the measured λ = 12.2 µs: 107 / 100 µs per layer (< 174.8) → 2 375.17 ms (0.105) / 136.64 ms (1.829, −2.0 %) | as stated | PROVED (λ INPUT) | [ALT-P-quant-*] | T_alt_quant_bounce_measured_lambda |
| P7 | the magic bias and the 19 / 8 µs estimate are retired as mechanisms; the arithmetic stays true (255 cases, f16 and f32) | — | SUPERSEDED (proved arithmetic) | [ALT-4-magic] | T_alt_magic_f16, T_alt_magic_f32 |
| P8 | instance gain with the pass on both sides: 138.74 → 1.801 vs 133.79 → 3.737 (+107.4 %); dense 2 383.29 → 0.104 vs 3 218.92 → 0.155 (+49.0 %); break-even 1 412 631 ns (0.7 GB/s/core; measured 7.1× inside; corrected ser passes) | **iff for every Tc** | PROVED (∀ Tc) | [ALT-P-inst-*] [ALT-P-breakeven-q] | T_instance_gain_q, T_instance_gain_q_cells |
| P9 | H10 as a hypothesis: the verdict needs η ≥ 482 ‰ (1.869 at 482, 1.865 at 481 vs 1.867); measured 995 ‰ → 3.859; 1000 ‰ → 3.878 | **iff for every η** | PROVED (∀ η; η = 995 INPUT at die scale, card scale EMPIRICAL — H10) | [ALT-P-h10] | T_instance_gain_h10, T_instance_gain_h10_cells |
| P10 | the other variants with the pass: direct path 122.88 ms → 2.034, megakernel (5 µs) 124.26 → 2.011; the MoE threshold 108 430 is invariant (the pass enters both sides) | as stated | PROVED (∀ c_sync for the invariance) | [ALT-P-variants-q] | T_alt_variants_q, T_megakernel_moe_q |
| P11 | exact fit margins: MoE 32k 40 / 24 / 24 / 40 MB, dense 32k 5 / 45 / 3 / 5 MB, MoE 1M 2 / 32 / 32 / 2 MB, dense 128k 23 / 15 / 20 / 23 MB; minimal x at +1 GB: 204 / 192 / 192 / 204 (MoE), 397 / 378 / 353 / 397 (dense) | as stated (bytes: 40 314 817 / 24 485 516; 5 862 794 / 45 211 336 / 3 346 208) | PROVED (∀ ort as the linear fit law) | [ALT-P-margin-*] | T_alt_fit_margin, T_alt_fit_dx_per_gb, T_alt_fit_overhead_moe, T_alt_fit_overhead_dense |
| P12 | two-tier at the measured c_pg: 38 ns → G 172.4 vs 174.4 (+1.1 %), steps 786 → 777 µs (32k), 24 919 → 24 632 (1M); 114 ns → 168.2 vs 174.1 (+3.5 %), 805 → 778; measured per-page basis 167.0 vs 169.1 (+1.2 %), 163.0 vs 168.8 (+3.5 %); floor facts: extent 48 044 vs 16 × 3 002 = 48 032; tenths equal for c_pg ≤ 2 | as stated | PROVED | [ALT-P-tier-floor] [ALT-P-tier-cpg*] [ALT-P-tier3-cpg*] | T_two_tier_measured, T_alt_tier_tenths, T_alt_tier_dominates, T_two_tier |
| P13 | draft-on-host share 2.2 % (54.28 of 2 416.72 ms); dense megakernel tie at 109 903 ns | as stated | PROVED | [ALT-P-draft-share] [ALT-3-dense-threshold] | T_dominated_draft_host, T_megakernel_dense, T_alt_mega_threshold_cells |

## Hypothesis variables and brackets (both endpoints proved)

| Variable | Bracket / branch | ∀-theorem | Endpoint cells |
|---|---|---|---|
| W4 core-slab time Tc (ns) | measured 197 844 (5.3 GB/s/core) … break-even 1 371 124 (0.8); sensitivity 262 144 / 349 525 (4.0 / 3.0 GB/s); corrected ser 413 184; as-written ser 305 152 | T_instance_gain (iff ∀ Tc), T_instance_gain_q (∀ Tc, with the pass), T_instance_form | T_instance_gain_measured (1 371 124 → 1.868, 1 371 125 → 1.867; 3.878 / 3.662 / 3.405 / 3.239 / 3.531), T_instance_gain_q_cells (1 412 631 / 1 412 632) |
| H10 efficiency η (‰) | 0 … 1000; measured 995 at die scale | T_instance_gain_h10 (iff ∀ η) | T_instance_gain_h10_cells (481 / 482 / 995 / 1000) |
| A-lift cost a (ns) | 0 (overlapped) … 3 285 (serialised) | T_alt_direct_bracket (∀ a ≤ 3 285) | T_alt_direct_bracket_ends (1 728 / 1 671) |
| drain rate R (tenths GB/s/core) | ≥ 1; measured 1 528 | T_alt_direct_drain (iff ∀ R > 0) | T_alt_direct_drain_cells (3 / 4 / 1 528) |
| c_sync (ns) | 0 … 108 430 (MoE) / 109 903 (dense) | T_megakernel_dense, T_megakernel_moe, T_megakernel_moe_q (iff ∀ c) | T_alt_mega_threshold_cells (boundaries), T_alt_mega_cells (0 / 2 000 / 5 000 / 20 000) |
| c_pg (ns) | 0 … 6 005; measured lower bound 38, 3× = 114 | T_alt_tier_dominates (∀ L c), T_alt_tier_le_1MiB (∀ L, c ≥ 1), T_alt_tier_below_extent (∀ L < 4096, ∀ c) | T_alt_tier_cells (0 / 100 / 500 / 2 000 / 6 005), T_alt_tier_tenths (0 / 1 / 2 / 3), T_two_tier_measured (38 / 114) |
| c_V, ρ32 | c_V ∈ ℕ at ρ32 ∈ {1, 2}; corners (7, 1), (12, 1), (33, 2) | T_alt_k8_threshold (∀ c_V), T_alt_lazy_threshold (∀ c_V), T_alt_lazy_dominates_twopass (∀ c_V, ρ ∈ {1, 2}), T_alt_lazy_dominates_S4 (∀ L G c_V ρ) | T_alt_k8_threshold_cells, T_alt_lazy_cells, T_alt_k8_steps |
| per-die overhead ort (B) | 2 GiB primary; +1 GB | T_alt_fit_overhead_moe / _dense (iff ∀ ort, ∀ x ≤ 1000), T_alt_fit_dense_1M_infeasible (∀ ort, ∀ pos) | T_alt_fit_margin, T_alt_fit_dx_per_gb |
| int4 share x (‰) | 0 … 1000 | T_alt_fit_minx_moe_32k / _dense_32k (iff ∀ x), T_alt_fit_monotone (∀ x ≤ y) | T_alt_fit_minx_cells (x and x − 1 on every table position) |
| bounce latency λ (ns) | 91 000 carried; 12 200 measured | T_dominated_expert_parallel (∀ λ > 0), T_dominated_p2p (∀ replacement cost x) | T_alt_quant_fallback_written (91 µs), T_alt_quant_bounce_measured_lambda (12.2 µs) |
| prefix length L_s | 0 … L; B = 16 and B = 1 | T_alt_prefix_iff (iff ∀ L_s ≤ 32 768) | T_alt_prefix_cells (4k / 16k / 28k) |
| popularity family | uniform / Zipf(1.0) (EMPIRICAL — H9) | — (exact scaled-natural arithmetic for Zipf) | T_alt_zipf_share, T_alt_rep_zipf, T_alt_hotcold_loses |

## Coverage

**32 / 32 ledger rows covered** (all PROVED on the integer model; 8 carry a CORRECTED statement, 1 is SUPERSEDED
as a mechanism, 1 contains a DEFINITION clause); **13 / 13 re-derived rows proved**; **0 orphans** (every number in
the corrected ALTERNATIVES.md text is printed by an alt.py label — the original 135 label lines byte-identical to
dd5f84c plus the 31 `[ALT-P-*]` lines); **0 uncited labels** in the ledger (`[ALT-2-mindies]` → row 6,
`[ALT-4-route1b]` → row 21, `[ALT-9-tokendrop]` / `[ALT-9-specialization]` / `[ALT-9-p2p]` → row 31).

EMPIRICAL rows (no theorem claims them; the theorems take them as hypotheses or branches): H9 (the popularity
family), H10 at card scale (η; measured 995 ‰ at die scale), H11 (the overhead `ort`), H12 (L_s), E29 (ser vs ovl
A lift — the `a` bracket), E30 (the cold-chain regime — the Tc bracket; the corrected ser branch), E31/E32
(c_sync, the watchdog), E33 (fusing the measured pass; the 19 / 8 µs estimate is retired), E34 (c_pg per size;
38 ns is a lower bound), E35/E36 (lazy rescale and K-int8 numerics), E37 (the rows cliff), E38 (fixed vs
proportional reading of the 43.7 µs pass — `quantTok` uses the fixed reading). ASSUMPTIONS carried explicitly:
the 2 GiB overhead (`oRt`), the 91 µs λ of the round-2 model (`lamMid`; the measured 12.2 µs is `lamMeas`), the
round-2 attention constants (merge 7 000, R_drain 10 GB/s, native exp 4 lane-ops, stream G = 174.6 — the D3/D4
models ALTERNATIVES is anchored to; DESIGN-3/4 round 3 re-ground them), the quantizer op count 8 (retired).

**Not proved, by design:** e⁸ = 2 981 (row 30's μ is a definition); the "head-aligned slice" property of row 18
(a layout statement); that the measured 43.7 µs is a fixed per-pass cost at other K and row counts (E38); the
two-card inheritance of H10. **What the round changed in the verdicts:** nothing load-bearing reversed —
T_instance_gain survives the measured premise with a 6.9× (time) / 3.3× (corrected serial chain) margin and
+107.4 % with the pass on both sides; the dense *serial-branch* cell of replication flips from +16.1 % to −4.7 %
(the ovl branch, +48.5 % / +49.0 %, stands); the two-tier page scheme "dominates" only in the restated sense and
buys 1.1 % at the measured c_pg; the quantizer rows become a 0.9 % / 3.5 % cost on every cell instead of a
0.1 % / 0.2 % fusion or a −2.8 % / −13.2 % fallback.


## PROMPT-6 audit (2026-11-08) — the cells errata #18–#31 move in ALTERNATIVES.md

`[PA-*]` labels are printed by `python3 -I proof/alt.py` after the `[ALT-P-*]` block (the first 166 output lines are byte-identical);
theorems `T6a_*` (7) close `proof/alt.lean` (namespace `Audit6A`; 111 theorems in all; standalone and `lake build` clean; 0 axioms /
sorry / native_decide — `#print axioms`: 5 depend on no axiom, the 2 `_gain` theorems on `propext` + `Classical.choice` + `Quot.sound` via
T_instance_gain). Cell theorems are generated from alt.py's own values (scratch `gen_alt6.py`). The per-design tables are ERRATA-IMPACT.md.

| # | Claim (ALTERNATIVES PROMPT-6 banner and marks) | Proof | labels | Status |
|---|---|---|---|---|
| PA5-1 | erratum #19 on the cold tier: fresh chunks + the vector f32 K-sum add 512 × 512 f32 lanes × 1.37 / 43.2 = 8 313 ns (throughput) / 512 × 63.7 = 32 614 ns (chained) per core-slab; the overlapped slab 197 844 → 206 157 / 230 458 ns; the serial piece 807 → 836 / 883 ns (+ 13 ns drain + 16 / 63 ns add) | T6a_cold_merge_T, T6a_cold_merge_C | [PA-cold-merge] | PROVED (the merge pattern: INPUT #19; the conventions: DESIGN-3's T / C) |
| PA5-2 | the instance cells with the merge: MoE 32k 3.878 → **3.849** / 3.766 (+106.1 / +101.7 %), Zipf(1.0) 4.190 → 4.184 / 4.166, dense 32k 0.156 → **0.153** / 0.144 (W8-eq 81.3 / 72.7); serial branch MoE 3.239 → 3.202 / 3.145, dense 0.100 → 0.098 / 0.094 (−6.6 / −10.4 %); break-even margin 6.9× → **6.6× / 5.9×** (serial 3.3× → 3.2× / 3.0×); T_instance_gain holds at both merged slabs | T6a_cold_merge_T / _C, T6a_cold_merge_zipf_T / _C, T6a_cold_merge_gain_T / _C (via T_instance_gain, ∀ Tc) | [PA-inst-T] [PA-inst-C] [PA-inst-ser-*] | PROVED; CORRECTION of rows 1, 8–11 and `[ALT-P-ser-*]`'s instantiation (the iff itself is untouched) |
| PA5-3 | erratum #29 on the megakernel: the primary reading is c_sync = 20 µs (one crossing per flag round) — the single megakernel MoE 2.058 (+10.2 %) / dense 0.107 (+1.9 %) (already T_alt_mega_cells); ALT-3+1 2.415 → **2.367**, ALT-2+3 MoE 4.369 → **4.291**, dense 0.158 unchanged; 108 430 / 109 902 ns are 5.4× above 20 µs | T6a_mega_20us, T_alt_mega_cells | [PA-mega-combos-*] [PA-mega-20us] | PROVED; CORRECTION of rows 16–18's primary branch (the iffs untouched); c_sync: EMPIRICAL — E31 (with vector work in flight) |
| PA5-4 | the placements without a number: the lazy-rescale cells `[ALT-8-*]` VOID as specified (#19 / #29 / #31); the quantizer's Muls (#22) and A-slot extraction (#20) struck; the megakernel's checksum compare (#31), slice-only norm / absmax (a dataflow gap), q bounce (#20), 16 KiB x staging (#25), bounded polls (#26), nest resets (#30 / #18 / #28); E30's oracle (#19), scales (#22) and patterns (#21); the B-slot US → S1 route (#20's sibling, unproven); corrected #3 (hygiene) | — | — | DEFINITION / VOID status (no cell; ERRATA-IMPACT.md) |

**Coverage, PROMPT-6:** 4 / 4 rows resolved; every `T6a_*` theorem of alt.lean is cited (PA5-1 … PA5-3); **0 orphans**. The proof-round
rows above are unchanged; rows 1, 8–11 and 16–18 keep their theorems (true of the as-written model) and gain the PROMPT-6 instantiation.
