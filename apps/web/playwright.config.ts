import { createRequire } from 'node:module'
import path from 'node:path'
import { defineConfig, devices } from '@playwright/test'

import { APP_URL } from './playwright/consts'

if (process.env.CAMPSITE_BROWSER_TEST !== '1') throw new Error('Run browser tests with pnpm test:browser')
const resolve = createRequire(__filename)
const quote = (value: string) => `'${value.replaceAll("'", "'\\''")}'`
const node = quote(process.env.BROWSER_NODE!)
const ruby = quote(process.env.BROWSER_RUBY!)
const shutdown = { signal: 'SIGTERM' as const, timeout: 10_000 }

export default defineConfig({
  testDir: './playwright',
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  reporter: 'list',
  outputDir: path.join(process.env.BROWSER_TEST_OUTPUT!, 'artifacts'),
  use: {
    baseURL: APP_URL,
    trace: 'off',
    screenshot: 'off',
    video: 'off',
    actionTimeout: 15_000,
    navigationTimeout: 45_000
  },
  timeout: 120_000,
  expect: { timeout: 15_000 },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer:
    process.env.BROWSER_TEST_LIST === '1'
      ? []
      : [
          {
            name: 'api',
            command: `${ruby} bin/rails server -b 127.0.0.1 -p 3101 --pid tmp/pids/browser-${process.env.BROWSER_TEST_RUN_ID}.pid`,
            cwd: '../../api',
            env: { BROWSER_TEST_SERVER: '1' },
            url: 'http://127.0.0.1:3101/up',
            timeout: 120_000,
            reuseExistingServer: false,
            gracefulShutdown: shutdown
          },
          {
            name: 'styled-text',
            command: `${node} dist/index.mjs`,
            cwd: '../styled-text-server',
            env: { PORT: '3102', AUTHTOKEN: process.env.BROWSER_STYLED_TEXT_TOKEN! },
            url: 'http://127.0.0.1:3102/up',
            reuseExistingServer: false,
            gracefulShutdown: shutdown
          },
          {
            name: 'sync',
            command: `${node} dist/index.mjs`,
            cwd: '../sync-server',
            env: { PORT: '9100' },
            url: 'http://127.0.0.1:9100/up',
            reuseExistingServer: false,
            gracefulShutdown: shutdown
          },
          {
            name: 'web',
            command: `${node} ${quote(resolve.resolve('next/dist/bin/next'))} dev -p 3100 --hostname 127.0.0.1`,
            cwd: path.dirname(resolve.resolve('./package.json')),
            url: APP_URL,
            timeout: 180_000,
            reuseExistingServer: false,
            gracefulShutdown: shutdown
          }
        ]
})
