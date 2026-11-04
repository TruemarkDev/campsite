import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import path from 'node:path'
import test from 'node:test'

const require = createRequire(import.meta.url)
const root = path.resolve(import.meta.dirname, '../..')
const cli = path.join(path.dirname(require.resolve('swagger-typescript-api')), 'cli.mjs')

test('unchanged schemas are deterministic and a response field changes only its contract', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'campsite-generation-contract-'))
  const schemaFile = path.join(directory, 'schema.json')
  const schema = {
    openapi: '3.0.0',
    info: { title: 'Generation contract regression', version: '1' },
    components: {
      schemas: { Reply: { type: 'object', required: ['value'], properties: { value: { type: 'string' } } } }
    },
    paths: {
      '/v1/organizations/{org_slug}/probe': {
        get: {
          parameters: [{ name: 'org_slug', in: 'path', required: true, schema: { type: 'string' } }],
          responses: {
            200: {
              description: 'ok',
              content: { 'application/json': { schema: { $ref: '#/components/schemas/Reply' } } }
            }
          }
        }
      }
    }
  }
  const generate = () => {
    writeFileSync(schemaFile, JSON.stringify(schema))
    const result = spawnSync(
      process.execPath,
      [
        cli,
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
        schemaFile,
        '--output',
        directory,
        '--name',
        'generated.ts',
        '--silent'
      ],
      { cwd: root, encoding: 'utf8' }
    )
    assert.equal(result.status, 0, result.stderr || result.stdout)
    return readFileSync(path.join(directory, 'generated.ts'), 'utf8')
  }
  try {
    const before = generate()
    assert.equal(generate(), before)
    schema.components.schemas.Reply.properties.canary = { type: 'boolean' }
    const after = generate()
    assert.match(after, /canary\?: boolean/)
    assert.equal(after.replace(/^[ \t]+canary\?: boolean;?\r?\n/m, ''), before)
    assert.match(after, /requestKey: \(orgSlug: string\)/)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
