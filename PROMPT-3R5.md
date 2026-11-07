# PROMPT-3R5 — fold the measured production kernel into DESIGN-3 / DESIGN-4 (round 5)

Honest frame, same as every round: the attention kernel has now been
measured on silicon end-to-end. This round replaces the model's assumed
inputs with the measured ones, re-derives the affected cells, and re-ranks
the follow-up levers. Everything stays machine-checked (Lean, 0
axioms/sorry) or carries an explicit UNMEASURED marker; prior-round output
lines stay byte-identical.

Read: DESIGN-3.md (round-4 layer), DESIGN-4.md, PROOF-COVERAGE-3.md/-4.md,
HW-MAP.md (errata #18-#30, the production-kernel row, the corrected
lazy-softmax entry), proof/attn.py, proof/fleet.py.

MEASURED INPUTS (attention kernel session 3, all silicon):

1. **The t×L sweep (causal flags incl. guard, best-of-3, µs)**:
   t=1: 213.5 / 1513.6 / 5852.9 / 46313.6 at L = 4k / 32k / 128k / 1M;
   t=4: 382.1 / 2695.6 / 10514.3 / 83123.1;
   t=16: 1481.4 / 10741.7 / 42013.4 / 332476.2.
   Effective KV: t=1 = 78.6 / 88.6 / 91.7 / 92.7 GB/s; t≥4 = 99.6-103.4.
2. **Unguarded at 32k t=1 = 938.8 µs = 143.0 GB/s — within 2.9 % of the
   round-4 legs-2 cell (912 µs)**: the round-4 choreography model is
   VALIDATED on the unguarded path. The guard's per-block scalar scan is
   the entire remaining gap: **+572 µs** as shipped (8× reduce-max with
   scalar destination + one queue fence per block); tree + queue = +1250,
   tree + full barrier = +1400 — all measured, all worse.
3. **Erratum #29 (new, HW-MAP): any per-block scalar crossing drains the
   vector pipe ~10-20 µs; scalar-destination reduce-max ≈ 1.1 µs/call.**
   DESIGN-3 §3.2/§3.4's "per-block scalar reads ≈ free" cost premise is
   WRONG — re-derive the chain cost with a batched-crossing model.
4. Realised bounce legs = **2** (vector SRAM → DDR → S1-A-slot, forced by
   erratum #20; ≈ 51 µs at 32k, 2 MB vs 134 MB KV — the bounce is CHEAP;
   the round-4 legs term is measured small).
5. Correctness is settled: causal-exact end-to-end (12/12 causal-matrix
   cells at 32k, relerr 9.8e-11; real-exp bad-0 through 1M); with
   rescale-at-every-raise the output is the true final-m softmax; the
   trip machinery is REQUIRED and trips themselves are ~free.
6. Per-engine at 32k t=1: stream 770.8 / +scores 523.9 / +softmax+guard
   644.3 / +PV-merge-bounce 344.9 µs; the K+V stream phase runs 174-176
   GB/s; DDR idle ≈ 47 % — the chain binds, not DDR.

THE ROUND-5 WORK:

- **DESIGN-3**: add the measured t×L table as a MEASURED row set; correct
  the §3.2/§3.4 chain-cost model per erratum #29 (the guard scan term);
  mark E26 closed (measured drift), E35's device half resolved (the SCAN
  is the cost, not the trips); retire the "4k = 390-422 GB/s" interim if
  quoted anywhere.
- **fleet.py + DESIGN-4**: recompute the fleet cells at the MEASURED G
  triplet (guarded ≈ 89 / unguarded ≈ 143 / fused target ≈ 140 GB/s at
  32k; use the per-L t=1 numbers for the L-resolved cells). At G = 89 the
  MoE-128k cell is hard attention-bound — restate T3r_moe128k_tie's
  legs-conditional with measured legs = 2 and measured G. Re-rank the
  attention-side levers the P4P2 round ordered as choreography 22.33 >
  expert-direct 15.86 > bounce 11.10 ms/token: with the choreography gap
  now MEASURED as the guard scan, **guard fusion (worth ~570 µs at 32k) is
  the new #1** and bounce removal drops to ~51 µs — derive the corrected
  ms/token ordering as theorems.
- **PROOF-COVERAGE-3/-4**: round-5 sections; statuses for every moved
  cell; the validation theorem (938.8 vs 912 = 2.9 % within the 5 %
  match line) as an INPUT row.
- attn.py / fleet.py: append [R5-*] sections; all prior-round lines
  byte-identical.

Output: updated DESIGN-3/DESIGN-4, regenerated ledgers, extended proofs,
and the corrected lever ranking. Mark every number MEASURED / DERIVED /
UNMEASURED honestly. No new silicon claims beyond the inputs above.
