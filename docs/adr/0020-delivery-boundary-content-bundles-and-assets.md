# ADR-0020: Delivery boundary, Content Bundles, and Delivery Assets

- Status: Accepted
- Date: 2026-10-11

## Context

CourierCMS reliably delivers selected CMS content into a Destination. Earlier
documents used **Target Consumer** as a named concept for customer code that
might react to a delivery, and mentioned a possible downstream
acknowledgement. Those terms made optional behavior in the target environment
look like part of the CourierCMS runtime and success model.

CMS content is also rarely a single isolated record. A Sitecore page may refer
to renderings, datasources, and media; a Drupal node may refer to paragraphs,
entities, taxonomy, and files. The platform needs a portable result without
pretending that every CMS exposes the same traversal model.

Large or shared media needs stronger reliability semantics than an incidental
field inside a content write. Extension Processors are also useful for bounded,
target-independent transformations. The runtime supports independent asset
delivery when both Adapters advertise the optional SDK callbacks and supports
bounded Processor execution through the Extension Gateway.

## Decision

### Delivery boundary

CourierCMS delivery is complete when the target Adapter confirms that the
Delivery Item and all of its required Delivery Assets have been accepted into
the configured Destination. CourierCMS records and retries that work.

Anything performed afterward by the target environment is outside CourierCMS.
That includes native content creation, template selection, hierarchy,
editorial workflow, approval, publishing, indexing, AI, and other target-side
automation. CourierCMS neither triggers nor monitors those actions, and no
downstream acknowledgement is part of a Run or Delivery Item status.

**Target Consumer** and **Target acknowledgement** are therefore retired as
CourierCMS domain terms. Documentation may describe target-owned hooks or code
as optional downstream use of delivered content, but not as a platform
component or roadmap requirement.

### Content assembly

Each source Adapter owns CMS-specific discovery and assembly. It understands
its CMS's references, components, datasources, taxonomy, locales, and media.
The portable output of that work is the implemented bounded **Content Bundle**:

- one selected root Content Item;
- normalized included content and relationships;
- Delivery Asset descriptors; and
- source metadata needed for mapping, change detection, and diagnostics.

The platform validates generic bounds and invariants such as payload size,
node count, duplicate identities, deterministic ordering, missing-dependency
policy, and cycles. It does not implement one universal CMS traversal
algorithm. Route configuration declares aggregation intent and limits; each
source Adapter validates and interprets the supported rules.

Included content normally becomes nested data in one root Delivery Item. It
does not create target hierarchy or automatically become independent Delivery
Items. Delivery Items remain flat within a Destination.

### Transformations and Processors

Small, named, deterministic, target-independent Transformations may be part of
the platform. Heavier bounded work may be provided by a Processor component in
a trusted Extension. One Extension package may contain source Adapters, target
Adapters, and Processors when they share ownership and release lifecycle; a
reusable Processor may instead be distributed as its own Extension.

The platform invokes Processors through the Extension Gateway and owns their
ordering, version evidence, limits, errors, retries, and execution history.
Adapters do not invoke Processors directly. Processors cannot call target
Adapters or introduce arbitrary workflow steps.

Processor execution is implemented through the package validator, Component
Registry, Extension Gateway, immutable Route Revisions, exact Run artifact
evidence, preview, and per-item execution path.

### Delivery Assets

A **Delivery Asset** is a first-class, durable media or file dependency needed
by one or more Delivery Items. It has its own deterministic source
identity, content metadata, status, retry history, checksum when available, and
target binding. Binary data is streamed or stored temporarily; it is not put in
database JSON or job arguments.

Required Delivery Assets are delivered before their dependent Delivery Item.
A required asset failure prevents that item from being marked successful. The
target Adapter returns the target asset reference used in the Canonical
Delivery Document. Shared assets may reuse a verified target binding, and
CourierCMS never deletes target assets.

Delivery Assets are logically related to a flat Destination even when the
target system stores them in a separate media library, bucket, or asset store.
They do not introduce a source-derived content hierarchy.

First-class Delivery Asset persistence, bounded temporary-file transfer,
independent jobs and retries, required-dependency gating, target-reference
injection, binding reuse, and stranded-job reconciliation are implemented.
The fake Extension exercises the complete contract in both release profiles.
The official WordPress source and Sanity target also advertise and test the
independent contract for featured images. WordPress streams source bytes and
Sanity records a deterministic owned receipt pointing to its content-addressed
native image. Run pages expose bounded asset views, summary counters, and a
retry action that also requeues affected required Delivery Items.

## Consequences

- CourierCMS has one unambiguous success boundary: reliable target acceptance.
- Target systems remain free to run any downstream behavior without coupling
  it to CourierCMS execution state.
- CMS-specific graph knowledge stays at the Adapter edge while the platform
  can enforce portable safety bounds.
- Flat Delivery Items remain easy to browse and operate.
- Assets can retry, deduplicate, reconcile, and record failures independently
  without weakening Delivery Item reliability.
- An Adapter must pass the asset contract tests before advertising the
  independent pipeline. A Processor must pass manifest, configuration,
  deterministic execution, artifact-pinning, limit, and failure tests before
  it is advertised as a current capability.

## Alternatives considered

- Make target-side native-content creation part of delivery: rejected because
  it would couple transport to target workflow and turn CourierCMS into a
  migration or automation engine.
- Track downstream acknowledgements: rejected because CourierCMS does not own
  the downstream process and cannot give that status consistent semantics.
- Implement generic reference traversal in the platform: rejected because CMS
  relationship and composition models differ substantially.
- Treat assets only as a side effect of content delivery: rejected as the
  long-term model because asset size, sharing, retries, and target identity
  require independent durable handling.
