import CodeBlock, { CodeBlockOptions } from '@tiptap/extension-code-block'

import { createMarkdownParserSpec } from '../utils/createMarkdownParser'
import CodeHighlighting from './CodeHighlighting'

export type CodeBlockHighlightedOptions = CodeBlockOptions & {
  highlight?: boolean
}

export const CodeBlockHighlighted = CodeBlock.extend<CodeBlockHighlightedOptions>({
  addOptions() {
    // this.parent is always defined when extending a concrete extension
    return {
      ...this.parent!(),
      highlight: false
    }
  },

  addAttributes() {
    return {
      ...(this.parent?.() || {}),
      spellcheck: {
        default: false
      }
    }
  },

  addProseMirrorPlugins() {
    return [
      ...(this.parent?.() || []),
      ...(this.options.highlight
        ? [
            CodeHighlighting({
              name: CodeBlock.name
            })
          ]
        : [])
    ]
  },

  markdownParseSpec() {
    return createMarkdownParserSpec({ block: CodeBlock.name, noCloseToken: true })
  },

  markdownToken: 'code_block'
})
