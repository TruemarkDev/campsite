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

  function insertTable(options: { rows?: number; cols?: number; withHeaderRow?: boolean } = {}) {
    const instance = editor!

    act(() => {
      instance.commands.insertTable({ rows: 2, cols: 2, withHeaderRow: false, ...options })
    })

    return instance
  }

  function tableRows(instance: Editor) {
    const table = instance.state.doc.content.content.find((node) => node.type.name === 'table')

    return table?.content.content || []
  }

  function tableCellPositions(instance: Editor) {
    const positions: number[] = []

    instance.state.doc.descendants((node, position) => {
      if (node.type.name === 'tableCell' || node.type.name === 'tableHeader') positions.push(position)
    })

    return positions
  }

  beforeEach(() => {
    editor = new Editor({
      extensions: [Document, Paragraph, Text, Table, TableRow, TableHeader, TableCell],
      content: '<p>Before the table</p>'
    })
  })

  afterEach(() => editor?.destroy())

  it('does not render for editors without table support', () => {
    editor?.destroy()
    editor = new Editor({ extensions: [Document, Paragraph, Text] })

    const { container } = render(<EditorTableMenu editor={editor} />)

    expect(container.innerHTML).toBe('')
  })

  it('survives editor destruction during a collaboration remount', () => {
    const instance = editor!
    const { rerender } = render(<EditorTableMenu editor={instance} />)

    act(() => instance.destroy())

    expect(() => rerender(<EditorTableMenu editor={instance} />)).not.toThrow()
    editor = undefined
  })

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

    insertTable()

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

  it('merges and splits a selected cell range', () => {
    const instance = insertTable()

    render(<EditorTableMenu editor={instance} />)

    const [firstCell, secondCell] = tableCellPositions(instance)

    act(() => {
      instance.commands.setCellSelection({ anchorCell: firstCell, headCell: secondCell })
    })

    fireEvent.click(screen.getByRole('button', { name: 'Merge selected cells' }))

    expect(tableRows(instance)[0].childCount).toBe(1)
    expect(tableRows(instance)[0].child(0).attrs.colspan).toBe(2)

    fireEvent.click(screen.getByRole('button', { name: 'Split cell' }))

    expect(tableRows(instance)[0].childCount).toBe(2)
    expect(tableRows(instance)[0].child(0).attrs.colspan).toBe(1)
  })

  it('toggles header rows and columns', () => {
    const instance = insertTable()

    render(<EditorTableMenu editor={instance} />)

    fireEvent.click(screen.getByRole('button', { name: 'Toggle header row' }))

    expect(tableRows(instance)[0].content.content.map((cell) => cell.type.name)).toEqual(['tableHeader', 'tableHeader'])

    fireEvent.click(screen.getByRole('button', { name: 'Toggle header column' }))

    expect(tableRows(instance).map((row) => row.content.content.map((cell) => cell.type.name))).toEqual([
      ['tableHeader', 'tableHeader'],
      ['tableHeader', 'tableCell']
    ])
  })

  it('persists cell alignment and background attributes', () => {
    const instance = insertTable()

    render(<EditorTableMenu editor={instance} />)

    fireEvent.click(screen.getByRole('button', { name: 'Align right' }))
    fireEvent.click(screen.getByRole('button', { name: 'Set cell background' }))

    expect(tableRows(instance)[0].child(0).attrs).toMatchObject({
      align: 'right',
      backgroundColor: 'var(--bg-quaternary)'
    })
    expect(instance.getHTML()).toContain('text-align: right')
    expect(instance.getHTML()).toContain('background-color: var(--bg-quaternary)')

    const clearBackground = screen.getByRole('button', { name: 'Clear cell background' }) as HTMLButtonElement

    expect(clearBackground.disabled).toBe(false)
    fireEvent.click(clearBackground)

    expect(tableRows(instance)[0].child(0).attrs.backgroundColor).toBeNull()
    expect(instance.getHTML()).not.toContain('background-color: var(--bg-quaternary)')
  })
})
