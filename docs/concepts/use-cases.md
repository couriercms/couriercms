# CourierCMS Use Cases

## Purpose

CourierCMS makes selected content from a CMS or CMS-like content source reliably
available in a controlled Destination without coupling the producer to the
consumer.

The use cases in this document are reasons to create Routes. They are not separate execution engines, product editions, or workflow modules. Migration, search, AI, archiving, and syndication all use the same transport primitive:

```text
CMS or CMS-like content source
    -> CMS-aware source Adapter
    -> selection and bounded aggregation
    -> Canonical Delivery Document
    -> Route execution and history
    -> content-delivery target Adapter
    -> target Destination
    -> target-owned hook, workflow, code, or AI
```

The source does not need target-specific integration code. The target does not need source-specific retrieval code. CourierCMS Adapters absorb those differences while the Canonical Delivery Document preserves provenance and the complete delivered payload.

## Qualification rules

A use case belongs in CourierCMS when:

- the source is a supported CMS or CMS-like repository with stable content
  identity and content semantics;
- the source is authoritative for the selected content delivered by that Route;
- CourierCMS can use create-or-update delivery without conflict resolution or target deletion;
- the target can accept content into an exclusively Route-assigned Destination
  and satisfy CourierCMS ownership and idempotent create-or-update semantics;
- delivery success can end when the target accepts the Delivery Item;
- target-native interpretation and downstream actions can remain target-owned; and
- operators benefit from durable history, retries, checkpoints, provenance, and alerts.

A use case does not belong in the core product when it requires generic workflow steps, arbitrary HTTP actions, direct delivery to unrelated business systems, bidirectional reconciliation, target publishing control, or customer scripts executed inside the CourierCMS runtime.

Search indexes, vector databases, commerce engines, translation services, and
similar systems normally participate downstream of a target-owned consumer. A
content store or purpose-built API may be a direct target only when it retains
the Canonical Delivery Document and implements the complete Destination
contract. Being able to accept an HTTP request is not sufficient.

## Transition and platform-change use cases

### Migration feed

During replatforming, CourierCMS continuously delivers selected content from the legacy CMS into the new CMS's Destination. Migration tooling or target-owned code converts those deliveries into the new native model.

CourierCMS supplies current, observable, replayable input to the migration. It does not own migration planning, redirects, editorial cutover, native schema design, or final validation.

### CMS replacement coexistence

An old CMS may remain authoritative for one content domain while a new CMS owns another for months or years. CourierCMS bridges the boundary without pretending the systems are synchronized.

This is valuable when organizational or technical constraints make a single cutover unrealistic.

### Acquisition integration

An acquired organization keeps its existing CMS while selected content begins entering the parent company's content ecosystem. Independent Routes can introduce only the approved content types, brands, locales, or regions.

This provides useful integration before a broader platform-consolidation decision is made.

### Vendor-exit continuity

An organization continuously materializes selected content in a second CMS while preparing to leave a vendor or reduce dependency on a legacy platform. The receiving CMS has an inspectable content-level copy with stable source identity and provenance.

CourierCMS does not claim to reproduce proprietary workflows, presentation, permissions, or complete disaster recovery.

### Headless modernization feed

A traditional CMS remains the editorial authority while content is delivered into a headless CMS used by a new frontend or application. This permits frontend modernization without immediately replacing established authoring workflows.

## Distribution and syndication use cases

### Central content distribution

One authoritative CMS feeds several consuming CMSs or digital properties. CourierCMS represents this as one Route per target so retry state, mappings, ownership, history, and failures remain independent.

```text
Corporate CMS -> Route A -> Regional CMS
              -> Route B -> Product CMS
              -> Route C -> Partner CMS
```

### Cross-brand and regional syndication

Corporate teams create articles, product information, campaign material, or legal notices once and distribute them to brand or regional CMSs. Each destination may localize, approve, enrich, schedule, or reject the delivered content after arrival.

### Partner and franchise distribution

A central organization delivers approved content to independently operated partner or franchise CMSs. Receivers obtain local content records rather than depending on runtime page embedding or availability of the central CMS.

Separate Routes preserve each partner's credentials, delivery history, rate limits, and failures.

### Legal and policy distribution

Approved disclosures, policies, safety notices, terms, or regulated copy can be delivered to every CMS that must make them available. The envelope provides source revision and delivery provenance, while each target remains responsible for approval, presentation, publishing, and retention.

CourierCMS does not certify regulatory compliance; it makes delivery observable and reproducible.

### Channel-specific content delivery

Selected content can be delivered into CMSs dedicated to mobile applications,
kiosks, portals, documentation, support, or other channels. The target
environment may independently adapt delivered canonical content to a
channel-native model.

### Content Hub, PIM, and DAM-style distribution

Structured product or content-hub records can be delivered into consuming CMSs.
Supported assets may currently remain remote references or be handled by the
target Adapter during the parent item attempt. First-class Delivery Assets are
planned for independent delivery, retries, and target bindings.

CourierCMS is most valuable for structured content that must exist locally in the consuming CMS rather than being fetched at request time.

This use case remains inside the product boundary when the source exposes
CMS-like content semantics and the target implements the complete Destination
contract. A generic product database or object store is not automatically
eligible; it requires a content-focused Adapter with stable identity, ownership,
canonical document retention, and create-or-update behavior.

## Consolidation and aggregation use cases

### Multi-CMS content aggregation

Selected content from several CMSs can converge on one target CMS. Because a
Route has exactly one source and one target, this is represented by several
independent Routes using separate Destinations beneath one optional
organizational parent:

```text
Regional Sitecore -> Route A -> Destination A --+
Drupal            -> Route B -> Destination B ---+-> Central headless CMS
WordPress         -> Route C -> Destination C --+
```

The target uses Route and source provenance to keep deliveries distinguishable and decides whether to merge them into native content.

### Editorial-domain handoff

Different teams may own specialized CMSs for products, documentation, news, learning content, or support. CourierCMS delivers selected records across those domain boundaries without requiring either team to implement the other platform's API.

### Corporate content library

An organization may collect approved content from business-unit CMSs into a central CMS used as a searchable internal library. The central target can retain the canonical deliveries, promote selected records, or expose them to downstream services.

## Target-processing use cases

### Target-site integration

A Delivery Item becomes input for target-owned hooks, functions, workflows, AI, or custom code. The consumer may create or update native site content, enrich it, route it for approval, or reject it.

CourierCMS success ends at Destination acceptance. Target processing needs its own idempotency, recursion protection, contract-version handling, monitoring, and optional future acknowledgement.

### External search and indexing feed

CourierCMS delivers selected content into a target CMS or intake area whose hook updates Solr, Elasticsearch, Azure AI Search, or another index. CourierCMS does not need a search module or direct search-engine Adapter.

This gives the indexing process a normalized change feed with stable identity, complete canonical content, retries, and provenance.

### AI and RAG ingestion source

Instead of giving an AI system custom read access to several CMS APIs, CourierCMS delivers selected content into a controlled target CMS Destination. A target-owned process handles chunking, embeddings, classification, vector storage, access filtering, and model interaction.

CourierCMS does not become an AI orchestration or RAG platform.

### Commerce enrichment

Editorial descriptions, buying guides, specifications, taxonomy, and media metadata can be delivered into a commerce-oriented CMS. Target-owned code connects those deliveries to native product records.

CourierCMS transports CMS content; it does not own catalog synchronization, pricing, inventory, orders, or commerce workflows.

### Content quality and governance intake

Selected content can be delivered to a target CMS where hooks evaluate accessibility, taxonomy, brand rules, broken links, metadata completeness, or policy compliance. Findings and remediation remain target-owned.

This is a delivery use case, not a reason to add a generic rules engine to CourierCMS.

### Localization and translation handoff

Source-language content can be delivered into a CMS used by localization teams or translation workflows. The target controls translation, review, and publication.

Returning translated content to another CMS would require a separate one-way Route with explicit authority. It must not be presented as bidirectional synchronization.

## Continuity and evidence use cases

### Content mirror and recovery feed

CourierCMS can continuously materialize selected content in another CMS as a recoverable content-level mirror. After an operator clears or recreates a Destination, Full Scan with Force Full Redelivery can repopulate all currently selected content.

This is not a backup service or an exact replica. It does not preserve the complete source database, binary history, users, permissions, workflows, configuration, presentation layer, or content that no longer matches the Route. CourierCMS never deletes obsolete target items to make the mirror exact; retention and cleanup remain target-owned.

### Compliance and reference copy

The target can retain the content received from another CMS together with source identity, locale, revision, timestamps, contract version, and content hash. This creates an attributable reference copy for target-owned retention or review processes.

The current create-or-update model retains the latest Delivery Item while CourierCMS Run history records delivery activity. Immutable payload history would be a separate retention capability, not an assumption of V0.

### Controlled external-content intake

An organization can receive selected content from another division, partner, or acquired company into an isolated Destination. Target teams inspect and process the canonical delivery without granting the producer access to native editorial areas.

## Development and operational use cases

### Preview, staging, and redesign feed

Production-like upstream content can be delivered to a staging CMS used for a frontend redesign, personalization project, search implementation, or content-model experiment.

Use non-sensitive or appropriately protected content. CourierCMS does not sanitize confidential production data automatically.

### Environment seeding

A controlled Route can populate a test or demonstration CMS with selected source content. After the Destination is cleared or recreated, Force Full Redelivery can repopulate all content currently matching the Route. This is useful when representative structured content is more valuable than synthetic fixtures.

This is content seeding, not complete environment cloning. CourierCMS does not remove target items that stopped matching the source selection.

### Normalized CMS change feed

Publish events or incremental polling cause CourierCMS to read authoritative
source content and create or update stable Delivery Items. Target-owned code may
read those items as a normalized CMS-aware feed without understanding the
source API, but that code is not part of CourierCMS execution.

CourierCMS guarantees observable at-least-once delivery, not an ordered global event stream or general-purpose message bus.

### Network-boundary bridge

A self-hosted CourierCMS deployment can read an internal CMS and deliver outward to an approved cloud CMS, or operate near private systems that cannot expose inbound webhooks. Incremental polling provides delivery without requiring public access to the source network.

Network policy, TLS, egress controls, and credentials remain deployment responsibilities.

## Product implications

These use cases do not justify separate Search, AI, Migration, Backup, or Commerce engines inside CourierCMS. They reinforce investment in the shared transport capabilities:

- deep CMS-aware Adapters;
- expressive source selection and bounded aggregation;
- complete Canonical Delivery Documents;
- stable identity, ownership, and provenance;
- manual, event-driven, incremental, and reconciliation execution;
- idempotent create-or-update delivery;
- item-level retries and replay;
- clear history, monitoring, and alerts; and
- a simple, versioned document for optional target-side integration.

The durable product value is decoupling content producers from content consumers while making delivery reliable and understandable.
