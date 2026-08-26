import { act, fireEvent, render, screen } from '@testing-library/react'
import { Editor } from '@tiptap/core'
import { describe, expect, it, vi } from 'vitest'

import { AiEditDialog } from './AiEditDialog'

const mocks = vi.hoisted(() => ({ mutateAsync: vi.fn() }))

vi.mock('@/hooks/useCreateNoteAiEdit', () => ({
  useCreateNoteAiEdit: () => ({ isPending: false, mutateAsync: mocks.mutateAsync })
}))
vi.mock('@campsite/ui', () => ({
  Button: ({
    children,
    loading: _loading,
    ...props
  }: React.ButtonHTMLAttributes<HTMLButtonElement> & { loading?: boolean }) => <button {...props}>{children}</button>,
  TextField: ({ label, onChange, value }: { label: string; onChange(value: string): void; value: string }) => (
    <label>
      {label}
      <textarea value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  )
}))
vi.mock('@campsite/ui/src/Dialog', () => ({
  Root: ({ children }: { children: React.ReactNode }) => children,
  Header: ({ children }: { children: React.ReactNode }) => children,
  Title: ({ children }: { children: React.ReactNode }) => children,
  Description: ({ children }: { children: React.ReactNode }) => children,
  Content: ({ children }: { children: React.ReactNode }) => children,
  Footer: ({ children }: { children: React.ReactNode }) => children,
  TrailingActions: ({ children }: { children: React.ReactNode }) => children
}))

describe('AiEditDialog', () => {
  it('discards an AI response when collaboration replaces the captured editor', async () => {
    let resolveResponse: (value: unknown) => void = () => undefined
    const response = new Promise((resolve) => {
      resolveResponse = resolve
    })
    const applySuggestion = vi.fn()
    const focus = vi.fn()
    const onClose = vi.fn()
    let isDestroyed = false
    const editor = {
      get isDestroyed() {
        return isDestroyed
      },
      state: {
        doc: {
          content: { size: 20 },
          textBetween: vi.fn().mockReturnValue('context')
        }
      },
      commands: { applySuggestion, focus }
    } as unknown as Editor

    mocks.mutateAsync.mockReturnValue(response)
    render(<AiEditDialog editor={editor} noteId='note-1' range={{ from: 1, to: 2 }} onClose={onClose} />)

    fireEvent.change(screen.getByLabelText('Instruction'), { target: { value: 'Rewrite this' } })
    fireEvent.click(screen.getByRole('button', { name: 'Suggest edit' }))
    isDestroyed = true

    await act(async () => {
      resolveResponse({
        actor_id: 'actor-1',
        actor_type: 'User',
        invoked_by: 'user-1',
        instruction: 'Rewrite this',
        batch_id: 'batch-1',
        created_at: '2026-08-27T00:00:00Z',
        operations: [{ type: 'replace_range', text: 'Updated' }]
      })
      await response
    })

    expect(applySuggestion).not.toHaveBeenCalled()
    expect(focus).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
  })
})
