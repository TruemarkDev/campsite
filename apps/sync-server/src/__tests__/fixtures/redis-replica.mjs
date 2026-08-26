import { readFile, writeFile } from 'node:fs/promises'
import { Redis } from '@hocuspocus/extension-redis'
import { Server } from '@hocuspocus/server'
import * as Y from 'yjs'

const redisUrl = new URL(process.env.TEST_REDIS_URL)
const redis = new Redis({
  host: redisUrl.hostname,
  port: Number(redisUrl.port || 6379),
  prefix: process.env.TEST_REDIS_PREFIX,
  options: { db: Number(redisUrl.pathname.slice(1) || 0), maxRetriesPerRequest: 1 },
  awaitInitialSyncTimeout: 2_000,
  disconnectDelay: 10
})
const connections = new Map()

function sendJson(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json' })
  response.end(JSON.stringify(body))
}

async function connectionFor(instance, documentName) {
  if (!connections.has(documentName)) {
    connections.set(documentName, await instance.openDirectConnection(documentName, {}))
  }

  return connections.get(documentName)
}

const server = new Server({
  port: Number(process.env.PORT),
  debounce: 60_000,
  extensions: [redis],
  async onLoadDocument({ document }) {
    try {
      Y.applyUpdate(document, Buffer.from(await readFile(process.env.TEST_STATE_FILE, 'utf8'), 'base64'))
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  },
  async onStoreDocument({ document }) {
    await writeFile(process.env.TEST_STATE_FILE, Buffer.from(Y.encodeStateAsUpdate(document)).toString('base64'))
  },
  async onRequest({ instance, request, response }) {
    const url = new URL(request.url, 'http://localhost')
    if (!['/edit', '/persist', '/state'].includes(url.pathname)) return

    const documentName = url.searchParams.get('document') || 'note-1'
    const connection = await connectionFor(instance, documentName)

    if (url.pathname === '/edit') {
      await connection.transact((document) => {
        const text = url.searchParams.get('text')
        const row = url.searchParams.get('row')

        if (text) document.getText('content').insert(document.getText('content').length, text)
        if (row) document.getArray('table').push([row])
      })
    }

    if (url.pathname === '/persist') {
      await connection.disconnect()
      connections.delete(documentName)
    }

    const document = connection.document
    sendJson(response, 200, {
      rows: document?.getArray('table').toArray() ?? [],
      text: document?.getText('content').toString() ?? ''
    })
    throw null
  }
})

async function shutdown() {
  for (const connection of connections.values()) await connection.disconnect()
  connections.clear()
  await server.destroy()
}

process.on('SIGTERM', () => {
  void shutdown().finally(() => process.exit(0))
})

await Promise.all([redis.pub.ping(), redis.sub.ping()])
server.listen()
process.send?.({ ready: true })
