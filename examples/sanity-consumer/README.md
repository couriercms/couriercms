# Sanity target-side integration example

This optional example installs the read-only `couriercmsDelivery` intake schema
and `couriercmsAsset` ownership-receipt schema used by the official Sanity
target extension. It demonstrates the
boundary after CourierCMS delivery. A Sanity project may independently observe
the delivered documents or add its own hooks and functions. CourierCMS does not
trigger, monitor, or include those actions in delivery status.

Every intake document retains the complete Canonical Delivery Document in
`deliveryJson`. Projection fields are derived conveniences and are not a second
source of truth. CourierCMS owns and updates intake documents; it never deletes
them or writes customer-native document types. Asset receipts associate a
Destination and Route with an uploaded Sanity image without claiming exclusive
ownership of Sanity's content-addressed image document.

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

If you independently add a Sanity Function or webhook that uses intake
documents, give any resulting native documents ordinary Sanity-generated IDs
and store the CourierCMS delivery key in an explicit field for lookup and
idempotency. Guard event handlers against recursion. Their success or failure
is not reported to CourierCMS.
