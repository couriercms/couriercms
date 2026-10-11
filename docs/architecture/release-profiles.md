# Release profiles

CourierCMS produces Local and Server artifacts from one source tree. The
profiles choose deployment infrastructure and fixed security behavior; they do
not fork the delivery domain or create Extension variants.

| Capability | Local | Server |
|---|---:|---:|
| Manual Runs | Yes | Yes |
| Incremental polling | Yes | Yes |
| Full redelivery | Yes | Yes |
| Item retries and reconciliation | Yes | Yes |
| Scheduling | While running | Continuous |
| Connector ingress | No | Yes |
| Identity | Implicit local operator | Authenticated users |
| Processes and nodes | One | One or more |
| Database | SQLite | PostgreSQL |

`CourierCMS.ReleaseProfile` is the single source of truth for these fixed
choices. It is deliberately not a general feature-flag system. The same domain
contexts still receive an authorized `Accounts.Scope`, and the same Oban
workers, SDK contracts, Extension packages, UI, and delivery invariants run in
both profiles.

Local uses one process and one database writer, recovers interrupted jobs at
startup, and forces loopback HTTP. Server retains PostgreSQL-specific locking,
rate limiting, notifications, and scalable roles. Database-specific code is
permitted behind narrow storage operations when it preserves correctness or
Server performance.

Local and Server databases are separate baselines. They are not synchronized,
and copying one database into the other profile is unsupported. A future
configuration export/import feature may promote configuration, but not active
Run or job state.

The authoritative decision is [ADR 0019](../adr/0019-local-and-server-release-profiles.md).
