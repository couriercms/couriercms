# ADR-0006: At-least-once execution

- Status: Accepted
- Date: 2026-09-24

## Context

CMS APIs, networks, webhooks, and workers can fail after either side has changed state. Exactly-once claims cannot be made reliably across these boundaries.

## Decision

CourierCMS provides at-least-once execution with idempotent target behavior. Durable identity, Route Item bindings, ownership metadata, hashes, uniqueness constraints, serialized work per logical key, and recovery lookup handle duplicates and ambiguous outcomes.

## Consequences

- Webhooks and jobs may be repeated safely.
- Target Adapters must support find/reconcile behavior.
- Checkpoints advance only after work is durably accounted for.
- Operators see retries and terminal item failures independently.
- Delivery success ends at Destination acceptance.

## Alternatives considered

- Exactly once: rejected as an inaccurate distributed-systems guarantee.
- At most once: rejected because transient failure could silently lose content.
