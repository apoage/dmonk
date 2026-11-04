# PROBLEM-4 — fleet partition planner (8 dies, one model, no P2P)

Same rules of engagement as the other problems, but this is a planning
problem, not a kernel: the deliverable is a partition + schedule + a
predictive model with derivations, Lean-checkable as feasibility and bound
theorems. Round-1 deliverable: DESIGN-4.md.

## The system (all from HW-MAP)

- 4 cards × 2 dies = **8 dies**, each 86 GB usable (688 GB total), shared
  host.
- Link asymmetry (measured): die 0 of each card: 27.6/27.3 GB/s H2D/D2H;
  die 1: 13.9/19.0 (its traffic transits die 0). **No die-die P2P** (runtime
  refuses); D2D via host at 10.7 GB/s r+w. All cross-die tensor exchanges
  bounce through host memory (errata #11).
- Serving runtime supports **layer-split** only (measured +2% decode at 2
  dies — dies alternate layers, no concurrent streaming); **tensor-split of
  one op across dies faults**.

## The model to place (parameterized like the others)

- Total weights: the source model is 160..200 GB of sub-8-bit quantization,
  **but W4 is silicon-dead on this part (HW-MAP errata #12) — weights
  resident on the dies must be modeled as int8 (2x the source bytes,
  320..400 GB) unless your plan includes a legal escape** (more dies,
  per-layer host streaming, hot/cold residency split with quantified
  on-the-fly costs). The headline question of this problem is now: **does
  ANY configuration of this fleet run the model at all**, and at what
  tokens/s. Both dense-GEMM and MoE (PROBLEM-2) weight shapes carry.
- KV cache: grows with context L and layer index; f16; the per-layer KV
  write path is die-local (errata #11).
- Draft model (speculative decoding): a second small model (0.5..2 GB)
  producing up to 3 draft tokens; verify batch t = k+1 ≤ 16 rides the main
  model under the flat m-curve (measured 144–148 GB/s flat M=16..128).
- Per-die step rate from the kernel work: dense decode ≈ 168 GB/s class
  (DESIGN.md), attention per PROBLEM-3 (carry its G/E branches), MoE per
  PROBLEM-2 (carry its skew branches).

## The planning problem

Choose, for the 8-die fleet: (a) layer→die assignment (boundaries; possibly
different per weight-shape), (b) expert→die placement if MoE (PROBLEM-2
inherits), (c) KV placement/growth policy, (d) draft-model placement, (e)
the per-token activation exchange schedule (bytes per boundary, host-bounce
serialized against compute), (f) load policy / weight residency plan.

Objective: **tokens/s per card** at L ∈ {4k, 32k, 128k, 1M}, with the
binding constraint named per regime (weights bandwidth? KV bandwidth?
host-bounce? softmax? imbalance?). Constraints: memory feasibility per die
(weights + KV + activations + runtime overhead ≤ 86 GB), layer-split only,
host-bounce bytes/toker ≤ link budget, thermal envelope 150 W/die class.

## Deliverables (DESIGN-4.md, numbered)

1. The partition (a)–(f) for dense and MoE weight shapes, with the memory
   feasibility table per die at L = 4k and 1M.
2. Per-token exchange traffic table (bytes, direction, link, μs at measured
   rates) and the serialization analysis vs compute time.
3. Predictive tokens/s/card model: step time = Σ per-layer (GEMM + attention
   + exchange) with every term derived from HW-MAP/DESIGN results; carry the
   PROBLEM-2/3 open-quantity branches; output the L × branch table.
4. Regime map: the binding constraint per (L, t, shape) cell, with the
   crossover derivations (these are the Lean theorems: "L* such that KV
   bandwidth binds for L > L*").
5. Sensitivity/what-if theorems: if P2P existed at rate X; if D2D were
   10.7→50; if tensor-split worked (the measured crash) — each as a bound,
   to quantify what a runtime upgrade would buy.
6. Placement of the draft model + the verify-batch schedule; does spec
   decode change the partition? (Verify batches are m≤16 flat — but do the
   draft's own layers contend for the same dies?)
7. Rollout plan: which 2-die subset proves the model first (one card),
   scaling path 1 card → 2 → 4 with re-partition steps.
8. Experiment ladder on the HOST only (no NPU needed): link microbench
   specs, host-bounce latency under concurrent load, KV growth trace.
9. Risk register: memory infeasibility at 1M context (KV bytes math),
   host-bounce becoming serial bottleneck, layer-split's +2% ceiling.
10. The single measurement that most changes the plan.
