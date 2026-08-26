import { useEffect } from 'react'
import { HocuspocusProvider } from '@hocuspocus/provider'
import { render, waitFor } from '@testing-library/react'
import { Editor, Extension } from '@tiptap/core'
import { describe, expect, it, vi } from 'vitest'

import { EditorTableMenu } from '@/components/EditorBubbleMenu/EditorTableMenu'

import { useNoteEditor } from './useNoteEditor'

const mocks = vi.hoisted(() => ({ linkOptions: {} }))

vi.mock('@tiptap/extension-collaboration', () => ({
  default: Extension.create({ name: 'testCollaboration' })
}))
vi.mock('@tiptap/extension-collaboration-caret', () => ({
  default: Extension.create({ name: 'testCollaborationCaret' })
}))
vi.mock('@tiptap/react/menus', () => ({
  BubbleMenu: ({ children }: { children: React.ReactNode }) => children
}))
vi.mock('@/components/InlineResourceMentionRenderer', () => ({ InlineResourceMentionRenderer: () => null }))
vi.mock('@/components/MarkdownEditor/ControlClickLink', () => ({
  useControlClickLink: () => mocks.linkOptions
}))
vi.mock('@/components/Post/MediaGalleryRenderer', () => ({ MediaGalleryRenderer: () => null }))
vi.mock('@/components/RichTextRenderer/handlers/RelativeTime', () => ({ InlineRelativeTimeRenderer: () => null }))
vi.mock('@/hooks/useCurrentUserOrOrganizationHasFeature', () => ({
  useCurrentUserOrOrganizationHasFeature: () => false
}))
vi.mock('@/hooks/useGetCurrentUser', () => ({ useGetCurrentUser: () => ({ data: null }) }))
vi.mock('../LinkUnfurlRenderer', () => ({ LinkUnfurlRenderer: () => null }))
vi.mock('./Attachments/NoteAttachmentRenderer', () => ({ NoteAttachmentRenderer: () => null }))

function EditorHarness({
  provider,
  onEditor
}: {
  provider: HocuspocusProvider | null
  onEditor(editor: Editor): void
}) {
  const editor = useNoteEditor({ content: '<p>Note</p>', editable: 'all', provider })

  useEffect(() => onEditor(editor), [editor, onEditor])

  return <EditorTableMenu editor={editor} />
}

describe('useNoteEditor lifecycle', () => {
  it('replaces the local editor with a provider-backed editor without rendering the destroyed instance', async () => {
    const editors: Editor[] = []
    const onEditor = (editor: Editor) => {
      editors.push(editor)
    }
    const { rerender, unmount } = render(<EditorHarness provider={null} onEditor={onEditor} />)
    const localEditor = editors[0]

    expect(localEditor.isDestroyed).toBe(false)

    expect(() =>
      rerender(<EditorHarness provider={{ document: {} } as unknown as HocuspocusProvider} onEditor={onEditor} />)
    ).not.toThrow()

    await waitFor(() => expect(editors).toHaveLength(2))
    expect(localEditor.isDestroyed).toBe(true)
    expect(editors[1].isDestroyed).toBe(false)

    unmount()
  })
})
