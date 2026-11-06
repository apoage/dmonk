# PROMPT-2P — proof round for DESIGN-2.md (MoE grouped quant-GEMM)

```
Round 2 — verification, same rules that caught 12 corrections in the dense
round. Your DESIGN-2.md is committed (81d5184) and strong; now prove it.
Working rule: a number that cannot be checked counts as unverified.

WHAT PROOF MEANS HERE (unchanged): silicon behavior is empirical and stays
with the experiment ladder; what must be proven is that every DESIGN-2.md
derivation follows arithmetically from HW-MAP constants, and that the
combinatorial claims (skew theorem, crossover set, overflow bound) are
correct as mathematics.

DELIVERABLES:
1. proof/moe.lean — Lean 4, CORE LIBRARY ONLY (no Mathlib/Batteries), scaled
   integers, every theorem closing by decide/omega/rfl/native_decide; must
   build via bare `lean proof/moe.lean` on Lean 4.35. If it doesn't build,
   it doesn't exist.
   Structure:
   - namespace Measured — HW-MAP constants ONLY as hypotheses with doc
     comments citing rows (the 174.6 kernel, 181.3 direct stream, 26.5
     serial loader, 15 ns MMA issue, 91 µs launch floor, per-die pure-read
     roof ~181, 24.6 vendor floor). NO axiom may state a DESIGN-2.md
     conclusion.
   - namespace Design — the scheme-S cost model as functions over
     (E, K, Ne, k, t, D, routing family, L, c_mma): per-core bytes, call
     counts, step time, effective GB/s.
   - namespace Proofs — one theorem per ledger row. Load-bearing set:
     T_anchor    : the 25.4 ns c_res subtraction identity — the model with
                   c_res derived from the measured 487 µs dense kernel
                   re-predicts 137.8 exactly, and the headline 135.3 follows
     T_bytes_eighth : per-core streamed bytes = step bytes / 8 for EVERY
                   routing outcome (the skew-immunity core — prove it as a
                   bijection/sum identity over arbitrary activation sets)
     T_skew_D    : the skew theorems over D (distinct active experts),
                   including the whole-expert-vs-S crossover set (S loses
                   only when 8 | D and by ≤ 1.8%)
     T_pp_thresh : ping-pong DDR-bound iff L >= 22.3 GB/s/core (and the
                   171.2 / 123.9 wall-clock branches)
     T_overflow  : the L0C before/after i32-difference exactness bound —
                   |sum| < 2^31 per 32 KiB region given the stated operand
                   bounds (prove the bound is sufficient, and exhibit the
                   tightness example if you can)
     T_w4_parity : the §8.4 claim that i4-route W4 equals W8 tokens/s in
                   the serial regime, with its premises as hypotheses
2. Regenerate/extend proof/moe.py if any constant or formula changes.
3. PROOF-COVERAGE-2.md — the ledger: every quantitative DESIGN-2.md claim ->
   theorem | moe.py label | EMPIRICAL (ladder ID) | ASSUMPTION. Orphans and
   uncited theorems both count against honesty.

CONSTRAINTS: U quantities (c_mma above its derived residual, dispatch cost,
routing distributions) stay universally quantified — threshold theorems hold
for ALL values. If any derivation fails to formalize — rounding, a missing
branch, arithmetic that doesn't close — FIX DESIGN-2.md in the same commit
and note it (prover-forced corrections score POSITIVE; silent mismatches
score zero). Report: theorem count, build status, coverage %, corrections.
```
