# Domain Model

## Entity relationships

```text
Workspace -- Membership -- User
    |
    +-- Extension/component definition
    |
    +-- Connection (source or target usage)
            |
            +-- Destination -- exclusive Route assignment
            |
            +-- Route -- current Route Revision
                    |
                    +-- Route Revision -- Run -- Run Item
                    |                       |
                    |                       +-- attempts/errors
                    |
                    +-- Route Item -- source/locale delivery identity
                    |       |
                    |       +-- Delivery Binding -- Destination target reference
                    |
                    +-- Checkpoint
```

## Initial persisted entities

### users, workspaces, and workspace_memberships

`users` hold global login identity. `workspaces` are the authorization and data
ownership boundary. `workspace_memberships` associate a user with a Workspace
using the `owner`, `admin`, `operator`, or `viewer` role and the `invited`,
`active`, or `blocked` status.

V0 creates one default Workspace and has no workspace switcher. Domain records
still require a Workspace so a future hosted deployment does not need to retrofit
its fundamental isolation boundary. Users and Memberships are retained for audit
history instead of being deleted.

### connections

- `id`
- `workspace_id`
- `name`
- stable Extension ID and Adapter component ID
- `endpoint`
- `settings`
- encrypted credential fields or secret reference
- capability snapshot
- enabled state
- last connection-test result and timestamp

Secrets must not be embedded in general settings JSON.

### routes

- `id`
- `workspace_id`
- `name`
- `source_connection_id`
- `target_connection_id`
- `current_revision_id`
- enabled state
- `current_destination_id`
- timestamps

A Route name can change. Route identity and Destination ownership must not depend on the name.

### destinations

- `id`, the stable CourierCMS Destination identity
- `workspace_id`
- `target_connection_id`
- operator-facing name
- Adapter-defined external scope settings
- lifecycle status: available, reserved, active, or retired
- independent validation status: unknown, valid, or invalid
- owning Route ID while reserved, active, or historically retired
- ownership evidence and last validation result
- first delivery and retirement timestamps
- timestamps

The target Connection determines which target Adapter validates and uses a
Destination. A database constraint prevents more than one Route from reserving
or activating the same Destination. An external scope that contained delivered
items is retired rather than silently released for another Route. Its owning
Route link remains as history.

### route_revisions

- `id`
- `route_id`
- sequential revision number
- source and target Extension/component IDs
- source selection
- aggregation rules
- mapping definition
- delivery contract and version
- target Projection Field definitions
- Delivery Item naming field and other immutable delivery presentation settings
- transformation/processor configuration
- trigger execution settings
- checksum
- created timestamp and actor

A revision becomes immutable when referenced by a Run.

### runs

- `id`
- `route_id`
- `route_revision_id`
- `destination_id` used by this execution
- `initiated_by_user_id` for manual Runs
- trigger kind and trigger metadata
- status
- started/completed timestamps
- discovered, succeeded, failed, retrying, and skipped counts
- cancellation metadata
- checkpoint before/after
- source and target Extension/component IDs, versions, package checksums, and
  SDK contract versions and runtimes actually used
- ordered Processor artifact evidence (empty until a Route uses Processors)

Trigger metadata must be sanitized and must not contain credentials or complete payloads.

Captured Extension artifact identity is immutable execution evidence. A retry
must not resolve to a different version/checksum silently.

Runs created before artifact persistence may have no evidence. If such a Run is
unfinished, CourierCMS captures the currently installed artifacts under a database
lock before allowing it to resume. Completed historical Runs remain empty rather
than claiming unobserved evidence.

### run_items

- `id`
- `run_id`
- normalized source identity
- `route_item_id`, nullable until resolved
- planned target operation
- status
- attempt count
- error category and safe summary
- timing
- content hash

Large payloads are not stored in Oban arguments. Payload retention, if introduced, requires a separate security and storage decision.

### route_items

- `id`
- `route_id`
- source item key
- locale key
- source revision key
- last authoritative source change token, when supported
- last Route Revision used for delivery
- latest authoritative source state
- current logical delivery state

Unique logical key:

```text
route_id + source_item_key + locale_key
```

### delivery_bindings

- `id`
- `route_item_id`
- `destination_id`
- opaque target reference
- ownership marker/evidence
- last content hash
- last successful Run ID and Route Revision ID
- last delivered timestamp
- state

Unique target-binding key:

```text
route_item_id + destination_id
```

Separating logical Route Items from target bindings allows an explicit Route
move to a new Destination without overwriting the old target reference or audit
history. Runs pin their Destination, and a move schedules a full delivery that
creates or updates the bindings for the new Destination.

### checkpoints

- `id`
- `route_id`
- source connection and stable Extension/Adapter component identity
- opaque adapter value
- last successful advancement time
- last Full Scan time
- associated Run

### inbound_events

- `id`
- source Connection
- adapter event key
- event kind
- received timestamp
- authentication result
- processing status
- safe normalized identity
- payload checksum

Raw event payload retention should be short and opt-in.

## Value objects

- `SourceIdentity`: item key, locale key, revision key, state, optional authoritative change token
- `Selection`: types, scopes, predicates, locales, state policy
- `AdapterError`: category, retryability, safe message, details
- `AssetDescriptor`: source identity, media type, filename, checksum, retrieval handle
- `DeliveryEnvelope`: CourierCMS and source provenance metadata
- `DeliveryPayload`: validated value conforming to a Delivery Contract
- `CanonicalDeliveryDocument`: complete authoritative envelope and payload JSON
- `ProjectionDefinition`: target field, canonical document path, and allowlisted value type
- `DeliveryItemName`: readable source-derived name plus deterministic short suffix

## State machines

Run:

```text
queued -> planning -> running -> succeeded
                           |--> partially_succeeded
                           |--> failed
                           |--> cancelled
```

Run Item:

```text
pending -> processing -> succeeded
                    |--> retrying -> processing
                    |--> failed
                    |--> skipped
                    |--> cancelled
```

`skipped` requires a reason such as unchanged hash or duplicate event. A content failure does not automatically fail unrelated Run Items.

## Non-entities

- A source folder is selection scope, not a single Delivery Item.
- Referenced authors, taxonomies, and components are graph nodes and usually become nested payload data, not independent Delivery Items.
- Oban jobs are execution machinery, not the source of record for Runs.
- Source folders and paths are canonical metadata, not target Destination
  hierarchy. Delivery Items are flat within a Destination.
