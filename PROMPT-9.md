# PROMPT-9 — round 5, fresh eyes: challenge the round-8 re-grounded corpus

Honest frame: this notebook was rebuilt and re-grounded through four
adversarial challenge rounds and one adjudication; ~1 400+
machine-checked theorems now stand, and the round-8 regen just
re-anchored its largest single premise on new measurements. Two
missions, in order: **(A) peer review** — find where the corpus is
wrong, circular, or standing on a stale measurement, with the round-8
changes as the highest-leverage targets; **(B) fork** — if you find a
materially better solution family, draft it. Changing your mind on
nothing is acceptable only if the re-derivations actually ran.

## Reading order (the corpus is large — this is the economy)

1. `README.md`, then `HW-MAP.md` whole (the errata are hard
   constraints; some errata CORRECT earlier errata — the errata
   history is itself data about measurement reliability). Note the
   three round-8 rows: the W4 tier dispatch, the KV-int8 fused
   verdict + drain wall, and the serving-layer constants.
2. Per problem: `PROBLEM*.md` → `DESIGN*.md` (round banners in
   historical order; later rounds supersede earlier bodies) →
   `PROOF-COVERAGE*.md` → the `proof/*.lean` + `proof/*.py` pair.
   Read DESIGN-4's ROUND-8 STATUS banner closely — it is the newest
   layer.
3. `CHEATSHEET.md` + `CHEAT-MATH.md` (the graded landscape and its
   machine-checked arithmetic layer — source-free by design), then
   `ALTERNATIVES.md` + `ERRATA-IMPACT.md` last.

## Mission A — the review protocol

1. **Re-derive, don't trust.** Pick AT LEAST TEN load-bearing
   theorems whose numbers steer decisions and re-prove them
   independently from the models' printed numbers — fresh proofs
   under a new namespace (e.g. `Chk5.*` in a new `proof/check5.lean`),
   never edits to existing proofs. Suggested targets: the round-8
   re-ground family (`R8r.w4_cold_slab_reground`, `R8r.plan_beats_chain_at_w4`,
   `R8r.drain_wall_closes_128k`, `R8r.sk3_parity`), the instance-gain
   and break-even family, the minimum-dies theorem, the drift family,
   the chain-cost bounds, the stage-overlap bound and its gate.
2. **Attack the round-8 re-ground specifically.** The cold-tier
   re-ground applies the MEASURED hot-path W4 rate (169.2 GB/s die
   aggregate) to the plan's COLD slabs by a single division (÷8
   cores). Is that transfer legitimate — or does the cold tier pay a
   rate the hot-path measurement cannot witness (cold-start effects,
   tier-switch boundaries, the arena's own packing)? What cell, if
   measured on the cold tier directly, would flip the new
   plan-beats-chain ordering (4.047 vs 3.852) back?
3. **Hunt circularity and harness taint** (the corpus's own history
   documents seven harness-deception classes). For each high-leverage
   INPUT: what harness measured it, does its arena coincide with what
   it claims, and would a same-class bug flip a decision? Output a
   taint ranking ordered by blast radius.
4. **Decision-sensitivity audit.** The UNMEASURED variables and
   ASSUMPTION rows: which, if resolved against the design, FLIP a
   ranked decision? The standing open cells: the megakernel go/no-go
   (launch-removal cell in the 17–36 µs band vs the 19.1/17.3 µs
   threshold); the 1M retry share (vs the 64.48 % legacy break-even);
   the region-difference saturation condition; the deferred kernel at
   t = 4; fleet-scale pipelining beyond die-pairs. This list is the
   round's most valuable single output.

## Mission B — the fork license

If — and only if — you find a family that plausibly DOMINATES a
design's chosen route under the HW-MAP constraints: draft it as a NEW
document (`DESIGN-FORK-*.md`; the corpus is append-only), containing:
the mechanism mapped to the errata constraints, an extension of the
relevant `proof/*.py` under `[FORK-*]` labels, theorems for its
headline cells, the honest statement of what must be MEASURED before
it can rank, and the experiment ladder that decides it. A fork that
ignores an erratum is dead on arrival. Note what the corpus already
closed: KV-precision flips at 128k (drain wall), lossless sub-byte
int8 packing, and tensor-parallel card-pair relays for
single-card-resident models.

## Deliverables

- Verdict table per problem: SOUND / WEAKENED / BROKEN, with evidence.
- The `Chk5.*` re-derivation file (compiling, core Lean only, 0
  axiom/sorry/native_decide — same rules as the corpus).
- The taint ranking and the decision-sensitivity list.
- Fork drafts if any.
- A `PROOF-COVERAGE-CHECK.md` section for the round; prior output
  stays byte-identical; corrections to design text applied in place
  and marked `challenge:` — they are the point of the round.

Frame discipline: every number in this notebook is MEASURED, DERIVED,
or marked UNMEASURED/ASSUMPTION — keep it that way, including your own.
