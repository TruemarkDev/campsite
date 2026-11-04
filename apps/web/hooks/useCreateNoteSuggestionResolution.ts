import { useMutation, useQueryClient } from '@tanstack/react-query'

import { OrganizationNoteSuggestionResolutionsPostRequest } from '@campsite/types'

import { useScope } from '@/contexts/scope'
import { apiErrorToast } from '@/utils/apiErrorToast'
import { apiClient } from '@/utils/queryClient'

const mutation = apiClient.organizations.postNotesSuggestionResolutions()
const timeline = apiClient.organizations.getNotesTimelineEvents()

export function useCreateNoteSuggestionResolution(noteId: string) {
  const { scope } = useScope()
  const queryClient = useQueryClient()
  const orgSlug = `${scope}`

  return useMutation({
    mutationFn: (data: OrganizationNoteSuggestionResolutionsPostRequest) => mutation.request(orgSlug, noteId, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: timeline.requestKey({ orgSlug, noteId }) }),
    onError: apiErrorToast
  })
}
