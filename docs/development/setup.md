# Local development

## Prerequisites

Install the Erlang/OTP, Elixir, and Node.js versions in `.tool-versions`.
Server-profile development also needs Docker with Compose or another PostgreSQL
installation. Local-profile development stores its SQLite database under
`.local/` and does not need PostgreSQL.

## Start the platform

```powershell
docker compose up -d postgres
./scripts/dev.ps1
```

On macOS/Linux use `sh ./scripts/dev.sh`. The script compiles the SDK, packages the
Content Processor, WordPress, Sanity, and fake development extensions into `.local/extensions`,
sets `COURIERCMS_EXTENSIONS_PATH`, runs `mix setup` inside `platform/`, and
starts Phoenix.

To run the Local profile instead, omit PostgreSQL and select Local:

```powershell
./scripts/dev.ps1 -Profile local
```

On macOS/Linux use `sh ./scripts/dev.sh local`. The two profiles use isolated
Mix build directories, so switching profiles does not reuse Repo bytecode built
for the other Ecto adapter. Local creates an implicit operator and default
workspace, hides login and user administration, and accepts HTTP only on the
loopback interface.

For Server development, create the first owner once:

```powershell
cd platform
mix couriercms.owner.create you@example.com
```

Open `http://localhost:4000/users/log-in`. Development email appears at
`http://localhost:4000/dev/mailbox`. Local opens the dashboard directly and
does not need this step.

## Work on one component

Each extension is a normal Mix project. For example:

```powershell
cd extensions/wordpress
mix deps.get
mix test
```

After changing an extension, rerun `scripts/prepare-extensions.ps1 -IncludeFake`
or the shell equivalent and restart the platform. Development intentionally
uses the same precompiled package-loading boundary as production.

Platform-only commands run from `platform/`. Set
`COURIERCMS_RELEASE_PROFILE=local` before them when working on Local; omitting
the variable selects Server.

```sh
mix setup
mix ecto.migrate
mix assets.build
mix couriercms.owner.create you@example.com
```

## Database baseline

Server and Local have separate migration baselines with the same logical domain
invariants. Each profile starts with exactly one initial migration. The
obsolete platform-owned fake-delivery tables are intentionally omitted now that
the fake adapter is an isolated development extension. The clean-break product
and Destination rename means databases created before the CourierCMS clean
break or dual-profile baseline are intentionally incompatible. Create fresh
databases rather than pointing this code at an older development database.
Local and Server databases are not interchangeable.

When updating a development checkout that previously compiled the historical
PostgreSQL migrations, clear its generated migration copies before recreating
the database:

```powershell
cd platform
mix clean
mix ecto.drop
mix ecto.setup
```

These commands intentionally discard the selected profile's development
database. Set `COURIERCMS_RELEASE_PROFILE` first when resetting Local.

## Windows TLS certificates

If OTP cannot read the Windows certificate store, set
`COURIERCMS_CACERTS_PATH` to a trusted PEM bundle such as Git for Windows'
`usr/ssl/cert.pem`. Keep TLS verification enabled.
