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

  Round 3 (PROMPT-4P2, 2026-11-07): the section after the round-2 umbrellas proves DESIGN-4's round-3 layer (Appendix A′, rows
  R1–R27, `proof/fleet.py` `[R3-*]`) — namespaces `Measured3` / `Attn3F` / `Design3F` (the DESIGN-3 attention chain is duplicated
  from proof/attn.lean, which this file cannot import standalone) and 168 theorems (166 `T3r_*`, two `max4_*` helpers); the round-2
  part above is unchanged and every round-2 theorem stays true of the round-2 model (`T3r_round2_limit` reduces the round-3
  step to it exactly).
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

/-! ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
  # ROUND 3 (PROMPT-4P2, 2026-11-07) — the round-3 layer of DESIGN-4 (Appendix A′, rows R1–R27) as theorems

  Everything above this line is the round-2 file, unchanged (124 theorems; every round-2 theorem stays true of the
  round-2 model). This section transcribes `proof/fleet.py`'s `[R3-*]` model 1:1:
    * `Measured3`  — the HW-MAP e9349c8 inputs round 3 adds (λ, E21 G per page size, E22 op set, c_q, 135.5, 5.3 GB/s/core),
                     plus the two round-4 inputs the MoE-128k tie needs (the session-1 loop's 138.3; the bounce legs are an argument);
    * `Attn3F`     — DESIGN-3's round-3 chain (`proof/attn.py` step3, as `fleet.py` `attn3_seq` calls it: rows = t·g per core,
                     d = 128, H_kv = 8 = cores) and the round-4 chain with the P-fragment bounce legs (`attn4_seq`), DUPLICATED
                     from `proof/attn.lean` (Design / Design3 / Design4) because this file cannot import it standalone — pure
                     integer arithmetic, the same formulas, a separate namespace; `proof/attn.lean` is not touched;
    * `Design3F`   — the round-3 step (`step3`), the per-die block (`die_block3`), tensor-split (`step_tsplit3`), the two-instance
                     variant (`inst_step3`, `min_x`, `cold_share`) and the megakernel launch term (`launch3_ns`).
  Hypothesis variables kept explicit: λ (`lam`), G (`Br3.G`), c_sync (`Br3.mega`), the int4 share x and the runtime overhead
  `ort`, the cold-tier core-slab time `Tc`, the acceptance α (`a`), the bounce legs (`legs`), the vector-chain cost per block
  (`v`, the T3r_spec_dense_split argument) and — new in this round — the two-instance concurrency `c` (H10: aggregate
  throughput of two instances in thousandths of one; measured 1 990 at card scale, 2 000 = full solo speed, 1 000 = serialised).
  Units as above (ns floor, tenths of GB/s, thousandths of tokens/s); `pcsUp`/`pcsDown` = fleet.py `pcs` (tenths of a percent). -/

namespace Measured3
/-- HW-MAP e9349c8 (round 3): host bounce 12.2 / 12.1 µs per direction on 4 KiB sync legs (bounce 23.8–24.6 µs; unchanged under
    a saturating die-0 D2D load). ns. The round-2 anchor 91 µs (`lamMid`) was the launch floor, a different quantity. -/
def lam3 : Nat := 12200
/-- E21 (20/20 reps): aggregate gather rate, tenths GB/s — 256 KiB pages (= the sequential rate; DESIGN-3's default and this plan's
    primary), 64 KiB sequential / shuffled, 16 KiB shuffled -/
def g256 : Nat := 1692
def gSeq64 : Nat := 1690
def gShuf64 : Nat := 1670
def gShuf16 : Nat := 1538
/-- the retained "3× slower" what-if (58.2): no longer a measured branch -/
def g3x : Nat := 582
/-- the on-device f16 → i8 A-quantization pass, ns (m = 1, K = 8 192; +12.2 % over host-packed A), and the passes per layer
    (QKV, O, gate/up with the router, down) -/
def cQ : Nat := 43700
def qPasses : Nat := 4
/-- the integrated production kernel f32-in / f32-out, 135.5 GB/s (tenths): the pessimistic branch for every weight stream -/
def rGemmInt : Nat := 1355
/-- the 5-pass vector i4 → f16 unpack, tenths GB/s per core of int4 bytes (the ALT-2 premise; "> 0.8" before e9349c8) -/
def rW4v : Nat := 53
/-- data-movement table: S1 → L0 loader 26.5 GB/s/core strict-serial; vector SRAM → S1 plain fill 250 GB/s/core (tenths) -/
def rLoader : Nat := 265
def rUsS1 : Nat := 2500
/-- the per-call A-lift residual of the direct path (ALT-1), tenths of ns -/
def cResT : Nat := 254
/-- E22 chained per-call tenths of ns on 1 024 lanes: exp, reduce-max f16, f16 Mul, f32 Mul/Add -/
def tExp : Nat := 2728
def tRm16 : Nat := 1819
def tF16 : Nat := 464
def tF32 : Nat := 636
/-- E22: exp = 11.5 lane-equivalents per element (hundredths); ρ32 = 63.6 / 46.4 = 1.37 (hundredths) -/
def cExp100 : Nat := 1150
def rho32 : Nat := 137
/-- L0C → US drain at mt = 1..4, tenths GB/s/core -/
def rDrain1 : Nat := 1528
def rDrain2 : Nat := 2223
def rDrain3 : Nat := 2603
def rDrain4 : Nat := 2855
/-- the validation pack's merge-chain itemisation, lane-equivalents per block-fragment (commit e9349c8) -/
def mergePack : Nat := 25750
/-- kernel session 1 (HW-MAP 423d433, round 4): the attention kernel's own fresh-path gather at 256 KiB, diagnostic loop -/
def gK1 : Nat := 1383
/-- H10 at card scale (HW-MAP, season h): two instances on disjoint dies at FULL solo speed, 1.99× aggregate (thousandths) -/
def h10Card : Nat := 1990
end Measured3

namespace Attn3F
open Measured Design Measured3

/-! ### DESIGN-3's attention chain at the fleet shapes (duplicated from proof/attn.lean; d = 128, one KV head per core) -/
inductive Conv where
  | T   -- throughput convention (1 lane-op = 1/43.2 ns, f32 at ρ32 = 1.37)
  | C   -- chained-latency bound (every 1 024-lane call at its measured chained ns)
  deriving DecidableEq, Repr
inductive Var where
  | rowmax   -- DESIGN-3 §3.2 as specified (per-row block max): "the chain as specified"
  | lazy     -- §3.4 fixed per-row shift + overflow guard (E35, LICENSED for qk-normalised models): "the fixed-shift chain"
  deriving DecidableEq, Repr
/-- tokens per online-softmax block: 512 at mt ≤ 2, 256 at mt = 3, 4 -/
def blockOf (mt : Nat) : Nat := if mt ≤ 2 then 512 else if mt ≤ 4 then 256 else 128
def mtOf (rows : Nat) : Nat := ceilDiv rows 16
def passesOf (rows : Nat) : Nat := ceilDiv rows 64
def mtPass (rows : Nat) : Nat := mtOf (min rows 64)
def lMatrix (L : Nat) : Nat := 16 * (L / 16)
def nblocks (L mt : Nat) : Nat := ceilDiv (lMatrix L) (blockOf mt)
/-- K + V bytes per token per core at d = 128 -/
def coreTok : Nat := 512
def ddrBlock (G mt : Nat) : Nat := tn (blockOf mt * coreTok * 8) G
def mmaBlock (mt : Nat) : Nat := mt * (blockOf mt / 16 + 8 * (blockOf mt / 128)) * cMma
def loaderBlock (mt : Nat) : Nat := tn ((blockOf mt / 128) * 4096 * mt) rLoader
def drainBlock (mt Rd : Nat) : Nat := tn ((blockOf mt * 16 * 4 + 16 * 128 * 4) * mt) Rd
def rDrainM (mt : Nat) : Nat := if mt ≤ 1 then rDrain1 else if mt = 2 then rDrain2 else if mt = 3 then rDrain3 else rDrain4
/-- vector tail: the L mod 16 newest tokens, scores + PV as 16-row Mul + Add -/
def tailOps (L mt : Nat) : Nat := (L % 16) * 128 * 16 * mt * 4
def call100 (t10 : Nat) : Nat := t10 * 432
def unitF16 : Conv → Nat
  | .T => 100
  | .C => ceilDiv (tF16 * 432) 1024
def unitF32 : Conv → Nat
  | .T => rho32
  | .C => ceilDiv (tF32 * 432) 1024
def treeOps (block : Nat) : Nat := 6 * ((block * 16 / 1024 - 1) * 1024 + 512 + 256)
/-- lane-eq ×100 per block for mt fragments (attn.py chain100) -/
def chain100 (block mt : Nat) : Var → Conv → Nat → Nat
  | .rowmax, c, m => mt * (block * 16 * (6 * unitF32 c + cExp100) + treeOps block * unitF16 c + 16 * call100 tRm16 + 20 * call100 tF16 + m)
  | .lazy, c, m => mt * (block * 16 * (5 * unitF32 c + cExp100) + (block * 16 / 1024) * call100 tRm16 + m)
def vec3 (block mt : Nat) (v : Var) (c : Conv) (m : Nat) : Nat := chain100 block mt v c m * 10 / (rVecCore * 100)
def mergeH : Nat := mergePack * 100
/-- the per-block vector time at the pack's merge -/
def vblk3 (mt : Nat) (v : Var) (c : Conv) : Nat := vec3 (blockOf mt) mt v c mergeH
def fixed3 (L rows : Nat) (v : Var) (c : Conv) : Nat :=
  2 * vblk3 (mtPass rows) v c + drainBlock (mtPass rows) (rDrainM (mtPass rows))
  + tailOps L (mtOf rows) * unitF32 c * 10 / (rVecCore * 100)
/-- the four engine totals of one sequence (fleet.py attn3_seq: KV-int8 halves the KV total) -/
def kv3 (L rows G : Nat) (i8 : Bool) : Nat :=
  passesOf rows * nblocks L (mtPass rows) * ddrBlock G (mtPass rows) / (if i8 then 2 else 1)
def vecT3 (L rows : Nat) (v : Var) (c : Conv) : Nat := passesOf rows * nblocks L (mtPass rows) * vblk3 (mtPass rows) v c
def mmaT3 (L rows : Nat) : Nat := passesOf rows * nblocks L (mtPass rows) * mmaBlock (mtPass rows)
def ldrT3 (L rows : Nat) : Nat := passesOf rows * nblocks L (mtPass rows) * loaderBlock (mtPass rows)
/-- `proof/fleet.py` attn3_seq: per-layer attention of ONE sequence with rows = t·g query rows per core -/
def attn3 (L rows G : Nat) (v : Var) (c : Conv) (i8 : Bool) : Nat :=
  max (max (max (kv3 L rows G i8) (vecT3 L rows v c)) (mmaT3 L rows)) (ldrT3 L rows) + fixed3 L rows v c

/-! ### Round 4 (DESIGN-3 round 4, `fleet.py` attn4_seq): fresh C_o chunk sets, the P-fragment DDR bounce (`legs` ∈ {0, 1, 2}
    transfers of 16 KiB·mt per block on the K/V stream's roof, UNMEASURED), the lazy first-block max, append-then-attend tails -/
def coSets (block : Nat) : Nat := block / 128
def pBytes (mt : Nat) : Nat := coSets (blockOf mt) * 4096 * mt
def ddr4Block (G mt legs : Nat) (i8 : Bool) : Nat := tn ((blockOf mt * coreTok / (if i8 then 2 else 1) + legs * pBytes mt) * 8) G
def merge4 (block : Nat) : Var → Conv → Nat
  | .rowmax, c => call100 tExp + 20 * call100 tF16 + (2048 * (coSets block + 1) + 2048 + 512 + 256 + 256 + 256) * unitF32 c
  | .lazy, c => (2048 * (coSets block + 1) + 512 + 256 + 256) * unitF32 c
def chain4 (block mt : Nat) : Var → Conv → Nat
  | .rowmax, c => mt * (block * 16 * (4 * unitF32 c + cExp100) + treeOps block * unitF16 c + 16 * call100 tRm16 + 20 * call100 tF16
                        + merge4 block .rowmax c)
  | .lazy, c => mt * (block * 16 * (3 * unitF32 c + cExp100) + (block * 16 / 1024) * call100 tRm16 + merge4 block .lazy c)
def vec4 (mt : Nat) (v : Var) (c : Conv) : Nat := chain4 (blockOf mt) mt v c * 10 / (rVecCore * 100)
def firstMax4 (mt : Nat) (c : Conv) : Nat :=
  mt * (blockOf mt * 16 * unitF32 c + treeOps (blockOf mt) * unitF16 c + 16 * call100 tRm16 + 20 * call100 tF16) * 10 / (rVecCore * 100)
def firstMaxOf (mt : Nat) : Var → Conv → Nat
  | .lazy, c => firstMax4 mt c
  | .rowmax, _ => 0
def drain4 (mt Rd : Nat) : Nat := tn ((blockOf mt * 16 * 4 + coSets (blockOf mt) * 16 * 128 * 4) * mt) Rd
def nblocks4 (L t mt : Nat) : Nat := ceilDiv (16 * ((L - t) / 16)) (blockOf mt)
def tail4Ops (L t mt : Nat) : Nat := ((L - t) % 16 + t) * 128 * 16 * mt * 4
def mask4 (t mt : Nat) : Nat := if 2 ≤ t then 512 * mt else 0
def attn4 (L t rows G : Nat) (v : Var) (c : Conv) (legs : Nat) (i8 : Bool) : Nat :=
  max (max (max (passesOf rows * nblocks4 L t (mtPass rows) * ddr4Block G (mtPass rows) legs i8)
                (passesOf rows * nblocks4 L t (mtPass rows) * vec4 (mtPass rows) v c))
           (passesOf rows * nblocks4 L t (mtPass rows) * mmaBlock (mtPass rows)))
      (passesOf rows * nblocks4 L t (mtPass rows) * loaderBlock (mtPass rows))
  + (2 * vec4 (mtPass rows) v c + drain4 (mtPass rows) (rDrainM (mtPass rows))
     + (tail4Ops L t (mtOf rows) + mask4 t (mtOf rows)) * unitF32 c * 10 / (rVecCore * 100) + firstMaxOf (mtPass rows) v c)
end Attn3F

namespace Design3F
open Measured Design Measured3 Attn3F

/-! ### The expert-chain regimes (DESIGN-2 anchor, ping-pong, ALT-1 direct path) and the int4 cold tier (ALT-2) -/
inductive XReg where
  | anchor | pp | directSer | directOvl
  deriving DecidableEq, Repr
/-- a 2 MiB core-slab at the 174.6 per-core share (96 089 ns) and the serialised A lift (3 285 ns) -/
def tBDirect : Nat := 2 * MiB * 80 / rGemm
def aLift : Nat := tn (64 * KiB) rLoader + 32 * cResT / 10
def tSlab3 : XReg → Nat
  | .anchor => tSlabSer
  | .pp => tSlabPP
  | .directSer => tBDirect + aLift
  | .directOvl => tBDirect
/-- the int4 core-slab (1 MiB of int4) on the measured unpack, overlapped with the loader/MMA chain: 197 844 ns -/
def tW4 : Nat := tn MiB rW4v
/-- the strictly serial chain per 2 KiB of int4 AS WRITTEN in fleet.py (4 KiB f16 legs, one MMA call): 596 ns — STALE -/
def pieceSerW : Nat := tn (2 * KiB) rW4v + tn (4 * KiB) rUsS1 + tn (4 * KiB) rLoader + cResT / 10 + cMma
/-- the same chain with the f16 bytes a 2 KiB int4 piece produces (4 096 values = 8 KiB f16, two (16,16,128) calls): 807 ns —
    the alternatives proof round's correction (alt.lean `pieceSerC`), carried here -/
def pieceSerC : Nat := tn (2 * KiB) rW4v + tn (8 * KiB) rUsS1 + tn (8 * KiB) rLoader + 2 * (cResT / 10) + 2 * cMma
def slabSer (piece : Nat) : Nat := 512 * piece
/-- W8-equivalent die rates of the cold tier for dense bytes: overlapped 2·8·5.3 = 84.8; serial per piece (fleet.py R_W4_W8EQ_SER) -/
def rW4ovl : Nat := 2 * 8 * rW4v
def rW4ser (piece : Nat) : Nat := 8 * ((2 * 4 * KiB * 10 + piece) / (2 * piece))
/-- an explicit cold core-slab time Tc as a dense W8-equivalent die rate (fleet.py cold_tier) -/
def rW4of (Tc : Nat) : Nat := 2 * 8 * (MiB * 10 / Tc)

/-! ### The quant pass, the weight stream, launches, the draft -/
inductive CQ where
  | none | fixed | prop
  deriving DecidableEq, Repr
def gOf (s : Shape) : Nat := s.Hq / s.Hkv
def quantNs (s : Shape) (rows : Nat) : CQ → Nat
  | .none => 0
  | .fixed => qPasses * cQ
  | .prop => cQ * ceilDiv (rows * (3 * s.d + (if s.moe then 8 * 4096 else 53248))) 8192
def rW (integ : Bool) : Nat := if integ then rGemmInt else rGemm
def gemm3 (s : Shape) (rows : Nat) (fam : Fam) (r : XReg) (integ : Bool) : Nat :=
  if s.moe then tn s.wStream (rW integ) + 2 * fMoe + s.slabs * dOf fam rows * tSlab3 r else tn s.wStream (rW integ)
/-- the per-layer weight time of the t = 1 cell (uniform routing, 174.6 kernel) — the T_w of every crossover -/
def tw3 (s : Shape) (r : XReg) : Nat := gemm3 s 1 .uniform r false
def syncs (s : Shape) : Nat := if s.moe then 5 else 4
/-- one cross-core reduction through DDR: 8 partials written + read (f32), x written (f16), x read by 8 cores -/
def redBytes (rows d : Nat) : Nat := 8 * rows * d * 4 + 8 * rows * d * 4 + rows * d * 2 + 8 * rows * d * 2
def launch3 (s : Shape) (rows : Nat) (launch : Bool) : Option Nat → Nat
  | none => if launch then (s.nL * s.nlaunch + 2) * tLaunch else 0
  | some c => (if launch then (s.nL + 2) * tLaunch else 0) + s.nL * (syncs s * c + 2 * tn (redBytes rows s.d) rGemm)
def draftNl : Option Nat → Nat
  | none => draftLaunch
  | some _ => 24
def draftSync : Option Nat → Nat
  | none => 0
  | some c => 24 * 4 * c
def draft3Tok (lam : Nat) (launch : Bool) (cq : CQ) (mega : Option Nat) : Nat :=
  tn draftW rGemm + tn draftKv rGemm + (if launch then draftNl mega * tLaunch else 0)
  + (if cq = .none then 0 else 24 * qPasses * cQ) + tn (128256 * 4) d2h0 + 2 * lam + draftSync mega
def draft3 (lam : Nat) (launch : Bool) (cq : CQ) (mega : Option Nat) (k : Nat) : Nat := k * draft3Tok lam launch cq mega

/-! ### The round-3 branch vector and the step (fleet.py BR3 / step3) -/
structure Br3 where
  G : Nat
  var : Var
  conv : Conv
  launch : Bool
  regime : XReg
  fam : Fam
  i8 : Bool
  cq : CQ
  integ : Bool
  mega : Option Nat
  pen : Nat
/-- the primary round-3 branch: 256 KiB pages (169.2), the chain as specified (throughput convention), launches serialised,
    the anchored serial MoE regime, uniform routing, f16 KV, the quant pass fixed per pass, the 174.6 kernel, no megakernel -/
def br3 : Br3 := { G := g256, var := .rowmax, conv := .T, launch := true, regime := .anchor, fam := .uniform, i8 := false,
                   cq := .fixed, integ := false, mega := none, pen := 0 }
def gemmTot3 (s : Shape) (B t : Nat) (b : Br3) : Nat :=
  if s.moe then s.nL * gemm3 s (B * t) b.fam b.regime b.integ
  else s.nL * gemm3 s (B * t) b.fam b.regime b.integ + s.nL * gemm3 s (B * t) b.fam b.regime b.integ * b.pen / 1000
def head3 (s : Shape) (b : Br3) : Nat := tn s.wHead (rW b.integ)
/-- the step's parts (fleet.py `parts`): W, ATTN, LAUNCH, QUANT, XCH, DRAFT -/
def W3 (s : Shape) (B t : Nat) (b : Br3) : Nat := gemmTot3 s B t b + head3 s b
def aSeq3 (s : Shape) (L t : Nat) (b : Br3) : Nat := attn3 L (t * gOf s) b.G b.var b.conv b.i8
def A3 (s : Shape) (L B t : Nat) (b : Br3) : Nat := s.nL * B * aSeq3 s L t b
def Ln3 (s : Shape) (B t : Nat) (b : Br3) : Nat := launch3 s (B * t) b.launch b.mega
def Q3 (s : Shape) (B t : Nat) (b : Br3) : Nat := s.nL * quantNs s (B * t) b.cq
def X3 (s : Shape) (B t lam : Nat) : Nat := Tx s (B * t) lam
def D3 (t : Nat) (b : Br3) (lam : Nat) : Nat := if t > 1 then draft3 lam b.launch b.cq b.mega kDraft else 0
def step3 (s : Shape) (L B t : Nat) (b : Br3) (lam : Nat) : Nat :=
  W3 s B t b + A3 s L B t b + Ln3 s B t b + Q3 s B t b + X3 s B t lam + D3 t b lam
/-- a verify step with k drafts (rows = k + 1): the draft term scales with k -/
def stepSpec3 (s : Shape) (L k : Nat) (b : Br3) (lam : Nat) : Nat :=
  W3 s 1 (k + 1) b + A3 s L 1 (k + 1) b + Ln3 s 1 (k + 1) b + Q3 s 1 (k + 1) b + X3 s 1 (k + 1) lam + draft3 lam b.launch b.cq b.mega k
/-- "W binds": the weight stream is strictly the largest additive term (Bool so that a regime map is one `decide`) -/
def bindsW3 (s : Shape) (L B t : Nat) (b : Br3) (lam : Nat) : Bool :=
  decide (A3 s L B t b < W3 s B t b) && decide (Ln3 s B t b < W3 s B t b) && decide (Q3 s B t b < W3 s B t b) &&
  decide (X3 s B t lam < W3 s B t b) && decide (D3 t b lam < W3 s B t b)
def bindsA3 (s : Shape) (L B t : Nat) (b : Br3) (lam : Nat) : Bool :=
  decide (W3 s B t b < A3 s L B t b) && decide (Ln3 s B t b < A3 s L B t b) && decide (Q3 s B t b < A3 s L B t b) &&
  decide (X3 s B t lam < A3 s L B t b) && decide (D3 t b lam < A3 s L B t b)

/-! ### Π = 8 blocks, rollout prefixes, tensor-split (fleet.py die_block3, step_tsplit3) -/
def dieBlock3 (s : Shape) (pos L B t : Nat) (b : Br3) (lam : Nat) : Nat :=
  s.layers pos * (gemm3 s (B * t) b.fam b.regime b.integ + B * aSeq3 s L t b + (if b.launch then s.nlaunch * tLaunch else 0)
                  + quantNs s (B * t) b.cq)
  + (if pos = 7 then headNs s + (if b.launch then 2 * tLaunch else 0) else 0)
  + (if pos > 0 then tn (act s (B * t)) (h2d (die pos)) + lam else 0)
  + (if pos < 7 then tn (act s (B * t)) (d2h (die pos)) + lam else tn (logits s (B * t)) (d2h (die pos)) + lam)
def sumBlocks3 (s : Shape) (L : Nat) (b : Br3) (lam : Nat) : Nat := sumPos (fun p => dieBlock3 s p L 1 1 b lam) 8
def maxBlock3 (s : Shape) (L : Nat) (b : Br3) (lam : Nat) : Nat := maxOver (fun p => dieBlock3 s p L 1 1 b lam) 7
def prefix3 (s : Shape) (npos L : Nat) (b : Br3) (lam : Nat) : Nat := sumPos (fun p => dieBlock3 s p L 1 1 b lam) npos
def gemmTs3 (s : Shape) (rows : Nat) (fam : Fam) (r : XReg) : Nat :=
  if s.moe then tn s.wStream (8 * rGemm) + 2 * fMoe + s.slabs * dOf fam rows * tSlab3 r / 8 else tn s.wStream (8 * rGemm)
def stepTs3 (s : Shape) (L B t : Nat) (b : Br3) (lam : Nat) : Nat :=
  s.nL * (gemmTs3 s (B * t) b.fam b.regime + B * aSeq3 s L t b / 8) + tn s.wHead (8 * rGemm)
  + (if b.launch then (s.nL * s.nlaunch + 2) * tLaunch else 0) + Q3 s B t b + s.nL * 2 * tReduce lam (B * t) s.d

/-! ### Variant I (ALT-2): two 4-die instances, chain c0.d1 → c0.d0 → c1.d1 → c1.d0, the minimal int4 share x per die -/
def layers4 (s : Shape) : Nat := if s.moe then 7 else 30
/-- the candidate bytes per layer for the int4 tier: MoE the expert slabs (attention stays int8), dense the whole layer -/
def candBytes (s : Shape) : Nat := if s.moe then s.wRes - s.wStream else s.wStream
def instDieWeights (s : Shape) (pos x : Nat) : Nat :=
  layers4 s * (s.wRes - candBytes s * x / 2000) + (if pos = 0 then s.wEmbed else 0) + (if pos = 3 then s.wHead else 0)
  + (if s.moe = false ∧ pos = 1 then draftW + draftKv else 0)
def instDieKv (s : Shape) (L B : Nat) (i8 : Bool) : Nat := if i8 then layers4 s * s.kvTok * L * B / 2 else layers4 s * s.kvTok * L * B
def instTotal (s : Shape) (pos L B : Nat) (i8 : Bool) (ort x : Nat) : Nat := instDieWeights s pos x + instDieKv s L B i8 + ws + ort
/-- the fit on die pos at overhead `ort` (the H8 / H11 hypothesis) and int4 share `x` (thousandths) -/
abbrev instFits (s : Shape) (pos L B : Nat) (i8 : Bool) (ort x : Nat) : Prop := instTotal s pos L B i8 ort x ≤ dieMem
def instXchBw (s : Shape) (rows : Nat) : Nat :=
  sumPos (fun p => hopBw (act s rows) (die p) (die (p + 1))) 3 + tn (logits s rows) (d2h (die 3)) + tn (rows * 4) (h2d (die 0))
def instXch (s : Shape) (rows lam : Nat) : Nat := instXchBw s rows + 8 * lam
/-- Zipf(1.0) popularity: rank weights 1/r over 256 experts as exact scaled naturals (Dz = lcm 1..256), as alt.lean -/
def lcmTo : Nat → Nat
  | 0 => 1
  | n + 1 => Nat.lcm (lcmTo n) (n + 1)
def hSum (D : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => hSum D n + D / (n + 1)
def Dz : Nat := lcmTo 256
def hTot : Nat := hSum Dz 256
/-- the traffic of the coldest nc experts: H(256) − H(256 − nc), scaled by Dz -/
def hCold (nc : Nat) : Nat := hTot - hSum Dz (256 - nc)
def ncOf (x : Nat) : Nat := 256 * x / 1000
inductive Pop where
  | uniform | zipf10
  deriving DecidableEq, Repr
/-- MoE expert time per layer when a share of the streamed slabs is int4: one floor of the exact rational (fleet.py `int(...)`) -/
def expCold (D x Thot Tc : Nat) : Nat := 3 * D * (Thot * (1000 - x) + Tc * x) / 1000
def expColdZ (D nc nt Thot Tc : Nat) : Nat := 3 * D * (Thot * (nt - nc) + Tc * nc) / nt
/-- weights per layer on an instance die: MoE hot / cold expert tiers; dense (1 − x) at the kernel rate + x at the int4 rate -/
def instWl (s : Shape) (rows x : Nat) (fam : Fam) (pop : Pop) (Thot Tc R4 : Nat) (integ : Bool) : Nat :=
  if s.moe then
    tn s.wStream (rW integ) + 2 * fMoe +
      (if pop = .uniform then expCold (dOf fam rows) x Thot Tc else expColdZ (dOf fam rows) (hCold (ncOf x)) hTot Thot Tc)
  else (s.wStream * 10 * (1000 - x) * R4 + s.wStream * 10 * x * rW integ) / (1000 * rW integ * R4)
def sum4 (f : Nat → Nat) : Nat := f 0 + f 1 + f 2 + f 3
def instNl (s : Shape) : Option Nat → Nat
  | none => s.nlaunch
  | some _ => 1
def instMega (s : Shape) (rows : Nat) : Option Nat → Nat
  | none => 0
  | some c => syncs s * c + 2 * tn (redBytes rows s.d) rGemm
/-- fleet.py inst_step3 (via inst_step3c): the step of ONE 4-die instance with per-die int4 shares xs, hot regime `hot`,
    cold core-slab time Tc (MoE) / cold W8-equivalent rate R4 (dense) -/
def instStep3 (s : Shape) (L B t : Nat) (xs : Nat → Nat) (hot : XReg) (Tc R4 : Nat) (pop : Pop) (b : Br3) (lam : Nat) : Nat :=
  sum4 (fun pos => layers4 s * (instWl s (B * t) (xs pos) b.fam pop (tSlab3 hot) Tc R4 b.integ + B * aSeq3 s L t b
                                 + instNl s b.mega * tLaunch + quantNs s (B * t) b.cq + instMega s (B * t) b.mega))
  + tn s.wHead (rW b.integ) + 2 * tLaunch + instXch s (B * t) lam + D3 t b lam
/-- tokens/s per card of two instances at aggregate concurrency c (H10: thousandths of one instance's throughput;
    2 000 = both at full solo speed, as fleet.py tps_card_inst; 1 990 = the card-scale measurement; 1 000 = serialised) -/
def tpsInst (tok c T : Nat) : Nat := tok * c * 1000000 / (4 * T)
/-- the minimal share vectors fleet.py's min_x finds (proved minimal below) -/
def xsMoe4k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 163 else 152
def xsMoe32k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 182 else 170
def xsMoe128k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 244 else 232
def xsMoe1M : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 827 else 816
def xsMoe32kB16 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 494 else 482
def xsDense4k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 303 else if p = 1 then 284 else 259
def xsDense32k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 376 else if p = 1 then 358 else 332
def xsDense128k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 629 else if p = 1 then 610 else 585
def xsAll : Nat → Nat := fun _ => 1000

/-! ### Named one-toggle branches of the round-3 step (fleet.py `step3(..., **kw)`) -/
def br3Lazy : Br3 := { br3 with var := .lazy }
def br3C : Br3 := { br3 with conv := .C }
def br3I8 : Br3 := { br3 with i8 := true }
def br3I8Lazy : Br3 := { br3 with i8 := true, var := .lazy }
def br3G (G : Nat) : Br3 := { br3 with G := G }
def br3Reg (r : XReg) : Br3 := { br3 with regime := r }
def br3Fam (f : Fam) : Br3 := { br3 with fam := f }
def br3FamReg (f : Fam) (r : XReg) : Br3 := { br3 with fam := f, regime := r }
def br3Mega (c : Nat) : Br3 := { br3 with mega := some c }

/-- the round-2 limit of the round-3 step: no quant pass (G, chain and λ are then replaced by the round-2 attention and λ) -/
def br3R2 : Br3 := { br3 with cq := .none }
/-- fleet.py step4f: the round-3 step with DESIGN-3's round-4 attention term (fresh sets, the P bounce legs, the lazy first-block max) -/
def step4F (s : Shape) (L B t : Nat) (b : Br3) (legs lam : Nat) : Nat :=
  W3 s B t b + s.nL * B * attn4 L t (t * gOf s) b.G b.var b.conv legs b.i8 + Ln3 s B t b + Q3 s B t b + X3 s B t lam + D3 t b lam
/-- the dense verify step (k = 3, rows 64 = four fragments on 256-token blocks, 32k) with the per-block vector chain cost v free —
    the T3r_spec_dense_split argument (the chain as specified gives v = 27 350 ns, the fixed-shift chain 12 254 ns) -/
def specDenseV (v : Nat) : Nat :=
  W3 dense 1 4 br3 + dense.nL * 1 * (128 * max (max (max 6197 v) 1920) 1236 + (2 * v + 344))
  + Ln3 dense 1 4 br3 + Q3 dense 1 4 br3 + X3 dense 1 4 lam3 + D3 4 br3 lam3

/-! ### fleet.py `pcs`: signed percent change in tenths, as two Nat halves -/
def pcsUp (n d : Nat) : Nat := (n - d) * 1000 / d
def pcsDown (n d : Nat) : Nat := (d - n) * 1000 / d
/-- a ratio a/b in hundredths, round-half-up (the "0.98×" convention of §10) -/
def x100r (a b : Nat) : Nat := (200 * a + b) / (2 * b)
end Design3F

open Measured3 Attn3F Design3F

/-! ## Round-3 proofs — one block per Appendix A′ row (R1–R27), then the PROMPT-4P2 targets and the corrections -/

/-! ### R1 (`[R3-xch-*]`, `[R3-inst-*]`): λ measured; T_x = Σbw + 16 λ; the instance chain carries 8 λ -/
theorem T3r_Tx_form (s : Shape) (rows lam : Nat) : Tx s rows lam = xchBw s rows + 16 * lam ∧ instXch s rows lam = instXchBw s rows + 8 * lam :=
  ⟨rfl, rfl⟩
theorem T3r_Tx : lam3 = 12200 ∧ 2 * lam3 = 24400 ∧
    Tx dense 1 lam3 = 236307 ∧ Tx dense 4 lam3 = 359643 ∧ Tx dense 16 lam3 = 852999 ∧
    Tx moe 1 lam3 = 219567 ∧ Tx moe 4 lam3 = 292684 ∧ Tx moe 16 lam3 = 585151 ∧
    xchBw dense 4 = 164443 ∧ xchBw moe 1 = 24367 ∧ xchBw moe 4 = 97484 ∧ xchBw moe 16 = 389951 ∧
    usR (Tx dense 1 lam3) = 236 ∧ usR (Tx dense 4 lam3) = 360 ∧ usR (Tx dense 16 lam3) = 853 ∧
    usR (Tx moe 1 lam3) = 220 ∧ usR (Tx moe 4 lam3) = 293 ∧ usR (Tx moe 16 lam3) = 585 ∧
    usR (Tx dense 1 lamMid) = 1497 ∧ usR (Tx moe 1 lamMid) = 1480 ∧ usR (Tx dense 4 lamMid) = 1620 ∧ usR (Tx dense 16 lamMid) = 2114 ∧
    usR (Tx dense 4 lamLo) = 324 ∧ usR (Tx dense 4 lamHi) = 8164 ∧ usR (Tx dense 16 lamLo) = 818 ∧ usR (Tx dense 16 lamHi) = 8658 ∧
    instXch dense 1 lam3 = 125771 ∧ instXch moe 1 lam3 = 118735 ∧ usR (instXch dense 1 lam3) = 126 ∧ usR (instXch moe 1 lam3) = 119 := by
  decide

/-! ### R2 (`[R3-T8-*]`): the bounce share as an iff over λ — the 32k step is affine in λ with slope 16 -/
theorem T3r_step_lambda_form (lam : Nat) :
    step3 dense 32768 1 1 br3 lam = 2386996682 + 41107 + 16 * lam ∧ step3 moe 32768 1 1 br3 lam = 138474340 + 24367 + 16 * lam := by
  have h : W3 dense 1 1 br3 + A3 dense 32768 1 1 br3 + Ln3 dense 1 1 br3 + Q3 dense 1 1 br3 = 2386996682 ∧
      W3 moe 1 1 br3 + A3 moe 32768 1 1 br3 + Ln3 moe 1 1 br3 + Q3 moe 1 1 br3 = 138474340 ∧
      xchBw dense (1 * 1) = 41107 ∧ xchBw moe (1 * 1) = 24367 := by decide
  have h0 : ∀ lam, D3 1 br3 lam = 0 := fun _ => rfl
  unfold step3 X3 Tx nLat
  rw [h0, h.2.2.1, h.2.2.2]
  omega
/-- dense: the host bounce reaches 10 % of the 32k step iff λ ≥ 16 573 797 ns (16.57 ms) and 50 % iff λ ≥ 149 184 724 ns (149.2 ms) -/
theorem T3r_bounce_threshold_dense (lam : Nat) :
    (step3 dense 32768 1 1 br3 lam ≤ 10 * X3 dense 1 1 lam ↔ 16573797 ≤ lam) ∧
    (step3 dense 32768 1 1 br3 lam ≤ 2 * X3 dense 1 1 lam ↔ 149184724 ≤ lam) := by
  rw [(T3r_step_lambda_form lam).1]
  have hx : X3 dense 1 1 lam = 41107 + 16 * lam := by
    have : xchBw dense (1 * 1) = 41107 := by decide
    unfold X3 Tx nLat; rw [this]
  rw [hx]; constructor <;> constructor <;> intro h <;> omega
/-- MoE: 10 % iff λ ≥ 960 105 ns (round 2: 918 µs — the step grew by the quant pass), 50 % iff λ ≥ 8 653 124 ns -/
theorem T3r_bounce_threshold_moe (lam : Nat) :
    (step3 moe 32768 1 1 br3 lam ≤ 10 * X3 moe 1 1 lam ↔ 960105 ≤ lam) ∧
    (step3 moe 32768 1 1 br3 lam ≤ 2 * X3 moe 1 1 lam ↔ 8653124 ≤ lam) := by
  rw [(T3r_step_lambda_form lam).2]
  have hx : X3 moe 1 1 lam = 24367 + 16 * lam := by
    have : xchBw moe (1 * 1) = 24367 := by decide
    unfold X3 Tx nLat; rw [this]
  rw [hx]; constructor <;> constructor <;> intro h <;> omega
/-- the cells: 16.57 ms / 960 µs, 149.2 / 8.65 ms; at the measured 12.2 µs the share is 0.01 % / 0.16 %, 1 358× / 78× below the
    10 % line -/
theorem T3r_bounce_cells : usR 16573797 = 16574 ∧ usR 149184724 = 149185 ∧ usR 960105 = 960 ∧ usR 8653124 = 8653 ∧
    pctH (X3 dense 1 1 lam3) (step3 dense 32768 1 1 br3 lam3) = 1 ∧ pctH (X3 moe 1 1 lam3) (step3 moe 32768 1 1 br3 lam3) = 16 ∧
    16573797 / lam3 = 1358 ∧ 960105 / lam3 = 78 := by decide

/-! ### R3 (`[R3-attn-*]`): the t = 1 attention per layer, ∀ G ≤ 174.6 in closed form, and the measured-G cells -/
theorem max4_left (a b c d : Nat) (hb : b ≤ a) (hc : c ≤ a) (hd : d ≤ a) : max (max (max a b) c) d = a := by omega
theorem max4_second (a b c d : Nat) (ha : a ≤ b) (hc : c ≤ b) (hd : d ≤ b) : max (max (max a b) c) d = b := by omega
/-- one fragment per pass (dense t = 1: rows 16; MoE t = 1 and t ≤ 4: rows ≤ 16) -/
theorem T3r_mt1 (rows : Nat) (h1 : 1 ≤ rows) (h2 : rows ≤ 16) : passesOf rows = 1 ∧ mtPass rows = 1 ∧ mtOf rows = 1 := by
  unfold passesOf mtPass mtOf ceilDiv; omega
/-- the mt = 1 step structure: one pass, 512-token blocks, the four engines of one fragment -/
theorem T3r_attn_mt1 (L rows G : Nat) (v : Var) (c : Conv) (i8 : Bool) (h1 : 1 ≤ rows) (h2 : rows ≤ 16) :
    attn3 L rows G v c i8 =
      max (max (max (nblocks L 1 * ddrBlock G 1 / (if i8 then 2 else 1)) (nblocks L 1 * vblk3 1 v c)) (nblocks L 1 * mmaBlock 1))
        (nblocks L 1 * loaderBlock 1)
      + (2 * vblk3 1 v c + drainBlock 1 (rDrainM 1) + tailOps L 1 * unitF32 c * 10 / (rVecCore * 100)) := by
  obtain ⟨hp, hm, hmo⟩ := T3r_mt1 rows h1 h2
  unfold attn3 kv3 vecT3 mmaT3 ldrT3 fixed3
  rw [hp, hm, hmo]; simp only [Nat.one_mul]
theorem T3r_block_consts : blockOf 1 = 512 ∧ vblk3 1 .rowmax .T = 9276 ∧ vblk3 1 .rowmax .C = 11836 ∧ vblk3 1 .lazy .T = 5530 ∧
    mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧ drainBlock 1 (rDrainM 1) = 268 ∧ unitF32 .T = 137 ∧ unitF32 .C = 269 ∧
    ddrBlock g256 1 = 12394 ∧ ddrBlock gShuf64 1 = 12557 ∧ ddrBlock gShuf16 1 = 13635 ∧ ddrBlock gStream 1 = 12011 ∧
    ddrBlock g3x 1 = 36033 ∧ ddrBlock gSeq64 1 = 12409 ∧ rVecCore * 100 = 43200 ∧
    pct 9276 12394 = 748 ∧ pct 11836 12394 = 955 := by decide
/-- every t = 1 cell (rows ≤ 16) on the chain as specified, at every G ≤ 174.6: nb(L)·⌊20 971 520 / G⌋ + 18 820 + the L mod 16 tail
    (the block is DDR-bound: ⌊20 971 520 / G⌋ ≥ 12 011 > the 9 276 ns chain) -/
theorem T3r_attn_t1_form (L rows G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) (hr1 : 1 ≤ rows) (hr2 : rows ≤ 16) :
    attn3 L rows G .rowmax .T false = ((16 * (L / 16) + 511) / 512) * (20971520 / G) + 18820 + (L % 16) * 8192 * 137 * 10 / 43200 := by
  rw [T3r_attn_mt1 L rows G .rowmax .T false hr1 hr2]
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 = 20971520 / G := by unfold ddrBlock tn coreTok; rw [hbl]
  have hge : 12011 ≤ 20971520 / G := by
    have := Nat.div_le_div_left (a := 20971520) h2 h1
    have e : 20971520 / gStream = 12011 := by decide
    omega
  have hc := T3r_block_consts
  have e1 : (if false = true then 2 else 1) = 1 := rfl
  rw [hddr, e1, Nat.div_one, hc.2.1, hc.2.2.2.2.1, hc.2.2.2.2.2.1, hc.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.1]
  have hn9 : nblocks L 1 * 9276 ≤ nblocks L 1 * (20971520 / G) := Nat.mul_le_mul_left _ (by omega)
  have hn6 : nblocks L 1 * 960 ≤ nblocks L 1 * (20971520 / G) := Nat.mul_le_mul_left _ (by omega)
  have hn4 : nblocks L 1 * 618 ≤ nblocks L 1 * (20971520 / G) := Nat.mul_le_mul_left _ (by omega)
  rw [max4_left _ _ _ _ hn9 hn6 hn4]
  unfold nblocks lMatrix ceilDiv tailOps rVecCore
  rw [hbl]
  have ha : (16 * (L / 16) + 512 - 1) / 512 = (16 * (L / 16) + 511) / 512 := by omega
  rw [ha]
  omega
/-- the measured-G cells (ns per layer, one sequence; dense t = 1 rows 16 = MoE t = 1 rows 4): 256 KiB / 64 KiB / 16 KiB / 174.6 /
    gather3x, the chained corner, the fixed-shift chain, the fixed costs, round 2's stream -/
theorem T3r_attn_t1 :
    attn3 4096 16 g256 .rowmax .T false = 117972 ∧ attn3 32768 16 g256 .rowmax .T false = 812036 ∧
    attn3 131072 16 g256 .rowmax .T false = 3191684 ∧ attn3 1048576 16 g256 .rowmax .T false = 25401732 ∧
    attn3 4096 16 gShuf64 .rowmax .T false = 119276 ∧ attn3 32768 16 gShuf64 .rowmax .T false = 822468 ∧
    attn3 131072 16 gShuf64 .rowmax .T false = 3233412 ∧ attn3 1048576 16 gShuf64 .rowmax .T false = 25735556 ∧
    attn3 4096 16 gShuf16 .rowmax .T false = 127900 ∧ attn3 32768 16 gShuf16 .rowmax .T false = 891460 ∧
    attn3 131072 16 gShuf16 .rowmax .T false = 3509380 ∧ attn3 1048576 16 gShuf16 .rowmax .T false = 27943300 ∧
    attn3 4096 16 gStream .rowmax .T false = 114908 ∧ attn3 32768 16 gStream .rowmax .T false = 787524 ∧
    attn3 131072 16 gStream .rowmax .T false = 3093636 ∧ attn3 1048576 16 gStream .rowmax .T false = 24617348 ∧
    attn3 4096 16 g3x .rowmax .T false = 307084 ∧ attn3 32768 16 g3x .rowmax .T false = 2324932 ∧
    attn3 131072 16 g3x .rowmax .T false = 9243268 ∧ attn3 1048576 16 g3x .rowmax .T false = 73814404 ∧
    attn3 4096 16 g256 .rowmax .C false = 123092 ∧ attn3 32768 16 g256 .rowmax .C false = 817156 ∧
    attn3 131072 16 g256 .rowmax .C false = 3196804 ∧ attn3 1048576 16 g256 .rowmax .C false = 25406852 ∧
    attn3 4096 16 g256 .lazy .T false = 110480 ∧ attn3 32768 16 g256 .lazy .T false = 804544 ∧
    attn3 131072 16 g256 .lazy .T false = 3184192 ∧ attn3 1048576 16 g256 .lazy .T false = 25394240 ∧
    fixed3 32768 16 .rowmax .T = 18820 ∧ fixed3 32768 16 .lazy .T = 11328 ∧
    attn3 32768 4 g256 .rowmax .T false = attn3 32768 16 g256 .rowmax .T false ∧
    attn3 1048576 4 g256 .rowmax .T false = attn3 1048576 16 g256 .rowmax .T false ∧
    nblocks 32768 1 = 64 ∧ nblocks 1048576 1 = 2048 ∧
    kvNs dense 32768 1 gStream false = 768715 ∧ kvNs dense 1048576 1 gStream false = 24598896 ∧
    pct 18820 117972 = 160 ∧ pct 18820 812036 = 23 := by decide
/-- every t = 1 measured cell is KV-bound (the KV total exceeds the vector, MMA and loader totals) -/
theorem T3r_attn_t1_bind : vecT3 32768 16 .rowmax .T < kv3 32768 16 g256 false ∧ vecT3 1048576 16 .rowmax .T < kv3 1048576 16 g256 false ∧
    vecT3 1048576 16 .rowmax .C < kv3 1048576 16 g256 false ∧ vecT3 1048576 16 .rowmax .T < kv3 1048576 16 gStream false ∧
    mmaT3 1048576 16 < kv3 1048576 16 gStream false ∧ ldrT3 1048576 16 < kv3 1048576 16 gStream false := by decide

/-! ### R4 (`[R3-attn-*]`): verify batches — dense t = 4 is 64 rows = four fragments on 256-token blocks, VECTOR-bound -/
theorem T3r_attn_t4 :
    attn3 4096 64 g256 .rowmax .T false = 492644 ∧ attn3 32768 64 g256 .rowmax .T false = 3555844 ∧
    attn3 131072 64 g256 .rowmax .T false = 14058244 ∧ attn3 1048576 64 g256 .rowmax .T false = 112080644 ∧
    attn3 4096 64 g256 .lazy .T false = 220916 ∧ attn3 32768 64 g256 .lazy .T false = 1593364 ∧
    attn3 131072 64 g256 .lazy .T false = 6298900 ∧ attn3 1048576 64 g256 .lazy .T false = 50217236 ∧
    attn3 4096 16 g256 .rowmax .T false = 117972 ∧ attn3 32768 16 g256 .rowmax .T false = 812036 ∧
    passesOf 64 = 1 ∧ mtPass 64 = 4 ∧ blockOf 4 = 256 ∧ nblocks 32768 4 = 128 ∧
    vblk3 4 .rowmax .T = 27350 ∧ vblk3 4 .lazy .T = 12254 ∧ ddrBlock g256 4 = 6197 ∧ x10 27350 6197 = 44 ∧
    kv3 32768 64 g256 false = 793216 ∧ vecT3 32768 64 .rowmax .T = 3500800 ∧ vecT3 32768 64 .lazy .T = 1568512 ∧
    kv3 32768 64 g256 false < vecT3 32768 64 .lazy .T ∧ fixed3 32768 64 .rowmax .T = 55044 ∧ fixed3 32768 64 .lazy .T = 24852 := by
  decide

/-! ### R5 (`[R3-attn-*]`): KV-int8 halves the stream, not the chain — vector-bound at t = 1 on the chain as specified -/
theorem T3r_attn_i8 :
    attn3 4096 16 g256 .rowmax .T true = 93028 ∧ attn3 32768 16 g256 .rowmax .T true = 612484 ∧
    attn3 131072 16 g256 .rowmax .T true = 2393476 ∧ attn3 1048576 16 g256 .rowmax .T true = 19016068 ∧
    attn3 4096 16 g256 .lazy .T true = 60904 ∧ attn3 32768 16 g256 .lazy .T true = 407936 ∧
    attn3 131072 16 g256 .lazy .T true = 1597760 ∧ attn3 1048576 16 g256 .lazy .T true = 12702784 ∧
    kv3 32768 16 g256 true = 396608 ∧ vecT3 32768 16 .rowmax .T = 593664 ∧ vecT3 32768 16 .lazy .T = 353920 ∧
    kv3 32768 16 g256 true < vecT3 32768 16 .rowmax .T ∧ vecT3 32768 16 .lazy .T < kv3 32768 16 g256 true ∧
    kv3 1048576 16 g256 true = 12691456 ∧ vecT3 1048576 16 .rowmax .T = 18997248 ∧ vecT3 1048576 16 .lazy .T = 11325440 := by
  decide

/-! ### R6 (`[R3-layer-*]`): the measured A-quantization pass, 4 per layer -/
theorem T3r_quant : quantNs dense 1 .fixed = 174800 ∧ quantNs moe 1 .fixed = 174800 ∧
    dense.nL * quantNs dense 1 .fixed = 20976000 ∧ moe.nL * quantNs moe 1 .fixed = 4894400 ∧
    ms2 20976000 = 2097 ∧ ms2 4894400 = 489 ∧
    quantNs dense 1 .prop = 568100 ∧ quantNs dense 4 .prop = 2185000 ∧ quantNs dense 16 .prop = 8740000 ∧
    quantNs moe 1 .prop = 262200 ∧ quantNs moe 4 .prop = 961400 ∧ quantNs moe 16 .prop = 3845600 ∧
    quantNs dense 16 .fixed = 174800 := by decide
/-! ### R7 (`[R3-step]`): the §3.5.2 table, all 31 rows — T_step (ns), parts (hundredths of ms), tokens/s/card, binding.
    Binding: `bindsW3` = the weight stream is strictly the largest additive term; `bindsA3` = attention is; MEM = ¬feasible
    (feasibility is round 2's memory model, unchanged: no round-3 term enters it — R27). -/
theorem T3r_step_dense_4k :
    step3 dense 4096 1 1 br3 lam3 = 2303945309 ∧
    ms2 (W3 dense 1 1 br3) = 220287 ∧
    ms2 (A3 dense 4096 1 1 br3) = 1415 ∧
    ms2 (Ln3 dense 1 1 br3) = 6570 ∧
    ms2 (Q3 dense 1 1 br3) = 2097 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    tpsCard 1000 (step3 dense 4096 1 1 br3 lam3) = 108 ∧
    bindsW3 dense 4096 1 1 br3 lam3 = true ∧
    step3 dense 4096 1 4 br3 lam3 = 2415418808 ∧
    ms2 (W3 dense 1 4 br3) = 220287 ∧
    ms2 (A3 dense 4096 1 4 br3) = 5911 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 4096 1 4 br3 lam3) = 262 ∧
    bindsW3 dense 4096 1 4 br3 lam3 = true ∧
    step3 dense 4096 1 4 br3Lazy lam3 = 2382811448 ∧
    ms2 (W3 dense 1 4 br3Lazy) = 220287 ∧
    ms2 (A3 dense 4096 1 4 br3Lazy) = 2650 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3Lazy lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 4096 1 4 br3Lazy lam3) = 265 ∧
    bindsW3 dense 4096 1 4 br3Lazy lam3 = true ∧
    step3 dense 4096 16 1 br3 lam3 = 2516911601 ∧
    ms2 (W3 dense 16 1 br3) = 220287 ∧
    ms2 (A3 dense 4096 16 1 br3) = 22650 ∧
    ms2 (X3 dense 16 1 lam3) = 85 ∧
    tpsCard 16000 (step3 dense 4096 16 1 br3 lam3) = 1589 ∧
    bindsW3 dense 4096 16 1 br3 lam3 = true := by decide
theorem T3r_step_dense_32k :
    step3 dense 32768 1 1 br3 lam3 = 2387232989 ∧
    ms2 (W3 dense 1 1 br3) = 220287 ∧
    ms2 (A3 dense 32768 1 1 br3) = 9744 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    tpsCard 1000 (step3 dense 32768 1 1 br3 lam3) = 104 ∧
    bindsW3 dense 32768 1 1 br3 lam3 = true ∧
    step3 dense 32768 1 4 br3 lam3 = 2783002808 ∧
    ms2 (W3 dense 1 4 br3) = 220287 ∧
    ms2 (A3 dense 32768 1 4 br3) = 42670 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 32768 1 4 br3 lam3) = 227 ∧
    bindsW3 dense 32768 1 4 br3 lam3 = true ∧
    step3 dense 32768 1 4 br3Lazy lam3 = 2547505208 ∧
    ms2 (W3 dense 1 4 br3Lazy) = 220287 ∧
    ms2 (A3 dense 32768 1 4 br3Lazy) = 19120 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3Lazy lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 32768 1 4 br3Lazy lam3) = 248 ∧
    bindsW3 dense 32768 1 4 br3Lazy lam3 = true ∧
    step3 dense 32768 16 1 br3 lam3 = 3849514481 ∧
    ms2 (W3 dense 16 1 br3) = 220287 ∧
    ms2 (A3 dense 32768 16 1 br3) = 155910 ∧
    ms2 (X3 dense 16 1 lam3) = 85 ∧
    tpsCard 16000 (step3 dense 32768 16 1 br3 lam3) = 1039 ∧
    bindsW3 dense 32768 16 1 br3 lam3 = true := by decide
theorem T3r_step_dense_128k :
    step3 dense 131072 1 1 br3 lam3 = 2672790749 ∧
    ms2 (W3 dense 1 1 br3) = 220287 ∧
    ms2 (A3 dense 131072 1 1 br3) = 38300 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    tpsCard 1000 (step3 dense 131072 1 1 br3 lam3) = 93 ∧
    bindsW3 dense 131072 1 1 br3 lam3 = true ∧
    step3 dense 131072 1 4 br3 lam3 = 4043290808 ∧
    ms2 (W3 dense 1 4 br3) = 220287 ∧
    ms2 (A3 dense 131072 1 4 br3) = 168698 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 131072 1 4 br3 lam3) = 156 ∧
    bindsW3 dense 131072 1 4 br3 lam3 = true ∧
    step3 dense 131072 1 4 br3Lazy lam3 = 3112169528 ∧
    ms2 (W3 dense 1 4 br3Lazy) = 220287 ∧
    ms2 (A3 dense 131072 1 4 br3Lazy) = 75586 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3Lazy lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 131072 1 4 br3Lazy lam3) = 203 ∧
    bindsW3 dense 131072 1 4 br3Lazy lam3 = true ∧
    step3 dense 131072 16 1 br3 lam3 = 8418438641 ∧
    ms2 (W3 dense 16 1 br3) = 220287 ∧
    ms2 (A3 dense 131072 16 1 br3) = 612803 ∧
    ms2 (X3 dense 16 1 lam3) = 85 ∧
    ¬ feasible dense 131072 16 false oRt := by decide
theorem T3r_step_dense_1M :
    step3 dense 1048576 1 1 br3 lam3 = 5337996509 ∧
    ms2 (W3 dense 1 1 br3) = 220287 ∧
    ms2 (A3 dense 1048576 1 1 br3) = 304820 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    ¬ feasible dense 1048576 1 false oRt ∧
    step3 dense 1048576 1 1 br3I8 lam3 = 4571716829 ∧
    ms2 (W3 dense 1 1 br3I8) = 220287 ∧
    ms2 (A3 dense 1048576 1 1 br3I8) = 228192 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    tpsCard 1000 (step3 dense 1048576 1 1 br3I8 lam3) = 54 ∧
    bindsA3 dense 1048576 1 1 br3I8 lam3 = true ∧
    step3 dense 1048576 1 1 br3I8Lazy lam3 = 3814122749 ∧
    ms2 (W3 dense 1 1 br3I8Lazy) = 220287 ∧
    ms2 (A3 dense 1048576 1 1 br3I8Lazy) = 152433 ∧
    ms2 (X3 dense 1 1 lam3) = 23 ∧
    tpsCard 1000 (step3 dense 1048576 1 1 br3I8Lazy lam3) = 65 ∧
    bindsW3 dense 1048576 1 1 br3I8Lazy lam3 = true ∧
    step3 dense 1048576 1 4 br3 lam3 = 15805978808 ∧
    ms2 (W3 dense 1 4 br3) = 220287 ∧
    ms2 (A3 dense 1048576 1 4 br3) = 1344967 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    ¬ feasible dense 1048576 1 false oRt ∧
    step3 dense 1048576 1 4 br3Lazy lam3 = 8382369848 ∧
    ms2 (W3 dense 1 4 br3Lazy) = 220287 ∧
    ms2 (A3 dense 1048576 1 4 br3Lazy) = 602606 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3Lazy lam3) = 6638 ∧
    ¬ feasible dense 1048576 1 false oRt ∧
    step3 dense 1048576 1 4 br3I8 lam3 = 15805978808 ∧
    ms2 (W3 dense 1 4 br3I8) = 220287 ∧
    ms2 (A3 dense 1048576 1 4 br3I8) = 1344967 ∧
    ms2 (X3 dense 1 4 lam3) = 35 ∧
    ms2 (D3 4 br3I8 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 dense 1048576 1 4 br3I8 lam3) = 40 ∧
    bindsA3 dense 1048576 1 4 br3I8 lam3 = true ∧
    step3 dense 1048576 16 1 br3 lam3 = 51061730801 ∧
    ms2 (W3 dense 16 1 br3) = 220287 ∧
    ms2 (A3 dense 1048576 16 1 br3) = 4877132 ∧
    ms2 (X3 dense 16 1 lam3) = 85 ∧
    ¬ feasible dense 1048576 16 false oRt := by decide
theorem T3r_step_moe_4k :
    step3 moe 4096 1 1 br3 lam3 = 119260115 ∧
    ms2 (W3 moe 1 1 br3) = 9282 ∧
    ms2 (A3 moe 4096 1 1 br3) = 330 ∧
    ms2 (Ln3 moe 1 1 br3) = 1801 ∧
    ms2 (Q3 moe 1 1 br3) = 489 ∧
    ms2 (X3 moe 1 1 lam3) = 21 ∧
    tpsCard 1000 (step3 moe 4096 1 1 br3 lam3) = 2096 ∧
    bindsW3 moe 4096 1 1 br3 lam3 = true ∧
    step3 moe 4096 1 4 br3 lam3 = 433648419 ∧
    ms2 (W3 moe 1 4 br3) = 34075 ∧
    ms2 (A3 moe 4096 1 4 br3) = 330 ∧
    ms2 (X3 moe 1 4 lam3) = 29 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 moe 4096 1 4 br3 lam3) = 1460 ∧
    bindsW3 moe 4096 1 4 br3 lam3 = true ∧
    step3 moe 4096 16 1 br3 lam3 = 1408802259 ∧
    ms2 (W3 moe 16 1 br3) = 133245 ∧
    ms2 (A3 moe 4096 16 1 br3) = 5285 ∧
    ms2 (X3 moe 16 1 lam3) = 58 ∧
    tpsCard 16000 (step3 moe 4096 16 1 br3 lam3) = 2839 ∧
    bindsW3 moe 4096 16 1 br3 lam3 = true := by decide
theorem T3r_step_moe_32k :
    step3 moe 32768 1 1 br3 lam3 = 138693907 ∧
    ms2 (W3 moe 1 1 br3) = 9282 ∧
    ms2 (A3 moe 32768 1 1 br3) = 2273 ∧
    ms2 (X3 moe 1 1 lam3) = 21 ∧
    tpsCard 1000 (step3 moe 32768 1 1 br3 lam3) = 1802 ∧
    bindsW3 moe 32768 1 1 br3 lam3 = true ∧
    step3 moe 32768 1 4 br3 lam3 = 453082211 ∧
    ms2 (W3 moe 1 4 br3) = 34075 ∧
    ms2 (A3 moe 32768 1 4 br3) = 2273 ∧
    ms2 (X3 moe 1 4 lam3) = 29 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 moe 32768 1 4 br3 lam3) = 1397 ∧
    bindsW3 moe 32768 1 4 br3 lam3 = true ∧
    step3 moe 32768 16 1 br3 lam3 = 1719742931 ∧
    ms2 (W3 moe 16 1 br3) = 133245 ∧
    ms2 (A3 moe 32768 16 1 br3) = 36379 ∧
    ms2 (X3 moe 16 1 lam3) = 58 ∧
    tpsCard 16000 (step3 moe 32768 16 1 br3 lam3) = 2325 ∧
    bindsW3 moe 32768 16 1 br3 lam3 = true := by decide
theorem T3r_step_moe_128k :
    step3 moe 131072 1 1 br3 lam3 = 205324051 ∧
    ms2 (W3 moe 1 1 br3) = 9282 ∧
    ms2 (A3 moe 131072 1 1 br3) = 8936 ∧
    ms2 (X3 moe 1 1 lam3) = 21 ∧
    tpsCard 1000 (step3 moe 131072 1 1 br3 lam3) = 1217 ∧
    bindsW3 moe 131072 1 1 br3 lam3 = true ∧
    step3 moe 131072 1 4 br3 lam3 = 519712355 ∧
    ms2 (W3 moe 1 4 br3) = 34075 ∧
    ms2 (A3 moe 131072 1 4 br3) = 8936 ∧
    ms2 (X3 moe 1 4 lam3) = 29 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 moe 131072 1 4 br3 lam3) = 1218 ∧
    bindsW3 moe 131072 1 4 br3 lam3 = true ∧
    step3 moe 131072 16 1 br3 lam3 = 2785825235 ∧
    ms2 (W3 moe 16 1 br3) = 133245 ∧
    ms2 (A3 moe 131072 16 1 br3) = 142987 ∧
    ms2 (X3 moe 16 1 lam3) = 58 ∧
    ¬ feasible moe 131072 16 false oRt := by decide
theorem T3r_step_moe_1M :
    step3 moe 1048576 1 1 br3 lam3 = 827205395 ∧
    ms2 (W3 moe 1 1 br3) = 9282 ∧
    ms2 (A3 moe 1048576 1 1 br3) = 71124 ∧
    ms2 (X3 moe 1 1 lam3) = 21 ∧
    tpsCard 1000 (step3 moe 1048576 1 1 br3 lam3) = 302 ∧
    bindsA3 moe 1048576 1 1 br3 lam3 = true ∧
    step3 moe 1048576 1 4 br3 lam3 = 1141593699 ∧
    ms2 (W3 moe 1 4 br3) = 34075 ∧
    ms2 (A3 moe 1048576 1 4 br3) = 71124 ∧
    ms2 (X3 moe 1 4 lam3) = 29 ∧
    ms2 (D3 4 br3 lam3) = 6638 ∧
    tpsCard (tau 700 3) (step3 moe 1048576 1 4 br3 lam3) = 554 ∧
    bindsA3 moe 1048576 1 4 br3 lam3 = true ∧
    step3 moe 1048576 16 1 br3 lam3 = 12735926739 ∧
    ms2 (W3 moe 16 1 br3) = 133245 ∧
    ms2 (A3 moe 1048576 16 1 br3) = 1137997 ∧
    ms2 (X3 moe 16 1 lam3) = 58 ∧
    ¬ feasible moe 1048576 16 false oRt := by decide

/-! ### R8 (`[R3-moved-*]`): every round-2 step cell (a theorem of the round-2 model above) → its round-3 value; the headline moves -/
theorem T3r_moved_cells :
    stepNs dense 4096 1 1 br0 lamMid 0 = 2281604149 ∧ step3 dense 4096 1 1 br3 lam3 = 2303945309 ∧
    stepNs dense 4096 1 4 br0 lamMid 0 = 2336004208 ∧ step3 dense 4096 1 4 br3 lam3 = 2415418808 ∧
    stepNs dense 4096 16 1 br0 lamMid 0 = 2455181881 ∧ step3 dense 4096 16 1 br3 lam3 = 2516911601 ∧
    stepNs dense 32768 1 1 br0 lamMid 0 = 2362319269 ∧ step3 dense 32768 1 1 br3 lam3 = 2387232989 ∧
    stepNs dense 32768 1 4 br0 lamMid 0 = 2416719328 ∧ step3 dense 32768 1 4 br3 lam3 = 2783002808 ∧
    stepNs dense 32768 16 1 br0 lamMid 0 = 3746623921 ∧ step3 dense 32768 16 1 br3 lam3 = 3849514481 ∧
    stepNs dense 131072 1 1 br0 lamMid 0 = 2639056909 ∧ step3 dense 131072 1 1 br3 lam3 = 2672790749 ∧
    stepNs dense 131072 1 4 br0 lamMid 0 = 2693456968 ∧ step3 dense 131072 1 4 br3 lam3 = 4043290808 ∧
    stepNs dense 131072 16 1 br0 lamMid 0 = 8174425201 ∧ step3 dense 131072 16 1 br3 lam3 = 8418438641 ∧
    stepNs dense 1048576 1 1 br0 lamMid 0 = 5221940989 ∧ step3 dense 1048576 1 1 br3 lam3 = 5337996509 ∧
    stepNs dense 1048576 1 4 br0 lamMid 0 = 5276341048 ∧ step3 dense 1048576 1 4 br3 lam3 = 15805978808 ∧
    stepNs dense 1048576 16 1 br0 lamMid 0 = 49500570961 ∧ step3 dense 1048576 16 1 br3 lam3 = 51061730801 ∧
    stepNs dense 1048576 1 1 brI8 lamMid 0 = 3746007229 ∧ step3 dense 1048576 1 1 br3I8 lam3 = 4571716829 ∧
    stepNs dense 1048576 1 4 brI8 lamMid 0 = 3800407288 ∧ step3 dense 1048576 1 4 br3I8 lam3 = 15805978808 ∧
    stepNs moe 4096 1 1 br0 lamMid 0 = 115013791 ∧ step3 moe 4096 1 1 br3 lam3 = 119260115 ∧
    stepNs moe 4096 1 4 br0 lamMid 0 = 417289295 ∧ step3 moe 4096 1 4 br3 lam3 = 433648419 ∧
    stepNs moe 4096 16 1 br0 lamMid 0 = 1395365271 ∧ step3 moe 4096 16 1 br3 lam3 = 1408802259 ∧
    stepNs moe 32768 1 1 br0 lamMid 0 = 133847319 ∧ step3 moe 32768 1 1 br3 lam3 = 138693907 ∧
    stepNs moe 32768 1 4 br0 lamMid 0 = 436122823 ∧ step3 moe 32768 1 4 br3 lam3 = 453082211 ∧
    stepNs moe 32768 16 1 br0 lamMid 0 = 1696701747 ∧ step3 moe 32768 16 1 br3 lam3 = 1719742931 ∧
    stepNs moe 131072 1 1 br0 lamMid 0 = 198419435 ∧ step3 moe 131072 1 1 br3 lam3 = 205324051 ∧
    stepNs moe 131072 1 4 br0 lamMid 0 = 500694939 ∧ step3 moe 131072 1 4 br3 lam3 = 519712355 ∧
    stepNs moe 131072 16 1 br0 lamMid 0 = 2729855379 ∧ step3 moe 131072 16 1 br3 lam3 = 2785825235 ∧
    stepNs moe 1048576 1 1 br0 lamMid 0 = 801092387 ∧ step3 moe 1048576 1 1 br3 lam3 = 827205395 ∧
    stepNs moe 1048576 1 4 br0 lamMid 0 = 1103367891 ∧ step3 moe 1048576 1 4 br3 lam3 = 1141593699 ∧
    stepNs moe 1048576 16 1 br0 lamMid 0 = 12372622723 ∧ step3 moe 1048576 16 1 br3 lam3 = 12735926739 := by decide
/-- the moved headline cells in tenths of a percent (fleet.py `pcs`): dense t = 1 −0.9 %, MoE −3.4 %, dense spec −13.3 %, dense 1M
    KV-int8 −18.1 %, MoE 1M −3.2 %, dense 128k spec −33.6 %; the others −0.9 … −3.5 %; dense 1M spec on KV-int8 −75.9 % -/
theorem T3r_moved_pct : pcsDown 104 105 = 9 ∧ pcsDown 1802 1867 = 34 ∧ pcsDown 227 262 = 133 ∧ pcsDown 54 66 = 181 ∧ pcsDown 302 312 = 32 ∧ pcsDown 156 235 = 336 ∧ pcsDown 108 109 = 9 ∧ pcsDown 93 94 = 10 ∧ pcsDown 2096 2173 = 35 ∧ pcsDown 1217 1259 = 33 ∧ pcsDown 40 166 = 759 ∧ pcsDown 1039 1067 = 26 ∧ pcsDown 2325 2357 = 13 := by decide
/-! ### R9 (`[R3-branch-*]`): every branch at 32k toggled one at a time, and the whole λ bracket at once -/
theorem T3r_branches_dense :
    step3 dense 32768 1 1 br3 lam3 = 2387232989 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3 lam3) = 104 ∧
    step3 dense 32768 1 1 (br3G gShuf64) lam3 = 2388484829 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3G gShuf64) lam3) = 104 ∧
    step3 dense 32768 1 1 (br3G gSeq64) lam3 = 2387348189 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3G gSeq64) lam3) = 104 ∧
    step3 dense 32768 1 1 (br3G gShuf16) lam3 = 2396763869 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3G gShuf16) lam3) = 104 ∧
    step3 dense 32768 1 1 (br3G gStream) lam3 = 2384291549 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3G gStream) lam3) = 104 ∧
    step3 dense 32768 1 1 (br3G g3x) lam3 = 2568780509 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3G g3x) lam3) = 97 ∧
    step3 dense 32768 1 1 br3Lazy lam3 = 2386333949 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3Lazy lam3) = 104 ∧
    step3 dense 32768 1 1 br3C lam3 = 2387847389 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3C lam3) = 104 ∧
    step3 dense 32768 1 1 br3 lamLo = 2387197789 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3 lamLo) = 104 ∧
    step3 dense 32768 1 1 br3 lamMid = 2388493789 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3 lamMid) = 104 ∧
    step3 dense 32768 1 1 br3 lamHi = 2395037789 ∧ tpsCard 1000 (step3 dense 32768 1 1 br3 lamHi) = 104 ∧
    step3 dense 32768 1 1 { br3 with launch := false } lam3 = 2321530989 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with launch := false } lam3) = 107 ∧
    step3 dense 32768 1 1 { br3 with cq := .none } lam3 = 2366256989 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with cq := .none } lam3) = 105 ∧
    step3 dense 32768 1 1 { br3 with cq := .prop } lam3 = 2434428989 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with cq := .prop } lam3) = 102 ∧
    step3 dense 32768 1 1 { br3 with integ := true } lam3 = 3022896357 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with integ := true } lam3) = 82 ∧
    step3 dense 32768 1 1 (br3Mega 2000) lam3 = 2335439549 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 2000) lam3) = 107 ∧
    step3 dense 32768 1 1 (br3Mega 5000) lam3 = 2336879549 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 5000) lam3) = 106 ∧
    step3 dense 32768 1 1 (br3Mega 20000) lam3 = 2344079549 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 20000) lam3) = 106 ∧
    step3 dense 32768 1 1 { br3 with G := gShuf16, conv := .C, integ := true, cq := .none } lamHi = 3019870437 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with G := gShuf16, conv := .C, integ := true, cq := .none } lamHi) = 82 ∧
    step3 dense 32768 1 1 { br3 with var := .lazy, launch := false, cq := .none } lamLo = 2299620749 ∧ tpsCard 1000 (step3 dense 32768 1 1 { br3 with var := .lazy, launch := false, cq := .none } lamLo) = 108 ∧
    pcsDown 82 104 = 211 ∧ pcsUp 108 104 = 38 := by decide
theorem T3r_branches_moe :
    step3 moe 32768 1 1 br3 lam3 = 138693907 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3 lam3) = 1802 ∧
    step3 moe 32768 1 1 (br3G gShuf64) lam3 = 138986003 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3G gShuf64) lam3) = 1798 ∧
    step3 moe 32768 1 1 (br3G gSeq64) lam3 = 138720787 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3G gSeq64) lam3) = 1802 ∧
    step3 moe 32768 1 1 (br3G gShuf16) lam3 = 140917779 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3G gShuf16) lam3) = 1774 ∧
    step3 moe 32768 1 1 (br3G gStream) lam3 = 138007571 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3G gStream) lam3) = 1811 ∧
    step3 moe 32768 1 1 (br3G g3x) lam3 = 181054995 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3G g3x) lam3) = 1380 ∧
    step3 moe 32768 1 1 br3Lazy lam3 = 138484131 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3Lazy lam3) = 1805 ∧
    step3 moe 32768 1 1 br3C lam3 = 138837267 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3C lam3) = 1800 ∧
    step3 moe 32768 1 1 br3 lamLo = 138658707 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3 lamLo) = 1802 ∧
    step3 moe 32768 1 1 br3 lamMid = 139954707 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3 lamMid) = 1786 ∧
    step3 moe 32768 1 1 br3 lamHi = 146498707 ∧ tpsCard 1000 (step3 moe 32768 1 1 br3 lamHi) = 1706 ∧
    step3 moe 32768 1 1 { br3 with launch := false } lam3 = 120675907 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with launch := false } lam3) = 2071 ∧
    step3 moe 32768 1 1 { br3 with cq := .none } lam3 = 133799507 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with cq := .none } lam3) = 1868 ∧
    step3 moe 32768 1 1 { br3 with cq := .prop } lam3 = 141141107 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with cq := .prop } lam3) = 1771 ∧
    step3 moe 32768 1 1 { br3 with integ := true } lam3 = 141503061 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with integ := true } lam3) = 1766 ∧
    step3 moe 32768 1 1 (br3Reg .directSer) lam3 = 122831347 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Reg .directSer) lam3) = 2035 ∧
    step3 moe 32768 1 1 (br3Reg .directOvl) lam3 = 120623827 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Reg .directOvl) lam3) = 2072 ∧
    step3 moe 32768 1 1 (br3Reg .pp) lam3 = 121246099 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Reg .pp) lam3) = 2061 ∧
    step3 moe 32768 1 1 (br3Fam .zipf15) lam3 = 138693907 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Fam .zipf15) lam3) = 1802 ∧
    step3 moe 32768 1 1 (br3Mega 2000) lam3 = 123793595 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 2000) lam3) = 2019 ∧
    step3 moe 32768 1 1 (br3Mega 5000) lam3 = 124213595 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 5000) lam3) = 2012 ∧
    step3 moe 32768 1 1 (br3Mega 20000) lam3 = 126313595 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 20000) lam3) = 1979 ∧
    step3 moe 32768 1 1 { br3 with G := gShuf16, conv := .C, integ := true, cq := .none } lamHi = 146780693 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with G := gShuf16, conv := .C, integ := true, cq := .none } lamHi) = 1703 ∧
    step3 moe 32768 1 1 { br3 with var := .lazy, launch := false, cq := .none, regime := .directOvl } lamLo = 97466451 ∧ tpsCard 1000 (step3 moe 32768 1 1 { br3 with var := .lazy, launch := false, cq := .none, regime := .directOvl } lamLo) = 2564 ∧
    pcsDown 1703 1802 = 54 ∧ pcsUp 2564 1802 = 422 := by decide
/-- the round-to-hundredths ratios §10 quotes (x100r a b = round(100·a/b)): quant reading 0.98× / 0.98×, the integrated reading 0.80×
    (dense), page size 1.00× / 0.98×, λ 1.00× / 0.95×, launch pipelining 1.03× / 1.15×, the MoE regime 1.13× (direct, A lift serialised;
    1.15× overlapped, 1.14× ping-pong), MoE 1M at 16 KiB 0.92×, dense 1M KV-int8 fixed-shift / as specified 1.20× -/
theorem T3r_branch_ratios : x100r 102 104 = 98 ∧ x100r 1771 1802 = 98 ∧ x100r 83 104 = 80 ∧ x100r 104 104 = 100 ∧ x100r 1774 1802 = 98 ∧
    x100r 1706 1802 = 95 ∧ x100r 107 104 = 103 ∧ x100r 2071 1802 = 115 ∧ x100r 2035 1802 = 113 ∧ x100r 2072 1802 = 115 ∧
    x100r 2061 1802 = 114 ∧ x100r 278 302 = 92 ∧ x100r 65 54 = 120 := by decide
theorem T3r_step_lambda_bracket (lam : Nat) (h1 : lamLo ≤ lam) (h2 : lam ≤ lamHi) :
    tpsCard 1000 (step3 dense 32768 1 1 br3 lam) = 104 ∧
    1706 ≤ tpsCard 1000 (step3 moe 32768 1 1 br3 lam) ∧ tpsCard 1000 (step3 moe 32768 1 1 br3 lam) ≤ 1802 := by
  have hl : lamLo = 10000 ∧ lamHi = 500000 := by decide
  rw [(T3r_step_lambda_form lam).1, (T3r_step_lambda_form lam).2]
  unfold tpsCard
  refine ⟨?_, ?_, ?_⟩
  · have a : 104 ≤ 1000 * 1000000000 / (4 * (2386996682 + 41107 + 16 * lam)) := by
      rw [Nat.le_div_iff_mul_le (by omega)]; omega
    have b : 1000 * 1000000000 / (4 * (2386996682 + 41107 + 16 * lam)) < 105 := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega
  · rw [Nat.le_div_iff_mul_le (by omega)]; omega
  · have b : 1000 * 1000000000 / (4 * (138474340 + 24367 + 16 * lam)) < 1803 := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega

/-! ### R10 (`[R3-B16-*]`): MoE B = 16 by routing family (D(16) = 128 / 68 / 45, EMPIRICAL — H9), anchored and direct path -/
theorem T3r_moe_families :
    dOf .uniform 16 = 128 ∧ step3 moe 32768 16 1 (br3Fam .uniform) lam3 = 1719742931 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3Fam .uniform) lam3) = 2325 ∧ ms2 (W3 moe 16 1 (br3Fam .uniform)) = 133245 ∧ step3 moe 32768 16 1 (br3FamReg .uniform .directSer) lam3 = 1465941971 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3FamReg .uniform .directSer) lam3) = 2728 ∧
    dOf .zipf10 16 = 68 ∧ step3 moe 32768 16 1 (br3Fam .zipf10) lam3 = 1099928771 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3Fam .zipf10) lam3) = 3636 ∧ ms2 (W3 moe 16 1 (br3Fam .zipf10)) = 71263 ∧ step3 moe 32768 16 1 (br3FamReg .zipf10 .directSer) lam3 = 965097011 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3FamReg .zipf10 .directSer) lam3) = 4144 ∧
    dOf .zipf15 16 = 45 ∧ step3 moe 32768 16 1 (br3Fam .zipf15) lam3 = 862333343 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3Fam .zipf15) lam3) = 4638 ∧ ms2 (W3 moe 16 1 (br3Fam .zipf15)) = 47504 ∧ step3 moe 32768 16 1 (br3FamReg .zipf15 .directSer) lam3 = 773106443 ∧ tpsCard 16000 (step3 moe 32768 16 1 (br3FamReg .zipf15 .directSer) lam3) = 5173 ∧
    ms2 (A3 moe 32768 16 1 br3) = 36379 ∧ pct (A3 moe 32768 16 1 br3) (step3 moe 32768 16 1 br3 lam3) = 212 ∧ ¬ feasible moe 1048576 16 false oRt := by decide

/-! ### R11 (`[R3-regime]`): the binding term per (shape, L, rows), its share and the attention share (tenths of a percent);
    the bounce share in hundredths (CORRECTED: ≤ 0.18 % — the MoE 4k cell — not "≤ 0.16 % everywhere"), quant and launch shares -/
theorem T3r_regime_dense_4k :
    bindsW3 dense 4096 1 1 br3 lam3 = true ∧ pct (W3 dense 1 1 br3) (step3 dense 4096 1 1 br3 lam3) = 956 ∧ pct (A3 dense 4096 1 1 br3) (step3 dense 4096 1 1 br3 lam3) = 6 ∧
    pctH (X3 dense 1 1 lam3) (step3 dense 4096 1 1 br3 lam3) = 1 ∧
    pct (Q3 dense 1 1 br3) (step3 dense 4096 1 1 br3 lam3) = 9 ∧ pct (Ln3 dense 1 1 br3) (step3 dense 4096 1 1 br3 lam3) = 29 ∧
    bindsW3 dense 4096 1 4 br3 lam3 = true ∧ pct (W3 dense 1 4 br3) (step3 dense 4096 1 4 br3 lam3) = 912 ∧ pct (A3 dense 4096 1 4 br3) (step3 dense 4096 1 4 br3 lam3) = 24 ∧
    pctH (X3 dense 1 4 lam3) (step3 dense 4096 1 4 br3 lam3) = 1 ∧
    bindsW3 dense 4096 16 1 br3 lam3 = true ∧ pct (W3 dense 16 1 br3) (step3 dense 4096 16 1 br3 lam3) = 875 ∧ pct (A3 dense 4096 16 1 br3) (step3 dense 4096 16 1 br3 lam3) = 90 ∧
    pctH (X3 dense 16 1 lam3) (step3 dense 4096 16 1 br3 lam3) = 3 := by decide
theorem T3r_regime_dense_32k :
    bindsW3 dense 32768 1 1 br3 lam3 = true ∧ pct (W3 dense 1 1 br3) (step3 dense 32768 1 1 br3 lam3) = 923 ∧ pct (A3 dense 32768 1 1 br3) (step3 dense 32768 1 1 br3 lam3) = 41 ∧
    pctH (X3 dense 1 1 lam3) (step3 dense 32768 1 1 br3 lam3) = 1 ∧
    pct (Q3 dense 1 1 br3) (step3 dense 32768 1 1 br3 lam3) = 9 ∧ pct (Ln3 dense 1 1 br3) (step3 dense 32768 1 1 br3 lam3) = 28 ∧
    bindsW3 dense 32768 1 4 br3 lam3 = true ∧ pct (W3 dense 1 4 br3) (step3 dense 32768 1 4 br3 lam3) = 792 ∧ pct (A3 dense 32768 1 4 br3) (step3 dense 32768 1 4 br3 lam3) = 153 ∧
    pctH (X3 dense 1 4 lam3) (step3 dense 32768 1 4 br3 lam3) = 1 ∧
    bindsW3 dense 32768 16 1 br3 lam3 = true ∧ pct (W3 dense 16 1 br3) (step3 dense 32768 16 1 br3 lam3) = 572 ∧ pct (A3 dense 32768 16 1 br3) (step3 dense 32768 16 1 br3 lam3) = 405 ∧
    pctH (X3 dense 16 1 lam3) (step3 dense 32768 16 1 br3 lam3) = 2 := by decide
theorem T3r_regime_dense_128k :
    bindsW3 dense 131072 1 1 br3 lam3 = true ∧ pct (W3 dense 1 1 br3) (step3 dense 131072 1 1 br3 lam3) = 824 ∧ pct (A3 dense 131072 1 1 br3) (step3 dense 131072 1 1 br3 lam3) = 143 ∧
    pctH (X3 dense 1 1 lam3) (step3 dense 131072 1 1 br3 lam3) = 1 ∧
    pct (Q3 dense 1 1 br3) (step3 dense 131072 1 1 br3 lam3) = 8 ∧ pct (Ln3 dense 1 1 br3) (step3 dense 131072 1 1 br3 lam3) = 25 ∧
    bindsW3 dense 131072 1 4 br3 lam3 = true ∧ pct (W3 dense 1 4 br3) (step3 dense 131072 1 4 br3 lam3) = 545 ∧ pct (A3 dense 131072 1 4 br3) (step3 dense 131072 1 4 br3 lam3) = 417 ∧
    pctH (X3 dense 1 4 lam3) (step3 dense 131072 1 4 br3 lam3) = 1 ∧
    ¬ feasible dense 131072 16 false oRt ∧ pct (A3 dense 131072 16 1 br3) (step3 dense 131072 16 1 br3 lam3) = 728 := by decide
theorem T3r_regime_dense_1M :
    ¬ feasible dense 1048576 1 false oRt ∧ pct (A3 dense 1048576 1 1 br3) (step3 dense 1048576 1 1 br3 lam3) = 571 ∧
    ¬ feasible dense 1048576 1 false oRt ∧ pct (A3 dense 1048576 1 4 br3) (step3 dense 1048576 1 4 br3 lam3) = 851 ∧
    ¬ feasible dense 1048576 16 false oRt ∧ pct (A3 dense 1048576 16 1 br3) (step3 dense 1048576 16 1 br3 lam3) = 955 ∧
    bindsA3 dense 1048576 1 1 br3I8 lam3 = true ∧ pct (A3 dense 1048576 1 1 br3I8) (step3 dense 1048576 1 1 br3I8 lam3) = 499 ∧ kv3 1048576 16 g256 true < vecT3 1048576 16 .rowmax .T ∧
    bindsA3 dense 1048576 1 4 br3I8 lam3 = true ∧ pct (A3 dense 1048576 1 4 br3I8) (step3 dense 1048576 1 4 br3I8 lam3) = 851 ∧
    bindsW3 dense 1048576 1 1 br3I8Lazy lam3 = true := by decide
theorem T3r_regime_moe_4k :
    bindsW3 moe 4096 1 1 br3 lam3 = true ∧ pct (W3 moe 1 1 br3) (step3 moe 4096 1 1 br3 lam3) = 778 ∧ pct (A3 moe 4096 1 1 br3) (step3 moe 4096 1 1 br3 lam3) = 28 ∧
    pctH (X3 moe 1 1 lam3) (step3 moe 4096 1 1 br3 lam3) = 18 ∧
    pct (Q3 moe 1 1 br3) (step3 moe 4096 1 1 br3 lam3) = 41 ∧ pct (Ln3 moe 1 1 br3) (step3 moe 4096 1 1 br3 lam3) = 151 ∧
    bindsW3 moe 4096 1 4 br3 lam3 = true ∧ pct (W3 moe 1 4 br3) (step3 moe 4096 1 4 br3 lam3) = 786 ∧ pct (A3 moe 4096 1 4 br3) (step3 moe 4096 1 4 br3 lam3) = 8 ∧
    pctH (X3 moe 1 4 lam3) (step3 moe 4096 1 4 br3 lam3) = 7 ∧
    bindsW3 moe 4096 16 1 br3 lam3 = true ∧ pct (W3 moe 16 1 br3) (step3 moe 4096 16 1 br3 lam3) = 946 ∧ pct (A3 moe 4096 16 1 br3) (step3 moe 4096 16 1 br3 lam3) = 38 ∧
    pctH (X3 moe 16 1 lam3) (step3 moe 4096 16 1 br3 lam3) = 4 := by decide
theorem T3r_regime_moe_32k :
    bindsW3 moe 32768 1 1 br3 lam3 = true ∧ pct (W3 moe 1 1 br3) (step3 moe 32768 1 1 br3 lam3) = 669 ∧ pct (A3 moe 32768 1 1 br3) (step3 moe 32768 1 1 br3 lam3) = 164 ∧
    pctH (X3 moe 1 1 lam3) (step3 moe 32768 1 1 br3 lam3) = 16 ∧
    pct (Q3 moe 1 1 br3) (step3 moe 32768 1 1 br3 lam3) = 35 ∧ pct (Ln3 moe 1 1 br3) (step3 moe 32768 1 1 br3 lam3) = 130 ∧
    bindsW3 moe 32768 1 4 br3 lam3 = true ∧ pct (W3 moe 1 4 br3) (step3 moe 32768 1 4 br3 lam3) = 752 ∧ pct (A3 moe 32768 1 4 br3) (step3 moe 32768 1 4 br3 lam3) = 50 ∧
    pctH (X3 moe 1 4 lam3) (step3 moe 32768 1 4 br3 lam3) = 6 ∧
    bindsW3 moe 32768 16 1 br3 lam3 = true ∧ pct (W3 moe 16 1 br3) (step3 moe 32768 16 1 br3 lam3) = 775 ∧ pct (A3 moe 32768 16 1 br3) (step3 moe 32768 16 1 br3 lam3) = 212 ∧
    pctH (X3 moe 16 1 lam3) (step3 moe 32768 16 1 br3 lam3) = 3 := by decide
theorem T3r_regime_moe_128k :
    bindsW3 moe 131072 1 1 br3 lam3 = true ∧ pct (W3 moe 1 1 br3) (step3 moe 131072 1 1 br3 lam3) = 452 ∧ pct (A3 moe 131072 1 1 br3) (step3 moe 131072 1 1 br3 lam3) = 435 ∧
    pctH (X3 moe 1 1 lam3) (step3 moe 131072 1 1 br3 lam3) = 11 ∧
    pct (Q3 moe 1 1 br3) (step3 moe 131072 1 1 br3 lam3) = 24 ∧ pct (Ln3 moe 1 1 br3) (step3 moe 131072 1 1 br3 lam3) = 88 ∧
    bindsW3 moe 131072 1 4 br3 lam3 = true ∧ pct (W3 moe 1 4 br3) (step3 moe 131072 1 4 br3 lam3) = 656 ∧ pct (A3 moe 131072 1 4 br3) (step3 moe 131072 1 4 br3 lam3) = 172 ∧
    pctH (X3 moe 1 4 lam3) (step3 moe 131072 1 4 br3 lam3) = 6 ∧
    ¬ feasible moe 131072 16 false oRt ∧ pct (A3 moe 131072 16 1 br3) (step3 moe 131072 16 1 br3 lam3) = 513 := by decide
theorem T3r_regime_moe_1M :
    bindsA3 moe 1048576 1 1 br3 lam3 = true ∧ pct (A3 moe 1048576 1 1 br3) (step3 moe 1048576 1 1 br3 lam3) = 860 ∧
    pctH (X3 moe 1 1 lam3) (step3 moe 1048576 1 1 br3 lam3) = 3 ∧
    pct (Q3 moe 1 1 br3) (step3 moe 1048576 1 1 br3 lam3) = 6 ∧ pct (Ln3 moe 1 1 br3) (step3 moe 1048576 1 1 br3 lam3) = 22 ∧
    bindsA3 moe 1048576 1 4 br3 lam3 = true ∧ pct (A3 moe 1048576 1 4 br3) (step3 moe 1048576 1 4 br3 lam3) = 623 ∧
    pctH (X3 moe 1 4 lam3) (step3 moe 1048576 1 4 br3 lam3) = 3 ∧
    ¬ feasible moe 1048576 16 false oRt ∧ pct (A3 moe 1048576 16 1 br3) (step3 moe 1048576 16 1 br3 lam3) = 894 ∧
    vecT3 1048576 4 .rowmax .T < kv3 1048576 4 g256 false := by decide
/-- the bounce share over the whole 24-cell map: at most 0.18 % (MoE 4k t = 1), 0.16 % at MoE 32k; dense ≤ 0.03 % -/
theorem T3r_bounce_share_max : pctH (X3 moe 1 1 lam3) (step3 moe 4096 1 1 br3 lam3) = 18 ∧ pctH (X3 moe 1 1 lam3) (step3 moe 32768 1 1 br3 lam3) = 16 ∧
    pctH (X3 dense 16 1 lam3) (step3 dense 4096 16 1 br3 lam3) = 3 ∧ 16 < 18 := by decide
/-! ### R12 (`[R3-Lkv-*]`): the KV crossover on the block model as an iff over EVERY L.
    CORRECTION (prover-forced): fleet.py's `Lstar_kv3` claims "smallest L … exact over every L" and checks only L* and L* − 16. The
    t = 1 attention is nb(L)·blk + fixed + tail(L mod 16) with a vector tail of up to 3 896 ns (15 tokens), so it is NOT monotone in
    L: in 13 of the 40 cells some lengths in the block just below L* are already attention-bound (every L ≡ τ…15 mod 16 in
    [L* − 512, L* − 1]). L* is the length from which EVERY longer context is attention-bound; the first attention-bound length is
    L* − 512 + τ. Design-relevant: MoE anchored at 256 KiB is first attention-bound at 131 103 (τ = 15; L* = 131 600) — 128k = 131 072
    stays weights-bound (tail 0); dense KV-int8 at 1 006 102 (τ = 6; L* = 1 006 608). Every design cell (L a multiple of 16) is unchanged. -/
theorem T3r_nb1 (L : Nat) : nblocks L 1 = (16 * (L / 16) + 511) / 512 := by
  unfold nblocks lMatrix ceilDiv
  rw [show blockOf 1 = 512 from rfl]
  omega
theorem T3r_tail1 (L : Nat) : tailOps L 1 * unitF32 .T * 10 / (rVecCore * 100) = (L % 16) * 8192 * 137 * 10 / 43200 := by
  unfold tailOps rVecCore; rw [show unitF32 .T = 137 from rfl]; omega
theorem T3r_Lstar_dense_p256k_anchor_rowmax (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g256 .rowmax .T false ↔ 753168 ≤ L := by
  rw [T3r_attn_mt1 L 16 g256 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_p256k_anchor_lazy (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g256 .lazy .T false ↔ (753680 ≤ L ∨ (753168 ≤ L ∧ 7 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 g256 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_p256k_anchor_rowmax_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g256 .rowmax .T true ↔ (1006608 ≤ L ∨ (1006096 ≤ L ∧ 6 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 g256 .rowmax .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_p256k_anchor_lazy_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g256 .lazy .T true ↔ (1507344 ≤ L ∨ (1506832 ≤ L ∧ 7 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 g256 .lazy .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf64k_anchor_rowmax (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf64 .rowmax .T false ↔ 743440 ≤ L := by
  rw [T3r_attn_mt1 L 16 gShuf64 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf64k_anchor_lazy (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf64 .lazy .T false ↔ (743952 ≤ L ∨ (743440 ≤ L ∧ 2 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf64 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf64k_anchor_rowmax_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf64 .rowmax .T true ↔ (1006608 ≤ L ∨ (1006096 ≤ L ∧ 6 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf64 .rowmax .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf64k_anchor_lazy_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf64 .lazy .T true ↔ (1487888 ≤ L ∨ (1487376 ≤ L ∧ 2 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf64 .lazy .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf16k_anchor_rowmax (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf16 .rowmax .T false ↔ 684560 ≤ L := by
  rw [T3r_attn_mt1 L 16 gShuf16 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf16k_anchor_lazy (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf16 .lazy .T false ↔ (685072 ≤ L ∨ (684560 ≤ L ∧ 8 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf16 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf16k_anchor_rowmax_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf16 .rowmax .T true ↔ (1006608 ≤ L ∨ (1006096 ≤ L ∧ 6 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf16 .rowmax .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_shuf16k_anchor_lazy_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gShuf16 .lazy .T true ↔ (1370128 ≤ L ∨ (1369616 ≤ L ∧ 8 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gShuf16 .lazy .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_stream174_anchor_rowmax (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gStream .rowmax .T false ↔ 777232 ≤ L := by
  rw [T3r_attn_mt1 L 16 gStream .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_stream174_anchor_lazy (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gStream .lazy .T false ↔ (777744 ≤ L ∨ (777232 ≤ L ∧ 4 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gStream .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_stream174_anchor_rowmax_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gStream .rowmax .T true ↔ (1006608 ≤ L ∨ (1006096 ≤ L ∧ 6 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gStream .rowmax .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_stream174_anchor_lazy_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 gStream .lazy .T true ↔ (1555472 ≤ L ∨ (1554960 ≤ L ∧ 4 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 16 gStream .lazy .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_gather3x_anchor_rowmax (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g3x .rowmax .T false ↔ 259088 ≤ L := by
  rw [T3r_attn_mt1 L 16 g3x .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_gather3x_anchor_lazy (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g3x .lazy .T false ↔ 259088 ≤ L := by
  rw [T3r_attn_mt1 L 16 g3x .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_gather3x_anchor_rowmax_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g3x .rowmax .T true ↔ 518160 ≤ L := by
  rw [T3r_attn_mt1 L 16 g3x .rowmax .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_dense_gather3x_anchor_lazy_i8 (L : Nat) : tw3 dense .anchor ≤ attn3 L 16 g3x .lazy .T true ↔ 518160 ≤ L := by
  rw [T3r_attn_mt1 L 16 g3x .lazy .T true (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 dense .anchor = 18256993 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if true = true then 2 else 1) = 2 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_p256k_anchor_rowmax (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 g256 .rowmax .T false ↔ (131600 ≤ L ∨ (131088 ≤ L ∧ 15 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 4 g256 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_p256k_directser_rowmax (L : Nat) : tw3 moe .directSer ≤ attn3 L 4 g256 .rowmax .T false ↔ 108048 ≤ L := by
  rw [T3r_attn_mt1 L 4 g256 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .directSer = 2641199 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_p256k_pp_rowmax (L : Nat) : tw3 moe .pp ≤ attn3 L 4 g256 .rowmax .T false ↔ (106000 ≤ L ∨ (105488 ≤ L ∧ 1 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 4 g256 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .pp = 2584583 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_p256k_anchor_lazy (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 g256 .lazy .T false ↔ 131600 ≤ L := by
  rw [T3r_attn_mt1 L 4 g256 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock g256 1 = 12394 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf64k_anchor_rowmax (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gShuf64 .rowmax .T false ↔ 129552 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf64 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf64k_directser_rowmax (L : Nat) : tw3 moe .directSer ≤ attn3 L 4 gShuf64 .rowmax .T false ↔ 106512 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf64 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .directSer = 2641199 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf64k_pp_rowmax (L : Nat) : tw3 moe .pp ≤ attn3 L 4 gShuf64 .rowmax .T false ↔ 104464 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf64 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .pp = 2584583 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf64k_anchor_lazy (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gShuf64 .lazy .T false ↔ 130064 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf64 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gShuf64 1 = 12557 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf16k_anchor_rowmax (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gShuf16 .rowmax .T false ↔ 119312 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf16 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf16k_directser_rowmax (L : Nat) : tw3 moe .directSer ≤ attn3 L 4 gShuf16 .rowmax .T false ↔ 98320 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf16 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .directSer = 2641199 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf16k_pp_rowmax (L : Nat) : tw3 moe .pp ≤ attn3 L 4 gShuf16 .rowmax .T false ↔ (96272 ≤ L ∨ (95760 ≤ L ∧ 10 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 4 gShuf16 .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .pp = 2584583 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_shuf16k_anchor_lazy (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gShuf16 .lazy .T false ↔ 119824 ≤ L := by
  rw [T3r_attn_mt1 L 4 gShuf16 .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gShuf16 1 = 13635 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_stream174_anchor_rowmax (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gStream .rowmax .T false ↔ 135696 ≤ L := by
  rw [T3r_attn_mt1 L 4 gStream .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_stream174_directser_rowmax (L : Nat) : tw3 moe .directSer ≤ attn3 L 4 gStream .rowmax .T false ↔ 111632 ≤ L := by
  rw [T3r_attn_mt1 L 4 gStream .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .directSer = 2641199 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_stream174_pp_rowmax (L : Nat) : tw3 moe .pp ≤ attn3 L 4 gStream .rowmax .T false ↔ 109072 ≤ L := by
  rw [T3r_attn_mt1 L 4 gStream .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .pp = 2584583 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_stream174_anchor_lazy (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 gStream .lazy .T false ↔ (136208 ≤ L ∨ (135696 ≤ L ∧ 6 ≤ L % 16)) := by
  rw [T3r_attn_mt1 L 4 gStream .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock gStream 1 = 12011 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_gather3x_anchor_rowmax (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 g3x .rowmax .T false ↔ 45072 ≤ L := by
  rw [T3r_attn_mt1 L 4 g3x .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_gather3x_directser_rowmax (L : Nat) : tw3 moe .directSer ≤ attn3 L 4 g3x .rowmax .T false ↔ 36880 ≤ L := by
  rw [T3r_attn_mt1 L 4 g3x .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .directSer = 2641199 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_gather3x_pp_rowmax (L : Nat) : tw3 moe .pp ≤ attn3 L 4 g3x .rowmax .T false ↔ 36368 ≤ L := by
  rw [T3r_attn_mt1 L 4 g3x .rowmax .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .pp = 2584583 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
theorem T3r_Lstar_moe_gather3x_anchor_lazy (L : Nat) : tw3 moe .anchor ≤ attn3 L 4 g3x .lazy .T false ↔ 45072 ≤ L := by
  rw [T3r_attn_mt1 L 4 g3x .lazy .T false (by decide) (by decide), T3r_nb1, T3r_tail1]
  have h : tw3 moe .anchor = 3207719 ∧ ddrBlock g3x 1 = 36033 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> intro h <;> omega
/-- the design-relevant L* cells of §4.3 / T5′ (the cells at L = 4k … 1M are unchanged by the correction) -/
theorem T3r_Lstar_kv : tw3 dense .anchor = 18256993 ∧ tw3 moe .anchor = 3207719 ∧ tw3 moe .directSer = 2641199 ∧ tw3 moe .pp = 2584583 ∧
    attn3 753168 16 g256 .rowmax .T false = 18262788 ∧ attn3 753152 16 g256 .rowmax .T false = 18250394 ∧
    attn3 131600 4 g256 .rowmax .T false = 3216472 ∧ attn3 131599 4 g256 .rowmax .T false = 3207974 ∧ attn3 131598 4 g256 .rowmax .T false = 3207715 ∧
    attn3 131103 4 g256 .rowmax .T false = 3207974 ∧ attn3 131072 4 g256 .rowmax .T false = 3191684 ∧
    attn3 1006608 16 g256 .rowmax .T true = 18264712 ∧ attn3 1006102 16 g256 .rowmax .T true = 18256994 ∧ attn3 1006101 16 g256 .rowmax .T true < 18256993 ∧
    131600 - 131072 = 528 ∧ 131103 - 131072 = 31 ∧ 131072 - 129552 = 1520 ∧ 1048576 - 1006608 = 41968 := by decide

/-! ### R13 (`[R3-Gstar-*]`): attention-bound iff G ≤ G* — over EVERY G > 0 (not only G ≤ 174.6): for G above ⌊20 971 520 / 9 276⌋ = 2 260
    the block is vector-bound, so the iff needs the per-block chain (9 276 ns) below the line ⌈(T_w − 18 820) / nb⌉.
    CORRECTION (prover-forced, as PROMPT-4P2 anticipated): at 1M the vector chain alone exceeds the weight time (2 048 · 9 276 + 18 820 =
    19 016 068 ≥ 18 256 993 dense, ≥ 3 207 719 / 2 641 199 / 2 584 583 MoE), so the printed "iff G ≤ 235.4 / 1 346.0 / 1 637.1 / 1 673.7"
    lines are false above them: the 1M cells are attention-bound at EVERY G (T3r_fleet_G_1M_everyG). -/
theorem T3r_attn_G_form (L rows G : Nat) (hr1 : 1 ≤ rows) (hr2 : rows ≤ 16) :
    attn3 L rows G .rowmax .T false = max (max (max (nblocks L 1 * (20971520 / G)) (nblocks L 1 * 9276)) (nblocks L 1 * 960)) (nblocks L 1 * 618)
      + (18820 + tailOps L 1 * unitF32 .T * 10 / (rVecCore * 100)) := by
  rw [T3r_attn_mt1 L rows G .rowmax .T false hr1 hr2]
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 = 20971520 / G := by unfold ddrBlock tn coreTok; rw [hbl]
  have h : vblk3 1 .rowmax .T = 9276 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧ drainBlock 1 (rDrainM 1) = 268 ∧
      (if false = true then 2 else 1) = 1 := by decide
  rw [hddr, h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2, Nat.div_one]
theorem T3r_fleet_G_dense_4k_anchor (G : Nat) (h1 : 0 < G) : tw3 dense .anchor ≤ attn3 4096 16 G .rowmax .T false ↔ G ≤ 9 := by
  rw [T3r_attn_G_form 4096 16 G (by decide) (by decide)]
  have h : tw3 dense .anchor = 18256993 ∧ nblocks 4096 1 = 8 ∧ tailOps 4096 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 2279772 ≤ 20971520 / G ↔ G ≤ 9 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_dense_32k_anchor (G : Nat) (h1 : 0 < G) : tw3 dense .anchor ≤ attn3 32768 16 G .rowmax .T false ↔ G ≤ 73 := by
  rw [T3r_attn_G_form 32768 16 G (by decide) (by decide)]
  have h : tw3 dense .anchor = 18256993 ∧ nblocks 32768 1 = 64 ∧ tailOps 32768 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 284972 ≤ 20971520 / G ↔ G ≤ 73 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_dense_128k_anchor (G : Nat) (h1 : 0 < G) : tw3 dense .anchor ≤ attn3 131072 16 G .rowmax .T false ↔ G ≤ 294 := by
  rw [T3r_attn_G_form 131072 16 G (by decide) (by decide)]
  have h : tw3 dense .anchor = 18256993 ∧ nblocks 131072 1 = 256 ∧ tailOps 131072 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 71243 ≤ 20971520 / G ↔ G ≤ 294 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_4k_anchor (G : Nat) (h1 : 0 < G) : tw3 moe .anchor ≤ attn3 4096 4 G .rowmax .T false ↔ G ≤ 52 := by
  rw [T3r_attn_G_form 4096 4 G (by decide) (by decide)]
  have h : tw3 moe .anchor = 3207719 ∧ nblocks 4096 1 = 8 ∧ tailOps 4096 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 398613 ≤ 20971520 / G ↔ G ≤ 52 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_4k_directser (G : Nat) (h1 : 0 < G) : tw3 moe .directSer ≤ attn3 4096 4 G .rowmax .T false ↔ G ≤ 63 := by
  rw [T3r_attn_G_form 4096 4 G (by decide) (by decide)]
  have h : tw3 moe .directSer = 2641199 ∧ nblocks 4096 1 = 8 ∧ tailOps 4096 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 327798 ≤ 20971520 / G ↔ G ≤ 63 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_4k_pp (G : Nat) (h1 : 0 < G) : tw3 moe .pp ≤ attn3 4096 4 G .rowmax .T false ↔ G ≤ 65 := by
  rw [T3r_attn_G_form 4096 4 G (by decide) (by decide)]
  have h : tw3 moe .pp = 2584583 ∧ nblocks 4096 1 = 8 ∧ tailOps 4096 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 320721 ≤ 20971520 / G ↔ G ≤ 65 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_32k_anchor (G : Nat) (h1 : 0 < G) : tw3 moe .anchor ≤ attn3 32768 4 G .rowmax .T false ↔ G ≤ 420 := by
  rw [T3r_attn_G_form 32768 4 G (by decide) (by decide)]
  have h : tw3 moe .anchor = 3207719 ∧ nblocks 32768 1 = 64 ∧ tailOps 32768 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 49827 ≤ 20971520 / G ↔ G ≤ 420 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_32k_directser (G : Nat) (h1 : 0 < G) : tw3 moe .directSer ≤ attn3 32768 4 G .rowmax .T false ↔ G ≤ 511 := by
  rw [T3r_attn_G_form 32768 4 G (by decide) (by decide)]
  have h : tw3 moe .directSer = 2641199 ∧ nblocks 32768 1 = 64 ∧ tailOps 32768 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 40975 ≤ 20971520 / G ↔ G ≤ 511 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_32k_pp (G : Nat) (h1 : 0 < G) : tw3 moe .pp ≤ attn3 32768 4 G .rowmax .T false ↔ G ≤ 523 := by
  rw [T3r_attn_G_form 32768 4 G (by decide) (by decide)]
  have h : tw3 moe .pp = 2584583 ∧ nblocks 32768 1 = 64 ∧ tailOps 32768 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 40091 ≤ 20971520 / G ↔ G ≤ 523 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_128k_anchor (G : Nat) (h1 : 0 < G) : tw3 moe .anchor ≤ attn3 131072 4 G .rowmax .T false ↔ G ≤ 1683 := by
  rw [T3r_attn_G_form 131072 4 G (by decide) (by decide)]
  have h : tw3 moe .anchor = 3207719 ∧ nblocks 131072 1 = 256 ∧ tailOps 131072 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 12457 ≤ 20971520 / G ↔ G ≤ 1683 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_128k_directser (G : Nat) (h1 : 0 < G) : tw3 moe .directSer ≤ attn3 131072 4 G .rowmax .T false ↔ G ≤ 2047 := by
  rw [T3r_attn_G_form 131072 4 G (by decide) (by decide)]
  have h : tw3 moe .directSer = 2641199 ∧ nblocks 131072 1 = 256 ∧ tailOps 131072 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 10244 ≤ 20971520 / G ↔ G ≤ 2047 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
theorem T3r_fleet_G_moe_128k_pp (G : Nat) (h1 : 0 < G) : tw3 moe .pp ≤ attn3 131072 4 G .rowmax .T false ↔ G ≤ 2092 := by
  rw [T3r_attn_G_form 131072 4 G (by decide) (by decide)]
  have h : tw3 moe .pp = 2584583 ∧ nblocks 131072 1 = 256 ∧ tailOps 131072 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2]
  have key : 10023 ≤ 20971520 / G ↔ G ≤ 2092 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
/-- CORRECTED STATEMENT: at 1M every fleet cell is attention-bound at EVERY G (no hypothesis on G at all) — the vector chain alone
    (2 048 blocks × 9 276 ns + 18 820) exceeds the dense, anchored, direct-path and ping-pong weight times -/
theorem T3r_fleet_G_1M_everyG (G : Nat) :
    tw3 dense .anchor ≤ attn3 1048576 16 G .rowmax .T false ∧ tw3 moe .anchor ≤ attn3 1048576 4 G .rowmax .T false ∧
    tw3 moe .directSer ≤ attn3 1048576 4 G .rowmax .T false ∧ tw3 moe .pp ≤ attn3 1048576 4 G .rowmax .T false := by
  rw [T3r_attn_G_form 1048576 16 G (by decide) (by decide), T3r_attn_G_form 1048576 4 G (by decide) (by decide)]
  have h : tw3 dense .anchor = 18256993 ∧ tw3 moe .anchor = 3207719 ∧ tw3 moe .directSer = 2641199 ∧ tw3 moe .pp = 2584583 ∧
      nblocks 1048576 1 = 2048 ∧ tailOps 1048576 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> omega
/-- …and the printed iff lines are FALSE as iffs over G > 0: at G one tenth above each printed G* the cell is still attention-bound -/
theorem T3r_fleet_G_1M_iff_false :
    tw3 dense .anchor ≤ attn3 1048576 16 2355 .rowmax .T false ∧ tw3 moe .anchor ≤ attn3 1048576 4 13461 .rowmax .T false ∧
    tw3 moe .directSer ≤ attn3 1048576 4 16372 .rowmax .T false ∧ tw3 moe .pp ≤ attn3 1048576 4 16738 .rowmax .T false ∧
    20971520 / 8906 = 2354 ∧ 20971520 / 1558 = 13460 ∧ 20971520 / 1281 = 16371 ∧ 20971520 / 1253 = 16737 ∧
    2048 * 9276 + 18820 = 19016068 := by decide
/-- the fixed-shift chain (E35, LICENSED) keeps a real G-line at dense 1M: 2 048 · 5 530 + 11 328 = 11 336 768 < 18 256 993 —
    attention-bound iff G ≤ 235.3 (every G ≤ 174.6, as before) -/
theorem T3r_fleet_G_dense_1M_lazy (G : Nat) (h1 : 0 < G) : tw3 dense .anchor ≤ attn3 1048576 16 G .lazy .T false ↔ G ≤ 2353 := by
  rw [T3r_attn_mt1 1048576 16 G .lazy .T false (by decide) (by decide)]
  have hbl : blockOf 1 = 512 := by decide
  have hddr : ddrBlock G 1 = 20971520 / G := by unfold ddrBlock tn coreTok; rw [hbl]
  have h : tw3 dense .anchor = 18256993 ∧ nblocks 1048576 1 = 2048 ∧ vblk3 1 .lazy .T = 5530 ∧ mmaBlock 1 = 960 ∧ loaderBlock 1 = 618 ∧
      drainBlock 1 (rDrainM 1) = 268 ∧ (if false = true then 2 else 1) = 1 ∧ tailOps 1048576 1 * unitF32 .T * 10 / (rVecCore * 100) = 0 := by decide
  rw [hddr, h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2.1, Nat.div_one, h.2.2.2.2.2.2.2]
  have key : 8910 ≤ 20971520 / G ↔ G ≤ 2353 := by rw [Nat.le_div_iff_mul_le h1]; omega
  constructor
  · intro h; exact key.mp (by omega)
  · intro h; have := key.mpr h; omega
/-- the MoE-128k cells of R13 (per layer, t = 1): anchored W by 16 µs (0.5 %) at 256 KiB, ATTN by 25.7 µs (0.8 %) at 64 KiB, by 301.7 µs
    (9.4 %) at 16 KiB; direct path ATTN at every page size (550.5 µs = 20.8 % at 256 KiB) -/
theorem T3r_moe_128k_cells :
    tw3 moe .anchor - attn3 131072 4 g256 .rowmax .T false = 16035 ∧ pct 16035 (tw3 moe .anchor) = 5 ∧
    attn3 131072 4 gShuf64 .rowmax .T false - tw3 moe .anchor = 25693 ∧ pct 25693 (tw3 moe .anchor) = 8 ∧
    attn3 131072 4 gShuf16 .rowmax .T false - tw3 moe .anchor = 301661 ∧ pct 301661 (tw3 moe .anchor) = 94 ∧
    tw3 moe .anchor - attn3 131072 4 gSeq64 .rowmax .T false = 12195 ∧ tw3 moe .anchor - attn3 131072 4 gStream .rowmax .T false = 114083 ∧
    attn3 131072 4 g256 .rowmax .T false - tw3 moe .directSer = 550485 ∧ pct 550485 (tw3 moe .directSer) = 208 ∧
    attn3 131072 4 gStream .rowmax .T false - tw3 moe .directSer = 452437 ∧ pct 452437 (tw3 moe .directSer) = 171 ∧
    usR 16035 = 16 ∧ usR 25693 = 26 ∧ usR 301661 = 302 ∧ usR 550485 = 550 := by decide

/-! ### R14 (`[R3-tstar-*]`): the softmax crossover — per block, vector ≥ KV from rows* = 16·mt* (L cancels), as an iff over every t ≤ 16 -/
def vecGeKv (g t : Nat) (v : Var) (c : Conv) (i8 : Bool) : Bool :=
  decide (ddrBlock g256 (mtPass (t * g)) / (if i8 then 2 else 1) ≤ vblk3 (mtPass (t * g)) v c)
theorem T3r_tstar_dense_rowmaxT :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .rowmax .T false = true ↔ 2 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .rowmax .T true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_dense_rowmaxC :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .rowmax .C false = true ↔ 2 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .rowmax .C true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_dense_lazyT :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .lazy .T false = true ↔ 3 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .lazy .T true = true ↔ 2 ≤ t)) := by decide
theorem T3r_tstar_dense_lazyC :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .lazy .C false = true ↔ 2 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 16 t .lazy .C true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_moe_rowmaxT :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .rowmax .T false = true ↔ 5 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .rowmax .T true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_moe_rowmaxC :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .rowmax .C false = true ↔ 5 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .rowmax .C true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_moe_lazyT :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .lazy .T false = true ↔ 9 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .lazy .T true = true ↔ 5 ≤ t)) := by decide
theorem T3r_tstar_moe_lazyC :
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .lazy .C false = true ↔ 5 ≤ t)) ∧
    (∀ t, t < 17 → 1 ≤ t → (vecGeKv 4 t .lazy .C true = true ↔ 1 ≤ t)) := by decide
theorem T3r_tstar_cells : vblk3 1 .rowmax .T = 9276 ∧ vblk3 2 .rowmax .T = 18552 ∧ ddrBlock g256 2 = 12394 ∧ vblk3 2 .lazy .T = 11061 ∧
    vblk3 3 .lazy .T = 9190 ∧ ddrBlock g256 3 = 6197 ∧ ddrBlock g256 1 / 2 = 6197 ∧ vblk3 1 .lazy .T = 5530 ∧ x10 9276 12394 = 7 := by decide

/-! ### R15 (`[R3-whatif-*]`): P2P, tensor-split, Π = 8 — each a bound or a decomposition with its premise explicit -/
/-- P2P at ANY rate: replacing the bounce by any cost x saves at most T_x (236 / 220 µs = 0.01 % / 0.16 %) -/
theorem T3r_p2p_bound (x : Nat) :
    step3 dense 32768 1 1 br3 lam3 - X3 dense 1 1 lam3 + x + X3 dense 1 1 lam3 = step3 dense 32768 1 1 br3 lam3 + x ∧
    step3 moe 32768 1 1 br3 lam3 - X3 moe 1 1 lam3 + x + X3 moe 1 1 lam3 = step3 moe 32768 1 1 br3 lam3 + x ∧
    X3 dense 1 1 lam3 = 236307 ∧ X3 moe 1 1 lam3 = 219567 ∧ usR 236307 = 236 ∧ usR 219567 = 220 := by
  have h : X3 dense 1 1 lam3 ≤ step3 dense 32768 1 1 br3 lam3 ∧ X3 moe 1 1 lam3 ≤ step3 moe 32768 1 1 br3 lam3 ∧
      X3 dense 1 1 lam3 = 236307 ∧ X3 moe 1 1 lam3 = 219567 ∧ usR 236307 = 236 ∧ usR 219567 = 220 := by decide
  refine ⟨by omega, by omega, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2⟩
/-- tensor-split (the runtime faults on it — a what-if): 382.32 ms = W/8 + ATTN/8 + lm_head/8 + launches + quant + 2·n_L host
    reductions of 34 µs (round 2: 191) → 0.653 (6.2×); MoE 39.24 → 6.369 (3.5×), reductions 27 µs (184); launch 17 % / 46 % of it -/
theorem T3r_tsplit : stepTs3 dense 32768 1 1 br3 lam3 = 382328080 ∧ stepTs3 moe 32768 1 1 br3 lam3 = 39247436 ∧
    dense.nL * gemmTs3 dense 1 .uniform .anchor = 273854880 ∧ dense.nL * (aSeq3 dense 32768 1 br3 / 8) = 12180480 ∧
    tn dense.wHead (8 * rGemm) = 1504400 ∧ dense.nL * 2 * tReduce lam3 1 dense.d = 8110320 ∧
    moe.nL * gemmTs3 moe 1 .uniform .anchor = 11618992 ∧ moe.nL * (aSeq3 moe 32768 1 br3 / 8) = 2842112 ∧
    tn moe.wHead (8 * rGemm) = 376100 ∧ moe.nL * 2 * tReduce lam3 1 moe.d = 1497832 ∧
    tReduce lam3 1 dense.d = 33793 ∧ usR 33793 = 34 ∧ usR (tReduce lamMid 1 dense.d) = 191 ∧
    tReduce lam3 1 moe.d = 26747 ∧ usR 26747 = 27 ∧ usR (tReduce lamMid 1 moe.d) = 184 ∧
    tpsCard 1000 382328080 = 653 ∧ tpsCard 1000 39247436 = 6369 ∧ x10 2387232989 382328080 = 62 ∧ x10 138693907 39247436 = 35 ∧
    pct 65702000 382328080 = 172 ∧ pct 20976000 382328080 = 55 ∧ pct 18018000 39247436 = 459 ∧ pct 4894400 39247436 = 125 := by decide
/-- Π = 8: the per-die blocks, Σ blocks + λ = T_step EXACTLY at the measured λ, the max block and the 7.7× / 7.1× cells -/
theorem T3r_pipelining_blocks :
    dieBlock3 dense 0 32768 1 1 br3 lam3 = 296861359 ∧ dieBlock3 dense 1 32768 1 1 br3 lam3 = 296874222 ∧
    dieBlock3 dense 2 32768 1 1 br3 lam3 = 296875916 ∧ dieBlock3 dense 7 32768 1 1 br3 lam3 = 309109016 ∧
    maxBlock3 dense 32768 br3 lam3 = 309109016 ∧
    dieBlock3 moe 0 32768 1 1 br3 lam3 = 19338851 ∧ dieBlock3 moe 1 32768 1 1 br3 lam3 = 14519661 ∧
    dieBlock3 moe 2 32768 1 1 br3 lam3 = 19351640 ∧ dieBlock3 moe 7 32768 1 1 br3 lam3 = 17728953 ∧
    maxBlock3 moe 32768 br3 lam3 = 19351640 ∧
    tpsFleet 1000 309109016 = 3235 ∧ tpsCard 1000 309109016 = 808 ∧ tpsFleet 1000 19351640 = 51675 ∧ tpsCard 1000 19351640 = 12918 ∧
    x10 2387232989 309109016 = 77 ∧ x10 138693907 19351640 = 71 ∧
    pct (8 * 309109016 - (2387232989 - lam3)) (8 * 309109016) = 35 ∧ pct (8 * 19351640 - (138693907 - lam3)) (8 * 19351640) = 104 := by
  decide
theorem T3r_pipelining_decomposition :
    step3 dense 32768 1 1 br3 lam3 = sumBlocks3 dense 32768 br3 lam3 + lam3 ∧
    step3 moe 32768 1 1 br3 lam3 = sumBlocks3 moe 32768 br3 lam3 + lam3 ∧
    step3 dense 32768 1 1 br3 lam3 ≤ 8 * maxBlock3 dense 32768 br3 lam3 + lam3 ∧
    step3 moe 32768 1 1 br3 lam3 ≤ 8 * maxBlock3 moe 32768 br3 lam3 + lam3 := by decide

/-! ### R16 (`[R3-mega-*]`): the per-layer megakernel pays iff c_sync ≤ 109 903 ns (dense; a TIE there, strict iff ≤ 109 902) /
    108 430 ns (MoE) — an iff over every c_sync (E31 measures it) -/
theorem T3r_mega_form (c : Nat) :
    step3 dense 32768 1 1 (br3Mega c) lam3 = 2334479549 + 480 * c ∧ step3 moe 32768 1 1 (br3Mega c) lam3 = 123513595 + 140 * c := by
  have hd : W3 dense 1 1 (br3Mega c) = W3 dense 1 1 br3 ∧ A3 dense 32768 1 1 (br3Mega c) = A3 dense 32768 1 1 br3 ∧
      Q3 dense 1 1 (br3Mega c) = Q3 dense 1 1 br3 ∧ D3 1 (br3Mega c) lam3 = 0 ∧
      W3 moe 1 1 (br3Mega c) = W3 moe 1 1 br3 ∧ A3 moe 32768 1 1 (br3Mega c) = A3 moe 32768 1 1 br3 ∧
      Q3 moe 1 1 (br3Mega c) = Q3 moe 1 1 br3 ∧ D3 1 (br3Mega c) lam3 = 0 :=
    ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have hL : Ln3 dense 1 1 (br3Mega c) = 11102000 + 120 * (4 * c + 15388) ∧ Ln3 moe 1 1 (br3Mega c) = 2730000 + 28 * (5 * c + 3846) :=
    ⟨rfl, rfl⟩
  have hk : W3 dense 1 1 br3 + A3 dense 32768 1 1 br3 + Q3 dense 1 1 br3 + X3 dense 1 1 lam3 = 2321530989 ∧
      W3 moe 1 1 br3 + A3 moe 32768 1 1 br3 + Q3 moe 1 1 br3 + X3 moe 1 1 lam3 = 120675907 := by decide
  unfold step3
  rw [hd.1, hd.2.1, hd.2.2.1, hd.2.2.2.1, hd.2.2.2.2.1, hd.2.2.2.2.2.1, hd.2.2.2.2.2.2.1, hL.1, hL.2]
  omega
theorem T3r_mega_threshold (c : Nat) :
    (step3 dense 32768 1 1 (br3Mega c) lam3 ≤ step3 dense 32768 1 1 br3 lam3 ↔ c ≤ 109903) ∧
    (step3 dense 32768 1 1 (br3Mega c) lam3 < step3 dense 32768 1 1 br3 lam3 ↔ c ≤ 109902) ∧
    (step3 moe 32768 1 1 (br3Mega c) lam3 ≤ step3 moe 32768 1 1 br3 lam3 ↔ c ≤ 108430) ∧
    (step3 moe 32768 1 1 (br3Mega c) lam3 < step3 moe 32768 1 1 br3 lam3 ↔ c ≤ 108430) := by
  rw [(T3r_mega_form c).1, (T3r_mega_form c).2]
  have h : step3 dense 32768 1 1 br3 lam3 = 2387232989 ∧ step3 moe 32768 1 1 br3 lam3 = 138693907 := by decide
  rw [h.1, h.2]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
theorem T3r_mega_cells : (dense.nlaunch - 1) * tLaunch = 455000 ∧ 2 * tn (redBytes 1 dense.d) rGemm = 15388 ∧ (455000 - 15388) / 4 = 109903 ∧
    (moe.nlaunch - 1) * tLaunch = 546000 ∧ 2 * tn (redBytes 1 moe.d) rGemm = 3846 ∧ (546000 - 3846) / 5 = 108430 ∧
    dense.nL * 455000 = 54600000 ∧ moe.nL * 546000 = 15288000 ∧ dense.nL * 15388 = 1846560 ∧ moe.nL * 3846 = 107688 ∧
    dense.nL * syncs dense = 480 ∧ moe.nL * syncs moe = 140 ∧ usR 109903 = 110 ∧ usR 108430 = 108 ∧
    tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 2000) lam3) = 107 ∧ tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 5000) lam3) = 106 ∧
    tpsCard 1000 (step3 dense 32768 1 1 (br3Mega 20000) lam3) = 106 ∧
    tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 2000) lam3) = 2019 ∧ tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 5000) lam3) = 2012 ∧
    tpsCard 1000 (step3 moe 32768 1 1 (br3Mega 20000) lam3) = 1979 ∧
    step3 moe 32768 1 1 { br3 with regime := .directSer, mega := some 5000 } lam3 = 108351035 ∧
    tpsCard 1000 108351035 = 2307 ∧ pcsUp 2307 1802 = 280 ∧ pcsUp 2012 1802 = 116 ∧ pcsUp 2019 1802 = 120 ∧ pcsUp 1979 1802 = 98 ∧
    pcsUp 107 104 = 28 ∧ pcsUp 106 104 = 19 := by decide

/-! ### R21 (`[R3-draft]`): the draft token and the verify step on the measured constants -/
theorem T3r_draft : tn draftW rGemm = 5727376 ∧ tn draftKv rGemm = 1153073 ∧ draftLaunch * tLaunch = 11011000 ∧
    24 * qPasses * cQ = 4195200 ∧ tn (128256 * 4) d2h0 = 18792 ∧ 2 * lam3 = 24400 ∧
    draft3Tok lam3 true .fixed none = 22129841 ∧ usR 22129841 = 22130 ∧
    draft3 lam3 true .fixed none 3 = 66389523 ∧ ms2 66389523 = 6638 ∧ ms2 (draft3 lam3 false .fixed none 3) = 3335 ∧
    ms2 (draft3 lam3 true .fixed (some 5000) 3) = 4134 ∧ ms2 (draft3 lam3 true .none none 3) = 5380 ∧
    pct (draftLaunch * tLaunch) 22129841 = 498 ∧ pct 4195200 22129841 = 190 ∧
    usR 5727376 = 5727 ∧ usR 1153073 = 1153 ∧ usR 4195200 = 4195 ∧ usR 18792 = 19 ∧ usR 24400 = 24 := by decide

/-! ### R22 (`[R3-spec-dense-*]`): dense spec decode — a gain for every α ≥ 0.144 (chain as specified) / 0.064 (fixed-shift), both
    directions; the cells and the best k -/
theorem T3r_spec_dense : step3 dense 32768 1 4 br3 lam3 = 2783002808 ∧ step3 dense 32768 1 1 br3 lam3 = 2387232989 ∧
    step3 dense 32768 1 4 br3Lazy lam3 = 2547505208 ∧ step3 dense 32768 1 1 br3Lazy lam3 = 2386333949 ∧
    tau 500 3 = 1875 ∧ tau 700 3 = 2533 ∧ tau 900 3 = 3439 ∧ tau 700 7 = 3139 ∧ tau 900 7 = 5693 ∧
    tpsCard (tau 500 3) 2783002808 = 168 ∧ tpsCard (tau 700 3) 2783002808 = 227 ∧ tpsCard (tau 900 3) 2783002808 = 308 ∧
    gainM 500 2387232989 2783002808 = 1608 ∧ gainM 700 2387232989 2783002808 = 2172 ∧ gainM 900 2387232989 2783002808 = 2949 ∧
    tpsCard (tau 500 3) 2547505208 = 184 ∧ tpsCard (tau 700 3) 2547505208 = 248 ∧ tpsCard (tau 900 3) 2547505208 = 337 ∧
    gainM 500 2386333949 2547505208 = 1756 ∧ gainM 700 2386333949 2547505208 = 2372 ∧ gainM 900 2386333949 2547505208 = 3221 ∧
    2783002808 * 10000 / 2387232989 = 11657 ∧ 2547505208 * 10000 / 2386333949 = 10675 ∧
    stepSpec3 dense 32768 3 br3 lam3 = step3 dense 32768 1 4 br3 lam3 ∧
    stepSpec3 dense 32768 7 br3 lam3 = 3291782626 ∧ tpsCard (tau 700 7) 3291782626 = 238 ∧ tpsCard (tau 900 7) 3291782626 = 432 ∧
    stepSpec3 dense 32768 7 br3Lazy lam3 = 2824410466 ∧ tpsCard (tau 700 7) 2824410466 = 277 ∧ tpsCard (tau 900 7) 2824410466 = 503 ∧
    pcsUp 238 227 = 48 ∧ passesOf (8 * 16) = 2 := by decide
theorem T3r_spec_dense_breakeven : (∀ a, a < 1001 → (1000 * 2783002808 < tau a 3 * 2387232989 ↔ 144 ≤ a)) ∧
    (∀ a, a < 1001 → (1000 * 2547505208 < tau a 3 * 2386333949 ↔ 64 ≤ a)) := by decide +kernel
theorem T3r_spec_dense_best_k : (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 700 k) (stepSpec3 dense 32768 k br3 lam3) ≤ 238) ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 900 k) (stepSpec3 dense 32768 k br3 lam3) ≤ 432) ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 500 k) (stepSpec3 dense 32768 k br3 lam3) ≤ 168) ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 700 k) (stepSpec3 dense 32768 k br3Lazy lam3) ≤ 277) := by decide

/-! ### R23 (`[R3-spec-moe-*]`): T_spec_moe_loss re-instantiated — the exact loss criterion τ(α,3)·T₁ < 1000·T₄ in BOTH directions
    for every α, per routing family and expert kernel; the tokens/s consequence; the mechanism bound -/
theorem T3r_spec_moe_steps : step3 moe 32768 1 1 br3 lam3 = 138693907 ∧ step3 moe 32768 1 4 br3 lam3 = 453082211 ∧
    step3 moe 32768 1 4 (br3Fam .zipf10) lam3 = 380770559 ∧ step3 moe 32768 1 4 (br3Fam .zipf15) lam3 = 329119379 ∧
    step3 moe 32768 1 1 (br3Reg .directSer) lam3 = 122831347 ∧ step3 moe 32768 1 4 (br3Reg .directSer) lam3 = 389631971 ∧
    step3 moe 32768 1 4 (br3FamReg .zipf10 .directSer) lam3 = 331200059 ∧ step3 moe 32768 1 4 (br3FamReg .zipf15 .directSer) lam3 = 289462979 ∧
    dOf .uniform 4 = 32 ∧ dOf .zipf10 4 = 25 ∧ dOf .zipf15 4 = 20 ∧
    453082211 * 10000 / 138693907 = 32667 ∧ 380770559 * 10000 / 138693907 = 27454 ∧ 329119379 * 10000 / 138693907 = 23729 ∧
    389631971 * 10000 / 122831347 = 31720 ∧ 331200059 * 10000 / 122831347 = 26963 ∧ 289462979 * 10000 / 122831347 = 23565 := by decide
theorem T3r_spec_moe_loss_exact : ∀ a, a < 1001 →
    ((tau a 3 * 138693907 < 1000 * 453082211 ↔ a ≤ 866) ∧ (tau a 3 * 138693907 < 1000 * 380770559 ↔ a ≤ 752) ∧
     (tau a 3 * 138693907 < 1000 * 329119379 ↔ a ≤ 657) ∧ (tau a 3 * 122831347 < 1000 * 389631971 ↔ a ≤ 847) ∧
     (tau a 3 * 122831347 < 1000 * 331200059 ↔ a ≤ 741) ∧ (tau a 3 * 122831347 < 1000 * 289462979 ↔ a ≤ 652)) := by decide +kernel
/-- the tokens/s/card consequence at the uniform anchored cell: every α ≤ 0.866 is below t = 1's 1.802 (0.866 gives 1.800), every
    α ≥ 0.867 above it (0.867 gives 1.803) -/
theorem T3r_spec_moe_loss_tps : ∀ a, a < 1001 →
    ((a ≤ 866 → tpsCard (tau a 3) 453082211 < 1802) ∧ (867 ≤ a → 1802 < tpsCard (tau a 3) 453082211)) := by decide +kernel
theorem T3r_spec_moe_cells : tpsCard (tau 866 3) 453082211 = 1800 ∧ tpsCard (tau 867 3) 453082211 = 1803 ∧
    tpsCard (tau 500 3) 453082211 = 1034 ∧ tpsCard (tau 700 3) 453082211 = 1397 ∧ tpsCard (tau 900 3) 453082211 = 1897 ∧
    tpsCard 1000 138693907 = 1802 ∧ tpsCard 1000 122831347 = 2035 ∧
    tpsCard (tau 700 3) 380770559 = 1663 ∧ tpsCard (tau 700 3) 329119379 = 1924 ∧
    tpsCard (tau 700 3) 389631971 = 1625 ∧ tpsCard (tau 700 3) 331200059 = 1911 ∧ tpsCard (tau 700 3) 289462979 = 2187 ∧
    tpsCard (tau 753 3) 380770559 = 1802 ∧ tpsCard (tau 658 3) 329119379 = 1803 ∧
    stepSpec3 moe 32768 1 br3 lam3 = 243490007 ∧ tpsCard (tau 700 1) 243490007 = 1745 ∧ tpsCard (tau 500 1) 243490007 = 1540 ∧
    tpsCard (tau 900 1) 243490007 = 1950 ∧
    (∀ k, k < 8 → 1 ≤ k → tpsCard (tau 700 k) (stepSpec3 moe 32768 k br3 lam3) ≤ 1745) := by decide
/-- the mechanism (before any draft cost): D(4) = 4·D(1) under uniform routing makes the t = 4 expert stream 4·E₁, E₁ = 82.64 ms
    = 59.6 % of T₁; T₄ ≥ 4·E₁ + (T₁ − E₁) = 386.62 ms, so every τ < 2.787 is a loss (round 2: 2.852) -/
theorem T3r_spec_moe_mechanism : dOf .uniform 4 = 4 * dOf .uniform 1 ∧
    moe.nL * (gemm3 moe 1 .uniform .anchor false - tn moe.wStream rGemm - 2 * fMoe) = 82641888 ∧
    W3 moe 1 4 br3 = W3 moe 1 1 br3 + 3 * 82641888 ∧ pct 82641888 138693907 = 596 ∧
    3 * 82641888 + 138693907 = 386619571 ∧ 386619571 ≤ step3 moe 32768 1 4 br3 lam3 ∧
    1000 + 3 * 82641888 * 1000 / 138693907 = 2787 ∧ ms2 82641888 = 8264 ∧ ms2 386619571 = 38661 := by decide

/-! ### R24 (`[R3-rollout-*]`): 1 → 2 → 4 cards; the scaling identity holds exactly at the measured λ -/
theorem T3r_rollout : prefix3 dense 2 4096 br3 lam3 = 572913661 ∧ prefix3 dense 2 32768 br3 lam3 = 593735581 ∧
    prefix3 dense 2 131072 br3 lam3 = 665125021 ∧ prefix3 dense 4 4096 br3 lam3 = 1145841879 ∧
    prefix3 dense 4 32768 br3 lam3 = 1187485719 ∧ prefix3 dense 4 131072 br3 lam3 = 1330264599 ∧
    prefix3 dense 8 4096 br3 lam3 = 2303933109 ∧ prefix3 dense 8 32768 br3 lam3 = 2387220789 ∧ prefix3 dense 8 131072 br3 lam3 = 2672778549 ∧
    prefix3 moe 2 4096 br3 lam3 = 29000064 ∧ prefix3 moe 2 32768 br3 lam3 = 33858512 ∧ prefix3 moe 2 131072 br3 lam3 = 50516048 ∧
    prefix3 moe 4 4096 br3 lam3 = 58012917 ∧ prefix3 moe 4 32768 br3 lam3 = 67729813 ∧ prefix3 moe 4 131072 br3 lam3 = 101044885 ∧
    prefix3 moe 8 4096 br3 lam3 = 119247915 ∧ prefix3 moe 8 32768 br3 lam3 = 138681707 ∧ prefix3 moe 8 131072 br3 lam3 = 205311851 := by
  decide
theorem T3r_rollout_identity :
    4 * prefix3 dense 2 32768 br3 lam3 + (headNs dense + 2 * tLaunch + 4 * lam3 + 3 * tn (act dense 1) h2d1
      + tn (logits dense 1) d2h0 - tn (act dense 1) d2h0) = step3 dense 32768 1 1 br3 lam3 ∧
    4 * prefix3 moe 2 32768 br3 lam3 + (headNs moe + 2 * tLaunch + 4 * lam3 + 3 * tn (act moe 1) h2d1
      + tn (logits moe 1) d2h0 - tn (act moe 1) d2h0) = step3 moe 32768 1 1 br3 lam3 ∧
    headNs dense + 2 * tLaunch + 4 * lam3 + 3 * tn (act dense 1) h2d1 + tn (logits dense 1) d2h0 - tn (act dense 1) d2h0 = 12290665 ∧
    headNs moe + 2 * tLaunch + 4 * lam3 + 3 * tn (act moe 1) h2d1 + tn (logits moe 1) d2h0 - tn (act moe 1) d2h0 = 3259859 ∧
    step3 dense 32768 1 1 br3 lam3 = prefix3 dense 8 32768 br3 lam3 + lam3 := by decide

/-! ### R25 (`[R3-ladder-*]`): the ladder's expected readings -/
theorem T3r_ladder : lam3 + tn 4096 h2d0 = 12348 ∧ lam3 + tn 4096 h2d1 = 12494 ∧ lam3 + tn (64 * KiB) h2d0 = 14574 ∧
    lam3 + tn (64 * KiB) h2d1 = 16914 ∧ lam3 + tn (64 * MiB) h2d0 = 2443680 ∧ lam3 + tn (64 * MiB) h2d1 = 4840175 ∧
    usR (tn (64 * KiB) h2d1) = 5 ∧ usR (tn MiB h2d1) = 75 ∧ usR (tn (16 * MiB) h2d1) = 1207 ∧
    step3 dense 32768 1 1 { br3 with cq := .prop } lam3 - step3 dense 32768 1 1 br3 lam3 = 47196000 ∧
    step3 moe 32768 1 1 { br3 with cq := .prop } lam3 - step3 moe 32768 1 1 br3 lam3 = 2447200 ∧
    ms2 47196000 = 4719 ∧ ms2 2447200 = 244 ∧ 2 * cQ = 87400 ∧ 7 * cQ = 305900 ∧
    tpsCard 1000 (step3 dense 32768 1 1 { br3 with cq := .prop } lam3) = 102 ∧
    tpsCard 1000 (step3 moe 32768 1 1 { br3 with cq := .prop } lam3) = 1771 := by decide

/-! ### R26 (`[R3-risk-*]`): the risk register's numbers -/
theorem T3r_fallbacks :
    step3 dense 32768 1 1 { br3 with integ := true, cq := .none } lam3 = 3001920357 ∧ tpsCard 1000 3001920357 = 83 ∧ pcsDown 83 104 = 201 ∧
    step3 moe 32768 1 1 { br3 with integ := true, cq := .none } lam3 = 136608661 ∧ tpsCard 1000 136608661 = 1830 ∧ pcsUp 1830 1802 = 15 ∧
    2387232989 - 2202874362 + 2202874362 * rGemm / rGemmSer = 2953414520 ∧ W3 dense 1 1 br3 = 2202874362 ∧ tpsCard 1000 2953414520 = 84 ∧
    step3 moe 131072 1 1 br3 lam3 = 205324051 ∧ tpsCard 1000 205324051 = 1217 ∧
    step3 moe 131072 1 1 (br3G gShuf64) lam3 = 206492435 ∧ tpsCard 1000 206492435 = 1210 ∧
    step3 moe 131072 1 1 (br3G gShuf16) lam3 = 214219539 ∧ tpsCard 1000 214219539 = 1167 ∧
    step3 moe 131072 1 1 (br3Reg .directSer) lam3 = 189461491 ∧ tpsCard 1000 189461491 = 1319 ∧
    step3 moe 131072 1 1 { br3 with G := gShuf64, regime := .directSer } lam3 = 190629875 ∧ tpsCard 1000 190629875 = 1311 ∧
    step3 moe 131072 1 1 { br3 with G := gShuf16, regime := .directSer } lam3 = 198356979 ∧ tpsCard 1000 198356979 = 1260 ∧
    step3 moe 1048576 1 1 br3 lam3 = 827205395 ∧ tpsCard 1000 827205395 = 302 ∧
    tpsCard 1000 (step3 moe 1048576 1 1 (br3G gShuf64) lam3) = 298 ∧ tpsCard 1000 (step3 moe 1048576 1 1 (br3G gShuf16) lam3) = 278 ∧
    step3 moe 1048576 1 1 (br3G g3x) lam3 = 2182760211 ∧ tpsCard 1000 2182760211 = 114 ∧ x10 302 114 = 26 ∧
    tpsCard 1000 (step3 moe 1048576 1 1 br3I8 lam3) = 385 ∧ tpsCard 1000 (step3 moe 1048576 1 1 br3I8Lazy lam3) = 530 ∧
    tpsCard 1000 (step3 dense 1048576 1 1 br3I8 lam3) = 54 ∧ tpsCard 1000 (step3 dense 1048576 1 1 br3I8Lazy lam3) = 65 ∧
    ms2 (A3 dense 1048576 1 1 br3I8) = 228192 ∧ ms2 (A3 dense 1048576 1 1 br3) = 304820 := by decide

/-! ### R17 (`[R3-inst-fit-*]`): the instance fit — the minimal int4 share x per die, an iff in x (weights(x) is non-increasing);
    the runtime overhead `ort` as a hypothesis variable (H8 / H11) -/
theorem T3r_inst_ort_add (s : Shape) (pos L B : Nat) (i8 : Bool) (ort x : Nat) :
    instTotal s pos L B i8 ort x = instTotal s pos L B i8 0 x + ort := by unfold instTotal; omega
/-- the per-die totals in closed form (x, L, ort free): MoE 7 layers per die, dense 30; embedding on position 0, lm_head on 3,
    the dense draft on 1 -/
theorem T3r_inst_form (L ort x : Nat) :
    instTotal moe 0 L 1 false ort x = 7 * (12926844928 - 12884901888 * x / 2000) + 525336576 + 0 + 0 + 7 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal moe 1 L 1 false ort x = 7 * (12926844928 - 12884901888 * x / 2000) + 0 + 0 + 0 + 7 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal moe 2 L 1 false ort x = 7 * (12926844928 - 12884901888 * x / 2000) + 0 + 0 + 0 + 7 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal moe 3 L 1 false ort x = 7 * (12926844928 - 12884901888 * x / 2000) + 0 + 525336576 + 0 + 7 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal dense 0 L 1 false ort x = 30 * (3187671040 - 3187671040 * x / 2000) + 2101346304 + 0 + 0 + 30 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal dense 1 L 1 false ort x = 30 * (3187671040 - 3187671040 * x / 2000) + 0 + 0 + (1000000000 + 201326592) + 30 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal dense 2 L 1 false ort x = 30 * (3187671040 - 3187671040 * x / 2000) + 0 + 0 + 0 + 30 * 4096 * L * 1 + 67108864 + ort ∧
    instTotal dense 3 L 1 false ort x = 30 * (3187671040 - 3187671040 * x / 2000) + 0 + 2101346304 + 0 + 30 * 4096 * L * 1 + 67108864 + ort :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
/-- the minimal x per die is an iff over every x ≤ 1000 at the assumed overhead (2 GiB + 64 MiB): MoE 32k 182 / 170 / 170 / 182 ‰ -/
theorem T3r_inst_fit_moe_32k (x : Nat) (hx : x ≤ 1000) :
    (instFits moe 0 32768 1 false oRt x ↔ 182 ≤ x) ∧ (instFits moe 1 32768 1 false oRt x ↔ 170 ≤ x) ∧
    (instFits moe 2 32768 1 false oRt x ↔ 170 ≤ x) ∧ (instFits moe 3 32768 1 false oRt x ↔ 182 ≤ x) := by
  have f := T3r_inst_form 32768 oRt x
  have ho : oRt = 2147483648 ∧ dieMem = 86000000000 := by decide
  unfold instFits; rw [f.1, f.2.1, f.2.2.1, f.2.2.2.1, ho.1, ho.2]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
theorem T3r_inst_fit_dense_32k (x : Nat) (hx : x ≤ 1000) :
    (instFits dense 0 32768 1 false oRt x ↔ 376 ≤ x) ∧ (instFits dense 1 32768 1 false oRt x ↔ 358 ≤ x) ∧
    (instFits dense 2 32768 1 false oRt x ↔ 332 ≤ x) ∧ (instFits dense 3 32768 1 false oRt x ↔ 376 ≤ x) := by
  have f := T3r_inst_form 32768 oRt x
  have ho : oRt = 2147483648 ∧ dieMem = 86000000000 := by decide
  unfold instFits; rw [f.2.2.2.2.1, f.2.2.2.2.2.1, f.2.2.2.2.2.2.1, f.2.2.2.2.2.2.2, ho.1, ho.2]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega
/-- the other cells of the §1.8 fit table, as minimality (fits at x, not at x − 1, die by die) -/
abbrev minimalAt (s : Shape) (L B : Nat) (xs : Nat → Nat) : Prop :=
  ∀ p, p < 4 → instFits s p L B false oRt (xs p) ∧ ¬ instFits s p L B false oRt (xs p - 1)
theorem T3r_inst_fit : minimalAt moe 4096 1 xsMoe4k ∧ minimalAt moe 32768 1 xsMoe32k ∧ minimalAt moe 131072 1 xsMoe128k ∧
    minimalAt moe 1048576 1 xsMoe1M ∧ minimalAt moe 32768 16 xsMoe32kB16 ∧ minimalAt dense 4096 1 xsDense4k ∧
    minimalAt dense 32768 1 xsDense32k ∧ minimalAt dense 131072 1 xsDense128k := by decide
/-- dense 1M cannot replicate at ANY x and ANY overhead: the KV alone is 128.8 GB (f16) per 4-die position; on KV-int8 64.4 GB of KV
    plus the all-int4 weights is still 112.0 GB > 86 -/
theorem T3r_inst_w_mono (s : Shape) (p x : Nat) (hx : x ≤ 1000) : instDieWeights s p 1000 ≤ instDieWeights s p x := by
  unfold instDieWeights
  have h1 : candBytes s * x / 2000 ≤ candBytes s * 1000 / 2000 := Nat.div_le_div_right (Nat.mul_le_mul_left _ hx)
  have h2 : layers4 s * (s.wRes - candBytes s * 1000 / 2000) ≤ layers4 s * (s.wRes - candBytes s * x / 2000) :=
    Nat.mul_le_mul_left _ (by omega)
  omega
theorem T3r_inst_dense_1M_infeasible (x ort : Nat) (hx : x ≤ 1000) (p : Nat) (hp : p < 4) :
    ¬ instFits dense p 1048576 1 false ort x ∧ ¬ instFits dense p 1048576 1 true ort x := by
  have hm := T3r_inst_w_mono dense p x hx
  have hd : ∀ q, q < 4 → dieMem < instTotal dense q 1048576 1 true 0 1000 := by decide
  have hq := hd p hp
  have hf : instDieKv dense 1048576 1 true ≤ instDieKv dense 1048576 1 false := by decide
  unfold instFits; unfold instTotal at hq ⊢
  constructor <;> omega
theorem T3r_inst_dense_1M_cells : instDieKv dense 1048576 1 false = 128849018880 ∧ instDieKv dense 1048576 1 true = 64424509440 ∧
    gb1 128849018880 = 1288 ∧ gb1 64424509440 = 644 ∧ instDieWeights dense 2 1000 = 47815065600 ∧
    gb1 (instTotal dense 2 1048576 1 true 0 1000) = 1123 := by decide

/-! ### T3r_instance_margin (PROMPT-4P2 target): the 2–30 MB fit margin per die and the 2.3 % / GB overhead sensitivity, with the
    runtime overhead `ort` as the hypothesis variable -/
/-- the worst-die margins of every replicable cell at the assumed 2 GiB: 1.9 MB (MoE 128k) … 30.1 MB (dense 4k) -/
theorem T3r_inst_margins :
    dieMem - instTotal moe 3 4096 1 false oRt 163 = 5552425 ∧ dieMem - instTotal moe 1 32768 1 false oRt 170 = 24485516 ∧
    dieMem - instTotal moe 1 131072 1 false oRt 232 = 1936941 ∧ dieMem - instTotal moe 3 1048576 1 false oRt 827 = 2733854 ∧
    dieMem - instTotal dense 1 4096 1 false oRt 284 = 30111826 ∧ dieMem - instTotal dense 2 32768 1 false oRt 332 = 3346208 ∧
    dieMem - instTotal dense 1 131072 1 false oRt 610 = 15012346 ∧
    dieMem - instTotal moe 0 32768 1 false oRt 182 = 40314817 ∧ dieMem - instTotal dense 0 32768 1 false oRt 376 = 5862794 ∧
    dieMem - instTotal dense 1 32768 1 false oRt 358 = 45211336 ∧
    gb1 (ws + oRt) = 22 ∧ 1936941 / 1000000 = 1 ∧ 30111826 / 1000000 = 30 := by decide
theorem T3r_instance_margin (ort : Nat) :
    -- (1) at the shipped minimal x the instance fits iff the real overhead is ≤ 2 GiB + the worst-die margin
    ((∀ p, p < 4 → instFits moe p 32768 1 false ort (xsMoe32k p)) ↔ ort ≤ 2147483648 + 24485516) ∧
    ((∀ p, p < 4 → instFits dense p 32768 1 false ort (xsDense32k p)) ↔ ort ≤ 2147483648 + 3346208) ∧
    -- (2) the sensitivity: every extra GB of overhead is absorbed by +23 ‰ of x (MoE) / +21 ‰ (dense), on every die, at every L, x
    (∀ L x, x + 23 ≤ 1000 → ∀ p, p < 4 → instFits moe p L 1 false ort x → instFits moe p L 1 false (ort + GB) (x + 23)) ∧
    (∀ L x, x + 21 ≤ 1000 → ∀ p, p < 4 → instFits dense p L 1 false ort x → instFits dense p L 1 false (ort + GB) (x + 21)) := by
  have c : instTotal moe 0 32768 1 false 0 182 = 83812201535 ∧ instTotal moe 1 32768 1 false 0 170 = 83828030836 ∧
      instTotal moe 2 32768 1 false 0 170 = 83828030836 ∧ instTotal moe 3 32768 1 false 0 182 = 83812201535 ∧
      instTotal dense 0 32768 1 false 0 376 = 83846653558 ∧ instTotal dense 1 32768 1 false 0 358 = 83807305016 ∧
      instTotal dense 2 32768 1 false 0 332 = 83849170144 ∧ instTotal dense 3 32768 1 false 0 376 = 83846653558 ∧
      dieMem = 86000000000 ∧ GB = 1000000000 := by decide
  refine ⟨?_, ?_, ?_, ?_⟩
  · constructor
    · intro h
      have h1 := h 1 (by decide)
      unfold instFits at h1; rw [T3r_inst_ort_add] at h1
      have e : xsMoe32k 1 = 170 := rfl
      rw [e] at h1; omega
    · intro h p hp
      unfold instFits; rw [T3r_inst_ort_add]
      have : p = 0 ∨ p = 1 ∨ p = 2 ∨ p = 3 := by omega
      rcases this with rfl | rfl | rfl | rfl
      · show instTotal moe 0 32768 1 false 0 182 + ort ≤ dieMem; omega
      · show instTotal moe 1 32768 1 false 0 170 + ort ≤ dieMem; omega
      · show instTotal moe 2 32768 1 false 0 170 + ort ≤ dieMem; omega
      · show instTotal moe 3 32768 1 false 0 182 + ort ≤ dieMem; omega
  · constructor
    · intro h
      have h1 := h 2 (by decide)
      unfold instFits at h1; rw [T3r_inst_ort_add] at h1
      have e : xsDense32k 2 = 332 := rfl
      rw [e] at h1; omega
    · intro h p hp
      unfold instFits; rw [T3r_inst_ort_add]
      have : p = 0 ∨ p = 1 ∨ p = 2 ∨ p = 3 := by omega
      rcases this with rfl | rfl | rfl | rfl
      · show instTotal dense 0 32768 1 false 0 376 + ort ≤ dieMem; omega
      · show instTotal dense 1 32768 1 false 0 358 + ort ≤ dieMem; omega
      · show instTotal dense 2 32768 1 false 0 332 + ort ≤ dieMem; omega
      · show instTotal dense 3 32768 1 false 0 376 + ort ≤ dieMem; omega
  · intro L x hx p hp
    unfold instFits
    have : p = 0 ∨ p = 1 ∨ p = 2 ∨ p = 3 := by omega
    rcases this with rfl | rfl | rfl | rfl
    · rw [(T3r_inst_form L ort x).1, (T3r_inst_form L (ort + GB) (x + 23)).1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.1, (T3r_inst_form L (ort + GB) (x + 23)).2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.2.1, (T3r_inst_form L (ort + GB) (x + 23)).2.2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.2.2.1, (T3r_inst_form L (ort + GB) (x + 23)).2.2.2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
  · intro L x hx p hp
    unfold instFits
    have : p = 0 ∨ p = 1 ∨ p = 2 ∨ p = 3 := by omega
    rcases this with rfl | rfl | rfl | rfl
    · rw [(T3r_inst_form L ort x).2.2.2.2.1, (T3r_inst_form L (ort + GB) (x + 21)).2.2.2.2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.2.2.2.2.1, (T3r_inst_form L (ort + GB) (x + 21)).2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.2.2.2.2.2.1, (T3r_inst_form L (ort + GB) (x + 21)).2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
    · rw [(T3r_inst_form L ort x).2.2.2.2.2.2.2, (T3r_inst_form L (ort + GB) (x + 21)).2.2.2.2.2.2.2, c.2.2.2.2.2.2.2.2.1, c.2.2.2.2.2.2.2.2.2]; intro h; omega
/-- the measured cells of the sensitivity: x at +1 GB / +3 GB of overhead (MoE 32k 204 / 192 / 192 / 204 and 248 / 236 / 236 / 248 —
    the minimal step is 22 ‰ per GB here, ≤ the 23 ‰ ceiling dx = ⌈2 000 · GB / (7 · expert bytes)⌉; dense 21 / 20 / 21 / 21 ≤ 21) -/
theorem T3r_inst_dx : ceilDiv (GB * 2000) (7 * (moe.wRes - moe.wStream)) = 23 ∧ ceilDiv (GB * 2000) (30 * dense.wStream) = 21 ∧
    instFits moe 1 32768 1 false (oRt + GB) 192 ∧ ¬ instFits moe 1 32768 1 false (oRt + GB) 191 ∧
    instFits moe 0 32768 1 false (oRt + GB) 204 ∧ ¬ instFits moe 0 32768 1 false (oRt + GB) 203 ∧
    instFits moe 1 32768 1 false (oRt + 3 * GB) 236 ∧ ¬ instFits moe 1 32768 1 false (oRt + 3 * GB) 235 ∧
    instFits moe 0 32768 1 false (oRt + 3 * GB) 248 ∧ ¬ instFits moe 0 32768 1 false (oRt + 3 * GB) 247 ∧
    instFits dense 0 32768 1 false (oRt + GB) 397 ∧ ¬ instFits dense 0 32768 1 false (oRt + GB) 396 ∧
    instFits dense 2 32768 1 false (oRt + GB) 353 ∧ ¬ instFits dense 2 32768 1 false (oRt + GB) 352 ∧
    instFits dense 0 32768 1 false (oRt + 3 * GB) 439 ∧ ¬ instFits dense 0 32768 1 false (oRt + 3 * GB) 438 := by decide

/-! ### R18 (`[R3-inst-*]`): the instance step and the fleet cell — fleet.py's cells at full concurrency (c = 2 000, two instances at
    solo speed), plus the H10 card-scale reading c = 1 990 -/
theorem T3r_inst_cells :
    instStep3 moe 32768 1 1 xsMoe32k .directSer tW4 0 .uniform br3 lam3 = 134376737 ∧ tpsInst 1000 2000 134376737 = 3720 ∧
    pcsUp 3720 1802 = 1064 ∧ 134376737 - 28 * 812036 - 198 * 91000 - 28 * 174800 - 118735 = 88608594 ∧ ms2 88608594 = 8860 ∧
    instStep3 moe 32768 1 1 xsMoe32k .anchor tW4 0 .uniform br3 lam3 = 147447501 ∧ tpsInst 1000 2000 147447501 = 3391 ∧ pcsUp 3391 1802 = 881 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directOvl tW4 0 .uniform br3 lam3 = 132557745 ∧ tpsInst 1000 2000 132557745 = 3771 ∧ pcsUp 3771 1802 = 1092 ∧
    instStep3 moe 4096 1 1 xsMoe4k .directSer tW4 0 .uniform br3 lam3 = 113718771 ∧ tpsInst 1000 2000 113718771 = 4396 ∧
    instStep3 moe 131072 1 1 xsMoe128k .directSer tW4 0 .uniform br3 lam3 = 205109539 ∧ tpsInst 1000 2000 205109539 = 2437 ∧
    instStep3 moe 1048576 1 1 xsMoe1M .directSer tW4 0 .uniform br3 lam3 = 865602155 ∧ tpsInst 1000 2000 865602155 = 577 ∧
    instStep3 moe 32768 16 1 xsMoe32kB16 .directSer tW4 0 .uniform br3 lam3 = 1982462339 ∧ tpsInst 16000 2000 1982462339 = 4035 ∧
    pcsUp 4035 2325 = 735 ∧
    instStep3 dense 32768 1 1 xsDense32k .directSer 0 rW4ovl .uniform br3 lam3 = 3223488193 ∧ tpsInst 1000 2000 3223488193 = 155 ∧
    pcsUp 155 104 = 490 ∧
    instStep3 dense 4096 1 1 xsDense4k .directSer 0 rW4ovl .uniform br3 lam3 = 2970259333 ∧ tpsInst 1000 2000 2970259333 = 168 ∧
    instStep3 dense 131072 1 1 xsDense128k .directSer 0 rW4ovl .uniform br3 lam3 = 4095430063 ∧ tpsInst 1000 2000 4095430063 = 122 ∧
    instStep3 dense 32768 1 4 xsDense32k .directSer 0 rW4ovl .uniform br3 lam3 = 3619219196 ∧ tpsInst (tau 700 3) 2000 3619219196 = 349 ∧
    instStep3 dense 32768 1 4 xsDense32k .directSer 0 rW4ovl .uniform br3Lazy lam3 = 3383721596 ∧ tpsInst (tau 700 3) 2000 3383721596 = 374 ∧
    pcsUp 349 227 = 537 ∧ pcsUp 374 248 = 508 ∧ pcsUp 168 108 = 555 ∧ pcsUp 122 93 = 311 ∧ pcsUp 4396 2096 = 1097 ∧
    pcsUp 2437 1217 = 1002 ∧ pcsUp 577 302 = 910 := by decide
/-- Zipf(1.0) popularity (EMPIRICAL — H9): the coldest 46 / 43 experts (x = 182 / 170 ‰) carry 3.2 % of the traffic; 4.006 -/
theorem T3r_inst_zipf : ncOf 182 = 46 ∧ ncOf 170 = 43 ∧ pct (hCold 46) hTot = 32 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer tW4 0 .zipf10 br3 lam3 = 124789523 ∧ tpsInst 1000 2000 124789523 = 4006 ∧
    pcsUp 4006 1802 = 1223 := by decide +kernel

/-! ### R19 (`[R3-inst-breakeven-moe-32k]`, `[R3-inst-sens-*]`): two instances beat one iff the int4 core-slab time ≤ 1 406 404 ns —
    an iff over every cold-tier time Tc AND, new in this round, over the H10 concurrency c (thousandths of one instance's throughput) -/
theorem T3r_inst_moe32k_form (Tc : Nat) :
    instStep3 moe 32768 1 1 xsMoe32k .directSer Tc 0 .uniform br3 lam3 =
      7 * (256223 + expCold 8 182 99374 Tc + 812036 + 637000 + 174800 + 0)
      + 7 * (256223 + expCold 8 170 99374 Tc + 812036 + 637000 + 174800 + 0)
      + 7 * (256223 + expCold 8 170 99374 Tc + 812036 + 637000 + 174800 + 0)
      + 7 * (256223 + expCold 8 182 99374 Tc + 812036 + 637000 + 174800 + 0)
      + 3008800 + 182000 + 118735 + 0 := rfl
/-- the generic H10 reading: two instances at concurrency c clear a one-instance cell of k thousandths iff k·4·T ≤ c·10⁹ -/
theorem T3r_h10_iff (k c T : Nat) (hT : 0 < T) : k ≤ tpsInst 1000 c T ↔ k * (4 * T) ≤ 1000 * c * 1000000 := by
  unfold tpsInst; exact Nat.le_div_iff_mul_le (by omega)
theorem T3r_inst_breakeven (Tc : Nat) :
    (1803 ≤ tpsInst 1000 2000 (instStep3 moe 32768 1 1 xsMoe32k .directSer Tc 0 .uniform br3 lam3) ↔ Tc ≤ 1406404) ∧
    (1803 ≤ tpsInst 1000 1990 (instStep3 moe 32768 1 1 xsMoe32k .directSer Tc 0 .uniform br3 lam3) ↔ Tc ≤ 1394680) := by
  rw [T3r_inst_moe32k_form]
  unfold expCold
  constructor
  · rw [T3r_h10_iff _ _ _ (by omega)]; constructor <;> intro h <;> omega
  · rw [T3r_h10_iff _ _ _ (by omega)]; constructor <;> intro h <;> omega
/-- at the MEASURED unpack (5.3 GB/s/core, Tc = 197 844 ns) the gain holds iff the fleet-scale concurrency c ≥ 0.970× of one instance
    (against the anchored 8-die chain, 1.802) and c ≥ 1.095× against the like-for-like direct-path chain (2.035): the card-scale H10
    measurement (1.99×) clears both — T3r_inst_gain_measured is the c-premise, the two-card inheritance is the open hypothesis -/
theorem T3r_inst_gain_measured (c : Nat) :
    (1803 ≤ tpsInst 1000 c 134376737 ↔ 970 ≤ c) ∧ (2036 ≤ tpsInst 1000 c 134376737 ↔ 1095 ≤ c) ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer tW4 0 .uniform br3 lam3 = 134376737 ∧ tW4 = 197844 ∧
    1406404 * 10 / tW4 = 71 ∧ 2 * MiB * 10 / (2 * 1406404) = 7 ∧ slabSer pieceSerC ≤ 1406404 ∧ slabSer pieceSerW ≤ 1406404 := by
  refine ⟨?_, ?_, by decide⟩
  · rw [T3r_h10_iff _ _ _ (by omega)]; constructor <;> intro h <;> omega
  · rw [T3r_h10_iff _ _ _ (by omega)]; constructor <;> intro h <;> omega
theorem T3r_inst_sens : instStep3 moe 32768 1 1 xsMoe32k .directSer (tn MiB 40) 0 .uniform br3 lam3 = 141981635 ∧ tpsInst 1000 2000 141981635 = 3521 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer (tn MiB 30) 0 .uniform br3 lam3 = 152316365 ∧ tpsInst 1000 2000 152316365 = 3282 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer (tn MiB 20) 0 .uniform br3 lam3 = 172985937 ∧ tpsInst 1000 2000 172985937 = 2890 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer (tn MiB 10) 0 .uniform br3 lam3 = 234994527 ∧ tpsInst 1000 2000 234994527 = 2127 ∧
    instStep3 moe 32768 1 1 xsAll .directSer tW4 0 .uniform br3 lam3 = 188902355 ∧ tpsInst 1000 2000 188902355 = 2646 ∧
    tpsInst 1000 2000 188902355 < tpsInst 1000 2000 134376737 := by decide

/-! ### H10 as a hypothesis variable — which cells ACTIVATE at the measured card-scale concurrency (1.99×) -/
/-- every variant-I cell at c = 1 990 (the card-scale measurement, under the two-card inheritance hypothesis) and the minimal c each
    needs to beat its one-instance comparator: MoE 32k 3.702 (c ≥ 970), dense 0.154 (c ≥ 1 354); B = 16 4.015; dense spec 0.348 /
    0.372; with the megakernel 4.149 / 0.156. All overlapped-tier cells activate; the serial-chain dense cells do NOT (T3r_serpiece) -/
theorem T3r_inst_h10 :
    tpsInst 1000 h10Card 134376737 = 3702 ∧ tpsInst 1000 h10Card 3223488193 = 154 ∧ tpsInst 16000 h10Card 1982462339 = 4015 ∧
    tpsInst (tau 700 3) h10Card 3619219196 = 348 ∧ tpsInst (tau 700 3) h10Card 3383721596 = 372 ∧
    tpsInst 1000 h10Card 113718771 = 4374 ∧ tpsInst 1000 h10Card 205109539 = 2425 ∧ tpsInst 1000 h10Card 865602155 = 574 ∧
    tpsInst 1000 h10Card 124789523 = 3986 ∧ tpsInst 1000 h10Card 2970259333 = 167 ∧ tpsInst 1000 h10Card 4095430063 = 121 ∧
    tpsInst 1000 h10Card 119896425 = 4149 ∧ tpsInst 1000 h10Card 3173134753 = 156 ∧
    (∀ c, 105 ≤ tpsInst 1000 c 3223488193 ↔ 1354 ≤ c) ∧ (∀ c, 1218 ≤ tpsInst 1000 c 205109539 ↔ 1000 ≤ c) ∧
    (∀ c, 303 ≤ tpsInst 1000 c 865602155 ↔ 1050 ≤ c) ∧ (∀ c, 109 ≤ tpsInst 1000 c 2970259333 ↔ 1296 ≤ c) ∧
    (∀ c, 94 ≤ tpsInst 1000 c 4095430063 ↔ 1540 ≤ c) ∧ (∀ c, 2326 ≤ tpsInst 16000 c 1982462339 ↔ 1153 ≤ c) := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide,
    by decide, by decide, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
  · intro c; unfold tpsInst; rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega

/-! ### R20 (`[R3-inst-combo-*]`): instances + megakernel; Π = 8 of one chain against the two-instance cell -/
theorem T3r_inst_vs_pipe :
    instStep3 moe 32768 1 1 xsMoe32k .directSer tW4 0 .uniform (br3Mega 5000) lam3 = 119896425 ∧ tpsInst 1000 2000 119896425 = 4170 ∧
    pcsUp 4170 1802 = 1314 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directOvl tW4 0 .uniform (br3Mega 5000) lam3 = 118077433 ∧ tpsInst 1000 2000 118077433 = 4234 ∧
    instStep3 dense 32768 1 1 xsDense32k .directSer 0 rW4ovl .uniform (br3Mega 5000) lam3 = 3173134753 ∧ tpsInst 1000 2000 3173134753 = 157 ∧
    pcsUp 157 104 = 509 ∧ tpsCard 1000 (maxBlock3 moe 32768 br3 lam3) = 12918 ∧ tpsCard 1000 (maxBlock3 dense 32768 br3 lam3) = 808 ∧
    x10 12918 3720 = 34 ∧ x10 808 155 = 52 ∧ tpsInst 1000 2000 134376737 * 4 = 14880 ∧ tpsCard 1000 138693907 * 4 = 7208 ∧
    x10 3720 1802 = 20 ∧ x100r 3720 1802 = 206 ∧ x100r 155 104 = 149 := by decide

/-! ### R8 (structural): the round-2 limit of the round-3 model reproduces the round-2 step EXACTLY, for every L, B, t and λ —
    round 3 changed λ, G, the attention term and c_q, nothing else: swap the attention term back and drop the quant pass -/
theorem T3r_round2_limit (L B t lam : Nat) :
    step3 dense L B t br3R2 lam - A3 dense L B t br3R2 + attnTot dense L B t br0 = stepNs dense L B t br0 lam 0 ∧
    step3 moe L B t br3R2 lam - A3 moe L B t br3R2 + attnTot moe L B t br0 = stepNs moe L B t br0 lam 0 := by
  have hd1a : W3 dense B t br3R2 = 120 * 18256993 + 120 * 18256993 * 0 / 1000 + 12035202 := rfl
  have g1 : gemmNs dense (B * t) br0.fam br0.regime 0 = gemmDenseNs dense 0 := by
    unfold gemmNs; rw [ite_eq_right (by decide)]
  have g2 : gemmDenseNs dense 0 = 18256993 ∧ headNs dense = 12035202 ∧ dense.nL = 120 := by decide
  have hd1b : wNs dense B t br0 0 = 120 * 18256993 + 12035202 := by unfold wNs; rw [g1, g2.1, g2.2.1, g2.2.2]
  have hm1 : W3 moe B t br3R2 = 28 * (240223 + 16000 + 3 * dOf .uniform (B * t) * 122979) + 3008800 := rfl
  have hm2 : wNs moe B t br0 0 = 28 * (240223 + (16000 + 3 * dOf .uniform (B * t) * 122979)) + 3008800 := rfl
  have hL : Ln3 dense B t br3R2 = launchNs dense br0.launch ∧ Ln3 moe B t br3R2 = launchNs moe br0.launch := ⟨rfl, rfl⟩
  have hQ : Q3 dense B t br3R2 = 0 ∧ Q3 moe B t br3R2 = 0 := ⟨rfl, rfl⟩
  have hX : X3 dense B t lam = xNs dense B t lam ∧ X3 moe B t lam = xNs moe B t lam := ⟨rfl, rfl⟩
  have hD : D3 t br3R2 lam = dNs t br0 lam := rfl
  unfold step3 stepNs
  rw [hd1a, hd1b, hm1, hm2, hL.1, hL.2, hQ.1, hQ.2, hX.1, hX.2, hD]
  constructor <;> omega

/-! ### R27 (`[R3-mem]`): no round-3 term enters the memory model — the round-2 theorems stand (the memory functions take no λ, G,
    c_q, chain or regime argument); the instance variant's fit is the separate R17 statement -/
theorem T3r_mem : (∀ ort, ¬ feasible dense 1048576 1 false ort) ∧ (∀ ort, feasible dense 1048576 1 true ort ↔ ort ≤ 3804224512) ∧
    Lmax dense 1 false oRt = 551253 ∧ Lmax moe 1 false oRt = 1925823 ∧ Lmax dense 1 true oRt = 1102506 ∧
    ¬ minDiesFits dense 4 ∧ minDiesFits dense 5 ∧ ¬ minDiesFits moe 4 ∧ minDiesFits moe 5 :=
  ⟨T_mem_infeas_dense_1M, T_mem_feas_kv_int8, T_Lmax.1, T_Lmax.2.2.2.2.1, T_Lmax.2.2.2.1, T_min_dies_heuristic⟩

/-! ## PROMPT-4P2 target — T3r_spec_dense_split: the 0.227 vs 0.248 pair as threshold theorems over the verify chain's cost.
    The dense verify step (k = 3, 32k) is affine in the per-block chain cost v once v ≥ the 6 197 ns DDR block (both chains are):
    T(v) = 2 356 342 808 + 15 600·v; the cell is ≥ 0.248 iff v ≤ 12 633 ns, ≥ 0.227 iff v ≤ 27 775, beats t = 1 (0.104) iff
    v ≤ 235 551. The chain as specified (27 350) clears 0.227 by 425 ns; the fixed-shift chain (12 254; E35 LICENSED for
    qk-normalised models) clears 0.248 by 379 ns. -/
theorem T3r_spec_dense_split_form (v : Nat) (hv : 6197 ≤ v) : specDenseV v = 2356342808 + 15600 * v := by
  have h : W3 dense 1 4 br3 + Ln3 dense 1 4 br3 + Q3 dense 1 4 br3 + X3 dense 1 4 lam3 + D3 4 br3 lam3 = 2356301528 ∧ dense.nL = 120 := by decide
  unfold specDenseV
  have hm : max (max (max 6197 v) 1920) 1236 = v := by omega
  rw [hm, h.2]
  omega
theorem T3r_spec_dense_split (v : Nat) (hv : 6197 ≤ v) :
    (248 ≤ tpsCard (tau 700 3) (specDenseV v) ↔ v ≤ 12633) ∧ (227 ≤ tpsCard (tau 700 3) (specDenseV v) ↔ v ≤ 27775) ∧
    (105 ≤ tpsCard (tau 700 3) (specDenseV v) ↔ v ≤ 235551) := by
  rw [T3r_spec_dense_split_form v hv]
  have ht : tau 700 3 = 2533 := by decide
  unfold tpsCard; rw [ht]
  refine ⟨?_, ?_, ?_⟩ <;> (rw [Nat.le_div_iff_mul_le (by omega)]; constructor <;> intro h <;> omega)
/-- the two measured chains are the two ends of the pair: specDenseV reproduces the §3.5.2 cells exactly -/
theorem T3r_spec_dense_split_cells : specDenseV (vblk3 4 .rowmax .T) = step3 dense 32768 1 4 br3 lam3 ∧
    specDenseV (vblk3 4 .lazy .T) = step3 dense 32768 1 4 br3Lazy lam3 ∧ vblk3 4 .rowmax .T = 27350 ∧ vblk3 4 .lazy .T = 12254 ∧
    mmaBlock 4 = 1920 ∧ loaderBlock 4 = 1236 ∧ drainBlock 4 (rDrainM 4) = 344 ∧ ddrBlock g256 4 = 6197 ∧ nblocks 32768 4 = 128 ∧
    tpsCard (tau 700 3) (specDenseV 27350) = 227 ∧ tpsCard (tau 700 3) (specDenseV 12254) = 248 ∧
    27775 - 27350 = 425 ∧ 12633 - 12254 = 379 ∧ tpsCard (tau 700 3) (specDenseV 12634) = 247 ∧
    tpsCard (tau 700 3) (specDenseV 27776) = 226 := by decide

/-! ## PROMPT-4P2 target — T3r_moe128k_tie, legs-conditional (DESIGN-3 round 4's P-fragment bounce, erratum #20).
    Per layer at 128k (t = 1, rows 4) the cell is attention-bound iff G ≤ the line for its bounce leg count:
      anchored kernel:      legs 0 → G ≤ 168.3 (the round-3 tie: weights-bound by 0.5 % at 169.2, attention-bound by 0.8 % at 167.0)
                            legs 1 → G ≤ 178.9     legs 2 → G ≤ 189.4     (both above the 174.6 ceiling: attention-bound at EVERY G)
      direct-path kernel:   legs 0 / 1 / 2 → G ≤ 204.7 / 217.5 / 230.3 (attention-bound at every G and every page size)
    THE LEG COUNT THE PLANNER MUST READ: legs = 2. Erratum #20 (measured) makes the vector-SRAM → S1 plain copy wrong, so P rides
    US → DDR scratch → DDR → S1: two transfers on the K/V stream's roof (DESIGN-3 round 4's headline, UNMEASURED until E24′). legs 0
    needs a proven direct route the erratum rules out as specified; and since legs 1 and legs 2 give the same verdict, the planner's
    reading does not hang on E24′ coming back 1 or 2 — only a legs-0 route would restore the round-3 tie. -/
theorem T3r_attn4_128k (G legs : Nat) :
    attn4 131072 1 4 G .lazy .T legs false =
      max (max (max (256 * ((262144 + legs * 16384) * 80 / G)) (256 * 4772)) (256 * 960)) (256 * 618) + 19328 := by
  have h : passesOf 4 = 1 ∧ mtPass 4 = 1 ∧ mtOf 4 = 1 ∧ nblocks4 131072 1 1 = 256 ∧ vec4 1 .lazy .T = 4772 ∧ mmaBlock 1 = 960 ∧
      loaderBlock 1 = 618 ∧ drain4 1 (rDrainM 1) = 428 ∧ tail4Ops 131072 1 1 = 16 * 8192 ∧ mask4 1 1 = 0 ∧ firstMaxOf 1 .lazy .T = 5200 ∧
      unitF32 .T = 137 ∧ rVecCore * 100 = 43200 := by decide
  have hd : ddr4Block G 1 legs false = (262144 + legs * 16384) * 80 / G := by
    unfold ddr4Block tn
    have e : (blockOf 1 * coreTok / (if false = true then 2 else 1) + legs * pBytes 1) * 8 * 10 = (262144 + legs * 16384) * 80 := by
      have e1 : blockOf 1 * coreTok / (if false = true then 2 else 1) = 262144 := by decide
      have e2 : pBytes 1 = 16384 := by decide
      rw [e1, e2]; omega
    rw [e]
  unfold attn4
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, hd, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.1,
    h.2.2.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.2.2.2.2]
  all_goals simp only [Nat.one_mul]
/-- the six legs-conditional lines, each an iff over EVERY G > 0 -/
theorem T3r_moe128k_lines (G : Nat) (h1 : 0 < G) :
    (tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 0 false ↔ G ≤ 1683) ∧
    (tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 1 false ↔ G ≤ 1789) ∧
    (tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 2 false ↔ G ≤ 1894) ∧
    (tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 0 false ↔ G ≤ 2047) ∧
    (tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 1 false ↔ G ≤ 2175) ∧
    (tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 2 false ↔ G ≤ 2303) := by
  rw [T3r_attn4_128k G 0, T3r_attn4_128k G 1, T3r_attn4_128k G 2]
  have hw : tw3 moe .anchor = 3207719 ∧ tw3 moe .directSer = 2641199 ∧ (262144 + 0 * 16384) * 80 = 20971520 ∧
      (262144 + 1 * 16384) * 80 = 22282240 ∧ (262144 + 2 * 16384) * 80 = 23592960 := by decide
  rw [hw.1, hw.2.1, hw.2.2.1, hw.2.2.2.1, hw.2.2.2.2]
  have k0a : 12455 ≤ 20971520 / G ↔ G ≤ 1683 := by rw [Nat.le_div_iff_mul_le h1]; omega
  have k1a : 12455 ≤ 22282240 / G ↔ G ≤ 1789 := by rw [Nat.le_div_iff_mul_le h1]; omega
  have k2a : 12455 ≤ 23592960 / G ↔ G ≤ 1894 := by rw [Nat.le_div_iff_mul_le h1]; omega
  have k0d : 10242 ≤ 20971520 / G ↔ G ≤ 2047 := by rw [Nat.le_div_iff_mul_le h1]; omega
  have k1d : 10242 ≤ 22282240 / G ↔ G ≤ 2175 := by rw [Nat.le_div_iff_mul_le h1]; omega
  have k2d : 10242 ≤ 23592960 / G ↔ G ≤ 2303 := by rw [Nat.le_div_iff_mul_le h1]; omega
  refine ⟨⟨fun h => k0a.mp (by omega), fun h => by have := k0a.mpr h; omega⟩, ⟨fun h => k1a.mp (by omega), fun h => by have := k1a.mpr h; omega⟩,
    ⟨fun h => k2a.mp (by omega), fun h => by have := k2a.mpr h; omega⟩, ⟨fun h => k0d.mp (by omega), fun h => by have := k0d.mpr h; omega⟩,
    ⟨fun h => k1d.mp (by omega), fun h => by have := k1d.mpr h; omega⟩, ⟨fun h => k2d.mp (by omega), fun h => by have := k2d.mpr h; omega⟩⟩
theorem T3r_moe128k_tie (G : Nat) (h1 : 0 < G) (h2 : G ≤ gStream) :
    -- round-3 chain (rowmax-T, the round-3 primary) on the anchored kernel: the tie, an iff — weights-bound at 169.2 (256 KiB)
    (tw3 moe .anchor ≤ attn3 131072 4 G .rowmax .T false ↔ G ≤ 1683) ∧
    -- round 4 without the bounce (legs 0): the round-3 tie reproduced
    (tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 0 false ↔ G ≤ 1683) ∧
    -- round 4 with one or both bounce legs: ATTENTION-bound at every G ≤ 174.6 (every page size, every gather loop)
    tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 1 false ∧ tw3 moe .anchor ≤ attn4 131072 1 4 G .lazy .T 2 false ∧
    -- the direct-path expert kernel: attention-bound at every G ≤ 174.6 on every chain and every leg count
    tw3 moe .directSer ≤ attn3 131072 4 G .rowmax .T false ∧ tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 0 false ∧
    tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 1 false ∧ tw3 moe .directSer ≤ attn4 131072 1 4 G .lazy .T 2 false := by
  have hg : gStream = 1746 := rfl
  have l := T3r_moe128k_lines G h1
  refine ⟨T3r_fleet_G_moe_128k_anchor G h1, l.1, l.2.1.mpr (by omega), l.2.2.1.mpr (by omega),
    (T3r_fleet_G_moe_128k_directser G h1).mpr (by omega), l.2.2.2.1.mpr (by omega), l.2.2.2.2.1.mpr (by omega),
    l.2.2.2.2.2.mpr (by omega)⟩
/-- the cells: per-layer margins at each measured G and leg count (anchored), and the round-4 step: legs 0 1.217 (W-bound step),
    legs 1 1.185, legs 2 1.155 (ATTN-bound steps); direct path 1.319 / 1.281 / 1.246 -/
theorem T3r_moe128k_tie_cells :
    tw3 moe .anchor - attn4 131072 1 4 g256 .lazy .T 0 false = 15527 ∧ pct 15527 (tw3 moe .anchor) = 5 ∧
    attn4 131072 1 4 gShuf64 .lazy .T 0 false - tw3 moe .anchor = 26201 ∧ pct 26201 (tw3 moe .anchor) = 8 ∧
    attn4 131072 1 4 gK1 .lazy .T 0 false - tw3 moe .anchor = 693337 ∧ pct 693337 (tw3 moe .anchor) = 216 ∧
    attn4 131072 1 4 g256 .lazy .T 1 false - tw3 moe .anchor = 182873 ∧ pct 182873 (tw3 moe .anchor) = 57 ∧
    attn4 131072 1 4 g256 .lazy .T 2 false - tw3 moe .anchor = 381017 ∧ pct 381017 (tw3 moe .anchor) = 119 ∧
    attn4 131072 1 4 gStream .lazy .T 2 false - tw3 moe .anchor = 270681 ∧ pct 270681 (tw3 moe .anchor) = 84 ∧
    attn4 131072 1 4 gStream .lazy .T 1 false - tw3 moe .anchor = 78425 ∧ pct 78425 (tw3 moe .anchor) = 24 ∧
    attn4 131072 1 4 g256 .lazy .T 0 false - tw3 moe .directSer = 550993 ∧ pct 550993 (tw3 moe .directSer) = 209 ∧
    step4F moe 131072 1 1 br3Lazy 0 lam3 = 205338275 ∧ tpsCard 1000 205338275 = 1217 ∧
    moe.nL * attn4 131072 1 4 g256 .lazy .T 0 false = 89381376 ∧ 89381376 < W3 moe 1 1 br3Lazy ∧
    step4F moe 131072 1 1 br3Lazy 1 lam3 = 210893475 ∧ tpsCard 1000 210893475 = 1185 ∧
    step4F moe 131072 1 1 br3Lazy 2 lam3 = 216441507 ∧ tpsCard 1000 216441507 = 1155 ∧
    moe.nL * attn4 131072 1 4 g256 .lazy .T 1 false = 94936576 ∧ moe.nL * attn4 131072 1 4 g256 .lazy .T 2 false = 100484608 ∧
    W3 moe 1 1 br3Lazy = 92824932 ∧ W3 moe 1 1 br3Lazy < 94936576 ∧
    step4F moe 131072 1 1 { br3Lazy with regime := .directSer } 0 lam3 = 189475715 ∧ tpsCard 1000 189475715 = 1319 ∧
    step4F moe 131072 1 1 { br3Lazy with regime := .directSer } 2 lam3 = 216441507 - 15862560 ∧ tpsCard 1000 200578947 = 1246 ∧
    262144 * 80 / 12455 = 1683 ∧ (262144 + 16384) * 80 / 12455 = 1789 ∧ (262144 + 2 * 16384) * 80 / 12455 = 1894 := by decide
/-- PRECISION (prover-forced): "attention-bound" is a per-layer statement. On the round-3 chain at 64 KiB the layer is attention-bound
    by 0.8 % but the STEP's largest term is still W (92.82 vs 90.53 ms): W carries the 3.00 ms lm_head, attention has no such term -/
theorem T3r_moe128k_step_level : tw3 moe .anchor ≤ attn3 131072 4 gShuf64 .rowmax .T false ∧
    bindsW3 moe 131072 1 1 (br3G gShuf64) lam3 = true ∧ A3 moe 131072 1 1 (br3G gShuf64) = 90535536 ∧ W3 moe 1 1 (br3G gShuf64) = 92824932 ∧
    headNs moe = 3008800 ∧ bindsA3 moe 131072 1 1 (br3G gShuf16) lam3 = true := by decide
/-- WHAT THE TIE DOES NOT DECIDE (prover-forced): at Π = 1 the step is a SUM (T = Σ W + Σ ATTN + …) — the binding side ranks nothing.
    Per MoE token at 128k on the round-4 headline (legs 2, 169.2): the direct-path expert kernel saves 15.86 ms; removing the bounce
    (legs 2 → 0) 11.10 ms; one leg 5.54 ms; the production loop at 169.2 instead of the session-1 138.3 is worth 22.33 ms; 169.2 → 174.6
    3.08 ms. So at 128k the expert-GEMM follow-up (E29) outranks the bounce follow-up (E24′) although the cell is attention-bound; the
    bounce removal overtakes E29 only from L = 187 392 (it is 88.82 ms at 1M); realising the measured G outranks both. -/
theorem T3r_moe128k_followups :
    moe.nL * (tw3 moe .anchor - tw3 moe .directSer) = 15862560 ∧
    moe.nL * (attn4 131072 1 4 g256 .lazy .T 2 false - attn4 131072 1 4 g256 .lazy .T 0 false) = 11103232 ∧
    moe.nL * (attn4 131072 1 4 g256 .lazy .T 2 false - attn4 131072 1 4 g256 .lazy .T 1 false) = 5548032 ∧
    moe.nL * (attn4 131072 1 4 gK1 .lazy .T 2 false - attn4 131072 1 4 g256 .lazy .T 2 false) = 22335488 ∧
    moe.nL * (attn4 131072 1 4 g256 .lazy .T 2 false - attn4 131072 1 4 gStream .lazy .T 2 false) = 3089408 ∧
    11103232 < 15862560 ∧ 15862560 < 22335488 ∧
    attn4 187392 1 4 g256 .lazy .T 2 false - attn4 187392 1 4 g256 .lazy .T 0 false = 566934 ∧
    attn4 186880 1 4 g256 .lazy .T 2 false - attn4 186880 1 4 g256 .lazy .T 0 false < tw3 moe .anchor - tw3 moe .directSer ∧
    tw3 moe .anchor - tw3 moe .directSer = 566520 ∧
    moe.nL * (attn4 1048576 1 4 g256 .lazy .T 2 false - attn4 1048576 1 4 g256 .lazy .T 0 false) = 88825856 ∧
    pct 15862560 216441507 = 73 ∧ pct 11103232 216441507 = 51 := by decide

/-! ## CORRECTION — the serial-chain int4 piece is 807 ns, not 596 (the alternatives proof round's correction; fleet.py still carries
    596 in `T_PIECE_W4_SER`). A 2 KiB int4 piece holds 4 096 values = 8 KiB of f16 and two (16,16,128) calls. Every serial-chain
    ("ser") cell of variant I moves; the dense 32k cell FLIPS from a gain to a loss — dense replication needs the overlapped cold
    tier (E30). The overlapped cells (the headline 3.720 / 0.155) do not use the piece and do not move. -/
theorem T3r_serpiece : pieceSerW = 596 ∧ pieceSerC = 807 ∧ slabSer pieceSerW = 305152 ∧ slabSer pieceSerC = 413184 ∧
    rW4ser pieceSerW = 552 ∧ rW4ser pieceSerC = 408 ∧ tn (8 * KiB) rUsS1 = 32 ∧ tn (8 * KiB) rLoader = 309 ∧
    -- MoE 32k: as written 147.06 ms → 3.399 (+88.6 %); corrected 159.85 → 3.128 (+73.5 %)
    instStep3 moe 32768 1 1 xsMoe32k .directSer (slabSer pieceSerW) 0 .uniform br3 lam3 = 147068283 ∧ tpsInst 1000 2000 147068283 = 3399 ∧
    instStep3 moe 32768 1 1 xsMoe32k .directSer (slabSer pieceSerC) 0 .uniform br3 lam3 = 159845439 ∧ tpsInst 1000 2000 159845439 = 3128 ∧
    pcsUp 3399 1802 = 886 ∧ pcsUp 3128 1802 = 735 ∧
    -- dense 32k: as written 4 095.48 → 0.122 (+17.3 %); corrected 4 977.19 → 0.100 (−3.8 %): a LOSS
    instStep3 dense 32768 1 1 xsDense32k .directSer 0 (rW4ser pieceSerW) .uniform br3 lam3 = 4095488833 ∧ tpsInst 1000 2000 4095488833 = 122 ∧
    instStep3 dense 32768 1 1 xsDense32k .directSer 0 (rW4ser pieceSerC) .uniform br3 lam3 = 4977193783 ∧ tpsInst 1000 2000 4977193783 = 100 ∧
    pcsUp 122 104 = 173 ∧ pcsDown 100 104 = 38 ∧
    -- dense 4k / 128k: 0.136 → 0.114 (+5.5 %); 0.089 (−4.3 %) → 0.070 (−24.7 %)
    instStep3 dense 4096 1 1 xsDense4k .directSer 0 (rW4ser pieceSerC) .uniform br3 lam3 = 4367629423 ∧ tpsInst 1000 2000 4367629423 = 114 ∧
    instStep3 dense 131072 1 1 xsDense128k .directSer 0 (rW4ser pieceSerW) .uniform br3 lam3 = 5578798663 ∧ tpsInst 1000 2000 5578798663 = 89 ∧
    instStep3 dense 131072 1 1 xsDense128k .directSer 0 (rW4ser pieceSerC) .uniform br3 lam3 = 7078675303 ∧ tpsInst 1000 2000 7078675303 = 70 ∧
    pcsUp 114 108 = 55 ∧ pcsDown 89 93 = 43 ∧ pcsDown 70 93 = 247 ∧
    -- MoE 4k / 128k / 1M serial-chain: 3.662 / 2.087 / 0.507 (as written 3.997 / 2.249 / 0.540)
    tpsInst 1000 2000 (instStep3 moe 4096 1 1 xsMoe4k .directSer (slabSer pieceSerC) 0 .uniform br3 lam3) = 3662 ∧
    tpsInst 1000 2000 (instStep3 moe 131072 1 1 xsMoe128k .directSer (slabSer pieceSerC) 0 .uniform br3 lam3) = 2087 ∧
    tpsInst 1000 2000 (instStep3 moe 1048576 1 1 xsMoe1M .directSer (slabSer pieceSerC) 0 .uniform br3 lam3) = 507 ∧
    -- the MoE breakeven still passes on the corrected chain, 3.4× inside the 1 406 404 ns line
    slabSer pieceSerC ≤ 1406404 ∧ 1406404 * 10 / slabSer pieceSerC = 34 := by decide
/-- H10 on the corrected serial chain: the dense 32k cell needs c ≥ 2.091× — more than two instances at full solo speed can give —
    so it loses at EVERY concurrency c ≤ 2 000, including the card-scale 1.99×; the MoE 32k cell needs c ≥ 1.153× -/
theorem T3r_serpiece_h10 (c : Nat) :
    (105 ≤ tpsInst 1000 c 4977193783 ↔ 2091 ≤ c) ∧ (1803 ≤ tpsInst 1000 c 159845439 ↔ 1153 ≤ c) ∧
    (c ≤ 2000 → tpsInst 1000 c 4977193783 < 105) := by
  have k1 : 105 ≤ tpsInst 1000 c 4977193783 ↔ 2091 ≤ c := by
    unfold tpsInst; rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega
  have k2 : 1803 ≤ tpsInst 1000 c 159845439 ↔ 1153 ≤ c := by
    unfold tpsInst; rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega
  exact ⟨k1, k2, fun h => Nat.lt_of_not_le (fun h' => absurd (k1.mp h') (by omega))⟩

/-! ## E35 is LICENSED (qk-norm + per-row guard, HW-MAP): both chains are carried. The fixed-shift (lazy) cells are the loadable
    branch for qk-normalised models; the guard is in every lazy cell (one reduce-max per P reel); the no-guard fixed shift (overflow
    on 42–48 % of the reported steps, DEAD) enters no cell. -/
theorem T3r_e35_guard : chain100 512 1 .lazy .T mergeH = 512 * 16 * (5 * 137 + 1150) + 8 * call100 tRm16 + mergeH ∧
    8 * call100 tRm16 * 10 / (rVecCore * 100) = 1455 ∧ vblk3 1 .lazy .T = 5530 ∧ vblk3 1 .rowmax .T = 9276 := by decide
/-- the paired cells (chain as specified / fixed-shift): dense spec 0.227 / 0.248, dense 128k spec 0.156 / 0.203, dense 1M KV-int8
    0.054 / 0.065, L*_KV on KV-int8 1 006 608 / 1 507 344, t* dense 2 / 3 and MoE 5 / 9, the instance dense spec 0.349 / 0.374 -/
theorem T3r_e35_branches :
    tpsCard (tau 700 3) (step3 dense 32768 1 4 br3 lam3) = 227 ∧ tpsCard (tau 700 3) (step3 dense 32768 1 4 br3Lazy lam3) = 248 ∧
    tpsCard (tau 700 3) (step3 dense 131072 1 4 br3 lam3) = 156 ∧ tpsCard (tau 700 3) (step3 dense 131072 1 4 br3Lazy lam3) = 203 ∧
    tpsCard 1000 (step3 dense 1048576 1 1 br3I8 lam3) = 54 ∧ tpsCard 1000 (step3 dense 1048576 1 1 br3I8Lazy lam3) = 65 ∧
    vecGeKv 16 1 .rowmax .T false = false ∧ vecGeKv 16 2 .rowmax .T false = true ∧
    vecGeKv 16 2 .lazy .T false = false ∧ vecGeKv 16 3 .lazy .T false = true ∧
    vecGeKv 4 4 .rowmax .T false = false ∧ vecGeKv 4 5 .rowmax .T false = true ∧
    vecGeKv 4 8 .lazy .T false = false ∧ vecGeKv 4 9 .lazy .T false = true := by decide
/-- the guard's exception path at the measured trip rate (0.087–0.22 % of steps) costs ≈ 10.7 µs per trip (DESIGN-3 §3.4 estimate):
    even ONE trip in EVERY layer of EVERY step (≥ 450× the measured rate) leaves the fixed-shift cells unchanged in thousandths -/
theorem T3r_e35_trip_bound (e : Nat) (he : e ≤ 120 * 10700) :
    tpsCard (tau 700 3) (step3 dense 32768 1 4 br3Lazy lam3 + e) = 248 ∧
    tpsCard 1000 (step3 dense 1048576 1 1 br3I8Lazy lam3 + e) = 65 ∧
    tpsCard 1000 (step3 dense 32768 1 1 br3Lazy lam3 + e) = 104 := by
  have h : step3 dense 32768 1 4 br3Lazy lam3 = 2547505208 ∧ step3 dense 1048576 1 1 br3I8Lazy lam3 = 3814122749 ∧
      step3 dense 32768 1 1 br3Lazy lam3 = 2386333949 ∧ tau 700 3 = 2533 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2]
  unfold tpsCard
  refine ⟨?_, ?_, ?_⟩
  · have a : 248 ≤ 2533 * 1000000000 / (4 * (2547505208 + e)) := by rw [Nat.le_div_iff_mul_le (by omega)]; omega
    have b : 2533 * 1000000000 / (4 * (2547505208 + e)) < 249 := by rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega
  · have a : 65 ≤ 1000 * 1000000000 / (4 * (3814122749 + e)) := by rw [Nat.le_div_iff_mul_le (by omega)]; omega
    have b : 1000 * 1000000000 / (4 * (3814122749 + e)) < 66 := by rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega
  · have a : 104 ≤ 1000 * 1000000000 / (4 * (2386333949 + e)) := by rw [Nat.le_div_iff_mul_le (by omega)]; omega
    have b : 1000 * 1000000000 / (4 * (2386333949 + e)) < 105 := by rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
    omega

/-! ## The load-bearing set under PROMPT-4P2's names (conjunctions of the theorems above) -/
/-- T_spec_moe_loss survives (threshold 0.864 → 0.866 under uniform routing): a loss iff α ≤ 0.866 / 0.752 / 0.657 by routing family
    (anchored) and ≤ 0.847 / 0.741 / 0.652 on the direct path, in both directions for every α -/
theorem T3r_spec_moe_loss : (∀ a, a < 1001 →
      ((tau a 3 * 138693907 < 1000 * 453082211 ↔ a ≤ 866) ∧ (tau a 3 * 138693907 < 1000 * 380770559 ↔ a ≤ 752) ∧
       (tau a 3 * 138693907 < 1000 * 329119379 ↔ a ≤ 657) ∧ (tau a 3 * 122831347 < 1000 * 389631971 ↔ a ≤ 847) ∧
       (tau a 3 * 122831347 < 1000 * 331200059 ↔ a ≤ 741) ∧ (tau a 3 * 122831347 < 1000 * 289462979 ↔ a ≤ 652))) ∧
    step3 moe 32768 1 4 br3 lam3 = 453082211 ∧ step3 moe 32768 1 1 br3 lam3 = 138693907 :=
  ⟨T3r_spec_moe_loss_exact, T3r_spec_moe_steps.2.1, T3r_spec_moe_steps.1⟩
/-- T_min_dies survives unchanged (R27): 4 dies infeasible for every layer assignment under full int8 residency, 5 feasible; the
    instance variant escapes it only under the different hypothesis that int4 bytes ride the measured unpack path (R17) -/
theorem T3r_min_dies :
    (∀ n0 n1 n2 n3, n0 + n1 + n2 + n3 = 120 →
      ¬ (n0 * dense.wRes ≤ dieMem ∧ n1 * dense.wRes ≤ dieMem ∧ n2 * dense.wRes ≤ dieMem ∧ n3 * dense.wRes ≤ dieMem)) ∧
    (∀ n0 n1 n2 n3, n0 + n1 + n2 + n3 = 28 →
      ¬ (n0 * moe.wRes ≤ dieMem ∧ n1 * moe.wRes ≤ dieMem ∧ n2 * moe.wRes ≤ dieMem ∧ n3 * moe.wRes ≤ dieMem)) ∧
    24 * dense.wRes + dense.wEmbed + 24 * 4096 * 4096 + ws + oRt ≤ dieMem ∧
    6 * moe.wRes + moe.wEmbed + 6 * 4096 * 4096 + ws + oRt ≤ dieMem := T_min_dies
