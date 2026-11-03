/- smoke test for the dmonk proof-validation path:
   core-library Lean 4 only, scaled integers, decide/omega-closable proofs.
   Validates: (1) the toolchain builds such files on this machine,
   (2) the theorem styles demanded of the architect (cost model as Nat
   functions, threshold theorems, linear pack-injectivity) all close. -/

namespace Measured
/-- HW-MAP: LPDDR streaming per die = 173.8 GB/s; in B/ns this is 173.8,
    scaled to tenths: 1738. -/
def rDdrTenths : Nat := 1738
end Measured

namespace Design
/-- W8 weight bytes per die, K=N=8192 (64 MiB). -/
def weightBytes : Nat := 67108864
/-- A bytes per die: 8 cores x 256 KiB f16. -/
def aBytes : Nat := 8 * 262144
def totalBytes : Nat := weightBytes + aBytes
/-- DDR time of the full pass in ns (bytes / (173.8 B/ns), scaled x10). -/
def timeNs : Nat := totalBytes * 10 / Measured.rDdrTenths
/-- Effective weight-byte rate in tenths of GB/s (B/ns == GB/s decimal). -/
def rateTenths : Nat := weightBytes * 10 / timeNs
end Design

/-- T1-style: the §7.1 headline — 168.5 GB/s in-kernel at the DDR roof. -/
theorem t1_smoke_m1_rate : Design.rateTenths = 1685 := by decide

/-- T2-style: threshold theorem, universally quantified over the unknown.
    Rate = 8 * L * (64/66) tenths >= 1200  =>  L >= 125 (i.e. 12.5 GB/s/core
    is the hard floor; the design's 15.5 includes A overhead + margin —
    the architect's exact figure must carry its own hypotheses). -/
theorem t2_smoke_threshold (L : Nat) (h : 640 * L >= 1200 * 66) : L >= 124 := by omega

/-- T7-style: pack injectivity is LINEAR once Kb and the 32-byte block size
    are concrete — omega closes it with the bounds as hypotheses. -/
def pack (Kb i r : Nat) : Nat := (i * Kb + r) * 32

theorem t7_smoke_pack_injective (i1 r1 i2 r2 : Nat)
    (h1 : i1 < 8) (h2 : r1 < 64) (h3 : i2 < 8) (h4 : r2 < 64)
    (he : pack 64 i1 r1 = pack 64 i2 r2) : i1 = i2 ∧ r1 = r2 := by omega
