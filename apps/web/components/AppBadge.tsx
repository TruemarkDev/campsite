import type { ReactElement } from 'react'

import { Badge } from '@campsite/ui/Badge'
import { cn } from '@campsite/ui/utils'

export function AppBadge({ size = 'sm', className }: { size?: 'xs' | 'sm'; className?: string }): ReactElement {
  if (size === 'xs') {
    return (
      <Badge tooltip='App' className={cn('h-4.5 w-4.5', className)} color='blue'>
        A
      </Badge>
    )
  }
  return (
    <Badge className={cn(className)} color='blue'>
      App
    </Badge>
  )
}
