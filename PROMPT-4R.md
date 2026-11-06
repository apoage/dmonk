# PROMPT-4R — P4 re-grounding round (bounce measured; alternatives landed)

```
You are the fleet planner for round 3. Two inputs changed your model:

NEW MEASURED: host bounce lambda = 12.2/12.1 µs per direction (idle ==
under-load), 7.6x below the 91 µs anchor. NOTE: the 91 µs KERNEL LAUNCH
FLOOR is a different quantity and stands — your model previously used one
number for both; split them and re-instantiate every theorem whose
hypothesis carried the 91 µs bounce (T8 thresholds shrink ~7.6x; bounce
share ~0.1% of any step).

NEW DESIGNS to integrate as first-class partition variants (from
ALTERNATIVES.md, dd5f84c, with the steering correction 0915e22 — the
f16->i8 pass is RESOLVED, measured 43.7 µs on-device, so re-derive any
alternatives arithmetic that assumed the magic-bias or bounce fallback):
- INSTANCE-PARALLELISM: two 4-die instances, each with the minimal int4
  share that closes the memory fit -> MoE 32k 1.867 -> 3.878 t/s/card.
  Validate its arithmetic against YOUR memory model (note: its fit leaves
  only 0.1 GB/die at the 2 GiB runtime overhead assumption — treat that
  overhead as a hypothesis variable and state the sensitivity); the W4
  unpack rate premise (>0.8 GB/s/core) is now MEASURED at 5.3.
- DIRECT-PATH MoE: expert stream on the DDR->L0B direct path, 135.3 ->
  167.1/172.8 GB/s (all rates measured) — fold into the step model.
- PERSISTENT MEGAKERNEL: pays iff cross-core sync <= 108 µs — the sync
  cost is the one remaining unknown; carry it as the branch variable.
- H10 (two-instance concurrency) and sequence pipelining are PENDING
  runtime probes — carry both outcomes as branches.

DO: re-derive the step tables and the regime map with lambda=12 and the
three variants; regenerate proof/fleet.py (diff, list moved cells);
re-verify proof/fleet.lean (T8 and every 91-anchored hypothesis
re-instantiated; T_min_dies and T_spec_moe_loss must survive — flag if
instance-parallelism changes their statement); add the instance-parallel
gain theorem with the measured 5.3 premise; refresh the ledger; banner
DESIGN-4.md round 3. Commit. Report: the new per-regime decision table
(what to build first given H10 and (h) pending), moved cells, theorem
status.
```
