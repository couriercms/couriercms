# Connector authoring

Connectors are installed in an external content system and are not CourierCMS
runtime Extensions. A connector sends the same versioned canonical event
contract regardless of where CourierCMS runs. Server exposes connector ingress;
the initial Local profile does not, so Local workflows use manual Runs,
polling, or schedules while the application is open. There are no separate
Local and Server connector codebases.

A connector runs inside an external content system. It is not a CourierCMS
runtime extension and must never be loaded by the extension registry.

Use a connector only when CMS-native code adds value, such as authenticated
publish events or an optimized internal endpoint. Keep the payload small and
identity-oriented; CourierCMS should re-read authoritative content through the
source extension. Treat delivery as duplicated, delayed, and out of order.

Connector requirements:

- document its supported CMS/runtime versions;
- authenticate requests and support secret rotation;
- use bounded queues, timeouts, retries, and payload sizes;
- omit credentials and content bodies from logs;
- preserve a stable external event ID for deduplication;
- remain independently packaged and versioned; and
- test without requiring a production CourierCMS installation.

## Canonical event contract

Connectors translate CMS-native hooks into the same platform-owned endpoint:

```text
POST /api/connectors/:connection_id/events
X-CourierCMS-Timestamp: <unix-seconds>
X-CourierCMS-Signature: sha256=<hex-hmac>
```

```json
{
  "contract_version": 1,
  "event_id": "stable-event-id",
  "event": "content.published",
  "source_item_id": "123",
  "source_modified_at": "2026-10-05T18:00:00Z"
}
```

`contract_version` is required. CourierCMS rejects unsupported versions with an
`unsupported_contract_version` response that lists the supported versions.
`event` is `content.published` or `content.updated` in contract version 1.
`source_item_id` is the source Adapter's stable item key. The modified timestamp
is optional, but when present it must be ISO 8601. Sign the exact request body as
`HMAC-SHA256(secret, timestamp + "." + body)`. CourierCMS validates the
Connection's declared connector capability, accepts the current or grace-period
secret, enforces a five-minute timestamp window, and deduplicates by Connection
and `event_id`.

The core does not interpret CMS-native event names or fields. Translation from
WordPress hooks, Drupal events, or another host belongs in that host's Connector.

The [WordPress connector](../../connectors/wordpress/README.md) is the reference
implementation. Its generated ZIP belongs under `.local/packages/`, not Git.
