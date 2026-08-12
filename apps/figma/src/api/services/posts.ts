import { useEffect, useRef } from 'react'
import { keepPreviousData, useMutation, useQuery } from '@tanstack/react-query'
import { useToken } from 'src/core/tokens'

import { OrganizationPostSharesPostRequest, OrganizationsOrgSlugPostsPostRequest } from '@campsite/types/generated'

import { client } from '../client'
import { useMeQuery } from './auth'

interface SearchOptions {
  query: string
  organization?: string
}

export function useSearchQuery(options: SearchOptions) {
  const token = useToken()
  const { data: me } = useMeQuery()

  const organizationRef = useRef(options.organization)

  const query = useQuery({
    queryKey: [token, 'org', options.organization, 'posts', 'search', options.query, me?.username],
    queryFn: ({ signal }) =>
      client.organizations.getSearchPosts().request(
        {
          orgSlug: options.organization ?? '',
          q: options.query,
          author: me?.username
        },
        {
          signal,
          headers: {
            Authorization: `Bearer ${token}`
          }
        }
      ),
    placeholderData: organizationRef.current === options.organization ? keepPreviousData : undefined,
    enabled: !!token && !!options.organization && !!me
  })

  // Only advance the ref once the new org's data has arrived (mirrors the
  // v4 onSuccess behavior) so keepPreviousData never shows another org's results
  const hasFreshData = query.isSuccess && !query.isPlaceholderData

  useEffect(() => {
    if (hasFreshData) {
      organizationRef.current = options.organization
    }
  }, [hasFreshData, options.organization])

  return query
}

interface CreateOptions {
  organization: string
  data: OrganizationsOrgSlugPostsPostRequest
}

export function useCreateMutation() {
  const token = useToken()

  return useMutation({
    mutationFn: (data: CreateOptions) =>
      client.organizations.postPosts().request(data.organization, data.data, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      })
  })
}

interface ShareOptions {
  organization: string
  postId: string
  data: OrganizationPostSharesPostRequest
}

export function useCreateShare() {
  const token = useToken()

  return useMutation({
    mutationFn: (data: ShareOptions) =>
      client.organizations.postPostsShares().request(data.organization, data.postId, data.data, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      })
  })
}
