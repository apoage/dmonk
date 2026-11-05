#!/usr/bin/env python3
"""proof/attn.py -- executable cost model for DESIGN-3.md (decode attention over the KV cache).

Integer arithmetic only, in the conventions of proof/model.py / moe.py / fleet.py:
  rates : tenths of GB/s (1 B/ns = 1 GB/s decimal; bytes*10 // ns = tenths)
  bytes : binary KiB/MiB ; time : ns floored ; usR = (ns+500)//1000 ; pct = tenths of a percent
  lane-ops : vector work units; R_VEC = 43.2 G lane-ops/s/core = 432 tenths -> ns = ops*10 // 432
Run: python3 -I proof/attn.py   (Python >= 3.8, no dependencies). Labels [A..] are cited in DESIGN-3.md and
PROOF-COVERAGE-3.md; every label is transcribed 1:1 into proof/attn.lean (round 2).
Round 3 (2026-11-05): the season (v1) measurements (HW-MAP commit 8a7079f) are added as the [R3-*] section at the end; every
round-2 label keeps printing its round-2 value so that `diff` lists exactly what moved (see [R3-moved-*]).
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
# HW-MAP commit 8a7079f resolved every U quantity: E21 (gather rate per page size), E22 (exp, reduce-max, And, rho32,
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
MERGE_PACK = 25750      # lane-eq per block-fragment: the validation pack's merge-chain itemisation (commit 8a7079f); round 2 assumed 7 000
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
    print("\n# ---- ROUND 3 (season v1 measured, HW-MAP commit 8a7079f): [R3-*] re-derive the headline cells; [A*] above are the round-2 cells ----")
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
