import { useEffect, useState } from 'react'
import { HocuspocusProvider, type HocuspocusProviderConfiguration } from '@hocuspocus/provider'

import { SYNC_URL } from '@campsite/config'
import { NOTE_SCHEMA_VERSION } from '@campsite/editor'
import { ApiError } from '@campsite/types'

import { useScope } from '@/contexts/scope'
import { useCurrentUserIsLoggedIn } from '@/hooks/useCurrentUserIsLoggedIn'
import { apiErrorToast } from '@/utils/apiErrorToast'
import { apiClient } from '@/utils/queryClient'

export type EditorSyncState = 'connecting' | 'connected' | 'disconnected'
type EditorSyncError = 'error' | 'invalid-schema'

interface Props {
  resourceId: string
  resourceType: 'Post' | 'Note'
}

export function useEditorSync({ resourceId, resourceType }: Props) {
  const { scope } = useScope()
  const isLoggedIn = useCurrentUserIsLoggedIn()

  const [syncError, setSyncError] = useState<EditorSyncError | null>(null)
  const [syncState, setSyncState] = useState<EditorSyncState>('connecting')
  const [hasSynced, setHasSynced] = useState(false)

  const [provider] = useState(() => {
    // v3 removed the `parameters` config option; pass them via the URL instead
    const parameters = new URLSearchParams({
      schemaVersion: String(NOTE_SCHEMA_VERSION),
      organization: String(scope),
      type: resourceType
    })

    const configuration: HocuspocusProviderConfiguration & { autoConnect: boolean } = {
      autoConnect: false,
      url: `${SYNC_URL}?${parameters}`,
      name: resourceId,
      token: () =>
        apiClient.users
          .postMeSyncToken()
          .request()
          .then((res) => res.token)
          .catch((error: ApiError) => {
            apiErrorToast(error)
            return ''
          }),
      onStateless: (data) => {
        const message = JSON.parse(data.payload)

        if (message.type === 'schema' && NOTE_SCHEMA_VERSION < message.version) {
          setSyncError('invalid-schema')
        }
      },
      onAuthenticationFailed() {
        setSyncError('error')
      },
      onAuthenticated() {
        // don't clear invalid-schema errors on auth
        if (syncError !== 'invalid-schema') {
          setSyncError(null)
        }
      },
      onStatus(data) {
        setSyncState(data.status)
      },
      onSynced({ state }) {
        if (state) setHasSynced(true)
      }
    }

    return new HocuspocusProvider(configuration)
  })

  useEffect(() => {
    if (isLoggedIn) provider.connect()

    return () => {
      // This also cancels a socket that is still connecting. Checking only for
      // Connected leaks providers during React Strict Mode's effect cleanup.
      provider.disconnect()
    }
  }, [isLoggedIn, provider])

  return [provider, syncState, syncError, hasSynced] as const
}
