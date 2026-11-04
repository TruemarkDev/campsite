import { m } from 'framer-motion'

import { IS_PRODUCTION } from '@campsite/config'
import { cn } from '@campsite/ui/src/utils'

export function DevModeBanner() {
  if (IS_PRODUCTION) return null

  return (
    <m.div className={cn('border-brand-primary fixed top-0 right-0 left-0 z-40 border-t-2')}>
      <div className='bg-brand-primary fixed left-1/2 -translate-x-1/2 rounded-b-md px-2.5 pb-0.5 text-center font-mono text-[10px] font-bold tracking-wider text-white uppercase'>
        Dev
      </div>
    </m.div>
  )
}
