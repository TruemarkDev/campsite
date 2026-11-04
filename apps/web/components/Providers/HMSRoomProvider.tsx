import { HMSRoomProvider as Provider } from '@100mslive/react-sdk'

import { HMSRoomStateSubscriber } from '@/components/Providers/HMSRoomStateSubscriber'

interface Props {
  children: React.ReactNode
}

export function HMSRoomProvider({ children }: Props) {
  return (
    <Provider>
      <HMSRoomStateSubscriber />
      {children}
    </Provider>
  )
}
