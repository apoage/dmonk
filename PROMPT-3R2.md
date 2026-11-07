# PROMPT-3R2 — DESIGN-3 round 4: absorb the pre-implementation review

Honest frame, same as every round: the design is about to be implemented on
real silicon; this round re-grounds DESIGN-3.md on a read-only
pre-implementation review BEFORE the implementation's own measurements land.
Everything you change stays machine-checked (Lean, 0 axioms/sorry) or
carries an explicit UNMEASURED marker.

SILICON UPDATES SINCE THE REVIEW (2026-11-07, kernel session 1 — these
supersede the review items where they conflict; HW-MAP is already updated):

- **The f16 k-shape sweep RAN: all k ∈ {16,32,64,128} EXACT on the f16×f16
  tuple** (128 reps/shape, one-hot k-probes at every k position, all 8
  cores). Item 1 below becomes: record the verdict, drop the
  conditionality, keep the cost table (d = 128 mainline licensed; a d = 64
  variant can use single k = 64 calls — 48 vs 80 per block). The i8 k = 64
  anomaly is i8-only, neither fragment- nor element-count-based.
- **f16 accumulation corrupts across any full barrier or A re-lift**
  (broken at ≥ 2 accumulates even at interleave ≥ 16; i8 is exact to depth
  8192 in the same pattern — E21 was that existence proof; erratum #19).
  Item 2's spacing fixes are therefore MOOT on f16: there are no accumulate
  chains. DESIGN-3 must adopt the implemented pivot — C_o =
  per-128-token-group FRESH chunk sets + a vector-side merge of the
  partials (accumulator budget fits: 128/256/256 KiB at mt = 1/2/4) — and
  re-cost the merge (a new ledger row).
- **The drift work re-aims**: the ±Q Z-branch is unimplementable on this
  tuple (its mechanism cannot exist); fresh-per-block accumulation is
  drift-free by construction; E26/K5 measure the ONLINE-CHAIN f32 drift
  instead. Item 5's C_o theorem question changes shape accordingly.
- New errata to respect in the spec (HW-MAP #18-#21): the matrix call's C
  destination drops view offsets (byte-offset tensor construction
  required); vector-SRAM → S1 A-slot plain copy is WRONG (A operands built
  in vector SRAM ride a DDR bounce); host verification patterns need prime
  periods > L (mod-N patterns alias tokens).
- **The lazy guard is REQUIRED, not advisory**: without the per-trip
  recompute exactly the predicted 9/8192 lanes per tripped block are wrong
  (measured on silicon).
- Rates: the kernel's own fresh-path gather runs ~138 GB/s aggregate,
  page-size-insensitive 64–256 KiB, c_pg ≈ 0 (18 % under the E21 basis
  from diagnostic-loop barrier density; the production loop halves
  barriers per byte); the scores half is verified exact at 32k (2.1M
  elements; the zero-copy P premise holds).
- OPEN implementation anomaly (session 2 owns it): 75–91 % of P lanes read
  back as raw scores from the softmax reel — deterministic; every isolated
  piece passes. Mark the softmax-reel cost cells OPEN in the ledger until
  it lands; do not model around it.

Read: DESIGN-3.md (round 3), PROOF-COVERAGE-3.md, HW-MAP.md (errata, E21,
E22, the two production-kernel rows, and the NEW dtype qualification on the
MMA shape-constraints paragraph), proof/attn.lean, proof/fleet.py.

Review verdict to carry at the top of the round: implementable as written
for d = 128 at t ≤ 2 on the lazy chain; five things can make the first
silicon numbers wrong or unexplainable. The findings, as the work list:

1. **k-shape is an i8 fact, not an f16 fact** (HW-MAP now says so). The i8
   sweep (k=32/128 correct, k=64 wrong — the two-fragment shape) does not
   transfer: the f16 fragment is 16 dims deep, so f16 k=32 is the
   two-fragment shape and f16 k=64 the four-fragment shape that works in
   i8 as k=128; f16 k=128 has no i8 analogue. Add the f16 (16,16,k) sweep,
   k ∈ {16,32,64,128}, as the GATING experiment row of the §8 ladder
   (k-position-sensitive planted patterns, ~128 reps, differencing through
   one L0B address); make the d = 64 split AND the d = 128 k = 128 call
   conditional on its verdict. Ledger table — calls per 512-token block at
   mt = 1 / MMA share at mt = 4 (256-token blocks): k = 64 48 / 12 %–48 %,
   2× k = 32 80 / 20 %–80 %, 4× k = 16 144 / 36 %–144 % (MMA-bound).
   Issue cost k-independence was measured only at k = 128.
2. **Choreography.** The two k-halves as written are a spacing-0 same-dst
   chain — first halves for all token groups, then second halves (spacing
   32, free). The PV chain is spacing 8 at mt = 1 (one call per n-chunk
   per 128-token group), depth 4 096 at 1M with no reset — alternate
   scores and PV calls per tile pair for spacing 16. C_s chunks (683 deep,
   spacing ≥ 64) are the safe class. Open question to resolve from the E21
   probe's structure, not the doc: if E21 accumulated per n-chunk across
   all tiles it is existence evidence for low-spacing deep chains — mark
   it CONFIRMED or REFUTED, do not assume.
3. **Lazy softmax spec (§3.4) closure:** (a) m_r's definition (first-block
   per-row max of this step vs prefill-calibrated — the 0.087–0.22 % trip
   rate transfers only to the measured definition; the calibration window
   shrinks to 256 tokens at mt ≥ 3); (b) the 8 reduce-max results cross to
   the scalar unit through the queue fence (erratum 15) or the guard reads
   pre-fold values; (c) gate the merge, not the PV calls (absorb a tripped
   block's partial into the snapshot, re-issue; no scalar stall on the
   common path); (d) fallback granularity (block ≈ 10 µs vs row via the
   reel's argmax lane); (e) a switch policy (after k trips in one step,
   finish the step on the §3.2 chain; else a needle profile pays ≈ 10 µs
   per block, 640 µs at 32k); (f) padding rows exactly zero in the staged
   Q and the −Q copy.
4. **Ledger corrections:** T3r_fixed omits the first-block max machinery
   and the one-time reel §3.4 itself prices at 4–5 µs/step (cells 0.6 %
   optimistic at 32k, 4 % at 4k); the KV-int8 × lazy cell quantizes P at
   fixed 127 on p ≤ 1 but lazy P reaches e⁸ — rescale or mark the cell
   unreachable.
5. **Drift:** T_drift_1M (512-token blocks) and T_drift_blocks (1 366
   visits, 256-token blocks at mt ≥ 3) both stand; state explicitly that
   the deterministic bounds (ulp 2⁻⁹ / 2⁻⁸) exceed the 10⁻³ ship criterion
   at both sizes (1M ships only under the random-walk hypothesis E26
   measures), that smax = 32 is the qk-norm license premise, and that the
   C_o region difference has NO theorem (1 024 visits/region at 1M, est.
   ~10⁻⁴ per block partial) — prove it or mark it unproved. Add the mt = 1
   1 024-token-block lever (208 KiB in L0C, half the visits, S1 snapshots
   as the price) as a listed variant.
6. **Causality at t > 1 (spec gap):** append-then-attend has no mask and
   no tail capacity (L mod 16 = 15 wants 31 tokens in a 16-token tail).
   Spec the per-row additive mask on the last block's drained scores over
   ≤ 2 token groups + the two-block masked tail on the vector path; E27's
   host reference must be causal.
7. **Numerics:** add a planted-sink case to E27 (the f16 cast flushes p
   below ~6·10⁻⁸ relative to the shift — one-sided bias, several % row-sum
   loss on a sink-like head at 1M; random inputs never produce it; both
   chains).
8. **Row extraction stride math:** drain chunks are 1 KiB = one
   [16 rows][16 dims] f32 fragment; C_o fragment-major, n-group-minor:
   row r of fragment f = 8 runs of 64 B at stride 1 024 B from f·8192 +
   r·64 (4 runs at d = 64; after an f16 cast 32 B runs at stride 512 B
   from f·4096 + r·32); m = 64 calls change the nesting (stride 4 096 B);
   the f32 nesting of the f16×f16 tuple is E23(v) — the production
   verification covered the i32 fragment at m = 16 only. Differencing
   pattern: V distinct per row AND dim, out[r] changes row by row. Rate
   unmeasured: fine once per step, not as a per-block re-layout.
9. **The P lift (not Q) is the S1-resident exposure:** it sits between
   direct-load barriers (the E29 fault class) at 2–8× the expert kernel's
   lift density per byte — E24 must run at the real P cadence at mt = 1
   and 4. The f16 A-fragment order for Q/P is E23(ii) regardless of
   staging; L0A exactly-full at mt = 4 is unprobed (mt = 3 fallback is
   free: the cell is vector-bound).
10. **Two-pass vs S4 stands** (S4 loses every merge on both chains; only a
    pipelined-exp result could move t = 4–8 to DDR-bound, and S4 still
    loses) — but flag the t = 1 rowmax chain (94 % of the block chained;
    flips vector-bound at the itemised merge: 77 354 vs the 56 932 line at
    167.0) and the −S third op on odd region visits (175 ns slack). Keep
    the E35-first build order.
11. **Planner:** fleet.py has no page-waste term (tail waste 4 MiB per
    layer-sequence at 256 KiB vs 1 MiB at 64 KiB; 60 MiB/seq on a
    15-layer dense die, 480 MiB at B = 8, against 3–45 MB instance-fit
    margins and the 1.66 GB margin of the 1M KV-int8 layout); weigh
    ALTERNATIVES §2.5's memory argument in the round-3 dominated verdict.
    Keep P_bytes a parameter; the MoE-128k tie is within 1 % at every
    size ≥ 64 KiB, so the planner must read the realised G, not assume a
    side. A 256 KiB page is four sub-pages with l div 1024 (the
    bijections and the 128k table window are 64 KiB facts).

Output: DESIGN-3 round 4 + PROOF-COVERAGE-3 round-4 section + updated
proof/attn.lean (every theorem re-verified, 0 axioms/sorry) + fleet.py with
the waste term. Mark every number's status honestly (measured / derived /
UNMEASURED). No new silicon claims.
