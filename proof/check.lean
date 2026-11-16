/-
  proof/check.lean — PROMPT-7 challenge round: INDEPENDENT re-derivations (namespace `Chk`).

  This file re-proves load-bearing cells of the corpus from the HW-MAP rows they trace to, in its own
  formulation. It imports nothing and shares no definition with model / moe / attn / fleet / alt / cheat:
  an agreement below is two routes landing on one number, and a disagreement is stated as a theorem
  about the number the corpus prints. Where a quantity is a corpus-DERIVED input of the check (not a
  measurement) it is named so (`tSer`, `tPP`, `mergeT`, `mergeC`, `fix3`, `fix4`) — the dependence is
  visible in the statement.

  Core Lean 4 only (no Mathlib, no Batteries). No `axiom`, no `sorry`, no `native_decide`.
  Units as elsewhere: bytes; rates in tenths of GB/s (1 B/ns = 1 GB/s); time in ns (floor);
  tokens/s per card in thousandths. `proof/check.py` prints the same numbers under `[CHK-*]`.

  Build: `lean proof/check.lean` (standalone) or `cd proof && lake build` (target `Check`).
  PROOF-COVERAGE-CHECK.md maps each theorem to the corpus row it re-derives and the verdict.
-/

namespace Chk

/-! ## Inputs. `[M]` = HW-MAP measured row, `[A]` = assumption, `[C]` = corpus-derived input. -/
def MiB : Nat := 1048576
def GiB : Nat := 1073741824
def GB : Nat := 1000000000
/-- [M] full W8 decode kernel 174.6 GB/s; expert-GEMM full dispatch M0 165.8 (t = 1) / 170.2 (t ≥ 4). -/
def rGemm : Nat := 1746
def rM0 : Nat := 1658
def rM0T4 : Nat := 1702
/-- [M] vector i4→f16 unpack, 5.3 GB/s per core of int4 bytes. -/
def rW4 : Nat := 53
/-- [M] host bounce 12.2 µs per direction; launch + queue floor 91 µs; on-device quantization pass 43.7 µs. -/
def lam : Nat := 12200
def tLaunch : Nat := 91000
def cQ : Nat := 43700
/-- [M] 86 GB usable per die. [A] 2 GiB runtime overhead + 64 MiB workspace per die (H8 / H11, UNMEASURED). -/
def dieMem : Nat := 86 * GB
def ort : Nat := 2 * GiB
def ws : Nat := 64 * MiB
/-- [M] deferred-guard trip-free cells (ns per layer, t = 1) at 32k / 128k / 1M; legacy scan and the
    adversarial canonical cell at 32k (session 5). -/
def dfr32 : Nat := 945500
def dfr128 : Nat := 3618800
def dfr1M : Nat := 28694000
def leg32 : Nat := 1514900
def canon32 : Nat := 1818100
/-- [C] DESIGN-2's DERIVED slab times (serial / ping-pong regime; `moe.lean`): never measured kernels. -/
def tSer : Nat := 122979
def tPP : Nat := 97015
/-- [C] erratum-19 cold merge per int4 core-slab, throughput / chained (ALTERNATIVES `[PA-cold-merge]`). -/
def mergeT : Nat := 8313
def mergeC : Nat := 32614
/-- [C] attention fixed cost per step: round-3 rowmax-T chain / round-4 lazy-T chain (`attn.py`). -/
def fix3 : Nat := 18820
def fix4 : Nat := 19328

/-- ns for `b` bytes at `r` tenths of GB/s. -/
def tn (b r : Nat) : Nat := b * 10 / r
/-- thousandths of tokens/s per card (4 cards) at aggregate concurrency `c` (thousandths of one stream). -/
def tps (c T : Nat) : Nat := 1000 * c * 1000000 / (4 * T)

/-! ## A — shapes and the minimum-dies theorem (PROBLEM-4's headline question) -/
def dLayer : Nat := 16384 * (16384 + 2 * 8 * 128) + 16384 * 16384 + 3 * 16384 * 53248
def dEmbed : Nat := 16384 * 128256
def dTotal : Nat := 120 * dLayer + 2 * dEmbed
def mAttn : Nat := 4096 * (4096 + 2 * 8 * 128) + 4096 * 4096
def mExp : Nat := 256 * 3 * 4096 * 4096
def mLayer : Nat := mAttn + mExp
def mEmbed : Nat := 4096 * 128256
def mTotal : Nat := 28 * mLayer + 2 * mEmbed
def kvTok : Nat := 2 * 8 * 128 * 2
def draftW : Nat := GB
def draftKv : Nat := 24 * 4096 * (2 * 8 * 64 * 2)

theorem A1_totals : dTotal = 386723217408 ∧ mTotal = 363002331136 ∧ dLayer = 3187671040 ∧
    mLayer = 12926844928 ∧ kvTok = 4096 := by decide

/-- Four dies cannot hold the int8 weights under ANY split of the bytes — sub-layer, per-expert, per-row;
    the corpus's `T_min_dies_dense_4` / `_moe_4` quantify over whole-layer counts only. -/
theorem A2_four_dies_any_split (w0 w1 w2 w3 : Nat) :
    (w0 + w1 + w2 + w3 = dTotal → ¬ (w0 ≤ dieMem ∧ w1 ≤ dieMem ∧ w2 ≤ dieMem ∧ w3 ≤ dieMem)) ∧
    (w0 + w1 + w2 + w3 = mTotal → ¬ (w0 ≤ dieMem ∧ w1 ≤ dieMem ∧ w2 ≤ dieMem ∧ w3 ≤ dieMem)) := by
  have h : dTotal = 386723217408 ∧ mTotal = 363002331136 ∧ dieMem = 86000000000 := by decide
  rw [h.1, h.2.1, h.2.2]
  constructor <;> intro hs hc <;> omega

/-- Five dies fit (L = 4k, B = 1), as an iff over the unmeasured per-die overhead `o`: the heaviest dense
    die (24 layers + lm_head + draft) tolerates 5.72 GB, the heaviest MoE die (6 layers + embedding) 7.75 GB;
    the assumed 2 GiB is inside both. -/
theorem A3_five_dies (o : Nat) :
    (24 * dLayer + dEmbed + draftW + draftKv + 24 * kvTok * 4096 + ws + o ≤ dieMem ↔ o ≤ 5723460096) ∧
    (6 * mLayer + mEmbed + 6 * kvTok * 4096 + ws + o ≤ dieMem ↔ o ≤ 7745821696) ∧
    ort ≤ 5723460096 ∧ 24 * 5 = 120 ∧ 6 * 3 + 5 * 2 = 28 := by
  have h : 24 * dLayer + dEmbed + draftW + draftKv + 24 * kvTok * 4096 + ws = 80276539904 ∧
      6 * mLayer + mEmbed + 6 * kvTok * 4096 + ws = 78254178304 ∧ dieMem = 86000000000 ∧
      ort = 2147483648 := by decide
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2]
  refine ⟨?_, ?_, by omega, by omega, by omega⟩ <;> constructor <;> intro h' <;> omega

/-! ## B — the round-7 chain step, rebuilt term by term (`T7r_step_cells`, `T7r_step_realized`) -/
/-- host-bounced exchange of the 8-die chain d1,d0,…,d0: 4 hops d1→d0, 3 hops d0→d1, logits out of d0,
    ids into d1, 16 one-way latencies. Link rates [M]: D2H 27.3 / 19.0, H2D 27.6 / 13.9 (die 0 / die 1). -/
def xch8 (d rows : Nat) : Nat :=
  4 * (tn (rows * d * 2) 190 + tn (rows * d * 2) 276) + 3 * (tn (rows * d * 2) 273 + tn (rows * d * 2) 139)
  + tn (rows * 128256 * 4) 273 + tn (rows * 4) 139 + 16 * lam
/-- the 4-die instance chain d1,d0,d1,d0: 8 latencies. -/
def xch4 (d rows : Nat) : Nat :=
  2 * (tn (rows * d * 2) 190 + tn (rows * d * 2) 276) + (tn (rows * d * 2) 273 + tn (rows * d * 2) 139)
  + tn (rows * 128256 * 4) 273 + tn (rows * 4) 139 + 8 * lam
/-- one 16 MiB expert slab at the measured M0 rate. -/
def slabM0 : Nat := 2 * MiB * 80 / rM0
def slabM0T4 : Nat := 2 * MiB * 80 / rM0T4
/-- one MoE layer: attention GEMMs + fixed launch cost + 3 slabs × `experts` + attention + 7 launches + 4 quant passes. -/
def moeLayer (slab attn launch experts : Nat) : Nat :=
  tn mAttn rGemm + 16000 + 3 * experts * slab + attn + 7 * launch + 4 * cQ
def moeStep (slab attn launch : Nat) : Nat :=
  28 * moeLayer slab attn launch 8 + tn mEmbed rGemm + 2 * launch + xch8 4096 1
def denseStep (attn launch : Nat) : Nat :=
  120 * (tn dLayer rGemm + attn + 6 * launch + 4 * cQ) + tn dEmbed rGemm + 2 * launch + xch8 16384 1
/-- the deferred cell amortized at retry share `t` (thousandths of launches), re-run 873 000 ns as the fleet model rounds it. -/
def amort (t : Nat) : Nat := dfr32 + t * 873000 / 1000

theorem B1_inputs : slabM0 = 101189 ∧ slabM0T4 = 98573 ∧ amort 80 = 1015340 ∧ amort 55 = 993515 ∧
    canon32 - dfr32 = 872600 ∧ dfr32 + 80 * 872600 / 1000 = 1015308 ∧ dfr32 + 55 * 872600 / 1000 = 993493 := by decide

theorem B2_moe_cells :
    moeStep slabM0 dfr32 tLaunch = 127788019 ∧ tps 1000 127788019 = 1956 ∧
    moeStep slabM0 (amort 80) tLaunch = 129743539 ∧ tps 1000 129743539 = 1926 ∧
    moeStep slabM0 (amort 55) tLaunch = 129132439 ∧ tps 1000 129132439 = 1935 ∧
    moeStep slabM0 dfr128 tLaunch = 202640419 ∧ tps 1000 202640419 = 1233 ∧
    moeStep slabM0 dfr1M tLaunch = 904746019 ∧ tps 1000 904746019 = 276 ∧
    moeStep slabM0 (amort 80) 36000 = 118853539 ∧ tps 1000 118853539 = 2103 := by decide

theorem B3_dense_cell : denseStep dfr32 tLaunch = 2403248669 ∧ tps 1000 2403248669 = 104 := by decide

/-- the MoE 32k layer is 54 % expert slabs, 22 % attention, 14 % launches at the 91 µs primary. -/
theorem B4_composition : moeLayer slabM0 (amort 80) tLaunch 8 = 4511899 ∧ 3 * 8 * slabM0 = 2428536 ∧
    2428536 * 1000 / 4511899 = 538 ∧ 1015340 * 1000 / 4511899 = 225 ∧ 7 * tLaunch * 1000 / 4511899 = 141 := by decide

/-! ## C — the two-instance cell at the round-7 anchors (round-4 C-3: in the repo only as a hard-coded
    print; `T7r_inst` and ledger row R7.4 still carry the superseded 3.853) -/
/-- resident bytes of a 7-layer instance die with `x` thousandths of the expert bytes as int4. -/
def instW (x : Nat) : Nat := 7 * (mAttn + mExp - mExp * x / 2000)
/-- KV room on an instance die at context `L` under overhead `o`. -/
def instRoom (L o : Nat) : Nat := dieMem - o - ws - 7 * kvTok * L
/-- one instance layer on a die with int4 share `x`: hot and cold slabs mixed in proportion (uniform routing). -/
def instLayer (hot cold attn launch x : Nat) : Nat :=
  tn mAttn rGemm + 16000 + 24 * (hot * (1000 - x) + cold * x) / 1000 + attn + 7 * launch + 4 * cQ
def instStep (hot cold attn launch : Nat) : Nat :=
  7 * instLayer hot cold attn launch 182 + 7 * instLayer hot cold attn launch 170
  + 7 * instLayer hot cold attn launch 170 + 7 * instLayer hot cold attn launch 182
  + tn mEmbed rGemm + 2 * launch + xch4 4096 1
/-- 1 MiB of int4 per core through the measured unpack. -/
def tCold0 : Nat := MiB * 10 / rW4

/-- the minimal int4 share per die, as an iff over every share: 182 ‰ on the embedding / lm_head dies,
    170 ‰ on the inner dies (`[R3-inst-fit]`, `T3r_inst_fit_moe_32k`). -/
theorem C1_min_share (x : Nat) (hx : x ≤ 1000) :
    (instW x + mEmbed ≤ instRoom 32768 ort ↔ 182 ≤ x) ∧ (instW x ≤ instRoom 32768 ort ↔ 170 ≤ x) := by
  have h : mAttn = 41943040 ∧ mExp = 12884901888 ∧ mEmbed = 525336576 ∧ dieMem = 86000000000 ∧
      ort = 2147483648 ∧ ws = 67108864 ∧ kvTok = 4096 := by decide
  unfold instW instRoom
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  constructor <;> constructor <;> intro h' <;> omega

theorem C2_instance_cells : tCold0 = 197844 ∧
    instStep slabM0 (tCold0 + mergeT) (amort 80) tLaunch = 142057473 ∧
    tps 2000 142057473 = 3519 ∧ tps 1990 142057473 = 3502 ∧
    instStep slabM0 (tCold0 + mergeC) (amort 80) tLaunch = 144931589 ∧
    tps 2000 144931589 = 3449 ∧ tps 1990 144931589 = 3432 := by decide

/-- the ns values the corpus prints (142 055 807 / 144 929 937) are NOT the model's: they reproduce only
    with the slab at 101 186 ns — the stale value in fleet.py's own comment — and sit 1 666 / 1 652 ns
    under the cells above. The three-decimal tokens/s are the same either way. -/
theorem C3_printed_ns : instStep 101186 (tCold0 + mergeT) (amort 80) tLaunch = 142055807 ∧
    instStep 101186 (tCold0 + mergeC) (amort 80) tLaunch = 144929937 ∧ slabM0 ≠ 101186 ∧
    142057473 - 142055807 = 1666 ∧ 144931589 - 144929937 = 1652 ∧
    tps 2000 142055807 = 3519 ∧ tps 2000 144929937 = 3449 := by decide

/-- replication beats the 8-die chain's 1.926 iff the aggregate concurrency c ≥ 1.095 / 1.118. -/
theorem C4_concurrency (c : Nat) :
    (1927 ≤ tps c 142057473 ↔ 1095 ≤ c) ∧ (1927 ≤ tps c 144931589 ↔ 1118 ≤ c) := by
  unfold tps
  constructor
  · rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega
  · rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega

/-! ## D — the 32k lever tie and its break-even (round-4 C-1: the 5.32 % is a hard-coded print) -/
theorem D1_e29 : 28 * 24 * (tSer - slabM0) = 14642880 := by decide

/-- fusion (legacy → deferred) ≥ E29 iff the per-layer cell ≤ 991 940 ns (`T7r_tie32k_iff`). -/
theorem D2_line (T : Nat) (hT : T ≤ 1514900) : 14642880 ≤ 28 * (1514900 - T) ↔ T ≤ 991940 := by
  constructor <;> intro h <;> omega

/-- in retry share: p per 100 000 launches clears the line iff p ≤ 5 319 (5.32 %); the measured
    8.0 % / 5.5 % sit 2.68 / 0.18 points above — E29 first on both caps, the wide cap by 181 per 100 000. -/
theorem D3_breakeven (p : Nat) :
    (945500 * 100000 + p * 873000 ≤ 991940 * 100000 ↔ p ≤ 5319) ∧
    8000 - 5319 = 2681 ∧ 5500 - 5319 = 181 := by
  refine ⟨?_, by decide, by decide⟩
  constructor <;> intro h <;> omega

/-- WHAT THE TIE RANKS. The fusion gain is measured − measured. The E29 "gain" is DESIGN-2's derived
    serial slab minus the measured kernel; against DESIGN-2's two other derived baselines the measured
    kernel is SLOWER (direct-serial 99 374, ping-pong 97 015) and the same lever reads −1.22 / −2.80 ms.
    The ranking's sign is a choice of counterfactual; both levers are banked. -/
theorem D4_baseline : 99374 < slabM0 ∧ tPP < slabM0 ∧ slabM0 < tSer ∧
    28 * 24 * (slabM0 - 99374) = 1219680 ∧ 28 * 24 * (slabM0 - tPP) = 2804928 := by decide

/-! ## E — MoE-128k attention-vs-weights, legs-conditional (`T3r_moe128k_lines`), in whole-stream form:
    the corpus sums 256 floored per-block times; here the KV extent is one stream of
    131072 × 4096 B × (16 + legs)/16. Same three lines. -/
theorem E1_weights : tn mAttn rGemm + 16000 + 24 * tSer = 3207719 ∧ 131072 * kvTok = 536870912 ∧
    3207719 - fix4 = 3188391 ∧ tn mAttn rGemm + 16000 + 24 * slabM0 = 2684759 := by decide

theorem E2_lines (G : Nat) (hG : 0 < G) :
    (3207719 ≤ 536870912 * 10 * 16 / (16 * G) + 19328 ↔ G ≤ 1683) ∧
    (3207719 ≤ 536870912 * 10 * 17 / (16 * G) + 19328 ↔ G ≤ 1789) ∧
    (3207719 ≤ 536870912 * 10 * 18 / (16 * G) + 19328 ↔ G ≤ 1894) := by
  have k0 : 3188391 ≤ 536870912 * 10 * 16 / (16 * G) ↔ G ≤ 1683 := by
    rw [Nat.le_div_iff_mul_le (by omega)]; constructor <;> intro h <;> omega
  have k1 : 3188391 ≤ 536870912 * 10 * 17 / (16 * G) ↔ G ≤ 1789 := by
    rw [Nat.le_div_iff_mul_le (by omega)]; constructor <;> intro h <;> omega
  have k2 : 3188391 ≤ 536870912 * 10 * 18 / (16 * G) ↔ G ≤ 1894 := by
    rw [Nat.le_div_iff_mul_le (by omega)]; constructor <;> intro h <;> omega
  refine ⟨⟨fun h => k0.mp (by omega), fun h => by have := k0.mpr h; omega⟩,
    ⟨fun h => k1.mp (by omega), fun h => by have := k1.mpr h; omega⟩,
    ⟨fun h => k2.mp (by omega), fun h => by have := k2.mpr h; omega⟩⟩

/-- the lines are superseded by measurement: the deferred 128k cell exceeds the weight layer by 12.8 %
    on the derived anchor and 34.8 % on the measured M0 slab — attention-bound at every page size. -/
theorem E3_superseded : 3207719 < dfr128 ∧ (dfr128 - 3207719) * 1000 / 3207719 = 128 ∧
    2684759 < dfr128 ∧ (dfr128 - 2684759) * 1000 / 2684759 = 347 := by decide

/-- HW-MAP's E21 sentence quotes the round-2 line (167.7) with the round-3 line's margins (0.8 / 0.5 %
    are against 168.3; against 167.7 they are 0.4 / 0.9 %). Tenths of a percent, round half up. -/
theorem E4_margins : (2 * (1683 - 1670) * 1000 + 1683) / (2 * 1683) = 8 ∧ (2 * (1692 - 1683) * 1000 + 1683) / (2 * 1683) = 5 ∧
    (2 * (1677 - 1670) * 1000 + 1677) / (2 * 1677) = 4 ∧ (2 * (1692 - 1677) * 1000 + 1677) / (2 * 1677) = 9 := by decide

/-! ## F — the instance fit margin (`T3r_instance_margin`): an ASSUMPTION with megabytes of slack -/
theorem F1_margin (o : Nat) :
    (instW 182 + mEmbed ≤ instRoom 32768 o ∧ instW 170 ≤ instRoom 32768 o) ↔ o ≤ 2147483648 + 24485516 := by
  have h : instW 182 + mEmbed = 83812201535 - 67108864 - 7 * 4096 * 32768 ∧
      instW 170 = 83828030836 - 67108864 - 7 * 4096 * 32768 ∧ dieMem = 86000000000 ∧ ws = 67108864 ∧
      kvTok = 4096 := by decide
  unfold instRoom
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2]
  constructor
  · intro h'; omega
  · intro h'; constructor <;> omega

/-- one thousandth of x frees 45.1 MB per die: +23 ‰ per GB of extra overhead; and at x = 1000 the die
    has 39 GB of room — the unmeasured overhead moves x, it cannot break the fit. -/
theorem F2_slope : 7 * mExp / 2000 = 45097156 ∧ 22 * 45097156 < GB ∧ GB ≤ 23 * 45097156 ∧
    24485516 * 1000000 / dieMem = 284 ∧ instRoom 32768 0 - (instW 1000 + mEmbed) = 39077272576 := by decide

/-! ## G — the instance gain as an iff over the int4 core-slab time (`T3r_inst_breakeven`) -/
/-- round-3 attention per layer: 64 blocks of 256 KiB per core at the E21 256-KiB rate 169.2 + the chain's fixed cost. -/
def a3 : Nat := 64 * (262144 * 80 / 1692) + fix3

theorem G1_form (tc : Nat) : instStep 99374 tc a3 tLaunch =
    7 * (256223 + 24 * (99374 * 818 + tc * 182) / 1000 + 812036 + 637000 + 174800)
    + 7 * (256223 + 24 * (99374 * 830 + tc * 170) / 1000 + 812036 + 637000 + 174800)
    + 7 * (256223 + 24 * (99374 * 830 + tc * 170) / 1000 + 812036 + 637000 + 174800)
    + 7 * (256223 + 24 * (99374 * 818 + tc * 182) / 1000 + 812036 + 637000 + 174800)
    + 3008800 + 182000 + 118735 := rfl

theorem G2_round3 (tc : Nat) : a3 = 812036 ∧ instStep 99374 tCold0 a3 tLaunch = 134376737 ∧
    tps 2000 134376737 = 3720 ∧ (1803 ≤ tps 2000 (instStep 99374 tc a3 tLaunch) ↔ tc ≤ 1406404) := by
  refine ⟨by decide, by decide, by decide, ?_⟩
  rw [G1_form]; unfold tps
  rw [Nat.le_div_iff_mul_le (by omega)]
  constructor <;> intro h <;> omega

theorem G3_form (tc : Nat) : instStep slabM0 tc (amort 80) tLaunch =
    7 * (256223 + 24 * (101189 * 818 + tc * 182) / 1000 + 1015340 + 637000 + 174800)
    + 7 * (256223 + 24 * (101189 * 830 + tc * 170) / 1000 + 1015340 + 637000 + 174800)
    + 7 * (256223 + 24 * (101189 * 830 + tc * 170) / 1000 + 1015340 + 637000 + 174800)
    + 7 * (256223 + 24 * (101189 * 818 + tc * 182) / 1000 + 1015340 + 637000 + 174800)
    + 3008800 + 182000 + 118735 := rfl

/-- NEW (not in the corpus): the same iff at the round-7 anchors — two instances beat the chain's 1.926
    iff the cold slab (merge included) ≤ 1 198 895 ns; the merged slabs 206 157 / 230 458 are ≥ 5.2× inside. -/
theorem G4_round7 (tc : Nat) :
    (1927 ≤ tps 2000 (instStep slabM0 tc (amort 80) tLaunch) ↔ tc ≤ 1198895) ∧
    tCold0 + mergeC = 230458 ∧ 1198895 * 10 / 230458 = 52 := by
  refine ⟨?_, by decide, by decide⟩
  rw [G3_form]; unfold tps
  rw [Nat.le_div_iff_mul_le (by omega)]
  constructor <;> intro h <;> omega

/-! ## H — speculative-decoding thresholds (`T6r_spec6_thresholds`, `T6r_spec_dense_line`) -/
/-- tokens per verify step at acceptance a (thousandths), k = 3 drafts: 1 + α + α² + α³ with the corpus's floors. -/
def tau3 (a : Nat) : Nat := 1000 + a + a * a / 1000 + a * a / 1000 * a / 1000
/-- three draft tokens: 1 GB of weights + the window KV + 121 launches + 96 quant passes + logits out + a bounce, each. -/
def draft3 : Nat :=
  3 * (tn draftW rGemm + tn draftKv rGemm + 121 * tLaunch + 24 * 4 * cQ + tn (128256 * 4) 273 + 2 * lam)
/-- the MoE verify step at t = 4: 32 active experts under uniform routing, the 16 rows in one fragment. -/
def moeVerify (slab attn : Nat) : Nat :=
  28 * moeLayer slab attn tLaunch 32 + tn mEmbed rGemm + 2 * tLaunch + xch8 4096 4 + draft3
def denseVerifyBase : Nat :=
  120 * (tn dLayer rGemm + 6 * tLaunch + 4 * cQ) + tn dEmbed rGemm + 2 * tLaunch + xch8 16384 4 + draft3

theorem H1_round6_steps : moeStep tSer dfr32 tLaunch = 142430899 ∧ moeVerify tSer dfr32 = 456819203 ∧
    tau3 700 = 2533 := by decide
theorem H2_round6_line : ∀ a, a < 1001 → (tau3 a * 142430899 < 1000 * 456819203 ↔ a ≤ 854) := by decide +kernel

/-- NEW: on the round-7 anchors (M0 slabs at t = 1 and t ≥ 4) the MoE loss line is 0.824, not the 0.854
    the corpus still quotes (that line rode the retired derived slab). Verdict at α = 0.7 unchanged: a loss. -/
theorem H3_round7_steps : moeVerify slabM0T4 dfr32 = 391215875 ∧
    tps 1000 127788019 = 1956 ∧ 1000 * tau3 700 * 1000000 / (4 * 391215875) = 1618 := by decide
theorem H4_round7_line : ∀ a, a < 1001 → (tau3 a * 127788019 < 1000 * 391215875 ↔ a ≤ 824) := by decide +kernel

/-- dense: the verify step is 2 356 301 528 + 120 v and at α = 0.7 beats t = 1 iff v ≤ 31 092 727 ns per layer. -/
theorem H5_dense (v : Nat) : denseVerifyBase = 2356301528 ∧
    (1000 * (2356301528 + 120 * v) < 2533 * 2403248669 ↔ v ≤ 31092727) := by
  refine ⟨by decide, ?_⟩
  constructor <;> intro h <;> omega

/-! ## I — the f32 online-chain drift bound (`T4r_drift_online`, `T5r_drift`) -/
/-- longest f32 addition chain into O: block-local sum of the 128-token partials, one hand-over, one running add per block. -/
def chainO (L b : Nat) : Nat := (b / 128 - 1) + 1 + L / b
/-- into S: 8 reels into the block accumulator, two folds, one running add per block, the final 16 → 1. -/
def chainS (L b : Nat) : Nat := b * 16 / 1024 + 2 + L / b + 4
/-- ⌈n · 2⁻²⁴ · 10⁶⌉ ppm: n round-to-nearest f32 additions, first order, relative to the sum of magnitudes. -/
def ppmCeil (n : Nat) : Nat := (n * 1000000 + 16777215) / 16777216

theorem I1_cells : chainO 1048576 512 = 2052 ∧ chainS 1048576 512 = 2062 ∧
    ppmCeil 2052 + ppmCeil 2062 = 246 ∧ ppmCeil (chainO 1048576 256) + ppmCeil (chainS 1048576 256) = 490 ∧
    ppmCeil (chainO 32768 512) + ppmCeil (chainS 32768 512) = 10 := by decide

/-- the bound omits the matrix unit's own accumulation inside each 128-token partial (order UNMEASURED);
    charged as 127 further sequential roundings the 1M bound is 253 ppm — the verdict (ships) is unchanged. -/
theorem I2_with_mma : ppmCeil (2052 + 127) + ppmCeil 2062 = 253 ∧ 253 < 1000 := by decide

theorem I3_ship_line (n : Nat) : ppmCeil n ≤ 499 ↔ n ≤ 8371 := by
  unfold ppmCeil; constructor <;> intro h <;> omega

/-- every context up to 8 357 blocks of 512 tokens (4.28 M tokens) ships deterministically. -/
theorem I4_range (nb : Nat) (h : nb ≤ 8357) :
    ppmCeil (chainO (512 * nb) 512) + ppmCeil (chainS (512 * nb) 512) < 1000 := by
  have e : chainO (512 * nb) 512 = nb + 4 ∧ chainS (512 * nb) 512 = nb + 14 := by
    unfold chainO chainS; constructor <;> omega
  rw [e.1, e.2]
  have a := (I3_ship_line (nb + 4)).mpr (by omega)
  have b := (I3_ship_line (nb + 14)).mpr (by omega)
  omega

/-! ## J — deferred guard vs legacy scan (`[R6-trip-breakeven]`) -/
theorem J1_breakeven (p : Nat) : 945500 * 100000 + p * 872600 < 1514900 * 100000 ↔ p ≤ 65253 := by
  constructor <;> intro h <;> omega

/-- effective KV rates, tenths of GB/s, round half up: 142.0 / 148.4 / 149.7 trip-free, 132.2 / 135.1 amortized. -/
theorem J2_rates : (2 * (32768 * 4096) * 10 + 945500) / (2 * 945500) = 1420 ∧
    (2 * (131072 * 4096) * 10 + 3618800) / (2 * 3618800) = 1484 ∧
    (2 * (1048576 * 4096) * 10 + 28694000) / (2 * 28694000) = 1497 ∧
    (2 * (32768 * 4096) * 10 + 1015340) / (2 * 1015340) = 1322 ∧
    (2 * (32768 * 4096) * 10 + 993515) / (2 * 993515) = 1351 := by decide

/-! ## K — the E40 stage-overlap bound and its gate (`[E40-*]`), from the measured phases -/
theorem K1_bound : 770800 + 51000 = 821800 ∧ 64 * 12394 + 51000 = 844216 ∧
    dfr32 - 821800 = 123700 ∧ dfr32 - 844216 = 101284 ∧ 770800 / 512 = 1505 ∧ 12394 / 8 = 1549 ∧
    (2 * 123700 * 1000 + dfr32) / (2 * dfr32) = 131 ∧ (2 * 101284 * 1000 + dfr32) / (2 * dfr32) = 107 := by decide

/-- E40 beats the deferred kernel iff the per-barrier cost φ is under the line: 1 687 ns on the most
    tolerant consistent cell, 635 ns on the least tolerant k ≤ 2 cell. The measured erratum-29 crossing
    (10–20 µs) is 5.9×–11.9× above the tolerant line. -/
theorem K2_gate (phi : Nat) :
    (64 * (1594 - 1505) + 64 * phi + 10000 < 123700 ↔ phi ≤ 1687) ∧
    (64 * (1438 - 2 * 1549) + 128 * phi + 20000 < 101284 ↔ phi ≤ 635) ∧
    59 * 1687 ≤ 10000 * 10 ∧ 10000 * 10 < 60 * 1687 ∧ 118 * 1687 ≤ 20000 * 10 ∧ 20000 * 10 < 119 * 1687 := by
  refine ⟨?_, ?_, by decide, by decide, by decide, by decide⟩ <;> constructor <;> intro h <;> omega

/-! ## L — the realized per-launch overhead (HW-MAP serving row; `tLaunch7`) -/
/-- 7.7 ms over 24 × 9 launches is 35.6 µs ≤ 36; 216 serialized 91 µs launches (19.7 ms) exceed the whole
    non-GEMM share. But the 7.7 ms is the residual 67.0 − 59.3 ms of a byte-accounted GEMM, not a
    measurement: allowing the in-situ GEMM the pure-read roof (181.3 vs 174.6) the bound is 45.8 µs and the
    realized headline 2.069, not 2.103. The 91 µs serialized reading is excluded either way. -/
theorem L1_realized : 7700000 / (24 * 9) = 35648 ∧ 35648 ≤ 36000 ∧ 7700000 < 24 * 9 * tLaunch ∧
    67000000 - 59300000 = 7700000 ∧ (67000000 - 59300000 * 1746 / 1813) / (24 * 9) = 45793 ∧
    moeStep slabM0 (amort 80) 45793 = 120792553 ∧ tps 1000 120792553 = 2069 ∧ 45793 < tLaunch := by decide

/-! ## M — exact i32 accumulation of the MoE chains (PROBLEM-2; `T_overflow_umax`) -/
theorem M1_overflow (u : Nat) :
    (u * (127 * 127 * 4096) < 2147483648 ↔ u ≤ 32) ∧ (u * (127 * 127 * 7168) < 2147483648 ↔ u ≤ 18) ∧
    2147092480 = 127 * 127 * 133120 ∧ 133120 < 33 * 4096 ∧ 32 * 4096 < 133120 := by
  refine ⟨?_, ?_, by decide, by decide, by decide⟩ <;> constructor <;> intro h <;> omega

/-! ## N — PROBLEM-1: issue occupancy is not compute utilization -/
/-- K = N = 8192: 4 096 calls per core × 15 ns = 61.4 µs; 12.6 % of the quoted 487 µs stream (a 137.8 GB/s
    stream — the pre-direct-load kernel), 16.0 % of the shipped 174.6 stream. Useful compute at m = 1 is
    1.96 % of the die's 17.8 TFLOPS (hundredths of a percent): the "12.5 % of compute peak" of CHEATSHEET §0
    is the ISSUE occupancy. -/
theorem N1_occupancy : 8192 / 16 * (8192 / 128) / 8 = 4096 ∧ 4096 * 15 = 61440 ∧
    (2 * 61440 * 1000 + 487000) / (2 * 487000) = 126 ∧ tn (8192 * 8192) rGemm = 384357 ∧
    (2 * 61440 * 1000 + 384357) / (2 * 384357) = 160 ∧ 1746 * 2 * 10000 / 178000 = 196 := by decide

/-- two HW-MAP rows side by side: at 17.8–26.6 TFLOPS/die a full (16,16,128) fragment (65 536 FLOPs) takes
    29.5–19.7 ns of one core's matrix unit (ps below) — above the 15 ns "issue cost". The 15 ns is an issue
    latency under a bandwidth-bound stream; multiplied by call counts it under-charges a compute-bound
    regime 1.31×–1.96×. PROBLEM-1's m = 64 flat target (128 OPs/byte) sits above the low-figure ridge. -/
theorem N2_fragment_time : 16 * 16 * 128 * 2 = 65536 ∧ 65536 * 8 * 1000 / 17800 = 29454 ∧
    65536 * 8 * 1000 / 26600 = 19710 ∧ 15000 < 19710 ∧ 2 * 64 * 1738 > 178000 ∧ 2 * 64 * 1738 ≤ 266000 := by decide

/-! ## O — the die-level roofline (CHEAT-MATH §B; `Cheat.ridge_die_bounds`, `free_rows_die`) -/
theorem O1_ridge (m : Nat) : 102 * 1738 < 178000 ∧ 178000 < 103 * 1738 ∧
    (2 * m * 1738 ≤ 178000 ↔ m ≤ 51) ∧ (4 * m * 1738 ≤ 178000 ↔ m ≤ 25) ∧
    (2 * m * 1738 ≤ 266000 ↔ m ≤ 76) ∧ (4 * m * 1738 ≤ 266000 ↔ m ≤ 38) := by
  refine ⟨by decide, by decide, ?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega

/-! ## C′ — the corpus's own round-4 page-waste term against the fit margin (`[R4-waste-256k]`) -/
/-- one partially filled 256 KiB page per (head, K|V) per layer: 29.3 MB per 7-layer die — more than the
    24.5 MB margin. At x = 170 the inner dies are 4.8 MB over; the minimal shares are 182 / 171. Rounds 6, 7
    and 7F kept 170, and `T3r_instance_margin` is a theorem of the waste-free memory model. -/
theorem C5_page_waste (x : Nat) (hx : x ≤ 1000) :
    7 * 16 * (262144 - 256) = 29331456 ∧ 29331456 - 24485516 = 4845940 ∧
    (instW x ≤ instRoom 32768 ort - 29331456 ↔ 171 ≤ x) ∧
    (instW x + mEmbed ≤ instRoom 32768 ort - 29331456 ↔ 182 ≤ x) := by
  have h : mAttn = 41943040 ∧ mExp = 12884901888 ∧ mEmbed = 525336576 ∧ dieMem = 86000000000 ∧
      ort = 2147483648 ∧ ws = 67108864 ∧ kvTok = 4096 := by decide
  unfold instW instRoom
  rw [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2]
  refine ⟨by decide, by decide, ?_, ?_⟩ <;> constructor <;> intro h' <;> omega

/-! ## Q — PROBLEM-2: the region-difference accumulator under the MEASURED saturation
    (HW-MAP: i32 accumulator SILENTLY SATURATES at 2³¹ − 1; L0C has no zero-init).
    DESIGN-2 P2 / `T_overflow_modular_diff` prove the difference exact "whatever the region held before" in
    WRAP arithmetic, and P3 / `T_overflow_region_exact` bound a running sum that starts at 0. -/
/-- saturating add at the positive rail, on naturals (the measured semantics). -/
def satAdd (b s : Nat) : Nat := min (b + s) 2147483647

theorem Q1_counterexample : satAdd 2147483000 1000 - 2147483000 = 647 ∧
    (2147483000 + 1000) - 2147483000 = 1000 := by decide

/-- under saturation the difference is exact iff the launch state leaves room for the whole sum. -/
theorem Q2_exact_iff (b s : Nat) (hb : b ≤ 2147483647) : satAdd b s - b = s ↔ b + s ≤ 2147483647 := by
  unfold satAdd
  rw [Nat.min_def]
  split <;> constructor <;> intro h <;> omega

/-- worst-case safe launch state at K = 4096: 2.02·10⁹ at D = 8 (two uses per region), 6.9·10⁸ at D = 128
    (22 uses); a region left holding the f32 pattern of 1.0 or 2.0 has room for 16 worst-case chains, the
    pattern of +Inf for none; the measured saturation probe itself started within 391 167 of zero. -/
theorem Q3_headroom : 2147483647 - 2 * (127 * 127 * 4096) = 2015354879 ∧
    2147483647 - 22 * (127 * 127 * 4096) = 694067199 ∧
    (2147483647 - 1065353216) / (127 * 127 * 4096) = 16 ∧ (2147483647 - 1073741824) / (127 * 127 * 4096) = 16 ∧
    (2147483647 - 2139095040) / (127 * 127 * 4096) = 0 ∧ 2147483647 - 2147092480 = 391167 := by decide

/-! ## R — the accuracy class of per-token int8 activations (PROBLEM-1 / -2 numerics gate) -/
/-- rint to 127 levels has rms error max/(127√12) with 127√12 ∈ (439, 440): relative rms error = crest/440.
    A uniform row (rms² = max²/3) lands at exactly 1/254 — 3.9·10⁻³, four times the "1e-3 class". -/
theorem R1_quantizer : 439 * 439 < 127 * 127 * 12 ∧ 127 * 127 * 12 < 440 * 440 ∧
    127 * 127 * 12 = 3 * (254 * 254) ∧ 254 < 1000 ∧ 1000000 / 254 = 3937 := by decide

/-! ## S — the two-instance plan against the same two sequences on the unchanged int8 chain -/
def denseStepB (B attn : Nat) : Nat :=
  120 * (tn dLayer rGemm + B * attn + 6 * tLaunch + 4 * cQ) + tn dEmbed rGemm + 2 * tLaunch + xch8 16384 B

/-- dense: two rows batched read the weights once — 0.198 tokens/s/card against the two-instance plan's
    0.149 / 0.140 (`T6r_inst6`, [C]: its step 3 337 073 683 ns). Even at the MEASURED two-client batching
    factor 1.53 the chain gives 0.159. Replication would need an aggregate concurrency of 2.643 > 2. -/
theorem S1_dense_batching (c : Nat) : denseStepB 2 dfr32 = 2516749780 ∧
    1000 * 2000 * 1000000 / (4 * 2516749780) = 198 ∧ 104 * 153 / 100 = 159 ∧
    (198 ≤ tps c 3337073683 ↔ 2643 ≤ c) := by
  refine ⟨by decide, by decide, by decide, ?_⟩
  unfold tps
  rw [Nat.le_div_iff_mul_le (by decide)]; constructor <;> intro h <;> omega

/-! ## T — the retry share where it is not measured (τ is measured at 32k, t = 1, one model) -/
theorem T1_breakeven_1M (p : Nat) :
    28694000 * 100000 + p * 27306000 < 46300000 * 100000 ↔ p ≤ 64476 := by
  constructor <;> intro h <;> omega

/-- IF trips were independent per 32k-token segment (an assumption; HW-MAP says they cluster), the measured
    8.0 % / 5.5 % put the 1M launch above the 64.476 % break-even, and the choice flips already at a 3.2 %
    segment rate: 0.968³² < 0.35524 < 0.969³². -/
theorem T2_independent_segments : 920 ^ 32 * 100000 < 35524 * 1000 ^ 32 ∧ 945 ^ 32 * 100000 < 35524 * 1000 ^ 32 ∧
    968 ^ 32 * 100000 < 35524 * 1000 ^ 32 ∧ 35524 * 1000 ^ 32 < 969 ^ 32 * 100000 := by decide

/-! ## U — E40 with the per-step fixed cost the three measured cells imply (`T6r_perblock`'s own chord) -/
/-- the 32k and 128k cells lie on 13 923 ns per block + 54 428 ns per step. Cross-block overlap cannot
    recover a per-step cost, so the reachable bound is cell − intercept − floor: 69 272 ns (F1) / 46 856 (F2),
    not 123 700 / 101 284; on F2 it is below the 51 000 ns bounce removal at φ = 0. -/
theorem U1_bound : (dfr128 - dfr32) / 192 = 13923 ∧ dfr32 - 64 * 13923 = 54428 ∧
    dfr32 - 54428 - 821800 = 69272 ∧ dfr32 - 54428 - 844216 = 46856 ∧ 46856 < 51000 ∧ 51000 < 69272 ∧
    (2 * 69272 * 1000 + dfr32) / (2 * dfr32) = 73 ∧ (2 * 46856 * 1000 + dfr32) / (2 * dfr32) = 50 := by decide

/-- the gate tightens to φ ≤ 1 082 ns (F1, one vector-carrying barrier per block); the measured erratum-29
    crossing is 9.2×–18.5× above it. -/
theorem U2_gate (phi : Nat) : (64 * phi < 69272 ↔ phi ≤ 1082) ∧
    92 * 1082 ≤ 10000 * 10 ∧ 10000 * 10 < 93 * 1082 ∧ 184 * 1082 ≤ 20000 * 10 ∧ 20000 * 10 < 185 * 1082 := by
  refine ⟨?_, by decide, by decide, by decide, by decide⟩
  constructor <;> intro h <;> omega

/-! ## V — the K-int8 lever on the measured rows (HW-MAP: same-K-extent time ratio 2.13×, exact ×20 at d = 64) -/
/-- the K half of the measured K+V stream phase (770.8 µs at 32k) is 385.4 µs per layer; halved it saves
    192.7 µs, at the measured 2.13× 204.5 µs — 2.8× the corrected E40 bound on F1, and not φ-gated.
    [A] the d = 64 ratio transfers to d = 128 production tiles; accuracy (E36) UNMEASURED. -/
theorem V1_kint8 : 770800 / 2 = 385400 ∧ 385400 - 385400 / 2 = 192700 ∧ 385400 - 385400 * 100 / 213 = 204462 ∧
    2 * 69272 < 192700 ∧
    tps 1000 (moeStep slabM0 (amort 80 - 192700) tLaunch) = 2010 ∧
    tps 1000 (moeStep slabM0 (amort 80 - 204462) tLaunch) = 2015 ∧
    tps 1000 (moeStep slabM0 (dfr128 - 4 * 192700) tLaunch) = 1380 ∧
    tps 1000 (moeStep slabM0 (dfr128 - 4 * 204462) tLaunch) = 1390 ∧
    tps 1000 (moeStep slabM0 (dfr1M - 32 * 192700) tLaunch) = 341 ∧
    tps 1000 (moeStep slabM0 (dfr1M - 32 * 204462) tLaunch) = 346 := by decide

/-! ## W — the planner's overhead terms against the one measured serving accounting -/
/-- on the measured stack (32 layers × 9 launches + 2) the planner's launch + quant terms are 32.0 ms at
    91 µs and 16.0 ms at 36 µs against a MEASURED non-GEMM share of 7.7 ms (4.2× / 2.1×): the "realized"
    reading still charges the quant pass on top of a residual that already contains it. With 26.7 µs per
    launch covering all non-GEMM work the MoE 32k cell is 2.229 (corpus: 1.926 primary / 2.103 realized). -/
theorem W1_overhead : 290 * 91000 + 32 * 4 * cQ = 31983600 ∧ 290 * 36000 + 32 * 4 * cQ = 16033600 ∧
    7700000 / 288 = 26736 ∧
    28 * (tn mAttn rGemm + 16000 + 24 * slabM0 + amort 80 + 7 * 26736) + tn mEmbed rGemm + 2 * 26736
      + xch8 4096 1 = 112124867 ∧ tps 1000 112124867 = 2229 := by decide

/-! ## X — the megakernel's pay line at the launch readings HW-MAP now carries (`T3r_mega_threshold`) -/
/-- per layer the megakernel removes 5 (dense) / 6 (MoE) launches and adds 4 / 5 flag rounds plus two
    DDR reductions ([C] 7 694 / 1 923 ns each). At the 91 µs primary the lines are the corpus's 109 903 /
    108 430 ns; at the realized 36 µs bound 41 153 / 42 430; at the 17 µs empty-launch floor 17 403 / 19 630. -/
theorem X1_lines (c : Nat) : tn 1343488 rGemm = 7694 ∧ tn 335872 rGemm = 1923 ∧
    (4 * c + 2 * 7694 ≤ 5 * 91000 ↔ c ≤ 109903) ∧ (5 * c + 2 * 1923 ≤ 6 * 91000 ↔ c ≤ 108430) ∧
    (4 * c + 2 * 7694 ≤ 5 * 36000 ↔ c ≤ 41153) ∧ (5 * c + 2 * 1923 ≤ 6 * 36000 ↔ c ≤ 42430) ∧
    (4 * c + 2 * 7694 ≤ 5 * 17000 ↔ c ≤ 17403) ∧ (5 * c + 2 * 1923 ≤ 6 * 17000 ↔ c ≤ 19630) := by
  refine ⟨by decide, by decide, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> constructor <;> intro h <;> omega

/-- at the erratum-29 primary reading (20 µs per flag round) the megakernel pays iff the launch it removes
    costs ≥ 19 078 ns (dense) / 17 308 ns (MoE) — inside the measured 17–36 µs band: undecided. -/
theorem X2_launch_line (T : Nat) :
    (4 * 20000 + 2 * 7694 ≤ 5 * T ↔ 19078 ≤ T) ∧ (5 * 20000 + 2 * 1923 ≤ 6 * T ↔ 17308 ≤ T) := by
  constructor <;> constructor <;> intro h <;> omega

/-! ## Y — what the 17.8 in CHEAT-MATH's ridge is -/
/-- 17.8 TFLOPS is 128 FLOP/byte × 139.06 GB/s = 80 % of the 173.8 stream — numerically the throughput of a
    stream-bound 128-row f16 GEMM (GFLOPS/128 in hundredths of GB/s); whether the n = 8k benchmark was so
    blocked is not recorded (SUSPECTED). What IS recorded: 17.8 is the low end of a measured range. The two
    other HW-MAP readings — 26.6 TFLOPS at n = 2k, and 15 ns per (16,16,128) call = 17 476 G-MAC/s =
    34.95 TFLOPS — put the ridge at 153 / 201 OPs/byte. The corpus's free-row counts (51 / 25) are the
    lowest of three readings; a 16-row tree is free on every one. -/
theorem Y1_ridge_readings : 17800 * 100 / 128 = 13906 ∧ 13906 * 1000 / 17380 = 800 ∧
    8 * 32768 / 15 = 17476 ∧ 2 * 17476 = 34952 ∧ 26600 < 34952 ∧
    266000 * 10 / 1738 = 1530 ∧ 349520 * 10 / 1738 = 2011 ∧ 2 * 16 * 1738 ≤ 178000 ∧ 4 * 16 * 1738 ≤ 178000 := by decide

/-! ## Z — CHEATSHEET candidate #3: the sign of "1.04×" -/
/-- half the bytes at the 42.0 GB/s int4-effective unpack against int8 at 87.6: time ratio 1.04 — SLOWER,
    not a gain cap; against the production f16 stream (142.0–149.7) 1.69–1.78× slower. Hundredths. -/
theorem Z1_kv4 : 876 * 100 / (2 * 420) = 104 ∧ 1420 * 100 / (2 * 420) = 169 ∧ 1497 * 100 / (2 * 420) = 178 := by decide

end Chk
