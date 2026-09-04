import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { AuthProvider } from './AuthProvider'

const mocks = vi.hoisted(() => ({
  currentUser: {
    data: undefined,
    isLoading: true,
    error: null,
    isSuccess: false
  }
}))

vi.mock('@sentry/nextjs', () => ({ setUser: vi.fn(), setContext: vi.fn() }))
vi.mock('@todesktop/client-core', () => ({ appMenu: { add: vi.fn(), refresh: vi.fn() } }))
vi.mock('@/hooks/useGetCurrentUser', () => ({ useGetCurrentUser: () => mocks.currentUser }))
vi.mock('next/router', () => ({ useRouter: () => ({ query: {}, asPath: '/', push: vi.fn() }) }))
vi.mock('@campsite/ui/src/hooks', () => ({ useHasMounted: () => true, useIsDesktopApp: () => false }))
vi.mock('@/components/Error', () => ({ FullPageError: () => <div>Error</div> }))
vi.mock('@/components/FullPageLoading', () => ({ FullPageLoading: () => <div>Loading</div> }))
vi.mock('@/hooks/useGetCurrentOrganization', () => ({
  useGetCurrentOrganization: () => ({ data: undefined, isLoading: false, error: null })
}))
vi.mock('@/hooks/useGetOrganizationMemberships', () => ({
  useGetOrganizationMemberships: () => ({ isLoading: false })
}))
vi.mock('@/utils/queryClient', () => ({ signinUrl: () => '/sign-in' }))

describe('AuthProvider', () => {
  beforeEach(() => {
    mocks.currentUser.data = undefined
    mocks.currentUser.isLoading = true
    mocks.currentUser.error = null
    mocks.currentUser.isSuccess = false
  })

  it('does not mount application providers while the current user is loading', () => {
    render(
      <AuthProvider allowLoggedOut={false}>
        <div>Application</div>
      </AuthProvider>
    )

    expect(screen.getByText('Loading')).toBeDefined()
    expect(screen.queryByText('Application')).toBeNull()
  })
})
