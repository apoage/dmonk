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
| Vector unit | 128-lane reels, elementwise/tensor ops, casts | **~40 fp16 lanes/cycle/core sustained** (count-mode Mul/Add/Cast uniform — operand/issue bound, not FLOP bound) |
| Dedicated dequant | i4→f16 dequant instruction with interleaved packed input + per-group offset/scale | gate passes on this part; **rate UNMEASURED** |

Derived: matrix-unit time per 16³-MAC ≈ 3.7 ns/core (17.8 TFLOPS ÷ 8 cores).
Effective weight-read of a good f16 batched matmul (M=16..128): **144–148 GB/s/die,
flat** — extra rows ride under the weight stream. M=1..12 on the vendor slow path: 53.

## Per-core memory hierarchy

| Level | Size | Notes |
|---|---|---|
| DDR (shared/die) | 86 GB usable/die (LPDDR) | 173.8 GB/s measured |
| S1 (core SRAM, staging) | ~1 MB | PRIOR (a 256 KB resident strip + working tiles fit) |
| Vector SRAM (US) | ~256 KB/core | ≥208 KB evidenced by working allocations |
| L0A / L0B (matrix operand memories) | ≥ 32–64 KB each | PRIOR (library tiling evidence); exact UNMEASURED |
| L0C (matrix accumulator) | ≥ 64 KB (holds 16×1024 f32) | PRIOR (tiling evidence); exact UNMEASURED |

## Measured data-movement rates (per core unless stated)

| Path | Rate | Notes |
|---|---|---|
| DDR → vector SRAM | 173–177 GB/s **aggregate** | full streaming rate |
| DDR → S1 (plain copies, pre-packed layout) | **180 GB/s aggregate** (≈22.5/core) | DRAM-roof-bound; per-core slabs, 64 MiB working set |
| Vector SRAM → S1 (plain fill, 48–64 KB tiles) | **250–255 GB/s/core** | plateau; ≤32 KB tiles masked by a ~91 µs launch+queue floor |
| Grouped quant-GEMM, vendor op (MoE decode shape: 8 groups, 1 token/group, K=N=4096, i8 weights) | **24.6 GB/s** effective weight read, relerr 0 | measured — the floor any custom MoE kernel must beat by ~5× |
| S1 → L0A/L0B (loader) | **UNMEASURED** | the big open number; matrix unit needs ≥69 GB/s/core of B to stay fed |
| DDR → L0 direct load instructions | exist in ISA | **UNMEASURED on silicon** (may be a silent no-op — see errata) |
| "fractal-transform" copy (DDR→S1 with layout transform) | ~7 GB/s/core | **software** transform on this part — do not use on any hot path |

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

## Verified layout geometry (for matrix-operand packs)

Fragment layout for a [rows K, cols N] operand, silicon-verified positional:
**F = [N/16][K][16]** — outermost by 16-column groups, then K rows, innermost
16-element run. For i8 operands each innermost run is a 32 B block; block
(i, r) of a [Kb, 256] tile sits at byte offset **(i·Kb + r)·32**. Host-side
pre-packing to this order is free (weights are static); in-kernel transform
copies are the ~7 GB/s software path — never use them on a hot path.
