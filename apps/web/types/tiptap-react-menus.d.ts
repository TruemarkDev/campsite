// @tiptap/react exposes this module through package.json exports, which this
// workspace's moduleResolution "node" setting cannot read. Keep the local
// declaration limited to the BubbleMenu surface used by the web app.
declare module '@tiptap/react/menus' {
  import type { Editor } from '@tiptap/core'
  import type { EditorState } from '@tiptap/pm/state'
  import type { EditorView } from '@tiptap/pm/view'
  import type * as React from 'react'

  export interface BubbleMenuProps extends React.HTMLAttributes<HTMLDivElement> {
    editor?: Editor | null
    pluginKey?: string
    updateDelay?: number
    appendTo?: HTMLElement | (() => HTMLElement)
    options?: {
      placement?: string
      flip?: boolean | { fallbackPlacements?: string[]; boundary?: HTMLElement }
      onHide?: () => void
    }
    shouldShow?: (props: {
      editor: Editor
      element: HTMLElement
      view: EditorView
      state: EditorState
      oldState?: EditorState
      from: number
      to: number
    }) => boolean
  }

  export const BubbleMenu: React.ForwardRefExoticComponent<BubbleMenuProps & React.RefAttributes<HTMLDivElement>>
}
