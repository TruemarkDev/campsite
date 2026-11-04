import type { Connection } from '@hocuspocus/server'

import { verifyConnectionAccess } from './api'
import { AuthenticationError, type Context } from './types'

// A bounded access lease avoids an authorization HTTP request per keystroke.
// Idle connections are checked too, so ignoring token refresh cannot retain access.
const AUTHORIZATION_LEASE_MS = 60_000
type Lease = {
  noteId: string
  expiresAt: number
  timer: ReturnType<typeof setInterval>
  pending?: Promise<void>
}

export class ConnectionAuthorization {
  private leases = new Map<Connection<Context>, Lease>()
  private closed = new WeakSet<Connection<Context>>()

  watch(connection: Connection<Context>, noteId: string) {
    if (this.closed.has(connection)) throw new AuthenticationError('invalid-permission')
    if (this.leases.has(connection)) return
    const timer = setInterval(() => {
      void this.verify(connection).catch(() => undefined)
    }, AUTHORIZATION_LEASE_MS)
    timer.unref()
    this.leases.set(connection, { noteId, expiresAt: Date.now() + AUTHORIZATION_LEASE_MS, timer })
  }

  async ensure(connection: Connection<Context>, noteId: string) {
    // Hocuspocus drains authenticated queued sync messages before `connected`.
    // Both entry points must share the same initial lease.
    if (this.closed.has(connection)) throw new AuthenticationError('invalid-permission')
    if (!this.leases.has(connection)) this.watch(connection, noteId)
    const lease = this.leases.get(connection)
    if (!lease) throw new AuthenticationError('invalid-permission')
    if (Date.now() >= lease.expiresAt) await this.verify(connection)
  }

  private verify(connection: Connection<Context>): Promise<void> {
    const lease = this.leases.get(connection)
    if (!lease) return Promise.reject(new AuthenticationError('invalid-permission'))
    if (lease.pending) return lease.pending
    lease.pending = verifyConnectionAccess(connection.context, lease.noteId)
      .then(() => {
        if (this.leases.get(connection) !== lease) throw new AuthenticationError('invalid-permission')
        lease.expiresAt = Date.now() + AUTHORIZATION_LEASE_MS
      })
      .catch(() => {
        this.stop(connection)
        connection.close({ code: 4403, reason: 'invalid-permission' })
        throw new AuthenticationError('invalid-permission')
      })
      .finally(() => {
        lease.pending = undefined
      })
    return lease.pending
  }

  stop(connection: Connection<Context>) {
    this.closed.add(connection)
    const lease = this.leases.get(connection)
    if (lease) clearInterval(lease.timer)
    this.leases.delete(connection)
  }

  stopSocket(socketId: string, noteId: string) {
    for (const [connection, lease] of this.leases) {
      if (connection.socketId === socketId && lease.noteId === noteId) this.stop(connection)
    }
  }

  destroy() {
    for (const connection of this.leases.keys()) this.stop(connection)
  }
}
