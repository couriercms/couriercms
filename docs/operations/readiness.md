# Production readiness

CourierCMS is pre-1.0. The code implements the core delivery and reliability
mechanisms, but production readiness is deployment-specific and is not a support
or availability promise.

Before production use, validate at minimum:

- database creation and forward migrations from an empty database;
- backup and isolated restore with the matching vault key;
- HTTPS, SMTP, DNS, time synchronization, and egress policy;
- health probes, metrics authentication, queue-age alerts, and log collection;
- official extension packages, checksums, compatibility, and identical node sets;
- realistic payload volume, memory, database I/O, and external CMS rate limits;
- process termination, stranded-job reconciliation, and replay drills;
- credential, webhook-secret, and vault-key rotation; and
- the operator procedure for pausing/draining Routes during extension upgrades.

CourierCMS provides health endpoints, durable jobs, worker heartbeats, bounded
planning, retention controls, and recovery commands. Deployment owners remain
responsible for PostgreSQL availability, off-site backups, restore drills,
orchestration, monitoring backends, paging ownership, and network controls.
