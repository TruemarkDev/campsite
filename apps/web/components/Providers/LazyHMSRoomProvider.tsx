import { ComponentType, useEffect, useState } from 'react'
import * as Sentry from '@sentry/nextjs'

interface Props {
  children: React.ReactNode
}

interface HMSRoomProviderModule {
  HMSRoomProvider: ComponentType<Props>
}

type HMSRoomProviderLoader = () => Promise<HMSRoomProviderModule>

function HMSRoomProviderUnavailable({ children }: Props) {
  return <>{children}</>
}

export async function loadHMSRoomProvider(
  load: HMSRoomProviderLoader = () => import('./HMSRoomProvider')
): Promise<ComponentType<Props>> {
  try {
    return (await load()).HMSRoomProvider
  } catch (error) {
    Sentry.captureException(error)
    return HMSRoomProviderUnavailable
  }
}

export function LazyHMSRoomProvider({ children }: Props) {
  const [Provider, setProvider] = useState<ComponentType<Props> | null>(null)

  useEffect(() => {
    let mounted = true

    loadHMSRoomProvider().then((LoadedProvider) => {
      if (mounted) setProvider(() => LoadedProvider)
    })

    return () => {
      mounted = false
    }
  }, [])

  if (!Provider) return null

  return <Provider>{children}</Provider>
}
