import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import test from 'node:test'

const root = resolve(import.meta.dirname, '../..')

test('preserves positional path arguments while combining query parameters', () => {
  const directory = mkdtempSync(join(tmpdir(), 'campsite-api-client-'))
  const schemaPath = join(directory, 'schema.json')

  writeFileSync(
    schemaPath,
    JSON.stringify({
      openapi: '3.0.0',
      info: { title: 'Template regression', version: '1' },
      paths: {
        '/v1/organizations/{org_slug}/projects/{project_id}/archive': {
          patch: {
            parameters: [
              { name: 'org_slug', in: 'path', required: true, schema: { type: 'string' } },
              { name: 'project_id', in: 'path', required: true, schema: { type: 'string' } }
            ],
            requestBody: {
              required: true,
              content: { 'application/json': { schema: { type: 'object', properties: { reason: { type: 'string' } } } } }
            },
            responses: { 200: { description: 'ok', content: { 'application/json': { schema: { type: 'object' } } } } }
          }
        },
        '/v1/organizations/{org_slug}/gifs': {
          get: {
            parameters: [
              { name: 'org_slug', in: 'path', required: true, schema: { type: 'string' } },
              { name: 'q', in: 'query', required: false, schema: { type: 'string' } }
            ],
            responses: { 200: { description: 'ok', content: { 'application/json': { schema: { type: 'object' } } } } }
          }
        }
      }
    })
  )

  try {
    const result = spawnSync(
      'pnpm',
      [
        'swagger-typescript-api',
        'generate',
        '--extract-request-params',
        '--extract-request-body',
        '--extract-response-body',
        '--module-name-index',
        '1',
        '--module-name-first-tag',
        'true',
        '--templates',
        join(root, 'script/swagger-templates'),
        '--path',
        schemaPath,
        '--output',
        directory,
        '--name',
        'generated.ts',
        '--silent'
      ],
      { cwd: root, encoding: 'utf8' }
    )

    assert.equal(result.status, 0, result.stderr || result.stdout)

    const generated = readFileSync(join(directory, 'generated.ts'), 'utf8')
    assert.match(generated, /requestKey: \(orgSlug: string, projectId: string\)/)
    assert.match(generated, /request:\s*\(\s*orgSlug: string,\s*projectId: string,\s*data: /)
    assert.match(generated, /requestKey: \(params: GetGifsParams\)/)
    assert.match(generated, /request:\s*\(\s*\{ orgSlug, \.\.\.query \}: GetGifsParams/)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
