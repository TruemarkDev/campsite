import { z } from 'zod'

import { OrganizationsOrgSlugOauthApplicationsPostRequest } from '@campsite/types/generated'

// Shared by the create dialog and general settings form. The `satisfies` anchor
// fails the build if the API's create/update payload fields drift from this schema.
export const oauthApplicationFormSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  avatar_path: z.string().optional()
}) satisfies z.ZodType<Pick<OrganizationsOrgSlugOauthApplicationsPostRequest, 'name' | 'avatar_path'>>

export type OauthApplicationFormSchema = z.infer<typeof oauthApplicationFormSchema>
