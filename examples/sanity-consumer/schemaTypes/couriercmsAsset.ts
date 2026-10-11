import {ImageIcon} from '@sanity/icons/Image'
import {defineField, defineType} from 'sanity'

export const couriercmsAsset = defineType({
  name: 'couriercmsAsset',
  title: 'CourierCMS Asset Receipt',
  type: 'document',
  icon: ImageIcon,
  readOnly: true,
  fields: [
    defineField({
      name: 'couriercmsAssetKey',
      title: 'CourierCMS asset key',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'installationId',
      title: 'Installation ID',
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
    defineField({
      name: 'asset',
      title: 'Sanity image asset',
      type: 'reference',
      to: [{type: 'sanity.imageAsset'}],
      validation: (rule) => rule.required(),
    }),
    defineField({name: 'filename', title: 'Filename', type: 'string'}),
    defineField({name: 'mediaType', title: 'Media type', type: 'string'}),
    defineField({name: 'contentHash', title: 'Content hash', type: 'string'}),
  ],
  preview: {
    select: {
      filename: 'filename',
      routeId: 'routeId',
      media: 'asset',
    },
    prepare({filename, routeId, media}) {
      return {
        title: filename || 'Delivery asset',
        subtitle: `Route ${routeId || 'unknown'}`,
        media,
      }
    },
  },
})
