import type {StructureResolver} from 'sanity/structure'
import {DocumentTextIcon} from '@sanity/icons/DocumentText'

export const couriercmsStructure: StructureResolver = (S) =>
  S.list()
    .title('CourierCMS Destination')
    .items([
      S.listItem()
        .title('All deliveries')
        .icon(DocumentTextIcon)
        .child(
          S.documentList()
            .title('All deliveries')
            .filter('_type == "couriercmsDelivery"')
            .defaultOrdering([{field: 'deliveredAt', direction: 'desc'}]),
        ),
      S.divider(),
      S.listItem()
        .title('Browse by Route ID')
        .child(
          S.documentTypeList('couriercmsDelivery')
            .title('CourierCMS deliveries')
            .defaultOrdering([{field: 'routeId', direction: 'asc'}]),
        ),
    ])
