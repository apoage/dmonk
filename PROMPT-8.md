# PROMPT-8 — research round: compute & bandwidth "witchery" for a bandwidth-walled machine

You are an independent RESEARCH session with web access. Your mission:
survey the 2024–2026 state of the art in LLM-inference efficiency and
grade every finding against THIS notebook's machine — a bandwidth-walled
part with a fixed-function matrix unit. The corpus you are reading was
built by measuring this machine directly; your job is to find what the
wider world has discovered that we can steal, and to kill honestly what
cannot transfer.

Two rules up front:
1. **Changing nothing is an acceptable outcome.** Most current SOTA
   targets HBM-class hardware with programmable shader units; much of it
   will NOT transfer. A clean kill list is as valuable as a candidate
   list. Do not flatter the corpus; do not pad the candidate list.
2. **Grade, don't collect.** Every candidate that survives gets the
   rubric below. Anything you cannot grade against the machine profile
   goes to the kill list with the reason.

## The machine profile (from this repo — read these first)

1. `README.md`, then `HW-MAP.md` whole (the data-movement table is the
   wall: ~165–175 GB/s per die sustained DDR stream, ~86 GB usable per
   die, 8 dies; per-core: ~192 KiB vector scratchpad, 64 KiB L0A/L0B,
   256 KiB L0C; a FIXED-FUNCTION int8/f16 matrix unit (16×16×k tiles) —
   no arbitrary instruction substitution; vector unit ~40 lanes/cycle;
   host bounce 12.2 µs per direction).
2. `ALTERNATIVES.md` (the ranked lever list + the retired families — do
   not re-propose dominated ones), `DESIGN-2.md`/`DESIGN-3.md`/
   `DESIGN-4.md` headers (the expert kernel, the attention chain, the
   fleet planner). `PROOF-COVERAGE-4.md` round-7 section = the current
   measured anchor state (M0 165.8, realized launch ≤36 µs, the
   measured retry share).
3. The binding fact: **decode at batch-1 is BYTES-bound** (weights + KV
   streamed per token at the DDR wall; the matrix unit is already fed at
   ~85% of the wall by our kernels). **Prefill is compute-shaped.**
   Anything that reduces FLOPs but not bytes does not move decode.
   Anything that reduces bytes AT CONSTANT EXACTNESS CLASS is gold.

## Mission A — arithmetic / compute witchery (helps prefill; helps decode ONLY if it cuts bytes)

Search the 2024–2026 literature and engineering blogs (arXiv, Alpha*
program-discovery work, llama.cpp / vLLM / ollama communities, hardware
blogs) for: machine-discovered matmul kernels (AlphaTensor / AlphaEvolve
class) and whether any beat vendor libraries on FIXED-FUNCTION units;
practical Strassen-family variants at small tiles; low-rank + structured
sparsity AT INFERENCE (not training); rotation-based quantization
(QuaRot / SpinQuant / QuIP# class Hadamard smoothing) — note these
REDUCE BYTES legally by killing outliers before int4/int2; sub-4-bit
weight math (ternary / BitNet-class, 2-bit with codebooks); exact int8
accumulation tricks; softmax-free / linear-attention families (Mamba,
RWKV, hybrids) as ALTERNATIVE MODEL CLASSES we might serve instead;
speculative-decoding advances (EAGLE-class draft trees, self-spec,
multi-token prediction) — grade against our measured draft costs;
prefill chunking math.

## Mission B — bandwidth witchery (the main prize)

KV-side: latent-compression attention (MLA-class) math and what a
serving kernel would need; KV cache int8/int4 with bounded error; cache
eviction / merging / pooling (H2O, SnapKV, pyramid-class) as
byte-reducers at long context; shared-pool KV layouts. Weight-side:
below-4-bit with rotations (see A); PALETTE / codebook weight sharing;
MoE EXPERT DEDUPLICATION / merging (expert-similarity exploitation — our
weights are static at load); in-kernel decompression of STATIC weight
streams (dictionary/LZ-class — weights never change, so compress once,
decompress into L0 during the stream; grade the vector-unit cost vs the
bytes saved); recomputation-vs-storage tradeoffs; prefix/radix caching
for serving.

## The rubric (every surviving candidate gets exactly this, as a table row)

| field | meaning |
|---|---|
| name + source | paper/repo/post + date |
| reduces | bytes-at-rest / bytes-per-token / FLOPs / overlap-only |
| exactness | exact / bounded-error (bound?) / quality-loss (measured how?) |
| machine fit | survives the FIXED-FUNCTION matrix unit? the 192 KiB scratch? the DDR wall? needs which pipe? |
| decode vs prefill | which one it moves, arithmetic estimate of the factor |
| engineering risk | kernel-side / bridge-side / model-side; forced-change class |
| the measuring cell | the dmonk-style probe that would decide it (rates in, rates out) |
| verdict | CANDIDATE (rank) / KILLED (reason) |

## Output contract

Write `PROPOSED-WITCHERY.md` in this repo: (1) the graded table, top 15
max, ranked by bytes-reduction × exactness-preservation ÷ engineering
risk; (2) the kill list with one-line reasons; (3) for the top 3
candidates, an ALTERNATIVES.md-style entry draft (mechanism, gain
arithmetic vs the measured anchors, gates, what to measure first).
Do NOT edit any other file. Do NOT absorb anything into the corpus —
absorption is the orchestrator's job after grading.
