# PROMPT-8 — RAW research sweep: compute & bandwidth tricks for LLM inference on a bandwidth-walled part

You are a RESEARCH session with web access. Pure sweep: find what's out
there, report it faithfully with sources. You are NOT grading against any
local corpus — a separate distillation step does that later. Your output
is raw material.

The only context you need (the eventual consumer's hardware, so your
"transfer smell" field makes sense):

> Target part: a per-die ~165–175 GB/s sustained DDR stream (no HBM),
> ~86 GB usable per die, 8 dies per fleet. Per core: ~192 KiB vector
> scratchpad, 64+64 KiB L0A/L0B, 256 KiB L0C, a FIXED-FUNCTION int8/f16
> matrix unit (16×16×k tiles — no arbitrary instruction substitution, no
> shader units), vector unit ~40 lanes/cycle. Decode at batch-1 is
> BYTES-bound (weights + KV streamed per token at the DDR wall; the
> matrix unit is already fed at ~85% of the wall). Prefill is
> compute-shaped. Host round-trip ~12 µs.

## Mission A — compute / arithmetic witchery

Search 2024–2026 papers, preprints, and engineering posts for:
machine-discovered matmul kernels (AlphaTensor / AlphaEvolve class) and
their measured wins on FIXED-FUNCTION or integer-only units; practical
Strassen-family variants at small tile sizes; low-rank and structured
sparsity APPLIED AT INFERENCE; rotation/Hadamard-based quantization
(QuaRot, SpinQuant, QuIP# class) — smoothing outliers to enable
int4/int2; sub-4-bit weight schemes (ternary, BitNet-class, 2-bit
codebooks, Marlin/AWQ/Marlin-style repacking); exact low-bit
accumulation tricks; speculative decoding advances (EAGLE-2/3, Medusa,
self-speculative, multi-token prediction) with real t/s numbers;
softmax-free / linear-attention families (Mamba-2, RWKV-7, hybrids,
gated deltanet) and their inference-cost math; anything genuinely new in
"matmul multiplication breakthrough" news — get the PRIMARY source, not
the press release.

## Mission B — bandwidth witchery (the main prize)

KV-side: latent-compression attention (MLA-class and successors —
exact math of what hides in the KV term); KV-cache int8/int4/int2 with
BOUNDED error (measured perplexity deltas, not vibes); cache eviction /
merging / pooling (H2O, SnapKV, PyramidKV, KIVI, streaming-LLM class)
with long-context byte savings; per-layer heterogeneous KV; shared/pooled
KV for grouped-query models. Weight-side: below-4-bit weights with
rotations; palette/codebook weight sharing; MoE expert deduplication /
merging / similarity exploitation at load time; compressing STATIC
weight streams with dictionary/LZ-class schemes decompressed close to
the compute unit (weights never change — compress once); delta-quantized
expert layouts; recomputation-vs-storage tradeoffs (what to recompute
instead of fetch); prefix caching / radix trees for multi-user serving;
paged/quantized KV allocators from vLLM/SGLang-class stacks.

## Search discipline

- Primary sources: arXiv papers, repo READMEs + measured tables,
  engineering blogs with benchmarks. Press articles only as pointers to
  the primary.
- 2024–2026 emphasis; include 2023 classics only if they became
  practical recently.
- Numbers or it didn't happen: every entry carries the reported
  speedup/bytes-savings + the hardware it was measured on.
- Deduplicate re-derivations of the same idea; keep the best source.

## Output

Write `RESEARCH-RAW.md`: one section per finding, each with —

- name / source / date (link)
- mechanism: 2–4 sentences, precise enough to re-implement from
- reported numbers (speedup, bytes saved, perplexity delta) + measured
  on WHAT hardware
- reduces: bytes-at-rest / bytes-per-token / FLOPs / overlap-only
- exactness: exact / bounded (the bound) / quality-loss (how measured)
- transfer smell: one line — survives a fixed-function int8 matrix unit
  + a DDR wall? (your first guess; the distillation will overrule you)

20–40 findings. Breadth beats depth here — the distillation step will
kill and rank; your job is to make sure nothing worth killing got
missed. No fluff, no restating the same paper three ways.
