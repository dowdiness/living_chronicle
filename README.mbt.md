# dowdiness/living_chronicle

A MoonBit, local-first collaborative story-world experiment built on
[Event Graph Walker](https://github.com/dowdiness/event-graph-walker).

The architecture and staged implementation plan live in
[`docs/architecture/event-graph-walker-living-chronicle-plan.md`](docs/architecture/event-graph-walker-living-chronicle-plan.md).

## Phase 0: Event Graph Walker integration gates

The first phase pins `dowdiness/event-graph-walker@0.6.0` and verifies its
public `container` façade through application-level black-box probes.

Current probes establish that:

- after the original live replica is retired, a full JSON sync export can
  restore its replacement with the same replica ID;
- that replacement can continue editing without reusing an operation identity;
- a peer already holding the pre-restart checkpoint can apply only the
  replacement's continuation delta and converge;
- exact duplicate delivery is idempotent and reported as duplicate operations;
- concurrent contribution appends converge under opposite delivery orders;
- decoded-operation and encoded-byte limits reject oversized input atomically.

Run the verification suite from the repository root:

```bash
moon check --target all --deny-warn
moon test --target all
moon fmt
moon info
```

Run the release-mode restore probes:

```bash
moon bench --release --target js benchmarks/phase0 --no-parallelize
moon bench --release --target wasm-gc benchmarks/phase0 --no-parallelize
```

### Initial local benchmark evidence

Environment: Moon `0.1.20260713`, moonc `v0.10.4+2cc641edf`. These are
single-machine directional baselines, not product SLOs.

| Restore workload | JS mean ± σ | wasm-gc mean ± σ |
|---|---:|---:|
| 1,000 immutable property contributions (2,001 tree operations) | 630.24 ms ± 164.60 ms | 332.98 ms ± 26.58 ms |
| 1,000 block-text codepoints | 96.36 ms ± 23.58 ms | 86.27 ms ± 13.47 ms |

The property workload intentionally creates one node and one atomic body
property per contribution. The result supports bounded IncidentDocuments and
document rotation rather than a world-sized CRDT document.

Replica-ID reuse is a restart-only restore workflow. Two concurrently live
replica instances must never share an ID; cloned profiles require a new replica
incarnation or conflict quarantine and command-level rebase.
