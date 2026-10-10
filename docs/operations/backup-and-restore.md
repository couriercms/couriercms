# Back up and restore CourierCMS

## What must be protected

- The complete PostgreSQL database, including Oban jobs and migration state
- `COURIERCMS_VAULT_KEY`, stored separately from the database backup
- `COURIERCMS_INSTALLATION_ID` and runtime configuration
- Deployment-specific SMTP, TLS, and Connection secret references

The vault key is required to decrypt stored CMS credentials. Losing it makes an
otherwise valid database backup operationally incomplete.

## Backup

Use the PostgreSQL provider's native snapshot/PITR mechanism or `pg_dump` with a
consistent snapshot. Encrypt backups, restrict access, and retain them according
to the organization's policy. Never copy secrets into this repository.

## Restore test

1. Provision an isolated PostgreSQL instance.
2. Restore the selected database backup.
3. supply the matching vault key and installation ID through the secret manager.
4. Run the same or a schema-compatible CourierCMS release with workers and periodic
   scheduling disabled.
5. Verify `/health/ready`, authentication, Connection credential decryption, and
   Run history.
6. Enable a worker only after confirming the isolated environment cannot write
   to production CMS endpoints.

## Production recovery

Stop CourierCMS writers, restore PostgreSQL, supply the matching secrets, run any
required forward migrations, and start one web node followed by workers. Oban
may retry work that was active at backup time. Stable Delivery Item identity,
target ownership checks, and idempotent target operations make that expected and
safe; verify ambiguous external writes in Run history.

This restores CourierCMS's control plane. It is not a backup or restore procedure for
source or target CMS content.
