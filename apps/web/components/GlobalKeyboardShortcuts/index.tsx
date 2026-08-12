import { useSetAtom } from 'jotai'
import Router from 'next/router'

import { useLayeredHotkeys } from '@campsite/ui/DismissibleLayer/useLayeredHotkeys'

import { defaultInboxView } from '@/components/InboxItems/InboxSplitView'
import { activityOpenAtom } from '@/components/Sidebar/SidebarActivity'
import { useScope } from '@/contexts/scope'

export function GlobalKeyboardShortcuts() {
  const { scope } = useScope()
  const setActivityOpen = useSetAtom(activityOpenAtom)

  useLayeredHotkeys({
    keys: 'g>i',
    callback: () => {
      Router.push(`/${scope}/inbox/${defaultInboxView}`)
    }
  })
  useLayeredHotkeys({
    keys: 'g>h',
    callback: () => Router.push(`/${scope}/posts`)
  })
  useLayeredHotkeys({
    keys: 'g>d',
    callback: () => Router.push(`/${scope}/notes`)
  })
  useLayeredHotkeys({
    keys: 'g>a',
    callback: () => setActivityOpen(true)
  })

  return null
}
