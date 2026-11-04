/-
  proof/fleet.lean — machine-checked derivations for DESIGN-4.md (dmonk, fleet partition planner:
  4 cards × 2 dies, no P2P, layer-split-only runtime).

  Core Lean 4 only (no Mathlib, no Batteries, no imports beyond the implicit Init). Every quantity is
  a scaled integer exactly as in proof/fleet.py, so every theorem closes with `decide`, `omega`, `rfl`
  or `simp` (structural steps: `unfold`, `intro`, `constructor`, `induction`, `rw` with core lemmas):
    bytes   : bytes (KiB = 1024, MiB = 2^20, GiB = 2^30; GB = 10^9 decimal, as HW-MAP quotes memory)
    rates   : tenths of GB/s (1 B/ns = 1 GB/s decimal)            1746 = 174.6
    time    : ns, floor  (tn b R = b*10 / R);  usR = µs round-half-up;  ms2 = hundredths of ms, floor
    tokens  : thousandths;  tokens/s : thousandths (tpsCard tok T = tok·10⁹ / (4·T))
    pct     : tenths of a percent, round-half-up;  pctH : hundredths;  x10 : a ratio in tenths, floor
  PROOF-COVERAGE-4.md maps every number in DESIGN-4.md to a theorem here, a fleet.py label, an
  experiment (EMPIRICAL, H-ladder) or an explicit ASSUMPTION.

  Structure: namespace Measured = HW-MAP constants only (each with the row it comes from) plus the
  two DESIGN-2-derived kernel inputs (theorems of proof/moe.lean) and the DESIGN-2 generator means;
  namespace Design = the partition and the cost model as functions (no number that DESIGN-4.md
  concludes); then the proofs, one theorem per ledger row. The unmeasured / assumed quantities are
  explicit arguments of the model: `lam` (host-bounce latency), `pen` (the A-fraction approximation),
  `ort` (runtime overhead), `G` / `cE` (PROBLEM-3 branches), `a` (draft acceptance).

  Build: `lean proof/fleet.lean` (standalone) or `cd proof && lake build` (target `Fleet`).
  No `axiom`, no `sorry`, no `native_decide` anywhere.
-/

namespace Measured
/-- HW-MAP data-movement table: full W8 decode kernel 174.6 GB/s aggregate, flat m = 1..16 (DDR → L0B
    direct path, fp64 20/20). Tenths. -/
def rGemm : Nat := 1746
/-- HW-MAP data-movement table: the same kernel's serial fallback 138.9 GB/s. Tenths. -/
def rGemmSer : Nat := 1389
/-- HW-MAP data-movement table: m ≥ 24 leaves the flat regime: 81 GB/s. Tenths. -/
def rRows24 : Nat := 810
/-- HW-MAP card table: LPDDR streaming per die 173.8 GB/s (read+write roof); pure read ~181. Tenths. -/
def rDdr : Nat := 1738
def rRead : Nat := 1810
/-- HW-MAP card table: host link die 0 = 27.6 / 27.3 GB/s H2D / D2H; die 1 = 13.9 / 19.0 (transits die 0). Tenths. -/
def h2d0 : Nat := 276
def h2d1 : Nat := 139
def d2h0 : Nat := 273
def d2h1 : Nat := 190
/-- HW-MAP card table: die-to-die copy via host 10.7 GB/s r+w (P2P refused by the runtime). Tenths. -/
def rD2D : Nat := 107
/-- HW-MAP data-movement table: MMA issue cost 15 ns per (16,16,128) call. ns. -/
def cMma : Nat := 15
/-- HW-MAP compute table: ~40 f16 lanes/cycle/core × 1.08 GHz = 43.2 G lane-ops/s per core. Tenths. -/
def rVecCore : Nat := 432
/-- HW-MAP data-movement table: ~91 µs launch + queue floor. ns. -/
def tLaunch : Nat := 91000
/-- HW-MAP hierarchy table: 86 GB usable DDR per die (decimal GB). -/
def dieMemGB : Nat := 86
/-- HW-MAP card table: 2 dies per card, 4 cards. -/
def diesPerCard : Nat := 2
def cards : Nat := 4
/-- HW-MAP card table: 141 W per card sustained all-core matrix load; 150 W TDP class; no throttle. -/
def pSustain : Nat := 141
def pTdp : Nat := 150

/-! DESIGN-2 derived kernel inputs (D2). Both are theorems of proof/moe.lean, not measurements:
    T_piece_expert proves tSerial 4096 4096 1 254 = 122 979 ns per (expert, 16 MiB slab) per core in the
    serial regime; T1_pp proves the ping-pong step 784 118 ns, whose per-slab share is (784 118 − 8 000)/8
    rounded half-up; F = 8 µs is DESIGN-2's fixed per-launch cost (its assumption, E14/E15). -/
def tSlabSer : Nat := 122979
def tPpStep : Nat := 784118
def fMoe : Nat := 8000
def tSlabPP : Nat := (tPpStep - fMoe + 4) / 8
/-- DESIGN-2 §7.1 generator means D(t) under Zipf(1.0) / Zipf(1.5) at rows 1 / 4 / 16 (EMPIRICAL:
    reproduced by `moe.py --zipf`; no interpolation — 0 outside the three measured rows). -/
def dZipf10 (rows : Nat) : Nat := if rows = 1 then 8 else if rows = 4 then 25 else if rows = 16 then 68 else 0
def dZipf15 (rows : Nat) : Nat := if rows = 1 then 8 else if rows = 4 then 20 else if rows = 16 then 45 else 0
end Measured

namespace Design
open Measured

/-! ### Units, assumptions (A) and branch endpoints (U) -/
def KiB : Nat := 1024
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB : Nat := 1000000000
def dieMem : Nat := dieMemGB * GB
def dies : Nat := cards * diesPerCard
/-- ASSUMPTION (A, H8): runtime overhead per die after load = 2 GiB; activation / workspace = 64 MiB.
    Every memory theorem takes the overhead as a hypothesis variable `ort`; `oRt` is only its assumed value. -/
def oRt : Nat := 2 * GiB
def ws : Nat := 64 * MiB
/-- ASSUMPTION (A, H3): host-bounce latency per direction; 91 µs primary, bracket 10 / 500 µs. ns. -/
def lamLo : Nat := 10000
def lamMid : Nat := 91000
def lamHi : Nat := 500000
/-- UNMEASURED (PROBLEM-3 E-exp): vector lane-ops per attention score, native exp 4 / polynomial 16. -/
def cNative : Nat := 4
def cPoly : Nat := 16
/-- UNMEASURED (PROBLEM-3 E-gather): KV read rate, stream branch = the kernel rate, gather3x = a third. Tenths. -/
def gStream : Nat := rGemm
def gGather3x : Nat := rGemm / 3
/-- k = 3 draft tokens per verify step (PROBLEM-4's "up to 3"); acceptance α is a theorem variable. -/
def kDraft : Nat := 3
/-- vector lane-ops per die, tenths of G/s: 8 cores × 43.2 -/
def rVecDie : Nat := 8 * rVecCore

/-! ### Helpers (fleet.py conventions) -/
def tn (b R : Nat) : Nat := b * 10 / R
def usR (ns : Nat) : Nat := (ns + 500) / 1000
def msR (ns : Nat) : Nat := (ns + 500000) / 1000000
/-- hundredths of a millisecond, floor (fleet.py `ms2`) -/
def ms2 (ns : Nat) : Nat := ns / 10000
def pct (n d : Nat) : Nat := (2 * n * 1000 + d) / (2 * d)
def pctH (n d : Nat) : Nat := (2 * n * 10000 + d) / (2 * d)
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b
/-- decimal GB in tenths, floor (fleet.py `gb1`) -/
def gb1 (b : Nat) : Nat := b / (GB / 10)
/-- ratio a/b in tenths, floor (fleet.py `t10(a*10//b)`) -/
def x10 (a b : Nat) : Nat := a * 10 / b
def tpsCard (tok T : Nat) : Nat := tok * 1000000000 / (4 * T)
def tpsFleet (tok T : Nat) : Nat := tok * 1000000000 / T
/-- Σ_{p < n} f p -/
def sumPos (f : Nat → Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => sumPos f n + f n
/-- min / max of f over 0..n -/
def minOver (f : Nat → Nat) : Nat → Nat
  | 0 => f 0
  | n + 1 => min (minOver f n) (f (n + 1))
def maxOver (f : Nat → Nat) : Nat → Nat
  | 0 => f 0
  | n + 1 => max (maxOver f n) (f (n + 1))

/-! ### Shapes (`[F0]`): the 2× int8 expansion of a 160..200 GB sub-8-bit source (errata #12) -/
structure Shape where
  nL : Nat
  d : Nat
  Hq : Nat
  Hkv : Nat
  vocab : Nat
  nlaunch : Nat
  moe : Bool
  /-- bytes streamed per token per layer by the dense kernel (dense: the whole layer; MoE: the attention GEMMs) -/
  wStream : Nat
  /-- resident int8 bytes per layer -/
  wRes : Nat
  wEmbed : Nat
  wHead : Nat
  /-- f16 KV bytes per token per layer -/
  kvTok : Nat
  /-- layers on chain position p (0..7) -/
  layers : Nat → Nat
  draftPos : Nat
  slabs : Nat
  slab : Nat

/-- dense layer: QKV d×(d + 2·H_kv·d_h) + O d×d + gate/up/down 3·d·ffn, int8 -/
def denseLayerBytes (d ffn Hkv dh : Nat) : Nat := d * (d + 2 * Hkv * dh) + d * d + 3 * d * ffn
def moeAttnBytes (d Hkv dh : Nat) : Nat := d * (d + 2 * Hkv * dh) + d * d
def moeExpertBytes (E slabs n : Nat) : Nat := E * slabs * n * n

def dense : Shape :=
  { nL := 120, d := 16384, Hq := 128, Hkv := 8, vocab := 128256, nlaunch := 6, moe := false,
    wStream := denseLayerBytes 16384 53248 8 128, wRes := denseLayerBytes 16384 53248 8 128,
    wEmbed := 16384 * 128256, wHead := 16384 * 128256, kvTok := 2 * 8 * 128 * 2,
    layers := fun _ => 15, draftPos := 1, slabs := 3, slab := 4096 * 4096 }
def moe : Shape :=
  { nL := 28, d := 4096, Hq := 32, Hkv := 8, vocab := 128256, nlaunch := 7, moe := true,
    wStream := moeAttnBytes 4096 8 128, wRes := moeAttnBytes 4096 8 128 + moeExpertBytes 256 3 4096,
    wEmbed := 4096 * 128256, wHead := 4096 * 128256, kvTok := 2 * 8 * 128 * 2,
    layers := fun p => if p % 2 = 0 then 4 else 3, draftPos := 7, slabs := 3, slab := 4096 * 4096 }
/-- draft model: 1 GB int8, 24 layers → 121 launches per draft token, 4k sliding-window KV (d_h = 64 class) -/
def draftW : Nat := 1 * GB
def draftLaunch : Nat := 121
def draftKv : Nat := 24 * 4096 * (2 * 8 * 64 * 2)

/-- chain position → die (0 or 1) and card: positions alternate d1, d0, d1, d0, … (§1.1) -/
def die (p : Nat) : Nat := if p % 2 = 0 then 1 else 0
def card (p : Nat) : Nat := p / 2
def h2d (d : Nat) : Nat := if d = 0 then h2d0 else h2d1
def d2h (d : Nat) : Nat := if d = 0 then d2h0 else d2h1

def totalResident (s : Shape) : Nat := s.nL * s.wRes + s.wEmbed + s.wHead
inductive Fam | uniform | zipf10 | zipf15
/-- active experts per step: uniform = min(8·rows, 256) by definition; Zipf only at the generator rows -/
def dOf : Fam → Nat → Nat
  | .uniform, rows => min (8 * rows) 256
  | .zipf10, rows => dZipf10 rows
  | .zipf15, rows => dZipf15 rows
def streamedPerToken (s : Shape) (rows : Nat) (fam : Fam) : Nat :=
  if s.moe then s.nL * (s.wStream + dOf fam rows * s.slabs * s.slab) + s.wHead else s.nL * s.wStream + s.wHead

/-! ### Memory (§1.7): per-die totals as functions of the overhead hypothesis `ort` -/
def dieWeights (s : Shape) (pos : Nat) (draft : Bool) : Nat :=
  s.layers pos * s.wRes + (if pos = 0 then s.wEmbed else 0) + (if pos = 7 then s.wHead else 0)
  + (if draft = true ∧ pos = s.draftPos then draftW + draftKv else 0)
def dieKv (s : Shape) (pos L B : Nat) (i8 : Bool) : Nat :=
  let b := s.layers pos * s.kvTok * L * B
  if i8 then b / 2 else b
def dieTotal (s : Shape) (pos L B : Nat) (i8 : Bool) (ort : Nat) : Nat :=
  dieWeights s pos true + dieKv s pos L B i8 + ws + ort
abbrev feasible (s : Shape) (L B : Nat) (i8 : Bool) (ort : Nat) : Prop :=
  ∀ p, p < 8 → dieTotal s p L B i8 ort ≤ dieMem
def kvPerTok (s : Shape) (pos B : Nat) (i8 : Bool) : Nat := s.layers pos * s.kvTok * B / (if i8 then 2 else 1)
def LmaxPos (s : Shape) (pos B : Nat) (i8 : Bool) (ort : Nat) : Nat :=
  (dieMem - ort - ws - dieWeights s pos true) / kvPerTok s pos B i8
def Lmax (s : Shape) (B : Nat) (i8 : Bool) (ort : Nat) : Nat := minOver (fun p => LmaxPos s p B i8 ort) 7
/-- fleet.py `min_dies` heuristic: a uniform share of the weights plus overhead, draft and 4k of KV -/
abbrev minDiesFits (s : Shape) (n : Nat) : Prop :=
  ceilDiv (totalResident s) n + oRt + ws + draftW + ceilDiv s.nL n * s.kvTok * 4096 ≤ dieMem
/-- fleet room for KV across the 8 dies after weights, overhead and workspace -/
def fleetRoom (s : Shape) (ort : Nat) : Nat := sumPos (fun p => dieMem - ort - ws - dieWeights s p true) 8

/-! ### Exchange (§2): 7 activation hops, logits D2H from position 7, ids H2D to position 0 -/
def act (s : Shape) (rows : Nat) : Nat := rows * s.d * 2
def logits (s : Shape) (rows : Nat) : Nat := rows * s.vocab * 4
def hopBw (b src dst : Nat) : Nat := tn b (d2h src) + tn b (h2d dst)
def xchBw (s : Shape) (rows : Nat) : Nat :=
  sumPos (fun p => hopBw (act s rows) (die p) (die (p + 1))) 7
  + tn (logits s rows) (d2h (die 7)) + tn (rows * 4) (h2d (die 0))
def nLat : Nat := 2 * 7 + 2
def Tx (s : Shape) (rows lam : Nat) : Nat := xchBw s rows + nLat * lam
/-- bytes through card c's die-0 link per token (own hops + die 1's transit) -/
def linkBytesPos (s : Shape) (rows p : Nat) : Nat :=
  (if p > 0 then act s rows else 0) + (if p < 7 then act s rows else 0)
  + (if p = 7 then logits s rows else 0) + (if p = 0 then rows * 4 else 0)
def linkBytesCard (s : Shape) (rows c : Nat) : Nat :=
  sumPos (fun p => if card p = c then linkBytesPos s rows p else 0) 8
/-- a general chain order as an 8-bit mask: bit p = die of position p -/
def bit (m p : Nat) : Nat := m / 2 ^ p % 2
def ones (m : Nat) : Nat := sumPos (fun p => bit m p) 8
def xchBwOrder (s : Shape) (rows m : Nat) : Nat :=
  sumPos (fun p => hopBw (act s rows) (bit m p) (bit m (p + 1))) 7
  + tn (logits s rows) (d2h (bit m 7)) + tn (rows * 4) (h2d (bit m 0))

/-! ### Per-layer time (§3.1) -/
def kvBytes (s : Shape) (L B : Nat) (i8 : Bool) : Nat := s.kvTok * L * B / (if i8 then 2 else 1)
def kvNs (s : Shape) (L B G : Nat) (i8 : Bool) : Nat := tn (kvBytes s L B i8) G
def smNs (s : Shape) (L B t cE : Nat) : Nat := B * t * s.Hq * L * cE * 10 / rVecDie
def frags (s : Shape) (t : Nat) : Nat := ceilDiv (t * (s.Hq / s.Hkv)) 16
def mmaCalls (s : Shape) (L B t : Nat) : Nat := B * 2 * s.Hkv * (L / 16) * frags s t
def mmaNs (s : Shape) (L B t : Nat) : Nat := mmaCalls s L B t * cMma / 8
def attnNs (s : Shape) (L B t G cE : Nat) (i8 : Bool) : Nat :=
  max (kvNs s L B G i8) (max (smNs s L B t cE) (mmaNs s L B t))
inductive Regime | serial | pp
def tSlab : Regime → Nat
  | .serial => tSlabSer
  | .pp => tSlabPP
def expertsNs (s : Shape) (rows : Nat) (fam : Fam) (r : Regime) : Nat :=
  2 * fMoe + s.slabs * dOf fam rows * tSlab r
/-- dense per-layer GEMM time with the A-fraction penalty `pen` (tenths of a percent): the stated
    approximation (ledger row 39) — the measured 174.6 carries 1.5 % of A bytes, the down-projection 3.1 % -/
def gemmDenseNs (s : Shape) (pen : Nat) : Nat := tn s.wStream rGemm * (1000 + pen) / 1000
def gemmNs (s : Shape) (rows : Nat) (fam : Fam) (r : Regime) (pen : Nat) : Nat :=
  if s.moe then tn s.wStream rGemm + expertsNs s rows fam r else gemmDenseNs s pen
def headNs (s : Shape) : Nat := tn s.wHead rGemm
def launchNs (s : Shape) (launch : Bool) : Nat := if launch then (s.nL * s.nlaunch + 2) * tLaunch else 0
def draftTokNs (lam : Nat) (launch : Bool) : Nat :=
  tn draftW rGemm + tn draftKv rGemm + (if launch then draftLaunch * tLaunch else 0)
  + tn (128256 * 4) d2h0 + 2 * lam
def draftNs (lam : Nat) (launch : Bool) (k : Nat) : Nat := k * draftTokNs lam launch

/-- the discrete branch vector: G, c_E, launch serialisation, MoE regime, routing family, KV-int8.
    λ (`lam`) and the A-fraction penalty (`pen`) are separate Nat arguments so that theorems quantify over them. -/
structure Br where
  G : Nat
  cE : Nat
  launch : Bool
  regime : Regime
  fam : Fam
  i8 : Bool
/-- primary branch: stream, native exp, launches serialised, MoE serial, uniform routing, f16 KV -/
def br0 : Br := { G := gStream, cE := cNative, launch := true, regime := .serial, fam := .uniform, i8 := false }
def brG : Br := { br0 with G := gGather3x }
def brPoly : Br := { br0 with cE := cPoly }
def brNoLaunch : Br := { br0 with launch := false }
def brPP : Br := { br0 with regime := .pp }
def brZ10 : Br := { br0 with fam := .zipf10 }
def brZ15 : Br := { br0 with fam := .zipf15 }
def brI8 : Br := { br0 with i8 := true }
def brPess : Br := { br0 with G := gGather3x, cE := cPoly }
def brOptM : Br := { br0 with launch := false, regime := .pp }

/-! ### The step (§3.1): T_step = Σ_layers (GEMM + attention) + head + launches + exchange + draft -/
def wNs (s : Shape) (B t : Nat) (br : Br) (pen : Nat) : Nat := s.nL * gemmNs s (B * t) br.fam br.regime pen + headNs s
def kvTot (s : Shape) (L B : Nat) (br : Br) : Nat := s.nL * kvNs s L B br.G br.i8
def smTot (s : Shape) (L B t : Nat) (br : Br) : Nat := s.nL * smNs s L B t br.cE
def mmaTot (s : Shape) (L B t : Nat) : Nat := s.nL * mmaNs s L B t
def attnTot (s : Shape) (L B t : Nat) (br : Br) : Nat := s.nL * attnNs s L B t br.G br.cE br.i8
def xNs (s : Shape) (B t lam : Nat) : Nat := Tx s (B * t) lam
/-- fleet.py `step`: the draft term is present whenever t > 1, always with k = K_DRAFT = 3 drafts -/
def dNs (t : Nat) (br : Br) (lam : Nat) : Nat := if t > 1 then draftNs lam br.launch kDraft else 0
def stepNs (s : Shape) (L B t : Nat) (br : Br) (lam pen : Nat) : Nat :=
  wNs s B t br pen + attnTot s L B t br + launchNs s br.launch + xNs s B t lam + dNs t br lam
/-- a verify step with k drafts (rows = k + 1, B = 1): the draft term scales with k -/
def stepSpec (s : Shape) (L k : Nat) (br : Br) (lam pen : Nat) : Nat :=
  wNs s 1 (k + 1) br pen + attnTot s L 1 (k + 1) br + launchNs s br.launch + xNs s 1 (k + 1) lam
  + draftNs lam br.launch k
/-- "binding = W": the weight stream is the largest of the additive terms (attention sub-terms are alternatives);
    Bool-valued so that a 24-cell regime map stays one `decide` -/
def bindsW (s : Shape) (L B t : Nat) (br : Br) (lam pen : Nat) : Bool :=
  decide (kvTot s L B br < wNs s B t br pen) && decide (smTot s L B t br < wNs s B t br pen) &&
  decide (mmaTot s L B t < wNs s B t br pen) && decide (launchNs s br.launch < wNs s B t br pen) &&
  decide (xNs s B t lam < wNs s B t br pen) && decide (dNs t br lam < wNs s B t br pen)
def bindsKV (s : Shape) (L B t : Nat) (br : Br) (lam pen : Nat) : Bool :=
  decide (wNs s B t br pen < kvTot s L B br) && decide (smTot s L B t br < kvTot s L B br) &&
  decide (mmaTot s L B t < kvTot s L B br) && decide (launchNs s br.launch < kvTot s L B br) &&
  decide (xNs s B t lam < kvTot s L B br) && decide (dNs t br lam < kvTot s L B br)
/-- tokens per verify step τ(α, k) = Σ_{i ≤ k} α^i, thousandths, with fleet.py's integer recurrence -/
def powM (a : Nat) : Nat → Nat
  | 0 => 1000
  | n + 1 => powM a n * a / 1000
def tau (a : Nat) : Nat → Nat
  | 0 => powM a 0
  | k + 1 => tau a k + powM a (k + 1)

/-! ### Crossovers (§4.2) -/
def kvPerTokB (s : Shape) (B : Nat) (i8 : Bool) : Nat := s.kvTok * B / (if i8 then 2 else 1)
/-- smallest L with KV time ≥ weight time per layer: ⌈T_w · G / (10 · kv_tok · B)⌉ -/
def LstarKv (s : Shape) (G B rows : Nat) (fam : Fam) (r : Regime) (i8 : Bool) : Nat :=
  ceilDiv (gemmNs s rows fam r 0 * G) (kvPerTokB s B i8 * 10)
/-- smallest t with softmax time ≥ KV stream time (L and B cancel) -/
def tStarSm (s : Shape) (G cE : Nat) (i8 : Bool) : Nat :=
  ceilDiv (kvPerTokB s 1 i8 * rVecDie) (G * s.Hq * cE)

/-! ### What-ifs (§5) -/
/-- one host all-reduce of a [rows, d] f32 partial from 8 dies: per card both dies' partials out, both f16
    results in, + 2 latencies -/
def tReduce (lam rows d : Nat) : Nat :=
  tn (rows * d * 4) d2h1 + tn (rows * d * 4) d2h0 + tn (rows * d * 2) h2d1 + tn (rows * d * 2) h2d0 + 2 * lam
def gemmTsNs (s : Shape) (rows : Nat) (fam : Fam) (r : Regime) : Nat :=
  if s.moe then tn s.wStream (8 * rGemm) + 2 * fMoe + s.slabs * dOf fam rows * tSlab r / 8
  else tn s.wStream (8 * rGemm)
def reduceTot (s : Shape) (B t lam : Nat) : Nat := s.nL * 2 * tReduce lam (B * t) s.d
def stepTs (s : Shape) (L B t : Nat) (br : Br) (lam : Nat) : Nat :=
  s.nL * (gemmTsNs s (B * t) br.fam br.regime + attnNs s L B t br.G br.cE br.i8 / 8)
  + tn s.wHead (8 * rGemm) + launchNs s br.launch + reduceTot s B t lam
/-- the same with the reductions over a P2P fabric of rate X (tenths) and latency lamP -/
def redP2p (s : Shape) (rows X lamP : Nat) : Nat := 8 * (rows * s.d * 4) * 10 / X + lamP
def stepTsP2p (s : Shape) (L B t : Nat) (br : Br) (lam X lamP : Nat) : Nat :=
  stepTs s L B t br lam - reduceTot s B t lam + s.nL * 2 * redP2p s (B * t) X lamP
/-- Π = 8: the per-die block = its layers' GEMM + attention + launches, extras, and its two bounce halves -/
def dieBlock (s : Shape) (pos L B t : Nat) (br : Br) (lam pen : Nat) : Nat :=
  s.layers pos * (gemmNs s (B * t) br.fam br.regime pen + attnNs s L B t br.G br.cE br.i8
                  + (if br.launch then s.nlaunch * tLaunch else 0))
  + (if pos = 7 then headNs s + (if br.launch then 2 * tLaunch else 0) else 0)
  + (if pos > 0 then tn (act s (B * t)) (h2d (die pos)) + lam else 0)
  + (if pos < 7 then tn (act s (B * t)) (d2h (die pos)) + lam
     else tn (logits s (B * t)) (d2h (die pos)) + lam)
def maxBlock (s : Shape) (L : Nat) (br : Br) (lam pen : Nat) : Nat := maxOver (fun p => dieBlock s p L 1 1 br lam pen) 7
def sumBlocks (s : Shape) (L : Nat) (br : Br) (lam pen : Nat) : Nat := sumPos (fun p => dieBlock s p L 1 1 br lam pen) 8
/-- §7 rollout: the prefix chain over the first `npos` positions -/
def prefixStep (s : Shape) (npos L : Nat) (br : Br) (lam pen : Nat) : Nat :=
  sumPos (fun p => dieBlock s p L 1 1 br lam pen) npos
/-- one die's KV at 128k moved through the host at rate r -/
def kvMoveNs (s : Shape) (r : Nat) : Nat := tn (s.layers 0 * s.kvTok * 131072) r

end Design

open Measured Design

/-! ## Proofs — one theorem per PROOF-COVERAGE-4.md row -/

/-! ### Rows 1–3: shapes `[F0]` -/
theorem T0_dense_bytes : denseLayerBytes 16384 53248 8 128 = 3187671040 ∧ dense.wEmbed = 2101346304 ∧
    totalResident dense = 386723217408 ∧ gb1 (totalResident dense) = 3867 ∧ gb1 (totalResident dense / 2) = 1933 ∧
    streamedPerToken dense 1 .uniform = 384621871104 ∧ gb1 (streamedPerToken dense 1 .uniform) = 3846 := by decide
theorem T0_moe_bytes : moeAttnBytes 4096 8 128 = 41943040 ∧ moeExpertBytes 256 3 4096 = 12884901888 ∧
    moe.wRes = 12926844928 ∧ moe.wEmbed = 525336576 ∧ totalResident moe = 363002331136 ∧
    gb1 (totalResident moe) = 3630 ∧ gb1 (totalResident moe / 2) = 1815 ∧
    streamedPerToken moe 1 .uniform = 12974030848 ∧ gb1 (streamedPerToken moe 1 .uniform) = 129 := by decide
/-- §1.2 "12.0 GB of expert slabs per layer" is 12 GiB = 12.9 GB (prover-forced unit correction) -/
theorem T0_expert_slabs_units : moeExpertBytes 256 3 4096 = 12 * GiB ∧ gb1 (moeExpertBytes 256 3 4096) = 128 := by decide
theorem T0_kv : dense.kvTok = 4096 ∧ dense.nL * dense.kvTok = 491520 ∧ moe.nL * moe.kvTok = 114688 ∧
    gb1 (dense.nL * dense.kvTok * 2 ^ 20) = 5153 ∧ gb1 (moe.nL * moe.kvTok * 2 ^ 20) = 1202 ∧
    dies * dieMemGB = 688 ∧ draftKv = 201326592 ∧ draftW = 1000000000 ∧
    tSlabPP = 97015 ∧ rVecDie = 3456 ∧ gGather3x = 582 := by decide
/-- §1.3: the new token's K/V per layer is kv_tok = 4 KiB (K and V together), not "8 KiB"; 16 per-core
    streams of L × 256 B make up the 4096 B per token -/
theorem T0_kv_write : dense.kvTok = 4 * KiB ∧ 2 * 8 * 128 * 2 = 16 * 256 ∧ 16 * 2048 * 4 = 128 * KiB := by decide

/-! ### Rows 4–7: per-die feasibility (§1.7, `[F10-mem-*]`) — the 2 GiB overhead is a hypothesis -/
theorem T_mem_feas_dense_4k : feasible dense 4096 1 false oRt ∧
    dieTotal dense 0 4096 1 false oRt = 52382662656 ∧ gb1 (dieTotal dense 0 4096 1 false oRt) = 523 ∧
    gb1 (dieTotal dense 1 4096 1 false oRt) = 514 ∧ gb1 (dieTotal dense 2 4096 1 false oRt) = 502 ∧
    gb1 (dieTotal dense 7 4096 1 false oRt) = 523 ∧ gb1 (dieWeights dense 0 true) = 499 ∧
    gb1 (dieWeights dense 1 true) = 490 ∧ gb1 (dieWeights dense 2 true) = 478 ∧ gb1 (ws + oRt) = 22 ∧
    gb1 (dieKv dense 0 4096 1 false) = 2 := by decide
theorem T_mem_feas_moe_4k : feasible moe 4096 1 false oRt ∧
    gb1 (dieTotal moe 0 4096 1 false oRt) = 545 ∧ gb1 (dieTotal moe 1 4096 1 false oRt) = 410 ∧
    gb1 (dieTotal moe 2 4096 1 false oRt) = 539 ∧ gb1 (dieTotal moe 7 4096 1 false oRt) = 427 ∧
    gb1 (dieWeights moe 0 true) = 522 ∧ gb1 (dieWeights moe 1 true) = 387 ∧ gb1 (dieWeights moe 2 true) = 517 ∧
    gb1 (dieWeights moe 7 true) = 405 ∧ gb1 (draftW + draftKv) = 12 := by decide
theorem T_mem_feas_moe_1M : feasible moe 1048576 1 false oRt ∧
    gb1 (dieTotal moe 0 1048576 1 false oRt) = 716 ∧ gb1 (dieTotal moe 1 1048576 1 false oRt) = 538 ∧
    gb1 (dieTotal moe 2 1048576 1 false oRt) = 711 ∧ gb1 (dieTotal moe 7 1048576 1 false oRt) = 556 ∧
    gb1 (dieKv moe 0 1048576 1 false) = 171 ∧ gb1 (dieKv moe 1 1048576 1 false) = 128 := by decide
/-- dense 1M with f16 KV: every die exceeds 86 GB (114.4–116.5), for any overhead ≥ 0 -/
theorem T_mem_infeas_dense_1M (ort : Nat) : ¬ feasible dense 1048576 1 false ort := by
  intro h
  have h0 := h 0 (by decide)
  have hw : dieWeights dense 0 true + dieKv dense 0 1048576 1 false + ws = 114408030208 ∧
      dieMem = 86000000000 := by decide
  unfold dieTotal at h0
  omega
theorem T_mem_infeas_dense_1M_cells : gb1 (dieTotal dense 0 1048576 1 false oRt) = 1165 ∧
    gb1 (dieTotal dense 2 1048576 1 false oRt) = 1144 ∧ gb1 (dieKv dense 0 1048576 1 false) = 644 := by decide
/-- …and under ANY partition: the fleet's KV room after the int8 weights (282.3 GB) is below the 515.4 GB
    of f16 KV at 2²⁰ tokens (infeasible by 233.0 GB) — a sum argument over any 8-way split -/
theorem sumPos_le (f : Nat → Nat) (c : Nat) : ∀ n, (∀ p, p < n → f p ≤ c) → sumPos f n ≤ n * c := by
  intro n
  induction n with
  | zero => intro _; exact Nat.zero_le _
  | succ n ih =>
    intro h
    have h1 := ih (fun p hp => h p (Nat.lt_succ_of_lt hp))
    have h2 := h n (Nat.lt_succ_self n)
    simp only [sumPos, Nat.succ_mul]
    omega
theorem sumPos_add (f g : Nat → Nat) : ∀ n, sumPos (fun p => f p + g p) n = sumPos f n + sumPos g n := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => simp only [sumPos, ih]; omega
theorem T_mem_infeas_1M_any_partition (w kv : Nat → Nat)
    (hw : sumPos w 8 = totalResident dense) (hkv : sumPos kv 8 = dense.nL * dense.kvTok * 2 ^ 20) :
    ¬ (∀ p, p < 8 → w p + kv p + ws ≤ dieMem) := by
  intro h
  have hs := sumPos_le (fun p => w p + kv p + ws) dieMem 8 h
  have hsplit := sumPos_add (fun p => w p + kv p) (fun _ => ws) 8
  have hsplit2 := sumPos_add w kv 8
  have hc : sumPos (fun _ => ws) 8 = 8 * ws := by decide
  have hn : totalResident dense = 386723217408 ∧ dense.nL * dense.kvTok * 2 ^ 20 = 515396075520 ∧
      ws = 67108864 ∧ dieMem = 86000000000 := by decide
  omega
theorem T_mem_room : fleetRoom dense oRt = 282358715904 ∧ gb1 (fleetRoom dense oRt) = 2823 ∧
    gb1 (dense.nL * dense.kvTok * 2 ^ 20 - fleetRoom dense oRt) = 2330 ∧
    gb1 (dense.nL * 2048 * 2 ^ 20) = 2576 ∧ gb1 (dense.nL * 3072 * 2 ^ 20) = 3865 ∧
    gb1 (dense.nL * 3072 * 2 ^ 20 - fleetRoom dense oRt) = 1041 := by decide
/-- the KV-int8 escape (row 6): 84.3 of 86 GB on positions 0 and 7 at the assumed 2 GiB; it fits iff the
    runtime overhead is ≤ 3 804 224 512 B = 3.80 GB = 3.54 GiB (not "3.85 GiB"); margin 1.66 GB -/
theorem T_mem_feas_kv_int8 (ort : Nat) : feasible dense 1048576 1 true ort ↔ ort ≤ 3804224512 := by
  have hall : ∀ p, p < 8 → dieWeights dense p true + dieKv dense p 1048576 1 true + ws ≤ 82195775488 := by decide
  have h0 : dieWeights dense 0 true + dieKv dense 0 1048576 1 true + ws = 82195775488 := by decide
  have hm : dieMem = 86000000000 := by decide
  constructor
  · intro h
    have := h 0 (by decide)
    unfold dieTotal at this
    omega
  · intro hort p hp
    have := hall p hp
    unfold dieTotal
    omega
theorem T_mem_feas_kv_int8_cells : feasible dense 1048576 1 true oRt ∧
    dieTotal dense 0 1048576 1 true oRt = 84343259136 ∧ gb1 (dieTotal dense 0 1048576 1 true oRt) = 843 ∧
    gb1 (dieTotal dense 1 1048576 1 true oRt) = 834 ∧ gb1 (dieTotal dense 2 1048576 1 true oRt) = 822 ∧
    gb1 (dieTotal dense 7 1048576 1 true oRt) = 843 ∧ gb1 (dieKv dense 0 1048576 1 true) = 322 ∧
    dieMem - dieTotal dense 0 1048576 1 true oRt = 1656740864 ∧
    3804224512 * 100 / GiB = 354 ∧ 3804224512 * 100 / GB = 380 ∧ 2 * GiB + 1656740864 = 3804224512 := by decide
/-- the §9 fallback "embedding table to the host → position 0 drops to 82.2 GB, position 7 stays 84.3" -/
theorem T_mem_embed_to_host : gb1 (dieTotal dense 0 1048576 1 true oRt - dense.wEmbed) = 822 ∧
    gb1 (dieTotal dense 7 1048576 1 true oRt) = 843 ∧ dense.wHead = 2101346304 := by decide

/-! ### Rows 8–9: L_max (`[F1-*-Lmax]`, `[F1-dLmax]`) -/
theorem T_Lmax : Lmax dense 1 false oRt = 551253 ∧ Lmax dense 4 false oRt = 137813 ∧ Lmax dense 16 false oRt = 34453 ∧
    Lmax dense 1 true oRt = 1102506 ∧ Lmax moe 1 false oRt = 1925823 ∧ Lmax moe 4 false oRt = 481455 ∧
    Lmax moe 16 false oRt = 120363 ∧ Lmax dense 8 false oRt = 68906 := by decide
/-- the binding position is 0 (embedding table) for both shapes; the draft die (dense pos 1) is not binding,
    so the draft costs no context (`[F1-dense-draftfree]`) -/
theorem T_Lmax_binding_pos : LmaxPos dense 0 1 false oRt = 551253 ∧ LmaxPos dense 7 1 false oRt = 551253 ∧
    LmaxPos dense 1 1 false oRt = 565901 ∧ LmaxPos dense 2 1 false oRt = 585454 ∧
    (dieMem - oRt - ws - dieWeights dense 1 false) / (15 * 4096) = 585454 ∧
    LmaxPos moe 0 1 false oRt = 1925823 ∧ LmaxPos moe 2 1 false oRt = 1957887 ∧ LmaxPos moe 7 1 false oRt = 3521989 := by decide
theorem T_Lmax_formula : Lmax dense 1 false oRt = (dieMem - oRt - ws - dieWeights dense 0 true) / (15 * 4096) ∧
    dieMem - oRt - ws - dieWeights dense 0 true = 33868995584 := by decide
/-- every GB of overhead beyond 2 GiB costs 16 276 tokens of dense L_max and 61 035 of MoE -/
theorem T_Lmax_dOverhead : Lmax dense 1 false oRt - Lmax dense 1 false (oRt + GB) = 16276 ∧
    Lmax moe 1 false oRt - Lmax moe 1 false (oRt + GB) = 61035 ∧ GB / (15 * 4096) = 16276 ∧ GB / (4 * 4096) = 61035 := by decide
/-- L_max falls monotonically with the overhead (so the H8 risk is one-directional) -/
theorem T_Lmax_monotone (a b : Nat) (h : a ≤ b) : LmaxPos dense 0 1 false b ≤ LmaxPos dense 0 1 false a := by
  unfold LmaxPos
  apply Nat.div_le_div_right
  omega

/-! ### Row 10: minimum dies — 4 dies infeasible for ANY layer assignment; 5 dies feasible -/
/-- any assignment of the 120 dense layers to 4 dies puts ≥ 30 layers (95.6 GB of int8) on one die -/
theorem T_min_dies_dense_4 (n0 n1 n2 n3 : Nat) (h : n0 + n1 + n2 + n3 = 120) :
    ¬ (n0 * dense.wRes ≤ dieMem ∧ n1 * dense.wRes ≤ dieMem ∧ n2 * dense.wRes ≤ dieMem ∧ n3 * dense.wRes ≤ dieMem) := by
  have hw : dense.wRes = 3187671040 ∧ dieMem = 86000000000 := by decide
  rw [hw.1, hw.2]
  omega
theorem T_min_dies_moe_4 (n0 n1 n2 n3 : Nat) (h : n0 + n1 + n2 + n3 = 28) :
    ¬ (n0 * moe.wRes ≤ dieMem ∧ n1 * moe.wRes ≤ dieMem ∧ n2 * moe.wRes ≤ dieMem ∧ n3 * moe.wRes ≤ dieMem) := by
  have hw : moe.wRes = 12926844928 ∧ dieMem = 86000000000 := by decide
  rw [hw.1, hw.2]
  omega
/-- the aggregate form: the int8 residency alone exceeds four dies (386.7 / 363.0 GB > 344 GB) -/
theorem T_min_dies_4_total : 4 * dieMem < totalResident dense ∧ 4 * dieMem < totalResident moe ∧
    30 * dense.wRes = 95630131200 ∧ 7 * moe.wRes = 90487914496 := by decide
/-- 5 dies: 24 dense layers per die (embedding on die 0, lm_head + draft on die 4), L = 4k, B = 1 — fits;
    MoE 6/6/6/5/5 likewise. The fleet.py uniform-share heuristic agrees (`min_dies` = 5). -/
theorem T_min_dies_5_dense :
    24 * dense.wRes + dense.wEmbed + 24 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    24 * dense.wRes + 24 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    24 * dense.wRes + dense.wHead + draftW + draftKv + 24 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    24 * 5 = 120 ∧ gb1 (24 * dense.wRes) = 765 ∧ gb1 (24 * dense.wRes + dense.wEmbed) = 786 ∧
    (dieMem - oRt - ws - (24 * dense.wRes + dense.wEmbed)) / (24 * 4096) = 52693 ∧
    gb1 (dieMem - oRt - ws - (24 * dense.wRes + dense.wEmbed)) = 51 := by decide
theorem T_min_dies_5_moe :
    6 * moe.wRes + moe.wEmbed + 6 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    5 * moe.wRes + moe.wHead + draftW + draftKv + 5 * 4096 * 4096 + ws + oRt ≤ dieMem ∧ 6 * 3 + 5 * 2 = 28 := by decide
theorem T_min_dies_heuristic : ¬ minDiesFits dense 4 ∧ minDiesFits dense 5 ∧ ¬ minDiesFits moe 4 ∧ minDiesFits moe 5 := by decide

/-! ### Rows 11–13: exchange bandwidth sums, order dependence, T_x(λ) (`[F2-*]`) -/
theorem T_bw_hops : hopBw 32768 1 0 = 2911 ∧ hopBw 32768 0 1 = 3557 ∧ hopBw 131072 1 0 = 11646 ∧ hopBw 131072 0 1 = 14230 ∧
    hopBw 8192 1 0 = 727 ∧ hopBw 8192 0 1 = 889 ∧ tn 513024 d2h0 = 18792 ∧ tn 2052096 d2h0 = 75168 ∧
    tn 513024 d2h1 = 27001 ∧ tn 4 h2d1 = 0 ∧ act dense 1 = 32768 ∧ act moe 1 = 8192 ∧ logits dense 1 = 513024 ∧
    tn 32768 h2d1 = 2357 ∧ tn 32768 d2h0 = 1200 ∧ tn 8208384 d2h0 = 300673 := by decide
theorem T_bw_sum : xchBw dense 1 = 41107 ∧ xchBw dense 4 = 164443 ∧ xchBw dense 16 = 657799 ∧
    xchBw moe 1 = 24367 ∧ xchBw moe 4 = 97484 ∧ xchBw moe 16 = 389951 ∧ nLat = 16 := by decide
/-- T7 corrected: the activation-hop sum of ANY chain order with four dies of each kind equals
    4·(h0 + h1 + g0 + g1) − h(first die) − g(last die): it depends on the order only through the first
    and last die types (plus the logits source and the id sink). Proved over all 256 masks. -/
theorem T_order_formula : ∀ m, m < 256 → ones m = 4 →
    xchBwOrder dense 1 m + tn 32768 (h2d (bit m 0)) + tn 32768 (d2h (bit m 7)) =
    4 * (tn 32768 h2d0 + tn 32768 h2d1 + tn 32768 d2h0 + tn 32768 d2h1)
    + tn 513024 (d2h (bit m 7)) + tn 4 (h2d (bit m 0)) := by decide +kernel
/-- the chosen order (d1 first, d0 last) is the minimum: 41 107 ns; the four (first, last) classes are
    41 107 / 42 277 / 48 792 / 49 962 ns — optimal by 1.2 µs over a d0-first order and 7.7–8.9 µs over a
    d1-last order (the text's "otherwise free" is a 1.2 µs effect) -/
theorem T_order_optimal : ∀ m, m < 256 → ones m = 4 → 41107 ≤ xchBwOrder dense 1 m := by decide +kernel
theorem T_order_d1_d0 : ∀ m, m < 256 → ones m = 4 → bit m 0 = 1 → bit m 7 = 0 → xchBwOrder dense 1 m = 41107 := by
  decide +kernel
theorem T_order_d0_d0 : ∀ m, m < 256 → ones m = 4 → bit m 0 = 0 → bit m 7 = 0 → xchBwOrder dense 1 m = 42277 := by
  decide +kernel
theorem T_order_d1_d1 : ∀ m, m < 256 → ones m = 4 → bit m 0 = 1 → bit m 7 = 1 → xchBwOrder dense 1 m = 48792 := by
  decide +kernel
theorem T_order_d0_d1 : ∀ m, m < 256 → ones m = 4 → bit m 0 = 0 → bit m 7 = 1 → xchBwOrder dense 1 m = 49962 := by
  decide +kernel
/-- mask 85 = 0b01010101 is the chosen order (bit p = die of position p): d1, d0, d1, d0, … -/
theorem T_order_chosen : xchBwOrder dense 1 85 = xchBw dense 1 ∧ ones 85 = 4 ∧ bit 85 0 = 1 ∧ bit 85 7 = 0 ∧
    (∀ p, p < 8 → bit 85 p = die p) ∧ 42277 - 41107 = 1170 ∧ 48792 - 41107 = 7685 ∧ 49962 - 41107 = 8855 := by decide
theorem T_Tx_cells : Tx dense 1 lamLo = 201107 ∧ Tx dense 1 lamMid = 1497107 ∧ Tx dense 1 lamHi = 8041107 ∧
    Tx dense 4 lamLo = 324443 ∧ Tx dense 4 lamMid = 1620443 ∧ Tx dense 4 lamHi = 8164443 ∧
    Tx moe 1 lamLo = 184367 ∧ Tx moe 1 lamMid = 1480367 ∧ Tx moe 1 lamHi = 8024367 ∧
    Tx moe 4 lamLo = 257484 ∧ Tx moe 4 lamMid = 1553484 ∧ Tx moe 4 lamHi = 8097484 ∧
    usR (Tx dense 1 lamMid) = 1497 ∧ usR (Tx moe 1 lamMid) = 1480 := by decide
/-- T_x over the whole λ bracket, universally quantified -/
theorem T_Tx_bracket (lam : Nat) (h1 : lamLo ≤ lam) (h2 : lam ≤ lamHi) :
    201107 ≤ Tx dense 1 lam ∧ Tx dense 1 lam ≤ 8041107 ∧ 184367 ≤ Tx moe 1 lam ∧ Tx moe 1 lam ≤ 8024367 := by
  have hb : xchBw dense 1 = 41107 ∧ xchBw moe 1 = 24367 ∧ nLat = 16 ∧ lamLo = 10000 ∧ lamHi = 500000 := by decide
  unfold Tx
  rw [hb.1, hb.2.1, hb.2.2.1]
  omega

/-! ### Rows 15–16: trunk bytes per card, utilisation, queueing bound (`[F2-dense-rows1]`, `[F8-H3]`) -/
theorem T_trunk_bytes : linkBytesCard dense 1 0 = 98308 ∧ linkBytesCard dense 1 1 = 131072 ∧
    linkBytesCard dense 1 2 = 131072 ∧ linkBytesCard dense 1 3 = 611328 ∧
    linkBytesCard moe 1 0 = 24580 ∧ linkBytesCard moe 1 3 = 537600 ∧
    98308 / KiB = 96 ∧ 611328 / KiB = 597 ∧ 98308 * 10 / KiB % 10 = 0 := by decide
/-- trunk utilisation at Π = 1 is below 0.02 % (dense 0.001 %, MoE 0.015 %); the per-token budget is
    27.6 GB/s × T_step = 65.2 GB (dense) / 3.69 GB (MoE) -/
theorem T_trunk_util : tn 611328 h2d0 = 22149 ∧ tn 537600 h2d0 = 19478 ∧
    pctH 22149 2362319269 = 0 ∧ pctH 19478 133847319 = 1 ∧ 10000 * 19478 < 2 * 133847319 ∧
    10000 * 22149 < 2 * 2362319269 ∧ 276 * 2362319269 / 10000000000 = 65 ∧ 276 * 133847319 / 1000000000 = 36 := by decide
theorem T_queue : tn (64 * KiB) h2d1 = 4714 ∧ usR (tn (64 * KiB) h2d1) = 5 ∧ tn MiB h2d1 = 75437 ∧
    usR (tn MiB h2d1) = 75 ∧ tn (16 * MiB) h2d1 = 1206993 ∧ usR (tn (16 * MiB) h2d1) = 1207 := by decide

/-! ### Row 17: per-layer times (`[F3-*-layer]`) -/
theorem T_layer : gemmNs dense 1 .uniform .serial 0 = 18256993 ∧ tn moe.wStream rGemm = 240223 ∧
    expertsNs moe 1 .uniform .serial = 2967496 ∧ expertsNs moe 1 .uniform .pp = 2344360 ∧
    gemmNs moe 1 .uniform .serial 0 = 3207719 ∧ gemmNs moe 1 .uniform .pp 0 = 2584583 ∧
    headNs dense = 12035202 ∧ headNs moe = 3008800 ∧ dense.nlaunch * tLaunch = 546000 ∧ moe.nlaunch * tLaunch = 637000 ∧
    launchNs dense true = 65702000 ∧ launchNs moe true = 18018000 ∧ ms2 (launchNs dense true) = 6570 ∧
    ms2 (launchNs moe true) = 1801 ∧ dense.nL * 6 + 2 = 722 ∧ moe.nL * 7 + 2 = 198 := by decide
/-- the W term (all weight streams) = Σ layers + lm_head: 2 202 874 362 ns dense, 92 824 932 MoE -/
theorem T_W : wNs dense 1 1 br0 0 = 2202874362 ∧ wNs moe 1 1 br0 0 = 92824932 ∧
    120 * tn dense.wStream rGemm + headNs dense = 2202874362 ∧ tn (streamedPerToken dense 1 .uniform) rGemm = 2202874404 ∧
    ms2 2202874362 = 220287 ∧ ms2 92824932 = 9282 := by decide

/-! ### Row 18: attention per layer (`[F3-*-attn]`) — stream / gather3x, native / poly, MMA -/
theorem T_attn_dense : kvNs dense 4096 1 gStream false = 96089 ∧ kvNs dense 4096 1 gGather3x false = 288268 ∧
    smNs dense 4096 1 1 cNative = 6068 ∧ smNs dense 4096 1 1 cPoly = 24272 ∧ mmaNs dense 4096 1 1 = 7680 ∧
    kvNs dense 32768 1 gStream false = 768715 ∧ kvNs dense 32768 1 gGather3x false = 2306146 ∧
    smNs dense 32768 1 1 cNative = 48545 ∧ smNs dense 32768 1 1 cPoly = 194180 ∧ mmaNs dense 32768 1 1 = 61440 ∧
    kvNs dense 131072 1 gStream false = 3074862 ∧ kvNs dense 131072 1 gGather3x false = 9224586 ∧
    smNs dense 131072 1 1 cNative = 194180 ∧ smNs dense 131072 1 1 cPoly = 776722 ∧ mmaNs dense 131072 1 1 = 245760 ∧
    kvNs dense 1048576 1 gStream false = 24598896 ∧ kvNs dense 1048576 1 gGather3x false = 73796688 ∧
    smNs dense 1048576 1 1 cNative = 1553445 ∧ smNs dense 1048576 1 1 cPoly = 6213783 ∧ mmaNs dense 1048576 1 1 = 1966080 := by decide
theorem T_attn_moe : kvNs moe 4096 1 gStream false = 96089 ∧ smNs moe 4096 1 1 cNative = 1517 ∧ smNs moe 4096 1 1 cPoly = 6068 ∧
    kvNs moe 32768 1 gStream false = 768715 ∧ kvNs moe 32768 1 gGather3x false = 2306146 ∧
    smNs moe 32768 1 1 cNative = 12136 ∧ smNs moe 32768 1 1 cPoly = 48545 ∧ mmaNs moe 32768 1 1 = 61440 ∧
    kvNs moe 131072 1 gStream false = 3074862 ∧ smNs moe 131072 1 1 cNative = 48545 ∧ smNs moe 131072 1 1 cPoly = 194180 ∧
    kvNs moe 1048576 1 gStream false = 24598896 ∧ kvNs moe 1048576 1 gGather3x false = 73796688 ∧
    smNs moe 1048576 1 1 cNative = 388361 ∧ smNs moe 1048576 1 1 cPoly = 1553445 ∧ mmaNs moe 1048576 1 1 = 1966080 := by decide
/-- "softmax and MMA are 6–8 % of the KV stream at t = 1": 6.3 % / 8.0 % dense; KV/T_gemm = 4.2 % dense, 24.0 % MoE at 32k -/
theorem T_attn_shares : pct 48545 768715 = 63 ∧ pct 61440 768715 = 80 ∧ pct 768715 18256993 = 42 ∧ pct 768715 3207719 = 240 ∧
    pct 12136 768715 = 16 := by decide
/-- the KV term over the whole G bracket (582 ≤ G ≤ 1746), universally quantified: monotone between the endpoints -/
theorem T_attn_G_bracket (G : Nat) (h1 : gGather3x ≤ G) (h2 : G ≤ gStream) :
    768715 ≤ kvNs dense 32768 1 G false ∧ kvNs dense 32768 1 G false ≤ 2306146 := by
  have hb : kvBytes dense 32768 1 false * 10 = 1342177280 ∧ gGather3x = 582 ∧ gStream = 1746 := by decide
  unfold kvNs tn
  rw [hb.1]
  rw [hb.2.1] at h1
  rw [hb.2.2] at h2
  constructor
  · have := Nat.div_le_div_left (a := 1342177280) h2 (by omega)
    have e : 1342177280 / 1746 = 768715 := by decide
    omega
  · have := Nat.div_le_div_left (a := 1342177280) h1 (by omega)
    have e : 1342177280 / 582 = 2306146 := by decide
    omega
/-- the softmax term over the c_E bracket (4 ≤ c_E ≤ 16) is linear in c_E: both endpoints -/
theorem T_attn_cE_bracket (cE : Nat) (h1 : cNative ≤ cE) (h2 : cE ≤ cPoly) :
    48545 ≤ smNs dense 32768 1 1 cE ∧ smNs dense 32768 1 1 cE ≤ 194180 := by
  have hc : cNative = 4 ∧ cPoly = 16 ∧ rVecDie = 3456 := by decide
  unfold smNs
  rw [hc.2.2]
  simp only [dense, Nat.one_mul, Nat.mul_one]
  constructor
  · rw [Nat.le_div_iff_mul_le (by decide)]; omega
  · rw [Nat.div_le_iff_le_mul_add_pred (by decide)]; omega

/-! ### Row 19: the §3.2 table (`[F3]`) — step, components (hundredths of ms), tokens/s/card (thousandths) -/
theorem T_step_dense_4k :
    stepNs dense 4096 1 1 br0 lamMid 0 = 2281604149 ∧ ms2 (stepNs dense 4096 1 1 br0 lamMid 0) = 228160 ∧
    ms2 (kvTot dense 4096 1 br0) = 1153 ∧ ms2 (xNs dense 1 1 lamMid) = 149 ∧ tpsCard 1000 (stepNs dense 4096 1 1 br0 lamMid 0) = 109 ∧
    ms2 (stepNs dense 4096 1 4 br0 lamMid 0) = 233600 ∧ ms2 (xNs dense 1 4 lamMid) = 162 ∧ ms2 (dNs 4 br0 lamMid) = 5427 ∧
    tpsCard (tau 700 3) (stepNs dense 4096 1 4 br0 lamMid 0) = 271 ∧
    ms2 (stepNs dense 4096 16 1 br0 lamMid 0) = 245518 ∧ ms2 (kvTot dense 4096 16 br0) = 18449 ∧ ms2 (xNs dense 16 1 lamMid) = 211 ∧
    tpsCard 16000 (stepNs dense 4096 16 1 br0 lamMid 0) = 1629 := by decide
theorem T_step_dense_32k :
    stepNs dense 32768 1 1 br0 lamMid 0 = 2362319269 ∧ ms2 (stepNs dense 32768 1 1 br0 lamMid 0) = 236231 ∧
    ms2 (kvTot dense 32768 1 br0) = 9224 ∧ tpsCard 1000 (stepNs dense 32768 1 1 br0 lamMid 0) = 105 ∧
    stepNs dense 32768 1 4 br0 lamMid 0 = 2416719328 ∧ ms2 (stepNs dense 32768 1 4 br0 lamMid 0) = 241671 ∧
    tpsCard (tau 700 3) (stepNs dense 32768 1 4 br0 lamMid 0) = 262 ∧
    stepNs dense 32768 16 1 br0 lamMid 0 = 3746623921 ∧ ms2 (stepNs dense 32768 16 1 br0 lamMid 0) = 374662 ∧
    ms2 (kvTot dense 32768 16 br0) = 147593 ∧ tpsCard 16000 (stepNs dense 32768 16 1 br0 lamMid 0) = 1067 := by decide
theorem T_step_dense_128k :
    ms2 (stepNs dense 131072 1 1 br0 lamMid 0) = 263905 ∧ ms2 (kvTot dense 131072 1 br0) = 36898 ∧
    tpsCard 1000 (stepNs dense 131072 1 1 br0 lamMid 0) = 94 ∧
    ms2 (stepNs dense 131072 1 4 br0 lamMid 0) = 269345 ∧ tpsCard (tau 700 3) (stepNs dense 131072 1 4 br0 lamMid 0) = 235 ∧
    ms2 (stepNs dense 131072 16 1 br0 lamMid 0) = 817442 ∧ ms2 (kvTot dense 131072 16 br0) = 590373 ∧
    ¬ feasible dense 131072 16 false oRt := by decide
theorem T_step_dense_1M :
    ms2 (stepNs dense 1048576 1 1 br0 lamMid 0) = 522194 ∧ ms2 (kvTot dense 1048576 1 br0) = 295186 ∧
    ¬ feasible dense 1048576 1 false oRt ∧
    stepNs dense 1048576 1 1 brI8 lamMid 0 = 3746007229 ∧ ms2 (stepNs dense 1048576 1 1 brI8 lamMid 0) = 374600 ∧
    ms2 (kvTot dense 1048576 1 brI8) = 147593 ∧ tpsCard 1000 (stepNs dense 1048576 1 1 brI8 lamMid 0) = 66 ∧
    ms2 (stepNs dense 1048576 1 4 br0 lamMid 0) = 527634 ∧
    ms2 (stepNs dense 1048576 1 4 brI8 lamMid 0) = 380040 ∧ tpsCard (tau 700 3) (stepNs dense 1048576 1 4 brI8 lamMid 0) = 166 ∧
    ms2 (stepNs dense 1048576 16 1 br0 lamMid 0) = 4950057 ∧ ms2 (kvTot dense 1048576 16 br0) = 4722988 ∧
    ¬ feasible dense 1048576 16 false oRt ∧ feasible dense 1048576 1 true oRt := by decide
theorem T_step_moe_4k :
    stepNs moe 4096 1 1 br0 lamMid 0 = 115013791 ∧ ms2 (stepNs moe 4096 1 1 br0 lamMid 0) = 11501 ∧
    ms2 (kvTot moe 4096 1 br0) = 269 ∧ ms2 (xNs moe 1 1 lamMid) = 148 ∧ tpsCard 1000 (stepNs moe 4096 1 1 br0 lamMid 0) = 2173 ∧
    ms2 (stepNs moe 4096 1 4 br0 lamMid 0) = 41728 ∧ ms2 (wNs moe 1 4 br0 0) = 34075 ∧ ms2 (xNs moe 1 4 lamMid) = 155 ∧
    tpsCard (tau 700 3) (stepNs moe 4096 1 4 br0 lamMid 0) = 1517 ∧
    ms2 (stepNs moe 4096 16 1 br0 lamMid 0) = 139536 ∧ ms2 (wNs moe 16 1 br0 0) = 133245 ∧ ms2 (kvTot moe 4096 16 br0) = 4304 ∧
    ms2 (xNs moe 16 1 lamMid) = 184 ∧ tpsCard 16000 (stepNs moe 4096 16 1 br0 lamMid 0) = 2866 := by decide
theorem T_step_moe_32k :
    stepNs moe 32768 1 1 br0 lamMid 0 = 133847319 ∧ ms2 (stepNs moe 32768 1 1 br0 lamMid 0) = 13384 ∧
    ms2 (kvTot moe 32768 1 br0) = 2152 ∧ tpsCard 1000 (stepNs moe 32768 1 1 br0 lamMid 0) = 1867 ∧
    stepNs moe 32768 1 4 br0 lamMid 0 = 436122823 ∧ ms2 (stepNs moe 32768 1 4 br0 lamMid 0) = 43612 ∧
    tpsCard (tau 700 3) (stepNs moe 32768 1 4 br0 lamMid 0) = 1451 ∧
    stepNs moe 32768 16 1 br0 lamMid 0 = 1696701747 ∧ ms2 (stepNs moe 32768 16 1 br0 lamMid 0) = 169670 ∧
    ms2 (kvTot moe 32768 16 br0) = 34438 ∧ tpsCard 16000 (stepNs moe 32768 16 1 br0 lamMid 0) = 2357 := by decide
theorem T_step_moe_128k :
    ms2 (stepNs moe 131072 1 1 br0 lamMid 0) = 19841 ∧ ms2 (kvTot moe 131072 1 br0) = 8609 ∧
    tpsCard 1000 (stepNs moe 131072 1 1 br0 lamMid 0) = 1259 ∧
    ms2 (stepNs moe 131072 1 4 br0 lamMid 0) = 50069 ∧ tpsCard (tau 700 3) (stepNs moe 131072 1 4 br0 lamMid 0) = 1264 ∧
    ms2 (stepNs moe 131072 16 1 br0 lamMid 0) = 272985 ∧ ms2 (kvTot moe 131072 16 br0) = 137753 ∧
    ¬ feasible moe 131072 16 false oRt := by decide
theorem T_step_moe_1M :
    stepNs moe 1048576 1 1 br0 lamMid 0 = 801092387 ∧ ms2 (stepNs moe 1048576 1 1 br0 lamMid 0) = 80109 ∧
    ms2 (kvTot moe 1048576 1 br0) = 68876 ∧ tpsCard 1000 (stepNs moe 1048576 1 1 br0 lamMid 0) = 312 ∧
    ms2 (stepNs moe 1048576 1 4 br0 lamMid 0) = 110336 ∧ tpsCard (tau 700 3) (stepNs moe 1048576 1 4 br0 lamMid 0) = 573 ∧
    ms2 (stepNs moe 1048576 16 1 br0 lamMid 0) = 1237262 ∧ ms2 (kvTot moe 1048576 16 br0) = 1102030 ∧
    ¬ feasible moe 1048576 16 false oRt ∧ feasible moe 1048576 1 false oRt := by decide
/-- the draft term (row 31) as it enters the table: 54.27 ms serialised, 21.24 pipelined -/
theorem T_draft : tn draftW rGemm = 5727376 ∧ tn draftKv rGemm = 1153073 ∧ draftLaunch * tLaunch = 11011000 ∧
    tn (128256 * 4) d2h0 = 18792 ∧ draftTokNs lamMid true = 18092241 ∧ msR (draftTokNs lamMid true) = 18 ∧
    usR (draftTokNs lamMid true) = 18092 ∧ draftNs lamMid true 3 = 54276723 ∧ ms2 (draftNs lamMid true 3) = 5427 ∧
    draftNs lamMid false 3 = 21243723 ∧ ms2 (draftNs lamMid false 3) = 2124 ∧ usR (draftTokNs lamMid false) = 7081 ∧
    pct 11011000 18092241 = 609 ∧ usR (tn (GB / 2) rGemm) = 2864 ∧ 60 * tLaunch = 5460000 ∧
    usR (draftTokNs 0 false) = 6899 ∧ 24 * 2048 = 49152 ∧ pct 49152 491520 = 100 ∧ gb1 (49152 * 2 ^ 20) = 515 := by decide

/-! ### Row 20: branches at 32k (`[F3b]`) -/
theorem T_branches_dense :
    stepNs dense 32768 1 1 brG lamMid 0 = 2546810989 ∧ tpsCard 1000 (stepNs dense 32768 1 1 brG lamMid 0) = 98 ∧
    stepNs dense 32768 1 1 brPoly lamMid 0 = 2362319269 ∧
    stepNs dense 32768 1 1 br0 lamLo 0 = 2361023269 ∧ tpsCard 1000 (stepNs dense 32768 1 1 br0 lamLo 0) = 105 ∧
    stepNs dense 32768 1 1 br0 lamHi 0 = 2368863269 ∧ tpsCard 1000 (stepNs dense 32768 1 1 br0 lamHi 0) = 105 ∧
    stepNs dense 32768 1 1 brNoLaunch lamMid 0 = 2296617269 ∧ tpsCard 1000 (stepNs dense 32768 1 1 brNoLaunch lamMid 0) = 108 ∧
    stepNs dense 32768 1 1 brPess lamHi 0 = 2553354989 ∧ tpsCard 1000 (stepNs dense 32768 1 1 brPess lamHi 0) = 97 ∧
    stepNs dense 32768 1 1 brNoLaunch lamLo 0 = 2295321269 ∧ tpsCard 1000 (stepNs dense 32768 1 1 brNoLaunch lamLo 0) = 108 ∧
    pct (105 - 97) 105 = 76 ∧ pct (108 - 105) 105 = 29 := by decide
theorem T_branches_moe :
    stepNs moe 32768 1 1 brG lamMid 0 = 176895387 ∧ tpsCard 1000 (stepNs moe 32768 1 1 brG lamMid 0) = 1413 ∧
    stepNs moe 32768 1 1 brPoly lamMid 0 = 133847319 ∧
    stepNs moe 32768 1 1 br0 lamLo 0 = 132551319 ∧ tpsCard 1000 (stepNs moe 32768 1 1 br0 lamLo 0) = 1886 ∧
    stepNs moe 32768 1 1 br0 lamHi 0 = 140391319 ∧ tpsCard 1000 (stepNs moe 32768 1 1 br0 lamHi 0) = 1780 ∧
    stepNs moe 32768 1 1 brNoLaunch lamMid 0 = 115829319 ∧ tpsCard 1000 (stepNs moe 32768 1 1 brNoLaunch lamMid 0) = 2158 ∧
    stepNs moe 32768 1 1 brPP lamMid 0 = 116399511 ∧ tpsCard 1000 (stepNs moe 32768 1 1 brPP lamMid 0) = 2147 ∧
    stepNs moe 32768 1 1 brZ15 lamMid 0 = 133847319 ∧
    stepNs moe 32768 1 1 brPess lamHi 0 = 183439387 ∧ tpsCard 1000 (stepNs moe 32768 1 1 brPess lamHi 0) = 1362 ∧
    stepNs moe 32768 1 1 brOptM lamLo 0 = 97085511 ∧ tpsCard 1000 (stepNs moe 32768 1 1 brOptM lamLo 0) = 2575 ∧
    pct (1867 - 1362) 1867 = 270 ∧ pct (2575 - 1867) 1867 = 379 ∧ pct (133847319 - 116399511) 133847319 = 130 := by decide
/-- the whole λ bracket at once, universally quantified: dense stays at 0.105 and MoE within 1.780–1.886 -/
theorem T_step_lambda_form (lam : Nat) :
    stepNs dense 32768 1 1 br0 lam 0 = 2360822162 + 41107 + 16 * lam ∧
    stepNs moe 32768 1 1 br0 lam 0 = 132366952 + 24367 + 16 * lam := by
  have hd : wNs dense 1 1 br0 0 + attnTot dense 32768 1 1 br0 + launchNs dense br0.launch = 2360822162 ∧
      wNs moe 1 1 br0 0 + attnTot moe 32768 1 1 br0 + launchNs moe br0.launch = 132366952 ∧
      xchBw dense (1 * 1) = 41107 ∧ xchBw moe (1 * 1) = 24367 := by decide
  have h0 : ∀ lam, dNs 1 br0 lam = 0 := fun _ => rfl
  unfold stepNs xNs Tx nLat
  rw [h0, hd.2.2.1, hd.2.2.2]
  omega
theorem T_step_lambda_bracket (lam : Nat) (h1 : lamLo ≤ lam) (h2 : lam ≤ lamHi) :
    tpsCard 1000 (stepNs dense 32768 1 1 br0 lam 0) = 105 ∧
    1780 ≤ tpsCard 1000 (stepNs moe 32768 1 1 br0 lam 0) ∧ tpsCard 1000 (stepNs moe 32768 1 1 br0 lam 0) ≤ 1886 := by
  have hl : lamLo = 10000 ∧ lamHi = 500000 := by decide
  rw [(T_step_lambda_form lam).1, (T_step_lambda_form lam).2]
  unfold tpsCard
  refine ⟨?_, ?_, ?_⟩
  · have a : 105 ≤ 1000 * 1000000000 / (4 * (2360822162 + 41107 + 16 * lam)) := by
      rw [Nat.le_div_iff_mul_le (by omega)]; omega
    have b : 1000 * 1000000000 / (4 * (2360822162 + 41107 + 16 * lam)) < 106 := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega
  · rw [Nat.le_div_iff_mul_le (by omega)]; omega
  · have b : 1000 * 1000000000 / (4 * (132366952 + 24367 + 16 * lam)) < 1887 := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega

/-! ### Row 21: MoE B = 16 by routing family (`[F3c]`) -/
theorem T_moe_families :
    stepNs moe 32768 16 1 br0 lamMid 0 = 1696701747 ∧ wNs moe 16 1 br0 0 = 1332453252 ∧
    tpsCard 16000 (stepNs moe 32768 16 1 br0 lamMid 0) = 2357 ∧ dOf .uniform 16 = 128 ∧
    stepNs moe 32768 16 1 brZ10 lamMid 0 = 1076887587 ∧ ms2 (wNs moe 16 1 brZ10 0) = 71263 ∧
    tpsCard 16000 (stepNs moe 32768 16 1 brZ10 lamMid 0) = 3714 ∧ dOf .zipf10 16 = 68 ∧
    stepNs moe 32768 16 1 brZ15 lamMid 0 = 839292159 ∧ ms2 (wNs moe 16 1 brZ15 0) = 47504 ∧
    tpsCard 16000 (stepNs moe 32768 16 1 brZ15 lamMid 0) = 4765 ∧ dOf .zipf15 16 = 45 ∧
    ms2 (stepNs moe 1048576 16 1 br0 lamMid 0) = 1237262 ∧ ms2 (kvTot moe 1048576 16 br0) = 1102030 ∧
    ¬ feasible moe 1048576 16 false oRt ∧ ms2 (stepNs moe 1048576 16 1 brZ15 lamMid 0) = 1151521 := by decide

/-! ### Row 22: KV-bandwidth crossover L* (`[F4-*-Lkv-*]`) -/
theorem T_Lstar_kv : LstarKv dense gStream 1 1 .uniform .serial false = 778240 ∧ LstarKv dense gStream 4 1 .uniform .serial false = 194560 ∧
    LstarKv dense gStream 16 1 .uniform .serial false = 48640 ∧ LstarKv dense gStream 1 1 .uniform .serial true = 1556480 ∧
    LstarKv dense gGather3x 1 1 .uniform .serial false = 259414 ∧ LstarKv dense gGather3x 4 1 .uniform .serial false = 64854 ∧
    LstarKv dense gGather3x 16 1 .uniform .serial false = 16214 ∧ LstarKv dense gGather3x 1 1 .uniform .serial true = 518827 ∧
    LstarKv moe gStream 1 1 .uniform .serial false = 136736 ∧ LstarKv moe gStream 4 1 .uniform .serial false = 34184 ∧
    LstarKv moe gStream 16 1 .uniform .serial false = 8546 ∧ LstarKv moe gStream 1 1 .uniform .pp false = 110173 ∧
    LstarKv moe gGather3x 1 1 .uniform .serial false = 45579 ∧ LstarKv moe gGather3x 4 1 .uniform .serial false = 11395 ∧
    LstarKv moe gGather3x 16 1 .uniform .serial false = 2849 ∧ LstarKv moe gGather3x 1 1 .uniform .pp false = 36725 ∧
    778240 * 4096 = dense.wStream ∧ 551253 < 778240 ∧ 1048576 < 1556480 ∧ 259414 < 551253 ∧
    131072 < 136736 ∧ pct (136736 - 131072) 136736 = 41 := by decide
/-- the crossover as an iff on the exact per-layer model (B = 1, stream): KV time ≥ GEMM time ⟺ L ≥ 778 240 -/
theorem T_Lstar_iff (L : Nat) : gemmNs dense 1 .uniform .serial 0 ≤ kvNs dense L 1 gStream false ↔ 778240 ≤ L := by
  have hg : gemmNs dense 1 .uniform .serial 0 = 18256993 := by decide
  rw [hg]
  unfold kvNs tn kvBytes gStream rGemm
  simp only [dense, Nat.mul_one, Bool.false_eq_true, ↓reduceIte, Nat.div_one]
  rw [Nat.le_div_iff_mul_le (by decide)]
  omega
theorem T_Lstar_iff_moe (L : Nat) : gemmNs moe 1 .uniform .serial 0 ≤ kvNs moe L 1 gStream false ↔ 136736 ≤ L := by
  have hg : gemmNs moe 1 .uniform .serial 0 = 3207719 := by decide
  rw [hg]
  unfold kvNs tn kvBytes gStream rGemm
  simp only [moe, Nat.mul_one, Bool.false_eq_true, ↓reduceIte, Nat.div_one]
  rw [Nat.le_div_iff_mul_le (by decide)]
  omega

/-! ### Row 23: softmax crossover t* (`[F4-*-tsm-*]`), L-independent -/
theorem T_tstar : tStarSm dense gStream cNative false = 16 ∧ tStarSm dense gGather3x cNative false = 48 ∧
    tStarSm dense gStream cPoly false = 4 ∧ tStarSm dense gGather3x cPoly false = 12 ∧
    tStarSm dense gStream cNative true = 8 ∧ tStarSm dense gStream cPoly true = 2 ∧
    tStarSm moe gStream cNative false = 64 ∧ tStarSm moe gGather3x cNative false = 191 ∧
    tStarSm moe gStream cPoly false = 16 ∧ tStarSm moe gGather3x cPoly false = 48 := by decide
/-- the exact-rate crossover: t·H_q·c_E·G ≥ kv_tok·R_vec ⟺ t ≥ t*, for every t (dense, stream, native) -/
theorem T_tstar_iff (t : Nat) : 4096 * 3456 ≤ t * 128 * 4 * 1746 ↔ 16 ≤ t := by omega
/-- …and in the floored model at L = 32k (both sides of the threshold): t = 16 binds, t = 15 does not;
    on the poly branch t = 4 binds (776 722 vs 768 715: +1.0 %), t = 3 does not -/
theorem T_tstar_model : kvNs dense 32768 1 gStream false ≤ smNs dense 32768 1 16 cNative ∧
    smNs dense 32768 1 15 cNative < kvNs dense 32768 1 gStream false ∧
    kvNs dense 32768 1 gStream false ≤ smNs dense 32768 1 4 cPoly ∧ smNs dense 32768 1 3 cPoly < kvNs dense 32768 1 gStream false ∧
    smNs dense 32768 1 4 cPoly = 776722 ∧ pct (776722 - 768715) 768715 = 10 := by decide

/-! ### Row 24: the matrix-unit attention bound (`[F4-*-mma-*]`) -/
theorem T_mma_share : mmaNs dense 32768 1 1 = 61440 ∧ pct 61440 768715 = 80 ∧ frags dense 1 = 1 ∧
    mmaNs dense 32768 1 4 = 245760 ∧ pct 245760 768715 = 320 ∧ frags dense 4 = 4 ∧
    mmaNs dense 32768 1 16 = 983040 ∧ pct 983040 768715 = 1279 ∧ frags dense 16 = 16 ∧
    mmaNs moe 32768 1 1 = 61440 ∧ mmaNs moe 32768 1 4 = 61440 ∧ frags moe 4 = 1 ∧
    mmaNs moe 32768 1 16 = 245760 ∧ pct 245760 768715 = 320 ∧ frags moe 16 = 4 ∧
    kvNs dense 32768 1 gStream false < mmaNs dense 32768 1 16 := by decide

/-! ### Row 25: the regime map (`[F4-regime]`): binding term and its share, every cell -/
theorem T_regime_dense :
    bindsW dense 4096 1 1 br0 lamMid 0 = true ∧ pct (wNs dense 1 1 br0 0) (stepNs dense 4096 1 1 br0 lamMid 0) = 965 ∧
    bindsW dense 4096 1 4 br0 lamMid 0 = true ∧ pct (wNs dense 1 4 br0 0) (stepNs dense 4096 1 4 br0 lamMid 0) = 943 ∧
    bindsW dense 4096 16 1 br0 lamMid 0 = true ∧ pct (wNs dense 16 1 br0 0) (stepNs dense 4096 16 1 br0 lamMid 0) = 897 ∧
    bindsW dense 32768 1 1 br0 lamMid 0 = true ∧ pct (wNs dense 1 1 br0 0) (stepNs dense 32768 1 1 br0 lamMid 0) = 933 ∧
    bindsW dense 32768 1 4 br0 lamMid 0 = true ∧ pct (wNs dense 1 4 br0 0) (stepNs dense 32768 1 4 br0 lamMid 0) = 912 ∧
    bindsW dense 32768 16 1 br0 lamMid 0 = true ∧ pct (wNs dense 16 1 br0 0) (stepNs dense 32768 16 1 br0 lamMid 0) = 588 ∧
    pct (kvTot dense 32768 16 br0) (stepNs dense 32768 16 1 br0 lamMid 0) = 394 ∧
    bindsW dense 131072 1 1 br0 lamMid 0 = true ∧ pct (wNs dense 1 1 br0 0) (stepNs dense 131072 1 1 br0 lamMid 0) = 835 ∧
    bindsW dense 131072 1 4 br0 lamMid 0 = true ∧ pct (wNs dense 1 4 br0 0) (stepNs dense 131072 1 4 br0 lamMid 0) = 818 ∧
    bindsW dense 1048576 1 1 brI8 lamMid 0 = true ∧ pct (wNs dense 1 1 brI8 0) (stepNs dense 1048576 1 1 brI8 lamMid 0) = 588 ∧
    pct (kvTot dense 1048576 1 brI8) (stepNs dense 1048576 1 1 brI8 lamMid 0) = 394 ∧
    bindsW dense 1048576 1 4 brI8 lamMid 0 = true := by decide
theorem T_regime_moe :
    bindsW moe 4096 1 1 br0 lamMid 0 = true ∧ pct (wNs moe 1 1 br0 0) (stepNs moe 4096 1 1 br0 lamMid 0) = 807 ∧
    pct (launchNs moe true) (stepNs moe 4096 1 1 br0 lamMid 0) = 157 ∧
    bindsW moe 4096 1 4 br0 lamMid 0 = true ∧ pct (wNs moe 1 4 br0 0) (stepNs moe 4096 1 4 br0 lamMid 0) = 817 ∧
    bindsW moe 4096 16 1 br0 lamMid 0 = true ∧ pct (wNs moe 16 1 br0 0) (stepNs moe 4096 16 1 br0 lamMid 0) = 955 ∧
    bindsW moe 32768 1 1 br0 lamMid 0 = true ∧ pct (wNs moe 1 1 br0 0) (stepNs moe 32768 1 1 br0 lamMid 0) = 694 ∧
    pct (kvTot moe 32768 1 br0) (stepNs moe 32768 1 1 br0 lamMid 0) = 161 ∧
    pct (launchNs moe true) (stepNs moe 32768 1 1 br0 lamMid 0) = 135 ∧
    bindsW moe 32768 1 4 br0 lamMid 0 = true ∧ pct (wNs moe 1 4 br0 0) (stepNs moe 32768 1 4 br0 lamMid 0) = 781 ∧
    bindsW moe 32768 16 1 br0 lamMid 0 = true ∧ pct (wNs moe 16 1 br0 0) (stepNs moe 32768 16 1 br0 lamMid 0) = 785 ∧
    pct (kvTot moe 32768 16 br0) (stepNs moe 32768 16 1 br0 lamMid 0) = 203 ∧
    bindsW moe 131072 1 1 br0 lamMid 0 = true ∧ pct (wNs moe 1 1 br0 0) (stepNs moe 131072 1 1 br0 lamMid 0) = 468 ∧
    pct (kvTot moe 131072 1 br0) (stepNs moe 131072 1 1 br0 lamMid 0) = 434 ∧
    bindsW moe 131072 1 4 br0 lamMid 0 = true ∧ pct (wNs moe 1 4 br0 0) (stepNs moe 131072 1 4 br0 lamMid 0) = 681 ∧
    bindsKV moe 1048576 1 1 br0 lamMid 0 = true ∧ pct (kvTot moe 1048576 1 br0) (stepNs moe 1048576 1 1 br0 lamMid 0) = 860 ∧
    bindsKV moe 1048576 1 4 br0 lamMid 0 = true ∧ pct (kvTot moe 1048576 1 br0) (stepNs moe 1048576 1 4 br0 lamMid 0) = 624 := by decide
/-- the bounce share is nowhere above 1.1 % and the launch floor is 2.8 % (dense) / 13.5 % (MoE) at 32k -/
theorem T_regime_shares : pctH (xNs dense 1 1 lamMid) (stepNs dense 32768 1 1 br0 lamMid 0) = 6 ∧
    pct (xNs moe 1 1 lamMid) (stepNs moe 32768 1 1 br0 lamMid 0) = 11 ∧
    pct (xNs moe 1 1 lamMid) (stepNs moe 4096 1 1 br0 lamMid 0) = 13 ∧
    pct (launchNs dense true) (stepNs dense 32768 1 1 br0 lamMid 0) = 28 ∧
    pct (launchNs moe true) (stepNs moe 32768 1 1 br0 lamMid 0) = 135 ∧
    pct 18018000 43027016 = 419 ∧ pct 18018000 33410360 = 539 := by decide

/-! ### Row 26 / T_serial: the layer-split ceiling — the fleet streams one die's rate -/
/-- Σ_pos n_pos·c = (Σ_pos n_pos)·c for ANY partition list: the chain's compute time does not depend on
    the layer → die map, only on the layer count -/
theorem T_serial_partition (l : List Nat) (c : Nat) : (l.map (· * c)).sum = l.sum * c := by
  induction l with
  | nil => simp
  | cons h t ih => simp only [List.map, List.sum_cons, ih, Nat.add_mul]
theorem T_serial_partition_120 (l : List Nat) (hl : l.sum = 120) (c : Nat) : (l.map (· * c)).sum = 120 * c := by
  rw [T_serial_partition, hl]
/-- hence every Π = 1 step is ≥ bytes-per-token / R_gemm, and tokens/s is bounded by R_gemm / bytes for ANY
    extra cost (attention, launches, bounces, draft): dense ≤ 0.453 fleet-wide (0.113 per card), MoE ≤ 13.457 (3.364) -/
theorem T_ceiling (extra : Nat) :
    tpsFleet 1000 (tn (streamedPerToken dense 1 .uniform) rGemm + extra) ≤ 453 ∧
    tpsCard 1000 (tn (streamedPerToken dense 1 .uniform) rGemm + extra) ≤ 113 ∧
    tpsFleet 1000 (tn (streamedPerToken moe 1 .uniform) rGemm + extra) ≤ 13457 ∧
    tpsCard 1000 (tn (streamedPerToken moe 1 .uniform) rGemm + extra) ≤ 3364 := by
  have h : tn (streamedPerToken dense 1 .uniform) rGemm = 2202874404 ∧ tn (streamedPerToken moe 1 .uniform) rGemm = 74307164 ∧
      1000 * 1000000000 / 2202874404 = 453 ∧ 1000 * 1000000000 / (4 * 2202874404) = 113 ∧
      1000 * 1000000000 / 74307164 = 13457 ∧ 1000 * 1000000000 / (4 * 74307164) = 3364 := by decide
  unfold tpsFleet tpsCard
  rw [h.1, h.2.1]
  refine ⟨?_, ?_, ?_, ?_⟩
  · have := Nat.div_le_div_left (a := 1000 * 1000000000) (Nat.le_add_right 2202874404 extra) (by decide); omega
  · have := Nat.div_le_div_left (a := 1000 * 1000000000) (Nat.mul_le_mul_left 4 (Nat.le_add_right 2202874404 extra)) (by decide); omega
  · have := Nat.div_le_div_left (a := 1000 * 1000000000) (Nat.le_add_right 74307164 extra) (by decide); omega
  · have := Nat.div_le_div_left (a := 1000 * 1000000000) (Nat.mul_le_mul_left 4 (Nat.le_add_right 74307164 extra)) (by decide); omega
/-- T_serial: the predicted cells sit at 93 % / 55 % of the ceilings; the +2 % two-die measurement is the
    same theorem observed (any partition of the same layers takes the same step) -/
theorem T_serial : tpsCard 1000 (stepNs dense 32768 1 1 br0 lamMid 0) = 105 ∧ tpsCard 1000 (stepNs moe 32768 1 1 br0 lamMid 0) = 1867 ∧
    tpsFleet 1000 (stepNs dense 32768 1 1 br0 lamMid 0) = 423 ∧ pct 105 113 = 929 ∧ pct 1867 3364 = 555 ∧
    x10 1746 276 = 63 := by decide

/-! ### Row 14 (T8 corrected): the bounce share as a function of λ — the step itself contains 16 λ -/
/-- share ≥ 10 % ⟺ λ ≥ 16 392 030 ns (dense) / 917 693 ns (MoE); ≥ 50 % ⟺ λ ≥ 147 548 816 / 8 271 412 ns.
    DESIGN-4 round 1 solved the threshold against the λ = 91 µs step (14.8 ms / 835 µs; 73.8 / 4.18 ms). -/
theorem T_bounce_threshold_dense (lam : Nat) :
    (stepNs dense 32768 1 1 br0 lam 0 ≤ 10 * Tx dense 1 lam ↔ 16392030 ≤ lam) ∧
    (stepNs dense 32768 1 1 br0 lam 0 ≤ 2 * Tx dense 1 lam ↔ 147548816 ≤ lam) := by
  have hb : xchBw dense 1 = 41107 ∧ nLat = 16 := by decide
  rw [(T_step_lambda_form lam).1]
  unfold Tx
  rw [hb.1, hb.2]
  omega
theorem T_bounce_threshold_moe (lam : Nat) :
    (stepNs moe 32768 1 1 br0 lam 0 ≤ 10 * Tx moe 1 lam ↔ 917693 ≤ lam) ∧
    (stepNs moe 32768 1 1 br0 lam 0 ≤ 2 * Tx moe 1 lam ↔ 8271412 ≤ lam) := by
  have hb : xchBw moe 1 = 24367 ∧ nLat = 16 := by decide
  rw [(T_step_lambda_form lam).2]
  unfold Tx
  rw [hb.1, hb.2]
  omega
/-- the round-1 numbers and what they actually are: at λ = 835 µs the MoE bounce is 9.2 % of the step, at 4.18 ms 33.6 % -/
theorem T_bounce_round1 : (2362319269 / 10 - 41107) / 16 = 14761926 ∧ usR 14761926 = 14762 ∧
    (133847319 / 10 - 24367) / 16 = 835022 ∧ usR 835022 = 835 ∧ (133847319 / 2 - 24367) / 16 = 4181205 ∧
    pct (Tx moe 1 835022) (stepNs moe 32768 1 1 br0 835022 0) = 92 ∧
    pct (Tx moe 1 4181205) (stepNs moe 32768 1 1 br0 4181205 0) = 336 ∧
    usR 16392030 = 16392 ∧ usR 917693 = 918 ∧ msR 147548816 = 148 ∧ usR 8271412 = 8271 ∧
    pct (Tx moe 1 917693) (stepNs moe 32768 1 1 br0 917693 0) = 100 ∧
    pct (Tx moe 1 8271412) (stepNs moe 32768 1 1 br0 8271412 0) = 500 := by decide

/-! ### Rows 27–30: what-ifs (`[F5-*]`) -/
/-- P2P at any rate: whatever replaces the exchange (cost x ≥ 0), the saving is ≤ T_x = 1 497 µs < 1.5 ms
    (0.06 % of the dense step) / 1 480 µs (1.1 % MoE); over the λ bracket T_x ≤ 8.04 ms -/
theorem T_p2p_bound (x : Nat) :
    stepNs dense 32768 1 1 br0 lamMid 0 ≤ (stepNs dense 32768 1 1 br0 lamMid 0 - xNs dense 1 1 lamMid + x) + xNs dense 1 1 lamMid ∧
    stepNs moe 32768 1 1 br0 lamMid 0 ≤ (stepNs moe 32768 1 1 br0 lamMid 0 - xNs moe 1 1 lamMid + x) + xNs moe 1 1 lamMid ∧
    xNs dense 1 1 lamMid = 1497107 ∧ 1497107 < 1500000 ∧ xNs moe 1 1 lamMid = 1480367 ∧
    pctH 1497107 2362319269 = 6 ∧ pct 1480367 133847319 = 11 := by
  refine ⟨?_, ?_, by decide⟩
  · unfold stepNs; omega
  · unfold stepNs; omega
/-- D2D 10.7 → 50 GB/s: per-token cross-die traffic is 0 B by construction (KV never moves; the model has no
    D2D term), so only a re-partition move changes: one die's KV at 128k -/
theorem T_d2d : kvMoveNs dense rD2D = 752622773 ∧ msR (kvMoveNs dense rD2D) = 753 ∧ kvMoveNs dense 500 = 161061273 ∧
    msR (kvMoveNs dense 500) = 161 ∧ msR (kvMoveNs moe rD2D) = 201 ∧ msR (kvMoveNs moe 500) = 43 ∧
    gb1 (dense.layers 0 * dense.kvTok * 131072) = 80 ∧ gb1 (moe.layers 0 * moe.kvTok * 131072) = 21 := by decide
/-- tensor-split (premises: 8 dies stream each layer concurrently; 2 host all-reduces per layer; λ = 91 µs;
    launches serialised): 398.53 ms = W/8 273.85 + KV/8 11.53 + lm_head/8 1.50 + launch 65.70 + reductions 45.93
    (round 1 omitted the lm_head/8 term in the decomposition) → 0.627 tok/s/card, 5.9×; MoE 43.03 → 5.810, 3.1× -/
theorem T_tsplit :
    stepTs dense 32768 1 1 br0 lamMid = 398526280 ∧ ms2 (stepTs dense 32768 1 1 br0 lamMid) = 39852 ∧
    ms2 (dense.nL * gemmTsNs dense 1 .uniform .serial) = 27385 ∧ ms2 (dense.nL * (attnNs dense 32768 1 1 gStream cNative false / 8)) = 1153 ∧
    ms2 (tn dense.wHead (8 * rGemm)) = 150 ∧ ms2 (reduceTot dense 1 1 lamMid) = 4593 ∧
    tReduce lamMid 1 16384 = 191393 ∧ usR 191393 = 191 ∧
    tpsCard 1000 (stepTs dense 32768 1 1 br0 lamMid) = 627 ∧ x10 2362319269 398526280 = 59 ∧
    ms2 (stepTs dense 32768 1 1 br0 lamLo) = 35964 ∧ ms2 (stepTs dense 32768 1 1 brNoLaunch lamMid) = 33282 ∧
    stepTs moe 32768 1 1 br0 lamMid = 43027016 ∧ ms2 (stepTs moe 32768 1 1 br0 lamMid) = 4302 ∧
    ms2 (moe.nL * gemmTsNs moe 1 .uniform .serial) = 1161 ∧ ms2 (moe.nL * (attnNs moe 32768 1 1 gStream cNative false / 8)) = 269 ∧
    ms2 (tn moe.wHead (8 * rGemm)) = 37 ∧ ms2 (reduceTot moe 1 1 lamMid) = 1032 ∧ tReduce lamMid 1 4096 = 184347 ∧
    tpsCard 1000 (stepTs moe 32768 1 1 br0 lamMid) = 5810 ∧ x10 133847319 43027016 = 31 ∧
    ms2 (stepTs moe 32768 1 1 br0 lamLo) = 3395 ∧ ms2 (stepTs moe 32768 1 1 brNoLaunch lamMid) = 2500 := by decide
/-- tensor-split + P2P (X = 50 GB/s, λ_p2p = 10 µs): 20 / 13 µs per reduction; 357.51 ms → 0.699 (6.6×), 33.41 → 7.482 (4.0×) -/
theorem T_tsplit_p2p : redP2p dense 1 500 10000 = 20485 ∧ usR 20485 = 20 ∧ redP2p moe 1 500 10000 = 12621 ∧ usR 12621 = 13 ∧
    stepTsP2p dense 32768 1 1 br0 lamMid 500 10000 = 357508360 ∧ tpsCard 1000 357508360 = 699 ∧ x10 2362319269 357508360 = 66 ∧
    stepTsP2p moe 32768 1 1 br0 lamMid 500 10000 = 33410360 ∧ tpsCard 1000 33410360 = 7482 ∧ x10 133847319 33410360 = 40 := by decide
/-- pipelining Π = 8 (premise: the runtime keeps every die busy on a different sequence): fleet tokens/s =
    1 / max_pos block(pos); blocks 293.66–305.99 ms (dense; pos 7 carries lm_head) → 3.268 fleet = 0.817/card
    = 7.7× the chain; MoE 14.02 / 18.63 ms → 53.657 fleet = 13.414/card = 7.1× -/
theorem T_pipelining_blocks :
    dieBlock dense 0 32768 1 1 br0 lamMid 0 = 293668344 ∧ dieBlock dense 1 32768 1 1 br0 lamMid 0 = 293760007 ∧
    dieBlock dense 2 32768 1 1 br0 lamMid 0 = 293761701 ∧ dieBlock dense 7 32768 1 1 br0 lamMid 0 = 305994801 ∧
    maxBlock dense 32768 br0 lamMid 0 = 305994801 ∧ sumBlocks dense 32768 br0 lamMid 0 = 2362228269 ∧
    tpsFleet 1000 (maxBlock dense 32768 br0 lamMid 0) = 3268 ∧ tpsCard 1000 (maxBlock dense 32768 br0 lamMid 0) = 817 ∧
    x10 (stepNs dense 32768 1 1 br0 lamMid 0) (maxBlock dense 32768 br0 lamMid 0) = 77 ∧
    dieBlock moe 0 32768 1 1 br0 lamMid 0 = 18545167 ∧ dieBlock moe 1 32768 1 1 br0 lamMid 0 = 14022898 ∧
    dieBlock moe 2 32768 1 1 br0 lamMid 0 = 18636756 ∧ dieBlock moe 7 32768 1 1 br0 lamMid 0 = 17232190 ∧
    maxBlock moe 32768 br0 lamMid 0 = 18636756 ∧ sumBlocks moe 32768 br0 lamMid 0 = 133756319 ∧
    tpsFleet 1000 (maxBlock moe 32768 br0 lamMid 0) = 53657 ∧ tpsCard 1000 (maxBlock moe 32768 br0 lamMid 0) = 13414 ∧
    x10 (stepNs moe 32768 1 1 br0 lamMid 0) (maxBlock moe 32768 br0 lamMid 0) = 71 := by decide
/-- the per-die step decomposition: T_step = Σ_pos block(pos) + λ (the id-entry latency is the only term not in
    a block), so the pipelined speed-up T_step / max block is ≤ 8 + λ / max block (< 8.003 here) -/
theorem T_pipelining_decomposition :
    stepNs dense 32768 1 1 br0 lamMid 0 = sumBlocks dense 32768 br0 lamMid 0 + lamMid ∧
    stepNs moe 32768 1 1 br0 lamMid 0 = sumBlocks moe 32768 br0 lamMid 0 + lamMid ∧
    stepNs dense 4096 1 1 br0 lamMid 0 = sumBlocks dense 4096 br0 lamMid 0 + lamMid ∧
    stepNs moe 131072 1 1 br0 lamMid 0 = sumBlocks moe 131072 br0 lamMid 0 + lamMid := by decide
theorem maxOver_mono (f : Nat → Nat) : ∀ n, maxOver f n ≤ maxOver f (n + 1) := by
  intro n; simp only [maxOver]; exact Nat.le_max_left _ _
theorem sumPos_le_maxOver (f : Nat → Nat) : ∀ n, sumPos f (n + 1) ≤ (n + 1) * maxOver f n := by
  intro n
  induction n with
  | zero => simp only [sumPos, maxOver, Nat.one_mul, Nat.zero_add]; exact Nat.le_refl _
  | succ n ih =>
    have h1 : sumPos f (n + 1) ≤ (n + 1) * maxOver f (n + 1) :=
      Nat.le_trans ih (Nat.mul_le_mul_left (n + 1) (maxOver_mono f n))
    have h2 : f (n + 1) ≤ maxOver f (n + 1) := by simp only [maxOver]; exact Nat.le_max_right _ _
    have h3 : sumPos f (n + 1 + 1) = sumPos f (n + 1) + f (n + 1) := rfl
    have h4 : (n + 1 + 1) * maxOver f (n + 1) = (n + 1) * maxOver f (n + 1) + maxOver f (n + 1) := Nat.succ_mul _ _
    rw [h3, h4]
    exact Nat.add_le_add h1 h2
theorem T_pipelining_bound :
    stepNs dense 32768 1 1 br0 lamMid 0 ≤ 8 * maxBlock dense 32768 br0 lamMid 0 + lamMid ∧
    stepNs moe 32768 1 1 br0 lamMid 0 ≤ 8 * maxBlock moe 32768 br0 lamMid 0 + lamMid ∧
    x10 (8 * 305994801 + 91000) 305994801 = 80 ∧ x10 (8 * 18636756 + 91000) 18636756 = 80 := by
  have hd : sumPos (fun p => dieBlock dense p 32768 1 1 br0 lamMid 0) 8 ≤ 8 * maxOver (fun p => dieBlock dense p 32768 1 1 br0 lamMid 0) 7 :=
    sumPos_le_maxOver (fun p => dieBlock dense p 32768 1 1 br0 lamMid 0) 7
  have hm : sumPos (fun p => dieBlock moe p 32768 1 1 br0 lamMid 0) 8 ≤ 8 * maxOver (fun p => dieBlock moe p 32768 1 1 br0 lamMid 0) 7 :=
    sumPos_le_maxOver (fun p => dieBlock moe p 32768 1 1 br0 lamMid 0) 7
  have e := T_pipelining_decomposition
  unfold sumBlocks at e
  unfold maxBlock
  refine ⟨?_, ?_, by decide⟩
  · rw [e.1]; omega
  · rw [e.2.1]; omega
/-- MoE 4/3-layer imbalance at Π = 8: the model's loss against a perfectly balanced 8-way split of the same work
    is 10.3 % (max block 18.64 ms vs 16.72 mean; 53.657 vs 59.810 fleet tokens/s), not the pure-layer 12.5 % -/
theorem T_pipelining_balance : pct (8 * 18636756 - 133756319) (8 * 18636756) = 103 ∧
    tpsFleet 1000 (ceilDiv 133756319 8) = 59810 ∧ ms2 (ceilDiv 133756319 8) = 1671 ∧ pct (4 - 3) 8 = 125 ∧
    x10 (8 * 133847319) 133756319 = 80 := by decide
/-- trunk occupancy at Π = 8: 8 bounces per block on the worst card — 0.06 % (dense) / 0.84 % (MoE, the logits
    card; round 1 said 0.2 %) of the 27.6 GB/s trunk — still no queueing -/
theorem T_pipelining_trunk : pctH (8 * 22149) 305994801 = 6 ∧ pctH (8 * 19478) 18636756 = 84 ∧
    pctH (8 * 4748) 18636756 = 20 := by decide
/-- Π = 8 at L = 32k needs 8 contexts per die: dense L_max(B = 8) = 68 906 ≥ 32 768 -/
theorem T_pipelining_memory : Lmax dense 8 false oRt = 68906 ∧ 32768 ≤ 68906 := by decide

/-! ### Rows 31–33: draft, τ(α, k), speculative decoding (`[F6-*]`) -/
theorem T_tau : tau 500 1 = 1500 ∧ tau 500 2 = 1750 ∧ tau 500 3 = 1875 ∧ tau 500 5 = 1968 ∧ tau 500 7 = 1990 ∧
    tau 700 1 = 1700 ∧ tau 700 2 = 2190 ∧ tau 700 3 = 2533 ∧ tau 700 5 = 2941 ∧ tau 700 7 = 3139 ∧
    tau 900 1 = 1900 ∧ tau 900 2 = 2710 ∧ tau 900 3 = 3439 ∧ tau 900 5 = 4685 ∧ tau 900 7 = 5693 ∧
    tau 1000 3 = 4000 := by decide
/-- τ(α, 3) < 4 for every α < 1 (the verify batch never pays for itself in rows) -/
theorem T_tau_lt_rows : ∀ a, a < 1000 → tau a 3 < 4000 := by decide +kernel
theorem T_spec_steps : stepSpec dense 32768 3 br0 lamMid 0 = stepNs dense 32768 1 4 br0 lamMid 0 ∧
    stepSpec moe 32768 3 br0 lamMid 0 = stepNs moe 32768 1 4 br0 lamMid 0 ∧
    stepSpec dense 32768 7 br0 lamMid 0 = 2489252746 ∧ ms2 2489252746 = 248925 := by decide
/-- T_spec_dense: gain(α) = τ(α,3)·T₁/T₄ as a function of the acceptance hypothesis α (thousandths):
    1.832× / 2.475× / 3.361× at α = 0.5 / 0.7 / 0.9 — "2.4×" is the floor of 2.475 (2.5× rounded);
    tokens/s/card 0.193 / 0.262 / 0.355; best k at α = 0.7 is 7 (0.315; 0.571 at α = 0.9), at α = 0.5 it is 5 (0.200) -/
def gainM (a T1 T4 : Nat) : Nat := tau a 3 * T1 / T4
theorem T_spec_dense : gainM 500 2362319269 2416719328 = 1832 ∧ gainM 700 2362319269 2416719328 = 2475 ∧
    gainM 900 2362319269 2416719328 = 3361 ∧
    tpsCard (tau 500 3) 2416719328 = 193 ∧ tpsCard (tau 700 3) 2416719328 = 262 ∧ tpsCard (tau 900 3) 2416719328 = 355 ∧
    x10 193 105 = 18 ∧ x10 262 105 = 24 ∧ x10 355 105 = 33 ∧ x10 262 105 < 25 ∧ (2475 + 50) / 100 = 25 ∧
    tpsCard (tau 700 7) (stepSpec dense 32768 7 br0 lamMid 0) = 315 ∧ tpsCard (tau 900 7) (stepSpec dense 32768 7 br0 lamMid 0) = 571 ∧
    tpsCard (tau 500 5) (stepSpec dense 32768 5 br0 lamMid 0) = 200 := by decide
/-- on dense the verify step is a gain for EVERY acceptance α ≥ 0.024 at k = 3 (rows are free in W: the break-even
    is τ ≥ T₄/T₁ = 1.023, i.e. α ≥ 0.024; α = 0.023 loses by rounding) -/
theorem T_spec_dense_all_alpha : ∀ a, a < 1001 → 24 ≤ a → 1000 * 2416719328 < tau a 3 * 2362319269 := by decide +kernel
theorem T_spec_dense_breakeven : tau 23 3 * 2362319269 < 1000 * 2416719328 ∧ 2416719328 * 1000 / 2362319269 = 1023 := by decide
theorem T_spec_dense_best_k : (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 700 k) (stepSpec dense 32768 k br0 lamMid 0) ≤ 315) ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 500 k) (stepSpec dense 32768 k br0 lamMid 0) ≤ 200) ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 700 k) (stepSpec moe 32768 k br0 lamMid 0) ≤ 1811) ∧
    tpsCard (tau 700 1) (stepSpec moe 32768 1 br0 lamMid 0) = 1811 ∧ tpsCard (tau 500 1) (stepSpec moe 32768 1 br0 lamMid 0) = 1598 ∧
    tpsCard (tau 900 1) (stepSpec moe 32768 1 br0 lamMid 0) = 2024 := by decide
/-- T_spec_moe_loss — the mechanism: under uniform routing D(k+1) = (k+1)·D(1), so the verify batch multiplies the
    active-expert bytes: experts(4) − 2F = 4·(experts(1) − 2F); T₄ ≥ 4·E₁ + (T₁ − E₁); hence any τ < 1 + 3·E₁/T₁ = 2.852
    is a loss regardless of the draft cost, and τ(0.7, 3) = 2.533 -/
theorem T_spec_moe_mechanism : dOf .uniform 4 = 4 * dOf .uniform 1 ∧
    expertsNs moe 4 .uniform .serial - 2 * fMoe = 4 * (expertsNs moe 1 .uniform .serial - 2 * fMoe) ∧
    moe.nL * (expertsNs moe 1 .uniform .serial - 2 * fMoe) = 82641888 ∧
    4 * 82641888 + (133847319 - 82641888) ≤ 436122823 ∧ 1000 + 3 * 82641888 * 1000 / 133847319 = 2852 ∧
    tau 700 3 < 2852 ∧ pct 82641888 133847319 = 617 := by decide
/-- T_spec_moe_loss — both directions, for every acceptance α ≤ 1 (thousandths), at k = 3, L = 32k:
    uniform: loss ⟺ α ≤ 0.864 (τ < T₄/T₁ = 3.2584; "α ≥ 0.87" in round 1 is the two-decimal rounding of 0.865);
    Zipf(1.5): loss ⟺ α ≤ 0.646 (threshold τ = 2.3322, α* = 0.647 — round 1's "α ≥ 0.65" holds);
    Zipf(1.0) (D(4) = 25): loss ⟺ α ≤ 0.746 — new row. Exact criterion τ·T₁ < 1000·T₄, and the tps consequence. -/
theorem T_spec_moe_loss_exact : ∀ a, a < 1001 →
    ((tau a 3 * 133847319 < 1000 * 436122823 ↔ a ≤ 864) ∧
     (tau a 3 * 133847319 < 1000 * 312159991 ↔ a ≤ 646) ∧
     (tau a 3 * 133847319 < 1000 * 363811171 ↔ a ≤ 746)) := by decide +kernel
theorem T_spec_moe_loss_tps : ∀ a, a < 1001 →
    ((a ≤ 864 → tpsCard (tau a 3) 436122823 < 1867) ∧ (865 ≤ a → 1867 < tpsCard (tau a 3) 436122823) ∧
     (a ≤ 646 → tpsCard (tau a 3) 312159991 ≤ 1867) ∧ (647 ≤ a → 1867 < tpsCard (tau a 3) 312159991)) := by decide +kernel
/-- at α = 0.646 the Zipf(1.5) row ties at 1.867 in thousandths while the exact criterion is a loss by 0.01 % -/
theorem T_spec_moe_tie : tpsCard (tau 646 3) 312159991 = 1867 ∧ tpsCard (tau 645 3) 312159991 = 1865 ∧
    tpsCard (tau 647 3) 312159991 = 1870 ∧ tpsCard (tau 864 3) 436122823 = 1865 ∧ tpsCard (tau 865 3) 436122823 = 1868 := by decide
theorem T_spec_moe_cells : stepNs moe 32768 1 4 brZ15 lamMid 0 = 312159991 ∧ ms2 312159991 = 31215 ∧
    ms2 (wNs moe 1 4 brZ15 0) = 21678 ∧ dOf .zipf15 4 = 20 ∧ stepNs moe 32768 1 4 brZ10 lamMid 0 = 363811171 ∧ dOf .zipf10 4 = 25 ∧
    tpsCard (tau 700 3) 312159991 = 2028 ∧ x10 2028 1867 = 10 ∧ tpsCard (tau 700 3) 363811171 = 1740 ∧
    tpsCard (tau 500 3) 436122823 = 1074 ∧ tpsCard (tau 700 3) 436122823 = 1451 ∧ tpsCard (tau 900 3) 436122823 = 1971 ∧
    x10 1074 1867 = 5 ∧ x10 1451 1867 = 7 ∧ x10 1971 1867 = 10 ∧
    436122823 * 1000 / 133847319 = 3258 ∧ 312159991 * 1000 / 133847319 = 2332 ∧ 363811171 * 1000 / 133847319 = 2718 ∧
    tau 864 3 = 3254 ∧ tau 865 3 = 3260 ∧ tau 870 3 = 3283 ∧ tau 860 3 = 3234 ∧ tau 646 3 = 2332 ∧ tau 647 3 = 2335 ∧
    tau 650 3 = 2346 ∧ tau 640 3 = 2310 := by decide
/-- T13 / row 36: rows = B·t ≤ 16; spec k = 3 allows B ≤ 4; the m ≥ 24 cliff is 46.3 % of the flat rate -/
theorem T_rows_cliff : 4 * 4 = 16 ∧ 16 * 1 = 16 ∧ pct rRows24 rGemm = 464 ∧ rRows24 * 1000 / rGemm = 463 := by decide

/-! ### Row 34: rollout (`[F7-*]`) — stage steps and the scaling identity -/
theorem T_rollout_dense : ms2 (prefixStep dense 2 4096 br0 lamMid 0) = 56724 ∧ prefixStep dense 2 32768 br0 lamMid 0 = 587428351 ∧
    ms2 (prefixStep dense 2 32768 br0 lamMid 0) = 58742 ∧ ms2 (prefixStep dense 2 131072 br0 lamMid 0) = 65661 ∧
    ms2 (prefixStep dense 4 4096 br0 lamMid 0) = 113459 ∧ ms2 (prefixStep dense 4 32768 br0 lamMid 0) = 117495 ∧
    ms2 (prefixStep dense 4 131072 br0 lamMid 0) = 131331 ∧ ms2 (prefixStep dense 8 4096 br0 lamMid 0) = 228151 ∧
    ms2 (prefixStep dense 8 32768 br0 lamMid 0) = 236222 ∧ ms2 (prefixStep dense 8 131072 br0 lamMid 0) = 263896 ∧
    ms2 (dieBlock dense 0 4096 1 1 br0 lamMid 0) = 28357 ∧ ms2 (dieBlock dense 1 4096 1 1 br0 lamMid 0) = 28367 ∧
    ms2 (dieBlock dense 0 131072 1 1 br0 lamMid 0) = 32826 ∧ ms2 (dieBlock dense 7 131072 1 1 br0 lamMid 0) = 34058 := by decide
theorem T_rollout_moe : ms2 (prefixStep moe 2 4096 br0 lamMid 0) = 2785 ∧ prefixStep moe 2 32768 br0 lamMid 0 = 32568065 ∧
    ms2 (prefixStep moe 2 32768 br0 lamMid 0) = 3256 ∧ ms2 (prefixStep moe 2 131072 br0 lamMid 0) = 4871 ∧
    ms2 (prefixStep moe 4 4096 br0 lamMid 0) = 5581 ∧ ms2 (prefixStep moe 4 32768 br0 lamMid 0) = 6522 ∧
    ms2 (prefixStep moe 4 131072 br0 lamMid 0) = 9751 ∧ ms2 (prefixStep moe 8 4096 br0 lamMid 0) = 11492 ∧
    ms2 (prefixStep moe 8 32768 br0 lamMid 0) = 13375 ∧ ms2 (prefixStep moe 8 131072 br0 lamMid 0) = 19832 ∧
    ms2 (dieBlock moe 0 4096 1 1 br0 lamMid 0) = 1585 ∧ ms2 (dieBlock moe 1 4096 1 1 br0 lamMid 0) = 1200 ∧
    ms2 (dieBlock moe 0 131072 1 1 br0 lamMid 0) = 2776 ∧ ms2 (dieBlock moe 1 131072 1 1 br0 lamMid 0) = 2094 := by decide
/-- T15 corrected: T_full = 4 × stage-1 + T_head + 2·T_launch (lm_head's launches) + 4 λ + (3 act hops at 13.9 −
    1 at 27.3 + logits) = 4 × 587.43 + 12.04 + 0.57 = 2362.32 ms exactly (round 1 wrote "+ 12 λ + T_head = 2362.8
    with a 0.5 ms residual": 4 × stage-1 already carries 12 of the 16 latencies) -/
theorem T_rollout_identity :
    stepNs dense 32768 1 1 br0 lamMid 0 + tn (act dense 1) d2h0 =
      4 * prefixStep dense 2 32768 br0 lamMid 0 + headNs dense + 2 * tLaunch + 4 * lamMid + 3 * tn (act dense 1) h2d1 + tn (logits dense 1) d2h0 ∧
    stepNs moe 32768 1 1 br0 lamMid 0 + tn (act moe 1) d2h0 =
      4 * prefixStep moe 2 32768 br0 lamMid 0 + headNs moe + 2 * tLaunch + 4 * lamMid + 3 * tn (act moe 1) h2d1 + tn (logits moe 1) d2h0 ∧
    headNs dense + 2 * tLaunch + 4 * lamMid + 3 * tn (act dense 1) h2d1 + tn (logits dense 1) d2h0 - tn (act dense 1) d2h0 = 12605865 ∧
    ms2 12605865 = 1260 ∧ ms2 (12605865 - headNs dense) = 57 ∧ ms2 (4 * 587428351 + 12 * lamMid + headNs dense) = 236284 := by decide

/-! ### Row 35: host-ladder expectations (`[F8-*]`) -/
theorem T_ladder_H1 : tn 4096 h2d0 = 148 ∧ tn 4096 h2d1 = 294 ∧ tn 4096 d2h0 = 150 ∧ tn 4096 d2h1 = 215 ∧
    tn (64 * KiB) h2d0 = 2374 ∧ tn (64 * KiB) h2d1 = 4714 ∧ tn (64 * KiB) d2h0 = 2400 ∧ tn (64 * KiB) d2h1 = 3449 ∧
    tn MiB h2d0 = 37991 ∧ tn MiB h2d1 = 75437 ∧ tn MiB d2h0 = 38409 ∧ tn MiB d2h1 = 55188 ∧
    tn (64 * MiB) h2d0 = 2431480 ∧ tn (64 * MiB) h2d1 = 4827975 ∧ tn (64 * MiB) d2h0 = 2458200 ∧ tn (64 * MiB) d2h1 = 3532045 ∧
    usR 2374 = 2 ∧ usR 4714 = 5 ∧ usR 2431480 = 2431 ∧ usR 4827975 = 4828 ∧ usR 2458200 = 2458 ∧ usR 3532045 = 3532 := by decide
theorem T_ladder_rest : h2d0 + h2d1 = 415 ∧ 15 * 4096 = 61440 ∧ 4 * 4096 = 16384 ∧ 3 * 4096 = 12288 ∧
    gb1 (15 * 4096 * 131072) = 80 ∧ tn (totalResident dense / 4) h2d0 = 3502927693 ∧ 3502927693 / 100000000 = 35 ∧
    tn (totalResident dense / 4) 415 = 2329657936 ∧ 2329657936 / 100000000 = 23 ∧ gb1 (totalResident dense / 2) = 1933 := by decide

/-! ### Row 37: fallbacks (`[F9-*]`) -/
theorem T_fallbacks : 2362319269 - 2202874362 + 2202874362 * rGemm / rGemmSer = 2928500800 ∧ ms2 2928500800 = 292850 ∧
    tpsCard 1000 2928500800 = 85 ∧ stepNs moe 1048576 1 1 brG lamMid 0 = 2178630563 ∧ ms2 2178630563 = 217863 ∧
    tpsCard 1000 2178630563 = 114 ∧ x10 312 114 = 27 ∧ 240 * tLaunch = 21840000 ∧ msR 21840000 = 22 ∧
    ms2 21840000 = 2184 ∧ 3 * 11011000 = 33033000 ∧ 233 * GB / 4 * 10 / h2d0 = 2110507246 ∧
    tpsCard 1000 5221940989 = 47 ∧ 1000 * 1000000000 * 10 / (4 * 5221940989) = 478 := by decide
/-- §10: the single-unknown multipliers at 32k; and the exception — at 1M the gather3x branch moves the MoE cell 2.7× -/
theorem T_single_measurement : x10 1867 1413 = 13 ∧ x10 1413 1867 = 7 ∧ x10 98 105 = 9 ∧ x10 2147 1867 = 11 ∧
    x10 2158 1867 = 11 ∧ x10 108 105 = 10 ∧ x10 1780 1867 = 9 ∧ x10 1886 1867 = 10 ∧ x10 312 114 = 27 ∧
    x10 817 105 = 77 ∧ x10 13414 1867 = 71 ∧ 1413 * 100 / 1867 = 75 ∧ 2147 * 100 / 1867 = 114 := by decide

/-! ### Row 38: power (M) and row 39: the A-fraction approximation as an explicit hypothesis -/
theorem T_power : pSustain < pTdp ∧ cards * pSustain = 564 := by decide
/-- the down-projection is 27.4 % of the dense layer's bytes; 1.6 % more A bytes on it is 0.44 % of the layer
    (round 1 wrote "≤ 0.4 %"); the headline 0.105 survives any per-layer penalty up to 0.8 % (pen ≤ 8) and
    breaks at 0.9 %; the spec-decode cell moves 0.262 → 0.260 at 0.5 % -/
theorem T_afrac_size : pct (16384 * 53248) dense.wStream = 274 ∧ pctH (16384 * 53248 * 16) (dense.wStream * 1000) = 44 ∧
    gemmDenseNs dense 0 = 18256993 ∧ gemmDenseNs dense 5 = 18348277 := by decide
theorem T_afrac_headline : ∀ pen, pen < 9 → tpsCard 1000 (stepNs dense 32768 1 1 br0 lamMid pen) = 105 := by decide
theorem T_afrac_edge : tpsCard 1000 (stepNs dense 32768 1 1 br0 lamMid 9) = 104 ∧
    tpsCard (tau 700 3) (stepNs dense 32768 1 4 br0 lamMid 5) = 260 ∧
    tpsCard (tau 700 3) (stepNs dense 32768 1 4 br0 lamMid 0) = 262 := by decide
/-- the headline cells under the stated approximation (pen ≤ 5, i.e. ≤ 0.5 %) — T_serial with the hypothesis explicit -/
theorem T_serial_dense_afrac (pen : Nat) (hpen : pen ≤ 5) : tpsCard 1000 (stepNs dense 32768 1 1 br0 lamMid pen) = 105 :=
  T_afrac_headline pen (by omega)
/-- the MoE step does not use the dense-layer rate for its expert stream (DESIGN-2's slab time), so `pen` is absent -/
theorem T_serial_moe_afrac (pen : Nat) : stepNs moe 32768 1 1 br0 lamMid pen = 133847319 := by
  have h : ∀ pen, gemmNs moe (1 * 1) br0.fam br0.regime pen = 3207719 := fun _ => rfl
  unfold stepNs wNs
  rw [h]
  decide

/-! ### §0 / §9 summary cells not covered above -/
theorem T_summary : gb1 (dieMem - 84343259136) = 16 ∧ msR 1497107 = 1 ∧ 10 * 1067 / 105 = 101 ∧
    pct 688769088 801092387 = 860 ∧ pct 1475933760 3746007229 = 394 ∧ tpsCard 1000 801092387 = 312 ∧
    tpsCard 1000 3746007229 = 66 ∧ usR (2 * lamMid + 2911) = 185 ∧ usR (2 * lamMid + 3557) = 186 ∧
    tn 2052096 d2h0 = 75168 ∧ 2052096 / 1000000 = 2 ∧ 8208384 / 100000 = 82 ∧
    pctH (300673 + lamMid) 2455181881 = 2 ∧ pctH (300673 + lamMid) 1395365271 = 3 := by decide

/-! ## The load-bearing set under the names of PROMPT-4P (conjunctions of the theorems above) -/
/-- dense at 1M: infeasible with f16 KV for every overhead; the KV-int8 escape fits iff overhead ≤ 3.80 GB -/
theorem T_mem_feas_dense_1M : (∀ ort, ¬ feasible dense 1048576 1 false ort) ∧
    (∀ ort, feasible dense 1048576 1 true ort ↔ ort ≤ 3804224512) ∧ feasible dense 1048576 1 true oRt :=
  ⟨T_mem_infeas_dense_1M, T_mem_feas_kv_int8, T_mem_feas_kv_int8_cells.1⟩
/-- 4 dies cannot hold either shape under ANY layer assignment (resident int8 weights alone); 5 dies can -/
theorem T_min_dies :
    (∀ n0 n1 n2 n3, n0 + n1 + n2 + n3 = 120 →
      ¬ (n0 * dense.wRes ≤ dieMem ∧ n1 * dense.wRes ≤ dieMem ∧ n2 * dense.wRes ≤ dieMem ∧ n3 * dense.wRes ≤ dieMem)) ∧
    (∀ n0 n1 n2 n3, n0 + n1 + n2 + n3 = 28 →
      ¬ (n0 * moe.wRes ≤ dieMem ∧ n1 * moe.wRes ≤ dieMem ∧ n2 * moe.wRes ≤ dieMem ∧ n3 * moe.wRes ≤ dieMem)) ∧
    24 * dense.wRes + dense.wEmbed + 24 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    6 * moe.wRes + moe.wEmbed + 6 * 4096 * 4096 + ws + oRt ≤ dieMem :=
  ⟨T_min_dies_dense_4, T_min_dies_moe_4, T_min_dies_5_dense.1, T_min_dies_5_moe.1⟩
/-- spec decode on MoE: the exact loss criterion and its tokens/s consequence, both directions, every α -/
theorem T_spec_moe_loss :
    (∀ a, a < 1001 →
      ((tau a 3 * 133847319 < 1000 * 436122823 ↔ a ≤ 864) ∧
       (tau a 3 * 133847319 < 1000 * 312159991 ↔ a ≤ 646) ∧
       (tau a 3 * 133847319 < 1000 * 363811171 ↔ a ≤ 746))) ∧
    (∀ a, a < 1001 →
      ((a ≤ 864 → tpsCard (tau a 3) 436122823 < 1867) ∧ (865 ≤ a → 1867 < tpsCard (tau a 3) 436122823) ∧
       (a ≤ 646 → tpsCard (tau a 3) 312159991 ≤ 1867) ∧ (647 ≤ a → 1867 < tpsCard (tau a 3) 312159991))) ∧
    stepNs moe 32768 1 4 br0 lamMid 0 = 436122823 ∧ stepNs moe 32768 1 1 br0 lamMid 0 = 133847319 ∧
    tpsCard (tau 700 3) 436122823 = 1451 ∧ tpsCard 1000 133847319 = 1867 :=
  ⟨T_spec_moe_loss_exact, T_spec_moe_loss_tps, by decide⟩
/-- Π = 8: step = Σ blocks + λ, speed-up ≤ 8 + λ/max, and the 7.7× / 7.1× cells -/
theorem T_pipelining :
    stepNs dense 32768 1 1 br0 lamMid 0 = sumBlocks dense 32768 br0 lamMid 0 + lamMid ∧
    stepNs dense 32768 1 1 br0 lamMid 0 ≤ 8 * maxBlock dense 32768 br0 lamMid 0 + lamMid ∧
    x10 (stepNs dense 32768 1 1 br0 lamMid 0) (maxBlock dense 32768 br0 lamMid 0) = 77 ∧
    stepNs moe 32768 1 1 br0 lamMid 0 = sumBlocks moe 32768 br0 lamMid 0 + lamMid ∧
    stepNs moe 32768 1 1 br0 lamMid 0 ≤ 8 * maxBlock moe 32768 br0 lamMid 0 + lamMid ∧
    x10 (stepNs moe 32768 1 1 br0 lamMid 0) (maxBlock moe 32768 br0 lamMid 0) = 71 :=
  ⟨T_pipelining_decomposition.1, T_pipelining_bound.1, by decide, T_pipelining_decomposition.2.1, T_pipelining_bound.2.1, by decide⟩
/-- what-ifs: P2P saving ≤ T_x < 1.5 ms for any replacement cost x; D2D only moves re-partition KV; tensor-split 5.9× / 3.1× -/
theorem T_whatif (x : Nat) :
    stepNs dense 32768 1 1 br0 lamMid 0 ≤ (stepNs dense 32768 1 1 br0 lamMid 0 - xNs dense 1 1 lamMid + x) + xNs dense 1 1 lamMid ∧
    xNs dense 1 1 lamMid < 1500000 ∧ kvMoveNs dense rD2D = 752622773 ∧ msR (kvMoveNs dense 500) = 161 ∧
    x10 (stepNs dense 32768 1 1 br0 lamMid 0) (stepTs dense 32768 1 1 br0 lamMid) = 59 ∧
    x10 (stepNs moe 32768 1 1 br0 lamMid 0) (stepTs moe 32768 1 1 br0 lamMid) = 31 :=
  ⟨(T_p2p_bound x).1, by decide⟩
