import { act, renderHook } from '@testing-library/react'
import { ChainedCommands, Editor } from '@tiptap/core'
import { describe, expect, it, vi } from 'vitest'

import { useCreateLinkAttachment } from './useCreateLinkAttachment'

const mocks = vi.hoisted(() => ({
  createAttachment: vi.fn(),
  createFigmaFileAttachment: vi.fn(),
  refetchFigmaIntegration: vi.fn(),
  setOptimisticAttachment: vi.fn(),
  updateOptimisticAttachment: vi.fn()
}))

vi.mock('@tanstack/react-query', () => ({ useQueryClient: () => ({}) }))
vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'acme' }) }))
vi.mock('@/hooks/useCreateAttachment', () => ({
  useCreateAttachment: () => ({ mutateAsync: mocks.createAttachment })
}))
vi.mock('@/hooks/useCreateFigmaFileAttachment', () => ({
  useCreateFigmaFileAttachment: () => ({ mutateAsync: mocks.createFigmaFileAttachment })
}))
vi.mock('@/hooks/useGetFigmaIntegration', () => ({
  useGetFigmaIntegration: () => ({ refetch: mocks.refetchFigmaIntegration })
}))
vi.mock('@/utils/createFileUploadPipeline', () => ({
  createOptimisticAttachment: () => ({
    id: 'optimistic-1',
    optimistic_id: 'optimistic-1',
    optimistic_file_path: null
  })
}))
vi.mock('../Post/Notes/Attachments/useUploadAttachments', () => ({
  setOptimisticAttachment: mocks.setOptimisticAttachment,
  updateOptimisticAttachment: mocks.updateOptimisticAttachment
}))
vi.mock('../Post/PostEmbeds/transformUrl', () => ({ embedType: () => null }))

describe('useCreateLinkAttachment', () => {
  it('does not update an editor replaced while link metadata is loading', async () => {
    let resolveAttachment: (value: unknown) => void = () => undefined
    const attachmentPromise = new Promise((resolve) => {
      resolveAttachment = resolve
    })
    let isDestroyed = false
    const updateAttachment = vi.fn()
    const insertAttachments = vi.fn()
    const editor = {
      get isDestroyed() {
        return isDestroyed
      },
      commands: { updateAttachment }
    } as unknown as Editor
    const chain = vi.fn(() => ({ insertAttachments }) as unknown as ChainedCommands)

    mocks.createAttachment.mockReturnValue(attachmentPromise)
    const { result } = renderHook(() => useCreateLinkAttachment())
    const createPromise = result.current({ url: 'https://example.com', editor, chain })

    isDestroyed = true
    await act(async () => {
      resolveAttachment({ id: 'attachment-1' })
      await createPromise
    })

    expect(insertAttachments).toHaveBeenCalledOnce()
    expect(updateAttachment).not.toHaveBeenCalled()
  })
})
