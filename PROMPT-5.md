# PROMPT-5 — cross-problem second-solution search (pattern matching over known solutions)

```
You are a performance architect in a cross-model bake-off. This repo now
contains four completed, mostly proof-verified designs for one real device:
DESIGN.md (dense quant GEMM, 174.6 measured), DESIGN-2.md (MoE grouped GEMM),
DESIGN-3.md (attention), DESIGN-4.md (fleet planner) — plus the measured map
they stand on. Your task is NOT literature search. It is PATTERN MATCHING:
take the known solution families of acceleration engineering (listed below)
and match each against this device's measured constraints, hunting for
alternatives the four designs missed — solutions that beat, fuse, or
dominate what we have.

Read, in order: HW-MAP.md (esp. errata — every idea must survive ALL of it),
ISA.md, then all four DESIGN documents and PROOF-COVERAGE ledgers.

THE PATTERN LIBRARY (match each family against each problem; extend it if
you know families we missed):
- GEMM: split-K / stream-K; persistent kernels; producer-consumer unit
  specialization (dedicated DMA cores feeding compute cores — warp
  specialization analog); output-stationary vs weight-stationary; fused
  epilogues; on-the-fly dequant fusion vs pre-expanded weights; L2-resident
  tile carving.
- Attention: flash-decoding (split-KV parallel reduction); paged/blocked KV
  (we have pages — are ours the right size?); GQA head packing; KV
  quantization; prefix/cache reuse across steps.
- MoE: expert-parallel vs data-parallel layer placement; hot-expert caching
  / residency tiers; capacity-factor token dropping; fused gather-GEMM-
  scatter; grouped-GEMM with per-group tiles; expert-pair scheduling.
- Systems: persistent megakernel / whole-layer single launch (the 91 µs
  launch floor is 13.5% of MoE steps and m-linear prologues gate routing);
  command-graph capture; zero-copy host bounce buffers; polling vs
  interrupt; sequence pipelining microbatch patterns across the die chain;
  NUMA-aware placement of the host-side bounce.
- Cross-cutting: kernel fusion (quant+A-pack+GEMM; attention+GEMV), shared
  passes across problems (one stream feeding two consumers), layout reuse
  between dense/MoE/attention packs.

RULES OF ENGAGEMENT (same scoring as prior rounds):
- Every alternative gets ARITHMETIC from HW-MAP numbers: which measured
  cell it improves, by how much, and which errata it must survive — an idea
  that trips errata #1 (silent no-op) or the choreography flags scores zero
  unless it includes a differencing-style validation plan.
- Dominated alternatives must be shown DOMINATED with arithmetic, not
  dismissed in prose; near-ties get the measurement that would separate
  them.
- Fusion opportunities must state what pass/buffer they eliminate and the
  new sync surface they create (errata #8/#14 applies).
- Rank everything by (expected gain x feasibility); name the single
  highest-value experiment among your proposals.
- Flag which claims are formalizable for the Lean round (threshold or
  bound theorems) — they will be proven next.

DELIVERABLE: ALTERNATIVES.md at repo root: (1) the ranked alternative
table across all four problems; (2) for each of the top five: the design
sketch, the arithmetic, the errata-survival argument, the experiment;
(3) the fusion map (which designs share streams/buffers/launches);
(4) a claims ledger in the established format. Per-model results are
published anonymized; a later session will demand proofs of whatever you
claim, so write derivations you would want to formalize.
```
