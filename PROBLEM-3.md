# PROBLEM-3 — decode attention over the KV cache (gather–softmax–reduce)

Same rules of engagement as PROBLEM.md/PROBLEM-2.md. Round-1 deliverable:
DESIGN-3.md; round 2 demands the Lean proof artifact per the established
pattern. You may cite DESIGN.md/DESIGN-2.md results where they apply (same
device, same measured map).

## Workload (one layer, one decode step)

t query tokens (t ∈ 1..16) attend over an KV cache of L prior tokens:

```
for each query head h (H_q heads, d = 64..128 head dim, GQA: H_kv = H_q/g,
g = 4..8 query heads share one KV head):
    scores[l] = (q_h · k_l) / sqrt(d)        l = 0..L-1   (gather + dot)
    p = softmax(scores)                                    (vector unit)
    out_h  = Σ_l p[l] · v_l                                (gather + weighted sum)
```

- KV cache bytes per layer = 2 · L · H_kv · d · dtype (ours to lay out;
  f16 assumed; paged/contiguous/head-interleaved is a DESIGN choice).
- L spans 1k..1M tokens (the long-context regime is the point of this
  problem). Working set ≫ any SRAM: this is a streaming/gather problem, not
  a residency problem.
- Compute per step is trivial vs bytes (t·L·d MACs vs 2·L·H_kv·d reads at
  t=1) — roofline it to prove you know why. The batch case t≤16 multiplies
  compute, not KV reads: state when the matrix unit becomes the right tool
  (scores as (t×d)·(d×L) GEMM reusing PROBLEM.md's pipeline vs vector dots).

## New open quantities (no measurements exist — branch on all of them)

- G: DDR **gather** rate for cache-layout-dependent access patterns
  (sequential is 173.8; page-sized random is the open question — page size
  is your design variable, so G becomes a function G(pagesize) with a
  measurement experiment per candidate).
- E: vector exp rate (softmax numerator/denominator) — availability and
  rate both UNMEASURED (ISA.md). If no fast exp: branch on the f32
  polynomial route at the measured 40-lane wall — cost it exactly.
- Online-softmax vs two-pass at t≤16 and the L regime boundary.

## Targets

- Attention step time must stay a bounded fraction of the GEMV step time so
  decode doesn't become attention-bound: state the fraction per regime
  (L = 4k / 32k / 128k / 1M) given the dense-GEMM step time implied by
  DESIGN.md route 1 (67.11 MB / 168.5 GB/s ≈ 398 µs per die-step class).
- No O(L) SRAM anywhere; O(t·H) only. Barrier plan per engine crossing.

## Deliverables (DESIGN-3.md, numbered)

1. Cache layout spec (byte-level; page geometry; K and V placement; the
   G(pagesize) model and its measurement experiment).
2. Pipeline design per engine (copy-in/loader/vector/matrix/copy-out) for
   t=1 and t≤16; when the matrix unit wins, cite DESIGN.md shapes.
3. Softmax strategy (online vs two-pass; exp branch) with full cost.
4. Buffer budgets + double-buffering over the L stream.
5. Sync/barrier plan (errata #8 applies to every reduce boundary).
6. Predicted ms and effective GB/s vs L for t ∈ {1,16}, derivations shown,
   with the G and E branches carried explicitly.
7. The regime map: where each design variant wins (L × t × G branch).
8. Experiment ladder (observable failure modes; the gather-rate probe is
   the single highest-value measurement — say so and spec it).
9. Risk register + fallbacks (e.g., no exp instruction; gather 3× slower
   than stream; H_kv=1 degenerate GQA).
10. Integration note: what the serving runtime must provide (KV write path
    per layer, page ownership across dies — assume KV is die-local to its
    layer, per HW-MAP errata #11).
