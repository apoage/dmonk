# DESIGN-3 — decode attention over the KV cache (gather → softmax → reduce), one die, 8 cores

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
`scores = q_h·k_l/√d`, `p = softmax(scores)`, `out_h = Σ_l p[l]·v_l`. Everything derives from HW-MAP.md (as of
commit f951a5c, the direct-load silicon sync), ISA.md, DESIGN.md (the dense decode pipeline this design reuses:
(16,16,128) i8/f16 MMA loop at 15 ns per call, DDR→L0B direct loads with one full barrier per 32 KiB tile at
174.6 GB/s flat m = 1..16, the A-pack §3.2 and C-drain §3.3 layouts) and DESIGN-2.md (the region-difference
accumulator reset §3.2, ladder E11–E13). Status tags: **M** measured (HW-MAP), **D** derived here by arithmetic
shown, **P** PRIOR, **A** explicit assumption with the experiment that measures it, **U** unmeasured and
branched (G, E, R, ρ32, R_drain, Z — every one has a probe in §8).

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
| ρ32 | f32 lane-rate penalty vs the f16 figure: 1 (same lanes/cycle) or **2** (operand-bound: same bytes/cycle) | **U** — E22 |
| E | vector exp: availability and rate; **c_exp** lane-equivalents per exp if native | **U** — E22; poly fallback costed exactly (§3.3) |
| R | cross-lane reduction (max): ISA.md lists none — **none is assumed**; elementwise tree + scalar tail costed (§3.3) | **U** — E22 |
| L_ld | S1→L0 loader 26.5 GB/s/core strict-serial | M |
| R_us→s1 | 250 GB/s/core (48–64 KiB tiles) | M |
| R_frac | COPY_FRAC software transform 7 GB/s/core | M |
| R_drain | L0C → US staged-read rate | **U** — DESIGN-2 E12; hidden iff ≥ 3.4 GB/s/core (§2.3); exposed rows use 10 GB/s (A) |
| Z | accumulator reset: flags ignored → the **region-difference** epilogue (DESIGN-2 §3.2) is assumed; a found reset mechanism removes 2 lane-ops per score and 96 KiB of US | **U** — DESIGN-2 E11 |
| G(P) | KV read rate at page size P: per-core time per page = P/21.825 + c_pg, **c_pg U** (0 / 0.5 µs / 2 µs bracket) | **U** — **E21, the single highest-value measurement** |
| T_launch | 91 µs launch + queue floor | M |
| L0A, L0B | 64 KB each | M |
| L0C | 256 KB; whole-slab accumulation works | M |
| US | 256 KB/core, ≥ 208 KB evidenced | P/M |
| S1 | ~1 MB | P |
| T_gemv | 398 µs = 67.11 MB / 168.5 GB/s, PROBLEM-3's "die-step class" unit for the attention fraction | DESIGN.md §7.1 |
| σ_s | scalar iteration cost, 2 ns budget | A — E22 |

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

**Predicted attention-step time, t = 1, headline shape** (`[A4-t1-*]`, in-kernel; wall = + 91 µs):

| L | KV bytes | G = stream 174.6 (64 KiB pages, c_pg = 0) | G = 149.7 (64 KiB pages, c_pg = 0.5 µs) | G = 58.2 (gather 3× slower) | worst vector corner (poly exp, tree max, ρ32 = 2) at G = stream |
|---|---|---|---|---|---|
| 4k | 16.8 MB | **103 µs** (162.6 GB/s eff.) | 119 µs | 295 µs | 132 µs (vector-bound) |
| 32k | 134.2 MB | **776 µs** (173.0 GB/s eff.) | 904 µs | 2 313 µs | 851 µs (vector-bound: 1.07× per block, +9.8 % on the step) |
| 128k | 536.9 MB | **3 082 µs** (174.2) | 3 593 µs | 9 232 µs | 3 317 µs |
| 1M | 4.295 GB | **24 606 µs** (174.6) | 28 698 µs | 73 803 µs | 26 324 µs |

The headline column is DDR-bound on every (E, R, ρ32) branch but one: with a native exp (any c_exp ≤ 56 with a native max, ≤ 51 with the tree — T3_cexp_threshold) or a
poly exp at the full f32 lane rate, and with or without a native max, the vector unit sits at 12–53 % of the
block period and the step is the KV stream (T3_t1_ddr_bound: hidden iff c_V ≤ 62 at ρ32 = 1, ≤ 30 at ρ32 = 2,
`[A4b-cV-threshold-*]`). The one corner that binds — no exp instruction **and** no reduction **and** f32 at
half the f16 lane rate — costs c_V = 33 lane-ops per (score, row) and is vector-bound by 6.9 % (`[A2-vec-poly_tree-half]`).
If the drain runs on the vector engine itself (not a separate path), that corner becomes 1 114 / 34 713 µs
(`[A4-…] drain on the vector engine`); on every other corner the drain is hidden (R_drain ≥ 3.4 GB/s/core).
Fraction of PROBLEM-3's 398 µs GEMV unit: **26 % / 195 % / 774 % / 6 182 %** at 4k / 32k / 128k / 1M (stream,
best corner) — attention is a bounded 1/4 of a GEMV at 4k and 2 GEMVs at 32k; beyond ~16k it is the step (§6.3).

**t = 16** (rows = 128 → two passes of 64 rows; `[A4-t16-*]`): 1 554 µs at 32k and 49.2 ms at 1M on the
native branch (DDR-bound at 2× the t = 1 bytes, 172.8 GB/s effective); 6.8 ms / 216 ms on the worst vector
corner (vector-bound 4.4×). The single-pass variant S4 (mt = 8, L0A and L0C exactly full, 128-token blocks,
§2.4) streams the KV once but is vector-bound by its merges: 1 032 µs / 32.4 ms (`[A4b-onepass-*]`) — a 1.5×
gain on the native branch only, gated on E24. The softmax crossover rows* (vector ≥ KV stream per block) is
112 / 80 / 48 / 32 rows at ρ32 = 1 and 64 / 48 / 32 / 16 at ρ32 = 2 for the (native, native) / (native, tree) /
(poly, native) / (poly, tree) corners (`[A3-rows*-*]`): at g = 8 a verify batch of t ≥ 2 is softmax-bound on the
ISA-as-written corner at the half f32 rate, and on the fully native corner at the full rate every t ≤ 16 stays
DDR-bound (two passes above t = 8; rows* = 112 is a single-pass quantity — T3_rows_star, round 2: not 128).

Ranking of the routes (expected t = 1 step at 32k, stream branch, and what each needs):

| # | Route | 32k, t = 1 | 1M, t = 1 | Needs | Risk |
|---|---|---|---|---|---|
| 1 | **M (this design): f16 KV, fractal pages, matrix scores + PV, online softmax** | **776 µs** | **24.6 ms** | f16 B-fragment geometry (E23); drain ≥ 3.4 GB/s/core (E12); c_V ≤ 30·(2/ρ32) (E22); G(64 KiB) (E21) | medium: one geometry hypothesis, one unmeasured rate on the hot path, the softmax op set |
| 1b | M with KV-int8 (per-token i8 K/V, i8×i8→i32 scores, P quantised to i8) — DESIGN-4's dense escape | 391 µs (DDR) / 851 (worst corner, vector-bound) | 12.3 ms / 26.3 | the settled i8 geometry (no E23), + per-token scale reels (+1 lane-op per score), numerics E27 | medium-high (accuracy) |
| 2 | M with S1-staged K/V through the serial loader (DESIGN-2's regime) instead of direct loads | 26.5 GB/s/core loader on 512 B/token = 19.3 ns/token vs 23.5 DDR → DDR-bound only if the loader overlaps (ping-pong, E13) | — | nothing new, but the measured direct path is faster and already built | low; fallback if direct loads fail E23/E24 |
| 3 | Vector-dot route (K^T layout, lanes = tokens, Muls + Add per d) | 0.505·rows·ρ32 × the KV time: ≥ 2× at g = 4, 4× at g = 8 | — | f32 Mul/Add rates | none; it is the floor at g ≥ 2 |
| 4 | Two-pass softmax (max pass over K, then exp + PV) | +50 % KV bytes at t = 1 (K read twice) | — | — | dead: the online merge costs 324 ns per block against 6 005 ns of re-streamed K (`[A5-online]`, T_online) |

**The single measurement: E21, the gather rate G(P) at 64 KiB pages.** It multiplies every cell of §6: the
design's page is 64 KiB (the measured 64 KiB copy granule and the maximal legal single transfer), and the model
`t_page = P/21.825 + c_pg` puts the stream rate at c_pg = 0, 149.7 GB/s at c_pg = 0.5 µs and 104.8 at 2 µs
(`[A1-G-64k]`); the "3× slower" risk framing is c_pg ≈ 6 µs at this page size. No other unknown moves the t = 1 headline by more than 9.8 % at 32k / 7.0 % at 1M (the vector corner,
T4_worst_overrun: 6.9 % per block plus 22.7 µs of fixed cost) unless the drain is on the vector engine (+43.5 % on
that corner only).
E22 (exp / reduction / f32 lane rate) is second: it decides whether verify batches (t ≥ 2..6 at g = 8) are
softmax-bound, and whether the t = 1 step on the worst corner is 776 or 851 µs.

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
k=128)`: one call per 16 tokens at d = 128. At d = 64 a single (16,16,64) call is the **illegal k = 64 shape**
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
at every G.

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

| Engine | Work per block of 512 tokens (per core, mt fragments) | Time | Share of the 12 011 ns block |
|---|---|---|---|
| **direct-load (copy-in)** | 4 K tiles + 4 V tiles of 32 KiB DDR→L0B, one full barrier each (the measured choreography); stream order K_b, V_{b−2}, K_{b+1}, V_{b−1}, … (V lags K by **two blocks**, §5) | 262 144 B / 21.825 GB/s = **12 011 ns** | 100 % — the roof |
| **matrix** | scores: 32 calls × mt (one per 16 tokens, A = ±Q_f, B = K call tile); PV: 32 calls × mt (8 per 128 tokens, A = P_f, B = V call tile) | 64·mt × 15 = **960·mt ns** | 8.0 %·mt |
| **vector** | drain C_s(b) 32 KiB·mt → US; difference with the stored negated snapshot (Z); block max (tree); shift; exp; Cast → P fragments (16 KiB·mt f16); f32 sum accumulate; merge of block b−2's PV partial (drain 8 KiB·mt, difference, scale, add) | (8 192·c_V + 7 000)·mt·ρ32 / 43.2 ns = **1 489·mt ns** (c_V = 7, ρ32 = 1) … **12 839·mt ns** (c_V = 33, ρ32 = 2) | 12.4 %·mt … 106.9 %·mt |
| **copy US→S1** | P fragments 16 KiB·mt (plain, 4 KiB pieces) | 16 384·mt / 250 GB/s = 66·mt ns (+ per-copy issue, U) | 0.5 % |
| **loader** | L0LOAD P: 4 × 4 KiB·mt S1→L0A | 16 384·mt / 26.5 = **618·mt ns** (serial) | 5.1 %·mt |
| **L0C drain** | 40 960·mt B (C_s 32 KiB + C_o 8 KiB) through the staged read | hidden iff **R_drain ≥ 3.41 / 6.83 / 12.28 / 16.37 GB/s/core at mt = 1 / 2 / 3 / 4** (T2_drain_threshold, an iff: 80 / 160 / 288 / 384 B per token — not 3.4·mt, the 256-token block at mt ≥ 3 amortises C_o over half the tokens); 4 096·mt ns at 10 GB/s | 0 % if separate and fast; 34.1 %·mt added to the vector engine if it is the vector engine's own path |
| **scalar** | 4 page-table lookups; 16 × 16 tree tail per fragment (256 compares); barrier issue | 256·mt·σ_s = 512·mt ns at σ_s = 2 ns (A) | 4.3 %·mt |
| **copy-out** | nothing per block; per step: out 4 KiB·mt, K append 8 × 32 B, V_tail row 256 B, every 16th token the 4 KiB V fractal tile | < 2 µs per step | ~0 |

Per step, fixed (`fixed=` in `[A4-*]`): the first block's softmax latency before the first PV plus the last
block's softmax + drain + merge after the stream ends = 2 vector blocks + 1 drain (7.1 µs best corner,
29.8 µs worst), the vector tail of the ≤ 15 newest tokens (scores and PV as 16-row Muls+Adds over K_tail/V_tail:
≤ 122 880·mt lane-ops = ≤ 5.7 µs·mt at ρ32 = 2, 0 when 16 | L, `[A6-kvwrite]`), and the launch floor (91 µs,
reported separately as wall). The in-kernel ceiling of the design is the KV stream itself: effective KV rate at
1M = 174.6 GB/s, at 32k 173.0 (the fixed 7 µs), at 4k 162.6 (`[A4-t1-*]`).

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
256 tokens, L0C exactly full — §4); t = 16 → rows = 128 → **two passes** of 64 rows, KV read twice: 1 554 µs at
32k on the native branch (`[A4-t16-32k-stream-nat_nat-full]`), DDR-bound at 172.8 GB/s effective.
**Variant S4** (one pass, mt = 8): L0A holds Q 32 KiB (no ±Q alternation) + one single-buffered P buffer of
32 KiB per 128 tokens = **64 KiB exactly**, L0C holds two C_s regions of 64 KiB and two C_o regions of 64 KiB = **256 KiB exactly** (T_buffers_s4), blocks
shrink to 128 tokens. The loader→MMA chain per 128 tokens is serial: 32 KiB at 26.5 = 1 236 ns + 64 PV calls
× 15 = 960 ns = **2 196 ns against 3 002 ns of DDR per 128 tokens (73.2 %)** (`[A4b-onepass-chain]`,
T4_s4_chain) — DDR-bound on that edge, but the merge (7 000·8 lane-ops) now recurs every 128 tokens and the
vector unit becomes the wall: 1 032 µs at 32k and 32.4 ms at 1M on the native branch (`[A4b-onepass-*]`,
1.5× better than two passes), and no gain on any other corner. S4 is gated on E24 (an L0A filled to exactly
64 KiB — the L0C "exactly full" erratum was cleared, L0A is unprobed) and loses the ±Q drift bound (it uses the
i8 variant's exact i32 difference or E11's reset).

---

## 3. Softmax strategy

### 3.1 Online, block-wise, with the rescale applied to the drained partial — never to L0C
L0C cannot be rescaled (no US→L0C write path; the matrix unit only accumulates), so a running output cannot
live in L0C across blocks. The design keeps the running state in US — per row r: max m_r (f32), partial sums
S_r (16 f32 lanes, reduced once at the end), running output O_r[d] (f32) — **O(rows·d) = 8 KiB·mt** — and lets
each block accumulate its own PV partial `O_b = P_b·V_b` in a fresh L0C region, with P_b = exp(S_b − m_b^new)
relative to the running max *after* the block. Merge per block (vector, 7 000·mt lane-ops, `MERGE_OPS` in attn.py — an ASSUMPTION, not itemised: T3_merge_threshold
shows the t = 1 cells are DDR-bound for every merge ≤ 461 574, and T3_merge_itemised that a count from this op list,
12 128, moves the t = 1 32k cell by 0.2 µs and S4 from 1 032 to 1 277 µs): `α_r = exp(m_r^old − m_r^new)` (16·mt lanes), `O ← α·O + (C_o(b) − snapshot_o)`, `S ← α·S + Σ_b`.
Exact: Σ_l p_l v_l with a common shift per row telescopes over blocks (T_online_exact, a finite-sum identity).

**Online vs two-pass** (`[A5-online]`, T_online): two-pass avoids the merge but re-streams K for the max pass:
+6 005 ns of DDR per block (128 KiB of K per core) against a 324 ns merge (ρ32 = 2) — online wins **18×** at
every L and t; the L-regime boundary PROBLEM-3 asks for does not exist for this design (both costs are per
block, L cancels — T_online_L_independent).

### 3.2 The per-block vector chain (every op is in ISA.md's list; nothing else is assumed)
Drained C_s block = [32 token-groups][16 rows][16 tokens] f32 = 8 reels of 1 024 lanes (mt = 1).
1. **Difference (Z branch):** `S = D_b + NegSnap[region]` (1 Add) and `NegSnap ← Muls(D_b, −1)` (1 Muls) —
   the region-difference epilogue of DESIGN-2 §3.2 in f32; with ±Q alternation per region visit the region
   content is a signed sum whose magnitude stays within ~√(blocks/3)·|s|_max (random-walk HYPOTHESIS measured by E26 — T_drift_1M: 683 visits per region, √683 × 32 = 832 ≈ 840 → f32 ulp
2⁻¹⁴ = 6·10⁻⁵ on a score, 10⁻⁴ class on p; the deterministic worst case over every sign pattern is 683 × 32 = 21 856
→ ulp 2⁻⁹ ≈ 2·10⁻³, T_drift_alt). 2 lane-ops per score.
2. **Row max (R branch).** No cross-lane op is listed. Elementwise tree over the reels: `max(a,b) =
   0.5·(a + b + |a − b|)` = Add, Muls(−1)+Add, And(0x7FFFFFFF), Add, Muls(0.5) = **6 lane-ops per pair**; reels
   8→4→2→1 (7 ops of 1 024 lanes), then 1 024→256 lanes (2 ops) → a [16 rows][16] reel; the last 16 lanes per
   row go to the **scalar unit** (256 compares, 512 ns at σ_s = 2 ns). ≈ 6 lane-ops per score. Needs a 32-bit
   And on f32 lane bits (E22 differencing; "no u8 And" is the only And erratum). Native reduce-max, if E22 finds
   one: ≈ 1 lane-op per score.
3. **Shift:** `X = S + ShiftReel` (1 Add), ShiftReel = [row constants −m_r^new repeated per 16-lane run],
   built per block by 16 Duplicate calls of 16 lanes + 3 copies (≈ 20 small calls, A).
4. **exp (E branch).** Native: c_exp lane-equivalents (U; 1 if full-rate). **Poly** (no exp instruction):
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

### 3.3 Numerics
Scores are f32 (exact products of f16 inputs, f32 sums over d ≤ 128); the shift makes every exp argument ≤ 0 so
no overflow is possible; P ≤ 1 in f16 (no saturation); O and S accumulate in f32 over ≤ 2²⁰ terms (relative
2⁻²⁴·√L class); out = O/S in f32 then one cast to f16 (E9's rounding-mode check applies). The i8 variant adds
per-token K scales (a reel per block, +1 Mul per score) and quantises P to i8 with the fixed scale 127 (p ≤ 1,
no max needed) — its accuracy is the open item of E27, not its rate.

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

### 6.1 t = 1 (rows = 8, mt = 1, one pass) — `[A4-t1-*]`

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

### 6.2 t = 16 (rows = 128, two passes of mt = 4, blocks of 256 tokens) — `[A4-t16-*]`

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
Per 398 µs "die-step class" unit (one 8192² W8 GEMV at 168.5 GB/s): **0.26 / 1.95 / 7.74 / 61.8** at
4k / 32k / 128k / 1M (t = 1, stream, native; `[A4-t1-*] x GEMV`). Attention equals one GEMV unit at
L_eq = **16 896 tokens** (`[A4c-Leq]`, T_crossover: the smallest 512-multiple whose step reaches 398 µs — 403 µs there, 391 µs at 16 384; proved both ways as an iff
over k for every 512·k, T_crossover). Over arbitrary L the model crosses at L ≥ 16 400 — the 33rd block is charged in
full from its first 16-token group (T_crossover_anyL; the partial-block charge is conservative by ≤ 12 µs); against
the measured kernel's 384 µs for the same 67.11 MB the crossover is 16 384 (T_crossover_384). Per *layer* the fraction depends on the layer's weight bytes: for DESIGN-4's dense layer (3.19 GB,
18.26 ms) it is 4.2 % at 32k and 135 % at 1M; for its MoE layer (serial regime, 3.21 ms) 24 % at 32k. So decode
is attention-bound above ~16k tokens per 8192² GEMV-equivalent of weights, by the KV bytes alone — no kernel
choice changes that ratio except KV-int8 (halves it) or page size (G).

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

Where the fixed costs matter: at 4k the 91 µs launch floor is 88 % of the 103 µs step (wall 194 µs) and the
pipeline fill/tail 7 %; at 32k 12 % and 1 %; at 1M 0.4 % and 0.03 % (`[A4-t1-*] wall`). Fusing the attention
launch with a neighbour (§10) is worth more than any kernel change below 8k tokens.

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
| **E21** | **G(P): the gather rate at page granularity — the single highest-value measurement** | 8 cores, each 2 048 pages of P bytes at pseudo-random 64 KiB-aligned addresses in a 4 GiB arena (the visit order is a fixed LCG seed, so host and device agree), P ∈ {4, 16, 64, 256, 1024 KiB} plus a sequential control; the kernel's own path: DDR→L0B direct 32 KiB tiles (or P-sized when P < 32 KiB), full barrier per tile, one (16,16,128) MMA per call tile into one C region; page content = a per-page integer pattern (column sums distinct per page index); the drained C is compared with the host's sum over the visited pages; 20 reps | a skipped, repeated, stale or mis-sized page changes the total (differencing by construction); c_pg = slope of time-per-page vs page size (T1_gather_cells fits it); a rate above the sequential control is itself a failure (a load that did nothing) | every §6 cell (×G); the runtime's page size (§10); whether the "3× slower" risk is real |
| **E22** | the vector op set behind the softmax: exp (existence, c_exp, accuracy), cross-lane reduce-max (existence), 32-bit And on f32 lane bits, Duplicate semantics, f32 Mul/Add lane rate (ρ32), scalar loop cost σ_s | (a) exp of an integer-valued lane set {0, ±1, …, ±20} with the result compared to the host at 10⁻⁶ (a no-op returns the input bits, a half-rate unit shows in the count-mode timing); (b) reduce-max on a reel with one planted maximum per row, moved between reps; (c) And(x, 0x7FFFFFFF) on negative f32 bit patterns — the result must equal |x| exactly; (d) count-mode f32 Mul/Add over 1024 lanes, 10⁴ calls, vs the measured f16 figure; (e) the polynomial of §3.2 on the same lane set vs the host, relative error must be ≤ 1.6·10⁻⁴; (f) 256-iteration scalar max over a US reel with a planted maximum, timed | unchanged bits = no-op (errata #1); wrong planted-max position = a reduction that is not a reduction; a 1025-lane call keeping the sentinel beyond lane 1024 (errata #3 margin check); poly error above the bound = a rounding-mode no-op (errata #6) in one of the ops | c_V (the §3.2 table row), ρ32, the t ≥ 2 regime map, the 776-vs-851 µs headline corner |
| **E23** | the f16 B-fragment geometry H-F16 (K and V tiles) and the drained-C → A-fragment identity | DESIGN.md E1's pack probe with f16 tiles: K tile with k[l][j] = ((7l + 13j) mod 15) − 7, A = all-ones row → C[0, l] = Σ_j k[l][j] exactly; variants: (i) a second pattern through the same L0B address; (ii) one-hot A rows e_j → C[0, l] = k[l][j] for every j (settles the A-fragment order for q and P); (iii) the 2 × (16,16,32) sequence at d = 64; (iv) V tile probe: P = one-hot in token l → out = v_l exactly; (v) the chain: drain C_s, cast, copy to S1, L0LOAD, PV call — with the identity-exp harness the result is (Q·Kᵀ)·V, exact | column (token) permutation → the fragment is not [16 n × 16 k]; e_j on the wrong k → the A pack differs from §3.2; (v) wrong → the drained C nesting is not the A nesting (then a 2D re-layout copy is needed, costed in §9) | the page layouts §1.2–1.3 (host packer change only, free) and the zero-copy P path |
| **E24** | the direct-load choreography at this kernel's tile mix (K and V tiles interleaved, 2-block V lag) and the two exactly-full cases (L0A at mt = 4 / S4, L0C at mt = 4) | E13(a)-style accumulating oracle with alternating K/V tile patterns X/Y through the same L0B half, 10⁴ tiles, expected total exact; then the same with L0A filled to exactly 64 KiB (Q 32 + P 32) and L0C to exactly 256 KiB, content-checked; positive control: one full barrier removed | any stale/skipped tile changes the total; exactly-full aliasing shows X's sum where Y's is expected; a watchdog hang on the exactly-full L0A kills S4; a passing positive control means the detector is blind | the 174.6 rate assumption for the attention tile mix (E21's control row measures it); S4 (§2.4); mt = 4 in one L0C pass |
| **E25** | the KV append path: 8 × 32 B K copies (c_copy), the US→DDR 2D variant, COPY_FRAC of the 4 KiB V_tail block into 8 fragments, V_tail/K_tail plain appends | write token l's k and v (two different value sets through the same page slot), run the identity-exp kernel over a 17-token L (one full group + a 1-token tail) → out must change with the appended values and equal the host; time 10⁴ appends | unchanged out = a silent no-op append (errata #1); a wrong fragment landing shows as a permuted v; c_copy > 1 µs blows the 8 µs per layer-step budget (§1.2) → use the 2D copy or batch K like V | the per-step write cost (§10), whether K also goes through a 16-token tail |
| **E26** | the Z branch: three-region rotation with the f32 region-difference, drift under ±Q alternation, R_drain, and the S1→US snapshot copy | 2 048 blocks of integer scores through 3 regions with ±Q, the difference of each block compared to the host exactly (f32-exact while |region| < 2²⁴, which the test keeps — then a second run with real-valued q, k to measure the drift against f64); drain 10⁴ × 32 KiB regions, timed, content-checked (DESIGN-2 E12 reused); snapshot round-trip US→S1→US compared | difference ≠ expected → the drain or the Sub path is broken; drift above 10⁻⁴ relative → smaller blocks or the i8 variant; R_drain < 3.4 GB/s/core → exposed-drain rows of §6; a drain that runs on the vector engine shows as vector-time additivity in E28 | the Z branch, the drain rows, whether mt ≥ 2 can use S1 for snapshots |
| **E27** | end-to-end numerics and determinism | random f16 q, K, V at L ∈ {1k, 4k, 32k, 128k} (1M on a die with the memory), t ∈ {1, 2, 4, 8, 16}, 20 reps per config, host f64 reference, relerr ≤ 10⁻³; L chosen with every residue mod 16 and mod 256 (tail and page-boundary cases); a positive control with A3 deleted; the i8 variant's accuracy on the same inputs | relerr > 10⁻³ (f16 P rounding, poly error, drift); any rep-to-rep bit difference = missing barrier; the control must show islands; an L ≡ 1 (mod 16) case that fails = tail path bug | ship/no-ship; the i8 variant's admissibility |
| **E28** | the 40 % number | 100 queued launches at L = 32k and L = 1M, t = 1 (and t = 16), random q per launch so a stuck kernel repeats an output, every output checked vs the host reference, 20 reps bit-identical on fixed inputs; per-engine timers read back (DDR idle fraction, vector busy) | any failed check voids the timing; DDR idle > 10 % with a passing check = the vector engine or the drain is the wall (classifies the corner of §6) | reported ms at 32k and 1M, in-kernel and wall (launch floor from DESIGN.md E0) |

Order: **E21 first** (it decides the page size the runtime must implement and moves every number), then E23 and
E24 together (the chain with the identity-exp harness: exactness before any transcendental), E22 (the
softmax op set), E26, E25, E27, E28. E22 is independent of E21/E23 and runs in parallel on a second core set.

---

## 9. Risk register and fallbacks

| Risk | Trigger | Impact (from the model) | Fallback |
|---|---|---|---|
| **No exp instruction** | E22(a) | the polynomial of §3.2: c_V 7 → 28 (native max) or 12 → 33 (tree): t = 1 still DDR-bound at ρ32 = 1; at ρ32 = 2 the ISA-as-written corner is vector-bound 1.07× (851 µs at 32k, 26.3 ms at 1M); verify batches vector-bound from rows ≥ 32 (t ≥ 4 at g = 8) | accept (costed); cut the clamp by a bounded-score contract with the model (|s| ≤ 22 + m is false in general, so only as a documented option); run the tree in f16 if a 16-bit And is proven (saves ≈ 3 lane-ops at ρ32 = 2) |
| **No cross-lane max / reduce** | E22(b) | the tree (+5 lane-ops per score) and a 256-compare scalar tail per block (512 ns at σ_s = 2 ns; 4.3 % of the block period — scalar-bound iff σ_s ≥ 47 ns, T2_sigma) | accept (costed); if the 32-bit And is also missing: max(a, b) via `Cast f32→f16→f32` saturation tricks is **not** assumed — the remaining route is the scalar max over all 8 192 scores per block (16 µs at 2 ns: scalar-bound 1.36×) |
| **Gather 3× slower than stream** (c_pg ≈ 6 µs at 64 KiB) | E21 | every cell ×3 (2.3 ms at 32k, 73.8 ms at 1M) | the page size is the lever: 256 KiB pages give 149.6 at the same c_pg = 2 µs and 1 MiB pages 167.6 (`[A1-G-*]`); the tail waste per sequence is (P_tok − 1) tokens × 4 KiB per layer (16 pages per layer: 4 MiB at 256 KiB pages, 16 MiB at 1 MiB pages — T1_tail_waste); if G is low at every page size, the bound is DRAM behaviour, not the layout, and the KV-int8 variant halves the bytes |
| f32 lane rate half the f16 rate (ρ32 = 2) | E22(d) | all vector shares double; the §3.2 table's right column | compute the max tree and the shift in f16 after one cast (needs the 16-bit ops proven: errata #4 class) |
| L0C → US drain slower than 3.4 GB/s/core, or on the vector engine | E26 / E28 | exposed: +4 096·mt ns per block at 10 GB/s = +34 % if serialised with the vector work (1 114 µs at 32k on the worst corner; 776 unchanged on the native corner because 95 + 262 µs < 769) | drain only the used rows through the 2D row read (half the bytes at t = 1, rows = 8) at the cost of a 2D re-layout of P (US→S1 2D copy, E5-class, 32 B runs at stride 512 B) |
| f16 fragment is not [16 n × 16 k] | E23 | wrong scores (column permutation) — detected, never silent in the oracle | host/runtime packer change (free); if the drained C nesting ≠ the A nesting, add a 2D copy per P fragment (4 KiB·mt per 128 tokens; at 7 GB/s COPY_FRAC worst case 585 ns per 3 002 ns of DDR = 19.5 %, hidden on the copy engine) |
| Accumulator cannot be reset (Z) and the f32 drift bound fails | E26 | the difference epilogue is the design; drift ≤ 10⁻⁴ by the √-bound | the KV-int8 variant (exact i32 difference, DESIGN-2's proven path) or E11's reset — NOT smaller blocks: halving the block doubles the visits per region and raises both bounds (T_drift_blocks: 1 366 visits, random-walk 1 152 → ulp 2⁻¹³) |
| US budget (208 KiB + 64 B at mt = 1 as tabled vs 208 evidenced — T_buffers_us) | E7-class aliasing probe | snapshots cannot stay in US at mt ≥ 2 | snapshots in S1 (E26 proves the copy); Z-reset branch frees 96 KiB |
| **H_kv = 1 (degenerate GQA)** | shape | one KV head: all 8 cores split L (block-round-robin, ±1 block imbalance); rows = t·H_q per core (e.g. 32 at t = 1 for H_q = 32 → mt = 2; t = 16 → 512 rows = 8 passes); KV bytes are 1/8 of the headline shape so the DDR time per pass is 1/8 and 8 passes cost the headline's bytes; the 8 per-core (m, S, O) partials (16·mt rows × (1 + 16 + 128) f32 = 9 280 B = 9.06 KiB·mt each, T_hkv1_partials) are written to DDR and merged by the consumer kernel's prologue (the O-projection GEMM) — one extra launch only if the consumer cannot absorb it (+91 µs) | no change to the kernel; the merge is 8 × 9 280 B·mt of reads and ≈ 8·(2 048 + 272)·mt lane-ops |
| t·g > 64 rows (t = 16 at g = 8) | shape | two passes (KV read twice; 1 554 µs at 32k native) | S4 single pass (gated on E24, exactly-full L0A and L0C; merge-heavy 128-token blocks), or cap verify batches at t ≤ 8 per sequence at g = 8 (DESIGN-4 never runs a single sequence at t > 8) |
| 16-row padding at t = 1 (rows = g = 8, half the vector lanes compute padding) | design | 2× the necessary vector work at t = 1 (already in c_V's accounting) | the 2D row-selective drain + 2D P scatter if E5-class 2D copies exist at ≥ 1/8 of the DDR rate |
| K append cost (8 small copies per token per head) | E25 | ≤ 8·c_copy per layer-step on the writer core (8 µs at c_copy = 1 µs; 2 % of a 398 µs GEMV step) | one 2D copy, or a 16-token K_tail with COPY_FRAC like V (then the tail path covers K too — it already does) |
| d = 64 shapes | shape | 2 × (16,16,32) calls per 16 tokens (k = 64 illegal): 80 MMA calls per block, 20.0 %·mt instead of 8 % (T2_d64); KV bytes halve so every DDR cell halves and the vector share per byte doubles (c_V ≤ 30 / 14 at ρ32 = 1 / 2 for t = 1 DDR-bound) | accept; the i8/poly corners become vector-bound at t = 1 |
| Launch floor | DESIGN.md E0 | +91 µs per layer-step unless launches pipeline (88 % of the 4k step, 12 % at 32k) | fuse the attention launch with the QKV epilogue / O-projection prologue where the runtime allows |
| Errata compliance | — | #2: every transfer ≤ 32 KiB (tiles), ≤ 4 KiB (P pieces), ≤ 64 KiB (COPY_FRAC source); #3: all vector calls ≤ 1 024 lanes (the reels are exactly 1 024); #5: no f16 accumulation anywhere; #6: casts verified by E9/E22; #7: out leaves through US; #8/#14: full barriers on direct loads, pipe barriers A1–A13, no queue staging; #9: depths = counts; #12/#13: no i4 anywhere, i8×i8→i32 only in the variant; k = 64 never issued; n ≤ 16 per call; init flags not relied on | — |

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
   DDR into US and indexes it with the scalar unit. Page size is the single runtime knob E21 informs: if E21
   shows c_pg ≥ 0.5 µs, the pool should use 256 KiB or 1 MiB pages (§9); the kernel takes P_bytes as a parameter
   (it must be a multiple of 32 KiB so that tiles never straddle pages).
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

---

## Appendix A — claim ledger (for the round-2 proof session: `proof/attn.py` labels and proposed theorem names)

Round 2: theorem names below are the realised proof/attn.lean names; the row-by-row status is in PROOF-COVERAGE-3.md.
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
