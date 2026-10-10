# ADR-0018: Managed Destinations and flat Delivery Items

- Status: Accepted
- Date: 2026-10-10
- Supersedes: ADR-0017

## Context

ADR-0017 represented a Destination as a stable key on a Route plus immutable
Adapter-defined placement settings in its Route Revision. That protects
delivery identity, but it does not model operator registration, validation,
availability, exclusive assignment, retirement, or safe reuse of an external
receiving scope.

Target systems also represent receiving scopes differently. A Sitecore project
may use a parent item, Sanity may use a logical document partition, and a
compatible storage target may use a bucket prefix or directory. CourierCMS needs
one management model without assuming that all targets have folders.

Operators need recognizable target item names to compare source and delivered
content quickly. Those names cannot safely provide identity because they are
editable, non-unique, and subject to target-specific restrictions.

## Decision

A Destination is a separately persisted resource beneath one target Connection.
It stores a stable CourierCMS identity, operator-facing name, bounded
Adapter-defined external scope configuration, validation state, ownership
evidence, and lifecycle state.

One Route selects exactly one Destination. One Destination may be reserved or
used by no more than one Route. Its lifecycle is:

```text
available -> reserved -> active -> retired
```

An undelivered reserved Destination may return to available. A Destination that
has accepted a Delivery Item becomes active and is never automatically released
to another Route. Detaching or archiving it retires it. Reusing the same
external scope requires explicit cleanup and validation followed by a new
Destination record; historical identity remains intact.

Validation status is independent from lifecycle: `unknown`, `valid`, or
`invalid`. A temporary validation failure must not erase assignment or ownership
history. Invalid Destinations cannot be newly reserved or receive delivery and
may return to valid after successful revalidation.

Manual creation of the external scope and registration in CourierCMS is the
default. An Adapter may optionally provide explicit provisioning. Delivery Runs
never mutate target schema.

Delivery Items are flat within a Destination. Source hierarchy may be preserved
as canonical content or metadata, but CourierCMS does not reproduce it in the
receiving scope. A target-owned consumer decides how deliveries become native
content and hierarchy.

Each Route Revision selects one canonical source field for the human-readable
Delivery Item name. The target Adapter falls back to the source item key,
sanitizes the result, and appends a stable short suffix derived from the
Delivery Item key. The readable name supports discovery but is not identity or
ownership evidence. CourierCMS continues to use the immutable Delivery Item key
and the Adapter-returned target reference for create-or-update behavior.

A Destination may be implemented by a CMS or a compatible content-delivery
store only when its target Adapter satisfies canonical-document retention,
ownership, idempotent create-or-update, lookup, and retry semantics. This does
not admit generic webhooks or arbitrary automation endpoints.

## Consequences

- Destination registration, validation, assignment, and retirement require a
  first-class persisted model and operator UI.
- Routes reference Destinations instead of owning opaque Destination keys and
  placement settings directly.
- A database constraint must enforce exclusive assignment.
- Route deletion or reassignment never deletes target content.
- Moving an active Route requires a new Destination and full delivery; the old
  Destination is retired.
- Runs pin the Destination used for execution, and target bindings are retained
  per Route Item and Destination so a move never overwrites historical target
  references.
- Target Adapters declare registration fields and naming constraints without
  exposing target vocabulary in platform LiveViews.
- Target references remain opaque execution state in the Route Item ledger.
- Existing Route-owned Destination settings require a clean-baseline schema
  update before the initial public release.

## Alternatives considered

- Keep Destination as Route Revision JSON: rejected because availability,
  validation, assignment, and retirement are durable domain state.
- Allow automatic reuse after Route deletion: rejected because delivered items
  and ownership markers remain in the external scope.
- Recreate source hierarchy: rejected because it couples transport to native
  target modeling and complicates independent item delivery.
- Use opaque hashes as visible names: rejected because operators need to locate
  and compare content quickly.
- Use titles or paths as identity: rejected because they change, collide, and
  follow target-specific rules.
