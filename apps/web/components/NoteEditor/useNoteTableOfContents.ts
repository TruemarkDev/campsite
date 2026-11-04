import { useEffect, useState } from 'react'
import { Editor } from '@tiptap/core'

import { getImmediateScrollableNode } from '@/utils/scroll'

import type { NoteTableOfContentsItem } from './NoteTableOfContents'

function itemsAreEqual(left: NoteTableOfContentsItem[], right: NoteTableOfContentsItem[]) {
  return (
    left.length === right.length &&
    left.every((item, index) => {
      const other = right[index]

      return (
        item.id === other?.id &&
        item.level === other.level &&
        item.textContent === other.textContent &&
        item.isActive === other.isActive &&
        item.dom === other.dom
      )
    })
  )
}

export function useNoteTableOfContents(editor: Editor) {
  const [items, setItems] = useState<NoteTableOfContentsItem[]>([])

  useEffect(() => {
    let frame: number | undefined
    const scrollParent = getImmediateScrollableNode(editor.view.dom)

    const update = () => {
      const next: NoteTableOfContentsItem[] = []
      const containerTop = scrollParent instanceof HTMLElement ? scrollParent.getBoundingClientRect().top : 0
      let activeId: string | undefined

      editor.state.doc.descendants((node, pos) => {
        if (node.type.name !== 'heading' || node.textContent.trim().length === 0) return

        const dom = editor.view.nodeDOM(pos) as HTMLHeadingElement | null

        if (!dom) return

        const id = node.attrs.id || node.attrs['data-toc-id'] || `note-heading-${pos}`

        // Viewer-mode TOCs are derived without dispatching a document
        // transaction. Setting the DOM id enables fragment navigation while
        // leaving the persisted ProseMirror/Yjs document untouched.
        if (dom.id !== id) dom.id = id
        if (dom.getBoundingClientRect().top <= containerTop + 16) activeId = id

        next.push({
          id,
          level: Number(node.attrs.level || 1),
          textContent: node.textContent,
          isActive: false,
          dom
        })
      })

      const normalized = next.map((item) => ({ ...item, isActive: item.id === activeId }))

      setItems((current) => (itemsAreEqual(current, normalized) ? current : normalized))
    }

    const scheduleUpdate = () => {
      if (frame !== undefined) cancelAnimationFrame(frame)
      frame = requestAnimationFrame(update)
    }

    editor.on('create', scheduleUpdate)
    editor.on('transaction', scheduleUpdate)
    scrollParent.addEventListener('scroll', scheduleUpdate, { passive: true })
    scheduleUpdate()

    return () => {
      editor.off('create', scheduleUpdate)
      editor.off('transaction', scheduleUpdate)
      scrollParent.removeEventListener('scroll', scheduleUpdate)
      if (frame !== undefined) cancelAnimationFrame(frame)
    }
  }, [editor])

  return items
}
