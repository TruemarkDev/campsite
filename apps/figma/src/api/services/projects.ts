import { useEffect, useRef } from 'react'
import { keepPreviousData, useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query'
import { useToken } from 'src/core/tokens'

import { client } from '../client'

export function useGetQuery(organization: string | undefined, projectId: string | undefined) {
  const token = useToken()

  return useQuery({
    queryKey: [token, 'org', organization, 'projects', projectId],
    queryFn: ({ signal }) =>
      client.organizations.getProjectsByProjectId().request(organization ?? '', projectId ?? '', {
        signal,
        headers: {
          Authorization: `Bearer ${token}`
        }
      }),
    enabled: !!token && !!organization && !!projectId
  })
}

interface SearchOptions {
  organization?: string
  query: string
}

export function useSearchQuery(options: SearchOptions) {
  const token = useToken()
  const queryClient = useQueryClient()

  const organizationRef = useRef(options.organization)

  const query = useInfiniteQuery({
    queryKey: [token, 'org', options.organization, 'projects', 'search', options.query],
    queryFn: ({ signal, pageParam }) =>
      client.organizations.getProjects().request(
        {
          orgSlug: options.organization ?? '',
          after: pageParam,
          q: options.query,
          limit: 50
        },
        {
          signal,
          headers: {
            Authorization: `Bearer ${token}`
          }
        }
      ),
    placeholderData: organizationRef.current === options.organization ? keepPreviousData : undefined,
    enabled: !!token && !!options.organization,
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (lastPage) => lastPage.next_cursor,
    getPreviousPageParam: (firstPage) => firstPage.prev_cursor
  })

  useEffect(() => {
    organizationRef.current = options.organization

    if (query.data) {
      const projects = query.data.pages.flatMap((page) => page.data)

      projects.forEach((project) => {
        queryClient.setQueryData([token, 'org', options.organization, 'projects', project.id], project)
      })
    }
  }, [options.organization, query.data, queryClient, token])

  return query
}
