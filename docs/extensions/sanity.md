# Sanity Target Adapter

The official Sanity target extension is implemented and covered by stubbed HTTP
contract tests. Live-project verification is an operator responsibility.

The Adapter writes only `couriercmsDelivery` destination documents. It does not
create native Sanity posts, publish editorial content, delete documents, or
manage downstream workflows.

## Connection settings

- Organization ID: optional administrative metadata
- Project ID: required
- Dataset: required; public and private datasets are supported
- Project robot token: required and encrypted at rest
- API version: pinned to `v2026-09-24`

Use a dedicated project robot token with read/write access. Do not use a
personal CLI token in a long-running CourierCMS installation.

## Delivery model

Each selected source item and locale produces one `couriercmsDelivery` document.
Later source revisions patch that same document. The Adapter:

1. Queries by `destinationId` and `couriercmsKey`.
2. Creates a CourierCMS-owned intake document with a deterministic `_id` derived
   from that Destination-and-item identity when no delivery exists.
3. Verifies `installationId`, `routeId`, `destinationId`, and `couriercmsKey`
   before an update.
4. Patches only the CourierCMS destination fields.
5. Returns the Sanity `_id` for the Delivery Binding.

The complete Canonical Delivery Document is stored as JSON text in a dedicated
field. Selected system fields remain independently queryable for identity,
ownership, Studio structure, and operations. The JSON document is always the
source of truth and includes both the CourierCMS envelope and mapped payload.

The Intake Schema may also declare optional typed Projection Fields such as a
title, slug, publication date, or classification. CourierCMS derives each configured
projection from a canonical document path and writes it with the canonical JSON.
These fields exist for GROQ queries, previews, hooks, and optional target-side integrations;
they are not native editorial content and must not contain independent values.

Sanity schemas are code-managed. Adding or changing Projection Fields therefore
requires an explicit Studio schema deployment followed by CourierCMS Destination
validation. A delivery Run never changes the Sanity schema.

CourierCMS never deletes a Sanity document.

## Current asset behavior

When the mapped payload includes a public HTTPS featured-image URL, Sanity's
from-URL Assets API fetches it and CourierCMS stores the resulting asset reference
in `featuredImage`. The original descriptor remains in the canonical document.

V0 does not fetch assets that require WordPress cookies or authorization
headers. A failed asset upload fails that Delivery Item visibly and may retry if
Sanity reports a transient failure.

This operation currently occurs inside the parent Delivery Item attempt. The
platform's first-class Delivery Asset pipeline is available, but the Sanity
Adapter does not yet advertise its optional callbacks. Adopting that contract
will give Sanity assets independent jobs, retries, and target bindings without
changing the Adapter's responsibility to return a usable asset reference.

## Studio package

The standalone package in `examples/sanity-consumer` (a historical directory
name) defines the read-only Intake Schema and Studio structure. It is a
target-side integration example, not a CourierCMS runtime component. Schema
deployment is explicit and separate from
delivery; Runs never mutate target schema. The implementation stores the
complete envelope-plus-payload document in `deliveryJson`. It does not write a
payload-only compatibility field. Updates explicitly unset the former
`payloadJson` field, and Force Full Redelivery cleans existing items while
populating the canonical field without changing Delivery Item identity.

The MVP Intake Schema provides five validated projection slots:

- `projectedTitle` (`string`)
- `projectedSlug` (`string`)
- `projectedPublishedAt` (`datetime`)
- `projectedNumber` (`number`)
- `projectedBoolean` (`boolean`)

The Content Lake API does not expose the deployed Studio schema for arbitrary
field introspection. CourierCMS therefore validates projection definitions against
this shipped Intake Schema manifest. Supporting customer-defined arbitrary
projection slots requires a future explicit schema-manifest handshake.

See `examples/sanity-consumer/README.md` for deployment commands.

The deterministic `_id` is reserved for CourierCMS-owned integration records so
ambiguous retries converge safely. Target-owned native editorial documents are
ordinary Sanity content and should normally use Sanity-generated IDs.
