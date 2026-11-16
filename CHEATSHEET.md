# CHEATSHEET — distilled compute & bandwidth witchery for this machine (2026-11-14)

Provenance: a two-stage research round — (1) a primary-source audit of the
2025–26 mathematics landscape (the ω ≤ 9/4 line, finite bilinear schemes,
transform/codec theory) plus an INDEPENDENT roofline derivation of this
machine; (2) a 40-finding sweep of LLM inference techniques (quantization,
KV compression, lossless codecs, speculative decoding, MoE compression).
Raw reports archived outside this repo; this file is the graded
distillation against OUR constants (HW-MAP + the round-7 anchors). The
arithmetic behind every guardrail and row is stated source-free and
machine-checked in `CHEAT-MATH.md` (`proof/cheat.lean`).

## 0. The external roofline vs our measured corpus (round-4 corrected)

The audit's independent derivation, re-graded against OUR errata
(round-4 C-15/C-17: the earlier "four independent agreements" counted
our own inlined constants three times and paired one core's OP rate
with the die's bytes): the die-level ridge is **102 OPs/byte**
(17.8 T-OP/s ÷ 173.8 GB/s) → batch-1 decode at the MEASURED **12.5 %**
of compute peak [**challenge:** 12.5 % is the matrix unit's ISSUE occupancy against the retired 487 µs stream (16.0 % at the shipped
174.6); the useful compute at m = 1 is 2 / 102.4 = 1.96 % of this ridge figure — Chk.N1_occupancy], hard-bound by weight bytes; per-element vector unpack
is the MEASURED **24 %** of the 4-bit stream rate (one lane-op per
element is the whole budget); **≤ 51 / 25 concurrent rows ride free**
(8-bit / 4-bit; our measured m ≤ 16 flat region sits well inside);
KV-parity with W4 weights at **2^15 tokens** is arithmetic, and whether
a regime flips at any context is a per-shape measured question (our
32k MoE cell is weights-bound). The wall is real and measured — once,
by us, at die level.

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
  unit in the decode path: per-element decode = the MEASURED 24 % of
  the 4-bit wall (one lane-op per element is the entire budget). Any
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
| 1 | **ZipServ-class triple-bitmap lossless weight packing** — f16 tiles → 3 aligned bitmaps + base-exponent, branch-free unpack | B/T, EXACT | round-4 re-grade (C-17): HERE the weight streams are int8 (no exponent field); a vector-side unpack emits f16 at ≈ 1.0× the wall and the loader caps at 212 GB/s ≤ 1.25× even with a free unpack; the only f16 stream (KV) is dominated by the MEASURED K-int8 (2.13×) — capped ≈ 1.0–1.25× on this machine (the packing identity itself is TRUE — CHEAT-MATH §C) | **bit-exact** | CAPPED HERE — exact-class byte cut only where f16 streams exist | host kill-check FIRST (a clean kill is the deliverable); only then any die time |
| 2 | **Block-16 Hadamard rotations (QuaRot/SpinQuant class)** — outlier smoothing, offline-fusable into weights; online cost lands on activations only | B/T enabler | turns W4/W2 from quality-lossy into near-neutral; multiplies with every weight lever below | transform exact, quant bounded | NEW — folds into the (existing) requant seat | rotate + requant a real tensor set; measure outlier tails before/after |
| 3 | **KIVI-class KV 2–4 bit, asymmetric (K per-channel, V per-token) + f16 rolling tail (R≈128)** | B/T | round-4 re-grade (C-17): erratum 12 — no i4 path on this part; a 4-bit KV unpacked at the ~42 GB/s int4 aggregate costs ≈ 1.04× KV-int8's time per extent, not ×2–4 — capped ≈ 1.04× HERE [**challenge:** 1.04× is a time COST — 4 % slower than KV-int8 per extent (1.69–1.78× slower than the production f16 stream); on this machine the row buys memory, not time — Chk.Z1_kv4] unless a native 4-bit intake is ever measured; the KV-parity-at-2^15 arithmetic itself stands | quality-loss (2-bit hurts long-CoT reasoning — Kitty); 4-bit near-neutral | EXTENDS our KV-int8 cells — RE-PRICE before it takes a card | 4-bit first: extend the fused attention kernel's KV intake; PPL + our exactness battery |
| 4 | **W4A8 co-design (QServe/QoQ class)** — progressive group quant, unpack fused/packed, KV4 | B/T | proven 3.5× on a GDDR-walled part (L40S); round-4 re-grade (C-17): HERE W4 rides as int8 at load — no stream-byte cut (2× memory) — ≈ 1× until the cube path lands; the activation-side recipe still attaches | quality-loss, small | CUT (running queue) — the standing W4 gate is the decider, not this row | the standing W4 gate |
| 5 | **Quest/DuoAttention query-aware page selection** — bounding-box pages, retrieval vs streaming heads | B/T at long ctx | our per-span page tables + 256 KiB pages are the substrate; 2–5× on the attention term at ≥ 32k | near-lossless | NEW — rides the existing page infra | per-page score histograms on real traces → selectable fraction |
| 6 | **MoE expert compression (D2-MoE / delta-vs-shared / dedup class)** | B@R + B/T | expert bytes 1.5–2× on top of W4; hot/cold tiers already modeled (our two-tier cells) | quality-loss, small | NEW — pairs with the expert kernel's arena | expert-similarity census on the A3B-class + GLM-class checkpoints |
| 7 | **MiniCache adjacent-layer KV merge** | B/T | KV ×~5 at 4-bit, near-lossless; changes the cache contract (merge at load? at serve?) | near-lossless | NEW | offline merge quality sweep first (no kernel work until quality holds) |
| 8 | **Speculative trees sized ≤ 16 rows (EAGLE-3/MTP class)** | OVERLAP (free rows) | the m ≤ 16 flat region makes verification ~free; 2–6.5× wall-clock at high acceptance | **lossless** (distribution-preserving) | NEW — needs a draft path (dense small draft on spare capacity) | draft acceptance-rate measurement on our traces before any kernel |
| 9 | **CLSA/MLA-class cross-layer KV sharing / latent KV** | B/T, architecture | up to 7.6× decode at 128k — but needs training-time architecture change | trained-in | PARKED (the latent-KV kernel item already sits with the MLA-class model note) | model-class decision, not a kernel decision |
| 10 | **Radix prefix cache (SGLang class)** | serving system | prefix reuse = free bytes for multi-user serving | exact | NEW — serving-layer | usage-trace analysis (how much prefix overlap do our workloads have?) |

## 3. What the sweep changes about our ranking

- The **exact class exists as arithmetic** — the packing identity is
  machine-checked TRUE (CHEAT-MATH §C) — but on THIS machine its byte
  cut is capped ≈ 1.0–1.25× (row #1 re-grade): no f16 weight streams,
  loader-capped unpack, KV-f16 dominated by measured K-int8.
- The **W4 route we already cut is the sweep's #4** — same class, with
  the activation-side recipe (progressive groups, smooth-attention)
  attached for the implementation season; here its byte cut rides
  entirely on the standing W4 cube-path gate.
- At long context the lever ranking leans **KV-side** (#3, #5, #7) —
  the 1M cells are the measured long-context anchors; the 2^15
  KV-parity arithmetic frames where the term starts to dominate.
- Speculative decoding (#8) is the only OVERLAP-class lever and our flat
  region was measured for it before we knew the literature agreed.
