import { Api } from '@campsite/types'

import type { Context } from './types'

let baseUrl = process.env.API_BASE_URL || 'http://api.campsite.test:3001'

if (process.env.NODE_ENV === 'production') {
  const prodBaseUrl = process.env.API_BASE_URL

  if (!prodBaseUrl) {
    throw new Error('API_BASE_URL must be set in production')
  }

  baseUrl = prodBaseUrl
}

export const api = new Api({
  baseUrl,
  baseApiParams: {
    headers: { 'Content-Type': 'application/json' },
    format: 'json'
  }
})

export async function verifyConnectionAccess(context: Context, noteId: string) {
  if (context.actorType === 'agent') {
    await api.agentSyncGrants
      .postAgentSyncGrantsVerify()
      .request(
        { note_id: noteId },
        { headers: { Authorization: `Bearer ${context.token}` }, signal: AbortSignal.timeout(10_000) }
      )
    return
  }
  await api.request({
    path: `/v1/organizations/${encodeURIComponent(context.organization)}/notes/${encodeURIComponent(noteId)}/sync_state`,
    method: 'HEAD',
    format: 'text',
    headers: { Authorization: `Bearer ${context.token}` },
    signal: AbortSignal.timeout(10_000)
  })
}
