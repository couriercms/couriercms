# Fake extension

This development/test-only CourierCMS extension supplies deterministic source and target adapters. It is not supported for production delivery and is never bundled into a production image.

The target stores deliveries in memory so tests can exercise the same package-loading and SDK boundary used by production extensions without importing platform internals.
