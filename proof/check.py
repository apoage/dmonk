#!/usr/bin/env python3
"""proof/check.py -- PROMPT-7 challenge round: INDEPENDENT re-derivations of load-bearing cells ([CHK-*] labels).

Rules of this file (they are what makes it a check and not a transcript):
  * it imports NOTHING from model.py / moe.py / attn.py / fleet.py / alt.py -- every quantity is rebuilt from the
    HW-MAP row it traces to, in this file's own formulation (whole-stream / closed forms where the corpus models
    go per block or per piece), so an agreement is two routes landing on one number;
  * every constant is tagged [M] measured (HW-MAP row), [D] derived here, [A] assumption, or [C] a corpus-derived
    number taken as an INPUT of the check (named, so the dependence is visible);
  * `corpus=` is the number the corpus prints; AGREE / DIFF is this file's verdict on it.
proof/check.lean (namespace Chk) fixes the same numbers as theorems. Run: python3 -I proof/check.py
"""
from fractions import Fraction as Fr

KiB, MiB, GiB, GB = 1024, 1 << 20, 1 << 30, 10 ** 9
def fl(x): return int(x // 1)                       # floor of a Fraction / int
def tn(b, r10): return b * 10 // r10                # ns for b bytes at r10 tenths of GB/s (floor)
def verdict(mine, corpus): return "AGREE" if mine == corpus else f"DIFF ({mine - corpus:+d})"
def r1(n, d): return (2 * n * 10 + d) // (2 * d) / 10        # n/d to one decimal, round half up
def r2(n, d): return (2 * n * 100 + d) // (2 * d) / 100      # two decimals

# ----------------------------------------------------------------------------- HW-MAP inputs
R_GEMM   = 1746        # [M] full W8 decode kernel, GB/s x10 (data-movement table)
R_M0     = 1658        # [M] expert-GEMM full dispatch M0, t = 1
R_M0_T4  = 1702        # [M] the same at t >= 4 (floor of 170.2-172.8)
R_W4     = 53          # [M] vector i4->f16 unpack, GB/s x10 PER CORE of int4 bytes
LAM      = 12_200      # [M] host bounce per direction, ns
T_LAUNCH = 91_000      # [M] launch + queue floor, ns (the conservative primary)
T_LAUNCH_REAL = 36_000 # [D by the corpus from M rows] realized per-launch bound
C_Q      = 43_700      # [M] on-device f16->i8 quantization pass, ns
H2D = {0: 276, 1: 139}; D2H = {0: 273, 1: 190}      # [M] host link, GB/s x10
DIE_MEM  = 86 * GB     # [M] usable DDR per die
ORT, WS  = 2 * GiB, 64 * MiB                        # [A] runtime overhead / workspace per die (H8, H11: UNMEASURED)
DFR      = {32768: 945_500, 131072: 3_618_800, 1 << 20: 28_694_000}   # [M] deferred-guard trip-free cells, ns per layer
LEG32    = 1_514_900   # [M] legacy scan cell, session 5, 32k t = 1
CANON32  = 1_818_100   # [M] adversarial canonical cell (retries ~100 % of steps)
TAU      = (Fr(80, 1000), Fr(55, 1000))             # [M] retry share of launches, cap 3072 / 61440
T_SER    = 122_979     # [C] DESIGN-2's DERIVED serial slab time (moe.lean T_piece_expert) -- never a measured kernel
T_PP     = 97_015      # [C] DESIGN-2's DERIVED ping-pong slab time
MERGE    = (8_313, 32_614)                          # [C] erratum-19 cold merge per int4 core-slab (ALTERNATIVES [PA-cold-merge])
FIX3     = 18_820      # [C] round-3 rowmax-T attention fixed cost per step (attn.py)
FIX4     = 19_328      # [C] round-4 lazy-T attention fixed cost per step (attn.py)

# ----------------------------------------------------------------------------- A. shapes, minimum dies
def dense_layer(d=16384, ffn=53248, hkv=8, dh=128): return d * (d + 2 * hkv * dh) + d * d + 3 * d * ffn
D_LAYER  = dense_layer()
D_EMBED  = 16384 * 128256
D_TOTAL  = 120 * D_LAYER + 2 * D_EMBED
M_ATTN   = 4096 * (4096 + 2 * 8 * 128) + 4096 * 4096
M_EXP    = 256 * 3 * 4096 * 4096
M_LAYER  = M_ATTN + M_EXP
M_EMBED  = 4096 * 128256
M_TOTAL  = 28 * M_LAYER + 2 * M_EMBED
KV_TOK   = 2 * 8 * 128 * 2                           # f16 K+V bytes per token per layer
DRAFT_W, DRAFT_KV = 1 * GB, 24 * 4096 * (2 * 8 * 64 * 2)

def sec_a():
    print("## [CHK-A] shapes and the minimum-dies theorem (PROBLEM-4 headline)")
    print(f"[CHK-A1] resident int8 totals: dense {D_TOTAL} B ({verdict(D_TOTAL, 386723217408)}), MoE {M_TOTAL} B ({verdict(M_TOTAL, 363002331136)})")
    print(f"[CHK-A2] four dies hold at most 4 x 86 GB = {4 * DIE_MEM} B: short of the weights ALONE by dense {D_TOTAL - 4 * DIE_MEM} B / "
          f"MoE {M_TOTAL - 4 * DIE_MEM} B -- infeasible for ANY byte split (sub-layer, per-expert, per-row), not only whole layers; "
          f"the corpus theorem T_min_dies_*_4 quantifies over whole-layer counts only (its aggregate twin T_min_dies_4_total is the general fact)")
    worst_d = 24 * D_LAYER + D_EMBED + DRAFT_W + DRAFT_KV + 24 * KV_TOK * 4096 + WS
    worst_m = 6 * M_LAYER + M_EMBED + 6 * KV_TOK * 4096 + WS
    print(f"[CHK-A3] five dies: dense 24 layers/die, heaviest die (lm_head + draft) needs {worst_d} B + overhead -> fits iff overhead <= {DIE_MEM - worst_d} B "
          f"= {(DIE_MEM - worst_d) / GiB:.2f} GiB (assumed 2 GiB [A]); MoE 6-layer die + embedding: fits iff overhead <= {DIE_MEM - worst_m} B = {(DIE_MEM - worst_m) / GiB:.2f} GiB")
    need_d = -(-(D_TOTAL + 5 * (ORT + WS)) // DIE_MEM); need_m = -(-(M_TOTAL + 5 * (ORT + WS)) // DIE_MEM)
    print(f"[CHK-A4] minimum dies = 5 for both shapes (4 infeasible by A2, 5 feasible by A3; byte-count lower bound with the assumed overhead: {need_d} / {need_m})")

# ----------------------------------------------------------------------------- B. the round-7 chain step
def xch(dies, d_model, lam=LAM, rows=1):
    """host-bounced exchange of a chain visiting `dies` (0/1 per position): hops + logits out + ids in + 2 lam per transfer"""
    act, logits = rows * d_model * 2, rows * 128256 * 4
    bw = sum(tn(act, D2H[dies[p]]) + tn(act, H2D[dies[p + 1]]) for p in range(len(dies) - 1))
    bw += tn(logits, D2H[dies[-1]]) + tn(rows * 4, H2D[dies[0]])
    return bw + (2 * (len(dies) - 1) + 2) * lam
CH8 = [1, 0, 1, 0, 1, 0, 1, 0]; CH4 = [1, 0, 1, 0]
def moe_layer(slab, attn, launch=T_LAUNCH, experts=8): return tn(M_ATTN, R_GEMM) + 2 * 8000 + 3 * experts * slab + attn + 7 * launch + 4 * C_Q
def moe_step(slab, attn, launch=T_LAUNCH): return 28 * moe_layer(slab, attn, launch) + tn(M_EMBED, R_GEMM) + 2 * launch + xch(CH8, 4096)
def dense_step(attn, launch=T_LAUNCH): return 120 * (tn(D_LAYER, R_GEMM) + attn + 6 * launch + 4 * C_Q) + tn(D_EMBED, R_GEMM) + 2 * launch + xch(CH8, 16384)
def tps(T, c=1000): return 1000 * c * 10 ** 6 // (4 * T)       # thousandths of tokens/s per card at aggregate concurrency c (thousandths)
SLAB_M0 = 2 * MiB * 80 // R_M0
RERUN   = CANON32 - DFR[32768]                                 # [D] 872 600 ns per tripped launch
AMORT   = tuple(DFR[32768] + fl(t * 873_000) for t in TAU)     # the corpus rounds the re-run to 873 000 ns
AMORT_X = tuple(DFR[32768] + fl(t * RERUN) for t in TAU)       # the same at the cell difference itself

def sec_b():
    print("\n## [CHK-B] the round-7 chain step, rebuilt term by term")
    print(f"[CHK-B1] M0 slab = 16 MiB / 165.8 GB/s = {SLAB_M0} ns ({verdict(SLAB_M0, 101189)}; fleet.py's own comment says 101 186)")
    for name, a, corpus_T, corpus_c in (("trip-free", DFR[32768], 127788019, 1956), ("amort cap 3072", AMORT[0], 129743539, 1926), ("amort cap 61440", AMORT[1], 129132439, 1935)):
        T = moe_step(SLAB_M0, a)
        print(f"[CHK-B2] MoE 32k {name}: {T} ns ({verdict(T, corpus_T)}) -> {tps(T)} ({verdict(tps(T), corpus_c)})")
    T = moe_step(SLAB_M0, AMORT[0], T_LAUNCH_REAL)
    print(f"[CHK-B3] MoE 32k amort cap 3072 at the realized launch bound: {T} ns ({verdict(T, 118853539)}) -> {tps(T)} ({verdict(tps(T), 2103)})")
    for L, corpus_T, corpus_c in ((131072, 202640419, 1233), (1 << 20, 904746019, 276)):
        T = moe_step(SLAB_M0, DFR[L]); print(f"[CHK-B4] MoE L={L} trip-free: {T} ns ({verdict(T, corpus_T)}) -> {tps(T)} ({verdict(tps(T), corpus_c)})")
    T = dense_step(DFR[32768]); print(f"[CHK-B5] dense 32k: {T} ns ({verdict(T, 2403248669)}) -> {tps(T)} ({verdict(tps(T), 104)})")
    print(f"[CHK-B6] the amortization constant: re-run = canonical - trip-free = {RERUN} ns; the fleet model uses 873 000 -> cells {AMORT} vs {AMORT_X} at the "
          f"cell difference (delta {AMORT[0] - AMORT_X[0]} / {AMORT[1] - AMORT_X[1]} ns: cosmetic)")
    sh = (("expert slabs", 24 * SLAB_M0), ("attention", AMORT[0]), ("launches at 91 us", 7 * T_LAUNCH), ("quant", 4 * C_Q), ("attn GEMMs + fixed", tn(M_ATTN, R_GEMM) + 16000))
    tot = moe_layer(SLAB_M0, AMORT[0])
    print("[CHK-B7] MoE 32k layer composition (amort cap 3072): " + ", ".join(f"{n} {v} ns = {r1(v * 100, tot)}%" for n, v in sh) + f"; layer {tot} ns")

# ----------------------------------------------------------------------------- C. the corrected two-instance cell (C-3)
def inst_weights(pos, x):
    w = 7 * (M_ATTN + M_EXP - M_EXP * x // 2000)
    return w + (M_EMBED if pos in (0, 3) else 0)
def inst_room(L, ort=ORT): return DIE_MEM - ort - WS - 7 * KV_TOK * L
def min_x(pos, L, ort=ORT): return next((x for x in range(1001) if inst_weights(pos, x) <= inst_room(L, ort)), None)
XS32 = [min_x(p, 32768) for p in range(4)]
def inst_step(hot, cold, attn, launch=T_LAUNCH, xs=XS32):
    T = 0
    for x in xs:
        T += 7 * (tn(M_ATTN, R_GEMM) + 16000 + 24 * (hot * (1000 - x) + cold * x) // 1000 + attn + 7 * launch + 4 * C_Q)
    return T + tn(M_EMBED, R_GEMM) + 2 * launch + xch(CH4, 4096)
T_COLD0 = MiB * 10 // R_W4                                     # 1 MiB of int4 per core at 5.3 GB/s/core

def sec_c():
    print("\n## [CHK-C] the two-instance cell at the round-7 anchors (round-4 C-3; in the repo only as a hard-coded print)")
    print(f"[CHK-C1] minimal int4 share per die: {XS32} thousandths ({'AGREE' if XS32 == [182, 170, 170, 182] else 'DIFF'}); worst-die margin "
          f"{min(inst_room(32768) - inst_weights(p, XS32[p]) for p in range(4))} B ({verdict(min(inst_room(32768) - inst_weights(p, XS32[p]) for p in range(4)), 24485516)})")
    for mg, corpus_T, corpus_c, corpus_cmin in zip(MERGE, (142055807, 144929937), (3519, 3449), (1095, 1118)):
        T = inst_step(SLAB_M0, T_COLD0 + mg, AMORT[0])
        cmin = -(-1927 * 4 * T // 10 ** 9)
        print(f"[CHK-C2] cold slab {T_COLD0 + mg} ns: instance step {T} ns (corpus print {corpus_T}: {verdict(T, corpus_T)}) -> two instances {tps(T, 2000)} "
              f"({verdict(tps(T, 2000), corpus_c)}) at c = 2.000, {tps(T, 1990)} at 1.990; beats the chain's 1.926 iff c >= {cmin} ({verdict(cmin, corpus_cmin)})")
    waste = 7 * 16 * (256 * KiB - 256)
    xw = [next(x for x in range(1001) if inst_weights(p, x) <= inst_room(32768) - waste) for p in range(4)]
    print(f"[CHK-C2b] the corpus's own round-4 page-waste term (one partial 256 KiB page per head and K|V: {waste} B per 7-layer die) exceeds that margin: "
          f"at x = 170 the inner dies are {waste - 24485516} B OVER; minimal shares become {xw} -- rounds 6 / 7 / 7F kept [182, 170, 170, 182] and T3r_instance_margin is stated on the waste-free model")
    T186 = inst_step(101186, T_COLD0 + MERGE[0], AMORT[0])
    print(f"[CHK-C3] the corpus print reproduces only with the slab at 101 186 ns (the stale comment value): {T186} ({verdict(T186, 142055807)}) -- "
          f"the cells are unaffected at three decimals; the ns print is {inst_step(SLAB_M0, T_COLD0 + MERGE[0], AMORT[0]) - 142055807} ns under the model's own constant")

# ----------------------------------------------------------------------------- D. the 32k break-even and what the "tie" ranks
def sec_d():
    print("\n## [CHK-D] the 32k lever tie (round-4 C-1; the 5.32 % is a hard-coded print in the repo)")
    e29 = 28 * 24 * (T_SER - SLAB_M0)
    line = LEG32 - e29 // 28
    taub = Fr(line - DFR[32768], 873_000)
    print(f"[CHK-D1] E29 at M0 = 28 x 24 x ({T_SER} - {SLAB_M0}) = {e29} ns ({verdict(e29, 14642880)}); fusion >= E29 iff the cell <= {line} ns ({verdict(line, 991940)})")
    print(f"[CHK-D2] break-even retry share = ({line} - {DFR[32768]}) / 873000 = {float(taub) * 100:.4f} % of launches (corpus 5.32 %); measured 8.0 / 5.5 % clear it by "
          f"{float((TAU[0] - taub) * 100):.2f} / {float((TAU[1] - taub) * 100):.2f} pt")
    print(f"[CHK-D3] what the tie ranks: the fusion gain is MEASURED - MEASURED (legacy {LEG32} - deferred); the E29 'gain' is DERIVED - MEASURED "
          f"(DESIGN-2's serial slab {T_SER}, never a kernel, minus M0). Against DESIGN-2's other derived baselines the same lever reads "
          f"{28 * 24 * (99374 - SLAB_M0)} ns (direct-serial 99 374) / {28 * 24 * (T_PP - SLAB_M0)} ns (ping-pong {T_PP}) -- the sign of the ranking is a choice of counterfactual; both levers are BANKED, so no build decision rides on it")
    for s in (5, 7, 8, 10, 15):
        t = Fr(s, 100) * DFR[32768] / (873_000 * (1 - Fr(s, 100)))
        print(f"[CHK-D4] HW-MAP also quotes the retry share as a share of attention ms: {s} % of ms <-> tau {float(t) * 100:.2f} % of launches -> cell {fl(DFR[32768] + t * 873_000)} ns "
              f"({'E29' if t > taub else 'fusion'} first)")

# ----------------------------------------------------------------------------- E. the MoE-128k attention-vs-weights line, whole-stream form
def sec_e():
    print("\n## [CHK-E] MoE-128k attention-vs-weights, legs-conditional -- whole-stream form (the corpus goes per 512-token block)")
    w_anchor = tn(M_ATTN, R_GEMM) + 16000 + 24 * T_SER
    kv = 131072 * KV_TOK
    for legs, corpus in zip((0, 1, 2), (1683, 1789, 1894)):
        # attention-bound iff  kv*(16+legs)/16 / G + FIX4 >= w_anchor   (G in GB/s x10 -> bytes*10/G ns)
        thr = max(g for g in range(1, 4000) if kv * 10 * (16 + legs) // (16 * g) + FIX4 >= w_anchor)
        print(f"[CHK-E1] legs {legs}: attention-bound iff G <= {thr / 10} GB/s ({verdict(thr, corpus)})")
    w_m0 = tn(M_ATTN, R_GEMM) + 16000 + 24 * SLAB_M0
    print(f"[CHK-E2] the line is superseded by measurement: deferred 128k cell {DFR[131072]} ns vs the weight layer {w_anchor} (derived anchor) / {w_m0} (M0): "
          f"attention-bound by {r1((DFR[131072] - w_anchor) * 100, w_anchor)} % / {r1((DFR[131072] - w_m0) * 100, w_m0)} % at every page size")
    print(f"[CHK-E3] HW-MAP's E21 sentence quotes the round-2 line 167.7 with the round-3 line's margins: (168.3 - 167.0) / 168.3 = {r1((1683 - 1670) * 100, 1683)} %, "
          f"(169.2 - 168.3) / 168.3 = {r1((1692 - 1683) * 100, 1683)} % (against 167.7 they would be {r1((1677 - 1670) * 100, 1677)} / {r1((1692 - 1677) * 100, 1677)} %)")

# ----------------------------------------------------------------------------- F. the instance fit margin
def sec_f():
    print("\n## [CHK-F] the instance fit: an assumption with megabytes of margin")
    m = min(inst_room(32768) - inst_weights(p, XS32[p]) for p in range(4))
    print(f"[CHK-F1] at x = {XS32} the MoE 32k instance fits iff the per-die overhead <= 2 GiB + {m} B ({verdict(m, 24485516)}) -- {m * 1e6 / DIE_MEM:.0f} ppm of the die")
    per = 7 * M_EXP // 2000
    print(f"[CHK-F2] one thousandth of x frees {per} B per die -> +{-(-GB // per)} thousandths per GB of extra overhead ({verdict(-(-GB // per), 23)}); "
          f"all-int4 (x = 1000) would absorb up to {(inst_room(32768, 0) - inst_weights(0, 1000)) / GiB:.1f} GiB of overhead: the overhead moves x, it cannot break the fit")

# ----------------------------------------------------------------------------- G. the instance-gain break-even over the cold-slab time
def inst_step3(tc):   # the round-3 anchors: hot 99 374 (derived direct-serial), attention 64 x 12 394 + FIX3, 8-lambda chain
    a3 = 64 * (262144 * 80 // 1692) + FIX3
    return sum(7 * (tn(M_ATTN, R_GEMM) + 16000 + 24 * (99374 * (1000 - x) + tc * x) // 1000 + a3 + 7 * T_LAUNCH + 4 * C_Q) for x in XS32) \
        + tn(M_EMBED, R_GEMM) + 2 * T_LAUNCH + xch(CH4, 4096)
def sec_g():
    print("\n## [CHK-G] instance gain: the iff over the int4 core-slab time")
    T0 = inst_step3(T_COLD0)
    print(f"[CHK-G1] round-3 instance step at the measured unpack ({T_COLD0} ns): {T0} ns ({verdict(T0, 134376737)}) -> {tps(T0, 2000)} ({verdict(tps(T0, 2000), 3720)})")
    tc = max(t for t in range(1_300_000, 1_500_000) if tps(inst_step3(t), 2000) >= 1803)
    print(f"[CHK-G2] two instances >= 1.803 (the anchored chain + 1) iff cold slab <= {tc} ns ({verdict(tc, 1406404)}) = {r2(MiB, tc)} GB/s per core; measured 5.3 is {r1(tc, T_COLD0)}x inside")
    lo, hi = T_COLD0, 2_000_000
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if tps(inst_step(SLAB_M0, mid, AMORT[0]), 2000) >= 1927: lo = mid
        else: hi = mid - 1
    print(f"[CHK-G3] NEW at the round-7 anchors (M0 hot slab, measured amortization, chain 1.926): two instances win iff cold slab (incl. merge) <= {lo} ns "
          f"= {r2(MiB, lo)} GB/s per core -- the merged slabs {T_COLD0 + MERGE[0]} / {T_COLD0 + MERGE[1]} are {r1(lo, T_COLD0 + MERGE[1])}x inside at worst")

# ----------------------------------------------------------------------------- H. speculative decoding
def tau3(a):
    p1 = a; p2 = p1 * a // 1000; p3 = p2 * a // 1000
    return 1000 + p1 + p2 + p3
def draft3(k=3): return k * (tn(DRAFT_W, R_GEMM) + tn(DRAFT_KV, R_GEMM) + 121 * T_LAUNCH + 24 * 4 * C_Q + tn(128256 * 4, D2H[0]) + 2 * LAM)
def moe_verify(slab, attn):   # t = 4 verify rows: 32 active experts (uniform), one 16-row fragment (rows = t x g = 16)
    return 28 * moe_layer(slab, attn, experts=32) + tn(M_EMBED, R_GEMM) + 2 * T_LAUNCH + xch(CH8, 4096, rows=4) + draft3()
def sec_h():
    print("\n## [CHK-H] speculative decoding thresholds")
    T1, T4 = moe_step(T_SER, DFR[32768]), moe_verify(T_SER, DFR[32768])
    a_loss = max(a for a in range(1001) if tau3(a) * T1 < 1000 * T4)
    print(f"[CHK-H1] MoE 32k on the round-6 anchors: t = 1 {T1} ({verdict(T1, 142430899)}), verify t = 4 {T4} ({verdict(T4, 456819203)}); spec LOSES iff alpha <= {a_loss / 1000} ({verdict(a_loss, 854)})")
    T1b, T4b = moe_step(SLAB_M0, DFR[32768]), moe_verify(2 * MiB * 80 // R_M0_T4, DFR[32768])
    a7 = max(a for a in range(1001) if tau3(a) * T1b < 1000 * T4b)
    print(f"[CHK-H2] NEW at the round-7 anchors (M0 slabs: {SLAB_M0} at t = 1, {2 * MiB * 80 // R_M0_T4} at t >= 4): t = 1 {T1b}, verify {T4b}; spec loses iff alpha <= {a7 / 1000} "
          f"-- the corpus still quotes 0.854 (the line rode the retired derived slab); verdict unchanged at alpha = 0.7 ({tps(T4b) * tau3(700) // 1000} vs {tps(T1b)})")
    base = 120 * (tn(D_LAYER, R_GEMM) + 6 * T_LAUNCH + 4 * C_Q) + tn(D_EMBED, R_GEMM) + 2 * T_LAUNCH + xch(CH8, 16384, rows=4) + draft3()
    Td = dense_step(DFR[32768])
    v = (tau3(700) * Td - 1000 * base - 1) // (1000 * 120)
    print(f"[CHK-H3] dense verify step = {base} + 120 v ({verdict(base, 2356301528)}); at alpha = 0.7 spec beats t = 1 iff v <= {v} ns per layer ({verdict(v, 31092727)}) = {r1(v, DFR[32768])}x the t = 1 cell")

# ----------------------------------------------------------------------------- I. the online-chain drift bound
def ppm_ceil(n): return -(-n * 10 ** 6 // 2 ** 24)
def sec_i():
    print("\n## [CHK-I] f32 online-chain drift (first-order bound: n roundings x 2^-24 relative to the sum of magnitudes)")
    for L, b, corpus in ((1 << 20, 512, 246), (1 << 20, 256, 490), (32768, 512, 10)):
        nb, groups = L // b, b // 128
        n_o = (groups - 1) + 1 + nb                     # block-local partial sums, one hand-over, one running add per block
        n_s = b * 16 // 1024 + 2 + nb + 4               # 8 reels into the block accumulator, two folds, running add, final 16 -> 1
        print(f"[CHK-I1] L={L} block {b}: chains O {n_o}, S {n_s} -> {ppm_ceil(n_o)} + {ppm_ceil(n_s)} = {ppm_ceil(n_o) + ppm_ceil(n_s)} ppm ({verdict(ppm_ceil(n_o) + ppm_ceil(n_s), corpus)})")
    n_o = 3 + 1 + 2048 + 127
    print(f"[CHK-I2] the bound omits the matrix unit's own accumulation inside each 128-token partial (order UNMEASURED): charged sequentially (+127 roundings) "
          f"the O chain is {n_o} -> {ppm_ceil(n_o)} + 123 = {ppm_ceil(n_o) + 123} ppm at 1M -- still {1000 // (ppm_ceil(n_o) + 123)}x inside the 1000 ppm line")
    nmax = 499 * 2 ** 24 // 10 ** 6
    print(f"[CHK-I3] the deterministic bound meets the ship line (each chain <= 499 ppm) at chain length {nmax}: {(nmax - 14) * 512} tokens at 512-token blocks "
          f"({(nmax - 14) * 512 / 1e6:.2f} M), {(nmax - 12) * 256} at 256 -- the 1M cell is not near it")
    print("[CHK-I4] not covered by the family: P is an f16 (relative half-ulp 2^-11 = 488 ppm per weight); a same-sign worst case on S and O is 977 ppm, "
          "L-independent -- inside 1000 ppm, but it is the tighter of the two deterministic numerics margins, and it is not a ledger row")

# ----------------------------------------------------------------------------- J. deferred-guard amortization
def sec_j():
    print("\n## [CHK-J] the deferred guard against the legacy scan")
    p = (LEG32 - DFR[32768]) * 100000 // RERUN
    if DFR[32768] * 100000 + p * RERUN >= LEG32 * 100000: p -= 1
    print(f"[CHK-J1] deferred beats legacy iff 945500 + p x {RERUN} < {LEG32}: p <= {p} per 1e5 launches = {p / 1000} % ({verdict(p, 65253)})")
    for L in (32768, 131072, 1 << 20):
        print(f"[CHK-J2] effective KV rate at L={L}: {r1(L * KV_TOK, DFR[L])} GB/s" + (f"; amortized {r1(32768 * KV_TOK, AMORT[0])} / {r1(32768 * KV_TOK, AMORT[1])} (corpus 142.0 / 132.2 / 135.1)" if L == 32768 else ""))

# ----------------------------------------------------------------------------- K. the stage-overlap bound and its gate
def sec_k():
    print("\n## [CHK-K] E40 stage overlap: bound and gate, from the measured phases")
    stream, bounce = 770_800, 51_000                      # [M] session-3 phases at 32k t = 1
    f1, f2 = stream + bounce, 64 * 12_394 + bounce       # [M] 12 394 ns per 256 KiB page (E21, shuffled)
    prize1, prize2 = DFR[32768] - f1, DFR[32768] - f2
    print(f"[CHK-K1] floors F1 {f1} / F2 {f2} ns; reachable overlap <= {prize1} ({r1(prize1 * 100, DFR[32768])} %) / {prize2} ({r1(prize2 * 100, DFR[32768])} %) "
          f"({verdict(prize1, 123700)} / {verdict(prize2, 101284)})")
    d1, d2 = stream // 512, 12_394 // 8                   # per-tile DDR time
    g1 = max(phi for phi in range(5000) if 64 * max(1594 - d1, 0) + 64 * phi + 10_000 < prize1)
    g2 = max(phi for phi in range(5000) if 64 * max(1438 - 2 * d2, 0) + 128 * phi + 20_000 < prize2)
    print(f"[CHK-K2] gate: most tolerant consistent cell phi <= {g1} ns ({verdict(g1, 1687)}); least tolerant k <= 2 cell phi <= {g2} ns ({verdict(g2, 635)}); "
          f"the erratum-29 crossing band 10 000-20 000 ns is {r1(10000, g1)}-{r1(20000, g1)}x above the tolerant line")
    print(f"[CHK-K3] the bound subtracts session-3 phases from a session-5 total: session 5's guard-off cell is 902 900 vs session 3's 938 800 (-35 900 ns), and the "
          f"session-5 phases were not re-timed -- if the stream phase carried that gain the F1 floor drops to {f1 - 35_900} and the bound rises to {prize1 + 35_900}; "
          f"if the other phases did, the bound stands. Either way it is a ceiling gated on an unmeasured phi, not a forecast")

# ----------------------------------------------------------------------------- L. the realized launch bound
def sec_l():
    print("\n## [CHK-L] the realized per-launch overhead")
    non_gemm, gemm, step, n = 7_700_000, 59_300_000, 67_000_000, 24 * 9
    print(f"[CHK-L1] 7.7 ms / (24 layers x 9 launches) = {non_gemm // n} ns <= 36 000 ({'AGREE' if non_gemm // n <= 36000 else 'DIFF'}); serialized 91 us launches alone = {n * T_LAUNCH} ns > the whole non-GEMM share")
    print(f"[CHK-L2] the 7.7 ms is not a measurement: it is the residual 67.0 - 59.3 ms (measured step minus BYTE-ACCOUNTED GEMM; 7.7 / 67 = {770 * 100 // 67 / 100} % = the quoted 11.5 % residual). "
          f"Roof-robust form: if the in-situ GEMM ran at the 181.3 pure-read roof instead of 174.6 the residual is {step - gemm * 1746 // 1813} ns -> <= {(step - gemm * 1746 // 1813) // n} ns per launch")
    T = moe_step(SLAB_M0, AMORT[0], (step - gemm * 1746 // 1813) // n)
    print(f"[CHK-L3] the realized headline at that bound: {tps(T)} (corpus 2.103 at 36 us; 1.926 at 91 us) -- the 91 us reading is excluded either way (needs the in-situ GEMM {r1((gemm - (step - n * T_LAUNCH)) * 100, gemm)} % faster than its byte accounting, against a DDR roof 3.8 % above the kernel)")

# ----------------------------------------------------------------------------- M. the i32 overflow bound (PROBLEM-2)
def sec_m():
    print("\n## [CHK-M] exact i32 accumulation of the MoE chains")
    for K, corpus in ((4096, 32), (7168, 18)):
        u = (2 ** 31 - 1) // (127 * 127 * K)
        print(f"[CHK-M1] K = {K}: {u} chains of |a|,|b| <= 127 stay below 2^31 - 1 ({verdict(u, corpus)}); {u + 1} can saturate")
    print(f"[CHK-M2] the measured saturation probe agrees: 2 147 092 480 = 127^2 x {2147092480 // 16129} products = {2147092480 // 16129 // 4096}.5 chains of 4096 -- exact below, clamped at 2^31 - 1 above")

# ----------------------------------------------------------------------------- N. the dense kernel's two utilization numbers
def sec_n():
    print("\n## [CHK-N] PROBLEM-1: issue occupancy is not compute utilization")
    calls = (8192 // 16) * (8192 // 128) // 8
    stream = 8192 * 8192 * 10 // R_GEMM
    print(f"[CHK-N1] K = N = 8192: {calls} MMA calls per core x 15 ns = {calls * 15} ns; against the quoted 487 us stream {r1(calls * 15 * 100, 487000)} % (the 12.5 % row); "
          f"487 us is a {r1(8192 * 8192, 487000)} GB/s stream -- at the shipped 174.6 the stream is {stream} ns and the occupancy {r1(calls * 15 * 100, stream)} %")
    print(f"[CHK-N2] useful compute at m = 1: 174.6 G MAC/s = 349.2 GFLOPS = {r2(3492 * 100, 178000)} % of the die's 17.8 TFLOPS -- the '12.5 % of compute peak' in CHEATSHEET section 0 is the "
          f"ISSUE occupancy (15 of 16 fragment rows are padding); the two differ by {r1(125 * 1780, 3492 * 10)}x")
    print(f"[CHK-N3] row-consistency of two HW-MAP rows: at 17.8-26.6 TFLOPS/die a full (16,16,128) fragment (65 536 FLOPs) is {r1(65536 * 8, 17800)} - {r1(65536 * 8, 26600)} ns of unit time "
          f"per core, above the 15 ns 'issue cost' -- the 15 ns is an issue latency under a bandwidth-bound stream, not an execution time; cost models that multiply it by call counts "
          f"under-charge a compute-bound regime by {r2(65536 * 8, 26600 * 15)}-{r2(65536 * 8, 17800 * 15)}x (moot at m <= 16 where the stream binds)")
    print(f"[CHK-N4] f16 flat region M = 16..128 at 144-148 GB/s needs {144 * 128 / 1000:.1f}-{148 * 128 / 1000:.1f} TFLOPS at M = 128: inside the measured 17.8-26.6 (consistent)")

# ----------------------------------------------------------------------------- O. roofline arithmetic (CHEAT-MATH B)
def sec_o():
    print("\n## [CHK-O] the die-level roofline")
    print(f"[CHK-O1] ridge 17.8 T-OP/s / 173.8 GB/s = {r1(178000, 1738)} OPs/byte (102 < ridge < 103: {'AGREE' if 102 * 1738 < 178000 < 103 * 1738 else 'DIFF'}); "
          f"free rows 2M <= ridge: {178000 // (2 * 1738)} (8-bit) / {178000 // (4 * 1738)} (4-bit) ({verdict(178000 // (2 * 1738), 51)} / {verdict(178000 // (4 * 1738), 25)})")
    print(f"[CHK-O2] the same ridge on the upper measured compute figure (26.6 TFLOPS/die at n = 2k): {r1(266000, 1738)} OPs/byte -> {266000 // (2 * 1738)} / {266000 // (4 * 1738)} free rows; "
          f"the corpus quotes one end of a measured range as 'the' ridge")
    print(f"[CHK-O3] the measured flat region ends at m = 16 (m = 24: 81 GB/s) -- 3.2x short of the ridge's 51 rows; HW-MAP attributes m >= 24 to an unresolved multi-strip wedge, "
          f"so the ridge is an upper bound the shipped kernel does not reach, not a reproduction of the flat region")

# ----------------------------------------------------------------------------- P. the fork's headline, recomputed here
def blocks(layers, layer_ns, head_ns, d_model, launch=T_LAUNCH):
    out = []
    for p, n in enumerate(layers):
        T = n * layer_ns
        if p == 7: T += head_ns + 2 * launch
        act = d_model * 2
        if p > 0: T += tn(act, H2D[CH8[p]]) + LAM
        T += (tn(act, D2H[CH8[p]]) if p < 7 else tn(128256 * 4, D2H[CH8[p]])) + LAM
        out.append(T)
    return out
def pipe(Pi, T, bmax, c=None):
    """fleet tokens/s (thousandths) with Pi sequences in flight at aggregate concurrency c (thousandths; default Pi x 1000)"""
    c = Pi * 1000 if c is None else c
    return min(1000 * c * 10 ** 6 // T, 10 ** 12 // bmax)
def sec_p():
    print("\n## [CHK-P] the fork (DESIGN-FORK-PIPE.md): sequence pipelining built from single-die runtime instances")
    Tm, Td = moe_step(SLAB_M0, AMORT[0]), dense_step(DFR[32768])
    bm = blocks([4, 3, 4, 3, 4, 3, 4, 3], moe_layer(SLAB_M0, AMORT[0]), tn(M_EMBED, R_GEMM), 4096)
    bd = blocks([15] * 8, tn(D_LAYER, R_GEMM) + DFR[32768] + 6 * T_LAUNCH + 4 * C_Q, tn(D_EMBED, R_GEMM), 16384)
    print(f"[CHK-P1] MoE blocks {bm} ns, sum + lambda = {sum(bm) + LAM} ({verdict(sum(bm) + LAM, Tm)} with the chain step); dense max block {max(bd)} ns, sum + lambda {verdict(sum(bd) + LAM, Td)}")
    for Pi in (1, 2, 4, 8):
        print(f"[CHK-P2] Pi = {Pi}: MoE {pipe(Pi, Tm, max(bm)) // 4} / dense {pipe(Pi, Td, max(bd)) // 4} thousandths of tok/s per card"
              + (f"  (the corpus's two-instance V3 at the same two sequences: 3519 / 3449 MoE, 149 / 140 dense)" if Pi == 2 else "")
              + (f"  (block-bound: 1 / max block; the balanced 7-units-per-die split would give {8 * 10 ** 12 // Tm // 4})" if Pi == 8 else ""))
    print(f"[CHK-P3] at Pi = 2 the cell is the chain's own step at c = 2.000: {tps(Tm, 2000)} -- exactly the number round-4 C-3 retired as an error for V3 (T7r_inst); "
          f"it is the correct cell of THIS plan. Pi = 2 beats V3's 3519 iff c >= {-(-3520 * 4 * Tm // 10 ** 9)}, and beats the single chain iff c >= {-(-1927 * 4 * Tm // 10 ** 9)} (V3 needs 1095 / 1118)")
    for Pi in (2, 8):
        kvm, kvd = 4 * KV_TOK * 32768 * Pi, 15 * KV_TOK * 32768 * Pi
        wm, wd = 4 * M_LAYER + M_EMBED, 15 * D_LAYER + D_EMBED + DRAFT_W + DRAFT_KV
        print(f"[CHK-P4] memory at 32k with {Pi} contexts per die: MoE worst die {wm + kvm + WS + ORT} B (slack {DIE_MEM - (wm + kvm + WS + ORT)}), dense {wd + kvd + WS + ORT} B (slack {DIE_MEM - (wd + kvd + WS + ORT)}) "
              f"-- GiB of slack where V3 has 24.5 MB")
    Lm = (DIE_MEM - ORT - WS - (4 * M_LAYER + M_EMBED)) // (4 * KV_TOK)
    print(f"[CHK-P5] context budget per die (MoE 4-layer die): L x Pi <= {Lm} tokens -> Pi = 8 up to L = {Lm // 8}, Pi = 2 up to {Lm // 2}, 1M only at Pi = 1")

# ----------------------------------------------------------------------------- Q. region-difference exactness under the MEASURED saturation
def sec_q():
    print("\n## [CHK-Q] PROBLEM-2: the region-difference accumulator under saturating i32 (HW-MAP: SILENT SATURATION at 2^31 - 1, no zero-init)")
    hi = 2 ** 31 - 1; M = 127 * 127 * 4096
    sat = lambda x: max(-2 ** 31, min(hi, x))
    b, S = 2_147_483_000, 1000
    print(f"[CHK-Q1] DESIGN-2 P2 says the difference is exact 'whatever the region held before' -- true in wrap arithmetic, false on this part: region {b}, "
          f"true sum {S}: wrap gives {(((b + S + 2 ** 31) % 2 ** 32 - 2 ** 31) - b + 2 ** 31) % 2 ** 32 - 2 ** 31}, the saturating unit gives {sat(b + S) - b}")
    print(f"[CHK-Q2] exact iff the launch state b keeps b + running sum inside the rails: |b| <= 2^31 - 1 - uses x 127^2 x K. At K = 4096: D = 8 (2 uses per region) "
          f"|b| <= {hi - 2 * M}; D = 128 (22 uses) |b| <= {hi - 22 * M}; the U_max = 32 bound holds only for b = 0")
    for name, pat in (("f32 1.0 (0x3F800000)", 0x3F800000), ("f32 2.0 (0x40000000)", 0x40000000), ("f32 +Inf (0x7F800000)", 0x7F800000)):
        print(f"[CHK-Q3] a region left holding {name} = {pat} as i32: worst-case chains before the rail = {(hi - pat) // M}")
    print(f"[CHK-Q4] f32 -0.0 is 0x80000000 = the negative rail itself: zero headroom for any negative sum. The serving loop alternates this kernel with an "
          f"f32-writing attention kernel on the same L0C; the measured saturation probe was exact to 2 147 092 480, i.e. its own launch state was <= {hi - 2147092480} -- a benign arena")

# ----------------------------------------------------------------------------- R. the accuracy class of per-token int8 activations
def sec_r():
    print("\n## [CHK-R] PROBLEM-1/2 numerics gate: 'relerr <= 1e-3 class' against per-token int8 activations")
    print(f"[CHK-R1] rint to 127 levels: rms error = step / sqrt(12) = max / (127 sqrt 12); 127 sqrt 12 lies in (439, 440) "
          f"({439 ** 2} < {127 * 127 * 12} < {440 ** 2}) -> relative rms error = crest / 440 (crest = max / rms of the row)")
    print("[CHK-R2] a uniform row (crest sqrt 3) lands at exactly 1 / 254 = 3.9e-3; Gaussian rows of 8192 (crest ~ 4.2) near 1e-2 -- 4x to 10x over the 1e-3 class. "
          "The measured 'fp64-exact x20, relerr 1.07e-7' compares against a reference that shares the quantizer (erratum-32 class): it certifies kernel arithmetic, not the gate")

# ----------------------------------------------------------------------------- S. V3 at equal demand: batching and staggering
def dense_step_b(B, attn=DFR[32768]): return 120 * (tn(D_LAYER, R_GEMM) + B * attn + 6 * T_LAUNCH + 4 * C_Q) + tn(D_EMBED, R_GEMM) + 2 * T_LAUNCH + xch(CH8, 16384, rows=B)
def sec_s():
    print("\n## [CHK-S] the two-instance plan against the same two sequences on the unchanged int8 chain")
    T2 = dense_step_b(2)
    print(f"[CHK-S1] dense, two rows batched (weights read once): {T2} ns ({verdict(T2, 2516749780)}) -> {1000 * 2 * 10 ** 9 // (4 * T2)} thousandths/card against V3's 149 / 140 [C] "
          f"-- V3 would need c >= {-(-198 * 4 * 3337073683 // 10 ** 9)} thousandths > 2.000 to match: dominated at every reachable concurrency")
    print(f"[CHK-S2] at the MEASURED 2-client batching factor 1.53 (HW-MAP, another served model): 0.104 x 1.53 = {104 * 153 // 100} thousandths -- still above V3's 149")
    print(f"[CHK-S3] MoE: batching does not rescue (distinct experts double); staggering does -- see CHK-P: 3853 vs V3's 3519 / 3449 at equal c")

# ----------------------------------------------------------------------------- T. where tau is not measured
def sec_t():
    print("\n## [CHK-T] the retry share beyond the measured cell (tau is MEASURED at 32k, t = 1, one model)")
    R1M = 56_000_000 - DFR[1 << 20]
    p = (46_300_000 - DFR[1 << 20]) * 100000 // R1M
    print(f"[CHK-T1] at 1M the deferred guard beats the legacy scan iff tau < {p / 1000} % (re-run {R1M} ns) ({verdict(p, 64476)})")
    for h in (Fr(8, 100), Fr(55, 1000)):
        print(f"[CHK-T2] IF trips were independent per 32k-token segment [A] at the measured {float(h) * 100} %: tau(128k) = {float(1 - (1 - h) ** 4) * 100:.1f} %, "
              f"tau(1M) = {float(1 - (1 - h) ** 32) * 100:.1f} % -> 1M cell {fl(DFR[1 << 20] + (1 - (1 - h) ** 32) * R1M)} ns vs legacy 46 300 000")
    hstar = next(h for h in range(1, 1000) if 1 - (1 - Fr(h, 1000)) ** 32 >= Fr(p, 100000))
    print(f"[CHK-T3] under that assumption the 1M choice flips at a 32k-segment rate of {hstar / 10} % -- BELOW both measured caps; HW-MAP says trips cluster "
          f"(which lowers tau(L)), so the truth is between 8 % and ~93 %: unmeasured, and it decides the 1M kernel")
    T = moe_step(SLAB_M0, DFR[1 << 20] + fl((1 - (1 - Fr(8, 100)) ** 32) * R1M))
    print(f"[CHK-T4] the corpus quotes 128k / 1M TRIP-FREE (1.233 / 0.276) beside an amortized 32k cell; at the independent-segment bound the 1M cell is {tps(T)} thousandths")

# ----------------------------------------------------------------------------- U. E40 with the measured per-step intercept
def sec_u():
    print("\n## [CHK-U] E40 again, with the fixed cost the three measured cells imply")
    slope = (DFR[131072] - DFR[32768]) // 192
    icpt = DFR[32768] - 64 * slope
    f1, f2 = 821_800, 844_216
    b1, b2 = DFR[32768] - icpt - f1, DFR[32768] - icpt - f2
    print(f"[CHK-U1] chord through the 32k and 128k cells: {slope} ns per block + {icpt} ns per step ({verdict(icpt, 54428)}; the 1M cell sits {DFR[1 << 20] - icpt - 2048 * slope} ns above it)")
    print(f"[CHK-U2] cross-block overlap cannot recover a per-step cost: bound = cell - intercept - floor = {b1} (F1, {r1(b1 * 100, DFR[32768])} %) / {b2} (F2, {r1(b2 * 100, DFR[32768])} %) "
          f"against the corpus's 123700 / 101284 (13.1 / 10.7 %)")
    print(f"[CHK-U3] the gate tightens to phi <= {(b1 - 1) // 64} ns (F1, k = 1; corpus 1687) and the erratum-29 band is {r1(10000, (b1 - 1) // 64)}-{r1(20000, (b1 - 1) // 64)}x above it; "
          f"on F2 the bound ({b2}) is under the bounce removal (51000) at phi = 0 -- 'E40 above bounce removal at both ends of the bracket' does not survive")

# ----------------------------------------------------------------------------- V. the K-int8 lever, re-priced on the measured rows
def sec_v():
    print("\n## [CHK-V] K-int8 on the measured rows (HW-MAP: 87.6 GB/s own-K bytes at d = 64, same-extent time ratio 2.13x; exact x20)")
    khalf = 770_800 // 2
    lo, hi = khalf - khalf // 2, khalf - khalf * 100 // 213
    print(f"[CHK-V1] the K half of the measured K+V stream phase at 32k is {khalf} ns per layer; halved / at 2.13x it saves {lo} / {hi} ns "
          f"({r1(lo * 100, DFR[32768])}-{r1(hi * 100, DFR[32768])} % of the cell) -- {r1(lo, 69272)}x-{r1(hi, 46856)}x the intercept-corrected E40 bound, with no phi gate")
    for L, mult, corpus in ((32768, 1, AMORT[0]), (131072, 4, DFR[131072]), (1 << 20, 32, DFR[1 << 20])):
        a, b = moe_step(SLAB_M0, corpus - mult * lo), moe_step(SLAB_M0, corpus - mult * hi)
        print(f"[CHK-V2] MoE L={L}: {tps(moe_step(SLAB_M0, corpus))} -> {tps(a)}-{tps(b)} thousandths/card (stream phase scaled x{mult}; [A] the d = 64 ratio transfers to d = 128 production tiles; accuracy E36 UNMEASURED)")
    print("[CHK-V3] ALTERNATIVES carries this as #7 (+4.2 / +12.2 / +27.2 % on the round-2 model -- the measured rows re-price it at the same size), but the round-6 lever "
          "ranking of DESIGN-3 / DESIGN-4 names E40 'attention-side #1' and omits it; on measured rows K-int8 is the larger attention-side lever at every L")

# ----------------------------------------------------------------------------- W. the realized overhead, read as the measurement gives it
def sec_w():
    print("\n## [CHK-W] the planner's overhead terms against the one measured serving accounting")
    plan91, plan36 = 290 * 91_000 + 32 * 4 * C_Q, 290 * 36_000 + 32 * 4 * C_Q
    print(f"[CHK-W1] the measured stack (32 layers x 9 launches + 2): the planner's launch + quant terms give {plan91} ns at 91 us / {plan36} at 36 us against the MEASURED non-GEMM share 7 700 000 "
          f"({r1(plan91, 7_700_000)}x / {r1(plan36, 7_700_000)}x) -- the 'realized' reading still double-counts the quant pass (the 7.7 ms is ALL non-GEMM time)")
    per = 7_700_000 // 288
    T = 28 * (tn(M_ATTN, R_GEMM) + 16000 + 24 * SLAB_M0 + AMORT[0] + 7 * per) + tn(M_EMBED, R_GEMM) + 2 * per + xch(CH8, 4096)
    print(f"[CHK-W2] MoE 32k with {per} ns per launch covering all non-GEMM work [A: the residual transfers]: {T} ns -> {tps(T)} thousandths (corpus 1926 primary / 2103 realized)")
    print("[CHK-W3] no row of DESIGN-4 or its ledger compares a planner cell with an end-to-end measured cell: the planner is self-consistent, not validated")

# ----------------------------------------------------------------------------- X. the megakernel at the realized launch
def sec_x():
    print("\n## [CHK-X] the megakernel's pay line at the launch readings HW-MAP now carries")
    red_d, red_m = 2 * tn(1_343_488, R_GEMM), 2 * tn(335_872, R_GEMM)       # [C] two DDR K-split reductions per layer
    for T, name in ((91_000, "91 us primary"), (36_000, "36 us realized bound"), (26_700, "26.7 us measured stack"), (17_000, "17 us empty-launch floor")):
        d, m = (5 * T - red_d) // 4, (6 * T - red_m) // 5
        print(f"[CHK-X1] launch {name}: pays iff c_sync <= {d} ns (dense, 5 launches saved vs 4 flag rounds) / {m} ns (MoE, 6 vs 5)"
              + (f" ({verdict(d, 109903)} / {verdict(m, 108430)})" if T == 91_000 else ""))
    print(f"[CHK-X2] at the erratum-29 primary reading c_sync = 20 000 ns it pays iff the launch it removes costs >= {-(-(4 * 20000 + red_d) // 5)} ns (dense) / {-(-(5 * 20000 + red_m) // 6)} ns (MoE): "
          f"inside the measured 17-36 us band -- the go/no-go is not decided, and ALTERNATIVES / DESIGN-4 still print the 109.9 / 108.4 us lines as current")

# ----------------------------------------------------------------------------- Y. what the 17.8 in the ridge is
def sec_y():
    print("\n## [CHK-Y] the roofline's compute figure")
    print(f"[CHK-Y1] 17.8 TFLOPS / 128 FLOP per byte (f16, 128 rows per weight pass) = {r2(17800, 128)} GB/s = {r1(17800 * 1000, 128 * 1738)} % of the 173.8 stream: numerically the n = 8k figure is what a "
          f"STREAM-BOUND 128-row f16 GEMM delivers (HW-MAP's own 144-148 GB/s flat region gives 18.4-18.9 TFLOPS). Whether that benchmark was so blocked is not recorded [SUSPECTED]; "
          f"what is recorded is that 17.8 is the LOW end of a measured range and is quoted as 'the' peak")
    print(f"[CHK-Y2] the other two rows: 26.6 TFLOPS at n = 2k -> ridge {r1(266000, 1738)}; 15 ns per (16,16,128) call = {8 * 32768 // 15} G-MAC/s per die = {r2(2 * 8 * 32768, 15 * 1000)} TFLOPS -> ridge {r1(2 * 8 * 32768 * 10, 15 * 1738)} "
          f"-- the free-row counts 51 / 25 are a LOWER reading (76 / 38 or 100 / 50); 'a 16-row tree is free on both formats' holds on all three")

# ----------------------------------------------------------------------------- Z. CHEATSHEET #3's 1.04x
def sec_z():
    print("\n## [CHK-Z] CHEATSHEET candidate #3 (4-bit KV): the sign of the 1.04x")
    print(f"[CHK-Z1] 4-bit KV through the measured unpack: half the bytes at 42.0 GB/s int4-effective vs int8 at 87.6 -> time ratio {r2(876, 2 * 420)}x -- 4 % SLOWER than KV-int8, "
          f"not a 1.04x gain cap; against the production f16 stream (142.0-149.7 GB/s) it is {r2(1420, 2 * 420)}-{r2(1497, 2 * 420)}x slower per extent. On this machine the row buys memory only")

if __name__ == "__main__":
    print("# proof/check.py -- PROMPT-7 challenge round, independent re-derivations")
    for s in (sec_a, sec_b, sec_c, sec_d, sec_e, sec_f, sec_g, sec_h, sec_i, sec_j, sec_k, sec_l, sec_m, sec_n, sec_o, sec_p, sec_q, sec_r, sec_s, sec_t, sec_u, sec_v, sec_w, sec_x, sec_y, sec_z): s()
