import { useMemo, useState } from 'react'

import { BeadsCard, Project, ProjectBeadsBoard } from '@campsite/types'
import { Button, Checkbox, UIText } from '@campsite/ui'

import { IndexPageEmptyState, IndexPageLoading } from '@/components/IndexPages/components'
import { ProjectArchiveBanner } from '@/components/Projects/ProjectArchiveBanner'
import { PROJECT_PAGE_SCROLL_CONTAINER_ID } from '@/components/Projects/utils'
import { longTimestamp } from '@/utils/timestamp'

const BOARD_STATES = ['Ready', 'In progress', 'Blocked', 'Closed'] as const
const CLOSED_PAGE_SIZE = 20

interface ProjectBeadsBoardProps {
  project: Project
  board?: ProjectBeadsBoard
  isLoading: boolean
  isError: boolean
  onRetry: () => void
}

export function ProjectBeadsBoardView({ project, board, isLoading, isError, onRetry }: ProjectBeadsBoardProps) {
  if (isLoading) return <IndexPageLoading />

  if (!board) {
    return (
      <IndexPageEmptyState>
        <UIText weight='font-semibold'>Board is unavailable</UIText>
        <UIText secondary>The attached Beads source could not be loaded.</UIText>
        <Button onClick={onRetry}>Try again</Button>
      </IndexPageEmptyState>
    )
  }

  if (!board.current_snapshot) {
    return (
      <IndexPageEmptyState>
        <UIText weight='font-semibold'>Waiting for the first snapshot</UIText>
        <UIText secondary>
          {board.repository_display_name} is attached. Board cards will appear after its publisher sends a snapshot.
        </UIText>
        <SourceIdentity board={board} />
      </IndexPageEmptyState>
    )
  }

  return <BoardContent project={project} board={board} isLastGood={isError} onRetry={onRetry} />
}

function BoardContent({
  project,
  board,
  isLastGood,
  onRetry
}: {
  project: Project
  board: ProjectBeadsBoard
  isLastGood: boolean
  onRetry: () => void
}) {
  const snapshot = board.current_snapshot!
  const [query, setQuery] = useState('')
  const [issueType, setIssueType] = useState('')
  const [priority, setPriority] = useState('')
  const [assignee, setAssignee] = useState('')
  const [label, setLabel] = useState('')
  const [includeClosed, setIncludeClosed] = useState(false)
  const [closedLimit, setClosedLimit] = useState(CLOSED_PAGE_SIZE)

  const options = useMemo(() => collectFilterOptions(snapshot.cards), [snapshot.cards])
  const filteredCards = useMemo(
    () =>
      snapshot.cards.filter((card) => {
        const normalizedQuery = query.trim().toLocaleLowerCase()

        return (
          (!normalizedQuery ||
            card.id.toLocaleLowerCase().includes(normalizedQuery) ||
            card.title.toLocaleLowerCase().includes(normalizedQuery)) &&
          (!issueType || card.issue_type === issueType) &&
          (!priority || `${card.priority}` === priority) &&
          (!assignee || card.assignee === assignee) &&
          (!label || card.labels.includes(label))
        )
      }),
    [assignee, issueType, label, priority, query, snapshot.cards]
  )

  return (
    <div id={PROJECT_PAGE_SCROLL_CONTAINER_ID} className='flex min-h-0 flex-1 flex-col overflow-hidden'>
      <div className='flex flex-col gap-3 border-b px-4 py-3'>
        <div className='flex flex-wrap items-center gap-2'>
          <label className='min-w-48 flex-1'>
            <span className='sr-only'>Filter by task id or title</span>
            <input
              className='bg-secondary w-full rounded-md border px-3 py-1.5 text-sm outline-none focus-visible:ring-2'
              type='search'
              placeholder='Filter by task id or title'
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </label>
          <FilterSelect label='Issue type' value={issueType} options={options.issueTypes} onChange={setIssueType} />
          <FilterSelect label='Priority' value={priority} options={options.priorities} onChange={setPriority} />
          <FilterSelect label='Assignee' value={assignee} options={options.assignees} onChange={setAssignee} />
          <FilterSelect label='Label' value={label} options={options.labels} onChange={setLabel} />
          <label className='flex items-center gap-2 text-sm whitespace-nowrap'>
            <Checkbox checked={includeClosed} onChange={setIncludeClosed} />
            Include Closed
          </label>
        </div>

        <div className='text-secondary flex flex-wrap items-center gap-x-3 gap-y-1 text-xs'>
          <span>{board.repository_display_name}</span>
          <span>Revision {snapshot.revision}</span>
          <span>Collected {longTimestamp(snapshot.collected_at)}</span>
          <span>Ingested {longTimestamp(snapshot.ingested_at)}</span>
          {project.archived && <ProjectArchiveBanner />}
        </div>

        {isLastGood && (
          <div
            role='status'
            className='flex items-center justify-between gap-3 rounded-md border border-yellow-500/30 bg-yellow-500/10 px-3 py-2 text-sm'
          >
            <span>Showing the last published snapshot because the latest refresh failed.</span>
            <Button size='sm' onClick={onRetry}>
              Retry
            </Button>
          </div>
        )}
      </div>

      <div className='flex min-h-0 flex-1 snap-x gap-3 overflow-x-auto p-3' aria-label='Beads Board'>
        {BOARD_STATES.map((state) => {
          const cards = filteredCards.filter((card) => card.board_state === state)
          const visibleCards = state === 'Closed' ? cards.slice(0, closedLimit) : cards
          const isHidden = state === 'Closed' && !includeClosed

          if (isHidden) return null

          return (
            <section
              key={state}
              aria-labelledby={`beads-column-${state.replaceAll(' ', '-').toLocaleLowerCase()}`}
              className='bg-secondary w-[min(85vw,20rem)] min-w-[min(85vw,20rem)] snap-start rounded-lg border p-2'
            >
              <div className='flex items-center justify-between px-1 pb-2'>
                <UIText id={`beads-column-${state.replaceAll(' ', '-').toLocaleLowerCase()}`} weight='font-semibold'>
                  {state}
                </UIText>
                <UIText tertiary>{cards.length}</UIText>
              </div>
              <div className='flex flex-col gap-2'>
                {visibleCards.map((card) => (
                  <BeadsBoardCard key={card.id} card={card} />
                ))}
                {cards.length === 0 && (
                  <UIText tertiary className='px-1 py-3 text-center'>
                    No matching tasks
                  </UIText>
                )}
                {state === 'Closed' && visibleCards.length < cards.length && (
                  <Button fullWidth onClick={() => setClosedLimit((value) => value + CLOSED_PAGE_SIZE)}>
                    Show more Closed
                  </Button>
                )}
              </div>
            </section>
          )
        })}
      </div>
    </div>
  )
}

function FilterSelect({
  label,
  value,
  options,
  onChange
}: {
  label: string
  value: string
  options: string[]
  onChange: (value: string) => void
}) {
  return (
    <label>
      <span className='sr-only'>{label}</span>
      <select
        aria-label={label}
        className='bg-secondary max-w-40 rounded-md border px-2 py-1.5 text-sm'
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value=''>{label}: All</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </label>
  )
}

export function BeadsBoardCard({ card }: { card: BeadsCard }) {
  const blockerIds = card.dependencies
    .filter((dependency) => dependency.type === 'blocks')
    .map((dependency) => dependency.id)

  return (
    <article
      className='bg-primary flex flex-col gap-2 rounded-md border p-3 text-sm'
      aria-label={`${card.id}: ${card.title}`}
    >
      <div className='flex items-start justify-between gap-2'>
        <UIText className='min-w-0 break-words' weight='font-medium'>
          {card.title}
        </UIText>
        <span className='text-tertiary shrink-0 font-mono text-xs'>{card.id}</span>
      </div>
      <div className='text-secondary flex flex-wrap gap-1 text-xs'>
        <span>{card.issue_type}</span>
        <span aria-label={`Priority ${card.priority}`}>P{card.priority}</span>
        <span>{card.status}</span>
        {card.assignee && <span>{card.assignee}</span>}
      </div>
      {card.labels.length > 0 && <div className='text-tertiary text-xs break-words'>{card.labels.join(', ')}</div>}
      {card.board_state === 'Blocked' && blockerIds.length > 0 && (
        <div className='text-secondary text-xs break-words'>Blocked by {blockerIds.join(', ')}</div>
      )}
    </article>
  )
}

function SourceIdentity({ board }: { board: ProjectBeadsBoard }) {
  return (
    <dl className='grid grid-cols-[auto_1fr] gap-x-2 text-left text-sm'>
      <dt className='text-tertiary'>Source</dt>
      <dd>{board.source_project_id}</dd>
      <dt className='text-tertiary'>Verified</dt>
      <dd>{longTimestamp(board.verified_at)}</dd>
    </dl>
  )
}

function collectFilterOptions(cards: BeadsCard[]) {
  const unique = (values: Array<string | null>) =>
    [...new Set(values.filter((value): value is string => !!value))].sort()

  return {
    issueTypes: unique(cards.map((card) => card.issue_type)),
    priorities: unique(cards.map((card) => `${card.priority}`)),
    assignees: unique(cards.map((card) => card.assignee)),
    labels: unique(cards.flatMap((card) => card.labels))
  }
}
