# ERRATA-IMPACT — the errata #18–#31 audit of the five designs (PROMPT-6, 2026-11-08)

The attention-kernel sessions added fourteen silicon errata (#18–#31) to HW-MAP, corrected #3 (count-mode vector ops do not cap at 1 024
lanes) and widened #25 (DDR → S1-A-slot staging: only offset-0 4-KiB blocks and 32-KiB-granular offsets are proven). Every design here
except DESIGN-3's round-4/5 layers was written against errata #1–#17 only. This document sweeps DESIGN.md, DESIGN-2.md, DESIGN-3.md,
DESIGN-4.md and ALTERNATIVES.md against the new constraints, classifies every encounter, and ranks the corrections. The stage-overlap
pre-design that the same prompt asks for is DESIGN-3 §5.1 (E40).

**Classes.** **VIOLATES**: a pattern that cannot work as written. **UNSAFE-ASSUMPTION**: works by luck or an unmeasured margin, or the
design does not pin the form that decides it. **OBSOLESCENT**: the design paid for something a correction removes. **UNAFFECTED**: the
erratum's topic appears and the design is safe — said so, so nobody "fixes" it. **Live / record:** the designs keep superseded bodies
as their record; an encounter in a superseded body is classified but marked *record*.

**Status of the numbers.** No new silicon claims. Every MEASURED cell is untouched. Every corrected cell is either machine-checked by a
new theorem (core Lean 4.35; `T6a_*` in attn.lean and alt.lean, `T6f_*` in fleet.lean, `T6m_*` in moe.lean, `T40_*` for E40 — 71 in all,
0 axioms / sorry / native_decide, `lake build` clean) or a re-designation of a cell already proved (DESIGN.md m = 32 → T5_m32_restream;
the megakernel's 20 µs branch → T_alt_mega_cells, T3r cells). Every `.py` model's prior output is byte-identical (model 97, moe 72, attn
913, fleet 669, alt 166 lines); the new labels are `[PA-*]` and `[E40-*]`. Each correction is marked **audit** in place in its design,
with a PROMPT-6 banner at the top; the ledgers carry PROMPT-6 sections (PROOF-COVERAGE-2 PA2-*, -3 PA-* / E40-*, -4 PA4-*, -5 PA5-*).

**Method.** DESIGN.md, DESIGN-4 and ALTERNATIVES were swept by three read-only agents briefed with the rubric above (not with expected
findings); DESIGN-2 (whose agent's report was lost) and DESIGN-3 were swept here. Every finding below was checked against the cited
lines before it was applied; §5 lists the agent claims that were softened or rejected.

## 0. The ranked correction list (most severe first)

| # | Correction | Erratum, class | Where | Applied | What it moves |
|---|---|---|---|---|---|
| 1 | **The int4 cold tier accumulates f16 across barriers** — the unpacked tile is the B operand of f16 × f16 → f32 and its C chunk summed K = 4 096 across the per-piece barriers and the A re-lifts; the region-difference epilogue is itself such a chain. Fix: one fresh chunk per call, the partials summed in f32 on the vector unit | #19 VIOLATES (live, the #1-ranked variant) | ALTERNATIVES §2.1 (rank 1), DESIGN-4 §1.8 (V3) | audit marks; `[PA-cold-merge]` `[PA-inst-*]`; T6a_cold_merge_*, T6f_cold_merge_* | + 8 313 ns (throughput) / 32 614 ns (chained) per core-slab: ALT MoE 32k **3.878 → 3.849 / 3.766**, dense 0.156 → 0.153 / 0.144; DESIGN-4 V3 **3.720 → 3.693 / 3.617**, dense 0.155 → 0.150 / 0.142; serial branch MoE 3.239 → 3.202 / 3.145, dense −4.7 % → −6.6 % / −10.4 %. **Verdict survives**: T_instance_gain is an iff over every slab time; the merged slab is 6.6× / 5.9× inside the line (was 6.9×) |
| 2 | **Unary `Muls` is a silent no-op in live epilogues** — every routed MoE output, every R3 dense row would come out unscaled (invisible in a test at scale 1). Fix: Duplicate + binary Mul | #22 VIOLATES (live) | DESIGN-2 §3.2; DESIGN.md §7.5 (R3 dequant, UNSAFE as written); DESIGN-3 vector tail (VIOLATES), out = O/S; ALT §2.4 quantizer | audit marks; `[PA-epi]` T6m_epi; `[PA-tail-dup]` T6a_tail_dup | DESIGN-2: 4 → 5 ops per routed pair, 30.3 → 31.9 µs per step (0.2 %). DESIGN-3: the tail's Duplicate repair costs 4 096 small calls (190 µs per step) — the fix is the padded matrix-path tail (≈ 0.7 µs, UNMEASURED) |
| 3 | **A-operand staging at unproven offsets / block sizes** — slots 2–6 KiB apart, single 64 KiB blocks, a 56 KiB offset, 16 KiB single blocks (the measured class that zeroes A rows ≥ 2). Fix: 32 KiB legs at 32-KiB-granular offsets (the measured expert-kernel route) or 4 KiB blocks at offset 0 | #25 VIOLATES / UNSAFE (live) | DESIGN.md A ring (VIOLATES, slots 2–3 even at m = 1); DESIGN-2 x_q (VIOLATES at K = 7 168; rows ≥ 2 at K = 4 096); DESIGN-3 S1 P ring (VIOLATES) and §10.11's staging form; ALT §2.3 x, §2.1 f16 x; DESIGN-4 x_q at B = 16 / verify | audit marks; `[PA-xq]` T6m_xq; `[PA-s1-pring-*]` T6a_s1_pring | DESIGN-2 S1 at K = 7 168: 592 → 608 KiB; DESIGN-3 S1 P ring 8·mt → 64·mt KiB; DESIGN.md m = 32 quotes **154.5** (T5_m32_restream) until a probe certifies A residency |
| 4 | **The megakernel's rendezvous is a crossing** — each flag round ends in a scalar read after a fence (10–20 µs measured), so c_sync is not "µs class"; its consumer checksum is a fresh-reduction readback; its "norm and quantizer on its slice" needs full-row statistics core c does not hold; polls are unbounded; several GEMM nests share one launch | #29 UNSAFE → re-priced; #31 VIOLATES-class; #26 / #30 / #18 / #28 UNSAFE; #20 / #25 on q and x | ALT §2.3, DESIGN-4 V2 | audit marks; `[PA-mega-*]`; T6a_mega_20us, T6f_mega_20us | primary branch 20 µs: ALT MoE 2.101 → **2.058** (+10.2 %), dense 0.108 → 0.107; ALT-3+1 2.415 → **2.367**, ALT-2+3 4.369 → **4.291**; DESIGN-4 V2 2.012 → **1.979**, V3 + V2 4.170 → **4.098**. The iff lines (108.4 / 109.9 µs) are untouched; eight unbatched flag crossings per round would sit at them |
| 5 | **Fresh-reduction readbacks in the attention guard family** — E39's batched fence + flag lane races (session 4 killed it); the rowmax chain's cheaper crossing (a drain + 16 scalar reads) races; so would the lazy chain's first-block max read back at a fence | #31 VIOLATES (E39 as specified); UNSAFE (the rest) | DESIGN-3 §3.2 / §3.4 / §8; DESIGN-4 E39, the dense 1M KV-int8 bound | audit marks; `[PA-rowmax-det]` `[PA-firstmax-det]` `[PA-dense-1M-kvi8]`; T6a_rowmax_det, T6a_firstmax_det, T6f_dense1M_det | the deterministic crossing is 16 scalar-destination reduces (17 600 ns): rowmax ≥ 2 065.2 µs at 32k (the 10 318 ns bound stays valid; never-switch strengthens); round-4 fixed cost 19 328 → 34 018 ns (DERIVED); dense 1M KV-int8 ≤ 0.034 → **≤ 0.027**. E39 is resolved by the shipped deferred guard (round 6 folds its measured cells) |
| 6 | **B-slot ping-pong state carried across loop nests** — nest-local parities (DESIGN.md), an L0B rotation that restarts per expert while the copy ring runs on (DESIGN-2: shifts by 128 mod 3 = 2 per expert at K = 4 096), the hot → cold nest (ALT / DESIGN-4), the megakernel's nests, DESIGN-3's second pass / trip re-run / H_kv = 1 split | #30 VIOLATES (DESIGN.md at one tile per chunk; DESIGN-2) / UNSAFE | all five | audit marks | none (correctness) |
| 7 | **C (and A) operands addressed by view slices** — `C[f][t]`, `A[f]`, `C[r] + g·1 KiB`, the six regions, the C_s ring and C_o sets, the L0A P slots | #18 UNSAFE (VIOLATES if implemented by slicing) | DESIGN.md, DESIGN-2, DESIGN-3 (L0C done in round 4; extended to L0A / L0B), ALT / DESIGN-4 | audit marks | none |
| 8 | **The lazy-rescale family (ALT rank 9)** keeps P·V in one resident f16 L0C region and checks a per-block row max | #19 VIOLATES; #29 / #31 | ALT §2.6 | VOID status | the `[ALT-8-*]` cells (787 µs …) are void; the shipped deferred-guard kernel is the realisable form |
| 9 | **Bounce removal as a lever** needs legs = 0 — a proven US → S1 route for P that #20 rules out | #20 VIOLATES (as a lever) | DESIGN-4 §10″, DESIGN-3 round-5 bound | audit mark | ranking only (MoE 1M: the overlap bound is next) |
| 10 | **The quantizer family**: ALT §2.4's `Muls` + tree max → scalar tail at a fence + US → S1 A-slot extraction; DESIGN-4's E33 fallback; E38 measured at m = 1 only | #22 VIOLATES; #31 / #29 / #20 UNSAFE | ALT §2.4, DESIGN-4 §9 / constants, DESIGN-2 §3.1 option | audit marks | none (the measured 43.7 µs pass is the route) |
| 11 | **Copy forms**: stride fields are gaps (#23), element-form copies > 4 KiB land partially (#24), full 32 KiB queue → vector stages hang (#27) | #23 / #24 / #27 UNSAFE | DESIGN.md drain + y copy-out, DESIGN-2 drains / shadows, DESIGN-3 K-append strides / tails / out, ALT / DESIGN-4 cold-tier copies | audit marks | none (the production drain — 1 KiB chunks + the measured US → US strided extraction — pins them) |
| 12 | **Short-period verification patterns** alias rows / tokens | #21 UNSAFE (ladder) | DESIGN.md E1, DESIGN-2 E11, DESIGN-3 E23 + harness, ALT E30 / E31 / E34 | audit marks | none |
| 13 | **Scalar loops deeper than ~256** (spin polls, a 512-entry page-table window) | #26 UNSAFE | ALT §2.3 polls, §2.5 walk; DESIGN-3 §10.2 | audit marks | none |
| 14 | **Event-arm discipline** — a flag layered on a queue's own arm, two releases on one event ID, pre-arms at nest entry | #28 UNSAFE | DESIGN.md §4.2, ALT §2.1 / §2.2 chain, E40 | audit marks; E40's plan | none |
| 15 | **Small #29 crossings** — DESIGN-2's dispatch reads the vector-zeroed slot[] (one crossing per launch at kernel start), DESIGN.md's per-row sx reads, DESIGN-4's router | #29 UNSAFE | DESIGN-2 §4.2, DESIGN.md §7.5, DESIGN-4 constants | audit marks | none at an empty vector pipe (E14 measures) |
| 16 | **Corrected #3** — "≤ 1 024 lanes per call" cited as a cap; **corrected #14** — the exactly-full L0C "hangs" | OBSOLESCENT | all five; ISA.md; DESIGN-2 (W-dyn, G = 8) | audit marks | nothing was paid in any cost model (they price lane-ops or measured rates); upside only — a wider-call unpack if it is issue-bound (ladder L6-6) |

## 1. The erratum × design matrix (the worst live class per cell; V = VIOLATES, U = UNSAFE-ASSUMPTION, O = OBSOLESCENT, ✓ = UNAFFECTED, · = absent; *rec* = only in a superseded body)

| Erratum | DESIGN.md | DESIGN-2 | DESIGN-3 | DESIGN-4 | ALTERNATIVES |
|---|---|---|---|---|---|
| #3 corrected (lane cap per op) | O | O | O | O | O |
| #18 C-destination view offsets dropped (A ignored) | U | U | ✓ C (round 4) / U A, B | U | U |
| #19 f16 accumulation across a barrier / A re-lift | ✓ (i8); V *rec* (f16 routes) | ✓ (i8) | ✓ (round 4); V *rec* (Z branch, E21 f16 build) | **V** (V3 cold tier) | **V** (cold tier; lazy rescale) |
| #20 vector SRAM → S1 A-slot copy wrong | U *rec* (scheme P) | U (in-kernel quant option) | ✓ (round 4 bounce); U (q prologue) | V (bounce-removal lever); U (B-slot sibling) | V (q, extraction); U (B-slot sibling) |
| #21 host patterns alias tokens | U (E1) | U (E11) | U (E23, harness) | ✓ | U (E30 / E31 / E34) |
| #22 unary Muls no-op | **U → V** (R3 sx) | **V** (epilogue) | **V** (vector tail); U (out = O/S) | V (inherited: E33 fallback) | **V** (quantizer) |
| #23 srcStride 0 = contiguous (strides are gaps) | U (drain, y copy) | ✓ | U (K-append 2D copy) | · | U (scale broadcast) |
| #24 element copies > 4 KiB land partially | U | U | U | ✓ | U |
| #25 A-slot staging offsets / block sizes | **V** (A ring); U (A resident) | **V** (x_q) | **V** (S1 P ring); U (P form, q) | U (x_q rows ≥ 2, cold x) | U (megakernel x, cold x); ✓ (expert legs) |
| #26 scalar loops > ~256 | ✓ | ✓ (≤ 160) | U (page-table window) | U (polls, inherited) | U (polls, walk) |
| #27 32 KiB queue → vector staging hangs | U | U | ✓ (1 KiB drains) | U (cold tier) | U |
| #28 surplus event arm deadlocks | U | ✓ (strict pairs) | ✓; E40 plan | U | U |
| #29 per-block scalar crossing drains the pipe | U (sx reads) | U (dispatch, per launch) | ✓ (round 5); E40 rule | U → re-priced (V2) | U → re-priced (megakernel) |
| #30 B ping-pong state across nests; per-region bounds | **V** (T = 1) / U | **V** (L0B rotation) | U (passes, trip re-run, H_kv = 1) | U (cold nest, V2 nests) | U (hot → cold, nests) |
| #31 fresh-reduction readback at a fence | ✓ | U (option) | **V** (E39); U (rowmax, first-block max) | V (E39 pointer); U (KV-int8, top-k) | V-class (checksum); U (absmax, top-k) |

## 2. The per-design tables

Line numbers refer to each file as it stood before the PROMPT-6 marks (the marks are inline, so every quoted anchor is still findable).

### 2.1 DESIGN.md — single-die W8/W4 decode matmul

The live route is R3 (i8 × i8 → i32, per-token-quantized A). The banner already calls the ranking pre-measurement history; the loop / ring /
L0 structure, §2–§4, the R3 epilogue, the harness and E5 / E7 / E9 / E10 are the live parts.

| # | Erratum | § (line) | Encounter | Class | Live? | Severity | Fix (applied in place) | Moves | Silicon |
|---|---|---|---|---|---|---|---|---|---|
| D1 | #25 | §2 A ring (177), §1.2 (119), §3.2 (239) | the A ring (S1, 4 × 2 KiB·mt slots), A-ring[j mod 4], one COPY of 2 KiB·mt per chunk | **VIOLATES** | live | high — slot offsets 2·mt·(j mod 4) KiB are neither offset 0 nor 32-KiB-granular: slots 2–3 corrupt even at m = 1 | the whole A pack once in 32 KiB legs at 32-KiB-granular offsets with loader-only lifts (the measured expert-kernel route), or per-tile 4 KiB blocks at offset 0 | no rate | L6-1 |
| D2 | #25 | §2 A resident (178), §0 (66), §9 | A resident (m ≤ 32), 512 KiB at mt = 2, rows ≥ 2 live | UNSAFE | live (pre-measurement) | medium | residency gated on L6-1 with live rows ≥ 2 | **m = 32: 163.6 → 154.5** (T5_m32_restream, proved) | L6-1 |
| D3 | #18 | §1.2 (123), §2 | `MMA(C[f][t], A[f], B[t], …)` and the L0 slots read as view slices | UNSAFE (V if sliced) | live | high — every tile and fragment would land in chunk 0 / read fragment 0 | every L0 destination and operand is an explicit byte-offset tensor | — | a ≥ 2-tile × ≥ 2-fragment oracle |
| D4 | #30 | §1.2 (120), §2, §4.2 | `L0A[j mod 2]`, `L0B[t mod 2]` — nest-local parities | **VIOLATES** at one tile per chunk (T = 1: m ≥ 33 at N = 8192, every m at 2048); lucky at even T | live | medium-high — the prefetch lands in the slot in use (stale B or full serialization) | one global counter for loader and MMA, reset by each consumer nest | only if unfixed | a T = 1 check at N = 2048 (L6-9) |
| D5 | #30 | §6 (346), §1.2 (116) | "N_c a multiple of 256 … QKV-fused is fine" vs a loop bound N_c/N_slab | UNSAFE | live | medium — fused QKV at N_model = 4096: N_c = 1536 vs N_slab = 1024 drops columns or overruns into the neighbour's region | per-region bound, the last slab N_c − s·N_slab wide | — | — |
| D6 | #22 | §7.5 (431), §0 (78) | "dequant y = sx[m]·s[n]·C … plus one per-row scalar" | UNSAFE (V if a unary Muls) | live (R3) | high — y off by sx[r], invisible at sx = 1 | Duplicate(sx[r]) + binary Mul, or v_r = sx[r]·s[n] built once per launch | — | an E9 control with distinct sx per row |
| D7 | #29 | §7.5 (431) | the per-row sx read as a scalar | UNSAFE | live | medium — a crossing per row if vector work is in flight | read sx[0..m) once under B7 | — | — |
| D8 | #23 | §3.3 (245, 248) | 2D staged drain read "at stride 1024 B"; the 32 KiB batched y copy-out | UNSAFE | live | medium — strides are gaps (960 B, not a 1 024 B pitch); the y copy needs a dst gap (N − N_c)·2 | the production drain (whole 1 KiB chunks + the measured US → US strided row extraction); y as a blocked copy | drain bytes per slab +0.4 µs | — |
| D9 | #24 / #27 | §2 drain staging (183), s load (115) | 2 × 32 KiB drain slices; the 12 KiB fused-QKV s load | UNSAFE | live | medium — element copies > 4 KiB land partially; a 32 KiB queue → vector stage hangs | 1 KiB-chunk drains read from the drained queue tensor; plain / ≤ 4 KiB element loads | — | — |
| D10 | #28 | §4.2 (291) | queue mechanics + explicit flags on the same edges; B3's two releases | UNSAFE | live | medium — a surplus arm deadlocks intermittently | one mechanism per edge; distinct event IDs for B3's releases (legal per #14) | — | a ≥ 100-rep hang soak |
| D11 | #21 | E1 (454), harness (447) | `b[k,n] = ((7k+13n) mod 31) − 15` | UNSAFE | E1 record; harness live | medium — b[k + 64, n] = b[k, n + 13]: a chunk transposition reads as a column permutation | seeded pseudo-random integers, no period ≤ max(K, N_c) | — | — |
| D12 | #19 | §0 (79), §1.4, §5(a), E1(iv) | R1b / R2 f16 × f16 accumulation over K; the f16 two-chunk oracle | VIOLATES | record | high for those routes | fresh C + a vector / host f32 sum | R1b's vector load ≈ 48.8 → ≈ 61 % (still DDR-bound) — record only | — |
| D13 | #19 | §0 (58), §3.4 | "f32 accumulation in L0C over the full K" on i8 × i8 → i32 | UNAFFECTED | live | — | wording: i32, #19 is f16-only | — | — |
| D14 | #20 | §1.4 scheme P (162) | partials parked in S1 via US | UNSAFE | live but moot (L0C 256 KiB measured) | low | drop scheme P or park via DDR | — | — |
| D15 | #3 corr. | §3.3 (247), §7.5, E9 (463) | "= errata-3 limit", "1025-lane truncation" | OBSOLESCENT | live / record | low — a row is ≤ 1 024 lanes and the model has no per-call term | hygiene wording; re-aim E9 at isolated width probes | — | L6-6 |
| D16 | #22 | §5(b) (314) | "Mul-1/16" in the W4 arrange chain | UNSAFE | record | low | Duplicate + binary Mul | — | — |
| D17 | #31, #26, #29, #27, #20 (A built in US) | — | no reduce-max, no fence readback, no deep scalar loop; the next layer's A already bounces via DDR | UNAFFECTED / absent | — | — | — | — | — |

### 2.2 DESIGN-2.md — MoE grouped quant-GEMM (the expert kernel)

The live tuple is i8 × i8 → i32; the region-difference accumulator is i8 and #19 does not touch it.

| # | Erratum | § (line) | Encounter | Class | Live? | Severity | Fix (applied in place) | Moves | Silicon |
|---|---|---|---|---|---|---|---|---|---|
| M1 | #22 | §3.2 (237), §3.2 costs (255), §5.4 (372) | `Muls(row, score_{τ,e}·sx[τ])` | **VIOLATES** | live | high — every routed output silently unscaled | Duplicate(reel, score·sx) + binary Mul | **5 × 512 lane-ops per pair (59 ns, was 47); 30.3 → 31.9 µs per step at t = 16, D = 128** (`[PA-epi]`, T6m_epi) | E12's chain with a non-unit scalar |
| M2 | #25 | §3.1 (220), §5.2 (336), §6 (414) | "one DDR→S1 COPY of 64 KiB (two of 56 KiB at K=7168)" | **VIOLATES** as written | live | high — a single large block is the class that zeroes A rows ≥ 2 (wrong rows from t = 3: B = 16, verify); the second 56 KiB copy lands at a non-32-KiB-granular offset (every row, K = 7 168) | 32 KiB legs at 32-KiB-granular offsets — the measured production route: 2 legs at K = 4 096, 4 padded legs at K = 7 168 | **S1 592 → 608 KiB at K = 7 168** (`[PA-xq]`, T6m_xq); 0 at K = 4 096 | L6-1 with rows 0–15 distinct |
| M3 | #30 | §5.2 (343) | `L0B[(4j+p) mod 3]` restarts at every expert while the copy ring's q runs on | **VIOLATES** (when 4·K/128 mod 3 ≠ 0 — at K = 4 096 the rotation shifts by 2 per expert) | live | medium-high — the first piece of expert d + 1 can land in a slot still in use | one global piece counter `qp` across experts | — | E13(b) with ≥ 2 experts (L6-9) |
| M4 | #18 | §5.2 (345), §1.5, §3.2 | `MMA(C[r] + g·1 KiB, L0A[j mod 2], L0B piece …)` | UNSAFE (V if sliced) | live | high — a view-sliced region lands in chunk 0, collapsing six regions × 32 chunks | explicit byte-offset tensors for every C region, L0A slot and L0B piece | — | E11 with distinct per-region oracles |
| M5 | #27 / #24 | §3.2 (233), §6 new / diff, shadows | 32 KiB drain into US; 32 KiB shadow copies S1 ↔ US | UNSAFE | live | medium — a full 32 KiB queue → vector stage hangs; element copies > 4 KiB land partially | 1 KiB-chunk drains read from the drained queue tensor; plain / blocked shadow copies | — | a 10⁴-drain soak |
| M6 | #21 | E11 (591) | `b_e[k,n] = ((7k + 13n + 5e) mod 31) − 15` | UNSAFE | live (ladder) | medium — period 31 < the 32-row fragment: rows k and k + 31 alias | a prime period > K, or seeded pseudo-random integers | — | — |
| M7 | #29 | §4.2 (295) | the scan's first scalar read of slot[] zeroed by a vector Duplicate | UNSAFE | live | low — one crossing per launch at kernel start; cheap only with an empty vector pipe | keep the vector pipe empty there (or zero slot[] by DMA) | — | E14 with vector work in flight (L6-8) |
| M8 | #20 / #22 / #31 | §3.1 (221) | the in-kernel quantization option (row-max reduce, scale, A built in US) | UNSAFE | option (U) | low | the measured separate pass; if in-kernel: DDR bounce, Duplicate + Mul, a deterministic scale path | — | — |
| M9 | #19 | §1.5 (160), §3.2 | i8 region-difference accumulation across experts, barriers and A re-lifts | UNAFFECTED | live | — | — (do not over-correct: E21's depth-8 192 i8 proof) | — | — |
| M10 | #28 | §5.5 (383) | "strict flag → wait pair (never two producer flags without a wait)" | UNAFFECTED | live | — | it is #28's rule; #14 later licensed consecutive same-pair flags — the strict form stays safe | — | — |
| M11 | #26 | §4.2 | the dispatch scan ≤ 160 iterations | UNAFFECTED | live | — | (zeroing slot[] by scalar would be 512 sets > 256 — the vector Duplicate is right for #26, M7 is its price) | — | — |
| M12 | #3 corr. | §3.2 (235), E12 (592) | "8 calls of 1024"; "a sentinel beyond lane 1024" | OBSOLESCENT | live | low — the model prices lane-ops, nothing paid | hygiene; invert E12's expectation (probe per op) | — | L6-6 |
| M13 | #14 corr. (outside #18–#31) | constants (46), §5.1, §6, W-dyn, G = 8 | "filling L0C to exactly 256 KB hangs" | OBSOLESCENT | live | low — HW-MAP now records m = 64 across the full 256 KB as working | W-dyn's single slab and the G = 8 knob are no longer blocked | W-dyn D = 8 137.4 → 137.7 (not re-proved; marked) | — |
| M14 | #23, #31 (live path) | — | no blocked srcStride-0 copy; no fresh-reduction readback on the chosen path | UNAFFECTED / absent | — | — | — | — | — |
| M15 | the documented staging | §1.5 / HW-MAP 101 | the expert kernel's 2 × 32 KiB legs | UNAFFECTED (measured) — the text said "one COPY", not the granularity | live | — | the granularity is now stated in place (M2) | — | — |

### 2.3 DESIGN-3.md — decode attention

Rounds 4–5 already absorbed #18 (L0C), #19, #20, #21 (E27′), #29 and #30 (a risk row). This audit adds #31, the S1-side #25, #22 in the
tail, and the placements; the E40 pre-design is §5.1.

| # | Erratum | § (line) | Encounter | Class | Live? | Severity | Fix (applied in place) | Moves | Silicon |
|---|---|---|---|---|---|---|---|---|---|
| A1 | #31 | §3.2 round 5 (656), §3.4 (b) round 5, §8 E39, §6.0, §10.14 | the batched guard: per-block flag lanes from fresh reduce calls, read at a crossing | **VIOLATES** (killed on silicon, session 4) | live (the round-5 target) | high — nondeterministic | the shipped deferred guard (vector-only fold, ONE end-of-step read, whole-step re-run) — MEASURED in session 5; round 6 folds its cells | the fused reading is superseded by measurement (PROMPT-3R6) | — (measured) |
| A2 | #31 | §3.2 round 5 (673) | the rowmax chain's cheaper crossing: one drain + 16 scalar reads of fresh maxima | UNSAFE (the racing composition) | live (a bound) | medium | the deterministic crossing: 16 scalar-destination reduces = 17 600 ns | **rowmax ≥ 2 065.2 µs at 32k, ≥ 63.96 ms at 1M** (`[PA-rowmax-det]`, T6a_rowmax_det); the 10 318 ns bound stays valid | — |
| A3 | #29 / #31 | §3.4 (a) round 4 (740) | the first-block max's 16 maxima → the shift reel's Duplicate operands | UNSAFE | live (DERIVED model) | medium | 16 scalar-destination reduces once per step, before any vector work is in flight | first-block max 5 200 → 19 890 ns; round-4 fixed cost 19 328 → 34 018 ns (`[PA-firstmax-det]`, T6a_firstmax_det) — the measured cells carry the real cost | — |
| A4 | #25 | §4 round 4 (840), §2.2 round 4 (446), §10.11 (1386) | the S1 P ring 2 × 4 KiB·mt (slots 4 KiB apart); "one pack per block" | **VIOLATES** as laid out | live (design text; the measured kernel works) | medium-high — dst offsets ≥ 4 KiB corrupt; a 16 KiB single block zeroes rows ≥ 2 | each 4 KiB piece at offset 0 of its own 32-KiB-granular slot (or offset 0, stage → lift per piece) | **S1 P ring 8·mt → 64·mt KiB** (`[PA-s1-pring-*]`, T6a_s1_pring) | — |
| A5 | #22 | §2.2 fixed cost (435), §10.8, `tail4_ops` | the vector tail: 16-row Muls + Adds with a K / V scalar per (token, dim) | **VIOLATES** | live (spec; the measured kernel is causal-exact, so it does not use this form) | high — silent wrong attention on the newest tokens if built as written | the padded matrix-path tail (the open group's K call tile masked; the zero-padded V_tail COPY_FRAC'd into a scratch B tile) — the Duplicate repair would cost 4 096 small calls | Duplicate repair 190 054 ns per step (T6a_tail_dup) vs the 4 156 ns term; the matrix tail ≈ 720 ns, UNMEASURED | E25 / E40b |
| A6 | #22 / #31 | §3.3 (682) | out = O/S | UNSAFE | live | low | Duplicate(1/S_r) + Mul; S_r crosses at most once per step by a proven composition | — | — |
| A7 | #20 / #25 | §1.1 (265), §10.3 | the q prologue: COPY_FRAC from a US-resident q into the S1 A slot | UNSAFE | live (option) | medium | the QKV epilogue writes q in A-fragment order to DDR; staged per 4 KiB fragment at offset 0 / 32-KiB-granular | — | — |
| A8 | #18 | §5 round 4 (893), §2.2 round 4 | "every L0C destination is a byte-offset tensor" — A-side not stated | UNSAFE (text) | live | low (the measured kernel works) | extended to the L0A Q / P slots and the L0B halves | — | — |
| A9 | #23 | §1.2 (292) | the K-append 2D copy "8 runs of 32 B at stride 512 B" | UNSAFE | live (E25) | low | strides are gaps: srcStride 0 (the contiguous source, correct), dst gap 480 B | — | E25 |
| A10 | #24 | §4 round 4 (K_tail / V_tail 8 KiB, q 4 KiB·mt, out ≤ 16 KiB) | copy forms unstated | UNSAFE | live | low | ≤ 4 KiB element blocks or the plain / blocked form | — | — |
| A11 | #26 / #29 | §10.2 (1340), §4 window | a 512-entry page-table window indexed by scalar | UNSAFE | live | low | ≤ 256-deep nests; E40 fetches the step's tables once in the prologue | — | — |
| A12 | #21 | §8 E23 (1221), harness (1213) | `k[l][j] = ((7l + 13j) mod 15) − 7`; X / Y alternation (E24 / E24′) | UNSAFE | E23(iv) open; harness live | medium | prime periods > L; sum oracles paired with a position check | — | — |
| A13 | #30 | §2.4 passes, §3.4 trip, §9 H_kv = 1 | two passes at t = 16, the whole-step re-run, the per-core L split | UNSAFE (covered by the round-5 risk row, now placed) | live | medium | each re-establishes "tile 0 preloaded"; per-region bounds | — | — |
| A14 | #27 | §2.2 drain | the C_s / C_o drains | UNAFFECTED (1 KiB chunks, the measured form) | live | — | keep the form | — | — |
| A15 | #28 | §5 | no surplus arm specified; E40 pre-arms | UNAFFECTED; E40 plan | live | — | E40 §5.1 (d) rule 5 | — | — |
| A16 | #19, #20, #29 | rounds 4–5 | fresh chunks, the P bounce, the crossing model | UNAFFECTED (already absorbed) | live | — | — | — | — |
| A17 | #19 / #20 / #22 | §3.2 Z branch (553), poly exp, §2.2 round-2 P path, §1.4 E21 f16 build, §2.3 vector-dot route | NegSnap ← Muls, y/128 Muls, US → S1 P copy, accumulating f16 C regions | VIOLATES | record | — | marked record-only | — | — |
| A18 | #3 corr. | constants R_vec (154), E22 (1220), §9 compliance (1290) | "≤ 1 024 lanes per call"; the 1 025-lane sentinel test | OBSOLESCENT | live / record | low — the measured cells paid nothing; the chained corner charged per call | hygiene; the compliance row now lists #18–#31 | — | L6-6 |

### 2.4 DESIGN-4.md — the fleet planner

DESIGN-4 writes two kernel patterns of its own — the V3 cold tier (§1.8) and the KV-int8 route (§1.3) — and consumes the rest as cells,
which inherit their designs' audit status (attention: DESIGN-3; experts: DESIGN-2 / ALT-1; the megakernel: ALT-3).

| # | Erratum | § (line) | Encounter | Class | Live? | Severity | Fix (applied in place) | Moves | Silicon |
|---|---|---|---|---|---|---|---|---|---|
| F1 | #19 | §1.8 (360–363) | the V3 cold tier: f16 × f16 → f32 over K across the per-piece syncs and the A re-lifts; the region-difference epilogue | **VIOLATES** | live (V3 = build-order #1) | high | fresh chunks + the vector f32 K-sum (ALTERNATIVES' fix) | **V3 MoE 3.720 → 3.693 / 3.617**; R5 at c = 1.990 guarded 3.230 → 3.209 / 3.151, fused 3.567 / 3.495; **dense 0.155 → 0.150 / 0.142** (`[PA-inst-*]`, T6f_cold_merge_*) — V3 survives at every reading | L6-2 (E30) |
| F2 | #20 (B-slot sibling) | §1.8 (361) | the US → S1 copy into the B slot | UNSAFE | live | high for dense — a rate row, no content proof; the only proven fallback is a DDR bounce, which puts the slab in the serial-branch class (dense V3 turns negative there) | E30 content-checks it; the bounce carried as the fallback branch | conditional | L6-2 |
| F3 | #25 / #20 | §1.8 (362) | the cold tier's f16 A (x, 128 KiB) next to x_q | UNSAFE | live | medium | the producer writes x in A order to DDR; 32 KiB legs at 32-KiB-granular offsets (e.g. S1 + 64 KiB) | — | L6-1 |
| F4 | #30 / #18 / #28 / #27 | §1.8 | the cold nest after the hot nest in one launch; per-piece handshakes; DDR → US copies | UNSAFE | live | medium | the cold nest resets the L0B parity and preloads its own first piece; byte-offset C; one arm per handshake; copies < 32 KiB through queues | — | L6-9 |
| F5 | #29 | constants (155), V2 (927), §10″ context | c_sync branches 2 / 5 / 20 µs with 5 µs as the working reading | UNSAFE → re-priced | live | medium-high | the 20 µs branch is the primary reading (one batched crossing per flag round) | **V2 MoE 2.012 → 1.979**, V3 + V2 4.170 → **4.098**, dense 0.157 (`[PA-mega-*]`, T6f_mega_20us) | L6-3 (E31) |
| F6 | #31 / #26 / #30 / #22 | V2 (927) | the consumer checksum + bounded retries; in-kernel top-k; the poll loop; 4–6 GEMM nests per launch; the quantizer's Muls | UNSAFE (VIOLATES for the fused router as ALT-3 is written) | live (inherited) | medium | vector-side compare + one read per layer + re-run; the router behind a launch boundary or the deterministic dispatch; bounded polls; nest resets; Duplicate + Mul | the router boundary would cost 28 × 91 µs (not applied: the deterministic dispatch keeps it inside) | L6-3 |
| F7 | #31 | §1.3 (285–287), §3.6 (727–728), §9 (1196) | the dense 1M KV-int8 rowmax route's per-block crossing | UNSAFE | live (a bound) | high (the only dense-1M layout) | the deterministic crossing (16 scalar-destination reduces) | **≤ 0.034 → ≤ 0.027** tokens/s/card (`[PA-dense-1M-kvi8]`, T6f_dense1M_det) — shippable, UNMEASURED | — |
| F8 | #25 | V1 (926), §1.2, B = 16 / verify rows | x_q for rows ≥ 2 (DESIGN-2's "one 64 KiB COPY") | UNSAFE (inherited) | live | medium — silent wrong rows at B = 16 / t = 4 | the production 2 × 32 KiB legs; E29 checks rows 0–15 | — | E29 / L6-1 |
| F9 | #20 | §10″ (1277–1278) | bounce removal as the MoE-1M #2 lever | VIOLATES (as a lever) | live | low-medium | conditional on an unproven US → S1 route | ranking only | — |
| F10 | #29 / #31 | constants c_q (152), E38 (1123), §9 (1184) | the quant pass measured at m = 1 only; per-row absmax at rows > 1 | UNSAFE | live | low-medium | E38 adds rows 4 / 16 and a determinism check | — (UNMEASURED) | L6-7 |
| F11 | #31 / #26 / #29 | launches (172), F | the router's top-k; the dispatch's first crossing | UNSAFE | live | low | top-k vector-side with ids copied out; dispatch reads ids once per launch | — | L6-8 |
| F12 | #22 / #31 / #20 | §9 (1174, 1184) | the E33 fallback (ALT §2.4's fused quantizer) | VIOLATES (as ALT §2.4 is written) | live (fallback text) | low | Duplicate + Mul, a deterministic per-row scale, i8 A out through DDR in 32 KiB legs | — | — |
| F13 | #29 / #31 (production answer) | banner (6), §3.6, E39 (1136) | the guarded column = the legacy scan; E39 → the batched fence + flag | OBSOLESCENT by measurement / VIOLATES (E39 design) | live | high (headline) | the deferred guard (MEASURED 945.5 / 3 618.8 / 28 694 µs) is the shipped kernel — **round 6 (PROMPT-3R6) folds it; this audit marks, it does not pre-empt** | (round 6) | — |
| F14 | #19 | §1.3 (286) | KV-int8 scores and PV on i8 × i8 → i32 | UNAFFECTED | live | — | — (i8) | — | — |
| F15 | #20 | L48, L1177 | the planner reads legs = 2 | UNAFFECTED (applied correctly; 4 KiB pieces in #25's proven class) | live | — | — | — | — |
| F16 | #3 corr. | R_w4v (156), §3.5.3 | the 5.3 GB/s/core unpack (measured); the chained-latency corner | UNAFFECTED in the model / OBSOLESCENT (corner) | live / record | low | ladder probe for wider unpack calls (upside +1.6 % MoE / +4.5 % dense per +10 % on R_w4v) | — | L6-6 |
| F17 | #18 | §1.3 (281) | a double-buffered scores L0C region in the round-2 model | UNSAFE | record | — | tag | — | — |
| F18 | #23 / #24 / #21 | — | no blocked or element copy of its own, no planted pattern | UNAFFECTED / absent | — | — | — | — | — |

### 2.5 ALTERNATIVES.md — the cross-problem families

| # | Erratum | § (line) | Encounter | Class | Severity | Fix (applied in place) | Moves | Silicon |
|---|---|---|---|---|---|---|---|---|
| X1 | #19 | §2.1 cold path (167–168), §3.2 | the int4 tile as the f16 B operand, K accumulated across the per-piece barriers and the A re-lifts; the region-difference epilogue | **VIOLATES** | high (rank 1's only W4 path) | fresh chunks + the vector f32 K-sum | **MoE 32k 3.878 → 3.849 / 3.766**, Zipf 4.190 → 4.184 / 4.166, dense 0.156 → 0.153 / 0.144; serial MoE 3.239 → 3.202 / 3.145, dense −4.7 % → −6.6 % / −10.4 %; break-even 6.9× → 6.6× / 5.9× (`[PA-cold-merge]` `[PA-inst-*]`, T6a_cold_merge_*) — **the verdict survives** | L6-2 |
| X2 | #19 | E30 (225), §5 (546) | the E13-style accumulating oracle over 10⁴ f16 pieces | VIOLATES | medium — it fails by #19 in every regime; its "barrier removed must corrupt" control is confounded | a fresh chunk per piece + a running f32 sum | — | L6-2 |
| X3 | #20 (B-slot sibling) | §2.1 (167) | US → S1 → L0B for the unpacked f16 B | UNSAFE | high (dense) | E30 content check, a cold-pipe warm-up; the DDR bounce named as the fallback | conditional (the serial-branch class) | L6-2 |
| X4 | #22 / #23 | §2.1 (166) | the per-group offset / scale application | UNSAFE | medium — a unary Muls is invisible at scale 1; a srcStride-0 broadcast lands one block | Duplicate + binary Mul; distinct non-unit per-group scales in E30 | — | L6-2 |
| X5 | #24 | §2.1 (8 KiB f16 pieces), §2.3, §2.5 | copy forms unstated | UNSAFE | medium-low | plain form; element copies ≤ 4 KiB blocks | — | — |
| X6 | #25 | §2.1 (169–170), S2 | x_q 64 KiB + x f16 128 KiB co-resident in S1 | UNSAFE | medium | 32 KiB legs at 32-KiB-granular offsets (x_q is the measured route) | — | L6-1 |
| X7 | #28 / #30 | §2.1 (212), §2.2, S7 | the four-engine per-piece chain; hot → cold in one launch on the same L0B | UNSAFE | high (#30) / medium (#28) | arm once per handshake; at the boundary reset the parity, full barrier, preload the first cold piece | — | L6-9 |
| X8 | #21 | E30 (222–223) | power-of-two scales, integer offsets, 16 nibble values | UNSAFE | medium | PRNG nibbles, distinct per-group offsets, one-hot A rows, a transposed control that must fail | — | L6-2 |
| X9 | #3 corr. | §2.1 (209), §2.4, §3.2 | "unpack reels of ≤ 1 024 lanes" | OBSOLESCENT | low — priced from the measured 5.3 GB/s/core | hygiene; probe the unpack's ops wider | upside only (capped by the loader leg) | L6-6 |
| X10 | #19 (i8) | §2.2 (239), E29 | six 32 KiB i8 regions with the region difference | UNAFFECTED | — | — (do not over-correct) | — | — |
| X11 | #20 / #25 | §2.2 (242) | x_q 64 KiB resident | UNAFFECTED (the measured 2 × 32 KiB legs) | — | the granularity now stated | — | — |
| X12 | #18 / #27 / #29 | §2.2 (239, 249, 240) | region addressing; the 32 KiB drained region; per-expert id reads | UNSAFE | low-medium | byte-offset regions; drained-queue reads; all expert ids read in one crossing at launch | only if ids are read per expert | — |
| X13 | #29 | §2.3 (306), E31, App. | c_sync "µs class, margin ≥ 5×" | UNSAFE → re-priced | high | the primary reading is 20 µs; the flag fetch batched | **MoE 2.101 → 2.058, dense 0.108 → 0.107; ALT-3+1 2.415 → 2.367; ALT-2+3 4.369 → 4.291** (`[PA-mega-*]`, T6a_mega_20us) | L6-3 |
| X14 | #31 | §2.3 (313, 317), E31 (322–323) | the consumer's checksum compare; E31's pass criterion | UNSAFE (VIOLATES-class) | high — false mismatches mimic the visibility gaps E31 hunts | vector-side compare into a sticky lane, one read per layer, re-run on a mismatch; E31 checksums on the host | none | L6-3 |
| X15 | #31 / #29 / #22 + a dataflow gap | §2.3 (291–295) | "residual + norm (+ RoPE) and the §2.4 quantizer on its slice" | UNSAFE | high — the norm statistic and the absmax are full-row reductions core c does not hold | every core normalizes and quantizes the full x after the broadcast read (no extra round); a deterministic scale path; Duplicate + Mul | none at the minimal fix (a stats round would move the thresholds to 73 / 77 µs — not adopted) | — |
| X16 | #26 | §2.3 (290, 317), §2.5 (420) | the flag poll loop; the 1M page walk | UNSAFE | high (poll) / low (walk) | polls in ≤ 256-deep nests inside an outer loop; windowed walk | — | L6-3 |
| X17 | #30 / #18 / #28 | §2.3 (296), row 3 | one launch per layer: ≥ 5 GEMM nests | UNSAFE | high | the nest-boundary protocol: reset state, explicit byte offsets, arm once, per-region bounds | — | L6-3 |
| X18 | #20 | §2.3 (283), S2 / S3 / S6 | "q stays in US in A-fragment order … the q round trip disappears" | VIOLATES | medium | q and every vector-built A ride the DDR bounce (the COPY_FRAC still disappears) | — (alt3 counts launches only) | — |
| X19 | #25 | §2.3 (292–293) | the next GEMM's x (32 KiB f16 + 16 KiB i8) | UNSAFE | medium-high — a 16 KiB single block zeroes rows ≥ 2 (B = 16, spec) | 32 KiB legs at 32-KiB-granular offsets or 4 KiB blocks at offset 0 | — | L6-1 |
| X20 | #22 / #29 / #31 / #20 | §2.4 (340–346), E33, §3.2 / §3.4 | `y = Muls(x, s)`; tree max → scalar tail; the extraction into the S1 A-resident | VIOLATES (#22, #20); UNSAFE (#29 / #31) | medium | Duplicate + Mul; the measured pass's scale composition; every vector-built A via DDR → S1 legs | none (`[ALT-P-quant-*]` use the measured pass) | E33 ×20 |
| X21 | #19 / #29 / #31 | §2.6 (438–444), row 9, E35 | lazy rescale: P·V into one resident f16 L0C region; a per-block row-max check | **VIOLATES** | high for the mechanism (not a scored cell) | VOID as specified; the shipped deferred-guard kernel is the realisable form | the `[ALT-8-*]` cells are void | — |
| X22 | #30 | §2.5 (398), §2.6 (457) | two page-table walks / prefix then suffix = two nests on one ping-pong | UNSAFE | medium | one flat tile list, or a reset at the switch | — | — |
| X23 | #21 | E34 (427–428), E31, E33, E35 | sum-over-pages oracles; P(round, core) patterns | UNSAFE | medium — a permuted compaction passes a sum | prime periods + a position-weighted checksum | — | — |
| X24 | #25 / #23 | §2.5 (419) | extents read as 32 × 32 KiB B tiles | UNAFFECTED | — | — | — | — |
| X25 | consistency (not an erratum) | §3.2 (490), §5 E30 (546) | "2 × 4 KiB f16 out"; "ser 596 ns" — missed by the proof round | — | — | 8 KiB per piece; 807 ns (836 / 883 with the merge) | — | — |
| X26 | the "Must survive" column, every errata-survival paragraph | §1 (112–132), §2.x | stop at #17 | — | — | the banner points here | — | — |

## 3. Ladder rows deferred to silicon

Every correction that needs a measurement before it can be trusted gets a row; each row's failure is observable.

| # | Settles | Setup | Observable failure | Decides |
|---|---|---|---|---|
| **L6-1** | the A-slot staging forms (#25) the designs now rely on | stage an A with 16 distinct rows (prime-period values) at dst offsets {0, 2, 4, 6, 32, 56, 64, 96} KiB and block sizes {2, 4, 8, 16, 32, 56, 64} KiB, lift it, one MMA against a one-hot B, check every row, 20 reps | any row ≥ 2 zeroed or wrong at a form = that form is out | DESIGN.md's A ring / residency (and m = 32's 163.6 vs 154.5), DESIGN-2's x_q at K = 7 168, DESIGN-3's P slots, the megakernel's x, the cold tier's f16 x |
| **L6-2** | the cold tier under #19 / #20 / #22 / #30 (E30 rewritten) | (a) two f16 pieces into one C chunk across one loader sync must corrupt; the fresh-chunk merge must be exact ×20; (b) the US → S1 → L0B route for f16 B, cold and warm pipe, content-checked by differencing; (c) distinct non-unit per-group scales; (d) hot → cold in one launch with per-region oracles; then the chain regime (ovl vs ser) with the merge in the loop | (a) a passing cross-barrier chain = #19's measurement does not transfer (record it); (b) a mismatch = the bounce fallback (dense V3 turns negative); (c) unscaled lanes = a no-op multiply; (d) a stale first cold piece = #30 | the instance verdict's dense half; the merged slab time (8.3–32.6 µs per core-slab bracket) |
| **L6-3** | the megakernel rendezvous under load (E31 extended) | E31's rounds with the epilogue's vector work in flight at the rendezvous; 1 vs 8 crossings per round; checksums on the host or in a sticky vector lane; polls in ≤ 256-deep nests; a 2-nest persistent kernel with per-nest oracles | c_sync above 20 µs per round (the primary reading) or above 108 µs (the line); any nondeterministic verdict; a hang | V2 / ALT-3's primary branch; whether the fused router stays inside |
| **L6-4** | E40's gate φ and the pipelined kernel | DESIGN-3 §5.1 (f): E40a (the φ probe on the stream rung), then E40b (the macro-step kernel, bit-identical to the serial one) | φ above the k-lines; any bit difference from the serial output | the attention-side lever after fusion |
| **L6-5** | the unary-op family (#22) | Muls (the known no-op) and Adds (same form, unprobed) at non-unit scalars, against Duplicate + binary Mul / Add, 20 reps | Adds also a no-op → every Adds in the corpus is a #22-class violation | every scalar add-by-constant (the poly exp, the mask, offsets) |
| **L6-6** | the corrected #3 upside | the unpack's ops and reduce-max at 2 048 / 4 096 lanes in isolation, then the 5-pass unpack re-timed at the widest exact width | a wide call keeping sentinels = the op is capped; no speed-up = the unpack is not issue-bound | R_w4v (+1.6 % MoE / +4.5 % dense V3 per +10 %), the guard / merge call counts |
| **L6-7** | the quant pass beyond m = 1 (E38 extended) | the 43.7 µs pass at rows 4 / 16 and K = 16 384 / 53 248, 20-rep determinism, with the scale composition named | a per-row crossing (cost ∝ rows) or a nondeterministic scale | the B = 16 / spec cells (up to −1.2 %) |
| **L6-8** | the dispatch's first crossing (E14 extended) | E14 with vector work in flight at the scan's first slot[] read | an exposed crossing of 10–20 µs per launch | F's 2 µs exposed-dispatch budget |
| **L6-9** | the #30 nest boundaries | DESIGN.md at N = 2 048 (one tile per chunk); DESIGN-2 with ≥ 2 experts at K = 4 096 (the rotation shifts); the hot → cold launch | a stale or overwritten B operand at the first tile of a nest | the global-counter rule |

## 4. What did not change — the do-not-over-correct list

- **i8 accumulation vs #19.** DESIGN.md's R3, DESIGN-2's region difference, the hot tier, ALT-1's six regions, and the KV-int8 scores /
  PV all accumulate i8 × i8 → i32 across barriers and A re-lifts — exactly the pattern E21 measured exact to depth 8 192. #19 is f16-only.
- **The expert kernel's staging vs #25.** 2 × 32 KiB legs at 32-KiB-granular offsets is the measured production route; the audit only
  makes the documents say the granularity.
- **DESIGN-3's rounds 4–5.** Fresh chunk sets (#19), the P bounce with legs = 2 (#20), byte-offset C destinations (#18), prime periods
  in E27′ (#21), the crossing model (#29) and the #30 risk row stand as written.
- **Every MEASURED cell.** No silicon number moves; the corrected cells are DERIVED rows, re-designations of proved cells, or bounds.
- **The verdicts.** T_instance_gain (an iff over every slab time), T_megakernel (an iff over c_sync), the never-switch verdict, the
  MoE-128k attention-bound reading and the dense-1M bound all survive; three instantiations move (the cold-tier cells, the megakernel's
  primary branch, the KV-int8 bound), each in the direction the erratum predicts.

## 5. Method notes — agent claims that were softened or rejected

- *"Dense 1M KV-int8 has no shippable route"* (DESIGN-4 audit) → **softened**: the rowmax route is shippable deterministically through
  16 scalar-destination reduces per block (the legacy guard's proven component); the bound tightens from 0.034 to 0.027 instead.
- *"The 1M rowmax route is a 2 048-deep scalar loop (#26)"* → **rejected**: the legacy guard ran 8 scalar-destination reduces per block
  over 2 048 blocks at 1M bad-0; #26 concerns tight scalar set / get loops, not a block loop with scalar-destination reduces.
- *"Move the cold tier to i8 × i8 → i32"* (DESIGN-4 audit, option b) → **not adopted**: per-group (along K) scales need per-group
  partials anyway, so the i8 route saves no merge; the minimal fix is the fresh-chunk merge.
- *Megakernel c_sync at 40 / 60 µs, a stats round at 73 / 77 µs* (ALTERNATIVES audit) → **20 µs adopted** as the primary reading (one
  batched crossing per round at the band's top); the slice-only norm is fixed by redundant full-row work after the broadcast read, which
  needs no extra round, so the thresholds stay.
- *The cold-tier merge cost* → both audits estimated it differently (+3 % / +8.3–16.3 µs); this audit fixes one model for both documents:
  512 pieces × 512 f32 lanes per core-slab, 8 313 ns at the throughput convention, 32 614 ns with one chained 512-lane add per piece.
- *DESIGN-2's audit* was lost to a tool failure and redone here from the full text.
- *Out-of-scope notes kept for the record:* DESIGN.md's initVal scheme rests on flags the hardware ignores (HW-MAP); HW-MAP measures
  m ≥ 24 at 81 / 59 / 43 GB/s against DESIGN.md §7.2's m ≥ 32 rows; DESIGN.md E2's 10 k-deep spacing-0 chain would also break #16.
