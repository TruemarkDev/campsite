import { FormEvent, useEffect, useState } from 'react'
import { Editor, Range } from '@tiptap/core'

import { Button, TextField } from '@campsite/ui'
import * as Dialog from '@campsite/ui/src/Dialog'

import { useCreateNoteAiEdit } from '@/hooks/useCreateNoteAiEdit'

interface Props {
  editor: Editor
  noteId: string
  range: Range | null
  onClose(): void
}

export function AiEditDialog({ editor, noteId, range, onClose }: Props) {
  const [instruction, setInstruction] = useState('')
  const mutation = useCreateNoteAiEdit(noteId)

  useEffect(() => {
    if (range) setInstruction('')
  }, [range])

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!range || !instruction.trim()) return

    const documentEnd = editor.state.doc.content.size
    const response = await mutation
      .mutateAsync({
        instruction: instruction.trim(),
        range,
        context: {
          selected_text: editor.state.doc.textBetween(range.from, range.to, '\n'),
          before: editor.state.doc.textBetween(Math.max(0, range.from - 2_000), range.from, '\n'),
          after: editor.state.doc.textBetween(range.to, Math.min(documentEnd, range.to + 2_000), '\n')
        }
      })
      .catch(() => null)

    if (!response) return

    const attributes = {
      actorId: response.actor_id,
      actorType: response.actor_type,
      invokedBy: response.invoked_by,
      instruction: response.instruction,
      batchId: response.batch_id,
      createdAt: response.created_at
    }

    response.operations.forEach((operation) => {
      const operationRange = operation.type === 'replace_range' ? range : { from: range.from, to: range.from }

      editor.commands.applySuggestion(operationRange, operation.text, attributes)
    })

    editor.commands.focus()
    onClose()
  }

  return (
    <Dialog.Root open={!!range} onOpenChange={(open) => !open && onClose()} size='lg'>
      <form onSubmit={submit}>
        <Dialog.Header>
          <Dialog.Title>Edit with AI</Dialog.Title>
          <Dialog.Description>
            Describe the change. The result will appear as a suggestion you can accept or reject.
          </Dialog.Description>
        </Dialog.Header>
        <Dialog.Content>
          <TextField
            id='note-ai-edit-instruction'
            name='instruction'
            label='Instruction'
            placeholder={range && range.from === range.to ? 'Draft a follow-up section…' : 'Make this more concise…'}
            value={instruction}
            onChange={setInstruction}
            maxLength={2_000}
            multiline
            minRows={3}
            autoFocus
            disabled={mutation.isPending}
          />
        </Dialog.Content>
        <Dialog.Footer>
          <Dialog.TrailingActions>
            <Button variant='flat' onClick={onClose} disabled={mutation.isPending}>
              Cancel
            </Button>
            <Button variant='primary' type='submit' loading={mutation.isPending} disabled={!instruction.trim()}>
              Suggest edit
            </Button>
          </Dialog.TrailingActions>
        </Dialog.Footer>
      </form>
    </Dialog.Root>
  )
}
