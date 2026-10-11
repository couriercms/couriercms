# Adapter Contract

## Principles

- One Adapter understands one CMS, content repository, or compatible
  content-delivery store.
- Source and target capabilities are separate behaviours.
- Adapters translate native CMS data into normalized CourierCMS types.
- Adapters do not orchestrate Runs, call other adapters, or implement cross-CMS mapping.
- Optional behavior is declared through capabilities, not detected through failed calls.
- Adapter behaviours and normalized boundary values live in the standalone
  `extensions/sdk` project; an Extension never imports platform modules.

## Component shape

```text
CourierCMSExtension.WordPress
  Client
  Source
  Capabilities

CourierCMSExtension.Sanity
  Client
  Target
  Capabilities
```

## Common capabilities

```text
source
target
connection_test
schema_discovery
selection_preview
native_filtering
incremental_changes
save_events
publish_events
locales
revisions
assets
destination_provisioning
destination_validation
canonical_document_storage
target_projections
```

Capabilities may include limits and supported predicate lists, not only booleans.

`authoritative_change_token` is an optional Source capability with strict
semantics. When true, an enumerated identity's `change_token` must change when
any root or bounded dependency included by `read_root/3` would change. A root
revision, ETag, or modified timestamp that excludes referenced content is not an
authoritative token.

## Adapter component definition

Every source or target Adapter component exposes `definition/0`. The definition
is the only place where the CMS's labels and configuration vocabulary
belong. It declares:

- stable component ID, label, and operator description;
- endpoint input or deterministic endpoint derivation;
- non-secret Connection settings and encrypted credential fields;
- optional Connector setup presentation and webhook path;
- source content label and typed selection fields;
- source-owned default mapping, aggregation rules, and Delivery Contract;
- target-owned default Projection Fields and explanatory text.
- target-owned Destination registration fields;
- target naming constraints and a supported Delivery Item naming source.

Generic Connection and Route screens render these definitions through the
Extension Gateway. They must not
branch on component IDs or contain WordPress, Sanity, Drupal, Sitecore, or other
CMS field names. Installing an Adapter Extension may add its own definition, but
must not require editing generic LiveViews or core execution code.

Definitions are declarative data, not executable UI injection. Supported field
types are intentionally bounded. Secrets are identified by storage class and
remain encrypted by the Connections context.

## Implemented source behaviour

Current callbacks:

- `component/0`
- `definition/0`
- `test_connection/1`
- `capabilities/1`
- `enumerate/3`
- `changes_since/4` (Connection, selection, opaque checkpoint/window, page cursor)
- `read_root/3`

Enumeration returns pages of normalized identities and an opaque continuation/checkpoint value. It does not return unbounded collections.

An identity may carry an authoritative change token only under the capability
contract above. CourierCMS otherwise calls `read_root/3` and compares the canonical
payload hash.

`read_root/3` returns the implemented bounded Content Bundle. The optional
`read_asset/2` callback returns replayable binary chunks plus declared size,
checksum, and media type without placing binary data in a database or job.
CMS-specific assembly and retrieval metadata remain inside the source Adapter.

## Implemented target behaviour

Current callbacks:

- `component/0`
- `definition/0`
- `test_connection/1`
- `capabilities/1`
- `idempotency_strategy/0`
- `validate_destination/2`
- `validate_projections/2`
- `find_delivery/3`
- `create_delivery/2`
- `update_delivery/4`

There is intentionally no `delete` callback in V0.

Any future provisioning capability must be explicit and separate from a
delivery Run. A target Adapter must never silently mutate target schema during
delivery.

Destination settings are declarative, bounded, and Adapter-defined. They are
stored on a separately managed Destination belonging to the target Connection,
validated before assignment, and passed with each target delivery. They
describe the registered receiving scope, not Connection-scoped addressing such
as a Sanity dataset.

The platform, not an Adapter, enforces exclusive Route assignment and
Destination lifecycle. An Adapter validates the external scope and reports
ownership evidence where the target supports a scope marker. Provisioning is an
optional explicit capability; manual registration is the default.

Each target Adapter must implement deterministic, human-readable Delivery Item
naming. It receives the configured source-derived name and immutable Delivery
Item key, applies target-specific sanitization and length limits, and appends a
short stable suffix derived from the key. It must not use the readable name for
lookup or ownership. Target references returned from create/update operations
remain opaque to the core.

Lookup and deterministic target identity are scoped by both Destination ID and
Delivery Item key. A Route move deliberately keeps the Delivery Item key stable,
but the new Destination must receive a distinct target item while the old item
and Delivery Binding remain untouched.

Delivery Items are flat within a Destination. A target Adapter must not infer or
recreate source hierarchy during delivery. Native target hierarchy is outside
CourierCMS delivery.

Every target Adapter must preserve the complete Canonical Delivery Document in each Delivery Item, either as a native arbitrary-value field when the CMS safely supports it or as canonical UTF-8 JSON text. Target-specific ownership, lookup, preview, asset, and Projection Fields may duplicate selected values. They are derivatives and must not replace the canonical document.

When `target_projections` is supported, its capability declaration includes supported target types, path/value limits, naming constraints, and whether writes can be atomic with the canonical document. Projection validation occurs before Route activation. An Adapter must reject a configured projection that the installed Intake Schema cannot store; it must not create fields during a Run.

## Adapter errors

Adapters return a normalized `AdapterError` containing:

- category from the execution error taxonomy
- retryable boolean
- safe human-readable message
- optional safe external code
- retry-after duration when supplied
- internal cause available to protected diagnostics without secrets or content

Adapters must not return raw exception strings or entire HTTP response bodies to the UI.

## HTTP requirements

Native Extensions issue outbound requests through the SDK HTTP boundary. The
platform implementation—not each Adapter—enforces the following controls:

- Explicit connect, receive, and total timeouts
- Bounded response bodies
- Connection-specific rate limiting
- Capped retries coordinated with CourierCMS rather than hidden infinite retries
- TLS verification outside local development
- Safe redirect rules
- SSRF-safe resolution and address validation
- Correlation IDs without credentials
- User agent identifying CourierCMS and adapter version

## Connector protocol

A CMS Connector authenticates every event/request and declares a machine-readable
connector contract version. Version 1 messages include a unique event ID,
canonical event kind, source item identity, optional source modification time,
request timestamp, and HMAC signature. Unsupported versions are rejected
explicitly rather than interpreted as the newest contract.

The Connector should notify CourierCMS and let the source Adapter read authoritative content. Large content payloads should not be pushed through event requests unless a CMS-specific limitation requires it.

CourierCMS persists a new Connector Event and its Oban processing job in one
database transaction. Duplicate delivery is safe and ensures a processing job
exists. Periodic reconciliation repairs old accepted or processing events that
have no active job.

## Contract testing

Every Adapter must pass shared tests covering applicable capabilities:

- Connection success and normalized failures
- Pagination without loss or duplication
- Stable identity normalization
- Selection validation and preview
- Rate-limit and transient-error mapping
- Idempotent target resolution
- Ownership verification
- Complete canonical document retention and projection consistency
- Ambiguous timeout recovery
- Current asset-operation limits where applicable
- Secret-safe errors and logging

Live integration tests are opt-in and use disposable test projects/sites.

## Delivery Asset callbacks

The SDK exposes optional `read_asset/2`, `find_asset/3`, `create_asset/2`, and
`update_asset/4` callbacks. They define bounded source streaming and target
create-or-update operations with deterministic identity, ownership, and
ambiguous-write recovery. The fake development Extension exercises this
contract end to end. The platform materializes a bounded verified stream,
persists dependencies and jobs atomically, retries asset work independently,
reconciles stranded jobs, and injects the returned reference before item
delivery. An official Adapter must pass the relevant contract and integration
tests before advertising these callbacks. WordPress and Sanity have not yet
adopted them and retain their documented in-item featured-image behavior.

## Versioning

Connections and Route Revisions persist the stable Extension ID and Adapter
component ID. Runs also capture the Extension version, package checksum, and SDK
contract version. Breaking changes require migration or explicit incompatibility
errors; an Adapter must not reinterpret an old opaque checkpoint silently.

The Extension version is manifest metadata, not part of the Elixir module name.
Adapter calls are resolved through the Extension Gateway; application contexts,
workers, and LiveViews do not dispatch directly to CMS-specific modules. Package
and lifecycle rules are defined in [Extension architecture](extensions.md).
