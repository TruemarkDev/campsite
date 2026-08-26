import { describe, expect, it } from 'vitest'

import { sanitizeHtml } from '@/utils/sanitizeHtml'

describe('sanitizeHtml', () => {
  it('removes executable markup and unsafe URLs', () => {
    const dirty = [
      '<script>alert(1)</script>',
      '<img src="x" onerror="alert(1)">',
      '<a href="javascript:alert(1)" onclick="alert(1)">link</a>',
      '<svg><a href="javascript:alert(1)">svg</a></svg>',
      '<math><mtext>math</mtext></math>'
    ].join('')

    const clean = sanitizeHtml(dirty)

    expect(clean).not.toMatch(/script|onerror|onclick|javascript:|<svg|<math/i)
    expect(clean).toContain('<a>link</a>')
  })

  it('preserves supported rich-text structure and Campsite editor metadata', () => {
    const richText = [
      '<p><strong>Safe</strong> <a href="https://example.com" target="_blank">link</a></p>',
      '<span class="mention" data-type="mention" data-id="member-id">@Member</span>',
      '<ul class="task-list" data-type="taskList"><li data-checked="true">Done</li></ul>',
      '<resource-mention href="https://app.campsite.com/acme/posts/123"></resource-mention>'
    ].join('')

    const clean = sanitizeHtml(richText)

    expect(clean).toContain('<strong>Safe</strong>')
    expect(clean).toContain('href="https://example.com"')
    expect(clean).toContain('target="_blank"')
    expect(clean).toContain('data-type="mention"')
    expect(clean).toContain('data-checked="true"')
    expect(clean).toContain('<resource-mention')
  })

  it('normalizes absent content to an empty string', () => {
    expect(sanitizeHtml()).toBe('')
    expect(sanitizeHtml(null)).toBe('')
  })
})
