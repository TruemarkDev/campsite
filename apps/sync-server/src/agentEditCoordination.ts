import { createHash } from 'node:crypto'
import type { Redis } from '@hocuspocus/extension-redis'

const HUMAN_LEASE_MS = 15_000
const HUMAN_REFRESH_MS = 5_000
const NOTE_LOCK_MS = 10_000
// Enforced globally across sync replicas for each verified agent grant.
const RATE_LIMIT = 30
const RATE_WINDOW_MS = 60_000

const TAKE_RATE_LIMIT = `
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
end
return count
`

const ACTIVE_HUMANS = `
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1])
return redis.call('ZCARD', KEYS[1])
`

const REMOVE_HUMAN = `
redis.call('ZREM', KEYS[1], ARGV[1])
if redis.call('ZCARD', KEYS[1]) == 0 then
  redis.call('DEL', KEYS[1])
end
return 1
`

export type AgentEditCoordination = {
  destroy(): Promise<void>
  hasActiveHuman(documentName: string): Promise<boolean>
  humanConnected(documentName: string, socketId: string): Promise<void>
  humanDisconnected(documentName: string, socketId: string): Promise<void>
  takeRateLimit(grantId: string): Promise<boolean>
  withNoteLock<T>(documentName: string, callback: () => Promise<T>): Promise<T>
}

function localQueue() {
  const queues = new Map<string, Promise<void>>()

  return async function withNoteLock<T>(documentName: string, callback: () => Promise<T>) {
    const prior = queues.get(documentName) ?? Promise.resolve()
    let release = () => {}
    const next = new Promise<void>((resolve) => {
      release = resolve
    })
    const queued = prior.then(() => next)

    queues.set(documentName, queued)
    await prior
    try {
      return await callback()
    } finally {
      release()
      if (queues.get(documentName) === queued) queues.delete(documentName)
    }
  }
}

export function createInMemoryAgentEditCoordination(): AgentEditCoordination {
  const humans = new Map<string, Set<string>>()
  const requestCounts = new Map<string, { count: number; resetAt: number }>()
  const withNoteLock = localQueue()

  return {
    async destroy() {
      humans.clear()
      requestCounts.clear()
    },
    async hasActiveHuman(documentName) {
      return (humans.get(documentName)?.size ?? 0) > 0
    },
    async humanConnected(documentName, socketId) {
      await withNoteLock(documentName, async () => {
        const connections = humans.get(documentName) ?? new Set<string>()
        connections.add(socketId)
        humans.set(documentName, connections)
      })
    },
    async humanDisconnected(documentName, socketId) {
      await withNoteLock(documentName, async () => {
        const connections = humans.get(documentName)
        if (!connections) return

        connections.delete(socketId)
        if (connections.size === 0) humans.delete(documentName)
      })
    },
    async takeRateLimit(grantId) {
      const now = Date.now()
      const current = requestCounts.get(grantId)

      if (!current || current.resetAt <= now) {
        requestCounts.set(grantId, { count: 1, resetAt: now + RATE_WINDOW_MS })
        return true
      }

      current.count += 1
      return current.count <= RATE_LIMIT
    },
    withNoteLock
  }
}

function boundedKeyPart(value: string) {
  return createHash('sha256').update(value).digest('hex')
}

type RedisAgentEditCoordinationOptions = {
  humanLeaseMs?: number
  humanRefreshMs?: number
  noteLockMs?: number
}

export function createRedisAgentEditCoordination(
  redis: Redis,
  options: RedisAgentEditCoordinationOptions = {}
): AgentEditCoordination {
  const namespace = `${redis.configuration.prefix}:agent-edits`
  const instanceId = redis.configuration.identifier
  const humanLeaseMs = options.humanLeaseMs ?? HUMAN_LEASE_MS
  const humanRefreshMs = options.humanRefreshMs ?? HUMAN_REFRESH_MS
  const noteLockMs = options.noteLockMs ?? NOTE_LOCK_MS
  const humanSockets = new Map<string, Set<string>>()
  let destroyed = false

  const humanKey = (documentName: string) => `${namespace}:humans:${boundedKeyPart(documentName)}`
  const lockKey = (documentName: string) => `${namespace}:lock:${boundedKeyPart(documentName)}`
  const rateKey = (grantId: string) => `${namespace}:rate:${boundedKeyPart(grantId)}`

  const refreshHuman = async (documentName: string) => {
    const key = humanKey(documentName)
    const expiresAt = Date.now() + humanLeaseMs
    const transaction = redis.pub.multi()

    transaction.zadd(key, expiresAt, instanceId)
    transaction.pexpire(key, humanLeaseMs * 2)
    await transaction.exec()
  }

  const refreshTimer = setInterval(() => {
    if (destroyed) return

    void Promise.all([...humanSockets.keys()].map(refreshHuman)).catch((error) => {
      console.error(`Agent edit human-presence refresh failed: ${(error as Error).message}`)
    })
  }, humanRefreshMs)
  refreshTimer.unref()

  const withNoteLock = async <T>(documentName: string, callback: () => Promise<T>) =>
    redis.redlock.using(
      [lockKey(documentName)],
      noteLockMs,
      { retryCount: 100, retryDelay: 50, retryJitter: 25 },
      async (signal) => {
        if (signal.aborted) throw signal.error
        const result = await callback()
        if (signal.aborted) throw signal.error
        return result
      }
    )

  return {
    async destroy() {
      if (destroyed) return
      destroyed = true
      clearInterval(refreshTimer)

      const documents = [...humanSockets.keys()]
      humanSockets.clear()
      await Promise.allSettled(
        documents.map((documentName) => redis.pub.eval(REMOVE_HUMAN, 1, humanKey(documentName), instanceId))
      )
    },
    async hasActiveHuman(documentName) {
      const count = await redis.pub.eval(ACTIVE_HUMANS, 1, humanKey(documentName), Date.now())
      return Number(count) > 0
    },
    async humanConnected(documentName, socketId) {
      await withNoteLock(documentName, async () => {
        const sockets = humanSockets.get(documentName) ?? new Set<string>()
        const wasEmpty = sockets.size === 0
        sockets.add(socketId)
        humanSockets.set(documentName, sockets)

        if (!wasEmpty) return

        try {
          await refreshHuman(documentName)
        } catch (error) {
          sockets.delete(socketId)
          if (sockets.size === 0) humanSockets.delete(documentName)
          throw error
        }
      })
    },
    async humanDisconnected(documentName, socketId) {
      await withNoteLock(documentName, async () => {
        const sockets = humanSockets.get(documentName)
        if (!sockets) return

        sockets.delete(socketId)
        if (sockets.size > 0) return

        humanSockets.delete(documentName)
        await redis.pub.eval(REMOVE_HUMAN, 1, humanKey(documentName), instanceId)
      })
    },
    async takeRateLimit(grantId) {
      const count = await redis.pub.eval(TAKE_RATE_LIMIT, 1, rateKey(grantId), RATE_WINDOW_MS)
      return Number(count) <= RATE_LIMIT
    },
    withNoteLock
  }
}
