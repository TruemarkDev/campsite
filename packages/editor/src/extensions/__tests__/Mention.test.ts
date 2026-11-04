import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { editorTestSetup } from '../../utils/editorTestSetup'
import * as E from '../index'

editorTestSetup()

const editors: Editor[] = []

afterEach(() => editors.splice(0).forEach((editor) => editor.destroy()))

function setupEditor(content: string) {
  const editor = new Editor({
    extensions: [E.Document, E.Text, E.Paragraph, E.Mention],
    content
  })
  editors.push(editor)
  return editor
}

describe('Mention', () => {
  it('inserts before the paragraph', () => {
    const editor = setupEditor('<p>Foo bar</p>')
    // mimic TipTap Mention command
    // https://github.com/ueberdosis/tiptap/blob/main/packages/extension-mention/src/mention.ts#L48-L61

    editor
      .chain()
      .focus()
      .insertContent([
        {
          type: E.Mention.name,
          attrs: { id: 'm-id', label: 'm-label', username: 'm-username' }
        },
        { type: 'text', text: ' ' }
      ])
      .run()

    // match against HTML as our API depends on the HTML structure not changing
    expect(editor.getHTML()).toMatchSnapshot()
  })
})
