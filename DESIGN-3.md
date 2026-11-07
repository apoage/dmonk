# DESIGN-3 — decode attention over the KV cache (gather → softmax → reduce), one die, 8 cores

> **ROUND-5 STATUS (2026-11-07 — the production kernel measured end-to-end, attention session 3; HW-MAP 62e8137, errata #29–#30;
> `proof/attn.py` `[R5-*]`, `proof/attn.lean` `T5r_*` (27 new theorems, 292 total, 0 axioms / sorry / native_decide), `proof/fleet.py`
> `[R5-*]`, PROOF-COVERAGE-3.md round-5 section).** The model's assumed inputs are replaced by measured ones; every number below is
> marked MEASURED (session 3 unless named), DERIVED (a theorem) or UNMEASURED. **MEASURED:** the production kernel's t × L sweep (§6.0:
> t = 1 213.5 / 1 513.6 / 5 852.9 / 46 313.6 µs at 4k / 32k / 128k / 1M = 78.6 / 88.7 / 91.7 / 92.7 GB/s, plus the t = 4 and t = 16 rows),
> the unguarded 32k cell (938.8 µs = 143.0 GB/s), the guard's per-block scalar scan (+572 µs quoted; 574.8 µs by the table difference),
> erratum #29, the realised bounce (legs = 2, ≈ 51 µs at 32k), the per-engine phases, causal-exactness, the 1M drift (session 2).
> **The INPUT validation row (T5r_validate): unguarded 938.8 µs against the round-4 legs-2 cell 911 680 ns = +3.0 % (2.9 % of the displayed
> 912 µs), inside the 5 % match line — the round-4 choreography model is validated at the cell level.** Two DERIVED readings qualify it
> (T5r_validate_terms, T5r_engines): the match nets offsetting terms (the model over-charges the bounce by 48.1 µs and the K/V basis by
> 22.4 µs and under-charges the exposed chain by 97.7 µs), and the measured phases SUM to the total, guarded and unguarded alike (the K+V
> stream busy 50.9 % / 82.1 %) — the kernel is chain-serial, not DDR-bound with hidden vector slack as §6.1″ modelled. **The cost premise
> of §3.2 / §3.4 is corrected (erratum #29; T5r_guard, T5r_A5_refuted, T5r_crossing_cells):** per-block scalar reads are not free — the
> shipped guard costs 8 981 ns per block, serialised (round 4's A5 said < 1 µs, hidden in 9.2 µs of DDR slack); the chain cost is
> max(stream, lane work) + a crossing term ⌈nb/K⌉·cx for one crossing per K blocks (cx = 10–20 µs measured). The "fused target ≈ 140 GB/s"
> is exactly the unguarded kernel + ONE 20 µs crossing per step (958.8 µs; 141.5 GB/s at 10 µs) — worth 554.8–564.8 µs per layer at 32k
> (574.8 µs is the zero-residual ceiling, the "~570 µs"); the batched guard itself is UNMEASURED (E39). **The rowmax chain of §3.2 needs its
> 16 row maxima as Duplicate operands every block**: ≥ one crossing per block (≥ 10.3 µs — UNMEASURED structure, a lower bound), so it is
> ≥ 1 599 µs at 32k, slower than the shipped guarded lazy chain: **the switch-to-rowmax policy of §3.4 (e) is void** and KV-int8 on rowmax
> is ≥ 1 311 µs at 32k (T5r_rowmax_bound, T5r_switch_void). **Statuses:** E26′ CLOSED (1.2 / 1.8 ppm at 1M against the 246 / 490 ppm bound,
> T5r_drift); E35's device half RESOLVED (the SCAN is the cost, the trips ≈ free; the trip rate per model stays open); E24′ CLOSED (legs = 2;
> the bounce costs 51.4 % of the modelled roof charge); E36 CLOSED (session 2: a host overrun); E27′ causal half CLOSED (12/12, relerr
> 9.8·10⁻¹¹; the planted-sink test open); E28 CLOSED (the realised rate is the sweep). The interim "4k = 390–422 GB/s" was never quoted in
> this document, DESIGN-4 or the ledgers (HW-MAP voids it): nothing to retire. **Readings for the planner (§6.0, T5r_readings; fleet.py
> `[R5-*]`):** guarded = MEASURED at every L; unguarded = MEASURED at 32k, elsewhere the guarded cell minus the per-block guard (UNMEASURED
> off 32k — the round-4 cells track it at 108.2 / 103.0 / 99.0 / 97.7 %); fused = unguarded + one crossing per step. The DESIGN-4 MoE-128k
> cell is attention-bound on every reading (by 82.5 / 10.8 / 11.4 %); with the measured bounce its stream-only line is G ≤ 178.7 (round 4:
> 189.4) — attention-bound at every G ≤ 174.6 even with zero chain cost (T5r_fleet_moe_128k_*). t ≥ 4: the measured cells are 2.4–2.6×
> (t = 4) and 3.9–4.2× (t = 16) the round-4 regime cells — the guarded multi-fragment kernel costs ≈ 20.3–24.0 µs per fragment per 512
> tokens whatever the fragment count (T5r_per_fragment); the unguarded t ≥ 4 kernel is UNMEASURED. The crossover moves to L ≈ 7 697
> (guarded) / 13 329 (unguarded) on the chord between the measured 4k and 32k cells (T5r_chord_*). New ladder rows: E39 (the batched
> guard's residual — it decides whether guard fusion outranks the direct-path expert kernel at 32k) and E40 (phase overlap, ≤ 117 µs at
> 32k). The round-4 banner and body are kept; every moved cell is in `[R5-moved]` and the round-5 ledger.

> **ROUND-4 STATUS (2026-11-07 — the pre-implementation review absorbed, re-grounded on kernel session 1; HW-MAP commit 423d433,
> errata #18–#21; `proof/attn.py` `[R4-*]`, `proof/attn.lean` `T4r_*` (66 new theorems, 265 total, 0 axioms / sorry / native_decide),
> `proof/fleet.py` `[R4-*]`, PROOF-COVERAGE-3.md round-4 section).** The review's verdict is carried as the frame: implementable as
> written for d = 128 at t ≤ 2 on the lazy chain, and the five things that could make the first silicon numbers wrong or unexplainable
> are now in the model with their status. **What session 1 settled (M):** the f16 (16,16,k) sweep is EXACT at every k ∈ {16, 32, 64, 128}
> (the i8 k = 64 anomaly is i8-only — §1.2: d = 128 keeps one k = 128 call per 16 tokens, d = 64 may use one k = 64 call: 48 instead
> of 80 calls per block, T4r_kshape); the f16 B fragment, the f16 A fragment and the f32 C-chunk nesting are measured (E23(i), (ii),
> (v): the zero-copy P premise holds, 2.1M score elements exact at 32k); **f16 accumulation into one C chunk corrupts across any full
> barrier or A re-lift (erratum #19) — this design now writes every C chunk FRESH: one matrix call per chunk per visit, C_o as one
> fresh chunk set per 128-token group summed on the vector unit** (§3.1, §4: L0C 128 / 256 / 192 / 256 KiB at mt = 1..4, T4r_l0c).
> The region difference, the ±Q alternation, the NegSnap buffers and the drift theorems' mechanism are RETIRED (its deterministic bounds,
> 2·10⁻³ / 4·10⁻³ at 512 / 256-token blocks, exceeded the 10⁻³ ship line — 1M shipped only under the random-walk hypothesis); the
> numerics that remain are the online chain's f32 sums, and with the two-level (block-local, then running) accumulation of §3.1 their
> deterministic first-order bound is **246 ppm at 1M** (chains of 2 052 / 2 062 adds; 490 ppm at 256-token blocks) — under the line
> without any hypothesis (T4r_drift_online, T4r_sum_error; the matrix unit's internal summation order stays UNMEASURED, E26′). **The P
> fragments ride a DDR bounce (erratum #20: US → DDR scratch → DDR → S1 → loader)** — carried as `legs` ∈ {0, 1, 2} transfers of the
> 16 KiB·mt of P per block on the K/V stream's roof, UNMEASURED, headline = 2 (the conservative reading): the t = 1 block grows
> 12.5 %·mt (T4r_bounce). **The lazy guard's per-trip recompute is REQUIRED (M: 9/8192 lanes wrong per tripped block without it)** and
> §3.4 is closed (a–f). **The headline moves (T4r_t1_*, `[R4-t1-*]`; lazy-T chain, 256 KiB pages 169.2, wall = + 91 µs): 32k
> 805 → 912 µs (+13.3 %; 813 without the bounce), 1M 25.4 → 28.6 ms (+12.5 %; 25.4 without)**; on the session-1 kernel loop's
> measured 138.3 GB/s (diagnostic-loop barrier density; the production loop is UNMEASURED) 1 111 µs / 35.0 ms. Every t = 1 cell is
> DDR-bound on every chain at every measured G with the bounce; without it the rowmax chain at chained latencies is vector-bound at
> 174.6 (12 265 > 12 011 ns: the review's flag, T4r_t1_binding). t ≥ 4 on the lazy chain: 1 030 µs at t = 4 (DDR-bound), 1 301 at
> t = 8, 2 565 at t = 16 (vector-bound; round 3: 3 162); S4 stays dominated (T4r_s4_dominated_*). **Fixed cost 19.3 µs on the lazy chain**
> (the first-block max the review found missing: round 3 said 11.3; cells were 0.6 % optimistic at 32k, 4 % at 4k — T4r_fixed), so
> L_eq moves: 14 848 at 174.6 with the bounce (16 384 without; round 3: 16 896), 14 336 / 15 872 on the design page (T4r_crossover).
> **The planner (DESIGN-4, fleet.py): with both bounce legs the MoE-128k cell is ATTENTION-bound at every G ≤ 174.6 (by 11.9 % at
> 169.2, 36.7 % at 138.3; T4r_fleet_moe_128k_legs2); without them it is the round-3 tie (iff G ≤ 168.3) — the planner must read the
> realised G and the realised bounce.** fleet.py now carries the page-waste term (4 MiB per layer-sequence at 256 KiB: 60 MiB per
> 15-layer dense die, 480 MiB at B = 8, 120 MiB per 30-layer instance die — above every 2–30 MB instance-fit margin, +1–3 ‰ of int4
> share; the dense 1M KV-int8 layout keeps 1.5 GB — T4r_waste, `[R4-waste-*]` `[R4-inst-fit-*]`), P_bytes as a parameter and the
> 256 KiB page as four 64 KiB sub-pages (T4r_page256_*). **OPEN (session 2 owns it): 75–91 % of P lanes read back as raw scores from the
> softmax reel — deterministic, every isolated piece passes; every vector-chain cell is marked OPEN in the ledger and is NOT modelled
> around.** The KV-int8 × lazy cell is UNREACHABLE as specified (P at the fixed scale 127 vs the lazy e⁸; reachable only at μ = 0,
> trip rate UNMEASURED — T4r_i8). The round-3 banner and body are kept; the round-4 section of the ledger marks what they no longer describe.

> **ROUND-3 STATUS (re-grounding on the season (v1) measurements — HW-MAP commit e9349c8; `proof/attn.py` `[R3-*]`,
> `proof/attn.lean` `T3r_*`, PROOF-COVERAGE-3.md round-3 section).** Every quantity this design carried as a branch is now
> measured: the gather rate per page size (E21: 153.8 / 167.0 / 169.2 GB/s shuffled at 16 / 64 / 256 KiB; c_pg = 39 ns at
> 64 KiB as a lower bound; the attention choreography's own sequential rate is 169.0–169.2, 3.2 % under the W8 kernel's 174.6),
> the softmax op set (E22: native exp at 11.5 lane-equivalents, native reduce-max at 181.9 ns per call, And<int32> absent,
> ρ32 = 1.37, σ_s = 19.9 ns), the drain (152.8–285.5 GB/s/core, hidden 17–44×) and the merge chain (25 750 lane-equivalents in
> the pack's itemisation). **Headline, t = 1 (§6.1, `[R3-t1-*]`, T3r_t1_*): 822 µs at 32k and 25.7 ms at 1M on the design's
> 64 KiB page (167.0); 812 µs / 25.4 ms at 256 KiB pages (169.2); 788 µs / 24.6 ms at the 174.6 basis — every t = 1 cell is
> DDR-bound. The round-2 worst corner (851 µs: polynomial exp + tree max at half rate) is unreachable; the new worst corner
> (every vector call at its chained latency) is 828 µs / 25.7 ms, +0.6 % / +0.0 % (T3r_worst_overrun).** What the
> measurements changed (`[R3-moved-*]`, T3r_moved): (1) the per-row block max, not the exp, is the expensive step — 16
> reduce-max calls per fragment (2.9 µs) plus the f16 tree and a 20-call shift reel make the §3.2 chain 9 276 ns per 512-token
> block (77 % of the block; 11 836 ns = 98.5 % at chained latencies; round 2's native corner was 1 489 ns = 12.4 %); so (2)
> verify batches are softmax-bound from t = 4 on the chain as specified (32k: 1 225 µs at t = 4, 3 556 at t = 8, 7 057 at
> t = 16 — round 2: 783 / 785 / 1 554); (3) **S4 is dead**: the single pass loses to two passes for every merge count on both
> chains (T3r_s4_dominated_*; 11 596 vs 7 057 µs at the pack merge) — the 12 128-vs-25 750 question is moot; (4) the fixed
> cost rises 7 074 → 18 820 ns, which **moves the crossover**: `T_crossover`'s stream basis (12 011 ns per block) is
> unaffected, but attention equals one 398 µs GEMV unit at **L_eq = 16 384** (k ≥ 32) on the measured per-row-max chain at the
> 174.6 basis, and at 15 872 on the attention path's own 167.0–169.2 (T3r_crossover_*: k ≥ 33 = 16 896 holds iff the fixed
> cost lies in [1 637, 13 647] ns — the fixed-shift variant keeps it); (5) `T_gqa_matrix` **survives unchanged** at the
> measured ρ32 = 1.37 (69.2 % at rows = 1, compute-bound for every rows ≥ 2: T_gqa_matrix_100, T3r_gqa_137); (6) the KV-int8
> variant is vector-bound on the chain as specified (612 µs, not 391). **The one design change the measurements force
> (§3.4, variant "lazy"): a fixed per-row shift with an overflow guard** — no per-block row max, no α: 5 530 ns per block
> (46 %), t ≤ 4 DDR-bound, t = 16 at 3 162 µs, KV-int8 at 413 µs, L_eq = 16 896 kept at 174.6 — gated on the exception rate
> (E35). **Page verdict (§1.4, §10; T3r_page_*, T3r_fleet_*): 256 KiB pages by default, 64 KiB where the allocator's granule
> forces it (−1.3 %), never 16 KiB (−9.1 %); the two-tier scheme of ALTERNATIVES §2.5 buys 1.3 % at the measured c_pg and is
> dominated by 256 KiB pages (it pays ≥ 5 % only if a real scattered cache shows c_pg ≥ 160 ns, 4× the measured lower
> bound). Design constraint: the DESIGN-4 MoE-128k cell sits at the attention/weights flip — ATTENTION-bound at the 64 KiB
> shuffled page (by 25.7 µs = 0.8 % of the 3.21 ms layer; HW-MAP's "stays stream-bound by 0.7 GB/s" reads
> `T_fleet_G_moe_128k`'s inequality backwards: 167.0 ≤ 167.7 is the attention-bound side), weights-bound at 256 KiB by 16 µs
> (0.5 %), attention-bound at 16 KiB by 9.4 % (T3r_fleet_moe_128k_cells, T3r_moe_128k_direction).** Build: `lean
> proof/attn.lean` and `lake build` succeed; 199 theorems (121 of round 2 kept as the round-2 model's arithmetic + 78 of
> round 3), 0 axioms / sorry / native_decide. The round-2 banner and the body's round-2 numbers are kept where the round-3
> section of the ledger marks them superseded; every moved cell is listed in `[R3-moved-*]`.

> **ROUND-2 STATUS (proof round, `proof/attn.lean`, PROOF-COVERAGE-3.md).** Every quantitative claim below is
> now a theorem of `proof/attn.lean` (core Lean 4.35, 0 axioms, 0 sorry, 0 native_decide; `lean proof/attn.lean`
> and `lake build` both succeed), an attn.py label, an experiment or a stated assumption — the ledger is
> PROOF-COVERAGE-3.md. **The two gating results survive formalization unchanged**: `T_crossover` (attention =
> one 398 µs GEMV unit at L = 16 896, proved both ways over the 512-multiples; over arbitrary L the model crosses
> at 16 400) and `T_gqa_matrix` (vector-dot route = 0.505·rows·ρ32 of the KV stream, compute-bound for every
> rows·ρ32 ≥ 2, hence every g ≥ 2, any head dim). **Prover-forced corrections (18, listed in the ledger):** the
> §4 US budget at mt = 1 is 208 KiB + 64 B as tabled (not 200 — over the 208 KiB evidence until the snapshots
> move to S1 or the prologue q buffer is aliased); L0A is 16 KiB·mt = 64 KiB at mt = 4 (not 48); the drain
> threshold is 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1..4 (not 3.4·mt, not 13.6); rows* = 112 on the
> native-native corner (not 128); native-exp thresholds c_exp ≤ 56 / 51 / 24 / 19 (not 55 / 23); the poly+tree
> corner binds from t = 4 at ρ32 = 1; d = 64 is 20.0 %·mt MMA and c_V ≤ 30 / 14; the drift bound 840 is the
> random-walk hypothesis (deterministic 21 856) and smaller blocks make it worse; page tables are 0.012 % of KV;
> tail waste 16 MiB at 1 MiB pages; S4 L0C = 2 × 64 C_s + 2 × 64 C_o; the worst corner is +9.8 % at 32k;
> σ_s ≥ 47; 9 280 B partials; G(P, 0) = 174.6 at every P. New: the gather rate each fleet cell needs
> (`T_fleet_G_*`: the MoE 128k cell is attention-bound for every G ≤ 167.7, i.e. c_pg ≥ 123 ns at 64 KiB).
> Theorem names throughout now refer to the realised proof/attn.lean names (the appendix's round-1 proposals were renamed).
Scope (PROBLEM-3.md): per decode step and layer, t ∈ 1..16 query tokens attend over L ∈ 1k..1M cached
tokens; H_q query heads in GQA groups of g = 4..8 over H_kv = H_q/g KV heads, head dim d = 64..128, f16 KV.
`scores = q_h·k_l/√d`, `p = softmax(scores)`, `out_h = Σ_l p[l]·v_l`. Everything derives from HW-MAP.md (round 3: as of
commit e9349c8, the season (v1) validation pack — E21 / E22 / R_drain / σ_s measured; rounds 1–2 were anchored at
7f53dce, the direct-load silicon sync), ISA.md, DESIGN.md (the dense decode pipeline this design reuses:
(16,16,128) i8/f16 MMA loop at 15 ns per call, DDR→L0B direct loads with one full barrier per 32 KiB tile at
174.6 GB/s flat m = 1..16, the A-pack §3.2 and C-drain §3.3 layouts) and DESIGN-2.md (the region-difference
accumulator reset §3.2, ladder E11–E13). Status tags: **M** measured (HW-MAP), **D** derived here by arithmetic
shown, **P** PRIOR, **A** explicit assumption with the experiment that measures it, **U** unmeasured and
branched in rounds 1–2 (G, E, R, ρ32, R_drain, σ_s — all MEASURED in round 3, the constants table carries the values; Z stays
the region-difference design).

Units: bytes binary (KiB/MiB), GB decimal; rates GB/s decimal (1 B/ns = 1 GB/s); times ns floored, quoted µs
round-half-up; percentages tenths. Every derived cell is printed by **`proof/attn.py`** (integer arithmetic only,
Python ≥ 3.8, no dependencies; label `[Ax-…]` in the text) in the conventions of `proof/model.py`, so the proof
session can transcribe it into core Lean 1:1 — theorem targets are listed in Appendix A.

**Headline shape** (`[A0-shape]`): H_kv = 8 (one KV head per core), g = 8 (H_q = 64), d = 128, f16 →
kv_tok = 2·8·128·2 = **4 096 B per token per layer** (512 B per core per token). This is the DESIGN-4 MoE/dense
KV geometry (kv_tok = 4 KiB) with g inside PROBLEM-3's 4..8 range. L = 4k/32k/128k/1M = 2¹²/2¹⁵/2¹⁷/2²⁰ tokens.
KV bytes per layer: 16.8 MB / 134.2 MB / 536.9 MB / **4.295 GB** (`[A0-kv-*]`).

## Constants used

| Symbol | Value | Status / origin |
|---|---|---|
| R_gemm | **174.6 GB/s** per die: full W8 decode kernel, DDR→L0B direct loads, one full barrier per tile, two 32 KiB parity halves, flat m = 1..16 — the exact choreography this design streams K and V through; 21.825 GB/s per core when all 8 stream | M (data-movement) |
| R_ddr / R_read | 173.8 r+w stream roof / ~181 pure read (181.3 direct stream) | M |
| c_mma | **15 ns** per (16,16,128) MMA call; n ≤ 16 per call; k ∈ {32, 128} correct, **k = 64 wrong**; m = 64 across the full L0C works; init/align flags **ignored** | M |
| R_vec | 40 f16 lanes/cycle × 1.08 GHz = **43.2 G lane-ops/s/core**, count-mode Mul/Add/Cast, ≤ 1024 lanes per call | M |
| ρ32 | f32 lane-rate penalty vs the f16 figure: **1.37 measured** (chained Mul 63.5 / Add 63.7 ns vs f16 46.4 ns per 1 024-lane call); rounds 1–2 bracketed 1 / 2 | **M** (round 3) — E22 |
| E | vector exp **EXISTS** (f16 and f32, bitwise-exact on x ≤ 0): 272.8 ns per 1 024-lane call = **c_exp = 11.5** lane-equivalents per element (chained, conservative); the 22-op polynomial of §3.2 is retired (it would bind only above c_exp = 21) | **M** (round 3) — E22 |
| R | cross-lane reduce-max **EXISTS**: f16 181.9 ns / f32 251.4 ns per call (one value per call, lane 0); And<int32> is ABSENT (the f32 6-op tree is closed, the f16 tree via And<int16> at 45.9 ns is open); the per-row block max of §3.2 costs 16 calls per fragment = 2.9 µs — the largest item of the chain | **M** (round 3) — E22 |
| L_ld | S1→L0 loader 26.5 GB/s/core strict-serial | M |
| R_us→s1 | 250 GB/s/core (48–64 KiB tiles) | M |
| R_frac | COPY_FRAC software transform 7 GB/s/core | M |
| R_drain | L0C → US drain **152.8 / 222.3 / 260.3 / 285.5 GB/s/core at mt = 1..4** (1 KB chunks, queue-fenced, content-exact) — 43.6× / 32.2× / 21.2× / 17.4× above the hide thresholds 3.41 / 6.83 / 12.28 / 16.37 (T3r_drain_hidden): hidden at every mt; 268 ns per block in the fixed cost | **M** (round 3) |
| Z | accumulator reset: flags ignored → the **region-difference** epilogue (DESIGN-2 §3.2) is assumed; a found reset mechanism removes 2 lane-ops per score and 96 KiB of US | **U** — DESIGN-2 E11 |
| G(P) | KV read rate at page size P, **measured on the kernel's own path** (E21, 20/20 reps exact): sequential 165.2 / 169.0 / 169.2, shuffled **153.8 / 167.0 / 169.2 GB/s** at 16 / 64 / 256 KiB; per page 793 / 3 101 / 12 391 ns sequential, 852 / 3 140 / 12 394 shuffled → **c_pg = 59 / 39 / 3 ns** (shuffled − sequential; a lower bound: shuffled within a contiguous per-core arena); the attention choreography itself streams at 169.0–169.2, 3.1–3.2 % under the W8 kernel's 174.6 (383 ns per 256 KiB page of per-tile barrier + per-chunk MMA against the 174.6 base) | **M** (round 3) — E21 |
| T_launch | 91 µs launch + queue floor | M |
| L0A, L0B | 64 KB each | M |
| L0C | 256 KB; whole-slab accumulation works | M |
| US | 256 KB/core, ≥ 208 KB evidenced | P/M |
| S1 | ~1 MB | P |
| T_gemv | 398 µs = 67.11 MB / 168.5 GB/s, PROBLEM-3's "die-step class" unit for the attention fraction | DESIGN.md §7.1 |
| σ_s | scalar iteration cost **19.9 ns per compare** (5.1 µs per 256-read tail — 10× the round-2 budget, 42 % of a block, below the 47 ns bind line); the tree's scalar tail is replaced by reduce-max calls (§3.2) | **M** (round 3) — E22 |
| merge | online-softmax merge per block-fragment: **25 750 lane-equivalents** in the validation pack's itemisation (596 ns); this design's own itemisation of §3.1 at the measured per-call costs is 64 851 (1 501 ns; the α reel's 20 small calls dominate); round 2 assumed 7 000 — carried as a hypothesis variable, every round-3 verdict is insensitive to it (T3r_merge_*, T3r_s4_dominated_*) | **M / D** (round 3) |
| c_call | per-call latency of a chained vector op on 1 024 lanes: f16 Mul 46.4 ns, f32 Mul / Add 63.5 / 63.7, exp 272.8, reduce-max 181.9 / 251.4, And<int16> 45.9 — latency-bound upper bounds; the **chained** convention (every call at its latency: f16 1.96, f32 2.69 lane-equivalents per lane) is the round-3 worst corner, the **throughput** convention (40 lanes/cycle, f32 × 1.37) the headline; small 16-lane calls (Duplicate, copies) are costed at one chained f16 call each (A, E22) | **M** (round 3) — E22 |
| G_K1 (round 4) | the attention kernel's OWN fresh-path gather, session 1: **138.3 / 138.7 / 138.0 GB/s** aggregate at 256 / 128 / 64 KiB — page-size-insensitive, c_pg ≈ 0; 18 % under the E21 basis from the diagnostic loop's barrier density; the production loop halves the barriers per byte and its rate is UNMEASURED (between 138 and 169) | **M** (session 1, diagnostic loop) |
| legs (round 4) | the P bounce (erratum #20: an A operand built in vector SRAM rides US → DDR scratch → DDR → S1 → loader): `legs` ∈ {0, 1, 2} transfers of the 16 KiB·mt of P per block charged on the K/V stream's DDR roof — headline 2 (+12.5 %·mt on the t = 1 block), 0 = a proven direct US → S1 route | **UNMEASURED** — E24′ |
| k-shapes (round 4) | f16 (16,16,k) EXACT at every k ∈ {16, 32, 64, 128} (session 1); the i8 k = 64 anomaly is i8-only; issue cost measured at k = 128 only (A4: 15 ns at every k) | **M** (session 1) |
| fresh chunks (round 4) | f16 accumulation into one C chunk corrupts across any full barrier or A re-lift (erratum #19): every C chunk written by exactly one matrix call per visit; C_o = one fresh chunk set per 128-token group, summed on the vector unit; Z, ±Q, NegSnap retired | **M** (session 1) |
| merge (round 4) | the fresh-set merge, itemised: lazy **15 431** lane-eq (357 ns) / rowmax 70 462 (1 631 ns) per 512-token block-fragment at T; 30 300 / 88 372 chained; the pack's 25 750 is retired | **D** (round 4) — T4r_merge |

---

## 0. Summary, ranking, the one measurement

**Ranked #1 (build this): route M — matrix-unit attention over a fractal-packed, page-granular KV cache,
one KV head per core, online softmax in 512-token blocks, K and V streamed DDR→L0B on the measured direct-load
path.** Scores `S[rows × 16 tokens] = Q_frag[rows × d] · K_tile[d × 16]` are one (16,16,128) call per 16
tokens with **K as the B operand** in the f16 analogue of the settled i8 fragment; the drained C block is already
in the A-fragment nesting, so `P = Cast_f16(exp(S − m))` is the next call's A operand with no rearrangement;
`O[rows × d] += P[rows × 128 tokens] · V_tile[128 × 16 d]` is 8 calls per 128 tokens with **V as the B operand**.
rows = t·g (GQA makes the effective M = t·g, not t), ≤ 64 per pass. No O(L) SRAM: every buffer is a function of
(rows, d, block) — §4 lists all of them; the KV cache and its page table are the only O(L) objects and they live
in DDR.

**Why the matrix unit from t = 1** (`[A3-vecroute-*]`, theorem T_gqa_matrix): the vector-dot route costs
4·rows·d lane-ops per token against 4d bytes per token per core of KV, so its time divided by the KV stream time
is **0.505 · rows · ρ32** — 50.5 % at rows = 1, 101 % at rows = 2 (ρ32 = 1), and 404 % at rows = 8. Every GQA
shape (g ≥ 4) has rows ≥ 4 at t = 1: the vector unit is compute-bound by 2–4× before the softmax is even counted.
The matrix route's MMA share is 8.0 % per A fragment (`[A2-block]`).

**Predicted attention-step time, t = 1, headline shape** (round 3: `[R3-t1-*]`, T3r_t1_*; in-kernel; wall = + 91 µs).
Columns = the measured gather rate per page size (E21) plus the W8-kernel ceiling and the retained 3× what-if; each cell is
**chain as specified (§3.2 per-row max, throughput convention) / chained-latency worst corner / fixed-shift variant (§3.4)**:

| L | KV bytes | **64 KiB pages, shuffled 167.0 (design)** | 256 KiB pages 169.2 | 16 KiB pages 153.8 | 174.6 (W8 ceiling, c_pg = 0) | 3× what-if (58.2, c_pg ≈ 6 µs) |
|---|---|---|---|---|---|---|
| 4k | 16.8 MB | **119** / 124 / 112 µs | 118 / 123 / 110 | 128 / 133 / 120 | 115 / 120 / 107 | 307 / 312 / 300 |
| 32k | 134.2 MB | **822** / 828 / 815 µs (163.2 GB/s eff.) | 812 / 817 / 805 | 891 / 897 / 884 | 788 / 793 / 780 | 2 325 / 2 330 / 2 317 |
| 128k | 536.9 MB | **3 233** / 3 239 / 3 226 µs | 3 192 / 3 197 / 3 184 | 3 509 / 3 515 / 3 502 | 3 094 / 3 099 / 3 086 | 9 243 / 9 248 / 9 236 |
| 1M | 4.295 GB | **25 736** / 25 741 / 25 728 µs (166.9 GB/s eff.) | 25 402 / 25 407 / 25 394 | 27 943 / 27 948 / 27 936 | 24 617 / 24 622 / 24 610 | 73 814 / 73 820 / 73 807 |

Every cell is DDR-bound (T3r_t1_binding). The measured chain costs **9 276 ns per 512-token block** (77.2 % of the 12 011 ns
block at 174.6, 73.9 % at 167.0): 16 per-row reduce-max calls 2 910 ns + the exp 2 181 + six f32-class elementwise ops
(difference 2, two casts, shift, sum) 1 559 + the f16 tree 1 102 + the shift reel 928 + the merge 596 (`[R3-chain-rowmax-T-512]`,
T3r_chain) — and **11 836 ns (98.5 %)** if every call runs at its chained latency: the vector unit then keeps 175 ns of slack per
block, so t = 1 is the KV stream on every reading but without margin on the chained one. The round-2 corner "no exp, no
reduction, f32 at half rate" (851 µs) is unreachable: both native ops exist and c_exp = 11.5 clears every round-2 line (56 / 51 /
24 / 19) and the round-3 lines (25.9 / 12.4 / 45.7 at 174.6 for the chain as specified / chained / fixed-shift: T3r_cexp_threshold).
The fixed cost is **18 820 ns** (two vector blocks + a 268 ns drain at the measured rate; round 2: 7 074 with a 4 096 ns drain at
the assumed 10 GB/s), which is why the 4k cell moves +15.6 % and the crossover of §6.3 moves down one block. Fraction of
PROBLEM-3's 398 µs GEMV unit: **0.30 / 2.07 / 8.12 / 64.7** at 4k / 32k / 128k / 1M on the design's page (0.29 / 1.98 / 7.77 /
61.9 at 174.6) — attention is 0.3 of a GEMV at 4k and 2 GEMVs at 32k; beyond ~16k it is the step (§6.3). The round-2 table
(103 / 776 / 3 082 / 24 606 µs stream, 904 page64k, 2 313 gather3x, 851 worst) is superseded cell by cell in `[R3-moved-*]`.

**t = 16** (rows = 128 → two passes of 64 rows; round 3: `[R3-t16-*]`, T3r_t16): **7 057 µs at 32k and 224 ms at 1M** on the
chain as specified — vector-bound 4.6× (27 350 ns per 256-token block against 6 005 ns of DDR), G-independent; 8 360 µs / 265 ms
at chained latencies; **3 162 µs / 100 ms on the fixed-shift variant** (2.0×). Round 2's 1 554 µs / 49.2 ms was DDR-bound because
its native chain cost 12 % of a block. **The single-pass variant S4 is dead** (T3r_s4, T3r_s4_dominated_*): 11 596 µs at 32k at
the pack's merge, and it loses to two passes for *every* merge count on both chains — its 128-token blocks pay the 16 per-row
reduce calls (23 283 ns per block, 7.8× that block's DDR time) twice as often per token; the round-2 question "7 000 or 12 128 or
25 750" is moot. The softmax crossover rows* (vector ≥ KV stream per block) is **32 rows (t ≥ 4 at g = 8)** on the chain as
specified at either convention and **48 rows (t ≥ 6)** on the fixed-shift variant (`[R3-rows*-*]`, T3r_rows_star; round 2 said
112 on its native corner): verify batches are softmax-bound unless the per-block row max goes (§3.4).

Ranking of the routes (expected t = 1 step at 32k, stream branch, and what each needs):

| # | Route | 32k, t = 1 | 1M, t = 1 | Needs | Risk |
|---|---|---|---|---|---|
| 1 | **M (this design): f16 KV, fractal pages, matrix scores + PV, online softmax** | **822 µs** (64 KiB, 167.0) / 812 (256 KiB) / 788 (174.6) | **25.7 ms** / 25.4 / 24.6 | f16 B-fragment geometry (E23); the measured drain, exp, reduce-max and G (round 3); the per-call latencies of §3.2 (E22; chained = the worst corner) | medium-low: one geometry hypothesis; the vector unit at 77–98 % of the block at t = 1, softmax-bound from t = 4 (fixed by §3.4) |
| 1b | M with KV-int8 (per-token i8 K/V, i8×i8→i32 scores, P quantised to i8) — DESIGN-4's dense escape | 612 µs (vector-bound on the chain as specified: the halved stream is under the 9 276 ns chain) / **413 on the fixed-shift variant** (DDR-bound) | 19.0 ms / 12.9 | the settled i8 geometry (no E23), + per-token scale reels (+1 lane-op per score), numerics E27 | medium-high (accuracy) |
| 2 | M with S1-staged K/V through the serial loader (DESIGN-2's regime) instead of direct loads | 26.5 GB/s/core loader on 512 B/token = 19.3 ns/token vs 23.5 DDR → DDR-bound only if the loader overlaps (ping-pong, E13) | — | nothing new, but the measured direct path is faster and already built | low; fallback if direct loads fail E23/E24 |
| 3 | Vector-dot route (K^T layout, lanes = tokens, Muls + Add per d) | 0.505·rows·ρ32 × the KV time: ≥ 2× at g = 4, 4× at g = 8 | — | f32 Mul/Add rates | none; it is the floor at g ≥ 2 |
| 4 | Two-pass softmax (max pass over K, then exp + PV) | +50 % KV bytes at t = 1 (K read twice) | — | — | dead: the online merge costs 596 ns per block (pack) / 1 501 (itemised) against 6 204 ns of re-streamed K at 169.0 (`[R3-online]`, T3r_online: online wins 10.4× / 4.1×; round 2 said 18× at 7 000) |

**E21 is measured** (`[R3-E21-*]`, T3r_E21). The gather rate at the design's 64 KiB page is 167.0 GB/s shuffled / 169.0
sequential: the model's c_pg = 0 cell (174.6) was the W8 kernel's rate, and the attention choreography's own per-tile barrier +
per-chunk MMA cost 3.2 % of it before any page cost (383 ns per 256 KiB page against the 174.6 base); the page cost proper is
39 ns at 64 KiB (3 ns at 256 KiB, 59 ns at 16 KiB), a lower bound (shuffled within a contiguous arena). The "3× slower" risk
(c_pg ≈ 6 µs) is retired to a what-if column; the page size moves the t = 1 cell by −1.3 % (64 KiB vs 256 KiB) and −9.1 % (16 KiB).
No remaining unknown moves the t = 1 headline by more than 0.7 % (the chained-latency corner, T3r_worst_overrun). What the
measurements move is above t = 2: E22's per-call latencies decide the verify-batch regime (§7) and make §3.4's fixed-shift
variant the next measurement (E35). The round-2 model's `t_page = P/21.825 + c_pg` is kept in §1.4 as the fit, re-based on the
measured sequential per-page times.

---
## 1. Cache layout spec (byte level), page geometry, the G(pagesize) model and its experiment

### 1.1 Objects in DDR, per (layer, kv-head h)
Everything attention reads is die-local to the layer (errata #11) and owned by the KV writer of §10.

| Object | Size | Layout | Written by |
|---|---|---|---|
| K pages | ⌈L/P_tok⌉ pages × 64 KiB, P_tok = 65 536/(2d) = 256 tokens at d = 128 (512 at d = 64) | fractal B-operand tiles, §1.2 | per token: 8 × 32 B copies (d = 128) |
| V pages | same count × 64 KiB | fractal B-operand tiles, §1.3 | per completed 16-token group: one COPY_FRAC of 4 KiB from V_tail |
| K_tail, V_tail | 16 × d × 2 B = 4 KiB each, row-major [16][d] | plain rows | per token: one 256 B copy each |
| page tables | one 8 B DDR address per page, per (h, K\|V): 2·⌈L/256⌉·8 B — 16 KiB at 32k, **512 KiB at 1M** for all 8 heads (`[A0-kv-*]`) | flat arrays | runtime allocator (§10) |
| q fragments | mt × 4 KiB f16 A fragments of q/√d for the g query heads of h (rows r = query head, padded to 16·mt) | DESIGN.md §3.2 A pack: byte (c·16 + r)·32 + j'·2 ↔ q[r][16c + j'] | QKV epilogue scatter, or this kernel's prologue by COPY_FRAC (4 KiB·mt at 7 GB/s = 0.6 µs·mt) |
| out | 16·mt × d × 2 B | C-slab order (DESIGN.md §3.3) or row-major via the epilogue | this kernel |

O(L) exists only here, in DDR: KV (4 096 B/token/layer) and the page tables (128 B per 256 tokens per die, 0.012 % of KV — T0_page_table_share; round 1 said 0.4 %). Tokens 0..16⌊L/16⌋−1 are served from pages by the matrix unit; the ≤ 15 newest tokens are served from
K_tail/V_tail by the vector unit (§2.2), so no page is ever read beyond what was written and no masking is needed.
Pages are never zero-initialised and never reallocated: append-only growth (DESIGN-4 §1.3), one new page per
256 tokens.

### 1.2 K page: tokens are the n-columns of the scores GEMM
The scores call is `MMA(C_s, A = Q_frag[16 rows × 128 d], B = K_tile[128 d (k) × 16 tokens (n)], m=16, n=16,
k=128)`: one call per 16 tokens at d = 128. At d = 64 (round 2/3 text — superseded in round 4 below: the f16 sweep licenses one k = 64 call) a single (16,16,64) call was taken to be the **illegal k = 64 shape**
(nondeterministically wrong, HW-MAP), so the call is (16,16,32) twice, accumulating: 2 calls per 16 tokens. B operand geometry,
hypothesis **H-F16**: the f16 fragment is **[16 n × 16 k], column-major, element (k, n) at byte n·32 + k·2** —
the f16 analogue of the settled i8 fragment [16 n × 32 k] at n·32 + k (a column is one 32 B run either way),
and the layout DESIGN.md §3.2 already uses for the f16 A operand. Fragments of one call are k-major and
contiguous (8 × 512 B = 4 KiB per call tile, as in the measured (16,16,128) loop).

K page byte address of element (token l, dim j), l' = l mod 256 (`T_kpage_bijection`):
```
addr_K(l, j) = page(l div 256)                     # 64 KiB page from the K page table
             + (l' div 16) · 4096                  # call tile: 16 tokens
             + (j div 16) · 512                    # k-fragment: 16 dims
             + (l' mod 16) · 32                    # token = fragment column (32 B run)
             + (j mod 16) · 2                      # dim inside the run
```
Append of token l = 8 runs of 32 B at stride 512 B inside call tile (l' div 16): **8 plain COPYs of 32 B**
(ISA-legal, ≤ 64 KB each; c_copy per call is U, budget ≤ 1 µs → ≤ 8 µs per layer-step on the writer core;
one 2D COPY if E25 proves the US→DDR 2D position pair). The i8 variant (route 1b) uses the settled
[16 n × 32 k] fragment: 4 runs of 32 B per token, 32 KiB pages of 256 tokens.

**Round 4 — the k-shape verdict (session 1, M; `[R4-kshape-*]`, T4r_kshape).** The round-2/3 sentence above ("k = 64 is the illegal
shape, so d = 64 uses two (16,16,32) calls, accumulating") was an i8 fact carried onto the f16 tuple: the f16 fragment is 16 dims deep,
so f16 k = 32 is the two-fragment shape and f16 k = 64 the four-fragment shape, and f16 k = 128 had no i8 analogue at all. **The f16
(16,16,k) sweep ran: EXACT at every k ∈ {16, 32, 64, 128}** (128 reps per shape, one-hot k-probes at every k position, all 8 cores) —
the i8 k = 64 anomaly is i8-only, neither fragment- nor element-count-based. Consequences: the d = 128 mainline's one k = 128 call per
16 tokens is licensed as written; a d = 64 variant uses **one k = 64 call** per 16 tokens — and with erratum #19 (§3.1) it must, since
two accumulating f16 calls into one chunk would corrupt; the i8 variant (route 1b) at d = 64 keeps 2 × k = 32 (k = 64 is wrong on i8,
and i8 accumulation across the two calls is the E21-proven safe class). Cost table at d = 64 (calls per 512-token block at mt = 1 /
MMA share; per 256-token block at mt = 4, 4 fragments):

| d = 64 scores shape | calls per block, mt = 1 | MMA share of the 6 005 ns block | calls per 256-token block, mt = 4 | share of 3 002 ns |
|---|---|---|---|---|
| **one k = 64 call (licensed)** | **48** (32 + 16 PV) | **12.0 %** | 96 | 48.0 % |
| 2 × k = 32 (the i8 variant's shape) | 80 | 20.0 % | 160 | 79.9 % |
| 4 × k = 16 | 144 | 36.0 % | 288 | 143.9 % — MMA-bound |

The issue cost (15 ns per call) was measured at k = 128 only; the k = 64 and k = 16 calls are costed at the same 15 ns (ASSUMPTION A4,
UNMEASURED — a k-dependent issue cost would move only the d = 64 rows).


### 1.3 V page: tokens are the k-rows of the PV GEMM
The PV call is `MMA(C_o[16 rows × 16 d], A = P_frag[16 rows × 128 tokens], B = V_tile[128 tokens (k) × 16 d (n)],
16,16,128)`: 8 calls per 128 tokens at d = 128 (4 at d = 64), each over one n-group of 16 dims. Under H-F16 a
token is a k-index: its 16 values inside a fragment sit **2 B apart at stride 32 B** — the inherent transpose
of putting the contraction index on the fragment column. Address (`T_vpage_bijection`):
```
addr_V(l, j) = page(l div 256)
             + ((l' div 128) · 8 + j div 16) · 4096   # call tile: 128 tokens × 16 dims (two 32 KiB halves per page)
             + ((l' mod 128) div 16) · 512            # k-fragment: 16 tokens
             + (j mod 16) · 32                         # dim = fragment column
             + (l' mod 16) · 2                         # token inside the run
```
A per-token scatter would be 128 two-byte writes; instead V is appended row-major into V_tail ([16][d], one
256 B copy) and **every 16th token one COPY_FRAC turns the full 4 KiB row-major block [16 tokens][128 d] = a
[K = 16][N = 128] row-major source into its 8 fractal fragments** — exactly the transform COPY_FRAC implements
(row-major [K][N] → F = [N/16][K][16]), 4 096 B at the measured 7 GB/s = **585 ns** (`[A6-kvwrite]`), amortised
37 ns per token-layer. The 8 fragments land in 8 different call tiles ((l' mod 128) div 16 fixed, j div 16
= 0..7): 8 copies of 512 B, or the COPY_FRAC's own destination stride if it supports one (E25 differences both).

### 1.4 Why pages of 64 KiB, and the G(P) model
P_bytes is the design variable. The stream figures (180 GB/s DDR→S1, 181.3 direct) were measured on
**per-core contiguous slabs read in 64 KiB pieces**; a 64 KiB page read by one core is that pattern at the DRAM
(a 64 KiB burst spans every channel and bank group; LPDDR row buffers are 2–4 KiB, so locality inside a page
is the same as inside a stream). What a page boundary adds is a per-page fixed cost on the load engine (address
fetch from the page table, a new descriptor, possibly a DRAM page miss on the first burst): **c_pg**. Model
(`[A1-G-*]`, T1_gather_cells):
```
t_core(P) = P / 21.825 GB/s + c_pg          # one core, one page
G(P)      = 8 · P / t_core(P)                # all 8 cores streaming their own pages
```
| P | 4 KiB | 16 KiB | 64 KiB (design) | 256 KiB | 1 MiB |
|---|---|---|---|---|---|
| c_pg = 0 | 174.6 (175.2 floored) | 174.6 (174.7 floored) | **174.6** | 174.6 | 174.6 |
| c_pg = 0.5 µs | 47.6 | 104.8 | **149.7** | 167.6 | 172.8 |
| c_pg = 2 µs | 14.9 | 47.6 | **104.8** | 149.6 | 167.6 |
At c_pg = 0 the exact rate is 174.6 at every P (T1_gather_exact); the 175.2 / 174.7 cells are floor artifacts of
the integer model. The "gather 3× slower" risk of PROBLEM-3 (58.2 GB/s) is c_pg = 6 µs at 64 KiB or 0.37 µs at 4 KiB: a 4 KiB
(16-token) page — the usual serving-runtime page — is DDR-stream-equivalent only if c_pg < 20 ns, which no
descriptor-driven engine achieves; **the page size is the lever**, and the probe sweeps it.

**Round 3 — E21 measured** (`[R3-E21-*]` `[R3-page-*]`, T3r_E21, T3r_page_sizes, T3r_page_tier). The probe ran on the kernel's own
path (DDR→L0B direct, full barrier per 32 KiB tile, one (16,16,128) MMA per 16-n-chunk, US-staged page table, 64 MiB per-core
arenas; 20/20 reps exact in both visit orders):

| P | sequential G (per page) | shuffled G (per page) | c_pg = shuffled − sequential | the same page against the 174.6 base | t = 1, 32k / 1M (chain as specified) |
|---|---|---|---|---|---|
| 16 KiB | 165.2 (793 ns) | **153.8** (852 ns) | 59 ns | 102 ns | 891 µs / 27.9 ms |
| 64 KiB (design) | 169.0 (3 101 ns) | **167.0** (3 140 ns) | 39 ns | 138 ns (> the 123 ns MoE-128k flip line of round 2) | **822 µs / 25.7 ms** |
| 256 KiB | 169.2 (12 391 ns) | **169.2** (12 394 ns) | 3 ns | 383 ns | 812 µs / 25.4 ms |

Three things the table settles. (i) The model's base is not 174.6: the attention choreography's sequential rate is 169.0–169.2 at
every size (21.16 GB/s per core), 3.2 % under the W8 kernel — the per-tile barrier and the per-16-n-chunk MMA of this kernel's
loop, not a page effect; the round-2 model is re-based as `t_page(P) = T_seq(P) + c` on the measured T_seq (`G_page3`). (ii) The
page cost proper is small and shrinks with P (59 / 39 / 3 ns; HW-MAP rounds the 64 KiB figure to 38) and it is a **lower bound**:
the shuffle stays inside a contiguous per-core arena, a real scattered cache can show more. (iii) The verdict by size: 64 KiB is
1.3 % under 256 KiB, 16 KiB is 7.9 % under 64 KiB and 9.1 % under 256 KiB (T3r_page_sizes); the tail waste per layer-sequence is
0.25 / 1.00 / 4.00 MiB. **Recommendation (§10): 256 KiB pages by default; 64 KiB where the serving allocator's granule forces it
(−1.3 %); never 16 KiB.** The two-tier scheme of ALTERNATIVES §2.5 (1 MiB extents + 64 KiB tails) is re-evaluated on the measured
base (`[R3-page-cpg*]`, T3r_page_tier): at the measured c = 39 ns it reaches 169.1 against 166.9 for 64 KiB pages (+1.3 %) and
168.7 for 256 KiB pages at the same per-page cost (the measured 256 KiB page costs 3 ns: 169.2) — the whole prize of the second
tier is the 1.3 % that 256 KiB pages already capture without compaction or a second table; it pays ≥ 5 % only if a real scattered
cache shows c_pg ≥ 160 ns at 64 KiB (`[R3-page-tier-rule]`; 4.1× the measured lower bound: +3.2 % at 100 ns, +6.1 % at 200,
+15.1 % at 500 — the ALTERNATIVES figure of −13.2 % assumed c_pg = 0.5 µs). Two-tier stays the contingency for that case, not the
design. **The design constraint E21 exposes (T3r_fleet_G_moe_128k_*, T3r_fleet_moe_128k_cells, T3r_moe_128k_direction):** the
DESIGN-4 MoE-128k cell is attention-bound iff G ≤ 168.3 on the chain as specified (167.9 fixed-shift, 168.6 chained; round 2's
167.7 used the 7 074 ns fixed cost) — at the 64 KiB shuffled page (167.0) it is **attention-bound** on every chain (by 25.7 /
18.2 / 30.8 µs = 0.8 / 0.6 / 1.0 % of the 3.21 ms layer: the bare stream, 256 × 12 557 = 3 214 592 ns, already exceeds the layer's
3 207 719), at 256 KiB (169.2) weights-bound by 16.0 / 23.5 / 10.9 µs (0.5 / 0.7 / 0.3 %), at 16 KiB attention-bound by 9.4 %, at
the 174.6 ceiling weights-bound by 3.6 %. HW-MAP's reading "MoE-128k stays stream-bound at 64 KiB by 0.7 GB/s" has the inequality
backwards: `T_fleet_G_moe_128k` says attention-bound iff G ≤ 167.7, and 167.0 is below that line. The cell is a tie at the
measurement's resolution: the page size is a ±1 % lever and a real scattered cache makes the margin negative at every size — the
levers with margin are K-int8 / KV-int8 (bytes × 3/4 or 1/2) on the fixed-shift chain of §3.4.

**E21 (the gather-rate probe; §8 has the full spec).** 8 cores, each reading 2 048 pages of P_bytes placed at
pseudo-random 64 KiB-aligned addresses inside a 4 GiB arena (far beyond any cache), through the exact path the
kernel uses (DDR→L0B direct, full barrier per tile, then one (16,16,128) MMA per call tile accumulating into
one C region), for P ∈ {4, 16, 64, 256, 1024 KiB} and a sequential control. Each page's content is an
integer pattern whose per-column sums depend on the page index; the drained C must equal the host's sum of the
visited pages exactly (i32 on the i8 build, f32-exact small integers on the f16 build). c_pg is the slope of
(time per page) against 1/P; the differencing is the pattern itself (a skipped, repeated or stale page changes
the total). The kernel's G is then read off at the runtime's chosen page size. **What E21 decides for the fleet**
(round 2, T_fleet_G_*, iff over every G ≤ 174.6): a DESIGN-4 cell is attention-bound iff G ≤ 7.3 GB/s (dense 32k),
29.4 (dense 128k), 41.9 (MoE 32k), **167.7 (MoE 128k)** — the MoE 128k cell flips already at c_pg ≥ 123 ns at 64 KiB
pages (the page64k and gather3x branches both flip it, neither flips MoE 32k); both 1M cells are attention-bound
at every G. Round 3: measured — see the block above; with the measured fixed cost the lines are 7.3 / 29.4 / 42.0 / 168.3
(T3r_fleet_G_*), and the 64 KiB shuffled page (167.0) sits on the attention-bound side of the MoE-128k line.

### 1.5 Memory accounting per die (headline shape, one layer)
KV = 4 096·L B (+ 64 KiB of tails and 16 B per 256 tokens of tables): at 1M, 4.295 GB per layer. The
die-level feasibility (layers × KV + weights ≤ 86 GB) is DESIGN-4's T3/T4 and is not restated. The i8
variant halves KV and adds 4 B of scale per token per K and per V page row (§9).

---

## 2. Pipeline design per engine, t = 1 and t ≤ 16

### 2.1 Work decomposition
Work unit = (kv-head h, block b of 512 tokens). With H_kv = 8, **core c ↔ head c** for the whole step: no
cross-core traffic and no reduction (the 174.6 figure was itself measured as 8 equal per-core streams, so no
single-core ceiling enters). Per core and block: 256 KiB of K + V (`[A0-shape]`), 12 011 ns at R_gemm
(`[A2-block]`, T2_block). If 8 ∤ H_kv the units are distributed round-robin over cores (a head's L-range split
across cores; ±1 block imbalance = ±12 µs) and the per-core (m, S, O) partials are merged by the consumer
(§9, H_kv = 1). rows = t·g query rows per core; mt = ⌈rows/16⌉ A fragments; **rows ≤ 64 per pass**
(L0A budget §4), passes = ⌈rows/64⌉ — at t = 16, g = 8 the KV is streamed twice (§2.4 for the one-pass variant).

### 2.2 Engine roles (steady state, one block, one pass; `[A2-block]`, `[A2-vec-*]`)

| Engine | Work per block of 512 tokens (per core, mt fragments) | Time | Share of the 12 011 ns block (174.6 basis; 12 557 ns on the measured 64 KiB page) |
|---|---|---|---|
| **direct-load (copy-in)** | 4 K tiles + 4 V tiles of 32 KiB DDR→L0B, one full barrier each (the measured choreography); stream order K_b, V_{b−2}, K_{b+1}, V_{b−1}, … (V lags K by **two blocks**, §5) | 262 144 B / 21.825 GB/s = **12 011 ns** at the 174.6 basis; **12 557 ns** measured on the 64 KiB shuffled page (12 394 at 256 KiB, `[R3-E21-block]`) | 100 % — the roof |
| **matrix** | scores: 32 calls × mt (one per 16 tokens, A = ±Q_f, B = K call tile); PV: 32 calls × mt (8 per 128 tokens, A = P_f, B = V call tile) | 64·mt × 15 = **960·mt ns** | 8.0 %·mt |
| **vector** | drain C_s(b) 32 KiB·mt → US; difference with the stored negated snapshot (Z); block row max (f16 tree + 16 reduce-max calls); shift reel + shift; exp; Cast → P fragments (16 KiB·mt f16); f32 sum accumulate; merge of block b−2's PV partial (drain 8 KiB·mt, difference, α-scale, add) | round 3, measured ops (§3.2): **9 276·mt ns** (throughput convention) … **11 836·mt ns** (every call at its chained latency); fixed-shift variant (§3.4) 5 530·mt ns; round 2: 1 489·mt (c_V = 7, ρ32 = 1) … 12 839·mt (c_V = 33, ρ32 = 2) | **77.2 %·mt … 98.5 %·mt** (fixed-shift 46.0 %·mt); round 2: 12.4 … 106.9 |
| **copy US→S1** | P fragments 16 KiB·mt (plain, 4 KiB pieces) | 16 384·mt / 250 GB/s = 66·mt ns (+ per-copy issue, U) | 0.5 % |
| **loader** | L0LOAD P: 4 × 4 KiB·mt S1→L0A | 16 384·mt / 26.5 = **618·mt ns** (serial) | 5.1 %·mt |
| **L0C drain** | 40 960·mt B (C_s 32 KiB + C_o 8 KiB) through the staged read | hidden iff **R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1 / 2 / 3 / 4** (T2_drain_threshold, an iff: 80 / 160 / 288 / 384 B per token); **measured 152.8 / 222.3 / 260.3 / 285.5** (round 3, T3r_drain_hidden, T3r_drain_cells): 268 / 368 / 283 / 344 ns per block, 43.6× / 32.2× / 21.2× / 17.4× under the line | 2.2 / 3.1 / 4.7 / 5.7 % on its own engine, hidden; the exposed-drain rows of round 2 (10 GB/s, 34.1 %·mt) are retired |
| **scalar** | 4 page-table lookups; barrier issue — the 256-compare tree tail of round 2 is replaced by 16 reduce-max calls on the vector engine (at the measured σ_s = 19.9 ns the scalar tail would be 5 094·mt ns = 42.4 %·mt, the reduce calls are 2 910·mt ns: T3r_sigma) | < 1 µs | ~0 |
| **copy-out** | nothing per block; per step: out 4 KiB·mt, K append 8 × 32 B, V_tail row 256 B, every 16th token the 4 KiB V fractal tile | < 2 µs per step | ~0 |

Per step, fixed (`fixed=` in `[R3-t1-*]`, T3r_fixed): the first block's softmax latency before the first PV plus the last
block's softmax + drain + merge after the stream ends = 2 vector blocks + 1 drain (**18.8 µs** on the chain as specified,
23.9 µs chained, 11.3 µs fixed-shift; round 2: 7.1 µs best corner, 29.8 worst), the vector tail of the ≤ 15 newest tokens (scores and PV as 16-row Muls+Adds over K_tail/V_tail:
≤ 122 880·mt lane-ops = ≤ 5.7 µs·mt at ρ32 = 2, 0 when 16 | L, `[A6-kvwrite]`), and the launch floor (91 µs,
reported separately as wall). The in-kernel ceiling of the design is the KV stream itself: effective KV rate at
1M = 166.9 GB/s on the design's page (169.1 at 256 KiB), at 32k 163.2 (the fixed 19 µs), at 4k 140.7 (`[R3-t1-*]`; round 2:
174.6 / 173.0 / 162.6 at the 174.6 basis with a 7 µs fixed cost).

**Round 4 — what the engine table becomes with fresh chunk sets and the P bounce** (`[R4-bounce-*]` `[R4-drain-*]` `[R4-lift-density]`,
T4r_bounce, T4r_drain, T4r_lift; per 512-token block, mt fragments, per core):

| Engine | Round-4 work per block | Time | Status |
|---|---|---|---|
| **direct-load (copy-in)** | 4 K + 4 V tiles of 32 KiB as before, **plus the DDR → S1 staging leg of the P bounce** (erratum #20: the P fragments cast in US cannot be copied US → S1; they go US → DDR scratch → DDR → S1 → loader): 16 KiB·mt per block | K/V 256 KiB per core at G, + `legs` × 16 KiB·mt on the same DDR roof: **13 512·mt-independent K/V + 1 501·mt ns at 174.6** per leg — 12 011 / 12 761 / **13 512** ns at legs 0 / 1 / 2 (mt = 1); 13 943 (169.2) / 14 127 (167.0) / **17 059 (138.3, the session-1 loop)** at legs 2 | **UNMEASURED** (the bounce's cost on the shared roof; legs = 2 is the headline, the conservative reading; a proven direct US → S1 route is legs 0 = the round-3 cell) |
| **copy-out (US → DDR)** | the write leg of the P bounce: 16 KiB·mt per block in 4 KiB pieces | counted in `legs` above; rate UNMEASURED | UNMEASURED |
| **loader** | L0LOAD P: 4 × 4 KiB·mt S1 → L0A, between direct-load barriers — **the S1-resident exposure the review named**: 16 KiB per 256 KiB of direct loads at mt = 1 (1/16), 32 KiB per 128 KiB at mt = 4 (1/4) = **2× / 8×** the expert kernel's 2 KiB per 64 KiB lift density | 618·mt ns (serial) | E24 at the real P cadence (mt = 1 and 4) |
| **matrix** | unchanged at d = 128: 32·mt scores + 32·mt PV calls, every C chunk written by exactly one call (no accumulate); d = 64: 48 calls per block (§1.2) | 960·mt ns | M (k-shapes), erratum #18: every C destination addressed by explicit byte-offset tensor construction, never by view slicing |
| **L0C drain** | C_s 32 KiB·mt + **every fresh C_o set of the block: 4 × 8 KiB·mt = 32 KiB·mt** (round 3: one 8 KiB·mt C_o region) = **64 KiB·mt** (32 KiB·mt at 256-token blocks) | hidden iff R_drain ≥ **5.5 / 11.0 / 16.4 / 21.9 GB/s/core** at mt = 1..4 (iff, T4r_drain; round 3: 3.41 … 16.37); measured 152.8 … 285.5: **428 / 589 / 377 / 459 ns** per block, 27.7× … 13.0× under the line | M (rates) / PROVED (threshold) |
| **vector** | the round-4 chain (§3.2): no Z difference, the fresh-set merge, the lazy guard | lazy-T **4 772·mt ns** (35.3 % of the legs-2 block at 174.6, 39.7 % at legs 0), lazy-C 5 867, rowmax-T 9 791 (72.5 / 81.5 %), rowmax-C 12 265 (90.8 / **102.1 %** — vector-bound at legs 0) | **OPEN** (the softmax-reel anomaly) |
| **scalar** | 4 page-table lookups, barrier issue, the lazy guard's 8 reduce results read through the queue fence (erratum #15), the per-trip branch | < 1 µs; a trip ≈ 10.7 µs (§3.4) | — |

Per step, fixed (`[R4-fixed-*]`, T4r_fixed): **19 328 ns on the lazy chain at t = 1** = 2 vector blocks (9 544) + the 428 ns drain + the
16-token vector tail (4 156 — under append-then-attend the step's own token is always in the tail, so every 512-multiple carries a full
16-token tail, §10.1) + **the first-block per-row max (5 200 ns: cast, tree, 16 reduce calls, reel — the item the review found missing
from T3r_fixed)**; 26 831 chained, 24 166 / 33 119 on the rowmax chain. Round 3's 11 328 made the lazy cells 0.6 % optimistic at 32k and
4 % at 4k.


### 2.3 When the matrix unit wins, and the DESIGN.md shapes it reuses
T_gqa_matrix (`[A3-vecroute-*]`): vector-dot route (K and V laid out dim-major so lanes index tokens: per dim
one Muls by the query scalar and one Add into the 1024-lane score accumulator; PV mirrored) needs 4·rows·d
lane-ops per token; the KV stream delivers 4d bytes per token per core at 21.825 GB/s; the ratio is
rows·ρ32·4·d·R_gemm/(80·512·R_vec) = **0.505·rows·ρ32**. The matrix unit therefore wins at rows ≥ 2 (ρ32 = 1)
or rows ≥ 1 (ρ32 = 2); GQA puts rows = g ≥ 4 at t = 1. This design uses DESIGN.md's loop unchanged where it
applies: the (16,16,128) call sequence with c_mma = 15 ns (HW-MAP, measured in the W8 kernel), the 32 KiB
direct-load tiles with a full barrier each (HW-MAP: "the full barrier is the ONLY working fence for direct GM
loads"), the A fragment pack §3.2 (q and P), the C drain order §3.3 (row r of column-group i at byte
(i·16 + r)·64 — the nesting that makes the drained scores the next A operand), and the epilogue cast. What is
new: K and V as B operands with tokens on the n (scores) and k (PV) axes, the three-region C_s rotation, and
the vector softmax between the two GEMMs.

### 2.4 t ≤ 16: rows = t·g, the pass rule and the S4 variant
Every per-block term except DDR scales with mt (table above); DDR scales with passes. At g = 8: t = 1 → mt = 1;
t = 2 → 1 (16 rows, no padding waste); t = 4 → 2; t = 8 → 4 (one pass, L0A = ±Q 32 + P 2 × 16 = 64 KiB exactly full — T_buffers_l0a, not 48 —, blocks of
256 tokens, L0C exactly full — §4); t = 16 → rows = 128 → **two passes** of 64 rows, KV read twice: **7 057 µs at
32k on the measured chain** (`[R3-t16-32k-shuf64k-rowmax-T]`, T3r_t16 — vector-bound 4.6×, G-independent; 3 162 on the fixed-shift
variant; round 2's 1 554 was DDR-bound at 172.8 GB/s because its native chain cost 12 % of a block).
**Variant S4** (one pass, mt = 8): L0A holds Q 32 KiB (no ±Q alternation) + one single-buffered P buffer of
32 KiB per 128 tokens = **64 KiB exactly**, L0C holds two C_s regions of 64 KiB and two C_o regions of 64 KiB = **256 KiB exactly** (T_buffers_s4), blocks
shrink to 128 tokens. The loader→MMA chain per 128 tokens is serial: 32 KiB at 26.5 = 1 236 ns + 64 PV calls
× 15 = 960 ns = **2 196 ns against 3 002 ns of DDR per 128 tokens (73.2 %)** (`[A4b-onepass-chain]`,
T4_s4_chain) — DDR-bound on that edge, but every per-fragment call (16 reduce-max, the 20-call shift reel, the merge) now recurs every
128 tokens and the vector unit is the wall: **11 596 µs at 32k and 368 ms at 1M** on the measured chain (`[R3-t16-*]`, T3r_s4 —
1.64× WORSE than two passes; round 2's 1 032 µs assumed a 7 000-lane-op merge and a 1-lane-op exp), and T3r_s4_dominated_* proves
S4 loses to two passes for every merge count on both chains: **S4 is retired in round 3** (the geometry stays documented). It was
gated on E24 (an L0A filled to exactly
64 KiB — the L0C "exactly full" erratum was cleared, L0A is unprobed) and loses the ±Q drift bound (it uses the
i8 variant's exact i32 difference or E11's reset).

**Round 4 — the pass cap and S4 with fresh chunk sets.** Without −Q (the ±Q alternation is retired, §3.1) L0A holds Q 4 KiB·mt + a
double-buffered P set 8 KiB·mt = **12 KiB·mt: 48 KiB at mt = 4, no longer exactly full** (T4r_l0a; the "L0A exactly-full at mt = 4 is
unprobed" item is moot), and mt = 5 (60 KiB) would fit L0A — the 64-row pass cap now comes from **L0C**: at 256-token blocks mt = 5 needs
3 × 80 + 2 × 40 = 320 KiB (T4r_l0c), and the only block that fits mt = 5 is S4's 128-token block. S4 itself stays dominated on the
round-4 chain: at the fresh-set merges 2 680 vs 2 565 µs at 32k on lazy-T (+4.5 %), 13 096 vs 7 756 on rowmax-T (+68.8 %), for every
merge count on rowmax and for every merge ≥ 640 lane-eq on lazy (the fresh-set merge at its block is 7 014; below 640 the DDR-bound
two-pass cell would lose by ≤ 30 µs — a regime no itemisation reaches): T4r_t16, T4r_s4_dominated_rowmaxT, T4r_s4_dominated_lazyT,
T4r_s4_cells. Keep two passes.


---

## 3. Softmax strategy

### 3.1 Online, block-wise, with the rescale applied to the drained partial — never to L0C
L0C cannot be rescaled (no US→L0C write path; the matrix unit only accumulates), so a running output cannot
live in L0C across blocks. The design keeps the running state in US — per row r: max m_r (f32), partial sums
S_r (16 f32 lanes, reduced once at the end), running output O_r[d] (f32) — **O(rows·d) = 8 KiB·mt** — and lets
each block accumulate its own PV partial `O_b = P_b·V_b` in a fresh L0C region, with P_b = exp(S_b − m_b^new)
relative to the running max *after* the block. Merge per block (vector; round 3: **25 750·mt lane-equivalents = 596 ns** in the validation pack's itemisation, and 64 851 =
1 501 ns in this design's own itemisation at the measured per-call costs — α exp 272.8 ns + the α reel's 20 small calls 928 ns +
O over 4 × 2 048 f32 lanes 260 ns + S 41 ns, `[R3-merge-*]`, T3r_merge_item; round 2 assumed 7 000: T3r_merge_threshold_* shows the
t = 1 block stays DDR-bound at 174.6 for every merge ≤ 143 937 (chain as specified) / 33 345 (chained) / 305 730 (fixed-shift),
and T3r_s4_dominated_* that S4 loses for every count — the 12 128-vs-25 750 question is moot): `α_r = exp(m_r^old − m_r^new)` (16·mt lanes), `O ← α·O + (C_o(b) − snapshot_o)`, `S ← α·S + Σ_b`.
Exact: Σ_l p_l v_l with a common shift per row telescopes over blocks (T_online_exact, a finite-sum identity).

**Online vs two-pass** (`[R3-online]`, T3r_online): two-pass avoids the merge but re-streams K for the max pass:
+6 204 ns of DDR per block (128 KiB of K per core at the measured 169.0) against a 596 ns merge (pack) / 1 501 (itemised) — online
wins **10.4× / 4.1×** at every L and t (round 2 said 18× at 7 000 lane-ops); the L-regime boundary PROBLEM-3 asks for does not exist for this design (both costs are per
block, L cancels — T_online_L_independent).

**Round 4 — fresh chunk sets replace the region difference (erratum #19, M; `[R4-l0c-*]` `[R4-merge-*]`, T4r_l0c, T4r_merge).**
Session 1 measured that **f16 accumulation into one C chunk corrupts across ANY full pipe barrier or A-operand re-lift** — broken at
≥ 2 accumulations even with interleave ≥ 16, while the i8 tuple tolerates the same pattern (the E21 probe accumulated per n-chunk across
all tiles: a spacing-8, depth-8192 same-destination i8 chain, exact 20/20 — the review's open question about E21's structure is
**CONFIRMED as the i8 existence proof; f16 does not inherit it**). The review's spacing fixes (item 2: alternate the two k-halves, interleave
scores and PV calls per tile pair) are therefore MOOT on f16: there are no accumulate chains at all. **Every C chunk is written by exactly
one matrix call per visit.** The scores already were (one (16,16,128) call per 16-token chunk at d = 128; at d = 64 the single k = 64
call of §1.2); the PV partials become **one fresh chunk set per 128-token group** — the 8 calls of a group write its 8 chunks ([16 rows]
[16 dims] f32 each, 8 KiB per fragment) and nothing accumulates across groups: 4 sets per 512-token block (2 at 256, 8 at 1 024). The
accumulator budget fits: L0C = 3 C_s regions + the block's fresh C_o sets = **128 / 256 / 192 / 256 KiB at mt = 1 / 2 / 3 / 4** (round 3:
112 / 224 / 192 / 256; exactly full at mt = 2 and 4, so the C_o sets are single-buffered there — the drain of block b's sets must retire
before block b + 1's first PV call, edge A10′ of §5; at mt = 1 double-buffering them costs 160 KiB). The partials are summed on the vector
unit: **O_b = Σ_g partial_g (block-local), then O ← O + O_b** — two-level on purpose, so that the longest sequential f32 chain feeding O is
O(L/block), not O(L/128) (§3.3). With fresh sets there is no region content: **no NegSnap, no ±Q, no snapshot copy, no drift of the
accumulator** — the Z branch, E11's reset question and the 96 KiB of US it cost are retired; the drained scores are the scores (the
2-op difference leaves the chain).

The merge is re-costed (a new ledger row): per block-fragment, lazy = O_b over the 4 partials (4 × 2 048 f32 lanes, the first a copy
costed as an op) + O += O_b (2 048) + the S fold (512 + 256) and running add (256) = 11 264 f32 lane-ops = **15 431 lane-eq = 357 ns** at
the throughput convention (round 3's itemised lazy merge was 9 820 with the snapshot difference; the pack's 25 750 no longer applies
to any chain); rowmax adds α = exp (1 call), the α reel (20 small calls), the O scale (2 048) and the S scale (256): **70 462 lane-eq =
1 631 ns**; chained 30 300 / 88 372. At 256-token blocks (2 partials) the lazy merge is 9 820 — the same count as round 3's itemisation.
The merge stays a hypothesis variable in the iff theorems (T4r_merge_threshold): t = 1 is DDR-bound at 174.6 with the bounce iff
merge ≤ 393 019 (lazy-T) / 142 261 (rowmax-C) lane-eq, without it iff ≤ 328 176 / 77 418 — the fresh-set rowmax-C merge (88 372) exceeds
the legs-0 line, which is the review's "flips vector-bound at the itemised merge" (it said 77 354 vs 56 932 at 167.0 on the round-3
chain). What the fresh sets cost on the drain: 32 KiB·mt of C_o per block instead of 8 (§2.2, hidden with 13–28× margin).


### 3.2 The per-block vector chain (every op is in ISA.md's list; nothing else is assumed)
Drained C_s block = [32 token-groups][16 rows][16 tokens] f32 = 8 reels of 1 024 lanes (mt = 1).
1. **Difference (Z branch):** `S = D_b + NegSnap[region]` (1 Add) and `NegSnap ← Muls(D_b, −1)` (1 Muls) —
   the region-difference epilogue of DESIGN-2 §3.2 in f32; with ±Q alternation per region visit the region
   content is a signed sum whose magnitude stays within ~√(blocks/3)·|s|_max (random-walk HYPOTHESIS measured by E26 — T_drift_1M: 683 visits per region, √683 × 32 = 832 ≈ 840 → f32 ulp
2⁻¹⁴ = 6·10⁻⁵ on a score, 10⁻⁴ class on p; the deterministic worst case over every sign pattern is 683 × 32 = 21 856
→ ulp 2⁻⁹ ≈ 2·10⁻³, T_drift_alt). 2 lane-ops per score.
2. **Row max (round 3, measured ops).** The reduce-max EXISTS (f16 181.9 ns / f32 251.4 ns per call, one value per call),
   but it reduces a whole call and the drained layout interleaves the 16 rows at 16-lane granularity — a per-row max still needs
   the elementwise tree to fold the 8 reels to one [16 rows][16] reel first. And<int32> is ABSENT, so the f32 6-op identity
   `max(a,b) = 0.5·(a + b + |a − b|)` is closed; the chain casts S to f16 (1 op; exact for the max, rounding is monotone) and
   runs the tree in f16 with And<int16> (45.9 ns): 7 pair-ops of 1 024 lanes + 2 of 512 / 256 = 47 616 lane-ops (5.8 per score),
   then **16 reduce-max calls of 16 lanes each (one per row) = 2 910 ns per fragment** instead of the 256-compare scalar tail
   (5 094 ns at the measured σ_s = 19.9 ns, T3r_sigma). The reduce calls are the largest item of the chain (24 % of a block per
   fragment); at t = 1 the 8 padding rows need none (7 820 ns, `[R3-chain-rowmax-t1-8calls]`) — the headline keeps the 16-call
   fragment accounting, which holds for every t. The shift reel of step 3 (16 Duplicate + 3 copies ≈ 20 small calls) is costed
   at one chained f16 call each (928 ns per fragment, ASSUMPTION A3 — E22). Round 2's text (tree in f32 + scalar tail) follows
   as the record of the branch.
3. **Shift:** `X = S + ShiftReel` (1 Add), ShiftReel = [row constants −m_r^new repeated per 16-lane run],
   built per block by 16 Duplicate calls of 16 lanes + 3 copies (≈ 20 small calls, A).
4. **exp (round 3: native, measured).** f32 exp at 272.8 ns per 1 024-lane call = **11.5 lane-equivalents per element**
   (2 181 ns per fragment), bitwise-exact against the host on x ≤ 0 (f32 maxRel 6.3·10⁻⁸); it beats the polynomial (22 ops) and
   clears every threshold (T3r_cexp_clears). The polynomial that follows is RETIRED — kept as the record of the no-exp branch.
   **Poly** (no exp instruction):
   `y = max(X, −22)` (6 ops — without the clamp the Taylor base misbehaves below −22 and 7 squarings blow it to
   inf), `y ← y/128` (1 Muls), Horner degree 4 `((((y/120 + 1/24)·y + 1/6)·y + 1/2)·y + 1)` (4 Mul + 4 Adds),
   then **7 squarings** (7 Mul): **22 lane-ops**, relative error ≤ 2⁷·(22/128)⁵/5! = **1.6·10⁻⁴** (Taylor
   remainder on [−0.172, 0] amplified by the squarings; f32 rounding 2⁷·6·10⁻⁸ = 8·10⁻⁶; T_poly_bound) —
   inside the 10⁻³ class. Values below −22 clamp to e⁻²² = 2.8·10⁻¹⁰ (f16 flushes them to 0 anyway).
5. **Cast f32→f16** (1) — P in f16 is exact to 2⁻¹¹ relative at p ≤ 1; the only f16 object in the chain is an
   MMA input, never an accumulator (errata #5 cannot bite: sums and O stay f32).
6. **Sum:** `Acc += P_f32` (1 Add per score into a 1 024-lane f32 accumulator; folded 4→1 per block and 16→1
   per row at the end — a fixed reassociation, exact in exact arithmetic; the f32 order is fixed and E27 checks it).
c_V per (score, row), all 16 rows of a fragment processed (padding rows included — the drained layout
interleaves rows at 16-lane granularity, so a 2D row-selective drain is the only way to skip them, §9):

| branch | difference | max | shift | exp | cast | sum | **c_V** | `[A2-vec-*]` at ρ32 = 1 / 2 (block share) |
|---|---|---|---|---|---|---|---|---|
| native exp, native max | 2 | 1 | 1 | 1 | 1 | 1 | **7** | 12.4 % / 24.8 % |
| native exp, tree max | 2 | 6 | 1 | 1 | 1 | 1 | **12** | 20.3 % / 40.6 % |
| poly exp, native max | 2 | 1 | 1 | 22 | 1 | 1 | **28** | 45.5 % / 91.1 % |
| poly exp, tree max (**ISA.md as written**) | 2 | 6 | 1 | 22 | 1 | 1 | **33** | 53.4 % / **106.9 %** |

T3_t1_ddr_bound: the t = 1 block is DDR-bound iff (8 192·c_V + 7 000)·ρ32·10/432 ≤ 12 011, i.e. c_V ≤ 62
(ρ32 = 1) or c_V ≤ 30 (ρ32 = 2) (`[A4b-cV-threshold-*]`). Three of the four branches pass at either rate; the
ISA-as-written branch passes only at the full f32 lane rate. A native exp keeps t = 1 DDR-bound iff c_exp ≤ 56 / 51 (native / tree max) at ρ32 = 1 and ≤ 24 / 19 at ρ32 = 2
(T3_cexp_threshold; c_V = c_exp + R + 5); it beats the 22-op polynomial iff c_exp ≤ 21.

**Round 3 — the measured chain per 512-token block-fragment** (`[R3-chain-*]`, T3r_chain, T3r_chain_shares; lane-equivalents at
43.2 G/s; "T" = throughput convention with f32 at the measured ρ32 = 1.37, "C" = every 1 024-lane call at its chained latency):

| item | T (lane-eq) | T (ns) | C (lane-eq) | C (ns) | note |
|---|---|---|---|---|---|
| difference 2 + cast S 1 + shift 1 + cast P 1 + sum 1 (six f32-class ops) | 67 338 | 1 559 | 132 218 | 3 061 | f32 1.37 / 2.69 per lane |
| exp (native, measured) | 94 208 | 2 181 | 94 208 | 2 181 | 11.5 per element, chained already |
| f16 tree 8 → 1 reel → 256 lanes | 47 616 | 1 102 | 93 327 | 2 161 | 6-op identity, And<int16> |
| 16 per-row reduce-max calls | 125 729 | 2 910 | 125 729 | 2 910 | 181.9 ns per call |
| shift reel (20 small calls) | 40 089 | 928 | 40 089 | 928 | A3: one chained f16 call each |
| merge (pack) | 25 750 | 596 | 25 750 | 596 | hypothesis variable (§3.1) |
| **chain as specified** | **400 731** | **9 276** | **511 323** | **11 836** | 77.2 % / 98.5 % of the 12 011 ns block |
| fixed-shift variant (§3.4): five f32-class ops + exp + 8 guard calls + merge | 238 937 | 5 530 | 293 005 | 6 782 | 46.0 % / 56.5 % |

T3r_merge_threshold_* (iffs over the merge): the t = 1 block is DDR-bound at 174.6 iff merge ≤ 143 937 (T) / 33 345 (C) / 305 730
(fixed-shift) lane-equivalents, and over c_exp iff c_exp ≤ 25.9 / 12.4 / 45.7 (T3r_cexp_threshold) — the measured 11.5 and 25 750
pass every line; the chained chain passes its own line by 175 ns. At 256-token blocks (mt = 3, 4) the chain as specified is 6 837 ns
per fragment against 6 005 ns of DDR (113.9 %): the reduce calls and the reel do not shrink with the block, which is what makes
t ≥ 4 vector-bound (§7) and S4 dead (§2.4).

**Round 4 — the chain without the Z difference, with the fresh-set merge** (`[R4-chain-*]`, T4r_chain, T4r_chain_shares; per 512-token
block-fragment; "T" throughput / "C" chained; **status OPEN**: session 1 found 75–91 % of the P lanes reading back as raw scores from the
softmax reel — deterministic, every isolated piece passes; session 2 owns it. The cells below are the chain as specified; they are not
modelled around the anomaly and must not be read as measured):

| item | lazy-T | lazy-C | rowmax-T | rowmax-C | note |
|---|---|---|---|---|---|
| elementwise per score | shift, exp, cast P, sum (3 f32-class + exp) | | cast S, shift, exp, cast P, sum (4 + exp) | | step 1 (difference 2) is gone: fresh chunks |
| f16 tree + 16 per-row reduce calls + 20-call reel | — | — | 1 102 + 2 910 + 928 ns | 2 161 + 2 910 + 928 | rowmax only |
| guard (one reduce-max per P reel) | 8 calls, 1 455 ns | 1 455 | — | — | lazy only; REQUIRED (M) |
| fresh-set merge (4 partials) | 357 ns | 701 | 1 631 | 2 046 | T4r_merge |
| **chain per fragment** | **4 772 ns** | 5 867 | 9 791 | 12 265 | round 3: 5 530 / 6 782 / 9 276 / 11 836 |
| share of the block at 174.6, legs 2 / legs 0 | **35.3 / 39.7 %** | 43.4 / 48.8 | 72.5 / 81.5 | 90.8 / **102.1 %** | the rowmax-C flag |
| at 256-token blocks (mt ≥ 3) | 2 434 (29.5 / 40.5 %) | 3 029 | 7 482 (90.6 / **124.6 %**) | 8 784 | per fragment |
| at 1 024-token blocks (mt = 1 variant, §4) | 9 447 (9.2 ns per token) | 11 544 | 14 409 (**14.1** ns per token vs 19.1) | 19 226 | T4r_chain_shares |

Reading it: the lazy chain has 9.2 µs of slack per block on the design page with the bounce (13 943 − 4 772; 7 622 without) and the
rowmax chain at chained latencies has 1.7 µs with the bounce and **−254 ns at 174.6 without it** — the one t = 1 cell that is
vector-bound (T4r_t1_binding). rows* (the fragment count at which the vector unit reaches the block, T4r_rows_star): lazy-T mt = 4
(64 rows, t ≥ 8) with the bounce, mt = 3 (48, t ≥ 6) without; rowmax-T mt = 2 (32, t ≥ 4) either way; rowmax-C mt = 1 without the bounce.
The lazy chain's per-step extra — the first-block max — is in the fixed cost (§2.2), not here.

**Round 5 — the chain cost with its scalar crossings (erratum #29; `[R5-guard*]`, `[R5-A5-refuted]`, `[R5-crossing-*]`, `[R5-rowmax-*]`;
T5r_guard, T5r_A5_refuted, T5r_xing_once, T5r_xing_every, T5r_fusion_32k, T5r_crossing_cells, T5r_rowmax_bound, T5r_switch_void).**
Rounds 3–4 costed the chain as lane work only and composed it with the stream by max(); the per-block scalar reads — the guard's 8 reduce
results through a queue fence, the rowmax chain's 16 row maxima into the shift reel's Duplicate calls — were "≈ free" (A5: under 1 µs by the
σ_s class). Erratum #29 (MEASURED, session 3) refutes the premise: any per-block scalar crossing drains the in-flight vector work by
≈ 10–20 µs, and a reduce-max with a scalar destination costs ≈ 1.1 µs per call. The corrected per-block cost, per pass:

  block = max(stream + bounce, vector lane work, MMA, loader) + X,  X = the crossing term (serial — it overlaps nothing).

| guard implementation | X per block (32k, 64 blocks) | 32k cell, t = 1 | status |
|---|---|---|---|
| none (unguarded) | 0 | **938 800 ns** = 143.0 GB/s | MEASURED |
| as shipped: 8 reduce-max calls with a scalar destination + one queue fence | **8 981 ns** (574 800 / 64; the quoted +572 000 gives 8 937) — 8 × 1 100 = 8 800 ns = 98.0 % of it: the scalar-destination reduce *is* the crossing | **1 513 600** = 88.7 | MEASURED |
| f16 tree + one queue round trip | 19 531 — one drain per block, inside the 10–20 µs band | 2 188 800 (+1 250 000) | MEASURED |
| f16 tree + one full barrier | 21 875 (1 875 above the band) | 2 338 800 (+1 400 000) | MEASURED |
| **batched guard**: the decision as a vector side-product (the 8 vector-destination reduce calls already in the chain, 1 455 ns, into a per-block flag lane), crossed once per K blocks | ⌈nb/K⌉·cx / nb | K = nb (once per step): **958 800 (140.0)** at cx = 20 µs, 948 800 (141.5) at 10 µs; K = 8: 1 098 800 / 1 018 800; K = 1: 2 218 800 / 1 578 800 | DERIVED; the kernel is UNMEASURED (E39) |

The algebra (∀ nb, K, cx): one crossing per step leaves exactly one crossing (T5r_xing_once: ⌈nb/K⌉ = 1 for 0 < nb ≤ K), one per block
leaves nb of them (T5r_xing_every); at 32k, for every K ≥ 64 and every cx ≤ 574 800, the fused cell is 938 800 + cx and guard fusion is
worth 574 800 − cx per layer (T5r_fusion_32k). So the "fused target ≈ 140 GB/s" is the unguarded kernel plus one crossing at the band's
top, and the "~570 µs" of the steering note is the zero-residual ceiling. Three terms can push the batched guard above its target and are
carried, not assumed away: (1) **the side-product** — the 8 vector-destination reduce calls cost 1 455 ns per block at the round-4
throughput convention; the measured kernel's chain is serial (§6.0), so if they land on it they add up to 93.1 µs at 32k (the measured
softmax runs 3.0× under that convention, ≈ 31 µs); (2) **the re-run** — with one crossing per step the merge cannot wait for a per-block
verdict, so the batched guard merges optimistically and re-runs the step with m_r raised when the step's flag shows a trip (exact by shift
invariance: the rescale-at-every-raise result) — ≤ 0.22 % of a step at the measured trip rate (≈ 2.1 µs at 32k); (3) **cx itself** (10–20
µs). E39 measures their sum X per step; DESIGN-4 round 5 shows that X decides whether guard fusion outranks the direct-path expert kernel at
MoE 32k (iff X ≤ 8 279 ns). Round 4's A5 is refuted 8.9× (8 981 ns per block against "< 1 000"), and the cell it fed — the guard "hidden in
9 171 ns of DDR slack" — never existed: the measured kernel has no DDR-bound slack to hide in.

**The rowmax chain under erratum #29.** Step 3's shift reel is built from the 16 per-row maxima by Duplicate — a scalar operand — so the
chain as specified crosses at least once per block: ≥ min(16 scalar-destination reduce calls = 17 600 ns, one drain + 16 scalar reads
= 10 000 + 318 ns) = **10 318 ns per block** (UNMEASURED structure; a lower bound — the extra lane work comes on top). At 32k that is
≥ 938 800 + 64 × 10 318 = **1 599 152 ns** (83.9 GB/s) > the shipped guarded lazy chain's 1 513 600; at 1M ≥ 49 051 264 > 46 313 600.
Every rowmax cell of the round-3 / round-4 tables (917 µs at 32k, 7 756 µs at t = 16, …) assumed free crossings and is superseded by this
bound.


### 3.3 Numerics
Scores are f32 (exact products of f16 inputs, f32 sums over d ≤ 128); the shift makes every exp argument ≤ 0 so
no overflow is possible; P ≤ 1 in f16 (no saturation); O and S accumulate in f32 over ≤ 2²⁰ terms (relative
2⁻²⁴·√L class); out = O/S in f32 then one cast to f16 (E9's rounding-mode check applies). The i8 variant adds
per-token K scales (a reel per block, +1 Mul per score) and quantises P to i8 with the fixed scale 127 (p ≤ 1,
no max needed) — its accuracy is the open item of E27, not its rate.


**Round 4 — numerics re-aimed (review items 5 and 7; `[R4-drift-*]` `[R4-sink-*]`, T4r_drift_online, T4r_sum_error, T4r_sink).**
(i) *The drift theorems' mechanism is retired.* T_drift_1M (683 visits per region, 512-token blocks) and T_drift_blocks (1 366 visits at
256-token blocks) stand as theorems of the round-2 region-difference model, and the review's point is stated explicitly: their
**deterministic bounds — f32 ulp 2⁻⁹ ≈ 1 953 ppm and 2⁻⁸ ≈ 3 906 ppm on a score — exceeded the 10⁻³ ship criterion at both block sizes;
1M shipped only under the random-walk hypothesis** (832 → 61 ppm) that E26 was to measure, and the C_o region's difference (1 024 visits
per region at 1M) never had a theorem at all. With fresh chunk sets (erratum #19) none of this exists: no region content, no visits, no
±Q — the mechanism cannot be built on this tuple. smax = 32 (|s| ≤ 32, the qk-norm premise) remains the premise of the lazy guard
(§3.4: without qk-norm the scores reach ~1 667 and the variant is dead, HW-MAP), not of any drift bound. (ii) *What remains is the
online chain's f32 rounding*, and it is now bounded deterministically. The partials are exact products of f16 pairs (22 significant
bits) summed over 128 tokens inside the matrix unit (internal order: UNMEASURED, E26′ = the former K5); the vector unit then runs the
longest sequential f32 chains O: 3 (block-local sum of 4 partials) + 1 running add per block = **2 052 adds at 1M**, S: 8 reels into
the block accumulator + 2 (fold 1 024 → 256) + 1 per block + 4 (final 16 → 1) = **2 062**. With IEEE round-to-nearest each add errs by
≤ 2⁻²⁴ of the partial sum, so n adds err by ≤ n · 2⁻²⁴ of the sum of magnitudes (first order; T4r_sum_error is the telescoping half,
the per-add bound is the INPUT): **123 + 123 = 246 ppm at 1M, 10 ppm at 32k, under the 1 000 ppm line without a hypothesis**
(T4r_drift_online); 490 ppm at 256-token blocks (4 098 / 4 106 adds), 125 ppm at 1 024-token blocks; a single-level O chain of L/128 =
8 192 adds would be 489 ppm and S summed straight into one accumulator (16 383 adds) 977 ppm — the two-level order of §3.1 is what buys
the margin, at no extra op. For O the bound is relative to Σ p|v| (cancellation across signed v makes it looser relative to |O|); the
random-walk figure is √2 052 · 2⁻²⁴ ≈ 2.7 ppb. E26′ measures the realised error against f64 on the online chain (not the region content).
(iii) *The planted sink (item 7).* The f16 cast flushes p below 2⁻²⁴ ≈ 6·10⁻⁸ (the smallest f16 subnormal), i.e. tokens with
s − m < −16.6 nats (e¹⁶ < 2²⁴ < e¹⁷, host arithmetic) — one-sided: mass is only lost. A row with one sink at p = 1 and L − 1 tokens just
under the line (p = 2⁻²⁵) loses **122 / 976 / 3 906 / 31 249 ppm at 4k / 32k / 128k / 1M** of its mass (T4r_sink) — several % at 1M on
either chain; random inputs never produce it, so E27 gets a planted-sink case. Two spec choices follow. The S sum (step 6 of §3.2) adds the
f32 p while PV multiplies the flushed f16 p: out = O/S then carries the lost mass in the denominator; summing the cast-back f16 p instead
(+1 f32-class op per score, +260 ns·mt per block) makes out the softmax over the surviving tokens — both are ≈ 3 % off on the sink row,
so consistency is a choice, not a fix. The fix is the shift offset: on the lazy chain the shift m_r − β with β ≤ 3 puts the row's largest
p at e^β (guard at e^(8+β) ≤ 59 874 < 65 504 only for β ≤ 3) and moves the flush line to −16.6 − β nats: at β = 3 the same tokens sit e³ ≈ 20×
above the line and nothing is lost. β = 3 is the round-4 default (cost 0; E27's planted sink verifies it on both chains).


### 3.4 Round-3 variant "lazy": a fixed per-row shift with an overflow guard (the one change the measurements force)
The measured chain is 77 % of a block at t = 1 and 4.6× a 256-token block at mt = 4 because the per-row block max costs 16
reduce-max calls plus a tree plus a rebuilt shift reel on every block. Softmax is shift-invariant, so the shift need not be the
running max: fix m_r once per step (the per-row max of the first block, computed with the full machinery once — 16 calls + tree,
≈ 4 µs per step) and compute every later block as P_b = exp(S_b − m_r). Correctness needs only that no P overflows f16 and that
the row's scale is consistent — T_online_exact holds with a constant shift. The guard: after the cast, one reduce-max per P reel
(8 calls per fragment at 512-token blocks, 1 455 ns) checks max P ≤ e^μ with μ = 8 (e⁸ = 2 981 ≪ 65 504, errata #5 never bites);
if it fires, the exception path runs the §3.2 machinery for that block (per-row max, α = exp(m_r − m_r^new) over 16 lanes,
O ← α·O, S ← α·S, recompute P, then its PV calls — ≈ 10 µs) and raises m_r. The merge loses its α (O ← O + (C_o − snap),
S ← S + Σ_b: 9 820 lane-eq itemised, 227 ns; the headline still charges the pack's 25 750) and the shift reel is built once per
step. Costs (`[R3-chain-lazy-*]`, `[R3-t1-*-lazy-*]`, T3r_chain, T3r_t1_*): 5 530 ns per 512-token block (46 %; 6 782 chained),
3 063 per 256-token block (51 %) — t = 1 at 32k 815 µs (167.0) / 780 (174.6); t = 4 DDR-bound (826 µs); t = 8 1 593 µs (1.9×);
t = 16 3 162 µs; KV-int8 413 µs (DDR-bound); the crossover keeps L_eq = 16 896 at the 174.6 basis (T3r_crossover_lazyT). Buffers
are unchanged (§4). Gate: **E35** — the exception rate with real q / K per (model, L): the variant pays iff exceptions × ≈ 10 µs
stay under the 3.7 µs per block it saves, i.e. fewer than one exception per ~3 blocks; a needle-token profile that trips it every
block falls back to §3.2 as specified. Everything else in this document is written for the chain as specified; the cells of this
variant are the third number of each round-3 triple.


**Round 4 — the lazy spec closed (review item 3 a–f, session 1; `[R4-lazy-trip]` `[R4-i8-t1-*]` `[R4-firstmax-*]`, T4r_lazy_trip,
T4r_i8, T4r_firstmax).** The lazy chain is the round-4 headline (it is what session 1 implemented; the rowmax chain is the fallback).
**(M) The guard's per-trip recompute is REQUIRED, not advisory: without it exactly the predicted 9 / 8 192 lanes per tripped block come
out wrong** (HW-MAP, session 1). The closure:
- **(a) m_r.** The per-row max of **this step's first block** (512 tokens at mt ≤ 2, 256 at mt ≥ 3 — the calibration window shrinks with
  the block), computed once per step with the full machinery (cast S → f16, the f16 tree, 16 reduce-max calls, the reel: **5 200 ns at
  the throughput convention, 6 508 chained; 4 501 / 5 138 at 256-token blocks** — in the fixed cost, T4r_fixed). The measured trip rate
  (0.087–0.22 % of steps, HW-MAP) transfers only to this definition; a prefill-calibrated m_r is a different variant with an unmeasured
  rate. The shift is m_r − β, β = 3 (§3.3 (iii)).
- **(b) The guard's result path.** The 8 reduce-max results per fragment (one per P reel; value in lane 0, index-class in lane 1) cross to
  the scalar unit **through the queue fence** (erratum #15: a raw read issued right after async vector math ships pre-fold values) —
  one fence per block, cost UNMEASURED (A5, under 1 µs by the σ_s class; E35 times it).
- **(c) Gate the merge, not the PV calls.** The PV calls of a block issue unconditionally on the (possibly overflowing) P; the guard
  decides only whether the block's fresh partial sets are merged. On a trip the block's partial is **discarded** (fresh sets make this a
  no-op: nothing to absorb or snapshot), the block is recomputed on the §3.2 machinery (per-row max, α = exp(m_r − m_r^new) on 16 lanes,
  O ← α·O, S ← α·S, P recomputed, PV re-issued, partials re-drained and merged) and m_r is raised; the common path has no scalar stall.
  Cost of a trip ≈ **10 699 ns** (the rowmax chain 9 791 + 480 ns of re-issued PV calls + a 428 ns re-drain).
- **(d) Granularity.** Block (≈ 10.7 µs); the reel's argmax lane identifies the tripped row, which decides which m_r rises — a per-row
  recompute would not be cheaper on the vector unit (every op is per reel), so block granularity it is.
- **(e) Switch policy.** The lazy chain saves **5 019 ns per 512-token block** (9 791 − 4 772), so the variant pays iff fewer than one trip
  per **2.1 blocks** (round 3 said 3 at its chain); a needle profile that trips every block costs **+685 µs at 32k (64 blocks), +21.9 ms at
  1M**. After **k = 3 trips in one step** the kernel finishes the step on the rowmax chain: the worst case is +32 µs plus the rowmax cells
  (917 µs at 32k instead of 912), never the needle cost. E35 measures the trip rate per (model, L) and the trip cost.
- **(f) Padding rows.** The 16·mt − rows padding rows of the staged Q are exactly zero (there is no −Q copy any more): their scores are 0,
  their first-block max is 0, their P is e^{0 − 0 + β} = e³ ≤ e^{8+β} — they never trip the guard and their rows are discarded at the end.

**KV-int8 × lazy (review item 4).** The round-3 cell (413 µs, DDR-bound) quantised P to i8 at the fixed scale 127 assuming p ≤ 1, but the
lazy P reaches e⁸ ≈ 2 981 (127 × 2 981 saturates i8): **the cell is UNREACHABLE as specified** (T4r_i8). It is reachable only with μ = 0
(P ≤ 1, scale 127 fixed, every P > 1 trips) at a trip rate that is UNMEASURED (E35 at μ = 0 — expected far above 0.22 %); otherwise KV-int8
needs the per-block max and lives on the rowmax chain: **651 µs at 32k (vector-bound: 9 791 > the 7 746 ns half-stream block), 20.1 ms at
1M** on the design page with the bounce (T4r_i8). The KV-int8 lever therefore loses its DDR-bound cell until E35 at μ = 0 says otherwise.

**Round 5 — what session 3 settled about the lazy chain (`[R5-e35]`, `[R5-guard]`, `[R5-rowmax-*]`; T5r_guard, T5r_rowmax_bound,
T5r_switch_void).** (MEASURED) Correctness: causal-exact end-to-end — 12/12 causal-matrix cells at 32k (t 2–16 × tail residues) bad 0,
relerr 9.8·10⁻¹¹; real-exp bad-0 at 4k / 32k / 128k / 1M; with rescale-at-every-raise the output IS the true final-m softmax; the trip
machinery is REQUIRED and the trips themselves are ≈ free. **E35's device half is RESOLVED: the guard's cost is the SCAN, not the trips**
— 574.8 µs at 32k (38.0 % of the guarded kernel, 61.2 % of the unguarded one), 8 981 ns per block. What moves in the closure (a)–(f):
- **(b) the result path.** As shipped the 8 reduce results cross as 8 scalar-destination reduce calls (≈ 1.1 µs each) plus one queue fence
  per block — that is the 8 981 ns; A5 ("one fence, under 1 µs") is refuted 8.9×. The fix is to stop crossing per block: the batched guard
  of §3.2 round 5 reads one flag per step (E39).
- **(c) gate the merge.** With one crossing per step the merge cannot wait for a per-block verdict unless the block partials are held: a
  ring of per-block partials costs 8 KiB·mt per block (8 blocks = +64 KiB of US at mt = 1, 186 KiB + 64 B in all — fits; a whole 32k step,
  512 KiB, does not). The batched guard therefore merges optimistically and, when the step's flag shows a trip, re-runs the step with m_r
  raised (exact by shift invariance): at the measured 0.087–0.22 % of steps ≤ 0.22 % of a step (≈ 2.1 µs at 32k) — UNMEASURED (E39); the
  trip rate per (model, L) is E35's open model half.
- **(e) the switch policy is VOID.** The rowmax chain pays ≥ 10 318 ns of crossings per block (§3.2 round 5) — more than the shipped guard's
  8 981 on every remaining stretch of r blocks (T5r_switch_void, ∀ r): finishing a step on rowmax after k trips is never cheaper than staying
  on the guarded lazy chain. Policy: stay on lazy; a trip is handled by the recompute (as shipped) or by the batched guard's re-run.
- **KV-int8 (review item 4).** Its rowmax route pays the same crossing: ≥ 1 311 142 ns at 32k (round 4: 650 790) and ≥ 41.2 ms at 1M —
  slower than the fused f16 lazy target (958 800 ns at 32k). The μ = 0 lazy route (P ≤ 1 at the fixed scale 127, every P > 1 trips) is the
  only KV-int8 route without a per-block crossing; its trip rate is UNMEASURED (E35, model half).


---

## 4. Buffer budgets and double-buffering over the L stream (per core; `[A7-sram]`)

Every size below is a function of (mt ≤ 4, d = 128, block = 512) only — **nothing scales with L**
(T_buffers_no_OL: the sum below is a constant for each mt).

| Buffer | Memory | Size (mt = 1 / mt = 4) | Depth / queue | Why |
|---|---|---|---|---|
| K/V tile ring | L0B | 2 × 32 KiB = **64 KiB** | 2 / 2 (errata #9) | the measured configuration ("two 32 KiB parity halves, one full barrier per tile"); a tile = 8 call tiles = 128 tokens of K, or 8 n-groups × 128 tokens of V; the ring is shared, tiles arrive in stream order |
| Q fragments | L0A | 2 × 4 KiB·mt (+Q, −Q) = 8 / 32 KiB | 1 | resident for the step; the sign alternates per C_s region visit (§3.2 drift bound) |
| P fragments | L0A | 2 × 4 KiB·mt = 8 / 32 KiB | 2 / 2 | one 128-token fragment set loads while the previous one multiplies; mt = 4 → L0A = 32 + 32 = 64 KiB **exactly full → cap mt at 4 per pass**; S4 drops −Q and single-buffers P (§2.4) |
| C_s score regions | L0C | 3 × (block·16·4 B)·mt: block = **512 tokens at mt ≤ 2, 256 at mt = 3, 4** → 96 / 192 / 144 / 192 KiB for mt = 1..4 (`[A7-l0c-mt*]`) | 3 / 3 | block b accumulates in region b mod 3 while b−1 drains and b−2's P multiplies: the two-block V lag of §5 needs three |
| C_o PV regions | L0C | 2 × 8 KiB·mt = 16 / 32 / 48 / 64 KiB | 2 / 2 | block b's partial accumulates while b−1's drains |
| **L0C total** | | **112 / 224 / 192 / 256 KiB** for mt = 1..4 — mt = 4 fills L0C exactly, which HW-MAP measured as working (m = 64 across the full 256 KB); the fallback is two C_s regions (192 KiB) with a one-block V lag | | never above the measured accumulator footprint |
| drained C_s | US | block·16·4 B·mt = 32 / 64 / 48 / 64 KiB | 1 | the working block |
| NegSnap (Z branch) | US at mt = 1, S1 above | 3 × drained = 96 KiB (mt = 1); 192 / 144 / 192 KiB in S1 for mt ≥ 2 (E26 proves the S1→US copy) | 3 | the region-difference epilogue; **vanishes if E11 finds a reset** |
| P staging | US | 2 × block·16·2 B·mt = 32 KiB (mt = 1) … single-buffered 32 KiB at mt = 4 | 2 (1 at mt = 4) | cast output, copied to S1 in 4 KiB pieces |
| O, partial drains | US | 8 KiB·mt + 2 × 8 KiB·mt (single at mt = 4) | 1 + 2 | running output and the PV partial drains in flight |
| S accumulator, shift reel, α | US | 4 KiB + 4 KiB + 64 B | 1 | per-row state |
| K_tail, V_tail, q row-major, page-table window | US | 4 + 4 + 4·mt + 4 KiB | 1 | the ≤ 15-token vector tail, the prologue COPY_FRAC source, 512 page addresses |
| **US total** | | **208 KiB + 64 B at mt = 1 as tabled** (213 056 B; 212 KiB + 64 B with the window at its declared depth 2) — **over the 208 KiB evidenced by 64 B / 4 160 B** (round 1 summed 200 KiB, omitting q row-major and the window; T_buffers_us); 112 KiB + 64 B on the Z-reset branch; mt = 2: 204 KiB + 64 B + snapshots in S1; mt = 3: 200 KiB + 64 B; mt = 4: 196 KiB + 64 B with P and partial drains single-buffered (`[A7-us-mt*]`) | | the tightest budget of the design: at mt = 1 the snapshots must go to S1 as well (→ 112 KiB + 64 B) or the prologue-only q buffer must alias the idle drained-C_s buffer (→ 204 KiB + 64 B, T_buffers_us_remedy); mt ≥ 2 **requires** the snapshots in S1 or a reset mechanism |
| P ring, NegSnap (mt ≥ 2) | S1 | 2 × 4 KiB·mt pieces + ≤ 192 KiB | 2 / 3 | within the ~1 MB P value |
| page-table window | US | 4 KiB (512 entries = 128k tokens per fetch) | 2 | refilled every 128k tokens |

Double-buffering depth is one block (12 µs) on every engine edge except the direct-load ring, which is two
32 KiB tiles deep as measured. The vector unit is decoupled from the DDR engine by the **two-block V lag**: the
softmax of block b runs while DDR streams K_{b+1} and V_{b−1}, so a vector block up to 2× the DDR block
(24 µs) is absorbed before any stall — the worst corner (12 839 ns) stalls DDR by 828 ns per block, the 6.9 %
in §0, and the K-only rows of the table show why a one-block lag would stall at 6 µs instead.


**Round 4 — the buffers with fresh chunk sets, the P bounce and 32-token tails** (`[R4-l0c-*]` `[R4-us-*]`, T4r_l0c, T4r_l0a, T4r_us;
every size a function of (mt, d, block) only — T_buffers_no_OL still holds, the rows are re-summed):

| Buffer | Memory | Size (mt = 1 / 2 / 3 / 4) | Round-4 change |
|---|---|---|---|
| K/V tile ring | L0B | 64 KiB | unchanged |
| Q fragments | L0A | 4 KiB·mt | **no −Q** (the ±Q alternation is retired) |
| P fragments | L0A | 2 × 4 KiB·mt | unchanged; L0A = **12 KiB·mt = 12 / 24 / 36 / 48 KiB** (round 3: 16 / 32 / 48 / 64; mt = 4 no longer exactly full) |
| C_s score regions | L0C | 3 × 32 / 64 / 48 / 64 KiB·… = 96 / 192 / 144 / 192 KiB | fresh chunks (one call per chunk per visit); the 3-deep ring stays |
| **C_o fresh chunk sets** | L0C | (block / 128) × 8 KiB·mt = 32 / 64 / 48 / 64 KiB | **replaces the 2 × 8 KiB·mt accumulating regions**; single-buffered (A10′) |
| **L0C total** | | **128 / 256 / 192 / 256 KiB** | exactly full at mt = 2 and 4; mt = 1 with double-buffered sets 160 KiB; the mt = 1, 1 024-token-block variant (3 × 64 + 8 × 8) fills L0C exactly |
| drained C_s | US | 32 / 64 / 48 / 64 KiB | unchanged |
| **NegSnap** | — | **0** | retired (round 3: 96 KiB in US at mt = 1, 144–192 KiB in S1 above) |
| P staging | US | 32 KiB at mt = 1 (double), 32 / 24 / 32 KiB single at mt ≥ 2 | the bounce drains each 4 KiB piece to DDR as it is cast |
| O, partial ring | US | 8 KiB·mt + 2 × 8 KiB·mt (1 × at mt = 4) | slot 0 of the ring holds O_b (the block-local sum) |
| S accumulator, shift reel, α | US | 4 + 4 KiB + 64 B | unchanged |
| **K_tail, V_tail** | US | **8 + 8 KiB (32 tokens each)** | append-then-attend needs ≤ 31 tail tokens at t = 16 (§10.1) |
| **mask reel** | US | 512·mt × 4 B = 2 / 4 / 6 / 8 KiB | the per-row causal mask (t > 1) |
| q row-major, page-table window | US | 4 KiB·mt (aliased onto the idle drained-C_s buffer at mt = 4) + 4 KiB | the round-2 remedy, applied at mt = 4 |
| **US total** | | **122 / 184 / 190 / 196 KiB + 64 B** | every mt under the 208 KiB evidence (round 3: 208 KiB + 64 B at mt = 1 and snapshots forced into S1 above) |
| P ring | S1 | 2 × 4 KiB·mt (the DDR → S1 staging target) | no snapshots: 8 / 16 / 24 / 32 KiB |
| **P scratch** | **DDR** | 2 × 16 KiB·mt (double-buffered) | new: the bounce's scratch, O(1) |

The 1 024-token block at mt = 1 (review item 5's lever) is listed as a variant: L0C exactly full (256 KiB), drained C_s 64 KiB in US
(154 KiB + 64 B total), the rowmax chain per token 14.1 instead of 19.1 ns (the 16 reduce calls and the reel amortise over twice the
tokens; the lazy chain gains nothing: 9.2 vs 9.3), the O chain halves (1 032 adds, 62 ppm), the fixed cost doubles (two 9.4 µs blocks on
lazy); its price is no longer S1 snapshots (there are none) but the exactly-full L0C and a 27 µs block at the design page.


---

## 5. Sync and barrier plan (errata #8, #9, #14 at every edge)

All direct loads are fenced with the full barrier (HW-MAP errata #14: the only working fence for direct GM
loads; the copy-in→matrix flag is INERT and is not used anywhere). Queue depths equal declared counts (#9):
L0B 2/2, P-L0A 2/2, P-S1 2/2, C_o 2/2, C_s 3/3. No queue-based staging into L1 (#14). Consecutive same-pair
producer flags with different IDs are legal (#14) and are used for the two P fragments of a block.

| # | Edge | Releasing event | Protects |
|---|---|---|---|
| A1 | direct-load → matrix | full barrier after tile i lands in L0B[i mod 2] | an MMA never reads a half-landed K/V tile |
| A2 | matrix → direct-load | last MMA using L0B[i mod 2] retired | the next load never overwrites an operand in use |
| A3 | matrix → vector (scores) | the 32·mt scores calls of block b retired | the drain never reads a C_s still accumulating |
| A4 | vector → matrix (scores) | drain of C_s[b mod 3] retired | block b+3's first call never lands in a region mid-drain (3 blocks apart: never stalls) |
| A5 | vector → copy (P) | Cast of P fragment f retired | the US→S1 copy never ships a half-written fragment |
| A6 | copy → loader | US→S1 copy of fragment f retired | L0LOAD never lifts a half-landed S1 piece |
| A7 | loader → matrix (PV) | L0LOAD of P fragment f retired | the PV call never multiplies a half-loaded A |
| A8 | matrix → loader | the 8·mt PV calls of fragment f retired | the next L0LOAD never overwrites a P in use |
| A9 | matrix → vector (PV) | the 32·mt PV calls of block b retired | the partial drain never reads a C_o still accumulating |
| A10 | vector → matrix (PV) | drain of C_o[b mod 2] retired | block b+2's first PV call never clobbers a draining partial |
| A11 | copy-in → vector | page-table window, K_tail/V_tail, q row-major landed in US | the prologue and the tail never read garbage |
| A12 | vector → copy-out | final out cast retired; KV-append sources written | copy-out never ships half-written data |
| A13 | copy-out → (next launch) | K append (8 × 32 B), V_tail row, V fractal tile retired | the next step's loads see the completed append (launch boundary = the only cross-engine fence that is free) |

Where errata #8 could enter: A3/A4 and A9/A10 are hand-managed cross-engine readbacks of L0C — each is an
explicit pipe barrier, never a queue assumption. **Detection (E27):** the accumulation order is fixed (blocks
in order, fragments in order, the same region rotation), so two runs on identical inputs must be bit-identical;
any rep-to-rep difference across ≥ 20 reps is a sync fault, and a positive control with A3 deleted must show
the ~512 B islands or the detector is blind. The vector merge order (α-scale before add) is fixed too, so the
f32 result is deterministic even though it is not associative.

Cross-core: none (one head per core; the launch boundary is the only cross-core sync, and the head split of
§9 uses it).


**Round 4 — the edges that changed (errata #18–#21, session 1).** The P path is now **A5′ vector → copy-out** (the cast P piece retired
before the US → DDR copy ships it), **A6′ copy-out → copy-in** (the 4 KiB piece landed in the DDR scratch before the DDR → S1 staging
reads it — a DDR round trip, fenced like every direct load with the full barrier, the only working fence) and **A6″ copy-in → loader**
(the S1 piece landed before L0LOAD lifts it); the old A5/A6 (US → S1 plain copy) are deleted — erratum #20 says that copy delivers data
that is not the source. The P lift sits between direct-load barriers at 2× / 8× the expert kernel's lift density (§2.2): E24 runs at this
cadence with differencing on A (E29's fault class). **A10′ vector → matrix (PV)**: at mt = 2 and 4 the fresh C_o sets are single-buffered
(L0C exactly full), so the drain of block b's sets must retire before block b + 1's first PV call — one block of slack (12 µs) against a
459 ns drain; at mt = 1 the sets are double-buffered and the edge is two blocks apart as before. **Every L0C destination is an explicit
byte-offset tensor (erratum #18: a chunk-offset view lands in chunk 0)**: the C_s ring's 3 × (block/16) chunks and the C_o sets' 8 chunks
per group are addressed by byte offset — E23(v)'s differencing (two patterns through one chunk address, out changes) is the check. The
determinism criterion of E27 is unchanged (fixed order: blocks, groups, partials, the two-level merge), and its host patterns use **prime
periods > L** (erratum #21: mod-N patterns alias tokens and hid a call-tile transposition as a clean one-token shift).


---

## 6. Predicted ms and effective GB/s vs L, t ∈ {1, 16}, with the G and E branches explicit

Model (`proof/attn.py`, `step_ns`): per pass, nb = ⌈16⌊L/16⌋ / block⌉ blocks;
`T = passes · nb · max(ddr, vec, mma, loader [, drain]) + fixed`, where per block (per core)
`ddr = block·4 096·10/G`, `vec = (block·16·c_V + 7 000)·mt·ρ32·10/432`, `mma = 64·mt·15` (block = 512),
`loader = 16 384·mt·10/265`, `drain = 40 960·mt·10/R_drain`, and `fixed = 2·vec + drain + tail` (§2.2).
G is the aggregate rate in tenths; the "page64k" column is G(64 KiB, c_pg = 0.5 µs) = 149.7; "gather3x" is
58.2 (c_pg = 6.0 µs at 64 KiB). Two vector corners bracket the (E, R, ρ32) space: **native** = native exp +
native max at the full f32 rate (c_V = 7, ρ32 = 1) and **worst** = ISA.md as written (poly exp, tree max) at
half rate (c_V = 33, ρ32 = 2). In-kernel µs; wall = + 91 µs (the launch floor, DESIGN.md E0 decides whether it
pipelines). "eff" = KV bytes streamed / T.

**Round 3 (`step3` in attn.py, `Design3.step3` in attn.lean):** the same step with `vec` = the measured chain of §3.2 (`chain100`:
per-score elementwise costs at the measured per-op latencies on the 43.2 G/s unit, plus the per-call items — 16 reduce-max calls,
the 20-call reel, the merge), `drain` at the measured R_drain (hidden; 268 ns in the fixed cost), G from the E21 table, and three
chain corners: **spec** = the chain as specified (throughput convention), **chained** = every call at its chained latency,
**lazy** = the fixed-shift variant of §3.4. The round-2 tables 6.1 / 6.2 are kept below as the record of the retired branches;
the round-3 cells are 6.1′ / 6.2′, and `[R3-moved-*]` pairs every round-2 headline cell with its replacement.

### 6.0 Round 5 — MEASURED: the production kernel's t × L sweep (attention session 3) — `[R5-meas-*]`, `[R5-ung-*]`, `[R5-overlap-*]`, `[R5-validate*]`, `[R5-engines*]`; T5r_meas_*, T5r_readings, T5r_overlap, T5r_validate*, T5r_engines

In-kernel µs as measured (best-of-3, causal flags incl. the guard — read as in-kernel, as the validation row compares them with the
in-kernel 912 µs cell); headline shape (H_kv = 8, g = 8, d = 128, f16 KV, 256 KiB pages, bounce legs = 2). These are the cells now; the
model tables 6.1′–6.2″ below are kept as the record of what was predicted:

| L | **t = 1** (rows 8, one fragment) | eff GB/s | t = 4 (rows 32, mt 2) | per fragment-pass | t = 16 (rows 128, 2 × mt 4) | per fragment-pass | round 4 (lazy-T, legs 2, 169.2): t = 1 / 4 / 16 |
|---|---|---|---|---|---|---|---|
| 4k | **213.5** | 78.6 | 382.1 | 87.8 | 1 481.4 | 90.6 | 131 / 162 / 383 |
| 32k | **1 513.6** | 88.7 (quoted 88.6) | 2 695.6 | 99.6 | 10 741.7 | 100.0 | 912 / 1 030 / 2 565 |
| 128k | **5 852.9** | 91.7 | 10 514.3 | 102.1 | 42 013.4 | 102.2 | 3 589 / 4 005 / 10 044 |
| 1M | **46 313.6** | 92.7 | 83 123.1 | 103.3 | 332 476.2 | 103.3 | 28 575 / 31 768 / 79 853 |

"eff" = KV bytes / T at round-half-up — HW-MAP's 88.6 at 32k is the floored tenth (134 217 728 B / 1 513 600 ns = 88.67; T5r_meas_t1).
"Per fragment-pass" = (rows/16)·KV / T, the normalisation behind HW-MAP's "t ≥ 4 = 99.6–103.4", which covers L ≥ 32k (87.8 / 90.6 at 4k;
T5r_meas_t4, T5r_meas_t16). Measured ÷ round-4 cell: 1.6–1.7× at t = 1, 2.4–2.6× at t = 4, 3.9–4.2× at t = 16. Per 512-token block at
t = 1: 26 687 / 23 650 / 22 862 / 22 614 ns; per fragment per 512 tokens at t ≥ 4: 20.3–24.0 µs — the guarded multi-fragment kernel costs
about the same per fragment whatever the fragment count, i.e. a verify batch costs ≈ fragments × the single-fragment kernel; the stream is
not amortised across fragments as the round-4 regime map assumed (T5r_per_fragment). Fraction of the 398 µs GEMV unit: 0.54 / 3.80 /
14.7 / 116.4.

**The validation row (INPUT, PROMPT-3R5; T5r_validate).** Unguarded 32k t = 1: 938 800 ns = 143.0 GB/s against the round-4 legs-2 cell
911 680 ns: +27 120 ns = **3.0 %** of the exact cell (**2.9 %** of the displayed 912 µs) — inside the 5 % match line (which allows 45 584
ns). **Term by term (T5r_validate_terms):** model = K/V at 169.2 (793 216) + the bounce on the DDR roof (99 136) + fixed (19 328);
measured = the K+V stream phase (770 800 = 174.1 GB/s) + the bounce (≈ 51 000) + the rest (117 000). The model over-charges the K/V basis
by 22 416 ns and the bounce by 48 136 ns (the measured bounce is 51.4 % of the modelled roof charge) and under-charges the exposed chain by
97 672 ns. **The phases serialise (T5r_engines):** scores 523.9 + softmax+guard 644.3 + PV-merge-bounce 344.9 = 1 513.1 µs against the
1 513.6 µs total (0.03 %); without the guard 523.9 + 69.5 + 344.9 = 938.3 against 938.8 (premise: the guard's cost lies in the
softmax+guard phase). The K+V stream is busy 50.9 % guarded (49.1 % idle by this split; HW-MAP quotes ≈ 47 %) and 82.1 % unguarded — the
binding engine is the serial chain in both kernels. So the cell-level validation stands, and the mechanism of §6.1″ ("DDR-bound with
9.2 µs of vector slack per block") is not what the silicon does: the round-4 cells match because their errors cancel. Per block the
measured softmax without the guard is 1 085 ns against the round-4 throughput convention's 3 317 ns (3.0×).

**The readings the planner uses (`[R5-ung-*]`, T5r_readings).** The unguarded kernel is MEASURED at 32k only; off 32k it is read as the
guarded cell minus the per-block guard (574 800 ns over 64 blocks, scaled per block — structurally per block, UNMEASURED off 32k); the fused
kernel as the unguarded one plus one 20 µs crossing per step (the band's top; UNMEASURED — E39); the constant-rate reading (143.0 / 140.0
GB/s at every L) is carried beside them as the bracket:

| L | guarded (M) | unguarded | fused (the target) | constant-rate bracket 143.0 / 140.0 | round 4 (legs 2, 169.2) | unguarded ÷ round 4 |
|---|---|---|---|---|---|---|
| 4k | 213.5 µs (78.6 GB/s) | 141.7 (118.4) D | 161.7 (103.8) D | 117.3 / 119.8 | 130.9 | 108.2 % |
| 32k | 1 513.6 (88.7) | **938.8 (143.0) M** | **958.8 (140.0)** D | 938.6 / 958.7 | 911.7 | 103.0 % |
| 128k | 5 852.9 (91.7) | 3 553.7 (151.1) D | 3 573.7 (150.2) D | 3 754.3 / 3 834.8 | 3 588.7 | 99.0 % |
| 1M | 46 313.6 (92.7) | 27 920.0 (153.8) D | 27 940.0 (153.7) D | 30 034.7 / 30 678.3 | 28 574.6 | 97.7 % |

On the per-block reading the round-4 cell family tracks the unguarded kernel within +8.2 % (4k) … −2.3 % (1M) — inside the 5 % line from 32k
up; the constant-rate bracket is up to 7.6 % slower at 1M (it ignores the amortisation of the fixed costs). **The overlapped floor**
(`[R5-overlap-*]`, T5r_overlap): the K+V stream phase scaled per block plus the measured bounce runs 163.3 GB/s at every L — 821.8 µs at
32k; the unguarded kernel sits 117.0 µs above it at 32k (12.5 %), 38.9 / 266.5 / 1 622.4 µs at 4k / 128k / 1M (27.5 / 7.5 / 5.8 %): that
gap is the most that overlapping the serial phases across blocks could recover (E40). The measured bounce removal would save 6.4 / 51.0 /
204.0 / 1 632.0 µs — 51.4 % of round 4's legs-2 → 0 charge (12.4 / 99.1 / 396.5 / 3 172.4 µs).

### 6.1′ t = 1, round 3 (rows = 8, mt = 1, one pass) — `[R3-t1-*]`, T3r_t1_4k … T3r_t1_1M

| L | 64 KiB shuffled 167.0 (design): spec / chained / lazy | 256 KiB 169.2 | 16 KiB 153.8 | 174.6 (W8 ceiling) | 3× what-if 58.2 | binding | eff GB/s (167.0, spec) | × GEMV (167.0, spec) |
|---|---|---|---|---|---|---|---|---|
| 4k | **119** / 124 / 112 | 118 / 123 / 110 | 128 / 133 / 120 | 115 / 120 / 107 | 307 / 312 / 300 | KV on every cell | 140.7 | 0.30 |
| 32k | **822** / 828 / 815 | 812 / 817 / 805 | 891 / 897 / 884 | 788 / 793 / 780 | 2 325 / 2 330 / 2 317 | KV | 163.2 | 2.07 |
| 128k | **3 233** / 3 239 / 3 226 | 3 192 / 3 197 / 3 184 | 3 509 / 3 515 / 3 502 | 3 094 / 3 099 / 3 086 | 9 243 / 9 248 / 9 236 | KV | 166.0 | 8.12 |
| 1M | **25 736** / 25 741 / 25 728 | 25 402 / 25 407 / 25 394 | 27 943 / 27 948 / 27 936 | 24 617 / 24 622 / 24 610 | 73 814 / 73 820 / 73 807 | KV | 166.9 | 64.7 |

In-kernel µs; wall = + 91. Headline: **822 µs at 32k, 25.7 ms at 1M** on the design's page (812 / 25 402 at 256 KiB); the chained
corner is +0.6 % / +0.0 % (T3r_worst_overrun), the fixed-shift variant −1 %; the page size is the only lever left at t = 1
(256 KiB: −1.3 %, 174.6 would be −4.2 %). Round 2's "drain on the vector engine" corner (+43.5 %) is retired: the drain is a
separate path at 152.8 GB/s/core (E26 measured).

### 6.2′ t = 16, round 3 (rows = 128, two passes of mt = 4, blocks of 256 tokens) — `[R3-t16-*]`, T3r_t16

| L | spec | chained | lazy | lazy, chained | binding | note |
|---|---|---|---|---|---|---|
| 4k | **930** | 1 102 | 417 | 502 | vector | G-independent on every cell |
| 32k | **7 057** | 8 360 | 3 162 | 3 808 | vector | 4.5× / 5.4× / 2.0× / 2.5× round 2's DDR-bound 1 554 |
| 128k | **28 061** | 33 244 | 12 573 | 15 141 | vector | |
| 1M | **224 106** | 265 494 | 100 410 | 120 919 | vector | |

S4 (one pass, mt = 8, 128-token blocks): 11 596 µs / 368 ms (spec), 3 777 / 120 (lazy) — worse than two passes on every chain and
for every merge count (T3r_s4, T3r_s4_dominated_*). KV-int8: 612 µs at 32k on spec (vector-bound: the halved stream, 6 278 ns per
block, is under the 9 276 ns chain), 413 µs on lazy (DDR-bound) — `[R3-i8-t1]`, T3r_i8.


### 6.1″ t = 1, round 4 (lazy chain, fresh chunk sets, the P bounce) — `[R4-t1-*]`, T4r_t1_4k … T4r_t1_1M

In-kernel µs; wall = + 91 µs; each cell is **lazy-T / lazy-C / rowmax-T / rowmax-C**; "legs 2" charges both bounce legs on the DDR roof
(headline, UNMEASURED), "legs 0" is a proven direct US → S1 route (= the round-3 model + the first-block max + the 16-token tail):

| L | **256 KiB, 169.2 (design), legs 2** | 169.2, legs 0 | 64 KiB 167.0, legs 2 / 0 (lazy-T) | 174.6, legs 2 / 0 (lazy-T) | **session-1 loop 138.3, legs 2 / 0 (lazy-T)** | binding |
|---|---|---|---|---|---|---|
| 4k | **131** / 138 / 136 / 145 | 118 / 126 / 123 / 132 | 132 / 120 | 127 / 115 | **156** / 141 | KV on every cell |
| 32k | **912** / 919 / 917 / 925 | 813 / 820 / 817 / 826 | 923 / 823 | 884 / 788 | **1 111** / 990 | KV (rowmax-C at 174.6 legs 0: vector, 818) |
| 128k | **3 589** / 3 596 / 3 594 / 3 603 | 3 192 / 3 200 / 3 197 / 3 206 | 3 636 / 3 234 | 3 478 / 3 094 | **4 386** / 3 901 | KV |
| 1M | **28 575** / 28 582 / 28 579 / 28 588 | 25 402 / 25 410 / 25 407 / 25 416 | 28 951 / 25 736 | 27 692 / 24 618 | **34 956** / 31 073 | KV |

Effective KV rate on the design page with the bounce: 128.2 / 147.2 / 149.6 / 150.3 GB/s (the bounce bytes are not KV bytes); fraction of
the 398 µs GEMV unit 0.33 / 2.29 / 9.02 / 71.8. The moves (T4r_moved): 32k 805 → **912 (+13.3 %)**, 1M 25.4 → **28.6 ms (+12.5 %)**
against round 3's lazy cells; without the bounce +1.0 % / +0.0 % (the first-block max and the tail). The legs-1 cell (read leg only) is
862 µs at 32k. The G column that will decide the first silicon numbers is the kernel's own: the session-1 diagnostic loop measured
**138.3 / 138.7 / 138.0 GB/s at 256 / 128 / 64 KiB, page-size-insensitive, c_pg ≈ 0** — 18 % under the E21 basis because of that loop's
barrier density; the production loop halves the barriers per byte and its rate is UNMEASURED (between 138 and 169). The page-size lever
of round 3 (−1.3 % at 64 KiB) is inside that uncertainty: the planner reads the realised G (§10).

### 6.2″ t = 16, round 4 (two passes of mt = 4, 256-token blocks) — `[R4-regime-t16-*]` `[R4-t16-*]`, T4r_t16

| L | lazy-T | lazy-C | rowmax-T | rowmax-C | binding |
|---|---|---|---|---|---|
| 32k | **2 565** | 3 213 | 7 756 | 9 132 | vector (G- and bounce-independent) |
| 1M | **79 853** | 99 373 | 245 288 | — | vector |

Round 3's lazy-T 3 162 µs at 32k becomes 2 565 (the Z difference and the pack merge are gone), rowmax-T 7 057 → 7 756 (the larger
fresh-set merge). S4 (one pass, 128-token blocks): 2 680 / 13 096 µs at 32k — dominated (§2.4). KV-int8: 651 µs at 32k on the rowmax
chain (vector-bound); the lazy cell is unreachable as specified (§3.4).


### 6.1 t = 1, round 2 — superseded by 6.1′ (rows = 8, mt = 1, one pass) — `[A4-t1-*]`

| L | G = stream (174.6) native / worst | G = page64k (149.7) native / worst | G = gather3x (58.2) native / worst | binding (native / worst) | eff GB/s (stream, native) | × GEMV unit (stream, native) |
|---|---|---|---|---|---|---|
| 4k | **103** / 132 | 119 / 142 | 295 / 318 | KV / vector | 162.6 | 0.26 |
| 32k | **776** / 851 | 904 / 926 | 2 313 / 2 336 | KV / vector | 173.0 | 1.95 |
| 128k | **3 082** / 3 317 | 3 593 / 3 616 | 9 232 / 9 254 | KV / vector | 174.2 | 7.74 |
| 1M | **24 606** / 26 324 | 28 698 / 28 720 | 73 803 / 73 825 | KV / vector | 174.6 | 61.8 |

If the L0C drain is executed by the vector engine (serial with the softmax; E26/E28 classify it), the worst
corner becomes 165 / 1 114 / 4 365 / 34 713 µs and the native corner is unchanged (its vector + drain time,
95 + 262 µs at 32k, is below the 769 µs stream) — `[A4-t1-*] drain on the vector engine`. The gather3x column
is unaffected by the vector corner at every L (DDR dominates by 3×). **Headline, t = 1: 776 µs at 32k and
24.6 ms at 1M**, each a KV stream at 173.0 / 174.6 GB/s effective, conditional on G(64 KiB) = stream and on
c_V·ρ32 ≤ 62 — the first is E21, the second holds on every softmax branch except the one where ISA.md's op
list is complete *and* f32 runs at half rate (then 851 µs / 26.3 ms).

### 6.2 t = 16, round 2 — superseded by 6.2′ (rows = 128, two passes of mt = 4, blocks of 256 tokens) — `[A4-t16-*]`

| L | stream native / worst | page64k native / worst | gather3x native / worst | binding (native / worst) | eff GB/s (stream, native) |
|---|---|---|---|---|---|
| 4k | **209** / 905 | 241 / 905 | 593 / 905 | KV / vector | 160.9 |
| 32k | **1 554** / 6 802 | 1 809 / 6 802 | 4 629 / 6 802 | KV / vector | 172.8 |
| 128k | **6 166** / 27 021 | 7 189 / 27 021 | 18 465 / 27 021 | KV / vector | 174.2 |
| 1M | **49 209** / 215 733 | 57 393 / 215 733 | 147 604 / 215 733 | KV / vector | 174.6 |

The native corner is DDR-bound at exactly twice the t = 1 bytes (two passes); the worst corner is
vector-bound by 4.4× and insensitive to G. With the drain on the vector engine the native corner itself becomes
drain+vector-bound (3 378 µs at 32k, 107.6 ms at 1M): at mt = 4 the drain bytes are 384 B per token against 512 B of KV, so **R_drain ≥ 16.4 GB/s/core** is needed to
hide it (T2_drain_threshold at mt = 4; round 1 said 640 B and 13.6). S4 (§2.4)
gives 1 032 µs / 32.4 ms on the native corner; the KV-int8 variant halves every DDR term (391 µs / 12.3 ms at
t = 1 on the native corner, `[A4b-i8-*]`) and leaves the vector terms unchanged.

### 6.3 The attention fraction of the GEMV step (PROBLEM-3's target)
Per 398 µs "die-step class" unit (one 8192² W8 GEMV at 168.5 GB/s): **0.30 / 2.07 / 8.12 / 64.7** at 4k / 32k / 128k / 1M on
the design's page (0.29 / 1.98 / 7.77 / 61.9 at the 174.6 basis; round 2: 0.26 / 1.95 / 7.74 / 61.8; `[R3-t1-*] x GEMV`).
**The crossover, round 3** (`[R3-crossover-*]`, T3r_crossover_*). The stream basis of `T_crossover` — 12 011 ns per 512-token
block at 174.6 — is unchanged, so step(512·k) = 12 011·k + fixed and the round-2 result k ≥ 33 (L_eq = 16 896) holds **iff the
fixed cost lies in [1 637, 13 647] ns** (T3r_crossover_iff, an iff over the fixed cost). Round 2's 7 074 did; the measured chain as
specified has 18 820 (two vector blocks + the 268 ns drain), so attention equals one GEMV unit at **L_eq = 16 384** (k ≥ 32:
403.2 µs there, 391.2 at 15 872 — T3r_crossover_rowmaxT; the same k on the chained corner, T3r_crossover_rowmaxC), and on the
attention path's own measured rates it is one block lower still: **15 872** at 167.0 / 169.0 / 169.2 (T3r_crossover_meas). The
fixed-shift variant (fixed 11 328) keeps 16 896 at 174.6 (T3r_crossover_lazyT) and crosses at 15 872 / 16 384 / 16 384 on the
measured rates. Over arbitrary L the chain as specified crosses monotonically at L ≥ 15 888 (T3r_crossover_anyL_rowmaxT: the
32nd block is charged from its first 16-token group); the fixed-shift variant is not monotone between 15 888 and 16 399 — the
vector tail of the ≤ 15 newest tokens decides (L mod 16 ≥ 9) — and crosses for good at 16 400 (T3r_crossover_anyL_lazyT). The
round-2 statements (16 896 over the 512-multiples, 16 400 over every L, 16 384 at the 384 µs unit: T_crossover, T_crossover_anyL,
T_crossover_384) remain true of the round-2 model and are superseded. Per *layer* the fraction depends on the layer's weight
bytes: for DESIGN-4's dense layer (3.19 GB, 18.26 ms) it is 4.5 % at 32k and 141 % at 1M on the design's page (round 2: 4.2 /
135); for its MoE layer (serial regime, 3.21 ms) 25.6 % at 32k and **100.8 % at 128k** — the attention/weights tie of §1.4. So decode
is attention-bound above ~16k tokens per 8192² GEMV-equivalent of weights, by the KV bytes alone — no kernel
choice changes that ratio except KV-int8 (halves it) or page size (G).


**The crossover, round 4** (`[R4-crossover-*]`, T4r_form_lazyT2, T4r_form_lazyT0, T4r_crossover, T4r_crossover_anyL). Two things move
it: the fixed cost (19 328 on the lazy chain, with the first-block max — round 3's 11 328 gave 16 896 at 174.6) and, with the bounce,
the stream term itself (13 512 instead of 12 011 ns per block at 174.6). Closed form for every L and every G ≤ 174.6 (the block is
DDR-bound on the lazy chain at every such G): step = nb₄(L) · ⌊23 592 960 / G⌋ + 15 172 + the tail, nb₄(L) = ⌈16⌊(L−1)/16⌋ / 512⌉ (with
both legs; 20 971 520 without). Over the 512-multiples attention equals one 398 µs GEMV unit at **L_eq = 14 848 (k ≥ 29) at 174.6 with
the bounce, 16 384 (k ≥ 32) without; 14 336 / 15 872 on the design page (169.2); 11 776 / 12 800 on the session-1 loop's 138.3**. Over
every L the crossover is monotone at 14 353 (174.6, legs 2), 15 889 (legs 0), 13 841 (169.2, legs 2); at 138.3 without the bounce it is
not: L ≥ 12 817, or 12 305 ≤ L with a tail of ≥ 15 tokens (the vector tail decides inside the 26th block). T_crossover's round-2 statement
(16 896) and round 3's (16 384 / 15 872 on the measured rates; 16 896 lazy) remain true of their models and are superseded. Per DESIGN-4
layer the MoE-128k cell is no longer a tie with the bounce: attention 3 589 µs against the 3 208 µs layer (§1.4, §10; T4r_fleet_moe_128k_*).

**The crossover, round 5** (`[R5-gemv]`, `[R5-crossover]`, `[R5-fleet-moe-128k]`; T5r_chord_guarded, T5r_chord_unguarded, T5r_nb_lines,
T5r_crossover_cells, T5r_fleet_moe_128k_*). Measured fractions of the 398 µs GEMV unit: **0.54 / 3.80 / 14.7 / 116.4** at 4k / 32k / 128k /
1M (guarded; 2.36 unguarded at 32k; round 4: 0.33 / 2.29 / 9.02 / 71.8). Between the measured 4k and 32k cells the crossover is read on the
chord over the 512-token blocks (DERIVED; the kernel is UNMEASURED in between): the guarded kernel reaches one GEMV unit at 16 blocks —
**every L ≥ 7 697** — and the unguarded one at 27 blocks — **every L ≥ 13 329** (iffs over the block count, ∀ nb ≥ 8, and over L; round 4:
14 336 over the 512-multiples and 13 841 over every L, at 169.2 with the bounce). Per DESIGN-4 layer the MoE-128k cell is attention-bound
on every reading: 5 852.9 µs guarded (+82.5 % over the 3 207.7 µs layer), 3 553.7 unguarded (+10.8 %), 3 573.7 fused (+11.4 %). On the
effective rate the line is G_eff ≤ 167.3 GB/s (every reading — 91.7 / 151.1 / 150.2 — is below it), and with the MEASURED legs-2 bounce
(204 µs per layer at 128k) the stream-only line is **G ≤ 178.7** (zero chain and zero fixed cost; ≤ 179.8 with the 19.3 µs lazy fixed cost)
against round 4's legs-2 line 189.4: attention-bound at every G ≤ 174.6 whatever the chain costs (DESIGN-4 round 5 restates T3r_moe128k_tie
on these numbers).


---

## 7. Regime map — where each variant wins (L × t × G branch × softmax corner)

**L does not change the regime.** Every per-block term is proportional to the block (T_online_L_independent,
T3_rows_star), so the binding engine of a (t, G, corner) cell is the same at 4k and at 1M; only the fixed costs
(7–30 µs) and the launch floor shift the 4k cells. The map is therefore t × G × corner, read at 32k
(`[A4c-regime-*]`, in-kernel µs, stream branch; g = 8 so rows = 8t):

| t (rows) | native exp + native max, ρ32 = 1 / 2 | native exp + tree max, 1 / 2 | poly exp + native max, 1 / 2 | poly exp + tree max (ISA.md as written), 1 / 2 |
|---|---|---|---|---|
| 1 (8) | **776** KV / 779 KV | 778 KV / 783 KV | 784 KV / 795 KV | 786 KV / **851 vector** |
| 2 (16) | 776 KV / 779 KV | 778 KV / 783 KV | 784 KV / 795 KV | 786 KV / 851 vector |
| 4 (32) | 783 KV / 789 KV | 787 KV / 796 KV | 799 KV / 1 453 vector | 856 vector / 1 703 vector |
| 8 (64) | 785 KV / 868 vector | 789 KV / 1 362 vector | 1 475 vector / 2 939 vector | 1 721 vector / 3 432 vector |
| 16 (128, 2 passes) | 1 554 KV / 1 714 vector | 1 558 KV / 2 693 vector | 2 917 vector / 5 824 vector | 3 406 vector / 6 802 vector |

Reading the map:
- **t = 1, 2 are the KV stream on 7 of 8 corners** (vector share 12–91 %); the eighth is the honest worst case
  and is 1.07× the stream. The t = 2 column equals t = 1 exactly: 16 rows fill the fragment that t = 1 pads.
- **Verify batches (t ≥ 4) are softmax-bound unless an exp instruction exists**: with a native exp the vector
  stays under the stream up to t = 8 (ρ32 = 1) or t = 4 (ρ32 = 2); with the polynomial it binds from t = 4 (ρ32 = 2 on both max branches, and at ρ32 = 1 with the tree max: 856 µs)
  or t = 8 (ρ32 = 1 with a native max) — T5_regime_binding. This is what E22 buys: at t = 8 the difference between the native and the
  as-written corner is 785 vs 3 432 µs (4.4×).
- **G multiplies the KV cells and never the vector cells**: on the gather3x branch every t ≤ 16 cell is
  DDR-bound (2 313 µs at t = 1, 4 629 at t = 16 — the stream time, 3× slower) except where the vector corner
  exceeds 3× (t ≥ 8 on the poly corners). The page64k branch (149.7) moves the KV cells by 1.17×.
- **The matrix route beats the vector-dot route in every cell** (T_gqa_matrix: the dot route is 4.04·ρ32× the
  stream at rows = 8 before any softmax work); the vector-dot route would win only at rows = 1 with ρ32 = 1,
  i.e. H_q = H_kv (no GQA) at t = 1 — and there it still carries the softmax on the same engine (c_V ≥ 7 →
  +12 %), so route M is never worse.
- **Two passes vs S4 at t = 16**: S4 (1 032 µs, vector-bound) beats two passes (1 554) only on the fully
  native corner; everywhere else the vector unit binds and the second pass is free.
- **KV-int8**: halves every KV cell; its vector cells are unchanged (+1 lane-op per score for the K scales), so
  it moves the softmax boundary down by one row: t = 1 is vector-bound already on the (poly, native, ρ32 = 2)
  corner (vec 91 % of a 512 B/token stream = 182 % of a 256 B/token stream).
- **d = 64**: KV cells halve, MMA share rises to 20.0 %·mt (80 calls per 512-token block: 2 × k = 32 per 16 tokens for the scores, 4 PV
  per 128 tokens), vector per byte doubles: the t = 1 DDR-bound condition tightens to c_V ≤ 30 (ρ32 = 1) / ≤ 14
  (ρ32 = 2) (T2_d64; round 1 said 16 % and 31 / 15) — the poly corners are vector-bound at t = 1.
- **H_kv = 1**: the same map with rows = t·H_q (32 at t = 1 for H_q = 32 → the t = 4 row), per-core KV bytes
  = 1/8 of the die's, passes = ⌈rows/64⌉, plus the partial merge (§9).

**Round 3 — the map on the measured chain** (`[R3-regime-*]`, T3r_regime, T3r_regime_binding; in-kernel µs at 32k on the
design's page, 167.0; the columns are the chain as specified at the throughput (T) and chained (C) convention and the fixed-shift
variant of §3.4 at both; "vec/ddr" = the per-block vector share):

| t (rows) | spec T | spec C | lazy T | lazy C | vec/ddr (spec T / spec C / lazy T / lazy C) |
|---|---|---|---|---|---|
| 1 (8) | **822** KV | 828 KV | 815 KV | 817 KV | 73.9 / 94.3 / 44.0 / 54.0 % |
| 2 (16) | 822 KV | 828 KV | 815 KV | 817 KV | the same: 16 rows fill the fragment t = 1 pads |
| 4 (32) | **1 225 vector** | 1 563 vector | 826 KV | 896 vector | 147.7 / 188.5 / 88.1 / 108.0 % |
| 8 (64) | 3 556 vector | 4 212 vector | 1 593 vector | 1 919 vector | 435.6 / 516.1 / 195.2 / 235.1 % |
| 16 (128, 2 passes) | 7 057 vector | 8 360 vector | 3 162 vector | 3 808 vector | the same per block as t = 8 |

Reading the round-3 map: t = 1, 2 are the KV stream on every chain (round 2's "7 of 8 corners" becomes 4 of 4, the chained corner
at 94 % of the block); **verify batches are softmax-bound from t = 4 on the chain as specified** (rows* = 32 — the per-row max
machinery doubles with mt while the block does not), from t = 8 on the fixed-shift variant (rows* = 48 at the throughput
convention, 32 chained); G never enters a vector-bound cell (the 174.6 column of `[R3-regime-*]` equals the 167.0 column from
t = 4 up); the matrix route still beats the vector-dot route everywhere (T3r_gqa_137: 5.5× the stream at rows = 8 before any
softmax work); S4 is dead (§2.4); KV-int8 moves the softmax boundary down one row on the chain as specified (t = 1 vector-bound:
612 µs) and not on the fixed-shift variant (413 µs). The round-2 map above describes the retired branches.

Where the fixed costs matter (round 3): at 4k the 91 µs launch floor is 76 % of the 119 µs step (wall 210 µs) and the
pipeline fill/tail 16 % (18.8 of 119 µs); at 32k 11 % and 2.3 %; at 1M 0.35 % and 0.07 % (`[R3-t1-*] wall`; round 2: 88 / 7,
12 / 1, 0.4 / 0.03 % with the 7 µs fixed cost). Fusing the attention
launch with a neighbour (§10) is worth more than any kernel change below 8k tokens.


**Round 4 — the map on the lazy chain with the bounce** (`[R4-regime-*]`, T4r_regime, T4r_rows_star; in-kernel µs at 32k on the design
page, 169.2; "legs 2" both bounce legs, "legs 0" none; the four columns are lazy-T / lazy-C / rowmax-T / rowmax-C):

| t (rows) | legs 2 | legs 0 | binding (legs 2) | vec/ddr at legs 2 (lazy-T) |
|---|---|---|---|---|
| 1 (8) | **912** / 919 / 917 / 925 | 813 / 820 / 817 / 826 | KV on every chain | 34.2 % |
| 2 (16) | 912 / 919 / 917 / 926 | 813 / 820 / 817 / 826 | KV (t = 2 = t = 1 + the 16 ns mask op) | 34.2 % |
| 4 (32, mt = 2) | **1 030** / 1 045 / 1 301 / 1 636 | 832 / 847 / 1 301 / 1 636 | KV on lazy, vector on rowmax | 61.6 % |
| 8 (64, mt = 4, 256-token blocks) | **1 301** / 1 629 / 3 908 / 4 601 | the same | vector on every chain | 104.8 % |
| 16 (128, 2 passes) | **2 565** / 3 213 / 7 756 / 9 132 | the same | vector | 104.8 % |

Reading the round-4 map: t = 1, 2 are the KV stream on every chain; **verify batches are DDR-bound through t = 4 on the lazy chain with
the bounce (rows* = 64, t ≥ 8 — the bounce bytes raise the DDR side; without it rows* = 48, t ≥ 6)** and vector-bound from t = 4 on the
rowmax chain (rows* = 32); the bounce never enters a vector-bound cell, so t ≥ 8 is bounce- and G-independent; S4 is dominated (§2.4);
KV-int8 is vector-bound at t = 1 on the rowmax chain (651) and unreachable on lazy (§3.4). The E35-first build order stands: the lazy
chain is the only one with slack at every t ≤ 4.

**Round 5 — the regime map on the measured kernel (§6.0; T5r_engines, T5r_per_fragment, T5r_rowmax_bound).** The t = 1 cells are MEASURED and
the binding engine is the serial chain (scores → softmax + guard → PV-merge-bounce), not the KV stream: the stream is busy 50.9 % guarded
and 82.1 % unguarded. Verify batches: 2 695.6 µs at t = 4 and 10 741.7 µs at t = 16 at 32k (round 4: 1 030 / 2 565); the guarded kernel
costs ≈ 20.3–24.0 µs per fragment per 512 tokens at every L, so a verify batch costs ≈ fragments × the single-fragment kernel — the rows* /
stream-amortisation argument of the round-4 map does not hold on the guarded kernel (the unguarded t ≥ 4 kernel is UNMEASURED). The rowmax
chain loses every cell to the guarded lazy chain (≥ 1 599 µs at 32k: its per-block crossing); KV-int8 on rowmax is ≥ 1 311 µs. Build order:
the batched guard (E39) first, then the phase overlap (E40).


---

## 8. Experiment ladder (continues DESIGN-2's E11–E20; every row has an observable failure)

Harness rules (DESIGN.md §8, unchanged): every destination pre-filled with a sentinel; every data path exercised
with two different sources through the same destination address (differencing); integer-valued inputs so every
expected value is exact (q, k, v ∈ [−7, 7] → scores |s| ≤ 7·7·128 = 6 272; with the identity-exp harness the
PV sums over one 512-token block are ≤ 512·6 272·7 = 2.25·10⁷ — above 2²⁴, so the dataflow tests use
|q| ≤ 1: |s| ≤ 896 and block PV sums ≤ 3.2·10⁶, f32-exact; i32-exact on the i8 build); pass = ≥ 20 reps bit-identical **and**
equal to the host reference; timing is recorded, never a pass criterion. The transcendental is removed from
every dataflow test by the **identity-exp harness**: `exp` replaced by the identity and the shift by 0, so
`out = (Q·Kᵀ)·V` is an exact integer GEMM-GEMM chain and the whole pipeline is checkable before E22 exists.

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **E21 — MEASURED (season v1, round 3)** | **G(P): the gather rate at page granularity** — result: 153.8 / 167.0 / 169.2 GB/s shuffled at 16 / 64 / 256 KiB, sequential 165.2 / 169.0 / 169.2, c_pg = 59 / 39 / 3 ns (a lower bound); verdict in §1.4, `[R3-E21-*]` | 8 cores, each 2 048 pages of P bytes at pseudo-random 64 KiB-aligned addresses in a 4 GiB arena (the visit order is a fixed LCG seed, so host and device agree), P ∈ {4, 16, 64, 256, 1024 KiB} plus a sequential control; the kernel's own path: DDR→L0B direct 32 KiB tiles (or P-sized when P < 32 KiB), full barrier per tile, one (16,16,128) MMA per call tile into one C region; page content = a per-page integer pattern (column sums distinct per page index); the drained C is compared with the host's sum over the visited pages; 20 reps | a skipped, repeated, stale or mis-sized page changes the total (differencing by construction); c_pg = slope of time-per-page vs page size (T1_gather_cells fits it); a rate above the sequential control is itself a failure (a load that did nothing) | every §6 cell (×G); the runtime's page size (§10); whether the "3× slower" risk is real |
| **E22 — MEASURED (season v1, round 3)** | the vector op set behind the softmax — result: exp f16 / f32 EXIST (272.8 ns per 1 024-lane call = 11.5 lane-equivalents, bitwise-exact on x ≤ 0), reduce-max EXISTS (181.9 / 251.4 ns per call), And<int32> ABSENT and And<int16> 45.9 ns, ρ32 = 1.37, σ_s = 19.9 ns; still open: the Duplicate / small-call latency (A3) and whether independent reels pipeline at the 40-lane/cycle wall (throughput vs chained convention, §3.2) | (a) exp of an integer-valued lane set {0, ±1, …, ±20} with the result compared to the host at 10⁻⁶ (a no-op returns the input bits, a half-rate unit shows in the count-mode timing); (b) reduce-max on a reel with one planted maximum per row, moved between reps; (c) And(x, 0x7FFFFFFF) on negative f32 bit patterns — the result must equal |x| exactly; (d) count-mode f32 Mul/Add over 1024 lanes, 10⁴ calls, vs the measured f16 figure; (e) the polynomial of §3.2 on the same lane set vs the host, relative error must be ≤ 1.6·10⁻⁴; (f) 256-iteration scalar max over a US reel with a planted maximum, timed | unchanged bits = no-op (errata #1); wrong planted-max position = a reduction that is not a reduction; a 1025-lane call keeping the sentinel beyond lane 1024 (errata #3 margin check); poly error above the bound = a rounding-mode no-op (errata #6) in one of the ops | c_V (the §3.2 table row), ρ32, the t ≥ 2 regime map, the 776-vs-851 µs headline corner |
| **E23** | the f16 B-fragment geometry H-F16 (K and V tiles) and the drained-C → A-fragment identity | DESIGN.md E1's pack probe with f16 tiles: K tile with k[l][j] = ((7l + 13j) mod 15) − 7, A = all-ones row → C[0, l] = Σ_j k[l][j] exactly; variants: (i) a second pattern through the same L0B address; (ii) one-hot A rows e_j → C[0, l] = k[l][j] for every j (settles the A-fragment order for q and P); (iii) the 2 × (16,16,32) sequence at d = 64; (iv) V tile probe: P = one-hot in token l → out = v_l exactly; (v) the chain: drain C_s, cast, copy to S1, L0LOAD, PV call — with the identity-exp harness the result is (Q·Kᵀ)·V, exact | column (token) permutation → the fragment is not [16 n × 16 k]; e_j on the wrong k → the A pack differs from §3.2; (v) wrong → the drained C nesting is not the A nesting (then a 2D re-layout copy is needed, costed in §9) | the page layouts §1.2–1.3 (host packer change only, free) and the zero-copy P path |
| **E24** | the direct-load choreography at this kernel's tile mix (K and V tiles interleaved, 2-block V lag) and the two exactly-full cases (L0A at mt = 4 / S4, L0C at mt = 4) | E13(a)-style accumulating oracle with alternating K/V tile patterns X/Y through the same L0B half, 10⁴ tiles, expected total exact; then the same with L0A filled to exactly 64 KiB (Q 32 + P 32) and L0C to exactly 256 KiB, content-checked; positive control: one full barrier removed | any stale/skipped tile changes the total; exactly-full aliasing shows X's sum where Y's is expected; a watchdog hang on the exactly-full L0A kills S4; a passing positive control means the detector is blind | the 174.6 rate assumption for the attention tile mix (E21's control row measures it); S4 (§2.4); mt = 4 in one L0C pass |
| **E25** | the KV append path: 8 × 32 B K copies (c_copy), the US→DDR 2D variant, COPY_FRAC of the 4 KiB V_tail block into 8 fragments, V_tail/K_tail plain appends | write token l's k and v (two different value sets through the same page slot), run the identity-exp kernel over a 17-token L (one full group + a 1-token tail) → out must change with the appended values and equal the host; time 10⁴ appends | unchanged out = a silent no-op append (errata #1); a wrong fragment landing shows as a permuted v; c_copy > 1 µs blows the 8 µs per layer-step budget (§1.2) → use the 2D copy or batch K like V | the per-step write cost (§10), whether K also goes through a 16-token tail |
| **E26** | the Z branch: three-region rotation with the f32 region-difference, drift under ±Q alternation, and the S1→US snapshot copy (R_drain is MEASURED in round 3: 152.8–285.5 GB/s/core, hidden at every mt — T3r_drain_hidden) | 2 048 blocks of integer scores through 3 regions with ±Q, the difference of each block compared to the host exactly (f32-exact while |region| < 2²⁴, which the test keeps — then a second run with real-valued q, k to measure the drift against f64); drain 10⁴ × 32 KiB regions, timed, content-checked (DESIGN-2 E12 reused); snapshot round-trip US→S1→US compared | difference ≠ expected → the drain or the Sub path is broken; drift above 10⁻⁴ relative → smaller blocks or the i8 variant; R_drain < 3.4 GB/s/core → exposed-drain rows of §6; a drain that runs on the vector engine shows as vector-time additivity in E28 | the Z branch, the drain rows, whether mt ≥ 2 can use S1 for snapshots |
| **E27** | end-to-end numerics and determinism | random f16 q, K, V at L ∈ {1k, 4k, 32k, 128k} (1M on a die with the memory), t ∈ {1, 2, 4, 8, 16}, 20 reps per config, host f64 reference, relerr ≤ 10⁻³; L chosen with every residue mod 16 and mod 256 (tail and page-boundary cases); a positive control with A3 deleted; the i8 variant's accuracy on the same inputs | relerr > 10⁻³ (f16 P rounding, poly error, drift); any rep-to-rep bit difference = missing barrier; the control must show islands; an L ≡ 1 (mod 16) case that fails = tail path bug | ship/no-ship; the i8 variant's admissibility |
| **E35** (round 3) | the fixed-shift variant of §3.4: guard correctness, exception rate and exception cost | real q / K at L ∈ {4k, 32k, 128k, 1M}, t ∈ {1, 4, 8, 16}, m_r from the first block, μ = 8; count guard firings per step and time the exception path; the identity-exp harness checks the guard itself (plant one P > e^μ: the block must be recomputed and the output must not change) | a guard that misses a planted overflow = a blind guard; exceptions above 1 per 3 blocks = the variant loses to §3.2; relerr > 10⁻³ after an exception = a broken rescale | whether verify batches (t ≥ 4) and KV-int8 run DDR-bound (§7) and whether L_eq is 16 896 or 16 384 (§6.3) |
| **E28** | the 40 % number | 100 queued launches at L = 32k and L = 1M, t = 1 (and t = 16), random q per launch so a stuck kernel repeats an output, every output checked vs the host reference, 20 reps bit-identical on fixed inputs; per-engine timers read back (DDR idle fraction, vector busy) | any failed check voids the timing; DDR idle > 10 % with a passing check = the vector engine or the drain is the wall (classifies the corner of §6) | reported ms at 32k and 1M, in-kernel and wall (launch floor from DESIGN.md E0) |

Order (round 3): E21 and E22 are measured; **E35 first** (it decides the verify-batch regime and whether KV-int8 pays), then
E23 and E24 together (the chain with the identity-exp harness: exactness before any transcendental), E26 (drift, snapshots),
E25, E27, E28. Round 2's order was E21 first, then E23 / E24, E22, E26, E25, E27, E28.


**Round 4 — the ladder after session 1** (what moved to MEASURED, what the review added, what is OPEN):

| # | Settles | Status / setup | Observable failure | Decides |
|---|---|---|---|---|
| **K-shape sweep — MEASURED (session 1)** | f16 (16,16,k) at k ∈ {16, 32, 64, 128} | EXACT on every k (128 reps per shape, one-hot k-probes at every k position, differencing through one L0B address, all 8 cores) — the gating row the review asked for, already run | — | §1.2: d = 128 k = 128 licensed, d = 64 single k = 64 (T4r_kshape) |
| **E23 — (i), (ii), (v) MEASURED (session 1)** | H-F16 (the f16 B fragment [16 n × 16 k] column-major, k-fragment-major), the f16 A fragment ([16 m × 16 k], m-row-major: Q and P), the f32 C nesting ([16 m][16 n] per 1 KiB chunk) and the zero-copy P premise | the scores half verified exact at 32k: 2 097 152 score elements, bad 0 | — | the page layouts and the P path stand; **open: (iv) the V tile at the real PV cadence** (blocked on the softmax-reel anomaly), the m = 64 C nesting (stride 4 096 B — only if an m = 64 PV call is ever used) |
| **E24′** | the direct-load choreography at the real P cadence **with the bounce**: K/V tiles interleaved with the P pieces' DDR → S1 staging and S1 → L0A lifts at 1/16 (mt = 1) and 1/4 (mt = 4) of the direct-load bytes; the rate of the US → DDR and DDR → S1 legs on the shared roof | the E13(a) accumulating oracle with alternating K/V patterns and one-hot P rows through the same L0A slot, 10⁴ tiles; the block time at legs 2 vs the round-3 cell | a stale P row (the E29 fault class: handshake faults after direct loads); the realised block time locates `legs` ∈ [0, 2] | the headline (912 vs 813 µs at 32k), rows*, L_eq, the MoE-128k verdict |
| **E26′ (was E26 / the session's K5)** | the ONLINE-CHAIN f32 drift (the region-difference drift is retired): O and S against f64 at 32k and 1M on both chains, two-level accumulation | real-valued q, K, V; relerr of out per row; the matrix unit's internal summation order (UNMEASURED) is inside the measurement | relerr above 246 ppm (1M) / 10 ppm (32k) × a small constant = an order the bound does not cover | ship at 1M on the deterministic bound (T4r_drift_online) |
| **E27′** | end-to-end numerics: **causal at t > 1** (the host reference masks the batch), the **planted sink** (one token at p = 1, the rest at 2⁻²⁵: expect 3.1 % row-mass loss at 1M with β = 0, none at β = 3), **prime-period host patterns > L** (erratum #21), fresh-set determinism | as E27, both chains | relerr > 10⁻³; any rep-to-rep difference; a mod-N pattern that passes while a prime-period one fails = aliasing | ship/no-ship; β |
| **E35 — the guard is MEASURED REQUIRED (session 1)** | the per-trip recompute is mandatory (9 / 8 192 lanes wrong per tripped block without it); still open: the trip rate per (model, L) at μ = 8, β = 3 and at μ = 0 (the KV-int8 × lazy cell), the trip cost (≈ 10.7 µs), the queue-fence cost of the guard read | as before, plus μ = 0 | trips above one per 2.1 blocks = the variant loses; a guard that misses a planted overflow = blind | the verify-batch regime; KV-int8 on lazy |
| **E36 — OPEN (session 2 owns it)** | the softmax reel: 75–91 % of P lanes read back as raw scores; deterministic; every isolated piece (exp, cast, reduce, drain, the C nesting) passes | the reel on the drained C_s in situ with differencing per op; the queue fence between the drain and the first vector op (erratum #15) is the first suspect | — | every vector-chain cell (OPEN in the ledger); E24′ and E26′ wait on it |
| E25, E28 | unchanged; E28 reports the realised G of the production loop (138–169) beside the in-kernel ms | | | |

Order (round 4): **E36 first** (nothing downstream of the reel can be measured until P is P), then E24′ (the bounce and the P cadence:
the headline's largest unmeasured term), E35 (trip rate at β = 3 and μ = 0), E27′ with the sink and the causal reference, E26′, E25, E28.

**Round 5 — the ladder after session 3** (what closed, what is new; statuses as MEASURED / DERIVED / UNMEASURED):

| # | Settles | Status / result | Observable failure | Decides |
|---|---|---|---|---|
| **E24′ — CLOSED (session 3)** | the bounce at the real P cadence | realised legs = 2, ≈ 51 µs at 32k — 51.4 % of the modelled roof charge (T5r_validate_terms) | — | the headline (now MEASURED) |
| **E26′ — CLOSED (session 2)** | the online-chain f32 drift | 1.2 / 1.8 ppm at 1M (512 / 256-token blocks): 205× / 272× inside the 246 / 490 ppm bound, 833× / 555× inside the ship line (T5r_drift) | — | ship at 1M |
| **E27′ — causal half CLOSED (session 3)** | end-to-end numerics | causal-exact 12/12 at 32k (relerr 9.8·10⁻¹¹), real-exp bad-0 through 1M; **open: the planted sink (β)** | 3.1 % row-mass loss at 1M with β = 0 | β |
| **E28 — CLOSED (session 3)** | the realised rate beside the ms | the t × L sweep (§6.0); the K+V stream phase 174–176 GB/s | — | the planner reads the measured per-layer time |
| **E35 — device half RESOLVED (session 3)** | the guard's cost | the SCAN costs 574.8 µs at 32k (8 981 ns per block); the trips ≈ free; **open (model half): the trip rate per (model, L) at μ = 8, β = 3 and at μ = 0** | trips well above the measured 0.087–0.22 % of steps = the batched guard's re-run term grows | the re-run term of E39; KV-int8 at μ = 0 |
| **E36 — CLOSED (session 2)** | the softmax reel | a host-side buffer overrun, not silicon (steering note, PROOF-COVERAGE-3) | — | — |
| **E39 (new) — the batched guard** | the guard decision as a vector side-product (the 8 vector-destination reduce calls into a per-block flag lane), ONE scalar crossing per step, optimistic merge, re-run on a trip | the 32k t = 1 cell; the residual over the unguarded 938.8 µs = crossings + side-product + re-runs (X per step) | X > 20 µs = the side-product sits on the serial chain (up to 93.1 µs at the round-4 convention); a planted trip without a re-run = a blind batched guard | fused ≈ 140 GB/s; **whether guard fusion outranks the direct-path expert kernel at MoE 32k (iff X ≤ 8 279 ns — DESIGN-4 round 5)** |
| **E40 (new) — phase overlap** | scores → softmax → PV overlapped across blocks (the 3 C_s regions were sized for it) | the 32k cell against the overlapped floor 821.8 µs (stream + bounce) | no gain = a hidden per-phase crossing (erratum #29 again) | up to 117 µs at 32k (12.5 %), 1.62 ms at 1M |
| E25 | unchanged | | | |

Order (round 5): **E39 first** (554.8–564.8 µs per layer at 32k; it decides the 32k lever rank), then E40, E35's model half, E27′'s sink
test, E25.


---

## 9. Risk register and fallbacks

| Risk | Trigger | Impact (from the model) | Fallback |
|---|---|---|---|
| **No exp instruction** | E22(a) — RESOLVED in round 3 | the native exp exists (272.8 ns per 1 024-lane call = 11.5 lane-equivalents, bitwise-exact on x ≤ 0): the polynomial branch is retired; the exp is 2.2 µs of the 9.3 µs chain. Round 2: c_V 7 → 28 / 33, the as-written corner 851 µs | — |
| **No cross-lane max / reduce** | E22(b) — RESOLVED, but the per-row max is the new top cost | the reduce-max exists (181.9 ns per call) yet reduces a whole call: a per-row block max needs the f16 tree (And<int32> is absent) + 16 calls per fragment = 2.9 µs + the rebuilt shift reel 0.9 µs — 41 % of the chain, the reason t ≥ 4 is softmax-bound and S4 is dead; the scalar tail at the measured σ_s = 19.9 ns would be 5.1 µs (42 % of the block, T3r_sigma) | the fixed-shift variant of §3.4 (E35); a row-major 2D drain + 16 strided per-row reduce calls would need the E5-class 2D P scatter (unmeasured) |
| **Gather 3× slower than stream** (c_pg ≈ 6 µs at 64 KiB) | E21 — MEASURED: c_pg = 39 ns at 64 KiB (a lower bound) | retired to a what-if column (2 325 µs at 32k, 73.8 ms at 1M); the measured page cost moves the cell by 1.3 % (64 vs 256 KiB), the choreography gap by 3.2 % (169.0 vs 174.6); 16 KiB pages cost 9.1 % | the page size is the lever: 256 KiB pages give 149.6 at the same c_pg = 2 µs and 1 MiB pages 167.6 (`[A1-G-*]`); the tail waste per sequence is (P_tok − 1) tokens × 4 KiB per layer (16 pages per layer: 4 MiB at 256 KiB pages, 16 MiB at 1 MiB pages — T1_tail_waste); if G is low at every page size, the bound is DRAM behaviour, not the layout, and the KV-int8 variant halves the bytes |
| f32 lane rate half the f16 rate (ρ32 = 2) | E22(d) — MEASURED: 1.37 | the f32-class ops are 17 % of the chain (1 559 of 9 276 ns); the chained-latency reading (2.69 per lane) is the round-3 worst corner, +0.6 % at t = 1 | — (the tree already runs in f16: And<int32> is absent) |
| L0C → US drain slower than 3.4 GB/s/core, or on the vector engine | E26 — MEASURED: 152.8–285.5 GB/s/core on its own path | hidden at every mt with 17–44× margin (268–368 ns per block); the exposed-drain and drain-on-vector rows of round 2 are retired | — |
| **Per-call latencies** (round 3) | E22 chained rates; A3 (small-call cost) | every 1 024-lane call costs 46–64 ns chained and a reduce-max 181.9 ns regardless of lane count: the 36 small calls + 16 reduce calls per fragment are 41 % of the chain; if independent reels do not pipeline (the chained convention) the chain is 98.5 % of the block at t = 1 with 175 ns of slack (T3r_t1_binding) | the fixed-shift variant (§3.4) removes 36 of the 52 calls; at t = 1 skip the 8 padding rows' reduce calls (7 820 ns, 65 %) |
| **MoE-128k attention / weights tie** (DESIGN-4 cell) | E21 + the fleet's T_layer | the cell sits within ±1 % of the flip at every page size ≥ 64 KiB: attention-bound at 64 KiB shuffled (by 0.8 %), weights-bound at 256 KiB (by 0.5 %); a real scattered cache (c_pg > 39 ns) flips it at any size (T3r_fleet_moe_128k_cells) | 256 KiB pages; K-int8 (bytes × 3/4) or KV-int8 on the fixed-shift chain; the fleet planner must not assume the weights-bound side at 64 KiB |
| f16 fragment is not [16 n × 16 k] | E23 | wrong scores (column permutation) — detected, never silent in the oracle | host/runtime packer change (free); if the drained C nesting ≠ the A nesting, add a 2D copy per P fragment (4 KiB·mt per 128 tokens; at 7 GB/s COPY_FRAC worst case 585 ns per 3 002 ns of DDR = 19.5 %, hidden on the copy engine) |
| Accumulator cannot be reset (Z) and the f32 drift bound fails | E26 | the difference epilogue is the design; drift ≤ 10⁻⁴ by the √-bound | the KV-int8 variant (exact i32 difference, DESIGN-2's proven path) or E11's reset — NOT smaller blocks: halving the block doubles the visits per region and raises both bounds (T_drift_blocks: 1 366 visits, random-walk 1 152 → ulp 2⁻¹³) |
| US budget (208 KiB + 64 B at mt = 1 as tabled vs 208 evidenced — T_buffers_us) | E7-class aliasing probe | snapshots cannot stay in US at mt ≥ 2 | snapshots in S1 (E26 proves the copy); Z-reset branch frees 96 KiB |
| **H_kv = 1 (degenerate GQA)** | shape | one KV head: all 8 cores split L (block-round-robin, ±1 block imbalance); rows = t·H_q per core (e.g. 32 at t = 1 for H_q = 32 → mt = 2; t = 16 → 512 rows = 8 passes); KV bytes are 1/8 of the headline shape so the DDR time per pass is 1/8 and 8 passes cost the headline's bytes; the 8 per-core (m, S, O) partials (16·mt rows × (1 + 16 + 128) f32 = 9 280 B = 9.06 KiB·mt each, T_hkv1_partials) are written to DDR and merged by the consumer kernel's prologue (the O-projection GEMM) — one extra launch only if the consumer cannot absorb it (+91 µs) | no change to the kernel; the merge is 8 × 9 280 B·mt of reads and ≈ 8·(2 048 + 272)·mt lane-ops |
| t·g > 64 rows (t = 16 at g = 8) | shape | two passes (KV read twice; 1 554 µs at 32k native) | S4 is dead on the measured chain (T3r_s4_dominated_*: it loses to two passes for every merge count); the fixed-shift variant (3 162 µs at 32k) or cap verify batches at t ≤ 8 per sequence at g = 8 (DESIGN-4 never runs a single sequence at t > 8) |
| 16-row padding at t = 1 (rows = g = 8, half the vector lanes compute padding) | design | 2× the necessary vector work at t = 1 (already in c_V's accounting) | the 2D row-selective drain + 2D P scatter if E5-class 2D copies exist at ≥ 1/8 of the DDR rate |
| K append cost (8 small copies per token per head) | E25 | ≤ 8·c_copy per layer-step on the writer core (8 µs at c_copy = 1 µs; 2 % of a 398 µs GEMV step) | one 2D copy, or a 16-token K_tail with COPY_FRAC like V (then the tail path covers K too — it already does) |
| d = 64 shapes | shape | 2 × (16,16,32) calls per 16 tokens (k = 64 illegal): 80 MMA calls per block, 20.0 %·mt instead of 8 % (T2_d64); KV bytes halve so every DDR cell halves and the vector share per byte doubles (c_V ≤ 30 / 14 at ρ32 = 1 / 2 for t = 1 DDR-bound) | accept; the i8/poly corners become vector-bound at t = 1 |
| Launch floor | DESIGN.md E0 | +91 µs per layer-step unless launches pipeline (88 % of the 4k step, 12 % at 32k) | fuse the attention launch with the QKV epilogue / O-projection prologue where the runtime allows |
| Errata compliance | — | #2: every transfer ≤ 32 KiB (tiles), ≤ 4 KiB (P pieces), ≤ 64 KiB (COPY_FRAC source); #3: all vector calls ≤ 1 024 lanes (the reels are exactly 1 024); #5: no f16 accumulation anywhere; #6: casts verified by E9/E22; #7: out leaves through US; #8/#14: full barriers on direct loads, pipe barriers A1–A13, no queue staging; #9: depths = counts; #12/#13: no i4 anywhere, i8×i8→i32 only in the variant; k = 64 never issued; n ≤ 16 per call; init flags not relied on | — |


**Round 4 — the risk rows the review and session 1 added or re-aimed:**

| Risk | Trigger | Impact (from the model) | Fallback |
|---|---|---|---|
| **The P bounce costs its bytes on the DDR roof** (erratum #20: no US → S1 plain copy of an A slot) | E24′ | legs 2: +12.5 %·mt on the t = 1 block (912 vs 813 µs at 32k; 28.6 vs 25.4 ms at 1M); the MoE-128k cell attention-bound at every G; L_eq 14 848 | legs 1 (862 µs) if the write leg is free on this part; the one exact variant of the three US → S1 probe variants (HW-MAP: "1-of-3 exact, cold-pipe-class") re-probed as a legs-0 route — UNMEASURED |
| **The softmax reel (OPEN)**: 75–91 % of P lanes = raw scores | E36 (session 2) | no cell moves until it lands; every vector-chain cell is OPEN | not modelled around; the queue fence (erratum #15) between the drain and the reel is the first suspect |
| **The production loop's gather rate** | E28 | the session-1 diagnostic loop measured 138.3 GB/s, page-insensitive (1 111 µs / 35.0 ms at t = 1); the production loop halves the barriers per byte: UNMEASURED between 138 and 169 | the planner reads the realised G; the page-size lever (−1.3 %) is inside this uncertainty |
| f16 accumulation across barriers (erratum #19) | measured | no f16 accumulate chain anywhere in this design (fresh chunk sets); d = 64 must use the single k = 64 call; the i8 variant may accumulate | — |
| Lazy guard without the recompute | measured | 9 / 8 192 lanes wrong per tripped block | the recompute is in the spec (§3.4 (c)) |
| The first-block max on every step | design | 5.2 µs per step on the lazy chain (4 % of the 4k step) | a prefill-calibrated m_r (trip rate UNMEASURED) |
| KV-int8 on the lazy chain | E35 at μ = 0 | unreachable at μ = 8 (P up to e⁸ at scale 127); 651 µs vector-bound on rowmax | μ = 0 if its trip rate allows; else K-int8 only (ALTERNATIVES row 7) |
| The planted sink | E27′ | 3.1 % row-mass loss at 1M with β = 0 | β = 3 (cost 0) |
| Causality at t > 1 | E27′ (causal host reference) | 32-token tails (8 KiB each) and the per-row additive mask; the vector tail is 64 µs at t = 16 worst case | — |
| Page waste in the planner | fleet.py `[R4-waste-*]` | 4 MiB per layer-sequence at 256 KiB: 120 MiB per instance die against 2–30 MB margins (+1–3 ‰ of int4 share), 60 MiB on the dense 1M KV-int8 die (1.5 GB left) | 64 KiB pages cut it to 1 MiB (30 MiB per instance die — still above every margin) |
| The C destination and the host patterns | errata #18, #21 | silent chunk-0 landing; aliased verification | byte-offset tensors; prime periods > L |

**Round 5 — the risk rows session 3 added or re-aimed:**

| Risk | Trigger | Impact (measured / derived) | Fallback |
|---|---|---|---|
| **Per-block scalar crossings** (erratum #29) | any per-block scalar read | 8 981 ns per block as shipped (574.8 µs at 32k = 38 % of the cell); tree + queue / tree + barrier +1 250 / +1 400 µs (measured) | the batched guard (E39): one crossing per step |
| The batched guard's side-product lands on the serial chain | E39 | ≤ 1 455 ns per block at the round-4 convention: fused 958.8 → ≤ 1 051.9 µs at 32k | overlap it with the chain (E40) |
| A trip under the batched guard | E35 (model half) | one re-run per tripped step: ≤ 0.22 % of a step at the measured rate (≈ 2.1 µs at 32k) | per-block flags + a ring of 8 partials (+64 KiB of US at mt = 1) |
| The rowmax fallback / switch policy | erratum #29 | ≥ 10 318 ns per block of crossings: ≥ 1 599 µs at 32k — never cheaper than the guarded lazy chain | stay on lazy; never switch |
| KV-int8 | erratum #29 | rowmax ≥ 1 311 µs at 32k (round 4: 651) | the lazy μ = 0 route (trip rate UNMEASURED) |
| Verify batches (t ≥ 4) scale with the fragment count | measured | t = 4 / 16 at 32k: 2 695.6 / 10 741.7 µs (2.6× / 4.2× the round-4 cells) | the batched guard, then E40, at mt ≥ 2; the unguarded t ≥ 4 kernel is UNMEASURED |
| The validation is a net of terms | T5r_validate_terms | the 2.9–3.0 % match hides −97.7 / +48.1 / +22.4 µs term errors; a change that moves one term alone loses the match | re-validate per term (stream phase, bounce, exposed chain) |
| Erratum #30 (B-slot ping-pong state carries across loop nests; per-region loop bounds) | spec | a consumer expecting "tile 0 preloaded" reads stale K/V; a strips·2 bound writes into a neighbour core | every consumer resets the ping-pong state; per-region bounds |


---

## 10. Integration note — what the serving runtime must provide

1. **KV write path per layer (inside the attention launch, by the head's own core).** After the QKV GEMM has
   produced k_l, v_l for the new token(s) (t of them per step), the attention kernel's epilogue appends: K
   directly into the fractal page (8 × 32 B copies per token per head, §1.2, or one 2D copy per E25), V as a
   256 B row into V_tail, and — when a 16-token group completes — one COPY_FRAC of the 4 KiB V_tail block into
   its 8 fragment slots (585 ns). The K_tail row is also kept (so the vector tail can serve K and V uniformly;
   8 KiB per head per layer). The current step's own tokens are attended from the tails, so the append is
   not on the critical path of the same step's matrix work: the order is "append, then attend", with A12/A13 of
   §5 fencing the copies. With t > 1 (verify batches) the t new tokens enter the tails together; a group that
   completes mid-batch is fractalised in the same epilogue.
2. **Page ownership.** KV is die-local to its layer (errata #11): a layer's pages, tails and tables live on the
   die that runs the layer; nothing attention-related crosses a die boundary (DESIGN-4 §1.3 placement). The
   runtime allocates 64 KiB pages per (layer, head, K|V) from a die-local pool and maintains the flat page
   tables (one 8 B entry per page); the kernel reads the table window (4 KiB = 512 pages = 128k tokens) from
   DDR into US and indexes it with the scalar unit. Page size, round 3 (E21 measured, `[R3-page-*]`): **256 KiB pages by default** (169.2 GB/s; 4 MiB of tail waste per
   layer-sequence), 64 KiB where the allocator's granule forces it (167.0, −1.3 %; 1 MiB of waste) — and for the DESIGN-4
   MoE-128k layers 256 KiB is a constraint, not a preference (§1.4: 64 KiB puts that cell on the attention-bound side by 0.8 %);
   never 16 KiB (153.8, −9.1 %); the two-tier extents of ALTERNATIVES §2.5 only if a real scattered cache measures c_pg ≥ 160 ns
   at 64 KiB (T3r_page_tier); the kernel takes P_bytes as a parameter (a multiple of 32 KiB so that tiles never straddle pages).
3. **q layout.** The QKV epilogue writes q for the g query heads of each KV head pre-scaled by 1/√d (a scalar
   fold into the Q projection's per-channel scale, free) into the A-fragment order of DESIGN.md §3.2 (32 B runs
   at stride 512 B — the scatter DESIGN.md already budgets) or row-major, in which case this kernel's prologue
   runs one COPY_FRAC per fragment (585 ns·mt). Verify batches: rows are ordered (token, query head) so that a
   16-row fragment holds whole tokens where g | 16.
4. **Output.** out[rows × d] per head is written f16 in C-slab order or row-major (the epilogue scatter, ≤ 32
   KiB); H_kv = 1 or 8 ∤ H_kv shapes write per-core (m, S, O) partials (9 280 B = 9.06 KiB·mt per core) and the consumer
   (O-projection) prologue merges them (§9).
5. **Prefill.** Out of scope for the step model, but the layouts need it: a prefill writes pages in fractal order
   either by the same per-token path (slow: 8 copies per token) or by bulk COPY_FRAC of row-major K^T / V blocks
   (7 GB/s/core = 56 GB/s per die: 128 MiB of K+V per layer at 32k in 2.4 ms per layer) — a prefill kernel that
   emits fractal order from its own L0C drains would avoid even that.
6. **Launch structure.** One launch per layer-step for attention (plus fusion with the QKV epilogue / O prologue
   if the runtime allows, saving one 91 µs floor); no cross-core sync is required at any point.
7. **What the runtime must not do.** Reallocate or compact pages behind the kernel (the table window is read
   once per 128k tokens); place K and V of one head on different dies; use pages smaller than 32 KiB with this
   kernel (tiles would straddle pages); zero pages (unnecessary — the kernel never reads beyond 16⌊L/16⌋).


**Round 4 — what changed for the runtime (session 1, the review's items 6 and 11):**
8. **Append-then-attend, spelled out.** The pages hold the 16-token groups completed BEFORE this step (L − t tokens); the current step's
   t tokens and the open group are served from the tails, so **K_tail / V_tail hold 32 tokens (8 KiB each at d = 128)**: the tail is
   (L − t) mod 16 + t ≤ 15 + t tokens (31 at t = 16 — the 16-token tail of round 3 cannot hold it; T4r_tail_bound), the vector path
   applies the **per-row additive causal mask** over the ≤ 2 token groups of the tail (−65 504 at lanes j > i for query token i; one
   512·mt-lane Add per step, 16 ns·mt), and nothing in the matrix path needs masking because no batch token is ever in a page during its
   own step. At t = 1 this makes the tail 16 tokens at every 512-multiple (4.2 µs of fixed cost); the group completed by this step is
   fractalised in the epilogue and read from its page next step. E27′'s host reference is causal.
9. **Page size and the realised rate.** The kernel takes P_bytes as a parameter (a multiple of 32 KiB). A 256 KiB page is **four 64 KiB
   sub-pages**: sub-page (l mod 1024) div 256, inside it the §1.2 / §1.3 maps unchanged (T4r_page256_*: a bijection onto the even bytes of
   [0, 262 144) with explicit inverses); the 4 KiB table window then covers 512 × 1 024 = 524 288 tokens (131 072 at 64 KiB). The MoE-128k
   verdict is NOT a page-size question any more: with both bounce legs it is attention-bound at every G ≤ 174.6 (T4r_fleet_moe_128k_legs2),
   without them a ±1 % tie — the planner reads the realised G of the production loop (the session-1 diagnostic loop: 138.3, page-insensitive)
   and the realised bounce, never a side.
10. **Page waste is budgeted.** One partially filled page per (head, K|V) per (layer, sequence): 16 × (P − 256 B) = 1 / 4 / 16 MiB at
    64 KiB / 256 KiB / 1 MiB (T4r_waste; fleet.py `[R4-waste-*]`, `[R4-mem-*]`, `[R4-inst-fit-*]`): 60 MiB per 15-layer dense die at B = 1
    (480 at B = 8), 16 MiB per 4-layer MoE die, 120 MiB per 30-layer instance die — above every instance-fit margin of DESIGN-4 (+1–3 ‰ of
    int4 share at 256 KiB, +0–1 ‰ at 64 KiB); L_max drops by ≈ 0.2 % (551 253 → 550 230 dense f16 at 256 KiB); the dense 1M KV-int8 layout
    keeps 1.5 GB of margin. ALTERNATIVES §2.5's memory argument for two-tier pages (waste ≤ 1 MiB) is real but buys 3 MiB per layer-sequence
    against a 1.3 % rate gain that 256 KiB pages already capture — dominated unless the instance fit is the binding constraint, where the
    64 KiB page (1 MiB of waste, −1.3 % of G) is the cheaper lever.
11. **The P scratch.** 2 × 16 KiB·mt of DDR per core (O(1)) for the bounce, allocated with the page tables; the DDR → S1 staging of P
    rides the same bulk A-staging route the expert kernel measured ("one pack per launch" there, one pack per block here).
12. **Verification data.** Host patterns for any token-mapped check use prime periods > L (erratum #21); every L0C destination the
    kernel addresses is a byte-offset tensor (erratum #18).
13. **The planner reads the measured per-layer attention, not G (round 5).** The t × L sweep is the attention term (DESIGN-4 round 5):
    guarded = MEASURED at every L; unguarded = MEASURED at 32k (938.8 µs), elsewhere the guarded cell minus the per-block guard; fused =
    unguarded + one crossing per step (the target, E39). At t = 1 both DESIGN-4 shapes run mt = 1 (dense rows 16, MoE rows 4) — the measured
    kernel's shape — so the per-layer time transfers as is; verify batches transfer by fragment count (dense t = 4 = one mt-4 pass of the
    measured t = 16 cell, MoE t = 4 = the measured t = 1 cell — DERIVED readings, not measurements).
14. **No per-block scalar crossing in a production kernel (erratum #29).** Scalar decisions are computed as vector side-products and
    crossed in batches; a kernel interface that exposes a per-block scalar decision (the guard verdict, a per-block scale) is batched per
    step, with a re-run path for the rare positive.


---

## Appendix A — claim ledger (for the round-2 proof session: `proof/attn.py` labels and proposed theorem names)

Round 2: theorem names below are the realised proof/attn.lean names; the row-by-row status is in PROOF-COVERAGE-3.md.
Round 3: the measured constants re-instantiate rows 4, 5, 7–9, 11–17, 23–25, 28, 29 and 31–33 as the `T3r_*` theorems; the
round-3 section of PROOF-COVERAGE-3.md lists them (rows R1–R34) with their `[R3-*]` labels and the cells they supersede.
Status: M = HW-MAP input; D = derived here (theorem target, `decide`/`omega` over Nat with the unmeasured
quantities as explicit arguments — G, c_pg, c_V, ρ32, R_drain, σ_s, MERGE_OPS); A = assumption measured by the
named experiment; U = empirical branch. Every row's number is printed by the label in `proof/attn.py`.

| # | claim | value | status | attn.py / theorem |
|---|---|---|---|---|
| 1 | kv_tok = 2·H_kv·d·2 = 4 096 B; per core 512 B/token; KV per layer at 4k/32k/128k/1M = 2²⁴ / 2²⁷ / 2²⁹ / 2³² B | | D | [A0-shape] [A0-kv-*] T0_kv_bytes |
| 2 | page table bytes = 2·H_kv·8·⌈L/256⌉: 2 048 / 16 384 / 65 536 / 524 288 B | | D | [A0-kv-*] T0_page_table |
| 3 | K page address bijection (§1.2) and V page address bijection (§1.3) on [0,256) × [0,128) → [0, 65 536) | bijective | D | T_kpage_bijection, T_vpage_bijection (linear, omega with bounds) |
| 4 | G(P) = 8·P·10 / (P·80/1746 + c_pg) tenths: the §1.4 table (15 cells) | | D (c_pg U) | [A1-G-*] T1_gather_cells, T1_gather_cells; monotone in P and in c_pg: T1_gather_monotone_cpg |
| 5 | block DDR time at 174.6 = 2 MiB·10/1746 = 12 011 ns; per-core share 21.8 GB/s | | D | [A2-block] T2_block |
| 6 | per block: MMA 960·mt ns (8.0 %), loader 618·mt ns (5.1 %), drain bytes 40 960·mt, scalar 512·mt ns | | D | [A2-block] T2_block_mt |
| 7 | drain hidden iff R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1..4 (35 / 69 / 123 / 164 tenths as an iff; round 1 said 3.4·mt and 136); at 10 GB/s 4 096·mt ns = 34.1 % | | D (R_drain U) | [A4b-drain-threshold] T2_drain_threshold (iff over R_drain) |
| 8 | vector per block = (8 192·c_V + 7 000)·mt·ρ32·10/432 ns: 1 489 … 12 839 ns at mt = 1 (the §3.2 table, 8 cells) | | D (c_V, ρ32 U) | [A2-vec-*] T_softmax_block, T3_vec_cells |
| 9 | t = 1 DDR-bound iff c_V ≤ 62 (ρ32 = 1) / ≤ 30 (ρ32 = 2); the (33, 2) corner is 106.9 % | | D | [A4b-cV-threshold-*] T3_t1_ddr_bound (iff over c_V for each ρ32) |
| 10 | vector-dot route / KV stream = rows·ρ32·4·d·1746·10 000 /(80·512·432) tenths of % = 50.5 %·rows·ρ32 (10 cells) | | D | [A3-vecroute-*] T_gqa_matrix |
| 11 | rows* (vector ≥ DDR per block): 112/80/48/32 (ρ32 = 1; round 1 said 128), 64/48/32/16 (ρ32 = 2) for the four (E, R) corners | | D | [A3-rows*-*] T3_rows_star (least rows, both sides proved) |
| 12 | t = 1 step: T = max(ddr, vec, mma, loader) + fixed; the 24 cells of §6.1 (L × G × 2 corners) incl. effective GB/s and GEMV fractions | | D (G, c_V, ρ32 U) | [A4-t1-*] T4_t1_4k … T4_t1_1M (one theorem per L; ∀ G in [582, 1746]: T_step_t1_G_bracket) |
| 13 | t = 1 with the drain on the vector engine: 1 114 µs (32k) / 34 713 µs (1M) on the worst corner; unchanged on the native corner (95 296 + 262 144 < 768 704) | | D | [A4-t1-*] (drain on the vector engine) T4_t1_drain_same |
| 14 | t = 16: rows = 128, passes = 2, mt = 4, block 256; the 24 cells of §6.2 | | D | [A4-t16-*] T4_t16_4k … T4_t16_1M |
| 15 | S4 single pass: chain 1 236 + 960 = 2 196 ns per 128 tokens = 73.2 % of 3 002; step 1 032 µs / 32.4 ms (native, vector-bound) vs 1 554 / 49 209 two-pass | | D (gated E24) | [A4b-onepass-*] T4_s4_chain, T4_s4 |
| 16 | KV-int8: t = 1 391 µs / 12.3 ms (native corner, DDR-bound), 851 / 26.3 (worst corner, vector-bound) | | D | [A4b-i8-*] T4_i8 |
| 17 | online vs two-pass: +6 005 ns of K per block vs 324 ns of merge → 18×; L-independent | | D | [A5-online] T_online, T_online_L_independent |
| 18 | the online merge is exact: Σ_b e^{m_b − m}·(Σ_{l∈b} e^{s_l − m_b} v_l) = Σ_l e^{s_l − m} v_l | identity | D (real-number identity; stated over ℚ-scaled integers or left as DEFINITION) | T_online_exact |
| 19 | poly exp bound: 2⁷·(22/128)⁵/5! ≤ 1.6·10⁻⁴; f32 rounding 2⁷·2⁻²⁴ | | D (rational arithmetic) | [A7-poly] T_poly_bound |
| 20 | drift bound of the ±Q region content: deterministic ≤ 683·32 = 21 856 at 1M (ulp 2⁻⁹) for every sign pattern; ≈ 840 (ulp 2⁻¹⁴ = 6·10⁻⁵) under the random-walk hypothesis; smaller blocks raise it | | D (worst case) / A (random-walk; E26 measures) | T_drift_alt, T_drift_1M, T_drift_blocks |
| 21 | SRAM budgets: L0C 112/224/192/256 KiB (mt = 1..4), US 208 KiB + 64 B at mt = 1 as tabled (112 on Z; round 1 said 200/104), 196 KiB + 64 B at mt = 4 (not 180), L0A 16·mt = 16/64 KiB (not 16/48), L0B 64, S1 208/168/224 KiB ≤ 230 — none depends on L | | D | [A7-*] T_buffers_no_OL, T_buffers_us / T_buffers_l0c / T_buffers_l0a / T_buffers_s1 |
| 22 | KV-write per step: V COPY_FRAC 585 ns per 16 tokens; vector tail ≤ 122 880·mt lane-ops = 5 688 ns·mt (ρ32 = 2) | | D | [A6-kvwrite] T_kvwrite, T_tail |
| 23 | attention / GEMV-unit fractions: 25.9 % / 194.9 % / 774.3 % / 6 182.3 % (t = 1, stream, native); L_eq where attention = one GEMV unit: 16 896 tokens (T_crossover) | | D | [A4-t1-*] T_fraction, T_crossover |
| 24 | regime map §7: the binding engine per (t, G, corner) cell | | D | [A4-*] bind= column; T5_regime_t1 … T5_regime_G |
| 25 | G branches: stream 1746, page64k(c_pg = 0.5 µs) 1497, gather3x 582; the "3× slower" case is c_pg = 6 005 ns at 64 KiB | | D | [A1-branches] T1_gather3x_cpg |
| 26 | the 32 KiB tile never straddles a 64 KiB page; pages are multiples of 32 KiB | | DEFINITION | — |
| 27 | errata compliance list (§9 last row): every transfer ≤ 64 KiB, every vector call ≤ 1 024 lanes, no k = 64, n ≤ 16, no f16 accumulation | | DEFINITION (checked by construction in attn.py's constants) | T_errata_sizes |

Assumptions carried as explicit hypothesis variables (bracket endpoints to be proved in round 2): c_pg ∈ [0, 6 005],
c_V ∈ {7, 12, 28, 33}, ρ32 ∈ {1, 2}, R_drain ∈ [34, ∞), σ_s = 2, MERGE_OPS = 7 000, R_gemm = 1746 as the
stream rate (the measured kernel's rate, not the 181.3 raw direct stream).
Round 3: of these only the merge count remains a hypothesis variable (25 750 pack / 64 851 itemised; every verdict is
insensitive, T3r_merge_*, T3r_s4_dominated_*); the new assumption is A3 (a 16-lane Duplicate or copy costs one chained f16 call,
46.4 ns — E22), and the modelling choice T vs C (whether independent reels pipeline at the 40-lane/cycle wall or every call pays
its chained latency) is carried as the headline / worst-corner pair.


Round 4 (2026-11-07): the review's eleven items and session 1's measurements are the `T4r_*` theorems (66, listed in PROOF-COVERAGE-3.md
rows R4-1–R4-30 with their `[R4-*]` labels). New hypothesis variables: `legs` ∈ {0, 1, 2} (the P bounce's transfers on the DDR roof,
UNMEASURED, headline 2) and the fresh-set merge (itemised, 15 431 lazy / 70 462 rowmax lane-eq, carried as `m` in the iffs); new
assumptions: A4 (the k = 64 / k = 16 issue cost equals the measured k = 128's 15 ns), A5 (the guard's queue-fence read under 1 µs); the
conventions T / C and the chain cells are carried as OPEN until the softmax-reel anomaly (E36) lands. Retired as hypotheses: the pack's
merge 25 750, the region-difference drift's random walk (its mechanism cannot be built: erratum #19), the i8 k-shape facts on f16.


Round 5 (2026-11-07): session 3's measurements are the `T5r_*` theorems (27, listed in PROOF-COVERAGE-3.md rows R5-1–R5-22 with their
`[R5-*]` labels). Resolved as hypotheses: `legs` = 2 (MEASURED), the production loop's rate (the sweep), A5 (refuted: 8 981 ns per block),
the OPEN chain cells (E36 closed), the drift (E26′ closed). New hypothesis variables: the crossing cost cx ∈ [10, 20] µs and the batching
factor K (erratum #29; `xing`, ∀ nb, K, cx), the batched guard's residual X per step (E39), and the per-block guard off 32k (the scaling rule
of the unguarded / fused readings; the constant-rate reading is carried beside it as the bracket). The t ≥ 4 transfers by fragment count and
the chord crossover are DERIVED readings of measured cells, not measurements; the rowmax crossing (≥ 10 318 ns per block) is a lower bound on
an UNMEASURED structure.
