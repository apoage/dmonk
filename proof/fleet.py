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
Round 3 (2026-11-05): the measured re-grounding (HW-MAP e9349c8) and the ALTERNATIVES variants are the [R3-*] section at the
end (imports proof/attn.py for the DESIGN-3 round-3 attention chain); every round-2 label keeps printing its round-2 value.
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


# ================================================================== ROUND 3 (2026-11-05): measured re-grounding ==========
# HW-MAP commit e9349c8 (the season (v1) validation pack) measured the quantities this plan carried as assumptions or as
# PROBLEM-3 branches -- the host-bounce latency (12.2 / 12.1 us per direction, idle == under saturating D2D load), the KV
# gather rate per page size (E21), the softmax op set (E22), the L0C drain, the on-device f16->i8 activation quantization
# pass (43.7 us) -- and ALTERNATIVES.md (dd5f84c, steering correction 0915e22) added three partition variants: two 4-die
# instances with a minimal int4 tier (ALT-2), the MoE expert kernel on the DDR->L0B direct path (ALT-1), and a per-layer
# persistent megakernel with a DDR-flag cross-core sync (ALT-3). Every round-2 label above keeps printing its round-2
# value; the [R3-*] labels below re-derive the cells on the measured constants. The attention model is DESIGN-3's round-3
# chain (proof/attn.py, step3) evaluated at this plan's GQA shapes (rows = t * g per core, g = 16 dense / 4 MoE).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import attn as A
from fractions import Fraction

# --------------------------------------------------------------- round-3 measured inputs [M] -------------------------
LAM3       = 12_200        # host bounce per direction, ns: 12.2 / 12.1 us measured; bounce 23.8-24.6 us; unchanged under load  [M]
LAM3_BR    = {"meas": 12_200, "lo": 10_000, "anchor91": 91_000, "hi": 500_000}   # the round-2 bracket, kept as what-ifs
G3         = {"p256k": 1692, "seq64k": 1690, "shuf64k": 1670, "shuf16k": 1538, "stream174": 1746, "gather3x": 582}   # E21 [M]; gather3x = what-if
C_Q        = 43_700        # on-device f16->i8 A-quantization pass, ns at m=1, K=8192 (+12.2 % over host-packed A)             [M]
Q_PASSES   = 4             # quantized GEMM inputs per layer: QKV, O, gate/up (the router shares it), down (all active experts) [D]
R_GEMM_INT = 1355          # the integrated production kernel f32-in / f32-out: 135.5 GB/s                                   [M] (pessimistic branch)
R_W4V      = 53            # vector i4->f16 unpack, tenths GB/s per core of int4 bytes                                       [M] (ALT-2 premise)
# --------------------------------------------------------------- derived expert-chain inputs [D2 / ALT] ---------------
T_B_DIRECT = 2 * MiB * 80 // R_GEMM                   # 96 089 ns: a 2 MiB core-slab at the 174.6 per-core share (ALT-1)
A_LIFT     = tn(64 * KiB, 265) + 32 * 254 // 10       # 3 285 ns: 64 KiB of A through the 26.5 GB/s loader + 32 x 25.4 ns residual
T_SLAB3    = {"anchor": T_SLAB_SER, "pp": T_SLAB_PP, "direct_ser": T_B_DIRECT + A_LIFT, "direct_ovl": T_B_DIRECT}
T_SLAB_W4  = tn(MiB, R_W4V)                           # 197 844 ns per 1 MiB int4 core-slab on the measured unpack path (ALT-2 cold tier)
R_W4_W8EQ  = 2 * 8 * R_W4V                            # 84.8 W8-equivalent GB/s per die for int4 dense bytes
SYNCS      = {"dense": 4, "moe": 5}                   # megakernel flag rounds per layer (ALT-3)
C_SYNC_BR  = {"2us": 2_000, "5us": 5_000, "20us": 20_000}

# --------------------------------------------------------------- attention: DESIGN-3 round-3 chain at the fleet shapes --
def g_of(s): return s["Hq"] // s["Hkv"]
def attn3_seq(s, L, t, G, variant="rowmax", conv="T", i8=False):
    """DESIGN-3 round-3 step (proof/attn.py step3) for ONE sequence with t query tokens on this shape: rows = t*g per core
    (one KV head per core: H_kv = 8 = cores, d = 128 on both fleet shapes = the DESIGN-3 headline KV geometry).
    Returns (ns, binding engine, parts)."""
    rows = t * g_of(s)
    p, mt = A.passes_of(rows), A.mt_pass(rows)
    bl = A.BL_of(mt); nb = A.nblocks(L, mt); Rd = A.R_DRAIN_M[min(mt, 4)]
    v = A.vec3_ns(bl, mt, variant, conv, A.MERGE_PACK * 100)
    ddr = p * nb * A.ddr_block_ns(G, mt) // (2 if i8 else 1)
    vec, mma, ldr = p * nb * v, p * nb * A.mma_block_ns(mt), p * nb * A.loader_block_ns(mt)
    fixed = 2 * v + A.drain_block_ns(mt, Rd) + A.tail_ops(L, A.mt_of(rows)) * A.UNIT[conv][1] * 10 // (A.R_VEC * 100)
    c = {"KV": ddr, "VEC": vec, "MMA": mma, "LDR": ldr}
    return max(c.values()) + fixed, max(c, key=c.get), dict(c, fixed=fixed, passes=p, mt=mt, nb=nb, vblk=v)

# --------------------------------------------------------------- the round-3 step --------------------------------------
BR3 = dict(G="p256k", var="rowmax", conv="T", lam="meas", launch=True, regime="anchor", fam="uniform", i8=False,
           cq="fixed", gemm="direct", mega=None, pen=0)
def quant_ns(s, rows, mode):
    """the measured on-device A-quantization pass per layer: 'fixed' = 43.7 us per pass (the figure is dominated by its fixed
    part: the elementwise work is < 20 us even at K = 53 248), 'prop' = 43.7 us per 8 192 quantized elements (upper bound)."""
    if mode is None: return 0
    if mode == "fixed": return Q_PASSES * C_Q
    elems = rows * (3 * s["d"] + (53248 if not s["moe"] else 8 * 4096))
    return C_Q * ceil(elems, 8192)
def gemm3_ns(s, rows, fam, regime, gemm="direct"):
    R = R_GEMM if gemm == "direct" else R_GEMM_INT
    if not s["moe"]: return tn(s["w_layer"], R)
    return tn(s["w_attn"], R) + 2 * F_MOE + s["slabs"] * D_of(fam, rows) * T_SLAB3[regime]
def reduction_bytes(rows, d): return 8 * rows * d * 4 + 8 * rows * d * 4 + rows * d * 2 + 8 * rows * d * 2
def launch3_ns(s, rows, launch, mega):
    if mega is None: return (s["nL"] * s["nlaunch"] + 2) * T_LAUNCH if launch else 0
    base = (s["nL"] + 2) * T_LAUNCH if launch else 0             # one launch per layer + lm_head's two
    return base + s["nL"] * (SYNCS[s["name"]] * mega + 2 * tn(reduction_bytes(rows, s["d"]), R_GEMM))
def draft3_ns(lam, launch=True, cq="fixed", mega=None, k=K_DRAFT):
    nl = DRAFT["nlaunch"] if mega is None else 24
    per = tn(DRAFT["w"], R_GEMM) + tn(DRAFT["kv_window"], R_GEMM) + (nl * T_LAUNCH if launch else 0) \
          + (24 * Q_PASSES * C_Q if cq else 0) + tn(128256 * 4, D2H[0]) + 2 * lam
    if mega is not None: per += 24 * SYNCS["dense"] * mega
    return k * per
def step3(s, L, B=1, t=1, **kw):
    br = dict(BR3); br.update(kw)
    rows = B * t; assert rows <= ROWS_FLAT
    G, lam = G3[br["G"]], LAM3_BR[br["lam"]]
    gemm = s["nL"] * gemm3_ns(s, rows, br["fam"], br["regime"], br["gemm"])
    if (not s["moe"]) and br["pen"]: gemm += gemm * br["pen"] // 1000
    a_seq, a_bind, _ = attn3_seq(s, L, t, G, br["var"], br["conv"], br["i8"])
    attn = s["nL"] * B * a_seq
    head = tn(s["w_head"], R_GEMM if br["gemm"] == "direct" else R_GEMM_INT)
    launch = launch3_ns(s, rows, br["launch"], br["mega"])
    quant = s["nL"] * quant_ns(s, rows, br["cq"])
    xch, xbw, nlat = exchange(s, rows, lam)
    draft = draft3_ns(lam, br["launch"], br["cq"], br["mega"]) if t > 1 else 0
    T = gemm + attn + head + launch + quant + xch + draft
    parts = {"W": gemm + head, "ATTN": attn, "LAUNCH": launch, "QUANT": quant, "XCH": xch, "DRAFT": draft}
    return T, parts, a_bind
def binding3(s, L, B, t, parts, a_bind, i8=False):
    if not feasible(s, L, B, i8): return "MEM"
    big = max(parts, key=lambda k: parts[k])
    return f"ATTN:{a_bind}" if big == "ATTN" else big

# --------------------------------------------------------------- what-ifs on the round-3 step --------------------------
def step_tsplit3(s, L, B=1, t=1, **kw):
    br = dict(BR3); br.update(kw)
    rows = B * t; G, lam = G3[br["G"]], LAM3_BR[br["lam"]]
    if s["moe"]:
        gemm_l = tn(s["w_attn"], 8 * R_GEMM) + 2 * F_MOE + s["slabs"] * D_of(br["fam"], rows) * T_SLAB3[br["regime"]] // 8
    else:
        gemm_l = tn(s["w_layer"], 8 * R_GEMM)
    attn_l = B * attn3_seq(s, L, t, G, br["var"], br["conv"], br["i8"])[0] // 8
    launch = (s["nL"] * s["nlaunch"] + 2) * T_LAUNCH if br["launch"] else 0
    quant = s["nL"] * quant_ns(s, rows, br["cq"])
    red = s["nL"] * 2 * t_reduce(lam, rows, s["d"])
    T = s["nL"] * (gemm_l + attn_l) + tn(s["w_head"], 8 * R_GEMM) + launch + quant + red
    return T, {"W/8": s["nL"] * gemm_l, "ATTN/8": s["nL"] * attn_l, "LAUNCH": launch, "QUANT": quant, "REDUCE": red}
def die_block3(s, pos, L, B=1, t=1, **kw):
    br = dict(BR3); br.update(kw)
    rows = B * t; G, lam = G3[br["G"]], LAM3_BR[br["lam"]]
    n = s["layers"][pos]
    T = n * (gemm3_ns(s, rows, br["fam"], br["regime"], br["gemm"]) + B * attn3_seq(s, L, t, G, br["var"], br["conv"], br["i8"])[0]
             + (s["nlaunch"] * T_LAUNCH if br["launch"] else 0) + quant_ns(s, rows, br["cq"]))
    if pos == DIES - 1: T += tn(s["w_head"], R_GEMM) + (2 * T_LAUNCH if br["launch"] else 0)
    act = rows * s["d"] * 2
    if pos > 0: T += tn(act, H2D[POS[pos][1]]) + lam
    if pos < DIES - 1: T += tn(act, D2H[POS[pos][1]]) + lam
    else: T += tn(rows * s["vocab"] * 4, D2H[POS[pos][1]]) + lam
    return T

# --------------------------------------------------------------- crossovers on the block model -------------------------
def Lstar_kv3(s, G, regime="anchor", variant="rowmax", conv="T", i8=False):
    """smallest L (over all L) with the t = 1 attention step >= the per-layer weight time: attention(L) = nb(L)*blk + fixed with
    nb = ceil(16*floor(L/16) / 512) and blk = the per-block cost of the binding engine (KV at f16, the vector chain at KV-int8
    on the chain as specified), so L* = (nb* - 1)*512 + 16 with nb* = ceil((T_w - fixed) / blk) -- checked by evaluation."""
    Tw = gemm3_ns(s, 1, "uniform", regime)
    _, _, pt = attn3_seq(s, 512, 1, G, variant, conv, i8)          # one block: the per-block cost of the binding engine
    blk = max(pt["KV"], pt["VEC"], pt["MMA"], pt["LDR"])
    fx = pt["fixed"]
    if Tw <= fx: return 16
    nbs = ceil(Tw - fx, blk); Ls = (nbs - 1) * 512 + 16
    assert attn3_seq(s, Ls, 1, G, variant, conv, i8)[0] >= Tw and attn3_seq(s, Ls - 16, 1, G, variant, conv, i8)[0] < Tw
    return Ls
def Gstar3(s, L, regime="anchor", variant="rowmax", conv="T"):
    """the cell is attention-bound at t = 1 iff G <= G* (tenths): nb*blk(G) + fixed >= T_w  <=>  2 MiB*10/G >= (T_w - fixed)/nb."""
    Tw = gemm3_ns(s, 1, "uniform", regime); fx = attn3_seq(s, 512, 1, 1692, variant, conv)[2]["fixed"]
    nb = A.nblocks(L, 1); k0 = ceil(Tw - fx, nb) if Tw > fx else 1
    return 512 * 4096 * 10 // k0
def tstar3(s, variant="rowmax", conv="T", G=1692, i8=False):
    """smallest t with the per-block vector time >= the per-block KV time (L cancels): rows* = 16*mt* at the shape's g."""
    for t in range(1, 17):
        rows = t * g_of(s); mt = A.mt_pass(rows)
        if A.vec3_ns(A.BL_of(mt), mt, variant, conv, A.MERGE_PACK * 100) >= A.ddr_block_ns(G, mt) // (2 if i8 else 1): return t, rows
    return None, None

# --------------------------------------------------------------- variant I: two 4-die instances (ALT-2) -----------------
POS4 = [(0, 1), (0, 0), (1, 1), (1, 0)]
LAYERS4 = {"dense": [30, 30, 30, 30], "moe": [7, 7, 7, 7]}
def inst_die_weights(s, pos, x, draft=True):
    """resident bytes on die pos of a 4-die instance when x (thousandths) of the candidate bytes (expert slabs / dense matrices) is int4."""
    n = LAYERS4[s["name"]][pos]
    if s["moe"]: w = n * (s["w_attn"] + s["w_experts"] - s["w_experts"] * x // 2000)
    else:        w = n * (s["w_layer"] - s["w_layer"] * x // 2000)
    if pos == 0: w += s["w_embed"]
    if pos == 3: w += s["w_head"]
    if draft and (not s["moe"]) and pos == 1: w += DRAFT["w"] + DRAFT["kv_window"]
    return w
def inst_die_kv(s, pos, L, B=1, i8=False):
    b = LAYERS4[s["name"]][pos] * s["kv_tok"] * L * B
    return b // 2 if i8 else b
def min_x(s, pos, L, B=1, i8=False, ort=O_RT):
    """smallest x with weights(x) + KV + ws + overhead <= 86 GB on die pos (weights(x) is non-increasing in x: an iff); None if x = 1000 fails."""
    room = DIE_MEM - ort - WS - inst_die_kv(s, pos, L, B, i8)
    if inst_die_weights(s, pos, 1000) > room: return None
    if inst_die_weights(s, pos, 0) <= room: return 0
    lo, hi = 0, 1000
    while lo < hi:
        mid = (lo + hi) // 2
        if inst_die_weights(s, pos, mid) <= room: hi = mid
        else: lo = mid + 1
    return lo
def harmonic(n): return sum(Fraction(1, r) for r in range(1, n + 1))
def cold_share(x, pop, E=256):
    """fraction of the streamed expert bytes that are int4: uniform routing streams the tier in proportion (x); under Zipf(1.0)
    popularity the coldest x of the experts carry the harmonic tail of the traffic (EMPIRICAL-class, H9)."""
    if pop == "uniform": return Fraction(x, 1000)
    nc = E * x // 1000
    return (harmonic(E) - harmonic(E - nc)) / harmonic(E) if nc else Fraction(0)
def inst_exchange(s, rows, lam):
    act = rows * s["d"] * 2; logits = rows * s["vocab"] * 4; ids = rows * 4
    bw = sum(tn(act, D2H[POS4[p][1]]) + tn(act, H2D[POS4[p + 1][1]]) for p in range(3))
    bw += tn(logits, D2H[POS4[3][1]]) + tn(ids, H2D[POS4[0][1]])
    return bw + 8 * lam, bw
def inst_step3(s, L, B=1, t=1, xs=None, hot="direct_ser", cold_ns=None, pop="uniform", **kw):
    """step of ONE 4-die instance: per-die int4 share xs (thousandths), hot tier = int8 expert regime (T_SLAB3 key), cold tier =
    int4 core-slab time (default: the measured 5.3 GB/s/core unpack), every other term exactly as step3 (chain d1,d0,d1,d0: 8 lambda)."""
    br = dict(BR3); br.update(kw)
    rows = B * t
    T_hot = T_SLAB3[hot]; T_cold = T_SLAB_W4 if cold_ns is None else cold_ns
    G, lam = G3[br["G"]], LAM3_BR[br["lam"]]
    a_seq = attn3_seq(s, L, t, G, br["var"], br["conv"], br["i8"])[0]
    R = R_GEMM if br["gemm"] == "direct" else R_GEMM_INT
    nl = s["nlaunch"] if br["mega"] is None else 1
    T = 0; W = 0
    for pos in range(4):
        n = LAYERS4[s["name"]][pos]; x = xs[pos]
        if s["moe"]:
            D = D_of(br["fam"], rows); share = cold_share(x, pop)
            w_l = tn(s["w_attn"], R) + 2 * F_MOE + int(s["slabs"] * D * (T_hot * (1 - share) + T_cold * share))
        else:
            w_l = int(Fraction(s["w_layer"] * 10 * (1000 - x), 1000 * R) + Fraction(s["w_layer"] * 10 * x, 1000 * R_W4_W8EQ))
        W += n * w_l
        T += n * (w_l + B * a_seq + nl * T_LAUNCH + quant_ns(s, rows, br["cq"]))
        if br["mega"] is not None: T += n * (SYNCS[s["name"]] * br["mega"] + 2 * tn(reduction_bytes(rows, s["d"]), R_GEMM))
    head = tn(s["w_head"], R); T += head + 2 * T_LAUNCH; W += head
    xch, xbw = inst_exchange(s, rows, lam); T += xch
    draft = draft3_ns(lam, br["launch"], br["cq"], br["mega"]) if t > 1 else 0; T += draft
    return T, dict(W=W, ATTN=s["nL"] * B * a_seq, LAUNCH=(s["nL"] * nl + 2) * T_LAUNCH, QUANT=s["nL"] * quant_ns(s, rows, br["cq"]), XCH=xch, DRAFT=draft)
def tps_card_inst(tok_milli, T, inst=2): return tok_milli * inst * 10 ** 9 // (4 * T)
def dx_per_gb(s):   # thousandths of x per GB of extra per-die overhead (the fit is linear in x)
    cand = LAYERS4[s["name"]][0] * (s["w_experts"] if s["moe"] else s["w_layer"])
    return ceil(GB * 2000, cand)

def pcs(n, d):      # signed percent change in tenths, n vs d
    return (n - d) * 1000 // d if n >= d else -((d - n) * 1000 // d)
def spc(x): return ("+" if x >= 0 else "-") + t10(abs(x)) + "%"

T_PIECE_W4_SER = tn(2 * KiB, R_W4V) + tn(4 * KiB, 2500) + tn(4 * KiB, 265) + 25 + 15   # unpack -> US->S1 -> loader -> MMA strictly serial per 2 KiB i4
T_SLAB_W4_SER  = 512 * T_PIECE_W4_SER                                                 # 305 152 ns per core-slab (ALT-2 'ser' branch)
R_W4_W8EQ_SER  = 8 * ((2 * 4 * KiB * 10 + T_PIECE_W4_SER) // (2 * T_PIECE_W4_SER))    # 55.2 W8-equivalent GB/s per die
def cold_tier(cold):
    """(int4 core-slab ns, dense W8-equivalent die rate in tenths) for the cold branch: 'ovl' = the measured 5.3 GB/s/core unpack
    overlapped with the loader/MMA chain, 'ser' = strictly serial per 2 KiB piece, or an explicit core-slab time in ns."""
    if cold == "ovl": return T_SLAB_W4, R_W4_W8EQ
    if cold == "ser": return T_SLAB_W4_SER, R_W4_W8EQ_SER
    return cold, 2 * 8 * (MiB * 10 // cold)
def inst_step3c(s, L, B=1, t=1, xs=None, hot="direct_ser", cold="ovl", pop="uniform", **kw):
    T_cold, R_cold = cold_tier(cold)
    saved = (globals()["T_SLAB_W4"], globals()["R_W4_W8EQ"])
    globals()["T_SLAB_W4"], globals()["R_W4_W8EQ"] = T_cold, R_cold
    try: return inst_step3(s, L, B, t, xs=xs, hot=hot, pop=pop, **kw)
    finally: globals()["T_SLAB_W4"], globals()["R_W4_W8EQ"] = saved

def main3():
    D, M = DENSE, MOE
    print("\n# ---- ROUND 3 (2026-11-05; HW-MAP e9349c8 measured, ALTERNATIVES dd5f84c variants): [R3-*] cells. The [F*] labels above are the round-2 cells, unchanged. ----")
    print(f"[R3-const] lambda {LAM3} ns per direction (measured 12.2 / 12.1 us; bounce {2*LAM3} ns vs measured 23.8-24.6 us; idle == under saturating D2D load); "
          f"T_launch {T_LAUNCH} ns = the kernel launch floor, a different quantity, unchanged; G (tenths) {G3} -- E21: 256 KiB = DESIGN-3's default page (primary), 64 KiB / 16 KiB shuffled, "
          f"174.6 = round 2's W8-kernel basis, gather3x = what-if; c_q {C_Q} ns per on-device A-quant pass x {Q_PASSES} per layer; integrated-chain rate {t10(R_GEMM_INT)}; "
          f"T_slab by expert regime {T_SLAB3} ns; int4 core-slab {T_SLAB_W4} ns ovl / {T_SLAB_W4_SER} ser ({t10(R_W4V)} GB/s/core measured); c_sync branches {C_SYNC_BR} ns")
    print("[R3-mem] section-1 memory tables, L_max, T_min_dies: UNCHANGED (no lambda, G, c_q or regime term enters the memory model); the instance variant's fit is [R3-inst-fit-*]")
    # ------------------------------------------------------------ per-layer terms
    for s in SHAPES:
        regs = ("anchor", "direct_ser", "direct_ovl", "pp") if s["moe"] else ("anchor",)
        print(f"[R3-layer-{s['name']}] weights per layer: " + ", ".join(f"{k} {gemm3_ns(s, 1, 'uniform', k)}" for k in regs)
              + f" ns; integrated-chain (135.5) {gemm3_ns(s, 1, 'uniform', 'anchor', 'integrated')} ns; quant per layer fixed {quant_ns(s, 1, 'fixed')} / prop rows 1, 4, 16: {quant_ns(s, 1, 'prop')}, {quant_ns(s, 4, 'prop')}, {quant_ns(s, 16, 'prop')} ns; "
              f"quant per token (fixed) {ms2(s['nL'] * quant_ns(s, 1, 'fixed'))} ms; launches per token {ms2(launch3_ns(s, 1, True, None))} ms, megakernel at c_sync 5 us {ms2(launch3_ns(s, 1, True, 5000))} ms (reductions {ms2(s['nL'] * 2 * tn(reduction_bytes(1, s['d']), R_GEMM))} ms)")
    for s in SHAPES:
        g = g_of(s)
        for lab, L in L_SET.items():
            Tp, bp, pp = attn3_seq(s, L, 1, 1692)
            cells = "; ".join(f"{gk}: {attn3_seq(s, L, 1, G3[gk])[0]} ({attn3_seq(s, L, 1, G3[gk])[1]})" for gk in ("p256k", "shuf64k", "shuf16k", "stream174", "gather3x"))
            Tl, bl_, pl = attn3_seq(s, L, 1, 1692, "lazy", "T"); Tc, bc, _ = attn3_seq(s, L, 1, 1692, "rowmax", "C")
            T4, b4, p4 = attn3_seq(s, L, 4, 1692); T4l, b4l, _ = attn3_seq(s, L, 4, 1692, "lazy", "T")
            Ti, bi, _ = attn3_seq(s, L, 1, 1692, i8=True); Til, bil, _ = attn3_seq(s, L, 1, 1692, "lazy", "T", i8=True)
            print(f"[R3-attn-{s['name']}-{lab}] t=1 rows={g} mt=1 nb={pp['nb']} per layer ns (binding): {cells}; chained corner {Tc} ({bc}); lazy {Tl} ({bl_}); fixed {pp['fixed']} / lazy {pl['fixed']}; "
                  f"round 2 stream {attn_parts(s, L, 1, 1, 1746, 4)[0]} | t=4 rows={4*g} mt={p4['mt']} block={A.BL_of(p4['mt'])} passes={p4['passes']}: rowmax {T4} ({b4}) lazy {T4l} ({b4l}) | KV-int8 t=1: rowmax {Ti} ({bi}) lazy {Til} ({bil})")
    # ------------------------------------------------------------ the step table
    print("\n[R3-step] primary round-3 branch: 256 KiB pages (169.2), chain as specified (throughput convention), lambda 12.2 us, launches serialised, MoE anchored serial regime, uniform routing, c_q fixed")
    print("| shape | L | config | feasible | T_step ms | W ms | ATTN ms | launch ms | quant ms | bounce ms | draft ms | tokens/step | tok/s/card | binding |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    R3ROWS = {}
    def row3(s, lab, L, cfg, B, t, tok_milli, **kw):
        T, p, ab = step3(s, L, B, t, **kw); i8 = kw.get("i8", False); fe = feasible(s, L, B, i8)
        print(f"| {s['name']} | {lab} | {cfg} | {'yes' if fe else 'NO'} | {ms2(T)} | {ms2(p['W'])} | {ms2(p['ATTN'])} | {ms2(p['LAUNCH'])} | {ms2(p['QUANT'])} | {ms2(p['XCH'])} | {ms2(p['DRAFT'])} | {t3(tok_milli)} | {t3(tps_card(tok_milli, T)) if fe else '-'} | {binding3(s, L, B, t, p, ab, i8)} |")
        R3ROWS[(s["name"], lab, cfg)] = (T, tok_milli, fe)
        return T
    for s in SHAPES:
        for lab, L in L_SET.items():
            row3(s, lab, L, "B=1 t=1", 1, 1, 1000)
            if lab == "1M" and not s["moe"]:
                row3(s, lab, L, "B=1 t=1 KV-i8", 1, 1, 1000, i8=True)
                row3(s, lab, L, "B=1 t=1 KV-i8 lazy", 1, 1, 1000, i8=True, var="lazy")
            row3(s, lab, L, "spec k=3 a=0.7", 1, 4, tau_milli(700))
            if not s["moe"]: row3(s, lab, L, "spec k=3 a=0.7 lazy", 1, 4, tau_milli(700), var="lazy")
            if lab == "1M" and not s["moe"]:
                row3(s, lab, L, "spec k=3 a=0.7 KV-i8", 1, 4, tau_milli(700), i8=True)
            row3(s, lab, L, "B=16 t=1", 16, 1, 16000)
    # moved cells: every round-2 step row -> its round-3 replacement
    print("\n[R3-moved] round-2 step cell -> round-3 primary cell (ms -> tok/s/card)")
    for s in SHAPES:
        for lab, L in L_SET.items():
            for cfg, B, t, tok, kw in (("B=1 t=1", 1, 1, 1000, {}), ("spec k=3 a=0.7", 1, 4, tau_milli(700), {}), ("B=16 t=1", 16, 1, 16000, {})) + (((("B=1 t=1 KV-i8", 1, 1, 1000, {"i8": True}), ("spec k=3 a=0.7 KV-i8", 1, 4, tau_milli(700), {"i8": True})) if (lab == "1M" and not s["moe"]) else ())):
                T2, _ = step(s, L, B, t, **kw); T3, _, _ = step3(s, L, B, t, **kw); fe = feasible(s, L, B, kw.get("i8", False))
                old = t3(tps_card(tok, T2)) if fe else "MEM"; new = t3(tps_card(tok, T3)) if fe else "MEM"
                print(f"[R3-moved-{s['name']}-{lab}-{cfg.replace(' ', '')}] {ms2(T2)} ms -> {old} ==> {ms2(T3)} ms -> {new}" + (f" ({spc(pcs(tps_card(tok, T3), tps_card(tok, T2)))})" if fe else ""))
    # ------------------------------------------------------------ branches at 32k, t = 1
    print("\n[R3-branch] L=32k, B=1, t=1: every branch toggled one at a time (ms -> tok/s/card)")
    for s in SHAPES:
        base = step3(s, 32768)[0]; cells = {"primary": base}
        toggles = [("G", "shuf64k"), ("G", "seq64k"), ("G", "shuf16k"), ("G", "stream174"), ("G", "gather3x"), ("var", "lazy"), ("conv", "C"), ("lam", "lo"), ("lam", "anchor91"), ("lam", "hi"),
                   ("launch", False), ("cq", None), ("cq", "prop"), ("gemm", "integrated")]
        if s["moe"]: toggles += [("regime", "direct_ser"), ("regime", "direct_ovl"), ("regime", "pp"), ("fam", "zipf15")]
        for k, v in toggles: cells[f"{k}={v}"] = step3(s, 32768, **{k: v})[0]
        for ck, cv in C_SYNC_BR.items(): cells[f"mega={ck}"] = step3(s, 32768, mega=cv)[0]
        print(f"[R3-branch-{s['name']}] " + " ; ".join(f"{k}: {ms2(T)} -> {t3(tps_card(1000, T))}" for k, T in cells.items()))
        lo = step3(s, 32768, G="shuf16k", conv="C", lam="hi", gemm="integrated", cq=None)[0]
        hi = step3(s, 32768, var="lazy", lam="lo", launch=False, cq=None, **({"regime": "direct_ovl"} if s["moe"] else {}))[0]
        print(f"[R3-branch-{s['name']}-bracket] pessimistic (16 KiB pages, chained latencies, lambda 500 us, integrated chain 135.5 with the quant pass folded in): {ms2(lo)} -> {t3(tps_card(1000, lo))} ({spc(pcs(tps_card(1000, lo), tps_card(1000, base)))}) ; "
              f"optimistic (lazy chain, lambda 10, launches pipelined, no quant pass{', direct_ovl experts' if s['moe'] else ''}): {ms2(hi)} -> {t3(tps_card(1000, hi))} ({spc(pcs(tps_card(1000, hi), tps_card(1000, base)))})")
    # ------------------------------------------------------------ MoE B = 16 by family
    for fam in ("uniform", "zipf10", "zipf15"):
        for lab in ("32k", "1M"):
            T, p, _ = step3(M, L_SET[lab], 16, 1, fam=fam); Td, _, _ = step3(M, L_SET[lab], 16, 1, fam=fam, regime="direct_ser")
            print(f"[R3-B16-{fam}-{lab}] D={D_of(fam, 16)}; T_step {ms2(T)} ms (W {ms2(p['W'])}, ATTN {ms2(p['ATTN'])}) -> {t3(tps_card(16000, T))} tok/s/card (direct_ser {t3(tps_card(16000, Td))}); feasible {feasible(M, L_SET[lab], 16)}")
    # ------------------------------------------------------------ regime map and crossovers
    print("\n[R3-regime] binding term per (shape, L, rows) on the primary branch (share of the step; attention share):")
    for s in SHAPES:
        for lab, L in L_SET.items():
            cells = []
            for (B, t, name) in ((1, 1, "r1"), (1, 4, "t4"), (16, 1, "B16")):
                T, p, ab = step3(s, L, B, t); b = binding3(s, L, B, t, p, ab)
                share = pct(p[b.split(":")[0]], T) if b != "MEM" else 0
                cells.append(f"{name}:{b}({t10(share)}%; attn {t10(pct(p['ATTN'], T))}%)")
            print(f"      {s['name']} {lab}: " + " ".join(cells))
    for s in SHAPES:
        regs = ("anchor", "direct_ser", "pp") if s["moe"] else ("anchor",)
        for gk in ("p256k", "shuf64k", "shuf16k", "stream174", "gather3x"):
            G = G3[gk]
            print(f"[R3-Lkv-{s['name']}-{gk}] L*_KV (smallest L with the t=1 attention step >= the per-layer weight time; exact over every L): "
                  + "; ".join(f"{r}: {Lstar_kv3(s, G, r)}" for r in regs) + f"; lazy chain (anchor): {Lstar_kv3(s, G, 'anchor', 'lazy')}"
                  + (f"; KV-int8 (anchor): rowmax {Lstar_kv3(s, G, 'anchor', i8=True)} / lazy {Lstar_kv3(s, G, 'anchor', 'lazy', i8=True)}" if not s["moe"] else ""))
        for lab, L in L_SET.items():
            for reg in regs:
                Tw = gemm3_ns(s, 1, "uniform", reg)
                verd = "; ".join(f"{gk}: {'ATTN' if attn3_seq(s, L, 1, G3[gk])[0] >= Tw else 'W'} by {abs(attn3_seq(s, L, 1, G3[gk])[0] - Tw) // 1000} us ({t10(pct(abs(attn3_seq(s, L, 1, G3[gk])[0] - Tw), Tw))}%)" for gk in ("shuf16k", "shuf64k", "seq64k", "p256k", "stream174"))
                print(f"[R3-Gstar-{s['name']}-{lab}-{reg}] t=1 attention-bound iff G <= {Gstar3(s, L, reg)} tenths: {verd}")
    for s in SHAPES:
        for var, conv in (("rowmax", "T"), ("rowmax", "C"), ("lazy", "T"), ("lazy", "C")):
            t_, r_ = tstar3(s, var, conv)
            ti, ri = tstar3(s, var, conv, i8=True)
            print(f"[R3-tstar-{s['name']}-{var}-{conv}] softmax binds (vector >= KV per block, L cancels) from t = {t_} (rows {r_}, g = {g_of(s)}); KV-int8: t = {ti} (rows {ri}); round 2 said t* = 16 native / 4 poly (dense), 64 / 16 (MoE)")
    # ------------------------------------------------------------ exchange, T8, what-ifs
    for s in SHAPES:
        for rows in (1, 4, 16):
            tot, bw, nlat = exchange(s, rows, LAM3)
            print(f"[R3-xch-{s['name']}-rows{rows}] T_x = {bw} + 16 x {LAM3} = {tot} ns = {usR(tot)} us (round 2 at 91 us: {usR(exchange(s, rows, 91_000)[0])}); lambda bracket lo/hi: {usR(exchange(s, rows, 10_000)[0])} / {usR(exchange(s, rows, 500_000)[0])} us")
        T0, p0, _ = step3(s, 32768); bw = exchange(s, 1, 0)[1]; rest = T0 - p0["XCH"]
        lam10 = ceil(rest - 9 * bw, 144); lam50 = ceil(rest - bw, 16)
        print(f"[R3-T8-{s['name']}] bounce >= 10 % of the 32k step iff lambda >= {usR(lam10)} us ({lam10} ns); 50 % iff >= {usR(lam50)} us; the measured 12.2 us is {lam10 // LAM3}x below the 10 % line; bounce share at 12.2 us = {pctH(p0['XCH'], T0) / 100:.2f} % (round 2 at 91 us: {t10(pct(step(s, 32768)[1]['XCH'], step(s, 32768)[0]))} %)")
        print(f"[R3-whatif-{s['name']}-p2p] host-bounce total {usR(p0['XCH'])} us = {pctH(p0['XCH'], T0) / 100:.2f} % of the step: a P2P link at ANY rate saves at most that (bound)")
        Tts, pts = step_tsplit3(s, 32768)
        print(f"[R3-whatif-{s['name']}-tsplit] tensor-split over 8 dies: {ms2(Tts)} ms = W/8 {ms2(pts['W/8'])} + ATTN/8 {ms2(pts['ATTN/8'])} + lm_head/8 {ms2(tn(s['w_head'], 8 * R_GEMM))} + launch {ms2(pts['LAUNCH'])} + quant {ms2(pts['QUANT'])} + 2 x {s['nL']} host reductions {ms2(pts['REDUCE'])} ({usR(t_reduce(LAM3, 1, s['d']))} us each; round 2: {usR(t_reduce(91_000, 1, s['d']))}) "
              f"-> {t3(tps_card(1000, Tts))} tok/s/card ({t10(T0 * 10 // Tts)}x; round 2 {t3(tps_card(1000, step_tensor_split(s, 32768)[0]))})")
        blocks = [die_block3(s, p, 32768) for p in range(DIES)]; mx = max(blocks); sm = sum(blocks)
        print(f"[R3-whatif-{s['name']}-pipe] Pi=8 per-die blocks ms {[ms2(b) for b in blocks]}; fleet tok/s = 1/max = {t3(tps_fleet(1000, mx))} -> {t3(tps_card(1000, mx))} per card = {t10(T0 * 10 // mx)}x the chain; "
              f"sum of blocks + lambda = {sm + LAM3} vs step {T0} ({'exact' if sm + LAM3 == T0 else 'MISMATCH'}); loss vs a balanced split {t10(pct(8 * mx - sm, 8 * mx))} %")
        kvmove = s["layers"][0] * s["kv_tok"] * 131072
        print(f"[R3-whatif-{s['name']}-d2d] per-token D2D traffic 0 B; one die's KV at 128k = {gb1(kvmove)} GB: {msR(tn(kvmove, R_D2D))} ms at 10.7 / {msR(tn(kvmove, 500))} ms at 50 (unchanged)")
    # ------------------------------------------------------------ megakernel (ALT-3) on the round-3 step
    for s in SHAPES:
        T0 = step3(s, 32768)[0]; saved = (s["nlaunch"] - 1) * T_LAUNCH; red = 2 * tn(reduction_bytes(1, s["d"]), R_GEMM)
        thr = (saved - red) // SYNCS[s["name"]]
        cells = " ; ".join(f"c_sync {ck}: {ms2(step3(s, 32768, mega=cv)[0])} -> {t3(tps_card(1000, step3(s, 32768, mega=cv)[0]))} ({spc(pcs(tps_card(1000, step3(s, 32768, mega=cv)[0]), tps_card(1000, T0)))})" for ck, cv in C_SYNC_BR.items())
        print(f"[R3-mega-{s['name']}] one launch per layer saves {ms2(s['nL'] * saved)} ms per token, the {2 * s['nL']} DDR reductions add {ms2(s['nL'] * red)} ms, {s['nL'] * SYNCS[s['name']]} flag rounds per token; pays iff c_sync <= {thr} ns = {usR(thr)} us (iff; E31 measures it); {cells}")
        if s["moe"]:
            Tc = step3(s, 32768, regime="direct_ser", mega=5000)[0]
            print(f"[R3-mega-moe-direct] direct_ser experts + megakernel (c_sync 5 us): {ms2(Tc)} ms -> {t3(tps_card(1000, Tc))} ({spc(pcs(tps_card(1000, Tc), tps_card(1000, T0)))})")
    # ------------------------------------------------------------ variant I: two 4-die instances (ALT-2) on the round-3 step
    print("\n[R3-inst] variant I: two 4-die instances (c0.d1 -> c0.d0 -> c1.d1 -> c1.d0 and the mirror), the minimal int4 share x per die that closes the fit")
    for s in SHAPES:
        for lab, L in L_SET.items():
            for i8 in ((False,) if s["moe"] else (False, True)):
                if i8 and lab != "1M": continue
                xs = [min_x(s, p, L, 1, i8) for p in range(4)]
                tag = f"{s['name']}-{lab}" + ("-kvi8" if i8 else "")
                if any(x is None for x in xs):
                    print(f"[R3-inst-fit-{tag}] infeasible even at x = 1000 (all candidate bytes int4) on dies {[p for p, x in enumerate(xs) if x is None]}: KV alone {gb1(inst_die_kv(s, 0, L, 1, i8))} GB per die"); continue
                tots = [inst_die_weights(s, p, xs[p]) + inst_die_kv(s, p, L, 1, i8) + WS + O_RT for p in range(4)]
                rows = " | ".join(f"pos{p} c{POS4[p][0]}.d{POS4[p][1]}: x={xs[p]} w={gb1(inst_die_weights(s, p, xs[p]))} kv={gb1(inst_die_kv(s, p, L, 1, i8))} total={gb1(tots[p])}" for p in range(4))
                margin = min(DIE_MEM - tt for tt in tots); xs1 = [min_x(s, p, L, 1, i8, O_RT + GB) for p in range(4)]; xs3 = [min_x(s, p, L, 1, i8, O_RT + 3 * GB) for p in range(4)]
                print(f"[R3-inst-fit-{tag}] {rows} (limit 86.0; overhead 2 GiB + 64 MiB = {gb1(WS + O_RT)} GB assumed, H8/H11); worst-die margin {margin} B = {gb1(margin)} GB; "
                      f"dx = {dx_per_gb(s)} thousandths per GB of extra overhead; x at +1 GB {xs1}, at +3 GB {xs3}")
                T0 = step3(s, L, i8=i8)[0] if feasible(s, L, 1, i8) else None
                variants = (("direct_ser", "ovl", "uniform"), ("direct_ser", "ser", "uniform"), ("anchor", "ovl", "uniform"), ("direct_ovl", "ovl", "uniform"), ("direct_ser", "ovl", "zipf10")) if s["moe"] else (("direct_ser", "ovl", "uniform"), ("direct_ser", "ser", "uniform"))
                for hot, cold, pop in variants:
                    T, parts = inst_step3c(s, L, xs=xs, hot=hot, cold=cold, pop=pop, i8=i8)
                    cmp = f" vs one 8-die instance {t3(tps_card(1000, T0))} ({spc(pcs(tps_card_inst(1000, T), tps_card(1000, T0)))})" if T0 else " (one 8-die instance: MEM)"
                    print(f"[R3-inst-{tag}-{hot}-{cold}-{pop}] instance step {ms2(T)} ms (W {ms2(parts['W'])}, ATTN {ms2(parts['ATTN'])}, launch {ms2(parts['LAUNCH'])}, quant {ms2(parts['QUANT'])}, xch {usR(parts['XCH'])} us) -> 2 instances {t3(tps_card_inst(1000, T))} tok/s/card{cmp}")
    xs = [min_x(D, p, 32768) for p in range(4)]
    for var in ("rowmax", "lazy"):
        T, parts = inst_step3c(D, 32768, 1, 4, xs=xs, var=var); T0 = step3(D, 32768, 1, 4, var=var)[0]
        print(f"[R3-inst-dense-32k-spec-{var}] spec k=3 a=0.7 ({var} chain): one instance {ms2(T0)} -> {t3(tps_card(tau_milli(700), T0))}; 2 instances {ms2(T)} -> {t3(tps_card_inst(tau_milli(700), T))} ({spc(pcs(tps_card_inst(tau_milli(700), T), tps_card(tau_milli(700), T0)))})")
    xs = [min_x(M, p, 32768, 16) for p in range(4)]
    T, parts = inst_step3c(M, 32768, 16, 1, xs=xs); T0 = step3(M, 32768, 16, 1)[0]
    print(f"[R3-inst-moe-32k-B16] B=16 uniform: x {xs}; one instance {ms2(T0)} -> {t3(tps_card(16000, T0))}; 2 instances {ms2(T)} -> {t3(tps_card_inst(16000, T))} ({spc(pcs(tps_card_inst(16000, T), tps_card(16000, T0)))})")
    xs = [min_x(M, p, 32768) for p in range(4)]; T0 = step3(M, 32768)[0]
    for r in (53, 40, 30, 20, 10):
        T, _ = inst_step3c(M, 32768, xs=xs, cold=tn(MiB, r))
        print(f"[R3-inst-sens-w4rate-{r}] int4 unpack at {t10(r)} GB/s/core: MoE 32k 2 instances {ms2(T)} ms -> {t3(tps_card_inst(1000, T))} tok/s/card (one instance {t3(tps_card(1000, T0))})")
    lo, hi = 0, 50_000_000
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if tps_card_inst(1000, inst_step3c(M, 32768, xs=xs, cold=mid)[0]) > tps_card(1000, T0): lo = mid
        else: hi = mid - 1
    print(f"[R3-inst-breakeven-moe-32k] two instances beat one (MoE 32k, uniform, direct_ser hot tier) for every int4 core-slab time <= {lo} ns = {t10(2 * MiB * 10 // (2 * lo) if lo else 0)} GB/s/core of int4 or faster; measured 5.3 is {t10(lo * 10 // T_SLAB_W4)}x inside; the ser branch ({T_SLAB_W4_SER} ns) {'passes' if T_SLAB_W4_SER <= lo else 'FAILS'}")
    Tall, _ = inst_step3c(M, 32768, xs=[1000] * 4); Tmin, _ = inst_step3c(M, 32768, xs=xs)
    print(f"[R3-inst-allw4-moe-32k] all experts int4 (x = 1000): {ms2(Tall)} ms -> {t3(tps_card_inst(1000, Tall))}; minimal x {xs}: {ms2(Tmin)} -> {t3(tps_card_inst(1000, Tmin))} (the tier is the price of the fit, the second instance is the gain)")
    for s in SHAPES:
        xs = [min_x(s, p, 32768) for p in range(4)]; T0 = step3(s, 32768)[0]
        Tm, _ = inst_step3c(s, 32768, xs=xs, mega=5000); Tmo, _ = inst_step3c(s, 32768, xs=xs, mega=5000, hot="direct_ovl")
        mx = max(die_block3(s, p, 32768) for p in range(DIES))
        print(f"[R3-inst-combo-{s['name']}-32k] instances + megakernel (c_sync 5 us): {ms2(Tm)} -> {t3(tps_card_inst(1000, Tm))} ({spc(pcs(tps_card_inst(1000, Tm), tps_card(1000, T0)))}); + direct_ovl hot tier {t3(tps_card_inst(1000, Tmo))}; "
              f"Pi=8 pipelining of ONE 8-die instance (H4) would give {t3(tps_card(1000, mx))} = {t10(tps_card(1000, mx) * 10 // tps_card_inst(1000, Tmin if s['moe'] else inst_step3c(s, 32768, xs=xs)[0]))}x the two-instance cell: instances are the Pi=1 substitute and must be undone if H4 passes")
    # ------------------------------------------------------------ draft + spec decode
    print(f"\n[R3-draft] per draft token: weights {usR(tn(DRAFT['w'], R_GEMM))} + window KV {usR(tn(DRAFT['kv_window'], R_GEMM))} + launches {usR(121 * T_LAUNCH)} + A-quant {usR(24 * Q_PASSES * C_Q)} + logits {usR(tn(128256 * 4, D2H[0]))} + 2 lambda {usR(2 * LAM3)} us = {usR(draft3_ns(LAM3) // 3)} us "
          f"(round 2: 18 092); verify step k=3 {ms2(draft3_ns(LAM3))} ms (round 2 54.27); launches pipelined {ms2(draft3_ns(LAM3, False))}; megakernel 24 launches at c_sync 5 us {ms2(draft3_ns(LAM3, True, 'fixed', 5000))}; no quant pass {ms2(draft3_ns(LAM3, True, None))}; launch share {t10(pct(121 * T_LAUNCH, draft3_ns(LAM3) // 3))} %")
    print("[R3-tau] tokens per verify step tau(alpha,k) unchanged: " + ", ".join(f"a={a}: k=3 {t3(tau_milli(a, 3))}, k=7 {t3(tau_milli(a, 7))}" for a in (500, 700, 900)))
    for s in SHAPES:
        for var in (("rowmax", "lazy") if not s["moe"] else ("rowmax",)):
            T1 = step3(s, 32768, var=var)[0]
            for ak, a in ALPHA.items():
                best = None
                for k in range(1, 8):
                    T = step3(s, 32768, 1, k + 1, var=var)[0] - draft3_ns(LAM3) + draft3_ns(LAM3, k=k)
                    r = tps_card(tau_milli(a, k), T)
                    if best is None or r > best[1]: best = (k, r, T)
                T4 = step3(s, 32768, 1, 4, var=var)[0]
                print(f"[R3-spec-{s['name']}-{var}-{ak}] k=3: {ms2(T4)} ms -> {t3(tps_card(tau_milli(a), T4))} tok/s/card = {t3(tau_milli(a) * T1 // T4)}x of t=1 ({t3(tps_card(1000, T1))}); best k = {best[0]} ({ms2(best[2])} ms) -> {t3(best[1])}")
            if not s["moe"]:
                T4 = step3(s, 32768, 1, 4, var=var)[0]; a = 0
                while tau_milli(a, 3) * T1 <= 1000 * T4: a += 1
                print(f"[R3-spec-dense-breakeven-{var}] spec k=3 on the {var} chain is a gain for every alpha >= {t3(a)} (tau > T4/T1 = {T4 * 10000 // T1 / 10000}); round 2: 0.024 at T4/T1 = 1.0230")
    for fam in ("uniform", "zipf10", "zipf15"):
        for reg in ("anchor", "direct_ser"):
            T1r = step3(M, 32768, regime=reg)[0]; T4, p4, _ = step3(M, 32768, 1, 4, fam=fam, regime=reg); a = 0
            while tau_milli(a, 3) * T1r < 1000 * T4: a += 1
            print(f"[R3-spec-moe-{fam}-{reg}] D(4)={D_of(fam, 4)}: step {ms2(T4)} ms (W {ms2(p4['W'])}, ATTN {ms2(p4['ATTN'])}); a=0.7 -> {t3(tps_card(tau_milli(700), T4))} vs t=1 {t3(tps_card(1000, T1r))}; "
                  f"loss iff alpha <= {t3(a - 1)} (tau(a,3) < T4/T1 = {T4 * 10000 // T1r / 10000}); alpha {t3(a)} gives {t3(tps_card(tau_milli(a, 3), T4))} (round 2: 0.864 / 0.746 / 0.646)")
    T1m = step3(M, 32768)[0]; E1 = M["nL"] * (gemm3_ns(M, 1, "uniform", "anchor") - tn(M["w_attn"], R_GEMM) - 2 * F_MOE)
    print(f"[R3-spec-moe-mechanism] expert stream at t=1 E1 = {ms2(E1)} ms = {t10(pct(E1, T1m))} % of T1; T4 >= 4 E1 + (T1 - E1) = {ms2(3 * E1 + T1m)} ms -> any tau < {t3(1000 + 3 * E1 * 1000 // T1m)} is a loss before the draft is counted (round 2: 2.852)")
    # ------------------------------------------------------------ rollout
    for s in SHAPES:
        for ncard in (1, 2, 4):
            npos = 2 * ncard
            print(f"[R3-rollout-{s['name']}-{ncard}card] " + "; ".join(f"{lab}: {ms2(sum(die_block3(s, p, L) for p in range(npos)))} ms" for lab, L in (("4k", 4096), ("32k", 32768), ("128k", 131072))) + f"; per-die blocks at 32k {[ms2(die_block3(s, p, 32768)) for p in range(npos)]}")
        st1 = sum(die_block3(s, p, 32768) for p in range(2)); act = s["d"] * 2
        extra = tn(s["w_head"], R_GEMM) + 2 * T_LAUNCH + 4 * LAM3 + 3 * tn(act, H2D[1]) + tn(s["vocab"] * 4, D2H[0]) - tn(act, D2H[0])
        print(f"[R3-rollout-{s['name']}-identity] 4 x stage-1 ({ms2(st1)} ms) + T_head + 2 T_launch + 4 lambda + 3 hops@13.9 - 1 hop@27.3 + logits ({ms2(extra)} ms) = {4 * st1 + extra} ns vs the direct step {step3(s, 32768)[0]} ({'exact' if 4 * st1 + extra == step3(s, 32768)[0] else 'MISMATCH'})")
        xs = [min_x(s, p, 32768) for p in range(4)]
        print(f"[R3-rollout-{s['name']}-stage2-instance] the 2-card stage IS one instance of variant I: with x = {xs} it serves 32k at {ms2(inst_step3c(s, 32768, xs=xs)[0])} ms per token on its own ({t3(tps_card_inst(1000, inst_step3c(s, 32768, xs=xs)[0], 1) * 2)} tok/s per 2 cards); H10 runs at stage 3")
    # ------------------------------------------------------------ ladder expectations
    print(f"\n[R3-ladder-H1] link time T(n) = lambda + n*10/R with the MEASURED intercept {LAM3} ns: 4 KiB H2D d0 {LAM3 + tn(4 * KiB, H2D[0])} / d1 {LAM3 + tn(4 * KiB, H2D[1])} ns; 64 KiB {LAM3 + tn(64 * KiB, H2D[0])} / {LAM3 + tn(64 * KiB, H2D[1])}; 64 MiB {LAM3 + tn(64 * MiB, H2D[0])} / {LAM3 + tn(64 * MiB, H2D[1])} ns -- H1 now re-verifies, it no longer decides")
    print(f"[R3-ladder-H3] MEASURED: the 4 KiB bounce is unchanged under die-0 saturating D2D load; the C/R queueing bound (64 KiB {usR(tn(64 * KiB, H2D[1]))} us, 1 MiB {usR(tn(MiB, H2D[1]))}, 16 MiB {usR(tn(16 * MiB, H2D[1]))} on the 13.9 link) stays the rule for bulk streams chunked above 4 KiB")
    T0 = step3(M, 32768)[0]; xs = [min_x(M, p, 32768) for p in range(4)]; Ti = inst_step3c(M, 32768, xs=xs)[0]
    print(f"[R3-ladder-H10] two instances concurrent: expected fleet throughput {t3(tps_card_inst(1000, Ti) * 4)} tok/s = {t10(tps_card_inst(1000, Ti) * 10 // tps_card(1000, T0))}x the single instance's {t3(tps_card(1000, T0) * 4)} (MoE 32k); all four cards at the loaded {P_SUSTAIN} W class; serialised instances show 1.0x and two cards at a time")
    print(f"[R3-ladder-H11] free memory after loading the MoE instance at x = {xs}: expected >= KV(32k) {gb1(inst_die_kv(M, 0, 32768))} GB + 64 MiB + margin {gb1(min(DIE_MEM - (inst_die_weights(M, p, xs[p]) + inst_die_kv(M, p, 32768) + WS + O_RT) for p in range(4)))} GB; each GB short raises x by {dx_per_gb(M)} thousandths")
    Tf, Tp = step3(D, 32768)[0], step3(D, 32768, cq="prop")[0]; Tfm, Tpm = step3(M, 32768)[0], step3(M, 32768, cq="prop")[0]
    print(f"[R3-ladder-E38] A-quant pass at K = 16 384 / 53 248 (dense) and rows 4 / 16: fixed reading {C_Q} ns per pass vs proportional {2 * C_Q} / {7 * C_Q} ns; the 32k step moves {ms2(Tp - Tf)} ms dense ({t3(tps_card(1000, Tf))} -> {t3(tps_card(1000, Tp))}) and {ms2(Tpm - Tfm)} ms MoE ({t3(tps_card(1000, Tfm))} -> {t3(tps_card(1000, Tpm))}) between the readings")
    # ------------------------------------------------------------ risk numbers
    for s in SHAPES:
        T0, p0, _ = step3(s, 32768); Ti = step3(s, 32768, gemm="integrated", cq=None)[0]
        print(f"[R3-risk-{s['name']}-integrated] every weight stream at the integrated production chain's 135.5 (quant pass folded in): {ms2(Ti)} ms -> {t3(tps_card(1000, Ti))} ({spc(pcs(tps_card(1000, Ti), tps_card(1000, T0)))})")
    T0, p0, _ = step3(D, 32768); Ts = T0 - p0["W"] + p0["W"] * R_GEMM // R_GEMM_SER
    print(f"[R3-risk-dense-serial] dense 32k if the kernel falls back to the serial regime (138.9): {ms2(Ts)} ms -> {t3(tps_card(1000, Ts))}")
    for gk in ("p256k", "shuf64k", "shuf16k"):
        T, p, ab = step3(M, 131072, G=gk); Td, pd, abd = step3(M, 131072, G=gk, regime="direct_ser")
        print(f"[R3-risk-moe-128k-{gk}] MoE 128k at {gk}: {ms2(T)} ms -> {t3(tps_card(1000, T))} binding {binding3(M, 131072, 1, 1, p, ab)} (W {ms2(p['W'])} vs ATTN {ms2(p['ATTN'])}); direct_ser experts {ms2(Td)} -> {t3(tps_card(1000, Td))} binding {binding3(M, 131072, 1, 1, pd, abd)}")
    Tg = step3(M, 1048576, G="gather3x")[0]; T1m = step3(M, 1048576)[0]
    print(f"[R3-risk-moe-1M] MoE 1M: 256 KiB pages {ms2(T1m)} ms -> {t3(tps_card(1000, T1m))}; 64 KiB {t3(tps_card(1000, step3(M, 1048576, G='shuf64k')[0]))}; 16 KiB {t3(tps_card(1000, step3(M, 1048576, G='shuf16k')[0]))}; gather3x what-if {ms2(Tg)} -> {t3(tps_card(1000, Tg))} ({t10(tps_card(1000, T1m) * 10 // tps_card(1000, Tg))}x); KV-int8 rowmax {t3(tps_card(1000, step3(M, 1048576, i8=True)[0]))} / lazy {t3(tps_card(1000, step3(M, 1048576, i8=True, var='lazy')[0]))}")
    Ti8, Ti8l = step3(D, 1048576, i8=True)[0], step3(D, 1048576, i8=True, var="lazy")[0]
    print(f"[R3-risk-dense-1M-kvi8] dense 1M KV-int8: rowmax chain {ms2(Ti8)} ms -> {t3(tps_card(1000, Ti8))} (attention vector-bound: {ms2(step3(D, 1048576, i8=True)[1]['ATTN'])} ms of attention vs f16 KV's {ms2(step3(D, 1048576)[1]['ATTN'])}); lazy chain {ms2(Ti8l)} -> {t3(tps_card(1000, Ti8l))} (round 2: 3746.00 -> 0.066)")
    print(f"[R3-risk-rows] B*t <= 16 unchanged; dense verify batches are softmax-bound from t = {tstar3(D)[0]} (rows {tstar3(D)[1]}) on the chain as specified, t = {tstar3(D, 'lazy', 'T')[0]} on the lazy chain; MoE from t = {tstar3(M)[0]} / {tstar3(M, 'lazy', 'T')[0]}")
    print(f"[R3-power] unchanged: Pi=1 one die streams at a time; two instances = two cards at {P_SUSTAIN} W; Pi=8 four cards at {P_SUSTAIN} < {P_TDP} W")
    # ------------------------------------------------------------ headline and decision table
    hd = {}
    for s in SHAPES:
        T0 = step3(s, 32768)[0]; xs = [min_x(s, p, 32768) for p in range(4)]
        hd[s["name"]] = dict(primary=tps_card(1000, T0),
                             direct=tps_card(1000, step3(s, 32768, regime="direct_ser")[0]) if s["moe"] else None,
                             mega=tps_card(1000, step3(s, 32768, mega=5000)[0]),
                             direct_mega=tps_card(1000, step3(s, 32768, regime="direct_ser", mega=5000)[0]) if s["moe"] else None,
                             inst=tps_card_inst(1000, inst_step3c(s, 32768, xs=xs)[0]),
                             inst_anchor=tps_card_inst(1000, inst_step3c(s, 32768, xs=xs, hot="anchor")[0]) if s["moe"] else None,
                             inst_mega=tps_card_inst(1000, inst_step3c(s, 32768, xs=xs, mega=5000)[0]),
                             pipe=tps_card(1000, max(die_block3(s, p, 32768) for p in range(DIES))),
                             spec=tps_card(tau_milli(700), step3(s, 32768, 1, 4)[0]), spec_lazy=tps_card(tau_milli(700), step3(s, 32768, 1, 4, var="lazy")[0]),
                             b16=tps_card(16000, step3(s, 32768, 16, 1)[0]))
    print("\n[R3-headline] L=32k tok/s/card (primary round-3 branch): " + " ; ".join(f"{n} t=1 {t3(h['primary'])}, spec(a=0.7,k=3) {t3(h['spec'])} (lazy chain {t3(h['spec_lazy'])}), B=16 {t3(h['b16'])}" for n, h in hd.items()))
    print("[R3-decision] per-regime decision table at 32k, t=1 (tok/s/card dense / MoE; gate; what to build):")
    rows = [("primary: one 8-die instance, anchored MoE kernel, measured lambda/G/c_q", "none (today)", hd["dense"]["primary"], hd["moe"]["primary"]),
            ("MoE expert kernel on the direct path (ALT-1, serialised A lift)", "E29 (kernel probe)", hd["dense"]["primary"], hd["moe"]["direct"]),
            ("per-layer megakernel, c_sync = 5 us (ALT-3)", "E31/E32 (c_sync <= the iff line)", hd["dense"]["mega"], hd["moe"]["mega"]),
            ("direct path + megakernel", "E29 + E31", hd["dense"]["mega"], hd["moe"]["direct_mega"]),
            ("two 4-die instances, minimal int4 tier, direct_ser hot tier (ALT-2)", "H10 (host-only) + H11 fit", hd["dense"]["inst"], hd["moe"]["inst"]),
            ("two instances with the anchored expert kernel (no E29)", "H10", hd["dense"]["inst"], hd["moe"]["inst_anchor"]),
            ("two instances + megakernel", "H10 + E31", hd["dense"]["inst_mega"], hd["moe"]["inst_mega"]),
            ("Pi=8 sequence pipelining of one 8-die instance (runtime capability)", "H4", hd["dense"]["pipe"], hd["moe"]["pipe"])]
    for name, gate, dd, mm in rows:
        print(f"      {name} | gate {gate} | dense {t3(dd)} ({spc(pcs(dd, hd['dense']['primary']))}) | MoE {t3(mm)} ({spc(pcs(mm, hd['moe']['primary']))})")

if __name__ == "__main__":
    main(); main3()
