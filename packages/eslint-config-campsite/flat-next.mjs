import { FlatCompat } from '@eslint/eslintrc'
import js from '@eslint/js'
import query from '@tanstack/eslint-plugin-query'
import react from 'eslint-plugin-react'
import typescriptParser from '@typescript-eslint/parser'
import restrictedImports from './rules/no-restricted-imports.js'

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all
})

export default [
  ...compat.extends('next', 'next/core-web-vitals'),
  {
    plugins: {
      '@tanstack/query': query,
      react
    },
    languageOptions: {
      globals: { React: 'writable' }
    },
    settings: {
      react: { version: 'detect' }
    },
    rules: {
      'no-console': 'error',
      // v5 removed the v4 `prefer-query-object-syntax` rule and its replacement
      // reports existing query declarations as migrations. Keep that migration
      // separate from the ESLint compatibility upgrade.
      '@tanstack/query/exhaustive-deps': 'off',
      '@tanstack/query/prefer-query-options': 'off',
      'react/no-array-index-key': 'error',
      'react-hooks/exhaustive-deps': 'error',
      // These React Compiler checks were introduced by eslint-config-next 15.
      // Keep the existing hooks policy while the application adopts them incrementally.
      'react-hooks/immutability': 'off',
      'react-hooks/incompatible-library': 'off',
      'react-hooks/preserve-manual-memoization': 'off',
      'react-hooks/purity': 'off',
      'react-hooks/refs': 'off',
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/set-state-in-render': 'off',
      'react-hooks/use-memo': 'off',
      'react/prop-types': 'off'
    }
  },
  restrictedImports,
  {
    files: ['**/*.{ts,tsx,mts,cts}'],
    languageOptions: {
      parser: typescriptParser,
      parserOptions: { project: true }
    }
  }
]
