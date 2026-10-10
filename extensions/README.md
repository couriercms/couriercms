# CourierCMS extensions

Each directory is an independently testable Mix project that depends on the
stable SDK contract:

- `sdk/` — public behaviours, values, errors, manifest parsing, and build task
- `wordpress/` — official WordPress source Adapter
- `sanity/` — official Sanity target Adapter
- `fake/` — deterministic development/test-only source and target Adapters

The platform does not use path dependencies on concrete extensions. Run
`scripts/prepare-extensions.ps1 -IncludeFake` or
`scripts/prepare-extensions.sh --include-fake` to compile and install packages
into `.local/extensions`. Production images bundle only official extensions in
`/var/lib/couriercms/extensions`.

Generated `.couriercms` packages, `_build/`, and `deps/` are not committed.
Connectors installed in external content systems belong under `connectors/`,
not here.
