# CourierCMS Extension SDK

The SDK is the only supported compile-time dependency from a native Extension
to CourierCMS. It contains versioned component identities, manifest validation,
Adapter/Processor behaviours, and transport-neutral boundary types.

It deliberately has no dependencies on Phoenix, Ecto, Oban, the CourierCMS
database, or application contexts. Its only library dependency is Jason for
manifest/package build tooling.

During monorepo development:

```text
cd extensions/sdk
mix test
```

The SDK is initially version `0.1.0`; compatibility is not declared stable
until the first `1.x` release.

Source identities may include an optional aggregation-wide `change_token` only
when the Source Adapter declares `authoritative_change_token`. Target Adapters
may implement `validate_destination/2`; each delivery receives a separately
registered, exclusively Route-assigned Destination scope. Target Adapters keep
Delivery Items flat, use the immutable delivery key for identity, and apply
target-specific sanitization to the source-derived human-readable name.
