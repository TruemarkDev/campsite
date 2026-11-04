import { useMutation, useQueryClient } from '@tanstack/react-query'

import { useScope } from '@/contexts/scope'
import { useQueryNormalizer } from '@/utils/normy/QueryNormalizerProvider'
import { removeFavorite } from '@/utils/optimisticFavorites'
import { apiClient, setTypedInfiniteQueriesData } from '@/utils/queryClient'
import { createNormalizedOptimisticUpdate } from '@/utils/queryNormalization'

const getThreads = apiClient.organizations.getThreads()
const deleteThreadsMyMembership = apiClient.organizations.deleteThreadsMyMembership()

export function useLeaveThread({ threadId }: { threadId: string }) {
  const { scope } = useScope()
  const queryClient = useQueryClient()
  const queryNormalizer = useQueryNormalizer()

  return useMutation({
    mutationFn: (_data: {}) => deleteThreadsMyMembership.request(`${scope}`, threadId),
    onMutate: () => {
      setTypedInfiniteQueriesData(queryClient, getThreads.requestKey({ orgSlug: `${scope}` }), (old) => {
        if (!old) return

        return {
          ...old,
          pages: old.pages.map((page) => ({
            ...page,
            threads: page.threads.filter((thread) => thread.id !== threadId)
          }))
        }
      })
      removeFavorite({ queryClient, scope, resourceId: threadId })

      return createNormalizedOptimisticUpdate({
        queryNormalizer,
        type: 'thread',
        id: threadId,
        update: { viewer_has_favorited: false }
      })
    }
  })
}
