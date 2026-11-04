import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { Document } from '../Document'
import { Paragraph } from '../Paragraph'
import { PasteHandler } from '../PasteHandler'
import { Table, TableCell, TableHeader, TableRow } from '../Table'
import { Text } from '../Text'

describe('PasteHandler table paste', () => {
  let editor: Editor | undefined

  afterEach(() => editor?.destroy())

  it('fills cells from the active cell and stays inside the table', () => {
    editor = new Editor({
      extensions: [Document, Paragraph, Text, PasteHandler, Table, TableRow, TableHeader, TableCell],
      content: '<p>Before</p>'
    })

    editor.commands.insertTable({ rows: 2, cols: 2, withHeaderRow: false })
    const event = {
      clipboardData: { getData: (type: string) => (type === 'text/plain' ? 'A\tB\nC\tD\nE\tF' : '') },
      preventDefault: () => undefined
    } as unknown as ClipboardEvent
    let handled = false

    const pastePlugin = editor.view.state.plugins.find((plugin) => plugin.key.startsWith('pasteHandler'))
    const pasteHandler = pastePlugin?.props.handlePaste

    expect(pasteHandler).toBeDefined()
    handled = pasteHandler!(editor.view, event)

    const table = editor.getJSON().content?.find((node) => node.type === 'table')
    const rows = table?.content || []

    expect(handled).toBe(true)
    expect(rows[0].content?.map((cell) => cell.content?.[0].content?.[0].text)).toEqual(['A', 'B'])
    expect(rows[1].content?.map((cell) => cell.content?.[0].content?.[0].text)).toEqual(['C', 'D'])
  })
})
