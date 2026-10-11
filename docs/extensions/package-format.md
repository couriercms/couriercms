# Native Extension Package

This document defines the package format for trusted CourierCMS OTP Extensions.
CourierCMS validates and loads these packages at node startup. Fields may only
change through a versioned contract update before the first stable SDK release.

## Archive layout

An Extension is distributed as a `.couriercms` archive containing one precompiled
OTP application and its manifest:

```text
couriercms_wordpress-1.0.0.couriercms
  couriercms-extension.json
  lib/couriercms_wordpress-1.0.0/ebin/*.beam
  lib/couriercms_wordpress-1.0.0/priv/**
  CHECKSUMS
  SIGNATURE                 # required when deployment policy enables signing
```

Source files, build tooling, dependency caches, database migrations, web routes,
and frontend assets are not package entry points. Archives must not contain
absolute paths, parent traversal, symbolic links, or duplicate normalized paths.

## Manifest

The manifest is declarative JSON. A representative shape is:

```json
{
  "manifestVersion": 1,
  "extensionId": "org.couriercms.wordpress",
  "name": "WordPress",
  "version": "1.0.0",
  "otpApplication": "couriercms_wordpress",
  "sdkRequirement": ">= 1.0.0 and < 2.0.0",
  "couriercmsRequirement": ">= 0.1.0 and < 1.0.0",
  "elixirRequirement": "~> 1.20",
  "otpRequirement": ">= 29.0.0 and < 30.0.0",
  "components": [
    {
      "id": "wordpress",
      "kind": "adapter",
      "module": "CourierCMSExtension.WordPress.Adapter",
      "capabilities": ["source", "incremental_changes", "publish_events"]
    }
  ]
}
```

Stable identifiers are lowercase reverse-domain or similarly collision-resistant
strings. A component ID is stable across compatible package upgrades. Version
numbers use semantic versioning. Module names remain clean and do not contain
the package version.

The manifest is descriptive, not executable UI. Connection fields, selection
fields, capabilities, limits, and help text are returned through bounded SDK
definitions after the application is loaded.

## Validation and activation

Before adding any package code to the VM, the loader validates:

- archive safety and configured compressed/uncompressed size limits;
- manifest schema and supported manifest version;
- Extension ID, version, application name, and component uniqueness;
- package checksum and configured signature/trust policy;
- SDK, CourierCMS, Elixir, and OTP compatibility;
- only one installed version for each Extension ID; and
- absence of forbidden migrations, application replacements, and module-name
  collisions with CourierCMS or another active Extension.

After loading, the gateway validates declared callbacks, definitions,
capabilities, and identifier consistency before registration. A package with
the same Extension ID and version but a different checksum is a different
artifact and is rejected unless explicitly installed as an upgrade.

`CHECKSUMS` is mandatory. It contains one lowercase SHA-256 digest, two spaces,
and the canonical archive path per line, sorted by the package builder. It must
cover every regular file except `CHECKSUMS` and `SIGNATURE`, with no missing or
extra paths:

```text
7b3...f91  couriercms-extension.json
0c1...a22  lib/couriercms_wordpress-1.0.0/ebin/couriercms_wordpress.app
```

When present, `SIGNATURE` is JSON and signs the exact `CHECKSUMS` bytes using
Ed25519:

```json
{
  "algorithm": "ed25519",
  "keyId": "production-2026",
  "signature": "base64-signature"
}
```

`COURIERCMS_EXTENSION_SIGNATURE_POLICY=required` rejects unsigned packages.
`COURIERCMS_EXTENSION_TRUSTED_KEYS` is a comma-separated list of
`keyId:base64-public-key` entries. An invalid or untrusted signature is always
rejected, including when signatures are optional.

## Filesystem rules

`COURIERCMS_EXTENSIONS_PATH` identifies the read-only active package directory in
production. Keep staging files and backups outside it. Copy a new package to a
temporary sibling path, verify it, then rename it atomically into the active
directory while CourierCMS is stopped or before the planned restart.

Extraction uses a separate content-addressed runtime cache keyed by the package
SHA-256 (which covers its Extension ID and version). The package remains the
installation source; the cache can be rebuilt.
CourierCMS verifies an existing cache against the installed archive and rejects a
mismatch rather than executing altered cached code.

Source checkouts default to `.local/extensions` and `.local/extension-cache`.
The production image uses `/var/lib/couriercms/extensions` and
`/var/lib/couriercms/extension-cache`. Configure them with
`COURIERCMS_EXTENSIONS_PATH` and `COURIERCMS_EXTENSION_CACHE_DIR`. Package count,
archive entry count, compressed bytes, and uncompressed bytes all have
configurable upper bounds.

## Dependency policy

Extensions compile against the published CourierCMS Extension SDK and the supported
Elixir/OTP versions. The SDK exposes stable value types and behaviours without
granting access to internal contexts.

An Extension may use OTP and an explicitly approved set of shared libraries.
It must not replace core dependencies or assume that its private dependency
version wins inside the VM. A required conflicting dependency, NIF, or native
runtime is not accepted silently; it triggers an architecture review.

## Persisted identity

Connections and Route Revisions refer to stable Extension and component IDs.
Runs additionally capture:

- Extension ID and version;
- package checksum;
- component ID;
- SDK contract version; and
- execution runtime.

Runs currently store source and target Adapter evidence. When Processor
execution is implemented, Runs will also store ordered Processor artifact
evidence using the same identity principles.

These fields make execution and recovery explainable even after an
administrator changes the installed package.
