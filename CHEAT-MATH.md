# CHEAT-MATH — the arithmetic layer of CHEATSHEET (2026-11-15)

Provenance: the same two research stashes CHEATSHEET grades (a
primary-source mathematics audit + an inference-technique sweep, both
archived outside this repo). This file is deliberately **source-free**:
no technique names, no citations — every statement stands on the math
and, where a constant is ours, on the HW-MAP row it traces to. Statements
marked **MATH** are machine-checked in `proof/cheat.lean` (kernel-decided,
core Lean only); **PRIOR** rows are literature arithmetic quoted at face
value and used only as guardrails.

## A. Exact accumulation (MATH — `Cheat.prod_abs_bound … preadd_widen2`)

int8·int8 products are bounded by 2^14, so a k-term dot is ≤ k·2^14:
**int32 exact ⟺ k < 2^17**; **f32 exact ⟺ k ≤ 2^10 = 1024** (exact
integers to 2^24); **f16 never** (127² = 16129 > 2^11 already at k = 1).
Each fast-bilinear pre-addition level widens operands one bit
(int8 → int9 → int10). Grounds CHEATSHEET G5; the kernel-side reason the
wide-cap fold and i32 accumulation are shaped as they are.

## B. Roofline arithmetic at DIE level (MATH — `Cheat.ridge_die_bounds … `unpack_share`)

The die's MEASURED 17.8 T-OP/s against its 173.8 GB/s stream → **ridge
strictly between 102 and 103 OPs/byte** (round-4 C-15 correction: the
earlier 48–49 paired ONE core's 8 192 OPs/cycle with the whole die's
bytes — a unit mix). Arithmetic intensity is 2M OPs/B (8-bit weights)
or 4M (4-bit): rows ride free to **M = 51 / 25**, one past crosses; a
**16-row tree is free on BOTH** formats (64 ≤ 102) — the shape behind
CHEATSHEET #8 and our measured m ≤ 16 flat region, without the
artificial 4-bit cliff. The vector lane budget (8 × 43.2 = 345.6 G
lane-ops/s) sits just under the 4-bit stream's 347.6 G elem/s — **at
most one lane-op per element**; the MEASURED 5-pass unpack (42 GB/s =
84 G elem/s) is **24 % of the stream wall** (not "< 12 %" — that was
the unit-mix number). KV for an 8B-class shape is exactly **128
KiB/token** (2·8·128·2·32), reaching parity with a 4 GiB weight set at
**2^15 = 32 Ki tokens** (≈30 k at real sizes) — arithmetic only:
whether a regime flips at any context is a per-shape measured question,
not this identity. A 256-cube prefill step is **256 OPs/byte ≈ 2.5×
the die ridge** (compute-bound); a 16×16 output tile needs **k ≥ 112**
(rule: 128) to hide its epilogue at 40 lanes.

## C. Fixed-plane packing (MATH — `Cheat.bitplanes_recombine`)

A 16-bit word cut into fixed 2^k-aligned disjoint planes (shown for the
9/3/4 shared-exponent-plus-three-planes shape) **recombines by pure
addition for every value** — the packing is an identity, hence bit-exact
by construction, with branch-free recombination. The kernel-side core of
CHEATSHEET #1. PRIOR rows that bound it: exponent fields carry ~2.6–3
bits of entropy → lossless ratio ceiling **≈ 16/10.6 = 1.51×**, so past
~1.3–1.5× any further byte cut must be lossy.

## D. The ±1 orthogonal rotation (MATH — `Cheat.orth2`, `Cheat.orth4`)

The 2×2 and 4×4 ±1 matrices are Hadamard: rows orthogonal (verified),
**multiplier-free** (adds only), **exactly representable** in integer /
f16 up to the 1/√n scaling, and **fusable offline into weights** so the
online transform cost lands on activations only. The enable behind every
sub-4-bit row in CHEATSHEET (#2–#4, #6). PRIOR: the n-point fast
transform is n·log₂n adds (4 stages at block-16).

## E. Modular reconstruction (MATH — `Cheat.crt_15_16`, `moduli_bits`)

Residues mod 15 and mod 16 determine every value < 240 (exhaustively
decided) — two exact small-modulus GEMMs recover a wide product; at ~8
bits per modulus **16 moduli cover the 123-bit wide-product bound and 15
do not**. The escape hatch if wide-precision GEMM is ever needed on an
int8 engine (CHEATSHEET P7 analogue). PRIOR: measured moduli counts for
full-precision emulation cluster at 14–16.

## F. The exponent landscape, as constants only (MATH — `omega_order`, `rank_savings`)

Ordered (×10⁹): 2250 < 2371.054886 < 2371.159238 < 2371.177 <
2371.339 < 2371.552 < 2372, with 9/4 = 2250/1000 exact. **PRIOR
semantics, load-bearing**: every bound in the chain is asymptotic,
exact-field-arithmetic, non-constructive or galactic (explicit bases are
2^((1/ε)^O(1))) — a negative guardrail for fixed-function hardware,
never a speedup (G1). Sub-n·log n transform claims ride a model of
unbounded-precision arithmetic with unit-cost indexing (G2). Finite
bilinear ranks: 7/8 (2×2), 23/27 (3×3), 48 & 49/64 (4×4) — but rank-48
needs half-integers or complex coefficients, and the pre-add widening of
§A breaks int8 exactness (G3). Distortion floors fall **exactly 4× per
added bit** (`Cheat.pow_floor`); at ≤ 3 residual bits, softmax convexity
turns unbiased inner products into biased attention (Jensen) — PRIOR,
benchmark before adopting (G7).

## Reading map to CHEATSHEET

G1–G3, G5–G7 → §F, §A, §B here; #1 → §C; #2–#4, #6 → §D; #3/#5/#7 → §B
(KV parity); #8 → §B (free rows); P7-analogue → §E. The lossless and
distortion ceilings of CHEATSHEET §0/§2 quote §C/§F PRIOR rows.
