# Security advisory exceptions

Exceptions are narrow, reviewed, and removed as soon as a compatible upstream
fix exists. They never suppress application-runtime advisories silently.

## Sanity Studio build toolchain

- Reviewed: 2026-10-11
- Review cadence: monthly and on every Sanity dependency update
- Next scheduled review: 2026-11-11
- Scope: `examples/sanity-consumer` development/build dependency graph
- Upstream: latest Sanity and Vision release `6.16.0`
- Status: accepted temporarily; review on every Sanity upgrade

`npm audit` currently reports 24 transitive findings (12 high and 12 moderate)
through the Sanity CLI/build dependency graph, including `adm-zip`, `braces`,
`js-yaml`, `smol-toml`, `source-map-js`, `sprintf-js`, `undici`, and `uuid`.
The available automatic remedies do not fully clear the graph without changing
upstream Sanity tooling. These packages execute while building or serving
Sanity Studio; they are not part of the CourierCMS Phoenix runtime container.

CI continues to print the complete audit and fails on critical advisories. Do
not process untrusted archives, YAML, or TOML through the Studio build toolchain.
Restore failure at `--audit-level=high` when compatible patched dependencies are
available.

## Cloak unused cipher and field-type paths

- Reviewed: 2026-10-11
- Review cadence: monthly and on every Cloak dependency or encryption configuration change
- Next scheduled review: 2026-11-11
- Scope: `platform` runtime dependency graph
- Status: acknowledged narrowly while no patched Hex releases are available

`mix hex.audit` reports `CVE-2026-95105` for Cloak's unauthenticated AES-CTR
cipher and `CVE-2026-94206` for Cloak Ecto's PBKDF2 field types. CourierCMS
configures only `Cloak.Ciphers.AES.GCM` and stores encrypted maps through
`Cloak.Ecto.Map`; it does not use the affected AES-CTR cipher or PBKDF2 field
types.

The two advisory IDs are acknowledged in `platform/mix.exs`, so Hex Audit
continues to print them as ignored findings while returning success. A
regression test prevents the affected modules from being introduced unnoticed.
Remove the acknowledgements immediately if CourierCMS adopts either affected
path, or when compatible patched releases become available.
