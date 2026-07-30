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
- non-BMP Unicode survives full restore and continuation-delta sync;
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

The reproducible environment, method, raw output, checkpoint sizes, and gates
are recorded in
[`docs/performance/2026-07-30-phase0-egw-restore-baseline.md`](docs/performance/2026-07-30-phase0-egw-restore-baseline.md).
These are single-machine core decode/apply measurements, not browser or product
SLOs.

| Restore workload | JSON bytes | JS mean ± σ | wasm-gc mean ± σ |
|---|---:|---:|---:|
| 1,000 immutable property contributions (2,001 tree operations) | 760,715 | 264.41 ms ± 10.33 ms | 178.86 ms ± 6.37 ms |
| 1,000 block-text codepoints | 455,763 | 40.03 ms ± 2.62 ms | 33.05 ms ± 1.43 ms |
| 1,000 mixed operations | 412,940 | 52.95 ms ± 2.10 ms | 38.16 ms ± 2.54 ms |
| 10,000 mixed operations | 4,230,684 | 1.78 s ± 146.92 ms | 1.20 s ± 27.08 ms |

The mixed 10,000-operation local restore gate passes, but workload composition
matters. A matched
[property-replay breakdown](docs/performance/2026-07-30-egw-restore-breakdown.md)
measured 10k interleaved create/property apply at 12.64 s on JS and 8.06 s on
wasm-gc, versus 406.92 ms and 354.13 ms when the same operations were grouped.
The initial active IncidentDocument budget therefore applies all three limits:
500 contributions, 10,000 total operations, and 8 MiB; browser evidence may
lower them further.

Replica-ID reuse is a restart-only restore workflow. Two concurrently live
replica instances must never share an ID; cloned profiles require a new replica
incarnation or conflict quarantine and command-level rebase.
