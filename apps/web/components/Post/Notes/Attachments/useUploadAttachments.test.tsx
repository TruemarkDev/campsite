import { act, renderHook } from '@testing-library/react'
import { Editor } from '@tiptap/core'
import { describe, expect, it, vi } from 'vitest'

import { useUploadNoteAttachments } from './useUploadAttachments'

const mocks = vi.hoisted(() => ({
  captureException: vi.fn(),
  createAttachment: vi.fn(),
  createFileUploadPipeline: vi.fn(),
  setTypedQueryData: vi.fn(),
  updateGalleryItem: vi.fn(),
  updateAttachment: vi.fn(),
  insertGallery: vi.fn(),
  insertAttachments: vi.fn()
}))

vi.mock('@sentry/nextjs', () => ({ captureException: mocks.captureException }))
vi.mock('@tanstack/react-query', () => ({ useQueryClient: () => ({}) }))
vi.mock('@campsite/config', () => ({ ONE_GB: 1_073_741_824 }))
vi.mock('@/components/Post/utils', () => ({ MEDIA_GALLERY_VALIDATORS: [() => false] }))
vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'acme' }) }))
vi.mock('@/hooks/useCreateAttachment', () => ({
  useCreateAttachment: () => ({ mutateAsync: mocks.createAttachment })
}))
vi.mock('@/hooks/useCreateNoteAttachment', () => ({
  useCreateNoteAttachment: () => ({ mutateAsync: mocks.createAttachment })
}))
vi.mock('@/hooks/useGetCurrentOrganization', () => ({
  useGetCurrentOrganization: () => ({ data: { limits: { file_size_bytes: 10_000 } } })
}))
vi.mock('@/utils/createFileUploadPipeline', () => ({
  createFileUploadPipeline: mocks.createFileUploadPipeline
}))
vi.mock('@/utils/queryClient', () => ({
  apiClient: { organizations: { getAttachmentsById: () => ({ requestKey: vi.fn(() => ['attachment']) }) } },
  getTypedQueryData: vi.fn(),
  setTypedQueryData: mocks.setTypedQueryData
}))

describe('useUploadNoteAttachments', () => {
  it('does not issue editor commands after a collaboration remount', async () => {
    let pipelineOptions: {
      onAppend(attachments: unknown[]): void
      onUpdate(id: string, value: { width: number; height: number }): void
    } | null = null
    let resolvePipeline: (ids: string[]) => void = () => undefined
    const pipelinePromise = new Promise<string[]>((resolve) => {
      resolvePipeline = resolve
    })
    let isDestroyed = false
    const editor = {
      get isDestroyed() {
        return isDestroyed
      },
      commands: {
        updateGalleryItem: mocks.updateGalleryItem,
        updateAttachment: mocks.updateAttachment,
        insertGallery: mocks.insertGallery,
        insertAttachments: mocks.insertAttachments
      }
    } as unknown as Editor

    mocks.createFileUploadPipeline.mockImplementation((options) => {
      pipelineOptions = options
      return pipelinePromise
    })
    const { result } = renderHook(() => useUploadNoteAttachments({ noteId: 'note-1' }))
    const uploadPromise = result.current({ files: [new File(['file'], 'file.txt')], editor })

    isDestroyed = true
    pipelineOptions!.onAppend([{ id: 'optimistic-1' }])
    pipelineOptions!.onUpdate('optimistic-1', { width: 100, height: 100 })

    await act(async () => {
      resolvePipeline([])
      await uploadPromise
    })

    expect(mocks.insertGallery).not.toHaveBeenCalled()
    expect(mocks.insertAttachments).not.toHaveBeenCalled()
    expect(mocks.updateGalleryItem).not.toHaveBeenCalled()
    expect(mocks.updateAttachment).not.toHaveBeenCalled()
    expect(mocks.captureException).not.toHaveBeenCalled()
  })
})
