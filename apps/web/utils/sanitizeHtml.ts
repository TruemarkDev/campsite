import DOMPurify from 'isomorphic-dompurify'

const CAMPSITE_RICH_TEXT_TAGS = ['link-unfurl', 'post-attachment', 'resource-mention']

/**
 * Sanitizes persisted and third-party rich text immediately before rendering.
 * The HTML profile excludes SVG and MathML while preserving Campsite's custom
 * editor nodes and data attributes.
 */
export function sanitizeHtml(html?: string | null): string {
  return DOMPurify.sanitize(html ?? '', {
    USE_PROFILES: { html: true },
    ADD_TAGS: CAMPSITE_RICH_TEXT_TAGS,
    ADD_ATTR: ['target']
  })
}
