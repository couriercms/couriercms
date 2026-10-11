# Testing

Run the complete local suite from the repository root:

```powershell
./scripts/test.ps1
```

or:

```sh
sh ./scripts/test.sh
```

The scripts build package-loaded development extensions, then format, compile
with warnings as errors, and test the SDK, fake extension, WordPress extension,
Sanity extension, and both platform profiles. PostgreSQL must be available with
the defaults in `compose.yaml` or corresponding environment overrides for the
Server pass. The Local pass uses SQLite.

To run only one platform profile after testing all extensions:

```powershell
./scripts/test.ps1 -PlatformProfile local
./scripts/test.ps1 -PlatformProfile server
```

The shell equivalents are `sh ./scripts/test.sh local` and
`sh ./scripts/test.sh server`.

Individual projects support the usual commands from their own directory:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

The platform suite uses deterministic fake adapters loaded from
`.local/extensions`; it does not import a concrete extension module. WordPress
and Sanity HTTP tests use local request stubs. Live third-party integration tests
must be opt-in and use disposable projects or sites.

The planner load test remains opt-in:

```sh
cd platform
COURIERCMS_RELEASE_PROFILE=local COURIERCMS_LOAD_ITEM_COUNT=10000 \
  mix test test/load/planner_load_test.exs --include load
```

Run the same command with `COURIERCMS_RELEASE_PROFILE=server`. The root test
scripts and CI run the default-size planner load test for both profiles.

Failure-path coverage should include retryable and terminal errors, idempotent
replay, ownership violations, checkpoint safety, bounded planning, cancellation,
and stranded-job reconciliation. Never claim a check passed unless it ran.
