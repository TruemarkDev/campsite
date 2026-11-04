import assert from 'node:assert/strict'
import test from 'node:test'

import { testEnvironment } from './test-environment.mjs'

test('retains runtime and explicit test database settings while excluding operator credentials', () => {
  const result = testEnvironment({
    PATH: '/runtime/bin',
    HOME: '/operator',
    LANG: 'en_US.UTF-8',
    LC_ALL: 'C',
    GEM_HOME: '/runtime/gems',
    BUNDLE_APP_CONFIG: '/runtime/bundle-config',
    PG_TEST_HOST: '127.0.0.1',
    PG_TEST_PASSWORD: 'synthetic-test-password',
    DATABASE_URL: 'production-sentinel',
    RAILS_MASTER_KEY: 'production-key-sentinel',
    NEXT_PUBLIC_API_URL: 'https://production.invalid',
    AWS_SECRET_ACCESS_KEY: 'aws-sentinel',
    UNRELATED_ENGINEERING_CREDENTIAL: 'unrelated-sentinel',
    NODE_OPTIONS: '--require untrusted-instrumentation'
  })
  assert.deepEqual(result, {
    PATH: '/runtime/bin',
    HOME: '/operator',
    LANG: 'en_US.UTF-8',
    LC_ALL: 'C',
    GEM_HOME: '/runtime/gems',
    BUNDLE_APP_CONFIG: '/runtime/bundle-config',
    PG_TEST_HOST: '127.0.0.1',
    PG_TEST_PASSWORD: 'synthetic-test-password'
  })
})
