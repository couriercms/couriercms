# Extension Development

An Extension package is profile-independent. Authors publish one package for
Local and Server; the platform supplies profile-specific storage and job
infrastructure behind the stable SDK contract. Do not branch Adapter behavior
on the release profile or depend on platform database internals.

An installed Extension is trusted OTP application code, comparable to an
installed WordPress plugin. The SDK is the supported integration contract, not
a security sandbox. Extension code can technically use capabilities available
to the CourierCMS operating-system process, so operators must install packages
only from trusted publishers.

Use native OTP code for the normal case. If a demonstrated capability requires
Rust or another runtime, the Extension may communicate with a separately
deployed helper through a supervised Erlang Port or another explicit boundary.
The current `.couriercms` format does not bundle, install, distribute, or
sandbox that helper. Its provenance, deployment, resource limits, failure
handling, upgrades, and Local/Server compatibility must be documented by the
Extension author.

This guide describes the native Extension development model. The SDK, startup
loader, and independently buildable WordPress and Sanity OTP applications are
implemented.

## Project shape

Develop an Extension as an ordinary Mix OTP application in its own project:

```text
couriercms_wordpress/
  mix.exs
  lib/
    courier_cms_extension/wordpress/application.ex
    courier_cms_extension/wordpress/source.ex
    courier_cms_extension/wordpress/client.ex
  test/
  couriercms-extension.json
```

Depend on the versioned CourierCMS Extension SDK, not the CourierCMS web application or
internal contexts. An Extension application starts only its own supervised
runtime resources. Stateless callback modules are preferred; any pools or
caches must have bounded resource use and stop cleanly with the application.

## Component contract

Each manifest component exposes a bounded SDK behaviour:

- an Adapter declares its configuration definition and source and/or target
  capabilities;
- a Processor declares one bounded, target-independent operation and validates
  its data-only configuration.

Definitions are declarative data rendered by generic CourierCMS screens. An
Extension cannot inject HTML, LiveViews, routes, JavaScript, arbitrary Oban
workers, or database migrations.

Adapter callbacks use normalized SDK values and errors. They do not receive
Ecto repositories or schemas, invoke another Adapter, advance checkpoints, or
decide Run state. Processor callbacks receive only their bounded input and
declared configuration.

Processor authoring is supported for trusted installable packages. Implement
`CourierCMS.ExtensionSDK.Processor`, declare `kind: "processor"` and the single
`processor` capability in the manifest, and provide `component/0`,
`definition/0`, `validate_config/1`, and `process/2`. `process/2` receives only
the value selected by the Route input path and the validated JSON configuration;
it returns the value written to the configured output path or a normalized,
secret-safe `AdapterError`.

Processor callbacks execute in a monitored process with a platform timeout,
but Extensions are trusted BEAM code rather than a security sandbox. Keep work
bounded and scheduler-friendly. Native libraries, untrusted code, AI calls, and
unbounded or blocking workloads require a separate architecture decision.

## Delivery Asset authoring

A source Adapter declares required media or files as `AssetDescriptor` values
inside its `ContentBundle`. Logical identity is the stable source asset key plus
variant; URLs, temporary paths, and checksums are not identity. Descriptors may
contain non-secret retrieval metadata, but must not contain credentials or an
expiring authorization token.

When the source advertises the asset capability, `read_asset/2` returns bounded,
replayable `AssetContent` chunks. CourierCMS writes the stream to
platform-controlled temporary storage, verifies declared size and checksum,
and removes the temporary file after every success or failure. The Adapter must
classify interrupted or expired authorized downloads as retryable errors and
must not put binary content in database values or job arguments.

A target advertising the asset capability implements deterministic lookup,
create, and update callbacks. It verifies CourierCMS ownership, recovers
ambiguous writes through lookup, consumes the provided stream, and returns an
opaque target reference plus matching ownership evidence. Delivery Item writes
consume that verified reference; they must not perform a second hidden upload.

Asset contract tests must cover shared logical assets, changed bytes under a
stable identity, bounded large streams, interrupted streams and cleanup,
duplicate execution, ownership conflicts, ambiguous writes, and retry of the
dependent Delivery Item.

## Target Destination contract

A target Adapter defines and validates the fields required to register one
receiving scope beneath a target Connection. Manual registration is the default;
provisioning is optional and must be an explicit operator operation.

The platform assigns a Destination exclusively to one Route and owns its
lifecycle. The Adapter must:

- validate that the external scope is reachable and compatible with its Intake
  Schema;
- create or update only flat Delivery Items within that scope;
- sanitize the configured source-derived name and append the supplied stable
  short identity suffix;
- use Destination ID plus the immutable Delivery Item key, never the readable
  name, for lookup, deterministic target identity, and duplicate recovery;
- return an opaque target reference and ownership evidence; and
- retain the complete Canonical Delivery Document.

CMS folders, document partitions, object-store prefixes, directories, and
purpose-built content API namespaces can implement this contract. Generic HTTP
actions and append-only endpoints without idempotent lookup/update do not.

## Build and package

1. Compile against the supported Elixir, OTP, and SDK versions.
2. Run the SDK conformance suite for every declared capability.
3. Build a production OTP application artifact without source or development
   dependencies.
4. Generate `couriercms-extension.json` and deterministic checksums. The supported
   SDK build task performs steps 3-4 with
   `MIX_ENV=prod mix couriercms.extension.build`.
5. Sign the package when required by deployment policy.
6. Assemble the `.couriercms` archive described in
   [Extension package format](../extensions/package-format.md).

Production CourierCMS nodes never compile `.ex` files. A compiler error or missing
dependency must be discovered in Extension CI, package verification, or a
staging CourierCMS installation—not during a production restart.

## Required tests

All Extensions require:

- manifest and compatibility validation;
- definition/schema validation;
- capability conformance tests;
- deterministic Processor configuration/input/output tests when applicable;
- secret-safe error and log tests;
- timeout, retry, rate-limit, and cancellation behavior where applicable;
- source pagination and stable identity tests for source Adapters;
- idempotency, ownership, and ambiguous-write recovery tests for targets;
- checkpoint compatibility tests across supported source upgrades; and
- startup, shutdown, and restart tests inside a representative CourierCMS release.

Live integration tests remain opt-in and use disposable CMS projects or sites.

## Processor configuration metadata

A Processor `definition/0` may expose `config_fields` so CourierCMS can render a
guided Route editor without knowing anything about the concrete Extension. The
supported presentation types are `:text`, `:integer`, `:checkbox`, and
`:json_object`. Every field declares a stable key and human-readable label and
may include a default, required marker, and description.

The metadata is a user-interface contract, not a substitute for
`validate_config/1`. The Extension must still enforce all semantic limits and
reject unknown or unsafe values. Processor configuration is stored in immutable
Route Revisions, so it must not contain credentials, tokens, or secrets.

The Route editor can add or edit a typed Processor step, reorder or remove draft
steps, and preview the complete draft against one source item. Preview executes
the same bounded Processor gateway and produces a canonical document without
writing to the Destination. Saving is a separate explicit action that creates a
Route Revision.

## Upgrade compatibility

Classify each release explicitly:

- **compatible:** existing Connection configuration, Route Revisions,
  checkpoints, and target identities remain valid;
- **requires full baseline:** source configuration remains valid but existing
  incremental checkpoints cannot be interpreted safely; or
- **breaking:** operator migration and a documented recovery procedure are
  required before activation.

Never reinterpret an opaque checkpoint or change target Delivery Item identity
silently. Do not encode the Extension version in module names; CourierCMS identifies
the installed artifact using the manifest version and checksum.

## Local development loop

Run `scripts/prepare-extensions.ps1 -IncludeFake` or
`scripts/prepare-extensions.sh --include-fake`, restart CourierCMS, and inspect
System > Extensions. Production hot reload is not a supported lifecycle.
