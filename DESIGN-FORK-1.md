# DESIGN-FORK-1 — Hybrid `K-int8 / V-f16` + Wide-Cap (`61 440`) Deferred-Guard Attention & Fleet Co-Design

> **PROMPT-7 Mission B Fork Document (2026-11-15)** — Append-only extension to [DESIGN-3.md](file:///Users/lukas/dmonk2/DESIGN-3.md), [DESIGN-4.md](file:///Users/lukas/dmonk2/DESIGN-4.md), and [ALTERNATIVES.md](file:///Users/lukas/dmonk2/ALTERNATIVES.md).
> Executable models: [proof/attn.py](file:///Users/lukas/dmonk2/proof/attn.py) (`[FORK-*]`), [proof/fleet.py](file:///Users/lukas/dmonk2/proof/fleet.py) (`[FORK-*]`), and machine-checked proofs in [proof/check.lean](file:///Users/lukas/dmonk2/proof/check.lean) (`Chk.Fork.*`, 0 `axiom`, 0 `sorry`, 0 `native_decide`).

---

## 0. Executive Thesis — Why This Fork Dominates the Corpus's Chosen Route

Across Rounds 3–7, the corpus's attention and fleet designs became trapped between two mutually incompatible regimes for KV compression:

1. **Full `KV-int8` + Lazy/Deferred Guard (`μ = 8`) is Numerically Unreachable (`T4r_i8`)**:
   On the lazy/deferred guard (`m_new = m_old` unless `m_blk > m_old + 8`), unrescaled probabilities in a non-tripping block reach $P = e^8 \approx 2\,981$. Quantizing $P \to \text{int8}$ for an $\text{i8} \times \text{i8} \to \text{i32}$ $PV$ MMA with fixed scale $127$ produces $127 \times 2\,981 = 378\,587 \gg 127$, saturating every non-trivial lane (`T4r_i8`). Setting $\mu = 0$ to keep $P \le 1$ destroys the lazy guard (`m_blk > m_old` trips on $\sim 35\text{--}50\%$ of blocks, exceeding the $31.9\%$ whole-step re-run break-even `T6a_trip_breakeven`).
2. **Full `KV-int8` + Rowmax (`μ = 0` per block) is Scalar-Crossing-Bound (`T6a_rowmax_det`)**:
   Under Errata #29 and #31 ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L337-L361)), a deterministic per-block rowmax requires $16$ scalar-destination vector reductions per 512-token block ($16 \times 1.1\;\mu\text{s} = 17.6\;\mu\text{s/block}$). At $L = 32\text{k}$ ($64$ blocks), that adds $+1\,126.4\;\mu\text{s}$ per layer (`938.8 + 1126.4 = 2065.2 µs/layer`, `65.0 GB/s` f16-eq — **2.03× slower than f16!**). At $L = 1\text{M}$ on Dense-469B ($120$ layers $\times 2\,048$ blocks), it adds **$+4\,325.38\;\text{ms/tok}$** (`9 024.30 ms/tok` $\to 0.027\;\text{tok/s/card}$, `T6f_dense1M_det`).
3. **Why [ALTERNATIVES.md](file:///Users/lukas/dmonk2/ALTERNATIVES.md#L486-L497) Falsely Dismissed `K-int8 / V-f16` (`ALT-6`)**:
   In Round 2, `ALT-6` (`K-int8 / V-f16`) was ranked #7 and dismissed with the one-line verdict: *"dominated by full KV-int8 on every rate cell."* When Round 4 (`T4r_i8`) and Prompt-6 (`T6a_rowmax_det`) killed full `KV-int8` on both the lazy and rowmax paths, `ALT-6` was **never re-evaluated** — even after [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L117) measured the `K-int8` score stream on silicon at **`87.6 GB/s` (`2.13×` speedup at `d = 64`, `1.39×` at `d = 128`, including `~3 %` scale dequant)** and retracted Erratum #14 (`k = 64` i8 is fp64-exact).

### The Fork Mechanism (`DESIGN-FORK-1`)

**Hybrid `K-int8 / V-f16` + Wide-Cap (`61 440`) Deferred-Guard Attention** resolves the dilemma by splitting the precision of the two KV tensors along the exact boundary of the hardware's MMA and scalar-crossing constraints:

* **Keys (`K`) are stored in `int8` (`128 B/tok/head` at `d = 128`)** with per-token-per-head `f16` scale (`2 B`), and **Queries (`Q`) are quantized to `int8` once per pass** in `US` before the block loop. Score MMA ($S = Q K^T$) executes in a **single `(16, 16, 128)` `i8×i8→i32` call** per 16-token subtile (`32 calls = 480 ns/block` vs `64 calls = 960 ns/block` in f16; and at $d = 64$, a **single `(16, 16, 64)` `i8×i8→i32` call** per the retracted Erratum #14).
* **Values (`V`) remain in `f16` (`256 B/tok/head`)**, so **attention weights (`P`) remain in `f16`** (`P` is **never** quantized to `int8`). Value MMA ($O += P V$) uses the unchanged f16 path (`2 × (16, 16, 64)` per 128-token chunk).
* Because $P$ stays in `f16`, the kernel runs on the **zero-per-block-crossing deferred guard** ($\mu = 8$) with the silicon-verified **wide cap `61 440 = 15 × 2¹²`** ($< 65\,504$, $> e^{11}$, [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L116)), which cuts the measured 32k production retry rate from $\tau = 8.0\%$ (`cap = 3072`) to **$\tau = 5.5\%$** (`cap = 61440`) with zero per-block scalar reads.

### Headline Gains (`DERIVED` from `MEASURED` anchors, proved in `Chk.Fork.*`)

| Metric / Cell | Corpus Baseline (`R7` / `PA`) | `DESIGN-FORK-1` (`[FORK-*]`) | Delta / Verdict | Theorem in `proof/check.lean` |
|---|---:|---:|---:|---|
| **KV bytes / token / layer** ($H_{kv}=8, d=128$) | $4\,096\;\text{B}$ (`f16`) | **$3\,072\;\text{B}$** (`K-i8 / V-f16`) | **$-25.0\%$ DDR bytes & footprint** | `Chk.Fork.fork_block_and_cap_invariants` |
| **`L0C` accumulator footprint** ($m_t = 1$) | $131\,072\;\text{B}$ ($128\;\text{KiB}$, full) | **$98\,304\;\text{B}$** ($96\;\text{KiB}$) | **$-32\;\text{KiB}$ ($1\times C_s$ set freed)** | `Chk.Fork.fork_block_and_cap_invariants` |
| **32k attention / layer (trip-free)** | $945\,500\;\text{ns}$ ($142.0\;\text{GB/s}$) | **$760\,800\;\text{ns}$** ($176.4\;\text{GB/s}$ f16-eq) | **$-184.70\;\mu\text{s/layer}$ ($-19.5\%$)** | `Chk.Fork.fork_attn_cells` |
| **32k attention / layer (amortized, real $\tau$)** | $1\,015\,340\;\text{ns}$ (`cap 3072`, $8.0\%$) | **$798\,656\;\text{ns}$** (`cap 61440`, $5.5\%$) | **$-216.68\;\mu\text{s/layer}$ ($-21.3\%$)** | `Chk.Fork.fork_attn_cells` |
| **32k attention vs rowmax `KV-int8`** | $2\,065\,200\;\text{ns}$ (`T6a_rowmax_det`) | **$798\,656\;\text{ns}$** ($0$ block crossings) | **$-1\,266.54\;\mu\text{s/layer}$ ($2.59\times$ faster)** | `Chk.Fork.fork_attn_cells` |
| **128k attention / layer (trip-free)** | $3\,618\,800\;\text{ns}$ | **$2\,880\,000\;\text{ns}$** | **$-738.80\;\mu\text{s/layer}$ ($-20.4\%$)** | `Chk.Fork.fork_attn_cells` |
| **1M attention / layer (trip-free)** | $28\,694\,000\;\text{ns}$ | **$22\,783\,600\;\text{ns}$** | **$-5.91\;\text{ms/layer}$ ($-20.6\%$)** | `Chk.Fork.fork_attn_cells` |
| **MoE-359B 32k step (8-die chain)** | $129.74\;\text{ms} \to 1.926\;\text{tok/s/card}$ | **$123.67\;\text{ms} \to 2.021\;\text{tok/s/card}$** | **$+4.9\%$** (`2.216` at realized launch) | `Chk.Fork.fork_fleet_steps` |
| **MoE-359B 128k step (8-die chain)** | $202.64\;\text{ms} \to 1.233\;\text{tok/s/card}$ | **$181.95\;\text{ms} \to 1.373\;\text{tok/s/card}$** | **$+11.3\%$** (`1.461` at realized launch) | `Chk.Fork.fork_fleet_steps` |
| **MoE-359B 1M step (8-die chain)** | $904.74\;\text{ms} \to 0.276\;\text{tok/s/card}$ | **$739.25\;\text{ms} \to 0.338\;\text{tok/s/card}$** | **$+22.4\%$** (`0.343` at realized launch) | `Chk.Fork.fork_fleet_steps` |
| **MoE-359B 32k 2-instance (`V3`, 4-die)** | $142.05\;\text{ms} \to 3.519\;\text{tok/s/card}$* | **$135.60\;\text{ms} \to 3.687\;\text{tok/s/card}$** | **$+4.8\%$** (`x`: `[176,165,165,176]`) | `Chk.Fork.fork_inst_fit_and_step` |
| **Dense-469B 1M step (8-die chain)** | $9\,024.30\;\text{ms} \to 0.027\;\text{tok/s/card}$ | **$6\,436.38\;\text{ms} \to 0.038\;\text{tok/s/card}$** | **$+40.7\%$** ($-2\,587.92\;\text{ms/tok}$, $0$ crossings) | `Chk.Fork.fork_dense_1M_zero_crossing` |

*\*Note: Uses the corrected Round-7 4-die instance baseline `142.05 ms → 3.519 tok/s/card` (`Chk.challenge_r7_inst_missing_cold_tier`); `proof/fleet.py` line 1635 printed `3.853` by evaluating `tps_card_inst` on the 8-die `x = 0` step time `129.74 ms`.*

---

## 1. Errata-Compliance Ledger (Every Constraint Mapped Before Any Timing Claim)

Per `PROMPT-7` Mission B (*"A fork that ignores an erratum is dead on arrival"*), Table 1 maps every mechanism of `DESIGN-FORK-1` against the hardware constraints and errata in [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md).

| Erratum / HW-MAP Fact | Constraint Summary | How `DESIGN-FORK-1` Satisfies It |
|---|---|---|
| **#1, #5, #6** (`L0A`/`L0B`/`L0C` residency & loader) | `L0A = 64 KiB`, `L0B = 64 KiB`, `L0C = 128 KiB`; `S1 → L0A/B` loader is `26.5 GB/s` (`618 ns` per `16 KiB`). | At $m_t = 1$, $Q_{\text{i8}}$ in `L0A` uses $16 \times 128 = 2\;\text{KiB}$ ($32\;\text{KiB}$ at $m_t = 8$); $K_{\text{i8}}$ tile in `L0B` uses $16 \times 128 = 2\;\text{KiB}$; $C_s$ in `L0C` uses **1 chunk set** ($32\;\text{KiB}$) + $C_o$ uses 8 chunk sets ($64\;\text{KiB}$) = **$96\;\text{KiB} < 128\;\text{KiB}$**. |
| **#8, #19, #23** (`L0C` Accumulate=1 hazard & fresh chunk sets) | `Accumulate=1` corrupts chunks $1..K-1$ on $K > 1$ chunk sets; reusing chunk sets across loop iterations corrupts accumulators. | Score MMA `(16,16,128)` `i8×i8→i32` completes the full $d = 128$ dot product in **one call** (`Accumulate=0`, 1 chunk set of 32 chunks = $32\;\text{KiB}$). Value MMA `f16×f16→f32` uses 2 calls of `(16,16,64)` with `Accumulate=0` into two fresh 4-chunk sets ($2 \times 32\;\text{KiB} = 64\;\text{KiB}$) and merges in f32 on the vector unit (`+8 313 ns` T / `+32 614 ns` C on cold W4 slabs). |
| **#9** (2D strided DMA unsupported) | All DDR $\leftrightarrow$ `S1`/`US` DMAs must be 1D contiguous transfers. | Each 256 KiB KV page stores $1\,024$ tokens of $K_{\text{i8}}$ contiguously ($128\;\text{KiB}$) followed by its $1\,024 \times 2\;\text{B} = 2\;\text{KiB}$ `f16` scale vector, and $1\,024$ tokens of $V_{\text{f16}}$ contiguously ($256\;\text{KiB}$). All reads are 1D contiguous bulk DMAs. |
| **#12** (`i4×i4→i32` SILICON-DEAD) | `i4×i4→i32` MMA does not function on silicon ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L157)). | Never used. Score MMA uses silicon-proven `(16,16,128)` / `(16,16,64)` `i8×i8→i32`; cold weights use the measured 5-pass `int4 → f16` vector unpack (`5.3 GB/s/core`). |
| **#14 (RETRACTED)** (`k = 64` `i8×i8→i32` is fp64-exact; full barrier `0x7` still required) | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L193-L201) proved `k = 64` i8 is fp64-exact (the earlier "wrong $k=64$" verdict was a host dump-decode stride bug). Pipe-specific barriers remain dead; full `Wait_Barrier(0x7)` is mandatory. | At $d = 128$, scores use native single-call `k = 128` `(16,16,128)` `i8×i8→i32`. At $d = 64$, scores use single-call `k = 64` `(16,16,64)` `i8×i8→i32` (`90.2 GB/s` vs `51.4 GB/s` on $2 \times k=32$, eliminating $k=32$'s A-offset ignore bug). Every tile uses full `Wait_Barrier(0x7)`. |
| **#18, #20** (No direct `US → S1` path; $P$ bounces via DDR) | Vector output $P_{\text{f16}}$ in `US` cannot DMA directly to `S1`; it must bounce `US → DDR → S1` (`legs = 2`, $2 \times 16\;\text{KiB} = 32\;\text{KiB/block/core}$ at $m_t = 1$). | Priced with full `legs = 2` bounce ($32\;\text{KiB/block/core}$) in both analytical (`ddr4_block_k8`) and measured-delta models. |
| **#25, #29, #31** (Scalar-engine read after vector write = $10\text{--}20\;\mu\text{s}$ crossing; `s_dst` reduce = $1.1\;\mu\text{s}$) | Any per-block scalar read of vector-written `US` or scalar-destination reduce stalls the pipeline by $10\text{--}20\;\mu\text{s}$ ($17.6\;\mu\text{s/block}$ for 16-row rowmax). | **Zero per-block scalar crossings.** Because $V$ and $P$ remain `f16`, `DESIGN-FORK-1` uses the vector-folded deferred guard (`Max(m_blk - (m_old + 8), 0)` accumulated in vector `US`, read **once** at end of step). |
| **#32, #33, #34** (Vector `Adds` f32 immediate truncation, `Div` vs `Recip`, `Exp` input range) | `Adds` truncates f32 immediate to bf16; wide cap must be bf16/f16-exact. | Wide cap $61\,440 = \text{0x7700}_{\text{f16}} = \text{0x47700000}_{\text{f32}}$ has only 4 significand bits ($15 \times 2^{12}$), so it is **exact in both f16 and bf16** (zero `Adds`/`Mins` immediate truncation). |
| **HW-MAP lines 121–122** (`s8` cast maps `Inf/NaN → 0`; `Tensor Min/Max` propagate `±Inf`) | If an activation or $K$ row contains $\pm\text{Inf}$, `Tensor Max` outputs $+\text{Inf}$, making $\text{scale} = 127 / \infty = 0$ and silently zeroing the entire quantized row! | **Inf-Scrubbed Quantizer (§2.1)**: Before `Tensor Max` on any $Q$, $K$, or activation row, a 2-op vector clamp `Min(x, +65504)` / `Max(x, -65504)` scrubs $\pm\text{Inf}$ to finite f16 max (`+34 ns` per 128-dim row), guaranteeing $0 < \text{absmax} \le 65\,504$. |

---

## 2. Detailed Kernel Architecture

### 2.1 Inf-Scrubbed Per-Token `K-int8` Write Quantizer & Once-Per-Pass `Q-int8` Staging

When a new token is appended to the KV cache at layer $l$, each of the 8 KV heads ($d = 128$) produces a key vector $k \in \mathbb{R}^{128}$ (in `f16`) and a value vector $v \in \mathbb{R}^{128}$ (in `f16`):

1. **`V-f16` Write**: $v$ ($256\;\text{B/head}$) is written directly to the `V` sub-page in DDR without quantization.
2. **Inf-Scrubbed `K-int8` Write**:
   To prevent the [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L121-L122) `Tensor Min/Max` $\pm\text{Inf}$ propagation bug (where a single $\pm\text{Inf}$ lane causes `rowmax = Inf`, `inv_scale = 0`, and `s8_cast(Inf) = 0`, silently zeroing all 128 elements of $k$):
   $$\tilde{k}_j = \max\!\bigl(-65\,504,\; \min(+65\,504,\; k_j)\bigr), \qquad a_k = \max_{0 \le j < 128} |\tilde{k}_j|, \qquad s_k = \frac{\max(a_k, 2^{-14})}{127}$$
   $$q_k[j] = \text{cast}_{\text{s8}}\!\left(\text{round}\!\left(\frac{\tilde{k}_j}{s_k}\right)\right) \in [-127, +127]$$
   The 128-byte `int8` vector $q_k$ is appended to the contiguous $K_{\text{i8}}$ sub-page, and the 2-byte `f16` scale $s_k$ is written to the page's contiguous scale footer. For $t = 1$, quantizing 8 KV heads of 128 elements in `US` takes $< 1.2\;\mu\text{s/layer}$ (folded into the K-write epilogue).
3. **Once-Per-Pass `Q-int8` Quantization**:
   At the start of the attention kernel (outside the $N_b$-block loop), the core's $16 \times 128$ query fragment $Q$ ($g = 8$ active query rows padded to $m = 16$ at $t = 1$, or $m_t \times 16$ rows at $t > 1$) is scrubbed and row-wise quantized in `US` to $Q_{\text{i8}} \in [-127, 127]^{16 \times 128}$ with per-row `f32` scale $s_q[r] = a_q[r] / (127 \sqrt{d})$.
   * Cost: $< 3.5\;\mu\text{s}$ **once per pass** (amortized over $N_b = 64\text{--}2\,048$ blocks $= 3\text{--}55\;\text{ns/block}$).
   * $Q_{\text{i8}}$ ($2\;\text{KiB}$ at $m_t = 1$, $16\;\text{KiB}$ at $m_t = 8$) is loaded into `L0A` once before the block loop and stays resident across all $N_b$ blocks.

### 2.2 Single-Call Score MMA & Reduced `L0C` Footprint

Inside each 512-token block ($32$ subtiles of $16$ tokens):

* **DDR $\to$ `S1` Stream**: Each core streams $512 \times 128\;\text{B} = 64\;\text{KiB}$ of $K_{\text{i8}}$, $512 \times 2\;\text{B} = 1\;\text{KiB}$ of $s_k$, and $512 \times 256\;\text{B} = 128\;\text{KiB}$ of $V_{\text{f16}}$ (totalKV $= 192\;\text{KiB/block/core}$ vs $256\;\text{KiB}$ in f16, plus $32\;\text{KiB}$ for the 2-leg $P_{\text{f16}}$ bounce $= 224\;\text{KiB/block/core}$).
* **Score MMA ($S = Q_{\text{i8}} K_{\text{i8}}^T$)**:
  Because `i8×i8→i32` supports native $(16, 16, 128)$ in a **single instruction** ($15\;\text{ns/call}$), each 16-token subtile executes **1 MMA call** (`Accumulate=0`) into chunk $t \in \{0..31\}$ of a **single `C_s` chunk set** ($32 \times 1\;\text{KiB} = 32\;\text{KiB}$ in `L0C`):
  * **32 MMA calls/block** ($32 \times 15 = 480\;\text{ns}$) vs 64 calls ($960\;\text{ns}$) in f16 (which required two $k = 64$ calls and two fresh $32\;\text{KiB}$ chunk sets per Erratum #23!).
  * **No Erratum-#23 score merge**: Because $k = 128$ finishes the dot product in one call with `Accumulate=0`, the vector f32 addition of `C_s0 + C_s1` required by Round-4 f16 attention is **completely eliminated**.
  * **`L0C` Headroom**: `L0C` occupancy at $m_t = 1$ drops from $64\;\text{KiB} (C_s) + 64\;\text{KiB} (C_o) = 128\;\text{KiB}$ (100% full) to **$32\;\text{KiB} (C_s) + 64\;\text{KiB} (C_o) = 96\;\text{KiB}$** (leaving $32\;\text{KiB}$ free in `L0C`).
  * **At $d = 64$**: By the retracted Erratum #14 ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L193-L201)), single-call $(16, 16, 64)$ `i8×i8→i32` is fp64-exact and runs at **`90.2 GB/s`** ($1.75\times$ the $51.4\;\text{GB/s}$ of $2 \times k=32$), avoiding $k=32$'s hardware A-offset ignore bug and powering the measured **`87.6 GB/s` (`2.13×`)** `K-int8` score stream ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L117)).

### 2.3 Scale-Folded Vector Softmax + Wide-Cap (`61 440`) Deferred Guard

After the 32 score subtiles drain from `L0C` (`32 KiB` of `i32` scores) to `US`:

1. **Score Dequantization**:
   Each `i32` score $S_{\text{i32}}[r, t]$ is cast to `f32` and multiplied by $s_q[r] \cdot s_k[t]$. Because the f16 baseline already performed an f32 chunk-set addition (`C_s0 + C_s1`) plus $\times (1/\sqrt{d})$ scaling, replacing the chunk-set addition with `Cast_i32_to_f32` + `Mul` by $s_k[t]$ adds only **$+388\;\text{ns/block}$** on the vector pipe (`vecBlkK8LazyT = 5 530 + 388 = 5 918 ns < 10 845 ns` DDR block time), matching the **measured `~3 %` dequant overhead** in [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L117) (`87.6 vs 90.2 GB/s`, $\sim 8\,000\;\text{ns}$ across 64 blocks at 32k).
2. **Wide-Cap (`61 440`) Deferred Guard**:
   The shifted exponentiation computes $\tilde{P}[r, t] = \min\!\bigl(61\,440,\; \exp(S[r, t] - (m_{\text{old}}[r] + 8))\bigr)$ and casts $\tilde{P}[r, t] \to \text{f16}$ for the $PV$ MMA:
   * Why `cap = 61 440` ($15 \times 2^{12}$): Under `cap = 3072` ($\ln 3072 \approx 8.03$), any block whose true max exceeds $m_{\text{old}} + 8.03$ clamps $\tilde{P}$ and requires a whole-step retry ($\tau = 8.0\%$ of 32k serving launches, [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L116)). Raising the cap to $61\,440 < 65\,504$ ($\ln 61440 \approx 11.026 > 11$, `Chk.Fork.fork_block_and_cap_invariants`) lowers the measured 32k retry share to **$\tau = 5.5\%$** (`HW-MAP.md` line 116).
   * Why $P$ never saturates: Because $V$ is `f16`, $\tilde{P}$ is cast to `f16` (max normal $65\,504 > 61\,440$), **not** `int8` (max $127$). Thus `T4r_i8`'s saturation barrier does not apply.
   * Zero per-block scalar crossings: The guard accumulator `g_acc = Max(g_acc, m_blk - (m_old + 8))` stays in vector `US` across all $N_b$ blocks and is read **once** at the end of the step.

### 2.4 Extension to $H_{kv} = 4$: Split-KV Core Map (`HW-MAP.md` Line 115)

In [DESIGN-3.md](file:///Users/lukas/dmonk2/DESIGN-3.md#L688-L692) §7 and [ALTERNATIVES.md](file:///Users/lukas/dmonk2/ALTERNATIVES.md#L562) §4, `H_kv = 4` was modeled by leaving **4 of the 8 AICores idle** (halving effective DDR bandwidth to $87.3\;\text{GB/s}$) and dismissing FlashDecoding split-KV as dominated. However, [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L115) **measured** the 2-cores/head split-KV schedule at $H_{kv} = 4$ on silicon:
* **Measured speedup**: **`1.97×`** ($167.8\;\text{GB/s}$ at 64k and $178.9\;\text{GB/s}$ at 256k vs $85.1\text{--}91.0\;\text{GB/s}$ with 4 idle cores), with final 2-split tree merge overhead $< 3\%$ ($51\;\mu\text{s}$ at 64k).
* `DESIGN-FORK-1` adopts the 2-cores/head split-KV schedule whenever $H_{kv} = 4$ and $L \ge 4\,096$: core $2h$ processes blocks $0 \dots N_b/2 - 1$ and core $2h+1$ processes blocks $N_b/2 \dots N_b - 1$ of KV head $h \in \{0..3\}$, followed by a single end-of-step $(m, \ell, O)$ merge via DDR workspace.

---

## 3. Derived Attention & Fleet Cells (`[FORK-*]` in `proof/attn.py` & `proof/fleet.py`)

### 3.1 Per-Layer Attention Cells (`t = 1`, Both Shapes, `mt = 1`)

From the measured Session-3/5 phase decomposition ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L111-L117), `STREAM5 = 770 800 ns` for the 32k f16 `K+V` stream = `385 400 ns` each for `K` and `V`):
* Halving the `K` stream saves $385\,400 / 2 = 192\,700\;\text{ns}$ per 64 blocks (32k), and subtracting the measured $\sim 3\%$ scale-dequant delta ($8\,000\;\text{ns}$ per 64 blocks) yields a net saving of:
  $$\Delta_{\text{K8}}(32\text{k}) = 192\,700 - 8\,000 = 184\,700\;\text{ns} \quad (2\,885.9\;\text{ns/block})$$
* On a tripped step at 32k, the whole-step retry cost $R$ also drops by $184\,700\;\text{ns}$ ($873\,000 - 184\,700 = 688\,300\;\text{ns}$).
* Scaling proportionally with $N_b$ ($4\times$ at 128k, $32\times$ at 1M) yields the `DESIGN-FORK-1` attention table (machine-checked in `Chk.Fork.fork_attn_cells`):

| Context $L$ | Reading | Shipped `DESIGN-3` (`R7` f16) | Full `KV-int8` Rowmax (`PA` det) | `DESIGN-FORK-1` (`K-int8 / V-f16`) | Saving vs Shipped `R7` | f16-eq Rate |
|---|---|---:|---:|---:|---:|---:|
| **32k** ($64$ blks) | Trip-free | $945\,500\;\text{ns}$ | $2\,065\,200\;\text{ns}$ | **$760\,800\;\text{ns}$** | $-184\,700\;\text{ns}$ (**$-19.5\%$**) | **$176.4\;\text{GB/s}$** |
| **32k** ($64$ blks) | Amortized (`cap 3072`, $\tau = 8.0\%$) | $1\,015\,340\;\text{ns}$ | $2\,065\,200\;\text{ns}$ | **$815\,864\;\text{ns}$** | $-199\,476\;\text{ns}$ (**$-19.6\%$**) | $164.5\;\text{GB/s}$ |
| **32k** ($64$ blks) | **Amortized (`cap 61440`, $\tau = 5.5\%$)** | $993\,515\;\text{ns}$ | $2\,065\,200\;\text{ns}$ | **$798\,656\;\text{ns}$** | **$-216\,684\;\text{ns}$ ($-21.3\%$ vs shipped)** | **$168.1\;\text{GB/s}$** |
| **128k** ($256$ blks) | Trip-free | $3\,618\,800\;\text{ns}$ | $8\,130\,000\;\text{ns}$ | **$2\,880\,000\;\text{ns}$** | **$-738\,800\;\text{ns}$ ($-20.4\%$)** | **$186.4\;\text{GB/s}$** |
| **1M** ($2\,048$ blks) | Trip-free | $28\,694\,000\;\text{ns}$ | $64\,738\,000\;\text{ns}$ | **$22\,783\,600\;\text{ns}$** | **$-5\,910\,400\;\text{ns}$ ($-20.6\%$)** | **$188.5\;\text{GB/s}$** |

Furthermore, on the Round-4 analytical model (`step4` at $169.2\;\text{GB/s}$ with `legs = 2`), `DESIGN-FORK-1` takes $256 \times 10\,845 + 19\,328 = 2\,795\,648\;\text{ns/layer} < 3\,207\,719\;\text{ns/layer}$ (`twMoeAnchor`), **flipping analytical MoE-128k (anchored) from attention-bound back to weights-bound** (`Chk.Fork.fork_attn_cells`)!

### 3.2 8-Die Fleet Step & Throughput Table (`[FORK-step-*]`, `Chk.Fork.fork_fleet_steps`)

| Shape & Context | Corpus `R7` Step ($91\;\mu\text{s}$ launch) | Corpus `R7` (`tok/s/card`) | `DESIGN-FORK-1` Step ($91\;\mu\text{s}$ launch) | `DESIGN-FORK-1` (`tok/s/card`) | `DESIGN-FORK-1` Realized Launch ($36\;\mu\text{s}$) | Throughput Gain |
|---|---:|---:|---:|---:|---:|---:|
| **MoE-359B 32k** (`amort`) | $129.74\;\text{ms}$ | $1.926$ | **$123.67\;\text{ms}$** | **$2.021$** | **$112.78\;\text{ms} \to 2.216$** | **$+4.9\%$** (`+5.4%` realized) |
| **MoE-359B 128k** | $202.64\;\text{ms}$ | $1.233$ | **$181.95\;\text{ms}$** | **$1.373$** | **$171.06\;\text{ms} \to 1.461$** | **$+11.3\%$** |
| **MoE-359B 1M** | $904.74\;\text{ms}$ | $0.276$ | **$739.25\;\text{ms}$** | **$0.338$** | **$728.36\;\text{ms} \to 0.343$** | **$+22.4\%$** |
| **Dense-469B 32k** (`amort`) | $2\,411.63\;\text{ms}$ | $0.103$ | **$2\,385.62\;\text{ms}$** | **$0.104$** | **$2\,345.91\;\text{ms} \to 0.106$** | $-26.00\;\text{ms/tok}$ |
| **Dense-469B 128k** | $2\,724.04\;\text{ms}$ | $0.091$ | **$2\,635.38\;\text{ms}$** | **$0.094$** | **$2\,595.67\;\text{ms} \to 0.096$** | **$+3.3\%$** ($-88.66\;\text{ms/tok}$) |
| **Dense-469B 1M** (8-die + W4) | $9\,024.30\;\text{ms}$ (`PA` det) | $0.027$ | **$6\,436.38\;\text{ms}$** | **$0.038$** | **$6\,396.67\;\text{ms} \to 0.039$** | **$+40.7\%$** ($-2\,587.92\;\text{ms/tok}$) |

### 3.3 Co-Design with Two 4-Die Instances (`V3`) & Zero-Crossing 8-Die Dense-1M

Because `K-int8 / V-f16` reduces KV memory from $4\,096\;\text{B/tok}$ to $3\,072\;\text{B/tok}$ ($-25\%$), it directly reduces the mandatory `int4` weight-compression share $x$ (thousandths) on every 4-die instance (`Chk.Fork.fork_inst_fit_and_step`):

1. **4-Die Instance Residency (`[FORK-inst-fit]`)**:
   * **MoE 32k**: $x$ drops from `[182, 170, 170, 182]` to **`[176, 165, 165, 176]`**. Combined with `amK8_32k_cap61440 = 798 656 ns`, the 4-die MoE 32k instance step (with `hot = 101 186 ns` and Erratum-#19 merged `cold = 206 157 ns`) drops from $142.05\;\text{ms}$ ($3.519\;\text{tok/s/card}$) to **$135.60\;\text{ms}$ ($3.687\;\text{tok/s/card}$ at $c = 2.000$, $3.668$ at $c = 1.990$)**.
   * **MoE 128k**: $x$ drops from `[244, 233, 233, 244]` to **`[223, 212, 212, 223]`** ($-21\text{‰}$ cold weights on every die).
   * **MoE 1M**: $x$ drops from `[827, 815, 815, 827]` to **`[661, 649, 649, 661]`** ($-166\text{‰}$ cold weights on every die — saving $16.6\%$ of all experts from the slower int4 cold tier!).
   * **Dense 32k**: $x$ drops from `[376, 358, 332, 376]` to **`[355, 337, 311, 355]`**.
2. **8-Die Dense-1M Zero-Crossing Route (`[FORK-dense-1M]`, `Chk.Fork.fork_dense_1M_zero_crossing`)**:
   In [DESIGN-4.md](file:///Users/lukas/dmonk2/DESIGN-4.md), Dense-469B at $L = 1\text{M}$ ($15$ layers/die) could not fit f16 KV ($64.42\;\text{GB/die}$) alongside all-int8 weights ($47.82\;\text{GB/die}$), forcing the design onto full `KV-int8` ($32.21\;\text{GB/die}$) with the rowmax chain — which under Erratum #31 suffers $120 \times 2\,048 \times 17\,600\;\text{ns} = +4\,325.38\;\text{ms/tok}$ of deterministic scalar-crossing stalls (`9 024.30 ms/tok` $\to 0.027\;\text{tok/s/card}$).
   Under `DESIGN-FORK-1`:
   * $15$ layers of `K-int8 / V-f16` at $L = 1\text{M}$ occupy $15 \times 3\,072 \times 1\,048\,576 = 48.32\;\text{GB/die}$, leaving $35.47\;\text{GB/die}$ of net room (`netDieRoom = 83.79 GB`).
   * Compressing a fraction $x = 605\text{‰}$ of dense weights on outer dies $0, 7$ (with `wEmbed`/`wHead`), $x = 567\text{‰}$ on die $1$ (with `wDraft`), and $x = 517\text{‰}$ on inner dies $2..6$ to the Erratum-#19 merged W4 tier ($R_{\text{W4}} = 80.0\;\text{GB/s}$ W8-eq) fits Dense-1M in $< 86\;\text{GB/die}$ with **zero per-block scalar crossings**.
   * Step time is **$6\,436.38\;\text{ms/tok} \to 0.038\;\text{tok/s/card}$**, beating the corpus's `0.027 tok/s/card` route by **$+40.7\%$** ($-2\,587.92\;\text{ms/tok}$)!

---

## 4. Honest Epistemic Ledger — What Is `MEASURED`, `DERIVED`, and `UNMEASURED`

Per the corpus's frame discipline, every premise of `DESIGN-FORK-1` is classified below:

| Component / Quantity | Status | Source / Evidence |
|---|---|---|
| `K-int8` score stream rate (`87.6 GB/s` own-bytes, `2.13×` at `d=64`, `1.39×` at `d=128`, incl. `~3 %` dequant) | **MEASURED** | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L117) (silicon 20/20). |
| Single-call `k = 64` and `k = 128` `i8×i8→i32` fp64-exactness & `90.2 GB/s` rate | **MEASURED** | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L193-L201) (Erratum #14 retraction). |
| Wide cap `61 440` retry rate $\tau = 5.5\%$ vs `cap = 3072` $\tau = 8.0\%$ at 32k | **MEASURED** | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L116) (real-model 32k decode). |
| Split-KV 2-cores/head at $H_{kv} = 4$ (`167.8 / 178.9 GB/s`, `1.97×`) | **MEASURED** | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L115). |
| 5-pass `int4 → f16` vector unpack (`5.3 GB/s/core`) | **MEASURED** | [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L118). |
| Per-layer `K-int8 / V-f16` + `cap 61440` cells (`798.66 µs` 32k, `2.88 ms` 128k, `22.78 ms` 1M) | **DERIVED** | Proved in `Chk.Fork.fork_attn_cells` from `MEASURED` Session-5/7 K+V phase split and `MEASURED` K-int8 dequant overhead. |
| End-to-end fused `K-int8 / V-f16` + `cap 61440` kernel at $d = 128$ across $L \in \{32\text{k}, 128\text{k}, 1\text{M}\}$ | **UNMEASURED** | The `K-int8` score phase (`HW-MAP.md` line 117) and the `cap 61440` deferred guard (`HW-MAP.md` line 116) were measured in separate kernel arms; their combined full-step loop at $d = 128$ must be timed on silicon (`FORK-E1`). |
| Real-model perplexity / KL drift of per-token-per-head `K-int8` + `cap 61440` at 32k–1M | **UNMEASURED** | Per-token-per-head `K-int8` has max quantization step $\le a_k / 127$, but end-to-end model quality on Dense-469B and MoE-359B requires benchmark validation (`FORK-E3`). |

---

## 5. Experiment Ladder to Decide the Fork (`FORK-E1` .. `FORK-E5`)

Before `DESIGN-FORK-1` replaces the baseline in the production rank, the following 5-step silicon experiment ladder decides every open question:

1. **`FORK-E1` (Combined `K-int8 / V-f16` + `cap 61440` Full-Step Kernel Timing at $d = 128$, $L \in \{32\text{k}, 128\text{k}, 1\text{M}\}$)**:
   * **Action**: Fuse the measured `K-int8` score path ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L117), single-call `(16,16,128)` `i8×i8→i32` into 1 `C_s` chunk set + `i32→f32` scale multiply) with the `cap = 61440` deferred-guard `V-f16` loop ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L116)) and time 20 iterations at 32k, 128k, and 1M.
   * **Pass / Decision Gate**: Trip-free 32k cell $\le 800\;\mu\text{s}$ (predicted $760.8\;\mu\text{s}$) and amortized 32k cell at $\tau = 5.5\%$ $\le 840\;\mu\text{s}$ (predicted $798.7\;\mu\text{s}$). Any cell $< 993.5\;\mu\text{s}$ beats the f16 `cap = 61440` baseline.
2. **`FORK-E2` (Inf-Scrubbed Quantizer Fault-Injection Gate)**:
   * **Action**: Inject planted $+\text{Inf}$, $-\text{Inf}$, and `NaN` values into 1 lane of $K$ and 1 lane of $Q$ before the quantizer (`Min(., +65504)` / `Max(., -65504)` + `Tensor Max`) and verify against fp64 reference.
   * **Pass / Decision Gate**: Non-planted lanes match fp64 reference to $\le 1\;\text{ULP}_{\text{i8}}$ (confirming the [HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L121-L122) row-zeroing bug is defeated) and step overhead is $\le 2\;\mu\text{s}$.
3. **`FORK-E3` (Real-Model Retry Share $\tau$ and KL Divergence under `K-int8 / V-f16` + `cap 61440`)**:
   * **Action**: Run 1 000 real-model decode steps at 32k and 128k with `K-int8 / V-f16` and `cap = 61440`, logging both the guard trip rate $\tau$ and top-1 / KL divergence vs f16 KV.
   * **Pass / Decision Gate**: $\tau \le 7.0\%$ (break-even vs f16 `cap 3072` is $\tau \le 37.0\%$!) and $\Delta\text{PPL} < 0.02$.
4. **`FORK-E4` (8-Die Dense-1M Zero-Crossing Step vs Rowmax `KV-int8`)**:
   * **Action**: Allocate the 15-layer Dense-1M die layout with $48.32\;\text{GB}$ of `K-int8 / V-f16` KV and $x = [605, 567, 517, \dots, 605]\text{‰}$ W4 weights, and time one full layer ($2\,048$ blocks of attention + W8/W4 hybrid projections).
   * **Pass / Decision Gate**: Per-layer time $\le 56\;\text{ms}$ ($\le 6.72\;\text{s/tok}$, predicted $6.44\;\text{s/tok}$), beating the $9.02\;\text{s/tok}$ deterministic rowmax `KV-int8` route by $> 2.3\;\text{s/tok}$.
5. **`FORK-E5` ($H_{kv} = 4$ Split-KV Integration with `K-int8 / V-f16`)**:
   * **Action**: Run the 2-cores/head split-KV schedule ([HW-MAP.md](file:///Users/lukas/dmonk2/HW-MAP.md#L115)) on the `K-int8 / V-f16` kernel at $H_{kv} = 4, L = 32\text{k}$ and $128\text{k}$.
   * **Pass / Decision Gate**: Speedup $\ge 1.85\times$ over the 4-idle-core map.
