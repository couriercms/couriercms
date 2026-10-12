# Content Processors

The official `com.couriercms.content` Extension provides small,
target-independent Processor components. The same package runs in Local and
Server profiles and is bundled with official releases.

These Processors run after Route mapping and built-in Transformations and before
content hashing. Changing their configuration creates a new immutable Route
Revision and causes the resulting content to be evaluated under the new delivery
contract.

## HTML text normalizer

Component: `html_text_normalizer`

This Processor performs conservative text-level normalization on a string:

- normalize CRLF and CR line endings to LF, enabled by default;
- remove non-printing ASCII control characters while retaining tabs and line
  endings, enabled by default;
- trim surrounding Unicode whitespace, enabled by default; and
- replace non-breaking spaces with ordinary spaces, disabled by default.

```text
body=body|com.couriercms.content/html_text_normalizer|{"replace_non_breaking_spaces":true}
```

Available boolean options are `normalize_line_endings`, `trim`,
`remove_control_characters`, and `replace_non_breaking_spaces`. Unknown options
are rejected.

Despite its name, this Processor does not parse, repair, or sanitize HTML. It
does not remove scripts, validate links, rewrite URLs, or guarantee valid markup.
Those operations require a deliberately selected parser and security policy.

## Exact token replacer

Component: `exact_token_replacer`

This Processor replaces an explicit map of literal strings in one
non-cascading pass. It is useful when a migration has a small known set of
complete shortcode or placeholder forms:

```text
body=body|com.couriercms.content/exact_token_replacer|{"replacements":{"[year]":"2026","[legacy-callout]":"<aside>Important</aside>"}}
```

The configuration requires between 1 and 50 replacements. Tokens and
replacement values are bounded strings. Replacements are literal, so regular
expression syntax has no special meaning, and generated output is not processed
again by the same step.

This is not a universal shortcode parser. It does not interpret attributes,
nested shortcodes, escaping, WordPress plugin callbacks, or Drupal filters.
Complex source semantics belong in a source-specific Processor or in explicit
project code, not in a misleading generic rule.

## Reliability and evidence

Both components are deterministic and perform no network or filesystem access.
Normal platform size limits, timeouts, per-item retries, immutable version
pinning, package checksums, telemetry, and durable Processor execution evidence
apply.

Both components publish typed configuration metadata for the guided Route
editor. The HTML text normalizer exposes boolean options. Exact token replacer
uses a JSON-object field because literal tokens and replacement values must be
represented without ambiguous delimiter or escaping rules. The Extension still
performs authoritative validation after the platform casts those fields.
