import { useSetAtom } from 'jotai'
import Router from 'next/router'

import { useLayeredHotkeys } from '@campsite/ui/DismissibleLayer/useLayeredHotkeys'

import { defaultInboxView } from '@/components/InboxItems/InboxSplitView'
import { activityOpenAtom } from '@/components/Sidebar/SidebarActivity'
import { useScope } from '@/contexts/scope'
import { useCurrentUserOrOrganizationHasFeature } from '@/hooks/useCurrentUserOrOrganizationHasFeature'
import { useGetCurrentOrganization } from '@/hooks/useGetCurrentOrganization'

export function GlobalKeyboardShortcuts() {
  const { scope } = useScope()
  const setActivityOpen = useSetAtom(activityOpenAtom)
  const hasSidebarChat = useCurrentUserOrOrganizationHasFeature('sidebar_dms')
  const { data: organization } = useGetCurrentOrganization()

  const navigationOptions = (description: string, enabled = true) => ({
    description,
    enabled,
    metadata: { category: 'Navigation' }
  })

  useLayeredHotkeys({
    keys: 'g>i',
    callback: () => {
      Router.push(`/${scope}/inbox/${defaultInboxView}`)
    },
    options: navigationOptions('Go to inbox')
  })
  useLayeredHotkeys({
    keys: 'g>h',
    callback: () => Router.push(`/${scope}/posts`),
    options: navigationOptions('Go to home')
  })
  useLayeredHotkeys({
    keys: 'g>d',
    callback: () => Router.push(`/${scope}/notes`),
    options: navigationOptions('Go to docs')
  })
  useLayeredHotkeys({
    keys: 'g>a',
    callback: () => setActivityOpen(true),
    options: navigationOptions('Open activity')
  })
  useLayeredHotkeys({
    keys: 'g>m',
    callback: () => Router.push(`/${scope}/chat`),
    options: navigationOptions('Go to messages', hasSidebarChat)
  })
  useLayeredHotkeys({
    keys: 'g>c',
    callback: () => Router.push(`/${scope}/calls`),
    options: navigationOptions('Go to calls')
  })
  useLayeredHotkeys({
    keys: 'g>p',
    callback: () => Router.push(`/${scope}/projects`),
    options: navigationOptions('Go to channels', organization?.viewer_can_see_projects_index === true)
  })
  useLayeredHotkeys({
    keys: 'g>e',
    callback: () => Router.push(`/${scope}/people`),
    options: navigationOptions('Go to people', organization?.viewer_can_see_people_index === true)
  })

  return null
}
