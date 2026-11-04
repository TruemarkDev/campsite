#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { lookup } from 'node:dns/promises'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import net from 'node:net'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { testEnvironment } from './test-environment.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const web = path.join(root, 'apps/web')
const requireWeb = createRequire(path.join(web, 'package.json'))
const id = randomBytes(8).toString('hex')
const database = `campsite_browser_${id}`
const output = path.join(web, 'playwright/.cache', id)
const nextEnvPath = path.join(web, 'next-env.d.ts')
const nextEnv = readFileSync(nextEnvPath, 'utf8')
const env = testEnvironment()
const pgHost = process.env.PG_TEST_HOST || '127.0.0.1'
if (!['127.0.0.1', 'localhost', '::1'].includes(pgHost)) throw new Error('Browser PostgreSQL must be local')
const redisUrl = process.env.BROWSER_REDIS_URL || 'redis://127.0.0.1:6379/14'
const redis = new URL(redisUrl)
if (redis.protocol !== 'redis:' || !['127.0.0.1', 'localhost', '[::1]'].includes(redis.hostname)) {
  throw new Error('Browser Redis must be local')
}
const misePath = (name) => {
  const result = spawnSync('mise', ['which', name], { cwd: root, encoding: 'utf8' })
  if (result.status !== 0) throw new Error(`Cannot resolve pinned ${name}`)
  return result.stdout.trim()
}
const ruby = misePath('ruby')
const pnpm = misePath('pnpm')
const node = misePath('node')
Object.assign(env, {
  PATH: [path.dirname(node), path.dirname(ruby), path.dirname(pnpm), env.PATH].join(path.delimiter),
  CAMPSITE_BROWSER_TEST: '1',
  BROWSER_TEST_RUN_ID: id,
  BROWSER_TEST_OUTPUT: output,
  BROWSER_NEXT_DIST_DIR: `playwright/.cache/${id}/next`,
  BROWSER_RUBY: ruby,
  BROWSER_NODE: node,
  BROWSER_TEST_PASSWORD: randomBytes(24).toString('hex'),
  BROWSER_STYLED_TEXT_TOKEN: randomBytes(24).toString('hex'),
  RAILS_ENV: 'test',
  NODE_ENV: 'development',
  PG_TEST_DATABASE: database,
  PG_TEST_HOST: pgHost,
  PG_TEST_PORT: process.env.PG_TEST_PORT || '5432',
  PG_TEST_USER: process.env.PG_TEST_USER || process.env.USER,
  PG_TEST_PASSWORD: process.env.PG_TEST_PASSWORD || '',
  PGGSSENCMODE: 'disable',
  WEB_CONCURRENCY: '0',
  RAILS_MAX_THREADS: '5',
  SIDEKIQ_SCHEDULER_ENABLED: 'false',
  OTEL_SDK_DISABLED: 'true',
  SESSION_COOKIE_SECURE: 'false',
  DEV_APP_URL: 'http://app.campsite.test:3100',
  DEV_STYLED_TEXT_API_URL: 'http://127.0.0.1:3102',
  DEV_SYNC_SERVER_URL: 'http://127.0.0.1:9100',
  API_BASE_URL: 'http://api.campsite.test:3101',
  NEXT_PUBLIC_WEB_URL: 'http://app.campsite.test:3100',
  NEXT_PUBLIC_API_URL: 'http://api.campsite.test:3101',
  NEXT_PUBLIC_AUTH_URL: 'http://auth.campsite.test:3101',
  NEXT_PUBLIC_ADMIN_URL: 'http://admin.campsite.test:3101',
  NEXT_PUBLIC_SYNC_URL: 'ws://127.0.0.1:9100',
  NEXT_PUBLIC_SAME_ORIGIN_API: 'true',
  NEXT_PUBLIC_SITE_URL: 'http://app.campsite.test:3100',
  NEXT_PUBLIC_CDN_URL: 'http://api.campsite.test:3101',
  NEXT_PUBLIC_IMGIX_URL: 'http://api.campsite.test:3101',
  NEXT_PUBLIC_OBJECT_STORAGE_URL: 'http://api.campsite.test:3101',
  NEXT_PUBLIC_PUSHER_KEY: 'browser-fixture',
  NEXT_PUBLIC_PUSHER_CLUSTER: 'mt1',
  NEXT_TELEMETRY_DISABLED: '1',
  REDIS_URL: redisUrl,
  REDIS_SIDEKIQ_URL: redisUrl,
  RACK_ATTACK_REDIS_URL: redisUrl,
  SYNC_REDIS_URL: redisUrl,
  SYNC_REDIS_PREFIX: `campsite-browser-${id}`
})
const args = process.argv.slice(2).filter((arg, index) => arg !== '--' || index !== 0)
const listOnly = args.includes('--list')
if (listOnly) env.BROWSER_TEST_LIST = '1'
const run = (command, commandArgs, cwd = root) => {
  const result = spawnSync(command, commandArgs, { cwd, env, stdio: 'inherit' })
  if (result.status !== 0) throw new Error(`${path.basename(command)} failed (${result.status ?? result.signal})`)
}
const rails = (...args) => run(ruby, ['bin/rails', ...args], path.join(root, 'api'))
const portIsFree = (port) =>
  new Promise((resolve, reject) => {
    const server = net.createServer()
    server.once('error', () => reject(new Error(`Browser fixture port ${port} is already in use`)))
    server.listen(port, '127.0.0.1', () => server.close(resolve))
  })
let prepared = false
let child
let interrupted = false
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    interrupted = true
    child?.kill(signal)
  })
}
try {
  if (!listOnly) {
    for (const hostname of ['app.campsite.test', 'api.campsite.test', 'auth.campsite.test']) {
      const addresses = await lookup(hostname, { all: true })
      if (!addresses.length || addresses.some(({ address }) => !['127.0.0.1', '::1'].includes(address))) {
        throw new Error(`${hostname} must resolve only to loopback for browser fixtures`)
      }
    }
    const browser = await requireWeb('@playwright/test').chromium.launch({ env })
    await browser.close()
    await Promise.all([3100, 3101, 3102, 9100].map(portIsFree))
    mkdirSync(output, { recursive: true, mode: 0o700 })
    prepared = true
    rails('db:create', 'db:schema:load')
    rails('runner', 'test/browser/seed.rb')
    run(pnpm, [
      'exec',
      'turbo',
      'run',
      'build',
      '--filter=@campsite/sync-server',
      '--filter=@campsite/styled-text-server'
    ])
    run(pnpm, ['build'], path.join(root, 'api'))
    run(pnpm, ['build:css'], path.join(root, 'api'))
  }
  const exitCode = await new Promise((resolve, reject) => {
    child = spawn(node, [requireWeb.resolve('@playwright/test/cli'), 'test', ...args], {
      cwd: web,
      env,
      stdio: 'inherit'
    })
    child.once('error', reject)
    child.once('exit', (code) => resolve(code ?? 1))
  })
  process.exitCode = interrupted ? 130 : exitCode
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
} finally {
  if (prepared) {
    try {
      run(ruby, ['-rbundler/setup', 'test/browser/cleanup_redis.rb'], path.join(root, 'api'))
    } catch {
      process.exitCode = 1
    }
    try {
      rails('db:drop')
    } catch {
      process.exitCode = 1
    }
    // Next generates a types reference for its run-specific dist directory.
    // Restore only our generated reference; preserve any concurrent edit.
    if (existsSync(nextEnvPath) && readFileSync(nextEnvPath, 'utf8').includes(`.cache/${id}/next`)) {
      writeFileSync(nextEnvPath, nextEnv)
    }
    if (process.env.BROWSER_KEEP_DIAGNOSTICS !== '1') rmSync(output, { recursive: true, force: true })
  }
}
