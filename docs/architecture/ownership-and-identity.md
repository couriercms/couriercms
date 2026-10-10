# Ownership and Identity

## Goal

CourierCMS must be able to create and replay Delivery Items without modifying arbitrary customer-authored target content.

## Destination

A Destination is a separately registered receiving scope belonging to one
target Connection and assigned exclusively to one Route. Physical
representation is Adapter-specific:

- Sitecore: a folder beneath a configured CourierCMS root
- WordPress: custom post type and metadata
- Drupal: bundle/fields/metadata or taxonomy
- Contentful: entry type plus metadata/tags
- Sanity: document type plus Destination ownership fields and Studio filtering
- Object storage: bucket plus prefix
- Filesystem: directory
- Purpose-built content API: resource namespace

Every Destination contains a flat set of Delivery Items. CourierCMS does not
recreate source hierarchy inside it. Source path and parent data may remain in
the canonical payload for target-owned materialization. Logical isolation and
ownership are mandatory even when the target has no folders.

An Adapter declares bounded Destination registration fields and validates each
Destination instance. Connection-scoped addressing remains on the Connection.
Separate Sanity datasets, for example, are separate Connections, while a
Sitecore parent item is a Destination scope beneath one Connection.

A Destination is available before assignment, reserved by a draft Route, active
after its first successful delivery, and retired when detached after delivery.
Only an undelivered reserved Destination is automatically released. Reuse of a
previously active external scope requires explicit cleanup, validation, and a
new Destination identity.

The Destination's Intake Schema must retain the complete Canonical Delivery Document. Adapter-specific indexed ownership fields and optional Projection Fields may duplicate values from it, but they do not change ownership or content authority.

## Stable namespace

Destination ownership uses immutable IDs:

```text
CourierCMS installation ID + Destination ID + Route ID
```

Route names and slugs are display values only. Renaming a Route must not move or duplicate its Destination.

## Human-readable Delivery Item name

The Delivery Item key is not its human-readable name. A Route Revision selects
one canonical source field for naming. The target Adapter sanitizes that value,
falls back to the source item key, and appends a deterministic short suffix from
the Delivery Item key. For example:

```text
mountain-bike--74bd2191
```

This makes deliveries easy to compare visually while preserving collision-safe
identity. Target Adapters may update the readable name when its configured
source value changes, but lookup and ownership never depend on it.

## Source identity

Adapters normalize native identity into:

```text
source_item_key
locale_key
source_revision_key
source_state
```

The item and locale keys form stable Delivery Item identity. The revision key is opaque revision metadata used for ordering, delivery history, and diagnostics; it does not create another target item.

## Target binding

The `route_items` ledger stores the target CMS identifier returned by the target Adapter. Prefer target-generated ordinary document IDs where the target CMS recommends them; keep CourierCMS identity in explicit metadata fields.

For a non-CMS target this identifier may be an object key, file path, or API
resource ID. It is an internal target reference, not a Route naming option.

When recovering from an uncertain write, the Adapter searches by a stable `couriercms_key` field and reconciles the binding before creating anything new.

## Ownership marker

The target item should contain equivalent metadata to:

```text
couriercms_installation_id
couriercms_route_id
couriercms_destination_id
couriercms_key
source_connection_id
source_item_key
locale_key
source_revision_key
```

Before updating, the target Adapter must verify that target metadata agrees with
the Delivery Binding for the current Destination. Missing or conflicting
evidence is an `ownership_violation`; CourierCMS must not overwrite the item.

CourierCMS may overwrite the canonical document, CourierCMS ownership fields, uploaded CourierCMS assets, preview fields, and configured Projection Fields on an owned Delivery Item. Customer-owned native content produced by a Target Consumer remains outside that write set.

## Create/update-only policy

CourierCMS exposes no target deletion operation in V0. The following conditions cause no destructive action:

- Source item deleted
- Source item unpublished
- Source item leaves the Route selection
- Route disabled or deleted
- Mapping field removed
- Connection removed

The target CMS owns retention, archival, and deletion.

## Duplicate prevention

- Enforce a database uniqueness constraint on the logical Route Item key.
- Serialize execution for the same logical key.
- Store the target-generated identifier immediately after confirmed creation.
- On ambiguous timeout, resolve by `couriercms_key` before retrying creation.
- Treat multiple matching target items as an ownership/data-integrity error requiring operator review.

## Multiple Routes

Each Route owns independent Delivery Items even when two Routes select the same source content. Sharing one target item across Routes is out of scope because it makes ownership and mapping authority ambiguous.
