import { useQuery } from '@tanstack/react-query'

import { ApiError } from '@campsite/types'

import { useScope } from '@/contexts/scope'
import { useGetCurrentOrganizationFeatures } from '@/hooks/useGetOrganizationFeatures'
import { apiClient } from '@/utils/queryClient'

export const getProjectBeadsBoard = apiClient.organizations.getProjectsBeadsBoard()

export function useGetProjectBeadsBoard({
  projectId,
  enabled = true,
  refetchInterval = false
}: {
  projectId: string
  enabled?: boolean
  refetchInterval?: number | false
}) {
  const { scope } = useScope()
  const features = useGetCurrentOrganizationFeatures()
  const featureEnabled = !!features.data?.features?.includes('channel_beads_board')

  const query = useQuery({
    queryKey: getProjectBeadsBoard.requestKey(`${scope}`, projectId),
    queryFn: () => getProjectBeadsBoard.request(`${scope}`, projectId),
    enabled: featureEnabled && enabled && !!scope && !!projectId,
    refetchInterval,
    retry: (failureCount, error) =>
      !(error instanceof ApiError && error.status >= 400 && error.status < 500) && failureCount < 3
  })

  const accessDenied = query.error instanceof ApiError && [401, 403, 404].includes(query.error.status)

  return {
    ...query,
    data: featureEnabled && enabled && !accessDenied ? query.data : undefined,
    isLoading: query.isLoading || (enabled && features.isPending),
    isError: query.isError || features.isError,
    isUnavailable: accessDenied || (!features.isPending && !features.isError && !featureEnabled)
  }
}
