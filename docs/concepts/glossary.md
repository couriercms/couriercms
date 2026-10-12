# Glossary

Use these terms consistently in code, UI, documentation, and discussion.

## Workspace

The customer-owned authorization and data boundary containing Connections,
Routes, Runs, and membership administration. V0 has one default Workspace and
does not expose switching in the UI.

## Workspace Membership

A user's role and access status in a Workspace. Roles are owner, admin,
operator, and viewer. Status is invited, active, or blocked. A future CourierCMS
hosted-platform administrator is not a Workspace Membership role.

## Adapter

A CourierCMS-side component that understands one content system. An Adapter can implement
source capabilities, target capabilities, or both. It never understands or
calls another Adapter. Native Adapters are supplied by an Extension.

## Extension

A trusted, administrator-installed, precompiled OTP application loaded into the
CourierCMS VM at startup. It contributes Adapter and Processor components through
the versioned Extension SDK. One version of
an Extension ID is installed at a time; installation and upgrade require a
restart.

## Component Registry

A rebuildable, node-local ETS lookup mapping stable Extension and component IDs
to validated modules, capabilities, versions, and package checksums. It is not
shared storage; the configured SQLite or PostgreSQL database remains the
durable source of configuration and execution history.

## Extension Gateway

The core boundary that resolves a stable component identifier through the
Component Registry, validates execution artifact compatibility, and invokes the
approved Adapter or Processor callback.

## CMS Connector

An optional component installed inside a CMS, such as a WordPress plugin, Drupal module, or Sitecore module. It can emit authenticated events or expose optimized CMS-native endpoints. A Connector is not an Adapter.

## Integration

An operator-facing grouping of an Adapter, optional CMS Connector,
documentation, and setup guidance for one external content system. It is not a
runtime execution unit.

## Connection

A configured instance of an Adapter, including endpoint, non-secret settings,
capability snapshot, and encrypted credential references. Connection-scoped
addressing such as a Sanity dataset belongs here. Examples include `Corporate
WordPress` and `Marketing Sanity`.

## Route

A persistent, one-directional delivery definition from exactly one source
Connection through exactly one current, exclusively assigned Destination. It
delegates executable configuration to immutable Route Revisions.

## Route Revision

An immutable snapshot of selection, aggregation, mapping, payload contract,
Delivery Item naming, transformations, Processors, and trigger-related execution settings.
Every Run references one Route Revision.

## Source Selection

The scope and filters used to discover root Content Items. It may contain content types, paths, parents, categories, tags, date predicates, locales, and publication-state rules.

## Root Content Item

An independently selected source CMS item, document, entry, entity, or post. Each root item is the basis of one or more Delivery Items across locales and revisions.

## Aggregation Rule

A bounded instruction describing which source references, components, datasources, taxonomy values, authors, or assets should be included in the root item's payload.

## Content Bundle

The bounded, normalized result assembled by a source Adapter for one root
Content Item. It contains included source content and relationships, Delivery
Asset descriptors, and required source metadata. Included content normally
becomes nested data in one Delivery Item rather than separate target items.

## Delivery Contract

The versioned, target-independent shape produced by a Route mapping. It describes the payload expected inside a Delivery Item.

## Delivery Envelope

The stable CourierCMS metadata surrounding a payload: installation, Route, source identity, locale, revision, state, contract version, timestamps, and content hash.

## Canonical Delivery Document

The complete, versioned JSON document formed from the Delivery Envelope,
Delivery Payload, and optional ordered Delivery Asset manifest. It is always
retained in the target Delivery Item and is the authoritative representation of
what CourierCMS delivered.

## Intake Schema

The stable, adapter-provided target CMS model used for CourierCMS Delivery Items. It stores the Canonical Delivery Document, ownership and lookup fields, and any explicitly configured Projection Fields. It is not the customer's native editorial content model.

## Projection Field

An optional target-native field deterministically derived from a path in the Canonical Delivery Document. Projection Fields make common target queries, hooks, and workflows easier, but contain no authoritative data that is absent from the canonical document.

## Delivery Item

One target resource created or updated by CourierCMS for one root Content Item
and locale. It may be represented as a CMS item, document, record, object, file,
or purpose-built API resource. Later source revisions update the same Delivery
Item. It retains the complete Canonical Delivery Document and may also contain
ownership, preview, Delivery Asset references, and Projection Fields.

## Delivery Asset

A durable media or file dependency delivered for one or more Delivery Items.
CourierCMS persists its deterministic identity, metadata, per-Run state, item
dependencies, and Destination-scoped target binding. When both Adapters support
the optional asset contract, required Delivery Assets execute and retry in
independent jobs and must succeed before a dependent Delivery Item can succeed.
Adapters that have not adopted the contract may retain documented in-item asset
behavior.

## Destination

A separately registered, target-Adapter-defined receiving scope for a flat set
of Delivery Items. It belongs to one target Connection and is assigned
exclusively to one Route. It may be a CMS parent item, logical document
partition, object-store prefix, filesystem directory, or purpose-built content
API namespace. After its first successful delivery it cannot be automatically
released or reassigned.

## Target Reference

The target-native identifier returned for a Delivery Item, such as a CMS item
ID, document ID, object key, file path, or API resource ID. CourierCMS stores it
in the Delivery Binding; it is not a human naming policy or ownership proof by
itself.

## Route Item

The durable CourierCMS ledger entry for one normalized source item/locale
identity within a Route. It records latest observed source state but does not
normally store the full payload.

## Delivery Binding

The durable association between one Route Item and its target resource in one
Destination. It stores the target reference, ownership evidence, last delivered
hash, and delivery history pointers. A new binding is created when a Route is
explicitly moved to a new Destination; the retired Destination's binding is
preserved.

## Run

One execution of one Route Revision, initiated manually, periodically, or from one or more source events.

## Run Item

The processing and delivery result for one Delivery Item within one Run, including status, operation, attempts, error category, and timing.

## Checkpoint

Durable adapter-specific progress used to resume incremental discovery. A checkpoint advances only after discovered work is durably accounted for.

## Trigger

A reason to start or contribute work to a Run: manual request, schedule, polling interval, save event, or publish event.

## Full Scan

A Run that enumerates the complete current Route selection. Previously delivered items whose content hash is unchanged are skipped. A Full Scan is useful for establishing a baseline, discovering content whose source modification time predates a checkpoint, and reconciliation.

## Force Full Redelivery

An explicit operator Run that enumerates the complete current Route selection and writes every matching Delivery Item again, including unchanged items. It retains stable Delivery Item identities, verifies ownership, and uses create-or-update semantics; it never deletes target content.

## Transformation

A named, allowlisted, deterministic conversion that makes source content
portable while remaining independent of the target's native editorial model.
Route Revisions store an ordered chain of versioned built-in operations as
immutable data. CourierCMS applies the chain after mapping and before hashing
and canonical-document construction.

## Processor

A bounded content operation such as OCR, image metadata extraction, or document
parsing. A Processor is supplied by a trusted native Extension. A Route Revision
stores its ordered component reference, exact component version, input/output
paths, data-only configuration, and fail policy. Runs pin the exact Extension
package checksum before executing it through the Extension Gateway. A Processor
cannot inject arbitrary Route workflow steps.

## Delivery success

Confirmation that the target Adapter accepted the Delivery Item and all of its
required Delivery Assets into the Destination. It does not mean the target
published, materialized, or otherwise processed the content afterward.
