# Extension Development

An Extension package is profile-independent. Authors publish one package for
Local and Server; the platform supplies profile-specific storage and job
infrastructure behind the stable SDK contract. Do not branch Adapter behavior
on the release profile or depend on platform database internals.

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
- a Processor declares its input/output contract, configuration, limits, and
  deterministic execution metadata.

Definitions are declarative data rendered by generic CourierCMS screens. An
Extension cannot inject HTML, LiveViews, routes, JavaScript, arbitrary Oban
workers, or database migrations.

Adapter callbacks use normalized SDK values and errors. They do not receive
Ecto repositories or schemas, invoke another Adapter, advance checkpoints, or
decide Run state. Processor callbacks receive only their bounded input and
declared configuration.

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
- secret-safe error and log tests;
- timeout, retry, rate-limit, and cancellation behavior where applicable;
- source pagination and stable identity tests for source Adapters;
- idempotency, ownership, and ambiguous-write recovery tests for targets;
- checkpoint compatibility tests across supported source upgrades; and
- startup, shutdown, and restart tests inside a representative CourierCMS release.

Live integration tests remain opt-in and use disposable CMS projects or sites.

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
