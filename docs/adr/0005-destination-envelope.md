# ADR-0005: Stable Destination envelope

- Status: Accepted
- Date: 2026-09-24

## Context

Target CMSs have incompatible schema and folder capabilities. Updating target editorial schemas whenever a Route mapping changes is unsafe and would make CourierCMS responsible for target content modeling.

## Decision

Deliver into a logical Route-owned Destination using a stable CourierCMS Delivery Envelope and a versioned payload contract. The payload represents one aggregated source root. Mapping changes create a new Route Revision and contract version but do not automatically mutate target schema.

Provisioning the Destination is an explicit operation. Adapters may automate it where safe or validate an installed schema/module package where schema is code-managed.

## Consequences

- Physical folders are optional Adapter implementations, not a universal contract.
- The target CMS interprets the payload and creates native content if desired.
- Payloads may remain nested even though there is one target item per root.
- Target consumers must handle declared contract versions.
- CourierCMS validates programmatic writes rather than assuming the target Studio/UI does so.

## Alternatives considered

- Directly reproduce every source node as native target content: rejected because it couples CourierCMS to target editorial design and shared-reference lifecycle.
- One scalar-flat payload: rejected because it loses arrays, component order, and semantic structure.
