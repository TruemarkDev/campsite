import { ORG_PATH } from './consts'
import { expect, test } from './fixtures'

test('loads the dashboard', async ({ page }) => {
  await page.goto(ORG_PATH)
  await page.waitForURL(`${ORG_PATH}/posts`)
  await expect(page.locator('body')).toHaveText(/Inbox/)
})

test('creates a post and deletes it', async ({ page }) => {
  const text = `Browser post ${crypto.randomUUID()}`

  await page.goto(ORG_PATH)
  await page.getByRole('button', { name: 'New post', exact: true }).click()
  const dialog = page.getByRole('dialog')

  await dialog.locator('.tiptap').fill(text)
  const created = page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' && /\/posts$/.test(new URL(response.url()).pathname) && response.ok()
  )

  await dialog.getByRole('button', { name: 'Post', exact: true }).click()
  const { id } = await (await created).json()

  await page.goto(`${ORG_PATH}/posts/${id}`)
  await expect(page.getByText(text, { exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Post actions dropdown' }).click()
  await page.getByRole('menuitem', { name: /Delete/ }).click()
  await page
    .getByRole('dialog')
    .getByRole('button', { name: /Delete/ })
    .click()
  await expect(page.getByText(text, { exact: true })).toHaveCount(0)
})

test('edits an existing poll, votes and preserves the result on reload', async ({ page }) => {
  await page.goto(`${ORG_PATH}/posts/pwpoll000001`)
  await page.getByRole('button', { name: 'Post actions dropdown' }).click()
  await page.getByRole('menuitem', { name: 'Edit', exact: true }).click()
  const dialog = page.getByRole('dialog')

  await dialog.getByRole('button', { name: 'Add option', exact: true }).click()
  await dialog.getByPlaceholder('Third option').fill('Browser third option')
  await dialog.getByLabel('Remove option').nth(1).click()
  await dialog.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page.getByRole('button', { name: 'option b', exact: true })).toHaveCount(0)
  await page.getByRole('button', { name: 'Browser third option', exact: true }).click()
  await expect(page.getByText('1 vote', { exact: true })).toBeVisible()
  await page.reload()
  await expect(page.getByText('1 vote', { exact: true })).toBeVisible()
  await expect(page.getByText('Browser third option', { exact: true })).toBeVisible()
})
