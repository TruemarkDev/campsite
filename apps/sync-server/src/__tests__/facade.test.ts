import { Readable } from 'node:stream'
import { Hocuspocus } from '@hocuspocus/server'
import { TiptapTransformer } from '@hocuspocus/transformer'
import type { JSONContent } from '@tiptap/core'
import { generateHTML, generateJSON } from '@tiptap/html'

import { getNoteExtensions } from '@campsite/editor'

import { facadeInternals, handleAgentEditRequest } from '../facade'
import type { Context } from '../types'

const context: Context = {
  actorId: 'summary-agent',
  actorName: 'Summary agent',
  actorType: 'agent',
  grantId: 'grant-1',
  invokedBy: 'member-1',
  organization: 'acme',
  schemaVersion: 9,
  token: 'grant-token',
  type: 'Note'
}

const mocks = vi.hoisted(() => ({ recordAttribution: vi.fn(), verifyGrant: vi.fn() }))

vi.mock('../api', () => ({
  api: {
    agentSyncGrants: {
      postAgentSyncGrantsNotesAttributions: () => ({ request: mocks.recordAttribution }),
      postAgentSyncGrantsVerify: () => ({ request: mocks.verifyGrant })
    }
  }
}))

function httpRequest(body: object) {
  const request = Readable.from([JSON.stringify(body)]) as Readable & {
    headers: Record<string, string>
    method: string
    url: string
  }

  request.headers = { authorization: 'Bearer grant-token' }
  request.method = 'POST'
  request.url = '/agent-edits'

  return request
}

function httpResponse() {
  const result = { body: '', status: 0 }

  return {
    response: {
      end: vi.fn((body: string) => {
        result.body = body
      }),
      writeHead: vi.fn((status: number) => {
        result.status = status
      })
    },
    result
  }
}

const current: JSONContent = {
  type: 'doc',
  content: [
    { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Summary' }] },
    { type: 'paragraph', content: [{ type: 'text', text: 'Old' }] },
    { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Next' }] },
    { type: 'paragraph', content: [{ type: 'text', text: 'Keep' }] }
  ]
}
const inserted: JSONContent = {
  type: 'doc',
  content: [{ type: 'paragraph', content: [{ type: 'text', text: 'New' }] }]
}

describe('agent edit facade transformations', () => {
  beforeEach(() => vi.clearAllMocks())

  it('creates resolvable insert and delete marks for a suggested section replacement', () => {
    const result = facadeInternals.nextDocument(
      current,
      inserted,
      {
        note_id: 'note-1',
        mode: 'suggest',
        instruction: 'refresh summary',
        operation: { type: 'replace_section', heading: 'Summary', content: '<p>New</p>' }
      },
      context,
      'batch-1'
    )
    const json = JSON.stringify(result)

    expect(json).toContain('suggestionDelete')
    expect(json).toContain('suggestionInsert')
    expect(json).toContain('batch-1')
    expect(json).toContain('member-1')
    expect(result.content?.at(-1)).toEqual(current.content?.at(-1))
  })

  it('replaces only the requested section in direct mode', () => {
    const result = facadeInternals.nextDocument(
      current,
      inserted,
      {
        note_id: 'note-1',
        mode: 'direct',
        operation: { type: 'replace_section', heading: 'Summary', content: '<p>New</p>' }
      },
      context,
      'batch-1'
    )

    expect(result.content?.map((node) => node.content?.[0]?.text)).toEqual(['New', 'Next', 'Keep'])
  })

  it('replaces the shared ProseMirror fragment in one Yjs document', () => {
    const extensions = getNoteExtensions()
    const document = TiptapTransformer.toYdoc(current, 'default', extensions)

    facadeInternals.replaceYDocument(document, inserted)

    expect(TiptapTransformer.fromYdoc(document, 'default')).toEqual(inserted)
  })

  it('updates only matching mention attributes while preserving one complex document root', () => {
    const extensions = getNoteExtensions()
    const json = generateJSON(
      '<h2>Plan</h2><table><tbody><tr><td><p>One</p></td><td><p>Two</p></td></tr></tbody></table><post-attachment id="attachment-1" file_type="image/png" width="100" height="100"></post-attachment><p>Hello <span data-type="mention" data-id="member-1" data-label="Old Name" data-role="member" data-username="old_username">@Old Name</span> and <span data-type="mention" data-id="member-2" data-label="Keep Me" data-role="member" data-username="keep_me">@Keep Me</span></p>',
      extensions
    )
    const document = TiptapTransformer.toYdoc(json, 'default', extensions)

    const updated = facadeInternals.updateMentionAttributes(document, {
      type: 'update_mentions',
      membership_id: 'member-1',
      display_name: 'New Name',
      username: 'new_username'
    })
    const result = TiptapTransformer.fromYdoc(document, 'default') as JSONContent
    const mentions = result.content?.at(-1)?.content?.filter((node) => node.type === 'mention')

    expect(updated).toBe(1)
    expect(document.getXmlFragment('default')).toHaveLength(4)
    expect(result.content?.map((node) => node.type)).toEqual(['heading', 'table', 'postNoteAttachment', 'paragraph'])
    expect(mentions?.map((node) => node.attrs)).toEqual([
      { id: 'member-1', label: 'New Name', role: 'member', username: 'new_username' },
      { id: 'member-2', label: 'Keep Me', role: 'member', username: 'keep_me' }
    ])
    expect(generateHTML(result, extensions)).toContain(
      'data-label="New Name" data-role="member" data-username="new_username"'
    )
  })

  it('returns 422 for invalid content without opening a document', async () => {
    const { response, result } = httpResponse()
    const instance = { documents: new Map(), openDirectConnection: vi.fn() }

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'summary-agent',
      actor_name: 'Summary agent',
      grant_id: 'grant-1',
      invoked_by: 'member-1',
      organization: 'acme'
    })

    await handleAgentEditRequest(
      httpRequest({
        note_id: 'note-1',
        mode: 'suggest',
        operation: { type: 'append_section', content: '' }
      }) as never,
      response as never,
      instance as never
    )

    expect(result.status).toBe(422)
    expect(JSON.parse(result.body).code).toBe('invalid_content')
    expect(instance.openDirectConnection).not.toHaveBeenCalled()
  })

  it('refuses direct edits while a human editor is active', async () => {
    const { response, result } = httpResponse()
    const instance = {
      documents: new Map([['note-1', { getConnectionsCount: () => 1 }]]),
      openDirectConnection: vi.fn()
    }

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'summary-agent',
      actor_name: 'Summary agent',
      grant_id: 'grant-2',
      invoked_by: 'member-1',
      organization: 'acme'
    })

    await handleAgentEditRequest(
      httpRequest({
        note_id: 'note-1',
        mode: 'direct',
        operation: { type: 'set_content', content: '<p>Unsafe replacement</p>' }
      }) as never,
      response as never,
      instance as never
    )

    expect(result.status).toBe(409)
    expect(JSON.parse(result.body).code).toBe('active_editors')
    expect(instance.openDirectConnection).not.toHaveBeenCalled()
  })

  it.each([
    {
      scopes: ['write'],
      operation: {
        type: 'update_mentions',
        membership_id: 'member-1',
        display_name: 'New Name',
        username: 'new_username'
      }
    },
    { scopes: ['write', 'mention_labels'], operation: { type: 'set_content', content: '<p>Not allowed</p>' } }
  ])('keeps mention maintenance grants and operations mutually scoped', async ({ operation, scopes }) => {
    const { response, result } = httpResponse()
    const instance = { documents: new Map(), openDirectConnection: vi.fn() }

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'actor-1',
      actor_name: 'Actor',
      grant_id: `grant-${scopes.length}`,
      invoked_by: 'member-1',
      organization: 'acme',
      scopes
    })

    await handleAgentEditRequest(
      httpRequest({ note_id: 'note-1', mode: 'direct', operation }) as never,
      response as never,
      instance as never
    )

    expect(result.status).toBe(403)
    expect(JSON.parse(result.body).code).toBe('invalid_grant_scope')
    expect(instance.openDirectConnection).not.toHaveBeenCalled()
  })

  it('applies stream chunks as live transactions sharing one suggestion batch', async () => {
    const snapshots: JSONContent[] = []
    const instance = new Hocuspocus<Context>({
      debounce: 0,
      flushDelay: false,
      async onLoadDocument({ document }) {
        facadeInternals.replaceYDocument(document, { type: 'doc', content: [{ type: 'paragraph' }] })
      },
      async onChange({ document }) {
        snapshots.push(TiptapTransformer.fromYdoc(document, 'default'))
      }
    })

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'summary-agent',
      actor_name: 'Summary agent',
      grant_id: 'grant-stream',
      invoked_by: 'member-1',
      organization: 'acme'
    })
    mocks.recordAttribution.mockResolvedValueOnce({})

    const result = await facadeInternals.applyEdit(instance, 'grant-token', {
      note_id: 'note-stream',
      mode: 'suggest',
      instruction: 'Stream summary',
      operation: { type: 'stream', chunks: ['<p>One</p>', '<p>Two</p>'] }
    })

    expect(snapshots).toHaveLength(2)
    expect(JSON.stringify(snapshots.at(-1))).toContain('One')
    expect(JSON.stringify(snapshots.at(-1))).toContain('Two')
    expect(mocks.recordAttribution).toHaveBeenCalledWith(
      'note-stream',
      { batch_id: result.batch_id, instruction: 'Stream summary' },
      { headers: { Authorization: 'Bearer grant-token' } }
    )
  })

  it('applies scoped mention maintenance while editors are active without agent attribution', async () => {
    const extensions = getNoteExtensions()
    const initial = generateJSON(
      '<p>Hello <span data-type="mention" data-id="member-1" data-label="Old Name" data-role="member" data-username="old_username">@Old Name</span></p>',
      extensions
    )
    const instance = new Hocuspocus<Context>({
      debounce: 0,
      flushDelay: false,
      async onLoadDocument({ document }) {
        facadeInternals.replaceYDocument(document, initial)
      }
    })
    const active = await instance.openDirectConnection('note-mention', context)

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'system:mention-labels',
      actor_name: 'Campsite',
      grant_id: 'grant-mention',
      invoked_by: 'member-1',
      organization: 'acme',
      scopes: ['write', 'mention_labels']
    })

    const result = await facadeInternals.applyEdit(instance, 'grant-token', {
      note_id: 'note-mention',
      mode: 'direct',
      operation: {
        type: 'update_mentions',
        membership_id: 'member-1',
        display_name: 'New Name',
        username: 'new_username'
      }
    })
    const reconnected = await instance.openDirectConnection('note-mention', context)
    const json = TiptapTransformer.fromYdoc(reconnected.document!, 'default')

    expect(result.updated_mentions).toBe(1)
    expect(result.attribution_recorded).toBe(false)
    expect(reconnected.document!.getXmlFragment('default')).toHaveLength(1)
    expect(JSON.stringify(json)).toContain('New Name')
    expect(JSON.stringify(json)).toContain('new_username')
    expect(mocks.recordAttribution).not.toHaveBeenCalled()

    await reconnected.disconnect()
    await active.disconnect()
  })
})
