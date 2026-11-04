import { describe, expect, it } from 'vitest'

describe('webrtc-adapter compatibility patch', () => {
  it('loads the media SDK with an immutable RTCPeerConnection prototype', async () => {
    class RTCPeerConnection {}

    Object.freeze(RTCPeerConnection.prototype)

    const testNavigator = window.navigator as Navigator & { webkitGetUserMedia?: () => void }
    const originalPeerConnection = Object.getOwnPropertyDescriptor(window, 'RTCPeerConnection')
    const originalUserAgent = Object.getOwnPropertyDescriptor(testNavigator, 'userAgent')
    const originalGetUserMedia = Object.getOwnPropertyDescriptor(testNavigator, 'webkitGetUserMedia')

    Object.defineProperty(window, 'RTCPeerConnection', { configurable: true, value: RTCPeerConnection })
    Object.defineProperty(testNavigator, 'userAgent', {
      configurable: true,
      value: 'Mozilla/5.0 Chrome/152.0.0.0'
    })
    Object.defineProperty(testNavigator, 'webkitGetUserMedia', { configurable: true, value: () => undefined })

    try {
      await expect(import('@100mslive/react-sdk')).resolves.toBeDefined()
    } finally {
      if (originalPeerConnection) Object.defineProperty(window, 'RTCPeerConnection', originalPeerConnection)
      else Reflect.deleteProperty(window, 'RTCPeerConnection')

      if (originalUserAgent) Object.defineProperty(testNavigator, 'userAgent', originalUserAgent)
      if (originalGetUserMedia) Object.defineProperty(testNavigator, 'webkitGetUserMedia', originalGetUserMedia)
      else Reflect.deleteProperty(testNavigator, 'webkitGetUserMedia')
    }
  })
})
