#!/usr/bin/env python3
"""proof/fleet.py -- executable integer cost model for DESIGN-4.md (fleet partition planner: 8 dies, no P2P,
layer-split-only runtime). Conventions of proof/model.py and proof/moe.py so the proof session can transcribe
it 1:1 into core Lean:
  bytes ; KiB = 1024, MiB = 2^20, GiB = 2^30 ; GB = 10^9 (decimal: HW-MAP quotes memory and rates decimally)
  rates   : tenths of GB/s (1 B/ns = 1 GB/s)      time : ns, floor  (b*10 // R)
  tokens  : thousandths                            tokens/s : thousandths
  usR = (ns+500)//1000 ; pct = tenths of a percent, round half up ; ceil(a,b) = (a+b-1)//b
Every constant is tagged with its origin: [M] HW-MAP measured, [D2] DESIGN-2 derived, [A] assumption with the
host experiment (H-number, DESIGN-4.md section 8) that measures it. Run: python3 -I proof/fleet.py
"""
KiB, MiB, GiB, GB = 1024, 1 << 20, 1 << 30, 10 ** 9

# ------------------------------------------------------------------ HW-MAP [M] --------------------------------
R_GEMM     = 1746          # full W8 decode kernel, aggregate, flat m=1..16                 [M data-movement]
R_GEMM_SER = 1389          # its serial fallback                                            [M data-movement]
R_DDR      = 1738          # LPDDR r+w streaming roof                                       [M card table]
R_READ     = 1810          # pure-read streams                                              [M data-movement]
H2D = {0: 276, 1: 139}     # host -> die, tenths of GB/s; die 1 transits die 0              [M card table]
D2H = {0: 273, 1: 190}     # die -> host                                                    [M card table]
R_D2D      = 107           # die-to-die copy via host, r+w                                  [M card table]
C_MMA      = 15            # ns per (16,16,128) MMA call                                    [M data-movement]
R_VEC_DIE  = 8 * 432       # tenths of G lane-ops/s per die (40 lanes x 1.08 GHz x 8)      [M compute table]
T_LAUNCH   = 91_000        # ns launch + queue floor                                        [M data-movement]
DIE_MEM    = 86 * GB       # usable DDR per die                                             [M hierarchy]
DIES       = 8             # 4 cards x 2 dies                                               [M card table]
ROWS_FLAT  = 16            # m <= 16 flat; m >= 24 leaves the flat regime (81/59/43)        [M data-movement]
P_SUSTAIN, P_TDP = 141, 150  # W per card, sustained all-core matrix load / TDP class       [M card table]
# ------------------------------------------------------------------ DESIGN-2 [D2] -----------------------------
T_SLAB_SER = 122_979       # ns per (expert, 16 MiB slab) per core, serial regime            [D2 M15 / Z3]
T_SLAB_PP  = 97_015        # ping-pong regime: (784118 - 8000) / 8 rounded                   [D2 M1]
F_MOE      = 8_000         # fixed per MoE launch (fill + dispatch + tail)                   [D2 A]
D_TAB = {("uniform", 1): 8, ("uniform", 4): 32, ("uniform", 16): 128,                     # [D2 T8] D(t)
         ("zipf10", 1): 8, ("zipf10", 4): 25, ("zipf10", 16): 68,
         ("zipf15", 1): 8, ("zipf15", 4): 20, ("zipf15", 16): 45}
# ------------------------------------------------------------------ assumptions [A] ---------------------------
O_RT    = 2 * GiB          # runtime overhead per die after load                            [A, H8]
WS      = 64 * MiB         # activation / workspace per die                                 [A, H8]
LAMBDA  = {"lo": 10_000, "mid": 91_000, "hi": 500_000}   # host-bounce latency per direction, ns [A, H3]
C_EXP   = {"native": 4, "poly": 16}   # vector lane-ops per attention score (PROBLEM-3 E branch) [A/U, E-exp]
G_BR    = {"stream": 1746, "gather3x": 582}   # KV read rate (PROBLEM-3 G branch; 582 = 1746/3) [A/U, E-gather]
ALPHA   = {"a50": 500, "a70": 700, "a90": 900}  # draft acceptance per token, thousandths          [A, fleet-only]
K_DRAFT = 3

# ------------------------------------------------------------------ helpers ------------------------------------
def ceil(a, b):   return (a + b - 1) // b
def tn(b, R):     return b * 10 // R                 # ns for b bytes at R tenths of GB/s
def usR(ns):      return (ns + 500) // 1000
def msR(ns):      return (ns + 500_000) // 1_000_000
def pct(n, d):    return (2 * n * 1000 + d) // (2 * d)
def pctH(n, d):   return (2 * n * 10000 + d) // (2 * d)       # hundredths of a percent
def t10(x):       return f"{x // 10}.{x % 10}"
def t3(x):        return f"{x // 1000}.{x % 1000:03d}"
def gb1(b):       return f"{b // GB}.{(b % GB) // (GB // 10)}"     # decimal GB, one decimal (floor)
def ms2(ns):      return f"{ns // 1_000_000}.{(ns % 1_000_000) // 10_000:02d}"

# ------------------------------------------------------------------ shapes ------------------------------------
def dense_layer_bytes(d, ffn, Hkv, dh): return d * (d + 2 * Hkv * dh) + d * d + 3 * d * ffn
DENSE = dict(name="dense", nL=120, d=16384, Hq=128, Hkv=8, dh=128, vocab=128256, nlaunch=6, moe=False,
             layers=[15] * 8, draft_pos=1)
DENSE["w_layer"]  = dense_layer_bytes(16384, 53248, 8, 128)        # 3 187 671 040 B i8 streamed per token
DENSE["w_res"]    = DENSE["w_layer"]                               # resident bytes per layer (same)
DENSE["w_embed"]  = 16384 * 128256
DENSE["w_head"]   = 16384 * 128256
DENSE["kv_tok"]   = 2 * 8 * 128 * 2                                # 4096 B per token per layer, f16
MOE = dict(name="moe", nL=28, d=4096, Hq=32, Hkv=8, dh=128, vocab=128256, nlaunch=7, moe=True,
           layers=[4, 3, 4, 3, 4, 3, 4, 3], draft_pos=7, E=256, k=8, slab=4096 * 4096, slabs=3)
MOE["w_attn"]     = 4096 * (4096 + 2 * 8 * 128) + 4096 * 4096       # 41 943 040 B per layer
MOE["w_experts"]  = 256 * 3 * 4096 * 4096                          # 12 884 901 888 B resident per layer
MOE["w_res"]      = MOE["w_attn"] + MOE["w_experts"]
MOE["w_embed"]    = 4096 * 128256
MOE["w_head"]     = 4096 * 128256
MOE["kv_tok"]     = 4096
DRAFT = dict(w=1 * GB, nlaunch=121, kv_window=24 * 4096 * (2 * 8 * 64 * 2))   # 1 GB i8, 24 layers, 4k window
POS = [(0, 1), (0, 0), (1, 1), (1, 0), (2, 1), (2, 0), (3, 1), (3, 0)]       # chain position -> (card, die)
SHAPES = (DENSE, MOE)
L_SET = {"4k": 4096, "32k": 32768, "128k": 131072, "1M": 1048576}

def total_resident(s):   return s["nL"] * s["w_res"] + s["w_embed"] + s["w_head"]
def streamed_per_token(s, rows=1, fam="uniform"):
    if not s["moe"]: return s["nL"] * s["w_layer"] + s["w_head"]
    return s["nL"] * (s["w_attn"] + D_of(fam, rows) * s["slabs"] * s["slab"]) + s["w_head"]

# ------------------------------------------------------------------ memory (section 1) -------------------------
def die_weights(s, pos, draft=True):
    w = s["layers"][pos] * s["w_res"]
    if pos == 0: w += s["w_embed"]
    if pos == DIES - 1: w += s["w_head"]
    if draft and pos == s["draft_pos"]: w += DRAFT["w"] + DRAFT["kv_window"]
    return w
def die_kv(s, pos, L, B=1, i8=False):
    b = s["layers"][pos] * s["kv_tok"] * L * B
    return b // 2 if i8 else b
def die_total(s, pos, L, B=1, i8=False, draft=True): return die_weights(s, pos, draft) + die_kv(s, pos, L, B, i8) + WS + O_RT
def feasible(s, L, B=1, i8=False):  return all(die_total(s, p, L, B, i8) <= DIE_MEM for p in range(DIES))
def Lmax(s, B=1, i8=False):
    per = []
    for p in range(DIES):
        room = DIE_MEM - O_RT - WS - die_weights(s, p)
        per_tok = s["layers"][p] * s["kv_tok"] * B // (2 if i8 else 1)
        per.append(room // per_tok)
    return min(per)
def min_dies(s):   # smallest die count whose uniform weight share leaves >= 0 room for KV at L = 4k
    for n in range(1, DIES + 1):
        if ceil(total_resident(s), n) + O_RT + WS + DRAFT["w"] + ceil(s["nL"], n) * s["kv_tok"] * 4096 <= DIE_MEM: return n
    return None

# ------------------------------------------------------------------ exchange (section 2) -----------------------
def hop_ns(b, src, dst, lam): return tn(b, D2H[src]) + tn(b, H2D[dst]) + 2 * lam
def exchange(s, rows, lam):
    """per token-step host bounces of the chain: 7 inter-die hops of the activation, logits D2H from the last
    die, sampled token id H2D to the first die. Returns (total ns, bandwidth-only ns, latency count)."""
    act = rows * s["d"] * 2; logits = rows * s["vocab"] * 4; ids = rows * 4
    bw = 0
    for p in range(DIES - 1):
        bw += tn(act, D2H[POS[p][1]]) + tn(act, H2D[POS[p + 1][1]])
    bw += tn(logits, D2H[POS[DIES - 1][1]]) + tn(ids, H2D[POS[0][1]])
    nlat = 2 * (DIES - 1) + 2
    return bw + nlat * lam, bw, nlat
def link_bytes_per_card(s, rows):   # bytes through each card's die-0 link per token (own + die-1 transit)
    act = rows * s["d"] * 2; logits = rows * s["vocab"] * 4
    per = []
    for c in range(4):
        b = 0
        for p in range(DIES):
            if POS[p][0] != c: continue
            if p > 0: b += act            # inbound
            if p < DIES - 1: b += act     # outbound
            if p == DIES - 1: b += logits + rows * 4 * 0
            if p == 0: b += rows * 4
        per.append(b)
    return per

# ------------------------------------------------------------------ per-layer time (section 3) -----------------
def attn_parts(s, L, B, t, G, cE, i8=False):
    kvb = s["kv_tok"] * L * B // (2 if i8 else 1)
    kv = tn(kvb, G)
    sm = B * t * s["Hq"] * L * cE * 10 // R_VEC_DIE
    g = s["Hq"] // s["Hkv"]; frags = ceil(t * g, 16)
    calls = B * 2 * s["Hkv"] * (L // 16) * frags
    mma = calls * C_MMA // 8
    return kv, sm, mma
def attn_ns(s, L, B, t, G, cE, i8=False): return max(attn_parts(s, L, B, t, G, cE, i8))
def D_of(fam, rows, E=256, k=8):
    """active experts per step: uniform = min(k*rows, E) by definition (DESIGN-2 Z1/U); Zipf only at the
    generator-measured rows 1/4/16 (DESIGN-2 T8) -- no interpolation."""
    if fam == "uniform": return min(k * rows, E)
    return D_TAB[(fam, rows)]
def experts_ns(s, rows, fam, regime):
    T = T_SLAB_SER if regime == "serial" else T_SLAB_PP
    return 2 * F_MOE + s["slabs"] * D_of(fam, rows) * T
def gemm_ns(s, rows, fam, regime):
    if not s["moe"]: return tn(s["w_layer"], R_GEMM)
    return tn(s["w_attn"], R_GEMM) + experts_ns(s, rows, fam, regime)
def draft_ns(lam, launch, k=K_DRAFT):
    per = tn(DRAFT["w"], R_GEMM) + tn(DRAFT["kv_window"], R_GEMM) + (DRAFT["nlaunch"] * T_LAUNCH if launch else 0) \
          + tn(128256 * 4, D2H[0]) + 2 * lam
    return k * per
BR0 = dict(G="stream", cE="native", lam="mid", launch=True, regime="serial", fam="uniform", i8=False)
def step(s, L, B=1, t=1, **kw):
    br = dict(BR0); br.update(kw)
    rows = B * t; assert rows <= ROWS_FLAT
    G, cE, lam = G_BR[br["G"]], C_EXP[br["cE"]], LAMBDA[br["lam"]]
    gemm = s["nL"] * gemm_ns(s, rows, br["fam"], br["regime"])
    kv, sm, mma = attn_parts(s, L, B, t, G, cE, br["i8"])
    attn = s["nL"] * max(kv, sm, mma)
    head = tn(s["w_head"], R_GEMM)
    launch = (s["nL"] * s["nlaunch"] + 2) * T_LAUNCH if br["launch"] else 0
    xch, xbw, nlat = exchange(s, rows, lam)
    draft = draft_ns(lam, br["launch"]) if t > 1 else 0
    T = gemm + attn + head + launch + xch + draft
    parts = {"W": gemm + head, "KV": s["nL"] * kv, "SM": s["nL"] * sm, "MMA": s["nL"] * mma,
             "LAUNCH": launch, "XCH": xch, "DRAFT": draft}
    return T, parts
def tau_milli(alpha, k=K_DRAFT):
    tot, p = 0, 1000
    for _ in range(k + 1): tot += p; p = p * alpha // 1000
    return tot
def tps_card(tok_milli, T): return tok_milli * 10 ** 9 // (4 * T)     # thousandths of tokens/s per card
def tps_fleet(tok_milli, T): return tok_milli * 10 ** 9 // T
def binding(s, L, B, t, parts, i8=False):
    if not feasible(s, L, B, i8): return "MEM"
    big = max(parts, key=lambda k: parts[k])
    # attention sub-terms are alternatives (max), report the realised one; W/KV/LAUNCH/XCH/DRAFT are additive
    return big

# ------------------------------------------------------------------ what-ifs (section 5) -----------------------
def t_reduce(lam, rows, d):
    """one host all-reduce of a [rows, d] f32 partial from 8 dies: per card the die-0 trunk carries both dies'
    D2H partials (die 1 at 19.0, die 0 at 27.3) then both H2D results f16 (13.9 / 27.6); + 2 latencies."""
    part = rows * d * 4; res = rows * d * 2
    return tn(part, D2H[1]) + tn(part, D2H[0]) + tn(res, H2D[1]) + tn(res, H2D[0]) + 2 * lam
def step_tensor_split(s, L, B=1, t=1, **kw):
    br = dict(BR0); br.update(kw)
    rows = B * t; G, cE, lam = G_BR[br["G"]], C_EXP[br["cE"]], LAMBDA[br["lam"]]
    if s["moe"]:
        gemm_l = tn(s["w_attn"], 8 * R_GEMM) + 2 * F_MOE + s["slabs"] * D_of(br["fam"], rows) * (T_SLAB_SER if br["regime"] == "serial" else T_SLAB_PP) // 8
    else:
        gemm_l = tn(s["w_layer"], 8 * R_GEMM)
    kv, sm, mma = attn_parts(s, L, B, t, G, cE, br["i8"])
    attn_l = max(kv, sm, mma) // 8
    launch = (s["nL"] * s["nlaunch"] + 2) * T_LAUNCH if br["launch"] else 0
    red = s["nL"] * 2 * t_reduce(lam, rows, s["d"])
    T = s["nL"] * (gemm_l + attn_l) + tn(s["w_head"], 8 * R_GEMM) + launch + red
    return T, {"W/8": s["nL"] * gemm_l, "KV/8": s["nL"] * attn_l, "LAUNCH": launch, "REDUCE": red}
def die_block_ns(s, pos, L, B=1, t=1, **kw):
    br = dict(BR0); br.update(kw)
    rows = B * t; G, cE, lam = G_BR[br["G"]], C_EXP[br["cE"]], LAMBDA[br["lam"]]
    n = s["layers"][pos]
    T = n * (gemm_ns(s, rows, br["fam"], br["regime"]) + attn_ns(s, L, B, t, G, cE, br["i8"]) + (s["nlaunch"] * T_LAUNCH if br["launch"] else 0))
    if pos == DIES - 1: T += tn(s["w_head"], R_GEMM) + (2 * T_LAUNCH if br["launch"] else 0)
    act = rows * s["d"] * 2
    if pos > 0: T += tn(act, H2D[POS[pos][1]]) + lam
    if pos < DIES - 1: T += tn(act, D2H[POS[pos][1]]) + lam
    else: T += tn(rows * s["vocab"] * 4, D2H[POS[pos][1]]) + lam
    return T

# ------------------------------------------------------------------ crossovers (section 4) ---------------------
def Lstar_kv(s, G, B=1, rows=1, fam="uniform", regime="serial", i8=False):
    """smallest L with KV stream time >= weight-stream time per layer: kv_tok*L*B*10/G >= T_w  (per layer)."""
    Tw = gemm_ns(s, rows, fam, regime)
    per_tok = s["kv_tok"] * B // (2 if i8 else 1)
    return ceil(Tw * G, per_tok * 10)
def rows_star_softmax(s, G, cE, i8=False):
    """smallest rows (= B*t, same B on both sides) with softmax time >= KV stream time; L cancels."""
    per_tok = s["kv_tok"] // (2 if i8 else 1)
    # rows*Hq*cE*10/R_VEC >= per_tok*rows_kv*10/G with rows_kv = B = rows at t = 1, i.e. independent of rows;
    # at B = 1: t*Hq*cE/R_VEC >= per_tok/G  ->  t >= per_tok*R_VEC/(G*Hq*cE)
    return ceil(per_tok * R_VEC_DIE, G * s["Hq"] * cE)

# ================================================================== main ========================================
def main():
    print("# proof/fleet.py -- derived cells of DESIGN-4.md\n")
    # ---------------------------------------------------------------- F0 shapes
    print("## [F0] shapes")
    for s in SHAPES:
        tot = total_resident(s)
        print(f"[F0-{s['name']}] layers {s['nL']}, resident/layer {s['w_res']} B, embed {s['w_embed']} B, head {s['w_head']} B,"
              f" total int8 {tot} B = {gb1(tot)} GB (int4 source {gb1(tot // 2)} GB), kv/token/layer {s['kv_tok']} B,"
              f" kv/token total {s['nL'] * s['kv_tok']} B, streamed/token (t=1) {streamed_per_token(s)} B = {gb1(streamed_per_token(s))} GB")
    print(f"[F0-moe-experts] expert slabs per layer {MOE['w_experts']} B = {MOE['w_experts'] // GiB} GiB = {gb1(MOE['w_experts'])} GB ; K+V written per token per layer = kv_tok = {MOE['kv_tok'] // KiB} KiB")
    print(f"[F0-draft] {DRAFT['w']} B i8, {DRAFT['nlaunch']} launches/token, KV window {DRAFT['kv_window']} B")
    print(f"[F0-kv1M] KV bytes at L=1M (2^20) f16: dense {gb1(DENSE['nL'] * 4096 * 2**20)} GB, moe {gb1(MOE['nL'] * 4096 * 2**20)} GB ;"
          f" fleet capacity 8 x 86 = {8 * 86} GB")
    print()
    # ---------------------------------------------------------------- F1 memory
    print("## [F1] memory feasibility per die (bytes decimal GB; usable 86.0)")
    for s in SHAPES:
        print(f"[F1-{s['name']}-layout] chain pos -> (card,die), layers: {[(p, POS[p], s['layers'][p]) for p in range(DIES)]} ; draft at pos {s['draft_pos']}")
        for lab, L in (("4k", 4096), ("1M", 1048576)):
            for i8 in ((False,) if s["moe"] or lab == "4k" else (False, True)):
                rows = []
                for p in range(DIES):
                    w = die_weights(s, p); kv = die_kv(s, p, L, 1, i8); tot = die_total(s, p, L, 1, i8)
                    rows.append((p, w, kv, tot, tot <= DIE_MEM))
                worst = max(rows, key=lambda r: r[3])
                print(f"[F1-{s['name']}-{lab}{'-kvi8' if i8 else ''}] feasible={feasible(s, L, 1, i8)} ; worst die pos {worst[0]}: weights {gb1(worst[1])} + KV {gb1(worst[2])} + ws 0.07 + rt 2.15 = {gb1(worst[3])} GB ; "
                      + " ".join(f"p{r[0]}:{gb1(r[3])}" for r in rows))
        print(f"[F1-{s['name']}-Lmax] L_max f16 B=1: {Lmax(s)} ; B=4: {Lmax(s, 4)} ; B=16: {Lmax(s, 16)} ; KV-i8 B=1: {Lmax(s, 1, True)} ; min dies: {min_dies(s)}")
        print(f"[F1-{s['name']}-draftfree] L_max without the draft on its die: {min((DIE_MEM - O_RT - WS - die_weights(s, p, False)) // (s['layers'][p] * s['kv_tok']) for p in range(DIES))}")
    print(f"[F1-dLmax] dense: tokens of L_max lost per GB of extra per-die overhead = {GB // (15 * 4096)} ; moe (4-layer die) {GB // (4 * 4096)}")
    room = DIE_MEM - die_weights(DENSE, 0) - die_kv(DENSE, 0, 1 << 20, 1, True) - WS
    print(f"[F1-ort-threshold] dense 1M KV-int8 fits iff the per-die runtime overhead <= {room} B = {gb1(room)} GB = {room * 100 // GiB / 100} GiB "
          f"(assumed 2 GiB = {gb1(O_RT)} GB ; margin at 2 GiB {gb1(DIE_MEM - die_total(DENSE, 0, 1 << 20, 1, True))} GB)")
    for s in SHAPES:
        n4, n5 = ceil(s["nL"], 4), ceil(s["nL"], 5)
        print(f"[F1-{s['name']}-min-dies] 4 dies: some die holds >= {n4} layers = {gb1(n4 * s['w_res'])} GB > 86 for ANY assignment (total {gb1(total_resident(s))} GB > 4 x 86 = 344) ; "
              f"5 dies: {n5} layers/die = {gb1(n5 * s['w_res'])} GB, worst die (+embed) {gb1(n5 * s['w_res'] + s['w_embed'] + n5 * s['kv_tok'] * 4096 + WS + O_RT)} GB at L=4k, "
              f"lm_head+draft die {gb1(n5 * s['w_res'] + s['w_head'] + DRAFT['w'] + DRAFT['kv_window'] + n5 * s['kv_tok'] * 4096 + WS + O_RT)} GB"
              + (f" ; dense 5-die L_max {(DIE_MEM - O_RT - WS - 24 * s['w_res'] - s['w_embed']) // (24 * 4096)}" if not s["moe"] else ""))
    print()
    # ---------------------------------------------------------------- F2 exchange
    print("## [F2] exchange traffic per token-step (t=1 rows unless stated)")
    for s in SHAPES:
        for rows in (1, 4, 16):
            act = rows * s["d"] * 2
            print(f"[F2-{s['name']}-rows{rows}] activation {act} B ; logits {rows * s['vocab'] * 4} B ; per-hop us: "
                  f"d1->d0 {usR(hop_ns(act, 1, 0, 0))}, d0->d1 {usR(hop_ns(act, 0, 1, 0))} (bandwidth only) ; "
                  f"logits D2H from d0 {usR(tn(rows * s['vocab'] * 4, D2H[0]))} us")
            tot, bw, nlat = exchange(s, rows, 0)
            print(f"      bandwidth-only total {bw} ns = {usR(bw)} us over {nlat} latencies ; with lambda lo/mid/hi: "
                  + ", ".join(f"{k}:{usR(exchange(s, rows, v)[0])} us" for k, v in LAMBDA.items())
                  + f" ; die-0 link bytes per card per token {link_bytes_per_card(s, rows)}")
    print(f"[F2-order] the hop sum = 4*(h0+h1+g0+g1) - h(first die) - g(last die): order-dependent only through the first and last die types, "
          f"plus which die emits the logits (d0 27.3 vs d1 19.0): {usR(tn(128256 * 4, D2H[0]))} vs {usR(tn(128256 * 4, D2H[1]))} us at rows=1")
    def bw_order(s, m):
        bitd = lambda p: (m >> p) & 1; act = s["d"] * 2
        return sum(tn(act, D2H[bitd(p)]) + tn(act, H2D[bitd(p + 1)]) for p in range(7)) + tn(s["vocab"] * 4, D2H[bitd(7)]) + tn(4, H2D[bitd(0)])
    cls = {}
    for m in range(256):
        if bin(m).count("1") == 4: cls.setdefault(((m >> 0) & 1, (m >> 7) & 1), set()).add(bw_order(DENSE, m))
    print(f"[F2-order-classes] dense r=1 bandwidth sum by (first die, last die) over all 70 orders with four dies of each kind: "
          + ", ".join(f"(d{k[0]},d{k[1]}): {sorted(v)} ns" for k, v in sorted(cls.items())) + f" ; chosen order (d1,d0) = {bw_order(DENSE, 0b01010101)} ns = min")
    print()
    # ---------------------------------------------------------------- F3 step table
    print("## [F3] per-layer components and step time, primary branch (G stream, exp native, lambda 91 us, launches serialised, MoE serial, uniform routing)")
    for s in SHAPES:
        print(f"[F3-{s['name']}-layer] gemm/layer {gemm_ns(s, 1, 'uniform', 'serial')} ns"
              + (f" (attn GEMMs {tn(s['w_attn'], R_GEMM)} + experts {experts_ns(s, 1, 'uniform', 'serial')} serial / {experts_ns(s, 1, 'uniform', 'pp')} pp)" if s["moe"] else "")
              + f" ; head {tn(s['w_head'], R_GEMM)} ns ; launch/layer {s['nlaunch'] * T_LAUNCH} ns")
        for lab, L in L_SET.items():
            kv, sm, mma = attn_parts(s, L, 1, 1, G_BR["stream"], C_EXP["native"])
            kv3 = attn_parts(s, L, 1, 1, G_BR["gather3x"], C_EXP["native"])[0]
            smp = attn_parts(s, L, 1, 1, G_BR["stream"], C_EXP["poly"])[1]
            print(f"[F3-{s['name']}-{lab}-attn] per layer: KV {kv} ns (gather3x {kv3}), softmax native {sm} / poly {smp}, MMA {mma} ns")
    print()
    print("| shape | L | config | feasible | T_step ms | W ms | KV ms | launch ms | bounce ms | draft ms | tokens/step | tok/s/card | binding |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    def row(s, lab, L, cfg, B, t, tok_milli, **kw):
        T, p = step(s, L, B, t, **kw)
        i8 = kw.get("i8", False)
        fe = feasible(s, L, B, i8)
        print(f"| {s['name']} | {lab} | {cfg} | {'yes' if fe else 'NO'} | {ms2(T)} | {ms2(p['W'])} | {ms2(p['KV'])} | {ms2(p['LAUNCH'])} | {ms2(p['XCH'])} | {ms2(p['DRAFT'])} | {t3(tok_milli)} | {t3(tps_card(tok_milli, T)) if fe else '-'} | {binding(s, L, B, t, p, i8)} |")
        return T
    for s in SHAPES:
        for lab, L in L_SET.items():
            row(s, lab, L, "B=1 t=1", 1, 1, 1000)
            if lab == "1M" and not s["moe"]:
                row(s, lab, L, "B=1 t=1 KV-i8", 1, 1, 1000, i8=True)
            row(s, lab, L, "spec k=3 a=0.7", 1, 4, tau_milli(700))
            if lab == "1M" and not s["moe"]:
                row(s, lab, L, "spec k=3 a=0.7 KV-i8", 1, 4, tau_milli(700), i8=True)
            row(s, lab, L, "B=16 t=1", 16, 1, 16000)
    print()
    # ---------------------------------------------------------------- F3b branch table at 32k
    print("## [F3b] L=32k, B=1, t=1: every branch toggled one at a time (tok/s/card, thousandths)")
    for s in SHAPES:
        base, _ = step(s, 32768)
        cells = {"primary": base}
        for k, v in (("G", "gather3x"), ("cE", "poly"), ("lam", "lo"), ("lam", "hi"), ("launch", False), ("regime", "pp"), ("fam", "zipf15")):
            if k in ("regime", "fam") and not s["moe"]: continue
            cells[f"{k}={v}"] = step(s, 32768, **{k: v})[0]
        print(f"[F3b-{s['name']}] " + " ; ".join(f"{k}: {ms2(T)} ms -> {t3(tps_card(1000, T))}" for k, T in cells.items()))
        lo = step(s, 32768, G="gather3x", cE="poly", lam="hi")[0]
        hi = step(s, 32768, lam="lo", launch=False, **({"regime": "pp"} if s["moe"] else {}))[0]
        print(f"[F3b-{s['name']}-bracket] pessimistic (gather3x, poly, lambda hi): {ms2(lo)} ms -> {t3(tps_card(1000, lo))} ; optimistic (lambda lo, launches pipelined{', MoE pp' if s['moe'] else ''}): {ms2(hi)} ms -> {t3(tps_card(1000, hi))}")
    print()
    # ---------------------------------------------------------------- F3c MoE routing families at B=16
    print("## [F3c] MoE B=16 t=1 by routing family (D from DESIGN-2 T8), L=32k and 1M")
    for fam in ("uniform", "zipf10", "zipf15"):
        for lab in ("32k", "1M"):
            T, p = step(MOE, L_SET[lab], 16, 1, fam=fam)
            print(f"[F3c-{fam}-{lab}] D={D_of(fam, 16)} ; T_step {ms2(T)} ms ; W {ms2(p['W'])} KV {ms2(p['KV'])} ; tok/s/card {t3(tps_card(16000, T))} ; feasible {feasible(MOE, L_SET[lab], 16)}")
    print()
    # ---------------------------------------------------------------- F4 regime map + crossovers
    print("## [F4] crossovers")
    for s in SHAPES:
        for Gk, G in G_BR.items():
            print(f"[F4-{s['name']}-Lkv-{Gk}] L*_KV (KV time >= weight time per layer) B=1: {Lstar_kv(s, G)} ; B=4: {Lstar_kv(s, G, 4)} ; B=16: {Lstar_kv(s, G, 16)}"
                  + (f" ; MoE pp regime B=1: {Lstar_kv(s, G, regime='pp')}" if s["moe"] else f" ; KV-i8: {Lstar_kv(s, G, i8=True)}"))
        for cEk, cE in C_EXP.items():
            print(f"[F4-{s['name']}-tsm-{cEk}] t* (softmax >= KV stream, any L, B=1): stream {rows_star_softmax(s, G_BR['stream'], cE)} ; gather3x {rows_star_softmax(s, G_BR['gather3x'], cE)}"
                  + (f" ; KV-i8 stream {rows_star_softmax(s, G_BR['stream'], cE, True)}" if not s["moe"] else ""))
        # MMA attention bound: rows where MMA calls time >= KV time at B=1: calls = 2*Hkv*(L/16)*ceil(t*g/16)
        g = s["Hq"] // s["Hkv"]
        for t in (1, 4, 16):
            L = 32768
            kv, sm, mma = attn_parts(s, L, 1, t, G_BR["stream"], C_EXP["native"])
            print(f"[F4-{s['name']}-mma-t{t}] per layer at 32k: KV {kv} ns, MMA {mma} ns ({t10(pct(mma, kv))} %), frags {ceil(t * g, 16)}")
    print("[F4-regime] binding per (shape, L, rows) = argmax of the additive terms, MEM if infeasible:")
    for s in SHAPES:
        for lab, L in L_SET.items():
            cells = []
            for (B, t, name) in ((1, 1, "r1"), (1, 4, "t4"), (16, 1, "B16")):
                T, p = step(s, L, B, t)
                b = binding(s, L, B, t, p)
                share = pct(p[b], T) if b != "MEM" else 0
                cells.append(f"{name}:{b}({t10(share)}%)")
            print(f"      {s['name']} {lab}: " + " ".join(cells))
    print()
    # ---------------------------------------------------------------- F5 what-ifs
    print("## [F5] what-ifs at L=32k, B=1, t=1 (primary branch)")
    for s in SHAPES:
        T0, p0 = step(s, 32768)
        xch = p0["XCH"]
        print(f"[F5-{s['name']}-p2p] host-bounce total {usR(xch)} us = {t10(pct(xch, T0))} % of the step: a P2P link at ANY rate saves at most that (bound)")
        Tts, pts = step_tensor_split(s, 32768)
        print(f"[F5-{s['name']}-tsplit] tensor-split over 8 dies: {ms2(Tts)} ms = W/8 {ms2(pts['W/8'])} + KV/8 {ms2(pts['KV/8'])} + lm_head/8 {ms2(tn(s['w_head'], 8 * R_GEMM))} + launch {ms2(pts['LAUNCH'])} + 2x{s['nL']} host reductions {ms2(pts['REDUCE'])} ; "
              f"tok/s/card {t3(tps_card(1000, Tts))} ({t10((Tts and (T0 * 10 // Tts)))}x) ; per reduction {usR(t_reduce(LAMBDA['mid'], 1, s['d']))} us ; with lambda lo: {ms2(step_tensor_split(s, 32768, lam='lo')[0])} ms ; pipelined launches: {ms2(step_tensor_split(s, 32768, launch=False)[0])} ms")
        # tensor-split with P2P all-reduce at X = 50 GB/s and lambda_p2p = 10 us: 8 partials over the P2P fabric
        red_p2p = 8 * (1 * s["d"] * 4) * 10 // 500 + 10_000
        Tp2p = Tts - pts["REDUCE"] + s["nL"] * 2 * red_p2p
        print(f"[F5-{s['name']}-tsplit-p2p] per reduction over P2P(50 GB/s, 10 us) {usR(red_p2p)} us ; step {ms2(Tp2p)} ms -> {t3(tps_card(1000, Tp2p))} tok/s/card ({t10(T0 * 10 // Tp2p)}x)")
        blocks = [die_block_ns(s, p, 32768) for p in range(DIES)]
        mx = max(blocks)
        print(f"[F5-{s['name']}-pipe] per-die block times ms {[ms2(b) for b in blocks]} ; pipelined (Pi=8 sequences) fleet tok/s = 1/max = {t3(tps_fleet(1000, mx))} -> per card {t3(tps_card(1000, mx))} ; "
              f"speed-up over the chain {t10(T0 * 10 // mx)}x ; per-sequence latency stays {ms2(T0)} ms")
        sm = sum(blocks)
        print(f"[F5-{s['name']}-pipe-balance] T_step = sum of blocks + lambda: {T0} = {sm} + {T0 - sm} ns ; loss vs a balanced 8-way split of the same work {t10(pct(8 * mx - sm, 8 * mx))} % "
              f"(ideal {t3(tps_fleet(1000, ceil(sm, 8)))} fleet tok/s, max block {ms2(mx)} vs mean {ms2(ceil(sm, 8))} ms) ; "
              f"trunk utilisation at Pi=8 on the worst card: 8 x {max(link_bytes_per_card(s, 1))} B per block = {pctH(8 * tn(max(link_bytes_per_card(s, 1)), H2D[0]), mx) / 100:.2f} % of 27.6 GB/s")
        kvmove = s["layers"][0] * s["kv_tok"] * 131072
        print(f"[F5-{s['name']}-d2d] per-token D2D traffic 0 B ; re-partition move of one die's KV at 128k = {gb1(kvmove)} GB: {msR(tn(kvmove, R_D2D))} ms at 10.7, {msR(tn(kvmove, 500))} ms at 50")
    print()
    # ---------------------------------------------------------------- F6 spec decode
    print("## [F6] speculative decoding (draft 1 GB i8, 121 launches/token, k=3)")
    print(f"[F6-draft] per draft token: weights {usR(tn(DRAFT['w'], R_GEMM))} us + window KV {usR(tn(DRAFT['kv_window'], R_GEMM))} us + launches {usR(DRAFT['nlaunch'] * T_LAUNCH)} us + logits/id bounce ; "
          f"per verify step (k=3) {ms2(draft_ns(LAMBDA['mid'], True))} ms serialised launches / {ms2(draft_ns(LAMBDA['mid'], False))} ms pipelined")
    print("[F6-tau] tokens per verify step tau(alpha,k): " + ", ".join(f"a={a}: k=1 {t3(tau_milli(a, 1))} k=2 {t3(tau_milli(a, 2))} k=3 {t3(tau_milli(a, 3))} k=5 {t3(tau_milli(a, 5))} k=7 {t3(tau_milli(a, 7))}" for a in (500, 700, 900)))
    for s in SHAPES:
        T1, _ = step(s, 32768)
        for ak, a in ALPHA.items():
            best = None
            for k in range(1, 8):
                T, _ = step(s, 32768, 1, k + 1)
                # step() uses K_DRAFT drafts; recompute draft cost for k
                T = T - draft_ns(LAMBDA["mid"], True) + draft_ns(LAMBDA["mid"], True, k)
                r = tps_card(tau_milli(a, k), T)
                if best is None or r > best[1]: best = (k, r)
            T3, _ = step(s, 32768, 1, 4)
            print(f"[F6-{s['name']}-{ak}] k=3: {ms2(T3)} ms, {t3(tau_milli(a))} tok/step -> {t3(tps_card(tau_milli(a), T3))} tok/s/card = {t10(tps_card(tau_milli(a), T3) * 10 // tps_card(1000, T1))}x of t=1 "
                  f"(exact gain tau*T1/T4 = {t3(tau_milli(a) * T1 // T3)}) ; best k = {best[0]} -> {t3(best[1])}")
        if not s["moe"]:
            T3 = step(s, 32768, 1, 4)[0]; a = 0
            while tau_milli(a, 3) * T1 <= 1000 * T3: a += 1
            print(f"[F6-dense-breakeven] spec k=3 is a gain on dense for every alpha >= {t3(a)} (tau >= T4/T1 = {T3 * 10000 // T1 / 10000})")
    T1m = step(MOE, 32768)[0]
    for fam in ("uniform", "zipf10", "zipf15"):
        T4, p4 = step(MOE, 32768, 1, 4, fam=fam)
        a = 0
        while tau_milli(a, 3) * T1m < 1000 * T4: a += 1          # exact criterion: spec is a loss iff tau * T1 < T4
        print(f"[F6-moe-{fam}-t4] D(4)={D_of(fam, 4)} ; step {ms2(T4)} ms (W {ms2(p4['W'])}) ; tok/s/card at a=0.7: {t3(tps_card(tau_milli(700), T4))} vs t=1 {t3(tps_card(1000, T1m))} ; "
              f"break-even tau(a,3) >= T4/T1 = {T4 * 10000 // T1m / 10000} -> alpha >= {t3(a)} "
              f"(alpha {t3(a - 1)} loses: tau {t3(tau_milli(a - 1, 3))} -> {t3(tps_card(tau_milli(a - 1, 3), T4))} ; alpha {t3(a)} gains: tau {t3(tau_milli(a, 3))} -> {t3(tps_card(tau_milli(a, 3), T4))})")
    E1 = MOE["nL"] * (experts_ns(MOE, 1, "uniform", "serial") - 2 * F_MOE)
    print(f"[F6-moe-mechanism] uniform D(4) = 4 D(1): the verify batch multiplies the active-expert bytes ; expert stream at t=1 E1 = {ms2(E1)} ms = {t10(pct(E1, T1m))} % of T1 ; "
          f"T4 >= 4 E1 + (T1 - E1) = {ms2(4 * E1 + T1m - E1)} ms, so any tau < 1 + 3 E1/T1 = {t3(1000 + 3 * E1 * 1000 // T1m)} is a loss before the draft cost is counted")
    T8d, _ = step(DENSE, 32768, 1, 8)
    T8d = T8d - draft_ns(LAMBDA["mid"], True) + draft_ns(LAMBDA["mid"], True, 7)
    print(f"[F6-dense-k7] k=7 (rows 8): step {ms2(T8d)} ms ; a=0.7 -> {t3(tps_card(tau_milli(700, 7), T8d))} tok/s/card ; a=0.9 -> {t3(tps_card(tau_milli(900, 7), T8d))}")
    print(f"[F6-contention] at Pi=1 the draft never shares a die with a running block (chain is serial); at Pi=8 the draft die loses {usR(draft_ns(0, False) // 3)} us of DDR per draft token")
    print()
    # ---------------------------------------------------------------- F7 rollout
    print("## [F7] rollout: 1 card (chain positions 0,1), 2 cards (0..3), 4 cards")
    for s in SHAPES:
        for ncard in (1, 2, 4):
            npos = 2 * ncard
            for lab in ("4k", "32k", "128k"):
                L = L_SET[lab]
                T = sum(die_block_ns(s, p, L) for p in range(npos))
                # the prefix chain ends on position npos-1: its logits leave from that die
                print(f"[F7-{s['name']}-{ncard}card-{lab}] layers {sum(s['layers'][:npos])} ; predicted prefix step {ms2(T)} ms ; per-die blocks {[ms2(die_block_ns(s, p, L)) for p in range(npos)]}")
    for s in SHAPES:
        st1 = sum(die_block_ns(s, p, 32768) for p in range(2)); act = s["d"] * 2
        extra = tn(s["w_head"], R_GEMM) + 2 * T_LAUNCH + 4 * LAMBDA["mid"] + 3 * tn(act, H2D[1]) + tn(s["vocab"] * 4, D2H[0]) - tn(act, D2H[0])
        print(f"[F7-{s['name']}-identity] 4 x stage-1 ({ms2(st1)} ms) + T_head + 2 T_launch + 4 lambda + 3 hops@13.9 - 1 hop@27.3 + logits ({ms2(extra)} ms) = {ms2(4 * st1 + extra)} ms = direct {ms2(step(s, 32768)[0])} ms exactly ({4 * st1 + extra} = {step(s, 32768)[0]} ns) ; "
              f"round-1 form 4 x stage-1 + 12 lambda + T_head = {ms2(4 * st1 + 12 * LAMBDA['mid'] + tn(s['w_head'], R_GEMM))} ms")
    print()
    # ---------------------------------------------------------------- F8 ladder expectations
    print("## [F8] host-ladder expected values")
    for n in (4 * KiB, 64 * KiB, 1 * MiB, 64 * MiB):
        print(f"[F8-H1-{n}] H2D d0 {tn(n, H2D[0])} ns, d1 {tn(n, H2D[1])} ; D2H d0 {tn(n, D2H[0])}, d1 {tn(n, D2H[1])} ns (plus lambda)")
    print(f"[F8-H2] trunk question: concurrent H2D to both dies of a card = {t10(H2D[0] + H2D[1])} GB/s if independent, {t10(H2D[0])} if die 0's link is the trunk")
    print(f"[F8-H5] KV growth slope per token: dense die {15 * 4096} B, MoE 4-layer die {4 * 4096} B, 3-layer die {3 * 4096} B ; at 128k a dense die holds {gb1(15 * 4096 * 131072)} GB")
    print(f"[F8-H7] load: {gb1(total_resident(DENSE))} GB over 4 cards at 27.6 GB/s trunk = {t10(tn(total_resident(DENSE) // 4, H2D[0]) // 10**8)} s ({t10(tn(total_resident(DENSE) // 4, H2D[0] + H2D[1]) // 10**8)} s if both links of a card were independent, H2) ; int4 source {gb1(total_resident(DENSE) // 2)} GB")
    print(f"[F8-H3] bounce queueing bound behind a bulk chunk C: wait <= C/R: 64 KiB {usR(tn(64 * KiB, H2D[1]))} us, 1 MiB {usR(tn(MiB, H2D[1]))} us, 16 MiB {usR(tn(16 * MiB, H2D[1]))} us on the die-1 link")
    print()
    # ---------------------------------------------------------------- F9 risk numbers
    print("## [F9] risk numbers")
    for s in SHAPES:
        T0, p0 = step(s, 32768)
        bw = exchange(s, 1, 0)[1]; rest = T0 - p0["XCH"]           # T_step = rest + bw + 16*lambda: the step itself carries the 16 latencies
        lam10 = ceil(rest - 9 * bw, 144); lam50 = ceil(rest - bw, 16)   # x*(rest+bw+16L) <= bw+16L  <=>  L >= (x*rest - (1-x)*bw) / (16*(1-x))
        old10 = (T0 // 10 - bw) // 16; old50 = (T0 // 2 - bw) // 16
        print(f"[F9-{s['name']}-lambda] bounce reaches 10 % of the 32k step iff lambda >= {usR(lam10)} us ({lam10} ns) ; 50 % iff lambda >= {usR(lam50)} us ({lam50} ns) ; "
              f"round-1 fixed-denominator figures {usR(old10)} / {usR(old50)} us actually give shares {t10(pct(bw + 16 * old10, rest + bw + 16 * old10))} / {t10(pct(bw + 16 * old50, rest + bw + 16 * old50))} %")
        print(f"[F9-{s['name']}-launch] launch floor share of the 32k step {t10(pct(p0['LAUNCH'], T0))} % ; dense-serial-fallback (138.9) step {ms2(T0 - p0['W'] + p0['W'] * R_GEMM // R_GEMM_SER)} ms")
    Tg, _ = step(MOE, 1048576, G="gather3x")
    print(f"[F9-moe-1M-gather3x] MoE 1M on the gather3x branch: {ms2(Tg)} ms -> {t3(tps_card(1000, Tg))} tok/s/card (stream branch {t3(tps_card(1000, step(MOE, 1048576)[0]))}) ; the G branch moves this cell {t10(tps_card(1000, step(MOE, 1048576)[0]) * 10 // tps_card(1000, Tg))}x")
    Td, _ = step(DENSE, 32768)
    Tds = Td - (step(DENSE, 32768)[1]['W']) + step(DENSE, 32768)[1]['W'] * R_GEMM // R_GEMM_SER
    print(f"[F9-dense-serial] dense 32k if the kernel falls back to the serial regime (138.9): {ms2(Tds)} ms -> {t3(tps_card(1000, Tds))} tok/s/card")
    print(f"[F9-mem] dense 1M f16 KV needs {gb1(DENSE['nL'] * 4096 * 2**20)} GB; fleet room for KV = {gb1(sum(DIE_MEM - O_RT - WS - die_weights(DENSE, p) for p in range(DIES)))} GB ; i8 KV needs {gb1(DENSE['nL'] * 2048 * 2**20)} GB ; f16-K/i8-V needs {gb1(DENSE['nL'] * 3072 * 2**20)} GB (short by {gb1(DENSE['nL'] * 3072 * 2**20 - sum(DIE_MEM - O_RT - WS - die_weights(DENSE, p) for p in range(DIES)))} GB)")
    print(f"[F9-launch-fuse] 6 -> 4 launches per dense layer saves {ms2(240 * T_LAUNCH)} ms per token ; pipelined launches save {ms2(3 * DRAFT['nlaunch'] * T_LAUNCH)} ms per verify step")
    print(f"[F9-rows] B*t <= 16 always (m >= 24 measured at 81 GB/s = {t10(810 * 1000 // R_GEMM)} % of the flat rate)")
    print(f"[F9-power] Pi=1: one die streams at a time -> <= 1 card at the measured sustained {P_SUSTAIN} W; Pi=8: all cards at {P_SUSTAIN} W < {P_TDP} W TDP class (measured, no throttle)")
    print()
    # ---------------------------------------------------------------- F10 markdown tables for DESIGN-4.md
    print("## [F10] markdown tables")
    for s in SHAPES:
        for lab, L, i8 in (("4k", 4096, False), ("1M", 1048576, False)) + ((("1M KV-i8", 1048576, True),) if not s["moe"] else ()):
            print(f"[F10-mem-{s['name']}-{lab}]")
            print("| pos | card.die | layers | weights GB | extras | KV GB | ws+rt GB | total GB | fits |")
            print("|---|---|---|---|---|---|---|---|---|")
            for p in range(DIES):
                ex = []
                if p == 0: ex.append("embed")
                if p == DIES - 1: ex.append("lm_head")
                if p == s["draft_pos"]: ex.append("draft")
                tot = die_total(s, p, L, 1, i8)
                print(f"| {p} | c{POS[p][0]}.d{POS[p][1]} | {s['layers'][p]} | {gb1(die_weights(s, p))} | {'+'.join(ex) or '-'} | {gb1(die_kv(s, p, L, 1, i8))} | {gb1(WS + O_RT)} | {gb1(tot)} | {'yes' if tot <= DIE_MEM else 'NO'} |")
        print(f"[F10-xch-{s['name']}] rows=1 and rows=4")
        print("| hop | from -> to | bytes r=1 | link out / in GB/s | us r=1 (bw) | bytes r=4 | us r=4 (bw) |")
        print("|---|---|---|---|---|---|---|")
        for p in range(DIES - 1):
            a1 = s["d"] * 2; a4 = 4 * s["d"] * 2
            sd, dd = POS[p][1], POS[p + 1][1]
            print(f"| {p} | pos{p} c{POS[p][0]}.d{sd} -> pos{p+1} c{POS[p+1][0]}.d{dd} | {a1} | {t10(D2H[sd])} / {t10(H2D[dd])} | {t10((hop_ns(a1, sd, dd, 0) + 50) // 100)} | {a4} | {t10((hop_ns(a4, sd, dd, 0) + 50) // 100)} |")
        lg1 = s["vocab"] * 4; lg4 = 4 * lg1; ld = POS[DIES - 1][1]
        print(f"| L | pos7 c3.d{ld} logits -> host | {lg1} | {t10(D2H[ld])} / - | {t10((tn(lg1, D2H[ld]) + 50) // 100)} | {lg4} | {t10((tn(lg4, D2H[ld]) + 50) // 100)} |")
        print(f"| I | host token ids -> pos0 c0.d{POS[0][1]} | 4 | - / {t10(H2D[POS[0][1]])} | 0.0 | 16 | 0.0 |")
    print("[F10-headline] L=32k tok/s/card: " + " ; ".join(
        f"{s['name']} t=1 {t3(tps_card(1000, step(s, 32768)[0]))}, spec(a=0.7,k=3) {t3(tps_card(tau_milli(700), step(s, 32768, 1, 4)[0]))}, B=16 {t3(tps_card(16000, step(s, 32768, 16, 1)[0]))}"
        for s in SHAPES))

if __name__ == "__main__":
    main()
