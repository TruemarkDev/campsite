import { TableOfContents } from '@tiptap/extension-table-of-contents'

export { TableOfContents }
export type { TableOfContentData, TableOfContentsOptions } from '@tiptap/extension-table-of-contents'

/**
 * Keeps the same heading attributes/schema as TableOfContents without
 * assigning IDs or dispatching transactions when a read-only viewer opens.
 */
export const ReadOnlyTableOfContents = TableOfContents.extend({
  name: 'readOnlyTableOfContents',
  onCreate() {},
  onTransaction() {},
  addProseMirrorPlugins() {
    return []
  }
})
