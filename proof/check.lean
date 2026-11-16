/-! # proof/check.lean — PROMPT-7 challenge round 4 (2026-11-15): independent re-derivations (`Chk.*`)

Core Lean 4 (v4.35.0), imports nothing beyond Init, compiles standalone with `lean check.lean`.
Corpus rules: no `sorry`, no `axiom`, no `native_decide` (`#print axioms` on every theorem is empty).

INDEPENDENCE: every constant below is re-typed from HW-MAP rows or from the models' PRINTED output
(`python3 proof/*.py`, run 2026-11-15 at HEAD 85a79d0) and every derived quantity is recomputed with this
file's own definitions — nothing is imported from or copied out of the existing proof files. Theorems named
`challenge_*` state a finding that corrects or qualifies a corpus statement (PROOF-COVERAGE-CHECK.md §3);
every other theorem re-proves a ledger row and matched the corpus to the digit.

Frame discipline (per PROMPT-7): a constant is MEASURED (M, an HW-MAP row), DERIVED (D, printed by a model
or computed here), UNMEASURED (U) or ASSUMPTION (A); the tag is in the doc-string of each definition. -/

namespace Chk

/-! ## 0. Units and helpers (own definitions; the corpus's conventions re-stated) -/
/-- bytes at a rate in tenths of GB/s → ns (floor): the corpus's `tn` -/
def tn (b r : Nat) : Nat := b * 10 / r
def KiB : Nat := 1024
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB : Nat := 1000000000
/-- tokens/s per card in thousandths: `tok` (per-mille tokens) per step of `T` ns on the 4-card fleet -/
def tpsCard (tok T : Nat) : Nat := tok * 1000000000 / (4 * T)
/-- two instances at aggregate gain `c` (per mille): the corpus's `tpsInst` -/
def tpsInst (tok c T : Nat) : Nat := tok * c * 1000000 / (4 * T)
/-- τ(α, 3) = Σ_{i≤3} α^i in per-mille, α in per-mille (floor at the end) -/
def tau3 (a : Nat) : Nat := (1000000000 + a * 1000000 + a * a * 1000 + a * a * a) / 1000000

theorem tau3_cells : tau3 700 = 2533 ∧ tau3 854 = 3206 ∧ tau3 855 = 3211 ∧ tau3 24 = 1024 ∧ tau3 146 = 1170 := by decide

/-! ## 1. The planner's step as a sum of printed components ([F0]/[F2]/[F3] of fleet.out; HW-MAP rows)

The corpus states (T5r_step_form) that the t = 1 step is affine in the per-layer attention a:
dense 2 289 788 669 + 120·a, MoE 115 956 899 + 28·a. Here both constants are REBUILT from components. -/
/-- M: direct-path W8 kernel 174.6 GB/s (tenths) -/
def rGemm : Nat := 1746
/-- D (DESIGN-2 T_piece_expert): one 16 MiB expert slab per core in the serial regime, ns -/
def tSlabSer : Nat := 122979
/-- A (DESIGN-2): fixed per-launch cost 8 µs -/
def fMoe : Nat := 8000
/-- M: launch + queue floor (primary) and the realized serving-loop bound -/
def tLaunch : Nat := 91000
def tLaunchRealized : Nat := 36000
/-- M: the on-device f16→i8 pass, 4 per layer -/
def tQuant : Nat := 43700
/-- M: host bounce per direction -/
def lam : Nat := 12200
/-- shapes ([F0]): MoE attention GEMM bytes per layer, dense layer bytes, heads -/
def moeAttnBytes : Nat := 4096 * (4096 + 2 * 8 * 128) + 4096 * 4096
def denseLayerBytes : Nat := 16384 * (16384 + 2 * 8 * 128) + 16384 * 16384 + 3 * 16384 * 53248
def moeExpertBytesLayer : Nat := 256 * 3 * 4096 * 4096
def headBytesMoe : Nat := 4096 * 128256
def headBytesDense : Nat := 16384 * 128256
/-- D: per-layer GEMM time; MoE = attention GEMMs + 2 F + 8 experts × 3 slabs (serial anchor) -/
def gemmLayerMoe : Nat := tn moeAttnBytes rGemm + 2 * fMoe + 8 * 3 * tSlabSer
def gemmLayerDense : Nat := tn denseLayerBytes rGemm
def headMoe : Nat := tn headBytesMoe rGemm
def headDense : Nat := tn headBytesDense rGemm
/-- D ([F2-*-rows1]): bandwidth-only hop sums of the 8-die chain at t = 1 (printed) -/
def xchBwMoe : Nat := 24367
def xchBwDense : Nat := 41107
def xchMoe : Nat := xchBwMoe + 16 * lam
def xchDense : Nat := xchBwDense + 16 * lam
/-- the step without attention: W + head + (launches + 2)·91 µs + 4 quant passes/layer + exchange -/
def baseMoe : Nat := 28 * gemmLayerMoe + headMoe + (28 * 7 + 2) * tLaunch + 28 * 4 * tQuant + xchMoe
def baseDense : Nat := 120 * gemmLayerDense + headDense + (120 * 6 + 2) * tLaunch + 120 * 4 * tQuant + xchDense
def stepMoe (a : Nat) : Nat := baseMoe + 28 * a
def stepDense (a : Nat) : Nat := baseDense + 120 * a

theorem shapes : moeAttnBytes = 41943040 ∧ denseLayerBytes = 3187671040 ∧ moeExpertBytesLayer = 12 * GiB ∧
    moeAttnBytes + moeExpertBytesLayer = 12926844928 := by decide
theorem components : gemmLayerMoe = 3207719 ∧ gemmLayerDense = 18256993 ∧ headMoe = 3008800 ∧ headDense = 12035202 ∧
    tn moeAttnBytes rGemm = 240223 ∧ 8 * 3 * tSlabSer + 2 * fMoe = 2967496 := by decide
/-- the corpus's affine constants reproduce from components to the digit -/
theorem step_form : baseMoe = 115956899 ∧ baseDense = 2289788669 := by decide
/-- the round-2 primary cells ([F3] table: MoE 32k 133.84 ms → 1.867, dense 2362.31 → 0.105) at the
    round-2 attention term max(KV 768 715, softmax 12 136 / 48 545, MMA 61 440) = the KV stream, λ = 91 µs, no quant pass -/
theorem round2_cells : 28 * gemmLayerMoe + headMoe + (28 * 7 + 2) * tLaunch + (xchBwMoe + 16 * tLaunch)
      + 28 * max 768715 (max 12136 61440) = 133847319 ∧ tpsCard 1000 133847319 = 1867 ∧
    120 * gemmLayerDense + headDense + (120 * 6 + 2) * tLaunch + (xchBwDense + 16 * tLaunch)
      + 120 * max 768715 (max 48545 61440) = 2362319269 ∧ tpsCard 1000 2362319269 = 105 := by decide

/-! ## 2. Round 7 — the measured-anchor re-grounding ([R7-*], T7r_*) -/
/-- M (expert-kernel dispatch cells; NOT an HW-MAP row — see PROOF-COVERAGE-CHECK §3 C-2): 165.8 / 170.2 GB/s -/
def rM0 : Nat := 1658
def rM0T4 : Nat := 1702
def slabM0 : Nat := tn (16 * MiB) rM0
def slabM0T4 : Nat := tn (16 * MiB) rM0T4
/-- D (ALT-1): the derived direct-path slab the E29 promise was priced against -/
def tSlabDirect : Nat := 99374
/-- E29 per MoE token = 28 layers × 24 slabs × the per-slab saving -/
def e29Derived : Nat := 28 * 24 * (tSlabSer - tSlabDirect)
def e29Banked : Nat := 28 * 24 * (tSlabSer - slabM0)
/-- M (kernel session 5): the deferred-guard trip-free cells; the session-5 legacy scan at 32k -/
def dfr32 : Nat := 945500
def dfr128 : Nat := 3618800
def dfr1M : Nat := 28694000
def legacy32 : Nat := 1514900
/-- D: the re-run cost of one tripped step as fleet.py prices it (attn.py: 872 600 = canonical 1 818 100 − trip-free) -/
def rTrip : Nat := 873000
/-- the amortized 32k cell at a trip rate of p10 × 0.1 % of launches -/
def amort (p10 : Nat) : Nat := dfr32 + p10 * rTrip / 1000
def step7Moe (a : Nat) : Nat := stepMoe a - e29Banked

theorem r7_inputs : slabM0 = 101189 ∧ slabM0T4 = 98573 ∧ e29Banked = 14642880 ∧ e29Derived = 15862560 ∧
    e29Derived - e29Banked = 1219680 ∧ amort 80 = 1015340 ∧ amort 55 = 993515 := by decide
/-- the round-7 cells: 1.956 / 1.926 / 1.935 / 1.233 / 0.276; dense unchanged 0.104 -/
theorem r7_cells : step7Moe dfr32 = 127788019 ∧ tpsCard 1000 (step7Moe dfr32) = 1956 ∧
    step7Moe (amort 80) = 129743539 ∧ tpsCard 1000 (step7Moe (amort 80)) = 1926 ∧
    step7Moe (amort 55) = 129132439 ∧ tpsCard 1000 (step7Moe (amort 55)) = 1935 ∧
    step7Moe dfr128 = 202640419 ∧ tpsCard 1000 (step7Moe dfr128) = 1233 ∧
    step7Moe dfr1M = 904746019 ∧ tpsCard 1000 (step7Moe dfr1M) = 276 ∧
    stepDense dfr32 = 2403248669 ∧ tpsCard 1000 (stepDense dfr32) = 104 := by decide
/-- the realized-launch reading: (launches + 2) × (91 − 36) µs; 2.103 / 0.105 -/
theorem r7_launch : (28 * 7 + 2) * (tLaunch - tLaunchRealized) = 10890000 ∧
    (120 * 6 + 2) * (tLaunch - tLaunchRealized) = 39710000 ∧
    tpsCard 1000 (step7Moe (amort 80) - 10890000) = 2103 ∧
    tpsCard 1000 (stepDense dfr32 - 39710000) = 105 := by decide
/-- two instances at the measured card-scale 2.0× / the die-scale 1.99×: 3.853 / 3.834 -/
theorem r7_inst : tpsInst 1000 2000 (step7Moe (amort 80)) = 3853 ∧ tpsInst 1000 1990 (step7Moe (amort 80)) = 3834 := by decide

/-! ## 3. The 32k tie (fusion gain 28·(legacy − T) against E29) — re-proved ∀ T, and its break-even trip rate -/
theorem tie32k_line (T : Nat) (hT : T ≤ legacy32) :
    (e29Banked ≤ 28 * (legacy32 - T) ↔ T ≤ 991940) ∧ (e29Banked < 28 * (legacy32 - T) ↔ T ≤ 991939) := by
  have h : e29Banked = 14642880 := by decide
  unfold legacy32 at *
  rw [h]
  refine ⟨⟨fun h1 => ?_, fun h1 => ?_⟩, ⟨fun h1 => ?_, fun h1 => ?_⟩⟩ <;> omega
theorem tie32k_cells : 991940 < amort 55 ∧ amort 55 < amort 80 ∧ amort 55 - 991940 = 1575 ∧ amort 80 - 991940 = 23400 ∧
    e29Banked - 28 * (legacy32 - amort 80) = 655200 ∧ e29Banked - 28 * (legacy32 - amort 55) = 44100 := by decide
/-- the 128k / 1M fusion-vs-E29 lines at the derived E29 (T6r_tie_lines: 5 286 379 / 45 747 079 strict) and at the banked one -/
theorem tie_lines_other_L : 5852900 - e29Derived / 28 = 5286380 ∧ 46313600 - e29Derived / 28 = 45747080 ∧
    5852900 - e29Banked / 28 = 5329940 ∧ 46313600 - e29Banked / 28 = 45790640 ∧
    dfr128 < 5329940 ∧ dfr1M < 45790640 := by decide

/-- **challenge C-1.** With T(p) = 945 500 + p·873 µs (p in 0.1 % of launches) and the BANKED E29, fusion ≥ E29
    iff p ≤ 53 — a break-even trip rate of 5.3 % of launches, not the 0.19 % HW-MAP / DESIGN-4 / PC-4 R7.1 quote.
    The measured 8.0 % / 5.5 % are 1.5× / 1.04× over the line (not 42× / 29×); the wide-cap verdict rests on a
    0.18-point margin of a measured rate. -/
theorem challenge_breakeven_banked (p10 : Nat) : (e29Banked ≤ 28 * (legacy32 - amort p10) ↔ p10 ≤ 53) := by
  have h : e29Banked = 14642880 := by decide
  unfold amort dfr32 rTrip legacy32
  rw [h]
  constructor <;> intro h1 <;> omega
/-- the 0.19 % figure IS the break-even of the round-6 line (the DERIVED E29 against the session-3 legacy
    1 513 600): p ≤ 18 in 0.01 % units = 0.18 % -/
theorem breakeven_derived_line (p100 : Nat) :
    (e29Derived ≤ 28 * (1513600 - (dfr32 + p100 * 8730 / 100)) ↔ p100 ≤ 18) := by
  have h : e29Derived = 15862560 := by decide
  unfold dfr32
  rw [h]
  constructor <;> intro h1 <;> omega
theorem breakeven_ratios : 80 / 53 = 1 ∧ 55 / 53 = 1 ∧ 80 * 100 / 53 = 150 ∧ 55 * 100 / 53 = 103 ∧
    80 * 100 / 19 = 421 ∧ 55 * 100 / 19 = 289 := by decide

/-- the deferred guard beats the legacy scan iff the trip rate (per 10⁵ steps) ≤ 65 253 at 32k (R = 872 600) -/
theorem trip_breakeven_legacy (p : Nat) : 100000 * dfr32 + p * 872600 < 100000 * legacy32 ↔ p ≤ 65253 := by
  unfold dfr32 legacy32
  constructor <;> intro h1 <;> omega
/-- the amortized band at the stale premise (0.087–0.22 % of steps) reproduces 946 259 / 947 419 — a two-point line
    through two measured cells evaluated at a third point, not a third measurement -/
theorem amort_band_premise : dfr32 + 87 * 872600 / 100000 = 946259 ∧ dfr32 + 220 * 872600 / 100000 = 947419 ∧
    1818100 - dfr32 = 872600 := by decide
/-- **challenge C-8** (reviewer P3-F8): at the MEASURED 8 % trip rate the 1M cell is +7.6 %, not +0.08–0.21 % -/
theorem challenge_amort_1M : dfr1M + 80 * (56000000 - dfr1M) / 1000 = 30878480 ∧
    (30878480 - dfr1M) * 1000 / dfr1M = 76 := by decide

/-! ## 4. Minimum dies (T_min_dies): a pigeonhole on 86 GB per die -/
def dieMem : Nat := 86 * GB
def wResDense : Nat := denseLayerBytes
def wResMoe : Nat := moeAttnBytes + moeExpertBytesLayer
theorem totals : 120 * wResDense + 2 * headBytesDense = 386723217408 ∧ 28 * wResMoe + 2 * headBytesMoe = 363002331136 ∧
    4 * dieMem < 120 * wResDense + 2 * headBytesDense ∧ 4 * dieMem < 28 * wResMoe + 2 * headBytesMoe := by decide
theorem min_dies_dense (n0 n1 n2 n3 : Nat) (h : n0 + n1 + n2 + n3 = 120) :
    dieMem < n0 * wResDense ∨ dieMem < n1 * wResDense ∨ dieMem < n2 * wResDense ∨ dieMem < n3 * wResDense := by
  have h30 : 30 ≤ n0 ∨ 30 ≤ n1 ∨ 30 ≤ n2 ∨ 30 ≤ n3 := by omega
  have hw : dieMem < 30 * wResDense := by decide
  rcases h30 with h0 | h1 | h2 | h3
  · exact Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h0))
  · exact Or.inr (Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h1)))
  · exact Or.inr (Or.inr (Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h2))))
  · exact Or.inr (Or.inr (Or.inr (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h3))))
theorem min_dies_moe (n0 n1 n2 n3 : Nat) (h : n0 + n1 + n2 + n3 = 28) :
    dieMem < n0 * wResMoe ∨ dieMem < n1 * wResMoe ∨ dieMem < n2 * wResMoe ∨ dieMem < n3 * wResMoe := by
  have h7 : 7 ≤ n0 ∨ 7 ≤ n1 ∨ 7 ≤ n2 ∨ 7 ≤ n3 := by omega
  have hw : dieMem < 7 * wResMoe := by decide
  rcases h7 with h0 | h1 | h2 | h3
  · exact Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h0))
  · exact Or.inr (Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h1)))
  · exact Or.inr (Or.inr (Or.inl (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h2))))
  · exact Or.inr (Or.inr (Or.inr (Nat.lt_of_lt_of_le hw (Nat.mul_le_mul_right _ h3))))
/-- five dies: 24 dense layers + embed + 2 GiB + 64 MiB + KV(4k) = 81.2 GB fits; 6 MoE layers + embed = 80.4 -/
theorem five_dies_fit : 24 * wResDense + headBytesDense + 2 * GiB + 64 * MiB + 24 * 4096 * 4096 ≤ dieMem ∧
    6 * wResMoe + headBytesMoe + 2 * GiB + 64 * MiB + 6 * 4096 * 4096 ≤ dieMem ∧
    (24 * wResDense + headBytesDense + 2 * GiB + 64 * MiB + 24 * 4096 * 4096) / 100000000 = 812 ∧
    30 * wResDense / 100000000 = 956 ∧ 7 * wResMoe / 100000000 = 904 := by decide
/-- **challenge C-10** (taint row 1): the whole 5-die verdict stands on erratum 12 (int8 residency); at the int4
    source size (193.3 / 181.5 GB) three dies would suffice for the weights of either shape (258 GB of room) -/
theorem challenge_min_dies_int4 : (120 * wResDense + 2 * headBytesDense) / 2 ≤ 3 * dieMem ∧
    (28 * wResMoe + 2 * headBytesMoe) / 2 ≤ 3 * dieMem ∧ 2 * dieMem < (120 * wResDense + 2 * headBytesDense) / 2 := by decide

/-! ## 5. Speculative decoding thresholds (T6r_spec6_thresholds, T6r_spec_dense_line, T_spec_dense_breakeven) -/
/-- D ([R6-spec6-steps]): the t = 4 MoE verify step at the deferred cell; rebuilt below from components -/
def T4r6 : Nat := 456819203
/-- D: the t = 4 expert term D(4) = 32 experts; the draft term (k = 3 tokens of 1 GB i8 + 4k window + 121 launches +
    24 × 4 quant passes + logits D2H + 2 λ): 22 129 841 ns per draft token -/
def draftTok : Nat := tn (1 * GB) rGemm + tn (24 * 4096 * (2 * 8 * 64 * 2)) rGemm + 121 * tLaunch
  + 24 * 4 * tQuant + tn (128256 * 4) 273 + 2 * lam
def gemmLayerMoeT4 : Nat := tn moeAttnBytes rGemm + 2 * fMoe + 32 * 3 * tSlabSer
def xchMoeRows4 : Nat := 97484 + 16 * lam
def xchDenseRows4 : Nat := 164443 + 16 * lam
theorem t4_steps_from_components : draftTok = 22129841 ∧
    28 * gemmLayerMoeT4 + headMoe + (28 * 7 + 2) * tLaunch + 28 * 4 * tQuant + xchMoeRows4 + 3 * draftTok + 28 * dfr32 = T4r6 ∧
    120 * gemmLayerDense + headDense + (120 * 6 + 2) * tLaunch + 120 * 4 * tQuant + xchDenseRows4 + 3 * draftTok = 2356301528 := by decide
/-- MoE: spec decode (k = 3) loses for every α ≤ 0.854 on the round-6 inputs (the quoted line) -/
theorem spec_moe_loss_line : ∀ a, a < 1001 → (tau3 a * stepMoe dfr32 < 1000 * T4r6 ↔ a ≤ 854) := by decide +kernel
/-- dense: spec (k = 3, α = 0.7) beats t = 1 for every verify-kernel attention v ≤ 31 092 727 ns per layer -/
theorem spec_dense_line (v : Nat) : 1000 * (2356301528 + 120 * v) < tau3 700 * stepDense dfr32 ↔ v ≤ 31092727 := by
  have h1 : tau3 700 = 2533 := by decide
  have h2 : stepDense dfr32 = 2403248669 := by decide
  rw [h1, h2]
  constructor <;> intro h <;> omega
/-- dense at the fragment-serial verify reading v = 3 782 000: a gain for every α ≥ 0.146 -/
theorem spec_dense_alpha : ∀ a, a < 1001 → (1000 * (2356301528 + 120 * 3782000) < tau3 a * stepDense dfr32 ↔ 146 ≤ a) := by decide +kernel
/-- the round-2 dense break-even α ≥ 0.024 (τ ≥ T4/T1 = 1.023) -/
theorem spec_dense_r2 : ∀ a, a < 1001 → (1000 * 2416719328 < tau3 a * 2362319269 ↔ 24 ≤ a) := by decide +kernel
/-- **challenge C-7.** Round 7 banked E29 only on the t = 1 side: with the t ≥ 4 slab 98 573 banked on the verify
    step too (32 experts × 3 slabs × 28 layers), the MoE loss line moves 0.854 → 0.823 (a number moves, no flip). -/
theorem challenge_spec_moe_r7 : 28 * 32 * 3 * (tSlabSer - slabM0T4) = 65603328 ∧
    (∀ a, a < 1001 → (tau3 a * step7Moe dfr32 < 1000 * (T4r6 - 65603328) ↔ a ≤ 823)) := by
  refine ⟨by decide, ?_⟩
  decide +kernel
/-- **challenge C-7′.** The MoE verify step prices its attention at the t = 1 cell (28 × 945 500); the only measured
    t = 4 cell is the legacy kernel's 2 695 600 ns. For every t = 4 attention a4 ≥ the t = 1 cell the loss region
    contains α ≤ 0.854 — the quoted line is a LOWER bound on the loss region, hostage to E41's t = 4 cell. -/
theorem challenge_spec_moe_t4_attention (a4 : Nat) (h4 : dfr32 ≤ a4) :
    ∀ a, a ≤ 854 → tau3 a * stepMoe dfr32 < 1000 * (T4r6 - 28 * dfr32 + 28 * a4) := by
  intro a ha
  have hmono : tau3 a ≤ 3206 := by
    have : ∀ b, b < 855 → tau3 b ≤ 3206 := by decide +kernel
    exact this a (by omega)
  have h1 : stepMoe dfr32 = 142430899 := by decide
  rw [h1]
  unfold T4r6 dfr32 at *
  have : tau3 a * 142430899 ≤ 3206 * 142430899 := Nat.mul_le_mul_right _ hmono
  omega
/-- the mechanism (T_spec_moe_mechanism): uniform D(4) = 4·D(1) → T4 ≥ 4 E1 + (T1 − E1); with E1 = 82.64 ms
    of 133.84 any τ < 1 + 3 E1/T1 = 2.852 is a loss before the draft is counted -/
theorem spec_moe_mechanism : 28 * 24 * tSlabSer = 82641888 ∧ 4 * 82641888 + (133847319 - 82641888) = 381772983 ∧
    1000 + 3 * 82641888 * 1000 / 133847319 = 2852 := by decide


/-! ## 6. The instance family (ALT-2 / V3): fit, margin, break-even, die-scale gain -/
/-- A (H8): 2 GiB runtime overhead + 64 MiB workspace per die -/
def oRt : Nat := 2 * GiB
def ws : Nat := 64 * MiB
/-- resident bytes on die `pos` of a 4-die MoE instance (7 layers each) when x‰ of the expert bytes are int4 -/
def dieW (pos x : Nat) : Nat := 7 * (moeAttnBytes + moeExpertBytesLayer - moeExpertBytesLayer * x / 2000)
  + (if pos = 0 then headBytesMoe else 0) + (if pos = 3 then headBytesMoe else 0)
def dieKv (L : Nat) : Nat := 7 * 4096 * L
/-- the die fits at overhead `o` (Bool so that `decide` evaluates it) -/
def fitsO (pos x L o : Nat) : Bool := dieW pos x + dieKv L + ws + o ≤ dieMem
def fits (pos x L : Nat) : Bool := fitsO pos x L oRt
/-- the minimal int4 shares [182, 170, 170, 182] at 32k and [827, 816, 816, 827] at 1M are minimal (iff) -/
theorem inst_fit_32k : fits 0 182 32768 = true ∧ fits 0 181 32768 = false ∧ fits 1 170 32768 = true ∧
    fits 1 169 32768 = false ∧ fits 2 170 32768 = true ∧ fits 2 169 32768 = false ∧
    fits 3 182 32768 = true ∧ fits 3 181 32768 = false := by decide
theorem inst_fit_1M : fits 0 827 1048576 = true ∧ fits 0 826 1048576 = false ∧ fits 1 816 1048576 = true ∧
    fits 1 815 1048576 = false := by decide
/-- the per-die margins at the minimal x: 40.3 / 24.5 / 24.5 / 40.3 MB ([ALT-P-margin-moe-32768]: [40, 24, 24, 40]) -/
theorem inst_margin_32k : dieMem - (dieW 0 182 + dieKv 32768 + ws + oRt) = 40314817 ∧
    dieMem - (dieW 1 170 + dieKv 32768 + ws + oRt) = 24485516 := by decide
/-- the margin is a rounding remainder of the per-mille x grid: one x step is 7 × 12 GiB / 2000 = 45.1 MB -/
theorem inst_margin_is_grid : 7 * moeExpertBytesLayer / 2000 = 45097156 ∧ 40314817 < 45097156 ∧ 24485516 < 45097156 := by decide
/-- +1 GB of overhead costs +22 ‰ of x ([ALT-P-margin]: minimal x at +1 GB = [204, 192, 192, 204]) -/
theorem inst_dx_per_gb : (GB * 2000 + 7 * moeExpertBytesLayer - 1) / (7 * moeExpertBytesLayer) = 23 ∧
    fitsO 0 204 32768 (oRt + GB) = true ∧ fitsO 0 203 32768 (oRt + GB) = false ∧
    fitsO 1 192 32768 (oRt + GB) = true ∧ fitsO 1 191 32768 (oRt + GB) = false := by decide

/-- the instance step (alt.py inst_step re-implemented): per layer tn(attn) + 2F + 24·(T_hot·(1−x) + T_cold·x)
    floored, + the round-2 attention 768 715 + 7 launches; head + 2 launches; the chain exchange 8 λ + hops -/
def attnGemmMoe : Nat := 240223
def attn32kR2 : Nat := 768715
def wLayerInst (x Th Tc : Nat) : Nat := attnGemmMoe + 2 * fMoe + 24 * (Th * (1000 - x) + Tc * x) / 1000
/-- the 4-die instance exchange: hops d1→host→d0→host→d1→host→d0 at the link rates + logits + 8 λ (λ = 91 µs) -/
def instXch : Nat := (tn 8192 190 + tn 8192 276) + (tn 8192 273 + tn 8192 139) + (tn 8192 190 + tn 8192 276)
  + tn (128256 * 4) 273 + tn 4 139 + 8 * tLaunch
def instStep (Tc : Nat) : Nat :=
  7 * (wLayerInst 182 tSlabDirect Tc + attn32kR2 + 7 * tLaunch) + 7 * (wLayerInst 170 tSlabDirect Tc + attn32kR2 + 7 * tLaunch)
  + 7 * (wLayerInst 170 tSlabDirect Tc + attn32kR2 + 7 * tLaunch) + 7 * (wLayerInst 182 tSlabDirect Tc + attn32kR2 + 7 * tLaunch)
  + headMoe + 2 * tLaunch + instXch
/-- M: the measured 5.3 GB/s/core int4 unpack → 1 MiB of int4 per core-slab in 197 844 ns -/
def tSlabW4 : Nat := tn MiB 53
def T0moe32k : Nat := 133847319
theorem inst_cells : tSlabW4 = 197844 ∧ instXch = 749135 ∧ instStep tSlabW4 / 10000 = 12889 ∧
    tpsInst 1000 2000 (instStep tSlabW4) = 3878 ∧ tpsCard 1000 T0moe32k = 1867 := by decide
/-- two instances beat one iff the instance step is under twice the chain step: iff T_cold ≤ 1 371 367 ns
    (the corpus's 1 371 124 is the same line read through the floored-thousandths tps: 1 371 125 here) -/
theorem inst_breakeven_iff (Tc : Nat) : instStep Tc < 2 * T0moe32k ↔ Tc ≤ 1371366 := by
  simp only [instStep, wLayerInst, attnGemmMoe, attn32kR2, tSlabDirect, fMoe, instXch, headMoe, tn, headBytesMoe, rGemm,
    tLaunch, T0moe32k]
  constructor <;> intro h <;> omega
/-- read through the floored-thousandths tps (the corpus's criterion) the line is exactly the printed 1 371 124 -/
theorem inst_breakeven_tps_cells : 1867 < tpsInst 1000 2000 (instStep 1371124) ∧
    ¬ (1867 < tpsInst 1000 2000 (instStep 1371125)) := by decide
theorem inst_margin_6_9x : 1371124 * 10 / tSlabW4 = 69 ∧ instStep 413184 < 2 * T0moe32k ∧ instStep 230458 < 2 * T0moe32k := by decide
/-- the die-scale gain η needed by two instances (ALT-P-h10): 3 878·η > 1 867 iff η ≥ 482 ‰ -/
theorem inst_eta_line (eta : Nat) : 1867 < eta * 3878 / 1000 ↔ 482 ≤ eta := by
  constructor <;> intro h <;> omega

/-! ## 7. MoE-128k: attention-bound vs weights-bound (T3r_moe128k_tie legs-conditional, T6r_fleet_moe_128k) -/
/-- the round-4 per-layer attention at 128k: 256 blocks × (2 MiB K+V + legs × 128 KiB bounce)/G + fixed 19 328 -/
def fixed4 : Nat := 19328
def attnLegs (G nb legs : Nat) : Nat := nb * tn (2 * MiB + legs * 128 * KiB) G + fixed4
/-- the floor-division line: 256·⌊num/G⌋ + 19 328 ≥ c ⇔ ⌊num/G⌋ ≥ q ⇔ q·G ≤ num (Nat.le_div_iff_mul_le) -/
theorem attnLegs_forms (G : Nat) : attnLegs G 256 2 = 256 * (23592960 / G) + 19328 ∧
    attnLegs G 256 1 = 256 * (22282240 / G) + 19328 ∧ attnLegs G 256 0 = 256 * (20971520 / G) + 19328 := by
  simp only [attnLegs, tn, MiB, KiB, fixed4, Nat.reduceMul, Nat.reduceAdd]
  first
  | exact ⟨trivial, trivial, trivial⟩
  | exact ⟨rfl, rfl, rfl⟩
/-- attention-bound iff G ≤ 189.4 / 178.9 / 168.3 GB/s at legs 2 / 1 / 0 — for every G > 0 -/
theorem moe128k_legs_lines (G : Nat) (hG : 0 < G) :
    (gemmLayerMoe ≤ attnLegs G 256 2 ↔ G ≤ 1894) ∧ (gemmLayerMoe ≤ attnLegs G 256 1 ↔ G ≤ 1789) ∧
    (gemmLayerMoe ≤ attnLegs G 256 0 ↔ G ≤ 1683) := by
  have hc : gemmLayerMoe = 3207719 := by decide
  obtain ⟨f2, f1, f0⟩ := attnLegs_forms G
  rw [hc, f2, f1, f0]
  refine ⟨⟨fun h => ?_, fun h => ?_⟩, ⟨fun h => ?_, fun h => ?_⟩, ⟨fun h => ?_, fun h => ?_⟩⟩
  · have hq : 12455 ≤ 23592960 / G := by omega
    have := (Nat.le_div_iff_mul_le hG).mp hq
    omega
  · have : 12455 ≤ 23592960 / G := (Nat.le_div_iff_mul_le hG).mpr (by omega)
    omega
  · have hq : 12455 ≤ 22282240 / G := by omega
    have := (Nat.le_div_iff_mul_le hG).mp hq
    omega
  · have : 12455 ≤ 22282240 / G := (Nat.le_div_iff_mul_le hG).mpr (by omega)
    omega
  · have hq : 12455 ≤ 20971520 / G := by omega
    have := (Nat.le_div_iff_mul_le hG).mp hq
    omega
  · have : 12455 ≤ 20971520 / G := (Nat.le_div_iff_mul_le hG).mpr (by omega)
    omega
theorem moe128k_legs_cells : attnLegs 1692 256 2 = 3588736 ∧ attnLegs 1692 256 0 = 3192192 ∧ gemmLayerMoe = 3207719 ∧
    3192192 < gemmLayerMoe ∧ gemmLayerMoe < 3588736 := by decide
/-- the measured deferred cell at 128k against the anchored layer: +12.8 % ([R6-fleet-moe-128k]) -/
theorem moe128k_measured : dfr128 - gemmLayerMoe = 411081 ∧ 411081 * 1000 / gemmLayerMoe = 128 := by decide
/-- **challenge C-9.** On the round-7 anchor the MoE layer GEMM is 2 684 759 ns (3.21 → 2.68 ms) and the measured
    128k cell is attention-bound by 34.8 %, not 12.8 %; the legs-conditional iff is moot — on that anchor the cell is
    attention-bound at every gather rate up to 226.5 GB/s, above the DDR roof. -/
def gemmLayerMoeM0 : Nat := gemmLayerMoe - 24 * (tSlabSer - slabM0)
theorem challenge_moe128k_anchor (G : Nat) (hG : 0 < G) : gemmLayerMoeM0 = 2684759 ∧
    (dfr128 - gemmLayerMoeM0) * 1000 / gemmLayerMoeM0 = 347 ∧
    (gemmLayerMoeM0 ≤ attnLegs G 256 2 ↔ G ≤ 2265) ∧ 1810 < 2265 := by
  have hc : gemmLayerMoeM0 = 2684759 := by decide
  obtain ⟨f2, _, _⟩ := attnLegs_forms G
  refine ⟨hc, by decide, ?_, by decide⟩
  rw [hc, f2]
  constructor
  · intro h
    have hq : 10412 ≤ 23592960 / G := by omega
    have := (Nat.le_div_iff_mul_le hG).mp hq
    omega
  · intro h
    have : 10412 ≤ 23592960 / G := (Nat.le_div_iff_mul_le hG).mpr (by omega)
    omega

/-! ## 8. Drift (T4r_drift_online / T5r_drift): the two-level f32 chain lengths and the ppm bound -/
def coSets : Nat → Nat
  | 512 => 4
  | 256 => 2
  | 1024 => 8
  | _ => 0
def chainO (L b : Nat) : Nat := (coSets b - 1) + 1 + L / b
def chainS (L b : Nat) : Nat := b * 16 / 1024 + 2 + L / b + 4
/-- ceil(n · 2⁻²⁴ · 10⁶): the first-order relative error of an n-term f32 chain in ppm -/
def relPpm (n : Nat) : Nat := (n * 1000000 + 16777215) / 16777216
theorem drift_1M : chainO 1048576 512 = 2052 ∧ chainS 1048576 512 = 2062 ∧ relPpm 2052 + relPpm 2062 = 246 ∧
    chainO 1048576 256 = 4098 ∧ chainS 1048576 256 = 4106 ∧ relPpm 4098 + relPpm 4106 = 490 ∧
    chainO 1048576 1024 = 1032 ∧ chainS 1048576 1024 = 1046 ∧ relPpm 1032 + relPpm 1046 = 125 ∧
    relPpm 8192 = 489 ∧ 246 < 1000 := by decide
/-- the measured 1.2 / 1.8 ppm sit 205× / 272× inside the bound and 833× / 555× inside the 1e-3 line -/
theorem drift_measured : 246 * 10 / 12 = 205 ∧ 490 * 10 / 18 = 272 ∧ 10000 / 12 = 833 ∧ 10000 / 18 = 555 := by decide
/-- **challenge C-11** (reviewer P3-F5): the f16 cast of P (DESIGN-3 §3.2 step 5) perturbs every weight by up to
    2⁻¹¹ = 488 ppm — outside the drift theorems and only 2.0× inside the 1e-3 ship line -/
theorem challenge_f16_P_cast : 1000000 / 2048 = 488 ∧ 488 < 1000 ∧ 1000 / 488 = 2 := by decide

/-! ## 9. E40 — the stage-overlap bound and its φ gate (T40_prize_*, T40_phi_gate) -/
/-- M (session 3): the K+V stream phase and the realised bounce at 32k; E21's per-page time at 256 KiB -/
def streamPhase32k : Nat := 770800
def bounce32k : Nat := 51000
def tPage256 : Nat := 12394
/-- per-tile DDR time d = 770 800 / (64 blocks × 8 tiles) -/
def dTile : Nat := streamPhase32k / 512
def floorF1 : Nat := streamPhase32k + bounce32k
def floorF2 : Nat := 64 * tPage256 + bounce32k
theorem e40_floor_prize : dTile = 1505 ∧ floorF1 = 821800 ∧ floorF2 = 844216 ∧ dfr32 - floorF1 = 123700 ∧
    dfr32 - floorF2 = 101284 ∧ 123700 * 1000 / dfr32 = 130 ∧ 101284 * 1000 / dfr32 = 107 := by decide
/-- E40 beats the deferred kernel iff nb·(V − k·d)⁺ + nb·k·φ + end read < deferred − floor -/
def e40Beats (V k phi endr floor : Nat) : Prop := 64 * (V - k * dTile) + 64 * k * phi + endr < dfr32 - floor
theorem e40_phi_gate (phi : Nat) : (e40Beats 1594 1 phi 10000 floorF1 ↔ phi ≤ 1687) ∧
    (e40Beats 1438 2 phi 20000 floorF2 ↔ phi ≤ 635) ∧ (e40Beats 1750 2 phi 0 floorF1 ↔ phi ≤ 966) ∧
    (e40Beats 1750 8 phi 0 floorF1 ↔ phi ≤ 241) := by
  simp only [e40Beats, dTile, streamPhase32k, floorF1, floorF2, bounce32k, tPage256, dfr32]
  refine ⟨⟨fun h => ?_, fun h => ?_⟩, ⟨fun h => ?_, fun h => ?_⟩, ⟨fun h => ?_, fun h => ?_⟩, ⟨fun h => ?_, fun h => ?_⟩⟩ <;> omega
/-- at erratum #29's band (10–20 µs per crossing) E40 is dead: the gate is 5.9–11.9× below it -/
theorem e40_dead_at_band : ¬ e40Beats 1594 1 10000 10000 floorF1 ∧ 10000 / 1687 = 5 ∧ 20000 / 1687 = 11 := by
  refine ⟨?_, by decide, by decide⟩
  simp only [e40Beats, dTile, streamPhase32k, floorF1, bounce32k, dfr32]
  decide
/-- **challenge C-12** (reviewer P3-F4): if the deferred kernel's softmax phase is the 565 µs HW-MAP quotes
    (8 828 ns per block = 5.9 × d), E40 cannot beat it at k ≤ 2 for ANY φ; only k = 8 (gate φ ≤ 241 ns) remains -/
theorem challenge_e40_V565 (phi : Nat) : ¬ e40Beats (565000 / 64) 2 phi 0 floorF1 ∧ 565000 / 64 = 8828 ∧
    (e40Beats 8828 8 phi 0 floorF1 ↔ phi ≤ 241) := by
  simp only [e40Beats, dTile, streamPhase32k, floorF1, bounce32k, dfr32]
  refine ⟨?_, by decide, ⟨fun h => ?_, fun h => ?_⟩⟩ <;> omega
/-- **challenge C-13** (reviewer P3-F7): E40's prologue page-table fetch is O(L): 16 KiB at 1M, and at mt = 4 the
    US budget 200 768 + 16 384 − 4 096 = 213 056 B exceeds the 208 KiB evidence by the 64 B round 2 once corrected -/
theorem challenge_e40_pagetable : 2 * 1024 * 8 = 16384 ∧ 200768 - 4096 + 16384 = 213056 ∧ 208 * KiB = 212992 ∧
    213056 - 212992 = 64 := by decide

/-! ## 10. The megakernel threshold (T3r_mega_threshold) at the primary and the realized launch -/
theorem mega_lines : 120 * 5 * tLaunch / 480 = 113750 ∧ (120 * 5 * tLaunch - 120 * 15388) / 480 = 109903 ∧
    28 * 6 * tLaunch / 140 = 109200 ∧ (120 * 5 * tLaunchRealized - 120 * 15388) / 480 = 41153 ∧
    28 * 6 * tLaunchRealized / 140 = 43200 ∧ 20000 < 41153 := by decide
theorem mega_dense_iff (c : Nat) : 480 * c + 120 * 15388 ≤ 120 * 5 * tLaunch ↔ c ≤ 109903 := by
  unfold tLaunch; constructor <;> intro h <;> omega
theorem mega_dense_realized_iff (c : Nat) : 480 * c + 120 * 15388 ≤ 120 * 5 * tLaunchRealized ↔ c ≤ 41153 := by
  unfold tLaunchRealized; constructor <;> intro h <;> omega

/-! ## 11. Two-tier pages (ALT-P-tier-floor): the tier saves 15·c_pg − 12 ns per extent — faster iff c_pg ≥ 1 ns -/
theorem tier_iff (c : Nat) : 12 < 15 * c ↔ 1 ≤ c := by constructor <;> intro h <;> omega
/-- at the measured lower bound c_pg = 38 ns the tier gains 1.1 % (174.4 vs 172.4, tenths) -/
theorem tier_38 : (1744 - 1724) * 1000 / 1724 = 11 := by decide

/-! ## 12. DESIGN-2 — overflow bound, dispatch, floors -/
/-- U_max = 32 (31 with −128 codes), 18 at K = 7168: the i32 saturation measurement made the clamp mandatory -/
theorem overflow_umax : 32 * (127 * 127 * 4096) < 2 ^ 31 ∧ 2 ^ 31 ≤ 33 * (127 * 127 * 4096) ∧
    32 * (128 * 128 * 4096) = 2 ^ 31 ∧ 18 * (127 * 127 * 7168) < 2 ^ 31 ∧ 2 ^ 31 ≤ 19 * (127 * 127 * 7168) := by decide
/-- **challenge C-14** (reviewer P2-F1): under the MEASURED saturating semantics with nondeterministic L0C content b,
    the region difference is exact only if |b| + U·127²·4096 < 2³¹: at b = 0x3F800000 (an f32 1.0 pattern) U_max is 16,
    at b ≥ 0x7F000000 one expert saturates -/
theorem challenge_overflow_prior_content : (2 ^ 31 - 1 - 1065353216) / (127 * 127 * 4096) = 16 ∧
    (2 ^ 31 - 1 - 2130706432) / (127 * 127 * 4096) = 0 := by decide
/-- dispatch hides under expert 0's chain iff σ_d ≤ 968 ns (127 remaining iterations) -/
theorem dispatch_hide (s : Nat) : 127 * s ≤ tSlabSer ↔ s ≤ 968 := by unfold tSlabSer; constructor <;> intro h <;> omega
/-- the headline 135.3 GB/s vs the vendor 24.6: 5.5× -/
theorem vendor_floor : 1353 * 10 / 246 = 55 ∧ 1658 * 10 / 246 = 67 := by decide
/-- the K-split margins at the realized launch (reviewer P2-F3): (4,32) and (16,68) flip sign at 36 µs -/
theorem challenge_ksplit_realized : 45838 + 36000 < 91000 ∧ 40280 + 36000 < 91000 ∧ 91000 - 45838 = 45162 := by decide

/-! ## 13. DESIGN.md — the ceiling, the loader line, the measured route -/
theorem d7_1 : tn (8 * (8 * MiB + 256 * KiB)) 1738 = 398193 ∧ (64 * MiB) * 10 / 398193 = 1685 ∧
    (64 * MiB) * 10 / (tn (8 * (8 * MiB + 256 * KiB)) 1800) = 1745 := by decide
/-- the loader-bound branch: 8·L·64/66 ≥ 168.5 iff L ≥ 21.8 GB/s/core (tenths) -/
theorem loader_line (L : Nat) : 1685 * 66 ≤ 8 * L * 64 ↔ 218 ≤ L := by constructor <;> intro h <;> omega
/-- the measured production route (174.6 flat m = 1..16) beat the modelled in-kernel ceiling (168.5) because the
    173.8 "roof" was a read+write stream; at the pure-read 181.3 with i8 A (64/65) the ceiling is 178.5 -/
theorem ceiling_reread : 1685 < 1746 ∧ 1813 * 64 / 65 = 1785 ∧ 1746 * 1000 / 1785 = 978 := by decide
/-- the m ≥ 24 cliff 81 / 59 / 43 equals the flat rate divided by the strip count (reviewer P1-F1): 87.3 / 58.2 / 43.6 -/
theorem challenge_rows_cliff_strips : 1746 / 2 = 873 ∧ 1746 / 3 = 582 ∧ 1746 / 4 = 436 ∧
    81 * 100 / 87 = 93 ∧ 59 * 100 / 58 = 101 ∧ 43 * 100 / 43 = 100 := by decide

/-! ## 14. CHEAT-MATH — the CRT theorem without `native_decide`, and the roofline's unit error -/
/-- `Cheat.crt_15_16` is proved by `native_decide` in cheat.lean (its `#print axioms` lists
    `Cheat.crt_15_16._native.native_decide.ax_1_1`), against the corpus rule. The statement is a core theorem: -/
theorem crt_15_16_core (x y : Nat) (hx : x < 240) (hy : y < 240) (h15 : x % 15 = y % 15) (h16 : x % 16 = y % 16) :
    x = y := by omega
theorem ridge_as_stated : 48 * 170 < 8192 ∧ 8192 < 49 * 170 := by decide
/-- **challenge C-15.** The "8192 OPs per cycle" peak is one 16³ fragment per cycle on ONE core; the die's MEASURED
    17.8 TFLOPS against 173.8 GB/s gives a ridge of 102 OPs/byte (free rows ≤ 51 on W8), and the per-core lane
    budget 43.2 G/s × 8 = 345.6 G lane-ops/s per die ≈ the 4-bit stream's 347.6 G elem/s: one lane-op per element,
    so the MEASURED 5-pass unpack (42 GB/s = 84 G elem/s) is 24 % of the stream, not "< 12 %". -/
theorem challenge_ridge_units : 178000 / 1738 = 102 ∧ 8 * 8192 = 65536 ∧ 8 * 432 = 3456 ∧ 2 * 1738 = 3476 ∧
    840 * 1000 / 3476 = 241 ∧ ¬ (840 * 100 < 12 * 3476) ∧ 102 / 2 = 51 ∧ 16 * 4 < 102 := by decide
/-- the HW-MAP occupancy at m = 1 is 12.5 % (61 of 487 µs), not the "4–8 %" CHEATSHEET §0 attributes to the machine -/
theorem challenge_occupancy : 61 * 1000 / 487 = 125 := by decide


/-! ## 15. DESIGN-FORK-EP8 — expert placement across the 8 dies with a host all-reduce per layer ([FORK-EP-*])

The fork's premise is a MEASURED fact the dominated-alternatives table predates: two dies of one card driven by
one process stream concurrently at 1.000–1.001 of their solo sum, and disjoint cards at 2.0× (HW-MAP, season h).
Erratum 11's "no concurrent streaming" is a property of the vendor runtime's layer-split loop, not of the silicon.
Rung EP-A places the 256 experts of every layer over the 8 dies (32 per die, 45 GB resident) and runs each layer's
active experts on their owning dies concurrently; attention stays on the layer-split chain. Rung EP-B additionally
splits the 8 KV heads one per die (the KV written die-locally to its head). -/
namespace ForkEP

def fact : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * fact n
def prodFact : List Nat → Nat
  | [] => 1
  | x :: xs => fact x * prodFact xs
def count (v : Nat) : List Nat → Nat
  | [] => 0
  | x :: xs => (if x = v then 1 else 0) + count v xs
/-- labelled balls into labelled bins realising the sorted load vector l: 8!/Π(mult_v!) × 8!/Π(a_i!) -/
def ways (l : List Nat) : Nat := (fact 8 / prodFact ((List.range 9).map (fun v => count v l))) * (fact 8 / prodFact l)
def maxL : List Nat → Nat
  | [] => 0
  | x :: xs => max x (maxL xs)
/-- the 22 partitions of 8 into at most 8 parts (the load vectors of 8 active experts over 8 dies) -/
def loads : List (List Nat) :=
  [[8,0,0,0,0,0,0,0], [7,1,0,0,0,0,0,0], [6,2,0,0,0,0,0,0], [6,1,1,0,0,0,0,0], [5,3,0,0,0,0,0,0],
   [5,2,1,0,0,0,0,0], [5,1,1,1,0,0,0,0], [4,4,0,0,0,0,0,0], [4,3,1,0,0,0,0,0], [4,2,2,0,0,0,0,0],
   [4,2,1,1,0,0,0,0], [4,1,1,1,1,0,0,0], [3,3,2,0,0,0,0,0], [3,3,1,1,0,0,0,0], [3,2,2,1,0,0,0,0],
   [3,2,1,1,1,0,0,0], [3,1,1,1,1,1,0,0], [2,2,2,2,0,0,0,0], [2,2,2,1,1,0,0,0], [2,2,1,1,1,1,0,0],
   [2,1,1,1,1,1,1,0], [1,1,1,1,1,1,1,1]]
def sumW : List (List Nat) → Nat
  | [] => 0
  | l :: ls => ways l + sumW ls
def sumMaxW : List (List Nat) → Nat
  | [] => 0
  | l :: ls => maxL l * ways l + sumMaxW ls
/-- the 22 load vectors account for every one of the 8⁸ assignments, and E[max load] = 43 574 336 / 8⁸ = 2.597 -/
theorem emax_8_8 : sumW loads = 16777216 ∧ 8 ^ 8 = 16777216 ∧ sumMaxW loads = 43574336 ∧
    43574336 * 1000 / 16777216 = 2597 := by decide
/-- P(max ≥ 2) = 99.8 %, P(max ≥ 3) = 49.9 %, P(max ≥ 4) = 9.0 %, P(max = 8) = 8/8⁸ -/
theorem tail_probs : sumW (loads.filter (fun l => 2 ≤ maxL l)) * 1000 / 16777216 = 997 ∧
    sumW (loads.filter (fun l => 3 ≤ maxL l)) * 1000 / 16777216 = 499 ∧
    sumW (loads.filter (fun l => 4 ≤ maxL l)) * 1000 / 16777216 = 89 ∧
    sumW (loads.filter (fun l => 8 ≤ maxL l)) = 8 := by decide

/-- A: per-layer orchestration on the critical path = two host rounds (D2H + H2D at the measured λ) + two launch
    latencies at the realized bound; the bracket's top (500 µs) is carried in the cells below -/
def syncEP : Nat := 2 * 2 * lam + 2 * tLaunchRealized
/-- the chain streams 8 experts × 3 slabs per layer on one die; EP-A streams E[max] experts per die concurrently -/
def expLayerChain : Nat := 24 * slabM0
def expLayerEP : Nat := 43574336 * 3 * slabM0 / 16777216
def stepEPA (a sync : Nat) : Nat := step7Moe a - 28 * expLayerChain + 28 * expLayerEP + 28 * sync
/-- EP-B: the attention term, the attention GEMMs and the head run 8-way (U: the 1-head / 8-core token split) -/
def stepEPB (a sync : Nat) : Nat :=
  stepEPA a sync - 28 * a + 28 * (a / 8) - 28 * attnGemmMoe + 28 * (attnGemmMoe / 8) - headMoe + headMoe / 8

theorem ep_inputs : syncEP = 120800 ∧ expLayerChain = 2428536 ∧ expLayerEP = 788434 ∧ 8 * 3 * slabM0 = expLayerChain ∧
    expLayerEP * 1000 / expLayerChain = 324 := by decide
/-- MoE 32k t = 1: EP-A 2.932 (sync 120.8 µs) / 2.607 (sync 500 µs) vs the chain's 1.956; EP-B 4.667 / 3.895;
    the adversarial load (all 8 active experts on one die) costs the chain + the sync: 1.905 -/
theorem ep_cells_32k : stepEPA dfr32 syncEP = 85247563 ∧ tpsCard 1000 (stepEPA dfr32 syncEP) = 2932 ∧
    tpsCard 1000 (stepEPA dfr32 500000) = 2607 ∧ tpsCard 1000 (step7Moe dfr32 + 28 * syncEP) = 1905 ∧
    tpsCard 1000 (stepEPB dfr32 syncEP) = 4667 ∧ tpsCard 1000 (stepEPB dfr32 500000) = 3895 := by decide
/-- the other contexts (4k at the legacy 213.5 µs cell — the deferred 4k cell is U): chain 2.330 / 1.233 / 0.276,
    EP-A 3.860 / 1.561 / 0.289, EP-B 4.901 / 3.973 / 1.659 -/
theorem ep_cells_L : tpsCard 1000 (step7Moe 213500) = 2330 ∧ tpsCard 1000 (stepEPA 213500 syncEP) = 3860 ∧
    tpsCard 1000 (stepEPB 213500 syncEP) = 4901 ∧ tpsCard 1000 (stepEPA dfr128 syncEP) = 1561 ∧
    tpsCard 1000 (stepEPB dfr128 syncEP) = 3973 ∧ tpsCard 1000 (stepEPA dfr1M syncEP) = 289 ∧
    tpsCard 1000 (stepEPB dfr1M syncEP) = 1659 := by decide
/-- EP-A beats the chain at 32k iff the per-layer orchestration overhead is under 1 640 102 ns (13.6× the assumed sync) -/
theorem ep_sync_line (s : Nat) : stepEPA dfr32 s < step7Moe dfr32 ↔ s < 1640102 := by
  have h : step7Moe dfr32 = 127788019 := by decide
  have h2 : expLayerChain = 2428536 := by decide
  have h3 : expLayerEP = 788434 := by decide
  simp only [stepEPA, h, h2, h3]
  constructor <;> intro h1 <;> omega
/-- the worst routing (max load 8) is the chain plus the sync for every attention cell -/
theorem ep_worst_case (a s : Nat) :
    step7Moe a - 28 * expLayerChain + 28 * (8 * 3 * slabM0) + 28 * s = step7Moe a + 28 * s := by
  have h2 : expLayerChain = 2428536 := by decide
  have h3 : 8 * 3 * slabM0 = 2428536 := by decide
  have h4 : baseMoe = 115956899 := by decide
  have h5 : e29Banked = 14642880 := by decide
  simp only [step7Moe, stepMoe, h2, h3, h4, h5]
  omega
/-- memory: 32 experts × 3 slabs × 16 MiB × 28 layers = 45.1 GB per die of expert slabs; with the chain's own
    attention weights, embed/head and KV at 1M (120.2 GB / 8) a die holds 62.7 GB ≤ 86 — no int4 tier -/
theorem ep_memory : 28 * 32 * 3 * 16 * MiB = 45097156608 ∧
    28 * 32 * 3 * 16 * MiB + 4 * moeAttnBytes + 2 * headBytesMoe + 28 * 4096 * 1048576 / 8 + 2 * GiB + 64 * MiB ≤ dieMem := by decide
/-- the fork's cells are DERIVED on four UNMEASURED premises; the one that kills it is an 8-die orchestration cost
    above the line (1.64 ms per layer at 32k, i.e. 13.6× the λ-and-launch sum) -/
theorem ep_gate_margin : 1640102 / syncEP = 13 := by decide

end ForkEP

/-! ## 16. Mission B — the gate decided in arithmetic, the corrected cells per flip-list row, and the doors tried
    (`PROOF-COVERAGE-CHECK.md` §11–§12, `DESIGN-FORK-EP8.md` §9–§13; `proof/fleet.py` `[CHK-B-*]`, `[FORK-EP-S/P/TP-*]`) -/
namespace MissionB
open ForkEP

/-! ### 16.1 The fork's gate at the most conservative composition of MEASURED constants
    Every leg of both per-layer host rounds serialized (16 × 12.2 µs) and both launches at the 91 µs floor: 377 200 ns per layer. -/
def syncSerialized : Nat := 16 * lam + 2 * tLaunch
theorem gate_decided : syncSerialized = 377200 ∧ syncSerialized < 1640102 ∧ 1640102 / syncSerialized = 4 ∧
    tpsCard 1000 (stepEPA dfr32 syncSerialized) = 2704 ∧ 1956 < 2704 ∧ (2704 - 1956) * 1000 / 1956 = 382 := by decide
/-- S1 (two dies of a card, concurrent, weight-streaming class) is the MEASURED 1.000–1.001 row's own class; S2's round at
    8 participants fully serialized is 195 µs; the line needs 1 640 µs: the gate can only fail on a new host-stack serialization
    that would also contradict the card-scale 2.0× row -/
theorem s2_bound : 8 * 2 * lam = 195200 ∧ 2 * (8 * 2 * lam) < 1640102 ∧ 1640102 / (2 * (8 * 2 * lam)) = 4 := by decide

/-! ### 16.2 EP-S — speculative decoding on EP-A flips the MoE spec verdict (k = 3)
    The chain (E29 banked on both sides): loss iff α ≤ 0.823. EP-A: the 32 verify experts spread over 8 dies — E[max] = 7.0478
    (a DP over the 8^32 assignments in fleet.py `[FORK-EP-S]`, DERIVED; the per-layer expert time ⌊E[max] × 3 × 98 573⌋ = 2 084 163
    ns enters here as that printed integer). -/
/-- the chain's t = 4 verify step with the t ≥ 4 slab banked (`Chk.t4_steps_from_components` minus 65 603 328) -/
def T4chainB : Nat := T4r6 - 28 * 32 * 3 * (tSlabSer - slabM0T4)
/-- D (DP over 8^32 assignments, fleet.py): E[max load of 32 experts over 8 dies] = 7.0478; × 3 × 98 573 floored -/
def exp4EP : Nat := 2084163
def T1EPA : Nat := stepEPA dfr32 syncEP
/-- the EP-A verify step: the chain's with the expert term replaced and the sync added; attention at the t = 1 cell (E41 U) -/
def T4EPA : Nat := T4chainB - 28 * (32 * 3 * slabM0T4) + 28 * exp4EP + 28 * syncEP
/-- the pessimistic reading: the verify attention at the legacy measured t = 4 cell (2 695 600) -/
def T4EPA_legacy : Nat := T4EPA - 28 * dfr32 + 28 * 2695600
theorem eps_steps : T4chainB = 391215875 ∧ T1EPA = 85247563 ∧ T4EPA = 187990615 ∧ T4EPA_legacy = 236993415 := by decide
/-- MoE spec (k = 3) on the chain loses iff α ≤ 0.823; on EP-A it GAINS iff α ≥ 0.610 (t = 1 attention reading) / 0.762 (legacy
    t = 4 reading): E41's t = 4 deferred cell is the decisive experiment -/
theorem eps_flip : (∀ a, a < 1001 → (tau3 a * step7Moe dfr32 < 1000 * T4chainB ↔ a ≤ 823)) ∧
    (∀ a, a < 1001 → (1000 * T4EPA ≤ tau3 a * T1EPA ↔ 610 ≤ a)) ∧
    (∀ a, a < 1001 → (1000 * T4EPA_legacy ≤ tau3 a * T1EPA ↔ 762 ≤ a)) := by
  refine ⟨?_, ?_, ?_⟩ <;> decide +kernel
/-- at α = 0.7 EP-A with spec decode: 2.533 tokens per 188 ms = 3.368 tok/s/card vs 2.932 without (+14.9 %) -/
theorem eps_cell : tau3 700 * 1000000000 / (4 * T4EPA) = 3368 ∧ tpsCard 1000 T1EPA = 2932 := by decide

/-! ### 16.3 EP-B batched: the B = 2 cell exactly (E[max of 16] by the 186 partitions of 16 into ≤ 8 parts) -/
def loads16 : List (List Nat) :=
  [[16,0,0,0,0,0,0,0], [15,1,0,0,0,0,0,0], [14,2,0,0,0,0,0,0], [14,1,1,0,0,0,0,0], [13,3,0,0,0,0,0,0], [13,2,1,0,0,0,0,0],
   [13,1,1,1,0,0,0,0], [12,4,0,0,0,0,0,0], [12,3,1,0,0,0,0,0], [12,2,2,0,0,0,0,0], [12,2,1,1,0,0,0,0], [12,1,1,1,1,0,0,0],
   [11,5,0,0,0,0,0,0], [11,4,1,0,0,0,0,0], [11,3,2,0,0,0,0,0], [11,3,1,1,0,0,0,0], [11,2,2,1,0,0,0,0], [11,2,1,1,1,0,0,0],
   [11,1,1,1,1,1,0,0], [10,6,0,0,0,0,0,0], [10,5,1,0,0,0,0,0], [10,4,2,0,0,0,0,0], [10,4,1,1,0,0,0,0], [10,3,3,0,0,0,0,0],
   [10,3,2,1,0,0,0,0], [10,3,1,1,1,0,0,0], [10,2,2,2,0,0,0,0], [10,2,2,1,1,0,0,0], [10,2,1,1,1,1,0,0], [10,1,1,1,1,1,1,0],
   [9,7,0,0,0,0,0,0], [9,6,1,0,0,0,0,0], [9,5,2,0,0,0,0,0], [9,5,1,1,0,0,0,0], [9,4,3,0,0,0,0,0], [9,4,2,1,0,0,0,0],
   [9,4,1,1,1,0,0,0], [9,3,3,1,0,0,0,0], [9,3,2,2,0,0,0,0], [9,3,2,1,1,0,0,0], [9,3,1,1,1,1,0,0], [9,2,2,2,1,0,0,0],
   [9,2,2,1,1,1,0,0], [9,2,1,1,1,1,1,0], [9,1,1,1,1,1,1,1], [8,8,0,0,0,0,0,0], [8,7,1,0,0,0,0,0], [8,6,2,0,0,0,0,0],
   [8,6,1,1,0,0,0,0], [8,5,3,0,0,0,0,0], [8,5,2,1,0,0,0,0], [8,5,1,1,1,0,0,0], [8,4,4,0,0,0,0,0], [8,4,3,1,0,0,0,0],
   [8,4,2,2,0,0,0,0], [8,4,2,1,1,0,0,0], [8,4,1,1,1,1,0,0], [8,3,3,2,0,0,0,0], [8,3,3,1,1,0,0,0], [8,3,2,2,1,0,0,0],
   [8,3,2,1,1,1,0,0], [8,3,1,1,1,1,1,0], [8,2,2,2,2,0,0,0], [8,2,2,2,1,1,0,0], [8,2,2,1,1,1,1,0], [8,2,1,1,1,1,1,1],
   [7,7,2,0,0,0,0,0], [7,7,1,1,0,0,0,0], [7,6,3,0,0,0,0,0], [7,6,2,1,0,0,0,0], [7,6,1,1,1,0,0,0], [7,5,4,0,0,0,0,0],
   [7,5,3,1,0,0,0,0], [7,5,2,2,0,0,0,0], [7,5,2,1,1,0,0,0], [7,5,1,1,1,1,0,0], [7,4,4,1,0,0,0,0], [7,4,3,2,0,0,0,0],
   [7,4,3,1,1,0,0,0], [7,4,2,2,1,0,0,0], [7,4,2,1,1,1,0,0], [7,4,1,1,1,1,1,0], [7,3,3,3,0,0,0,0], [7,3,3,2,1,0,0,0],
   [7,3,3,1,1,1,0,0], [7,3,2,2,2,0,0,0], [7,3,2,2,1,1,0,0], [7,3,2,1,1,1,1,0], [7,3,1,1,1,1,1,1], [7,2,2,2,2,1,0,0],
   [7,2,2,2,1,1,1,0], [7,2,2,1,1,1,1,1], [6,6,4,0,0,0,0,0], [6,6,3,1,0,0,0,0], [6,6,2,2,0,0,0,0], [6,6,2,1,1,0,0,0],
   [6,6,1,1,1,1,0,0], [6,5,5,0,0,0,0,0], [6,5,4,1,0,0,0,0], [6,5,3,2,0,0,0,0], [6,5,3,1,1,0,0,0], [6,5,2,2,1,0,0,0],
   [6,5,2,1,1,1,0,0], [6,5,1,1,1,1,1,0], [6,4,4,2,0,0,0,0], [6,4,4,1,1,0,0,0], [6,4,3,3,0,0,0,0], [6,4,3,2,1,0,0,0],
   [6,4,3,1,1,1,0,0], [6,4,2,2,2,0,0,0], [6,4,2,2,1,1,0,0], [6,4,2,1,1,1,1,0], [6,4,1,1,1,1,1,1], [6,3,3,3,1,0,0,0],
   [6,3,3,2,2,0,0,0], [6,3,3,2,1,1,0,0], [6,3,3,1,1,1,1,0], [6,3,2,2,2,1,0,0], [6,3,2,2,1,1,1,0], [6,3,2,1,1,1,1,1],
   [6,2,2,2,2,2,0,0], [6,2,2,2,2,1,1,0], [6,2,2,2,1,1,1,1], [5,5,5,1,0,0,0,0], [5,5,4,2,0,0,0,0], [5,5,4,1,1,0,0,0],
   [5,5,3,3,0,0,0,0], [5,5,3,2,1,0,0,0], [5,5,3,1,1,1,0,0], [5,5,2,2,2,0,0,0], [5,5,2,2,1,1,0,0], [5,5,2,1,1,1,1,0],
   [5,5,1,1,1,1,1,1], [5,4,4,3,0,0,0,0], [5,4,4,2,1,0,0,0], [5,4,4,1,1,1,0,0], [5,4,3,3,1,0,0,0], [5,4,3,2,2,0,0,0],
   [5,4,3,2,1,1,0,0], [5,4,3,1,1,1,1,0], [5,4,2,2,2,1,0,0], [5,4,2,2,1,1,1,0], [5,4,2,1,1,1,1,1], [5,3,3,3,2,0,0,0],
   [5,3,3,3,1,1,0,0], [5,3,3,2,2,1,0,0], [5,3,3,2,1,1,1,0], [5,3,3,1,1,1,1,1], [5,3,2,2,2,2,0,0], [5,3,2,2,2,1,1,0],
   [5,3,2,2,1,1,1,1], [5,2,2,2,2,2,1,0], [5,2,2,2,2,1,1,1], [4,4,4,4,0,0,0,0], [4,4,4,3,1,0,0,0], [4,4,4,2,2,0,0,0],
   [4,4,4,2,1,1,0,0], [4,4,4,1,1,1,1,0], [4,4,3,3,2,0,0,0], [4,4,3,3,1,1,0,0], [4,4,3,2,2,1,0,0], [4,4,3,2,1,1,1,0],
   [4,4,3,1,1,1,1,1], [4,4,2,2,2,2,0,0], [4,4,2,2,2,1,1,0], [4,4,2,2,1,1,1,1], [4,3,3,3,3,0,0,0], [4,3,3,3,2,1,0,0],
   [4,3,3,3,1,1,1,0], [4,3,3,2,2,2,0,0], [4,3,3,2,2,1,1,0], [4,3,3,2,1,1,1,1], [4,3,2,2,2,2,1,0], [4,3,2,2,2,1,1,1],
   [4,2,2,2,2,2,2,0], [4,2,2,2,2,2,1,1], [3,3,3,3,3,1,0,0], [3,3,3,3,2,2,0,0], [3,3,3,3,2,1,1,0], [3,3,3,3,1,1,1,1],
   [3,3,3,2,2,2,1,0], [3,3,3,2,2,1,1,1], [3,3,2,2,2,2,2,0], [3,3,2,2,2,2,1,1], [3,2,2,2,2,2,2,1], [2,2,2,2,2,2,2,2]]
def ways16 (l : List Nat) : Nat := (fact 8 / prodFact ((List.range 17).map (fun v => count v l))) * (fact 16 / prodFact l)
def sumW16 : List (List Nat) → Nat
  | [] => 0
  | l :: ls => ways16 l + sumW16 ls
def sumMaxW16 : List (List Nat) → Nat
  | [] => 0
  | l :: ls => maxL l * ways16 l + sumMaxW16 ls
set_option maxRecDepth 100000 in
theorem emax_16_8 : sumW16 loads16 = 281474976710656 ∧ 8 ^ 16 = 281474976710656 ∧ sumMaxW16 loads16 = 1182593387302784 ∧
    1182593387302784 * 1000 / 281474976710656 = 4201 := by decide +kernel
/-- the B = 2 cells at 32k: chain 2.249, EP-A 3.988, EP-B 7.091 tok/s/card (two sequences) -/
def chainB2 : Nat := baseMoe - e29Banked + 28 * 24 * slabM0 + 28 * 2 * dfr32
def epA_B2 : Nat := chainB2 - 28 * 24 * 2 * slabM0 + 28 * (1182593387302784 * 3 * slabM0 / 281474976710656) + 28 * syncEP
def epB_B2 : Nat := epA_B2 - 28 * 2 * dfr32 + 28 * (2 * dfr32 / 8) - 28 * attnGemmMoe + 28 * (attnGemmMoe / 8) - headMoe + headMoe / 8
theorem b2_cells : chainB2 = 222261027 ∧ epA_B2 = 125356919 ∧ epB_B2 = 70509231 ∧
    2 * 1000 * 1000000000 / (4 * chainB2) = 2249 ∧ 2 * 1000 * 1000000000 / (4 * epA_B2) = 3988 ∧
    2 * 1000 * 1000000000 / (4 * epB_B2) = 7091 ∧ 3878 < 3988 := by decide

/-! ### 16.4 EP-P — the pipelined-EP throughput bound: fleet tokens/s ≤ 1 / max_die(DDR time per token) -/
def perDieEP_A : Nat := 28 * 3 * slabM0 + 4 * dfr32
def perDieEP_B : Nat := 28 * 3 * slabM0 + 28 * (dfr32 / 8) + 28 * (attnGemmMoe / 8)
theorem epp_bound : perDieEP_A = 12281876 ∧ perDieEP_B = 12649868 ∧ 1000000000 * 1000 / (4 * perDieEP_A) = 20355 ∧
    1000000000 * 1000 / (4 * perDieEP_B) = 19763 ∧ 13414 < 19763 := by decide

/-! ### 16.5 K-int8-only: the attention lever the post-fusion ranking forgot (MEASURED 2.13× on the K half) -/
def ki8Save (nb : Nat) : Nat := (770800 * nb / 64) / 2 - ((770800 * nb / 64) / 2) * 100 / 213
theorem ki8_lever : ki8Save 64 = 204462 ∧ ki8Save 256 = 817845 ∧ ki8Save 2048 = 6542754 ∧
    28 * ki8Save 64 = 5724936 ∧ 3460000 < 28 * ki8Save 64 ∧ 28 * ki8Save 64 < e29Banked ∧
    9280000 < 28 * ki8Save 256 ∧ e29Banked < 28 * ki8Save 256 ∧ 67090000 < 28 * ki8Save 2048 := by decide
/-- the K-int8 deferred cell at 32k ≈ 741 µs and the fusion-vs-E29 tie re-read: 28·(1 514 900 − (741 038 + 70 000)) = 19.7 ms > E29 -/
theorem ki8_tie : dfr32 - ki8Save 64 = 741038 ∧ 28 * (legacy32 - (741038 + 69840)) = 19712616 ∧ e29Banked < 19712616 := by decide

/-! ### 16.6 If erratum 12 fell (W4 alive at the W8 kernel's per-byte rate): the counterfactual cells -/
def slabW4 : Nat := tn (8 * MiB) rGemm
theorem w4_alive : slabW4 = 48044 ∧ tpsCard 1000 (step7Moe dfr32 - 28 * 24 * slabM0 + 28 * 24 * slabW4) = 2715 ∧
    tpsCard 1000 (stepDense dfr32 - 120 * gemmLayerDense + 120 * tn (denseLayerBytes / 2) rGemm - headDense + tn (headBytesDense / 2) rGemm) = 192 ∧
    (120 * wResDense + 2 * headBytesDense) / 2 ≤ 3 * dieMem := by decide

/-! ### 16.7 The packing door: two nibbles per byte through the i8 MMA are not separable -/
/-- with b = 16·hi + lo the MMA returns 16·S_hi + S_lo; |S_lo| reaches 127·15·128 = 243 840 ≫ 16, so (S_hi, S_lo) = (0, 16) and
    (1, 0) are both reachable and collide: no second call on the same B separates them -/
theorem nibble_not_separable : 127 * 15 * 128 = 243840 ∧ 16 < 243840 ∧ 16 * 0 + 16 = 16 * 1 + 0 ∧
    (∃ s1 s2 : Nat × Nat, s1 ≠ s2 ∧ s1.2 ≤ 243840 ∧ s2.2 ≤ 243840 ∧ 16 * s1.1 + s1.2 = 16 * s2.1 + s2.2) := by
  refine ⟨by decide, by decide, by decide, ⟨(0, 16), (1, 0), by decide, by decide, by decide, by decide⟩⟩
/-- and the vector route is capped: one lane-op per element keeps pace; the measured 5-pass unpack is 24 % -/
theorem unpack_cap : 8 * 432 = 3456 ∧ 2 * 1738 = 3476 ∧ 3456 * 100 / 3476 = 99 ∧ 3456 / 5 * 1000 / 3476 = 198 ∧ 840 * 1000 / 3476 = 241 := by decide

/-! ### 16.8 TP-8 dense (the corpus's §5 what-if on the measured primitive): W/8 per die, attention die-local by layer -/
def tp8Dense (tl : Nat) : Nat := 120 * (gemmLayerDense / 8 + dfr32 + (2 * 2 * lam + 2 * tl) + 4 * tQuant) + headDense / 8 + 2 * tl + (41107 + 16 * lam)
theorem tp8_dense : tpsCard 1000 (tp8Dense tLaunchRealized) = 588 ∧ tpsCard 1000 (tp8Dense tLaunch) = 570 ∧
    tpsCard 1000 (tp8Dense tLaunchRealized - 120 * dfr32 + 120 * (dfr32 / 8)) = 768 ∧ 104 < 570 := by decide

end MissionB
end Chk
