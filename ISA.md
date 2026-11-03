# ISA — what the device actually gives you (sanitized)

A C++-like single-file kernel dialect; one program instance per core, all 8
cores of a die launched together. Engines per core: **copy-in** (DDR→SRAM),
**loader** (S1→L0 operand memories), **matrix unit**, **vector unit**,
**copy-out** (SRAM→DDR). Ordering across engines is YOUR job — queues give
automatic ordering only inside their own buffer mechanics (errata #8, #9).

## Matrix unit

```
MMA(dstC, A, B, {m, n, k, initVal, alignK, ...})
```
- Native fragment m=16; n and k take wider per-call values (library evidence:
  n=256, k=64 ran on this part — but that is library-internal, not a raw-MMA
  proof; sweep it yourself, content-checking every shape).
- `initVal`: first-k-tile zero-init vs accumulate — get it backwards and you
  keep only the last k-tile's product. A single-k-tile test CANNOT detect the
  inversion; always test with ≥2 k-tiles.
- Dtype combos: **f16×f16→f32, i8×i8→i32, f16×i8→f32**. The f16×i8 combo has
  executed and been timed but NOT yet been numerically verified — oracle it
  first (A = all-1.0 f16 tensor, B = known ints → exact column sums).
- A operand: f16 [16, K] per core (padded rows = 0), fractal-packed.
- B operand: i8 or f16 fractal-packed (geometry in HW-MAP).
- C accumulator: f32 (or i32 for i8×i8), fractal in L0C; readable only via
  staged reads through vector SRAM (row 0 only is ~4 KB/core at m=1).

## Loader (S1 → L0)

```
L0LOAD(dstL0, srcS1, params2D)     // also 3D variants, transpose variant
L0LOAD_GM(dstL0, srcDDR, params2D) // direct DDR→L0 — UNMEASURED (errata #1!)
```
Rate UNMEASURED — the single most valuable unknown to settle first. Guard any
L0LOAD use with a differencing test (two different sources through the same
L0 address, MMA result must change and match reference both times).

## Copies

```
COPY(dst, src, len)        // plain, ≤64 KB per call (errata #2), both SRAM and DDR positions
COPY_FRAC(dst, src, p)     // layout-transforming copy — SOFTWARE on this part, ~7 GB/s/core, avoid
```
Positions: DDR ↔ S1 ↔ vector SRAM plain copies are real (measured rates in
HW-MAP). Position pairs not in the measured table may be silent no-ops
(errata #1) — prove before use. No S1/L0→DDR copy exists.

## Vector unit

Elementwise/tensor ops on 128-lane reels: Mul/Muls/Add/Adds/And/Duplicate,
casts (i8→f16, i16→f16, f32↔f16). **≤1024 lanes per call** (errata #3);
sustained ~40 f16 lanes/cycle/core. Dedicated dequant instruction:
i4 (interleaved packing) + per-group offset/scale → f16, rate UNMEASURED.
Transcendentals (exp etc., e.g. for softmax): availability and rate
**UNMEASURED** — treat as an open quantity with both branches.

## Sync

Explicit pipe barriers between engines (copy-in / loader / matrix / vector /
copy-out). Cross-engine hand-rolled ordering without barriers is
nondeterministic (errata #8). A vendor mailbox/workspace mechanism exists for
library-internal cross-core sync; hand-rolled kernels have none — 8 cores are
independent except for the shared DDR roof.

## Fault model

Hangs fault via core watchdog (~seconds). Silent no-ops and silent
wrong-numbers do NOT fault (errata #1, MMA initVal, offset arithmetic).
Design every experiment so the failure mode is observable.
