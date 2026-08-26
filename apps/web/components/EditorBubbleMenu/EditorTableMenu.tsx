import { Editor, useEditorState } from '@tiptap/react'
import { BubbleMenu } from '@tiptap/react/menus'

import { MinusIcon, PlusIcon, TrashIcon } from '@campsite/ui'

import { BubbleMenuButton } from './BubbleMenuButton'
import { BubbleMenuSeparator } from './BubbleMenuSeparator'

interface Props {
  editor: Editor
  appendTo?: HTMLElement
}

export function EditorTableMenu({ editor, appendTo }: Props) {
  const commandAvailability = useEditorState({
    editor,
    selector: ({ editor }) => ({
      addRowAfter: editor.can().addRowAfter(),
      addColumnAfter: editor.can().addColumnAfter(),
      deleteRow: editor.can().deleteRow(),
      deleteColumn: editor.can().deleteColumn()
    })
  })

  return (
    <BubbleMenu
      pluginKey='bubbleMenuTable'
      editor={editor}
      appendTo={appendTo}
      options={{ placement: 'bottom' }}
      shouldShow={({ editor }) => editor.isEditable && editor.isActive('table')}
    >
      <div className='text-primary bg-elevated dark flex max-w-[calc(100vw-1rem)] items-center gap-1 overflow-x-auto rounded-lg p-1 shadow-lg'>
        <BubbleMenuButton
          icon={<PlusIcon />}
          title='Row'
          tooltip='Add row below'
          aria-label='Add row below'
          onClick={() => editor.chain().focus().addRowAfter().run()}
          disabled={!commandAvailability.addRowAfter}
        />
        <BubbleMenuButton
          icon={<PlusIcon />}
          title='Column'
          tooltip='Add column to the right'
          aria-label='Add column to the right'
          onClick={() => editor.chain().focus().addColumnAfter().run()}
          disabled={!commandAvailability.addColumnAfter}
        />
        <BubbleMenuSeparator />
        <BubbleMenuButton
          icon={<MinusIcon />}
          title='Row'
          tooltip='Delete current row'
          aria-label='Delete current row'
          onClick={() => editor.chain().focus().deleteRow().run()}
          disabled={!commandAvailability.deleteRow}
        />
        <BubbleMenuButton
          icon={<MinusIcon />}
          title='Column'
          tooltip='Delete current column'
          aria-label='Delete current column'
          onClick={() => editor.chain().focus().deleteColumn().run()}
          disabled={!commandAvailability.deleteColumn}
        />
        <BubbleMenuSeparator />
        <BubbleMenuButton
          icon={<TrashIcon />}
          tooltip='Delete table'
          aria-label='Delete table'
          onClick={() => editor.chain().focus().deleteTable().run()}
        />
      </div>
    </BubbleMenu>
  )
}
