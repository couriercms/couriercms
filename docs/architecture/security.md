# Security Model

## Assets to protect

- Source and target CMS credentials
- Unpublished and restricted content
- Webhook signing secrets
- Encryption keys
- CMS endpoint and topology information
- Delivery history and error diagnostics
- Processor inputs and temporary assets

## Trust boundaries

```text
Browser/operator
    -> CourierCMS web boundary
    -> database/job boundary
    -> Adapter HTTP boundary
    -> configured CMS

CMS Connector/webhook
    -> public webhook boundary
    -> durable event storage
    -> asynchronous execution

CourierCMS VM
    -> trusted native Extension code
```

Core code and native Extensions share one BEAM trust boundary. Route
configuration, mapped content, webhook payloads, CMS responses, and target
endpoints remain untrusted inputs. Installing an Extension is equivalent to
installing server application code: it is restricted to owners/administrators,
must come from a trusted source, and is not sandboxed by the VM.

## Credentials

- Encrypt credentials at the application layer before persistence.
- Supply the encryption root key outside PostgreSQL through deployment secrets.
- Separate credential fields from general Connection settings.
- Show secret presence, not secret values, after save.
- Support rotation without recreating a Connection.
- Never place credentials in Oban arguments, URLs, telemetry metadata, exceptions, or audit diffs.
- Prefer least-privilege CMS service accounts limited to the selected source and Destination target operations.

An external secret manager can be supported later through secret references.

Credential replacement is available to owners/admins without recreating a
Connection. Connector rotation accepts the prior HMAC key for 24
hours. Vault-key rotation loads the current and previous cipher tags together,
re-encrypts all Connection credential maps, and removes the previous key only
after verification. Never rotate the database and key backups independently.

## Authentication and authorization

In Server, all application pages require authentication. CourierCMS uses
invite-only email magic links; it has no public registration or password-login
UI. A user also needs an active membership in the current Workspace. Login
requests return the same message for known and unknown email addresses.

Local has one implicit internal operator and Workspace. It constructs the same
authorization scope used by Server contexts; it does not bypass context
authorization and does not expose a general disable-authentication setting.
Its security boundary is the workstation account plus a listener hard-coded to
IPv4 loopback (`127.0.0.1`). Local refuses Server deployment roles, has no
Connector ingress, and cannot be configured to bind publicly. Anyone able to
use the operator's OS account can use Local CourierCMS, so workstation access
and disk encryption matter.

V0 has one default Workspace and no workspace switcher, but Connections, Routes,
Runs, Destination views, and membership administration are scoped by
`workspace_id`. Treat this as a required authorization boundary, not merely a
future database field.

Roles are:

- `owner`: full workspace control and the only role allowed to assign owners or administrators
- `admin`: configuration plus operator/viewer administration
- `operator`: manual execution and retry operations
- `viewer`: read-only access

At least one active owner must remain. Users cannot block themselves. Accounts
are blocked rather than deleted, and blocking revokes their sessions. Sensitive
membership changes and manually initiated Runs produce audit events.

A future hosted-service platform administrator or billing account is separate
from Workspace ownership. Do not add a global superuser flag to Workspace
Memberships. See [ADR-0009](../adr/0009-invite-only-auth-and-workspaces.md).

Sensitive actions requiring audit include:

- Inviting, blocking, unblocking, and changing roles
- Creating/updating credentials
- Testing Connections
- Provisioning a Destination
- Activating a Route Revision
- Manual Runs and replays
- Cancelling Runs
- Resetting checkpoints

## Webhook security

- Require HTTPS outside development.
- Verify the provider/Connector signature over the raw request body.
- Reject timestamps outside a bounded clock-skew window.
- Deduplicate a provider event key under a database uniqueness constraint.
- Limit body size before parsing.
- Respond after durable receipt, not after content delivery.
- Rate-limit by Connection and network source without trusting IP alone.
- Rotate webhook secrets with overlap where supported.

## SSRF controls

Connections contain user-configured URLs, so Adapter clients must:

- Allow only supported schemes, normally HTTPS
- Resolve and validate addresses before connecting
- Block loopback, link-local, metadata-service, and prohibited private ranges unless an administrator explicitly enables private-network access
- Revalidate redirects and limit redirect count
- Avoid forwarding credentials across host changes
- Apply DNS rebinding defenses

Self-hosted private CMS access is a legitimate use case. Private-network access must be an explicit deployment policy, not an accidental bypass.

The platform-owned SDK HTTP implementation validates an Extension request's
resolved endpoint before each call, applies cluster-wide Connection rate limits,
bounds timeouts and response sizes, and does not follow redirects. Production
requires HTTPS and blocks private addresses by default.
`COURIERCMS_ALLOW_PRIVATE_NETWORKS=true` enables RFC1918/ULA endpoints;
loopback, link-local, metadata, multicast, and unspecified addresses remain
blocked unless `COURIERCMS_ALLOW_UNSAFE_LOCAL_ENDPOINTS=true` is also set. That
second setting is intended only for explicitly isolated development/test
deployments. DNS and egress firewall policy remain the final rebinding defense.

## Content and logging

Default logs include opaque IDs, Extension/component IDs, operation, status,
duration, safe error category, and correlation ID. They exclude full payloads,
rich text, binary data, credentials, authorization headers, webhook bodies, and
raw third-party responses.

Developer debug logging must use synthetic data and must not be enabled by default in production.

The Local data directory contains the SQLite database, encryption material,
release cookie, installed Extensions, and logs. The database may contain
client content, delivery errors, endpoint details, and encrypted credentials.
Back up the database together with its installation secrets, protect the whole
backup as sensitive client data, and never publish either file as a diagnostic
artifact.

## Target ownership

An update requires both a CourierCMS Route Item binding and matching target ownership metadata. Failure is terminal and visible. No force-overwrite option exists in normal execution.

## Extensions, processors, and temporary files

- Use per-execution temporary directories.
- Enforce file count, size, duration, and output limits.
- Pass only required inputs and configuration.
- Do not inherit unnecessary environment secrets.
- Treat output as untrusted and validate it.
- Remove temporary data after processing; operational cleanup handles crash remnants.
- Load only precompiled OTP Extension packages that pass manifest, archive,
  compatibility, checksum/signature-policy, module-collision, and callback
  validation. Never compile Extension source in production.
- Treat Extension code as fully trusted. Do not claim process, memory, or secret
  isolation merely because its processes are supervised.
- Do not grant an Extension direct PostgreSQL access, the encryption root key,
  or unrelated Connection credentials through the SDK.
- Capture Extension identity, version, SDK contract, and package checksum on
  Runs; never silently retry with a different artifact.
- Require explicit owner/admin filesystem installation and restart; never
  download and execute marketplace packages automatically.
- Reject duplicate Extension IDs, unsafe archive paths, forbidden migrations,
  and incompatible Elixir/OTP/dependency requirements.
- Native libraries, untrusted code, scheduler-blocking parsing, and conflicting
  dependency versions require a separate architecture decision.

## Dependency and release security

- Lock dependencies.
- Run dependency vulnerability and license checks in CI.
- Produce reproducible container images where practical.
- Run as a non-root user.
- Keep the application filesystem read-only except explicit temporary/storage paths.
- Document supported upgrade and backup procedures before production claims.

Temporary dependency-audit exceptions are documented in
[security advisory exceptions](../operations/security-advisories.md); they must state scope,
mitigation, and a removal condition.
