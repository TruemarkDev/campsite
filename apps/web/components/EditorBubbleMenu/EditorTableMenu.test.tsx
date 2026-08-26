import { act, fireEvent, render, screen } from '@testing-library/react'
import { Editor } from '@tiptap/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { Document, Paragraph, Table, TableCell, TableHeader, TableRow, Text } from '@campsite/editor'

import { EditorTableMenu } from './EditorTableMenu'

vi.mock('@tiptap/react/menus', () => ({
  BubbleMenu: ({ children }: { children: React.ReactNode }) => children
}))

describe('EditorTableMenu', () => {
  let editor: Editor | undefined

  beforeEach(() => {
    editor = new Editor({
      extensions: [Document, Paragraph, Text, Table, TableRow, TableHeader, TableCell],
      content: '<p>Before the table</p>'
    })
  })

  afterEach(() => editor?.destroy())

  it('reacts to table selection changes and executes every row and column command', () => {
    const instance = editor!

    render(<EditorTableMenu editor={instance} />)

    const addRow = screen.getByRole('button', { name: 'Add row below' }) as HTMLButtonElement
    const addColumn = screen.getByRole('button', { name: 'Add column to the right' }) as HTMLButtonElement
    const deleteRow = screen.getByRole('button', { name: 'Delete current row' }) as HTMLButtonElement
    const deleteColumn = screen.getByRole('button', { name: 'Delete current column' }) as HTMLButtonElement

    expect(addRow.disabled).toBe(true)
    expect(addColumn.disabled).toBe(true)
    expect(deleteRow.disabled).toBe(true)
    expect(deleteColumn.disabled).toBe(true)

    act(() => {
      instance.commands.insertTable({ rows: 2, cols: 2, withHeaderRow: false })
    })

    expect(addRow.disabled).toBe(false)
    expect(addColumn.disabled).toBe(false)
    expect(deleteRow.disabled).toBe(false)
    expect(deleteColumn.disabled).toBe(false)

    fireEvent.click(addRow)
    expect(instance.getJSON().content?.[0].content).toHaveLength(3)

    fireEvent.click(deleteRow)
    expect(instance.getJSON().content?.[0].content).toHaveLength(2)

    fireEvent.click(addColumn)
    expect(instance.state.doc.firstChild?.firstChild?.childCount).toBe(3)

    fireEvent.click(deleteColumn)
    expect(instance.state.doc.firstChild?.firstChild?.childCount).toBe(2)
  })
})
