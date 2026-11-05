/-
  proof/attn.lean — machine-checked derivations for DESIGN-3.md (dmonk, decode attention over the
  KV cache: gather → online softmax → reduce, one die, 8 cores, one KV head per core).

  Core Lean 4 only (no Mathlib, no Batteries, no imports beyond the implicit Init). Every quantity is
  a scaled integer exactly as in proof/attn.py, so every theorem closes with `decide`, `omega`, `rfl`
  or `simp` plus core lemmas (`Nat.le_div_iff_mul_le`, `Nat.div_le_div_left`, `Nat.max_eq_left`,
  `Nat.mul_le_mul_*`, `Int.natAbs_add_le`), with `induction` / `ac_rfl` for the structural steps:
    bytes   : bytes (KiB = 1024, MiB = 2^20; GB = 10^9 decimal where HW-MAP quotes memory)
    rates   : tenths of GB/s (1 B/ns = 1 GB/s decimal)          1746 = 174.6
    time    : ns, floor  (tn b R = b*10 / R);  usR = µs round-half-up
    lane-ops: vector work units; 43.2 G lane-ops/s/core = 432 tenths → ns = ops*10 / 432
    pct     : tenths of a percent, round-half-up;  rateT : tenths of GB/s, round-half-up
  PROOF-COVERAGE-3.md maps every number in DESIGN-3.md to a theorem here, an attn.py label, an
  experiment (EMPIRICAL, E21–E28) or an explicit ASSUMPTION.

  Structure: namespace Measured = HW-MAP constants only (each with the row it comes from) plus the
  two cross-design inputs (PROBLEM-3's 398 µs unit, DESIGN-4's per-layer times — theorems of
  proof/fleet.lean); namespace Design = the (rows = t·g, d, block, page, L, H_kv, g)-parameterised
  cost model, buffer model, softmax op counts, drift model and page address maps as functions (no
  number that DESIGN-3.md concludes); then the proofs, one theorem per ledger row. The unmeasured and
  assumed quantities are explicit arguments of the model: `G` / `cpg` (gather rate / per-page cost,
  E21), `cV` / `cExp` / `R` / `rho` (softmax op set and f32 lane rate, E22), `Rd` (drain rate, E26),
  `merge` (merge lane-ops, §3.1), `sigma` (scalar iteration, E22), `smax` (score magnitude, E26/E27).

  Build: `lean proof/attn.lean` (standalone) or `cd proof && lake build` (target `Attn`).
  No `axiom`, no `sorry`, no `native_decide` anywhere.

  ROUND 3 (2026-11-05): the `T3r_*` section at the end of this file re-grounds every moved cell on the season (v1)
  measurements (HW-MAP commit 8a7079f: E21 gather rates per page size, E22 exp / reduce-max / And / rho32 / sigma_s,
  R_drain, the merge chain); the round-2 theorems above are kept as the arithmetic of the round-2 model and its retired
  branches (PROOF-COVERAGE-3.md's round-3 section says which cells they no longer describe).
-/

namespace Measured
/-- HW-MAP data-movement table: full W8 decode kernel, DDR → L0B direct loads with one full barrier per
    32 KiB tile, 174.6 GB/s aggregate, flat m = 1..16 (fp64 20/20). This is the STREAM BRANCH of the KV
    read: the attention kernel streams K and V through exactly this choreography and the stream is
    read-only (the only writes per step are the ≤ 8 KiB K/V append and the output), so the pure-read
    roof class applies — not the 173.8 read+write figure (HW-MAP: "the 173.8 roof was a read+write roof;
    pure read streams sustain ~181"). Tenths. -/
def rGemm : Nat := 1746
/-- HW-MAP data-movement table: raw DDR → L0B direct stream 181.3 GB/s — the pure-read roof the kernel's
    174.6 sits under (the difference is the per-tile barrier). Tenths. Used only for the what-if row. -/
def rDirect : Nat := 1813
/-- HW-MAP card table: LPDDR 173.8 GB/s is the read+WRITE streaming figure (512 MB fp16 stream);
    recorded, not used for the KV stream (see rGemm). Tenths. -/
def rDdrRW : Nat := 1738
/-- HW-MAP data-movement table: S1 → L0A/L0B loader 26.5 GB/s/core strict-serial. Tenths. -/
def rLoader : Nat := 265
/-- HW-MAP data-movement table: vector SRAM → S1 plain fill 250 GB/s/core (48–64 KiB tiles). Tenths. -/
def rUsS1 : Nat := 2500
/-- HW-MAP data-movement table: "fractal-transform" copy (COPY_FRAC) ~7 GB/s/core, software. Tenths. -/
def rFrac : Nat := 70
/-- HW-MAP data-movement table: MMA issue cost 15 ns per (16,16,128) call. ns. -/
def cMma : Nat := 15
/-- HW-MAP compute table: ~40 f16 lanes/cycle/core × 1.08 GHz = 43.2 G lane-ops/s per core. Tenths. -/
def rVecCore : Nat := 432
/-- HW-MAP data-movement table: ~91 µs launch + queue floor. ns. Enters WALL-CLOCK rows only. -/
def tLaunch : Nat := 91000
/-- HW-MAP hierarchy table: L0A / L0B 64 KB each, L0C 256 KB (measured, raw-MMA probes). Bytes. -/
def l0aCap : Nat := 65536
def l0bCap : Nat := 65536
def l0cCap : Nat := 262144
/-- HW-MAP hierarchy table: vector SRAM ~256 KB/core, ≥ 208 KB evidenced by working allocations. Bytes. -/
def usEvid : Nat := 212992
/-- HW-MAP hierarchy table: S1 ~1 MB (PRIOR). Bytes. -/
def s1Prior : Nat := 1000000
/-- HW-MAP errata #2 (single copy > 64 KB faults), #3 (≤ 1024 lanes per vector call), MMA shape constraints
    (n caps at 16; k = 64 deterministically wrong, k ∈ {32, 128} correct). -/
def copyCap : Nat := 65536
def laneCap : Nat := 1024
def nCap : Nat := 16
/-- PROBLEM-3's "die-step class" unit: 67.11 MB / 168.5 GB/s ≈ 398 µs (DESIGN.md route 1, m = 1 rate).
    An input of the PROBLEM statement, not a silicon measurement; the measured kernel at 174.6 would make
    the same bytes 384 µs (T_crossover_384 carries that variant). ns. -/
def tGemvUnit : Nat := 398000
def gemvBytes : Nat := 67110000
/-- DESIGN-4 per-layer weight-stream times, theorems of proof/fleet.lean (T_layer): dense layer
    18 256 993 ns, MoE layer (serial regime) 3 207 719 ns. Used only by the E21 fleet-cell theorem. -/
def tLayerDense : Nat := 18256993
def tLayerMoe : Nat := 3207719
end Measured

namespace Design
open Measured

/-! ### Units and helpers (attn.py conventions) -/
def KiB : Nat := 1024
def MiB : Nat := 1048576
def tn (b R : Nat) : Nat := b * 10 / R
def usR (ns : Nat) : Nat := (ns + 500) / 1000
def pct (n d : Nat) : Nat := (2 * n * 1000 + d) / (2 * d)
def rateT (b ns : Nat) : Nat := (2 * b * 10 + ns) / (2 * ns)
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b
def x10 (a b : Nat) : Nat := a * 10 / b

/-! ### Shape: (L, H_kv, g, d) — the headline is H_kv = 8 (one head per core), g = 8, d = 128, f16 -/
def hkvH : Nat := 8
def gH : Nat := 8
def dH : Nat := 128
/-- KV bytes per token per layer: K and V, f16 -/
def kvTok (hkv d : Nat) : Nat := 2 * hkv * d * 2
/-- KV bytes per token per core (one head per core) -/
def coreTok (d : Nat) : Nat := 4 * d   -- K 2d B + V 2d B
def kvBytes (L hkv d : Nat) : Nat := L * kvTok hkv d
/-- design page: 64 KiB; tokens per page at head dim d -/
def pageB : Nat := 65536
def pageTok (P d : Nat) : Nat := P / (2 * d)
/-- flat page tables: one 8 B entry per page per (head, K|V) -/
def pageTableBytes (L hkv P d : Nat) : Nat := 2 * hkv * 8 * ceilDiv L (pageTok P d)
/-- the page-table window read into US: 512 entries -/
def ptWindowEntries : Nat := 512

/-! ### Gather model `[A1]` (U, E21): per core one page costs P/21.825 GB/s + c_pg; 8 cores stream their own pages -/
def tCore (P cpg : Nat) : Nat := P * 80 / rGemm + cpg
def gPage (P cpg : Nat) : Nat := 8 * P * 10 / tCore P cpg
/-- the three G branches of §6 (tenths): stream = the kernel rate; page64k = G(64 KiB, 0.5 µs); gather3x = a third -/
def gStream : Nat := rGemm
def gPage64k : Nat := gPage pageB 500
def gGather3x : Nat := rGemm / 3

/-! ### Blocks, fragments, passes -/
/-- tokens per online-softmax block as a function of the A-fragment count: 512 at mt ≤ 2, 256 at mt = 3, 4
    (L0C budget §4), 128 at mt = 5..8 (the S4 single-pass geometry only) -/
def blockOf (mt : Nat) : Nat := if mt ≤ 2 then 512 else if mt ≤ 4 then 256 else 128
def rowsOf (t g : Nat) : Nat := t * g
def mtOf (rows : Nat) : Nat := ceilDiv rows 16
def rowsPassMax : Nat := 64
def passesOf (rows : Nat) : Nat := ceilDiv rows rowsPassMax
def mtPass (rows : Nat) : Nat := mtOf (min rows rowsPassMax)
/-- tokens served by the matrix path (whole 16-token groups); the ≤ 15 newest go to the vector tail -/
def lMatrix (L : Nat) : Nat := 16 * (L / 16)
def nblocks (L mt : Nat) : Nat := ceilDiv (lMatrix L) (blockOf mt)

/-! ### Per-core, per-block engine costs (ns) for one pass with mt A fragments at head dim d -/
/-- the die streams blockOf·coreTok·8 bytes per block at the gather rate G -/
def ddrBlock (G mt d : Nat) : Nat := tn (blockOf mt * coreTok d * 8) G
/-- vector chain: cV lane-ops per (score, row) over 16 rows per fragment (padding included) + the merge,
    at the f32 lane-rate penalty rho -/
def vecBlock (cV rho mt merge : Nat) : Nat := (blockOf mt * 16 * mt * cV + merge * mt) * rho * 10 / rVecCore
/-- MMA calls: scores one (16,16,128) call per 16 tokens at d = 128, two (16,16,32) calls at d = 64
    (k = 64 is illegal); PV d/16 calls per 128 tokens -/
def scoresCallsPer16 (d : Nat) : Nat := if d ≤ 64 then 2 else 1
def mmaCalls (mt d : Nat) : Nat := mt * ((blockOf mt / 16) * scoresCallsPer16 d + (d / 16) * (blockOf mt / 128))
def mmaBlock (mt d : Nat) : Nat := mmaCalls mt d * cMma
/-- loader: P fragments (16 rows × 128 tokens × 2 B = 4 KiB per fragment per 128 tokens) S1 → L0A -/
def pFragB : Nat := 4096
def loaderBlock (mt : Nat) : Nat := tn ((blockOf mt / 128) * pFragB * mt) rLoader
/-- L0C drain bytes per block: C_s (block × 16 rows × f32) + C_o (16 rows × d × f32), per fragment -/
def drainBytes (mt d : Nat) : Nat := (blockOf mt * 16 * 4 + 16 * d * 4) * mt
def drainBlock (mt d Rd : Nat) : Nat := tn (drainBytes mt d) Rd
/-- scalar tail of the tree max: 16 × 16 compares per fragment -/
def scalarBlock (mt sigma : Nat) : Nat := 256 * mt * sigma
/-- vector tail for the L mod 16 newest tokens: scores and PV as 16-row Mul + Add over K_tail / V_tail -/
def tailOps (L mt d : Nat) : Nat := (L % 16) * d * 16 * mt * 4
def tailNs (L mt d rho : Nat) : Nat := tailOps L mt d * rho * 10 / rVecCore

/-! ### The step model `[A4]`: T = passes · nb · max(engines) + fixed -/
inductive DrainMode where
  | hidden    -- the L0C drain is a separate path with R_drain ≥ the §2.2 threshold
  | separate  -- a separate path at the explicit rate Rd (enters the max)
  | same      -- the vector engine executes the drain (serial with the softmax)
  deriving DecidableEq, Repr

def blockMax (G cV rho Rd merge mt d : Nat) (mode : DrainMode) : Nat :=
  match mode with
  | .hidden => max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge)) (mmaBlock mt d)) (loaderBlock mt)
  | .separate => max (max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge)) (mmaBlock mt d)) (loaderBlock mt)) (drainBlock mt d Rd)
  | .same => max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge + drainBlock mt d Rd)) (mmaBlock mt d)) (loaderBlock mt)
/-- per-step fixed cost: pipeline fill (first block's softmax before the first PV) + tail (last block's
    softmax, drain, merge) + the vector tail; the launch floor is NOT here (wall-clock rows add tLaunch) -/
def fixedNs (L cV rho Rd merge mt mtAll d : Nat) : Nat :=
  2 * vecBlock cV rho mt merge + drainBlock mt d Rd + tailNs L mtAll d rho
def pSel (rows : Nat) (onepass : Bool) : Nat := if onepass then 1 else passesOf rows
def mtSel (rows : Nat) (onepass : Bool) : Nat := if onepass then mtOf rows else mtPass rows
/-- in-kernel step time (ns), f16 KV -/
def stepNs (L t g d G cV rho Rd merge : Nat) (mode : DrainMode) (onepass : Bool) : Nat :=
  pSel (rowsOf t g) onepass * nblocks L (mtSel (rowsOf t g) onepass) * blockMax G cV rho Rd merge (mtSel (rowsOf t g) onepass) d mode
  + fixedNs L cV rho Rd merge (mtSel (rowsOf t g) onepass) (mtOf (rowsOf t g)) d
/-- the KV-int8 variant (route 1b): the streamed bytes halve (attn.py halves the DDR total), nothing else moves -/
def stepI8 (L t g d G cV rho Rd merge : Nat) : Nat :=
  let p := passesOf (rowsOf t g)
  let mt := mtPass (rowsOf t g)
  let nb := nblocks L mt
  max (max (max (p * nb * ddrBlock G mt d / 2) (p * nb * vecBlock cV rho mt merge)) (p * nb * mmaBlock mt d)) (p * nb * loaderBlock mt)
  + fixedNs L cV rho Rd merge mt (mtOf (rowsOf t g)) d
/-- wall clock = in-kernel + the launch floor -/
def wallNs (ns : Nat) : Nat := ns + tLaunch
/-- effective KV rate (tenths, round-half-up): bytes streamed (passes × KV) / T -/
def effRate (L hkv d passes T : Nat) : Nat := rateT (kvBytes L hkv d * passes) T
/-- the headline corners of §6: native = (cV 7, rho 1), worst = ISA.md as written at half rate (cV 33, rho 2) -/
def cvNat : Nat := 7
def cvWorst : Nat := 33
def rDrainA : Nat := 100
def mergeOps : Nat := 7000
/-- shorthand for the headline-shape step (g = 8, d = 128, drain hidden, R_drain = 10 GB/s, merge 7000) -/
def stepH (L t G cV rho : Nat) : Nat := stepNs L t gH dH G cV rho rDrainA mergeOps .hidden false
def stepHsame (L t G cV rho : Nat) : Nat := stepNs L t gH dH G cV rho rDrainA mergeOps .same false
def stepS4 (L G cV rho : Nat) : Nat := stepNs L 16 gH dH G cV rho rDrainA mergeOps .hidden true
def stepI8H (L G cV rho : Nat) : Nat := stepI8 L 1 gH dH G cV rho rDrainA mergeOps

/-! ### The vector-dot route (route 3, T_gqa_matrix): 4·rows·d lane-ops per token against 4d bytes per token per core -/
def dotRouteOpsTok (rows d : Nat) : Nat := 4 * rows * d
/-- ratio vector-dot / KV stream in tenths of a percent (attn.py `[A3-vecroute-*]`) -/
def dotRatioT (rows rho d : Nat) : Nat := rows * rho * 4 * d * rGemm * 10000 / (80 * coreTok d * rVecCore)

/-! ### Softmax op counts `[A7-poly]` `[A7-tree-ops]` (§3.2): every op from ISA.md's list -/
/-- c_V per (score, row) = difference 2 + max R + shift 1 + exp E + cast 1 + sum 1 -/
def cVof (cExp R : Nat) : Nat := 2 + R + 1 + cExp + 1 + 1
def rNative : Nat := 1
def rTree : Nat := 6
def eNative : Nat := 1
/-- the clamped Horner-plus-squaring exp: clamp (a 6-op max) + scale + Horner degree 4 (4 Mul + 4 Add) + 7 squarings -/
def polyOps : Nat := 6 + 1 + (4 + 4) + 7
/-- elementwise tree max over 8 reels of 1024 lanes (7 pair-ops) then 1024 → 256 lanes (2 pair-ops), 6 lane-ops per pair -/
def treeLaneOps : Nat := 6 * (7 * 1024 + 512 + 256)
def treeScalarCompares : Nat := 16 * 15
/-- exact per-block lane-ops of the (poly, tree) chain at mt = 1, block 512 (8192 scores) -/
def polyTreeBlockExact : Nat := 2 * 8192 + treeLaneOps + 8192 + polyOps * 8192 + 8192 + 8192
/-- the HYPOTHESIS constant: relative error of the polynomial, in 10⁻⁶ units (Taylor remainder on
    [−22/128, 0] amplified by the 7 squarings: 2⁷·(22/128)⁵/5!, DESIGN-3 §3.2; E22(e) measures it) -/
def polyRelErrPpm : Nat := 160

/-! ### Drift model (§3.2 step 1, T_drift): a region's content after n visits with ±Q alternation -/
/-- alternating sum of n block sums at one lane: Σ_{i<n} (−1)^i s_i -/
def altSum (s : Nat → Int) : Nat → Int
  | 0 => 0
  | n + 1 => altSum s n + (if n % 2 = 0 then s n else - s n)
/-- floor log2 with fuel (structural, decide-friendly) -/
def lg2 : Nat → Nat → Nat
  | 0, _ => 0
  | fuel + 1, n => if n < 2 then 0 else lg2 fuel (n / 2) + 1
/-- f32 ulp of a magnitude M ≥ 1 in units of 2⁻²⁴: 2^(⌊log2 M⌋ + 1) -/
def ulpU (M : Nat) : Nat := 2 ^ (lg2 64 M + 1)
/-- region visits at context L with blocks of blk tokens over 3 rotating regions -/
def visits (L blk : Nat) : Nat := ceilDiv (L / blk) 3
/-- integer square root by bounded search (decide-friendly for the sizes used) -/
def isqrtLe (n : Nat) : Nat := (List.range 64).foldl (fun acc k => if k * k ≤ n then k else acc) 0

/-! ### Buffers (§4): every size is a function of (mt, d, blk) — never of L -/
structure Cfg where
  mt : Nat
  d : Nat
  blk : Nat
  L : Nat
/-- A fragment (q or P): 16 rows × 128 × 2 B -/
def fragB : Nat := 4096
def l0bRing : Nat := 2 * 32768
/-- +Q and −Q resident (the ±Q alternation of §3.2) and a double-buffered P fragment set -/
def l0aQ (c : Cfg) : Nat := 2 * fragB * c.mt
def l0aP (c : Cfg) : Nat := 2 * fragB * c.mt
def l0aTotal (c : Cfg) : Nat := l0aQ c + l0aP c
def csRegion (c : Cfg) : Nat := c.blk * 16 * 4 * c.mt
def coRegion (c : Cfg) : Nat := 16 * c.d * 4 * c.mt
def l0cTotal (c : Cfg) : Nat := 3 * csRegion c + 2 * coRegion c
/-- US rows of the §4 table, in order -/
def usDrained (c : Cfg) : Nat := csRegion c
def usNegSnap (c : Cfg) : Nat := if c.mt = 1 then 3 * csRegion c else 0
def dbl (c : Cfg) : Nat := if c.mt < 4 then 2 else 1
def usPStage (c : Cfg) : Nat := dbl c * (c.blk * 16 * 2 * c.mt)
def usO (c : Cfg) : Nat := coRegion c
def usPartials (c : Cfg) : Nat := dbl c * coRegion c
def usSAcc : Nat := 4096
def usShift : Nat := 4096
def usAlpha : Nat := 64
def usKTail : Nat := 4096
def usVTail : Nat := 4096
def usQRow (c : Cfg) : Nat := fragB * c.mt
def usPtWindow (win : Nat) : Nat := 4096 * win
def usTotal (c : Cfg) (win : Nat) : Nat :=
  usDrained c + usNegSnap c + usPStage c + usO c + usPartials c + usSAcc + usShift + usAlpha
  + usKTail + usVTail + usQRow c + usPtWindow win
/-- S1 at mt ≥ 2: the P ring pieces and the three snapshots -/
def s1Total (c : Cfg) : Nat := 2 * fragB * c.mt + (if 2 ≤ c.mt then 3 * csRegion c else 0)
/-- the design's (mt, blk) pairs: blk = blockOf mt -/
def cfgH (mt : Nat) (L : Nat) : Cfg := { mt := mt, d := dH, blk := blockOf mt, L := L }
/-- the S4 single-pass geometry: mt = 8, 128-token blocks, Q single (no −Q), P single-buffered, 2 C_s regions -/
def s4L0A : Nat := fragB * 8 + fragB * 8
def s4L0C : Nat := 2 * (128 * 16 * 4 * 8) + 2 * (16 * dH * 4 * 8)

/-! ### Page address maps (§1.2, §1.3) within one 64 KiB page: l' = token mod 256, j = dim -/
def kAddr (l j : Nat) : Nat := (l / 16) * 4096 + (j / 16) * 512 + (l % 16) * 32 + (j % 16) * 2
def vAddr (l j : Nat) : Nat := ((l / 128) * 8 + j / 16) * 4096 + ((l % 128) / 16) * 512 + (j % 16) * 32 + (l % 16) * 2
def kInvL (a : Nat) : Nat := 16 * (a / 2048) + (a / 16) % 16
def kInvJ (a : Nat) : Nat := 16 * ((a / 256) % 8) + a % 16
def vInvL (a : Nat) : Nat := 128 * (a / 16384) + 16 * ((a / 256) % 8) + a % 16
def vInvJ (a : Nat) : Nat := 16 * ((a / 2048) % 8) + (a / 16) % 16

/-! ### KV write path (§1.2, §1.3, §10) and the vector tail -/
def vTailBlockB (d : Nat) : Nat := 16 * d * 2
def kAppendCopies (d : Nat) : Nat := d / 16
end Design

open Measured Design

/-! ## T0 — shape, bytes, blocks, page tables (`[A0-*]`, ledger rows 1–2) -/
theorem T0_kv_bytes : kvTok 8 128 = 4096 ∧ coreTok 128 = 512 ∧ kvBytes 4096 8 128 = 2 ^ 24 ∧
    kvBytes 32768 8 128 = 2 ^ 27 ∧ kvBytes 131072 8 128 = 2 ^ 29 ∧ kvBytes 1048576 8 128 = 2 ^ 32 ∧
    pageTok pageB 128 = 256 ∧ pageTok pageB 64 = 512 ∧ blockOf 1 * coreTok 128 = 256 * KiB ∧
    blockOf 1 * kvTok 8 128 = 2 * MiB ∧ hkvH * gH = 64 := by decide
theorem T0_blocks : nblocks 4096 1 = 8 ∧ nblocks 32768 1 = 64 ∧ nblocks 131072 1 = 256 ∧
    nblocks 1048576 1 = 2048 ∧ nblocks 32768 4 = 128 ∧ nblocks 1048576 4 = 4096 ∧ nblocks 32768 8 = 256 := by decide
/-- the matrix path serves 16⌊L/16⌋ tokens and the vector tail the remaining L mod 16 ≤ 15, for every L -/
theorem T0_matrix_tail (L : Nat) : lMatrix L + L % 16 = L ∧ L % 16 ≤ 15 ∧ lMatrix L % 16 = 0 := by
  unfold lMatrix; omega
theorem T0_page_table : pageTableBytes 4096 8 pageB 128 = 2048 ∧ pageTableBytes 32768 8 pageB 128 = 16384 ∧
    pageTableBytes 131072 8 pageB 128 = 65536 ∧ pageTableBytes 1048576 8 pageB 128 = 524288 ∧
    ptWindowEntries * pageTok pageB 128 = 131072 ∧ ptWindowEntries * 8 = 4096 := by decide
/-- CORRECTION (§1.1 "0.4 % of KV"): the tables are 128 B per 256 tokens per die against 1 MiB of KV =
    122 ppm = 0.012 %; the round-1 figure divided 16 B per 256 tokens by 4 096 B per ONE token -/
theorem T0_page_table_share : 2 * 8 * 8 * 1000000 / (256 * kvTok 8 128) = 122 ∧
    pageTableBytes 1048576 8 pageB 128 * 1000000 / kvBytes 1048576 8 128 = 122 ∧ pct 16 4096 = 4 := by decide

/-! ## T1 — the G(P) gather model (`[A1-*]`, rows 4, 25; c_pg is a hypothesis variable, E21) -/
theorem T1_gather_cells :
    gPage 4096 0 = 1752 ∧ gPage 4096 500 = 476 ∧ gPage 4096 2000 = 149 ∧
    gPage 16384 0 = 1747 ∧ gPage 16384 500 = 1048 ∧ gPage 16384 2000 = 476 ∧
    gPage 65536 0 = 1746 ∧ gPage 65536 500 = 1497 ∧ gPage 65536 2000 = 1048 ∧
    gPage 262144 0 = 1746 ∧ gPage 262144 500 = 1676 ∧ gPage 262144 2000 = 1496 ∧
    gPage 1048576 0 = 1746 ∧ gPage 1048576 500 = 1728 ∧ gPage 1048576 2000 = 1676 := by decide
theorem T1_gather_branches : gStream = 1746 ∧ gPage64k = 1497 ∧ gGather3x = 582 ∧
    gPage pageB 6005 = 582 ∧ gPage pageB 6006 = 582 ∧ gPage pageB 6007 = 581 ∧ gPage pageB 5990 = 583 ∧
    gPage 4096 376 = 582 ∧ gPage 4096 375 = 583 ∧ tCore pageB 0 = 3002 := by decide
/-- the "3× slower" branch is a per-page cost of 5 991–6 006 ns at 64 KiB pages (G = 582 exactly), ≥ 6 006 ns gives ≤ 582 -/
theorem T1_gather3x_cpg (cpg : Nat) : (582 ≤ gPage pageB cpg ↔ cpg ≤ 6006) ∧ (gPage pageB cpg ≤ 582 ↔ 5991 ≤ cpg) := by
  unfold gPage tCore pageB rGemm
  show (582 ≤ 5242880 / (3002 + cpg) ↔ cpg ≤ 6006) ∧ (5242880 / (3002 + cpg) ≤ 582 ↔ 5991 ≤ cpg)
  constructor
  · rw [Nat.le_div_iff_mul_le (by omega)]; constructor <;> intro h <;> omega
  · rw [Nat.div_le_iff_le_mul_add_pred (by omega)]; constructor <;> intro h <;> omega
/-- G(P, c_pg) is non-increasing in c_pg for every page size (row 4 "monotone in c_pg") -/
theorem T1_gather_monotone_cpg (P c c' : Nat) (h : c ≤ c') (hP : 0 < tCore P c) : gPage P c' ≤ gPage P c := by
  unfold gPage
  apply Nat.div_le_div_left _ hP
  unfold tCore; omega
/-- monotone in P along the table's page sizes at c_pg = 0.5 µs and 2 µs (floored model) -/
theorem T1_gather_monotone_P : gPage 4096 500 ≤ gPage 16384 500 ∧ gPage 16384 500 ≤ gPage 65536 500 ∧
    gPage 65536 500 ≤ gPage 262144 500 ∧ gPage 262144 500 ≤ gPage 1048576 500 ∧
    gPage 4096 2000 ≤ gPage 16384 2000 ∧ gPage 16384 2000 ≤ gPage 65536 2000 ∧
    gPage 65536 2000 ≤ gPage 262144 2000 ∧ gPage 262144 2000 ≤ gPage 1048576 2000 := by decide
/-- CORRECTION (§1.4 table, c_pg = 0 row): at c_pg = 0 the rate is exactly R_gemm for every page size; the
    175.2 / 174.7 cells are floor artifacts (t_core floored to 187 / 750 ns). In the integer model
    G(P, 0) ≥ 1746 for every P ≥ 22 B. -/
theorem T1_gather_exact (P : Nat) (hP : 22 ≤ P) : 1746 ≤ gPage P 0 := by
  unfold gPage tCore rGemm
  have hq : 0 < P * 80 / 1746 := by
    rw [Nat.lt_div_iff_mul_lt (by decide)] <;> omega
  rw [Nat.le_div_iff_mul_le (by omega)]
  have := Nat.div_mul_le_self (P * 80) 1746
  omega
theorem T1_gather_artifact : 4096 * 80 / 1746 = 187 ∧ 4096 * 80 = 187 * 1746 + 1178 ∧ 16384 * 80 / 1746 = 750 := by decide
/-- a 4 KiB page is within 10 % of the stream only for c_pg ≤ 20 ns (90.6 % at 20 ns, 90.2 % at 21) -/
theorem T1_small_page : gPage 4096 20 = 1582 ∧ pct 1582 1746 = 906 ∧ gPage 4096 21 = 1575 ∧ pct 1575 1746 = 902 ∧
    gPage 4096 22 = 1567 ∧ pct 1567 1746 = 897 := by decide
/-- what-if the stream ran at the raw direct-load roof 181.3 (the kernel's 174.6 sits under it by the per-tile barrier) -/
theorem T1_stream_roof : stepH 1048576 1 rDirect cvNat 1 = 23696290 ∧ stepH 32768 1 rDirect cvNat 1 = 747362 ∧
    pct 24605602 23696290 = 1038 ∧ rGemm ≤ rDirect ∧ rDdrRW < rGemm := by decide
/-- CORRECTION (§9 gather row "≤ 4 MiB per layer at 1 MiB pages"): the worst tail waste is one partially
    filled page per (head, K|V) = 16 pages per layer: 4.00 MiB at 256 KiB pages, 16.00 MiB at 1 MiB pages -/
theorem T1_tail_waste : pageTok (256 * KiB) 128 = 1024 ∧ pageTok MiB 128 = 4096 ∧
    16 * (256 * KiB - 256) = 4190208 ∧ 16 * (MiB - 256) = 16773120 ∧ 16773120 / MiB = 15 ∧ 16773121 ≤ 16 * MiB := by decide
/-- a 32 KiB tile never straddles a page of 64 KiB / 256 KiB / 1 MiB (row 26) -/
theorem T1_tile_in_page (k : Nat) : (k * 32768) / 65536 = (k * 32768 + 32767) / 65536 ∧
    (k * 32768) / 262144 = (k * 32768 + 32767) / 262144 ∧ (k * 32768) / 1048576 = (k * 32768 + 32767) / 1048576 := by
  omega

/-! ## T2 — per-block engine budgets (`[A2-*]`, rows 5–7) -/
theorem T2_block : ddrBlock gStream 1 128 = 12011 ∧ rGemm / 8 = 218 ∧ mmaBlock 1 128 = 960 ∧
    pct 960 12011 = 80 ∧ loaderBlock 1 = 618 ∧ pct 618 12011 = 51 ∧ tn 16384 rUsS1 = 65 ∧
    drainBytes 1 128 = 40960 ∧ rateT 40960 12011 = 34 ∧ drainBlock 1 128 rDrainA = 4096 ∧
    pct 4096 12011 = 341 ∧ scalarBlock 1 2 = 512 ∧ pct 512 12011 = 43 ∧ pct 65 12011 = 5 := by decide
/-- the per-fragment scaling of §2.2: MMA 960·mt, loader 618·mt, drain 40 960·mt B at block 512 (mt ≤ 2);
    at block 256 (mt = 3, 4) the same per token: 480·mt, 309·mt, 24 576·mt B per block -/
theorem T2_block_mt : mmaBlock 2 128 = 1920 ∧ loaderBlock 2 = 1236 ∧ drainBytes 2 128 = 81920 ∧
    mmaBlock 3 128 = 1440 ∧ mmaBlock 4 128 = 1920 ∧ loaderBlock 4 = 1236 ∧ drainBytes 4 128 = 98304 ∧
    ddrBlock gStream 4 128 = 6005 ∧ ddrBlock gStream 8 128 = 3002 := by decide
/-- CORRECTION (row 7, §6.2 "R_drain ≥ 13.6 GB/s/core at mt = 4", "640 B per token"): the drain is hidden
    iff R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1 / 2 / 3 / 4 (80 / 160 / 288 / 384 B per
    token: C_s 64·mt + C_o 16·mt·(512/block)); in integer tenths the iff thresholds are 35 / 69 / 123 / 164
    (the round-1 "3.4" is 3.41 rounded; at exactly 34 tenths the drain is 36 ns over the block) -/
theorem T2_drain_threshold (Rd : Nat) (h : 0 < Rd) :
    (drainBlock 1 128 Rd ≤ ddrBlock gStream 1 128 ↔ 35 ≤ Rd) ∧
    (drainBlock 2 128 Rd ≤ ddrBlock gStream 2 128 ↔ 69 ≤ Rd) ∧
    (drainBlock 3 128 Rd ≤ ddrBlock gStream 3 128 ↔ 123 ≤ Rd) ∧
    (drainBlock 4 128 Rd ≤ ddrBlock gStream 4 128 ↔ 164 ≤ Rd) := by
  have e1 : ddrBlock gStream 1 128 = 12011 := by decide
  have e2 : ddrBlock gStream 2 128 = 12011 := by decide
  have e3 : ddrBlock gStream 3 128 = 6005 := by decide
  have e4 : ddrBlock gStream 4 128 = 6005 := by decide
  have d1 : drainBytes 1 128 = 40960 := by decide
  have d2 : drainBytes 2 128 = 81920 := by decide
  have d3 : drainBytes 3 128 = 73728 := by decide
  have d4 : drainBytes 4 128 = 98304 := by decide
  rw [e1, e2, e3, e4]
  unfold drainBlock tn
  rw [d1, d2, d3, d4]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> rw [Nat.div_le_iff_le_mul_add_pred h] <;> constructor <;> intro hh <;> omega
theorem T2_drain_cells : drainBlock 1 128 34 = 12047 ∧ drainBlock 1 128 35 = 11702 ∧ drainBlock 4 128 164 = 5994 ∧
    drainBlock 4 128 163 = 6030 ∧ drainBytes 4 128 / 256 = 384 ∧ drainBytes 1 128 / 512 = 80 ∧
    rateT 98304 6005 = 164 ∧ 98304 * 10 / 12011 = 81 := by decide
/-- CORRECTION (§9 "scalar-bound only if σ_s > 47 ns"): the 256-compare tail reaches the block iff σ_s ≥ 47 ns -/
theorem T2_sigma (sigma : Nat) : (ddrBlock gStream 1 128 ≤ scalarBlock 1 sigma ↔ 47 ≤ sigma) ∧
    8192 * 2 = 16384 ∧ x10 16384 12011 = 13 ∧ (2 * 16384 * 10 + 12011) / (2 * 12011) = 14 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  rw [e]; unfold scalarBlock
  refine ⟨?_, by decide, by decide, by decide⟩
  constructor <;> intro h <;> omega
/-- CORRECTION (§7, §9 d = 64: "MMA share 16 %·mt", "c_V ≤ 31 / 15"): at d = 64 a 512-token block streams in
    6 005 ns; the scores need 2 (16,16,32) calls per 16 tokens (k = 64 is illegal) and PV 4 per 128 tokens:
    80 calls = 1 200 ns = 20.0 %·mt; t = 1 stays DDR-bound iff c_V ≤ 30 (ρ32 = 1) / 14 (ρ32 = 2) -/
theorem T2_d64 (cV : Nat) : ddrBlock gStream 1 64 = 6005 ∧ mmaCalls 1 64 = 80 ∧ mmaBlock 1 64 = 1200 ∧
    pct 1200 6005 = 200 ∧ (vecBlock cV 1 1 mergeOps ≤ ddrBlock gStream 1 64 ↔ cV ≤ 30) ∧
    (vecBlock cV 2 1 mergeOps ≤ ddrBlock gStream 1 64 ↔ cV ≤ 14) := by
  have e : ddrBlock gStream 1 64 = 6005 := by decide
  have hb : blockOf 1 = 512 := by decide
  refine ⟨e, by decide, by decide, by decide, ?_, ?_⟩ <;> rw [e] <;> unfold vecBlock mergeOps rVecCore <;> rw [hb] <;>
    constructor <;> intro h <;> omega

/-! ## T3 — the vector unit: cells, the GQA theorem, rows*, thresholds (`[A2-vec-*]` `[A3-*]` `[A4b-*]`, rows 8–11) -/
theorem T3_vec_cells : vecBlock 7 1 1 mergeOps = 1489 ∧ vecBlock 7 2 1 mergeOps = 2978 ∧
    vecBlock 12 1 1 mergeOps = 2437 ∧ vecBlock 12 2 1 mergeOps = 4875 ∧ vecBlock 28 1 1 mergeOps = 5471 ∧
    vecBlock 28 2 1 mergeOps = 10943 ∧ vecBlock 33 1 1 mergeOps = 6419 ∧ vecBlock 33 2 1 mergeOps = 12839 ∧
    pct 1489 12011 = 124 ∧ pct 2978 12011 = 248 ∧ pct 2437 12011 = 203 ∧ pct 4875 12011 = 406 ∧
    pct 5471 12011 = 455 ∧ pct 10943 12011 = 911 ∧ pct 6419 12011 = 534 ∧ pct 12839 12011 = 1069 ∧
    12839 - 12011 = 828 := by decide
/-- the four c_V corners are the op table of §3.2: c_V = 2 + R + 1 + E + 1 + 1 -/
theorem T3_cV_table : cVof eNative rNative = 7 ∧ cVof eNative rTree = 12 ∧ cVof polyOps rNative = 28 ∧
    cVof polyOps rTree = 33 ∧ polyOps = 22 := by decide

/-- T_gqa_matrix (general form): the vector-dot route (4·rows·d lane-ops per token at the f32 penalty ρ32)
    takes longer than the per-core KV stream of one token (4d bytes at 174.6/8 GB/s) whenever rows·ρ32 ≥ 2:
    cross-multiplied, 4d·80·432 < 4·rows·d·ρ32·10·1746. Holds for EVERY head dim d > 0 (d cancels). -/
theorem T_gqa_matrix (rows rho d : Nat) (hd : 0 < d) (h : 2 ≤ rows * rho) :
    4 * d * 80 * 432 < 4 * rows * d * rho * 10 * 1746 := by
  have e1 : 4 * rows * d * rho * 10 * 1746 = 4 * d * (rows * rho * 10 * 1746) := by ac_rfl
  have e2 : 4 * d * 80 * 432 = 4 * d * (80 * 432) := by ac_rfl
  rw [e1, e2]
  apply (Nat.mul_lt_mul_left (by omega)).mpr
  have := Nat.mul_le_mul_right (10 * 1746) h
  omega
/-- hence for every GQA group g ≥ 2, every t ≥ 1 and either lane rate the dot route is compute-bound (rows = t·g) -/
theorem T_gqa_matrix_g (t g rho d : Nat) (hd : 0 < d) (hg : 2 ≤ g) (ht : 1 ≤ t) (hr : 1 ≤ rho) :
    4 * d * 80 * 432 < 4 * rowsOf t g * d * rho * 10 * 1746 := by
  apply T_gqa_matrix (rowsOf t g) rho d hd
  unfold rowsOf
  have h1 : g ≤ t * g := Nat.le_mul_of_pos_left g ht
  have h2 : t * g ≤ t * g * rho := Nat.le_mul_of_pos_right (t * g) hr
  omega

/-- the ratio cells of `[A3-vecroute-*]`: 50.5 %·rows·ρ32, and d cancels exactly for every d > 0 -/
theorem T3_vecroute_cells : dotRatioT 1 1 128 = 505 ∧ dotRatioT 2 1 128 = 1010 ∧ dotRatioT 4 1 128 = 2020 ∧
    dotRatioT 8 1 128 = 4041 ∧ dotRatioT 16 1 128 = 8083 ∧ dotRatioT 1 2 128 = 1010 ∧ dotRatioT 2 2 128 = 2020 ∧
    dotRatioT 4 2 128 = 4041 ∧ dotRatioT 8 2 128 = 8083 ∧ dotRatioT 16 2 128 = 16166 ∧ dotRatioT 8 1 64 = 4041 := by decide
theorem T3_vecroute_d_cancels (rows rho d : Nat) (hd : 0 < d) :
    dotRatioT rows rho d = rows * rho * 1746 * 10000 / (80 * 432) := by
  unfold dotRatioT coreTok rGemm rVecCore
  have e1 : rows * rho * 4 * d * 1746 * 10000 = (4 * d) * (rows * rho * 1746 * 10000) := by ac_rfl
  have e2 : 80 * (4 * d) * 432 = (4 * d) * (80 * 432) := by ac_rfl
  rw [e1, e2, Nat.mul_div_mul_left _ _ (by omega)]
/-- at rows = 1, ρ32 = 1 (no GQA) the dot route is NOT compute-bound (50.5 %): the strict inequality needs rows·ρ32 ≥ 2 -/
theorem T3_vecroute_rows1 : 4 * 1 * 128 * 1 * 10 * 1746 < 4 * 128 * 80 * 432 ∧ dotRatioT 1 1 128 < 1000 := by decide

/-- rows* (row 11): the least fragment count at which the vector chain reaches the block's DDR time, per corner,
    under the block rule blockOf (512 / 256 / 128 tokens). CORRECTION: (native, native, ρ32 = 1) is 112 rows
    (mt = 7), not 128; the two-pass design caps mt at 4 so that corner never binds within a pass. -/
theorem T3_rows_star :
    (ddrBlock gStream 7 128 ≤ vecBlock 7 1 7 mergeOps ∧ ∀ mt, mt < 7 → vecBlock 7 1 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 4 128 ≤ vecBlock 7 2 4 mergeOps ∧ ∀ mt, mt < 4 → vecBlock 7 2 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 5 128 ≤ vecBlock 12 1 5 mergeOps ∧ ∀ mt, mt < 5 → vecBlock 12 1 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 3 128 ≤ vecBlock 12 2 3 mergeOps ∧ ∀ mt, mt < 3 → vecBlock 12 2 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 3 128 ≤ vecBlock 28 1 3 mergeOps ∧ ∀ mt, mt < 3 → vecBlock 28 1 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 2 128 ≤ vecBlock 28 2 2 mergeOps ∧ ∀ mt, mt < 2 → vecBlock 28 2 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 2 128 ≤ vecBlock 33 1 2 mergeOps ∧ ∀ mt, mt < 2 → vecBlock 33 1 mt mergeOps < ddrBlock gStream mt 128) ∧
    (ddrBlock gStream 1 128 ≤ vecBlock 33 2 1 mergeOps) := by decide
theorem T3_rows_star_rows : 7 * 16 = 112 ∧ ceilDiv 112 8 = 14 ∧ 4 * 16 = 64 ∧ 5 * 16 = 80 ∧ 3 * 16 = 48 ∧ 2 * 16 = 32 ∧
    vecBlock 7 1 8 mergeOps = 3951 ∧ ddrBlock gStream 8 128 = 3002 := by decide
/-- within the two-pass design (mt ≤ 4) the native corners stay under the stream: 55.0 % / 86.6 % at mt = 4 -/
theorem T3_rows_star_two_pass : pct (vecBlock 7 1 4 mergeOps) (ddrBlock gStream 4 128) = 550 ∧
    pct (vecBlock 12 1 4 mergeOps) (ddrBlock gStream 4 128) = 866 ∧ vecBlock 7 1 4 mergeOps < ddrBlock gStream 4 128 := by decide

/-- T3_t1_ddr_bound (row 9): the t = 1 block is DDR-bound iff c_V ≤ 62 (ρ32 = 1) / ≤ 30 (ρ32 = 2), as an iff over c_V -/
theorem T3_t1_ddr_bound (cV : Nat) :
    (vecBlock cV 1 1 mergeOps ≤ ddrBlock gStream 1 128 ↔ cV ≤ 62) ∧
    (vecBlock cV 2 1 mergeOps ≤ ddrBlock gStream 1 128 ↔ cV ≤ 30) := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  have hb : blockOf 1 = 512 := by decide
  rw [e]; unfold vecBlock mergeOps rVecCore; rw [hb]
  constructor <;> constructor <;> intro h <;> omega
theorem T3_t1_ddr_bound_edges : vecBlock 62 1 1 mergeOps = 11919 ∧ vecBlock 63 1 1 mergeOps = 12108 ∧
    vecBlock 30 2 1 mergeOps = 11701 ∧ vecBlock 31 2 1 mergeOps = 12081 := by decide
/-- CORRECTION (§0, §3.2 "a native exp at c_exp ≤ 55 (ρ32 = 1) / ≤ 23 (ρ32 = 2) beats the polynomial"): with
    c_V = c_exp + R + 5 the t = 1 DDR-bound condition is c_exp ≤ 56 / 51 (native / tree max) at ρ32 = 1 and
    ≤ 24 / 19 at ρ32 = 2; "beats the polynomial" (22 ops) is c_exp ≤ 21 -/
theorem T3_cexp_threshold (cExp : Nat) :
    (cVof cExp rNative ≤ 62 ↔ cExp ≤ 56) ∧ (cVof cExp rTree ≤ 62 ↔ cExp ≤ 51) ∧
    (cVof cExp rNative ≤ 30 ↔ cExp ≤ 24) ∧ (cVof cExp rTree ≤ 30 ↔ cExp ≤ 19) ∧ (cExp < polyOps ↔ cExp ≤ 21) := by
  unfold cVof rNative rTree polyOps; omega
/-- `[A4b-G-threshold]`: on the worst corner the t = 1 block is DDR-bound iff G ≤ 163.3 (so page64k is DDR-bound, stream is vector-bound) -/
theorem T3_G_threshold (G : Nat) (hG : 0 < G) : vecBlock cvWorst 2 1 mergeOps ≤ ddrBlock G 1 128 ↔ G ≤ 1633 := by
  have hv : vecBlock cvWorst 2 1 mergeOps = 12839 := by decide
  have hb : blockOf 1 = 512 := by decide
  rw [hv]; unfold ddrBlock tn coreTok; rw [hb]
  show 12839 ≤ 20971520 / G ↔ G ≤ 1633
  rw [Nat.le_div_iff_mul_le hG]; constructor <;> intro h <;> omega
/-- the merge count is an ASSUMPTION (7 000, not itemised in §3.1): the t = 1 native corner stays DDR-bound for
    every merge ≤ 461 574 lane-ops; an itemisation of §3.1's own op list gives 12 128, which moves the t = 1
    32k cell by 238 ns and the S4 variant from 1 032 to 1 277 µs -/
theorem T3_merge_threshold (merge : Nat) : vecBlock cvNat 1 1 merge ≤ ddrBlock gStream 1 128 ↔ merge ≤ 461574 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  have hb : blockOf 1 = 512 := by decide
  rw [e]; unfold vecBlock cvNat rVecCore; rw [hb]
  constructor <;> intro h <;> omega
theorem T3_merge_itemised : 4 * 2048 + 3 * 1024 + 2 * 256 + 22 * 16 = 12128 ∧
    stepNs 32768 1 gH dH gStream cvNat 1 rDrainA 12128 .hidden false = 776016 ∧
    stepNs 32768 16 gH dH gStream cvNat 1 rDrainA 12128 .hidden true = 1277307 ∧
    stepNs 1048576 16 gH dH gStream cvNat 1 rDrainA 12128 .hidden true = 40163707 ∧
    vecBlock cvNat 1 1 12128 = 1608 := by decide

/-! ## T4 — predicted step times (`[A4-*]`, rows 12–16): one theorem per L for t = 1, the drain-on-vector rows,
    t = 16 two-pass, S4 single-pass, KV-int8 -/
/-- t = 1, mt = 1, one pass: 6 branch cells per L (stream / page64k / gather3x × native / worst), in-kernel ns -/
theorem T4_t1_4k : stepH 4096 1 gStream cvNat 1 = 103162 ∧ stepH 4096 1 gStream cvWorst 2 = 132486 ∧
    stepH 4096 1 gPage64k cvNat 1 = 119146 ∧ stepH 4096 1 gPage64k cvWorst 2 = 141846 ∧
    stepH 4096 1 gGather3x cvNat 1 = 295338 ∧ stepH 4096 1 gGather3x cvWorst 2 = 318038 ∧
    usR 103162 = 103 ∧ usR 132486 = 132 ∧ usR 119146 = 119 ∧ usR 141846 = 142 ∧ usR 295338 = 295 ∧ usR 318038 = 318 ∧
    usR (wallNs 103162) = 194 ∧ effRate 4096 8 128 1 103162 = 1626 ∧ pct 103162 tGemvUnit = 259 := by decide
theorem T4_t1_32k : stepH 32768 1 gStream cvNat 1 = 775778 ∧ stepH 32768 1 gStream cvWorst 2 = 851470 ∧
    stepH 32768 1 gPage64k cvNat 1 = 903650 ∧ stepH 32768 1 gPage64k cvWorst 2 = 926350 ∧
    stepH 32768 1 gGather3x cvNat 1 = 2313186 ∧ stepH 32768 1 gGather3x cvWorst 2 = 2335886 ∧
    usR 775778 = 776 ∧ usR 851470 = 851 ∧ usR 903650 = 904 ∧ usR 926350 = 926 ∧ usR 2313186 = 2313 ∧ usR 2335886 = 2336 ∧
    usR (wallNs 775778) = 867 ∧ effRate 32768 8 128 1 775778 = 1730 ∧ pct 775778 tGemvUnit = 1949 := by decide
theorem T4_t1_128k : stepH 131072 1 gStream cvNat 1 = 3081890 ∧ stepH 131072 1 gStream cvWorst 2 = 3316558 ∧
    stepH 131072 1 gPage64k cvNat 1 = 3593378 ∧ stepH 131072 1 gPage64k cvWorst 2 = 3616078 ∧
    stepH 131072 1 gGather3x cvNat 1 = 9231522 ∧ stepH 131072 1 gGather3x cvWorst 2 = 9254222 ∧
    usR 3081890 = 3082 ∧ usR 3316558 = 3317 ∧ usR 3593378 = 3593 ∧ usR 3616078 = 3616 ∧ usR 9231522 = 9232 ∧
    usR 9254222 = 9254 ∧ effRate 131072 8 128 1 3081890 = 1742 ∧ pct 3081890 tGemvUnit = 7743 := by decide
theorem T4_t1_1M : stepH 1048576 1 gStream cvNat 1 = 24605602 ∧ stepH 1048576 1 gStream cvWorst 2 = 26324046 ∧
    stepH 1048576 1 gPage64k cvNat 1 = 28697506 ∧ stepH 1048576 1 gPage64k cvWorst 2 = 28720206 ∧
    stepH 1048576 1 gGather3x cvNat 1 = 73802658 ∧ stepH 1048576 1 gGather3x cvWorst 2 = 73825358 ∧
    usR 24605602 = 24606 ∧ usR 26324046 = 26324 ∧ usR 28697506 = 28698 ∧ usR 28720206 = 28720 ∧
    usR 73802658 = 73803 ∧ usR 73825358 = 73825 ∧ effRate 1048576 8 128 1 24605602 = 1746 ∧
    pct 24605602 tGemvUnit = 61823 ∧ usR (wallNs 24605602) = 24697 := by decide
/-- the binding engine of the t = 1 cells: the KV stream on the native corner at every G, the vector unit on the
    worst corner only at the stream rate (page64k / gather3x are DDR-bound there too) -/
theorem T4_t1_binding : blockMax gStream cvNat 1 rDrainA mergeOps 1 128 .hidden = ddrBlock gStream 1 128 ∧
    blockMax gStream cvWorst 2 rDrainA mergeOps 1 128 .hidden = vecBlock cvWorst 2 1 mergeOps ∧
    blockMax gPage64k cvWorst 2 rDrainA mergeOps 1 128 .hidden = ddrBlock gPage64k 1 128 ∧
    blockMax gGather3x cvWorst 2 rDrainA mergeOps 1 128 .hidden = ddrBlock gGather3x 1 128 := by decide
/-- fixed costs: 7 074 ns (native) / 29 774 (worst) = 2 vector blocks + 1 drain; 0 tail when 16 ∣ L -/
theorem T4_fixed : fixedNs 32768 cvNat 1 rDrainA mergeOps 1 1 128 = 7074 ∧ fixedNs 32768 cvWorst 2 rDrainA mergeOps 1 1 128 = 29774 ∧
    fixedNs 32768 cvNat 1 rDrainA mergeOps 4 8 128 = 16434 ∧ fixedNs 32768 cvWorst 2 rDrainA mergeOps 4 8 128 = 62484 ∧
    pct 91000 103162 = 882 ∧ pct 7074 103162 = 69 ∧ pct 91000 775778 = 117 ∧ pct 7074 775778 = 9 ∧
    pct 91000 24605602 = 4 ∧ 7074 * 100000 / 24605602 = 28 := by decide
/-- row 13: the drain executed by the vector engine — worst corner 165 / 1 114 / 4 365 / 34 713 µs, native unchanged -/
theorem T4_t1_drain_same : stepHsame 4096 1 gStream cvWorst 2 = 165254 ∧ stepHsame 32768 1 gStream cvWorst 2 = 1113614 ∧
    stepHsame 131072 1 gStream cvWorst 2 = 4365134 ∧ stepHsame 1048576 1 gStream cvWorst 2 = 34712654 ∧
    stepHsame 32768 1 gStream cvNat 1 = 775778 ∧ stepHsame 1048576 1 gStream cvNat 1 = 24605602 ∧
    64 * (vecBlock cvNat 1 1 mergeOps + drainBlock 1 128 rDrainA) = 357440 ∧ 95296 + 262144 < 768704 ∧
    usR 1113614 = 1114 ∧ usR 34712654 = 34713 ∧ usR 165254 = 165 ∧ usR 4365134 = 4365 := by decide
/-- CORRECTION (§0 "no other unknown moves the t = 1 headline by more than 7 %", "vector-bound 1.07×"):
    the worst corner is +9.8 % at 32k (851 vs 776: 6.9 % per block plus 22.7 µs of fixed cost) and +7.0 % at
    1M; 1.07× is the per-block ratio. Drain on the vector engine: +43.5 % / +41.1 % -/
theorem T4_worst_overrun : pct (851470 - 775778) 775778 = 98 ∧ pct (26324046 - 24605602) 24605602 = 70 ∧
    29774 - 7074 = 22700 ∧ pct (1113614 - 775778) 775778 = 435 ∧ pct (34712654 - 24605602) 24605602 = 411 := by decide

/-- row 14, §6.2: t = 16 = rows 128 → two passes of mt = 4 (64 rows), 256-token blocks, KV streamed twice -/
theorem T4_t16_passes : rowsOf 16 8 = 128 ∧ passesOf 128 = 2 ∧ mtPass 128 = 4 ∧ blockOf 4 = 256 ∧ mtOf 128 = 8 ∧
    passesOf 64 = 1 ∧ mtPass 64 = 4 ∧ passesOf 65 = 2 ∧ rowsOf 8 8 = 64 ∧ rowsOf 2 8 = 16 ∧ mtPass 16 = 1 := by decide
theorem T4_t16_4k : stepH 4096 16 gStream cvNat 1 = 208594 ∧ stepH 4096 16 gStream cvWorst 2 = 904948 ∧
    stepH 4096 16 gPage64k cvNat 1 = 240562 ∧ stepH 4096 16 gPage64k cvWorst 2 = 904948 ∧
    stepH 4096 16 gGather3x cvNat 1 = 592946 ∧ stepH 4096 16 gGather3x cvWorst 2 = 904948 ∧
    usR 208594 = 209 ∧ usR 904948 = 905 ∧ usR 240562 = 241 ∧ usR 592946 = 593 ∧ effRate 4096 8 128 2 208594 = 1609 := by decide
theorem T4_t16_32k : stepH 32768 16 gStream cvNat 1 = 1553714 ∧ stepH 32768 16 gStream cvWorst 2 = 6802196 ∧
    stepH 32768 16 gPage64k cvNat 1 = 1809458 ∧ stepH 32768 16 gPage64k cvWorst 2 = 6802196 ∧
    stepH 32768 16 gGather3x cvNat 1 = 4628530 ∧ stepH 32768 16 gGather3x cvWorst 2 = 6802196 ∧
    usR 1553714 = 1554 ∧ usR 6802196 = 6802 ∧ usR 1809458 = 1809 ∧ usR 4628530 = 4629 ∧
    effRate 32768 8 128 2 1553714 = 1728 ∧ x10 6802196 1553714 = 43 ∧ (2 * 6802196 * 10 + 1553714) / (2 * 1553714) = 44 := by decide
theorem T4_t16_128k : stepH 131072 16 gStream cvNat 1 = 6165554 ∧ stepH 131072 16 gStream cvWorst 2 = 27021332 ∧
    stepH 131072 16 gPage64k cvNat 1 = 7188530 ∧ stepH 131072 16 gPage64k cvWorst 2 = 27021332 ∧
    stepH 131072 16 gGather3x cvNat 1 = 18464818 ∧ stepH 131072 16 gGather3x cvWorst 2 = 27021332 ∧
    usR 6165554 = 6166 ∧ usR 27021332 = 27021 ∧ usR 7188530 = 7189 ∧ usR 18464818 = 18465 ∧
    effRate 131072 8 128 2 6165554 = 1742 := by decide
theorem T4_t16_1M : stepH 1048576 16 gStream cvNat 1 = 49209394 ∧ stepH 1048576 16 gStream cvWorst 2 = 215733268 ∧
    stepH 1048576 16 gPage64k cvNat 1 = 57393202 ∧ stepH 1048576 16 gPage64k cvWorst 2 = 215733268 ∧
    stepH 1048576 16 gGather3x cvNat 1 = 147603506 ∧ stepH 1048576 16 gGather3x cvWorst 2 = 215733268 ∧
    usR 49209394 = 49209 ∧ usR 215733268 = 215733 ∧ usR 57393202 = 57393 ∧ usR 147603506 = 147604 ∧
    effRate 1048576 8 128 2 49209394 = 1746 := by decide
/-- t = 16 with the drain on the vector engine: the native corner becomes drain + vector-bound (3 378 µs / 107.6 ms) -/
theorem T4_t16_drain_same : stepHsame 32768 16 gStream cvNat 1 = 3378226 ∧ stepHsame 1048576 16 gStream cvNat 1 = 107593778 ∧
    usR 3378226 = 3378 ∧ 107593778 / 100000 = 1075 := by decide
/-- row 15, the t = 16 variant split. S4 = ONE pass, mt = 8, 128-token blocks, L0A exactly full (Q 32 + P 32),
    gated on E24: vector-bound by its merges, 1 032 µs / 32.4 ms on the native corner (1.5× better than two
    passes), worse than two passes on every other corner; the serial loader → MMA chain is 2 196 of 3 002 ns -/
theorem T4_s4 : stepS4 32768 gStream cvNat 1 = 1032465 ∧ stepS4 1048576 gStream cvNat 1 = 32387601 ∧
    stepS4 32768 gStream cvNat 2 = 2051823 ∧ stepS4 1048576 gStream cvNat 2 = 64762095 ∧
    stepS4 32768 gStream cvWorst 2 = 7139841 ∧ stepS4 1048576 gStream cvWorst 2 = 226355969 ∧
    stepH 32768 16 gStream cvNat 2 = 1713920 ∧ stepH 1048576 16 gStream cvNat 2 = 54131200 ∧
    usR 1032465 = 1032 ∧ 32387601 / 100000 = 323 ∧ x10 1553714 1032465 = 15 ∧ x10 49209394 32387601 = 15 ∧
    1713920 < 2051823 ∧ 6802196 < 7139841 ∧ mtOf 128 = 8 ∧ blockOf 8 = 128 ∧ pSel 128 true = 1 := by decide
theorem T4_s4_chain : tn (8 * 4096) rLoader = 1236 ∧ 64 * cMma = 960 ∧ 1236 + 960 = 2196 ∧ ddrBlock gStream 8 128 = 3002 ∧
    pct 2196 3002 = 732 ∧ vecBlock cvNat 1 8 mergeOps = 3951 ∧ 3002 < 3951 := by decide
/-- row 16: the KV-int8 variant halves the streamed bytes: 391 µs / 12.3 ms native (DDR-bound), 851 / 26.3 worst (vector-bound) -/
theorem T4_i8 : stepI8H 32768 gStream cvNat 1 = 391426 ∧ stepI8H 1048576 gStream cvNat 1 = 12306338 ∧
    stepI8H 32768 gStream cvWorst 2 = 851470 ∧ stepI8H 1048576 gStream cvWorst 2 = 26324046 ∧
    usR 391426 = 391 ∧ 12306338 / 100000 = 123 ∧ 64 * ddrBlock gStream 1 128 / 2 = 384352 := by decide

/-! ## T5 — the regime map at 32k (`[A4c-regime-*]`, row 24): 40 cells, binding engine and the vector share -/
theorem T5_regime_t1 : usR (stepH 32768 1 gStream 7 1) = 776 ∧ usR (stepH 32768 1 gStream 7 2) = 779 ∧
    usR (stepH 32768 1 gStream 12 1) = 778 ∧ usR (stepH 32768 1 gStream 12 2) = 783 ∧
    usR (stepH 32768 1 gStream 28 1) = 784 ∧ usR (stepH 32768 1 gStream 28 2) = 795 ∧
    usR (stepH 32768 1 gStream 33 1) = 786 ∧ usR (stepH 32768 1 gStream 33 2) = 851 ∧
    stepH 32768 2 gStream 7 1 = stepH 32768 1 gStream 7 1 ∧ stepH 32768 2 gStream 33 2 = stepH 32768 1 gStream 33 2 := by decide
theorem T5_regime_t4 : usR (stepH 32768 4 gStream 7 1) = 783 ∧ usR (stepH 32768 4 gStream 7 2) = 789 ∧
    usR (stepH 32768 4 gStream 12 1) = 787 ∧ usR (stepH 32768 4 gStream 12 2) = 796 ∧
    usR (stepH 32768 4 gStream 28 1) = 799 ∧ usR (stepH 32768 4 gStream 28 2) = 1453 ∧
    usR (stepH 32768 4 gStream 33 1) = 856 ∧ usR (stepH 32768 4 gStream 33 2) = 1703 ∧ mtPass 32 = 2 := by decide
theorem T5_regime_t8 : usR (stepH 32768 8 gStream 7 1) = 785 ∧ usR (stepH 32768 8 gStream 7 2) = 868 ∧
    usR (stepH 32768 8 gStream 12 1) = 789 ∧ usR (stepH 32768 8 gStream 12 2) = 1362 ∧
    usR (stepH 32768 8 gStream 28 1) = 1475 ∧ usR (stepH 32768 8 gStream 28 2) = 2939 ∧
    usR (stepH 32768 8 gStream 33 1) = 1721 ∧ usR (stepH 32768 8 gStream 33 2) = 3432 ∧ x10 3432 785 = 43 := by decide
theorem T5_regime_t16 : usR (stepH 32768 16 gStream 7 1) = 1554 ∧ usR (stepH 32768 16 gStream 7 2) = 1714 ∧
    usR (stepH 32768 16 gStream 12 1) = 1558 ∧ usR (stepH 32768 16 gStream 12 2) = 2693 ∧
    usR (stepH 32768 16 gStream 28 1) = 2917 ∧ usR (stepH 32768 16 gStream 28 2) = 5824 ∧
    usR (stepH 32768 16 gStream 33 1) = 3406 ∧ usR (stepH 32768 16 gStream 33 2) = 6802 := by decide
/-- the binding engine per cell is the per-block comparison vec vs ddr (shares in tenths of a percent);
    CORRECTION (§7 "with the polynomial it binds from t = 8 (ρ32 = 1)"): the (poly, tree, ρ32 = 1) corner binds
    from t = 4 (106.9 %, 856 µs); only (poly, native max) waits for t = 8 -/
theorem T5_regime_binding : pct (vecBlock 7 1 4 mergeOps) (ddrBlock gStream 4 128) = 550 ∧
    pct (vecBlock 7 2 4 mergeOps) (ddrBlock gStream 4 128) = 1100 ∧ pct (vecBlock 7 2 2 mergeOps) (ddrBlock gStream 2 128) = 496 ∧
    pct (vecBlock 12 2 2 mergeOps) (ddrBlock gStream 2 128) = 812 ∧ pct (vecBlock 28 1 2 mergeOps) (ddrBlock gStream 2 128) = 911 ∧
    pct (vecBlock 28 2 2 mergeOps) (ddrBlock gStream 2 128) = 1822 ∧ pct (vecBlock 33 1 2 mergeOps) (ddrBlock gStream 2 128) = 1069 ∧
    pct (vecBlock 33 2 2 mergeOps) (ddrBlock gStream 2 128) = 2138 ∧ pct (vecBlock 28 1 4 mergeOps) (ddrBlock gStream 4 128) = 1876 ∧
    pct (vecBlock 12 1 4 mergeOps) (ddrBlock gStream 4 128) = 866 ∧ pct (vecBlock 33 2 4 mergeOps) (ddrBlock gStream 4 128) = 4384 := by decide
/-- G scales the KV cells and never the vector cells: page64k is 1.17× on the DDR-bound cells; on gather3x the
    t = 1 and t = 16 native cells are the 3× stream and the worst t = 16 cell is unchanged -/
theorem T5_regime_G : x10 1746 1497 = 11 ∧ (2 * 1746 * 100 + 1497) / (2 * 1497) = 117 ∧ (2 * 903650 * 100 + 775778) / (2 * 775778) = 116 ∧
    stepH 32768 16 gGather3x cvWorst 2 = stepH 32768 16 gStream cvWorst 2 ∧ x10 2313186 775778 = 29 := by decide

/-! ## T_crossover — attention = one 398 µs GEMV unit (row 23, `[A4c-Leq*]`), both sides, as functions of L -/
theorem blockMax_hidden (G cV rho Rd merge mt d : Nat) : blockMax G cV rho Rd merge mt d .hidden =
    max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge)) (mmaBlock mt d)) (loaderBlock mt) := rfl
theorem blockMax_same (G cV rho Rd merge mt d : Nat) : blockMax G cV rho Rd merge mt d .same =
    max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge + drainBlock mt d Rd)) (mmaBlock mt d)) (loaderBlock mt) := rfl
/-- the closed form of the t = 1 native stream step for every L: 12 011 ns per block + 7 074 + the vector tail -/
theorem T_step_t1_form (L : Nat) :
    stepH L 1 gStream cvNat 1 = ((16 * (L / 16) + 511) / 512) * 12011 + 7074 + (L % 16) * 8192 * 10 / 432 := by
  have hb : blockMax gStream cvNat 1 rDrainA mergeOps 1 128 .hidden = 12011 := by decide
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hm : mtSel (rowsOf 1 gH) false = 1 := by decide
  have hm2 : mtOf (rowsOf 1 gH) = 1 := by decide
  have hv : vecBlock cvNat 1 1 mergeOps = 1489 := by decide
  have hd : drainBlock 1 128 rDrainA = 4096 := by decide
  have hbl : blockOf 1 = 512 := by decide
  unfold stepH stepNs dH
  rw [hp, hm, hm2, hb]
  unfold fixedNs tailNs tailOps nblocks lMatrix ceilDiv rVecCore
  rw [hv, hd, hbl]
  omega
/-- the 512-multiples: step(512·k) ≥ 398 µs ⟺ k ≥ 33, i.e. L_eq = 16 896 (403.4 µs there, 391.4 at 16 384) -/
theorem T_crossover (k : Nat) : (tGemvUnit ≤ stepH (512 * k) 1 gStream cvNat 1 ↔ 33 ≤ k) ∧
    stepH 16896 1 gStream cvNat 1 = 403437 ∧ stepH 16384 1 gStream cvNat 1 = 391426 ∧ 33 * 512 = 16896 := by
  refine ⟨?_, by decide, by decide, by decide⟩
  rw [T_step_t1_form]; unfold tGemvUnit
  constructor <;> intro h <;> omega
/-- over EVERY L: step(L) ≥ 398 µs ⟺ L ≥ 16 400 — the 33rd block is charged in full from its first 16-token
    group (the model's partial-block charge is conservative by ≤ one block); the max over L < 16 400 is 394 270 ns -/
theorem T_crossover_anyL (L : Nat) : tGemvUnit ≤ stepH L 1 gStream cvNat 1 ↔ 16400 ≤ L := by
  rw [T_step_t1_form]; unfold tGemvUnit
  constructor <;> intro h <;> omega
theorem T_crossover_anyL_cells : stepH 16400 1 gStream cvNat 1 = 403437 ∧ stepH 16399 1 gStream cvNat 1 = 394270 ∧
    stepH 16384 1 gStream cvNat 1 = 391426 ∧ 15 * 8192 * 10 / 432 = 2844 := by decide
/-- the same bytes at the measured 174.6 are a 384 µs unit: the crossover moves to the 512-multiple 16 384 -/
theorem T_crossover_384 (k : Nat) : tn gemvBytes rGemm = 384364 ∧ (384364 ≤ stepH (512 * k) 1 gStream cvNat 1 ↔ 32 ≤ k) ∧
    stepH 15872 1 gStream cvNat 1 = 379415 := by
  refine ⟨by decide, ?_, by decide⟩
  rw [T_step_t1_form]
  constructor <;> intro h <;> omega
/-- the attention fractions of the GEMV unit (row 23) and per DESIGN-4 layer (§6.3): 4.2 % / 134.8 % dense, 24.2 % MoE at 32k -/
theorem T_fraction : pct 103162 tGemvUnit = 259 ∧ pct 775778 tGemvUnit = 1949 ∧ pct 3081890 tGemvUnit = 7743 ∧
    pct 24605602 tGemvUnit = 61823 ∧ pct 775778 tLayerDense = 42 ∧ pct 24605602 tLayerDense = 1348 ∧
    pct 775778 tLayerMoe = 242 := by decide

/-! ## T_fleet_G — the E21-relevant statement: the gather rate each DESIGN-4 fleet cell needs (`[A4d-fleet-G-*]`) -/
/-- for G ≤ 174.6 the native t = 1 block is DDR-bound, so the step is nb·⌊20 971 520/G⌋ + 7 074 (+ tail) for every L -/
theorem T_step_t1_G_form (L G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    stepH L 1 G cvNat 1 = ((16 * (L / 16) + 511) / 512) * (20971520 / G) + 7074 + (L % 16) * 8192 * 10 / 432 := by
  have hb : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 128 = 20971520 / G := by
    unfold ddrBlock tn coreTok; rw [hb]
  have hge : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  have hmax : blockMax G cvNat 1 rDrainA mergeOps 1 128 .hidden = 20971520 / G := by
    rw [blockMax_hidden, hddr]
    have hv : vecBlock cvNat 1 1 mergeOps = 1489 := by decide
    have hm : mmaBlock 1 128 = 960 := by decide
    have hl : loaderBlock 1 = 618 := by decide
    rw [hv, hm, hl, Nat.max_eq_left (by omega), Nat.max_eq_left (by omega), Nat.max_eq_left (by omega)]
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hm : mtSel (rowsOf 1 gH) false = 1 := by decide
  have hm2 : mtOf (rowsOf 1 gH) = 1 := by decide
  have hv : vecBlock cvNat 1 1 mergeOps = 1489 := by decide
  have hd : drainBlock 1 128 rDrainA = 4096 := by decide
  unfold stepH stepNs dH
  rw [hp, hm, hm2, hmax]
  unfold fixedNs tailNs tailOps nblocks lMatrix ceilDiv rVecCore
  rw [hv, hd, hb]
  simp only [Nat.one_mul, Nat.mul_one]
  have ha : (16 * (L / 16) + 512 - 1) / 512 = (16 * (L / 16) + 511) / 512 := by omega
  rw [ha]
  omega
/-- a fleet cell (shape, L) is attention-bound iff G ≤ G*(shape, L); G* in tenths: dense 7.3 / 29.4 at 32k / 128k,
    MoE 41.9 / 167.7 — the MoE 128k cell flips to attention-bound already at c_pg ≥ 123 ns (G ≤ 167.7); both 1M
    cells are attention-bound at every G ≤ 174.6 -/
theorem T_fleet_G_dense_32k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    tLayerDense ≤ stepH 32768 1 G cvNat 1 ↔ G ≤ 73 := by
  rw [T_step_t1_G_form 32768 G h1 h2]; unfold tLayerDense
  have key : 285155 ≤ 20971520 / G ↔ G ≤ 73 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T_fleet_G_dense_128k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    tLayerDense ≤ stepH 131072 1 G cvNat 1 ↔ G ≤ 294 := by
  rw [T_step_t1_G_form 131072 G h1 h2]; unfold tLayerDense
  have key : 71289 ≤ 20971520 / G ↔ G ≤ 294 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T_fleet_G_dense_1M (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerDense ≤ stepH 1048576 1 G cvNat 1 := by
  rw [T_step_t1_G_form 1048576 G h1 h2]; unfold tLayerDense
  have : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  omega
theorem T_fleet_G_moe_32k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    tLayerMoe ≤ stepH 32768 1 G cvNat 1 ↔ G ≤ 419 := by
  rw [T_step_t1_G_form 32768 G h1 h2]; unfold tLayerMoe
  have key : 50011 ≤ 20971520 / G ↔ G ≤ 419 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T_fleet_G_moe_128k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    tLayerMoe ≤ stepH 131072 1 G cvNat 1 ↔ G ≤ 1677 := by
  rw [T_step_t1_G_form 131072 G h1 h2]; unfold tLayerMoe
  have key : 12503 ≤ 20971520 / G ↔ G ≤ 1677 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T_fleet_G_moe_1M (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerMoe ≤ stepH 1048576 1 G cvNat 1 := by
  rw [T_step_t1_G_form 1048576 G h1 h2]; unfold tLayerMoe
  have : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  omega
/-- the same thresholds as per-page costs at 64 KiB pages (G(64 KiB, c_pg) ≥ G* + 1 ⟺ c_pg ≤ …): MoE 128k needs
    c_pg ≤ 122 ns, MoE 32k ≤ 9 481 ns, dense 128k ≤ 14 770 ns, dense 32k ≤ 67 847 ns; the page64k branch (0.5 µs)
    and the gather3x branch both flip the MoE 128k cell, neither flips the MoE 32k cell -/
theorem T_fleet_G_cpg : gPage pageB 122 = 1678 ∧ gPage pageB 123 = 1677 ∧ gPage pageB 9481 = 420 ∧ gPage pageB 9482 = 419 ∧
    gPage pageB 14770 = 295 ∧ gPage pageB 14771 = 294 ∧ gPage pageB 67847 = 74 ∧ gPage pageB 67848 = 73 ∧
    gPage64k ≤ 1677 ∧ gGather3x ≤ 1677 ∧ 419 < gGather3x ∧ 294 < gGather3x ∧ 73 < gGather3x := by decide
/-- the ∀-G bracket of the headline cells (row 12): for every G in [582, 1746] the native t = 1 step is between the
    stream and the gather3x values -/
theorem T_step_t1_G_bracket (G : Nat) (h1 : gGather3x ≤ G) (h2 : G ≤ gStream) :
    (775778 ≤ stepH 32768 1 G cvNat 1 ∧ stepH 32768 1 G cvNat 1 ≤ 2313186) ∧
    (24605602 ≤ stepH 1048576 1 G cvNat 1 ∧ stepH 1048576 1 G cvNat 1 ≤ 73802658) := by
  have hg : 0 < G := by unfold gGather3x rGemm at h1; omega
  rw [T_step_t1_G_form 32768 G hg h2, T_step_t1_G_form 1048576 G hg h2]
  have ha := Nat.div_le_div_left (a := 20971520) h2 hg
  have hb := Nat.div_le_div_left (a := 20971520) h1 (by unfold gGather3x rGemm; decide)
  have e1 : 20971520 / gStream = 12011 := by decide
  have e2 : 20971520 / gGather3x = 36033 := by decide
  omega
/-- the worst corner over the same bracket at 32k: between 851 470 (vector-bound at the stream rate) and 2 335 886 -/
theorem T_step_t1_worst_G_bracket (G : Nat) (h1 : gGather3x ≤ G) (h2 : G ≤ gStream) :
    851470 ≤ stepH 32768 1 G cvWorst 2 ∧ stepH 32768 1 G cvWorst 2 ≤ 2335886 := by
  have hg : 0 < G := by unfold gGather3x rGemm at h1; omega
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 128 = 20971520 / G := by unfold ddrBlock tn coreTok; rw [hbl]
  have ha := Nat.div_le_div_left (a := 20971520) h2 hg
  have hb := Nat.div_le_div_left (a := 20971520) h1 (by unfold gGather3x rGemm; decide)
  have e1 : 20971520 / gStream = 12011 := by decide
  have e2 : 20971520 / gGather3x = 36033 := by decide
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hm : mtSel (rowsOf 1 gH) false = 1 := by decide
  have hm2 : mtOf (rowsOf 1 gH) = 1 := by decide
  have hv : vecBlock cvWorst 2 1 mergeOps = 12839 := by decide
  have hmm : mmaBlock 1 128 = 960 := by decide
  have hl : loaderBlock 1 = 618 := by decide
  have hfix : fixedNs 32768 cvWorst 2 rDrainA mergeOps 1 1 128 = 29774 := by decide
  have hnb : nblocks 32768 1 = 64 := by decide
  unfold stepH stepNs dH
  rw [hp, hm, hm2, hnb, hfix, blockMax_hidden, hddr, hv, hmm, hl]
  have hx : max (max (max (20971520 / G) 12839) 960) 618 = max (20971520 / G) 12839 := by
    rw [Nat.max_eq_left (by omega), Nat.max_eq_left (by omega)]
  rw [hx]
  have hlo : 12839 ≤ max (20971520 / G) 12839 := Nat.le_max_right _ _
  have hhi : max (20971520 / G) 12839 ≤ 36033 := Nat.max_le.mpr ⟨by omega, by decide⟩
  omega
/-- the c_V × ρ32 bracket at t = 1 (row 12): on every corner with the vector block ≤ 12 011 ns the 32k stream cell is
    exactly 768 704 + fixed, and fixed ≤ 28 118 — the vector corner can move the DDR-bound cell by at most 2.7 % -/
theorem T_step_t1_cV_bracket (cV rho : Nat) (hc : vecBlock cV rho 1 mergeOps ≤ 12011) :
    stepH 32768 1 gStream cV rho = 768704 + fixedNs 32768 cV rho rDrainA mergeOps 1 1 128 ∧
    fixedNs 32768 cV rho rDrainA mergeOps 1 1 128 ≤ 28118 := by
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hm : mtSel (rowsOf 1 gH) false = 1 := by decide
  have hm2 : mtOf (rowsOf 1 gH) = 1 := by decide
  have hnb : nblocks 32768 1 = 64 := by decide
  have hddr : ddrBlock gStream 1 128 = 12011 := by decide
  have hmm : mmaBlock 1 128 = 960 := by decide
  have hl : loaderBlock 1 = 618 := by decide
  have hd : drainBlock 1 128 rDrainA = 4096 := by decide
  have ht : tailNs 32768 1 128 rho = 0 := by unfold tailNs tailOps; simp
  constructor
  · unfold stepH stepNs dH
    rw [hp, hm, hm2, hnb, blockMax_hidden, hddr, hmm, hl, Nat.max_eq_left hc, Nat.max_eq_left (by omega),
      Nat.max_eq_left (by omega)]
  · unfold fixedNs; rw [hd, ht]; omega

/-! ## T_buffers — every SRAM buffer is a function of (mt, d, blk) only; no O(L) SRAM (row 21, `[A7-*]`) -/
/-- structural: the SRAM totals do not read the L field of the configuration — rewriting L changes nothing -/
theorem T_buffers_no_OL (c : Cfg) (L' : Nat) (win : Nat) :
    usTotal { c with L := L' } win = usTotal c win ∧ l0cTotal { c with L := L' } = l0cTotal c ∧
    l0aTotal { c with L := L' } = l0aTotal c ∧ s1Total { c with L := L' } = s1Total c ∧ l0bRing = l0bRing :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩
/-- the only O(L) objects live in DDR and are linear in L: KV bytes and the page tables (monotone) -/
theorem T_buffers_OL_in_DDR (L L' : Nat) (h : L ≤ L') : kvBytes L 8 128 ≤ kvBytes L' 8 128 ∧
    pageTableBytes L 8 pageB 128 ≤ pageTableBytes L' 8 pageB 128 := by
  constructor
  · unfold kvBytes; exact Nat.mul_le_mul_right _ h
  · unfold pageTableBytes ceilDiv
    apply Nat.mul_le_mul_left
    apply Nat.div_le_div_right; omega
/-- L0C: 112 / 224 / 192 / 256 KiB for mt = 1..4 (3 C_s regions + 2 C_o regions); mt = 4 fills L0C exactly -/
theorem T_buffers_l0c : l0cTotal (cfgH 1 0) = 112 * KiB ∧ l0cTotal (cfgH 2 0) = 224 * KiB ∧ l0cTotal (cfgH 3 0) = 192 * KiB ∧
    l0cTotal (cfgH 4 0) = 256 * KiB ∧ l0cTotal (cfgH 4 0) = l0cCap ∧ csRegion (cfgH 1 0) = 32 * KiB ∧
    csRegion (cfgH 4 0) = 64 * KiB ∧ coRegion (cfgH 4 0) = 32 * KiB ∧ 2 * csRegion (cfgH 4 0) + 2 * coRegion (cfgH 4 0) = 192 * KiB := by decide
/-- CORRECTION (§2.4 "L0A = 16 + 2·16 = 48 KiB", appendix "L0A 16/48"): with +Q and −Q resident (§3.2, §4) and a
    double-buffered P set, L0A = 16 KiB·mt: 16 / 32 / 48 / 64 KiB for mt = 1..4 — exactly full at mt = 4, which is
    what forces the 64-row pass cap (mt = 5 would need 80 KiB) -/
theorem T_buffers_l0a (mt : Nat) : l0aTotal (cfgH mt 0) = 16 * KiB * mt ∧ l0aTotal (cfgH 4 0) = l0aCap ∧
    l0aTotal (cfgH 1 0) = 16 * KiB ∧ l0aTotal (cfgH 5 0) = 80 * KiB ∧ l0aCap < l0aTotal (cfgH 5 0) ∧
    (l0aTotal (cfgH mt 0) ≤ l0aCap ↔ mt ≤ 4) := by
  refine ⟨?_, by decide, by decide, by decide, by decide, ?_⟩
  · unfold l0aTotal l0aQ l0aP cfgH fragB KiB; dsimp only; omega
  · unfold l0aTotal l0aQ l0aP cfgH fragB l0aCap; dsimp only; constructor <;> intro h <;> omega
/-- CORRECTION (§4 "US total 200 KiB at mt = 1 (≤ 208 evidenced)"): the table's own rows sum to 213 056 B =
    208 KiB + 64 B with one page-table window buffer (217 152 = 212 KiB + 64 B with the declared depth 2) —
    over the 208 KiB evidence by 64 B / 4 160 B; mt = 2: 204 KiB + 64 B (not 164), mt = 3: 200 KiB + 64 B,
    mt = 4: 196 KiB + 64 B (not 180). The Z-reset branch is 112 / 116 KiB + 64 B at mt = 1. -/
theorem T_buffers_us : usTotal (cfgH 1 0) 1 = 213056 ∧ usTotal (cfgH 1 0) 2 = 217152 ∧ usTotal (cfgH 2 0) 1 = 208960 ∧
    usTotal (cfgH 3 0) 1 = 204864 ∧ usTotal (cfgH 4 0) 1 = 200768 ∧ usTotal (cfgH 2 0) 2 = 213056 ∧ usTotal (cfgH 4 0) 2 = 204864 ∧
    213056 = 208 * KiB + 64 ∧ 217152 = 212 * KiB + 64 ∧ usEvid = 208 * KiB ∧ usEvid < usTotal (cfgH 1 0) 1 ∧
    usTotal (cfgH 1 0) 1 - usNegSnap (cfgH 1 0) = 112 * KiB + 64 ∧ usNegSnap (cfgH 1 0) = 96 * KiB ∧
    usTotal (cfgH 2 0) 1 ≤ usEvid ∧ usTotal (cfgH 4 0) 2 ≤ usEvid ∧ 200 * KiB = 204800 := by decide
/-- the round-1 sum (32 + 96 + 32 + 8 + 16 + 4 + 4 + 8 = 200 KiB) omitted the q row-major buffer and the page-table
    window of its own table; remedies the design already names: snapshots to S1 (→ 112 KiB + 64 B, as on the
    Z-reset branch) or aliasing the prologue-only q buffer onto the idle drained-C_s buffer (→ 204 KiB + 64 B) -/
theorem T_buffers_us_remedy : usTotal (cfgH 1 0) 1 - usNegSnap (cfgH 1 0) ≤ usEvid ∧
    usTotal (cfgH 1 0) 1 - usQRow (cfgH 1 0) = 204 * KiB + 64 ∧ usTotal (cfgH 1 0) 1 - usQRow (cfgH 1 0) ≤ usEvid ∧
    (32 + 96 + 32 + 8 + 16 + 4 + 4 + 8) * KiB = 200 * KiB := by decide
/-- S1 at mt ≥ 2: the P ring and the three snapshots — 208 / 168 / 224 KiB, all under the "≤ 230 KiB" claim and the ~1 MB prior -/
theorem T_buffers_s1 : s1Total (cfgH 2 0) = 208 * KiB ∧ s1Total (cfgH 3 0) = 168 * KiB ∧ s1Total (cfgH 4 0) = 224 * KiB ∧
    s1Total (cfgH 4 0) ≤ 230 * KiB ∧ s1Total (cfgH 4 0) ≤ s1Prior ∧ l0bRing = l0bCap := by decide
/-- CORRECTION (§2.4 "L0C holds two C_s regions of 128 KiB = 256 KiB"): the S4 geometry is 2 C_s regions of 64 KiB
    plus 2 C_o regions of 64 KiB = 256 KiB (exactly full), and L0A = Q 32 + P 32 = 64 KiB exactly -/
theorem T_buffers_s4 : s4L0C = 256 * KiB ∧ s4L0C = l0cCap ∧ 2 * (128 * 16 * 4 * 8) = 128 * KiB ∧ 2 * (16 * dH * 4 * 8) = 128 * KiB ∧
    s4L0A = 64 * KiB ∧ s4L0A = l0aCap := by decide
/-- the page-table window is O(1): 4 KiB = 512 entries = 128k tokens per refill, for every L -/
theorem T_buffers_window (L : Nat) : usPtWindow 1 = 4096 ∧ ptWindowEntries * pageTok pageB 128 = 131072 ∧
    usPtWindow 1 = usPtWindow 1 + 0 * L := by simp [usPtWindow, ptWindowEntries, pageTok, pageB]

/-! ## T_online — online vs two-pass (rows 17–18) -/
/-- two-pass re-streams K: 128 KiB per core per 512-token block = 6 005 ns at the stream rate, against a 324 ns merge
    (7 000 lane-ops at ρ32 = 2): online wins 18×; both are per block, so L cancels -/
theorem T_online : tn (512 * 128 * 2 * 8) gStream = 6005 ∧ mergeOps * 2 * 10 / rVecCore = 324 ∧ 6005 / 324 = 18 ∧
    mergeOps * 1 * 10 / rVecCore = 162 := by decide
theorem T_online_L_independent (L nb : Nat) : nb * 6005 + L * 0 = nb * 6005 ∧ (nb * 324 ≤ nb * 6005) := by
  constructor
  · simp
  · exact Nat.mul_le_mul_left nb (by decide)
/-- the merge is exact for ANY multiplicative exp (E (a + b) = E a · E b): Σ_{l∈b} E(s_l − m_b)·v_l rescaled by
    E(m_b − m) equals Σ_{l∈b} E(s_l − m)·v_l, so the block partials telescope to the global sum (row 18) -/
def sumI : List Int → Int
  | [] => 0
  | x :: xs => x + sumI xs
theorem T_online_exact_block (E : Int → Int) (hE : ∀ a b, E (a + b) = E a * E b) (m mb : Int) (blk : List (Int × Int)) :
    E (mb - m) * sumI (blk.map (fun p => E (p.1 - mb) * p.2)) = sumI (blk.map (fun p => E (p.1 - m) * p.2)) := by
  induction blk with
  | nil => simp [sumI]
  | cons p ps ih =>
    simp only [List.map, sumI]
    rw [Int.mul_add, ih]
    have : E (p.1 - m) = E (mb - m) * E (p.1 - mb) := by
      rw [← hE]; congr 1; omega
    rw [this, Int.mul_assoc]
theorem sumI_append (a b : List Int) : sumI (a ++ b) = sumI a + sumI b := by
  induction a with
  | nil => simp [sumI]
  | cons x xs ih => simp [sumI, ih, Int.add_assoc]
/-- the token list of a block list -/
def catL : List (Int × List (Int × Int)) → List (Int × Int)
  | [] => []
  | b :: bs => b.2 ++ catL bs
/-- over a list of blocks, each with its own block max m_b: Σ_b E(m_b − m)·(block partial at m_b) = the single-pass sum at m -/
theorem T_online_exact (E : Int → Int) (hE : ∀ a b, E (a + b) = E a * E b) (m : Int) (blocks : List (Int × List (Int × Int))) :
    sumI (blocks.map (fun b => E (b.1 - m) * sumI (b.2.map (fun p => E (p.1 - b.1) * p.2)))) =
    sumI ((catL blocks).map (fun p => E (p.1 - m) * p.2)) := by
  induction blocks with
  | nil => simp [sumI, catL]
  | cons b bs ih =>
    simp only [List.map, catL, sumI]
    rw [List.map_append, sumI_append, ih, T_online_exact_block E hE m b.1 b.2]

/-! ## T_kvwrite, T_tail (row 22, `[A6-kvwrite]`) -/
theorem T_kvwrite : vTailBlockB 128 = 4096 ∧ tn 4096 rFrac = 585 ∧ 585 / 16 = 36 ∧ kAppendCopies 128 = 8 ∧ 8 * 32 = 256 ∧
    kAppendCopies 128 * 1000 = 8000 ∧ pct 8000 tGemvUnit = 20 ∧ tn (4096 * 4) rFrac = 2340 ∧
    pct 585 3002 = 195 ∧ 134217728 * 10 / (8 * rFrac) = 2396745 := by decide
theorem T_tail : tailOps 15 1 128 = 122880 ∧ tailNs 15 1 128 2 = 5688 ∧ tailNs 15 1 128 1 = 2844 ∧ tailNs 16 1 128 2 = 0 ∧
    (∀ L, tailOps L 1 128 ≤ 122880) := by
  refine ⟨by decide, by decide, by decide, by decide, ?_⟩
  intro L; unfold tailOps; have := Nat.mod_lt L (show 16 > 0 by decide); omega

/-! ## T_softmax_ops — the op-count arithmetic (rows 8, 19; `[A7-poly]` `[A7-tree-ops]`) -/
/-- per score: c_V = 2 + R + 1 + E + 1 + 1 for the four corners; the polynomial is 6 + 1 + 8 + 7 = 22; the tree max is
    6 lane-ops per pair over 7 × 1024 + 512 + 256 lanes = 47 616 per 8 192 scores (≤ 6 per score, the table's figure)
    plus a 240-compare scalar tail (≤ 256); the exact (poly, tree) chain is 268 800 lane-ops per block, 0.6 % under
    the model's 33 × 8 192 = 270 336 -/
theorem T_softmax_ops : polyOps = 22 ∧ cVof eNative rNative = 7 ∧ cVof eNative rTree = 12 ∧ cVof polyOps rNative = 28 ∧
    cVof polyOps rTree = 33 ∧ treeLaneOps = 47616 ∧ treeLaneOps ≤ 6 * 8192 ∧ treeLaneOps * 1000 / 8192 = 5812 ∧
    treeScalarCompares = 240 ∧ treeScalarCompares ≤ 256 ∧ polyTreeBlockExact = 268800 ∧
    polyTreeBlockExact ≤ cvWorst * 8192 ∧ cvWorst * 8192 = 270336 ∧ 2 ^ 7 = 128 ∧ 512 * 16 = 8192 := by decide
/-- the max identity costs 6 ops: a+b (Add), a−b (Muls −1, Add), |·| (And), sum (Add), ×0.5 (Muls) -/
theorem T_softmax_max_ops : 1 + 2 + 1 + 1 + 1 = 6 := by decide
/-- per block at mt = 1: lane-ops = 8 192·c_V + merge; the ns cells of T3_vec_cells follow -/
theorem T_softmax_block (cV : Nat) : vecBlock cV 1 1 mergeOps = (8192 * cV + 7000) * 10 / 432 := by
  unfold vecBlock mergeOps rVecCore
  have hb : blockOf 1 = 512 := by decide
  rw [hb]; omega
/-- the HYPOTHESIS constant and its arithmetic: 2⁷·(22/128)⁵/5! lies in [159, 160]·10⁻⁶ (so "1.6·10⁻⁴"), and the f32
    rounding term 2⁷·2⁻²⁴ = 2⁻¹⁷ ≈ 7.6·10⁻⁶; the polynomial's accuracy itself is E22(e), carried as polyRelErrPpm -/
theorem T_poly_bound : 128 * 22 ^ 5 * 1000000 / (128 ^ 5 * 120) = 159 ∧
    159 * (128 ^ 5 * 120) ≤ 128 * 22 ^ 5 * 1000000 ∧ 128 * 22 ^ 5 * 1000000 ≤ 160 * (128 ^ 5 * 120) ∧
    polyRelErrPpm = 160 ∧ 2 ^ 7 * 1000000000 / 2 ^ 24 = 7629 ∧ polyRelErrPpm * 10 ≤ 1000 * 10 / 6 := by decide

/-! ## T_drift — the ±Q region-difference drift bound (row 20, `[A7-drift-*]`) -/
/-- for ANY sign pattern of block sums bounded by smax, the alternating region content after n visits is bounded by
    n·smax (the deterministic worst case; alternation cancels only between similar consecutive blocks) -/
theorem T_drift_alt (s : Nat → Int) (smax : Nat) (h : ∀ i, (s i).natAbs ≤ smax) :
    ∀ n, (altSum s n).natAbs ≤ n * smax := by
  intro n
  induction n with
  | zero => simp [altSum]
  | succ n ih =>
    unfold altSum
    have h1 := h n
    have h2 := Int.natAbs_add_le (altSum s n) (if n % 2 = 0 then s n else - s n)
    have h3 : (if n % 2 = 0 then s n else - s n).natAbs = (s n).natAbs := by
      split <;> simp [Int.natAbs_neg]
    rw [Nat.succ_mul]
    omega
/-- the per-block recovered-score error: one f32 rounding in the accumulate and one in the difference, each ≤ ½ ulp
    of the content bound C → ≤ 1 ulp(C); stated over the hypothesis variables (eps per rounding, C the content bound) -/
theorem T_drift_error (eps C : Nat) (he : 2 * eps ≤ ulpU C) : eps + eps ≤ ulpU C := by omega
/-- instantiation at 1M, 512-token blocks, |s| ≤ 32 (A): 683 visits per region; deterministic bound 21 856 → ulp 2⁻⁹ ≈
    2·10⁻³ on a score; under the RANDOM-WALK HYPOTHESIS (E26) √683·32 = 832 ≈ 840 → ulp 2⁻¹⁴ = 6.1·10⁻⁵ (61 ppm),
    the "10⁻⁴ class" claim. The 10⁻⁴ figure therefore rests on the random-walk hypothesis, not on a worst case. -/
theorem T_drift_1M : visits 1048576 512 = 683 ∧ 683 * 32 = 21856 ∧ ulpU 21856 = 2 ^ 15 ∧ ulpU 21856 * 1000000 / 2 ^ 24 = 1953 ∧
    isqrtLe 683 = 26 ∧ 26 * 32 = 832 ∧ 832 ≤ 840 ∧ ulpU 840 = 2 ^ 10 ∧ ulpU 832 = 2 ^ 10 ∧ ulpU 840 * 1000000 / 2 ^ 24 = 61 ∧
    2 ^ 20 / 1536 = 682 ∧ 26 * 26 ≤ 683 ∧ 683 < 27 * 27 ∧ 1000 * 10 ≤ 2 * 1000000 / ulpU 21856 * 0 + 10000 := by decide
/-- CORRECTION (§9 "smaller blocks (256 tokens halve the drift)"): halving the block doubles the visits per region
    (1 366 at 1M), so the deterministic bound doubles (43 712 → ulp 2⁻⁸) and the random-walk bound grows √2× (1 152 →
    ulp 2⁻¹³ = 1.2·10⁻⁴): smaller blocks make the drift WORSE; the levers are the KV-int8 variant (exact i32) or a reset -/
theorem T_drift_blocks : visits 1048576 256 = 1366 ∧ visits 1048576 256 = 2 * visits 1048576 512 ∧ 1366 * 32 = 43712 ∧
    ulpU 43712 = 2 ^ 16 ∧ isqrtLe 1366 = 36 ∧ 36 * 32 = 1152 ∧ ulpU 1152 = 2 ^ 11 ∧ ulpU 1152 * 1000000 / 2 ^ 24 = 122 ∧
    ulpU 840 < ulpU 1152 := by decide
/-- visits per region grow with L and shrink with the block for every L (monotone): the bound is O(L/blk) -/
theorem T_drift_monotone (L L' : Nat) (h : L ≤ L') : visits L 512 ≤ visits L' 512 ∧ visits L 512 ≤ visits L 256 := by
  unfold visits ceilDiv
  constructor
  · apply Nat.div_le_div_right; have := Nat.div_le_div_right (c := 512) h; omega
  · apply Nat.div_le_div_right; have : L / 512 ≤ L / 256 := Nat.div_le_div_left (by decide) (by decide); omega

/-! ## T_kpage_bijection, T_vpage_bijection (row 3) — the K and V page maps on [0,256) × [0,128) → even bytes of [0, 65 536) -/
theorem T_kpage_range (l j : Nat) (hl : l < 256) (hj : j < 128) : kAddr l j < 65536 ∧ kAddr l j % 2 = 0 := by
  unfold kAddr; omega
theorem T_kpage_injective (l j l' j' : Nat) (hl : l < 256) (hj : j < 128) (hl' : l' < 256) (hj' : j' < 128)
    (h : kAddr l j = kAddr l' j') : l = l' ∧ j = j' := by
  unfold kAddr at h; omega
theorem T_kpage_surjective (a : Nat) (_ha : a < 32768) : kAddr (kInvL a) (kInvJ a) = 2 * a ∧ kInvL a < 256 ∧ kInvJ a < 128 := by
  unfold kAddr kInvL kInvJ; omega
theorem T_kpage_bijection (l j : Nat) (_hl : l < 256) (_hj : j < 128) : kInvL (kAddr l j / 2) = l ∧ kInvJ (kAddr l j / 2) = j := by
  unfold kAddr kInvL kInvJ; omega
theorem T_vpage_range (l j : Nat) (hl : l < 256) (hj : j < 128) : vAddr l j < 65536 ∧ vAddr l j % 2 = 0 := by
  unfold vAddr; omega
theorem T_vpage_injective (l j l' j' : Nat) (hl : l < 256) (hj : j < 128) (hl' : l' < 256) (hj' : j' < 128)
    (h : vAddr l j = vAddr l' j') : l = l' ∧ j = j' := by
  unfold vAddr at h; omega
theorem T_vpage_surjective (a : Nat) (ha : a < 32768) : vAddr (vInvL a) (vInvJ a) = 2 * a ∧ vInvL a < 256 ∧ vInvJ a < 128 := by
  obtain ⟨p, q, r, s, t, hp, hq, hr, hs, ht, rfl⟩ : ∃ p q r s t, p < 2 ∧ q < 8 ∧ r < 8 ∧ s < 16 ∧ t < 16 ∧
      a = 16384 * p + 2048 * q + 256 * r + 16 * s + t :=
    ⟨a / 16384, (a / 2048) % 8, (a / 256) % 8, (a / 16) % 16, a % 16, by omega, by omega, by omega, by omega, by omega, by omega⟩
  have hl : vInvL (16384 * p + 2048 * q + 256 * r + 16 * s + t) = 128 * p + 16 * r + t := by unfold vInvL; omega
  have hj : vInvJ (16384 * p + 2048 * q + 256 * r + 16 * s + t) = 16 * q + s := by unfold vInvJ; omega
  rw [hl, hj]; unfold vAddr; omega
theorem vDigits (p q r s t : Nat) (_hp : p < 2) (hq : q < 8) (hr : r < 8) (hs : s < 16) (ht : t < 16) :
    (16384 * p + 2048 * q + 256 * r + 16 * s + t) / 16384 = p ∧
    ((16384 * p + 2048 * q + 256 * r + 16 * s + t) / 256) % 8 = r ∧
    (16384 * p + 2048 * q + 256 * r + 16 * s + t) % 16 = t ∧
    ((16384 * p + 2048 * q + 256 * r + 16 * s + t) / 2048) % 8 = q ∧
    ((16384 * p + 2048 * q + 256 * r + 16 * s + t) / 16) % 16 = s := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> omega
theorem vAddr_digits (p q r s t : Nat) (_hp : p < 2) (_hq : q < 8) (hr : r < 8) (hs : s < 16) (ht : t < 16) :
    vAddr (128 * p + 16 * r + t) (16 * q + s) = 2 * (16384 * p + 2048 * q + 256 * r + 16 * s + t) := by
  unfold vAddr; omega
theorem T_vpage_bijection (l j : Nat) (hl : l < 256) (hj : j < 128) : vInvL (vAddr l j / 2) = l ∧ vInvJ (vAddr l j / 2) = j := by
  obtain ⟨p, r, t, hp, hr, ht, rfl⟩ : ∃ p r t, p < 2 ∧ r < 8 ∧ t < 16 ∧ l = 128 * p + 16 * r + t :=
    ⟨l / 128, (l / 16) % 8, l % 16, by omega, by omega, by omega, by omega⟩
  obtain ⟨q, s, hq, hs, rfl⟩ : ∃ q s, q < 8 ∧ s < 16 ∧ j = 16 * q + s := ⟨j / 16, j % 16, by omega, by omega, by omega⟩
  obtain ⟨d1, d2, d3, d4, d5⟩ := vDigits p q r s t hp hq hr hs ht
  rw [vAddr_digits p q r s t hp hq hr hs ht, Nat.mul_div_cancel_left _ (by decide : 0 < 2)]
  unfold vInvL vInvJ
  rw [d1, d2, d3, d4, d5]
  exact ⟨rfl, rfl⟩
/-- geometry facts behind the maps: a K call tile is 4 KiB (16 tokens), 16 per page; a V call tile is 128 tokens × 16
    dims = 4 KiB, 8 n-groups per 128 tokens = 32 KiB (two halves per page); a token's K append is 8 runs of 32 B at
    stride 512 B; the i8 variant's page is 32 KiB with 4 runs per token -/
theorem T_page_geometry : 16 * 128 * 2 = 4096 ∧ 65536 / 4096 = 16 ∧ 128 * 16 * 2 = 4096 ∧ 8 * 4096 = 32768 ∧
    kAddr 1 0 - kAddr 0 0 = 32 ∧ kAddr 0 16 - kAddr 0 0 = 512 ∧ kAddr 16 0 - kAddr 0 0 = 4096 ∧
    vAddr 1 0 - vAddr 0 0 = 2 ∧ vAddr 0 1 - vAddr 0 0 = 32 ∧ vAddr 16 0 - vAddr 0 0 = 512 ∧ vAddr 128 0 - vAddr 0 0 = 32768 ∧
    256 * 128 = 32768 ∧ 128 / 32 = 4 := by decide

/-! ## T_errata_sizes (row 27) and the H_kv = 1 partials (row "H_kv = 1") -/
theorem T_errata_sizes : 32768 ≤ copyCap ∧ pFragB ≤ copyCap ∧ 4096 ≤ copyCap ∧ 1024 ≤ laneCap ∧ 16 ≤ nCap ∧
    (32 ≠ 64 ∧ 128 ≠ 64) ∧ 2 * 32 = 64 ∧ l0bRing ≤ l0bCap := by decide
/-- CORRECTION (§9, §10 "9.3 KiB·mt"): 16 rows × (1 + 16 + 128) f32 = 9 280 B = 9.06 KiB (9.3 KB) per fragment -/
theorem T_hkv1_partials : 16 * (1 + 16 + 128) * 4 = 9280 ∧ 9280 * 100 / KiB = 906 ∧ 9280 * 100 / 1000 = 928 ∧
    rowsOf 1 32 = 32 ∧ mtOf 32 = 2 ∧ rowsOf 16 32 = 512 ∧ passesOf 512 = 8 := by decide
/-- wall-clock rows add the launch floor; it never enters an in-kernel cell (the model's step has no tLaunch term) -/
theorem T_wall (ns : Nat) : wallNs ns = ns + 91000 ∧ wallNs ns - ns = tLaunch := by unfold wallNs tLaunch; omega

/-! ## §8 harness arithmetic and the E21 arena (ledger rows 38–39) -/
/-- integer-valued inputs: |q|,|k|,|v| ≤ 7 → |s| ≤ 6 272 but the identity-exp block PV sums 2.25·10⁷ exceed 2²⁴;
    |q| ≤ 1 → |s| ≤ 896 and block sums 3 211 264 < 2²⁴ (f32-exact) -/
theorem T_harness : 7 * 7 * 128 = 6272 ∧ 512 * 6272 * 7 = 22478848 ∧ 2 ^ 24 < 22478848 ∧ 1 * 7 * 128 = 896 ∧
    512 * 896 * 7 = 3211264 ∧ 3211264 < 2 ^ 24 ∧ 2 ^ 24 = 16777216 := by decide
/-- E21 at P = 1 MiB: 8 cores × 2 048 pages = 16 GiB of visits inside a 4 GiB arena — pages repeat 4×; the per-page
    pattern check still differences every visit (the host sums the visited pages), so the probe stays valid -/
theorem T_e21_arena : 8 * 2048 * MiB = 16 * 1024 * MiB ∧ 4 * 1024 * MiB < 8 * 2048 * MiB ∧ 8 * 2048 * 65536 = 1024 * MiB := by decide

/-! # ROUND 3 (2026-11-05) — the season (v1) measurements (HW-MAP commit 8a7079f) ground the model

  Every round-2 theorem above is kept (it is the arithmetic of the round-2 model and its branches); the
  round-3 theorems `T3r_*` re-instantiate every moved cell on the measured constants. The measured
  quantities enter as `Measured3` constants; the two remaining modelling choices are explicit:
    `Var`  — the per-block softmax chain: `.rowmax` = DESIGN-3 §3.2 as specified (per-row block max:
             f32 difference, cast, f16 6-op tree, 16 per-row reduce-max calls, a 20-call shift reel,
             exp, cast, sum), `.lazy` = the fixed per-row shift with an overflow guard (one reduce-max
             call per P reel, no per-block row max, no alpha);
    `Conv` — the op-cost convention: `.T` = throughput (1 lane-op = 1/43.2 ns, f32 at the measured
             rho32 = 1.37), `.C` = chained-latency bound (every 1024-lane call at its measured chained ns);
  the merge count stays a hypothesis variable (`m`, lane-eq x100) with the pack's 25 750 as the headline.
  Units: lane-equivalents x100 inside the chain (1 lane-eq = 10/432 ns), ns elsewhere, as in attn.py `[R3-*]`. -/
namespace Measured3
/-- E21 (gather rate, 20/20 reps exact): aggregate tenths GB/s, sequential control / shuffled, at 16 / 64 / 256 KiB -/
def gSeq16 : Nat := 1652
def gShuf16 : Nat := 1538
def gSeq64 : Nat := 1690
def gShuf64 : Nat := 1670
def g256 : Nat := 1692
/-- E21 per-page ns per core, sequential / shuffled -/
def tPgSeq16 : Nat := 793
def tPgShuf16 : Nat := 852
def tPgSeq64 : Nat := 3101
def tPgShuf64 : Nat := 3140
def tPgSeq256 : Nat := 12391
def tPgShuf256 : Nat := 12394
/-- E22 (softmax op set): chained per-call tenths of ns on 1024 lanes — exp, reduce-max f16 / f32, f16 Mul, f32 Mul/Add, And<int16> -/
def tExp : Nat := 2728
def tRm16 : Nat := 1819
def tRm32 : Nat := 2514
def tF16 : Nat := 464
def tF32 : Nat := 636
def tAnd16 : Nat := 459
/-- E22: c_exp = 272.8 ns x 43.2 / 1024 = 11.5 lane-eq per element (hundredths); rho32 = 63.6 / 46.4 = 1.37 (hundredths); sigma_s = 19.9 ns (tenths) -/
def cExp100 : Nat := 1150
def rho32_100 : Nat := 137
def sigma3 : Nat := 199
/-- L0C -> US drain measured at mt = 1..4, tenths GB/s/core -/
def rDrain1 : Nat := 1528
def rDrain2 : Nat := 2223
def rDrain3 : Nat := 2603
def rDrain4 : Nat := 2855
/-- the validation pack's merge-chain itemisation, lane-eq per block-fragment (commit 8a7079f message) -/
def mergePack : Nat := 25750
/-- the retained "3x slower" what-if (a scattered cache, c_pg ~ 6 us at 64 KiB): no longer a measured branch -/
def g3x : Nat := 582
end Measured3

namespace Design3
open Measured Measured3 Design

/-! ### Units: lane-eq x100 per tenth of a ns; chained call costs -/
def lanePerNs10 : Nat := 432
def call100 (t10 : Nat) : Nat := t10 * lanePerNs10
inductive Conv where
  | T   -- throughput convention
  | C   -- chained-latency bound
  deriving DecidableEq, Repr
inductive Var where
  | rowmax   -- DESIGN-3 §3.2 as specified (per-row block max)
  | lazy     -- fixed per-row shift + overflow guard
  deriving DecidableEq, Repr
/-- per-lane cost of one elementwise f16 / f32 op, hundredths of a lane-eq -/
def unitF16 : Conv → Nat
  | .T => 100
  | .C => ceilDiv (tF16 * lanePerNs10) 1024
def unitF32 : Conv → Nat
  | .T => rho32_100
  | .C => ceilDiv (tF32 * lanePerNs10) 1024
/-- f16 6-op pair-max tree: block·16/1024 reels -> 1 reel (1024 lanes per pair-op), then 1024 -> 256 (512 + 256 lanes) -/
def treeOps (block : Nat) : Nat := 6 * ((block * 16 / 1024 - 1) * 1024 + 512 + 256)
/-- rowmax chain per block for mt fragments, lane-eq x100: 6 f32 ops per score (difference 2, cast S 1, shift 1,
    cast P 1, sum 1) + exp + the f16 tree + 16 per-row reduce-max calls + the shift reel (16 Duplicate + 3 copies
    = 20 small calls, each costed as one chained f16 call: ASSUMPTION A3) + the merge -/
def chainRowmax (block mt f16 f32 cexp merge100 : Nat) : Nat :=
  mt * (block * 16 * (6 * f32 + cexp) + treeOps block * f16 + 16 * call100 tRm16 + 20 * call100 tF16 + merge100)
/-- lazy chain: 5 f32 ops per score (difference 2, shift 1, cast P 1, sum 1) + exp + one guard reduce-max per P reel + the merge -/
def chainLazy (block mt f32 cexp merge100 : Nat) : Nat :=
  mt * (block * 16 * (5 * f32 + cexp) + (block * 16 / 1024) * call100 tRm16 + merge100)
def chain100 (block mt : Nat) : Var → Conv → Nat → Nat
  | .rowmax, c, m => chainRowmax block mt (unitF16 c) (unitF32 c) cExp100 m
  | .lazy, c, m => chainLazy block mt (unitF32 c) cExp100 m
/-- vector time per block, ns -/
def vec3 (block mt : Nat) (v : Var) (c : Conv) (m : Nat) : Nat := chain100 block mt v c m * 10 / (rVecCore * 100)
/-- the itemised merge chain of §3.1 at the measured constants: alpha exp (1 call) + alpha reel (20 small calls) +
    O (difference Add, snapshot Muls, scale Mul, Add over 2048 lanes) + S (fold 512 + 256, scale 256, add 256);
    the lazy variant has no alpha: O (difference, snapshot, add) + S (fold, add) -/
def mergeItem : Var → Conv → Nat
  | .rowmax, c => call100 tExp + 20 * call100 tF16 + 4 * 2048 * unitF32 c + (512 + 256 + 256 + 256) * unitF32 c
  | .lazy, c => (3 * 2048 + 512 + 256 + 256) * unitF32 c
/-- the measured drain rate per fragment count (mt >= 4 uses the mt = 4 figure) -/
def rDrainM (mt : Nat) : Nat := if mt ≤ 1 then rDrain1 else if mt = 2 then rDrain2 else if mt = 3 then rDrain3 else rDrain4
def mtS (t : Nat) (onepass : Bool) : Nat := mtSel (rowsOf t gH) onepass
def pn (L t : Nat) (onepass : Bool) : Nat := pSel (rowsOf t gH) onepass * nblocks L (mtS t onepass)
def blockMax3 (G : Nat) (v : Var) (c : Conv) (m mt : Nat) : Nat :=
  max (max (max (ddrBlock G mt dH) (vec3 (blockOf mt) mt v c m)) (mmaBlock mt dH)) (loaderBlock mt)
/-- fixed cost: pipeline fill + tail = 2 vector blocks + 1 drain at the measured rate + the vector tail -/
def fixed3 (L : Nat) (v : Var) (c : Conv) (m mt mtAll : Nat) : Nat :=
  2 * vec3 (blockOf mt) mt v c m + drainBlock mt dH (rDrainM mt) + tailOps L mtAll dH * unitF32 c * 10 / (rVecCore * 100)
/-- the round-3 step (ns, in-kernel): passes·blocks·max(engines) + fixed; drain hidden (T3r_drain) -/
def step3 (L t G : Nat) (v : Var) (c : Conv) (m : Nat) (onepass : Bool) : Nat :=
  pn L t onepass * blockMax3 G v c m (mtS t onepass) + fixed3 L v c m (mtS t onepass) (mtOf (rowsOf t gH))
/-- the KV-int8 variant: the streamed bytes halve (on the total, as attn.py), nothing else moves -/
def step3I8 (L t G : Nat) (v : Var) (c : Conv) (m : Nat) : Nat :=
  max (max (max (pn L t false * ddrBlock G (mtS t false) dH / 2) (pn L t false * vec3 (blockOf (mtS t false)) (mtS t false) v c m))
      (pn L t false * mmaBlock (mtS t false) dH)) (pn L t false * loaderBlock (mtS t false))
  + fixed3 L v c m (mtS t false) (mtOf (rowsOf t gH))
/-- headline shorthand: the pack's merge, two-pass -/
def step3H (L t G : Nat) (v : Var) (c : Conv) : Nat := step3 L t G v c (mergePack * 100) false
def step3S4 (L G : Nat) (v : Var) (c : Conv) : Nat := step3 L 16 G v c (mergePack * 100) true
/-- E21 page model: measured sequential per-page base + an extra per-page cost c -/
def tPgSeq (P : Nat) : Nat := if P = 16384 then tPgSeq16 else if P = 65536 then tPgSeq64 else tPgSeq256
def gPage3 (P c : Nat) : Nat := 8 * P * 10 / (tPgSeq P + c)
/-- two-tier pages (ALTERNATIVES §2.5) on the measured base: 1 MiB extents (4 x the 256 KiB page + c) + 64 KiB tails -/
def gTier3 (L c : Nat) : Nat :=
  let nE := L / 4096
  let nT := ceilDiv (L - nE * 4096) 256
  let tCore := nE * (4 * tPgSeq256 + c) + nT * (tPgSeq64 + c)
  if tCore = 0 then g256 else 8 * L * 256 * 10 / tCore
/-- the vector-dot route ratio at a hundredths rho (T_gqa_matrix at the measured 1.37) -/
def dotRatioT100 (rows rho100 d : Nat) : Nat := rows * rho100 * 4 * d * rGemm * 10000 / (80 * coreTok d * rVecCore * 100)
end Design3

open Measured3 Design3

/-! ## T3r_E21 — the measured gather rates (`[R3-E21-*]`) -/
/-- shuffled − sequential = 59 / 39 / 3 ns at 16 / 64 / 256 KiB; against the round-2 model's 174.6 base the same
    pages cost 102 / 138 / 383 ns — the 64 KiB shuffled page sits ABOVE the 123 ns flip line of round 2 because the
    attention choreography itself streams at 169.0 (a 3.2 % gap to the W8 kernel's 174.6), not because of c_pg -/
theorem T3r_E21 : tPgShuf16 - tPgSeq16 = 59 ∧ tPgShuf64 - tPgSeq64 = 39 ∧ tPgShuf256 - tPgSeq256 = 3 ∧
    tPgShuf16 - 16384 * 80 / rGemm = 102 ∧ tPgShuf64 - 65536 * 80 / rGemm = 138 ∧ tPgShuf256 - 262144 * 80 / rGemm = 383 ∧
    123 ≤ 138 ∧ pct (rGemm - gSeq64) rGemm = 32 ∧ pct (rGemm - g256) rGemm = 31 ∧ pct (rGemm - gSeq16) rGemm = 54 ∧
    gPage pageB 38 = 1724 ∧ 8 * 65536 * 10 / tPgShuf64 = 1669 ∧ 8 * 262144 * 10 / tPgSeq256 = 1692 := by decide
/-- block DDR times on the measured rates: 12 409 (seq 64 KiB) / 12 557 (shuffled 64 KiB, the design's page) /
    12 394 (256 KiB) / 13 635 (16 KiB) / 36 033 (3x what-if) against the round-2 12 011 -/
theorem T3r_E21_block : ddrBlock gSeq64 1 128 = 12409 ∧ ddrBlock gShuf64 1 128 = 12557 ∧ ddrBlock g256 1 128 = 12394 ∧
    ddrBlock gShuf16 1 128 = 13635 ∧ ddrBlock g3x 1 128 = 36033 ∧ ddrBlock gStream 1 128 = 12011 ∧
    ddrBlock gShuf64 4 128 = 6278 ∧ ddrBlock gShuf64 8 128 = 3139 := by decide

/-! ## T3r_units, T3r_tree, T3r_chain — the measured softmax chain (`[R3-units]` `[R3-tree-ops]` `[R3-chain-*]`) -/
theorem T3r_units : call100 tExp / 100 = 11784 ∧ tExp * lanePerNs10 / 1024 = 1150 ∧ call100 tRm16 / 100 = 7858 ∧
    call100 tRm32 / 100 = 10860 ∧ call100 tF16 / 100 = 2004 ∧ call100 tF32 / 100 = 2747 ∧
    unitF16 .C = 196 ∧ unitF32 .C = 269 ∧ unitF16 .T = 100 ∧ unitF32 .T = 137 ∧ 636 * 100 / 464 = 137 := by decide
theorem T3r_tree : treeOps 512 = 47616 ∧ treeOps 256 = 23040 ∧ treeOps 128 = 10752 ∧ treeOps 512 = treeLaneOps ∧
    treeOps 512 * 10000 / 8192 = 58125 := by decide
/-- the 12 chain cells (ns per fragment at the pack merge): rowmax 9 276 / 6 837 / 5 618 (T), 11 836 / 8 100 / 6 232 (C);
    lazy 5 530 / 3 063 / 1 829 (T), 6 782 / 3 689 / 2 142 (C) at blocks 512 / 256 / 128 -/
theorem T3r_chain : vec3 512 1 .rowmax .T (mergePack * 100) = 9276 ∧ vec3 256 1 .rowmax .T (mergePack * 100) = 6837 ∧
    vec3 128 1 .rowmax .T (mergePack * 100) = 5618 ∧ vec3 512 1 .rowmax .C (mergePack * 100) = 11836 ∧
    vec3 256 1 .rowmax .C (mergePack * 100) = 8100 ∧ vec3 128 1 .rowmax .C (mergePack * 100) = 6232 ∧
    vec3 512 1 .lazy .T (mergePack * 100) = 5530 ∧ vec3 256 1 .lazy .T (mergePack * 100) = 3063 ∧
    vec3 128 1 .lazy .T (mergePack * 100) = 1829 ∧ vec3 512 1 .lazy .C (mergePack * 100) = 6782 ∧
    vec3 256 1 .lazy .C (mergePack * 100) = 3689 ∧ vec3 128 1 .lazy .C (mergePack * 100) = 2142 := by decide
/-- vector share of the block at mt = 1: 77.2 % (rowmax-T) / 98.5 % (rowmax-C) / 46.0 % (lazy-T) / 56.5 % (lazy-C) at 174.6 —
    round 2's native corner was 12.4 % (c_V = 7); at t = 1 the 8 padding rows need no reduce call: 7 820 ns = 65.1 % -/
theorem T3r_chain_shares : pct 9276 12011 = 772 ∧ pct 11836 12011 = 985 ∧ pct 5530 12011 = 460 ∧ pct 6782 12011 = 565 ∧
    pct 9276 12557 = 739 ∧ pct 11836 12557 = 943 ∧ pct 5530 12557 = 440 ∧ pct 6837 6005 = 1139 ∧ pct 5618 3002 = 1871 ∧
    (chain100 512 1 .rowmax .T (mergePack * 100) - 8 * call100 tRm16) * 10 / (rVecCore * 100) = 7820 ∧ pct 7820 12011 = 651 ∧
    chain100 512 1 .rowmax .T (mergePack * 100) / 100 = 400731 ∧ 16 * call100 tRm16 / 100 = 125729 ∧ 20 * call100 tF16 / 100 = 40089 ∧
    8192 * (6 * 137 + 1150) / 100 = 161546 := by decide
/-- the linear forms behind the iff theorems: chain100 at merge 0 (lane-eq x100) -/
theorem chain100_rowmax (b mt m : Nat) (c : Conv) : chain100 b mt .rowmax c m = chainRowmax b mt (unitF16 c) (unitF32 c) cExp100 m := rfl
theorem chain100_lazy (b mt m : Nat) (c : Conv) : chain100 b mt .lazy c m = chainLazy b mt (unitF32 c) cExp100 m := rfl
theorem unitT16 : unitF16 .T = 100 := rfl
theorem unitT32 : unitF32 .T = 137 := rfl
theorem unitC16 : unitF16 .C = 196 := by decide
theorem unitC32 : unitF32 .C = 269 := by decide
theorem T3r_lin : chain100 512 1 .rowmax .T 0 = 37498112 ∧ chain100 256 1 .rowmax .T 0 = 26963200 ∧ chain100 128 1 .rowmax .T 0 = 21695744 ∧
    chain100 512 1 .rowmax .C 0 = 48557312 ∧ chain100 512 1 .lazy .T 0 = 21318784 ∧ chain100 256 1 .lazy .T 0 = 10659392 ∧
    chain100 128 1 .lazy .T 0 = 5329696 ∧ chain100 512 1 .lazy .C 0 = 26725504 := by decide
theorem vec3_rowmaxT_512 (m : Nat) : vec3 512 1 .rowmax .T m = (37498112 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_rowmax, unitT16, unitT32]; unfold chainRowmax
  have ht : treeOps 512 = 47616 := by decide
  rw [ht]; unfold call100 lanePerNs10 tRm16 tF16 cExp100 rVecCore; omega
theorem vec3_rowmaxC_512 (m : Nat) : vec3 512 1 .rowmax .C m = (48557312 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_rowmax, unitC16, unitC32]; unfold chainRowmax
  have ht : treeOps 512 = 47616 := by decide
  rw [ht]; unfold call100 lanePerNs10 tRm16 tF16 cExp100 rVecCore; omega
theorem vec3_lazyT_512 (m : Nat) : vec3 512 1 .lazy .T m = (21318784 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_lazy, unitT32]; unfold chainLazy call100 lanePerNs10 tRm16 cExp100 rVecCore; omega
theorem vec3_lazyC_512 (m : Nat) : vec3 512 1 .lazy .C m = (26725504 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_lazy, unitC32]; unfold chainLazy call100 lanePerNs10 tRm16 cExp100 rVecCore; omega
theorem vec3_rowmaxT_256_4 (m : Nat) : vec3 256 4 .rowmax .T m = 4 * (26963200 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_rowmax, unitT16, unitT32]; unfold chainRowmax
  have ht : treeOps 256 = 23040 := by decide
  rw [ht]; unfold call100 lanePerNs10 tRm16 tF16 cExp100 rVecCore; omega
theorem vec3_rowmaxT_128_8 (m : Nat) : vec3 128 8 .rowmax .T m = 8 * (21695744 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_rowmax, unitT16, unitT32]; unfold chainRowmax
  have ht : treeOps 128 = 10752 := by decide
  rw [ht]; unfold call100 lanePerNs10 tRm16 tF16 cExp100 rVecCore; omega
theorem vec3_lazyT_256_4 (m : Nat) : vec3 256 4 .lazy .T m = 4 * (10659392 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_lazy, unitT32]; unfold chainLazy call100 lanePerNs10 tRm16 cExp100 rVecCore; omega
theorem vec3_lazyT_128_8 (m : Nat) : vec3 128 8 .lazy .T m = 8 * (5329696 + m) * 10 / 43200 := by
  unfold vec3; rw [chain100_lazy, unitT32]; unfold chainLazy call100 lanePerNs10 tRm16 cExp100 rVecCore; omega

/-! ## T3r_merge — the merge count as a hypothesis variable (`[R3-merge-*]`): the pack's 25 750, the itemised chains, thresholds -/
/-- itemised merge chains (lane-eq x100): rowmax 64 851 (T) / 77 354 (C) — 2.5–3.0x the pack's 25 750, the alpha reel's
    20 small calls being the largest item; lazy 9 820 / 19 281; in ns: 596 (pack) / 1 501 / 1 790 / 227 / 446 -/
theorem T3r_merge_item : mergeItem .rowmax .T = 6485120 ∧ mergeItem .rowmax .C = 7735424 ∧ mergeItem .lazy .T = 982016 ∧
    mergeItem .lazy .C = 1928192 ∧ mergePack * 10 / rVecCore = 596 ∧ mergeItem .rowmax .T * 10 / (rVecCore * 100) = 1501 ∧
    mergeItem .rowmax .C * 10 / (rVecCore * 100) = 1790 ∧ mergeItem .lazy .T * 10 / (rVecCore * 100) = 227 ∧
    7000 * 10 / rVecCore = 162 ∧ 12128 * 10 / rVecCore = 280 ∧ 20 * call100 tF16 / 100 = 40089 ∧ call100 tExp / 100 = 11784 := by decide
/-- t = 1 DDR-bound at 174.6 iff merge ≤ 143 937 (rowmax-T) / 33 345 (rowmax-C) / 305 730 (lazy-T) / 251 663 (lazy-C) lane-eq;
    the pack's 25 750 passes on every chain, the itemised rowmax-C chain (77 354) exceeds its own line -/
theorem T3r_merge_threshold_rowmaxT (m : Nat) : vec3 512 1 .rowmax .T m ≤ ddrBlock gStream 1 128 ↔ m ≤ 14393727 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  rw [e, vec3_rowmaxT_512]; constructor <;> intro h <;> omega
theorem T3r_merge_threshold_rowmaxC (m : Nat) : vec3 512 1 .rowmax .C m ≤ ddrBlock gStream 1 128 ↔ m ≤ 3334527 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  rw [e, vec3_rowmaxC_512]; constructor <;> intro h <;> omega
theorem T3r_merge_threshold_lazyT (m : Nat) : vec3 512 1 .lazy .T m ≤ ddrBlock gStream 1 128 ↔ m ≤ 30573055 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  rw [e, vec3_lazyT_512]; constructor <;> intro h <;> omega
theorem T3r_merge_threshold_lazyC (m : Nat) : vec3 512 1 .lazy .C m ≤ ddrBlock gStream 1 128 ↔ m ≤ 25166335 := by
  have e : ddrBlock gStream 1 128 = 12011 := by decide
  rw [e, vec3_lazyC_512]; constructor <;> intro h <;> omega
/-- at the design's page (167.0): merge ≤ 167 524 / 56 932 / 329 317 / 275 250 -/
theorem T3r_merge_threshold_167 (m : Nat) : (vec3 512 1 .rowmax .T m ≤ ddrBlock gShuf64 1 128 ↔ m ≤ 16752447) ∧
    (vec3 512 1 .rowmax .C m ≤ ddrBlock gShuf64 1 128 ↔ m ≤ 5693247) ∧ (vec3 512 1 .lazy .T m ≤ ddrBlock gShuf64 1 128 ↔ m ≤ 32931775) := by
  have e : ddrBlock gShuf64 1 128 = 12557 := by decide
  rw [e, vec3_rowmaxT_512, vec3_rowmaxC_512, vec3_lazyT_512]
  refine ⟨?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
theorem T3r_merge_cells : mergePack * 100 ≤ 14393727 ∧ mergeItem .rowmax .T ≤ 14393727 ∧ 3334527 < mergeItem .rowmax .C ∧
    mergePack * 100 ≤ 3334527 ∧ mergeItem .lazy .T ≤ 30573055 ∧ 14393727 / 100 = 143937 ∧ 3334527 / 100 = 33345 ∧
    30573055 / 100 = 305730 ∧ 16752447 / 100 = 167524 := by decide
/-- the c_exp threshold on the measured chains (hundredths): t = 1 DDR-bound iff c_exp ≤ 25.92 (rowmax-T) / 45.67 (lazy-T) /
    12.42 (rowmax-C) at 174.6; 28.80 / 48.55 / 15.30 at 167.0 — the measured 11.5 clears every one, and every round-2 line -/
theorem T3r_cexp_threshold (c : Nat) :
    (chainRowmax 512 1 100 137 c (mergePack * 100) * 10 / 43200 ≤ 12011 ↔ c ≤ 2592) ∧
    (chainLazy 512 1 137 c (mergePack * 100) * 10 / 43200 ≤ 12011 ↔ c ≤ 4567) ∧
    (chainRowmax 512 1 196 269 c (mergePack * 100) * 10 / 43200 ≤ 12011 ↔ c ≤ 1242) ∧
    (chainRowmax 512 1 100 137 c (mergePack * 100) * 10 / 43200 ≤ 12557 ↔ c ≤ 2880) := by
  have ht : treeOps 512 = 47616 := by decide
  unfold chainRowmax chainLazy; rw [ht]; unfold call100 lanePerNs10 tRm16 tF16 mergePack
  refine ⟨?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
theorem T3r_cexp_clears : cExp100 ≤ 2592 ∧ cExp100 ≤ 1242 ∧ cExp100 ≤ 1900 ∧ cExp100 ≤ 2100 ∧ cExp100 / 100 ≤ 19 ∧
    cExp100 / 100 < polyOps ∧ cVof 12 rNative = 18 ∧ cVof 12 rNative ≤ 62 ∧ cVof 12 rTree = 23 ∧ cVof 12 rTree ≤ 30 := by decide

/-! ## T3r_t1 — the headline cells on the measured constants (`[R3-t1-*]`): L × G ∈ {174.6, 167.0 (64 KiB shuffled,
    the design's page), 169.2 (256 KiB), 153.8 (16 KiB), 58.2 (3x what-if)} × chain ∈ {rowmax-T (headline), rowmax-C
    (worst corner), lazy-T (variant)}; every cell is DDR-bound (T3r_t1_binding) -/
theorem T3r_t1_4k : step3H 4096 1 gStream .rowmax .T = 114908 ∧ step3H 4096 1 gStream .rowmax .C = 120028 ∧ step3H 4096 1 gStream .lazy .T = 107416 ∧
    step3H 4096 1 gShuf64 .rowmax .T = 119276 ∧ step3H 4096 1 gShuf64 .rowmax .C = 124396 ∧ step3H 4096 1 gShuf64 .lazy .T = 111784 ∧
    step3H 4096 1 g256 .rowmax .T = 117972 ∧ step3H 4096 1 g256 .rowmax .C = 123092 ∧ step3H 4096 1 g256 .lazy .T = 110480 ∧
    step3H 4096 1 gShuf16 .rowmax .T = 127900 ∧ step3H 4096 1 gShuf16 .rowmax .C = 133020 ∧ step3H 4096 1 gShuf16 .lazy .T = 120408 ∧
    step3H 4096 1 g3x .rowmax .T = 307084 ∧ step3H 4096 1 g3x .rowmax .C = 312204 ∧ step3H 4096 1 g3x .lazy .T = 299592 ∧
    usR 114908 = 115 ∧ usR 119276 = 119 ∧ usR 117972 = 118 ∧ usR 127900 = 128 ∧ usR 120028 = 120 ∧ usR 124396 = 124 ∧
    usR (wallNs 119276) = 210 ∧ effRate 4096 8 128 1 119276 = 1407 ∧ pct 119276 tGemvUnit = 300 := by decide
theorem T3r_t1_32k : step3H 32768 1 gStream .rowmax .T = 787524 ∧ step3H 32768 1 gStream .rowmax .C = 792644 ∧ step3H 32768 1 gStream .lazy .T = 780032 ∧
    step3H 32768 1 gShuf64 .rowmax .T = 822468 ∧ step3H 32768 1 gShuf64 .rowmax .C = 827588 ∧ step3H 32768 1 gShuf64 .lazy .T = 814976 ∧
    step3H 32768 1 g256 .rowmax .T = 812036 ∧ step3H 32768 1 g256 .rowmax .C = 817156 ∧ step3H 32768 1 g256 .lazy .T = 804544 ∧
    step3H 32768 1 gShuf16 .rowmax .T = 891460 ∧ step3H 32768 1 gShuf16 .rowmax .C = 896580 ∧ step3H 32768 1 gShuf16 .lazy .T = 883968 ∧
    step3H 32768 1 g3x .rowmax .T = 2324932 ∧ step3H 32768 1 g3x .rowmax .C = 2330052 ∧ step3H 32768 1 g3x .lazy .T = 2317440 ∧
    usR 787524 = 788 ∧ usR 792644 = 793 ∧ usR 780032 = 780 ∧ usR 822468 = 822 ∧ usR 827588 = 828 ∧ usR 814976 = 815 ∧
    usR 812036 = 812 ∧ usR 891460 = 891 ∧ usR 2324932 = 2325 ∧ usR (wallNs 822468) = 913 ∧
    effRate 32768 8 128 1 822468 = 1632 ∧ effRate 32768 8 128 1 787524 = 1704 ∧ effRate 32768 8 128 1 812036 = 1653 ∧
    pct 822468 tGemvUnit = 2067 ∧ pct 787524 tGemvUnit = 1979 := by decide
theorem T3r_t1_128k : step3H 131072 1 gStream .rowmax .T = 3093636 ∧ step3H 131072 1 gStream .rowmax .C = 3098756 ∧ step3H 131072 1 gStream .lazy .T = 3086144 ∧
    step3H 131072 1 gShuf64 .rowmax .T = 3233412 ∧ step3H 131072 1 gShuf64 .rowmax .C = 3238532 ∧ step3H 131072 1 gShuf64 .lazy .T = 3225920 ∧
    step3H 131072 1 g256 .rowmax .T = 3191684 ∧ step3H 131072 1 g256 .rowmax .C = 3196804 ∧ step3H 131072 1 g256 .lazy .T = 3184192 ∧
    step3H 131072 1 gShuf16 .rowmax .T = 3509380 ∧ step3H 131072 1 gShuf16 .rowmax .C = 3514500 ∧ step3H 131072 1 gShuf16 .lazy .T = 3501888 ∧
    step3H 131072 1 g3x .rowmax .T = 9243268 ∧ step3H 131072 1 g3x .rowmax .C = 9248388 ∧ step3H 131072 1 g3x .lazy .T = 9235776 ∧
    usR 3093636 = 3094 ∧ usR 3233412 = 3233 ∧ usR 3191684 = 3192 ∧ usR 3509380 = 3509 ∧ usR 3238532 = 3239 ∧
    effRate 131072 8 128 1 3233412 = 1660 ∧ effRate 131072 8 128 1 3191684 = 1682 ∧ pct 3233412 tGemvUnit = 8124 := by decide
theorem T3r_t1_1M : step3H 1048576 1 gStream .rowmax .T = 24617348 ∧ step3H 1048576 1 gStream .rowmax .C = 24622468 ∧ step3H 1048576 1 gStream .lazy .T = 24609856 ∧
    step3H 1048576 1 gShuf64 .rowmax .T = 25735556 ∧ step3H 1048576 1 gShuf64 .rowmax .C = 25740676 ∧ step3H 1048576 1 gShuf64 .lazy .T = 25728064 ∧
    step3H 1048576 1 g256 .rowmax .T = 25401732 ∧ step3H 1048576 1 g256 .rowmax .C = 25406852 ∧ step3H 1048576 1 g256 .lazy .T = 25394240 ∧
    step3H 1048576 1 gShuf16 .rowmax .T = 27943300 ∧ step3H 1048576 1 gShuf16 .rowmax .C = 27948420 ∧ step3H 1048576 1 gShuf16 .lazy .T = 27935808 ∧
    step3H 1048576 1 g3x .rowmax .T = 73814404 ∧ step3H 1048576 1 g3x .rowmax .C = 73819524 ∧ step3H 1048576 1 g3x .lazy .T = 73806912 ∧
    usR 24617348 = 24617 ∧ usR 25735556 = 25736 ∧ usR 25401732 = 25402 ∧ usR 27943300 = 27943 ∧ usR 25740676 = 25741 ∧
    effRate 1048576 8 128 1 25735556 = 1669 ∧ effRate 1048576 8 128 1 25401732 = 1691 ∧ effRate 1048576 8 128 1 24617348 = 1745 ∧
    pct 25735556 tGemvUnit = 64662 ∧ usR (wallNs 25735556) = 25827 := by decide
/-- every t = 1 cell is DDR-bound: the vector block (9 276 / 11 836 / 5 530 ns) is under the block at every measured G,
    including the chained-latency bound at 174.6 (11 836 < 12 011 — by 175 ns: the vector unit has no slack there) -/
theorem T3r_t1_binding : blockMax3 gStream .rowmax .T (mergePack * 100) 1 = ddrBlock gStream 1 dH ∧
    blockMax3 gStream .rowmax .C (mergePack * 100) 1 = ddrBlock gStream 1 dH ∧ blockMax3 gStream .lazy .T (mergePack * 100) 1 = ddrBlock gStream 1 dH ∧
    blockMax3 gShuf64 .rowmax .C (mergePack * 100) 1 = ddrBlock gShuf64 1 dH ∧ blockMax3 g256 .rowmax .C (mergePack * 100) 1 = ddrBlock g256 1 dH ∧
    blockMax3 gShuf16 .rowmax .C (mergePack * 100) 1 = ddrBlock gShuf16 1 dH ∧ 12011 - 11836 = 175 := by decide
/-- fixed cost: 18 820 (rowmax-T) / 23 940 (rowmax-C) / 11 328 (lazy-T) / 13 832 (lazy-C) = 2 vector blocks + a 268 ns drain
    (round 2: 7 074 = 2 x 1 489 + 4 096 at the assumed 10 GB/s); the vector tail at L mod 16 = 15 is 3 896 (T) / 7 651 (C) -/
theorem T3r_fixed : fixed3 32768 .rowmax .T (mergePack * 100) 1 1 = 18820 ∧ fixed3 32768 .rowmax .C (mergePack * 100) 1 1 = 23940 ∧
    fixed3 32768 .lazy .T (mergePack * 100) 1 1 = 11328 ∧ fixed3 32768 .lazy .C (mergePack * 100) 1 1 = 13832 ∧
    drainBlock 1 dH (rDrainM 1) = 268 ∧ fixed3 15 .rowmax .T (mergePack * 100) 1 1 = 18820 + 3896 ∧
    fixed3 15 .rowmax .C (mergePack * 100) 1 1 = 23940 + 7651 ∧ 2 * 9276 + 268 = 18820 := by decide
/-- the new worst corner (chained-latency bound) overruns the headline by 0.7 % at 32k / 0.0 % at 1M (round 2: +9.8 % / +7.0 %);
    the lazy variant is 1 % under the headline at t = 1 -/
theorem T3r_worst_overrun : pct (792644 - 787524) 787524 = 7 ∧ pct (827588 - 822468) 822468 = 6 ∧ pct (24622468 - 24617348) 24617348 = 0 ∧
    pct 814976 822468 = 991 ∧ pct 780032 787524 = 990 := by decide

/-! ## T3r_t16, T3r_s4 — verify batches on the measured chain (`[R3-t16-*]` `[R3-s4-*]`) -/
/-- t = 16 two passes (mt = 4, 256-token blocks): 7 057 µs / 224.1 ms (rowmax-T, vector-bound 4.4x), 8 360 / 265.5 (rowmax-C),
    3 162 / 100.4 (lazy-T, 2.0x) — round 2's 1 554 µs / 49.2 ms native cell was DDR-bound; G no longer enters -/
theorem T3r_t16 : step3H 32768 16 gStream .rowmax .T = 7056644 ∧ step3H 1048576 16 gStream .rowmax .T = 224106244 ∧
    step3H 32768 16 gStream .rowmax .C = 8359802 ∧ step3H 1048576 16 gStream .rowmax .C = 265494138 ∧
    step3H 32768 16 gStream .lazy .T = 3161876 ∧ step3H 1048576 16 gStream .lazy .T = 100409620 ∧
    step3H 32768 16 gStream .lazy .C = 3807650 ∧ step3H 32768 16 gShuf64 .rowmax .T = 7056644 ∧ step3H 32768 16 gShuf64 .lazy .T = 3161876 ∧
    usR 7056644 = 7057 ∧ usR 8359802 = 8360 ∧ usR 3161876 = 3162 ∧ 224106244 / 100000 = 2241 ∧ 100409620 / 100000 = 1004 ∧
    vec3 256 4 .rowmax .T (mergePack * 100) = 27350 ∧ vec3 256 4 .lazy .T (mergePack * 100) = 12254 ∧
    pct 27350 6005 = 4555 ∧ pct 12254 6005 = 2041 ∧ step3H 4096 16 gStream .rowmax .T = 930244 ∧ step3H 131072 16 gStream .rowmax .T = 28061444 := by decide
/-- S4 one pass (mt = 8, 128-token blocks) at the pack merge: 11 596 µs / 368.3 ms (rowmax-T), 3 777 / 119.9 (lazy-T) — worse than
    two passes on every chain (164 % / 154 % / 120 % / 116 %); at the itemised merges 13 464 / 3 016 µs. Per 128-token block the
    16 per-row reduce calls alone are 23 283 ns against 3 002 ns of DDR -/
theorem T3r_s4 : step3S4 32768 gStream .rowmax .T = 11596269 ∧ step3S4 1048576 gStream .rowmax .T = 368279789 ∧
    step3S4 32768 gStream .rowmax .C = 12864597 ∧ step3S4 32768 gStream .lazy .T = 3777063 ∧ step3S4 1048576 gStream .lazy .T = 119944231 ∧
    step3S4 32768 gStream .lazy .C = 4422837 ∧
    step3 32768 16 gStream .rowmax .T (mergeItem .rowmax .T) true = 13464447 ∧ step3 32768 16 gStream .lazy .T (mergeItem .lazy .T) true = 3015963 ∧
    pct 11596269 7056644 = 1643 ∧ pct 12864597 8359802 = 1539 ∧ pct 3777063 3161876 = 1195 ∧ pct 4422837 3807650 = 1162 ∧
    vec3 128 8 .rowmax .T (mergePack * 100) = 44945 ∧ vec3 128 8 .lazy .T (mergePack * 100) = 14638 ∧ ddrBlock gStream 8 dH = 3002 ∧
    16 * 8 * tRm16 / 10 = 23283 ∧ pct 44945 3002 = 14972 ∧ pct 14638 3002 = 4876 ∧ usR 11596269 = 11596 ∧ usR 3777063 = 3777 := by decide
theorem bm3_vec (G : Nat) (v : Var) (c : Conv) (m mt : Nat) (h1 : ddrBlock G mt dH ≤ vec3 (blockOf mt) mt v c m)
    (h2 : mmaBlock mt dH ≤ vec3 (blockOf mt) mt v c m) (h3 : loaderBlock mt ≤ vec3 (blockOf mt) mt v c m) :
    blockMax3 G v c m mt = vec3 (blockOf mt) mt v c m := by
  unfold blockMax3; rw [Nat.max_eq_right h1, Nat.max_eq_left h2, Nat.max_eq_left h3]
theorem bm3_ddr (G : Nat) (v : Var) (c : Conv) (m mt : Nat) (h1 : vec3 (blockOf mt) mt v c m ≤ ddrBlock G mt dH)
    (h2 : mmaBlock mt dH ≤ ddrBlock G mt dH) (h3 : loaderBlock mt ≤ ddrBlock G mt dH) :
    blockMax3 G v c m mt = ddrBlock G mt dH := by
  unfold blockMax3; rw [Nat.max_eq_left h1, Nat.max_eq_left h2, Nat.max_eq_left h3]
/-- the 12 128-vs-25 750 question is MOOT: S4 loses to two passes at 32k for EVERY merge count on the rowmax chain (and on the
    lazy chain) — the 128-token block pays the per-fragment calls twice as often per token as the 256-token block -/
theorem T3r_s4_dominated_rowmaxT (m : Nat) : step3 32768 16 gStream .rowmax .T m false < step3 32768 16 gStream .rowmax .T m true := by
  have hm4 : mtS 16 false = 4 := by decide
  have hm8 : mtS 16 true = 8 := by decide
  have hp2 : pn 32768 16 false = 256 := by decide
  have hp1 : pn 32768 16 true = 256 := by decide
  have hb4 : blockOf 4 = 256 := by decide
  have hb8 : blockOf 8 = 128 := by decide
  have hmo : mtOf (rowsOf 16 gH) = 8 := by decide
  have hd4 : drainBlock 4 dH (rDrainM 4) = 344 := by decide
  have hd8 : drainBlock 8 dH (rDrainM 8) = 459 := by decide
  have htl : tailOps 32768 8 dH = 0 := by decide
  have hddr4 : ddrBlock gStream 4 dH = 6005 := by decide
  have hddr8 : ddrBlock gStream 8 dH = 3002 := by decide
  have hmm4 : mmaBlock 4 dH = 1920 := by decide
  have hmm8 : mmaBlock 8 dH = 1920 := by decide
  have hl4 : loaderBlock 4 = 1236 := by decide
  have hl8 : loaderBlock 8 = 1236 := by decide
  have h4 : blockMax3 gStream .rowmax .T m 4 = vec3 (blockOf 4) 4 .rowmax .T m :=
    bm3_vec _ _ _ _ _ (by rw [hb4, hddr4, vec3_rowmaxT_256_4]; omega) (by rw [hb4, hmm4, vec3_rowmaxT_256_4]; omega)
      (by rw [hb4, hl4, vec3_rowmaxT_256_4]; omega)
  have h8 : blockMax3 gStream .rowmax .T m 8 = vec3 (blockOf 8) 8 .rowmax .T m :=
    bm3_vec _ _ _ _ _ (by rw [hb8, hddr8, vec3_rowmaxT_128_8]; omega) (by rw [hb8, hmm8, vec3_rowmaxT_128_8]; omega)
      (by rw [hb8, hl8, vec3_rowmaxT_128_8]; omega)
  unfold step3
  rw [hm4, hm8, hp2, hp1, h4, h8]
  unfold fixed3
  rw [hb4, hb8, hd4, hd8, hmo, htl, vec3_rowmaxT_256_4, vec3_rowmaxT_128_8, unitT32]
  unfold rVecCore; omega
theorem T3r_s4_dominated_lazyT (m : Nat) : step3 32768 16 gStream .lazy .T m false < step3 32768 16 gStream .lazy .T m true := by
  have hm4 : mtS 16 false = 4 := by decide
  have hm8 : mtS 16 true = 8 := by decide
  have hp2 : pn 32768 16 false = 256 := by decide
  have hp1 : pn 32768 16 true = 256 := by decide
  have hb4 : blockOf 4 = 256 := by decide
  have hb8 : blockOf 8 = 128 := by decide
  have hmo : mtOf (rowsOf 16 gH) = 8 := by decide
  have hd4 : drainBlock 4 dH (rDrainM 4) = 344 := by decide
  have hd8 : drainBlock 8 dH (rDrainM 8) = 459 := by decide
  have htl : tailOps 32768 8 dH = 0 := by decide
  have hddr4 : ddrBlock gStream 4 dH = 6005 := by decide
  have hddr8 : ddrBlock gStream 8 dH = 3002 := by decide
  have hmm4 : mmaBlock 4 dH = 1920 := by decide
  have hmm8 : mmaBlock 8 dH = 1920 := by decide
  have hl4 : loaderBlock 4 = 1236 := by decide
  have hl8 : loaderBlock 8 = 1236 := by decide
  have h4 : blockMax3 gStream .lazy .T m 4 = vec3 (blockOf 4) 4 .lazy .T m :=
    bm3_vec _ _ _ _ _ (by rw [hb4, hddr4, vec3_lazyT_256_4]; omega) (by rw [hb4, hmm4, vec3_lazyT_256_4]; omega)
      (by rw [hb4, hl4, vec3_lazyT_256_4]; omega)
  have h8 : blockMax3 gStream .lazy .T m 8 = vec3 (blockOf 8) 8 .lazy .T m :=
    bm3_vec _ _ _ _ _ (by rw [hb8, hddr8, vec3_lazyT_128_8]; omega) (by rw [hb8, hmm8, vec3_lazyT_128_8]; omega)
      (by rw [hb8, hl8, vec3_lazyT_128_8]; omega)
  unfold step3
  rw [hm4, hm8, hp2, hp1, h4, h8]
  unfold fixed3
  rw [hb4, hb8, hd4, hd8, hmo, htl, vec3_lazyT_256_4, vec3_lazyT_128_8, unitT32]
  unfold rVecCore; omega

/-! ## T3r_regime, T3r_rows_star — the regime map at 32k on the measured chain (`[R3-regime-*]` `[R3-rows*-*]`) -/
/-- at the design's page (167.0): t = 1, 2 are the KV stream on every chain (822 / 828 / 815 / 817 µs); t = 4 is vector-bound on the
    rowmax chain (1 225 µs, 1.48x) and on lazy-C (896), DDR-bound on lazy-T (826); t = 8 and 16 are vector-bound on every chain -/
theorem T3r_regime : usR (step3H 32768 1 gShuf64 .rowmax .T) = 822 ∧ usR (step3H 32768 1 gShuf64 .rowmax .C) = 828 ∧
    usR (step3H 32768 1 gShuf64 .lazy .T) = 815 ∧ usR (step3H 32768 1 gShuf64 .lazy .C) = 817 ∧
    step3H 32768 2 gShuf64 .rowmax .T = step3H 32768 1 gShuf64 .rowmax .T ∧ step3H 32768 2 gShuf64 .lazy .T = step3H 32768 1 gShuf64 .lazy .T ∧
    usR (step3H 32768 4 gShuf64 .rowmax .T) = 1225 ∧ usR (step3H 32768 4 gShuf64 .rowmax .C) = 1563 ∧
    usR (step3H 32768 4 gShuf64 .lazy .T) = 826 ∧ usR (step3H 32768 4 gShuf64 .lazy .C) = 896 ∧
    usR (step3H 32768 8 gShuf64 .rowmax .T) = 3556 ∧ usR (step3H 32768 8 gShuf64 .rowmax .C) = 4212 ∧
    usR (step3H 32768 8 gShuf64 .lazy .T) = 1593 ∧ usR (step3H 32768 8 gShuf64 .lazy .C) = 1919 ∧
    usR (step3H 32768 16 gShuf64 .rowmax .T) = 7057 ∧ usR (step3H 32768 16 gShuf64 .rowmax .C) = 8360 ∧
    usR (step3H 32768 16 gShuf64 .lazy .T) = 3162 ∧ usR (step3H 32768 16 gShuf64 .lazy .C) = 3808 ∧
    step3H 32768 4 gStream .rowmax .T = step3H 32768 4 gShuf64 .rowmax .T ∧ usR (step3H 32768 4 gStream .lazy .T) = 791 := by decide
/-- the binding engine per cell is the per-block comparison: vector / DDR shares 73.9 / 94.3 / 44.0 / 54.0 % (t = 1, 2),
    147.7 / 188.5 / 88.1 / 108.0 % (t = 4, mt = 2), 435.6 / 516.1 / 195.2 / 235.1 % (t = 8, 16; mt = 4, 256-token blocks) at 167.0 -/
theorem T3r_regime_binding : pct 593664 803648 = 739 ∧ pct 757504 803648 = 943 ∧ pct 353920 803648 = 440 ∧ pct 434048 803648 = 540 ∧
    pct 1187328 803648 = 1477 ∧ pct 1515008 803648 = 1885 ∧ pct 707904 803648 = 881 ∧ pct 868160 803648 = 1080 ∧
    pct 3500800 803584 = 4356 ∧ pct 4147328 803584 = 5161 ∧ pct 1568512 803584 = 1952 ∧ pct 1888896 803584 = 2351 ∧
    64 * vec3 512 1 .rowmax .T (mergePack * 100) = 593664 ∧ 64 * ddrBlock gShuf64 1 dH = 803648 ∧
    64 * vec3 512 2 .rowmax .T (mergePack * 100) = 1187328 ∧ 128 * vec3 256 4 .rowmax .T (mergePack * 100) = 3500800 ∧ 128 * ddrBlock gShuf64 4 dH = 803584 := by decide
/-- rows*: the vector chain reaches the block from mt = 2 (rows* = 32, t ≥ 4 at g = 8) on the rowmax chain at either convention and
    on lazy-C; from mt = 3 (rows* = 48, t ≥ 6) on lazy-T. Round 2's native corner said 112 (mt = 7) -/
theorem T3r_rows_star : vec3 (blockOf 1) 1 .rowmax .T (mergePack * 100) < ddrBlock gStream 1 dH ∧ ddrBlock gStream 2 dH ≤ vec3 (blockOf 2) 2 .rowmax .T (mergePack * 100) ∧
    vec3 (blockOf 1) 1 .rowmax .C (mergePack * 100) < ddrBlock gStream 1 dH ∧ ddrBlock gStream 2 dH ≤ vec3 (blockOf 2) 2 .rowmax .C (mergePack * 100) ∧
    vec3 (blockOf 1) 1 .lazy .T (mergePack * 100) < ddrBlock gStream 1 dH ∧ vec3 (blockOf 2) 2 .lazy .T (mergePack * 100) < ddrBlock gStream 2 dH ∧
    ddrBlock gStream 3 dH ≤ vec3 (blockOf 3) 3 .lazy .T (mergePack * 100) ∧
    vec3 (blockOf 1) 1 .lazy .C (mergePack * 100) < ddrBlock gStream 1 dH ∧ ddrBlock gStream 2 dH ≤ vec3 (blockOf 2) 2 .lazy .C (mergePack * 100) ∧
    vec3 (blockOf 2) 2 .rowmax .T (mergePack * 100) = 18552 ∧ vec3 (blockOf 2) 2 .lazy .T (mergePack * 100) = 11061 ∧
    vec3 (blockOf 3) 3 .lazy .T (mergePack * 100) = 9190 ∧ ddrBlock gStream 3 dH = 6005 ∧ 2 * 16 = 32 ∧ 3 * 16 = 48 ∧ ceilDiv 32 8 = 4 ∧ ceilDiv 48 8 = 6 := by decide

/-! ## T3r_form — closed forms of the t = 1 step for every L and every G ≤ 174.6 (the block is DDR-bound on each chain) -/
theorem T3r_form_rowmaxT (L G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    step3H L 1 G .rowmax .T = ((16 * (L / 16) + 511) / 512) * (20971520 / G) + 18820 + (L % 16) * 8192 * 137 * 10 / 43200 := by
  have hm : mtS 1 false = 1 := by decide
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hmo : mtOf (rowsOf 1 gH) = 1 := by decide
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 dH = 20971520 / G := by unfold ddrBlock tn coreTok dH; rw [hbl]
  have hge : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  have hv : vec3 (blockOf 1) 1 .rowmax .T (mergePack * 100) = 9276 := by decide
  have hmm : mmaBlock 1 dH = 960 := by decide
  have hl : loaderBlock 1 = 618 := by decide
  have hd : drainBlock 1 dH (rDrainM 1) = 268 := by decide
  have hmax : blockMax3 G .rowmax .T (mergePack * 100) 1 = 20971520 / G := by
    rw [← hddr]; exact bm3_ddr _ _ _ _ _ (by rw [hv, hddr]; omega) (by rw [hmm, hddr]; omega) (by rw [hl, hddr]; omega)
  unfold step3H step3 pn
  rw [hm, hp, hmax]
  unfold fixed3
  rw [hv, hd, hmo, unitT32]
  unfold nblocks lMatrix ceilDiv tailOps dH rVecCore
  rw [hbl]
  simp only [Nat.one_mul, Nat.mul_one]
  have ha : (16 * (L / 16) + 512 - 1) / 512 = (16 * (L / 16) + 511) / 512 := by omega
  rw [ha]
  omega
theorem T3r_form_rowmaxC (L G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    step3H L 1 G .rowmax .C = ((16 * (L / 16) + 511) / 512) * (20971520 / G) + 23940 + (L % 16) * 8192 * 269 * 10 / 43200 := by
  have hm : mtS 1 false = 1 := by decide
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hmo : mtOf (rowsOf 1 gH) = 1 := by decide
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 dH = 20971520 / G := by unfold ddrBlock tn coreTok dH; rw [hbl]
  have hge : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  have hv : vec3 (blockOf 1) 1 .rowmax .C (mergePack * 100) = 11836 := by decide
  have hmm : mmaBlock 1 dH = 960 := by decide
  have hl : loaderBlock 1 = 618 := by decide
  have hd : drainBlock 1 dH (rDrainM 1) = 268 := by decide
  have hmax : blockMax3 G .rowmax .C (mergePack * 100) 1 = 20971520 / G := by
    rw [← hddr]; exact bm3_ddr _ _ _ _ _ (by rw [hv, hddr]; omega) (by rw [hmm, hddr]; omega) (by rw [hl, hddr]; omega)
  unfold step3H step3 pn
  rw [hm, hp, hmax]
  unfold fixed3
  rw [hv, hd, hmo, unitC32]
  unfold nblocks lMatrix ceilDiv tailOps dH rVecCore
  rw [hbl]
  simp only [Nat.one_mul, Nat.mul_one]
  have ha : (16 * (L / 16) + 512 - 1) / 512 = (16 * (L / 16) + 511) / 512 := by omega
  rw [ha]
  omega
theorem T3r_form_lazyT (L G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    step3H L 1 G .lazy .T = ((16 * (L / 16) + 511) / 512) * (20971520 / G) + 11328 + (L % 16) * 8192 * 137 * 10 / 43200 := by
  have hm : mtS 1 false = 1 := by decide
  have hp : pSel (rowsOf 1 gH) false = 1 := by decide
  have hmo : mtOf (rowsOf 1 gH) = 1 := by decide
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 dH = 20971520 / G := by unfold ddrBlock tn coreTok dH; rw [hbl]
  have hge : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  have hv : vec3 (blockOf 1) 1 .lazy .T (mergePack * 100) = 5530 := by decide
  have hmm : mmaBlock 1 dH = 960 := by decide
  have hl : loaderBlock 1 = 618 := by decide
  have hd : drainBlock 1 dH (rDrainM 1) = 268 := by decide
  have hmax : blockMax3 G .lazy .T (mergePack * 100) 1 = 20971520 / G := by
    rw [← hddr]; exact bm3_ddr _ _ _ _ _ (by rw [hv, hddr]; omega) (by rw [hmm, hddr]; omega) (by rw [hl, hddr]; omega)
  unfold step3H step3 pn
  rw [hm, hp, hmax]
  unfold fixed3
  rw [hv, hd, hmo, unitT32]
  unfold nblocks lMatrix ceilDiv tailOps dH rVecCore
  rw [hbl]
  simp only [Nat.one_mul, Nat.mul_one]
  have ha : (16 * (L / 16) + 512 - 1) / 512 = (16 * (L / 16) + 511) / 512 := by omega
  rw [ha]
  omega

/-! ## T3r_crossover — attention = one 398 µs GEMV unit, re-instantiated (`[R3-crossover-*]`) -/
/-- the stream basis per block (12 011 ns at 174.6) is unchanged, so over the 512-multiples the crossover is k ≥ 33
    (L_eq = 16 896) iff the fixed cost lies in [1 637, 13 647] ns; round 2's 7 074 passed, the measured rowmax chain's 18 820 does not -/
theorem T3r_crossover_iff (fixed : Nat) : (∀ k, tGemvUnit ≤ 12011 * k + fixed ↔ 33 ≤ k) ↔ (1637 ≤ fixed ∧ fixed ≤ 13647) := by
  unfold tGemvUnit; constructor
  · intro h
    have h32 := h 32
    have h33 := (h 33).mpr (Nat.le_refl 33)
    exact ⟨by omega, Nat.le_of_not_lt (fun hc => by have := h32.mp (by omega); omega)⟩
  · intro h k; constructor <;> intro hh <;> omega
theorem T3r_crossover_iff_32 (fixed : Nat) (h1 : 13648 ≤ fixed) (h2 : fixed ≤ 25658) : ∀ k, tGemvUnit ≤ 12011 * k + fixed ↔ 32 ≤ k := by
  unfold tGemvUnit; intro k; constructor <;> intro hh <;> omega
/-- CORRECTION (round-2 banner "T_crossover: 16 896 survives"): on the measured per-row-max chain the crossover over the
    512-multiples moves to k ≥ 32, L_eq = 16 384 (403.2 µs there, 391.2 at 15 872) at the 174.6 basis — the stream term is
    unchanged, the fixed cost (18 820) is not; the lazy chain (11 328) keeps k ≥ 33 = 16 896 -/
theorem T3r_crossover_rowmaxT (k : Nat) : (tGemvUnit ≤ step3H (512 * k) 1 gStream .rowmax .T ↔ 32 ≤ k) ∧
    step3H 16384 1 gStream .rowmax .T = 403172 ∧ step3H 15872 1 gStream .rowmax .T = 391161 ∧ 32 * 512 = 16384 := by
  refine ⟨?_, by decide, by decide, by decide⟩
  rw [T3r_form_rowmaxT _ _ (by decide) (by decide)]; unfold tGemvUnit gStream rGemm
  constructor <;> intro h <;> omega
theorem T3r_crossover_rowmaxC (k : Nat) : (tGemvUnit ≤ step3H (512 * k) 1 gStream .rowmax .C ↔ 32 ≤ k) ∧
    step3H 16384 1 gStream .rowmax .C = 408292 ∧ step3H 15872 1 gStream .rowmax .C = 396281 := by
  refine ⟨?_, by decide, by decide⟩
  rw [T3r_form_rowmaxC _ _ (by decide) (by decide)]; unfold tGemvUnit gStream rGemm
  constructor <;> intro h <;> omega
theorem T3r_crossover_lazyT (k : Nat) : (tGemvUnit ≤ step3H (512 * k) 1 gStream .lazy .T ↔ 33 ≤ k) ∧
    step3H 16896 1 gStream .lazy .T = 407691 ∧ step3H 16384 1 gStream .lazy .T = 395680 := by
  refine ⟨?_, by decide, by decide⟩
  rw [T3r_form_lazyT _ _ (by decide) (by decide)]; unfold tGemvUnit gStream rGemm
  constructor <;> intro h <;> omega
/-- on the attention path's own measured rates the crossover is one block lower still: k ≥ 31 (15 872) at 167.0 / 169.0 / 169.2
    on the rowmax chain, k ≥ 31 / 32 / 32 on the lazy chain -/
theorem T3r_crossover_meas (k : Nat) : (tGemvUnit ≤ step3H (512 * k) 1 gShuf64 .rowmax .T ↔ 31 ≤ k) ∧
    (tGemvUnit ≤ step3H (512 * k) 1 gSeq64 .rowmax .T ↔ 31 ≤ k) ∧ (tGemvUnit ≤ step3H (512 * k) 1 g256 .rowmax .T ↔ 31 ≤ k) ∧
    (tGemvUnit ≤ step3H (512 * k) 1 gShuf64 .lazy .T ↔ 31 ≤ k) ∧ (tGemvUnit ≤ step3H (512 * k) 1 gSeq64 .lazy .T ↔ 32 ≤ k) ∧
    (tGemvUnit ≤ step3H (512 * k) 1 g256 .lazy .T ↔ 32 ≤ k) := by
  rw [T3r_form_rowmaxT _ _ (by decide) (by decide), T3r_form_rowmaxT _ _ (by decide) (by decide), T3r_form_rowmaxT _ _ (by decide) (by decide),
    T3r_form_lazyT _ _ (by decide) (by decide), T3r_form_lazyT _ _ (by decide) (by decide), T3r_form_lazyT _ _ (by decide) (by decide)]
  unfold tGemvUnit gShuf64 gSeq64 g256
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
/-- over every L: the rowmax chain crosses monotonically at L ≥ 15 888 (the 32nd block charged from its first 16-token group);
    the lazy chain is NOT monotone between 15 888 and 16 399 (the vector tail decides: L mod 16 ≥ 9) and crosses for good at 16 400 -/
theorem T3r_crossover_anyL_rowmaxT (L : Nat) : tGemvUnit ≤ step3H L 1 gStream .rowmax .T ↔ 15888 ≤ L := by
  rw [T3r_form_rowmaxT _ _ (by decide) (by decide)]; unfold tGemvUnit gStream rGemm
  constructor <;> intro h <;> omega
theorem T3r_crossover_anyL_lazyT (L : Nat) : tGemvUnit ≤ step3H L 1 gStream .lazy .T ↔ 16400 ≤ L ∨ (15888 ≤ L ∧ 9 ≤ L % 16) := by
  rw [T3r_form_lazyT _ _ (by decide) (by decide)]; unfold tGemvUnit gStream rGemm
  constructor <;> intro h <;> omega
theorem T3r_crossover_anyL_cells : step3H 15888 1 gStream .rowmax .T = 403172 ∧ step3H 15887 1 gStream .rowmax .T = 395057 ∧
    step3H 15897 1 gStream .lazy .T = 398018 ∧ step3H 15904 1 gStream .lazy .T = 395680 ∧ step3H 16400 1 gStream .lazy .T = 407691 ∧
    step3H 16399 1 gStream .lazy .T = 399576 := by decide

/-! ## T_gqa_matrix at the measured rho32 = 1.37 (`[R3-gqa-137]`): the general theorem in hundredths, and its cells -/
theorem T_gqa_matrix_100 (rows rho100 d : Nat) (hd : 0 < d) (h : 200 ≤ rows * rho100) :
    4 * d * 80 * 432 * 100 < 4 * rows * d * rho100 * 10 * 1746 := by
  have e1 : 4 * rows * d * rho100 * 10 * 1746 = 4 * d * (rows * rho100 * 10 * 1746) := by ac_rfl
  have e2 : 4 * d * 80 * 432 * 100 = 4 * d * (80 * 432 * 100) := by ac_rfl
  rw [e1, e2]
  apply (Nat.mul_lt_mul_left (by omega)).mpr
  have := Nat.mul_le_mul_right (10 * 1746) h
  omega
/-- the vector-dot route is 69.2 % of the KV stream at rows = 1 (DDR-bound), 138.4 % at rows = 2, 553.7 % at rows = 8 (g = 8, t = 1):
    T_gqa_matrix survives unchanged — compute-bound for every rows ≥ 2 since 2 x 1.37 ≥ 2 -/
theorem T3r_gqa_137 : dotRatioT100 1 rho32_100 128 = 692 ∧ dotRatioT100 2 rho32_100 128 = 1384 ∧ dotRatioT100 4 rho32_100 128 = 2768 ∧
    dotRatioT100 8 rho32_100 128 = 5537 ∧ dotRatioT100 16 rho32_100 128 = 11074 ∧ dotRatioT100 1 rho32_100 128 < 1000 ∧
    200 ≤ 2 * rho32_100 ∧ 2 * rho32_100 < 400 ∧ 4 * 1 * 128 * 137 * 10 * 1746 < 4 * 128 * 80 * 432 * 100 := by decide
theorem T3r_gqa_137_g (t g d : Nat) (hd : 0 < d) (hg : 2 ≤ g) (ht : 1 ≤ t) :
    4 * d * 80 * 432 * 100 < 4 * rowsOf t g * d * rho32_100 * 10 * 1746 := by
  apply T_gqa_matrix_100 (rowsOf t g) rho32_100 d hd
  unfold rowsOf rho32_100
  have h1 : g ≤ t * g := Nat.le_mul_of_pos_left g ht
  omega

/-! ## T3r_fleet_G — the E21 fleet statement re-instantiated (`[R3-fleet-G-*]`): G* with the measured fixed cost -/
/-- MoE 128k: attention-bound iff G ≤ 168.3 (rowmax-T) / 167.9 (lazy-T) / 168.6 (rowmax-C) — round 2 said 167.7 at fixed 7 074 -/
theorem T3r_fleet_G_moe_128k_rowmaxT (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerMoe ≤ step3H 131072 1 G .rowmax .T ↔ G ≤ 1683 := by
  rw [T3r_form_rowmaxT 131072 G h1 h2]; unfold tLayerMoe
  have key : 12457 ≤ 20971520 / G ↔ G ≤ 1683 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_128k_lazyT (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerMoe ≤ step3H 131072 1 G .lazy .T ↔ G ≤ 1679 := by
  rw [T3r_form_lazyT 131072 G h1 h2]; unfold tLayerMoe
  have key : 12486 ≤ 20971520 / G ↔ G ≤ 1679 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_128k_rowmaxC (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerMoe ≤ step3H 131072 1 G .rowmax .C ↔ G ≤ 1686 := by
  rw [T3r_form_rowmaxC 131072 G h1 h2]; unfold tLayerMoe
  have key : 12437 ≤ 20971520 / G ↔ G ≤ 1686 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
/-- the other cells on the headline chain: dense 32k ≤ 7.3, dense 128k ≤ 29.4, MoE 32k ≤ 42.0 (round 2: 41.9); both 1M cells at every G -/
theorem T3r_fleet_G_dense_32k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerDense ≤ step3H 32768 1 G .rowmax .T ↔ G ≤ 73 := by
  rw [T3r_form_rowmaxT 32768 G h1 h2]; unfold tLayerDense
  have key : 284972 ≤ 20971520 / G ↔ G ≤ 73 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_dense_128k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerDense ≤ step3H 131072 1 G .rowmax .T ↔ G ≤ 294 := by
  rw [T3r_form_rowmaxT 131072 G h1 h2]; unfold tLayerDense
  have key : 71243 ≤ 20971520 / G ↔ G ≤ 294 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_32k (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerMoe ≤ step3H 32768 1 G .rowmax .T ↔ G ≤ 420 := by
  rw [T3r_form_rowmaxT 32768 G h1 h2]; unfold tLayerMoe
  have key : 49827 ≤ 20971520 / G ↔ G ≤ 420 := by
    rw [Nat.le_div_iff_mul_le h1]; constructor <;> intro h <;> omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_1M (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) : tLayerDense ≤ step3H 1048576 1 G .rowmax .T ∧ tLayerMoe ≤ step3H 1048576 1 G .rowmax .T := by
  rw [T3r_form_rowmaxT 1048576 G h1 h2]; unfold tLayerDense tLayerMoe
  have : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  constructor <;> omega
/-- THE DESIGN CONSTRAINT (`[R3-fleet-G-*-moe-128k]`): at the design's 64 KiB page (167.0) the MoE-128k cell is ATTENTION-bound
    on every chain (by 25.7 / 18.2 / 30.8 µs = 0.8 / 0.6 / 1.0 % of the 3.21 ms layer); at 256 KiB (169.2) it is weights-bound
    (by 16.0 / 23.5 / 10.9 µs = 0.5 / 0.7 / 0.3 %); at 16 KiB attention-bound by 9.4 %; at the W8 ceiling 174.6 weights-bound by 3.6 % -/
theorem T3r_fleet_moe_128k_cells : tLayerMoe ≤ step3H 131072 1 gShuf64 .rowmax .T ∧ tLayerMoe ≤ step3H 131072 1 gShuf64 .lazy .T ∧
    tLayerMoe ≤ step3H 131072 1 gShuf64 .rowmax .C ∧ tLayerMoe ≤ step3H 131072 1 gShuf16 .rowmax .T ∧
    step3H 131072 1 g256 .rowmax .T < tLayerMoe ∧ step3H 131072 1 g256 .lazy .T < tLayerMoe ∧ step3H 131072 1 g256 .rowmax .C < tLayerMoe ∧
    step3H 131072 1 gSeq64 .rowmax .T < tLayerMoe ∧ step3H 131072 1 gStream .rowmax .T < tLayerMoe ∧
    3233412 - tLayerMoe = 25693 ∧ 3225920 - tLayerMoe = 18201 ∧ 3238532 - tLayerMoe = 30813 ∧ tLayerMoe - 3191684 = 16035 ∧
    tLayerMoe - 3184192 = 23527 ∧ tLayerMoe - 3196804 = 10915 ∧ tLayerMoe - 3195524 = 12195 ∧ tLayerMoe - 3093636 = 114083 ∧
    pct 25693 tLayerMoe = 8 ∧ pct 16035 tLayerMoe = 5 ∧ pct 301661 tLayerMoe = 94 ∧ pct 114083 tLayerMoe = 36 ∧
    gShuf64 ≤ 1683 ∧ 1683 < gSeq64 ∧ 1683 < g256 ∧ gShuf64 ≤ 1679 ∧ 1679 < g256 ∧ 1686 < g256 := by decide
/-- CORRECTION of the HW-MAP reading "MoE-128k stays stream-bound at 64 KiB by 0.7 GB/s": the round-2 line (T_fleet_G_moe_128k) is
    "attention-bound iff G ≤ 167.7", and the measured 167.0 is BELOW it — attention-bound already in the round-2 model, and the
    bare stream (256 x 12 557 = 3 214 592 ns) exceeds the MoE layer (3 207 719) before any fixed cost -/
theorem T3r_moe_128k_direction : tLayerMoe ≤ stepH 131072 1 gShuf64 cvNat 1 ∧ gShuf64 ≤ 1677 ∧ 256 * ddrBlock gShuf64 1 128 = 3214592 ∧
    tLayerMoe < 3214592 ∧ 3214592 - tLayerMoe = 6873 ∧ stepH 131072 1 gShuf64 cvNat 1 = 3221666 :=
  ⟨(T_fleet_G_moe_128k gShuf64 (by decide) (by decide)).mpr (by decide), by decide, by decide, by decide, by decide, by decide⟩

/-! ## T3r_page — the page-size verdict (`[R3-page-*]`): measured sizes, two-tier on the measured base, the c_pg rule -/
/-- 16 / 64 / 256 KiB: 153.8 / 167.0 / 169.2 — 64 KiB is 1.3 % under 256 KiB, 16 KiB 7.9 % under 64 KiB and 9.1 % under 256 KiB;
    tail waste per layer-sequence 0.25 / 1.00 / 4.00 MiB -/
theorem T3r_page_sizes : pct (g256 - gShuf64) g256 = 13 ∧ pct (gShuf64 - gShuf16) gShuf64 = 79 ∧ pct (g256 - gShuf16) g256 = 91 ∧
    16 * (16384 - 256) = 258048 ∧ 16 * (65536 - 256) = 1044480 ∧ 16 * (262144 - 256) = 4190208 ∧ 1044480 ≤ MiB ∧ 4190208 ≤ 4 * MiB ∧
    gPage3 65536 39 = 1669 ∧ gPage3 65536 0 = 1690 ∧ gPage3 262144 0 = 1692 ∧ gPage3 16384 59 = 1538 ∧ gPage3 262144 3 = 1692 := by decide
/-- two-tier (1 MiB extents + 64 KiB tails) on the measured base, versus 64 KiB and 256 KiB pages at the same extra per-page cost c:
    c = 0: 169.2 vs 169.0 / 169.2; c = 39 (measured lower bound): 169.1 vs 166.9 / 168.7 (+1.3 %); c = 100: +3.2 %; c = 153: +4.7 %;
    c = 160: +5.0 %; c = 200: +6.1 %; c = 500: +15.1 %; c = 2 µs: +58.3 % — the ALTERNATIVES verdict (−13.2 % at 0.5 µs) assumed c = 500 -/
theorem T3r_page_tier : gTier3 32768 0 = 1692 ∧ gTier3 32768 39 = 1691 ∧ gTier3 32768 100 = 1689 ∧ gTier3 32768 153 = 1687 ∧
    gTier3 32768 160 = 1687 ∧ gTier3 32768 200 = 1685 ∧ gTier3 32768 500 = 1675 ∧ gTier3 32768 2000 = 1626 ∧
    gTier3 34768 39 = 1687 ∧ gTier3 1048576 39 = 1691 ∧ gTier3 1048576 2000 = 1626 ∧
    gPage3 65536 100 = 1637 ∧ gPage3 65536 153 = 1611 ∧ gPage3 65536 159 = 1608 ∧ gPage3 65536 160 = 1607 ∧ gPage3 65536 200 = 1588 ∧
    gPage3 65536 500 = 1455 ∧ gPage3 65536 2000 = 1027 ∧ gPage3 262144 39 = 1687 ∧ gPage3 262144 500 = 1626 ∧ gPage3 262144 2000 = 1457 ∧
    pct (gTier3 32768 39 - gPage3 65536 39) (gPage3 65536 39) = 13 ∧ pct (gTier3 32768 153 - gPage3 65536 153) (gPage3 65536 153) = 47 ∧
    pct (gTier3 32768 159 - gPage3 65536 159) (gPage3 65536 159) = 49 ∧ pct (gTier3 32768 160 - gPage3 65536 160) (gPage3 65536 160) = 50 ∧
    pct (gTier3 32768 500 - gPage3 65536 500) (gPage3 65536 500) = 151 ∧ pct (gTier3 32768 2000 - gPage3 65536 2000) (gPage3 65536 2000) = 583 := by decide

/-! ## T3r_drain, T3r_sigma, T3r_online, T3r_i8 — the remaining measured rows -/
/-- the measured drain rates satisfy the round-2 iff thresholds (35 / 69 / 123 / 164 tenths) with 43.6x / 32.2x / 21.2x / 17.4x margin:
    the drain is hidden at every mt (268 / 368 / 283 / 344 ns per block = 2.2 / 3.1 / 4.7 / 5.7 %) -/
theorem T3r_drain_hidden : drainBlock 1 128 rDrain1 ≤ ddrBlock gStream 1 128 ∧ drainBlock 2 128 rDrain2 ≤ ddrBlock gStream 2 128 ∧
    drainBlock 3 128 rDrain3 ≤ ddrBlock gStream 3 128 ∧ drainBlock 4 128 rDrain4 ≤ ddrBlock gStream 4 128 :=
  ⟨(T2_drain_threshold rDrain1 (by decide)).1.mpr (by decide), (T2_drain_threshold rDrain2 (by decide)).2.1.mpr (by decide),
   (T2_drain_threshold rDrain3 (by decide)).2.2.1.mpr (by decide), (T2_drain_threshold rDrain4 (by decide)).2.2.2.mpr (by decide)⟩
theorem T3r_drain_cells : x10 rDrain1 35 = 436 ∧ x10 rDrain2 69 = 322 ∧ x10 rDrain3 123 = 211 ∧ x10 rDrain4 164 = 174 ∧
    drainBlock 1 128 rDrain1 = 268 ∧ drainBlock 2 128 rDrain2 = 368 ∧ drainBlock 3 128 rDrain3 = 283 ∧ drainBlock 4 128 rDrain4 = 344 ∧
    pct 268 12011 = 22 ∧ pct 368 12011 = 31 ∧ pct 283 6005 = 47 ∧ pct 344 6005 = 57 ∧ rDrainM 1 = rDrain1 ∧ rDrainM 4 = rDrain4 ∧ rDrainM 8 = rDrain4 := by decide
/-- sigma_s = 19.9 ns: the 256-compare tail is 5 094 ns = 42.4 % of the block (round 2: 512 ns, 4.3 %), under the 47 ns bind line
    (T2_sigma instantiated at 20); 16 reduce-max calls (2 910 ns, 24.2 %) replace it, 1.7x cheaper; an all-scalar max is 13.5x the block -/
theorem T3r_sigma : 256 * sigma3 / 10 = 5094 ∧ pct 5094 12011 = 424 ∧ scalarBlock 1 20 < ddrBlock gStream 1 128 ∧ sigma3 / 10 < 47 ∧
    16 * tRm16 / 10 = 2910 ∧ pct 2910 12011 = 242 ∧ 5094 * 10 / 2910 = 17 ∧ 8192 * sigma3 / 10 = 163020 ∧ x10 163020 12011 = 135 := by decide
/-- online vs two-pass at the measured merge: re-streaming K costs 6 204 ns per block at 169.0 against 596 (pack) / 1 501 / 1 790 ns
    (itemised T / C): online wins 10.4x / 4.1x / 3.4x (round 2: 18x at 7 000) -/
theorem T3r_online : tn (512 * 128 * 2 * 8) gSeq64 = 6204 ∧ 6204 * 10 / 596 = 104 ∧ 6204 * 10 / 1501 = 41 ∧ 6204 * 10 / 1790 = 34 ∧
    tn (512 * 128 * 2 * 8) gStream = 6005 ∧ 6005 * 10 / 596 = 100 := by decide
/-- KV-int8 on the measured chain at 167.0: 612 µs / 19.0 ms on the rowmax chain — VECTOR-bound (the halved stream 6 278 ns per block
    is under the 9 276 ns chain), 413 µs / 12.9 ms DDR-bound on the lazy chain: the KV-int8 lever pays only with the lazy chain -/
theorem T3r_i8 : step3I8 32768 1 gShuf64 .rowmax .T (mergePack * 100) = 612484 ∧ step3I8 1048576 1 gShuf64 .rowmax .T (mergePack * 100) = 19016068 ∧
    step3I8 32768 1 gShuf64 .lazy .T (mergePack * 100) = 413152 ∧ step3I8 1048576 1 gShuf64 .lazy .T (mergePack * 100) = 12869696 ∧
    64 * ddrBlock gShuf64 1 dH / 2 = 401824 ∧ 64 * vec3 512 1 .rowmax .T (mergePack * 100) = 593664 ∧ 401824 < 593664 ∧
    64 * vec3 512 1 .lazy .T (mergePack * 100) = 353920 ∧ 353920 < 401824 ∧ usR 612484 = 612 ∧ usR 413152 = 413 := by decide

/-! ## T3r_moved — the round-2 headline cells beside their round-3 replacements (`[R3-moved-*]`) -/
theorem T3r_moved : stepH 32768 1 gStream cvNat 1 = 775778 ∧ step3H 32768 1 gStream .rowmax .T = 787524 ∧ step3H 32768 1 gShuf64 .rowmax .T = 822468 ∧
    stepH 32768 1 gStream cvWorst 2 = 851470 ∧ step3H 32768 1 gShuf64 .rowmax .C = 827588 ∧
    stepH 32768 1 gPage64k cvNat 1 = 903650 ∧ stepH 32768 1 gGather3x cvNat 1 = 2313186 ∧ step3H 32768 1 g3x .rowmax .T = 2324932 ∧
    step3H 32768 1 gShuf16 .rowmax .T = 891460 ∧ stepH 32768 16 gStream cvNat 1 = 1553714 ∧ step3H 32768 16 gShuf64 .rowmax .T = 7056644 ∧
    stepS4 32768 gStream cvNat 1 = 1032465 ∧ step3S4 32768 gShuf64 .rowmax .T = 11596269 ∧ stepI8H 32768 gStream cvNat 1 = 391426 ∧
    step3I8 32768 1 gShuf64 .rowmax .T (mergePack * 100) = 612484 ∧
    stepH 1048576 1 gStream cvNat 1 = 24605602 ∧ step3H 1048576 1 gShuf64 .rowmax .T = 25735556 ∧ step3H 1048576 1 gStream .rowmax .T = 24617348 ∧
    stepH 1048576 1 gStream cvWorst 2 = 26324046 ∧ step3H 1048576 1 gShuf64 .rowmax .C = 25740676 ∧ stepH 1048576 1 gPage64k cvNat 1 = 28697506 ∧
    stepH 1048576 16 gStream cvNat 1 = 49209394 ∧ step3H 1048576 16 gShuf64 .rowmax .T = 224106244 ∧
    pct (822468 - 775778) 775778 = 60 ∧ pct (25735556 - 24605602) 24605602 = 46 ∧ pct (787524 - 775778) 775778 = 15 ∧
    fixedNs 32768 cvNat 1 rDrainA mergeOps 1 1 128 = 7074 ∧ fixed3 32768 .rowmax .T (mergePack * 100) 1 1 = 18820 := by decide
