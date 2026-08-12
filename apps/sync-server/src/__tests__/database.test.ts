import * as Y from 'yjs'

import { database, getResource, sendVersionToConnections } from '../database'

const mocks = vi.hoisted(() => ({
  captureException: vi.fn(),
  fromYdoc: vi.fn(),
  generateHTML: vi.fn(),
  generateJSON: vi.fn(),
  getNoteExtensions: vi.fn(() => []),
  getRequest: vi.fn(),
  putRequest: vi.fn(),
  setContext: vi.fn(),
  toYdoc: vi.fn()
}))

vi.mock('@campsite/editor', () => ({ getNoteExtensions: mocks.getNoteExtensions }))
vi.mock('@hocuspocus/transformer', () => ({
  TiptapTransformer: {
    fromYdoc: mocks.fromYdoc,
    toYdoc: mocks.toYdoc
  }
}))
vi.mock('@sentry/node', () => ({
  captureException: mocks.captureException,
  setContext: mocks.setContext
}))
vi.mock('@tiptap/html', () => ({
  generateHTML: mocks.generateHTML,
  generateJSON: mocks.generateJSON
}))
vi.mock('../api', () => ({
  api: {
    organizations: {
      getNotesSyncState: () => ({ request: mocks.getRequest }),
      putNotesSyncState: () => ({ request: mocks.putRequest })
    }
  }
}))

const context = {
  organization: 'acme',
  schemaVersion: 3,
  token: 'secret',
  type: 'Note'
}

function connection(schemaVersion?: number) {
  return {
    context: { schemaVersion },
    readOnly: false,
    sendStateless: vi.fn()
  }
}

function documentWithConnections(...connections: ReturnType<typeof connection>[]) {
  return { getConnections: () => connections }
}

describe('getResource', () => {
  it('loads notes with the expected authorization', async () => {
    const state = { description_schema_version: 3 }

    mocks.getRequest.mockResolvedValueOnce(state)

    await expect(getResource({ token: 'secret', id: 'note-1', type: 'Note', organization: 'acme' })).resolves.toBe(
      state
    )
    expect(mocks.getRequest).toHaveBeenCalledWith('acme', 'note-1', {
      headers: { Authorization: 'Bearer secret' }
    })
  })

  it('does not request unsupported resource types', async () => {
    await expect(
      getResource({ token: 'secret', id: 'post-1', type: 'Post', organization: 'acme' })
    ).resolves.toBeUndefined()
    expect(mocks.getRequest).not.toHaveBeenCalled()
  })
})

describe('sendVersionToConnections', () => {
  it('updates read-only state and broadcasts the current schema version', () => {
    const older = connection(2)
    const current = connection(3)
    const missing = connection()

    sendVersionToConnections(documentWithConnections(older, current, missing) as never, 3)

    expect(older.readOnly).toBe(true)
    expect(current.readOnly).toBe(false)
    expect(missing.readOnly).toBe(true)
    for (const item of [older, current, missing]) {
      expect(item.sendStateless).toHaveBeenCalledWith(JSON.stringify({ type: 'schema', version: 3 }))
    }
  })
})

describe('database fetch', () => {
  const fetch = database.configuration.fetch

  it('returns an empty update when organization context is absent', async () => {
    const result = await fetch({ context: { ...context, organization: '' }, documentName: 'note-1' } as never)

    expect(result).toEqual(new Uint8Array())
    expect(mocks.getRequest).not.toHaveBeenCalled()
  })

  it('returns an empty update when the resource is unavailable', async () => {
    mocks.getRequest.mockResolvedValueOnce(undefined)

    const result = await fetch({ context, documentName: 'note-1', document: documentWithConnections() } as never)

    expect(result).toEqual(new Uint8Array())
  })

  it('returns persisted Yjs state and updates connected clients', async () => {
    const persisted = Uint8Array.from([1, 2, 3])
    const peer = connection(1)

    mocks.getRequest.mockResolvedValueOnce({
      description_schema_version: 3,
      description_state: Buffer.from(persisted).toString('base64')
    })

    const result = await fetch({
      context,
      documentName: 'note-1',
      document: documentWithConnections(peer)
    } as never)

    expect(result).toEqual(persisted)
    expect(peer.readOnly).toBe(true)
  })

  it('converts legacy HTML into a Yjs update', async () => {
    const ydoc = new Y.Doc()

    ydoc.getText('default').insert(0, 'Hello')
    mocks.getRequest.mockResolvedValueOnce({
      description_html: '<p>Hello</p>',
      description_schema_version: 3,
      description_state: null
    })
    mocks.generateJSON.mockReturnValueOnce({ type: 'doc' })
    mocks.toYdoc.mockReturnValueOnce(ydoc)

    const result = await fetch({
      context,
      documentName: 'note-1',
      document: documentWithConnections()
    } as never)

    expect(mocks.generateJSON).toHaveBeenCalledWith('<p>Hello</p>', [])
    expect(mocks.toYdoc).toHaveBeenCalledWith({ type: 'doc' }, 'default', [])
    expect(result).toEqual(Y.encodeStateAsUpdate(ydoc))
  })

  it('reports and rethrows API failures', async () => {
    const error = new Error('fetch failed')

    mocks.getRequest.mockRejectedValueOnce(error)

    await expect(fetch({ context, documentName: 'note-1', document: documentWithConnections() } as never)).rejects.toBe(
      error
    )
    expect(mocks.setContext).toHaveBeenCalledWith('document', {
      id: 'note-1',
      organization: 'acme',
      type: 'Note'
    })
    expect(mocks.setContext).toHaveBeenCalledWith('context', { schemaVersion: 3, token: 'secret' })
    expect(mocks.captureException).toHaveBeenCalledWith(error)
  })
})

describe('database store', () => {
  const store = database.configuration.store

  it('does nothing when organization context is absent', async () => {
    await store({ lastContext: { ...context, organization: '' }, documentName: 'note-1' } as never)

    expect(mocks.putRequest).not.toHaveBeenCalled()
  })

  it('stores Yjs state, generated HTML, schema version, and authorization', async () => {
    const ydoc = new Y.Doc()

    ydoc.getText('default').insert(0, 'Hello')
    mocks.fromYdoc.mockReturnValueOnce({ type: 'doc' })
    mocks.generateHTML.mockReturnValueOnce('<p>Hello</p>')
    mocks.putRequest.mockResolvedValueOnce(undefined)

    await store({ lastContext: context, documentName: 'note-1', document: ydoc } as never)

    expect(mocks.fromYdoc).toHaveBeenCalledWith(ydoc, 'default')
    expect(mocks.generateHTML).toHaveBeenCalledWith({ type: 'doc' }, [])
    expect(mocks.putRequest).toHaveBeenCalledWith(
      'acme',
      'note-1',
      {
        description_html: '<p>Hello</p>',
        description_state: Buffer.from(Y.encodeStateAsUpdate(ydoc)).toString('base64'),
        description_schema_version: 3
      },
      { headers: { Authorization: 'Bearer secret' } }
    )
  })

  it('reports and rethrows persistence failures', async () => {
    const error = new Error('store failed')
    const ydoc = new Y.Doc()

    mocks.fromYdoc.mockReturnValueOnce({ type: 'doc' })
    mocks.generateHTML.mockReturnValueOnce('<p></p>')
    mocks.putRequest.mockRejectedValueOnce(error)

    await expect(store({ lastContext: context, documentName: 'note-1', document: ydoc } as never)).rejects.toBe(error)
    expect(mocks.setContext).toHaveBeenCalledWith('document', {
      id: 'note-1',
      organization: 'acme',
      type: 'Note'
    })
    expect(mocks.setContext).toHaveBeenCalledWith('context', { schemaVersion: 3, token: 'secret' })
    expect(mocks.captureException).toHaveBeenCalledWith(error)
  })
})

beforeEach(() => {
  vi.clearAllMocks()
})
