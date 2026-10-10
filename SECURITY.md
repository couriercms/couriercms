# Security Policy

CourierCMS handles privileged CMS credentials and potentially sensitive
unpublished content. Security is part of the product contract.

## Reporting vulnerabilities

Use GitHub's [private vulnerability reporting][report-vulnerability] to submit
a suspected vulnerability. Include the affected version, impact, and sanitized
reproduction details. Do not open a public issue containing exploit details,
credentials, customer data, or unredacted logs.

CourierCMS is an early-stage project and does not currently promise a response
or remediation time. Reports will be assessed through GitHub Security
Advisories, where disclosure and remediation can be coordinated privately.

[report-vulnerability]: https://github.com/couriercms/couriercms/security/advisories/new

## Security invariants

- Credentials are encrypted at rest with key material stored outside PostgreSQL.
- Tokens, passwords, webhook secrets, raw content, and full payloads are not logged.
- Incoming connector events are authenticated, timestamp-checked, and deduplicated.
- Target ownership is verified before every update.
- Outbound clients enforce timeouts, response bounds, redirect policy, and URL safety.
- Transformations are allowlisted; Route configuration cannot contain scripts.
- Extensions are trusted, precompiled OTP applications loaded at startup. They
  are not sandboxed and must be installed only from trusted sources.

See the [security model](docs/architecture/security.md).

Never commit `.env` files, CMS credentials, webhook signatures, production
database dumps, customer content, vault keys, private TLS keys, or generated
packages. Use synthetic fixtures and `.env.example` placeholders.
