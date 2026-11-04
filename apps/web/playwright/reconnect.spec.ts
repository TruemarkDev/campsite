import type { WebSocketRoute } from '@playwright/test'

import { ORG_PATH } from './consts'
import { expect, test } from './fixtures'

test('preserves edits made during a sync transport outage after reconnect and reload', async ({ page, context }) => {
  let interrupted = false
  let socket: WebSocketRoute | undefined
  let connections = 0

  await page.routeWebSocket(
    (url) => url.hostname === '127.0.0.1' && url.port === '9100',
    (route) => {
      connections++
      if (interrupted) {
        void route.close({ code: 1013, reason: 'Fixture sync outage' })
        return
      }
      socket = route
      route.connectToServer()
    }
  )
  const original = `Before interruption ${crypto.randomUUID()}`
  const recovered = `${original} — edited while disconnected`

  await page.goto(`${ORG_PATH}/notes`)
  await page.getByRole('button', { name: 'New doc', exact: true }).first().click()
  await page.waitForURL(new RegExp(`${ORG_PATH}/notes/[^/]+$`))
  const noteId = new URL(page.url()).pathname.split('/').pop()
  const canonical = async () => {
    const response = await context.request.get(`/api/rails/v1/organizations${ORG_PATH}/notes/${noteId}`)

    expect(response.status()).toBe(200)
    return (await response.json()).description_html as string
  }
  const editor = page.locator('.tiptap').first()

  await expect(editor).toHaveAttribute('contenteditable', 'true')
  await editor.fill(original)
  await expect.poll(canonical).toContain(original)
  const previousConnections = connections

  interrupted = true
  await socket!.close({ code: 1012, reason: 'Fixture sync interruption' })
  try {
    await expect.poll(() => connections).toBeGreaterThan(previousConnections)
    await editor.fill(recovered)
    await expect(editor).toContainText(recovered)
    expect(await canonical()).not.toContain('edited while disconnected')
  } finally {
    interrupted = false
  }
  await expect.poll(canonical).toContain(recovered)
  await page.reload()
  await expect(page.locator('.tiptap').first()).toContainText(recovered)
})
