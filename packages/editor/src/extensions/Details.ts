// Stub for @tiptap-pro/extension-details
// This is a private package that requires authentication to install

import { Node, mergeAttributes } from '@tiptap/core'

export const Details = Node.create({
  name: 'details',
  group: 'block',
  content: 'summary detailsContent',
  defining: true,
  parseHTML() {
    return [{ tag: 'details' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['details', mergeAttributes(HTMLAttributes), 0]
  },
  addCommands() {
    return {
      setDetails: () => ({ commands }: { commands: any }) => {
        return commands.toggleNode(this.name, 'paragraph')
      }
    } as any
  }
})

export const DetailsContent = Node.create({
  name: 'detailsContent',
  group: 'block',
  content: 'block+',
  defining: true,
  parseHTML() {
    return [{ tag: 'div.details-content' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { class: 'details-content' }), 0]
  }
})

export const DetailsSummary = Node.create({
  name: 'detailsSummary',
  group: 'block',
  content: 'inline*',
  parseHTML() {
    return [{ tag: 'summary' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['summary', HTMLAttributes, 0]
  }
})

export type DetailsOptions = {
  HTMLAttributes: Record<string, any>
}

export type DetailsContentOptions = {
  HTMLAttributes: Record<string, any>
}

export type DetailsSummaryOptions = {
  HTMLAttributes: Record<string, any>
}
