# ADR-0011: Canonical Delivery Document and target projections

- Status: Accepted
- Date: 2026-09-24

## Context

Target CMSs increasingly provide hooks, functions, workflows, and AI-assisted processing. Making CourierCMS understand and maintain every customer's native target schema would expand it into a migration or automation platform and couple reliable transport to changing business models.

Target-side consumers still benefit from typed, queryable fields. Requiring every consumer to parse JSON for common filters and previews can be inefficient or awkward, especially in CMS query languages and visual administration tools.

## Decision

Every Delivery Item must retain a complete Canonical Delivery Document containing the stable CourierCMS Delivery Envelope and the full mapped payload. This document is the authoritative representation of what CourierCMS delivered.

Each target Adapter supplies or validates a stable Intake Schema. The Intake Schema stores the canonical document plus adapter-required ownership and lookup fields. It may also contain optional Projection Fields configured by the customer.

A Projection Field is deterministically derived from a path in the Canonical Delivery Document and written with it. It may duplicate canonical content for efficient querying, previews, hooks, or downstream integrations, but it cannot introduce independent content and is never authoritative. CourierCMS may overwrite it on every delivery.

Projection definitions are versioned in the Route Revision. Target schema provisioning or deployment is explicit and occurs before Route activation; a delivery Run never mutates schema.

Customer-owned target hooks, code, workflows, or AI may consume Delivery Items and create native editorial content. That Target Consumer remains outside CourierCMS's delivery success boundary.

## Consequences

- CourierCMS stays focused on faithful extraction, packaging, delivery, retry, provenance, and monitoring.
- The complete delivered content remains portable and recoverable even if projections or target consumers change.
- Common target queries and event handlers can use typed native fields without parsing JSON repeatedly.
- Projection consistency is testable because every projected value has one canonical source path.
- Schema-managed CMSs require an explicit deployment step before new projections can be activated.
- Target consumers must handle contract versions, recursion protection, and their own idempotency.

## Alternatives considered

- Map directly into native target editorial schemas: rejected because it makes CourierCMS responsible for target content modeling, workflows, and schema evolution.
- Store only generic JSON: rejected as the sole option because common target queries and hooks may need typed, indexed fields.
- Store only projected target fields: rejected because it creates a lossy, target-specific representation and multiple possible sources of truth.
- Let AI transform content inside the core delivery path: rejected because transport must remain deterministic and independently operable.
