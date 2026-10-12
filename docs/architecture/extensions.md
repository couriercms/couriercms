# Extension Strategy

## Decision

CourierCMS uses trusted, native OTP extensions inside the modular monolith. An
extension is a precompiled OTP application package that CourierCMS discovers and
loads when the node starts. The runtime accepts Adapter and Processor components
through a small versioned SDK contract.

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
marketplace, or a language-neutral extension protocol. An Extension is still
ordinary trusted OTP code: when a demonstrated capability needs Rust or
another runtime, it may communicate with an explicitly deployed helper through
a supervised Erlang Port or another deliberate integration boundary. The V0
package contract does not bundle, install, distribute, supervise, or sandbox
such external helpers for the Extension author.

See [ADR-0015](../adr/0015-native-otp-extensions.md).

## Integration vocabulary

The terms describe different technical responsibilities:

- **Extension:** the installable CourierCMS-side OTP package.
- **Adapter:** a component in an Extension that communicates with exactly one
  external content system. It may expose source capabilities, target
  capabilities, or both.
- **Processor:** a component in an Extension that performs one bounded,
  declared, target-independent content operation.
- **CMS Connector:** optional companion code installed inside a CMS. It can
  emit events or expose a CMS-native endpoint, but is not loaded by CourierCMS.
- **Integration:** the operator-facing grouping of an Adapter, optional CMS
  Connector, documentation, and setup guidance. It is not an execution unit.
- **Transformation:** a named target-independent content conversion. Built-in
  operations execute in core; specialized work executes through an explicitly
  configured Extension Processor.

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
7. validates supported Adapter and Processor components and callbacks; and
8. registers valid components in the local registry.

An invalid package remains visible to operators with a safe load error. It must
not take down the web/admin surface or unrelated Routes. Workers do not begin
Extension-dependent jobs until discovery and registration finish.

Supported packages contain compiled artifacts, a manifest, and optional static
metadata. They cannot add Phoenix routes, LiveViews, JavaScript, database migrations, or
arbitrary Oban plugins. See [Extension package](../extensions/package-format.md).

## Version and execution safety

Clean module names are used; versions are not encoded into Elixir namespaces.
The version and checksum live in the package manifest and runtime registry.

A Run captures the exact Adapter and Processor Extension ID, component ID,
version, checksum, and SDK contract used to plan it. A retry must not silently execute with different
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

Installing an Extension is equivalent to installing a WordPress plugin or
server application code. Only owners/administrators may do it, and packages
come from a trusted source. An in-VM Extension is not sandboxed: as ordinary
OTP code it can inspect process state, call Erlang/Elixir modules available to
the VM, open network connections, access operating-system resources granted to
the CourierCMS process, or harm VM availability. The SDK describes the
supported product contract; it is not a security sandbox. The package gate and
operational policy are therefore security boundaries, not cosmetic checks.

Extensions must depend on the CourierCMS Extension SDK and an approved shared
dependency set. They must not bundle conflicting versions of core libraries.
Extensions should use the SDK HTTP and Adapter contracts for normal CMS work.
Native libraries, untrusted customer code, scheduler-blocking work, bundled
helper executables, or conflicting dependency requirements need an explicit
design and deployment review. A trusted Extension may coordinate with a
separately deployed Rust or other-language process through a supervised Port,
but that process remains part of the operator's trusted deployment and is not
managed by the current `.couriercms` package lifecycle.

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

Common small deterministic transformations are implemented in the core.
Specialized target-independent transformations use native Processor components
with the same package, registry, and gateway lifecycle as Adapters. Route
configuration selects a declared Processor using identifiers, paths, and
data-only JSON configuration; it never contains executable source code.

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
5. [complete] package the Content Processor, WordPress, and Sanity
   implementations as native Extensions;
6. [complete] add the read-only System > Extensions operator screen, lifecycle
   verification commands, and clean-VM install/upgrade/rollback drill; and
7. [complete] add deterministic package-set heartbeats, readiness/telemetry
   mismatch reporting, and multi-node compatibility tests; and
8. [complete] validate, register, invoke, and record bounded Processor
   components through the Extension Gateway.

External runtimes are not a prerequisite for extensible CMS delivery. When a
demonstrated capability requires one, document its executable provenance,
deployment, supervision, resource limits, failure behavior, upgrade
compatibility, and Local/Server support before treating it as an official
Extension dependency.
