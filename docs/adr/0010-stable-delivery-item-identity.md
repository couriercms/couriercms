# ADR-0010: Stable Delivery Item identity

- Status: Accepted
- Date: 2026-09-24
- Supersedes: ADR-0003

## Context

CourierCMS delivers the current selected representation of content into a target
Destination. Creating a target item for every source edit accumulates revisions
and conflicts with the product's create-if-missing, update-if-existing behavior.
Revision history is already preserved in Runs and Run Items.

## Decision

One selected root item and locale produces one mutable Delivery Item per Route.
Its logical key is Route ID plus normalized source item key and locale key. The
source revision remains envelope metadata used for ordering, observability, and
audit history, but it is not part of target identity.

The first delivery creates the target item. Later source revisions update the
same owned item. A different locale produces a different Delivery Item. CourierCMS
never deletes target items.

## Consequences

- Repeated source edits do not create target duplicates.
- Run Items retain the revision processed by every attempt.
- Adapters must prevent an older event from overwriting a newer delivered
  revision during future event-driven execution.
- Existing revision-addressed bindings retain their latest target binding when
  upgraded; older target duplicates are not deleted automatically.


