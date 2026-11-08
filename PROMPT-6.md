# PROMPT-6 — the new-errata design audit + the stage-overlap pre-design

Honest frame, same as every round: the attention-kernel sessions just added
fourteen silicon errata (#18-#31) to HW-MAP. Every design in this notebook
except DESIGN-3's round-4/5 layers was written against errata #1-#17 only.
This session audits the corpus against the new constraints, then pre-designs
the one lever the fleet round ranked next. No new silicon claims; every
number keeps its MEASURED / DERIVED / UNMEASURED marker; anything you change
in a design stays machine-checked or explicitly marked.

Read: HW-MAP.md first and carefully — errata #1-#31, the production
attention rows (session 3 + 4), the corrected #3 and widened #25. Then
DESIGN.md, DESIGN-2.md, DESIGN-3.md (round-4/5 layers), DESIGN-4.md,
ALTERNATIVES.md, PROOF-COVERAGE-*.md.

## Part A — the errata-impact audit (the main task)

For each erratum #18-#31, sweep all five designs + the alternatives table
and classify every encounter:

- **VIOLATES** — a pattern that cannot work as written. Cite the design
  section, the severity, and the minimal fix.
- **UNSAFE-ASSUMPTION** — works by luck or an unmeasured margin.
- **OBSOLESCENT** — the design PAID for something a correction removes.
  (E.g. corrected #3: count-mode ops measured full at 4096/2048 lanes —
  paid-for 1024-lane chunking may be unnecessary; wider calls are now
  licensed per-op. Check every chunked vector chain.)
- **UNAFFECTED.**

Specific places to look (not exhaustive):

- The megakernel's cross-engine sync plan vs #31 (fresh-reduction readback
  races) and #29 (per-block scalar crossings drain the vector pipe) — its
  rendezvous pattern predates both.
- The two-tier / overlapped cold tier vs #25 (staging offsets ≥ 4 KiB
  corrupt — only offset-0 4-KiB blocks and 32-KiB-granularity offsets are
  proven) and #23 (srcStride = 0 means contiguous).
- Every A/B/C-operand addressing pattern vs #18 (C-destination view offsets
  dropped) and #30 (B-slot ping-pong carries across loop nests).
- Every accumulate pattern vs #19 — f16 ONLY (i8 chains across barriers are
  measured exact to depth 8192; do not over-correct the i8 designs).
- Every copy-parameter table vs #22-#24 (unary Muls no-op; element-form
  copies > 4 KiB land partially; blocked-copy stride semantics).
- The expert kernel's documented staging (2×32-KiB legs at 32-KiB-granular
  offsets — measured fine; confirm the docs say the granularity, not just
  "offsets").

Output: an ERRATA-IMPACT table per design + a ranked correction list.
Corrections applied in place (marked "audit:") score positive; anything
deferred to silicon gets a ladder row.

## Part B — the stage-overlap pre-design (E40)

The measured engine split at 32k t=1 (legacy-scan form, strictly serial,
total 1513.6 µs): stream 770.9 / +scores 523.9 / +softmax+guard 644.3 /
+PV-merge-bounce 344.9. Round 5 bounds perfect phase overlap at
≤ 7.46 ms per token on the 128k fleet cell. Pre-design the real thing:

- Which stages can physically overlap? (The engines are distinct — DDR
  streaming vs matrix+barriers vs vector — but the accumulator and vector
  SRAM budgets may force serialization; say which and why.)
- The barrier structure under #14 (the full barrier is the only direct-load
  fence), #19 (no f16 accumulation across barriers), #29 and #31 (no
  per-block scalar crossings, no fresh-reduction readbacks at fences).
- What fraction of the serial sum is reachable, as a bound, with the
  arithmetic as theorems where it closes.
- Keep every cost cell parameterized on the measured phase deltas — the
  final numbers land after the next kernel session; design the STRUCTURE,
  not the constants.

Output: an E40 section drafted for DESIGN-3 (a round-6 layer) with the
barrier plan, the reachable-overlap bound, and its ladder row.

Deliverables: the ERRATA-IMPACT tables, in-place corrections (marked),
the E40 draft section, updated ledgers if corrections move cells. Prior
model output stays byte-identical.
