import react from 'eslint-plugin-react'
import reactHooks from 'eslint-plugin-react-hooks'
import restrictedImports from './rules/no-restricted-imports.js'

export default [
  react.configs.flat.recommended,
  {
    plugins: {
      'react-hooks': reactHooks
    },
    languageOptions: {
      globals: { React: 'writable' }
    },
    settings: {
      next: { rootDir: ['apps/*/', 'packages/*/'] },
      react: { version: 'detect' }
    },
    rules: {
      'no-console': 'error',
      'react/no-array-index-key': 'error',
      'react/prop-types': 'off',
      'react-hooks/exhaustive-deps': 'error',
      'react-hooks/rules-of-hooks': 'error'
    }
  },
  restrictedImports,
  {
    files: ['**/*.stories.tsx'],
    rules: {
      'react-hooks/rules-of-hooks': 'off'
    }
  }
]
