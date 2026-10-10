# ADR-0012: Transformation ownership and extension boundary

- Status: Accepted
- Date: 2026-09-24

The transformation ownership boundary remains accepted. The out-of-process
Extension runtime decision is superseded by
[ADR-0015](0015-native-otp-extensions.md).

## Context

CourierCMS needs enough transformation to produce useful portable delivery payloads. Customers may later require specialized operations such as OCR, document parsing, or image metadata extraction, potentially implemented in Rust or another language. Allowing arbitrary scripts or dynamically loading third-party BEAM code would weaken security, release compatibility, determinism, and operational isolation. Moving every conversion into CourierCMS would also make it responsible for target-native content modeling and workflow.

## Decision

V0 provides only built-in, named, allowlisted, versioned, deterministic, target-independent Transformations. Route configuration contains transformation identifiers and configuration, never executable source code.

Target-native schema construction, editorial policy, publishing behavior, rewriting, translation, embeddings, and AI orchestration belong to the Target Consumer by default.

Specialized target-independent processing may use administrator-installed
Processor components supplied by trusted, precompiled native OTP Extensions.
CourierCMS does not compile source files or hot-load arbitrary BEAM modules.

## Consequences

- Common transformations remain simple to operate, test, version, and replay.
- CourierCMS preserves its reliable transport boundary instead of becoming a workflow or target-modeling engine.
- Customer-specific processing has a path without rebuilding the core CourierCMS
  release.
- Native Extensions require manifest, compatibility, resource-limit,
  signing/distribution, and conformance-test design; they are trusted, not
  sandboxed.
- AI in the delivery path remains excluded unless a future ADR explicitly addresses its non-determinism and operational consequences.

## Alternatives considered

- Keep all transformation target-side: rejected because portable delivery sometimes requires deterministic source normalization or extraction before target acceptance.
- Allow arbitrary scripts in Route configuration: rejected because it creates an unsafe generic automation runtime.
- Load Extension source or hot-replace modules dynamically: rejected because
  startup-loaded precompiled OTP packages provide a simpler, verifiable
  lifecycle.
- Require every Extension to use an Elixir Port: rejected because it introduces
  a second runtime and IPC protocol without a demonstrated need.
