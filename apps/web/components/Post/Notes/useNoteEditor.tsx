import { useEffect, useMemo } from 'react'
import { HocuspocusProvider } from '@hocuspocus/provider'
import Collaboration from '@tiptap/extension-collaboration'
import CollaborationCaret from '@tiptap/extension-collaboration-caret'
import { EditorOptions, ReactNodeViewRenderer, useEditor } from '@tiptap/react'

import { ActiveEditorComment, BlurAtTopOptions, getNoteExtensions, PostNoteAttachmentOptions } from '@campsite/editor'
import { cn } from '@campsite/ui/src/utils'

import { InlineResourceMentionRenderer } from '@/components/InlineResourceMentionRenderer'
import { useControlClickLink } from '@/components/MarkdownEditor/ControlClickLink'
import { MediaGalleryRenderer } from '@/components/Post/MediaGalleryRenderer'
import { InlineRelativeTimeRenderer } from '@/components/RichTextRenderer/handlers/RelativeTime'
import { useCurrentUserOrOrganizationHasFeature } from '@/hooks/useCurrentUserOrOrganizationHasFeature'
import { useGetCurrentUser } from '@/hooks/useGetCurrentUser'
import { notEmpty } from '@/utils/notEmpty'

import { LinkUnfurlRenderer } from '../LinkUnfurlRenderer'
import { NoteAttachmentRenderer } from './Attachments/NoteAttachmentRenderer'
import { useUploadNoteAttachments } from './Attachments/useUploadAttachments'
import { currentUserToCollaborationUser, renderCollaborationCaret } from './collaborationUser'
import { DragAndDrop } from './DragAndDrop'

interface NoteEditorOptions {
  content: string
  onOpenAttachment?: PostNoteAttachmentOptions['onOpenAttachment']
  autofocus?: boolean
  editable?: 'all' | 'viewer' | 'none'
  editorProps?: EditorOptions['editorProps']
  onHoverComment?(comment: ActiveEditorComment | null): void
  onActiveComment?(comment: ActiveEditorComment | null): void
  onBlurAtTop?: BlurAtTopOptions['onBlur']
  provider?: HocuspocusProvider | null
  upload?: ReturnType<typeof useUploadNoteAttachments>
}

export function useNoteEditor({
  content,
  autofocus,
  editable,
  editorProps,
  onHoverComment,
  onActiveComment,
  onOpenAttachment,
  onBlurAtTop,
  provider
}: NoteEditorOptions) {
  const { data: currentUser } = useGetCurrentUser()
  const linkOptions = useControlClickLink()
  const hasRelativeTime = useCurrentUserOrOrganizationHasFeature('relative_time')

  const extensions = useMemo(() => {
    return [
      ...getNoteExtensions({
        history: {
          enabled: !provider
        },
        dropcursor: {
          class: 'text-blue-500',
          width: 2
        },
        link: linkOptions,
        linkUnfurl: {
          addNodeView() {
            return ReactNodeViewRenderer(LinkUnfurlRenderer)
          }
        },
        taskItem: {
          canEdit() {
            return editable !== 'none'
          },
          onReadOnlyChecked() {
            return editable === 'viewer'
          }
        },
        postNoteAttachment: {
          onOpenAttachment,
          addNodeView() {
            return ReactNodeViewRenderer(NoteAttachmentRenderer)
          }
        },
        mediaGallery: {
          onOpenAttachment,
          addNodeView() {
            return ReactNodeViewRenderer(MediaGalleryRenderer)
          }
        },
        resourceMention: {
          addNodeView() {
            return ReactNodeViewRenderer(InlineResourceMentionRenderer, { contentDOMElementTag: 'span' })
          }
        },
        comment: {
          enabled: true,
          onCommentHovered: onHoverComment,
          onCommentActivated: onActiveComment
        },
        codeBlockHighlighted: {
          highlight: true
        },
        blurAtTop: {
          enabled: !!onBlurAtTop,
          onBlur: onBlurAtTop
        },
        relativeTime: {
          disabled: !hasRelativeTime,
          addNodeView() {
            return ReactNodeViewRenderer(InlineRelativeTimeRenderer, { contentDOMElementTag: 'span' })
          }
        },
        tableOfContents: {
          // Keep the same heading schema for every collaborator, but only
          // editors may persist the stable-ID migration.
          updateDocument: editable === 'all'
        }
      }),
      ...(provider
        ? [
            Collaboration.extend({
              onTransaction() {
                // IMPORTANT: this is a hacky fix to prevent scroll-jank on initial load in Safari
                this.editor.view.dom.style.overflowAnchor = ''
              }
            }).configure({
              document: provider.document
            }),
            CollaborationCaret.configure({
              provider: provider,
              render: renderCollaborationCaret,
              selectionRender(user) {
                return {
                  class: cn(user.customSelection)
                }
              }
            })
          ]
        : []),
      DragAndDrop
    ].filter(notEmpty)
  }, [editable, linkOptions, onActiveComment, onBlurAtTop, onHoverComment, onOpenAttachment, provider, hasRelativeTime])

  const allEditable = editable === 'all'

  const editor = useEditor(
    {
      immediatelyRender: true,
      shouldRerenderOnTransaction: false,
      editorProps: {
        attributes: {
          class:
            'new-posts prose select-text focus:outline-none w-full relative note min-w-full px-[calc((100%-44rem)/2)]',
          style: "overflow-anchor: ''"
        },
        ...editorProps
      },
      extensions,
      autofocus: !!autofocus,
      content: provider ? undefined : content,
      editable: allEditable
    },
    [extensions]
  )

  useEffect(() => {
    if (editor.isEditable !== allEditable) {
      editor.setEditable(allEditable)
    }
  }, [editor, allEditable])

  useEffect(() => {
    if (!provider?.awareness || !currentUser) return

    provider.awareness.setLocalStateField('user', currentUserToCollaborationUser(currentUser))
  }, [currentUser, provider])

  return editor
}
