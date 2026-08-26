import { spawn, type ChildProcess } from 'node:child_process'
import { mkdtemp, rm } from 'node:fs/promises'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const runWithRedis = process.env.TEST_REDIS_URL ? describe : describe.skip
const fixture = fileURLToPath(new URL('./fixtures/redis-replica.mjs', import.meta.url))

async function availablePort() {
  const server = createServer()
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') throw new Error('Unable to reserve a test port')
  await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())))
  return address.port
}

async function startReplica(port: number, prefix: string, stateFile: string) {
  const output: string[] = []
  const child = spawn(process.execPath, [fixture], {
    env: {
      NODE_ENV: 'test',
      PATH: process.env.PATH,
      PORT: String(port),
      TEST_REDIS_PREFIX: prefix,
      TEST_REDIS_URL: process.env.TEST_REDIS_URL,
      TEST_STATE_FILE: stateFile
    },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc']
  })
  child.stdout?.on('data', (chunk) => output.push(chunk.toString()))
  child.stderr?.on('data', (chunk) => output.push(chunk.toString()))

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Replica startup timed out:\n${output.join('')}`)), 10_000)
    child.once('error', reject)
    child.once('exit', (code) => reject(new Error(`Replica exited ${code}:\n${output.join('')}`)))
    child.once('message', () => {
      clearTimeout(timeout)
      resolve()
    })
  })

  return child
}

async function stopReplica(child: ChildProcess) {
  if (child.exitCode !== null || child.signalCode !== null) return

  child.kill('SIGTERM')
  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      child.kill('SIGKILL')
      resolve()
    }, 5_000)
    child.once('exit', () => {
      clearTimeout(timeout)
      resolve()
    })
  })
}

async function request(port: number, path: string) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`)
  if (!response.ok) throw new Error(`Replica returned ${response.status}`)
  return response.json() as Promise<{ rows: string[]; text: string }>
}

runWithRedis('Redis multi-process coordination', () => {
  it('shares and persists edits while a replacement loads unsaved peer state', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'campsite-sync-redis-'))
    const stateFile = join(directory, 'state.bin')
    const prefix = `campsite-sync-process-test-${crypto.randomUUID()}`
    const replicas: ChildProcess[] = []

    try {
      const [firstPort, secondPort, replacementPort] = await Promise.all([
        availablePort(),
        availablePort(),
        availablePort()
      ])
      const first = await startReplica(firstPort, prefix, stateFile)
      const second = await startReplica(secondPort, prefix, stateFile)
      replicas.push(first, second)

      await request(firstPort, '/edit?document=note-1&text=from-first')
      await vi.waitFor(() =>
        expect(request(secondPort, '/state?document=note-1')).resolves.toMatchObject({ text: 'from-first' })
      )

      await request(secondPort, '/edit?document=note-1&row=from-second')
      await vi.waitFor(() =>
        expect(request(firstPort, '/state?document=note-1')).resolves.toMatchObject({ rows: ['from-second'] })
      )

      const replacement = await startReplica(replacementPort, prefix, stateFile)
      replicas.push(replacement)
      await expect(request(replacementPort, '/state?document=note-1')).resolves.toEqual({
        rows: ['from-second'],
        text: 'from-first'
      })

      await request(replacementPort, '/persist?document=note-1')
      await stopReplica(second)

      const rollingPort = await availablePort()
      const rollingReplacement = await startReplica(rollingPort, prefix, stateFile)
      replicas.push(rollingReplacement)
      await expect(request(rollingPort, '/state?document=note-1')).resolves.toEqual({
        rows: ['from-second'],
        text: 'from-first'
      })
    } finally {
      for (const replica of replicas.reverse()) await stopReplica(replica)
      await rm(directory, { force: true, recursive: true })
    }
  }, 30_000)
})
