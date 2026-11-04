import { Editor, KeyboardShortcutCommand } from '@tiptap/core'
import TipTapListKeyMap from '@tiptap/extension-list-keymap'

import { handleBackspace } from '../utils/handleBackspace'

export const ListKeyMap = TipTapListKeyMap.extend({
  addKeyboardShortcuts() {
    // v3's Extension.extend() drops `parent` from the inferred `this` type
    const parentShortcuts = (this as unknown as { parent?: () => Record<string, KeyboardShortcutCommand> }).parent?.()

    return {
      ...parentShortcuts,
      Backspace: ({ editor }: { editor: Editor }) => {
        let handled = false

        this.options.listTypes.forEach(({ itemName, wrapperNames }) => {
          if (editor.state.schema.nodes[itemName] === undefined) {
            return
          }

          if (handleBackspace(editor, itemName, wrapperNames)) {
            handled = true
          }
        })

        return handled
      },
      'Mod-Backspace': ({ editor }: { editor: Editor }) => {
        let handled = false

        this.options.listTypes.forEach(({ itemName, wrapperNames }) => {
          if (editor.state.schema.nodes[itemName] === undefined) {
            return
          }

          if (handleBackspace(editor, itemName, wrapperNames)) {
            handled = true
          }
        })

        return handled
      }
    }
  }
})
