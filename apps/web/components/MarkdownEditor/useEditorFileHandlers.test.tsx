import { act, renderHook } from '@testing-library/react'
import { Editor } from '@tiptap/core'
import { describe, expect, it, vi } from 'vitest'

import { useEditorFileHandlers } from './useEditorFileHandlers'

describe('useEditorFileHandlers', () => {
  it('does not upload through an editor destroyed during a remount', async () => {
    const upload = vi.fn()
    const editor = { isDestroyed: true } as Editor
    const { result } = renderHook(() => useEditorFileHandlers({ editor, upload }))

    await act(() => result.current.uploadAndAppendAttachments([new File(['file'], 'file.txt')]))

    expect(upload).not.toHaveBeenCalled()
  })

  it('does not upload through the imperative note drop handler while synchronization is pending', () => {
    const upload = vi.fn()
    const editor = {
      isDestroyed: false,
      view: { posAtCoords: vi.fn(() => ({ pos: 1 })) }
    } as unknown as Editor
    const { result } = renderHook(() => useEditorFileHandlers({ editor, enabled: false, upload }))

    act(() => {
      result.current.imperativeHandlers.handleDrop({
        dataTransfer: { files: [new File(['file'], 'file.txt')] },
        clientX: 0,
        clientY: 0,
        preventDefault: vi.fn(),
        stopPropagation: vi.fn()
      } as unknown as React.DragEvent<HTMLDivElement>)
    })

    expect(upload).not.toHaveBeenCalled()
  })
})
