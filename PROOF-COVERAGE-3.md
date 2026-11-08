# PROOF-COVERAGE-3 — ledger of every quantitative claim in DESIGN-3.md (round 2, 2026-11-04; round 3, 2026-11-05; round 4, 2026-11-07; round 5, 2026-11-07 — the measured production kernel; PROMPT-6, 2026-11-08 — the errata #18–#31 audit and the E40 pre-design; round 6, 2026-11-08 — the measured deferred-guard cells)

How to read a row: **Claim** quotes or paraphrases the DESIGN-3.md statement (section numbers refer to the
corrected document); **Proof** names the theorem(s) in `proof/attn.lean` that fix the number; **attn.py** names
the label in `proof/attn.py` that prints it; **Status** is one of PROVED (follows arithmetically from the
constants table; "∀ x" marks a universally quantified result over an unmeasured or assumed quantity x — both
bracket endpoints are then proved as well), INPUT (a HW-MAP measurement or erratum used as given), D4 / D1 (a
DESIGN-4 theorem of proof/fleet.lean or DESIGN.md's route-1 unit used as an input), DEFINITION (true by
construction of the cost model or a structural choice with no number in it), EMPIRICAL — Ex (settled only by
the named experiment of DESIGN-3.md §8; no theorem claims it), or ASSUMPTION — Ex (explicitly labelled A in
the design and carried as a hypothesis variable of the theorems that use it: "PROVED given the assumption").

Units in the proof file: bytes (KiB/MiB binary); rates in tenths of GB/s (1746 = 174.6); time in ns (floored),
quoted µs round-half-up (`usR`); lane-ops as vector work units (43.2 G/s/core = 432 tenths → ns = ops·10/432);
percentages in tenths (`pct`); ratios in tenths, floored (`x10`); the gather rate G and per-page cost c_pg, the
softmax op counts c_V / c_exp / R and the f32 lane-rate penalty ρ32, the drain rate R_drain, the merge count,
the scalar iteration σ_s and the score magnitude smax are explicit arguments of the model.

The stream column uses the kernel's measured **174.6 GB/s** (DDR → L0B direct, one full barrier per 32 KiB tile,
flat m = 1..16) as the pure-read roof class — the KV stream is read-only (the only writes per step are the
≤ 8 KiB K/V append and the output), so the 173.8 read+write figure does not apply; the raw direct-load 181.3 is
recorded as the ceiling the kernel's choreography sits under (`Measured.rGemm`, `rDirect`, `rDdrRW`;
T1_stream_roof gives the 3.8 % what-if).

## Round 6 (2026-11-08) — the MEASURED deferred-guard cells folded in (PROMPT-3R6; kernel session 5, HW-MAP 3928d0e)

Round 6 replaces round 5's fused reading with the measured deferred-guard kernel, resolves E39, closes E35's device half and documents the
two numerics classes session 5 surfaced. Labels `[R6-*]` are printed by `python3 -I proof/attn.py` after the PROMPT-6 block (the first 942
output lines — every round-2 … PROMPT-6 line — are byte-identical: `diff` of the two outputs is exactly the `[R6-*]` block); theorems
`T6r_*` are the last section of `proof/attn.lean` (namespaces `Measured6`, `Design6`). Status words: **MEASURED** (= INPUT: a kernel-session-5
number used as given, or session 3 where named), PROVED / **DERIVED** (a theorem from measured inputs), **UNMEASURED** (carried as a variable,
a bracket or a bound, with a ladder row), CORRECTION, EMPIRICAL — Ex.

### Build status, round 6

| Item | Result |
|---|---|
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 8 s |
| `cd proof && lake build` | **succeeds** (all six targets; the only warnings are smoke.lean's, pre-existing) |
| Theorems in attn.lean | **366** = 350 (rounds 2–5 + PROMPT-6, kept byte-identical) + **16** round 6 (`T6r_*`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` over the 16: 14 depend on no axiom, 2 (`T6r_trip_breakeven`, `T6r_fleet_moe_128k_eff`) on `propext` + `Quot.sound` |
| New namespaces | `Measured6` (the canonical adversarial cells, the 1M legacy as quoted, the trip-rate premise, the two quoted differences, the fold's cap, the numerics counts, the direct-path MoE layer), `Design6` (`amort`, `reRun32k`, `reRun1M`, `pctH6`); the session-5 cells themselves are PROMPT-6's `Audit6` constants |
| `python3 -I proof/attn.py` | 942 lines unchanged + 21 lines (19 `[R6-*]` labels); `python3 -I proof/fleet.py` 676 unchanged + 36 lines; `proof/alt.py` output unchanged |
| Cell theorems | generated from attn.py's own values (scratch `gen_attn6.py`) — no hand-typed cell |

### The moved cells (round 5 → round 6; `[R6-moved]`, T6r_vs_round5)

| Cell | Round 5 | Round 6 | Status | Theorem |
|---|---|---|---|---|
| fused (the fleet's attention), 32k t = 1 | 958 800 ns (140.0 GB/s): unguarded + one 20 µs crossing — the E39 target | **945 500 trip-free (142.0)**; 946 300–947 400 amortized (141.8–141.7) | M (the amortized band: an amortization of two M cells) | T6r_cells, T6r_vs_round5, T6r_amort |
| fused, 128k / 1M | 3 573 700 / 27 940 000 (D: the per-block guard rule) | **3 618 800 (148.4) / 28 694 000 (149.7)** — 1.3 / 2.7 % slower than the reading | M | T6r_cells, T6r_vs_round5 |
| E39 (batched guard, residual X) | UNMEASURED; decides the 32k rank iff X ≤ 8 279 ns | **RESOLVED**: the deferred guard; X = 6 700 trip-free / 7 500–8 600 amortized (straddles 8 279) | M | T6r_e39 |
| E35 device half | RESOLVED: the scan is the cost, trips ≈ free | **CLOSED**: +42 600 ns per step (fold + end read), R = 872 600 per trip, breakeven 65.25 % / 64.47 % of steps | M + D (∀ p) | T6r_fold, T6r_amort, T6r_trip_breakeven |
| the guarded column | the shipped kernel (1 513 600 at 32k) | the legacy A/B control (1 514 900 at session 5) | M | T6r_base |
| validation row (vs the round-4 legs-2 cell 911 680) | +3.0 % (session 3's unguarded 938 800) | **−1.0 %** (session 5's guard-off 902 900) | M + D | T6r_base |
| MoE 128k (DESIGN-4) per layer | +11.4 % over the anchored layer (the fused reading) | **+12.8 %** (anchored), +37.0 % (direct) | D (M cell) | T6r_fleet_moe_128k |
| × GEMV at 32k / 128k / 1M | 3.80 / 14.7 / 116.4 (guarded) | **2.38 / 9.09 / 72.1** (deferred) | M | T6r_cells |

### Corrections forced by the measurements (round 5 → round 6)

| # | Where | Round 5 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §6.0 readings off 32k | unguarded / fused = the guarded cell minus a flat 8 981 ns per block (UNMEASURED off 32k) | the rule was **optimistic by 1.3 / 2.7 % at 128k / 1M** (fused reading vs the measured cell); legacy − deferred per block is 8 876 / 8 726 / 8 603 ns (mixed sessions) | session 5 (T6r_perblock, T6r_vs_round5) |
| 2 | §3.2 / §8 E39 model | fused = 938 800 + X with X = one ≤ 20 µs crossing | the shipped guard costs **42 600 ns over its own base** (2.1× the modelled crossing); the cell still lands 1.4 % under the target because the base moved −35 900 ns — a net of two terms | session 5 (T6r_e39, T6r_base) |
| 3 | §3.4 (c) / §9 the trip under a batched guard | ≤ 0.22 % of a step (≈ 2.1 µs at 32k), re-run cost UNMEASURED | re-run R = **872 600 ns** (30 300 under one guard-off step); amortized +800–1 900 ns; the band 946.3–947.4 µs is T₀ + p·R (an amortization of the trip-free and canonical cells, not a third measurement) | session 5 (T6r_amort) |
| 4 | §6.0 validation | the round-4 cell matches the unguarded kernel at +3.0 % | on the session-5 base the match is **−1.0 %**; the term split is not re-instantiated (session 5 did not re-time the phases) | session 5 (T6r_base) |
| 5 | steering (PROMPT-3R6) "the fold costs −59 µs vs the scan (one pass)"; HW-MAP "−558 µs at real rates" | — | **neither reproduces from the quoted cells**: the one-pass cell difference is 569 400 ns (9.7× 59 000), the real-rate differences 567 500–568 600 (9 500–10 600 above 558 000); both carried as given, no cell uses them | T6r_fold |

Not corrections (survivals): MoE 128k attention-bound (now by 12.8 % on the measured cell, and still +2.5 % at a perfect overlap); the
online two-level chain and the trip machinery (exact at the +8 bound); erratum #31's verdict (the batched fence + flag design stays killed);
E40's pre-design and its prize (PROMPT-6 already priced it on these cells); the legacy scan (byte-identical; it reproduces session 3 within
+0.1 %).

### The round-6 ledger (every `[R6-*]` label and every round-6 claim of DESIGN-3.md)

| # | Claim (round-6 text: banner, §3.2, §3.4, §5.1, §6.0′, §6.3, §7, §8, §9, §10, App. A) | Proof | labels | Status |
|---|---|---|---|---|
| R6-1 | the deferred cells, trip-free: 945 500 / 3 618 800 / 28 694 000 ns = 142.0 / 148.4 / 149.7 GB/s; 64 / 256 / 2 048 blocks; 14 773 / 14 135 / 14 010 ns per block; × GEMV 237.6 / 909.2 / 7 209.5 % | T6r_cells | [R6-cells-*] | **INPUT (session 5)** + PROVED |
| R6-2 | the amortized band 946 300–947 400 ns (141.8–141.7 GB/s) = T₀ + p·R at p = 0.087 / 0.22 % (946 259 / 947 419 → 946.3 / 947.4 µs); R = 872 600 = guard-off − 30 300; trips +800–1 900 ns = 0.08–0.20 %; each 1 % of tripped steps 8 726 ns (0.92 %) | T6r_amort | [R6-amort] | INPUT (band, canonical) + PROVED (the reproduction); the ~100 % canonical trip rate: INPUT |
| R6-3 | 1M: R = 27 306 000 (the 56.0 ms adversarial cell); IF the 32k premise transfers, 28 717 756–28 754 073 ns = 149.6–149.4 GB/s (+0.08–0.21 %) | T6r_amort | [R6-amort-1M] | PROVED; the trip rate per (model, L): **UNMEASURED** — E35 (model half) |
| R6-4 | the trip-rate breakeven against the legacy scan, ∀ p: p ≤ 65 253 per 10⁵ (65.25 %) at 32k, ≤ 64 476 (64.47 %, against the quoted 46.3 ms) at 1M; the premise (≤ 220) ≥ 296× inside | T6r_trip_breakeven (∀ p), T6r_trip_premise | [R6-trip-breakeven] | PROVED ∀ p |
| R6-5 | the adversarial canonical profile: 1 818 100 ns (73.8 GB/s) vs the legacy 1 514 900 (+20.0 %, +303 200); 56.0 ms (76.7 GB/s) vs 46.3 (+21.0 %, +9 700 000); the gap grows with L; an upper bound, never the fleet cell | T6r_adversarial | [R6-adversarial] | INPUT + PROVED |
| R6-6 | the session-5 base: guard-off 902 900 (148.7 GB/s) = −35 900 (−3.8 %) vs session 3's unguarded; legacy 1 514 900 (88.6 GB/s) = +1 300 (+0.1 %) vs session 3; vs the round-4 cell 911 680: −1.0 % (session 3 +3.0 %), inside the 5 % line | T6r_base | [R6-base] | INPUT + PROVED; the session-5 term split: **UNMEASURED** — E41 |
| R6-7 | the fold decomposition: legacy − guard-off 612 000 (session 3: 574 800); deferred − guard-off 42 600 (4.7 %); the deferred guard removes 569 400 = 93.0 % trip-free, 567 500–568 600 amortized | T6r_fold | [R6-fold] | INPUT + PROVED; the fold / end-read split: **UNMEASURED** |
| R6-8 | the quoted differences: "−59 µs vs the scan (one pass)" (PROMPT-3R6) and "−558 µs at real rates" (HW-MAP) do not reproduce (569 400 = 9.7 × 59 000; 558 000 is 9 500–10 600 under the cell differences) | T6r_fold | [R6-fold] | INPUT (as quoted); CORRECTION 5 (not used by any cell) |
| R6-9 | E39 RESOLVED: the cell beats the 958 800 target by 13 300 (1.4 %) trip-free, ≥ 11 400 amortized; X = 6 700 / 7 500 / 8 600 vs the 8 279 line; own-base residual 42 600 = 2.1× the 20 µs crossing, between 20 000 and 51 040 (crossing + side-product at the measured softmax rate); residual +22 600 netted against the base −35 900 | T6r_e39 | [R6-e39] | INPUT + PROVED |
| R6-10 | E35's device half CLOSED: zero scalar ops per block; +42 600 per step; R = 872 600; amortized +800–1 900; breakeven 65.25 / 64.47 % | T6r_amort, T6r_trip_breakeven, T6r_fold | [R6-e35] | INPUT + PROVED; the trip rate per (model, L): EMPIRICAL — E35 |
| R6-11 | the fold at the +8 bound: e⁸ < 2.7183⁸ = 2 981.1 < 3 072; e^8.02 < 2.7183⁸ · 50/49 = 3 042.0 < 3 072 (the cap clamps from ln 3 072 = 8.030); cap = 3 · 2¹⁰ (f16-exact); planted 8.0 → 0 trips, 8.02 → exactly 1 | T6r_fold_bound | [R6-fold-bound] | PROVED given e < 2.7183 and e^x ≤ 1/(1 − x) (analytic inputs); the trip counts: INPUT |
| R6-12 | round 5's off-32k rule tested: legacy − deferred per block 8 876 / 8 726 / 8 603 ns vs 8 981; the deferred kernel affine in nb (slopes 13 923 / 13 992, intercept 54 428 ns; the 1M cell +125 268 = 0.4 % over the 32k–128k chord) | T6r_perblock, T6r_vs_round5 | [R6-perblock] | PROVED (mixed sessions 3 / 5); CORRECTION 1; below 32k: **UNMEASURED** |
| R6-13 | the measured cells against round 5's readings: fused −1.4 / +1.3 / +2.7 %, unguarded +0.7 / +1.8 / +2.8 %, the 140.0 bracket −1.4 / −5.6 / −6.5 %, the legacy −37.5 / −38.2 / −38.0 % | T6r_vs_round5 | [R6-cells-*], [R6-moved] | PROVED |
| R6-14 | × GEMV 2.38 / 9.09 / 72.1 units (legacy 3.80 / 14.7 / 116.4); per DESIGN-4 layer MoE 29.5 / 112.8 / 894.5 %, dense 5.2 / 19.8 %; +3.7 / +0.8 / +0.4 % over the round-4 legs-2 cells | T6r_cells, T6r_layer_fractions | [R6-gemv] | PROVED (layer times: D4 inputs) |
| R6-15 | MoE 128k on the measured cell: +411 081 ns = 12.8 % (anchored), +977 601 = 37.0 % (direct); 148.4 GB/s under the 167.3 / 203.2 effective-rate lines; the E40 floor F1 +79 481 = 2.5 % | T6r_fleet_moe_128k, T6r_fleet_moe_128k_eff (instance of the ∀ G iff) | [R6-fleet-moe-128k] | PROVED |
| R6-16 | the 1M canonical bad-2: f16 normals end at 2⁻¹⁴ (ln −9.704), subnormal spacing 2⁻²⁴, 1 % granularity at P ≤ 1/167 772 (ln −12.03); the exact P path = 8 388 608 lanes, 100.00 %; disposition: adversarial-only, documented, no kernel change | T6r_numerics | [R6-numerics-subnormal] | INPUT (the class, the counts) + PROVED (the constants); its reading as a row-max outlier with no output weight: INTERPRETATION of the session's description |
| R6-17 | the random-profile out-verify floor: bad 324 at 32k / 65 at 1M, identical for deferred / legacy / guard-off; disposition: a verification-methodology class (an absolute floor in the checker) | T6r_numerics | [R6-numerics-verify] | INPUT |
| R6-18 | E40 post-fusion: the PROMPT-6 bound on the measured cells (123 700 / 101 284, 331 600 / 241 936, 2 396 400 / 1 679 088 ns) is unchanged, +800 / +1 900 on the amortized 32k cell; the session-3 stream phase = 81.5 % of the deferred cell (82.1 % of the unguarded) | T6r_e40_amort (+ T40_prize_*) | [R6-e40] | PROVED; reaching it: EMPIRICAL — E40a / E40b |
| R6-19 | the session-4 "spurious fold misread under the PV flow" closed as a test-harness artifact (the identity gate repacked the shared arenas before the timing cell); the deferred guard exact and deterministic (12/12 matrix, stress) | — | — | INPUT (session 5) |
| R6-20 | the ladder: E39 RESOLVED, E35 device half CLOSED, E41 new (the deferred kernel's phases, t = 4 / 16 and a 4k cell); order E40a → E41 → E40b → E35 (model half) → E27′ (sink) → E25; risk rows (trip rate, adversarial inputs, the two numerics classes, the mixed-session floors, the netted match) | — | — | DEFINITION (ladder / risk structure); EMPIRICAL — E40a, E41, E40b |

**Coverage, round 6: 20 rows, 18 with a theorem (90 %); the 2 without (R6-19, R6-20) are a measurement statement used as given and the
ladder structure. 0 orphans — every `T6r_*` theorem of attn.lean is cited above (T6r_cells, T6r_vs_round5, T6r_amort, T6r_trip_breakeven,
T6r_trip_premise, T6r_adversarial, T6r_base, T6r_fold, T6r_e39, T6r_perblock, T6r_layer_fractions, T6r_fleet_moe_128k,
T6r_fleet_moe_128k_eff, T6r_fold_bound, T6r_numerics, T6r_e40_amort), and every `[R6-*]` label family of attn.py is cited.** Status summary:
**MEASURED** — the three trip-free cells, the amortized band (as quoted; reproduced from two measured cells), the legacy / guard-off /
canonical cells at 32k, the 1M adversarial and legacy cells (as quoted), the planted-delta trip counts, the two numerics classes and their
counts, the harness-artifact closure; **DERIVED** — every other number of the section; **UNMEASURED** — the trip rate per (model, L), the
fold / end-read split, the session-5 phase split (E41), the deferred kernel below 32k and at t ≥ 4 (E41), φ (E40a). The rounds-2 … 5 and
PROMPT-6 ledgers below are unchanged.

## PROMPT-6 (2026-11-08) — the errata #18–#31 audit cells and the E40 stage-overlap pre-design

PROMPT-6 audits DESIGN-3 against errata #18–#31 (with the corrected #3 and the widened #25) and pre-designs E40. No new silicon claims.
Labels `[PA-*]` (the audit cells) and `[E40-*]` (the pre-design) are printed by `python3 -I proof/attn.py` after the `[R5-*]` block (the
first 913 output lines — every round-2 … round-5 line — are byte-identical: `diff` of the two outputs is exactly the new block); theorems
`T6a_*` and `T40_*` are the last section of `proof/attn.lean` (namespace `Audit6`). Inputs: the session-3 phases (`Measured5`) and the
session-5 deferred-guard cells of HW-MAP (MEASURED: 945.5 / 3 618.8 / 28 694.0 µs trip-free at 32k / 128k / 1M; guard-off 902.9, legacy
1 514.9, amortized 946.3–947.4 µs at 32k). The per-design tables of the audit are ERRATA-IMPACT.md.

### Build status, PROMPT-6

| Item | Result |
|---|---|
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 20 s |
| `cd proof && lake build` | **succeeds** (all six targets; the one linter warning is smoke.lean's, pre-existing) |
| Theorems in attn.lean | **350** = 292 (rounds 2–5, kept byte-identical) + **58** PROMPT-6 (`T6a_*` 4, `T40_*` 54) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` over the 58: 12 depend on no axiom, 4 on `propext` + `Quot.sound`, 42 on `propext` + `Classical.choice` + `Quot.sound` (the `omega` / `simp` standard set) |
| New namespace | `Audit6` (the deferred cells, `ivl` / `sumD` / `sumW` — the barrier-interval schedule — `e40`, `floorF1`, `floorF2`, `xDet`) |
| `python3 -I proof/attn.py` | 913 lines unchanged + 29 lines (`[PA-*]` 7, `[E40-*]` 22) |
| Cell theorems | generated from attn.py's own values (scratch `gen_lean6.py`) — no hand-typed cell; the 36 φ-line theorems are ∀ φ iffs |

### Cells the audit moves (DERIVED rows of rounds 4–5; no MEASURED cell moves)

| Row | Was | Now | Why | Theorem |
|---|---|---|---|---|
| R4-4 (S1 P ring) | 2 × 4 KiB·mt = 8 / 16 / 24 / 32 KiB, slots 4 KiB apart | **64 / 128 / 192 / 256 KiB** at 32-KiB-granular slots (or one 4 KiB piece at offset 0 per lift) | #25: plain-copy dst offsets ≥ 4 KiB corrupt; only offset-0 4-KiB blocks and 32-KiB-granular offsets are proven | T6a_s1_pring |
| R4-10 (first-block max, fixed cost) | 5 200 ns; fixed 19 328 ns | **19 890 ns; fixed 34 018 ns** (DERIVED — superseded at the cell level by the measured sweep) | #29 / #31: the 16 maxima reach the Duplicate operands as scalars; the deterministic path is 16 scalar-destination reduces (17 600 ns) | T6a_firstmax_det |
| R5-10 (rowmax crossing) | ≥ 10 318 ns per block → ≥ 1 599 152 ns at 32k | the bound stands; **the deterministic crossing is 17 600 ns → ≥ 2 065 200 ns at 32k (65.0 GB/s), ≥ 63 964 800 at 1M** | #31: the cheaper composition (a drain + 16 scalar reads of fresh maxima) races | T6a_rowmax_det |
| R4-22 (vector tail) | 4 156 ns at t = 1 (16-row Muls + Adds) | the form **VIOLATES #22** (a unary Muls); its Duplicate repair = 4 096 small calls = 190 054 ns at A3; the fix is the padded matrix-path tail (≈ 720 ns, UNMEASURED) | #22 | T6a_tail_dup |
| R5-8 / R5-9 (the batched guard, E39) | fused = unguarded + one crossing (958.8 µs) | E39 as specified is **killed** (#31, session 4); the shipped deferred guard is MEASURED (945.5 µs) — round 6 (PROMPT-3R6) folds it | #31 | — (INPUT) |

### The PROMPT-6 ledger (every `[PA-*]` / `[E40-*]` label and every PROMPT-6 claim of DESIGN-3.md)

| # | Claim (PROMPT-6 text: banner, §3.2, §3.4, §4, §5.1, §8, §9, §10, App. A) | Proof | labels | Status |
|---|---|---|---|---|
| PA-1 | the rowmax chain's deterministic crossing: 16 × 1 100 = 17 600 ns per block > the round-5 bound 10 318; rowmax ≥ 938 800 + 64 × 17 600 = 2 065 200 ns (65.0 GB/s) at 32k, ≥ 27 920 000 + 2 048 × 17 600 = 63 964 800 at 1M; both above the guarded cells | T6a_rowmax_det | [PA-rowmax-det] | PROVED (the 1.1 µs call: INPUT #29; the racing verdict: INPUT #31) |
| PA-2 | first-block max on the deterministic path 5 200 − 2 910 + 17 600 = 19 890 ns; the round-4 fixed cost 19 328 → 34 018 ns | T6a_firstmax_det | [PA-firstmax-det] | PROVED; CORRECTION of R4-10's derived cell |
| PA-3 | the S1 P ring at 32-KiB granularity: 2 × mt × 32 KiB = 64 / 128 / 192 / 256 KiB ≤ 1 MB; every slot offset j·32 768 ≡ 0 (mod 32 768) (∀ j); the round-4 ring's second slot sat at 4 096·mt | T6a_s1_pring | [PA-s1-pring-mt*] | PROVED (S1 size: PRIOR); CORRECTION of R4-4 |
| PA-4 | the vector tail's Duplicate repair: 2 × 16 × 128 = 4 096 calls × 46.4 ns = 190 054 ns per step vs the 4 156 ns tail term; the matrix-path tail 585 + 9 × 15 = 720 ns | T6a_tail_dup | [PA-tail-dup] | PROVED (arithmetic); the matrix-path tail's cost: EMPIRICAL — E25 / E40b |
| PA-5 | E39 as specified (per-block flag lanes from fresh reduce calls, read at a crossing) is the racing composition; the deferred guard (a vector-only fold, ONE end-of-step read, a whole-step re-run) replaces it | — | — | INPUT (#31; HW-MAP session-4 / -5 rows) |
| PA-6 | the placements without a number: #18 on every L0 operand; #20 / #25 on the q staging and on the P staging form (§10.11); #21 in the harness and E23's period 15; #22 on out = O/S; #23 the K-append strides as gaps; #24 the tail / q / out copies; #26 the page-table nests; #27 the drain form; #28 the arm discipline; #30 the passes, the trip re-run and the H_kv = 1 split; corrected #3 (R_vec, E22, the §9 compliance row) | — | — | DEFINITION (design rules; ERRATA-IMPACT.md) |
| E40-1 | the barrier-interval schedule, ∀ interval lists: Σ d ≤ Σ max(d, w) and Σ w ≤ Σ max(d, w); Σ max(d, w) ≤ Σ d + Σ w; Σ d + (Σ w − Σ d) ≤ Σ max(d, w); Σ max(d, w) = Σ d **iff** every w ≤ d | T40_ivl_lower, T40_ivl_upper, T40_ivl_excess, T40_ivl_floor_iff | (structure) | PROVED (∀ l); the interval model (a full barrier waits for every pipe): INPUT #14 + DEFINITION |
| E40-2 | T_E40 = floor + nb·((V − k·d)⁺ + k·φ) + τ + nx·cx ≥ floor + nx·cx (∀); = floor + τ + nx·cx **iff** V ≤ k·d ∧ φ = 0 (nb, k > 0); < T_b **iff** nb·k·φ < T_b − (floor + nb·(V − k·d)⁺ + τ + nx·cx); monotone in φ; a per-block crossing X adds nb·X | T40_gain_le, T40_reach_iff, T40_pays_iff, T40_mono_phi, T40_crossing_serial | (structure) | PROVED (∀ inputs) |
| E40-3 | inputs: serial sums 1 513 100 / 938 300 ns; fold + end read = 945 500 − 902 900 = 42 600 ns per step; per tile 770 800 / 512 = 1 505 (F1), 12 394 / 8 = 1 549 (F2); softmax 69 500 / 64 = 1 085; fold 665 / 509 / 353 at an end read of 0 / 10 / 20 µs; merge 357 (round-4 lazy-T model); V ∈ [1 438, 2 107] ≤ 2 d; V > d at the full fold | T40_inputs | [E40-inputs] [E40-tile] [E40-vec] | INPUT (sessions 3 and 5) + PROVED; the split: UNMEASURED |
| E40-4 | floors F1 = 821 800 / 3 287 200 / 26 297 600 ns (163.3 GB/s), F2 = 844 216 / 3 376 864 / 27 014 912 (159.0); the deferred cells 142.0 / 148.4 / 149.7 GB/s | T40_floor | [E40-floor-*] | PROVED (a mixed-session reading: the floors from session 3's stream phase) |
| E40-5 | the reachable-overlap bound on the deferred kernel (φ = 0, τ = 0, V ≤ k·d): 32k 123 700 / 113 700 / 103 700 ns (F1; 13.1 / 12.0 / 11.0 %) and 101 284 / 91 284 / 81 284 (F2; 10.7 / 9.7 / 8.6 %); 128k 331 600 … 221 936 (9.2 … 6.1 %); 1M 2 396 400 … 1 659 088 (8.4 … 5.8 %); × 28 MoE layers: 3 463 600 / 2 835 952 (32k), 9 284 800 / 6 774 208 (128k; round 5's 7 462 000 at the unguarded reading), 67 099 200 / 47 014 464 ns (1M) | T40_prize_32k, T40_prize_128k, T40_prize_1M | [E40-prize-*] | PROVED; reaching it: EMPIRICAL — E40a, E40b |
| E40-6 | the φ lines, ∀ φ: E40 beats 945 500 ns iff φ ≤ 966 / 888 / 810 (F1, k = 2, end read 0 / 10 / 20 µs), 791 / 713 / 635 (F2); k = 1: 1 330 … 1 687 (F1), 1 024 … 1 381 (F2); k = 8: 158 … 241 — at every consistent (fold, read) split and merge 0 / 357 | T40_phi_* (36 theorems) | [E40-phi-32k-F1] [E40-phi-32k-F2] | PROVED (∀ φ); φ: UNMEASURED — E40a |
| E40-7 | the gate: the most tolerant consistent cell needs φ ≤ 1 687 ns; erratum #29's crossing (10 000–20 000 ns) is 5.9–11.9× above it | T40_phi_gate | [E40-phi-gate] | PROVED; whether φ is crossing-class: EMPIRICAL — E40a |
| E40-8 | the phase-delta form: (c + v + p) − (s + b) − serial crossings = 1 513 100 − 821 800 − 574 800 = 116 500 (legacy) and 938 300 − 821 800 = 116 500 (unguarded) = 12.4 % of 938 300 | T40_phases | [E40-phases] | PROVED (re-instantiated by the next session's phase deltas) |
| E40-9 | on the legacy scan: floor + nb × guard = 821 800 + 574 800 = 1 396 600 ns (96.1 GB/s), 47.7 % slower than the deferred kernel run serially | T40_phases | [E40-legacy] | PROVED |
| E40-10 | the budgets: L0C with double-buffered C_o 160 / 320 / 240 / 320 KiB (fits at mt = 1, 3); US + a second drained C_s 157 760 / 254 016 / 243 776 / 266 304 B vs the 212 992 B evidence (fits at mt = 1); S1 P slots for two blocks at 32-KiB granularity 256 / 512 / 384 / 512 KiB ≤ 1 MB; vector fit 10 535 / 5 267 / 1 505 / 1 128 ns per fragment | T40_buf | [E40-buf-mt*] | PROVED (S1: PRIOR; US: the ≥ 208 KiB evidence) |
| E40-11 | the trip re-run: amortized +800 … +1 900 ns at 32k, ≤ 0.22 % of the cell | T40_trip | [E40-trip] | INPUT (session 5) + PROVED |
| E40-12 | the schedule (§5.1 (c)) and the barrier plan (§5.1 (d)): every edge ≥ one interval after its producer → zero added full barriers; one B ping-pong state; one arm per handshake; zero per-block scalar reads; the deferred guard's single end-of-step read; bit-identity with the serial kernel's output | — | — | DEFINITION (structure); EMPIRICAL — E40b |

**Hypothesis variables, PROMPT-6:** φ (per vector-carrying barrier, UNMEASURED — E40a), k (vector-carrying intervals per block), the
(fold, end read) split of the session-5 42.6 µs (end read ≤ 20 µs by #29's band), τ (the exposed prologue / epilogue), the merge
(0–357 ns per block). **Coverage, PROMPT-6:** 18 / 18 rows resolved — 13 with theorems (9 of them universally quantified), 1 INPUT,
4 DEFINITION / EMPIRICAL; **0 orphans** — every `T6a_*` / `T40_*` theorem is cited above and every `[PA-*]` / `[E40-*]` label family is
cited. The round-2 … round-5 ledgers below are unchanged.

## Round 5 (2026-11-07) — the measured production kernel folded in (attention session 3, HW-MAP 62e8137, errata #29–#30)

Round 5 replaces the model's assumed inputs with the measured kernel, re-derives the affected cells and corrects the chain-cost premise
that erratum #29 refutes. Labels `[R5-*]` are printed by `python3 -I proof/attn.py` after the `[R4-*]` block (the first 869 output lines —
every round-2, round-3 and round-4 line — are byte-identical: `diff` of the two outputs is exactly the `[R5-*]` block) and by
`python3 -I proof/fleet.py` after `[R3P-*]` (the first 628 lines byte-identical); theorems `T5r_*` are the last section of
`proof/attn.lean` (and of `proof/fleet.lean`, PROOF-COVERAGE-4.md). Status words this round: **MEASURED** (= INPUT: an attention-session-3
number used as given, or session 2 where named), PROVED / **DERIVED** (a theorem from measured inputs), **UNMEASURED** (carried with an
explicit variable or as a bound, with a ladder row), CORRECTION, EMPIRICAL — Ex.

### Build status, round 5

| Item | Result |
|---|---|
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 8 s |
| `cd proof && lake build` | **succeeds** (all six targets) |
| Theorems in attn.lean | **292** = 265 (rounds 2–4, kept byte-identical) + **27** round 5 (`T5r_*`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` over the 27: 18 depend on no axiom, 8 on `propext` + `Quot.sound`, 1 on `propext` (the `omega` / `simp` standard set) |
| New namespaces | `Measured5` (the t × L sweep, the unguarded cell, the guard readings, erratum #29's two constants, the bounce, the per-engine phases, the drift, the 5 % line), `Design5` (`nb5`, `guardTab`, `guard5`, `bounce5`, `stream5`, `ung5`, `xing`, `fused5`, `overlap5`, `xRowmax`, `chord`, `x10r`) |
| `python3 -I proof/attn.py` | 869 lines unchanged + 44 lines (42 `[R5-*]` labels); `python3 -I proof/fleet.py` 628 unchanged + 41 lines (39 `[R5-*]` labels); `proof/alt.py` output unchanged |
| Cell theorems | generated from attn.py's own values (`gen_attn5.py`, scratch) — no hand-typed cell |

### The moved cells (round 4 → round 5; `[R5-moved]`, T5r_moved)

| Cell | Round 4 (lazy-T, legs 2, 169.2) | Round 5 | Status | Theorem |
|---|---|---|---|---|
| t = 1, 32k | 912 µs (DDR-bound) | **1 513.6 µs guarded** / 938.8 unguarded / 958.8 fused | M / M / D (target, E39) | T5r_meas_t1, T5r_readings |
| t = 1, 4k / 128k / 1M | 131 / 3 589 / 28 575 µs | **213.5 / 5 852.9 / 46 313.6** guarded; 141.7 / 3 553.7 / 27 920.0 unguarded | M / D (per-block guard off 32k UNMEASURED) | T5r_meas_t1, T5r_readings |
| effective KV, t = 1 | 128.2 / 147.2 / 149.6 / 150.3 GB/s | **78.6 / 88.7 / 91.7 / 92.7** (guarded) | M (88.7 vs the quoted 88.6: floored display) | T5r_meas_t1 |
| t = 4 / t = 16 at 32k | 1 030 / 2 565 µs | **2 695.6 / 10 741.7** (2.6× / 4.2×) | M | T5r_meas_t4, T5r_meas_t16 |
| binding at t = 1 | KV stream (9.2 µs of vector slack per block) | **the serial chain** (phases sum to the total; stream 50.9 % / 82.1 % busy) | D | T5r_engines |
| the guard's cost | 1 455 ns + a fence < 1 µs, hidden in DDR slack → 0 on the cell | **8 981 ns per block, serial: 574.8 µs at 32k** | M | T5r_guard, T5r_A5_refuted |
| the bounce at 32k | 99 136 ns (legs 2 on the roof) | **≈ 51 000** (legs 2, measured) | M | T5r_validate_terms |
| rowmax cells (32k) | 917 µs | **≥ 1 599 µs** (≥ one crossing per block) | D bound (structure UNMEASURED) | T5r_rowmax_bound |
| switch-to-rowmax worst case | +32 µs + the rowmax cells (917 µs) | **void** (never cheaper than staying) | D | T5r_switch_void |
| KV-int8 (rowmax), 32k | 651 µs | **≥ 1 311 µs** | D bound | T5r_rowmax_bound |
| L_eq (one 398 µs GEMV unit) | 14 336 (512-multiples) / 13 841 (every L) | **every L ≥ 7 697 guarded / ≥ 13 329 unguarded** (chord) | D (interpolation UNMEASURED) | T5r_chord_*, T5r_nb_lines |
| × GEMV, t = 1 | 0.33 / 2.29 / 9.02 / 71.8 | **0.54 / 3.80 / 14.7 / 116.4** | M | T5r_meas_t1 |
| MoE-128k (DESIGN-4) | attention-bound at every G ≤ 174.6 (line 189.4) | attention-bound by **82.5 / 10.8 / 11.4 %**; stream-only line **178.7**; G_eff line 167.3 | D (∀ G) | T5r_fleet_moe_128k_* |
| drift at 1M | 246 ppm (deterministic bound) | **1.2 ppm measured** (E26′ closed) | M (session 2) | T5r_drift |

### Corrections forced by the measurements (round 4 → round 5)

| # | Where | Round 4 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §3.2 / §3.4 cost premise, A5 | per-block scalar reads ≈ free; the guard's fence < 1 µs and hidden in DDR slack | **erratum #29: any per-block crossing drains the vector pipe ~10–20 µs; the shipped guard costs 8 981 ns per block, serialised (8.9× A5's ceiling)**; the chain cost becomes max(stream, lane work) + ⌈nb/K⌉·cx | session 3 (T5r_guard, T5r_A5_refuted, T5r_xing_*) |
| 2 | §6.1″ mechanism | DDR-bound, the chain hidden in 9.2 µs of slack per block | **the phases serialise** guarded (1 513.1 vs 1 513.6 µs) and unguarded (938.3 vs 938.8); the 3.0 % cell-level match nets −97.7 / +48.1 / +22.4 µs term errors | session 3 per-engine split (T5r_engines, T5r_validate_terms) |
| 3 | §6.1″ headline | 912 µs at 32k (legs 2) | **1 513.6 µs guarded (M)**; 938.8 unguarded (M) = the 912 cell + 3.0 % | session 3 (T5r_validate) |
| 4 | §2.2 bounce term | legs 2 on the DDR roof: 99 136 ns at 32k | **≈ 51 000 ns measured (51.4 %)** — legs = 2 confirmed, its cost halved | session 3 (T5r_validate_terms, T5r_overlap) |
| 5 | §6.2″ / §7 t ≥ 4 regime | t = 4 1 030 µs (KV-bound), t = 16 2 565 (vector-bound); rows* = 64 | **2 695.6 / 10 741.7 µs**: the guarded kernel costs ≈ 20.3–24.0 µs per fragment per 512 tokens at every fragment count — no stream amortisation | session 3 (T5r_meas_t4/t16, T5r_per_fragment) |
| 6 | §3.4 (e) switch policy | after 3 trips finish on rowmax: worst case 917 µs at 32k | **void**: rowmax pays ≥ 10 318 ns of crossings per block > the shipped guard's 8 981 (∀ r blocks) | erratum #29 (T5r_switch_void, T5r_rowmax_bound) |
| 7 | §3.4 KV-int8 | rowmax 651 µs, vector-bound | **≥ 1 311 µs** (the per-block crossing) — above the fused f16 lazy target (958.8) | erratum #29 (T5r_rowmax_bound) |
| 8 | HW-MAP quote (not edited) | 32k effective KV 88.6 GB/s | **88.7** at round-half-up (88.67; the quote is the floored tenth); t ≥ 4 "99.6–103.4" is per fragment-pass and covers L ≥ 32k only (4k: 87.8 / 90.6) | T5r_meas_t1, T5r_meas_t4, T5r_meas_t16 |
| 9 | steering figures (PROMPT-3R5) | "guard fusion worth ~570 µs at 32k"; "fused target ≈ 140" | consistent once read together: **574.8 µs is the zero-residual ceiling; 140.0 GB/s = the unguarded kernel + one 20 µs crossing per step, worth 554.8 µs** (564.8 at 10 µs); the quoted +572 µs and the table difference 574.8 µs are 0.5 % apart | T5r_guard, T5r_fusion_32k, T5r_crossing_cells |
| 10 | §6.3 crossover | L_eq 14 336 / 13 841 at 169.2 with the bounce | **≈ 7 697 guarded / 13 329 unguarded** on the chord between the measured 4k and 32k cells | T5r_chord_*, T5r_nb_lines |
| 11 | ladder statuses | E24′ / E26′ / E28 / E36 open; E35 open; E27′ open | **E24′, E26′, E28, E36 CLOSED; E35 device half RESOLVED (model half open); E27′ causal half CLOSED (sink open)**; new E39 (batched guard), E40 (phase overlap) | session 2 / 3 |

Not corrections (survivals): the round-4 legs-2 cell at 32k (validated, 3.0 % ≤ 5 %); legs = 2 as the planner's reading (measured); the
online two-level chain ships at 1M (now measured, 205× inside its bound); the MoE-128k cell attention-bound at every G ≤ 174.6 (now with the
measured bounce, line 178.7); fresh chunk sets, the C_o nesting, the page maps, the buffer budgets (no round-5 input touches them).

### The round-5 ledger (every `[R5-*]` label and every round-5 claim of DESIGN-3.md)

| # | Claim (round-5 text) | Proof | labels | Status |
|---|---|---|---|---|
| R5-1 | the t × L sweep: t = 1 213.5 / 1 513.6 / 5 852.9 / 46 313.6 µs, t = 4 382.1 / 2 695.6 / 10 514.3 / 83 123.1, t = 16 1 481.4 / 10 741.7 / 42 013.4 / 332 476.2; 8 / 64 / 256 / 2 048 blocks; 26 687 / 23 650 / 22 862 / 22 614 ns per block at t = 1; × GEMV 53.6 / 380.3 / 1 470.6 / 11 636.6 %; measured ÷ round 4 1.6–1.7× / 2.4–2.6× / 3.9–4.2× | T5r_meas_t1, T5r_meas_t4, T5r_meas_t16 | [R5-meas-*] | **INPUT (session 3)** + PROVED (the readings) |
| R5-2 | effective KV: t = 1 78.6 / 88.7 / 91.7 / 92.7 GB/s (the quoted 88.6 is the floored tenth, 88.67); t ≥ 4 per fragment-pass ((rows/16)·KV / T) 87.8 / 99.6 / 102.1 / 103.3 and 90.6 / 100.0 / 102.2 / 103.3 — the quoted 99.6–103.4 covers L ≥ 32k | T5r_meas_t1, T5r_meas_t4, T5r_meas_t16 | [R5-meas-eff-check] | PROVED (display CORRECTION 8) |
| R5-3 | **VALIDATION (INPUT row):** unguarded 938 800 ns vs the round-4 legs-2 cell 911 680 ns: +27 120 ns = 3.0 % of the exact cell, 2.9 % of the displayed 912 µs; ≤ the 5 % match line (≤ 45 584 ns); 143.0 GB/s | T5r_validate | [R5-validate] | **INPUT** (the PROMPT-3R5 validation row) + PROVED |
| R5-4 | the term-level reading: model 793 216 + 99 136 + 19 328 = 911 680; measured 770 800 (174.1 GB/s) + ≈ 51 000 + 117 000 = 938 800; offsets +22 416 / +48 136 / −97 672 (net −27 120); the bounce 51.4 % of the modelled charge | T5r_validate_terms | [R5-validate-terms] | PROVED (from INPUT terms) |
| R5-5 | the phases serialise: 523.9 + 644.3 + 344.9 = 1 513.1 µs vs 1 513.6 (0.03 %); stream 50.9 % busy (49.1 % idle by the split; quoted ≈ 47 %); without the guard 938.3 vs 938.8, stream 82.1 % busy; per block 8 185 / 10 067 / 5 389 ns; softmax w/o guard 1 085 ns per block vs 3 317 modelled (3.0×) | T5r_engines | [R5-engines], [R5-engines-unguarded] | INPUT + PROVED (premise: the guard lies in the softmax+guard phase) |
| R5-6 | the guard: 574 800 ns (table difference; quoted 572 000, 2 800 = 0.5 % apart), 8 981 ns per block (8 937 quoted), 8 × 1 100 = 98.0 % of it; 61.2 % of the unguarded / 38.0 % of the guarded cell; tree + queue 19 531 per block (in the 10–20 µs band), tree + barrier 21 875 (above), +675 200 / +825 200 over shipped | T5r_guard | [R5-guard], [R5-guard-alt] | INPUT + PROVED |
| R5-7 | A5 refuted: the round-4 guard (1 455 ns + a fence < 1 µs, inside 9 171 ns of DDR slack) → 8 981 ns serial per block (8.9×) | T5r_A5_refuted | [R5-A5-refuted] | CORRECTION (A5 → INPUT) |
| R5-8 | the batched-crossing model xing(nb, K, cx) = ⌈nb/K⌉·cx: one crossing per step = cx (∀ 0 < nb ≤ K); per block = nb·cx (∀ nb); at 32k fused = 938 800 + cx and guard fusion = 574 800 − cx (∀ K ≥ 64, cx ≤ 574 800); cells K = 1 / 8 / 64 at cx = 10 / 20 µs: 85.0 / 60.5, 131.7 / 122.1, 141.5 / 140.0 GB/s | T5r_xing_once (∀), T5r_xing_every (∀), T5r_fusion_32k (∀ K, cx), T5r_crossing_cells | [R5-crossing-K*] | PROVED ∀ (the batched kernel: **UNMEASURED**, E39) |
| R5-9 | "fused target ≈ 140" = unguarded + one 20 µs crossing per step = 958 800 ns = 140.0 GB/s (141.5 at 10 µs); "~570 µs" = the zero-residual ceiling 574 800; the side-product (≤ 93.1 µs at 32k at the round-4 convention) and the re-run (≤ 0.22 % of a step at the measured trip rate) carried as risks | T5r_fusion_32k, T5r_crossing_cells | [R5-crossing-target] | PROVED (target UNMEASURED; side-product, re-run: UNMEASURED, E39) |
| R5-10 | rowmax under erratum #29: ≥ 10 318 ns per block (min(16 × 1 100, 10 000 + 16 σ_s)); ≥ 1 599 152 ns at 32k (83.9 GB/s) > 1 513 600; ≥ 49 051 264 at 1M > 46 313 600; the switch policy void ∀ r | T5r_rowmax_bound, T5r_switch_void (∀ r) | [R5-rowmax-bound] | PROVED (crossing structure UNMEASURED: lower bound) |
| R5-11 | KV-int8 on rowmax ≥ 1 311 142 / 41 207 398 ns (32k / 1M) > the fused f16 958 800; μ = 0 the only crossing-free KV-int8 route | T5r_rowmax_bound | [R5-rowmax-i8] | PROVED (bound); μ = 0 trip rate: EMPIRICAL — E35 |
| R5-12 | readings per L: guard5 71 850 / 574 800 / 2 299 200 / 18 393 600; unguarded 141 650 / 938 800 / 3 553 700 / 27 920 000 ns (118.4 / 143.0 / 151.1 / 153.8 GB/s); fused 161 650 / 958 800 / 3 573 700 / 27 940 000 (151 650 … at 10 µs); constant-rate bracket 117 323 / 938 585 / 3 754 342 / 30 034 736 and 119 837 / 958 698 / 3 834 792 / 30 678 337; ÷ round 4 108.2 / 103.0 / 99.0 / 97.7 % | T5r_readings | [R5-ung-*] | PROVED (32k: M; the per-block guard off 32k: **UNMEASURED**) |
| R5-13 | the overlapped floor (stream + bounce, 163.3 GB/s at every L): 102 725 / 821 800 / 3 287 200 / 26 297 600 ns; the overlap gap ≤ 38 925 / 117 000 / 266 500 / 1 622 400 (27.5 / 12.5 / 7.5 / 5.8 %); the bounce removal 6 375 / 51 000 / 204 000 / 1 632 000 vs round 4's 12 392 / 99 136 / 396 544 / 3 172 352 | T5r_overlap | [R5-overlap-*] | PROVED (bound; the overlap mechanism: EMPIRICAL — E40) |
| R5-14 | t ≥ 4 per fragment per 512 tokens: 23 974 / 21 069 / 20 538 / 20 294 (t = 4), 23 237 / 20 990 / 20 516 / 20 293 (t = 16), t = 1 26 792 / 23 661 / 22 865 / 22 614 ns — fragment-serial | T5r_per_fragment | [R5-t4], [R5-t16] | PROVED (INPUT rows); the unguarded t ≥ 4 kernel: **UNMEASURED** |
| R5-15 | E26′ CLOSED: 1.2 / 1.8 ppm at 1M vs the 246 / 490 ppm bound (205× / 272×), 833× / 555× inside the 1 000 ppm line | T5r_drift | [R5-drift] | INPUT (session 2) + PROVED |
| R5-16 | E35 device half RESOLVED: the scan costs 574 800 ns at 32k, the trips ≈ free; a batched guard re-streams / re-runs on a trip (≈ 23.7 µs per block re-stream, UNMEASURED) | T5r_guard | [R5-e35] | INPUT; the trip rate per model: EMPIRICAL — E35 (model half) |
| R5-17 | the chord crossover: guarded one GEMV unit iff nb ≥ 16 (∀ nb ≥ 8) ⇔ L ≥ 7 697; unguarded iff nb ≥ 27 ⇔ L ≥ 13 329 (∀ L); 2.36 × GEMV unguarded at 32k | T5r_chord_guarded (∀ nb), T5r_chord_unguarded (∀ nb), T5r_nb_lines (∀ L), T5r_crossover_cells | [R5-gemv], [R5-crossover] | PROVED ∀ (the interpolation itself: UNMEASURED between 4k and 32k) |
| R5-18 | MoE-128k on the measured kernel: +2 645 181 / +345 981 / +365 981 ns over the 3 207 719 ns layer (82.5 / 10.8 / 11.4 %); G_eff line ≤ 167.3 (∀ G iff); with the measured bounce (204 000 ns) the stream-only line G ≤ 178.7 (∀ G iff) and attention-bound at every G ≤ 174.6 (∀ G); the overlapped floor 3 287 200 still +2.5 % | T5r_fleet_moe_128k_bounce (∀ G), T5r_fleet_moe_128k_line (∀ G, iff), T5r_fleet_moe_128k_eff (∀ G, iff), T5r_fleet_moe_128k_cells | [R5-fleet-moe-128k] | PROVED ∀ G (layer time: D4 input) |
| R5-19 | the moved cells (round 4 → round 5) | T5r_moved | [R5-moved] | PROVED |
| R5-20 | correctness settled: causal-exact 12/12 at 32k (relerr 9.8·10⁻¹¹), real-exp bad-0 through 1M, rescale-at-every-raise = the true final-m softmax; E27′'s causal half closed | — | — | **INPUT (session 3)**; the planted-sink test: EMPIRICAL — E27′ |
| R5-21 | legs = 2 MEASURED (the round-4 headline reading confirmed); E24′, E28, E36 closed | T5r_validate_terms, T5r_overlap | [R5-validate-terms] | INPUT |
| R5-22 | the interim "4k = 390–422 GB/s" is not quoted in DESIGN-3, DESIGN-4 or these ledgers (HW-MAP marks it VOID: its rung gates skipped PV + softmax) — nothing to retire | — | — | INPUT (checked by search) |

**Coverage, round 5: 22 rows, 19 with a theorem (86 %); the 3 without (R5-20, R5-21, R5-22) are measurement statements used as given
(INPUT). 0 orphans — every `T5r_*` theorem of attn.lean is cited in R5-1–R5-19 or in the corrections table, every `[R5-*]` label family of
attn.py is cited.** The status summary the round asked for: **MEASURED** — the t × L sweep, the unguarded 32k cell, the guard readings
(+572 quoted, the table difference 574.8, tree + queue, tree + barrier), erratum #29's constants (1.1 µs, 10–20 µs), the bounce (legs = 2,
≈ 51 µs), the per-engine phases, the stream-phase rate, causal-exactness, the 1M drift (session 2); **DERIVED** — every other number of the
section, each with its theorem; **UNMEASURED** — the batched guard (its crossing, side-product and re-run; E39), the phase overlap (E40), the
per-block guard off 32k (the readings' scaling rule; the constant-rate bracket beside it), the unguarded t ≥ 4 kernel, the rowmax crossing
structure (a lower bound), the KV-int8 μ = 0 trip rate, the per-model trip rate (E35's model half). The empirical residue is DESIGN-3 §8's
round-5 order: E39, E40, E35 (model half), E27′ (sink), E25.

## Round 4 (2026-11-07) — the pre-implementation review absorbed, re-grounded on kernel session 1 (HW-MAP commit 423d433, errata #18–#21)

Round 4 changes the design in three places that session 1 forced (fresh C chunks instead of accumulating regions, the P bounce, the
lazy guard's mandatory recompute), closes the review's eleven items, and marks every number by status. Labels `[R4-*]` are printed by
`python3 -I proof/attn.py` after the `[R3-*]` block (every round-2 and round-3 line prints unchanged: `diff` of the two outputs is
exactly the `[R4-*]` block) and by `python3 -I proof/fleet.py` after `[R3-*]` (likewise unchanged above); theorems `T4r_*` are the last
section of `proof/attn.lean`. Status words: PROVED, INPUT (a HW-MAP measurement used as given; "session 1" marks the kernel-session
rows), **UNMEASURED** (a quantity the model carries with an explicit variable and a ladder row), **OPEN** (a cell blocked on the
softmax-reel anomaly — modelled as specified, not modelled around), ASSUMPTION (A4, A5), DEFINITION, EMPIRICAL — Ex.

### Build status, round 4

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (elan), Lake 5.0.0 — unchanged |
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 7 s |
| `cd proof && lake build` | **succeeds** (target `Attn`) |
| Theorems in attn.lean | **265** = 199 (rounds 2–3, kept) + 66 (round 4: 54 `T4r_*` theorems + 12 helpers `chain4_rowmax`, `chain4_lazy`, `vec4_lazyT_512`, `vec4_lazyC_512`, `vec4_rowmaxT_512`, `vec4_rowmaxC_512`, `vec4_rowmaxT_256_4`, `vec4_rowmaxT_128_8`, `vec4_lazyT_256_4`, `vec4_lazyT_128_8`, `bm4_vec`, `bm4_ddr`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` over the 66 round-4 declarations: 35 depend on no axiom, 19 on `propext` + `Quot.sound`, 2 on `propext`, 10 on `propext` / `Quot.sound` / `Classical.choice` (the `omega` / `simp` standard set) |
| Measured namespace `Measured4` | the session-1 gather rates (138.3 / 138.7 / 138.0 at 256 / 128 / 64 KiB) and five DESIGN-4 memory margins (D4 inputs from fleet.py: the dense 1M KV-int8 margin, four instance-fit margins) |
| Model `Design4` | fresh chunk sets (`coSets`, `l0c4`, `l0a4`, `drain4`), the P bounce (`pBytes`, `bounceBytes`, `ddr4Block` with `legs`), the round-4 chains (`chain4Rowmax` without the Z difference, `chain4Lazy`, the itemised `merge4`, `firstMax4`), append-then-attend (`tail4Tok`, `lMatrix4`, `nblocks4`, `mask4`), `step4` / `step4H` / `step4S4` / `step4I8`, the d = 64 call counts, the online-chain lengths (`chainO`, `chainS`, `relPpm`, `errSum`), the sink (`sinkLostPpm`), the page waste, the C_o nesting (`coAddr*`), the 256 KiB page maps with inverses, the US rows (`us4`) |
| `python3 -I proof/attn.py` | 467 lines unchanged + 402 lines (400 `[R4-*]` labels); `python3 -I proof/fleet.py` 537 lines unchanged + 46 lines (45 `[R4-*]` labels) |

### The moved cells (round 3 → round 4; `[R4-moved-*]`, T4r_moved)

Headline = the lazy chain at the throughput convention on the design page (256 KiB, 169.2) with both bounce legs; "legs 0" = a proven
direct US → S1 route (the round-3 DDR model); "138.3" = the session-1 kernel loop (diagnostic).

| Cell | Round 3 | Round 4, legs 2 | legs 0 | at 138.3, legs 2 | Theorem |
|---|---|---|---|---|---|
| t = 1, 32k (lazy-T / rowmax-T) | 805 / 812 µs | **912 (+13.3 %)** / 917 | 813 / 817 | 1 111 / 1 116 | T4r_t1_32k |
| t = 1, 1M | 25 394 / 25 402 | **28 575 (+12.5 %)** / 28 579 | 25 402 / 25 407 | 34 956 / 34 961 | T4r_t1_1M |
| t = 1, 4k / 128k (lazy-T) | 110 / 3 184 | 131 / 3 589 | 118 / 3 192 | 156 / 4 386 | T4r_t1_4k, T4r_t1_128k |
| worst t = 1 corner | lazy-C +0.2 % | rowmax-C 925 (+1.5 % over lazy-T), DDR-bound | rowmax-C vector-bound at 174.6 (12 265 > 12 011) | | T4r_t1_binding |
| vector chain per 512-token block | 5 530 / 6 782 / 9 276 / 11 836 ns | 4 772 / 5 867 / 9 791 / 12 265 (OPEN) | | | T4r_chain |
| merge per block-fragment | pack 25 750 (596 ns) | 15 431 lazy (357) / 70 462 rowmax (1 631), itemised fresh-set | | | T4r_merge |
| fixed cost (lazy-T) | 11 328 | **19 328** (first-block max 5 200 + a 16-token tail 4 156) | 19 328 | | T4r_fixed |
| block DDR time at 174.6 | 12 011 | **13 512** (+12.5 %); 15 013 at mt = 2 (+25 %), 9 008 at mt = 4 (+50 %) | 12 011 | 17 059 | T4r_bounce |
| drain bytes / time per block (mt = 1) | 40 960 B / 268 ns | 65 536 B / 428 ns; hidden iff R_drain ≥ 5.5 GB/s/core (27.7×) | | | T4r_drain |
| L0C / L0A / US at mt = 1 … 4 | 112–256 / 16·mt / 208 KiB + 64 B | **128 / 256 / 192 / 256**; **12·mt**; **122 / 184 / 190 / 196 KiB + 64 B** | | | T4r_l0c, T4r_l0a, T4r_us |
| t = 4 / 8 / 16 at 32k (lazy-T) | 826 / 1 593 / 3 162 | **1 030** (KV) / 1 301 / 2 565 (vector) | 832 / 1 301 / 2 565 | | T4r_regime |
| rows* (lazy-T / rowmax-T) | 48 / 32 | **64 / 32** | 48 / 32 | | T4r_rows_star |
| S4 vs two passes, 32k | 3 777 vs 3 162 | 2 680 vs 2 565 (lazy), 13 096 vs 7 756 (rowmax) | | | T4r_t16, T4r_s4_* |
| KV-int8, 32k | 413 (lazy, DDR) / 612 (rowmax) | lazy UNREACHABLE; rowmax 651 (vector) | | | T4r_i8 |
| L_eq (512-multiples, lazy) | 16 896 at 174.6 | **14 848** at 174.6, 14 336 at 169.2, 11 776 at 138.3 | 16 384 / 15 872 / 12 800 | | T4r_crossover |
| MoE-128k (DESIGN-4) | tie: weights-bound by 0.5 % at 169.2 | **attention-bound at every G ≤ 174.6** (11.9 % at 169.2, 36.7 % at 138.3) | tie (iff G ≤ 168.3) | | T4r_fleet_moe_128k_* |
| drift bound at 1M | 2·10⁻³ deterministic (region difference), 61 ppm random walk | **246 ppm deterministic** (online chain, two-level) | | | T4r_drift_online |
| d = 64 MMA calls per block | 80 (2 × k = 32) | **48** (one k = 64 call) | | | T4r_kshape |
| page waste in the planner | none | 4 MiB per layer-sequence at 256 KiB; +1–3 ‰ of int4 share; dense 1M KV-int8 margin 1.66 → 1.59 GB | | | T4r_waste |

### Corrections forced by the review and by session 1 (round 3 → round 4)

| # | Where | Round 3 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §1.2, §7, §9 d = 64 rows, T2_d64 | "k = 64 is the illegal shape": d = 64 uses 2 × (16,16,32) accumulating calls, 80 per block, 20 %·mt | an i8 fact carried onto f16; the f16 sweep is EXACT at every k: **one k = 64 call, 48 calls per block (12.0 %)** — and it must be one call (erratum #19 forbids the accumulating pair on f16); the i8 variant keeps 2 × k = 32 | review item 1 + session 1 (T4r_kshape) |
| 2 | §3.1, §3.2 step 1, §4 NegSnap rows, T_drift_* | the region-difference epilogue with ±Q alternation; NegSnap 96 KiB in US / 144–192 KiB in S1; drift ≤ 10⁻⁴ under the random walk | **f16 accumulation into one C chunk corrupts across any barrier or re-lift (erratum #19): every chunk is fresh, C_o = one fresh set per 128-token group summed on the vector unit**; Z, ±Q, NegSnap retired; the drift theorems' mechanism cannot be built; their deterministic bounds (1 953 / 3 906 ppm) exceeded the ship line | session 1 (T4r_l0c, T4r_drift_online) |
| 3 | §2.2 copy row, §5 A5/A6 | P fragments US → S1 by plain copy (66 ns per block) | **erratum #20: the US → S1 A-slot copy delivers data ≠ source; P rides a DDR bounce** — `legs` ∈ {0, 1, 2} transfers of 16 KiB·mt per block on the DDR roof, headline 2: the t = 1 block +12.5 %·mt, 32k 805 → 912 µs | session 1 (T4r_bounce, T4r_t1_*) |
| 4 | §3.4 | the guard's recompute path described; "gated on E35" | **REQUIRED: 9 / 8 192 lanes per tripped block wrong without it** (measured); §3.4 closed (a)–(f) | session 1 + review item 3 |
| 5 | T3r_fixed, §2.2 fixed, §6.1′ lazy cells | lazy fixed cost 11 328 ns (2 vector blocks + drain) | **19 328**: + the first-block per-row max (5 200 ns) + the 16-token tail of append-then-attend (4 156); the round-3 lazy cells were 0.6 % optimistic at 32k, 4 % at 4k | review item 4 (T4r_fixed, T4r_firstmax) |
| 6 | §0 route 1b, §3.3, §7, T3r_i8 | KV-int8 × lazy 413 µs DDR-bound | **unreachable as specified**: P at the fixed scale 127 assumes p ≤ 1, the lazy P reaches e⁸ (127 × 2 981 saturates i8); reachable only at μ = 0 (trip rate UNMEASURED); rowmax 651 µs vector-bound | review item 4 (T4r_i8) |
| 7 | §6.3, T3r_crossover_lazyT | L_eq = 16 896 on the lazy chain at 174.6 | 16 384 from the fixed cost alone (T3r_crossover_iff: k ≥ 32 iff fixed ∈ [13 648, 25 658], 19 328 is inside), **14 848 with the bounce**; 14 336 / 11 776 at 169.2 / 138.3 | T4r_crossover |
| 8 | §1.4, §10, T3r_fleet_moe_128k_cells | MoE-128k: a ±1 % tie, weights-bound at 256 KiB | with both bounce legs **attention-bound at every G ≤ 174.6** (the line is 189.4 > 174.6); the tie only at legs 0 | T4r_fleet_moe_128k_legs2 |
| 9 | §4 L0A row, T_buffers_l0a, review item 9 | L0A = 16 KiB·mt, exactly full at mt = 4 (unprobed) | no −Q: **12 KiB·mt, 48 KiB at mt = 4**; the 64-row pass cap now comes from L0C (mt = 5 at 256-token blocks = 320 KiB) | T4r_l0a, T4r_l0c |
| 10 | §4 US rows, T_buffers_us | 208 KiB + 64 B at mt = 1, over the evidence by 64 B; snapshots in S1 above | **122 / 184 / 190 / 196 KiB + 64 B** at mt = 1..4 (no NegSnap; 32-token tails and the mask reel added) — every mt fits | T4r_us |
| 11 | §2.2 drain row, T3r_drain_cells | 40 960·mt B per block, hidden iff ≥ 3.41 GB/s/core | **65 536·mt B** (every fresh C_o set drains): hidden iff ≥ 5.5 / 11.0 / 16.4 / 21.9; 428 / 589 / 377 / 459 ns, 13–28× under the line | T4r_drain |
| 12 | §3.1 merge, T3r_merge_item | 25 750 (pack) / 64 851 itemised with the snapshot difference | the fresh-set merge, itemised: 15 431 lazy / 70 462 rowmax (T), 30 300 / 88 372 (C); the pack figure no longer describes any chain; rowmax-C exceeds the legs-0 line (77 418) — the review's "flips vector-bound at the itemised merge" | T4r_merge, T4r_merge_threshold |
| 13 | §1.1, §10.1, T0_matrix_tail, the tail term of every t = 1 cell | tail = L mod 16 ≤ 15 (0 at 512-multiples); 16-token tails | append-then-attend: **tail = (L − t) mod 16 + t ≤ 15 + t** (31 at t = 16); 32-token tails; the per-row causal mask; every 512-multiple carries a 16-token tail at t = 1 (+4.2 µs) | review item 6 (T4r_tail_bound, T4r_tail) |
| 14 | §3.3 | "P ≤ 1 in f16 (no saturation)" was the only f16 remark | the f16 cast flushes p < 2⁻²⁴: a planted sink loses 3.1 % of its row mass at 1M; β = 3 shift offset removes it | review item 7 (T4r_sink) |
| 15 | §2.4 S4, T3r_s4_dominated_lazyT | S4 loses for every merge on both chains | on the lazy chain only for merge ≥ 640 lane-eq (below it the DDR-bound two-pass cell would lose by ≤ 30 µs); every itemisation is far above (7 014 / 9 820) | T4r_s4_dominated_lazyT, T4r_s4_cells |
| 16 | §1.2 / §1.3 bijections, §10 window | 64 KiB facts stated as the page | a 256 KiB page = four 64 KiB sub-pages; the window covers 524 288 tokens | review item 11 (T4r_page256_*) |
| 17 | fleet.py memory model | no page-waste term | 16 × (P − 256 B) per (layer, sequence): instance-fit x +1–3 ‰, dense 1M KV-int8 margin 1.66 → 1.59 GB | review item 11 (T4r_waste, `[R4-waste-*]`) |

Not corrections (survivals): T_gqa_matrix (unchanged); the page bijections (lifted to 256 KiB); T_online_exact (the merge is exact with
fresh partials too — the identity needs only multiplicativity); S4 dominated on the rowmax chain for every merge; the E21 structure
question — CONFIRMED as the i8 existence proof (HW-MAP), f16 does not inherit it (no accumulate chain is used on f16).

### The round-4 ledger (every `[R4-*]` label and every round-4 claim of DESIGN-3.md)

| # | Claim (round-4 text) | Proof | labels | Status |
|---|---|---|---|---|
| R4-1 | f16 (16,16,k) EXACT at k ∈ {16, 32, 64, 128}; d = 64: 48 / 80 / 144 calls per 512-token block (12.0 / 20.0 / 36.0 %), 96 / 160 / 288 per 256-token block at mt = 4 (48.0 / 79.9 / 143.9 %, the last MMA-bound); the i8 variant keeps 2 × k = 32 | T4r_kshape | [R4-kshape-*] | INPUT (session 1) + PROVED; issue cost at k ≠ 128: ASSUMPTION A4 |
| R4-2 | every C chunk fresh; L0C 128 / 256 / 192 / 256 KiB (exactly full at mt = 2, 4); mt = 5 at 256-token blocks 320 KiB; 1 024-token block 256 KiB; mt = 1 double-buffered sets 160 KiB; the E21 structure (i8 existence proof) CONFIRMED | T4r_l0c | [R4-l0c-*] | INPUT (session 1, erratum #19) + PROVED |
| R4-3 | L0A = 12 KiB·mt (no −Q), 48 KiB at mt = 4, mt = 5 fits L0A (60 KiB); the pass cap is L0C's | T4r_l0a (∀ mt) | [R4-l0c-*] | PROVED ∀ mt |
| R4-4 | US 122 / 184 / 190 / 196 KiB + 64 B at mt = 1..4, all ≤ 208 KiB; S1 = P ring 8 KiB·mt; DDR scratch 2 × 16 KiB·mt | T4r_us | [R4-us-*] | PROVED |
| R4-5 | drain 64 / 128 / 96 / 128 KiB per block; hidden iff R_drain ≥ 55 / 110 / 164 / 219 tenths (iff); 428 / 589 / 377 / 459 ns; margins 27.7 / 20.2 / 15.8 / 13.0× | T4r_drain (∀ R_drain, iff), T4r_drain_cells | [R4-drain-*] | PROVED ∀ R_drain |
| R4-6 | the bounce: P 16 / 32 / 32 KiB per block at mt = 1 / 2 / 4; block 12 011 / 12 761 / 13 512 (mt = 1), 15 013 (mt = 2), 9 008 (mt = 4) at 174.6 with 0 / 1 / 2 legs (+12.5 / 25.0 / 50.0 %); 13 943 / 14 127 / 17 059 / 15 340 at 169.2 / 167.0 / 138.3 / 153.8 (legs 2); i8 7 746 | T4r_bounce | [R4-bounce-*] | PROVED arithmetic; the legs count: **UNMEASURED** (E24′) |
| R4-7 | P lift density 1/16 (mt = 1), 1/4 (mt = 4) of the direct-load bytes = 2× / 8× the expert kernel's 1/32 | T4r_lift | [R4-lift-density] | PROVED; the fault class: EMPIRICAL — E24′ |
| R4-8 | fresh-set merge 15 431 / 9 820 / 7 014 / 26 654 lane-eq (lazy-T at 512 / 256 / 128 / 1024), 70 462 / 64 851 / 62 045 / 81 685 (rowmax-T), 30 300 / 88 372 chained at 512; 357 / 227 / 1 631 / 617 ns | T4r_merge | [R4-merge-*] | PROVED (itemisation: D) |
| R4-9 | the 16 chain cells 4 772 / 2 434 / 1 266 / 9 447 (lazy-T), 5 867 / 3 029 / 1 610 / 11 544 (lazy-C), 9 791 / 7 482 / 6 328 / 14 409 (rowmax-T), 12 265 / 8 784 / 7 044 / 19 226 (rowmax-C); mt = 4 at 256: 9 739 / 12 117 / 29 931 / 35 139; shares 35.3 / 39.7 … 102.1 %; per token 14.1 vs 19.1 ns at the 1 024-token block | T4r_chain, T4r_chain_shares | [R4-chain-*] | **OPEN** (softmax-reel anomaly, E36) — arithmetic PROVED |
| R4-10 | first-block max 5 200 (T) / 6 508 (C) ns at 512, 4 501 / 5 138 at 256; fixed 19 328 / 26 831 / 24 166 / 33 119 at t = 1; 71 326 / 93 704 at mt = 4; the 16-token tail 4 156 / 8 161; the mask 16 ns | T4r_firstmax, T4r_fixed | [R4-firstmax-*] [R4-fixed-*] | PROVED |
| R4-11 | the t = 1 cells: 4k 131 / 138 / 136 / 145 (169.2, legs 2) …; 32k 912 / 919 / 917 / 925, 813 … (legs 0), 1 111 (138.3), 884 (174.6), 923 (167.0), 862 (legs 1); 128k 3 589 …; 1M 28 575 …; wall, eff, × GEMV | T4r_t1_4k, T4r_t1_32k, T4r_t1_128k, T4r_t1_1M | [R4-t1-*] | PROVED (legs: UNMEASURED; G: INPUT; chain: OPEN) |
| R4-12 | binding: KV on every chain at every measured G with the bounce (slack 1 678 ns for rowmax-C at 169.2, 9 171 for lazy-T); rowmax-C vector-bound at 174.6 without the bounce (12 265 > 12 011) | T4r_t1_binding | [R4-t1-binding-*] | PROVED |
| R4-13 | the moves: lazy-T +13.3 % at 32k / +12.5 % at 1M (legs 2), +1.0 / +0.0 % (legs 0); t = 2 = t = 1 + 16 ns | T4r_moved | [R4-moved-*] | PROVED |
| R4-14 | linear forms vec4(512, 1, ·) = (19 074 176 / 22 318 208 / 35 253 504 / 44 150 016 + m)·10/43 200; (256, 4) and (128, 8) forms | vec4_lazyT_512, vec4_lazyC_512, vec4_rowmaxT_512, vec4_rowmaxC_512, vec4_rowmaxT_256_4, vec4_rowmaxT_128_8, vec4_lazyT_256_4, vec4_lazyT_128_8 (∀ m) | [R4-chain-*] | PROVED ∀ merge |
| R4-15 | t = 1 DDR-bound at 174.6 iff merge ≤ 393 019 (lazy-T) / 142 261 (rowmax-C) / 231 226 (rowmax-T) with the bounce, ≤ 328 176 / 77 418 without; the fresh-set rowmax-C merge (88 372) exceeds the legs-0 line | T4r_merge_threshold (∀ merge, iff), T4r_merge_cells | [R4-merge-threshold-*] | PROVED ∀ merge |
| R4-16 | rows* = 64 (lazy-T, legs 2) / 48 (legs 0); 32 rowmax-T; rowmax-C at mt = 1 without the bounce | T4r_rows_star | [R4-rows*-*] | PROVED |
| R4-17 | regime at 32k: 912 / 919 / 917 / 925 (t = 1, 2), 1 030 / 1 045 KV and 1 301 / 1 636 vector (t = 4), 1 301 / 1 629 / 3 908 / 4 601 (t = 8), 2 565 / 3 213 / 7 756 / 9 132 (t = 16); legs 0 at t = 4: 832 / 847; vector-bound cells bounce-independent; shares 61.6 / 104.8 / 322.0 % | T4r_regime | [R4-regime-*] | PROVED (chain: OPEN) |
| R4-18 | t = 16: two passes 2 565 / 7 756 µs vs S4 2 680 / 13 096 at 32k (+4.5 / +68.8 %), 79.9 / 245.3 ms vs 83.1 / 414.9 at 1M | T4r_t16 | [R4-t16-*] | PROVED |
| R4-19 | S4 loses to two passes for every merge on rowmax-T and for every merge ≥ 640 lane-eq on lazy-T (boundary 63 915 / 63 916 in ×100; the two-pass block is DDR-bound below 1 916 lane-eq) | T4r_s4_dominated_rowmaxT (∀ m), T4r_s4_dominated_lazyT (∀ m ≥ 63 916), T4r_s4_cells; helpers bm4_vec, bm4_ddr | [R4-s4-threshold-*] | PROVED ∀ merge (with the stated bound) |
| R4-20 | KV-int8: rowmax 651 µs / 20.1 ms vector-bound (9 791 > 7 746); lazy 515 / 15.9 ms UNREACHABLE (127 × 2 981 saturates i8) | T4r_i8 | [R4-i8-t1-*] | PROVED; μ = 0 trip rate: UNMEASURED (E35) |
| R4-21 | lazy economics: saves 5 019 ns per block; a trip 10 699; pays iff < 1 trip per 2.1 blocks; needle +685 µs at 32k / +21.9 ms at 1M; switch after 3 trips: +32 µs worst | T4r_lazy_trip | [R4-lazy-trip] | PROVED (trip rate: EMPIRICAL — E35; the guard's recompute: INPUT, session 1) |
| R4-22 | tail = (L − t) mod 16 + t ≤ 15 + t for every L ≥ t; lMatrix4 + tail = L; 31 at t = 16; 32-token tails 8 KiB; vector tail 4 156 / 9 872 / 23 900 / 64 428 ns at t = 1 / 4 / 8 / 16; mask 129 ns at t = 16 | T4r_tail_bound (∀ L t), T4r_tail | [R4-tail-*] | PROVED ∀ L, t |
| R4-23 | the planted sink: 122 / 976 / 3 906 / 31 249 ppm lost at 4k / 32k / 128k / 1M; e¹⁶ < 2²⁴ < e¹⁷ (host arithmetic); β ≤ 3 | T4r_sink | [R4-sink-*] | PROVED (the −16.6 nat line: INPUT, host arithmetic) |
| R4-24 | online-chain rounding: chains O 2 052 / S 2 062 at 1M (512), 4 098 / 4 106 (256), 1 032 / 1 046 (1 024), 68 / 78 at 32k; 246 / 490 / 125 / 10 ppm deterministic first-order, all < 1 000; single-level 489 ppm (O) / 977 (S); the region-difference bounds 1 953 / 3 906 ppm exceeded the line; n rounded adds err ≤ n × the per-add bound | T4r_drift_online, T4r_sum_error (∀ e, b, n) | [R4-drift-*] | PROVED (the per-add 2⁻²⁴ bound: INPUT, IEEE round-to-nearest; the matrix unit's internal order: UNMEASURED — E26′) |
| R4-25 | C_o nesting: 8 runs of 64 B at stride 1 024 from f·8192 + r·64; f16 32 B at stride 512 from f·4096 + r·32; m = 64 stride 4 096; injective on (f < 4, g < 8, r < 16, j < 16), < 32 KiB, 4-aligned | T4r_stride, T4r_stride_runs (∀), T4r_stride_injective (∀), T4r_stride_range (∀) | [R4-stride] | PROVED ∀; the f32 nesting itself: INPUT (session 1, E23(v)); m = 64: UNMEASURED |
| R4-26 | 256 KiB page = four 64 KiB sub-pages: range, injectivity, explicit inverses for K and V; window 524 288 tokens; cells 74 122 / 262 142 | T4r_page256_range, T4r_page256_k_injective, T4r_page256_v_injective, T4r_page256_k_inverse, T4r_page256_v_inverse (∀ l, j), T4r_page256_cells | [R4-page256] | PROVED ∀ |
| R4-27 | page waste 1 / 4 / 16 MiB per layer-sequence; 60 / 480 / 959 MiB per dense die at B = 1 / 8 / 16; 16 MiB per MoE die; 120 MiB per instance die > every margin (3.3 / 15.0 / 24.5 / 2.7 MB), 30 MiB at 64 KiB too; +3 ‰ of x; the dense 1M KV-int8 margin 1 593 887 744 B | T4r_waste | [R4-waste-*]; fleet.py [R4-waste-*] [R4-mem-*] [R4-inst-fit-*] [R4-ort-threshold-256k] | PROVED (margins: D4 inputs) |
| R4-28 | closed forms of the t = 1 lazy-T step for every L and every 0 < G ≤ 174.6 with and without the bounce | T4r_form_lazyT2, T4r_form_lazyT0 (∀ L, G) | — | PROVED ∀ L, G |
| R4-29 | L_eq: k ≥ 29 (14 848) / 32 (16 384) at 174.6 with / without the bounce, 28 / 31 at 169.2, 23 / 25 at 138.3 (iffs over k); over every L: 14 353, 15 889, 13 841 (monotone), and at 138.3 without the bounce L ≥ 12 817 ∨ (12 305 ≤ L ∧ a ≥ 15-token tail) | T4r_crossover (∀ k, iff), T4r_crossover_cells, T4r_crossover_anyL (∀ L, iff), T4r_crossover_anyL_cells | [R4-crossover-*] | PROVED ∀ k, L |
| R4-30 | MoE-128k: attention-bound at every G ≤ 174.6 with the bounce (line 189.4); iff G ≤ 168.3 without; cells +11.9 / +13.3 / +36.7 / +8.4 % (legs 2), +5.7 % (legs 1 at 169.2), −0.5 / +0.8 / +21.6 / −3.5 % (legs 0); fleet.py: 1.155 vs 1.217 tok/s/card at 169.2 | T4r_fleet_moe_128k_legs2 (∀ G), T4r_fleet_moe_128k_legs0 (∀ G, iff), T4r_fleet_moe_128k_cells | [R4-fleet-moe-128k-*]; fleet.py [R4-moe-128k-*] [R4-G-param] [R4-step-*] [R4-attn-*] [R4-spec-*] [R4-dense-1M-kvi8] | PROVED ∀ G (layer time: D4; G, legs: INPUT / UNMEASURED) |

**Coverage, round 4: 30 rows, 30 with a theorem (100 %); 29 PROVED (12 universally quantified over merge, R_drain, mt, L, G, k, t, the
page coordinates, the error sequence), 1 row (R4-9) PROVED as arithmetic but OPEN as a design number; 0 orphans — every `T4r_*` theorem and
helper is cited in R4-1–R4-30 or in the corrections table, every `[R4-*]` label family of attn.py and fleet.py is cited.** The status
summary the round asked for: MEASURED (session 1) — the k-shapes, the f16 geometry and C nesting (E23 i / ii / v), erratum #19's fresh
chunks, erratum #20's bounce as a route, the guard's recompute, the diagnostic loop's 138.3; UNMEASURED — the bounce's cost on the DDR
roof (`legs`), the production loop's rate, the matrix unit's internal summation order, the m = 64 nesting, the issue cost at k ≠ 128
(A4), the guard's fence read (A5), the trip rate at β = 3 and μ = 0; OPEN — every vector-chain cell (E36); DERIVED — everything else,
each with its theorem. The empirical residue is the round-4 ladder of DESIGN-3 §8: E36 first, then E24′, E35, E27′, E26′, E25, E28.

**Steering note (2026-11-07, kernel session 2): the OPEN vector-chain cells
may now be read as loadable.** The softmax-reel anomaly that forced the OPEN
markers was root-caused as a host-side buffer overrun cluster (an under-sized
strip accumulator trampling the reel — errata #22-#28 in HW-MAP document the
silicon semantics found en route), not a vector-unit limitation: the full
chain is now bitwise-exact on silicon at 32k (262,144 lanes, maxRel 0.0) with
all guard tests green, and E26 is CLOSED — kernel-true f32 online-chain drift
at 1M = 1.2e-6 (512-token blocks) / 1.8e-6 (256) ≈ 500× inside the ship line.
Still genuinely open at silicon: the causal/pad mask path (unexercised — the
green runs were non-causal) and the flaky full-pipeline hang at 32k; the
`legs` and production-loop-rate UNMEASURED markers stand until the t×L sweep.


## Round 3 (2026-11-05) — re-grounding on the season (v1) measurements (HW-MAP commit e9349c8)

Round 3 adds no new design; it instantiates the round-2 model on the measured constants and proves every moved cell again.
The round-2 sections below are kept verbatim (they remain true statements about the round-2 model and its branches); this
section says which of their cells are superseded and by which theorem. Labels `[R3-*]` are printed by `python3 -I
proof/attn.py` after the round-2 labels (which still print their round-2 values, so `diff` of the two outputs is exactly the
`[R3-*]` block plus one header line); theorems `T3r_*` are the last 694 lines of `proof/attn.lean`.

### Build status, round 3

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (elan), Lake 5.0.0 — unchanged |
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 6 s |
| `cd proof && lake build` | **succeeds** (target `Attn`) |
| Theorems in attn.lean | **199** = 121 (round 2, kept) + 78 (round 3: 61 `T3r_*` theorems + `T_gqa_matrix_100` + 16 helper lemmas `chain100_rowmax`, `chain100_lazy`, `unitT16/32`, `unitC16/32`, `vec3_rowmaxT_512`, `vec3_rowmaxC_512`, `vec3_lazyT_512`, `vec3_lazyC_512`, `vec3_rowmaxT_256_4`, `vec3_rowmaxT_128_8`, `vec3_lazyT_256_4`, `vec3_lazyT_128_8`, `bm3_vec`, `bm3_ddr`) |
| `axiom` / `sorry` / `native_decide` | 0 / 0 / 0; `#print axioms` over the 78 round-3 declarations: 38 depend on no axiom, 35 on `propext` + `Quot.sound`, 2 on `propext`, 3 on `propext` / `Quot.sound` / `Classical.choice` (the `omega` / `simp` standard set) |
| Measured namespace `Measured3` | 23 constants, each with its HW-MAP row (E21 rates and per-page times at three sizes, E22 per-call latencies, c_exp, ρ32, σ_s, R_drain at mt = 1..4, the pack's merge count, the retained 3× what-if) |
| Model `Design3` | `chain100` (the measured chain: `chainRowmax` = §3.2 as specified, `chainLazy` = §3.4), two explicit modelling choices as inductives (`Var` = rowmax / lazy, `Conv` = T throughput / C chained), `vec3`, `blockMax3`, `fixed3`, `step3`, `step3I8`, `gPage3` / `gTier3` on the measured per-page base, `dotRatioT100`; the merge count stays an explicit argument |
| `python3 -I proof/attn.py` | 190 round-2 lines unchanged (one header line reworded) + 273 `[R3-*]` lines; `[R3-moved-*]` pairs every round-2 headline cell with its replacement |

### The moved cells (round 2 → round 3; `[R3-moved-*]`, T3r_moved)

Headline = the chain as specified (§3.2) at the throughput convention on the design's 64 KiB page (167.0); "174.6" = the same
W8-kernel basis as round 2; "lazy" = the fixed-shift variant of §3.4.

| Cell | Round 2 | Round 3 at 174.6 | Round 3 at 167.0 (headline) | lazy at 167.0 | Theorem |
|---|---|---|---|---|---|
| t = 1, 4k, stream / native | 103 µs | 115 (+11.4 %) | **119** (+15.6 %) | 112 | T3r_t1_4k |
| t = 1, 32k, stream / native | 776 µs | 788 (+1.5 %) | **822** (+6.0 %) | 815 | T3r_t1_32k |
| t = 1, 128k, stream / native | 3 082 µs | 3 094 | **3 233** (+4.9 %) | 3 226 | T3r_t1_128k |
| t = 1, 1M, stream / native | 24 606 µs | 24 617 | **25 736** (+4.6 %) | 25 728 | T3r_t1_1M |
| t = 1, 32k / 1M worst corner (poly, tree, ρ32 = 2; unreachable) | 851 / 26 324 | 793 / 24 622 (chained-latency corner) | **828 / 25 741** | 817 / 25 731 (lazy chained) | T3r_t1_*, T3r_worst_overrun |
| t = 1, 32k / 1M page64k (c_pg = 0.5 µs) | 904 / 28 698 | — | **822 / 25 736** (measured 64 KiB); 812 / 25 402 at 256 KiB | | T3r_t1_* |
| t = 1, 32k / 1M gather3x (c_pg ≈ 6 µs) | 2 313 / 73 803 | 2 325 / 73 814 (what-if at the measured base) | 891 / 27 943 (16 KiB, the measured worst page) | | T3r_t1_* |
| t = 16, 32k / 1M two passes native | 1 554 / 49 209 (DDR-bound) | 7 057 / 224 106 (vector-bound, G-independent) | **7 057 / 224 106** | 3 162 / 100 410 | T3r_t16 |
| S4 one pass, 32k / 1M | 1 032 / 32 388 | 11 596 / 368 280 | 11 596 / 368 280 | 3 777 / 119 944 | T3r_s4, T3r_s4_dominated_* |
| KV-int8, 32k / 1M | 391 / 12 306 (DDR-bound) | 612 / 19 016 (vector-bound) | 612 / 19 016 | 413 / 12 870 (DDR-bound) | T3r_i8 |
| fixed cost | 7 074 ns (2 × 1 489 + 4 096 drain at 10 GB/s) | 18 820 (2 × 9 276 + 268) | 18 820 | 11 328 | T3r_fixed |
| vector share of the block at mt = 1 | 12.4 % (c_V = 7) … 106.9 % | 77.2 % spec / 98.5 % chained | 73.9 / 94.3 % | 46.0 / 54.0 % | T3r_chain_shares |
| rows* (softmax ≥ stream per block) | 112 (native, ρ32 = 1) | 32 (spec, either convention) | 32 | 48 (T) / 32 (C) | T3r_rows_star |
| regime at 32k, t = 4 / 8 / 16 | 783 / 785 / 1 554 (KV) | 1 225 / 3 556 / 7 057 (vector) | same | 826 (KV) / 1 593 / 3 162 | T3r_regime |
| crossover L_eq (512-multiples) | 16 896 (k ≥ 33) | **16 384** (k ≥ 32) spec and chained; 16 896 lazy | 15 872 (k ≥ 31) spec; 15 872 lazy | | T3r_crossover_* |
| crossover over every L | 16 400 | 15 888 spec (monotone); lazy: 16 400, non-monotone from 15 888 (L mod 16 ≥ 9) | | | T3r_crossover_anyL_* |
| fleet G* MoE-128k | 167.7 | 168.3 spec / 168.6 chained / 167.9 lazy; verdict at 167.0: ATTENTION-bound | | | T3r_fleet_G_moe_128k_*, T3r_fleet_moe_128k_cells |
| drain threshold vs measured | hidden iff ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core | measured 152.8 / 222.3 / 260.3 / 285.5: hidden, 43.6× / 32.2× / 21.2× / 17.4× | | | T3r_drain_hidden, T3r_drain_cells |
| scalar tail | 512 ns (σ_s = 2 ns), 4.3 % | 5 094 ns at the measured 19.9 ns (42.4 %), replaced by 16 reduce calls = 2 910 ns | | | T3r_sigma |
| merge | 7 000 lane-ops (assumption); 12 128 itemised | 25 750 (pack) / 64 851 itemised T / 77 354 itemised C; every verdict insensitive | | 9 820 itemised | T3r_merge_item, T3r_merge_threshold_* |
| online vs two-pass | 18× (6 005 vs 324 ns) | 10.4× (6 204 vs 596) / 4.1× (vs 1 501) | | | T3r_online |
| G(P) model | t_page = P/21.825 + c_pg, c_pg ∈ {0, 0.5, 2} µs | measured T_seq(P) + c: 793 / 3 101 / 12 391 ns at 16 / 64 / 256 KiB, c = 59 / 39 / 3 ns; the 174.6 base is 3.2 % too fast for this choreography | | | T3r_E21, T3r_E21_block |
| two-tier pages (ALTERNATIVES §2.5) | −13.2 % of the step at c_pg = 0.5 µs | +1.3 % of G at the measured c_pg; ≥ 5 % iff c_pg ≥ 160 ns; dominated by 256 KiB pages | | | T3r_page_tier |
| GEMV fractions 4k / 32k / 128k / 1M | 0.26 / 1.95 / 7.74 / 61.8 | 0.29 / 1.98 / 7.77 / 61.9 | 0.30 / 2.07 / 8.12 / 64.7 | | T3r_t1_* |

### Corrections forced by the measurements (round 2 → round 3)

| # | Where | Round 2 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §0, §6.1 headline | 776 µs / 24.6 ms at t = 1 on the stream branch (174.6, c_pg = 0) | **822 µs / 25.7 ms** on the design's 64 KiB page (167.0 measured), 812 / 25.4 at 256 KiB, 788 / 24.6 at the 174.6 basis — the attention choreography streams at 169.0–169.2 (3.2 % under the W8 kernel) and the fixed cost is 18.8 µs | T3r_t1_*, T3r_E21 |
| 2 | §0, §6.1 worst corner | 851 µs (poly exp + tree max at ρ32 = 2), +9.8 % | that corner is unreachable (both native ops exist, c_exp = 11.5 ≤ every line); the new worst corner is every call at its chained latency: **828 µs, +0.6 %**; at t = 1 the chained chain is 98.5 % of the block (175 ns of slack) | T3r_cexp_clears, T3r_t1_binding, T3r_worst_overrun |
| 3 | §0, §6.2, §7 | t = 16 two passes 1 554 µs DDR-bound; verify batches DDR-bound up to t = 8 on the native corner; rows* = 112 | **7 057 µs vector-bound 4.5×**; softmax-bound from **t = 4** (1 225 µs); rows* = **32** — the per-row block max (16 reduce calls + tree + reel per fragment) does not shrink with the block | T3r_t16, T3r_regime, T3r_rows_star |
| 4 | §0, §2.4 S4 | S4 1 032 µs, 1.5× better than two passes on the native branch; "7 000 vs 12 128 vs 25 750" flagged | **S4 is dead**: 11 596 µs at the pack merge, and worse than two passes for EVERY merge count on both chains (∀-merge theorem) — the question is moot | T3r_s4, T3r_s4_dominated_rowmaxT, T3r_s4_dominated_lazyT |
| 5 | §6.3, round-2 banner | T_crossover survives: L_eq = 16 896 (k ≥ 33); any-L 16 400 | the stream basis (12 011 ns per block) is unchanged, but k ≥ 33 holds iff fixed ∈ [1 637, 13 647]; the measured chain's 18 820 gives **L_eq = 16 384 (k ≥ 32)** at 174.6 and **15 872** on the measured 167.0 / 169.0 / 169.2; any-L 15 888 (monotone); the fixed-shift variant keeps 16 896 at 174.6 and crosses at 16 400 any-L but NOT monotonically (L mod 16 ≥ 9 between 15 888 and 16 399) | T3r_crossover_iff, T3r_crossover_rowmaxT, T3r_crossover_meas, T3r_crossover_anyL_* |
| 6 | §1.4, §10, HW-MAP E21 sentence | "MoE-128k stays stream-bound at 64 KiB by 0.7 GB/s (167.0 vs the 167.7 line)"; "flips at c_pg ≥ 123 ns" | T_fleet_G_moe_128k says attention-bound **iff G ≤ 167.7**, and 167.0 is below it: the cell is **ATTENTION-bound at 64 KiB** already in the round-2 model (the bare stream 3 214 592 ns > the 3 207 719 ns layer) and on every round-3 chain (by 0.6–1.0 %); weights-bound at 256 KiB by 0.3–0.7 %; the measured 64 KiB page sits 138 ns above the 174.6 base (> 123) because the choreography gap is 99 ns of it | T3r_moe_128k_direction, T3r_fleet_moe_128k_cells, T3r_E21 |
| 7 | §1.4 G(P) table | G(64 KiB, 0) = 174.6; "3× slower" = c_pg ≈ 6 µs; page64k = 149.7 at 0.5 µs | measured 167.0 / 169.2 / 153.8 at 64 / 256 / 16 KiB; c_pg = 39 / 3 / 59 ns (lower bound); the 0.5 µs and 6 µs branches are retired to what-ifs | T3r_E21, T3r_E21_block, T3r_page_sizes |
| 8 | ALTERNATIVES §2.5 / §9 gather row | two-tier pages dominate every fixed size (−13.2 % at 0.5 µs) | at the measured c_pg two-tier gains 1.3 %, the same as 256 KiB pages without compaction; ≥ 5 % iff c_pg ≥ 160 ns | T3r_page_tier |
| 9 | §2.2 drain row, §6, §9 | R_drain assumed 10 GB/s on exposed rows; drain-on-vector corner +43.5 % | measured 152.8–285.5 GB/s/core: hidden at every mt (17–44×), both round-2 corners retired; the drain is 268 ns of the fixed cost | T3r_drain_hidden, T3r_drain_cells |
| 10 | §2.2 scalar row, §9 | σ_s = 2 ns (512 ns tail); scalar-bound iff σ_s ≥ 47 | measured 19.9 ns: the tail would be 5 094 ns (42 %); the design uses 16 reduce-max calls (2 910 ns) instead; T2_sigma's line is still clear | T3r_sigma |
| 11 | §3.1 merge, §3.1 online | 7 000 lane-ops (assumption); online wins 18× | 25 750 (pack) / 64 851 (itemised: the α reel's 20 small calls dominate); online wins 10.4× / 4.1× | T3r_merge_item, T3r_online |
| 12 | §3.2 c_V table | c_V = 7 lane-ops per (score, row) on the native corner | the measured chain is 400 731 lane-eq per 8 192-score fragment (48.9 per score effective: 11.5 exp + 5.8 tree + 15.3 reduce calls + 4.9 reel + 8.2 f32 ops + 3.1 merge) | T3r_chain, T3r_chain_shares |
| 13 | §0 route 1b, §7 | KV-int8 391 µs DDR-bound | 612 µs VECTOR-bound on the chain as specified; 413 µs DDR-bound only on the fixed-shift variant | T3r_i8 |
| 14 | §2.2 fixed, §7 launch share | fixed 7 074 ns; launch floor 88 % of the 4k step | fixed 18 820 ns; launch floor 76 % of the 119 µs 4k step, fill/tail 16 % | T3r_fixed |
| 15 | §3.2 step 2 | f32 tree with And(0x7FFFFFFF) + scalar tail | And<int32> is absent: the tree runs in f16 after a cast; the tail is 16 reduce-max calls | T3r_chain (definition `chainRowmax`) |
| 16 | §0 "no other unknown moves the headline by more than 9.8 %" | | 0.7 % (the chained corner) at t = 1; the unknowns that matter are above t = 2 | T3r_worst_overrun |

Not corrections (survivals): `T_gqa_matrix` at the measured ρ32 = 1.37 — 69.2 % of the stream at rows = 1, compute-bound for every
rows ≥ 2 (T_gqa_matrix_100 in hundredths, T3r_gqa_137, T3r_gqa_137_g); the §4 buffers (L-independent, unchanged); the page
bijections; the online-merge identity (T_online_exact holds for the fixed shift too); the E21 fleet lines for dense 32k / 128k and
MoE 32k (7.3 / 29.4 / 42.0 — 41.9 in round 2) and both 1M cells (T3r_fleet_G_*).

### The round-3 ledger (every `[R3-*]` label and every round-3 claim of DESIGN-3.md)

Status words as in the round-2 ledger; "INPUT (season v1)" marks a HW-MAP e9349c8 measurement used as given; "A3" is the one
new assumption (a 16-lane Duplicate / copy costs one chained f16 call, 46.4 ns); "T / C" is the modelling choice (throughput vs
chained convention), carried as the headline / worst-corner pair, not proved either way.

| # | Claim (round-3 text) | Proof | attn.py | Status |
|---|---|---|---|---|
| R1 | E21: shuffled − sequential = 59 / 39 / 3 ns at 16 / 64 / 256 KiB; the same pages against the 174.6 base 102 / 138 / 383 ns (138 > the 123 ns round-2 line); sequential gap 5.4 / 3.2 / 3.1 %; round-2 model G(64 KiB, 38 ns) = 172.4 would have said weights-bound; block DDR time 12 409 / 12 557 / 12 394 / 13 635 / 36 033 ns at 169.0 / 167.0 / 169.2 / 153.8 / 58.2 | T3r_E21, T3r_E21_block | [R3-E21-*] | INPUT (season v1) + PROVED arithmetic |
| R2 | units: exp 11 784 lane-eq per 1 024-lane call = 11.5 per element; reduce-max 7 858 (f16) / 10 860 (f32) per call; chained f16 op 2 004 per call = 1.96 per lane, f32 2 747 = 2.69; ρ32 = 1.37 | T3r_units | [R3-units] | PROVED (conversion of INPUTs) |
| R3 | f16 tree lane-ops 47 616 / 23 040 / 10 752 at blocks 512 / 256 / 128 (5.81 per score), = round 2's treeLaneOps | T3r_tree | [R3-tree-ops] | PROVED |
| R4 | the 12 chain cells: spec 9 276 / 6 837 / 5 618 ns (T), 11 836 / 8 100 / 6 232 (C); lazy 5 530 / 3 063 / 1 829 (T), 6 782 / 3 689 / 2 142 (C); shares 77.2 / 98.5 / 46.0 / 56.5 % of 12 011, 73.9 / 94.3 / 44.0 at 12 557, 113.9 % at the 256-token block; 8-call t = 1 variant 7 820 ns (65.1 %); the item split 161 546 / 47 616 / 125 729 / 40 089 / 25 750 | T3r_chain, T3r_chain_shares | [R3-chain-*] | PROVED (A3 for the reel; T / C: DEFINITION; c_exp, per-call ns: INPUT) |
| R5 | linear forms chain100(block, 1, merge 0) = 37 498 112 / 26 963 200 / 21 695 744 (spec T), 48 557 312 (spec C), 21 318 784 / 10 659 392 / 5 329 696 (lazy T), 26 725 504 (lazy C), and vec3 as a function of the merge | T3r_lin, vec3_rowmaxT_512, vec3_rowmaxC_512, vec3_lazyT_512, vec3_lazyC_512, vec3_rowmaxT_256_4, vec3_rowmaxT_128_8, vec3_lazyT_256_4, vec3_lazyT_128_8 (∀ merge) | [R3-lin-*] | PROVED ∀ merge |
| R6 | merge itemisations 64 851 (spec T) / 77 354 (spec C) / 9 820 (lazy T) / 19 281 (lazy C) lane-eq = 1 501 / 1 790 / 227 / 446 ns; the pack's 25 750 = 596 ns; round 2's 7 000 = 162, 12 128 = 280 | T3r_merge_item | [R3-merge-*] | PROVED arithmetic; the pack's 25 750: INPUT (commit e9349c8 message) |
| R7 | t = 1 DDR-bound at 174.6 iff merge ≤ 143 937 (spec T) / 33 345 (spec C) / 305 730 (lazy T) / 251 663 (lazy C) lane-eq; at 167.0 iff ≤ 167 524 / 56 932 / 329 317; the pack passes every line, the itemised spec-C chain exceeds its own | T3r_merge_threshold_rowmaxT, _rowmaxC, _lazyT, _lazyC, T3r_merge_threshold_167 (∀ merge, iff), T3r_merge_cells | [R3-merge-threshold-*] | PROVED ∀ merge |
| R8 | t = 1 DDR-bound iff c_exp ≤ 25.92 (spec T) / 45.67 (lazy T) / 12.42 (spec C) at 174.6, 28.80 at 167.0; the measured 11.5 clears every round-3 line and every round-2 line (56 / 51 / 24 / 19; c_V = 18 / 23 at c_exp = 12) | T3r_cexp_threshold (∀ c_exp, iff), T3r_cexp_clears | [R3-cexp-threshold-*] | PROVED ∀ c_exp |
| R9 | t = 1 cells: 4k 115 / 120 / 107, 119 / 124 / 112, 118 / 123 / 110, 128 / 133 / 120, 307 / 312 / 300 µs; 32k 788 / 793 / 780, 822 / 828 / 815, 812 / 817 / 805, 891 / 897 / 884, 2 325 / 2 330 / 2 317; 128k 3 094 … 9 236; 1M 24 617 … 73 807 (G ∈ {174.6, 167.0, 169.2, 153.8, 58.2} × {spec T, spec C, lazy T}); wall 210 / 913 / 25 827; eff 140.7 / 163.2 / 166.0 / 166.9 (170.4 / 165.3 at 174.6 / 256 KiB); × GEMV 0.30 / 2.07 / 8.12 / 64.7 | T3r_t1_4k, T3r_t1_32k, T3r_t1_128k, T3r_t1_1M | [R3-t1-*] | PROVED |
| R10 | every t = 1 cell is DDR-bound; the chained chain is under the 174.6 block by 175 ns | T3r_t1_binding | — | PROVED |
| R11 | fixed cost 18 820 / 23 940 / 11 328 / 13 832 ns (spec T / spec C / lazy T / lazy C) = 2 vector blocks + the 268 ns drain; vector tail at L mod 16 = 15: 3 896 (T) / 7 651 (C) | T3r_fixed | [R3-moved-fixed] | PROVED |
| R12 | worst-corner overrun +0.7 % / +0.6 % / +0.0 % (32k at 174.6 / 167.0, 1M); lazy = 99.0–99.1 % of the headline | T3r_worst_overrun | [R3-worst-overrun-*] | PROVED |
| R13 | t = 16 two passes: 7 057 / 224 106 (spec T), 8 360 / 265 494 (spec C), 3 162 / 100 410 (lazy T), 3 808 (lazy C) µs at 32k / 1M, G-independent (the 167.0 and 174.6 cells coincide); per 256-token block 27 350 / 12 254 ns = 455.5 / 204.1 % of 6 005; 4k 930, 128k 28 061 | T3r_t16 | [R3-t16-*] | PROVED |
| R14 | S4 one pass: 11 596 / 368 280 (spec T), 12 865 (spec C), 3 777 / 119 944 (lazy T), 4 423 (lazy C) µs; at the itemised merges 13 464 / 3 016; S4 / two-pass = 164.3 / 153.9 / 119.5 / 116.2 %; per 128-token block 44 945 / 14 638 ns against 3 002 of DDR, the 16 reduce calls alone 23 283 ns | T3r_s4 | [R3-t16-*] [R3-s4-chain] | PROVED |
| R15 | S4 loses to two passes at 32k for EVERY merge count on the chain as specified and on the fixed-shift variant (the 12 128-vs-25 750 question is moot) | T3r_s4_dominated_rowmaxT, T3r_s4_dominated_lazyT (∀ merge); helpers bm3_vec, bm3_ddr | [R3-s4-threshold-*] | PROVED ∀ merge |
| R16 | regime map at 32k (167.0): t = 1, 2: 822 / 828 / 815 / 817 KV; t = 4: 1 225 / 1 563 vector, 826 KV, 896 vector; t = 8: 3 556 / 4 212 / 1 593 / 1 919 vector; t = 16: 7 057 / 8 360 / 3 162 / 3 808; t = 2 equals t = 1; the vector-bound cells equal their 174.6 twins; shares 73.9 / 94.3 / 44.0 / 54.0, 147.7 / 188.5 / 88.1 / 108.0, 435.6 / 516.1 / 195.2 / 235.1 % | T3r_regime, T3r_regime_binding | [R3-regime-*] | PROVED |
| R17 | rows* = 32 (spec T, spec C, lazy C: mt = 2 binds, mt = 1 does not) and 48 (lazy T: mt = 3 binds, mt ≤ 2 do not); t ≥ 4 / 6 at g = 8 | T3r_rows_star | [R3-rows*-*] | PROVED |
| R18 | closed forms of the t = 1 step for every L and every 0 < G ≤ 174.6 on the three chains: nb(L)·⌊20 971 520 / G⌋ + 18 820 / 23 940 / 11 328 + the vector tail | T3r_form_rowmaxT, T3r_form_rowmaxC, T3r_form_lazyT (∀ L, G) | — | PROVED ∀ L, G |
| R19 | over the 512-multiples, k ≥ 33 (L_eq = 16 896) for every k iff the fixed cost lies in [1 637, 13 647] ns; k ≥ 32 for every k if it lies in [13 648, 25 658] | T3r_crossover_iff (∀ fixed, iff), T3r_crossover_iff_32 | [R3-crossover-iff] | PROVED ∀ fixed |
| R20 | at 174.6: spec T and spec C cross at k ≥ 32 (16 384; 403 172 / 408 292 ns there, 391 161 / 396 281 at 15 872), lazy T at k ≥ 33 (16 896; 407 691, 395 680 at 16 384) | T3r_crossover_rowmaxT, T3r_crossover_rowmaxC, T3r_crossover_lazyT (∀ k, iff) | [R3-crossover-*-stream174] | PROVED ∀ k — CORRECTION of the round-2 survival claim (row 5 above) |
| R21 | on the measured rates: spec T crosses at k ≥ 31 (15 872) at 167.0 / 169.0 / 169.2; lazy T at k ≥ 31 / 32 / 32 | T3r_crossover_meas (∀ k, iff) | [R3-crossover-*-seq64k] [R3-crossover-*-shuf64k] [R3-crossover-*-p256k] | PROVED ∀ k |
| R22 | over every L: spec T ⟺ L ≥ 15 888 (monotone); lazy T ⟺ L ≥ 16 400 ∨ (15 888 ≤ L ∧ L mod 16 ≥ 9) — not monotone (398 018 at 15 897, 395 680 at 15 904, 399 576 at 16 399, 407 691 at 16 400) | T3r_crossover_anyL_rowmaxT, T3r_crossover_anyL_lazyT (∀ L, iff), T3r_crossover_anyL_cells | [R3-crossover-*] | PROVED ∀ L |
| R23 | T_gqa_matrix at the measured ρ32: the general inequality in hundredths (4·d·80·432·100 < 4·rows·d·ρ100·10·1746 for every rows·ρ100 ≥ 200, every d > 0), hence for every g ≥ 2, t ≥ 1; cells 69.2 / 138.4 / 276.8 / 553.7 / 1 107.4 % at rows = 1 / 2 / 4 / 8 / 16; rows = 1 is DDR-bound (69.2 %) | T_gqa_matrix_100 (∀ rows ρ d), T3r_gqa_137, T3r_gqa_137_g (∀ t g d) | [R3-gqa-137] | PROVED (∀) — T_gqa_matrix survives |
| R24 | fleet lines with the measured fixed cost: MoE-128k attention-bound iff G ≤ 168.3 (spec T) / 167.9 (lazy T) / 168.6 (spec C); dense 32k ≤ 7.3, dense 128k ≤ 29.4, MoE 32k ≤ 42.0; both 1M cells at every G ≤ 174.6 | T3r_fleet_G_moe_128k_rowmaxT, _lazyT, _rowmaxC, T3r_fleet_G_dense_32k, T3r_fleet_G_dense_128k, T3r_fleet_G_moe_32k, T3r_fleet_G_1M (∀ G ≤ 1746, iff) | [R3-fleet-G-*] | PROVED ∀ G (layer times: D4, fleet.lean T_layer) |
| R25 | MoE-128k verdict cells: attention-bound at 167.0 on every chain (by 25 693 / 18 201 / 30 813 ns = 0.8 / 0.6 / 1.0 %) and at 153.8 (9.4 %); weights-bound at 169.0 (12 195 ns), 169.2 (16 035 / 23 527 / 10 915 = 0.5 / 0.7 / 0.3 %) and 174.6 (114 083 = 3.6 %) | T3r_fleet_moe_128k_cells | [R3-fleet-G-*-moe-128k] | PROVED |
| R26 | HW-MAP's E21 verdict sentence is inverted: the round-2 theorem instantiated at 167.0 gives attention-bound (3 221 666 ≥ 3 207 719), 167.0 ≤ 167.7, and the bare stream 256 × 12 557 = 3 214 592 exceeds the layer by 6 873 ns | T3r_moe_128k_direction (instantiates T_fleet_G_moe_128k) | [R3-fleet-moe128k-direction] | PROVED — CORRECTION of HW-MAP's reading (the measurement itself stands) |
| R27 | page sizes: 64 KiB 1.3 % under 256 KiB, 16 KiB 7.9 % under 64 KiB and 9.1 % under 256 KiB; tail waste 258 048 / 1 044 480 / 4 190 208 B (0.25 / 1 / 4 MiB); G_page3 cells 169.0 / 166.9 / 169.2 / 153.8 | T3r_page_sizes | [R3-page-*] | PROVED |
| R28 | two-tier G on the measured base at c = 0 / 39 / 100 / 153 / 160 / 200 / 500 / 2 000 ns: 169.2 / 169.1 / 168.9 / 168.7 / 168.7 / 168.5 / 167.5 / 162.6 at 32k (and 1M), 168.7 at 34 768 and 39 ns; 64 KiB pages 169.0 / 166.9 / 163.7 / 161.1 / 160.8 / 160.7 / 158.8 / 145.5 / 102.7; 256 KiB 168.7 / 167.1 / 167.0 / 162.6 / 145.7; the gain 1.3 / 4.7 / 4.9 / 5.0 / 15.1 / 58.3 % at 39 / 153 / 159 / 160 / 500 / 2 000 — the "≥ 5 % iff c ≥ 160" rule holds at the 159 / 160 pair and every listed cell (monotonicity in c not formalised) | T3r_page_tier | [R3-page-cpg*] [R3-page-tier-rule] | PROVED (cells) |
| R29 | the measured drain rates satisfy the round-2 iff thresholds at mt = 1..4 (instantiating T2_drain_threshold); margins 43.6× / 32.2× / 21.2× / 17.4×; 268 / 368 / 283 / 344 ns per block = 2.2 / 3.1 / 4.7 / 5.7 %; rDrainM at mt ≥ 4 uses the mt = 4 figure | T3r_drain_hidden, T3r_drain_cells | [R3-drain] | PROVED (R_drain: INPUT) |
| R30 | σ_s = 19.9 ns: 256-compare tail 5 094 ns = 42.4 % (round 2: 512 ns), under the 47 ns line (T2_sigma at 20); 16 reduce calls 2 910 ns = 24.2 %, 1.7× cheaper; all-scalar max 163 020 ns = 13.5× the block | T3r_sigma | [R3-sigma] | PROVED (σ_s: INPUT) |
| R31 | online vs two-pass: re-streamed K 6 204 ns per block at 169.0 (6 005 at 174.6) vs 596 / 1 501 / 1 790 ns → 10.4× / 4.1× / 3.4× | T3r_online | [R3-online] | PROVED |
| R32 | KV-int8: 612 µs / 19.0 ms (spec T, vector-bound: 64 × 6 278 / 2 = 401 824 < 593 664), 413 µs / 12.9 ms (lazy T, DDR-bound: 353 920 < 401 824) | T3r_i8 | [R3-i8-t1] | PROVED |
| R33 | the moved-cell pairs (round-2 value beside the round-3 value for 32k and 1M: stream, worst, page64k, gather3x, t = 16, S4, KV-int8, fixed) and the +6.0 % / +4.6 % / +1.5 % deltas | T3r_moved | [R3-moved-*] | PROVED |
| R34 | the helper lemmas chain100_rowmax, chain100_lazy, unitT16, unitT32, unitC16, unitC32 (definitional unfoldings) and the forms of R5, R15, R18 | — | — | cited above (no claim of their own) |

**Coverage, round 3: 34 rows, 34 with a theorem (100 %); 33 PROVED (18 universally quantified over merge, c_exp, L, G, k, fixed,
rows, ρ, d, t, g), 1 row of helpers; 0 orphans — every `T3r_*` theorem and every round-3 helper is cited in R1–R34 or in the
corrections table; every `[R3-*]` label of attn.py is cited (the label families `[R3-t1-*]`, `[R3-t16-*]`, `[R3-regime-*]`,
`[R3-fleet-G-*]`, `[R3-page-cpg*]`, `[R3-moved-*]`, `[R3-crossover-*]`, `[R3-chain-*]`, `[R3-merge-*]`, `[R3-cexp-threshold-*]`,
`[R3-lin-*]`, `[R3-rows*-*]`, `[R3-worst-overrun-*]`, `[R3-E21-*]` expand to the 273 printed lines).** The empirical residue after
round 3: E23 (H-F16 geometry), E24 (the tile mix at the measured rates; S4's exactly-full L0A no longer matters), E25 (c_copy),
E26 (drift, snapshots), E27 (numerics), E28 (the realised ms), the new **E35** (the fixed-shift variant's exception rate), and
within E22 the two open items A3 (small-call latency) and T-vs-C (whether independent reels pipeline).

## Round 2 (kept) — build status, corrections and ledger as submitted on 2026-11-04

### Build status (round 2)

| Item | Result |
|---|---|
| Toolchain | Lean 4.35.0 (`leanprover/lean4:v4.35.0` in `proof/lean-toolchain`, elan), Lake 5.0.0 |
| `lean proof/attn.lean` standalone | **succeeds**, 0 errors, 0 warnings, ≈ 4 s (no imports beyond Init; Mathlib/Batteries not used) |
| `cd proof && lake build` | **succeeds** (targets `Model`, `Smoke`, `Moe`, `Fleet`, `Attn` = attn.lean, added to `lakefile.toml`) |
| Theorems in attn.lean | **121** (`grep -c '^theorem'`), of which the load-bearing set under PROMPT-3P's names is `T_crossover` (+ `T_crossover_anyL`, `T_crossover_384`, `T_step_t1_form`), `T_gqa_matrix` (+ `T_gqa_matrix_g`), `T_softmax_ops` (+ `T_poly_bound`, `T_softmax_block`, `T_softmax_max_ops`), `T_drift_alt` / `T_drift_1M` / `T_drift_blocks` / `T_drift_error` / `T_drift_monotone`, `T_buffers_no_OL` / `T_buffers_us` / `T_buffers_l0a` / `T_buffers_l0c` / `T_buffers_s1` / `T_buffers_s4` / `T_buffers_window` / `T_buffers_OL_in_DDR`, and the branch set `T4_t1_*` / `T4_t16_*` / `T4_s4` / `T4_i8` / `T_step_t1_G_bracket` / `T_fleet_G_*` |
| `axiom` / `sorry` / `native_decide` declared or used | 0 / 0 / 0; 69 theorems depend on no axiom at all, 3 on `propext`, 33 on `propext` + `Quot.sound`, 16 on the standard `propext` / `Quot.sound` / `Classical.choice` that `omega` / `simp` emit (`#print axioms` over every theorem) |
| `decide +kernel` | 0 (the largest bounded `decide` is the 7-case rows* search; the 32 768-point page bijections are proved with explicit inverses and `omega`, not by enumeration) |
| Leaf closers used | `decide`, `omega`, `rfl`, `simp` / `simp only` with core lemmas (`Nat.one_mul`, `Nat.mul_one`, `Nat.succ_mul`, `Int.natAbs_neg`), `exact` / `apply` of core lemmas (`Nat.le_div_iff_mul_le`, `Nat.div_le_iff_le_mul_add_pred`, `Nat.lt_div_iff_mul_lt`, `Nat.div_le_div_left`, `Nat.div_le_div_right`, `Nat.div_mul_le_self`, `Nat.mul_div_mul_left`, `Nat.mul_div_cancel_left`, `Nat.max_eq_left`, `Nat.max_le`, `Nat.le_max_right`, `Nat.mul_le_mul_left/right`, `Nat.mul_lt_mul_left`, `Nat.le_mul_of_pos_left/right`, `Nat.mod_lt`, `Int.natAbs_add_le`, `Int.mul_add`, `Int.mul_assoc`, `List.map_append`); structure: `unfold`, `rw`, `intro`, `constructor`, `refine`, `obtain`, `induction`, `split`, `ac_rfl`, `dsimp only` |
| `python3 -I proof/attn.py` | runs on Python ≥ 3.8, no dependencies; every number in the text has a label; labels that moved or were added in round 2: `[A4b-drain-threshold]` (82 → 164 at mt = 4, now per mt), `[A4b-G-threshold]` (parenthetical 11 701 → 12 839), `[A7-sram]` → `[A7-us-mt*-win*]` / `[A7-l0a-mt*]` / `[A7-s1-mt*]` (200 → 213 056 B; L0A 48 → 64 KiB; S1 36 → 208/168/224 KiB), new `[A0-pt-share]` `[A1-G-exact]` `[A1-G-roof]` `[A1-tailwaste-*]` `[A2-sigma]` `[A2-d64]` `[A4-worst-overrun-*]` `[A4b-cexp-*]` `[A4b-merge-*]` `[A4b-s4-l0c]` `[A4c-Leq-anyL]` `[A4c-Leq-384]` `[A4d-fleet-G-*]` `[A7-tree-ops]` `[A7-drift-*]` `[A9-hkv1]`; no previously printed step-time cell changed |
| Measured namespace | 20 plain definitions, each with the HW-MAP row it comes from (rates, MMA cost, lane rate, launch floor, SRAM sizes, errata caps), plus PROBLEM-3's 398 µs unit (D1: DESIGN.md route 1, not a measurement — the 384 µs value at the measured 174.6 is carried as a variant) and DESIGN-4's two per-layer times (D4: fleet.lean `T_layer`); none states a DESIGN-3.md conclusion |
| The t = 16 variant split | explicit: two-pass = `stepH L 16 …` with `pSel = passesOf 128 = 2`, `mtSel = mtPass 128 = 4`, 256-token blocks (T4_t16_passes, T4_t16_*); single-pass S4 = `stepS4` = `stepNs … true` with `pSel = 1`, `mtSel = mtOf 128 = 8`, 128-token blocks, single-buffered P, Q without −Q (T4_s4, T4_s4_chain, T_buffers_s4); the S4 merge sensitivity is T3_merge_itemised |

### Corrections forced by formalization (round 1 → round 2)

| # | Where | Round 1 said | Now | Caught by |
|---|---|---|---|---|
| 1 | §4 US table, §0 ranking, row 21 | "US total 200 KiB at mt = 1 (≤ 208 KiB evidenced; 104 on the Z-reset branch); mt = 2: 164; mt = 4: 180" | the table's own rows sum to **213 056 B = 208 KiB + 64 B** with one page-table window buffer (217 152 = 212 KiB + 64 B with the declared depth 2) — 64 B / 4 160 B OVER the 208 KiB evidence; mt = 2: 204 KiB + 64 B, mt = 3: 200 KiB + 64 B, mt = 4: 196 KiB + 64 B; Z-reset branch 112 / 116 KiB + 64 B. The 200 KiB sum omitted the q row-major buffer and the page-table window. Remedies the design already names: snapshots to S1 at mt = 1 too (→ 112 KiB + 64 B) or aliasing the prologue-only q buffer onto the idle drained-C_s buffer (→ 204 KiB + 64 B) | T_buffers_us, T_buffers_us_remedy |
| 2 | §2.4, §4 L0A rows, row 21 | "t = 8 → L0A = 16 + 2·16 = 48 KiB"; appendix "L0A 16/48 KiB" (while §4's own row says 32 + 32 = 64) | with +Q and −Q resident (the ±Q alternation) and a double-buffered P set, **L0A = 16 KiB·mt: 16 / 32 / 48 / 64 KiB**, exactly full at mt = 4 — which is what forces the 64-row pass cap (mt = 5 needs 80 KiB) | T_buffers_l0a (iff over mt) |
| 3 | §2.2 drain row, §6.2, row 7 | "drain hidden iff R_drain ≥ 3.4·mt GB/s/core … at mt = 4 the drain bytes are 640 B per token … R_drain ≥ 13.6 GB/s/core"; attn.py printed 82 | per token the drain is 80 / 160 / 288 / 384 B at mt = 1..4 (C_s 64·mt, C_o 16·mt·512/block — at the 256-token block the C_o drain is amortised over half the tokens): hidden iff **R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core**, i.e. ≥ 35 / 69 / 123 / 164 tenths as an iff in the integer model ("3.4" is the rounded 3.41: at 3.4 the drain is 36 ns over the block). "640 B" double-counted C_s; "13.6" ignored the block shrink; "82" compared mt = 4 bytes with the mt = 1 block | T2_drain_threshold (∀ R_drain, iff), T2_drain_cells |
| 4 | §0, §2.4, row 11 | "rows* = 128 / 80 / 48 / 32 (ρ32 = 1) … every t ≤ 15 stays DDR-bound only on the fully native corner" | rows* for (native, native, ρ32 = 1) is **112 rows (mt = 7, t ≥ 14)** under the block rule (128-token blocks at mt ≥ 5); it is a single-pass (S4) quantity — the two-pass design caps mt at 4, where that corner is at 55.0 % and every t ≤ 16 stays DDR-bound (the t = 16 cell is 1 554 µs, KV-bound) | T3_rows_star (least mt, both sides), T3_rows_star_two_pass |
| 5 | §0, §3.2 | "a native exp at c_exp ≤ 55 lane-equivalents (ρ32 = 1) or ≤ 23 (ρ32 = 2) beats the polynomial" | with c_V = c_exp + R + 5 the t = 1 DDR-bound condition is **c_exp ≤ 56 / 51 (native / tree max) at ρ32 = 1 and ≤ 24 / 19 at ρ32 = 2**; "beats the 22-op polynomial" is c_exp ≤ 21 | T3_cexp_threshold (iff) |
| 6 | §7 reading, §9 | "with the polynomial it binds from t = 4 (ρ32 = 2) or t = 8 (ρ32 = 1)" | at ρ32 = 1 the (poly, tree) corner binds from **t = 4** (106.9 %, 856 µs); only (poly, native max) waits for t = 8 | T5_regime_t4, T5_regime_binding |
| 7 | §7, §9 d = 64 rows | "MMA share doubles to 16 %·mt"; "c_V ≤ 31 (ρ32 = 1) / ≤ 15 (ρ32 = 2)" | at d = 64 a block streams in 6 005 ns; scores need 2 (16,16,32) calls per 16 tokens (k = 64 illegal) and PV 4 per 128: **80 calls = 1 200 ns = 20.0 %·mt**; t = 1 DDR-bound iff **c_V ≤ 30 / 14** | T2_d64 (iff over c_V) |
| 8 | §3.2 step 1, §9 drift row, row 20 | "drift ≤ √(blocks/3)·|s|max ≈ 840 → 10⁻⁴ relative"; fallback "smaller blocks (256 tokens halve the drift)" | the deterministic worst case at 1M is 683 visits × 32 = **21 856 → f32 ulp 2⁻⁹ ≈ 2·10⁻³** on a score; the 10⁻⁴ figure (832 → ulp 2⁻¹⁴ = 61 ppm) holds only under the random-walk HYPOTHESIS that E26 measures. Halving the block **doubles the visits** (1 366): deterministic bound 43 712 (ulp 2⁻⁸), random-walk 1 152 (ulp 2⁻¹³ = 122 ppm) — smaller blocks make the drift worse; the levers are KV-int8 (exact i32) or a reset | T_drift_alt (∀ signs), T_drift_1M, T_drift_blocks, T_drift_monotone |
| 9 | §1.1 | "page tables … 0.4 % of KV" | 128 B per 256 tokens per die against 1 MiB of KV = **0.012 %** (122 ppm); 0.4 % divided 16 B per 256 tokens by 4 096 B per one token | T0_page_table_share |
| 10 | §9 gather row | "tail waste … ≤ 4 MiB per layer at 1 MiB pages" | one partially filled page per (head, K\|V) = 16 pages: **4.00 MiB at 256 KiB pages, 16.00 MiB at 1 MiB pages** | T1_tail_waste |
| 11 | §2.4 S4 | "L0C holds two C_s regions of 128 KiB = 256 KiB exactly" | the S4 geometry is **2 C_s regions of 64 KiB + 2 C_o regions of 64 KiB = 256 KiB** (L0A: Q 32 + P 32 = 64 KiB) | T_buffers_s4 |
| 12 | §0 | "no other unknown moves the t = 1 headline by more than 7 % (the vector corner)"; "851 µs (vector-bound 1.07×)" | the worst corner is **+9.8 % at 32k** (851 vs 776: 6.9 % per block plus 22.7 µs of fixed cost) and +7.0 % at 1M; 1.07× is the per-block ratio; drain on the vector engine +43.5 % / +41.1 % | T4_worst_overrun |
| 13 | §9 reduce row | "scalar-bound only if σ_s > 47 ns" | the 256-compare tail reaches the 12 011 ns block iff **σ_s ≥ 47 ns** (256 × 47 = 12 032); the all-scalar fallback is 1.36× the block (1.3 floored, 1.4 rounded) | T2_sigma (iff) |
| 14 | §9, §10 | "(m, S, O) partials … 9.3 KiB·mt" | 16 × (1 + 16 + 128) × 4 = **9 280 B = 9.06 KiB** (9.3 KB) | T_hkv1_partials |
| 15 | §1.4 table | G(4 KiB, 0) = 175.2, G(16 KiB, 0) = 174.7 | at c_pg = 0 the rate is exactly **174.6 at every page size**; the two cells are floor artifacts of the integer model (t_core floored to 187 / 750 ns) | T1_gather_exact (∀ P ≥ 22), T1_gather_artifact |
| 16 | §6.3, row 23 (tightening, claim survives) | "attention equals one GEMV unit at L_eq = 16 896 tokens (the smallest 512-multiple …)" | true as stated and proved both ways over k (512-multiples); over EVERY L the model crosses at **L ≥ 16 400**, because the 33rd block is charged in full from its first 16-token group (the partial-block charge is conservative by ≤ 12 µs); against the measured kernel's 384 µs for the same bytes the crossover is 16 384 | T_crossover, T_crossover_anyL, T_crossover_384 |
| 17 | §3.1 merge, attn.py MERGE_OPS (new ASSUMPTION flag) | "merge per block (vector, 7 000·mt lane-ops)" — not itemised anywhere in the text | carried as the explicit hypothesis `merge`: the t = 1 native corner stays DDR-bound for every merge ≤ 461 574; an itemisation of §3.1's own op list (O: 4 × 2 048, S fold 3 × 1 024 + 2 × 256, α 22 × 16) gives 12 128, which moves the t = 1 32k cell by 238 ns and **S4 from 1 032 to 1 277 µs** (1M: 32.4 → 40.2 ms) | T3_merge_threshold (∀ merge), T3_merge_itemised |
| 18 | attn.py `[A4b-G-threshold]`, `[A7-sram]`, `[A4d]` (no text change) | printed the c_V = 30 vector time (11 701) beside the c_V = 33 threshold; S1 "36 KiB" (P ring only); the c_pg boundary of the fleet cells used G* instead of G* + 1 | 12 839; S1 = P ring + snapshots = 208 / 168 / 224 KiB at mt = 2 / 3 / 4; c_pg boundaries 122 / 9 481 / 14 770 / 67 847 ns | T3_G_threshold, T_buffers_s1, T_fleet_G_cpg |

New results found while proving (not corrections): (a) **what gather rate each fleet cell needs** — a DESIGN-4 cell is attention-bound iff G ≤ G*: dense 32k 7.3 GB/s, dense 128k 29.4, MoE 32k 41.9, **MoE 128k 167.7** (so the page64k branch at c_pg = 0.5 µs, and any c_pg ≥ 123 ns at 64 KiB pages, already flips the MoE 128k cell), both 1M cells attention-bound at every G ≤ 174.6 (T_fleet_G_*, iff over every G ≤ 174.6); (b) the vector-dot route theorem holds for every head dim (d cancels exactly) and needs rows·ρ32 ≥ 2 — at rows = 1, ρ32 = 1 (no GQA) the dot route is DDR-bound at 50.5 % like route M, not worse (T3_vecroute_d_cancels, T3_vecroute_rows1); (c) the online merge is exact for any multiplicative exp, proved as a list identity (T_online_exact); (d) the K and V page maps are bijections onto the even bytes of the page with explicit inverses (T_kpage_*, T_vpage_*); (e) the model's partial-block charge and the 384 µs variant of the GEMV unit (row 16 above).

**Load-bearing verdicts.** `T_crossover` **survives unchanged**: attention time equals one 398 µs GEMV unit at L = 16 896 as the smallest 512-multiple (403.4 µs there, 391.4 at 16 384), proved as an iff over k for every 512·k, with the closed form of the step for every L (T_step_t1_form) and the finer any-L crossover 16 400 recorded as a tightening. `T_gqa_matrix` **survives unchanged and in a stronger form**: the vector-dot route costs 0.505·rows·ρ32 of the KV stream time (the 10 cells of `[A3-vecroute-*]`, and d cancels exactly), and the strict inequality "compute-bound" is proved for every rows·ρ32 ≥ 2 — hence for every g ≥ 2 at any t ≥ 1 and either lane rate (T_gqa_matrix, T_gqa_matrix_g); the one shape outside it (rows = 1, ρ32 = 1, no GQA) is a tie at 50.5 %, not a counterexample.
### The round-2 ledger (DESIGN-3.md Appendix A rows 1–27, then the claims the appendix did not list)

| # | Claim | Proof | attn.py | Status |
|---|---|---|---|---|
| 1 | kv_tok = 2·8·128·2 = 4 096 B; 512 B per core per token; KV per layer 2²⁴ / 2²⁷ / 2²⁹ / 2³² B at 4k / 32k / 128k / 1M; 256 tokens per 64 KiB page (512 at d = 64); 256 KiB per core per block = 2 MiB per die; blocks 8 / 64 / 256 / 2 048; the matrix path serves 16⌊L/16⌋ and the tail ≤ 15 tokens for every L | T0_kv_bytes, T0_blocks, T0_matrix_tail (∀ L) | [A0-shape] [A0-kv-*] | PROVED |
| 2 | page tables 2·H_kv·8·⌈L/256⌉ = 2 048 / 16 384 / 65 536 / 524 288 B; window 512 entries = 128k tokens = 4 KiB; share of KV 0.012 % (122 ppm) | T0_page_table, T0_page_table_share | [A0-kv-*] [A0-pt-share] | PROVED — corrected (round 1: 0.4 %) |
| 3 | K page map addr_K(l, j) and V page map addr_V(l, j) are bijections [0,256) × [0,128) → even bytes of [0, 65 536): range, injectivity, surjectivity with explicit inverses; the 32 B token runs at stride 512 B (K), the 2 B token stride inside 32 B dim runs (V), 4 KiB call tiles, 32 KiB V halves | T_kpage_range, T_kpage_injective, T_kpage_surjective, T_kpage_bijection, T_vpage_range, T_vpage_injective, T_vpage_surjective, T_vpage_bijection (∀ l, j / ∀ a; helpers vDigits, vAddr_digits), T_page_geometry | — | PROVED (the fragment geometry H-F16 itself: EMPIRICAL — E23) |
| 4 | G(P) = 8·P·10/(P·80/1746 + c_pg): the 15 cells of §1.4 (175.2 … 167.6); non-increasing in c_pg for every P; monotone in P along the table; G(P, 0) ≥ 174.6 for every P ≥ 22 B (the 175.2 / 174.7 cells are floor artifacts); a 4 KiB page is within 10 % of the stream iff c_pg ≤ 20 ns (90.6 % at 20) | T1_gather_cells, T1_gather_monotone_cpg (∀ P, c ≤ c'), T1_gather_monotone_P, T1_gather_exact (∀ P), T1_gather_artifact, T1_small_page | [A1-G-*] [A1-G-exact] | PROVED (the value of c_pg: EMPIRICAL — E21) — corrected (c_pg = 0 row) |
| 5 | block DDR time 2 MiB·10/1746 = 12 011 ns; per-core share 21.8 GB/s (174.6/8); ±1 block imbalance = ±12 µs | T2_block | [A2-block] | PROVED |
| 6 | per block: MMA 64 calls = 960·mt ns (8.0 %), loader 16 384·mt/26.5 = 618·mt ns (5.1 %), US → S1 copy 65 ns (0.5 %; "66" rounded), drain bytes 40 960·mt (81 920 at mt = 2; 73 728 / 98 304 at the 256-token blocks of mt = 3 / 4), scalar tail 256·2 = 512·mt ns (4.3 %), MMA at mt = 3 / 4 = 1 440 / 1 920 per 256-token block | T2_block, T2_block_mt | [A2-block] | PROVED |
| 7 | drain hidden iff R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1..4 (iff thresholds 35 / 69 / 123 / 164 tenths; 80 / 160 / 288 / 384 B per token); at 10 GB/s 4 096·mt ns = 34.1 % per block; at exactly 34 tenths 12 047 > 12 011 | T2_drain_threshold (∀ R_drain, iff, four mt), T2_drain_cells | [A4b-drain-threshold] | PROVED ∀ R_drain — corrected (3.4·mt, 13.6, 640 B, 82); the realised R_drain: EMPIRICAL — E26 |
| 8 | vector per block (8 192·c_V + 7 000)·ρ32·10/432: 1 489 / 2 978 / 2 437 / 4 875 / 5 471 / 10 943 / 6 419 / 12 839 ns = 12.4 / 24.8 / 20.3 / 40.6 / 45.5 / 91.1 / 53.4 / 106.9 % of the block; c_V = 2 + R + 1 + E + 1 + 1 = 7 / 12 / 28 / 33; the worst corner overruns the block by 828 ns | T3_vec_cells, T3_cV_table, T_softmax_block (∀ c_V) | [A2-vec-*] | PROVED (which corner holds: EMPIRICAL — E22) |
| 9 | t = 1 DDR-bound iff c_V ≤ 62 (ρ32 = 1) / ≤ 30 (ρ32 = 2) — edges 11 919 / 12 108 and 11 701 / 12 081 ns; native exp keeps t = 1 DDR-bound iff c_exp ≤ 56 / 51 (native / tree max) at ρ32 = 1, ≤ 24 / 19 at ρ32 = 2; beats the 22-op polynomial iff c_exp ≤ 21 | T3_t1_ddr_bound (∀ c_V, iff), T3_t1_ddr_bound_edges, T3_cexp_threshold (∀ c_exp, iff) | [A4b-cV-threshold-*] [A4b-cexp-*] | PROVED ∀ c_V, c_exp — corrected (55 / 23) |
| 10 | vector-dot route / KV stream = rows·ρ32·4·d·1746·10⁴/(80·4d·432) = 0.505·rows·ρ32: 50.5 / 101.0 / 202.0 / 404.1 / 808.3 % (ρ32 = 1), 101.0 … 1 616.6 % (ρ32 = 2); d cancels for every d > 0; strictly compute-bound iff rows·ρ32 ≥ 2, hence for every g ≥ 2, t ≥ 1, either lane rate, any d; at rows = 1, ρ32 = 1 it is 50.5 % (DDR-bound, a tie with route M) | T_gqa_matrix (∀ rows ρ32 d), T_gqa_matrix_g (∀ t g ρ32 d), T3_vecroute_cells, T3_vecroute_d_cancels (∀ d), T3_vecroute_rows1 | [A3-vecroute-*] | PROVED (∀) |
| 11 | rows* (least rows with vector ≥ DDR per block under the block rule): 112 / 80 / 48 / 32 at ρ32 = 1 (mt = 7 / 5 / 3 / 2), 64 / 48 / 32 / 16 at ρ32 = 2 (mt = 4 / 3 / 2 / 1), both sides (every smaller mt is DDR-bound); within the two-pass cap mt ≤ 4 the native corners are 55.0 / 86.6 % | T3_rows_star, T3_rows_star_rows, T3_rows_star_two_pass | [A3-rows*-*] | PROVED — corrected (128 → 112) |
| 12 | t = 1 step = nb·max(ddr, vec, mma, loader) + fixed: all 24 cells of §6.1 (103 / 132, 119 / 142, 295 / 318; 776 / 851, 904 / 926, 2 313 / 2 336; 3 082 / 3 317, 3 593 / 3 616, 9 232 / 9 254; 24 606 / 26 324, 28 698 / 28 720, 73 803 / 73 825 µs), binding engine per cell, eff 162.6 / 173.0 / 174.2 / 174.6 GB/s, wall 194 / 867 / 24 697 µs, fixed 7 074 / 29 774 ns; the closed form of the step for every L; for every G in [582, 1746] the native cells lie between the stream and gather3x values and the worst cell in [851 470, 2 335 886]; on every corner with vec ≤ 12 011 the 32k stream cell is 768 704 + fixed with fixed ≤ 28 118 | T4_t1_4k, T4_t1_32k, T4_t1_128k, T4_t1_1M, T4_t1_binding, T4_fixed, T_step_t1_form (∀ L), T_step_t1_G_form (∀ L, G ≤ 1746), T_step_t1_G_bracket (∀ G), T_step_t1_worst_G_bracket (∀ G), T_step_t1_cV_bracket (∀ c_V, ρ32); helpers blockMax_hidden, blockMax_same | [A4-t1-*] | PROVED ∀ G, c_V, ρ32; which branch holds: EMPIRICAL — E21 (G), E22 (corner) |
| 13 | drain on the vector engine: worst corner 165 / 1 114 / 4 365 / 34 713 µs; native unchanged (64·(1 489 + 4 096) = 357 440 < 768 704); t = 16 native becomes 3 378 µs / 107.6 ms | T4_t1_drain_same, T4_t16_drain_same | [A4-t1-*] drain, [A4-t16-*] drain | PROVED (which engine executes the drain: EMPIRICAL — E26 / E28) |
| 14 | t = 16: rows 128 → 2 passes of mt = 4, 256-token blocks, tail fragment count 8; all 24 cells of §6.2 (209 / 905 … 49 209 / 215 733 µs), eff 160.9 / 172.8 / 174.2 / 174.6, worst corner 4.4× (4.38) and G-insensitive | T4_t16_passes, T4_t16_4k, T4_t16_32k, T4_t16_128k, T4_t16_1M | [A4-t16-*] | PROVED (two-pass variant) |
| 15 | S4 single pass (mt = 8, 128-token blocks, L0A exactly full): 1 032 µs / 32.4 ms native (vector-bound, 1.5× vs two passes), 2 052 / 64 762 at ρ32 = 2 and 7 140 / 226 356 worst — both worse than two passes (1 714 / 6 802); chain 1 236 + 960 = 2 196 ns = 73.2 % of 3 002; L0C = 2 × 64 (C_s) + 2 × 64 (C_o) KiB, L0A = 32 + 32 KiB | T4_s4, T4_s4_chain, T_buffers_s4 | [A4b-onepass-*] [A4b-onepass-chain] [A4b-s4-l0c] | PROVED (single-pass variant; exactly-full L0A: EMPIRICAL — E24; merge count: ASSUMPTION, row 32) — S4 L0C decomposition corrected |
| 16 | KV-int8 (route 1b): 391 µs / 12.3 ms native (DDR-bound; 384 352 = 64·12 011/2), 851 / 26.3 worst (vector-bound, unchanged) | T4_i8 | [A4b-i8-*] | PROVED (accuracy: EMPIRICAL — E27) |
| 17 | online vs two-pass: re-streaming K costs 128 KiB per core per block = 6 005 ns against a 324 ns merge (ρ32 = 2; 162 at ρ32 = 1) → 18×; per block, so L cancels | T_online, T_online_L_independent (∀ L, nb) | [A5-online] | PROVED |
| 18 | the online merge is exact: Σ_b E(m_b − m)·Σ_{l∈b} E(s_l − m_b)·v_l = Σ_l E(s_l − m)·v_l for every multiplicative E and every block list (the telescoping identity) | T_online_exact_block, T_online_exact (∀ E, m, blocks; helper sumI_append) | — | PROVED (algebraic identity, the only property of exp used is E(a + b) = E(a)·E(b)) |
| 19 | polynomial exp: 6 + 1 + 8 + 7 = 22 lane-ops; the bound 2⁷·(22/128)⁵/5! = 159.99·10⁻⁶ ≈ 1.6·10⁻⁴ (in [159, 160]·10⁻⁶); f32 rounding 2⁷·2⁻²⁴ = 7.6·10⁻⁶; carried as polyRelErrPpm = 160 | T_softmax_ops, T_poly_bound | [A7-poly] | arithmetic PROVED; the error bound itself HYPOTHESIS on the polynomial — EMPIRICAL — E22(e) |
| 20 | drift of the ±Q region content: for every sign pattern ≤ n·smax (683 visits per region at 1M → 21 856 → f32 ulp 2⁻⁹ ≈ 2·10⁻³); random-walk hypothesis √683·32 = 832 ≈ 840 → ulp 2⁻¹⁴ = 61 ppm ("10⁻⁴ class"); recovered-score error ≤ 1 ulp of the content bound; smaller blocks double the visits (1 366: 43 712 / 1 152 → ulp 2⁻⁸ / 2⁻¹³); visits monotone in L and in 1/block | T_drift_alt (∀ s, n), T_drift_error, T_drift_1M, T_drift_blocks, T_drift_monotone (∀ L) | [A7-drift-*] | PROVED (deterministic bound); the 840 / 10⁻⁴ figure: ASSUMPTION — E26 (random walk), smax = 32: ASSUMPTION — E27 — corrected (fallback direction) |
| 21 | SRAM is a function of (mt, d, block) only — rewriting L changes no SRAM total (structural); the O(L) objects (KV, page tables) are in DDR and monotone in L; L0C 112 / 224 / 192 / 256 KiB (mt = 4 exactly full; the 2-region fallback 192); L0A 16·mt KiB, exactly full at mt = 4, mt ≤ 4 iff it fits; US 213 056 / 208 960 / 204 864 / 200 768 B (mt = 1..4, window × 1; +4 096 at depth 2), Z-reset 114 752; remedies 114 752 / 208 960 B; S1 208 / 168 / 224 KiB ≤ 230 KiB; L0B 64 KiB; the page-table window 4 KiB for every L | T_buffers_no_OL (∀ cfg, L'), T_buffers_OL_in_DDR (∀ L ≤ L'), T_buffers_l0c, T_buffers_l0a (∀ mt, iff), T_buffers_us, T_buffers_us_remedy, T_buffers_s1, T_buffers_s4, T_buffers_window (∀ L) | [A7-l0c-mt*] [A7-us-mt*-win*] [A7-l0a-mt*] [A7-s1-mt*] [A7-sram] | PROVED — corrected (US 200 → 208 KiB + 64 B over the evidence; L0A 48 → 64; mt = 2 / 4 totals) |
| 22 | KV write: V_tail block 4 096 B at 7 GB/s = 585 ns per 16 tokens (36 ns/token); K append 8 × 32 B copies, ≤ 8 µs per layer-step at c_copy = 1 µs = 2.0 % of the GEMV unit; q prologue COPY_FRAC 585 ns·mt; 2D re-layout fallback 585 / 3 002 = 19.5 %; prefill bulk COPY_FRAC 128 MiB at 56 GB/s = 2.40 ms per layer; vector tail ≤ 122 880·mt lane-ops = 5 688 ns (ρ32 = 2) / 2 844 (ρ32 = 1), 0 when 16 ∣ L, bounded for every L | T_kvwrite, T_tail (∀ L) | [A6-kvwrite] | PROVED (c_copy ≤ 1 µs: ASSUMPTION — E25) |
| 23 | attention / GEMV unit 25.9 / 194.9 / 774.3 / 6 182.3 %; per DESIGN-4 layer 4.2 % (dense 32k), 134.8 % (dense 1M), 24.2 % (MoE 32k); L_eq = 16 896: step(512k) ≥ 398 µs iff k ≥ 33 (403 437 at 16 896, 391 426 at 16 384); over every L: iff L ≥ 16 400 (394 270 max below); at the 384 364 ns unit (67.11 MB at 174.6): iff k ≥ 32 (379 415 at 15 872) | T_fraction, T_crossover (∀ k), T_crossover_anyL (∀ L), T_crossover_anyL_cells, T_crossover_384 (∀ k) | [A4-t1-*] [A4c-Leq] [A4c-Leq-anyL] [A4c-Leq-384] | PROVED (the 398 µs unit: D1 input from PROBLEM-3 / DESIGN.md route 1) |
| 24 | regime map at 32k, all 40 cells (776 … 6 802 µs) with the binding engine from the per-block shares (55.0 / 110.0 / 49.6 / 81.2 / 91.1 / 182.2 / 106.9 / 213.8 / 187.6 / 86.6 / 438.4 %); t = 2 equals t = 1 exactly; the native-vs-as-written gap at t = 8 is 4.4×; page64k moves the KV cells 1.17×; gather3x leaves the worst t = 16 cell unchanged and triples the native t = 1 cell | T5_regime_t1, T5_regime_t4, T5_regime_t8, T5_regime_t16, T5_regime_binding, T5_regime_G | [A4c-regime-*] | PROVED — corrected (poly + tree binds from t = 4 at ρ32 = 1) |
| 25 | G branches: stream 1 746, page64k = G(64 KiB, 0.5 µs) = 1 497, gather3x = 582; the "3× slower" case is c_pg ∈ [5 991, 6 006] ns at 64 KiB (both directions as iffs over c_pg), 376 ns at 4 KiB | T1_gather_branches, T1_gather3x_cpg (∀ c_pg, iff) | [A1-branches] | PROVED |
| 26 | a 32 KiB tile never straddles a 64 KiB / 256 KiB / 1 MiB page (every tile index k) | T1_tile_in_page (∀ k) | — | PROVED (round 1: DEFINITION) |
| 27 | errata compliance: tiles 32 KiB and P pieces 4 KiB ≤ the 64 KB copy cap, reels 1 024 ≤ the lane cap, n = 16 ≤ 16, k ∈ {32, 128} ≠ 64, the L0B ring = its capacity | T_errata_sizes | — | PROVED (the caps themselves: INPUT, HW-MAP errata #2 / #3 / MMA constraints) |
| 28 | worst-corner overrun of the headline: +9.8 % at 32k, +7.0 % at 1M (22 700 ns extra fixed cost); drain on the vector engine +43.5 % / +41.1 % | T4_worst_overrun | [A4-worst-overrun-*] | PROVED — corrected ("7 %", "1.07×") |
| 29 | scalar tail: 256·σ_s ≥ the block iff σ_s ≥ 47 ns; the all-scalar max 8 192 × 2 = 16 384 ns = 1.36× the block | T2_sigma (∀ σ_s, iff) | [A2-sigma] | PROVED ∀ σ_s (σ_s = 2 ns: ASSUMPTION — E22(f)) — corrected ("> 47", "1.4×") |
| 30 | d = 64: block 6 005 ns, 80 MMA calls = 1 200 ns = 20.0 %·mt; t = 1 DDR-bound iff c_V ≤ 30 / 14 | T2_d64 (∀ c_V, iff) | [A2-d64] | PROVED — corrected (16 %, 31 / 15) |
| 31 | the worst corner is DDR-bound iff G ≤ 163.3 (so vector-bound at the stream rate, DDR-bound on page64k and gather3x) | T3_G_threshold (∀ G, iff) | [A4b-G-threshold] | PROVED |
| 32 | merge count 7 000 lane-ops per block-fragment: the t = 1 native corner is DDR-bound for every merge ≤ 461 574; an itemisation of §3.1's op list = 12 128 moves t = 1 32k by 238 ns (776 016) and S4 to 1 277 307 / 40 163 707 ns | T3_merge_threshold (∀ merge, iff), T3_merge_itemised | [A4b-merge-*] | ASSUMPTION (the 7 000 is not derived in the text) — robustness PROVED ∀ merge |
| 33 | E21 for the fleet: a DESIGN-4 cell is attention-bound iff G ≤ 73 / 294 tenths (dense 32k / 128k), 419 / 1 677 (MoE 32k / 128k); both 1M cells at every G ≤ 1 746; in c_pg at 64 KiB: weights-bound iff c_pg ≤ 67 847 / 14 770 / 9 481 / 122 ns; page64k and gather3x both flip MoE 128k, neither flips MoE 32k | T_fleet_G_dense_32k, T_fleet_G_dense_128k, T_fleet_G_dense_1M, T_fleet_G_moe_32k, T_fleet_G_moe_128k, T_fleet_G_moe_1M (∀ G ≤ 1746, iff), T_fleet_G_cpg | [A4d-fleet-G-*] | PROVED ∀ G (layer times: D4 — fleet.lean T_layer; which G holds: EMPIRICAL — E21) |
| 34 | what-if the stream ran at the raw direct-load roof 181.3: 23.70 ms at 1M (the 174.6 cell is 103.8 % of it), 747 µs at 32k; 173.8 < 174.6 ≤ 181.3 | T1_stream_roof | [A1-G-roof] | PROVED (the roof class choice: INPUT, HW-MAP "pure read streams sustain ~181") |
| 35 | page tail waste: P_tok = 1 024 / 4 096 at 256 KiB / 1 MiB; 16 pages × (P − 256 B) = 4.00 / 16.00 MiB per layer | T1_tail_waste | [A1-tailwaste-*] | PROVED — corrected ("≤ 4 MiB at 1 MiB pages") |
| 36 | H_kv = 1 partials 16·(1 + 16 + 128)·4 = 9 280 B = 9.06 KiB·mt (9.3 KB); rows = t·H_q: 32 at t = 1 (mt = 2), 512 at t = 16 (8 passes) | T_hkv1_partials | [A9-hkv1] | PROVED — corrected (unit) |
| 37 | wall = in-kernel + 91 µs; the launch floor appears in no in-kernel cell (the step model has no tLaunch term); 88 % / 12 % / 0.4 % of the 4k / 32k / 1M step, fill/tail 7 % / 1 % / 0.03 % | T_wall (∀ ns), T4_fixed | [A4-*] wall | PROVED (launch floor: INPUT; whether launches pipeline: EMPIRICAL — DESIGN.md E0) |
| 38 | §8 harness bounds: |s| ≤ 6 272, block PV sums 2.25·10⁷ > 2²⁴; with |q| ≤ 1: 896 and 3 211 264 < 2²⁴ | T_harness | — | PROVED |
| 39 | E21 arena: 8 × 2 048 × 1 MiB = 16 GiB of visits in a 4 GiB arena (pages repeat 4×; the per-page pattern still differences every visit) | T_e21_arena | — | PROVED (a note on the probe spec, not a correction) |

**Qualitative rows (no number to prove; listed so nothing is silently skipped).** §1.4's DRAM locality argument
(row buffers 2–4 KiB, a 64 KiB burst spans every channel) — PRIOR, settled by E21. §2.2 "a vector block up to
2× the DDR block is absorbed by the two-block V lag" — a latency statement; the model charges the steady-state
rate deficit (T4_t1_binding: the worst corner binds), so it is DEFINITION. §2.2 copy-out "< 2 µs per step" —
ASSUMPTION — E25 (c_copy). §5 barrier plan A1–A13 and the E27 determinism criterion — DEFINITION / EMPIRICAL —
E27. §8 E22–E28 setups — EMPIRICAL by construction. §9 "run the tree in f16 saves ≈ 3 lane-ops at ρ32 = 2" —
arithmetic of T3_cV_table (6 → 3). §10 runtime obligations — DEFINITION.

**Coverage of the 39 rows: 39/39 have a theorem (100 %); 36 PROVED (24 of them universally quantified over
an unmeasured or assumed quantity: c_pg, G, c_V, c_exp, ρ32, R_drain, σ_s, merge, L, k, sign patterns, E, mt,
tile index, page coordinates), 2 ASSUMPTION carried as a hypothesis with its arithmetic / robustness proved
(rows 19, 32), 1 PROVED-note (row 39); 0 orphans (every theorem of attn.lean is cited above or in the
corrections table — the five helper lemmas `blockMax_hidden`, `blockMax_same`, `sumI_append`, `vDigits`,
`vAddr_digits` are cited in rows 3, 12 and 18), 0 uncited theorems.** The empirical residue is exactly the
E-ladder: E21 (G / c_pg), E22 (c_V, c_exp, R, ρ32, σ_s, the polynomial's error), E23 (H-F16 geometry), E24
(exactly-full L0A for S4, the tile mix at 174.6), E25 (c_copy), E26 (R_drain, the drift's random-walk
hypothesis, which engine drains), E27 (smax, accuracy), E28 (the realised ms).
