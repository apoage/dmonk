#!/usr/bin/env python3
"""proof/alt.py -- executable arithmetic for ALTERNATIVES.md (the pattern-matching round).

Integer arithmetic only, in the conventions of proof/model.py / moe.py / attn.py / fleet.py:
  rates : tenths of GB/s (1 B/ns = 1 GB/s decimal; bytes*10 // ns = tenths)
  bytes : binary KiB/MiB ; time : ns floored ; usR = (ns+500)//1000 ; pct = tenths of a percent
Run:  python3 -I proof/alt.py   (Python >= 3.8, no dependencies; imports proof/fleet.py and proof/attn.py
for the DESIGN-4 / DESIGN-3 cost models so that every "today" cell is the ledgered number, and every
alternative is the same model with one term changed).  Labels [ALT-x-...] are cited in ALTERNATIVES.md;
the rational (Zipf traffic-share) rows are printed to 0.1 % and marked EMPIRICAL-class in the ledger.
"""
import os, sys
from fractions import Fraction
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F
import attn as A

KiB, MiB, GiB, GB = 1024, 1 << 20, 1 << 30, 10 ** 9
ceil, tn, usR, pct, t10, rateT = F.ceil, F.tn, F.usR, F.pct, F.t10, A.rateT
def t3(x):  return F.t3(x)
def ms2(ns): return F.ms2(ns)
def pcs(n, d):                       # signed percent change in tenths, n vs d
    return (n - d) * 1000 // d if n >= d else -((d - n) * 1000 // d)
def spc(x):                          # "+12.3%" / "-4.5%"
    return ("+" if x >= 0 else "-") + t10(abs(x)) + "%"

# ------------------------------------------------------------ Measured (HW-MAP) used beyond fleet/attn -------
R_CORE_GEMM = 1746               # per-die kernel rate (M); per-core share = 1746/8 -> ns = bytes*80//1746
R_LOADER    = 265                # S1->L0 loader, strict-serial, per core (M)
C_RES_T     = 254                # tenths of ns per call, the DESIGN-2 subtraction residual (D)
C_MMA       = 15                 # ns per (16,16,128) call (M)
R_W4V_CORE  = 53                 # vector i4->f16 unpack, 5-pass: 5.3 GB/s/core of int4 bytes (M, HW-MAP)
R_W4V_DIE   = 8 * R_W4V_CORE     # 42.4 aggregate int4-effective (HW-MAP quotes ~42)
R_US_S1     = 2500               # US->S1 plain fill per core (M)
R_VEC       = 432                # 43.2 G lane-ops/s/core (M)
T_LAUNCH    = F.T_LAUNCH         # 91 us (M)
LAM         = F.LAMBDA["mid"]    # 91 us primary host-bounce latency (A, H3)
DIE_MEM, O_RT, WS = F.DIE_MEM, F.O_RT, F.WS

# ============================================================ ALT-1: MoE expert kernel on the direct path =====
def alt1():
    out = {}
    b_core = 2 * MiB                                   # per-core expert slice at the DESIGN-2 headline (N_c = 512)
    t_b = b_core * 80 // R_CORE_GEMM                   # DDR->L0B direct, 21.825 GB/s/core share: 96 089 ns
    a_lift = tn(64 * KiB, R_LOADER) + 32 * C_RES_T // 10   # 64 KiB of A per expert per core through S1->L0A + 32 calls' residual
    ser = t_b + a_lift                                 # A lift serialised with the direct-load barrier cadence
    ovl = t_b                                          # A lift overlapped (different engine, between barriers)
    mma = 1024 * C_MMA
    F_MOE = F.F_MOE
    step_ser = 8 * ser + F_MOE; step_ovl = 8 * ovl + F_MOE
    bytes_step = 8 * 16 * MiB
    out.update(t_b=t_b, a_lift=a_lift, ser=ser, ovl=ovl, mma=mma, step_ser=step_ser, step_ovl=step_ovl,
               rate_ser=rateT(bytes_step, step_ser), rate_ovl=rateT(bytes_step, step_ovl),
               rate_anchor=rateT(bytes_step, 8 * F.T_SLAB_SER + F_MOE), g2=t_b + a_lift // 2,
               drain_thresh=rateT(32 * KiB, t_b))      # R_drain (tenths GB/s/core) that hides a 32 KiB drain under one expert
    return out

def fleet_cell(s, L, B=1, t=1, tslab=None, nlaunch=None, **kw):
    """fleet.step with an optional expert-chain time (per expert-slab per core) and launches-per-layer override."""
    s2 = dict(s)
    if nlaunch is not None: s2["nlaunch"] = nlaunch
    saved = F.T_SLAB_PP
    if tslab is not None:
        F.T_SLAB_PP = tslab; kw = dict(kw); kw["regime"] = "pp"
    try:
        T, parts = F.step(s2, L, B, t, **kw)
    finally:
        F.T_SLAB_PP = saved
    return T, parts

# ============================================================ ALT-2: replication with a minimal W4 tier ========
# Instance = 4 dies (2 cards), chain d1-first/d0-last inside each card: positions (c0.d1, c0.d0, c1.d1, c1.d0).
POS4 = [(0, 1), (0, 0), (1, 1), (1, 0)]
LAYERS4 = {"dense": [30, 30, 30, 30], "moe": [7, 7, 7, 7]}
T_SLAB_W4_OVL = tn(MiB, R_W4V_CORE)                            # 1 MiB of int4 per core per expert slab at 5.3 GB/s: 197 849 ns
T_PIECE_W4_SER = (tn(2 * KiB, R_W4V_CORE) + tn(4 * KiB, R_US_S1) + tn(4 * KiB, R_LOADER) + C_RES_T // 10 + C_MMA)
T_SLAB_W4_SER = 512 * T_PIECE_W4_SER                            # unpack -> US->S1 -> loader -> MMA strictly serial per 2 KiB i4
R_W4_W8EQ_OVL = 2 * R_W4V_DIE                                   # 84.8 W8-equivalent GB/s per die
def w4_dense_rate(branch):          # W8-equivalent die rate of the W4 vector path (tenths)
    return R_W4_W8EQ_OVL if branch == "ovl" else rateT(2 * 2 * KiB, T_PIECE_W4_SER) * 8

def inst_die_weights(s, pos, x, draft=True):
    """resident bytes on die pos of a 4-die instance when a fraction x (thousandths) of the candidate bytes is int4."""
    n = LAYERS4[s["name"]][pos]
    if s["moe"]: w = n * (s["w_attn"] + s["w_experts"] - s["w_experts"] * x // 2000)
    else:        w = n * (s["w_layer"] - s["w_layer"] * x // 2000)
    if pos == 0: w += s["w_embed"]
    if pos == 3: w += s["w_head"]
    if draft and (not s["moe"]) and pos == 1: w += F.DRAFT["w"] + F.DRAFT["kv_window"]
    return w
def inst_die_kv(s, pos, L, B=1, i8=False):
    b = LAYERS4[s["name"]][pos] * s["kv_tok"] * L * B
    return b // 2 if i8 else b
def min_x(s, pos, L, B=1, i8=False):
    """smallest x (thousandths, 0..1000) with weights(x) + KV + ws + rt <= 86 GB on die pos; None if even x=1000 fails."""
    room = DIE_MEM - O_RT - WS - inst_die_kv(s, pos, L, B, i8)
    lo, hi = 0, 1000
    if inst_die_weights(s, pos, 1000) > room: return None
    if inst_die_weights(s, pos, 0) <= room: return 0
    while lo < hi:                           # weights(x) is non-increasing in x
        mid = (lo + hi) // 2
        if inst_die_weights(s, pos, mid) <= room: hi = mid
        else: lo = mid + 1
    return lo
def harmonic(n, sexp=Fraction(1)):          # sum_{r=1..n} r^-s for s = 1 (exact rational); s=1.5 handled separately
    return sum(Fraction(1, r) for r in range(1, n + 1))
def cold_traffic_share(x, E=256):
    """traffic share of the coldest x (thousandths) of E experts under Zipf(1.0) popularity (rank weights 1/r): rational."""
    nc = E * x // 1000
    if nc == 0: return Fraction(0)
    return (harmonic(E) - harmonic(E - nc)) / harmonic(E)
def inst_exchange(s, rows, lam):
    act = rows * s["d"] * 2; logits = rows * s["vocab"] * 4; ids = rows * 4
    bw = 0
    for p in range(3): bw += tn(act, F.D2H[POS4[p][1]]) + tn(act, F.H2D[POS4[p + 1][1]])
    bw += tn(logits, F.D2H[POS4[3][1]]) + tn(ids, F.H2D[POS4[0][1]])
    return bw + 8 * lam, bw
def inst_step(s, L, B=1, t=1, xs=None, hot="direct_ser", cold="ovl", pop="uniform", i8=False, nlaunch=None, fam="uniform"):
    """step time of one 4-die instance. xs = per-die int4 share (thousandths). hot = int8 expert regime
    ('anchor' = DESIGN-2 serial 122 979, 'direct_ser' = ALT-1 serialised A lift, 'direct_ovl'); cold = W4 vector branch;
    pop = expert-popularity family deciding which fraction of the *streamed* bytes is W4 ('uniform': x; 'zipf10': coldest-x share)."""
    rows = B * t
    a1 = alt1(); T_hot = {"anchor": F.T_SLAB_SER, "direct_ser": a1["ser"], "direct_ovl": a1["ovl"]}[hot]
    T_cold = T_SLAB_W4_OVL if cold == "ovl" else T_SLAB_W4_SER
    G, cE, lam = F.G_BR["stream"], F.C_EXP["native"], LAM
    nl = s["nlaunch"] if nlaunch is None else nlaunch
    kv, sm, mma = F.attn_parts(s, L, B, t, G, cE, i8)
    attn_l = max(kv, sm, mma)
    T = 0; W = 0
    for pos in range(4):
        n = LAYERS4[s["name"]][pos]; x = xs[pos]
        if s["moe"]:
            D = F.D_of(fam, rows)
            share = Fraction(x, 1000) if pop == "uniform" else cold_traffic_share(x)
            per_exp = T_hot * (1 - share) + T_cold * share        # exact rational, floored at the end
            w_l = tn(s["w_attn"], F.R_GEMM) + 2 * F.F_MOE + int(s["slabs"] * D * per_exp)
        else:
            w_l = int(Fraction(s["w_layer"] * 10 * (1000 - x), 1000 * F.R_GEMM) + Fraction(s["w_layer"] * 10 * x, 1000 * w4_dense_rate(cold)))
        W += n * w_l
        T += n * (w_l + attn_l + nl * T_LAUNCH)
    head = tn(s["w_head"], F.R_GEMM); T += head + 2 * T_LAUNCH; W += head
    xch, xbw = inst_exchange(s, rows, lam); T += xch
    draft = F.draft_ns(lam, True) if t > 1 else 0; T += draft
    return T, dict(W=W, KV=s["nL"] * kv, LAUNCH=(s["nL"] * nl + 2) * T_LAUNCH, XCH=xch, DRAFT=draft)
def tps_card_inst(tok_milli, T, inst=2): return tok_milli * inst * 10 ** 9 // (4 * T)

# ============================================================ ALT-3: per-layer persistent megakernel ==========
SYNCS_PER_LAYER = {"dense": 4, "moe": 5}    # dense: 2 K-split reductions x (partial exchange + broadcast); MoE: + router logits exchange
def reduction_bytes(rows, d):               # one cross-core reduction through DDR: 8 partials written+read, x slices written, x read by 8
    return 8 * rows * d * 4 + 8 * rows * d * 4 + rows * d * 2 + 8 * rows * d * 2
def alt3(s, L, csync, rows=1):
    """megakernel: 1 launch per layer; adds per layer SYNCS x csync + 2 reductions' DDR traffic."""
    nl = s["nlaunch"]; name = s["name"]
    saved_per_layer = (nl - 1) * T_LAUNCH
    red = 2 * tn(reduction_bytes(rows, s["d"]), F.R_GEMM)
    added_per_layer = SYNCS_PER_LAYER[name] * csync + red
    T0, p0 = F.step(s, L, 1, 1)
    T1 = T0 - s["nL"] * saved_per_layer + s["nL"] * added_per_layer
    thresh = saved_per_layer // SYNCS_PER_LAYER[name]            # c_sync at which the megakernel stops paying (red ignored: separate row)
    thresh_exact = (saved_per_layer - red) // SYNCS_PER_LAYER[name]
    return dict(T0=T0, T1=T1, saved=s["nL"] * saved_per_layer, red=s["nL"] * red, thresh=thresh, thresh_exact=thresh_exact,
                syncs=s["nL"] * SYNCS_PER_LAYER[name])
def draft_token_ns(nlaunch):
    return tn(F.DRAFT["w"], F.R_GEMM) + tn(F.DRAFT["kv_window"], F.R_GEMM) + nlaunch * T_LAUNCH + tn(128256 * 4, F.D2H[0]) + 2 * LAM

# ============================================================ ALT-4: the quantizing epilogue =================
QUANT_OPS = 8                                # per element: tree max 6 + Muls scale 1 + Adds bias 1 (extraction is a copy)
def alt4(s):
    if s["moe"]:
        elems = 3 * s["d"] + 8 * s["d"]       # QKV, O, gate/up inputs (d each) + 8 experts' down inputs (N_e = 4096 each)
    else:
        elems = 3 * s["d"] + 53248            # QKV, O, gate/up (d) + down (ffn)
    ops = elems * QUANT_OPS
    per_layer_ns = ops * 10 // R_VEC          # redundant on every core (each core needs the whole A)
    bounces_per_layer = 4
    host_fallback = bounces_per_layer * (2 * LAM + tn(s["d"] * 2, F.D2H[0]) + tn(s["d"], F.H2D[1]))
    return dict(elems=elems, ops=ops, per_layer_ns=per_layer_ns, host_per_layer=host_fallback)
def magic_bias_check():
    """f16 magic bias: y = q + 1280 for q in [-127,127] lies in [1024, 2048) where the f16 ulp is 1, and the low byte of the
    f16 word (mantissa bits 0..7) equals (q + 256) mod 256 = q as two's complement. Checked exhaustively."""
    ok = True
    for q in range(-127, 128):
        y = q + 1280
        if not (1024 <= y < 2048): ok = False
        mant = y - 1024                       # 10-bit mantissa of a value in [1024, 2048)
        if mant & 0xFF != (q & 0xFF): ok = False
    return ok

# ============================================================ ALT-5: two-tier KV pages ========================
def G_tier(L, c_pg, P_e=MiB, P_t=64 * KiB):
    """aggregate KV rate (tenths) when tokens in whole 4096-token extents are read as 1 MiB pages and the remainder as 64 KiB pages."""
    tok_e = (L // (P_e // 256)) * (P_e // 256)         # 256 B per token per core -> P_e//256 tokens per extent
    tok_t = L - tok_e
    n_e = tok_e // (P_e // 256); n_t = ceil(tok_t, P_t // 256)
    t_core = n_e * (P_e * 80 // R_CORE_GEMM + c_pg) + n_t * (P_t * 80 // R_CORE_GEMM + c_pg)
    return 8 * L * 256 * 10 // t_core if t_core else R_CORE_GEMM
def compaction_ns_per_token_layer():
    # per (layer, head, K|V) stream: every 4096 tokens read 16 x 64 KiB + write 1 MiB = 2 MiB; 16 streams per layer
    return tn(16 * 2 * MiB, F.R_GEMM) // 4096

# ============================================================ ALT-6: K-int8 / V-f16 KV ========================
def attn_k8(L, t, G, cV, rho):
    s = A.step_parts(L, t, G, cV + 1, rho)             # +1 lane-op per score for the per-token K scale reel
    ddr = s["ddr"] * 3 // 4
    c = {"KV stream": ddr, "vector": s["vec"], "MMA": s["mma"], "loader": s["loader"]}
    return max(c.values()) + s["fixed"], c, max(c, key=c.get)
def fleet_k8(s, L, B=1, t=1):
    """fleet.step with KV bytes x 3/4 (K int8, V f16)."""
    saved = F.attn_parts
    def ap(s_, L_, B_, t_, G_, cE_, i8_=False):
        kv, sm, mma = saved(s_, L_, B_, t_, G_, cE_, False)
        return kv * 3 // 4, sm, mma
    F.attn_parts = ap
    try: return F.step(s, L, B, t)
    finally: F.attn_parts = saved
def cV_threshold_k8(rho):
    # DDR-bound iff (8192*(cV+1) + 7000)*rho*10/432 <= 3/4 * 12011
    blk = A.ddr_block_ns(A.R_GEMM) * 3 // 4
    best = None
    for cV in range(0, 200):
        if (8192 * (cV + 1) + 7000) * rho * 10 // 432 <= blk: best = cV
    return best, blk

# ============================================================ ALT-7: shared-prefix batched attention ==========
def prefix_kv_ns(s, L, Ls, B, passes_rows=64):
    g = s["Hq"] // s["Hkv"]; rows = B * g
    passes = ceil(rows, passes_rows)
    full = tn(s["kv_tok"] * L * B, F.R_GEMM)
    shared = tn(s["kv_tok"] * ((L - Ls) * B + Ls * passes), F.R_GEMM)
    return full, shared, passes

# ============================================================ ALT-8: lazy-rescale online softmax ==============
def alt8(L, cV, rho):
    two, s2, b2 = A.step_ns(L, 16, A.R_GEMM, cV, rho)                       # two passes, mt=4 (DESIGN-3 baseline)
    s4, s4s, b4 = A.step_ns(L, 16, A.R_GEMM, cV, rho, onepass=True)        # S4 with the merge
    lz, lzs, bz = A.step_ns(L, 16, A.R_GEMM, cV, rho, onepass=True, merge=0)   # S4 + lazy rescale (no merge, O resident in L0C)
    return two, s4, lz, b2, b4, bz, lzs
def lazy_block_bound():
    # S4 block (128 tokens, mt=8) DDR-bound iff 2048*cV*8*rho*10/432 <= 3002
    blk = A.ddr_block_ns(A.R_GEMM, 8)
    res = {}
    for rho in (1, 2):
        best = None
        for cV in range(0, 100):
            if 2048 * cV * 8 * rho * 10 // 432 <= blk: best = cV
        res[rho] = best
    return blk, res

# ============================================================ ALT-9: dominated alternatives, with arithmetic ===
def dom_ksplit_dense():
    """dense m=1, K=N=8192: K-split saves A bytes, adds f32 partial traffic + one cross-core sync."""
    a_now = 8 * 128 * KiB; a_ks = 8 * 16 * KiB
    saved = tn(a_now - a_ks, F.R_GEMM)
    partials = 8 * 32 * KiB                       # 8 cores x [1 x 8192] f32
    added = tn(2 * partials, F.R_GEMM)            # written once, read once
    return saved, added, saved - added
def dom_expert_parallel_card(s):
    T0, _ = F.step(s, 32768); extra = s["nL"] * 2 * LAM
    return T0, T0 + extra
def dom_hot_cold_same_fleet(s, x=250):
    """MoE on the 8-die fleet with the coldest x experts as W4 (no replication): expert time per layer under uniform / Zipf(1.0)."""
    a1 = alt1(); res = {}
    for pop in ("uniform", "zipf10"):
        share = Fraction(x, 1000) if pop == "uniform" else cold_traffic_share(x)
        per_exp = F.T_SLAB_SER * (1 - share) + T_SLAB_W4_OVL * share
        T0, p0 = F.step(s, 32768)
        delta = s["nL"] * int(s["slabs"] * 8 * (per_exp - F.T_SLAB_SER))
        res[pop] = (T0, T0 + delta)
    return res
def dom_rows_cliff(s, L=4096):
    """what a flat m-curve to 64 would buy at 4k: B=64 rows vs B=16 (same model, rows cap lifted)."""
    saved = F.ROWS_FLAT; F.ROWS_FLAT = 64
    try:
        T16, _ = F.step(s, L, 16, 1); T64, _ = F.step(s, L, 64, 1)
    finally: F.ROWS_FLAT = saved
    feas = F.feasible(s, L, 64)
    return T16, T64, feas
def dom_token_drop(Dcap=64):
    T0 = F.F_MOE + 128 * F.T_SLAB_SER; T1 = F.F_MOE + Dcap * F.T_SLAB_SER
    return T0, T1

# ============================================================ main ============================================
def main():
    print("# proof/alt.py -- derived cells of ALTERNATIVES.md\n")
    D, M = F.DENSE, F.MOE
    print("## [ALT-0] constants beyond fleet/attn")
    print(f"[ALT-0-w4v] W4 vector path: {t10(R_W4V_CORE)} GB/s/core of int4 = {t10(R_W4V_DIE)} per die = {t10(R_W4_W8EQ_OVL)} W8-equivalent GB/s "
          f"(overlapped-unpack branch); serial-chain branch per 2 KiB i4: unpack {tn(2*KiB, R_W4V_CORE)} + US->S1 {tn(4*KiB, R_US_S1)} + loader {tn(4*KiB, R_LOADER)} "
          f"+ residual {C_RES_T//10} + MMA {C_MMA} = {T_PIECE_W4_SER} ns -> {t10(w4_dense_rate('ser'))} W8-equivalent per die; "
          f"per-expert-slab per core: {T_SLAB_W4_OVL} ns (ovl) / {T_SLAB_W4_SER} ns (ser) vs int8 anchor {F.T_SLAB_SER}")
    # ---------------------------------------------------------------- ALT-1
    a = alt1()
    print("\n## [ALT-1] MoE expert kernel on the DDR->L0B direct path (headline K=N_e=4096, k=8, t=1, W8)")
    print(f"[ALT-1-chain] per expert per core: B 2 MiB direct {a['t_b']} ns; A lift 64 KiB via S1->L0A {a['a_lift']} ns (2473 + 32 x 25.4); "
          f"serialised {a['ser']} / overlapped {a['ovl']} ns; MMA {a['mma']} ns ({t10(pct(a['mma'], a['t_b']))}% of the DDR time); G=2 knob {a['g2']}")
    print(f"[ALT-1-rate] step 8 x chain + F: serialised {a['step_ser']} ns -> {t10(a['rate_ser'])} GB/s; overlapped {a['step_ovl']} ns -> {t10(a['rate_ovl'])}; "
          f"DESIGN-2 anchor {t10(a['rate_anchor'])}; gain {spc(pcs(a['rate_ser'], a['rate_anchor']))} / {spc(pcs(a['rate_ovl'], a['rate_anchor']))}; "
          f"drain 32 KiB hidden iff R_drain >= {t10(a['drain_thresh'])} GB/s/core")
    for L in (32768, 131072, 1048576):
        T0, _ = F.step(M, L); Ts, _ = fleet_cell(M, L, tslab=a['ser']); To, _ = fleet_cell(M, L, tslab=a['ovl'])
        print(f"[ALT-1-fleet-{L}] MoE t=1: today {ms2(T0)} ms -> {t3(F.tps_card(1000, T0))} ; direct serialised {ms2(Ts)} -> {t3(F.tps_card(1000, Ts))} "
              f"({spc(pcs(F.tps_card(1000, Ts), F.tps_card(1000, T0)))}) ; overlapped {ms2(To)} -> {t3(F.tps_card(1000, To))} ({spc(pcs(F.tps_card(1000, To), F.tps_card(1000, T0)))})")
    T0, _ = F.step(M, 32768, 16, 1); Ts, _ = fleet_cell(M, 32768, 16, 1, tslab=a['ser'])
    print(f"[ALT-1-fleet-B16] MoE B=16 32k: today {ms2(T0)} -> {t3(F.tps_card(16000, T0))} ; direct serialised {ms2(Ts)} -> {t3(F.tps_card(16000, Ts))}")
    # ---------------------------------------------------------------- ALT-2
    print("\n## [ALT-2] replication: two 4-die instances, minimal W4 (vector-unpack) tier for the fit")
    for s in (D, M):
        for L in (32768, 131072, 1048576):
            for i8 in ((False,) if s["moe"] else (False, True)):
                xs = [min_x(s, p, L, 1, i8) for p in range(4)]
                tag = f"{s['name']}-{L}" + ("-kvi8" if i8 else "")
                if any(x is None for x in xs):
                    print(f"[ALT-2-fit-{tag}] infeasible even at x=1000 on dies {[p for p, x in enumerate(xs) if x is None]}"); continue
                T0, _ = F.step(s, L, i8=i8) if (s["moe"] or L < 1048576 or i8) else (None, None)
                for hot, cold, pop in (("direct_ser", "ovl", "uniform"), ("direct_ser", "ser", "uniform"), ("direct_ser", "ovl", "zipf10"), ("anchor", "ovl", "uniform")):
                    if not s["moe"] and (pop != "uniform" or hot != "direct_ser"): continue
                    T, parts = inst_step(s, L, xs=xs, hot=hot, cold=cold, pop=pop, i8=i8)
                    base = f"today {ms2(T0)} ms -> {t3(F.tps_card(1000, T0))}" if T0 else "today: MEM"
                    gain = f" ({spc(pcs(tps_card_inst(1000, T), F.tps_card(1000, T0)))})" if T0 else ""
                    print(f"[ALT-2-{tag}-{hot}-{cold}-{pop}] x per die {xs} (thousandths of candidate bytes as int4); {base} ; "
                          f"2 instances: step {ms2(T)} ms (W {ms2(parts['W'])}, KV {ms2(parts['KV'])}, launch {ms2(parts['LAUNCH'])}, xch {usR(parts['XCH'])} us) "
                          f"-> {t3(tps_card_inst(1000, T))} tok/s/card{gain}")
    # dense with spec decode under replication
    xs = [min_x(D, p, 32768) for p in range(4)]
    T, parts = inst_step(D, 32768, 1, 4, xs=xs); T0, _ = F.step(D, 32768, 1, 4)
    tau = F.tau_milli(700)
    print(f"[ALT-2-dense-32k-spec] spec k=3 a=0.7: today {ms2(T0)} -> {t3(F.tps_card(tau, T0))} ; 2 instances {ms2(T)} -> {t3(tps_card_inst(tau, T))} "
          f"({spc(pcs(tps_card_inst(tau, T), F.tps_card(tau, T0)))})")
    xs = [min_x(M, p, 32768, 16) for p in range(4)]
    if all(x is not None for x in xs):
        T, parts = inst_step(M, 32768, 16, 1, xs=xs); T0, _ = F.step(M, 32768, 16, 1)
        print(f"[ALT-2-moe-32k-B16] B=16: x {xs}; today {ms2(T0)} -> {t3(F.tps_card(16000, T0))} ; 2 instances {ms2(T)} -> {t3(tps_card_inst(16000, T))} "
              f"({spc(pcs(tps_card_inst(16000, T), F.tps_card(16000, T0)))})")
    else: print(f"[ALT-2-moe-32k-B16] infeasible: x {xs}")
    print(f"[ALT-2-zipf-share] coldest x of 256 experts carry (Zipf 1.0 popularity) x=10%: {float(cold_traffic_share(100))*100:.1f}% , 25%: {float(cold_traffic_share(250))*100:.1f}% , "
          f"50%: {float(cold_traffic_share(500))*100:.1f}% , 75%: {float(cold_traffic_share(750))*100:.1f}% of the expert traffic (EMPIRICAL-class, H9)")
    print(f"[ALT-2-mindies] int8 residency: DESIGN-4 T_min_dies = 5; with x=1000 (all-W4 candidates) the per-die weights at 4 dies are "
          f"dense {F.gb1(inst_die_weights(D, 0, 1000))} / {F.gb1(inst_die_weights(D, 3, 1000))} GB, MoE {F.gb1(inst_die_weights(M, 0, 1000))} / {F.gb1(inst_die_weights(M, 3, 1000))} GB (pos 0 / pos 3)")
    # ---------------------------------------------------------------- ALT-3
    print("\n## [ALT-3] per-layer persistent megakernel with DDR-flag cross-core sync")
    for s in (D, M):
        for csync in (0, 2000, 5000, 20000):
            r = alt3(s, 32768, csync)
            print(f"[ALT-3-{s['name']}-csync{csync}] launches/layer {s['nlaunch']} -> 1 saves {ms2(r['saved'])} ms/token; reductions add {ms2(r['red'])} ms; "
                  f"{r['syncs']} syncs x {csync} ns; step {ms2(r['T0'])} -> {ms2(r['T1'])} ms ; {t3(F.tps_card(1000, r['T0']))} -> {t3(F.tps_card(1000, r['T1']))} tok/s/card "
                  f"({spc(pcs(F.tps_card(1000, r['T1']), F.tps_card(1000, r['T0'])))})")
        r = alt3(s, 32768, 0)
        print(f"[ALT-3-{s['name']}-threshold] megakernel pays iff c_sync <= {r['thresh']} ns per sync (launch savings only); {r['thresh_exact']} ns net of the reduction traffic")
    for nl in (121, 24, 1):
        print(f"[ALT-3-draft-{nl}] draft token with {nl} launches: {usR(draft_token_ns(nl))} us; verify step (k=3) {ms2(3*draft_token_ns(nl))} ms")
    a = alt1(); T0, _ = F.step(M, 32768); Tc = alt3(M, 32768, 5000)["T1"] - (F.step(M, 32768)[0] - fleet_cell(M, 32768, tslab=a['ser'])[0])
    print(f"[ALT-3+1-moe] ALT-1 (serialised) + ALT-3 (c_sync 5 us): MoE 32k {ms2(T0)} -> {ms2(Tc)} ms ; {t3(F.tps_card(1000, T0))} -> {t3(F.tps_card(1000, Tc))} ({spc(pcs(F.tps_card(1000, Tc), F.tps_card(1000, T0)))})")
    # ---------------------------------------------------------------- ALT-4
    print("\n## [ALT-4] quantizing epilogue (f16 -> i8 per-token A without a cast)")
    print(f"[ALT-4-magic] f16 magic bias 1280: low byte of the f16 word = two's-complement q for every q in [-127,127]: {magic_bias_check()}")
    for s in (D, M):
        q = alt4(s); T0, _ = F.step(s, 32768); Th = T0 + s["nL"] * q["host_per_layer"]
        print(f"[ALT-4-{s['name']}] {q['elems']} elements/layer x {QUANT_OPS} ops = {q['ops']} lane-ops = {usR(q['per_layer_ns'])} us per layer per core (redundant on 8 cores) = "
              f"{t10(pct(q['per_layer_ns'] * s['nL'], T0))}% of the 32k step; host-quantization fallback 4 bounces/layer = {usR(q['host_per_layer'])} us/layer -> step {ms2(T0)} -> {ms2(Th)} ms "
              f"({spc(pcs(F.tps_card(1000, Th), F.tps_card(1000, T0)))} tok/s)")
    print(f"[ALT-4-draft] draft with host quantization: +{4*24} bounces x {usR(2*LAM + tn(2*8192, F.D2H[0]))} us = +{ms2(4*24*(2*LAM + tn(2*8192, F.D2H[0])))} ms per draft token (of {usR(draft_token_ns(121))} us)")
    r1b = rateT(64 * MiB, tn(64 * MiB + 2 * MiB, R_LOADER // 2 * 8))   # Route 1b class: f16 tiles through the serial loader, 8 cores
    print(f"[ALT-4-route1b] no quantizer and no host bounce -> f16 A x f16 (vector-cast) W through the 26.5 GB/s/core loader: {t10(rateT(8*64*MiB, tn(64*MiB, R_LOADER)*2))} GB/s-class vs 174.6")
    # ---------------------------------------------------------------- ALT-5
    print("\n## [ALT-5] two-tier KV pages: 1 MiB extents + 64 KiB tail pages")
    for cpg in (0, 100, 500, 2000, 6005):
        g64 = A.G_page(64 * KiB, cpg); g1m = A.G_page(MiB, cpg)
        cells = []
        for L in (32768, 32768 + 2000, 1048576):
            cells.append(f"L={L}: {t10(G_tier(L, cpg))}")
        print(f"[ALT-5-G-cpg{cpg}] G(64 KiB) {t10(g64)} ; G(1 MiB) {t10(g1m)} ; two-tier " + " ; ".join(cells) + " (tenths GB/s)")
    for cpg in (500, 2000):
        g64 = A.G_page(64 * KiB, cpg); g1m = A.G_page(MiB, cpg)
        for L in (32768, 1048576):
            T64, _, _ = A.step_ns(L, 1, g64, 7, 1); T1m, _, _ = A.step_ns(L, 1, G_tier(L, cpg), 7, 1)
            print(f"[ALT-5-step-cpg{cpg}-{L}] t=1 native corner: 64 KiB pages {usR(T64)} us -> two-tier {usR(T1m)} us ({spc(pcs(T1m, T64))})")
    print(f"[ALT-5-compaction] compaction traffic {compaction_ns_per_token_layer()} ns per token-layer (16 streams x 2 MiB per 4096 tokens at 174.6); "
          f"tail waste <= 16 x 64 KiB = 1 MiB per layer-sequence (vs 16 MiB with fixed 1 MiB pages); page-table entries per 1M tokens per stream: {1048576//4096} extents + <= 15 tail pages")
    # ---------------------------------------------------------------- ALT-6
    print("\n## [ALT-6] K-int8 / V-f16 KV (bytes x 3/4, P stays f16)")
    for rho in (1, 2):
        best, blk = cV_threshold_k8(rho)
        print(f"[ALT-6-threshold-rho{rho}] t=1 block DDR-bound iff c_V <= {best} (block {blk} ns at 3/4 bytes)")
    for L in (32768, 1048576):
        for cvk, rk in (("nat_nat", "full"), ("poly_tree", "half")):
            T, c, b = attn_k8(L, 1, A.R_GEMM, A.CV_BR[cvk], A.RHO32[rk]); T0, _, _ = A.step_ns(L, 1, A.R_GEMM, A.CV_BR[cvk], A.RHO32[rk])
            print(f"[ALT-6-attn-{L}-{cvk}-{rk}] t=1 {usR(T0)} us -> {usR(T)} us bind={b} ({spc(pcs(T, T0))})")
    for s in (D, M):
        for L in (32768, 131072, 1048576):
            if not s["moe"] and L == 1048576: continue
            T0, _ = F.step(s, L); T, _ = fleet_k8(s, L); Ti, _ = F.step(s, L, i8=True)
            print(f"[ALT-6-fleet-{s['name']}-{L}] t=1: f16 KV {ms2(T0)} -> {t3(F.tps_card(1000, T0))} ; K-int8 {ms2(T)} -> {t3(F.tps_card(1000, T))} ({spc(pcs(F.tps_card(1000, T), F.tps_card(1000, T0)))}) ; "
                  f"full KV-int8 {ms2(Ti)} -> {t3(F.tps_card(1000, Ti))} ({spc(pcs(F.tps_card(1000, Ti), F.tps_card(1000, T0)))})")
    # ---------------------------------------------------------------- ALT-7
    print("\n## [ALT-7] shared-prefix batched attention (prefix KV streamed once per pass)")
    for s in (D, M):
        for Ls in (4096, 16384, 28672):
            full, shared, passes = prefix_kv_ns(s, 32768, Ls, 16)
            T0, p0 = F.step(s, 32768, 16, 1); T = T0 - s["nL"] * (full - shared)
            print(f"[ALT-7-{s['name']}-B16-Ls{Ls}] rows {16*(s['Hq']//s['Hkv'])} -> {passes} passes; KV per layer {usR(full)} -> {usR(shared)} us; step {ms2(T0)} -> {ms2(T)} ms ; "
                  f"{t3(F.tps_card(16000, T0))} -> {t3(F.tps_card(16000, T))} ({spc(pcs(F.tps_card(16000, T), F.tps_card(16000, T0)))})")
    # ---------------------------------------------------------------- ALT-8
    print("\n## [ALT-8] lazy-rescale online softmax (O resident in L0C, no per-block merge) at t=16, g=8")
    blk, res = lazy_block_bound()
    print(f"[ALT-8-threshold] S4 128-token block {blk} ns DDR-bound without merge iff c_V <= {res[1]} (rho32=1) / {res[2]} (rho32=2)")
    for L in (32768, 1048576):
        for cvk, rk in (("nat_nat", "full"), ("nat_tree", "full"), ("poly_tree", "half")):
            two, s4, lz, b2, b4, bz, lzs = alt8(L, A.CV_BR[cvk], A.RHO32[rk])
            print(f"[ALT-8-{L}-{cvk}-{rk}] two-pass {usR(two)} us ({b2}) ; S4+merge {usR(s4)} ({b4}) ; S4+lazy {usR(lz)} ({bz}) ; lazy vs two-pass {spc(pcs(lz, two))}, vs S4 {spc(pcs(lz, s4))}")
    # ---------------------------------------------------------------- ALT-9
    print("\n## [ALT-9] dominated alternatives")
    sv, ad, net = dom_ksplit_dense()
    print(f"[ALT-9-ksplit] dense m=1 8192^2 K-split: A bytes saved {usR(sv)} us, partial traffic added {usR(ad)} us, net {usR(net)} us = {t10(pct(net, 384000))}% of a 384 us kernel before the sync (>= 91 us launch, or c_sync)")
    T0, T1 = dom_expert_parallel_card(M)
    print(f"[ALT-9-expert-parallel] experts split over the card's two dies at Pi=1: no concurrency; +2 lambda per layer: {ms2(T0)} -> {ms2(T1)} ms ({spc(pcs(F.tps_card(1000,T1), F.tps_card(1000,T0)))})")
    for pop, (T0, T1) in dom_hot_cold_same_fleet(M).items():
        print(f"[ALT-9-hotcold-{pop}] coldest 25% of experts as W4 on the same 8-die fleet (no replication): MoE 32k {ms2(T0)} -> {ms2(T1)} ms ({spc(pcs(F.tps_card(1000,T1), F.tps_card(1000,T0)))})")
    for s in (D, M):
        T16, T64, feas = dom_rows_cliff(s)
        print(f"[ALT-9-rowscliff-{s['name']}] 4k: B=16 {ms2(T16)} ms -> {t3(F.tps_card(16000, T16))} ; B=64 (if m=64 were flat) {ms2(T64)} -> {t3(F.tps_card(64000, T64))} "
              f"(x{(F.tps_card(64000, T64)*10//F.tps_card(16000, T16))/10:.1f}), memory feasible {feas}; at 32k L_max(64) = {F.Lmax(s, 64)}")
    T0, T1 = dom_token_drop()
    print(f"[ALT-9-tokendrop] t=16 uniform D=128 -> cap 64: step {ms2(T0)} -> {ms2(T1)} ms per MoE launch (x{T0*10//T1/10:.1f}), dropping 50% of routed pairs (quality knob)")
    print(f"[ALT-9-specialization] a DMA core feeding compute cores must hand bytes over through DDR (no inter-core SRAM path): W read + W write + W read = 3x bytes -> <= {t10(F.R_GEMM//3)} GB/s")
    print(f"[ALT-9-p2p] zero-copy / NUMA / polling: bounded by T_p2p_bound <= T_x = {usR(F.exchange(M,1,LAM)[0])} us MoE / {usR(F.exchange(D,1,LAM)[0])} us dense per token")


# ============================================================ extras: combinations and feasibility tables =====
def extras():
    D, M = F.DENSE, F.MOE
    print("\n## [ALT-X] combinations and per-die fit tables")
    a = alt1()
    for cpg in (6005,):
        g64 = A.G_page(64 * KiB, cpg)
        for L in (32768, 1048576):
            T64, _, _ = A.step_ns(L, 1, g64, 7, 1); T1m, _, _ = A.step_ns(L, 1, G_tier(L, cpg), 7, 1)
            print(f"[ALT-5-step-cpg{cpg}-{L}] t=1 native corner: 64 KiB pages {usR(T64)} us -> two-tier {usR(T1m)} us ({spc(pcs(T1m, T64))})")
    # head-aligned QKV packing: attention fused into the QKV launch (no cross-core sync): 1 launch per layer saved
    for s in (D, M):
        T0, _ = F.step(s, 32768); T1, _ = fleet_cell(s, 32768, nlaunch=s["nlaunch"] - 1)
        print(f"[ALT-3-headaligned-{s['name']}] QKV+attention in one launch (head-aligned column slices, no sync): {ms2(T0)} -> {ms2(T1)} ms ({spc(pcs(F.tps_card(1000, T1), F.tps_card(1000, T0)))})")
    # replication + megakernel (+ direct-path hot tier), MoE and dense at 32k
    for s in (D, M):
        xs = [min_x(s, p, 32768) for p in range(4)]
        T0, _ = F.step(s, 32768)
        T, parts = inst_step(s, 32768, xs=xs, nlaunch=1)
        Tsync = T + s["nL"] * SYNCS_PER_LAYER[s["name"]] * 5000 + s["nL"] * 2 * tn(reduction_bytes(1, s["d"]), F.R_GEMM)
        print(f"[ALT-2+3-{s['name']}-32k] replication + megakernel (c_sync 5 us): today {ms2(T0)} -> {t3(F.tps_card(1000, T0))} ; 2 instances {ms2(Tsync)} -> {t3(tps_card_inst(1000, Tsync))} "
              f"({spc(pcs(tps_card_inst(1000, Tsync), F.tps_card(1000, T0)))})")
    # replication + full KV-int8 for MoE long context
    for L in (131072, 1048576):
        xs = [min_x(M, p, L, 1, True) for p in range(4)]
        T0, _ = F.step(M, L, i8=True); T, parts = inst_step(M, L, xs=xs, i8=True)
        print(f"[ALT-2+6-moe-{L}] replication + full KV-int8: x {xs}; single instance KV-int8 {ms2(T0)} -> {t3(F.tps_card(1000, T0))} ; 2 instances {ms2(T)} -> {t3(tps_card_inst(1000, T))} "
              f"({spc(pcs(tps_card_inst(1000, T), F.tps_card(1000, T0)))}); vs f16-KV single {t3(F.tps_card(1000, F.step(M, L)[0]))}")
    # all-W4 replication (x = 1000) vs minimal x, MoE 32k
    T0, _ = F.step(M, 32768); Tall, _ = inst_step(M, 32768, xs=[1000] * 4); Tmin, _ = inst_step(M, 32768, xs=[min_x(M, p, 32768) for p in range(4)])
    print(f"[ALT-2-allw4-moe-32k] all experts W4 (x=1000): 2 instances {ms2(Tall)} ms -> {t3(tps_card_inst(1000, Tall))} ; minimal x: {ms2(Tmin)} -> {t3(tps_card_inst(1000, Tmin))} ; today {t3(F.tps_card(1000, T0))}")
    # per-die fit tables at the chosen x
    for s, L in ((M, 32768), (M, 1048576), (D, 32768), (D, 131072)):
        xs = [min_x(s, p, L) for p in range(4)]
        rows = []
        for p in range(4):
            w = inst_die_weights(s, p, xs[p]); kv = inst_die_kv(s, p, L); tot = w + kv + WS + O_RT
            rows.append(f"pos{p} c{POS4[p][0]}.d{POS4[p][1]}: x={xs[p]} w={F.gb1(w)} kv={F.gb1(kv)} total={F.gb1(tot)} GB")
        print(f"[ALT-2-fit-table-{s['name']}-{L}] " + " | ".join(rows) + f" (limit 86.0; overhead {F.gb1(O_RT + WS)} assumed, H8)")
    # ALT-2 sensitivity: the W4 vector rate bracket (5.3 measured; what if the full kernel realises only 4.0 or 3.0 GB/s/core)
    global T_SLAB_W4_OVL
    saved = T_SLAB_W4_OVL
    for r in (53, 40, 30):
        T_SLAB_W4_OVL = tn(MiB, r)
        xs = [min_x(M, p, 32768) for p in range(4)]; T, _ = inst_step(M, 32768, xs=xs)
        print(f"[ALT-2-sens-w4rate-{r}] W4 unpack at {t10(r)} GB/s/core: MoE 32k 2 instances {ms2(T)} ms -> {t3(tps_card_inst(1000, T))} tok/s/card (today 1.867)")
    T_SLAB_W4_OVL = saved
    # ALT-2 break-even: the W4 slab time at which two instances stop beating one (MoE 32k, uniform, direct_ser hot)
    T0, _ = F.step(M, 32768); xs = [min_x(M, p, 32768) for p in range(4)]
    lo, hi = 0, 50_000_000
    while lo < hi:
        mid = (lo + hi + 1) // 2
        T_SLAB_W4_OVL = mid; T, _ = inst_step(M, 32768, xs=xs)
        if tps_card_inst(1000, T) > F.tps_card(1000, T0): lo = mid
        else: hi = mid - 1
    T_SLAB_W4_OVL = saved
    print(f"[ALT-2-breakeven-moe-32k] two instances beat one for every W4 slab time <= {lo} ns per core-slab (= {t10(rateT(MiB, lo))} GB/s/core of int4; measured 5.3; serial-chain branch {t10(rateT(MiB, T_SLAB_W4_SER))})")


# ============================================================ PROOF ROUND (2026-11-05): [ALT-P-*] re-derived cells ======
# Prover-forced corrections and the re-derivations the proof round applied before proving (PROMPT-5P): the on-device
# f16->i8 activation pass is MEASURED (HW-MAP 0915e22: 43.7 us per pass, rint-half-even saturating +-127), so every claim
# that assumed the magic-bias quantizer or the host-bounce fallback is re-derived; the serial-chain W4 piece carried 4 KiB
# of f16 per 2 KiB of int4 (it is 8 KiB: two MMA calls); the two-tier dominance is restated with its floor thresholds.
# Every label above keeps printing its ALTERNATIVES (dd5f84c) value; the [ALT-P-*] labels are the moved / new cells.
C_Q      = 43_700            # on-device A-quantization pass, ns per pass at m=1, K=8192 (M, HW-MAP 0915e22)
Q_PASSES = 4                 # quantized GEMM inputs per layer: QKV, O, gate/up, down (D, as DESIGN-4 round 3)
LAM_MEAS = 12_200            # measured host-bounce latency per direction, ns (M, HW-MAP e9349c8)
T_PIECE_W4_SER_C = tn(2 * KiB, R_W4V_CORE) + tn(8 * KiB, R_US_S1) + tn(8 * KiB, R_LOADER) + 2 * (C_RES_T // 10) + 2 * C_MMA
T_SLAB_W4_SER_C  = 512 * T_PIECE_W4_SER_C      # corrected serial-chain core-slab time (f16 legs 8 KiB, 2 MMA calls per 2 KiB i4)
def quant_per_token(s): return s["nL"] * Q_PASSES * C_Q
def inst_step_q(s, L, B=1, t=1, **kw):
    """inst_step + the measured A-quant pass on every layer (and on the draft's 24 layers when t > 1)."""
    T, parts = inst_step(s, L, B, t, **kw)
    q = quant_per_token(s) + (3 * 24 * Q_PASSES * C_Q if t > 1 else 0)
    parts = dict(parts); parts["QUANT"] = q
    return T + q, parts
def step_q(s, L, B=1, t=1, **kw):
    T, parts = F.step(s, L, B, t, **kw)
    q = quant_per_token(s) + (3 * 24 * Q_PASSES * C_Q if t > 1 else 0)
    parts = dict(parts); parts["QUANT"] = q
    return T + q, parts
def tier_times(L, c, P_e=MiB, P_t=64 * KiB):
    """(two-tier core time, 64 KiB-page core time) for L tokens at per-page cost c: the time form of G_tier / G_page."""
    tok_e = (L // 4096) * 4096; n_e = tok_e // 4096; n_t = ceil(L - tok_e, 256)
    t_tier = n_e * (P_e * 80 // R_CORE_GEMM + c) + n_t * (P_t * 80 // R_CORE_GEMM + c)
    t_64 = ceil(L, 256) * (P_t * 80 // R_CORE_GEMM + c)
    return t_tier, t_64

def proofround():
    global T_SLAB_W4_SER, T_PIECE_W4_SER, T_SLAB_W4_OVL, O_RT
    D, M = F.DENSE, F.MOE
    a = alt1()
    print("\n## [ALT-P] proof-round re-derivations (PROMPT-5P; HW-MAP 0915e22 / fa2c24a inputs)")
    # --- P1: the serial-chain W4 piece carries 8 KiB of f16 per 2 KiB of int4 (two (16,16,128) calls), not 4 KiB
    print(f"[ALT-P-w4ser] serial-chain piece per 2 KiB i4 (4 096 values -> 8 KiB f16): unpack {tn(2*KiB, R_W4V_CORE)} + US->S1 {tn(8*KiB, R_US_S1)} + loader {tn(8*KiB, R_LOADER)} "
          f"+ 2 x residual {2*(C_RES_T//10)} + 2 x MMA {2*C_MMA} = {T_PIECE_W4_SER_C} ns (as written: {T_PIECE_W4_SER}, 4 KiB legs and one call); "
          f"core-slab {T_SLAB_W4_SER_C} ns (was {T_SLAB_W4_SER}); {t10(rateT(2*2*KiB, T_PIECE_W4_SER_C)*8)} W8-equivalent GB/s per die (was {t10(w4_dense_rate('ser'))}); "
          f"{t10(rateT(MiB, T_SLAB_W4_SER_C))} GB/s/core of int4 (was {t10(rateT(MiB, T_SLAB_W4_SER))}); break-even 1 371 124 ns is {t10(1371124*10//T_SLAB_W4_SER_C)}x above it (was {t10(1371124*10//T_SLAB_W4_SER)}x)")
    savedS, savedP = T_SLAB_W4_SER, T_PIECE_W4_SER
    T_SLAB_W4_SER, T_PIECE_W4_SER = T_SLAB_W4_SER_C, T_PIECE_W4_SER_C
    try:
        for s in (D, M):
            for L in (32768, 131072, 1048576):
                for i8 in ((False,) if s["moe"] else (False, True)):
                    xs = [min_x(s, p, L, 1, i8) for p in range(4)]
                    if any(x is None for x in xs): continue
                    T0, _ = F.step(s, L, i8=i8); T, parts = inst_step(s, L, xs=xs, cold="ser", i8=i8)
                    tag = f"{s['name']}-{L}" + ("-kvi8" if i8 else "")
                    print(f"[ALT-P-ser-{tag}] corrected ser branch: 2 instances {ms2(T)} ms (W {ms2(parts['W'])}) -> {t3(tps_card_inst(1000, T))} tok/s/card "
                          f"({spc(pcs(tps_card_inst(1000, T), F.tps_card(1000, T0)))} vs today {t3(F.tps_card(1000, T0))})")
    finally:
        T_SLAB_W4_SER, T_PIECE_W4_SER = savedS, savedP
    # --- P2: the drain iff in tenths
    print(f"[ALT-P-drain] 32 KiB drain under one expert's DDR time ({a['t_b']} ns): hidden iff R_drain >= 0.4 GB/s/core in tenths "
          f"(0.3: {tn(32*KiB, 3)} ns > {a['t_b']}; 0.4: {tn(32*KiB, 4)} ns <= {a['t_b']}); exact threshold {32*KiB*10/a['t_b']:.3f} GB/s; the measured 152.8 is {1528//4}x above")
    # --- P3: the G = 2 knob as a rate
    r2 = rateT(8 * 16 * MiB, 8 * a['g2'] + F.F_MOE)
    print(f"[ALT-P-g2] G = 2 (one A lift per expert pair): step {8*a['g2']+F.F_MOE} ns -> {t10(r2)} GB/s = {spc(pcs(r2, a['rate_ser']))} over the serialised 167.1 "
          f"(time ratio {a['ser']*1000//a['g2']/10:.1f} % as a real)")
    # --- P4: two-tier pages: floors and the measured c_pg
    te, t64 = MiB * 80 // R_CORE_GEMM, 64 * KiB * 80 // R_CORE_GEMM
    first = next(c for c in range(0, 100) if G_tier(32768, c) > A.G_page(64 * KiB, c))
    print(f"[ALT-P-tier-floor] extent time {te} ns vs 16 x 64 KiB pages {16*t64} ns: the extent floors {te-16*t64} ns per MiB SLOWER at c_pg = 0 "
          f"(exact arithmetic: both {MiB*80/R_CORE_GEMM:.1f}); per extent the tier saves 15 c_pg - {te-16*t64} ns -> faster iff c_pg >= 1 ns; "
          f"in tenths G_tier(32k) > G(64 KiB) from c_pg = {first} ns (equal at 0..{first-1})")
    for c in (38, 114):
        g64, gt, g1 = A.G_page(64 * KiB, c), G_tier(32768, c), A.G_page(MiB, c)
        cells = []
        for L in (32768, 1048576):
            T64, _, _ = A.step_ns(L, 1, g64, 7, 1); Tt, _, _ = A.step_ns(L, 1, G_tier(L, c), 7, 1)
            cells.append(f"t=1 {L}: {usR(T64)} -> {usR(Tt)} us ({spc(pcs(Tt, T64))})")
        print(f"[ALT-P-tier-cpg{c}] c_pg = {c} ns ({'measured lower bound' if c == 38 else '3x the lower bound'}): G(64 KiB) {t10(g64)} ; two-tier {t10(gt)} ({spc(pcs(gt, g64))}) ; G(1 MiB) {t10(g1)} ; " + " ; ".join(cells))
    # --- P5: the measured A-quantization pass replaces the quantizer-cost and host-bounce rows
    print(f"[ALT-P-quant-pass] measured on-device pass {C_Q} ns x {Q_PASSES} per layer = {usR(Q_PASSES*C_Q)} us per layer (the 19 / 8 us epilogue estimate and the magic-bias mechanism are retired); "
          f"per token dense {ms2(quant_per_token(D))} ms, MoE {ms2(quant_per_token(M))} ms, draft {ms2(24*Q_PASSES*C_Q)} ms")
    for s in (D, M):
        T0, _ = F.step(s, 32768); Tq, _ = step_q(s, 32768)
        bm = Q_PASSES * (2 * LAM_MEAS + tn(s["d"] * 2, F.D2H[0]) + tn(s["d"], F.H2D[1])); Tb = T0 + s["nL"] * bm
        print(f"[ALT-P-quant-{s['name']}] 32k t=1: today {ms2(T0)} ms -> {t3(F.tps_card(1000, T0))} ; + measured pass {ms2(Tq)} -> {t3(F.tps_card(1000, Tq))} "
              f"({spc(pcs(F.tps_card(1000, Tq), F.tps_card(1000, T0)))}; {t10(pct(quant_per_token(s), T0))}% of the step) ; "
              f"host-bounce counterfactual at the MEASURED lambda {LAM_MEAS} ns: {usR(bm)} us per layer (was {usR(alt4(s)['host_per_layer'])} at 91 us) -> {ms2(Tb)} -> {t3(F.tps_card(1000, Tb))} ({spc(pcs(F.tps_card(1000, Tb), F.tps_card(1000, T0)))})")
    d0 = draft_token_ns(121); dq = d0 + 24 * Q_PASSES * C_Q
    T4, _ = F.step(D, 32768, 1, 4); T4q, _ = step_q(D, 32768, 1, 4); tau = F.tau_milli(700)
    print(f"[ALT-P-quant-draft] draft token {usR(d0)} -> {usR(dq)} us ({spc(pcs(dq, d0))}); dense spec k=3 a=0.7: {ms2(T4)} -> {ms2(T4q)} ms, {t3(F.tps_card(tau, T4))} -> {t3(F.tps_card(tau, T4q))} tok/s/card")
    # --- P5b: the load-bearing cells with the pass on both sides
    for s in (D, M):
        xs = [min_x(s, p, 32768) for p in range(4)]
        T0q, _ = step_q(s, 32768); Tiq, parts = inst_step_q(s, 32768, xs=xs)
        print(f"[ALT-P-inst-{s['name']}-32k] two instances with the pass: {ms2(T0q)} ms -> {t3(F.tps_card(1000, T0q))} ; instance {ms2(Tiq)} -> {t3(tps_card_inst(1000, Tiq))} ({spc(pcs(tps_card_inst(1000, Tiq), F.tps_card(1000, T0q)))})")
    xs = [min_x(M, p, 32768) for p in range(4)]; T0q, _ = step_q(M, 32768)
    saved = T_SLAB_W4_OVL; lo, hi = 0, 50_000_000
    while lo < hi:
        mid = (lo + hi + 1) // 2; T_SLAB_W4_OVL = mid; T, _ = inst_step_q(M, 32768, xs=xs)
        if tps_card_inst(1000, T) > F.tps_card(1000, T0q): lo = mid
        else: hi = mid - 1
    T_SLAB_W4_OVL = saved
    print(f"[ALT-P-breakeven-q] with the pass on both sides two instances beat one for every W4 core-slab time <= {lo} ns ({t10(rateT(MiB, lo))} GB/s/core of int4; measured 197 844 is {t10(lo*10//197844)}x inside; corrected ser {T_SLAB_W4_SER_C} {'passes' if T_SLAB_W4_SER_C <= lo else 'FAILS'})")
    T0, _ = F.step(M, 32768); Ti, _ = inst_step(M, 32768, xs=xs)
    eta_min = next(e for e in range(0, 1001) if 1000 * 2 * e * 10 ** 9 // (1000 * 4 * Ti) > F.tps_card(1000, T0))
    print(f"[ALT-P-h10] H10 measured at die scale: 1.99x aggregate (eta = 995 per mille); the instance verdict needs only eta > {eta_min - 1} per mille "
          f"(two instances at eta: {t3(2 * 995 * 10 ** 9 // (4 * Ti))} tok/s/card at 995, {t3(2 * eta_min * 10 ** 9 // (4 * Ti))} at {eta_min} vs {t3(F.tps_card(1000, T0))})")
    Ts, _ = fleet_cell(M, 32768, tslab=a['ser']); Tsq = Ts + quant_per_token(M)
    r3 = alt3(M, 32768, 5000); Tmq = r3["T1"] + quant_per_token(M)
    print(f"[ALT-P-variants-q] MoE 32k with the pass: direct path {ms2(Tsq)} -> {t3(F.tps_card(1000, Tsq))} ; megakernel (5 us) {ms2(Tmq)} -> {t3(F.tps_card(1000, Tmq))} "
          f"(thresholds unchanged: the pass is on both sides of the iff); DESIGN-4 round 3 on its fuller basis: 2.035 / 2.012 / 3.720")
    # --- P6: fit margins in bytes and the x shift per GB of overhead
    for s, L in ((M, 32768), (D, 32768), (M, 1048576), (D, 131072)):
        xs = [min_x(s, p, L) for p in range(4)]
        margins = [DIE_MEM - (inst_die_weights(s, p, xs[p]) + inst_die_kv(s, p, L) + WS + O_RT) for p in range(4)]
        savedO = O_RT; O_RT = F.O_RT + GB; xs1 = [min_x(s, p, L) for p in range(4)]; O_RT = savedO
        print(f"[ALT-P-margin-{s['name']}-{L}] exact per-die margin at the minimal x {xs}: {[m // 10**6 for m in margins]} MB ('0.1 GB' was 86.0 - 85.9 in floored tenths); "
              f"minimal x at +1 GB overhead {xs1} (+{[b - a_ for a_, b in zip(xs, xs1)]} per mille per GB)")
    # --- P7: draft on the host CPU share
    print(f"[ALT-P-draft-share] 3 draft tokens {ms2(3*d0)} ms of the verify step {ms2(T4)} ms = {t10(pct(3*d0, T4))}% (the text said 2.3)")
    # --- P8: the measured sequential basis for the tier question (DESIGN-3 round 3: G_page3 / G_tier3)
    for c in (38, 114):
        print(f"[ALT-P-tier3-cpg{c}] measured per-page basis (3 101 ns per 64 KiB page, 4 x 12 391 per extent, + c): G(64 KiB) {t10(A.G_page3(64*KiB, c))} ; two-tier 32k {t10(A.G_tier3(32768, c))} ({spc(pcs(A.G_tier3(32768, c), A.G_page3(64*KiB, c)))}) ; 256 KiB pages {t10(A.G_page3(256*KiB, c))}")

if __name__ == "__main__":
    main(); extras(); proofround()


# =====================================================================================================================================
# PROMPT-6 (2026-11-08) — the new-errata audit (#18-#31): the cells it moves in this document. Labels [PA-*]; every label above keeps
# printing its value. No new silicon.
#   (1) erratum #19 on the cold tier (section 2.1): the unpacked int4 tile is the B operand of the f16 x f16 -> f32 tuple and the C chunk
#       accumulated K = 4096 (32 calls) across the per-piece barriers and the A re-lifts (x f16 = 128 KiB > L0A) -- f16 accumulation
#       across a barrier corrupts at >= 2 accumulations. Fix: every call writes a FRESH chunk; the vector unit sums the partials in f32
#       (DESIGN-3 round 4's pattern). Per 2 KiB piece: 2 fresh 1 KiB chunks drained (2 KiB at the measured 152.8 GB/s/core = 13 ns, copy-out
#       engine) and added: 512 f32 lanes = 16 ns at the throughput convention (rho32 1.37) / one chained 512-lane f32 Add = 63 ns (C).
#       Overlapped branch: the vector unit is the cold slab's binding engine (the 5.3 GB/s/core unpack), so the merge adds to it;
#       serial branch: drain + add join the per-piece chain.
#   (2) erratum #29 on the megakernel (section 2.3): every flag round ends in a scalar read of a polled DDR->US copy = one crossing
#       (10-20 us measured); the primary c_sync reading moves from 5 us to the 20 us branch (one batched crossing per round). The cells
#       of the single megakernel at 20 us already print ([ALT-3-*-csync20000]); the combos are restated here.
# =====================================================================================================================================
MERGE6_T = 512 * 512 * 137 * 10 // (100 * R_VEC)          # 8 313 ns per core-slab: 512 pieces x 512 f32 lanes at rho32 1.37 (T)
MERGE6_C = 512 * 637 // 10                                       # 32 614 ns: one chained 512-lane f32 Add (63.7 ns) per piece (C)
DRAIN6_PIECE = tn(2 * KiB, 1528)                                 # 13 ns: 2 fresh 1 KiB chunks at the measured L0C -> US drain rate
ADD6_T, ADD6_C = 512 * 137 * 10 // (100 * R_VEC), 637 // 10   # 16 / 63 ns per piece on the serial chain

def main_pa():
    global T_SLAB_W4_OVL, R_W4_W8EQ_OVL, T_SLAB_W4_SER, T_PIECE_W4_SER
    print("\n# ---- PROMPT-6 (2026-11-08; the new-errata audit): [PA-*] cells. Every label above is unchanged ----")
    D_, M_ = F.DENSE, F.MOE
    xsM = [min_x(M_, p, 32768) for p in range(4)]; xsD = [min_x(D_, p, 32768) for p in range(4)]
    T0M, _ = F.step(M_, 32768); T0D, _ = F.step(D_, 32768)
    oM, oD = F.tps_card(1000, T0M), F.tps_card(1000, T0D)
    base = T_SLAB_W4_OVL
    print(f"[PA-cold-merge] erratum #19: fresh chunks + the vector f32 K-sum per int4 core-slab: {MERGE6_T} ns (T) / {MERGE6_C} ns (C) on the binding vector unit "
          f"(+ {512 * DRAIN6_PIECE} ns of drain on the copy-out engine, overlapped); overlapped core-slab {base} -> {base + MERGE6_T} / {base + MERGE6_C} ns; "
          f"serial piece {T_PIECE_W4_SER_C} -> {T_PIECE_W4_SER_C + DRAIN6_PIECE + ADD6_T} / {T_PIECE_W4_SER_C + DRAIN6_PIECE + ADD6_C} ns")
    sv = (T_SLAB_W4_OVL, R_W4_W8EQ_OVL, T_SLAB_W4_SER, T_PIECE_W4_SER)
    for conv, mg, ad in (("T", MERGE6_T, ADD6_T), ("C", MERGE6_C, ADD6_C)):
        try:
            T_SLAB_W4_OVL = base + mg
            R_W4_W8EQ_OVL = 8 * 2 * MiB * 10 // T_SLAB_W4_OVL
            TM, _ = inst_step(M_, 32768, xs=xsM); TD, _ = inst_step(D_, 32768, xs=xsD)
            TZ, _ = inst_step(M_, 32768, xs=xsM, pop="zipf10")
            gM, gD = tps_card_inst(1000, TM), tps_card_inst(1000, TD)
            print(f"[PA-inst-{conv}] two 4-die instances, overlapped cold tier with the #19 merge: MoE 32k {ms2(TM)} ms -> {t3(gM)} ({spc(pcs(gM, oM))}; was 3.878); "
                  f"Zipf(1.0) {ms2(TZ)} -> {t3(tps_card_inst(1000, TZ))} (was 4.190); dense 32k (W8-eq {t10(R_W4_W8EQ_OVL)}) {ms2(TD)} -> {t3(gD)} ({spc(pcs(gD, oD))}; was 0.156); "
                  f"break-even 1 371 124 ns per core-slab is {t10(1371124 * 10 // T_SLAB_W4_OVL)}x the merged slab (was 6.9x)")
            T_PIECE_W4_SER = T_PIECE_W4_SER_C + DRAIN6_PIECE + ad; T_SLAB_W4_SER = 512 * T_PIECE_W4_SER
            TMs, _ = inst_step(M_, 32768, xs=xsM, cold="ser"); TDs, _ = inst_step(D_, 32768, xs=xsD, cold="ser")
            print(f"[PA-inst-ser-{conv}] serial branch with the #19 merge (piece {T_PIECE_W4_SER} ns, slab {T_SLAB_W4_SER}): MoE 32k {t3(tps_card_inst(1000, TMs))} "
                  f"({spc(pcs(tps_card_inst(1000, TMs), oM))}; was 3.239); dense 32k (W8-eq {t10(w4_dense_rate('ser'))}) {t3(tps_card_inst(1000, TDs))} "
                  f"({spc(pcs(tps_card_inst(1000, TDs), oD))}; was 0.100); break-even margin {t10(1371124 * 10 // T_SLAB_W4_SER)}x (was 3.3x)")
        finally:
            T_SLAB_W4_OVL, R_W4_W8EQ_OVL, T_SLAB_W4_SER, T_PIECE_W4_SER = sv
    # ---- the megakernel combos at the 20 us primary reading (erratum #29: one batched crossing per flag round)
    a = alt1()
    for cs in (5000, 20000):
        Tc = alt3(M_, 32768, cs)["T1"] - (T0M - fleet_cell(M_, 32768, tslab=a["ser"])[0])
        cells = [f"ALT-3+1-moe {ms2(Tc)} ms -> {t3(F.tps_card(1000, Tc))} ({spc(pcs(F.tps_card(1000, Tc), oM))})"]
        for s, xs, o in ((D_, xsD, oD), (M_, xsM, oM)):
            T, _ = inst_step(s, 32768, xs=xs, nlaunch=1)
            Ts = T + s["nL"] * SYNCS_PER_LAYER[s["name"]] * cs + s["nL"] * 2 * tn(reduction_bytes(1, s["d"]), F.R_GEMM)
            cells.append(f"ALT-2+3-{s['name']} {ms2(Ts)} -> {t3(tps_card_inst(1000, Ts))} ({spc(pcs(tps_card_inst(1000, Ts), o))})")
        print(f"[PA-mega-combos-{cs // 1000}us] c_sync {cs} ns{' (the erratum-#29 primary reading)' if cs == 20000 else ' (as written)'}: " + "; ".join(cells))
    r = alt3(M_, 32768, 20000); rd = alt3(D_, 32768, 20000)
    print(f"[PA-mega-20us] the single megakernel at the primary reading: MoE {t3(F.tps_card(1000, r['T1']))} ({spc(pcs(F.tps_card(1000, r['T1']), oM))}), "
          f"dense {t3(F.tps_card(1000, rd['T1']))} ({spc(pcs(F.tps_card(1000, rd['T1']), oD))}); the iff lines (108 430 / 109 902 ns) are unchanged -- "
          f"the margin to them is {t10(108430 * 10 // 20000)}x / {t10(109902 * 10 // 20000)}x at 20 us (was >= 5x at the 'us-class' reading)")

if __name__ == "__main__":
    main_pa()
