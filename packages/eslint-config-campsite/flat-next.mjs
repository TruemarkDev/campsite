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
      '@tanstack/query/exhaustive-deps': 'error',
      '@tanstack/query/prefer-query-object-syntax': 'error',
      'react/no-array-index-key': 'error',
      'react-hooks/exhaustive-deps': 'error',
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
