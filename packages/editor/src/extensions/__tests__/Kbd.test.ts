import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { editorTestSetup } from '../../utils/editorTestSetup'
import * as E from '../index'

editorTestSetup()

const editors: Editor[] = []

afterEach(() => editors.splice(0).forEach((editor) => editor.destroy()))

function setupEditor(content: string) {
  const editor = new Editor({
    extensions: [E.Document, E.Text, E.Paragraph, E.Kbd],
    content
  })
  editors.push(editor)
  return editor
}

describe('Kbd', () => {
  it('parses kbd html', () => {
    const editor = setupEditor('<p><kbd>Ctrl+A</kbd></p>')
    const html = editor.getHTML()

    expect(html).toBe('<p><kbd>Ctrl+A</kbd></p>')
  })
})
