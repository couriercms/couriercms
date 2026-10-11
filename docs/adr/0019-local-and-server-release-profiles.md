# ADR-0019: Local and Server release profiles

Status: Accepted

## Context

CourierCMS is useful both as a continuously operated delivery service and as a
temporary tool for one-time CMS migration work. Requiring PostgreSQL and a
server deployment before a user can evaluate a Route adds unnecessary friction
for the second case.

The delivery model must not split into separate products. Routes,
Destinations, Runs, Run Items, checkpoints, ownership, Extensions and the
canonical delivery document have the same meaning in every installation.
Reliability takes precedence over making the two storage engines look
identical internally.

## Decision

CourierCMS has two fixed release profiles built from one codebase:

Both artifacts are distributed under the repository's Apache License 2.0 and
use the same domain model, Phoenix/LiveView UI, execution workers, Extension
SDK, and Extension packages. A profile changes infrastructure and product
capabilities; it does not create a second implementation of the delivery
engine.

| Capability | Local | Server |
| --- | --- | --- |
| Database | SQLite | PostgreSQL |
| Manual Runs | Yes | Yes |
| Incremental polling | Yes | Yes |
| Full redelivery | Yes | Yes |
| Item retries | Yes | Yes |
| Reconciliation | Yes | Yes |
| Scheduling | While open | Continuous |
| Connector ingress | Initially no | Yes |
| Authentication | Implicit local operator | Required |
| Multiple users | No | Yes |
| Multiple processes/nodes | No | Yes |

Local binds to loopback and runs as one application instance. Server may bind
to an explicitly configured public interface and may run combined or split
web/worker roles.

The profiles are CourierCMS-defined constants selected when an artifact is
built. They are not a collection of independently supported user settings.
Ordinary runtime settings such as the HTTP port, SQLite file location and
queue concurrency remain configurable within the limits of a profile.

The two artifacts compile the public `CourierCMS.Repo` module with the
appropriate Ecto adapter. Domain code continues to use that single public Repo
API. Database-specific implementations are permitted for locking, leases,
operational queries and migrations when using a lowest-common-denominator
implementation would weaken correctness or PostgreSQL performance.

Extensions and Connectors do not have Local and Server variants. An Extension
uses the stable SDK contract and does not know which database persists a Run.
A Connector uses the same canonical event contract and a configured CourierCMS
base URL. Connector events accelerate discovery; authoritative pull, polling
and reconciliation remain available without them.

Local and Server installations have distinct installation identities and do
not share or synchronize databases. They must not deliver concurrently to the
same Destination. A future sanitized configuration export/import workflow may
promote configuration from Local to Server; copying database files is not that
workflow.

The project is unreleased. Introducing these profiles may replace the current
development migration history with clean PostgreSQL and SQLite baselines.
Existing development databases may be intentionally incompatible and can be
recreated.

## Reliability requirements

Both profiles preserve deterministic target identity, ownership protection,
atomic planning and job insertion, durable item-level retries, checkpoints,
overlap prevention, reconciliation and authoritative final recounts.

Local may use lower concurrency and has laptop-dependent availability. Those
are capacity and operational differences, not weaker delivery semantics.
PostgreSQL remains the production and scale reference. Existing PostgreSQL
locking and query performance must not regress merely to accommodate SQLite.

## Consequences

- The platform gains a two-database CI matrix and two release artifacts.
- Schema changes must be verified against PostgreSQL and SQLite.
- A small storage-specific infrastructure layer is expected.
- Local mode materially reduces evaluation and one-time migration setup cost.
- A Local SQLite database may contain sensitive operational data and encrypted
  credentials; it is not a client report or portable configuration bundle.
- Windows is the first supported downloadable Local artifact. Other operating
  systems can follow after the release workflow is proven.

