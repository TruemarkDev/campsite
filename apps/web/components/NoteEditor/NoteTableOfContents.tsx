import { TableOfContentData } from '@campsite/editor'
import { cn } from '@campsite/ui/src/utils'

interface Props {
  anchors: TableOfContentData
}

export function NoteTableOfContents({ anchors }: Props) {
  if (anchors.length < 2) return null

  return (
    <nav aria-label='Table of contents' className='border-primary mx-auto mb-6 max-w-[44rem] border-b pb-4'>
      <p className='text-secondary mb-2 text-xs font-semibold uppercase tracking-wide'>On this page</p>
      <ol className='space-y-1'>
        {anchors.map((anchor) => (
          <li key={anchor.id} style={{ paddingInlineStart: `${(anchor.level - 1) * 0.75}rem` }}>
            <button
              type='button'
              onClick={() => anchor.dom.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              className={cn('text-secondary hover:text-primary block w-full truncate text-left text-sm', {
                'text-primary font-medium': anchor.isActive
              })}
              aria-current={anchor.isActive ? 'location' : undefined}
            >
              {anchor.textContent}
            </button>
          </li>
        ))}
      </ol>
    </nav>
  )
}
