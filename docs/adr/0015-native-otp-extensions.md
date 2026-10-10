# ADR-0015: Native OTP extensions loaded at startup

- Status: Accepted
- Date: 2026-09-25

## Context

CourierCMS must allow administrators to add CMS-specific Adapters and bounded
Processors without rebuilding the core Phoenix release. It must remain a simple
self-hosted modular monolith, preserve durable delivery through restarts, and
avoid making operators deploy and secure a collection of network services.

Ports and external services provide language and process isolation, but add a
second lifecycle, IPC protocol, credentials, health model, and distributed
failure modes. Runtime source compilation and hot code replacement make package
validation, dependency compatibility, and recovery harder than the expected
infrequent Extension installation warrants.

## Decision

CourierCMS will support trusted, precompiled OTP Extension applications loaded into
the CourierCMS VM at node startup.

- One version of an Extension ID may be installed in an installation at a time.
- Administrators place packages in a configured local directory and restart the
  node to install, upgrade, or remove them.
- Packages contain a manifest, compiled BEAM application, checksum, and optional
  signature. Production nodes do not compile Extension source.
- A versioned Extension SDK defines Adapter and Processor component behaviours,
  value types, declarative definitions, and normalized errors.
- A node-local ETS registry maps stable Extension/component IDs to validated
  modules and artifact metadata. A gateway performs all dynamic resolution.
- PostgreSQL stores configuration references and captures the exact Extension
  version/checksum used by each Run; ETS is disposable runtime state.
- Extensions cannot inject web UI, routes, database migrations, or arbitrary
  workflow code.
- Extensions are trusted server code, not sandboxed tenant code.
- Multi-node installations provision the identical package on each eligible
  node; initial CourierCMS does not distribute packages automatically.
- Hot reload, side-by-side versions, Ports, sidecars, remote workers, and a
  language-neutral protocol are outside this decision.

Affected Routes are paused and drained before an upgrade. Jobs must never
silently resume using an artifact different from the version/checksum captured
for their Run.

## Consequences

- CourierCMS remains one application, one database, and one operational model.
- Native calls preserve simple debugging and avoid serialization/IPC overhead.
- Infrequent upgrades require a controlled restart, which is acceptable for the
  intended self-hosted installations.
- Extension authors must use compatible Elixir/OTP/SDK and shared dependency
  versions.
- A faulty Extension can affect the VM, so trust, package verification,
  conformance tests, timeouts, and resource limits are mandatory.
- Zero-downtime core deployment remains possible with multiple nodes, but an
  affected Route pauses during a one-version Extension upgrade unless a future
  ADR adds stronger version coexistence.

## Supersedes

This ADR supersedes only the Extension-runtime portions of:

- ADR-0001's deferral to an external Adapter protocol;
- ADR-0007's requirement to rebuild the CourierCMS release for trusted Adapters; and
- ADR-0012's out-of-process External Processor plan and rejection of packaged
  BEAM Extensions.

The modular-monolith decision, Adapter/Connector separation, deterministic
Transformation boundary, and target ownership rules remain in force.

## Alternatives considered

- **Compile every Adapter into the core release:** operationally simple but
  prevents administrator-installed integrations and couples release cadence.
- **Hot-load source or replace modules at runtime:** avoids restarts but makes
  partial activation, dependency changes, rollback, and in-flight version
  semantics substantially harder.
- **Multiple namespaced Extension versions:** supports side-by-side Runs but
  leaks versioning into module names and package design for an infrequent need.
- **Ports or sidecar services:** useful for isolation or other languages, but
  rejected as the default because they add an unnecessary distributed runtime.
- **Remote microservices:** rejected because they contradict the self-hosted
  modular-monolith operational goal.
