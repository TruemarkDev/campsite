import { useQuery } from '@tanstack/react-query'

import { ApiError } from '@campsite/types'

import { useScope } from '@/contexts/scope'
import { apiClient } from '@/utils/queryClient'

export const getProjectBeadsBoard = apiClient.organizations.getProjectsBeadsBoard()

export function useGetProjectBeadsBoard({ projectId, enabled = true }: { projectId: string; enabled?: boolean }) {
  const { scope } = useScope()

  return useQuery({
    queryKey: getProjectBeadsBoard.requestKey(`${scope}`, projectId),
    queryFn: () => getProjectBeadsBoard.request(`${scope}`, projectId),
    enabled: enabled && !!scope && !!projectId,
    retry: (failureCount, error) =>
      !(error instanceof ApiError && error.status >= 400 && error.status < 500) && failureCount < 3
  })
}
