# Sanity extension

Official CourierCMS-hosted target Adapter for deterministic, CourierCMS-owned
Sanity intake documents. It verifies ownership, creates or updates one stable
Delivery Item, retains the canonical document, uploads supported public images,
and writes validated projection fields. It never deletes target documents.

```sh
mix deps.get
mix test
MIX_ENV=prod mix couriercms.extension.build
```

The project depends only on `../sdk` and shared HTTP/JSON libraries; it does not
import platform internals. See [the extension guide](../../docs/extensions/sanity.md).
