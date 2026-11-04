import { JSONContent } from '@tiptap/core'

export type ResolveSuggestionsMode = 'accept' | 'reject' | 'strip'

const INSERT_MARK = 'suggestionInsert'
const DELETE_MARK = 'suggestionDelete'

/**
 * Returns a copy of a Tiptap JSON document with unresolved suggestions resolved.
 * `strip` produces effective/accepted content: deletions are omitted and insertion
 * metadata is removed. The input document is never mutated.
 */
export function resolveSuggestions(document: JSONContent, mode: ResolveSuggestionsMode): JSONContent {
  function resolveNode(node: JSONContent): JSONContent | null {
    const marks = node.marks || []
    const hasInsert = marks.some((mark) => mark.type === INSERT_MARK)
    const hasDelete = marks.some((mark) => mark.type === DELETE_MARK)
    const accept = mode === 'accept' || mode === 'strip'

    if ((accept && hasDelete) || (mode === 'reject' && hasInsert)) return null

    const content = node.content?.map(resolveNode).filter((child): child is JSONContent => child !== null)
    const resolvedMarks = marks.filter((mark) => mark.type !== INSERT_MARK && mark.type !== DELETE_MARK)
    const resolved: JSONContent = { ...node }

    if (content) resolved.content = content
    if (node.marks) resolved.marks = resolvedMarks

    return resolved
  }

  return resolveNode(document) || { type: document.type || 'doc', content: [] }
}
