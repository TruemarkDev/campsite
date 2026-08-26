import { Redis } from '@hocuspocus/extension-redis'
import { Hocuspocus } from '@hocuspocus/server'
import { TiptapTransformer } from '@hocuspocus/transformer'
import type { JSONContent } from '@tiptap/core'
import { generateJSON } from '@tiptap/html'
import * as Y from 'yjs'

import { getNoteExtensions } from '@campsite/editor'

import { facadeInternals } from '../facade'
import { redisSettings, verifyRedisExtension } from '../redis'
import type { Context } from '../types'

const runWithRedis = process.env.TEST_REDIS_URL ? describe : describe.skip
const extensions = getNoteExtensions()
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
