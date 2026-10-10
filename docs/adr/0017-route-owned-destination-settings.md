# ADR-0017: Route-owned Destination settings

- Status: Superseded by ADR-0018
- Date: 2026-09-29

## Context

The stable Destination key proves ownership but does not describe optional
physical placement such as a CourierCMS root folder, bundle, or target scope.
Connection settings describe an Adapter instance; they should not absorb every
Route-specific target placement decision.

## Decision

An Adapter may declare bounded Destination configuration fields. Their values
are stored in the immutable Route Revision, validated by the target Adapter, and
passed through the Extension Gateway on delivery. The Route continues to own one
stable logical Destination key.

Destination placement cannot change after the Route has planned its first Route
Item. Moving delivery requires a new Route so existing target bindings and
ownership evidence never silently point at a different physical area.

Connection-scoped addressing remains on the Connection. For example, separate
Sanity datasets are separate Connections, while a future Sitecore Adapter may
declare a Route-specific CourierCMS root beneath its configured instance.

## Consequences

- Target-specific vocabulary remains in Adapter definitions, not generic UI or
  execution code.
- Runs pin the exact placement settings through their Route Revision.
- Logical Destinations need no physical folder; Sanity continues to use Route
  ownership fields and Studio filtering.
- Provisioning state may become a separate entity later if automated lifecycle
  operations require durable status; the settings alone do not justify one.

## Alternatives considered

- Put all target placement in Connection settings: rejected because two Routes
  may need independent areas within one configured CMS instance.
- Allow multiple Routes to share a Destination: rejected because write
  authority and ownership become ambiguous.
- Mutate placement on an active Route: rejected because existing Route Item
  bindings would refer to the former location.
