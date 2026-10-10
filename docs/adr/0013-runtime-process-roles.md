# ADR-0013: Runtime process roles

- Status: Accepted
- Date: 2026-09-24

## Context

Small self-hosted installations should remain simple, while larger installations need to scale HTTP traffic and CMS delivery work independently. Oban already coordinates durable work through PostgreSQL, but starting every queue and scheduler on every CourierCMS process makes operational ownership implicit. LiveView progress delivered only through local PubSub would also become stale when a worker runs on another unclustered machine.

## Decision

One CourierCMS release supports three runtime roles selected by `COURIERCMS_ROLE`:

- `all` starts the web endpoint and all configured Oban queues; it remains the default.
- `web` serves Phoenix and retains a queue-less Oban instance for inserting jobs.
- `worker` executes selected Oban queues without starting the HTTP listener.

`COURIERCMS_QUEUES` may allocate allowlisted queues and concurrency per executing node. Worker-only nodes do not run the periodic scheduler unless explicitly designated with `COURIERCMS_SCHEDULER_ENABLED=true`. Combined `all` nodes preserve the existing scheduler default. Oban's configurable shutdown grace period is used to drain active work during normal termination.

All roles share PostgreSQL and the same installation identity and cryptographic configuration. PubSub remains the fast progress path; open Route views and active Run views also refresh durable database state so correctness does not depend on Erlang node clustering.

## Consequences

- Existing local installations keep the same behavior without new configuration.
- Web and delivery capacity can be scaled independently with the same release artifact.
- Operators must ensure one worker owns periodic scheduling in a split deployment.
- Queue concurrency is multiplied by the number of worker nodes and must respect database and CMS API limits.
- Database polling adds a small bounded query load only while an observed Run is active.
- Fly.io, Kubernetes, autoscaling policies, and release packaging remain deployment-specific future work.

## Alternatives considered

- Separate web and worker applications: rejected because it duplicates release and domain configuration without adding a useful product boundary.
- Require Erlang clustering for progress: rejected because durable operational status should remain visible even when clustering is unavailable.
- Run every queue and scheduler on every node: rejected because resource allocation and periodic-dispatch ownership become difficult to operate explicitly.
