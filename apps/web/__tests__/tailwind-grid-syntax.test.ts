import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'

const SOURCE_EXTENSIONS = new Set(['.css', '.js', '.jsx', '.ts', '.tsx'])
const SKIPPED_DIRECTORIES = new Set(['.next', 'dist', 'node_modules', 'storybook-static'])

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isDirectory()) {
      return SKIPPED_DIRECTORIES.has(entry.name) ? [] : sourceFiles(path.join(directory, entry.name))
    }

    const file = path.join(directory, entry.name)

    return SOURCE_EXTENSIONS.has(path.extname(file)) ? [file] : []
  })
}

function hasTopLevelComma(value: string) {
  let parentheses = 0

  for (const character of value) {
    if (character === '(') parentheses += 1
    if (character === ')') parentheses -= 1
    if (character === ',' && parentheses === 0) return true
  }

  return false
}

describe('Tailwind arbitrary grid track syntax', () => {
  it('uses underscores rather than top-level commas between grid tracks', () => {
    const repositoryRoot = path.resolve(import.meta.dirname, '../../..')
    const files = [path.join(repositoryRoot, 'apps'), path.join(repositoryRoot, 'packages')].flatMap(sourceFiles)
    const offenders = files.flatMap((file) => {
      const source = readFileSync(file, 'utf8')

      return [...source.matchAll(/grid-(?:cols|rows)-\[([^\]]+)]/g)]
        .filter((match) => hasTopLevelComma(match[1]))
        .map((match) => `${path.relative(repositoryRoot, file)}: ${match[0]}`)
    })

    expect(offenders).toEqual([])
  })
})
