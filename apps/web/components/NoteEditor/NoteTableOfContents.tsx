import { cn } from '@campsite/ui/src/utils'

export interface NoteTableOfContentsItem {
  id: string
  level: number
  textContent: string
  isActive?: boolean
  dom?: HTMLHeadingElement
}

interface Props {
  anchors: NoteTableOfContentsItem[]
}

export function NoteTableOfContents({ anchors }: Props) {
  if (anchors.length < 2) return null

  return (
    <nav aria-label='Table of contents' className='border-primary mx-auto mb-6 max-w-[44rem] border-b pb-4'>
      <p className='text-secondary mb-2 text-xs font-semibold uppercase tracking-wide'>On this page</p>
      <ol className='max-h-64 space-y-1 overflow-y-auto pr-1'>
        {anchors.map((anchor) => (
          <li key={anchor.id} style={{ paddingInlineStart: `${(anchor.level - 1) * 0.75}rem` }}>
            <a
              href={`#${encodeURIComponent(anchor.id)}`}
              onClick={(event) => {
                const heading = anchor.dom || document.getElementById(anchor.id)

                if (!heading) return

                event.preventDefault()
                window.history.replaceState(null, '', `#${encodeURIComponent(anchor.id)}`)
                const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

                heading.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth', block: 'start' })
                heading.focus({ preventScroll: true })
              }}
              className={cn('text-secondary hover:text-primary block w-full truncate text-left text-sm', {
                'text-primary font-medium': anchor.isActive
              })}
              aria-current={anchor.isActive ? 'location' : undefined}
            >
              {anchor.textContent}
            </a>
          </li>
        ))}
      </ol>
    </nav>
  )
}
