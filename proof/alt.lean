/-
  proof/alt.lean — machine-checked derivations for ALTERNATIVES.md (dmonk, the pattern-matching round):
  the 32-claim ledger of Appendix A plus the proof-round re-derivations (PROMPT-5P).

  Core Lean 4.35 only (no Mathlib, no Batteries, nothing beyond the implicit Init). Every quantity is a
  scaled integer exactly as in proof/alt.py (which imports proof/fleet.py and proof/attn.py), so every
  theorem closes with `decide`, `omega`, `rfl` or `simp` plus structural steps:
    bytes   : bytes (KiB = 1024, MiB = 2^20, GiB = 2^30; GB = 10^9 decimal)
    rates   : tenths of GB/s (1 B/ns = 1 GB/s decimal)             1746 = 174.6
    time    : ns, floor (tn b R = b*10 / R); usR = µs round-half-up; ms2 = hundredths of ms, floor
    tokens/s: thousandths per card (tpsCard tok T = tok·10⁹ / (4·T); tpsInst = two instances on the 4 cards)
    pct     : tenths of a percent round-half-up; pcs = signed change in tenths, floor toward zero
    shares  : thousandths (x = int4 share of the candidate bytes per die)

  The file cannot import proof/fleet.lean or proof/attn.lean when built standalone, so the handful of
  round-2 fleet / attention functions ALTERNATIVES builds on are duplicated here, name for name, in the
  namespaces `Fleet2` and `Attn2` (pure integer arithmetic; `T_alt_baseline_identity` proves the "today"
  cells equal the numbers fleet.lean / attn.lean fix). PROOF-COVERAGE-5.md maps every ledger row to a
  theorem here, an alt.py label, an experiment (EMPIRICAL) or an explicit ASSUMPTION.

  Inputs applied by steering before proving (PROMPT-5P): the f16→i8 activation pass is MEASURED (HW-MAP
  0915e22: 43.7 µs per pass, rint-half-even saturating ±127) and H10 is GREEN at die scale (HW-MAP
  fa2c24a: two instances on disjoint dies at 1.99× aggregate). The unmeasured / assumed quantities are
  explicit arguments: the W4 core-slab time `Tc`, the A-lift cost `a`, `csync`, `cpg`, `cV`, `rho`, the
  per-die overhead `ort`, the bounce latency `lam`, the concurrency efficiency `eta`, the prefix `Ls`.

  Build: `lean proof/alt.lean` (standalone) or `cd proof && lake build` (target `Alt`).
  No `axiom`, no `sorry`, no `native_decide` anywhere.
-/

namespace Measured
/-- HW-MAP data-movement table: full W8 decode kernel 174.6 GB/s aggregate, flat m = 1..16. Tenths. -/
def rGemm : Nat := 1746
/-- HW-MAP card table: host links, tenths of GB/s (die 1 transits die 0). -/
def h2d0 : Nat := 276
def h2d1 : Nat := 139
def d2h0 : Nat := 273
def d2h1 : Nat := 190
/-- HW-MAP: MMA issue cost 15 ns per (16,16,128) call; S1 → L0 loader 26.5 GB/s/core strict-serial;
    vector SRAM → S1 plain fill 250 GB/s/core; ~40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core. -/
def cMma : Nat := 15
def rLoader : Nat := 265
def rUsS1 : Nat := 2500
def rVecCore : Nat := 432
/-- HW-MAP: ~91 µs launch + queue floor. ns. -/
def tLaunch : Nat := 91000
/-- HW-MAP realized-launch row: per-launch overhead as the serving loop REALIZES it ≤ 36 µs (the serving
    byte accounting bounds the whole non-GEMM share at 7.7 ms over ≥ 24 layers × ≥ 9 launches; empty-launch
    floor 17 µs; device-dispatch route 2.9 µs scan + 6.2 µs host build + 35.4 µs H2D per step corroborate).
    The 91 µs primary stays as the conservative wall-clock bound (bracket 10/500 covers 36). ns. -/
def tLaunchRealized : Nat := 36000
/-- HW-MAP hierarchy: 86 GB usable DDR per die; S1 ~1 MB (PRIOR). -/
def dieMemGB : Nat := 86
def s1Prior : Nat := 1000000
/-- HW-MAP: vector i4 → f16 unpack, 5 passes, ~5.3 GB/s/core of int4 bytes (tenths). -/
def rW4v : Nat := 53
/-- HW-MAP 0915e22 (steering input): on-device f16 → i8 activation quantization pass, 43.7 µs at m = 1,
    K = 8192 (fixed reading; E38 asks whether it is proportional). ns. -/
def cQ : Nat := 43700
/-- HW-MAP e9349c8: host bounce 12.2 / 12.1 µs per direction (ns); ALTERNATIVES used the 91 µs anchor. -/
def lamMeas : Nat := 12200
/-- HW-MAP E21: c_pg(64 KiB, shuffled − sequential) = 38 ns per page (a lower bound); measured per-page
    sequential times 3 101 ns (64 KiB) and 12 391 ns (256 KiB); shuffled aggregate 167.0 at 64 KiB. -/
def cPgMeas : Nat := 38
def tPgSeq64 : Nat := 3101
def tPgSeq256 : Nat := 12391
/-- HW-MAP fa2c24a (season h): two instances on disjoint dies run at 1.99× aggregate (η = 995 ‰). -/
def etaH10 : Nat := 995
/-- HW-MAP: L0C → US drain 152.8 GB/s/core at mt = 1 (tenths); the f16 maximum 65 504. -/
def rDrainMeas : Nat := 1528
def f16Max : Nat := 65504

/-! DESIGN-2 derived inputs (theorems of proof/moe.lean, not measurements): the serial-regime expert slab
    time per core 122 979 ns (T_piece_expert), the fixed per-launch cost F = 8 µs (its assumption), and the
    subtraction residual 25.4 ns per MMA call (tenths). -/
def tSlabSer : Nat := 122979
def fMoe : Nat := 8000
def cResT : Nat := 254
end Measured

namespace Design
open Measured

/-! ### Units, helpers (alt.py / fleet.py / attn.py conventions) -/
def KiB : Nat := 1024
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB : Nat := 1000000000
def dieMem : Nat := dieMemGB * GB
/-- ASSUMPTION (A, H8 / H11): runtime overhead per die 2 GiB, workspace 64 MiB; `ort` is a hypothesis
    variable of every fit theorem. -/
def oRt : Nat := 2 * GiB
def ws : Nat := 64 * MiB
/-- ASSUMPTION (A, H3): the 91 µs host-bounce latency ALTERNATIVES carried (the measured value is 12.2 µs). -/
def lamMid : Nat := 91000
/-- PROBLEM-3 branch carried by fleet.py: native exp = 4 lane-ops per score; KV stream at the kernel rate. -/
def cNative : Nat := 4
def gStream : Nat := rGemm
def rVecDie : Nat := 8 * rVecCore
def kDraft : Nat := 3

def tn (b R : Nat) : Nat := b * 10 / R
def usR (ns : Nat) : Nat := (ns + 500) / 1000
def ms2 (ns : Nat) : Nat := ns / 10000
def pct (n d : Nat) : Nat := (2 * n * 1000 + d) / (2 * d)
def pctH (n d : Nat) : Nat := (2 * n * 10000 + d) / (2 * d)
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b
def rateT (b ns : Nat) : Nat := (2 * b * 10 + ns) / (2 * ns)
def x10 (a b : Nat) : Nat := a * 10 / b
def gb1 (b : Nat) : Nat := b / (GB / 10)
/-- alt.py `pcs`: signed percent change in tenths (floor toward zero) — returned as (gain?, magnitude) -/
def pcsUp (n d : Nat) : Nat := (n - d) * 1000 / d
def pcsDown (n d : Nat) : Nat := (d - n) * 1000 / d
def tpsCard (tok T : Nat) : Nat := tok * 1000000000 / (4 * T)
/-- two instances on the four cards (alt.py `tps_card_inst`) -/
def tpsInst (tok T : Nat) : Nat := tok * 2 * 1000000000 / (4 * T)
/-- two instances at a concurrency efficiency η (thousandths): H10's hypothesis variable -/
def tpsInstEta (tok T eta : Nat) : Nat := tok * 2 * eta * 1000000000 / (1000 * 4 * T)
def sumPos (f : Nat → Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => sumPos f n + f n
def minOver (f : Nat → Nat) : Nat → Nat
  | 0 => f 0
  | n + 1 => min (minOver f n) (f (n + 1))

/-! ### Fleet2: the round-2 DESIGN-4 cost model ALTERNATIVES builds on (proof/fleet.py `step`) -/
namespace Fleet2
structure Shape where
  nL : Nat
  d : Nat
  Hq : Nat
  Hkv : Nat
  vocab : Nat
  nlaunch : Nat
  moe : Bool
  /-- bytes streamed per token per layer by the dense kernel (dense: the layer; MoE: the attention GEMMs) -/
  wStream : Nat
  /-- resident int8 bytes per layer (MoE: attention + 256 expert slabs) -/
  wRes : Nat
  wEmbed : Nat
  wHead : Nat
  kvTok : Nat
  layers : Nat → Nat
  draftPos : Nat
  slabs : Nat
  slab : Nat

def denseLayerBytes (d ffn Hkv dh : Nat) : Nat := d * (d + 2 * Hkv * dh) + d * d + 3 * d * ffn
def moeAttnBytes (d Hkv dh : Nat) : Nat := d * (d + 2 * Hkv * dh) + d * d
def moeExpertBytes (E slabs n : Nat) : Nat := E * slabs * n * n
/-- the two shapes with their byte counts as literals (T_alt_shapes proves them equal to the formulas) -/
def dense : Shape :=
  { nL := 120, d := 16384, Hq := 128, Hkv := 8, vocab := 128256, nlaunch := 6, moe := false,
    wStream := 3187671040, wRes := 3187671040, wEmbed := 2101346304, wHead := 2101346304, kvTok := 4096,
    layers := fun _ => 15, draftPos := 1, slabs := 3, slab := 16777216 }
def moe : Shape :=
  { nL := 28, d := 4096, Hq := 32, Hkv := 8, vocab := 128256, nlaunch := 7, moe := true,
    wStream := 41943040, wRes := 12926844928, wEmbed := 525336576, wHead := 525336576, kvTok := 4096,
    layers := fun p => if p % 2 = 0 then 4 else 3, draftPos := 7, slabs := 3, slab := 16777216 }
def draftW : Nat := 1 * GB
def draftLaunch : Nat := 121
def draftKv : Nat := 24 * 4096 * (2 * 8 * 64 * 2)
/-- chain position → die: positions alternate d1, d0, d1, d0, … (the 4-die instance uses the same rule) -/
def die (p : Nat) : Nat := if p % 2 = 0 then 1 else 0
def h2d (d : Nat) : Nat := if d = 0 then h2d0 else h2d1
def d2h (d : Nat) : Nat := if d = 0 then d2h0 else d2h1
/-- active experts per step under uniform routing: min(8·rows, 256) -/
def dU (rows : Nat) : Nat := if 8 * rows ≤ 256 then 8 * rows else 256

/-! memory (fleet.py section 1, needed for the rows-cliff row) -/
def dieWeights (s : Shape) (pos : Nat) : Nat :=
  s.layers pos * s.wRes + (if pos = 0 then s.wEmbed else 0) + (if pos = 7 then s.wHead else 0)
  + (if pos = s.draftPos then draftW + draftKv else 0)
def dieKv (s : Shape) (pos L B : Nat) (i8 : Bool) : Nat :=
  s.layers pos * s.kvTok * L * B / (if i8 then 2 else 1)
def dieTotal (s : Shape) (pos L B : Nat) (i8 : Bool) : Nat := dieWeights s pos + dieKv s pos L B i8 + ws + oRt
def feasibleB (s : Shape) (L B : Nat) : Bool :=
  (List.range 8).all fun p => decide (dieTotal s p L B false ≤ dieMem)
def LmaxPos (s : Shape) (pos B : Nat) : Nat :=
  (dieMem - oRt - ws - dieWeights s pos) / (s.layers pos * s.kvTok * B)
def Lmax (s : Shape) (B : Nat) : Nat := minOver (fun p => LmaxPos s p B) 7

/-! exchange (section 2): 7 activation hops, logits D2H from position 7, ids H2D to position 0 -/
def act (s : Shape) (rows : Nat) : Nat := rows * s.d * 2
def logits (s : Shape) (rows : Nat) : Nat := rows * s.vocab * 4
def hopBw (b src dst : Nat) : Nat := tn b (d2h src) + tn b (h2d dst)
def xchBw (s : Shape) (rows : Nat) : Nat :=
  sumPos (fun p => hopBw (act s rows) (die p) (die (p + 1))) 7
  + tn (logits s rows) (d2h (die 7)) + tn (rows * 4) (h2d (die 0))
def Tx (s : Shape) (rows lam : Nat) : Nat := xchBw s rows + 16 * lam

/-! per-layer time (section 3): attention parts at G, c_E; GEMM with an explicit expert-slab time -/
def kvBytes (s : Shape) (L B : Nat) (i8 : Bool) : Nat := s.kvTok * L * B / (if i8 then 2 else 1)
def kvNs (s : Shape) (L B G : Nat) (i8 : Bool) : Nat := tn (kvBytes s L B i8) G
def smNs (s : Shape) (L B t cE : Nat) : Nat := B * t * s.Hq * L * cE * 10 / rVecDie
def frags (s : Shape) (t : Nat) : Nat := ceilDiv (t * (s.Hq / s.Hkv)) 16
def mmaNs (s : Shape) (L B t : Nat) : Nat := B * 2 * s.Hkv * (L / 16) * frags s t * cMma / 8
def attnNs (s : Shape) (L B t G cE : Nat) (i8 : Bool) : Nat :=
  max (kvNs s L B G i8) (max (smNs s L B t cE) (mmaNs s L B t))
/-- MoE per-layer GEMM with the expert-slab time `tslab` as a parameter (serial 122 979; ALT-1 99 374 / 96 089) -/
def gemmNs (s : Shape) (rows tslab : Nat) : Nat :=
  if s.moe then tn s.wStream rGemm + 2 * fMoe + s.slabs * dU rows * tslab else tn s.wStream rGemm
def headNs (s : Shape) : Nat := tn s.wHead rGemm
def draftTokNs (lam nl : Nat) : Nat :=
  tn draftW rGemm + tn draftKv rGemm + nl * tLaunch + tn (128256 * 4) d2h0 + 2 * lam
def draftNs (lam : Nat) : Nat := kDraft * draftTokNs lam draftLaunch
/-- the draft term is present whenever t > 1 (k = 3 drafts) -/
def dNs (t lam : Nat) : Nat := if t > 1 then draftNs lam else 0
/-- fleet.py `step` at the primary branch (G = stream, native exp, launches serialised) with the expert-slab
    time, the launches per layer and λ explicit: T = Σ_layers (GEMM + attention) + head + launches + exchange + draft -/
def stepNs (s : Shape) (L B t tslab nl lam : Nat) (i8 : Bool) : Nat :=
  s.nL * gemmNs s (B * t) tslab + s.nL * attnNs s L B t gStream cNative i8 + headNs s
  + (s.nL * nl + 2) * tLaunch + Tx s (B * t) lam + dNs t lam
/-- the ledgered "today" cell: serial regime, the design's launches, λ = 91 µs, f16 KV -/
def today (s : Shape) (L B t : Nat) : Nat := stepNs s L B t tSlabSer s.nlaunch lamMid false
def todayI8 (s : Shape) (L : Nat) : Nat := stepNs s L 1 1 tSlabSer s.nlaunch lamMid true
/-- τ(α, k) tokens per verify step, thousandths (fleet.py `tau_milli`) -/
def powM (a : Nat) : Nat → Nat
  | 0 => 1000
  | n + 1 => powM a n * a / 1000
def tau (a : Nat) : Nat → Nat
  | 0 => powM a 0
  | k + 1 => tau a k + powM a (k + 1)
end Fleet2

/-! ### Attn2: the round-2 DESIGN-3 attention model ALTERNATIVES builds on (proof/attn.py `step_ns`,
    duplicated from proof/attn.lean's `Design` namespace: drain hidden, R_drain 10 GB/s, merge 7 000) -/
namespace Attn2
def gH : Nat := 8
def dH : Nat := 128
def coreTok (d : Nat) : Nat := 4 * d
/-- [A1] per-page model: t_core = P·80/R_gemm + c_pg ; aggregate = 8·P·10 / t_core -/
def tCore (P cpg : Nat) : Nat := P * 80 / rGemm + cpg
def gPage (P cpg : Nat) : Nat := 8 * P * 10 / tCore P cpg
def blockOf (mt : Nat) : Nat := if mt ≤ 2 then 512 else if mt ≤ 4 then 256 else 128
def rowsOf (t g : Nat) : Nat := t * g
def mtOf (rows : Nat) : Nat := ceilDiv rows 16
def rowsPassMax : Nat := 64
def passesOf (rows : Nat) : Nat := ceilDiv rows rowsPassMax
def mtPass (rows : Nat) : Nat := mtOf (min rows rowsPassMax)
def lMatrix (L : Nat) : Nat := 16 * (L / 16)
def nblocks (L mt : Nat) : Nat := ceilDiv (lMatrix L) (blockOf mt)
def ddrBlock (G mt d : Nat) : Nat := tn (blockOf mt * coreTok d * 8) G
def vecBlock (cV rho mt merge : Nat) : Nat := (blockOf mt * 16 * mt * cV + merge * mt) * rho * 10 / rVecCore
def scoresCallsPer16 (d : Nat) : Nat := if d ≤ 64 then 2 else 1
def mmaCalls (mt d : Nat) : Nat := mt * ((blockOf mt / 16) * scoresCallsPer16 d + (d / 16) * (blockOf mt / 128))
def mmaBlock (mt d : Nat) : Nat := mmaCalls mt d * cMma
def pFragB : Nat := 4096
def loaderBlock (mt : Nat) : Nat := tn ((blockOf mt / 128) * pFragB * mt) rLoader
def drainBytes (mt d : Nat) : Nat := (blockOf mt * 16 * 4 + 16 * d * 4) * mt
def drainBlock (mt d Rd : Nat) : Nat := tn (drainBytes mt d) Rd
def tailOps (L mt d : Nat) : Nat := (L % 16) * d * 16 * mt * 4
def tailNs (L mt d rho : Nat) : Nat := tailOps L mt d * rho * 10 / rVecCore
/-- drain hidden: the block is the slowest of KV stream, vector, MMA, loader -/
def blockMax (G cV rho mt d merge : Nat) : Nat :=
  max (max (max (ddrBlock G mt d) (vecBlock cV rho mt merge)) (mmaBlock mt d)) (loaderBlock mt)
def fixedNs (L cV rho Rd merge mt mtAll d : Nat) : Nat :=
  2 * vecBlock cV rho mt merge + drainBlock mt d Rd + tailNs L mtAll d rho
def pSel (rows : Nat) (onepass : Bool) : Nat := if onepass then 1 else passesOf rows
def mtSel (rows : Nat) (onepass : Bool) : Nat := if onepass then mtOf rows else mtPass rows
/-- attn.py `step_ns` (drain hidden): passes · blocks · max(engines) + fixed; `onepass` = the S4 variant
    (mt ≤ 8, L0A exactly full), `merge` = lane-ops per block-fragment for the online-softmax merge -/
def stepNs (L t g d G cV rho Rd merge : Nat) (onepass : Bool) : Nat :=
  pSel (rowsOf t g) onepass * nblocks L (mtSel (rowsOf t g) onepass) * blockMax G cV rho (mtSel (rowsOf t g) onepass) d merge
  + fixedNs L cV rho Rd merge (mtSel (rowsOf t g) onepass) (mtOf (rowsOf t g)) d
def rDrainA : Nat := 100
def mergeOps : Nat := 7000
def cvNat : Nat := 7
def cvWorst : Nat := 33
/-- the headline shape (g = 8, d = 128): two-pass / S4 with the merge / S4 with the lazy rescale (merge 0) -/
def stepH (L t G cV rho : Nat) : Nat := stepNs L t gH dH G cV rho rDrainA mergeOps false
def stepS4 (L G cV rho : Nat) : Nat := stepNs L 16 gH dH G cV rho rDrainA mergeOps true
def stepLazy (L G cV rho : Nat) : Nat := stepNs L 16 gH dH G cV rho rDrainA 0 true
/-- ALT-6: K int8 / V f16 — the streamed bytes × 3/4, one more lane-op per score for the K-scale reel -/
def stepK8 (L t G cV rho : Nat) : Nat :=
  let rows := rowsOf t gH
  let p := passesOf rows
  let mt := mtPass rows
  let nb := nblocks L mt
  max (max (max (p * nb * ddrBlock G mt dH * 3 / 4) (p * nb * vecBlock (cV + 1) rho mt mergeOps)) (p * nb * mmaBlock mt dH))
      (p * nb * loaderBlock mt)
  + fixedNs L (cV + 1) rho rDrainA mergeOps mt (mtOf rows) dH
/-- ALT-5: two-tier pages — 1 MiB extents for every whole 4 096-token run, 64 KiB tail pages for the rest;
    time per core and the aggregate rate in tenths (alt.py `G_tier`) -/
def tExt (cpg : Nat) : Nat := MiB * 80 / rGemm + cpg
def tPage64 (cpg : Nat) : Nat := 64 * KiB * 80 / rGemm + cpg
def nExt (L : Nat) : Nat := L / 4096
def nTail (L : Nat) : Nat := ceilDiv (L % 4096) 256
def tTier (L cpg : Nat) : Nat := nExt L * tExt cpg + nTail L * tPage64 cpg
/-- the same L tokens read as 64 KiB pages: ⌈L/256⌉ pages -/
def tPages64 (L cpg : Nat) : Nat := ceilDiv L 256 * tPage64 cpg
def gTier (L cpg : Nat) : Nat := if tTier L cpg = 0 then rGemm else 8 * L * 256 * 10 / tTier L cpg
/-- the measured per-page basis (DESIGN-3 round 3, attn.py `G_page3` / `G_tier3`): sequential per-page
    times 3 101 ns (64 KiB) and 4 × 12 391 ns per extent, plus the extra per-page cost c -/
def gPage3 (P tseq c : Nat) : Nat := 8 * P * 10 / (tseq + c)
def tTier3 (L c : Nat) : Nat := nExt L * (4 * tPgSeq256 + c) + nTail L * (tPgSeq64 + c)
def gTier3 (L c : Nat) : Nat := 8 * L * 256 * 10 / tTier3 L c
end Attn2

/-! ### Alt: the alternatives as the same models with one term changed (proof/alt.py) -/
namespace Alt
open Fleet2

/-! ALT-1: the MoE expert kernel on the DDR → L0B direct path -/
/-- B 2 MiB per core-slab at the per-core share of 174.6: 96 089 ns -/
def tBDirect : Nat := 2 * MiB * 80 / rGemm
/-- the A lift: 64 KiB through the 26.5 GB/s loader + 32 calls × 25.4 ns residual: 3 285 ns -/
def aLift : Nat := tn (64 * KiB) rLoader + 32 * cResT / 10
def chainSer : Nat := tBDirect + aLift
def chainOvl : Nat := tBDirect
def chainG2 : Nat := tBDirect + aLift / 2
/-- the A-lift cost as a hypothesis variable a ∈ [0, 3 285] -/
def chainA (a : Nat) : Nat := tBDirect + a
def mmaExp : Nat := 1024 * cMma
def bytesStep : Nat := 8 * 16 * MiB
def stepExp (chain : Nat) : Nat := 8 * chain + fMoe
def rateExp (chain : Nat) : Nat := rateT bytesStep (stepExp chain)

/-! ALT-0 / ALT-2: the W4 vector-unpack cold tier -/
/-- 1 MiB of int4 per core-slab at the unpack rate r (tenths): 197 844 ns at the measured 5.3 -/
def tSlabW4 (r : Nat) : Nat := tn MiB r
/-- the strictly serial chain per 2 KiB of int4 AS WRITTEN in ALTERNATIVES (4 KiB f16 legs, one MMA call): 596 ns -/
def pieceSerW : Nat := tn (2 * KiB) rW4v + tn (4 * KiB) rUsS1 + tn (4 * KiB) rLoader + cResT / 10 + cMma
/-- the same chain with the f16 bytes a 2 KiB int4 piece actually produces (4 096 values = 8 KiB f16, two
    (16,16,128) calls): 807 ns — the proof-round correction -/
def pieceSerC : Nat := tn (2 * KiB) rW4v + tn (8 * KiB) rUsS1 + tn (8 * KiB) rLoader + 2 * (cResT / 10) + 2 * cMma
def slabSer (piece : Nat) : Nat := 512 * piece
/-- W8-equivalent die rates of the cold tier: overlapped 2 × 8 × 5.3 = 84.8; serial per piece -/
def rW4W8Ovl : Nat := 2 * 8 * rW4v
def rW4W8Ser (piece : Nat) : Nat := rateT (2 * 2 * KiB) piece * 8

/-! ALT-2: two 4-die instances (c0.d1 → c0.d0 → c1.d1 → c1.d0), the minimal int4 share x per die -/
def layers4 (s : Shape) : Nat := if s.moe then 7 else 30
/-- the int4 candidate bytes per layer: the expert slabs (MoE) or the whole layer (dense) -/
def cand (s : Shape) : Nat := if s.moe then s.wRes - s.wStream else s.wStream
def instDieWeights (s : Shape) (pos x : Nat) : Nat :=
  layers4 s * (s.wRes - cand s * x / 2000) + (if pos = 0 then s.wEmbed else 0) + (if pos = 3 then s.wHead else 0)
  + (if s.moe = false ∧ pos = 1 then draftW + draftKv else 0)
def instDieKv (s : Shape) (L B : Nat) (i8 : Bool) : Nat := layers4 s * s.kvTok * L * B / (if i8 then 2 else 1)
def instTotal (s : Shape) (pos L B : Nat) (i8 : Bool) (ort x : Nat) : Nat :=
  instDieWeights s pos x + instDieKv s L B i8 + ws + ort
/-- the fit premise on die `pos` with overhead `ort` and int4 share `x` -/
abbrev instFits (s : Shape) (pos L B : Nat) (i8 : Bool) (ort x : Nat) : Prop := instTotal s pos L B i8 ort x ≤ dieMem
def instXchBw (s : Shape) (rows : Nat) : Nat :=
  sumPos (fun p => hopBw (act s rows) (die p) (die (p + 1))) 3 + tn (logits s rows) (d2h (die 3)) + tn (rows * 4) (h2d (die 0))
def instXch (s : Shape) (rows lam : Nat) : Nat := instXchBw s rows + 8 * lam
/-- MoE expert time per layer when a share x (thousandths) of the streamed slabs is int4: one floor of the
    exact rational 3·D·(T_hot·(1 − x) + T_cold·x) -/
def expCold (D x Thot Tcold : Nat) : Nat := 3 * D * (Thot * (1000 - x) + Tcold * x) / 1000
/-- the same with a rational share nc/nt (the Zipf traffic share of the coldest experts) -/
def expColdZ (D nc nt Thot Tcold : Nat) : Nat := 3 * D * (Thot * (nt - nc) + Tcold * nc) / nt
def instWMoe (s : Shape) (rows x Thot Tcold : Nat) : Nat := tn s.wStream rGemm + 2 * fMoe + expCold (dU rows) x Thot Tcold
def instWMoeZ (s : Shape) (rows nc nt Thot Tcold : Nat) : Nat := tn s.wStream rGemm + 2 * fMoe + expColdZ (dU rows) nc nt Thot Tcold
/-- dense: (1 − x) of the layer bytes at 174.6 and x at the W4 W8-equivalent rate — one floor of the sum -/
def instWDense (s : Shape) (x rW4 : Nat) : Nat :=
  (s.wStream * 10 * (1000 - x) * rW4 + s.wStream * 10 * x * rGemm) / (1000 * rGemm * rW4)
def instW (s : Shape) (rows x Thot Tcold rW4 : Nat) : Nat :=
  if s.moe then instWMoe s rows x Thot Tcold else instWDense s x rW4
def sum4 (f : Nat → Nat) : Nat := f 0 + f 1 + f 2 + f 3
/-- the step of one 4-die instance: per die, layers × (weights + attention + launches); + head + 2 launches
    + the 8-λ exchange + the draft (t > 1). `xs pos` = the int4 share of die pos. -/
def instStep (s : Shape) (L B t : Nat) (xs : Nat → Nat) (Thot Tcold rW4 nl lam : Nat) (i8 : Bool) : Nat :=
  sum4 (fun pos => layers4 s * (instW s (B * t) (xs pos) Thot Tcold rW4 + attnNs s L B t gStream cNative i8 + nl * tLaunch))
  + headNs s + 2 * tLaunch + instXch s (B * t) lam + dNs t lam
/-- the Zipf(1.0) popularity variant: the coldest nc experts carry the traffic share hCold nc / hTot -/
def instStepZ (s : Shape) (L : Nat) (ncs : Nat → Nat) (nt : Nat) (hc : Nat → Nat) (Thot Tcold nl lam : Nat) : Nat :=
  sum4 (fun pos => layers4 s * (instWMoeZ s 1 (hc (ncs pos)) nt Thot Tcold + attnNs s L 1 1 gStream cNative false + nl * tLaunch))
  + headNs s + 2 * tLaunch + instXch s 1 lam
/-- the share vectors alt.py's `min_x` finds (proved minimal below) -/
def xsMoe32k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 182 else 170
def xsMoe128k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 244 else 232
def xsMoe1M : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 827 else 816
def xsMoe128kI8 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 202 else 191
def xsMoe1MI8 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 494 else 482
def xsMoe32kB16 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 494 else 482
def xsDense32k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 376 else if p = 1 then 358 else 332
def xsDense32kI8 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 334 else if p = 1 then 315 else 290
def xsDense128k : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 629 else if p = 1 then 610 else 585
def xsDense128kI8 : Nat → Nat := fun p => if p = 0 ∨ p = 3 then 461 else if p = 1 then 442 else 417
def xsAll : Nat → Nat := fun _ => 1000
/-- the headline instance cell as a function of the W4 core-slab time (MoE 32k, uniform, direct_ser hot tier) -/
def instMoe32k (Tc : Nat) : Nat := instStep moe 32768 1 1 xsMoe32k chainSer Tc rW4W8Ovl 7 lamMid false
def instDense32k (rW4 : Nat) : Nat := instStep dense 32768 1 1 xsDense32k chainSer 0 rW4 6 lamMid false
/-- the measured cold tier -/
def tW4 : Nat := tSlabW4 rW4v

/-! Zipf(1.0) popularity: rank weights 1/r over 256 experts, exact as scaled naturals (D = lcm 1..256) -/
def lcmTo : Nat → Nat
  | 0 => 1
  | n + 1 => Nat.lcm (lcmTo n) (n + 1)
def hSum (D : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => hSum D n + D / (n + 1)
def Dz : Nat := lcmTo 256
def hTot : Nat := hSum Dz 256
/-- the traffic of the coldest nc experts: H(256) − H(256 − nc), scaled by D -/
def hCold (nc : Nat) : Nat := hTot - hSum Dz (256 - nc)
def ncOf (x : Nat) : Nat := 256 * x / 1000

/-! ALT-3: the per-layer persistent megakernel -/
def syncsPerLayer (s : Shape) : Nat := if s.moe then 5 else 4
/-- one cross-core reduction through DDR: 8 partials written + read (f32), x written (f16), x read by 8 cores -/
def reductionBytes (rows d : Nat) : Nat := 8 * rows * d * 4 + 8 * rows * d * 4 + rows * d * 2 + 8 * rows * d * 2
def redNs (s : Shape) (rows : Nat) : Nat := 2 * tn (reductionBytes rows s.d) rGemm
def savedPerLayer (s : Shape) : Nat := (s.nlaunch - 1) * tLaunch
/-- alt.py `alt3`: one launch per layer; + syncs × c_sync + the two reductions' traffic per layer -/
def megaStep (s : Shape) (L csync : Nat) : Nat :=
  today s L 1 1 - s.nL * savedPerLayer s + s.nL * (syncsPerLayer s * csync + redNs s 1)
def megaThresh (s : Shape) : Nat := savedPerLayer s / syncsPerLayer s
def megaThreshExact (s : Shape) : Nat := (savedPerLayer s - redNs s 1) / syncsPerLayer s
/-- the draft token with nl launches (λ = 91 µs) and the verify step (k = 3) -/
def draftTok (nl : Nat) : Nat := draftTokNs lamMid nl
/-- head-aligned QKV packing alone: one launch fewer per layer -/
def headAligned (s : Shape) (L : Nat) : Nat := stepNs s L 1 1 tSlabSer (s.nlaunch - 1) lamMid false
/-- ALT-1 on the fleet: today's step with the expert slab on the direct path -/
def directStep (s : Shape) (L B t chain : Nat) : Nat := stepNs s L B t chain s.nlaunch lamMid false
/-- ALT-3 + ALT-1 (alt.py `[ALT-3+1-moe]`): the megakernel delta applied to the direct-path step -/
def megaDirect (csync : Nat) : Nat :=
  megaStep moe 32768 csync - (today moe 32768 1 1 - directStep moe 32768 1 1 chainSer)
/-- ALT-2 + ALT-3: the instance with one launch per layer plus the sync and reduction terms -/
def instMega (s : Shape) (xs : Nat → Nat) (Tc csync : Nat) : Nat :=
  instStep s 32768 1 1 xs chainSer Tc rW4W8Ovl 1 lamMid false + s.nL * syncsPerLayer s * csync + s.nL * redNs s 1

/-! ALT-4: the quantizing epilogue — as written (magic bias, 8 lane-ops) and as measured (43.7 µs per pass) -/
def quantOps : Nat := 8
def quantElems (s : Shape) : Nat := if s.moe then 3 * s.d + 8 * s.d else 3 * s.d + 53248
def quantPerLayerNs (s : Shape) : Nat := quantElems s * quantOps * 10 / rVecCore
def hostBouncePerLayer (s : Shape) (lam : Nat) : Nat := 4 * (2 * lam + tn (s.d * 2) d2h0 + tn s.d h2d1)
def quantPasses : Nat := 4
/-- the measured pass per token: n_L × 4 × 43.7 µs -/
def quantTok (s : Shape) : Nat := s.nL * quantPasses * cQ
def quantDraft : Nat := 24 * quantPasses * cQ
/-- f16 magic bias: y = q + 1280 ∈ [1024, 2048) has ulp 1; mantissa = y − 1024; its low byte = q mod 256 -/
def magicF16 (q : Int) : Bool :=
  let y := q + 1280
  decide (1024 ≤ y ∧ y < 2048) && decide ((y - 1024) % 256 = q % 256)
def magicF32 (q : Int) : Bool :=
  let y := q + 12582912
  decide (8388608 ≤ y ∧ y < 16777216) && decide (y % 256 = q % 256)
/-- Route-1b class: f16 A × f16 (vector-cast) W through the loader on 8 cores (alt.py `[ALT-4-route1b]`) -/
def route1bRate : Nat := rateT (8 * 64 * MiB) (tn (64 * MiB) rLoader * 2)

/-! ALT-5: two-tier pages — compaction and tail waste -/
def compactionNsPerTokLayer : Nat := tn (16 * 2 * MiB) rGemm / 4096

/-! ALT-6 / ALT-7: K-int8 on the fleet; shared-prefix attention -/
def attnNsK8 (s : Shape) (L B t G cE : Nat) : Nat :=
  max (kvNs s L B G false * 3 / 4) (max (smNs s L B t cE) (mmaNs s L B t))
def stepK8 (s : Shape) (L : Nat) : Nat :=
  s.nL * gemmNs s 1 tSlabSer + s.nL * attnNsK8 s L 1 1 gStream cNative + headNs s
  + (s.nL * s.nlaunch + 2) * tLaunch + Tx s 1 lamMid
def passes (s : Shape) (B : Nat) : Nat := ceilDiv (B * (s.Hq / s.Hkv)) 64
def prefixFull (s : Shape) (L B : Nat) : Nat := tn (s.kvTok * L * B) rGemm
def prefixShared (s : Shape) (L Ls B : Nat) : Nat := tn (s.kvTok * ((L - Ls) * B + Ls * passes s B)) rGemm
def prefixStep (s : Shape) (L Ls B : Nat) : Nat := today s L B 1 - s.nL * (prefixFull s L B - prefixShared s L Ls B)

/-! ALT-9: the dominated families -/
def ksplitSaved : Nat := tn (8 * 128 * KiB - 8 * 16 * KiB) rGemm
def ksplitAdded : Nat := tn (2 * (8 * 32 * KiB)) rGemm
def expertParallel (lam : Nat) : Nat := today moe 32768 1 1 + moe.nL * 2 * lam
/-- the coldest quarter of the experts as int4 on the single 8-die instance (uniform / Zipf traffic share) -/
def hotColdUniform : Nat := today moe 32768 1 1 + moe.nL * (24 * (tSlabSer * 3 + tW4) / 4 - 24 * tSlabSer)
def hotColdZipf : Nat := today moe 32768 1 1 + moe.nL * (24 * (tW4 - tSlabSer) * hCold 64 / hTot)
def tokenDropStep (D : Nat) : Nat := fMoe + D * tSlabSer
def specializationCap : Nat := rGemm / 3
end Alt
end Design

open Measured Design Design.Fleet2 Design.Attn2 Design.Alt

/-! ## Row 32 — baseline identity: every "today" cell is the number fleet.lean / attn.lean fix
    (fleet.lean `T_serial` / `T_spec_dense` / `T_serial_moe_afrac`: 2 362 319 269 / 133 847 319 ns, 0.105 / 1.867;
    attn.lean `T4_t1_32k` / `T4_t1_1M`: 775 778 / 851 470 / 903 650 / 24 605 602 ns) -/
theorem T_alt_shapes : dense.wStream = denseLayerBytes 16384 53248 8 128 ∧ moe.wStream = moeAttnBytes 4096 8 128 ∧
    moe.wRes = moeAttnBytes 4096 8 128 + moeExpertBytes 256 3 4096 ∧ dense.wEmbed = 16384 * 128256 ∧
    moe.wEmbed = 4096 * 128256 ∧ dense.kvTok = 2 * 8 * 128 * 2 ∧ cand moe = moeExpertBytes 256 3 4096 ∧
    cand dense = dense.wStream := by decide
theorem T_alt_baseline_identity :
    today dense 32768 1 1 = 2362319269 ∧ today moe 32768 1 1 = 133847319 ∧
    tpsCard 1000 (today dense 32768 1 1) = 105 ∧ tpsCard 1000 (today moe 32768 1 1) = 1867 ∧
    today moe 131072 1 1 = 198419435 ∧ today moe 1048576 1 1 = 801092387 ∧ today dense 131072 1 1 = 2639056909 ∧
    today dense 32768 1 4 = 2416719328 ∧ today moe 32768 16 1 = 1696701747 ∧ today dense 32768 16 1 = 3746623921 ∧
    todayI8 dense 32768 = 2316196309 ∧ todayI8 moe 1048576 = 456707843 ∧
    stepH 32768 1 gStream cvNat 1 = 775778 ∧ usR 775778 = 776 ∧ stepH 1048576 1 gStream cvNat 1 = 24605602 ∧
    usR 24605602 = 24606 ∧ stepH 32768 1 gStream cvWorst 2 = 851470 ∧ stepH 32768 1 (gPage 65536 500) cvNat 1 = 903650 ∧
    ms2 2362319269 = 236231 ∧ ms2 133847319 = 13384 := by decide

/-! ## Row 1 — the W4 vector path (`[ALT-0-w4v]`): 5.3 GB/s/core of int4 = 42.4 per die = 84.8 W8-equivalent;
    197 844 ns per 1 MiB core-slab; the serial chain AS WRITTEN 386 + 16 + 154 + 25 + 15 = 596 ns per 2 KiB -/
theorem T_alt_w4_rates : rW4v = 53 ∧ 8 * rW4v = 424 ∧ rW4W8Ovl = 848 ∧ tSlabW4 rW4v = 197844 ∧ tW4 = 197844 ∧
    tn (2 * KiB) rW4v = 386 ∧ tn (4 * KiB) rUsS1 = 16 ∧ tn (4 * KiB) rLoader = 154 ∧ cResT / 10 = 25 ∧ cMma = 15 ∧
    pieceSerW = 596 ∧ slabSer pieceSerW = 305152 ∧ rW4W8Ser pieceSerW = 552 ∧ rateT MiB (slabSer pieceSerW) = 34 ∧
    x10 tSlabSer 1 / 10 = 122979 ∧ x10 tW4 tSlabSer = 16 := by decide
/-- CORRECTION (row 1, §2.1, §5 E30): a 2 KiB int4 piece holds 4 096 values, i.e. 8 KiB of f16 (not 4 KiB) and
    two (16,16,128) B fragments (2 048 elements each), so the strictly serial chain is 386 + 32 + 309 + 50 + 30 =
    807 ns per piece: 413 184 ns per core-slab, 40.8 W8-equivalent GB/s per die, 2.5 GB/s/core of int4 -/
theorem T_alt_w4_ser_corrected : 2 * KiB * 2 = 4096 ∧ 4096 * 2 = 8 * KiB ∧ 4096 / (16 * 128) = 2 ∧
    tn (8 * KiB) rUsS1 = 32 ∧ tn (8 * KiB) rLoader = 309 ∧ pieceSerC = 807 ∧ slabSer pieceSerC = 413184 ∧
    rW4W8Ser pieceSerC = 408 ∧ rateT MiB (slabSer pieceSerC) = 25 ∧ pieceSerW < pieceSerC ∧
    tn (8 * KiB) rLoader < tn (2 * KiB) rW4v := by decide

/-! ## Row 2 — the direct-path expert chain (`[ALT-1-chain]`) -/
theorem T_alt_direct_chain : tBDirect = 96089 ∧ tn (64 * KiB) rLoader = 2473 ∧ 32 * cResT / 10 = 812 ∧ aLift = 3285 ∧
    chainSer = 99374 ∧ chainOvl = 96089 ∧ chainG2 = 97731 ∧ mmaExp = 15360 ∧ pct mmaExp tBDirect = 160 ∧
    x10 rGemm 8 = 2182 ∧ mmaExp < tBDirect := by decide

/-! ## Row 3 — the anchor identity (`[ALT-1-rate]`): 8 × chain + F → 167.1 / 172.8 against 135.3, and the whole
    A-lift bracket a ∈ [0, 3 285] stays inside [167.1, 172.8] -/
theorem T_alt_direct_rate : stepExp chainSer = 802992 ∧ rateExp chainSer = 1671 ∧ stepExp chainOvl = 776712 ∧
    rateExp chainOvl = 1728 ∧ rateExp tSlabSer = 1353 ∧ stepExp tSlabSer = 991832 ∧
    pcsUp 1671 1353 = 235 ∧ pcsUp 1728 1353 = 277 ∧ bytesStep = 134217728 := by decide
theorem T_alt_direct_bracket (a : Nat) (h : a ≤ 3285) : 1671 ≤ rateExp (chainA a) ∧ rateExp (chainA a) ≤ 1728 := by
  unfold rateExp rateT stepExp chainA bytesStep tBDirect MiB rGemm fMoe
  constructor
  · rw [Nat.le_div_iff_mul_le (by omega)]; omega
  · apply Nat.le_of_lt_succ
    rw [Nat.div_lt_iff_lt_mul (by omega)]; omega
/-- the ends of the bracket are the two quoted cells, and the rate is monotone in a -/
theorem T_alt_direct_bracket_ends : rateExp (chainA 0) = 1728 ∧ rateExp (chainA 3285) = 1671 ∧ chainA aLift = chainSer ∧
    chainA 0 = chainOvl := by decide
/-- the G = 2 knob (one A lift per expert pair) as a rate: 169.9, +1.6 % over 167.1 in the pcs convention
    (ALTERNATIVES printed +1.7 %, the real time ratio 1.68 % rounded) -/
theorem T_alt_direct_g2 : stepExp chainG2 = 789848 ∧ rateExp chainG2 = 1699 ∧ pcsUp 1699 1671 = 16 ∧
    (chainSer - chainG2) * 1000 / chainG2 = 16 ∧ (chainSer - chainG2) * 10000 / chainG2 = 168 := by decide

/-! ## Row 4 — the 32 KiB drain per expert hides under one expert's DDR time iff R_drain ≥ 0.4 GB/s/core
    (tenths; the exact threshold is 0.341 GB/s, which `rateT` rounds to 0.3 — CORRECTION of the quoted "≥ 0.3":
    at 0.3 the drain takes 109 226 ns > 96 089) -/
theorem T_alt_direct_drain (R : Nat) (hR : 0 < R) : tn (32 * KiB) R ≤ tBDirect ↔ 4 ≤ R := by
  have h1 : tBDirect = 96089 := by decide
  rw [h1]; unfold tn KiB
  rw [← Nat.lt_succ_iff, Nat.div_lt_iff_lt_mul hR]
  omega
theorem T_alt_direct_drain_cells : tn (32 * KiB) 3 = 109226 ∧ tn (32 * KiB) 4 = 81920 ∧ rateT (32 * KiB) tBDirect = 3 ∧
    (32 * KiB * 1000) / tBDirect = 341 ∧ rDrainMeas / 4 = 382 ∧ tn (32 * KiB) rDrainMeas = 214 := by decide

/-! ## Row 5 — the fleet with T_slab = 99 374 / 96 089 (`[ALT-1-fleet-*]`): MoE 32k 117.98 / 115.77 ms → 2.118 /
    2.159 (+13.4 / +15.6 %); 128k 1.369 / 1.386; 1M 0.318 / 0.319; B = 16 2.772; DESIGN-4's ping-pong branch
    (116.40 ms) is reproduced within 1.4 % -/
theorem T_alt_direct_fleet :
    directStep moe 32768 1 1 chainSer = 117984759 ∧ tpsCard 1000 117984759 = 2118 ∧ pcsUp 2118 1867 = 134 ∧
    directStep moe 32768 1 1 chainOvl = 115777239 ∧ tpsCard 1000 115777239 = 2159 ∧ pcsUp 2159 1867 = 156 ∧
    directStep moe 131072 1 1 chainSer = 182556875 ∧ tpsCard 1000 182556875 = 1369 ∧ pcsUp 1369 1259 = 87 ∧
    directStep moe 131072 1 1 chainOvl = 180349355 ∧ tpsCard 1000 180349355 = 1386 ∧
    directStep moe 1048576 1 1 chainSer = 785229827 ∧ tpsCard 1000 785229827 = 318 ∧ pcsUp 318 312 = 19 ∧
    directStep moe 1048576 1 1 chainOvl = 783022307 ∧ tpsCard 1000 783022307 = 319 ∧
    directStep moe 32768 16 1 chainSer = 1442900787 ∧ tpsCard 16000 1442900787 = 2772 ∧
    tpsCard 16000 (today moe 32768 16 1) = 2357 ∧ ms2 117984759 = 11798 ∧ ms2 115777239 = 11577 ∧
    pct (117984759 - 116399511) 116399511 = 14 ∧ directStep moe 32768 1 1 tSlabSer = today moe 32768 1 1 := by decide
/-- the direct-path step is the serial step minus 8·D·(122 979 − chain) per layer: linear in the chain time -/
theorem T_alt_direct_fleet_form (chain : Nat) (h : chain ≤ tSlabSer) :
    directStep moe 32768 1 1 chain = today moe 32768 1 1 - 28 * 24 * (tSlabSer - chain) := by
  have hs : tSlabSer = 122979 ∧ moe.nL = 28 ∧ attnNs moe 32768 1 1 gStream cNative false = 768715 ∧ headNs moe = 3008800 ∧
      Tx moe 1 lamMid = 1480367 ∧ tn moe.wStream rGemm = 240223 ∧ dU 1 = 8 ∧ moe.nlaunch = 7 ∧ moe.slabs = 3 ∧
      dNs 1 lamMid = 0 ∧ tLaunch = 91000 ∧ fMoe = 8000 := by decide
  have hm : ∀ c, gemmNs moe 1 c = tn moe.wStream rGemm + 2 * fMoe + moe.slabs * dU 1 * c := fun _ => rfl
  unfold directStep today Fleet2.stepNs
  rw [hm, hm, hs.2.2.1, hs.2.2.2.1, hs.2.2.2.2.1, hs.2.2.2.2.2.1, hs.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.1,
    hs.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.2.2, hs.2.1, hs.1]
  omega

/-! ## Row 6 — the 4-die fit: weights(x) is non-increasing in the int4 share, so the minimal x is an iff -/
theorem T_alt_fit_monotone (s : Shape) (pos x y : Nat) (h : x ≤ y) :
    instDieWeights s pos y ≤ instDieWeights s pos x := by
  unfold instDieWeights
  have h1 : cand s * x / 2000 ≤ cand s * y / 2000 := Nat.div_le_div_right (Nat.mul_le_mul_left _ h)
  have h2 : s.wRes - cand s * y / 2000 ≤ s.wRes - cand s * x / 2000 := Nat.sub_le_sub_left h1 _
  have _h3 := Nat.mul_le_mul_left (layers4 s) h2
  omega
/-- the per-die totals as explicit functions of x and the overhead (kernel-checked unfoldings) -/
theorem instTotal_moe32k_0 (ort x : Nat) : instTotal moe 0 32768 1 false ort x =
    7 * (12926844928 - 12884901888 * x / 2000) + 525336576 + 0 + 0 + 939524096 + 67108864 + ort := rfl
theorem instTotal_moe32k_1 (ort x : Nat) : instTotal moe 1 32768 1 false ort x =
    7 * (12926844928 - 12884901888 * x / 2000) + 0 + 0 + 0 + 939524096 + 67108864 + ort := rfl
theorem instTotal_moe32k_2 (ort x : Nat) : instTotal moe 2 32768 1 false ort x =
    7 * (12926844928 - 12884901888 * x / 2000) + 0 + 0 + 0 + 939524096 + 67108864 + ort := rfl
theorem instTotal_moe32k_3 (ort x : Nat) : instTotal moe 3 32768 1 false ort x =
    7 * (12926844928 - 12884901888 * x / 2000) + 0 + 525336576 + 0 + 939524096 + 67108864 + ort := rfl
theorem instTotal_dense32k_0 (ort x : Nat) : instTotal dense 0 32768 1 false ort x =
    30 * (3187671040 - 3187671040 * x / 2000) + 2101346304 + 0 + 0 + 4026531840 + 67108864 + ort := rfl
theorem instTotal_dense32k_1 (ort x : Nat) : instTotal dense 1 32768 1 false ort x =
    30 * (3187671040 - 3187671040 * x / 2000) + 0 + 0 + 1201326592 + 4026531840 + 67108864 + ort := rfl
theorem instTotal_dense32k_2 (ort x : Nat) : instTotal dense 2 32768 1 false ort x =
    30 * (3187671040 - 3187671040 * x / 2000) + 0 + 0 + 0 + 4026531840 + 67108864 + ort := rfl
theorem instTotal_dense32k_3 (ort x : Nat) : instTotal dense 3 32768 1 false ort x =
    30 * (3187671040 - 3187671040 * x / 2000) + 0 + 2101346304 + 0 + 4026531840 + 67108864 + ort := rfl
/-- MoE 32k: die 0 / 3 fit iff x ≥ 182 ‰, dies 1 / 2 iff x ≥ 170 ‰ (for every x, at the 2 GiB overhead) -/
theorem T_alt_fit_minx_moe_32k (x : Nat) :
    (instFits moe 0 32768 1 false oRt x ↔ 182 ≤ x) ∧ (instFits moe 1 32768 1 false oRt x ↔ 170 ≤ x) ∧
    (instFits moe 2 32768 1 false oRt x ↔ 170 ≤ x) ∧ (instFits moe 3 32768 1 false oRt x ↔ 182 ≤ x) := by
  unfold instFits
  rw [instTotal_moe32k_0, instTotal_moe32k_1, instTotal_moe32k_2, instTotal_moe32k_3]
  unfold dieMem dieMemGB GB oRt GiB
  omega
/-- dense 32k: 376 / 358 / 332 / 376 ‰ -/
theorem T_alt_fit_minx_dense_32k (x : Nat) :
    (instFits dense 0 32768 1 false oRt x ↔ 376 ≤ x) ∧ (instFits dense 1 32768 1 false oRt x ↔ 358 ≤ x) ∧
    (instFits dense 2 32768 1 false oRt x ↔ 332 ≤ x) ∧ (instFits dense 3 32768 1 false oRt x ↔ 376 ≤ x) := by
  unfold instFits
  rw [instTotal_dense32k_0, instTotal_dense32k_1, instTotal_dense32k_2, instTotal_dense32k_3]
  unfold dieMem dieMemGB GB oRt GiB
  omega
/-- the other fit tables, as the minimal-x cells (fit at x, not at x − 1) -/
theorem T_alt_fit_minx_cells :
    instFits moe 0 131072 1 false oRt 244 ∧ ¬ instFits moe 0 131072 1 false oRt 243 ∧
    instFits moe 1 131072 1 false oRt 232 ∧ ¬ instFits moe 1 131072 1 false oRt 231 ∧
    instFits moe 0 1048576 1 false oRt 827 ∧ ¬ instFits moe 0 1048576 1 false oRt 826 ∧
    instFits moe 1 1048576 1 false oRt 816 ∧ ¬ instFits moe 1 1048576 1 false oRt 815 ∧
    instFits dense 0 131072 1 false oRt 629 ∧ ¬ instFits dense 0 131072 1 false oRt 628 ∧
    instFits dense 1 131072 1 false oRt 610 ∧ ¬ instFits dense 1 131072 1 false oRt 609 ∧
    instFits dense 2 131072 1 false oRt 585 ∧ ¬ instFits dense 2 131072 1 false oRt 584 ∧
    instFits dense 0 32768 1 true oRt 334 ∧ ¬ instFits dense 0 32768 1 true oRt 333 ∧
    instFits dense 1 32768 1 true oRt 315 ∧ ¬ instFits dense 1 32768 1 true oRt 314 ∧
    instFits dense 2 32768 1 true oRt 290 ∧ ¬ instFits dense 2 32768 1 true oRt 289 ∧
    instFits dense 0 131072 1 true oRt 461 ∧ ¬ instFits dense 0 131072 1 true oRt 460 ∧
    instFits dense 1 131072 1 true oRt 442 ∧ ¬ instFits dense 1 131072 1 true oRt 441 ∧
    instFits dense 2 131072 1 true oRt 417 ∧ ¬ instFits dense 2 131072 1 true oRt 416 ∧
    instFits moe 0 131072 1 true oRt 202 ∧ ¬ instFits moe 0 131072 1 true oRt 201 ∧
    instFits moe 1 131072 1 true oRt 191 ∧ ¬ instFits moe 1 131072 1 true oRt 190 ∧
    instFits moe 0 1048576 1 true oRt 494 ∧ ¬ instFits moe 0 1048576 1 true oRt 493 ∧
    instFits moe 1 1048576 1 true oRt 482 ∧ ¬ instFits moe 1 1048576 1 true oRt 481 ∧
    instFits moe 0 32768 16 false oRt 494 ∧ ¬ instFits moe 0 32768 16 false oRt 493 ∧
    instFits moe 1 32768 16 false oRt 482 ∧ ¬ instFits moe 1 32768 16 false oRt 481 := by decide
/-- dense 1M cannot replicate: the KV alone (128.8 GB f16 / 64.4 GB int8 per 4-die position) exceeds the die
    for every share x ≤ 1 and every overhead -/
theorem T_alt_fit_dense_1M_infeasible (pos x ort : Nat) (hx : x ≤ 1000) :
    ¬ instFits dense pos 1048576 1 false ort x ∧ ¬ instFits dense pos 1048576 1 true ort x := by
  have hk : instDieKv dense 1048576 1 false = 128849018880 ∧ instDieKv dense 1048576 1 true = 64424509440 ∧
      dieMem = 86000000000 := by decide
  have hw : layers4 dense * (dense.wRes - cand dense * x / 2000) = 30 * (3187671040 - 3187671040 * x / 2000) := rfl
  unfold instFits instTotal instDieWeights
  rw [hk.1, hk.2.1, hk.2.2, hw]
  omega
/-- the minimal x at 4 dies versus DESIGN-4's T_min_dies (5 dies for int8): all-W4 candidates leave 49.9 / 45.9 GB -/
theorem T_alt_fit_allw4 : gb1 (instDieWeights dense 0 1000) = 499 ∧ gb1 (instDieWeights dense 3 1000) = 499 ∧
    gb1 (instDieWeights moe 0 1000) = 459 ∧ gb1 (instDieWeights moe 3 1000) = 459 := by decide

/-! ## Row 7 — totals, margins and the overhead sensitivity (overhead as the hypothesis variable `ort`) -/
/-- the fit on die 0 (MoE 32k) for every overhead and share: an iff between `ort` and x -/
theorem T_alt_fit_overhead_moe (ort x : Nat) (hx : x ≤ 1000) :
    instFits moe 0 32768 1 false ort x ↔ 6019884032 + ort ≤ 7 * (12884901888 * x / 2000) := by
  unfold instFits; rw [instTotal_moe32k_0]; unfold dieMem dieMemGB GB; omega
theorem T_alt_fit_overhead_dense (ort x : Nat) (hx : x ≤ 1000) :
    instFits dense 0 32768 1 false ort x ↔ 15825118208 + ort ≤ 30 * (3187671040 * x / 2000) := by
  unfold instFits; rw [instTotal_dense32k_0]; unfold dieMem dieMemGB GB; omega
/-- +1 GB of overhead moves the minimal share by +22 ‰ (MoE) / +21 ‰ (dense, die 0) — "2.2 % / 2.1 %" -/
theorem T_alt_fit_dx_per_gb (x : Nat) :
    (instFits moe 0 32768 1 false (oRt + GB) x ↔ 204 ≤ x) ∧ (instFits moe 1 32768 1 false (oRt + GB) x ↔ 192 ≤ x) ∧
    (instFits dense 0 32768 1 false (oRt + GB) x ↔ 397 ≤ x) ∧ (instFits dense 1 32768 1 false (oRt + GB) x ↔ 378 ≤ x) ∧
    (instFits dense 2 32768 1 false (oRt + GB) x ↔ 353 ≤ x) := by
  unfold instFits
  rw [instTotal_moe32k_0, instTotal_moe32k_1, instTotal_dense32k_0, instTotal_dense32k_1, instTotal_dense32k_2]
  unfold dieMem dieMemGB GB oRt GiB
  omega
/-- CORRECTION (row 7, §2.1): the per-die margin at the minimal x is 24–40 MB (MoE 32k) and 3–45 MB (dense 32k),
    not "0.1 GB" — that figure was 86.0 − 85.9 in floored tenths; the totals do print 85.9 on every die -/
theorem T_alt_fit_margin :
    dieMem - instTotal moe 0 32768 1 false oRt 182 = 40314817 ∧ dieMem - instTotal moe 1 32768 1 false oRt 170 = 24485516 ∧
    dieMem - instTotal moe 2 32768 1 false oRt 170 = 24485516 ∧ dieMem - instTotal moe 3 32768 1 false oRt 182 = 40314817 ∧
    dieMem - instTotal dense 0 32768 1 false oRt 376 = 5862794 ∧ dieMem - instTotal dense 1 32768 1 false oRt 358 = 45211336 ∧
    dieMem - instTotal dense 2 32768 1 false oRt 332 = 3346208 ∧ dieMem - instTotal dense 3 32768 1 false oRt 376 = 5862794 ∧
    dieMem - instTotal moe 0 1048576 1 false oRt 827 = 2733854 ∧ dieMem - instTotal moe 1 1048576 1 false oRt 816 = 32001710 ∧
    gb1 (instTotal moe 0 32768 1 false oRt 182) = 859 ∧ gb1 (instTotal moe 1 32768 1 false oRt 170) = 859 ∧
    gb1 (instTotal dense 0 32768 1 false oRt 376) = 859 ∧ gb1 (instTotal dense 2 32768 1 false oRt 332) = 859 ∧
    gb1 (instDieWeights moe 0 182) = 828 ∧ gb1 (instDieKv moe 32768 1 false) = 9 ∧ gb1 (ws + oRt) = 22 ∧
    gb1 dieMem = 860 ∧ 40314817 < 100000000 := by decide
/-- each 1 % of x costs 0.66 ms of the MoE 32k instance step (24 × 985 ns × 28 layers); shipping x + 3 % (≈ 1 GB
    of margin) gives 130.88 ms → 3.820 -/
theorem T_alt_fit_ship_margin :
    instStep moe 32768 1 1 (fun p => xsMoe32k p + 10) chainSer tW4 rW4W8Ovl 7 lamMid false = 129561473 ∧
    129561473 - 128899749 = 661724 ∧ 24 * 28 * 985 = 661920 ∧ ms2 661724 = 66 ∧ ms2 661920 = 66 ∧
    instStep moe 32768 1 1 (fun p => xsMoe32k p + 30) chainSer tW4 rW4W8Ovl 7 lamMid false = 130884921 ∧
    tpsInst 1000 130884921 = 3820 ∧ ms2 130884921 = 13088 := by decide

/-! ## Rows 8–10 — the instance cells (`[ALT-2-*]`) -/
theorem T_alt_rep_moe_32k :
    instMoe32k tW4 = 128899749 ∧ ms2 128899749 = 12889 ∧ tpsInst 1000 128899749 = 3878 ∧ pcsUp 3878 1867 = 1077 ∧
    sum4 (fun p => 7 * instW moe 1 (xsMoe32k p) chainSer tW4 rW4W8Ovl) + headNs moe = 88608594 ∧
    28 * attnNs moe 32768 1 1 gStream cNative false = 21524020 ∧ (28 * 7 + 2) * tLaunch = 18018000 ∧
    instXch moe 1 lamMid = 749135 ∧ instXchBw moe 1 = 21135 ∧ 88608594 + 21524020 + 18018000 + 749135 = 128899749 ∧
    instMoe32k (slabSer pieceSerW) = 141591295 ∧ tpsInst 1000 141591295 = 3531 ∧ pcsUp 3531 1867 = 891 ∧
    instMoe32k (slabSer pieceSerC) = 154368451 ∧ tpsInst 1000 154368451 = 3239 ∧ pcsUp 3239 1867 = 734 ∧
    instStep moe 32768 1 1 xsMoe32k tSlabSer tW4 rW4W8Ovl 7 lamMid false = 141970513 ∧ tpsInst 1000 141970513 = 3521 ∧
    pcsUp 3521 1867 = 885 ∧ 128899749 < today moe 32768 1 1 := by decide
theorem T_alt_rep_dense_32k :
    instDense32k rW4W8Ovl = 3197944073 ∧ ms2 3197944073 = 319794 ∧ tpsInst 1000 3197944073 = 156 ∧ pcsUp 156 105 = 485 ∧
    sum4 (fun p => 30 * instW dense 1 (xsDense32k p) chainSer 0 rW4W8Ovl) + headNs dense = 3039240102 ∧
    120 * attnNs dense 32768 1 1 gStream cNative false = 92245800 ∧ (120 * 6 + 2) * tLaunch = 65702000 ∧
    instXch dense 1 lamMid = 756171 ∧
    instDense32k (rW4W8Ser pieceSerW) = 4069944713 ∧ tpsInst 1000 4069944713 = 122 ∧ pcsUp 122 105 = 161 ∧
    instDense32k (rW4W8Ser pieceSerC) = 4951649663 ∧ tpsInst 1000 4951649663 = 100 ∧ pcsDown 100 105 = 47 ∧
    instStep dense 32768 1 1 xsDense32kI8 chainSer 0 rW4W8Ovl 6 lamMid true = 3053800463 ∧ tpsInst 1000 3053800463 = 163 ∧
    instStep dense 32768 1 4 xsDense32k chainSer 0 rW4W8Ovl 6 lamMid false = 3252305316 ∧ tau 700 3 = 2533 ∧
    tpsInst 2533 3252305316 = 389 ∧ tpsCard 2533 (today dense 32768 1 4) = 262 ∧ pcsUp 389 262 = 484 ∧
    pct (3197944073 - 2362319269) 2362319269 = 354 := by decide
theorem T_alt_rep_cells :
    instStep moe 131072 1 1 xsMoe128k chainSer tW4 rW4W8Ovl 7 lamMid false = 197574523 ∧ tpsInst 1000 197574523 = 2530 ∧
    pcsUp 2530 1259 = 1009 ∧
    instStep moe 1048576 1 1 xsMoe1M chainSer tW4 rW4W8Ovl 7 lamMid false = 838858747 ∧ tpsInst 1000 838858747 = 596 ∧
    pcsUp 596 312 = 910 ∧
    instStep dense 131072 1 1 xsDense128k chainSer 0 rW4W8Ovl 6 lamMid false = 4061065823 ∧ tpsInst 1000 4061065823 = 123 ∧
    tpsCard 1000 (today dense 131072 1 1) = 94 ∧ pcsUp 123 94 = 308 ∧
    instStep dense 131072 1 1 xsDense128k chainSer 0 (rW4W8Ser pieceSerW) 6 lamMid false = 5544434423 ∧
    tpsInst 1000 5544434423 = 90 ∧ pcsDown 90 94 = 42 ∧
    instStep dense 131072 1 1 xsDense128k chainSer 0 (rW4W8Ser pieceSerC) 6 lamMid false = 7044311063 ∧
    tpsInst 1000 7044311063 = 70 ∧ pcsDown 70 94 = 255 ∧
    instStep moe 32768 16 1 xsMoe32kB16 chainSer tW4 rW4W8Ovl 7 lamMid false = 1958790755 ∧ tpsInst 16000 1958790755 = 4084 ∧
    pcsUp 4084 2357 = 732 ∧
    instStep moe 131072 1 1 xsMoe128k chainSer (slabSer pieceSerW) rW4W8Ovl 7 lamMid false = 214736927 ∧
    tpsInst 1000 214736927 = 2328 ∧
    instStep moe 131072 1 1 xsMoe128k chainSer (slabSer pieceSerC) rW4W8Ovl 7 lamMid false = 232015153 ∧
    tpsInst 1000 232015153 = 2155 ∧ pcsUp 2155 1259 = 711 ∧
    instStep moe 1048576 1 1 xsMoe1M chainSer (slabSer pieceSerC) rW4W8Ovl 7 lamMid false = 957736765 ∧
    tpsInst 1000 957736765 = 522 ∧ pcsUp 522 312 = 673 := by decide

/-! ## Row 11 — T_instance_gain: two 4-die instances beat the 8-die chain iff the W4 core-slab time ≤ 1 371 124 ns
    (an unpack rate ≥ 0.8 GB/s/core of int4), for every T_cold; the measured 5.3 GB/s (197 844 ns) instantiates it -/
theorem instW_moe (rows x Thot Tcold rW4 : Nat) : instW moe rows x Thot Tcold rW4 = instWMoe moe rows x Thot Tcold := rfl
/-- the headline instance step is affine in the two cold-tier terms: 50 474 199 + 14·e(182) + 14·e(170) -/
theorem T_instance_form (Tc : Nat) :
    instMoe32k Tc = 50474199 + 14 * expCold 8 182 99374 Tc + 14 * expCold 8 170 99374 Tc := by
  have hs : attnNs moe 32768 1 1 gStream cNative false = 768715 ∧ headNs moe = 3008800 ∧ instXch moe 1 lamMid = 749135 ∧
      tn moe.wStream rGemm = 240223 ∧ dU 1 = 8 ∧ layers4 moe = 7 ∧ tLaunch = 91000 ∧ fMoe = 8000 ∧ chainSer = 99374 ∧
      dNs 1 lamMid = 0 ∧ xsMoe32k 0 = 182 ∧ xsMoe32k 1 = 170 ∧ xsMoe32k 2 = 170 ∧ xsMoe32k 3 = 182 := by decide
  unfold instMoe32k instStep sum4
  dsimp only
  simp only [Nat.mul_one, instW_moe]
  unfold instWMoe
  simp only [hs.1, hs.2.1, hs.2.2.1, hs.2.2.2.1, hs.2.2.2.2.1, hs.2.2.2.2.2.1, hs.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.1,
    hs.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.2.2.1,
    hs.2.2.2.2.2.2.2.2.2.2.2.2.1, hs.2.2.2.2.2.2.2.2.2.2.2.2.2]
  omega
theorem T_instance_gain (Tc : Nat) :
    tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k Tc) ↔ Tc ≤ 1371124 := by
  have h0 : tpsCard 1000 (today moe 32768 1 1) = 1867 := by decide
  rw [h0, T_instance_form Tc]
  unfold tpsInst expCold
  rw [Nat.lt_iff_add_one_le, Nat.le_div_iff_mul_le (by omega)]
  omega
/-- both sides of the break-even, and the measured premise instantiated: 197 844 ns is 6.9× inside (6.6× in rate),
    the corrected serial chain (413 184) 3.3× inside, the as-written one 4.4× -/
theorem T_instance_gain_measured :
    tpsInst 1000 (instMoe32k 1371124) = 1868 ∧ tpsInst 1000 (instMoe32k 1371125) = 1867 ∧ rateT MiB 1371124 = 8 ∧
    tW4 ≤ 1371124 ∧ x10 1371124 tW4 = 69 ∧ x10 rW4v 8 = 66 ∧ slabSer pieceSerC ≤ 1371124 ∧ x10 1371124 (slabSer pieceSerC) = 33 ∧
    slabSer pieceSerW ≤ 1371124 ∧ x10 1371124 (slabSer pieceSerW) = 44 ∧
    tSlabW4 40 = 262144 ∧ instMoe32k 262144 = 136504647 ∧ tpsInst 1000 136504647 = 3662 ∧
    tSlabW4 30 = 349525 ∧ instMoe32k 349525 = 146839377 ∧ tpsInst 1000 146839377 = 3405 := by decide
/-- with the MEASURED A-quantization pass on both sides (4 × 43.7 µs per layer) the break-even moves to
    1 412 631 ns (0.7 GB/s/core; the measured tier 7.1× inside) and the cell is 3.737 vs 1.801 (+107.4 %) -/
theorem T_instance_gain_q (Tc : Nat) :
    tpsCard 1000 (today moe 32768 1 1 + quantTok moe) < tpsInst 1000 (instMoe32k Tc + quantTok moe) ↔ Tc ≤ 1412631 := by
  have h0 : tpsCard 1000 (today moe 32768 1 1 + quantTok moe) = 1801 ∧ quantTok moe = 4894400 := by decide
  rw [h0.1, h0.2, T_instance_form Tc]
  unfold tpsInst expCold
  rw [Nat.lt_iff_add_one_le, Nat.le_div_iff_mul_le (by omega)]
  omega
theorem T_instance_gain_q_cells : tpsInst 1000 (instMoe32k tW4 + quantTok moe) = 3737 ∧ pcsUp 3737 1801 = 1074 ∧
    tpsInst 1000 (instMoe32k 1412631 + quantTok moe) = 1802 ∧ tpsInst 1000 (instMoe32k 1412632 + quantTok moe) = 1801 ∧
    rateT MiB 1412631 = 7 ∧ x10 1412631 tW4 = 71 ∧ slabSer pieceSerC ≤ 1412631 ∧
    tpsInst 1000 (instDense32k rW4W8Ovl + quantTok dense) = 155 ∧ tpsCard 1000 (today dense 32768 1 1 + quantTok dense) = 104 ∧
    pcsUp 155 104 = 490 := by decide
/-- H10 as a hypothesis variable: with the second instance running at a concurrency efficiency η (thousandths)
    the verdict needs only η ≥ 482 ‰; the measured 995 ‰ gives 3.859 -/
theorem T_instance_gain_h10 (eta : Nat) :
    tpsCard 1000 (today moe 32768 1 1) < tpsInstEta 1000 (instMoe32k tW4) eta ↔ 482 ≤ eta := by
  have h : tpsCard 1000 (today moe 32768 1 1) = 1867 ∧ instMoe32k tW4 = 128899749 := by decide
  rw [h.1, h.2]; unfold tpsInstEta; omega
theorem T_instance_gain_h10_cells : tpsInstEta 1000 (instMoe32k tW4) etaH10 = 3859 ∧ tpsInstEta 1000 (instMoe32k tW4) 1000 = 3878 ∧
    tpsInstEta 1000 (instMoe32k tW4) 482 = 1869 ∧ tpsInstEta 1000 (instMoe32k tW4) 481 = 1865 := by decide

/-! ## Row 12 — all-W4 replication and the hot/cold tier on the single 8-die fleet -/
theorem T_alt_rep_dominates_allw4 :
    instStep moe 32768 1 1 xsAll chainSer tW4 rW4W8Ovl 7 lamMid false = 183425367 ∧ tpsInst 1000 183425367 = 2725 ∧
    2725 < 3878 ∧ pct (3878 - 2725) 2725 = 423 := by decide
theorem T_alt_hotcold_loses : hotColdUniform = 146424639 ∧ tpsCard 1000 146424639 = 1707 ∧ pcsDown 1707 1867 = 85 ∧
    hotColdZipf = 136205171 ∧ tpsCard 1000 136205171 = 1835 ∧ pcsDown 1835 1867 = 17 ∧
    24 * (tSlabSer * 3 + tW4) / 4 - 24 * tSlabSer = 449190 ∧ today moe 32768 1 1 < hotColdZipf := by decide +kernel

/-! ## Row 13 — Zipf(1.0) traffic shares as exact scaled naturals: the coldest 10 / 25 / 50 / 75 % of 256 experts
    carry 1.7 / 4.7 / 11.3 / 22.5 % (EMPIRICAL-class family, H9; the arithmetic is exact: D = lcm(1..256)) -/
theorem T_alt_zipf_divisible : ∀ r, r < 257 → 0 < r → Dz % r = 0 := by decide +kernel
theorem T_alt_zipf_share : pct (hCold 25) hTot = 17 ∧ pct (hCold 64) hTot = 47 ∧ pct (hCold 128) hTot = 113 ∧
    pct (hCold 192) hTot = 225 ∧ ncOf 100 = 25 ∧ ncOf 250 = 64 ∧ ncOf 500 = 128 ∧ ncOf 750 = 192 ∧
    ncOf 182 = 46 ∧ ncOf 170 = 43 ∧ pct (hCold 46) hTot = 32 ∧ pct (hCold 43) hTot = 30 := by decide +kernel
theorem T_alt_rep_zipf :
    instStepZ moe 32768 (fun p => ncOf (xsMoe32k p)) hTot hCold chainSer tW4 7 lamMid = 119312535 ∧
    tpsInst 1000 119312535 = 4190 ∧ pcsUp 4190 1867 = 1244 ∧
    instStepZ moe 131072 (fun p => ncOf (xsMoe128k p)) hTot hCold chainSer tW4 7 lamMid = 184732561 ∧
    tpsInst 1000 184732561 = 2706 ∧
    instStepZ moe 1048576 (fun p => ncOf (xsMoe1M p)) hTot hCold chainSer tW4 7 lamMid = 802839295 ∧
    tpsInst 1000 802839295 = 622 := by decide +kernel

/-! ## Row 14 — combinations -/
theorem T_alt_combos : megaDirect 5000 = 103504447 ∧ tpsCard 1000 103504447 = 2415 ∧ pcsUp 2415 1867 = 293 ∧
    instMega moe xsMoe32k tW4 5000 = 114419437 ∧ tpsInst 1000 114419437 = 4369 ∧ pcsUp 4369 1867 = 1340 ∧
    instMega dense xsDense32k 0 5000 = 3147590633 ∧ tpsInst 1000 3147590633 = 158 ∧ pcsUp 158 105 = 504 ∧
    instStep moe 131072 1 1 xsMoe128kI8 chainSer tW4 rW4W8Ovl 7 lamMid true = 151780327 ∧ tpsInst 1000 151780327 = 3294 ∧
    todayI8 moe 131072 = 155371367 ∧ tpsCard 1000 155371367 = 1609 ∧
    instStep moe 1048576 1 1 xsMoe1MI8 chainSer tW4 rW4W8Ovl 7 lamMid true = 472405891 ∧ tpsInst 1000 472405891 = 1058 ∧
    tpsCard 1000 (todayI8 moe 1048576) = 547 ∧ pcsUp 1058 547 = 934 ∧ pcsUp 1058 312 = 2391 := by decide +kernel

/-! ## Rows 15–18 — the per-layer persistent megakernel (`[ALT-3-*]`) -/
theorem T_alt_mega_savings : savedPerLayer dense = 455000 ∧ dense.nL * savedPerLayer dense = 54600000 ∧
    savedPerLayer moe = 546000 ∧ moe.nL * savedPerLayer moe = 15288000 ∧
    reductionBytes 1 16384 = 1343488 ∧ tn 1343488 rGemm = 7694 ∧ redNs dense 1 = 15388 ∧ dense.nL * redNs dense 1 = 1846560 ∧
    reductionBytes 1 4096 = 335872 ∧ redNs moe 1 = 3846 ∧ moe.nL * redNs moe 1 = 107688 ∧
    dense.nL * syncsPerLayer dense = 480 ∧ moe.nL * syncsPerLayer moe = 140 ∧
    ms2 54600000 = 5460 ∧ ms2 15288000 = 1528 ∧ ms2 1846560 = 184 ∧ ms2 107688 = 10 := by decide
/-- Realized-launch adjudication: the megakernel's launch savings at tLaunchRealized = 36 µs — dense 180 µs per
    layer (21.60 ms per token), MoE 216 µs (6.048 ms). Net of 20 µs crossings + reduction traffic the prize is
    +10.15 ms dense (0.44 % of the 2319 ms step) / +3.15 ms MoE (2.6 % of 121.46 ms): the megakernel case rests
    on the measured sub-µs cross-core sync, not on launch serialization. -/
theorem T_alt_mega_savings_realized :
    (dense.nlaunch - 1) * tLaunchRealized = 180000 ∧ dense.nL * ((dense.nlaunch - 1) * tLaunchRealized) = 21600000 ∧
    (moe.nlaunch - 1) * tLaunchRealized = 216000 ∧ moe.nL * ((moe.nlaunch - 1) * tLaunchRealized) = 6048000 := by decide
/-- T_megakernel: the megakernel pays iff c_sync ≤ 109 903 ns (dense; a TIE at exactly 109 903 — the strict form is
    ≤ 109 902) / 108 430 ns (MoE) net of the reduction traffic — both directions, for every c_sync -/
theorem T_megakernel_dense (c : Nat) :
    (megaStep dense 32768 c ≤ today dense 32768 1 1 ↔ c ≤ 109903) ∧ (megaStep dense 32768 c < today dense 32768 1 1 ↔ c ≤ 109902) := by
  have h : today dense 32768 1 1 = 2362319269 ∧ dense.nL = 120 ∧ savedPerLayer dense = 455000 ∧
      syncsPerLayer dense = 4 ∧ redNs dense 1 = 15388 := by decide
  unfold megaStep
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2]
  omega
theorem T_megakernel_moe (c : Nat) : megaStep moe 32768 c < today moe 32768 1 1 ↔ c ≤ 108430 := by
  have h : today moe 32768 1 1 = 133847319 ∧ moe.nL = 28 ∧ savedPerLayer moe = 546000 ∧
      syncsPerLayer moe = 5 ∧ redNs moe 1 = 3846 := by decide
  unfold megaStep
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2]
  omega
/-- launch savings only: 113 750 / 109 200 ns; the quoted "≤ 109 µs / 114 µs" and "≤ 108 µs" are these two -/
theorem T_alt_mega_threshold_cells : megaThresh dense = 113750 ∧ megaThreshExact dense = 109903 ∧
    megaThresh moe = 109200 ∧ megaThreshExact moe = 108430 ∧ usR 109903 = 110 ∧ usR 108430 = 108 ∧
    megaStep moe 32768 108430 < today moe 32768 1 1 ∧ ¬ megaStep moe 32768 108431 < today moe 32768 1 1 ∧
    megaStep dense 32768 109903 = today dense 32768 1 1 ∧ megaStep dense 32768 109902 < today dense 32768 1 1 ∧
    ¬ megaStep dense 32768 109904 ≤ today dense 32768 1 1 ∧
    108430 / 2000 = 54 ∧ 108430 / 20000 = 5 := by decide
theorem T_alt_mega_cells :
    megaStep dense 32768 0 = 2309565829 ∧ megaStep dense 32768 2000 = 2310525829 ∧ tpsCard 1000 2310525829 = 108 ∧
    megaStep dense 32768 5000 = 2311965829 ∧ tpsCard 1000 2311965829 = 108 ∧
    megaStep dense 32768 20000 = 2319165829 ∧ tpsCard 1000 2319165829 = 107 ∧ pcsUp 108 105 = 28 ∧ pcsUp 107 105 = 19 ∧
    megaStep moe 32768 0 = 118667007 ∧ tpsCard 1000 118667007 = 2106 ∧
    megaStep moe 32768 2000 = 118947007 ∧ tpsCard 1000 118947007 = 2101 ∧ pcsUp 2101 1867 = 125 ∧
    megaStep moe 32768 5000 = 119367007 ∧ tpsCard 1000 119367007 = 2094 ∧ pcsUp 2094 1867 = 121 ∧
    megaStep moe 32768 20000 = 121467007 ∧ tpsCard 1000 121467007 = 2058 ∧ pcsUp 2058 1867 = 102 ∧
    ms2 2310525829 = 231052 ∧ ms2 118947007 = 11894 := by decide
/-- Row 17: the draft token at 121 / 24 / 1 launches and the verify step (k = 3) -/
theorem T_alt_draft_launches : draftTok 121 = 18092241 ∧ usR 18092241 = 18092 ∧ draftTok 24 = 9265241 ∧ usR 9265241 = 9265 ∧
    draftTok 1 = 7172241 ∧ usR 7172241 = 7172 ∧ ms2 (3 * 18092241) = 5427 ∧ ms2 (3 * 9265241) = 2779 ∧ ms2 (3 * 7172241) = 2151 ∧
    121 * tLaunch = 11011000 ∧ pct (121 * tLaunch) 18092241 = 609 ∧ draftNs lamMid = 3 * draftTok 121 := by decide
/-- Row 18: head-aligned QKV packing alone (one launch fewer per layer): +0.9 % dense, +1.9 % MoE -/
theorem T_alt_headaligned : headAligned dense 32768 = 2351399269 ∧ tpsCard 1000 2351399269 = 106 ∧ pcsUp 106 105 = 9 ∧
    headAligned moe 32768 = 131299319 ∧ tpsCard 1000 131299319 = 1904 ∧ pcsUp 1904 1867 = 19 ∧
    today dense 32768 1 1 - headAligned dense 32768 = 120 * tLaunch ∧ today moe 32768 1 1 - headAligned moe 32768 = 28 * tLaunch ∧
    dense.Hq / dense.Hkv = 16 ∧ moe.Hq / moe.Hkv = 4 := by decide
/-- the launch table of §3.3: 6 / 7 launches per layer today, 1 with the megakernel; 722 / 198 per token -/
theorem T_alt_launch_table : dense.nL * dense.nlaunch + 2 = 722 ∧ 722 * tLaunch = 65702000 ∧ ms2 65702000 = 6570 ∧
    moe.nL * moe.nlaunch + 2 = 198 ∧ 198 * tLaunch = 18018000 ∧ ms2 18018000 = 1801 ∧
    (120 * 1 + 2) * tLaunch = 11102000 ∧ ms2 11102000 = 1110 ∧ (28 * 1 + 2) * tLaunch = 2730000 ∧ ms2 2730000 = 273 := by decide

/-! ## Rows 19–21 — the quantizing epilogue: as written (magic bias, 8 lane-ops, host-bounce fallback) and
    RE-DERIVED on the measured pass (43.7 µs per pass × 4 per layer) -/
/-- Row 19 (arithmetic only — SUPERSEDED as a mechanism by the measured cast): for every q ∈ [−127, 127],
    q + 1280 ∈ [1024, 2048) and (q + 1280 − 1024) mod 256 = q mod 256; the f32 analogue with bias 1.5·2²³ -/
theorem T_alt_magic_f16 : ((List.range 255).all fun i => magicF16 (Int.ofNat i - 127)) = true := by decide +kernel
theorem T_alt_magic_f32 : ((List.range 255).all fun i => magicF32 (Int.ofNat i - 127)) = true := by decide +kernel
theorem T_alt_magic_cells : magicF16 (-127) = true ∧ magicF16 127 = true ∧ magicF16 0 = true ∧ magicF16 (-128) = true ∧
    magicF32 (-127) = true ∧ magicF32 127 = true ∧ (1280 - 1024 : Nat) = 256 ∧ 12582912 % 256 = 0 := by decide
/-- Row 20 as written: 102 400 / 45 056 elements × 8 lane-ops = 19 / 8 µs per layer per core = 0.1 / 0.2 % — the
    ESTIMATE the measured pass replaces -/
theorem T_alt_quant_cost_written : quantElems dense = 102400 ∧ quantElems moe = 45056 ∧
    quantElems dense * quantOps = 819200 ∧ quantElems moe * quantOps = 360448 ∧
    quantPerLayerNs dense = 18962 ∧ usR 18962 = 19 ∧ quantPerLayerNs moe = 8343 ∧ usR 8343 = 8 ∧
    pct (120 * quantPerLayerNs dense) (today dense 32768 1 1) = 1 ∧ pct (28 * quantPerLayerNs moe) (today moe 32768 1 1) = 2 := by decide
/-- Row 21 as written: 4 bounces per layer at λ = 91 µs = 738 / 730 µs per layer → −2.8 % dense, −13.2 % MoE,
    draft +17.52 ms; Route-1b-class 106.0 — the COUNTERFACTUAL the measured pass retires -/
theorem T_alt_quant_fallback_written : hostBouncePerLayer dense lamMid = 737512 ∧ usR 737512 = 738 ∧
    hostBouncePerLayer moe lamMid = 730376 ∧ usR 730376 = 730 ∧
    today dense 32768 1 1 + 120 * hostBouncePerLayer dense lamMid = 2450820709 ∧ tpsCard 1000 2450820709 = 102 ∧ pcsDown 102 105 = 28 ∧
    today moe 32768 1 1 + 28 * hostBouncePerLayer moe lamMid = 154297847 ∧ tpsCard 1000 154297847 = 1620 ∧ pcsDown 1620 1867 = 132 ∧
    4 * 24 * (2 * lamMid + tn (2 * 8192) d2h0) = 17529600 ∧ ms2 17529600 = 1752 ∧ route1bRate = 1060 ∧
    ms2 2450820709 = 245082 ∧ ms2 154297847 = 15429 := by decide
/-- RE-DERIVED (HW-MAP 0915e22): the pass exists and costs 4 × 43.7 = 174.8 µs per layer — 20.98 ms per dense
    token (0.9 %: 0.105 → 0.104), 4.89 ms per MoE token (3.5 %: 1.867 → 1.801), +4.20 ms per draft token
    (+23.1 %); dense spec 0.262 → 0.258 -/
theorem T_alt_quant_measured : cQ = 43700 ∧ quantPasses * cQ = 174800 ∧ usR 174800 = 175 ∧
    quantTok dense = 20976000 ∧ ms2 20976000 = 2097 ∧ quantTok moe = 4894400 ∧ ms2 4894400 = 489 ∧ quantDraft = 4195200 ∧
    today dense 32768 1 1 + quantTok dense = 2383295269 ∧ tpsCard 1000 2383295269 = 104 ∧ pcsDown 104 105 = 9 ∧
    pct (quantTok dense) (today dense 32768 1 1) = 9 ∧
    today moe 32768 1 1 + quantTok moe = 138741719 ∧ tpsCard 1000 138741719 = 1801 ∧ pcsDown 1801 1867 = 35 ∧
    pct (quantTok moe) (today moe 32768 1 1) = 37 ∧
    draftTok 121 + quantDraft = 22287441 ∧ usR 22287441 = 22287 ∧ pcsUp 22287441 18092241 = 231 ∧
    today dense 32768 1 4 + quantTok dense + 3 * quantDraft = 2450280928 ∧ tpsCard 2533 2450280928 = 258 ∧
    quantPerLayerNs dense < quantPasses * cQ ∧ (quantPasses * cQ) / quantPerLayerNs dense = 9 := by decide
/-- the host-bounce counterfactual at the MEASURED λ = 12.2 µs is 107 / 100 µs per layer — cheaper than the
    measured on-device pass (174.8): the −2.8 % / −13.2 % figures were λ = 91 µs artefacts -/
theorem T_alt_quant_bounce_measured_lambda : hostBouncePerLayer dense lamMeas = 107112 ∧ usR 107112 = 107 ∧
    hostBouncePerLayer moe lamMeas = 99976 ∧ usR 99976 = 100 ∧ 107112 < quantPasses * cQ ∧ 99976 < quantPasses * cQ ∧
    today dense 32768 1 1 + 120 * hostBouncePerLayer dense lamMeas = 2375172709 ∧ tpsCard 1000 2375172709 = 105 ∧
    today moe 32768 1 1 + 28 * hostBouncePerLayer moe lamMeas = 136646647 ∧ tpsCard 1000 136646647 = 1829 ∧
    pcsDown 1829 1867 = 20 := by decide
/-- the other load-bearing cells with the pass on both sides: direct path 2.034, megakernel 2.011; the megakernel
    threshold is invariant (the pass enters both sides of the iff) -/
theorem T_alt_variants_q : directStep moe 32768 1 1 chainSer + quantTok moe = 122879159 ∧ tpsCard 1000 122879159 = 2034 ∧
    megaStep moe 32768 5000 + quantTok moe = 124261407 ∧ tpsCard 1000 124261407 = 2011 := by decide
theorem T_megakernel_moe_q (c : Nat) :
    megaStep moe 32768 c + quantTok moe < today moe 32768 1 1 + quantTok moe ↔ c ≤ 108430 := by
  rw [Nat.add_lt_add_iff_right]; exact T_megakernel_moe c

/-! ## Rows 22–25 — two-tier KV pages (`[ALT-5-*]`) -/
theorem T_alt_tier_cells :
    gPage 65536 0 = 1746 ∧ gPage MiB 0 = 1746 ∧ gTier 32768 0 = 1746 ∧ gTier 34768 0 = 1743 ∧ gTier 1048576 0 = 1746 ∧
    gPage 65536 100 = 1690 ∧ gPage MiB 100 = 1742 ∧ gTier 32768 100 = 1742 ∧ gTier 34768 100 = 1736 ∧
    gPage 65536 500 = 1497 ∧ gPage MiB 500 = 1728 ∧ gTier 32768 500 = 1728 ∧ gTier 34768 500 = 1710 ∧ gTier 1048576 500 = 1728 ∧
    gPage 65536 2000 = 1048 ∧ gPage MiB 2000 = 1676 ∧ gTier 32768 2000 = 1676 ∧ gTier 34768 2000 = 1616 ∧
    gPage 65536 6005 = 582 ∧ gPage MiB 6005 = 1552 ∧ gTier 32768 6005 = 1552 ∧ gTier 34768 6005 = 1411 ∧
    tExt 0 = 48044 ∧ tPage64 0 = 3002 ∧ nExt 32768 = 8 ∧ nTail 32768 = 0 ∧ nExt 34768 = 8 ∧ nTail 34768 = 8 := by decide
/-- the measured question: at c_pg = 38 ns (lower bound) the tier buys +1.1 % (174.4 vs 172.4), at 3× (114 ns)
    +3.5 %; on the measured per-page basis (DESIGN-3 round 3) +1.2 % / +3.5 % — it dominates, by little -/
theorem T_two_tier_measured : gPage 65536 38 = 1724 ∧ gTier 32768 38 = 1744 ∧ pcsUp 1744 1724 = 11 ∧ gPage MiB 38 = 1744 ∧
    gPage 65536 114 = 1682 ∧ gTier 32768 114 = 1741 ∧ pcsUp 1741 1682 = 35 ∧ gPage MiB 114 = 1741 ∧
    stepH 32768 1 (gPage 65536 38) cvNat 1 = 785570 ∧ stepH 32768 1 (gTier 32768 38) cvNat 1 = 776610 ∧ pcsDown 776610 785570 = 11 ∧
    stepH 1048576 1 (gPage 65536 38) cvNat 1 = 24918946 ∧ stepH 1048576 1 (gTier 1048576 38) cvNat 1 = 24632226 ∧
    stepH 32768 1 (gPage 65536 114) cvNat 1 = 805026 ∧ stepH 32768 1 (gTier 32768 114) cvNat 1 = 777954 ∧ pcsDown 777954 805026 = 33 ∧
    gPage3 65536 tPgSeq64 38 = 1670 ∧ gTier3 32768 38 = 1691 ∧ pcsUp 1691 1670 = 12 ∧ gPage3 262144 tPgSeq256 38 = 1687 ∧
    gPage3 65536 tPgSeq64 114 = 1630 ∧ gTier3 32768 114 = 1688 ∧ pcsUp 1688 1630 = 35 ∧ 3 * cPgMeas = 114 ∧
    pct (1691 - 1670) 1670 = 13 := by decide
/-- Row 23 — dominance, the time form. Below one extent (L < 4 096) the tier IS the 64 KiB-page stream. -/
theorem T_alt_tier_below_extent (L c : Nat) (h : L < 4096) : tTier L c = tPages64 L c := by
  have hq : L / 4096 = 0 := Nat.div_eq_of_lt h
  have hr : L % 4096 = L := Nat.mod_eq_of_lt h
  unfold tTier tPages64 nExt nTail
  rw [hq, hr, Nat.zero_mul, Nat.zero_add]
/-- CORRECTION (row 23): with at least one extent the tier is strictly faster iff c_pg ≥ 1 ns — at c_pg = 0 the
    floored extent (48 044 ns) is 12 ns per MiB SLOWER than 16 floored pages (48 032): "equality iff c_pg = 0" is
    not what the integer model says; per extent the tier saves 15·c_pg − 12 ns -/
theorem T_alt_tier_dominates (L c : Nat) (hL : 4096 ≤ L) :
    (tTier L c < tPages64 L c ↔ 1 ≤ c) ∧ (tPages64 L c < tTier L c ↔ c = 0) := by
  have hdecomp : L = 4096 * (L / 4096) + L % 4096 := (Nat.div_add_mod L 4096).symm
  generalize hq : L / 4096 = q at hdecomp
  generalize hr : L % 4096 = r at hdecomp
  have hrb : r < 4096 := by rw [← hr]; exact Nat.mod_lt _ (by decide)
  have hq1 : 1 ≤ q := by omega
  have hceil : ceilDiv L 256 = 16 * q + ceilDiv r 256 := by unfold ceilDiv; omega
  have hqc : (c = 0 ∧ q * c = 0) ∨ (1 ≤ c ∧ q ≤ q * c) := by
    cases c with
    | zero => exact Or.inl ⟨rfl, Nat.mul_zero q⟩
    | succ c' => exact Or.inr ⟨Nat.succ_pos c', Nat.le_mul_of_pos_right q (Nat.succ_pos c')⟩
  unfold tTier tPages64 nExt nTail tExt tPage64 MiB KiB rGemm
  rw [hq, hr, hceil]
  simp only [Nat.add_mul, Nat.mul_add, Nat.mul_assoc]
  omega
/-- the tenths view of the same fact: G_tier(32k) and G(64 KiB) print equal for c_pg ≤ 2 ns and differ from 3 ns;
    at c_pg = 0 the extent's 12 ns per MiB is invisible in tenths -/
theorem T_alt_tier_tenths : (∀ c, c < 3 → gTier 32768 c = gPage 65536 c) ∧ gPage 65536 3 < gTier 32768 3 ∧
    tTier 32768 0 = 384352 ∧ tPages64 32768 0 = 384256 ∧ ¬ tPages64 32768 1 < tTier 32768 1 ∧ tTier 32768 1 < tPages64 32768 1 := by decide
/-- G_tier ≤ G(1 MiB) for c_pg ≥ 1 as an exact rational statement (cross-multiplied: L·(48 044 + c) ≤ 4096·t_tier),
    with equality iff 4096 ∣ L; at c_pg = 0 the floored tail pages are 0.75 ns per page faster than the extent -/
theorem T_alt_tier_le_1MiB (L c : Nat) (hc : 1 ≤ c) :
    L * (48044 + c) ≤ 4096 * tTier L c ∧ (L * (48044 + c) = 4096 * tTier L c ↔ L % 4096 = 0) := by
  have hdecomp : L = 4096 * (L / 4096) + L % 4096 := (Nat.div_add_mod L 4096).symm
  generalize hq : L / 4096 = q at hdecomp
  generalize hr : L % 4096 = r at hdecomp
  have hrb : r < 4096 := by rw [← hr]; exact Nat.mod_lt _ (by decide)
  have hn : r ≤ 256 * ceilDiv r 256 := by unfold ceilDiv; omega
  have hn0 : r = 0 → ceilDiv r 256 = 0 := by intro h0; subst h0; decide
  have hn1 : 1 ≤ r → 1 ≤ ceilDiv r 256 := by intro h1; unfold ceilDiv; omega
  have hA : 16 * r * (3002 + c) ≤ 4096 * ceilDiv r 256 * (3002 + c) := Nat.mul_le_mul_right _ (by omega)
  have hB : r * (48044 + c) ≤ 16 * r * (3002 + c) := by
    rw [Nat.mul_assoc]
    calc r * (48044 + c) ≤ r * (16 * (3002 + c)) := Nat.mul_le_mul_left r (by omega)
      _ = 16 * (r * (3002 + c)) := Nat.mul_left_comm r 16 (3002 + c)
  have hB' : 1 ≤ r → r * (48044 + c) < 16 * r * (3002 + c) := by
    intro h1
    rw [Nat.mul_assoc]
    calc r * (48044 + c) < r * (16 * (3002 + c)) := Nat.mul_lt_mul_of_pos_left (by omega) h1
      _ = 16 * (r * (3002 + c)) := Nat.mul_left_comm r 16 (3002 + c)
  unfold tTier nExt nTail tExt tPage64 MiB KiB rGemm
  rw [hq, hr, hdecomp]
  have e1 : (4096 * q + r) * (48044 + c) = 4096 * q * (48044 + c) + r * (48044 + c) := Nat.add_mul _ _ _
  have e2 : 4096 * (q * (1048576 * 80 / 1746 + c) + ceilDiv r 256 * (65536 * 80 / 1746 + c))
      = 4096 * q * (48044 + c) + 4096 * ceilDiv r 256 * (3002 + c) := by
    rw [Nat.mul_add, ← Nat.mul_assoc, ← Nat.mul_assoc]
  rw [e1, e2]
  constructor
  · omega
  · constructor
    · intro heq
      by_cases h0 : r = 0
      · exact h0
      · exfalso
        have := hB' (Nat.pos_of_ne_zero h0)
        omega
    · intro h0
      rw [hn0 h0, h0]
      omega
/-- Row 24 — the attention steps on the paged branches (t = 1, native corner) -/
theorem T_alt_tier_steps :
    stepH 32768 1 (gPage 65536 500) cvNat 1 = 903650 ∧ stepH 32768 1 (gTier 32768 500) cvNat 1 = 783778 ∧
    usR 783778 = 784 ∧ pcsDown 783778 903650 = 132 ∧
    stepH 32768 1 (gPage 65536 2000) cvNat 1 = 1287714 ∧ stepH 32768 1 (gTier 32768 2000) cvNat 1 = 807842 ∧
    usR 1287714 = 1288 ∧ usR 807842 = 808 ∧ pcsDown 807842 1287714 = 372 ∧
    stepH 32768 1 (gPage 65536 6005) cvNat 1 = 2313186 ∧ stepH 32768 1 (gTier 32768 6005) cvNat 1 = 871842 ∧
    usR 2313186 = 2313 ∧ usR 871842 = 872 ∧ pcsDown 871842 2313186 = 623 ∧
    stepH 1048576 1 (gPage 65536 500) cvNat 1 = 28697506 ∧ stepH 1048576 1 (gTier 1048576 500) cvNat 1 = 24861602 ∧
    usR 28697506 = 28698 ∧ usR 24861602 = 24862 ∧
    stepH 1048576 1 (gPage 65536 2000) cvNat 1 = 40987554 ∧ stepH 1048576 1 (gTier 1048576 2000) cvNat 1 = 25631650 ∧
    usR 40987554 = 40988 ∧ usR 25631650 = 25632 ∧
    stepH 1048576 1 (gPage 65536 6005) cvNat 1 = 73802658 ∧ stepH 1048576 1 (gTier 1048576 6005) cvNat 1 = 27679650 ∧
    usR 73802658 = 73803 ∧ usR 27679650 = 27680 ∧
    stepH 32768 1 (gTier 32768 0) cvNat 1 = stepH 32768 1 gStream cvNat 1 := by decide
/-- Row 25 — compaction 46 ns per token-layer; tail waste ≤ 16 × 64 KiB = 1 MiB; 256 extents + ≤ 15 tails per 1M -/
theorem T_alt_tier_overhead : compactionNsPerTokLayer = 46 ∧ tn (16 * 2 * MiB) rGemm = 192178 ∧ 120 * 46 = 5520 ∧
    16 * 64 * KiB = MiB ∧ 16 * MiB / MiB = 16 ∧ 1048576 / 4096 = 256 ∧ nTail 1048575 = 16 ∧ nTail (1048576 - 256) = 15 ∧
    15 * 8 * MiB = 125829120 ∧ 15 * 8 * 16 * MiB = 2013265920 ∧ 2 * 16 * KiB = 32 * KiB := by decide

/-! ## Rows 26–27 — K-int8 / V-f16 (`[ALT-6-*]`): bytes × 3/4, one more lane-op per score -/
/-- the t = 1 block stays DDR-bound iff c_V ≤ 45 (ρ32 = 1) / 21 (ρ32 = 2): the vector block ≤ 9 008 ns -/
theorem T_alt_k8_threshold (cV : Nat) :
    (vecBlock (cV + 1) 1 1 mergeOps ≤ ddrBlock gStream 1 dH * 3 / 4 ↔ cV ≤ 45) ∧
    (vecBlock (cV + 1) 2 1 mergeOps ≤ ddrBlock gStream 1 dH * 3 / 4 ↔ cV ≤ 21) := by
  have h : ddrBlock gStream 1 dH * 3 / 4 = 9008 ∧ blockOf 1 = 512 ∧ mergeOps = 7000 ∧ rVecCore = 432 := by decide
  unfold vecBlock
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2]
  omega
theorem T_alt_k8_threshold_cells : ddrBlock gStream 1 dH = 12011 ∧ 12011 * 3 / 4 = 9008 ∧ mmaBlock 1 dH = 960 ∧
    loaderBlock 1 = 618 ∧ vecBlock 46 1 1 mergeOps = 8885 ∧ vecBlock 47 1 1 mergeOps = 9074 ∧
    vecBlock 22 2 1 mergeOps = 8667 ∧ vecBlock 23 2 1 mergeOps = 9047 := by decide
theorem T_alt_k8_steps : stepK8 32768 1 gStream cvNat 1 = 583982 ∧ usR 583982 = 584 ∧ pcsDown 583982 775778 = 247 ∧
    stepK8 32768 1 gStream cvWorst 2 = 876484 ∧ usR 876484 = 876 ∧ pcsUp 876484 851470 = 29 ∧
    stepK8 1048576 1 gStream cvNat 1 = 18456350 ∧ usR 18456350 = 18456 ∧ pcsDown 18456350 24605602 = 249 ∧
    stepK8 1048576 1 gStream cvWorst 2 = 27100996 ∧ usR 27100996 = 27101 ∧ pcsUp 27100996 26324046 = 29 ∧
    stepH 1048576 1 gStream cvWorst 2 = 26324046 := by decide
theorem T_alt_k8_fleet : stepK8 dense 32768 = 2339257789 ∧ tpsCard 1000 2339257789 = 106 ∧ pcsUp 106 105 = 9 ∧
    stepK8 dense 131072 = 2546810989 ∧ tpsCard 1000 2546810989 = 98 ∧ pcsUp 98 94 = 42 ∧
    stepK8 moe 32768 = 128466307 ∧ tpsCard 1000 128466307 = 1946 ∧ pcsUp 1946 1867 = 42 ∧
    stepK8 moe 131072 = 176895387 ∧ tpsCard 1000 176895387 = 1413 ∧ pcsUp 1413 1259 = 122 ∧
    stepK8 moe 1048576 = 628900115 ∧ tpsCard 1000 628900115 = 397 ∧ pcsUp 397 312 = 272 ∧
    todayI8 dense 32768 = 2316196309 ∧ tpsCard 1000 2316196309 = 107 ∧ pcsUp 107 105 = 19 ∧
    todayI8 dense 131072 = 2454565189 ∧ tpsCard 1000 2454565189 = 101 ∧ pcsUp 101 94 = 74 ∧
    todayI8 moe 32768 = 123085295 ∧ tpsCard 1000 123085295 = 2031 ∧ pcsUp 2031 1867 = 87 ∧
    todayI8 moe 131072 = 155371367 ∧ tpsCard 1000 155371367 = 1609 ∧ pcsUp 1609 1259 = 277 ∧
    todayI8 moe 1048576 = 456707843 ∧ tpsCard 1000 456707843 = 547 ∧ pcsUp 547 312 = 753 := by decide

/-! ## Row 28 — shared-prefix batched attention (`[ALT-7-*]`): gain iff passes < B -/
theorem T_alt_prefix_cells : passes dense 16 = 4 ∧ passes moe 16 = 1 ∧ prefixFull dense 32768 16 = 12299448 ∧
    usR 12299448 = 12299 ∧ prefixShared dense 32768 4096 16 = 11146374 ∧ usR 11146374 = 11146 ∧
    prefixShared dense 32768 16384 16 = 7687155 ∧ prefixShared dense 32768 28672 16 = 4227935 ∧
    prefixStep dense 32768 4096 16 = 3608255041 ∧ tpsCard 16000 3608255041 = 1108 ∧ tpsCard 16000 (today dense 32768 16 1) = 1067 ∧
    pcsUp 1108 1067 = 38 ∧ prefixStep dense 32768 16384 16 = 3193148761 ∧ tpsCard 16000 3193148761 = 1252 ∧ pcsUp 1252 1067 = 173 ∧
    prefixStep dense 32768 28672 16 = 2778042361 ∧ tpsCard 16000 2778042361 = 1439 ∧ pcsUp 1439 1067 = 348 ∧
    prefixStep moe 32768 4096 16 = 1656344171 ∧ tpsCard 16000 1656344171 = 2414 ∧ pcsUp 2414 2357 = 24 ∧
    prefixStep moe 32768 16384 16 = 1535271471 ∧ tpsCard 16000 1535271471 = 2605 ∧ pcsUp 2605 2357 = 105 ∧
    prefixStep moe 32768 28672 16 = 1414198799 ∧ tpsCard 16000 1414198799 = 2828 ∧ pcsUp 2828 2357 = 199 := by decide
/-- for every prefix length: the shared stream is strictly shorter iff L_s ≥ 1 (dense B = 16: 4 passes < 16;
    MoE: 1 pass < 16); at B = 1 (passes = B) the prefix changes nothing -/
theorem T_alt_prefix_iff (Ls : Nat) (h : Ls ≤ 32768) :
    (prefixShared dense 32768 Ls 16 < prefixFull dense 32768 16 ↔ 1 ≤ Ls) ∧
    (prefixShared moe 32768 Ls 16 < prefixFull moe 32768 16 ↔ 1 ≤ Ls) ∧
    prefixShared dense 32768 Ls 1 = prefixFull dense 32768 1 := by
  have hp : passes dense 16 = 4 ∧ passes moe 16 = 1 ∧ passes dense 1 = 1 ∧ dense.kvTok = 4096 ∧ moe.kvTok = 4096 := by decide
  unfold prefixShared prefixFull tn
  rw [hp.1, hp.2.1, hp.2.2.1, hp.2.2.2.1, hp.2.2.2.2]
  unfold rGemm
  omega

/-! ## Rows 29–30 — the lazy-rescale online softmax (`[ALT-8-*]`) -/
/-- the S4 128-token block (mt = 8) stays DDR-bound without the merge iff c_V ≤ 7 (ρ32 = 1) / 3 (ρ32 = 2) -/
theorem T_alt_lazy_threshold (cV : Nat) :
    (vecBlock cV 1 8 0 ≤ ddrBlock gStream 8 dH ↔ cV ≤ 7) ∧ (vecBlock cV 2 8 0 ≤ ddrBlock gStream 8 dH ↔ cV ≤ 3) := by
  have h : ddrBlock gStream 8 dH = 3002 ∧ blockOf 8 = 128 ∧ rVecCore = 432 := by decide
  unfold vecBlock
  rw [h.1, h.2.1, h.2.2]
  omega
theorem T_alt_lazy_cells :
    stepH 32768 16 gStream 7 1 = 1553714 ∧ stepS4 32768 gStream 7 1 = 1032465 ∧ stepLazy 32768 gStream 7 1 = 786927 ∧
    usR 1553714 = 1554 ∧ usR 1032465 = 1032 ∧ usR 786927 = 787 ∧ pcsDown 786927 1553714 = 493 ∧ pcsDown 786927 1032465 = 237 ∧
    stepH 32768 16 gStream 12 1 = 1557508 ∧ stepS4 32768 gStream 12 1 = 1521633 ∧ stepLazy 32768 gStream 12 1 = 1187265 ∧
    stepH 32768 16 gStream 33 2 = 6802196 ∧ stepS4 32768 gStream 33 2 = 7139841 ∧ stepLazy 32768 gStream 33 2 = 6471105 ∧
    stepH 1048576 16 gStream 7 1 = 49209394 ∧ stepS4 1048576 gStream 7 1 = 32387601 ∧ stepLazy 1048576 gStream 7 1 = 24610799 ∧
    stepH 1048576 16 gStream 12 1 = 49213188 ∧ stepS4 1048576 gStream 12 1 = 47923425 ∧ stepLazy 1048576 gStream 12 1 = 37304001 ∧
    stepH 1048576 16 gStream 33 2 = 215733268 ∧ stepS4 1048576 gStream 33 2 = 226355969 ∧ stepLazy 1048576 gStream 33 2 = 205117121 ∧
    usR 24610799 = 24611 ∧ usR 1187265 = 1187 ∧ usR 6471105 = 6471 := by decide
theorem vecBlock_mono_merge (cV rho mt m1 m2 : Nat) (h : m1 ≤ m2) : vecBlock cV rho mt m1 ≤ vecBlock cV rho mt m2 := by
  unfold vecBlock
  apply Nat.div_le_div_right
  apply Nat.mul_le_mul_right
  apply Nat.mul_le_mul_right
  apply Nat.add_le_add_left
  exact Nat.mul_le_mul_right _ h
theorem blockMax_mono_merge (G cV rho mt d m1 m2 : Nat) (h : m1 ≤ m2) :
    blockMax G cV rho mt d m1 ≤ blockMax G cV rho mt d m2 := by
  have := vecBlock_mono_merge cV rho mt m1 m2 h
  unfold blockMax
  omega
/-- removing the merge never costs: lazy ≤ S4 on every corner, every L, every G (monotone in the merge count) -/
theorem T_alt_lazy_dominates_S4 (L G cV rho : Nat) : stepLazy L G cV rho ≤ stepS4 L G cV rho := by
  unfold stepLazy stepS4 Attn2.stepNs
  have hb := blockMax_mono_merge G cV rho (mtSel (rowsOf 16 gH) true) dH 0 mergeOps (Nat.zero_le _)
  have hf : fixedNs L cV rho rDrainA 0 (mtSel (rowsOf 16 gH) true) (mtOf (rowsOf 16 gH)) dH
      ≤ fixedNs L cV rho rDrainA mergeOps (mtSel (rowsOf 16 gH) true) (mtOf (rowsOf 16 gH)) dH := by
    unfold fixedNs
    have := vecBlock_mono_merge cV rho (mtSel (rowsOf 16 gH) true) 0 mergeOps (Nat.zero_le _)
    omega
  exact Nat.add_le_add (Nat.mul_le_mul_left _ hb) hf
/-- lazy ≤ two-pass at 32k for every c_V at ρ32 = 1 and 2 (the KV stream is read once instead of twice) -/
theorem T_alt_lazy_dominates_twopass (cV : Nat) :
    stepLazy 32768 gStream cV 1 ≤ stepH 32768 16 gStream cV 1 ∧ stepLazy 32768 gStream cV 2 ≤ stepH 32768 16 gStream cV 2 := by
  have hc : mtSel (rowsOf 16 gH) true = 8 ∧ mtSel (rowsOf 16 gH) false = 4 ∧ mtOf (rowsOf 16 gH) = 8 ∧
      pSel (rowsOf 16 gH) true = 1 ∧ pSel (rowsOf 16 gH) false = 2 ∧ nblocks 32768 8 = 256 ∧ nblocks 32768 4 = 128 ∧
      ddrBlock gStream 8 dH = 3002 ∧ ddrBlock gStream 4 dH = 6005 ∧ mmaBlock 8 dH = 1920 ∧ mmaBlock 4 dH = 1920 ∧
      loaderBlock 8 = 1236 ∧ loaderBlock 4 = 1236 ∧ drainBlock 8 dH rDrainA = 13107 ∧ drainBlock 4 dH rDrainA = 9830 ∧
      blockOf 8 = 128 ∧ blockOf 4 = 256 ∧ mergeOps = 7000 ∧ rVecCore = 432 := by decide
  have ht : ∀ rho, tailNs 32768 8 dH rho = 0 := by intro rho; simp [tailNs, tailOps]
  unfold stepLazy stepH Attn2.stepNs blockMax fixedNs
  rw [hc.1, hc.2.1, hc.2.2.1, hc.2.2.2.1, hc.2.2.2.2.1, hc.2.2.2.2.2.1, hc.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.1,
    hc.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.2.1,
    hc.2.2.2.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1, ht, ht]
  unfold vecBlock
  rw [hc.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1,
    hc.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2]
  omega
/-- Row 30: with one resident O region the S4 L0C is exactly full: 3 × 64 KiB C_s + 64 KiB O = 256 KiB; the
    margin μ = 8 is a DEFINITION (exp(8) = 2 981 < 65 504 is transcendental, not proved here) -/
theorem T_alt_lazy_l0c : 3 * (128 * 16 * 4 * 8) + 16 * 128 * 4 * 8 = 262144 ∧ 262144 = 256 * KiB ∧ 2981 < f16Max ∧
    (128 * 16 * 4 * 8 : Nat) = 64 * KiB := by decide

/-! ## Row 31 — the dominated families as bounds (`[ALT-9-*]`) -/
/-- K-split on the dense kernel: A bytes −5 254 ns, partials +3 002 ns, net +2 252 ns = 0.6 % of 384 µs — a bound
    that any cross-core sync ≥ 2.3 µs (a launch is 91 µs) turns negative -/
theorem T_dominated_ksplit : ksplitSaved = 5254 ∧ ksplitAdded = 3002 ∧ ksplitSaved - ksplitAdded = 2252 ∧ usR 5254 = 5 ∧
    usR 3002 = 3 ∧ usR 2252 = 2 ∧ pct 2252 384000 = 6 ∧ 384000 < 384000 - 2252 + tLaunch ∧
    (∀ sync, 2252 < sync → 384000 < 384000 - 2252 + sync) := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, fun sync h => by omega⟩ <;> decide
/-- producer–consumer core specialisation: without an inter-core SRAM path the bytes cross DDR three times, and
    3× the bytes at 174.6 is exactly the useful bytes at 58.2 — the cap, for every byte count -/
theorem T_dominated_specialization (W : Nat) : tn (3 * W) rGemm = tn W specializationCap ∧ specializationCap = 582 := by
  constructor
  · show 3 * W * 10 / 1746 = W * 10 / (1746 / 3)
    have h1 : 3 * W * 10 = 3 * (W * 10) := Nat.mul_assoc 3 W 10
    rw [h1, show (1746 : Nat) / 3 = 582 from rfl, show (1746 : Nat) = 3 * 582 from rfl]
    exact Nat.mul_div_mul_left (W * 10) 582 (by decide)
  · rfl
theorem T_dominated_specialization_cell : rateT (64 * MiB) (tn (3 * 64 * MiB) rGemm) = 582 ∧ x10 rGemm 3 / 10 = 582 := by decide
/-- weight-stationary tiling: at m ≤ 16 a B tile is used once, so the best case saves the A bytes — 1.5 % of the
    bytes (1 MiB of A against 64 MiB of B) -/
theorem T_dominated_weight_stationary : 8 * 128 * KiB = MiB ∧ pct MiB (64 * MiB + MiB) = 15 ∧ 8 * 8 * MiB = 64 * MiB := by decide
/-- L2-resident carving: the smallest hot object (an 8 MiB dense slab per core, a 16 MiB expert slab) exceeds
    8 × the ~1 MB S1 -/
theorem T_dominated_l2 : 8 * s1Prior < 8 * MiB ∧ 8 * s1Prior < 16 * MiB ∧ 1 * MiB > s1Prior := by decide
/-- expert-parallel across the card's two dies (and flash-decoding split-KV across dies): at Π = 1 no concurrency,
    +2 λ per MoE layer: 133.84 → 138.94 ms (−3.6 %) at λ = 91 µs; a loss for every λ > 0; H_kv = 8 = cores -/
theorem T_dominated_expert_parallel (lam : Nat) (h : 0 < lam) : today moe 32768 1 1 < expertParallel lam := by
  unfold expertParallel; have : moe.nL = 28 := rfl; rw [this]; omega
theorem T_dominated_expert_parallel_cells : expertParallel lamMid = 138943319 ∧ tpsCard 1000 138943319 = 1799 ∧
    pcsDown 1799 1867 = 36 ∧ ms2 138943319 = 13894 ∧ moe.Hkv = 8 ∧ dense.Hkv = 8 := by decide
theorem T_dominated_hotcold : hotColdUniform = 146424639 ∧ hotColdZipf = 136205171 ∧ today moe 32768 1 1 < hotColdUniform :=
  ⟨T_alt_hotcold_loses.1, T_alt_hotcold_loses.2.2.2.1, by decide⟩
/-- zero-copy / NUMA / polling: whatever replaces the exchange, the saving is ≤ T_x = 1 480 µs MoE (1.1 %) /
    1 497 µs dense (0.06 %) per token -/
theorem T_dominated_p2p (x : Nat) :
    today moe 32768 1 1 ≤ (today moe 32768 1 1 - Tx moe 1 lamMid + x) + Tx moe 1 lamMid ∧
    today dense 32768 1 1 ≤ (today dense 32768 1 1 - Tx dense 1 lamMid + x) + Tx dense 1 lamMid ∧
    Tx moe 1 lamMid = 1480367 ∧ Tx dense 1 lamMid = 1497107 ∧ pct 1480367 133847319 = 11 ∧ pctH 1497107 2362319269 = 6 := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · have : Tx moe 1 lamMid ≤ today moe 32768 1 1 := by decide
    omega
  · have : Tx dense 1 lamMid ≤ today dense 32768 1 1 := by decide
    omega
  all_goals decide
/-- capacity-factor token dropping: F + D·T_S halves at D = 64 of 128 (×1.9) by discarding half the routed pairs -/
theorem T_dominated_tokendrop : tokenDropStep 128 = 15749312 ∧ tokenDropStep 64 = 7878656 ∧ ms2 15749312 = 1574 ∧
    ms2 7878656 = 787 ∧ x10 15749312 7878656 = 19 := by decide
/-- rows-cliff repair: a flat m-curve to 64 would buy B = 64 at 4k only (dense ×3.2, MoE ×1.9); at 32k B = 64 is
    memory-infeasible (L_max(64) = 8 613 / 30 090 < 32 768) -/
theorem T_dominated_rowscliff : today dense 4096 16 1 = 2455181881 ∧ tpsCard 16000 2455181881 = 1629 ∧
    today dense 4096 64 1 = 3010630465 ∧ tpsCard 64000 3010630465 = 5314 ∧ x10 5314 1629 = 32 ∧
    today moe 4096 16 1 = 1395365271 ∧ tpsCard 16000 1395365271 = 2866 ∧ today moe 4096 64 1 = 2847949565 ∧
    tpsCard 64000 2847949565 = 5618 ∧ x10 5618 2866 = 19 ∧ feasibleB dense 4096 64 = true ∧ feasibleB moe 4096 64 = true ∧
    Lmax dense 64 = 8613 ∧ Lmax moe 64 = 30090 ∧ 8613 < 32768 ∧ 30090 < 32768 := by decide
/-- draft on the host CPU: the draft is ≤ 54.27 ms of the 2 416.71 ms verify step = 2.2 % (the text said 2.3) -/
theorem T_dominated_draft_host : 3 * draftTok 121 = 54276723 ∧ ms2 54276723 = 5427 ∧ pct 54276723 (today dense 32768 1 4) = 22 ∧
    3 * draftTok 24 = 27795723 ∧ ms2 27795723 = 2779 := by decide
/-- GQA head packing is already the design: the only loss is the 16-row padding at t = 1 (×2 at g = 8, ×4 at g = 4) -/
theorem T_dominated_gqa_padding : 16 / 8 = 2 ∧ 16 / 4 = 4 ∧ ceilDiv 8 16 * 16 = 16 ∧ ceilDiv 4 16 * 16 = 16 := by decide

/-! ## The load-bearing umbrellas (PROMPT-5P) -/
/-- T_instance_gain: fit premise (minimal x as an iff), the break-even iff over every W4 core-slab time, the
    measured 5.3 GB/s instantiated, H10's efficiency as a hypothesis, and the same iff with the measured pass -/
theorem T_instance_gain_umbrella :
    (∀ x, (instFits moe 0 32768 1 false oRt x ↔ 182 ≤ x) ∧ (instFits moe 1 32768 1 false oRt x ↔ 170 ≤ x)) ∧
    (∀ ort x, x ≤ 1000 → (instFits moe 0 32768 1 false ort x ↔ 6019884032 + ort ≤ 7 * (12884901888 * x / 2000))) ∧
    (∀ Tc, tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k Tc) ↔ Tc ≤ 1371124) ∧
    tW4 ≤ 1371124 ∧ tpsInst 1000 (instMoe32k tW4) = 3878 ∧ tpsCard 1000 (today moe 32768 1 1) = 1867 ∧
    (∀ eta, tpsCard 1000 (today moe 32768 1 1) < tpsInstEta 1000 (instMoe32k tW4) eta ↔ 482 ≤ eta) ∧
    (∀ Tc, tpsCard 1000 (today moe 32768 1 1 + quantTok moe) < tpsInst 1000 (instMoe32k Tc + quantTok moe) ↔ Tc ≤ 1412631) := by
  refine ⟨fun x => ⟨(T_alt_fit_minx_moe_32k x).1, (T_alt_fit_minx_moe_32k x).2.1⟩, fun ort x hx => T_alt_fit_overhead_moe ort x hx,
    T_instance_gain, ?_, ?_, ?_, T_instance_gain_h10, T_instance_gain_q⟩ <;> decide
/-- T_direct_path: the anchor identity 167.1 / 172.8 from the measured rates, the A-lift bracket, the drain iff -/
theorem T_direct_path : rateExp chainSer = 1671 ∧ rateExp chainOvl = 1728 ∧ rateExp tSlabSer = 1353 ∧
    (∀ a, a ≤ 3285 → 1671 ≤ rateExp (chainA a) ∧ rateExp (chainA a) ≤ 1728) ∧
    (∀ R, 0 < R → (tn (32 * KiB) R ≤ tBDirect ↔ 4 ≤ R)) ∧ tpsCard 1000 (directStep moe 32768 1 1 chainSer) = 2118 := by
  refine ⟨?_, ?_, ?_, T_alt_direct_bracket, T_alt_direct_drain, ?_⟩ <;> decide
/-- T_megakernel: pays iff c_sync ≤ 109 903 ns (dense) / 108 430 ns (MoE), both directions, every c_sync -/
theorem T_megakernel : (∀ c, (megaStep dense 32768 c ≤ today dense 32768 1 1 ↔ c ≤ 109903) ∧ (megaStep dense 32768 c < today dense 32768 1 1 ↔ c ≤ 109902)) ∧
    (∀ c, megaStep moe 32768 c < today moe 32768 1 1 ↔ c ≤ 108430) ∧ usR 108430 = 108 ∧ usR 109903 = 110 ∧
    tpsCard 1000 (megaStep moe 32768 2000) = 2101 :=
  ⟨T_megakernel_dense, T_megakernel_moe, by decide, by decide, by decide⟩
/-- T_two_tier: the time-form dominance with its c_pg ≥ 1 ns threshold, the identity below one extent, the exact
    rational bound against 1 MiB pages, and the measured-c_pg cells (+1.1 % at 38 ns, +3.5 % at 114 ns) -/
theorem T_two_tier : (∀ L c, 4096 ≤ L → ((tTier L c < tPages64 L c ↔ 1 ≤ c) ∧ (tPages64 L c < tTier L c ↔ c = 0))) ∧
    (∀ L c, L < 4096 → tTier L c = tPages64 L c) ∧
    (∀ L c, 1 ≤ c → L * (48044 + c) ≤ 4096 * tTier L c ∧ (L * (48044 + c) = 4096 * tTier L c ↔ L % 4096 = 0)) ∧
    gTier 32768 38 = 1744 ∧ gPage 65536 38 = 1724 ∧ gTier 32768 114 = 1741 ∧ gPage 65536 114 = 1682 :=
  ⟨T_alt_tier_dominates, T_alt_tier_below_extent, T_alt_tier_le_1MiB, by decide, by decide, by decide, by decide⟩

/-! # PROMPT-6 (2026-11-08) — the new-errata audit: the cells it moves in ALTERNATIVES (`[PA-*]` in proof/alt.py; PROOF-COVERAGE-5
    rows PA5-1 … PA5-4). No new silicon. (1) Erratum #19 on the cold tier (§2.1): every f16 call writes a FRESH C chunk and the vector
    unit sums the partials in f32 — + 8313 ns (throughput) / 32614 ns (chained) per int4 core-slab on the binding vector
    unit, + 13 ns of drain and 16 / 63 ns of add per serial piece. (2) Erratum #29 on the megakernel (§2.3): one crossing per flag round
    puts the primary c_sync reading at the 20 µs branch. The instance verdict T_instance_gain is an iff over every Tc and is untouched;
    only its instantiation moves. -/
namespace Audit6A
open Measured Design Fleet2
def mergeT : Nat := 512 * 512 * 137 * 10 / (100 * rVecCore)
def mergeC : Nat := 512 * 637 / 10
def drainPiece : Nat := tn (2 * KiB) rDrainMeas
def addT : Nat := 512 * 137 * 10 / (100 * rVecCore)
def addC : Nat := 637 / 10
/-- the dense int4 path's W8-equivalent die rate at a core-slab time Tc (2 MiB of W8-equivalent bytes per core, 8 cores) -/
def rW4of (Tc : Nat) : Nat := 8 * 2 * MiB * 10 / Tc
end Audit6A
open Audit6A

/-- erratum #19, T convention: the overlapped instance cells (MoE 32k uniform / Zipf(1.0), dense 32k) and the serial branch -/
theorem T6a_cold_merge_T : mergeT = 8313 ∧ drainPiece = 13 ∧ addT = 16 ∧ tW4 + mergeT = 206157 ∧
    instMoe32k 206157 = 129882955 ∧ tpsInst 1000 129882955 = 3849 ∧ pcsUp 3849 1867 = 1061 ∧
    rW4of 206157 = 813 ∧ instDense32k 813 = 3267951143 ∧ tpsInst 1000 3267951143 = 153 ∧ pcsUp 153 105 = 457 ∧
    pieceSerC + drainPiece + addT = 836 ∧ instMoe32k (slabSer 836) = 156124555 ∧ tpsInst 1000 156124555 = 3202 ∧
    rW4W8Ser 836 = 392 ∧ instDense32k 392 = 5089603493 ∧ tpsInst 1000 5089603493 = 98 ∧ pcsDown 98 105 = 66 ∧
    1371124 * 10 / 206157 = 66 ∧ 1371124 * 10 / slabSer 836 = 32 := by decide
theorem T6a_cold_merge_zipf_T : instStepZ moe 32768 (fun p => ncOf (xsMoe32k p)) hTot hCold chainSer 206157 7 lamMid = 119486359 ∧
    tpsInst 1000 119486359 = 4184 := by decide +kernel
/-- the instance verdict survives the merge: both merged slabs are inside T_instance_gain's line (iff over every Tc) -/
theorem T6a_cold_merge_gain_T : tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k 206157) ∧
    tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k (slabSer 836)) :=
  ⟨(T_instance_gain 206157).mpr (by decide), (T_instance_gain (slabSer 836)).mpr (by decide)⟩

/-- erratum #19, C convention: the overlapped instance cells (MoE 32k uniform / Zipf(1.0), dense 32k) and the serial branch -/
theorem T6a_cold_merge_C : mergeC = 32614 ∧ drainPiece = 13 ∧ addC = 63 ∧ tW4 + mergeC = 230458 ∧
    instMoe32k 230458 = 132757071 ∧ tpsInst 1000 132757071 = 3766 ∧ pcsUp 3766 1867 = 1017 ∧
    rW4of 230458 = 727 ∧ instDense32k 727 = 3468598493 ∧ tpsInst 1000 3468598493 = 144 ∧ pcsUp 144 105 = 371 ∧
    pieceSerC + drainPiece + addC = 883 ∧ instMoe32k (slabSer 883) = 158970643 ∧ tpsInst 1000 158970643 = 3145 ∧
    rW4W8Ser 883 = 368 ∧ instDense32k 368 = 5319026723 ∧ tpsInst 1000 5319026723 = 94 ∧ pcsDown 94 105 = 104 ∧
    1371124 * 10 / 230458 = 59 ∧ 1371124 * 10 / slabSer 883 = 30 := by decide
theorem T6a_cold_merge_zipf_C : instStepZ moe 32768 (fun p => ncOf (xsMoe32k p)) hTot hCold chainSer 230458 7 lamMid = 119994503 ∧
    tpsInst 1000 119994503 = 4166 := by decide +kernel
/-- the instance verdict survives the merge: both merged slabs are inside T_instance_gain's line (iff over every Tc) -/
theorem T6a_cold_merge_gain_C : tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k 230458) ∧
    tpsCard 1000 (today moe 32768 1 1) < tpsInst 1000 (instMoe32k (slabSer 883)) :=
  ⟨(T_instance_gain 230458).mpr (by decide), (T_instance_gain (slabSer 883)).mpr (by decide)⟩

/-- erratum #29: the megakernel combos at the 20 µs primary reading (one batched crossing per flag round); the single megakernel's 20 µs
    cells are T_alt_mega_cells (MoE 2.058, dense 0.107) -/
theorem T6a_mega_20us : megaDirect 20000 = 105604447 ∧ tpsCard 1000 105604447 = 2367 ∧ pcsUp 2367 1867 = 267 ∧
    instMega moe xsMoe32k tW4 20000 = 116519437 ∧ tpsInst 1000 116519437 = 4291 ∧ pcsUp 4291 1867 = 1298 ∧
    instMega dense xsDense32k 0 20000 = 3154790633 ∧ tpsInst 1000 3154790633 = 158 ∧
    108430 * 10 / 20000 = 54 ∧ 109902 * 10 / 20000 = 54 := by decide +kernel

