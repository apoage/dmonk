#!/usr/bin/env python3
"""proof/attn.py -- executable cost model for DESIGN-3.md (decode attention over the KV cache).

Integer arithmetic only, in the conventions of proof/model.py / moe.py / fleet.py:
  rates : tenths of GB/s (1 B/ns = 1 GB/s decimal; bytes*10 // ns = tenths)
  bytes : binary KiB/MiB ; time : ns floored ; usR = (ns+500)//1000 ; pct = tenths of a percent
  lane-ops : vector work units; R_VEC = 43.2 G lane-ops/s/core = 432 tenths -> ns = ops*10 // 432
Run: python3 -I proof/attn.py   (Python >= 3.8, no dependencies). Labels [A..] are cited in DESIGN-3.md and
PROOF-COVERAGE-3.md; every label is transcribed 1:1 into proof/attn.lean (round 2).
Round 3 (2026-11-05): the season (v1) measurements (HW-MAP commit e9349c8) are added as the [R3-*] section at the end; every
round-2 label keeps printing its round-2 value so that `diff` lists exactly what moved (see [R3-moved-*]).
Round 4 (2026-11-07): the pre-implementation review + kernel session 1 (HW-MAP 423d433, errata #18-#21) are the [R4-*] section at the
end (fresh C chunk sets, the P bounce as `legs`, the round-4 chains and merge, append-then-attend tails, the online-chain rounding
bound, the planted sink, the C_o nesting, 256 KiB pages, the page-waste term); the [A*] and [R3-*] lines keep printing unchanged.
Round 5 (2026-11-07): the measured production kernel (attention session 3, HW-MAP 62e8137) is the [R5-*] section at the end (the t x L
sweep as MEASURED rows, the validation row, the guard scan and erratum #29's batched-crossing chain model, the unguarded / fused readings
per L, the phase-overlap and rowmax-crossing bounds, E26' closed); every earlier line keeps printing unchanged.
Round-2 changes: [A4b-drain-threshold] compares the mt=4 drain bytes with the mt=4 block time (164, not 82);
[A4b-G-threshold] prints the c_V=33 vector time; [A7-us-*] sums the section-4 table rows (the old [A7-sram]
omitted q row-major and the page-table window); [A7-l0a] is 16 KiB*mt (+-Q resident); new labels
[A0-pt-share] [A1-G-exact] [A1-G-roof] [A1-tailwaste-*] [A2-d64] [A2-sigma] [A4-worst-overrun] [A4b-cexp-*]
[A4b-merge-*] [A4b-s4-l0c] [A4c-Leq-anyL] [A4c-Leq-384] [A4d-fleet-G-*] [A7-drift-*] [A7-tree-ops] [A9-hkv1].
"""
KiB, MiB = 1024, 1 << 20

# ------------------------------------------------------------ Measured (HW-MAP) -----------------------------
R_GEMM   = 1746     # full W8 decode kernel, DDR->L0B direct + one full barrier per tile, flat m=1..16 (M)
R_READ   = 1813     # raw DDR->L0B direct stream 181.3 (M) -- the pure-read roof class; 173.8 is the r+w roof
R_DDR    = 1738     # LPDDR r+w stream roof (M); not used for the KV stream (read-only)
R_LOADER = 265      # S1->L0 loader, strict-serial, per core (M)
R_US_S1  = 2500     # US->S1 plain fill, per core, 48-64 KiB tiles (M)
R_FRAC   = 70       # COPY_FRAC software transform, per core (M)
C_MMA    = 15       # ns per (16,16,128) MMA call (M)
R_VEC    = 432      # tenths of G lane-ops/s/core, f16 count-mode (M)
T_LAUNCH = 91_000   # ns launch + queue floor (M)
L0A = L0B = 64 * KiB; L0C = 256 * KiB; US_EVID = 208 * KiB; S1_P = 1_000_000     # M / M / M / P
T_GEMV   = 398_000  # PROBLEM-3's "die-step class" unit: 67.11 MB / 168.5 GB/s (DESIGN.md route 1)
T_LAYER_DENSE, T_LAYER_MOE = 18_256_993, 3_207_719   # DESIGN-4 per-layer weight-stream times (fleet.lean T_layer)

# ------------------------------------------------------------ Unmeasured, carried as explicit variables ------
G_BR   = {"stream": R_GEMM, "page64k": None, "gather3x": R_GEMM // 3}   # page64k computed from c_pg below
C_PG   = {"zero": 0, "half_us": 500, "two_us": 2_000}                   # per-page fixed cost, ns (U, E21)
CV_BR  = {"nat_nat": 7, "nat_tree": 12, "poly_nat": 28, "poly_tree": 33} # vector lane-ops per (score,row) (D, §3.2; E/R branches U, E22)
RHO32  = {"full": 1, "half": 2}                                          # f32 lane-rate penalty vs the f16 40/cycle (U, E22)
R_DRAIN_A = 100     # tenths: 10 GB/s/core L0C->US staged read, ASSUMED for the exposed-drain rows (U, DESIGN-2 E12)
SIGMA_S = 2         # ns per scalar iteration, ASSUMED (U, E22)
MERGE_OPS = 7000    # vector lane-ops per block per A fragment for the online-softmax merge (A, §3.1 -- not itemised there; see [A4b-merge-*])

# ------------------------------------------------------------ Shape (headline) and design constants ----------
D, HKV, G_Q = 128, 8, 8          # head dim, KV heads (= cores), query heads per KV head
HQ = HKV * G_Q                   # 64 query heads
KV_TOK = 2 * HKV * D * 2         # 4096 B per token per layer (f16, K and V)
CORE_TOK = 2 * D * 2             # 512 B per token per core
BL = 512                         # tokens per block at mt <= 2 (online-softmax granule); 256 at mt = 3, 4 (L0C budget, section 4)
def BL_of(mt): return 512 if mt <= 2 else (256 if mt <= 4 else 128)   # mt 5..8 only in the S4 variant (128-token blocks)
PAGE = 64 * KiB                  # page bytes (design variable); tokens per page = PAGE // (2*D)
ROWS_PASS_MAX = 64               # rows per pass (L0A budget, §4: +-Q 8 KiB*mt + P 8 KiB*mt = 16 KiB*mt <= 64 KiB)

def ceil(a, b):   return (a + b - 1) // b
def tn(b, R):     return b * 10 // R                       # ns for b bytes at R tenths of GB/s
def usR(ns):      return (ns + 500) // 1000
def pct(n, d):    return (2 * n * 1000 + d) // (2 * d)      # tenths of a percent
def t10(x):       return f"{x // 10}.{x % 10}"
def rateT(b, ns): return (2 * b * 10 + ns) // (2 * ns)      # tenths, round half up

def G_page(P, c_pg):              # [A1] per-page model: t_core = P*8*10/R_GEMM + c_pg ; aggregate = 8*P*10/t_core
    t_core = P * 80 // R_GEMM + c_pg
    return 8 * P * 10 // t_core

def rows_of(t): return t * G_Q
def mt_of(rows): return ceil(rows, 16)
def passes_of(rows): return ceil(rows, ROWS_PASS_MAX)
def mt_pass(rows): return mt_of(min(rows, ROWS_PASS_MAX))

def L_matrix(L): return 16 * (L // 16)                     # tokens on the matrix path; tail = L mod 16 on the vector unit
def nblocks(L, mt=1):  return ceil(L_matrix(L), BL_of(mt))

# per-core, per-block costs (ns) for one pass with mt A fragments
def ddr_block_ns(G, mt=1): return tn(BL_of(mt) * CORE_TOK * 8, G)       # block bytes of the die at G
def vec_block_ns(cV, rho, mt, merge=None):
    m = MERGE_OPS if merge is None else merge
    return (BL_of(mt) * 16 * mt * cV + m * mt) * rho * 10 // R_VEC
def mma_block_ns(mt):      return mt * (BL_of(mt) // 16 + (D // 16) * (BL_of(mt) // 128)) * C_MMA
def loader_block_ns(mt):   return tn((BL_of(mt) // 128) * 4096 * mt, R_LOADER)
def drain_block_bytes(mt): return (BL_of(mt) * 16 * 4 + 16 * D * 4) * mt
def drain_block_ns(mt, Rd): return tn(drain_block_bytes(mt), Rd)
def scalar_block_ns(mt):   return 256 * mt * SIGMA_S                     # 16x16 tree tail per fragment

def tail_ops(L, mt): return (L % 16) * D * 16 * mt * 4                  # vector tail: scores + PV, Mul+Add each
def step_parts(L, t, G, cV, rho, Rd=R_DRAIN_A, i8=False, onepass=False, merge=None):
    rows = rows_of(t)
    p, mt = (1, mt_of(rows)) if onepass else (passes_of(rows), mt_pass(rows))   # onepass: mt<=8, L0A exactly full (S4 variant)
    nb = nblocks(L, mt)
    ddr = p * nb * ddr_block_ns(G, mt) // (2 if i8 else 1)
    vec = p * nb * vec_block_ns(cV, rho, mt, merge)
    mma = p * nb * mma_block_ns(mt)
    ldr = p * nb * loader_block_ns(mt)
    drn = p * nb * drain_block_ns(mt, Rd)
    fixed = 2 * vec_block_ns(cV, rho, mt, merge) + drain_block_ns(mt, Rd) + tail_ops(L, mt_of(rows)) * rho * 10 // R_VEC
    return dict(ddr=ddr, vec=vec, mma=mma, loader=ldr, drain=drn, fixed=fixed, passes=p, mt=mt, nb=nb)
def cands(s, drain):          # drain = "hidden" (separate engine, R_drain >= threshold) | "separate" | "same" (vector engine)
    c = {"KV stream": s["ddr"], "vector": s["vec"] + (s["drain"] if drain == "same" else 0), "MMA": s["mma"], "loader": s["loader"]}
    if drain == "separate": c["drain"] = s["drain"]
    return c
def step_ns(L, t, G, cV, rho, Rd=R_DRAIN_A, drain="hidden", i8=False, onepass=False, merge=None):
    s = step_parts(L, t, G, cV, rho, Rd, i8, onepass, merge)
    c = cands(s, drain)
    return max(c.values()) + s["fixed"], s, max(c, key=c.get)

LS = {"4k": 4096, "32k": 32768, "128k": 131072, "1M": 1 << 20}

# section-4 US table rows (bytes), per mt; win = page-table window buffers (the table declares depth 2)
def us_rows(mt, win=1):
    bl = BL_of(mt); cs = bl * 16 * 4 * mt; co = 16 * D * 4 * mt
    return {"drained C_s": cs, "NegSnap (US at mt=1, S1 above)": 3 * cs if mt == 1 else 0,
            "P staging": (2 if mt < 4 else 1) * bl * 16 * 2 * mt, "O": co, "partial drains": (2 if mt < 4 else 1) * co,
            "S acc": 4 * KiB, "shift reel": 4 * KiB, "alpha": 64, "K_tail": 4 * KiB, "V_tail": 4 * KiB,
            "q row-major": 4 * KiB * mt, "page-table window": 4 * KiB * win}
def l0c_bytes(mt): return 3 * BL_of(mt) * 16 * 4 * mt + 2 * 16 * D * 4 * mt
def l0a_bytes(mt): return 2 * 4 * KiB * mt + 2 * 4 * KiB * mt          # +Q,-Q resident + double-buffered P
def s1_bytes(mt):  return 2 * 4 * KiB * mt + (3 * BL_of(mt) * 16 * 4 * mt if mt >= 2 else 0)

# ============================================================ ROUND 3 (2026-11-05): season (v1) measured constants ===
# HW-MAP commit e9349c8 resolved every U quantity: E21 (gather rate per page size), E22 (exp, reduce-max, And, rho32,
# sigma_s), R_drain, host bounce. Every round-2 label above still prints its round-2 value (the retired branches are
# kept so the diff is explicit); the [R3-*] labels below re-derive the headline cells on the measured constants.
# --- E21: gather rate, measured (aggregate tenths GB/s; per-page ns per core; 20/20 reps exact) ---
G_SEQ  = {16*KiB: 1652, 64*KiB: 1690, 256*KiB: 1692}      # sequential control = the attention choreography's own stream basis
G_SHUF = {16*KiB: 1538, 64*KiB: 1670, 256*KiB: 1692}      # shuffled within a contiguous per-core arena (c_pg is a LOWER bound)
T_PG_SEQ  = {16*KiB: 793, 64*KiB: 3101, 256*KiB: 12391}   # ns per page per core, sequential
T_PG_SHUF = {16*KiB: 852, 64*KiB: 3140, 256*KiB: 12394}   # ns per page per core, shuffled
R_ATTN  = 1692          # the attention path's sequential stream rate at 256 KiB (174.6 minus the per-tile barrier + per-chunk MMA gap)
G_3X    = 582           # the retained "3x slower" what-if (a scattered cache, c_pg ~ 6 us at 64 KiB): no longer a measured branch
def cpg_meas(P):  return T_PG_SHUF[P] - T_PG_SEQ[P]                       # 59 / 39 / 3 ns at 16 / 64 / 256 KiB (HW-MAP quotes 38 at 64 KiB)
def cpg_vs174(P): return T_PG_SHUF[P] - P * 80 // R_GEMM                  # the same page against the round-2 model's 174.6 basis
def G_page3(P, c): return 8 * P * 10 // (T_PG_SEQ[P] + c)                  # measured sequential base + an extra per-page cost c
def G_tier3(L, c, P_e=MiB):   # two-tier (ALTERNATIVES 2.5): 1 MiB extents (per-page = 4 x the 256 KiB figure, + c) + 64 KiB tails (3101 + c)
    tok_e = (L // 4096) * 4096; n_e = tok_e // 4096; n_t = ceil(L - tok_e, 256)
    t_core = n_e * (4 * T_PG_SEQ[256*KiB] + c) + n_t * (T_PG_SEQ[64*KiB] + c)
    return 8 * L * 256 * 10 // t_core if t_core else R_ATTN
# --- E22: the softmax op set, measured (chained per-call ns = latency-bound upper bounds; lane-equivalent = 43.2 G lane-ops/s/core) ---
T_EXP, T_RM16, T_RM32, T_F16, T_F32, T_AND16 = 2728, 1819, 2514, 464, 636, 459   # tenths of ns per 1024-lane call
C_EXP100  = 1150        # exp: 272.8 ns x 43.2 / 1024 = 11.51 lane-eq per element (HW-MAP ~11.5; f32 exp ~11.4) -- hundredths
RHO32_100 = 137         # f32 / f16 chained op = 63.6 / 46.4 (round 2 bracketed 1 / 2)
SIGMA_S3  = 199         # tenths of ns per scalar compare (5.1 us per 256-read tail; round 2 assumed 2 ns)
R_DRAIN_M = {1: 1528, 2: 2223, 3: 2603, 4: 2855}   # tenths GB/s/core: L0C -> US drain measured at mt = 1..4 (round 2 assumed 10 GB/s)
MERGE_PACK = 25750      # lane-eq per block-fragment: the validation pack's merge-chain itemisation (commit e9349c8); round 2 assumed 7 000
LANE_PER_NS10 = 432     # lane-eq x100 per tenth of a ns (43.2 lane-eq per ns)
def call100(t10): return t10 * LANE_PER_NS10                                # lane-eq x100 of one chained call of t10 tenths-ns
# per-lane cost of one elementwise op, hundredths of a lane-eq: "T" = throughput convention (the 40-lane/cycle count-mode
# wall, f32 at the measured rho32 = 1.37), "C" = chained-latency convention (every 1024-lane call at its chained ns)
UNIT = {"T": (100, RHO32_100), "C": (ceil(T_F16 * LANE_PER_NS10, 1024), ceil(T_F32 * LANE_PER_NS10, 1024))}
def tree_ops(block):            # f16 6-op pair-max tree: block*16/1024 reels -> 1 reel (1024 lanes each), then 1024 -> 256 (512 + 256 lanes)
    reels = block * 16 // 1024
    return 6 * ((reels - 1) * 1024 + 512 + 256)
def chain100(block, mt, variant, conv, merge100):
    """vector lane-eq x100 per block for mt fragments.  variant 'rowmax' = DESIGN-3 section 3.2 as specified, on the measured op set:
    f32 difference (2), cast S -> f16 (1), f16 tree (tree_ops), 16 per-row reduce-max calls, shift reel (16 Duplicate + 3 copies = 20
    small calls, A), shift Add (1), exp (11.5), cast P (1), sum (1).  variant 'lazy' = fixed per-row shift (built once per step) with an
    overflow guard = one reduce-max call per P reel; no per-block row max, no alpha."""
    f16, f32 = UNIT[conv]; sc = block * 16
    if variant == "rowmax":
        el = sc * (2 * f32 + f32 + f32 + C_EXP100 + f32 + f32) + tree_ops(block) * f16
        calls = 16 * call100(T_RM16) + 20 * call100(T_F16)
    else:
        el = sc * (2 * f32 + f32 + C_EXP100 + f32 + f32)
        calls = (sc // 1024) * call100(T_RM16)
    return mt * (el + calls + merge100)
def merge_item(variant, conv):  # lane-eq x100 per block-fragment, itemised from section 3.1's op list at the measured constants
    f16, f32 = UNIT[conv]
    if variant == "rowmax":     # alpha = exp (1 call), alpha reel (20 small calls), O: diff Add + snap Muls + scale Mul + Add (4 x 2048), S: fold 512 + 256, scale 256, add 256
        return call100(T_EXP) + 20 * call100(T_F16) + 4 * 2048 * f32 + (512 + 256 + 256 + 256) * f32
    return (3 * 2048 + 512 + 256 + 256) * f32   # lazy: no alpha: O diff + snap + add, S fold + add
def vec3_ns(block, mt, variant, conv, merge100): return chain100(block, mt, variant, conv, merge100) * 10 // (R_VEC * 100)
def step3(L, t, G, variant="rowmax", conv="T", merge100=MERGE_PACK * 100, onepass=False, i8=False):
    rows = rows_of(t)
    p, mt = (1, mt_of(rows)) if onepass else (passes_of(rows), mt_pass(rows))
    bl = BL_of(mt); nb = nblocks(L, mt); Rd = R_DRAIN_M[min(mt, 4)]
    v = vec3_ns(bl, mt, variant, conv, merge100)
    ddr = p * nb * ddr_block_ns(G, mt) // (2 if i8 else 1)
    vec, mma, ldr, drn = p * nb * v, p * nb * mma_block_ns(mt), p * nb * loader_block_ns(mt), p * nb * drain_block_ns(mt, Rd)
    fixed = 2 * v + drain_block_ns(mt, Rd) + tail_ops(L, mt_of(rows)) * UNIT[conv][1] * 10 // (R_VEC * 100)
    c = {"KV stream": ddr, "vector": vec, "MMA": mma, "loader": ldr}
    return max(c.values()) + fixed, dict(ddr=ddr, vec=vec, mma=mma, loader=ldr, drain=drn, fixed=fixed, passes=p, mt=mt, nb=nb, vblk=v), max(c, key=c.get)
G3 = {"stream174": R_GEMM, "seq64k": G_SEQ[64*KiB], "shuf64k": G_SHUF[64*KiB], "p256k": G_SHUF[256*KiB], "shuf16k": G_SHUF[16*KiB], "gather3x": G_3X}
CORNERS3 = (("rowmax", "T"), ("rowmax", "C"), ("lazy", "T"), ("lazy", "C"))

if __name__ == "__main__":
    print("# proof/attn.py -- derived cells of DESIGN-3.md (round-2 cells, then the round-3 [R3-*] section)\n")
    print(f"[A0-shape] d={D} H_kv={HKV} g={G_Q} H_q={HQ}; kv_tok={KV_TOK} B/token/layer; per core {CORE_TOK} B/token; "
          f"block {BL} tokens = {BL*CORE_TOK//KiB} KiB per core = {BL*KV_TOK//KiB} KiB per die; page {PAGE//KiB} KiB = {PAGE//(2*D)} tokens")
    for k, L in LS.items():
        print(f"[A0-kv-{k}] L={L}: KV bytes/layer {L*KV_TOK} = {L*KV_TOK/1e9:.3f} GB; matrix-path tokens {L_matrix(L)}, blocks {nblocks(L)}, "
              f"page table {ceil(L, PAGE//(2*D))*2*HKV*8} B")
    print(f"[A0-pt-share] page table / KV = {2*HKV*8} B per {PAGE//(2*D)} tokens per die / {PAGE//(2*D)*KV_TOK} B = "
          f"{t10(pct(2*HKV*8*100, PAGE//(2*D)*KV_TOK))} hundredths of a percent = 0.012% (at 1M: {524288*10**6//(1<<32)} ppm)")
    # A1: gather model
    for P in (4*KiB, 16*KiB, 64*KiB, 256*KiB, MiB):
        print(f"[A1-G-{P//KiB}k] G(P) tenths: " + ", ".join(f"c_pg={c}: {G_page(P, cpg)}" for c, cpg in C_PG.items()))
    print(f"[A1-G-exact] at c_pg = 0 the exact rate is R_gemm = 1746 for every P; the 1752 / 1747 cells at 4 / 16 KiB are floor "
          f"artifacts (t_core floored to {4*KiB*80//R_GEMM} / {16*KiB*80//R_GEMM} ns from {4*KiB*80/R_GEMM:.1f} / {16*KiB*80/R_GEMM:.1f})")
    G_BR["page64k"] = G_page(PAGE, C_PG["half_us"])
    print(f"[A1-branches] G branches (tenths): {G_BR}; gather3x = c_pg {8*PAGE*10//G_BR['gather3x'] - PAGE*80//R_GEMM} ns at 64 KiB, "
          f"{8*4*KiB*10//G_BR['gather3x'] - 4*KiB*80//R_GEMM} ns at 4 KiB; G(4 KiB, 20 ns) = {G_page(4*KiB, 20)} = {t10(pct(G_page(4*KiB,20), R_GEMM))}% of stream")
    print(f"[A1-G-roof] what-if the KV stream ran at the raw direct-load roof 181.3 instead of the kernel's 174.6: "
          f"t=1 1M {2048*tn(2*MiB, R_READ) + 7074} ns vs {2048*tn(2*MiB, R_GEMM) + 7074} ({t10(pct(2048*tn(2*MiB, R_GEMM), 2048*tn(2*MiB, R_READ)))}%)")
    for P in (256*KiB, MiB):
        print(f"[A1-tailwaste-{P//KiB}k] P_tok = {P//(2*D)}; worst tail waste per layer = 16 (head, K|V) pages x (P - 256 B) = {16*(P - 2*D)} B = {16*(P-2*D)/MiB:.2f} MiB")
    # A2: per-block engine budgets at t=1 (mt=1)
    blk = ddr_block_ns(R_GEMM)
    print(f"[A2-block] block DDR time at 174.6: {blk} ns; per-core share {t10(R_GEMM*10//8//10)} GB/s; "
          f"MMA {mma_block_ns(1)} ns ({t10(pct(mma_block_ns(1), blk))}%); loader {loader_block_ns(1)} ns ({t10(pct(loader_block_ns(1), blk))}%); "
          f"US->S1 copy {tn(16384, R_US_S1)} ns; drain bytes {drain_block_bytes(1)} B -> hidden iff R_drain >= {rateT(drain_block_bytes(1), blk)} tenths GB/s/core; "
          f"at 10 GB/s exposed {drain_block_ns(1, R_DRAIN_A)} ns ({t10(pct(drain_block_ns(1, R_DRAIN_A), blk))}%); scalar tail {scalar_block_ns(1)} ns")
    print(f"[A2-sigma] scalar tail 256*sigma_s >= block iff sigma_s >= {ceil(blk, 256)} ns (256*46 = {256*46}, 256*47 = {256*47}); "
          f"scalar max over all 8192 scores at 2 ns = {8192*SIGMA_S} ns = {t10(8192*SIGMA_S*10//blk)}x the block")
    blk64 = tn(BL * 2 * 64 * 2 * 8, R_GEMM)
    print(f"[A2-d64] d=64: block DDR {blk64} ns; MMA calls per block = 64 scores (2 x k=32 per 16 tokens) + 16 PV = 80 -> {80*C_MMA} ns = "
          f"{t10(pct(80*C_MMA, blk64))}%; t=1 DDR-bound iff c_V <= " + " / ".join(f"{max(c for c in range(100) if (8192*c+MERGE_OPS)*rho*10//R_VEC <= blk64)} (rho32={rho})" for rho in (1, 2)))
    for cvk, cV in CV_BR.items():
        for rk, rho in RHO32.items():
            v = vec_block_ns(cV, rho, 1)
            print(f"[A2-vec-{cvk}-{rk}] vector per block (16 rows incl. padding): {v} ns = {t10(pct(v, blk))}% of the block DDR time")
    # A3: vector-route (dot products) ratio theorem; rows* softmax crossover
    for rk, rho in RHO32.items():
        print(f"[A3-vecroute-{rk}] vector-dot route / KV stream per token = rows*rho*4*d*R_gemm/(80*{CORE_TOK}*R_vec) -> "
              + ", ".join(f"rows={r}: {t10(r*rho*4*D*R_GEMM*10000//(80*CORE_TOK*R_VEC))}%" for r in (1, 2, 4, 8, 16)))
    for cvk, cV in CV_BR.items():
        for rk, rho in RHO32.items():
            r = 16
            while vec_block_ns(cV, rho, mt_of(r)) < ddr_block_ns(R_GEMM, mt_of(r)) and r < 1024: r += 16
            print(f"[A3-rows*-{cvk}-{rk}] smallest rows (multiple of 16) with vector >= KV stream per block: {r} (t >= {ceil(r, G_Q)} at g={G_Q}; mt = {mt_of(r)}, block {BL_of(mt_of(r))})")
    # A4: predicted step times
    print("\n[A4] t x L x branch -> step time (in-kernel, ns; wall = + 91 000), binding engine, parts")
    for t in (1, 16):
        for k, L in LS.items():
            for gk, G in G_BR.items():
                for cvk, rk in (("nat_nat", "full"), ("poly_tree", "half")):
                    T, s, b = step_ns(L, t, G, CV_BR[cvk], RHO32[rk])
                    Tx, _, _ = step_ns(L, t, G, CV_BR[cvk], RHO32[rk], drain="same")
                    print(f"[A4-t{t}-{k}-{gk}-{cvk}-{rk}] T={T} ns ({usR(T)} us; wall {usR(T+T_LAUNCH)} us) bind={b} "
                          f"passes={s['passes']} mt={s['mt']} ddr={s['ddr']} vec={s['vec']} mma={s['mma']} ldr={s['loader']} "
                          f"drain={s['drain']} fixed={s['fixed']} | drain on the vector engine T={Tx} ({usR(Tx)} us) "
                          f"| eff KV rate {t10(rateT(L*KV_TOK*s['passes'], T))} GB/s | x GEMV {t10(pct(T, T_GEMV))}%")
    for k in ("32k", "1M"):
        L = LS[k]; a = step_ns(L, 1, R_GEMM, 7, 1)[0]; w = step_ns(L, 1, R_GEMM, 33, 2)[0]; ws = step_ns(L, 1, R_GEMM, 33, 2, drain="same")[0]
        print(f"[A4-worst-overrun-{k}] worst corner / headline = +{t10(pct(w - a, a))}% ({w} vs {a} ns: per-block 6.9% + the fixed {step_parts(L,1,R_GEMM,33,2)['fixed'] - step_parts(L,1,R_GEMM,7,1)['fixed']} ns); drain on the vector engine +{t10(pct(ws - a, a))}%")
    # A4b: thresholds and variants
    for rk, rho in RHO32.items():
        cv = (blk * R_VEC // 10 // rho - MERGE_OPS) // (BL * 16)
        print(f"[A4b-cV-threshold-{rk}] t=1 vector hidden under the block DDR time iff c_V <= {cv} lane-ops per (score,row)")
        print(f"[A4b-cexp-{rk}] c_V = c_exp + R + 5 (difference 2, shift 1, cast 1, sum 1): t=1 stays DDR-bound iff c_exp <= {cv - 1 - 5} (native max, R=1) / {cv - 6 - 5} (tree max, R=6); "
              f"a native exp beats the 22-op polynomial iff c_exp <= 21")
    Gmax = BL * KV_TOK * 10 // vec_block_ns(CV_BR["poly_tree"], 2, 1)
    print(f"[A4b-G-threshold] t=1 is DDR-bound on the worst vector corner for every G <= {Gmax} tenths (block vector {vec_block_ns(33, 2, 1)} ns)")
    print(f"[A4b-drain-threshold] drain hidden iff R_drain >= " + "; ".join(f"{rateT(drain_block_bytes(mt), ddr_block_ns(R_GEMM, mt))} tenths/core at mt={mt} ({drain_block_bytes(mt)//BL_of(mt)} B/token: C_s {BL_of(mt)*16*4*mt//BL_of(mt)} + C_o {16*D*4*mt//BL_of(mt)})" for mt in (1, 2, 3, 4))
          + f"; same-engine cost at 10 GB/s = {t10(pct(drain_block_ns(1, R_DRAIN_A), blk))}% of the block at mt=1")
    for k in ("32k", "1M"):
        L = LS[k]
        for cvk, rk in (("nat_nat", "full"), ("poly_tree", "half")):
            T, s, b = step_ns(L, 1, R_GEMM, CV_BR[cvk], RHO32[rk], i8=True)
            print(f"[A4b-i8-t1-{k}-{cvk}-{rk}] KV-int8 (bytes/2): T={T} ns ({usR(T)} us) bind={b} ddr={s['ddr']} vec={s['vec']}")
        for cvk, rk in (("nat_nat", "full"), ("nat_nat", "half"), ("poly_tree", "half")):
            T, s, b = step_ns(L, 16, R_GEMM, CV_BR[cvk], RHO32[rk], onepass=True)
            T2, s2, b2 = step_ns(L, 16, R_GEMM, CV_BR[cvk], RHO32[rk])
            print(f"[A4b-onepass-t16-{k}-{cvk}-{rk}] one pass mt=8 (L0A exactly full): T={T} ns ({usR(T)} us) bind={b} ddr={s['ddr']} vec={s['vec']} mma={s['mma']} ldr={s['loader']} | two passes {T2} ({usR(T2)} us)")
    p_chain = tn(8 * 4096, R_LOADER) + 64 * C_MMA
    print(f"[A4b-onepass-chain] single-buffered P at mt=8: load 32 KiB at 26.5 = {tn(8*4096, R_LOADER)} ns + 64 PV calls {64*C_MMA} ns = {p_chain} ns per 128 tokens vs DDR {tn(128*CORE_TOK*8, R_GEMM)} ns -> {t10(pct(p_chain, tn(128*CORE_TOK*8, R_GEMM)))}%")
    print(f"[A4b-s4-l0c] S4 L0C: 2 C_s regions of {128*16*4*8//KiB} KiB + 2 C_o regions of {16*D*4*8//KiB} KiB = {(2*128*16*4*8 + 2*16*D*4*8)//KiB} KiB (exactly full); L0A: Q {4*KiB*8//KiB} + P {4*KiB*8//KiB} = {8*KiB*8//KiB} KiB")
    m_lim = ((blk + 1) * R_VEC - 1) // 10 - BL * 16 * 7     # exact: vec(m) <= blk iff (57344 + m)*10 < (blk+1)*432
    print(f"[A4b-merge-threshold] t=1 native corner stays DDR-bound for every merge count <= {m_lim} lane-ops per block-fragment "
          f"(vec = {vec_block_ns(7, 1, 1, m_lim)} ns at the limit, {vec_block_ns(7, 1, 1, m_lim + 1)} one above)")
    m_alt = 4 * 2048 + 3 * 1024 + 2 * 256 + 22 * 16
    print(f"[A4b-merge-itemised] a count from the section-3.1 op list (O: 4 x 2048, S fold 3 x 1024 + 2 x 256, alpha 22 x 16) = {m_alt} lane-ops: "
          f"t=1 32k {step_ns(32768, 1, R_GEMM, 7, 1, merge=m_alt)[0]} ns (vs {step_ns(32768, 1, R_GEMM, 7, 1)[0]}); S4 32k {step_ns(32768, 16, R_GEMM, 7, 1, onepass=True, merge=m_alt)[0]} (vs {step_ns(32768, 16, R_GEMM, 7, 1, onepass=True)[0]}), "
          f"1M {step_ns(1<<20, 16, R_GEMM, 7, 1, onepass=True, merge=m_alt)[0]} (vs {step_ns(1<<20, 16, R_GEMM, 7, 1, onepass=True)[0]})")
    # A4c: L_eq (attention = one GEMV unit) and the regime map at 32k
    L = 512
    while step_ns(L, 1, R_GEMM, CV_BR["nat_nat"], 1)[0] < T_GEMV: L += 512
    print(f"[A4c-Leq] smallest L (multiple of 512) with the t=1 native-corner step >= {T_GEMV} ns: {L} (step {step_ns(L,1,R_GEMM,7,1)[0]} ns; at L-512: {step_ns(L-512,1,R_GEMM,7,1)[0]})")
    La = 1
    while step_ns(La, 1, R_GEMM, 7, 1)[0] < T_GEMV: La += 1
    print(f"[A4c-Leq-anyL] over every L: step >= {T_GEMV} iff L >= {La} (the 33rd block is charged from its first 16-token group; step {step_ns(La,1,R_GEMM,7,1)[0]} at {La}, "
          f"max over L < {La} = {max(step_ns(x,1,R_GEMM,7,1)[0] for x in range(La-16, La))})")
    T384 = 67_110_000 * 10 // R_GEMM
    L5 = 512
    while step_ns(L5, 1, R_GEMM, 7, 1)[0] < T384: L5 += 512
    print(f"[A4c-Leq-384] if the unit were 67.11 MB at the measured 174.6 = {T384} ns: smallest 512-multiple {L5} (step {step_ns(L5,1,R_GEMM,7,1)[0]}; at L-512 {step_ns(L5-512,1,R_GEMM,7,1)[0]})")
    for t in (1, 2, 4, 8, 16):
        for cvk, cV in CV_BR.items():
            for rk, rho in RHO32.items():
                T, s, b = step_ns(32768, t, R_GEMM, cV, rho)
                print(f"[A4c-regime-t{t}-{cvk}-{rk}] rows={rows_of(t)} passes={s['passes']} mt={s['mt']} T={usR(T)} us bind={b} vec/ddr={t10(pct(s['vec'], s['ddr']))}%")
    # A4d: what gather rate each DESIGN-4 fleet cell needs to stay weights-bound (E21)
    for name, Tl in (("dense", T_LAYER_DENSE), ("moe", T_LAYER_MOE)):
        for k, L in LS.items():
            nb = nblocks(L); k0 = ceil(Tl - 7074, nb); Gs = BL * KV_TOK * 10 // k0
            cpg = 8 * PAGE * 10 // (Gs + 1) - PAGE * 80 // R_GEMM if Gs <= R_GEMM else None   # largest c_pg with G(64 KiB, c_pg) >= Gs + 1
            print(f"[A4d-fleet-G-{name}-{k}] attention (t=1, native) >= the {name} layer's weight stream ({Tl} ns) iff G <= {Gs} tenths"
                  + (f" -> the cell stays weights-bound iff G >= {Gs+1} = c_pg <= {cpg} ns at 64 KiB pages" if cpg is not None else " -> attention-bound at every G <= 174.6"))
    # A5: online vs two-pass
    extraK = tn(BL * D * 2 * 8, R_GEMM)
    print(f"\n[A5-online] two-pass re-streams K: +{extraK} ns per block of {BL} tokens vs merge {MERGE_OPS*2*10//R_VEC} ns (rho=2): online wins {extraK // (MERGE_OPS*2*10//R_VEC)}x")
    # A6: KV-write path per step per layer per core
    print(f"[A6-kvwrite] K append 8 x 32 B copies; V tail block COPY_FRAC {16*D*2} B at 7 GB/s = {tn(16*D*2, R_FRAC)} ns per 16 tokens ({tn(16*D*2, R_FRAC)//16} ns/token); "
          f"tail vector worst {tail_ops(15, 1)} lane-ops = {tail_ops(15,1)*2*10//R_VEC} ns (rho=2)")
    # A7: SRAM budgets (L-independent)
    for mt in (1, 2, 3, 4):
        cs = BL_of(mt) * 16 * 4 * mt; co = 16 * D * 4 * mt
        print(f"[A7-l0c-mt{mt}] block {BL_of(mt)} tokens: C_s region {cs//KiB} KiB x3 + C_o {co//KiB} KiB x2 = {l0c_bytes(mt)//KiB} KiB of L0C")
        for win in (1, 2):
            r = us_rows(mt, win); s = sum(r.values())
            print(f"[A7-us-mt{mt}-win{win}] US = {s} B = {s//KiB} KiB + {s % KiB} B (Z-reset branch {(s - r['NegSnap (US at mt=1, S1 above)'])//KiB} KiB + {s % KiB} B) "
                  f"vs 208 KiB = {US_EVID} evidenced: {'FITS' if s <= US_EVID else 'OVER by ' + str(s - US_EVID) + ' B'}; rows: " + ", ".join(f"{a} {b}" for a, b in r.items()))
        print(f"[A7-l0a-mt{mt}] L0A = +-Q {2*4*KiB*mt//KiB} + P x2 {2*4*KiB*mt//KiB} = {l0a_bytes(mt)//KiB} KiB" + ("; mt=5 would need 80 KiB > 64: the 64-row pass cap" if mt == 4 else ""))
        if mt >= 2: print(f"[A7-s1-mt{mt}] S1 = P ring {2*4*KiB*mt//KiB} + snapshots {3*BL_of(mt)*16*4*mt//KiB} = {s1_bytes(mt)//KiB} KiB")
    print(f"[A7-sram] L0B 64 KiB (2 x 32 KiB tiles); page-table window 4 KiB = 512 entries = {512*256} tokens; none of the above depends on L")
    print(f"[A7-tree-ops] tree max per 8192-score block: 6 lane-ops x (7 x 1024 + 512 + 256 lanes) = {6*(7*1024+512+256)} <= 6 x 8192 = {6*8192}; scalar tail 16 rows x 15 = 240 <= 256 compares; "
          f"exact (poly, tree) chain per block {2*8192 + 6*(7*1024+512+256) + 8192 + 22*8192 + 2*8192} <= model 33 x 8192 = {33*8192}")
    print(f"[A7-poly] exp poly: clamp 6 + scale 1 + Horner(4) 8 + 7 squarings = 22 lane-ops; Taylor bound 2^7*(22/128)^5/120 = {128*22**5*10**6//(128**5*120)}e-6 -> 1.6e-4 relative (HYPOTHESIS on the polynomial); f32 rounding 2^7 x 2^-24 = 2^-17 = 7.6e-6")
    for bl in (512, 256):
        nb = (1 << 20) // bl; v = ceil(nb, 3)
        def lg(M): return M.bit_length() - 1
        det = v * 32; rw = int(v ** 0.5) * 32
        print(f"[A7-drift-{bl}] 1M, {bl}-token blocks: {nb} blocks, {v} visits per region; deterministic |content| <= {v}*32 = {det} (f32 ulp 2^{lg(det)-23} = {2**(lg(det)-23):.1e}); "
              f"random-walk hypothesis sqrt({v})*32 = {rw} (ulp 2^{lg(rw)-23} = {2**(lg(rw)-23):.1e}); recovered-score error <= 1 ulp -> {2**(lg(rw)-23)*1e6:.0f} ppm (rw) / {2**(lg(det)-23)*1e6:.0f} ppm (det)")
    print(f"[A9-hkv1] per-core partials at H_kv = 1: 16*mt rows x (1 + 16 + 128) f32 = {16*145*4} B*mt = {16*145*4/KiB:.2f} KiB*mt (9.3 KB)")
    # ======================================================== ROUND 3: the measured constants =========================
    print("\n# ---- ROUND 3 (season v1 measured, HW-MAP commit e9349c8): [R3-*] re-derive the headline cells; [A*] above are the round-2 cells ----")
    blk174 = ddr_block_ns(R_GEMM); blk167 = ddr_block_ns(G_SHUF[64*KiB]); blk169 = ddr_block_ns(G_SHUF[256*KiB])
    for P in (16*KiB, 64*KiB, 256*KiB):
        print(f"[R3-E21-{P//KiB}k] G seq {t10(G_SEQ[P])} / shuffled {t10(G_SHUF[P])} GB/s agg; per page {T_PG_SEQ[P]} / {T_PG_SHUF[P]} ns -> c_pg(shuffled - sequential) = {cpg_meas(P)} ns; "
              f"the same page against the 174.6 model base ({P*80//R_GEMM} ns): {cpg_vs174(P)} ns ({'>' if cpg_vs174(P) > 122 else '<='} the 123 ns MoE-128k flip line of round 2); "
              f"sequential gap vs 174.6: {t10(pct(R_GEMM - G_SEQ[P], R_GEMM))}%")
    print(f"[R3-E21-block] block (2 MiB per die) DDR time: {blk174} ns at 174.6 (round 2) / {ddr_block_ns(G_SEQ[64*KiB])} at 169.0 (seq 64 KiB) / {blk167} at 167.0 (shuffled 64 KiB, the design's page) / "
          f"{blk169} at 169.2 (256 KiB) / {ddr_block_ns(G_SHUF[16*KiB])} at 153.8 (16 KiB) / {ddr_block_ns(G_3X)} at 58.2 (3x what-if)")
    print(f"[R3-E21-model] round-2 model G(64 KiB, 38 ns) = {G_page(64*KiB, 38)} (would be weights-bound); measured 1670: the attention choreography streams at 169.0, not 174.6 -> "
          f"the 64 KiB shuffled page sits {cpg_vs174(64*KiB)} ns above the 174.6 base, i.e. above the 123 ns flip line")
    # ---- the vector chain on the measured op set
    print(f"[R3-units] 1 lane-eq = 10/432 ns; chained call costs (lane-eq): exp {call100(T_EXP)//100} per 1024 lanes = {C_EXP100/100} per element; reduce-max f16 {call100(T_RM16)//100} per call (f32 {call100(T_RM32)//100}); "
          f"f16 op {call100(T_F16)//100} per call = {UNIT['C'][0]/100} per lane; f32 op {call100(T_F32)//100} per call = {UNIT['C'][1]/100} per lane (rho32 = {RHO32_100/100}); 'T' convention: f16 1.00, f32 1.37 per lane")
    print(f"[R3-tree-ops] f16 tree lane-ops per fragment: block 512 {tree_ops(512)} ({tree_ops(512)/8192:.4f}/score), 256 {tree_ops(256)}, 128 {tree_ops(128)}; the 32-bit And is ABSENT -> the f32 tree is closed, the f16 tree (And<int16> 45.9 ns) is open")
    for var, conv in CORNERS3:
        for bl in (512, 256, 128):
            v = vec3_ns(bl, 1, var, conv, MERGE_PACK * 100); f16, f32 = UNIT[conv]; sc = bl * 16
            if var == "rowmax":
                parts = (f"elementwise {sc*(2*f32+f32+f32+C_EXP100+f32+f32)//100} + tree {tree_ops(bl)*f16//100} + 16 reduce {16*call100(T_RM16)//100} + shift reel {20*call100(T_F16)//100} + merge {MERGE_PACK}")
            else:
                parts = (f"elementwise {sc*(2*f32+f32+C_EXP100+f32+f32)//100} + guard {sc//1024} reduce {(sc//1024)*call100(T_RM16)//100} + merge {MERGE_PACK}")
            d = ddr_block_ns(R_GEMM, 1 if bl == 512 else (3 if bl == 256 else 8)); d167 = ddr_block_ns(G_SHUF[64*KiB], 1 if bl == 512 else (3 if bl == 256 else 8))
            print(f"[R3-chain-{var}-{conv}-{bl}] per fragment at block {bl}: {chain100(bl,1,var,conv,MERGE_PACK*100)//100} lane-eq = {v} ns = {t10(pct(v, d))}% of the {d} ns block at 174.6 / {t10(pct(v, d167))}% at 167.0 ({parts})")
    for var, conv in CORNERS3:
        m = merge_item(var, conv)
        print(f"[R3-merge-{var}-{conv}] itemised merge chain = {m//100} lane-eq = {m*10//(R_VEC*100)} ns" + (f" (alpha exp {call100(T_EXP)//100} + alpha reel {20*call100(T_F16)//100} + O {4*2048*UNIT[conv][1]//100} + S {(512+256+256+256)*UNIT[conv][1]//100})" if var == "rowmax" else f" (O {3*2048*UNIT[conv][1]//100} + S {(512+256+256)*UNIT[conv][1]//100}, no alpha)")
              + f"; pack 25 750 = {MERGE_PACK*10//R_VEC} ns; round-2 7 000 = {7000*10//R_VEC}; section-3.1 count 12 128 = {12128*10//R_VEC}")
    for G, gk in ((R_GEMM, "174.6"), (G_SHUF[64*KiB], "167.0")):
        d = ddr_block_ns(G)
        for var, conv in CORNERS3:
            base = chain100(512, 1, var, conv, 0)
            lim = (d + 1) * R_VEC * 100 // 10 - 1 - base      # largest merge100 with vec <= d:  (base + m)*10 // 43200 <= d  <=>  base + m < (d+1)*4320
            lim = ((d + 1) * 4320 - 1 - base)
            print(f"[R3-merge-threshold-{var}-{conv}-{gk}] t = 1 block DDR-bound at {gk} iff merge <= {lim//100} lane-eq ({'pack 25 750 OK' if MERGE_PACK*100 <= lim else 'pack 25 750 EXCEEDS'}; itemised {merge_item(var,conv)//100} {'OK' if merge_item(var,conv) <= lim else 'EXCEEDS'})"
                  + (f"; with the pack merge the block is vector-bound by {t10(pct(vec3_ns(512,1,var,conv,MERGE_PACK*100) - d, d))}%" if lim < 0 or vec3_ns(512,1,var,conv,MERGE_PACK*100) > d else ""))
    # c_exp threshold on the measured chain (rowmax-T): vec <= block iff C_EXP100 <= x
    for G, gk in ((R_GEMM, "174.6"), (G_SHUF[64*KiB], "167.0")):
        d = ddr_block_ns(G)
        for var, conv in (("rowmax", "T"), ("lazy", "T"), ("rowmax", "C")):
            f16, f32 = UNIT[conv]
            other = chain100(512, 1, var, conv, MERGE_PACK * 100) - 8192 * C_EXP100
            cx = ((d + 1) * 4320 - 1 - other) // 8192
            print(f"[R3-cexp-threshold-{var}-{conv}-{gk}] t = 1 DDR-bound iff c_exp <= {cx/100:.2f} lane-eq (measured 11.5{' OK' if C_EXP100 <= cx else ' EXCEEDS'}); round-2 lines 56 / 51 / 24 / 19 all cleared by 11.5")
    # ---- headline cells, t = 1
    print("\n[R3-t1] t = 1 x L x G-branch x chain-corner -> in-kernel ns (wall = + 91 000): rowmax = section 3.2 as specified, lazy = fixed shift + guard; T = throughput, C = chained-latency bound")
    for k, L in LS.items():
        for gk, G in G3.items():
            for var, conv in CORNERS3:
                T, s, b = step3(L, 1, G, var, conv)
                print(f"[R3-t1-{k}-{gk}-{var}-{conv}] T={T} ns ({usR(T)} us; wall {usR(T+T_LAUNCH)}) bind={b} ddr={s['ddr']} vec={s['vec']} mma={s['mma']} ldr={s['loader']} drain={s['drain']} fixed={s['fixed']} vblk={s['vblk']} "
                      f"| eff {t10(rateT(L*KV_TOK, T))} GB/s | x GEMV {t10(pct(T, T_GEMV))}%")
    for k in ("32k", "1M"):
        L = LS[k]
        for gk, G in (("stream174", R_GEMM), ("shuf64k", G_SHUF[64*KiB]), ("p256k", G_SHUF[256*KiB])):
            a = step3(L, 1, G, "rowmax", "T")[0]; w = step3(L, 1, G, "rowmax", "C")[0]; z = step3(L, 1, G, "lazy", "T")[0]
            print(f"[R3-worst-overrun-{k}-{gk}] chained-latency corner / headline = +{t10(pct(w - a, a))}% ({w} vs {a}); lazy / headline = {t10(pct(z, a))}%")
    # ---- t = 16: two passes vs S4, at the pack merge and the itemised merge
    for k in ("32k", "1M"):
        L = LS[k]
        for gk, G in (("stream174", R_GEMM), ("shuf64k", G_SHUF[64*KiB])):
            for var, conv in CORNERS3:
                T2, s2, b2 = step3(L, 16, G, var, conv)
                T1, s1, b1 = step3(L, 16, G, var, conv, onepass=True)
                Ti, _, _ = step3(L, 16, G, var, conv, merge100=merge_item(var, conv), onepass=True)
                print(f"[R3-t16-{k}-{gk}-{var}-{conv}] two passes (mt 4, block 256): T={T2} ({usR(T2)} us) bind={b2} vblk={s2['vblk']} ddr/blk={ddr_block_ns(G,4)} | S4 one pass (mt 8, block 128): T={T1} ({usR(T1)} us) bind={b1} vblk={s1['vblk']} ddr/blk={ddr_block_ns(G,8)} "
                      f"| S4 at the itemised merge {Ti} ({usR(Ti)} us) | S4/two-pass = {t10(pct(T1, T2))}%")
    for var, conv in (("rowmax", "T"), ("lazy", "T")):
        # S4 beats two passes at 32k iff merge <= m*: search (monotone in merge)
        L = 32768; lo, hi = 0, 200000
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if step3(L, 16, R_GEMM, var, conv, merge100=mid * 100, onepass=True)[0] < step3(L, 16, R_GEMM, var, conv, merge100=mid * 100)[0]: lo = mid
            else: hi = mid - 1
        print(f"[R3-s4-threshold-{var}-{conv}] S4 beats two passes at 32k (174.6) iff merge <= {lo} lane-eq per block-fragment (pack 25 750: {'S4 wins' if MERGE_PACK <= lo else 'two passes win'}; round-2 7 000: {'S4 wins' if 7000 <= lo else 'two passes win'})")
    print(f"[R3-s4-chain] S4 per 128-token block, mt 8, rowmax-T: vector {vec3_ns(128, 8, 'rowmax', 'T', MERGE_PACK*100)} ns vs DDR {ddr_block_ns(R_GEMM, 8)} ({t10(pct(vec3_ns(128,8,'rowmax','T',MERGE_PACK*100), ddr_block_ns(R_GEMM,8)))}%): "
          f"16 reduce calls per fragment recur every 128 tokens = {16*8*T_RM16//10} ns of the block alone; lazy-T {vec3_ns(128, 8, 'lazy', 'T', MERGE_PACK*100)} ns ({t10(pct(vec3_ns(128,8,'lazy','T',MERGE_PACK*100), ddr_block_ns(R_GEMM,8)))}%)")
    # ---- crossover (attention = one 398 us GEMV unit)
    k33 = (T_GEMV - 1) - 32 * blk174
    print(f"[R3-crossover-iff] at the 174.6 basis step(512k) = 12 011 k + fixed: k >= 33 (L_eq = 16 896) iff fixed <= {k33} ns; k >= 32 (16 384) iff fixed in [{T_GEMV - 32*blk174}, {T_GEMV - 1 - 31*blk174}]; round-2 fixed 7 074")
    for var, conv in CORNERS3:
        for gk, G in (("stream174", R_GEMM), ("seq64k", G_SEQ[64*KiB]), ("shuf64k", G_SHUF[64*KiB]), ("p256k", G_SHUF[256*KiB])):
            fx = step3(512, 1, G, var, conv)[1]["fixed"]
            kk = 1
            while step3(512 * kk, 1, G, var, conv)[0] < T_GEMV: kk += 1
            La = 1
            while step3(La, 1, G, var, conv)[0] < T_GEMV: La += 1               # first L that reaches the unit
            Lm = 512 * kk
            while Lm > 1 and step3(Lm - 1, 1, G, var, conv)[0] >= T_GEMV: Lm -= 1   # every L >= Lm reaches it (monotone crossover)
            print(f"[R3-crossover-{var}-{conv}-{gk}] fixed={fx} ns: smallest 512-multiple with step >= 398 000: k={kk} -> L_eq={512*kk} (step {step3(512*kk,1,G,var,conv)[0]}; at k-1: {step3(512*(kk-1),1,G,var,conv)[0]}); "
                  f"first L reaching the unit {La}; every L >= {Lm} reaches it" + ("" if La == Lm else f" (NOT monotone between: the vector tail decides, e.g. step({La + 7}) = {step3(La + 7, 1, G, var, conv)[0]})")
                  + (" -- 16 896 SURVIVES" if 512 * kk == 16896 else f" -- MOVED from 16 896"))
    # ---- GQA matrix theorem at the measured rho32
    print(f"[R3-gqa-137] vector-dot route / KV stream at rho32 = 1.37: rows 1: {t10(1*137*4*D*R_GEMM*10000//(80*CORE_TOK*R_VEC*100))}%, 2: {t10(2*137*4*D*R_GEMM*10000//(80*CORE_TOK*R_VEC*100))}%, 8: {t10(8*137*4*D*R_GEMM*10000//(80*CORE_TOK*R_VEC*100))}% "
          f"-> compute-bound for every rows >= 2 (rows x rho32 = 2.74 >= 2): T_gqa_matrix unchanged (rows = 1 alone is DDR-bound at 69.2%)")
    # ---- regime map at 32k on the measured chain
    for t in (1, 2, 4, 8, 16):
        for var, conv in CORNERS3:
            T, s, b = step3(32768, t, G_SHUF[64*KiB], var, conv)
            T4, _, b4 = step3(32768, t, R_GEMM, var, conv)
            print(f"[R3-regime-t{t}-{var}-{conv}] rows={rows_of(t)} passes={s['passes']} mt={s['mt']} block={BL_of(s['mt'])}: at 167.0 T={usR(T)} us bind={b} vec/ddr={t10(pct(s['vec'], s['ddr']))}% | at 174.6 T={usR(T4)} us bind={b4}")
    for var, conv in CORNERS3:
        mt = 1
        while vec3_ns(BL_of(mt), mt, var, conv, MERGE_PACK * 100) < ddr_block_ns(R_GEMM, mt) and mt < 8: mt += 1
        print(f"[R3-rows*-{var}-{conv}] smallest mt with vector >= KV stream per block (174.6): mt={mt} -> rows*={16*mt} (t >= {ceil(16*mt, G_Q)} at g=8); round 2 (native, native, rho 1) said 112")
    # ---- the fleet cells (E21 for the fleet): G* with the measured fixed cost, and the verdict at every measured G
    for var, conv in (("rowmax", "T"), ("lazy", "T"), ("rowmax", "C")):
        fx = step3(512, 1, R_GEMM, var, conv)[1]["fixed"]
        for name, Tl in (("dense", T_LAYER_DENSE), ("moe", T_LAYER_MOE)):
            for k, L in LS.items():
                nb = nblocks(L); k0 = ceil(Tl - fx, nb) if Tl > fx else 1; Gs = BL * KV_TOK * 10 // k0
                verd = []
                for gk, G in (("16k", G_SHUF[16*KiB]), ("64k", G_SHUF[64*KiB]), ("64k-seq", G_SEQ[64*KiB]), ("256k", G_SHUF[256*KiB]), ("174.6", R_GEMM)):
                    T = step3(L, 1, G, var, conv)[0]
                    verd.append(f"{gk}: {'ATTN-bound' if T >= Tl else 'weights-bound'} by {t10(pct(abs(T - Tl), Tl))}% ({abs(T-Tl)//1000} us)")
                print(f"[R3-fleet-G-{var}-{conv}-{name}-{k}] attention-bound iff G <= {Gs} tenths (fixed {fx}): " + "; ".join(verd))
    print(f"[R3-fleet-moe128k-direction] round-2 line: attention-bound iff G <= 1677; measured shuffled 64 KiB G = 1670 <= 1677 -> ATTENTION-bound (HW-MAP's 'stays stream-bound by 0.7 GB/s' reads the inequality backwards); "
          f"stream alone at 1670: 256 x {blk167} = {256*blk167} ns vs the MoE layer {T_LAYER_MOE} -> attention-bound by {256*blk167 - T_LAYER_MOE} ns before any fixed cost")
    # ---- page verdict
    for P in (16*KiB, 64*KiB, 256*KiB):
        print(f"[R3-page-{P//KiB}k] G = {t10(G_SHUF[P])} shuffled; vs 256 KiB: {t10(pct(G_SHUF[256*KiB] - G_SHUF[P], G_SHUF[256*KiB]))}% slower; tail waste per layer-sequence 16 x (P - 256 B) = {16*(P-256)/MiB:.2f} MiB; "
              f"t=1 32k rowmax-T {usR(step3(32768,1,G_SHUF[P])[0])} us, 1M {usR(step3(1<<20,1,G_SHUF[P])[0])} us")
    for c in (0, 39, 100, 153, 200, 500, 2000):
        print(f"[R3-page-cpg{c}] 64 KiB at c_pg = {c} ns: G = {t10(G_page3(64*KiB, c))}; two-tier (1 MiB extents + 64 KiB tails) at 32k {t10(G_tier3(32768, c))}, 34 768 {t10(G_tier3(34768, c))}, 1M {t10(G_tier3(1<<20, c))}; "
              f"256 KiB pages at the same c {t10(G_page3(256*KiB, c))}; two-tier gain over 64 KiB at 32k {t10(pct(G_tier3(32768, c) - G_page3(64*KiB, c), G_page3(64*KiB, c)))}%")
    c = 0
    while pct(G_tier3(32768, c) - G_page3(64*KiB, c), G_page3(64*KiB, c)) < 50: c += 1
    print(f"[R3-page-tier-rule] two-tier (or 1 MiB extents) gains >= 5.0% over 64 KiB pages at 32k iff c_pg >= {c} ns at 64 KiB (measured lower bound 39: gain {t10(pct(G_tier3(32768, 39) - G_page3(64*KiB, 39), G_page3(64*KiB, 39)))}%); "
          f"256 KiB pages vs 64 KiB at the measured rates: +{t10(pct(G_SHUF[256*KiB] - G_SHUF[64*KiB], G_SHUF[64*KiB]))}%; 16 KiB: {t10(pct(G_SHUF[64*KiB] - G_SHUF[16*KiB], G_SHUF[64*KiB]))}% below 64 KiB")
    # ---- drain, scalar, online
    TH_DRAIN = {1: 35, 2: 69, 3: 123, 4: 164}   # the round-2 iff thresholds (T2_drain_threshold), tenths GB/s/core
    print("[R3-drain] measured R_drain vs the round-2 iff hide thresholds: " + "; ".join(f"mt={mt}: {t10(R_DRAIN_M[mt])} GB/s/core vs {t10(TH_DRAIN[mt])} -> {t10(R_DRAIN_M[mt]*10//TH_DRAIN[mt])}x margin, drain {drain_block_ns(mt, R_DRAIN_M[mt])} ns per block ({t10(pct(drain_block_ns(mt, R_DRAIN_M[mt]), ddr_block_ns(R_GEMM, mt)))}%)" for mt in (1, 2, 3, 4)))
    print(f"[R3-sigma] scalar tail at sigma_s = 19.9 ns: 256 x 19.9 = {256*SIGMA_S3//10} ns per fragment = {t10(pct(256*SIGMA_S3//10, blk174))}% of the block (round 2: 512 ns, 4.3%); below the 47 ns bind line; "
          f"replaced by 16 reduce-max calls = {16*T_RM16//10} ns ({t10(pct(16*T_RM16//10, blk174))}%), {t10(x if (x:=256*SIGMA_S3*10//(16*T_RM16)) else 0)}x cheaper; the all-scalar max over 8 192 scores = {8192*SIGMA_S3//10} ns = {t10(8192*SIGMA_S3//blk174)}x the block")
    extraK = tn(BL * D * 2 * 8, G_SEQ[64*KiB])
    print(f"[R3-online] two-pass re-streams K: +{extraK} ns per block at 169.0 ({tn(BL*D*2*8, R_GEMM)} at 174.6) vs merge {MERGE_PACK*10//R_VEC} ns (pack 25 750) / {merge_item('rowmax','T')*10//(R_VEC*100)} (itemised T) / {merge_item('rowmax','C')*10//(R_VEC*100)} (itemised C): "
          f"online wins {extraK*10//(MERGE_PACK*10//R_VEC)/10:.1f}x / {extraK*10//(merge_item('rowmax','T')*10//(R_VEC*100))/10:.1f}x / {extraK*10//(merge_item('rowmax','C')*10//(R_VEC*100))/10:.1f}x (round 2 said 18x at 7 000)")
    print(f"[R3-i8-t1] KV-int8 variant on the measured chain (rowmax-T, 167.0): 32k {usR(step3(32768,1,G_SHUF[64*KiB],i8=True)[0])} us bind={step3(32768,1,G_SHUF[64*KiB],i8=True)[2]}, 1M {usR(step3(1<<20,1,G_SHUF[64*KiB],i8=True)[0])} us; "
          f"lazy-T 32k {usR(step3(32768,1,G_SHUF[64*KiB],'lazy','T',i8=True)[0])} us bind={step3(32768,1,G_SHUF[64*KiB],'lazy','T',i8=True)[2]}")
    # ---- the moved cells: every round-2 headline cell -> its round-3 replacement (headline = rowmax-T at the design's 64 KiB page, shuffled 167.0)
    print("\n[R3-moved] round-2 headline cell -> round-3 replacement; '174.6' = the same W8-kernel basis as round 2, '167.0' = the measured 64 KiB shuffled page (design), 'lazy' = the fixed-shift variant")
    G64 = G_SHUF[64*KiB]
    mv = []
    for k in ("4k", "32k", "128k", "1M"):
        L = LS[k]
        mv.append((f"t1-{k}-stream", "stream native (c_V 7, rho 1)", step_ns(L,1,R_GEMM,7,1)[0], step3(L,1,R_GEMM)[0], step3(L,1,G64)[0], step3(L,1,G64,'lazy','T')[0]))
        mv.append((f"t1-{k}-worst", "worst corner (poly, tree, rho 2)", step_ns(L,1,R_GEMM,33,2)[0], step3(L,1,R_GEMM,'rowmax','C')[0], step3(L,1,G64,'rowmax','C')[0], step3(L,1,G64,'lazy','C')[0]))
        mv.append((f"t1-{k}-page64k", "page64k (c_pg 0.5 us) -> measured 64 KiB", step_ns(L,1,G_BR['page64k'],7,1)[0], step3(L,1,R_GEMM)[0], step3(L,1,G64)[0], step3(L,1,G64,'lazy','T')[0]))
        mv.append((f"t1-{k}-gather3x", "gather3x (c_pg 6 us) -> what-if at the measured base", step_ns(L,1,R_GEMM//3,7,1)[0], step3(L,1,G_3X)[0], step3(L,1,G_SHUF[16*KiB])[0], step3(L,1,G_SHUF[16*KiB],'lazy','T')[0]))
        mv.append((f"t16-{k}", "t=16 two passes native", step_ns(L,16,R_GEMM,7,1)[0], step3(L,16,R_GEMM)[0], step3(L,16,G64)[0], step3(L,16,G64,'lazy','T')[0]))
    for k in ("32k", "1M"):
        L = LS[k]
        mv.append((f"S4-{k}", "S4 one pass native", step_ns(L,16,R_GEMM,7,1,onepass=True)[0], step3(L,16,R_GEMM,onepass=True)[0], step3(L,16,G64,onepass=True)[0], step3(L,16,G64,'lazy','T',onepass=True)[0]))
        mv.append((f"i8-{k}", "KV-int8 native", step_ns(L,1,R_GEMM,7,1,i8=True)[0], step3(L,1,R_GEMM,i8=True)[0], step3(L,1,G64,i8=True)[0], step3(L,1,G64,'lazy','T',i8=True)[0]))
    def chg(o, n): return ("+" + t10(pct(n - o, o))) if n >= o else ("-" + t10(pct(o - n, o)))
    for lab, name, old, n174, n167, nlazy in mv:
        extra = " (gather3x column: 16 KiB = the measured worst page)" if "gather3x" in lab else ""
        print(f"[R3-moved-{lab}] {name}: {old} ns ({usR(old)} us) -> {n174} ({usR(n174)}) at 174.6 [{chg(old, n174)}%] / {n167} ({usR(n167)}) at 167.0 [{chg(old, n167)}%] / lazy at 167.0 {nlazy} ({usR(nlazy)}){extra}")
    print(f"[R3-moved-fixed] fixed cost 7 074 ns -> {step3(32768,1,R_GEMM)[1]['fixed']} (rowmax-T) / {step3(32768,1,R_GEMM,'rowmax','C')[1]['fixed']} (rowmax-C) / {step3(32768,1,R_GEMM,'lazy','T')[1]['fixed']} (lazy-T): 2 vector blocks {vec3_ns(512,1,'rowmax','T',MERGE_PACK*100)} / {vec3_ns(512,1,'rowmax','C',MERGE_PACK*100)} / {vec3_ns(512,1,'lazy','T',MERGE_PACK*100)} + drain {drain_block_ns(1, R_DRAIN_M[1])} (was 4 096 at 10 GB/s)")
    print(f"[R3-moved-vecshare] vector share of the 12 011 ns block at mt=1: 12.4% (c_V 7) -> {t10(pct(vec3_ns(512,1,'rowmax','T',MERGE_PACK*100), blk174))}% rowmax-T / {t10(pct(vec3_ns(512,1,'rowmax','C',MERGE_PACK*100), blk174))}% rowmax-C / {t10(pct(vec3_ns(512,1,'lazy','T',MERGE_PACK*100), blk174))}% lazy-T; "
          f"the 851 us corner (c_V 33, rho 2, 106.9%) is unreachable (both native ops exist)")
    for var, conv in CORNERS3:
        print(f"[R3-lin-{var}-{conv}] chain100(block, 1, merge100 = 0): 512 {chain100(512,1,var,conv,0)}, 256 {chain100(256,1,var,conv,0)}, 128 {chain100(128,1,var,conv,0)} (lane-eq x100; vec ns = (base + merge100) x 10 // 43200)")
    print(f"[R3-chain-rowmax-t1-8calls] at t = 1 the 8 padding rows need no reduce call: rowmax-T with 8 calls = {(chain100(512,1,'rowmax','T',MERGE_PACK*100) - 8*call100(T_RM16))*10//(R_VEC*100)} ns ({t10(pct((chain100(512,1,'rowmax','T',MERGE_PACK*100) - 8*call100(T_RM16))*10//(R_VEC*100), blk174))}% of the block); the headline keeps the 16-call fragment accounting (holds for every t)")

# ============================================================ ROUND 4 (2026-11-07): pre-implementation review + kernel session 1 ====
# Silicon inputs (HW-MAP 423d433, errata #18-#21; "K1" = kernel session 1):
#   * f16 k-shape sweep: (16,16,k) EXACT at every k in {16, 32, 64, 128} on the f16 x f16 tuple (128 reps/shape, one-hot k-probes,
#     all 8 cores) -- the i8 k = 64 anomaly is i8-only. d = 128 keeps one k = 128 call per 16 tokens; d = 64 may use ONE k = 64 call.
#   * erratum #19: f16 accumulation into one C chunk corrupts across ANY full barrier or A re-lift (>= 2 accumulations). Consequence:
#     every C chunk is FRESH (written by exactly one matrix call per visit): C_s chunks (one (16,16,128) call per 16 tokens) and
#     C_o = one fresh chunk set per 128-token group (8 calls, 8 chunks); the partials are summed on the vector unit. The region
#     difference (Z, the +-Q alternation, the NegSnap buffers) is gone: no mechanism, no drift, no snapshot.
#   * erratum #20: an A operand built in vector SRAM (the P fragments) must ride a DDR bounce (US -> DDR scratch -> DDR -> S1 staging
#     -> loader lift): `legs` DDR transfers of the P bytes per block ride the same DDR roof as the K/V stream (legs = 2: both legs
#     charged, the headline / conservative reading; 1: only the read leg; 0: a direct US -> S1 route, the round-3 model). UNMEASURED.
#   * erratum #18 (C destination by byte-offset tensor), #21 (prime-period host patterns): spec items, no number.
#   * the lazy guard's per-trip recompute is REQUIRED (measured: 9 / 8192 lanes wrong per tripped block without it).
#   * the kernel's own fresh-path gather: 138.3 / 138.7 / 138.0 GB/s aggregate at 256 / 128 / 64 KiB (diagnostic loop; the production
#     loop halves the barriers per byte: its rate is UNMEASURED, between 138 and the E21 169).
#   * OPEN (session 2): 75-91 % of P lanes read back as raw scores from the softmax reel -- the vector-chain cells are OPEN.
# Every round-2 / round-3 label above keeps printing its value; the [R4-*] labels below are the round-4 cells.
G_K1 = {256 * KiB: 1383, 128 * KiB: 1387, 64 * KiB: 1380}   # session-1 kernel loop, aggregate tenths GB/s (M, diagnostic loop)
G4 = {"p256k": G_SHUF[256 * KiB], "shuf64k": G_SHUF[64 * KiB], "stream174": R_GEMM, "k1loop": G_K1[256 * KiB], "shuf16k": G_SHUF[16 * KiB]}
LEGS_HEAD = 2                                              # headline: both bounce legs on the DDR roof (UNMEASURED, conservative)
def co_sets(block): return block // 128                     # fresh C_o chunk sets per block-fragment (one per 128-token group)
def l0c4(mt):  return 3 * BL_of(mt) * 16 * 4 * mt + co_sets(BL_of(mt)) * 16 * D * 4 * mt    # 3 C_s regions + single-buffered fresh C_o sets
def l0a4(mt):  return 4 * KiB * mt + 2 * 4 * KiB * mt                                      # Q (no -Q) + double-buffered P
def drain4_bytes(mt): return (BL_of(mt) * 16 * 4 + co_sets(BL_of(mt)) * 16 * D * 4) * mt   # C_s + every fresh C_o set of the block
def drain4_ns(mt, Rd): return tn(drain4_bytes(mt), Rd)
def p_bytes(mt): return co_sets(BL_of(mt)) * 4096 * mt                                     # P fragments per block per core (f16)
def bounce_bytes(mt, legs): return legs * p_bytes(mt)                                      # DDR bytes the bounce adds per block per core
def ddr4_block_ns(G, mt, legs, i8=False): return tn((BL_of(mt) * CORE_TOK // (2 if i8 else 1) + bounce_bytes(mt, legs)) * 8, G)
def merge4_100(block, variant, conv):
    """fresh-set merge per block-fragment, lane-eq x100: O_b = sum of the block's co_sets partials (2048 f32 lanes each: n adds, the
    first a copy costed as an op), O += O_b (1 add) [rowmax: O scaled by alpha first (1 Mul), alpha = exp (1 call) + alpha reel (20 small
    calls)]; S: fold 1024 -> 256 (512 + 256), [rowmax: scale 256], running add 256. Two-level (block-local, then running) so that the
    longest f32 rounding chain is O(L/block), not O(L/128) -- T4r_drift_online."""
    f16, f32 = UNIT[conv]; n = co_sets(block)
    if variant == "rowmax": return call100(T_EXP) + 20 * call100(T_F16) + (2048 * (n + 1) + 2048 + 512 + 256 + 256 + 256) * f32
    return (2048 * (n + 1) + 512 + 256 + 256) * f32
def chain4_100(block, mt, variant, conv, merge100=None):
    """round-4 vector chain per block for mt fragments, lane-eq x100. rowmax (section 3.2 minus the Z difference): cast S -> f16, shift,
    exp, cast P, sum (4 f32-class ops + exp per score) + the f16 tree + 16 per-row reduce-max calls + the 20-call shift reel + merge.
    lazy (section 3.4): shift, exp, cast P, sum (3 f32 ops + exp) + one guard reduce-max per P reel + merge.  OPEN: the softmax reel's
    cost is modelled as specified; session 2 owns the P-lane anomaly."""
    f16, f32 = UNIT[conv]; sc = block * 16
    m = merge4_100(block, variant, conv) if merge100 is None else merge100
    if variant == "rowmax":
        el = sc * (f32 + f32 + C_EXP100 + f32 + f32) + tree_ops(block) * f16
        calls = 16 * call100(T_RM16) + 20 * call100(T_F16)
    else:
        el = sc * (f32 + C_EXP100 + f32 + f32)
        calls = (sc // 1024) * call100(T_RM16)
    return mt * (el + calls + m)
def vec4_ns(block, mt, variant, conv, merge100=None): return chain4_100(block, mt, variant, conv, merge100) * 10 // (R_VEC * 100)
def firstmax4_100(block, mt, conv):   # lazy: the first block's per-row max, once per step (cast S -> f16, tree, 16 reduce calls, reel)
    f16, f32 = UNIT[conv]
    return mt * (block * 16 * f32 + tree_ops(block) * f16 + 16 * call100(T_RM16) + 20 * call100(T_F16))
def firstmax4_ns(block, mt, conv): return firstmax4_100(block, mt, conv) * 10 // (R_VEC * 100)
# append-then-attend (section 10.1 / review item 6): the pages hold the 16-token groups completed BEFORE this step (L - t tokens), the
# tails serve the open group plus the t new tokens: tail4_tok <= 15 + 16 = 31 (two 16-token groups); the per-row causal mask is one
# additive op over <= 32 lanes x 16 rows per fragment, once per step
def tail4_tok(L, t): return (L - t) % 16 + t
def L_matrix4(L, t): return 16 * ((L - t) // 16)
def nblocks4(L, t, mt): return ceil(L_matrix4(L, t), BL_of(mt))
def tail4_ops(L, t, mt): return tail4_tok(L, t) * D * 16 * mt * 4
def mask4_lanes(t, mt): return 512 * mt if t > 1 else 0
def step4(L, t, G, variant="lazy", conv="T", merge100=None, legs=LEGS_HEAD, onepass=False, i8=False):
    rows = rows_of(t)
    p, mt = (1, mt_of(rows)) if onepass else (passes_of(rows), mt_pass(rows))
    bl = BL_of(mt); nb = nblocks4(L, t, mt); Rd = R_DRAIN_M[min(mt, 4)]
    v = vec4_ns(bl, mt, variant, conv, merge100)
    ddr = p * nb * ddr4_block_ns(G, mt, legs, i8)
    vec, mma, ldr, drn = p * nb * v, p * nb * mma_block_ns(mt), p * nb * loader_block_ns(mt), p * nb * drain4_ns(mt, Rd)
    f32u = UNIT[conv][1]
    fixed = 2 * v + drain4_ns(mt, Rd) + (tail4_ops(L, t, mt_of(rows)) + mask4_lanes(t, mt_of(rows))) * f32u * 10 // (R_VEC * 100)
    if variant == "lazy": fixed += firstmax4_ns(bl, mt, conv)
    c = {"KV stream": ddr, "vector": vec, "MMA": mma, "loader": ldr}
    return max(c.values()) + fixed, dict(ddr=ddr, vec=vec, mma=mma, loader=ldr, drain=drn, fixed=fixed, passes=p, mt=mt, nb=nb, vblk=v), max(c, key=c.get)
CORNERS4 = (("lazy", "T"), ("lazy", "C"), ("rowmax", "T"), ("rowmax", "C"))
# C_o drain nesting (review item 8): chunk (fragment f, n-group g) = 1 KiB = [16 rows][16 dims] f32 at f*8192 + g*1024; element (r, j) at
# + r*64 + j*4 -> row r of fragment f = 8 runs of 64 B at stride 1024 B from f*8192 + r*64; after an f16 cast 32 B runs at stride 512 B
# from f*4096 + r*32; an m = 64 call writes [64 rows][16 dims] chunks of 4 KiB: row r at g*4096 + r*64 (stride 4096)
def co_addr(f, g, r, j): return f * 8192 + g * 1024 + r * 64 + j * 4
def co_addr16(f, g, r, j): return f * 4096 + g * 512 + r * 32 + j * 2
def co_addr_m64(g, r, j): return g * 4096 + r * 64 + j * 4
# 256 KiB pages (review item 11): four 64 KiB sub-pages, sub-page = (l mod 1024) div 256, inside it the round-2 maps
def kAddr64(l, j): return (l // 16) * 4096 + (j // 16) * 512 + (l % 16) * 32 + (j % 16) * 2
def vAddr64(l, j): return ((l // 128) * 8 + j // 16) * 4096 + ((l % 128) // 16) * 512 + (j % 16) * 32 + (l % 16) * 2
def kAddr256(l, j): return ((l % 1024) // 256) * 65536 + kAddr64(l % 256, j)
def vAddr256(l, j): return ((l % 1024) // 256) * 65536 + vAddr64(l % 256, j)
# online-chain f32 rounding (review item 5, re-aimed): longest sequential chain of f32 additions feeding out = O / S, first-order
# bound (n - 1) * 2^-24 relative to the sum of magnitudes (IEEE round-to-nearest; the matrix unit's internal order: UNMEASURED)
U24_PPB = 10 ** 9 // 2 ** 24 + 1          # 2^-24 = 59.6e-9: 60 ppb (rounded up)
def chain_O(L, block): return (co_sets(block) - 1) + 1 + L // block          # block-local sum of the partials, then one running add per block
def chain_S(L, block): return block * 16 // 1024 + 2 + L // block + 4         # 8 reels into the block Acc, fold 1024 -> 256 (2), running add per block, final 16 -> 1 (4)
def rel_ppm(n): return (n * 10 ** 6 + 2 ** 24 - 1) // 2 ** 24                 # ceil(n * 2^-24 * 1e6)
def isqrt(n):
    r = int(n ** 0.5)
    while r * r > n: r -= 1
    while (r + 1) * (r + 1) <= n: r += 1
    return r
# planted sink (review item 7): the f16 cast flushes p < 2^-24 (the smallest f16 subnormal); a row with one sink at p = 1 and L - 1
# tokens just under the flush line (p = 2^-25 each) loses (L - 1) * 2^-25 of its mass -- one-sided
def sink_lost_ppm(L): return ((L - 1) * 10 ** 6) // 2 ** 25
# page waste (review item 11): one partially filled page per (head, K|V) per (layer, sequence) = 16 pages of (P - one token)
def page_waste(P, tokB=256): return 16 * (P - tokB)
# US rows, round 4 (section 4): no NegSnap (fresh chunks), 32-token tails, the mask reel, the fresh-set partial ring (slot 0 holds the
# block-local sum O_b); P staging double-buffered at mt = 1 only (the bounce drains each 4 KiB piece as it is cast); the partial ring is
# 2 slots at mt <= 3, 1 at mt = 4; the prologue-only q row-major buffer is aliased onto the idle drained-C_s buffer at mt = 4 (round-2 remedy)
def us4_rows(mt):
    bl = BL_of(mt); cs = bl * 16 * 4 * mt; co = 16 * D * 4 * mt
    return {"drained C_s": cs, "P staging": (2 if mt == 1 else 1) * bl * 16 * 2 * mt, "O": co, "partial ring (O_b in slot 0)": (2 if mt <= 3 else 1) * co,
            "S acc": 4 * KiB, "shift reel": 4 * KiB, "alpha": 64, "K_tail (32 tokens)": 8 * KiB, "V_tail (32 tokens)": 8 * KiB,
            "mask reel": 512 * mt * 4, "q row-major": 4 * KiB * mt if mt < 4 else 0, "page-table window": 4 * KiB}

def main4():
    print("\n# ---- ROUND 4 (2026-11-07; pre-implementation review + kernel session 1, HW-MAP 423d433): [R4-*] cells; [A*]/[R3-*] above unchanged ----")
    blk174 = ddr_block_ns(R_GEMM); blk169 = ddr_block_ns(G_SHUF[256 * KiB]); blk167 = ddr_block_ns(G_SHUF[64 * KiB])
    # ---- k-shape (review item 1): measured verdict; d = 64 cost table
    blk64 = tn(BL * 2 * 64 * 2 * 8, R_GEMM); blk64_256 = tn(256 * 2 * 64 * 2 * 8, R_GEMM)
    for name, kc in (("k64", 1), ("2xk32", 2), ("4xk16", 4)):
        c1 = 32 * kc + 16; c4 = 4 * (16 * kc + 8)
        print(f"[R4-kshape-d64-{name}] d = 64, scores as {name} per 16 tokens: calls per 512-token block (mt 1) = {c1} -> {c1*C_MMA} ns = {t10(pct(c1*C_MMA, blk64))}% of the {blk64} ns block; "
              f"per 256-token block at mt 4 = {c4} -> {c4*C_MMA} ns = {t10(pct(c4*C_MMA, blk64_256))}% of {blk64_256} ns" + (" -- MMA-bound" if c4 * C_MMA > blk64_256 else ""))
    print(f"[R4-kshape-verdict] f16 (16,16,k) EXACT at k in {{16, 32, 64, 128}} (session 1, 128 reps/shape): d = 128 mainline = one k = 128 call per 16 tokens (licensed); d = 64 = one k = 64 call (48 calls per block, 12.0 %); "
          f"the i8 variant keeps 2 x k = 32 at d = 64 (k = 64 wrong on i8); issue cost 15 ns measured at k = 128 only (k = 64 / 16 calls: ASSUMED 15 ns, UNMEASURED)")
    # ---- fresh chunk sets (erratum #19): L0C, L0A, drain, merge
    for mt in (1, 2, 3, 4, 5):
        print(f"[R4-l0c-mt{mt}] block {BL_of(mt)}: C_s {3*BL_of(mt)*16*4*mt//KiB} KiB (3 regions) + fresh C_o sets {co_sets(BL_of(mt))} x {16*D*4*mt//KiB} KiB = {l0c4(mt)//KiB} KiB"
              + (" (exactly full)" if l0c4(mt) == L0C else (" OVER 256 KiB" if l0c4(mt) > L0C else "")) + f"; L0A = Q {4*mt} + P 2 x {4*mt} = {l0a4(mt)//KiB} KiB (no -Q)")
    print(f"[R4-l0c-1024] mt = 1, 1024-token blocks: C_s 3 x 64 KiB + 8 fresh sets x 8 KiB = {(3*1024*16*4 + 8*16*D*4)//KiB} KiB (exactly full); 512-token blocks at mt = 1 with double-buffered C_o sets: {(l0c4(1) + 4*16*D*4)//KiB} KiB")
    for mt in (1, 2, 3, 4):
        d = ddr_block_ns(R_GEMM, mt); b = drain4_bytes(mt); thr = (b * 10 + d - 1) // d
        while tn(b, thr) > d: thr += 1
        print(f"[R4-drain-mt{mt}] drain bytes per block {b} (C_s {BL_of(mt)*16*4*mt} + C_o fresh sets {co_sets(BL_of(mt))*16*D*4*mt}; round 3: {drain_block_bytes(mt)}) -> hidden iff R_drain >= {thr} tenths GB/s/core; "
              f"measured {t10(R_DRAIN_M[mt])}: {drain4_ns(mt, R_DRAIN_M[mt])} ns per block = {t10(pct(drain4_ns(mt, R_DRAIN_M[mt]), d))}% ({t10(R_DRAIN_M[mt]*10//thr)}x margin)")
    for var, conv in CORNERS4:
        for bl in (512, 256, 128, 1024):
            m = merge4_100(bl, var, conv)
            print(f"[R4-merge-{var}-{conv}-{bl}] fresh-set merge at block {bl} ({co_sets(bl)} partials): {m//100} lane-eq = {m*10//(R_VEC*100)} ns (round 3 itemised {merge_item(var, conv)//100}, pack 25 750)")
    # ---- the bounce (erratum #20)
    for mt in (1, 2, 4):
        print(f"[R4-bounce-mt{mt}] P per block {p_bytes(mt)} B per core; DDR bytes per block (per core) K/V {BL_of(mt)*CORE_TOK} + bounce legs x {p_bytes(mt)}: "
              + "; ".join(f"legs {lg}: {ddr4_block_ns(R_GEMM, mt, lg)} ns at 174.6 ({t10(pct(ddr4_block_ns(R_GEMM, mt, lg) - ddr_block_ns(R_GEMM, mt), ddr_block_ns(R_GEMM, mt)))}% over round 3)" for lg in (0, 1, 2))
              + f"; at 169.2 legs 2: {ddr4_block_ns(G_SHUF[256*KiB], mt, 2)}; at 138.3: {ddr4_block_ns(G_K1[256*KiB], mt, 2)}")
    print(f"[R4-lift-density] P lifted per direct-load byte: {p_bytes(1)} B per {BL*CORE_TOK} B at mt 1 = 1/{BL*CORE_TOK//p_bytes(1)}, {p_bytes(4)} per {256*CORE_TOK} at mt 4 = 1/{256*CORE_TOK//p_bytes(4)}; the expert kernel lifts 2 KiB per 64 KiB = 1/32 -> {32*p_bytes(1)//(BL*CORE_TOK)}x / {32*p_bytes(4)//(256*CORE_TOK)}x (E24 at the real P cadence)")
    # ---- the chain (OPEN: softmax-reel anomaly), fixed cost
    for var, conv in CORNERS4:
        for bl in (512, 256, 128, 1024):
            v = vec4_ns(bl, 1, var, conv); d = ddr4_block_ns(R_GEMM, 1 if bl >= 512 else (3 if bl == 256 else 8), 2) if bl != 1024 else tn((1024 * CORE_TOK + 2 * 8 * 4096) * 8, R_GEMM)
            d0 = ddr_block_ns(R_GEMM, 1 if bl >= 512 else (3 if bl == 256 else 8)) if bl != 1024 else tn(1024 * CORE_TOK * 8, R_GEMM)
            print(f"[R4-chain-{var}-{conv}-{bl}] per fragment at block {bl}: {chain4_100(bl,1,var,conv)//100} lane-eq = {v} ns = {t10(pct(v, d))}% of the {d} ns block (174.6, legs 2) / {t10(pct(v, d0))}% of {d0} (legs 0); round 3: {vec3_ns(bl,1,var,conv,MERGE_PACK*100) if bl != 1024 else '-'} -- OPEN (softmax-reel anomaly, session 2)")
    for conv in ("T", "C"):
        print(f"[R4-firstmax-{conv}] lazy: first-block per-row max once per step at block 512 = {firstmax4_100(512,1,conv)//100} lane-eq = {firstmax4_ns(512,1,conv)} ns per fragment (cast {8192*UNIT[conv][1]//100} + tree {tree_ops(512)*UNIT[conv][0]//100} + 16 reduce {16*call100(T_RM16)//100} + reel {20*call100(T_F16)//100}); at block 256: {firstmax4_ns(256,1,conv)} ns")
    for var, conv in CORNERS4:
        s = step4(32768, 1, R_GEMM, var, conv)[1]
        print(f"[R4-fixed-{var}-{conv}] fixed cost at 32k, t = 1: {s['fixed']} ns = 2 x {s['vblk']} + drain {drain4_ns(1, R_DRAIN_M[1])} + tail ({tail4_tok(32768,1)} token: {tail4_ops(32768,1,1)*UNIT[conv][1]*10//(R_VEC*100)} ns)" + (f" + first-block max {firstmax4_ns(512,1,conv)}" if var == "lazy" else "") + f"; round 3: {step3(32768,1,R_GEMM,var,conv)[1]['fixed']}")
    # ---- t = 1 headline cells
    print("\n[R4-t1] t = 1 x L x G x legs x chain -> in-kernel ns (wall = + 91 000); G: p256k 169.2 (E21, design page), shuf64k 167.0, stream174, k1loop 138.3 (session-1 diagnostic loop), shuf16k 153.8")
    for k, L in LS.items():
        for gk, G in G4.items():
            for lg in (2, 1, 0):
                for var, conv in CORNERS4:
                    T, s, b = step4(L, 1, G, var, conv, legs=lg)
                    print(f"[R4-t1-{k}-{gk}-legs{lg}-{var}-{conv}] T={T} ns ({usR(T)} us; wall {usR(T+T_LAUNCH)}) bind={b} ddr={s['ddr']} vec={s['vec']} mma={s['mma']} ldr={s['loader']} drain={s['drain']} fixed={s['fixed']} vblk={s['vblk']} nb={s['nb']} "
                          f"| eff {t10(rateT(L*KV_TOK, T))} GB/s | x GEMV {t10(pct(T, T_GEMV))}%")
    for k in ("32k", "1M"):
        L = LS[k]
        for gk in ("p256k", "shuf64k", "k1loop"):
            G = G4[gk]; r3 = step3(L, 1, G if gk != "k1loop" else G, "lazy", "T")[0] if gk != "k1loop" else None
            a = step4(L, 1, G, "lazy", "T")[0]; a0 = step4(L, 1, G, "lazy", "T", legs=0)[0]; w = step4(L, 1, G, "lazy", "C")[0]; rm = step4(L, 1, G, "rowmax", "T")[0]; rc = step4(L, 1, G, "rowmax", "C")[0]
            print(f"[R4-moved-t1-{k}-{gk}] round-3 lazy-T {step3(L,1,G,'lazy','T')[0]} ({usR(step3(L,1,G,'lazy','T')[0])} us) / rowmax-T {step3(L,1,G)[0]} ({usR(step3(L,1,G)[0])}) -> round 4 lazy-T legs 2 {a} ({usR(a)} us, {'+' if a >= step3(L,1,G,'lazy','T')[0] else '-'}{t10(pct(abs(a - step3(L,1,G,'lazy','T')[0]), step3(L,1,G,'lazy','T')[0]))}%) / legs 0 {a0} ({usR(a0)}) / lazy-C {w} ({usR(w)}) / rowmax-T {rm} ({usR(rm)}) / rowmax-C {rc} ({usR(rc)})")
    for gk in ("p256k", "k1loop", "stream174"):
        G = G4[gk]
        for lg in (2, 0):
            d = ddr4_block_ns(G, 1, lg)
            print(f"[R4-t1-binding-{gk}-legs{lg}] block DDR {d} ns vs vector lazy-T {vec4_ns(512,1,'lazy','T')} / lazy-C {vec4_ns(512,1,'lazy','C')} / rowmax-T {vec4_ns(512,1,'rowmax','T')} / rowmax-C {vec4_ns(512,1,'rowmax','C')}: "
                  + ", ".join(f"{var}-{conv} {'DDR-bound' if vec4_ns(512,1,var,conv) <= d else 'VECTOR-bound'} (slack {d - vec4_ns(512,1,var,conv)} ns)" for var, conv in CORNERS4))
    # ---- merge as a hypothesis variable: thresholds at legs 2 / 0
    for gk in ("stream174", "p256k"):
        G = G4[gk]
        for lg in (2, 0):
            d = ddr4_block_ns(G, 1, lg)
            for var, conv in CORNERS4:
                base = chain4_100(512, 1, var, conv, 0); lim = (d + 1) * 4320 - 1 - base
                print(f"[R4-merge-threshold-{var}-{conv}-{gk}-legs{lg}] t = 1 DDR-bound iff merge <= {lim//100} lane-eq (fresh-set merge {merge4_100(512,var,conv)//100}: {'OK' if merge4_100(512,var,conv) <= lim else 'EXCEEDS'})")
    # ---- t = 16: two passes vs S4, t = 4 / 8 regime at 32k
    for t in (1, 2, 4, 8, 16):
        for var, conv in CORNERS4:
            T, s, b = step4(32768, t, G4["p256k"], var, conv)
            T0, s0, b0 = step4(32768, t, G4["p256k"], var, conv, legs=0)
            print(f"[R4-regime-t{t}-{var}-{conv}] rows={rows_of(t)} passes={s['passes']} mt={s['mt']} block={BL_of(s['mt'])}: at 169.2 legs 2 T={usR(T)} us bind={b} vec/ddr={t10(pct(s['vec'], s['ddr']))}% | legs 0 T={usR(T0)} us bind={b0} | round 3 {usR(step3(32768,t,G4['p256k'],var,conv)[0])}")
    for k in ("32k", "1M"):
        L = LS[k]
        for var, conv in (("lazy", "T"), ("rowmax", "T")):
            T2 = step4(L, 16, R_GEMM, var, conv)[0]; T1 = step4(L, 16, R_GEMM, var, conv, onepass=True)[0]
            print(f"[R4-t16-{k}-{var}-{conv}] two passes {T2} ({usR(T2)} us) vs S4 one pass {T1} ({usR(T1)} us): S4/two-pass = {t10(pct(T1, T2))}% (two passes win)")
    for var, conv in (("lazy", "T"), ("rowmax", "T")):
        lo, hi = 0, 400000
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if step4(32768, 16, R_GEMM, var, conv, merge100=mid * 100, onepass=True)[0] < step4(32768, 16, R_GEMM, var, conv, merge100=mid * 100)[0]: lo = mid
            else: hi = mid - 1
        print(f"[R4-s4-threshold-{var}-{conv}] S4 beats two passes at 32k iff merge <= {lo} lane-eq per block-fragment (fresh-set merge {merge4_100(128,var,conv)//100} / {merge4_100(256,var,conv)//100} at 128 / 256: two passes win)")
    for var, conv in CORNERS4:
        mt = 1
        while vec4_ns(BL_of(mt), mt, var, conv) < ddr4_block_ns(R_GEMM, mt, 2) and mt < 8: mt += 1
        mt0 = 1
        while vec4_ns(BL_of(mt0), mt0, var, conv) < ddr4_block_ns(R_GEMM, mt0, 0) and mt0 < 8: mt0 += 1
        print(f"[R4-rows*-{var}-{conv}] smallest mt with vector >= KV per block at 174.6: legs 2 mt={mt} -> rows*={16*mt} (t >= {ceil(16*mt, G_Q)}); legs 0 mt={mt0} -> rows*={16*mt0} (t >= {ceil(16*mt0, G_Q)})")
    # ---- KV-int8
    for var in ("rowmax", "lazy"):
        T, s, b = step4(32768, 1, G4["p256k"], var, "T", i8=True); T1, s1, b1 = step4(1 << 20, 1, G4["p256k"], var, "T", i8=True)
        print(f"[R4-i8-t1-{var}] KV-int8 at 169.2, legs 2: 32k {T} ({usR(T)} us) bind={b}; 1M {T1} ({usR(T1)} us); " + ("UNREACHABLE as specified: P quantised at the fixed scale 127 assumes p <= 1 but the lazy P reaches e^8 = 2981 (127 x 2981 saturates i8); reachable only at mu = 0 (trip rate UNMEASURED, E35 at mu = 0)" if var == "lazy" else "the rowmax chain's per-block max is what the fixed scale 127 needs"))
    # ---- lazy economics (section 3.4 closure)
    saved = vec4_ns(512, 1, "rowmax", "T") - vec4_ns(512, 1, "lazy", "T"); trip = vec4_ns(512, 1, "rowmax", "T") + 32 * C_MMA + drain4_ns(1, R_DRAIN_M[1])
    print(f"[R4-lazy-trip] per 512-token block the lazy chain saves {saved} ns ({vec4_ns(512,1,'rowmax','T')} - {vec4_ns(512,1,'lazy','T')}); a trip costs ~{trip} ns (the section-3.2 chain + {32*C_MMA} ns of re-issued PV calls + a {drain4_ns(1, R_DRAIN_M[1])} ns re-drain) -> the variant pays iff fewer than one trip per {trip*10//saved/10:.1f} blocks; "
          f"a needle profile (every block trips) costs +{64*trip} ns = {usR(64*trip)} us at 32k (64 blocks), +{2048*trip//1000} us at 1M; switch policy: after k = 3 trips in one step finish on the rowmax chain (worst case +{3*trip} ns + the rowmax cells)")
    # ---- causality at t > 1 (review item 6)
    for t in (1, 2, 4, 8, 16):
        worst = max(tail4_tok(L, t) for L in range(t, t + 16))
        print(f"[R4-tail-t{t}] tail tokens = (L - t) mod 16 + t: max {worst} (two 16-token groups: tails of 32 tokens = {32*D*2} B each); vector tail at the max = {worst*D*16*mt_of(rows_of(t))*4} lane-ops x mt {mt_of(rows_of(t))} = {worst*D*16*mt_of(rows_of(t))*4*137*10//43200} ns (T); mask {mask4_lanes(t, mt_of(rows_of(t)))} lanes = {mask4_lanes(t, mt_of(rows_of(t)))*137*10//43200} ns per step")
    # ---- planted sink (review item 7)
    for k, L in LS.items():
        print(f"[R4-sink-{k}] one sink at p = 1 and L - 1 tokens at p = 2^-25 (just under the f16 flush line 2^-24 = 5.96e-8): lost row mass {sink_lost_ppm(L)} ppm = {sink_lost_ppm(L)/10000:.2f} %; the same tokens with the shift offset beta = 3 nats sit at 2^-25 x e^3 (> the line): no loss")
    print(f"[R4-sink-line] f16 flushes p below 2^-24: s - m < -ln(2^24) = -16.6 nats (host arithmetic: e^16 = 8.89e6 < 2^24 = {2**24} < e^17 = 2.42e7); with the lazy shift m_r - beta the top of the range is e^beta (guard at e^(8+beta) must stay < 65 504: beta <= 3)")
    # ---- online-chain f32 drift (review item 5 re-aimed)
    for k, L in LS.items():
        for bl in (512, 256, 1024):
            nO, nS = chain_O(L, bl), chain_S(L, bl)
            print(f"[R4-drift-{k}-{bl}] partials {L//128}; longest f32 add chain O {nO}, S {nS}: deterministic first-order rel. error {rel_ppm(nO)} + {rel_ppm(nS)} = {rel_ppm(nO) + rel_ppm(nS)} ppm (ship line 1000 ppm: {'ships' if rel_ppm(nO) + rel_ppm(nS) < 1000 else 'FAILS'}); "
                  f"naive single-level O chain {L//128}: {rel_ppm(L//128)} ppm; random-walk sqrt({nO}) x 2^-24 = {isqrt(nO)*60} ppb")
    print(f"[R4-drift-retired] the region-difference bounds of round 2/3 (T_drift_1M: 683 visits x 32 -> ulp 2^-9 = 1953 ppm; T_drift_blocks: 1366 visits -> ulp 2^-8 = 3906 ppm) exceeded the 1000 ppm ship line deterministically (1M shipped only under the random-walk hypothesis); the mechanism is retired (erratum #19): fresh chunk sets have no region content")
    # ---- C_o stride math (review item 8) and 256 KiB pages (item 11)
    print(f"[R4-stride] C_o f32: row r of fragment f = 8 runs of 64 B at stride {co_addr(0,1,0,0) - co_addr(0,0,0,0)} B from f*{co_addr(1,0,0,0)} + r*{co_addr(0,0,1,0)} (dim j at +{co_addr(0,0,0,1)}); f16: 32 B runs at stride {co_addr16(0,1,0,0)} from f*{co_addr16(1,0,0,0)} + r*{co_addr16(0,0,1,0)}; m = 64 calls: stride {co_addr_m64(1,0,0) - co_addr_m64(0,0,0)}, row r at +{co_addr_m64(0,1,0)}; d = 64: 4 runs; out per step = {16*D*4} B x mt")
    print(f"[R4-page256] 256 KiB page = 4 sub-pages of 64 KiB, sub-page (l mod 1024) div 256: addr_K(300, 5) = {kAddr256(300, 5)} = 65536 + {kAddr64(44, 5)}; addr_V(1023, 127) = {vAddr256(1023, 127)} (max, even, < 262144); window 512 entries x 1024 tokens = {512*1024} tokens per 4 KiB (64 KiB pages: 131072)")
    # ---- page waste (review item 11)
    for P in (64 * KiB, 256 * KiB, MiB):
        w = page_waste(P)
        print(f"[R4-waste-{P//KiB}k] worst tail waste per (layer, sequence) {w} B = {w/MiB:.2f} MiB; per 15-layer dense die B = 1 / 8 / 16: {15*w/MiB:.0f} / {15*8*w/MiB:.0f} / {15*16*w/MiB:.0f} MiB; per 4-layer MoE die {4*w/MiB:.0f} / {4*8*w/MiB:.0f} / {4*16*w/MiB:.0f} MiB; "
              f"per 30-layer instance die B = 1: {30*w/MiB:.0f} MiB vs the instance-fit margins 3.3 / 15.0 / 24.5 / 2.7 MB (dense 32k / 128k, MoE 32k / 1M): {'EXCEEDS every margin' if 30*w > 24485516 else 'within some margins'}; dense 1M KV-int8 margin 1 656 740 864 B - 15 x {w} = {1656740864 - 15*w} B (fits)")
    # ---- fleet: the MoE-128k verdict with the bounce (review item 11: read the realised G)
    for lg in (2, 1, 0):
        verd = []
        for gk in ("p256k", "shuf64k", "k1loop", "stream174"):
            T = step4(131072, 1, G4[gk], "lazy", "T", legs=lg)[0]
            verd.append(f"{gk}: {'ATTN-bound' if T >= T_LAYER_MOE else 'weights-bound'} by {t10(pct(abs(T - T_LAYER_MOE), T_LAYER_MOE))}% ({abs(T - T_LAYER_MOE)//1000} us)")
        fx = step4(512, 1, R_GEMM, "lazy", "T", legs=lg)[1]["fixed"]; nb = nblocks4(131072, 1, 1); k0 = ceil(T_LAYER_MOE - fx, nb); Gs = (BL * CORE_TOK + bounce_bytes(1, lg)) * 8 * 10 // k0
        print(f"[R4-fleet-moe-128k-legs{lg}] lazy-T, legs {lg}: attention-bound iff G <= {Gs} tenths (fixed {fx}, {nb} blocks): " + "; ".join(verd))
    # ---- crossover (section 6.3) on the round-4 lazy chain
    for gk in ("stream174", "p256k", "k1loop"):
        G = G4[gk]
        for lg in (2, 0):
            kk = 1
            while step4(512 * kk, 1, G, "lazy", "T", legs=lg)[0] < T_GEMV: kk += 1
            La = 1
            while step4(La, 1, G, "lazy", "T", legs=lg)[0] < T_GEMV: La += 1
            Lm = 512 * kk
            while Lm > 1 and step4(Lm - 1, 1, G, "lazy", "T", legs=lg)[0] >= T_GEMV: Lm -= 1
            print(f"[R4-crossover-lazy-T-{gk}-legs{lg}] block {ddr4_block_ns(G,1,lg)} ns, fixed {step4(512,1,G,'lazy','T',legs=lg)[1]['fixed']}: smallest 512-multiple with step >= 398 us: k={kk} -> L_eq={512*kk} (step {step4(512*kk,1,G,'lazy','T',legs=lg)[0]}, at k-1 {step4(512*(kk-1),1,G,'lazy','T',legs=lg)[0]}); first L {La}, every L >= {Lm}" + ("" if La == Lm else " (not monotone between)"))
    # ---- buffers: US and S1 round 4
    for mt in (1, 2, 3, 4):
        r = us4_rows(mt); s = sum(r.values())
        print(f"[R4-us-mt{mt}] US = {s} B = {s//KiB} KiB + {s % KiB} B vs 208 KiB evidenced: {'FITS' if s <= US_EVID else 'OVER by ' + str(s - US_EVID)}; S1 = P ring {2*4*KiB*mt//KiB} KiB (no snapshots); DDR scratch for P {2*p_bytes(mt)//KiB} KiB; rows: " + ", ".join(f"{a} {b}" for a, b in r.items()))

if __name__ == "__main__":
    main4()

# ============================================================ ROUND 5 (2026-11-07): the measured production kernel (attention session 3) ====
# Silicon inputs (HW-MAP 62e8137; all MEASURED; no other silicon claim enters this section):
#   * the t x L sweep (causal flags incl. the guard, best-of-3, in-kernel us): t = 1: 213.5 / 1513.6 / 5852.9 / 46313.6 at 4k / 32k / 128k / 1M;
#     t = 4: 382.1 / 2695.6 / 10514.3 / 83123.1; t = 16: 1481.4 / 10741.7 / 42013.4 / 332476.2; quoted effective KV: t = 1 78.6 / 88.6 /
#     91.7 / 92.7 GB/s, t >= 4 99.6-103.4;
#   * UNGUARDED at 32k, t = 1: 938.8 us = 143.0 GB/s (the round-4 legs-2 cell, 912 us, within 2.9 %: the INPUT validation row);
#   * the guard's per-block scalar scan as shipped (8 reduce-max calls with a scalar destination + one queue fence per block): +572 us; tree +
#     queue +1250 us, tree + full barrier +1400 us (both worse); erratum #29: a per-block scalar crossing drains the vector pipe ~10-20 us,
#     a scalar-destination reduce-max costs ~1.1 us per call;
#   * realised bounce legs = 2, ~51 us at 32k; per-engine at 32k t = 1: stream 770.8 / scores 523.9 / softmax+guard 644.3 / PV-merge-bounce
#     344.9 us (the K+V stream phase 174-176 GB/s; DDR ~47 % idle: the chain binds);
#   * correctness: causal-exact 12/12 at 32k (relerr 9.8e-11), real-exp bad-0 through 1M; online-chain drift at 1M 1.2e-6 / 1.8e-6
#     (session 2, 512 / 256-token blocks); trips ~free, the trip machinery REQUIRED.
# Readings this section derives (D) from those inputs: the guard per block (the t = 1 table difference at 32k over its 64 blocks), the
# batched-crossing chain model (erratum #29), the unguarded / fused per-L cells (guarded per-L MEASURED minus the per-block guard; the
# per-block guard off 32k is UNMEASURED), the phase-overlap bound, the rowmax-chain crossing bound. Every [A*] / [R3-*] / [R4-*] label
# above keeps printing its value; the [R5-*] labels below are the round-5 cells.
LS5 = (4096, 32768, 131072, 1 << 20)
LK5 = ("4k", "32k", "128k", "1M")
T5 = {1: (213_500, 1_513_600, 5_852_900, 46_313_600), 4: (382_100, 2_695_600, 10_514_300, 83_123_100),
      16: (1_481_400, 10_741_700, 42_013_400, 332_476_200)}        # ns in-kernel, best-of-3, causal flags incl. the guard (M)
EFF5_Q1 = (786, 886, 917, 927)                                     # HW-MAP's quoted t = 1 effective KV, tenths GB/s (M, as quoted)
EFF5_QHI = (996, 1034)                                            # its quoted t >= 4 range (tenths)
T5_UNG, G5_UNG_Q = 938_800, 1430                                  # unguarded, 32k, t = 1 (M)
GUARD5_Q, GUARD5_TQ, GUARD5_TB = 572_000, 1_250_000, 1_400_000    # guard as shipped / tree + queue / tree + full barrier, 32k (M)
C5_SDST, C5_X = 1_100, (10_000, 20_000)                           # erratum #29: scalar-destination reduce-max; one crossing drain (M, approx.)
BOUNCE5, LEGS5 = 51_000, 2                                        # the realised P bounce at 32k, t = 1 (M)
ENG5, STREAM5 = (523_900, 644_300, 344_900), 770_800              # per-engine phases at 32k t = 1: scores / softmax+guard / PV-merge-bounce; stream (M)
STREAM5_Q, IDLE5_Q = (1740, 1760), 47                             # quoted K+V stream-phase rate (tenths) and DDR idle share (%) (M, as quoted)
DRIFT5_PPM10 = (12, 18)                                           # online-chain drift at 1M, tenths of ppm, 512 / 256-token blocks (M, session 2)
MATCH5 = 50                                                       # the 5.0 % model-match line (tenths of a percent), PROMPT-3R5
NB32 = 64                                                         # 512-token blocks at 32k, t = 1 (nblocks4)
def x10r(a, b): return (20 * a + b) // (2 * b)                    # a / b in tenths, round-half-up
def nb5(L, t=1): return nblocks4(L, t, mt_pass(rows_of(t)))       # blocks per pass (512-token at mt <= 2, 256 at mt 3-4)
def frags5(t): return ceil(rows_of(t), 16)                         # 16-row fragments summed over the passes (t = 1: one, half full)
def guard5(L): return nb5(L) * (T5[1][1] - T5_UNG) // NB32         # the as-shipped guard scan, scaled per block (D; 574 800 ns at 32k)
def bounce5(L): return nb5(L) * BOUNCE5 // NB32                    # the measured bounce, scaled per block (D)
def stream5(L): return nb5(L) * STREAM5 // NB32                    # the measured K+V stream phase, scaled per block (D)
def ung5(L): return T5[1][LS5.index(L)] - guard5(L)                # reading (ii): guarded per-L (M) minus the per-block guard; exact at 32k
def rate5(L, G): return L * KV_TOK * 10 // G                       # reading (i): a constant effective rate G at every L
def xing5(nb, K, cx): return ceil(nb, K) * cx                      # batched crossings: one crossing per K blocks, each draining cx ns
def fused5(L, cx=C5_X[1], K=None): return ung5(L) + xing5(nb5(L), nb5(L) if K is None else K, cx)
def overlap5(L): return ung5(L) - stream5(L) - bounce5(L)          # what full phase overlap could recover at most (D, upper bound)
X5_ROWMAX = min(16 * C5_SDST, C5_X[0] + 16 * SIGMA_S3 // 10)      # rowmax chain: 16 row maxima reach Duplicate every block (>= one crossing)

def main5():
    print("\n# ---- ROUND 5 (2026-11-07; the measured production kernel, attention session 3, HW-MAP 62e8137): [R5-*] cells; [A*]/[R3-*]/[R4-*] above unchanged ----")
    g256 = G_SHUF[256 * KiB]; tab = T5[1][1] - T5_UNG
    m4 = {t: [step4(L, t, g256, "lazy", "T")[0] for L in LS5] for t in (1, 4, 16)}
    # ---- the t x L sweep as MEASURED rows, with the derived per-block and per-fragment readings
    for t in (1, 4, 16):
        for i, L in enumerate(LS5):
            T = T5[t][i]; nb = nb5(L, t); p = passes_of(rows_of(t)); f = frags5(t)
            q = f" (quoted {t10(EFF5_Q1[i])})" if t == 1 else ""
            print(f"[R5-meas-t{t}-{LK5[i]}] MEASURED {T} ns ({t10(T // 100)} us; wall {usR(T + T_LAUNCH)} us): rows {rows_of(t)}, {p} pass(es) x {nb} blocks of {BL_of(mt_pass(rows_of(t)))}, {f} fragment(s); "
                  f"eff KV {t10(rateT(L * KV_TOK, T))} GB/s{q}; per fragment-pass {t10(rateT(f * L * KV_TOK, T))}; per block-pass {T // (p * nb)} ns; x GEMV {t10(pct(T, T_GEMV))}% ; "
                  f"round-4 model (lazy-T, legs 2, 169.2) {m4[t][i]} ns -> measured / model = {t10(x10r(T, m4[t][i]))}x")
    print(f"[R5-meas-eff-check] t = 1 recomputed eff (rateT, round-half-up): {', '.join(t10(rateT(L * KV_TOK, T5[1][i])) for i, L in enumerate(LS5))} vs quoted 78.6 / 88.6 / 91.7 / 92.7 -- "
          f"32k recomputes to {t10(rateT(32768 * KV_TOK, T5[1][1]))} (134 217 728 B / 1 513 600 ns = 88.67; the quote is the floored tenth); t >= 4 quotes are per fragment-pass "
          f"((rows/16) x KV / T): {', '.join(t10(rateT(frags5(t) * L * KV_TOK, T5[t][i])) for t in (4, 16) for i, L in enumerate(LS5))} -- the quoted 99.6-103.4 covers L >= 32k (4k: 87.8 / 90.6)")
    # ---- the validation row (INPUT) and its term-level reading
    d = T5_UNG - m4[1][1]
    print(f"[R5-validate] INPUT: unguarded 32k t = 1 {T5_UNG} ns ({t10(rateT(32768 * KV_TOK, T5_UNG))} GB/s) vs the round-4 legs-2 cell {m4[1][1]} ns: +{d} ns = {t10(pct(d, m4[1][1]))}% of the exact cell "
          f"({t10(pct(T5_UNG - 912_000, 912_000))}% of the displayed 912 us); within the {t10(MATCH5)}% match line: {1000 * d <= MATCH5 * m4[1][1]} (needs <= {MATCH5 * m4[1][1] // 1000} ns)")
    kv169 = NB32 * ddr4_block_ns(g256, 1, 0); b169 = NB32 * ddr4_block_ns(g256, 1, 2) - kv169; fx = step4(32768, 1, g256, "lazy", "T")[1]["fixed"]
    rest = T5_UNG - STREAM5 - BOUNCE5
    print(f"[R5-validate-terms] the cell-level match nets offsetting terms: model = K/V at 169.2 {kv169} + bounce (legs 2 on the roof) {b169} + fixed {fx} = {kv169 + b169 + fx}; "
          f"measured = K+V stream phase {STREAM5} ({t10(rateT(32768 * KV_TOK, STREAM5))} GB/s) + bounce ~{BOUNCE5} + the rest {rest}; model - measured: K/V basis +{kv169 - STREAM5}, bounce +{b169 - BOUNCE5}, "
          f"fixed vs exposed chain -{rest - fx} -> net -{T5_UNG - kv169 - b169 - fx}; the measured bounce is {t10(pct(BOUNCE5, b169))}% of the modelled roof charge")
    # ---- per-engine: the chain is serial, guarded and unguarded
    s3 = sum(ENG5); sg = ENG5[1] - tab
    print(f"[R5-engines] guarded phases scores {ENG5[0]} + softmax+guard {ENG5[1]} + PV-merge-bounce {ENG5[2]} = {s3} ns vs the total {T5[1][1]} (|diff| {abs(T5[1][1] - s3)} ns = {t10(pct(abs(T5[1][1] - s3), T5[1][1]))}%): "
          f"the phases SERIALISE; stream {STREAM5} = {t10(pct(STREAM5, s3))}% busy ({t10(1000 - pct(STREAM5, s3))}% idle by this split; quoted ~{IDLE5_Q}%); per block {ENG5[0] // NB32} / {ENG5[1] // NB32} / {ENG5[2] // NB32} ns")
    print(f"[R5-engines-unguarded] softmax without the guard {ENG5[1]} - {tab} = {sg} ns ({sg // NB32} ns per block vs the round-4 lazy-T chain without its guard calls {vec4_ns(512, 1, 'lazy', 'T') - 8 * call100(T_RM16) * 10 // (R_VEC * 100)} ns: "
          f"{t10((vec4_ns(512, 1, 'lazy', 'T') - 8 * call100(T_RM16) * 10 // (R_VEC * 100)) * 10 // (sg // NB32))}x); serial sum without the guard {ENG5[0] + sg + ENG5[2]} vs the measured unguarded {T5_UNG} "
          f"(|diff| {abs(ENG5[0] + sg + ENG5[2] - T5_UNG)}): the unguarded kernel is phase-serial too -- stream busy {t10(pct(STREAM5, T5_UNG))}%, not the binding engine")
    # ---- the guard (erratum #29) and the round-4 assumption it refutes
    gq = GUARD5_Q // NB32; gt = tab // NB32
    print(f"[R5-guard] as shipped: table difference {T5[1][1]} - {T5_UNG} = {tab} ns (quoted +{GUARD5_Q}: {tab - GUARD5_Q} ns = {t10(pct(tab - GUARD5_Q, GUARD5_Q))}% apart, two measured readings); "
          f"per block {gt} ns ({gq} quoted); 8 scalar-destination reduce calls x {C5_SDST} = {8 * C5_SDST} ns = {t10(pct(8 * C5_SDST, gt))}% of it -- the scalar-destination reduce IS the crossing; "
          f"{t10(pct(tab, T5_UNG))}% of the unguarded kernel, {t10(pct(tab, T5[1][1]))}% of the guarded")
    print(f"[R5-guard-alt] tree + queue {GUARD5_TQ} = {GUARD5_TQ // NB32} ns per block (one crossing per block, in the {C5_X[0]}-{C5_X[1]} ns band: {C5_X[0] <= GUARD5_TQ // NB32 <= C5_X[1]}); "
          f"tree + full barrier {GUARD5_TB} = {GUARD5_TB // NB32} ns per block ({GUARD5_TB // NB32 - C5_X[1]} ns above the band); both worse than shipped by {GUARD5_TQ - tab} / {GUARD5_TB - tab} ns")
    g4 = 8 * call100(T_RM16) * 10 // (R_VEC * 100); sl = ddr4_block_ns(g256, 1, 2) - vec4_ns(512, 1, "lazy", "T")
    print(f"[R5-A5-refuted] round 4 modelled the guard as 8 vector-destination reduce calls ({g4} ns) + one queue fence (A5: < 1 000 ns) inside a DDR-bound block with {sl} ns of slack -> 0 ns on the cell; "
          f"measured: {gt} ns per block, serialised ({t10(gt * 10 // 1000)}x the A5 ceiling); the 'per-block scalar reads ~ free' premise of sections 3.2 / 3.4 is refuted (erratum #29)")
    # ---- the batched-crossing model (the corrected chain cost)
    for K in (1, 8, NB32):
        cells = []
        for cx in C5_X:
            T = T5_UNG + xing5(NB32, K, cx)
            cells.append(f"cx {cx // 1000} us: {xing5(NB32, K, cx)} ns -> {T} ns = {t10(rateT(32768 * KV_TOK, T))} GB/s, guard fusion worth {tab - xing5(NB32, K, cx)} ns")
        print(f"[R5-crossing-K{K}] one crossing per {K} block(s) at 32k ({ceil(NB32, K)} crossings): " + "; ".join(cells))
    print(f"[R5-crossing-target] the 'fused target ~140 GB/s' = the unguarded kernel + ONE crossing per step at the band's top: {T5_UNG} + {C5_X[1]} = {T5_UNG + C5_X[1]} ns = {t10(rateT(32768 * KV_TOK, T5_UNG + C5_X[1]))} GB/s "
          f"({t10(rateT(32768 * KV_TOK, T5_UNG + C5_X[0]))} at the bottom); worth {tab - C5_X[1]} - {tab - C5_X[0]} ns per layer; zero-residual ceiling {tab} ns (~570 us = the prompt's figure)")
    # ---- the rowmax chain under erratum #29 (the fallback and KV-int8)
    i8m = step4(32768, 1, g256, "rowmax", "T", i8=True)[0]; i8m1 = step4(1 << 20, 1, g256, "rowmax", "T", i8=True)[0]
    print(f"[R5-rowmax-bound] the section-3.2 chain builds its shift reel by Duplicate from the 16 row maxima every block: >= one crossing per block = min(16 x {C5_SDST}, {C5_X[0]} + 16 x sigma_s) = {X5_ROWMAX} ns "
          f"(UNMEASURED structure, lower bound); rowmax >= unguarded + nb x {X5_ROWMAX}: 32k >= {T5_UNG + NB32 * X5_ROWMAX} ns ({t10(rateT(32768 * KV_TOK, T5_UNG + NB32 * X5_ROWMAX))} GB/s) > the guarded lazy {T5[1][1]}; "
          f"1M >= {ung5(1 << 20) + 2048 * X5_ROWMAX} > {T5[1][3]} -- the round-4 switch policy (finish on rowmax after 3 trips, '917 us') is VOID: never switch")
    print(f"[R5-rowmax-i8] KV-int8 on the rowmax chain (round 4: {i8m} ns at 32k, {i8m1} at 1M, vector-bound) + the per-block crossing: >= {i8m + NB32 * X5_ROWMAX} / {i8m1 + 2048 * X5_ROWMAX} ns "
          f"(> the fused f16 lazy {fused5(32768)} at 32k); KV-int8 lives only on the lazy mu = 0 variant (trip rate UNMEASURED, E35 model half)")
    # ---- the unguarded / fused readings per L, the overlap bound, the measured bounce
    for i, L in enumerate(LS5):
        u, fz = ung5(L), fused5(L); r1, r2 = rate5(L, G5_UNG_Q), rate5(L, 1400)
        print(f"[R5-ung-{LK5[i]}] guarded {T5[1][i]} (M) - guard {guard5(L)} ({nb5(L)} blocks) = unguarded {u} ns ({t10(rateT(L * KV_TOK, u))} GB/s){' (M)' if L == 32768 else ' (D)'}; "
              f"fused (one 20 us crossing) {fz} ({t10(rateT(L * KV_TOK, fz))}), at 10 us {fused5(L, C5_X[0])}; rate reading (i): unguarded at 143.0 {r1}, fused at 140.0 {r2}; "
              f"round-4 model {m4[1][i]}: unguarded/model {t10(pct(u, m4[1][i]))}%")
        print(f"[R5-overlap-{LK5[i]}] stream {stream5(L)} + bounce {bounce5(L)} = {stream5(L) + bounce5(L)} ns ({t10(rateT(L * KV_TOK, stream5(L) + bounce5(L)))} GB/s, the overlapped floor); "
              f"phase-overlap gap <= {overlap5(L)} ns ({t10(pct(overlap5(L), u))}% of the unguarded cell); measured bounce removal {bounce5(L)} ns (round 4 legs 2 -> 0 at 169.2: {nb5(L) * (ddr4_block_ns(g256, 1, 2) - ddr4_block_ns(g256, 1, 0))})")
    # ---- the drift (E26' closed) and E35's device half
    b512, b256 = rel_ppm(chain_O(1 << 20, 512)) + rel_ppm(chain_S(1 << 20, 512)), rel_ppm(chain_O(1 << 20, 256)) + rel_ppm(chain_S(1 << 20, 256))
    print(f"[R5-drift] E26' CLOSED (session 2): online-chain drift at 1M {t10(DRIFT5_PPM10[0])} / {t10(DRIFT5_PPM10[1])} ppm (512 / 256-token blocks) vs the deterministic bound {b512} / {b256} ppm "
          f"({b512 * 10 // DRIFT5_PPM10[0]}x / {b256 * 10 // DRIFT5_PPM10[1]}x inside) and the 1000 ppm ship line ({10000 // DRIFT5_PPM10[0]}x / {10000 // DRIFT5_PPM10[1]}x inside)")
    print(f"[R5-e35] E35 device half RESOLVED: the trip machinery is REQUIRED and trips are ~free (session 3); the SCAN is the cost ({tab} ns at 32k = {gt} ns per block); "
          f"still open (model half): the trip rate per (model, L) at mu = 8, beta = 3 and at mu = 0; with a batched guard a trip found at the batch crossing re-streams its block (~{ddr4_block_ns(g256, 1, 2) + vec4_ns(512, 1, 'rowmax', 'T')} ns, UNMEASURED)")
    # ---- t >= 4: the measured rows against the round-4 regime cells
    for t in (4, 16):
        f = frags5(t); per = [T5[t][i] * 512 // (f * L_matrix4(L, t)) for i, L in enumerate(LS5)]
        print(f"[R5-t{t}] measured / round-4 model: {', '.join(t10(x10r(T5[t][i], m4[t][i])) + 'x' for i in range(4))}; per fragment per 512 tokens {', '.join(str(x) for x in per)} ns "
              f"(t = 1: {', '.join(str(T5[1][i] * 512 // L_matrix4(L, 1)) for i, L in enumerate(LS5))}) -- the guarded multi-fragment kernel scales with the fragment count (no stream amortisation); "
              f"the unguarded t >= 4 kernel is UNMEASURED")
    # ---- the attention fraction of the GEMV step and the crossover (chord between measured points)
    def chord_first(T4k, T32k):
        nb = 8
        while T4k + (nb - 8) * (T32k - T4k) // 56 < T_GEMV: nb += 1
        return nb, 512 * (nb - 1) + 17
    nbg, Lg = chord_first(T5[1][0], T5[1][1]); nbu, Lu = chord_first(ung5(4096), T5_UNG)
    print(f"[R5-gemv] x GEMV (398 us unit), MEASURED guarded: {', '.join(t10(pct(T5[1][i], T_GEMV)) + '%' for i in range(4))}; unguarded 32k {t10(pct(T5_UNG, T_GEMV))}% (round 4 legs 2: {', '.join(t10(pct(m4[1][i], T_GEMV)) + '%' for i in range(4))})")
    print(f"[R5-crossover] chord between the 4k and 32k cells (D; UNMEASURED in between): guarded reaches one GEMV unit at nb >= {nbg} -> L >= {Lg}; unguarded (4k derived) at nb >= {nbu} -> L >= {Lu}; round 4: 14 336 / 13 841 (legs 2, 169.2)")
    # ---- the planner reading: MoE 128k with the measured bounce and the measured kernel
    bl = 256 * BOUNCE5 // NB32; k0 = ceil(T_LAYER_MOE - bl, 256); kf = ceil(T_LAYER_MOE - bl - 19_328, 256)
    print(f"[R5-fleet-moe-128k] measured kernel per layer: guarded {T5[1][2]} / unguarded {ung5(131072)} / fused {fused5(131072)} ns vs the {T_LAYER_MOE} ns MoE layer: ATTN-bound by "
          f"{t10(pct(T5[1][2] - T_LAYER_MOE, T_LAYER_MOE))} / {t10(pct(ung5(131072) - T_LAYER_MOE, T_LAYER_MOE))} / {t10(pct(fused5(131072) - T_LAYER_MOE, T_LAYER_MOE))}%; effective-rate line: attention-bound iff G_eff <= "
          f"{131072 * KV_TOK * 10 // T_LAYER_MOE} tenths; with the MEASURED legs-2 bounce ({bl} ns at 128k) the stream-only line is G <= {20971520 // k0} (zero fixed cost; {20971520 // kf} with the 19 328 ns lazy fixed) "
          f"vs the round-4 legs-2 line 189.4 -> attention-bound at every G <= 174.6 even with zero chain cost")
    # ---- the moved cells (round 4 -> round 5)
    print(f"[R5-moved] round 4 (lazy-T, legs 2, 169.2) -> round 5 MEASURED (guarded) / D (unguarded): t = 1 {', '.join(f'{LK5[i]} {usR(m4[1][i])} -> {t10(T5[1][i] // 100)} / {usR(ung5(L))} us' for i, L in enumerate(LS5))}; "
          f"t = 4 32k {usR(m4[4][1])} -> {t10(T5[4][1] // 100)}; t = 16 32k {usR(m4[16][1])} -> {t10(T5[16][1] // 100)}; drift bound 246 ppm -> measured 1.2 ppm; the switch-to-rowmax worst case 917 us -> void")

if __name__ == "__main__":
    main5()


# =====================================================================================================================================
# PROMPT-6 (2026-11-08) — the new-errata audit (#18-#31) + the E40 stage-overlap pre-design (DESIGN-3, round-6 layer "E40").
# No new silicon claims. Inputs: the session-3 phases above (ENG5, STREAM5, BOUNCE5, T5, T5_UNG; MEASURED) and the deferred-guard cells
# of kernel session 5 (HW-MAP, the DEFERRED GUARD row; MEASURED, production flags, trips 0). Labels: [PA-*] = audit cells (errata
# #22/#25/#29/#31 consequences for this design's DERIVED rows), [E40-*] = the pre-design (structure + the reachable-overlap bound,
# parameterized on the measured phase deltas). Every label above keeps printing its value.
#
# The E40 schedule model (DESIGN-3 "Round 6 (PROMPT-6) — E40"): one macro-step per block = the block's tile intervals (8 at 512-token
# blocks: 4 K + 4 V tiles of 32 KiB, each closed by the full barrier erratum #14 requires). A full barrier waits for every pipe, so
# vector work overlaps the stream only INSIDE a tile interval; the block's vector work V is cut into k slices (k vector-carrying
# intervals). Per macro-step: sum_j max(d_j, w_j) = 8 d + (V - k d)^+ for even slices; plus phi per vector-carrying barrier (the cost of
# a full barrier issued with vector work in flight — UNMEASURED, E40a; erratum #29 measured 10-20 us for barrier/queue + scalar read).
#   T_E40 = floor + nb * ((V - k d)^+ + k phi) + tau + nx * cx      (floor = the DDR engine's measured stream + bounce)
# =====================================================================================================================================
T6_DFR = {32768: 945_500, 131072: 3_618_800, 1 << 20: 28_694_000}   # deferred guard, trip-free, t = 1 (M, session 5)
T6_AMORT32 = (946_300, 947_400)                                      # amortized at the real trip rate 0.087-0.22 % of steps, 32k (M, session 5)
T6_OFF32, T6_LEG32, T6_CANON32 = 902_900, 1_514_900, 1_818_100     # session 5, 32k t = 1: guard-off / legacy scan / canonical adversarial (M)
FOLD6 = T6_DFR[32768] - T6_OFF32                                    # 42 600 ns per step: the deferred guard over guard-off (D) = fold + end read
MOE_LAYERS6 = 28                                                    # DESIGN-4 MoE layers (fleet.py LAYERS4: 4 dies x 7)
TILES6 = 8                                                          # 32 KiB K/V tiles per 512-token block per core, one full barrier each
CX6 = (0, 10_000, 20_000)                                           # the end-of-step read's serial cost bracket (0 .. the #29 band top)
S1_SLOT6 = 32 * KiB                                                 # erratum #25: the proven S1 A-slot staging granularity (or offset-0 4 KiB)

def floorF1(L): return stream5(L) + bounce5(L)                      # the round-5 overlapped floor: the K+V stream phase + the measured bounce
def floorF2(L, g): return nb5(L) * ddr4_block_ns(g, 1, 0) + bounce5(L)   # the E21 basis (per-tile barrier + MMA at 169.2) + the bounce
def e40_step(floor, nb, V, k, d, phi, tau=0, nx=0, cx=0):
    return floor + nb * max(0, V - k * d) + nb * k * phi + tau + nx * cx
def phi_line(Tbase, floor, nb, V, k, d, tau=0, nx=0, cx=0):         # the largest phi (ns) with e40_step < Tbase; None if none >= 0
    r = Tbase - floor - nb * max(0, V - k * d) - tau - nx * cx
    return (r - 1) // (nb * k) if r > 0 else None
def k_min(V, d): return max(1, ceil(V, d))                          # vector-carrying intervals needed for no excess
def pieces6(mt): return co_sets(BL_of(mt)) * mt                     # 4 KiB P pieces per block per core (one per 128-token group per fragment)

def main6a():
    g256 = G_SHUF[256 * KiB]; tab = T5[1][1] - T5_UNG
    # ---------------------------------------------------------------- audit cells (DESIGN-3 rows the new errata touch) -------------
    det = 16 * C5_SDST                                              # 16 scalar-destination reduce calls: the proven-deterministic crossing
    print(f"[PA-rowmax-det] erratum #31: the rowmax chain's cheaper crossing (one drain + 16 scalar reads of fresh reduce-max results, {C5_X[0] + 16 * SIGMA_S3 // 10} ns) is the "
          f"racing composition; the deterministic one is 16 scalar-destination reduces = {det} ns per block: rowmax >= {T5_UNG} + {NB32} x {det} = {T5_UNG + NB32 * det} ns at 32k "
          f"({t10(rateT(32768 * KV_TOK, T5_UNG + NB32 * det))} GB/s), 1M >= {ung5(1 << 20) + 2048 * det} ns; the round-5 bound ({X5_ROWMAX} ns per block) stays a valid lower bound; the verdict (never switch) strengthens")
    fm = firstmax4_ns(512, 1, "T"); rm = 16 * call100(T_RM16) * 10 // (R_VEC * 100); fmd = fm - rm + det; fx = step4(32768, 1, g256, "lazy", "T")[1]["fixed"]
    print(f"[PA-firstmax-det] erratum #29/#31: the lazy chain's first-block max reaches the shift reel's Duplicate operands as 16 scalars once per step; deterministic path = 16 "
          f"scalar-destination reduces ({det} ns) instead of 16 vector-destination calls read back at a fence ({rm} ns, the racing composition): first-block max {fm} -> {fmd} ns, "
          f"round-4 fixed cost {fx} -> {fx - fm + fmd} ns (+{fmd - fm}) -- DERIVED; the MEASURED cells (6.0) carry whatever the shipped kernel does")
    for mt in (1, 2, 3, 4):
        print(f"[PA-s1-pring-mt{mt}] erratum #25: the round-4 S1 P ring (2 x 4 KiB x mt = {2 * 4 * mt} KiB, slot offsets 4 KiB apart) violates the offset rule; "
              f"32-KiB-granular slots: 2 x {mt} x 32 KiB = {2 * mt * S1_SLOT6 // KiB} KiB of S1 (~1 MB PRIOR: fits); or one 4 KiB piece at offset 0 per lift")
    tail16 = 16; dups = 2 * tail16 * D; dns = dups * T_F16 // 10
    print(f"[PA-tail-dup] erratum #22: the vector tail of 2.2 / 10.8 (16-row Muls + Adds over K_tail / V_tail) multiplies by a K or V scalar per (token, dim) -- unary Muls is a silent no-op; "
          f"the Duplicate + Mul repair needs {dups} Duplicate calls per step at a {tail16}-token tail = {dns} ns at A3 (46.4 ns per small call) vs the round-4 tail term "
          f"{tail4_ops(32768, 1, 1) * UNIT['T'][1] * 10 // (R_VEC * 100)} ns -- not viable; the padded matrix-path tail (the open group's K call tile masked, V_tail COPY_FRAC'd "
          f"into a scratch B tile: {tn(16 * D * 2, R_FRAC)} ns + 9 calls x 15 = {tn(16 * D * 2, R_FRAC) + 9 * 15} ns, UNMEASURED) is the fix")
    # ---------------------------------------------------------------- E40: inputs, per-tile, per-block vector work ------------------
    soft = (ENG5[1] - tab) // NB32; fold = FOLD6 // NB32; mrg = merge4_100(512, "lazy", "T") * 10 // (R_VEC * 100)
    d1 = STREAM5 // (NB32 * TILES6); d2 = ddr4_block_ns(g256, 1, 0) // TILES6
    Vlo, Vhi = soft + (FOLD6 - CX6[2]) // NB32, soft + fold + mrg     # V in [soft + fold at a 20 us end read, soft + all the fold + merge]
    print(f"[E40-inputs] MEASURED phases at 32k t = 1 (session 3): stream {STREAM5}, scores {ENG5[0]}, softmax+guard {ENG5[1]}, PV-merge-bounce {ENG5[2]}, bounce {BOUNCE5} ns; "
          f"serial sum {sum(ENG5)} (legacy) / {ENG5[0] + ENG5[1] - tab + ENG5[2]} (unguarded); session 5: deferred {T6_DFR[32768]}, guard-off {T6_OFF32}, legacy {T6_LEG32}, "
          f"canonical {T6_CANON32}, amortized {T6_AMORT32[0]}-{T6_AMORT32[1]} ns; fold + end read = {FOLD6} ns per step (split UNMEASURED)")
    print(f"[E40-tile] per-tile DDR time: F1 (stream phase) {STREAM5} / ({NB32} x {TILES6}) = {d1} ns; F2 (E21 basis, per-tile barrier + MMA) {ddr4_block_ns(g256, 1, 0)} / {TILES6} = {d2} ns; "
          f"per block {TILES6} full barriers (4 K + 4 V tiles; 4 at 256-token blocks) -- E40 adds none")
    print(f"[E40-vec] vector work per block: softmax (unguarded, MEASURED) {ENG5[1] - tab} / {NB32} = {soft} ns + fold (353-665: the fold + end-read split of {FOLD6} is UNMEASURED, the end read <= 20 us) + merge (round-4 model, lazy-T, 0-{mrg}) "
          f"-> V in [{Vlo}, {Vhi}] ns; k_min = {k_min(Vlo, d1)} .. {k_min(Vhi, d1)} (F1) / {k_min(Vlo, d2)} .. {k_min(Vhi, d2)} (F2) vector-carrying intervals of {TILES6}; "
          f"excess at k = 1: {max(0, Vhi - d1)} ns (F1)")
    # ---------------------------------------------------------------- E40: floors, prizes, fractions -------------------------------
    for L in (32768, 131072, 1 << 20):
        nb = nb5(L); f1, f2 = floorF1(L), floorF2(L, g256); Tb = T6_DFR[L]; lk = LK5[LS5.index(L)]
        print(f"[E40-floor-{lk}] nb {nb}: F1 = stream {stream5(L)} + bounce {bounce5(L)} = {f1} ns ({t10(rateT(L * KV_TOK, f1))} GB/s); F2 = {nb} x {ddr4_block_ns(g256, 1, 0)} + {bounce5(L)} = {f2} ns "
              f"({t10(rateT(L * KV_TOK, f2))} GB/s); deferred (M) {Tb} ns ({t10(rateT(L * KV_TOK, Tb))} GB/s)")
        cells = []
        for cx in CX6:
            p1, p2 = Tb - f1 - cx, Tb - f2 - cx
            cells.append(f"end read {cx // 1000} us: F1 {p1} ({t10(pct(p1, Tb))}%) / F2 {p2} ({t10(pct(p2, Tb))}%)")
        print(f"[E40-prize-{lk}] the reachable-overlap bound on the deferred kernel (phi = 0, tau = 0, V <= k d): gain <= deferred - floor - end read: " + "; ".join(cells))
        print(f"[E40-prize-{lk}-moe] x {MOE_LAYERS6} MoE layers per token (DESIGN-4 cell; round 5 at the unguarded reading: {MOE_LAYERS6} x {overlap5(L)} = {MOE_LAYERS6 * overlap5(L)} ns): "
              f"F1 {MOE_LAYERS6 * (Tb - f1)} / F2 {MOE_LAYERS6 * (Tb - f2)} ns at a free end read, {MOE_LAYERS6 * (Tb - f1 - CX6[2])} / {MOE_LAYERS6 * (Tb - f2 - CX6[2])} at 20 us")
    # ---------------------------------------------------------------- E40: the phi lines (the gate) --------------------------------
    # the session-5 difference fixes fold + end read = FOLD6 per step; a crossing costs <= 20 us (#29), so the fold carries >= the rest:
    # consistent splits (end read cx, fold per block): (0, 665), (10 us, 509), (20 us, 353); the merge (inside the PV phase) in [0, 357]
    splits = [(cx, (FOLD6 - cx) // NB32) for cx in CX6]
    gate = []
    for (lab, fl, d) in (("F1", floorF1(32768), d1), ("F2", floorF2(32768, g256), d2)):
        rows = []
        for (cx, fb) in splits:
            for m in (0, mrg):
                V = soft + fb + m
                for k in (1, 2, 8):
                    ph = phi_line(T6_DFR[32768], fl, NB32, V, k, d, 0, 1, cx); rows.append(f"cx {cx // 1000} V {V} k {k}: {ph}")
                    gate.append((ph, lab, cx, V, k))
        print(f"[E40-phi-32k-{lab}] E40 beats the deferred kernel ({T6_DFR[32768]} ns) iff nb (V - k d)^+ + nb k phi + end read < deferred - floor (phi <= the cell, ns): " + "; ".join(rows))
    best = max(gate); worst = min(g for g in gate if g[4] <= 2)
    print(f"[E40-phi-gate] the most tolerant consistent cell ({best[1]}, end read {best[2] // 1000} us, V {best[3]}, k {best[4]}) needs phi <= {best[0]} ns per vector-carrying barrier; "
          f"the least tolerant k <= 2 cell ({worst[1]}, end read {worst[2] // 1000} us, V {worst[3]}, k {worst[4]}) {worst[0]} ns; the erratum-#29 band ({C5_X[0]}-{C5_X[1]} ns per crossing) "
          f"is {t10(x10r(C5_X[0], best[0]))}-{t10(x10r(C5_X[1], best[0]))}x above the most tolerant line -- if a barrier with vector work in flight costs what a barrier + scalar "
          f"read costs, E40 is dead; E40a decides it")
    # ---------------------------------------------------------------- E40: the phase-delta form (session 3) --------------------------
    ser_leg, ser_ung = sum(ENG5), ENG5[0] + ENG5[1] - tab + ENG5[2]; f1 = floorF1(32768)
    print(f"[E40-phases] parameterized form: gain <= (c + v + p) - (s + b) - (serial crossings) - tau; session 3: legacy {ser_leg} - {f1} - {tab} (per-block guard, serial) = "
          f"{ser_leg - f1 - tab} ns; unguarded {ser_ung} - {f1} = {ser_ung - f1} ns ({t10(pct(ser_ung - f1, ser_ung))}% of the serial sum); the deferred kernel's phases are UNMEASURED "
          f"(the next kernel session re-instantiates c, v, p, s, b)")
    print(f"[E40-legacy] on the legacy scan E40 cannot beat floor + nb x guard = {f1} + {tab} = {f1 + tab} ns at 32k ({t10(rateT(32768 * KV_TOK, f1 + tab))} GB/s) -- "
          f"{t10(pct(f1 + tab - T6_DFR[32768], T6_DFR[32768]))}% slower than the deferred kernel serial: E40 composes only with a zero-crossing guard")
    # ---------------------------------------------------------------- E40: buffers per mt (what the budgets force) ------------------
    for mt in (1, 2, 3, 4):
        us = sum(us4_rows(mt).values()); cs = BL_of(mt) * 16 * 4 * mt; co = co_sets(BL_of(mt)) * 16 * D * 4 * mt
        l0c1, l0c2 = l0c4(mt), l0c4(mt) + co; us2 = us + cs; s1 = 2 * pieces6(mt) * S1_SLOT6
        print(f"[E40-buf-mt{mt}] L0C single C_o {l0c1 // KiB} KiB / double {l0c2 // KiB} KiB ({'fits' if l0c2 <= L0C else 'OVER: single-buffered C_o -> merge before the next PV'}); "
              f"US {us // KiB} KiB + {us % KiB} B / + a second drained C_s {us2 // KiB} KiB + {us2 % KiB} B ({'fits' if us2 <= US_EVID else 'OVER: drain C_s after the last softmax slice'}); "
              f"S1 P slots for 2 blocks in flight at 32 KiB granularity {2 * pieces6(mt)} x 32 = {s1 // KiB} KiB ({'fits' if s1 <= S1_P else 'OVER'} the ~1 MB PRIOR); "
              f"vector-fit at the deferred fragment chain: mt x V <= ({BL_of(mt) // 64} - 1) x d needs V <= {(BL_of(mt) // 64 - 1) * d1 // mt} ns per fragment")
    print(f"[E40-trip] a trip re-runs the whole step (serial): at the 0.087-0.22 % trip rate <= 0.22 % of a step; measured amortized {T6_AMORT32[0]}-{T6_AMORT32[1]} vs trip-free "
          f"{T6_DFR[32768]} ns (+{T6_AMORT32[0] - T6_DFR[32768]}-{T6_AMORT32[1] - T6_DFR[32768]})")

if __name__ == "__main__":
    main6a()


# =====================================================================================================================================
# ROUND 6 (PROMPT-3R6, 2026-11-08) — the MEASURED deferred-guard cells folded in (kernel session 5; HW-MAP 3928d0e, the DEFERRED GUARD
# row). Silicon inputs (all MEASURED, production flags; no other silicon claim enters this section):
#   * trip-free full-pipeline cells (trips 0), t = 1: 945.5 / 3618.8 / 28694.0 us at 32k / 128k / 1M = 142.0 / 148.4 / 149.7 GB/s
#     (T6_DFR above, carried since PROMPT-6);
#   * amortized at the real trip-rate premise (0.087-0.22 % of steps): 946.3-947.4 us at 32k = G 141.7-141.8 (T6_AMORT32);
#   * reference points at 32k t = 1: legacy scan 1514.9 us (2 trips), guard-off 902.9, canonical adversarial 1818.1 (63 trips; it
#     retries ~100 % of steps — an upper bound, never the fleet cell); at 1M the adversarial canonical 56.0 ms vs the legacy 46.3 ms;
#   * the fold: "costs -59 us vs the scan (one pass)" (PROMPT-3R6, quoted), trips ~free; HW-MAP: "-558 us vs the legacy scan at real
#     rates, +42.6 us over unguarded (902.9)"; the session-4 "fold misread" = a test-harness artifact (the identity gate repacked the
#     shared arenas before the timing cell); the fold is exact at the +8 bound (planted 8.0 -> 0 trips, 8.02 -> exactly 1, cap not binding);
#   * numerics: the 1M canonical bad-2 (a weightless-outlier row's whole mass in f16 subnormals at the global-m retry, ~1e-2 granularity;
#     adversarial-only; the exact P path, 8.4M lanes, 100.00 %) and the random-profile out-verify floor (bad 324 at 32k / 65 at 1M,
#     deferred = legacy = guard-off; worst lanes near-zero wants) — a verification-methodology class, not a kernel defect.
# Readings this section derives (D): the trip model T(p) = T0 + p R (R = canonical - trip-free; it reproduces the quoted amortized band),
# the trip-rate breakeven against the legacy scan, the session-5 base shift, E39's resolution against the round-5 target, the per-block
# legacy-minus-deferred difference (round 5's off-32k scaling rule, tested), the x GEMV / per-layer fractions, the MoE-128k cell, the
# numerics constants. Every label above keeps printing its value; the [R6-*] labels below are the round-6 cells.
# =====================================================================================================================================
import math
P_TRIP6 = (87, 220)                          # the real trip-rate premise, per 100 000 steps (0.087-0.22 %) (M, HW-MAP)
TRIPS6 = (2, 63)                             # trips in the 32k legacy cell / in the 32k canonical cell (M)
CANON1M6, LEG1M6 = 56_000_000, 46_300_000    # 1M: adversarial canonical vs legacy, as quoted to 0.1 ms (M)
FOLD6_Q, WIN6_Q = 59_000, 558_000            # quoted: the fold vs the scan "one pass" (PROMPT-3R6); the real-rate win vs legacy (HW-MAP)
MU6, CAP6 = 8, 3072                          # the guard bound (P <= e^mu) and the fold's cap, f16-exact (M)
PLANT6 = (8.0, 8.02)                         # planted near-bound deltas (ln P): 0 trips / exactly 1 trip, cap not binding (M)
BAD6_RAND = (324, 65)                        # random-profile out-verify bad counts at 32k / 1M, identical for deferred / legacy / guard-off (M)
BAD6_CANON1M = 2                             # the 1M canonical bad-2 (M)
LANES6_1M = (1 << 20) * 8                    # the exact P path's lanes at 1M, t = 1 (rows 8): "8.4M lanes, 100.00 %" (M)
SIDE5 = NB32 * 1455                          # round 5's batched-guard side-product at the round-4 convention (93 120 ns at 32k)
T_LAYER_MOE_DIRECT = 2_641_199               # DESIGN-4's MoE layer on the direct-path expert kernel (fleet.lean tw3 moe .directSer; D4 input)

def amort6(T0, R, p): return T0 + p * R // 100_000                      # trip-free + p (per 1e5 steps) x the re-run cost R
def us1(ns): return f"{(ns + 50) // 1000}.{((ns + 50) // 100) % 10}"   # ns -> us, one decimal, round-half-up
def pctH6(n, d): return (2 * n * 10_000 + d) // (2 * d)                  # hundredths of a percent, round-half-up
def h2(x): return f"{x // 100}.{x % 100:02d}"
def spct(a, b): return ("+" if a >= b else "-") + t10(pct(abs(a - b), b)) + "%"
def p5(p): return f"{p // 1000}.{(p % 1000) // 10:02d}"                  # per-1e5 -> percent, two decimals (floored)

def main6():
    print("\n# ---- ROUND 6 (PROMPT-3R6, 2026-11-08; the MEASURED deferred-guard cells, kernel session 5): [R6-*] cells; every label above unchanged ----")
    g256 = G_SHUF[256 * KiB]
    D32, D128, D1M = T6_DFR[32768], T6_DFR[131072], T6_DFR[1 << 20]
    # ---------------------------------------------------------------- the measured cells, against the round-5 readings --------------
    for L in (32768, 131072, 1 << 20):
        i = LS5.index(L); T = T6_DFR[L]; nb = nb5(L)
        print(f"[R6-cells-{LK5[i]}] deferred guard, trip-free (M, session 5): {T} ns = {t10(rateT(L * KV_TOK, T))} GB/s; nb {nb}, {T // nb} ns per block; x GEMV {t10(pct(T, T_GEMV))}%; "
              f"round-5 readings: fused {fused5(L)} ({spct(T, fused5(L))}), unguarded {ung5(L)} ({'M' if L == 32768 else 'D'}; {spct(T, ung5(L))}), constant-rate 140.0 {rate5(L, 1400)} "
              f"({spct(T, rate5(L, 1400))}), guarded = the legacy scan (M, session 3) {T5[1][i]} ({spct(T, T5[1][i])})")
    # ---------------------------------------------------------------- the trip model and the amortized band ------------------------
    R = T6_CANON32 - D32; am = [amort6(D32, R, p) for p in P_TRIP6]
    print(f"[R6-amort] trip model T(p) = T0 + p R: R = canonical - trip-free = {T6_CANON32} - {D32} = {R} ns per tripped step (the canonical profile retries ~100 % of steps, "
          f"{TRIPS6[1]} trips; R = guard-off - {T6_OFF32 - R}: one whole-step re-run costs less than a guard-off step); at p = 0.087 / 0.22 % of steps: {am[0]} / {am[1]} ns "
          f"-> {us1(am[0])} / {us1(am[1])} us = the quoted band {us1(T6_AMORT32[0])}-{us1(T6_AMORT32[1])} (reproduced to the displayed 0.1 us: the band is an amortization of the two MEASURED cells, not a third measurement); G {t10(rateT(32768 * KV_TOK, T6_AMORT32[0]))} / "
          f"{t10(rateT(32768 * KV_TOK, T6_AMORT32[1]))} GB/s; the trips add +{T6_AMORT32[0] - D32}-{T6_AMORT32[1] - D32} ns = {h2(pctH6(T6_AMORT32[0] - D32, D32))}-{h2(pctH6(T6_AMORT32[1] - D32, D32))}% of the cell; each 1 % of tripped steps costs R / 100 = {R // 100} ns "
          f"({h2(pctH6(R // 100, D32))}% of the cell)")
    R1 = CANON1M6 - D1M; am1 = [amort6(D1M, R1, p) for p in P_TRIP6]
    print(f"[R6-amort-1M] at 1M with the measured adversarial cell ({CANON1M6} ns, quoted 56.0 ms): R = {R1} ns; IF the 32k trip-rate premise transfers (the rate per (model, L) is "
          f"UNMEASURED: E35's model half): {am1[0]}-{am1[1]} ns = {t10(rateT((1 << 20) * KV_TOK, am1[0]))}-{t10(rateT((1 << 20) * KV_TOK, am1[1]))} GB/s "
          f"(+{h2(pctH6(am1[0] - D1M, D1M))}-{h2(pctH6(am1[1] - D1M, D1M))}%): trips stay ~free at 1M")
    p32 = max(p for p in range(100_001) if 100_000 * D32 + p * R < 100_000 * T6_LEG32)
    p1m = max(p for p in range(100_001) if 100_000 * D1M + p * R1 < 100_000 * LEG1M6)
    print(f"[R6-trip-breakeven] the deferred guard beats the legacy scan iff its trip rate p (per 1e5 steps) <= {p32} at 32k ({p5(p32)} %: 100 000 x {D32} + p x {R} < 100 000 x {T6_LEG32}) "
          f"and <= {p1m} at 1M ({p5(p1m)} %, against the quoted 46.3 ms); the premise (<= 0.22 %) is {p32 // 220}x inside at 32k")
    print(f"[R6-adversarial] the canonical adversarial profile (an upper bound, never the fleet cell): 32k {T6_CANON32} ns = {t10(rateT(32768 * KV_TOK, T6_CANON32))} GB/s vs the legacy {T6_LEG32} "
          f"({spct(T6_CANON32, T6_LEG32)}, +{T6_CANON32 - T6_LEG32} ns); 1M {CANON1M6} = {t10(rateT((1 << 20) * KV_TOK, CANON1M6))} GB/s vs {LEG1M6} ({spct(CANON1M6, LEG1M6)}, +{CANON1M6 - LEG1M6} ns): "
          f"the gap grows with L ({us1(T6_CANON32 - T6_LEG32)} us -> {(CANON1M6 - LEG1M6) // 1_000_000}.{((CANON1M6 - LEG1M6) // 10_000) % 100:02d} ms; no lazy switch amortizes the re-run)")
    # ---------------------------------------------------------------- the session-5 base, the fold, E39, E35 ----------------------
    r4 = step4(32768, 1, g256, "lazy", "T")[0]
    print(f"[R6-base] the session-5 base at 32k t = 1 (guard-off {t10(rateT(32768 * KV_TOK, T6_OFF32))} GB/s, legacy {t10(rateT(32768 * KV_TOK, T6_LEG32))} GB/s): guard-off {T6_OFF32} vs session 3's unguarded {T5_UNG}: -{T5_UNG - T6_OFF32} ns ({spct(T6_OFF32, T5_UNG)}); legacy {T6_LEG32} vs "
          f"session 3's guarded {T5[1][1]}: +{T6_LEG32 - T5[1][1]} ({spct(T6_LEG32, T5[1][1])}) -- the A/B control reproduces session 3; against the round-4 legs-2 cell {r4}: guard-off "
          f"{spct(T6_OFF32, r4)} (session 3's unguarded: {spct(T5_UNG, r4)}), inside the {t10(MATCH5)} % line; the session-5 phases are not re-timed (the term split is UNMEASURED)")
    print(f"[R6-fold] at 32k: legacy - guard-off = {T6_LEG32 - T6_OFF32} ns (the scan on the session-5 base; session 3: {T5[1][1] - T5_UNG} on its own); deferred - guard-off = {FOLD6} ns "
          f"(fold + end-of-step read = {t10(pct(FOLD6, T6_OFF32))}% of guard-off; split UNMEASURED); the deferred guard removes {T6_LEG32 - D32} ns = {t10(pct(T6_LEG32 - D32, T6_LEG32 - T6_OFF32))}% "
          f"of the scan's cost trip-free ({T6_LEG32 - T6_AMORT32[1]}-{T6_LEG32 - T6_AMORT32[0]} amortized); quoted: HW-MAP's '-558 us at real rates' ({WIN6_Q}: {T6_LEG32 - T6_AMORT32[1] - WIN6_Q}-"
          f"{T6_LEG32 - T6_AMORT32[0] - WIN6_Q} ns below the cell differences) and PROMPT-3R6's 'the fold costs -59 us vs the scan (one pass)' ({FOLD6_Q}; the one-pass cell difference is {T6_LEG32 - D32}, "
          f"{t10(x10r(T6_LEG32 - D32, FOLD6_Q))}x it) -- neither reproduces from the quoted cells; both are carried as given and no cell uses them")
    f5 = fused5(32768)
    print(f"[R6-e39] E39 RESOLVED by measurement: the round-5 batched-guard target (unguarded {T5_UNG} + one 20 us crossing = {f5} ns = {t10(rateT(32768 * KV_TOK, f5))} GB/s) vs the shipped deferred "
          f"guard: {D32} trip-free ({spct(D32, f5)}), {T6_AMORT32[0]}-{T6_AMORT32[1]} amortized ({spct(T6_AMORT32[1], f5)} at worst); round 5's residual X (against {T5_UNG}) = {D32 - T5_UNG} trip-free, "
          f"{T6_AMORT32[0] - T5_UNG}-{T6_AMORT32[1] - T5_UNG} amortized (DESIGN-4's line: X <= 8 279); against its own base the residual is {FOLD6} ns = {t10(x10r(FOLD6, C5_X[1]))}x the 20 us band top, "
          f"between the crossing-only {C5_X[1]} and the crossing + side-product {C5_X[1] + SIDE5 // 3} at the measured softmax rate: the target is met because the base moved -{T5_UNG - T6_OFF32} ns "
          f"-- a net of two terms (residual +{FOLD6 - C5_X[1]} over the modelled crossing, base -{T5_UNG - T6_OFF32})")
    print(f"[R6-e35] E35's device half CLOSED: zero scalar ops per block on the common path (the vector fold); the deferred guard costs {FOLD6} ns per step over guard-off; a trip costs R = {R} ns "
          f"(one whole-step re-run), amortized +{T6_AMORT32[0] - D32}-{T6_AMORT32[1] - D32} ns at the premise (M; the model gives +{am[0] - D32}-{am[1] - D32}); the deferred guard beats the legacy scan at every trip rate <= {p5(p32)} % (32k) / {p5(p1m)} % (1M). "
          f"Open (model half): the trip rate per (model, L) at mu = 8, beta = 3, and at mu = 0 (KV-int8)")
    e8, e802 = math.exp(MU6), math.exp(PLANT6[1])
    print(f"[R6-fold-bound] the fold at the +8 bound: e^8 = {e8:.1f} < cap {CAP6} = 3 x 2^10 (f16-exact) -- an untripped lane (P <= e^8) never clamps; planted 8.02: e^8.02 = {e802:.1f} < {CAP6} "
          f"(the cap binds from ln {CAP6} = {math.log(CAP6):.4f}): the planted lane trips (8.02 > 8) with the cap not yet binding; planted 8.0 = the bound itself: 0 trips (the guard is inclusive); "
          f"integer check: 2.7183^8 = {27183 ** 8 // 10 ** 31 // 10}.{(27183 ** 8 // 10 ** 31) % 10} < 3072 and 2.7183^8 x 50/49 = {(27183 ** 8 * 50 * 100 // 49 // 10 ** 32 + 5) // 100}.{((27183 ** 8 * 50 * 100 // 49 // 10 ** 32 + 5) // 10) % 10} < 3072 "
          f"(given e < 2.7183 and e^0.02 <= 1/(1 - 0.02))")
    # ---------------------------------------------------------------- the per-block rule tested, the fractions, MoE 128k ----------
    pb = [(T5[1][LS5.index(L)] - T6_DFR[L]) // nb5(L) for L in (32768, 131072, 1 << 20)]
    s1, s2 = (D128 - D32) // 192, (D1M - D128) // 1792; ic = D32 - 64 * s1; ex = ic + 2048 * s1
    print(f"[R6-perblock] legacy (M, session 3) - deferred (M, session 5) per block: {pb[0]} / {pb[1]} / {pb[2]} ns at 32k / 128k / 1M (mixed sessions) vs round 5's per-block guard "
          f"{guard5(32768) // NB32} at every L; the deferred kernel's chord slopes {s1} (32k-128k) / {s2} (128k-1M) ns per block, intercept {ic} ns per step (the 1M cell sits {D1M - ex} ns = "
          f"{t10(pct(D1M - ex, ex))}% above the 32k-128k chord); the round-5 off-32k readings sit under the measured cells: fused {spct(D128, fused5(131072))} / {spct(D1M, fused5(1 << 20))}, unguarded "
          f"{spct(D128, ung5(131072))} / {spct(D1M, ung5(1 << 20))} at 128k / 1M -- the per-block rule over-charged the legacy guard off 32k (its 32k reading: {spct(D32, f5)})")
    print(f"[R6-gemv] x GEMV (398 us unit), MEASURED deferred: {t10(pct(D32, T_GEMV))} / {t10(pct(D128, T_GEMV))} / {t10(pct(D1M, T_GEMV))}% at 32k / 128k / 1M (guarded session 3: "
          f"{t10(pct(T5[1][1], T_GEMV))} / {t10(pct(T5[1][2], T_GEMV))} / {t10(pct(T5[1][3], T_GEMV))}%); per DESIGN-4 layer: MoE ({T_LAYER_MOE} ns) {t10(pct(D32, T_LAYER_MOE))} / "
          f"{t10(pct(D128, T_LAYER_MOE))} / {t10(pct(D1M, T_LAYER_MOE))}%, dense ({T_LAYER_DENSE} ns) {t10(pct(D32, T_LAYER_DENSE))} / {t10(pct(D128, T_LAYER_DENSE))}% (dense 1M runs KV-int8 only); "
          f"against the round-4 legs-2 cells {', '.join(str(step4(L, 1, g256, 'lazy', 'T')[0]) for L in (32768, 131072, 1 << 20))}: "
          f"{' / '.join(spct(T6_DFR[L], step4(L, 1, g256, 'lazy', 'T')[0]) for L in (32768, 131072, 1 << 20))}")
    kv128 = 131072 * KV_TOK
    print(f"[R6-fleet-moe-128k] DESIGN-4's MoE-128k layer on the measured deferred kernel: {D128} vs {T_LAYER_MOE} (anchored): +{D128 - T_LAYER_MOE} ns = {t10(pct(D128 - T_LAYER_MOE, T_LAYER_MOE))}%; "
          f"vs {T_LAYER_MOE_DIRECT} (direct path): +{D128 - T_LAYER_MOE_DIRECT} = {t10(pct(D128 - T_LAYER_MOE_DIRECT, T_LAYER_MOE_DIRECT))}%; G {t10(rateT(kv128, D128))} against the effective-rate lines "
          f"{t10(kv128 * 10 // T_LAYER_MOE)} (anchored) / {t10(kv128 * 10 // T_LAYER_MOE_DIRECT)} (direct): attention-bound on both; even the E40 floor F1 {floorF1(131072)} is "
          f"+{floorF1(131072) - T_LAYER_MOE} = {t10(pct(floorF1(131072) - T_LAYER_MOE, T_LAYER_MOE))}% over the anchored layer")
    # ---------------------------------------------------------------- the two numerics classes ------------------------------------
    print(f"[R6-numerics-subnormal] the 1M canonical bad-{BAD6_CANON1M} (MEASURED; adversarial profile only): f16 normals end at 2^-14 = 1/{2 ** 14} (ln {math.log(2.0 ** -14):.3f}); below it the "
          f"spacing is 2^-24 = 1/{2 ** 24}, so a value's relative granularity reaches 1 % at P <= 100 x 2^-24 = 1/{2 ** 24 // 100} (ln {math.log(100 / 2 ** 24):.2f}) -- a row whose whole surviving "
          f"mass sits there after the global-m retry's shift is quantised at ~1e-2; the exact P path at 1M = {LANES6_1M} lanes (1 048 576 x rows 8), 100.00 % exact; no fleet cell runs the "
          f"adversarial profile -- disposition: a documented class, no kernel change")
    print(f"[R6-numerics-verify] the random-profile out-verify floor (MEASURED): bad {BAD6_RAND[0]} at 32k / {BAD6_RAND[1]} at 1M, the SAME for deferred = legacy = guard-off -- the guard path "
          f"contributes none of them; the worst lanes have near-zero expected values: a verification-methodology class (a relative tolerance on near-zero wants), not a kernel defect -- "
          f"disposition: fix the checker's tolerance, not the kernel")
    # ---------------------------------------------------------------- E40 on the measured cells, the moved cells -------------------
    e40 = [(T6_DFR[L] - floorF1(L), T6_DFR[L] - floorF2(L, g256)) for L in (32768, 131072, 1 << 20)]
    print(f"[R6-e40] post-fusion the stage overlap (E40, section 5.1) is the attention-side #1 lever (DESIGN-4 round 6 ranks it): its bound on the measured cells is PROMPT-6's -- "
          f"32k {e40[0][0]} / {e40[0][1]}, 128k {e40[1][0]} / {e40[1][1]}, 1M {e40[2][0]} / {e40[2][1]} ns (F1 / F2, free end read, phi = 0); on the amortized 32k cell "
          f"+{T6_AMORT32[0] - D32}-{T6_AMORT32[1] - D32} ns more (the re-run is serial: E40 does not overlap it); gated on phi (E40a); "
          f"session 3's K+V stream phase ({STREAM5} ns) is {t10(pct(STREAM5, D32))}% of the deferred cell (round 5 unguarded: {t10(pct(STREAM5, T5_UNG))}%)")
    print(f"[R6-moved] round 5 -> round 6: fused 32k {f5} (D target, E39) -> {D32} trip-free / {T6_AMORT32[0]}-{T6_AMORT32[1]} amortized (M); 128k {fused5(131072)} (D) -> {D128} (M); "
          f"1M {fused5(1 << 20)} (D) -> {D1M} (M); E39 UNMEASURED -> RESOLVED (M); E35's device half RESOLVED -> CLOSED; the guarded column -> the legacy A/B control ({T6_LEG32} at session 5)")

if __name__ == "__main__":
    main6()
