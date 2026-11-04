import { createInMemoryAgentEditCoordination } from '../agentEditCoordination'

describe('agent edit coordination', () => {
  it('tracks human sockets per document', async () => {
    const coordination = createInMemoryAgentEditCoordination()

    await coordination.humanConnected('note-1', 'socket-1')
    await coordination.humanConnected('note-1', 'socket-2')
    expect(await coordination.hasActiveHuman('note-1')).toBe(true)

    await coordination.humanDisconnected('note-1', 'socket-1')
    expect(await coordination.hasActiveHuman('note-1')).toBe(true)

    await coordination.humanDisconnected('note-1', 'socket-2')
    expect(await coordination.hasActiveHuman('note-1')).toBe(false)
  })

  it('enforces one 30-per-minute budget for each grant', async () => {
    const coordination = createInMemoryAgentEditCoordination()

    for (let request = 0; request < 30; request += 1) {
      await expect(coordination.takeRateLimit('grant-1')).resolves.toBe(true)
    }
    await expect(coordination.takeRateLimit('grant-1')).resolves.toBe(false)
    await expect(coordination.takeRateLimit('grant-2')).resolves.toBe(true)
  })

  it('serializes the same note without blocking a different note', async () => {
    const coordination = createInMemoryAgentEditCoordination()
    let releaseFirst = () => {}
    let secondEntered = false
    const firstEntered = new Promise<void>((resolve) => {
      void coordination.withNoteLock('note-1', async () => {
        resolve()
        await new Promise<void>((release) => {
          releaseFirst = release
        })
      })
    })

    await firstEntered
    const second = coordination.withNoteLock('note-1', async () => {
      secondEntered = true
    })
    await coordination.withNoteLock('note-2', async () => {})
    expect(secondEntered).toBe(false)

    releaseFirst()
    await second
    expect(secondEntered).toBe(true)
  })

  it('serializes human registration with an in-flight note edit', async () => {
    const coordination = createInMemoryAgentEditCoordination()
    let releaseEdit = () => {}
    let humanRegistered = false
    const editEntered = new Promise<void>((resolve) => {
      void coordination.withNoteLock('note-1', async () => {
        resolve()
        await new Promise<void>((release) => {
          releaseEdit = release
        })
      })
    })

    await editEntered
    const registration = coordination.humanConnected('note-1', 'socket-1').then(() => {
      humanRegistered = true
    })
    await Promise.resolve()
    expect(humanRegistered).toBe(false)

    releaseEdit()
    await registration
    expect(humanRegistered).toBe(true)
    await expect(coordination.hasActiveHuman('note-1')).resolves.toBe(true)
  })
})
