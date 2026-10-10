# ADR-0016: Authoritative source change tokens

- Status: Accepted
- Date: 2026-09-29

## Context

Full Scan and repeated event Runs may enumerate many unchanged items. Computing
the canonical content hash requires `read_root/3`, which can perform several CMS
requests to assemble bounded dependencies. A root revision or HTTP ETag is not
necessarily sufficient because referenced authors, taxonomies, components, or
assets may change independently.

## Decision

A Source Adapter may declare `authoritative_change_token`. When declared, every
enumerated identity may include a `change_token` that changes whenever any data
included in that root's aggregated Delivery Item changes.

CourierCMS may skip `read_root/3` only when the token matches the last successful
delivery, the same Route Revision produced that delivery, valid target ownership
evidence exists, and the Run is not Force Full Redelivery. Adapters that cannot
provide that guarantee omit the capability and CourierCMS retains the canonical
post-read content-hash comparison.

## Consequences

- Trustworthy tokens avoid source calls for unchanged items.
- The token is an optimization hint with strict semantics, not target identity.
- Root-only revision IDs and modification timestamps must not be advertised as
  authoritative when aggregated dependencies can change independently.
- A false authoritative declaration can suppress required delivery and is an
  Adapter conformance failure.

## Alternatives considered

- Trust every source revision key: rejected because it may not cover aggregated
  dependencies.
- Remove the canonical content hash: rejected because it remains the portable
  correctness fallback and detects mapping-visible changes.
