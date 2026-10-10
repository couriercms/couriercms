# ADR-0002: One source and one target per Route

- Status: Accepted
- Date: 2026-09-24

## Context

One source selection may need to feed several CMS targets. Each target has distinct schema, credentials, rate limits, availability, retry state, ownership, and mapping.

## Decision

A Route has exactly one source Connection and one target Connection. Its source selection may discover many root Content Items. Delivering to several targets uses several Routes.

A future Distribution or Route Group may start and present several Routes together but does not change their independent execution.

## Consequences

- Failures, retries, mappings, checkpoints, and history remain target-specific.
- One target cannot block another target's Route.
- Some configuration may be duplicated until Route cloning/grouping exists.
- Adapter interfaces remain simple and directional.

## Alternatives considered

- Multiple targets in one Route: rejected because partial status, retries, mapping revisions, and ownership become ambiguous.
