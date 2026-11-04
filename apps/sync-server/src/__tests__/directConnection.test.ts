import { Hocuspocus } from '@hocuspocus/server'

interface TestContext {
  actorType: 'agent'
  organization: string
  schemaVersion: number
  token: string
  type: string
}

const context: TestContext = {
  actorType: 'agent',
  organization: 'acme',
  schemaVersion: 9,
  token: 'agent-token',
  type: 'Note'
}

function createInstance() {
  const stores: { clientsCount: number; name: string; text: string }[] = []
  const instance = new Hocuspocus<TestContext>({
    debounce: 0,
    flushDelay: false,
    async onLoadDocument({ document, documentName }) {
      document.getText('default').insert(0, `${documentName}:`)
    },
    async onStoreDocument({ clientsCount, document, documentName }) {
      stores.push({ clientsCount, name: documentName, text: document.getText('default').toString() })
    }
  })

  return { instance, stores }
}

describe('openDirectConnection', () => {
  it('loads, transacts, and durably stores a closed document on disconnect', async () => {
    const { instance, stores } = createInstance()
    const connection = await instance.openDirectConnection('closed-note', context)

    await connection.transact((document) =>
      document.getText('default').insert(document.getText('default').length, 'edit')
    )
    await connection.disconnect()

    expect(stores.at(-1)).toEqual({ clientsCount: 0, name: 'closed-note', text: 'closed-note:edit' })
    expect(instance.documents.has('closed-note')).toBe(false)
  })

  it('shares live state, broadcasts updates and awareness, then clears agent presence', async () => {
    const { instance, stores } = createInstance()
    const viewer = { messageAddress: 'live-note', send: vi.fn() }
    const connection = await instance.openDirectConnection('live-note', context)
    const document = connection.document!

    document.addConnection(viewer as never)

    await connection.transact((sharedDocument) => {
      sharedDocument.getText('default').insert(sharedDocument.getText('default').length, 'stream')
    })

    expect(document.getText('default').toString()).toBe('live-note:stream')
    expect(viewer.send).toHaveBeenCalled()

    viewer.send.mockClear()
    document.awareness.setLocalState({ user: { isAgent: true, name: 'Campsite AI' } })
    expect(document.awareness.getLocalState()).toEqual({ user: { isAgent: true, name: 'Campsite AI' } })
    expect(viewer.send).toHaveBeenCalled()

    document.awareness.setLocalState(null)
    expect(document.awareness.getLocalState()).toBeNull()

    await connection.disconnect()
    expect(stores.at(-1)).toEqual({ clientsCount: 1, name: 'live-note', text: 'live-note:stream' })

    document.removeConnection(viewer as never)
    await instance.unloadDocument(document)
  })
})
