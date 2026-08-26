import { TiptapTransformer } from '@hocuspocus/transformer'
import * as Y from 'yjs'

import { database } from '../database'

const mocks = vi.hoisted(() => ({
  canonical: undefined as
    | {
        description_html: string
        description_state: string
        description_schema_version: number
      }
    | undefined,
  putRequests: [] as Array<{ description_state: string }>
}))

vi.mock('@sentry/node', () => ({ captureException: vi.fn(), setContext: vi.fn() }))
vi.mock('../api', () => ({
  api: {
    agentSyncGrants: {
      getAgentSyncGrantsNotesSyncState: () => ({ request: vi.fn() }),
      putAgentSyncGrantsNotesSyncState: () => ({ request: vi.fn() })
    },
    organizations: {
      getNotesSyncState: () => ({
        request: vi.fn().mockResolvedValue({
          description_html:
            '<h2>Plan</h2><table><tbody><tr><td><p>One</p></td><td><p>Two</p></td></tr></tbody></table><post-attachment id="attachment-1" file_type="image/png" width="100" height="100"></post-attachment><p>After</p>',
          description_schema_version: 9,
          description_state: null
        })
      }),
      putNotesSyncState: () => ({
        request: vi.fn(async (_organization: string, _id: string, payload: typeof mocks.canonical) => {
          mocks.putRequests.push(payload!)
          mocks.canonical ??= payload

          return { id: 'note-1', ...mocks.canonical }
        })
      })
    }
  }
}))

describe('collaboration lineage', () => {
  beforeEach(() => {
    mocks.canonical = undefined
    mocks.putRequests.length = 0
  })

  it('selects one canonical Yjs root for concurrent table-document cold loads', async () => {
    const fetch = database.configuration.fetch
    const context = {
      actorType: 'human' as const,
      organization: 'acme',
      schemaVersion: 9,
      token: 'secret',
      type: 'Note'
    }
    const document = { getConnections: () => [] }

    const [first, second] = await Promise.all([
      fetch({ context, documentName: 'note-1', document } as never),
      fetch({ context, documentName: 'note-1', document } as never)
    ])

    expect(mocks.putRequests).toHaveLength(2)
    expect(mocks.putRequests[0].description_state).not.toBe(mocks.putRequests[1].description_state)
    expect(first).toEqual(second)

    const merged = new Y.Doc()

    Y.applyUpdate(merged, first)
    Y.applyUpdate(merged, second)

    const json = TiptapTransformer.fromYdoc(merged, 'default')

    expect(json.content?.map((node) => node.type)).toEqual(['heading', 'table', 'postNoteAttachment', 'paragraph'])
  })
})
