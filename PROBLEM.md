# PROBLEM — design the best possible execution layer

You are a performance architect. HW-MAP.md and ISA.md describe a real
inference accelerator with measured numbers and verified silicon errata.
Design the optimal execution layer for the workload below. The errata are
hard constraints, not documentation noise — a design that trips errata #1
(silent no-ops) or #8 (missing barriers) produces plausible-looking wrong
answers, and on this silicon that is the normal failure mode, not the
exception.

## Workload

LLM decode layers on one die (8 cores):

```
y[m, n] = s[n] · Σ_k x[m, k] · W[k, n]        m ∈ {1..64}, K = N ∈ {2048..8192}
```

- Weights: **W8** (int8, per-output-channel scale s[n]) or **W4** (int4 +
  per-group offset/scale, dequantized to f16 or kept for i8 routes).
  Weights are **static** — offline repacking is free. Activations arrive
  on-device from the previous layer (on-device repack cost counts for
  integration; the benchmark phase may assume host-packed A).
- M profile: m=1 is the decode step; m=16 is batched speculative
  verification; the m=1..64 curve should be **flat** (extra rows ride under
  the weight stream — the measured f16 matmul already shows 144–148 GB/s flat
  from M=16..128, so the memory system permits it).

## Targets (per die)

- **≥120 GB/s effective weight-byte rate at m=1** (bytes = K·N·(W8:1|W4:0.5));
  the memory roof is 173.8 with a demonstrated 180 aggregate into staging.
- Flat m=1..64 curve.
- Numerics: f32 accumulation; relerr ≤1e-3 class acceptable (per-token i8
  activation quantization is an allowed route at that accuracy).

## Routes on the table (beat or critique with arithmetic)

1. Host-packed i8 → S1 (180 agg) → loader → **f16×i8 MMA** — current main
   line; ceiling = min(180, loader, MMA issue).
2. W4 → dedicated dequant instr → f16 fractal arrange → f16×f16 MMA.
3. Per-token i8 activations × i8 weights → i32 C → dequant in epilogue.
4. Vector-only (the floor to beat): measured 70–78 GB/s W8, 22 GB/s W4,
   vector wall ~40 lanes/cycle caps dequant-pass designs.
5. Vendor GEMM library: 4.2 GB/s, quadratic control path — dead, listed for
   completeness.

## Deliverables (numbered, in this order)

1. **Loop nest + tiling**: exact MMA shapes (m, n, k) with the issue-count
   arithmetic; k-outer vs n-outer decision and why (A-operand residency vs
   C-slab residency vs weight-stream sequentiality).
2. **Buffer budget table**: every operand/queue/staging buffer vs the
   hierarchy sizes, with the double-buffering depths chosen and why.
3. **Byte-level layout specs**: weight pack order (the verified fragment
   geometry F=[N/16][K][16], i8 32 B blocks) incl. the visit order the loop
   implies; A pack; C drain path.
4. **Pipeline + sync plan**: which engine does what when; every cross-engine
   boundary and its barrier; where nondeterminism could enter (errata #8) and
   how the design suppresses it.
5. **W4 strategy**: dedicated dequant vs vector arrange vs f16 round-trip —
   cost each in measured units (the dequant instruction rate is UNMEASURED;
   carry both branches and design the experiment that settles it).
6. **Cross-core partitioning**: 8 cores over (N, K, M); what shares the DDR
   roof; expected aggregate from the per-core design.
7. **Predicted performance with the arithmetic shown**: per-stage occupancy
   vs the 173.8/180 roofs, the m=1 and m=16 numbers, and the honest ceiling
   of your design. If the loader rate is the open risk, show the two branches
   (loader ≥69 GB/s/core vs loader-bound).
8. **Experiment ladder**: each assumption → cheapest decisive silicon
   experiment, ordered; every experiment must have an observable failure
   mode (differencing/oracle/pass-rate, never timing alone).
9. **Risk register** with fallbacks (e.g., f16×i8 oracle fails → i8×i8 route;
   loader slow → ...; L0C smaller than 64 KB → ...).
10. **Measurement wishlist**: ranked list of unknowns (loader rate, L0 sizes,
    DDR→L0 direct, MMA issue cost, dequant rate) and what each unlocks.

Be quantitative throughout: every claim about time or bandwidth derives from
a number in HW-MAP.md, shown in the derivation. Where you assume an
UNMEASURED or PRIOR quantity, say so and branch on it.
