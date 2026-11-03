# PROMPT — paste this to the design reviewer

```
You are a performance architect. This repo (dmonk) contains a sanitized,
measurement-based map of a real production inference accelerator: a 2-die
card, 8 cores/die, quantized-LLM decode workload. Every number in HW-MAP.md
was measured on silicon; unverified items are explicitly marked PRIOR or
UNMEASURED. The errata section is verified device behavior, not spec-sheet
caveats — designs that trip it fail silently, which is the normal failure
mode on this part.

Read, in order: HW-MAP.md, ISA.md, PROBLEM.md.

CONTEXT — this task is one submission in a cross-model architecture bake-off:
the same sanitized device map is being given to several frontier models
(GPT-class and others), and the designs are then BUILT AND RUN on the actual
silicon by the evaluation team. Scoring is by measured behavior, not by how
the write-up reads:

  40%  measured m=1 GB/s of your ranked #1 route when implemented
  30%  derivation correctness — every number traceable to HW-MAP, errata
       compliance throughout (a design that trips errata #1 scores zero on
       this axis: it will look fine and silently do nothing)
  20%  experiment-ladder quality — would each experiment actually settle its
       assumption, with an observable failure mode
  10%  honesty about unknowns — clean branching on UNMEASURED quantities,
       zero invented features

Prior submissions lost the most points by: assuming an unmeasured rate equals
its best case, skipping differencing guards, and proposing experiments whose
failure mode is invisible. A concrete, checkable design that is wrong in one
spot outscores a safe, vague one. Per-model results are published anonymized.

Task: produce the execution-layer design per PROBLEM.md's ten deliverables.
Rules of engagement:
- Quantitative: every time/bandwidth claim derives from a HW-MAP number,
  with the derivation shown inline.
- No assumed features: only ISA.md exists. Where you need an UNMEASURED
  quantity (loader rate, L0 sizes, DDR→L0 direct loads, MMA issue cost,
  dequant rate), carry both branches and specify the cheapest decisive
  silicon experiment that would settle it.
- Every experiment you propose must have an observable failure mode
  (differencing, oracle, or ≥20-rep pass rate) — on this device, timing
  alone cannot distinguish "fast" from "silently did nothing".
- Beat or critique the five routes listed in PROBLEM.md with arithmetic.
- If multiple designs are viable, rank them by expected m=1 GB/s and by
  experimental risk, and say which single measurement most changes the
  ranking.
```
