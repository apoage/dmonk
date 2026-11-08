# DESIGN — execution layer for quantized-LLM decode matmul (one die, 8 cores)

> **PROMPT-6 AUDIT (2026-11-08 — errata #18–#31, the corrected #3 and the widened #25 against this design; all five designs in
> ERRATA-IMPACT.md).** No new silicon, no new theorem: model.py's output is unchanged (byte-identical), and the one cell this audit
> re-designates is already proved. Every correction is marked **audit** in place. The live structure is the R3 route (i8 × i8 → i32 —
> **erratum #19 does not touch it**: i8 chains across barriers are measured exact to depth 8 192); the f16 routes (R1, R1b, the W4 dequant
> chain) are record-only and their f16 accumulate chains would VIOLATE #19. **Live findings:** (1) **#25 VIOLATES the A ring** — slots of
> 2 KiB·mt put A copies at 2 / 4 / 6 KiB (mt = 1) up to 24 KiB offsets in the S1 A slot; only offset-0 4-KiB blocks and 32-KiB-granular
> offsets are proven — the production route is the whole A pack in 32 KiB legs at 32-KiB-granular offsets with loader-only lifts (or per-tile
> 4 KiB blocks at offset 0); (2) **#18:** `C[f][t]`, `A[f]` and the L0A/L0B slots are explicit byte-offset tensors — a view-sliced C lands
> in chunk 0, A view offsets are ignored; (3) **#30:** the `t mod 2` / `j mod 2` parities are nest-local — one global counter, reset by each
> consumer nest (at one tile per chunk the prefetch would land in the slot in use); per-region slab bounds (the fused-QKV example breaks the
> divisibility the bound assumes); (4) **#22 / #29:** the R3 dequant's per-row sx multiply is Duplicate + binary Mul (a unary Muls is a
> silent no-op — invisible at sx = 1), with sx read once under B7, not per row; (5) **#23 / #24 / #27:** the drain's stride encoding is
> unpinned (#23: strides are gaps) — adopt the production drain (1 KiB chunks + the measured US → US strided row extraction); 32 KiB drain
> slices as element copies land partially (#24) and as queue → vector-buffer stages hang (#27); (6) **#28:** one sync mechanism per edge,
> distinct event IDs for B3's two releases; (7) **#21:** E1's period-31 pattern aliases (b[k + 64, n] = b[k, n + 13]). **Re-designated
> cell:** m = 32 quotes **154.5** (T5_m32_restream) instead of 163.6 (A resident) until a #25 probe certifies 32 KiB-leg residency with live
> rows ≥ 2 — and HW-MAP already measures m ≥ 24 at 81 / 59 / 43 GB/s on the realised kernel, so both are pre-measurement cells.
> Corrected #3: the "errata-3 limit" citations are hygiene — no cell paid for them.

> **SILICON UPDATE (post-round-2, measured)**: three of this document's
> hypotheses are now SETTLED by measurement, and they change the ranking:
> (1) **f16×i8 does not exist at the raw matrix level** (errata #13) — the
> realized route is R3 (i8×i8→i32, per-token-quantized A), which has since
> **run at 137.8 GB/s aggregate m=1, fp64-verified 20/20** (gate met);
> (2) **per-call n caps at 16** and k=64 is anomalous — the (16,256,64)
> tile of §1.1 is impossible; the working loop is 16-chunk (16,16,128)
> sequences at 15 ns/call issue (12.5% occupancy);
> (3) the L0B geometry family G1a/G1b/G1c/G2 of §3.1 is superseded by the
> measured fragment [16 N × 32 K] column-major, byte n·32+k (HW-MAP).
> The model.lean theorems remain TRUE AS STATED — they were conditionals
> over these hypotheses; what changed is which hypotheses the silicon
> selected. A round-3 re-ranking under the measured facts (including the
> 26.5 GB/s/core serial loader rate and the overlap question it opens) is
> the natural next exercise; PROBLEM-2/3/4 sessions should read HW-MAP
> first and treat this document's ranking as pre-measurement history.

Scope: `y[m,n] = s[n] · Σ_k x[m,k]·W[k,n]`, m ∈ 1..64, K = N ∈ {2048..8192},
W8 (i8 + per-channel s[n]) primary, W4 (i4 + per-group offset/scale) secondary.
Everything below derives from HW-MAP.md / ISA.md. Status tags: **M** = measured
in HW-MAP, **P** = PRIOR in HW-MAP, **U** = UNMEASURED (branched, experiment named).

Units: buffer sizes in KiB/MiB (binary); rates in GB/s (decimal). 64 MiB = 67.11 MB.
Derived rates are quoted to one decimal, rounded half-up at the 0.1 GB/s step; thresholds on
unmeasured rates are stated at that 0.1 granularity.

**Verification (round 2):** every derived number below is reproduced by `proof/model.py` and
fixed by a theorem in `proof/model.lean` (core Lean 4, `decide`/`omega` only, no axioms);
`PROOF-COVERAGE.md` is the claim-by-claim ledger and lists the corrections that formalization
forced on round 1 (tile geometry §3.1, K-split §6, scheme-P costs §1.4, several roundings).

## Constants used (all from HW-MAP)

| Symbol | Value | Derivation / status |
|---|---|---|
| R_ddr | 173.8 GB/s/die | M (fp16 stream) |
| R_stage | 180 GB/s/die = 22.5 GB/s/core | M (DDR→S1 plain copies, per-core slabs); 173.8/8 = 21.725/core at the stream roof |
| R_us→s1 | 250 GB/s/core | M (48–64 KiB tiles) |
| L | S1→L0 loader rate, GB/s/core | **U** — the open number |
| τ_mma | 3.7 ns per 16³ fragment/core | M-derived: 17.8 TFLOPS/8 cores; 2.46 ns at the 26.6 figure; ≤3.46 ns implied by the f16 library matmul staying flat at 148 GB/s to M=128 (8 fragments per 512 B B-fragment: 512 B / 18.5 GB/s/core = 27.7 ns / 8 = 3.46 ns) |
| c_mma | MMA per-call issue cost | **U** |
| R_vec | 40 lanes/cycle × 1.08 GHz = 43.2 G lane-ops/s/core | M |
| D | dedicated i4→f16 dequant rate, Gelem/s/core | **U** |
| T_launch | ~91 µs per kernel launch+queue | M (floor seen in ≤32 KiB tile tests) |
| COPY_FRAC | 7 GB/s/core | M (software) |
| S1 | ~1 MB (decimal; modeled as 1 000 000 B = 976 KiB) | P |
| US | 256 KiB (≥208 evidenced) | P/M |
| L0A, L0B | ≥32–64 KiB each | P |
| L0C | ≥64 KiB (16×1024 f32) | P |

---

## 0. Summary, ranking, and the one measurement that moves the ranking

**Ranked #1 (build this): Route 1 — W8, host fractal-packed i8 → DDR→S1 64 KiB plain
copies → L0LOAD S1→L0B in 16 KiB tiles → f16×i8 MMA (m=16, n=256, k=64) → f32 C
resident in L0C across all of K → one staged drain per slab → s[n] in the vector
epilogue. N split 8-way across cores, no cross-core sync.**

Predicted effective weight-byte rate, K=N=8192, W8 (derivations in §7):

| Branch | m=1 | m=16 | m=32 | m=64 |
|---|---|---|---|---|
| DDR-bound (L ≥ 21.8 GB/s/core, the first 0.1 step above 173.8/8 = 21.725) | **168.5** | 168.5 | 163.6 (A resident in S1) / 154.5 (re-streamed) | 115.9 (L0C = 64 KiB) → 138.4–154.5 with scheme P (§1.4) |
| Loader-bound (L ≤ 21.7) | 8·L·(64/66) → L=18.5: 143.5; L=15.5: 120.2 | same | same minus slab re-stream | — |
| Wall-clock incl. unpipelined 91 µs launch floor | 137.2 | 137.2 | | |

Honest in-kernel ceiling of the design: 173.8 × (64 KiB B)/(66 KiB B+A) = **168.5 GB/s**
(174.5 if the 180 GB/s staging figure is the true roof). Target is 120.

Ranking of all viable routes by expected m=1 GB/s (of the route's own weight bytes) and risk:

| # | Route | Expected m=1 (DDR branch) | What it needs | Risk |
|---|---|---|---|---|
| 1 | R1: W8 f16×i8 (this design) | 168.5 | L ≥ 21.8; f16×i8 oracle passes (E1); dense i8 tile geometry G1 (§3.1); L0B ≥ 32 KiB, L0C ≥ 64 KiB | medium: one U rate, one unverified dtype combo, one geometry hypothesis |
| 2 | R3: W8 i8×i8 → i32, epilogue sx[m]·s[n] | 168.5 (identical byte stream, identical fragment count) | L ≥ 21.8; i8×i8 oracle; host-quantized A for the benchmark; **no f16→i8 cast in ISA.md** → integration gap | medium; swap-in if E1 fails on f16×i8 |
| 3 | R1b: W8 → vector i8→f16 cast → f16×f16 | 168.5 if L ≥ 43.5 (f16 tiles are 2 B/elem) and vector 48.8% busy (8 Mi casts / 43.2 G/s = 194 µs of 398); target needs L ≥ 31.0 | the cast op works at the 40-lane rate; L twice R1's; independent of the i8 tile geometry | medium-high; fallback if both integer MMA combos fail; **#1 if E1 shows geometry G2** |
| 4 | R2: W4 dedicated dequant → f16×f16 | 163.6 W4-GB/s (= 2× R1 tokens/s; DDR-bound incl. the A stream) only if D ≥ 43.5 Gelem/s/core **and** L ≥ 86.9 GB/s/core f16; target 120 needs D ≥ 30 and L ≥ 60 | two U rates chained + unknown group semantics | high |
| 5 | R4: vector-only | 70–78 (M) and ∝1/m | — | none, it is the floor |
| 6 | R5: vendor GEMM | 4.2 (M) | — | dead |

**The single measurement that most changes the ranking: the S1→L0 loader rate L (E2).**
L ≥ 86.9 and D ≥ 43.5 → R2 doubles token rate and moves to #1. 21.8 ≤ L < 60 → R1 at the roof
is #1 and R2 is loader-capped below its own target. L < 15.5 → every MMA route is below
target and the only remaining lever is DDR→L0 direct (E3); if that is a no-op too, the
answer is the measured vector floor (R4, 70–78). The one *non-rate* unknown with the same
leverage is the i8 tile geometry (§3.1): if E1 shows 2 B per element (G2), R1 drops to 85.6
and R1b becomes #1 at the same 168.5.

Why 69 GB/s/core is *not* the threshold: 69.2 = 256 B per i8 fragment / 3.7 ns is the rate at
which an idle MMA could *consume* B. DDR hands each core only 21.7–22.5 GB/s, so the loader
only has to keep pace with DDR, not with the MMA. 69 would matter only with weights resident
in SRAM, which they never are here.

---

## 1. Loop nest + tiling

### 1.1 Shapes
- Core c ∈ 0..7 owns output columns `n ∈ [c·N_c, (c+1)·N_c)`, `N_c = N/8` (1024 at N=8192,
  512 at 4096, 256 at 2048). Every core sees all K and all m rows.
- A fragment count `mt = ceil(m/16)`; A operand per core per fragment = f16 [16, K], rows ≥ m zero.
- MMA call shape: **m=16, n=256, k=64**, i8 B tile = 256·64 = 16 KiB, f16 A block = 16·64·2 = 2 KiB,
  C sub-slab 16·256·4 = 16 KiB. This is the only shape with any silicon evidence (library-internal
  n=256, k=64); E1 sweeps larger n/k and the tile grows if they pass content checks.
- Fragments per call = (256/16)·(64/16) = 64 → 64 × 3.7 ns = **236.8 ns** compute per call
  (157.4 ns at 2.46 ns).
- Slab width: `N_slab = min(N_c, floor_256(L0C / (16·mt·4 B)))`; with L0C = 64 KiB (P):
  mt=1 → 1024 (1 slab at N=8192), mt=2 → 512 (2 slabs), mt=3,4 → 256 (4 slabs).

### 1.2 Loop nest (per core)
```
load s[c·N_c .. +N_c) → US                           (4 KiB, once; audit #24: plain form or ≤ 4 KiB element blocks — 12 KiB at fused QKV)
for slab s in 0 .. N_c/N_slab-1:                      # n-outer
  for k-chunk j in 0 .. K/64-1:                        # k-inner (64 rows)
    copy-in : B tiles (j, t) for all t in slab s → S1 B-ring[j mod 4]   (16 KiB each, 64 KiB per COPY)
              A blocks (j, f) for f in 0..mt-1       → S1 A-ring[j mod 4]   (2 KiB·mt, one COPY)
              # audit (#25): VIOLATES — slot offsets 2·mt·(j mod 4) KiB are neither offset 0 nor 32-KiB-granular;
              # stage the whole A pack once in 32 KiB legs at 32-KiB-granular offsets (loader-only lifts), or 4 KiB blocks at offset 0
    loader  : A blocks → L0A[j mod 2]; B tile t → L0B[t mod 2] (double-buffered, one tile ahead)
              # audit (#30): nest-local parities — use one global counter for loader and MMA, reset by each consumer nest
              # (at one tile per chunk the prefetch would land in the slot still in use)
    for tile t in slab s:                              # N_slab/256 tiles
      for f in 0 .. mt-1:
        MMA(C[f][t], A[f], B[t], {m=16, n=256, k=64, initVal = (j == 0 ? ZERO : ACC)})
        # audit (#18): C[f][t], A[f] and every L0 slot are explicit byte-offset tensors — a view-sliced C lands in chunk 0,
        # A view offsets are ignored (and the init flags are ignored on this part: HW-MAP)
  vector  : drain rows r < m of C slab → US (2D staged read); y = C·s[n]; f32→f16
  copy-out: y rows → DDR
```
initVal is ZERO exactly once per (slab, tile, f), at j = 0; a k-chunk count of 128 (K=8192)
means an inverted initVal keeps only chunk 127 — E1 tests with ≥2 chunks for that reason.

### 1.3 Issue-count arithmetic (K=N=8192, per core)
- Calls = (K/64) · (N_c/256) · mt = 128 · 4 · mt = **512·mt**. Independent of slab count.
- MMA busy = 512·mt × 236.8 ns = **121 µs** at mt=1, then 242 / 364 / 485 µs for mt = 2 / 3 / 4
  (3.7 ns); 81 / 161 / 242 / 322 µs at 2.46 ns; 113 / 227 / 340 / 454 at 3.46 ns.
- DDR delivers one 16 KiB tile per core every 16384 B / 22.5 GB/s = 728 ns (754 ns at 173.8).
- Slack for issue overhead per call at m ≤ 16: 728.0 − 236.8 = **491.2 ns**. c_mma (U) ≤ 491 ns
  keeps the matrix engine off the critical path (492 ns is the first value that does not);
  c_mma = 1 µs would cap at 8 × 16 KiB / 1.2368 µs = 106.0 GB/s. If E1 shows (n=1024, k=64)
  legal and L0B ≥ 128 KiB, calls drop 4× and the slack per call becomes 1.96 µs.
- K=N=4096: N_c = 512, calls = 64·2·mt = 128·mt. K=N=2048: N_c = 256, calls = 32·mt.
- m-dependence: calls scale with mt, so m=1 and m=16 cost identical MMA time (121 µs);
  m=64 costs 485 µs, above the 373 µs B-only DDR time at 22.5 GB/s/core, so the MMA is the
  wall at m=64 whenever DDR finishes first: 8 MiB / 485 µs = 17.3 GB/s/core = 138.4 GB/s/die
  at 3.7 ns. With scheme P's 434 µs of DDR that holds for τ > 3.31 ns; at 2.46 ns it is
  DDR-bound again.

### 1.4 k-outer vs n-outer: n-outer / k-inner, for three measured reasons
1. **C-slab residency.** ISA lists L0C as readable only via staged reads; no US→L0C write
   path exists, so a partial accumulator cannot be reloaded. The full-K reduction of a slab
   must finish inside L0C, which forces k to be the inner loop of each slab. k-outer would
   need a drain + f32 re-add per k-chunk: 128 chunks × 64 KiB·mt = 8 MiB·mt per core, the
   size of the entire weight stream, through an unmeasured path. Dead.
2. **A residency.** A is the small operand: 2 KiB·mt per 64 KiB chunk (3.1% at mt=1, 12.5%
   at mt=4), so streaming it with B from DDR costs ≤12.5% of DDR per slab. n-outer re-streams
   A once per slab; the cost is n_slabs × that (table in §7.2). S1 residency (256 KiB at
   mt=1, 512 KiB at mt=2) removes the re-stream when S1 ≥ 768 KiB (P).
3. **Weight-stream sequentiality.** Pack order = visit order (§3.1): each core reads one
   contiguous K·N_c region (8 MiB) in 64 KiB sequential pieces, i.e. exactly the per-core-slab
   pattern that measured 180 GB/s aggregate.

**Scheme P (m=64 upgrade, gated on E6/E7-S1):** keep A resident in S1 per k-block of 2048
rows (64·2048·2 = 256 KiB), loop slabs inside the k-block, drain each slab's partial C after
the block, and accumulate the 4 partials in f32 in S1 (256 KiB) via US. A is read from DDR
once (1 MiB/core, 12.5%) instead of 4× → DDR 434 µs → 154.5 GB/s, MMA-capped at 138.4 (3.7 ns)
to 148.0 (3.46 ns). Cost: 4 blocks × 4 slabs × 64 KiB = 1 MiB of L0C drain per core (U rate;
105 µs at 10 GB/s/core, so ≥ ~10 GB/s/core keeps it hidden) + 3 × 64 Ki f32 Adds = 196 608
lane-ops = 4.6 µs vector + 2 MiB of US↔S1 copies at 250 GB/s = 8.4 µs (round 1 said 1 Mi adds
/ 3 MiB — corrected by proof/model.lean T5_P_*). S1 = 256 (A block) + 256 (B ring) + 256
(partials) = 768 KiB.

---

## 2. Buffer budget (per core)

| Buffer | Memory | Size | Depth / queue | Why this size and depth |
|---|---|---|---|---|
| B ring | S1 | 4 × 64 KiB = 256 KiB | 4 buffers, queue depth 4 (errata 9) | 64 KiB is the largest legal single COPY (errata 2) and the measured 180 GB/s granule. One chunk (66 KiB incl. A) = 3.0–3.1 µs of DDR; depth 4 keeps copy-in ≥ 2 chunks (≥ 6.2 µs) ahead of the loader, hiding per-call copy issue latency (U) and DDR jitter |
| A ring | S1 | 4 × 2 KiB·mt ≤ 32 KiB | 4 / 4 | same cadence as B; separate queue so a B slot never waits on an A copy — **audit (#25): VIOLATES (slot offsets ≥ 4 KiB, not 32-KiB-granular); the production route stages the whole A pack in 32 KiB legs** |
| A resident (option, m ≤ 32) | S1 | 16·mt·K·2 B = 256 KiB (mt=1), 512 KiB (mt=2) (**audit, #25:** UNSAFE until a probe certifies 32 KiB legs with live rows ≥ 2 — m = 32 quotes 154.5, T5_m32_restream) | 1 | replaces per-slab DDR re-stream; requires S1 ≥ 768 KiB (P ~1 MB = 976 KiB, E7-S1 confirms); the 1 MiB needed at mt=3 does not fit |
| L0A | L0A | 2 × 2 KiB·mt ≤ 16 KiB | 2 / 2 | A block for chunk j+1 loads while chunk j runs; fits the 32 KiB P lower bound at mt=4 |
| L0B | L0B | 2 × 16 KiB = 32 KiB | 2 / 2 | equals the P lower bound; tile t+1 loads during the 237·mt ns of tile t. If E4 shows L0B ≥ 64 KiB → 2 × 32 KiB tiles (n=512,k=64 or n=256,k=128), halving call count |
| L0C | L0C | 16·mt·N_slab·4 B = 64 KiB | 1 | equals the P lower bound by construction (N_slab derived from it) |
| s[n] | US | N_c × 4 B = 4 KiB | 1 | loaded once per matmul via DDR→US (M path) |
| drain staging | US | 4 KiB (m=1, row 0) … 64 KiB (m=16, N_slab=1024) | 2 × 32 KiB (**audit, #24 / #27:** drain in 1 KiB chunks read from the drained queue tensor — 32 KiB element copies land partially, 32 KiB queue → vector stages hang) | staged L0C reads sliced at ≤32 KiB (errata 2 margin) |
| y staging | US | 16·mt·N_slab·2 B ≤ 32 KiB | 1 | f16 result for copy-out |
| **S1 total** | | **288 KiB** streamed-A / **800 KiB** A-resident (mt=2) | | 288 fits even a 512 KiB S1; 800 needs the P ~1 MB |
| **US total** | | ≤ 100 KiB (W8) | | within the 208 KiB evidenced |
| **L0** | | L0A ≤ 16, L0B 32, L0C 64 KiB | | at the P lower bounds |

W4 variant of US (§5): i4 in-ring 2 × 16 KiB + f16 out-ring 2 × 32 KiB + drain 32 KiB + y 32 KiB
+ s 4 KiB = 164 KiB ≤ 208 KiB evidenced.

---

## 3. Byte-level layouts

### 3.1 W8 weight pack (host-side, free) — tile geometry carried as an explicit hypothesis
HW-MAP gives, silicon-verified: "F = [N/16][K][16], innermost 16-element run; for i8 each
innermost run is a 32 B block; block (i, r) of a [Kb, 256] tile at byte (i·Kb + r)·32". For a
dense i8 tile of 64 rows × 256 columns (16 KiB — the byte count every rate in this document
uses) that formula only closes if a 32 B block holds 32 elements, i.e. i indexes **8 column
groups of 32**. That is the primary reading, **G1c**. Round 1 of this section used 16-column
groups with 16 B of each 32 B block, which is not a bijection: byte 16 of every block was never
written and the last element landed at byte 32751 of a "16 KiB" tile (caught by
proof/model.lean T7_old_*). The alternatives are carried and E1's pack probe picks one:

| Hyp. | Element (k, n') of a 64×256 tile at byte | Tile | Proof |
|---|---|---|---|
| **G1c** (primary) | ((n' div 32)·64 + k)·32 + n' mod 32 | 16 KiB | T7_g1c_* (bijection) |
| G1a | ((n' div 16)·32 + k div 2)·32 + (k mod 2)·16 + n' mod 16 | 16 KiB | T7_g1a_* (bijection) |
| G1b | ((n' div 16)·32 + k div 2)·32 + (n' mod 16)·2 + k mod 2 | 16 KiB | T7_g1b_* (bijection) |
| G2 | ((n' div 16)·64 + k)·32 + (n' mod 16)·2 + byte, 2 B per element | 32 KiB | T7_g2_* |

Under any G1 the rest of the design is unchanged. Under G2 every i8 tile is 2 B per element:
the W8 stream becomes 130 MiB per die → 85.6 GB/s (T9_g2_rate), below target, and Route 1b
(dense i8 from DDR, vector cast to f16 on-chip, f16×f16 MMA) becomes the #1 route at the
same 168.5 with its own loader thresholds, 43.5 (roof) / 31.0 (target) GB/s/core.

Full address under G1c. Core c, tiles-per-k-chunk `T = N_c/256`, k-chunk `j = k div 64`,
`r = k mod 64`, `n' = n − c·N_c`, `t = n' div 256`, `i = (n' mod 256) div 32`, `l = n' mod 32`:

```
addr(W[k,n]) = c·K·N_c                      # per-core region, contiguous (8 MiB at 8192²)
             + (j·T + t)·16384              # tile index q = j·T + t, visit order (k-chunk outer, tile inner)
             + (i·64 + r)·32                # HW-MAP block (i, r) at (i·Kb + r)·32 with Kb = 64, i < 8
             + l                            # 32 i8 columns per block
```
Each 16 KiB tile is one [Kb=64, 256] fractal; the only design choice is the tile order, which
equals the loop's visit order so the copy-in reads 4 consecutive tiles per 64 KiB COPY. For
N_c = 1024 a 64 KiB copy is one k-chunk; for N_c = 512 it is two k-chunks; for N_c = 256 four.
The loader lifts tile q from S1 slot offset (q mod 4)·16384 to L0B — a plain contiguous 16 KiB
move (no stride, no transform).

### 3.2 A pack (f16) — geometry **P**, settled by E1's one-hot probe
Applying the verified B rule to A's [rows = m, cols = k] axes: `F_A = [K/16][16 m][16 k]`.
Per k-chunk j and fragment f, the 2 KiB block:
```
A_pack[j][f] : byte (g·16 + mr)·32 + kl·2  ↔  x[16f + mr, 64j + 16g + kl],  g ∈ 0..3, zero if 16f+mr ≥ m
```
Blocks (j, 0..mt−1) are contiguous, so one COPY of 2 KiB·mt per chunk (**audit, #25:** into the A ring's offsets this violates the staging rule — see §2). Benchmark: host-packed.
Integration: the producing layer's epilogue writes y in this order (§3.3). If E1 shows the
A fractal is different, only this host routine and the epilogue scatter change.

### 3.3 C layout and drain path — geometry **P**, verified by E1 (row 0) and E6
C slab in L0C: `[N_slab/16][16 m][16 n] f32`; row r of column-group i at byte (i·16 + r)·64.
Drain row r = 2D staged read of N_slab/16 runs × 64 B at stride 1024 B → contiguous [N_slab] f32 (**audit, #23:** blocked strides are
gaps, so this needs 960 B, not the 1 024 B pitch — the production drain sidesteps it: whole 1 KiB chunks, then the measured US → US strided
row extraction)
in US (m=1: one read, 4 KiB — matches HW-MAP's "row 0 only ≈ 4 KB/core"). Then per row:
`Mul(row, s, 1024 lanes)` (= errata-3 limit, one call per row — audit: hygiene, corrected #3; the per-row s operand forces one call per row anyway) → `Cast f32→f16` (1024 lanes) →
COPY US→DDR 2 KiB (benchmark: row-major y at byte (r·N + c·N_c + n')·2; rows batched to one
32 KiB copy at m=16 — audit #23 / #24: a blocked copy, 16 × 2 KiB with a destination gap of (N − N_c)·2 B, never an element copy > 4 KiB).
Integration scatter into the next layer's A pack: 16-element runs of 32 B at stride 512 B.
Use a 2D COPY if E5 proves US→DDR 2D is a real position pair; else COPY_FRAC is acceptable
*here only* because the volume is tiny: ≤32 KiB/core (m=16) at 7 GB/s = 4.7 µs = 1.2% of a
398 µs 8192² matmul; at 2048², m=16 the y slab is 8 KiB → 1.2 µs = 4.3% of 27 µs. Never on the
weight path.

### 3.4 Numerics
f32 accumulation in L0C over the full K (no f16 partials anywhere → errata 5 cannot bite).
Output f16: y magnitudes are model activations; the only f16 cast is the final one (saturation
at 65504 only if |y| > 65504, which a decode layer never produces; E9 verifies the cast's
rounding mode is not a silent no-op, errata 6).

---

## 4. Pipeline + sync plan

### 4.1 Engine roles per k-chunk (steady state, DDR branch, K=N=8192, m ≤ 16)
| Engine | Work per chunk | Time per chunk | Occupancy |
|---|---|---|---|
| copy-in | COPY 64 KiB B + COPY 2 KiB·mt A, DDR→S1 | 66 KiB / 21.725 GB/s = 3.11 µs (3.00 at 22.5) | 100% — this is the roof |
| loader | 4 × L0LOAD 16 KiB + L0LOAD 2 KiB·mt, S1→L0 | 66 KiB / L | 21.725/L (U) |
| MMA | 4·mt calls × 236.8 ns | 0.947·mt µs | 30.5% (mt=1), 60.9% (2), 91.4% (3), 121.8% (4) of the 3.11 µs chunk |
| vector | nothing until the slab ends | — | ~0 |
| copy-out | nothing until the slab ends | — | ~0 |
Slab end (once per slab): drain ≤64 KiB staged read + 16·mt Mul and 16·mt Cast calls of 1024
lanes (32 768 lane-ops / 43.2 G = 0.76 µs at mt=1) + copy-out ≤32 KiB. Pipeline fill ≈ 3.1 µs
(first chunk) + 16 KiB/L + 236.8 ns. The fill + drain budget of ≤ 5 µs is an ASSUMPTION
(measured in E7/E10): 1.2% at 8192² (398 µs), 15.6% at 2048² (27 µs).

### 4.2 Every cross-engine boundary and its barrier
| # | Edge | Event that releases | Protects |
|---|---|---|---|
| B1 | copy-in → loader | both COPYs of chunk j retired | loader never reads a half-landed S1 slot |
| B2 | loader → MMA | L0A[j mod 2] and L0B[t mod 2] loads retired | MMA never multiplies a half-loaded tile |
| B3 | MMA → loader | MMA(tile t) retired → L0B[t mod 2] free; last MMA of chunk j retired → L0A[j mod 2] free | loader never overwrites an operand in use |
| B4 | loader → copy-in | all T tiles + A block of slot j lifted | copy-in never refills an S1 slot still being read (chunk j+4) |
| B5 | MMA → vector | last MMA of the slab retired | drain never reads a C still accumulating |
| B6 | vector → MMA | drain of slab s retired | the next slab's initVal=ZERO never clobbers a C mid-drain (slab boundary only) |
| B7 | copy-in → vector | s[n] COPY retired | epilogue never multiplies by garbage scales |
| B8 | vector → copy-out | Cast of the y rows retired | copy-out never ships a half-written y |
| B9 | copy-out → vector | COPY of y retired | y staging reused only after it left US |
All nine are explicit pipe barriers (ISA: "explicit pipe barriers between engines"). Within a
single queue (B ring, A ring, L0A, L0B) ordering comes from the queue's own buffer mechanics (**audit, #28:** one mechanism per edge —
no explicit flag layered on a queue's own arm; B3's two releases take distinct event IDs, legal per #14)
with declared count = depth (errata 9: 4/4, 4/4, 2/2, 2/2). Nothing relies on timing.

### 4.3 Where errata 8 could enter, and how it is suppressed
Nondeterministic ~512 B islands come from hand-managed cross-engine readback without barriers.
The exposed readbacks in this design are exactly B3, B4, B5, B6, B8, B9 — each is a barrier,
not a queue assumption. Detection (E7): the f32 accumulation order is fixed (chunks j = 0..127
into one accumulator, tiles in a fixed order), so two runs on identical input must be
**bit-identical**; any rep-to-rep difference across ≥20 reps is a sync fault, independent of
the host reference. A positive control (run with B5 deleted) must reproduce islands, proving
the detector sees them.

---

## 5. W4 strategy

Weight bytes per die = K·N/2 = 32 MiB at 8192² → 33.55 MB / 173.8 = 193 µs at the roof;
target 120 W4-GB/s = 280 µs. Elements to dequantize per core = 8 Mi.

| Option | Cost in measured units | Verdict |
|---|---|---|
| **(a) dedicated dequant instr → f16 fractal → f16×f16 MMA** | rate D (**U**). D = 43.2 Gelem/s/core (the vector-unit class rate) → 8 Mi / 43.2 G = 194 µs → dequant-bound 172.8 W4-GB/s, vector ~100% busy; the DDR roof including the 2 MiB A stream is 32/34 × 173.8 = 163.6, so the chain lands at 163.6 (round 1 said ~170). D = 30 → 280 µs = target 120.0. Token-rate break-even with W8 at the roof (173.8 G weights/s ÷ 8 cores = 21.725 Gelem/s/core): D ≥ 21.8 at 0.1 granularity → 385 µs → 87.2 W4-GB/s; D = 21.7 → 86.8 falls just short. Chain after dequant: US→S1 f16 at 2 B/elem = 86.9 GB/s/core at roof (M: 250 ✓) → **S1→L0B f16 at 86.9 GB/s/core at roof, 60 at target** (U — 4× the W8 requirement) → f16×f16 MMA at 512 B/fragment → 3.7 ns → 138.4 GB/s/core consumption, 62.8% busy at roof | the only W4 route that can beat W8; gated on D and L |
| (b) vector arrange (And, shift or Mul-1/16, i8→f16 cast, Adds offset, Mul scale ≈ 5 lane-ops/elem) | 8 Mi × 5 / 43.2 G = 971 µs/core → 33.55 MB / 971 µs = **34.6 W4-GB/s** (= 69.2 W8-equivalent); plus errata 4 (16-bit shifts no-op) and errata 6 (rounding no-op) on the hot path | dead; agrees with the measured 22 GB/s vector-only W4 |
| (c) f16 round-trip (host dequant, stream f16) | 2·K·N = 134 MB / 173.8 = 772 µs → 43.5 W4-equivalent GB/s; it is the measured 144–148 f16 matmul | dead: half the W8 token rate |
| (d) dequant to i8 + i8×i8 with per-group partial drains | instruction emits f16 and no f16→i8 cast is listed; per-group K-scales cannot fold into a per-n epilogue; K/128 = 64 drains × 64 KiB·mt = 4 MiB·mt per core through the U drain path | not pursued unless E6 shows drain ≥ 50 GB/s/core |

**Group-semantics problem (U).** Fractal order puts 16 different n in consecutive lanes, so a
K-grouped (G=128) scale is a per-lane 16-vector constant over 128 k-rows = 2048 consecutive
elements. Two pack variants, both proven or killed by E8 differencing:
- V1: i4 packed in the element order of the f16 fractal the MMA needs (2 elements per byte), scale/offset
  supplied as a 16-lane vector per 2048-element run — works iff the instruction accepts a
  vector scale.
- V2: i4 packed k-contiguous [N][K] (scalar scale per 128-run, the natural quant format),
  dequant produces f16 [n][k] rows, and the **loader transpose variant** (ISA lists one, U)
  lands it in L0B as the [K, N] operand.
If neither passes, W4 cannot feed the MMA from a fractal tile at better than the 7 GB/s
COPY_FRAC rate, and W4 falls back to W8.

**Decision rule:** run W4 only when `8·min(D·0.5 B, L/4)` ≥ 86.9 GB/s (i.e. W4 token rate beats
W8 at the roof: D ≥ 21.8 Gelem/s/core and L ≥ 43.5 GB/s/core f16 at 0.1 granularity; exact
crossovers 21.725 and 43.45), expect the target (120 W4-GB/s) only when D ≥ 30 and L ≥ 60, and
the roof (dequant and loader both non-binding) only when D ≥ 43.5 and L ≥ 86.9.

---

## 6. Cross-core partitioning

**N-split, 8 ways.** Core c computes all m rows × all K for columns [c·N/8, (c+1)·N/8).
- Shares only the DDR roof: 8 disjoint sequential 8 MiB weight regions + the same A read by
  all 8 cores (2 MiB·mt total, 3.1%·mt of the weight bytes).
- No reduction, no cross-core sync — mandatory, since hand-rolled kernels have no mailbox.
- Identical work per core → no imbalance; the 180 GB/s staging number was itself measured as
  8 concurrent per-core slabs, so DDR fairness is inside the measured figure.
- Aggregate = 8 × per-core = `min(173.8–180, 8·L·64/66, 8·16 KiB/(237·mt ns + c_mma))`.
- N must make N_c a multiple of 256 (pad N otherwise; QKV-fused N = 3·N_model is fine). **audit (#30):** the slab loop bound N_c/N_slab
  assumes N_slab | N_c, which "a multiple of 256" does not give (fused QKV at N_model = 4096: N_c = 1536 against N_slab = 1024) — bound the
  loop per region, the last slab N_c − s·N_slab wide.

Alternatives, with arithmetic:
- **K-split** (core = K/8 rows × all N): A per core shrinks to 128 KiB at m=64 (fits S1), but
  each core emits a partial C[m, N] (2 MiB f32 at m=64) → 16 MiB of DDR writes, 16 MiB of
  reads in a second reduction launch (no cross-core sync in-kernel) and 2 MiB of y → 99 MiB
  per die → 112.4 GB/s at m=64 (97.5 counting the extra 91 µs launch) versus 115.9 for N-split
  at L0C = 64 KiB, and worse than N-split at every m ≤ 32. Round 1 quoted 136 here; it omitted
  the reduction read-back (caught by proof/model.lean T9_ksplit). Not worth a second launch.
- **M-split** (core groups per 16-row block): re-streams W once per block → m=64 costs 4× the
  weight bytes → 258 MiB per die → 43.1 GB/s. Dead.

**Launch granularity.** Without cross-core sync, one launch per matmul (or per group of
matmuls sharing x: fuse Q/K/V into N = 3·N_model, gate/up into 2·N_model → 4 launches per
layer instead of 7). With the 91 µs floor unpipelined, a standalone 2048² W8 matmul is
4.19 MB / (27 + 91 µs) = 35.5 GB/s wall-clock no matter how good the kernel is; 8192² is
137.2 GB/s wall. E0 decides whether queued launches overlap the floor.

---

## 7. Predicted performance

### 7.1 Per-stage occupancy, K=N=8192, W8, m=1 (= m=16), DDR branch
| Stage | Bytes per core | Time | vs roof |
|---|---|---|---|
| DDR / copy-in | 8 MiB B + 256 KiB A = 8650752 B | 398 µs | 100% |
| loader | 8650752 B | 8650752 B / L | 100% needs L ≥ 21.8 GB/s/core; target needs 15.5 |
| MMA | 512 calls | 121 µs (3.7 ns) / 81 µs (2.46) | 30.4% / 20.2% |
| vector | 16 rows × (Mul + Cast) × 1024 lanes | 758 ns | 0.2% |
| copy-out | 2 KiB (m=1) / 32 KiB (m=16) | < 0.2 µs | ~0 |
| fill + drain (ASSUMED ≤ 5 µs, empirical E7/E10) | | ≤ 5 µs | 1.2% |

Effective weight-byte rate = 67 108 864 B / 398 193 ns = **168.5 GB/s** at the 173.8 roof
(= 173.8 × 64/66); 174.5 at the 180 staging rate. m=16 is identical (mt = 1 either way).

### 7.2 m-curve, K=N=8192, W8, L0C = 64 KiB (P), DDR branch
| m | mt | N_slab | slabs | A per core | A policy | DDR bytes/die | DDR time | MMA time 3.7 / 3.46 / 2.46 ns | predicted |
|---|---|---|---|---|---|---|---|---|---|
| 1, 16 | 1 | 1024 | 1 | 256 KiB | once | 66 MiB | 398 µs | 121 / 113 / 81 | **168.5** (DDR-bound at 3.7 ns) |
| 32 | 2 | 512 | 2 | 512 KiB | resident in S1 | 68 MiB | 410 µs | 242 / 227 / 161 | **163.6** (DDR-bound at 3.7 ns) |
| 32 (A re-streamed) | 2 | 512 | 2 | 512 KiB | re-streamed ×2 | 72 MiB | 434 µs | 242 / 227 / 161 | **154.5** (DDR-bound at 3.7 ns) |
| 48 | 3 | 256 | 4 | 768 KiB | re-streamed ×4 | 88 MiB | 531 µs | 364 / 340 / 242 | **126.4** (DDR-bound at 3.7 ns) |
| 64 | 4 | 256 | 4 | 1024 KiB | re-streamed ×4 | 96 MiB | 579 µs | 485 / 454 / 322 | **115.9** (DDR-bound at 3.7 ns) |
| 64, scheme P | 4 | 256 | 4 | 1024 KiB | once (scheme P) | 72 MiB | 434 µs | 485 / 454 / 322 | **138.4–154.5** (MMA-bound at 3.7 ns) |
| 64, L0C ≥ 256 KiB | 4 | 1024 | 1 | 1024 KiB | once | 72 MiB | 434 µs | 485 / 454 / 322 | **138.4–154.5** (MMA-bound at 3.7 ns) |
The curve is flat through m=32 and sags at m=48–64 by the A re-stream (DDR) and by the MMA
fragment count; the sag is bounded below by 115.9 at the P value of L0C and lifted to
138.4–154.5 by either a larger L0C (E4) or scheme P (E6, E7-S1); the scheme-P band is MMA-bound
for τ > 3.31 ns and DDR-bound below. Honest statement: **m=64 at the P sizes is 115.9, 3% under
target**, and the fix is a measurement, not a redesign.

### 7.3 Loader-bound branch
Predicted = min(168.5, 8 · L · 64/66): DDR-bound iff L ≥ 21.8 GB/s/core (the first 0.1 step
above 173.8/8 = 21.725), target met iff L ≥ 15.5 (proof/model.lean T2_*).

| L (GB/s/core) | 8·L·64/66 | predicted W8 | Route 1b (f16 tiles, L/2) |
|---|---|---|---|
| 10.0 | 77.6 | 77.6 | 38.8 |
| 15.5 | 120.2 | 120.2 | 60.1 |
| 18.5 | 143.5 | 143.5 | 71.8 |
| 21.7 | 168.3 | 168.3 | 84.2 |
| 21.8 | 169.1 | 168.5 | 84.6 |
| 22.0 | 170.7 | 168.5 | 85.3 |
| 31.0 | 240.5 | 168.5 | 120.2 |
| 43.5 | 337.5 | 168.5 | 168.5 |

Evidence on L: none direct. The f16 library matmul moved 148/8 = 18.5 GB/s/core of f16 B into
L0 by *some* path (S1→L0 or DDR→L0 direct, unknown which), so at least one L0 ingress path
sustains ≥ 18.5 GB/s/core → ≥ 143.5 GB/s on this design **if that path is S1→L0**
(T2_inference_from_library carries exactly that premise). This is inference, not measurement.

### 7.4 Other sizes, W8, m=1, DDR branch
| K=N | W8 bytes/die | DDR time incl. A | in-kernel | with ASSUMED 5 µs fill/drain | wall with unpipelined 91 µs |
|---|---|---|---|---|---|
| 2048 | 4.19 MB | 27 µs | 154.5 | 130.5 | 35.5 |
| 4096 | 16.78 MB | 103 µs | 163.6 | 156.0 | 86.7 |
| 8192 | 67.11 MB | 398 µs | 168.5 | 166.4 | 137.2 |

### 7.5 Routes 1–5, beaten or critiqued with arithmetic
1. **Route 1 (this design):** ceiling min(180, 8·L·64/66, 8·16 KiB/(236.8 ns + c_mma)) → with
   L ≥ 21.8 and c_mma ≤ 491 ns the memory system is the wall at 168.5–174.5. The vendor library's
   quadratic control cost is replaced by 512 calls × O(c_mma) = linear in K·N.
2. **Route 2 (W4 dequant):** 2× the token rate of Route 1 iff D ≥ 43.5 and L ≥ 86.9 (then
   163.6 W4-GB/s); equals Route 1's token rate at D = 21.8 or L = 43.5; below it otherwise (§5).
3. **Route 3 (i8×i8):** same bytes, same fragments, same 168; exact i32 accumulation
   (127²·8192 = 1.3e8 < 2³¹), dequant y = sx[m]·s[n]·C in the same 1024-lane epilogue plus one (**audit, #22 / #29:** Duplicate(sx[r]) + binary Mul, or v_r = sx[r]·s[n]
   built once per launch — a unary Muls is a silent no-op, invisible at sx = 1; sx[0..m) read once under B7, never per row)
   per-row scalar. Only differences: unverified dtype combo swapped, and no f16→i8 vector
   cast in ISA.md for on-device per-token quantization (benchmark may host-pack; integration
   needs a cast to be found, else Route 1b). Ranked #2 because its integration gap is a
   missing feature, not a rate.
4. **Route 4 (vector-only):** per weight at m=1: cast + Mul + Add = 3 lane-ops → 43.2 G/3 =
   14.4 G weights/s/core = 115.2 GB/s/die ceiling before reductions and ≤1024-lane call
   overhead, measured 70–78; cost grows ∝ m (m=16 → 4.4–4.9 GB/s). Not flat, below target.
5. **Route 5:** 60 ns·(K/64)² = 983 µs per tile at K=8192; 4.2 GB/s. Dead.

---

## 8. Experiment ladder (ordered; every one has an observable failure)

Common harness rules: every destination is pre-filled with a sentinel; every data path is
exercised with two different sources through the same destination address (differencing);
every numeric check uses integer-valued inputs so f32 results are exact (|b| ≤ 15, column sums
< 2²⁴); every pass criterion is evaluated on ≥ 20 reps and must be bit-identical across reps.
Timing is recorded but never used as a pass criterion.

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **E0** | T_launch: does the 91 µs floor serialize back-to-back launches? | kernel k writes its index k to DDR slot k; launch 1, 10, 100 queued | missing/duplicated slot indices = launches dropped; T(100) ≈ 100×91 µs = serialized, ≈ 91 + 100×small = pipelined | whether wall-clock ≈ in-kernel; fusion requirements (§6) |
| **E1** | the whole Route-1 chain: DDR→S1 copy, S1→L0 loader, f16×i8 MMA numerics, initVal polarity, B fractal geometry, A fractal (P), row-0 drain | A = all-ones f16 [16, 128] (2 k-chunks), B = i8 tile pair with b[k,n] = ((7k+13n) mod 31) − 15 (**audit, #21:** period 31 < 128 rows and 256 columns, and b[k + 64, n] = b[k, n + 13] — an A-pack chunk transposition reads as a B column permutation; use seeded pseudo-random integers) packed per §3.1; expect C[0,n] = Σ_k b[k,n] exactly. Variants: (i) swap B for a second pattern at the same addresses (differencing), (ii) A row 0 = one-hot e_j → C[0,n] must equal b[j,n] (A-pack probe for every j in 0..127), (iii) rows 1..15 of C must be 0, (iv) repeat with i8×i8 and f16×f16 (**audit, #19:** the f16 two-chunk variant fails by #19 — one k = 128 call, or a fresh C per chunk + a host sum), (v) pack probe: the same logical tile packed under G1c, G1a, G1b and G2 (§3.1) through the same S1 address — exactly one packing reproduces the column sums (the four give pairwise different sums for this b; under G2 only the 32 KiB packing can) | all-zero → a no-op somewhere (bisect with E5/E3); only chunk-1 sums → initVal inverted; column permutation → B geometry wrong; e_j lands on the wrong k → A geometry wrong; wrong magnitudes → dtype combo broken | go/no-go for f16×i8 vs Route 3 vs 1b; the tile geometry and with it Route 1 vs 1b; the A pack; E1-sweep below |
| **E1-sweep** | legal MMA call shapes and c_mma | same oracle, n ∈ {16,64,256,512,1024}, k ∈ {16,64,128,256}; 10k calls per shape, each content-checked | wrong sums at a shape = illegal shape (never "fast"); c_mma = intercept of time vs fragment count across passing shapes | tile size (§2), issue-slack budget (§1.3) |
| **E2** | **L — the loader rate** | S1 holds tiles X and Y (ΣX ≠ ΣY per column) at the same slot alternately; 10k L0LOADs of 16 KiB into alternating L0B slots, each followed by MMA(ones, tile, k=64) accumulating into one C; expected C[0,n] = n_X·ΣX[n] + n_Y·ΣY[n] (≤ 9.6e6, exact in f32) | any skipped or stale load changes the total → caught; MMA at 236.8 ns/tile cannot mask L below 69.2 GB/s, and L ≥ 69 is all we need to know above that | the branch in §7.3; ranking in §0 |
| **E3** | DDR→L0 direct (L0LOAD_GM) | E2 with the source in DDR; also one 65 KiB load | silent no-op → total unchanged from sentinel; 65 KiB faulting or not is observable by watchdog | removes S1 staging if it works at ≥ 21.7 GB/s/core |
| **E4** | L0A, L0B, L0C sizes | place tile Y at L0B offset 0 and tile X at offset S−16 KiB for S ∈ {32,64,128,256 KiB}; MMA from both; same for L0A with A blocks, for L0C with C slabs at high offsets then drained | aliasing shows X's sum where Y's is expected (differencing); out-of-range faults by watchdog | N_slab, L0B tile size, scheme P need |
| **E5** | every copy position pair used: DDR→S1, DDR→US, US→S1, US→DDR (1D and 2D), L0C→US staged read | write X then Y through the same destination, read back via a path already proven | unchanged = silent no-op (errata 1); partial = size/stride bug | which copy variants the pipeline may use (§3.3 scatter) |
| **E6** | L0C drain rate and the row-0 2D read | drain 64 KiB slabs with known content 1000× | content mismatch; islands across reps | scheme P viability (≥ 10 GB/s/core), Route 5(d) viability (≥ 50) |
| **E7** | barrier sufficiency (errata 8) and S1 size | full pipeline on random x, W at 8192², 20 reps per config; ≥ 20 reps bit-identical and relerr ≤ 1e-3 vs host f32; positive control with B5 removed; S1 size by E4-style aliasing with 64 KiB copies at high offsets | any rep-to-rep bit difference = missing barrier; the positive control must show islands or the detector is blind | ship/no-ship; A-residency option |
| **E8** | dequant instruction: numerics, group semantics (V1 vector scale / V2 scalar + loader transpose), rate D | i4 pattern with power-of-two scales and integer offsets → exact f16 expected values; 8 Mi elements, output content-compared on host | wrong/unchanged outputs; V1 or V2 producing the wrong column mapping in a follow-on E1-style MMA oracle | W4 go/no-go and the decision rule in §5 |
| **E9** | epilogue vector ops: Mul 1024 lanes, Cast f32→f16 rounding (errata 6), 1025-lane truncation (errata 3; **audit:** OBSOLESCENT — corrected #3; probe f32 Mul and Cast widths in isolation instead) | Mul with known s; cast of 1 + 2⁻¹¹ (a round-to-nearest-even tie) and of 65505 (saturation); a 1025-lane call | truncated lanes keep the sentinel; a no-op rounding mode returns the input bits | epilogue correctness |
| **E10** | the 40% number | 100 queued launches of 8192² at m ∈ {1,16,32,64}, random x per launch (so outputs differ per launch — a stuck kernel is visible), every output checked vs host f32 (relerr ≤ 1e-3), bit-identical across 20 reps of the same x | any failed check voids the timing | reported m=1 GB/s, both in-kernel-equivalent (floor from E0) and wall |

Order: E0, E1 (+sweep), E2, E3, E5, E4, E6, E7, E9, E10, then E8 for W4. E1 is first because
its oracle proves the whole chain at once and any failure bisects into E3/E5.

---

## 9. Risk register with fallbacks

| Risk | Trigger (experiment) | Impact | Fallback |
|---|---|---|---|
| f16×i8 numerically wrong | E1 | Route 1 dead | Route 3 (i8×i8, same bytes, same 168; host-quantized A for the benchmark); if i8×i8 also fails → Route 1b (vector i8→f16 cast, 52% vector busy, needs L ≥ 43.4) |
| L ≤ 21.7 GB/s/core (below 173.8/8 = 21.725) | E2 | loader-bound: 8·L·64/66 | L ≥ 15.5 still meets 120; below that → E3 DDR→L0 direct; if that is a no-op → nothing MMA-based reaches target; report the vector floor (70–78) |
| L0LOAD_GM silent no-op | E3 | none for Route 1 (S1 staging is the baseline) | — |
| L0C < 64 KiB | E4 | more slabs: 32 KiB → 2 slabs at m=16 but A (256 KiB) stays resident in S1 → still 168.5 (163.6 only if S1 cannot hold it — round 1 said 164); m=64 needs n=128 tiles → 8 slabs, A re-streamed 8× → 86.9 | scheme P for m ≥ 32; A resident in S1 for m ≤ 32 |
| L0B < 32 KiB | E4 | single-buffered L0B: loader and MMA serialize per tile: 16 KiB/L + 236.8 ns; at L = 50 → 564.4 ns/tile = 29.0 GB/s/core, still ≥ 21.8 | 8 KiB tiles (n=128) to double-buffer in 16 KiB |
| S1 < 768 KiB | E7 | lose A residency at m=32 (163.6 → 154.5); 288 KiB rings still fit at 512 KiB | shrink B ring to 2 × 64 KiB if S1 < 320 KiB |
| MMA max shape < (256,64) | E1-sweep | more calls; at 16×16×16 only, 32768·mt calls and 11.3 ns slack each | c_mma decides; if > slack, MMA-issue-bound at 8·256 B/(3.7 ns + c_mma) |
| c_mma > 491 ns at (256,64) | E1-sweep | MMA-issue-bound below the roof | larger legal tiles (slack 1.96 µs at n=1024) |
| 91 µs floor serializes launches | E0 | 2048² standalone capped at 35.5 GB/s wall; 8192² at 137.2 | fuse QKV / gate-up; report in-kernel and wall separately |
| Copy-in per-call issue latency | E0/E7 timing | hidden by the 4-deep ring up to ~1.46 µs per call (373 µs / 256 calls) | 2D copies covering 2 chunks if legal (E5) — still ≤ 64 KiB each |
| Missing barrier (errata 8) | E7 | silent corruption | the positive control proves the detector; add barriers until 20/20 bit-identical |
| A fractal differs from §3.2 | E1 one-hot | wrong results | host packer + epilogue scatter updated from the probe map |
| i8 tile geometry is G2 (2 B/elem) rather than dense G1 | E1 pack probe | Route 1 streams 130 MiB → 85.6 GB/s | Route 1b: dense i8 in DDR, vector cast (48.8% busy), f16×f16 MMA; 168.5 if L ≥ 43.5, target iff L ≥ 31.0 |
| Dequant slow / vector-scale unsupported | E8 | W4 below W8 token rate | W4 → W8 (§5 decision rule) |
| f32→f16 rounding no-op (errata 6) | E9 | ~1e-3 bias on y | select a verified rounding mode or truncate deliberately and document |
| No f16→i8 cast (Route 3 integration) | ISA | on-device per-token quant impossible | stay on Route 1; Route 3 benchmark-only |

---

## 10. Measurement wishlist (ranked by what it unlocks)

1. **S1→L0 loader rate L (E2).** Decides DDR-bound vs loader-bound (168.5 vs 8·L·64/66), the
   entire route ranking, and whether W4 (needs 2× the bytes through it) is even on the table.
2. **f16×i8 numeric correctness + initVal polarity (E1).** One oracle run; without it nothing
   downstream is trustworthy. Also yields the A-operand fractal order.
3. **L0C size (E4).** 64 KiB → m=64 at 115.9; 128 KiB → 2 slabs → 138.4–139.0; ≥ 256 KiB →
   single slab → 138.4–154.5 at every m. Also sets N_slab for every N.
4. **MMA legal shapes + issue cost c_mma (E1-sweep).** Converts the 491 ns slack from
   assumption to margin; larger tiles cut calls 4×.
5. **DDR→L0 direct (E3).** If real at ≥ 21.7 GB/s/core it deletes the S1 stage, the loader
   question, and 256 KiB of S1.
6. **Dedicated dequant rate D and group semantics (E8).** Unlocks W4 = up to 2× tokens/s.
7. **L0C drain rate (E6).** Unlocks scheme P (m=64 → 138.4–154.5) and Route 5(d).
8. **S1 size and L0B size (E4/E7).** A residency at m=32 (+9.1 GB/s), 32 KiB tiles.
9. **Launch floor behaviour (E0).** Whether 2048² matmuls can ever show ≥ 120 on the wall
   clock, and how many matmuls to fuse per launch.
10. **Copy-in per-call issue latency.** Only matters if > 1.46 µs; sizes the ring depth.
