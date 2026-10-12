# CourierCMS Content Processors

This official, target-independent Extension contains conservative deterministic
Processors that run after mapping and built-in Transformations.

## HTML text normalizer

`com.couriercms.content/html_text_normalizer` can normalize line endings, remove
non-printing ASCII control characters, optionally replace non-breaking spaces,
and trim the surrounding string. It deliberately does not parse, repair, or
sanitize HTML and does not remove scripts or unsafe markup.

Example Route definition:

```text
body=body|com.couriercms.content/html_text_normalizer|{"replace_non_breaking_spaces":true}
```

## Exact token replacer

`com.couriercms.content/exact_token_replacer` replaces explicitly enumerated
literal tokens in one non-cascading pass. It can handle known complete shortcode
forms, but it is not a general shortcode parser and does not interpret attributes,
nesting, escaping, or CMS plugin behavior.

```text
body=body|com.couriercms.content/exact_token_replacer|{"replacements":{"[year]":"2026","[gallery ids=\"1,2\"]":"<div data-gallery=\"1,2\"></div>"}}
```

Run `mix test` from this directory. Build a package with
`MIX_ENV=prod mix couriercms.extension.build`.
