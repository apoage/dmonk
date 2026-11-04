#!/usr/bin/env python3
"""proof/attn.py -- executable cost model for DESIGN-3.md (decode attention over the KV cache).

Integer arithmetic only, in the conventions of proof/model.py / moe.py / fleet.py:
  rates : tenths of GB/s (1 B/ns = 1 GB/s decimal; bytes*10 // ns = tenths)
  bytes : binary KiB/MiB ; time : ns floored ; usR = (ns+500)//1000 ; pct = tenths of a percent
  lane-ops : vector work units; R_VEC = 43.2 G lane-ops/s/core = 432 tenths -> ns = ops*10 // 432
Run: python3 -I proof/attn.py   (Python >= 3.8, no dependencies). Labels [A..] are cited in DESIGN-3.md.
"""
KiB, MiB = 1024, 1 << 20

# ------------------------------------------------------------ Measured (HW-MAP) -----------------------------
R_GEMM   = 1746     # full W8 decode kernel, DDR->L0B direct + one full barrier per tile, flat m=1..16 (M)
R_DDR    = 1738     # LPDDR r+w stream roof (M); pure-read ~1810 (M)
R_LOADER = 265      # S1->L0 loader, strict-serial, per core (M)
R_US_S1  = 2500     # US->S1 plain fill, per core, 48-64 KiB tiles (M)
R_FRAC   = 70       # COPY_FRAC software transform, per core (M)
C_MMA    = 15       # ns per (16,16,128) MMA call (M)
R_VEC    = 432      # tenths of G lane-ops/s/core, f16 count-mode (M)
T_LAUNCH = 91_000   # ns launch + queue floor (M)
L0A = L0B = 64 * KiB; L0C = 256 * KiB; US_EVID = 208 * KiB; S1_P = 1_000_000     # M / M / M / P
T_GEMV   = 398_000  # PROBLEM-3's "die-step class" unit: 67.11 MB / 168.5 GB/s (DESIGN.md route 1)

# ------------------------------------------------------------ Unmeasured, carried as explicit variables ------
G_BR   = {"stream": R_GEMM, "page64k": None, "gather3x": R_GEMM // 3}   # page64k computed from c_pg below
C_PG   = {"zero": 0, "half_us": 500, "two_us": 2_000}                   # per-page fixed cost, ns (U, E21)
CV_BR  = {"nat_nat": 7, "nat_tree": 12, "poly_nat": 28, "poly_tree": 33} # vector lane-ops per (score,row) (D, §3.3; E/R branches U, E22)
RHO32  = {"full": 1, "half": 2}                                          # f32 lane-rate penalty vs the f16 40/cycle (U, E22)
R_DRAIN_A = 100     # tenths: 10 GB/s/core L0C->US staged read, ASSUMED for the exposed-drain rows (U, DESIGN-2 E12)
SIGMA_S = 2         # ns per scalar iteration, ASSUMED (U, E22)
MERGE_OPS = 7000    # vector lane-ops per block per A fragment for the online-softmax merge (D, §3.4)

# ------------------------------------------------------------ Shape (headline) and design constants ----------
D, HKV, G_Q = 128, 8, 8          # head dim, KV heads (= cores), query heads per KV head
HQ = HKV * G_Q                   # 64 query heads
KV_TOK = 2 * HKV * D * 2         # 4096 B per token per layer (f16, K and V)
CORE_TOK = 2 * D * 2             # 512 B per token per core
BL = 512                         # tokens per block at mt <= 2 (online-softmax granule); 256 at mt = 3, 4 (L0C budget, section 4)
def BL_of(mt): return 512 if mt <= 2 else (256 if mt <= 4 else 128)   # mt 5..8 only in the S4 variant: 2 C_s regions of 128 KiB
PAGE = 64 * KiB                  # page bytes (design variable); tokens per page = PAGE // (2*D)
ROWS_PASS_MAX = 64               # rows per pass (L0A budget, §4)

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
def vec_block_ns(cV, rho, mt): return (BL_of(mt) * 16 * mt * cV + MERGE_OPS * mt) * rho * 10 // R_VEC
def mma_block_ns(mt):      return mt * (BL_of(mt) // 16 + (D // 16) * (BL_of(mt) // 128)) * C_MMA
def loader_block_ns(mt):   return tn((BL_of(mt) // 128) * 4096 * mt, R_LOADER)
def drain_block_bytes(mt): return (BL_of(mt) * 16 * 4 + 16 * D * 4) * mt
def drain_block_ns(mt, Rd): return tn(drain_block_bytes(mt), Rd)
def scalar_block_ns(mt):   return 256 * mt * SIGMA_S                     # 16x16 tree tail per fragment

def tail_ops(L, mt): return (L % 16) * D * 16 * mt * 4                  # vector tail: scores + PV, Mul+Add each
def step_parts(L, t, G, cV, rho, Rd=R_DRAIN_A, i8=False, onepass=False):
    rows = rows_of(t)
    p, mt = (1, mt_of(rows)) if onepass else (passes_of(rows), mt_pass(rows))   # onepass: mt<=8, L0A exactly full (S4 variant)
    nb = nblocks(L, mt)
    ddr = p * nb * ddr_block_ns(G, mt) // (2 if i8 else 1)
    vec = p * nb * vec_block_ns(cV, rho, mt)
    mma = p * nb * mma_block_ns(mt)
    ldr = p * nb * loader_block_ns(mt)
    drn = p * nb * drain_block_ns(mt, Rd)
    fixed = 2 * vec_block_ns(cV, rho, mt) + drain_block_ns(mt, Rd) + tail_ops(L, mt_of(rows)) * rho * 10 // R_VEC
    return dict(ddr=ddr, vec=vec, mma=mma, loader=ldr, drain=drn, fixed=fixed, passes=p, mt=mt, nb=nb)
def cands(s, drain):          # drain = "hidden" (separate engine, R_drain >= threshold) | "separate" | "same" (vector engine)
    c = {"KV stream": s["ddr"], "vector": s["vec"] + (s["drain"] if drain == "same" else 0), "MMA": s["mma"], "loader": s["loader"]}
    if drain == "separate": c["drain"] = s["drain"]
    return c
def step_ns(L, t, G, cV, rho, Rd=R_DRAIN_A, drain="hidden", i8=False, onepass=False):
    s = step_parts(L, t, G, cV, rho, Rd, i8, onepass)
    c = cands(s, drain)
    return max(c.values()) + s["fixed"], s, max(c, key=c.get)

LS = {"4k": 4096, "32k": 32768, "128k": 131072, "1M": 1 << 20}

if __name__ == "__main__":
    print("# proof/attn.py -- derived cells of DESIGN-3.md\n")
    print(f"[A0-shape] d={D} H_kv={HKV} g={G_Q} H_q={HQ}; kv_tok={KV_TOK} B/token/layer; per core {CORE_TOK} B/token; "
          f"block {BL} tokens = {BL*CORE_TOK//KiB} KiB per core = {BL*KV_TOK//KiB} KiB per die; page {PAGE//KiB} KiB = {PAGE//(2*D)} tokens")
    for k, L in LS.items():
        print(f"[A0-kv-{k}] L={L}: KV bytes/layer {L*KV_TOK} = {L*KV_TOK/1e9:.3f} GB; matrix-path tokens {L_matrix(L)}, blocks {nblocks(L)}, "
              f"page table {ceil(L, PAGE//(2*D))*2*HKV*8} B")
    # A1: gather model
    for P in (4*KiB, 16*KiB, 64*KiB, 256*KiB, MiB):
        print(f"[A1-G-{P//KiB}k] G(P) tenths: " + ", ".join(f"c_pg={c}: {G_page(P, cpg)}" for c, cpg in C_PG.items()))
    G_BR["page64k"] = G_page(PAGE, C_PG["half_us"])
    print(f"[A1-branches] G branches (tenths): {G_BR}")
    # A2: per-block engine budgets at t=1 (mt=1)
    blk = ddr_block_ns(R_GEMM)
    print(f"[A2-block] block DDR time at 174.6: {blk} ns; per-core share {t10(R_GEMM*10//8//10)} GB/s; "
          f"MMA {mma_block_ns(1)} ns ({t10(pct(mma_block_ns(1), blk))}%); loader {loader_block_ns(1)} ns ({t10(pct(loader_block_ns(1), blk))}%); "
          f"drain bytes {drain_block_bytes(1)} B -> hidden iff R_drain >= {rateT(drain_block_bytes(1), blk)} tenths GB/s/core; "
          f"at 10 GB/s exposed {drain_block_ns(1, R_DRAIN_A)} ns ({t10(pct(drain_block_ns(1, R_DRAIN_A), blk))}%); scalar tail {scalar_block_ns(1)} ns")
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
            print(f"[A3-rows*-{cvk}-{rk}] smallest rows (multiple of 16) with vector >= KV stream per block: {r} (t >= {ceil(r, G_Q)} at g={G_Q})")
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
    # A4b: thresholds and variants
    for rk, rho in RHO32.items():
        cv = (blk * R_VEC // 10 // rho - MERGE_OPS) // (BL * 16)
        print(f"[A4b-cV-threshold-{rk}] t=1 vector hidden under the block DDR time iff c_V <= {cv} lane-ops per (score,row)")
    Gmax = BL * KV_TOK * 10 // vec_block_ns(CV_BR["poly_tree"], 2, 1)
    print(f"[A4b-G-threshold] t=1 is DDR-bound on the worst vector corner for every G <= {Gmax} tenths (block vector {vec_block_ns(30,2,1)} ns)")
    print(f"[A4b-drain-threshold] drain hidden iff R_drain >= {rateT(drain_block_bytes(1), blk)} tenths/core at mt=1; {rateT(drain_block_bytes(4), blk)} at mt=4; same-engine cost at 10 GB/s = {t10(pct(drain_block_ns(1, R_DRAIN_A), blk))}% of the block")
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
    # A4c: L_eq (attention = one GEMV unit) and the regime map at 32k
    L = 512
    while step_ns(L, 1, R_GEMM, CV_BR["nat_nat"], 1)[0] < T_GEMV: L += 512
    print(f"[A4c-Leq] smallest L (multiple of 512) with the t=1 native-corner step >= {T_GEMV} ns: {L} (step {step_ns(L,1,R_GEMM,7,1)[0]} ns; at L-512: {step_ns(L-512,1,R_GEMM,7,1)[0]})")
    for t in (1, 2, 4, 8, 16):
        for cvk, cV in CV_BR.items():
            for rk, rho in RHO32.items():
                T, s, b = step_ns(32768, t, R_GEMM, cV, rho)
                print(f"[A4c-regime-t{t}-{cvk}-{rk}] rows={rows_of(t)} passes={s['passes']} mt={s['mt']} T={usR(T)} us bind={b} vec/ddr={t10(pct(s['vec'], s['ddr']))}%")
    # A5: online vs two-pass
    extraK = tn(BL * D * 2 * 8, R_GEMM)
    print(f"\n[A5-online] two-pass re-streams K: +{extraK} ns per block of {BL} tokens vs merge {MERGE_OPS*2*10//R_VEC} ns (rho=2): online wins {extraK // (MERGE_OPS*2*10//R_VEC)}x")
    # A6: KV-write path per step per layer per core
    print(f"[A6-kvwrite] K append 8 x 32 B copies; V tail block COPY_FRAC {16*D*2} B at 7 GB/s = {tn(16*D*2, R_FRAC)} ns per 16 tokens; "
          f"tail vector worst {tail_ops(15, 1)} lane-ops = {tail_ops(15,1)*2*10//R_VEC} ns (rho=2)")
    # A7: SRAM budgets (L-independent)
    us = 32*KiB + 3*32*KiB + 2*16*KiB + 8*KiB + 2*8*KiB + 4*KiB + 4*KiB + 8*KiB     # drain, 3 snapshots, P x2, O, partials x2, sums, shift reel, tails
    print(f"[A7-sram] US {us//KiB} KiB <= {US_EVID//KiB} evidenced (mt=1; snapshots 96 KiB vanish on the Z branch); "
          f"L0B 64 KiB (2 x 32 KiB tiles); L0A {16 + 2*16} KiB at mt=4 ({8+2*4} at mt=1); S1 {2*16 + 4} KiB")
    for mt in (1, 2, 3, 4):
        cs = BL_of(mt) * 16 * 4 * mt; co = 16 * D * 4 * mt
        us4 = BL_of(mt)*16*4*mt + (2 if mt < 4 else 1)*BL_of(mt)*16*2*mt + co + (2 if mt < 4 else 1)*co + 20*KiB
        print(f"[A7-l0c-mt{mt}] block {BL_of(mt)} tokens: C_s region {cs//KiB} KiB x3 + C_o {co//KiB} KiB x2 = {(3*cs+2*co)//KiB} KiB of L0C; US working set {us4//KiB} KiB (+ snapshots {3*cs//KiB} KiB in US at mt=1, in S1 above)")
    print(f"[A7-poly] exp poly: clamp 6 + scale 1 + Horner(4) 8 + 7 squarings = 22 lane-ops; Taylor bound 2^7*(22/128)^5/120 = 1.6e-4 relative")
