# PROMPT-3R — P3 re-grounding round (all open quantities now measured)

```
You are the attention architect for round 3. Season (v1) measured every
quantity DESIGN-3.md carried as a branch (HW-MAP rows through commit
8a7079f). Ground the design down onto the measured constants:

NEW MEASURED INPUTS (read them in HW-MAP first — these change your model):
- vexp EXISTS (bitwise-exact on the softmax domain, c_exp ~= 11.5
  lane-equivalents — clears every native-exp threshold 56/51/24/19);
  WholeReduceMax EXISTS (181.9 ns/call, beats the 6-op tree). The 851 µs
  worst corner is expected to COLLAPSE to the stream branch — re-derive
  and confirm with arithmetic.
- Merge chain itemized at 25,750 lane-equivalents (3.7x the 7,000
  assumption); native exp collapses ~half its cost to the ~650 ns class.
  Re-derive S4 single-pass with the MEASURED chain; state the new t=16
  figure and whether the flagged 12,128-vs-25,750 question is now moot.
- rho32 = 1.37 chained (model assumed 2); sigma_s = 19.9 ns/compare;
  And<i32> ABSENT from the op table.
- G(page) MEASURED: shuffled 153.8 / 167.0 / 169.2 GB/s agg at 16/64/256
  KiB; c_pg = 38 ns/page (lower bound — shuffled-within-contiguous-arena
  caveat stands). MoE-128k stays stream-bound at 64 KiB by only 0.7 GB/s.
- R_drain 152.8-285.5 GB/s/core (never binds, 9-45x margin).
- P5's two-tier pages (1 MiB extents + 64 KiB tails) dominate every fixed
  size at c_pg = 0.5 µs; re-evaluate against the MEASURED 38 ns c_pg and
  the lower-bound caveat — is two-tier still right at 38 ns?

DO: re-derive the four headline branches at 32k/1M; re-check the
crossover theorem's stream basis (16,896 should be unaffected — confirm);
update the page-size recommendation with the razor-thin MoE-128k margin
called out as a design constraint; regenerate proof/attn.py (no cell may
move silently — diff and list); re-verify proof/attn.lean against the new
constants (re-instantiate the moved theorems; T_crossover and T_gqa_matrix
must survive or the corrections get flagged); refresh the ledger; banner
DESIGN-3.md as round 3. Commit. Report: moved cells, the new worst corner,
the page verdict, theorem status.
```
