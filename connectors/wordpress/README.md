# CourierCMS WordPress Connector

The Connector sends small signed publish/update notifications to CourierCMS. It
does not send post content. CourierCMS re-reads the authoritative post through the
WordPress Adapter, applies the Route's collection filters, and then uses the
normal delivery pipeline.

## Install

1. From the repository root, run `scripts/package-wordpress-connector.ps1` on
   Windows or `scripts/package-wordpress-connector.sh` on macOS/Linux.
2. In WordPress, open Plugins -> Add New -> Upload Plugin.
3. Activate **CourierCMS Connector**.
4. In CourierCMS, open Connections and select **Set up publish Connector** on the
   WordPress Connection.
5. Copy the displayed webhook URL and signing secret.
6. In WordPress, open Settings -> CourierCMS Connector and save both values.

The webhook URL must be reachable from the WordPress server. A localhost URL is
not reachable from a remote WordPress host; deploy CourierCMS or use a secure
HTTPS tunnel for local testing.

## Delivery behavior

- New published posts emit canonical `content.published` events.
- Updates to published posts emit canonical `content.updated` events.
- Every request declares connector contract version `1`.
- Drafts, autosaves, revisions, pages, and other post types are ignored.
- Failed webhook calls are kept in a bounded WordPress option queue and retried
  through WP-Cron with backoff.
- The event includes identity/status metadata only, never the post body.
- CourierCMS accepts signatures only within five minutes and deduplicates event IDs.

CourierCMS accepts the previous secret for a 24-hour rotation grace period.
Copy the newly generated value into WordPress before that period expires.
