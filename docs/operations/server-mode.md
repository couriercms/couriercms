# Server mode

Server is the continuously operated CourierCMS profile. It uses PostgreSQL,
requires authenticated users, exposes authenticated connector ingress, and can
split web, worker, scheduler, and migration responsibilities across processes.

Server remains the default when `COURIERCMS_RELEASE_PROFILE` is omitted. A
production deployment should set it explicitly to `server` for clarity.

```sh
COURIERCMS_RELEASE_PROFILE=server
COURIERCMS_ROLE=all
DATABASE_URL=ecto://couriercms:password@postgres/couriercms
```

The `all` role is suitable for a small installation. Larger installations may
use the documented web/worker role split against the same PostgreSQL database.
PostgreSQL-specific advisory locking and database operations remain optimized;
Local portability does not replace them with lowest-common-denominator logic.

Use the root Dockerfile and Compose files for Server deployment. Apply
migrations before starting upgraded application nodes, keep the vault key
separate from database backups, and mount the same Extension package set on
every executing node.

See [configuration and scaling](configuration-and-scaling.md),
[deployment and upgrade](deployment-and-upgrade.md), and
[backup and restore](backup-and-restore.md).
