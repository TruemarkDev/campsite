import { Link } from '@campsite/ui'

interface Props {
  url: string
}

export function SharedPost({ url }: Props) {
  return (
    <div className='ring-primary bg-primary flex h-5.5 flex-wrap items-center rounded-full px-px shadow-sm ring-2'>
      <Link
        href={url}
        className='bg-tertiary hover:bg-quaternary group pointer-events-auto flex h-5.5 min-w-[32px] items-center justify-center rounded-full px-2 text-[11px] font-medium ring-1'
      >
        View post
      </Link>
    </div>
  )
}
