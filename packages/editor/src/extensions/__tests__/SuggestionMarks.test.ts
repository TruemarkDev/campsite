import { Editor } from '@tiptap/core'
import { describe, expect, it } from 'vitest'

import { editorTestSetup } from '../../utils/editorTestSetup'
import { resolveSuggestions } from '../../utils/resolveSuggestions'
import * as E from '../index'

editorTestSetup()

const attributes = {
  actorId: 'assistant',
  actorType: 'ai',
  invokedBy: 'user-1',
  instruction: null,
  batchId: 'batch-1',
  createdAt: '2026-08-25T00:00:00Z'
}

function suggestion(kind: 'insert' | 'delete', text: string, batchId = 'batch-1') {
  const attrs = Object.entries({ ...attributes, batchId })
    .filter(([, value]) => value !== null && value !== undefined)
    .map(([key, value]) => {
      const name = key.replace(/[A-Z]/g, (character) => `-${character.toLowerCase()}`)

      return `data-${name}="${value}"`
    })
    .join(' ')

  return `<span data-suggestion-${kind}="" ${attrs}>${text}</span>`
}

function setupEditor(content: string) {
  return new Editor({
    extensions: [E.Document, E.Text, E.Paragraph, E.Bold, E.SuggestionInsert, E.SuggestionDelete],
    content
  })
}

describe('suggestion marks', () => {
  it('round-trips persisted attribution through HTML', () => {
    const editor = setupEditor(`<p>${suggestion('insert', 'new')}</p>`)

    expect(editor.getHTML()).toContain('data-suggestion-insert=""')
    expect(editor.getHTML()).toContain('data-actor-id="assistant"')
    expect(editor.getHTML()).toContain('data-batch-id="batch-1"')
    expect(editor.getJSON().content?.[0].content?.[0].marks?.[0].attrs).toEqual(attributes)
  })

  it('accepts and rejects replacement batches', () => {
    const original = `<p>Keep ${suggestion('delete', 'verbose')} ${suggestion('insert', 'short')} text</p>`
    const accepted = setupEditor(original)
    const rejected = setupEditor(original)

    expect(accepted.commands.acceptSuggestion('batch-1')).toBe(true)
    expect(accepted.getText()).toBe('Keep  short text')
    expect(accepted.getHTML()).not.toContain('data-suggestion-')

    expect(rejected.commands.rejectSuggestion('batch-1')).toBe(true)
    expect(rejected.getText()).toBe('Keep verbose  text')
    expect(rejected.getHTML()).not.toContain('data-suggestion-')
  })

  it('applies a replacement that reject restores exactly', () => {
    const editor = setupEditor('<p>Before verbose after</p>')
    const original = editor.getJSON()
    const from = 8
    const to = from + 'verbose'.length

    expect(editor.state.doc.textBetween(from, to)).toBe('verbose')
    expect(editor.commands.applySuggestion({ from, to }, 'concise', attributes)).toBe(true)
    expect(editor.getHTML()).toContain('data-suggestion-delete')
    expect(editor.getHTML()).toContain('data-suggestion-insert')

    expect(editor.commands.rejectSuggestion(attributes.batchId)).toBe(true)
    expect(editor.getJSON()).toEqual(original)
  })

  it('resolves all suggestions and is a no-op when repeated', () => {
    const editor = setupEditor(
      `<p>${suggestion('delete', 'old', 'batch-1')}${suggestion('insert', 'new', 'batch-1')} ${suggestion('insert', 'tail', 'batch-2')}</p>`
    )

    expect(editor.commands.acceptAllSuggestions()).toBe(true)
    expect(editor.getText()).toBe('new tail')
    expect(editor.commands.acceptAllSuggestions()).toBe(false)
    expect(editor.commands.rejectSuggestion('batch-1')).toBe(false)
  })

  it('preserves suggestion metadata across copy/paste HTML parsing', () => {
    const source = setupEditor(`<p>${suggestion('delete', '<strong>copy me</strong>')}</p>`)
    const pasted = setupEditor(source.getHTML())

    expect(pasted.getJSON()).toEqual(source.getJSON())
  })

  it('produces effective content without mutating the unresolved document', () => {
    const editor = setupEditor(
      `<p>Keep ${suggestion('delete', 'old')} ${suggestion('insert', '<strong>new</strong>')} text</p>`
    )
    const unresolved = editor.getJSON()

    const accepted = resolveSuggestions(unresolved, 'strip')
    const rejected = resolveSuggestions(unresolved, 'reject')

    expect(
      unresolved.content?.[0].content?.some((node) => node.marks?.some((mark) => mark.type.startsWith('suggestion')))
    ).toBe(true)
    expect(setupEditor('').commands.setContent(accepted)).toBe(true)

    const acceptedEditor = setupEditor('')
    const rejectedEditor = setupEditor('')

    acceptedEditor.commands.setContent(accepted)
    rejectedEditor.commands.setContent(rejected)

    expect(acceptedEditor.getText()).toBe('Keep  new text')
    expect(rejectedEditor.getText()).toBe('Keep old  text')
    expect(acceptedEditor.getHTML()).not.toContain('data-suggestion-')
    expect(rejectedEditor.getHTML()).not.toContain('data-suggestion-')
  })
})
