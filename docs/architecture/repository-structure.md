# Repository structure

```text
couriercms/
  platform/                 Phoenix/Mix application
    assets/
    config/
    lib/courier_cms/
    lib/courier_cms_web/
    priv/
    rel/
    test/
  extensions/
    sdk/                    stable public Extension SDK
    fake/                   development/test-only adapters
    wordpress/              CourierCMS-hosted source extension
    sanity/                 CourierCMS-hosted target extension
  connectors/
    wordpress/              plugin installed inside WordPress
  examples/
    sanity-consumer/        optional target-side Sanity integration example
  docs/
  scripts/
```

There are no Phoenix application source files at the repository root. The root
Docker build can see both `platform/` and official extension source projects.

## Dependency direction

```text
platform -> Extension SDK
extension -> Extension SDK + external CMS API
connector -> documented HTTP/event contract
example -> target-owned integration APIs
```

The platform never imports a concrete extension module. Extensions do not
import Phoenix contexts, Ecto schemas, Oban workers, or undocumented platform
internals. Connectors are installed in external systems and are never loaded by
the CourierCMS extension registry.

Source projects live under `extensions/`; generated `.couriercms` packages live
under gitignored `.local/extensions/` for development or an operator-controlled
runtime directory such as `/var/lib/couriercms/extensions` in production.
