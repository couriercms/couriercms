# ADR-0007: Adapter and Connector separation

- Status: Accepted
- Date: 2026-09-24

The Adapter/Connector separation remains accepted. The original compiled-in
Adapter lifecycle is superseded by
[ADR-0015](0015-native-otp-extensions.md).

## Context

Cloud CMSs are normally accessed through remote APIs, while Sitecore, Drupal, and WordPress may benefit from installed modules for native events or privileged content access.

## Decision

An Adapter always runs on the CourierCMS side and understands one CMS. A CMS Connector is an optional installed component inside that CMS. The Adapter may use the standard CMS API directly or communicate with its Connector.

Adapters run on the CourierCMS side as native OTP Extension components. Remote
Adapter workers are outside the accepted architecture unless a later ADR adds
them.

## Consequences

- The core integration model remains consistent for cloud and self-hosted CMSs.
- Connector code stays small and CMS-native.
- Events normally contain identity hints; the Adapter reads authoritative content.
- Native Adapter Extensions are trusted code and require a compatible,
  administrator-installed package and node restart.

## Alternatives considered

- Call installed modules Adapters: rejected because it makes deployment and responsibility ambiguous.
- Require a module for every CMS: rejected because cloud CMSs and adequate standard APIs do not need one.
