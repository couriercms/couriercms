# ADR-0014: Crash-safe bounded execution

- Status: Accepted
- Date: 2026-09-24

[ADR-0019](0019-local-and-server-release-profiles.md) preserves these
reliability invariants for both profiles. The PostgreSQL coordination details
below are the Server implementation; Local uses SQLite-specific transactions
and leases within its required single-instance topology.

## Context

CourierCMS promises reliable at-least-once delivery while allowing the web tier and
workers to scale independently. Enumeration may discover many items, processes
may stop between database writes, two scheduler nodes may observe the same due
Route, and multiple workers may receive work for the same logical Delivery Item.
Source and target CMSs also have independent capacity and rate limits.

## Decision

- Persist each bounded source page, its Run Items, and its Oban delivery jobs in
  one PostgreSQL transaction.
- Advance an incremental checkpoint only after every page in the bounded window
  has been durably accounted for.
- Give scheduled windows a durable unique identity so more than one scheduler
  cannot create duplicate Runs.
- Serialize delivery for a logical Delivery Item with an expiring PostgreSQL
  lease. Oban uniqueness is an optimization, not the correctness boundary.
- Enforce cluster-wide per-Connection concurrency with PostgreSQL leases. Every
  delivery acquires source and target capacity in stable ID order.
- Bound source page size, Run item count, and canonical Delivery Document size.
- Let operators cancel undispatched work without attempting to undo accepted
  target writes.
- Use stable target document IDs when a target supports caller-supplied IDs.

## Consequences

Planner retries and scheduler overlap are safe. Worker nodes can be added without
silently multiplying load beyond Connection limits. A process crash may cause an
attempt to run again, but stable identity and target idempotency preserve the
intended result.

Leases must outlive the longest supported adapter request. They expire rather
than requiring manual cleanup after a crashed worker. Operators must size the
lease duration and Connection concurrency for their CMS APIs.

PostgreSQL is part of CourierCMS's coordination plane, not only its data store.

## Alternatives considered

- In-memory locks and counters do not coordinate separate worker machines.
- Oban uniqueness alone does not serialize jobs after execution starts.
- Holding an entire enumeration in memory is simpler but cannot provide a useful
  resource bound or safe checkpoint boundary.
- Exactly-once external delivery cannot be guaranteed across a database and an
  independent CMS API.
