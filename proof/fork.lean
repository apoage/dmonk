/-
  proof/fork.lean — theorems for DESIGN-FORK-PIPE.md (PROMPT-7 challenge round, namespace `Fork`):
  host-scheduled multi-die concurrency on the UNCHANGED full-int8 8-die partition.

    member P  sequence pipelining: Π sequences staggered along the layer-split chain, each die serving one
              sequence at a time — fleet tokens/s = min(c / T_step, 1 / max block);
    member S  one layer step on all 8 dies at once (N-split / head-split custom launches gathered through the
              host) — DESIGN-4's own "tensor-split worked" what-if on the round-7 anchors.

  Every cell is the round-7 step's own terms re-arranged; nothing new is priced. What is NOT proved here and
  cannot be: that the silicon delivers the concurrency c the cells take as an argument (measured for PAIRS of
  dies and PAIRS of cards only), and that same-step launches on several dies overlap (member S, unmeasured).

  Core Lean 4 only (no Mathlib, no Batteries). No `axiom`, no `sorry`, no `native_decide`. Standalone:
  `lean proof/fork.lean`, or `cd proof && lake build` (target `Fork`). Labels: `proof/fleet.py` `[FORK-*]`.
-/

namespace Fork

/-! ## Inputs — HW-MAP rows ([M]), assumptions ([A]) and the two corpus-derived cells the comparison needs ([C]) -/
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB : Nat := 1000000000
/-- [M] W8 decode kernel 174.6 GB/s; expert-GEMM M0 165.8; host bounce 12.2 µs; launch floor 91 µs (primary)
    and the realized bound 36 µs; quantization pass 43.7 µs. -/
def rGemm : Nat := 1746
def rM0 : Nat := 1658
def lam : Nat := 12200
def cQ : Nat := 43700
/-- [M] deferred-guard cell at 32k: trip-free 945.5 µs; amortized at the measured 8 % retry share. -/
def dfr32 : Nat := 945500
def amort80 : Nat := dfr32 + 80 * 873000 / 1000
/-- [M] 86 GB per die. [A] 2 GiB overhead + 64 MiB workspace per die (UNMEASURED, H8). -/
def dieMem : Nat := 86 * GB
def ort : Nat := 2 * GiB
def ws : Nat := 64 * MiB
/-- [C] the two-instance plan (V3) at the round-7 anchors, erratum-19 merge throughput / chained
    (`Chk.C2_instance_cells`; `[FORK-v3-moe-32k]`), and its dense step (`T6r_inst6`). -/
def v3T : Nat := 142057473
def v3C : Nat := 144931589
def v3Dense : Nat := 3337073683

def tn (b r : Nat) : Nat := b * 10 / r
/-- thousandths of tokens/s per card at aggregate concurrency `c` (thousandths of one stream). -/
def tps (c T : Nat) : Nat := 1000 * c * 1000000 / (4 * T)

/-! ## Shapes (PROBLEM-4's two models, int8-resident) -/
def dLayer : Nat := 16384 * (16384 + 2 * 8 * 128) + 16384 * 16384 + 3 * 16384 * 53248
def dEmbed : Nat := 16384 * 128256
def mAttn : Nat := 4096 * (4096 + 2 * 8 * 128) + 4096 * 4096
def mExp : Nat := 256 * 3 * 4096 * 4096
def mLayer : Nat := mAttn + mExp
def mEmbed : Nat := 4096 * 128256
def kvTok : Nat := 2 * 8 * 128 * 2
def draft : Nat := GB + 24 * 4096 * (2 * 8 * 64 * 2)
def slabM0 : Nat := 2 * MiB * 80 / rM0

/-! ## The round-7 layer and the per-die block (chain order d1, d0, d1, d0, …; position 7 carries lm_head) -/
def moeLayerNs (launch : Nat) : Nat := tn mAttn rGemm + 16000 + 24 * slabM0 + amort80 + 7 * launch + 4 * cQ
def denseLayerNs (launch : Nat) : Nat := tn dLayer rGemm + dfr32 + 6 * launch + 4 * cQ
/-- host link [M]: die 0 H2D 27.6 / D2H 27.3; die 1 13.9 / 19.0. Even positions sit on die 1. -/
def h2d (p : Nat) : Nat := if p % 2 = 0 then 139 else 276
def d2h (p : Nat) : Nat := if p % 2 = 0 then 190 else 273
/-- the time position `p` holds one sequence: its layers, the head on the last die, its two bounce halves. -/
def block (nLayers : Nat → Nat) (layerNs headNs launch d p : Nat) : Nat :=
  nLayers p * layerNs + (if p = 7 then headNs + 2 * launch else 0)
  + (if p > 0 then tn (d * 2) (h2d p) + lam else 0)
  + (if p < 7 then tn (d * 2) (d2h p) + lam else tn (128256 * 4) (d2h p) + lam)
def moeLayers (p : Nat) : Nat := if p % 2 = 0 then 4 else 3
def moeBlock (launch p : Nat) : Nat := block moeLayers (moeLayerNs launch) (tn mEmbed rGemm) launch 4096 p
def denseBlock (launch p : Nat) : Nat := block (fun _ => 15) (denseLayerNs launch) (tn dEmbed rGemm) launch 16384 p
def sum8 (f : Nat → Nat) : Nat := f 0 + f 1 + f 2 + f 3 + f 4 + f 5 + f 6 + f 7
def max8 (f : Nat → Nat) : Nat :=
  max (max (max (f 0) (f 1)) (max (f 2) (f 3))) (max (max (f 4) (f 5)) (max (f 6) (f 7)))
/-- member P: Π staggered sequences at aggregate concurrency c — stream-limited or block-limited. -/
def pipe (c T bmax : Nat) : Nat := min (tps c T) (1000000000000 / (4 * bmax))

/-! ## P1 — the blocks are the chain step, re-arranged (`[FORK-blocks-*]`) -/
theorem P1_blocks_moe : moeBlock 91000 0 = 18060227 ∧ moeBlock 91000 1 = 13560693 ∧ moeBlock 91000 2 = 18073016 ∧
    moeBlock 91000 7 = 16769985 ∧ max8 (moeBlock 91000) = 18073016 ∧
    sum8 (moeBlock 91000) + lam = 129743539 ∧ sum8 (moeBlock 36000) + lam = 118853539 ∧
    max8 (moeBlock 36000) = 16533016 := by decide

theorem P1_blocks_dense : max8 (denseBlock 91000) = 311110976 ∧ sum8 (denseBlock 91000) + lam = 2403248669 ∧
    max8 (denseBlock 36000) = 306050976 ∧ sum8 (denseBlock 36000) + lam = 2363538669 := by decide

/-- up to seven staggered sequences never want the same die at once (Π · max block ≤ T_step); the eighth
    makes the slowest die the bottleneck. -/
theorem P2_collision_free : 7 * 18073016 ≤ 129743539 ∧ 129743539 < 8 * 18073016 ∧
    7 * 311110976 ≤ 2403248669 ∧ 2403248669 < 8 * 311110976 := by decide

/-! ## P3 — the cells (`[FORK-pi-*]`), tokens/s per card in thousandths at c = Π -/
theorem P3_cells_moe : pipe 1000 129743539 18073016 = 1926 ∧ pipe 2000 129743539 18073016 = 3853 ∧
    pipe 4000 129743539 18073016 = 7707 ∧ pipe 8000 129743539 18073016 = 13832 ∧
    pipe 1990 129743539 18073016 = 3834 ∧
    pipe 1000 118853539 16533016 = 2103 ∧ pipe 2000 118853539 16533016 = 4206 ∧
    pipe 4000 118853539 16533016 = 8413 ∧ pipe 8000 118853539 16533016 = 15121 ∧
    8 * 1000000000000 / (4 * 129743539) = 15415 := by decide

theorem P3_cells_dense : pipe 1000 2403248669 311110976 = 104 ∧ pipe 2000 2403248669 311110976 = 208 ∧
    pipe 4000 2403248669 311110976 = 416 ∧ pipe 8000 2403248669 311110976 = 803 ∧
    pipe 2000 2363538669 306050976 = 211 ∧ pipe 8000 2363538669 306050976 = 816 := by decide

/-! ## P4 — against the two-instance plan (V3) on the same two sequences -/
/-- at ANY equal concurrency the chain's own step beats the instance step: the int4 tier makes the instance
    slower per token, and both plans spend the same two streams. -/
theorem P4_dominates_v3 (c : Nat) : tps c v3T ≤ tps c 129743539 ∧ tps c v3C ≤ tps c 129743539 ∧
    tps c v3Dense ≤ tps c 2403248669 := by
  unfold tps v3T v3C v3Dense
  refine ⟨?_, ?_, ?_⟩ <;> omega

theorem P4_cells : tps 2000 129743539 = 3853 ∧ tps 2000 v3T = 3519 ∧ tps 2000 v3C = 3449 ∧
    tps 2000 2403248669 = 208 ∧ tps 1990 v3Dense = 149 ∧
    (3853 - 3519) * 1000 / 3519 = 94 ∧ (3853 - 3449) * 1000 / 3449 = 117 := by decide

/-- the concurrency each plan needs: pipelining clears the single chain (1.926) as soon as there is ANY
    overlap (c ≥ 1.001); V3 needs 1.095 / 1.118; pipelining matches V3's best cell from c ≥ 1.827. -/
theorem P5_thresholds (c : Nat) :
    (1927 ≤ tps c 129743539 ↔ 1001 ≤ c) ∧ (1927 ≤ tps c v3T ↔ 1095 ≤ c) ∧ (1927 ≤ tps c v3C ↔ 1118 ≤ c) ∧
    (3519 ≤ tps c 129743539 ↔ 1827 ≤ c) := by
  unfold tps v3T v3C
  refine ⟨?_, ?_, ?_, ?_⟩ <;>
  · rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega

/-! ## P6 — memory: Π contexts per die on the full-int8 partition (`[FORK-mem-*]`) -/
/-- the tightest dies (MoE: 4 layers + embedding; dense: 15 layers + embedding) hold n = L · Π context
    tokens of f16 KV iff n ≤ 1 925 823 / 551 253 — eight 32k contexts leave 27 / 17 GB free, where the
    two-instance plan sits on a 24.5 MB margin (negative once the page-waste term is charged). -/
theorem P6_memory (n : Nat) :
    (4 * mLayer + mEmbed + 4 * kvTok * n + ws + ort ≤ dieMem ↔ n ≤ 1925823) ∧
    (15 * dLayer + dEmbed + 15 * kvTok * n + ws + ort ≤ dieMem ↔ n ≤ 551253) ∧
    8 * 32768 ≤ 551253 ∧ 1925823 / 8 = 240727 ∧ 551253 / 8 = 68906 ∧ 2 * 1048576 > 1925823 := by
  have h : 4 * mLayer + mEmbed + ws + ort = 54447308800 ∧ 15 * dLayer + dEmbed + ws + ort = 52131004416 ∧
      kvTok = 4096 ∧ dieMem = 86000000000 := by decide
  refine ⟨?_, ?_, by decide, by decide, by decide, by decide⟩
  · have e : 4 * mLayer + mEmbed + 4 * kvTok * n + ws + ort = 54447308800 + 16384 * n := by
      rw [← h.1, h.2.2.1]; omega
    rw [e, h.2.2.2]; constructor <;> intro h' <;> omega
  · have e : 15 * dLayer + dEmbed + 15 * kvTok * n + ws + ort = 52131004416 + 61440 * n := by
      rw [← h.2.1, h.2.2.1]; omega
    rw [e, h.2.2.2]; constructor <;> intro h' <;> omega

/-- the draft model's die (dense position 1) is lighter than the embedding die, so P6's dense line binds. -/
theorem P6_draft_die : 15 * dLayer + draft ≤ 15 * dLayer + dEmbed := by decide

/-! ## S — member S: every layer step on all 8 dies (`[FORK-split-*]`); the model is `step_tsplit3` -/
/-- one host gather/broadcast of a [1, d] partial: both dies of a card out, both results in, two latencies. -/
def tReduce (d : Nat) : Nat := tn (d * 4) 190 + tn (d * 4) 273 + tn (d * 2) 139 + tn (d * 2) 276 + 2 * lam
def splitMoe (launch : Nat) : Nat :=
  28 * (tn mAttn (8 * rGemm) + 16000 + 24 * slabM0 / 8 + amort80 / 8) + tn mEmbed (8 * rGemm)
  + (28 * 7 + 2) * launch + 28 * 4 * cQ + 28 * 2 * tReduce 4096
def splitDense (launch : Nat) : Nat :=
  120 * (tn dLayer (8 * rGemm) + dfr32 / 8) + tn dEmbed (8 * rGemm)
  + (120 * 6 + 2) * launch + 120 * 4 * cQ + 120 * 2 * tReduce 16384

/-- ONE sequence: MoE 38.1 ms → 6.556 tokens/s/card (3.4× the chain), dense 384.3 ms → 0.650 (6.2×); at
    the realized launch bound 9.178 / 0.725. The step is launch-bound (47 % MoE at 91 µs): the cell is a
    ceiling on a mechanism whose concurrency is unmeasured. -/
theorem S1_cells : splitMoe 91000 = 38128640 ∧ tps 1000 38128640 = 6556 ∧
    splitMoe 36000 = 27238640 ∧ tps 1000 27238640 = 9178 ∧
    splitDense 91000 = 384330040 ∧ tps 1000 384330040 = 650 ∧
    splitDense 36000 = 344620040 ∧ tps 1000 344620040 = 725 ∧
    129743539 * 10 / 38128640 = 34 ∧ 2403248669 * 10 / 384330040 = 62 ∧
    (28 * 7 + 2) * 91000 * 1000 / 38128640 = 472 := by decide

/-- member S fits with room: an eighth of every layer per die. -/
theorem S2_memory : (28 * mLayer + 2 * mEmbed) / 8 = 45375291392 ∧ (120 * dLayer + 2 * dEmbed) / 8 = 48340402176 ∧
    48340402176 + 120 * kvTok * 32768 / 8 + ws + ort ≤ dieMem := by decide

/-- the two members answer different demands: with ONE sequence in flight member P is the chain (1.926)
    and member S is 6.556; with EIGHT in flight member P is 13.832 and member S is still 6.556 unless it
    batches rows. -/
theorem S3_regimes : pipe 1000 129743539 18073016 < tps 1000 38128640 ∧
    tps 1000 38128640 < pipe 8000 129743539 18073016 ∧ tps 1000 38128640 < pipe 4000 129743539 18073016 ∧
    pipe 2000 129743539 18073016 < tps 1000 38128640 := by decide

end Fork
