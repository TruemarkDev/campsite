import { InfiniteData, QueryClient } from '@tanstack/react-query'
import { describe, expect, it } from 'vitest'

import { MessageThread, MessageThreadInbox, MessageThreadPusher } from '@campsite/types'

import { prependThreadToInbox, updateThreadInInbox } from '../prependThreadToInbox'

const thread = (id: string, project_id: string | null = null) => ({ id, project_id }) as MessageThread
const inbox = (): InfiniteData<MessageThreadInbox> => ({
  pageParams: [undefined, 'recent'],
  pages: [
    { threads: [thread('recent')], next_cursor: 'recent' },
    { threads: [thread('older')], next_cursor: null }
  ]
})

describe('prependThreadToInbox', () => {
  it('moves a thread from an older page while preserving cursors and the previous cache', () => {
    const original = inbox()
    const updated = prependThreadToInbox(original, thread('older'))!

    expect(updated.pages.map((page) => page.threads.map((item) => item.id))).toEqual([['older', 'recent'], []])
    expect(updated.pages.map((page) => page.next_cursor)).toEqual(['recent', null])
    expect(updated.pageParams).toEqual(original.pageParams)
    expect(original.pages[1].threads.map((item) => item.id)).toEqual(['older'])
  })

  it('adds a newly created conversation without replacing older pages', () => {
    const updated = prependThreadToInbox(inbox(), thread('new'))!

    expect(updated.pages.map((page) => page.threads.map((item) => item.id))).toEqual([['new', 'recent'], ['older']])
  })

  it('keeps project channels out of the direct-message inbox', () => {
    const original = inbox()

    expect(prependThreadToInbox(original, thread('channel', 'project'))).toBe(original)
    expect(prependThreadToInbox(undefined, thread('new'))).toBeUndefined()
  })
})

describe('updateThreadInInbox', () => {
  it('refetches when a message arrives for a thread outside the loaded pages', () => {
    const client = new QueryClient()
    const key = ['threads', 'org']
    const original = inbox()

    client.setQueryData(key, original)
    updateThreadInInbox(client, key, { id: 'unloaded', project_id: null } as MessageThreadPusher)
    expect(client.getQueryState(key)?.isInvalidated).toBe(true)
    expect(client.getQueryData(key)).toEqual(original)
  })

  it('promotes a loaded thread without refetching and retains fields absent from realtime payloads', () => {
    const client = new QueryClient()
    const key = ['threads', 'org']
    const original = inbox()

    original.pages[1].threads[0].other_members = []
    client.setQueryData(key, original)
    updateThreadInInbox(client, key, { id: 'older', project_id: null, title: 'Updated' } as MessageThreadPusher)
    const updated = client.getQueryData<InfiniteData<MessageThreadInbox>>(key)!

    expect(updated.pages[0].threads[0]).toMatchObject({ id: 'older', title: 'Updated', other_members: [] })
    expect(client.getQueryState(key)?.isInvalidated).toBe(false)
  })
})
