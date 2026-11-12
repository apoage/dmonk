# DESIGN-4 — fleet partition planner (4 cards × 2 dies, no P2P, layer-split-only runtime)

> **ROUND-6 STATUS (2026-11-08 — the MEASURED deferred-guard cells are the attention term; kernel session 5, HW-MAP 3928d0e; `proof/fleet.py`
> `[R6-*]`, `proof/fleet.lean` `T6r_*` (20 new theorems, 334 total, 0 axioms / sorry / native_decide; `lake build` clean), PROOF-COVERAGE-4
> rows F6-1 … F6-14).** fleet.py's first 676 output lines are byte-identical (alt.py's output unchanged). The per-layer attention at t = 1
> is the MEASURED deferred-guard kernel (DESIGN-3 §6.0′): **945.5 µs trip-free at 32k (142.0 GB/s; 946.3–947.4 amortized at the trip
> premise, 141.8–141.7), 3 618.8 at 128k (148.4), 28 694.0 at 1M (149.7)**. **Cells, t = 1: MoE 32k 1.755 trip-free / 1.754 amortized
> (round 5: fused reading 1.750, unguarded 1.757, the legacy scan 1.578), dense 32k 0.104 on every reading; MoE 128k 1.150 (round 5 fused
> 1.157), MoE 1M 0.271 (0.278), dense 128k 0.091** — at 128k / 1M the measured cells are 1.3 / 2.7 % slower per layer than round 5's
> fused readings (its off-32k per-block rule was optimistic). **MoE 128k stays attention-bound on the measured cell**, by 12.8 % per layer
> (anchored; 37.0 % direct) and 101.32 vs 92.82 ms per step, and even E40's floor leaves it 2.5 % over; MoE 32k stays weights-bound
> (attention 18.6 % of the step), MoE 1M attention-bound (87.4 %). **The 32k rank question is answered — a tie on the line:** the realized
> guard fusion (legacy → deferred) outranks E29 iff the cell is ≤ 947 079 ns = 141.7 GB/s (∀ T, T6r_tie32k, round 5's basis); the measured
> band straddles it (fusion leads by 0.28 / 0.14 % at the trip-free / low-rate readings, E29 by 0.06 % at the high-rate one; on the
> same-session legacy 1 514.9 µs the line is 948 379 ns = 141.5 GB/s and fusion leads at every reading by 0.17–0.51 %). **At 128k / 1M
> attention wins outright:** the tie lines are 101.6 / 93.9 GB/s, and the banked fusion is 62.55 / 493.34 ms per token against E29's 15.86
> (3.9× / 31.1×). **Post-fusion ranking (§10‴, T6r_levers6):** the stage overlap (E40; a bound gated on φ) is the attention-side #1 on
> every cell — above the bounce removal at both ends of its F1/F2 bracket; E29 stays the expert-side lever and the largest remaining lever
> on MoE 32k / 128k (15.86 ms vs E40 ≤ 3.46 / 9.28); at MoE 1M E40 ≤ 67.09 > bounce 45.69 > E29; the bounce removal is last everywhere
> except MoE 1M (second there, as in round 5) and needs an unproven US → S1 route (#20). **Spec decode at the fused G (§6.6):**
> T_spec_moe_loss survives with its line moved **0.807 → 0.854** on every deferred reading (∀ α); dense spec is affine in the verify
> kernel's attention v (UNMEASURED on the deferred kernel at t ≥ 4) and at α = 0.7 beats t = 1 for every v ≤ 31.09 ms per layer (32.8×
> the t = 1 cell); at the fragment-serial / ratio-scaled / legacy-verify readings of v the dense spec cell is 0.225 / 0.229 / 0.211 with
> breakevens α ≥ 0.146 / 0.130 / 0.201. MoE B = 16 2.247; two instances (V3 with the erratum-#19 merge) MoE 3.576 / 3.504, dense 0.149 /
> 0.140 — the instance verdict holds (c ≥ 0.978–0.998 of the measured 1.990). T_min_dies is untouched. The round-5 guarded column is now
> the legacy A/B control; the rounds-2…5 and PROMPT-6 banners and bodies are kept.

> **PROMPT-6 AUDIT (2026-11-08 — errata #18–#31, the corrected #3 and the widened #25 against this design; `proof/fleet.py` `[PA-*]`,
> `proof/fleet.lean` `T6f_*` (4 new theorems, 314 total, 0 axioms / sorry / native_decide; `lake build` clean); PROOF-COVERAGE-4 rows
> PA4-1 … PA4-4; all five designs in ERRATA-IMPACT.md).** No new silicon; fleet.py's first 669 output lines are byte-identical (alt.py's
> output unchanged); every correction is marked **audit** in place. DESIGN-4 writes two kernel patterns of its own (the V3 cold tier,
> the KV-int8 route) and consumes the rest as cells that inherit their designs' audit status. **What moves:** (1) **erratum #19 VIOLATES
> the V3 cold tier** (§1.8: f16 × f16 → f32 accumulation of K across the per-piece barriers and the A re-lifts, and the region-difference
> epilogue is itself such a chain) — fresh chunks + the vector f32 sum (ALTERNATIVES' fix): V3 MoE 32k **3.720 → 3.693** (throughput) /
> 3.617 (chained), round-5 readings at c = 1.990: guarded 3.230 → 3.209 / 3.151, fused 3.567 / 3.495; dense 0.155 → 0.150 / 0.142
> (T6f_cold_merge_*); V3 survives on every reading (it needs c ≥ 0.98–1.00 of the measured 1.99). (2) **Erratum #29 re-prices V2:** each
> flag round ends in a crossing (10–20 µs), so the primary branch is 20 µs: V2 MoE **2.012 → 1.979**, V3 + V2 MoE 4.170 → **4.098**, dense
> unchanged at 0.157 (T6f_mega_20us); the 2 / 5 µs branches assumed crossing-free polls. (3) **Erratum #31 on the dense 1M KV-int8 route:**
> the rowmax chain's cheaper crossing (a drain + 16 scalar reads of fresh maxima) is the racing composition; the deterministic one (16
> scalar-destination reduces, 17 600 ns per block) tightens the bound **≤ 0.034 → ≤ 0.027** tokens/s/card (T6f_dense1M_det) — a route
> that is shippable, deterministically, and still UNMEASURED. (4) Placements, no cell moves: x_q staging for rows ≥ 2 (#25: the production
> 2 × 32 KiB legs, never one block — B = 16 and verify batches); the bounce-removal lever needs a proven US → S1 route that #20 rules out;
> the V2 protocol's checksum compare and in-kernel top-k (#31), unbounded polls (#26), nest boundaries (#30 / #18 / #28); the quantizing-
> epilogue fallback's Muls (#22); the router top-k (#31 / #26). (5) **Obsolescent by measurement:** the guarded column (the legacy scan)
> is no longer the shipped kernel — the deferred guard (#31's production answer) is MEASURED (945.5 / 3 618.8 / 28 694 µs) and E39 is
> resolved by it; round 6 (PROMPT-3R6) folds those cells and re-ranks — this audit does not pre-empt it.

> **ROUND-5 STATUS (2026-11-07 — the measured production attention kernel; attention session 3, HW-MAP 62e8137; `proof/fleet.py`
> `[R5-*]`, `proof/fleet.lean` `T5r_*` (18 new theorems, 310 total, 0 axioms / sorry / native_decide), PROOF-COVERAGE-4.md round-5
> section).** The attention term is now a MEASURED per-layer time (DESIGN-3 §6.0), carried as three readings — the G triplet at 32k:
> **guarded 88.7 GB/s** (the kernel as shipped at session 3 — **audit:** OBSOLESCENT by measurement, the deferred guard shipped in session 4 is MEASURED in session 5 and round 6 folds it; MEASURED at every L: 213.5 / 1 513.6 / 5 852.9 / 46 313.6 µs), **unguarded 143.0**
> (MEASURED at 32k, 938.8 µs; off 32k the guarded cell minus the per-block guard — DERIVED), **fused ≈ 140** (the target: the unguarded
> kernel plus one batched 20 µs crossing per step — UNMEASURED, E39). The step is affine in the per-layer attention a (dense 2 289 788 669
> + 120·a ns, MoE 115 956 899 + 28·a — T5r_step_form, ∀ a), so every cell below is a theorem about the measured number. **Headline,
> L = 32k, t = 1 (§3.6, T5r_step_cells): dense 0.101 / 0.104 / 0.103 tokens/s/card (guarded / unguarded / fused; round 4: 0.104), MoE
> 1.578 / 1.757 / 1.750 (round 4: 1.766 — the shipped guard costs the MoE cell 10.6 %)**; MoE 128k 0.893 / 1.160 / 1.157 (1.155), MoE 1M
> 0.176 / 0.278 / 0.278 (0.272), dense 128k 0.083 / 0.092 / 0.091 (0.091). **T3r_moe128k_tie restated with the MEASURED legs = 2 and the
> measured kernel (§4.4, T5r_moe128k_tie_measured): the MoE-128k cell is hard attention-bound on every reading** — per layer by 82.5 %
> guarded, 10.8 % unguarded, 11.4 % fused (anchored; 121.6 / 34.5 / 35.3 % on the direct path) — and so is the STEP (163.88 / 99.50 /
> 100.06 ms of attention against 92.82 ms of weights); at the measured bounce the legs-conditional lines are G ≤ 178.7 (anchored) / 220.2
> (direct) with zero chain and zero fixed cost (round 4's legs-2 lines: 189.4 / 230.3), on the effective KV rate G_eff ≤ 167.3 / 203.2 —
> every reading (91.7 / 151.1 / 150.2) is below them. **The lever ranking, corrected (§10″, T5r_levers): the P4P2 order at MoE 128k
> (choreography 22.33 > E29 15.86 > bounce 11.10 ms per token) becomes guard fusion 63.81 > E29 15.86 > phase overlap ≤ 7.46 > bounce
> removal 5.71 ms.** The 138.3 → 169.2 "choreography" lever is retired (the K+V stream phase runs 174–176 GB/s, MEASURED; the gap to the
> round-4 cell is the guard scan, which covers 101.5 % of it — T5r_retired); the bounce is cheap (51 µs at 32k). Guard fusion is first for
> dense at every L and for MoE at every L ≥ 33 297 (32 785 at a 10 µs crossing; T5r_levers_overtake); **at exactly MoE 32k it ties E29
> within 2.1 % and comes second (15.53–15.81 vs 15.86 ms) unless the fused kernel's residual per step is ≤ 8 279 ns (T_fused ≤ 947.1 µs =
> 141.7 GB/s — T5r_levers_moe32k_iff): "guard fusion (~570 µs) is the new #1" holds at 32k only at the zero-residual ceiling (574.8 µs →
> 16.09 ms)**; at MoE 4k E29 stays first. Spec decode on the guarded verify kernel (DERIVED transfers): dense 0.211 (round 4: 0.252; beats
> t = 1 iff α ≥ 0.179, round 3: 0.144), MoE 1.339 (1.389); **T_spec_moe_loss survives with its line moved: the MoE verify batch loses for
> every α ≤ 0.807 guarded / 0.854 unguarded / 0.853 fused (round 3: 0.866 — T5r_spec_thresholds)**. MoE B = 16 1.966 / 2.251 / 2.240
> (round 4: 2.267); two instances at H10's c = 1.990: MoE 3.230 / 3.607 / 3.592 (round 3: 3.702), dense 0.150 / 0.153 / 0.153; dense 1M
> KV-int8 ≤ 0.034 under erratum #29's crossing bound (round 4: 0.053). T_min_dies is untouched (no attention term).

> **ROUND-3 PROOF STATUS (PROMPT-4P2, 2026-11-07 — `proof/fleet.lean` round-3 section, PROOF-COVERAGE-4.md round-3 proof session,
> `proof/fleet.py` `[R3P-*]`).** The 27 round-3 rows of Appendix A′ are proved in core Lean 4.35: 168 theorems `T3r_*` (292 in the
> file), 0 axioms / sorry / native_decide, `lean proof/fleet.lean` and `lake build` clean; every round-3 cell was printed by
> `proof/fleet.py` and fixed by a theorem, with DESIGN-3's attention chain duplicated from `proof/attn.lean`. **Inputs instantiated:**
> H10 is GREEN at card scale (two instances on disjoint dies, 1.99× aggregate) and enters as the concurrency hypothesis c — every
> overlapped-tier instance cell activates (MoE 32k 3.702 at c = 1.99; it beats the 8-die chain for any c ≥ 0.970× and the
> direct-path chain for c ≥ 1.095×; dense 0.154, c ≥ 1.354×), the two-card inheritance stays the open premise; E35 is LICENSED —
> both chains are carried, the fixed-shift cells are the loadable branch (a guard trip in every layer of every step leaves them
> unchanged). **Corrections the prover forced (applied in place, marked "proof:")**: (1) the serial-chain int4 piece is **807 ns,
> not 596** (8 KiB of f16 per 2 KiB of int4, two MMA calls — the alternatives proof round's figure, never propagated here): the
> serial-chain instance cells move (MoE 32k 3.399 → 3.128) and **dense 32k flips from +17.3 % to −3.8 %** — dense replication needs
> the overlapped cold tier (E30); (2) L* is the length from which every longer context is attention-bound, but the t = 1 attention
> is not monotone in L (the 15-token vector tail): in 13 of 40 cells the first attention-bound length is lower — **MoE at 256 KiB
> from 131 103, not 131 600**; dense KV-int8 from 1 006 102 — no design cell moves; (3) the 1M "iff G ≤ G*" lines are false over
> G > 0: **every 1M cell is attention-bound at every G** (the vector chain alone exceeds the weight time); (4) the bounce share
> peaks at **0.18 %** (MoE 4k), not ≤ 0.16 %; precision: the dense megakernel ties at exactly 109 903 ns (strict ≤ 109 902),
> α = 0.866 gives 1.800, the MoE regime spread is 1.13–1.15×. **The MoE-128k tie moved with DESIGN-3 round 4 and is proved
> legs-conditional:** attention-bound iff G ≤ 168.3 / 178.9 / 189.4 (P-bounce legs 0 / 1 / 2; ≤ 204.7 / 217.5 / 230.3 on the
> direct path) — **the planner reads legs = 2 (erratum #20), so the cell is attention-bound at every G ≤ 174.6 on both expert
> kernels**; the round-3 tie survives only at legs 0. At Π = 1 the step is a sum, so the binding side does not rank follow-ups: at
> 128k E29 saves 15.86 ms per token against 11.10 for removing the bounce (the bounce removal wins from L = 187 392; realising the
> measured G instead of the session-1 loop's 138.3 is worth 22.33 ms). **T_min_dies survives unchanged; T_spec_moe_loss survives
> (α ≤ 0.866); T3r_spec_dense_split: ≥ 0.248 iff the verify chain is ≤ 12 633 ns per block, ≥ 0.227 iff ≤ 27 775;
> T3r_instance_margin: the MoE 32k instance fits iff the overhead is ≤ 2 GiB + 24.5 MB (dense + 3.3 MB), each GB absorbed by
> +23 / 21 ‰ of x.**

> **ROUND-3 STATUS (re-grounding on the season (v1) measurements — HW-MAP commit e9349c8; the ALTERNATIVES variants of
> dd5f84c with the steering correction 0915e22; `proof/fleet.py` `[R3-*]`, PROOF-COVERAGE-4.md round-3 section).** Three
> inputs this plan carried as assumptions or as PROBLEM-3 branches are now measured, and three partition variants are
> first-class: (1) **the host bounce is 12.2 / 12.1 µs per direction** (bounce 23.8–24.6 µs, unchanged under a saturating
> D2D load on die 0) — 7.5× below the 91 µs anchor round 2 borrowed from the kernel-launch floor, which is a *different*
> quantity and stands at 91 µs as the conservative primary (adjudicated: the serving byte accounting bounds the
> REALIZED per-launch cost at ≤ 36 µs — HW-MAP realized-launch row; serialized-launch readings are upper bounds); every λ-anchored cell is re-instantiated (T_x = 236 / 220 µs per token, 0.01 % / 0.16 % of
> the dense / MoE step; the T8 lines move to λ ≥ 16.6 ms / 960 µs for a 10 % share, 1 358× / 78× above the measurement).
> (2) **The KV read rate is measured per page size** (E21: 169.2 GB/s at 256 KiB, 167.0 at 64 KiB shuffled, 153.8 at 16 KiB —
> the attention choreography streams 3.2 % under the W8 kernel's 174.6) and **the softmax op set is measured** (E22), so the
> attention term is now DESIGN-3's round-3 chain (9 276 ns per 512-token block = 77 % of the block at t = 1, 18.8 µs fixed per
> launch) at this plan's GQA shapes: every t = 1 cell stays KV-bound, but **verify batches are softmax-bound from t = 2 on
> dense (rows = 32) and t = 5 on MoE**, and the KV-int8 escape is vector-bound at t = 1 (612 µs at 32k) unless the
> fixed-shift chain of DESIGN-3 §3.4 ships (E35). (3) **The on-device f16→i8 activation-quantization pass is measured
> (43.7 µs)** and is charged four times per layer — 21.0 ms (0.9 %) per dense token, 4.9 ms (3.5 %) per MoE token; the
> integrated production chain's 135.5 GB/s is carried as the pessimistic branch (dense −20 %). **Headline, L = 32k, t = 1
> (`[R3-headline]`): dense 0.104 tokens/s/card (round 2: 0.105), MoE 1.802 (1.867)** — the dense cell moves by the quant pass,
> the MoE cell by the quant pass and the slower attention stream; with spec decode dense 0.227 (0.248 on the fixed-shift
> chain; round 2: 0.262 — the 64-row verify batch is vector-bound, 427 ms of attention); dense 1M on KV-int8 0.054 (0.065
> fixed-shift; round 2: 0.066); MoE 1M 0.302 (0.312). **Variants (§1.8, §3.5, §5, §10)**: the MoE expert kernel on the
> DDR→L0B direct path (E29) 2.035 (+12.9 %); a per-layer megakernel (E31: pays iff c_sync ≤ 108.4 / 109.9 µs) 2.012 / dense
> 0.106; both 2.307; **two 4-die instances with the minimal int4 tier (H10, host-only) MoE 3.720 (+106 %), dense 0.155
> (+49 %)** — the fit closes with < 25 MB of margin per die at the assumed 2 GiB overhead and needs +2.3 % of int4 share per
> GB of extra overhead; all three together 4.170 (+131 %). Π = 8 sequence pipelining (H4) stays the one lever above all of
> them (0.808 / 12.918) and reverses the instance decision. **T_min_dies survives unchanged** (full int8 residency: 4 dies
> infeasible, 5 feasible; the instance variant is PROBLEM-4's "hot/cold residency split" escape under a *different*
> hypothesis — int4 bytes on the measured 5.3 GB/s/core vector-unpack path). **T_spec_moe_loss survives** with its threshold
> moved from α ≤ 0.864 to **α ≤ 0.866** (Zipf(1.0) 0.752, Zipf(1.5) 0.657; 0.847 / 0.741 / 0.652 on the direct path). The
> round-2 body and its numbers are kept below as the record; every moved cell is listed in `[R3-moved-*]` and the round-3
> section of the ledger; the round-3 theorems are theorems-in-waiting (named in Appendix A′) for the next proof session.

> **ROUND-2 STATUS (proof session)**: every derived number below is checked by `proof/fleet.lean` (core Lean 4.35,
> no declared axioms, builds standalone and via lake) and printed by `proof/fleet.py`; the claim ledger is
> `PROOF-COVERAGE-4.md`. Corrections the prover forced are applied in place and listed there: the bounce-threshold
> formula (T8: the step itself carries the 16 λ — a 10 % share needs λ ≥ 918 µs / 16.4 ms, not 835 µs / 14.8 ms;
> 50 % needs 8.27 / 147.5 ms, not 4.18 / 73.8), the §7 scaling identity (4 × stage-1 + T_head + 2·T_launch + 4λ +
> hop terms = 2362.32 ms exactly, not "+ 12λ" with a residual), the H8 overhead ceiling (3.54 GiB = 3.80 GB, not
> 3.85 GiB), the spec-decode thresholds (α ≥ 0.865 / 0.747 / 0.647 by routing family, proved in both directions;
> the dense gain is 2.475×), the T7 order statement (order-dependent through the first and last die types, 1.2 µs),
> the Π = 8 imbalance (10.3 %, not 12.5 %) and trunk share (0.84 %, not 0.2 %), the tensor-split decomposition
> (the lm_head/8 term), the §10 "≤ 1.3×" claim (2.7× for MoE at 1M on the G branch), and unit slips (12 GiB expert
> slabs, 4 KiB of K/V per token-layer, 96 KiB trunk bytes, 386.5 GB, 21.8 ms, 0.44 %). **T_min_dies (4 dies
> infeasible for every layer assignment; 5 feasible) and T_spec_moe_loss (the verify batch multiplies the
> active-expert bytes; a loss for every α ≤ 0.864 under uniform routing) survive formalization unchanged.**
Scope (PROBLEM-4.md): place one model (dense-GEMM shape and MoE shape, both parameterised so that the int8
residency lands inside the 320..400 GB band that errata #12 forces), its KV cache and a draft model on 8 dies
of 86 GB, choose the per-token exchange schedule through host memory, and predict tokens/s per card at
L ∈ {4k, 32k, 128k, 1M} with the binding constraint named per cell. Everything derives from HW-MAP.md (as of
commit 7f53dce, the direct-load silicon sync; **round 3: commit e9349c8, the season (v1) validation pack**), DESIGN.md (dense decode kernel: the per-die rate inputs),
DESIGN-2.md (MoE kernel: the per-expert chain and its two regimes) and PROBLEM-3.md (attention: the two
unmeasured rates G and E are carried as branches — rounds 1–2 predate DESIGN-3.md and state a minimal branched
attention model here; **round 3 replaces it with DESIGN-3's measured round-3 chain (§3.5) and adds the ALTERNATIVES.md
variants (dd5f84c, steering correction 0915e22) as first-class partition variants (§1.8, §5′)**). Status tags: **M** measured (HW-MAP), **D2** derived in DESIGN-2,
**D** derived here by arithmetic shown, **A** explicit assumption with the host experiment (H-number, §8)
that measures it, **U** unmeasured and branched.

Units: bytes binary where named KiB/MiB/GiB, memory totals in decimal GB (HW-MAP quotes 86 GB usable);
rates in GB/s decimal (1 B/ns = 1 GB/s); times in ns floored, quoted in ms/µs round-half-up; tokens/s to
three decimals. Every derived cell is printed by **`proof/fleet.py`** (integer arithmetic only, Python ≥ 3.8,
no dependencies; label `[Fx-…]` in the text) in the conventions of `proof/model.py` / `proof/moe.py`, so the
proof session can transcribe it into core Lean 1:1 — the theorem targets are listed in Appendix A.

**Definitions.** *Chain position* p ∈ 0..7 is the order in which a token visits the dies. *Π* is the number of
independent sequences in flight across the chain at once (the measured runtime behaviour is Π = 1: "dies
alternate, no concurrent streaming"). *B* is the number of sequences batched into one GEMM row block on a
die, *t* the query tokens per sequence per step (t = k + 1 for a verify batch with k draft tokens), *rows* =
B·t ≤ 16 (the flat regime). **tokens/s per card = fleet tokens/s ÷ 4** — one model instance spans the fleet.
L = 4k/32k/128k/1M means 4096 / 32 768 / 131 072 / 1 048 576 tokens.

> **ROUND-7 STATUS (2026-11-12 — the measured-anchor re-grounding, `[R7-*]` / `T7r_*`)**: the expert
> slab's ANCHOR is now the MEASURED kernel (M0 165.8 GB/s t = 1, 170.2 at t ≥ 4; 99.2 % of the design
> target) — the D2-derived serial anchor retires and **E29 is BANKED at 14.64 ms per MoE token** (7.7 %
> under the derived promise). The deferred-guard cell amortizes at the MEASURED retry share (τ = 8 % /
> 5.5 % of launches at cap 3072 / 61440 vs break-even 0.19 % — the round-6 premise was stale ~30–40×),
> and **the 32k tie is settled: E29 #1 on both caps** (the wide cap misses the line by 1 576 ns/layer).
> Headline MoE 32k t = 1: 1.755 → **1.956 trip-free / 1.926 measured-amortized / 2.103 at the realized
> launch bound (≤ 36 µs)**; 128k 1.233; 1M 0.276; two instances at the measured card-scale 2.0× = 3.853.
> All round ≤ 6 cells keep their printed values as history.

## Constants used

| Symbol | Value | Status / origin |
|---|---|---|
| R_gemm | **174.6 GB/s** per die, full W8 decode kernel, flat m = 1..16; serial fallback 138.9; m ≥ 24 leaves the flat regime (81/59/43) | M (data-movement) |
| R_ddr / R_read | 173.8 r+w stream roof / ~181 pure read | M |
| Host links | die 0: 27.6 H2D / 27.3 D2H; die 1: 13.9 / 19.0, transiting die 0 | M (card table) |
| P2P | **refused by the runtime**; D2D copy via host 10.7 GB/s r+w | M (errata #11) |
| Runtime | layer-split works (+2 % at 2 dies, dies alternate, no concurrent streaming); **tensor-split of one op faults** | M (errata #11) |
| T_slab | **122 979 ns** per (active expert, 16 MiB slab) per core, MoE serial regime, anchored to the measured dense kernel; ping-pong regime 97 015 ns = (784 118 − 8 000)/8; F = 8 µs per launch | D2 ([M15], [M1]) |
| D(t) | active experts per step: uniform min(8t, 256); Zipf(1.0) 8/25/68 and Zipf(1.5) 8/20/45 at t = 1/4/16 | D2 (§7.1 generator means) |
| c_mma | 15 ns per (16,16,128) MMA call | M |
| R_vec | 40 lanes/cycle × 1.08 GHz × 8 cores = 345.6 G lane-ops/s per die | M |
| T_launch | 91 µs launch + queue floor, per kernel launch (serialised unless H6 shows pipelining) | M |
| Memory | 86 GB usable per die, 8 dies = 688 GB; L0/S1/US sizes per HW-MAP (not binding here) | M |
| Power | 141 W per card sustained all-core matrix load, 150 W TDP class, no throttle | M |
| G (round 2) | KV read rate of the attention kernel — **superseded in round 3 by the measured E21 rows below**: **stream** branch 174.6 (contiguous per-core head slabs, the pattern that measured 180/181); **gather3x** branch 58.2 (3× slower, PROBLEM-3's risk framing) | U — PROBLEM-3 E-gather; A-layout §1(c) |
| c_E (round 2) | vector lane-ops per attention score incl. max-subtract, sum, rescale: **native** exp 4; **poly** (no exp instruction) 16 — **superseded in round 3 by the measured chain (E22)** | U — PROBLEM-3 E-exp |
| λ (round 2) | host-bounce latency per direction (bandwidths are measured, latency is not): **91 µs primary** (the only measured runtime floor of this class), bracket 10 / 500 µs — **superseded in round 3: measured 12.2 µs (below)** | A — H3 |
| O_rt, WS | runtime overhead 2 GiB and workspace 64 MiB per die | A — H8 |
| α | draft acceptance per token: 0.5 / **0.7** / 0.9 | A — fleet-only (§8 H9) |
| Π | sequences in flight across the chain: **1 (measured)**; 8 is the §5 what-if | M / U — H4 |

| **Round 3 — measured (HW-MAP e9349c8) and the variant inputs** | | |
| λ (round 3) | **12.2 µs per direction** (12.2 / 12.1 measured; bounce 23.8–24.6 µs; unchanged under a saturating D2D load on die 0) — the round-2 anchor 91 µs was the kernel-launch floor, a different quantity; the 10 / 91 / 500 µs points are kept as what-ifs | **M** (round 3) |
| T_launch | 91 µs kernel launch + queue floor — unchanged, now split from λ | M |
| G (round 3) | **169.2 GB/s at 256 KiB pages** (the DESIGN-3 §10 default and this plan's primary; = the sequential rate, c_pg = 3 ns), 167.0 at 64 KiB shuffled (c_pg 39 ns), 153.8 at 16 KiB; the W8 kernel's 174.6 is the ceiling (the attention choreography's per-tile barrier + per-chunk MMA cost 3.2 %); "gather3x" 58.2 is a what-if only | **M** (round 3, E21) |
| attention chain | DESIGN-3 round 3 (`proof/attn.py` step3): 9 276 ns per 512-token block-fragment on the chain as specified (throughput convention; 11 836 chained-latency corner), fixed 18 820 ns per launch; fixed-shift variant 5 530 / 11 328 (E35); rows = t·g per core, mt = ⌈rows/16⌉ fragments, 256-token blocks at mt ≥ 3, two passes above 64 rows | **M/D** (round 3, E22) |
| c_q | **43.7 µs per on-device f16→i8 A-quantization pass** (m = 1, K = 8192; +12.2 % over host-packed A); 4 passes per layer (QKV, O, gate/up, down); "prop" branch: 43.7 µs per 8 192 elements (E38; **audit, #29 / #31:** measured at m = 1 only — a per-row absmax read through a per-row crossing or a fresh-reduction readback would scale with rows; E38 adds rows 4 / 16 and a 20-rep determinism check) | **M** (round 3) |
| R_gemm,int | 135.5 GB/s — the integrated production kernel f32-in / f32-out (the quant pass folded in): the pessimistic branch for every weight stream | **M** (round 3) |
| T_slab (variants) | anchor 122 979 (DESIGN-2 serial, primary); **direct path 99 374** (A lift serialised) / 96 089 (overlapped) — ALT-1, all rates measured, choreography E29; ping-pong 97 015 (E13) | D2 / ALT |
| c_sync | cross-core DDR-flag round trip of the per-layer megakernel (ALT-3): branches 2 / 5 / 20 µs; pays iff c_sync ≤ 108.4 µs (MoE) / 109.9 (dense) (**audit, #29:** each flag round ends in a scalar read after a fence = one crossing, 10–20 µs measured — the 20 µs branch is the primary reading; 2 / 5 µs assumed crossing-free polls) | **U** — E31 |
| R_w4v | **5.3 GB/s per core** of int4 bytes on the 5-pass vector unpack (42.4 per die = 84.8 W8-equivalent); serial-chain branch **807 ns** per 2 KiB piece (40.8 W8-equivalent; proof: the 596 ns / 55.2 first written here carried 4 KiB of f16 per 2 KiB of int4 — T3r_serpiece) — the instance variant's cold tier | **M** (ALT-2 premise, was "> 0.8") |
| Π, H10 | Π = 1 measured; Π = 8 the H4 what-if; **two concurrent runtime instances: H10 GREEN at card scale (disjoint dies, 1.99× aggregate); on disjoint card pairs the inheritance is the hypothesis, carried as the concurrency variable c (T3r_inst_h10)** | U — H4 / M (card scale) — H10 |

**Shapes** (`[F0]`): both are the 2× int8 expansion of a 160..200 GB sub-8-bit source.

| | dense "D" (405B-class geometry) | MoE "M" (PROBLEM-2 headline slabs) |
|---|---|---|
| layers | 120 | 28 |
| d_model / FFN | 16 384 / 53 248 | 4 096 / experts |
| heads H_q / H_kv / d_h | 128 / 8 / 128 (g = 16) | 32 / 8 / 128 (g = 4) |
| per-layer resident int8 | 3 187 671 040 B (QKV 18432 + O + gate/up 106496 + down) | 41 943 040 B attention + 256 experts × 3 slabs × 4096² = 12 926 844 928 B |
| embed + lm_head | 2 × 2 101 346 304 B | 2 × 525 336 576 B |
| **total int8** | **386.7 GB** (int4 source 193.3) | **363.0 GB** (181.5) |
| streamed per token (t = 1, uniform) | 384.6 GB | 12.9 GB (8 experts × 48 MiB + attention per layer, + lm_head) |
| KV per token per layer (f16) | 4 096 B → 491 520 B per token | 4 096 B → 114 688 B per token |
| KV at L = 1M (f16) | **515.3 GB** | 120.2 GB |
| launches per layer | 6 (QKV, attention, O, gate-up, down, norm/rope/residual) | 7 (+ router, experts gate-up fused, experts down; **audit, #31 / #26:** the router's top-k is computed vector-side with the ids copied out — never a fresh reduce-max read at a fence, never a > 256-deep scalar scan; DESIGN-2's dispatch reads the ids once per launch) |

Draft model: 1 GB int8, 24 layers, 121 launches per draft token, 4k-token sliding window of its own KV
(201 MB), k = 3 draft tokens per verify step (PROBLEM-4's "up to 3").

---

## 0. Summary — does any configuration close, and at what tokens/s

### 0‴ Round-6 summary (`[R6-headline-*]`, `[R6-step-*]`, `[R6-tie-*]`, `[R6-levers-*]`)

**Nothing in the partition moves; the attention term is the measured deferred-guard kernel.** What round 6 settles: (1) the fused cells are
MEASURED, so the fleet numbers stop depending on E39's residual X — MoE 32k 1.755 (trip-free) / 1.754 (amortized), dense 0.104; (2) the 32k
rank against E29 is a tie on the 141.7 GB/s line (within 0.51 % on either legacy basis), and at 128k / 1M the banked fusion is 3.9× / 31.1×
E29; (3) post-fusion the attention-side order is E40 > bounce removal on every cell, with E29 > E40 on MoE 32k / 128k and E40 > bounce > E29
on MoE 1M; (4) the MoE spec loss line moves 0.807 → 0.854; the dense spec decision holds for any verify kernel ≤ 31.09 ms per layer.

| L = 32k, t = 1 | deferred, trip-free (M) | amortized 946.3 / 947.4 µs | round 5 fused (D) | round 5 unguarded | legacy scan (M, s3) | round 4 |
|---|---|---|---|---|---|---|
| dense tokens/s/card | **0.104** | 0.104 / 0.104 | 0.103 | 0.104 | 0.101 | 0.104 |
| MoE tokens/s/card | **1.755** | 1.754 / 1.754 | 1.750 | 1.757 | 1.578 | 1.766 |
| MoE attention per token | 26.47 ms (18.6 %) | 26.49 / 26.52 ms | 26.84 | 26.28 | 42.38 | 25.52 |

### 0″ Round-5 summary (`[R5-headline-*]`, `[R5-step-*]`, `[R5-levers-*]`)

**Nothing in the partition moves; the attention term is replaced by the measured kernel.** At t = 1 both shapes run the measured kernel's
shape (mt = 1), so the per-layer attention is the t × L sweep (guarded, MEASURED) or one of its two readings (unguarded: MEASURED at 32k;
fused: the E39 target). What the measurement changed: (1) **the shipped guard is the largest attention cost** — 574.8 µs of the 1 513.6 µs
per layer at 32k (38 %), 16.09 ms per MoE token, 68.97 ms per dense token; (2) **the round-4 model was right on the unguarded cell** (3.0 %),
so on the unguarded and fused readings every round-4 fleet cell holds within ±2.2 %; (3) **the MoE-128k cell is no longer close to a tie
on any reading** (attention-bound by 10.8–82.5 %); (4) **the follow-up ranking moves**: guard fusion first from 32 785–33 297 tokens
of context on (the crossing at 10–20 µs), E29 first below it, the bounce removal last everywhere except MoE 1M (second there: 45.69 ms,
just above the overlap bound, with E29 last). The single measurement that decides the 32k rank is E39's residual X (≤ 8 279 ns per step
for guard fusion to beat E29 there).

| L = 32k, t = 1 | guarded (M) | unguarded | fused (target) | round 4 | round 3 |
|---|---|---|---|---|---|
| dense tokens/s/card | **0.101** | 0.104 | 0.103 | 0.104 | 0.104 |
| MoE tokens/s/card | **1.578** | 1.757 | 1.750 | 1.766 | 1.802 |
| MoE attention per token | 42.38 ms (26.8 %) | 26.28 ms (18.5 %) | 26.84 ms (18.8 %) | 25.52 ms | 22.73 ms |

### 0′ Round-3 summary (`[R3-headline]`, `[R3-decision]`, `[R3-moved-*]`)

**Both shapes still close on 8 dies as int8; nothing in the memory model moved (`[R3-mem]`). What moved is the step: the
measured host bounce (12.2 µs) takes 1.3 ms out of every dense step and 1.3 ms out of every MoE step, the measured
attention stream (169.2 at 256 KiB pages, 18.8 µs fixed per launch) puts 5.2 / 1.2 ms back, and the measured on-device
quantization pass (43.7 µs × 4 per layer) adds 21.0 / 4.9 ms.** Net: dense 0.105 → **0.104**, MoE 1.867 → **1.802**
tokens/s/card at 32k, t = 1.

| Question | Round-3 answer | Where |
|---|---|---|
| Memory | unchanged: dense 386.7 GB to L_max = 551 253 (f16 KV), 1M only on KV-int8 at 84.3 of 86 GB (H8 hostage); MoE 363.0 GB to 1.93M; minimum 5 dies under full int8 residency (T_min_dies unchanged). **New escape (§1.8): two 4-die instances with the minimal int4 share on the measured 5.3 GB/s/core unpack path — MoE needs x = 18.2 / 17.0 / 17.0 / 18.2 % of the expert bytes as int4 at 32k (82.7 % at 1M), dense 37.6 / 35.8 / 33.2 / 37.6 % (dense 1M cannot replicate: KV alone is 128.8 GB per 4-die position)** — with < 25 MB of margin per die at the 2 GiB overhead, +2.3 % of x per GB of extra overhead (H11) | §1, §1.8 |
| tokens/s per card at L = 32k (primary) | **dense 0.104** (t = 1), 0.227 with spec decode (k = 3, α = 0.7; 0.248 on the fixed-shift chain), 1.039 at B = 16; **MoE 1.802** (t = 1), 2.325 at B = 16 uniform (4.638 Zipf 1.5); spec decode on MoE stays a loss (1.397) | §3.5 |
| the same cells on the variants | MoE: direct-path expert kernel **2.035** (E29), megakernel 2.012 (E31, c_sync 5 µs), both 2.307; **two instances 3.720** (H10; 3.391 with the anchored kernel, 4.006 under Zipf(1.0) popularity), all three 4.170. Dense: megakernel 0.106, two instances **0.155** (spec 0.349 / 0.374), both 0.157. Π = 8 (H4): 0.808 / 12.918 | §3.5, §5, §10 |
| Binding constraint | still the weight stream of one die at a time in every Π = 1 cell up to 128k; the host bounce is 0.01 % / 0.16 % (T8: 10 % needs λ ≥ 16.6 ms / 960 µs); the launch floor 2.8 % / 13.0 %; the quant pass 0.9 % / 3.5 %; **attention binds MoE at 1M (86 %) and sits at the flip at 128k: weights-bound by 0.5 % at 256 KiB pages, attention-bound at 16 KiB, and attention-bound at every page size once the expert kernel moves to the direct path (L* = 108 048 < 131 072)** — proof: with DESIGN-3 round 4's P bounce at the leg count erratum #20 forces (2), attention-bound at every G ≤ 174.6 on both kernels (T3r_moe128k_tie); dense verify batches (rows = 64) are vector-bound: 427 ms of attention per step on the chain as specified, 191 on the fixed-shift chain | §4.3 |
| 1M | MoE 0.302 (KV 711 of 827 ms; 0.577 on two instances); dense KV-int8 **0.054 on the chain as specified (the halved stream is under the 9 276 ns vector chain: attention 2 282 ms) and 0.065 on the fixed-shift chain (E35)**; dense f16 KV infeasible | §3.5, §9 |
| What a runtime upgrade buys | P2P at any rate ≤ 236 / 220 µs per token (≤ 0.16 %); D2D 10.7 → 50: nothing per token; tensor-split 6.2× dense / 3.5× MoE (the 34 / 27 µs host reductions are now negligible: launch-floor- and quant-bound); Π = 8: 7.7× / 7.1× | §5 |
| The single measurement | **H4 (Π = 8) is still the largest lever (7×) and is the only one that reverses a build decision; H10 (two instances, host-only, an afternoon) is the largest lever that needs no runtime change (2.1× MoE / 1.5× dense).** Build order given H4 and H10 pending: H10 → E29 → E31/E35 → the instance plan on 2 + 2 cards unless H4 passes, in which case the single 8-die chain with Π = 8 | §10 |

**Round-2 summary (kept as the record; every moved cell is in `[R3-moved-*]`):**

**Yes, both shapes run on the 8-die fleet as int8, and the fleet's size buys context, not speed.**

| Question | Answer | Where |
|---|---|---|
| Memory | dense 386.7 GB fits with f16 KV up to **L_max = 551 253** tokens (B = 1); **1M does not close with f16 KV** (515.3 GB of KV against 282.3 GB of room, `[F9-mem]`); it closes with the **KV-int8 escape at 84.3 of 86 GB** on the worst die (1.66 GB margin: it fits iff the per-die runtime overhead is ≤ 3.80 GB = 3.54 GiB, hostage to the 2 GiB assumption H8; T_mem_feas_kv_int8). MoE 363.0 GB fits with f16 KV to L_max = 1 925 823. Minimum fleet for either shape: 5 dies (3 cards). | §1, T3–T4 |
| tokens/s per card at L = 32k (primary branch) | **dense 0.105** (t = 1), 0.262 with spec decode (α = 0.7, k = 3), 1.067 at B = 16 sequences; **MoE 1.867** (t = 1), 2.357 at B = 16 uniform (4.765 under Zipf 1.5); **spec decode is a loss on MoE** (1.451) because the verify batch multiplies the active-expert set (T12). | §3, §6 |
| Binding constraint | in every Π = 1 cell the **weight stream of ONE die at a time** (layer-split serialises the dies: the fleet streams 174.6 GB/s, not 8 × 174.6); KV binds for MoE at 1M (86 % of the step) and for dense beyond L* = 778 240; host bounce is ≤ 1.1 %; the launch floor is 13.5 % of the MoE step; softmax never binds at t = 1. | §4 |
| 1M | MoE 0.312 tokens/s/card (KV-bound: 688.8 of 801.1 ms); dense 0.066 with KV-int8 (weights-bound; KV 1 475.9 of 3 746.0 ms); dense with f16 KV: infeasible. | §3 |
| What a runtime upgrade buys | P2P at any rate: ≤ 1.5 ms per token (≤ 1.1 %); D2D 10.7 → 50: nothing per token; tensor-split: 5.9× dense / 3.1× MoE (then launch-floor-bound); **pipelining Π = 8 independent sequences: 7.7× dense / 7.1× MoE throughput** at unchanged per-sequence latency. | §5 |
| The single measurement | **H4: does the runtime pipeline independent sequences through the layer-split chain?** It moves every cell by ~7×; at 32k no other unknown moves a cell by more than 1.32× (G 3× slower: −7 % dense / −24 % MoE; MoE ping-pong regime +15 %; launch pipelining +3 % / +16 %; λ 10 ↔ 500 µs: ±5 % MoE); the one larger single-unknown swing is the G branch at 1M, where the MoE cell falls 2.7× (0.312 → 0.114, T_single_measurement). | §10 |

Honest ceiling of any layer-split, single-stream plan on this fleet (T2): tokens/s ≤ R_gemm / bytes streamed
per token = 174.6 / 384.6 = **0.454 tokens/s fleet-wide for dense** (0.113 per card) and 174.6 / 12.9 ≈ 13.5
for MoE (3.4 per card) — the predicted 0.105 / 1.867 are 93 % / 55 % of those ceilings (MoE loses to the
serial-regime expert kernel 135.3 vs 174.6, the launch floor and the KV stream).

---

## 1. The partition (a)–(f)

### 1.1 (a) layer → die assignment (contiguous blocks, 7 boundaries)
Chain order puts a **die 1 first and a die 0 last**: the first position receives only token ids (4 B over
the 13.9 GB/s link), the last emits the logits (513 KB at t = 1) over the 27.3 GB/s link instead of 19.0
(`[F2-order]`: 18.8 vs 27.0 µs). The activation-hop sum depends on the order only through the first and last die types (T7, §2): the chosen order is the minimum of the four classes, by 1.2 µs over the other d0-last order.

| pos | card.die | dense layers (15 each) | MoE layers (4/3) | extras |
|---|---|---|---|---|
| 0 | c0.d1 | 0–14 | 0–3 | embedding table |
| 1 | c0.d0 | 15–29 | 4–6 | **dense draft model** (1 GB + 0.2 GB window) |
| 2 | c1.d1 | 30–44 | 7–10 | |
| 3 | c1.d0 | 45–59 | 11–13 | |
| 4 | c2.d1 | 60–74 | 14–17 | |
| 5 | c2.d0 | 75–89 | 18–20 | |
| 6 | c3.d1 | 90–104 | 21–24 | |
| 7 | c3.d0 | 105–119 | 25–27 | lm_head; **MoE draft model** (reserved, §6) |

Boundaries: dense after layers 14, 29, 44, 59, 74, 89, 104; MoE after 3, 6, 10, 13, 17, 20, 24. 28 MoE
layers do not divide by 8 (3.5 per die): the 4-layer dies take 4/3 of a 3-layer die's time, which is
invisible at Π = 1 (T1: the step is the sum) and costs 10.3 % of throughput at Π = 8 (the max block, 18.64 ms, against the 16.72 ms balanced mean — 12.5 % is the pure 4-vs-3.5-layer figure before lm_head and the bounce halves; T_pipelining_balance) (§5; a sub-layer split — attention
block / expert block as separate runtime units, 56 units = 7 per die — would balance it exactly, contingent
on the runtime accepting sub-layer placement, H4).

Why contiguous blocks: every boundary is a host bounce on the critical path (§2); 7 is the minimum for 8
dies. Why 8 dies and not 5: T2 — under layer-split the step time Σ_layers T_layer is the same for any
partition (Σ_pos n_pos = n_L), so extra dies cost one hop each (≈ 2λ + 3 µs) and buy KV room: 5 dies hold
dense only to L ≈ 53k (24 layers = 76.5 GB per die, 78.6 with the embedding table, leaves 5.2 GB), 8 dies hold 551k.

### 1.2 (b) expert → die placement (MoE)
All 256 experts of a layer live on the layer's die: an expert-parallel split across dies would be a
tensor-split of one op (the measured runtime fault, errata #11) and would add 2 host reductions per layer.
Inside a die, DESIGN-2 scheme S: core c owns column slice c of every active expert (per-core bytes identical
under every routing outcome, DESIGN-2 Z2), 3 slabs per expert (gate+up fused into one launch of two slabs,
down in a second), region-difference accumulator reset. The 12.9 GB (12 GiB) of expert slabs per layer are packed
per DESIGN-2 §2.1 at load.

### 1.3 (c) KV placement and growth policy
KV is die-local to its layers (errata #11). Per (layer, kv-head) one contiguous K slab and one V slab of
L_cap × 256 B each (f16, d_h = 128), **core c ↔ kv-head c** (8 heads = 8 cores): a decode step on a layer is 16
sequential per-core streams of L × 256 B, i.e. the "per-core slabs" access pattern of the measured 180/181
GB/s figures — this is what justifies the stream branch of G, and the gather3x branch is kept because the
attention kernel is unbuilt (PROBLEM-3). Append-only: the new token's K and V (kv_tok = 4 KiB per layer at t = 1) are
written at offset L inside the attention launch; no paging, no reallocation. L_cap per die is fixed at load
from the memory table (T4): dense 551 253 (f16) / 1 102 506 (int8), MoE 1 925 823. Online softmax in 2048-key
blocks (scores 16 × 2048 × 4 B = 128 KiB in L0C, double-buffered; running max/sum per (query row, head):
O(t·H) state, never O(L)).

**KV-int8 variant** (the dense escape above 551k): K and V stored as per-token-quantised i8 (2 048 B per
token per layer), scores and PV on the i8×i8→i32 route the dense kernel already runs (errata #13's realised
path), P quantised per row to i8 for the PV pass — a numerics risk (§9), not a rate risk: the stream halves (**audit, #29 / #31:** the per-row
scale needs the block's row maxima on the scalar side — deterministically 16 scalar-destination reduces per block, 17 600 ns; see §3.6).

### 1.4 (d) draft placement — §6
Dense: position 1 (c0.d0), the die with the fewest extras (the binding die for L_max is position 0 with the
embedding table, so the draft costs no context: `[F1-dense-draftfree]` = `[F1-dense-Lmax]` = 551 253).
MoE: not deployed (T12); 1.2 GB reserved on position 7.

### 1.5 (e) exchange schedule — §2
Per token-step: 7 activation hops (rows × d_model × 2 B each), logits D2H from position 7, sampled ids H2D
to position 0; nothing else crosses a die boundary (KV never moves; draft tokens are ids).

### 1.6 (f) load policy / residency
Host expands the int4 source to int8 per 64 KiB chunk (errata #12's "host-side int4→int8 expansion at
load") into pinned buffers and streams per die; fully resident thereafter. Link-bound load time: 386.7 GB
over 4 card trunks at 27.6 GB/s = 3.5 s (`[F8-H7]`), far below any host-side expansion rate that matters.
No on-the-fly weight streaming: a byte served from the host costs 27.6 vs 174.6 GB/s = 6.3× its DDR time,
and a host-paged KV prefix costs the same ratio (§9, T10): both escapes are quantified there and rejected
for the baseline in favour of the KV-int8 escape, which costs no link bandwidth.

### 1.7 Memory feasibility per die (`[F10-mem-*]`, `[F1]`)
Totals = weights + extras + KV + 64 MiB workspace + 2 GiB runtime (A, H8); "fits" = ≤ 86.0 GB.

**Dense, L = 4k (f16 KV):**

| pos | card.die | layers | weights GB | extras | KV GB | ws+rt GB | total GB | fits |
|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 15 | 49.9 | embed | 0.2 | 2.2 | 52.3 | yes |
| 1 | c0.d0 | 15 | 49.0 | draft | 0.2 | 2.2 | 51.4 | yes |
| 2–6 | c1.d1 … c3.d1 | 15 | 47.8 | - | 0.2 | 2.2 | 50.2 | yes |
| 7 | c3.d0 | 15 | 49.9 | lm_head | 0.2 | 2.2 | 52.3 | yes |

**Dense, L = 1M, f16 KV: infeasible on every die** — 15 layers × 4 096 B × 2²⁰ = 64.4 GB of KV per die, totals
114.4–116.5 GB (`[F10-mem-dense-1M]`). **Dense, L = 1M, KV-int8:**

| pos | card.die | layers | weights GB | extras | KV GB | ws+rt GB | total GB | fits |
|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 15 | 49.9 | embed | 32.2 | 2.2 | **84.3** | yes |
| 1 | c0.d0 | 15 | 49.0 | draft | 32.2 | 2.2 | 83.4 | yes |
| 2–6 | c1.d1 … c3.d1 | 15 | 47.8 | - | 32.2 | 2.2 | 82.2 | yes |
| 7 | c3.d0 | 15 | 49.9 | lm_head | 32.2 | 2.2 | **84.3** | yes |

**MoE, L = 4k and L = 1M (f16 KV):**

| pos | card.die | layers | weights GB | extras | KV 4k | total 4k | KV 1M | total 1M | fits |
|---|---|---|---|---|---|---|---|---|---|
| 0 | c0.d1 | 4 | 52.2 | embed | 0.0 | 54.5 | 17.1 | 71.6 | yes |
| 1, 3, 5 | c0.d0, c1.d0, c2.d0 | 3 | 38.7 | - | 0.0 | 41.0 | 12.8 | 53.8 | yes |
| 2, 4, 6 | c1.d1, c2.d1, c3.d1 | 4 | 51.7 | - | 0.0 | 53.9 | 17.1 | 71.1 | yes |
| 7 | c3.d0 | 3 | 40.5 | lm_head + draft | 0.0 | 42.7 | 12.8 | 55.6 | yes |

**T4 (context capacity):** L_max = min_pos ⌊(86·10⁹ − 2 GiB − 64 MiB − W_pos) / (n_pos · kv_tok · B)⌋:
dense f16 **551 253** (B = 1), 137 813 (B = 4), 34 453 (B = 16); dense int8 1 102 506; MoE 1 925 823 /
481 455 / 120 363. Every GB of per-die overhead beyond the assumed 2 GiB costs 16 276 tokens of dense L_max
and 61 035 of MoE (`[F1-dLmax]`). The B = 16 throughput configuration of §3 is memory-feasible for dense
only to 34k and for MoE to 120k: the "MEM" cells of the regime map.

### 1.8 Round 3 — variant I: two 4-die instances with the minimal int4 tier (`[R3-inst-*]`)

The round-2 plan spans the fleet with one model instance because T_min_dies forbids 4 dies under **full int8**
residency. PROBLEM-4 allows a "hot/cold residency split with quantified on-the-fly costs" as a legal escape, and HW-MAP
measured the only on-the-fly int4 path that exists on this part: the 5-pass vector unpack at **5.3 GB/s per core** of int4
bytes (42.4 per die; 2.06× slower per byte than the int8 stream, errata #12). ALTERNATIVES §2.1 showed that at Π = 1 this
trade is a win for the fleet (a byte served from int4 costs 2.06× its time but halves its memory, and memory is what pins
the fleet to one instance). Round 3 re-derives it on the measured λ, G and c_q and against this document's own memory model:

**(a)–(f) for variant I.** *Instance* = 4 dies = 2 cards, chain c0.d1 → c0.d0 → c1.d1 → c1.d0 (d1 first, d0 last: the T7
minimum class; 3 hops + logits + ids = **8 λ**); two instances on the 8 dies, each its own runtime process owning its two
cards' links; nothing crosses between them (errata #11 untouched). Layers per die: dense 30 (embedding on position 0,
lm_head on 3, the draft on 1), MoE 7. *Tier:* per die the smallest share x of the candidate bytes (MoE: the expert slabs —
the attention weights stay int8; dense: whole matrices in the order down, O, QKV, gate/up) stored as int4 such that
weights(x) + KV(L) + 64 MiB + 2 GiB ≤ 86 GB; weights(x) is non-increasing in x, so the minimal x is an iff (T3r_inst_fit; proof:
T3r_inst_fit_moe_32k / _dense_32k over every x, T3r_instance_margin over every overhead).
Under Zipf popularity the int4 experts are the coldest by H9's histogram. *Hot path:* DESIGN-2 scheme S (per-core column
slice of every active expert) at the anchored 122 979 ns per core-slab, or 99 374 on the direct path (E29). *Cold path:*
host-packed i4 nibbles in the f16 fractal order → DDR → US plain copies (≤ 64 KiB) → the measured 5-pass unpack → US → S1
(250 GB/s/core) → the 26.5 GB/s/core loader → f16×f16→f32 MMA → the region-difference epilogue [**audit (#19): VIOLATES — f16
accumulation into one C chunk across the per-piece barriers and the A re-lifts corrupts at ≥ 2 accumulations; every call writes a fresh
chunk and the vector unit sums the partials in f32: + 8 313 / 32 614 ns per core-slab, V3 MoE 32k 3.720 → 3.693 / 3.617, dense 0.155 →
0.150 / 0.142 (`[PA-inst-*]`, T6f_cold_merge_*); (#20 sibling): the US → S1 B-slot copy has a rate, not a content proof — E30 checks it;
(#25): the f16 A (x, 128 KiB) is staged in 32 KiB legs at 32-KiB-granular offsets beside x_q; (#30 / #18 / #28): the cold nest resets the
L0B ping-pong and preloads its own first piece, C regions by explicit byte offset, one arm per handshake**]; same core, same column
slice, hot experts first then cold, so scheme S's balance theorem holds per tier. KV, draft and exchange exactly as §1.3–1.5
with four positions. *Fleet accounting:* tokens/s per card = 2 instances / (4 cards × T_inst).

**Memory feasibility of the instance (`[R3-inst-fit-*]`; limit 86.0 GB; overhead 2 GiB + 64 MiB = 2.2 GB assumed, H8/H11):**

| shape, L | x per die (‰ of candidate bytes as int4), pos 0 / 1 / 2 / 3 | weights GB | KV GB | total GB each | worst-die margin | x at +1 GB / +3 GB overhead |
|---|---|---|---|---|---|---|
| MoE 4k | 163 / 152 / 152 / 163 | 83.6 | 0.1 | 85.9 | 5.6 MB | 186 … / 230 … |
| **MoE 32k** | **182 / 170 / 170 / 182** | 82.8 | 0.9 | 85.9 | 24.5 MB | 204 / 192 / 192 / 204 ; 248 / 236 / 236 / 248 |
| MoE 128k | 244 / 232 / 232 / 244 | 80.0 | 3.7 | 85.9 | 1.9 MB | 266 … / 311 … |
| MoE 1M | 827 / 816 / 816 / 827 | 53.7 | 30.0 | 85.9 | 2.7 MB | 850 … / 894 … |
| MoE 32k, B = 16 | 494 / 482 / 482 / 494 | | | 85.9 | | |
| dense 4k | 303 / 284 / 259 / 303 | 83.2 | 0.5 | 85.9 | 30.1 MB | 324 … / 365 … |
| **dense 32k** | **376 / 358 / 332 / 376** | 79.7 | 4.0 | 85.9 | 3.3 MB | 397 / 378 / 353 / 397 ; 439 / 420 / 395 / 439 |
| dense 128k | 629 / 610 / 585 / 629 | 67.6 | 16.1 | 85.9 | 15.0 MB | 650 … / 692 … |
| dense 1M (f16 or KV-int8) | **infeasible at x = 1000**: KV alone 128.8 / 64.4 GB per 4-die position | | | | | |

The fit is linear in x: every GB of per-die overhead above the assumed 2 GiB costs **23 ‰ of x (MoE) / 21 ‰ (dense)**, i.e.
about 0.66 ms (MoE 32k) per percent of x (24 core-slabs × 28 layers × (197 844 − 99 374) ns × 1 %); ship x + 2.3 % per GB of
margin wanted (H11 measures the margin). The minimal x leaves 2–30 MB on the worst die — the fit is exact, not comfortable.

**Instance step and the fleet cell (`[R3-inst-*]`, 32k, t = 1; every term as §3.5 with the four-position chain):**

| shape, L | hot tier / cold branch / popularity | T_inst (W, ATTN, launch, quant, xch) | 2 instances tok/s/card | vs one 8-die instance |
|---|---|---|---|---|
| **MoE 32k** | direct path (serialised A lift) / unpack overlapped / uniform | **134.37 ms** (88.60, 22.73, 18.01, 4.89, 0.12) | **3.720** | 1.802 → **+106.4 %** |
| MoE 32k | direct / unpack serial-chain (40.8 W8-eq — proof: 807 ns per piece) / uniform | 159.85 | 3.128 | +73.5 % (as first written: 147.06 / 3.399 / +88.6 %) |
| MoE 32k | **anchored serial kernel** (no E29) / overlapped / uniform | 147.44 | 3.391 | +88.1 % |
| MoE 32k | direct, A lift overlapped / overlapped / uniform | 132.55 | 3.771 | +109.2 % |
| MoE 32k | direct / overlapped / **Zipf(1.0)** (the coldest 18 % carry 3.2 % of the traffic) | 124.78 | 4.006 | +122.3 % |
| MoE 4k / 128k / 1M | direct / overlapped / uniform | 113.71 / 205.10 / 865.60 | 4.396 / 2.437 / 0.577 | +109.7 / +100.2 / +91.0 % |
| MoE 32k, B = 16 uniform | direct / overlapped | 1 982.46 | 4.035 | 2.325 → +73.5 % |
| **dense 32k** | 174.6 for the int8 bytes, 84.8 W8-eq for the int4 bytes (unpack overlapped) | **3 223.48 ms** (3 039.24, 97.44, 65.70, 20.97, 0.13) | **0.155** | 0.104 → **+49.0 %** |
| dense 32k | serial-chain unpack (40.8 — proof: 807 ns per piece) | 4 977.19 | 0.100 | **−3.8 %: a loss** (needs c ≥ 2.091×; as first written 4 095.48 / 0.122 / +17.3 %) |
| dense 32k, spec k = 3, α = 0.7 | overlapped; chain as specified / fixed-shift | 3 619.21 / 3 383.72 | 0.349 / 0.374 | 0.227 / 0.248 → +53.7 / +50.8 % |
| dense 4k / 128k | overlapped | 2 970.25 / 4 095.43 | 0.168 / 0.122 | +55.5 / +31.1 % (serial-chain, proof: 4k +5.5 %, 128k −24.7 %; first written −4.3 % at 128k) |

Per-sequence latency is 4 % *better* for MoE (134.37 < 138.69: the direct-path hot tier and eight fewer λ outweigh the
int4 bytes) and 35 % worse for dense. **Robustness (`[R3-inst-breakeven-moe-32k]`, T3r_inst_breakeven, an iff over the
cold-tier time):** two instances beat one for every int4 core-slab time ≤ 1 406 404 ns, i.e. any unpack rate ≥ 0.7 GB/s per
core — the measured 5.3 is 7.1× inside the line (at 4.0 / 3.0 / 2.0 / 1.0 GB/s/core the cell is 3.521 / 3.282 / 2.890 /
2.127). All-int4 replication (x = 1) gives 2.646: the tier is the price of the fit, the second instance is the gain. **Proof — H10 as a
variable (T3r_inst_gain_measured, T3r_inst_h10):** with c the fleet-scale concurrency (thousandths of one instance's throughput)
the cell is 1 000·c·10⁶ / (4·T_inst): MoE 32k beats the 8-die chain iff c ≥ 0.970 and the direct-path chain iff c ≥ 1.095; at the
measured card-scale c = 1.990 it is 3.702 (dense 0.154, iff c ≥ 1.354) and the breakeven moves to 1 394 680 ns per int4 core-slab.
Every overlapped-tier cell activates at 1.99×; the serial-chain dense cells do not (dense 32k needs c ≥ 2.091×, above two
solo-speed instances). The
variant is a **Π = 1 substitute**: Π = 8 pipelining of one 8-die instance (H4) would give 12.918 / 0.808, 3.4× / 5.2× the
two-instance cells — if H4 passes, every die is busy and the slower int4 bytes cost throughput, so the instances are undone.

**Gate and risks:** H10 (two runtime instances stream concurrently; host-only — GREEN at card scale, 1.99×; the 2-card-pair run
remains), H11 (the per-die fit at x with the measured
overhead), E30 (the cold chain's exactness and regime; kernel-side, owned by ALTERNATIVES), E29 for the hot tier. Thermal:
two cards at the measured 141 W sustained per instance (four at Π = 1 of each), inside the 150 W class (`[R3-power]`).

---

## 2. Per-token exchange traffic and its serialisation against compute

### 2.1 Traffic table (`[F10-xch-*]`, `[F2]`) — bandwidth terms at the measured link rates, latency λ separate
Activation per hop = rows × d_model × 2 B (f16): dense 32 KiB (t = 1) / 128 KiB (t = 4), MoE 8 / 32 KiB.
Logits = rows × 128 256 × 4 B (f32; the sampler runs on the host — on-device sampling is a runtime feature
not in HW-MAP, so the conservative path is costed).

| hop | from → to | dense bytes r=1 | link out / in GB/s | dense µs r=1 | dense µs r=4 | MoE bytes r=1 | MoE µs r=1 | MoE µs r=4 |
|---|---|---|---|---|---|---|---|---|
| 0 | pos0 c0.d1 → pos1 c0.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 1 | pos1 c0.d0 → pos2 c1.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 2 | pos2 c1.d1 → pos3 c1.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 3 | pos3 c1.d0 → pos4 c2.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 4 | pos4 c2.d1 → pos5 c2.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| 5 | pos5 c2.d0 → pos6 c3.d1 | 32 768 | 27.3 / 13.9 | 3.6 | 14.2 | 8 192 | 0.9 | 3.6 |
| 6 | pos6 c3.d1 → pos7 c3.d0 | 32 768 | 19.0 / 27.6 | 2.9 | 11.6 | 8 192 | 0.7 | 2.9 |
| L | pos7 c3.d0 logits → host | 513 024 | 27.3 / – | 18.8 | 75.2 | 513 024 | 18.8 | 75.2 |
| I | host ids → pos0 c0.d1 | 4 | – / 13.9 | 0.0 | 0.0 | 4 | 0.0 | 0.0 |
| **Σ bandwidth** | | | | **41.1** | **164.4** | | **24.4** | **97.5** |
| latencies | 7 hops × 2 + L + I = **16 λ** | | | | | | | |

Each hop is D2H (die → pinned host buffer) + H2D (host buffer → next die): the host touches nothing in
between for hops 0–6; for L/I the host samples (≤ 0.1 ms of CPU work at 128 256 logits, overlapped with
nothing — counted inside λ's bracket).

**Total per token-step** T_x = Σbw + 16λ (`[F2-*]`):

| λ (A, H3) | dense r=1 | dense r=4 | MoE r=1 | MoE r=4 |
|---|---|---|---|---|
| 10 µs | 201 µs | 324 µs | 184 µs | 257 µs |
| **91 µs (primary)** | **1 497 µs** | 1 620 µs | **1 480 µs** | 1 553 µs |
| 500 µs | 8 041 µs | 8 164 µs | 8 024 µs | 8 097 µs |

### 2.2 Serialisation analysis (Π = 1: every bounce is on the critical path, nothing overlaps it)
Layer-split with one sequence is inherently serial — layer ℓ+1 cannot start before layer ℓ's output has
bounced — so the exchange is modelled as **fully additive**, the worst case the prompt warns about: T_step =
Σ_layers T_layer + T_head + T_launch + T_x (+ T_draft). Shares at L = 32k, λ = 91 µs: dense 1.497 / 2 362 ms =
**0.06 %**, MoE 1.480 / 133.84 ms = **1.1 %** (`[F5-*-p2p]`).

**T8 (bounce threshold).** The step itself carries the 16 λ, so the bounce reaches a fraction x of the step iff 16λ + Σbw ≥ x·(T_rest + Σbw + 16λ), i.e. λ ≥ (x·T_rest − (1−x)·Σbw) / (16·(1−x)) with T_rest = T_step − T_x: 10 % needs λ ≥ 16.4 ms (dense) / **918 µs (MoE)**; 50 % needs 147.5 ms / 8.27 ms (`[F9-*-lambda]`, T_bounce_threshold_dense/_moe, iff for every λ). Round 1 solved against the fixed λ = 91 µs step and quoted 14.8 ms / 835 µs and 73.8 / 4.18 ms — at λ = 4.18 ms the MoE bounce is 33.6 % of the step, not 50 %. The
measured "+2 % at 2 dies" (one boundary, on a model of unstated size) bounds nothing sharper than λ ≲ 1 % of
that model's step; H1/H3 measure λ directly.

**T7 (order dependence).** Every die except the first receives the activation once and every die except the last sends it once, so the hop sum over the 7 hops is 4·(h₀ + h₁ + g₀ + g₁) − h(first die) − g(last die) (h = H2D time, g = D2H time of one activation): it depends on the chain order only through the first and last die types, plus the logits source (27.3 vs 19.0 GB/s: 18.8 vs 27.0 µs) and the id sink. The four classes are 41.1 µs (d1 first, d0 last — the chosen order), 42.3 (d0, d0), 48.8 (d1, d1) and 50.0 (d0, d1): the chosen order is the minimum, by 1.2 µs over the other d0-last order and 7.7–8.9 µs over the d1-last orders (T_order_formula, T_order_optimal: proved over all 70 orders; round 1 called the hop sum order-invariant).

### 2.3 The host bounce as a contended resource
- **Per-card trunk occupancy.** Die 1's link transits die 0, so each card's die-0 link carries its own
  hops plus die 1's: per token (dense r=1) 96 KiB (98 308 B), 128 KiB, 128 KiB and 597 KiB on the logits card
  (`[F2-dense-rows1]`); against a budget of 27.6 GB/s × T_step = 65 GB (dense) / 3.7 GB (MoE) per token the
  utilisation is < 0.02 %. **Bandwidth never binds; latency is the whole cost.**
- **Concurrent transfers.** At Π = 1 the only transfers that can coexist with a bounce are the draft's
  logits/ids (its die is idle otherwise) — no queueing. At Π = 8 (§5) up to 8 bounces per block time share the trunks: on the logits card 8 × 537 600 B per 18.6 ms block (MoE) = 0.84 % utilisation (dense: 8 × 611 328 B per 306 ms = 0.06 %); still no queueing (T_pipelining_trunk).
- **Bulk traffic (load, re-partition KV moves, any host-paging escape) does queue ahead of a bounce.** With
  bulk chunk size C on the same link the added wait is ≤ C/R_link per direction (T-queue, `[F8-H3]`): 64 KiB →
  5 µs, 1 MiB → 75 µs, 16 MiB → 1.2 ms on the 13.9 GB/s die-1 link. Rule: bulk streams that overlap decode
  are chunked at ≤ 1 MiB; H3 measures the realised wait under exactly this contention and fails the
  rule if the wait exceeds C/R + λ.
- **Hop 1/3/5 (d0 → d1', H2D at 13.9) is the slowest hop** (3.6 µs at 32 KiB, 14.2 at 128 KiB); the 0.6 µs (r = 1) to 2.6 µs (r = 4) it
  loses to a d1 → d0 hop is below λ's bracket and is not worth re-ordering for (T7).

### 2.4 Round 3 — the exchange at the measured bounce (`[R3-xch-*]`, `[R3-T8-*]`, `[R3-ladder-H3]`)

HW-MAP now measures the host bounce directly: **12.2 / 12.1 µs per direction on 4 KiB sync legs, bounce 23.8–24.6 µs,
unchanged when die 0's link is saturated by a D2D load**. The 91 µs this document used in rounds 1–2 was the kernel-launch
floor (the only measured runtime floor of that class at the time) borrowed as an anchor; it is a different quantity and
stays at 91 µs in the launch term. The bandwidth terms of §2.1 are unchanged; only the 16 latencies move:

| rows | dense Σbw | dense T_x = Σbw + 16 λ (round 2 at 91 µs) | MoE Σbw | MoE T_x (round 2) | λ = 10 / 500 µs what-ifs (dense) |
|---|---|---|---|---|---|
| 1 | 41.1 µs | **236 µs** (1 497) | 24.4 µs | **220 µs** (1 480) | 201 / 8 041 |
| 4 | 164.4 | 360 (1 620) | 97.5 | 293 (1 553) | 324 / 8 164 |
| 16 | 657.8 | 853 (2 114) | 390.0 | 585 (1 846) | 818 / 8 658 |

Shares of the 32k step: dense **0.01 %**, MoE **0.16 %** (round 2: 0.06 % / 1.1 %). **T8 re-instantiated (T3r_bounce_threshold,
an iff over λ):** the bounce reaches 10 % of the step iff λ ≥ 16.57 ms (dense) / **960 µs** (MoE) and 50 % iff λ ≥ 149.2 ms /
8.65 ms — the measured 12.2 µs is 1 358× / 78× below the 10 % line (the MoE line moved 918 → 960 µs because the rest of the
step grew by the quant pass). **Contention (§2.3), measured:** the bounce latency is the same idle and under a saturating
die-0 D2D load, so at the 4 KiB sync-leg size there is no queueing behind bulk traffic; the C/R rule for bulk streams
chunked above that (5 µs / 75 µs / 1.2 ms behind 64 KiB / 1 MiB / 16 MiB on the 13.9 GB/s link) stays the design rule for
loads and re-partition moves that overlap decode, and H3 now re-verifies it rather than deciding λ. Trunk utilisation at
Π = 1 is unchanged (the bytes did not move: < 0.02 %); the instance variant's chain has 8 latencies instead of 16 (T_x = 126 /
119 µs, `[R3-inst-*]`). The P2P bound of §5 shrinks with it: a P2P link at any rate saves ≤ 236 / 220 µs per token.

---

## 3. Predictive tokens/s/card model

### 3.1 The step (one sequence, B = 1, t query rows; every term integer in `proof/fleet.py`)
```
T_step(L, B, t)  = Σ_{layers} [ T_gemm + T_attn(L, B, t) ]  +  T_head  +  T_launch  +  T_x(rows)  +  T_draft(t)
T_gemm (dense)   = W_layer · 10 / 1746 ns                                   = 18 256 993 ns     [R_gemm, M]
T_gemm (MoE)     = W_attn · 10 / 1746  +  2·F + 3·D(rows)·T_slab            = 240 223 + 2 967 496 (serial) / 2 344 360 (pp)
T_attn           = max( KV, SM, MMA )                                       engines overlap as in the measured dense kernel
   KV            = kv_tok · L · B · 10 / G                                  kv_tok = 4096 (2048 int8)   [G: U]
   SM            = B · t · H_q · L · c_E · 10 / 3456                        [R_vec M, c_E: U]
   MMA           = B · 2 · H_kv · (L/16) · ⌈t·g/16⌉ · 15 / 8                [c_mma M; one kv-head per core]
T_head           = W_head · 10 / 1746                                       = 12 035 202 (dense) / 3 008 800 (MoE) ns
T_launch         = (n_L · launches_per_layer + 2) · 91 000                  = 65.70 ms (dense) / 18.01 ms (MoE)   [M; 0 if H6 shows pipelining]
T_x              = Σbw(rows) + 16 λ                                         §2
T_draft(t = k+1) = k · [ 10⁹·10/1746 + 201 MB·10/1746 + 121·91 000 + 513 KB·10/273 + 2λ ]   = 54.27 ms (k = 3; 21.24 if launches pipeline)
tokens per step  = B · τ(α, k),  τ(α, k) = Σ_{i=0..k} α^i  (1 at t = 1);  tokens/s/card = tokens per step / (4 · T_step)
```
Rows = B·t ≤ 16 always (T13: m ≥ 24 measured at 81 GB/s = 46 % of the flat rate). The per-layer attention
terms (`[F3-*-attn]`, ns, B = 1, t = 1):

| shape | L | KV (stream / gather3x) | softmax (native / poly) | MMA |
|---|---|---|---|---|
| dense | 4k | 96 089 / 288 268 | 6 068 / 24 272 | 7 680 |
| dense | 32k | 768 715 / 2 306 146 | 48 545 / 194 180 | 61 440 |
| dense | 128k | 3 074 862 / 9 224 586 | 194 180 / 776 722 | 245 760 |
| dense | 1M | 24 598 896 / 73 796 688 | 1 553 445 / 6 213 783 | 1 966 080 |
| MoE | 32k | 768 715 / 2 306 146 | 12 136 / 48 545 | 61 440 |
| MoE | 1M | 24 598 896 / 73 796 688 | 388 361 / 1 553 445 | 1 966 080 |

Softmax and MMA are 6–8 % of the KV stream at t = 1 on the stream branch: the attention step is a KV stream
with the vector and matrix units at ≤ 8 % occupancy — the "attention must stay a bounded fraction of the
GEMV step" target of PROBLEM-3 is met by the layout, not by a kernel trick (the fraction is KV/T_gemm:
4.2 % at 32k for dense, 24 % at 32k for MoE, §4).

### 3.2 The L × configuration table (primary branch: G stream, native exp, λ = 91 µs, launches serialised, MoE serial regime, uniform routing) — `[F3]`

| shape | L | config | feasible | T_step ms | W ms | KV ms | launch ms | bounce ms | draft ms | tokens/step | **tok/s/card** | binding |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense | 4k | B=1 t=1 | yes | 2281.60 | 2202.87 | 11.53 | 65.70 | 1.49 | 0.00 | 1.000 | **0.109** | W |
| dense | 4k | spec k=3 α=0.7 | yes | 2336.00 | 2202.87 | 11.53 | 65.70 | 1.62 | 54.27 | 2.533 | 0.271 | W |
| dense | 4k | B=16 t=1 | yes | 2455.18 | 2202.87 | 184.49 | 65.70 | 2.11 | 0.00 | 16.000 | 1.629 | W |
| dense | 32k | B=1 t=1 | yes | 2362.31 | 2202.87 | 92.24 | 65.70 | 1.49 | 0.00 | 1.000 | **0.105** | W |
| dense | 32k | spec k=3 α=0.7 | yes | 2416.71 | 2202.87 | 92.24 | 65.70 | 1.62 | 54.27 | 2.533 | 0.262 | W |
| dense | 32k | B=16 t=1 | yes | 3746.62 | 2202.87 | 1475.93 | 65.70 | 2.11 | 0.00 | 16.000 | 1.067 | W |
| dense | 128k | B=1 t=1 | yes | 2639.05 | 2202.87 | 368.98 | 65.70 | 1.49 | 0.00 | 1.000 | **0.094** | W |
| dense | 128k | spec k=3 α=0.7 | yes | 2693.45 | 2202.87 | 368.98 | 65.70 | 1.62 | 54.27 | 2.533 | 0.235 | W |
| dense | 128k | B=16 t=1 | **NO** | 8174.42 | 2202.87 | 5903.73 | 65.70 | 2.11 | 0.00 | 16.000 | – | MEM |
| dense | 1M | B=1 t=1, f16 KV | **NO** | 5221.94 | 2202.87 | 2951.86 | 65.70 | 1.49 | 0.00 | 1.000 | – | MEM |
| dense | 1M | B=1 t=1, **KV-int8** | yes | 3746.00 | 2202.87 | 1475.93 | 65.70 | 1.49 | 0.00 | 1.000 | **0.066** | W |
| dense | 1M | spec k=3 α=0.7, f16 KV | **NO** | 5276.34 | 2202.87 | 2951.86 | 65.70 | 1.62 | 54.27 | 2.533 | – | MEM |
| dense | 1M | spec k=3 α=0.7, KV-int8 | yes | 3800.40 | 2202.87 | 1475.93 | 65.70 | 1.62 | 54.27 | 2.533 | 0.166 | W |
| dense | 1M | B=16 t=1 | **NO** | 49500.57 | 2202.87 | 47229.88 | 65.70 | 2.11 | 0.00 | 16.000 | – | MEM |
| MoE | 4k | B=1 t=1 | yes | 115.01 | 92.82 | 2.69 | 18.01 | 1.48 | 0.00 | 1.000 | **2.173** | W |
| MoE | 4k | spec k=3 α=0.7 | yes | 417.28 | 340.75 | 2.69 | 18.01 | 1.55 | 54.27 | 2.533 | 1.517 | W |
| MoE | 4k | B=16 t=1 | yes | 1395.36 | 1332.45 | 43.04 | 18.01 | 1.84 | 0.00 | 16.000 | 2.866 | W |
| MoE | 32k | B=1 t=1 | yes | 133.84 | 92.82 | 21.52 | 18.01 | 1.48 | 0.00 | 1.000 | **1.867** | W |
| MoE | 32k | spec k=3 α=0.7 | yes | 436.12 | 340.75 | 21.52 | 18.01 | 1.55 | 54.27 | 2.533 | 1.451 | W |
| MoE | 32k | B=16 t=1 | yes | 1696.70 | 1332.45 | 344.38 | 18.01 | 1.84 | 0.00 | 16.000 | 2.357 | W |
| MoE | 128k | B=1 t=1 | yes | 198.41 | 92.82 | 86.09 | 18.01 | 1.48 | 0.00 | 1.000 | **1.259** | W |
| MoE | 128k | spec k=3 α=0.7 | yes | 500.69 | 340.75 | 86.09 | 18.01 | 1.55 | 54.27 | 2.533 | 1.264 | W |
| MoE | 128k | B=16 t=1 | **NO** | 2729.85 | 1332.45 | 1377.53 | 18.01 | 1.84 | 0.00 | 16.000 | – | MEM |
| MoE | 1M | B=1 t=1 | yes | 801.09 | 92.82 | 688.76 | 18.01 | 1.48 | 0.00 | 1.000 | **0.312** | KV |
| MoE | 1M | spec k=3 α=0.7 | yes | 1103.36 | 340.75 | 688.76 | 18.01 | 1.55 | 54.27 | 2.533 | 0.573 | KV |
| MoE | 1M | B=16 t=1 | **NO** | 12372.62 | 1332.45 | 11020.30 | 18.01 | 1.84 | 0.00 | 16.000 | – | MEM |

W = all weight streams (layers + lm_head; for MoE attention GEMMs + active experts). "binding" = the largest
additive term. The infeasible rows are printed for the arithmetic only (what the time would be if the memory
existed). The 40 %-scored cells are the bold t = 1 rows at 32k: **dense 0.105, MoE 1.867 tokens/s/card**;
the configuration the plan actually runs at 32k is dense with spec decode (0.262) and MoE at t = 1 (1.867).

### 3.3 Branches at L = 32k, B = 1, t = 1 (`[F3b]`) — one toggle at a time
| branch | dense ms → tok/s/card | MoE ms → tok/s/card |
|---|---|---|
| **primary** | 2362.31 → **0.105** | 133.84 → **1.867** |
| G = gather3x (KV 3× slower) | 2546.81 → 0.098 | 176.89 → 1.413 |
| c_E = poly (no exp instruction) | 2362.31 → 0.105 (softmax still < KV) | 133.84 → 1.867 |
| λ = 10 µs / 500 µs | 2361.02 → 0.105 / 2368.86 → 0.105 | 132.55 → 1.886 / 140.39 → 1.780 |
| launches pipelined (H6) | 2296.61 → 0.108 | 115.82 → 2.158 |
| MoE ping-pong regime (DESIGN-2 E13) | – | 116.39 → 2.147 |
| routing Zipf(1.5) at t = 1 | – | 133.84 → 1.867 (D(1) = 8 under every family) |
| **pessimistic** (gather3x + poly + λ 500) | 2553.35 → 0.097 | 183.43 → 1.362 |
| **optimistic** (λ 10 + launches pipelined + MoE pp) | 2295.32 → 0.108 | 97.08 → 2.575 |

The dense prediction is bracketed within −8 % / +3 % by every unmeasured quantity of the model; the MoE
prediction within −27 % / +38 % (the KV-stream branch and the two kernel-regime branches are each worth
15–25 % because MoE streams 30× fewer weight bytes per token than dense, so everything else is visible).

### 3.4 MoE at B = 16 by routing family (`[F3c]`; D(16) from DESIGN-2's generator)
| family | D(16) | T_step 32k | W | KV | tok/s/card 32k | 1M |
|---|---|---|---|---|---|---|
| uniform | 128 | 1696.70 ms | 1332.45 | 344.38 | 2.357 | MEM (KV 11.0 s if it fit) |
| Zipf(1.0) | 68 | 1076.88 | 712.63 | 344.38 | 3.714 | MEM |
| Zipf(1.5) | 45 | 839.29 | 475.04 | 344.38 | 4.765 | MEM |

Batching sequences on a MoE die amortises the attention GEMMs, lm_head and launch floor but not the expert
stream under uniform routing (D = 8·rows): the lever is routing overlap, exactly DESIGN-2 §5.4's "tokens/s
scale with t/D(t)". H9 (host-side routing histogram) decides which row applies.

### 3.5 Round 3 — the step on the measured constants (`[R3-layer-*]`, `[R3-attn-*]`, `[R3-step]`, `[R3-branch-*]`, `[R3-B16-*]`)

**3.5.1 The step.** Three terms change and one is added:
```
T_step3(L, B, t) = Σ_layers [ T_gemm + B·T_attn3(L, t) + 4·c_q ] + T_head + T_launch + T_x(rows, λ = 12.2 µs) + T_draft3(t)
T_attn3(L, t)    = passes · nb · max(ddr, vec, mma, loader) + fixed           DESIGN-3 round 3 (proof/attn.py step3), rows = t·g per core
   rows          = t·g  (g = 16 dense, 4 MoE); mt = ⌈rows/16⌉ fragments; blocks of 512 tokens (256 at mt ≥ 3); passes = ⌈rows/64⌉
   ddr           = 2 MiB·10/G per block (1 MiB at 256-token blocks); G = 1692 (256 KiB pages), 1670 (64 KiB), 1538 (16 KiB)
   vec           = 9 276·mt ns per 512-token block (chain as specified, throughput convention) — 6 837·mt per 256-token block
   fixed         = 2·vec + drain(268 ns at the measured R_drain) = 18 820 ns (mt = 1)        [fixed-shift chain: 5 530·mt, 11 328]
c_q              = 43 700 ns per A-quantization pass, 4 per layer: 174 800 ns = 20.97 ms (dense) / 4.89 ms (MoE) per token   [M]
T_gemm (MoE)     = 240 223 + 2·F + 24·T_slab:  3 207 719 (anchored serial, primary) / 2 641 199 (direct path) / 2 562 359 (direct, A lift overlapped) / 2 584 583 (pp)
T_draft3(k = 3)  = 3 · [5 727 + 1 153 + 11 011 + 4 195 (24 layers × 4 quant passes) + 19 + 24 µs] = 66.38 ms   (round 2: 54.27)
```
Per-layer attention on the primary page size (`[R3-attn-*]`, ns, binding engine; both shapes share the KV geometry, so the
t = 1 cells coincide — dense rows = 16 and MoE rows = 4 both fit one fragment):

| L | t = 1, 256 KiB (primary) | 64 KiB / 16 KiB | 174.6 ceiling / gather3x what-if | chained corner / fixed-shift | **dense t = 4 (rows 64, mt 4)** as specified / fixed-shift | MoE t = 4 (rows 16) | KV-int8 t = 1 as specified / fixed-shift | round 2 (stream) |
|---|---|---|---|---|---|---|---|---|
| 4k | 117 972 (KV) | 119 276 / 127 900 | 114 908 / 307 084 | 123 092 / 110 480 | **492 644 (VEC)** / 220 916 (VEC) | 117 972 (KV) | 93 028 (VEC) / 60 904 (KV) | 96 089 |
| 32k | **812 036 (KV)** | 822 468 / 891 460 | 787 524 / 2 324 932 | 817 156 / 804 544 | **3 555 844 (VEC)** / 1 593 364 (VEC) | 812 036 (KV) | 612 484 (VEC) / 407 936 (KV) | 768 715 |
| 128k | 3 191 684 (KV) | 3 233 412 / 3 509 380 | 3 093 636 / 9 243 268 | 3 196 804 / 3 184 192 | 14 058 244 (VEC) / 6 298 900 (VEC) | 3 191 684 (KV) | 2 393 476 (VEC) / 1 597 760 (KV) | 3 074 862 |
| 1M | 25 401 732 (KV) | 25 735 556 / 27 943 300 | 24 617 348 / 73 814 404 | 25 406 852 / 25 394 240 | 112 080 644 (VEC) / 50 217 236 (VEC) | 25 401 732 (KV) | 19 016 068 (VEC) / 12 702 784 (KV) | 24 598 896 |

Every t = 1 cell is the KV stream (the chain as specified is 74.8 % of the block at 169.2 — DDR-bound without margin on the
chained reading, 95.5 %); the fixed 18.8 µs is 16 % of the 4k cell and 2.3 % at 32k. **The dense verify batch is not:** t = 4
at g = 16 is 64 rows = four fragments on 256-token blocks, 4.4× the DDR time per block (27 350 vs 6 197 ns), so a dense
spec-decode step carries 427 ms of attention at 32k instead of 97 (191 on the fixed-shift chain, E35). MoE verify batches
(rows 16) stay one fragment. KV-int8 halves the stream but not the chain: vector-bound at t = 1 on the chain as specified
(612 µs at 32k, 19.0 ms at 1M), DDR-bound on the fixed-shift chain (408 µs / 12.7 ms).

**3.5.2 The L × configuration table — primary round-3 branch (`[R3-step]`: 256 KiB pages, chain as specified, λ = 12.2 µs,
launches serialised, MoE anchored serial regime, uniform routing, c_q fixed).** Feasibility is round 2's (unchanged).

| shape | L | config | feasible | T_step ms | W ms | ATTN ms | launch ms | quant ms | bounce ms | draft ms | tokens/step | **tok/s/card** | binding | round 2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense | 4k | B=1 t=1 | yes | 2303.94 | 2202.87 | 14.15 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | **0.108** | W | 0.109 |
| dense | 4k | spec k=3 α=0.7 | yes | 2415.41 | 2202.87 | 59.11 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.262 | W | 0.271 |
| dense | 4k | spec k=3 α=0.7, fixed-shift | yes | 2382.81 | 2202.87 | 26.50 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.265 | W | – |
| dense | 4k | B=16 t=1 | yes | 2516.91 | 2202.87 | 226.50 | 65.70 | 20.97 | 0.85 | 0.00 | 16.000 | 1.589 | W | 1.629 |
| dense | 32k | B=1 t=1 | yes | 2387.23 | 2202.87 | 97.44 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | **0.104** | W | 0.105 |
| dense | 32k | spec k=3 α=0.7 | yes | 2783.00 | 2202.87 | 426.70 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.227 | W | 0.262 |
| dense | 32k | spec k=3 α=0.7, fixed-shift | yes | 2547.50 | 2202.87 | 191.20 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.248 | W | – |
| dense | 32k | B=16 t=1 | yes | 3849.51 | 2202.87 | 1559.10 | 65.70 | 20.97 | 0.85 | 0.00 | 16.000 | 1.039 | W | 1.067 |
| dense | 128k | B=1 t=1 | yes | 2672.79 | 2202.87 | 383.00 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | **0.093** | W | 0.094 |
| dense | 128k | spec k=3 α=0.7 | yes | 4043.29 | 2202.87 | 1686.98 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.156 | W | 0.235 |
| dense | 128k | spec k=3 α=0.7, fixed-shift | yes | 3112.16 | 2202.87 | 755.86 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.203 | W | – |
| dense | 128k | B=16 t=1 | **NO** | 8418.43 | 2202.87 | 6128.03 | 65.70 | 20.97 | 0.85 | 0.00 | 16.000 | – | MEM | MEM |
| dense | 1M | B=1 t=1, f16 KV | **NO** | 5337.99 | 2202.87 | 3048.20 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | – | MEM | MEM |
| dense | 1M | B=1 t=1, **KV-int8** | yes | 4571.71 | 2202.87 | 2281.92 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | **0.054** | **ATTN (vector)** | 0.066 |
| dense | 1M | B=1 t=1, KV-int8, fixed-shift | yes | 3814.12 | 2202.87 | 1524.33 | 65.70 | 20.97 | 0.23 | 0.00 | 1.000 | 0.065 | W | – |
| dense | 1M | spec k=3 α=0.7, KV-int8 | yes | 15805.97 | 2202.87 | 13449.67 | 65.70 | 20.97 | 0.35 | 66.38 | 2.533 | 0.040 | ATTN (vector) | 0.166 |
| dense | 1M | B=16 t=1 | **NO** | 51061.73 | 2202.87 | 48771.32 | 65.70 | 20.97 | 0.85 | 0.00 | 16.000 | – | MEM | MEM |
| MoE | 4k | B=1 t=1 | yes | 119.26 | 92.82 | 3.30 | 18.01 | 4.89 | 0.21 | 0.00 | 1.000 | **2.096** | W | 2.173 |
| MoE | 4k | spec k=3 α=0.7 | yes | 433.64 | 340.75 | 3.30 | 18.01 | 4.89 | 0.29 | 66.38 | 2.533 | 1.460 | W | 1.517 |
| MoE | 4k | B=16 t=1 | yes | 1408.80 | 1332.45 | 52.85 | 18.01 | 4.89 | 0.58 | 0.00 | 16.000 | 2.839 | W | 2.866 |
| MoE | 32k | B=1 t=1 | yes | 138.69 | 92.82 | 22.73 | 18.01 | 4.89 | 0.21 | 0.00 | 1.000 | **1.802** | W | 1.867 |
| MoE | 32k | spec k=3 α=0.7 | yes | 453.08 | 340.75 | 22.73 | 18.01 | 4.89 | 0.29 | 66.38 | 2.533 | 1.397 | W | 1.451 |
| MoE | 32k | B=16 t=1 | yes | 1719.74 | 1332.45 | 363.79 | 18.01 | 4.89 | 0.58 | 0.00 | 16.000 | 2.325 | W | 2.357 |
| MoE | 128k | B=1 t=1 | yes | 205.32 | 92.82 | 89.36 | 18.01 | 4.89 | 0.21 | 0.00 | 1.000 | **1.217** | W (by 0.5 % per layer) | 1.259 |
| MoE | 128k | spec k=3 α=0.7 | yes | 519.71 | 340.75 | 89.36 | 18.01 | 4.89 | 0.29 | 66.38 | 2.533 | 1.218 | W | 1.264 |
| MoE | 128k | B=16 t=1 | **NO** | 2785.82 | 1332.45 | 1429.87 | 18.01 | 4.89 | 0.58 | 0.00 | 16.000 | – | MEM | MEM |
| MoE | 1M | B=1 t=1 | yes | 827.20 | 92.82 | 711.24 | 18.01 | 4.89 | 0.21 | 0.00 | 1.000 | **0.302** | ATTN (KV) | 0.312 |
| MoE | 1M | spec k=3 α=0.7 | yes | 1141.59 | 340.75 | 711.24 | 18.01 | 4.89 | 0.29 | 66.38 | 2.533 | 0.554 | ATTN (KV) | 0.573 |
| MoE | 1M | B=16 t=1 | **NO** | 12735.92 | 1332.45 | 11379.97 | 18.01 | 4.89 | 0.58 | 0.00 | 16.000 | – | MEM | MEM |

The 40 %-scored cells are **dense 0.104 and MoE 1.802** (t = 1, 32k); the configuration the plan runs at 32k is dense with
spec decode (0.227, or 0.248 once E35 lands the fixed-shift chain) and MoE at t = 1 — 1.802 on the anchored kernel, 2.035
once the expert kernel runs on the direct path (E29), 3.720 on two instances (H10). What moved and why (`[R3-moved-*]`):
dense t = 1 −0.9 % (quant +20.97 ms, attention +5.20, bounce −1.26); MoE t = 1 −3.4 % (quant +4.89, attention +1.21,
bounce −1.27); dense spec −13.3 % (the 64-row attention +334 ms, the draft's quant passes +12.6 ms); dense 128k spec
−33.6 %; dense 1M KV-int8 −18.1 % (vector-bound; −1.5 % on the fixed-shift chain); the B = 16 cells −1 … −3 %.

**3.5.3 Branches at L = 32k, B = 1, t = 1 (`[R3-branch-*]`) — one toggle at a time:**

| branch | dense ms → tok/s/card | MoE ms → tok/s/card |
|---|---|---|
| **primary** | 2387.23 → **0.104** | 138.69 → **1.802** |
| page size 64 KiB shuffled (167.0) / 16 KiB (153.8) / W8 ceiling 174.6 | 2388.48 / 2396.76 / 2384.29 → 0.104 | 138.98 → 1.798 / 140.91 → 1.774 / 138.00 → 1.811 |
| gather3x what-if (58.2) | 2568.78 → 0.097 | 181.05 → 1.380 |
| fixed-shift chain / chained-latency corner | 2386.33 / 2387.84 → 0.104 | 138.48 → 1.805 / 138.83 → 1.800 |
| λ = 10 / 91 / 500 µs | 2387.19 / 2388.49 / 2395.03 → 0.104 | 138.65 → 1.802 / 139.95 → 1.786 / 146.49 → 1.706 |
| launches pipelined (H6) | 2321.53 → 0.107 | 120.67 → 2.071 |
| no quant pass / quant ∝ elements (E38) | 2366.25 → 0.105 / 2434.42 → 0.102 | 133.79 → 1.868 / 141.14 → 1.771 |
| integrated chain 135.5 for every weight stream (quant folded) | 3022.89 → 0.082 | 141.50 → 1.766 |
| MoE expert regime: direct path / direct overlapped / ping-pong | – | 122.83 → **2.035** / 120.62 → 2.072 / 121.24 → 2.061 |
| routing Zipf(1.5) at t = 1 | – | 138.69 → 1.802 (D(1) = 8 under every family) |
| megakernel c_sync 2 / 5 / 20 µs | 2335.43 → 0.107 / 2336.87 → 0.106 / 2344.07 → 0.106 | 123.79 → 2.019 / 124.21 → 2.012 / 126.31 → 1.979 |
| **pessimistic** (16 KiB pages, chained latencies, λ 500 µs, integrated chain) | 3019.87 → 0.082 (−21 %) | 146.78 → 1.703 (−5 %) |
| **optimistic** (fixed-shift, λ 10, launches pipelined, no quant pass, direct overlapped) | 2299.62 → 0.108 (+4 %) | 97.46 → 2.564 (+42 %) |

The dense cell is bracketed −21 % / +4 % (the integrated-chain reading is the whole downside: on the 174.6 kernel plus the
measured pass it is 0.102–0.105 for every other toggle); the MoE cell −5 % / +42 % — the expert-kernel regime and the
launch floor are the two big MoE levers, both measurable, neither a runtime change.

**3.5.4 MoE B = 16 by routing family (`[R3-B16-*]`):** uniform D = 128 → 1 719.74 ms, **2.325** (2.728 on the direct path);
Zipf(1.0) D = 68 → 1 099.92, 3.636 (4.144); Zipf(1.5) D = 45 → 862.33, 4.638 (5.173); 1M infeasible (memory). The
attention of 16 sequences is 363.79 ms at 32k (21 % of the step).

### 3.6 Round 5 — the step on the measured attention kernel (`[R5-attn-*]`, `[R5-step-*]`, `[R5-headline-*]`, `[R5-B16-*]`, `[R5-inst-*]`)

**The attention term is a measured per-layer time.** fleet.py `step5f` is the round-4 step with the attention replaced by a per-layer time
a (ns); every other term (weights, lm_head, launches, quant passes, bounce, draft) is unchanged. The step is affine in a (T5r_step_form, ∀ a):
**T_dense = 2 289 788 669 + 120·a, T_MoE = 115 956 899 + 28·a** (t = 1, B = 1). The three readings per layer (T5r_readings; DESIGN-3 §6.0):

| L | guarded (M) | unguarded | fused (target, E39) | constant-rate bracket 143.0 / 140.0 | round 4 (lazy-T, legs 2, 169.2) |
|---|---|---|---|---|---|
| 4k | 213 500 ns | 141 650 (D) | 161 650 (D) | 117 323 / 119 837 | 130 872 |
| 32k | 1 513 600 | **938 800 (M)** | **958 800** (D) | 938 585 / 958 698 | 911 680 |
| 128k | 5 852 900 | 3 553 700 (D) | 3 573 700 (D) | 3 754 342 / 3 834 792 | 3 588 736 |
| 1M | 46 313 600 | 27 920 000 (D) | 27 940 000 (D) | 30 034 736 / 30 678 337 | 28 574 592 |

**The cells (T5r_step_cells; ms → tokens/s/card, change against round 4, binding term):**

| shape, L | round 4 | guarded (M attention) | unguarded | fused | constant-rate bracket |
|---|---|---|---|---|---|
| dense 4k | 2 305.49 → 0.108 | 2 315.40 → **0.107** (−0.9 %; W) | 2 306.78 → 0.108 | 2 309.18 → 0.108 | 0.108 / 0.108 |
| dense 32k | 2 399.19 → 0.104 | 2 471.42 → **0.101** (−2.8 %; W, attention 7.3 %) | 2 402.44 → 0.104 | 2 404.84 → 0.103 | (32k is measured) |
| dense 128k | 2 720.43 → 0.091 | 2 992.13 → **0.083** (−8.7 %; W, attention 23.5 %) | 2 716.23 → 0.092 | 2 718.63 → 0.091 | 0.091 / 0.090 |
| MoE 4k | 119.62 → 2.089 | 121.93 → **2.050** (−1.8 %; W) | 119.92 → 2.084 | 120.48 → 2.074 | 2.096 / 2.095 |
| MoE 32k | 141.48 → 1.766 | 158.33 → **1.578** (−10.6 %; W, attention 26.8 %) | 142.24 → 1.757 | 142.80 → 1.750 | (32k is measured) |
| MoE 128k | 216.44 → 1.155 | 279.83 → **0.893** (−22.6 %; **ATTN** 58.6 %) | 215.46 → 1.160 (ATTN) | 216.02 → 1.157 (ATTN) | 1.130 / 1.119 |
| MoE 1M | 916.04 → 0.272 | 1 412.73 → **0.176** (−35.2 %; **ATTN** 91.8 %) | 897.71 → 0.278 | 898.27 → 0.278 | 0.261 / 0.256 |

Dense 1M (KV-int8 only; no KV-int8 kernel is measured): the round-4 rowmax cell (4 698.92 ms → 0.053) plus erratum #29's per-block crossing
(≥ 10 318 ns × 2 048 blocks × 120 layers = +2 535.75 ms) gives **≤ 0.034** (T5r_dense1M_bound — a bound; the lazy μ = 0 route is UNMEASURED). **audit (#31):** the 10 318 ns crossing is the
drain + 16 scalar reads of freshly reduced maxima — the racing composition; the deterministic crossing (16 scalar-destination reduces,
17 600 ns) adds 4 325.38 ms: **≤ 0.027** (`[PA-dense-1M-kvi8]`, T6f_dense1M_det) — a tighter bound on a route that is shippable, still UNMEASURED.
Reading it: the guarded column is what the shipped kernel delivers (the guard is 38 % of the attention at 32k); the unguarded and fused
columns are within ±2.2 % of round 4 on every cell (the round-4 attention model was right on the unguarded cell); the bracket shows how
much of that rests on the per-block scaling of the guard off 32k (up to 6.1 % / 7.9 % at MoE 1M, unguarded / fused).

**MoE B = 16 (uniform) at 32k** (T5r_B16): 2 034.04 → **1.966** guarded / 1 776.53 → 2.251 unguarded / 1 785.49 → 2.240 fused (round 4:
2.267) — 16 sequences carry 678.09 ms of guarded attention. **Two 4-die instances** (T5r_inst; overlapped cold tier, the round-3 minimal
shares, H10's c = 1.990): MoE 32k 154.02 / 137.92 / 138.48 ms → **3.230** / 3.607 / 3.592 (round 3: 3.702), each beating its one-instance
cell for every c ≥ 0.973 / 0.970 / 0.970; dense 32k 3 307.67 / 3 238.69 / 3 241.09 ms → 0.150 / 0.153 / 0.153, for every c ≥ 1.350 /
1.361 / 1.349. The instance decision is unchanged on every reading.

### 3.7 Round 6 — the step on the measured deferred kernel (`[R6-attn-*]`, `[R6-step-*]`, `[R6-headline-*]`, `[R6-B16-*]`, `[R6-inst-*]`)

**The attention term is the MEASURED deferred-guard kernel.** The step is still `step5f`, affine in the per-layer attention a (T5r_step_form:
T_dense = 2 289 788 669 + 120·a, T_MoE = 115 956 899 + 28·a), so every cell below is an instance of that form at a measured a
(T6r_attn6, T6r_step6_cells):

| L | per-layer a (M, session 5) | GB/s | against round 5's fused reading (D) | against the legacy scan (M, session 3) |
|---|---|---|---|---|
| 4k | not measured — round 5's readings stay (unguarded 141 650 / fused 161 650 ns, D) | | | |
| 32k | **945 500** trip-free; 946 300–947 400 amortized (the 0.087–0.22 % premise) | 142.0; 141.8–141.7 | −1.4 % | −37.5 % |
| 128k | **3 618 800** | 148.4 | +1.3 % | −38.2 % |
| 1M | **28 694 000** | 149.7 | +2.7 % | −38.0 % |

| shape, L | round 4 | round 5: legacy (M) / unguarded / fused | **round 6: deferred (M attention)** | binding; ATTN share of the step |
|---|---|---|---|---|
| dense 32k | 0.104 | 0.101 / 0.104 / 0.103 | 2 403.24 ms → **0.104** (amortized 2 403.34 / 2 403.47 → 0.104 / 0.104) | W; 4.7 % |
| dense 128k | 0.091 | 0.083 / 0.092 / 0.091 | 2 724.04 → **0.091** | W; 15.9 % |
| MoE 32k | 1.766 | 1.578 / 1.757 / 1.750 | 142.43 → **1.755** (amortized 142.45 / 142.48 → 1.754 / 1.754) | W; 18.6 % |
| MoE 128k | 1.155 | 0.893 / 1.160 / 1.157 | 217.28 → **1.150** | **ATTN**; 46.6 % |
| MoE 1M | 0.272 | 0.176 / 0.278 / 0.278 | 919.38 → **0.271** | **ATTN**; 87.4 % |

Reading it: at 32k the measured kernel sits between round 5's unguarded and fused readings (1.755 against 1.757 / 1.750); at 128k and 1M
it sits below both (1.150 against 1.160 / 1.157, 0.271 against 0.278) because round 5's off-32k readings were optimistic per layer
(DESIGN-3 §6.0′). The trips cost the MoE 32k cell one thousandth (1.755 → 1.754); dense does not see them. Dense 1M exists only on KV-int8,
which the deferred guard does not reach (the rowmax chain's per-block max, or the lazy μ = 0 route, UNMEASURED): it stays at PROMPT-6's
≤ 0.027 bound. **MoE B = 16 (uniform)** on the deferred cell: 1 779.53 ms → **2.247** (2.246 amortized-hi; round 5 1.966 / 2.251 / 2.240,
round 4 2.267; T6r_B16_6). **Two 4-die instances** (V3 with the PROMPT-6 erratum-#19 merge, H10's c = 1.990; T6r_inst6, T6r_inst6_c): MoE
32k 139.09 ms → **3.576** (T) / 141.97 → **3.504** (C) trip-free (3.575 / 3.502 amortized-hi), each beating the one-instance cell (1.755)
for every c ≥ 0.978 / 0.998; dense 0.149 (T) / 0.140 (C), for every c ≥ 1.402 / 1.483. The instance decision is unchanged.

---

## 4. Regime map and crossover theorems

### 4.1 Binding constraint per (shape, L, rows) — `[F4-regime]` (primary branch; share of the step in brackets)
| shape | L | rows = 1 (t = 1) | rows = 4 (verify, k = 3) | rows = 16 (B = 16, t = 1) |
|---|---|---|---|---|
| dense | 4k | W (96.5 %) | W (94.3 %) | W (89.7 %) |
| dense | 32k | W (93.3 %) | W (91.2 %) | W (58.8 %) — KV 39 % |
| dense | 128k | W (83.5 %) | W (81.8 %) | **MEM** (L_max(16) = 34 453) |
| dense | 1M | **MEM** f16 → W (58.8 %) with KV-int8, KV 39 % | **MEM** → W with KV-int8 | **MEM** |
| MoE | 4k | W (80.7 %) — launch 15.7 % | W (81.7 %) | W (95.5 %) |
| MoE | 32k | W (69.4 %) — KV 16 %, launch 13.5 % | W (78.1 %) | W (78.5 %) — KV 20 % |
| MoE | 128k | W (46.8 %) — KV 43.4 % | W (68.1 %) | **MEM** (L_max(16) = 120 363) |
| MoE | 1M | **KV (86.0 %)** | KV (62.4 %) | **MEM** |

Host bounce is nowhere above 1.1 %; softmax is nowhere binding at rows ≤ 4 on the native branch; "imbalance"
does not exist at Π = 1 (T1). The two regime changes inside the table are MoE's KV crossover between 128k
and 1M and dense's memory wall between 551k and 1M.

### 4.2 Crossover derivations (the Lean targets; all integers from `proof/fleet.py`)
**T5 — KV-bandwidth crossover.** Per layer, KV binds iff kv_tok·L·B·10/G ≥ T_w(rows), i.e.
L ≥ L* = ⌈T_w · G / (10 · kv_tok · B)⌉ (`[F4-*-Lkv-*]`):

| shape | G branch | T_w per layer (ns) | L* at B = 1 | B = 4 | B = 16 |
|---|---|---|---|---|---|
| dense | stream 174.6 | 18 256 993 | **778 240** (= W_layer / 4096 exactly, since W_layer = 778 240 · 4096) | 194 560 | 48 640 |
| dense | gather3x 58.2 | 18 256 993 | 259 414 | 64 854 | 16 214 |
| dense, KV-int8 | stream | 18 256 993 | 1 556 480 | – | – |
| MoE serial | stream | 3 207 719 | **136 736** | 34 184 | 8 546 |
| MoE ping-pong | stream | 2 584 583 | 110 173 | – | – |
| MoE serial | gather3x | 3 207 719 | 45 579 | 11 395 | 2 849 |

So at B = 1 dense is weights-bound at every feasible L on the stream branch (L* > L_max = 551 253 with f16 KV;
with KV-int8 L* = 1.56M > 1M) and KV-bound only on the gather3x branch beyond 259k; MoE is weights-bound at
4k/32k and KV-bound at 1M under every branch (128k sits 4 % under L* on the serial-stream branch and above it
on every other). Batching divides L* by B.

**T6 — softmax crossover is L-independent.** SM ≥ KV ⟺ B·t·H_q·c_E·10/3456 ≥ kv_tok·B·10/G: L and B cancel,
leaving t ≥ t* = ⌈kv_tok · 3456 / (G · H_q · c_E)⌉ (`[F4-*-tsm-*]`):

| shape | native (c_E = 4) stream / gather3x | poly (c_E = 16) stream / gather3x | KV-int8 native / poly (stream) |
|---|---|---|---|
| dense (H_q = 128) | 16 / 48 | **4** / 12 | 8 / 2 |
| MoE (H_q = 32) | 64 / 191 | 16 / 48 | – |

Consequence: a dense verify batch of t = 4 is softmax-bound **iff** there is no exp instruction (poly) and the
KV stream runs at the stream rate — and then only marginally (SM 776 722 vs KV 768 715 ns per layer at 32k:
+1 %); with KV-int8 the poly branch binds already at t = 2. The E-exp measurement (PROBLEM-3) therefore matters
for dense spec decode and for nothing else in this plan.

**T-MMA — matrix-unit attention bound.** Calls per layer = B·2·H_kv·(L/16)·⌈t·g/16⌉; per-layer MMA time /
KV time = 8.0 % (dense t = 1), 32.0 % (t = 4), **127.9 % (t = 16, a single-sequence 16-row verify: MMA-bound)**;
MoE (g = 4): 8.0 % / 8.0 % / 32.0 % (`[F4-*-mma-*]`). The plan never runs a single sequence at t > 8 (§6).

**T4 — memory boundary** (§1.7): L_max values; dense f16 1M infeasible by 515.3 − 282.3 = 233.0 GB fleet-wide.

**T8 — bounce boundary** (§2.2): λ ≥ 918 µs (MoE) / 16.4 ms (dense) for a 10 % share.

**T2 — the layer-split ceiling.** For any partition under Π = 1, T_step ≥ Σ_layers T_gemm = bytes streamed per
token / R_gemm: tokens/s ≤ 174.6 / 384.6 GB = 0.454 fleet-wide (dense), 0.113 per card. No layer→die map, no
die count, no exchange schedule beats it; the "+2 % at 2 dies" measurement is this theorem observed.

### 4.3 Round 3 — regime map and crossovers on the measured constants (`[R3-regime]`, `[R3-Lkv-*]`, `[R3-Gstar-*]`, `[R3-tstar-*]`)

**Binding term per (shape, L, rows), primary branch** (share of the step; attention share in brackets):

| shape | L | rows = 1 (t = 1) | rows = 4 (verify, k = 3) | rows = 16 (B = 16, t = 1) |
|---|---|---|---|---|
| dense | 4k | W 95.6 % [attn 0.6] | W 91.2 % [2.4] | W 87.5 % [9.0] |
| dense | 32k | W 92.3 % [4.1] | W 79.2 % [**15.3**, vector-bound rows] | W 57.2 % [40.5] |
| dense | 128k | W 82.4 % [14.3] | W 54.5 % [41.7] | **MEM** |
| dense | 1M | **MEM** f16 → **ATTN (vector) 50 %** on KV-int8, W on the fixed-shift chain | MEM → ATTN (vector) 85 % | MEM |
| MoE | 4k | W 77.8 % [2.8] — launch 15.1 % | W 78.6 % | W 94.6 % |
| MoE | 32k | W 66.9 % [16.4] — launch 13.0 %, quant 3.5 % | W 75.2 % | W 77.5 % [21.2] |
| MoE | 128k | W 45.2 % [**43.5**] — a tie: W by 0.5 % per layer at 256 KiB, ATTN at 16 KiB, **ATTN at every page size on the direct-path kernel**; proof: with DESIGN-3 round 4's P bounce at legs ≥ 1 (the planner reads 2) ATTN per layer at every G ≤ 174.6 on both kernels (T3r_moe128k_tie) | W 65.6 % | MEM |
| MoE | 1M | **ATTN (KV) 86.0 %** | ATTN 62.3 % | MEM |

Host bounce ≤ 0.18 % everywhere (MoE 4k; 0.16 % at 32k — proof: first written "≤ 0.16 %", T3r_bounce_share_max); the quant pass 0.9 % / 3.5 %; no imbalance at Π = 1 (T1). The regime changes inside the
table are the MoE KV crossover just above 128k and the dense memory wall between 551k and 1M, exactly as in round 2 — plus
two new ones the measurements introduced: **the dense verify batch is softmax-bound (rows ≥ 32) and the dense KV-int8 cell
is softmax-bound at t = 1**.

**T5′ — KV-bandwidth crossover on the block model (T3r_Lstar_kv, an iff over every L).** Per layer, attention ≥ T_w iff
nb(L)·blk + fixed ≥ T_w with nb = ⌈16⌊L/16⌋/512⌉ and blk the per-block cost of the binding engine (12 394 ns of KV at 169.2;
9 276 ns of vector chain on KV-int8), so **L* = (nb* − 1)·512 + 16 with nb* = ⌈(T_w − 18 820)/blk⌉** (`[R3-Lkv-*]`; proof: an iff over EVERY L, T3r_Lstar_* — L* is the length from which every longer context is
attention-bound, but the L mod 16 vector tail (up to 3.9 µs) makes the t = 1 attention non-monotone, so in 13 of the 40 cells
some lengths in the block below L* are already attention-bound: attention-bound ⟺ L ≥ L* ∨ (L ≥ L* − 512 ∧ L mod 16 ≥ τ);
first attention-bound lengths: MoE anchored 256 KiB 131 103, dense KV-int8 1 006 102, dense fixed-shift 753 175, MoE ping-pong
105 489 — `[R3P-Lkv-*]`):

| shape, expert regime | 256 KiB (primary) | 64 KiB shuffled | 16 KiB | 174.6 ceiling | gather3x what-if | fixed-shift chain, 256 KiB |
|---|---|---|---|---|---|---|
| dense (T_w = 18 256 993) | **753 168** | 743 440 | 684 560 | 777 232 (round 2: 778 240 on the KV-only model) | 259 088 | 753 680 |
| dense, KV-int8 | **1 006 608 at every G** (vector-bound: the chain, not the stream, is the per-block cost) | 1 006 608 | 1 006 608 | 1 006 608 | 518 160 | 1 507 344 (DDR-bound again) |
| MoE, anchored serial (3 207 719) | **131 600** | 129 552 | 119 312 | 135 696 (round 2: 136 736) | 45 072 | 131 600 |
| MoE, direct path (2 641 199) | **108 048** | 106 512 | 98 320 | 111 632 | 36 880 | – |
| MoE, ping-pong (2 584 583) | 106 000 | 104 464 | 96 272 | 109 072 | 36 368 | – |

Reading: at B = 1 dense is weights-bound at every feasible f16-KV length (L* > L_max = 551 253 on every measured page size)
and the KV-int8 1M cell is attention-bound (1M > 1 006 608) on the chain as specified but weights-bound on the fixed-shift
chain (L* = 1 507 344). **MoE at 128k = 131 072 sits 528 tokens under L* on the primary page size (31 under the first attention-bound length, 131 103
with a 15-token tail — proof) and 1 520 tokens above it
at 64 KiB** — the tie DESIGN-3 §1.4 flagged; on the direct-path kernel L* falls to 108 048 and the cell is attention-bound
at every page size (by 20.8 % at 256 KiB). Batching divides L* by B as before.

**E21 for the fleet, re-instantiated (T3r_fleet_G, an iff over G):** the t = 1 cell is attention-bound iff G ≤ G* =
512·4 096·10/⌈(T_w − 18 820)/nb⌉ tenths — dense 32k / 128k: 7.3 / 29.4 GB/s; MoE 32k 42.0 (51.1 on the direct path); **MoE 128k
168.3 on the anchored kernel (256 KiB's 169.2 clears it by 0.9 GB/s, 64 KiB's 167.0 does not) and 204.7 on the direct path
(nothing clears it)** — each an iff over every G > 0 (proof: T3r_fleet_G_*). **Proof correction: at 1M there is no G line — the
vector chain alone (2 048 × 9 276 + 18 820 = 19.0 ms per layer) exceeds the dense and every MoE weight time, so the dense and MoE
1M cells are attention-bound at EVERY G** (T3r_fleet_G_1M_everyG; the formula's 235.4 / 1 346.0 GB/s first written here are
not iff lines — above them the block turns vector-bound and stays attention-bound; the fixed-shift chain keeps a real dense-1M
line at 235.3). HW-MAP's "stays
stream-bound at 64 KiB by 0.7 GB/s" has the inequality backwards (DESIGN-3 §1.4): 167.0 ≤ 167.7 was the attention-bound side.

**T6′ — softmax crossover (T3r_tstar).** On the block model the vector chain scales with the fragment count mt and the
block with the KV bytes, so the crossover is a row count (L cancels, as in round 2): vector ≥ KV per block from **mt = 2
on the chain as specified (rows* = 32) and mt = 3 on the fixed-shift chain (rows* = 48)** — dense (g = 16) **t ≥ 2 / t ≥ 3**,
MoE (g = 4) t ≥ 5 / t ≥ 9; on KV-int8 the stream halves and the line moves to mt = 1 (dense t = 1, MoE t = 1) on the chain as
specified, mt = 2 (dense t = 2, MoE t = 5) on the fixed-shift chain. Round 2's t* = 16 (native) / 4 (poly) for dense and 64 /
16 for MoE rested on a 4-lane-op softmax; the measured chain costs 9 276 ns per fragment — 75 % of a block — so the second
fragment already exceeds the stream (25.5 lane-equivalents per score of elementwise work plus the per-call items: 16
reduce-max calls, the 20-call shift reel and the merge, 48 % of the chain). The matrix-unit bound (T-MMA, 8 %·mt of the stream) is unchanged.

**T8′ (bounce), T2 (ceiling), T4 (memory):** T8 is re-instantiated in §2.4; T2 and T4 are unchanged (no λ, G or c_q term).

### 4.4 Round 5 — the MoE-128k tie on the measured kernel (`[R5-moe-128k-*]`; T5r_moe128k_tie_measured, T5r_moe128k_everyG, T5r_moe128k_cells)

**T3r_moe128k_tie, restated with the MEASURED legs = 2 and the MEASURED kernel.** The round-3 proof session proved the tie legs-conditional
(attention-bound iff G ≤ 168.3 / 178.9 / 189.4 at legs 0 / 1 / 2, anchored; 204.7 / 217.5 / 230.3 direct) and the planner read legs = 2.
Session 3 measured both inputs. The verdict, per layer against the anchored weight layer (3 207 719 ns) and the direct-path one (2 641 199):

| reading | attention per layer | anchored | direct path | step at Π = 1: ATTN vs W |
|---|---|---|---|---|
| guarded (M) | 5 852 900 ns | **ATTN-bound by 82.5 %** | ATTN by 121.6 % | 163.88 vs 92.82 ms — ATTN |
| unguarded (D) | 3 553 700 | ATTN by 10.8 % | ATTN by 34.5 % | 99.50 vs 92.82 — ATTN |
| fused (D, target) | 3 573 700 | ATTN by 11.4 % | ATTN by 35.3 % | 100.06 vs 92.82 — ATTN |

**The lines, as iffs over every G > 0 (T5r_moe128k_tie_measured):** with the measured bounce (204 000 ns per layer at 128k: 51 µs at 32k
scaled per block) and NO chain or fixed cost at all, the layer is attention-bound iff G ≤ **178.7** (anchored) / **220.2** (direct) — the
round-4 legs-2 lines (189.4 / 230.3) move down because the measured bounce is 51.4 % of the modelled roof charge, but both stay above the
174.6 ceiling: **attention-bound at every G ≤ 174.6 on both expert kernels, whatever the chain costs** (T5r_moe128k_everyG). On the
effective KV rate (all costs folded in) the lines are G_eff ≤ **167.3 / 203.2** — every reading (91.7 / 151.1 / 150.2 GB/s at 128k) is
below them. The planner's question "which side binds at MoE 128k" is closed: attention, by a margin no remaining unknown can close — guard
fusion leaves 11.4 %, and even the overlapped floor (the K+V stream phase + the measured bounce = 3 287 200 ns, what a perfect E40 would
reach) exceeds the layer by 2.5 % (T5r_fleet_moe_128k_cells).

**T5′ / R12 / R13 on the measured kernel.** The L-crossovers of §4.3 (L* per G) were properties of the modelled block; on the measured
kernel the MoE cells are attention-bound at 128k and 1M and weights-bound at 4k and 32k on every reading (§3.6), the dense cells
weights-bound at 4k–128k; the dense 1M cell exists only on KV-int8 (bounded above by 0.034). The G* iff lines of R13 are superseded by the
effective-rate lines above (G_eff ≤ 167.3 / 203.2 at MoE 128k).

### 4.5 Round 6 — the MoE-128k cell on the measured deferred kernel (`[R6-moe-128k]`; T6r_moe128k6, T6r_moe128k6_eff)

§4.4's restated tie, evaluated at the measured cell: **3 618 800 ns per layer — attention-bound by 12.8 % against the anchored weight layer
(3 207 719 ns) and by 37.0 % against the direct-path layer (2 641 199)**; the step at Π = 1 carries 101.32 ms of attention against 92.82 ms
of weights. The measured rate, 148.4 GB/s, is under both effective-rate lines of T5r_moe128k_tie_measured (G_eff ≤ 167.3 / 203.2 —
instantiated at G = 148.4 in T6r_moe128k6_eff), and E40's floor (3 287 200 ns, a perfect overlap) still exceeds the anchored layer by 2.5 %.
The cell stays attention-bound at every reading: it is trip-free here, and the trips only add (≤ 0.22 % if the premise transfers and a
re-run costs at most one step, as measured at 32k and 1M). Round 5's fused reading (3 573 700 ns, +11.4 %) was 1.3 % optimistic. MoE 1M is
attention-bound (87.4 % of the step), MoE 32k weights-bound (18.6 %), every dense cell weights-bound.

---

## 5. Sensitivity / what-if theorems (each a bound, `[F5]`, L = 32k, B = 1, t = 1, primary branch)

| what-if | bound | dense | MoE |
|---|---|---|---|
| **P2P link at any rate X** | saving ≤ T_x (the whole exchange) — at Π = 1 nothing else is on the link | ≤ 1.497 ms = **0.06 %** | ≤ 1.480 ms = **1.1 %** |
| **D2D 10.7 → 50 GB/s** | per-token traffic is 0 B (KV never moves) → 0 %; only a re-partition move changes: one die's KV at 128k (dense 8.0 GB, MoE 2.1 GB) | 753 → 161 ms per move | 201 → 43 ms |
| **tensor-split worked** (8 dies stream each layer concurrently, 2 host all-reduces per layer of a rows × d f32 partial: per card the trunk carries both dies' partials out and both results in + 2λ = 191 µs (dense d = 16384) / 184 µs (MoE)) | T_TS = Σ(W + KV)/8 + T_head/8 + T_launch + 2·n_L·T_red | 398.52 ms = 273.85 + 11.53 + 1.50 (lm_head/8) + 65.70 + 45.93 → **0.627 tok/s/card (5.9×)**; λ = 10 µs: 359.64; launches pipelined: 332.82 | 43.02 ms = 11.61 + 2.69 + 0.37 (lm_head/8) + 18.01 + 10.32 → **5.810 (3.1×)**, launch-floor-bound (42 %); λ 10: 33.95; pipelined: 25.00 |
| **pipelined sequences Π = 8** (the runtime keeps every die busy on a different sequence; per-sequence latency unchanged) | fleet tokens/s = 1 / max_pos block(pos); block = n_pos·(T_gemm + T_attn + launches) + extras + its two bounce halves | blocks 293.66–305.99 ms (pos 7 carries lm_head) → 3.268 fleet = **0.817/card (7.7×)** | blocks 14.02 (3-layer) / 18.63 ms (4-layer) → 53.66 fleet = **13.414/card (7.1×)**; a sub-layer split (7 units per die) would reach 8× |
| **tensor-split + P2P** | the reductions leave the host: T_red → 8 · rows·d·4 B / X + λ_p2p; at X = 50 GB/s, λ_p2p = 10 µs: 20 µs (dense) / 13 µs (MoE) per reduction instead of 191 / 184 (`[F5-*-tsplit-p2p]`) | 357.50 ms → 0.699 (6.6×) | 33.41 ms → 7.482 (4.0×), launch-bound (54 %) |

Reading: on this runtime the only upgrade that pays is **pipelining independent sequences** (×7–8 throughput,
zero link bandwidth, zero kernel change — the exchange table of §2 at 8 tokens in flight uses 0.2 % of a
trunk). Tensor-split would be the latency lever (one sequence 5.9× faster for dense) but it needs the
runtime to stop faulting on split ops **and** converts the launch floor into the MoE wall (18 of 43 ms).
P2P is worth less than the measurement noise of this plan unless tensor-split exists too. D2D is irrelevant
to steady-state decode.

### 5′ Round 3 — the what-ifs re-derived, and the three runtime-free variants (`[R3-whatif-*]`, `[R3-mega-*]`, `[R3-inst-*]`)

| what-if (L = 32k, B = 1, t = 1, primary branch) | bound | dense | MoE |
|---|---|---|---|
| **P2P link at any rate X** | saving ≤ T_x = Σbw + 16 λ at the measured λ | ≤ 236 µs = **0.01 %** | ≤ 220 µs = **0.16 %** |
| **D2D 10.7 → 50 GB/s** | per-token traffic 0 B; one die's KV at 128k moves in 753 → 161 ms (dense) / 201 → 43 (MoE) | unchanged | unchanged |
| **tensor-split worked** (8 dies stream each layer; 2 host all-reduces per layer at the measured λ: 34 / 27 µs each) | T_TS = Σ(W + ATTN)/8 + T_head/8 + T_launch + quant + 2·n_L·T_red | 382.32 ms = 273.85 + 12.18 + 1.50 + 65.70 + 20.97 + 8.11 → **0.653 (6.2×)**, launch 17 % + quant 5 % | 39.24 = 11.61 + 2.84 + 0.37 + 18.01 + 4.89 + 1.49 → **6.369 (3.5×)**, launch 46 % + quant 12 % |
| **Π = 8 sequence pipelining** (H4) | fleet tokens/s = 1/max_pos block(pos); Σ blocks + λ = T_step exactly (T3r_pipelining_decomposition) | blocks 296.86 … 309.10 ms → 3.235 fleet = **0.808/card (7.7×)**; balance loss 3.5 % (the lm_head die) | blocks 14.51 / 19.35 ms (3- / 4-layer dies), 17.72 (lm_head) → 51.675 fleet = **12.918/card (7.1×)**; loss 10.4 % vs a balanced split |

The reductions that made tensor-split launch-bound in round 2 (191 / 184 µs each at λ = 91) are 34 / 27 µs at the measured
bounce: the what-if is now bounded by the launch floor and the quant pass, and P2P is worth less than the rounding of this
table. The three variants that need **no runtime change** (each a measured-rate model with one term changed; gates in §8):

| variant — what changes in the step | gate | dense 32k | MoE 32k |
|---|---|---|---|
| **V1 — MoE expert kernel on the DDR→L0B direct path** (ALT-1): T_slab 122 979 → 99 374 (A lift serialised with the barrier cadence) / 96 089 (overlapped); every rate measured, the A-L0LOAD interleave is the one unmeasured choreography (**audit, #25:** x_q rides the production 2 × 32 KiB legs at 32-KiB-granular offsets, never one 64 KiB block — a single large block zeroes A rows ≥ 2, silent at t = 1 and wrong at B = 16 / verify t = 4; E29 checks rows 0–15 with prime-period patterns) | E29 | – | **2.035 (+12.9 %)** / 2.072 (+15.0 %) |
| **V2 — per-layer persistent megakernel** (ALT-3): one launch per layer instead of 6 / 7 (saves 54.60 / 15.28 ms per token), two DDR K-split reductions per layer (+1.84 / +0.10 ms) and 480 / 140 flag rounds at c_sync each; **pays iff c_sync ≤ 109.9 µs (dense) / 108.4 µs (MoE)** [**audit (#29): the primary reading is c_sync = 20 µs — V2 MoE 1.979, V3 + V2 4.098 (`[PA-mega-*]`, T6f_mega_20us); (#31 / #26 / #30 / #22): the consumer's checksum compare and an in-kernel top-k are fresh-reduction readbacks — compare on the vector side, read once per layer, re-run on a mismatch, keep the router behind a launch boundary or route through the deterministic dispatch; polls in bounded nests; every nest resets the B ping-pong; the quantizer uses Duplicate + Mul or the measured pass**] (T3r_mega_threshold, an iff; proof: the dense line is a tie — at 109 903 ns the step is unchanged, strictly better iff ≤ 109 902) | E31 (c_sync), E32 (watchdog) | 0.107 / 0.106 / 0.106 at c_sync 2 / 5 / 20 µs (+2.8 / +1.9 / +1.9 %) | 2.019 / 2.012 / 1.979 (+12.0 / +11.6 / +9.8 %); with V1: **2.307 (+28.0 %)** |
| **V3 — two 4-die instances with the minimal int4 tier** (§1.8) | H10, H11 (+ E29 for the hot tier) | **0.155 (+49.0 %)**; spec 0.349 / 0.374 | **3.720 (+106.4 %)** (3.391 on the anchored kernel); with V2 4.170 (+131 %), with V1-overlapped and V2 4.234 |

Reading: on this runtime the only upgrade that still pays is Π = 8 (×7–8, zero link bandwidth, zero kernel change); V3 is its
Π = 1 substitute (×1.5 / ×2.1) and is undone if H4 passes (Π = 8 of a single instance is 5.2× / 3.4× the two-instance cells,
`[R3-inst-combo-*]`); V1 and V2 compose with either (they shorten every die's block). Tensor-split would be the latency
lever (6.2× for one dense sequence) but the runtime faults on it. D2D is irrelevant to steady-state decode.

---

## 6. Draft model placement and the verify-batch schedule

### 6.1 Cost of a draft token (`[F6-draft]`)
| component | value | origin |
|---|---|---|
| draft weights 1 GB at R_gemm | 5 727 µs | M |
| draft window KV 201 MB at R_gemm | 1 153 µs | M + A (4k window) |
| 121 launches × 91 µs | 11 011 µs | M (0 if H6 shows pipelining) |
| logits D2H 513 KB at 27.3 + 2λ | 19 µs + 182 µs | M + A |
| **per draft token** | **18.1 ms** (7.1 ms pipelined) | |
| **per verify step, k = 3** | **54.27 ms** (21.24 pipelined) | |

The launch floor is 61 % of the draft's cost: a draft model on this part is launch-bound, not bandwidth-bound,
so its layer count matters more than its byte count (a 0.5 GB draft with the same 24 layers saves 2.9 ms of
18.1; a 12-layer 1 GB draft saves 5.5).

### 6.2 Placement
- **Dense: chain position 1 (c0.d0)**, 49.0 GB with the draft; the binding die for L_max is position 0 (the
  embedding table, 49.9 GB), so the draft costs zero context (`[F1-dense-draftfree]` = 551 253). Its logits
  leave on a 27.3 GB/s link; its ids go to position 0 over 13.9 GB/s (4 B). At Π = 1 the draft runs while
  the whole chain is idle (the three draft steps precede the verify step), so there is **no contention**: its
  cost is purely additive (54.27 ms). At Π = 8 the draft die loses 6.9 ms of DDR time per draft token to a
  running block (`[F6-contention]`) — then the draft belongs on the die with the smallest block (position 1
  is 293.76 ms like every middle die; nothing to gain, and the sub-layer-balanced MoE layout would give it a
  3-layer die).
- **MoE: reserved on position 7 (c3.d0, 40.5 GB with it), not deployed by default** (T12 below).
- The draft's own KV: a 4k sliding window (A — a model-quality choice outside HW-MAP; a full-context draft
  KV would cost 49 152 B per token = 10 % of the main model's, and 51.5 GB at 1M, which no die has).

### 6.3 Verify-batch schedule and the spec-decode theorem
Per verify step: 3 draft steps on the draft die (ids bounce to the host each), then one chain pass with
rows = t = 4 (the four candidate positions as 4 rows of every GEMM: free under the flat m-curve; the KV stream
is read once; softmax ×4; MMA ×4 fragments = 32 % of the KV time, T-MMA), logits for 4 positions D2H (75 µs),
host acceptance test, ids back. Tokens per step τ(α, k) = Σ_{i=0..k} α^i (`[F6-tau]`): α = 0.5 / 0.7 / 0.9 →
1.875 / 2.533 / 3.439 at k = 3.

| shape, L = 32k | t = 1 | spec k = 3: α 0.5 / 0.7 / 0.9 | best k at α = 0.7 (rows = k+1 ≤ 16) |
|---|---|---|---|
| dense | 0.105 | 0.193 / **0.262** / 0.355 (1.83× / 2.48× / 3.36×) | k = 7: 0.315 (`[F6-dense-k7]`; 0.571 at α = 0.9) |
| MoE, uniform routing | 1.867 | 1.074 / **1.451** / 1.971 (0.5× / 0.7× / 1.0×) | k = 1: 1.811 — still a loss |
| MoE, Zipf(1.5) routing | 1.867 | – / 2.028 / – (1.09×) | – |

**T12 (spec decode on MoE).** Under uniform routing D(t) = min(8t, 256), so the expert stream of a verify
step is (k+1)× that of a decode step: T(k+1) ≥ (k+1)·W_exp(1) + (everything else), while tokens per step
τ(α, k) < k+1 for every α < 1. Hence tokens/s(spec) < tokens/s(t = 1) whenever the expert stream dominates
— at 32k the break-even is τ(α, 3) ≥ T₄/T₁ = 3.2584 (`[F6-moe-uniform-t4]`), i.e. α ≥ 0.865 (α = 0.864 loses, 0.865 gains; T_spec_moe_loss_exact proves both directions for every α); under Zipf(1.0) (D(4) = 25) it is τ ≥ 2.7182, α ≥ 0.747; under Zipf(1.5) (D(4) = 20) τ ≥ 2.3322, α ≥ 0.647 (α = 0.646 ties at 1.867 in thousandths and loses by 0.01 % exactly). Before any draft cost is counted, T₄ ≥ 4·E₁ + (T₁ − E₁) with E₁ = 61.7 % of T₁ makes every τ < 2.852 a loss (T_spec_moe_mechanism). On dense the verify rows are free (W is flat in rows), so spec decode
is a pure gain: ×2.475 at α = 0.7 (every α ≥ 0.024 gains) and ×3.0 with k = 7.

**Does spec decode change the partition?** Dense: no — 1.2 GB on a non-binding die, same boundaries, same
KV policy, L_max unchanged; the only schedule change is that each step carries 4 rows (bounce bytes ×4,
still ≤ 0.07 %). MoE: it changes the *decision*, not the partition: spec decode is off unless H9 measures
routing skew at Zipf(1.5)-class or better and the fleet-measured α clears 0.647; the reservation on position 7
costs 1.2 GB of a 42.7 GB die. The draft's own layers never contend with the main model's dies at Π = 1.

### 6.4 Round 3 — the draft and the verify batch on the measured constants (`[R3-draft]`, `[R3-spec-*]`)

**Draft token:** 5 727 (1 GB at 174.6) + 1 153 (window KV) + 11 011 (121 launches) + **4 195 (24 layers × 4 quant passes
at 43.7 µs)** + 19 (logits) + 24 (2 λ) = **22.13 ms** (round 2: 18.09 — the measured bounce takes 0.16 ms out, the measured
quant pass puts 4.2 ms in); verify step k = 3: **66.38 ms** (33.35 with pipelined launches, 41.34 under the megakernel with
24 launches at c_sync 5 µs, 53.80 without the quant pass). The launch floor is 50 % of the draft, the quant pass 19 %.

**Dense (`[R3-spec-dense-*]`):** the verify batch is 4 rows = 64 attention rows at g = 16 = four fragments on 256-token
blocks: the attention of a verify step is **426.70 ms** at 32k on the chain as specified (191.20 on the fixed-shift chain)
against 97.44 at t = 1 — the only place in this plan where DESIGN-3's softmax finding bites (§4.3, T6′).

| L = 32k | t = 1 | spec k = 3: α 0.5 / 0.7 / 0.9 | gain at α = 0.7 | best k at α = 0.7 (0.9) | gain for every α ≥ |
|---|---|---|---|---|---|
| dense, chain as specified | 0.104 | 0.168 / **0.227** / 0.308 | 2.172× | k = 7 (rows 8, two passes): 0.238 (0.432) | 0.144 (τ > T₄/T₁ = 1.1657) |
| dense, fixed-shift chain (E35) | 0.104 | 0.184 / **0.248** / 0.337 | 2.372× | k = 7: 0.277 (0.503) | 0.064 (1.0675) |
| MoE uniform, anchored kernel | 1.802 | 1.034 / **1.397** / 1.897 | 0.775× | k = 1: 1.745 — still a loss | loss iff α ≤ **0.866** |
| MoE Zipf(1.0) / Zipf(1.5), anchored | 1.802 | – / 1.663 / – ; – / 1.924 / – | 0.92× / 1.07× | | loss iff α ≤ 0.752 / 0.657 |
| MoE uniform / Zipf(1.0) / Zipf(1.5), direct-path kernel | 2.035 | 1.625 / 1.911 / 2.187 at α = 0.7 | | | loss iff α ≤ 0.847 / 0.741 / 0.652 |

**T12′ (T3r_spec_moe_loss, both directions for every α):** the mechanism is unchanged — D(4) = 4·D(1) under uniform routing
multiplies the expert stream (E₁ = 82.64 ms = 59.6 % of T₁), so T₄ ≥ 4 E₁ + (T₁ − E₁) = 386.61 ms makes every τ < 2.787 a
loss before the draft is counted (round 2: 2.852); with the draft the break-even is τ(α, 3) ≥ T₄/T₁ = 3.2667, **α ≥ 0.867**
(proof: 0.866 gives 1.800 < 1.802, 0.867 gives 1.803; T3r_spec_moe_cells). Round 2 said α ≤ 0.864: the line moved by 0.002 because the verify step
carries the draft's quant passes. **T_spec_moe_loss survives.** On dense the gain shrinks from 2.475× to **2.172×** (the
vector-bound verify rows) and the all-α statement weakens from "every α ≥ 0.024" to **"every α ≥ 0.144"** (0.064 on the
fixed-shift chain); k = 7 is now the best k at α = 0.7 by only 5 % (two attention passes) — ship k = 3 until E35 lands.

**Does spec decode change the partition?** Still no for dense (1.2 GB on a non-binding die; bounce bytes × 4 = 0.02 %);
the 64-row verify batch changes the *attention kernel's* configuration (mt = 4, 256-token blocks, L0C full) and makes E35
a dense-fleet item. MoE: off by default (the thresholds are a shade higher than round 2's); on only if H9 shows Zipf(1.5)-
class skew and α ≥ 0.658 (0.653 on the direct path). On two instances the dense spec cell is 0.349 / 0.374 (`[R3-inst-dense-32k-spec-*]`).

### 6.5 Round 5 — spec decode on the measured verify kernel (`[R5-spec-*]`; T5r_spec, T5r_spec_steps, T5r_spec_thresholds)

The verify kernel is measured on the headline shape only (g = 8: t = 4 is rows 32 at mt 2, t = 16 is rows 128 in two mt-4 passes), so the
fleet shapes take it by fragment count — DERIVED transfers, not measurements: **dense t = 4 (rows 64, one mt-4 pass) = half of the measured
t = 16 cell = 5 370 850 ns per layer at 32k; MoE t = 4 (rows 16, one mt-1 fragment) = the measured t = 1 cell** (1 513 600 guarded; the
unguarded / fused readings carry over the same way). The guarded verify kernel is 4.1× the round-4 lazy-T verify model on dense (5.37 vs
1.30 ms per layer): the multi-fragment kernel scales with fragments (DESIGN-3 §6.0).

| k = 3, α = 0.7, 32k | guarded verify (M attention) | round 4 | t = 1 guarded | threshold (round 3) |
|---|---|---|---|---|
| dense | 3 000.80 ms → **0.211** | 0.252 | 0.101 | beats t = 1 iff **α ≥ 0.179** (0.144) |
| MoE (uniform, anchored) | 472.72 ms → **1.339** | 1.389 | 1.578 | **loses iff α ≤ 0.807** guarded / 0.854 unguarded / 0.853 fused (0.866) |

**T_spec_moe_loss survives; its line moves** (T5r_spec_thresholds, iffs over every α ∈ [0, 1] in thousandths, `decide +kernel`): the MoE
verify batch still multiplies the active-expert bytes, so at α = 0.7 spec decode loses on every reading; the measured attention, the same
per layer in the verify and the t = 1 step, shrinks the ratio T₄ / T₁ (472.72 / 158.33 ms guarded) and so the loss line (0.866 → 0.807).
Dense spec still pays: 0.211 against 0.101 (2.09×); its breakeven rises 0.144 → 0.179. The unguarded verify kernel is UNMEASURED — the
dense guarded-verify cell is the only dense spec number this round can quote.

### 6.6 Round 6 — spec decode at the fused G (`[R6-spec-*]`; T6r_spec6_steps, T6r_spec6_thresholds, T6r_spec_dense_form, T6r_spec_dense_line, T6r_spec_dense_cells, T6r_spec_dense_thresholds)

**MoE** (verify kernel = the t = 1 kernel — rows 16 = one mt-1 fragment, round 5's D transfer, now applied to the measured deferred cell):
at α = 0.7 the verify batch gives 456.81 ms → 1.386 against 142.43 ms → 1.755 at t = 1 — spec decode loses, and **T_spec_moe_loss survives
with its line moved to α ≤ 0.854 on every deferred reading** (trip-free and both amortized ends; ∀ α ∈ [0, 1] in thousandths, `decide
+kernel`): **0.807** (round 5, the legacy scan) **→ 0.854**. It lands where round 5's unguarded reading put it (0.854; fused 0.853)
because the measured cell lies between those two readings.

**Dense** (the deferred kernel's verify cells at t ≥ 4 are UNMEASURED — E41): the verify step is affine in its per-layer attention v,
**T₄(v) = 2 356 301 528 + 120·v ns** (∀ v, T6r_spec_dense_form), and at α = 0.7 spec decode beats t = 1 (2 403.24 ms) **iff v ≤ 31 092 727
ns per layer** (∀ v, T6r_spec_dense_line) — 32.8× the t = 1 cell, so the dense spec decision holds for any plausible verify kernel. The cell
and the breakeven move with v:

| reading of v (dense t = 4 = rows 64, one mt-4 pass) | v per layer | spec at α = 0.7 (t = 1: 0.104) | beats t = 1 iff |
|---|---|---|---|
| fragment-serial: 4 × the t = 1 deferred cell (D; round 5's rule, its conservative end) | 3 782 000 | 2 810.14 ms → **0.225** | **α ≥ 0.146** |
| ratio-scaled: the legacy t = 16 half × deferred / legacy at t = 1 (D) | 3 355 007 | 2 758.90 → 0.229 | α ≥ 0.130 |
| the legacy verify kernel: half the t = 16 cell (MEASURED, session 3) | 5 370 850 | 3 000.80 → 0.211 | α ≥ 0.201 |

Until E41 measures the deferred verify, DESIGN-4 quotes the fragment-serial reading (0.225, α ≥ 0.146) as the dense spec number and the
legacy verify (0.211, α ≥ 0.201) as its measured floor; round 5's 0.179 paired the legacy verify with the legacy t = 1 kernel and is
superseded (the t = 1 cell got faster, so the breakeven on the legacy verify rises to 0.201).

---

## 7. Rollout plan: 1 card → 2 cards → 4 cards without re-partitioning

**T15 (block invariance).** block(pos) depends only on (layers on pos, extras on pos, L): the per-die blocks
of the final layout are therefore measurable on a single card holding chain positions 0 and 1 with exactly
the final blocks, and every later stage adds positions without changing the ones already proven.

| stage | positions | dense layers | MoE layers | what it proves | predicted step at 4k / 32k / 128k (`[F7]`) |
|---|---|---|---|---|---|
| **1 card** (c0.d1 → c0.d0) | 0, 1 | 0–29 (15 + 15, embed on pos 0, draft on pos 1) | 0–6 (4 + 3) | layer-split through the runtime; the d1 → d0 hop (hop 0) and the d0 → host logits path; KV growth to 128k+ on a die holding its final 47.8–49.9 GB of weights (`[F8-H5]`: 61 440 B/token, 8.0 GB at 128k, room to 551k); the per-block timings that T15 extrapolates | dense 567.24 / 587.42 / 656.61 ms; MoE 27.85 / 32.56 / 48.71 ms |
| **2 cards** | 0–3 | 0–59 | 0–13 | the inter-card hop (hop 1: d0 → d1', H2D at 13.9, the slowest), trunk sharing (H2), two boundaries of each type | dense 1134.59 / 1174.95 / 1313.31; MoE 55.81 / 65.22 / 97.51 |
| **4 cards** | 0–7 | all | all | the full chain; lm_head on pos 7 | dense 2281.51 / 2362.22 / 2638.96; MoE 114.92 / 133.75 / 198.32 |

Re-partition steps: **none for the layer blocks** (the 15-layer / 4-3 blocks are final from stage 1). The
extras move: at stages 1 and 2 the chain ends on position 1 / 3, which temporarily hosts the stage's logits
exit (the prefix model has no lm_head: correctness is judged per layer, below); at stage 3 lm_head loads on
position 7. The draft is loaded at its final position from stage 1. KV of a prefix stage is not carried
forward (a stage's context is regenerated); if a live context must survive a stage change, moving one die's
KV costs 753 ms (dense, 128k) / 201 ms (MoE) at the measured 10.7 GB/s D2D rate (`[F5-*-d2d]`).

Correctness at every stage without a whole-model host reference (386.7 GB of int8 on a host is not
assumed): teacher-forced tokens, and a **per-layer host oracle** — the host holds one layer's weights at a time
(3.2 GB dense / 12.9 GB MoE), recomputes layer ℓ's output from the die's recorded input (f32), and compares
(relerr ≤ 10⁻³ class, as DESIGN.md E10); differencing: the same layer with a second weight set must change
the output. MoE stage 1 additionally checks per-core chunk counts = D × 32 per slab (DESIGN-2 E15) through the
runtime's profiler.

Scaling arithmetic the stages verify: T_full = Σ_pos block(pos) + λ (the id-entry latency is the only term outside the blocks, T_pipelining_decomposition). 4 × (stage-1 step) already carries 12 of the 16 latencies, so the 4-card prediction is **4 × (stage-1 step) + T_head + 2·T_launch (lm_head's launches) + 4λ + (3 hops at 13.9 − 1 at 27.3 + logits)** = 4 × 587.43 + 12.04 + 0.18 + 0.36 + 0.03 = 2362.32 ms at 32k — exactly the direct 2362.32 (T_rollout_identity; MoE: 4 × 32.57 + 3.57 = 133.85). Round 1 wrote 4 × stage-1 + 12λ + T_head = 2362.8 and attributed the 0.5 ms residual to double-counted chain ends.

### 7.1 Round 3 — rollout on the measured constants, and where the instance plan enters (`[R3-rollout-*]`)

| stage | positions | predicted step at 4k / 32k / 128k — dense | MoE | round 2 (32k) |
|---|---|---|---|---|
| **1 card** (c0.d1 → c0.d0) | 0, 1 | 572.91 / **593.73** / 665.12 ms (blocks 296.86, 296.87) | 29.00 / **33.85** / 50.51 (19.33, 14.51) | 587.42 / 32.56 |
| **2 cards** | 0–3 | 1 145.84 / 1 187.48 / 1 330.26 | 58.01 / 67.72 / 101.04 | 1 174.95 / 65.22 |
| **4 cards** | 0–7 | 2 303.93 / 2 387.22 / 2 672.77 | 119.24 / 138.68 / 205.31 | 2 362.22 / 133.75 |

The scaling identity holds exactly at the measured λ (T3r_rollout_identity): 4 × stage-1 + T_head + 2·T_launch + 4λ + (3
hops at 13.9 − 1 at 27.3 + logits) = 4 × 593.73 + 12.29 = **2 387.23 ms** = the direct step (MoE 4 × 33.85 + 3.25 = 138.69).
**The 2-card stage is one instance of variant I:** loaded with the int4 tier (x = 376 / 358 / 332 / 376 ‰ dense, 182 / 170 /
170 / 182 MoE) instead of the 15-layer prefix blocks, the same two cards serve 32k on their own at 3 223.48 ms (dense) /
134.37 ms (MoE) per token — 0.154 / 3.720 tokens/s per 2 cards — so stage 2 proves the whole instance plan (fit at x: H11;
the cold chain: E30) before stage 3 adds the second pair and runs **H10** (two instances concurrently) against the 8-die
chain. Re-partition steps: none for the 8-die layer blocks; the instance load is a different image (int4 tier packed in the
f16 fractal nibble order), so a stage-3 decision between "two instances" and "one chain" is a reload (3.5 s link-bound),
not a KV move. Everything else in §7 (per-layer host oracle, KV move costs) is unchanged.

---

## 8. Experiment ladder — host only (the runtime API and the host clock; no custom device kernel)

Harness rules: every device buffer is pre-filled with a sentinel and every transfer is **content-checked** on
the receiving side (a transfer that "completes" without changing the destination is the host-side analogue
of errata #1); every timing is the median of ≥ 100 reps with the full distribution kept; pass/fail is never
timing alone. Expected values are `[F8-*]`.

| # | settles | setup | observable failure | decides |
|---|---|---|---|---|
| **H0** | host inventory: RAM, NUMA, pinned-memory limit, PCIe topology of the 4 cards, aggregate host DMA | allocate pinned buffers up to the limit; map each card's root port; 4-card concurrent H2D of 1 GiB each | aggregate < 4 × 27.6 = 110.4 GB/s → the cards share a host-side bottleneck (load and any host-paging escape are then slower than §1.6); pinned limit < 2 × 64 MiB → the load pipeline's chunking changes | load time; whether host paging is even on the table |
| **H1** | per-die link curves T(n) = λ + n·10/R for n ∈ {4 KiB, 64 KiB, 1 MiB, 64 MiB}, both directions, all 8 dies | pattern A then pattern B through the same device buffer; read back through the opposite direction; expected bandwidth terms: 64 KiB → 2.4 (d0) / 4.7 (d1) µs H2D, 2.4 / 3.4 D2H; 64 MiB → 2 431 / 4 828 and 2 458 / 3 532 µs | readback unchanged (silent no-op); R below the HW-MAP figures (27.6/27.3/13.9/19.0) by > 10 %; λ intercept is **the λ branch of §2** | λ (primary 91 µs or not), the per-hop table |
| **H2** | whether die 0's link is a shared trunk | concurrent H2D (and D2H) to both dies of one card, 64 MiB each, content-checked | sum 41.5 GB/s (independent) vs 27.6 (trunk); either die's checksum wrong under concurrency = a DMA ordering bug | stage-2 hop costs; the Π = 8 trunk model; load time |
| **H3** | host-bounce round trip λ_rt and its behaviour under contention | for all 56 ordered die pairs: D2H a counter-pattern buffer of {8, 32, 128, 512 KiB, 2 MiB} → host increments it → H2D to the other die; the receiver's buffer must equal sender + 1 in every rep; then repeat with a concurrent bulk H2D stream on the same card chunked at 64 KiB / 1 MiB / 16 MiB | stale receiver buffer (bounce re-ordered behind bulk); wait beyond C/R + λ_rt (5 µs / 75 µs / 1.2 ms on the 13.9 link, T-queue) | §2.3's chunking rule; λ |
| **H4** | **Π — does the runtime pipeline independent sequences through a layer-split chain?** (the §10 measurement) | a model that fits one die, split over 2 dies by the runtime; submit N = 1, 2, 4 independent sequences; log per-token completion timestamps per sequence; sample the card power sensor (idle 41 W, loaded 141 W) at 10 Hz | throughput(N) flat in N → Π = 1 (the measured "dies alternate"); ∝ N up to 2 → pipelined; outputs of any sequence differ from its single-sequence run → cross-talk bug; power never above one-die load while two are "busy" → the runtime serialises | 7.7× / 7.1× or nothing; the Π = 8 layout refinements of §5 |
| **H5** | KV growth trace: the runtime allocator's real bytes per token per die | the stage-1 model; query per-die free memory every 1k tokens to 128k and beyond; expected slope 61 440 B/token (dense 15-layer die), 16 384 / 12 288 (MoE 4-/3-layer die), 8.0 GB at 128k | slope above expected (allocator overhead → L_max shrinks by 16 276 tokens per GB), steps (preallocation granularity), non-monotone free memory (fragmentation) | L_max, T4's premise, whether the preallocated-slab policy of §1.3 is what the runtime does |
| **H6** | launch-floor serialisation through the runtime (DESIGN.md E0 from the host) | N = 1, 10, 100 queued tiny ops, each writing its index to slot i | missing/duplicate slots; T(N) ≈ N × 91 µs serialised vs ≈ 91 + N × small pipelined | the launch branch: 65.7 ms (dense) / 18.0 ms (MoE) per token, 11.0 ms per draft token |
| **H7** | load path: int4 → int8 expansion throughput and end-to-end load time | expand per 64 KiB chunk into pinned buffers, stream per die; per-die checksum over the loaded bytes vs the host's checksum of the expanded chunk stream; differencing: layer A then layer B into the same region must change the checksum | checksum mismatch (expansion or DMA error); load slower than 3.5 s link-bound (386.7 GB) by more than the expansion's own cost | §1.6; whether the expansion must be cached on disk |
| **H8** | per-die overhead after load (the 2 GiB assumption) | free memory reported by the runtime after loading a die's final block, minus the known weight bytes | overhead > 3.54 GiB (3.80 GB) → the dense 1M KV-int8 layout (84.3 GB) no longer fits; > 2 GiB → L_max falls per T4 | T3/T4 margins |
| **H9** | routing skew D(t) (host-side; the router is 2 MiB per layer) and — fleet-only — the draft's α | run the 28 routers on the host over a text sample of ≥ 10⁵ tokens; histogram of distinct experts per 4- and 16-token group; compare with DESIGN-2's generator columns | D(4) ≥ 30 → uniform rows of §3.4 and T12's loss apply; D(4) ≤ 20 → the Zipf(1.5) rows | spec decode on/off for MoE; which B = 16 row to expect |

Order: H0, H1, H2, H3, H6, H8, H5, H4, H7, H9. H1–H3 settle λ (the only exchange unknown) in an afternoon;
H4 is the one whose answer rewrites §5 from a what-if into the plan.

**Round 3 (`[R3-ladder-*]`).** H1 and H3 are **measured** (λ = 12.2 / 12.1 µs; unchanged under a saturating die-0 D2D load):
they now re-verify the model (expected 4 KiB legs 12 348 / 12 494 ns H2D on d0 / d1, 64 MiB 2.44 / 4.84 ms) instead of
deciding it. H4 stays the one that rewrites §5. New rows:

| # | settles | setup | observable failure | decides |
|---|---|---|---|---|
| **H10** | **two serving-runtime instances on disjoint card pairs stream concurrently** (variant I's gate) — **GREEN at card scale** (HW-MAP: two instances on disjoint dies at full solo speed, 1.99×); the 2-card-pair run is the remaining check (proof: the cells are functions of the concurrency c, T3r_inst_h10) | two processes, each a 2-card layer-split model (the stage-2 image of §7.1), each fed an independent sequence for ≥ 100 steps; per-token timestamps; the four cards' power sensors at 10 Hz; outputs compared with each instance's single-instance run | either output differs (cross-talk); throughput(2) / throughput(1) ≈ 1.0 instead of the expected **2.0** (14.880 vs 7.208 fleet tokens/s, MoE 32k); only two cards at the loaded power at any time (the runtime serialises instances) | §1.8 on / off: +106 % MoE / +49 % dense at 32k |
| **H11** | the per-die fit at the chosen int4 share x with the real overhead | load the instance at x, read free memory per die, allocate KV(L) + 64 MiB | allocation refused; free memory < the expected margin (24.5 MB MoE 32k, 3.3 MB dense 32k at the 2 GiB assumption) → x must rise by 23 ‰ (MoE) / 21 ‰ (dense) per missing GB, 0.66 ms of MoE step per percent | the shipped x (+2.3 % per GB of margin) |
| **E38** (kernel-side, requested of the kernel ladder) | the on-device A-quant pass at K = 16 384 / 53 248 and at rows 4 / 16 — fixed per pass or proportional to the elements? | the measured 43.7 µs pass (m = 1, K = 8 192) re-run at the dense layer's shapes and at the verify-batch and B = 16 row counts, content-checked against the host quantizer | fixed reading: 43.7 µs each; proportional reading: 87.4 / 305.9 µs (and × rows) — the 32k step moves 47.19 ms dense (0.104 → 0.102) and 2.44 ms MoE (1.802 → 1.771) between the readings; the integrated-chain 135.5 figure (dense −20 %) is the reading to rule out | the quant term of every cell |
| H6′ | launch-floor serialisation — unchanged, but it now also sizes the megakernel's prize (54.60 / 15.28 ms per token) | as H6 | as H6 | whether V2 (E31) is worth building |

Order (round 3): **H10 first** (an afternoon, host-only, gates the largest runtime-free gain), H11 with it, then E38
(the production chain's cost), H4 (the one that rewrites the plan), H5, H8, H9, H7; H1–H3 only as regression checks. The
kernel-side gates this plan now depends on are owned by the other designs: E29 (direct-path expert chain, DESIGN-2 / ALT-1),
E31 / E32 (DDR-flag sync, watchdog — ALT-3), E35 (fixed-shift softmax — DESIGN-3 §3.4), E30 (cold-tier chain — ALT-2).

**Round 5 — the ladder rows the measured attention kernel adds** (kernel-side; owned by DESIGN-3 §8, listed here because they rank the
plan's follow-ups):

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **E39** (DESIGN-3 §8) | the batched guard's residual X per step (crossings + vector side-product + re-runs) over the unguarded 938.8 µs (**audit, #31:** the batched fence + flag design is the racing composition — killed in session 4; RESOLVED by the shipped deferred guard, MEASURED in session 5 — round 6 folds it) | the 32k t = 1 cell of the batched-guard kernel | X > 20 µs = the side-product sits on the serial chain | **the MoE 32k rank: guard fusion beats E29 iff X ≤ 8 279 ns** (T5r_levers_moe32k_iff); the fused column of §3.6 |
| **E40** (DESIGN-3 §8) | the serial phases overlapped across blocks | the 32k cell against the overlapped floor (821.8 µs) | no gain = a hidden per-phase crossing | ≤ 3.27 / 7.46 / 45.42 ms per MoE token at 32k / 128k / 1M |

Order (round 5): H10 and H11 keep their place (host-only); on the kernel side **E39 first** — it is worth 554.8–564.8 µs per layer at 32k
(15.53–15.81 ms per MoE token, 66.57–67.77 per dense token) and decides the 32k rank against E29 — then E29, then E40; the bounce (E24′)
is closed and cheap.

**Round 6 — the ladder rows after kernel session 5** (kernel-side; owned by DESIGN-3 §8 / §5.1, listed here because they rank the plan's
follow-ups):

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **E39 — RESOLVED** (DESIGN-3 §8) | the guard without per-block crossings | the shipped deferred guard, MEASURED: 945.5 µs trip-free at 32k, 946.3–947.4 amortized | — | the MoE 32k rank: a tie with E29 on the 141.7 GB/s line (§10‴) |
| **E40a → E40b** (DESIGN-3 §5.1) | the stage overlap | the φ probe on the stream rung, then the pipelined kernel | φ above 1.7 µs per vector-carrying barrier → E40 dead | the attention-side #1 lever: ≤ 3.46 / 9.28 / 67.09 ms per MoE token at 32k / 128k / 1M, ≤ 14.84 / 39.79 per dense token |
| **E41 (new)** (DESIGN-3 §8) | the deferred kernel re-timed: its per-engine phases, its t = 4 / 16 cells and a 4k cell | timing-only, the session-3 method | phases that do not sum to the cell | the dense verify attention v (§6.6), E40's prize on one session, the 4k cell |

Order (round 6): H10 and H11 keep their place (host-only). On the kernel side E29 is the largest remaining lever on MoE ≤ 128k (15.86 ms per
token, weights side) and E40a the cheapest decision (an afternoon; it gates the attention-side #1), so both go first; then E41, then E40b;
the bounce removal waits on a proven US → S1 route (#20).

---

## 9. Risk register

| risk | trigger / evidence | impact (numbers from `proof/fleet.py`) | fallback |
|---|---|---|---|
| **Memory infeasibility at 1M (dense)** | T3: f16 KV = 120 layers × 4 096 B × 2²⁰ = 515.3 GB against 282.3 GB of fleet room after weights (T4) — infeasible by 233 GB, on every die (114.4–116.5 GB) | no dense 1M with f16 KV on 8 dies, under any partition (the weights alone leave 282.3 GB) | **KV-int8** (257.6 GB; 84.3 of 86 GB on positions 0 and 7, T3') at the i8×i8 attention route; or a host-paged KV prefix: 233 GB per token through 4 trunks at 27.6 = 2.1 s per card per token if perfectly overlapped — T_step ≥ max(chain, X_card/R_h2d) (T10) → ≥ 5.2 s, 0.048 tokens/s/card (0.0479; 0.047 under the floor convention), and ≥ 233 GB of host RAM (H0); or fewer layers resident (host-streamed layers cost 6.3× their DDR time) |
| KV-int8 is the only dense 1M layout and it has 1.7 GB of margin on two dies | H8 (runtime overhead), H5 (allocator slope) | overhead > 3.54 GiB (3.80 GB) kills it (T_mem_feas_kv_int8); every GB above 2 GiB costs 16 276 tokens of L_max (T4) | move the embedding table to the host (a lookup; 32 KiB per token over the id link) → position 0 drops to 82.2 GB, but position 7 (lm_head) stays at 84.3: the margin grows only if lm_head also moves to the host (2.1 G MACs per token ≈ 0.1 s of CPU, 3 % of the 1M step) |
| KV-int8 numerics (i8 K, V and P) | fleet-only: relerr on attention outputs vs an f16 host reference on the stage-1 card | accuracy, not rate | keep f16 K and int8 V (386.5 GB of KV → still infeasible by 104 GB); or accept L_max = 551k |
| **Host bounce becomes the serial bottleneck** | H1/H3 λ; T8 | bounce = 10 % of the MoE step iff λ ≥ 918 µs; 50 % iff ≥ 8.27 ms; dense 16.4 / 147.5 ms (T8, corrected). At λ = 500 µs the MoE step is 140.39 ms (−5 %) | nothing structural is left to remove (7 hops is the minimum for 8 dies); the lever is fewer dies (5 dies: 4 hops, 10 λ) at the cost of context: dense L_max on 5 dies ≈ 53k |
| **Layer-split's "+2 %" ceiling** (T2) | measured: dies alternate | single-stream tokens/s ≤ 174.6 GB/s ÷ bytes per token no matter how many dies: 0.113/card dense, 3.4/card MoE; the fleet's 1.4 TB/s is unreachable by any Π = 1 plan | batching sequences (B = 16: 10× dense throughput at 32k, memory-limited to 34k), spec decode (2.48× dense), or the Π = 8 runtime capability (H4, 7–8×) |
| Launch floor | H6; measured 91 µs per launch | 13.5 % of the MoE step (18.0 of 133.8 ms), 2.8 % of dense, 61 % of a draft token; 42 % of the tensor-split what-if | fuse launches (norm/rope into GEMM epilogues: 6 → 4 per dense layer saves 21.8 ms per token); H6 may show pipelining (then −18.0 ms MoE, −33 ms per verify step) |
| MoE kernel stays in the serial regime | DESIGN-2 E13 | 133.84 ms (serial) vs 116.39 (ping-pong): −13 % | ship the serial number (it is the anchored one) |
| KV gather 3× slower than stream (attention kernel unbuilt) | PROBLEM-3 E-gather | −7 % dense at 32k; −24 % MoE at 32k; MoE 1M 0.312 → 0.114 (`[F9-moe-1M-gather3x]`); L*_KV falls to 259k (dense) / 45.6k (MoE) | the per-core head-slab layout of §1.3 makes the read sequential; if the realised rate is still low, the attention kernel, not the plan, is the fix |
| No exp instruction (poly softmax) | PROBLEM-3 E-exp | only dense verify batches at t ≥ 4 (t* = 4, T6): +1 % per attention layer | reduce k to 2 for dense (t* not reached) |
| Rows cliff | measured m ≥ 24 at 81 GB/s (46 % of flat) | any config with B·t > 16 halves its weight rate | T13: B·t ≤ 16 enforced by the scheduler (B = 16 excludes spec; spec k = 3 allows B ≤ 4) |
| Dense kernel falls back to the serial regime (138.9) | per-launch regression (HW-MAP: multi-strip wedge unresolved for m ≥ 24 only) | 2362 → 2928.50 ms, 0.085/card (`[F9-dense-serial]`) | keep rows ≤ 16; the direct-load path is the production path |
| Runtime overhead / allocator fragmentation | H5, H8 | L_max −16 276 tokens per GB (dense), −61 035 (MoE) | preallocated slabs (§1.3) if the runtime exposes them |
| Trunk sharing (die 1 transits die 0) | H2 | at Π = 1 nothing (utilisation < 0.02 %); load 3.5 s vs 2.3 s; Π = 8 bounces still ≤ 0.2 % of a trunk | none needed |
| MoE expert imbalance across dies (4 vs 3 layers) | layout | 0 at Π = 1 (T1); −12.5 % at Π = 8 | sub-layer split (7 units per die) if the runtime allows placing attention and expert blocks separately (H4) |
| Spec decode on MoE is a loss | T12; H9 routing | 1.451 vs 1.867 at α = 0.7 under uniform routing | off by default; on only if H9 shows Zipf(1.5)-class skew and α ≥ 0.647 |
| Draft launch-bound | H6 | 54.27 ms per verify step (2.3 % of dense, 41 % of MoE) | fewer draft layers; pipelined launches → 21.24 ms |
| Host RAM for the int4 source and (paging escape) KV | H0 | 193.3 GB (dense source) must be host-resident or disk-streamed at load; the paging escape needs ≥ 233 GB more | stream the source from disk through the expansion pipeline (load time becomes disk-bound) |
| Thermal | measured 141 W sustained all-core per card, 150 W class, no throttle | Π = 1: one die streams at a time (one card at ≤ 141 W, three near 41 W idle); Π = 8: every card at the measured sustained load | none |
| Host sampling path | logits 513 KB per step (2 MB at t = 4, 8.2 MB at B = 16) at 27.3 GB/s = 19 / 75 / 301 µs + λ | ≤ 0.3 % | on-device argmax/top-k if the runtime exposes it (removes one λ and the logits bytes) |

**Round 3 — risk register additions and moves (`[R3-risk-*]`):**

| risk | trigger / evidence | impact (numbers from `proof/fleet.py` `[R3-*]`) | fallback |
|---|---|---|---|
| **Serial-chain cold tier (proof: 807 ns per 2 KiB piece, not 596)** | ALTERNATIVES proof round; T3r_serpiece | MoE 32k two instances 3.128 instead of 3.399 (+73.5 % instead of +88.6 %); **dense 32k 0.100 (−3.8 %): replication loses**; dense 128k −24.7 % | the overlapped cold tier (E30) is a precondition of the dense instance plan; MoE keeps a +73 % floor on the serial chain |
| **The production chain runs at the integrated 135.5, not 174.6 + 43.7 µs** | HW-MAP: "integrated kernel 135.5 GB/s f32-in/f32-out"; E38 | every dense weight stream 22 % slower: 3 001.92 ms → **0.083 (−20 %)**; MoE 1.830 (+1.5 %: the folded pass costs less than four separate ones) — the one single-unknown swing above 5 % on the dense cell | the pass is a per-launch fixed cost on the measurement (43.7 µs for 8 192 elements is 5 ns per element — far above the vector rate), so the fix is the quantizing epilogue of ALTERNATIVES §2.4 fused into the producing GEMM (E33), not a kernel re-rate |
| **Dense verify batches are vector-bound** (rows = 64 = four fragments) | T6′; the measured per-call softmax items | spec decode at 32k 0.262 → 0.227 (2.17× instead of 2.48×); at 128k 0.156 | the fixed-shift chain (E35): 0.248 / 0.203; or k = 1 (rows 32, two fragments — 1.6× only) |
| **Dense 1M on KV-int8 is vector-bound at t = 1** | T5′ (L* = 1 006 608 at every G on the chain as specified) | 0.066 → **0.054**; attention 2 282 of 4 572 ms | the fixed-shift chain restores the KV-bound 0.065 (L* = 1 507 344); E35 is therefore a dense-1M item, not only a verify-batch item |
| **MoE 128k is a tie at 256 KiB pages and flips on the faster kernel** — proof: **with DESIGN-3 round 4's P bounce (legs 2, erratum #20) it is attention-bound at every G ≤ 174.6 on both kernels (lines 189.4 / 230.3); the tie survives only at legs 0** | T5′: L* = 131 600 (anchored, 256 KiB) vs 129 552 (64 KiB) vs 108 048 (direct path); T3r_moe128k_tie | 1.217 weights-bound by 0.5 % per layer at 256 KiB; 1.210 at 64 KiB (attention-bound by 0.8 % per layer, the step still W-bound: lm_head); 1.167 at 16 KiB; on the direct path 1.319 and attention-bound at every page size (by 20.8 %); round 4 legs 2: 1.155 / 1.246 (direct). Binding does not rank follow-ups at Π = 1: at 128k E29 saves 15.86 ms vs 11.10 for removing the bounce (T3r_moe128k_followups) | 256 KiB pages (DESIGN-3 §10) and never 16 KiB; the next lever at 128k is K-int8 / KV-int8 on the fixed-shift chain, not a page size |
| Host bounce as a serial bottleneck | **measured 12.2 µs; T8′** | 0.01 % / 0.16 % of the step; 10 % would need λ ≥ 16.6 ms / 960 µs | retired (re-verified by H1/H3) |
| Instance fit margin | H11; H8 | the minimal x leaves 2–30 MB per die; +1 GB of overhead needs x + 21–23 ‰ (0.66 ms per percent on MoE 32k: 3.720 → 3.70 at x + 1 %) | ship x + 2.3 % per GB of wanted margin; dense 1M cannot replicate at any x |
| H10 fails (the runtime serialises instances) — proof: **retired at card scale** (1.99× measured); the residual risk is the 2-card-pair inheritance (c < 0.970 would kill the MoE gain, < 1.354 the dense one) | H10 | variant I dead: MoE 32k stays 1.802 / 2.035 (E29) / 2.307 (+ E31) | V1 + V2 on the 8-die chain; the int4 tier on a single 8-die instance *loses* (ALTERNATIVES §4: −8.5 %) |
| Megakernel sync slower than the iff line | E31 | pays iff c_sync ≤ 108.4 / 109.9 µs; at 20 µs still +9.8 % MoE | launch fusion without the sync (head-aligned QKV: +1.9 %) |
| Expert kernel stays on the S1-staged path | E29 | 1.802 instead of 2.035 (−11 %); the instance cell 3.391 instead of 3.720 | ship the anchored number; the direct path is the follow-up |
| H4 passes after the instances ship | H4 | the two-instance layout is 3.4× / 5.2× below Π = 8 of one chain | reload the 8-die int8 image (3.5 s); the instances are a Π = 1 substitute by construction |
| Quant pass scales with rows / K (E38) | E38 | dense 0.102, MoE 1.771 (proportional reading at rows = 1); × rows at B = 16 would cost 8.7 ms per dense layer | fuse the quantizer into the producing epilogue (E33; **audit, #22 / #31 / #20:** with Duplicate + Mul, the per-row scale as a deterministic side-product, the i8 A out through DDR in 32 KiB legs — ALTERNATIVES §2.4's Muls and A-slot extraction are struck) |
| Launch floor | unchanged | 2.8 % dense / 13.0 % MoE / 50 % of a draft token / 46 % of the MoE tensor-split what-if | V2; H6 |
| Thermal | unchanged | two instances = two cards at 141 W each at Π = 1; Π = 8 four cards at 141 < 150 | none |

**Round 5 — the risk rows of the measured attention kernel:**

| Risk | Trigger | Impact | Fallback |
|---|---|---|---|
| The shipped guard stays in production | E39 not done | the guarded column of §3.6: MoE 32k 1.578 (−10.6 %), 128k 0.893 (−22.6 %), 1M 0.176 (−35.2 %); dense 32k 0.101 | the batched guard (E39) |
| The batched guard misses its target | E39 | X > 20 µs per step: each 10 µs is 0.28 ms per MoE token (0.2 % of the 32k step) — small on cells, decisive only for the 32k rank against E29 | E40 on the side-product |
| The per-block guard does not scale per block off 32k | the readings' rule | the unguarded / fused columns off 32k move to the constant-rate bracket: MoE 128k 1.130 / 1.119, 1M 0.261 / 0.256 (−2.6 … −7.9 %) | measure the unguarded kernel at 128k / 1M |
| Verify batches at the measured per-fragment cost | measured (t ≥ 4) | dense spec 0.211 (round 4: 0.252); MoE spec loses for α ≤ 0.807 | E39 and E40 at mt ≥ 2 |
| Dense 1M on KV-int8 pays erratum #29 | no KV-int8 kernel | ≤ 0.034 tokens/s/card (rowmax crossing bound; **audit, #31:** ≤ 0.027 at the deterministic crossing, T6f_dense1M_det) | the lazy μ = 0 KV-int8 route (trip rate UNMEASURED) |

**Round 6 — the risk rows of the measured deferred kernel:**

| Risk | Trigger | Impact | Fallback |
|---|---|---|---|
| ~~The shipped guard stays in production~~; ~~the batched guard misses its target~~ | — | **retired**: the deferred guard shipped and is MEASURED (MoE 32k 1.755, not the legacy 1.578) | — |
| A production model trips far above the premise | E35 (model half) | each 1 % of tripped steps costs 8.73 µs per layer at 32k (0.92 % of the cell); the deferred guard loses to the legacy scan only above 65.25 % of steps (32k) / 64.47 % (1M) | the legacy scan, kept byte-identical as the A/B control |
| Off-32k cells read by a rule instead of measured | any future reading | round 5's rule was 1.3 / 2.7 % optimistic per layer at 128k / 1M (MoE 128k 1.157 → 1.150, 1M 0.278 → 0.271) | measure the cell; do not scale it |
| E40's bound unreachable (φ) | E40a | the attention-side #1 is lost: MoE 1M falls back to the bounce removal (45.69 ms, itself conditional on #20), MoE 32k / 128k to E29 alone | stay serial on the deferred kernel |
| The deferred verify kernel slower than fragment-serial | E41 | dense spec 0.225 → toward 0.211 (the legacy verify); spec still pays at α = 0.7 for every v ≤ 31.09 ms per layer | none needed |

---

## 10. The single measurement that most changes the plan

**H4 — whether the serving runtime pipelines independent sequences through the layer-split chain (Π > 1).**
At 32k every other unknown moves a cell by at most 1.32× (G: 0.93× / 0.76×; MoE regime: 1.15×; launch pipelining: 1.03× / 1.16×; λ across its whole bracket: 1.0× / 0.95×; routing skew: 1× at t = 1); the exception is the G branch at 1M, where the MoE cell falls 2.7× (0.312 → 0.114). Π = 8 moves every cell
by **7.7× (dense) / 7.1× (MoE)** at unchanged per-sequence latency, with zero extra link bandwidth (0.2 % of a
trunk) and no kernel change — and it rewrites the plan: the partition objective becomes the per-die block
time (balance MoE at the sub-layer level, 7 units per die; put lm_head and the draft on the lightest
blocks), the draft starts contending for DDR (6.9 ms per draft token), the exchange schedule gains a queue
model (8 bounces in flight per trunk), and the memory plan must hold 8 contexts (B = 8 at L = 32k: dense
L_max(8) = 68 906 — still feasible, so the throughput plan at 32k is Π = 8 × B = 1, not B = 16). If H4 says
Π = 1 (the measured "dies alternate"), the plan is exactly §1–§3 and the fleet's aggregate bandwidth is
reachable only by batching (memory-limited) or by a runtime that stops faulting on tensor-split (§5). It is
a host-only experiment: two sequences, per-token timestamps, and the card power sensor as the independent
witness that both dies of a card are streaming at once.

**Round 3 — the per-regime decision table (`[R3-decision]`; L = 32k, t = 1, tokens/s per card dense / MoE):**

| plan | gate (pending) | dense | MoE | build order |
|---|---|---|---|---|
| **primary**: one 8-die chain, anchored MoE kernel, measured λ / G / c_q | none — today | **0.104** | **1.802** | the baseline every stage of §7 verifies |
| + MoE expert kernel on the direct path (V1) | E29 | 0.104 | **2.035** (+12.9 %) | 2nd: a kernel probe on a measured path, +13 % for every MoE cell and +10 % on the instance cell |
| + per-layer megakernel, c_sync = 5 µs (V2) | E31 / E32 | 0.106 (+1.9 %) | 2.012 (+11.6 %) | 3rd: iff c_sync ≤ 108 µs; composes with everything |
| V1 + V2 | E29 + E31 | 0.106 | **2.307** (+28.0 %) | |
| **two 4-die instances, minimal int4 tier, direct-path hot tier (V3)** | **H10** (GREEN at card scale, 1.99× → 3.702 / 0.154; 2-card pairs pending) + H11 | **0.155** (+49.0 %) | **3.720** (+106.4 %) | **1st: an afternoon on the host; the largest gain that needs no runtime change** |
| V3 with the anchored kernel (no E29) | H10 | 0.155 | 3.391 (+88.1 %) | |
| V3 + V2 | H10 + E31 | 0.157 (+50.9 %) | **4.170** (+131.4 %) | |
| Π = 8 pipelining of one 8-die chain (runtime capability) | **H4** | **0.808** (7.7×) | **12.918** (7.1×) | the only lever above V3 — and it undoes V3 |

**Given H4 and H10 both pending (proof session: H10 is now GREEN at card scale — the 2-card-pair run is what remains of it), the order is H10 → E29 → E31 / E35 → H4**, because H10 and H4 are cheap and decide the
*shape* of the plan (one chain or two instances) while E29 / E31 / E35 only scale it: if H10 passes and H4 fails, ship the
two-instance plan at 3.720 / 0.155 (4.170 / 0.157 with the megakernel); if H4 passes, ship the single chain with Π = 8 at
12.918 / 0.808 and keep V1 / V2 (they shorten every block); if both fail, V1 + V2 on the chain is the ceiling (2.307 / 0.106).
**H4 remains the single measurement that most changes the plan** (7×, and it reverses the instance decision); H10 is the
single measurement that most changes what ships *next month*. At 32k the other unknowns move the cells by at most: the
quant-pass reading 0.98× / 0.98× (the integrated-chain reading 0.80× on dense), page size 1.00× / 0.98×, the chain
convention 1.00×, λ over 10–500 µs 1.00× / 0.95×, launch pipelining 1.03× / 1.15×, the MoE regime 1.13× (1.13–1.15× across the direct / overlapped / ping-pong readings — proof, T3r_branch_ratios); at 1M the page size
moves MoE by 0.92× (16 KiB) and the chain variant moves dense KV-int8 by 1.20×.

### 10″ Round 5 — the attention-side levers, re-ranked on the measured kernel (`[R5-levers-*]`, `[R5-retired]`; T5r_levers, T5r_levers_moe32k_iff, T5r_levers_overtake, T5r_nbF_lines, T5r_retired, T5r_levers_context)

At Π = 1 the step is a sum (T = Σ W + Σ ATTN + …), so a follow-up's worth is the time it removes per token, whichever side binds. The P4P2
round ordered the attention-side follow-ups at MoE 128k as **choreography 22.33 > expert-direct (E29) 15.86 > bounce 11.10 ms per token**,
where "choreography" was the gap between the session-1 diagnostic loop (138.3 GB/s) and the E21 page rate (169.2). Session 3 measured that
gap: the production kernel's K+V stream phase runs 174–176 GB/s, so the G gap is closed, and what separates the shipped kernel from the
round-4 cell is the guard's per-block scan — at 128k the guarded cell exceeds the round-4 cell by 2 264 164 ns per layer (63.39 ms per MoE
token), and the per-block guard (2 299 200 ns) covers 101.5 % of it (T5r_retired). The corrected levers per token (ms, ms2 convention;
guard fusion = guarded → fused with one 20 µs crossing per step, 10 µs alongside; phase overlap = unguarded → the overlapped floor, an upper
bound; bounce removal = the measured bounce scaled per block; E29 = 28 × 566 520 ns, weights side, L-independent):

| cell | #1 | #2 | #3 | #4 | guard fusion at a 10 µs crossing / constant-rate reading |
|---|---|---|---|---|---|
| MoE 4k | **E29 15.86** | guard fusion 1.45 | overlap ≤ 1.08 | bounce 0.17 | 1.73 / 2.62 |
| MoE 32k | **E29 15.86** | guard fusion 15.53 | overlap ≤ 3.27 | bounce 1.42 | 15.81 / 15.53 |
| **MoE 128k** (the P4P2 cell) | **guard fusion 63.81** | E29 15.86 | overlap ≤ 7.46 | bounce 5.71 | 64.09 / 56.50 |
| MoE 1M | **guard fusion 514.46** | bounce 45.69 | overlap ≤ 45.42 | E29 15.86 | 514.74 / 437.78 |
| dense 4k | **guard fusion 6.22** | overlap ≤ 4.67 | bounce 0.76 | — | 7.42 / 11.23 |
| dense 32k | **guard fusion 66.57** | overlap ≤ 14.04 | bounce 6.12 | — | 67.77 / 66.58 |
| dense 128k | **guard fusion 273.50** | overlap ≤ 31.98 | bounce 24.48 | — | 274.70 / 242.17 |

**The corrected ordering, as theorems:**
- **At the P4P2 cell (MoE 128k): guard fusion 63.81 > E29 15.86 > phase overlap ≤ 7.46 > bounce removal 5.71 ms** (T5r_levers; on the
  constant-rate reading guard fusion is 56.50, still first). The choreography lever (22.33 ms) is retired; the bounce lever moves 11.10 →
  5.71 ms (the measured bounce is 51.4 % of the modelled charge); "169.2 → 174.6" (3.08 ms) is moot (the stream phase runs 174–176).
- **Dense: guard fusion first at every L** (no E29 on dense; E31's launch saving, 50.35 ms per dense token at c_sync = 5 µs, is a
  non-attention lever of comparable size, discussed with the megakernel in §5′, not ranked here).
- **MoE, by L:** guard fusion outranks E29 for every L ≥ 33 297 at a 20 µs crossing and every L ≥ 32 785 at 10 µs (iffs over the block
  count, T5r_levers_overtake + T5r_nbF_lines — on the per-block guard reading, which is exact at 32k and UNMEASURED off it).
- **MoE 32k — where the steering note's "guard fusion (worth ~570 µs at 32k) is the new #1" needs a condition:** guard fusion saves
  574 800 − X ns per layer, X = the fused kernel's residual per step (crossings + side-product + re-runs), and it outranks E29 **iff
  X ≤ 8 279 ns** (∀ X; T5r_levers_moe32k_iff) — i.e. iff the fused kernel reaches ≤ 947 079 ns = 141.7 GB/s. At the measured crossing band
  (X = 10–20 µs, the fused target 140.0–141.5 GB/s) E29 stays first by 48 160–328 160 ns per token (0.3–2.1 %): a tie inside the band.
  "~570 µs" is the zero-residual ceiling (574.8 µs → 16.09 ms per MoE token), which would be first.
- **MoE 4k: E29 first** on every reading (guard fusion 1.45–2.62 ms).
- **Context (T5r_levers_context):** the E31 megakernel saves 14.48 ms per MoE token at c_sync = 5 µs — the same size class as E29 and the
  32k guard fusion; it carries its own gate (pays iff c_sync ≤ 108.4 µs, §5′).

What ships next, by this table: the batched guard (E39) is the largest attention-side lever on every MoE cell above 33.3k tokens (32.8k
at a 10 µs crossing) and on every dense cell; E29 keeps first place on short-context MoE serving; E40 is worth at most an eighth of E39 at 128k; the bounce is the smallest
attention lever except at MoE 1M, where the measured bounce removal (45.69 ms) edges out the overlap bound (45.42). **audit (#20):** bounce
removal means legs = 0, which needs a proven US → S1 route for P — #20 measured the plain copy wrong and no other route is proven, so the
lever is conditional (UNMEASURED route); at MoE 1M the next lever is the overlap bound (DESIGN-3 §5.1 pre-designs it, gated on φ).

### 10‴ Round 6 — the levers after fusion (`[R6-tie-*]`, `[R6-realized-*]`, `[R6-levers-*]`; T6r_tie32k, T6r_tie32k_cells, T6r_tie_lines, T6r_tie_lines_cells, T6r_realized, T6r_levers6, T6r_levers_moe4k)

**Guard fusion is banked.** What it delivered per token at Π = 1 (the legacy scan, session 3 → the deferred kernel, session 5; T6r_realized):
MoE 15.90 / 62.55 / 493.34 ms at 32k / 128k / 1M, dense 68.17 / 268.09 ms at 32k / 128k (amortized at 32k: MoE 15.85–15.88, dense
67.94–68.07; on the same-session legacy scan, 1 514.9 µs: MoE 15.94, dense 68.32).

**Round 5's open question — does guard fusion outrank E29 at MoE 32k? — answered by measurement: a tie on the line.** For every per-layer
cell T, the realized fusion outranks E29 (15.86 ms per token) **iff T ≤ 947 079 ns = 141.7 GB/s** on round 5's basis (the session-3 legacy
1 513 600 ns; ∀ T, T6r_tie32k) — round 5's "X ≤ 8 279 ns" in absolute form. The measured readings straddle it (T6r_tie32k_cells):

| 32k reading | cell | against the 947 079 ns line (round 5's basis) | on the session-5 legacy (line 948 379 ns = 141.5 GB/s) |
|---|---|---|---|
| trip-free | 945 500 (142.0 GB/s) | fusion 15.90 ms: leads by 44 240 ns per token (0.28 %) | fusion leads by 80 640 (0.51 %) |
| amortized, 0.087 % of steps | 946 300 (141.8) | fusion leads by 21 840 (0.14 %) | fusion leads by 58 240 (0.37 %) |
| amortized, 0.22 % of steps | 947 400 (141.7) | **E29 leads by 8 960 (0.06 %)** | fusion leads by 27 440 (0.17 %) |

The two levers are equal within 0.51 % on either basis — the amortized band alone spans 1.9 µs per layer — so at exactly 32k the rank is
a tie, ON the 141.7 line, as the steering note reads it. **At 128k / 1M attention wins outright:** the tie lines are T ≤ 5 286 379 ns
(101.6 GB/s) and T ≤ 45 747 079 ns (93.9 GB/s) (∀ T, T6r_tie_lines); the measured cells sit 1 667 579 / 17 053 079 ns per layer inside them,
and the banked fusion is 3.9× / 31.1× E29 (T6r_tie_lines_cells).

**The levers that remain, per token at Π = 1 (T6r_levers6, T6r_levers_moe4k).** E40 = the stage overlap's reachable bound on the measured
cell (deferred − floor − end read, DESIGN-3 §5.1; top = F1 + a free read, bottom = F2 + a 20 µs read; reachable only if φ is small — E40a);
bounce removal = the measured bounce scaled per block (conditional on a proven US → S1 route, #20); E29 = 28 × 566 520 ns (weights side,
L-independent):

| cell | #1 | #2 | #3 | E40 bracket (bottom – top) | E40's bottom over the bounce removal |
|---|---|---|---|---|---|
| MoE 4k (no deferred cell) | **E29 15.86** | E40 ≤ 3.10 and bounce 0.17 — for every deferred 4k cell ≤ the guarded 213.5 µs (their order UNMEASURED) | | — | — |
| MoE 32k | **E29 15.86** | E40 ≤ 3.46 | bounce 1.42 | 2.27 – 3.46 | 0.84 ms |
| MoE 128k | **E29 15.86** | E40 ≤ 9.28 | bounce 5.71 | 6.21 – 9.28 | 0.50 ms |
| MoE 1M | **E40 ≤ 67.09** | bounce 45.69 | E29 15.86 | 46.45 – 67.09 | 0.75 ms |
| dense 32k | **E40 ≤ 14.84** | bounce 6.12 | — | 9.75 – 14.84 | 3.63 ms |
| dense 128k | **E40 ≤ 39.79** | bounce 24.48 | — | 26.63 – 39.79 | 2.15 ms |

**The order, as theorems:** every row holds at both ends of the E40 bracket (T6r_levers6). So **E40 is the attention-side #1 on every
cell** — even at its pessimistic end it beats the bounce removal, by 0.50 ms per token at MoE 128k and 0.75 ms at MoE 1M, the two closest
cells; **E29 remains the expert-side lever, and the largest remaining lever on MoE at 32k and 128k** (15.86 ms against E40 ≤ 3.46 / 9.28);
**at MoE 1M E40 ≤ 67.09 > bounce 45.69 > E29 15.86**. The bounce removal is last on every cell except MoE 1M, where it is second — the same
exception as round 5 — so "bounce removal stays last (~51 µs)" holds at 32k (51 µs per layer = 1.42 ms per MoE token) and 128k, not at 1M.
MoE 4k: E29 first for every deferred 4k cell up to the guarded one (∀ T, T6r_levers_moe4k). Context (not ranked): the E31 megakernel is a
non-attention lever of the same size class as E29 (§5′; its primary reading is c_sync = 20 µs since PROMPT-6).

What ships next, by this table: **E29 and E40a first** — E29 is the largest lever on short- and mid-context MoE, E40a decides in an
afternoon whether E40's bound is reachable at all; then E41 (E40's prize on one session, the dense verify v), then E40b; the bounce removal
waits on a proven US → S1 route.

---

## Appendix A — claim ledger (for the proof session: `proof/fleet.py` labels and proposed theorem names)

Status: M = HW-MAP input; D2 = DESIGN-2 derived input; D = derived here (theorem target, `decide`/`omega` over Nat); A = assumption measured by the named host experiment; U = empirical branch. Round 2: the theorem names are those of `proof/fleet.lean`; "∀ x" marks a result universally quantified over the unmeasured or assumed quantity x.

| # | claim | value | status | fleet.py / theorem |
|---|---|---|---|---|
| 1 | dense resident int8 = 120 · 3 187 671 040 + 2 · 2 101 346 304 | 386 723 217 408 B | D | [F0-dense] T0_dense_bytes |
| 2 | MoE resident int8 = 28 · 12 926 844 928 + 2 · 525 336 576; expert slabs 12 GiB = 12.9 GB per layer | 363 002 331 136 B | D | [F0-moe] [F0-moe-experts] T0_moe_bytes, T0_expert_slabs_units |
| 3 | KV per token: 491 520 B (dense), 114 688 (MoE); at 2²⁰ tokens 515.3 / 120.2 GB; K+V per token-layer 4 KiB | | D | [F0-kv1M] T0_kv, T0_kv_write |
| 4 | per-die totals at 4k: dense ≤ 52.3 GB, MoE ≤ 54.5 — all ≤ 86·10⁹ | feasible | D | [F10-mem-*-4k] T_mem_feas_dense_4k, T_mem_feas_moe_4k |
| 5 | dense 1M f16: every die ≥ 114.4 GB > 86 for any overhead, and under ANY partition (fleet KV room 282.3 GB < 515.4) | infeasible | D (∀ overhead, ∀ partition) | [F10-mem-dense-1M] [F9-mem] T_mem_infeas_dense_1M, T_mem_infeas_1M_any_partition, T_mem_room, T_mem_feas_dense_1M |
| 6 | dense 1M KV-int8: max die 84.3 GB ≤ 86; fits iff the per-die overhead ≤ 3 804 224 512 B = 3.80 GB = 3.54 GiB (margin 1.66 GB at 2 GiB) | feasible | D (overhead A, H8) | [F10-mem-dense-1M KV-i8] [F1-ort-threshold] T_mem_feas_kv_int8 (∀ overhead, iff), T_mem_feas_kv_int8_cells |
| 7 | MoE 1M f16: max die 71.6 GB | feasible | D | [F10-mem-moe-1M] T_mem_feas_moe_1M |
| 8 | L_max = min_pos ⌊room_pos / (n_pos·kv_tok·B)⌋: dense 551 253 / 137 813 / 34 453 (B = 1/4/16), int8 1 102 506; MoE 1 925 823 / 481 455 / 120 363; B = 8: 68 906 | | D | [F1-*-Lmax] T_Lmax, T_Lmax_binding_pos, T_Lmax_formula |
| 9 | ΔL_max per GB of overhead: 16 276 (dense), 61 035 (MoE); L_max monotone in the overhead | | D | [F1-dLmax] T_Lmax_dOverhead, T_Lmax_monotone |
| 10 | minimum dies for either shape: 4 dies infeasible for ANY layer assignment (some die holds ≥ 30 / 7 layers = 95.6 / 90.5 GB; totals 386.7 / 363.0 > 344); 5 dies feasible (24 / 6 layers per die, worst die 81.2 / 80.4 GB at 4k; dense L_max ≈ 53k) | 5 | D (∀ assignment) | [F1-*-min-dies] T_min_dies, T_min_dies_dense_4, T_min_dies_moe_4, T_min_dies_4_total, T_min_dies_5_dense, T_min_dies_5_moe, T_min_dies_heuristic |
| 11 | Σbw per token = 41 107 ns (dense r=1), 164 443 (r=4), 24 367 / 97 484 (MoE); 16 latencies | | D | [F2-*] T_bw_hops, T_bw_sum |
| 12 | hop sum = 4·(h₀+h₁+g₀+g₁) − h(first die) − g(last die): order-dependent only through the first and last die types; classes 41 107 / 42 277 / 48 792 / 49 962 ns, chosen (d1, d0) = min; logits source 18.8 vs 27.0 µs | | D (∀ 70 orders) | [F2-order] [F2-order-classes] T_order_formula, T_order_optimal, T_order_d1_d0, T_order_d0_d0, T_order_d1_d1, T_order_d0_d1, T_order_chosen |
| 13 | T_x(λ) at 10/91/500 µs: dense 201 / 1 497 / 8 041 µs; MoE 184 / 1 480 / 8 024; = Σbw + 16λ over the whole bracket | | D (λ A) | [F2-*] T_Tx_cells, T_Tx_bracket (∀ λ) |
| 14 | bounce ≥ 10 % of the 32k step iff λ ≥ 16 392 µs (dense) / 918 (MoE); 50 % iff 147 549 / 8 271 — the step carries the 16 λ (round 1: 14 762 / 835 and 73 820 / 4 181 against the fixed λ = 91 µs step) | | D (∀ λ, iff) | [F9-*-lambda] T_bounce_threshold_dense, T_bounce_threshold_moe, T_bounce_round1 |
| 15 | per-card trunk bytes per token (dense r=1): 98 308 (= 96 KiB) / 131 072 / 131 072 / 611 328; utilisation < 0.02 % | | D | [F2-dense-rows1] T_trunk_bytes, T_trunk_util |
| 16 | queueing bound behind bulk chunk C on the 13.9 link: 5 / 75 / 1 207 µs for 64 KiB / 1 MiB / 16 MiB | | D | [F8-H3] T_queue |
| 17 | per-layer times: dense GEMM 18 256 993 ns; MoE 240 223 + 2 967 496 (serial) / 2 344 360 (pp); heads 12 035 202 / 3 008 800; launches 546 000 / 637 000; W = 2 202 874 362 / 92 824 932 | | D (D2) | [F3-*-layer] T_layer, T_W |
| 18 | attention per layer (`[F3-*-attn]`): KV = 4096·L·10/G; SM = t·H_q·L·c_E·10/3456; MMA = 2·8·(L/16)·⌈t·g/16⌉·15/8 — every cell of the §3.1 table; KV monotone over 582 ≤ G ≤ 1746, SM linear over 4 ≤ c_E ≤ 16 | table §3.1 | D (G, c_E U: ∀ over the brackets) | T_attn_dense, T_attn_moe, T_attn_shares, T_attn_G_bracket, T_attn_cE_bracket |
| 19 | §3.2 table: 26 rows of T_step, components, tokens/s/card, feasibility | | D | [F3] T_step_dense_4k/_32k/_128k/_1M, T_step_moe_4k/_32k/_128k/_1M, T_draft |
| 20 | §3.3 branch table and brackets (dense −8 %/+3 %; MoE −27 %/+38 %); dense 0.105 for every λ in 10–500 µs, MoE within 1.780–1.886 | | D (∀ λ) | [F3b] T_branches_dense, T_branches_moe, T_step_lambda_form, T_step_lambda_bracket |
| 21 | MoE B = 16 by family: 2.357 / 3.714 / 4.765 at 32k | | D (D(16) U) | [F3c] T_moe_families |
| 22 | L*_KV = ⌈T_w·G/(10·kv_tok·B)⌉: dense 778 240 (= W_layer/4096), 194 560, 48 640; gather3x 259 414; int8 1 556 480; MoE 136 736 / 34 184 / 8 546, pp 110 173, gather3x 45 579; an iff on the exact model for every L | | D | [F4-*-Lkv-*] T_Lstar_kv, T_Lstar_iff, T_Lstar_iff_moe |
| 23 | t* = ⌈kv_tok·3456/(G·H_q·c_E)⌉, L-independent: dense 16 / 4 (native / poly), MoE 64 / 16; gather3x 48 / 12, 191 / 48; int8 8 / 2; both sides of the threshold in the floored model | | D | [F4-*-tsm-*] T_tstar, T_tstar_iff, T_tstar_model |
| 24 | MMA share of KV time: dense 8.0 / 32.0 / 127.9 % at t = 1/4/16; MoE 8.0 / 8.0 / 32.0 | | D | [F4-*-mma-*] T_mma_share |
| 25 | regime map cells (§4.1): binding term and share, all 24 cells | | D | [F4-regime] T_regime_dense, T_regime_moe, T_regime_shares |
| 26 | layer-split ceiling: Σ_pos n_pos·T = n_L·T for any partition; tokens/s ≤ R_gemm / bytes per token = 0.453 fleet (dense), 13.457 (MoE) for any extra cost | | D (∀ partition, ∀ extra) | T_serial_partition, T_serial_partition_120, T_ceiling, T_serial |
| 27 | P2P saving ≤ T_x = 1 497 µs < 1.5 ms: 0.06 % / 1.1 % | | D (∀ replacement cost) | [F5-*-p2p] T_p2p_bound, T_whatif |
| 28 | tensor-split: dense 398.52 ms (273.85 + 11.53 + 1.50 lm_head/8 + 65.70 + 45.93), MoE 43.02 (11.61 + 2.69 + 0.37 + 18.01 + 10.32); per reduction 191 / 184 µs; with P2P 357.50 / 33.41; 5.9× / 3.1×, 6.6× / 4.0× | | D | [F5-*-tsplit*] T_tsplit, T_tsplit_p2p |
| 29 | Π = 8: blocks 293.66–305.99 ms (dense), 14.02–18.63 (MoE); 1/max = 3.268 / 53.657 fleet tokens/s = 7.7× / 7.1×; T_step = Σ blocks + λ, speed-up ≤ 8 + λ/max; MoE imbalance loss 10.3 % (not 12.5 %); trunk 0.06 % / 0.84 % (not 0.2 %) | | D | [F5-*-pipe] [F5-*-pipe-balance] T_pipelining, T_pipelining_blocks, T_pipelining_decomposition, T_pipelining_bound, T_pipelining_balance, T_pipelining_trunk, T_pipelining_memory |
| 30 | D2D: 0 B per token (no D2D term in the step); KV move 753 → 161 ms (dense 128k), 201 → 43 (MoE) | | D / DEFINITION | [F5-*-d2d] T_d2d |
| 31 | draft token 18.1 ms (5 727 + 1 153 + 11 011 + 19 + 182 µs); verify step 54.27 / 21.24 ms; 61 % launch-bound; 0.5 GB saves 2.9 ms, 12 layers save 5.5 | | D (launch M, λ A) | [F6-draft] T_draft |
| 32 | τ(α, k) = Σ α^i: 1.875 / 2.533 / 3.439 at k = 3; τ(α, 3) < 4 for every α < 1 | | D | [F6-tau] T_tau, T_tau_lt_rows |
| 33 | spec on dense: 0.262 (k = 3), 0.315 (k = 7) at α = 0.7, gain 2.475× (1.832 / 3.361 at α = 0.5 / 0.9), a gain for every α ≥ 0.024; on MoE uniform 1.451 < 1.867: loss iff α ≤ 0.864 (τ < T₄/T₁ = 3.2584), Zipf(1.0) iff α ≤ 0.746, Zipf(1.5) iff α ≤ 0.646 (tie at 1.867 in thousandths), both directions for every α; mechanism D(4) = 4·D(1) | | D (α as a variable) | [F6-*] T_spec_dense, T_spec_dense_all_alpha, T_spec_dense_breakeven, T_spec_dense_best_k, T_spec_moe_loss, T_spec_moe_mechanism, T_spec_moe_loss_exact, T_spec_moe_loss_tps, T_spec_moe_tie, T_spec_moe_cells, T_spec_steps |
| 34 | rollout: stage steps (§7 table); 4 × stage-1 + T_head + 2·T_launch + 4λ + (3 hops at 13.9 − 1 at 27.3 + logits) = 2362.32 ms exactly (round 1: + 12λ + T_head = 2362.8 with a 0.5 ms residual) | | D | [F7-*] [F7-*-identity] T_rollout_dense, T_rollout_moe, T_rollout_identity |
| 35 | ladder expectations: link µs per size, trunk 41.5 vs 27.6, KV slopes 61 440 / 16 384 / 12 288 B per token, load 3.5 s (2.3 s with independent links) | | D | [F8-*] T_ladder_H1, T_ladder_rest |
| 36 | rows cliff: 81/174.6 = 46.3 %; B·t ≤ 16 | | M/D | [F9-rows] T_rows_cliff |
| 37 | dense serial fallback: 2928.50 ms → 0.085; MoE 1M gather3x: 2178.63 ms → 0.114 (2.7× — the one single-unknown swing above 1.32×) | | D | [F9-*] T_fallbacks, T_single_measurement |
| 38 | power: Π = 1 one card at ≤ 141 W; Π = 8 all at 141 < 150 | | M | [F9-power] T_power |
| 39 | A-fraction approximation: the measured 174.6 carries 1.5 % of A bytes; the dense down-projection (K = 53 248) streams 3.1 % → 0.44 % per layer (27.4 % of the layer × 1.6 %), carried as the explicit hypothesis pen ≤ 0.5 % on every dense cell; the headline 0.105 survives any penalty ≤ 0.8 % | | A (stated, as a hypothesis) | T_afrac_size, T_afrac_headline, T_afrac_edge, T_serial_dense_afrac, T_serial_moe_afrac |

---

## Appendix A′ — round-3 claim ledger (theorems-in-waiting for the next proof session; `proof/fleet.py` `[R3-*]`)

Status: every row is printed by the named `[R3-*]` label (integer arithmetic on the measured constants) and is a
**theorem-in-waiting**: the proposed `T3r_*` name is the statement the proof session should add to `proof/fleet.lean`
(the attention terms come from `proof/attn.lean`'s `Design3.step3` evaluated at rows = t·g, and the three variants are the
round-2 cost model with one term changed). Every round-2 theorem remains true of the round-2 model; the cells it fixes that
round 3 supersedes are listed in `[R3-moved-*]` and in the round-3 section of PROOF-COVERAGE-4.md. Hypothesis variables to
carry explicitly: λ (measured 12 200 ns; the 10 / 91 / 500 µs what-ifs), G ∈ {1538, 1670, 1690, 1692, 1746} (582 what-if),
the chain variant and convention, c_q ∈ {0, 43 700 fixed, proportional}, the integrated-chain rate, the expert regime, c_sync,
the int4 share x, the cold-tier time T_cold, the runtime overhead `ort`, α, Π.

| # | claim | value | status | fleet.py / proposed theorem |
|---|---|---|---|---|
| R1 | λ = 12 200 ns per direction; T_x = Σbw + 16 λ: dense 236 307 / 359 643 / 852 999 ns (rows 1 / 4 / 16), MoE 219 567 / 292 684 / 585 151; instance chain 8 λ: 126 / 119 µs | | M → D | [R3-xch-*] [R3-inst-*] T3r_Tx |
| R2 | bounce ≥ 10 % of the 32k step iff λ ≥ 16 573 797 ns (dense) / 960 105 (MoE); 50 % iff ≥ 149.2 / 8.65 ms; share at 12.2 µs = 0.01 % / 0.16 % | iff | D (∀ λ) | [R3-T8-*] T3r_bounce_threshold_dense/_moe |
| R3 | per-layer attention (t = 1, rows ≤ 16, mt = 1): nb·(2 MiB·10/G) + 18 820 — 812 036 ns at 32k, 25 401 732 at 1M on 256 KiB pages; 822 468 / 25 735 556 at 64 KiB; 891 460 / 27 943 300 at 16 KiB; 787 524 / 24 617 348 at 174.6 | | D (D3 model; G M) | [R3-attn-*] T3r_attn_t1 (∀ G in the measured set) |
| R4 | dense verify batch (rows 64, mt 4, 256-token blocks): 3 555 844 ns at 32k (vector-bound), 1 593 364 on the fixed-shift chain; MoE verify (rows 16): 812 036 | | D | [R3-attn-*] T3r_attn_t4 |
| R5 | KV-int8 at t = 1 is vector-bound on the chain as specified: 612 484 ns at 32k, 19 016 068 at 1M; DDR-bound on the fixed-shift chain: 407 936 / 12 702 784 | | D | [R3-attn-*] T3r_attn_i8 |
| R6 | c_q = 43 700 ns × 4 per layer: 20.97 ms (dense) / 4.89 ms (MoE) per token; proportional reading 568 100 / 262 200 ns per layer at rows 1 | | M → D | [R3-layer-*] T3r_quant |
| R7 | the §3.5.2 table, all 31 rows: dense 32k 2 387 232 989 ns → 0.104; MoE 32k 138 693 907 → 1.802; dense spec 2 783.00 → 0.227 (fixed-shift 2 547.50 → 0.248); dense 1M KV-int8 4 571.71 → 0.054 (fixed-shift 3 814.12 → 0.065); MoE 1M 827.20 → 0.302; B = 16: 1.039 / 2.325 | | D | [R3-step] T3r_step_dense_4k … T3r_step_moe_1M |
| R8 | moved cells: every round-2 step cell → its round-3 value (26 pairs); dense t = 1 −0.9 %, MoE −3.4 %, dense spec −13.3 %, dense 1M KV-int8 −18.1 %, MoE 1M −3.2 % | | D | [R3-moved-*] T3r_moved |
| R9 | branches at 32k: dense 0.082 … 0.108 (integrated chain … optimistic), MoE 1.703 … 2.564; page size 1.00× / 0.98×; λ ∈ [10, 500] µs: 0.104 for every λ, MoE 1.706–1.802; expert regime 2.035 / 2.072 / 2.061 | | D (∀ λ) | [R3-branch-*] T3r_branches, T3r_step_lambda_bracket |
| R10 | MoE B = 16: 2.325 / 3.636 / 4.638 (uniform / Zipf 1.0 / Zipf 1.5); 2.728 / 4.144 / 5.173 on the direct path | | D (D(16) EMPIRICAL — H9) | [R3-B16-*] T3r_moe_families |
| R11 | regime map, 24 cells: W everywhere except MoE 1M (ATTN:KV 86.0 %), dense 1M KV-int8 (ATTN:VEC) and the MEM cells; bounce ≤ 0.16 % (proof: **≤ 0.18 %**, MoE 4k), quant 0.9 / 3.5 %, launch 2.8 / 13.0 % | | D → CORRECTED | [R3-regime] T3r_regime_* |
| R12 | L*_KV on the block model = (nb* − 1)·512 + 16, nb* = ⌈(T_w − fixed)/blk⌉: dense 753 168 (256 KiB) / 743 440 / 684 560 / 777 232 / 259 088; KV-int8 1 006 608 at every G (vector-bound), 1 507 344 fixed-shift; MoE 131 600 / 129 552 / 119 312 / 135 696 / 45 072 (anchored), 108 048 … (direct), 106 000 … (pp); iff over every L (proof: non-monotone — L* is where every longer L is attention-bound; first attention-bound 131 103 / 1 006 102 / … in 13 of 40 cells) | iff | D → CORRECTED | [R3-Lkv-*] [R3P-Lkv-*] T3r_Lstar_kv, T3r_Lstar_* |
| R13 | attention-bound iff G ≤ G*: dense 32k / 128k / 1M 73 / 294 / 2 354 tenths; MoE 32k 420 (511 direct), **128k 1 683 (2 047 direct)**, 1M 13 460 (proof: **the 1M cells are attention-bound at every G** — no iff line); MoE 128k: W by 16 µs (0.5 %) at 256 KiB, ATTN by 25 µs at 64 KiB, by 301 µs at 16 KiB; ATTN at every page size on the direct path (550 µs = 20.8 % at 256 KiB) | iff | D (∀ G) → CORRECTED (1M) | [R3-Gstar-*] [R3P-Gstar-*] T3r_fleet_G_*, T3r_fleet_G_1M_everyG, T3r_moe_128k_cells, T3r_moe128k_tie |
| R14 | softmax crossover: rows* = 32 (chain as specified) / 48 (fixed-shift) → dense t ≥ 2 / 3, MoE t ≥ 5 / 9; KV-int8: dense t = 1 / 2, MoE t = 1 / 5 | | D | [R3-tstar-*] T3r_tstar |
| R15 | P2P saving ≤ T_x = 236 / 220 µs; tensor-split 382.32 ms → 0.653 (6.2×) / 39.24 → 6.369 (3.5×) with 34 / 27 µs reductions; Π = 8 blocks 296.86 … 309.10 / 14.51 … 19.35 ms → 0.808 (7.7×) / 12.918 (7.1×); Σ blocks + λ = T_step exactly; balance loss 3.5 / 10.4 % | | D (premises as hypotheses) | [R3-whatif-*] T3r_whatif, T3r_pipelining_decomposition |
| R16 | megakernel: saves 54.60 / 15.28 ms per token, reductions +1.84 / +0.10 ms, 480 / 140 syncs; pays iff c_sync ≤ 109 903 / 108 430 ns (proof: a tie at 109 903 on dense, strict ≤ 109 902); cells at 2 / 5 / 20 µs: dense 0.107 / 0.106 / 0.106, MoE 2.019 / 2.012 / 1.979; V1 + V2 2.307 | iff | D (∀ c_sync) | [R3-mega-*] T3r_mega_threshold, T3r_mega_cells |
| R17 | instance fit: minimal x per die (‰) MoE 32k 182 / 170 / 170 / 182, 128k 244 / 232 / 232 / 244, 1M 827 / 816 / 816 / 827, B = 16 494 / 482 / 482 / 494; dense 32k 376 / 358 / 332 / 376, 128k 629 / 610 / 585 / 629; dense 1M infeasible at x = 1000 (KV 128.8 / 64.4 GB per position); every die at 85.9 GB; margin 2–30 MB; Δx = 23 / 21 ‰ per GB of overhead; weights(x) non-increasing → the minimal x is an iff | iff | D (overhead ASSUMPTION — H8/H11) | [R3-inst-fit-*] T3r_inst_fit, T3r_inst_dx, T3r_inst_dense_1M_infeasible |
| R18 | instance step MoE 32k 134.37 ms (W 88.60 + ATTN 22.73 + launch 18.01 + quant 4.89 + xch 0.12) → 3.720 (+106.4 %); ser cold 3.399 (proof: **3.128** on the 807 ns piece); anchored hot 3.391; overlapped 3.771; Zipf(1.0) 4.006; 4k / 128k / 1M 4.396 / 2.437 / 0.577; B = 16 4.035; dense 32k 3 223.48 → 0.155 (+49.0 %), ser 0.122 (proof: **0.100, a loss**), spec 0.349 / 0.374, 4k / 128k 0.168 / 0.122 | | D (popularity EMPIRICAL — H9) → ser CORRECTED | [R3-inst-*] [R3P-serpiece-*] T3r_inst_cells, T3r_serpiece |
| R19 | two instances beat one (MoE 32k, uniform, direct-path hot tier) iff the int4 core-slab time ≤ 1 406 404 ns (≥ 0.7 GB/s/core); measured 5.3 is 7.1× inside; 4.0 / 3.0 / 2.0 / 1.0 GB/s/core → 3.521 / 3.282 / 2.890 / 2.127; all-int4 2.646 dominated; proof: H10 as the variable c — ≤ 1 394 680 ns at the card-scale c = 1.990, and at 5.3 GB/s/core iff c ≥ 0.970 | iff | D (∀ T_cold, ∀ c) | [R3-inst-breakeven-moe-32k] [R3-inst-sens-*] T3r_inst_breakeven, T3r_inst_gain_measured (the 5.3 premise) |
| R20 | combinations: V3 + V2 4.170 / 0.157; + overlapped hot tier 4.234; Π = 8 of one chain = 3.4× / 5.2× the two-instance cell | | D | [R3-inst-combo-*] T3r_inst_vs_pipe |
| R21 | draft token 22 130 µs = 5 727 + 1 153 + 11 011 + 4 195 + 19 + 24; verify step 66.38 ms (33.35 pipelined, 41.34 megakernel, 53.80 without the pass); launch share 49.8 % | | D | [R3-draft] T3r_draft |
| R22 | dense spec: 0.168 / 0.227 / 0.308 at α = 0.5 / 0.7 / 0.9 (1.608 / 2.172 / 2.949×), best k = 7 → 0.238 (0.432); gain iff α ≥ 0.144 (τ > 1.1657); fixed-shift 0.184 / 0.248 / 0.337, k = 7 0.277 / 0.503, α ≥ 0.064 | iff | D (∀ α) | [R3-spec-dense-*] T3r_spec_dense, T3r_spec_dense_breakeven |
| R23 | MoE spec loss: uniform 1.034 / 1.397 / 1.897, best k = 1 → 1.745; loss iff α ≤ 0.866 (τ < 3.2667; proof: 0.866 gives 1.800), Zipf(1.0) 0.752, Zipf(1.5) 0.657; direct path 0.847 / 0.741 / 0.652; mechanism E₁ = 82.64 ms = 59.6 %, τ < 2.787 a loss | iff | D (∀ α, both directions) | [R3-spec-moe-*] T3r_spec_moe_loss, T3r_spec_moe_mechanism |
| R24 | rollout: 1 card 593.73 / 33.85 ms at 32k, 2 cards 1 187.48 / 67.72, 4 cards 2 387.22 / 138.68 (and the 4k / 128k cells); identity 4 × stage-1 + 12.29 = 2 387.23 exactly (MoE + 3.25 = 138.69); stage 2 = one instance: 3 223.48 / 134.37 ms | | D | [R3-rollout-*] T3r_rollout, T3r_rollout_identity |
| R25 | ladder expectations: H1 4 KiB 12 348 / 12 494 ns; H10 2.0× (14.880 vs 7.208 fleet tokens/s); H11 margin 24.5 MB; E38 47.19 ms / 2.44 ms between the readings | | D | [R3-ladder-*] T3r_ladder |
| R26 | risks: integrated chain 3 001.92 → 0.083 (−20.1 %) / 136.60 → 1.830; dense serial regime 2 953.41 → 0.084; MoE 128k 1.217 / 1.210 / 1.167 by page size (1.319 / 1.311 / 1.260 direct); MoE 1M 0.302 / 0.298 / 0.278, gather3x 0.114 (2.6×), KV-int8 0.385 / 0.530; dense 1M KV-int8 0.054 / 0.065 | | D | [R3-risk-*] T3r_fallbacks |
| R27 | memory tables, L_max, T_min_dies, T_serial, T_ceiling, T_order_*, T_mem_*: unchanged (no round-3 term enters them) | identity | D | [R3-mem] (the round-2 theorems stand) |

**Proof session (PROMPT-4P2, 2026-11-07): every row is proved in `proof/fleet.lean` (PROOF-COVERAGE-4.md, round-3 proof
session); R11, R12, R13 and the serial-chain cells of R18 are CORRECTED as marked, R9 / R16 / R23 sharpened.** The proposed names
map to families split per cell: T3r_regime_*, T3r_Lstar_*, T3r_fleet_G_*, T3r_tstar_*, T3r_branches_*; T3r_whatif = T3r_p2p_bound
+ T3r_tsplit + T3r_pipelining_*; T3r_moved = T3r_moved_cells + T3r_moved_pct + T3r_round2_limit; plus the PROMPT-4P2 targets
T3r_spec_dense_split, T3r_moe128k_tie (legs-conditional) and T3r_instance_margin.

Formalizable as iffs / bounds over one explicit variable: R2 (λ), R12 (L), R13 (G), R16 (c_sync), R17 (x), R19 (T_cold),
R22–R23 (α); the rest are cell identities on the imported DESIGN-3 round-3 model (transcribe `attn3_seq`, `step3`,
`inst_step3`, `die_block3` as functions of the same constants; their round-2 limits — λ = 91 000, G = 1746, c_q = 0, the
round-2 attention — must reproduce `T_step_*` of `proof/fleet.lean`, which `[R3-moved-*]` pairs cell by cell).


## Appendix A″ — round-5 claim ledger (`proof/fleet.py` `[R5-*]`, `proof/fleet.lean` `T5r_*`)

Every round-5 number of this document is printed by `proof/fleet.py` (`[R5-*]`, after the unchanged first 628 output lines) and fixed by a
theorem of `proof/fleet.lean`'s round-5 section (18 theorems; the cell theorems were generated from the script's own values). The ledger
rows F5-1 … F5-14 with their statuses are in PROOF-COVERAGE-4.md's round-5 section: the readings (T5r_readings), the affine step
(T5r_step_form, ∀ a), the cells (T5r_step_cells), the restated MoE-128k tie (T5r_moe128k_tie_measured / _everyG / _cells, ∀ G), the
lever ranking (T5r_levers, T5r_levers_moe32k_iff ∀ X, T5r_levers_overtake ∀ nb, T5r_nbF_lines ∀ L, T5r_retired, T5r_levers_context), spec
decode (T5r_spec, T5r_spec_steps, T5r_spec_thresholds ∀ α), B = 16 (T5r_B16), the instances (T5r_inst, ∀ c) and the dense 1M bound
(T5r_dense1M_bound). Hypothesis variables new this round: the per-layer attention a (the step's only attention input), the fused kernel's
residual X (E39), the block count nb (the per-block guard reading); the measured inputs are DESIGN-3 §6.0's (attention session 3).

## Appendix A‴ — round-6 claim ledger (`proof/fleet.py` `[R6-*]`, `proof/fleet.lean` `T6r_*`)

Every round-6 number of this document is printed by `proof/fleet.py` (`[R6-*]`, after the unchanged first 676 output lines) and fixed by a
theorem of `proof/fleet.lean`'s round-6 section (20 theorems, generated from the script's own values; 334 in all). The ledger rows F6-1 …
F6-14 with their statuses are in PROOF-COVERAGE-4.md's round-6 section: the readings (T6r_attn6), the cells (T6r_step6_cells), MoE 128k
(T6r_moe128k6, T6r_moe128k6_eff), the 32k tie (T6r_tie32k ∀ T, T6r_tie32k_cells), the 128k / 1M lines (T6r_tie_lines ∀ T,
T6r_tie_lines_cells), the banked fusion (T6r_realized), the post-fusion ranking (T6r_levers6, T6r_levers_moe4k ∀ T), spec decode
(T6r_spec6_steps, T6r_spec6_thresholds ∀ α, T6r_spec_dense_form ∀ v, T6r_spec_dense_line ∀ v, T6r_spec_dense_cells,
T6r_spec_dense_thresholds ∀ α), B = 16 (T6r_B16_6), the instances (T6r_inst6, T6r_inst6_c ∀ c). Resolved hypothesis: E39's residual X
(the fused cells are MEASURED). New hypothesis variable: the dense verify attention v (E41). The measured inputs are DESIGN-3 §6.0′'s
(kernel session 5).
