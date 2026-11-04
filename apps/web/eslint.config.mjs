import storybook from 'eslint-plugin-storybook'

import base from '@campsite/eslint-config/flat-base.mjs'
import next from '@campsite/eslint-config/flat-next.mjs'

const config = [
  ...base,
  ...next,
  ...storybook.configs['flat/recommended'],
  {
    ignores: [
      '.*.js',
      '.next/**',
      '.storybook/**',
      'node_modules/**',
      'dist/**',
      'storybook-static/**',
      'playwright/.cache/**'
    ]
  }
]

export default config
