import { Editor, useEditorState } from '@tiptap/react'
import { BubbleMenu } from '@tiptap/react/menus'

import {
  ArrowDownIcon,
  ArrowLeftIcon,
  ArrowRightIcon,
  ArrowUpIcon,
  GridIcon,
  MinusIcon,
  PlusIcon,
  TextAlignLeftIcon,
  TrashIcon
} from '@campsite/ui'

import { BubbleMenuButton } from './BubbleMenuButton'
import { BubbleMenuSeparator } from './BubbleMenuSeparator'

interface Props {
  editor: Editor
  appendTo?: HTMLElement
}

export function EditorTableMenu({ editor, appendTo }: Props) {
  if (!editor.schema.nodes.table) return null

  return <EditorTableMenuContent editor={editor} appendTo={appendTo} />
}

function EditorTableMenuContent({ editor, appendTo }: Props) {
  const commandAvailability = useEditorState({
    editor,
    selector: ({ editor }) => ({
      addRowBefore: editor.can().addRowBefore(),
      addRowAfter: editor.can().addRowAfter(),
      addColumnBefore: editor.can().addColumnBefore(),
      addColumnAfter: editor.can().addColumnAfter(),
      deleteRow: editor.can().deleteRow(),
      deleteColumn: editor.can().deleteColumn(),
      mergeCells: editor.can().mergeCells(),
      splitCell: editor.can().splitCell(),
      toggleHeaderRow: editor.can().toggleHeaderRow(),
      toggleHeaderColumn: editor.can().toggleHeaderColumn(),
      setCellAttribute: editor.can().setCellAttribute('align', 'left'),
      setBackgroundColor: editor.can().setCellAttribute('backgroundColor', 'var(--bg-quaternary)'),
      clearBackgroundColor: editor.can().setCellAttribute('backgroundColor', null)
    })
  })

  const runCellAttribute = (name: string, value: string | null) =>
    editor.chain().focus().setCellAttribute(name, value).run()

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
          icon={<ArrowUpIcon />}
          title='Row'
          tooltip='Add row above'
          aria-label='Add row above'
          onClick={() => editor.chain().focus().addRowBefore().run()}
          disabled={!commandAvailability.addRowBefore}
        />
        <BubbleMenuButton
          icon={<PlusIcon />}
          title='Row'
          tooltip='Add row below'
          aria-label='Add row below'
          onClick={() => editor.chain().focus().addRowAfter().run()}
          disabled={!commandAvailability.addRowAfter}
        />
        <BubbleMenuButton
          icon={<ArrowLeftIcon />}
          title='Column'
          tooltip='Add column to the left'
          aria-label='Add column to the left'
          onClick={() => editor.chain().focus().addColumnBefore().run()}
          disabled={!commandAvailability.addColumnBefore}
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
          icon={<GridIcon />}
          tooltip='Merge selected cells'
          aria-label='Merge selected cells'
          onClick={() => editor.chain().focus().mergeCells().run()}
          disabled={!commandAvailability.mergeCells}
        />
        <BubbleMenuButton
          icon={<GridIcon />}
          tooltip='Split cell'
          aria-label='Split cell'
          onClick={() => editor.chain().focus().splitCell().run()}
          disabled={!commandAvailability.splitCell}
        />
        <BubbleMenuSeparator />
        <BubbleMenuButton
          icon={<ArrowDownIcon />}
          tooltip='Toggle header row'
          aria-label='Toggle header row'
          onClick={() => editor.chain().focus().toggleHeaderRow().run()}
          disabled={!commandAvailability.toggleHeaderRow}
        />
        <BubbleMenuButton
          icon={<ArrowRightIcon />}
          tooltip='Toggle header column'
          aria-label='Toggle header column'
          onClick={() => editor.chain().focus().toggleHeaderColumn().run()}
          disabled={!commandAvailability.toggleHeaderColumn}
        />
        <BubbleMenuSeparator />
        <BubbleMenuButton
          icon={<TextAlignLeftIcon />}
          tooltip='Align left'
          aria-label='Align left'
          onClick={() => runCellAttribute('align', 'left')}
          disabled={!commandAvailability.setCellAttribute}
        />
        <BubbleMenuButton
          icon={<span className='text-xs font-bold'>C</span>}
          tooltip='Align center'
          aria-label='Align center'
          onClick={() => runCellAttribute('align', 'center')}
          disabled={!commandAvailability.setCellAttribute}
        />
        <BubbleMenuButton
          icon={<span className='text-xs font-bold'>R</span>}
          tooltip='Align right'
          aria-label='Align right'
          onClick={() => runCellAttribute('align', 'right')}
          disabled={!commandAvailability.setCellAttribute}
        />
        <BubbleMenuButton
          icon={<span className='block size-4 rounded-sm bg-blue-500' />}
          tooltip='Set cell background'
          aria-label='Set cell background'
          onClick={() => runCellAttribute('backgroundColor', 'var(--bg-quaternary)')}
          disabled={!commandAvailability.setBackgroundColor}
        />
        <BubbleMenuButton
          icon={<span className='border-secondary block size-4 rounded-sm border' />}
          tooltip='Clear cell background'
          aria-label='Clear cell background'
          onClick={() => runCellAttribute('backgroundColor', null)}
          disabled={!commandAvailability.clearBackgroundColor}
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
