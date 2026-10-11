# Server implementation baseline

This file records the PostgreSQL reference behavior immediately before the
Local release-profile implementation. It is a regression baseline, not a
performance promise.

Recorded on 2026-10-11 from commit `0a008ea` using PostgreSQL 17 from the root
Compose configuration on an isolated local port.

## Automated baseline

- Platform suite: 212 passed, 1 load test excluded.
- Test duration reported by ExUnit: 14.4 seconds.
- The expected invalid-package fixture emitted its handled invalid-BEAM log.
- PostgreSQL remained the configured Ecto adapter.
- Oban used its PostgreSQL engine outside test-manual mode.

The decision gate required the PostgreSQL suite, explicit planner load test,
production release build, and existing Extension suites to remain green. The
final comparison below records that result. Later performance comparisons must
use the same machine, database container, and test inputs; elapsed values in
this document are diagnostic rather than portable benchmarks.

## Post-boundary comparison

Recorded on the same development machine on 2026-10-11 after introducing the
storage boundary. PostgreSQL 17 ran through Compose on host port 55432.

- Platform suite: 216 passed, 1 load test and 1 benchmark excluded; 15.0 seconds.
- Forced application compilation with warnings as errors: passed.
- 10,000-item bounded planner test: passed in 2.3 seconds.
- Empty PostgreSQL database creation from the single clean Server baseline:
  passed.
- Production assets: built and digested successfully.
- Production OTP release: built at the conventional
  `_build/prod/rel/couriercms` path used by the Dockerfile.
- Dependency audit: passed with only the two documented unused Cloak-path
  exceptions.

Existing focused tests cover fake-to-fake delivery and retry, delivery-lock
contention and expiry recovery, connection concurrency, overlapping scheduled
Runs, checkpoint safety, stranded planning and item reconciliation, and atomic
Connector Event acceptance. They run as part of the complete platform suite.

## Reproducible performance sample

Run:

```powershell
cd platform
$env:COURIERCMS_RELEASE_PROFILE = "server"
$env:MIX_ENV = "test"
mix test test/load/server_baseline_test.exs --include benchmark --trace
```

The 500-item sample recorded:

| Measurement | Result |
| --- | ---: |
| Planning | 165 ms / 31 queries |
| Sequential fake delivery | 37,835 ms / 25,506 queries |
| Fake delivery throughput | 13.22 items/second |
| Final reconciliation | 8 ms / 4 queries |
| Bounded Run operator page mount | 252 ms / 22 queries |

These figures are a regression reference for this machine, not product
capacity claims. Delivery intentionally runs sequentially in this benchmark so
results do not depend on scheduler concurrency. Set
`COURIERCMS_BASELINE_ITEM_COUNT` to an integer from 100 through 10,000 to repeat
the same workload at another size.

CI runs the 500-item sample with `COURIERCMS_ENFORCE_BASELINE=true`. It enforces
stable query-count ceilings and deliberately generous elapsed-time ceilings so
a shared runner catches material regressions without turning normal host
variance into noise. Every ceiling can be overridden with the corresponding
`COURIERCMS_MAX_*` environment variable defined in the test.

## Final dual-profile comparison

The completed implementation was measured again on the same machine and
database container. The Server suite passed 217 tests (with Server-inapplicable
Local tests excluded). The identical 500-item benchmark reported 158 ms
planning, 37,661 ms delivery (13.28 items/second), 7 ms reconciliation, and a
204 ms operator-page mount, with unchanged query counts. These values show no
measured Server regression from the recorded reference; they are still only a
development-machine guardrail, not a throughput guarantee.

