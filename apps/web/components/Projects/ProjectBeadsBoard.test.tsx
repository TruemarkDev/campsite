import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'

import { BeadsCard, Project, ProjectBeadsBoard } from '@campsite/types'

import { ProjectBeadsBoardView } from './ProjectBeadsBoard'

const project = { id: 'project-1', archived: false } as Project

function card(overrides: Partial<BeadsCard> = {}): BeadsCard {
  return {
    id: 'task-1',
    title: 'Ship the board',
    status: 'open',
    board_state: 'Ready',
    priority: 1,
    issue_type: 'task',
    assignee: 'Ada',
    owner: null,
    labels: ['web'],
    parent_id: null,
    dependencies: [],
    created_at: '2026-08-27T10:00:00Z',
    updated_at: '2026-08-28T10:00:00Z',
    closed_at: null,
    ...overrides
  }
}

function board(cards: BeadsCard[], overrides: Partial<ProjectBeadsBoard> = {}): ProjectBeadsBoard {
  return {
    source_id: 'source-1',
    source_project_id: 'beads-project-1',
    repository_display_name: 'Campsite',
    verified_at: '2026-08-27T10:00:00Z',
    last_successful_collection_at: '2026-08-28T10:00:00Z',
    last_successful_ingest_at: '2026-08-28T10:01:00Z',
    current_snapshot: {
      schema_version: 1,
      beads_version: '1.2.2',
      beads_schema_version: null,
      branch: 'main',
      revision: 'abc123',
      collected_at: '2026-08-28T10:00:00Z',
      ingested_at: '2026-08-28T10:01:00Z',
      digest: 'digest-1',
      cards
    },
    agents: [],
    ...overrides
  }
}

function renderBoard(
  value: ProjectBeadsBoard,
  props: Partial<React.ComponentProps<typeof ProjectBeadsBoardView>> = {}
) {
  return render(
    <ProjectBeadsBoardView
      project={project}
      board={value}
      isLoading={false}
      isError={false}
      onRetry={vi.fn()}
      {...props}
    />
  )
}

describe('ProjectBeadsBoardView', () => {
  it('renders untrusted task metadata as plain text and safe blocker ids', () => {
    const title = '<img src=x onerror=alert(1)> **plain**'

    const { container } = renderBoard(
      board([
        card({
          title,
          board_state: 'Blocked',
          dependencies: [{ id: 'task-0', type: 'blocks' }],
          labels: ['<script>nope</script>']
        })
      ])
    )

    expect(screen.getByText(title)).not.toBeNull()
    expect(screen.getByText('Blocked by task-0')).not.toBeNull()
    expect(container.querySelector('img')).toBeNull()
    expect(container.querySelector('script')).toBeNull()
  })

  it('filters cards without changing their source columns', () => {
    renderBoard(
      board([
        card(),
        card({
          id: 'bug-2',
          title: 'Fix sync',
          board_state: 'In progress',
          issue_type: 'bug',
          priority: 2,
          assignee: 'Grace'
        })
      ])
    )

    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'sync' } })

    expect(screen.queryByText('Ship the board')).toBeNull()
    expect(screen.getByText('Fix sync')).not.toBeNull()
    expect(within(screen.getByRole('region', { name: 'In progress' })).getByText('Fix sync')).not.toBeNull()
  })

  it('hides Closed by default and progressively reveals long history', () => {
    const closedCards = Array.from({ length: 21 }, (_, index) =>
      card({ id: `closed-${index}`, title: `Closed task ${index}`, board_state: 'Closed', status: 'closed' })
    )

    renderBoard(board(closedCards))

    expect(screen.queryByRole('region', { name: 'Closed' })).toBeNull()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Include Closed' }))
    expect(screen.getAllByText(/Closed task/)).toHaveLength(20)
    fireEvent.click(screen.getByRole('button', { name: 'Show more Closed' }))
    expect(screen.getAllByText(/Closed task/)).toHaveLength(21)
  })

  it('distinguishes waiting for first snapshot from an empty snapshot', () => {
    const value = board([], { current_snapshot: null })

    renderBoard(value)

    expect(screen.getByText('Waiting for the first snapshot')).not.toBeNull()
    expect(screen.queryByLabelText('Beads Board')).toBeNull()
  })

  it('keeps the last snapshot visible after a refresh error', () => {
    renderBoard(board([card()]), { isError: true })

    expect(screen.getByText('Ship the board')).not.toBeNull()
    expect(screen.getByRole('status').textContent).toContain('Showing the last published snapshot')
  })
})
