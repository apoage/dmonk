# HW-MAP — the device (sanitized, measurement-based)

Every number below was **measured on real silicon** unless marked PRIOR
(strong architectural inference) or UNMEASURED. The device is a production
inference accelerator card; nothing here is spec-sheet marketing.

## Card / die level

| Quantity | Value | Status |
|---|---|---|
| Dies per card | 2, each visible as one device to the host | measured |
| Host link (die 0) | 27.6 / 27.3 GB/s H2D/D2H | measured |
| Host link (die 1) | 13.9 / 19.0 (transits die 0) | measured |
| Die-to-die P2P | refused by runtime; D2D copy 10.7 GB/s r+w via host | measured |
| LPDDR streaming per die | **173.8 GB/s** (spec 204.8) | measured (512 MB fp16 stream) |
| Cores per die | 8 AI cores, user kernels run 1 block/core | measured |
| Core clock | 1.08 GHz pinned, no throttle under sustained load | measured |
| Power/thermal | 150 W TDP class; sustained all-core matrix load = 141 W card, 72/69 °C hotspot pair at mid fan curve; idle 41 W, 36 °C | measured |

## Per-core compute units

| Unit | Capability | Measured throughput |
|---|---|---|
| Matrix unit | native **16×16×16** MAC fragment; f16×f16→f32, i8×i8→i32, f16×i8→f32 | **17.8–26.6 TFLOPS/die** fp16 (n=8k/2k; flat over 8 s+, no throttle) |
| Vector unit | 128-lane reels, elementwise/tensor ops, casts | **~40 fp16 lanes/cycle/core sustained in kernel-mixed contexts** (count-mode Mul/Add/Cast uniform — operand/issue bound, not FLOP bound); **isolated chained-op rates ~5× higher — see the E22 table below** |
| Dedicated dequant | i4→f16 dequant instruction with interleaved packed input + per-group offset/scale | gate passes on this part; **rate UNMEASURED** |

Derived: matrix-unit time per 16³-MAC ≈ 3.7 ns/core (17.8 TFLOPS ÷ 8 cores).
Effective weight-read of a good f16 batched matmul (M=16..128): **144–148 GB/s/die,
flat** — extra rows ride under the weight stream. M=1..12 on the vendor slow path: 53.

## E22 vector op set (measured 2026-11-05 — the softmax op menu, U resolved)

| Op | Verdict | Rate (1024-lane count-mode, dependency-chained) |
|---|---|---|
| exp (f16) | **EXISTS** (hardware exp; bitwise-matches host on the softmax domain x ≤ 0; overflows f16 above x = 11.1) | **272.8 ns/call → c_exp ≈ 11.5 lane-equiv/elem** |
| exp (f32) | **EXISTS** (maxRel 6.3e-08 vs host) | ≈ 11.4 lane-equiv/elem |
| reduce-max (f16/f32) | **EXISTS** (planted max verified at moved positions; f16 result = value in lane 0, lane 1 = index-class) | f16 181.9 ns/call (≈ 0.74 lane-equiv/score), f32 251.4 ns — **beats the 6-op elementwise max tree (6 × 46.4 = 278 ns chained)** |
| And (bitwise) | **int16/uint16 only**; **int32 And ABSENT** — the f32-tree And route is closed, the f16-tree route is open | And<int16> 45.9 ns/call, bitwise-exact |
| Mul/Add f32 vs f16 | ρ32 = **1.37** chained per-op (Mul 63.5 / Add 63.7 f32 vs 46.4 f16 ns) — between the modeled 1 and 2 | f16 Mul 46.4 ns/call chained |
| scalar loop | **σ_s = 19.9 ns per compare** (5.1 µs per 256-read tail) — 10× the 2 ns model, below the 47 ns bind line | — |

**Verdicts:** c_exp = 11.5 ≤ 21 → **native exp beats the 22-op polynomial** and
clears all four native-exp thresholds (56/51/24/19) → the worst vector corner
(851 µs @32k) **collapses to the stream branch**; the "ISA-as-written" (poly exp,
tree max) table row is not reachable on this part — both the native exp and the
native reduce-max exist. Caveats: chained rates are latency-bound upper bounds on
cost (conservative); the exp chain reaches inf operands after ~4 iterations
(exp(inf) = inf, timing unaffected as measured). The ~40 lanes/cycle wall above
was measured in kernel-mixed contexts; isolated vector ops run faster.

## E21 gather rate G(P) (measured 2026-11-05 — U resolved)

The production B path (DDR→L0B direct load, full barrier per 32 KiB call tile,
one (16,16,128) MMA per 16-n-chunk into an accumulating C region) driven by a
US-staged page table over 64 MiB per-core arenas, sequential vs shuffled visit
order, page-weight multiset hash **verified 20/20 reps exact, both orders, every
size**:

| P | G seq (agg) | G shuffled (agg) | per-page seq/shuf |
|---|---|---|---|
| 16 KiB | 165.2 GB/s | 153.8 GB/s | 793 / 852 ns |
| 64 KiB | 169.0 GB/s | **167.0 GB/s** | 3101 / 3140 ns |
| 256 KiB | 169.2 GB/s | 169.2 GB/s | 12391 / 12394 ns |

**c_pg(64 KiB, shuffled − sequential) = 38 ns/page.** CORRECTED (P3 round-3
re-read — the original verdict below read the inequality backwards): the flip
rule is attention-bound iff G <= 167.7, and shuffled G at 64 KiB is 167.0 <=
167.7, so **the MoE-128k cell IS attention-bound at 64 KiB pages (by 0.8 %)
and weights-bound at 256 KiB (by 0.5 %)** — page guidance: 256 KiB default,
64 KiB where the allocator forces it (-1.3 %), never 16 KiB (-9.1 %).
**MoE-32k (≤ 41.9) and dense (≤ 7.3/29.4) never flip;
16 KiB pages DO flip MoE-128k attention-bound** (153.8 ≤ 167.7); both 1M cells
attention-bound at every G (unchanged). Runtime page-size guidance: **≥ 64 KiB,
prefer 256 KiB; the usual 4–16 KiB serving page is gather-bound for MoE-128k.**
Caveat: shuffle is random-within-contiguous-per-core-arena — a real scattered KV
cache shows a higher c_pg (38 ns is a lower bound). The per-page numbers include
the page-table read (kept in US) and the per-tile barrier+MMA.
Structure note (settled by the attention session): E21 accumulated per
n-chunk across ALL tiles — at 16 KiB pages that is a spacing-8, depth-8192
same-destination i8 chain, exact 20/20: the existence proof that deep
low-spacing i8 chains with per-group barriers are safe (f16 does NOT
inherit this — erratum #19).

## Per-core memory hierarchy

| Level | Size | Notes |
|---|---|---|
| DDR (shared/die) | 86 GB usable/die (LPDDR) | 173.8 GB/s measured |
| S1 (core SRAM, staging) | ~1 MB | PRIOR (a 256 KB resident strip + working tiles fit) |
| Vector SRAM (US) | ~256 KB/core | ≥208 KB evidenced by working allocations |
| L0A / L0B (matrix operand memories) | **64 KB each** | measured (raw-MMA probes) |
| L0C (matrix accumulator) | **256 KB** (whole 16×1024 f32 slab resident) | measured |

## Measured data-movement rates (per core unless stated)

| Path | Rate | Notes |
|---|---|---|
| DDR → vector SRAM | 173–177 GB/s **aggregate** | full streaming rate |
| DDR → S1 (plain copies, pre-packed layout) | **180 GB/s aggregate** (≈22.5/core) | DRAM-roof-bound; per-core slabs, 64 MiB working set |
| **DDR → S1 bulk A staging (ONE pack per launch, 2×32 KiB legs, feeding loader-only S1→L0A lifts)** | **measured — production route** (expert-GEMM kernel) | the pattern ALTERNATIVES.md's S1/S2 rows assume; A stays S1-resident for the whole launch |
| Vector SRAM → S1 (plain fill, 48–64 KB tiles) | **250–255 GB/s/core** | plateau; ≤32 KB tiles masked by a ~91 µs launch+queue floor |
| Grouped quant-GEMM, vendor op (MoE decode shape: 8 groups, 1 token/group, K=N=4096, i8 weights) | **24.6 GB/s** effective weight read, relerr 0 | measured — the floor any custom MoE kernel must beat by ~5× |
| S1 → L0A/L0B (loader) | **26.5 GB/s/core strict-serial** | measured — superseded in production by the direct path below |
| **DDR → L0B direct load (bypassing S1 entirely)** | **181.3 GB/s aggregate** | measured, byte-exact — now the production B path (beats the S1-staged copy leg at 180.4); with one full barrier per tile and two 32 KiB parity halves the whole kernel runs **174.6 GB/s m=1, flat m=1..16, fp64 20/20** |
| DDR → L0 direct load instructions | exist in ISA | **UNMEASURED on silicon** (may be a silent no-op — see errata) |
| MMA issue cost | **15 ns/call at (m,n,k)=(16,16,128)** | measured — 4096 calls/core = 61 µs vs 487 µs stream = 12.5% occupancy |
| Full W8 decode kernel (i8×i8 route, per-token-quantized A) | **174.6 GB/s aggregate, flat m=1..16** (serial fallback 138.9; m>=24 stays serial: 81/59/43 — direct-load multi-strip wedge unresolved) | measured, fp64 20/20 — the 173.8 "roof" was a read+write roof; pure read streams sustain ~181 |
| Vector i4→f16 unpack (5-pass) | **~5.3 GB/s/core = 42 aggregate int4-effective** | measured — there is NO i4→f16 hardware path on this part (see errata #12); vector dequant for W4 is dead vs 120 |
| **f16→i8 activation quantization ON-DEVICE** (the production-chain pass) | **measured, works: 43.7 µs at m=1, K=8192 (+12.2% over host-packed A)**; end-to-end fp64-exact ×20 (relerr 1.07e-7); integrated kernel 135.5 GB/s f32-in/f32-out | measured (production integration season) — the cast is **rint-half-even, saturating at ±127** (which conveniently ENFORCES the [−127,127] quantizer clamp the MoE overflow bound requires); one-time weight repack at load = 0.82 s/GB |
| "fractal-transform" copy (DDR→S1 with layout transform) | ~7 GB/s/core | **software** transform on this part — do not use on any hot path |
| L0C → US window drain (copy-out 1 KB chunks, queue-fenced) | **152.8 / 222.3 / 260.3 / 285.5 GB/s/core at mt = 1..4** | measured — **9×–45× above the 3.41/6.83/12.28/16.37 hide thresholds: the drain is HIDDEN at every mt**, content-checked exact |
| **US → US strided copy (post-PV row extraction, plain strided bytes)** | **works — measured REAL** (production expert-GEMM kernel epilogue, differencing-verified) | no layout transform (the ~7 GB/s transform-copy path is a different route); stride math must follow the fragment-order L0C → US drain below |
| **Gather at the attention kernel's own choreography (fresh-path tile-mix loop)** | **~138 GB/s aggregate, page-size-insensitive** (138.3 / 138.7 / 138.0 at 256 / 128 / 64 KiB) | 18 % under the E21 169 basis — barrier density of the 2-kind diagnostic loop; the production loop halves barriers per byte; c_pg ≈ 0 at ≥ 64 KiB confirmed |
| **i32 accumulator overflow semantics** | **SILENT SATURATION at 2³¹−1** (not wrap) | measured: 127² chains exact to 2,147,092,480 (99.98 % of 2³¹); −128² chains hitting 2³¹ exactly clamp at 2,147,483,647 — **the [−127,127] quantizer clamp is REQUIRED; U_max = 32 MoE-shape chains are exact (bound HOLDS)**; L0C has no zero-init (pre-accumulation reads are nondeterministic → drain-before-accumulate required) |
| **Host bounce λ (die→host→die, 4 KiB sync legs)** | **12.2 / 12.1 µs per direction; bounce 23.8–24.6 µs; unchanged under die-0 saturating D2D load** | measured — 7.6× below the 91 µs launch-floor-class anchor, inside the 10/500 bracket; **bounce share of any step ≈ 0.1 % — negligible for the planner** |

## Silicon errata (all verified live — treat as hard constraints)

1. **Unsupported instruction variants compile to silent NO-OPS.** "Not
   supported" reporting is compiled out in device builds. A copy or load that
   the toolchain doesn't implement executes as nothing — no fault, no warning.
   Every data path must be proven by differencing tests (same destination
   address, different source content, observable result must change).
2. **Single copy > 64 KB faults** (core watchdog timeout). Slice all copies.
3. **Count-mode vector ops process ≤ 1024 lanes per call** — larger calls
   silently truncate.
4. Some bitwise shifts on 16-bit integers are **silent no-ops**.
5. **f16 accumulation saturates at 65504** — never carry growing factors
   through long f16 sums.
6. No i16→i32 vector cast exists. Some float rounding modes silently no-op.
7. **No S1/L0 → DDR direct copy** in vector builds — stage through vector SRAM.
8. Hand-managed cross-engine readback **without explicit barriers** shows
   nondeterministic small (~512 B) corrupted islands, mostly-clean reps.
   One clean verification rep is not evidence; use ≥20-rep pass rates.
9. Buffer-queue depth must equal declared buffer count or the core hangs.
10. Vendor GEMM template library: **~4.2 GB/s effective** at K=8192, m=1 —
    per-tile control overhead grows **quadratically with K** (≈60 ns·(K/64)²)
    while its own input leg runs 180 GB/s. The library control path is the
    wall, not the memory system. Hand-rolled pipelines are the only route.
11. Multi-die serving (measured): a serving runtime may place consecutive
    layers on different dies (**layer-split works**, +2% decode at 2 dies —
    dies alternate, no concurrent streaming); **tensor-split of a single op
    across dies is unsupported** for this workload class (runtime fault).
    All cross-die exchanges bounce through the host.
12. **No i4→f16 conversion path exists anywhere on this part** (measured),
    and the **i4×i4→i32 matrix tuple is silicon-dead** (in the calibration
    table and compiles, but produces all-zero C via staged operands and
    dead-waits on direct operands): **W4 must ride as int8** — host-side
    int4→int8 expansion at load, doubling weight memory; there is no
    on-the-fly route that sustains ≥120. Plan fleet memory accordingly.
    Original: no i4→f16 conversion path exists (measured):
    the dedicated dequant instruction's gate covers only i8 inputs here; the
    vector cast table has only the quantize direction; the dequantizing copy
    modes are compiled-out no-ops; there is no u8 bitwise And. All i4
    unpacking is multi-pass vector work (~10 lane-equivalents per i4 byte,
    ≈83% of the lane wall → ~42 GB/s aggregate ceiling). W4 ≥120 therefore
    requires an **i4×i4→i32 matrix route** (dtype tuple present in the
    matrix calibration table, unverified on silicon) or W4 is not viable.
13. **f16×i8→f32 does NOT exist at the raw matrix level** — the library
    accepted it once but the hardware calibration table has no such tuple;
    the realized W8 route is **i8×i8→i32 with per-token-quantized A**
    (activation scale folded into the epilogue). Assumptions of an f16×i8
    route are library-level artifacts, not silicon.
15. **Production-chain landmines (integration season, all measured)**: raw
    copy-out reads issued right after async vector math ship PRE-FOLD values
    — the queue mechanics are the fence, in both directions; the first
    cold-pipe producer handshake can deliver zeros (warm it); threads must
    each set their device context or device-memory ops segfault; no i8
    broadcast op (build constants by cast); per-tile scalar divisions in a
    loop cost real issue latency (~10 GB/s class) — hoist to multiplies.
14. **Choreography landmines (raw pipelines, all live-probed)**: the
    copy-in→matrix consumer flag is INERT (stale reads — catch by
    differencing); some cross-engine handshakes fault after direct loads;
    consecutive same-pair different-ID producer flags are LEGAL (vendor
    ping-pong constructor does exactly this — corrects an earlier note);
    **the full barrier is the ONLY working fence for direct GM loads**;
    queue-based staging into L1 is nondeterministically ordered (root of
    the "never stabilizes" verification class) — raw buffer staging +
    full barriers. m=64 across the full 256 KB accumulator WORKS (the
    earlier "exactly-full" hang was an artifact of a 4-sweep structure).
    k=64 matrix calls are nondeterministically wrong (32/128 exact).
16. **Back-to-back same-destination MMA accumulate chains lose updates
    nondeterministically** (probe-pack season, live): a 1024-deep isBias chain
    into one L0C chunk kept ~50 % of its accumulations in one run and ~99 % in
    the next; with same-chunk calls spaced 32 matrix calls apart every value is
    exact, and the production chains (≤ 64 deep, operand lifts interleaved) are
    the safe class. Never chain > 64 same-dst matrix calls without interleaving.
17. **Vector-rate loops are silently optimized away**: a count-mode loop into an
    unconsumed buffer is deleted entire (launch runs at the empty floor);
    independent identical ops into a queue tensor collapse to one op. Rate
    loops need a dependency chain plus a periodic scalar read-back, and the
    number must be validated by an reps-scaling (8×) check before quoting.
  Also: a verify variant driven by `reps` must force ≥ 1 work block when
   reps = 0 (a zero-iteration loop silently returns lane 0).
18. **The matrix call's C destination silently drops view/slice offsets**
    (a destination addressed at a chunk offset lands in chunk 0 — the
    earlier "A offsets ignored, B honored" asymmetry extends to the C
    side). Address every L0 destination by explicit byte-offset tensor
    construction, never by view slicing.
19. **f16 accumulation into one C chunk corrupts across ANY full pipe
    barrier or A-operand re-lift** — broken at ≥ 2 accumulations, even
    with interleave ≥ 16; a barrier-flag dance alone (no loads) breaks it.
    The i8 tuple tolerates the same pattern (the E21 probe: spacing-8,
    per-tile barriers, depth 8192, exact 20/20). **Consequence: f16
    accumulate chains do not exist on this part** — fresh chunk sets + a
    vector-side merge instead (the accumulator budget fits per-group fresh
    sets), and any mechanism requiring cross-barrier f16 accumulation
    (e.g. the ±Q difference branch of the attention drift design) is
    unimplementable on this tuple; fresh-per-block accumulation is
    drift-free by construction.
20. **Vector SRAM → S1 A-slot plain copy is WRONG** (data changes but ≠
    source; 1-of-3 probe variants exact — cold-pipe-class). An A operand
    built in vector SRAM must ride a DDR bounce (vector out → DDR scratch
    → the proven DDR → S1 staging → loader lift).
21. **Host reference patterns alias tokens**: mod-N / short-period planted
    patterns make distinct tokens share values, hiding transposition and
    mapping bugs (a call-tile transposition looked like a clean one-token
    shift). Use prime periods > L for any token-mapped verification data.

## Concurrency & runtime behavior (all measured, season h)

- **Continuous batching pipelines sequences**: N concurrent decode
  sequences share ONE compute graph per step (batched rows ride the
  kernel's flat m<=16 region); aggregate throughput 1.00 / 1.53 / 2.38 /
  3.26x at 1/2/4/8 clients (queued control = exactly 1.00x). Utilization
  gaps, not serialization, cap the curve. **Batching == pipelining for
  weight-bound decode** (weights read once per step regardless of rows).
- **Two instances on disjoint dies run at FULL solo speed concurrently**
  (1.99x aggregate, both dies 89% busy) — no driver-level cross-process
  serialization on separate devices. The instance-parallelism partition
  (ALTERNATIVES.md) is mechanically unlocked.
- Layer-split does NOT multiply single-sequence decode: +1.4% only (a
  single sequence's chain is a serial dependency). Multi-stream throughput
  comes from concurrency or spec-decode, not layer placement.
- The STOCK vendor op path aborts on multi-sequence decode (the known
  non-contiguous-output bug extends to every multi-slot step) — custom
  kernels are mandatory for any concurrent serving.
- Decode byte accounting at 100% custom-kernel coverage: GEMM 59.3 ms +
  non-GEMM 7.7 ms vs 67 ms measured (11.5% residual); at m=8 the step
  reads the SAME weight bytes (weights-once dividend byte-exact); the
  per-sequence non-GEMM overhead erodes ~5% at fleet model scale.
- Lazy softmax (fixed per-row shift + overflow guard): licensed for
  qk-normalized models (guard trips 0.087-0.22% of steps, non-vacuous);
  DEAD without qk-norm (scores reach ~1667, drift ~560). Check the target
  model's normalization class first. **Measured (attention kernel session
  1): the guard + per-trip recompute is REQUIRED, not advisory — without
  the recompute exactly the predicted 9/8192 lanes per tripped block come
  out wrong.**
- **Same-dst MMA chains: SPACING is the binding variable, not depth** —
  interleave >= 16 is exact at every depth 64..1024; spacing-0 corrupts
  bidirectionally at depth >= 256 (filler results leak into chain chunks).
  Rule: interleave >= 16 licenses any depth; never back-to-back same-dst.
- Power-sensor witness caveat: card idles ~65 W with a model resident
  (vs ~41 W cold) — the sensor discriminates per-DIE process activity,
  not per-sequence batching; use throughput for batching verdicts.

## Verified layout geometry (for matrix-operand packs)

**SETTLED BY MEASUREMENT (raw-MMA probes):** the i8 L0B fragment is
**[16 N-columns × 32 K-rows], column-major** — element (k, n) of a fragment
sits at byte **n·32 + k**; fragments are laid out n-c-major across the tile.
This supersedes the G1a/G1b/G1c/G2 hypothesis family (DESIGN.md §3.1): none
of the four matched exactly; the probes settled the real one. Host-side
pre-packing to this order is free (weights are static); in-kernel transform
copies are the ~7 GB/s software path — never use them on a hot path.

**SETTLED BY MEASUREMENT (f16 sweep, same session):** the f16 B fragment is
**[16 N-columns × 16 K-rows], column-major, k-fragment-major**; the f16 A
operand is **[16 M-rows × 16 K-rows], m-row-major**; the f32 C-chunk
nesting of the f16×f16 tuple is **[16m][16n] per 1-KiB drain chunk**
(E23(v)) — and the drained scores-chunk nesting equals the A-fragment
nesting (the zero-copy P·V premise), verified on the full pipeline:
**2,097,152 score elements exact (bad 0) at L = 32k**.

**MMA shape constraints (measured):** per-call **n caps at 16** — n=256
silently computes only columns 0–15 (the (16,256,64) design tile is
impossible; the working loop is a 16-chunk (16,16,128) sequence). k=32 and
k=128 are correct; **k=64 is nondeterministically wrong** (32/128 reps
exact — erratum #14) — **an i8×i8-tuple-ONLY anomaly: the f16×f16 sweep
(128 reps/shape, one-hot k-probes covering every k position, all 8 cores
redundant) is EXACT at every k ∈ {16,32,64,128}** — so the anomaly is
neither fragment-count- nor element-count-based (i8-only; open, cause not
isolated). f16 shapes are unrestricted. The align/init flags in the MMA parameter struct are
ignored on this part.
