import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

/** Keeps a text insertion point available after a table at the end of a document. */
export const TrailingParagraphAfterTable = Extension.create({
  name: 'trailingParagraphAfterTable',

  onCreate() {
    const { doc, schema, tr } = this.editor.state

    if (doc.lastChild?.type === schema.nodes.table) {
      this.editor.view.dispatch(tr.insert(doc.content.size, schema.nodes.paragraph.create()))
    }
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('trailingParagraphAfterTable'),
        appendTransaction: (transactions, _oldState, newState) => {
          if (!transactions.some((transaction) => transaction.docChanged)) return null

          const { doc, schema, tr } = newState

          if (doc.lastChild?.type !== schema.nodes.table) return null

          return tr.insert(doc.content.size, schema.nodes.paragraph.create())
        }
      })
    ]
  }
})
