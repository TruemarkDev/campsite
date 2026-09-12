import { act, ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { ApiError } from '@campsite/types'

import { useGetProjectBeadsBoard } from './useGetProjectBeadsBoard'

const mocks = vi.hoisted(() => ({ request: vi.fn(), features: vi.fn() }))

vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'fixture-org' }) }))
vi.mock('@/hooks/useGetOrganizationFeatures', () => ({ useGetCurrentOrganizationFeatures: mocks.features }))
vi.mock('@/utils/queryClient', () => ({
  apiClient: {
    organizations: {
      getProjectsBeadsBoard: () => ({
        request: mocks.request,
        requestKey: (...parts: string[]) => ['board', ...parts]
      })
    }
  }
}))

function setup() {
  const client = new QueryClient({ defaultOptions: { queries: { retryDelay: 0 } } })
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )

  return renderHook(() => useGetProjectBeadsBoard({ projectId: 'fixture-project' }), { wrapper })
}

describe('useGetProjectBeadsBoard', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    mocks.features.mockReturnValue({ data: { features: ['channel_beads_board'] }, isPending: false, isError: false })
    mocks.request.mockResolvedValue({ source_id: 'fixture-source' })
  })

  it('scopes the request and hides cached data when the feature is disabled', async () => {
    const { result, rerender } = setup()

    await waitFor(() => expect(result.current.data?.source_id).toBe('fixture-source'))
    expect(mocks.request).toHaveBeenCalledWith('fixture-org', 'fixture-project')
    mocks.features.mockReturnValue({ data: { features: [] }, isPending: false, isError: false })
    rerender()
    expect(result.current.data).toBeUndefined()
    expect(result.current.isUnavailable).toBe(true)
    expect(mocks.request).toHaveBeenCalledTimes(1)
  })

  it.each([401, 403, 404])('removes cached content from readers after HTTP %s', async (status) => {
    const { result } = setup()

    await waitFor(() => expect(result.current.data).toBeDefined())
    mocks.request.mockRejectedValue(new ApiError(status, 'Unavailable', 'unavailable'))
    await act(async () => {
      await result.current.refetch()
    })
    await waitFor(() => expect(result.current.isUnavailable).toBe(true))
    expect(result.current.data).toBeUndefined()
    expect(mocks.request).toHaveBeenCalledTimes(2)
  })

  it('keeps the last good snapshot after a server refresh failure', async () => {
    const { result } = setup()

    await waitFor(() => expect(result.current.data).toBeDefined())
    mocks.request.mockRejectedValue(new ApiError(500, 'Unavailable', 'unavailable'))
    await act(async () => {
      await result.current.refetch()
    })
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data?.source_id).toBe('fixture-source')
    expect(result.current.isUnavailable).toBe(false)
  })

  it('does not query before the feature has loaded', () => {
    mocks.features.mockReturnValue({ data: undefined, isPending: true, isError: false })
    const { result } = setup()

    expect(result.current.isLoading).toBe(true)
    expect(result.current.isUnavailable).toBe(false)
    expect(mocks.request).not.toHaveBeenCalled()
  })
})
