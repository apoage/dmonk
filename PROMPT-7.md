# PROMPT-7 — fresh-eyes challenge round: re-derive, attack, fork if better

Honest frame: this notebook was built and verified across many sessions —
problems, designs, measured hardware facts, and ~1 300 machine-checked
theorems. This round is an INDEPENDENT adversarial re-review by eyes with
no stake in any prior round's conclusions. Two missions, in order:
**(A) peer review** — find where the corpus is wrong, circular, or
standing on a tainted measurement; **(B) fork** — if you find a materially
better solution family for any problem, draft it. Changing your mind on
nothing is an acceptable outcome only if the re-derivations actually ran.

## Reading order (the corpus is large — this is the economy)

1. `README.md`, then `HW-MAP.md` whole (the errata are hard constraints;
   note that some errata CORRECT earlier errata — the errata history is
   itself data about measurement reliability).
2. Per problem: `PROBLEM*.md` → `DESIGN*.md` (with its round layers —
   later rounds supersede earlier bodies, banners say what moved) →
   `PROOF-COVERAGE*.md` (every claim maps to a theorem and a status word)
   → the `proof/*.lean` + `proof/*.py` pair.
3. `ALTERNATIVES.md` + `ERRATA-IMPACT.md` last — they are the cross-problem
   views.

## Mission A — the review protocol

1. **Re-derive, don't trust.** From the ledger rows whose status is PROVED
   and whose numbers steer decisions, pick AT LEAST TEN load-bearing
   theorems and re-prove them INDEPENDENTLY from the models' printed
   numbers — fresh proofs under a new namespace (e.g. `Chk.*` in a new
   file `proof/check.lean`), never edits to existing proofs. Suggested
   targets (not exhaustive): the instance-gain and break-even family, the
   minimum-dies theorem, the drift family, the attention-vs-weights tie
   (legs-conditional), the fit-margin and spec-decode threshold theorems,
   the chain-cost bounds, the stage-overlap bound and its gate.
2. **Hunt circularity and harness taint.** Every INPUT row was measured by
   some harness. This corpus's own history contains a documented class
   where an entire measurement family stood on a harness bug invisible to
   its own tests (an integration bug that every correctness gate missed
   because the test arena coincided with the bug — recorded in HW-MAP's
   integrated-kernel row). For each high-leverage INPUT: ask what harness
   measured it, whether that harness's arena coincides with what it
   claims to measure, and whether a same-class bug would flip a decision.
   Output a taint-ranking (blast radius ordered).
3. **Decision-sensitivity audit.** The UNMEASURED variables and ASSUMPTION
   rows: list which ones, if resolved against the design, FLIP a ranked
   decision (not merely move a number). This list is the round's most
   valuable single output.
4. **The dominated-alternatives table.** Re-score it independently: is any
   family under-scored, missing a premise, or dismissed on a stale number?
   (The table itself caught one such error before — check its own history
   notes.)

## Mission B — the fork license

If — and only if — you find a solution family that plausibly DOMINATES a
design's chosen route under the HW-MAP constraints: draft it as a NEW
document (`DESIGN-FORK-*.md`; the corpus is append-only — never rewrite
existing designs), containing: the mechanism mapped to the errata
constraints, an extension of the relevant `proof/*.py` under `[FORK-*]`
labels, theorems for its headline cells, the honest statement of what must
be MEASURED on silicon before it can rank, and the experiment ladder that
would decide it. A fork that ignores an erratum is dead on arrival.

## Deliverables

- Verdict table per problem: SOUND / WEAKENED / BROKEN, with evidence.
- The `Chk.*` re-derivation file (compiling, core Lean only, 0
  axiom/sorry/native_decide — same rules as the corpus).
- The taint-ranking and the decision-sensitivity list.
- Fork drafts if any.
- A `PROOF-COVERAGE-CHECK.md` section for the round; prior model output
  stays byte-identical; corrections to design text applied in place and
  marked `challenge:` score positive — they are the point of the round.

Frame discipline: every number in this notebook is MEASURED, DERIVED, or
marked UNMEASURED/ASSUMPTION — keep it that way, including your own.
