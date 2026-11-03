/-
  proof/model.lean — machine-checked derivations for DESIGN.md (dmonk).

  Core Lean 4 only (no Mathlib, no Batteries, no imports beyond the implicit
  Init).  Every quantity is a scaled integer so every theorem closes with
  `decide`, `omega`, `rfl` or `simp`:
    rates   : tenths of GB/s   (1 B/ns = 1 GB/s decimal → bytes*10/ns = tenths)
    bytes   : bytes            (KiB = 1024, MiB = 1048576)
    time    : ns, floor        (timeNs b R = b*10 / R)
    tau     : hundredths of ns per 16×16×16 MMA fragment
    rate    : round-half-up    (rateT W t = (2*W*10 + t) / (2*t))
  The identical formulas are in proof/model.py; PROOF-COVERAGE.md maps every
  number in DESIGN.md to a theorem here, a model.py label, or an experiment.

  Build: `cd proof && lake build`  (lakefile.toml provided), or `lean model.lean`.
  No `axiom` appears anywhere: the Measured namespace holds plain definitions
  of the HW-MAP constants and nothing that DESIGN.md concludes.
-/

namespace Measured
/-- HW-MAP card table: LPDDR streaming per die = 173.8 GB/s (measured). Tenths. -/
def rDdr : Nat := 1738
/-- HW-MAP data-movement table: DDR → S1 plain copies = 180 GB/s aggregate (measured). Tenths. -/
def rStage : Nat := 1800
/-- HW-MAP data-movement table: vector SRAM → S1 = 250 GB/s per core (measured). Tenths. -/
def rUsS1 : Nat := 2500
/-- HW-MAP compute table, derived row: 17.8 TFLOPS/die ÷ 8 cores → 3.7 ns per 16³ fragment. Hundredths of ns. -/
def tau370 : Nat := 370
/-- HW-MAP compute table: 26.6 TFLOPS/die figure → 2.46 ns per fragment. Hundredths of ns. -/
def tau246 : Nat := 246
/-- HW-MAP: f16 library matmul flat at 148 GB/s/die to M=128 → ≤ 3.46 ns per fragment (proved below). Hundredths. -/
def tau346 : Nat := 346
/-- HW-MAP compute table: vector unit ~40 f16 lanes/cycle/core × 1.08 GHz = 43.2 G lane-ops/s/core. Tenths. -/
def rVec : Nat := 432
/-- HW-MAP data-movement table: ~91 µs launch+queue floor. ns. -/
def tLaunch : Nat := 91000
/-- HW-MAP data-movement table: fractal-transform copy ~7 GB/s/core (software). Tenths. -/
def rFrac : Nat := 70
/-- HW-MAP hierarchy table: L0C ≥ 64 KiB (PRIOR lower bound). Bytes. -/
def l0cP : Nat := 65536
/-- HW-MAP hierarchy table: S1 ~1 MB (PRIOR), taken as decimal 1 000 000 B. -/
def s1P : Nat := 1000000
/-- HW-MAP errata 10: vendor GEMM control overhead 60 ns·(K/64)². ns. -/
def libQuad : Nat := 60
end Measured

namespace Design

def KiB : Nat := 1024
def MiB : Nat := 1048576

def minN (a b : Nat) : Nat := if a ≤ b then a else b
def maxN (a b : Nat) : Nat := if a ≤ b then b else a

/-- columns per core (N split 8-way) -/
def Nc (N : Nat) : Nat := N / 8
/-- A fragments: 16-row blocks covering m rows -/
def mFrag (m : Nat) : Nat := (m + 15) / 16
/-- MMA calls per core at (m=16, n=256, k=64): (K/64)·(Nc/256)·mFrag — no slab parameter: independent of slab count -/
def calls (K N m : Nat) : Nat := (K / 64) * (Nc N / 256) * mFrag m
/-- W8 weight bytes per die -/
def wBytes (K N : Nat) : Nat := K * N
/-- A bytes per core for one full-K pass: f16 [16·mFrag, K] -/
def aBytesCore (K m : Nat) : Nat := 16 * mFrag m * K * 2
/-- slab width: whole MMA tiles (tileN columns) whose f32 accumulator fits L0C -/
def nSlab (N m l0c tileN : Nat) : Nat := minN (Nc N) ((l0c / (64 * mFrag m)) / tileN * tileN)
def nSlabs (N m l0c tileN : Nat) : Nat := Nc N / nSlab N m l0c tileN
/-- A is kept resident in S1 when it fits beside the 256 KiB B ring -/
def aPasses (K N m l0c s1 tileN : Nat) : Nat :=
  if aBytesCore K m + 256 * KiB ≤ s1 then 1 else nSlabs N m l0c tileN
/-- DDR bytes per die: weights once + A once per pass per core -/
def ddrBytesDie (K N m l0c s1 tileN : Nat) : Nat :=
  wBytes K N + 8 * aPasses K N m l0c s1 tileN * aBytesCore K m
/-- scheme P (§1.4): A read once, partials accumulated through S1 -/
def ddrBytesDieP (K N m : Nat) : Nat := wBytes K N + 8 * aBytesCore K m
/-- geometry hypothesis G2 (§3.1): i8 tiles at 2 B per element -/
def ddrBytesDieG2 (K N m : Nat) : Nat := 2 * wBytes K N + 8 * aBytesCore K m
/-- time in ns of `b` bytes at `R` tenths of GB/s (floor) -/
def timeNs (b R : Nat) : Nat := b * 10 / R
/-- MMA busy time per core in ns: calls × 64 fragments × tau/100 -/
def mmaNs (K N m tau : Nat) : Nat := calls K N m * 64 * tau / 100
/-- rate in tenths of GB/s of W bytes in t ns, round half up -/
def rateT (W t : Nat) : Nat := (2 * W * 10 + t) / (2 * t)
def kernelNs (K N m l0c s1 R tau tileN : Nat) : Nat :=
  maxN (timeNs (ddrBytesDie K N m l0c s1 tileN) R) (mmaNs K N m tau)
def predicted (K N m l0c s1 R tau tileN : Nat) : Nat := rateT (wBytes K N) (kernelNs K N m l0c s1 R tau tileN)
def kernelNsP (K N m R tau : Nat) : Nat := maxN (timeNs (ddrBytesDieP K N m) R) (mmaNs K N m tau)
def predictedP (K N m R tau : Nat) : Nat := rateT (wBytes K N) (kernelNsP K N m R tau)
/-- loader-bound W8 rate, tenths: 8 cores × L × 64/66 (B is 64 of every 66 KiB through the loader) -/
def loaderRate (L : Nat) : Nat := (2 * 8 * L * 64 + 66) / (2 * 66)
/-- Route 1b: f16 tiles carry 2 B per weight through the loader -/
def loaderRate1b (L : Nat) : Nat := (2 * 8 * L * 64 + 132) / (2 * 132)
/-- predicted W8 m=1 rate as a function of the unmeasured loader rate L (tenths of GB/s/core) -/
def predictedW8 (L : Nat) : Nat := minN 1685 (loaderRate L)
/-- W4 die byte rate (tenths): min(DDR roof, 8·D·0.5 B, 8·L/4) with D tenths of Gelem/s/core, L tenths of f16 GB/s/core -/
def w4Rate (D L : Nat) : Nat := minN Measured.rDdr (minN (4 * D) (2 * L))
/-- MMA-issue-bound die rate (tenths) for a 16 KiB tile with per-call cost c ns: 8·16384 B / (236.8 + c) ns -/
def mmaCap (c : Nat) : Nat := (2 * 8 * 16384 * 100 + (2368 + 10 * c)) / (2 * (2368 + 10 * c))
/-- ns → µs, round half up -/
def usR (ns : Nat) : Nat := (ns + 500) / 1000
/-- tenths of a percent, round half up -/
def pct (num den : Nat) : Nat := (2 * num * 1000 + den) / (2 * den)
/-- per-call MMA time, tenths of ns: 64 fragments × 3.70 ns -/
def perCallTenths : Nat := 64 * Measured.tau370 / 10
/-- tile cadence in ns: tileBytes at 22.5 GB/s/core (= 180/8, the demonstrated per-core copy rate) -/
def cadenceNs (tileBytes : Nat) : Nat := tileBytes * 10 / (Measured.rStage / 8)

/-! ### Pack geometry (§3.1).  A [64 k-rows, 256 cols] i8 tile; byte offsets inside the tile. -/
namespace Pack
/-- G1c (primary; HW-MAP's literal formula, dense): 8 column groups of 32, block (i, r) at (i·64 + r)·32, byte n' mod 32 -/
def g1c (k n' : Nat) : Nat := ((n' / 32) * 64 + k) * 32 + n' % 32
def g1cK (b : Nat) : Nat := (b / 32) % 64
def g1cN (b : Nat) : Nat := ((b / 32) / 64) * 32 + b % 32
/-- G1a (alternative, dense): 16 column groups, k-pairs per 32 B block, block = [2 k][16 n] -/
def g1a (k n' : Nat) : Nat := ((n' / 16) * 32 + k / 2) * 32 + (k % 2) * 16 + n' % 16
def g1aK (b : Nat) : Nat := 2 * ((b / 32) % 32) + (b % 32) / 16
def g1aN (b : Nat) : Nat := ((b / 32) / 32) * 16 + b % 16
/-- G1b (alternative, dense): 16 column groups, k-pairs per 32 B block, block = [16 n][2 k] -/
def g1b (k n' : Nat) : Nat := ((n' / 16) * 32 + k / 2) * 32 + (n' % 16) * 2 + k % 2
def g1bK (b : Nat) : Nat := 2 * ((b / 32) % 32) + b % 2
def g1bN (b : Nat) : Nat := ((b / 32) / 32) * 16 + (b % 32) / 2
/-- G2 (alternative, 2 B per element): 16 column groups, one k-row per 32 B block, 2 bytes per element -/
def g2 (k n' byte : Nat) : Nat := ((n' / 16) * 64 + k) * 32 + (n' % 16) * 2 + byte
/-- the round-1 DESIGN.md §3.1 formula (16 column groups, one k-row per 32 B block, 1 byte per element) -/
def old (k n' : Nat) : Nat := ((n' / 16) * 64 + k) * 32 + n' % 16
end Pack

/-! ### Accumulation semantics (§1.2, E1).  Partial products per k-chunk are exact integers in the oracle. -/
namespace Accum
def sumList : List Int → Int
  | [] => 0
  | p :: ps => p + sumList ps
/-- every chunk accumulates: C ← C + p -/
def accumulate : Int → List Int → Int
  | c, [] => c
  | c, p :: ps => accumulate (c + p) ps
/-- every chunk overwrites: C ← p -/
def overwrite : Int → List Int → Int
  | c, [] => c
  | _, p :: ps => overwrite p ps
/-- correct polarity: chunk 0 zero-inits (C ← p₀), later chunks accumulate -/
def runCorrect : Int → List Int → Int
  | c, [] => c
  | _, p :: ps => accumulate p ps
/-- inverted polarity: chunk 0 accumulates onto the stale C, later chunks overwrite -/
def runInverted : Int → List Int → Int
  | c, [] => c
  | c, p :: ps => overwrite (c + p) ps
end Accum

end Design

namespace Proofs
open Measured Design

/-! ## T0 — the constants table's own derived rows (HW-MAP "Derived" lines re-checked) -/

/-- 16³ MACs = 8192 FLOP × 8 cores / 17.8 TFLOPS = 65536/17.8 ps = 3.68 ns ≈ 3.7 (65536/178 = hundredths of ns) -/
theorem T0_tau_from_17_8 : (2 * 65536 + 178) / (2 * 178) = 368 := by decide
/-- 26.6 TFLOPS/8 cores → 65536/26.6 ps = 2.46 ns -/
theorem T0_tau_from_26_6 : (2 * 65536 + 266) / (2 * 266) = 246 := by decide
/-- 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core (tenths: 432) -/
theorem T0_rvec : 40 * 108 / 10 = rVec := by decide
/-- per-core shares of the two roofs: 180/8 = 22.5, 173.8/8 = 21.7 remainder 2 (= 21.725) -/
theorem T0_per_core_rates : rStage / 8 = 225 ∧ rDdr / 8 = 217 ∧ rDdr % 8 = 2 := by decide
/-- 64 MiB of W8 = 67.11 MB; 1 MB PRIOR S1 = 976 KiB -/
theorem T0_units : 64 * MiB = 67108864 ∧ s1P / KiB = 976 := by decide

/-! ## T1 — m=1 DDR-bound rate (§0, §7.1) -/

/-- 64 MiB of W8 plus 8 cores × 256 KiB of A = 66 MiB per die at m=1 -/
theorem T1_m1_bytes : ddrBytesDie 8192 8192 1 l0cP s1P 256 = 66 * MiB := by decide
/-- 66 MiB at 173.8 GB/s = 398 193 ns (398 µs) -/
theorem T1_m1_ddr_time : timeNs (66 * MiB) rDdr = 398193 := by decide
theorem T1_m1_ddr_time_us : usR (timeNs (66 * MiB) rDdr) = 398 := by decide
/-- headline: 67.1 MB of weights in 398 193 ns = 168.5 GB/s (= 173.8 × 64/66, rounded) -/
theorem T1_m1_ddr_bound_rate : predicted 8192 8192 1 l0cP s1P rDdr tau370 256 = 1685 := by decide
theorem T1_m1_rate_is_64_66 : rateT (64 * MiB) (timeNs (66 * MiB) rDdr) = 1685 := by decide
/-- the same at the 180 GB/s staging figure: 174.5 -/
theorem T1_m1_rate_at_180 : predicted 8192 8192 1 l0cP s1P rStage tau370 256 = 1745 := by decide
/-- m=16 is the same fragment count (mFrag = 1) hence the same number -/
theorem T1_m16_same_as_m1 : predicted 8192 8192 16 l0cP s1P rDdr tau370 256 = 1685 := by decide
/-- per-core view: 8 MiB + 256 KiB -/
theorem T1_bytes_per_core : ddrBytesDie 8192 8192 1 l0cP s1P 256 / 8 = 8650752 := by decide
/-- MMA occupancy at m=1: 121 241 ns of 398 193 = 30.4 %; at 2.46 ns: 80 609 ns = 20.2 % -/
theorem T1_mma_time_370 : mmaNs 8192 8192 1 tau370 = 121241 := by decide
theorem T1_mma_time_246 : mmaNs 8192 8192 1 tau246 = 80609 := by decide
theorem T1_mma_occupancy_370 : pct (mmaNs 8192 8192 1 tau370) (timeNs (66 * MiB) rDdr) = 304 := by decide
theorem T1_mma_occupancy_246 : pct (mmaNs 8192 8192 1 tau246) (timeNs (66 * MiB) rDdr) = 202 := by decide
/-- vector epilogue: 16 rows × (Mul + Cast) × 1024 lanes = 32 768 lane-ops / 43.2 G = 758 ns = 0.2 % -/
theorem T1_epilogue_ns : 16 * 2 * 1024 * 10 / rVec = 758 := by decide
theorem T1_epilogue_pct : pct 758 398193 = 2 := by decide
/-- the ASSUMED 5 µs fill/drain budget is 1.2 % of the kernel (budget itself is empirical: E7/E10) -/
theorem T1_fill_pct : pct 5000 (398193 + 5000) = 12 := by decide
/-- Route 1b: the i8→f16 cast of 8 Mi elements per core takes 194 180 ns = 48.8 % of the DDR time -/
theorem T1_cast_time : 8 * MiB * 10 / rVec = 194180 := by decide
theorem T1_cast_pct : pct (8 * MiB * 10 / rVec) 398193 = 488 := by decide
/-- wall-clock with an unpipelined 91 µs launch floor: 137.2 GB/s -/
theorem T1_wall_with_launch : rateT (64 * MiB) (398193 + tLaunch) = 1372 := by decide
theorem T1_with_fill : rateT (64 * MiB) (398193 + 5000) = 1664 := by decide

/-! ## T2 — loader thresholds (§7.3), universally quantified over the unmeasured L (tenths of GB/s/core) -/

/-- target 120 GB/s is met iff L ≥ 15.5 GB/s/core -/
theorem T2_loader_threshold_target (L : Nat) : predictedW8 L ≥ 1200 ↔ L ≥ 155 := by
  unfold predictedW8 minN loaderRate
  constructor
  · intro h; split at h <;> omega
  · intro h; split <;> omega
/-- the DDR-bound figure 168.5 is reached iff L ≥ 21.8 (the first tenth above 173.8/8 = 21.725) -/
theorem T2_loader_threshold_roof (L : Nat) : predictedW8 L = 1685 ↔ L ≥ 218 := by
  unfold predictedW8 minN loaderRate
  constructor
  · intro h; split at h <;> omega
  · intro h; split <;> omega
/-- below that the design is loader-bound: predicted = 8·L·64/66 < 168.5 -/
theorem T2_loader_bound_branch (L : Nat) (h : L ≤ 217) :
    predictedW8 L = loaderRate L ∧ loaderRate L ≤ 1683 := by
  unfold predictedW8 minN loaderRate
  constructor
  · split <;> omega
  · omega
/-- the loader-bound curve is monotone in L -/
theorem T2_loader_rate_monotone (L L' : Nat) (h : L ≤ L') : loaderRate L ≤ loaderRate L' := by
  unfold loaderRate; omega
/-- breakpoints quoted in §7.3 -/
theorem T2_at_100 : loaderRate 100 = 776 := by decide
theorem T2_at_155 : loaderRate 155 = 1202 := by decide
theorem T2_at_185 : loaderRate 185 = 1435 := by decide
theorem T2_at_217 : loaderRate 217 = 1683 := by decide
theorem T2_at_220 : loaderRate 220 = 1707 := by decide
theorem T2_crossover : rDdr / 8 = 217 ∧ rDdr % 8 = 2 := by decide
/-- the §7.3 table, cell by cell -/
theorem T2_table_w8 : predictedW8 100 = 776 ∧ predictedW8 155 = 1202 ∧ predictedW8 185 = 1435 ∧ predictedW8 217 = 1683 ∧
    predictedW8 218 = 1685 ∧ predictedW8 220 = 1685 ∧ predictedW8 310 = 1685 ∧ predictedW8 435 = 1685 := by decide
theorem T2_table_loader : loaderRate 310 = 2405 ∧ loaderRate 435 = 3375 := by decide
theorem T2_table_1b : minN 1685 (loaderRate1b 100) = 388 ∧ minN 1685 (loaderRate1b 155) = 601 ∧
    minN 1685 (loaderRate1b 185) = 718 ∧ minN 1685 (loaderRate1b 217) = 842 ∧ minN 1685 (loaderRate1b 218) = 846 ∧
    minN 1685 (loaderRate1b 220) = 853 ∧ minN 1685 (loaderRate1b 310) = 1202 ∧ minN 1685 (loaderRate1b 435) = 1685 := by decide
/-- Route 1b (f16 tiles, 2 B/weight through the loader) meets target iff L ≥ 31.0 and the roof iff L ≥ 43.5 -/
theorem T2_1b_threshold_target (L : Nat) : loaderRate1b L ≥ 1200 ↔ L ≥ 310 := by
  unfold loaderRate1b; constructor <;> intro h <;> omega
theorem T2_1b_threshold_roof (L : Nat) : loaderRate1b L ≥ 1685 ↔ L ≥ 435 := by
  unfold loaderRate1b; constructor <;> intro h <;> omega
/-- §9: the library's 148 GB/s/die f16 matmul implies some L0 ingress path sustained ≥ 18.5 GB/s/core;
    IF that path is S1→L0 (unproven premise), the design is ≥ 143.5 GB/s -/
theorem T2_inference_from_library (L : Nat) (hPremise : L ≥ 185) : predictedW8 L ≥ 1435 := by
  unfold predictedW8 minN loaderRate; split <;> omega

/-! ## T3 — MMA off the critical path (§1.3), universally quantified over the unmeasured c_mma (ns) -/

theorem T3_per_call_tenths : perCallTenths = 2368 := by decide
theorem T3_per_call_246 : 64 * tau246 / 10 = 1574 := by decide
theorem T3_cadence_16KiB_at_22_5 : cadenceNs 16384 = 728 := by decide
theorem T3_cadence_16KiB_at_21_725 : 16384 * 80 / rDdr = 754 := by decide
/-- slack = 728.0 − 236.8 = 491.2 ns -/
theorem T3_slack_256x64 : cadenceNs 16384 * 10 - perCallTenths = 4912 := by decide
/-- any per-call issue cost ≤ 491 ns keeps 236.8 + c under the 728 ns tile cadence -/
theorem T3_mma_off_critical_path (c : Nat) (h : c ≤ 491) : 2368 + 10 * c ≤ 7280 := by omega
/-- and 492 ns is the first value that does not -/
theorem T3_mma_exposed (c : Nat) (h : c ≥ 492) : 2368 + 10 * c > 7280 := by omega
/-- the user's round number 490 is inside the safe region -/
theorem T3_490_safe : 2368 + 10 * 490 ≤ 7280 := by decide
/-- c_mma = 1 µs would cap the die at 106.0 GB/s; c_mma = 0 gives the 553.5 GB/s MMA ceiling (= 8 × 69.2) -/
theorem T3_cap_1000 : mmaCap 1000 = 1060 := by decide
theorem T3_cap_0 : mmaCap 0 = 5535 := by decide
/-- (1024×64) tiles: cadence 2912 ns − 4 × 236.8 ns = 1964.8 ns of slack per call -/
theorem T3_slack_1024x64 : cadenceNs 65536 * 10 - 4 * perCallTenths = 19648 := by decide
/-- m=64 at 3.7 ns: 8 MiB of B per core in 484 966 ns = 17.3 GB/s/core → 138.4 GB/s/die -/
theorem T3_m64_mma_time : mmaNs 8192 8192 64 tau370 = 484966 := by decide
theorem T3_m64_core_rate : rateT (8 * MiB) (mmaNs 8192 8192 64 tau370) = 173 := by decide
theorem T3_m64_die_rate : 8 * rateT (8 * MiB) (mmaNs 8192 8192 64 tau370) = 1384 := by decide
/-- B-only DDR time per core at 22.5 GB/s/core: 373 µs (the figure used for slack budgets) -/
theorem T3_ddr_373 : usR (timeNs (8 * MiB) (rStage / 8)) = 373 := by decide
/-- τ ≤ 3.46 ns from the library's flat 148 GB/s to M=128: 512 B / 18.5 GB/s / 8 fragments -/
theorem T3_tau_from_148 : (2 * 512 * 100 + 148) / (2 * 148) = 346 := by decide

/-! ## T4 — issue counts (§1.3) -/

theorem T4_calls_8192 (m : Nat) : calls 8192 8192 m = 512 * mFrag m := by
  simp only [calls, Nc, Nat.reduceDiv, Nat.reduceMul]
theorem T4_calls_4096 (m : Nat) : calls 4096 4096 m = 128 * mFrag m := by
  simp only [calls, Nc, Nat.reduceDiv, Nat.reduceMul]
theorem T4_calls_2048 (m : Nat) : calls 2048 2048 m = 32 * mFrag m := by
  simp only [calls, Nc, Nat.reduceDiv, Nat.reduceMul]
theorem T4_Nc : Nc 8192 = 1024 ∧ Nc 4096 = 512 ∧ Nc 2048 = 256 ∧ 8192 / 64 = 128 := by decide
theorem T4_mt_values : mFrag 1 = 1 ∧ mFrag 16 = 1 ∧ mFrag 32 = 2 ∧ mFrag 48 = 3 ∧ mFrag 64 = 4 := by decide
theorem T4_instances_8192 :
    calls 8192 8192 1 = 512 ∧ calls 8192 8192 16 = 512 ∧ calls 8192 8192 32 = 1024 ∧
    calls 8192 8192 48 = 1536 ∧ calls 8192 8192 64 = 2048 := by decide
theorem T4_instances_4096 : calls 4096 4096 1 = 128 ∧ calls 4096 4096 64 = 512 := by decide
theorem T4_instances_2048 : calls 2048 2048 1 = 32 ∧ calls 2048 2048 64 = 128 := by decide
/-- MMA busy per core, µs, mFrag = 1..4 at the three τ values (§1.3, §7.2 columns) -/
theorem T4_mma_us_370 : usR (mmaNs 8192 8192 16 tau370) = 121 ∧ usR (mmaNs 8192 8192 32 tau370) = 242 ∧
    usR (mmaNs 8192 8192 48 tau370) = 364 ∧ usR (mmaNs 8192 8192 64 tau370) = 485 := by decide
theorem T4_mma_us_346 : usR (mmaNs 8192 8192 16 tau346) = 113 ∧ usR (mmaNs 8192 8192 32 tau346) = 227 ∧
    usR (mmaNs 8192 8192 48 tau346) = 340 ∧ usR (mmaNs 8192 8192 64 tau346) = 454 := by decide
theorem T4_mma_us_246 : usR (mmaNs 8192 8192 16 tau246) = 81 ∧ usR (mmaNs 8192 8192 32 tau246) = 161 ∧
    usR (mmaNs 8192 8192 48 tau246) = 242 ∧ usR (mmaNs 8192 8192 64 tau246) = 322 := by decide
/-- 16³-only fallback (§9): 32 768 calls per core, 11.3 ns of slack each -/
theorem T4_16cube_calls : (8192 / 16) * (Nc 8192 / 16) = 32768 := by decide
theorem T4_16cube_slack_tenths : 373000 * 10 / 32768 = 113 := by decide
/-- §9: 256 copy-in calls per core; 373 µs / 256 = 1457 ns each -/
theorem T4_copyin_calls : 2 * (8192 / 64) = 256 ∧ 373000 * 10 / 256 = 14570 := by decide

/-! ## T5 — the m-curve (§7.2), K=N=8192, L0C = 64 KiB (P), S1 = 1 MB (P), R = 173.8 -/

theorem T5_slabs : nSlab 8192 1 l0cP 256 = 1024 ∧ nSlab 8192 32 l0cP 256 = 512 ∧
    nSlab 8192 48 l0cP 256 = 256 ∧ nSlab 8192 64 l0cP 256 = 256 := by decide
theorem T5_nslabs : nSlabs 8192 1 l0cP 256 = 1 ∧ nSlabs 8192 32 l0cP 256 = 2 ∧
    nSlabs 8192 48 l0cP 256 = 4 ∧ nSlabs 8192 64 l0cP 256 = 4 := by decide
theorem T5_a_bytes : aBytesCore 8192 1 = 256 * KiB ∧ aBytesCore 8192 32 = 512 * KiB ∧
    aBytesCore 8192 48 = 768 * KiB ∧ aBytesCore 8192 64 = 1024 * KiB := by decide
/-- m=32: A (512 KiB) + B ring (256 KiB) = 768 KiB fits the 1 MB S1 → resident; m=48: 1 MiB does not -/
theorem T5_m32_resident : aBytesCore 8192 32 + 256 * KiB ≤ s1P := by decide
theorem T5_m48_not_resident : ¬ (aBytesCore 8192 48 + 256 * KiB ≤ s1P) := by decide
theorem T5_ddr_bytes : ddrBytesDie 8192 8192 32 l0cP s1P 256 = 68 * MiB ∧
    ddrBytesDie 8192 8192 32 l0cP 0 256 = 72 * MiB ∧
    ddrBytesDie 8192 8192 48 l0cP s1P 256 = 88 * MiB ∧
    ddrBytesDie 8192 8192 64 l0cP s1P 256 = 96 * MiB ∧
    ddrBytesDieP 8192 8192 64 = 72 * MiB ∧
    ddrBytesDie 8192 8192 64 (256 * KiB) s1P 256 = 72 * MiB := by decide
theorem T5_ddr_us : usR (timeNs (68 * MiB) rDdr) = 410 ∧ usR (timeNs (72 * MiB) rDdr) = 434 ∧
    usR (timeNs (88 * MiB) rDdr) = 531 ∧ usR (timeNs (96 * MiB) rDdr) = 579 := by decide
/-- the rows -/
theorem T5_m32 : predicted 8192 8192 32 l0cP s1P rDdr tau370 256 = 1636 := by decide
theorem T5_m32_restream : predicted 8192 8192 32 l0cP 0 rDdr tau370 256 = 1545 := by decide
theorem T5_m48 : predicted 8192 8192 48 l0cP s1P rDdr tau370 256 = 1264 := by decide
theorem T5_m64 : predicted 8192 8192 64 l0cP s1P rDdr tau370 256 = 1159 := by decide
/-- those four rows are DDR-bound at every τ (the m=64 row at 2.46 ns included) -/
theorem T5_m64_ddr_bound : mmaNs 8192 8192 64 tau370 ≤ timeNs (96 * MiB) rDdr := by decide
theorem T5_m48_ddr_bound : mmaNs 8192 8192 48 tau370 ≤ timeNs (88 * MiB) rDdr := by decide
theorem T5_m32_ddr_bound : mmaNs 8192 8192 32 tau370 ≤ timeNs (68 * MiB) rDdr := by decide
theorem T5_rows_tau_independent :
    predicted 8192 8192 32 l0cP s1P rDdr tau246 256 = 1636 ∧
    predicted 8192 8192 48 l0cP s1P rDdr tau246 256 = 1264 ∧
    predicted 8192 8192 64 l0cP s1P rDdr tau246 256 = 1159 := by decide
/-- scheme P: MMA-bound at 3.70 and 3.46 ns (138.4, 148.0), DDR-bound at 2.46 ns (154.5) -/
theorem T5_m64_P_370 : predictedP 8192 8192 64 rDdr tau370 = 1384 := by decide
theorem T5_m64_P_346 : predictedP 8192 8192 64 rDdr tau346 = 1480 := by decide
theorem T5_m64_P_246 : predictedP 8192 8192 64 rDdr tau246 = 1545 := by decide
theorem T5_m64_P_mma_bound_370 : timeNs (72 * MiB) rDdr < mmaNs 8192 8192 64 tau370 := by decide
theorem T5_m64_P_mma_bound_346 : timeNs (72 * MiB) rDdr < mmaNs 8192 8192 64 tau346 := by decide
theorem T5_m64_P_ddr_bound_246 : mmaNs 8192 8192 64 tau246 ≤ timeNs (72 * MiB) rDdr := by decide
/-- L0C ≥ 256 KiB: a single 1024-column slab, same bytes and same band as scheme P -/
theorem T5_m64_bigL0C_slab : nSlab 8192 64 (256 * KiB) 256 = 1024 ∧ nSlabs 8192 64 (256 * KiB) 256 = 1 := by decide
theorem T5_m64_bigL0C : predicted 8192 8192 64 (256 * KiB) s1P rDdr tau370 256 = 1384 ∧
    predicted 8192 8192 64 (256 * KiB) s1P rDdr tau246 256 = 1545 := by decide
/-- the MMA bound at m=64 switches to DDR-bound exactly when 2048·64·τ/100 ≤ 434 392 ns, i.e. τ ≤ 3.31 ns at 72 MiB -/
theorem T5_m64_P_switch (tau : Nat) (h : tau ≤ 331) : mmaNs 8192 8192 64 tau ≤ timeNs (72 * MiB) rDdr := by
  unfold mmaNs calls Nc mFrag timeNs
  simp only [Nat.reduceDiv, Nat.reduceMul, Nat.reduceAdd, MiB, rDdr]
  omega
theorem T5_m64_P_switch_tight : timeNs (72 * MiB) rDdr < mmaNs 8192 8192 64 332 := by decide
/-- §10: L0C = 128 KiB at m=64 → 2 slabs, 80 MiB → MMA-bound 138.4 at 3.7 ns, DDR-bound 139.0 at 2.46 ns -/
theorem T5_m64_l0c128 : nSlabs 8192 64 (128 * KiB) 256 = 2 ∧
    predicted 8192 8192 64 (128 * KiB) s1P rDdr tau370 256 = 1384 ∧
    predicted 8192 8192 64 (128 * KiB) s1P rDdr tau246 256 = 1390 := by decide
/-- §9 rows: L0C = 32 KiB keeps m=16 at 168.5 (A stays resident: 2 slabs but one A pass);
    m=64 with n=128 tiles → 8 slabs, A re-streamed 8× → 86.9 -/
theorem T5_l0c32_m16 : nSlabs 8192 16 (32 * KiB) 256 = 2 ∧ predicted 8192 8192 16 (32 * KiB) s1P rDdr tau370 256 = 1685 := by decide
theorem T5_l0c32_m64 : nSlabs 8192 64 (32 * KiB) 128 = 8 ∧ predicted 8192 8192 64 (32 * KiB) s1P rDdr tau370 128 = 869 := by decide
theorem T5_l0c32_m16_if_restreamed : predicted 8192 8192 16 (32 * KiB) 0 rDdr tau370 256 = 1636 := by decide
/-- scheme P side costs (§1.4): 196 608 f32 adds = 4 551 ns; 2 MiB of US↔S1 copies = 8 388 ns; 1 MiB drain at 10 GB/s = 105 µs -/
theorem T5_P_adds : 3 * 64 * 1024 * 10 / rVec = 4551 := by decide
theorem T5_P_copies : 2 * MiB * 10 / rUsS1 = 8388 := by decide
theorem T5_P_drain : usR (MiB * 10 / 100) = 105 := by decide
theorem T5_P_s1 : 256 * KiB + 256 * KiB + 256 * KiB = 768 * KiB := by decide
/-- scheme P geometry: A block [64, 2048] f16 = 256 KiB; 16 (block, slab) drains × 64 KiB = 1 MiB; A once = 1 MiB = 12.5 % of 8 MiB -/
theorem T5_P_geometry : 64 * 2048 * 2 = 256 * KiB ∧ 4 * 4 * 64 * KiB = MiB ∧ pct MiB (8 * MiB) = 125 := by decide
/-- §7.2: the m=64 sag at the PRIOR sizes is 3.4 % under the 120 target; A residency at m=32 is worth 9.1 GB/s -/
theorem T5_m64_shortfall : pct (1200 - 1159) 1200 = 34 ∧ 1636 - 1545 = 91 := by decide
/-- §1.4 reasons: k-outer would drain 128 × 64 KiB = 8 MiB per core; A is 2 KiB of every 66 KiB (3.1 %) at mt=1, 8 KiB (12.5 %) at mt=4 -/
theorem T5_korder_cost : 128 * 64 * KiB = 8 * MiB ∧ pct (2 * KiB) (64 * KiB) = 31 ∧ pct (8 * KiB) (64 * KiB) = 125 ∧ pct (2 * MiB) (64 * MiB) = 31 := by decide

/-! ## T6 — W4 thresholds (§5), universally quantified over the unmeasured D and L -/

/-- target 120 W4-GB/s iff D ≥ 30.0 Gelem/s/core and L ≥ 60.0 GB/s/core of f16 -/
theorem T6_w4_target (D L : Nat) : w4Rate D L ≥ 1200 ↔ (D ≥ 300 ∧ L ≥ 600) := by
  unfold w4Rate minN rDdr
  constructor
  · intro h; split at h <;> split at h <;> omega
  · intro h; split <;> split <;> omega
/-- W4 beats W8-at-the-roof in tokens/s (2 × W4 byte rate ≥ 173.8) iff D ≥ 21.8 and L ≥ 43.5 -/
theorem T6_w4_beats_w8 (D L : Nat) : 2 * w4Rate D L ≥ 1738 ↔ (D ≥ 218 ∧ L ≥ 435) := by
  unfold w4Rate minN rDdr
  constructor
  · intro h; split at h <;> split at h <;> omega
  · intro h; split <;> split <;> omega
/-- W4 sits on the DDR roof (dequant and loader not binding) iff D ≥ 43.5 and L ≥ 86.9 -/
theorem T6_w4_roof (D L : Nat) : w4Rate D L = 1738 ↔ (D ≥ 435 ∧ L ≥ 869) := by
  unfold w4Rate minN rDdr
  constructor
  · intro h; split at h <;> split at h <;> omega
  · intro h; split <;> split <;> omega
/-- the DDR-bound W4 rate including the 2 MiB A stream is 163.6 (32 MiB of 34 MiB), not 173.8 -/
theorem T6_w4_ddr_incl_A : rateT (32 * MiB) (timeNs (32 * MiB + 8 * aBytesCore 8192 1) rDdr) = 1636 := by decide
theorem T6_w4_ddr_time : usR (timeNs (32 * MiB) rDdr) = 193 ∧ usR (32 * MiB * 10 / 1200) = 280 := by decide
/-- dequant branch points: D = 43.2 → 194 µs → 172.8; D = 30 → 280 µs → 120.0; D = 21.8 → 87.2; D = 21.7 → 86.8 -/
theorem T6_dequant_432 : usR (8 * MiB * 10 / 432) = 194 ∧ rateT (32 * MiB) (8 * MiB * 10 / 432) = 1728 := by decide
theorem T6_dequant_300 : usR (8 * MiB * 10 / 300) = 280 ∧ rateT (32 * MiB) (8 * MiB * 10 / 300) = 1200 := by decide
theorem T6_dequant_218 : usR (8 * MiB * 10 / 218) = 385 ∧ rateT (32 * MiB) (8 * MiB * 10 / 218) = 872 ∧ 2 * 872 ≥ 1738 := by decide
theorem T6_dequant_217 : rateT (32 * MiB) (8 * MiB * 10 / 217) = 868 ∧ 2 * 868 < 1738 := by decide
/-- vector arrange at 5 lane-ops/element: 971 µs → 34.6 W4-GB/s = 69.2 W8-equivalent -/
theorem T6_vector_arrange : usR (8 * MiB * 5 * 10 / rVec) = 971 ∧ rateT (32 * MiB) (8 * MiB * 5 * 10 / rVec) = 346 ∧ 2 * 346 = 692 := by decide
theorem T6_elements_per_core : 8192 * Nc 8192 = 8 * MiB ∧ 32 * MiB = 8 * (8 * MiB) / 2 := by decide
/-- f16 round trip: 128 MiB at 173.8 = 772 µs → 43.5 W4-equivalent -/
theorem T6_f16_roundtrip : usR (timeNs (128 * MiB) rDdr) = 772 ∧ rateT (32 * MiB) (timeNs (128 * MiB) rDdr) = 435 := by decide
/-- f16 B consumption by the MMA: 512 B per 3.70 ns = 138.4 GB/s/core; 86.9 of it = 62.8 % busy -/
theorem T6_f16_consumption : (2 * 512 * 1000 + 370) / (2 * 370) = 1384 ∧ pct 869 1384 = 628 := by decide
/-- (d): K/128 = 64 drains of 64 KiB·mFrag per core = 4 MiB·mFrag -/
theorem T6_drains : 8192 / 128 = 64 ∧ 64 * 64 * KiB = 4 * MiB := by decide
/-- US budget for W4 (§2): 2×16 + 2×32 + 32 + 32 + 4 = 164 KiB ≤ 208 KiB evidenced -/
theorem T6_us_budget : 2 * 16 + 2 * 32 + 32 + 32 + 4 = 164 ∧ 164 ≤ 208 := by decide

/-! ## T7 — pack geometry (§3.1): bijections for a [64 × 256] i8 tile, decided for Kb = 64 -/

/-- G1c: image inside the 16 KiB tile -/
theorem T7_g1c_range (k n' : Nat) (hk : k < 64) (hn : n' < 256) : Pack.g1c k n' < 16384 := by
  unfold Pack.g1c; omega
/-- G1c: left inverse (injective) -/
theorem T7_g1c_left_inverse (k n' : Nat) (hk : k < 64) (_hn : n' < 256) :
    Pack.g1cK (Pack.g1c k n') = k ∧ Pack.g1cN (Pack.g1c k n') = n' := by
  unfold Pack.g1c Pack.g1cK Pack.g1cN; omega
/-- G1c: right inverse (surjective onto the whole 16 KiB) -/
theorem T7_g1c_right_inverse (b : Nat) (hb : b < 16384) :
    Pack.g1c (Pack.g1cK b) (Pack.g1cN b) = b ∧ Pack.g1cK b < 64 ∧ Pack.g1cN b < 256 := by
  unfold Pack.g1c Pack.g1cK Pack.g1cN; omega
theorem T7_g1c_injective (k₁ n₁ k₂ n₂ : Nat) (h₁ : k₁ < 64) (h₂ : n₁ < 256) (h₃ : k₂ < 64) (h₄ : n₂ < 256)
    (he : Pack.g1c k₁ n₁ = Pack.g1c k₂ n₂) : k₁ = k₂ ∧ n₁ = n₂ := by
  unfold Pack.g1c at he; omega
/-- G1c is HW-MAP's literal block formula (i·Kb + r)·32 with Kb = 64 and i = n'/32 < 8 -/
theorem T7_g1c_is_hwmap_formula (k n' : Nat) : Pack.g1c k n' = ((n' / 32) * 64 + k) * 32 + n' % 32 := rfl
theorem T7_g1c_groups : 256 / 32 = 8 ∧ 8 * 64 * 32 = 16384 := by decide
/-- G1a: bijection -/
theorem T7_g1a_range (k n' : Nat) (hk : k < 64) (_hn : n' < 256) : Pack.g1a k n' < 16384 := by
  unfold Pack.g1a; omega
theorem T7_g1a_left_inverse (k n' : Nat) (hk : k < 64) (_hn : n' < 256) :
    Pack.g1aK (Pack.g1a k n') = k ∧ Pack.g1aN (Pack.g1a k n') = n' := by
  unfold Pack.g1a Pack.g1aK Pack.g1aN; omega
theorem T7_g1a_right_inverse (b : Nat) (hb : b < 16384) :
    Pack.g1a (Pack.g1aK b) (Pack.g1aN b) = b ∧ Pack.g1aK b < 64 ∧ Pack.g1aN b < 256 := by
  unfold Pack.g1a Pack.g1aK Pack.g1aN; omega
/-- G1b: bijection -/
theorem T7_g1b_range (k n' : Nat) (hk : k < 64) (_hn : n' < 256) : Pack.g1b k n' < 16384 := by
  unfold Pack.g1b; omega
theorem T7_g1b_left_inverse (k n' : Nat) (hk : k < 64) (_hn : n' < 256) :
    Pack.g1bK (Pack.g1b k n') = k ∧ Pack.g1bN (Pack.g1b k n') = n' := by
  unfold Pack.g1b Pack.g1bK Pack.g1bN; omega
theorem T7_g1b_right_inverse (b : Nat) (hb : b < 16384) :
    Pack.g1b (Pack.g1bK b) (Pack.g1bN b) = b ∧ Pack.g1bK b < 64 ∧ Pack.g1bN b < 256 := by
  unfold Pack.g1b Pack.g1bK Pack.g1bN; omega
/-- G2: injective, but a 64×256 tile occupies 32 KiB (last byte 32767), i.e. 2 B per element -/
theorem T7_g2_injective (k₁ n₁ b₁ k₂ n₂ b₂ : Nat) (h₁ : k₁ < 64) (h₂ : n₁ < 256) (h₃ : b₁ < 2)
    (h₄ : k₂ < 64) (h₅ : n₂ < 256) (h₆ : b₂ < 2) (he : Pack.g2 k₁ n₁ b₁ = Pack.g2 k₂ n₂ b₂) :
    k₁ = k₂ ∧ n₁ = n₂ ∧ b₁ = b₂ := by
  unfold Pack.g2 at he; omega
theorem T7_g2_tile_is_32KiB : Pack.g2 63 255 1 + 1 = 2 * 64 * 256 := by decide
theorem T7_g2_range (k n' b : Nat) (hk : k < 64) (_hn : n' < 256) (hb : b < 2) : Pack.g2 k n' b < 32768 := by
  unfold Pack.g2; omega
/-- the round-1 formula was injective but NOT onto the 16 KiB tile: byte 16 is never written and the
    last element lands at byte 32751 > 16383 — the correction recorded in PROOF-COVERAGE.md -/
theorem T7_old_misses_byte_16 (k n' : Nat) (_hk : k < 64) (_hn : n' < 256) : Pack.old k n' ≠ 16 := by
  unfold Pack.old; omega
theorem T7_old_exceeds_tile : Pack.old 63 255 = 32751 ∧ 32751 ≥ 16384 := by decide
/-- tile/stream arithmetic of §3.1: tiles per k-chunk, bytes per tile, per-core region, 64 KiB copies -/
theorem T7_tiles : Nc 8192 / 256 = 4 ∧ 64 * 256 = 16384 ∧ 4 * 16384 = 65536 ∧ 8192 * Nc 8192 = 8 * MiB := by decide
theorem T7_tiles_4096 : Nc 4096 / 256 = 2 ∧ 4096 * Nc 4096 = 2 * MiB := by decide
theorem T7_tiles_2048 : Nc 2048 / 256 = 1 ∧ 2048 * Nc 2048 = 512 * KiB := by decide
/-- A block per (chunk, fragment): 16 × 64 × 2 B = 2 KiB; C row drain at m=1: 1024 × 4 B = 4 KiB; C slab 16×1024×4 = 64 KiB -/
theorem T7_a_block : 16 * 64 * 2 = 2 * KiB ∧ 1024 * 4 = 4 * KiB ∧ 16 * 1024 * 4 = 64 * KiB := by decide
/-- COPY_FRAC on the y scatter (§3.3): 32 KiB at 7 GB/s = 4 681 ns = 1.2 % of 8192²; 8 KiB at 2048² (m=16) = 4.3 % of 27 149 ns -/
theorem T7_frac_cost : 32 * KiB * 10 / rFrac = 4681 ∧ pct 4681 398193 = 12 := by decide
theorem T7_frac_cost_2048 : timeNs (ddrBytesDie 2048 2048 1 l0cP s1P 256) rDdr = 27149 ∧
    8 * KiB * 10 / rFrac = 1170 ∧ pct 1170 27149 = 43 := by decide

/-! ## T8 — accumulation semantics (§1.2, E1): initVal chaining over exact integer partial products -/

open Design.Accum in
theorem T8_accumulate_eq (c : Int) (ps : List Int) : accumulate c ps = c + sumList ps := by
  induction ps generalizing c with
  | nil => simp [accumulate, sumList]
  | cons p ps ih => simp only [accumulate, sumList]; rw [ih]; omega

open Design.Accum in
/-- correct polarity (zero-init at chunk 0, accumulate after) equals the full sum, whatever L0C held before -/
theorem T8_accumulation_semantics (c₀ p : Int) (ps : List Int) :
    runCorrect c₀ (p :: ps) = sumList (p :: ps) := by
  simp only [runCorrect, sumList]; rw [T8_accumulate_eq]

open Design.Accum in
/-- inverted polarity keeps only the last chunk once there are ≥ 2 chunks -/
theorem T8_inverted_keeps_last (c₀ p q : Int) (ps : List Int) :
    runInverted c₀ (p :: q :: ps) = overwrite q ps := by
  simp [runInverted, overwrite]

open Design.Accum in
/-- a single-chunk test on a fresh (zero) accumulator cannot distinguish the polarities -/
theorem T8_single_chunk_cannot_detect (p : Int) : runCorrect 0 [p] = runInverted 0 [p] := by
  simp [runCorrect, runInverted, accumulate, overwrite]

open Design.Accum in
/-- two chunks with a nonzero first partial product do: p + q ≠ q -/
theorem T8_two_chunks_detect (p q : Int) (hp : p ≠ 0) : runCorrect 0 [p, q] ≠ runInverted 0 [p, q] := by
  simp only [runCorrect, runInverted, accumulate, overwrite]; omega

open Design.Accum in
theorem T8_two_chunks_values (p q : Int) : runCorrect 0 [p, q] = p + q ∧ runInverted 0 [p, q] = q := by
  simp [runCorrect, runInverted, accumulate, overwrite]

/-- E1/E2 oracle exactness: integer column sums stay below 2²⁴ (exact in f32) -/
theorem T8_e1_exact : 2 * 64 * 15 < 2 ^ 24 := by decide
theorem T8_e2_exact : 10000 * 64 * 15 = 9600000 ∧ 9600000 < 2 ^ 24 := by decide
/-- Route 3 i32 accumulation cannot overflow: 127·127·8192 < 2³¹ -/
theorem T8_i32_no_overflow : 127 * 127 * 8192 < 2 ^ 31 := by decide
/-- E2: an MMA of 236.8 ns per 16 KiB tile cannot mask loader rates below 69.2 GB/s/core -/
theorem T8_e2_mask : (2 * 16384 * 100 + 2368) / (2 * 2368) = 692 := by decide

/-! ## T9 — other sizes (§7.4), partition alternatives (§6), routes 4/5 (§7.5), chunk cadence (§4.1), G2 branch (§9) -/

theorem T9_2048 : ddrBytesDie 2048 2048 1 l0cP s1P 256 = 4718592 ∧ timeNs 4718592 rDdr = 27149 ∧
    rateT (4 * MiB) 27149 = 1545 ∧ rateT (4 * MiB) (27149 + 5000) = 1305 ∧ rateT (4 * MiB) (27149 + tLaunch) = 355 := by decide
theorem T9_4096 : ddrBytesDie 4096 4096 1 l0cP s1P 256 = 17825792 ∧ timeNs 17825792 rDdr = 102564 ∧
    rateT (16 * MiB) 102564 = 1636 ∧ rateT (16 * MiB) (102564 + 5000) = 1560 ∧ rateT (16 * MiB) (102564 + tLaunch) = 867 := by decide
theorem T9_sizes_us : usR 27149 = 27 ∧ usR 102564 = 103 := by decide
/-- K-split at m=64: 64 MiB B + 1 MiB A + 16 MiB partial writes + 16 MiB reduction reads + 2 MiB y = 99 MiB → 112.4; with +91 µs: 97.5 -/
theorem T9_ksplit : 64 * MiB + 8 * (64 * (8192 / 8) * 2) + 16 * MiB + 16 * MiB + 2 * MiB = 99 * MiB ∧
    rateT (64 * MiB) (timeNs (99 * MiB) rDdr) = 1124 ∧ rateT (64 * MiB) (timeNs (99 * MiB) rDdr + tLaunch) = 975 := by decide
theorem T9_ksplit_worse_than_nsplit : rateT (64 * MiB) (timeNs (99 * MiB) rDdr) < 1159 := by decide
/-- M-split (4 groups × 2 cores, W streamed 4×): 258 MiB → 43.1 -/
theorem T9_msplit : 4 * (64 * MiB) + 4 * 2 * (256 * KiB) = 258 * MiB ∧ rateT (64 * MiB) (timeNs (258 * MiB) rDdr) = 431 := by decide
/-- route 4: 43.2 G lane-ops / 3 ops per weight = 14.4 G weights/s/core → 115.2 GB/s/die ceiling -/
theorem T9_route4 : rVec / 3 = 144 ∧ 8 * (rVec / 3) = 1152 := by decide
/-- route 5: 60 ns × (8192/64)² = 983 µs per tile -/
theorem T9_route4_m16 : (2 * 70 * 10 + 16) / 32 = 44 ∧ (2 * 78 * 10 + 16) / 32 = 49 := by decide
theorem T9_route5 : libQuad * (8192 / 64) * (8192 / 64) = 983040 ∧ usR 983040 = 983 := by decide
/-- §4.1 chunk: 66 KiB at 21.725 GB/s/core = 3 110 ns, at 22.5 = 3 003 ns; two chunks = 6 220 ns -/
theorem T9_chunk : (64 * KiB + 2 * KiB) * 80 / rDdr = 3110 ∧ (64 * KiB + 2 * KiB) * 10 / (rStage / 8) = 3003 := by decide
/-- §4.1 MMA per chunk: 4·mFrag calls × 236.8 ns → 30.5 / 60.9 / 91.4 / 121.8 % of 3 110 ns -/
theorem T9_chunk2 : 2 * 3110 = 6220 ∧ 4 * 64 * tau370 / 100 = 947 ∧ pct 5000 (27149 + 5000) = 156 := by decide
/-- §2 budget identities: rings, L0 buffers, US pieces -/
theorem T9_budget_arith : 4 * 64 * KiB = 256 * KiB ∧ 4 * 8 * KiB = 32 * KiB ∧ 2 * 8 * KiB = 16 * KiB ∧ 2 * 16 * KiB = 32 * KiB ∧
    16 * 1024 * 2 = 32 * KiB ∧ 16 * 256 * 4 = 16 * KiB ∧ 4 + 64 + 32 = 100 ∧ 1024 / 16 = 64 ∧ 16 * 4 = 64 ∧ 16 * 16 * 4 = 1024 := by decide
theorem T9_chunk_occupancy : pct (4 * 64 * tau370 / 100) 3110 = 305 ∧ pct (8 * 64 * tau370 / 100) 3110 = 609 ∧
    pct (12 * 64 * tau370 / 100) 3110 = 914 ∧ pct (16 * 64 * tau370 / 100) 3110 = 1218 := by decide
/-- §2 S1 budget: 4×64 + 4×8 = 288 KiB streamed-A; 512 + 256 + 32 = 800 KiB with A resident at m=32 -/
theorem T9_s1_budget : 4 * 64 + 4 * 8 = 288 ∧ 512 + 256 + 32 = 800 ∧ 800 * KiB ≤ s1P := by decide
/-- §9 single-buffered L0B at L = 50 GB/s/core: 327.7 + 236.8 = 564.4 ns per 16 KiB → 29.0 GB/s/core ≥ 21.8 -/
theorem T9_l0b_single : 16384 * 100 / 500 + 2368 = 5644 ∧ (2 * 16384 * 100 + 5644) / (2 * 5644) = 290 ∧ 290 ≥ 218 := by decide
/-- §9 geometry G2 branch: W8 tiles at 2 B/element → 130 MiB per die → 85.6 GB/s, below target -/
theorem T9_g2_rate : ddrBytesDieG2 8192 8192 1 = 130 * MiB ∧ rateT (64 * MiB) (timeNs (130 * MiB) rDdr) = 856 ∧ 856 < 1200 := by decide
/-- §7.5: the m=1 MMA-bound ceiling 553.5 GB/s is 8 × 69.2 GB/s/core (HW-MAP's "≥ 69 GB/s/core to stay fed") -/
theorem T9_69_per_core : 8 * 692 = 5536 ∧ mmaCap 0 = 5535 := by decide
/-- §7.3 / §5 crossover granularity: 173.8/8 = 21.725 lies strictly between 21.7 and 21.8 -/
theorem T9_crossover_between : 217 * 8 < rDdr ∧ rDdr < 218 * 8 := by decide

end Proofs
