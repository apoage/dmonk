/-
  proof/moe.lean — machine-checked derivations for DESIGN-2.md (dmonk, MoE grouped quant-GEMM).

  Core Lean 4 only (no Mathlib, no Batteries, no imports beyond the implicit Init).
  Every quantity is a scaled integer, exactly as in proof/moe.py, so every theorem closes with
  `decide`, `omega`, `rfl` or `simp` (structural steps: `unfold`, `intro`, `split`, `induction`,
  `constructor`, `rw` with core Nat lemmas):
    rates   : tenths of GB/s   (1 B/ns = 1 GB/s decimal → bytes*10/ns = tenths)   1353 = 135.3
    bytes   : bytes            (KiB = 1024, MiB = 1048576)
    time    : ns, floor        (timeNs b R = b*10 / R);  usR = µs round-half-up; usT = tenths of µs
    rate    : round-half-up    (rateT W t = (2*W*10 + t) / (2*t))
    pct     : tenths of a percent, round-half-up          pctH : hundredths
  PROOF-COVERAGE-2.md maps every number in DESIGN-2.md to a theorem here, a moe.py label, an
  experiment (EMPIRICAL) or an explicit ASSUMPTION.

  Build: `lean proof/moe.lean` (standalone) or `cd proof && lake build` (target `Moe`).
  No `axiom` and no `sorry` appear anywhere: namespace Measured holds plain definitions of the
  HW-MAP constants (with the row each one comes from) and nothing that DESIGN-2.md concludes.
-/

namespace Measured
/-- HW-MAP card table: LPDDR streaming per die = 173.8 GB/s (measured; the read+write roof). Tenths. -/
def rDdr : Nat := 1738
/-- HW-MAP data-movement table: DDR → S1 plain copies = 180 GB/s aggregate (≈ 22.5/core, measured). Tenths. -/
def rStage : Nat := 1800
/-- HW-MAP data-movement table: S1 → L0A/L0B loader = 26.5 GB/s/core strict-serial (measured). Tenths. -/
def lSer : Nat := 265
/-- HW-MAP data-movement table: MMA issue cost 15 ns/call at (m,n,k) = (16,16,128) (measured). ns. -/
def cMma : Nat := 15
/-- HW-MAP@3eaf322 "Full W8 decode kernel" row (the design's anchor): 137.8 GB/s aggregate, m=1 = m=16,
    fp64 20/20; the same table's MMA row quotes the 487 µs per-core stream it ran in. Tenths / ns. -/
def rDense : Nat := 1378
def tDense : Nat := 487000
/-- HW-MAP compute table: vector unit ~40 f16 lanes/cycle/core × 1.08 GHz = 43.2 G lane-ops/s/core. Tenths. -/
def rVec : Nat := 432
/-- HW-MAP data-movement table: ~91 µs launch + queue floor (measured). ns. -/
def tLaunch : Nat := 91000
/-- HW-MAP hierarchy table: L0A / L0B 64 KB each, L0C 256 KB (measured, raw-MMA probes). Bytes. -/
def l0a : Nat := 65536
def l0b : Nat := 65536
def l0c : Nat := 262144
/-- HW-MAP data-movement table: vendor grouped quant-GEMM at the MoE decode shape = 24.6 GB/s (measured). Tenths. -/
def rVendor : Nat := 246
/-- HW-MAP data-movement table: vector SRAM ↔ S1 plain fill 250–255 GB/s/core (measured). Tenths. -/
def rUsS1 : Nat := 2500
/-- HW-MAP hierarchy table: S1 ~1 MB (PRIOR), taken as decimal 1 000 000 B = 976 KiB; US ≥ 208 KB evidenced. -/
def s1P : Nat := 1000000
def usEvidenced : Nat := 208 * 1024
/-- HW-MAP (current, f951a5c) "Full W8 decode kernel" row: 174.6 GB/s aggregate flat m=1..16 on the
    DDR → L0B direct path (serial fallback 138.9). Tenths. Not the design's anchor: see T_sync_*. -/
def rKernelDirect : Nat := 1746
def rSerialFallback : Nat := 1389
/-- HW-MAP (current) data-movement table: DDR → L0B direct load 181.3 GB/s aggregate (measured). Tenths. -/
def rDirectLoad : Nat := 1813
/-- HW-MAP (current) dense-kernel row: "pure read streams sustain ~181" (the 173.8 roof was read+write). Tenths. -/
def rPureRead : Nat := 1810
/-- HW-MAP data-movement table: vector i4→f16 unpack ~42 GB/s aggregate int4-effective (measured). Tenths. -/
def rUnpack4 : Nat := 420
/-- HW-MAP card table: cross-die exchanges bounce through the host at 10.7 GB/s (measured). Tenths. -/
def rHostBounce : Nat := 107
end Measured

namespace Design

def KiB : Nat := 1024
def MiB : Nat := 1048576
/-- router descriptor bytes per core (≤ 16 × 10 × 6 B = 960, budgeted 1024) -/
def desc : Nat := 1024
/-- ASSUMED fixed per-step cost: 5 µs fill + 2 µs exposed dispatch + 1 µs tail (E14/E15). ns. -/
def fixed : Nat := 8000

/-- rate in tenths of GB/s of W bytes in t ns, round half up -/
def rateT (W t : Nat) : Nat := (2 * W * 10 + t) / (2 * t)
/-- ns → µs, round half up -/
def usR (ns : Nat) : Nat := (ns + 500) / 1000
/-- ns → tenths of µs, round half up -/
def usT (ns : Nat) : Nat := (ns + 50) / 100
/-- ns → tenths of ms, round half up -/
def msT (ns : Nat) : Nat := (ns + 50000) / 100000
/-- tenths of a percent, round half up -/
def pct (num den : Nat) : Nat := (2 * num * 1000 + den) / (2 * den)
/-- hundredths of a percent, round half up -/
def pctH (num den : Nat) : Nat := (2 * num * 10000 + den) / (2 * den)
/-- time in ns of `b` bytes at `R` tenths of GB/s (floor) -/
def timeNs (b R : Nat) : Nat := b * 10 / R
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b
/-- tokens per ms in hundredths: t tokens per `step` ns -/
def tokPerMs (t step : Nat) : Nat := (2 * t * 100000000 + step) / (2 * step)

/-! ### Geometry (§2, §5.1) — functions of (K, N_e, D, t); the routing family enters only through D. -/
/-- scheme S: 8-way column split of every expert -/
def Nc (Ne : Nat) : Nat := Ne / 8
/-- W8 bytes of one expert (what the effective rate counts) -/
def bX (K Ne : Nat) : Nat := K * Ne
/-- i8 A operand [16, K], per-token-quantized (errata 13), shared by every expert -/
def aCore (K : Nat) : Nat := 16 * K
/-- per-core column slice of one expert -/
def sliceB (K Ne : Nat) : Nat := K * Nc Ne
/-- (16,16,128) MMA calls per expert per core: no m parameter (one fragment covers t ≤ 16, Z5) -/
def callsX (K Ne : Nat) : Nat := (K / 128) * (Nc Ne / 16)
/-- loader bytes per core per step: the slice plus one A re-lift per expert -/
def loaderBytes (K Ne D : Nat) : Nat := D * (sliceB K Ne + aCore K)
/-- DDR bytes per die per step: weights, 8 × A, per-channel scales, 8 × descriptor, y -/
def ddrBytes (K Ne D t : Nat) : Nat := D * bX K Ne + 8 * aCore K + D * 4 * Ne + 8 * desc + t * Ne * 2

/-! ### Scheme S time model (§5.3, §8) -/
def tDdr (K Ne D t : Nat) : Nat := timeNs (ddrBytes K Ne D t) Measured.rDdr
/-- loader time at an arbitrary loader rate L (tenths of GB/s/core) — L is the unmeasured ping-pong quantity -/
def tLoadL (K Ne D L : Nat) : Nat := timeNs (loaderBytes K Ne D) L
def tLoad (K Ne D : Nat) : Nat := tLoadL K Ne D Measured.lSer
def tMma (K Ne D : Nat) : Nat := D * callsX K Ne * Measured.cMma
/-- per-call residual c (tenths of ns) — the derived c_res, kept as a parameter so theorems quantify over it -/
def tRes (K Ne D c : Nat) : Nat := D * callsX K Ne * c / 10
def tSerial (K Ne D c : Nat) : Nat := tLoad K Ne D + tMma K Ne D + tRes K Ne D c
/-- serial regime: the loader/MMA/residual chain, DDR underneath, plus the fixed cost F -/
def stepSer (K Ne D t c F : Nat) : Nat := max (tSerial K Ne D c) (tDdr K Ne D t) + F
/-- ping-pong regime: the three streams overlap; L = loader rate -/
def stepPP (K Ne D t L F : Nat) : Nat := max (tDdr K Ne D t) (max (tLoadL K Ne D L) (tMma K Ne D)) + F
def rateSer (K Ne D t c F : Nat) : Nat := rateT (D * bX K Ne) (stepSer K Ne D t c F)
def ratePP (K Ne D t L F : Nat) : Nat := rateT (D * bX K Ne) (stepPP K Ne D t L F)
/-- expert-group knob G (§5.6): one A lift per G experts -/
def tSerialG (K Ne D G c : Nat) : Nat := timeNs (D * (sliceB K Ne + aCore K / G)) Measured.lSer + tMma K Ne D + tRes K Ne D c
def stepSerG (K Ne D t G c F : Nat) : Nat := max (tSerialG K Ne D G c) (tDdr K Ne D t) + F
def rateSerG (K Ne D t G c F : Nat) : Nat := rateT (D * bX K Ne) (stepSerG K Ne D t G c F)
/-- A resident in L0A (16·K ≤ 48 KiB): one A lift per step instead of one per expert -/
def tSerialRes (K Ne D c : Nat) : Nat := timeNs (D * sliceB K Ne) Measured.lSer + timeNs (aCore K) Measured.lSer + tMma K Ne D + tRes K Ne D c
def rateSerRes (K Ne D t c F : Nat) : Nat := rateT (D * bX K Ne) (max (tSerialRes K Ne D c) (tDdr K Ne D t) + F)

/-! ### The anchor (constants table, c_res): the realized dense kernel decomposed -/
/-- loader bytes of the measured dense kernel per core: 8 MiB of B + 128 KiB of A, at 26.5 -/
def loaderDenseNs : Nat := timeNs (8 * MiB + 128 * KiB) Measured.lSer
/-- c_res (tenths of ns) = the part of T_dense not explained by loader bytes and 4096 MMA issues, per call -/
def cResOf (T : Nat) : Nat := (T - loaderDenseNs - 4096 * Measured.cMma) * 10 / 4096
def cResTenths : Nat := cResOf Measured.tDense
/-- the model's re-prediction of the dense per-core time with residual c -/
def denseModelNs (c : Nat) : Nat := loaderDenseNs + 4096 * Measured.cMma + 4096 * c / 10

/-! ### Scheme W-dyn (whole experts per core, round-robin per step) and W-static -/
def unitsW (D : Nat) : Nat := (D + 7) / 8
def tSerialW (K Ne D c : Nat) : Nat :=
  unitsW D * (K * Ne + aCore K) * 10 / Measured.lSer + unitsW D * (K / 128) * (Ne / 16) * (Measured.cMma * 10 + c) / 10
def tDdrCoreW (K Ne D : Nat) : Nat := (unitsW D * K * Ne + aCore K) * 80 / Measured.rDdr
def stepW (K Ne D t c : Nat) : Nat := max (tSerialW K Ne D c) (max (tDdrCoreW K Ne D) (tDdr K Ne D t)) + fixed
def rateW (K Ne D t c : Nat) : Nat := rateT (D * bX K Ne) (stepW K Ne D t c)
/-- W-dyn with two 2048-column C slabs (its 256 KiB slab is the errata-14 size): A lifted twice per expert -/
def tSerialW2 (K Ne D c : Nat) : Nat :=
  unitsW D * (K * Ne + 2 * aCore K) * 10 / Measured.lSer + unitsW D * (K / 128) * (Ne / 16) * (Measured.cMma * 10 + c) / 10
def rateW2 (K Ne D t c : Nat) : Nat := rateT (D * bX K Ne) (max (tSerialW2 K Ne D c) (max (tDdrCoreW K Ne D) (tDdr K Ne D t)) + fixed)
/-- W-static under family H_c: all D active experts on one core -/
def tSerialWstatic (K Ne D c : Nat) : Nat :=
  D * (K * Ne + aCore K) * 10 / Measured.lSer + D * (K / 128) * (Ne / 16) * (Measured.cMma * 10 + c) / 10
def stepWstatic (K Ne D _t c : Nat) : Nat := max (tSerialWstatic K Ne D c) ((D * K * Ne + aCore K) * 80 / Measured.rDdr) + fixed
def rateWstatic (K Ne D t c : Nat) : Nat := rateT (D * bX K Ne) (stepWstatic K Ne D t c)

/-! ### K-split hybrid (§1.2, Z8): K/8 rows of every expert per core, i32 partials reduced in a second launch -/
def chainK (K Ne c : Nat) : Nat := (K * Ne / 8 + 16 * (K / 8)) * 10 / Measured.lSer + callsX K Ne * (Measured.cMma * 10 + c) / 10
def deltaA (K Ne c : Nat) : Nat := tSerial K Ne 1 c - chainK K Ne c
/-- partials read back by the reduce launch: 8 cores × k·t routed rows × N_e × 4 B (the write rides under DDR slack: T_Z8_write_hidden) -/
def partialBytes (Ne k t : Nat) : Nat := 8 * k * t * Ne * 4
def stepKsplit (K Ne D t k c : Nat) : Nat := D * chainK K Ne c + fixed + Measured.tLaunch + timeNs (partialBytes Ne k t) Measured.rDdr
def rateKsplit (K Ne D t k c : Nat) : Nat := rateT (D * bX K Ne) (stepKsplit K Ne D t k c)

/-! ### W4 via i4×i4→i32 with nibble-split A and per-group drains (§8.4; the route is U, E19) -/
def b4X (K Ne : Nat) : Nat := K * Ne / 2
def ddrBytes4 (K Ne D t : Nat) : Nat := D * (b4X K Ne + (K / 128) * Ne * 4) + 8 * aCore K + 8 * desc + t * Ne * 2
def calls4 (K Ne : Nat) : Nat := 2 * callsX K Ne
def loaderBytes4 (K Ne D : Nat) : Nat := D * (sliceB K Ne / 2 + (K / 128) * Nc Ne * 4 + aCore K)
def tSerial4 (K Ne D c : Nat) : Nat := timeNs (loaderBytes4 K Ne D) Measured.lSer + D * calls4 K Ne * (Measured.cMma * 10 + c) / 10
def drainBytes4 (K Ne D : Nat) : Nat := D * (K / 128) * 16 * Nc Ne * 4
def step4 (K Ne D t c : Nat) : Nat := max (tSerial4 K Ne D c) (timeNs (ddrBytes4 K Ne D t) Measured.rDdr) + fixed
def rate4 (K Ne D t c : Nat) : Nat := rateT (D * b4X K Ne) (step4 K Ne D t c)
def drainNeed4 (K Ne D t c : Nat) : Nat := rateT (drainBytes4 K Ne D) (step4 K Ne D t c)
def stepPP4 (K Ne D t : Nat) : Nat := timeNs (ddrBytes4 K Ne D t) Measured.rDdr + fixed

/-! ### Dispatch and epilogue (§3, §4) -/
/-- scalar scan: t·k iterations at σ_d ns each (σ_d is U) -/
def scanNs (t k σ : Nat) : Nat := t * k * σ
def laneNs (ops : Nat) : Nat := ops * 10 / Measured.rVec
/-- per-step vector epilogue: one 16-row Sub per expert (8192 lanes) + 4 ops × 512 lanes per routed pair -/
def epilogueNs (D kt : Nat) : Nat := D * 8192 * 10 / Measured.rVec + kt * 2048 * 10 / Measured.rVec

/-! ### Pack geometry (§2.1, P1): offset of (k, n') inside the per-core slice of one expert -/
namespace Pack
def off (Nc k n' : Nat) : Nat :=
  (k / 128) * (128 * Nc) + (n' / 16) * 2048 + ((k % 128) / 32) * 512 + (n' % 16) * 32 + k % 32
def invK (Nc o : Nat) : Nat := 128 * (o / (128 * Nc)) + 32 * ((o % 2048) / 512) + o % 32
def invN (Nc o : Nat) : Nat := 16 * ((o % (128 * Nc)) / 2048) + (o % 512) / 32
end Pack

/-! ### Column-slice bijection (§1.2, Z2): column n of an expert belongs to core n / N_c -/
namespace Slice
/-- number of columns n < N that core c owns -/
def colsOn (Nc c : Nat) : Nat → Nat
  | 0 => 0
  | N + 1 => colsOn Nc c N + (if N / Nc = c then 1 else 0)
end Slice

/-! ### Routing outcomes (§7.1, §7.2): ω = {m_e}, one entry per expert id, m_e = tokens routed to e -/
namespace Routing
def act (m : Nat) : Nat := if m = 0 then 0 else 1
/-- D = number of distinct active experts -/
def D : List Nat → Nat
  | [] => 0
  | m :: ms => act m + D ms
/-- Σ_e m_e = number of routed (token, expert) pairs = k·t -/
def pairs : List Nat → Nat
  | [] => 0
  | m :: ms => m + pairs ms
/-- every m_e ≤ t -/
def bounded (t : Nat) : List Nat → Prop
  | [] => True
  | m :: ms => m ≤ t ∧ bounded t ms
/-- every (τ, e) pair distinct: m_e ≤ 1 -/
def distinctPairs : List Nat → Prop
  | [] => True
  | m :: ms => m ≤ 1 ∧ distinctPairs ms
/-- scheme S weight bytes streamed by core c: K rows × (the columns of each active expert that core c owns) -/
def coreWeightS (K Nc c : Nat) : List Nat → Nat
  | [] => 0
  | m :: ms => act m * (K * Slice.colsOn Nc c (8 * Nc)) + coreWeightS K Nc c ms
/-- step weight bytes: Σ_{e active} K·N_e -/
def stepWeight (K Ne : Nat) : List Nat → Nat
  | [] => 0
  | m :: ms => act m * (K * Ne) + stepWeight K Ne ms
/-- separate (token, expert) passes: Σ_e m_e·K·N_e -/
def separateWeight (K Ne : Nat) : List Nat → Nat
  | [] => 0
  | m :: ms => m * (K * Ne) + separateWeight K Ne ms
/-- full per-core bytes of scheme S (Z2): weights + A + scale slice per expert + descriptor + y slice -/
def coreBytesS (K Nc c t : Nat) (ω : List Nat) : Nat :=
  coreWeightS K Nc c ω + 16 * K + D ω * 4 * Nc + desc + t * 2 * Nc
/-- W-dyn round robin: the d-th active expert goes to core d mod 8; experts on core c among the first D -/
def countRR : Nat → Nat → Nat
  | 0, _ => 0
  | D + 1, c => countRR D c + (if D % 8 = c then 1 else 0)
end Routing

/-! ### i32 accumulator semantics (§3.2, P2/P3) -/
namespace Accum
/-- 32-bit wraparound: representative in [0, 2³²) -/
def wrap (x : Int) : Int := x % 4294967296
/-- the signed reading of a 32-bit pattern -/
def signed (w : Int) : Int := if w < 2147483648 then w else w - 4294967296
def sumI : List Int → Int
  | [] => 0
  | x :: xs => x + sumI xs
def prods : List (Int × Int) → List Int
  | [] => []
  | (a, b) :: ps => a * b :: prods ps
/-- the stated operand bounds: |a|, |b| ≤ 127 (the quantizer never emits −128; see T_overflow_m128) -/
def opBounded : List (Int × Int) → Prop
  | [] => True
  | (a, b) :: ps => (-127 ≤ a ∧ a ≤ 127 ∧ -127 ≤ b ∧ b ≤ 127) ∧ opBounded ps
/-- every per-expert sum in a region's history is bounded by M -/
def eachBounded (M : Int) : List Int → Prop
  | [] => True
  | s :: ss => (-M ≤ s ∧ s ≤ M) ∧ eachBounded M ss
end Accum

end Design

namespace Proofs
open Measured Design

/-! ## T0 — constants table rows re-checked (HW-MAP inputs and their derived lines) -/

/-- headline: K = N_e = 4096, k = 8 → N_c = 512, 8 × 16 MiB = 128 MiB = 134.22 MB of weights per step -/
theorem T0_headline : Nc 4096 = 512 ∧ 8 * bX 4096 4096 = 128 * MiB ∧ 128 * MiB = 134217728 ∧ bX 4096 4096 = 16 * MiB := by decide
/-- 173.8/8 = 21.725 GB/s/core (21.7 remainder 2 tenths); 180/8 = 22.5 -/
theorem T0_per_core_rates : rDdr / 8 = 217 ∧ rDdr % 8 = 2 ∧ rStage / 8 = 225 := by decide
/-- 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core -/
theorem T0_rvec : 40 * 108 / 10 = rVec := by decide
/-- S1 ~1 MB = 976 KiB; US evidenced 208 KiB -/
theorem T0_s1_us : s1P / KiB = 976 ∧ usEvidenced = 212992 := by decide
/-- the MMA consumes 2 KiB of B per 15 ns call = 136.5 GB/s/core if fed -/
theorem T0_mma_feed : 2048 * 10 / cMma = 1365 := by decide
/-- the anchor row is self-consistent: 64 MiB per die in 487 µs per core = 137.8 GB/s; its MMA occupancy 4096 × 15 / 487 000 = 12.6 % (HW-MAP quotes 12.5) -/
theorem T0_dense_row : rateT (64 * MiB) tDense = rDense ∧ pct (4096 * cMma) tDense = 126 := by decide
/-- the vendor floor and the gate: 24.6 and 120 -/
theorem T0_floor_gate : rVendor = 246 ∧ 1200 / rVendor = 4 ∧ 1200 * 10 / rVendor = 48 := by decide

/-! ## T_anchor — the c_res subtraction identity (constants table, [M0], Appendix rows 1–2) -/

/-- loader time of the dense kernel's bytes: (8 MiB + 128 KiB) × 10 / 265 = 321 497 ns -/
theorem T_anchor_loader : loaderDenseNs = 321497 ∧ 4096 * cMma = 61440 := by decide
/-- c_res = (487 000 − 321 497 − 61 440) × 10 / 4096 = 254 tenths = 25.4 ns -/
theorem T_anchor_cres : cResTenths = 254 := by decide
/-- the decomposition re-predicts the dense per-core time to 486 975 ns, 25 ns (< one tenth-ns per call) under the measured 487 000 -/
theorem T_anchor_model : denseModelNs cResTenths = 486975 ∧ tDense - denseModelNs cResTenths = 25 ∧ tDense - denseModelNs cResTenths < 410 := by decide
/-- …and re-predicts the measured 137.8 GB/s exactly -/
theorem T_anchor_dense : rateT (64 * MiB) (denseModelNs cResTenths) = rDense := by decide
/-- the identity holds for ANY per-core time T ≥ loader + MMA: the derived residual reproduces T to within 410 ns (one tenth-ns per call, floored twice) -/
theorem T_anchor_identity (T : Nat) (h : loaderDenseNs + 4096 * cMma ≤ T) :
    denseModelNs (cResOf T) ≤ T ∧ T - denseModelNs (cResOf T) ≤ 410 := by
  unfold denseModelNs cResOf loaderDenseNs timeNs MiB KiB lSer cMma at *; omega
/-- the headline 135.3 follows from c_res = 25.4 at K = N_e = 4096, k = 8, t = 1 -/
theorem T_anchor_headline : rateSer 4096 4096 8 1 cResTenths fixed = 1353 := by decide
/-- re-anchoring sensitivity: with c_res ± 0.1 ns the headline moves by 0.1 (135.4 / 135.2) -/
theorem T_anchor_sensitivity : rateSer 4096 4096 8 1 253 fixed = 1354 ∧ rateSer 4096 4096 8 1 255 fixed = 1352 := by decide

/-! ## T1 — the headline cells (§Summary, §3.3, §5.1, [M1]; Appendix rows 3–8) -/

/-- DDR bytes per die = 134 889 472 = 128 MiB (W) + 512 KiB (8 A) + 128 KiB (scales) + 8 KiB (desc) + 8 KiB (y) -/
theorem T1_ddr_bytes : ddrBytes 4096 4096 8 1 = 134889472 ∧ 8 * bX 4096 4096 = 134217728 ∧ 8 * aCore 4096 = 524288 ∧
    8 * 4 * 4096 = 131072 ∧ 8 * desc = 8192 ∧ 1 * 4096 * 2 = 8192 := by decide
/-- the overhead over pure weights is 0.64 MiB (0.5 %); the DDR-bound ceiling before F is 172.9 -/
theorem T1_overhead : 8 * aCore 4096 + 8 * 4 * 4096 + 8 * desc + 2 * 4096 = 671744 ∧ 671744 * 100 / MiB = 64 ∧
    pct 671744 (128 * MiB) = 5 ∧ rateT (128 * MiB) (tDdr 4096 4096 8 1) = 1729 := by decide
/-- tDdr 776 118 / tLoad 652 886 / tMma 122 880 / tRes 208 076 ns; loader bytes per core 16.5 MiB; 8192 calls per core -/
theorem T1_times : tDdr 4096 4096 8 1 = 776118 ∧ loaderBytes 4096 4096 8 = 17301504 ∧ loaderBytes 4096 4096 8 = 16 * MiB + 512 * KiB ∧
    tLoad 4096 4096 8 = 652886 ∧ callsX 4096 4096 = 1024 ∧ 8 * callsX 4096 4096 = 8192 ∧ tMma 4096 4096 8 = 122880 ∧
    tRes 4096 4096 8 254 = 208076 := by decide
/-- serial chain 983 842 ns > DDR 776 118: the chain is the critical path; step 991 842 ns = 991.8 µs → 135.3 GB/s -/
theorem T1_serial : tSerial 4096 4096 8 254 = 983842 ∧ 776118 < 983842 ∧ stepSer 4096 4096 8 1 254 fixed = 991842 ∧
    usT 991842 = 9918 ∧ usR 991842 = 992 ∧ rateSer 4096 4096 8 1 254 fixed = 1353 := by decide
/-- the Summary table's one-decimal µs cells: 652.9 / 122.9 / 208.1 / 983.8 / 776.1 -/
theorem T1_us_cells : usT 652886 = 6529 ∧ usT 122880 = 1229 ∧ usT 208076 = 2081 ∧ usT 983842 = 9838 ∧ usT 776118 = 7761 := by decide
/-- ping-pong: max(776.1, 652.9, 122.9) + 8 = 784.1 µs → 171.2 GB/s -/
theorem T1_pp : stepPP 4096 4096 8 1 lSer fixed = 784118 ∧ usT 784118 = 7841 ∧ ratePP 4096 4096 8 1 lSer fixed = 1712 := by decide
/-- wall clock with an unpipelined 91 µs launch: 1082.8 / 875.1 µs → 123.9 / 153.4 -/
theorem T1_wall : rateT (128 * MiB) (991842 + tLaunch) = 1239 ∧ rateT (128 * MiB) (784118 + tLaunch) = 1534 ∧
    usT (991842 + tLaunch) = 10828 ∧ usT (784118 + tLaunch) = 8751 := by decide
/-- gate met at 113 % (112.8); vendor floor beaten 5.5×; MMA occupancy 15.8 % of tDdr; loader share 84.1 % -/
theorem T1_ratios : pct 1353 1200 = 1128 ∧ 1353 * 10 / rVendor = 55 ∧ pct 122880 776118 = 158 ∧ pct 652886 776118 = 841 := by decide
/-- W-dyn in the ping-pong regime is the same DDR bound: its loader (16 MiB + 64 KiB)/26.5 = 635 575 < 776 118 -/
theorem T1_pp_wdyn_same : timeNs (16 * MiB + 64 * KiB) lSer = 635575 ∧ max 776118 (max 635575 122880) + fixed = 784118 := by decide
/-- the E11 fallback: ⌈8/6⌉ = 2 launches per step → 123.9 ("124"); W-dyn needs one region per core at D ≤ 8 and stays 137.7 -/
theorem T1_fallback_two_launches : ceilDiv 8 6 = 2 ∧ rateT (128 * MiB) (stepSer 4096 4096 8 1 254 fixed + tLaunch) = 1239 ∧
    rateW 4096 4096 8 1 254 = 1377 := by decide

/-! ## T_pp_thresh — ping-pong regime, universally quantified over the loader rate L (tenths of GB/s/core) (§5.3, §8.2, [M3], Appendix 9, 31) -/

/-- DDR-bound iff L ≥ 22.3 GB/s/core: loader bytes 17 301 504 × 10 / L ≤ 776 118 ⟺ L ≥ 223 -/
theorem T_pp_thresh (L : Nat) (hL : 0 < L) : tLoadL 4096 4096 8 L ≤ tDdr 4096 4096 8 1 ↔ 223 ≤ L := by
  have h : tLoadL 4096 4096 8 L = 173015040 / L := rfl
  have h2 : tDdr 4096 4096 8 1 = 776118 := by decide
  rw [h, h2, ← Nat.lt_add_one_iff, Nat.div_lt_iff_lt_mul hL]; omega
/-- the threshold value itself: 17 301 504 × 10 / 776 118 = 222.9 → first DDR-bound tenth 22.3; measured 26.5 is 16 % above -/
theorem T_pp_thresh_value : loaderBytes 4096 4096 8 * 10 / 776118 = 222 ∧ ceilDiv (loaderBytes 4096 4096 8 * 10) 776118 = 223 ∧
    223 ≤ lSer ∧ pct (lSer - 223) lSer = 158 := by decide
/-- for every L ≥ 22.3 the step is 784 118 ns and the rate 171.2 -/
theorem T_pp_rate_ddr_bound (L : Nat) (h : 223 ≤ L) : stepPP 4096 4096 8 1 L fixed = 784118 ∧ ratePP 4096 4096 8 1 L fixed = 1712 := by
  have hq : 173015040 / L ≤ 776118 := by
    rw [← Nat.lt_add_one_iff, Nat.div_lt_iff_lt_mul (by omega)]; omega
  have hs : stepPP 4096 4096 8 1 L fixed = 784118 := by
    simp only [stepPP, tLoadL, timeNs, loaderBytes, sliceB, aCore, Nc, tDdr, ddrBytes, bX, desc, tMma, callsX, fixed, rDdr, cMma,
      Nat.reduceMul, Nat.reduceDiv, Nat.reduceAdd]
    omega
  refine ⟨hs, ?_⟩
  unfold ratePP; rw [hs]; decide
/-- for every 0 < L ≤ 22.2 the design is loader-bound: step = 17 301 504 × 10 / L + 8 000 -/
theorem T_pp_rate_loader_bound (L : Nat) (h0 : 0 < L) (h : L ≤ 222) : stepPP 4096 4096 8 1 L fixed = 173015040 / L + 8000 := by
  have hq : 776118 < 173015040 / L := by
    have : 173015040 / L < 776119 ↔ 173015040 < 776119 * L := Nat.div_lt_iff_lt_mul h0
    omega
  simp only [stepPP, tLoadL, timeNs, loaderBytes, sliceB, aCore, Nc, tDdr, ddrBytes, bX, desc, tMma, callsX, fixed, rDdr, cMma,
    Nat.reduceMul, Nat.reduceDiv, Nat.reduceAdd]
  omega
/-- helper: the ping-pong rate meets 120 iff the loader term q ≤ 1 110 947 ns -/
theorem T_pp_target_core (q : Nat) : 1200 ≤ rateT 134217728 (max 776118 (max q 122880) + 8000) ↔ q ≤ 1110947 := by
  unfold rateT; rw [Nat.le_div_iff_mul_le (by omega)]; omega
/-- target 120 in the ping-pong regime iff L ≥ 15.6 GB/s/core (§10.1 "still > 120 for L ≥ 15.6") -/
theorem T_pp_target (L : Nat) (hL : 0 < L) : 1200 ≤ ratePP 4096 4096 8 1 L fixed ↔ 156 ≤ L := by
  have hq : 173015040 / L ≤ 1110947 ↔ 156 ≤ L := by
    rw [← Nat.lt_add_one_iff, Nat.div_lt_iff_lt_mul hL]; omega
  have hs : ratePP 4096 4096 8 1 L fixed = rateT 134217728 (max 776118 (max (173015040 / L) 122880) + 8000) := rfl
  rw [hs]; exact (T_pp_target_core _).trans hq
/-- §8.2 loader row: 15.0 → 115.6, 20.0 → 153.7, 22.0 → 168.9, 22.2 → 170.5, ≥ 22.3 → 171.2; 15.5 → 119.4, 15.6 → 120.2 -/
theorem T_pp_rows : ratePP 4096 4096 8 1 150 fixed = 1156 ∧ ratePP 4096 4096 8 1 200 fixed = 1537 ∧ ratePP 4096 4096 8 1 220 fixed = 1689 ∧
    ratePP 4096 4096 8 1 222 fixed = 1705 ∧ ratePP 4096 4096 8 1 223 fixed = 1712 ∧ ratePP 4096 4096 8 1 155 fixed = 1194 ∧
    ratePP 4096 4096 8 1 156 fixed = 1202 := by decide
/-- MMA + residual (330 956 ns) ≤ tDdr: the matrix unit is off the critical path in both regimes; dense threshold was 21.8 -/
theorem T_pp_margins : tMma 4096 4096 8 + tRes 4096 4096 8 254 = 330956 ∧ 330956 ≤ 776118 ∧ 122880 ≤ 776118 ∧ 218 < 223 := by decide

/-! ## T_cres — the residual as a universally quantified quantity (§8.2, [M2], [M24]; Appendix 32) -/

/-- the serial chain at the headline as a linear function of the residual c (tenths of ns) -/
theorem T_cres_chain (c : Nat) : tSerial 4096 4096 8 c = 775766 + 8192 * c / 10 := by
  simp only [tSerial, tLoad, tLoadL, timeNs, loaderBytes, sliceB, aCore, Nc, tMma, tRes, callsX, lSer, cMma,
    Nat.reduceMul, Nat.reduceDiv, Nat.reduceAdd]
/-- at c = 0 the chain (775 766) is 352 ns under the DDR time: a zero-overhead serial chain is DDR-paced (171.2); for every c ≥ 0.1 ns it is chain-bound -/
theorem T_cres_regimes (c : Nat) : (stepSer 4096 4096 8 1 0 fixed = 776118 + fixed) ∧ (1 ≤ c → stepSer 4096 4096 8 1 c fixed = tSerial 4096 4096 8 c + fixed) := by
  constructor
  · decide
  · intro h; unfold stepSer; rw [T_cres_chain]; have : tDdr 4096 4096 8 1 = 776118 := by decide
    rw [this]; omega
/-- §8.2 c_res row, in ns: 0 → 171.2, 5 → 162.7, 10 → 155.0, 15 → 148.0, 20 → 141.6, 25.4 → 135.3, 30 → 130.4
    (PROVER-FORCED: the text labelled the first five cells 0/50/100/150/200, which are moe.py's tenths; 50 ns would give 112.5) -/
theorem T_cres_rows : rateSer 4096 4096 8 1 0 fixed = 1712 ∧ rateSer 4096 4096 8 1 50 fixed = 1627 ∧ rateSer 4096 4096 8 1 100 fixed = 1550 ∧
    rateSer 4096 4096 8 1 150 fixed = 1480 ∧ rateSer 4096 4096 8 1 200 fixed = 1416 ∧ rateSer 4096 4096 8 1 254 fixed = 1353 ∧
    rateSer 4096 4096 8 1 300 fixed = 1304 ∧ rateSer 4096 4096 8 1 500 fixed = 1125 := by decide
/-- for EVERY residual the serial rate is ≤ 171.2 (the DDR bound) -/
theorem T_cres_upper (c : Nat) : rateSer 4096 4096 8 1 c fixed ≤ 1712 := by
  have hs : 784118 ≤ stepSer 4096 4096 8 1 c fixed := by
    unfold stepSer; rw [T_cres_chain]; have : tDdr 4096 4096 8 1 = 776118 := by decide
    rw [this]; unfold fixed; omega
  unfold rateSer
  have h2 : rateT (8 * bX 4096 4096) (stepSer 4096 4096 8 1 c fixed) < 1713 := by
    unfold rateT; rw [Nat.div_lt_iff_lt_mul (by omega)]; unfold bX; omega
  omega
/-- the gate 120 is met in the serial regime iff c_res ≤ 40.9 ns (for every c) -/
theorem T_cres_target (c : Nat) : 1200 ≤ rateSer 4096 4096 8 1 c fixed ↔ c ≤ 409 := by
  unfold rateSer stepSer; rw [T_cres_chain]; have : tDdr 4096 4096 8 1 = 776118 := by decide
  rw [this]; unfold rateT bX fixed; rw [Nat.le_div_iff_mul_le (by omega)]; omega
/-- §8.2 F row: 0 → 136.4, 8 → 135.3, 20 → 133.7 µs -/
theorem T_cres_F_rows : rateSer 4096 4096 8 1 254 0 = 1364 ∧ rateSer 4096 4096 8 1 254 8000 = 1353 ∧ rateSer 4096 4096 8 1 254 20000 = 1337 := by decide

/-! ## T_piece — per-16-KiB-piece and per-expert timing (§5.3, [M4], [M15]; Appendix 10–11) -/

/-- per piece: loader 618, 8 MMA 120, DDR share 754, residual 203 → serial 941 ns = 17.4 GB/s/core of B; ping-pong hides it iff barriers ≤ 136 ns -/
theorem T_piece : timeNs 16384 lSer = 618 ∧ 8 * cMma = 120 ∧ 16384 * 80 / rDdr = 754 ∧ 8 * 254 / 10 = 203 ∧ 618 + 120 + 203 = 941 ∧
    16384 * 10 / 941 = 174 ∧ 754 - 618 = 136 := by decide
/-- per expert per core: (2 MiB + 64 KiB)/26.5 = 81 610 + 1024 × 40.4 = 41 369 → 122 979 ns = 123.0 µs, vs 96 531 ns of DDR share -/
theorem T_piece_expert : timeNs (2 * MiB + 64 * KiB) lSer = 81610 ∧ 1024 * (cMma * 10 + 254) / 10 = 41369 ∧ tSerial 4096 4096 1 254 = 122979 ∧
    usT 122979 = 1230 ∧ sliceB 4096 4096 * 80 / rDdr = 96531 ∧ usT 96531 = 965 := by decide
/-- the per-expert DDR slope (16 MiB + 16 KiB)/173.8 = 96 626 ns and the D-independent part 3 110 ns at t = 1 (Appendix row 11) -/
theorem T_piece_slope : timeNs (bX 4096 4096 + 4 * 4096) rDdr = 96626 ∧ timeNs (8 * aCore 4096 + 8 * desc + 2 * 4096) rDdr = 3110 := by decide
/-- chunk and copy sizes: 64 KiB chunk = 128 rows × 512 B = one errata-2-maximal COPY; 32 copies per 2 MiB slice; 2.9 µs for the 64 KiB A copy at 22.5 -/
theorem T_piece_sizes : 128 * Nc 4096 = 64 * KiB ∧ sliceB 4096 4096 / (64 * KiB) = 32 ∧ aCore 4096 = 64 * KiB ∧ aCore 7168 = 112 * KiB ∧
    64 * KiB * 10 / (rStage / 8) = 2912 ∧ 64 * KiB * 80 / rDdr = 3016 ∧ 2 * 2912 = 5824 ∧ 2 * 3016 = 6032 ∧ usT 5824 = 58 ∧ usT 6032 = 60 := by decide

/-! ## T_bytes_eighth — per-core bytes = step bytes / 8 for EVERY routing outcome (§1.2, §7.2 Z2; Appendix row 3) -/

/-- column-slice bijection, N_c ∈ {64, 128, 256, 512}: n ↦ (n / N_c, n % N_c) maps [0, 8·N_c) onto [0, 8) × [0, N_c) with inverse (c, n') ↦ c·N_c + n' -/
theorem T_slice_bijection (Nc n c n' : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hn : n < 8 * Nc) (hn' : n' < Nc) :
    n / Nc < 8 ∧ n % Nc < Nc ∧ (n / Nc) * Nc + n % Nc = n ∧ (c * Nc + n') / Nc = c ∧ (c * Nc + n') % Nc = n' := by
  rcases hN with h | h | h | h <;> subst h <;> omega
/-- closed form of the column count a core owns among the first N columns (N_c ∈ {64, 128, 256, 512}) -/
theorem T_slice_cols_closed (Nc c N : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) :
    Slice.colsOn Nc c N = (if N ≤ c * Nc then 0 else if (c + 1) * Nc ≤ N then Nc else N - c * Nc) := by
  induction N with
  | zero => simp [Slice.colsOn]
  | succ n ih =>
    simp only [Slice.colsOn]; rw [ih]
    rcases hN with h | h | h | h <;> subst h <;> split <;> (try split) <;> (try split) <;> (try split) <;> (try split) <;> (try split) <;> omega
/-- every core c < 8 owns exactly N_c of the N_e = 8·N_c columns of every expert (the sum identity Σ_c N_c = N_e) -/
theorem T_slice_cols_per_core (Nc c : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hc : c < 8) : Slice.colsOn Nc c (8 * Nc) = Nc := by
  rw [T_slice_cols_closed Nc c (8 * Nc) hN]
  have _hc := hc
  rcases hN with h | h | h | h <;> subst h <;> split <;> (try split) <;> omega
/-- scheme S weight bytes on core c = D·K·N_c for every core and every outcome ω (no c, no m_e in the result) -/
theorem T_bytes_core (K Nc c : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hc : c < 8) (ω : List Nat) :
    Routing.coreWeightS K Nc c ω = Routing.D ω * (K * Nc) := by
  induction ω with
  | nil => simp [Routing.coreWeightS, Routing.D]
  | cons m ms ih =>
    simp only [Routing.coreWeightS, Routing.D]; rw [ih, T_slice_cols_per_core Nc c hN hc]; simp only [Nat.add_mul]
/-- step weight bytes = D·K·N_e -/
theorem T_bytes_step (K Ne : Nat) (ω : List Nat) : Routing.stepWeight K Ne ω = Routing.D ω * (K * Ne) := by
  induction ω with
  | nil => simp [Routing.stepWeight, Routing.D]
  | cons m ms ih => simp only [Routing.stepWeight, Routing.D]; rw [ih]; simp only [Nat.add_mul]
/-- THE SKEW-IMMUNITY CORE: 8 × (core c's weight bytes) = step weight bytes, hence core bytes = step bytes / 8, for every c and every ω -/
theorem T_bytes_eighth (K Nc c : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hc : c < 8) (ω : List Nat) :
    8 * Routing.coreWeightS K Nc c ω = Routing.stepWeight K (8 * Nc) ω ∧ Routing.coreWeightS K Nc c ω = Routing.stepWeight K (8 * Nc) ω / 8 := by
  rw [T_bytes_core K Nc c hN hc ω, T_bytes_step]
  have h1 : 8 * (Routing.D ω * (K * Nc)) = Routing.D ω * (K * (8 * Nc)) := by
    simp only [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm]
  exact ⟨h1, by omega⟩
/-- any two cores stream identical bytes under scheme S -/
theorem T_bytes_balanced (K Nc c c' : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hc : c < 8) (hc' : c' < 8) (ω : List Nat) :
    Routing.coreWeightS K Nc c ω = Routing.coreWeightS K Nc c' ω := by
  rw [T_bytes_core K Nc c hN hc ω, T_bytes_core K Nc c' hN hc' ω]
/-- Z2 in full: 8 × (per-core bytes incl. A, scale slice, descriptor, y slice) = the die's ddrBytes, for every ω, c, t -/
theorem T_bytes_eighth_full (K Nc c t : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hc : c < 8) (ω : List Nat) :
    8 * Routing.coreBytesS K Nc c t ω = ddrBytes K (8 * Nc) (Routing.D ω) t := by
  unfold Routing.coreBytesS ddrBytes bX aCore desc
  rw [T_bytes_core K Nc c hN hc ω]
  rcases hN with h | h | h | h <;> subst h <;> simp only [Nat.reduceMul, ← Nat.mul_assoc] <;> omega
/-- the headline instance: core bytes 16 861 184 = 8 × 2 MiB + 64 KiB + 8 × 2 KiB + 1 KiB + 1 KiB; × 8 = 134 889 472 -/
theorem T_bytes_headline : 8 * (2 * MiB) + 64 * KiB + 8 * 2 * KiB + KiB + KiB = 16861184 ∧ 8 * 16861184 = ddrBytes 4096 4096 8 1 ∧
    4 * Nc 4096 = 2 * KiB ∧ 2 * Nc 4096 = KiB := by decide

/-! ## T_skew_D — the skew theorems over D (§7.2, §7.3; Appendix rows 11–16) -/

/-- Z1 (bounds): D ≤ E (list length), D ≤ Σ m_e = k·t, and k·t ≤ t·D when every m_e ≤ t -/
theorem T_Z1_D_le_E (ω : List Nat) : Routing.D ω ≤ ω.length := by
  induction ω with
  | nil => simp [Routing.D]
  | cons m ms ih => simp only [Routing.D, Routing.act, List.length_cons]; split <;> omega
theorem T_Z1_D_le_pairs (ω : List Nat) : Routing.D ω ≤ Routing.pairs ω := by
  induction ω with
  | nil => simp [Routing.D, Routing.pairs]
  | cons m ms ih => simp only [Routing.D, Routing.pairs, Routing.act]; split <;> omega
theorem T_Z1_pairs_le (t : Nat) (ω : List Nat) (h : Routing.bounded t ω) : Routing.pairs ω ≤ t * Routing.D ω := by
  induction ω with
  | nil => simp [Routing.D, Routing.pairs]
  | cons m ms ih =>
    simp only [Routing.bounded] at h
    simp only [Routing.D, Routing.pairs, Routing.act]
    have := ih h.2
    split <;> simp only [Nat.mul_add, Nat.mul_zero, Nat.mul_one] <;> omega
/-- Z1 assembled: Σ m_e = k·t, m_e ≤ t, t ≥ 1 ⇒ k ≤ D ≤ min(k·t, E) -/
theorem T_Z1_bounds (k t : Nat) (ω : List Nat) (ht : 0 < t) (hk : Routing.pairs ω = k * t) (hb : Routing.bounded t ω) :
    k ≤ Routing.D ω ∧ Routing.D ω ≤ k * t ∧ Routing.D ω ≤ ω.length := by
  refine ⟨?_, ?_, T_Z1_D_le_E ω⟩
  · have h1 := T_Z1_pairs_le t ω hb
    have h2 : k * t ≤ Routing.D ω * t := by rw [Nat.mul_comm (Routing.D ω) t]; omega
    exact Nat.le_of_mul_le_mul_right h2 ht
  · have := T_Z1_D_le_pairs ω; omega
/-- Z5: t ≤ 16 ⇒ every m_e ≤ 16 ⇒ one 16-row fragment per expert; calls per expert are (K/128)(N_c/16), no m parameter -/
theorem T_Z5_one_fragment (m : Nat) (h1 : 1 ≤ m) (h2 : m ≤ 16) : (m + 15) / 16 = 1 := by omega
/-- Z6: separate passes stream Σ m_e slabs ≥ D slabs; equality iff every (τ, e) pair is distinct (m_e ≤ 1) -/
theorem T_Z6_separate (K Ne : Nat) (ω : List Nat) : Routing.separateWeight K Ne ω = Routing.pairs ω * (K * Ne) := by
  induction ω with
  | nil => simp [Routing.separateWeight, Routing.pairs]
  | cons m ms ih => simp only [Routing.separateWeight, Routing.pairs]; rw [ih]; simp only [Nat.add_mul]
theorem T_Z6_batching_never_worse (K Ne : Nat) (ω : List Nat) : Routing.stepWeight K Ne ω ≤ Routing.separateWeight K Ne ω := by
  rw [T_Z6_separate, T_bytes_step]; exact Nat.mul_le_mul_right _ (T_Z1_D_le_pairs ω)
theorem T_Z6_equality_iff (ω : List Nat) : Routing.pairs ω = Routing.D ω ↔ Routing.distinctPairs ω := by
  induction ω with
  | nil => simp [Routing.pairs, Routing.D, Routing.distinctPairs]
  | cons m ms ih =>
    simp only [Routing.pairs, Routing.D, Routing.act, Routing.distinctPairs]
    have := T_Z1_D_le_pairs ms
    constructor
    · intro h; split at h <;> (constructor <;> first | omega | (apply ih.mp; omega))
    · intro ⟨h1, h2⟩; have := ih.mpr h2; split <;> omega
/-- under single-hot routing H (k experts each with m_e = t, the rest 0): D = k, Σ m_e = k·t, the ratio is t -/
theorem T_Z6_single_hot_D (k t : Nat) (ht : 0 < t) : Routing.D (List.replicate k t) = k := by
  induction k with
  | zero => simp [Routing.D]
  | succ n ih => simp only [List.replicate, Routing.D, Routing.act]; rw [ih]; split <;> omega
theorem T_Z6_single_hot_pairs (k t : Nat) : Routing.pairs (List.replicate k t) = k * t := by
  induction k with
  | zero => simp [Routing.pairs]
  | succ n ih => simp only [List.replicate, Routing.pairs]; rw [ih, Nat.succ_mul]; omega
/-- D and Σ m_e are additive over concatenation; idle experts (m_e = 0) contribute nothing to either -/
theorem T_Z6_D_append (l₁ l₂ : List Nat) : Routing.D (l₁ ++ l₂) = Routing.D l₁ + Routing.D l₂ := by
  induction l₁ with
  | nil => simp [Routing.D]
  | cons m ms ih => simp only [List.cons_append, Routing.D]; rw [ih]; omega
theorem T_Z6_pairs_append (l₁ l₂ : List Nat) : Routing.pairs (l₁ ++ l₂) = Routing.pairs l₁ + Routing.pairs l₂ := by
  induction l₁ with
  | nil => simp [Routing.pairs]
  | cons m ms ih => simp only [List.cons_append, Routing.pairs]; rw [ih]; omega
theorem T_Z6_idle_D (n : Nat) : Routing.D (List.replicate n 0) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp only [List.replicate, Routing.D]; rw [ih]; decide
theorem T_Z6_idle_pairs (n : Nat) : Routing.pairs (List.replicate n 0) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp only [List.replicate, Routing.pairs]; rw [ih]
/-- the idle experts (m_e = 0) change neither D nor Σ m_e: the single-hot outcome H with E experts is (replicate k t ++ replicate (E − k) 0) -/
theorem T_Z6_idle_experts (ω : List Nat) (n : Nat) : Routing.D (ω ++ List.replicate n 0) = Routing.D ω ∧ Routing.pairs (ω ++ List.replicate n 0) = Routing.pairs ω := by
  rw [T_Z6_D_append, T_Z6_pairs_append, T_Z6_idle_D, T_Z6_idle_pairs]; omega

/-- the headline-shaped chain as an explicit function of D and c (the generic model at K = N_e = 4096) -/
theorem T_Z3_chain_form (D c : Nat) : tSerial 4096 4096 D c = D * 2162688 * 10 / 265 + D * 1024 * 15 + D * 1024 * c / 10 := by
  simp only [tSerial, tLoad, tLoadL, timeNs, loaderBytes, sliceB, aCore, Nc, tMma, tRes, callsX, lSer, cMma,
    Nat.reduceMul, Nat.reduceDiv, Nat.reduceAdd]
theorem T_Z3_ddr_form (D t : Nat) : tDdr 4096 4096 D t = (D * 16777216 + 524288 + D * 4 * 4096 + 8192 + t * 4096 * 2) * 10 / 1738 := by
  simp only [tDdr, timeNs, ddrBytes, bX, aCore, desc, rDdr, Nat.reduceMul]
/-- Z3: the chain dominates DDR for every D ≥ 1 and t ≤ 16, with ≥ 22 536 ns of slack (the minimum, at D = 1, t = 16) -/
theorem T_Z3_chain_dominates (D t : Nat) (hD : 1 ≤ D) (ht : t ≤ 16) : tDdr 4096 4096 D t + 22536 ≤ tSerial 4096 4096 D 254 := by
  rcases Nat.lt_or_ge D 2 with h | h
  · -- D = 1: the bound is exact at t = 16, so it is checked cell by cell
    have h1 : D = 1 := by omega
    have key : ∀ t, t < 17 → tDdr 4096 4096 1 t + 22536 ≤ tSerial 4096 4096 1 254 := by decide
    subst h1; exact key t (by omega)
  · rw [T_Z3_chain_form, T_Z3_ddr_form]; omega
theorem T_Z3_slack_tight : tSerial 4096 4096 1 254 - tDdr 4096 4096 1 16 = 22536 := by decide
/-- hence stepS(D) = chain + F, affine in D up to floor rounding: D·T_S ≤ chain(D) < D·T_S + 2D (T_S = 122 979) -/
theorem T_Z3_affine (D t : Nat) (hD : 1 ≤ D) (ht : t ≤ 16) :
    stepSer 4096 4096 D t 254 fixed = tSerial 4096 4096 D 254 + fixed ∧
    D * 122979 ≤ tSerial 4096 4096 D 254 ∧ tSerial 4096 4096 D 254 < D * 122979 + 2 * D := by
  have h := T_Z3_chain_dominates D t hD ht
  refine ⟨?_, ?_⟩
  · unfold stepSer; omega
  · rw [T_Z3_chain_form]; omega
/-- the rounding at D = 8 is 10 ns (991 842 vs 8 000 + 8 × 122 979 = 991 832): invisible at µs precision -/
theorem T_Z3_rounding_8 : tSerial 4096 4096 8 254 - 8 * 122979 = 10 ∧ usR (8000 + 8 * 122979) = usR 991842 := by decide
/-- Z3 values: rateS(4) = 134.2 (t = 1), rateS(8) = 135.3, rateS(128) = 136.4 (t = 16); limit B_x/T_S = 136.4 -/
theorem T_Z3_values : rateSer 4096 4096 4 1 254 fixed = 1342 ∧ rateSer 4096 4096 8 1 254 fixed = 1353 ∧ rateSer 4096 4096 128 16 254 fixed = 1364 ∧
    bX 4096 4096 * 10 / 122979 = 1364 := by decide
/-- the unrounded rate D·B/(F + D·T_S) is strictly increasing in D (cross-multiplied; F > 0 is the whole reason) -/
theorem T_Z10_increasing (D : Nat) :
    D * 16777216 * (8000 + (D + 1) * 122979) < (D + 1) * 16777216 * (8000 + D * 122979) := by
  simp only [Nat.mul_add, Nat.add_mul, Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm, Nat.one_mul]
  omega
/-- Z10 bracket: for EVERY D ≥ 8 and t ≤ 16, 135.3 ≤ rateS(D) ≤ 136.4 — skew (any family, any s, any seed) moves scheme S by ≤ 1.1 GB/s = 0.8 % -/
theorem T_Z10_bracket (D t : Nat) (hD : 8 ≤ D) (ht : t ≤ 16) : 1353 ≤ rateSer 4096 4096 D t 254 fixed ∧ rateSer 4096 4096 D t 254 fixed ≤ 1364 := by
  have h := T_Z3_affine D t (by omega) ht
  unfold rateSer; rw [h.1, T_Z3_chain_form]
  unfold rateT bX fixed; simp only [Nat.reduceMul]
  constructor
  · rw [Nat.le_div_iff_mul_le (by omega)]; omega
  · have : (2 * (D * 16777216) * 10 + (D * 2162688 * 10 / 265 + D * 1024 * 15 + D * 1024 * 254 / 10 + 8000)) /
        (2 * (D * 2162688 * 10 / 265 + D * 1024 * 15 + D * 1024 * 254 / 10 + 8000)) < 1365 := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega
theorem T_Z10_width : 1364 - 1353 = 11 ∧ pct 11 1353 = 8 := by decide
/-- the step time scales with D: 15.7 ms (U, D = 128) vs 5.5 ms (Z(1.5), D = 45) at t = 16 — 2.8× fewer bytes -/
theorem T_Z10_steps : msT (stepSer 4096 4096 128 16 254 fixed) = 157 ∧ msT (stepSer 4096 4096 45 16 254 fixed) = 55 ∧ 128 * 10 / 45 = 28 := by decide

/-- Z4: round-robin count on core c among D active experts = (D + 7 − c) / 8 for c < 8 -/
theorem T_Z4_countRR (D c : Nat) (hc : c < 8) : Routing.countRR D c = (D + 7 - c) / 8 := by
  induction D with
  | zero => simp [Routing.countRR]; omega
  | succ n ih => simp only [Routing.countRR]; rw [ih]; split <;> omega
/-- hence max_c = ⌈D/8⌉ (core 0), min_c = ⌊D/8⌋ (core 7), every core in between -/
theorem T_Z4_max_min (D c : Nat) (hc : c < 8) :
    Routing.countRR D 0 = unitsW D ∧ Routing.countRR D 7 = D / 8 ∧ Routing.countRR D c ≤ unitsW D ∧ D / 8 ≤ Routing.countRR D c := by
  rw [T_Z4_countRR D c hc, T_Z4_countRR D 0 (by decide), T_Z4_countRR D 7 (by decide)]; unfold unitsW; omega
/-- balance: 8·⌈D/8⌉ = D iff 8 | D; otherwise max/mean = 8⌈D/8⌉/D > 1 (16/9 at D = 9, 64/63 at D = 63); ⌈D/8⌉ = 1 for 1 ≤ D ≤ 8 -/
theorem T_Z4_balanced_iff (D : Nat) : 8 * unitsW D = D ↔ D % 8 = 0 := by unfold unitsW; omega
theorem T_Z4_values : unitsW 9 = 2 ∧ 8 * unitsW 9 = 16 ∧ unitsW 63 = 8 ∧ 8 * unitsW 63 = 64 ∧ unitsW 4 = 1 ∧ 8 * unitsW 4 = 8 ∧
    (∀ D, D < 9 → 1 ≤ D → unitsW D = 1) := by decide
/-- W-dyn max per-core loader bytes = ⌈D/8⌉·K·N_e + 16·K (the definition's byte term), 16 MiB + 64 KiB per unit at the headline -/
theorem T_Z4_bytes : 4096 * 4096 + aCore 4096 = 16 * MiB + 64 * KiB := by decide
/-- Z4 rows ([M5], [M18]): W-dyn 68.9 (D = 4), 137.7 (8), 77.8 (9, t = 4), 86.4 (10, t = 4), 138.3 (16), 138.6 (32), 138.8 (128) -/
theorem T_Z4_rows : rateW 4096 4096 4 1 254 = 689 ∧ rateW 4096 4096 8 1 254 = 1377 ∧ rateW 4096 4096 9 4 254 = 778 ∧ rateW 4096 4096 10 4 254 = 864 ∧
    rateW 4096 4096 16 4 254 = 1383 ∧ rateW 4096 4096 32 4 254 = 1386 ∧ rateW 4096 4096 128 16 254 = 1388 := by decide
/-- W-dyn's A fraction is 0.4 %; its C slab 16 × 4096 × 4 B = 256 KiB = L0C (errata 14); two slabs double the A lifts → 137.4 -/
theorem T_Z4_wdyn_slab : pct (aCore 4096) (bX 4096 4096) = 4 ∧ 16 * 4096 * 4 = l0c ∧ rateW2 4096 4096 8 1 254 = 1374 := by decide
/-- Z9: W-static under H_c puts all D experts on one core: 17.3 GB/s at D = 8; 17.3–17.4 on every §7.4 cell -/
theorem T_Z9_static : rateWstatic 4096 4096 8 1 254 = 173 ∧ rateWstatic 4096 4096 4 1 254 = 173 ∧ rateWstatic 4096 4096 9 4 254 = 173 ∧
    rateWstatic 4096 4096 32 4 254 = 174 ∧ rateWstatic 4096 4096 128 16 254 = 174 ∧ rateWstatic 4096 4096 17 4 254 = 173 := by decide
/-- Z9 bytes: the hot core carries D·K·N_e + 16K = 8 × scheme S's D·K·N_c (plus the A block) -/
theorem T_Z9_bytes (D K Nc : Nat) : D * K * (8 * Nc) = 8 * (D * K * Nc) := by
  simp only [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm]

/-- Z7: T_W = 966 531 ns per whole expert, T_S = 122 979 per slice; T_W/(8·T_S) = 0.9824; tSerialW(D) = ⌈D/8⌉·T_W up to < ⌈D/8⌉ ns of rounding -/
theorem T_Z7_constants : tSerialW 4096 4096 8 254 = 966531 ∧ tSerial 4096 4096 1 254 = 122979 ∧ 966531 * 10000 / (8 * 122979) = 9824 := by decide
theorem T_Z7_W_form (D c : Nat) : tSerialW 4096 4096 D c = unitsW D * 16842752 * 10 / 265 + unitsW D * 32 * 256 * (150 + c) / 10 := by
  unfold tSerialW aCore lSer cMma; simp only [Nat.reduceMul, Nat.reduceAdd]
theorem T_Z7_W_affine (D : Nat) (hD : 1 ≤ D) : unitsW D * 966531 ≤ tSerialW 4096 4096 D 254 ∧ tSerialW 4096 4096 D 254 < unitsW D * 966531 + 2 * unitsW D := by
  rw [T_Z7_W_form]
  have h3 : 1 ≤ unitsW D := by unfold unitsW; omega
  generalize unitsW D = u at *
  constructor
  · -- lower bound: each floor is ≥ u × its integer part, 635 575 + 330 956 = 966 531
    have h1 : u * 635575 ≤ u * 16842752 * 10 / 265 := by rw [Nat.le_div_iff_mul_le (by decide)]; omega
    have h2 : u * 330956 ≤ u * 32 * 256 * (150 + 254) / 10 := by rw [Nat.le_div_iff_mul_le (by decide)]; omega
    have h4 : u * 966531 = u * 635575 + u * 330956 := by omega
    rw [h4]; exact Nat.add_le_add h1 h2
  · omega
/-- the design's crossover set (affine forms): ⌈D/8⌉·T_W < D·T_S ⟺ D ∈ {8|D} ∪ {D ≡ 7 (8), D ≥ 63} ∪ {118, 126}, for 1 ≤ D ≤ 128 -/
theorem T_Z7_crossover_affine (D : Nat) (h1 : 1 ≤ D) (h2 : D ≤ 128) :
    unitsW D * 966531 < D * 122979 ↔ (D % 8 = 0 ∨ (D % 8 = 7 ∧ 63 ≤ D) ∨ D = 118 ∨ D = 126) := by
  unfold unitsW; omega
/-- the same set under the exact (floor-rounded) model, with the §8 t per D: checked for every 1 ≤ D ≤ 128 (kernel evaluation) -/
theorem T_Z7_crossover_model : ∀ D, D < 129 → 1 ≤ D →
    (stepW 4096 4096 D (if D ≤ 8 then 1 else if D ≤ 32 then 4 else 16) 254 < stepSer 4096 4096 D (if D ≤ 8 then 1 else if D ≤ 32 then 4 else 16) 254 fixed
      ↔ (D % 8 = 0 ∨ (D % 8 = 7 ∧ 63 ≤ D) ∨ D = 118 ∨ D = 126)) := by decide +kernel
/-- on the winning set W-dyn's edge is ≤ 1.8 % (affine forms, every D): 2000·(D·T_S − ⌈D/8⌉·T_W) < 37·(F + ⌈D/8⌉·T_W) -/
theorem T_Z7_margin_affine (D : Nat) (_hw : D % 8 = 0 ∨ (D % 8 = 7 ∧ 63 ≤ D) ∨ D = 118 ∨ D = 126) (_h1 : 1 ≤ D) :
    pct (D * 122979 - unitsW D * 966531) (fixed + unitsW D * 966531) ≤ 18 := by
  unfold pct unitsW fixed
  have : (2 * (D * 122979 - (D + 7) / 8 * 966531) * 1000 + (8000 + (D + 7) / 8 * 966531)) / (2 * (8000 + (D + 7) / 8 * 966531)) < 19 := by
    rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
  omega
/-- exact-model margin on the winning set, and the values quoted: 1.8 % at D = 8 and 128, 0.2 % at 63, 0.1 % at 118 -/
theorem T_Z7_margin_model : (∀ D, D < 129 → (D % 8 = 0 ∨ (D % 8 = 7 ∧ 63 ≤ D) ∨ D = 118 ∨ D = 126) → 1 ≤ D →
      pct (stepSer 4096 4096 D (if D ≤ 8 then 1 else if D ≤ 32 then 4 else 16) 254 fixed - stepW 4096 4096 D (if D ≤ 8 then 1 else if D ≤ 32 then 4 else 16) 254)
          (stepW 4096 4096 D (if D ≤ 8 then 1 else if D ≤ 32 then 4 else 16) 254) ≤ 18) ∧
    pct (stepSer 4096 4096 8 1 254 fixed - stepW 4096 4096 8 1 254) (stepW 4096 4096 8 1 254) = 18 ∧
    pct (stepSer 4096 4096 128 16 254 fixed - stepW 4096 4096 128 16 254) (stepW 4096 4096 128 16 254) = 18 ∧
    pct (stepSer 4096 4096 63 16 254 fixed - stepW 4096 4096 63 16 254) (stepW 4096 4096 63 16 254) = 2 := by decide
/-- off the winning set scheme S wins: by 74.1 % at D = 9 (1.115 vs 1.941 ms), 94.9 % at D = 4, 56.8 % at D = 10, and by as little as 0.03 % at D = 55 -/
theorem T_Z7_losses : pct (stepW 4096 4096 9 4 254 - stepSer 4096 4096 9 4 254 fixed) (stepSer 4096 4096 9 4 254 fixed) = 741 ∧
    usR (stepSer 4096 4096 9 4 254 fixed) = 1115 ∧ usR (stepW 4096 4096 9 4 254) = 1941 ∧
    pct (stepW 4096 4096 4 1 254 - stepSer 4096 4096 4 1 254 fixed) (stepSer 4096 4096 4 1 254 fixed) = 949 ∧
    pct (stepW 4096 4096 10 4 254 - stepSer 4096 4096 10 4 254 fixed) (stepSer 4096 4096 10 4 254 fixed) = 568 ∧
    pctH (stepW 4096 4096 55 16 254 - stepSer 4096 4096 55 16 254 fixed) (stepSer 4096 4096 55 16 254 fixed) = 3 := by decide
/-- the comparison depends on D alone (both steps are functions of D and t, never of s): there is no threshold in s -/
theorem T_Z7_no_s_threshold (D t _s _s' : Nat) : (stepW 4096 4096 D t 254 < stepSer 4096 4096 D t 254 fixed) ↔ (stepW 4096 4096 D t 254 < stepSer 4096 4096 D t 254 fixed) := Iff.rfl
/-- the G = 2 knob: T_S' = 121 743; the winning set shrinks to 8 | D (for 1 ≤ D ≤ 128) and W-dyn's edge to ≤ 0.8 % -/
theorem T_Z7_G2_constant : tSerialG 4096 4096 1 2 254 = 121743 := by decide
theorem T_Z7_G2_crossover (D : Nat) (h1 : 1 ≤ D) (h2 : D ≤ 128) : unitsW D * 966531 < D * 121743 ↔ D % 8 = 0 := by
  unfold unitsW; omega
theorem T_Z7_G2_margin (D : Nat) (hw : D % 8 = 0) (h1 : 1 ≤ D) :
    pct (D * 121743 - unitsW D * 966531) (fixed + unitsW D * 966531) ≤ 8 := by
  unfold pct unitsW fixed
  have : (2 * (D * 121743 - (D + 7) / 8 * 966531) * 1000 + (8000 + (D + 7) / 8 * 966531)) / (2 * (8000 + (D + 7) / 8 * 966531)) < 9 := by
    rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
  omega

/-- Z8 (K-split): chainK 120 815 ns, ΔA = 2 164 ns (its A block is 8 KiB instead of 64), partials 1 MiB = 6 033 ns at the headline -/
theorem T_Z8_constants : chainK 4096 4096 254 = 120815 ∧ deltaA 4096 4096 254 = 2164 ∧ partialBytes 4096 8 1 = MiB ∧ timeNs (partialBytes 4096 8 1) rDdr = 6033 ∧
    16 * (4096 / 8) = 8 * KiB := by decide
/-- Z8 margins stepK − stepS ([M20]): +79 711 (t=1, D=8), +45 838 (4, 32), +71 823 (4, 20), +40 280 (16, 68), +90 085 (16, 45); and −89 648 at (16, 128) -/
theorem T_Z8_margins : stepKsplit 4096 4096 8 1 8 254 - stepSer 4096 4096 8 1 254 fixed = 79711 ∧
    stepKsplit 4096 4096 32 4 8 254 - stepSer 4096 4096 32 4 254 fixed = 45838 ∧
    stepKsplit 4096 4096 20 4 8 254 - stepSer 4096 4096 20 4 254 fixed = 71823 ∧
    stepKsplit 4096 4096 68 16 8 254 - stepSer 4096 4096 68 16 254 fixed = 40280 ∧
    stepKsplit 4096 4096 45 16 8 254 - stepSer 4096 4096 45 16 254 fixed = 90085 ∧
    stepSer 4096 4096 128 16 254 fixed - stepKsplit 4096 4096 128 16 8 254 = 89648 ∧
    stepKsplit 4096 4096 128 16 8 254 < stepSer 4096 4096 128 16 254 fixed := by decide
/-- the margin identity: stepK − stepS = T_launch + partials − D·ΔA, up to the chain's floor rounding (< 2D ns) -/
theorem T_Z8_identity (D t : Nat) (hD : 1 ≤ D) (ht : t ≤ 16) :
    stepKsplit 4096 4096 D t 8 254 + D * deltaA 4096 4096 254 ≤ stepSer 4096 4096 D t 254 fixed + tLaunch + timeNs (partialBytes 4096 8 t) rDdr ∧
    stepSer 4096 4096 D t 254 fixed + tLaunch + timeNs (partialBytes 4096 8 t) rDdr < stepKsplit 4096 4096 D t 8 254 + D * deltaA 4096 4096 254 + 2 * D := by
  have h := T_Z3_affine D t hD ht
  have hc : chainK 4096 4096 254 = 120815 := by decide
  have hd : deltaA 4096 4096 254 = 2164 := by decide
  unfold stepKsplit; rw [h.1, hc, hd]; omega
/-- Z8 rates: K-split 125.3 (D = 8), 114.7 (k = 4), 124.7 (D = 9, t = 4), 137.1 (D = 128, t = 16) vs S 136.4; S-G2 137.7 ≥ 137.1 there; its C slab is the errata-14 size -/
theorem T_Z8_rates : rateKsplit 4096 4096 8 1 8 254 = 1253 ∧ rateKsplit 4096 4096 4 1 4 254 = 1147 ∧ rateKsplit 4096 4096 9 4 8 254 = 1247 ∧
    rateKsplit 4096 4096 128 16 8 254 = 1371 ∧ rateSer 4096 4096 128 16 254 fixed = 1364 ∧ rateSerG 4096 4096 128 16 2 254 fixed = 1377 ∧
    1371 ≤ 1377 ∧ 16 * 4096 * 4 = l0c ∧ pct 89648 (stepKsplit 4096 4096 128 16 8 254) = 6 := by decide
/-- the partial WRITE (same bytes) rides under the serial regime's DDR slack: 6 033 ≤ 207 724 ns at D = 8; 96 450 ≤ slack at D = 128, t = 16 -/
theorem T_Z8_write_hidden : timeNs (partialBytes 4096 8 1) rDdr ≤ tSerial 4096 4096 8 254 - tDdr 4096 4096 8 1 ∧ tSerial 4096 4096 8 254 - tDdr 4096 4096 8 1 = 207724 ∧
    partialBytes 4096 8 16 = 16 * MiB ∧ timeNs (partialBytes 4096 8 16) rDdr = 96531 ∧ 96531 ≤ tSerial 4096 4096 128 254 - tDdr 4096 4096 128 16 := by decide
/-- host pre-pass / launch floor against the headline: 91 µs = 9.2 % of the headline step, 211.3 % of a (2048, 512, 4) step -/
theorem T_Z8_launch_pct : pct tLaunch (stepSer 4096 4096 8 1 254 fixed) = 92 ∧ stepSer 2048 512 4 1 254 fixed = 43072 ∧ pct tLaunch 43072 = 2113 := by decide

/-! ## T_floors — §7.4 rate floors per family (min over the family's generator D range; the ranges themselves are [Z], EMPIRICAL) -/

/-- family U (idealized): D = 8 / 32 / 128 exactly -/
theorem T_floors_U : rateSer 4096 4096 8 1 254 fixed = 1353 ∧ rateSer 4096 4096 32 4 254 fixed = 1361 ∧ rateSer 4096 4096 128 16 254 fixed = 1364 ∧
    rateW 4096 4096 8 1 254 = 1377 ∧ rateW 4096 4096 32 4 254 = 1386 ∧ rateW 4096 4096 128 16 254 = 1388 ∧
    rateKsplit 4096 4096 8 1 8 254 = 1253 ∧ rateKsplit 4096 4096 32 4 8 254 = 1346 ∧ rateKsplit 4096 4096 128 16 8 254 = 1371 := by decide
/-- family U_s: D ∈ [25, 32] at t = 4, [89, 115] at t = 16 -/
theorem T_floors_Us : (∀ D, D < 33 → 25 ≤ D → 1361 ≤ rateSer 4096 4096 D 4 254 fixed ∧ rateSer 4096 4096 D 4 254 fixed ≤ 1361 ∧ 1083 ≤ rateW 4096 4096 D 4 254 ∧ 1334 ≤ rateKsplit 4096 4096 D 4 8 254) ∧
    rateW 4096 4096 25 4 254 = 1083 ∧ rateKsplit 4096 4096 25 4 8 254 = 1334 ∧
    (∀ D, D < 116 → 89 ≤ D → 1363 ≤ rateSer 4096 4096 D 16 254 fixed ∧ rateSer 4096 4096 D 16 254 fixed ≤ 1363 ∧ 1287 ≤ rateW 4096 4096 D 16 254 ∧ 1364 ≤ rateKsplit 4096 4096 D 16 8 254) ∧
    rateW 4096 4096 89 16 254 = 1287 ∧ rateKsplit 4096 4096 89 16 8 254 = 1364 := by decide
/-- family Z(1.0): D ∈ [18, 31] at t = 4, [54, 84] at t = 16 -/
theorem T_floors_Z10 : (∀ D, D < 32 → 18 ≤ D → 1359 ≤ rateSer 4096 4096 D 4 254 fixed ∧ rateSer 4096 4096 D 4 254 fixed ≤ 1361 ∧ 1039 ≤ rateW 4096 4096 D 4 254 ∧ 1314 ≤ rateKsplit 4096 4096 D 4 8 254) ∧
    rateSer 4096 4096 18 4 254 fixed = 1359 ∧ rateW 4096 4096 18 4 254 = 1039 ∧ rateKsplit 4096 4096 18 4 8 254 = 1314 ∧
    (∀ D, D < 85 → 54 ≤ D → 1363 ≤ rateSer 4096 4096 D 16 254 fixed ∧ rateSer 4096 4096 D 16 254 fixed ≤ 1363 ∧ 1235 ≤ rateW 4096 4096 D 16 254 ∧ 1348 ≤ rateKsplit 4096 4096 D 16 8 254) ∧
    rateW 4096 4096 57 16 254 = 1235 ∧ rateKsplit 4096 4096 54 16 8 254 = 1348 := by decide
/-- family Z(1.5): D ∈ [13, 26] at t = 4, [34, 58] at t = 16 -/
theorem T_floors_Z15 : (∀ D, D < 27 → 13 ≤ D → 1357 ≤ rateSer 4096 4096 D 4 254 fixed ∧ rateSer 4096 4096 D 4 254 fixed ≤ 1361 ∧ 981 ≤ rateW 4096 4096 D 4 254 ∧ 1288 ≤ rateKsplit 4096 4096 D 4 8 254) ∧
    rateSer 4096 4096 13 4 254 fixed = 1357 ∧ rateW 4096 4096 17 4 254 = 981 ∧ rateKsplit 4096 4096 13 4 8 254 = 1288 ∧
    (∀ D, D < 59 → 34 ≤ D → 1362 ≤ rateSer 4096 4096 D 16 254 fixed ∧ rateSer 4096 4096 D 16 254 fixed ≤ 1363 ∧ 1178 ≤ rateW 4096 4096 D 16 254 ∧ 1326 ≤ rateKsplit 4096 4096 D 16 8 254) ∧
    rateSer 4096 4096 34 16 254 fixed = 1362 ∧ rateW 4096 4096 34 16 254 = 1178 ∧ rateKsplit 4096 4096 34 16 8 254 = 1326 := by decide
/-- family H (single-hot, D = 8 at every t): S 135.3, W-dyn 137.7, K-split 125.3 / 123.2 / 115.5 (its partials grow with t) -/
theorem T_floors_H : rateSer 4096 4096 8 4 254 fixed = 1353 ∧ rateSer 4096 4096 8 16 254 fixed = 1353 ∧ rateW 4096 4096 8 4 254 = 1377 ∧ rateW 4096 4096 8 16 254 = 1377 ∧
    rateKsplit 4096 4096 8 4 8 254 = 1232 ∧ rateKsplit 4096 4096 8 16 8 254 = 1155 := by decide
/-- W-static floors: 17.3 at every family's t = 1 point; ≤ 17.4 everywhere on D ∈ [8, 128] -/
theorem T_floors_static : (∀ D, D < 129 → 8 ≤ D → 173 ≤ rateWstatic 4096 4096 D 16 254 ∧ rateWstatic 4096 4096 D 16 254 ≤ 174) ∧
    (∀ D, D < 33 → 8 ≤ D → 173 ≤ rateWstatic 4096 4096 D 4 254 ∧ rateWstatic 4096 4096 D 4 254 ≤ 174) := by decide

/-! ## T_overflow — the L0C before/after i32-difference exactness bound (§3.2 P2/P3, [M12], [M25]; Appendix 17–18) -/

/-- P2: the i32 difference of a region's after- and before-readings equals the true per-expert sum S, whatever the region held before, iff −2³¹ ≤ S < 2³¹ -/
theorem T_overflow_modular_diff (b S : Int) :
    Accum.signed (Accum.wrap (Accum.signed (Accum.wrap (b + S)) - Accum.signed (Accum.wrap b))) = S ↔ (-2147483648 ≤ S ∧ S < 2147483648) := by
  unfold Accum.signed Accum.wrap
  constructor
  · intro h; split at h <;> split at h <;> split at h <;> omega
  · intro h; split <;> split <;> split <;> omega
/-- operand bound: with |a_k|, |b_k| ≤ 127 the per-expert column sum over K terms satisfies |S| ≤ 127²·K -/
theorem T_overflow_sum_bound (ps : List (Int × Int)) (h : Accum.opBounded ps) :
    -(16129 * (ps.length : Int)) ≤ Accum.sumI (Accum.prods ps) ∧ Accum.sumI (Accum.prods ps) ≤ 16129 * (ps.length : Int) := by
  induction ps with
  | nil => simp [Accum.sumI, Accum.prods]
  | cons p ps ih =>
    obtain ⟨a, b⟩ := p
    simp only [Accum.opBounded] at h
    have ih' := ih h.2
    have h1 : (a * b).natAbs = a.natAbs * b.natAbs := Int.natAbs_mul a b
    have h2 : a.natAbs ≤ 127 := by omega
    have h3 : b.natAbs ≤ 127 := by omega
    have h4 : a.natAbs * b.natAbs ≤ 127 * 127 := Nat.mul_le_mul h2 h3
    simp only [Accum.sumI, Accum.prods, List.length_cons, Int.natCast_add, Int.natCast_one]
    omega
/-- tightness witness: a_k = b_k = 127 for all K terms attains S = 127²·K exactly -/
theorem T_overflow_sum_tight (K : Nat) : Accum.sumI (Accum.prods (List.replicate K ((127 : Int), (127 : Int)))) = 16129 * (K : Int) := by
  induction K with
  | zero => simp [Accum.sumI, Accum.prods]
  | succ n ih => simp only [List.replicate, Accum.prods, Accum.sumI, ih, Int.natCast_add, Int.natCast_one]; omega
/-- a region used U times holds a running sum of U per-expert sums: |Σ| ≤ U·M when each |S_i| ≤ M -/
theorem T_overflow_running (M : Int) (ss : List Int) (h : Accum.eachBounded M ss) :
    -(M * (ss.length : Int)) ≤ Accum.sumI ss ∧ Accum.sumI ss ≤ M * (ss.length : Int) := by
  induction ss with
  | nil => simp [Accum.sumI]
  | cons s ss ih =>
    simp only [Accum.eachBounded] at h
    have ih' := ih h.2
    simp only [Accum.sumI, List.length_cons, Int.natCast_add, Int.natCast_one, Int.mul_add, Int.mul_one]
    omega
/-- P3 numbers: 127²·4096 = 66 064 384; U_max = ⌊(2³¹−1)/M⌋ = 32 at K = 4096 (6 regions cover D ≤ 192), 18 at K = 7168 (7 regions, 224 KiB, cover D ≤ 126); never the full 256 KB -/
theorem T_overflow_umax : 127 * 127 * 4096 = 66064384 ∧ (2 ^ 31 - 1) / 66064384 = 32 ∧ 6 * 32 = 192 ∧ 127 * 127 * 7168 = 115612672 ∧
    (2 ^ 31 - 1) / 115612672 = 18 ∧ 7 * 18 = 126 ∧ 6 * 32 * KiB = 192 * KiB ∧ 7 * 32 * KiB = 224 * KiB ∧ 224 * KiB < l0c ∧ 16 * Nc 4096 * 4 = 32 * KiB := by decide
/-- sufficiency for every U ≤ U_max: U·M < 2³¹, so the running sum never leaves i32 and wrap-vs-saturate is moot -/
theorem T_overflow_sufficient (U : Nat) (h : U ≤ 32) : U * 66064384 < 2 ^ 31 := by omega
theorem T_overflow_sufficient_7168 (U : Nat) (h : U ≤ 18) : U * 115612672 < 2 ^ 31 := by omega
/-- the bound is tight: U = 33 (K = 4096) or U = 19 (K = 7168) can overflow, and the all-127 witness reaches exactly U·M -/
theorem T_overflow_tight : 33 * 66064384 = 2180124672 ∧ 2 ^ 31 ≤ 33 * 66064384 ∧ 2 ^ 31 ≤ 19 * 115612672 ∧ 32 * 66064384 = 2114060288 ∧ 2114060288 < 2 ^ 31 := by decide
/-- combined: U ≤ 32 regions-uses of K = 4096 experts with bounded operands keep every reading inside i32 -/
theorem T_overflow_region_exact (ss : List Int) (hU : ss.length ≤ 32) (h : Accum.eachBounded 66064384 ss) :
    -2147483648 < Accum.sumI ss ∧ Accum.sumI ss < 2147483648 := by
  have := T_overflow_running 66064384 ss h
  have hl : (ss.length : Int) ≤ 32 := by omega
  constructor <;> omega
/-- the −128 caveat (prover-forced): if the quantizer may emit −128, 128²·4096·32 = 2³¹ exactly → U_max = 31 (6 regions still cover 186 ≥ 128); K = 7168 unchanged at 18 -/
theorem T_overflow_m128 : 32 * (128 * 128 * 4096) = 2 ^ 31 ∧ (2 ^ 31 - 1) / (128 * 128 * 4096) = 31 ∧ 6 * 31 = 186 ∧ 128 ≤ 186 ∧ (2 ^ 31 - 1) / (128 * 128 * 7168) = 18 := by decide
/-- D = 128 with six regions: ⌈128/6⌉ = 22 uses, 22·M = 1 453 416 448 < 2³¹ but > 2²⁴: the f32-difference branch needs A-mag -/
theorem T_overflow_D128 : ceilDiv 128 6 = 22 ∧ 22 * 66064384 = 1453416448 ∧ 1453416448 < 2 ^ 31 ∧ 2 ^ 24 = 16777216 ∧ 2 ^ 24 < 22 * 66064384 ∧ 2 ^ 24 < 2 ^ 25 + 1 := by decide
/-- the 4-region alternative (§6): covers D ≤ 128 at K ≤ 4096, D ≤ 72 at K = 7168 -/
theorem T_overflow_four_regions : 4 * 32 = 128 ∧ 4 * 18 = 72 := by decide
/-- E11(iv): a 127-valued oracle adds 127²·128 = 2 064 512 per call; the i32 range is exceeded at call 1041, so 1 100 calls make wrap-vs-saturate observable -/
theorem T_overflow_e11 : 127 * 127 * 128 = 2064512 ∧ (2 ^ 31 - 1) / 2064512 + 1 = 1041 ∧ 1041 ≤ 1100 ∧ 2 ^ 31 - 1 < 1100 * 2064512 ∧ 1040 * 2064512 ≤ 2 ^ 31 - 1 := by decide
/-- E13 accumulating oracle at the (16,16,128) shape: 10 000 loads × 8 calls × 128 × 15 = 1.536·10⁸ < 2³¹ (exact in i32) but > 2²⁴ (not f32-exact) -/
theorem T_overflow_e13 : 10000 * 8 * 128 * 15 = 153600000 ∧ 153600000 < 2 ^ 31 ∧ 2 ^ 24 < 10000 * 128 * 15 := by decide
/-- harness rule: |a|, |b| ≤ 15 over 2 × 128 k-rows → sums ≤ 57 600 ≪ 2²⁴, exact in i32 and f32 -/
theorem T_overflow_harness : 2 * 128 * 15 * 15 = 57600 ∧ 57600 < 2 ^ 24 := by decide

/-! ## T_pack — §2.1 P1: the per-core slice pack map is a bijection [0, K) × [0, N_c) → [0, K·N_c) (128 | K; N_c ∈ {64, 128, 256, 512}) -/

theorem T_pack_range (Nc K k n' : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hK : K % 128 = 0) (hk : k < K) (hn : n' < Nc) :
    Pack.off Nc k n' < K * Nc := by
  unfold Pack.off; rcases hN with h | h | h | h <;> subst h <;> omega
/-- the digit sum X = j·128N_c + g·2048 + f·512 + n·32 + k_l, with g < N_c/16, f < 4, n < 16, k_l < 32, divides back into its digits -/
theorem T_pack_digit_chunk (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hg : g < Nc / 16) (hf : f < 4) (hn : n < 16) (hkl : kl < 32) :
    (j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl) / (128 * Nc) = j := by
  rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_digit_inchunk (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hg : g < Nc / 16) (hf : f < 4) (hn : n < 16) (hkl : kl < 32) :
    (j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl) % (128 * Nc) = g * 2048 + f * 512 + n * 32 + kl := by
  rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_digit_instrip (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hf : f < 4) (hn : n < 16) (hkl : kl < 32) :
    (j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl) % 2048 = f * 512 + n * 32 + kl := by
  rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_digit_kl (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hkl : kl < 32) :
    (j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl) % 32 = kl := by
  rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_digit_infrag (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hn : n < 16) (hkl : kl < 32) :
    (j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl) % 512 = n * 32 + kl := by
  rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_digit_f (f n kl : Nat) (_hn : n < 16) (_hkl : kl < 32) : (f * 512 + n * 32 + kl) / 512 = f := by omega
theorem T_pack_digit_g (g f n kl : Nat) (_hf : f < 4) (_hn : n < 16) (_hkl : kl < 32) : (g * 2048 + f * 512 + n * 32 + kl) / 2048 = g := by omega
theorem T_pack_digit_n (n kl : Nat) (_hkl : kl < 32) : (n * 32 + kl) / 32 = n := by omega
theorem T_pack_left_inverse (Nc k n' : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hn : n' < Nc) :
    Pack.invK Nc (Pack.off Nc k n') = k ∧ Pack.invN Nc (Pack.off Nc k n') = n' := by
  -- write (k, n') in digits, then invert one division at a time
  have hg : n' / 16 < Nc / 16 := by have := hn; rcases hN with h | h | h | h <;> subst h <;> omega
  have hk1 : k = 128 * (k / 128) + 32 * (k % 128 / 32) + k % 32 := by omega
  have hn1 : n' = 16 * (n' / 16) + n' % 16 := by omega
  have hf : k % 128 / 32 < 4 := by omega
  have hn2 : n' % 16 < 16 := by omega
  have hkl : k % 32 < 32 := by omega
  have hoff : Pack.off Nc k n' = (k / 128) * (128 * Nc) + (n' / 16) * 2048 + (k % 128 / 32) * 512 + (n' % 16) * 32 + k % 32 := rfl
  rw [hoff]
  generalize k / 128 = j at *
  generalize n' / 16 = g at *
  generalize k % 128 / 32 = f at *
  generalize n' % 16 = n at *
  generalize k % 32 = kl at *
  unfold Pack.invK Pack.invN
  rw [T_pack_digit_chunk Nc j g f n kl hN hg hf hn2 hkl, T_pack_digit_inchunk Nc j g f n kl hN hg hf hn2 hkl,
    T_pack_digit_instrip Nc j g f n kl hN hf hn2 hkl, T_pack_digit_f f n kl hn2 hkl, T_pack_digit_kl Nc j g f n kl hN hkl,
    T_pack_digit_g g f n kl hf hn2 hkl, T_pack_digit_infrag Nc j g f n kl hN hn2 hkl, T_pack_digit_n n kl hkl]
  exact ⟨hk1.symm, hn1.symm⟩
/-- the pack map on digit form: off(128j + 32f + k_l, 16g + n_l) = j·128N_c + g·2048 + f·512 + n_l·32 + k_l -/
theorem T_pack_off_digits (Nc j g f n kl : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hg : g < Nc / 16) (hf : f < 4) (hn : n < 16) (hkl : kl < 32) :
    Pack.off Nc (128 * j + 32 * f + kl) (16 * g + n) = j * (128 * Nc) + g * 2048 + f * 512 + n * 32 + kl := by
  unfold Pack.off; rcases hN with h | h | h | h <;> subst h <;> omega
theorem T_pack_right_inverse (Nc K o : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (hK : K % 128 = 0) (ho : o < K * Nc) :
    Pack.off Nc (Pack.invK Nc o) (Pack.invN Nc o) = o ∧ Pack.invK Nc o < K ∧ Pack.invN Nc o < Nc := by
  have hg : o % (128 * Nc) / 2048 < Nc / 16 := by rcases hN with h | h | h | h <;> subst h <;> omega
  have hf : o % 2048 / 512 < 4 := by omega
  have hn : o % 512 / 32 < 16 := by omega
  have hkl : o % 32 < 32 := by omega
  have hoff := T_pack_off_digits Nc (o / (128 * Nc)) (o % (128 * Nc) / 2048) (o % 2048 / 512) (o % 512 / 32) (o % 32) hN hg hf hn hkl
  unfold Pack.invK Pack.invN
  rw [hoff]
  rcases hN with h | h | h | h <;> subst h <;> refine ⟨?_, ?_, ?_⟩ <;> omega
theorem T_pack_injective (Nc k₁ n₁ k₂ n₂ : Nat) (hN : Nc = 64 ∨ Nc = 128 ∨ Nc = 256 ∨ Nc = 512) (h₂ : n₁ < Nc) (h₄ : n₂ < Nc)
    (he : Pack.off Nc k₁ n₁ = Pack.off Nc k₂ n₂) : k₁ = k₂ ∧ n₁ = n₂ := by
  have h1 := T_pack_left_inverse Nc k₁ n₁ hN h₂
  have h2 := T_pack_left_inverse Nc k₂ n₂ hN h₄
  rw [he] at h1; omega
/-- every tile boundary is a multiple of the next smaller one: 2 MiB slice = 32 × 64 KiB chunk = 4 × 16 KiB piece = 8 × 2 KiB operand = 4 × 512 B fragment -/
theorem T_pack_boundaries : 2 * MiB = 32 * (64 * KiB) ∧ 64 * KiB = 4 * (16 * KiB) ∧ 16 * KiB = 8 * 2048 ∧ 2048 = 4 * 512 ∧ 512 = 16 * 32 ∧ 4096 * 4096 = 16 * MiB := by decide
/-- generic N_c: a k-chunk is 128·N_c B = 64 / 32 / 16 / 8 KiB; one 64 KiB COPY covers 1 / 2 / 4 / 8 chunks; a 16 KiB piece = 8 strips of one chunk (N_c ≥ 128) or 2 chunks × 4 strips (N_c = 64) -/
theorem T_pack_chunks : 128 * 512 = 64 * KiB ∧ 128 * 256 = 32 * KiB ∧ 128 * 128 = 16 * KiB ∧ 128 * 64 = 8 * KiB ∧
    64 * KiB / (128 * 512) = 1 ∧ 64 * KiB / (128 * 256) = 2 ∧ 64 * KiB / (128 * 128) = 4 ∧ 64 * KiB / (128 * 64) = 8 ∧
    512 / 16 = 32 ∧ 128 / 16 = 8 ∧ 64 / 16 = 4 ∧ 16 * KiB / (128 * 64) = 2 := by decide

/-! ## T_w4_parity — §8.4: the i4×i4 route in the serial regime (premises = the model's definitions; route existence is E19) -/

/-- W4 headline cells ([M7]): DDR bytes 71 843 840 (68.5 MiB), loader 9 MiB → 356 120 ns, 16 384 calls × 40.4 = 661 913 ns, chain 1 018 033, step 1 026 033 → 65.4 W4-GB/s = 130.8 W8-equivalent -/
theorem T_w4_cells : ddrBytes4 4096 4096 8 1 = 71843840 ∧ 71843840 * 10 / MiB = 685 ∧ loaderBytes4 4096 4096 8 = 9 * MiB ∧ timeNs (loaderBytes4 4096 4096 8) lSer = 356120 ∧
    8 * calls4 4096 4096 = 16384 ∧ 8 * calls4 4096 4096 * (cMma * 10 + 254) / 10 = 661913 ∧ tSerial4 4096 4096 8 254 = 1018033 ∧ step4 4096 4096 8 1 254 = 1026033 ∧
    rate4 4096 4096 8 1 254 = 654 ∧ 2 * 654 = 1308 ∧ (4096 / 128) * 4096 * 4 = 4096 * 4096 / 32 ∧ 16 * 128 / 2 = KiB := by decide
/-- PROVER-FORCED: W4 is NOT at parity with W8 in the serial regime — its step is 3.4 % longer, i.e. 96.7 % of W8's tokens/s (130.8 vs 135.3 W8-equivalent) -/
theorem T_w4_ratio : stepSer 4096 4096 8 1 254 fixed < step4 4096 4096 8 1 254 ∧ pct (stepSer 4096 4096 8 1 254 fixed) (step4 4096 4096 8 1 254) = 967 ∧
    pct (step4 4096 4096 8 1 254 - stepSer 4096 4096 8 1 254 fixed) (stepSer 4096 4096 8 1 254 fixed) = 34 ∧ pct 1308 1353 = 967 := by decide
/-- the W4 serial chain as a function of the residual c; it is chain-bound for every c (its DDR time is 413 370 ns) -/
theorem T_w4_chain (c : Nat) : tSerial4 4096 4096 8 c = 356120 + 16384 * (150 + c) / 10 ∧ timeNs (ddrBytes4 4096 4096 8 1) rDdr = 413370 := by
  constructor
  · simp only [tSerial4, timeNs, loaderBytes4, sliceB, aCore, Nc, calls4, callsX, lSer, cMma, Nat.reduceMul, Nat.reduceDiv, Nat.reduceAdd]
  · decide
/-- T_w4_parity: for EVERY residual c, W4 ≥ W8 tokens/s in the serial regime ⟺ c ≤ 21.2 ns; at the derived 25.4 ns W4 is slower -/
theorem T_w4_parity (c : Nat) : step4 4096 4096 8 1 c ≤ stepSer 4096 4096 8 1 c fixed ↔ c ≤ 212 := by
  unfold step4 stepSer; rw [(T_w4_chain c).1, (T_w4_chain c).2, T_cres_chain]
  have : tDdr 4096 4096 8 1 = 776118 := by decide
  rw [this]; unfold fixed; omega
/-- ping-pong W4: DDR-bound at 159.3 W4-GB/s = 1.86× W8's ping-pong tokens/s (not 2×); its doubled calls are 59.5 % of ITS DDR time; drain path needs 8.2 GB/s/core; c_res = 0 gives 110.0 -/
theorem T_w4_pp : stepPP4 4096 4096 8 1 = 421370 ∧ rateT (8 * b4X 4096 4096) (stepPP4 4096 4096 8 1) = 1593 ∧ pct (2 * 1593) 1712 = 1861 ∧
    pct (8 * calls4 4096 4096 * cMma) (timeNs (ddrBytes4 4096 4096 8 1) rDdr) = 595 ∧ pct (8 * calls4 4096 4096 * cMma) (tDdr 4096 4096 8 1) = 317 ∧
    drainNeed4 4096 4096 8 1 254 = 82 ∧ rate4 4096 4096 8 1 0 = 1100 ∧ drainBytes4 4096 4096 8 = 8 * 32 * (32 * KiB) := by decide
/-- the vector-unpack W4 route is dead: 42 GB/s aggregate int4-effective = 84 W8-equivalent < 120 -/
theorem T_w4_vector_dead : 2 * rUnpack4 = 840 ∧ 840 < 1200 := by decide
/-- §8.1 W4 column (serial, conditional route): 65.4 / 65.8 / 65.7 / 65.9 / 65.8 at the nine cells -/
theorem T_w4_table : rate4 4096 4096 8 1 254 = 654 ∧ rate4 4096 4096 32 4 254 = 658 ∧ rate4 4096 4096 25 4 254 = 658 ∧ rate4 4096 4096 20 4 254 = 657 ∧
    rate4 4096 4096 128 16 254 = 659 ∧ rate4 4096 4096 68 16 254 = 659 ∧ rate4 4096 4096 45 16 254 = 658 ∧
    usR (step4 4096 4096 8 1 254) = 1026 ∧ usR (step4 4096 4096 32 4 254) = 4080 ∧ usR (step4 4096 4096 25 4 254) = 3189 ∧ usR (step4 4096 4096 20 4 254) = 2553 ∧
    usR (step4 4096 4096 128 16 254) = 16297 ∧ usR (step4 4096 4096 68 16 254) = 8661 ∧ usR (step4 4096 4096 45 16 254) = 5734 ∧
    8 * b4X 4096 4096 / MiB = 64 ∧ 128 * b4X 4096 4096 / MiB = 1024 := by decide

/-! ## T8 — the §8.1 step-time table ([T8], [T8b]); Zipf D values are generator means (EMPIRICAL [Z]) -/

theorem T8_row_t1 : 8 * bX 4096 4096 / MiB = 128 ∧ usR (stepSer 4096 4096 8 1 254 fixed) = 992 ∧ rateSer 4096 4096 8 1 254 fixed = 1353 ∧
    tokPerMs 1 (stepSer 4096 4096 8 1 254 fixed) = 101 ∧ usR (stepPP 4096 4096 8 1 lSer fixed) = 784 ∧ ratePP 4096 4096 8 1 lSer fixed = 1712 := by decide
theorem T8_row_t4_U : 32 * bX 4096 4096 / MiB = 512 ∧ usR (stepSer 4096 4096 32 4 254 fixed) = 3943 ∧ rateSer 4096 4096 32 4 254 fixed = 1361 ∧
    tokPerMs 4 (stepSer 4096 4096 32 4 254 fixed) = 101 ∧ usR (stepPP 4096 4096 32 4 lSer fixed) = 3103 ∧ ratePP 4096 4096 32 4 lSer fixed = 1730 := by decide
theorem T8_row_t4_Z10 : 25 * bX 4096 4096 / MiB = 400 ∧ usR (stepSer 4096 4096 25 4 254 fixed) = 3083 ∧ rateSer 4096 4096 25 4 254 fixed = 1361 ∧
    tokPerMs 4 (stepSer 4096 4096 25 4 254 fixed) = 130 ∧ usR (stepPP 4096 4096 25 4 lSer fixed) = 2427 ∧ ratePP 4096 4096 25 4 lSer fixed = 1728 := by decide
theorem T8_row_t4_Z15 : 20 * bX 4096 4096 / MiB = 320 ∧ usR (stepSer 4096 4096 20 4 254 fixed) = 2468 ∧ rateSer 4096 4096 20 4 254 fixed = 1360 ∧
    tokPerMs 4 (stepSer 4096 4096 20 4 254 fixed) = 162 ∧ usR (stepPP 4096 4096 20 4 lSer fixed) = 1944 ∧ ratePP 4096 4096 20 4 lSer fixed = 1726 := by decide
theorem T8_row_t16_U : 128 * bX 4096 4096 / MiB = 2048 ∧ usR (stepSer 4096 4096 128 16 254 fixed) = 15749 ∧ rateSer 4096 4096 128 16 254 fixed = 1364 ∧
    tokPerMs 16 (stepSer 4096 4096 128 16 254 fixed) = 102 ∧ usR (stepPP 4096 4096 128 16 lSer fixed) = 12380 ∧ ratePP 4096 4096 128 16 lSer fixed = 1735 := by decide
theorem T8_row_t16_Z10 : 68 * bX 4096 4096 / MiB = 1088 ∧ usR (stepSer 4096 4096 68 16 254 fixed) = 8371 ∧ rateSer 4096 4096 68 16 254 fixed = 1363 ∧
    tokPerMs 16 (stepSer 4096 4096 68 16 254 fixed) = 191 ∧ usR (stepPP 4096 4096 68 16 lSer fixed) = 6582 ∧ ratePP 4096 4096 68 16 lSer fixed = 1733 := by decide
theorem T8_row_t16_Z15 : 45 * bX 4096 4096 / MiB = 720 ∧ usR (stepSer 4096 4096 45 16 254 fixed) = 5542 ∧ rateSer 4096 4096 45 16 254 fixed = 1362 ∧
    tokPerMs 16 (stepSer 4096 4096 45 16 254 fixed) = 289 ∧ usR (stepPP 4096 4096 45 16 lSer fixed) = 4360 ∧ ratePP 4096 4096 45 16 lSer fixed = 1732 := by decide
/-- single-hot: D = 8 at every t → 992 µs, 135.3, 16.13 tokens/ms at t = 16; idealized uniform gains nothing from a verify batch (1.01 at every t) -/
theorem T8_single_hot : usR (stepSer 4096 4096 8 16 254 fixed) = 992 ∧ rateSer 4096 4096 8 16 254 fixed = 1353 ∧ tokPerMs 16 (stepSer 4096 4096 8 16 254 fixed) = 1613 ∧
    tokPerMs 1 (stepSer 4096 4096 8 1 254 fixed) = 101 ∧ tokPerMs 4 (stepSer 4096 4096 32 4 254 fixed) = 101 ∧ tokPerMs 16 (stepSer 4096 4096 128 16 254 fixed) = 102 := by decide
/-- the ping-pong cell formula: max(ddr, loader, calls × 15) + 8 000 — the generic stepPP at L = 26.5 is exactly that (by definition); its t = 1 value -/
theorem T8_pp_formula : stepPP 4096 4096 8 1 lSer fixed = max (tDdr 4096 4096 8 1) (max (tLoad 4096 4096 8) (tMma 4096 4096 8)) + 8000 := rfl
/-- §8.2 wall-clock row: t=1 123.9; t=4 (D=32) 133.1, (D=20) 131.1; t=16 (D=128) 135.6, (D=45) 134.0 -/
theorem T8_wall_rows : rateT (8 * bX 4096 4096) (stepSer 4096 4096 8 1 254 fixed + tLaunch) = 1239 ∧ rateT (32 * bX 4096 4096) (stepSer 4096 4096 32 4 254 fixed + tLaunch) = 1331 ∧
    rateT (20 * bX 4096 4096) (stepSer 4096 4096 20 4 254 fixed + tLaunch) = 1311 ∧ rateT (128 * bX 4096 4096) (stepSer 4096 4096 128 16 254 fixed + tLaunch) = 1356 ∧
    rateT (45 * bX 4096 4096) (stepSer 4096 4096 45 16 254 fixed + tLaunch) = 1340 := by decide
/-- §8.2 G row ([M14]): A-lift fraction 3.1 / 1.6 / 0.8 %; serial rate 135.3 / 136.7 / 137.4 / 137.7 for G = 1 / 2 / 4 / 8; G = 2 is +1.0 %; G = 8 needs 256 KiB of live regions = L0C -/
theorem T8_gknob : pct (aCore 4096) (sliceB 4096 4096) = 31 ∧ pct (aCore 4096) (2 * sliceB 4096 4096) = 16 ∧ pct (aCore 4096) (4 * sliceB 4096 4096) = 8 ∧
    rateSerG 4096 4096 8 1 1 254 fixed = 1353 ∧ rateSerG 4096 4096 8 1 2 254 fixed = 1367 ∧ rateSerG 4096 4096 8 1 4 254 fixed = 1374 ∧ rateSerG 4096 4096 8 1 8 254 fixed = 1377 ∧
    pct (1367 - 1353) 1353 = 10 ∧ 8 * 32 * KiB = l0c := by decide
/-- Summary ranking table columns: S 134.2 at k = 4, 135.4 at D = 9 (t = 4); W-dyn 137.4 with two slabs; K-split 114.7 at k = 4, 124.7 at D = 9 -/
theorem T8_ranking : rateSer 4096 4096 4 1 254 fixed = 1342 ∧ rateSer 4096 4096 9 4 254 fixed = 1354 ∧ rateW2 4096 4096 8 1 254 = 1374 ∧
    rateKsplit 4096 4096 4 1 4 254 = 1147 ∧ rateKsplit 4096 4096 9 4 8 254 = 1247 := by decide

/-! ## T8s — the §8.3 other-shapes table ([M6], [M22]) -/

theorem T8s_4096_4096_8 : Nc 4096 = 512 ∧ callsX 4096 4096 = 1024 ∧ pct (aCore 4096) (sliceB 4096 4096) = 31 ∧ rateSer 4096 4096 8 1 254 fixed = 1353 ∧
    ratePP 4096 4096 8 1 lSer fixed = 1712 ∧ rateT (8 * bX 4096 4096) (stepSer 4096 4096 8 1 254 fixed + tLaunch) = 1239 ∧ rateW 4096 4096 8 1 254 = 1377 := by decide
theorem T8s_7168_4096_10 : Nc 4096 = 512 ∧ callsX 7168 4096 = 1792 ∧ pct (aCore 7168) (sliceB 7168 4096) = 31 ∧ rateSer 7168 4096 10 1 254 fixed = 1359 ∧
    ratePP 7168 4096 10 1 lSer fixed = 1723 ∧ rateT (10 * bX 7168 4096) (stepSer 7168 4096 10 1 254 fixed + tLaunch) = 1304 ∧ rateW 7168 4096 10 1 254 = 866 := by decide
theorem T8s_2048_4096_4 : callsX 2048 4096 = 512 ∧ pct (aCore 2048) (sliceB 2048 4096) = 31 ∧ rateSer 2048 4096 4 1 254 fixed = 1321 ∧
    ratePP 2048 4096 4 1 lSer fixed = 1653 ∧ rateT (4 * bX 2048 4096) (stepSer 2048 4096 4 1 254 fixed + tLaunch) = 973 ∧ rateW 2048 4096 4 1 254 = 683 := by decide
theorem T8s_7168_2048_8 : Nc 2048 = 256 ∧ callsX 7168 2048 = 896 ∧ pct (aCore 7168) (sliceB 7168 2048) = 63 ∧ rateSer 7168 2048 8 1 254 fixed = 1325 ∧
    ratePP 7168 2048 8 1 lSer fixed = 1703 ∧ rateT (8 * bX 7168 2048) (stepSer 7168 2048 8 1 254 fixed + tLaunch) = 1202 ∧ rateW 7168 2048 8 1 254 = 1372 := by decide
theorem T8s_4096_1024_8 : Nc 1024 = 128 ∧ callsX 4096 1024 = 256 ∧ pct (aCore 4096) (sliceB 4096 1024) = 125 ∧ rateSer 4096 1024 8 1 254 fixed = 1248 ∧
    ratePP 4096 1024 8 1 lSer fixed = 1642 ∧ rateT (8 * bX 4096 1024) (stepSer 4096 1024 8 1 254 fixed + tLaunch) = 933 ∧ rateW 4096 1024 8 1 254 = 1334 ∧
    rateSerG 4096 1024 8 1 4 254 fixed = 1321 ∧ pct (aCore 4096 / 4) (sliceB 4096 1024) = 31 := by decide
theorem T8s_4096_512_8 : Nc 512 = 64 ∧ callsX 4096 512 = 128 ∧ pct (aCore 4096) (sliceB 4096 512) = 250 ∧ rateSer 4096 512 8 1 254 fixed = 1131 ∧
    ratePP 4096 512 8 1 lSer fixed = 1558 ∧ rateT (8 * bX 4096 512) (stepSer 4096 512 8 1 254 fixed + tLaunch) = 701 ∧ rateW 4096 512 8 1 254 = 1281 ∧
    rateSerG 4096 512 8 1 4 254 fixed = 1257 ∧ pct (aCore 4096 / 4) (sliceB 4096 512) = 63 := by decide
/-- (2048, 512, 4): 97.4 serial; with A resident in L0A (one 32 KiB lift per step, 1.2 µs) 106.6 (PROVER-FORCED: the text's 110.0 dropped the remaining lift); 31.3 on the wall clock -/
theorem T8s_2048_512_4 : callsX 2048 512 = 64 ∧ pct (aCore 2048) (sliceB 2048 512) = 250 ∧ rateSer 2048 512 4 1 254 fixed = 974 ∧ usR (stepSer 2048 512 4 1 254 fixed) = 43 ∧
    ratePP 2048 512 4 1 lSer fixed = 1243 ∧ rateT (4 * bX 2048 512) (stepSer 2048 512 4 1 254 fixed + tLaunch) = 313 ∧ rateW 2048 512 4 1 254 = 604 ∧
    aCore 2048 = 32 * KiB ∧ timeNs (aCore 2048) lSer = 1236 ∧ rateSerRes 2048 512 4 1 254 fixed = 1066 ∧
    4 * bX 2048 512 = 4 * MiB := by decide
/-- A fits L0A (48 KiB of 64 budgeted) iff K ≤ 3072 — the residency rule of §5.1 -/
theorem T8s_resident_rule (K : Nat) : aCore K ≤ 48 * KiB ↔ K ≤ 3072 := by unfold aCore KiB; omega
/-- §8.3 step µs column: 992 / 2160 / 254 / 886 / 269 / 148 / 43 -/
theorem T8s_steps : usR (stepSer 4096 4096 8 1 254 fixed) = 992 ∧ usR (stepSer 7168 4096 10 1 254 fixed) = 2160 ∧ usR (stepSer 2048 4096 4 1 254 fixed) = 254 ∧
    usR (stepSer 7168 2048 8 1 254 fixed) = 886 ∧ usR (stepSer 4096 1024 8 1 254 fixed) = 269 ∧ usR (stepSer 4096 512 8 1 254 fixed) = 148 ∧ usR (stepSer 2048 512 4 1 254 fixed) = 43 := by decide

/-! ## T_budget — §6 buffer budget, §2.3 operands, §4.2 CSR memory ([M9], [M10]) -/

/-- S1: ring 256 KiB + A 64/112 KiB + shadows 192/224 KiB = 512 / 592 KiB ≤ 976 KiB; G = 2 adds 256 KiB → 768 / 848 -/
theorem T_budget_s1 : 4 * 64 * KiB = 256 * KiB ∧ 256 + 64 + 192 = 512 ∧ 256 + 112 + 224 = 592 ∧ 592 * KiB ≤ s1P ∧ 512 + 256 = 768 ∧ 592 + 256 = 848 ∧ 848 * KiB ≤ s1P := by decide
/-- L0A: 2 × 2 KiB, or the whole 32 KiB A at K = 2048; L0B: 3 × 16 KiB = 48 of 64 KiB; L0C: 6 × 32 = 192 KiB (7 × 32 = 224 at K = 7168), never 256 -/
theorem T_budget_l0 : 2 * 2 * KiB = 4 * KiB ∧ aCore 2048 = 32 * KiB ∧ 3 * 16 * KiB = 48 * KiB ∧ 48 * KiB < l0b ∧ 6 * 32 * KiB = 192 * KiB ∧ 192 * KiB < l0c ∧ 224 * KiB < l0c := by decide
/-- US ≈ 162.5 KiB (166 400 B) ≤ 208 KiB evidenced; with six shadows resident instead of one staging buffer it would be 322.5 KiB > 208 (PROVER-FORCED: text said ≈ 317) -/
theorem T_budget_us : (960 + 64) + 3 * 512 + 128 * 16 * 5 + 16 * 512 * 4 + 32 * KiB + 2 * 32 * KiB + 2 * 2 * KiB + 2 * KiB + 16 * KiB = 166400 ∧
    166400 * 10 / KiB = 1625 ∧ 166400 ≤ usEvidenced ∧ (166400 - 32 * KiB + 192 * KiB) * 10 / KiB = 3225 ∧ usEvidenced < 166400 - 32 * KiB + 192 * KiB := by decide
/-- operand sizes: descriptor ≤ 16 × 10 × 6 = 960 B; CSR 512 + 512 + 128 × 16 × 5 = 11 264 B = 11 KiB; y_acc 32 KiB; tok/sc 10 KiB; s_e slice 2 KiB (16 KiB per expert per die); y row 1 KiB runs, t × 8 KiB -/
theorem T_budget_operands : 16 * 10 * 6 = 960 ∧ 512 + 512 + 128 * 16 * 5 = 11264 ∧ 11264 / KiB = 11 ∧ 16 * 512 * 4 = 32 * KiB ∧ 128 * 16 * 5 = 10 * KiB ∧
    4 * Nc 4096 = 2 * KiB ∧ 4 * 4096 = 16 * KiB ∧ 2 * Nc 4096 = KiB ∧ 2 * 4096 = 8 * KiB ∧ aCore 7168 = 2 * 56 * KiB := by decide
/-- the drain geometry: a region row = 32 runs of 64 B at stride 1 024 (16 n × 4 B fragments), 16 rows = 32 KiB; shadows 6 × 32 KiB = 192 KiB in S1 -/
theorem T_budget_drain : Nc 4096 / 16 = 32 ∧ 16 * 4 = 64 ∧ 16 * 16 * 4 = 1024 ∧ 32 * 64 = 2 * KiB ∧ 16 * 2 * KiB = 32 * KiB ∧ 6 * 32 * KiB = 192 * KiB := by decide

/-! ## T_dispatch — §1.4, §4 ([M16], [M17], [M30]); σ_d stays universally quantified -/

/-- scan cells: σ_d = 10 / 50 / 100 / 250 ns → 0.08 / 0.4 / 0.8 / 2 µs at t = 1 and 1.3 / 6.4 / 12.8 / 32 µs at t = 16 (k = 8) -/
theorem T_dispatch_cells : scanNs 1 8 10 = 80 ∧ scanNs 1 8 50 = 400 ∧ scanNs 1 8 100 = 800 ∧ scanNs 1 8 250 = 2000 ∧
    scanNs 16 8 10 = 1280 ∧ scanNs 16 8 50 = 6400 ∧ scanNs 16 8 100 = 12800 ∧ scanNs 16 8 250 = 32000 ∧ scanNs 16 10 100 = 16000 := by decide
/-- t·k ≤ 160 iterations for t ≤ 16, k ≤ 10 (128 at k = 8) -/
theorem T_dispatch_iterations (t k : Nat) (ht : t ≤ 16) (hk : k ≤ 10) : scanNs t k 1 ≤ 160 := by
  unfold scanNs; have := Nat.mul_le_mul ht hk; omega
/-- the ≤ 127 iterations after the first hide under expert 0's 122 979 ns chain for every σ_d ≤ 968 ns (and the 12.8 µs at σ_d = 100 trivially) -/
theorem T_dispatch_hidden (σ : Nat) : 127 * σ ≤ tSerial 4096 4096 1 254 ↔ σ ≤ 968 := by
  have : tSerial 4096 4096 1 254 = 122979 := by decide
  rw [this]; omega
/-- at t = 1 the whole scan (0.8 µs at σ_d = 100) is smaller than one 64 KiB chunk time (3.0 µs at 21.725, 2.9 at 22.5); the exposed +30 µs worst case (σ_d = 250, t = 16) is 0.2 % of the step -/
theorem T_dispatch_small : scanNs 1 8 100 < 64 * KiB * 80 / rDdr ∧ 64 * KiB * 80 / rDdr = 3016 ∧ pct 32000 (stepSer 4096 4096 128 16 254 fixed) = 2 ∧ pct 2000 (stepSer 4096 4096 8 1 254 fixed) = 2 := by decide
/-- host pre-pass: ≥ 91 µs = 9.2 % of the headline step, 211.3 % of the (2048, 512, 4) step -/
theorem T_dispatch_host : pct tLaunch (stepSer 4096 4096 8 1 254 fixed) = 92 ∧ pct tLaunch (stepSer 2048 512 4 1 254 fixed) = 2113 := by decide

/-! ## T_epilogue — §3.1–§3.3 costs ([M8], [M15], [M19]; Appendix 20–22) -/

/-- per routed pair 4 × 512 = 2 048 lane-ops = 47 ns; per expert the 16-row Sub = 8 192 lane-ops = 189 ns; per step at t = 16, D = 128: 30 340 ns = 30.3 µs = 0.2 % (PROVER-FORCED: text said 31.9 / 190) -/
theorem T_epilogue_vector : laneNs 2048 = 47 ∧ laneNs 8192 = 189 ∧ epilogueNs 128 128 = 30340 ∧ usT 30340 = 303 ∧ pct 30340 (stepSer 4096 4096 128 16 254 fixed) = 2 ∧
    epilogueNs 8 8 = 1896 ∧ usT 1896 = 19 := by decide
/-- drain: 32 KiB per expert at 10 GB/s/core = 3 276 ns = 2.7 % of the 122 979 ns per-expert chain if exposed; D × 32 KiB = 256 KiB (D = 8) / 4 MiB (D = 128) -/
theorem T_epilogue_drain : timeNs (32 * KiB) 100 = 3276 ∧ pct 3276 122979 = 27 ∧ 8 * 32 * KiB = 256 * KiB ∧ 128 * 32 * KiB = 4 * MiB ∧ 2 * 2 * KiB = 4 * KiB := by decide
/-- §3.3 budget: scatter-add 8 × (3.3 µs drain + 0.24 µs vector) = 28 µs; shadow swap 2 × 32 KiB at 250 GB/s = 262 ns; x copy 2.9 µs; A share 0.4 % of bytes; per-token quantization 4.6 µs at t = 16 -/
theorem T_epilogue_budget : 8 * (3276 + 189 + 47) = 28096 ∧ usR 28096 = 28 ∧ timeNs (2 * 32 * KiB) rUsS1 = 262 ∧ timeNs (64 * KiB) (rStage / 8) = 2912 ∧
    pct (8 * aCore 4096) (8 * bX 4096 4096) = 4 ∧ laneNs (3 * 16 * 4096) = 4551 ∧ usT 4551 = 46 := by decide
/-- regression vs two measured 8 MiB dense passes (974 µs): +17 842 ns = 9 892 (256 KiB of extra A lifts: 8 × 64 KiB vs 2 × 128 KiB) + 8 000 (F) − 50 (anchor rounding); 1.8 %, dispatch share 0.2 %
    (PROVER-FORCED: the text's 14.8 + 3 decomposition did not add up) -/
theorem T_epilogue_regression : 2 * tDense = 974000 ∧ stepSer 4096 4096 8 1 254 fixed - 974000 = 17842 ∧
    loaderBytes 4096 4096 8 - 2 * (8 * MiB + 128 * KiB) = 256 * KiB ∧ timeNs (256 * KiB) lSer = 9892 ∧ 974000 - 2 * denseModelNs 254 = 50 ∧
    9892 + 8000 - 50 = 17842 ∧ pct 17842 974000 = 18 ∧ pct 2000 974000 = 2 ∧ pct 3000 974000 = 3 ∧ pct (128 * KiB) (8 * MiB) = 16 := by decide
/-- A-lift fraction 16/N_c: 3.1 / 6.3 / 12.5 / 25 % at N_c = 512 / 256 / 128 / 64; it costs 1.8 % in the serial regime vs W-dyn, 0 in the DDR-bound regime -/
theorem T_epilogue_alift : pct (16 * 4096) (4096 * 512) = 31 ∧ pct (16 * 4096) (4096 * 256) = 63 ∧ pct (16 * 4096) (4096 * 128) = 125 ∧ pct (16 * 4096) (4096 * 64) = 250 ∧
    pct (1377 - 1353) 1353 = 18 ∧ ratePP 4096 4096 8 1 lSer fixed = 1712 := by decide

/-! ## T_risk — §10 risk register numbers -/

/-- DDR pattern slower than per-core slabs is invisible in the serial regime until it exceeds the 983.8 µs chain: 27 % slack; E13 moves the number by up to 36 GB/s -/
theorem T_risk_slack : pct (983842 - 776118) 776118 = 268 ∧ 1712 - 1353 = 359 ∧ usT 983842 = 9838 := by decide
/-- loader < 22.3 at 16 KiB granules: L = 20 → 153.7 (the model's number includes F; 8·L·16/16.5 alone would be 155.2); still > 120 for L ≥ 15.6 -/
theorem T_risk_loader : ratePP 4096 4096 8 1 200 fixed = 1537 ∧ 8 * 200 * 16 / 165 = 155 ∧ ratePP 4096 4096 8 1 156 fixed = 1202 := by decide
/-- K = 7168, D > 126 exceeds 7 × U_max: cap D per launch at 7 × 18 = 126 -/
theorem T_risk_7168 : 7 * 18 = 126 := by decide
/-- small layers: (2048, 512, 4) is 31.3 on the wall clock and 97.4 in-kernel (E17 pipelining) -/
theorem T_risk_small : rateT (4 * bX 2048 512) (stepSer 2048 512 4 1 254 fixed + tLaunch) = 313 ∧ rateSer 2048 512 4 1 254 fixed = 974 := by decide

/-! ## T_sync — silicon-sync sensitivity (current HW-MAP rows 174.6 / 181.3 / ~181 / 138.9; not the design's anchor) ([M29]) -/

/-- re-anchoring c_res to the current serial-fallback row 138.9: T_dense = 483 145 ns, c_res = 24.4 ns, headline 136.4 (+1.1) -/
theorem T_sync_reanchor : 64 * MiB * 10 / rSerialFallback = 483145 ∧ cResOf 483145 = 244 ∧ rateSer 4096 4096 8 1 244 fixed = 1364 := by decide
/-- the DDR-bound ceiling at the ~181 pure-read roof: 178.2 (vs 171.2 at the 173.8 read+write roof); the 181.3 direct path and the 174.6 flat kernel are the un-modelled follow-up -/
theorem T_sync_roof : rateT (128 * MiB) (timeNs (ddrBytes 4096 4096 8 1) rPureRead + fixed) = 1782 ∧ ratePP 4096 4096 8 1 lSer fixed = 1712 ∧ 1746 ≤ rDirectLoad ∧ rKernelDirect ≤ rPureRead := by decide

end Proofs
