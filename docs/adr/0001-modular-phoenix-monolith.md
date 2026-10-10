# ADR-0001: Modular Phoenix monolith

- Status: Accepted
- Date: 2026-09-24

Extension runtime details in this ADR are superseded by
[ADR-0015](0015-native-otp-extensions.md). The modular-monolith decision remains
accepted.

## Context

CourierCMS needs durable jobs, concurrency, fault isolation, real-time progress, a web UI, and an extensible CMS integration layer. The first release must remain easy to self-host and operate.

## Decision

Build one Phoenix/Elixir application backed by PostgreSQL and Oban. Organize it as a modular monolith with explicit contexts and Adapter behaviours. Do not begin with an umbrella application, microservices, or an external Adapter protocol.

## Consequences

- One release and database simplify self-hosting and transactions.
- The BEAM and Oban support reliable concurrent delivery.
- Module and data boundaries must be enforced deliberately.
- Specialized integration components follow the native OTP Extension decision
  in ADR-0015. Other runtimes require a future ADR.

## Alternatives considered

- Microservices: rejected as premature operational complexity.
- Phoenix umbrella: rejected because no independently deployed applications currently exist.
- Rust core: rejected because orchestration and reliability fit Elixir; Rust remains appropriate for specialized processors.
