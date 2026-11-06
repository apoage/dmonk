# PROMPT-5P — proof round for ALTERNATIVES.md (the pattern-search claims)

```
Round 2 for the alternatives, same rules as every proof round (they have
each caught material errors). ALTERNATIVES.md (dd5f84c) carries a 32-claim
ledger (Appendix A) with alt.py labels. Prove it — with one input change
already applied by steering: the f16->i8 activation pass is RESOLVED
(measured 43.7 µs on-device, rint-half-even saturating +-127 — HW-MAP
0915e22), so re-derive every claim that assumed the magic-bias trick or
the bounce fallback before proving it.

Load-bearing theorem set:
- T_instance_gain : the instance-parallelism bound — two 4-die instances
  beat one 8-die chain iff W4 unpack > 0.8 GB/s/core (now MEASURED 5.3:
  instantiate), including the memory-fit premise (minimal int4 share,
  0.1 GB/die margin at the 2 GiB overhead — overhead as hypothesis
  variable with the sensitivity theorem)
- T_direct_path   : MoE on the direct path = 167.1/172.8 from measured
  rates (anchor identity, same style as the P2 anchor theorem)
- T_megakernel    : pays iff sync <= 108 µs, both directions
- T_two_tier      : page-tier dominance at c_pg = 38 ns measured (does it
  still dominate at the lower bound? and at 3x the lower bound per the
  scattered-cache caveat?)
- T_dominated_*   : the eight dominated families — domination as BOUNDS,
  not prose (e.g., DMA-core specialization <= 58.2 GB/s absent an
  inter-core SRAM path — prove the cap from the map)
Deliverables: proof/alt.lean (core-only 4.35, integer, decide/omega class,
builds standalone), regenerated alt.py, PROOF-COVERAGE-5.md (32 rows +
any re-derived post-correction claims, 0 orphans). Prover-forced
corrections to ALTERNATIVES.md score positive. Report: theorem count,
build status, coverage, corrections — flag whether T_instance_gain
survives with the measured premise, since it currently gates the largest
fleet decision after H10.
```
