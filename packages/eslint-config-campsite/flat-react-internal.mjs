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
      globals: { React: 'readonly' }
    },
    settings: {
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
    // CSF `render:` functions call hooks but aren't recognized as components;
    // this config is used outside Next apps where eslint-plugin-storybook
    // (which normally handles this) isn't loaded.
    files: ['**/*.stories.tsx'],
    rules: {
      'react-hooks/rules-of-hooks': 'off'
    }
  }
]
