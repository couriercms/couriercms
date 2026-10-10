# Sanity consumer example

This optional, target-owned example installs the read-only `couriercmsDelivery`
intake schema used by the official Sanity target extension. It demonstrates the
boundary where a Sanity project can observe CourierCMS deliveries and implement
its own hooks, functions, AI, or custom code to create native editorial content.
Those downstream actions are not part of CourierCMS delivery success.

Every intake document retains the complete Canonical Delivery Document in
`deliveryJson`. Projection fields are derived conveniences and are not a second
source of truth. CourierCMS owns and updates intake documents; it never deletes
them or writes customer-native document types.

## Configure and run

Set `SANITY_STUDIO_PROJECT_ID` and, optionally, `SANITY_STUDIO_DATASET`
(`production` by default), then run:

```sh
npm ci
npm run schema:deploy
npm run dev
```

Use a dedicated project robot token with read/write access when configuring the
Sanity Connection in CourierCMS. Do not commit the token. Deploy the intake
schema before activating Routes that use projections, then use **Force full
redelivery** to populate new projection fields.

If you add a Sanity Function or webhook that turns intake documents into native
content, give native documents ordinary Sanity-generated IDs and store the
CourierCMS delivery key in an explicit field for lookup and idempotency. Guard
event handlers against recursion and keep their success/failure independent of
CourierCMS delivery acceptance.
