# PROMPT-4P2 — Lean proof round for DESIGN-4 round 3 (the 27 T3r_* claims)

```
Round-3 proof session for the fleet planner. DESIGN-4.md's round-3 layer
(committed with the R3 re-grounding) names 27 theorems-in-waiting in
Appendix A', each with its fleet.py [R3-*] label. Prove them.

BUILD NOTES from the re-grounding session (read first):
- proof/fleet.lean builds standalone and via lake, untouched by round 3 —
  your round-3 additions extend it in place.
- The fleet file CANNOT import proof/attn.lean when built standalone:
  duplicate the handful of attention-chain functions it needs (they are
  pure integer arithmetic — copy them with a namespace, do not refactor
  attn.lean).
- Core Lean 4.35 only, integer arithmetic, decide/omega/rfl class, 0
  axioms/sorry/native_decide; bare `lean proof/fleet.lean` must build clean.

INPUT CHANGES to instantiate (the map moved since the prompt was written):
- H10 is GREEN at card scale (measured, HW-MAP): two instances on disjoint
  dies at full solo speed, 1.99x aggregate. The instance-parallelism gate
  is therefore OPEN at card scale; the two-card inheritance remains a
  hypothesis — prove the instance-gain theorems with H10 as a hypothesis
  variable, and note which cells activate under the measured card-scale
  result.
- E35 is LICENSED (qk-norm + per-row guard): the fixed-shift softmax chain
  numbers are the loadable branch; the 42-48% overflow no-guard case is
  dead — carry both as the prompt's ladder rows require.

UPDATES SINCE THIS PROMPT WAS WRITTEN (2026-11-07, before this session):
- DESIGN-3 round 4 landed: proof/attn.lean is at 265 theorems, and
  proof/fleet.py gained [R4-*] sections plus the page-waste term (all
  round-2/3 lines byte-identical). Your additions still extend fleet.lean
  in place — and must leave the [R4-*] sections intact.
- The T3r_moe128k_tie statement has MOVED: round 4 carries the P-fragment
  DDR bounce as legs 0/1/2 per block. Legs-0 reproduces the round-3 tie
  (weights-bound by 0.5% at 256 KiB); with both legs charged the MoE-128k
  cell is attention-bound at every gather rate up to 174.6. Prove the tie
  as a legs-conditional and state which leg count the planner must read.
- Known stale figure to correct (diff-list it): fleet.py's serial-chain
  int4 per-piece figure (596 ns) predates the alternatives proof round's
  measured 807 ns.
- If a round-3 "attention-bound iff G <= G*" cell cannot hold because the
  vector chain alone exceeds the weight time, prove the corrected statement
  (attention-bound at every G) and correct DESIGN-4's round-3 text —
  corrections score positive.

THEOREM TARGETS: the 27 named T3r_* statements (Appendix A'), plus:
  T3r_spec_dense_split : the 0.227 vs 0.248 (std vs fixed-shift verify
  chain) pair as threshold theorems over the chain cost
  T3r_moe128k_tie      : the tie — weights-bound by 0.5% at 256 KiB,
  attention-bound at 64 KiB AND at every page size on the direct-path
  expert kernel (this decides whether attention-kernel follow-ups —
  DESIGN-3's route M — outrank expert-GEMM follow-ups — the direct-path
  expert kernel)
  T3r_instance_margin  : the 2-30 MB/die fit margin with the 2.3%/GB
  overhead sensitivity, overhead as hypothesis variable
Deliverables: extended proof/fleet.lean, regenerated PROOF-COVERAGE-4
(27 rows resolved, 0 orphans), fleet.py untouched unless a correction
forces it (then diff-list). Prover-forced corrections to DESIGN-4 round-3
text score positive. Report: theorem count, build status, coverage,
corrections, and whether the tie and instance-margin theorems survive.
```
