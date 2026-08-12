import { useMemo } from 'react'

import { Command, HighlightedCommandItem, KeyboardShortcut, UIText, useRegisteredLayeredHotkeys } from '@campsite/ui'
import type { RegisteredLayeredHotkey } from '@campsite/ui'

const CATEGORY_ORDER = ['Navigation', 'Create', 'View', 'Actions', 'Other']

export interface ShortcutReferenceEntry {
  category: string
  description: string
  hotkey: string
}

function categoryFor(hotkey: RegisteredLayeredHotkey) {
  const category = hotkey.metadata?.category

  return typeof category === 'string' ? category : 'Other'
}

export function getShortcutReferenceEntries(hotkeys: ReadonlyArray<RegisteredLayeredHotkey>): ShortcutReferenceEntry[] {
  const entries = new Map<string, ShortcutReferenceEntry>()

  for (const hotkey of hotkeys) {
    if (!hotkey.description) continue

    const entry = {
      category: categoryFor(hotkey),
      description: hotkey.description,
      hotkey: hotkey.hotkey
    }

    entries.set(`${entry.hotkey}:${entry.description}`, entry)
  }

  return Array.from(entries.values()).sort((a, b) => {
    const aCategory = CATEGORY_ORDER.indexOf(a.category)
    const bCategory = CATEGORY_ORDER.indexOf(b.category)
    const categoryComparison =
      (aCategory === -1 ? CATEGORY_ORDER.length : aCategory) - (bCategory === -1 ? CATEGORY_ORDER.length : bCategory)

    return categoryComparison || a.description.localeCompare(b.description)
  })
}

function displayShortcut(hotkey: string) {
  return hotkey.includes('>') ? hotkey.split('>') : hotkey
}

export function KeyboardShortcutReference() {
  const hotkeys = useRegisteredLayeredHotkeys()
  const entries = useMemo(() => getShortcutReferenceEntries(hotkeys), [hotkeys])
  const categories = Array.from(new Set(entries.map((entry) => entry.category)))

  if (entries.length === 0) {
    return (
      <Command.Empty className='text-secondary px-4 py-8 text-center text-sm'>
        No keyboard shortcuts are available in this view.
      </Command.Empty>
    )
  }

  return categories.map((category) => (
    <Command.Group heading={category} key={category}>
      {entries
        .filter((entry) => entry.category === category)
        .map((entry) => (
          <HighlightedCommandItem
            className='h-10 cursor-default gap-2 px-2'
            disableOnClick
            key={`${entry.hotkey}:${entry.description}`}
            keywords={[category, entry.hotkey]}
            value={`${entry.description} ${entry.hotkey}`}
          >
            <UIText className='min-w-0 flex-1 truncate'>{entry.description}</UIText>
            <KeyboardShortcut shortcut={displayShortcut(entry.hotkey)} />
          </HighlightedCommandItem>
        ))}
    </Command.Group>
  ))
}
