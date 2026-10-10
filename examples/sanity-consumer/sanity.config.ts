import {defineConfig} from 'sanity'
import {structureTool} from 'sanity/structure'
import {visionTool} from '@sanity/vision'
import {schemaTypes} from './schemaTypes'
import {couriercmsStructure} from './structure'

const projectId = process.env.SANITY_STUDIO_PROJECT_ID
const dataset = process.env.SANITY_STUDIO_DATASET || 'production'

if (!projectId) {
  throw new Error('SANITY_STUDIO_PROJECT_ID is required')
}

export default defineConfig({
  name: 'couriercms',
  title: 'CourierCMS Destination',
  projectId,
  dataset,
  plugins: [structureTool({structure: couriercmsStructure}), visionTool()],
  schema: {types: schemaTypes},
})
