# PROMPT-3P — proof round for DESIGN-3.md (decode attention / KV gather–reduce)

```
Round 2 — verification, same rules as the dense, MoE, and fleet rounds
(each of which caught material errors: a broken bijection, a false parity
claim, double-counted latencies). DESIGN-3.md is committed (4bc9738);
prove it. This design carries the fleet's largest open lever (the P4 proof
round showed the gather-rate branch moves 1M-context MoE cells 2.7x), so
its arithmetic will be checked as hard as the fleet's.

WHAT PROOF MEANS HERE (unchanged): DDR rates, kernel rates, and ISA op
costs are empirical axioms from HW-MAP; everything downstream — block/page
arithmetic, buffer sizes, op counts, branch times, crossovers, drift
bounds — must be proven.

DELIVERABLES:
1. proof/attn.lean — Lean 4, CORE LIBRARY ONLY, scaled integers, every
   theorem closing by decide/omega/rfl/native_decide; builds via bare
   `lean proof/attn.lean` on Lean 4.35 (~seconds; if it doesn't build it
   doesn't exist). Structure: Measured (HW-MAP constants ONLY, cited —
   note the stream column must use the pure-read roof ~181/174.6 class,
   not the 173.8 read+write figure, with the choice justified) / Design
   (the (rows, d, block, page, L, H_kv, g)-parameterized cost model) /
   Proofs (one theorem per ledger row). Load-bearing set:
     T_crossover  : attention time equals one 398 µs GEMV unit exactly at
                    L = 16,896 tokens — both sides of the crossover, as
                    functions of L
     T_gqa_matrix : the vector-dot route costs 0.505 · rows · ρ32 of the
                    KV stream time, hence compute-bound for every g >= 2 —
                    prove the inequality for all g, not example values
     T_softmax_ops: the op-count arithmetic for the tree max and the 22-op
                    clamped Horner-plus-squaring exp, per score and per
                    block; the 1.6e-4 relative-error claim enters as a
                    HYPOTHESIS on the polynomial (do not prove numerics —
                    carry the constant as an input with its source)
     T_drift      : the ±Q sign-alternation region-difference drift bound
                    in f32 — state and prove the bound as a theorem over
                    the alternation count and per-block error hypotheses
     T_buffers    : every SRAM buffer is a function of (rows, d, block)
                    only — no O(L) SRAM anywhere, as structural theorems
                    over the buffer-size definitions
     T_branches   : the four headline branches at 32k and 1M (stream /
                    paged 0.5 µs / gather-3x / worst softmax corner) and
                    the E21-relevant statement of what gather rate each
                    fleet cell needs
2. proof/attn.py regenerated if anything moves.
3. PROOF-COVERAGE-3.md — the ledger over every quantitative DESIGN-3.md
   claim: theorem | attn.py label | EMPIRICAL (E-ladder ID) | ASSUMPTION.
   Orphans and uncited theorems both count against honesty. The t=16
   two-pass vs single-pass-full-L0A variant split must be explicit.

CONSTRAINTS: the two truly unknown quantities (gather page cost c_pg, and
the softmax op set — E22) stay universally quantified hypothesis variables
with both bracket endpoints proven (c_pg in {0, 0.5, 2} µs at minimum; the
no-exp corner and the fast-exp branch both carried). The launch floor
enters wall-clock rows only, never in-kernel ones. Prover-forced
corrections to DESIGN-3.md score POSITIVE; silent mismatches score zero.
Report: theorem count, build status, coverage %, corrections — and flag
explicitly whether T_crossover and T_gqa_matrix survive unchanged, since
they gate the attention-implementation season.
```
