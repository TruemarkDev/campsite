import { test as base, BrowserContext, expect } from '@playwright/test'

import { APP_URL, ORG_PATH } from './consts'

type AuthState = Awaited<ReturnType<BrowserContext['storageState']>>

async function isolate(context: BrowserContext) {
  context.on('page', (page) =>
    page.on('pageerror', (error) => process.stderr.write(`Browser error: ${error.name}: ${error.message}\n`))
  )
  const allowed = (url: string) =>
    ['app.campsite.test', 'api.campsite.test', 'auth.campsite.test', '127.0.0.1', 'localhost'].includes(
      new URL(url).hostname
    )

  await context.route('**/*', (route) => (allowed(route.request().url()) ? route.continue() : route.abort()))
  await context.routeWebSocket(/.*/, (socket) => {
    if (allowed(socket.url())) socket.connectToServer()
    else socket.close()
  })
}

export async function authenticate(context: BrowserContext, email = 'author@example.test') {
  await isolate(context)
  const page = await context.newPage()

  await page.goto(`${APP_URL}${ORG_PATH}`)
  await expect(
    page.getByLabel('Email', { exact: true }),
    `Fixture login at ${page.url()}: ${(await page.locator('body').innerText()).slice(0, 500)}`
  ).toBeVisible()
  await page.getByLabel('Email', { exact: true }).fill(email)
  await page.getByLabel('Password', { exact: true }).fill(process.env.BROWSER_TEST_PASSWORD!)
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await page.waitForURL(`${APP_URL}${ORG_PATH}/posts`)
  return page
}

export const test = base.extend<{}, { fixtureAuth: AuthState }>({
  fixtureAuth: [
    async ({ browser }, provide) => {
      const context = await browser.newContext({ storageState: { cookies: [], origins: [] } })

      await authenticate(context)
      const state = await context.storageState()

      await context.close()
      await provide(state)
    },
    { scope: 'worker' }
  ],
  storageState: async ({ fixtureAuth }, provide) => provide(fixtureAuth),
  context: async ({ context }, provide) => {
    await isolate(context)
    const resources = new Set<string>()
    const pending: Promise<void>[] = []

    context.on('response', (response) => {
      const match = new URL(response.url()).pathname.match(/\/v1\/organizations\/browser-fixtures\/(notes|posts)$/)

      if (!match || response.request().method() !== 'POST' || !response.ok()) return
      pending.push(
        response.json().then((body) => {
          if (body.id) resources.add(`${match[1]}/${body.id}`)
        })
      )
    })
    await provide(context)
    // Close collaborative sockets before deleting their canonical documents.
    for (const page of context.pages()) await page.close()
    await Promise.all(pending)
    for (const resource of [...resources].reverse()) {
      const response = await context.request.delete(`${APP_URL}/api/rails/v1/organizations${ORG_PATH}/${resource}`)

      expect([200, 204, 404], `cleanup ${resource}`).toContain(response.status())
    }
  }
})

export { expect }
