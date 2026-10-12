# Adapter Capability Matrix

This matrix records implemented behavior, not aspirations. Update it with every Adapter capability change.

Legend: `Planned`, `Implemented`, `Not adopted`, `Unsupported`, `Unknown`.

| Capability | WordPress | Sanity | Sitecore | Drupal | Contentful |
|---|---|---|---|---|---|
| Source Adapter | Implemented V0 | Future | Future | Future | Future |
| Target Adapter | Future | Implemented V0 | Future | Future | Future |
| Direct API mode | Implemented | Implemented | Unknown | Unknown | Unknown |
| CMS Connector | Implemented V0 plugin | Not required for V0 | Future | Future | Not required initially |
| Selection preview | Planned | Future | Future | Future | Future |
| Native type filter | Implemented (`post`) | Future | Future | Future | Future |
| Category/tag filter | Implemented (slugs) | N/A until source | Future mapping required | Future | Future |
| Parent/path scope | Limited by post hierarchy | N/A until source | Future | Future | N/A/adapter-defined |
| Incremental polling | Implemented | Future | Future | Future | Future |
| Save/update event | Implemented Connector | Future webhook | Future Connector | Future Connector | Future webhook |
| Publish event | Implemented Connector | Future webhook | Future Connector | Future Connector | Future webhook |
| Locales | Connection default; plugins deferred | Future | Future | Future | Future |
| Revisions | Implemented using published `modified_gmt` | Future | Future | Future | Future |
| Asset handling inside Delivery Item attempt | Not adopted | Not adopted | Future | Future | Future |
| First-class Delivery Asset pipeline | Implemented authenticated streaming | Implemented image upload and owned receipt | Planned | Planned | Planned |
| Destination provisioning | N/A as V0 target | Implemented schema package; explicit deployment | Future | Future | Future |
| Ownership verification | N/A as V0 target | Implemented | Future | Future | Future |

## Matrix rules

- `Planned` does not permit production use.
- The platform pipeline, fake Extension, and official WordPress-to-Sanity path
  implement the optional Delivery Asset contract. `Not adopted` in the
  in-item row means those Adapters deliberately avoid hidden asset-upload side
  effects; asset success is reported only through the first-class pipeline.
- Capability details and limits belong in Adapter-specific documentation once implementation begins.
- The runtime capability declaration is authoritative for a configured Connection; this matrix is a human overview.
