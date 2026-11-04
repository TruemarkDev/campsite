import { createRedisExtension, redisConnectionsReady, redisSettings, verifyRedisExtension } from '../redis'

const mocks = vi.hoisted(() => ({ configuration: undefined as Record<string, any> | undefined }))

vi.mock('@hocuspocus/extension-redis', () => ({
  Redis: class {
    pub = { on: vi.fn(), ping: vi.fn().mockResolvedValue('PONG'), status: 'ready' }
    sub = { on: vi.fn(), ping: vi.fn().mockResolvedValue('PONG'), status: 'ready' }

    constructor(configuration: Record<string, any>) {
      mocks.configuration = configuration
    }
  }
}))

describe('Redis coordination', () => {
  beforeEach(() => {
    mocks.configuration = undefined
  })

  it('parses credentials, TLS, database, and namespace from the deployment URL', () => {
    expect(
      redisSettings({
        NODE_ENV: 'production',
        SYNC_REDIS_PREFIX: 'campsite-sync-staging',
        SYNC_REDIS_URL: 'rediss://sync-user:encoded%20password@redis.internal:6380/3'
      })
    ).toEqual({
      host: 'redis.internal',
      port: 6380,
      prefix: 'campsite-sync-staging',
      options: {
        connectTimeout: 5000,
        db: 3,
        maxRetriesPerRequest: 1,
        password: 'encoded password',
        tls: {},
        username: 'sync-user'
      }
    })
  })

  it('requires Redis coordination in production', () => {
    expect(() => redisSettings({ NODE_ENV: 'production' })).toThrow('SYNC_REDIS_URL is required in production')
    expect(() => redisSettings({ NODE_ENV: 'test', SYNC_REDIS_URL: 'http://localhost:6379/3' })).toThrow(
      'SYNC_REDIS_URL must use redis:// or rediss://'
    )
  })

  it('uses the local Redis database and consistent-load wait by default', async () => {
    const redis = createRedisExtension({ NODE_ENV: 'test' })

    expect(mocks.configuration).toMatchObject({
      awaitInitialSyncTimeout: 1000,
      host: '127.0.0.1',
      options: { db: 3 },
      port: 6379,
      prefix: 'campsite-sync'
    })
    expect(redisConnectionsReady(redis as never)).toBe(true)

    await verifyRedisExtension(redis as never)
    expect(redis.pub.ping).toHaveBeenCalledOnce()
    expect(redis.sub.ping).toHaveBeenCalledOnce()
  })
})
