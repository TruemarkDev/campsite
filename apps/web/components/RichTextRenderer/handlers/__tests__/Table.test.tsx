import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'

import { Table, TableCell, TableHeader, TableRow } from '@/components/RichTextRenderer/handlers/Table'

const node = {
  type: 'table',
  content: [
    {
      type: 'tableRow',
      content: [
        { type: 'tableHeader', attrs: { colspan: 1, colwidth: [180] } },
        { type: 'tableHeader', attrs: { colspan: 1, colwidth: [240] } }
      ]
    }
  ]
}

describe('Table handlers', () => {
  it('renders semantic, responsive table markup', () => {
    const { container } = render(
      <Table node={node}>
        <TableRow node={{ type: 'tableRow' }}>
          <TableHeader node={{ type: 'tableHeader' }}>Name</TableHeader>
          <TableHeader node={{ type: 'tableHeader' }}>Status</TableHeader>
        </TableRow>
        <TableRow node={{ type: 'tableRow' }}>
          <TableCell node={{ type: 'tableCell' }}>Editor</TableCell>
          <TableCell node={{ type: 'tableCell' }}>Ready</TableCell>
        </TableRow>
      </Table>
    )

    expect(container.querySelector('.rich-text-table-wrapper')).not.toBeNull()
    expect(container.querySelectorAll('table')).toHaveLength(1)
    expect(container.querySelectorAll('tr')).toHaveLength(2)
    expect(container.querySelectorAll('th[scope="col"]')).toHaveLength(2)
    expect(container.querySelectorAll('td')).toHaveLength(2)
    expect(container.querySelectorAll('col')).toHaveLength(2)
    expect(container.querySelector('col')?.style.width).toBe('180px')
    expect(container.textContent).toBe('NameStatusEditorReady')
  })
})
