import { AnyExtension } from '@tiptap/core'
import { Schema } from '@tiptap/pm/model'
import MarkdownIt from 'markdown-it'
import Token from 'markdown-it/lib/token'

import markdownItTasks from './markdownItTasks'
import { MarkdownParser, ParseSpec } from './MarkdownParser'

// Tiptap v2 allowed arbitrary extra keys in extension configs; v3 types are
// closed, so our custom markdown-parsing config keys need explicit augmentation.
declare module '@tiptap/core' {
  interface NodeConfig<Options, Storage> {
    markdownParseSpec?: () => ParseSpec | null | undefined
    markdownToken?: string
  }

  interface MarkConfig<Options, Storage> {
    markdownParseSpec?: () => ParseSpec | null | undefined
    markdownToken?: string
  }

  interface ExtensionConfig<Options, Storage> {
    markdownParseSpec?: () => ParseSpec | null | undefined
    markdownToken?: string
  }
}

const ignoreAllMarkdownTokens: { [name: string]: ParseSpec } = {
  // blocks
  paragraph: { block: 'paragraph' },
  blockquote: { block: 'paragraph' },
  code_block: { block: 'paragraph' },
  fence: { block: 'paragraph' },
  heading: { block: 'paragraph' },
  hr: { ignore: true, noCloseToken: true },
  ordered_list: { ignore: true },
  bullet_list: { ignore: true },
  list_item: { ignore: true },
  references: { block: 'paragraph' },
  table: { block: 'paragraph' },
  thead: { ignore: true },
  th: { ignore: true },
  tbody: { ignore: true },
  tr: { ignore: true },
  td: { ignore: true },
  image: { block: 'paragraph', noCloseToken: true },
  hardbreak: { ignore: true, noCloseToken: true },
  softbreak: { ignore: true, noCloseToken: true },

  // inline
  code_inline: { ignore: true },
  strong: { ignore: true },
  em: { ignore: true },
  link: { ignore: true },
  s: { ignore: true }
}

const tableMarkdownTokens: { [name: string]: ParseSpec } = {
  table: { block: 'table' },
  thead: { ignore: true },
  tbody: { ignore: true },
  tr: { block: 'tableRow' },
  th: { block: 'tableHeader', contentWrapper: 'paragraph' },
  td: { block: 'tableCell', contentWrapper: 'paragraph' }
}

export function listIsTight(tokens: readonly Token[], i: number) {
  while (++i < tokens.length) if (tokens[i].type != 'list_item_open') return tokens[i].hidden
  return false
}

function getMarkdownSpec(extension: AnyExtension) {
  if ('markdownParseSpec' in extension.config === false || typeof extension.config.markdownParseSpec !== 'function') {
    return null
  }

  return extension.config.markdownParseSpec() as ParseSpec | null | undefined
}

function getMarkdownToken(extension: AnyExtension) {
  if ('markdownToken' in extension.config === false || typeof extension.config.markdownToken !== 'string') {
    return extension.name
  }
  return extension.config.markdownToken
}

export const createMarkdownParserSpec = (spec: ParseSpec) => spec

export function createMarkdownParser(
  schema: Schema,
  extensions: AnyExtension[],
  // WARNING: Provide JSDOM window and document objects to avoid errors in Node.js environment
  domParser: DOMParser = new window.DOMParser(),
  document: Document = window.document
) {
  const tokens = extensions
    .filter(
      (extension) => 'markdownParseSpec' in extension.config && typeof extension.config.markdownParseSpec === 'function'
    )
    .reduce(
      (nodes, extension) => {
        const parseSpec = getMarkdownSpec(extension)

        if (!parseSpec) {
          return nodes
        }

        return {
          ...nodes,
          [getMarkdownToken(extension)]: parseSpec
        }
      },
      { ...ignoreAllMarkdownTokens }
    )

  const tableNodeNames = ['table', 'tableRow', 'tableHeader', 'tableCell']
  if (tableNodeNames.every((name) => schema.nodes[name])) {
    Object.assign(tokens, tableMarkdownTokens)
  }

  return new MarkdownParser(
    schema,
    MarkdownIt('default', {
      // enables raw inline html with the html_inline token
      html: true,
      breaks: false,
      linkify: true
    })
      .enable('table')
      .use(markdownItTasks),
    tokens,
    domParser,
    document
  )
}
