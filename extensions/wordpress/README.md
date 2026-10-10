# WordPress extension

Official CourierCMS-hosted source Adapter for WordPress core posts through the
WordPress REST API. It supports bounded enumeration, filtered and incremental
discovery, authoritative content reads, normalized identities, and optional
publish events from the separately installed WordPress connector.

```sh
mix deps.get
mix test
MIX_ENV=prod mix couriercms.extension.build
```

The project depends only on `../sdk` and shared HTTP/JSON libraries; it does not
import platform internals. See [the extension guide](../../docs/extensions/wordpress.md).
