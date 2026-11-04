import { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { COMMANDS } from './SlashCommand'

vi.mock('@/components/SuggestionList', () => ({
  SuggestionItem: () => null,
  SuggestionRoot: ({ children }: { children: React.ReactNode }) => children
}))

describe('SlashCommand lifecycle', () => {
  afterEach(() => vi.useRealTimers())

  it('does not run a delayed toggle callback after the editor is destroyed', () => {
    vi.useFakeTimers()
    const run = vi.fn()
    const nodeDOM = vi.fn()
    const chain = {
      focus: vi.fn(() => chain),
      deleteRange: vi.fn(() => chain),
      setDetails: vi.fn(() => chain),
      run
    }
    const editor = {
      isDestroyed: false,
      chain: vi.fn(() => chain),
      view: { nodeDOM }
    } as unknown as Editor
    const command = COMMANDS.find((item) => item.title === 'Toggle section')?.command

    expect(typeof command).toBe('function')
    if (typeof command !== 'function') return

    command({ editor, range: { from: 1, to: 1 } })
    Object.defineProperty(editor, 'isDestroyed', { value: true })
    vi.runAllTimers()

    expect(run).toHaveBeenCalledOnce()
    expect(nodeDOM).not.toHaveBeenCalled()
  })
})
