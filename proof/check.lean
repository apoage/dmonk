/-
proof/check.lean — PROMPT-7 independent adversarial re-derivation (`Chk.*`) and fork theorems (`Chk.Fork.*`).

Rules (same as the corpus, enforced strictly):
  * Core Lean 4 only (leanprover/lean4:v4.35.0; imports nothing beyond Init).
  * 0 `axiom`, 0 `sorry`, 0 `native_decide` (every finite quantifier domain closes via `decide +kernel` or `omega`).
  * Independent re-derivations from the models' printed numbers and definitions — never edits to existing proofs.

Contents:
  §1  Minimum-dies theorem (`Chk.min_dies_*`) — Problem 4
  §2  Instance-gain & break-even family + Round-7 cold-tier bug proof (`Chk.instance_gain_*`, `Chk.challenge_r7_inst_*`) — Problem 4 / 5
  §3  Fit-margin, page-waste & runtime-overhead sensitivity (`Chk.inst_fit_*`, `Chk.inst_fit_margins_and_ort`) — Problem 4 / 5
  §4  Speculative-decoding thresholds & mechanism bound (`Chk.spec_*`) — Problem 4
  §5  Online-softmax drift & telescoping sum error (`Chk.sum_error_telescoping`, `Chk.drift_*`) — Problem 3
  §6  Attention-vs-weights tie at MoE-128k, legs-conditional & measured (`Chk.moe128k_tie_*`) — Problem 3 / 4
  §7  Chain-cost bounds, residual cancellation & rowmax crossing penalty (`Chk.moe_*`, `Chk.attn_rowmax_*`) — Problem 1 / 2 / 3
  §8  Stage-overlap interval bound & its φ gate (`Chk.e40_*`) — Problem 3 / 4
  §9  Challenge round theorems: production trip rate flips 32k rank, k=64 i8 retraction, realized-launch megakernel (`Chk.challenge_*`)
  §10 Fork theorems: Hybrid K-int8 / V-f16 + Wide-Cap 61440 Deferred-Guard Attention (`Chk.Fork.*`) — Mission B
-/

namespace Chk

/-! ## Basic integer helpers (independent definitions matching the printed conventions) -/
def KiB : Nat := 1024
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB  : Nat := 1000000000

def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b
def tn (bytes rateTenths : Nat) : Nat := bytes * 10 / rateTenths
def rateT (bytes ns : Nat) : Nat := (2 * bytes * 10 + ns) / (2 * ns)
def pct (n d : Nat) : Nat := (2 * n * 1000 + d) / (2 * d)
def tpsCard (tokMilli stepNs : Nat) : Nat := tokMilli * 1000000000 / (4 * stepNs)
def tpsInst (tokMilli c stepNs : Nat) : Nat := tokMilli * c * 1000000 / (4 * stepNs)

/-! =================================================================================================
    §1 — Minimum-Dies Theorem (`T_min_dies` re-derivation, Problem 4)
    =================================================================================================
    Printed constants (`proof/fleet.py` `[F0-shapes]`, `[F1-*]`):
      * Usable memory per die: `dieMem = 86 GB = 86 000 000 000 B`.
      * Per-die fixed reservations: runtime `oRt = 2 GiB = 2 147 483 648 B`, workspace `ws = 64 MiB = 67 108 864 B`
        → net room per die before weights/KV = `83 785 407 488 B`.
      * Dense-469B (`nL = 120`): `wLayer = 3 187 671 040 B`, `wEmbed = wHead = 2 101 346 304 B`, `wDraft = 1 201 326 592 B`.
      * MoE-359B (`nL = 28`): `wLayer = 12 926 844 928 B` (`wAttn = 41 943 040 B` + `wExperts = 12 884 901 888 B`),
        `wEmbed = wHead = 525 336 576 B`.
    We prove that NO 4-die partition of the 120 dense layers or 28 MoE layers can fit in `86 GB/die` even at `L = 0`
    (zero KV bytes, no draft model), and that 5 dies suffice for both shapes at `L = 32 768, B = 1`. -/

def dieMem : Nat := 86000000000
def oRt    : Nat := 2147483648
def ws     : Nat := 67108864
def netDieRoom : Nat := dieMem - oRt - ws

def wLayerDense : Nat := 3187671040
def wEndDense   : Nat := 2101346304
def wDraft      : Nat := 1201326592

def wLayerMoe   : Nat := 12926844928
def wEndMoe     : Nat := 525336576
def kvTok       : Nat := 4096

/-- Theorem 1a: For every 4-die partition `n0 + n1 + n2 + n3 = 120` of Dense-469B, at least one die exceeds 86 GB even at L = 0. -/
theorem min_dies_dense_4_infeasible (n0 n1 n2 n3 : Nat) (hsum : n0 + n1 + n2 + n3 = 120) :
    ¬ (n0 * wLayerDense + wEndDense ≤ netDieRoom ∧
       n1 * wLayerDense ≤ netDieRoom ∧
       n2 * wLayerDense ≤ netDieRoom ∧
       n3 * wLayerDense + wEndDense ≤ netDieRoom) := by
  unfold wLayerDense wEndDense netDieRoom dieMem oRt ws
  omega

/-- Theorem 1b: For every 4-die partition `n0 + n1 + n2 + n3 = 28` of MoE-359B, at least one die exceeds 86 GB even at L = 0. -/
theorem min_dies_moe_4_infeasible (n0 n1 n2 n3 : Nat) (hsum : n0 + n1 + n2 + n3 = 28) :
    ¬ (n0 * wLayerMoe + wEndMoe ≤ netDieRoom ∧
       n1 * wLayerMoe ≤ netDieRoom ∧
       n2 * wLayerMoe ≤ netDieRoom ∧
       n3 * wLayerMoe + wEndMoe ≤ netDieRoom) := by
  unfold wLayerMoe wEndMoe netDieRoom dieMem oRt ws
  omega

/-- Theorem 1c: 5 dies suffice for both Dense-469B (`[24,24,24,24,24]`) and MoE-359B (`[5,6,6,6,5]`) at L = 32 768, B = 1. -/
theorem min_dies_5_feasible :
    24 + 24 + 24 + 24 + 24 = 120 ∧
    24 * (wLayerDense + kvTok * 32768) + wEndDense ≤ netDieRoom ∧
    24 * (wLayerDense + kvTok * 32768) + wDraft ≤ netDieRoom ∧
    5 + 6 + 6 + 6 + 5 = 28 ∧
    5 * (wLayerMoe + kvTok * 32768) + wEndMoe ≤ netDieRoom ∧
    6 * (wLayerMoe + kvTok * 32768) ≤ netDieRoom := by decide


/-! =================================================================================================
    §2 — Instance-Gain & Break-Even Family + Round-7 Cold-Tier Bug (`T_instance_gain`, `T7r_inst`)
    =================================================================================================
    On two 4-die instances (Variant I / ALT-2), each die holds 7 MoE layers (or 30 dense layers) and compresses
    a fraction `x` (thousandths) of candidate weights from int8 to int4 (`5.3 GB/s/core` vector unpack, `tW4 = 197 844 ns`
    per 1 MiB int4 core-slab, plus `+8 313 ns` (T) / `+32 614 ns` (C) for the Erratum-#19 fresh-chunk f32 K-sum).
    At MoE 32k, the minimal per-die int4 shares are `xs = [182, 170, 170, 182]`. -/

/-- Per-layer expert time in `alt.py` (`8` active experts per layer; `T_hot` and `T_cold` are per-expert or per-slab). -/
def expCold (nAct x tHot tCold : Nat) : Nat :=
  3 * nAct * (tHot * (1000 - x) + tCold * x) / 1000

/-- Per-layer expert time in `fleet.py` (`inst_step3`: `3` slabs × `8` active experts = `24` slabs per layer). -/
def expLayer24 (x tHot tCold : Nat) : Nat :=
  (24 * (1000 - x) * tHot + 24 * x * tCold) / 1000

def moeInstExpTotal24 (tHot tCold : Nat) : Nat :=
  14 * expLayer24 182 tHot tCold + 14 * expLayer24 170 tHot tCold

/-- Round-2 MoE 32k 4-die instance step in `alt.py` as a function of cold slab time `Tc` (`hot = 99 374 ns`). -/
def instMoe32kR2 (Tc : Nat) : Nat :=
  50474199 + 14 * expCold 8 182 99374 Tc + 14 * expCold 8 170 99374 Tc

/-- Round-3 MoE 32k 4-die instance step in `alt.py` as a function of cold slab time `Tc` (`hot = 99 374 ns`). -/
def instMoe32kR3 (Tc : Nat) : Nat :=
  55951187 + 14 * expCold 8 182 99374 Tc + 14 * expCold 8 170 99374 Tc

/-- Theorem 2a: Re-derivation of `T_instance_gain` (R2 and R3): two 4-die instances beat the 8-die chain
    (`1867` milli-tok/s/card in R2, `1802` in R3) iff `Tc ≤ 1 371 124 ns` (R2) and `Tc ≤ 1 406 404 ns` (R3). -/
theorem instance_gain_iff_tc (Tc : Nat) :
    (1867 < tpsInst 1000 2000 (instMoe32kR2 Tc) ↔ Tc ≤ 1371124) ∧
    (1802 < tpsInst 1000 2000 (instMoe32kR3 Tc) ↔ Tc ≤ 1406404) := by
  unfold instMoe32kR2 instMoe32kR3 expCold tpsInst
  constructor
  · rw [Nat.lt_iff_add_one_le, Nat.le_div_iff_mul_le (by omega)]; omega
  · rw [Nat.lt_iff_add_one_le, Nat.le_div_iff_mul_le (by omega)]; omega

/-- Theorem 2b: Both the Erratum-#19 merged overlapped slabs (`206 157 ns` T, `230 458 ns` C) and the corrected
    serial-chain slabs (`512 × 807 = 413 184 ns`, and with #19 merge `512 × 836 = 428 032 ns` T / `512 × 883 = 452 096 ns` C)
    lie strictly inside the MoE 32k break-even threshold, whereas on Dense 32k the corrected serial-chain cold tier
    flips two instances to a LOSS (`100 < 104` in R3P, `98 < 105` in PA-T, `94 < 105` in PA-C). -/
theorem cold_merge_erratum19_survives :
    197844 + 8313 = 206157 ∧ 197844 + 32614 = 230458 ∧
    512 * 807 = 413184 ∧ 512 * 836 = 428032 ∧ 512 * 883 = 452096 ∧
    206157 ≤ 1371124 ∧ 230458 ≤ 1371124 ∧ 452096 ≤ 1371124 ∧
    tpsInst 1000 2000 4990434793 = 100 ∧ 100 < 104 ∧
    tpsInst 1000 2000 5089603493 = 98 ∧ 98 < 105 ∧
    tpsInst 1000 2000 5319026723 = 94 ∧ 94 < 105 := by decide

/-- Theorem 2c: Re-derivation of the H10 concurrency threshold `c` (thousandths of one instance) on the Round-6
    deferred-guard cells (`139 096 935 ns` T / `141 971 051 ns` C vs single-instance `1.755 tok/s/card`). -/
theorem instance_gain_iff_c (c : Nat) :
    (1756 ≤ tpsInst 1000 c 139096935 ↔ 978 ≤ c) ∧
    (1756 ≤ tpsInst 1000 c 141971051 ↔ 998 ≤ c) := by
  unfold tpsInst
  constructor
  · rw [Nat.le_div_iff_mul_le (by decide)]; omega
  · rw [Nat.le_div_iff_mul_le (by decide)]; omega

/-- Exact 4-die MoE 32k instance step in `fleet.py` (`inst_step3c`) as a function of `(tHot, Tc, a)`:
    Fixed non-expert-slab non-attention terms equal `33 214 179 ns`. -/
def instMoe32kR7 (tHot Tc a : Nat) : Nat :=
  33214179 + 28 * a + moeInstExpTotal24 tHot Tc

/-- Theorem 2d (`challenge:` finding on `proof/fleet.py` line 1635 & `proof/fleet.lean` `T7r_inst`):
    In Round 7, `fleet.py` computed `xs = [182, 170, 170, 182]` on line 1633 but never passed `xs` to `inst_step3c`,
    instead evaluating `tps_card_inst(1000, T1)` on `T1 = 129 743 539 ns` (the 8-die `x = 0` step time!) to print `3.853 tok/s/card`.
    Because an `x = 0` MoE instance cannot fit on 4 dies (`min_dies_moe_4_infeasible`), the 4-die instance MUST pay the `x` cold-tier
    penalty (`Tc = 206 157 ns` T / `230 458 ns` C), giving `142 055 807 ns` (`3.519 tok/s/card` at `c = 2.000`, `3.502` at `c = 1.990`)
    under T and `144 929 937 ns` (`3.449` at `c = 2.000`, `3.432` at `c = 1.990`) under C — so `3.853` overstates the 2-instance
    cell by `+0.334` (`+9.5 %`) to `+0.404 tok/s/card` (`+11.7 %`), while the instance verdict itself (`> 1.926`) still holds (`c ≥ 1095 / 1118`). -/
theorem challenge_r7_inst_missing_cold_tier :
    instMoe32kR7 99374 206157 945500 = 139096935 ∧
    instMoe32kR7 99374 230458 945500 = 141971051 ∧
    instMoe32kR7 101186 206157 1015340 = 142055807 ∧
    instMoe32kR7 101186 230458 1015340 = 144929937 ∧
    instMoe32kR7 101189 206157 1015340 = 142057473 ∧
    tpsInst 1000 2000 129743539 = 3853 ∧
    tpsInst 1000 2000 142055807 = 3519 ∧
    tpsInst 1000 1990 142055807 = 3502 ∧
    tpsInst 1000 2000 144929937 = 3449 ∧
    tpsInst 1000 1990 144929937 = 3432 ∧
    3853 - 3519 = 334 ∧ 3853 - 3449 = 404 ∧
    (∀ c, 1927 ≤ tpsInst 1000 c 142055807 ↔ 1095 ≤ c) ∧
    (∀ c, 1927 ≤ tpsInst 1000 c 144929937 ↔ 1118 ≤ c) := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, ?_, ?_⟩ <;>
  · intro c; unfold tpsInst; rw [Nat.le_div_iff_mul_le (by decide)]; omega


/-! =================================================================================================
    §3 — Fit-Margin, Page-Waste & Runtime-Overhead Sensitivity (`T_alt_fit_*`, `T_mem_room`, `T4r_inst_fit`)
    ================================================================================================= -/

def wAttnMoe : Nat := 41943040
def wExpMoe  : Nat := 12884901888

def instMoeBase (x : Nat) : Nat :=
  7 * (wAttnMoe + wExpMoe - wExpMoe * x / 2000)

def instDenseBase (x : Nat) : Nat :=
  30 * (wLayerDense - wLayerDense * x / 2000)

def pageWaste256F16 : Nat := 16 * (256 * KiB - 256)
def pageWaste256I8  : Nat := 16 * (256 * KiB - 128)

/-- Theorem 3a: Exact minimal `x` (thousandths) for 4-die residency at L = 32 768 (`[182, 170, 170, 182]` MoE,
    `[376, 358, 332, 376]` Dense) and with 256 KiB page-tail waste (`[182, 171, 171, 182]` MoE, `[379, 360, 335, 379]` Dense). -/
theorem inst_fit_moe32k_iff (x : Nat) (hx : x ≤ 1000) :
    (instMoeBase x + wEndMoe + 7 * kvTok * 32768 ≤ netDieRoom ↔ 182 ≤ x) ∧
    (instMoeBase x + 7 * kvTok * 32768 ≤ netDieRoom ↔ 170 ≤ x) ∧
    (instMoeBase x + wEndMoe + 7 * kvTok * 32768 + 7 * pageWaste256F16 ≤ netDieRoom ↔ 182 ≤ x) ∧
    (instMoeBase x + 7 * kvTok * 32768 + 7 * pageWaste256F16 ≤ netDieRoom ↔ 171 ≤ x) := by
  unfold instMoeBase wAttnMoe wExpMoe wEndMoe kvTok netDieRoom dieMem oRt ws pageWaste256F16 KiB
  refine ⟨?_, ?_, ?_, ?_⟩ <;> omega

theorem inst_fit_dense32k_iff (x : Nat) (hx : x ≤ 1000) :
    (instDenseBase x + wEndDense + 30 * kvTok * 32768 ≤ netDieRoom ↔ 376 ≤ x) ∧
    (instDenseBase x + wDraft + 30 * kvTok * 32768 ≤ netDieRoom ↔ 358 ≤ x) ∧
    (instDenseBase x + 30 * kvTok * 32768 ≤ netDieRoom ↔ 332 ≤ x) ∧
    (instDenseBase x + wEndDense + 30 * kvTok * 32768 + 30 * pageWaste256F16 ≤ netDieRoom ↔ 379 ≤ x) := by
  unfold instDenseBase wLayerDense wEndDense wDraft kvTok netDieRoom dieMem oRt ws pageWaste256F16 KiB
  refine ⟨?_, ?_, ?_, ?_⟩ <;> omega

/-- Theorem 3b: Exact worst-die fit margins in bytes (`40 314 817 B` MoE 32k, `5 862 794 B` Dense 32k) and
    the Dense 1M KV-int8 runtime-overhead threshold (`ort ≤ 3 804 224 512 B` without waste, `≤ 3 741 340 672 B` with 256 KiB page waste). -/
theorem inst_fit_margins_and_ort (ort : Nat) :
    netDieRoom - (instMoeBase 182 + wEndMoe + 7 * kvTok * 32768) = 40314817 ∧
    netDieRoom - (instDenseBase 376 + wEndDense + 30 * kvTok * 32768) = 5862794 ∧
    (15 * wLayerDense + wEndDense + 15 * (kvTok / 2) * 1048576 + ws + ort ≤ dieMem ↔ ort ≤ 3804224512) ∧
    (15 * wLayerDense + wEndDense + 15 * (kvTok / 2) * 1048576 + 15 * pageWaste256I8 + ws + ort ≤ dieMem ↔ ort ≤ 3741340672) := by
  unfold wLayerDense wEndDense kvTok ws dieMem pageWaste256I8 KiB
  refine ⟨by decide, by decide, ?_, ?_⟩ <;> omega


/-! =================================================================================================
    §4 — Speculative-Decoding Thresholds & Mechanism Bound (`T_spec_*`, Problem 4)
    ================================================================================================= -/

def tauMilli (a : Nat) : Nat :=
  1000 + a + a * a / 1000 + (a * a / 1000) * a / 1000

/-- Theorem 4a: The MoE speculative-decoding mechanism bound: at `t = 1`, uniform routing reads `D(1) = 8` experts per layer
    (`E1 = 28 × 8 × 3 × 122 979 = 82 641 888 ns` on the D2 anchor, or `28 × 8 × 3 × 101 189 = 67 999 008 ns` on the M0 anchor),
    and at `t = 4` (`k = 3`), uniform routing reads `D(4) = 32 = 4 × D(1)` experts per layer, adding `3 × E1` before any draft or
    attention cost is counted. Thus `T4 ≥ T1 + 3 × E1`, requiring `τ > 2.852` (R2), `2.787` (R3), or `2.572` (R7 at M0) just to break even
    with zero draft cost. -/
theorem spec_moe_mechanism_bound :
    28 * 8 * 3 * 122979 = 82641888 ∧
    133847319 + 3 * 82641888 = 381772983 ∧
    381772983 * 1000 / 133847319 = 2852 ∧
    138693907 + 3 * 82641888 = 386619571 ∧
    386619571 * 1000 / 138693907 = 2787 ∧
    28 * 8 * 3 * 101189 = 67999008 ∧
    129743539 + 3 * 67999008 = 333740563 ∧
    333740563 * 1000 / 129743539 = 2572 := by decide

/-- Theorem 4b: Re-derivation of `T_spec_moe_loss` across Round 2 (`a ≤ 864`), Round 3 (`a ≤ 866`), Round 6 deferred (`a ≤ 854`),
    and Round 7 (`M0 + amort-cap3072`, where `T1 = 129 743 539 ns` and `T4 = 458 775 283 - 4 * 14 642 880 = 400 203 763 ns` at `t=1` M0
    → loses for every `a ≤ 828`). -/
theorem spec_moe_loss_iff : ∀ a, a < 1001 →
    ((tauMilli a * 133847319 < 1000 * 436122823 ↔ a ≤ 864) ∧
     (tauMilli a * 138693907 < 1000 * 453082211 ↔ a ≤ 866) ∧
     (tauMilli a * 142430899 < 1000 * 456819203 ↔ a ≤ 854) ∧
     (tauMilli a * 129743539 < 1000 * 400203763 ↔ a ≤ 828)) := by decide +kernel

/-- Theorem 4c: Re-derivation of `T6r_spec_dense_line`: Dense 32k spec decode (`k = 3, α = 0.7`, `τ = 2.533`) beats `t = 1`
    on the deferred guard (`2 403 248 669 ns`) iff the per-layer verify attention `v ≤ 31 092 727 ns` (`32.8×` the `t = 1` cell).
    Moreover, under the realized launch bound (`36 µs` vs `91 µs`), the 3-token draft step saves `3 × 121 × 55 000 = 19 965 000 ns`
    (`19.97 ms`), raising the `v` threshold even higher. -/
theorem spec_dense_verify_iff (v : Nat) :
    (1000 * (2356301528 + 120 * v) < tauMilli 700 * 2403248669 ↔ v ≤ 31092727) ∧
    3 * 121 * (91000 - 36000) = 19965000 := by
  have ht : tauMilli 700 = 2533 := by decide
  rw [ht]
  refine ⟨?_, by decide⟩
  omega


/-! =================================================================================================
    §5 — Online-Softmax Drift & Telescoping Sum Error (`T_drift_*`, `sum_error`, Problem 3)
    ================================================================================================= -/

/-- Theorem 5a: Re-derivation of `sum_error` by induction on `n`: an `n`-add reduction tree of `(n + 1)` terms,
    where each leaf has error `≤ e` and each add introduces error `≤ e`, accumulates `2 * n * e`. -/
def sumErrRec : Nat → Nat → Nat
  | 0, _ => 0
  | n + 1, e => sumErrRec n e + 2 * e

theorem sum_error_telescoping (n e : Nat) : sumErrRec n e = 2 * n * e := by
  induction n with
  | zero => simp [sumErrRec]
  | succ k ih =>
    rw [sumErrRec, ih, Nat.mul_add, Nat.add_mul]

/-- Theorem 5b: Why the Round-1 `±Q` region-difference layout was retired (`T_drift_bound` vs `T_drift_online_passes`):
    * Under `±Q` difference (`Z = Z_+ - Z_-`), a cancellation ratio `κ = 2` (or `4`) across `N_acc = 4` regions gives a
      deterministic worst-case f16 rounding bound (`ulp = 2⁻¹¹ = 1/2048`) of `4 × 2 × 1 000 000 / 4096 = 1 953 ppm > 1 000 ppm`
      (and `3 906 ppm` at `κ = 4`), FAILING the `1 000 ppm` (`0.1 %`) ship threshold!
    * Under the Round-4/5/6 non-negative two-level online softmax (`L = 1 048 576`, `2 048` blocks of `512` tokens,
      f32 `ulp = 2⁻²⁴ = 1/16 777 216`), each level performs at most `2 062` f32 additions (`2 062 × 10⁶ / 2²⁴ = 123 ppm`),
      so `S` drift + `O` drift = `123 + 123 = 246 ppm < 1 000 ppm`, whereas a single-level f32 chain (`8 192` / `16 384` adds)
      reaches `489 + 977 = 1 466 ppm > 1 000 ppm`. -/
theorem drift_bounds_comparison :
    4 * 2 * 1000000 / 4096 = 1953 ∧ 1000 < 1953 ∧
    4 * 4 * 1000000 / 4096 = 3906 ∧ 1000 < 3906 ∧
    ceilDiv (2062 * 1000000) 16777216 = 123 ∧
    123 + 123 = 246 ∧ 246 < 1000 ∧
    ceilDiv (8192 * 1000000) 16777216 + ceilDiv (16384 * 1000000) 16777216 = 1466 ∧
    1000 < 1466 := by decide


/-! =================================================================================================
    §6 — Attention-vs-Weights Tie at MoE-128k, Legs-Conditional & Measured (`T3r_moe128k_tie`, `T5r_moe128k_tie_measured`)
    ================================================================================================= -/

def twMoeAnchor    : Nat := 3207719
def twMoeDirectSer : Nat := 2641199
def twMoeM0        : Nat := 2684823

/-- Theorem 6a: Re-derivation of `T3r_moe128k_tie`:
    * At `legs = 0` (`20 971 520 / G` ns/block), MoE-128k is attention-bound against the anchored expert kernel iff `G ≤ 1683`
      (straddling `167.0` and `169.2 GB/s`).
    * At `legs = 1` (`22 282 240 / G`, `G ≤ 1789`) and `legs = 2` (`23 592 960 / G`, `G ≤ 1894`, required by Erratum #20),
      MoE-128k is attention-bound for EVERY `G ≤ 1746` (`174.6 GB/s` DDR roof). -/
theorem moe128k_tie_legs_conditional (G : Nat) (hG : 0 < G) :
    (twMoeAnchor ≤ 256 * (20971520 / G) + 19328 ↔ G ≤ 1683) ∧
    (twMoeAnchor ≤ 256 * (22282240 / G) + 19328 ↔ G ≤ 1789) ∧
    (twMoeAnchor ≤ 256 * (23592960 / G) + 19328 ↔ G ≤ 1894) ∧
    (twMoeDirectSer ≤ 256 * (23592960 / G) + 19328 ↔ G ≤ 2303) := by
  unfold twMoeAnchor twMoeDirectSer
  have h0 : 12455 ≤ 20971520 / G ↔ G ≤ 1683 := by rw [Nat.le_div_iff_mul_le hG]; omega
  have h1 : 12455 ≤ 22282240 / G ↔ G ≤ 1789 := by rw [Nat.le_div_iff_mul_le hG]; omega
  have h2 : 12455 ≤ 23592960 / G ↔ G ≤ 1894 := by rw [Nat.le_div_iff_mul_le hG]; omega
  have h3 : 10242 ≤ 23592960 / G ↔ G ≤ 2303 := by rw [Nat.le_div_iff_mul_le hG]; omega
  refine ⟨⟨fun h => h0.mp (by omega), fun h => by have := h0.mpr h; omega⟩,
          ⟨fun h => h1.mp (by omega), fun h => by have := h1.mpr h; omega⟩,
          ⟨fun h => h2.mp (by omega), fun h => by have := h2.mpr h; omega⟩,
          ⟨fun h => h3.mp (by omega), fun h => by have := h3.mpr h; omega⟩⟩

/-- Theorem 6b: Re-derivation of `T5r_moe128k_tie_measured` extended to Round 7's measured `M0` expert kernel (`2 684 823 ns/layer`):
    with the measured 128k bounce (`204 000 ns`) and zero vector/MMA overhead, MoE-128k is attention-bound iff
    `G ≤ 1787` (anchored), `G ≤ 2202` (derived direct), and `G ≤ 2164` (measured `M0`), all strictly above `1746`. -/
theorem moe128k_tie_measured (G : Nat) (hG : 0 < G) :
    (twMoeAnchor ≤ 256 * (20971520 / G) + 204000 ↔ G ≤ 1787) ∧
    (twMoeDirectSer ≤ 256 * (20971520 / G) + 204000 ↔ G ≤ 2202) ∧
    (twMoeM0 ≤ 256 * (20971520 / G) + 204000 ↔ G ≤ 2164) := by
  unfold twMoeAnchor twMoeDirectSer twMoeM0
  have ha : 11734 ≤ 20971520 / G ↔ G ≤ 1787 := by rw [Nat.le_div_iff_mul_le hG]; omega
  have hd : 9521 ≤ 20971520 / G ↔ G ≤ 2202 := by rw [Nat.le_div_iff_mul_le hG]; omega
  have hm : 9691 ≤ 20971520 / G ↔ G ≤ 2164 := by rw [Nat.le_div_iff_mul_le hG]; omega
  refine ⟨⟨fun h => ha.mp (by omega), fun h => by have := ha.mpr h; omega⟩,
          ⟨fun h => hd.mp (by omega), fun h => by have := hd.mpr h; omega⟩,
          ⟨fun h => hm.mp (by omega), fun h => by have := hm.mpr h; omega⟩⟩


/-! =================================================================================================
    §7 — Chain-Cost Bounds, Residual Cancellation & Rowmax Crossing (`T_cres_cancels`, `T_w4_parity`, `T6a_rowmax_det`)
    ================================================================================================= -/

/-- Theorem 7a: For every per-call barrier residual `cRes` (tenths of ns) and every tile count `nCalls`,
    the difference between the strict-serial tile time and the ping-pong overlapped tile time is independent of `cRes`. -/
theorem moe_cres_cancellation (cBase sBase nCalls cRes : Nat) (h : sBase ≤ cBase) :
    (cBase + nCalls * cRes) - (sBase + nCalls * cRes) = cBase - sBase := by omega

/-- Theorem 7b: Re-derivation of `T_w4_parity` (`PROOF-COVERAGE-2.md` row 19): on an 8-core die, an int4 weight stream
    (`1 MiB` int4 per core per expert = `2 MiB` W8-equivalent) unpacked at rate `R` (tenths of GB/s/core of int4 bytes)
    matches or beats the W8 S1-staged baseline (`122 979 ns` per expert) iff `R ≥ 86` (`8.6 GB/s/core` of int4 = `17.2 GB/s/core` f16),
    and matches the measured `M0` direct-path W8 kernel (`101 189 ns`) iff `R ≥ 104` (`10.4 GB/s/core` of int4);
    the measured 5-pass vector unpack is `R = 53` (`5.3 GB/s/core`), strictly below both. -/
theorem moe_w4_parity_threshold (R : Nat) (hR : 0 < R) :
    (tn MiB R ≤ 122979 ↔ 86 ≤ R) ∧
    (tn MiB R ≤ 101189 ↔ 104 ≤ R) ∧
    53 < 86 := by
  unfold tn MiB
  refine ⟨?_, ?_, by decide⟩
  · rw [Nat.div_le_iff_le_mul (by omega)]; omega
  · rw [Nat.div_le_iff_le_mul (by omega)]; omega

/-- Theorem 7c: Re-derivation of `T6a_rowmax_det` and `T4r_hybrid_void`: under Erratum #29 & #31, the deterministic
    per-block rowmax crossing is `16 × 1 100 = 17 600 ns` (`xDet`), which exceeds the legacy per-block scan delta
    (`8 981 ns`) by `8 619 ns/block`. At 32k (`64` blocks), switching to rowmax after a guard trip at block `64 - r`
    for ANY `r ≥ 1` remaining blocks adds `r × 17 600 ns` on top of the `902 900 ns` guard-off base, which already
    exceeds the `8 981 ns/block` legacy guard for every `r ≥ 1`; at `r = 64` blocks, deterministic rowmax takes
    `938 800 + 64 × 17 600 = 2 065 200 ns` (`65.0 GB/s`), slower than the `1 514 900 ns` legacy scan! -/
theorem attn_rowmax_crossing_voids_switch (r : Nat) (hr : 1 ≤ r) :
    16 * 1100 = 17600 ∧
    8981 * r < 17600 * r ∧
    938800 + 64 * 17600 = 2065200 ∧
    1514900 < 2065200 := by
  refine ⟨by decide, ?_, by decide, by decide⟩
  omega


/-! =================================================================================================
    §8 — Stage-Overlap Interval Bound & Its φ Gate (`T40_ivl`, `T40_phi_*`, Problem 3 / 4)
    ================================================================================================= -/

def sumD : List (Nat × Nat) → Nat
  | [] => 0
  | (d, _) :: xs => d + sumD xs

def sumW : List (Nat × Nat) → Nat
  | [] => 0
  | (_, w) :: xs => w + sumW xs

def sumMax : List (Nat × Nat) → Nat
  | [] => 0
  | (d, w) :: xs => max d w + sumMax xs

/-- Theorem 8a: Re-derivation of `T40_ivl` for every list of barrier-separated intervals `(d_i, w_i)` (DMA time `d_i`,
    compute/work time `w_i`): `Σ d_i ≤ Σ max(d_i, w_i)`, `Σ w_i ≤ Σ max(d_i, w_i)`, and `Σ max(d_i, w_i) ≤ Σ d_i + Σ w_i`. -/
theorem e40_ivl_bounds (xs : List (Nat × Nat)) :
    sumD xs ≤ sumMax xs ∧ sumW xs ≤ sumMax xs ∧ sumMax xs ≤ sumD xs + sumW xs := by
  induction xs with
  | nil => simp [sumD, sumW, sumMax]
  | cons p tl ih =>
    rcases p with ⟨d, w⟩
    simp [sumD, sumW, sumMax]
    omega

/-- Stage-overlap (E40) step model (`attn.lean` `e40`): `floor + nb * (V - k * d) + nb * k * phi + tau + nx * cx`. -/
def e40 (nb floor V d k phi tau nx cx : Nat) : Nat :=
  floor + nb * (V - k * d) + nb * k * phi + tau + nx * cx

/-- Theorem 8b: Re-derivation of `T40_phi_*` and `T40_phi_gate`:
    * At the most tolerant `k = 1` cell (`F1 = 821 800`, `cxEnd = 10 000`, `V = 1 438 + 1 505 = 2 943`, `d = 12 841`),
      E40 beats `945 500 ns` iff `phi ≤ 1 776 ns` (`T40_phi_1` in `attn.lean`).
    * At `k = 2` crossings per block (the literal Erratum-#25/#29 count: `S1 → L0A` + `US → DDR`), E40 beats `945 500 ns`
      iff `phi ≤ 888 ns` (`T40_phi_2` in `attn.lean`).
    * Even at `cxEnd = 0` (`nx = 0`), `k = 1` requires `phi ≤ 1 932 ns`, while the measured Erratum-#29 crossing (`10 000–20 000 ns`)
      is `5.2×–11.3×` above the threshold! -/
theorem e40_phi_gate_iff (phi : Nat) :
    (e40 64 821800 2943 12841 1 phi 0 1 10000 < 945500 ↔ phi ≤ 1776) ∧
    (e40 64 821800 2943 12841 2 phi 0 1 10000 < 945500 ↔ phi ≤ 888) ∧
    (e40 64 821800 2943 12841 1 phi 0 0 10000 < 945500 ↔ phi ≤ 1932) ∧
    1932 < 10000 := by
  unfold e40
  refine ⟨?_, ?_, ?_, by decide⟩ <;> omega


/-! =================================================================================================
    §9 — Challenge Round Theorems (`Chk.challenge_*`)
    ================================================================================================= -/

/-- Theorem 9a (`challenge:` on `DESIGN-3.md` Round 6 & `PROOF-COVERAGE-3.md`):
    1. Under Round 6's synthetic trip-rate premise `p ∈ [87, 220]` per `10⁵` steps (`0.087–0.22 %`), the 32k amortized
       cell (`946 259 – 947 419 ns`) straddled the E29 tie line (`947 079 ns`).
    2. At the MEASURED real-model production trip rates (`p = 8 000` = `8.0 %` at shipped `cap = 3072`, `p = 5 500` = `5.5 %`
       at wide `cap = 61440`), amortized 32k attention is `1 015 308 ns` / `993 493 ns` (using `R = 872 600 ns` from `attn.py`)
       or `1 015 340 ns` / `993 515 ns` (using `R = 873 000 ns` from `fleet.py`).
    3. Against the Round-7 M0 tie line (`991 939 ns`), guard fusion beats E29 iff `p ≤ 5 319` per `10⁵` steps (`5.32 %`)
       against the session-5 legacy (`1 514 900 ns`), and against the Round-6 tie line (`947 079 ns`) iff `p ≤ 181` (`0.18 %` / `0.19 %`).
       Both measured production rates (`8.0 %` and `5.5 %`) FAIL to cross the line: E29 wins outright on both caps!
    4. Furthermore, `DESIGN-3.md` line 24 claimed `"−59 µs (one pass)"` did not reproduce from the quoted cells; `HW-MAP.md`
       line 116 shows it is the exact **softmax-phase** delta (`624 000 - 565 000 = 59 000 ns`). -/
theorem challenge_trip_rate_32k_flips_rank (p : Nat) :
    945500 + 8000 * 872600 / 100000 = 1015308 ∧
    945500 + 5500 * 872600 / 100000 = 993493 ∧
    945500 + 8000 * 873000 / 100000 = 1015340 ∧
    945500 + 5500 * 873000 / 100000 = 993515 ∧
    (945500 + p * 872600 / 100000 ≤ 947079 ↔ p ≤ 181) ∧
    (945500 + p * 873000 / 100000 ≤ 991939 ↔ p ≤ 5319) ∧
    991939 < 993493 ∧ 993493 < 1015308 ∧
    624000 - 565000 = 59000 := by
  refine ⟨by decide, by decide, by decide, by decide, ?_, ?_, by decide, by decide, by decide⟩
  · omega
  · omega

/-- Theorem 9b (`challenge:` on `DESIGN.md`, `DESIGN-2.md`, `DESIGN-3.md` §1.2 / §5.2):
    Retracted Erratum #14 (`HW-MAP.md` lines 193–201, 464–484): `k = 64` on `i8 × i8 → i32` is fp64-exact (the original
    "wrong `k = 64`" verdict was a host dump-decode offset bug: 16 KB reader stride vs 1 KB kernel chunk stride).
    At `d = 64`, `k = 32` (`2 × (16,16,32)`) required `64` MMA calls per 512-token block and `32` A-operand re-stagings
    (because `k = 32` ignores A-operand offsets and always reads A columns `0..31`), running at `51.4 GB/s`;
    single-call `k = 64` takes `32` MMA calls and `0` A re-stagings, running at `90.2 GB/s` (`1.75×` speedup) and
    powering `K-int8` at `87.6 GB/s` (`2.13×` over the `41.1 GB/s` f16 arm). -/
theorem challenge_k64_i8_d64 :
    (512 / 16) * 2 = 64 ∧
    (512 / 16) * 1 = 32 ∧
    rateT 902 514 = 18 ∧
    902 * 100 / 514 = 175 ∧
    876 * 100 / 411 = 213 := by decide

/-- Theorem 9c (`challenge:` on `DESIGN-4.md` §5′ V2 & `ALTERNATIVES.md` Rank 3):
    Under the `HW-MAP.md` realized launch bound (`tLaunch ≤ 36 000 ns`, and `26 700 ns` at the measured 15-op stack)
    and Erratum #29's `c_sync = 20 000 ns` per flag round (`5` rounds/layer + `3 581 ns` reduction traffic on MoE;
    `4` rounds/layer + `15 388 ns` reduction traffic on Dense):
    * At the stale `91 000 ns` launch premise, the MoE megakernel saved `28 × (5 × 91 000 - 103 581) = 9 839 732 ns` (`+7.6 %` on R7 step)
      and paid iff `c_sync ≤ 108 430 ns` (MoE) / `109 903 ns` (Dense).
    * At the realized `36 000 ns` launch bound, the MoE megakernel saves only `28 × (5 × 36 000 - 103 581) = 2 139 732 ns`
      (`2.14 ms/tok` = `+1.8 %` on the `118.85 ms` realized-launch MoE 32k step!) and Dense saves only
      `120 × (4 × 36 000 - 95 388) = 5 833 440 ns` (`5.83 ms/tok` = `+0.25 %` on Dense 32k!), with break-even thresholds
      dropping to `c_sync ≤ 35 283 ns` (MoE) and `c_sync ≤ 32 153 ns` (Dense).
    * At the measured `26 700 ns` per-launch overhead (`HW-MAP.md` line 276), MoE net savings drop to `0.84 ms/tok` (`+0.7 %`),
      Dense net savings drop to `1.52 ms/tok` (`+0.06 %`), and the Dense `c_sync` break-even threshold is `22 853 ns` —
      only `2 853 ns` above the `20 000 ns` single-crossing floor! -/
theorem challenge_mega_realized_launch (csync : Nat) :
    28 * (5 * 91000 - (5 * 20000 + 3581)) = 9839732 ∧
    28 * (5 * 36000 - (5 * 20000 + 3581)) = 2139732 ∧
    28 * (5 * 26700 - (5 * 20000 + 3581)) = 837732 ∧
    120 * (4 * 36000 - (4 * 20000 + 15388)) = 5833440 ∧
    120 * (4 * 26700 - (4 * 20000 + 15388)) = 1369440 ∧
    (5 * csync + 3581 ≤ 5 * 36000 ↔ csync ≤ 35283) ∧
    (4 * csync + 15388 ≤ 4 * 36000 ↔ csync ≤ 32153) ∧
    (5 * csync + 3581 ≤ 5 * 26700 ↔ csync ≤ 25983) ∧
    (4 * csync + 15388 ≤ 4 * 26700 ↔ csync ≤ 22853) := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, ?_, ?_, ?_, ?_⟩ <;> omega


/-! =================================================================================================
    §10 — Mission B Fork Theorems (`Chk.Fork.*` — `DESIGN-FORK-1.md`)
    =================================================================================================
    Hybrid `K-int8 / V-f16` + Wide-Cap (`61 440`) Deferred-Guard Attention (`DESIGN-FORK-1.md`):
      1. KV bytes per token per layer = `3 072 B` (`128 B` K-int8 + `256 B` V-f16 per head × 8 KV heads; `3/4` of f16's `4 096 B`).
      2. Because `V` stays `f16`, `P` stays `f16` (`P` is NEVER quantized to `i8`), so the kernel runs on the
         zero-per-block-crossing deferred guard at `μ = 8` with wide cap `61 440 = 15 × 2¹²` (`< 65 504`, `e¹¹ < 61 440`),
         cutting the measured 32k retry share from `8.0 %` to `5.5 %` (`HW-MAP.md` line 116) while avoiding both `T4r_i8`
         (lazy × full KV-int8 saturation) and `T6a_rowmax_det` (Erratum-#31's `17.6 µs/block` rowmax crossing).
      3. Score MMA uses `i8 × i8 → i32` at native `(16, 16, 128)` in a single call per 16-token subtile (`32 × 15 = 480 ns`
         per 512-token block vs `960 ns` f16, and 1 `C_s` chunk set = `32 KiB` instead of `64 KiB` in `L0C`).
      4. Per-block DDR time (`192 KiB` KV + `2 × 16 KiB` P bounce = `224 KiB` per core at `169.2 GB/s` = `10 845 ns`) remains
         strictly DDR-bound above the vector softmax + scale-dequant chain (`5 530 + 388 = 5 918 ns < 10 845 ns`).
      5. On the measured Session-5/7 decomposition (`K+V` stream = `770 800 ns` at 32k, half-stream saved = `192 700 ns` minus
         `8 000 ns` measured ~3 % dequant delta = `184 700 ns` net saved per 64 blocks):
         * 32k per-layer attention: `760 800 ns` trip-free (`176.4 GB/s` f16-eq), `798 656 ns` amortized at `τ = 5.5 %`
           (vs `1 015 340 ns` shipped f16 = `-21.3 %` per layer!).
         * 128k per-layer attention: `2 880 000 ns` trip-free (vs `3 618 800 ns` f16 = `-20.4 %`), and on the Round-4
           analytical model `2 795 648 ns < 3 207 719 ns`, flipping MoE-128k (anchored) back to weights-bound!
         * 1M per-layer attention: `22 783 600 ns` trip-free (vs `28 694 000 ns` f16 = `-20.6 %`), raising MoE-1M fleet
           throughput from `0.276` to `0.338 tok/s/card` (`+22.5 %`).
      6. On two 4-die instances (`V3`), the 25 % KV reduction lowers the minimal int4 share `x` on every shape/context
         (`MoE 32k`: `[176, 165, 165, 176]`, `MoE 128k`: `[223, 212, 212, 223]`, `MoE 1M`: `[661, 649, 649, 661]`,
         `Dense 32k`: `[355, 337, 311, 355]`), and on 8-die Dense 1M it enables a zero-crossing deferred-guard route
         with `x = [605, 567, 517, ..., 605]` that reaches `0.038 tok/s/card` (`+40.7 %` over the `0.027 tok/s/card` rowmax KV-int8 route!). -/

namespace Fork

def kvTokK8 : Nat := 3072
def ddrBlkK8 (G legs : Nat) : Nat := (196608 + legs * 16384) * 80 / G
def vecBlkK8LazyT : Nat := 5530 + 388
def mmaBlkK8 : Nat := 32 * 15

/-- Fork per-layer attention cells derived from the measured Session-5/7 K+V stream decomposition:
    Per 64 blocks (32k), halving the K stream (`385 400 / 2 = 192 700 ns`) net of the measured ~3 % dequant (`8 000 ns`)
    saves `184 700 ns` (`2 885 ns/block`). At `cap = 61 440` (`τ = 5.5 %`), tripped re-run cost also drops by `184 700 ns`
    (`873 000 - 184 700 = 688 300 ns`). -/
def sav32k  : Nat := 192700 - 8000
def dfrK8_32k  : Nat := 945500 - sav32k
def reRunK8_32k : Nat := 873000 - sav32k
def amK8_32k_cap61440 : Nat := dfrK8_32k + 55 * reRunK8_32k / 1000
def amK8_32k_cap3072  : Nat := dfrK8_32k + 80 * reRunK8_32k / 1000
def dfrK8_128k : Nat := 3618800 - 4 * sav32k
def dfrK8_1M   : Nat := 28694000 - 32 * sav32k

/-- Theorem 10a: Block-level invariants of `K-int8 / V-f16` + Wide-Cap `61 440`:
    * Wide cap `61 440 = 15 × 2¹² < 65 504` is f16-exact and exceeds `e¹¹` (`2.7183¹¹ < 61 440`).
    * Per-block DDR time at `169.2 GB/s` with `legs = 2` is `10 845 ns` (vs `13 945 ns` f16), which stays strictly above
      the vector chain (`5 918 ns`) and MMA (`480 ns`), so `t = 1` attention remains 100 % DDR-bound with 0 per-block crossings.
    * `L0C` footprint at `mt = 1` drops from `131 072 B` (`128 KiB`) to `98 304 B` (`96 KiB`) because single-call `k = 128` i8
      needs only 1 `C_s` chunk set (`32 KiB`) + 8 `C_o` chunk sets (`64 KiB`). -/
theorem fork_block_and_cap_invariants :
    61440 = 15 * 2 ^ 12 ∧ 15 < 2 ^ 11 ∧ 61440 < 65504 ∧
    27183 ^ 11 < 61440 * 10 ^ 44 ∧
    ddrBlkK8 1692 2 = 10845 ∧
    vecBlkK8LazyT = 5918 ∧ mmaBlkK8 = 480 ∧
    vecBlkK8LazyT < ddrBlkK8 1692 2 ∧ mmaBlkK8 < ddrBlkK8 1692 2 ∧
    1 * 32768 + 8 * 8192 = 98304 ∧ 98304 < 131072 := by decide

/-- Theorem 10b: Per-layer attention times and analytical model (`step4`) comparison:
    * `dfrK8_32k = 760 800 ns` (`-19.5 %` vs trip-free f16 `945 500 ns`), `amK8_32k_cap61440 = 798 656 ns`
      (`-21.3 %` vs shipped `cap = 3072` f16 `1 015 340 ns`, and `-61.3 %` vs deterministic rowmax full `KV-int8` `2 065 200 ns`!).
    * `dfrK8_128k = 2 880 000 ns` (`-20.4 %` vs `3 618 800 ns`), and on the Round-4 analytical model
      `256 * ddrBlkK8 1692 2 + 19328 = 2 795 648 ns < twMoeAnchor (3 207 719 ns)`,
      flipping analytical MoE-128k (anchored) from attention-bound back to weights-bound!
    * `dfrK8_1M = 22 783 600 ns` (`-20.6 %` vs `28 694 000 ns`). -/
theorem fork_attn_cells :
    sav32k = 184700 ∧
    dfrK8_32k = 760800 ∧
    reRunK8_32k = 688300 ∧
    amK8_32k_cap61440 = 798656 ∧
    amK8_32k_cap3072 = 815864 ∧
    dfrK8_128k = 2880000 ∧
    dfrK8_1M = 22783600 ∧
    amK8_32k_cap61440 < 993515 ∧ 993515 < 1015340 ∧
    amK8_32k_cap61440 * 2 < 2065200 ∧
    64 * ddrBlkK8 1692 2 + 19328 = 713408 ∧
    256 * ddrBlkK8 1692 2 + 19328 = 2795648 ∧
    2795648 < twMoeAnchor := by decide

/-- Theorem 10c: Fleet step times (`step7F`) and throughput gains of `DESIGN-FORK-1.md` on the 8-die chain:
    * MoE 32k (`amort-cap61440`): `129 743 539 → 123 676 387 ns` (`1.926 → 2.021 tok/s/card`, `+4.9 %`;
      with realized launch `36 µs`: `112 786 387 ns` = `2.216 tok/s/card`, `+5.4 %`).
    * MoE 128k: `202 640 419 → 181 954 019 ns` (`1.233 → 1.373 tok/s/card`, `+11.4 %`;
      with realized launch: `171 064 019 ns` = `1.461 tok/s/card`).
    * MoE 1M: `904 746 019 → 739 254 819 ns` (`0.276 → 0.338 tok/s/card`, `+22.5 %`).
    * Dense 32k (`amort-cap61440`): `2 411 629 469 → 2 385 627 389 ns` (`0.103 → 0.104 tok/s/card`; `-26.00 ms/tok`).
    * Dense 128k: `2 724 044 669 → 2 635 388 669 ns` (`0.091 → 0.094 tok/s/card`; `-88.66 ms/tok`). -/
theorem fork_fleet_steps :
    101314019 + 28 * amK8_32k_cap61440 = 123676387 ∧
    tpsCard 1000 123676387 = 2021 ∧
    tpsCard 1000 (123676387 - 10890000) = 2216 ∧
    101314019 + 28 * dfrK8_128k = 181954019 ∧
    tpsCard 1000 181954019 = 1373 ∧
    tpsCard 1000 (181954019 - 10890000) = 1461 ∧
    101314019 + 28 * dfrK8_1M = 739254819 ∧
    tpsCard 1000 739254819 = 338 ∧
    2289788669 + 120 * amK8_32k_cap61440 = 2385627389 ∧
    tpsCard 1000 2385627389 = 104 ∧
    2289788669 + 120 * dfrK8_128k = 2635388669 ∧
    tpsCard 1000 2635388669 = 94 := by decide

/-- Theorem 10d: 4-die instance residency (`x` in thousandths) under `K-int8 / V-f16` (`kvTokK8 = 3 072 B/tok`):
    * MoE 32k minimal `x` drops from `[182, 170, 170, 182]` to `[176, 165, 165, 176]`.
    * MoE 128k minimal `x` drops from `[244, 233, 233, 244]` to `[223, 212, 212, 223]`.
    * MoE 1M minimal `x` drops from `[827, 815, 815, 827]` to `[661, 649, 649, 661]`.
    * Dense 32k minimal `x` drops from `[376, 358, 332, 376]` to `[355, 337, 311, 355]`.
    * With `[176, 165, 165, 176]` and `amK8_32k_cap61440 = 798 656 ns`, the corrected Round-7 4-die MoE 32k instance step
      drops from `142 055 807 ns` (`3.519 tok/s/card`) to `135 600 687 ns` (`3.687 tok/s/card` at `c = 2.000`, `3.668` at `c = 1.990`). -/
def moeInstExpTotalK8 (tHot tCold : Nat) : Nat :=
  14 * expLayer24 176 tHot tCold + 14 * expLayer24 165 tHot tCold

theorem fork_inst_fit_and_step (x : Nat) (hx : x ≤ 1000) :
    (instMoeBase x + wEndMoe + 7 * kvTokK8 * 32768 ≤ netDieRoom ↔ 176 ≤ x) ∧
    (instMoeBase x + 7 * kvTokK8 * 32768 ≤ netDieRoom ↔ 165 ≤ x) ∧
    (instMoeBase x + wEndMoe + 7 * kvTokK8 * 131072 ≤ netDieRoom ↔ 223 ≤ x) ∧
    (instMoeBase x + wEndMoe + 7 * kvTokK8 * 1048576 ≤ netDieRoom ↔ 661 ≤ x) ∧
    (instDenseBase x + wEndDense + 30 * kvTokK8 * 32768 ≤ netDieRoom ↔ 355 ≤ x) ∧
    33214179 + 28 * amK8_32k_cap61440 + moeInstExpTotalK8 101186 206157 = 135600687 ∧
    tpsInst 1000 2000 135600687 = 3687 ∧
    tpsInst 1000 1990 135600687 = 3668 := by
  unfold instMoeBase instDenseBase wAttnMoe wExpMoe wEndMoe wLayerDense wEndDense kvTokK8 netDieRoom dieMem oRt ws
  refine ⟨?_, ?_, ?_, ?_, ?_, by decide, by decide, by decide⟩ <;> omega

/-- Theorem 10e: Dense 1M on the 8-die fleet via `K-int8 / V-f16` (zero per-block crossings!) + minimal 8-die W4 weight tier:
    * On 8 dies (15 layers/die), `15 × 3 072 × 1 048 576 = 48 318 382 080 B` of KV fits with `x = 605` on outer dies 0, 7
      (with `wEmbed` / `wHead`), `x = 567` on die 1 (with `wDraft`), and `x = 517` on inner dies 2..6.
    * At `R_W4 = 800` tenths (`80.0 GB/s` W8-eq with the Erratum-#19 merge) and `dfrK8_1M = 22 783 600 ns/layer`,
      the 8-die Dense 1M step is `6 436 381 994 ns` → `0.038 tok/s/card`, beating the deterministic rowmax `KV-int8` route
      (`9 024 300 749 ns` → `0.027 tok/s/card`, `T6f_dense1M_det`) by `+2 587.92 ms/tok` (`+40.7 %` throughput) with ZERO
      per-block scalar crossings! -/
def dense8DieLayerW (x rW4 : Nat) : Nat :=
  wLayerDense * 10 * (1000 - x) / (1000 * 1746) + wLayerDense * 10 * x / (1000 * rW4)

def dense1MK8Step : Nat :=
  30 * dense8DieLayerW 605 800 + 15 * dense8DieLayerW 567 800 + 75 * dense8DieLayerW 517 800 +
  (2289788669 - 120 * (wLayerDense * 10 / 1746)) + 120 * dfrK8_1M

theorem fork_dense_1M_zero_crossing (x : Nat) (hx : x ≤ 1000) :
    (15 * (wLayerDense - wLayerDense * x / 2000) + wEndDense + 15 * kvTokK8 * 1048576 ≤ netDieRoom ↔ 605 ≤ x) ∧
    (15 * (wLayerDense - wLayerDense * x / 2000) + wDraft + 15 * kvTokK8 * 1048576 ≤ netDieRoom ↔ 567 ≤ x) ∧
    (15 * (wLayerDense - wLayerDense * x / 2000) + 15 * kvTokK8 * 1048576 ≤ netDieRoom ↔ 517 ≤ x) ∧
    dense1MK8Step = 6436381994 ∧
    tpsCard 1000 dense1MK8Step = 38 ∧
    tpsCard 1000 9024300749 = 27 ∧
    27 < 38 := by
  refine ⟨?_, ?_, ?_, by decide, by decide, by decide, by decide⟩ <;>
  · dsimp [wLayerDense, wEndDense, wDraft, kvTokK8, netDieRoom, dieMem, oRt, ws]
    omega

end Fork
end Chk
