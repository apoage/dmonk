# PROMPT-3R6 — fold the measured fused cells into the designs (round 6)

Honest frame, same as every round: the fused (deferred-guard) kernel is now
MEASURED end-to-end at production flags. This round replaces the round-5
"inferred ~950 µs" cells with the measured ones, restates the lever ranking
post-fusion, and documents two numerics classes the runs surfaced. Prior
output stays byte-identical; every number keeps its MEASURED / DERIVED /
UNMEASURED marker; core Lean only, 0 axioms/sorry.

Read: HW-MAP.md (the deferred-guard row, updated by the kernel session
itself), DESIGN-3.md (R4/R5 layers), DESIGN-4.md, ALTERNATIVES.md,
PROOF-COVERAGE-3/-4.md, proof/attn.py, proof/fleet.py.

MEASURED INPUTS (kernel session 5, all production flags):

1. **Trip-free full-pipeline cells (trips 0)**: 32k t=1 = **945.5 µs =
   142.0 GB/s**; 128k = 3618.8 µs = **148.4**; 1M = 28.694 ms = **149.7**.
2. **Amortized at the real trip-rate premise (0.087-0.22 % of steps)**:
   946.3-947.4 µs at 32k t=1 → **G ≈ 141.7-141.8 GB/s — exactly ON the
   141.7 line** where round 5 said fused attention beats the direct-path
   expert kernel at exactly 32k. At 128k/1M the fused rate (148.4/149.7)
   is above every tie threshold — attention wins outright there.
3. Reference points at 32k t=1: legacy scan 1514.9 µs (2 trips); guard-off
   902.9 µs; canonical adversarial 1818.1 µs (63 trips — upper bound,
   never the fleet cell; the adversarial gap vs legacy GROWS with L:
   1M 56.0 vs 46.3 ms, no switch to amortize).
4. The fold itself costs −59 µs vs the scan (one pass); trips ~free;
   the session-4 "fold misread" is CLOSED as a test-harness artifact
   (the identity gate repacked shared arenas before the timing cell;
   the fold is exact at the +8 bound — planted 8.0 → 0 trips,
   8.02 → exactly 1 with the cap not yet binding).
5. Two numerics classes, dispositioned, to document:
   - the 1M canonical bad-2: a weightless-outlier row's whole mass lands
     in f16 subnormals at the global-m retry (~1e-2 granularity) —
     adversarial-profile-only, no fleet cell affected; the exact P path
     (8.4M lanes) is 100.00 %.
   - the random-profile out-verify noise floor (bad 324 @32k / 65 @1M,
     deferred ≡ legacy ≡ guard-off, worst lanes near-zero wants) — a
     verification-methodology class, not a kernel defect.

THE ROUND-6 WORK:

- **DESIGN-3**: round-6 measured layer — the fused cells as MEASURED rows;
  E39 (batched guard) resolved by measurement; the E35 device half fully
  closed (fold −59 µs one-pass, trips ~free); the two numerics classes as
  notes with their dispositions.
- **DESIGN-4 + fleet.py**: the fused cells ARE the fleet numbers now.
  Restate the MoE cells at G = 142.0/148.4/149.7 (trip-free) and the
  amortized 141.7-141.8 at 32k — the cell stays attention-bound at every
  reading. Re-rank the levers post-fusion: at exactly 32k fused attention
  TIES the direct-path expert kernel (on the line); at 128k/1M attention
  wins outright — so **E40 (stage overlap) becomes the attention-side #1**,
  E29 remains the expert-side lever, bounce removal stays last (~51 µs).
  The verify-batch thresholds and the spec-decode α-threshold re-derive at
  the fused G (the 0.807 guarded number moves again).
- **Ledgers**: round-6 sections (R6-*), statuses, 0 orphans.

Output: updated DESIGN-3/DESIGN-4, extended proofs for every restated
threshold, [R6-*] model sections, regenerated ledgers. No new silicon
claims beyond the inputs above.
