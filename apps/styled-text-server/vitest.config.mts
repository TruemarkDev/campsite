import path from 'path'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
    env: { AUTHTOKEN: 'styled-text-test-token' }
  },
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, '.')
    }
  }
})
