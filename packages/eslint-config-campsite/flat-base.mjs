import js from '@eslint/js'
import typescriptEslint from '@typescript-eslint/eslint-plugin'
import typescriptParser from '@typescript-eslint/parser'
import globals from 'globals'
import turbo from 'eslint-plugin-turbo'
import unusedImports from 'eslint-plugin-unused-imports'

export default [
  js.configs.recommended,
  turbo.configs['flat/recommended'],
  {
    plugins: {
      '@typescript-eslint': typescriptEslint,
      'unused-imports': unusedImports
    },
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.node,
      parser: typescriptParser,
      parserOptions: { project: true }
    },
    rules: {
      'no-irregular-whitespace': 'error',
      'no-empty-function': 'error',
      'newline-after-var': 'error',
      'no-unused-vars': 'off',
      'no-fallthrough': ['error', { allowEmptyCase: true }],
      'no-extra-semi': 'off',
      'max-lines': ['error', 500],
      '@typescript-eslint/no-unused-vars': 'off',
      '@typescript-eslint/consistent-type-definitions': ['error', 'interface'],
      'unused-imports/no-unused-imports': 'error',
      'unused-imports/no-unused-vars': [
        'warn',
        {
          vars: 'all',
          varsIgnorePattern: '^_',
          args: 'after-used',
          argsIgnorePattern: '^_'
        }
      ]
    }
  },
  {
    files: ['**/__tests__/**/*'],
    languageOptions: { globals: globals.jest }
  },
  {
    files: ['**/*.{ts,tsx,mts,cts}'],
    rules: {
      'no-undef': 'off',
      'no-redeclare': 'off'
    }
  }
]
