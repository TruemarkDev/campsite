import { renderHook } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'

import { Organization } from '@campsite/types'

import { useLiveOrganizationUpdates } from './useLiveOrganizationUpdates'

const mocks = vi.hoisted(() => ({ bind: vi.fn(), invalidate: vi.fn() }))

vi.mock('@tanstack/react-query', () => ({ useQueryClient: () => ({ invalidateQueries: mocks.invalidate }) }))
vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'fixture-org' }) }))
vi.mock('@/hooks/useGetCurrentUser', () => ({ useGetCurrentUser: () => ({}) }))
vi.mock('@/utils/normy/QueryNormalizerProvider', () => ({ useQueryNormalizer: () => ({}) }))
vi.mock('@/utils/queryNormalization', () => ({ setNormalizedData: vi.fn() }))
vi.mock('./useBindChannelEvent', () => ({ useBindChannelEvent: mocks.bind }))
vi.mock('./useCurrentUserChannel', () => ({ useCurrentUserChannel: () => ({ channel: 'private-user' }) }))
vi.mock('./useOrganizationChannel', () => ({ useOrganizationChannel: () => 'organization' }))
vi.mock('@/utils/queryClient', () => ({
  setTypedQueryData: vi.fn(),
  apiClient: {
    users: { getMe: () => ({}) },
    organizations: {
      getSyncMembers: () => ({}),
      getProjectsBeadsBoard: () => ({ requestKey: (...parts: string[]) => ['board', ...parts] })
    }
  }
}))

describe('Board stale events', () => {
  it('invalidates the whole project snapshot only for this organization on the private user channel', () => {
    mocks.bind.mockClear()
    mocks.invalidate.mockClear()
    renderHook(() => useLiveOrganizationUpdates({ slug: 'fixture-org' } as Organization))
    const binding = mocks.bind.mock.calls.find((call) => call[1] === 'project-beads-board-stale')

    expect(binding?.[0]).toBe('private-user')
    const callback = binding?.[2]

    callback({ organization_slug: 'another-org', project_id: 'project-1' })
    expect(mocks.invalidate).not.toHaveBeenCalled()
    callback({ organization_slug: 'fixture-org', project_id: 'project-1' })
    expect(mocks.invalidate).toHaveBeenCalledExactlyOnceWith({ queryKey: ['board', 'fixture-org', 'project-1'] })
  })
})
