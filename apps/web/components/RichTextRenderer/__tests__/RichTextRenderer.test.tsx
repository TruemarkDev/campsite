import { describe, expect, it } from 'vitest'

import { getNoteExtensions } from '@campsite/editor'

import { prepareRichTextContent } from '@/components/RichTextRenderer/content'

describe('prepareRichTextContent', () => {
  it('preserves table nodes from persisted HTML', () => {
    const content = `
      <table><tbody>
        <tr><th><p>Name</p></th><th><p>Status</p></th></tr>
        <tr><td><p>Editor</p></td><td><p>Ready</p></td></tr>
      </tbody></table>
    `
    const { output } = prepareRichTextContent(content, getNoteExtensions())
    const table = output.content?.[0]

    expect(table?.type).toBe('table')
    expect(table?.content).toHaveLength(2)
  })

  it('provides unique fragment targets for headings', () => {
    const content = '<h2>Overview</h2><h2>Overview</h2>'
    const { headings, output } = prepareRichTextContent(content, getNoteExtensions())

    expect(headings.map((heading) => heading.id)).toEqual(['overview', 'overview-2'])
    expect(output.content?.[0]?.attrs?.id).toBe('overview')
  })

  it('renders effective content when suggestion marks are unresolved', () => {
    const content = `<p>Keep <span data-suggestion-delete="" data-actor-id="assistant" data-actor-type="ai" data-batch-id="one" data-created-at="2026-08-25T00:00:00Z">old</span><span data-suggestion-insert="" data-actor-id="assistant" data-actor-type="ai" data-batch-id="one" data-created-at="2026-08-25T00:00:00Z">new</span></p>`
    const { output } = prepareRichTextContent(content, getNoteExtensions())
    const textNodes = output.content?.[0]?.content

    expect(textNodes?.map((node) => node.text).join('')).toBe('Keep new')
    expect(textNodes?.flatMap((node) => node.marks || [])).toEqual([])
  })
})
