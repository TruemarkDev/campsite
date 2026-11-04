import { createRequire } from 'node:module'
import path from 'node:path'

import { APP_URL, ORG_PATH } from './consts'
import { authenticate, expect, test } from './fixtures'

// Observe the backend's logical document close, not its multiplexed TCP socket.
const requireSync = createRequire(path.resolve(__dirname, '../../sync-server/package.json'))
const { IncomingMessage, MessageType } = requireSync('@hocuspocus/server')

test('an independent member cannot read a private doc or edit a view-only doc', async ({ browser }) => {
  const context = await browser.newContext({ baseURL: APP_URL, storageState: { cookies: [], origins: [] } })

  try {
    const page = await authenticate(context, 'viewer@example.test')
    const denied = await context.request.get(`${APP_URL}/api/rails/v1/organizations${ORG_PATH}/notes/pwprivate001`)

    expect(denied.status()).toBe(403)
    await page.goto(`${ORG_PATH}/notes/pwprivate001`)
    await expect(page.getByText('Private fixture content', { exact: true })).toHaveCount(0)
    await page.goto(`${ORG_PATH}/notes/pwshared0001`)
    await expect(page.locator('.tiptap')).toContainText('Read-only fixture content')
    await expect(page.locator('.tiptap')).toHaveAttribute('contenteditable', 'false')
    const changed = await context.request.put(`${APP_URL}/api/rails/v1/organizations${ORG_PATH}/notes/pwshared0001`, {
      data: { title: 'Unauthorized edit' }
    })

    expect(changed.status()).toBe(403)
  } finally {
    await context.close()
  }
})

test('revoking a permission closes an already connected viewer when its access lease expires', async ({
  browser,
  context
}) => {
  const viewer = await browser.newContext({ baseURL: APP_URL, storageState: { cookies: [], origins: [] } })
  let revokedConnectionClosed = false
  let synchronized = false

  try {
    const page = await authenticate(viewer, 'viewer@example.test')

    await page.routeWebSocket(
      (url) => url.hostname === '127.0.0.1' && url.port === '9100',
      (route) => {
        const server = route.connectToServer()

        server.onMessage((data) => {
          route.send(data)
          if (typeof data === 'string') return
          const message = new IncomingMessage(data)

          if (message.readVarString() !== 'pwrevoked001') return
          const type = message.readVarUint()

          if (type === MessageType.Sync || type === MessageType.SyncReply) synchronized = true
          if (type === MessageType.CLOSE && message.readVarString() === 'invalid-permission') revokedConnectionClosed = true
        })
      }
    )
    await page.goto(`${ORG_PATH}/notes/pwrevoked001`)
    await expect(page.locator('.tiptap')).toContainText('Revocation fixture content')
    await expect.poll(() => synchronized).toBe(true)
    const revoked = await context.request.delete(
      `${APP_URL}/api/rails/v1/organizations${ORG_PATH}/notes/pwrevoked001/permissions/pwrevokeperm`
    )

    expect([200, 204]).toContain(revoked.status())
    const denied = await viewer.request.get(`${APP_URL}/api/rails/v1/organizations${ORG_PATH}/notes/pwrevoked001`)

    expect(denied.status()).toBe(403)
    // The server's idle check runs each minute with a ten-second API deadline.
    await expect.poll(() => revokedConnectionClosed, { timeout: 75_000 }).toBe(true)
  } finally {
    await viewer.close()
  }
})
