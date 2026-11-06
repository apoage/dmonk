# dmonk

<p align="center">
  <img src="assets/monk.svg" alt="dmonk: a slim hooded monk with glowing red eyes">
</p>

Design notebook for running quantized LLM decode on a real inference accelerator: a measured hardware
map, a series of execution-layer design problems, the designs that answer them, and machine-checked
arithmetic (core Lean 4) behind every quantitative claim.

The device is described in vendor-neutral terms: a 2-die card, 8 cores per die, with copy / loader /
matrix / vector engines per core. Every number in `HW-MAP.md` was measured on silicon; anything not
measured is explicitly tagged **PRIOR** or **UNMEASURED**. The errata are verified device behavior, and
on this part a design that trips them fails *silently*, so they are treated as hard constraints.
The card is deliberately identified only by what the measurements say about it — no vendor names, no
spec sheets; every claim stands on its own measurement or proof.

## Reading order

1. **`HW-MAP.md`**: measured rates, memory sizes, fragment geometries, concurrency results, silicon errata.
2. **`ISA.md`**: the kernel-dialect primitives the designs are allowed to use (sanitized).
3. A problem and its design (below), then its proof ledger.

## Problems and designs

| # | Problem | Design | Proof | Ledger |
|---|---|---|---|---|
| 1 | Single-die W8/W4 decode matmul, `y = s · xW`, m = 1..64 | `DESIGN.md` | `proof/model.lean` | `PROOF-COVERAGE.md` |
| 2 | MoE grouped quantized GEMM | `DESIGN-2.md` | `proof/moe.lean` | `PROOF-COVERAGE-2.md` |
| 3 | Decode attention: paged KV, online softmax on the matrix unit | `DESIGN-3.md` | `proof/attn.lean` | `PROOF-COVERAGE-3.md` |
| 4 | Fleet partition planner: 4 cards × 2 dies, no P2P | `DESIGN-4.md` | `proof/fleet.lean` | `PROOF-COVERAGE-4.md` |
| 5 | Cross-problem search for alternative solution families | `ALTERNATIVES.md` | `proof/alt.lean` | `PROOF-COVERAGE-5.md` |

`PROBLEM*.md` state each problem. Each design and proof round was handed to an external AI assistant
session for adversarial review — the `PROMPT*.md` files are those briefs, and the round sections in
the ledgers record what the reviews corrected. Designs carry status banners at the top. When later
silicon measurements supersede a hypothesis, the banner says what changed, and the original body is
kept below as the record.

## How claims are verified

Each design has a Python model (`proof/*.py`) that recomputes every derived number under a label, and
a Lean file that fixes the same number as a theorem. The ledger (`PROOF-COVERAGE*.md`) maps each claim
in the design to its theorem and label and gives its status: PROVED, INPUT (a measurement taken as
given), EMPIRICAL (settled only by a named experiment), ASSUMPTION, or CORRECTED, where formalization
changed the claim.

The Lean files use **core Lean 4 only** (no Mathlib, no Batteries; closed by `decide` / `omega` /
`simp` with core lemmas, no `sorry`, no `native_decide`), and each compiles standalone.

```sh
# toolchain: leanprover/lean4:v4.35.0 (via elan)
cd proof
lake build                 # all targets: Model, Smoke, Moe, Fleet, Attn, Alt
lean alt.lean              # or any single file, standalone

python3 alt.py             # print the labelled numbers a design quotes
```

## Layout

```
HW-MAP.md, ISA.md          measured hardware + primitives
PROBLEM*.md                problem statements
DESIGN*.md, ALTERNATIVES.md designs
PROOF-COVERAGE*.md         claim → theorem ledgers
PROMPT*.md                 design / proof round prompts
proof/                     *.lean theorems, *.py models, lakefile
```
