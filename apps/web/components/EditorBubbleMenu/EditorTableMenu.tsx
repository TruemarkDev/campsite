import { Editor } from '@tiptap/react'
import { BubbleMenu } from '@tiptap/react/menus'

import { MinusIcon, PlusIcon, TrashIcon } from '@campsite/ui'

import { BubbleMenuButton } from './BubbleMenuButton'
import { BubbleMenuSeparator } from './BubbleMenuSeparator'

interface Props {
  editor: Editor
  appendTo?: HTMLElement
}

export function EditorTableMenu({ editor, appendTo }: Props) {
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
          disabled={!editor.can().addRowAfter()}
        />
        <BubbleMenuButton
          icon={<PlusIcon />}
          title='Column'
          tooltip='Add column to the right'
          aria-label='Add column to the right'
          onClick={() => editor.chain().focus().addColumnAfter().run()}
          disabled={!editor.can().addColumnAfter()}
        />
        <BubbleMenuSeparator />
        <BubbleMenuButton
          icon={<MinusIcon />}
          title='Row'
          tooltip='Delete current row'
          aria-label='Delete current row'
          onClick={() => editor.chain().focus().deleteRow().run()}
          disabled={!editor.can().deleteRow()}
        />
        <BubbleMenuButton
          icon={<MinusIcon />}
          title='Column'
          tooltip='Delete current column'
          aria-label='Delete current column'
          onClick={() => editor.chain().focus().deleteColumn().run()}
          disabled={!editor.can().deleteColumn()}
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
