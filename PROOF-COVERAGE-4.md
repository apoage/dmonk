# PROOF-COVERAGE-4 — ledger of every quantitative claim in DESIGN-4.md

How to read a row: **Claim** quotes or paraphrases the DESIGN-4.md statement (section numbers refer to the
corrected document); **Proof** names the theorem(s) in `proof/fleet.lean` that fix the number; **fleet.py** names
the label in `proof/fleet.py` that prints it; **Status** is one of PROVED (follows arithmetically from the
constants table; "∀ x" marks a universally quantified result over the unmeasured or assumed quantity x — both
bracket endpoints are then proved as well), INPUT (a HW-MAP measurement or erratum used as given), D2 (a
DESIGN-2 theorem used as an input), DEFINITION (true by construction of the cost model or a structural choice
with no number in it), EMPIRICAL — Hx (settled only by the named host experiment of DESIGN-4.md §8, or by
PROBLEM-3's E-gather / E-exp; no theorem claims it), or ASSUMPTION — Hx (explicitly labelled A in the design and
carried as a hypothesis variable of the theorems that use it: "PROVED given the assumption").

Units in the proof file: bytes (KiB/MiB/GiB binary, GB decimal); rates in tenths of GB/s (1746 = 174.6);
time in ns (floored), quoted µs round-half-up (`usR`) or hundredths of ms floored (`ms2`, the convention of the
§3.2 table); tokens and tokens/s in thousandths (`tpsCard tok T = tok·10⁹/(4·T)`); percentages in tenths
(`pct`) or hundredths (`pctH`); ratios in tenths, floored (`x10`, the convention behind "7.7×", "2.4×");
acceptance α and τ(α, k) in thousandths; the host-bounce latency λ, the runtime overhead `ort`, the A-fraction
penalty `pen` (tenths of a percent) and the KV read rate G are explicit arguments of the model.

## Build status

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (`leanprover/lean4:v4.35.0` in `proof/lean-toolchain`, elan), Lake 5.0.0 |
| `lean proof/fleet.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 7 s (no imports beyond Init; Mathlib/Batteries not used) |
| `cd proof && lake build` | **succeeds** (targets `Model`, `Smoke`, `Moe`, `Fleet` = fleet.lean, added to `lakefile.toml`) |
| Theorems in fleet.lean | **124** (`grep -c '^theorem'`), of which 5 are the load-bearing umbrellas under PROMPT-4P's names: `T_mem_feas_dense_1M`, `T_min_dies`, `T_spec_moe_loss`, `T_pipelining`, `T_whatif` (plus `T_mem_feas_dense_4k`, `T_mem_feas_kv_int8`, `T_Lmax`, `T_serial`, `T_spec_dense` under their own names) |
| Theorems after the round-3 proof session (2026-11-07) | **292** = these 124 + 168 round-3 theorems (`T3r_*`); see the round-3 proof section at the end — `lean proof/fleet.lean` and `lake build` succeed, 0 axioms / sorry / native_decide |
| Theorems after round 5 (2026-11-07, PROMPT-3R5) | **310** = 292 + 18 round-5 theorems (`T5r_*`: the measured attention kernel in the planner); see the round-5 section at the end — standalone and `lake build` clean, 0 axioms / sorry / native_decide |
| `axiom` / `sorry` / `native_decide` declared or used | 0 / 0 / 0; 94 theorems depend on no axiom at all, 30 (the `omega` / `simp` / `Nat.div_le_div_left` proofs and the umbrellas built on them) on the standard `propext` / `Quot.sound` / `Classical.choice` that core tactics emit (`#print axioms` over every theorem) |
| `decide +kernel` | 10 (the 256-order exchange theorems, the 1001-case α thresholds, τ < 4 ∀ α — the elaborator's recursion limit, not the kernel's, is what they exceed) |
| Leaf closers used | `decide`, `omega`, `rfl`, `simp` / `simp only` with core lemmas (`List.sum_cons`, `Nat.add_mul`, `Nat.succ_mul`, `Nat.mul_one`, `Nat.div_one`), `exact` / `apply` of core lemmas (`Nat.le_div_iff_mul_le`, `Nat.div_lt_iff_lt_mul`, `Nat.div_le_iff_le_mul_add_pred`, `Nat.div_le_div_left`, `Nat.div_le_div_right`, `Nat.mul_le_mul_left`, `Nat.le_add_right`, `Nat.add_le_add`, `Nat.le_max_left/right`, `Nat.zero_le`); structure: `unfold`, `rw`, `intro`, `constructor`, `refine`, `induction` |
| `python3 -I proof/fleet.py` | runs on Python ≥ 3.8, no dependencies; every number in the text has a label; the labels that moved in round 2 are `[F9-*-lambda]`, `[F7-*-identity]`, `[F5-*-tsplit]`, `[F5-*-pipe-balance]`, `[F6-moe-*-t4]`, `[F6-moe-mechanism]`, `[F6-dense-breakeven]`, `[F2-order]`, `[F2-order-classes]`, `[F1-ort-threshold]`, `[F1-*-min-dies]`, `[F0-moe-experts]`, `[F8-H7]`, `[F9-mem]`, `[F9-launch-fuse]` — no previously printed number changed |
| Measured namespace | 20 plain definitions, each with the HW-MAP row it comes from, plus the two DESIGN-2 kernel inputs (`tSlabSer` = moe.lean `T_piece_expert`, `tSlabPP` from moe.lean `T1_pp`) and the DESIGN-2 generator means; none states a DESIGN-4.md conclusion |

## Corrections forced by formalization (round 1 → round 2)

| # | Where | Round 1 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §2.2 T8, §4.2, §9, row 14 | "the bounce reaches a fraction x of the step iff λ ≥ (x·T_step − Σbw)/16: 10 % needs λ ≥ 14.8 ms (dense) / 835 µs (MoE); 50 % needs 73.8 ms / 4.18 ms" | the step itself contains the 16 λ: λ ≥ (x·T_rest − (1−x)·Σbw)/(16(1−x)) — **16.4 ms / 918 µs for 10 %, 147.5 ms / 8.27 ms for 50 %**, as an iff over every λ; at the quoted 4.18 ms the MoE bounce is 33.6 % of the step, at 835 µs 9.2 % | T_bounce_threshold_dense, T_bounce_threshold_moe, T_bounce_round1 |
| 2 | §7 scaling arithmetic, row 34 | "4 × (stage-1 step) + 12λ + T_head = 2362.8 ms against the direct 2362.31; the 0.5 ms residual is the chain ends counted four times" | 4 × stage-1 already carries 12 of the 16 latencies; the exact identity is **4 × stage-1 + T_head + 2·T_launch + 4λ + (3 hops at 13.9 − 1 at 27.3 + logits) = 2362.32 ms** (dense) and 133.85 (MoE), no residual; T_step = Σ blocks + λ | T_rollout_identity, T_pipelining_decomposition |
| 3 | §8 H8, §9 | "overhead > 3.85 GiB → the dense 1M KV-int8 layout no longer fits" | it fits iff the per-die overhead ≤ 3 804 224 512 B = **3.80 GB = 3.54 GiB** (2.147 GB + the 1.657 GB margin; "3.85" added GB to GiB) | T_mem_feas_kv_int8 (∀ overhead), T_mem_feas_kv_int8_cells |
| 4 | §6.3 T12, §9, row 33 | "break-even τ ≥ 3.258, i.e. α ≥ 0.87; Zipf(1.5): τ ≥ 2.332, α ≥ 0.65" | exact criterion τ·T₁ ≥ 1000·T₄: uniform **α ≥ 0.865** (0.864 loses at 1.865, 0.865 gains at 1.868), Zipf(1.5) **α ≥ 0.647** (0.646 ties at 1.867 in thousandths while losing by 0.01 % exactly), Zipf(1.0) α ≥ 0.747 (new row); proved in both directions for every α ≤ 1 | T_spec_moe_loss_exact, T_spec_moe_loss_tps, T_spec_moe_tie |
| 5 | §6.3 table, T12, §9 | dense spec gain "2.4×" (also 1.8× / 3.3×) | the ratio τ·T₁/T₄ is **2.475×** (1.832× / 3.361×); "2.4" was the floored tenths of a ratio of two floored tokens/s cells; the gain holds for every α ≥ 0.024 | T_spec_dense, T_spec_dense_all_alpha, T_spec_dense_breakeven |
| 6 | §1.1, §2.2 T7, row 12 | "Σbw is the same for every chain order; the only order-dependent terms are the logits source and the id sink; the chosen order is optimal by 8 µs and otherwise free" | the first die receives no activation and the last sends none, so the hop sum is 4·(h₀+h₁+g₀+g₁) − h(first) − g(last): four classes **41 107 / 42 277 / 48 792 / 49 962 ns** by (first, last) die type; the chosen (d1, d0) order is the minimum by 1.2 µs over (d0, d0) and 7.7–8.9 µs over the d1-last orders — proved over all 70 orders | T_order_formula, T_order_optimal, T_order_d1_d0 … T_order_d0_d1, T_order_chosen |
| 7 | §1.1, §5 | MoE 4/3-layer imbalance "costs 12.5 % at Π = 8" | with lm_head and the bounce halves in the blocks the loss against a balanced 8-way split of the same work is **10.3 %** (max block 18.64 ms vs 16.72 mean; 53.657 vs 59.810 fleet tokens/s); 12.5 % is the pure 4-vs-3.5 figure | T_pipelining_balance |
| 8 | §2.3, §10 | Π = 8 trunk share "8 × 128 KiB per 18.6 ms block (MoE) = 0.2 %" | the logits card carries 537 600 B per bounce: **0.84 %** of the trunk (dense 0.06 %) — still no queueing | T_pipelining_trunk |
| 9 | §5, row 28 | "398.52 ms = 273.85 + 11.53 + 65.70 + 45.93" (sums to 397.01); "43.02 = 11.61 + 2.69 + 18.01 + 10.32" | the decomposition omitted the lm_head/8 term: **+ 1.50 ms** (dense) / **+ 0.37 ms** (MoE); the totals and the 5.9× / 3.1× were right | T_tsplit |
| 10 | §0, §10 | "no other unknown moves any cell by more than 1.3×" | true at 32k (largest 1.32×, the G branch on MoE); at 1M the G branch moves the MoE cell **2.7×** (0.312 → 0.114, already in §9) | T_single_measurement, T_fallbacks |
| 11 | §1.2 | "the 12.0 GB of expert slabs per layer" | 256 × 3 × 4096² = 12 GiB = **12.9 GB** | T0_expert_slabs_units |
| 12 | §1.3 | "the new token's K/V (8 KiB per layer at t = 1)" | kv_tok = 2 × 8 × 128 × 2 B = **4 KiB** per token-layer (K and V together; 16 per-core streams of 256 B) | T0_kv_write |
| 13 | §2.3 | "per token (dense r=1) 98 KiB, 128 KiB, 128 KiB and 597 KiB" | 98 308 B = **96 KiB** (98.3 KB) | T_trunk_bytes |
| 14 | §9 | "keep f16 K and int8 V (386.4 GB of KV …)" | 120 × 3072 B × 2²⁰ = **386.5 GB** (short by 104.1) | T_mem_room |
| 15 | §9 | "6 → 4 launches per dense layer saves 21.9 ms per token" | 240 × 91 µs = **21.84 ms** | T_fallbacks |
| 16 | row 39 | "3.1 % vs 1.5 % → ≤ 0.4 % per layer, not modelled" | 27.4 % of the layer's bytes × 1.6 % = **0.44 %**; now modelled as the explicit hypothesis `pen` ≤ 0.5 % on every dense cell; the headline 0.105 survives any penalty ≤ 0.8 % and breaks at 0.9 % (0.104); spec 0.262 → 0.260 at 0.5 % | T_afrac_size, T_afrac_headline, T_afrac_edge, T_serial_dense_afrac |
| 17 | §9 | host-paged KV prefix "0.048 tokens/s/card" | 0.0479: 0.048 rounded, 0.047 under the floor convention of every other tokens/s cell | T_fallbacks |
| 18 | fleet.py (no text change) | `[F8-H7]` printed "3 s" (integer division) for a 3.50 s load | 3.5 s (2.3 s if both links of a card were independent, H2) | T_ladder_rest |

Not corrections but tightenings found while proving: (a) under layer-split the compute time is the same for
every partition list of the 120 layers (T_serial_partition), and tokens/s ≤ R_gemm/bytes holds for any extra
cost (T_ceiling: 0.453 fleet-wide in floored thousandths, "0.454" is the rounded real ratio); (b) the dense
0.105 cell holds for every λ in the 10–500 µs bracket, not only at its three points (T_step_lambda_bracket);
(c) the KV-int8 fit depends on the overhead monotonically, so H8 can only shrink L_max (T_Lmax_monotone);
(d) the spec-decode verify batch on dense is a gain for every α ≥ 0.024 (T_spec_dense_all_alpha); (e) the
MoE loss has a draft-independent floor: T₄ ≥ 4·E₁ + (T₁ − E₁) makes every τ < 2.852 a loss (T_spec_moe_mechanism).

**Load-bearing verdicts.** `T_min_dies` survives formalization unchanged and in a stronger form than round 1
stated it: 4 dies cannot hold either shape under ANY assignment of layers to dies (some die carries ≥ 30 dense /
≥ 7 MoE layers = 95.6 / 90.5 GB of int8 before KV or overhead; the totals 386.7 / 363.0 GB exceed 4 × 86 = 344),
with full int8 residency as the hypothesis (the host-streaming escape is costed and rejected in §9); 5 dies hold
both at 4k (24 / 6 layers per die; dense L_max 52 693 on 5 dies). `T_spec_moe_loss` survives unchanged in
substance — the verify batch multiplies the active-expert bytes (D(4) = 4·D(1)), 1.451 < 1.867 at α = 0.7, a
loss for every α ≤ 0.864 under uniform routing — with its threshold sharpened from "α ≥ 0.87" to α ≥ 0.865
(and Zipf(1.5) from "0.65" to 0.647, both directions proved for every α).

## The 39-row ledger (DESIGN-4.md Appendix A)

| # | Claim | Proof | fleet.py | Status |
|---|---|---|---|---|
| 1 | dense resident int8 = 120 · 3 187 671 040 + 2 · 2 101 346 304 = 386 723 217 408 B = 386.7 GB (int4 source 193.3); streamed per token 384.6 GB | T0_dense_bytes | [F0-dense] | PROVED |
| 2 | MoE resident int8 = 28 · 12 926 844 928 + 2 · 525 336 576 = 363 002 331 136 B = 363.0 GB (181.5); 12 GiB = 12.9 GB of expert slabs per layer; streamed per token 12.9 GB | T0_moe_bytes, T0_expert_slabs_units | [F0-moe] [F0-moe-experts] | PROVED |
| 3 | KV per token 491 520 B (dense) / 114 688 (MoE); at 2²⁰ tokens 515.3 / 120.2 GB; kv_tok = 4 KiB; fleet 688 GB | T0_kv, T0_kv_write | [F0-kv1M] | PROVED |
| 4 | per-die totals at 4k: dense 52.3 / 51.4 / 50.2 / 52.3 GB, MoE 54.5 / 41.0 / 53.9 / 42.7 — all ≤ 86 GB (weights 49.9 / 49.0 / 47.8; 52.2 / 38.7 / 51.7 / 40.5; ws + rt 2.2) | T_mem_feas_dense_4k, T_mem_feas_moe_4k | [F10-mem-dense-4k] [F10-mem-moe-4k] | PROVED given ASSUMPTION — H8 (2 GiB overhead, 64 MiB workspace) |
| 5 | dense 1M f16 KV: every die 114.4–116.5 GB > 86, for every overhead ≥ 0; under ANY 8-way partition the fleet's KV room 282.3 GB < 515.4 (short by 233.0) | T_mem_infeas_dense_1M (∀ ort), T_mem_infeas_dense_1M_cells, T_mem_infeas_1M_any_partition (∀ w, kv), T_mem_room, T_mem_feas_dense_1M | [F10-mem-dense-1M] [F9-mem] | PROVED (∀ overhead, ∀ partition) |
| 6 | dense 1M KV-int8: 84.3 / 83.4 / 82.2 / 84.3 GB, feasible iff overhead ≤ 3 804 224 512 B = 3.80 GB = 3.54 GiB; margin 1 656 740 864 B = 1.66 GB at 2 GiB; embedding to host → 82.2, lm_head die stays 84.3 | T_mem_feas_kv_int8 (∀ ort, iff), T_mem_feas_kv_int8_cells, T_mem_embed_to_host | [F10-mem-dense-1M KV-i8] [F1-dense-1M-kvi8] [F1-ort-threshold] | PROVED ∀ overhead (the razor-thin fit is the H8 hypothesis ort ≤ 3.80 GB: ASSUMPTION — H8) |
| 7 | MoE 1M f16: 71.6 / 53.8 / 71.1 / 55.6 GB; KV 17.1 / 12.8 | T_mem_feas_moe_1M | [F10-mem-moe-1M] | PROVED given ASSUMPTION — H8 |
| 8 | L_max = min_pos ⌊room/(n_pos·kv_tok·B)⌋: dense 551 253 / 137 813 / 34 453 (B = 1/4/16), KV-i8 1 102 506, B = 8: 68 906; MoE 1 925 823 / 481 455 / 120 363; binding position 0 (embedding) for both; the draft die is not binding (draft-free L_max = 551 253) | T_Lmax, T_Lmax_binding_pos, T_Lmax_formula | [F1-dense-Lmax] [F1-moe-Lmax] [F1-dense-draftfree] | PROVED given ASSUMPTION — H8 |
| 9 | ΔL_max per GB of overhead = 16 276 (dense) / 61 035 (MoE); L_max monotone in the overhead | T_Lmax_dOverhead, T_Lmax_monotone (∀ a ≤ b) | [F1-dLmax] | PROVED (direction: EMPIRICAL — H8/H5 decide the overhead) |
| 10 | minimum dies = 5: 4 dies infeasible for ANY layer assignment (≥ 30 / 7 layers on some die = 95.6 / 90.5 GB; totals > 344 GB); 5 dies fit at 4k (dense 24/die: 81.2 GB worst, 82.4 on the lm_head + draft die, L_max 52 693 ≈ 53k; MoE 6/6/6/5/5: 80.4 / 81.6); the fleet.py uniform-share heuristic agrees | T_min_dies, T_min_dies_dense_4, T_min_dies_moe_4 (∀ n₀..n₃), T_min_dies_4_total, T_min_dies_5_dense, T_min_dies_5_moe, T_min_dies_heuristic | [F1-dense-min-dies] [F1-moe-min-dies] [F1-*-Lmax] | PROVED (∀ assignment) under the stated hypothesis of full int8 residency (errata #12; the host-streaming escape is rejected in §9) |
| 11 | Σbw per token: hops 2.9 / 3.6 µs (r = 1), 11.6 / 14.2 (r = 4), MoE 0.7 / 0.9; logits 18.8 / 75.2 µs; totals 41 107 / 164 443 / 657 799 ns (dense r = 1/4/16), 24 367 / 97 484 / 389 951 (MoE); 16 latencies | T_bw_hops, T_bw_sum | [F2-*-rows*] | PROVED |
| 12 | hop sum = 4·(h₀+h₁+g₀+g₁) − h(first) − g(last) for every order with four dies of each kind; classes 41 107 / 42 277 / 48 792 / 49 962 ns; the chosen order (mask 0b01010101) is the minimum; logits source 18.8 vs 27.0 µs | T_order_formula, T_order_optimal, T_order_d1_d0, T_order_d0_d0, T_order_d1_d1, T_order_d0_d1, T_order_chosen (all 256 masks) | [F2-order] [F2-order-classes] | PROVED (∀ 70 orders) |
| 13 | T_x(λ) = Σbw + 16λ: dense 201 / 1 497 / 8 041 µs at λ = 10 / 91 / 500 µs (r = 1), 324 / 1 620 / 8 164 (r = 4); MoE 184 / 1 480 / 8 024, 257 / 1 553 / 8 097; between the endpoints for every λ in the bracket | T_Tx_cells, T_Tx_bracket (∀ λ) | [F2-*-rows1] [F2-*-rows4] | PROVED ∀ λ; the value of λ: ASSUMPTION — H1/H3 (91 µs primary) |
| 14 | bounce ≥ 10 % of the 32k step iff λ ≥ 16 392 030 ns (dense) / 917 693 (MoE); ≥ 50 % iff λ ≥ 147 548 816 / 8 271 412; the round-1 figures (14 762 / 835 µs; 73 820 / 4 181) give 9.1 / 9.2 % and 33.3 / 33.6 % | T_bounce_threshold_dense, T_bounce_threshold_moe (∀ λ, iff both ways), T_bounce_round1, T_step_lambda_form | [F9-dense-lambda] [F9-moe-lambda] | PROVED (∀ λ) — corrected |
| 15 | per-card trunk bytes per token (dense r = 1): 98 308 (= 96 KiB) / 131 072 / 131 072 / 611 328; MoE 24 580 … 537 600; utilisation at Π = 1 < 0.02 % (dense 0.001 %, MoE 0.015 %); budget 27.6 GB/s × T_step = 65 / 3.7 GB | T_trunk_bytes, T_trunk_util | [F2-dense-rows1] [F2-moe-rows1] | PROVED |
| 16 | queueing bound behind a bulk chunk on the 13.9 GB/s link: 64 KiB → 4 714 ns (5 µs), 1 MiB → 75 437 (75 µs), 16 MiB → 1 206 993 (1 207 µs = 1.2 ms) | T_queue | [F8-H3] | PROVED (the realised wait: EMPIRICAL — H3) |
| 17 | per-layer times: dense GEMM 18 256 993 ns; MoE 240 223 + 2 967 496 (serial) / 2 344 360 (pp) = 3 207 719 / 2 584 583; heads 12 035 202 / 3 008 800; launches 546 000 / 637 000 per layer, 65.70 / 18.01 ms per token (722 / 198 launches); W = 2 202 874 362 / 92 824 932 ns; T_slab,pp = 97 015 = (784 118 − 8 000)/8 rounded | T_layer, T_W, T0_kv | [F3-dense-layer] [F3-moe-layer] | PROVED from INPUT (R_gemm M) and D2 (T_slab: moe.lean T_piece_expert, T1_pp; F = 8 µs: DESIGN-2 ASSUMPTION E14/E15; regime: EMPIRICAL — DESIGN-2 E13) |
| 18 | attention per layer: every cell of the §3.1 table (KV 96 089 … 24 598 896 stream, ×3 gather3x; softmax native/poly; MMA 7 680 … 1 966 080); softmax/MMA 6.3 / 8.0 % of the KV stream; KV/T_gemm 4.2 % dense, 24.0 % MoE at 32k; KV monotone between the endpoints for every G in 582..1746, softmax linear for every c_E in 4..16 | T_attn_dense, T_attn_moe, T_attn_shares, T_attn_G_bracket (∀ G), T_attn_cE_bracket (∀ c_E) | [F3-*-attn] | PROVED ∀ G, c_E; which branch holds: EMPIRICAL — PROBLEM-3 E-gather / E-exp |
| 19 | §3.2 table, all 26 rows: T_step, W, KV, launch, bounce, draft (hundredths of ms), tokens/step, tokens/s/card, feasibility; e.g. dense 32k 2362.31 → 0.105, spec 2416.71 → 0.262, B = 16 3746.62 → 1.067; MoE 32k 133.84 → 1.867, 436.12 → 1.451, 1696.70 → 2.357; dense 1M f16 MEM, KV-i8 3746.00 → 0.066; MoE 1M 801.09 → 0.312 | T_step_dense_4k, T_step_dense_32k, T_step_dense_128k, T_step_dense_1M, T_step_moe_4k, T_step_moe_32k, T_step_moe_128k, T_step_moe_1M, T_draft | [F3] | PROVED (primary branch: λ = 91 µs ASSUMPTION — H3; G/c_E EMPIRICAL — PROBLEM-3; launches serialised EMPIRICAL — H6; MoE serial regime EMPIRICAL — DESIGN-2 E13; A-fraction pen = 0, see row 39) |
| 20 | §3.3 branches at 32k: dense gather3x 2546.81 → 0.098, poly 0.105, λ 10/500 µs 2361.02 / 2368.86 → 0.105, launches pipelined 2296.61 → 0.108, pessimistic 2553.35 → 0.097, optimistic 2295.32 → 0.108 (−8 % / +3 %); MoE 176.89 → 1.413, 132.55 → 1.886, 140.39 → 1.780, 115.82 → 2.158, pp 116.39 → 2.147 (−13 %), Zipf 1.867, pessimistic 183.43 → 1.362, optimistic 97.08 → 2.575 (−27 % / +38 %); dense 0.105 and MoE 1.780–1.886 for EVERY λ in 10–500 µs | T_branches_dense, T_branches_moe, T_step_lambda_form, T_step_lambda_bracket (∀ λ) | [F3b-*] | PROVED (∀ λ; branch endpoints) |
| 21 | MoE B = 16 by family at 32k: uniform D = 128 → 1696.70 ms, 2.357; Zipf(1.0) D = 68 → 1076.88, 3.714; Zipf(1.5) D = 45 → 839.29, 4.765; at 1M MEM | T_moe_families | [F3c-*] | PROVED (D(16): EMPIRICAL — DESIGN-2 generator / H9) |
| 22 | L*_KV: dense 778 240 (= W_layer/4096 exactly), 194 560, 48 640; gather3x 259 414 / 64 854 / 16 214; KV-i8 1 556 480 / 518 827; MoE 136 736 / 34 184 / 8 546, pp 110 173; gather3x 45 579 / 11 395 / 2 849, pp 36 725; 128k is 4.1 % under 136 736; KV ≥ GEMM ⟺ L ≥ L* on the exact per-layer model for every L | T_Lstar_kv, T_Lstar_iff (∀ L), T_Lstar_iff_moe (∀ L) | [F4-*-Lkv-*] | PROVED |
| 23 | t* = ⌈kv_tok·3456/(G·H_q·c_E)⌉: dense 16 / 4 (native / poly), gather3x 48 / 12, KV-i8 8 / 2; MoE 64 / 16, gather3x 191 / 48; the exact-rate iff for every t; in the floored model at 32k t = 16 binds and 15 does not, poly t = 4 binds (776 722 vs 768 715, +1.0 %) and 3 does not | T_tstar, T_tstar_iff (∀ t), T_tstar_model | [F4-*-tsm-*] | PROVED |
| 24 | MMA share of the KV time at 32k: dense 8.0 / 32.0 / 127.9 % (t = 1/4/16, fragments 1/4/16; t = 16 is MMA-bound), MoE 8.0 / 8.0 / 32.0 (1/1/4) | T_mma_share | [F4-*-mma-*] | PROVED |
| 25 | regime map, all 24 cells: binding term (W everywhere except MoE 1M = KV, MEM where infeasible) and share: dense 96.5 / 94.3 / 89.7, 93.3 / 91.2 / 58.8 (KV 39 %), 83.5 / 81.8 / MEM, MEM → 58.8 with KV-i8; MoE 80.7 (launch 15.7) / 81.7 / 95.5, 69.4 (KV 16, launch 13.5) / 78.1 / 78.5 (KV 20), 46.8 (KV 43.4) / 68.1 / MEM, KV 86.0 / 62.4 / MEM; bounce ≤ 1.1 %, launch 2.8 / 13.5 % | T_regime_dense, T_regime_moe, T_regime_shares | [F4-regime] | PROVED |
| 26 | layer-split ceiling: Σ_pos n_pos·T = n_L·T for ANY partition list; tokens/s ≤ R_gemm/bytes for ANY extra cost: dense ≤ 0.453 fleet-wide (0.113/card), MoE ≤ 13.457 (3.364); the predictions are 92.9 % / 55.5 % of the ceilings; the fleet streams one die's rate (0.423 fleet = 0.105 × 4) | T_serial_partition (∀ list), T_serial_partition_120, T_ceiling (∀ extra), T_serial | [F10-headline] | PROVED (∀ partition, ∀ extra); the "+2 % at 2 dies" measurement is INPUT |
| 27 | P2P at any rate: saving ≤ T_x for any replacement cost x: 1 497 µs < 1.5 ms = 0.06 % of the dense step; 1 480 µs = 1.1 % MoE; over the λ bracket T_x ≤ 8.04 ms | T_p2p_bound (∀ x), T_whatif, T_Tx_bracket | [F5-*-p2p] | PROVED (∀ x, ∀ λ) |
| 28 | tensor-split: dense 398.52 ms = 273.85 + 11.53 + 1.50 (lm_head/8) + 65.70 + 45.93 → 0.627 (5.9×); λ = 10 µs 359.64; pipelined 332.82; per reduction 191 µs; MoE 43.02 = 11.61 + 2.69 + 0.37 + 18.01 + 10.32 → 5.810 (3.1×), launch 42 %; 33.95 / 25.00; 184 µs; with P2P (50 GB/s, 10 µs): 20 / 13 µs per reduction, 357.50 → 0.699 (6.6×), 33.41 → 7.482 (4.0×), launch 54 % | T_tsplit, T_tsplit_p2p, T_regime_shares | [F5-*-tsplit] [F5-*-tsplit-p2p] | PROVED under the stated premises (8-way concurrent streaming + 2 host all-reduces per layer: a what-if, the runtime faults today — INPUT errata #11) |
| 29 | Π = 8: dense blocks 293.67 / 293.76 / 293.76 … 305.99 ms, max 305 994 801 ns, Σ = 2 362 228 269 = T_step − λ, 1/max = 3.268 fleet = 0.817/card = 7.7×; MoE 18.55 / 14.02 / 18.64 … 17.23, max 18 636 756, Σ = 133 756 319, 53.657 fleet = 13.414/card = 7.1×; speed-up ≤ 8 + λ/max (< 8.003); MoE imbalance 10.3 % against a balanced split (ideal 59.810); trunk at Π = 8: 0.06 % / 0.84 %; B = 8 contexts at 32k fit (L_max(8) = 68 906) | T_pipelining, T_pipelining_blocks, T_pipelining_decomposition, T_pipelining_bound (via sumPos_le_maxOver), T_pipelining_balance, T_pipelining_trunk, T_pipelining_memory | [F5-*-pipe] [F5-*-pipe-balance] | PROVED under the premise Π = 8 (whether the runtime pipelines: EMPIRICAL — H4) |
| 30 | D2D 10.7 → 50 GB/s: per-token cross-die traffic 0 B (the step has no D2D term); a re-partition move of one die's KV at 128k: dense 8.0 GB 753 → 161 ms, MoE 2.1 GB 201 → 43 ms | T_d2d, T_whatif | [F5-*-d2d] | PROVED (the 0 B is DEFINITION: KV is die-local, errata #11) |
| 31 | draft token: 5 727 + 1 153 + 11 011 + 19 + 182 µs = 18 092 241 ns = 18.1 ms (7.1 pipelined), 61 % launch-bound; verify step k = 3: 54.28 ms (fleet.py `ms2` 54.27) / 21.24 pipelined; a 0.5 GB draft saves 2.9 ms, a 12-layer draft 5.5 ms; Π = 8 contention 6.9 ms per draft token; full-context draft KV 49 152 B/token = 10 % of the main model's, 51.5 GB at 1M | T_draft | [F6-draft] [F6-contention] | PROVED (launch floor INPUT; pipelining EMPIRICAL — H6; λ ASSUMPTION — H3; the 4k window is a model-quality choice: DEFINITION) |
| 32 | τ(α, k) = Σ α^i: 1.500 / 1.750 / 1.875 / 1.968 / 1.990 (α = 0.5, k = 1/2/3/5/7), 1.700 / 2.190 / 2.533 / 2.941 / 3.139 (0.7), 1.900 / 2.710 / 3.439 / 4.685 / 5.693 (0.9); τ(α, 3) < 4 for every α < 1 | T_tau, T_tau_lt_rows (∀ α) | [F6-tau] | PROVED (α itself: ASSUMPTION — fleet-only H9) |
| 33 | spec decode: dense 0.193 / 0.262 / 0.355 at α = 0.5 / 0.7 / 0.9 (gain 1.832 / 2.475 / 3.361×), best k = 5 → 0.200 (α 0.5), 7 → 0.315 (0.7) and 0.571 (0.9), a gain for every α ≥ 0.024; MoE uniform 1.074 / 1.451 / 1.971 < 1.867, best k = 1 → 1.811, loss iff α ≤ 0.864 (τ·T₁ < 1000·T₄, T₄/T₁ = 3.2584); Zipf(1.0) D(4) = 25: 1.740, loss iff α ≤ 0.746; Zipf(1.5) D(4) = 20: 2.028 (1.09×), loss iff α ≤ 0.646 (tie at 1.867); mechanism D(4) = 4·D(1), E₁ = 61.7 % of T₁, floor τ < 2.852 | T_spec_dense, T_spec_dense_all_alpha, T_spec_dense_breakeven, T_spec_dense_best_k, T_spec_steps, T_spec_moe_loss, T_spec_moe_loss_exact, T_spec_moe_loss_tps (∀ α, both directions), T_spec_moe_tie, T_spec_moe_mechanism, T_spec_moe_cells | [F6-dense-a*] [F6-dense-k7] [F6-dense-breakeven] [F6-moe-a*] [F6-moe-*-t4] [F6-moe-mechanism] | PROVED (∀ α); which routing family holds: EMPIRICAL — H9 |
| 34 | rollout: 1 card 567.24 / 587.42 / 656.61 ms (dense, 4k / 32k / 128k), 2 cards 1134.59 / 1174.95 / 1313.31, 4 cards 2281.51 / 2362.22 / 2638.96; MoE 27.85 / 32.56 / 48.71, 55.81 / 65.22 / 97.51, 114.92 / 133.75 / 198.32; blocks 283.57 … 340.58 / 15.85 … 27.86; identity 4 × stage-1 + T_head + 2·T_launch + 4λ + (3 hops at 13.9 − 1 at 27.3 + logits) = T_step exactly (both shapes); the round-1 form gives 2362.84 | T_rollout_dense, T_rollout_moe, T_rollout_identity, T_pipelining_decomposition | [F7-*] [F7-*-identity] | PROVED — corrected |
| 35 | ladder expectations: H1 link ns for 4 KiB / 64 KiB / 1 MiB / 64 MiB in both directions (2 374 / 4 714 / 2 400 / 3 449 ns at 64 KiB; 2 431 / 4 828 / 2 458 / 3 532 µs at 64 MiB); H2 41.5 vs 27.6; H5 slopes 61 440 / 16 384 / 12 288 B per token, 8.0 GB at 128k; H7 load 3.5 s (2.3 s with independent links), source 193.3 GB; H3 queue bound (row 16) | T_ladder_H1, T_ladder_rest, T_queue | [F8-*] | PROVED (what the experiments return: EMPIRICAL — H1/H2/H3/H5/H7) |
| 36 | rows cliff: 81/174.6 = 46.3 % (46.4 rounded); B·t ≤ 16 — spec k = 3 allows B ≤ 4, B = 16 excludes spec | T_rows_cliff | [F9-rows] | INPUT (m ≥ 24 measurement) + PROVED arithmetic |
| 37 | fallbacks: dense serial regime (138.9) 2928.50 ms → 0.085; MoE 1M gather3x 2178.63 ms → 0.114 (2.7×); launch fusion 6 → 4 saves 21.84 ms; H6 pipelining −18.0 ms MoE / −33.0 ms per verify step; host-paged KV prefix 2.1 s per card per token, ≥ 5.2 s, 0.0479; §10 single-unknown multipliers 0.93 / 0.76 / 1.15 / 1.03 / 1.16 / 1.0 / 0.95× | T_fallbacks, T_single_measurement | [F9-dense-serial] [F9-moe-1M-gather3x] [F9-launch-fuse] | PROVED |
| 38 | power: Π = 1 one die streams at a time → ≤ 1 card at the measured 141 W; Π = 8 all cards at 141 < 150 W TDP, no throttle | T_power | [F9-power] | INPUT (HW-MAP card table) — the 141 < 150 comparison is the only arithmetic |
| 39 | A-fraction approximation: the measured 174.6 carries 1.5 % of A bytes, the down-projection 3.1 % → 0.44 % per dense layer (27.4 % × 1.6 %); modelled as the explicit hypothesis `pen` (tenths of a percent) on every dense cell; the 32k headline is 0.105 for every pen ≤ 0.8 % and 0.104 at 0.9 %; the spec cell 0.262 → 0.260 at 0.5 %; the MoE step does not contain pen | T_afrac_size, T_afrac_headline (∀ pen ≤ 0.8 %), T_afrac_edge, T_serial_dense_afrac, T_serial_moe_afrac (∀ pen) | — | ASSUMPTION (stated; "3.1 %" is DESIGN-2's kernel-geometry figure, not re-derived here) — carried as a hypothesis, robustness PROVED |

**Coverage of the 39 rows: 39/39 have a theorem (100 %); 37 PROVED (14 of them universally quantified over an
assumed or unmeasured quantity: overhead, λ, G, c_E, α, partition, order, replacement cost, pen), 1 INPUT
(row 38), 1 ASSUMPTION carried as a hypothesis with its robustness proved (row 39); 0 orphans.** The
assumptions the proved rows rest on, each named where it enters: H8 (2 GiB overhead; rows 4, 6–8), H3/H1 (λ =
91 µs; rows 13, 19, 20, 31 — every one also proved over the 10–500 µs bracket), H6 (launch serialisation; rows
17, 19, 31), H4 (Π = 8 is a what-if; row 29), H9 (routing family and α; rows 21, 33), PROBLEM-3 E-gather / E-exp
(rows 18–20, 22–25: both branches proved), DESIGN-2 E13 (serial vs ping-pong expert regime; rows 17, 19, 20, 22),
errata #11/#12 as INPUT (KV die-local, no P2P, no tensor-split, int8 residency; rows 10, 26, 28, 30).

## Section-by-section ledger (every other number in the text)

### Constants table and header
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| R_gemm 174.6 flat m = 1..16, serial fallback 138.9, m ≥ 24: 81 (46.3 % of flat) | Measured.rGemm, rGemmSer, rRows24, T_rows_cliff | R_GEMM, R_GEMM_SER | INPUT |
| R_ddr 173.8 / R_read ~181 (not binding) | Measured.rDdr, rRead | R_DDR, R_READ | INPUT (unused by any cell) |
| host links 27.6 / 27.3, 13.9 / 19.0; P2P refused; D2D 10.7 | Measured.h2d0 … d2h1, rD2D | H2D, D2H, R_D2D | INPUT |
| T_slab 122 979 ns serial, 97 015 pp = (784 118 − 8 000)/8 rounded, F = 8 µs | Measured.tSlabSer, tPpStep, tSlabPP (T0_kv proves 97 015), fMoe | T_SLAB_SER, T_SLAB_PP, F_MOE | D2 (moe.lean T_piece_expert, T1_pp); F: DESIGN-2 ASSUMPTION |
| D(t): uniform min(8t, 256); Zipf(1.0) 8/25/68, Zipf(1.5) 8/20/45 | Design.dOf, Measured.dZipf10/15 | D_TAB, D_of | DEFINITION (uniform) / EMPIRICAL — DESIGN-2 generator, H9 |
| c_mma 15 ns; R_vec 345.6 G lane-ops/s per die = 8 × 43.2; T_launch 91 µs | Measured.cMma, rVecCore, tLaunch; T0_kv (rVecDie = 3456) | C_MMA, R_VEC_DIE, T_LAUNCH | INPUT + PROVED unit conversion |
| 86 GB per die, 8 dies = 688 GB; 141 W / 150 W | Measured.dieMemGB, cards, diesPerCard, pSustain, pTdp; T0_kv, T_power | DIE_MEM, DIES, P_SUSTAIN, P_TDP | INPUT |
| G: stream 174.6 / gather3x 58.2; c_E native 4 / poly 16 | Design.gStream, gGather3x (T0_kv: 582), cNative, cPoly | G_BR, C_EXP | UNMEASURED — PROBLEM-3 E-gather / E-exp (both branches proved everywhere) |
| λ 91 µs primary, bracket 10 / 500 | Design.lamLo/Mid/Hi | LAMBDA | ASSUMPTION — H3 (every λ-dependent theorem also ∀ λ in the bracket) |
| O_rt 2 GiB, WS 64 MiB | Design.oRt, ws | O_RT, WS | ASSUMPTION — H8 (hypothesis variable `ort`) |
| α 0.5 / 0.7 / 0.9; k = 3 | theorem variable `a`; Design.kDraft | ALPHA, K_DRAFT | ASSUMPTION — fleet-only H9 |
| Π = 1 measured; 8 is the what-if | model structure (stepNs vs dieBlock) | — | INPUT / EMPIRICAL — H4 |
| shapes: dense 120 layers, 16 384 / 53 248, 128 / 8 / 128; per-layer 3 187 671 040 (QKV 18 432 + O + 3 × 53 248); MoE 28 layers, 4 096, 32 / 8 / 128; 41 943 040 + 12 926 844 928; embed/head 2 101 346 304 / 525 336 576 | T0_dense_bytes, T0_moe_bytes (denseLayerBytes, moeAttnBytes, moeExpertBytes) | [F0-*] | PROVED |
| KV 4 096 B per token-layer → 491 520 / 114 688 per token; 515.3 / 120.2 GB at 1M; launches 6 / 7 per layer | T0_kv, T_layer | [F0-kv1M] | PROVED |
| draft 1 GB, 24 layers, 121 launches, 201 MB window, k = 3 | Design.draftW, draftLaunch, draftKv; T0_kv | [F0-draft] | DEFINITION (the draft is a design choice) |

### §0 Summary
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| dense fits with f16 KV to L_max = 551 253; 1M does not close with f16 KV (515.3 vs 282.3 GB room); closes with KV-int8 at 84.3 of 86 on the worst die, 1.66 GB margin, iff overhead ≤ 3.80 GB; MoE L_max 1 925 823; minimum fleet 5 dies | rows 5, 6, 8, 10 | — | PROVED (given H8) |
| 32k: dense 0.105 (t = 1), 0.262 spec, 1.067 at B = 16; MoE 1.867, 2.357 B = 16 (4.765 Zipf 1.5); spec on MoE 1.451 | T_step_dense_32k, T_step_moe_32k, T_moe_families | [F10-headline] | PROVED |
| binding: the weight stream of one die at a time; KV binds for MoE at 1M (86 %) and dense beyond L* = 778 240; bounce ≤ 1.1 %; launch 13.5 % of the MoE step; softmax never binds at t = 1 | T_regime_dense, T_regime_moe, T_regime_shares, T_Lstar_kv, T_tstar (t* ≥ 4 on every branch) | [F4-regime] | PROVED |
| 1M: MoE 0.312 (KV 688.8 of 801.1 ms); dense 0.066 with KV-int8 (KV 1 475.9 of 3 746.0); f16 infeasible | T_step_moe_1M, T_step_dense_1M, T_summary | [F3] | PROVED |
| P2P ≤ 1.5 ms (≤ 1.1 %); D2D nothing per token; tensor-split 5.9× / 3.1×; Π = 8 7.7× / 7.1× | rows 27–30 | [F5-*] | PROVED (premises as hypotheses) |
| H4 moves every cell ~7×; at 32k no other unknown > 1.32×; at 1M the G branch 2.7× | T_single_measurement | [F3b-*] [F9-moe-1M-gather3x] | PROVED — corrected |
| ceiling 174.6 / 384.6 = 0.454 fleet (0.113/card), MoE ≈ 13.5 (3.4); predictions at 93 % / 55 % | T_ceiling, T_serial | [F10-headline] | PROVED (0.453 / 13.457 in floored thousandths) |

### §1 Partition
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| §1.1 chain order d1 first / d0 last: 18.8 vs 27.0 µs logits; the hop sum depends only on the first and last die types; chosen = min of four classes (1.2 µs) | T_bw_hops, T_order_* | [F2-order*] | PROVED — corrected |
| §1.1 boundaries after 14, 29, …; MoE 4/3 split; imbalance invisible at Π = 1, 10.3 % at Π = 8 | T_serial_partition, T_pipelining_balance | [F1-*-layout] [F5-moe-pipe-balance] | PROVED — corrected (12.5 → 10.3) |
| §1.1 extra dies cost one hop each ≈ 2λ + 3 µs; 5 dies hold dense to L ≈ 53k (24 layers = 76.5 GB, 78.6 with embedding, 5.2 GB left) | T_summary (185 / 186 µs), T_min_dies_5_dense (52 693; 76.5; 78.6; 5.1 GB floored) | [F1-dense-min-dies] | PROVED |
| §1.2 expert-parallel split = tensor-split (faults); 12.9 GB (12 GiB) of slabs per layer | T0_expert_slabs_units | [F0-moe-experts] | INPUT (errata #11) + PROVED — corrected units |
| §1.3 16 per-core streams of L × 256 B; kv_tok = 4 KiB written per token-layer; L_cap 551 253 / 1 102 506 / 1 925 823; 2048-key blocks = 128 KiB of scores | T0_kv_write, T_Lmax | — | PROVED — corrected (8 → 4 KiB); the stream rate itself: EMPIRICAL — E-gather |
| §1.4 draft on position 1 costs no context (binding die is position 0) | T_Lmax_binding_pos | [F1-dense-draftfree] | PROVED |
| §1.6 load 3.5 s link-bound (2.3 if independent); a host byte costs 6.3× its DDR time | T_ladder_rest, T_serial (x10 1746 276 = 63) | [F8-H7] | PROVED |
| §1.7 tables (rows 4–8); ΔL_max 16 276 / 61 035; B = 16 feasible only to 34k / 120k | rows 4–9 | [F10-mem-*] | PROVED (given H8) |

### §2 Exchange
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| §2.1 hop table (bytes, µs r = 1 / r = 4), logits 18.8 / 75.2, ids 0.0, Σ 41.1 / 164.4 / 24.4 / 97.5 µs, 16 λ | T_bw_hops, T_bw_sum | [F10-xch-*] [F2-*] | PROVED |
| §2.1 T_x table (λ = 10 / 91 / 500) | T_Tx_cells, T_Tx_bracket | [F2-*] | PROVED (∀ λ) |
| §2.2 shares 0.06 % / 1.1 % at 32k | T_regime_shares, T_p2p_bound | [F5-*-p2p] | PROVED |
| §2.2 T8 thresholds 16.4 ms / 918 µs (10 %), 147.5 / 8.27 ms (50 %) | T_bounce_threshold_dense/_moe, T_bounce_round1 | [F9-*-lambda] | PROVED (∀ λ) — corrected |
| §2.2 T7 order dependence | T_order_* | [F2-order-classes] | PROVED — corrected |
| §2.3 trunk bytes 96 KiB / 128 / 128 / 597; budget 65 / 3.7 GB; < 0.02 % | T_trunk_bytes, T_trunk_util | [F2-dense-rows1] | PROVED — corrected units |
| §2.3 Π = 8: 0.84 % on the logits card (MoE), 0.06 % dense | T_pipelining_trunk | [F5-*-pipe-balance] | PROVED — corrected |
| §2.3 bulk chunk waits 5 µs / 75 µs / 1.2 ms | T_queue | [F8-H3] | PROVED (realised wait: EMPIRICAL — H3) |
| §2.3 hop 1/3/5 slowest: 3.6 / 14.2 µs, 2.4 µs below … ≈ 0.6 / 2.6 µs more than a d1 → d0 hop | T_bw_hops (3 557 − 2 911 = 646 ns; 14 230 − 11 646 = 2 584) | [F2-*] | PROVED (the "2.4 µs" is the r = 4 figure 2.6 rounded down — below λ either way) |

### §3 Predictive model
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| §3.1 T_gemm 18 256 993; MoE 240 223 + 2 967 496 / 2 344 360; T_head 12 035 202 / 3 008 800; T_launch 65.70 / 18.01 ms; T_draft 54.27 / 21.24 ms; rows ≤ 16 | T_layer, T_W, T_draft, T_rows_cliff | [F3-*-layer] [F6-draft] | PROVED |
| §3.1 attention table (8 rows) and the 6–8 % / 4.2 % / 24 % shares | T_attn_dense, T_attn_moe, T_attn_shares | [F3-*-attn] | PROVED (∀ G, c_E) |
| §3.2 table (26 rows) | row 19 | [F3] | PROVED |
| §3.3 branches and brackets | row 20 | [F3b-*] | PROVED (∀ λ) |
| §3.4 B = 16 families | row 21 | [F3c-*] | PROVED (D(16) EMPIRICAL — H9) |

### §4 Regime map and crossovers
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| §4.1 all cells and sub-shares | T_regime_dense, T_regime_moe, T_regime_shares | [F4-regime] | PROVED |
| §4.2 T5 L* table; 778 240 = W_layer/4096; 128k 4 % under 136 736; batching divides L* by B | T_Lstar_kv, T_Lstar_iff, T_Lstar_iff_moe | [F4-*-Lkv-*] | PROVED |
| §4.2 T6 t* table; dense t = 4 softmax-bound iff poly and stream, +1 %; KV-int8 poly at t = 2 | T_tstar, T_tstar_iff, T_tstar_model | [F4-*-tsm-*] | PROVED |
| §4.2 T-MMA 8.0 / 32.0 / 127.9 %, MoE 8.0 / 8.0 / 32.0 | T_mma_share | [F4-*-mma-*] | PROVED |
| §4.2 T4 infeasible by 233.0 GB; T8; T2 ceiling | T_mem_room, T_bounce_threshold_*, T_ceiling | [F9-mem] [F9-*-lambda] | PROVED |

### §5 What-ifs
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| P2P ≤ 1.497 / 1.480 ms; D2D 0 B, moves 753 → 161 / 201 → 43 ms; tensor-split 398.52 / 43.02 ms with the corrected decompositions, 5.9× / 3.1×, λ-lo and pipelined variants, 42 % launch-bound; Π = 8 blocks, 7.7× / 7.1×, sub-layer split → ≈ 8× (x10 (8·T_step) Σblocks = 80); tensor-split + P2P 20 / 13 µs per reduction, 6.6× / 4.0×, 54 % launch-bound | T_whatif, T_p2p_bound, T_d2d, T_tsplit, T_tsplit_p2p, T_pipelining_*, T_regime_shares | [F5-*] | PROVED (premises as hypotheses: Π = 8 EMPIRICAL — H4; tensor-split and P2P are counterfactuals to INPUT errata #11) |

### §6 Draft and speculative decoding
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| §6.1 cost table; 61 % launch-bound; 2.9 / 5.5 ms savings | T_draft | [F6-draft] | PROVED |
| §6.2 placement: no contention at Π = 1 (DEFINITION); 6.9 ms DDR contention per draft token at Π = 8; 49 152 B / 10 % / 51.5 GB for a full-context draft KV; 1.2 GB reservation on a 42.7 GB die | T_draft, T_mem_feas_moe_4k | [F6-contention] [F10-mem-moe-4k] | PROVED |
| §6.3 τ table; dense 0.193 / 0.262 / 0.355 (1.83 / 2.48 / 3.36×), k = 7: 0.315 / 0.571; MoE 1.074 / 1.451 / 1.971, best k = 1: 1.811; Zipf(1.5) 2.028 (1.09×); T12 thresholds α ≥ 0.865 / 0.747 / 0.647; mechanism floor τ < 2.852; partition unchanged (bounce bytes × 4 ≤ 0.07 %) | rows 32, 33; T_regime_shares (xNs r = 4 share) | [F6-*] | PROVED (∀ α) — thresholds corrected |

### §7 Rollout
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| T15 block invariance: block(pos) depends only on (layers, extras, L) | Design.dieBlock (a function of exactly those) | — | DEFINITION |
| stage table (18 cells) and per-stage KV facts (61 440 B/token, 8.0 GB at 128k, room to 551k) | T_rollout_dense, T_rollout_moe, T_ladder_rest, T_Lmax | [F7-*] [F8-H5] | PROVED |
| KV move 753 / 201 ms; per-layer oracle 3.2 / 12.9 GB; D × 32 chunks per slab (DESIGN-2 E15) | T_d2d, T0_dense_bytes, T0_moe_bytes | [F5-*-d2d] | PROVED / D2 |
| scaling identity (exact, both shapes) | T_rollout_identity | [F7-*-identity] | PROVED — corrected |

### §8 Ladder and §9 Risks
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| H1 link curves, H2 41.5 vs 27.6, H3 queue, H5 slopes and 16 276 per GB, H7 3.5 s, H8 3.54 GiB (3.80 GB) threshold, H9 D(4) ≥ 30 / ≤ 20 cut-offs | T_ladder_H1, T_ladder_rest, T_queue, T_Lmax_dOverhead, T_mem_feas_kv_int8 | [F8-*] [F1-ort-threshold] | PROVED expectations; outcomes EMPIRICAL — H0–H9 |
| §9 memory risk: 515.3 vs 282.3, 233 GB; KV-int8 257.6 GB; host-paged prefix 2.1 s / ≥ 5.2 s / 0.048 (0.0479); embedding to host 82.2 / 84.3; lm_head 2.1 G MACs ≈ 3 % of the 1M step (0.1 s CPU is an assumption); f16-K/i8-V 386.5 GB, short by 104 | T_mem_room, T_fallbacks, T_mem_embed_to_host, T_summary | [F9-mem] | PROVED (the 0.1 s CPU figure: ASSUMPTION, host-only) |
| §9 bounce thresholds; λ = 500 µs → 140.39 ms (−5 %); 5 dies = 4 hops = 10 λ | T_bounce_threshold_*, T_branches_moe | [F9-*-lambda] [F3b-moe] | PROVED — corrected |
| §9 ceiling 0.113 / 3.4 per card; B = 16 = 10× dense at 32k (memory-limited to 34k); spec 2.48×; Π = 8 7–8× | T_ceiling, T_summary (10 × 1067 / 105 = 101), T_spec_dense, T_pipelining | — | PROVED |
| §9 launch floor 13.5 / 2.8 / 61 / 42 %; fusion saves 21.84 ms; H6 −18.0 / −33.0 ms | T_regime_shares, T_draft, T_fallbacks | [F9-launch-fuse] | PROVED |
| §9 regime −13 %; G −7 / −24 %, 1M 0.312 → 0.114, L* 259k / 45.6k; poly +1 % at t ≥ 4; rows cliff; serial fallback 2928.50 → 0.085; overhead −16 276 / −61 035 per GB; trunk sharing (load 3.5 vs 2.3 s, Π = 8 ≤ 0.84 %); imbalance 0 / 10.3 %; spec on MoE 1.451 vs 1.867, α ≥ 0.647 with Zipf(1.5); draft 54.27 ms = 2.3 % dense / 41 % MoE; host RAM 193.3 + 233 GB; thermal; sampling 19 / 75 / 301 µs + λ ≤ 0.3 % | T_branches_*, T_fallbacks, T_Lstar_kv, T_tstar_model, T_rows_cliff, T_Lmax_dOverhead, T_ladder_rest, T_pipelining_trunk, T_pipelining_balance, T_spec_moe_*, T_draft, T_step_*, T_summary, T_power | [F9-*] [F3b-*] | PROVED (thermal INPUT) |

### §10 The single measurement
| Claim | Proof | fleet.py | Status |
|---|---|---|---|
| Π = 8 moves every cell 7.7× / 7.1×; at 32k every other unknown ≤ 1.32× (0.93 / 0.76 / 1.15 / 1.03 / 1.16 / 1.0 / 0.95×); at 1M the G branch 2.7×; 0.84 % of a trunk; 6.9 ms draft contention; L_max(8) = 68 906 ≥ 32k | T_pipelining, T_single_measurement, T_pipelining_trunk, T_draft, T_pipelining_memory | [F5-*-pipe*] [F6-contention] [F1-dense-Lmax] | PROVED — corrected (the 1M exception) |

---

## Round 3 (2026-11-05) — re-grounding on the season (v1) measurements (HW-MAP e9349c8) and the ALTERNATIVES variants

**What this section is.** DESIGN-4.md round 3 re-derives every λ-, G- and attention-dependent cell on the measured
constants (host bounce 12.2 / 12.1 µs; E21 gather rate per page size; E22 softmax op set via DESIGN-3's round-3 chain;
the measured on-device f16→i8 pass, 43.7 µs) and adds three partition variants (direct-path expert kernel, per-layer
megakernel, two 4-die instances with a minimal int4 tier). The arithmetic is `proof/fleet.py`'s `[R3-*]` section (it
imports `proof/attn.py` for the DESIGN-3 round-3 attention model); **every round-2 label still prints its round-2 value**
(the first 278 lines of the script's output are byte-identical to round 2), so `diff` of the two outputs is exactly the
`[R3-*]` block. **No round-3 theorem is proved yet**: this round is the design re-grounding; the rows below are
theorems-in-waiting with their proposed `T3r_*` names (DESIGN-4.md Appendix A′), to be added to `proof/fleet.lean` in the
next proof session in the convention of `proof/attn.lean`'s round-3 section (round-2 theorems kept as the round-2 model's
arithmetic; `T3r_*` re-instantiations alongside).

| Item | Result |
|---|---|
| `proof/fleet.lean` | *(at the design round; the proof session below extends it)* **unchanged**; `lean proof/fleet.lean` and `cd proof && lake build` still succeed (124 theorems, 0 axioms / sorry / native_decide) — every round-2 theorem remains true of the round-2 model; the cells it fixes that round 3 supersedes are listed below |
| `python3 -I proof/fleet.py` | runs on Python ≥ 3.8 (needs `proof/attn.py` beside it); round-2 output unchanged (278 lines, byte-identical); + 200 `[R3-*]` labels (259 output lines) |
| `proof/alt.py` | unchanged and its output unchanged (it imports `fleet.py`; the new section adds functions only) |
| Round-3 theorems | *(superseded 2026-11-07: all 27 resolved, 168 theorems — see the proof session below)* 0 proved / 27 ledger rows (R1–R27) in waiting; load-bearing survivors stated below |

**Load-bearing verdicts, round 3.** `T_min_dies` **survives unchanged**: no round-3 term enters the memory model
(`[R3-mem]`); the instance variant is PROBLEM-4's "hot/cold residency split" escape under the *different* hypothesis that
int4 bytes ride the measured 5.3 GB/s/core vector-unpack path (the theorem's hypothesis is full int8 residency), so it does
not contradict the theorem — the proof session should state `T3r_inst_fit` as the iff in x beside it. `T_spec_moe_loss`
**survives** with its threshold moved by 0.002: a loss for every α ≤ **0.866** under uniform routing (round 2: 0.864; the
verify step now carries the draft's quant passes), Zipf(1.0) 0.752 (0.746), Zipf(1.5) 0.657 (0.646); on the direct-path
kernel 0.847 / 0.741 / 0.652; the mechanism bound τ < 2.787 (2.852). `T_spec_dense` weakens: the gain is 2.172× (2.475) and
holds for every α ≥ 0.144 (0.024), because the 64-row verify batch is vector-bound on the measured chain; 2.372× / 0.064 on
the fixed-shift chain. `T_serial`, `T_ceiling`, `T_order_*`, `T_mem_*`, `T_Lmax_*`, `T_pipelining_decomposition` (the
identity Σ blocks + λ = T_step holds at λ = 12 200 as well, `[R3-whatif-*-pipe]`, `[R3-rollout-*-identity]`) are untouched.

### Round-2 cells superseded by round 3 (the round-2 theorem stays true of the round-2 model)

| round-2 theorem / row | round-2 cell | round-3 value | `[R3-*]` | why it moved |
|---|---|---|---|---|
| T_Tx_cells (row 13) | T_x 1 497 / 1 480 µs at λ = 91 | **236 / 220 µs** | [R3-xch-*] | λ measured 12.2 µs (the 91 µs was the launch floor) |
| T_bounce_threshold_* (row 14) | 10 % at λ ≥ 16.4 ms / 918 µs | 16.57 ms / **960 µs**; 50 % at 149.2 / 8.65 ms | [R3-T8-*] | T_rest grew by the quant pass |
| T_attn_* (row 18) | per-layer KV 768 715 ns at 32k (174.6, no fixed cost) | **812 036** (256 KiB) / 822 468 (64 KiB); 1M 24 598 896 → 25 401 732 | [R3-attn-*] | E21 rate + DESIGN-3's 18 820 ns fixed cost |
| T_tstar (row 23) | t* = 16 / 4 (dense native / poly), 64 / 16 (MoE) | dense **t ≥ 2** (rows 32) / 3 fixed-shift; MoE 5 / 9; KV-int8 dense 1 / 2 | [R3-tstar-*] | the measured per-call softmax items |
| T_step_dense_32k (row 19) | 2 362.31 ms → 0.105 | **2 387.23 → 0.104** | [R3-moved-dense-32k-B=1t=1] | quant +20.97 ms, attention +5.20, bounce −1.26 |
| T_step_moe_32k (row 19) | 133.84 → 1.867 | **138.69 → 1.802** | [R3-moved-moe-32k-B=1t=1] | quant +4.89, attention +1.21, bounce −1.27 |
| T_step_dense_32k spec (row 19) | 2 416.71 → 0.262 | **2 783.00 → 0.227** (fixed-shift 2 547.50 → 0.248) | [R3-moved-dense-32k-speck=3a=0.7] | rows 64 = four fragments, vector-bound: attention 92 → 427 ms; draft 54.27 → 66.38 |
| T_step_dense_1M KV-int8 (row 19) | 3 746.00 → 0.066 | **4 571.71 → 0.054** (fixed-shift 3 814.12 → 0.065) | [R3-moved-dense-1M-B=1t=1KV-i8] | the halved stream is under the 9 276 ns chain |
| T_step_moe_1M (row 19) | 801.09 → 0.312 | 827.20 → 0.302 | [R3-moved-moe-1M-B=1t=1] | attention 688.76 → 711.24 at 169.2 |
| the other 20 step cells (row 19) | §3.2 | §3.5.2 (−0.9 … −3.7 %; dense 128k spec −33.6 %) | [R3-moved-*] | as above |
| T_branches_* (row 20) | brackets −8 / +3 % dense, −27 / +38 % MoE | **−21 / +4 %** dense (the integrated-chain reading), **−5 / +42 %** MoE | [R3-branch-*] | measured λ and G shrink the old brackets; c_q and the expert regime open new ones |
| T_moe_families (row 21) | 2.357 / 3.714 / 4.765 | 2.325 / 3.636 / 4.638 (direct path 2.728 / 4.144 / 5.173) | [R3-B16-*] | |
| T_Lstar_kv (row 22) | dense 778 240 (= W_layer/4096), MoE 136 736 | dense **753 168** (256 KiB; 777 232 at 174.6 on the block model), KV-int8 1 006 608 at every G; MoE **131 600** / 108 048 (direct) | [R3-Lkv-*] | block granularity + fixed cost + the measured G; KV-int8 is vector-bound. L* is the length from which every longer context is attention-bound; the first attention-bound length is lower in 13 of 40 cells (131 103 for MoE at 256 KiB) — proof-session correction 2 |
| T_fleet_G_* (attn.lean, round 2) | MoE 128k attention-bound iff G ≤ 167.7 | iff G ≤ **168.3** (anchored) / **204.7** (direct path) | [R3-Gstar-*] | the 18 820 ns fixed cost; the faster expert kernel |
| T_regime_* (row 25) | 24 cells | 24 cells: + dense 1M KV-int8 = ATTN:VEC; MoE 128k W by 0.5 % per layer at 256 KiB | [R3-regime] | |
| T_p2p_bound, T_tsplit, T_pipelining (rows 27–29) | ≤ 1.5 / 1.48 ms; 398.52 / 43.02 ms (5.9× / 3.1×); 0.817 / 13.414 | ≤ **236 / 220 µs**; **382.32 / 39.24 ms (6.2× / 3.5×)**; **0.808 / 12.918** (7.7× / 7.1×) | [R3-whatif-*] | reductions 191 → 34 µs; blocks carry c_q |
| T_draft (row 31) | 18.1 ms per draft token, 54.27 per verify step | **22.13 / 66.38 ms** | [R3-draft] | + 24 × 4 quant passes (4.2 ms), − 0.16 ms of bounce |
| T_spec_dense (row 33) | 2.475×, every α ≥ 0.024; best k = 7 → 0.315 | **2.172×, every α ≥ 0.144**; k = 7 → 0.238 (fixed-shift 2.372× / 0.064 / 0.277) | [R3-spec-dense-*] | vector-bound verify rows |
| T_spec_moe_loss_* (row 33) | loss iff α ≤ 0.864 / 0.746 / 0.646 | **0.866 / 0.752 / 0.657** (direct path 0.847 / 0.741 / 0.652) | [R3-spec-moe-*] | the draft's quant passes |
| T_rollout_* (row 34) | 587.42 / 1 174.95 / 2 362.22 ms (dense 32k), 32.56 / 65.22 / 133.75 (MoE) | **593.73 / 1 187.48 / 2 387.22**, **33.85 / 67.72 / 138.68**; identity 4 × stage-1 + 12.29 = 2 387.23 exactly | [R3-rollout-*] | |
| T_ladder_H1 (row 35) | λ intercept = the H1 unknown | λ = 12 200 ns measured; H1 re-verifies | [R3-ladder-H1] | |
| T_fallbacks (row 37) | dense serial 0.085; MoE 1M gather3x 0.114 (2.7×) | 0.084; 0.114 (2.6×); + the integrated chain 0.083 (−20 %) | [R3-risk-*] | |
| T_single_measurement (§10) | every other unknown ≤ 1.32× at 32k | ≤ 1.15× at 32k except the integrated-chain reading (0.80× dense) and the MoE regime (1.13×); H10 2.06× / 1.49× | [R3-decision] | |

### Round-3 rows R1–R27 (DESIGN-4.md Appendix A′) — status

**Superseded by the proof session below (2026-11-07): every row is now PROVED, PROVED ∀ (its hypothesis variable), or
CORRECTED.** The design-round text that stood here ("THEOREM-IN-WAITING … 0 / 27 proved") is replaced by the ledger that follows.

## Round 3 proof session (PROMPT-4P2, 2026-11-07) — the 27 `T3r_*` rows proved

**What this section is.** `proof/fleet.lean` gains a round-3 section after the round-2 umbrellas: namespace `Measured3` (the HW-MAP
e9349c8 inputs and the two round-4 inputs the MoE-128k tie needs), namespace `Attn3F` (DESIGN-3's round-3 attention chain and
its round-4 bounce-legs variant, **duplicated** from `proof/attn.lean` — the fleet file cannot import it standalone; same integer
formulas, rows = t·g per core, `proof/attn.lean` untouched), namespace `Design3F` (`step3`, `die_block3`, `step_tsplit3`,
`inst_step3`, `min_x`, `cold_share` of `proof/fleet.py` transcribed 1:1), and 168 theorems. Every `[R3-*]` number the design
quotes was first printed from `proof/fleet.py` and then fixed by a theorem; the cell theorems were generated from the script's
own values, not typed. The round-2 part of the file is byte-identical (the diff is a header note plus the appended section).

| Item | Result |
|---|---|
| `lean proof/fleet.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 45 s (core Lean 4.35, no imports beyond Init) |
| `cd proof && lake build` | **succeeds** (all six targets: `Model`, `Smoke`, `Moe`, `Fleet`, `Attn`, `Alt`) |
| Theorems in fleet.lean | **292** = 124 round 2 (unchanged) + 168 round 3 (166 `T3r_*`, 2 `max4_*` helpers) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0. `#print axioms` over the 168 new theorems: 79 depend on no axiom; 89 (the `omega` / `simp` proofs and the umbrellas) on the standard `propext` / `Quot.sound` / `Classical.choice` only |
| `decide +kernel` | 4 new (the 1 001-case α iffs `T3r_spec_dense_breakeven`, `T3r_spec_moe_loss_exact`, `T3r_spec_moe_loss_tps`; the lcm(1..256) Zipf share `T3r_inst_zipf`) |
| `python3 -I proof/fleet.py` | the first 583 output lines (every `[F*]`, `[R3-*]`, `[R4-*]` label) **byte-identical**; + 45 `[R3P-*]` lines appended (the corrections and the new hypothesis-variable readings — `diff` of the two outputs IS the correction list); `proof/alt.py` output unchanged |
| Ledger | **27 / 27 rows resolved** (21 PROVED / PROVED ∀ x, 6 CORRECTED with the corrected statement proved), **0 orphans** |

**Inputs instantiated this session (PROMPT-4P2).**
- **H10 is GREEN at card scale** (HW-MAP, season h: two instances on disjoint dies at full solo speed, 1.99× aggregate). It is
  carried as the hypothesis variable `c` (aggregate two-instance throughput in thousandths of one instance: 2 000 = both at solo
  speed — fleet.py's `tps_card_inst`; 1 990 = the measurement; 1 000 = serialised). Every variant-I cell is a function of `c`
  (`tpsInst`), each gain is an iff in `c` (`T3r_h10_iff`, `T3r_inst_gain_measured`, `T3r_inst_h10`), and the card-scale reading
  activates **every overlapped-tier cell** (MoE 32k 3.702, dense 32k 0.154 at c = 1.990; thresholds c ≥ 0.970 / 1.354). The
  two-card inheritance (two 2-card instances behave like two single-die instances) remains the open hypothesis.
- **E35 is LICENSED** (qk-norm + per-row guard): both chains are carried in every cell where they differ (`T3r_e35_branches`);
  the fixed-shift cells are the loadable branch for qk-normalised models; the guard is inside every lazy cell (`T3r_e35_guard`:
  one reduce-max per P reel, 1 455 ns of the 5 530 ns block); the no-guard variant enters no cell. Even one ≈ 10.7 µs guard trip
  in every layer of every step (≥ 450× the measured 0.087–0.22 % rate) leaves the fixed-shift cells unchanged
  (`T3r_e35_trip_bound`).
- **DESIGN-3 round 4** (landed before this session): the tie is stated over the bounce legs (`attn4`, `step4F` = fleet.py
  `attn4_seq` / `step4f`); the `[R4-*]` sections of fleet.py are untouched.

### Corrections forced by formalization (round-3 text → proof)

| # | DESIGN-4 round-3 claim | what the prover found | theorem / label |
|---|---|---|---|
| 1 | serial-chain int4 cold tier: 596 ns per 2 KiB piece, 55.2 W8-eq (constants table, §1.8, R18); "MoE 32k … 147.06 → 3.399 (+88.6 %)", "dense 32k … 4 095.48 → 0.122 (+17.3 %)", "serial-chain at 128k: −4.3 %" | the piece carries **8 KiB** of f16 and two MMA calls: **807 ns**, 413 184 ns per core-slab, **40.8** W8-eq (the alternatives proof round's correction, never propagated). MoE 32k **159.85 → 3.128 (+73.5 %)**; **dense 32k 4 977.19 → 0.100 (−3.8 %): the gain FLIPS to a loss** — it needs c ≥ 2.091×, more than two solo-speed instances give; dense 4k 0.114 (+5.5 %); dense 128k **0.070 (−24.7 %)**; MoE 4k / 128k / 1M 3.662 / 2.087 / 0.507. Dense replication needs the **overlapped** cold tier (E30). The MoE breakeven still passes on the corrected chain (3.4× inside) | `T3r_serpiece`, `T3r_serpiece_h10`; `[R3P-serpiece-*]` |
| 2 | T5′ / R12: "L* = (nb* − 1)·512 + 16 … (checked at L* and L* − 16)"; fleet.py "smallest L … exact over every L" | the t = 1 attention is **not monotone in L**: the L mod 16 vector tail adds up to 3 896 ns, so in **13 of the 40 cells** lengths just below L* are already attention-bound. Proved exact form: attention-bound ⟺ L ≥ L* ∨ (L* − 512 ≤ L ∧ L mod 16 ≥ τ). L* is where every longer context is attention-bound; the first attention-bound length is lower — **MoE anchored at 256 KiB: 131 103 (τ = 15), not 131 600; dense KV-int8: 1 006 102 (τ = 6), not 1 006 608**; dense fixed-shift 753 175, MoE ping-pong 105 489, … Every design cell (L a multiple of 16: tail 0) keeps its verdict — 128k = 131 072 is still weights-bound at 256 KiB, now 31 tokens under the first attention-bound length | 40 × `T3r_Lstar_*`, `T3r_Lstar_kv`; `[R3P-Lkv-*]` |
| 3 | R13 / §4.3: "attention-bound iff G ≤ G*: … dense 1M 2 354 tenths … MoE 1M 13 460" (16 371 / 16 737 on the direct / ping-pong kernels) | false as iffs over G > 0: **the vector chain alone (2 048 × 9 276 + 18 820 = 19 016 068 ns) exceeds every 1M weight time**, so above the printed line the block turns vector-bound and the cell stays attention-bound. Corrected statement proved: **every 1M cell is attention-bound at EVERY G** (no hypothesis on G). The fixed-shift chain keeps a real line at dense 1M (G ≤ 235.3). Every other G* line is an exact iff over all G > 0 (stronger than the G ≤ 174.6 domain) | `T3r_fleet_G_1M_everyG`, `T3r_fleet_G_1M_iff_false`, `T3r_fleet_G_dense_1M_lazy`, 12 × `T3r_fleet_G_*`; `[R3P-Gstar-*]` |
| 4 | §4.3 / R11: "Host bounce ≤ 0.16 % everywhere" | the 24-cell map peaks at **0.18 %** (MoE 4k, t = 1); 0.16 % is the 32k value | `T3r_regime_moe_4k`, `T3r_bounce_share_max`; `[R3P-bounce-max]` |
| 5 | §0′ / §4.3 / §9: MoE 128k "weights-bound by 0.5 % at 256 KiB, attention-bound at 64 KiB / 16 KiB" | **moved by DESIGN-3 round 4** — proved legs-conditional: attention-bound iff G ≤ **168.3 (legs 0) / 178.9 (legs 1) / 189.4 (legs 2)** on the anchored kernel and ≤ 204.7 / 217.5 / 230.3 on the direct path. The planner reads **legs = 2** (erratum #20): **attention-bound at every G ≤ 174.6 on both kernels**; legs 1 gives the same verdict, only a legs-0 route restores the round-3 tie. Precision: "attention-bound" is per layer — at 64 KiB on the round-3 chain the step's largest term is still W (92.82 vs 90.53 ms, the lm_head) | `T3r_moe128k_tie`, `T3r_moe128k_lines`, `T3r_moe128k_tie_cells`, `T3r_moe128k_step_level`; `[R3P-tie-*]` |
| 6 | (decision framing, PROMPT-4P2) "the tie decides whether attention-kernel follow-ups outrank expert-GEMM follow-ups" | at Π = 1 the step is a **sum** (Σ W + Σ ATTN + …), so the binding side ranks nothing. Per MoE token at 128k (legs 2, 169.2): **E29 (direct-path expert kernel) saves 15.86 ms; removing the bounce 11.10 ms; one leg 5.54 ms; 174.6 instead of 169.2 3.08 ms; 169.2 instead of the session-1 loop's 138.3 22.33 ms.** E29 outranks the bounce follow-up at 128k although the cell is attention-bound; the bounce removal overtakes E29 only from L = 187 392 (88.82 ms at 1M); realising the measured G outranks both | `T3r_moe128k_followups`; `[R3P-tie-followups]` |
| 7 | §6.4 T12′: "0.866 loses at 1.397 … 1.802, 0.867 gains at 1.803" | at α = 0.866 the cell is **1.800** (< 1.802); 0.867 gives 1.803 | `T3r_spec_moe_cells`, `T3r_spec_moe_loss_tps` |
| 8 | R16 / §5′: "pays iff c_sync ≤ 109.9 µs (dense)" | the dense line is a **tie**: at c_sync = 109 903 ns the megakernel step equals the launch-per-op step exactly (4 × 109 903 + 15 388 = 455 000); strictly better iff ≤ 109 902 (MoE ≤ 108 430 either way) | `T3r_mega_threshold`; `[R3P-mega-tie]` |
| 9 | §10: "the MoE regime 1.13×" | 1.13× is the serialised-A-lift direct path; the overlapped lift is 1.15× and ping-pong 1.14× — the regime spread is 1.13–1.15× | `T3r_branch_ratios` |

### The 27-row round-3 ledger (DESIGN-4.md Appendix A′)

| # | claim (as corrected) | theorem(s) in `proof/fleet.lean` | fleet.py | status |
|---|---|---|---|---|
| R1 | λ = 12 200 ns; T_x = Σbw + 16 λ: dense 236 307 / 359 643 / 852 999, MoE 219 567 / 292 684 / 585 151 ns; 201 / 8 041 µs at the 10 / 500 µs what-ifs; instance chain 8 λ: 126 / 119 µs | `T3r_Tx_form` (∀ shape, rows, λ), `T3r_Tx` | [R3-xch-*] [R3-inst-*] | PROVED (λ INPUT, HW-MAP e9349c8) |
| R2 | bounce ≥ 10 % of the 32k step iff λ ≥ 16 573 797 ns (dense) / 960 105 (MoE); 50 % iff ≥ 149 184 724 / 8 653 124; 0.01 % / 0.16 % at 12.2 µs, 1 358× / 78× below the 10 % line | `T3r_step_lambda_form`, `T3r_bounce_threshold_dense`, `T3r_bounce_threshold_moe` (iffs ∀ λ), `T3r_bounce_cells` | [R3-T8-*] | PROVED ∀ λ |
| R3 | t = 1 attention per layer (rows ≤ 16): nb(L)·⌊20 971 520 / G⌋ + 18 820 + tail for every G ≤ 174.6 and every L — 812 036 / 25 401 732 ns at 256 KiB, 822 468 / 25 735 556 at 64 KiB, 891 460 / 27 943 300 at 16 KiB, 787 524 / 24 617 348 at 174.6; KV-bound; chain 74.8 % of the block (95.5 % chained) | `T3r_mt1`, `T3r_attn_mt1`, `T3r_block_consts`, `T3r_attn_t1_form` (∀ L, G, rows), `T3r_attn_t1`, `T3r_attn_t1_bind` | [R3-attn-*] | PROVED ∀ G (E21 / E22 INPUT) |
| R4 | dense verify (rows 64, mt 4, 256-token blocks): 3 555 844 ns at 32k, vector-bound (27 350 vs 6 197 ns per block, 4.4×); fixed-shift 1 593 364; MoE verify (rows 16) 812 036 | `T3r_attn_t4` | [R3-attn-*] | PROVED |
| R5 | KV-int8 t = 1 vector-bound: 612 484 / 19 016 068 ns; DDR-bound on the fixed-shift chain: 407 936 / 12 702 784 | `T3r_attn_i8` | [R3-attn-*] | PROVED |
| R6 | c_q × 4 per layer: 20.97 / 4.89 ms per token; proportional reading 568 100 / 262 200 ns per layer at rows 1 | `T3r_quant` | [R3-layer-*] | PROVED (c_q INPUT; the E38 reading is the branch `cq`) |
| R7 | the §3.5.2 table, 31 rows: T_step, W / ATTN / launch / quant / bounce / draft, tokens/s/card, binding, feasibility | `T3r_step_dense_{4k,32k,128k,1M}`, `T3r_step_moe_{4k,32k,128k,1M}` | [R3-step] | PROVED |
| R8 | 26 moved pairs (round-2 theorem value → round-3 value); −0.9 / −3.4 / −13.3 / −18.1 / −3.2 % (dense 128k spec −33.6 %); the round-3 step with the round-2 attention and no quant pass IS the round-2 step, ∀ L, B, t, λ | `T3r_moved_cells`, `T3r_moved_pct`, `T3r_round2_limit` | [R3-moved-*] | PROVED |
| R9 | branches at 32k: dense 0.082 … 0.108, MoE 1.703 … 2.564; λ ∈ [10, 500] µs: dense 0.104 for every λ, MoE 1.706 … 1.802; regimes 2.035 / 2.072 / 2.061; §10's ratios (0.98× … 1.20×; MoE regime 1.13–1.15×) | `T3r_branches_dense`, `T3r_branches_moe`, `T3r_branch_ratios`, `T3r_step_lambda_bracket` (∀ λ in the bracket) | [R3-branch-*] | PROVED ∀ λ (precision (9)) |
| R10 | MoE B = 16: 2.325 / 3.636 / 4.638 (uniform / Zipf 1.0 / Zipf 1.5), 2.728 / 4.144 / 5.173 direct | `T3r_moe_families` | [R3-B16-*] | PROVED (D(16) EMPIRICAL — H9) |
| R11 | regime map, 24 cells: W everywhere except MoE 1M (ATTN:KV 86.0 %), dense 1M KV-int8 (ATTN:VEC 49.9 %) and the MEM cells; quant 0.9 / 3.5 %, launch 2.8 / 13.0 %; **bounce ≤ 0.18 %** | `T3r_regime_{dense,moe}_{4k,32k,128k,1M}`, `T3r_bounce_share_max` | [R3-regime] [R3P-bounce-max] | CORRECTED (4) |
| R12 | KV crossover over every L: attention-bound ⟺ L ≥ L* ∨ (L* − 512 ≤ L ∧ L mod 16 ≥ τ); L* dense 753 168 / 743 440 / 684 560 / 777 232 / 259 088, KV-int8 1 006 608 (first 1 006 102), fixed-shift 753 680 (first 753 175) / 1 507 344; MoE anchored 131 600 (**first 131 103**) / 129 552 / 119 312 / 135 696 / 45 072; direct 108 048 …; ping-pong 106 000 (first 105 489) … | `T3r_nb1`, `T3r_tail1`, 40 × `T3r_Lstar_<shape>_<G>_<regime>_<chain>[_i8]` (∀ L, exact), `T3r_Lstar_kv` | [R3-Lkv-*] [R3P-Lkv-*] | CORRECTED (2) |
| R13 | t = 1 attention-bound iff G ≤ G*, as iffs over every G > 0: dense 32k / 128k 7.3 / 29.4; MoE 32k 42.0 / 51.1 / 52.3, **128k 168.3 / 204.7 / 209.2**; **every 1M cell attention-bound at every G**; MoE-128k margins (W by 16.0 µs = 0.5 % at 256 KiB, ATTN by 25.7 µs at 64 KiB, 301.7 µs at 16 KiB, 550.5 µs = 20.8 % direct) | `T3r_attn_G_form`, 12 × `T3r_fleet_G_<shape>_<L>_<regime>`, `T3r_fleet_G_1M_everyG`, `T3r_fleet_G_1M_iff_false`, `T3r_fleet_G_dense_1M_lazy`, `T3r_moe_128k_cells` | [R3-Gstar-*] [R3P-Gstar-*] | CORRECTED (3); PROVED ∀ G |
| R14 | softmax crossover rows* = 32 (chain as specified) / 48 (fixed-shift): dense t ≥ 2 / 3, MoE t ≥ 5 / 9; KV-int8 dense 1 / 2, MoE 1 / 5; chained convention as stated per corner | 8 × `T3r_tstar_<shape>_<chain><conv>` (∀ t ≤ 16, iff), `T3r_tstar_cells` | [R3-tstar-*] | PROVED ∀ t |
| R15 | P2P saving ≤ T_x (236 / 220 µs); tensor-split 382.32 / 39.24 ms → 0.653 (6.2×) / 6.369 (3.5×), 34 / 27 µs reductions; Π = 8 blocks, Σ blocks + λ = T_step exactly, 0.808 (7.7×) / 12.918 (7.1×), balance loss 3.5 / 10.4 % | `T3r_p2p_bound` (∀ x), `T3r_tsplit`, `T3r_pipelining_blocks`, `T3r_pipelining_decomposition` | [R3-whatif-*] | PROVED (premises: the runtime capabilities, H4) |
| R16 | megakernel saves 54.60 / 15.28 ms, reductions +1.84 / +0.10 ms, 480 / 140 syncs; pays iff c_sync ≤ 109 903 ns (dense: a tie there, strict iff ≤ 109 902) / 108 430 (MoE); cells 0.107 / 0.106 / 0.106, 2.019 / 2.012 / 1.979; V1 + V2 2.307 | `T3r_mega_form` (∀ c), `T3r_mega_threshold` (iffs ≤ and <), `T3r_mega_cells` | [R3-mega-*] [R3P-mega-tie] | PROVED ∀ c_sync (precision (8)) |
| R17 | instance fit: minimal x per die an iff in x (MoE 32k 182 / 170 / 170 / 182 ‰, dense 32k 376 / 358 / 332 / 376) and minimal in all 8 cells; dense 1M infeasible at every x ≤ 1000 and every overhead; margins 1.9 … 30.1 MB; Δx ≤ 23 / 21 ‰ per GB | `T3r_inst_ort_add`, `T3r_inst_form`, `T3r_inst_fit_moe_32k`, `T3r_inst_fit_dense_32k` (∀ x), `T3r_inst_fit`, `T3r_inst_w_mono`, `T3r_inst_dense_1M_infeasible` (∀ x, ort), `T3r_inst_dense_1M_cells`, `T3r_inst_margins`, `T3r_instance_margin` (∀ ort), `T3r_inst_dx` | [R3-inst-fit-*] | PROVED ∀ x, ∀ ort (overhead ASSUMPTION — H8 / H11) |
| R18 | instance cells at c = 2.000: MoE 32k 134.37 ms → 3.720 (+106.4 %), anchored 3.391, overlapped lift 3.771, Zipf(1.0) 4.006, 4k / 128k / 1M 4.396 / 2.437 / 0.577, B = 16 4.035; dense 32k 3 223.48 → 0.155 (+49.0 %), spec 0.349 / 0.374, 4k / 128k 0.168 / 0.122; **serial-chain cells on the 807 ns piece: MoE 32k 3.128, dense 32k 0.100 (a loss)** | `T3r_inst_cells`, `T3r_inst_zipf`, `T3r_serpiece` | [R3-inst-*] [R3P-serpiece-*] | PROVED (popularity EMPIRICAL — H9); serial-chain cells CORRECTED (1) |
| R19 | two instances beat one (MoE 32k) iff the int4 core-slab time ≤ 1 406 404 ns at c = 2.000 / ≤ 1 394 680 at the card-scale c = 1.990; at the measured 5.3 GB/s/core iff c ≥ 0.970 (≥ 1.095 against the direct-path chain); 4.0 / 3.0 / 2.0 / 1.0 GB/s/core → 3.521 / 3.282 / 2.890 / 2.127; all-int4 2.646 dominated | `T3r_inst_moe32k_form` (∀ Tc), `T3r_h10_iff`, `T3r_inst_breakeven` (∀ Tc), `T3r_inst_gain_measured` (∀ c), `T3r_inst_sens`, `T3r_inst_h10`, `T3r_serpiece_h10` | [R3-inst-breakeven-moe-32k] [R3-inst-sens-*] [R3P-h10-*] | PROVED ∀ Tc, ∀ c (H10 hypothesis variable) |
| R20 | V3 + V2 4.170 / 0.157; + overlapped lift 4.234; Π = 8 of one chain 3.4× / 5.2× the two-instance cells; H10's 14.880 vs 7.208 fleet tokens/s (2.06× / 1.49×) | `T3r_inst_vs_pipe` | [R3-inst-combo-*] | PROVED |
| R21 | draft token 22 130 µs = 5 727 + 1 153 + 11 011 + 4 195 + 19 + 24; verify step 66.38 ms (33.35 / 41.34 / 53.80); launch 49.8 %, quant 19.0 % | `T3r_draft` | [R3-draft] | PROVED |
| R22 | dense spec 0.168 / 0.227 / 0.308 (1.608 / 2.172 / 2.949×), k = 7 → 0.238 (0.432); gain iff α ≥ 0.144; fixed-shift 0.184 / 0.248 / 0.337, k = 7 0.277 / 0.503, iff α ≥ 0.064; the pair as thresholds over the chain cost (T3r_spec_dense_split) | `T3r_spec_dense`, `T3r_spec_dense_breakeven` (∀ α, iff), `T3r_spec_dense_best_k`, `T3r_spec_dense_split_form`, `T3r_spec_dense_split` (∀ v), `T3r_spec_dense_split_cells`, `T3r_e35_branches`, `T3r_e35_guard`, `T3r_e35_trip_bound` | [R3-spec-dense-*] [R3P-spec-split] [R3P-e35-trips] | PROVED ∀ α, ∀ v |
| R23 | MoE spec loss iff α ≤ 0.866 / 0.752 / 0.657 (anchored), 0.847 / 0.741 / 0.652 (direct), both directions; 1.034 / 1.397 / 1.897; best k = 1 → 1.745; mechanism E₁ = 82.64 ms = 59.6 %, every τ < 2.787 a loss | `T3r_spec_moe_steps`, `T3r_spec_moe_loss_exact` (∀ α, iff), `T3r_spec_moe_loss_tps`, `T3r_spec_moe_cells`, `T3r_spec_moe_mechanism`, `T3r_spec_moe_loss` | [R3-spec-moe-*] | PROVED ∀ α — **T_spec_moe_loss survives** (precision (7)) |
| R24 | rollout 593.73 / 1 187.48 / 2 387.22 ms (dense 32k), 33.85 / 67.72 / 138.68 (MoE) and the 4k / 128k cells; 4 × stage-1 + 12.29 = 2 387.23 exactly (MoE + 3.25 = 138.69) | `T3r_rollout`, `T3r_rollout_identity` | [R3-rollout-*] | PROVED |
| R25 | ladder: H1 12 348 / 12 494 ns (4 KiB), 2.44 / 4.84 ms (64 MiB); H3 queueing 5 / 75 / 1 207 µs; H10 2.0× (14.880 vs 7.208); H11 margin 24.5 MB, 23 ‰ per GB; E38 47.19 / 2.44 ms between the readings | `T3r_ladder`, `T3r_inst_vs_pipe`, `T3r_inst_margins`, `T3r_inst_dx` | [R3-ladder-*] | PROVED |
| R26 | integrated chain 3 001.92 → 0.083 (−20.1 %) / 136.60 → 1.830 (+1.5 %); dense serial 2 953.41 → 0.084; MoE 128k 1.217 / 1.210 / 1.167 (1.319 / 1.311 / 1.260 direct); MoE 1M 0.302 / 0.298 / 0.278, gather3x 0.114 (2.6×), KV-int8 0.385 / 0.530; dense 1M KV-int8 0.054 / 0.065 | `T3r_fallbacks` | [R3-risk-*] | PROVED |
| R27 | memory tables, L_max, T_min_dies, T_mem_*: unchanged (no round-3 term enters them) | `T3r_mem`, `T3r_min_dies` (= the round-2 theorems) | [R3-mem] | PROVED — **T_min_dies survives unchanged** |

### The three PROMPT-4P2 targets

- **`T3r_spec_dense_split` — survives, sharpened.** The dense verify step at 32k is affine in the per-block chain cost v (ns per
  256-token block at mt = 4, v ≥ 6 197): T(v) = 2 356 342 808 + 15 600·v (`T3r_spec_dense_split_form`). The cell is ≥ 0.248 iff
  v ≤ 12 633, ≥ 0.227 iff v ≤ 27 775, and beats t = 1 iff v ≤ 235 551. The chain as specified (27 350) gives 0.227 with 425 ns of
  margin; the fixed-shift chain (12 254; E35 licensed) gives 0.248 with 379 ns.
- **`T3r_moe128k_tie` — survives as a legs-conditional; the planner reads legs = 2.** Attention-bound iff G ≤ 168.3 / 178.9 /
  189.4 (legs 0 / 1 / 2, anchored), ≤ 204.7 / 217.5 / 230.3 (direct path). At legs ≥ 1 — and legs = 2 is what erratum #20 forces —
  the cell is attention-bound at every G ≤ 174.6 on both expert kernels; the round-3 tie (weights-bound by 0.5 % at 256 KiB) exists
  only at legs 0. What the tie does **not** decide is the ranking of follow-ups (correction 6): at 128k E29 saves 15.86 ms per token
  against 11.10 ms for removing the bounce, so the expert-GEMM follow-up still outranks the bounce follow-up there; the bounce
  removal wins only from L = 187 392 on, and realising the measured G (169.2 rather than the session-1 loop's 138.3) is worth
  22.33 ms, more than either.
- **`T3r_instance_margin` — survives, with the overhead as the hypothesis.** At the shipped minimal x the MoE 32k instance fits iff
  the real per-die overhead is ≤ 2 GiB + 24 485 516 B (dense 32k: + 3 346 208 B). For every L, x and overhead, one more GB of
  overhead is absorbed by +23 ‰ of x (MoE) / +21 ‰ (dense) on every die. Worst-die margins over the replicable cells run from
  1.9 MB (MoE 128k) to 30.1 MB (dense 4k). The cells at +1 / +3 GB step by 22 ‰ per GB (MoE), within the 23 ‰ ceiling.

### Assumptions and hypothesis variables carried, round 3

λ (`lam`, measured 12 200; brackets 10 / 91 / 500 µs), G (`Br3.G` and the ∀ G iffs; E21 rows as inputs), the chain variant and
convention (`Var`, `Conv`: E35 licensed, both carried), the quant-pass reading (`CQ`: E38), the integrated-chain rate (`integ`),
the expert regime (`XReg`: E29), c_sync (`mega`: E31), the int4 share x and the overhead `ort` (H8 / H11), the cold-tier time `Tc`
(the measured 5.3 GB/s/core and its serial-chain branch, 807 ns per piece), the popularity family (H9), the acceptance α, the
bounce legs (E24′), the verify-chain cost v (E35), and the two-instance concurrency c (H10: measured 1.99× at card scale; the
two-card inheritance is the open premise). Π stays 1 in every cell except the Π = 8 what-if (H4).

**Coverage, round 3 (proof session):** 27 / 27 rows resolved — 20 PROVED as stated (most of them ∀ an explicit hypothesis
variable), 4 CORRECTED (R11, R12, R13, R18: the corrected statement is the one proved), 3 PROVED with a precision correction (R9,
R16, R23); the MoE-128k tie target is proved in its moved, legs-conditional form; **0 orphans** — every
number in DESIGN-4.md's round-3 blocks and in its corrected cells is fixed by a theorem above or is an INPUT (HW-MAP) / EMPIRICAL
(named experiment) entry of this ledger. The round-2 ledger above is unchanged (39 / 39 proved of the round-2 model).


## Round 5 (2026-11-07) — the measured production attention kernel in the planner (PROMPT-3R5; attention session 3, HW-MAP 62e8137)

**What this section is.** `proof/fleet.lean` gains a round-5 section after the round-3 proof session: namespace `Measured5F` (the t = 1
per-layer cells of the t × L sweep, the unguarded 32k cell, the t = 16 32k cell, the bounce, the stream phase, erratum #29's crossing band
and the rowmax crossing bound — duplicated from `proof/attn.lean`'s `Measured5`, which the fleet file cannot import standalone), namespace
`Design5F` (`guardF`, `bounceF`, `streamF`, `aUng`, `aFused`, `overlapF`, `step5F` = fleet.py `step5f`, `instStep5`, `e29`), and 18
theorems. Every round-5 number DESIGN-4 quotes was first printed by `proof/fleet.py` (`[R5-*]`) and then fixed by a theorem generated from
the script's own values. The round-2 and round-3 parts of the file are byte-identical (the diff is the appended section).

| Item | Result |
|---|---|
| `lean proof/fleet.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 46 s |
| `cd proof && lake build` | **succeeds** (all six targets) |
| Theorems in fleet.lean | **310** = 292 (rounds 2–3, unchanged) + **18** round 5 (`T5r_*`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0. `#print axioms` over the 18: 11 depend on no axiom, 7 on `propext` + `Quot.sound` only |
| `decide +kernel` | 1 new (`T5r_spec_thresholds`: four 1 001-case α iffs, the round-3 pattern) |
| `python3 -I proof/fleet.py` | the first 628 output lines **byte-identical**; + 41 lines (39 `[R5-*]` labels); `proof/alt.py` output unchanged |
| Ledger | **14 / 14 rows resolved** (F5-1 … F5-14), **0 orphans** |

**Inputs (MEASURED, attention session 3; DESIGN-3 §6.0 and its ledger rows R5-1 … R5-22):** the t = 1 per-layer cells 213 500 /
1 513 600 / 5 852 900 / 46 313 600 ns at 4k / 32k / 128k / 1M (guarded), the unguarded 32k cell 938 800 ns, the t = 16 32k cell
10 741 700 ns, the bounce ≈ 51 000 ns and the K+V stream phase 770 800 ns at 32k, erratum #29's crossing band 10–20 µs. **The validation
row** (DESIGN-3 R5-3, an INPUT row here): 938.8 vs the round-4 cell 911.68 µs = 3.0 % (2.9 % of the displayed 912) ≤ the 5 % match line.

**The three readings and their status.** guarded = MEASURED at every L; unguarded = MEASURED at 32k, DERIVED off 32k (the guarded cell
minus the per-block guard 574 800 ns / 64 blocks — the per-block scaling is UNMEASURED off 32k; the constant-rate reading 143.0 GB/s is
carried as the bracket); fused = DERIVED target (unguarded + one 20 µs crossing per step; the batched guard is UNMEASURED — E39).

### Corrections and moves (round 4 / round-3 proof session → round 5)

| # | Claim before | Now | theorem / label |
|---|---|---|---|
| 1 | the attention term = DESIGN-3's round-4 model (lazy-T, legs 2, 169.2): MoE 32k 1.766, 128k 1.155, 1M 0.272; dense 32k 0.104 | the MEASURED kernel: **guarded MoE 32k 1.578 (−10.6 %), 128k 0.893 (−22.6 %), 1M 0.176 (−35.2 %); dense 32k 0.101 (−2.8 %), 128k 0.083 (−8.7 %)**; on the unguarded / fused readings every cell within ±2.2 % of round 4 | `T5r_step_cells`; `[R5-step-*]` |
| 2 | T3r_moe128k_tie: legs-conditional; the planner reads legs = 2 (UNMEASURED) | legs = 2 MEASURED; on the measured kernel attention-bound by 82.5 / 10.8 / 11.4 % (anchored), 121.6 / 34.5 / 35.3 % (direct); the step attention-bound on every reading; stream-only lines at the measured bounce **178.7 / 220.2** (round 4: 189.4 / 230.3); G_eff lines 167.3 / 203.2 | `T5r_moe128k_tie_measured`, `T5r_moe128k_everyG`, `T5r_moe128k_cells`; `[R5-moe-128k-*]` |
| 3 | the follow-up ranking at MoE 128k: choreography 22.33 > E29 15.86 > bounce 11.10 ms | **guard fusion 63.81 > E29 15.86 > phase overlap ≤ 7.46 > bounce 5.71**; the choreography lever retired (the stream phase runs 174–176, MEASURED; the guard covers 101.5 % of the measured gap); 169.2 → 174.6 moot | `T5r_levers`, `T5r_retired`; `[R5-levers-*]`, `[R5-retired]` |
| 4 | (steering, PROMPT-3R5) "guard fusion (worth ~570 µs at 32k) is the new #1" | true at MoE 128k / 1M and on every dense cell; **at MoE 32k guard fusion outranks E29 iff the fused kernel's residual X ≤ 8 279 ns per step** (T_fused ≤ 947 079 ns = 141.7 GB/s); at the measured band (10–20 µs) E29 stays first by 48 160–328 160 ns per token (0.3–2.1 %); first for every L ≥ 33 297 (32 785 at 10 µs); MoE 4k: E29 first | `T5r_levers_moe32k_iff` (∀ X), `T5r_levers_overtake` (∀ nb), `T5r_nbF_lines` (∀ L) |
| 5 | T_spec_moe_loss: the MoE verify batch loses iff α ≤ 0.866 (round 3) | **survives, line moved: α ≤ 0.807 guarded / 0.854 unguarded / 0.853 fused** (verify kernel = the t = 1 kernel, D transfer); dense spec breakeven 0.144 → 0.179 | `T5r_spec_steps`, `T5r_spec_thresholds` (∀ α) |
| 6 | dense spec 0.252 (round 4), MoE spec 1.389 | guarded verify kernel (D transfers): **dense 0.211, MoE 1.339** | `T5r_spec`; `[R5-spec-*]` |
| 7 | MoE B = 16 2.267 (round 4) | 1.966 / 2.251 / 2.240 | `T5r_B16` |
| 8 | two instances at c = 1.990: MoE 32k 3.702, dense 0.154 (round 3) | MoE 3.230 / 3.607 / 3.592 (needs c ≥ 0.973 / 0.970 / 0.970), dense 0.150 / 0.153 / 0.153 (c ≥ 1.350 / 1.361 / 1.349) — the instance decision unchanged | `T5r_inst` (∀ c) |
| 9 | dense 1M KV-int8 0.053 (round 4, rowmax chain) | **≤ 0.034** with erratum #29's per-block crossing bound (≥ 10 318 ns × 2 048 × 120) | `T5r_dense1M_bound` |

### The round-5 ledger (DESIGN-4.md round-5 blocks: banner, §0″, §3.6, §4.4, §6.5, §8 / §9 rows, §10″, Appendix A″)

| # | claim | theorem(s) in `proof/fleet.lean` | fleet.py | status |
|---|---|---|---|---|
| F5-1 | per-layer readings, t = 1 (both shapes, mt = 1): guarded 213 500 / 1 513 600 / 5 852 900 / 46 313 600; unguarded 141 650 / 938 800 / 3 553 700 / 27 920 000; fused 161 650 / 958 800 / 3 573 700 / 27 940 000 (cx 10 µs: −10 000 each); round 4 130 872 / 911 680 / 3 588 736 / 28 574 592; the unguarded reading exact at 32k | `T5r_readings` | [R5-attn-*] | INPUT (guarded; unguarded 32k) + PROVED (D readings; per-block guard off 32k UNMEASURED) |
| F5-2 | the step is affine in the per-layer attention: dense 2 289 788 669 + 120·a, MoE 115 956 899 + 28·a (t = 1, B = 1) | `T5r_step_form` (∀ a) | [R5-step-*] | PROVED ∀ a |
| F5-3 | the t = 1 cells: dense 4k 0.107 / 0.108 / 0.108, 32k 0.101 / 0.104 / 0.103, 128k 0.083 / 0.092 / 0.091; MoE 4k 2.050 / 2.084 / 2.074, 32k 1.578 / 1.757 / 1.750, 128k 0.893 / 1.160 / 1.157, 1M 0.176 / 0.278 / 0.278; round 4 beside each | `T5r_step_cells` | [R5-step-*], [R5-headline-*] | PROVED |
| F5-4 | the MoE-128k tie restated (correction 2) | `T5r_moe128k_tie_measured` (∀ G, iffs), `T5r_moe128k_everyG` (∀ G ≤ 174.6), `T5r_moe128k_cells` | [R5-moe-128k-tie], [R5-moe-128k-step] | PROVED ∀ G (legs, kernel: INPUT) |
| F5-5 | the lever table per (shape, L) and its orderings (cx = 20 µs; 10 µs alongside) | `T5r_levers` | [R5-levers-*] | PROVED (E39 / E40 values: UNMEASURED targets / bounds) |
| F5-6 | MoE 32k: guard fusion > E29 iff X ≤ 8 279 ns | `T5r_levers_moe32k_iff` (∀ X ≤ 574 800) | [R5-levers-moe-32k-iff] | PROVED ∀ X (X: EMPIRICAL — E39) |
| F5-7 | guard fusion overtakes E29 from 66 / 65 blocks = every L ≥ 33 297 / 32 785 | `T5r_levers_overtake` (∀ nb), `T5r_nbF_lines` (∀ L) | [R5-levers-overtake-*] | PROVED ∀ nb, L (per-block guard reading) |
| F5-8 | the P4P2 ranking retired / moved: 22 335 488 ns choreography lever; gap 2 264 164 ns per layer (63.39 ms per token), the per-block guard 101.5 % of it; bounce 11 103 232 → 5 712 000 ns; 169.2 → 174.6 3 089 408 ns (moot) | `T5r_retired` | [R5-retired] | PROVED |
| F5-9 | context: E31 at c_sync = 5 µs saves 14 480 312 ns per MoE token, 50 353 440 per dense token | `T5r_levers_context` | [R5-levers-context] | PROVED (c_sync: EMPIRICAL — E31) |
| F5-10 | spec decode on the guarded verify kernel: dense 3 000.80 ms → 0.211, MoE 472.72 → 1.339; round 4 0.252 / 1.389 | `T5r_spec` | [R5-spec-dense-32k], [R5-spec-moe-32k] | PROVED (the fragment transfers: D; unguarded verify: UNMEASURED) |
| F5-11 | spec thresholds: dense beats t = 1 iff α ≥ 0.179; MoE loses iff α ≤ 0.807 / 0.854 / 0.853 | `T5r_spec_steps`, `T5r_spec_thresholds` (∀ α) | [R5-spec-dense-breakeven], [R5-spec-moe-loss-*] | PROVED ∀ α — **T_spec_moe_loss survives (line moved)** |
| F5-12 | MoE B = 16: 1.966 / 2.251 / 2.240 (round 4 2.267) | `T5r_B16` | [R5-B16-moe-32k-*] | PROVED (D(16): EMPIRICAL — H9) |
| F5-13 | two instances (c = 1.990): MoE 3.230 / 3.607 / 3.592, dense 0.150 / 0.153 / 0.153, with the c each needs | `T5r_inst` (∀ c) | [R5-inst-*] | PROVED ∀ c (H10 hypothesis variable) |
| F5-14 | dense 1M KV-int8 ≤ 0.034 (round 4 0.053) | `T5r_dense1M_bound` | [R5-dense-1M-kvi8] | PROVED (bound; KV-int8 kernel UNMEASURED) |

**Hypothesis variables carried, round 5:** the per-layer attention a (the step's only attention input — every cell is an instance of
`T5r_step_form`), the fused kernel's residual X per step (E39: crossings + vector side-product + re-runs), the block count nb (the per-block
guard reading), the crossing cost cx ∈ [10, 20] µs, the concurrency c (H10, unchanged), the acceptance α. Unchanged: λ, the expert regime,
the int4 share x and the overhead `ort`, c_sync, the popularity family. **T_min_dies is untouched** (no attention term enters it).

**Coverage, round 5:** 14 / 14 rows resolved — 13 PROVED (6 universally quantified over a, G, X, nb / L, α, c), 1 PROVED bound (F5-14);
the MoE-128k tie target is proved in its measured form; **0 orphans** — every `T5r_*` theorem of fleet.lean is cited in F5-1 … F5-14, every
`[R5-*]` label family of fleet.py is cited. The round-2, round-3 and round-3-proof-session ledgers above are unchanged.
