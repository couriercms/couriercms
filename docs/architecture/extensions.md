# Extension Strategy

## Decision

CourierCMS uses trusted, native OTP extensions inside the modular monolith. An
extension is a precompiled OTP application package that CourierCMS discovers and
loads when the node starts. The current runtime accepts Adapter components
through a small versioned SDK contract. Processor components are an accepted
extension of that model but are not yet accepted or executed by the loader.

This is not a microservice design. Extensions execute in the CourierCMS BEAM VM and
are called through normal Elixir modules. PostgreSQL and Oban remain the durable
execution foundation.

The first implementation intentionally supports:

- one installed version of an Extension ID per CourierCMS installation;
- startup loading only;
- administrator-managed local packages;
- restart-based installation, upgrade, and removal; and
- trusted precompiled BEAM code only.

It intentionally does not support hot reload, multiple active versions,
runtime compilation of source files, automatic cluster distribution, a public
marketplace, Ports, sidecars, or a language-neutral extension protocol.

See [ADR-0015](../adr/0015-native-otp-extensions.md).

## Integration vocabulary

The terms describe different technical responsibilities:

- **Extension:** the installable CourierCMS-side OTP package.
- **Adapter:** a component in an Extension that communicates with exactly one
  external content system. It may expose source capabilities, target
  capabilities, or both.
- **Processor:** a planned component in an Extension that performs one bounded,
  declared, target-independent content operation.
- **CMS Connector:** optional companion code installed inside a CMS. It can
  emit events or expose a CMS-native endpoint, but is not loaded by CourierCMS.
- **Integration:** the operator-facing grouping of an Adapter, optional CMS
  Connector, documentation, and setup guidance. It is not an execution unit.
- **Transformation:** a named target-independent content conversion. A future
  Transformation may invoke an Extension Processor from a Route Revision.

An Extension may contain several related components when they share ownership,
dependencies, and release lifecycle. Reusable Processors may instead be
independent Extensions. The execution engine resolves and calls each component
through its declared contract. Adapters never call other Adapters or invoke a
Processor directly.

## Runtime model

```text
Route Revision / Connection
        |
stable Extension ID + Component ID
        |
Extension Gateway
        |
node-local Component Registry (ETS)
        |
loaded OTP application module
        |
source CMS, target CMS, or bounded processing
```

The registry is a node-local lookup table, not shared infrastructure. It maps a
stable `{extension_id, component_id}` to the loaded module, extension version,
package checksum, capabilities, and contract version. The gateway resolves the
identifier and invokes only approved callbacks. Core execution and LiveView
code must not directly reference WordPress, Sanity, or another Extension module.

The filesystem contains installed code. The configured database contains Connections,
Routes, immutable Route Revisions, Runs, and the Extension identity used by
those records. ETS contains only the rebuildable runtime lookup table.

## Package and startup lifecycle

Administrators place `.couriercms` packages in the configured extensions directory
and restart the CourierCMS node. At boot, the Extension loader:

1. discovers packages without following unsafe paths or links;
2. validates manifest structure, checksum/signature policy, and uniqueness;
3. validates CourierCMS SDK, CourierCMS release, Elixir, and OTP compatibility;
4. extracts into a version/checksum-specific immutable runtime directory;
5. adds the package `ebin` directory to the code path;
6. loads and starts the OTP application as `:temporary`;
7. validates supported Adapter components and callbacks; and
8. registers valid components in the local registry.

An invalid package remains visible to operators with a safe load error. It must
not take down the web/admin surface or unrelated Routes. Workers do not begin
Extension-dependent jobs until discovery and registration finish.

Packages containing Processor components are rejected until Processor runtime
support is implemented. Supported packages contain compiled artifacts, a
manifest, and optional static metadata.
They cannot add Phoenix routes, LiveViews, JavaScript, database migrations, or
arbitrary Oban plugins. See [Extension package](../extensions/package-format.md).

## Version and execution safety

Clean module names are used; versions are not encoded into Elixir namespaces.
The version and checksum live in the package manifest and runtime registry.

A Run captures the exact Adapter Extension ID, component ID, version, checksum,
and SDK contract used to plan it. Future Processor execution will capture the
same evidence. A retry must not silently execute with different
Extension code. If the recorded artifact is no longer installed, the work is
blocked with an explicit compatibility error. An operator either restores the
old package or intentionally supersedes/replays the work under a new Run.

Because only one version is installed at a time, the normal upgrade procedure
is to pause affected Routes, let affected jobs drain, replace the package
atomically, restart the node, verify the Extension, and resume the Routes. This
is a deliberate simplicity tradeoff for an infrequent administrative action.

An Adapter upgrade declares checkpoint compatibility. An incompatible source
upgrade establishes a new Full Scan baseline. A target upgrade must preserve
Delivery Item identity and ownership semantics or provide an explicit recovery
procedure.

See [Extension management](../operations/extension-management.md).

## Trust and dependency boundary

Installing an Extension is equivalent to installing server application code.
Only owners/administrators may do it, and packages come from a trusted source.
An in-VM Extension is not sandboxed: it can crash schedulers, inspect process
state, and call any dependency available in the VM. The package gate and
operational policy are therefore security boundaries, not cosmetic checks.

Extensions must depend on the CourierCMS Extension SDK and an approved shared
dependency set. They must not bundle conflicting versions of core libraries.
Native libraries, untrusted customer code, scheduler-blocking work, or
conflicting dependency requirements need a separate architecture decision; the
initial Extension system does not solve them with Ports.

Extensions receive configuration and credentials through gateway callback
arguments. They do not receive direct PostgreSQL access, the vault root key, or
unrelated Connection credentials, and they do not own core database tables.

## Multiple nodes

Every web or worker node that can validate or execute an Extension component
must have the same package version and checksum. Each node independently loads
the package and builds its own ETS registry. PostgreSQL remains the shared
source of truth for configured identifiers and captured execution metadata.

Each fresh node heartbeat publishes a deterministic fingerprint and
content-free list of its registered Extension artifacts. CourierCMS compares those
snapshots through readiness, telemetry, and System > Extensions. The heartbeat
is diagnostic coordination, not remote dispatch: workers still resolve local
modules through ETS and validate every Run's pinned artifact before execution.

The initial system does not distribute packages. Operators copy and verify the
same package on every eligible node. With the one-version rule, affected Routes
are paused and drained while nodes are upgraded. Unrelated Routes and the web
surface may remain available.

## Transformation policy

Common small deterministic transformations may remain in the core. Specialized
target-independent transformations are planned as native Processor components
using the same package, registry, and gateway lifecycle as Adapters. When
implemented, Route configuration will select a declared Processor and will
never contain executable source code.

Target-native content modeling, publishing, editorial policy, rewriting,
translation, embeddings, and AI orchestration are outside CourierCMS. The
target environment may implement them independently after delivery.

## Implementation sequence

The native runtime and initial Adapter extraction are implemented. Continue
without changing delivery semantics:

1. [complete] define the Extension SDK, manifest, and component contracts;
2. [complete] add the local registry and Extension Gateway and remove
   CMS-specific dispatch from core code;
3. [complete] add package discovery, validation, and startup loading;
4. [complete] persist stable component identity and enforce exact Run artifact
   evidence;
5. [complete] package the existing WordPress and Sanity implementations as
   native Extensions;
6. [complete] add the read-only System > Extensions operator screen, lifecycle
   verification commands, and clean-VM install/upgrade/rollback drill; and
7. [complete] add deterministic package-set heartbeats, readiness/telemetry
   mismatch reporting, and multi-node compatibility tests; and
8. [planned] validate, register, invoke, and record bounded Processor
   components through the Extension Gateway.

External runtimes can be considered later only for a demonstrated requirement
and require a new ADR. They are not a prerequisite for extensible CMS delivery.
