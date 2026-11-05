# PROMPT-3 — kickstart: decode attention over the KV cache (fresh session)

```
You are a performance architect. This is a continuation task in a measured-hardware engineering repo: designs get implemented and run on the real device, and derivations are machine-checked afterwards.
This repo (dmonk) holds a sanitized, measurement-based map of a real
production inference accelerator (2-die card, 8 cores/die): every number in
HW-MAP.md was measured on silicon, unverified items are marked PRIOR or
UNMEASURED, and the errata section is verified device behavior — designs
that trip it fail silently, which is the normal failure mode here.

Read, in order: HW-MAP.md, ISA.md, PROBLEM-3.md. You may also read DESIGN.md
(the winning dense-GEMM submission — its matrix-unit pipeline, tile shapes
and §3.1 geometry hypotheses carry over where the batched-scores route uses
the matrix unit; cite rather than restate).

YOUR PROBLEM: PROBLEM-3.md — decode attention over the KV cache
(gather -> softmax -> reduce), t = 1..16 query tokens, context L up to 1M.
This problem's defining feature: its two most important rates (DDR gather
at page granularity; vector exp) are UNMEASURED — the winning design
carries them as explicit branches and specifies the probe that measures
each. Scoring, same as prior rounds:

  40%  predicted attention-step time at L = 32k and 1M (t=1), judged when
       the design meets the real silicon
  30%  derivation correctness — rooflines proven, every number traceable
       to HW-MAP, errata compliance
  20%  experiment-ladder quality — observable failure modes only; the
       gather-rate probe is expected to be named the single highest-value
       measurement, spec it properly
  10%  honesty about unknowns — branch on G and E explicitly, zero
       invented features (no exp instruction is assumed to exist until
       ISA.md says so)

Prior submissions lost points by assuming unmeasured rates equal their best
case, and by O(L) memory creeping into "streaming" designs. Deliverable:
DESIGN-3.md at repo root, ten numbered sections per PROBLEM-3.md. Per-model
results are published anonymized. A later session will demand a
machine-checked proof of your derivations (core-Lean, integer arithmetic,
claim ledger) — write derivations you would want to formalize.
```
