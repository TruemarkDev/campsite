import { Table as BaseTable, TableCell as BaseTableCell, TableHeader as BaseTableHeader } from '@tiptap/extension-table'

const backgroundColorAttribute = {
  default: null,
  parseHTML: (element: HTMLElement) => element.style.backgroundColor || null,
  renderHTML: (attributes: { backgroundColor?: string | null }) =>
    attributes.backgroundColor ? { style: `background-color: ${attributes.backgroundColor}` } : {}
}

export const Table = BaseTable

export const TableCell = BaseTableCell.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      backgroundColor: backgroundColorAttribute
    }
  }
})

export const TableHeader = BaseTableHeader.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      backgroundColor: backgroundColorAttribute
    }
  }
})

export { TableRow } from '@tiptap/extension-table'
export type { TableOptions } from '@tiptap/extension-table'
