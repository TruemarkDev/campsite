import { StrictMode } from 'react'
import { act, renderHook } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useEditorSync } from './useEditorSync'

const mocks = vi.hoisted(() => ({
  instances: [] as Array<{
    configuration: Record<string, unknown>
    connect: ReturnType<typeof vi.fn>
    disconnect: ReturnType<typeof vi.fn>
  }>,
  isLoggedIn: true
}))

vi.mock('@hocuspocus/provider', () => ({
  HocuspocusProvider: class {
    configuration: Record<string, unknown>
    connect = vi.fn()
    disconnect = vi.fn()

    constructor(configuration: Record<string, unknown>) {
      this.configuration = configuration
      mocks.instances.push(this)
    }
  }
}))
vi.mock('@campsite/config', () => ({ SYNC_URL: 'ws://sync.test' }))
vi.mock('@campsite/editor', () => ({ NOTE_SCHEMA_VERSION: 10 }))
vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'acme' }) }))
vi.mock('@/hooks/useCurrentUserIsLoggedIn', () => ({
  useCurrentUserIsLoggedIn: () => mocks.isLoggedIn
}))
vi.mock('@/utils/apiErrorToast', () => ({ apiErrorToast: vi.fn() }))
vi.mock('@/utils/queryClient', () => ({
  apiClient: {
    users: {
      postMeSyncToken: () => ({ request: vi.fn().mockResolvedValue({ token: 'token' }) })
    }
  }
}))

describe('useEditorSync', () => {
  beforeEach(() => {
    mocks.instances.length = 0
    mocks.isLoggedIn = true
  })

  it('does not connect discarded Strict Mode providers during render', () => {
    const { result, unmount } = renderHook(() => useEditorSync({ resourceId: 'note-1', resourceType: 'Note' }), {
      wrapper: StrictMode
    })
    const provider = result.current[0] as unknown as (typeof mocks.instances)[number]

    expect(provider.configuration).toMatchObject({
      autoConnect: false,
      name: 'note-1',
      url: 'ws://sync.test?schemaVersion=10&organization=acme&type=Note'
    })
    expect(provider.configuration).not.toHaveProperty('document')
    for (const discarded of mocks.instances.filter((instance) => instance !== provider)) {
      expect(discarded.connect).not.toHaveBeenCalled()
    }

    unmount()
    expect(provider.disconnect).toHaveBeenCalled()
  })

  it('waits for authentication and exposes the first authoritative sync', () => {
    mocks.isLoggedIn = false
    const { result, rerender } = renderHook(() => useEditorSync({ resourceId: 'note-1', resourceType: 'Note' }))
    const provider = result.current[0] as unknown as (typeof mocks.instances)[number]

    expect(provider.connect).not.toHaveBeenCalled()
    expect(result.current[3]).toBe(false)

    mocks.isLoggedIn = true
    rerender()
    expect(provider.connect).toHaveBeenCalledTimes(1)

    act(() => {
      const onSynced = provider.configuration.onSynced as (data: { state: boolean }) => void

      onSynced({ state: true })
    })
    expect(result.current[3]).toBe(true)
  })
})
