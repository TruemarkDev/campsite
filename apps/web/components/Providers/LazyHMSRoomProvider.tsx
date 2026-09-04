import { ComponentType } from 'react'
import * as Sentry from '@sentry/nextjs'
import dynamic from 'next/dynamic'

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

export const LazyHMSRoomProvider = dynamic<Props>(() => loadHMSRoomProvider(), { ssr: false })
