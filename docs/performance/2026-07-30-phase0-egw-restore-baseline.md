# Phase 0 Event Graph Walker restore baseline

Date: 2026-07-30

Commit: `6fc587bc3d94214a887a118bd24267b1bb96c1bf`

## Question

Can the published `dowdiness/event-graph-walker@0.6.0` container façade restore
semantically valid Living Chronicle-shaped checkpoints at 1,000 and 10,000
operations within a conservative local Phase 0 budget?

This is a core decode/apply measurement. It is not a browser-loading, IndexedDB,
network, projection, DOM, or mobile-device benchmark.

## Environment

- OS/kernel: WSL2, Linux `6.6.114.1-microsoft-standard-WSL2`, x86_64
- CPU: AMD Ryzen 7 6800H with Radeon Graphics
- Node: `v24.14.1`
- Moon: `0.1.20260713 (75c7e1f 2026-07-13)`
- moonc: `v0.10.4+2cc641edf (2026-07-15)`
- moonrun: `0.1.20260713 (75c7e1f 2026-07-13)`
- Build: release
- Targets: JS first, then wasm-gc; targets were measured sequentially
- Explicit application warm-up: none. Moon's benchmark harness performed its
  normal calibration and reported 10 measurements per case.

The earlier README values measured JS and wasm-gc concurrently and are
superseded by this sequential run because shared-host contention materially
inflated them.

## Method

`benchmarks/phase0/egw_probe_benchmark.mbt` builds source fixtures outside the
timed closure. Before timing each fixture, it performs one complete restore and
asserts:

- applied tree/text operation counts;
- zero pending operations;
- contribution child count;
- restored text length and full content;
- first and last contribution body properties.

Each timed iteration measures only:

1. fresh receiver `Document` construction;
2. receiver-bound JSON decode;
3. `SyncSession::apply`.

### Workloads

| Name | Contributions | Text codepoints | Tree ops | Text ops | Total ops |
|---|---:|---:|---:|---:|---:|
| property-1k | 1,000 | 0 | 2,001 | 0 | 2,001 |
| text-1k | 0 | 1,000 | 1 | 1,000 | 1,001 |
| mixed-1k | 250 | 499 | 501 | 499 | 1,000 |
| mixed-10k | 2,500 | 4,999 | 5,001 | 4,999 | 10,000 |

The property and text isolates have different total operation counts and must
not be interpreted as a property-vs-text per-operation comparison.

## Pre-registered local Phase 0 gates

These gates classify this machine-level integration experiment only:

- semantic fixture verification passes;
- mixed-10k checkpoint remains below an 8 MiB product decode cap, which is
  deliberately below EGW's 16 MiB protocol default;
- mixed-10k mean restore is below 2 seconds on JS and wasm-gc;
- mixed-10k observed maximum is below 3 seconds;
- coefficient of variation (`sigma / mean`) is below 20%.

Passing these gates does not establish a browser p95 or justify increasing the
active-document cap beyond 10,000 operations.

Normal CI executes `egw_probe_benchmark.mbt` on both benchmark targets. That
continuously enforces the baseline fixture semantics, exact mixed operation
counts, the deterministic 8 MiB checkpoint cap, and benchmark executability.
Detailed component investigations remain manual so they do not add several
minutes to every change. CI does not compare wall-clock values against the local
timing gates because shared-runner timing is not a stable regression signal;
dated controlled runs own those measurements.

## Commands

```bash
moon bench --release --target js benchmarks/phase0 --no-parallelize
moon bench --release --target wasm-gc benchmarks/phase0 --no-parallelize
```

## Results

### Checkpoint sizes

| Workload | JSON bytes |
|---|---:|
| property-1k | 760,715 |
| text-1k | 455,763 |
| mixed-1k | 412,940 |
| mixed-10k | 4,230,684 |

### Timing

| Target | Workload | Mean ± sigma | Min … max | Harness samples |
|---|---|---:|---:|---:|
| JS | property-1k | 264.41 ms ± 10.33 ms | 254.58 … 284.15 ms | 10 × 1 |
| JS | text-1k | 40.03 ms ± 2.62 ms | 37.62 … 46.31 ms | 10 × 3 |
| JS | mixed-1k | 52.95 ms ± 2.10 ms | 49.80 … 56.02 ms | 10 × 2 |
| JS | mixed-10k | 1.78 s ± 146.92 ms | 1.65 … 2.15 s | 10 × 1 |
| wasm-gc | property-1k | 178.86 ms ± 6.37 ms | 171.36 … 191.15 ms | 10 × 1 |
| wasm-gc | text-1k | 33.05 ms ± 1.43 ms | 31.10 … 34.92 ms | 10 × 4 |
| wasm-gc | mixed-1k | 38.16 ms ± 2.54 ms | 35.07 … 43.62 ms | 10 × 3 |
| wasm-gc | mixed-10k | 1.20 s ± 27.08 ms | 1.16 … 1.23 s | 10 × 1 |

Mixed-10k coefficients of variation are approximately 8.3% on JS and 2.3% on
wasm-gc.

## Gate result

| Gate | Result |
|---|---|
| Semantic restore | PASS |
| Mixed-10k below 8 MiB | PASS — 4,230,684 bytes |
| Mean below 2 s | PASS — JS 1.78 s, wasm-gc 1.20 s |
| Observed max below 3 s | PASS — JS 2.15 s, wasm-gc 1.23 s |
| Variation below 20% | PASS |

**Phase 0 local restore gate: PASS, with a scaling warning.**

A 10x increase from mixed-1k to mixed-10k increased mean restore time by about
33.6x on JS and 31.4x on wasm-gc. The absolute local gate passes, but the growth
is materially superlinear and agrees with upstream performance concerns. The
initial active IncidentDocument budget is therefore capped at 10,000 operations
and 8 MiB, whichever comes first. Rotation should happen earlier when device
measurements or projection work consume the remaining latency budget.

## Raw output

### JS

```text
property-1k: checkpoint_bytes=760715 tree_ops=2001 text_ops=0
text-1k: checkpoint_bytes=455763 tree_ops=1 text_ops=1000
mixed-1k: checkpoint_bytes=412940 tree_ops=501 text_ops=499
mixed-10k: checkpoint_bytes=4230684 tree_ops=5001 text_ops=4999
phase0 restore 1k atomic-property contributions
  264.41 ms ± 10.33 ms; 254.58 ms … 284.15 ms; 10 × 1 runs
phase0 restore 1k block-text codepoints
  40.03 ms ± 2.62 ms; 37.62 ms … 46.31 ms; 10 × 3 runs
phase0 restore mixed 1k operations
  52.95 ms ± 2.10 ms; 49.80 ms … 56.02 ms; 10 × 2 runs
phase0 restore mixed 10k operations
  1.78 s ± 146.92 ms; 1.65 s … 2.15 s; 10 × 1 runs
```

### wasm-gc

```text
property-1k: checkpoint_bytes=760715 tree_ops=2001 text_ops=0
text-1k: checkpoint_bytes=455763 tree_ops=1 text_ops=1000
mixed-1k: checkpoint_bytes=412940 tree_ops=501 text_ops=499
mixed-10k: checkpoint_bytes=4230684 tree_ops=5001 text_ops=4999
phase0 restore 1k atomic-property contributions
  178.86 ms ± 6.37 ms; 171.36 ms … 191.15 ms; 10 × 1 runs
phase0 restore 1k block-text codepoints
  33.05 ms ± 1.43 ms; 31.10 ms … 34.92 ms; 10 × 4 runs
phase0 restore mixed 1k operations
  38.16 ms ± 2.54 ms; 35.07 ms … 43.62 ms; 10 × 3 runs
phase0 restore mixed 10k operations
  1.20 s ± 27.08 ms; 1.16 s … 1.23 s; 10 × 1 runs
```

## Follow-up

- Measure full browser load, IndexedDB read, projection, and first render before
  defining a user-visible p95.
- Add 5k and 10k active-document checkpoints to browser/device tests.
- Revisit the 10,000-operation cap only after upstream superlinear insertion
  work and application-level browser evidence improve it.
