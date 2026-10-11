# Destinations and Delivery Items

## Definition

A Destination is a registered, target-Adapter-defined receiving scope for a
flat collection of CourierCMS Delivery Items. A Destination belongs to one
target Connection and is assigned exclusively to one Route.

Its physical representation depends on the target:

- a parent item in a tree-based CMS;
- a document collection or logical partition in a headless CMS;
- an object-store bucket and prefix;
- a filesystem directory; or
- a namespace exposed by a purpose-built content API.

A non-CMS target is compatible only when its Adapter can provide the same
stable identity, ownership, create-or-update, canonical-document, and retry
semantics as a CMS target. A generic webhook or arbitrary HTTP action is not a
Destination.

## Setup and assignment

Manual registration is the default:

1. An operator creates or selects the receiving scope in the target system.
2. The operator registers it as a Destination beneath a target Connection.
3. The target Adapter validates reachability, permissions, required Intake
   Schema, and ownership compatibility.
4. A Route may select only a compatible, available Destination from its target
   Connection.
5. CourierCMS reserves that Destination exclusively for the Route.

An Adapter may optionally support explicit provisioning. It must not install or
mutate target schemas silently during a delivery Run.

## Lifecycle

```text
available -> reserved -> active -> retired
```

- `available`: validated and not assigned to a Route.
- `reserved`: assigned to a draft Route that has not successfully delivered an
  item.
- `active`: at least one Delivery Item has been accepted; ownership is locked
  to the Route.
- `retired`: detached after delivery or retained with an archived Route; it is
  not offered to another Route.

Validation is separate from lifecycle. A Destination may be `unknown`, `valid`,
or `invalid` while retaining its lifecycle and Route ownership. An invalid
Destination cannot be newly reserved or receive delivery, but successful
revalidation can restore it without changing its identity.

A reserved Destination returns to `available` when its undelivered Route is
changed or removed. An active Destination does not automatically become
available when a Route is changed, disabled, archived, or removed.

CourierCMS never deletes existing target content when a Route changes
Destination. Reusing an old external scope requires explicit operator cleanup,
validation, and registration with a new Destination identity. The historical
Destination record remains for auditability.

Moving an active Route is an explicit operation: the old Destination is retired
and the new Destination is reserved. The next manual or scheduled Run performs a
full delivery because the prior checkpoint is cleared. If a Connector event
arrives first, CourierCMS promotes that event-triggered Run to the same full
Destination baseline instead of delivering only the changed item. Runs record
which Destination they used. Target references and ownership evidence are stored
in a Delivery Binding for each Route Item and Destination, so the move does not
overwrite the historical binding.

CourierCMS archives Routes instead of hard-deleting them so Run history and
ownership evidence remain auditable. Archiving an undelivered Route releases its
reserved Destination. Archiving a Route that has delivered content retires its
active Destination and never deletes target content.

## Exclusive and flat delivery

One Route selects exactly one Destination, and one Destination may be assigned
to no more than one Route. Several Destination scopes may exist beneath a shared
organizational parent, but Routes never write into one shared scope.

Delivery Items form a flat set inside their Destination. CourierCMS does not
reproduce the source tree. Source path and parent information may be retained in
the Canonical Delivery Document. CourierCMS does not create native target
hierarchy from it.

For example, a Sitecore project may organize receiving scopes as:

```text
/sitecore/content/CourierCMS Deliveries
  /Articles       <- Destination owned by Route A
  /Products       <- Destination owned by Route B
```

Every delivered article is a direct child of `Articles`; every delivered
product is a direct child of `Products`.

## Human-readable names and immutable identity

A Route Revision selects one canonical source field for the Delivery Item name,
such as source name, title, or slug. The target Adapter:

1. reads the configured value;
2. falls back to the normalized source item ID when it is absent;
3. sanitizes it for the target; and
4. appends a short deterministic suffix derived from the Delivery Item key.

Examples:

```text
mountain-bike--74bd2191
about-our-company--a82f14c9
```

The recognizable part supports visual comparison between source and target.
The suffix avoids collisions. The name is never ownership evidence and is never
used to decide whether to create or update an item.

CourierCMS separately maintains:

- the immutable Delivery Item key derived from Route, source item, and locale;
- the target reference returned by the Adapter, such as a Sitecore GUID, Sanity
  document ID, object key, file path, or API resource ID; and
- target ownership evidence used before an update.

The target reference is execution state, not a user naming policy. The Adapter
may update a physical name when the configured source value changes because the
stable target reference and Delivery Item key continue to identify the item.

## Required and optional target fields

The Intake Schema must retain the complete Canonical Delivery Document and the
ownership fields needed for lookup and safe updates. This includes the delivery
contract version, CourierCMS installation and Route identity, source identity,
locale, revision metadata, content hash, and complete canonical payload.

The canonical payload is normalized source content, not necessarily an exact
vendor API response. Literal raw responses may contain transient, irrelevant,
or sensitive values and are retained only when an Adapter explicitly defines a
safe need.

A project may extend its target Intake Schema with Projection Fields such as a
title, normalized body, legacy URL, or source classification. Route mappings and
transformations may populate reproducible projections from the Canonical
Delivery Document. Those projections remain conveniences; the canonical
document is authoritative.

The target environment may independently run hooks, workflows, scripts, AI, or
manual processes after delivery. CourierCMS does not trigger, monitor, or
include those actions in delivery status.

## Delivery Assets

The accepted architecture treats media and file dependencies as first-class
Delivery Assets with their own identity, retries, and target
bindings. Delivery Items remain flat. A target Adapter may store assets in a
separate CMS media library, object store, or asset service associated with the
Destination.

Required Delivery Assets must be accepted before their dependent Delivery Item
can succeed. CourierCMS never deletes target assets. Asset identities and item
dependencies are persisted. Independent jobs, retries, and target-reference
injection are still planned; currently supported production media is handled
during the parent Delivery Item attempt.
