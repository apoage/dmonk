# DESIGN-2 — MoE grouped quant-GEMM decode kernel (one die, 8 cores)

> **ROUND-2 STATUS (proof session, commit after 7b82332)**: every derived number below is checked by
> `proof/moe.lean` (189 core-Lean theorems, 0 axioms) and printed by `proof/moe.py`; the claim ledger is
> `PROOF-COVERAGE-2.md`. Corrections the prover forced are applied in place and listed there (the W4
> "parity" claim, the regression decomposition, the per-step epilogue, the W-dyn loss range, the §8.2 c_res
> row units, the A-resident small-shape row, the −128 operand caveat, and smaller ones).
> **SILICON NOTE**: this design is anchored to HW-MAP@3eaf322's dense row (487 µs / 137.8 GB/s, S1-staged
> serial loader). The current HW-MAP (f951a5c) lists that path as the "serial fallback 138.9" and a
> DDR→L0B direct path at 174.6 flat (181.3 direct stream, ~181 pure-read roof). The theorems here are
> conditionals on the anchor: re-anchored to 138.9 the headline is 136.4 (T_sync_reanchor); the DDR-bound
> ceiling at the ~181 roof is 178.2 (T_sync_roof); a direct-path MoE kernel (no S1→L0B leg) is not modelled
> here and is the natural round-3 exercise.

Scope (PROBLEM-2.md): per decode step, t ∈ 1..16 tokens, each routed to k experts (k = 4..10), E = 64..512
experts, expert slab `W_e [K, N_e]`, K = 2048..7168, N_e = 512..4096, W8 (i8 + per-channel f32 scale s_e[n])
primary, W4 secondary; `y_τ[n] = Σ_{e ∈ topk(τ)} score_{τ,e} · s_e[n] · Σ_k x_τ[k]·W_e[k,n]`. Everything derives
from HW-MAP.md (as of commit 3eaf322, the silicon sync) and ISA.md. Status tags: **M** = measured in HW-MAP,
**D** = derived from measured numbers by arithmetic shown here, **P** = PRIOR, **A** = explicit assumption with
the experiment that measures it, **U** = UNMEASURED (branched, experiment named).

DESIGN.md is cited where it still holds (n-outer/k-inner ordering §1.4, the 64 KiB copy ring §2, barrier
edges B1–B9 §4.2, experiment conventions §8). Its f16×i8 route, (16,256,64) tile and G-family geometry are
pre-measurement history (HW-MAP errata 13, MMA shape constraints, settled fragment) and are not used.

Units: bytes/KiB/MiB binary; rates in GB/s decimal (1 B/ns = 1 GB/s); times in ns floored, quoted in µs
round-half-up; rates one decimal, round-half-up at 0.1 — the exact conventions of `proof/model.py`, and every
derived cell below is printed by **`proof/moe.py`** (integer arithmetic only, label `[Mx]`/`[T8]` in the text).

**Headline shape** (the HW-MAP vendor-floor shape, 24.6 GB/s): K = N_e = 4096, k = 8, t = 1, W8, E = 256.
Per-core column slice N_c = N_e/8 = 512. Weight bytes per step = 8 × 16 MiB = 128 MiB = 134.22 MB.

## Constants used

| Symbol | Value | Status / origin |
|---|---|---|
| R_ddr | 173.8 GB/s/die → 21.725 GB/s/core share when all 8 stream | M (card table) |
| R_stage | 180 GB/s/die = 22.5 GB/s/core, 64 KiB plain copies, per-core slabs | M (data-movement) |
| L | S1→L0 loader **26.5 GB/s/core under strict-serial barriers** | M; overlap/ping-pong and granule dependence **U** |
| c_mma | **15 ns per MMA call at (m,n,k) = (16,16,128)** | M |
| T_dense | **487 µs per core** for 8 MiB of i8 B + 128 KiB of i8 A = the realized dense W8 kernel, 137.8 GB/s aggregate, m=1 = m=16, fp64-verified 20/20 | M |
| c_res | **25.4 ns per call** = (487 000 − (8 MiB + 128 KiB)·10/265 − 4096·15) / 4096 ns — the part of T_dense not explained by loader bytes and MMA calls (barrier/flag waits, per-load overhead) | **D** by subtraction; one consistent decomposition, not a direct measurement (E13 splits it) |
| R_vec | 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core | M |
| T_launch | ~91 µs launch + queue floor | M |
| L0A, L0B | 64 KB each | M |
| L0C | 256 KB; **filling it to exactly 256 KB hangs** (errata 14) | M |
| S1 | ~1 MB (976 KiB) | P |
| US | 256 KB (≥ 208 evidenced) | P/M |
| R_vendor | 24.6 GB/s, grouped quant op at the headline shape | M |
| MMA shapes | n ≤ 16 per call; k ∈ {32, 128} correct, k = 64 wrong; **init/align flags ignored** | M |
| dtypes | i8×i8→i32 verified; f16×i8 nonexistent (errata 13); no i4→f16 path (errata 12); i4×i4→i32 in the calibration table, unverified | M / U |
| R_drain | L0C → US staged-read rate | U (demonstrated by the dense kernel's epilogue, rate unknown; E12) |
| σ_d | scalar cost per dispatch iteration | U (E14); budget 100 ns |
| F | fixed per-step cost 8 µs = 5 (pipeline fill) + 2 (exposed dispatch) + 1 (tail) | **A** (E14/E15) |
| ρ₁ | single-core DDR ceiling when fewer than 8 cores stream | U (≥ 22.5 measured share; E18) — the chosen design never depends on it |
| i32 Sub | vector i32 subtract (or Add of a negated i32) | U (E12); fallback stated in §3.2 |

---

## Summary and ranking

**Ranked #1 (build this): scheme S — every core owns column slice c of every active expert.** Core c streams
`W_e[:, c·N_c .. (c+1)·N_c)` for each active expert e in a flat 64 KiB chunk stream, through the measured
dense pipeline (DDR→S1 ring → S1→L0B in 16 KiB pieces → i8×i8 (16,16,128) MMA into an i32 region of L0C),
with one i8 A operand `[16, K]` holding **all t ≤ 16 tokens**, shared by every expert and resident in S1 for the
whole step. The token sum over experts is local to the core (an N-split needs no reduction), so there is no
cross-core traffic, no second launch and no host bounce. Per-core bytes are exactly 1/8 of the step's bytes
for every routing outcome (§7, theorem Z2): skew cannot unbalance it. Accumulator reset does not rely on the
ignored init flag: each expert's result is the i32 difference of its region before and after (§3.2), exact by
modular arithmetic under a proved overflow bound.

Predicted effective weight-byte rate, headline shape, W8, t = 1 (`[M1]`, derivations in §5, §8):

| Regime | Per-core time | Step | GB/s | Status |
|---|---|---|---|---|
| **Serial loader (the measured dense regime, anchored to T_dense)** | loader 652.9 + MMA 122.9 + residual 208.1 = 983.8 µs, DDR 776.1 µs hidden underneath | 991.8 µs | **135.3** | D from M (c_res by subtraction) — **the number to be judged** |
| Ping-pong (loader overlapped with MMA; the "known follow-up") | max(DDR 776.1, loader 652.9, MMA 122.9) | 784.1 µs | 171.2 | U — E13 decides; errata 14 is the risk |
| Wall clock with an unpipelined 91 µs launch | +91 µs | 1082.8 / 875.1 | 123.9 / 153.4 | floor M; pipelining E17 |

Target 120 is met at 113 % in the anchored regime; the vendor floor 24.6 is beaten 5.5×. Honest ceiling of
the design in the DDR-bound regime: 173.8 × 128 MiB / (128 MiB + 0.64 MiB of A, scales, descriptors, y) =
172.9 minus the fixed 8 µs → 171.2.

| # | Design | t=1, k=8 (serial / ping-pong) | k=4 | D=9 (t=4) | Needs | Risk |
|---|---|---|---|---|---|---|
| 1 | **S (this design, G=1)** | **135.3** / 171.2 | 134.2 | 135.4 | i32 difference epilogue (§3.2); A fragment probe (E11) | low: every path is one the dense kernel already exercised, plus one vector op |
| 1b | S with expert pairs per A lift (G=2, §5.6) | 136.7 / 171.2 | — | — | + interleaved 2-region DDR pattern (A-reg2, E15) | low-medium |
| 2 | W-dyn: whole experts per core, round-robin per step | 137.7 / 171.2 only when 8 \| D | 68.9 | 77.8 | 256 KiB C slab = L0C full (errata 14) → 2 slabs → 137.4 | high: rate is a function of D mod 8 |
| 3 | K-split hybrid: each core K/8 rows of every expert, i32 partials reduced in a second launch | 125.3 / — | 114.7 | 124.7 | +T_launch, +8·k·t·N_e·4 B of partials read back (their write hides under the DDR slack, Z8) | below S on every §8 cell except (t=16, D=128), where S-G2 still wins (Z8) |
| 4 | Vector-only (DESIGN.md route 4) | 70–78 (M), ∝ 1/t | | | | floor |
| 5 | Vendor grouped op | 24.6 (M) | | | | floor |

**The single measurement that changes the ranking: E11's accumulator-reset result.** If neither the init
flag, nor an i32 subtract, nor the f32 difference under the magnitude assumption gives an exact per-expert
result, scheme S must split a step into ⌈D/6⌉ launches (six fresh 32 KiB regions per launch) and W-dyn,
which needs one region per core at D ≤ 8, becomes #1 for t = 1 (137.7 vs 124). Every other unknown moves the
number, not the order: the loader/MMA overlap (E13) moves S from 135.3 to 171.2 and moves W-dyn identically.

---

## 1. Work decomposition and the three-axis design

### 1.1 Work units and what is inherited
A step is the set of active experts A = ∪_τ topk(τ), |A| = D, k ≤ D ≤ min(k·t, E). The work unit is
(expert e, core c) → the slice `W_e[:, c·N_c .. (c+1)·N_c)`, K·N_c bytes (2 MiB at the headline), streamed as
K/128 k-chunks of 128·N_c bytes (64 KiB — exactly one errata-2-maximal COPY at N_c = 512). Inside a unit the
pipeline is the realized dense kernel's: copy-in DDR→S1 (64 KiB ring), loader S1→L0B (16 KiB pieces = 8
call operands), MMA (16,16,128) i8×i8→i32 accumulating across k-chunks (k-inner, DESIGN.md §1.4 reason 1 still
holds: no US→L0C path), vector epilogue, copy-out. The MMA consumes 2 KiB of B per 15 ns call = 136.5 GB/s/core
if fed; the loader feeds 26.5 serial; DDR gives each core 21.7–22.5 — so per core the measured regime is
loader-serial-bound and the ping-pong regime is DDR-bound (§5.3).

### 1.2 Axis 1 — activation set → core mapping: scheme S (column slice per core)
Core c processes **every** active expert, column slice c. Consequences, each a theorem in §7:
- per-core bytes = D·K·N_c + A + scales/8 + desc + y/8 — a function of (D, K, N_e, t) only, identical on all
  8 cores for every routing outcome (Z2). The measured 173.8/180 aggregate was itself measured as 8 equal
  per-core streams, so no unmeasured single-core ceiling ρ₁ enters the prediction;
- the per-token sum Σ_e score_{τ,e}·y_e[τ, n] runs over experts, and every expert's columns n ∈ slice c are on
  core c: the scatter-add is local, there is no cross-core reduction. (PROBLEM-2's framing that an N-split
  "adds cross-core reduction through host" conflates two things: only a **K**-split needs a reduction, and on
  one die that reduction would go through DDR with a launch boundary as the only synchronization — ISA.md:
  hand-rolled kernels have no cross-core sync; the 10.7 GB/s host bounce of errata 11 is cross-**die**. This
  design uses neither.)
- the cost is the A-lift fraction: the A block (2 KiB per 128-row k-chunk) is re-lifted through the loader
  once per expert per core because it is reused across only N_c/16 = 32 strips instead of 256. Loader bytes
  per expert = K·N_c + 16·K: 3.1 % over B at N_c = 512 (`[M6]`: 6.3 % at N_c = 256, 12.5 % at 128, 25 % at
  64). It costs nothing in the DDR-bound regime and 1.8 % in the serial regime versus a whole-expert scheme.

Alternatives, costed (`[M5]`, `[M18]`; serial regime; W8; headline unless stated):
- **W-dyn** (whole expert per core, round-robin assignment computed per step): per-core work = ⌈D/8⌉ experts.
  D = 8: 137.7 (its A fraction is 0.4 %); D = 4 (k = 4): 68.9; D = 10 (k = 10): 86.4; D = 9: 77.8. Its C slab
  for one expert is 16 × 4096 × 4 B = 256 KiB = L0C exactly, the errata-14 hang; two slabs of 2048 columns
  double its A lifts → 137.4. It beats S only when ⌈D/8⌉·T_W < D·T_S (Z7), i.e. by ≤ 1.8 % on the set
  {8, 16, …, 128} ∪ {63, 71, …, 127} ∪ {118, 126}, and loses everywhere else — by 95 % at D = 4, 74 % at D = 9,
  57 % at D = 10, down to 0.03 % at D = 55 (the D just below the r = 7 crossover; T_Z7_losses).
- **W-static** (expert e lives on core e mod 8, no per-step assignment): adversarial single-hot routing puts all
  D active experts on one core → 17.3 GB/s (Z9). Under the generator (§7.1) the hottest core carries 2.6×
  the mean at t = 1 and 1.3–1.6× at t = 16 (`[Z]`). Dead.
- **K-split** (core = K/8 rows of every expert, all N_e columns): every core emits i32 partials [t, N_e] per
  expert: 8·D·t·N_e·4 B written and read back (1 MiB at the headline), reduced in a second launch (+91 µs,
  M) — 125.3 at D = 8, 114.7 at k = 4; below S on every §8 cell except (t=16, D=128), where its 8× smaller A block outweighs the launch floor by 0.6 % — a margin the G = 2 knob returns to S (Z8).

### 1.3 Axis 2 — per-expert tiny-M batching: one shared A fragment, rows selected in the epilogue
For t ≤ 16 every token row fits the single 16-row A fragment, so **one** i8 operand `x_q [16, K]` (rows ≥ t
zero, per-token scale sx[τ] in f32) serves every expert: the MMA computes all t rows for every expert at the
cost of one (mFrag = 1: DESIGN.md's m-flatness, measured m=1 = m=16 at 137.8), and the epilogue uses only the
routed rows via the CSR from dispatch. No gather, no per-expert A, no on-device fractal repack (which would be
the 7 GB/s COPY_FRAC path). Rule and proof in §5.4 (Z5, Z6): separate passes would stream Σ_e m_e = k·t
slabs instead of D; batching is never worse and the "free lunch" is exactly k·t/D ≥ 1.

### 1.4 Axis 3 — dispatch: in-kernel, redundant per core, on the scalar path, overlapped
Each core reads the router descriptor (≤ 960 B) and builds the active-expert list and per-expert token/score
lists itself (t·k ≤ 160 scalar iterations, §4). Cores are independent (no cross-core sync exists), the work
is ≤ 16 µs even at σ_d = 100 ns, t = 16, k = 10 (12.8 µs at k = 8), and it overlaps the 64 KiB A copy and the first expert's
stream; only the first iteration is exposed. A host pre-pass costs ≥ T_launch = 91 µs = 9.2 % of the
headline step and 211 % of a (K, N_e, k) = (2048, 512, 4) step (`[M16]`, `[M17]`): dead.

### 1.5 The five MoE deltas on the dense pipeline
(1) A resident in S1 for the step, lifted per k-chunk per expert; (2) expert loop outside the k-chunk loop,
flat chunk stream, ring never drains; (3) C accumulates into one of six 32 KiB L0C regions per expert, result
= region difference (init flags ignored, §3.2); (4) per-expert epilogue: s_e slice, score·sx scalar, f32
accumulation into y_acc, one f16 cast at the end; (5) per-core dispatch prologue.

---

## 2. Weight slab packing spec (host side, byte level)

### 2.1 Address of W_e[k, n] (W8)
Expert arena: slab e at `base_e = base + e·K·N_e` (expert ids are static; the active set selects slabs).
With c = n div N_c, n' = n mod N_c, g = n' div 16, n_l = n' mod 16, j = k div 128, f = (k mod 128) div 32,
k_l = k mod 32:

```
addr(e, k, n) = base + e·K·N_e            # expert slab, K·N_e bytes (16 MiB at the headline)
             + c·K·N_c                    # per-core slice, contiguous K·N_c bytes (2 MiB)
             + j·(128·N_c)                # k-chunk j: 128 rows × N_c columns (64 KiB at N_c = 512)
             + g·2048                     # strip g: the (16 n × 128 k) operand of one MMA call, 2 KiB
             + f·512                      # k-fragment f = (k mod 128) div 32 — hypothesis H-op, §2.2
             + n_l·32 + k_l               # HW-MAP settled fragment: [16 N × 32 K] column-major, byte n·32 + k
```
Claim P1 (Lean target, like DESIGN.md's T7): for fixed (e, c) the map (k, n') ↦ offset is a bijection of
[0, K) × [0, N_c) onto [0, K·N_c); inverse: k = 128·(o div (128·N_c)) + 32·((o mod 2048) div 512) + o mod 32,
n' = 16·((o mod (128·N_c)) div 2048) + (o mod 512) div 32. Every tile boundary the loop uses (64 KiB chunk,
16 KiB piece, 2 KiB operand) is a multiple of the next smaller one.

Generic N_c: a k-chunk is 128·N_c bytes = 64 KiB (N_c = 512), 32 KiB (256), 16 KiB (128), 8 KiB (64); a 64 KiB
COPY covers 1 / 2 / 4 / 8 k-chunks; a 16 KiB loader piece covers 8 operands = 8 strips of one chunk (N_c ≥
128) or 2 chunks × 4 strips (N_c = 64). N_e must be a multiple of 128 (pad otherwise); all PROBLEM-2 values are.

### 2.2 The two open geometry items (each one host-packer change, settled by E11)
- **H-op**: the four 512 B k-fragments of a (16,16,128) operand are consecutive in k order (HW-MAP: "fragments
  are laid out n-c-major across the tile" — for a single-n-group operand that is k order). Alternative: the
  MMA reads its 4 fragments at some other stride; E11(vi) uses a B pattern with distinct per-fragment column
  sums and reads the permutation off the oracle.
- **H-A**: the i8 A operand per (k-chunk, call) is the mirror of the settled B fragment: `[16 m × 32 k]`
  column-major per 32-k fragment, byte (k div 32)·512 + m·32 + k mod 32, four fragments per 128-k block;
  DESIGN.md §3.2's F_A = [K/16][16 m][16 k] is the f16 alternative. E11(v)'s one-hot rows decide; only the host
  packer (benchmark) / producer epilogue (integration) changes.

### 2.3 The other operands
| Operand | Layout | Bytes (headline) | Who writes |
|---|---|---|---|
| x_q, A | i8 [16, K] per H-A, rows ≥ t zero; `sx` f32 [16] | 64 KiB (K=4096), 112 KiB (K=7168) + 64 B | producer epilogue / host (benchmark, as the measured dense kernel) |
| s_e | f32 [N_e] at `sbase + e·4·N_e`; core c reads 4·N_c = 2 KiB | 16 KiB per expert per die | static |
| descriptor | `idx` i32 [16][k], `score` f16 [16][k] (rows ≥ t unused) | ≤ 960 B | router |
| y | f16 [t, N_e] row-major; core c writes columns [c·N_c, (c+1)·N_c) of each row (1 KiB runs) | t × 8 KiB | this kernel |

### 2.4 Visit order
Pack order = visit order: core c reads one contiguous 2 MiB region per expert in 32 sequential 64 KiB COPYs,
then jumps to the next expert's region. This is the measured "per-core slabs" pattern of the 180 GB/s figure
with a region switch every 2 MiB instead of every 8 MiB (A-reg, M-class; E15 records the rate).

---

## 3. Token gather / result scatter-add paths with costs

### 3.1 Gather(x): nothing to gather
| Item | Path | Cost (headline, per core) | Status |
|---|---|---|---|
| x_q + sx | one DDR→S1 COPY of 64 KiB (two of 56 KiB at K=7168) + 64 B to US, once per step | 2.9 µs at 22.5 GB/s/core, issued first, overlapped with dispatch; counted in the DDR byte total (0.4 %) | M path |
| per-token quantization f16→i8 | producer's epilogue (integration) or host (benchmark — exactly the measured dense kernel's setup) | if done in this kernel: 3 lane-ops/element × t·K = 4.6 µs at t=16, K=4096; needs a row-max reduce (U, not in ISA.md's op list) | U |
| per-expert token rows | none: all 16 rows are in the shared A; routed rows chosen by the CSR in the epilogue | 0 | — |

### 3.2 Scatter-add: the region-difference epilogue (init flags are ignored on this part)
HW-MAP: "the align/init flags in the MMA parameter struct are ignored" and MMA accumulates across k-chunks
(the dense kernel accumulated 64 chunks). A step has D = 8..128 experts per core, so accumulators must be
reused without a zero-init instruction. Design: six 32 KiB regions `C[r]`, r = d mod 6, each a running i32
sum over every expert that used it; expert d's result is the difference of its region after and before.

```
shadow[r] := drain(C[r])                       # once per region, lazily before first use (16 rows × 2 KiB)
per expert d (region r = d mod 6), after its last k-chunk:
    new  := drain(C[r])                        # 16 rows: 32 × 64 B runs at stride 1024 per row → 32 KiB in US
                                               # (C fragment [16 m][16 n] i32 row-major = DESIGN.md §3.3's P; E11(v)(vii))
    diff := new − shadow[r]  (i32, 16 × 512 lanes = 8 calls of 1024)   ;  shadow[r] := new   # shadows live in S1 (§6)
    for each routed (τ, e=act[d]) :  row := Cast_i32→f32(diff[τ]) ; Mul(row, s_e slice) ;
                                     Muls(row, score_{τ,e}·sx[τ]) ; Add(y_acc[τ], row)      # 4 × 512 lanes
step end: Cast_f32→f16(y_acc rows < t) ; COPY t × 1 KiB → y[τ, c·N_c ..]
```
Exactness (Lean targets): **P2** the difference is exact whatever the region held before, in modular i32
arithmetic, iff |S_e| < 2³¹ where S_e is the true per-expert sum; |S_e| ≤ 127²·K = 66 064 384 (K=4096).
**P3** overflow never occurs (so wrap-vs-saturate semantics are irrelevant) if each region is used at most
U_max = ⌊(2³¹−1)/(127²·K)⌋ times per launch (the operand bound |a|, |b| ≤ 127 is a requirement on the quantizers:
if −128 can occur, 128²·4096·32 = 2³¹ exactly and U_max drops to 31 at K = 4096 — 6 regions still cover
D ≤ 186 ≥ 128; K = 7168 is unchanged at 18 — T_overflow_m128): U_max = 32 at K = 4096 → 6 regions cover D ≤ 192; at K = 7168,
U_max = 18 → 7 regions (224 KiB) cover D ≤ 126 (`[M12]`). The regions total 192 KiB (224 at K = 7168), never
the full 256 KB (errata 14). Only routed rows are converted and accumulated: Σ_e m_e = k·t pairs per step. The six shadows (192 KiB) live in
S1 (US cannot hold them, §6): the region's shadow is copied S1→US before the Sub and the new drain copied back
(2 × 32 KiB per expert at the 250 GB/s/core US↔S1 class rate = 0.26 µs; the S1→US direction is listed in
ISA.md's "DDR ↔ S1 ↔ vector SRAM plain copies are real" and is content-checked in E12).

Costs per step (`[M8]`, `[M15]`, `[M19]`): drain D × 32 KiB per core (256 KiB at D = 8; 4 MiB at D = 128) on
the L0C→US path at R_drain (U): 3.3 µs per expert at 10 GB/s/core = 2.7 % of the 123 µs per-expert serial
time **if exposed**, 0 if overlapped with the next expert's MMA into another region (E16); vector: 8192
lane-ops Sub per expert (189 ns) + 2048 per routed pair (47 ns) → 30.3 µs per step at t = 16, D = 128 = 0.2 %;
copy-out t KiB.

Branches: (i) E11 shows the first call of an expert does zero-init after all → drop the shadow/Sub, keep
regions; (ii) no i32 Sub → f32 difference: exact iff |new|, |shadow| < 2²⁴ = 16 777 216, which the overflow
bound does **not** guarantee (22 × 66 M) — rely on ASSUMPTION A-mag (typical |S_e| ~ 10⁵–10⁶ for per-token-
quantized activations, running sums < 2²⁴) with E15's relerr check as the guard, or shrink U_max to keep the
running sum under 2²⁴ at the cost of more regions per launch; (iii) nothing exact → ⌈D/6⌉ launches per step
(+91 µs each) — the fallback that lets W-dyn overtake at D ≤ 8 (Summary).

### 3.3 Step budget, t = 1 headline (per core; the full budget demanded by PROBLEM-2)
| Component | Time | Hidden under | Status |
|---|---|---|---|
| dispatch | ≤ 0.8 µs scalar at σ_d = 100 ns; exposed ≤ 2 µs (descriptor latency + first iteration) | A copy (2.9 µs) | U/A (E14) |
| gather(x) | 2.9 µs copy | — (first bytes of the step) | M |
| grouped GEMM | 983.8 µs serial chain (DDR 776.1 µs underneath) | — | D |
| scatter-add + scores | 8 × (3.3 µs drain + 0.24 µs vector) = 28 µs | next expert's chain (regions double-buffered) | U/A (E16) |
| pipeline fill + tail | 5 + 1 µs | — | A |
| **step** | **991.8 µs → 135.3 GB/s**; + 91 µs launch floor → 123.9 wall | | |
Regression versus a dense kernel of the same bytes (two measured 8 MiB passes = 974 µs): +17.8 µs = 9.9 µs
of extra A lifts (256 KiB more through the loader: 8 × 64 KiB instead of 2 × 128 KiB, an A fraction of 3.1 % vs
1.6 %) + 8 µs of F (5 fill + 2 dispatch + 1 tail) − 0.05 µs of anchor rounding (`[M11]`): 1.8 %, of which the
dispatch share is 0.2 %.

---

## 4. Dispatch design and latency budget

### 4.1 Options, costed in measured units
| Option | Cost per step | Verdict |
|---|---|---|
| Host pre-pass (read router output, build descriptors, write back, launch) | ≥ T_launch = 91 µs (M) + D2H/H2D latency (U, only bandwidths are measured) + one sync point; 9.2 % of the headline step, 211 % of a (2048, 512, 4) step (`[M17]`) | dead |
| Dedicated tiny kernel ahead of the main kernel | + one launch: 91 µs if launches serialize (E17 decides), plus the queue hop even if they pipeline | dead unless E17 shows full overlap; even then it adds nothing over the in-kernel scan |
| Vector unit on one core, broadcast to the others | no cross-core sync or mailbox exists for hand-rolled kernels (ISA.md) | impossible in-kernel |
| **In-kernel, every core redundantly, scalar path** (chosen) | t·k iterations × σ_d (U): at σ_d = 100 ns, 0.8 µs (t = 1) … 12.8 µs (t = 16) (`[M16]`); the descriptor copy ≤ 960 B; overlapped with the A copy and expert 0's chain, exposed ≈ descriptor latency + 1 iteration (budget 2 µs, A) | chosen |
| Router emits CSR directly (integration option) | the scan collapses to one ≤ 6 KiB copy | best; needs the router kernel's cooperation |

### 4.2 The chosen algorithm (per core, scalar, US-resident, ≤ 128 iterations)
```
COPY desc → US (idx i32 [t][k], score f16 [t][k]); COPY sx → US (64 B)
Duplicate(slot[0..E), 0)                      # E bytes, ≤ 512: one vector call
D := 0
for τ in 0..t−1: for j in 0..k−1:             # t·k ≤ 160 iterations
    e := idx[τ][j]
    if slot[e] == 0: slot[e] := D+1; act[D] := e; cnt[D] := 0; D := D+1
    d := slot[e]−1; tok[d][cnt[d]] := τ; sc[d][cnt[d]] := f32(score[τ][j]) · sx[τ]; cnt[d] += 1
    if τ == 0 and j == 0: issue the first B COPYs of expert e   # the chain starts after one iteration
```
Output: `act[D]` (expert ids in first-seen order), per expert `tok[d][0..cnt[d])`, `sc[d][..]` (score × sx
folded once). Memory ≤ 512 B (slot) + 512 B (act) + 128 × 16 × 5 B (tok, sc) = 11 KiB. Every core computes
the same list; cores never communicate. The slab address of (e, c) is `base + e·K·N_e + c·K·N_c` — a pure
function, no per-step address table. Order of experts is irrelevant to correctness (each expert's result is a
region difference) and to balance (every core does every expert).

### 4.3 Latency budget
| Item | Bound | Status |
|---|---|---|
| descriptor and sx copies | ≤ 1 KiB; issue + DDR latency, U; must land before iteration 1 | U — E14 measures (content-checked) |
| scan | t·k·σ_d: 8·σ_d at t = 1, 128·σ_d at t = 16; σ_d = 10 / 100 / 250 ns → 0.08 / 0.8 / 2 µs (t=1), 1.3 / 12.8 / 32 µs (t=16) | U — E14 |
| overlap | the A copy (2.9 µs at K=4096) is issued before the scan; expert 0's 32 COPYs of 64 KiB start after iteration 1 and its chain takes 123 µs: the remaining ≤ 127 iterations hide under it | design |
| **exposed** | descriptor latency + σ_d ≤ **2 µs** (A, inside F) | A — E14 |
At t = 1 the whole dispatch is smaller than one 64 KiB chunk time (3.0 µs); the budget is dominated by the
descriptor's DDR latency, which is why the descriptor copy is the first instruction of the kernel.

---

## 5. Loop nest and tiling per expert pass; the m_e-batching rule

### 5.1 Shapes (all M-legal per HW-MAP)
- MMA call **(m, n, k) = (16, 16, 128)**, i8×i8→i32: B operand 2 KiB (one strip × one k-chunk), A block 2 KiB
  (16 × 128 i8), C fragment 16 × 16 i32 = 1 KiB. K ∈ {2048..7168} is a multiple of 128; N_c = N_e/8 ∈ {64..512}
  is a multiple of 16. (k = 64 is the HW-MAP anomaly and is never used; n > 16 silently truncates.)
- Calls per expert per core = (K/128)·(N_c/16) = 32 × 32 = **1024** at the headline; per step 8 × 1024 = 8192
  → MMA busy 8192 × 15 ns = 122.9 µs = 15.8 % of the 776.1 µs DDR time (`[M1]`).
- Loader piece 16 KiB = 8 operands (8 calls); L0B holds 3 pieces (48 KiB of 64 — never all 64, errata 14
  analogue); L0A holds 2 A blocks (4 KiB) — or the whole A when 16·K ≤ 48 KiB (K ≤ 3072: A lifted once per
  step, the 3.1 % A-lift cost vanishes).
- C region 16 × N_c × 4 B = 32 KiB (N_c = 512); six regions, r = d mod 6.

### 5.2 Loop nest (per core)
```
prologue : COPY desc, sx → US ; COPY x_q → S1 (64 KiB) ; dispatch (§4.2) ; Duplicate(y_acc[16][N_c] f32, 0)
for d in 0 .. D−1:                                        # expert loop; flat chunk stream, ring never drains
    e := act[d] ; r := d mod 6 ; COPY s_e[c·N_c .. +N_c) → US (2 KiB, double-buffered)
    if first use of r: drain C[r] → shadow[r]             # lazily, under the previous expert's chain
    for j in 0 .. K/128−1:                                # k-chunk = 128 rows × N_c = 64 KiB = one COPY
        copy-in : COPY(ring[q mod 4], base + e·K·N_e + c·K·N_c + j·64 KiB, 64 KiB) ; q += 1
        loader  : L0A[j mod 2] ← x_q block j (2 KiB)      # skipped when A is L0A-resident (K ≤ 3072)
                  for p in 0..3: L0B[(4j+p) mod 3] ← ring slot + p·16 KiB   # 8 operands per piece
        MMA     : for g in 0 .. N_c/16−1:
                      MMA(C[r] + g·1 KiB, L0A[j mod 2], L0B piece(g div 8) + (g mod 8)·2 KiB, 16,16,128)
                  # accumulates (flags ignored); chunk 0 of expert d adds onto the region's running sum
    epilogue (vector, overlapped with expert d+1's chain): §3.2 on C[r]
tail      : Cast y_acc rows < t → f16 ; COPY t × 1 KiB → y
```

### 5.3 Per-piece timing and the two regimes (`[M4]`)
| Per 16 KiB loader piece (8 calls) | ns | Status |
|---|---|---|
| copy-in share: 16 KiB at 21.725 GB/s/core | 754 | M |
| loader: 16 KiB at 26.5 | 618 | M (serial) |
| MMA: 8 × 15 | 120 | M |
| residual c_res × 8 | 203 | D |
| **serial chain** loader + MMA + residual | **941** | → 16 KiB / 941 ns = 17.4 GB/s/core of B, before A lifts and F |
| ping-pong: max(754, 618 + barriers, 120) | 754 if barriers ≤ 136 ns per piece | U (E13) |
Per expert: serial chain (2 MiB + 64 KiB)/26.5 + 1024 × (15 + 25.4) = 81.6 + 41.4 = **123.0 µs** vs 96.5 µs
of DDR share (`[M15]`). Per step: ×8 + F = 991.8 µs. In the ping-pong regime the loader needs L ≥ 17 MiB /
776.1 µs = 22.3 GB/s/core to stay off the critical path (`[M3]`), 16 % under the measured 26.5: the design
is DDR-bound there with margin, and the MMA (122.9 µs) is off the path in both regimes. Scheme S's loader
threshold is 22.3 versus 21.8 for the dense kernel (DESIGN.md §7.3) because of the A re-lifts.

### 5.4 The m_e-batching rule
- **t ≤ 16 (the whole PROBLEM-2 range): always batch — one shared A fragment, every expert computes all t
  rows, routed rows selected in the epilogue.** Z5: m_e ≤ t ≤ 16 ⇒ mFrag(m_e) = 1 for every expert under
  every routing, so MMA calls per expert are independent of the routing. Z6: separate (token, expert) passes
  would stream Σ_e m_e = k·t slabs; batching streams D; the ratio k·t/D ≥ 1 with equality iff all pairs are
  distinct (uniform, k·t ≤ E); under single-hot routing it is t. Nothing is paid for the batching except
  2048 lane-ops per routed pair (47 ns).
- The t-curve analogue of DESIGN.md's m-curve: the per-expert cost is flat in t; the step is D(t) × 123 µs +
  F, so **tokens/s scale with t/D(t)**: idealized uniform routing (D = 8t) gains nothing from a verify batch
  (1.01 tokens/ms at every t); Zipf(1.5) at t = 16 gives 2.89 tokens/ms (§8). Spec-decode gains on this
  kernel come only from routing overlap, never from the matrix unit.
- t > 16 (out of scope): gather the m_e routed rows of expert e into ⌈m_e/16⌉ fragments (A no longer shared:
  +16·K·⌈m_e/16⌉ B of A per expert per core, and an on-device H-A repack — a 2D copy if E5-style tests prove
  one, else the 7 GB/s path on ≤ 64 KiB per expert).

### 5.5 Barrier plan (errata 8, 14)
DESIGN.md §4.2's B1–B9 edges carry over per k-chunk and per piece with these MoE additions, all explicit
pipe barriers, each a strict flag → wait pair (errata 14: never two producer flags without a wait):
B10 copy-in(desc, sx) → scalar scan; B11 scalar scan → copy-in (first B COPY address); B12 copy-in(s_e) →
vector Mul; B5' last MMA of expert d → drain of C[r]; B6' drain of C[r] retired → first MMA of expert d+6
into C[r] (six regions make this edge six experts apart, so it never stalls); B13 Sub/Cast/… of expert d →
y_acc reuse by expert d+1 (same engine, program order); B8/B9 as in DESIGN.md for the tail copy-out. Queue
depths = declared counts (errata 9): ring 4/4, L0A 2/2, L0B 3/3, s_e 2/2, shadow 6/6. No queue-based staging
into L1 (errata 14): raw buffer staging only. Determinism check: fixed accumulation order ⇒ 20 reps on the
same inputs must be bit-identical (E15), positive control with B5' removed (E16).

### 5.6 Deltas versus DESIGN.md §1 and the expert-group knob
| DESIGN.md | Here | Why |
|---|---|---|
| (16,256,64) tile, 64 calls per 16 KiB | (16,16,128), 8 calls per 16 KiB piece | HW-MAP: n ≤ 16, k = 64 wrong |
| f16 A, 2 KiB per chunk, f16×i8 | i8 A, 2 KiB per 128-k chunk, i8×i8→i32, sx in the epilogue | errata 13 |
| initVal = ZERO at chunk 0 | region difference (§3.2) | flags ignored |
| one slab per launch | six 32 KiB regions, rotation d mod 6 | D experts per launch |
| A streamed per slab | A resident in S1 (64–112 KiB) for the step, lifted per chunk per expert | shared across experts |
**Expert-group knob G** (`[M14]`): lifting one A block for G experts' chunk j (G C regions live at once, ring
2·G × 64 KiB, DDR alternating G regions per 64 KiB) cuts the A-lift fraction to 3.1 %/G: serial-regime rate
136.7 (G = 2), 137.4 (G = 4), 137.7 (G = 8). Not the baseline: G = 8 needs 256 KiB of live regions (errata 14),
G = 4 forces single-buffered regions (exposed drains ≈ the gain), G = 2 is the only clean upgrade (+1.0 %)
and changes the DDR pattern class (A-reg2, E15 timing).

---

## 6. Buffer budget versus the hierarchy — worst activated set (D = 128, t = 16, E = 512, K = 7168, N_e = 4096)

| Buffer | Memory | Size | Depth / queue | Why |
|---|---|---|---|---|
| B ring | S1 | 4 × 64 KiB = 256 KiB | 4 / 4 | 64 KiB = errata-2 maximum and the measured 180 GB/s granule; 2 chunks (5.8–6.0 µs) of lookahead over the loader |
| x_q (A) resident | S1 | 16·K = 64 KiB (K=4096) … 112 KiB (K=7168) | 1 | one copy per step; re-lifted per expert |
| **S1 total** | | **512–592 KiB** incl. shadows | | ≤ 976 KiB P; the G = 2 knob adds 256 KiB (768–848) |
| L0A | L0A | 2 × 2 KiB (or 32 KiB resident at K = 2048) | 2 / 2 | 64 KB measured; never filled |
| L0B | L0B | 3 × 16 KiB = 48 KiB | 3 / 3 | 64 KB measured; one piece ahead of the MMA, one in flight, never all 64 (errata 14 analogue) |
| C regions | L0C | 6 × 32 KiB = 192 KiB (7 × 32 at K = 7168) | 6 / 6 | 256 KB measured; the overflow bound (P3) needs 6–7; never 256 |
| descriptor, sx | US | ≤ 960 B + 64 B | 1 | |
| slot[E], act, cnt | US | 512 B + 512 B + 512 B | 1 | E ≤ 512 |
| tok, sc | US | 128 × 16 × (1 + 4) B = 10 KiB | 1 | ≤ 128 experts × ≤ 16 tokens |
| y_acc | US | 16 × N_c × 4 B = 32 KiB | 1 | f32 accumulation across experts (no f16 sums: errata 5) |
| shadow[6] | **S1** | 6 × 32 KiB = 192 KiB (7 × 32 = 224 at K = 7168) | 6 | the before-state of each region (§3.2); in S1 because US cannot hold them (below) |
| shadow staging | US | 32 KiB | 1 | the active region's shadow, copied S1→US per expert |
| new / diff | US | 2 × 32 KiB | 2 | drain target and difference |
| s_e slice | US | 2 × 2 KiB | 2 / 2 | |
| row buffer | US | 2 KiB f32 | 1 | per routed pair |
| y_out | US | 16 × 1 KiB f16 | 1 | tail |
| **US total** | | **≈ 162 KiB** | | ≤ 208 KiB evidenced |

Why the shadows are in S1: with six 32 KiB shadows resident in US (and no staging buffer) the US total would be ≈ 322 KiB, above the
208 KiB evidenced. Alternatives if S1 is short (E7-style aliasing test): (b) 4 regions (overflow bound D ≤ 128
at K ≤ 4096, D ≤ 72 at K = 7168 — beyond that A-mag); (c) shadow only the rows that will be routed to the
region's next occupant (known from dispatch), 2 KiB per row. For the W4 branch the dequant staging of
DESIGN.md §2 is gone (errata 12); the i4×i4 route adds one 32 KiB group-drain buffer.

---

## 7. Skew model: hypothesis families, per-core byte loads, rate theorems

### 7.1 Routing outcomes and the hypothesis families
A routing outcome is ω = (A, {m_e}_{e∈A}) with D = |A| active experts, 1 ≤ m_e ≤ t, Σ_e m_e = k·t. The
families are defined on ω, and the Zipf parameter s enters **only through the distribution of D** (and of
m_e, which the design makes irrelevant below t = 17):

| Family | Definition | D | max m_e |
|---|---|---|---|
| **U** idealized uniform (PROBLEM-2's "min(top-k·t, E)") | token τ picks experts (k·τ + j) mod E | min(k·t, E) exactly: 8 / 32 / 128 | ⌈k·t/D⌉ = 1 |
| **U_s** sampled uniform | generator Z (§9.3) with s = 0 | 8 / 30.5 [25, 32] / 102.0 [89, 115] | 1 / 1.8 / 3.3 |
| **Z(1.0)** | Z with s = 1.0 | 8 / 25.0 [18, 31] / 68.3 [54, 84] | 1 / 3.4 / 12.7 |
| **Z(1.5)** | Z with s = 1.5 | 8 / 19.6 [13, 26] / 45.4 [34, 58] | 1 / 4.0 / 15.9 |
| **H** adversarial single-hot | every token picks the same k experts | k = 8 at every t | t |
| **H_c** static-map collision (W-static only) | the k hot experts are ≡ c (mod 8) | k | t |
Columns are t = 1 / 4 / 16 at E = 256, k = 8; generator means over 2000 seeds with [min, max] (`[Z]`). At
t = 1 every family has D = k: **skew is invisible at t = 1 for any per-step (dynamic) scheme**; it exists
only for a static expert→core map (H_c).

### 7.2 Per-core byte loads (Lean targets; Nat arithmetic over D, t, K, N_e)
- **Z1** (bounds): k ≤ D ≤ min(k·t, E); 1 ≤ m_e ≤ t; Σ m_e = k·t.
- **Z2** (scheme S balance): for every core c and every ω, `coreBytes_S = D·K·N_c + 16·K + D·4·N_c + 1024 +
  t·2·N_c` — the expression has no c and no m_e in it. Hence max_c / mean_c = 1 for all ω, and the
  per-die DDR time is `ddrBytes·10/1738` with the measured 8-stream aggregate, no ρ₁ assumption.
- **Z4** (W-dyn imbalance): max_c units = ⌈D/8⌉, min_c = ⌊D/8⌋; max per-core bytes = ⌈D/8⌉·K·N_e + 16·K;
  max/mean = 8⌈D/8⌉/D: = 1 iff 8 | D, = 8(q+1)/(8q+r) > 1 for D = 8q + r, 1 ≤ r ≤ 7 (16/9 at D = 9, 64/63 at D = 63), and 8/D at D < 8.
- **Z9** (W-static, family H_c): max per-core bytes = D·K·N_e + 16·K (all active experts on one core): max/mean
  = 8.
- **Z5** (one fragment): t ≤ 16 ⇒ m_e ≤ 16 ⇒ mFrag(m_e) = ⌈m_e/16⌉ = 1 for every e, every ω ⇒ MMA calls per
  expert = (K/128)(N_c/16) independent of ω.
- **Z6** (batching): separate passes stream Σ_e m_e·K·N_e = k·t·K·N_e; batched streams D·K·N_e; the ratio
  k·t/D ≥ 1, = 1 iff all (τ, e) pairs are distinct, = t under H.

### 7.3 Rate theorems (serial regime; T_S = 122 979 ns per expert per core, T_W = 966 531 ns per whole expert,
F = 8 000 ns, B_x = 16 MiB; `[M15]`, `[M20]`)
- **Z3** (scheme S is affine in D): `stepS(D) = F + D·T_S` because D·T_S ≥ tDdr(D, t) for every D ≥ 1,
  t ≤ 16 (minimum slack 22 536 ns at D = 1). Therefore `rateS(D) = rateT(D·B_x, F + D·T_S)` is strictly
  increasing in D with limit B_x/T_S = 136.4 GB/s, and rateS(4) = 134.2, rateS(8) = 135.3, rateS(128) = 136.4.
- **Z10** (skew bracket): for every family, every s, every seed: D ∈ [k, min(k·t, E)] ⇒ rateS ∈ [rateS(k),
  rateS(min(k·t, E))] = **[135.3, 136.4]** at the headline constants — skew moves the effective rate of
  scheme S by at most 1.1 GB/s (0.8 %), while the step time scales with D(s): 15.7 ms (U, t = 16) versus 5.5 ms
  (Z(1.5), t = 16), 2.8× fewer bytes streamed.
- **Z7** (whole-expert versus slice; the "imbalance threshold"): `stepW(D) = F + ⌈D/8⌉·T_W`; W-dyn beats S iff
  `⌈D/8⌉·T_W < D·T_S`. With T_W/(8·T_S) = 0.9824 the winning set within 1..128 is {8, 16, …, 128} ∪
  {63, 71, 79, 87, 95, 103, 111, 119, 127} ∪ {118, 126}, by at most 1.8 % (the A-lift fraction); on every
  other D scheme S wins, by 74 % at D = 9 (1.115 ms vs 1.941 ms), 95 % at D = 4, and by as little as 0.03 % at
  D = 55. Under the generator the
  winning set is hit by 20 / 19 / 4 % of outcomes at t = 4 and 25 / 26 / 12 % at t = 16 (s = 0 / 1.0 / 1.5),
  and the generator-mean W-dyn rate is 132 / 121 / 115 (t = 4) and 134 / 132 / 129 (t = 16) against 136 for
  S. With the G = 2 knob
  (T_S' = 121 743 ns) the set shrinks to 8 | D and the margin to 0.8 %. There is no threshold in s at which
  a whole-expert scheme becomes preferable: the dependence is on D mod 8, not on s.
- **Z8** (K-split never pays): `stepK(D, t) = F + D·(T_S − ΔA) + T_launch + partialBytes·10/1738` with ΔA =
  2 164 ns (its A block is 8 KiB instead of 64) and partialBytes = 8·k·t·N_e·4 (the i32 rows read back by the
  reduce launch; their write — the same bytes — rides under the serial regime's DDR slack: 6 µs of 208 µs at
  the headline, 97 µs of 3.4 ms at D = 128, T_Z8_write_hidden). Margin stepK − stepS = T_launch + partials −
  D·ΔA (exact up to the chain's floor rounding, < 2D ns): +79.7 µs (t=1, D=8), +45.8 µs
  (t=4, D=32), +71.8 µs (t=4, D=20), +40.3 µs (t=16, D=68), +90.1 µs (t=16, D=45), and **−89.6 µs at (t=16,
  D=128)** — the one cell where K-split's A amortization beats a launch floor (137.1 vs 136.4), ignoring that its
  256 KiB C slab is the errata-14 size. S with G = 2 is 137.7 there without any reduction, so S ≥ K-split on
  every cell of §8 for the design as a whole (S-G2 ≥ K-split; S-G1 ≥ K-split except that cell).
- **Z9'** (static map floor): under H_c, stepW-static(D) = F + D·T_W → 17.3 GB/s at D = 8: 8× slower.

### 7.4 Rate floor per family (serial regime, headline K, N_e; t = 1 / 4 / 16; min over the family's D range)
| Family | S floor (ceiling) | W-dyn floor (at D) | W-static floor | K-split floor |
|---|---|---|---|---|
| U idealized | 135.3 / 136.1 / 136.4 | 137.7 / 138.6 / 138.8 (8 \| D always) | 17.3 | 125.3 / 134.6 / 137.1 |
| U_s sampled | 135.3 / 136.1 / 136.3 | 137.7 / **108.3** (25) / **128.7** (89) | 17.3 | 125.3 / 133.4 / 136.4 |
| Z(1.0) | 135.3 / 135.9 / 136.3 | 137.7 / **103.9** (18) / **123.5** (57) | 17.3 | 125.3 / 131.4 / 134.8 |
| Z(1.5) | 135.3 / 135.7 / 136.2 | 137.7 / **98.1** (17) / **117.8** (34) | 17.3 | 125.3 / 128.8 / 132.6 |
| H single-hot | 135.3 / 135.3 / 135.3 | 137.7 / 137.7 / 137.7 | 17.3 | 125.3 / 123.2 / 115.5 |
Scheme S's floor is ≥ 135.3 under every family; W-dyn's floor under any sampled family is 98–129; W-static's
is 17.3. (The 1.8 % W-dyn edge at 8 | D is the A-lift fraction and is recovered by the G knob, §5.6.)

---

## 8. Predicted step-time table

### 8.1 t ∈ {1, 4, 16} × routing ∈ {uniform, Zipf(1.0), Zipf(1.5)} × {W8, W4}; K = N_e = 4096, k = 8, E = 256 (`[T8]`)
D for "uniform" is the idealized min(k·t, E); Zipf D are the generator means rounded. W8 = scheme S, serial
regime (the number to be judged) with the ping-pong branch beside it; W4 = the conditional i4×i4 route of
§8.4 (serial regime). Step = per-core chain + F; tokens/ms = t / step.

| t | routing | D | W8 bytes | W8 step | **W8 GB/s** | tokens/ms | ping-pong step → GB/s | W4 bytes | W4 step | W4-GB/s |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | uniform | 8 | 128 MiB | 0.992 ms | **135.3** | 1.01 | 0.784 ms → 171.2 | 64 MiB | 1.026 ms | 65.4 |
| 1 | Zipf(1.0) | 8 | 128 MiB | 0.992 ms | **135.3** | 1.01 | 0.784 → 171.2 | 64 MiB | 1.026 ms | 65.4 |
| 1 | Zipf(1.5) | 8 | 128 MiB | 0.992 ms | **135.3** | 1.01 | 0.784 → 171.2 | 64 MiB | 1.026 ms | 65.4 |
| 4 | uniform | 32 | 512 MiB | 3.943 ms | 136.1 | 1.01 | 3.103 → 173.0 | 256 MiB | 4.080 ms | 65.8 |
| 4 | Zipf(1.0) | 25 | 400 MiB | 3.083 ms | 136.1 | 1.30 | 2.427 → 172.8 | 200 MiB | 3.189 ms | 65.8 |
| 4 | Zipf(1.5) | 20 | 320 MiB | 2.468 ms | 136.0 | 1.62 | 1.944 → 172.6 | 160 MiB | 2.553 ms | 65.7 |
| 16 | uniform | 128 | 2048 MiB | 15.749 ms | 136.4 | 1.02 | 12.380 → 173.5 | 1024 MiB | 16.297 ms | 65.9 |
| 16 | Zipf(1.0) | 68 | 1088 MiB | 8.371 ms | 136.3 | 1.91 | 6.582 → 173.3 | 544 MiB | 8.661 ms | 65.9 |
| 16 | Zipf(1.5) | 45 | 720 MiB | 5.542 ms | 136.2 | 2.89 | 4.360 → 173.2 | 360 MiB | 5.734 ms | 65.8 |
Single-hot (D = 8 at every t): 0.992 ms, 135.3 GB/s, 16.13 tokens/ms at t = 16. Derivation of every W8 cell:
step = 8 000 + D × 122 979 ns (Z3; exact up to the floor rounding of the summed loader and residual terms, < 2D ns:
991 842 vs 991 832 at D = 8, invisible at µs precision); GB/s = D·16 MiB / step; the per-expert 122 979 ns = (2 MiB + 64 KiB)·10/265
+ 1024 × 15 + 1024 × 25.4 (§5.3). Ping-pong cell: max(ddrBytes·10/1738, loaderBytes·10/265, calls × 15) + 8 000.

### 8.2 Sensitivity of the headline cell
| Quantity | Values → headline GB/s | Status |
|---|---|---|
| c_res (per-call residual) | 0 ns: 171.2 (= the DDR bound: a zero-overhead serial chain is exactly DDR-paced), 5 ns: 162.7, 10 ns: 155.0, 15 ns: 148.0, 20 ns: 141.6, **25.4 ns: 135.3**, 30 ns: 130.4, 40.9 ns: 120.0 (the gate's edge: target met iff c_res ≤ 40.9 ns, T_cres_target), 50 ns: 112.5 (`[M2]`, `[M24]`) | D; E13 splits it into loader-granule and barrier parts |
| loader L in the ping-pong regime | 15.0: 115.6, 20.0: 153.7, 22.0: 168.9, **≥ 22.3: 171.2** (`[M3]`) | threshold PROVED; regime U |
| A-lift group G | 1: 135.3, 2: 136.7, 4: 137.4, 8: 137.7 (`[M14]`) | D; G = 2 is the clean upgrade |
| wall clock (+91 µs unpipelined launch) | t=1: 123.9; t=4 (D=32): 133.1; t=4 (D=20): 131.1; t=16 (D=128): 135.6; t=16 (D=45): 134.0 | floor M; pipelining E17 |
| fixed cost F | 0 µs: 136.4; 8 µs: 135.3; 20 µs: 133.7 | A |

### 8.3 Other shapes at t = 1, D = k (`[M6]`): serial / ping-pong / wall, and the structural reason
| (K, N_e, k) | N_c | calls per expert per core | A-lift over B | S serial | S ping-pong | wall | W-dyn |
|---|---|---|---|---|---|---|---|
| (4096, 4096, 8) headline | 512 | 1024 | 3.1 % | **135.3** | 171.2 | 123.9 | 137.7 |
| (7168, 4096, 10) | 512 | 1792 | 3.1 % | 135.9 | 172.3 | 130.4 | 86.6 |
| (2048, 4096, 4) | 512 | 512 | 3.1 % | 132.1 | 165.3 | 97.3 | 68.3 |
| (7168, 2048, 8) | 256 | 896 | 6.3 % | 132.5 | 170.3 | 120.2 | 137.2 |
| (4096, 1024, 8) | 128 | 256 | 12.5 % → 3.1 % with G = 4 | 124.8 → 132.1 | 164.2 | 93.3 | 133.4 |
| (4096, 512, 8) | 64 | 128 | 25 % → 6.3 % with G = 4 | 113.1 → 125.7 | 155.8 | 70.1 | 128.1 |
| (2048, 512, 4) | 64 | 64 | 25 % → 0.8 % (A resident in L0A: one 32 KiB lift per step) | 97.4 → 106.6 | 124.3 | 31.3 | 60.4 |
Small N_e hurts scheme S through the A-lift fraction (16/N_c of B through the loader), not through the
MMA: at N_e ≤ 1024 use the G = 4 knob (A fraction /4: 124.8 → 132.1, 113.1 → 125.7) or, for K ≤ 3072, keep A
resident in L0A (the last row: 97.4 → 106.6 — the one remaining 32 KiB lift per step still costs 1.2 µs of a 43 µs
step; still launch-floor-bound on the wall clock). Small total bytes are launch-floor-bound on the wall clock regardless of the kernel
(31.3 GB/s at 4 MiB per step): such layers must be fused into the surrounding ops' launch (E17).

### 8.4 W4 on this part (errata 12: no i4→f16 path; the vector unpack ceiling is 42 GB/s aggregate — dead vs 120)
The only W4 route left is **i4×i4→i32 on the matrix unit** (dtype tuple in the calibration table, unverified).
Design: nibble-split the i8 activations, x = 16·x_hi + x_lo, two i4 planes → two MMA passes per operand,
C = 16·C_hi + C_lo exact in i32; per-group (G = 128 rows) f16 offset/scale per column — K·N_e/32 extra bytes —
forces a drain of the [16, N_c] i32 slab **per group** (the scale cannot fold into a per-n epilogue):
(K/128) × 32 KiB per expert per core on the L0C→US path (U). Cost at the headline (`[M7]`): DDR bytes 68.5 MiB
(i4 + scales + A), serial chain 1 018 µs (2× the calls: 16 384 × 40.4 ns = 662 µs, plus 9 MiB of i4, group scales
and A lifts through the loader at 26.5 = 356 µs) → **65.4 W4-GB/s =
130.8 W8-equivalent**, i.e. 96.7 % of W8's tokens/s (1 026 µs per step vs 992): in the serial regime the call
count, not bytes, is the wall, and W4 is 3.4 % *slower* than W8; tokens/s parity would need c_res ≤ 21.2 ns
(T_w4_parity, ∀ c_res). Ping-pong regime: DDR-bound at 159.3 W4-GB/s (1.86× W8's ping-pong tokens/s) only if the
i4 operand is 1 KiB per (16,16,128) call, the drain path sustains ≥ 8.2 GB/s/core, and the 2× calls (59.5 % of
the W4 DDR time) stay hidden. Decision
rule: W4 only if E19 passes all three; else W4 weights are requantized offline to per-channel i8 and streamed as
W8 (no memory saving, the measured route). The W4 column of §8.1 is the serial-regime conditional number.

---

## 9. Experiment ladder (continues DESIGN.md's E0–E10 numbering; every one has an observable failure)

Harness rules (DESIGN.md §8, unchanged): every destination pre-filled with a sentinel; every data path
exercised with two different sources through the same destination address (differencing); integer-valued
inputs so every expected value is exact (i8×i8 column sums over 2 × 128 k-rows with |a|, |b| ≤ 15 are
≤ 57 600 ≪ 2²⁴, exact in i32 and in f32); pass = ≥ 20 reps bit-identical **and** equal to the host reference;
timing is recorded, never a pass criterion. E1-class geometry probes and E2-class accumulating oracles are
reused as written there with the (16,16,128) shape.

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **E11** | accumulator semantics across experts, the region-difference epilogue, launch state, wrap-vs-saturate, H-op, H-A | A = all-ones i8 [16, 256] (2 k-chunks); two experts with b_e[k,n] = ((7k + 13n + 5e) mod 31) − 15 packed per §2.1 into one 64-column slice; (i) run expert 0 then expert 1 into the same region with no reset → drained row 0 must equal ΣW_0 + ΣW_1 (accumulate-across-experts confirmed; if it equals ΣW_1, the first call of a pass zero-inits and §3.2 simplifies); (ii) drain before/after expert 1, i32 difference must equal ΣW_1 exactly; repeat with a second B pattern at the same addresses; (iii) drain all six regions at kernel start and write them out, 20 launches; (iv) 1 100 calls of a 127-valued oracle into one region (2 064 512 per call) → the drained value is either the wrapped integer (known) or 2³¹−1; (v) A row r = one-hot e_j for every j → C[r, n] must equal b[j, n] (H-A); (vi) a B pattern whose four 32-k fragments have distinct column sums → the permutation of fragments in the result (H-op); (vii) rows 1..15 of C must be 0 for row-0-only A | all-zero → silent no-op (bisect with E5/E3); expert-1-only → zero-init exists (branch); difference ≠ ΣW_1 → Sub/drain path broken; non-identical launch state → regions must be drained lazily (the design does, so this only informs); wrong (j, n) in (v)/(vi) → packer change | the reset mechanism (**the ranking measurement**, Summary), the two geometry hypotheses, the overflow semantics |
| **E12** | the epilogue vector chain and the drain rate R_drain | i32 Sub (or Add of a negated operand), Cast i32→f32, Mul f32, Muls scalar, Add; 1024-lane calls with a sentinel beyond lane 1024 (errata 3); 1 000 drains of a 32 KiB region with known content; S1→US copy of a 32 KiB shadow | lanes beyond 1024 keep the sentinel; a missing i32 Sub shows as wrong bits at magnitudes ≥ 2²⁴ (test with 2²⁵ + 1); drain content mismatch or rep-to-rep islands; the measured R_drain classifies §3.2's overlap claim | i32 vs f32 difference branch; whether 3.3 µs per expert of drain is hidden (E16) |
| **E13** | **the loader regime: c_res split into granule overhead and barrier cost; ping-pong** | (a) E2-style accumulating oracle (10 000 loads alternating tiles X/Y into L0B, each followed by 8 MMA calls into one region; expected total n_X·ΣX + n_Y·ΣY ≤ 10 000 × 8 × 128 × 15 = 1.5·10⁸ < 2³¹, exact in i32 — above 2²⁴, so the region is read as i32, never through f32) at 2 KiB and 16 KiB load granules with strict-serial barriers; (b) the same with 2 and 3 L0B slots and flag→wait choreography; 20 reps each; (c) positive control: one wait removed — must hang (watchdog) or corrupt the total | a skipped or stale load changes the total; any rep-to-rep difference in (b) = choreography fault; a positive control that passes means the detector is blind and (b) is void | the headline number: serial 135.3 vs ping-pong 171.2 (§8.2); the per-piece barrier budget 136 ns |
| **E14** | dispatch correctness and σ_d | every core builds the CSR from a synthetic descriptor with duplicates (t = 16, k = 8, 37 distinct experts) and writes `act, tok, sc, cnt` to DDR; compared with the host; a second descriptor through the same address; 20 reps; descriptor-only kernel vs empty kernel for σ_d and the descriptor latency | wrong or stale lists; cores disagreeing with each other (impossible by construction — a disagreement is a copy fault) | the 2 µs exposed-dispatch assumption inside F |
| **E15** | end-to-end numerics and the balance premise under every family | random x (per-token-quantized on the host), random W_e, routing from the generator Z (§9.3) for (U, U_s, Z(1.0), Z(1.5), H) at t ∈ {1, 4, 16}, 20 reps per config; host f64 reference of Σ_e score·sx·s_e·(x_q·W_e); each core also writes (chunk count, expert list) to DDR | relerr > 10⁻³ (includes a violated A-mag in the f32 branch); any rep-to-rep bit difference = missing barrier; any core whose chunk count ≠ D × 32 = mapping bug (Z2's premise checked on silicon) | ship/no-ship; the region-switch timing A-reg (recorded) |
| **E16** | region double-buffering and drain overlap; six-region rotation | expert d accumulates into region (d mod 6) while the vector unit drains region ((d−1) mod 6); 20 reps bit-identical; positive control with B5' removed | islands or non-identical reps; the control must show islands | whether §3.2's drain is hidden (0 %) or exposed (2.7 %) |
| **E17** | launch-floor behaviour for small MoE layers (E0 analogue) | 100 queued launches of (K, N_e, k) = (2048, 512, 4), kernel i writes its index to slot i | missing/duplicate slots = dropped launches; T(100) ≈ 100 × 91 µs = serialized, ≈ 91 + 100 × small = pipelined | wall-clock rows of §8.2/§8.3; fusion requirements |
| **E18** | single-core DDR ceiling ρ₁ | 1 / 2 / 4 / 8 cores each stream 64 MiB and write a checksum | checksum mismatch; the rate per active core is the measurement | nothing for scheme S (Z2); informational for W-dyn |
| **E19** | W4: i4×i4→i32 existence, nibble-split exactness, per-group drain path | A = nibble planes of all-ones, B = known i4 pattern → exact column sums; C = 16·C_hi + C_lo checked; 32 group drains per expert content-checked and rate recorded | all-zero (no such tuple, errata 1); wrong sums; drain rate < 8.2 GB/s/core | the W4 decision rule (§8.4) |
| **E20** | the 40 % number | 100 queued launches at the headline shape, random x and random routing per launch (a stuck kernel is visible as a repeated output), every output checked vs host f64 (relerr ≤ 10⁻³), 20 reps bit-identical for fixed inputs | any failed check voids the timing | reported t = 1 GB/s, in-kernel-equivalent (floor from E17) and wall |
Order: E11, E12, E13(a), E14, E15, E16, E13(b)+(c), E17, E20, then E18, E19. E11 is first because it carries
the ranking; E13 is the one that moves the number.

### 9.3 Routing-skew synthetic generator Z(E, k, t, s, seed) — deterministic, host and device agree
```
w[r]   = (r + 1)^(−s)                 r = 0..E−1     (rank weights; s = 0 is uniform)
π      = Fisher–Yates permutation of 0..E−1 with PRNG(seed)       (rank → expert id, hides rank order)
for τ in 0..t−1:
    avail = all ranks
    for j in 0..k−1:                                                (sequential draws without replacement)
        u = PRNG(seed, τ, j) · Σ_{r ∈ avail} w[r] ; pick the first r ∈ avail with cumulative w ≥ u
        idx[τ][j] = π[r] ; remove r from avail
    score[τ][0..k) = f16( w[r_j] / Σ_j w[r_j] )                    (positive, sums to 1)
```
PRNG = any seeded 64-bit generator fixed in the harness (`random.Random(seed)` in `proof/moe.py --zipf`).
Families: U = idealized (idx[τ][j] = (k·τ + j) mod E, score 1/k); U_s = Z(s=0); Z(1.0), Z(1.5); H = idx[τ][j]
= π[j] for all τ; H_c = idx[τ][j] = 8·j + c. Output: `idx` i32 [t][k], `score` f16 [t][k] → DDR; the host
reference computes y from the same arrays. Reported per seed: D, max m_e, per-core chunk counts (E15).

---

## 10. Risk register, what each UNMEASURED quantity unlocks, the one measurement

### 10.1 Risks and fallbacks
| Risk | Trigger | Impact | Fallback |
|---|---|---|---|
| No exact accumulator reset: no init semantics, no i32 Sub, A-mag violated | E11, E12, E15 | regions cannot be reused in a launch | ⌈D/6⌉ launches per step (+91 µs each: 124 GB/s at D = 8); W-dyn becomes #1 at t = 1 (137.7) — **the ranking flip** |
| i32 saturates and the bound is exceeded (K = 7168, D > 126) | E11(iv) | wrong differences | cap D per launch at 7·U_max, second launch for the rest |
| Ping-pong choreography hangs (errata 14) | E13(b) | stays in the serial regime | ship serial: 135.3 (above target); the upside 171.2 is the follow-up, never the baseline |
| c_res is granule-bound rather than barrier-bound | E13(a) | 16 KiB pieces cut it: up to 162.7 at 50 ns | free gain; nothing in the design changes |
| Loader < 22.3 GB/s/core at 16 KiB granules (the measured 26.5 may be granule-specific) | E13(a) | ping-pong regime becomes loader-bound: 128 MiB / (16.5 MiB/L + 8 µs) → L = 20: 153.7 | still > 120 for L ≥ 15.6 (T_pp_target, ∀ L) |
| H-op / H-A geometry different | E11(v)(vi) | wrong results | host packer / producer epilogue updated from the probe; no rate change |
| Dispatch descriptor latency > 2 µs or σ_d > 250 ns | E14 | exposed prologue grows: +30 µs at t = 16 worst case = 0.2 % | router emits the CSR (one ≤ 6 KiB copy) |
| US cannot hold 162 KiB | E7-style aliasing | shadows and y_acc contend | shadows in S1 (already the design); shrink regions to 4 |
| S1 < 592 KiB (K = 7168 worst case) | E7-style | A + ring + shadows do not fit | shadows of routed rows only (2 KiB per row), ring 3 × 64 KiB |
| Region-switch DDR pattern slower than the per-core-slab figure (A-reg) | E15 timing | DDR time grows; invisible in the serial regime until it exceeds 983.8 µs (27 % slack) | the 2 MiB regions are 32 sequential 64 KiB copies; no change expected |
| Drain not overlapped with the next expert's MMA | E16 | +2.7 % serial (3.3 µs per expert at 10 GB/s/core) | drain only routed rows before/after (4 KiB per pair) |
| N_e ≤ 1024 | shape | A-lift fraction 12.5–25 % (§8.3) | G = 4 knob; A resident in L0A for K ≤ 3072 |
| Small total bytes per step (≤ 8 MiB) | E17 | launch-floor-bound on the wall clock (31 GB/s) | fuse MoE with attention-out/router in one launch; report in-kernel and wall separately |
| t > 16 | workload | shared A no longer covers all tokens | ⌈m_e/16⌉ fragments with a gathered A (§5.4); out of scope here |
| f16 score/sx scalar multiply precision | — | score·sx in f32 on the scalar path; one f16→f32 cast of ≤ 160 lanes | — |
| Missing barrier (errata 8) | E15/E16 | silent islands | positive control proves the detector; add barriers until 20/20 |
| i4×i4 tuple absent or group drains slow | E19 | W4 not viable | offline requantize to per-channel i8, stream as W8 |

### 10.2 What each UNMEASURED quantity unlocks (ranked)
1. **Accumulator reset mechanism (E11)** — decides whether scheme S runs a step in one launch; the only
   unknown that can reorder the ranking (S ↔ W-dyn at t = 1).
2. **Loader/MMA choreography cost at 16 KiB granules and ping-pong (E13)** — 135.3 → up to 171.2 (+26.5 %);
   moves every design equally.
3. **R_drain (E12/E16)** — 0 % vs 2.7 % per expert; also the W4 route's 8.2 GB/s/core requirement.
4. **i32 vector Sub (E12)** — exact difference without the magnitude assumption.
5. **Launch pipelining (E17)** — wall-clock rate of small MoE layers (31 → 97 GB/s at 4 MiB per step).
6. **σ_d and descriptor latency (E14)** — the 2 µs inside F; ≤ 0.3 % either way.
7. **i4×i4→i32 (E19)** — W4 at 1.86× tokens/s only in the ping-pong regime; 0.97× in the serial regime (parity iff c_res ≤ 21.2 ns).
8. **ρ₁ (E18)** — nothing for this design; it would only soften W-dyn's imbalance, never its loader imbalance.

**The one measurement that most changes the ranking: E11 — whether an exact per-expert accumulator reset
exists (init semantics, i32 difference, or the f32 difference under A-mag).** Everything else changes the
predicted number (E13 by up to 36 GB/s) but leaves scheme S ranked first.

---

## Appendix A — claim ledger (for the round-2 proof session)

Status: M = HW-MAP input; D = derived (theorem target, `decide`/`omega`); A = assumption measured by the
named experiment; U = empirical. Labels refer to `proof/moe.py` output. The theorem names in the last column
were round-1 proposals; the actual `proof/moe.lean` theorem for every row (and for every other number in this
document) is in `PROOF-COVERAGE-2.md`, which supersedes this table as the ledger.

| # | Claim | Value | Status | moe.py / proposed theorem |
|---|---|---|---|---|
| 1 | c_res = (487 000 − (8 MiB + 128 KiB)·10/265 − 4096·15)/4096 | 25.4 ns | D from M | [M0] P0_cres |
| 2 | the decomposition re-predicts the dense kernel | 137.8 GB/s | D | [M0] P0_dense_anchor |
| 3 | headline DDR bytes per die | 134 889 472 B (= 128 MiB + 512 KiB + 128 KiB + 8 KiB + 8 KiB) | D | [M1] P1_bytes |
| 4 | tDdr, tLoad, tMma, tRes per core | 776 118 / 652 886 / 122 880 / 208 076 ns | D | [M1] P1_times |
| 5 | serial step and rate | 991 842 ns → 135.3 GB/s | D (+F: A) | [M1] P1_rate_serial |
| 6 | ping-pong step and rate | 784 118 ns → 171.2 | D (regime U) | [M1] P1_rate_pp |
| 7 | wall with 91 µs | 123.9 / 153.4 | D | [M1] P1_wall |
| 8 | vendor ratio; MMA occupancy; loader share of DDR time | 5.5×; 15.8 %; 84.1 % | D | [M1] P1_occupancy |
| 9 | ping-pong DDR-bound iff L ≥ 22.3 GB/s/core | threshold | D (∀L) | [M3] P3_loader_threshold |
| 10 | per-16 KiB piece: 754 / 618 / 120 / 203 ns; serial 941 | | D | [M4] P4_piece |
| 11 | per-expert serial 122 979 ns ≥ per-expert DDR 96 626 + 3 110 for all D ≥ 1 (min slack 22 536 ns at D = 1, t = 16) | Z3 premise | D (∀D) | [M15][M28] T_Z3_chain_dominates |
| 12 | rateS(D) increasing, limit 136.4; bracket [135.3, 136.4] for D ∈ [8, 128] | Z10 | D (∀D) | [M5] Z10_bracket |
| 13 | W-dyn: ⌈D/8⌉·T_W < D·T_S exactly on the listed set | Z7 | D (∀D ≤ 128) | Z7_crossover |
| 14 | W-dyn at D = 4, 8, 9, 10: 68.9, 137.7, 77.8, 86.4; W-static 17.3 | | D | [M5][M18] Z4_rows, Z9_static |
| 15 | K-split margin = T_launch + partials − D·ΔA, ΔA = 2 164 ns; cells of §7.3 | Z8 | D | [M20] Z8_ksplit |
| 16 | S-G2 per-expert chain 121 743 ns → 137.7 at D = 128 ≥ K-split 137.1 | | D | Z8_g2 |
| 17 | overflow bound: 127²·4096·32 < 2³¹ ; 127²·7168·18 < 2³¹ ; 22 × 66 064 384 < 2³¹ | P3 | D | [M12] P3_overflow |
| 18 | modular difference exact iff \|S_e\| < 2³¹ | P2 | D (Int) | P2_modular_diff |
| 19 | pack map bijection (k, n') ↔ offset on [0, K·N_c) | P1 | D (∀) | P1_pack_bijection |
| 20 | epilogue 2048 lane-ops = 47 ns per routed pair; 30.3 µs per step at t = 16, D = 128 | | D | [M8][M19] T_epilogue_vector |
| 21 | drain 32 KiB at 10 GB/s = 3 276 ns = 2.7 % of 122 979 | | D (rate U) | [M15] P5_drain |
| 22 | regression vs 2 × 487 µs: +17 842 ns = 9 892 (256 KiB of A lifts) + 8 000 (F) − 50 (anchor rounding) | | D | [M11] T_epilogue_regression |
| 23 | dispatch: 8σ_d / 128σ_d; host pre-pass 9.2 % / 211 % | | D (σ_d U) | [M16][M17] P4_dispatch |
| 24 | A-lift fraction 16/N_c: 3.1 / 6.3 / 12.5 / 25 % | | D | [M6][M14] P2_alift |
| 25 | G knob rates 136.7 / 137.4 / 137.7 | | D | [M14] P5_gknob |
| 26 | §8.1 table, 18 cells + tokens/ms | | D (Zipf D: U) | [T8] T8_row_t1 … T8_row_t16_Z15, T8_single_hot |
| 27 | §8.3 rows | | D | [M6][M22] T8s_4096_4096_8 … T8s_2048_512_4, T8s_steps |
| 28 | W4: 65.4 W4-GB/s serial = 130.8 W8-equivalent; 159.3 ping-pong; drain need 8.2 GB/s/core | | D (route U) | [M7] P6_w4 |
| 29 | buffers: S1 512–592 KiB; L0B 48 of 64; L0C 192/224 of 256; US ≈ 162 KiB | | D | [M9] P7_budget |
| 30 | D(t, s) generator means and ranges | §7.1 table | U (generator, 2000 seeds) | [Z] |
| 31 | 26.5 ≥ 22.3; 122.9 µs ≤ 776.1 µs (MMA off the path in both regimes) | | D | [M3] P3_margins |
| 32 | c_res sensitivity row; F sensitivity row | §8.2 | D | [M2] P8_sensitivity |
