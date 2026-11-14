# CHEATSHEET — distilled compute & bandwidth witchery for this machine (2026-11-14)

Provenance: a two-stage research round — (1) a primary-source audit of the
2025–26 mathematics landscape (the ω ≤ 9/4 line, finite bilinear schemes,
transform/codec theory) plus an INDEPENDENT roofline derivation of this
machine; (2) a 40-finding sweep of LLM inference techniques (quantization,
KV compression, lossless codecs, speculative decoding, MoE compression).
Raw reports archived outside this repo; this file is the graded
distillation against OUR constants (HW-MAP + the round-7 anchors).

## 0. The external roofline VALIDATES our measured corpus

The audit's independent derivation (before reading our numbers): int8
ridge ≈ **48 OPs/byte** against the ~170 GB/s wall → batch-1 decode at
**4–8 % of compute peak, hard-bound by weight bytes**; per-element vector
dequant caps any unpacked format at **~12 %** of the W4 stream rate;
**≤ 12–24 concurrent rows ride free** (our measured m ≤ 16 flat region);
KV traffic reaches parity with W4 weights at **~30 k tokens** (our
measured attention-bound flip at 32k). Four independent agreements with
HW-MAP — the wall is real, measured twice, once by us.

## 1. Guardrails (kills — do not re-litigate)

- **G1** ω ≤ 9/4, ω < 2.3711…, and every laser-method bound: real
  (Lean-checked in places) but asymptotic, exact-field-arithmetic,
  non-constructive or galactic (explicit base sizes are astronomical).
  Hardware gets nothing. Cite as negative guardrails only.
- **G2** Sub-n log n DFT claims: precision-illusion model (unbounded
  complex arithmetic, unit-cost indexing). Ignore.
- **G3** Strassen / rank-48 / Laderman tiles in decode: GEMV has no n³
  reuse; pre-additions widen int8 operands (int9/int10 per level) and the
  best 4×4 rank-48 schemes need complex numbers or ½-coefficients.
  Their only theoretical home is compute-bound prefill — and they break
  int8 exactness there too.
- **G4** Generic-CVP / large-LUT VQ codebooks: NP-hard decode class,
  codebooks thrash the ~192 KiB scratchpad. Structured lattices/trellises
  only, and only under G6.
- **G5** Never accumulate integer products in f16 (not exact even at
  k = 1 full-range); f32 exact only to k ≤ 1 024; int32 exact to
  k ≤ 2^17. (Matches our i32-saturation rows.)
- **G6** No variable-length entropy decode (Huffman/rANS) on the vector
  unit in the decode path: per-element decode = ~12 % of the wall. Any
  compressed format must be consumed natively by the matrix unit,
  unpacked with ≥ 4–8 elements per lane-op, or fused into the load path.
- **G7** QJL-style 1-bit residual at ≤ 3 bits: softmax convexity turns
  unbiased inner products into biased attention (Jensen); benchmark
  before adopting.
- **G8** Magnitude-activation sparsity (column skipping): breaks 16-wide
  tiles — weak fit here.

## 2. Candidates, ranked for THIS machine (gold = bytes cut, exactness kept)

| # | technique | class | gain arithmetic vs our anchors | exactness | status here | first probe |
|---|---|---|---|---|---|---|
| 1 | **ZipServ-class triple-bitmap lossless weight packing** — f16 tiles → 3 aligned bitmaps + base-exponent, branch-free unpack | B/T, EXACT | ~30 % off EVERY f16 stream = ~1.4× effective wall; also KV-f16 and capacity (a 333 GB-class model → ~235 GB) | **bit-exact** | NEW — the only exact-class byte cut | encode our f16 streams; unpack rate in the scratchpad vs the 40-lane budget (must meet G6: packed, branch-free) |
| 2 | **Block-16 Hadamard rotations (QuaRot/SpinQuant class)** — outlier smoothing, offline-fusable into weights; online cost lands on activations only | B/T enabler | turns W4/W2 from quality-lossy into near-neutral; multiplies with every weight lever below | transform exact, quant bounded | NEW — folds into the (existing) requant seat | rotate + requant a real tensor set; measure outlier tails before/after |
| 3 | **KIVI-class KV 2–4 bit, asymmetric (K per-channel, V per-token) + f16 rolling tail (R≈128)** | B/T | KV term ×2–4 beyond our KV-int8 readings; the audit's KV-parity-at-30k arithmetic says this is THE lever past 32k | quality-loss (2-bit hurts long-CoT reasoning — Kitty); 4-bit near-neutral | EXTENDS our KV-int8 cells | 4-bit first: extend the fused attention kernel's KV intake; PPL + our exactness battery |
| 4 | **W4A8 co-design (QServe/QoQ class)** — progressive group quant, unpack fused/packed, KV4 | B/T | proven 3.5× on a GDDR-walled part (L40S); our W4 anti-quant route is this class | quality-loss, small | CUT (running queue) — this validates the route + adds the activation-side recipe | the standing W4 gate |
| 5 | **Quest/DuoAttention query-aware page selection** — bounding-box pages, retrieval vs streaming heads | B/T at long ctx | our per-span page tables + 256 KiB pages are the substrate; 2–5× on the attention term at ≥ 32k | near-lossless | NEW — rides the existing page infra | per-page score histograms on real traces → selectable fraction |
| 6 | **MoE expert compression (D2-MoE / delta-vs-shared / dedup class)** | B@R + B/T | expert bytes 1.5–2× on top of W4; hot/cold tiers already modeled (our two-tier cells) | quality-loss, small | NEW — pairs with the expert kernel's arena | expert-similarity census on the A3B-class + GLM-class checkpoints |
| 7 | **MiniCache adjacent-layer KV merge** | B/T | KV ×~5 at 4-bit, near-lossless; changes the cache contract (merge at load? at serve?) | near-lossless | NEW | offline merge quality sweep first (no kernel work until quality holds) |
| 8 | **Speculative trees sized ≤ 16 rows (EAGLE-3/MTP class)** | OVERLAP (free rows) | the m ≤ 16 flat region makes verification ~free; 2–6.5× wall-clock at high acceptance | **lossless** (distribution-preserving) | NEW — needs a draft path (dense small draft on spare capacity) | draft acceptance-rate measurement on our traces before any kernel |
| 9 | **CLSA/MLA-class cross-layer KV sharing / latent KV** | B/T, architecture | up to 7.6× decode at 128k — but needs training-time architecture change | trained-in | PARKED (the latent-KV kernel item already sits with the MLA-class model note) | model-class decision, not a kernel decision |
| 10 | **Radix prefix cache (SGLang class)** | serving system | prefix reuse = free bytes for multi-user serving | exact | NEW — serving-layer | usage-trace analysis (how much prefix overlap do our workloads have?) |

## 3. What the sweep changes about our ranking

- The **exact class exists**: lossless bitmap packing (#1) is the only
  candidate that cuts bytes with ZERO quality debate — it stacks under
  W4 (pack the int4 streams? the codec is exponent-targeted; probe) and
  on KV-f16 arms.
- The **W4 route we already cut is the sweep's #4** — independently
  validated, with the activation-side recipe (progressive groups,
  smooth-attention) attached for the implementation season.
- Past 32k the lever ranking flips to **KV-side** (#3, #5, #7) — our own
  measured regime boundary, now with three independent techniques aimed
  at it.
- Speculative decoding (#8) is the only OVERLAP-class lever and our flat
  region was measured for it before we knew the literature agreed.
