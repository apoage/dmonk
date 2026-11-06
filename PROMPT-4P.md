# PROMPT-4P — proof round for DESIGN-4.md (fleet partition planner)

```
Round 2 — verification, same rules as the dense and MoE rounds. DESIGN-4.md
is committed (dd78a8d); prove it. An unverifiable number counts as
unverified; and this document steers a hardware purchase decision, so its
arithmetic will be checked harder than most.

WHAT PROOF MEANS HERE: link rates, kernel rates, and runtime behaviors are
empirical axioms (HW-MAP); everything downstream — feasibility, capacities,
tokens/s, crossovers, multipliers — must be proven as arithmetic/combinatorial
consequences.

DELIVERABLES:
1. proof/fleet.lean — Lean 4, CORE LIBRARY ONLY, scaled integers,
   decide/omega/rfl-closable, builds via bare `lean proof/fleet.lean` on
   4.35. Structure: Measured (HW-MAP constants ONLY, cited) / Design (the
   partition + cost model as functions) / Proofs (one theorem per ledger
   row). Load-bearing set:
     T_mem_feas_dense_4k / _1M / _kv_int8 : the per-die feasibility rows
                   (49.9 + KV + ws + rt <= 86), including the razor-thin
                   84.3/86 KV-int8 escape and its dependence on the stated
                   2 GiB runtime overhead AS A HYPOTHESIS
     T_Lmax       : L_max formulas (dense f16 551253; B=4/16 scalings;
                   KV-i8 1102506; MoE 1.9M)
     T_min_dies   : the >= 5 dies lower bound (as an infeasibility result
                   for 4 dies — this is the theorem that kills 4-card Flash)
     T_serial     : under layer-split serialization the fleet streams
                   exactly one die's rate, hence dense t/s and MoE t/s
                   per card as derived (0.105 / 1.867 at 32k, t=1)
     T_spec_dense : 2.4x spec-decode gain on dense at acceptance 0.7 —
                   acceptance as a hypothesis variable, gain as a function
     T_spec_moe_loss : the MoE-uniform LOSS theorem (verify batch multiplies
                   active-expert bytes; net negative below the stated
                   skew/acceptance thresholds) — the thesis-correcting claim;
                   prove both directions of the threshold
     T_pipelining : the 7.7x / 7.1x multipliers as bounds given the
                   per-die step decomposition
     T_whatif     : P2P < 1.5 ms/token saving; D2D no-gain; tensor-split
                   5.9x/3.1x bounds, each with premises as hypotheses
2. proof/fleet.py regenerated if anything moves.
3. PROOF-COVERAGE-4.md — the ledger over all 39 rows: theorem | fleet.py
   label | EMPIRICAL (H-ladder ID) | ASSUMPTION (e.g. the 2 GiB runtime
   overhead, the anchored 91 µs bounce). Orphans count against honesty.

CONSTRAINTS: unmeasured quantities (bounce latency 10–500 µs bracket, P3's
attention branches) stay universally quantified with both bracket endpoints
proven. The one stated approximation (3.1% vs 1.5% activation bytes) must
appear as an explicit hypothesis on the affected theorems, not silently
absorbed. Prover-forced corrections to DESIGN-4.md score positive; silent
mismatches score zero. Report: theorem count, build status, coverage %,
corrections — and flag explicitly if T_min_dies or T_spec_moe_loss survive
formalization unchanged, since those two steer spending.
```
