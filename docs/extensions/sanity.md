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

The Adapter implements the first-class Delivery Asset contract for featured
images. CourierCMS streams the source bytes through its bounded transfer layer,
uploads them to Sanity's image API in an independent asset job, and stores the
returned native image reference in `featuredImage` before writing the dependent
Delivery Item. Asset failures and retries are therefore visible independently
from item failures.

Sanity image assets are content-addressed and may be shared. CourierCMS does not
claim exclusive ownership of the native image document. It creates a
deterministic read-only `couriercmsAsset` receipt for each Destination asset
identity. The receipt records Route and Destination ownership and points to the
native image asset; it is used for safe lookup, replay, and update. CourierCMS
never deletes either record.

The Adapter never uploads an asset as a side effect of writing a Delivery Item.
A featured image is written only when the payload contains the verified target
reference produced by the independent Delivery Asset job. The
WordPress-to-Sanity path can therefore read protected WordPress media with the
Connection's Application Password and does not require Sanity to fetch a
public source URL.

## Studio package

The standalone package in `examples/sanity-consumer` defines the read-only
Delivery Item and asset-receipt schemas plus the Studio structure. It is a
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
