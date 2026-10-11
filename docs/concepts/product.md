# Product Definition

## One-sentence definition

CourierCMS is a self-hosted, adapter-based platform for reliably delivering
selected content from a CMS or CMS-like content source into a controlled
Destination.

## Problem

Organizations often operate more than one CMS permanently. Moving selected content between them usually requires custom integrations that are difficult to observe, retry, audit, and extend. CourierCMS provides a CMS-focused transport layer with reusable adapters and durable delivery history.

## Core job

```text
Select source content
        -> assemble relevant source content
        -> map it into the delivery contract
        -> reliably create or update target Delivery Items and Assets
        -> expose history, errors, retries, and alerts
```

CourierCMS's responsibility ends when the target Adapter confirms acceptance
of a Delivery Item and its required Delivery Assets into the configured
Destination. Every Delivery Item includes the complete
Canonical Delivery Document as JSON. Optional target-native Projection Fields
expose selected canonical values for easier target-side querying and
integration; they do not replace the canonical document.

## Users

- Developers building and operating CMS integrations
- Content platform teams supporting multiple CMS products
- Enterprise operations teams that need self-hosted credential and content handling
- Content administrators who configure Routes and monitor delivery

## Primary use cases

- Content distribution from a central CMS to other CMS platforms
- Long-lived delivery between CMSs used by different departments or regions
- Acquisition and consolidation scenarios where both CMSs remain operational
- Temporary transport during a replatforming project
- CMS-to-CMS content syndication
- Delivery through a compatible content store when a target CMS cannot accept
  content directly yet

See [CourierCMS Use Cases](use-cases.md) for the complete catalog and the rules used to decide whether a scenario belongs in the platform.

## Core behavior

A Route has one source Connection, a selection that can discover many root
items, bounded aggregation rules, a versioned mapping, one target Connection,
one exclusively assigned Destination, and trigger policies. Each root source
item and locale produces one Delivery Item in that flat, Route-owned
Destination.

CourierCMS creates a Delivery Item if it has not been delivered before and updates that same Delivery Item for later source revisions. A different locale produces a distinct Delivery Item. Revision history remains visible in CourierCMS Runs and Run Items.

CourierCMS never deletes Delivery Items. If a source item is deleted or stops matching a Route, CourierCMS may record that fact but takes no destructive target action.

## Responsibility boundary

CourierCMS owns:

- Source connectivity and selection
- Source save/publish/manual/periodic triggers
- CMS-specific, bounded assembly of referenced source content
- Mapping to a versioned delivery contract
- Building and validating the complete Canonical Delivery Document
- Planned target-independent Transformations and Extension Processors
- Reliable Delivery Asset handling as it becomes available
- Deterministically deriving configured Projection Fields from that document
- Reliable create/update delivery
- Idempotency, retries, checkpoints, monitoring, and alerts
- The CourierCMS Destination and ownership metadata

The target environment may independently perform:

- Parsing or otherwise using delivered payloads
- Transforming deliveries into its native schema and business model
- Creating or updating native editorial content
- Editorial review and approval
- Publishing and unpublishing
- Indexing, site builds, and downstream hooks
- Retention, archival, and deletion

## Explicit non-goals

CourierCMS is not:

- Bidirectional synchronization
- Conflict resolution
- A full migration suite
- A generic workflow designer
- An integration marketplace for non-CMS systems
- A replacement for target CMS workflow or publishing
- A general ETL, ESB, iPaaS, n8n, or Zapier alternative
- A place to run arbitrary user-supplied scripts

Two Routes in opposite directions are independent and dangerous. The UI should warn about a possible content loop.

## Product principles

1. **CMS-specific at the edges.** Each adapter understands one CMS deeply.
2. **Small common core.** The transport envelope does not attempt to model every CMS.
3. **One-way authority.** The source is authoritative for each delivery.
4. **Reliable over immediate.** Eventual delivery with visible retries is preferable to hidden loss.
5. **Safe ownership.** CourierCMS modifies only target items it can prove it owns.
6. **Target autonomy.** Target workflows remain outside CourierCMS.
7. **Deterministic execution.** Approved mappings run predictably; enrichment records its configuration and version.
8. **Self-hosted by default.** Credentials and content remain inside the customer's deployment boundary, apart from calls to configured CMS platforms.
9. **Extensible deliberately.** Adapters, transformations, planned Processors,
   and optional CMS Connectors have focused contracts.
10. **Operational clarity.** Every delivery has an understandable status and history.
11. **Canonical first.** The complete JSON delivery is always retained; target-native projections are disposable, reproducible conveniences.
12. **Human-readable delivery.** Delivery Item names remain recognizable to
    operators, while immutable identifiers—not names—control updates.

## Endpoint boundary

CourierCMS remains CMS-focused even though a Destination does not have to be a
CMS tree. A source must expose content semantics such as stable item identity,
content type, locale, modification state, fields, references, and assets. A
target must implement the CourierCMS create-or-update, ownership, canonical
document, and idempotency contract.

A purpose-built API, object-store prefix, or filesystem directory may therefore
be supported by a target Adapter as a compatible content-delivery store. This
does not make arbitrary HTTP actions, business events, queues, or unrelated SaaS
automation valid CourierCMS endpoints.

## Current foundation

- Configure and test a WordPress source Connection and Sanity target Connection.
- Define a filtered Blog Post Route.
- Preview a representative delivery from the current source selection.
- Manually and periodically execute the Route.
- Configure incremental periodic polling with full fallback and scheduled Full Scan reconciliation.
- Run a Full Scan and explicitly Force Full Redelivery without creating duplicate target identities.
- Receive authenticated publish events through an optional WordPress Connector.
- Aggregate author, taxonomy, body, and featured image data per post.
- Create one Sanity Delivery Item per source item and locale, then update it for later revisions.
- Preserve the complete canonical JSON in every Sanity Delivery Item and prove optional projected fields match it.
- Replay without duplicates.
- Retry transient failures without failing unrelated items.
- Display Run and Run Item history.
- Alert on terminal delivery failures.

These capabilities define the current working foundation; they are not a 1.0
release or compatibility promise.

## Current foundation and next execution stage

The current implementation assembles referenced content inside each source
Adapter and returns it through the bounded Content Bundle contract. When both
Adapters support the optional asset callbacks, the platform persists,
transfers, retries, binds, and reconciles Delivery Assets independently before
delivering dependent items. The official WordPress source and Sanity target
implement the independent featured-image path; other Adapter combinations may
still use an Adapter-specific fallback until they adopt the contract.
Extension Processor execution is an accepted next capability, not a claim about
the current runtime. See
[ADR-0020](../adr/0020-delivery-boundary-content-bundles-and-assets.md).
