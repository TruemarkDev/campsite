import { Extensions, generateJSON, JSONContent } from '@tiptap/core'

import { resolveSuggestions } from '@campsite/editor'

export interface RichTextHeading {
  id: string
  level: number
  textContent: string
}

function nodeText(node: JSONContent): string {
  return node.text || node.content?.map(nodeText).join('') || ''
}

function slugify(value: string) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-|-$/g, '')
}

export function prepareRichTextContent(content: string | JSONContent, extensions: Extensions) {
  const unresolved = typeof content === 'string' ? (generateJSON(content, extensions) as JSONContent) : content
  const source = resolveSuggestions(unresolved, 'strip')
  const headings: RichTextHeading[] = []
  const usedIds = new Set<string>()

  function prepareNode(node: JSONContent): JSONContent {
    const preparedContent = node.content?.map(prepareNode)

    if (node.type !== 'heading') return { ...node, content: preparedContent }

    const textContent = nodeText(node).trim()
    let id = node.attrs?.id || node.attrs?.['data-toc-id'] || slugify(textContent) || 'section'
    const baseId = id
    let suffix = 2

    while (usedIds.has(id)) {
      id = `${baseId}-${suffix}`
      suffix += 1
    }

    usedIds.add(id)
    if (textContent) headings.push({ id, level: Number(node.attrs?.level || 1), textContent })

    return { ...node, attrs: { ...node.attrs, id }, content: preparedContent }
  }

  return { output: prepareNode(source), headings }
}
