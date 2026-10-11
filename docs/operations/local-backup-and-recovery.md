# Local backup and recovery

The Windows Local release stores durable data under
`%LOCALAPPDATA%\CourierCMS` by default. This directory contains the SQLite
database, encryption material, the Erlang release cookie, installed Extensions,
and logs. Treat it as sensitive client data.

Run `backup-couriercms.ps1` from the extracted release directory. The script
stops CourierCMS before copying SQLite so the resulting ZIP is consistent. It
includes:

- `couriercms.db` and any SQLite journal files;
- `installation-secrets.json`;
- `release-cookie.txt`;
- installed Extension packages.

Store backups encrypted and do not separate the database from its installation
secrets. To restore, stop CourierCMS, preserve the current data directory,
extract the backup contents into an empty Local data directory, and start the
same or a compatible newer Local release. Startup applies pending migrations
and reconciles interrupted durable jobs.

CourierCMS uses stable delivery identities and create-or-update semantics, so a
replayed item does not create a second target item when the target Adapter
honors the contract. A backup restores CourierCMS state; it does not roll back
content already written to a target system.

Do not restore a Local ZIP into Server or copy a Server PostgreSQL database into
Local. Export/import of configuration may be added later, but it does not exist
in the current MVP.

## Release acceptance drill

The automated Windows release test builds two Local artifacts, starts both
against one data directory, and verifies that the database identity,
installation secrets, release cookie, backup contents, health checks, and
repeated restarts remain stable. Run it from the repository root with:

```powershell
.\scripts\test-local-release-upgrade.ps1
```

Before publishing a Local release candidate, also perform this hardware-level
drill on a clean Windows machine without Elixir or Erlang installed:

1. Create a fake-to-fake Route with enough items to keep planning active, start
   a Run, terminate CourierCMS during planning, and restart it.
2. Confirm that recovery completes or safely retries the plan without a partial
   invalid plan.
3. Start another Run, terminate CourierCMS during delivery, and restart it.
4. Confirm that reconciliation resumes unfinished items, the Run is retained,
   and deterministic target identity prevents duplicate delivery items.
5. Repeat an active Run while putting the laptop to sleep and waking it.
6. Confirm that due schedules are recovered after wake without implying that
   work ran while the application was offline.
7. Create and inspect a backup, then restore it into an empty Local data
   directory using the same or a newer compatible release.

Process termination and laptop sleep are deliberately release-acceptance tests:
operating-system lifecycle behavior cannot be faithfully simulated by an ExUnit
process. The Local reliability suite separately exercises the corresponding
durable interrupted states, reconciliation, retry, locking, checkpoint, and
idempotency invariants on every CI run.
