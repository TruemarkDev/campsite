import { render, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'

import MarkdownEditor from './index'

const mocks = vi.hoisted(() => ({
  createLinkAttachment: vi.fn(),
  linkOptions: {},
  upload: vi.fn()
}))

vi.mock('@campsite/ui/src/hooks', () => ({ useHasMounted: () => true }))
vi.mock('@/hooks/useCurrentUserOrOrganizationHasFeature', () => ({
  useCurrentUserOrOrganizationHasFeature: () => false
}))
vi.mock('./ControlClickLink', () => ({ useControlClickLink: () => mocks.linkOptions }))
vi.mock('./useCreateLinkAttachment', () => ({ useCreateLinkAttachment: () => mocks.createLinkAttachment }))
vi.mock('../Post/Notes/Attachments/useUploadAttachments', () => ({
  useUploadNoteAttachments: () => mocks.upload
}))
vi.mock('../EditorBubbleMenu', () => ({ EditorBubbleMenu: () => null }))
vi.mock('../CodeBlockLanguagePicker', () => ({ CodeBlockLanguagePicker: () => null }))
vi.mock('../Post/Notes/SlashCommand', () => ({ SlashCommand: () => null }))
vi.mock('./MentionList', () => ({ MentionList: () => null }))
vi.mock('./ResourceMentionList', () => ({ ResourceMentionList: () => null }))
vi.mock('./ReactionList', () => ({ ReactionList: () => null }))
vi.mock('@/components/InlineResourceMentionRenderer', () => ({ InlineResourceMentionRenderer: () => null }))
vi.mock('../Post/MediaGalleryRenderer', () => ({ MediaGalleryRenderer: () => null }))
vi.mock('../Post/PostInlineAttachmentRenderer', () => ({ PostInlineAttachmentRenderer: () => null }))
vi.mock('../Post/LinkUnfurlRenderer', () => ({ LinkUnfurlRenderer: () => null }))
vi.mock('../RichTextRenderer/handlers/RelativeTime', () => ({ InlineRelativeTimeRenderer: () => null }))

describe('MarkdownEditor lifecycle', () => {
  it('updates a dynamic placeholder without replacing or destroying the editor', async () => {
    const { container, rerender } = render(
      <MarkdownEditor placeholder='Write a comment...' disableSlashCommand disableMentions disableReactions />
    )
    const editorElement = container.querySelector('[contenteditable="true"]')

    expect(editorElement).not.toBeNull()
    expect(container.querySelector('[data-placeholder="Write a comment..."]')).not.toBeNull()

    expect(() =>
      rerender(<MarkdownEditor placeholder='Write a reply...' disableSlashCommand disableMentions disableReactions />)
    ).not.toThrow()

    await waitFor(() => expect(container.querySelector('[data-placeholder="Write a reply..."]')).not.toBeNull())
    expect(container.querySelector('[contenteditable="true"]')).toBe(editorElement)
  })
})
