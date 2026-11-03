# PROMPT-4 — kickstart: fleet partition planner (fresh session)

```
You are a systems architect competing in a cross-model design bake-off.
This repo (dmonk) holds a sanitized, measurement-based map of a real
production inference accelerator fleet: 4 cards x 2 dies, every number in
HW-MAP.md measured on silicon (link asymmetries, the refused P2P, the
host-bounce D2D rate, the layer-split-only serving runtime), errata
verified device behavior.

Read, in order: HW-MAP.md, PROBLEM-4.md. Also read DESIGN.md (dense decode
kernel: the per-die step-rate inputs your model needs) and, if present,
DESIGN-2.md / DESIGN-3.md (MoE and attention results — carry their open
branches as your model's parameters).

YOUR PROBLEM: PROBLEM-4.md — partition 160-200 GB of W4 weights + KV cache
+ a draft model across 8 dies with NO peer-to-peer and a layer-split-only
runtime, and predict tokens/s per card at L = 4k..1M. This is a planning
problem: the deliverable is a partition, an exchange schedule, and a
predictive model where every term derives from measured rates — the
crossovers ("L* where KV bandwidth starts binding") must be theorems-in-
waiting, derivable by a proof checker, not prose.

Scoring, same as prior rounds:

  40%  predicted tokens/s/card at L = 32k (dense and MoE shapes), judged
       against the real fleet when the plan is executed
  30%  derivation correctness — memory feasibility arithmetic, exchange
       traffic tables, every number traceable to HW-MAP/DESIGN results
  20%  experiment-ladder quality — host-only microbench specs with
       observable failure modes (this problem's ladder runs on the host)
  10%  honesty about unknowns — carry PROBLEM-2/3 branches explicitly;
       zero invented link capabilities (P2P is REFUSED; do not quietly
       assume it)

Prior submissions lost points by assuming unmeasured rates equal their best
case and by exchange schedules that serialize worse than analyzed — model
the host bounce as a real contended resource. Deliverable: DESIGN-4.md at
repo root, ten numbered sections per PROBLEM-4.md. Per-model results are
published anonymized. A later session will demand a machine-checked proof
(core-Lean, integer arithmetic, claim ledger) of the feasibility bounds and
crossover derivations.
```
