import { describe, expect, it } from 'vitest'

import { parseTablePaste } from '../tablePaste'

describe('parseTablePaste', () => {
  it('parses rectangular TSV and pads short rows', () => {
    expect(parseTablePaste('Name\tScore\nAda\t10\nGrace')).toEqual({
      rows: [
        ['Name', 'Score'],
        ['Ada', '10'],
        ['Grace', '']
      ]
    })
  })

  it('parses quoted CSV fields and escaped quotes', () => {
    expect(parseTablePaste('Name,Note\nAda,"Uses, ""quotes"""')).toEqual({
      rows: [
        ['Name', 'Note'],
        ['Ada', 'Uses, "quotes"']
      ]
    })
  })

  it('supports newlines inside quoted CSV fields', () => {
    expect(parseTablePaste('Name,Note\nAda,"line one\nline two"')).toEqual({
      rows: [
        ['Name', 'Note'],
        ['Ada', 'line one\nline two']
      ]
    })
  })

  it('rejects malformed or ordinary single-value clipboard text', () => {
    expect(parseTablePaste('just text')).toBeNull()
    expect(parseTablePaste('Name,"unterminated')).toBeNull()
  })
})
