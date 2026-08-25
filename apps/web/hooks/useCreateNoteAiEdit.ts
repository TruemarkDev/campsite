import { useMutation } from '@tanstack/react-query'

import { OrganizationNoteAiEditsPostRequest } from '@campsite/types'

import { useScope } from '@/contexts/scope'
import { apiErrorToast } from '@/utils/apiErrorToast'
import { apiClient } from '@/utils/queryClient'

const query = apiClient.organizations.postNotesAiEdits()

export function useCreateNoteAiEdit(noteId: string) {
  const { scope } = useScope()

  return useMutation({
    mutationFn: (data: OrganizationNoteAiEditsPostRequest) => query.request(`${scope}`, noteId, data),
    onError: apiErrorToast
  })
}
