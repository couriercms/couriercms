# Architecture Decision Records

ADRs record durable decisions and their consequences. They are immutable history after acceptance; supersede an ADR with a new one rather than rewriting its decision.

## Status values

- `Proposed`
- `Accepted`
- `Deprecated`
- `Superseded by ADR-NNNN`

## Index

- [ADR-0001: Modular Phoenix monolith](0001-modular-phoenix-monolith.md)
- [ADR-0002: One source and one target per Route](0002-route-cardinality.md)
- [ADR-0003: Versioned Delivery Item identity](0003-delivery-item-identity.md)
- [ADR-0004: Create/update-only target ownership](0004-create-update-only.md)
- [ADR-0005: Stable Destination envelope](0005-destination-envelope.md)
- [ADR-0006: At-least-once execution](0006-at-least-once-execution.md)
- [ADR-0007: Adapter and Connector separation](0007-adapter-connector-separation.md)
- [ADR-0008: WordPress-to-Sanity prototype](0008-wordpress-sanity-prototype.md)
- [ADR-0009: Invite-only authentication and workspace authorization](0009-invite-only-auth-and-workspaces.md)
- [ADR-0010: Stable Delivery Item identity](0010-stable-delivery-item-identity.md)
- [ADR-0011: Canonical Delivery Document and target projections](0011-canonical-delivery-document-and-projections.md)
- [ADR-0012: Transformation ownership and extension boundary](0012-transformation-ownership-and-extension-boundary.md)
- [ADR-0013: Runtime process roles](0013-runtime-process-roles.md)
- [ADR-0014: Crash-safe bounded execution](0014-crash-safe-bounded-execution.md)
- [ADR-0015: Native OTP extensions loaded at startup](0015-native-otp-extensions.md)
- [ADR-0016: Authoritative source change tokens](0016-authoritative-source-change-tokens.md)
- [ADR-0017: Route-owned Destination settings](0017-route-owned-destination-settings.md) — superseded
- [ADR-0018: Managed Destinations and flat Delivery Items](0018-managed-destinations-and-flat-delivery-items.md)

## Template

```md
# ADR-NNNN: Title

- Status: Proposed
- Date: YYYY-MM-DD

## Context

## Decision

## Consequences

## Alternatives considered
```
