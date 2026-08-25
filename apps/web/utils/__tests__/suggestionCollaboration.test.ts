import { Editor } from '@tiptap/core'
import Collaboration from '@tiptap/extension-collaboration'
import { describe, expect, it } from 'vitest'
import * as Y from 'yjs'

import { Document, Paragraph, SuggestionDelete, SuggestionInsert, Text } from '@campsite/editor'

const suggestion =
  '<p>Keep <span data-suggestion-delete="" data-actor-id="assistant" data-actor-type="ai" ' +
  'data-batch-id="batch-1" data-created-at="2026-08-25T00:00:00Z">old</span>' +
  '<span data-suggestion-insert="" data-actor-id="assistant" data-actor-type="ai" ' +
  'data-batch-id="batch-1" data-created-at="2026-08-25T00:00:00Z">new</span> text</p>'

function collaborativeEditor(document: Y.Doc) {
  return new Editor({
    extensions: [Document, Paragraph, Text, SuggestionInsert, SuggestionDelete, Collaboration.configure({ document })]
  })
}

describe('suggestion resolution collaboration', () => {
  it('converges when two disconnected Yjs clients resolve the same batch concurrently', () => {
    const documentA = new Y.Doc()
    const editorA = collaborativeEditor(documentA)

    editorA.commands.setContent(suggestion)

    const documentB = new Y.Doc()

    Y.applyUpdate(documentB, Y.encodeStateAsUpdate(documentA))
    const editorB = collaborativeEditor(documentB)
    const updatesA: Uint8Array[] = []
    const updatesB: Uint8Array[] = []

    documentA.on('update', (update: Uint8Array) => updatesA.push(update))
    documentB.on('update', (update: Uint8Array) => updatesB.push(update))

    expect(editorA.commands.acceptSuggestion('batch-1')).toBe(true)
    expect(editorB.commands.acceptSuggestion('batch-1')).toBe(true)

    updatesA.forEach((update) => Y.applyUpdate(documentB, update))
    updatesB.forEach((update) => Y.applyUpdate(documentA, update))

    expect(editorA.getJSON()).toEqual(editorB.getJSON())
    expect(editorA.getText()).toBe('Keep new text')
    expect(editorA.getHTML()).not.toContain('data-suggestion-')

    editorA.destroy()
    editorB.destroy()
    documentA.destroy()
    documentB.destroy()
  })
})
