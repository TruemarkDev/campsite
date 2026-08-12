import base from '@campsite/eslint-config/flat-base.mjs'
import next from '@campsite/eslint-config/flat-next.mjs'

export default [
  ...base,
  ...next,
  { ignores: ['.*.js', '.next/**', 'node_modules/**', 'dist/**'] }
]
