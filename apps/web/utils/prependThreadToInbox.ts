import { InfiniteData, QueryClient, QueryKey } from '@tanstack/react-query'

import { MessageThread, MessageThreadInbox, MessageThreadPusher } from '@campsite/types'

export function prependThreadToInbox(
  inbox: InfiniteData<MessageThreadInbox> | undefined,
  thread: MessageThread
): InfiniteData<MessageThreadInbox> | undefined {
  if (!inbox?.pages.length || thread.project_id) return inbox

  return {
    ...inbox,
    pages: inbox.pages.map((page, index) => ({
      ...page,
      threads: [...(index === 0 ? [thread] : []), ...page.threads.filter((existing) => existing.id !== thread.id)]
    }))
  }
}

// Realtime payloads are partial. Refetch an unloaded thread instead of inserting
// an incomplete record that lacks members, permissions, and avatar data.
export function updateThreadInInbox(queryClient: QueryClient, queryKey: QueryKey, update: MessageThreadPusher) {
  let missingThread = false

  queryClient.setQueriesData<InfiniteData<MessageThreadInbox>>({ queryKey }, (old) => {
    const existing = old?.pages.flatMap((page) => page.threads).find((thread) => thread.id === update.id)

    if (!existing) {
      missingThread = !update.project_id
      return old
    }
    return prependThreadToInbox(old, { ...existing, ...update })
  })
  if (missingThread) queryClient.invalidateQueries({ queryKey })
}
