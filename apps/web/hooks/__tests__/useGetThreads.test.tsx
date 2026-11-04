import { PropsWithChildren } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useGetThreads } from '../useGetThreads'

const { request } = vi.hoisted(() => ({ request: vi.fn() }))

vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'test-org' }) }))
vi.mock('@/utils/queryClient', () => ({
  apiClient: {
    organizations: {
      getThreads: () => ({
        requestKey: (params: unknown) => ['threads', params],
        request
      })
    }
  }
}))

function wrapper({ children }: PropsWithChildren) {
  return (
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      {children}
    </QueryClientProvider>
  )
}

describe('useGetThreads', () => {
  beforeEach(() => request.mockReset())

  it('fetches one window initially and loads older conversations on demand', async () => {
    request.mockResolvedValueOnce({ threads: [{ id: 'recent' }], next_cursor: 'recent' })
    request.mockResolvedValueOnce({ threads: [{ id: 'older' }], next_cursor: null })
    const { result } = renderHook(() => useGetThreads(), { wrapper })

    await waitFor(() => expect(result.current.data?.threads).toEqual([{ id: 'recent' }]))
    expect(request).toHaveBeenCalledTimes(1)
    expect(result.current.hasNextPage).toBe(true)

    await act(async () => {
      await result.current.fetchNextPage()
    })
    await waitFor(() => expect(result.current.data?.threads).toEqual([{ id: 'recent' }, { id: 'older' }]))
    expect(request).toHaveBeenLastCalledWith({ orgSlug: 'test-org', after: 'recent' })
    expect(result.current.hasNextPage).toBe(false)
  })

  it('deduplicates threads that move between windows', async () => {
    request.mockResolvedValueOnce({ threads: [{ id: 'recent' }], next_cursor: 'recent' })
    request.mockResolvedValueOnce({ threads: [{ id: 'recent' }, { id: 'older' }], next_cursor: null })
    const { result } = renderHook(() => useGetThreads(), { wrapper })

    await waitFor(() => expect(result.current.hasNextPage).toBe(true))
    await act(async () => {
      await result.current.fetchNextPage()
    })
    await waitFor(() => expect(result.current.data?.threads.map((thread) => thread.id)).toEqual(['recent', 'older']))
  })
})
