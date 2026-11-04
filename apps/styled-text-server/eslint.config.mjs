import { FlatCompat } from '@eslint/eslintrc'
import js from '@eslint/js'

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all
})

export default [
  { ignores: ['.*.js', 'node_modules/', 'dist/', '**/*.snap'] },
  ...compat.extends('@campsite/eslint-config/base.js')
]
