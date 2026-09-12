import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { Project, ProjectBeadsBoard, ProjectBeadsPairing } from '@campsite/types'

import { ProjectSidebarBeadsSource } from './ProjectSidebarBeadsSource'

const mocks = vi.hoisted(() => ({
  createPairing: vi.fn(),
  deleteSource: vi.fn(),
  replaceRoute: vi.fn(),
  useCurrentOrganizationHasFeature: vi.fn(),
  useGetProjectBeadsBoard: vi.fn(),
  useGetProjectOauthApps: vi.fn()
}))

vi.mock('next/router', () => ({
  useRouter: () => ({ pathname: '/[org]/projects/[projectId]/board', replace: mocks.replaceRoute })
}))

vi.mock('@/contexts/scope', () => ({ useScope: () => ({ scope: 'acme' }) }))
vi.mock('@/hooks/useCurrentOrganizationHasFeature', () => ({
  useCurrentOrganizationHasFeature: mocks.useCurrentOrganizationHasFeature
}))
vi.mock('@/hooks/useGetProjectBeadsBoard', () => ({ useGetProjectBeadsBoard: mocks.useGetProjectBeadsBoard }))
vi.mock('@/hooks/useGetProjectOauthApps', () => ({ useGetProjectOauthApps: mocks.useGetProjectOauthApps }))
vi.mock('@/utils/apiErrorToast', () => ({ apiErrorToast: vi.fn() }))
vi.mock('@/utils/queryClient', () => ({
  apiClient: {
    organizations: {
      postProjectsBeadsSourcePairings: () => ({ request: mocks.createPairing }),
      deleteProjectsBeadsSource: () => ({ request: mocks.deleteSource }),
      getProjectsBeadsBoard: () => ({ requestKey: (...parts: string[]) => ['board', ...parts] }),
      getProjectsBeadsSource: () => ({ requestKey: (...parts: string[]) => ['source', ...parts] })
    }
  }
}))

const project = {
  id: 'project-1',
  archived: false,
  personal: false,
  viewer_is_member: true,
  viewer_can_update: true,
  viewer_can_manage_beads_source: true
} as Project

const currentBoard: ProjectBeadsBoard = {
  source_id: 'source-current',
  source_project_id: 'beads-current',
  repository_display_name: 'Current repository',
  verified_at: '2026-08-27T10:00:00Z',
  last_successful_collection_at: '2026-08-28T10:00:00Z',
  last_successful_ingest_at: '2026-08-28T10:01:00Z',
  current_snapshot: {
    schema_version: 1,
    beads_version: '1.2.2',
    beads_schema_version: null,
    branch: 'main',
    revision: 'current-revision',
    collected_at: '2026-08-28T10:00:00Z',
    ingested_at: '2026-08-28T10:01:00Z',
    digest: 'digest-current',
    cards: []
  },
  agents: []
}

const pendingPairing: ProjectBeadsPairing = {
  challenge: 'replacement-challenge',
  expires_at: '2099-08-28T12:00:00Z'
}

function renderSource(value: Project = project) {
  const queryClient = new QueryClient({ defaultOptions: { mutations: { retry: false }, queries: { retry: false } } })

  return render(
    <QueryClientProvider client={queryClient}>
      <ProjectSidebarBeadsSource project={value} />
    </QueryClientProvider>
  )
}

function expectCurrentBoardVisible() {
  expect(screen.getByText('Current repository')).not.toBeNull()
  expect(screen.getByText('current-revision')).not.toBeNull()
}

describe('ProjectSidebarBeadsSource', () => {
  it('hides setup and cached source metadata when the feature is disabled', () => {
    mocks.useCurrentOrganizationHasFeature.mockReturnValue(false)
    renderSource()

    expect(screen.queryByText('Current repository')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Replace source' })).toBeNull()
  })

  beforeEach(() => {
    vi.clearAllMocks()
    vi.useRealTimers()
    mocks.useCurrentOrganizationHasFeature.mockReturnValue(true)
    mocks.useGetProjectBeadsBoard.mockReturnValue({ data: currentBoard })
    mocks.useGetProjectOauthApps.mockReturnValue({
      data: [{ id: 'connector-2', name: 'Replacement publisher' }],
      isLoading: false
    })
    mocks.createPairing.mockResolvedValue(pendingPairing)
    mocks.deleteSource.mockResolvedValue({})
    mocks.replaceRoute.mockResolvedValue(true)
  })

  it('starts replacement pairing separately while preserving the current Board', async () => {
    const { rerender } = renderSource()

    fireEvent.click(screen.getByRole('button', { name: 'Replace source' }))
    fireEvent.change(screen.getByLabelText('Publisher application'), { target: { value: 'connector-2' } })
    fireEvent.click(screen.getByRole('button', { name: 'Start replacement pairing' }))

    await screen.findByText(/Replacement pairing pending/)
    expect(mocks.createPairing).toHaveBeenCalledWith('acme', 'project-1', {
      oauth_application_id: 'connector-2'
    })
    expectCurrentBoardVisible()

    mocks.useGetProjectBeadsBoard.mockReturnValue({
      data: {
        ...currentBoard,
        source_project_id: 'beads-replacement',
        repository_display_name: 'Replacement repository',
        verified_at: '2026-08-28T11:00:00Z'
      }
    })
    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <ProjectSidebarBeadsSource project={project} />
      </QueryClientProvider>
    )
    expect(screen.getByText('Replacement repository')).not.toBeNull()
    expect(screen.queryByText(/Replacement pairing pending/)).toBeNull()
  })

  it('keeps the current Board when replacement pairing fails', async () => {
    mocks.createPairing.mockRejectedValue(new Error('pairing failed'))
    renderSource()

    fireEvent.click(screen.getByRole('button', { name: 'Replace source' }))
    fireEvent.change(screen.getByLabelText('Publisher application'), { target: { value: 'connector-2' } })
    fireEvent.click(screen.getByRole('button', { name: 'Start replacement pairing' }))

    await waitFor(() => expect(mocks.createPairing).toHaveBeenCalledOnce())
    expect(screen.getByRole('button', { name: 'Start replacement pairing' })).not.toBeNull()
    expectCurrentBoardVisible()
  })

  it('keeps the current Board when replacement is cancelled', async () => {
    renderSource()

    fireEvent.click(screen.getByRole('button', { name: 'Replace source' }))
    fireEvent.change(screen.getByLabelText('Publisher application'), { target: { value: 'connector-2' } })
    fireEvent.click(screen.getByRole('button', { name: 'Start replacement pairing' }))

    await screen.findByText(/Replacement pairing pending/)
    fireEvent.click(screen.getByRole('button', { name: 'Cancel replacement' }))
    expect(screen.queryByText(/Replacement pairing pending/)).toBeNull()
    expectCurrentBoardVisible()
  })

  it('keeps the current Board when replacement pairing expires', async () => {
    mocks.createPairing.mockResolvedValue({ ...pendingPairing, expires_at: '2000-08-28T12:00:00Z' })
    renderSource()

    fireEvent.click(screen.getByRole('button', { name: 'Replace source' }))
    fireEvent.change(screen.getByLabelText('Publisher application'), { target: { value: 'connector-2' } })
    fireEvent.click(screen.getByRole('button', { name: 'Start replacement pairing' }))

    await screen.findByText(/Replacement pairing expired/)
    expectCurrentBoardVisible()
  })

  it('requires a separate destructive confirmation before detaching', async () => {
    renderSource()

    expect(screen.getByRole('button', { name: 'Replace source' })).not.toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Detach source' }))
    expect(screen.getByText(/remove its cached Board snapshots/)).not.toBeNull()
    expect(mocks.deleteSource).not.toHaveBeenCalled()

    fireEvent.click(screen.getByRole('button', { name: 'Confirm detach' }))

    await waitFor(() => expect(mocks.deleteSource).toHaveBeenCalledWith('acme', 'project-1'))
    expect(mocks.replaceRoute).toHaveBeenCalledWith('/acme/projects/project-1')
  })

  it('does not expose source controls without membership and management permission', () => {
    const { rerender } = renderSource({ ...project, viewer_can_manage_beads_source: false } as Project)

    expectCurrentBoardVisible()
    expect(screen.queryByRole('button', { name: 'Replace source' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Detach source' })).toBeNull()
    expect(mocks.useGetProjectOauthApps).toHaveBeenLastCalledWith({ projectId: 'project-1', enabled: false })

    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <ProjectSidebarBeadsSource project={{ ...project, viewer_is_member: false } as Project} />
      </QueryClientProvider>
    )
    expect(screen.queryByRole('region', { name: 'Beads' })).toBeNull()
  })

  it('uses labelled native controls that remain keyboard focusable', () => {
    renderSource()

    const replace = screen.getByRole('button', { name: 'Replace source' })
    const detach = screen.getByRole('button', { name: 'Detach source' })

    replace.focus()
    expect(document.activeElement).toBe(replace)
    detach.focus()
    expect(document.activeElement).toBe(detach)

    fireEvent.click(replace)
    const connector = screen.getByLabelText('Publisher application')

    connector.focus()
    expect(document.activeElement).toBe(connector)
    expect(connector.tagName).toBe('SELECT')
    expect(screen.getByRole('button', { name: 'Start replacement pairing' }).tabIndex).toBe(0)
  })
})
