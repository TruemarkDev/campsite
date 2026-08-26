const mocks: Record<string, any> = vi.hoisted(() => ({
  captureException: vi.fn(),
  database: { name: 'database' },
  disconnectRedisExtension: vi.fn(),
  dotenvConfig: vi.fn(),
  getResource: vi.fn(),
  handleAgentEditRequest: vi.fn(),
  verifyGrant: vi.fn(),
  init: vi.fn(),
  listen: vi.fn(),
  logger: { name: 'logger' },
  redis: { name: 'redis', pub: { status: 'ready' }, sub: { status: 'ready' } },
  redisConnectionsReady: vi.fn(() => true),
  sendVersionToConnections: vi.fn(),
  serverConfiguration: undefined as Record<string, any> | undefined,
  setContext: vi.fn(),
  verifyRedisExtension: vi.fn()
}))

vi.mock('@hocuspocus/extension-logger', () => ({
  Logger: class {
    constructor() {
      return mocks.logger
    }
  }
}))
vi.mock('@hocuspocus/server', () => ({
  Server: class {
    listen = mocks.listen

    constructor(configuration: Record<string, any>) {
      mocks.serverConfiguration = configuration
    }
  }
}))
vi.mock('@sentry/node', () => ({
  captureException: mocks.captureException,
  init: mocks.init,
  setContext: mocks.setContext
}))
vi.mock('dotenv', () => ({ config: mocks.dotenvConfig }))
vi.mock('../database', () => ({
  database: mocks.database,
  getResource: mocks.getResource,
  sendVersionToConnections: mocks.sendVersionToConnections
}))
vi.mock('../api', () => ({
  api: {
    agentSyncGrants: {
      postAgentSyncGrantsVerify: () => ({ request: mocks.verifyGrant })
    }
  }
}))
vi.mock('../facade', () => ({ handleAgentEditRequest: mocks.handleAgentEditRequest }))
vi.mock('../redis', () => ({
  createRedisExtension: () => mocks.redis,
  disconnectRedisExtension: mocks.disconnectRedisExtension,
  redisConnectionsReady: mocks.redisConnectionsReady,
  verifyRedisExtension: mocks.verifyRedisExtension
}))

async function loadServer() {
  await import('../index')
  await vi.waitFor(() => expect(mocks.listen).toHaveBeenCalledOnce())

  return mocks.serverConfiguration!
}

function authenticationData(overrides: Record<string, any> = {}) {
  return {
    connectionConfig: { readOnly: false },
    documentName: 'note-1',
    instance: { documents: new Map() },
    requestParameters: new URLSearchParams({ organization: 'acme', schemaVersion: '3', type: 'Note' }),
    token: 'secret',
    ...overrides
  }
}

describe('sync server', () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
    mocks.serverConfiguration = undefined
    mocks.redisConnectionsReady.mockReturnValue(true)
    mocks.verifyRedisExtension.mockResolvedValue(undefined)
    process.env.NODE_ENV = 'test'
    delete process.env.PORT
    delete process.env.SENTRY_DSN
  })

  it('starts on the default port after Redis is ready', async () => {
    const configuration = await loadServer()

    expect(mocks.dotenvConfig).toHaveBeenCalledOnce()
    expect(configuration.port).toBe(9000)
    expect(configuration.extensions).toEqual([mocks.redis, mocks.database, mocks.logger])
    expect(mocks.verifyRedisExtension).toHaveBeenCalledWith(mocks.redis)
    expect(mocks.listen).toHaveBeenCalledOnce()
    expect(mocks.init).not.toHaveBeenCalled()
  })

  it('returns unavailable from the health endpoint when Redis disconnects', async () => {
    const { onRequest } = await loadServer()
    const response = { end: vi.fn(), writeHead: vi.fn() }

    mocks.redisConnectionsReady.mockReturnValue(false)

    await expect(onRequest({ request: { url: '/up' }, response, instance: {} })).rejects.toBeNull()
    expect(response.writeHead).toHaveBeenCalledWith(503, { 'Content-Type': 'application/json' })
    expect(response.end).toHaveBeenCalledWith(JSON.stringify({ status: 'unavailable', dependency: 'redis' }))
    expect(mocks.handleAgentEditRequest).not.toHaveBeenCalled()
  })

  it('uses configured production settings', async () => {
    process.env.NODE_ENV = 'production'
    process.env.PORT = '9100'
    process.env.SENTRY_DSN = 'https://sentry.test/1'

    const configuration = await loadServer()

    expect(configuration.port).toBe(9100)
    expect(mocks.init).toHaveBeenCalledWith({
      dsn: 'https://sentry.test/1',
      environment: 'production',
      tracesSampleRate: 0
    })
  })

  it('rejects authentication without a token', async () => {
    const { onAuthenticate } = await loadServer()

    await expect(onAuthenticate(authenticationData({ token: '' }))).rejects.toMatchObject({
      reason: 'no-token'
    })
    expect(mocks.getResource).not.toHaveBeenCalled()
  })

  it('rejects authentication without an organization', async () => {
    const { onAuthenticate } = await loadServer()
    const requestParameters = new URLSearchParams({ schemaVersion: '3', type: 'Note' })

    await expect(onAuthenticate(authenticationData({ requestParameters }))).rejects.toMatchObject({
      reason: 'invalid-type'
    })
    expect(mocks.getResource).not.toHaveBeenCalled()
  })

  it('authenticates and makes older clients read-only', async () => {
    const { onAuthenticate } = await loadServer()
    const document = { name: 'note-1' }
    const data = authenticationData({ instance: { documents: new Map([['note-1', document]]) } })

    mocks.getResource.mockResolvedValueOnce({ description_schema_version: 4 })

    await expect(onAuthenticate(data)).resolves.toEqual({
      actorType: 'human',
      organization: 'acme',
      schemaVersion: 3,
      token: 'secret',
      type: 'Note'
    })
    expect(mocks.getResource).toHaveBeenCalledWith({
      actorType: 'human',
      id: 'note-1',
      organization: 'acme',
      token: 'secret',
      type: 'Note'
    })
    expect(mocks.sendVersionToConnections).toHaveBeenCalledWith(document, 4)
    expect(data.connectionConfig.readOnly).toBe(true)
  })

  it('keeps current clients writable when no document is loaded', async () => {
    const { onAuthenticate } = await loadServer()
    const data = authenticationData()

    mocks.getResource.mockResolvedValueOnce({ description_schema_version: 3 })

    await onAuthenticate(data)

    expect(mocks.sendVersionToConnections).not.toHaveBeenCalled()
    expect(data.connectionConfig.readOnly).toBe(false)
  })

  it('authenticates an agent from the note-scoped grant instead of trusting request identity', async () => {
    const { onAuthenticate } = await loadServer()
    const requestParameters = new URLSearchParams({ actorType: 'agent', schemaVersion: '9', type: 'Note' })

    mocks.verifyGrant.mockResolvedValueOnce({
      actor_id: 'summary-agent',
      actor_name: 'Summary agent',
      grant_id: 'grant-1',
      invoked_by: 'member-1',
      note_id: 'note-1',
      organization: 'verified-org'
    })
    mocks.getResource.mockResolvedValueOnce({ description_schema_version: 9 })

    await expect(onAuthenticate(authenticationData({ requestParameters, token: 'grant-token' }))).resolves.toEqual({
      actorId: 'summary-agent',
      actorName: 'Summary agent',
      actorType: 'agent',
      grantId: 'grant-1',
      invokedBy: 'member-1',
      organization: 'verified-org',
      schemaVersion: 9,
      token: 'grant-token',
      type: 'Note'
    })
    expect(mocks.getResource).toHaveBeenCalledWith({
      actorType: 'agent',
      id: 'note-1',
      organization: 'verified-org',
      token: 'grant-token',
      type: 'Note'
    })
  })

  it('rechecks agent grants on token sync and rejects revoked grants', async () => {
    const { onTokenSync } = await loadServer()
    const data = {
      context: { actorType: 'agent' },
      documentName: 'note-1',
      token: 'grant-token'
    }

    mocks.verifyGrant.mockRejectedValueOnce(new Error('revoked'))

    await expect(onTokenSync(data)).rejects.toMatchObject({ reason: 'invalid-grant' })
  })

  it('treats a missing schema version as version zero', async () => {
    const { onAuthenticate } = await loadServer()
    const requestParameters = new URLSearchParams({ organization: 'acme', type: 'Note' })
    const data = authenticationData({ requestParameters })

    mocks.getResource.mockResolvedValueOnce({ description_schema_version: 1 })

    await expect(onAuthenticate(data)).resolves.toMatchObject({ schemaVersion: 0 })
    expect(data.connectionConfig.readOnly).toBe(true)
  })

  it('reports and rejects missing resources', async () => {
    const { onAuthenticate } = await loadServer()
    const data = authenticationData()

    mocks.getResource.mockResolvedValueOnce(undefined)

    await expect(onAuthenticate(data)).rejects.toMatchObject({ reason: 'invalid-type' })
    expect(mocks.setContext).toHaveBeenCalledWith('document', {
      id: 'note-1',
      organization: 'acme',
      type: 'Note'
    })
    expect(mocks.setContext).toHaveBeenCalledWith('context', { actorType: 'human', schemaVersion: 3 })
    expect(mocks.captureException).toHaveBeenCalledWith(expect.objectContaining({ reason: 'invalid-type' }))
  })

  it('reports and rethrows resource request failures', async () => {
    const { onAuthenticate } = await loadServer()
    const error = new Error('API unavailable')

    mocks.getResource.mockRejectedValueOnce(error)

    await expect(onAuthenticate(authenticationData())).rejects.toBe(error)
    expect(mocks.captureException).toHaveBeenCalledWith(error)
  })
})
