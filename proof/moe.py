#!/usr/bin/env python3
"""proof/moe.py -- executable integer cost model for DESIGN-2.md (MoE grouped quant-GEMM decode).

Same conventions as proof/model.py so the round-2 Lean session can transcribe it 1:1:
  rates   : tenths of GB/s (bytes*10/ns) ; time : ns (floor) ; bytes ; KiB = 1024, MiB = 2^20
  rateT   = (2*W*10 + t) // (2*t)   (round half up, tenths)   usR = (ns+500)//1000   pct = tenths of %
Every constant is tagged with its HW-MAP origin. Run: python3 -I proof/moe.py
"""
KiB, MiB = 1024, 1 << 20
# ------------------------------------------------------------------ HW-MAP (measured) -------------
R_DDR     = 1738     # LPDDR streaming per die, tenths of GB/s                          [card table]
R_STAGE   = 1800     # DDR->S1 plain copies aggregate (22.5/core)                        [data-movement]
L_SER     = 265      # S1->L0 loader, strict-serial barriers, tenths GB/s per core       [data-movement]
C_MMA     = 15       # ns per MMA call at (16,16,128)                                    [data-movement]
T_DENSE   = 487_000  # ns: realized dense W8 kernel per core, 8 MiB B + 128 KiB i8 A    [137.8 GB/s row]
R_VEC     = 432      # tenths of G lane-ops/s/core (40 lanes/cycle x 1.08 GHz)           [compute table]
T_LAUNCH  = 91_000   # ns launch+queue floor                                             [data-movement]
L0A = L0B = 64 * KiB # measured
L0C       = 256 * KiB
R_VENDOR  = 246      # vendor grouped quant-GEMM, tenths GB/s                            [data-movement]
# ------------------------------------------------------------------ DERIVED / ASSUMED -------------
def residualPerCallTenths():
    """c_res: per-call residual of the realized dense kernel, tenths of ns.
    487 000 ns - loader(8 MiB + 128 KiB)/26.5 - 4096 x 15 ns, divided by 4096 calls."""
    loader = (8 * MiB + 128 * KiB) * 10 // L_SER
    return (T_DENSE - loader - 4096 * C_MMA) * 10 // 4096
C_RES   = residualPerCallTenths()      # = 254 -> 25.4 ns (DERIVED by subtraction, not measured directly)
FIXED   = 8_000      # ASSUMED fixed per-step cost: 5 us fill + 2 us exposed dispatch + 1 us tail (E14/E15)
DESC    = 1024       # router descriptor bytes per core (<= 16 x 10 x 6 B = 960)

def rateT(W, t): return (2 * W * 10 + t) // (2 * t)
def usR(ns):     return (ns + 500) // 1000
def pct(n, d):   return (2 * n * 1000 + d) // (2 * d)
def t10(x):      return f"{x // 10}.{x % 10}"
def ceil(a, b):  return (a + b - 1) // b

# ------------------------------------------------------------------ geometry -----------------------
def Nc(Ne):                 return Ne // 8                 # scheme S: 8-way column split of every expert
def bX(K, Ne):              return K * Ne                  # W8 bytes per expert (what the rate counts)
def aCore(K):               return 16 * K                  # i8 A [16, K] (per-token-quantized, errata 13)
def sliceB(K, Ne):          return K * Nc(Ne)              # per-core slice of one expert
def callsX(K, Ne):          return (K // 128) * (Nc(Ne) // 16)   # (16,16,128) calls per expert per core
def aLiftPerExpert(K):      return aCore(K)                # A re-lifted through the loader once per expert (K > 3072)
def loaderBytes(K, Ne, D):  return D * (sliceB(K, Ne) + aLiftPerExpert(K))
def ddrBytes(K, Ne, D, t):  return D * bX(K, Ne) + 8 * aCore(K) + D * 4 * Ne + 8 * DESC + t * Ne * 2
# ------------------------------------------------------------------ per-core time model ------------
def tDdr(K, Ne, D, t):      return ddrBytes(K, Ne, D, t) * 10 // R_DDR
def tLoad(K, Ne, D):        return loaderBytes(K, Ne, D) * 10 // L_SER
def tMma(K, Ne, D):         return D * callsX(K, Ne) * C_MMA
def tRes(K, Ne, D, cres=C_RES): return D * callsX(K, Ne) * cres // 10
def tSerial(K, Ne, D, cres=C_RES): return tLoad(K, Ne, D) + tMma(K, Ne, D) + tRes(K, Ne, D, cres)
def stepSer(K, Ne, D, t, cres=C_RES, fixed=FIXED): return max(tSerial(K, Ne, D, cres), tDdr(K, Ne, D, t)) + fixed
def stepPP(K, Ne, D, t, fixed=FIXED):   return max(tDdr(K, Ne, D, t), tLoad(K, Ne, D), tMma(K, Ne, D)) + fixed
def rateSer(K, Ne, D, t, cres=C_RES, fixed=FIXED): return rateT(D * bX(K, Ne), stepSer(K, Ne, D, t, cres, fixed))
def ratePP(K, Ne, D, t, fixed=FIXED):   return rateT(D * bX(K, Ne), stepPP(K, Ne, D, t, fixed))
# ------------------------------------------------------------------ scheme W (whole experts per core) -
def unitsW(D):              return ceil(D, 8)              # dynamic round-robin: max experts on one core
def tSerialW(K, Ne, D, cres=C_RES):
    u = unitsW(D); return u * (K * Ne + aCore(K)) * 10 // L_SER + u * (K // 128) * (Ne // 16) * (C_MMA * 10 + cres) // 10
def tDdrCoreW(K, Ne, D):    return (unitsW(D) * K * Ne + aCore(K)) * 80 // R_DDR   # per-core DDR share 173.8/8
def stepW(K, Ne, D, t, cres=C_RES): return max(tSerialW(K, Ne, D, cres), tDdrCoreW(K, Ne, D), tDdr(K, Ne, D, t)) + FIXED
def rateW(K, Ne, D, t, cres=C_RES): return rateT(D * bX(K, Ne), stepW(K, Ne, D, t, cres))
def stepWstatic(K, Ne, D, t, cres=C_RES):   # adversarial static map: all D active experts on one core
    return max(D * (K * Ne + aCore(K)) * 10 // L_SER + D * (K // 128) * (Ne // 16) * (C_MMA * 10 + cres) // 10,
               (D * K * Ne + aCore(K)) * 80 // R_DDR) + FIXED
def rateWstatic(K, Ne, D, t, cres=C_RES): return rateT(D * bX(K, Ne), stepWstatic(K, Ne, D, t, cres))
# ------------------------------------------------------------------ K-split hybrid (needs a reduce launch) --
# per core: K/8 rows x all Ne columns of every expert = the same K*Ne/8 bytes and the same call count as S,
# A lift per expert = 16 x K/8 i8 (8x smaller), partials: the m_e routed rows x Ne x 4 B i32 per expert per core,
# written to DDR and read back by a second launch (no cross-core sync in-kernel); k*t routed pairs per step.
def chainK(K, Ne):           return (K * Ne // 8 + 16 * (K // 8)) * 10 // L_SER + callsX(K, Ne) * (C_MMA * 10 + C_RES) // 10
def deltaA(K, Ne):           return tSerial(K, Ne, 1) - chainK(K, Ne)          # per-expert A-lift saving of K-split vs S
def partialBytes(Ne, kk, t): return 8 * kk * t * Ne * 4                         # written once, read once
def stepKsplit(K, Ne, D, t, kk=8):
    return D * chainK(K, Ne) + FIXED + T_LAUNCH + partialBytes(Ne, kk, t) * 10 // R_DDR
def rateKsplit(K, Ne, D, t, kk=8): return rateT(D * bX(K, Ne), stepKsplit(K, Ne, D, t, kk))
def marginK(K, Ne, D, t, kk=8):    return stepKsplit(K, Ne, D, t, kk) - stepSer(K, Ne, D, t)   # > 0 means S wins
# ------------------------------------------------------------------ W4 via i4x i4 (conditional route) --
def b4X(K, Ne):            return K * Ne // 2
def ddrBytes4(K, Ne, D, t): return D * (b4X(K, Ne) + (K // 128) * Ne * 4) + 8 * aCore(K) + 8 * DESC + t * Ne * 2
def calls4(K, Ne):         return 2 * callsX(K, Ne)                       # nibble-split A: two i4 planes
def loaderBytes4(K, Ne, D): return D * (sliceB(K, Ne) // 2 + (K // 128) * Nc(Ne) * 4 + aCore(K))
def tSerial4(K, Ne, D, cres=C_RES): return loaderBytes4(K, Ne, D) * 10 // L_SER + D * calls4(K, Ne) * (C_MMA * 10 + cres) // 10
def drainBytes4(K, Ne, D, t): return D * (K // 128) * 16 * Nc(Ne) * 4   # one [16, Nc] i32 slab per 128-row group
def step4(K, Ne, D, t, cres=C_RES): return max(tSerial4(K, Ne, D, cres), ddrBytes4(K, Ne, D, t) * 10 // R_DDR) + FIXED
def rate4(K, Ne, D, t, cres=C_RES): return rateT(D * b4X(K, Ne), step4(K, Ne, D, t, cres))
def drainNeed4(K, Ne, D, t): # tenths of GB/s per core the L0C->US path must sustain to hide the group drains
    return rateT(drainBytes4(K, Ne, D, t), step4(K, Ne, D, t))

K, Ne, k, E = 4096, 4096, 8, 256
if __name__ == "__main__":
    import sys
    print("# proof/moe.py -- DESIGN-2.md derived cells\n")
    print("[M0] c_res = (487000 - (8 MiB+128 KiB)*10/265 - 4096*15) / 4096 =", t10(C_RES), "ns ; dense re-prediction:",
          t10(rateT(64 * MiB, (8 * MiB + 128 * KiB) * 10 // L_SER + 4096 * C_MMA + 4096 * C_RES // 10)), "GB/s (measured 137.8)")
    D = 8
    print(f"[M1] headline K=Ne={K}, k={k}, t=1, D=8, W8:")
    print("     ddrBytes =", ddrBytes(K, Ne, 8, 1), "= W", 8 * bX(K, Ne), "+ A", 8 * aCore(K), "+ scales", 8 * 4 * Ne, "+ desc", 8 * DESC, "+ y", 2 * Ne)
    print("     tDdr", tDdr(K, Ne, 8, 1), "ns ; loaderBytes/core", loaderBytes(K, Ne, 8), "tLoad", tLoad(K, Ne, 8), "; calls/core", 8 * callsX(K, Ne), "tMma", tMma(K, Ne, 8), "tRes", tRes(K, Ne, 8))
    print("     tSerial", tSerial(K, Ne, 8), "stepSer", stepSer(K, Ne, 8, 1), "-> rateSer", t10(rateSer(K, Ne, 8, 1)), "| stepPP", stepPP(K, Ne, 8, 1), "-> ratePP", t10(ratePP(K, Ne, 8, 1)))
    print("     wall (+91 us): ser", t10(rateT(8 * bX(K, Ne), stepSer(K, Ne, 8, 1) + T_LAUNCH)), "pp", t10(rateT(8 * bX(K, Ne), stepPP(K, Ne, 8, 1) + T_LAUNCH)))
    print("     vs vendor 24.6:", t10(rateSer(K, Ne, 8, 1) * 10 // R_VENDOR), "x ; MMA occupancy of tDdr", t10(pct(tMma(K, Ne, 8), tDdr(K, Ne, 8, 1))), "% ; loader share", t10(pct(tLoad(K, Ne, 8), tDdr(K, Ne, 8, 1))), "%")
    print("[M2] c_res sensitivity (headline):", {c: t10(rateSer(K, Ne, 8, 1, c)) for c in (0, 50, 100, 150, 200, 254, 300)})
    # loader threshold in ping-pong regime
    need = loaderBytes(K, Ne, 8) * 10
    Lstar = ceil(need, tDdr(K, Ne, 8, 1))
    print("[M3] ping-pong DDR-bound iff L >= loaderBytes/tDdr =", t10(Lstar), "GB/s/core (measured 26.5) ; MMA+res", tMma(K,Ne,8)+tRes(K,Ne,8), "<= tDdr", tDdr(K,Ne,8,1))
    print("[M4] per 16 KiB piece: loader", 16384 * 10 // L_SER, "ns, 8 MMA", 8 * C_MMA, "ns, DDR share", 16384 * 80 // R_DDR, "ns, residual 8 x", t10(C_RES), "=", 8 * C_RES // 10)
    print("[M5] D sweep, t as in table, scheme S serial / S ping-pong / W-dyn / W-static / K-split")
    for DD in (4, 8, 9, 10, 16, 32, 64, 128):
        t = 1 if DD <= 8 else (4 if DD <= 32 else 16)
        print(f"     D={DD:3d} t={t:2d} S-ser {t10(rateSer(K,Ne,DD,t))} step {usR(stepSer(K,Ne,DD,t)):5d} us | S-pp {t10(ratePP(K,Ne,DD,t))} | W-dyn {t10(rateW(K,Ne,DD,t))} | W-static {t10(rateWstatic(K,Ne,DD,t))} | K-split {t10(rateKsplit(K,Ne,DD,t))} | D/(8ceil) {DD}/{8*ceil(DD,8)}")
    print("[M6] other shapes, t=1, D=k: (K,Ne,k) -> Nc, calls/expert/core, S-ser, step us, wall, S-pp, W-dyn")
    for (KK, NN, kk) in ((4096,4096,8),(7168,2048,8),(4096,1024,8),(2048,512,4),(7168,4096,10),(2048,4096,4),(4096,512,8)):
        print(f"     {(KK,NN,kk)} Nc {Nc(NN):4d} calls {callsX(KK,NN):5d} S-ser {t10(rateSer(KK,NN,kk,1))} step {usR(stepSer(KK,NN,kk,1)):5d} us wall {t10(rateT(kk*bX(KK,NN), stepSer(KK,NN,kk,1)+T_LAUNCH))} S-pp {t10(ratePP(KK,NN,kk,1))} W-dyn {t10(rateW(KK,NN,kk,1))} A/B loader {t10(pct(aCore(KK), sliceB(KK,NN)))}%")
    print("[M7] W4 (i4x i4 + nibble-split A, per-group drains), headline D=8 t=1: ddrBytes4", ddrBytes4(K,Ne,8,1), "tSerial4", tSerial4(K,Ne,8), "rate4", t10(rate4(K,Ne,8,1)), "W4-GB/s = tokens x", t10(2*rate4(K,Ne,8,1)), "W8-equiv ; drain need", t10(drainNeed4(K,Ne,8,1)), "GB/s/core ; vector-unpack ceiling 42")
    print("     c_res=0:", t10(rate4(K,Ne,8,1,0)), "; ping-pong DDR-bound W4:", t10(rateT(8*b4X(K,Ne), ddrBytes4(K,Ne,8,1)*10//R_DDR + FIXED)))
    # epilogue + dispatch budgets
    epi = 4 * 512 * 10 // R_VEC
    print("[M8] epilogue per routed (tau,e): 4 ops x 512 lanes =", 4*512, "lane-ops =", epi, "ns ; per step k*t=128:", 128*epi, "ns ; drain 2 KiB per routed pair, 256 KiB per step at t=16")
    print("[M9] buffers: S1 ring 4x64 KiB =", 4*64, "KiB + A", aCore(K)//KiB, "KiB (K=4096) /", aCore(7168)//KiB, "KiB (K=7168) ; L0B 3x16 KiB =", 48, "KiB of 64 ; L0C 2 x", 16*Nc(Ne)*4//KiB, "KiB of 256 ; US ~", 1+6+1+32+4+4+2+16, "KiB")
    print("[M10] quantities: A i8 per core", aCore(K), "B =", aCore(K)//KiB, "KiB ; per-expert slice", sliceB(K,Ne)//MiB, "MiB =", sliceB(K,Ne)//(64*KiB), "copies of 64 KiB ; k-chunk (128 rows x Nc) =", 128*Nc(Ne)//KiB, "KiB")

    # ------------------------------------------------------------- Zipf bridge (empirical, floating point, NOT part of the integer model)
    if "--zipf" in sys.argv:
        import random, math
        def gen(E, k, t, s, seed):
            rng = random.Random(seed)
            perm = list(range(E)); rng.shuffle(perm)          # rank -> expert id
            w = [ (r + 1) ** (-s) for r in range(E) ]
            idx = []
            for tau in range(t):
                avail = list(range(E)); ww = w[:]
                chosen = []
                for j in range(k):
                    tot = sum(ww[i] for i in avail)
                    u = rng.random() * tot; acc = 0.0
                    for i in avail:
                        acc += ww[i]
                        if acc >= u: pick = i; break
                    chosen.append(perm[pick]); avail.remove(pick)
                idx.append(chosen)
            return idx
        print("\n[Z] generator Z(E=256,k=8): mean D (distinct experts), mean max m_e, mean max experts on one core under a static e mod 8 map; 2000 seeds")
        for t in (1, 4, 16):
            for s in (0.0, 1.0, 1.5):
                Ds = []; Ms = []; Bs = []
                for seed in range(2000):
                    idx = gen(E, k, t, s, seed)
                    cnt = {}
                    for row in idx:
                        for e in row: cnt[e] = cnt.get(e, 0) + 1
                    Ds.append(len(cnt)); Ms.append(max(cnt.values()))
                    bins = [0]*8
                    for e in cnt: bins[e % 8] += 1
                    Bs.append(max(bins))
                print(f"     t={t:2d} s={s:.1f}: D = {sum(Ds)/len(Ds):6.2f}  (min {min(Ds)}, max {max(Ds)})  max m_e = {sum(Ms)/len(Ms):5.2f}  static-map max/core = {sum(Bs)/len(Bs):5.2f}  ideal D/8 = {sum(Ds)/len(Ds)/8:5.2f}")

# ------------------------------------------------------------------ §8 table ------------------------
DTAB = {  # D per (t, family): uniform = min(k*t, E) by definition; Zipf = rounded generator means (see [Z] above)
    (1, "uniform"): 8,  (1, "Zipf(1.0)"): 8,  (1, "Zipf(1.5)"): 8,
    (4, "uniform"): 32, (4, "Zipf(1.0)"): 25, (4, "Zipf(1.5)"): 20,
    (16, "uniform"): 128, (16, "Zipf(1.0)"): 68, (16, "Zipf(1.5)"): 45,
}
def table8():
    print("\n[T8] K=Ne=4096, k=8, E=256 | W8 serial (anchored) / W8 ping-pong | W4 i4x i4 conditional")
    print("| t | routing | D | W8 bytes MiB | W8 step us (serial) | W8 GB/s | tokens/ms | ping-pong step us | GB/s | W4 bytes MiB | W4 step us | W4-GB/s |")
    for t in (1, 4, 16):
        for fam in ("uniform", "Zipf(1.0)", "Zipf(1.5)"):
            D = DTAB[(t, fam)]
            s8 = stepSer(K, Ne, D, t); p8 = stepPP(K, Ne, D, t); s4 = step4(K, Ne, D, t)
            tok = (2 * t * 100_000_000 + s8) // (2 * s8)  # tokens per ms in hundredths: t * 1e6 ns / step_ns * 100
            print(f"| {t} | {fam} | {D} | {D*bX(K,Ne)//MiB} | {usR(s8)} | {t10(rateSer(K,Ne,D,t))} | {tok//100}.{tok%100:02d} | {usR(p8)} | {t10(ratePP(K,Ne,D,t))} | {D*b4X(K,Ne)//MiB} | {usR(s4)} | {t10(rate4(K,Ne,D,t))} |")
if __name__ == "__main__":
    table8()
    print("[T8b] single-hot adversarial = D = k = 8 at every t: step", usR(stepSer(K,Ne,8,16)), "us at t=16 ->", t10(rateSer(K,Ne,8,16)), "GB/s; tokens/ms (hundredths)", (2*16*100_000_000 + stepSer(K,Ne,8,16))//(2*stepSer(K,Ne,8,16)))
    # regression vs dense-equivalent and misc
    dense2 = 2 * T_DENSE
    print("[M11] dense-equivalent 16 MiB/core anchored =", dense2, "ns ; MoE headline", stepSer(K,Ne,8,1), "-> delta", stepSer(K,Ne,8,1) - dense2, "ns = A lifts", (8*aCore(K) - 128*KiB)*10//L_SER, "+ fixed", FIXED)
    print("[M12] overflow bound: 127*127*4096 =", 127*127*4096, "; x22 =", 22*127*127*4096, "< 2^31 =", 2**31, ":", 22*127*127*4096 < 2**31, "; K=7168: 127*127*7168*18 =", 127*127*7168*18, "<2^31:", 127*127*7168*18 < 2**31)
    print("[M13] f32-exact bound 2^24 =", 2**24, "; 6 regions x 32 KiB =", 6*32, "KiB")
    print("[M14] expert-group knob: A lift fraction G=1", t10(pct(aCore(K), sliceB(K,Ne))), "% G=2", t10(pct(aCore(K), 2*sliceB(K,Ne))), "% G=4", t10(pct(aCore(K), 4*sliceB(K,Ne))), "% ; serial rate with A lifts /G:",
          {G: t10(rateT(8*bX(K,Ne), max(8*(sliceB(K,Ne)+aCore(K)//G)*10//L_SER + tMma(K,Ne,8) + tRes(K,Ne,8), tDdr(K,Ne,8,1)) + FIXED)) for G in (1,2,4,8)})
    print("[M15] per-expert serial time", tSerial(K,Ne,1), "ns ; per-expert DDR share", sliceB(K,Ne)*80//R_DDR, "ns ; drain 32 KiB at 10 GB/s", 32*KiB*10//100, "ns =", t10(pct(32*KiB*10//100, tSerial(K,Ne,1))), "% if exposed")
    print("[M16] dispatch: t*k iterations at sigma_d: ", {sd: (8*sd, 128*sd) for sd in (10, 50, 100, 250)}, "ns (t=1, t=16); A copy 64 KiB at 22.5 =", 64*KiB*10//225, "ns; host pre-pass >= T_launch", T_LAUNCH, "=", t10(pct(T_LAUNCH, stepSer(K,Ne,8,1))), "% of headline step")
    print("[M17] small-shape wall: (2048,512,4) step", stepSer(2048,512,4,1), "ns +91 us ->", t10(rateT(4*bX(2048,512), stepSer(2048,512,4,1)+T_LAUNCH)), "; host pre-pass would be", t10(pct(T_LAUNCH, stepSer(2048,512,4,1))), "% of the step")
    print("[M18] W-dyn k=4,10 at t=1:", t10(rateW(K,Ne,4,1)), t10(rateW(K,Ne,10,1)), "; W C slab", 16*Ne*4//KiB, "KiB = L0C", L0C//KiB, "(errata 14)")
    print("[M20] K-split: chainK", chainK(K,Ne), "deltaA", deltaA(K,Ne), "ns ; margin (stepK - stepS) ns:", {(t,D): marginK(K,Ne,D,t) for (t,D) in ((1,8),(4,32),(4,20),(16,128),(16,68),(16,45))})
    print("[M19] i32 epilogue exactness oracle: |a|,|b|<=15, 2 chunks x 128 k:", 2*128*15*15, "< 2^24 ; per-step vector epilogue at t=16:", 128*5*512*10//R_VEC + 128*8192*10//R_VEC, "ns incl. 16-row Sub per expert (D=128)")
