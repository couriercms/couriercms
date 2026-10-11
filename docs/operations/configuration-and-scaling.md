# Operations

This guide describes the Server profile. Local always uses one process, one
SQLite database, an implicit operator, and a loopback listener. Local uses the
same scheduler, but scheduled work can execute only while the application is
running; startup reconciliation recovers durable work interrupted by a stop.
See [Local mode](../development/local-mode.md).

## Initial deployment

V0 targets Docker Compose with two required services:

```text
couriercms
postgres
```

CourierCMS may call configured cloud CMS APIs and private self-hosted CMS endpoints. Optional CMS Connectors are installed separately in their CMS.

Native OTP Extensions are installed as trusted precompiled `.couriercms` packages
in `COURIERCMS_EXTENSIONS_PATH` and loaded only when a CourierCMS node starts. The initial
Extension system supports one installed version per Extension ID and no hot
reload. Every node eligible to validate or execute an Extension component must
have the identical package version and checksum.

The production image bundles the official packages in
`/var/lib/couriercms/extensions`. To manage packages outside the image, mount a
read-only host directory at that path (or set `COURIERCMS_EXTENSIONS_PATH` to a
different mounted directory) on every eligible node. Keep the writable
`COURIERCMS_EXTENSION_CACHE_DIR` on a separate volume; do not mount it over the
package directory.

The repository includes a directly runnable override for the normal local
package directory:

```sh
sh ./scripts/prepare-extensions.sh --include-fake
docker compose -f compose.yaml -f compose.extensions.yaml up
```

On Windows, run `scripts/prepare-extensions.ps1 -IncludeFake` first. The
override bind-mounts `.local/extensions` read-only into the combined, web,
worker, and migration services. A mounted directory replaces the packages
bundled in the image, so it must contain every official or custom Extension the
deployment needs.

The loader rejects unsafe ZIP paths, checksum/signature failures, incompatible
runtimes, duplicate IDs, module collisions, invalid callbacks, and source code.
One rejected package is recorded as a diagnostic and does not prevent unrelated
Extensions or the CourierCMS admin surface from starting. The extracted cache is
rebuildable and must be writable by CourierCMS; the active package directory should
be read-only to the application process after deployment.

The default `COURIERCMS_ROLE=all` runs Phoenix, all Oban queues, and periodic scheduling in one CourierCMS process. This preserves the local development and small self-hosted setup. Upgrading requires `mix ecto.migrate` (or `/app/bin/migrate` in the release), but never a PostgreSQL reinstall or database reset.

For independent scaling, run the same CourierCMS release against the same PostgreSQL database with separate roles:

```text
web node:     COURIERCMS_ROLE=web
worker node:  COURIERCMS_ROLE=worker
```

Web nodes serve HTTP and enqueue durable jobs but execute no queues. Worker nodes do not listen for HTTP traffic. Configure worker queue allocation with a comma-separated allowlisted value such as:

```text
COURIERCMS_QUEUES=route_planning:2,delivery:20,webhooks:5,maintenance:1
```

The supported queues are `route_planning`, `delivery`, `webhooks`, and `maintenance`. Concurrency applies per node, so two nodes configured with `delivery:20` may execute up to 40 delivery jobs. Size the total against PostgreSQL capacity and source/target CMS rate limits.

The delivery queue value controls available worker processes. The per-Connection
limit in the Connections UI is a cluster-wide safety boundary backed by database
leases; it defaults to `COURIERCMS_DEFAULT_CONNECTION_CONCURRENCY`. A delivery needs
capacity from both its source and target Connections.

The same screen configures a cluster-wide requests-per-second limit. PostgreSQL
rate buckets enforce it across nodes and default to
`COURIERCMS_DEFAULT_CONNECTION_REQUESTS_PER_SECOND`.

Worker-only nodes disable periodic scheduling by default. Set `COURIERCMS_SCHEDULER_ENABLED=true` on one designated worker that consumes the `maintenance` queue. Combined `all` nodes retain the scheduler by default; it can be disabled explicitly when another node owns scheduling.

Oban pauses queues and allows active jobs to finish during normal shutdown. `COURIERCMS_SHUTDOWN_GRACE_PERIOD_MS` changes its 15-second default when adapters require more drain time. Jobs that cannot finish remain recoverable through Oban's at-least-once execution model.

All nodes must use the same `DATABASE_URL`, `COURIERCMS_INSTALLATION_ID`, `COURIERCMS_VAULT_KEY`, and compatible application release. Web nodes must also share `SECRET_KEY_BASE`. Adjust `POOL_SIZE` per node so aggregate database connections remain within server limits.

Periodic delivery uses an Oban Cron dispatcher every minute. A Route's selected
interval is stored in its immutable Route Revision. The dispatcher creates a
normal scheduled Run, so progress, item failures, retries, and history use the
same operational path as manual delivery.

Owners and admins configure the polling strategy per Route. `Incremental with
full fallback` is the default: the first Run establishes a Full Scan checkpoint,
subsequent Runs request the bounded change window, and a configurable daily,
weekly, or 30-day reconciliation performs another Full Scan. `Full scan every
run` is available for small sources or troubleshooting. Each scheduled Run
records the effective strategy and reason in its history.

If the previous scheduled Run is still queued, planning, or running when the
next interval becomes due, CourierCMS coalesces the tick instead of creating an
overlapping scheduled Run. The next Run resumes from the durable checkpoint.

Retry attempts, retry backoff caps, planning page limits, and retention delete
batch size have bounded deployment defaults. Configure them with
`COURIERCMS_DELIVERY_MAX_ATTEMPTS`, `COURIERCMS_PLANNING_MAX_ATTEMPTS`,
`COURIERCMS_DELIVERY_BACKOFF_CAP_SECONDS`,
`COURIERCMS_PLANNING_BACKOFF_CAP_SECONDS`, `COURIERCMS_MAX_PLANNING_PAGES`, and
`COURIERCMS_RETENTION_BATCH_SIZE`. Per-Connection concurrency remains the normal CMS
load-control mechanism; its absolute safety ceiling is not a deployment tuning
knob.

Connector events are visible at `/connector-events`. Every Connector uses the
generic `/api/connectors/:connection_id/events` ingress contract. The public
webhook endpoint is authenticated by HMAC rather than a browser session. It
requires accurate clocks on both hosts and an HTTPS URL reachable from the
external CMS.

## First owner and email

After migrations, bootstrap exactly one initial Workspace owner:

```text
mix couriercms.owner.create owner@example.com
```

Then start CourierCMS, open `/users/log-in`, request a link for that address, and
follow it. In development, Swoosh exposes delivered mail at `/dev/mailbox`. The
bootstrap command does not send mail and refuses to run after an owner exists.

Production uses SMTP and requires `SMTP_RELAY`, `SMTP_USERNAME`, and
`SMTP_PASSWORD`. Configure `SMTP_PORT`, `SMTP_SSL`, `MAIL_FROM_NAME`, and
`MAIL_FROM_ADDRESS` for the provider. Confirm that generated links use the public
HTTPS host before inviting users.

Owners and administrators invite users from `/users`. Users are blocked rather
than deleted. Keep at least two owners in a production installation so owner
recovery does not depend on direct database intervention.

## Production prerequisites

- HTTPS termination
- Persistent PostgreSQL storage
- Encryption key and Phoenix secrets supplied through deployment secret management
- Authenticated administrative access
- Reliable outbound email for magic-link authentication
- Outbound network rules permitting only required CMS endpoints where practical
- Inbound webhook route protection
- Time synchronization
- Backup and restore procedure tested

## Health

- `GET /health/live` returns liveness without checking dependencies.
- `GET /health/ready` returns readiness only when PostgreSQL is reachable, no
  migration is pending, the fresh node Extension fingerprints agree, and (when
  enabled) a worker heartbeat is fresh.

Set `COURIERCMS_REQUIRE_WORKER_READINESS=false` only when web availability must be
independent of workers. Worker-only nodes intentionally expose no HTTP endpoint.
Their container health check uses the non-HTTP release probe
`/app/bin/couriercms rpc "CourierCMS.Release.worker_health!()"`, which fails when
the release node, Oban, worker heartbeat process, or database is unavailable.

Production enables `COURIERCMS_REQUIRE_EXTENSION_CONSISTENCY=true` by default.
Setting it to `false` keeps readiness available during deliberate mixed-node
maintenance, but exact Run artifact enforcement still rejects affected work.
The `couriercms_extension_mismatched_nodes` metric and System > Extensions screen
remain available regardless of that readiness setting.

Configured CMS Connections are not part of application readiness; their status is monitored separately so one unavailable CMS does not remove CourierCMS from service.

## Telemetry

`GET /metrics` exports Prometheus text. Production requires an Authorization
header containing `Bearer <COURIERCMS_METRICS_TOKEN>`; use at least 32 random
characters and restrict the endpoint at the network boundary too.

At minimum emit metrics for:

- Run and Run Item counts by status
- Queue depth and age
- Delivery latency and throughput
- Adapter request duration and result category
- Retry counts and terminal failures
- Rate-limit responses
- Webhook accepted/rejected/deduplicated counts
- Checkpoint lag
- Processor duration and failures

Metric labels use low-cardinality Adapter/operation/status values, not item IDs, URLs, content, or credentials.

## Alerts

CourierCMS emails all active owners and administrators when a Run Item reaches a
terminal failure. The email contains only safe identifiers and a Run link. Set
`COURIERCMS_FAILURE_EMAIL_ALERTS=false` only when an external alert pipeline replaces
it.

Additional deployment monitoring should cover:

- Terminal Run Item failures above a configurable threshold
- Route planning/system failure
- Repeated authentication failure
- Webhook authentication failures or backlog
- Queue age beyond threshold
- Database/storage health

Alerts report safe identifiers and link operators to CourierCMS history. They do not include content payloads.

## Backups

Back up PostgreSQL and encryption-key material through separate protected mechanisms. A database backup without the correct encryption key cannot restore Connection credentials. Test restoration regularly.

CourierCMS does not back up target CMS content or source CMS content. A Route may
maintain a content-level mirror in another CMS, but that is a delivery use case,
not a substitute for database, asset, configuration, permission, or disaster-
recovery backups.

## Upgrades

- Back up before upgrades.
- Run database migrations as an explicit release step.
- Validate Adapter and checkpoint compatibility.
- Use rolling deployment only after job-execution compatibility across versions is designed.
- Never reinterpret stored Route Revisions silently.
- Before a rolling deployment, run
  `/app/bin/couriercms rpc "CourierCMS.Release.assert_job_compatibility!()"`. Version 2
  accepts existing unversioned, v1, and v2 jobs; any other active version aborts
  the check.

Core release upgrades and Extension upgrades are separate administrative
operations. For an Extension upgrade, pause and drain only affected Routes,
stop eligible nodes, atomically replace the package, restart, verify the
version/checksum on every node, and then resume. Queued work remains durable in
PostgreSQL. Exact per-Run artifact pinning prevents queued work from silently
using a replacement: a version/checksum/SDK mismatch blocks visibly. Draining
remains the normal procedure because this first runtime intentionally supports
only one installed version per Extension ID. See the
[Extension management](extension-management.md).

Owners and administrators can inspect the current node at
`/system/extensions`. The screen is intentionally read-only: it shows loaded,
missing, incomplete, and rejected Extensions, their components and artifact
metadata, and durable Connection/Route/unfinished-Run reference counts. Before
replacing or removing packages, use:

```text
/app/bin/couriercms rpc "CourierCMS.Release.verify_extensions!()"
/app/bin/couriercms rpc "CourierCMS.Release.assert_extension_removable!(\"com.example.extension\")"
```

Neither command installs or deletes code. Package changes remain controlled
filesystem operations followed by a node restart.

`verify_extensions!()` also fails while a fresh eligible node reports a
different fingerprint. During a deliberate upgrade, run it only as the final
consistency gate after all eligible nodes have restarted.

Every heartbeat contains the node role, release version, Extension artifact
fingerprint, and a content-free component artifact list. Fresh `all`, `web`, and
`worker` nodes are compared. A mismatch makes readiness fail when consistency
enforcement is enabled, emits `couriercms_extension_mismatched_nodes`, and is shown
on System > Extensions. Adapter credentials and content are never included.

## Retention and key rotation

History retention is off by default. Enable `COURIERCMS_RETENTION_ENABLED=true` and
set the Run, Connector event, and audit retention days. Cleanup is batched daily;
completed Oban jobs use Oban's separate one-day pruner.

Connection credentials can be replaced from `/connections`. Rotating a
Connector signing-secret rotation keeps the previous secret valid for 24 hours
so the external Connector can be updated without losing events.

To rotate the vault key, deploy with a new `COURIERCMS_VAULT_KEY` and incremented
`COURIERCMS_VAULT_KEY_VERSION`, while also supplying the previous key and version.
Then run:

```text
/app/bin/couriercms rpc "CourierCMS.Security.VaultRotation.rotate!()"
```

After verifying every Connection can be loaded and tested, remove the previous
key variables. Backups made before rotation still require their matching old
key.

## Recovery principles

- Restarting CourierCMS must not duplicate target Delivery Items.
- Oban jobs may resume or retry; identity and ownership checks make this safe.
- Operators can replay terminal items after fixing configuration.
- A Full Scan rediscovers the complete Route selection but skips unchanged items.
- Force Full Redelivery rewrites every selected item with its existing stable identity and is the recovery action after a Destination is cleared or rebuilt.
- Resetting a checkpoint may rediscover content but must remain idempotent.
- Cancellation and rollback never delete target content.

See [deployment and upgrade](deployment-and-upgrade.md) and [backup and
restore](backup-and-restore.md). Additional runbooks should be added as
operator controls mature.
