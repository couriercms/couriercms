# ADR-0003: Versioned Delivery Item identity

- Status: Superseded by ADR-0010
- Date: 2026-09-24

The historical **Target consumer** wording below is also retired by
[ADR-0020](0020-delivery-boundary-content-bundles-and-assets.md). It does not
identify a CourierCMS component.

## Context

CMSs represent languages and versions differently. The target must be free to retain, consume, or discard each delivered variant without CourierCMS imposing native target modeling.

## Decision

This ADR recorded the original revision-addressed model. ADR-0010 replaces it with one mutable Delivery Item per selected root item and locale.

Replaying the same logical key creates no duplicate. A new locale or revision creates a new Delivery Item. Initial imports default to the latest published revision per selected locale; full revision history is opt-in.

## Consequences

- Target consumers receive durable versioned inputs.
- Save-event volume must be controlled through Route policy, debounce, and content hashes.
- Adapters must normalize stable locale and revision identifiers or declare limitations.
- The target owns retention of accumulated versions.

## Alternatives considered

- One mutable target item per source item: rejected because it hides source revision history and makes event replay less explicit.
- One item containing every locale/version: rejected because partial updates, identity, retries, and consumer logic become more complex.
