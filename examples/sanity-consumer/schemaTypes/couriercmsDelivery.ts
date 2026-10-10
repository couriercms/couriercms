import {DocumentTextIcon} from '@sanity/icons/DocumentText'
import {defineField, defineType} from 'sanity'

export const couriercmsDelivery = defineType({
  name: 'couriercmsDelivery',
  title: 'CourierCMS Delivery',
  type: 'document',
  icon: DocumentTextIcon,
  readOnly: true,
  fields: [
    defineField({
      name: 'title',
      title: 'Title',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'couriercmsKey',
      title: 'CourierCMS key',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'routeId',
      title: 'Route ID',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'destinationId',
      title: 'Destination ID',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({name: 'routeRevision', title: 'Route revision', type: 'number'}),
    defineField({
      name: 'installationId',
      title: 'Installation ID',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({name: 'sourceConnectionId', title: 'Source Connection ID', type: 'string'}),
    defineField({name: 'sourceItemId', title: 'Source item ID', type: 'string'}),
    defineField({name: 'sourceType', title: 'Source type', type: 'string'}),
    defineField({name: 'locale', title: 'Locale', type: 'string'}),
    defineField({name: 'sourceRevision', title: 'Source revision', type: 'string'}),
    defineField({name: 'sourceState', title: 'Source state', type: 'string'}),
    defineField({name: 'sourceModifiedAt', title: 'Source modified at', type: 'datetime'}),
    defineField({name: 'contractVersion', title: 'Contract version', type: 'number'}),
    defineField({name: 'contentHash', title: 'Content hash', type: 'string'}),
    defineField({name: 'deliveredAt', title: 'Delivered at', type: 'datetime'}),
    defineField({name: 'sourceUrl', title: 'Source URL', type: 'url'}),
    defineField({
      name: 'projectedTitle',
      title: 'Projected title',
      type: 'string',
      description: 'Derived from the configured canonical document path.',
    }),
    defineField({
      name: 'projectedSlug',
      title: 'Projected slug',
      type: 'string',
      description: 'Derived from the configured canonical document path.',
    }),
    defineField({
      name: 'projectedPublishedAt',
      title: 'Projected publication date',
      type: 'datetime',
      description: 'Derived from the configured canonical document path.',
    }),
    defineField({
      name: 'projectedNumber',
      title: 'Projected number',
      type: 'number',
      description: 'General-purpose numeric projection slot for the MVP.',
    }),
    defineField({
      name: 'projectedBoolean',
      title: 'Projected boolean',
      type: 'boolean',
      description: 'General-purpose boolean projection slot for the MVP.',
    }),
    defineField({
      name: 'featuredImage',
      title: 'Featured image',
      type: 'image',
      options: {hotspot: true},
      fields: [defineField({name: 'alt', title: 'Alternative text', type: 'string'})],
    }),
    defineField({
      name: 'deliveryJson',
      title: 'Canonical delivery document (JSON)',
      type: 'text',
      rows: 30,
      validation: (rule) =>
        rule.required().custom((value) => {
          if (!value) return true

          try {
            JSON.parse(value)
            return true
          } catch {
            return 'Delivery document must contain valid JSON'
          }
        }),
    })
  ],
  preview: {
    select: {
      title: 'title',
      routeId: 'routeId',
      locale: 'locale',
      media: 'featuredImage',
    },
    prepare({title, routeId, locale, media}) {
      return {
        title,
        subtitle: `${locale || 'und'} · Route ${routeId || 'unknown'}`,
        media,
      }
    },
  },
})
