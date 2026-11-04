import { Mark, mergeAttributes } from '@tiptap/core'
import { Mark as PMMark, Node as PMNode } from '@tiptap/pm/model'
import { Transaction } from '@tiptap/pm/state'

export type SuggestionActorType = 'ai' | 'user'

export interface SuggestionAttributes {
  actorId: string
  actorType: SuggestionActorType
  invokedBy?: string | null
  instruction?: string | null
  batchId: string
  createdAt: string
}

export type SuggestionResolution = 'accept' | 'reject'

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    suggestions: {
      acceptSuggestion: (batchId: string) => ReturnType
      rejectSuggestion: (batchId: string) => ReturnType
      acceptAllSuggestions: () => ReturnType
      rejectAllSuggestions: () => ReturnType
      applySuggestion: (
        range: { from: number; to: number },
        text: string,
        attributes: SuggestionAttributes
      ) => ReturnType
    }
  }
}

type SuggestionKind = 'insert' | 'delete'

interface SuggestionAction {
  from: number
  to: number
  mark: PMMark
  kind: SuggestionKind
}

function suggestionKind(mark: PMMark): SuggestionKind | null {
  if (mark.type.name === SuggestionInsert.name) return 'insert'
  if (mark.type.name === SuggestionDelete.name) return 'delete'
  return null
}

function resolveTransaction(
  document: PMNode,
  transaction: Transaction,
  resolution: SuggestionResolution,
  batchId?: string
) {
  const actions: SuggestionAction[] = []

  document.descendants((node, position) => {
    if (!node.isText) return

    node.marks.forEach((mark) => {
      const kind = suggestionKind(mark)

      if (!kind || (batchId && mark.attrs.batchId !== batchId)) return

      actions.push({
        from: position,
        to: position + node.nodeSize,
        mark,
        kind
      })
    })
  })

  actions
    .sort((left, right) => right.from - left.from || right.to - left.to)
    .forEach(({ from, to, mark, kind }) => {
      const shouldDelete =
        (resolution === 'accept' && kind === 'delete') || (resolution === 'reject' && kind === 'insert')

      if (shouldDelete) {
        transaction.delete(from, to)
      } else {
        transaction.removeMark(from, to, mark)
      }
    })

  return actions.length > 0
}

const suggestionAttributes = {
  actorId: {
    default: '',
    parseHTML: (element: HTMLElement) => element.getAttribute('data-actor-id') || '',
    renderHTML: (attributes: SuggestionAttributes) => ({ 'data-actor-id': attributes.actorId })
  },
  actorType: {
    default: 'ai',
    parseHTML: (element: HTMLElement) => element.getAttribute('data-actor-type') || 'ai',
    renderHTML: (attributes: SuggestionAttributes) => ({ 'data-actor-type': attributes.actorType })
  },
  invokedBy: {
    default: null,
    parseHTML: (element: HTMLElement) => element.getAttribute('data-invoked-by'),
    renderHTML: (attributes: SuggestionAttributes) =>
      attributes.invokedBy ? { 'data-invoked-by': attributes.invokedBy } : {}
  },
  instruction: {
    default: null,
    parseHTML: (element: HTMLElement) => element.getAttribute('data-instruction'),
    renderHTML: (attributes: SuggestionAttributes) =>
      attributes.instruction ? { 'data-instruction': attributes.instruction } : {}
  },
  batchId: {
    default: '',
    parseHTML: (element: HTMLElement) => element.getAttribute('data-batch-id') || '',
    renderHTML: (attributes: SuggestionAttributes) => ({ 'data-batch-id': attributes.batchId })
  },
  createdAt: {
    default: '',
    parseHTML: (element: HTMLElement) => element.getAttribute('data-created-at') || '',
    renderHTML: (attributes: SuggestionAttributes) => ({ 'data-created-at': attributes.createdAt })
  }
}

function createSuggestionMark(name: 'suggestionInsert' | 'suggestionDelete', kind: SuggestionKind) {
  return Mark.create({
    name,
    inclusive: false,
    excludes: '',

    addAttributes() {
      return suggestionAttributes
    },

    parseHTML() {
      return [{ tag: `span[data-suggestion-${kind}]` }]
    },

    renderHTML({ HTMLAttributes }) {
      return [
        'span',
        mergeAttributes(HTMLAttributes, {
          [`data-suggestion-${kind}`]: ''
        }),
        0
      ]
    },

    addCommands() {
      return {
        applySuggestion:
          (range: { from: number; to: number }, text: string, attributes: SuggestionAttributes) =>
          ({ state, tr, dispatch }) => {
            const insertMark = state.schema.marks.suggestionInsert
            const deleteMark = state.schema.marks.suggestionDelete

            if (
              !insertMark ||
              !deleteMark ||
              range.from < 0 ||
              range.to < range.from ||
              range.to > state.doc.content.size
            ) {
              return false
            }

            if (range.from < range.to) tr.addMark(range.from, range.to, deleteMark.create(attributes))
            if (text) {
              tr.insertText(text, range.to)
              tr.addMark(range.to, range.to + text.length, insertMark.create(attributes))
            }

            dispatch?.(tr)
            return true
          },
        acceptSuggestion:
          (batchId: string) =>
          ({ state, tr, dispatch }) => {
            if (!batchId || !resolveTransaction(state.doc, tr, 'accept', batchId)) return false
            dispatch?.(tr)
            return true
          },
        rejectSuggestion:
          (batchId: string) =>
          ({ state, tr, dispatch }) => {
            if (!batchId || !resolveTransaction(state.doc, tr, 'reject', batchId)) return false
            dispatch?.(tr)
            return true
          },
        acceptAllSuggestions:
          () =>
          ({ state, tr, dispatch }) => {
            if (!resolveTransaction(state.doc, tr, 'accept')) return false
            dispatch?.(tr)
            return true
          },
        rejectAllSuggestions:
          () =>
          ({ state, tr, dispatch }) => {
            if (!resolveTransaction(state.doc, tr, 'reject')) return false
            dispatch?.(tr)
            return true
          }
      }
    }
  })
}

export const SuggestionInsert = createSuggestionMark('suggestionInsert', 'insert')
export const SuggestionDelete = createSuggestionMark('suggestionDelete', 'delete')
