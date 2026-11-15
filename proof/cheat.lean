/-
CHEAT-MATH — the arithmetic layer of CHEATSHEET.md.

Condensed, source-free statements: no technique names, no citations, by
design — each entry stands on the math and (where ours) on HW-MAP rows.
Everything here is a MATH fact decided by the kernel (decide / omega /
native_decide); none of it is a device measurement. Core Lean 4 only,
imports nothing beyond Init, compiles standalone with `lean cheat.lean`.
-/

namespace Cheat

/- §A — exact accumulation of integer products.

  An int8-by-int8 product is bounded by 2^14 in magnitude, so a k-term
  dot product is bounded by k * 2^14. int32 is exact up to 2^31, f32
  represents integers exactly only to 2^24, f16 only to 2^11 — and a
  full-range int8 product already exceeds 2^11, so f16 accumulation is
  never exact. Each pre-addition level of a fast-bilinear scheme widens
  operands by one bit. -/

theorem prod_abs_bound (m n : Nat) (h1 : m ≤ 128) (h2 : n ≤ 128) : m * n ≤ 16384 :=
  Nat.le_trans (Nat.mul_le_mul h1 h2) (by decide)

theorem int32_exact_iff (k : Nat) : k * 16384 < 2147483648 ↔ k < 131072 := by omega

theorem f32_exact_iff (k : Nat) : k * 16384 ≤ 16777216 ↔ k ≤ 1024 := by omega

theorem f16_not_exact : 2048 < 127 * 127 := by decide

theorem preadd_widen2 (a b c d : Int)
    (ha : -128 ≤ a) (ha' : a ≤ 127) (hb : -128 ≤ b) (hb' : b ≤ 127)
    (hc : -128 ≤ c) (hc' : c ≤ 127) (hd : -128 ≤ d) (hd' : d ≤ 127) :
    -512 ≤ (a + b) + (c + d) ∧ (a + b) + (c + d) ≤ 508 := by omega

/- §B — roofline arithmetic on the stated engine constants
  (one 16×16×16 int8 block per cycle = 8192 OPs, 170 B/ns stream,
  40 vector lanes/cycle). -/

theorem ridge_bounds : 48 * 170 < 8192 ∧ 8192 < 49 * 170 := by decide

/-- Arithmetic intensity reaches the ridge at ~24 concurrent rows (2
OPs/byte-weight, W8-class) or ~12 (4 OPs/byte-weight, W4-class); one row
past each crosses it. -/
theorem free_rows :
    2 * 24 < 49 ∧ 4 * 12 < 49 ∧ 2 * 25 ≥ 49 ∧ 4 * 13 ≥ 49 := by decide

/-- A 16-row verification tree rides free on the 2-OPs/byte format but
NOT on the 4-OPs/byte one. -/
theorem tree16 : 2 * 16 < 49 ∧ 4 * 16 ≥ 49 := by decide

/-- KV bytes per decoded token, 8B-class shape (32 layers, 8 KV heads,
d = 128, f16): exactly 128 KiB. -/
theorem kv_per_token : 2 * 8 * 128 * 2 * 32 = 131072 := by decide

/-- KV traffic reaches parity with a 4 GiB weight set at 2^15 tokens
(= 32 Ki); at real sizes ≈ 30 k — past that, KV bytes dominate. -/
theorem parity_ctx : 4294967296 / 131072 = 32768 := by decide

/-- A 256-cube int8 prefill step moves 128 KiB of operands for 33.5 M
OPs: 256 OPs/byte, 5.33× the 48.2 ridge — prefill is compute-bound. -/
theorem prefill_intensity : 33554432 / 131072 = 256 ∧ 256 = 5 * 48 + 16 := by decide

/-- A 16×16 output tile needs ceil(256/40) = 7 epilogue cycles per
1-cycle MAC block, so k ≥ 7 × 16 = 112 hides it; the rule is k ≥ 128. -/
theorem epilogue : 256 = 40 * 6 + 16 ∧ 7 * 16 = 112 ∧ 112 ≤ 128 := by decide

/-- Per-element vector unpacking (40 G elem/s) against the W4 stream
supply (340 G elem/s): under 12% of the wall. -/
theorem dequant_cap : 40 * 25 < 340 * 3 := by decide

/- §C — fixed-plane packing.

  A 16-bit word cut into any fixed 2^k-aligned disjoint planes
  recombines by pure addition: the packing is an identity, hence
  bit-exact by construction (the 9/3/4 split below is the
  shared-exponent-plus-three-planes shape). -/

theorem bitplanes_recombine (x : Nat) (h : x < 65536) :
    x % 512 + (x / 512 % 8) * 512 + (x / 4096 % 16) * 4096 = x := by omega

/- §D — the ±1 orthogonal rotation.

  The 4×4 ±1 matrix below is a Hadamard matrix: rows are orthogonal,
  each of norm 4. Scaled by 1/2 it is exactly orthogonal; entries are
  ±1 so the transform is multiplier-free (adds only) and fuses into a
  weight stream offline, leaving online cost on activations. -/

def dot (v w : List Int) : Int := (v.zipWith (fun a b => a * b) w).sum

def w0 : List Int := [1, 1, 1, 1]
def w1 : List Int := [1, -1, 1, -1]
def w2 : List Int := [1, 1, -1, -1]
def w3 : List Int := [1, -1, -1, 1]

theorem orth4 :
    dot w0 w0 = 4 ∧ dot w1 w1 = 4 ∧ dot w2 w2 = 4 ∧ dot w3 w3 = 4 ∧
    dot w0 w1 = 0 ∧ dot w0 w2 = 0 ∧ dot w0 w3 = 0 ∧
    dot w1 w2 = 0 ∧ dot w1 w3 = 0 ∧ dot w2 w3 = 0 := by decide

theorem orth2 :
    dot [1, 1] [1, 1] = 2 ∧ dot [1, 1] [1, -1] = 0 ∧ dot [1, -1] [1, -1] = 2 := by decide

/- §E — modular reconstruction.

  Residues mod 15 and mod 16 (coprime, product 240) determine every
  value below 240: a pair of exact int8-GEMMs per modulus recovers the
  wide product. At ~8 bits per modulus, 16 moduli cover 128 bits ≥ 123
  (the wide-product bound) and 15 do not. -/

theorem crt_15_16 :
    (List.range 240).all (fun x =>
      (List.range 240).all (fun y =>
        !(x % 15 == y % 15) || !(x % 16 == y % 16) || (x == y))) = true := by
  native_decide

theorem moduli_bits : 15 * 8 = 120 ∧ 16 * 8 = 128 ∧ 120 < 123 ∧ 123 ≤ 128 := by decide

/- §F — the exponent landscape, as ordered constants only (×10⁹).

  Semantics live in CHEAT-MATH.md: every bound in this chain is
  asymptotic, exact-field-arithmetic, and non-constructive or galactic —
  a negative guardrail for fixed-function hardware, never a speedup. -/

theorem omega_order :
    2250000000 < 2371054886 ∧ 2371054886 < 2371159238 ∧ 2371159238 < 2371177000 ∧
    2371177000 < 2371339000 ∧ 2371339000 < 2371552000 ∧ 2371552000 < 2372000000 ∧
    9 * 1000000000 = 4 * 2250000000 := by decide

/-- Finite bilinear schemes trade multiplications for additions: rank 7
vs 8 (2×2), 23 vs 27 (3×3), 48/49 vs 64 (4×4). The best 4×4 rank-48
schemes need half-integer or complex coefficients — both off-contract
for exact int8. -/
theorem rank_savings : 7 < 8 ∧ 23 < 27 ∧ 48 < 64 ∧ 49 < 64 := by decide

/-- Quantization distortion floors fall by exactly 4× per added bit. -/
theorem pow_floor (b : Nat) : 4 ^ (b + 1) = 4 * 4 ^ b := by
  rw [Nat.pow_succ, Nat.mul_comm]

end Cheat
