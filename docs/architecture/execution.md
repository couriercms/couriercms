# Execution Semantics

## Delivery guarantee

CourierCMS provides at-least-once delivery. Duplicate events and repeated attempts are expected; target delivery must be idempotent.

Exactly-once delivery is not claimed. CourierCMS achieves the intended user outcome through stable logical identity, target lookup/binding, ownership verification, content hashes, and idempotent create/update operations.

## Trigger normalization

Manual, schedule, polling, save, and publish triggers all enter the same execution pipeline. Triggers affect the initial work set but not delivery semantics.

- **Manual:** enumerate the Route selection or replay explicitly chosen items.
- **Scheduled/polling:** enumerate changes after a durable checkpoint.
- **Save/publish event:** validate and deduplicate the event, then evaluate the affected item against the Route selection.

Webhook requests should be authenticated and acknowledged quickly after durable receipt. Content work runs asynchronously.

## Selection semantics

A selection can return zero, one, or many root items. Common filters include content type, parent/path, category, tag, date, locale, and source state. Adapters declare supported predicates and may expose CMS-specific options.

The Route UI must support validation and a preview before activation. Relative date filters must define their evaluation semantics and timezone.

If an item no longer matches the selection, CourierCMS records or reports it as out of scope and performs no target deletion or archival.

## Planning and batching

1. Create a Run bound to one immutable Route Revision.
2. Ask the source Adapter to enumerate normalized root identities.
3. Persist one bounded source page, its Run Items, and its Oban delivery jobs in
   one database transaction.
4. Repeat from the durable cursor without retaining the full result set in memory.
5. Assemble dependencies, map, apply available transformations, validate, and
   deliver each item independently.
6. Reconcile counts and finish the Run after all terminal item states are known.

Source pages, Run item counts, and canonical document bytes have deployment
limits. A page or Run over its limit fails visibly instead of consuming
unbounded resources. Cluster-wide Connection leases constrain source and target
work independently, so adding worker machines does not multiply pressure on a
CMS beyond its configured limit. Unrelated Connections retain their own slots.

## Identity and replay

The logical Delivery Item key is:

```text
Route ID + source item key + locale key
```

The first delivery creates the target item. A later source revision updates
that same owned item. A new locale creates a separate Delivery Item.
Target-native identifiers are stored in Delivery Bindings rather than inferred
from user-editable names.

## Initial and incremental behavior

Recommended defaults:

- Initial import: latest published revision per selected locale
- Publish event: published revision represented by the event
- Save event: saved revision represented by the event
- Polling: changes since the last durable checkpoint
- Manual replay: explicit identities or current selection defaults

Transporting all historical revisions is opt-in because draft and autosave volume can be large.

## Periodic retrieval and reconciliation

`Periodic delivery` is the user-facing behavior. Admins configure its retrieval strategy, while operators see the effective strategy recorded on each Run:

- The first Run performs a Full Scan.
- The default `incremental` strategy requests changes since a valid checkpoint when the Adapter supports it.
- The `full` strategy enumerates the complete selection on every scheduled Run.
- A changed Route Revision invalidates the prior incremental baseline and forces a Full Scan.
- When incremental discovery is unavailable or its checkpoint is invalid, CourierCMS falls back to a Full Scan.
- CourierCMS performs a configurable daily, weekly, or 30-day Full Scan reconciliation even when normal scheduled Runs are incremental.

Incremental windows include a small overlap and a fixed upper boundary. Repeated identities are harmless because target delivery is idempotent. The effective strategy and fallback reason are retained in sanitized Run metadata.

## Full Scan and forced redelivery

A Full Scan enumerates every item in the current Route selection but retains normal content-hash behavior: unchanged Delivery Items are skipped.

Force Full Redelivery is a distinct manual recovery action. It enumerates every selected item and bypasses the unchanged-content skip, causing the target Adapter to create a missing Delivery Item or update an existing owned Delivery Item using its stable identity. Ownership verification remains mandatory and no target deletion, archival, or unpublishing occurs.

Use Force Full Redelivery after a Destination is rebuilt or cleared, after source content with historical modification timestamps is introduced, or when an operator intentionally needs the target to process every Delivery Item again.

## Checkpoint rule

A checkpoint advances after all discovered work before that checkpoint has been durably recorded, not necessarily fully delivered. Recorded Run Items can continue retrying after enumeration progresses. A planning failure does not advance the checkpoint.

Planner retries may enumerate an already persisted page again. Database identity
constraints make that safe: existing Run Items are reused and active delivery
jobs are not duplicated.

An adapter checkpoint is opaque to the core but must be versioned and associated with its adapter. Resetting a checkpoint is an explicit operator action and never deletes target content.

## Error taxonomy

Normalized categories:

- `authentication`
- `authorization`
- `rate_limited`
- `temporarily_unavailable`
- `timeout`
- `invalid_selection`
- `source_not_found`
- `invalid_content`
- `mapping_failed`
- `transformation_failed`
- `contract_validation_failed`
- `ownership_violation`
- `target_rejected`
- `unsupported`
- `internal`

Every error declares retryability and may carry a sanitized adapter code. Raw response bodies and payloads are not included in logs or user-facing messages.

## Retry policy

- Rate limits honor `Retry-After` or equivalent CMS guidance.
- Network timeouts and temporary unavailability retry with capped exponential backoff and jitter.
- Authentication, invalid mapping, unsupported capability, and ownership violations do not retry automatically.
- When Transformation and Processor execution is implemented, deterministic
  content errors will be terminal and explicitly classified transient failures
  may retry.
- Terminal Run Items can be manually replayed after configuration is corrected.

Retry counts belong to CourierCMS execution history even when Oban performs scheduling.

## Run outcome

- `succeeded`: all planned items succeeded or were intentionally skipped.
- `partially_succeeded`: at least one item succeeded and at least one ended in terminal failure.
- `failed`: planning/system failure prevented meaningful delivery, or all planned items failed.
- `cancelled`: an operator cancelled outstanding work; completed deliveries remain valid.

## Delivery success boundary

Delivery succeeds when the target Adapter confirms that the Delivery Item and
all required Delivery Assets were accepted into the Destination. Target hooks,
native content generation, editorial workflow, publishing, indexing, and other
post-delivery actions are outside CourierCMS. CourierCMS does not request or
track a downstream acknowledgement.

First-class Delivery Asset jobs are planned. In the current runtime, a
supported asset operation occurs within the parent Run Item attempt, and its
failure fails that Run Item visibly.

## Concurrency and ordering

- Serialize concurrent work for the same logical Delivery Item key.
- Serialization uses an expiring database lease and therefore applies across all
  worker nodes. Queue uniqueness is only an additional efficiency measure.
- Do not assume webhook order.
- Prefer the source revision's ordering metadata when the CMS provides it.
- Never let an older event overwrite a newer successful representation for the same logical source stream without an explicit replay action.
- Independent items can run concurrently within Connection rate limits.

## Cancellation

Cancellation stops new work and marks unstarted items cancelled. It does not roll back target writes or delete Delivery Items. In-flight external calls may finish and must be reconciled idempotently.

Scheduled Runs carry a unique schedule-window key. Multiple scheduler nodes may
observe a due Route, but only one Run is persisted for that Route and window.
