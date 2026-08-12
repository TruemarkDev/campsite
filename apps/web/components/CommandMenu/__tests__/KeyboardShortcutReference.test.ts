import { describe, expect, it } from 'vitest'

import { getShortcutReferenceEntries } from '@/components/CommandMenu/KeyboardShortcutReference'

describe('getShortcutReferenceEntries', () => {
  it('keeps described shortcuts, removes duplicates, and puts navigation first', () => {
    const hotkeys = [
      { description: 'Create post', hotkey: 'c', metadata: { category: 'Create' } },
      { description: 'Go to inbox', hotkey: 'g>i', metadata: { category: 'Navigation' } },
      { description: 'Go to inbox', hotkey: 'g>i', metadata: { category: 'Navigation' } }
    ]

    expect(getShortcutReferenceEntries(hotkeys)).toEqual([
      { category: 'Navigation', description: 'Go to inbox', hotkey: 'g>i' },
      { category: 'Create', description: 'Create post', hotkey: 'c' }
    ])
  })

  it('uses Other for shortcuts without category metadata', () => {
    expect(getShortcutReferenceEntries([{ description: 'Open menu', hotkey: 'meta+k' }])).toEqual([
      { category: 'Other', description: 'Open menu', hotkey: 'meta+k' }
    ])
  })
})
