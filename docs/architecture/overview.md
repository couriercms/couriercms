# Architecture

## Style

CourierCMS is a modular Phoenix monolith using Ecto and Oban. It is not an
umbrella application or collection of microservices. Domain boundaries are
enforced through modules, contexts, behaviours, data ownership, and tests.

One codebase produces two release profiles. Local is a single process backed by
SQLite; Server is backed by PostgreSQL and may run as a combined, web, or worker
process. Server roles are deployment choices, not separate applications or
domain services. See [release profiles](release-profiles.md).

## Runtime view

```text
                         CourierCMS
  +----------------------------------------------------+
  | Phoenix / LiveView                                 |
  |   Access | Connections | Routes | Runs | Monitoring|
  |                         |                          |
  |                    Application contexts            |
  |                         |                          |
  |                   Execution planner                |
  |                         |                          |
  |                    Oban job graph                  |
  |                         |                          |
  | Extension Gateway / node-local Component Registry      |
  |                         |                          |
  | Source Adapter -> canonical document -> Target Adapter |
  |                         |                          |
  |          SQLite or PostgreSQL + PubSub              |
  +-----------+----------------------------+-----------+
              |                            |
     Content source/API          CMS/content delivery store
              ^
              |
     Optional CMS Connector
```

## Deployment topology

Local runs exactly one application process and listens on loopback:

```text
Browser -> CourierCMS Local (web + workers + scheduler) -> SQLite file
```

Server supports the following topologies.

The default `all` role preserves the small-installation topology:

```text
CourierCMS (web + workers + scheduler) -> PostgreSQL
```

A larger installation may run the same release in separate roles:

```text
                    +-> web node(s)
PostgreSQL <--------+-> worker node(s)
                    +-> one scheduler-enabled worker
```

Every node shares the same database, installation ID, vault key, and compatible release version. Web nodes retain Oban without executing queues so controllers and LiveViews can durably enqueue work. Worker nodes can consume a configured subset of allowlisted queues. Queue concurrency is per node.

Every node that validates or executes Extension-backed components also has the
same Extension package version and checksum. Each node loads packages locally
at startup and builds its own ETS Component Registry; the registry is not a
shared service. Fresh node heartbeats persist a content-free, deterministic
fingerprint of registered component artifacts in PostgreSQL. Readiness,
telemetry, and the operator screen expose a mixed package set, while each Run's
exact artifact evidence prevents an incompatible worker from executing only
the affected work.

Phoenix PubSub provides immediate progress when nodes are connected. Open Route pages and active Run pages also periodically read PostgreSQL, making the displayed state resilient when cross-node PubSub is unavailable.

## Application areas

### Accounts and Workspaces

Own passwordless identity, magic-link sessions, invitations, role-based
authorization, workspace data boundaries, and security audit events. V0 presents
one default Workspace. Every authenticated domain operation receives a Scope
containing the user, active Membership, and Workspace.

### Connections

Owns configured Adapter instances, endpoints, non-secret settings, encrypted credentials, capability discovery, and connection tests.

### Routes

Owns Routes, immutable Route Revisions, source selections, aggregation
configuration, payload contracts, Delivery Item naming configuration, and
trigger policy. Content Bundle validation, root mapping, versioned built-in
Transformations, and version-pinned Extension Processors are implemented.

Mutable Route identity is limited to operator-facing name and active state.
Changing selection, aggregation, mapping, projections, transformations, or
trigger execution settings creates an immutable Route Revision. Mapping and
Projection changes increment the Delivery Contract version. Selection changes
establish a new Full Scan baseline before later incremental discovery.

### Transport

Owns Canonical Delivery Documents, Projection definitions, and validation
independent of a particular CMS. Source Adapters assemble normalized Content
Bundles in `read_root/3`. The SDK exposes portable assembly results and an
optional asset-streaming contract without moving CMS-specific traversal into
the platform. Public boundary values such as
normalized source identity, content nodes, delivery envelopes, and Adapter
errors live in the standalone Extension SDK.

### Execution

Owns Runs, planning, enumeration, batching, item state, delivery, checkpoints, retries, cancellation, and progress telemetry.

Scheduled ticks coalesce while a scheduled Run for the same Route remains
active. Run summary counters are updated transactionally with item status
transitions and receive one authoritative recount when completion is possible.
An Adapter-declared authoritative change token may avoid `read_root/3`; the
canonical content hash remains the fallback.

### Adapters

Defines source and target behaviours, capability declarations, error
normalization, and CMS-independent gateway calls. CMS-specific implementations
are supplied by trusted native OTP Extensions.

### Extensions

Owns package discovery and validation, the Extension SDK compatibility boundary,
OTP application startup, the node-local Component Registry, and gateway
resolution. Installed code lives on the local filesystem; configured component
identities and execution artifact evidence live in PostgreSQL.

The supervised Component Registry loads startup-validated `.couriercms`
packages. Contexts, workers, and LiveViews dispatch only through the Gateway.
Durable records use stable Extension/component IDs.

### Transformations

Owns ordered built-in allowlisted Transformations and Extension Processors,
including immutable versioned configuration, exact Run artifact evidence,
bounded execution, and safe failure reporting. They run after mapping and
before content hashing and canonical-document construction. Target-native business transformations remain
outside CourierCMS.

### Ownership

Owns registered Destination lifecycle and exclusive Route assignment, per-
Destination Delivery Bindings, and verification required before an update.

### Web

Owns presentation, HTTP endpoints, authenticated webhook ingress, and LiveView state. It does not contain delivery business logic.

Operator screens follow a summary-first query model. Opening a Run, Route, or
other aggregate loads its persisted summary and counters, not every child
record. Potentially large collections such as Run Items, deliveries, events,
and audit entries are queried separately only after an explicit operator action
and are always bounded by pagination or an equivalent cursor. Live progress
updates refresh summary state without retransmitting an entire child
collection. Full payloads and record details are loaded only when requested.

Connection and Route forms are Adapter-driven. Generic LiveViews render bounded
field descriptors returned by registered Adapter components and never branch on
a CMS key. CMS-specific labels, settings, credential names, selection
predicates, defaults, and Connector presentation remain inside the Adapter
implementation.

## Code structure

```text
platform/
  lib/
    courier_cms/
    courier_cms_web/
  test/
    courier_cms/
    courier_cms_web/
extensions/
  sdk/
  fake/
  content/
  wordpress/
  sanity/
connectors/
  wordpress/
examples/
  sanity-consumer/
docs/
```

## Adapter topology

Cloud CMS:

```text
CourierCMS -> native Extension Adapter -> cloud CMS API
```

Self-hosted CMS without a Connector:

```text
CourierCMS -> native Extension Adapter -> CMS REST/API endpoint
```

Self-hosted CMS with a Connector:

```text
CourierCMS -> native Extension Adapter -> installed CMS Connector -> CMS internals
```

Remote Adapter workers and an external protocol are not part of the accepted
Extension architecture. Segmented-network support requires a separate decision.

## Current data flow

1. A Trigger requests execution of a Route Revision.
2. The source Adapter enumerates matching root identities or reads the event-specific identity.
3. Execution durably records discovered work.
4. The source Adapter reads and assembles the normalized root content.
5. CourierCMS validates the returned content and builds the Delivery Contract payload.
6. CourierCMS combines the stable envelope, complete payload, and ordered resolved asset manifest into the Canonical Delivery Document.
7. Configured Projection Fields are derived from that same document and validated; they never become a second source of truth.
8. When both Adapters support the independent asset contract, CourierCMS
   schedules, retries, binds, and reconciles Delivery Assets before resuming the
   dependent item; otherwise the Adapter may retain its documented in-item
   asset behavior.
9. CourierCMS injects successful asset target references at declared payload
   paths and records every reference in the canonical asset manifest.
10. CourierCMS derives a recognizable, collision-safe flat Delivery Item name
    from the Route Revision's naming field and immutable Delivery Item key.
11. The target Adapter resolves or creates the Delivery Item and writes the canonical document plus any projections atomically where the CMS permits.
12. Ownership is verified before an existing item or asset is updated.
13. CourierCMS records the Delivery Binding and Run Item result.
14. Progress is published to the UI and terminal failures can raise alerts.

The bounded Content Bundle and independent Delivery Asset execution are
implemented foundations. The fake Extension validates the full portable path,
and the official WordPress source and Sanity target implement it for featured
images. Other Adapters must adopt and test the callbacks before advertising
them. Platform-invoked target-independent Processors cover specialized portable
content work. See
[ADR-0020](../adr/0020-delivery-boundary-content-bundles-and-assets.md).

## Extension boundaries

- **Extension:** trusted installable OTP package containing one or more components
- **Adapter:** one CMS's API and semantics
- **CMS Connector:** optional installed CMS companion
- **Transformation:** small field conversion
- **Processor:** bounded, target-independent Extension content operation

Adapters and Processors are components in trusted, precompiled OTP Extensions
loaded when the CourierCMS node starts. One version of an Extension ID is
installed at a time.
Installation and upgrade use a controlled restart, not hot reload. The
Extension Gateway resolves stable identifiers through a node-local ETS registry
and calls the validated module directly.

CMS Connectors remain separately installed CMS-native components. Extensions
provide declarative definitions rather than injecting LiveView, JavaScript,
database migrations, or arbitrary executable Route steps. Ports, sidecars,
remote workers, and a language-neutral protocol are not part of this design.
See [Extension architecture](extensions.md) and
[ADR-0015](../adr/0015-native-otp-extensions.md).

## Architectural constraints

- No adapter-to-adapter knowledge.
- No CMS-specific module references outside Extension loading, gateway, and
  conformance-test boundaries.
- No runtime compilation or hot reload of Extension source.
- No business logic in Oban workers or LiveViews.
- No raw CMS response maps beyond adapter boundaries.
- No arbitrary executable transformations from database content.
- No target-native schema, workflow, publishing, rewriting, translation, or AI policy in a core Transformation.
- No target deletion operation in the core target behaviour.
- No assumption that target CMSs support folders.
- No source hierarchy is recreated inside a Destination; Delivery Items are flat.
- No target-side post-delivery action or acknowledgement is part of CourierCMS
  execution state.
- No assumption that all CMSs expose locales, revisions, or publish events identically.
- No target Adapter may omit the complete Canonical Delivery Document because Projection Fields exist.
- No delivery Run may mutate target schema; Intake Schema provisioning and validation are explicit operations.
