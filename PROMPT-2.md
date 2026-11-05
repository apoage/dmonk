# PROMPT-2 — kickstart: MoE grouped quant-GEMM decode (fresh session)

```
You are a performance architect. This is a continuation task in a measured-hardware engineering repo: designs get implemented and run on the real device, and derivations are machine-checked afterwards.
This repo (dmonk) holds a sanitized, measurement-based map of a real
production inference accelerator (2-die card, 8 cores/die): every number in
HW-MAP.md was measured on silicon, unverified items are marked PRIOR or
UNMEASURED, and the errata section is verified device behavior — designs
that trip it fail silently, which is the normal failure mode here.

Read, in order: HW-MAP.md, ISA.md, PROBLEM-2.md. You may also read DESIGN.md
(the winning round-1 submission for the dense GEMM problem — its route 1
pipeline and §3.1 geometry hypotheses carry over; cite rather than restate).

YOUR PROBLEM: PROBLEM-2.md — the MoE grouped quant-GEMM decode kernel.
It is scored on the same terms as the prior round, which the winner led:

  40%  predicted t=1 GB/s of the ranked #1 design (uniform routing, W8),
       judged when the design is implemented and run on the real silicon
  30%  derivation correctness — every number traceable to HW-MAP, errata
       compliance (a design that can silently do nothing scores zero here)
  20%  experiment-ladder quality — each experiment settles its assumption
       with an observable failure mode (differencing / oracle / >=20-rep
       pass rate; timing alone never counts as a pass)
  10%  honesty about unknowns — clean branching, zero invented features

Prior submissions lost points by assuming an unmeasured rate equals its
best case and by proposing experiments whose failure mode is invisible.
Skewed routing must come out as a THEOREM over a skew parameter, not prose.
Deliverable: DESIGN-2.md at repo root, ten numbered sections per
PROBLEM-2.md. A second session
will later demand a machine-checked proof of your derivations (core-Lean,
integer arithmetic, claim ledger) — write your derivations now the way you
would want to formalize them, and keep every constant traceable.
```
