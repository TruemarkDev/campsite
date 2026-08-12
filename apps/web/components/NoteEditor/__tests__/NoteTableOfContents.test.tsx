import { fireEvent, render } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { NoteTableOfContents } from '@/components/NoteEditor/NoteTableOfContents'

describe('NoteTableOfContents', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'matchMedia',
      vi.fn().mockReturnValue({ matches: false })
    )
    window.history.replaceState(null, '', '/')
  })

  it('uses fragment links and uniquely identifies the active section', () => {
    const { getByRole } = render(
      <NoteTableOfContents
        anchors={[
          { id: 'overview', level: 1, textContent: 'Overview' },
          { id: 'details', level: 2, textContent: 'Details', isActive: true }
        ]}
      />
    )

    expect(getByRole('navigation', { name: 'Table of contents' })).not.toBeNull()
    expect(getByRole('link', { name: 'Overview' }).getAttribute('href')).toBe('#overview')
    expect(getByRole('link', { name: 'Details' }).getAttribute('aria-current')).toBe('location')
  })

  it('focuses the heading and honors reduced motion', () => {
    const heading = document.createElement('h2')
    const scrollIntoView = vi.fn()

    heading.id = 'details'
    heading.tabIndex = -1
    heading.scrollIntoView = scrollIntoView
    document.body.appendChild(heading)
    vi.mocked(window.matchMedia).mockReturnValue({ matches: true } as MediaQueryList)

    const { getByRole } = render(
      <NoteTableOfContents
        anchors={[
          { id: 'overview', level: 1, textContent: 'Overview' },
          { id: 'details', level: 2, textContent: 'Details', dom: heading }
        ]}
      />
    )

    fireEvent.click(getByRole('link', { name: 'Details' }))

    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: 'auto', block: 'start' })
    expect(document.activeElement).toBe(heading)
    heading.remove()
  })
})
