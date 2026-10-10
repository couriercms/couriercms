# Contributing to CourierCMS

CourierCMS is early-stage. Contributions should reinforce its narrow focus:
reliable, observable, one-way content delivery between content systems.

## Before starting

Read the [product definition](docs/concepts/product.md),
[glossary](docs/concepts/glossary.md),
[architecture](docs/architecture/overview.md), and relevant accepted
[ADRs](docs/adr/README.md). Discuss a durable architectural change before
implementation and record an ADR when a decision changes.

## Development workflow

1. Define user-visible behavior and failure semantics.
2. Keep Phoenix controllers, LiveViews, and Oban workers as orchestration boundaries.
3. Keep concrete CMS behavior in independently testable extensions.
4. Add deterministic tests; live third-party systems must remain opt-in.
5. Run `scripts/test.ps1` or `sh scripts/test.sh`.
6. Update the owning documentation and capability matrix.

Never commit credentials, `.env` files, customer content, database dumps,
generated extension archives, connector ZIPs, dependency trees, or build output.

## Pull requests

Keep changes focused. Explain the behavior, product fit, retry/idempotency
effects, security implications, tests run, and documentation or ADR changes.
Do not claim checks that were not executed.

By participating, follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security
issues follow [SECURITY.md](SECURITY.md), not the public issue tracker.
