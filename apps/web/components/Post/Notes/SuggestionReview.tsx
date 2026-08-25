import { useCallback, useEffect, useMemo, useState } from 'react'
import { Editor, useEditorState } from '@tiptap/react'

import {
  Button,
  CheckIcon,
  CONTAINER_STYLES,
  Popover,
  PopoverContent,
  PopoverElementAnchor,
  PopoverPortal,
  SparklesIcon,
  TrashIcon,
  UIText
} from '@campsite/ui'
import { cn } from '@campsite/ui/src/utils'

import { useCreateNoteSuggestionResolution } from '@/hooks/useCreateNoteSuggestionResolution'

interface SuggestionSummary {
  actorId: string
  actorType: string
  batchId: string
  invokedBy?: string | null
  instruction?: string | null
}

function suggestionsIn(editor: Editor | null): SuggestionSummary[] {
  if (!editor) return []

  const suggestions = new Map<string, SuggestionSummary>()

  editor.state.doc.descendants((node) => {
    node.marks.forEach((mark) => {
      if (mark.type.name !== 'suggestionInsert' && mark.type.name !== 'suggestionDelete') return
      if (!mark.attrs.batchId || suggestions.has(mark.attrs.batchId)) return

      suggestions.set(mark.attrs.batchId, {
        actorId: mark.attrs.actorId,
        actorType: mark.attrs.actorType,
        batchId: mark.attrs.batchId,
        invokedBy: mark.attrs.invokedBy,
        instruction: mark.attrs.instruction
      })
    })
  })

  return Array.from(suggestions.values())
}

function suggestionElement(target: EventTarget | null) {
  if (!(target instanceof Element)) return null

  return target.closest<HTMLElement>('[data-suggestion-insert], [data-suggestion-delete]')
}

function rangeForSuggestion(editor: Editor, batchId: string) {
  let result: { from: number; to: number } | undefined

  editor.state.doc.descendants((node, position) => {
    if (node.marks.some((mark) => mark.attrs.batchId === batchId)) {
      result = { from: position, to: position + node.nodeSize }
      return false
    }
  })

  return result
}

interface Props {
  editor: Editor | null
  noteId: string
}

export function SuggestionReview({ editor, noteId }: Props) {
  const { mutate: recordResolution } = useCreateNoteSuggestionResolution(noteId)
  const editorSuggestions = useEditorState({ editor, selector: ({ editor }) => suggestionsIn(editor) })
  const suggestions = useMemo(() => editorSuggestions || [], [editorSuggestions])
  const [activeBatchId, setActiveBatchId] = useState<string | null>(null)
  const [anchor, setAnchor] = useState<HTMLElement | null>(null)
  const activeSuggestion = useMemo(
    () => suggestions.find((suggestion) => suggestion.batchId === activeBatchId),
    [activeBatchId, suggestions]
  )

  const activateElement = useCallback((element: HTMLElement | null) => {
    const batchId = element?.dataset.batchId

    if (!element || !batchId) return
    setActiveBatchId(batchId)
    setAnchor(element)
  }, [])

  useEffect(() => {
    if (!editor) return

    const root = editor.view.dom
    const onMouseOver = (event: MouseEvent) => activateElement(suggestionElement(event.target))
    const onSelectionUpdate = () => {
      const { from } = editor.state.selection
      const dom = editor.view.domAtPos(from).node

      activateElement(suggestionElement(dom instanceof Element ? dom : dom.parentElement))
    }

    root.addEventListener('mouseover', onMouseOver)
    editor.on('selectionUpdate', onSelectionUpdate)

    return () => {
      root.removeEventListener('mouseover', onMouseOver)
      editor.off('selectionUpdate', onSelectionUpdate)
    }
  }, [activateElement, editor])

  useEffect(() => {
    if (activeBatchId && !suggestions.some((suggestion) => suggestion.batchId === activeBatchId)) {
      setActiveBatchId(null)
      setAnchor(null)
    }
  }, [activeBatchId, suggestions])

  if (!editor?.isEditable || suggestions.length === 0) return null

  const reviewSuggestion = (suggestion: SuggestionSummary) => {
    const range = rangeForSuggestion(editor, suggestion.batchId)

    if (!range) return

    editor.chain().focus().setTextSelection(range).scrollIntoView().run()
    const dom = editor.view.domAtPos(range.from).node

    setActiveBatchId(suggestion.batchId)
    setAnchor(suggestionElement(dom instanceof Element ? dom : dom.parentElement))
  }

  const resolve = (resolution: 'accept' | 'reject', batchId: string) => {
    if (resolution === 'accept') {
      editor.chain().focus().acceptSuggestion(batchId).run()
    } else {
      editor.chain().focus().rejectSuggestion(batchId).run()
    }
    recordResolution({ batch_id: batchId, resolution })
  }

  const resolveAll = (resolution: 'accept' | 'reject') => {
    suggestions.forEach(({ batchId }) => recordResolution({ batch_id: batchId, resolution }))
    if (resolution === 'accept') editor.commands.acceptAllSuggestions()
    else editor.commands.rejectAllSuggestions()
  }

  return (
    <>
      <div
        className='bg-elevated sticky top-2 z-30 mx-auto mb-2 flex w-fit max-w-[calc(100%-2rem)] items-center gap-1 rounded-full border px-2 py-1 shadow-sm'
        aria-live='polite'
      >
        <SparklesIcon size={16} />
        <UIText size='text-xs' weight='font-medium' className='px-1 whitespace-nowrap'>
          {suggestions.length} suggested {suggestions.length === 1 ? 'change' : 'changes'}
        </UIText>
        <Button size='sm' variant='plain' onClick={() => resolveAll('accept')}>
          Accept all
        </Button>
        <Button size='sm' variant='plain' onClick={() => resolveAll('reject')}>
          Reject all
        </Button>
        <Button size='sm' variant='plain' onClick={() => reviewSuggestion(suggestions[0])}>
          Review
        </Button>
      </div>

      <Popover
        open={!!activeSuggestion && !!anchor}
        onOpenChange={(open) => {
          if (!open) {
            setActiveBatchId(null)
            setAnchor(null)
          }
        }}
      >
        <PopoverElementAnchor element={anchor} asChild />
        <PopoverPortal>
          <PopoverContent
            className={cn(CONTAINER_STYLES.base, 'w-64')}
            side='top'
            align='center'
            sideOffset={6}
            avoidCollisions
          >
            {activeSuggestion && (
              <div className='bg-elevated flex flex-col gap-2 rounded-lg p-3 shadow-lg'>
                <div>
                  <UIText size='text-xs' weight='font-semibold'>
                    {['ai', 'agent'].includes(activeSuggestion.actorType) ? 'AI suggestion' : 'Suggested edit'}
                  </UIText>
                  <UIText size='text-xs' tertiary>
                    {activeSuggestion.invokedBy
                      ? `Requested by ${activeSuggestion.invokedBy}`
                      : `Proposed by ${activeSuggestion.actorId}`}
                  </UIText>
                  {activeSuggestion.instruction && (
                    <UIText size='text-xs' className='mt-1 line-clamp-3'>
                      “{activeSuggestion.instruction}”
                    </UIText>
                  )}
                </div>
                <div className='flex gap-2'>
                  <Button
                    size='sm'
                    variant='flat'
                    leftSlot={<CheckIcon />}
                    onClick={() => resolve('accept', activeSuggestion.batchId)}
                  >
                    Accept
                  </Button>
                  <Button
                    size='sm'
                    variant='plain'
                    leftSlot={<TrashIcon />}
                    onClick={() => resolve('reject', activeSuggestion.batchId)}
                  >
                    Reject
                  </Button>
                </div>
              </div>
            )}
          </PopoverContent>
        </PopoverPortal>
      </Popover>
    </>
  )
}
