# Local mode

Local mode is the single-operator CourierCMS release for migration and delivery
work performed from a workstation. It uses the same delivery engine and
Extension packages as Server, with SQLite and a loopback-only dashboard.

## Development

Set `COURIERCMS_RELEASE_PROFILE=local` before dependency resolution, compilation,
migration, or tests because the selected Ecto adapter is compiled into the
artifact.

```powershell
$env:COURIERCMS_RELEASE_PROFILE = 'local'
./scripts/dev.ps1
```

```sh
COURIERCMS_RELEASE_PROFILE=local sh ./scripts/dev.sh
```

Local creates an internal operator and default workspace, then constructs the
normal authorization scope. There is no unscoped context API and no general
authentication-disable setting. Login and user-management routes and connector
ingress are unavailable.

Development data is kept under the repository's ignored `.local/` directory.
The packaged Windows release instead uses `%LOCALAPPDATA%\CourierCMS`, unless
`COURIERCMS_LOCAL_DATA_PATH` is explicitly set.

## Limits

- exactly one CourierCMS application instance may use a Local database;
- the listener is always `127.0.0.1`;
- schedules run only while the application is running;
- the SQLite file may contain content and encrypted credentials;
- Local data is not a Server database and cannot be synchronized with one;
- Extensions are identical in both profiles; connector software remains an
  external-system component and has no Local variant.

Build the Windows ZIP with `scripts/build-local-release.ps1`. The generated
artifact is placed under the ignored `.tmp/releases/` directory.

## Run Local and Server together

They are separate artifacts and may run on the same workstation. Give them
different HTTP ports and keep their databases and Extension caches separate.
For example, leave Compose Server on port 4000 and start packaged Local on
4100:

```powershell
docker compose up -d
$env:PORT = '4100'
./start-couriercms.ps1
```

Local continues to use `%LOCALAPPDATA%\CourierCMS`; Compose Server uses its
PostgreSQL and cache volumes. The two databases do not exchange state.

See [Local troubleshooting](local-troubleshooting.md) for startup and recovery
checks.
