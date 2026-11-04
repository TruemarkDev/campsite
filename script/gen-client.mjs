import { spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import * as prettier from 'prettier'

import { testEnvironment } from './test-environment.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const require = createRequire(import.meta.url)
const { values } = parseArgs({ options: { check: { type: 'boolean' }, help: { type: 'boolean' } } })
if (values.help) {
  console.log(
    'Usage: script/gen-client [--check]\nGenerate API contracts, or verify that tracked contracts are current.'
  )
  process.exit(0)
}

// Resolve once, then bypass runtime shims that can re-inject the operator's
// production credentials after we have selected the test environment.
const resolvedRuby = spawnSync('ruby', ['-rrbconfig', '-e', 'print RbConfig.ruby'], {
  cwd: root,
  encoding: 'utf8'
})
if (resolvedRuby.status !== 0) throw new Error('Cannot resolve the project Ruby; run through mise exec')
const ruby = resolvedRuby.stdout.trim()
const environment = { ...testEnvironment(), RAILS_ENV: 'test', OTEL_SDK_DISABLED: 'true', PGGSSENCMODE: 'disable' }
// Contract generation may inspect model columns but must not write application data.
environment.PGOPTIONS = '-c default_transaction_read_only=on -c statement_timeout=15000'
const directory = mkdtempSync(path.join(tmpdir(), 'campsite-gen-client-'))
const run = (command, args, cwd = root, extra = {}) => {
  const result = spawnSync(command, args, { cwd, env: { ...environment, ...extra }, stdio: 'inherit' })
  if (result.status !== 0) throw new Error(`${path.basename(command)} failed (${result.status ?? result.signal})`)
}

try {
  run(ruby, ['bin/rake', 'apigen:generate_json'], path.join(root, 'api'), { OUT: directory })
  run(ruby, ['bin/rake', 'openapi:generate_json'], path.join(root, 'api'), {
    SWAGGER_SCHEMA: path.join(directory, 'schema_swagger.json'),
    OUT: path.join(directory, 'openapi_schema.json')
  })
  // The installed generator uses Biome internally. There is no reason to move
  // the repository's Prettier configuration out of the way while it runs.
  run(process.execPath, [
    path.join(path.dirname(require.resolve('swagger-typescript-api')), 'cli.mjs'),
    'generate',
    '--extract-request-params',
    '--extract-request-body',
    '--extract-response-body',
    '--extract-response-error',
    '--module-name-index',
    '1',
    '--module-name-first-tag',
    '--templates',
    path.join(root, 'script/swagger-templates'),
    '--path',
    path.join(directory, 'schema_swagger.json'),
    '--output',
    directory,
    '--name',
    'generated.ts'
  ])

  const files = [
    ['generated.ts', 'packages/types/generated.ts'],
    ['openapi_schema.json', 'docs/api-reference/openapi_schema.json']
  ]
  const generated = []
  for (const [source, target] of files) {
    const filename = path.join(root, target)
    const content = await prettier.format(readFileSync(path.join(directory, source), 'utf8'), {
      ...(await prettier.resolveConfig(filename)),
      filepath: filename
    })
    generated.push({ filename, target, content })
  }
  // Generate and format both outputs before replacing either tracked file.
  for (const { filename, target, content } of generated) {
    if (existsSync(filename) && readFileSync(filename, 'utf8') === content) continue
    if (values.check) {
      console.error(`Generated contract differs: ${target}. Run script/gen-client and review the diff.`)
      process.exitCode = 1
    } else {
      writeFileSync(filename, content)
      console.log(`Updated ${target}`)
    }
  }
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
} finally {
  rmSync(directory, { recursive: true, force: true })
}
