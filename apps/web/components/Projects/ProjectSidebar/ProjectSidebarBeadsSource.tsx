import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/router'

import { Project, ProjectBeadsBoard, ProjectBeadsPairing } from '@campsite/types'
import { Button, UIText } from '@campsite/ui'

import { useScope } from '@/contexts/scope'
import { useGetCurrentUser } from '@/hooks/useGetCurrentUser'
import { useGetProjectBeadsBoard } from '@/hooks/useGetProjectBeadsBoard'
import { useGetProjectOauthApps } from '@/hooks/useGetProjectOauthApps'
import { apiErrorToast } from '@/utils/apiErrorToast'
import { apiClient } from '@/utils/queryClient'
import { longTimestamp } from '@/utils/timestamp'

const createPairing = apiClient.organizations.postProjectsBeadsSourcePairings()
const deleteSource = apiClient.organizations.deleteProjectsBeadsSource()
const getBoard = apiClient.organizations.getProjectsBeadsBoard()
const getSource = apiClient.organizations.getProjectsBeadsSource()

export function ProjectSidebarBeadsSource({ project }: { project: Project }) {
  const router = useRouter()
  const queryClient = useQueryClient()
  const { scope } = useScope()
  const [selectedApplicationId, setSelectedApplicationId] = useState('')
  const [pairing, setPairing] = useState<ProjectBeadsPairing>()
  const [managementMode, setManagementMode] = useState<'replace' | 'detach'>()
  const [replacementSourceVerifiedAt, setReplacementSourceVerifiedAt] = useState<string>()
  const currentUser = useGetCurrentUser().data
  const canManageSource =
    project.viewer_is_member && project.viewer_can_update && currentUser?.unconfirmed_email === null
  const boardQuery = useGetProjectBeadsBoard({ projectId: project.id, enabled: project.viewer_is_member })
  const oauthAppsQuery = useGetProjectOauthApps({ projectId: project.id, enabled: canManageSource })
  const board = boardQuery.data
  const isReplacingCurrentSource =
    !!board && managementMode === 'replace' && replacementSourceVerifiedAt === board.verified_at

  const pairingMutation = useMutation({
    mutationFn: (oauthApplicationId: string) =>
      createPairing.request(`${scope}`, project.id, { oauth_application_id: oauthApplicationId }),
    onSuccess: setPairing,
    onError: apiErrorToast
  })

  const detachMutation = useMutation({
    mutationFn: () => deleteSource.request(`${scope}`, project.id),
    onSuccess: async () => {
      setManagementMode(undefined)
      setPairing(undefined)
      queryClient.removeQueries({ queryKey: getBoard.requestKey(`${scope}`, project.id) })
      queryClient.removeQueries({ queryKey: getSource.requestKey(`${scope}`, project.id) })

      if (router.pathname === '/[org]/projects/[projectId]/board') {
        await router.replace(`/${scope}/projects/${project.id}`)
      }
    },
    onError: apiErrorToast
  })

  if (!project.viewer_is_member) return null
  if (!board && !canManageSource) return null

  return (
    <section aria-labelledby='beads-source-heading' className='flex flex-col gap-3 border-b px-4 py-4'>
      <div className='flex items-center justify-between gap-3'>
        <UIText id='beads-source-heading' size='text-xs' tertiary weight='font-medium'>
          Beads
        </UIText>
        {board && <span className='text-tertiary text-xs'>Read-only</span>}
      </div>

      {board ? (
        <ConnectedSource board={board} />
      ) : pairing ? (
        <PairingState pairing={pairing} onRetry={() => setPairing(undefined)} />
      ) : (
        <ConnectSource
          applications={oauthAppsQuery.data ?? []}
          isLoading={oauthAppsQuery.isLoading}
          selectedApplicationId={selectedApplicationId}
          onApplicationChange={setSelectedApplicationId}
          onConnect={() => pairingMutation.mutate(selectedApplicationId)}
          isPending={pairingMutation.isPending}
        />
      )}

      {board &&
        canManageSource &&
        (isReplacingCurrentSource ? (
          pairing ? (
            <PairingState
              pairing={pairing}
              replacement
              onRetry={() => setPairing(undefined)}
              onCancel={() => {
                setPairing(undefined)
                setSelectedApplicationId('')
                setManagementMode(undefined)
              }}
            />
          ) : (
            <ConnectSource
              applications={oauthAppsQuery.data ?? []}
              isLoading={oauthAppsQuery.isLoading}
              selectedApplicationId={selectedApplicationId}
              onApplicationChange={setSelectedApplicationId}
              onConnect={() => pairingMutation.mutate(selectedApplicationId)}
              isPending={pairingMutation.isPending}
              replacement
              onCancel={() => {
                setSelectedApplicationId('')
                setManagementMode(undefined)
              }}
            />
          )
        ) : managementMode === 'detach' ? (
          <div className='flex flex-col gap-2 rounded-md border border-red-500/30 p-2'>
            <UIText size='text-xs'>Detach the source and remove its cached Board snapshots from Campsite?</UIText>
            <div className='flex gap-2'>
              <Button
                size='sm'
                variant='destructive'
                disabled={detachMutation.isPending}
                onClick={() => detachMutation.mutate()}
              >
                Confirm detach
              </Button>
              <Button size='sm' onClick={() => setManagementMode(undefined)}>
                Cancel
              </Button>
            </div>
          </div>
        ) : (
          <div className='flex gap-2'>
            <Button
              size='sm'
              onClick={() => {
                setReplacementSourceVerifiedAt(board.verified_at)
                setManagementMode('replace')
              }}
            >
              Replace source
            </Button>
            <Button size='sm' variant='destructive' onClick={() => setManagementMode('detach')}>
              Detach source
            </Button>
          </div>
        ))}
    </section>
  )
}

function ConnectedSource({ board }: { board: ProjectBeadsBoard }) {
  return (
    <div className='flex flex-col gap-2 text-sm'>
      <div>
        <UIText weight='font-medium'>{board.repository_display_name}</UIText>
        <UIText secondary size='text-xs'>
          Source {board.source_project_id}
        </UIText>
      </div>
      <dl className='grid grid-cols-[auto_1fr] gap-x-2 gap-y-1 text-xs'>
        <dt className='text-tertiary'>Status</dt>
        <dd>{board.current_snapshot ? 'Snapshot available' : 'Waiting for first snapshot'}</dd>
        <dt className='text-tertiary'>Verified</dt>
        <dd>{longTimestamp(board.verified_at)}</dd>
        {board.current_snapshot && (
          <>
            <dt className='text-tertiary'>Revision</dt>
            <dd className='break-all'>{board.current_snapshot.revision}</dd>
            <dt className='text-tertiary'>Collected</dt>
            <dd>{longTimestamp(board.current_snapshot.collected_at)}</dd>
          </>
        )}
      </dl>
      {board.agents.length > 0 && (
        <div className='flex flex-col gap-2 pt-1'>
          <UIText size='text-xs' tertiary weight='font-medium'>
            Attached agents
          </UIText>
          <ul className='flex flex-col gap-2'>
            {board.agents.map((agent) => (
              <li key={agent.id} className='flex items-center justify-between gap-2 text-xs'>
                <span className='min-w-0 truncate'>{agent.name}</span>
                <span className='text-tertiary text-right'>
                  {agent.roles.join(' · ')} · {agent.status}
                </span>
              </li>
            ))}
          </ul>
          <UIText size='text-xs' tertiary>
            Attached describes channel access, not live presence.
          </UIText>
        </div>
      )}
    </div>
  )
}

function ConnectSource({
  applications,
  isLoading,
  selectedApplicationId,
  onApplicationChange,
  onConnect,
  isPending,
  replacement = false,
  onCancel
}: {
  applications: Array<{ id: string; name: string }>
  isLoading: boolean
  selectedApplicationId: string
  onApplicationChange: (value: string) => void
  onConnect: () => void
  isPending: boolean
  replacement?: boolean
  onCancel?: () => void
}) {
  return (
    <div className='flex flex-col gap-3'>
      <div>
        <UIText weight='font-medium'>{replacement ? 'Replace Beads repository' : 'Connect Beads repository'}</UIText>
        <UIText secondary size='text-xs'>
          Channel members will see task ids, titles, state, priority, type, assignee, labels, dependencies, and
          timestamps. Repository paths, descriptions, comments, notes, memories, and credentials are not shared.
        </UIText>
      </div>
      <label className='flex flex-col gap-1 text-xs'>
        Publisher application
        <select
          className='bg-secondary rounded-md border px-2 py-1.5 text-sm'
          disabled={isLoading}
          value={selectedApplicationId}
          onChange={(event) => onApplicationChange(event.target.value)}
        >
          <option value=''>Select an attached application</option>
          {applications.map((application) => (
            <option key={application.id} value={application.id}>
              {application.name}
            </option>
          ))}
        </select>
      </label>
      <div className='flex gap-2'>
        <Button size='sm' disabled={!selectedApplicationId || isPending} onClick={onConnect}>
          {replacement ? 'Start replacement pairing' : 'Start pairing'}
        </Button>
        {onCancel && (
          <Button size='sm' onClick={onCancel}>
            Cancel replacement
          </Button>
        )}
      </div>
    </div>
  )
}

function PairingState({
  pairing,
  replacement = false,
  onRetry,
  onCancel
}: {
  pairing: ProjectBeadsPairing
  replacement?: boolean
  onRetry: () => void
  onCancel?: () => void
}) {
  const expired = Date.parse(pairing.expires_at) <= Date.now()

  return (
    <div className='flex flex-col gap-2'>
      <UIText weight='font-medium'>
        {replacement ? 'Replacement pairing' : 'Pairing'} {expired ? 'expired' : 'pending'}
      </UIText>
      <UIText secondary size='text-xs'>
        {expired
          ? `This challenge expired at ${longTimestamp(pairing.expires_at)}.`
          : `Complete this single-use challenge from the Beads repository before ${longTimestamp(pairing.expires_at)}.`}{' '}
        {replacement
          ? 'The current Board remains active until the replacement verifies.'
          : 'Board stays hidden until verification.'}
      </UIText>
      <code className='bg-secondary rounded-md border p-2 text-xs break-all select-all'>{pairing.challenge}</code>
      <div className='flex gap-2'>
        <Button size='sm' onClick={onRetry}>
          Start over
        </Button>
        {onCancel && (
          <Button size='sm' onClick={onCancel}>
            Cancel replacement
          </Button>
        )}
      </div>
    </div>
  )
}
