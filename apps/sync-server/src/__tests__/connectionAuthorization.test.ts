import type { Connection } from '@hocuspocus/server'

import { ConnectionAuthorization } from '../connectionAuthorization'
import type { Context } from '../types'

const { verifyAccess } = vi.hoisted(() => ({ verifyAccess: vi.fn() }))
vi.mock('../api', () => ({ verifyConnectionAccess: verifyAccess }))

describe('connection authorization leases', () => {
  let authorization: ConnectionAuthorization
  let connection: Connection<Context>

  beforeEach(() => {
    vi.useFakeTimers()
    verifyAccess.mockReset().mockResolvedValue(undefined)
    authorization = new ConnectionAuthorization()
    connection = {
      context: { actorType: 'human', organization: 'acme', type: 'Note', schemaVersion: 1, token: 'original-token' },
      close: vi.fn()
    } as unknown as Connection<Context>
  })
  afterEach(() => {
    authorization.destroy()
    vi.useRealTimers()
  })

  it('accepts initial authenticated queued sync messages before connected without per-keystroke HTTP calls', async () => {
    await authorization.ensure(connection, 'note-1')
    authorization.watch(connection, 'note-1')
    for (let index = 0; index < 20; index++) await authorization.ensure(connection, 'note-1')
    expect(verifyAccess).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(60_000)
    expect(verifyAccess).toHaveBeenCalledOnce()
  })

  it('closes an idle revoked connection and cannot recreate its lease', async () => {
    authorization.watch(connection, 'note-1')
    verifyAccess.mockRejectedValueOnce(new Error('revoked'))
    await vi.advanceTimersByTimeAsync(60_000)
    expect(connection.close).toHaveBeenCalledWith({ code: 4403, reason: 'invalid-permission' })
    await expect(authorization.ensure(connection, 'note-1')).rejects.toMatchObject({ reason: 'invalid-permission' })
    await vi.advanceTimersByTimeAsync(120_000)
    expect(verifyAccess).toHaveBeenCalledOnce()
  })

  it('blocks expired-lease writes until a single in-flight authorization request succeeds', async () => {
    let resolve!: () => void
    verifyAccess.mockReturnValueOnce(
      new Promise<void>((done) => {
        resolve = done
      })
    )
    authorization.watch(connection, 'note-1')
    await vi.advanceTimersByTimeAsync(60_000)
    let accepted = false
    const pending = authorization.ensure(connection, 'note-1').then(() => {
      accepted = true
    })
    await Promise.resolve()
    expect(accepted).toBe(false)
    expect(verifyAccess).toHaveBeenCalledOnce()
    resolve()
    await pending
    expect(accepted).toBe(true)
  })

  it('fails closed when the API is unavailable', async () => {
    authorization.watch(connection, 'note-1')
    verifyAccess.mockRejectedValueOnce(new Error('API unavailable'))
    await vi.advanceTimersByTimeAsync(60_000)
    expect(connection.close).toHaveBeenCalledOnce()
    await expect(authorization.ensure(connection, 'note-1')).rejects.toMatchObject({ reason: 'invalid-permission' })
  })

  it('uses refreshed credentials and cleans timers on disconnect and shutdown', async () => {
    authorization.watch(connection, 'note-1')
    connection.context.token = 'renewed-token'
    await vi.advanceTimersByTimeAsync(60_000)
    expect(verifyAccess).toHaveBeenCalledWith(expect.objectContaining({ token: 'renewed-token' }), 'note-1')
    authorization.stop(connection)
    authorization.destroy()
    await vi.advanceTimersByTimeAsync(120_000)
    expect(verifyAccess).toHaveBeenCalledOnce()
    await expect(authorization.ensure(connection, 'note-1')).rejects.toMatchObject({ reason: 'invalid-permission' })
  })
})
