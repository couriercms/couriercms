# Storage portability

CourierCMS keeps ordinary domain code on one `CourierCMS.Repo` API while the
compiled adapter is selected by the release profile. Server compiles PostgreSQL;
Local compiles SQLite.

## Boundaries

Database-specific behavior is isolated in `CourierCMS.Storage` and the focused
execution components it delegates to. This includes delivery locks, connection
leases and rate buckets, JSON lookup behavior, readiness, and transaction
details. PostgreSQL keeps its optimized implementations; SQLite uses serialized
operations appropriate to one Local process.

Small configuration collections use portable Ecto values. Durable correctness
does not rely on PostgreSQL notifications: jobs, Run Items, checkpoints,
ownership bindings, and reconciliation state remain authoritative in the
database.

## Schema parity checklist

Every schema change must be evaluated for both baselines:

- tables, columns, logical types, defaults, and nullability;
- primary, unique, and partial indexes;
- foreign keys, deletion behavior, and circular references;
- check constraints and ownership invariants;
- Oban schema compatibility;
- empty-database creation and migration;
- transaction and contention behavior.

SQLite may express an invariant differently from PostgreSQL, but tests must
prove the same externally observable result. Shared migrations are preferred;
adapter-specific migrations are acceptable when the databases require
different DDL.

Existing development databases from before the dual-profile baselines are
intentionally incompatible and may be deleted. Local and Server databases are
also mutually incompatible. The first public schema is represented by one
PostgreSQL initial migration and one SQLite initial migration; future changes
append migrations normally rather than rewriting either published baseline.
