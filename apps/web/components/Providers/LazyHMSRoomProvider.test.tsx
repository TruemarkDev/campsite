import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'

import { loadHMSRoomProvider } from './LazyHMSRoomProvider'

const mocks = vi.hoisted(() => ({
  captureException: vi.fn()
}))

vi.mock('@sentry/nextjs', () => ({ captureException: mocks.captureException }))

describe('loadHMSRoomProvider', () => {
  it('loads the room provider when the media SDK initializes', async () => {
    const Provider = ({ children }: { children: React.ReactNode }) => <section>{children}</section>
    const LoadedProvider = await loadHMSRoomProvider(async () => ({ HMSRoomProvider: Provider }))

    render(<LoadedProvider>Application</LoadedProvider>)

    expect(screen.getByText('Application').tagName).toBe('SECTION')
  })

  it('keeps the application available when the media SDK cannot initialize', async () => {
    const error = new TypeError('WebRTC initialization failed')
    const LoadedProvider = await loadHMSRoomProvider(async () => {
      throw error
    })

    render(<LoadedProvider>Application</LoadedProvider>)

    expect(screen.getByText('Application')).toBeDefined()
    expect(mocks.captureException).toHaveBeenCalledWith(error)
  })
})
