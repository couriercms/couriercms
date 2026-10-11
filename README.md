# CourierCMS

CourierCMS is a self-hosted, CMS-aware content delivery platform. It reliably
makes selected content from one content system available at a configured
Destination in another.

A Route selects content from one Source Connection and delivers it to one
Destination, a configured receiving scope inside a Target Connection. Each
Delivery Item retains the complete Canonical Delivery Document. Optional
projected fields make target-side integration easier, but never replace that
authoritative document.

Destinations are assigned exclusively to Routes and contain flat Delivery Item
sets. A compatible target may be a CMS or a content-delivery store that provides
the same ownership and idempotent create-or-update guarantees.

CourierCMS creates or updates deterministic, CourierCMS-owned Delivery Items.
It never deletes target content. Target-side hooks, workflows, AI, or custom
code decide how a delivery becomes native editorial content.

CourierCMS supports migration as a use case, but it is not a complete migration
suite, bidirectional synchronization system, workflow engine, or general-purpose
automation platform.

## Repository

- `platform/` — Phoenix, LiveView, Ecto, PostgreSQL, Oban, execution, and operator UI
- `extensions/` — host-installed SDK and source/target Adapter projects
- `connectors/` — optional software installed inside external content systems
- `examples/` — optional target-owned consumers and hooks
- `docs/` — concepts, architecture, development, operations, and ADRs

## Choose Local or Server

CourierCMS ships the same delivery engine in two release profiles:

- **Local** is a downloadable, single-operator application for a laptop or
  workstation. It uses SQLite, binds only to `127.0.0.1`, and needs no separate
  database installation. Scheduling operates while CourierCMS is running.
- **Server** is the continuously operated, authenticated deployment. It uses
  PostgreSQL and supports connector ingress, multiple users, split web/worker
  roles, and multiple nodes.

Both profiles run the same Routes, item-level jobs, retries, reconciliation,
SDK, and Extension packages. Local is not a reduced-quality delivery engine;
it trades availability, concurrency, and scale for a simpler installation.
Local and Server databases are intentionally not interchangeable or
synchronized.

## Development

Install the versions in `.tool-versions`, start PostgreSQL, and use the local
scripts to build package-loaded extensions before starting the platform:

```powershell
docker compose up -d postgres
./scripts/dev.ps1
```

On macOS or Linux:

```sh
docker compose up -d postgres
sh ./scripts/dev.sh
```

The scripts compile the SDK, package the official and fake development
extensions into `.local/extensions`, configure `COURIERCMS_EXTENSIONS_PATH`,
set up the platform, and start Phoenix. To run all local checks, use
`scripts/test.ps1` or `sh scripts/test.sh`.

To develop against the Local profile without PostgreSQL:

```powershell
$env:COURIERCMS_RELEASE_PROFILE = 'local'
./scripts/dev.ps1
```

See [Local mode](docs/development/local-mode.md) and
[Server mode](docs/operations/server-mode.md) for the operating differences.

To run Compose with locally built or custom packages mounted read-only over the
image's bundled Extensions, use:

```sh
docker compose -f compose.yaml -f compose.extensions.yaml up
```

Prepare `.local/extensions` with the appropriate script first. See
[Extension management](docs/operations/extension-management.md) for production
rollout and consistency requirements.

Create the first owner from `platform/` with:

```sh
mix couriercms.owner.create you@example.com
```

See the [development setup](docs/development/setup.md) and
[documentation index](docs/README.md) for details.

For contribution expectations, support boundaries, and private security
reporting guidance, see [CONTRIBUTING.md](CONTRIBUTING.md),
[SUPPORT.md](SUPPORT.md), and [SECURITY.md](SECURITY.md).

## Reliability model

CourierCMS preserves durable item-level jobs, per-item retries, atomic bounded
planning, checkpoint advancement, overlap prevention, database-backed logical
content locking, stranded-job reconciliation, authoritative completion recounts,
worker heartbeats, health endpoints, retention, secret rotation, and exact
extension artifact validation. Delivery is at least once; stable target identity
and ownership checks make replay safe.

## Status

CourierCMS is an unreleased, pre-1.0 open-source foundation. The current code
is functional and tested, but no compatibility, support, or release guarantees
are promised yet.

## License

CourierCMS is licensed under the [Apache License 2.0](LICENSE).
