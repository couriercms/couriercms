# ADR-0004: Create/update-only target ownership

- Status: Accepted
- Date: 2026-09-24

## Context

CourierCMS transports content into a target-controlled system. Deleting, unpublishing, or reconciling target content would expand CourierCMS into synchronization and conflict management.

## Decision

CourierCMS creates Delivery Items and updates an existing item only when it can verify ownership. CourierCMS never deletes, archives, or unpublishes target content. Source deletion, unpublish, or leaving a selection causes no destructive target action.

## Consequences

- Target CMSs control lifecycle and retention.
- The target Adapter behaviour contains no deletion callback in V0.
- Operators may see target items whose source no longer matches; this is expected.
- Ownership conflicts are terminal visible failures, never force-overwrites.

## Alternatives considered

- Configurable delete propagation: rejected because it changes the safety and product boundary.
- Best-effort overwrite by deterministic target path: rejected because it can damage customer-authored content.
