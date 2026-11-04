#!/usr/bin/env node
// Production CSP/collector smoke test. Uses an isolated, unauthenticated browser
// and local Next.js server; no Rails, provider services or browser profile needed.
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { createRequire } from 'node:module'
import net from 'node:net'
import path from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'

import { testEnvironment } from './test-environment.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const web = path.join(root, 'apps/web')
const require = createRequire(path.join(web, 'package.json'))
const { chromium } = require('@playwright/test')
assert(existsSync(chromium.executablePath()), 'Use the existing project Chromium installation before running this test')
const directory = path.join(web, 'playwright/.cache', `csp-${randomBytes(8).toString('hex')}`)
mkdirSync(directory, { recursive: true })
const nextEnvPath = path.join(web, 'next-env.d.ts')
const nextEnv = readFileSync(nextEnvPath)
const environment = {
  ...testEnvironment(),
  NODE_ENV: 'production',
  NEXT_TELEMETRY_DISABLED: '1',
  NEXT_PUBLIC_WEB_URL: 'http://127.0.0.1',
  NEXT_PUBLIC_API_URL: 'http://127.0.0.1:3101',
  NEXT_PUBLIC_AUTH_URL: 'http://127.0.0.1:3101',
  NEXT_PUBLIC_SYNC_URL: 'ws://127.0.0.1:9100',
  CAMPSITE_BROWSER_TEST: '1',
  BROWSER_NEXT_DIST_DIR: path.relative(web, path.join(directory, 'next'))
}
const next = require.resolve('next/dist/bin/next')
let server
let browser
let logs = ''

async function until(check, description) {
  const deadline = Date.now() + 30_000
  while (Date.now() < deadline) {
    if (server?.exitCode !== null && server?.exitCode !== undefined) throw new Error('Local Next server exited')
    if (await check()) return
    await delay(100)
  }
  throw new Error(`Timed out: ${description}`)
}

try {
  const build = spawnSync(process.execPath, [next, 'build'], { cwd: web, env: environment, stdio: 'inherit' })
  assert.equal(build.status, 0, 'Production build failed')
  const reservation = net.createServer()
  await new Promise((resolve, reject) => reservation.once('error', reject).listen(0, '127.0.0.1', resolve))
  const { port } = reservation.address()
  await new Promise((resolve) => reservation.close(resolve))
  const origin = `http://127.0.0.1:${port}`
  server = spawn(process.execPath, [next, 'start', '--hostname', '127.0.0.1', '--port', String(port)], {
    cwd: web,
    env: environment,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  for (const stream of [server.stdout, server.stderr]) {
    stream.on('data', (chunk) => {
      // Keep only a bounded local buffer. It is never emitted or persisted.
      logs = (logs + chunk.toString()).slice(-64_000)
    })
  }
  await until(
    async () =>
      fetch(`${origin}/new`).then(
        () => true,
        () => false
      ),
    'server startup'
  )
  const response = await fetch(`${origin}/new`)
  assert.equal(response.status, 200, 'Expected the static app route')
  const enforced = response.headers.get('content-security-policy')
  const candidate = response.headers.get('content-security-policy-report-only')
  assert(enforced?.includes("'unsafe-eval'"))
  assert(candidate?.includes('report-uri /api/security/csp-report;'))
  const scripts = candidate.split(';').find((directive) => directive.trim().startsWith('script-src '))
  assert(scripts && !scripts.includes('unsafe-inline') && !scripts.includes('unsafe-eval'))
  assert((await response.text()).includes('__NEXT_DATA__'), 'Expected a real Next.js document')

  const endpoint = `${origin}/api/security/csp-report`
  assert.equal((await fetch(endpoint)).status, 405)
  assert.equal((await fetch(endpoint, { method: 'POST', body: 'invalid' })).status, 415)
  const post = (body, contentType = 'application/csp-report') =>
    fetch(endpoint, { method: 'POST', headers: { 'content-type': contentType }, body })
  assert.equal((await post('{invalid')).status, 400)
  assert.equal((await post(JSON.stringify(Array(21).fill({})), 'application/reports+json')).status, 400)
  assert.equal((await post('x'.repeat(20_000))).status, 413)
  assert.equal(
    (
      await post(
        JSON.stringify([
          {
            type: 'csp-violation',
            body: { disposition: 'report', effectiveDirective: 'script-src', blockedURL: 'wasm-eval' }
          }
        ]),
        'application/reports+json'
      )
    ).status,
    204
  )

  browser = await chromium.launch({ env: testEnvironment() })
  const context = await browser.newContext({ serviceWorkers: 'block' })
  await context.route('**/*', (route) =>
    new URL(route.request().url()).origin === origin ? route.continue() : route.abort()
  )
  const observed = new Set()
  context.on('response', async (result) => {
    if (result.url() !== endpoint || result.status() !== 204) return
    const report = result.request().postDataJSON()?.['csp-report']
    if (report) observed.add(`${report['effective-directive']}:${report['blocked-uri']}`)
  })
  const page = await context.newPage()
  const marker = 'synthetic-csp-private-marker'
  await page.route(`${origin}/csp-validation?*`, (route) =>
    route.fulfill({
      status: 200,
      headers: {
        'content-type': 'text/html',
        'content-security-policy': enforced,
        'content-security-policy-report-only': candidate
      },
      body: '<!doctype html><html><body><script>window.inlineRan = true; window.evalResult = eval("6 * 7")</script><button onclick="this.dataset.clicked = true">Continue</button></body></html>'
    })
  )
  await page.goto(`${origin}/csp-validation?token=${marker}`)
  assert.equal(await page.evaluate(() => window.inlineRan), true)
  assert.equal(await page.evaluate(() => window.evalResult), 42)
  await page.getByRole('button', { name: 'Continue' }).click()
  assert.equal(await page.getByRole('button').getAttribute('data-clicked'), 'true')
  await until(
    () =>
      observed.has('script-src:eval') &&
      observed.has('script-src-elem:inline') &&
      observed.has('script-src-attr:inline'),
    'browser report delivery'
  )
  await until(() => logs.includes('"event":"csp_violation"'), 'sanitized diagnostic')
  assert(!logs.includes(marker), 'Document URL leaked into diagnostics')
  await context.close()
  console.log(
    'Production CSP browser checks passed: inline/eval/handler execution preserved; violations delivered; input limits and privacy verified.'
  )
} finally {
  await browser?.close()
  if (server && server.exitCode === null) {
    const exited = new Promise((resolve) => server.once('exit', resolve))
    server.kill('SIGTERM')
    await Promise.race([exited, delay(5000)])
    if (server.exitCode === null) {
      server.kill('SIGKILL')
      await exited
    }
  }
  // Restore only the file this isolated build generates; retain no test data.
  const { writeFileSync } = await import('node:fs')
  writeFileSync(nextEnvPath, nextEnv)
  rmSync(directory, { recursive: true, force: true })
}
