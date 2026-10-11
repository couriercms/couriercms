# Local troubleshooting

The Windows Local launcher reports the data directory and writes startup output
to its `logs` directory. By default that is
`%LOCALAPPDATA%\CourierCMS\logs`.

## The dashboard does not start

1. Read `couriercms-error.log` and `couriercms.log`.
2. Check whether another program already owns port 4000. Set a free loopback
   port before starting again, for example `$env:PORT = '4100'`.
3. Confirm the extracted release directory is complete and still contains
   `bin`, `erts-*`, `lib`, `releases`, and `bundled-extensions`.
4. Confirm the OS account can write the Local data directory.

Do not work around startup failures by exposing another network interface.
Local always binds to `127.0.0.1`; use Server when remote access is required.

## CourierCMS was interrupted

Start it normally. Durable Runs, Run Items, jobs, checkpoints, and ownership
bindings remain in SQLite. Startup migrations run before the application opens,
and reconciliation recovers stranded work. Inspect the affected Run before
retrying failed items; do not edit the SQLite file manually.

Schedules execute only while Local is running. After a laptop shutdown or
sleep, CourierCMS resumes durable work when it starts or wakes, but it does not
pretend the workstation was continuously available.

## The database is locked

Only one CourierCMS process may use a Local data directory. Run
`stop-couriercms.ps1`, confirm the recorded process has stopped, and then start
again. Do not put the SQLite database on a network share or synchronize the
live directory with cloud-drive software.

## An Extension is missing

Official Extension packages are copied from `bundled-extensions` into the Local
data directory on startup. Custom packages belong in the data directory's
`extensions` folder. Restart CourierCMS after changing packages, then inspect
the operator UI and logs for contract, checksum, or compatibility failures.

## Recovery and support evidence

Use [Local backup and recovery](../operations/local-backup-and-recovery.md)
before changing or restoring durable data. When collecting diagnostics, share
only the minimum relevant log excerpt. Never share the SQLite database,
`installation-secrets.json`, `release-cookie.txt`, credentials, payloads, or a
complete backup archive.
