# ADR-0008: WordPress-to-Sanity prototype

- Status: Accepted
- Date: 2026-09-24

## Context

The first prototype must exercise realistic CMS selection, references, assets, events, target APIs, and differing hosting models without requiring a heavy licensed enterprise CMS environment.

## Decision

Use WordPress as the first real source and Sanity as the first real target. The use case is filtered published Blog Posts aggregated into versioned `couriercmsDelivery` documents. Develop against disposable/local environments and permit a Namecheap-hosted WordPress staging site for manual integration when prerequisites are satisfied.

Build fake source and target Adapters before live integrations. Sitecore-to-Sanity is the recommended next commercial validation.

## Consequences

- The prototype validates a self-hosted source, optional installed Connector, and cloud target.
- WordPress REST, taxonomy, revision, media, and publish behavior receive early coverage.
- Sanity validates logical Destinations without folders.
- Locale plugins, arbitrary custom fields, and complete Gutenberg semantics are deferred.

## Alternatives considered

- Sanity-to-Sanity: faster but insufficiently tests CMS differences and the Connector model.
- Sitecore-to-Sanity: commercially relevant but too much environment and API complexity before the runner is proven.
- Drupal-to-Sanity: viable alternative, but WordPress offers a simpler initial hosted/local setup.
