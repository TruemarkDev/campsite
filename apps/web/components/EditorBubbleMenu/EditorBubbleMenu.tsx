/* eslint-disable max-lines */
import { memo, MouseEvent, useCallback, useEffect, useRef, useState } from 'react'
import { Editor, findParentNode, isList, isTextSelection, useEditorState } from '@tiptap/react'
import { BubbleMenu } from '@tiptap/react/menus'
import { isMobile } from 'react-device-detect'

import {
  BoldIcon,
  ChecklistIcon,
  CodeBlockIcon,
  CodeIcon,
  ExternalLinkIcon,
  Heading1Icon,
  Heading2Icon,
  Heading3Icon,
  isValidUrl,
  ItalicIcon,
  Link,
  LinkIcon,
  OrderedListIcon,
  PencilIcon,
  QuoteIcon,
  SparklesIcon,
  SpeechBubblePlusIcon,
  StrikeIcon,
  TextCapitalizeIcon,
  TrashIcon,
  UnderlineIcon,
  UnorderedListIcon
} from '@campsite/ui'
import { DropdownMenu } from '@campsite/ui/DropdownMenu'
import { buildMenuItems } from '@campsite/ui/Menu'

import { BubbleMenuSeparator } from '@/components/EditorBubbleMenu/BubbleMenuSeparator'

import { BubbleMenuButton } from './BubbleMenuButton'
import { EditorTableMenu } from './EditorTableMenu'
import { AnyEvent, LinkEditor } from './LinkEditor'

interface BubbleMenuState {
  headingLevel: 1 | 2 | 3 | null
  isBlockquote: boolean
  isBold: boolean
  isCode: boolean
  isCodeBlock: boolean
  isItalic: boolean
  isLink: boolean
  isOrderedList: boolean
  isStrike: boolean
  isTaskList: boolean
  isUnderline: boolean
}

function paragraphIcon(state: BubbleMenuState | null) {
  if (state?.headingLevel === 1) return <Heading1Icon size={20} />
  if (state?.headingLevel === 2) return <Heading2Icon />
  if (state?.headingLevel === 3) return <Heading3Icon />
  return <TextCapitalizeIcon />
}

function listIcon(state: BubbleMenuState | null) {
  if (state?.isOrderedList) return <OrderedListIcon />
  if (state?.isTaskList) return <ChecklistIcon />
  return <UnorderedListIcon />
}

interface Props {
  editor: Editor | null
  canComment?: boolean
  enableHeaders?: boolean
  enableLists?: boolean
  enableBlockquote?: boolean
  enableUnderline?: boolean
  enableCodeBlock?: boolean
  // Use this to append the menu to a different element other than the editor's parent
  appendBubbleMenuTo?: () => HTMLElement | null
  onAiEdit?: (range: { from: number; to: number }) => void
}

export const EditorBubbleMenu = memo(function EditorBubbleMemo({
  editor,
  canComment = false,
  enableHeaders = true,
  enableLists = true,
  enableBlockquote = true,
  enableUnderline = true,
  enableCodeBlock = true,
  appendBubbleMenuTo,
  onAiEdit
}: Props) {
  const [linkEditorOpen, setLinkEditorOpen] = useState(false)
  const [url, setUrl] = useState(editor?.getAttributes('link').href ?? '')

  const editorState = useEditorState<BubbleMenuState | null>({
    editor,
    selector: ({ editor }) => {
      if (!editor) return null

      return {
        headingLevel: editor.isActive('heading', { level: 1 })
          ? 1
          : editor.isActive('heading', { level: 2 })
            ? 2
            : editor.isActive('heading', { level: 3 })
              ? 3
              : null,
        isBlockquote: editor.isActive('blockquote'),
        isBold: editor.isActive('bold'),
        isCode: editor.isActive('code'),
        isCodeBlock: editor.isActive('codeBlock'),
        isItalic: editor.isActive('italic'),
        isLink: editor.isActive('link'),
        isOrderedList: editor.isActive('orderedList'),
        isStrike: editor.isActive('strike'),
        isTaskList: editor.isActive('taskList'),
        isUnderline: editor.isActive('underline')
      }
    }
  })

  const openLinkEditor = useCallback(
    (e?: MouseEvent) => {
      e?.stopPropagation()
      setUrl(editor?.getAttributes('link').href ?? '')
      setLinkEditorOpen(true)
    },
    [editor]
  )

  const closeLinkEditor = useCallback(() => {
    setLinkEditorOpen(false)
    editor?.chain().focus().run()
  }, [editor])

  function saveLink() {
    if (url) {
      const href = url.includes('://') ? url : `https://${url}`

      editor?.chain().focus().extendMarkRange('link').setLink({ href }).run()
    } else {
      editor?.chain().focus().extendMarkRange('link').unsetLink().run()
    }

    closeLinkEditor()
  }

  function removeLink(e: AnyEvent) {
    e.stopPropagation()
    editor?.chain().focus().extendMarkRange('link').unsetLink().run()
    closeLinkEditor()
  }

  function blurEditor() {
    // blur editor on mobile in order to hide the keyboard and show mobile dropdown
    if (isMobile && document.activeElement instanceof HTMLElement) {
      document.activeElement.blur()
    }
  }
  // Show LinkEditor when text highlighted on cmd+k
  useEffect(() => {
    const container = editor?.view.dom

    if (!container) return

    const keydown = (e: KeyboardEvent) => {
      if (e.key === 'k' && (e.metaKey || e.ctrlKey)) {
        if (!editor?.isFocused || editor.view.state.selection.from === editor.view.state.selection.to) return
        e.stopPropagation()
        if (linkEditorOpen) {
          closeLinkEditor()
        } else {
          openLinkEditor()
        }
      }
    }

    // update the URL anytime the selection changes
    const updateUrl = () => setUrl(editor?.getAttributes('link').href ?? '')

    container.addEventListener('keydown', keydown, { capture: true })
    editor.on('selectionUpdate', updateUrl)

    return () => {
      container.removeEventListener('keydown', keydown, { capture: true })
      editor.off('selectionUpdate', updateUrl)
    }
  }, [closeLinkEditor, editor, linkEditorOpen, openLinkEditor])

  const containerRef = useRef<HTMLDivElement>(null)

  if (!editor) return null

  const paragraphItems = buildMenuItems([
    {
      type: 'item',
      label: 'Regular text',
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().setParagraph().focus().run()
      },
      className: 'font-normal',
      kbd: 'mod+alt+0'
    },
    {
      type: 'item',
      label: 'Heading 1',
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().splitNearHardBreaks().setHeading({ level: 1 }).focus().run()
      },
      className: 'font-bold !text-lg',
      kbd: 'mod+alt+1'
    },
    {
      type: 'item',
      label: 'Heading 2',
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().splitNearHardBreaks().setHeading({ level: 2 }).focus().run()
      },
      className: 'font-bold',
      kbd: 'mod+alt+2'
    },
    {
      type: 'item',
      label: 'Heading 3',
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().splitNearHardBreaks().setHeading({ level: 3 }).focus().run()
      },
      className: 'font-semibold',
      kbd: 'mod+alt+3'
    }
  ])

  const listItems = buildMenuItems([
    {
      type: 'item',
      label: 'List',
      leftSlot: <UnorderedListIcon />,
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().toggleBulletList().focus().run()
      },
      kbd: 'mod+shift+7'
    },
    {
      type: 'item',
      label: 'Numbered',
      leftSlot: <OrderedListIcon />,
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().toggleOrderedList().focus().run()
      },
      kbd: 'mod+shift+8'
    },
    {
      type: 'item',
      label: 'Checklist',
      leftSlot: <ChecklistIcon />,
      onSelect: (e) => {
        e.stopPropagation()
        editor.chain().toggleTaskList().focus().run()
      },
      kbd: 'mod+shift+9'
    }
  ])

  const parentContainer = appendBubbleMenuTo?.() ?? undefined

  return (
    <div
      className='absolute'
      onKeyDownCapture={(e) => {
        if (e.key !== 'Escape') return
        e.stopPropagation()
        closeLinkEditor()
      }}
    >
      <BubbleMenu
        pluginKey='bubbleMenuText'
        editor={editor}
        appendTo={parentContainer}
        options={{
          onHide: closeLinkEditor,
          // prefer top; allow flipping to the bottom to avoid getting clipped.
          // if the popover is completely off-screen it will be hidden by CSS in editor.css.
          placement: 'top',
          flip: {
            fallbackPlacements: ['top', 'bottom'],
            ...(parentContainer ? { boundary: parentContainer } : {})
          }
        }}
        updateDelay={50}
        shouldShow={({ editor, view, state, from, to }) => {
          // Reworked from the default, because we only want the selection
          // menu for text selections where a mark change will be visible.
          // https://github.com/ueberdosis/tiptap/blob/063ced27ca55f331960b01ee6aea5623eee0ba49/packages/extension-bubble-menu/src/bubble-menu-plugin.ts#L43
          if (!view.hasFocus() && !canComment) {
            return false
          }

          const { doc, selection } = state
          const isText = isTextSelection(selection)

          if (!isText) return false
          const isEmpty = selection.empty || (isText && doc.textBetween(from, to).length === 0)

          if (isEmpty) return false
          if (['postNoteAttachment', 'comment', 'codeBlock'].some((name) => editor.isActive(name))) return false
          return true
        }}
      >
        <div
          ref={containerRef}
          className='text-primary bg-elevated dark flex cursor-default items-center gap-1 rounded-lg p-1 shadow-lg dark:shadow-[inset_0px_1px_0px_rgb(255_255_255_/_0.04),_inset_0px_0px_0px_1px_rgb(255_255_255_/_0.02),_0px_1px_2px_rgb(0_0_0_/_0.4),_0px_2px_4px_rgb(0_0_0_/_0.08),_0px_0px_0px_0.5px_rgb(0_0_0_/_0.24)]'
        >
          {linkEditorOpen ? (
            <LinkEditor url={url} onChangeUrl={setUrl} onSaveLink={saveLink} onRemoveLink={removeLink} />
          ) : (
            <>
              {editor.isEditable && (
                <>
                  {enableHeaders && (
                    <DropdownMenu
                      align='start'
                      items={paragraphItems}
                      trigger={
                        <BubbleMenuButton
                          onClick={blurEditor}
                          icon={paragraphIcon(editorState)}
                          tooltip='Paragraph'
                          dropdown
                        />
                      }
                      desktop={{ container: containerRef.current, width: 'w-50' }}
                    />
                  )}
                  <BubbleMenuButton
                    onClick={(e) => {
                      e.stopPropagation()
                      editor.chain().toggleBold().focus().run()
                    }}
                    isActive={editorState?.isBold}
                    icon={<BoldIcon />}
                    tooltip='Bold'
                    shortcut='mod+b'
                  />
                  <BubbleMenuButton
                    onClick={(e) => {
                      e.stopPropagation()
                      editor.chain().toggleItalic().focus().run()
                    }}
                    isActive={editorState?.isItalic}
                    icon={<ItalicIcon />}
                    tooltip='Italic'
                    shortcut='mod+i'
                  />
                  {enableUnderline && (
                    <BubbleMenuButton
                      onClick={(e) => {
                        e.stopPropagation()
                        editor.chain().toggleUnderline().focus().run()
                      }}
                      isActive={editorState?.isUnderline}
                      icon={<UnderlineIcon />}
                      tooltip='Underline'
                      shortcut='mod+u'
                    />
                  )}
                  <BubbleMenuButton
                    onClick={(e) => {
                      e.stopPropagation()
                      editor.chain().toggleStrike().focus().run()
                    }}
                    isActive={editorState?.isStrike}
                    icon={<StrikeIcon />}
                    tooltip='Strikethrough'
                    shortcut='mod+shift+s'
                  />
                  <BubbleMenuSeparator />

                  {enableBlockquote && (
                    <BubbleMenuButton
                      onClick={(e) => {
                        e.stopPropagation()

                        const selection = editor.state.selection
                        const parentList = findParentNode((node) =>
                          isList(node.type.name, editor.extensionManager.extensions)
                        )(selection)
                        let chain = editor.chain()

                        // fully collapse nested lists
                        if (parentList) {
                          for (let i = 0; i < parentList.depth; i++) {
                            chain = chain.liftListItem('listItem')
                          }
                        }

                        chain.toggleBlockquote().focus().run()
                      }}
                      isActive={editorState?.isBlockquote}
                      icon={<QuoteIcon />}
                      tooltip='Quote'
                      shortcut='mod+shift+b'
                    />
                  )}
                  {enableLists && (
                    <DropdownMenu
                      align='start'
                      items={listItems}
                      trigger={
                        <BubbleMenuButton onClick={blurEditor} icon={listIcon(editorState)} tooltip='List' dropdown />
                      }
                      desktop={{ container: containerRef.current, width: 'w-50' }}
                    />
                  )}
                  <BubbleMenuButton
                    onClick={(e) => {
                      e.stopPropagation()
                      editor.chain().toggleCode().focus().run()
                    }}
                    isActive={editorState?.isCode}
                    icon={<CodeIcon />}
                    tooltip='Code'
                    shortcut='mod+e'
                  />

                  {enableCodeBlock && (
                    <BubbleMenuButton
                      onClick={(e) => {
                        e.stopPropagation()
                        editor.chain().toggleCodeBlock().focus().run()
                      }}
                      isActive={editorState?.isCodeBlock}
                      icon={<CodeBlockIcon />}
                      tooltip='Code block'
                      shortcut='mod+alt+c'
                    />
                  )}

                  <BubbleMenuSeparator />

                  {onAiEdit && (
                    <>
                      <BubbleMenuButton
                        onClick={(event) => {
                          event.stopPropagation()
                          onAiEdit({
                            from: editor.state.selection.from,
                            to: editor.state.selection.to
                          })
                        }}
                        icon={<SparklesIcon />}
                        aria-label='Edit with AI'
                        tooltip='Edit with AI'
                      />
                      <BubbleMenuSeparator />
                    </>
                  )}

                  <BubbleMenuButton
                    onClick={openLinkEditor}
                    isActive={editorState?.isLink}
                    icon={<LinkIcon />}
                    tooltip='Link'
                    shortcut='mod+k'
                  />
                </>
              )}
              {canComment && (
                <>
                  {editor.isEditable && <BubbleMenuSeparator />}
                  <BubbleMenuButton
                    onClick={() => editor.commands.setNewComment()}
                    icon={<SpeechBubblePlusIcon />}
                    tooltip='Write a comment'
                    title={editor.isEditable ? undefined : 'Comment'}
                  />
                </>
              )}
            </>
          )}
        </div>
      </BubbleMenu>

      <BubbleMenu
        pluginKey='bubbleMenuLink'
        editor={editor}
        appendTo={parentContainer}
        options={{ onHide: closeLinkEditor }}
        shouldShow={({ editor, from, to }) => {
          // only show the bubble menu for links.
          return from === to && editor.isActive('link')
        }}
      >
        <div className='dark:bg-elevated text-primary dark flex gap-1 rounded-lg bg-black p-1'>
          {linkEditorOpen ? (
            <LinkEditor url={url} onChangeUrl={setUrl} onSaveLink={saveLink} onRemoveLink={removeLink} />
          ) : (
            <>
              <button
                type='button'
                onClick={openLinkEditor}
                className='hover:bg-quaternary flex w-7 flex-none rounded p-1'
              >
                <PencilIcon />
              </button>
              <button type='button' onClick={removeLink} className='hover:bg-quaternary flex w-7 flex-none rounded p-1'>
                <TrashIcon />
              </button>
              {!!url && isValidUrl(url) && (
                <Link
                  href={url}
                  target='_blank'
                  className={'hover:bg-quaternary flex h-7 w-7 flex-none items-center justify-center rounded p-1'}
                  forceInternalLinksBlank
                >
                  <ExternalLinkIcon />
                </Link>
              )}
            </>
          )}
        </div>
      </BubbleMenu>

      <EditorTableMenu editor={editor} appendTo={parentContainer} />
    </div>
  )
})
