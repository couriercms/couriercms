# Mapping, Aggregation, and Transformations

## Implementation status

Declarative mapping and Projection Fields are implemented. Route Revisions
persist transformation configuration, but the current execution pipeline does
not yet apply built-in Transformations or invoke Extension Processors. The
Transformation and Processor sections below describe the accepted boundary for
that planned implementation.

## Mapping target

Mappings transform normalized source content into a versioned,
target-independent Delivery Contract. They do not map directly into the target
CMS's native editorial schema.

```text
Source Adapter -> normalized content -> Route mapping -> Delivery Payload vN
               -> Canonical Delivery Document -> Target Destination
```

## Aggregation

The root item is selected independently. Aggregation Rules describe which
related source content should be included and the bounds that apply. The source
Adapter, not a generic platform crawler, interprets those rules using its CMS's
reference, component, datasource, taxonomy, locale, and media semantics.

Each implemented source Adapter returns a bounded Content Bundle through
`read_root/3`. The SDK contract makes the root, included content,
relationships, Delivery Asset descriptors, and generic safety bounds explicit
without moving CMS-specific traversal into the platform.

For each relationship a Route can:

- Embed mapped dependency data in the root payload
- Flatten selected dependency fields into a parent object
- Include a Delivery Asset descriptor
- Preserve a source reference identifier as data
- Ignore the relationship

Automatically following every source reference is prohibited.

## Mapping definition

A mapping is declarative and versioned. It can express:

- Source path to payload path
- Constant/default values
- Required and optional values
- List/object projection
- Named transformation chains
- Missing dependency behavior
- Output contract validation

Mappings contain no arbitrary executable code.

## Target projections

A Route Revision may define optional Projection Fields for the target Intake Schema. Each projection identifies a target field, a path in the Canonical Delivery Document, and an allowlisted target value type. For example, `payload.title` may project to `projectedTitle` and `payload.published_at` to `projectedPublishedAt`.

Projection Fields follow these rules:

- The complete Canonical Delivery Document is always delivered and retained.
- A projection is derived from that document and cannot introduce independent content.
- CourierCMS may overwrite projections on every delivery; target-side edits to them are not authoritative.
- Projection definitions belong to the immutable Route Revision.
- Missing fields, incompatible target types, and unsupported projection capabilities fail preflight or the affected Run Item visibly.
- Changing projections never causes runtime target-schema mutation. An operator must provision or deploy the Intake Schema change explicitly before activating the Route Revision.

Projections are intended for efficient target queries, previews, hooks, and
integrations when repeatedly parsing JSON would be inconvenient. They are not
mappings into the target's native editorial model. Any native target modeling
or post-delivery behavior is independently owned by the target environment.

## Transformations (planned execution)

Transformations make source content portable enough to enter the Canonical Delivery Document. They do not convert it into the target customer's native editorial or business model.

Common transformations may be built into the CourierCMS release. They are named,
allowlisted, deterministic, versioned operations such as:

- string to slug
- date normalization
- URL normalization
- concatenation
- safe HTML cleanup or extraction of plain text
- normalization into a target-independent rich-text representation

Transformation configuration is stored in a Route Revision. Errors identify the transformation and safe field path without logging the value.

A transformation belongs in CourierCMS when its output remains meaningful
regardless of the target CMS. Converting HTML into a customer's Sanity Portable
Text blocks, selecting a native target content type, applying editorial policy,
rewriting copy, translating content, or generating embeddings is outside the
CourierCMS delivery boundary by default.

Route configuration never contains transformation source code or scripts.
Common small operations should first be implemented and tested in the core;
specialized target-independent work may eventually use a declared native
Extension Processor loaded through the normal startup package lifecycle.

## Processors (planned)

The architecture below is accepted, but Processor packages are not yet
accepted or executed by the current platform runtime.

Processors handle heavier deterministic work such as OCR, image metadata extraction, PDF parsing, or archive extraction. Processor execution records:

- processor name and version
- configuration version
- input hash
- output hash
- duration
- retryability and sanitized error

Processors are the customization boundary for customer-specific or specialized
target-independent transformation work. A Processor is a component in a trusted
native OTP Extension and follows the same package, registry, gateway, restart,
and version-capture rules as an Adapter. It receives bounded inputs and declared
configuration. CPU-heavy, native, untrusted, or scheduler-blocking processing is
outside the initial native Extension contract and requires a separate ADR.

Processors are declarative from the Route's point of view: Extension/component
identifier, input/output paths, configuration, limits, and failure policy are
versioned in the Route Revision. They cannot access CourierCMS's database through
the SDK, execute arbitrary workflow steps, call target Adapters, or receive
unrelated credentials.

One Extension package may declare Adapters and Processors when they share an
owner, dependencies, and release lifecycle. A reusable Processor may be an
independent Extension. The platform invokes Processors through the Extension
Gateway; an Adapter never calls a Processor directly.

AI enrichment is outside the current CourierCMS delivery boundary. Introducing
AI into that path would require a new ADR that addresses non-determinism,
provider/model and prompt versions, input/output retention, approval policy,
replay, privacy, cost, and failure semantics.

## Ownership decision

Use this rule when evaluating a requested conversion:

```text
Makes source content portable and target-independent?
    -> CourierCMS mapping, built-in Transformation, or native Extension Processor

Makes content native to the target's schema, workflow, or business policy?
    -> Outside CourierCMS; the target environment may handle it independently
```

## Contract evolution

Changing a mapping creates a new Route Revision and Delivery Contract version. It does not mutate past Runs and does not automatically change target CMS schema.

The target Delivery Item uses a stable system envelope and replaceable payload. Updating a source item with a later revision replaces the Canonical Delivery Document as a whole or its target-equivalent atomic field so removed mapping fields do not remain stale. Projection Fields are regenerated from that same document during the write.

Breaking contract changes require preview and an explicit Route activation.
Any target-owned code that reads delivered documents is responsible for the
declared `contractVersion`.

## Preview

Before activation, users should be able to select representative source items and inspect:

- Discovered dependencies
- Aggregated normalized input
- Mapped payload
- Transformation warnings/errors
- Contract validation result
- Estimated asset work

Preview must redact configured sensitive fields and must not write to the target unless explicitly running a delivery test.

## Delivery Assets

A Delivery Asset is a durable media or file dependency with independent
identity, metadata, retry state, and target binding. The database baselines,
SDK stream contract, atomic dependency/job persistence, bounded transfer,
independent retries, required-item gating, target-reference injection, and
stranded-job reconciliation are implemented. The full path is used only when
both Adapters advertise its optional callbacks. Official Adapters that have not
adopted it retain their documented in-item behavior. Operators can inspect and
retry the independent asset work from a Run without loading an unbounded list.
