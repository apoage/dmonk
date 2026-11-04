#!/usr/bin/env python3
"""proof/attn.py -- executable cost model for DESIGN-3.md (decode attention over the KV cache).

Integer arithmetic only, in the conventions of proof/model.py / moe.py / fleet.py:
  rates : tenths of GB/s (1 B/ns = 1 GB/s decimal; bytes*10 // ns = tenths)
  bytes : binary KiB/MiB ; time : ns floored ; usR = (ns+500)//1000 ; pct = tenths of a percent
  lane-ops : vector work units; R_VEC = 43.2 G lane-ops/s/core = 432 tenths -> ns = ops*10 // 432
Run: python3 -I proof/attn.py   (Python >= 3.8, no dependencies). Labels [A..] are cited in DESIGN-3.md and
PROOF-COVERAGE-3.md; every label is transcribed 1:1 into proof/attn.lean (round 2).
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

if __name__ == "__main__":
    print("# proof/attn.py -- derived cells of DESIGN-3.md (round 2)\n")
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
