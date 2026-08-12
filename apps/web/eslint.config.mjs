import { FlatCompat } from '@eslint/eslintrc'
import js from '@eslint/js'
import base from '@campsite/eslint-config/flat-base.mjs'
import next from '@campsite/eslint-config/flat-next.mjs'

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all
})

export default [
  ...base,
  ...next,
  ...compat.extends('plugin:storybook/recommended'),
  { ignores: ['.*.js', '.next/**', 'node_modules/**', 'dist/**'] }
]
