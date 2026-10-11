# Deploy and upgrade CourierCMS

This page describes the Server profile. The downloadable Windows Local profile
is upgraded by stopping it, taking a Local backup, replacing the extracted
application files, and starting the new release against the persistent Local
data directory.

## Before deployment

1. Back up PostgreSQL and the separately stored `COURIERCMS_VAULT_KEY`.
2. Confirm the new image uses the same installation ID and vault key as the
   current deployment.
3. Review migrations and release notes. Do not mix releases whose job arguments
   or Route Revision interpretation are incompatible.
4. Run `/app/bin/couriercms rpc "CourierCMS.Release.assert_job_compatibility!()"` against
   the current database. Stop if it reports an unsupported active job version.

## Deploy

Run migrations exactly once from the new image before starting new application
processes:

```text
docker run --rm --env-file .env couriercms:<version> /app/bin/migrate
```

For a single-node installation, start one container with `COURIERCMS_ROLE=all`.
For a split installation, start web and worker containers against the same
PostgreSQL database. Enable periodic scheduling on exactly one suitable node.

Use these probes on HTTP-serving nodes:

```text
GET /health/live   # BEAM/Phoenix process is serving requests
GET /health/ready  # PostgreSQL is reachable and no migration is pending
```

Do not put configured CMS availability into the orchestrator readiness probe;
one unavailable customer system must not restart CourierCMS.

## Verify

1. `/health/ready` returns HTTP 200.
2. The login email flow works.
3. Oban queues are processing on worker nodes.
4. `/metrics` authenticates and reports a fresh worker plus acceptable queue age.
5. Run one controlled Route and verify its Run Items and target update.
6. Verify the terminal-failure recipient list and monitoring integration.

## Rollback

Application rollback is safe only while the earlier release understands the
current schema and persisted job arguments. Database migrations are forward-only;
do not reverse them automatically. If compatibility is uncertain, stop writers
and restore the pre-deployment PostgreSQL backup with its matching vault key.
