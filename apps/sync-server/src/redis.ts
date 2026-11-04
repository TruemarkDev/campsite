import { Redis } from '@hocuspocus/extension-redis'

const DEFAULT_REDIS_URL = 'redis://127.0.0.1:6379/3'
const DEFAULT_REDIS_PREFIX = 'campsite-sync'
const REDIS_CONNECT_TIMEOUT_MS = 5_000

type RedisEnvironment = Partial<Pick<NodeJS.ProcessEnv, 'NODE_ENV' | 'SYNC_REDIS_PREFIX' | 'SYNC_REDIS_URL'>>

export function redisSettings(environment: RedisEnvironment = process.env) {
  const rawUrl = environment.SYNC_REDIS_URL

  if (environment.NODE_ENV === 'production' && !rawUrl) {
    throw new Error('SYNC_REDIS_URL is required in production')
  }

  const url = new URL(rawUrl || DEFAULT_REDIS_URL)
  if (!['redis:', 'rediss:'].includes(url.protocol)) {
    throw new Error('SYNC_REDIS_URL must use redis:// or rediss://')
  }

  const database = url.pathname === '' || url.pathname === '/' ? 0 : Number(url.pathname.slice(1))
  if (!Number.isInteger(database) || database < 0)
    throw new Error('SYNC_REDIS_URL must contain a valid database number')

  return {
    host: url.hostname,
    port: url.port ? Number(url.port) : 6379,
    prefix: environment.SYNC_REDIS_PREFIX || DEFAULT_REDIS_PREFIX,
    options: {
      db: database,
      connectTimeout: REDIS_CONNECT_TIMEOUT_MS,
      maxRetriesPerRequest: 1,
      ...(url.username && { username: decodeURIComponent(url.username) }),
      ...(url.password && { password: decodeURIComponent(url.password) }),
      ...(url.protocol === 'rediss:' && { tls: {} })
    }
  }
}

export function createRedisExtension(environment: RedisEnvironment = process.env) {
  const redis = new Redis({
    ...redisSettings(environment),
    awaitInitialSyncTimeout: 1_000
  })

  const reportFirstError = (client: 'publisher' | 'subscriber') => {
    let reported = false

    return (error: Error) => {
      if (reported) return

      reported = true
      console.error(`Redis coordination ${client} error: ${error.message}`)
    }
  }

  redis.pub.on('error', reportFirstError('publisher'))
  redis.sub.on('error', reportFirstError('subscriber'))

  return redis
}

export function redisConnectionsReady(redis: Redis) {
  return redis.pub.status === 'ready' && redis.sub.status === 'ready'
}

export function disconnectRedisExtension(redis: Redis) {
  redis.pub.disconnect(false)
  redis.sub.disconnect(false)
}

export async function verifyRedisExtension(redis: Redis) {
  let timeoutId: NodeJS.Timeout | undefined
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => reject(new Error('Redis coordination readiness timed out')), REDIS_CONNECT_TIMEOUT_MS)
  })

  try {
    await Promise.race([Promise.all([redis.pub.ping(), redis.sub.ping()]), timeout])
  } finally {
    if (timeoutId) clearTimeout(timeoutId)
  }
}
