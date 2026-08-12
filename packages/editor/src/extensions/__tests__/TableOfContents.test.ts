import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { getNoteExtensions } from '../../note'

describe('TableOfContents', () => {
  let editor: Editor | undefined

  afterEach(() => editor?.destroy())

  it('assigns stable heading IDs when enabled for an editor', async () => {
    editor = new Editor({
      extensions: getNoteExtensions(),
      content: '<h2>Overview</h2><h2>Details</h2>'
    })

    await new Promise((resolve) => window.setTimeout(resolve, 0))

    const firstId = editor.state.doc.child(0).attrs['data-toc-id']
    const secondId = editor.state.doc.child(1).attrs['data-toc-id']

    expect(firstId).toBeTruthy()
    expect(secondId).toBeTruthy()
    expect(secondId).not.toBe(firstId)

    editor.commands.insertContentAt(editor.state.doc.content.size, '<p>After</p>')

    expect(editor.state.doc.child(0).attrs['data-toc-id']).toBe(firstId)
  })

  it('does not mutate headings when disabled for a viewer', async () => {
    editor = new Editor({
      extensions: getNoteExtensions({ tableOfContents: { updateDocument: false } }),
      content: '<h2 id="existing" data-toc-id="existing">Existing</h2><h2>Overview</h2>'
    })

    await new Promise((resolve) => window.setTimeout(resolve, 0))

    expect(editor.state.doc.child(0).attrs['data-toc-id']).toBe('existing')
    expect(editor.state.doc.child(1).attrs['data-toc-id']).toBeNull()
    expect(editor.getHTML()).toBe(
      '<h2 id="existing" data-toc-id="existing">Existing</h2><h2>Overview</h2>'
    )
  })
})
