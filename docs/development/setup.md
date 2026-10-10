# Local development

## Prerequisites

Install the Erlang/OTP, Elixir, and Node.js versions in `.tool-versions`, Docker
with Compose, and PostgreSQL (Compose supplies the normal local database).

## Start the platform

```powershell
docker compose up -d postgres
./scripts/dev.ps1
```

On macOS/Linux use `sh ./scripts/dev.sh`. The script compiles the SDK, packages the
WordPress, Sanity, and fake development extensions into `.local/extensions`,
sets `COURIERCMS_EXTENSIONS_PATH`, runs `mix setup` inside `platform/`, and
starts Phoenix.

Create the first owner once:

```powershell
cd platform
mix couriercms.owner.create you@example.com
```

Open `http://localhost:4000/users/log-in`. Development email appears at
`http://localhost:4000/dev/mailbox`.

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

Platform-only commands run from `platform/`:

```sh
mix setup
mix ecto.migrate
mix assets.build
mix couriercms.owner.create you@example.com
```

## Database baseline

The migrations are retained as an ordered clean CourierCMS baseline with all
current production-domain constraints and indexes. The obsolete platform-owned
fake-delivery tables are intentionally omitted now that the fake adapter is an
isolated development extension. The clean-break product and Destination rename
means databases created before the CourierCMS clean break are intentionally incompatible. Create
fresh `couriercms_dev` and `couriercms_test` databases; do not point this code at
a pre-CourierCMS database.

## Windows TLS certificates

If OTP cannot read the Windows certificate store, set
`COURIERCMS_CACERTS_PATH` to a trusted PEM bundle such as Git for Windows'
`usr/ssl/cert.pem`. Keep TLS verification enabled.
