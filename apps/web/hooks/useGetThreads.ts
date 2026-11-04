import { keepPreviousData, useInfiniteQuery } from '@tanstack/react-query'

import { PublicOrganization } from '@campsite/types/generated'

import { useScope } from '@/contexts/scope'
import { apiClient } from '@/utils/queryClient'

interface Options {
  enabled?: boolean
  organization?: PublicOrganization
}

const query = apiClient.organizations.getThreads()

export function useGetThreads({ enabled = true, organization }: Options = {}) {
  const { scope } = useScope()
  const orgSlug = organization?.slug || `${scope}`

  const result = useInfiniteQuery({
    queryKey: query.requestKey({ orgSlug }),
    queryFn: ({ pageParam }) => query.request({ orgSlug, after: pageParam }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (lastPage) => lastPage.next_cursor,
    enabled,
    placeholderData: keepPreviousData,
    refetchOnWindowFocus: true,
    staleTime: 30 * 1000
  })

  return {
    ...result,
    data: result.data
      ? {
          threads: Array.from(
            new Map(result.data.pages.flatMap((page) => page.threads).map((thread) => [thread.id, thread])).values()
          )
        }
      : undefined
  }
}
