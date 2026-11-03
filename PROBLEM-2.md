# PROBLEM-2 — MoE grouped quant-GEMM decode kernel (the sparse-batch shape)

Same rules of engagement as PROBLEM.md: quantitative throughout, derive from
HW-MAP numbers, branch on UNMEASURED quantities, observable failure modes.
Round-1 deliverable: DESIGN-2.md. Round 2 (separate session) will demand a
core-Lean proof artifact with a claim ledger, per the established pattern.

## Workload (mixture-of-experts decode step, one die = 8 cores)

Per decode step with t tokens (t ∈ 1..16; t=1 pure decode, t≤16 speculative
verify batch):

- A router selects, per token, its top-k experts (k = 4..10, typical 8) from
  E experts (E = 64..512). Token τ activates expert e iff e ∈ top-k(τ).
- Each activated expert e owns a private weight slab W_e: **[K, N_e]**,
  K = 2048..7168, N_e = 512..4096, **W8 or W4** (same quant semantics as
  PROBLEM.md: i8 + per-channel scale, or i4 + per-group offset/scale).
  Per-expert token count m_e = |{τ : e ∈ top-k(τ)}| — almost always 1..3 at
  small t (distinct experts activated per step: min(top-k·t, E), typically
  8..128).
- Compute per activated expert: y_e[m_e, N_e] = s_e[n] · Σ_k x_e[m_e, k] ·
  W_e[k, n]; outputs scatter-add back to their tokens (weighted by router
  scores — assume scores arrive as f16 vectors, apply in the epilogue).
- Weights are static and offline-repackable. Activated-set changes every
  step. Per-step streamed weight bytes = Σ_{e active} K·N_e·(1 or 0.5).

Measured floor to beat: the vendor grouped quant op does this at
**24.6 GB/s** (HW-MAP). The dense single-slab design (DESIGN.md route 1
pattern) does 168 GB/s when there is exactly one giant expert — your job is
to keep that class of rate under grouping, sparsity, and imbalance.

## The three new design axes (this is where the problem lives)

1. **Activation set → core mapping.** Options include: expert-slab-contiguous
   packing with whole-expert assignment to cores (zero fragmentation, load =
   Σ bytes per core — imbalance risk under skewed routing); K- or N-split of
   experts across cores (balances bytes, adds cross-core reduction through
   host — errata #11 says exchanges bounce via host at 10.7 GB/s); hybrid.
   Formalize routing skew as a hypothesis family (uniform; Zipf(s) over
   expert popularity; adversarial single-hot) and prove per-core byte-loads
   and the resulting rate floor per family.
2. **Per-expert tiny-M batching.** m_e = 1..3 means the matrix unit runs its
   16-wide fragment mostly padded (same as PROBLEM.md — fine) but ALSO that
   tokens sharing an expert are the only free lunch: group them. Derive when
   gathering shared-expert tokens beats separate passes, and the t-kernel
   curve analogue for grouped shapes.
3. **Dispatch cost.** Router outputs arrive as small index/score tensors in
   DDR. Someone must turn them into per-core work descriptors (expert list,
   token lists, slab addresses). Options: host pre-pass per step (adds host
   round-trip latency — quantify against the ~91 µs launch floor), vector-unit
   on-pass on one core, dedicated tiny kernel. Cost each in measured units;
   the wrong answer here can eat the entire step budget at t=1.

## Targets

- t=1, uniform routing, W8: **≥120 GB/s** effective over streamed expert
  weight bytes (the same gate as the dense design); stretch 150+.
- Skew degradation must be a THEOREM, not a vibe: under Zipf(s) routing,
  predicted GB/s as a function of s, with the imbalance threshold where the
  byte-balanced-but-host-reduction hybrid takes over.
- Step latency at t=1 must not regress vs the dense kernel by more than the
  dispatch cost — state the full step time budget: dispatch + gather(x) +
  grouped GEMM + scatter-add + scores.

## Deliverables (DESIGN-2.md, numbered)

1. Work decomposition + the three-axis design with the chosen point and why.
2. Weight slab packing spec (byte-level; extends DESIGN.md §3.1's geometry
   hypotheses — you inherit G1a/G1b/G1c/G2 and its pack-probe obligation).
3. Token gather / result scatter-add paths with costs.
4. Dispatch design (host vs vector vs tiny-kernel) with the latency budget.
5. Loop nest + tiling per expert pass (may reference DESIGN.md; only deltas
   needed) + the m_e-batching rule.
6. Buffer budgets vs hierarchy for the worst activated set (128 experts).
7. Skew model: hypothesis families, per-family rate theorems (these become
   Lean threshold theorems over the skew parameter — same pattern as the
   loader-rate L).
8. Predicted step-time table: t ∈ {1,4,16} × routing ∈ {uniform, Zipf(1.0),
   Zipf(1.5)} × W8/W4, GB/s effective + ms per step, derivations shown.
9. Experiment ladder (E-numbered, observable failure modes, differencing/
   oracle/pass-rate style; include a routing-skew synthetic generator spec).
10. Risk register + what each UNMEASURED quantity unlocks (which measurement
    most changes the ranking — name exactly one).
