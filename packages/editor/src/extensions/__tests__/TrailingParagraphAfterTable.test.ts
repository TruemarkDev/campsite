import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { Document } from '../Document'
import { Paragraph } from '../Paragraph'
import { Table, TableCell, TableHeader, TableRow } from '../Table'
import { Text } from '../Text'
import { TrailingParagraphAfterTable } from '../TrailingParagraphAfterTable'

describe('TrailingParagraphAfterTable', () => {
  let editor: Editor | undefined

  afterEach(() => editor?.destroy())

  function createEditor(content = '<p>Before</p>') {
    editor = new Editor({
      extensions: [Document, Text, Paragraph, Table, TableRow, TableHeader, TableCell, TrailingParagraphAfterTable],
      content
    })

    return editor
  }

  it('adds an insertable paragraph after a table at the end of the document', () => {
    const instance = createEditor()

    instance.chain().focus('end').insertTable({ rows: 2, cols: 2, withHeaderRow: true }).run()

    expect(instance.state.doc.lastChild?.type.name).toBe('paragraph')
    expect(instance.state.doc.lastChild?.textContent).toBe('')
    expect(instance.state.doc.childCount).toBe(3)
  })

  it('does not add another paragraph when the table already has trailing content', () => {
    const instance = createEditor('<table><tbody><tr><td><p>Cell</p></td></tr></tbody></table><p>After</p>')

    expect(instance.state.doc.childCount).toBe(2)
    expect(instance.state.doc.lastChild?.textContent).toBe('After')
  })

  it('adds a trailing paragraph when initial content ends with a table', async () => {
    const instance = createEditor('<table><tbody><tr><td><p>Cell</p></td></tr></tbody></table>')

    await new Promise((resolve) => window.setTimeout(resolve, 0))

    expect(instance.state.doc.childCount).toBe(2)
    expect(instance.state.doc.lastChild?.type.name).toBe('paragraph')
  })

  it('supports adding rows and columns from a table cell selection', () => {
    const instance = createEditor()

    instance.chain().focus('end').insertTable({ rows: 2, cols: 2, withHeaderRow: true }).run()
    instance.commands.addRowAfter()
    instance.commands.addColumnAfter()

    const table = instance.state.doc.child(1)

    expect(table.childCount).toBe(3)
    expect(table.firstChild?.childCount).toBe(3)
  })

  it('preserves resized column widths through HTML serialization', async () => {
    const instance = createEditor(
      '<table><tbody><tr><td colwidth="180"><p>Wide</p></td><td colwidth="240"><p>Wider</p></td></tr></tbody></table>'
    )

    await new Promise((resolve) => window.setTimeout(resolve, 0))

    expect(instance.state.doc.firstChild?.firstChild?.child(0).attrs.colwidth).toEqual([180])
    expect(instance.state.doc.firstChild?.firstChild?.child(1).attrs.colwidth).toEqual([240])
    expect(instance.getHTML()).toContain('colwidth="180"')
    expect(instance.getHTML()).toContain('colwidth="240"')
  })
})
