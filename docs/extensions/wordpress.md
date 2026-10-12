# WordPress Source Adapter

## Status

The V0 REST source Adapter is implemented against sanitized fixtures. Live
verification requires the staging WordPress URL that will be supplied after the
site is installed. It supports WordPress core posts only; it is not yet approved
for production content.

## Source access

Configure a Connection with the public site URL, for example
`https://wordpress.example`, not an individual REST endpoint. CourierCMS derives
`/wp-json/wp/v2` safely.

Public published posts can be read without credentials. For authenticated
edit-context reads, create a dedicated least-privilege WordPress user and a
revocable Application Password. Store the username and Application Password in
the Connection form. CourierCMS encrypts the credential map at rest and never places
it in job arguments or logs.

Connection testing reads one published post. With credentials configured, it
uses `context=edit`, so an invalid Application Password cannot accidentally pass
because public posts are accessible.

## Implemented content inventory

| Source | Scope | Notes |
|---|---|---|
| `post` | Published only | Pages and custom post types are rejected in V0 |
| Categories | Embedded relationship | Filter accepts a category slug |
| Tags | Embedded relationship | Filter accepts one or more tag slugs; match semantics are any |
| Author | Embedded relationship | Preserves WordPress user ID, display name, and public link |
| Featured media | Required Delivery Asset | Preserves attachment ID, original URL, MIME type, dimensions, alt text, and caption |
| Inline images | Required Delivery Assets | Discovers absolute HTTP(S) `img src` values in rendered HTML, deduplicates them, and preserves source URL and alt text |
| Body | Rendered HTML | Gutenberg-aware conversion is deferred to a transformation layer |
| Locale | Connection default | WordPress core has no locale per post; WPML/Polylang are deferred |
| Revision | Published `modified_gmt` | Historical WordPress revisions and autosaves are out of scope |

The live inventory—counts, real editors/blocks, media volume, plugins, custom
types, and data-quality issues—must be recorded after access is available.

## Selection mapping

CourierCMS sends filters to WordPress wherever core REST supports them:

| CourierCMS selection | WordPress REST behavior |
|---|---|
| `content_type=post` | `/wp/v2/posts` |
| `state=published` | `status=publish` |
| `category` | Resolve slug through `/categories`, then send category ID |
| `tags[]` | Resolve slugs through `/tags`, then send tag IDs |
| `published_year` | ISO-8601 `after`/`before` date window |
| Incremental checkpoint | ISO-8601 `modified_after`/`modified_before` window |

Collections are ordered by WordPress ID and fetched in bounded pages. Missing
category or tag slugs produce an empty result instead of broadening the Route.

The internal `source_item_ids` predicate is used for authenticated Connector
events. It maps to WordPress REST's `include` parameter while retaining the
Route's category, tag, year, and published-state filters.

## Automatic delivery

Periodic delivery is configured per Route. The default strategy establishes a
Full Scan baseline and then queries WordPress with a bounded modification-time
window. CourierCMS subtracts a two-minute overlap from the durable checkpoint, so
boundary changes may be rediscovered and are safely deduplicated by stable
identity and content hash. The window also has a fixed upper bound captured when
the Run is created, preventing a moving result set during pagination.

Admins can instead select Full Scan for every scheduled Run and can configure a
daily, weekly, or 30-day Full Scan reconciliation. If incremental discovery is
unsupported or WordPress rejects its parameters, the Run falls back to a Full
Scan. Checkpoints advance only after every discovered Run Item is durable.
Changing the Route Revision, including its selection or polling configuration,
establishes a new Full Scan baseline.

The optional plugin in `connectors/wordpress` emits signed
canonical contract-version-1 `content.published` and `content.updated` events. Events contain post identity and
status metadata only. CourierCMS re-reads the post through this Adapter before
mapping or delivery.

Connector authentication uses a per-Connection secret, an HMAC-SHA256 signature
over `<unix timestamp>.<raw JSON body>`, and a five-minute timestamp window.
Event IDs are durably deduplicated. Failed WordPress calls are retried through a
bounded WP-Cron queue.

## Blog Delivery Contract mapping

One WordPress post becomes one normalized root `ContentNode`. The Route mapping
produces:

```text
title
slug
excerpt
body { format: "html", value }
canonical_url
published_at
modified_at
author { source_id, name, url? }
categories[] { source_id, name, slug }
tags[] { source_id, name, slug }
featured_image? {
  source_id, source_url, filename, media_type,
  width?, height?, alt?, caption?
}
```

The source Adapter exposes featured media and inline rendered-HTML images
through the first-class Delivery Asset contract. CourierCMS streams the media with the same optional WordPress
Application Password used for source reads, enforces the platform byte and time
limits, and gives the target Adapter an independently retryable asset. The
target reference is injected into the final Delivery Item and its canonical
asset manifest, so a legacy WordPress URL is not the only asset identity. The
rendered HTML is deliberately preserved. Target-owned hooks can rewrite each
manifest `sourceUrl` to its `targetReference` without CourierCMS assuming a
target-native rich-text model.

## Identity and replay

- `item_key`: WordPress numeric post ID
- `locale_key`: configured Connection default, initially `und`
- `revision_key`: published `modified_gmt` timestamp
- `state`: `published`

If a post changes between enumeration and reading, the Adapter refuses to bind
the newer representation to the older Run Item. The operator starts another Run,
which discovers the new revision identity. Normal replay converges through the
CourierCMS content hash and target ownership checks.

## Known blind spots

- WPML, Polylang, multisite, custom post types, custom taxonomies, ACF, comments,
  menus, drafts, scheduled content, historical revisions, and page builders
- Shortcodes or plugin output that does not survive rendered REST HTML
- `srcset`, lazy-load-only attributes, CSS background images, and reusable Gutenberg blocks
- Media protected by CDN cookies, hotlink controls, or private storage
- SEO plugin fields not registered in the REST API

Inspect representative live posts before expanding scope. Do not silently treat
unsupported plugin data as complete.

## Validation before a live Route

1. Confirm HTTPS and `GET /wp-json/wp/v2/posts?per_page=1` work externally.
2. Test the CourierCMS Connection and inspect its capability snapshot.
3. Record counts for published posts, categories, tags, authors, and media.
4. Inspect at least five posts: old/new, short/long, media-heavy, and block-heavy.
5. Confirm category, tag, and year selections return expected IDs.
6. Confirm featured-media original URLs are reachable by CourierCMS.
7. Run WordPress to the fake target before enabling the Sanity target.
8. Confirm the first scheduled Run reports `full`, the next reports
   `incremental`, and a modified post is the only discovered item.

Redirects and final cutover are not CourierCMS V0 responsibilities. The payload keeps
the canonical WordPress URL so optional target-side code can make those decisions.
