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

## Automated release evidence

The repository test matrix must establish the portable correctness baseline on
both PostgreSQL and SQLite. In particular it covers atomic planning and job
creation, item and asset retries, ownership checks, overlapping Runs,
checkpoint advancement, deterministic duplicate protection, missing-job
reconciliation, and temporary-file cleanup. The official-package integration
test also carries a WordPress Content Bundle and authenticated asset through a
failed-then-retried Sanity upload before creating the final delivery document.

These tests prove application invariants. They do not substitute for operating
system, network, or multi-node release-candidate drills.

## Release-candidate environment gates

Complete and record these checks against the exact artifacts intended for
publication:

- run the Windows Local ZIP on a clean machine without Elixir or Erlang;
- interrupt the Local process during planning, asset download, target upload,
  and Delivery Item delivery, then verify restart and reconciliation;
- suspend and resume the laptop during an active Run and while a schedule is
  due;
- stream representative maximum-size assets while recording process maximum
  resident memory and confirming that no partial temporary files remain;
- run Server web and worker roles as separate processes, then repeat with more
  than one worker node to exercise PostgreSQL locks, leases, and contention;
- run a disposable WordPress-to-Sanity delivery with realistic credentials,
  authenticated media, source throttling, and a forced transient target
  failure; and
- inspect the Local ZIP and Server image for credentials, development files,
  and unintended generated artifacts.

Record the artifact checksum, operating-system version, database version,
extension checksums, dataset size, elapsed time, throughput, maximum memory,
and outcome. A failed gate blocks publication until it is understood; it is not
converted into an undocumented exception.

CourierCMS provides health endpoints, durable jobs, worker heartbeats, bounded
planning, retention controls, and recovery commands. Deployment owners remain
responsible for PostgreSQL availability, off-site backups, restore drills,
orchestration, monitoring backends, paging ownership, and network controls.
