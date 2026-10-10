# Content Envelope and Delivery Contract

## Purpose

CourierCMS uses a small normalized model to keep CMS-specific data at adapter boundaries without pretending that all CMS content models are identical.

## Source identity

```elixir
%SourceIdentity{
  item_key: "101",
  locale_key: "en",
  revision_key: "15",
  state: :published,
  modified_at: ~U[2026-09-24 14:00:00Z],
  change_token: "aggregate:15" # optional
}
```

Keys are opaque strings supplied by the source Adapter. `locale_key` may use an
Adapter-normalized locale. A CMS without locales uses a documented default. The
optional `change_token` is not revision history or identity: an Adapter may
supply it only when it declares that the token covers the root and every bounded
dependency included in the aggregated Delivery Item.

## Source content node

A source Adapter returns normalized nodes used to assemble a Content Graph:

```text
identity
source type
name/path, when available
fields containing scalar, list, object, or rich-content values
references with relationship names and target source identities
assets as descriptors, never inline unbounded binaries
source metadata required for mapping or diagnostics
```

Adapter-specific metadata is namespaced and must not be required by unrelated adapters.

## Content Graph

The graph contains one root and only dependencies allowed by Aggregation Rules. Execution enforces:

- Maximum traversal depth
- Maximum nodes per root
- Maximum payload size
- Allowed relationship names/types/scopes
- Cycle detection
- Shared-node deduplication
- Missing dependency policy

Graph nodes normally become nested payload values, not separate Delivery Items.

## Canonical Delivery Document

The Canonical Delivery Document is the complete, authoritative JSON value delivered for one root item and locale. Its normative conceptual shape is:

```json
{
  "couriercms": {
    "envelopeVersion": 1,
    "installationId": "...",
    "routeId": "...",
    "destinationId": "...",
    "routeRevision": 3,
    "deliveryKey": "...",
    "sourceConnectionId": "...",
    "sourceItemId": "101",
    "sourceType": "post",
    "locale": "en",
    "sourceRevision": "15",
    "sourceState": "published",
    "sourceModifiedAt": "2026-09-24T14:00:00Z",
    "contractVersion": 2,
    "deliveredAt": "2026-09-24T14:05:00Z",
    "contentHash": "sha256:..."
  },
  "payload": {}
}
```

The `couriercms` object is the Delivery Envelope and `payload` is the Delivery Payload. Exact target field names may differ, but the Adapter must retain this complete document in the Delivery Item and preserve these semantics. A target representation may use a native arbitrary-value field or canonical UTF-8 JSON text.

Adapter-specific ownership, lookup, preview, and asset fields may duplicate values outside this document. Optional Projection Fields may also duplicate configured paths. These fields are indexes or conveniences; the Canonical Delivery Document remains the source of truth.

The payload is complete normalized source content, not necessarily a verbatim
vendor API response. Source Adapters must exclude transient, irrelevant, or
sensitive response data unless the Delivery Contract explicitly requires a safe
representation of it.

## Delivery Item name

Human-readable target naming is separate from the Canonical Delivery Document's
identity. A Route Revision selects a path in the canonical source content. The
target Adapter uses its value, or the source item ID as a fallback, sanitizes it
for the target, and appends a deterministic short suffix derived from
`deliveryKey`.

The name helps operators browse and compare source and target content. It is not
used for target lookup, duplicate prevention, or ownership verification. The
Adapter-returned target reference is stored separately in the Route Item ledger.

## Payload values

Delivery Contracts may contain:

- Null, boolean, number, and string scalars
- Lists with stable ordering
- Nested objects
- Rich text represented by a declared transformation format
- Asset references/descriptors
- Source provenance values intentionally included by mapping

Payload field names describe content meaning rather than presentation.

## Assets

An asset descriptor includes source identity, filename, media type, size when known, checksum when known, alt/caption metadata, and a bounded retrieval mechanism. Binary data is streamed or written to controlled temporary storage; it is not put in PostgreSQL JSON or Oban arguments.

The target Adapter can upload assets and replace source descriptors with target asset references inside the payload. Asset ownership uses the same Route namespace principles.

## Validation and hashing

CourierCMS validates the mapped payload and complete Canonical Delivery Document before making a target call. The content hash is calculated from a canonical representation of delivery-relevant envelope fields and payload, excluding volatile delivery timestamps.

Identical hashes may be skipped safely when the target binding and ownership evidence are intact.

## Projection Fields

A Projection definition contains:

```text
target field name
Canonical Delivery Document path
allowlisted target value type
required/optional policy
```

The projection value is computed only from the Canonical Delivery Document being written. Projections must be reproducible, are overwritten during later delivery, and cannot carry target-authored content. A Route Revision owns the projection definitions so a historical Run remains explainable.

Targets differ in their supported field types, indexes, naming rules, and schema deployment model. The target Adapter declares those capabilities and validates the installed Intake Schema before Route activation. Runtime delivery never adds or changes target schema.

## Retention

CourierCMS stores identity, hashes, mapping metadata, and safe error information by default. Persisting complete source or target payloads is not required for V0 and would require explicit retention, encryption, and privacy controls.
