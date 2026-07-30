# Event Graph Walker restore component breakdown

Date: 2026-07-30

Benchmark source commit: `0521cb9ffae48198c8982459c1ad5f2b767ca7e9`

Event Graph Walker: `dowdiness/event-graph-walker@0.6.0`
(`c522b536f481da6e7d7be16198c9503c83d41f6b`)

## Question

Which current `container.Document` component explains the superlinear restore
result: receiver construction, receiver-bound JSON decode, predecoded sync
apply, or interaction between tree moves and retained properties?

This investigation uses current v0.6.0 behavior. Historical Issue #73 numbers
are not inputs to the decision.

As a separate current-code check, the upstream v0.6.0 container benchmarks were
rerun before this breakdown. JS sequential text grew from 83.91 ms at 1k to
9.79 s at 10k (116.67x), and sequential tree from 80.60 ms to 5.72 s
(70.97x). wasm-gc text grew from 74.03 ms to 14.70 s (198.57x), and tree from
56.69 ms to 6.24 s (110.07x). A single append against prebuilt 10k state was
still small on JS—2.58 ms for text and 2.48 ms for tree—so Issue #73 remains a
bulk-growth concern rather than evidence that one ordinary edit misses an
interaction budget.

## Environment

- OS/kernel: WSL2, Linux `6.6.114.1-microsoft-standard-WSL2`, x86_64
- CPU: AMD Ryzen 7 6800H with Radeon Graphics
- Node: `v24.14.1`
- Moon: `0.1.20260713 (75c7e1f 2026-07-13)`
- moonc: `v0.10.4+2cc641edf (2026-07-15)`
- moonrun: `0.1.20260713 (75c7e1f 2026-07-13)`
- Build: release
- Targets: JS followed by wasm-gc, measured sequentially
- Harness: 10 reported measurements per case, no explicit application warm-up

## Matched property fixtures

`benchmarks/phase0/egw_restore_breakdown_benchmark.mbt` creates two fixtures
with the same operation count, contribution count, property values, and final
application projection:

- **grouped:** create every contribution, then set every body property;
- **interleaved:** create one contribution, immediately set its body property,
  then repeat.

An incident create and final incident marker property make the requested totals
exact: 1,000, 5,000, and 10,000 tree operations. For 10,000 operations each
fixture has 4,999 contribution creates, 4,999 body properties, one incident
create, and one incident property.

Before timing, every fixture is restored and checked for:

- exact decoded/applied operation count;
- zero text and pending operations;
- exact contribution count;
- incident marker property;
- first and last contribution body properties.

Grouped and interleaved JSON sizes differ by about 4.4% at 10k because causal
identities and dependencies reflect their different operation order. The apply
comparison uses predecoded `SyncMessage` values, so JSON parsing and byte length
are excluded from that timing.

## Timed boundaries

- **receiver baseline:** construct an empty `Document` and retain its version.
- **decode:** reuse an empty receiver, call `decode_json`, retain message count.
- **apply:** decode once outside timing; each iteration constructs a fresh empty
  receiver and applies the same predecoded message.

The apply result includes public `SyncSession::apply` preparation and commit;
there is no public seam that times its private commit shell separately.

## Commands

```bash
moon bench --release --target js \
  -p dowdiness/living_chronicle/benchmarks/phase0 \
  -f egw_restore_breakdown_benchmark.mbt --no-parallelize

moon bench --release --target wasm-gc \
  -p dowdiness/living_chronicle/benchmarks/phase0 \
  -f egw_restore_breakdown_benchmark.mbt --no-parallelize
```

## Checkpoint sizes

| Fixture | 1k | 5k | 10k |
|---|---:|---:|---:|
| grouped decode fixture | 405,286 B | 2,045,784 B | 4,143,282 B |
| grouped apply fixture | 400,788 B | 2,023,286 B | 4,098,284 B |
| interleaved apply fixture | 418,780 B | 2,113,278 B | 4,278,276 B |

Labels are part of replica identities, so separately generated decode/apply
fixtures have slightly different sizes despite the same shape.

## Results

### JS

| Component | 1k | 5k | 10k | 1k→10k |
|---|---:|---:|---:|---:|
| decode grouped | 25.73 ms | 201.10 ms | 424.25 ms | 16.49x |
| apply grouped | 64.91 ms | 296.34 ms | 406.92 ms | 6.27x |
| apply interleaved | 96.24 ms | 2.52 s | 12.64 s | 131.34x |

Receiver construction: `1.13 µs ± 95.28 ns`.

At 10k, interleaved apply is **31.06x** grouped apply. Even the interleaved
minimum (`10.82 s`) is 24.4x the grouped maximum (`443.42 ms`).

### wasm-gc

| Component | 1k | 5k | 10k | 1k→10k |
|---|---:|---:|---:|---:|
| decode grouped | 14.87 ms | 102.02 ms | 375.31 ms | 25.24x |
| apply grouped | 35.07 ms | 145.06 ms | 354.13 ms | 10.10x |
| apply interleaved | 81.66 ms | 1.67 s | 8.06 s | 98.70x |

Receiver construction: `358.35 ns ± 22.34 ns`.

At 10k, interleaved apply is **22.76x** grouped apply. Even the interleaved
minimum (`6.93 s`) is 17.5x the grouped maximum (`395.88 ms`).

### Raw mean, sigma, and range

| Target | Case | Mean ± sigma | Min … max |
|---|---|---:|---:|
| JS | decode 1k | 25.73 ms ± 3.66 ms | 21.96 … 33.43 ms |
| JS | decode 5k | 201.10 ms ± 73.14 ms | 125.14 … 300.23 ms |
| JS | decode 10k | 424.25 ms ± 160.75 ms | 245.28 … 711.14 ms |
| JS | grouped apply 1k | 64.91 ms ± 16.79 ms | 52.09 … 107.24 ms |
| JS | grouped apply 5k | 296.34 ms ± 131.79 ms | 183.76 … 540.13 ms |
| JS | grouped apply 10k | 406.92 ms ± 19.43 ms | 373.05 … 443.42 ms |
| JS | interleaved apply 1k | 96.24 ms ± 10.37 ms | 84.47 … 112.99 ms |
| JS | interleaved apply 5k | 2.52 s ± 442.53 ms | 2.05 … 3.47 s |
| JS | interleaved apply 10k | 12.64 s ± 1.86 s | 10.82 … 15.91 s |
| wasm-gc | decode 1k | 14.87 ms ± 0.70 ms | 13.77 … 15.83 ms |
| wasm-gc | decode 5k | 102.02 ms ± 9.58 ms | 87.57 … 118.83 ms |
| wasm-gc | decode 10k | 375.31 ms ± 86.97 ms | 252.52 … 491.67 ms |
| wasm-gc | grouped apply 1k | 35.07 ms ± 8.77 ms | 24.81 … 50.39 ms |
| wasm-gc | grouped apply 5k | 145.06 ms ± 17.68 ms | 128.14 … 175.70 ms |
| wasm-gc | grouped apply 10k | 354.13 ms ± 32.87 ms | 310.89 … 395.88 ms |
| wasm-gc | interleaved apply 1k | 81.66 ms ± 5.14 ms | 75.06 … 89.65 ms |
| wasm-gc | interleaved apply 5k | 1.67 s ± 180.19 ms | 1.48 … 1.96 s |
| wasm-gc | interleaved apply 10k | 8.06 s ± 1.00 s | 6.93 … 9.77 s |

## Current-code interpretation

Receiver construction is negligible. Decode shows a noisy 16–25x increase for
a 10x operation increase and costs about 0.4 seconds at 10k; that deserves a
repeatable parser/structural-validation breakdown before being called a
separate defect.

Predecoded grouped apply remains below 0.5 seconds at 10k on both targets. The
severe growth appears only when property operations are interleaved with tree
moves.

In current EGW v0.6.0, `Document::apply_move_op` applies the move and then calls
`Document::reapply_properties`. `reapply_properties` iterates the complete
retained property state after every move. Grouped replay performs all moves
while property state is empty. Interleaved replay grows property state before
each later move, yielding a cumulative scan consistent with quadratic work.
The matched result, its non-overlapping ranges, and the current source path
confirm a material property-replay interaction in public container sync apply.

This is distinct from Issue #73, which tracks local `insert_text` and
`create_node` generation paths. Post-Issue remote-admission optimizations in
`internal/oplog` do not serve `container.SyncSession::apply`.

## Decision

**A separate upstream issue is warranted.** Proposed title:

> [`#98 perf(container): isolate quadratic property replay during full-sync tree apply`](https://github.com/dowdiness/event-graph-walker/issues/98)

Recommended scope:

1. add the grouped/interleaved 1k/5k/10k predecoded-apply matrix to EGW;
2. add a deterministic private work counter or isolated benchmark for
   `reapply_properties` calls and visited properties;
3. preserve undo/redo semantics that require properties to survive move replay;
4. prototype only after the private counter confirms attribution;
5. compare JS and wasm-gc and retain convergence/failure-atomicity gates.

The upstream investigation is tracked in
[`dowdiness/event-graph-walker#98`](https://github.com/dowdiness/event-graph-walker/issues/98).
Current v0.6.0 local-growth measurements and the scope split are recorded on
[Issue #73](https://github.com/dowdiness/event-graph-walker/issues/73#issuecomment-5131576474).

## Product implication

A total-operation cap alone does not predict restore cost. Until the property
replay path is fixed, Living Chronicle must retain a separate contribution cap.
The current 500-contribution MVP cap is consistent with the approximately 1k
interleaved fixture; 10k property-interleaved operations are not an acceptable
restore workload despite remaining below the byte cap.
