import { Redis } from '@hocuspocus/extension-redis'
import { Hocuspocus } from '@hocuspocus/server'
import { TiptapTransformer } from '@hocuspocus/transformer'
import type { JSONContent } from '@tiptap/core'
import { generateJSON } from '@tiptap/html'
import * as Y from 'yjs'

import { getNoteExtensions } from '@campsite/editor'

import { createRedisAgentEditCoordination } from '../agentEditCoordination'
import { facadeInternals } from '../facade'
import { redisSettings, verifyRedisExtension } from '../redis'
import type { Context } from '../types'

const runWithRedis = process.env.TEST_REDIS_URL ? describe : describe.skip
const extensions = getNoteExtensions()
const mocks = vi.hoisted(() => ({ recordAttribution: vi.fn(), verifyGrant: vi.fn() }))

vi.mock('../api', () => ({
  api: {
    agentSyncGrants: {
      postAgentSyncGrantsNotesAttributions: () => ({ request: mocks.recordAttribution }),
      postAgentSyncGrantsVerify: () => ({ request: mocks.verifyGrant })
    }
  }
}))

const context: Context = {
  actorId: 'system:mention-labels',
  actorName: 'Campsite',
  actorType: 'agent',
  grantId: 'grant-mention',
  invokedBy: 'member-1',
  organization: 'acme',
  schemaVersion: 9,
  token: 'grant-token',
  type: 'Note'
}

runWithRedis('Redis multi-instance coordination', () => {
  it('coordinates human leases, note locks, and grant rate limits across instances', async () => {
    const prefix = `campsite-sync-agent-test-${crypto.randomUUID()}`
    const redisExtensions = [
      new Redis({
        ...redisSettings({ NODE_ENV: 'test', SYNC_REDIS_PREFIX: prefix, SYNC_REDIS_URL: process.env.TEST_REDIS_URL })
      }),
      new Redis({
        ...redisSettings({ NODE_ENV: 'test', SYNC_REDIS_PREFIX: prefix, SYNC_REDIS_URL: process.env.TEST_REDIS_URL })
      })
    ]
    const coordinators = redisExtensions.map((redis) => createRedisAgentEditCoordination(redis))

    try {
      await Promise.all(redisExtensions.map(verifyRedisExtension))

      await coordinators[0].humanConnected('note-human', 'socket-1')
      await expect(coordinators[1].hasActiveHuman('note-human')).resolves.toBe(true)

      const guardedInstance = new Hocuspocus<Context>({
        async onLoadDocument({ document }) {
          document.getText('content').insert(0, 'unchanged')
        }
      })
      mocks.verifyGrant.mockResolvedValueOnce({
        actor_id: 'summary-agent',
        actor_name: 'Summary agent',
        grant_id: 'grant-human-guard',
        invoked_by: 'member-1',
        organization: 'acme'
      })
      await expect(
        facadeInternals.applyEdit(
          guardedInstance,
          'grant-token',
          {
            note_id: 'note-human',
            mode: 'direct',
            operation: { type: 'set_content', content: '<p>Unsafe replacement</p>' }
          },
          coordinators[1]
        )
      ).rejects.toMatchObject({ code: 'active_editors', status: 409 })
      expect(guardedInstance.documents.size).toBe(0)

      await coordinators[0].humanDisconnected('note-human', 'socket-1')
      await expect(coordinators[1].hasActiveHuman('note-human')).resolves.toBe(false)

      let releaseFirst = () => {}
      let secondEntered = false
      const firstEntered = new Promise<void>((resolve) => {
        void coordinators[0].withNoteLock('note-lock', async () => {
          resolve()
          await new Promise<void>((release) => {
            releaseFirst = release
          })
        })
      })

      await firstEntered
      const second = coordinators[1].withNoteLock('note-lock', async () => {
        secondEntered = true
      })
      await coordinators[1].withNoteLock('another-note', async () => {})
      expect(secondEntered).toBe(false)

      releaseFirst()
      await second
      expect(secondEntered).toBe(true)

      let releaseEdit = () => {}
      let humanRegistered = false
      const editEntered = new Promise<void>((resolve) => {
        void coordinators[0].withNoteLock('note-connect-race', async () => {
          resolve()
          await new Promise<void>((release) => {
            releaseEdit = release
          })
        })
      })
      await editEntered
      const registration = coordinators[1].humanConnected('note-connect-race', 'socket-race').then(() => {
        humanRegistered = true
      })
      await new Promise((resolve) => setTimeout(resolve, 25))
      expect(humanRegistered).toBe(false)

      releaseEdit()
      await registration
      await expect(coordinators[0].hasActiveHuman('note-connect-race')).resolves.toBe(true)
      await coordinators[1].humanDisconnected('note-connect-race', 'socket-race')

      for (let request = 0; request < 30; request += 1) {
        await expect(coordinators[request % 2].takeRateLimit('grant-shared')).resolves.toBe(true)
      }
      await expect(coordinators[1].takeRateLimit('grant-shared')).resolves.toBe(false)

      const rateKeys = await redisExtensions[0].pub.keys(`${prefix}:agent-edits:rate:*`)
      expect(rateKeys).toHaveLength(2)
      const rateTtls = await Promise.all(rateKeys.map((key) => redisExtensions[0].pub.pttl(key)))
      expect(rateTtls.every((ttl) => ttl > 0)).toBe(true)
      expect(await redisExtensions[0].pub.keys(`${prefix}:agent-edits:lock:*`)).toEqual([])
    } finally {
      for (const coordinator of coordinators.reverse()) await coordinator.destroy()
      const keys = await redisExtensions[0].pub.keys(`${prefix}:agent-edits:*`)
      if (keys.length > 0) await redisExtensions[0].pub.del(...keys)
      for (const redis of redisExtensions.reverse()) await redis.onDestroy()
    }
  })

  it('expires a crashed replica human lease', async () => {
    const prefix = `campsite-sync-agent-lease-test-${crypto.randomUUID()}`
    const redisExtensions = [
      new Redis({
        ...redisSettings({ NODE_ENV: 'test', SYNC_REDIS_PREFIX: prefix, SYNC_REDIS_URL: process.env.TEST_REDIS_URL })
      }),
      new Redis({
        ...redisSettings({ NODE_ENV: 'test', SYNC_REDIS_PREFIX: prefix, SYNC_REDIS_URL: process.env.TEST_REDIS_URL })
      })
    ]
    const crashed = createRedisAgentEditCoordination(redisExtensions[0], {
      humanLeaseMs: 100,
      humanRefreshMs: 60_000
    })
    const observer = createRedisAgentEditCoordination(redisExtensions[1])

    try {
      await Promise.all(redisExtensions.map(verifyRedisExtension))
      await crashed.humanConnected('note-crashed', 'socket-crashed')
      await expect(observer.hasActiveHuman('note-crashed')).resolves.toBe(true)

      await new Promise((resolve) => setTimeout(resolve, 150))
      await expect(observer.hasActiveHuman('note-crashed')).resolves.toBe(false)
    } finally {
      await crashed.destroy()
      await observer.destroy()
      const keys = await redisExtensions[0].pub.keys(`${prefix}:agent-edits:*`)
      if (keys.length > 0) await redisExtensions[0].pub.del(...keys)
      for (const redis of redisExtensions.reverse()) await redis.onDestroy()
    }
  })

  it('shares live mention and awareness updates, persists them, and preserves unsaved state during replacement', async () => {
    const prefix = `campsite-sync-test-${crypto.randomUUID()}`
    const redisExtensions: Redis[] = []
    const connections: Array<Awaited<ReturnType<Hocuspocus<Context>['openDirectConnection']>>> = []
    let stores = 0
    let persisted = Y.encodeStateAsUpdate(
      TiptapTransformer.toYdoc(
        generateJSON(
          '<h2>Plan</h2><table><tbody><tr><td><p>One</p></td><td><p>Two</p></td></tr></tbody></table><post-attachment id="attachment-1" file_type="image/png" width="100" height="100"></post-attachment><p>Hello <span data-type="mention" data-id="member-1" data-label="Old Name" data-role="member" data-username="old_username">@Old Name</span></p>',
          extensions
        ),
        'default',
        extensions
      )
    )

    const createInstance = async () => {
      const redis = new Redis({
        ...redisSettings({ NODE_ENV: 'test', SYNC_REDIS_PREFIX: prefix, SYNC_REDIS_URL: process.env.TEST_REDIS_URL }),
        awaitInitialSyncTimeout: 2_000,
        disconnectDelay: 10
      })
      redisExtensions.push(redis)
      await verifyRedisExtension(redis)

      return new Hocuspocus<Context>({
        debounce: 60_000,
        extensions: [redis],
        async onLoadDocument({ document }) {
          Y.applyUpdate(document, persisted)
        },
        async onStoreDocument({ document }) {
          persisted = Y.encodeStateAsUpdate(document)
          stores += 1
        }
      })
    }

    try {
      const first = await createInstance()
      const second = await createInstance()
      const firstConnection = await first.openDirectConnection('note-1', context)
      const secondConnection = await second.openDirectConnection('note-1', context)
      connections.push(firstConnection, secondConnection)

      await firstConnection.transact((document) => {
        facadeInternals.updateMentionAttributes(document, {
          type: 'update_mentions',
          membership_id: 'member-1',
          display_name: 'New Name',
          username: 'new_username'
        })
      })

      await vi.waitFor(
        () => {
          expect(JSON.stringify(TiptapTransformer.fromYdoc(secondConnection.document!, 'default'))).toContain(
            'new_username'
          )
        },
        { timeout: 3_000 }
      )

      const websocketConnection = { messageAddress: 'note-1', send: vi.fn() }
      firstConnection.document!.connections.set(websocketConnection as never, { clients: new Set() })
      firstConnection.document!.awareness.setLocalState({ user: { id: 'member-1', name: 'Active editor' } })
      await vi.waitFor(
        () => {
          expect([...secondConnection.document!.awareness.getStates().values()]).toContainEqual({
            user: { id: 'member-1', name: 'Active editor' }
          })
        },
        { timeout: 3_000 }
      )
      firstConnection.document!.connections.delete(websocketConnection as never)

      await secondConnection.disconnect()
      const persistedDocument = new Y.Doc()
      Y.applyUpdate(persistedDocument, persisted)

      expect(stores).toBeGreaterThan(0)
      expect(JSON.stringify(TiptapTransformer.fromYdoc(persistedDocument, 'default'))).toContain('new_username')

      await firstConnection.transact((document) => {
        facadeInternals.updateMentionAttributes(document, {
          type: 'update_mentions',
          membership_id: 'member-1',
          display_name: 'Unsaved Name',
          username: 'unsaved_username'
        })
      })

      const replacement = await createInstance()
      const replacementConnection = await replacement.openDirectConnection('note-1', context)
      connections.push(replacementConnection)
      const replacementJson = TiptapTransformer.fromYdoc(replacementConnection.document!, 'default') as JSONContent

      expect(JSON.stringify(replacementJson)).toContain('unsaved_username')
      expect(replacementConnection.document!.getXmlFragment('default')).toHaveLength(4)
      expect(replacementJson.content?.map((node) => node.type)).toEqual([
        'heading',
        'table',
        'postNoteAttachment',
        'paragraph'
      ])
    } finally {
      for (const connection of connections.reverse()) await connection.disconnect()
      for (const redis of redisExtensions.reverse()) await redis.onDestroy()
    }
  })
})
