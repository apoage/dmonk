#!/usr/bin/env python3
"""proof/model.py -- executable cost model for DESIGN.md (dmonk).

Integer arithmetic only, formula-for-formula identical to proof/model.lean:
  rates   : tenths of GB/s  (1 B/ns = 1 GB/s decimal, so bytes*10/ns = tenths)
  bytes   : bytes ;  KiB = 1024, MiB = 1048576
  time    : ns (floor) ;  tau (MMA 16^3 fragment time) : hundredths of ns
  rounding: time   = bytes*10 // R                      (floor)
            rate   = (2*W*10 + t) // (2*t)             (round half up, tenths)
            us     = (ns + 500) // 1000                 (round half up)
            pct    = (2*num*1000 + den) // (2*den)      (tenths of a percent)
Run:  python3 proof/model.py      (no dependencies; Python >= 3.8)
Output = the sections of DESIGN.md whose cells are derived numbers, labelled
[Dx.y] so PROOF-COVERAGE.md can cite them; every label also names the Lean
theorem that fixes the same integer.
"""

KiB, MiB = 1024, 1 << 20

# ---------------------------------------------------------------- Measured (HW-MAP)
R_DDR    = 1738      # LPDDR streaming per die, tenths of GB/s            (HW-MAP card table)
R_STAGE  = 1800      # DDR->S1 plain copies aggregate, tenths of GB/s     (HW-MAP data-movement)
R_US_S1  = 2500      # vector SRAM -> S1, tenths of GB/s per core         (HW-MAP data-movement)
TAU      = {"3.70": 370, "3.46": 346, "2.46": 246}   # hundredths of ns per 16^3 fragment
R_VEC    = 432       # tenths of G lane-ops/s/core  (40 lanes/cycle * 1.08 GHz)
T_LAUNCH = 91_000    # ns, launch+queue floor
R_FRAC   = 70        # COPY_FRAC software path, tenths of GB/s per core
L0C_P    = 64 * KiB  # PRIOR lower bound
S1_P     = 1_000_000 # PRIOR "~1 MB" (decimal)
L0C_BIG  = 256 * KiB # hypothetical, §7.2 last row
FILL_NS  = 5_000     # ASSUMED fill+drain budget (empirical, E7/E10) -- not a HW-MAP number

# ---------------------------------------------------------------- Design (cost model)
def Nc(N):            return N // 8
def mFrag(m):         return (m + 15) // 16
def calls(K, N, m):   return (K // 64) * (Nc(N) // 256) * mFrag(m)
def wBytes(K, N):     return K * N
def aBytesCore(K, m): return 16 * mFrag(m) * K * 2
def nSlab(N, m, l0c, tileN=256): return min(Nc(N), (l0c // (64 * mFrag(m))) // tileN * tileN)   # slab = whole MMA tiles
def nSlabs(N, m, l0c, tileN=256): return Nc(N) // nSlab(N, m, l0c, tileN)
def aResident(K, m, s1): return aBytesCore(K, m) + 256 * KiB <= s1
def aPasses(K, N, m, l0c, s1, tileN=256): return 1 if aResident(K, m, s1) else nSlabs(N, m, l0c, tileN)
def ddrBytesDie(K, N, m, l0c, s1, tileN=256): return wBytes(K, N) + 8 * aPasses(K, N, m, l0c, s1, tileN) * aBytesCore(K, m)
def ddrBytesDieP(K, N, m):  return wBytes(K, N) + 8 * aBytesCore(K, m)          # scheme P: A once
def ddrBytesDieG2(K, N, m): return 2 * wBytes(K, N) + 8 * aBytesCore(K, m)      # geometry G2: 2 B/elem
def timeNs(b, R):      return b * 10 // R
def mmaNs(K, N, m, tau): return calls(K, N, m) * 64 * tau // 100
def rateT(W, t):       return (2 * W * 10 + t) // (2 * t)
def kernelNs(K, N, m, l0c, s1, R, tau, tileN=256): return max(timeNs(ddrBytesDie(K, N, m, l0c, s1, tileN), R), mmaNs(K, N, m, tau))
def predicted(K, N, m, l0c, s1, R, tau, tileN=256): return rateT(wBytes(K, N), kernelNs(K, N, m, l0c, s1, R, tau, tileN))
def kernelNsP(K, N, m, R, tau): return max(timeNs(ddrBytesDieP(K, N, m), R), mmaNs(K, N, m, tau))
def predictedP(K, N, m, R, tau): return rateT(wBytes(K, N), kernelNsP(K, N, m, R, tau))
def loaderRate(L):     return (2 * 8 * L * 64 + 66) // (2 * 66)        # W8, 1 B/elem through loader
def loaderRate1b(L):   return (2 * 8 * L * 64 + 132) // (2 * 132)      # W8 via f16 tiles (2 B/elem)
def predictedW8(L):    return min(1685, loaderRate(L))
def w4Rate(D, L):      return min(R_DDR, 4 * D, 2 * L)                  # D tenths Gelem/s/core, L tenths GB/s/core f16
def mmaCap(c_ns):      return (2 * 8 * 16384 * 100 + (2368 + 10 * c_ns)) // (2 * (2368 + 10 * c_ns))  # tenths
def usR(ns):           return (ns + 500) // 1000
def pct(num, den):     return (2 * num * 1000 + den) // (2 * den)       # tenths of a percent
def t10(x):            return f"{x // 10}.{x % 10}"

K = N = 8192
W = wBytes(K, N)
A1 = aBytesCore(K, 1)

def main():
    print("# model.py output -- cells of DESIGN.md §1.3, §4.1, §7, plus derived constants\n")

    # ------------------------------------------------------------ §1.3 issue counts / cadence
    print("## [D1.3] issue counts and MMA cadence (K=N=8192 unless stated)")
    for (KK, NN) in ((8192, 8192), (4096, 4096), (2048, 2048)):
        print(f"[D1.3-calls-{KK}] calls(m) = {calls(KK, NN, 1)}*mt :", {m: calls(KK, NN, m) for m in (1, 16, 32, 48, 64)})
    per_call = 64 * TAU["3.70"] // 10          # tenths of ns
    print(f"[D1.3-percall] 64 fragments x 3.70 ns = {t10(per_call)} ns ; at 2.46 ns = {t10(64 * TAU['2.46'] // 10)} ns")
    cad_stage = 16384 * 10 // (R_STAGE // 8)   # ns, 16 KiB at 22.5 GB/s/core
    cad_ddr = 16384 * 80 // R_DDR              # ns, 16 KiB at 173.8/8 GB/s/core
    print(f"[D1.3-cadence] 16 KiB tile every {cad_stage} ns at 22.5 GB/s/core, {cad_ddr} ns at 21.725")
    slack = cad_stage * 10 - per_call          # tenths of ns
    print(f"[D1.3-slack] slack per (256x64) call = {cad_stage} - {t10(per_call)} = {t10(slack)} ns  -> c_mma <= {slack // 10} ns hides")
    print(f"[D1.3-cap1000] c_mma = 1000 ns caps at {t10(mmaCap(1000))} GB/s ; c_mma = 0 -> {t10(mmaCap(0))}")
    cad64 = 65536 * 10 // (R_STAGE // 8)
    print(f"[D1.3-slack1024] (1024x64) tile: cadence {cad64} ns - {t10(4 * per_call)} ns = {t10(cad64 * 10 - 4 * per_call)} ns")
    for key, tau in TAU.items():
        print(f"[D1.3-mma-{key}] MMA busy per core, mt=1..4 (us): {[usR(mmaNs(K, N, 16 * i, tau)) for i in (1, 2, 3, 4)]}")
    print(f"[D1.3-m64] m=64: 8 MiB / {usR(mmaNs(K, N, 64, 370))} us = {t10(rateT(8 * MiB, mmaNs(K, N, 64, 370)))} GB/s/core -> x8 = {t10(8 * rateT(8 * MiB, mmaNs(K, N, 64, 370)))} GB/s/die")
    print(f"[D1.3-ddr373] B only, 8 MiB at 22.5 GB/s/core = {usR(timeNs(8 * MiB, R_STAGE // 8))} us ; B+A at 21.725 = {usR((8 * MiB + A1) * 80 // R_DDR)} us (= D7.1)")
    print()

    # ------------------------------------------------------------ §4.1 per-chunk
    print("## [D4.1] per k-chunk (66 KiB = 64 KiB B + 2 KiB A, m<=16)")
    chunk = 64 * KiB + 2 * KiB
    c_ddr = chunk * 80 // R_DDR; c_stage = chunk * 10 // (R_STAGE // 8)
    print(f"[D4.1-chunk] 66 KiB per core: {c_ddr} ns at 21.725 GB/s/core, {c_stage} ns at 22.5 -> 3.0-3.1 us ; 2 chunks = {2 * c_ddr} ns")
    for i in (1, 2, 3, 4):
        mma_chunk = 4 * i * 64 * TAU["3.70"] // 100
        print(f"[D4.1-occ-mt{i}] MMA per chunk mt={i}: {mma_chunk} ns -> {t10(pct(mma_chunk, c_ddr))} % of the {c_ddr} ns chunk")
    epi = 16 * 2 * 1024 * 10 // R_VEC   # ns: 16 rows x (Mul + Cast) x 1024 lanes
    print(f"[D4.1-epilogue] 16 rows x 2 ops x 1024 lanes / 43.2 G = {epi} ns")
    print()

    # ------------------------------------------------------------ §7.1 occupancy
    print("## [D7.1] per-stage occupancy, K=N=8192, W8, m=1 (= m=16), DDR branch (R = 173.8)")
    tot = ddrBytesDie(K, N, 1, L0C_P, S1_P); t = timeNs(tot, R_DDR); t180 = timeNs(tot, R_STAGE)
    m370 = mmaNs(K, N, 1, 370); m246 = mmaNs(K, N, 1, 246)
    print("| Stage | Bytes per core | Time | vs roof |")
    print("|---|---|---|---|")
    print(f"| DDR / copy-in | 8 MiB B + 256 KiB A = {tot // 8} B | {usR(t)} µs | 100% |")
    print(f"| loader | {tot // 8} B | {tot // 8} B / L | 100% needs L ≥ 21.8 GB/s/core; target needs 15.5 |")
    print(f"| MMA | {calls(K, N, 1)} calls | {usR(m370)} µs (3.7 ns) / {usR(m246)} µs (2.46) | {t10(pct(m370, t))}% / {t10(pct(m246, t))}% |")
    print(f"| vector | 16 rows × (Mul + Cast) × 1024 lanes | {epi} ns | {t10(pct(epi, t))}% |")
    print(f"| copy-out | 2 KiB (m=1) / 32 KiB (m=16) | < 0.2 µs | ~0 |")
    print(f"| fill + drain (ASSUMED ≤ 5 µs, empirical E7/E10) | | ≤ 5 µs | {t10(pct(FILL_NS, t + FILL_NS))}% |")
    print(f"[D7.1-rate] effective = {W} B / {t} ns = {t10(rateT(W, t))} GB/s at 173.8 ; {t10(rateT(W, t180))} at 180")
    print(f"[D7.1-rate-1b] Route 1b vector cast: 8 Mi / 43.2 G = {usR(8 * MiB * 10 // R_VEC)} us = {t10(pct(8 * MiB * 10 // R_VEC, t))}% of {usR(t)} us")
    print()

    # ------------------------------------------------------------ §7.2 m-curve
    print("## [D7.2] m-curve, K=N=8192, W8, L0C = 64 KiB (P), S1 = 1 MB (P), R = 173.8")
    print("| m | mt | N_slab | slabs | A per core | A policy | DDR bytes/die | DDR time | MMA time 3.7 / 3.46 / 2.46 ns | predicted |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    def row(label, m, l0c, s1, schemeP=False):
        i = mFrag(m); ns = nSlab(N, m, l0c); nsl = nSlabs(N, m, l0c)
        a = aBytesCore(K, m)
        if schemeP:
            tot = ddrBytesDieP(K, N, m); pol = "once (scheme P)"
        else:
            tot = ddrBytesDie(K, N, m, l0c, s1); pol = "resident in S1" if aResident(K, m, s1) else f"re-streamed ×{nsl}"
            if nsl == 1: pol = "once"
        td = timeNs(tot, R_DDR)
        mm = [mmaNs(K, N, m, tau) for tau in (370, 346, 246)]
        pred = [rateT(W, max(td, x)) for x in mm]
        bound = "DDR" if td >= mm[0] else "MMA"
        ps = t10(pred[0]) if pred[0] == pred[2] else f"{t10(pred[0])}–{t10(pred[2])}"
        print(f"| {label} | {i} | {ns} | {nsl} | {a // KiB} KiB | {pol} | {(tot - W) // MiB + 64} MiB | {usR(td)} µs | {usR(mm[0])} / {usR(mm[1])} / {usR(mm[2])} | **{ps}** ({bound}-bound at 3.7 ns) |")
        return pred
    row("1, 16", 1, L0C_P, S1_P)
    row("32", 32, L0C_P, S1_P)
    row("32 (A re-streamed)", 32, L0C_P, 0)
    row("48", 48, L0C_P, S1_P)
    row("64", 64, L0C_P, S1_P)
    row("64, scheme P", 64, L0C_P, S1_P, schemeP=True)
    row("64, L0C ≥ 256 KiB", 64, L0C_BIG, S1_P)
    print("[D7.2-l0c32] L0C = 32 KiB: m=16 ->", t10(predicted(K, N, 16, 32 * KiB, S1_P, R_DDR, 370)), "(slabs", nSlabs(N, 16, 32 * KiB), "); m=64 with n=128 tiles ->", t10(predicted(K, N, 64, 32 * KiB, S1_P, R_DDR, 370, 128)), "(slabs", nSlabs(N, 64, 32 * KiB, 128), ")")
    print()

    # ------------------------------------------------------------ §7.3 loader-bound branch
    print("## [D7.3] loader-bound branch: rate = 8·L·(64/66), predicted = min(168.5, that)")
    print("| L (GB/s/core) | 8·L·64/66 | predicted W8 | Route 1b (f16 tiles, L/2) |")
    print("|---|---|---|---|")
    for L in (100, 155, 185, 217, 218, 220, 310, 435):
        print(f"| {t10(L)} | {t10(loaderRate(L))} | {t10(predictedW8(L))} | {t10(min(1685, loaderRate1b(L)))} |")
    print()

    # ------------------------------------------------------------ §7.4 other sizes
    print("## [D7.4] other sizes, W8, m=1, DDR branch (R = 173.8)")
    print("| K=N | W8 bytes/die | DDR time incl. A | in-kernel | with ASSUMED 5 µs fill/drain | wall with unpipelined 91 µs |")
    print("|---|---|---|---|---|---|")
    for KK in (2048, 4096, 8192):
        NN = KK; Wk = wBytes(KK, NN); tot = ddrBytesDie(KK, NN, 1, L0C_P, S1_P); td = timeNs(tot, R_DDR)
        print(f"| {KK} | {Wk / 1e6:.2f} MB | {usR(td)} µs | {t10(rateT(Wk, td))} | {t10(rateT(Wk, td + FILL_NS))} | {t10(rateT(Wk, td + T_LAUNCH))} |")
    print()

    # ------------------------------------------------------------ §5 W4
    print("## [D5] W4 (K=N=8192): 32 MiB of i4 per die, 8 Mi elements per core")
    W4 = W // 2; t4 = timeNs(W4, R_DDR)
    print(f"[D5-ddr] 32 MiB at 173.8 = {usR(t4)} us ; target 120 -> {usR(W4 * 10 // 1200)} us ; DDR-bound incl. A stream: {t10(rateT(W4, timeNs(W4 + 8 * A1, R_DDR)))}")
    for D in (432, 300, 218, 217):
        td = 8 * MiB * 10 // D
        print(f"[D5-dequant-{D}] D = {t10(D)} Gelem/s/core -> {usR(td)} us -> {t10(rateT(W4, td))} W4-GB/s ; w4Rate(D, L=inf) = {t10(w4Rate(D, 10**6))}, token-equiv x2 = {t10(2 * w4Rate(D, 10**6))}")
    print(f"[D5-loader] f16 through loader at roof: 2 x 21.725 = 43.45 -> W4 roof needs L >= {t10(869)} x2 = 87.0 (model: 2L >= 1738 <-> L >= 869) ; target: 2L >= 1200 <-> L >= 600")
    print(f"[D5-vector] 5 lane-ops/elem: 8 Mi x 5 / 43.2 G = {usR(8 * MiB * 5 * 10 // R_VEC)} us -> {t10(rateT(W4, 8 * MiB * 5 * 10 // R_VEC))} W4-GB/s = {t10(2 * rateT(W4, 8 * MiB * 5 * 10 // R_VEC))} W8-equivalent")
    print(f"[D5-f16] f16 round trip: 2·K·N = {2 * W} B / 173.8 = {usR(timeNs(2 * W, R_DDR))} us -> {t10(rateT(W4, timeNs(2 * W, R_DDR)))} W4-equivalent")
    f16cons = (2 * 512 * 1000 + 370) // (2 * 370)      # tenths of GB/s: 512 B per 3.70 ns
    print(f"[D5-mma] f16 B consumption 512 B / 3.70 ns = {t10(f16cons)} GB/s/core ; at 86.9 GB/s/core the MMA is {t10(pct(869, f16cons))}% busy")
    print(f"[D5-drains] (d): K/128 = {K // 128} drains x 64 KiB·mt = {K // 128 * 64 // 1024} MiB·mt per core")
    print()

    # ------------------------------------------------------------ §6 partition alternatives
    print("## [D6] partition alternatives at m=64, K=N=8192")
    ksplit = W + 8 * (64 * (K // 8) * 2) + 16 * MiB + 16 * MiB + 2 * MiB
    tk = timeNs(ksplit, R_DDR)
    print(f"[D6-ksplit] K-split DDR bytes = 64 MiB B + 1 MiB A + 16 MiB partial writes + 16 MiB reduction reads + 2 MiB y = {ksplit // MiB} MiB -> {t10(rateT(W, tk))} ; with the +91 us second launch: {t10(rateT(W, tk + T_LAUNCH))}")
    msplit = 4 * W + 4 * 2 * A1
    print(f"[D6-msplit] M-split (4 groups x 2 cores, W streamed 4x): {msplit // MiB} MiB -> {t10(rateT(W, timeNs(msplit, R_DDR)))}")
    print()

    # ------------------------------------------------------------ §1.4 scheme P costs, §3.3, §9 misc
    print("## [D-misc] other derived cells")
    adds_ns = 3 * 64 * 1024 * 10 // R_VEC; cp_ns = 2 * MiB * 10 // R_US_S1; drain_ns = MiB * 10 // 100
    print(f"[D1.4-adds] scheme P f32 adds: 3 blocks x 64 x 1024 = {3 * 64 * 1024} lane-ops / 43.2 G = {adds_ns} ns = {t10((adds_ns + 50) // 100)} us")
    print(f"[D1.4-copies] scheme P US<->S1 copies: 16 x 2 x 64 KiB = 2 MiB / 250 GB/s = {cp_ns} ns = {t10((cp_ns + 50) // 100)} us ; drain 1 MiB at 10 GB/s = {usR(drain_ns)} us")
    frac_ns = 32 * KiB * 10 // R_FRAC; frac8_ns = 8 * KiB * 10 // R_FRAC; t2048 = timeNs(ddrBytesDie(2048, 2048, 1, L0C_P, S1_P), R_DDR)
    print(f"[D3.3-frac] COPY_FRAC for 32 KiB y: {frac_ns} ns = {t10((frac_ns + 50) // 100)} us = {t10(pct(frac_ns, t))}% of 8192² (m=16 at 2048²: 8 KiB -> {frac8_ns} ns = {t10(pct(frac8_ns, t2048))}% of {usR(t2048)} us)")
    print(f"[D7.5-route4] vector-only: 43.2 G / 3 ops = {t10(R_VEC // 3)} G weights/s/core -> x8 = {t10(8 * (R_VEC // 3))} GB/s/die ceiling ; /16 rows at m=16: 70-78 -> {70 / 16:.1f}-{78 / 16:.1f}")
    print(f"[D7.5-route5] 60 ns x (8192/64)^2 = {60 * (8192 // 64) ** 2} ns = {usR(60 * (8192 // 64) ** 2)} us per tile")
    tile_ser = 16384 * 100 // 500 + 2368                 # tenths of ns: 16 KiB at 50 GB/s + one call
    print(f"[D9-l0b] single-buffered L0B at L = 50 GB/s/core: 327.7 + 236.8 = {t10(tile_ser)} ns per tile -> {t10((2 * 16384 * 100 + tile_ser) // (2 * tile_ser))} GB/s/core")
    print(f"[D9-16cube] 16^3-only calls per core = {(K // 16) * (Nc(N) // 16)} ; slack = 373 us / that = {t10(373_000 * 10 // ((K // 16) * (Nc(N) // 16)))} ns")
    print(f"[D9-copyin] 256 copy calls per core ; 373 us / 256 = {t10(373_000 * 10 // 256)} ns per call hidden by the 4-deep ring")
    print(f"[D9-g2] geometry G2 (2 B/elem i8 tiles): W8 DDR = {ddrBytesDieG2(K, N, 1) // MiB} MiB -> {t10(rateT(W, timeNs(ddrBytesDieG2(K, N, 1), R_DDR)))} GB/s ; Route 1b target threshold L >= 31.0 (model: loaderRate1b(310) = {t10(loaderRate1b(310))}, (309) = {t10(loaderRate1b(309))})")
    print(f"[D8-e2] E2 exactness: 10000 tiles x 64 rows x 15 = {10000 * 64 * 15} < 2^24 = {2 ** 24} ; MMA cannot mask L below 16384 B / 236.8 ns = {t10((2 * 16384 * 100 + 2368) // (2 * 2368))} GB/s")
    tau148 = (2 * 512 * 100 + 148) // (2 * 148)   # hundredths of ns: 512 B / (148/8 GB/s) / 8 fragments
    print(f"[D0-tau] 148/8 = 18.5 GB/s/core ; 512 B / 18.5 GB/s = 27.7 ns per 8 fragments -> {tau148 // 100}.{tau148 % 100:02d} ns per fragment")
    print(f"[D-const] R_DDR/8 = 21.725 ; first tenth above = 21.8 ; W4 break-even D >= 21.8 (8D >= 1738), L >= 43.5 (4L >= 1738)")

if __name__ == "__main__":
    main()
