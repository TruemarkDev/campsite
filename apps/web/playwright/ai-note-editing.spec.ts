import { ORG_PATH } from './consts'
import { expect, test } from './fixtures'

test('shares an AI suggestion with another note client and lets it reject the change', async ({ context, page }) => {
  const originalText = 'The quarterly launch plan needs a concise executive summary.'
  const suggestedText = 'Add a concise executive summary to the quarterly launch plan.'
  let aiRequest: Record<string, unknown> | undefined

  await page.route('**/v1/organizations/browser-fixtures/notes/*/ai_edits', async (route) => {
    aiRequest = route.request().postDataJSON()
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        batch_id: 'playwright-ai-batch',
        actor_id: 'campsite-ai',
        actor_type: 'ai',
        invoked_by: 'Browser Author',
        created_at: '2026-08-25T00:00:00Z',
        instruction: 'Make this more concise',
        operations: [{ type: 'replace_range', text: suggestedText }]
      })
    })
  })

  await page.goto(`${ORG_PATH}/notes`)
  await page.getByRole('button', { name: 'New doc', exact: true }).first().click()
  await page.waitForURL(new RegExp(`${ORG_PATH}/notes/[^/]+$`))

  const noteUrl = page.url()
  const editor = page.locator('.tiptap').first()

  await expect(editor).toHaveAttribute('contenteditable', 'true')
  await editor.fill(originalText)
  await expect(editor).toContainText(originalText)

  const collaborator = await context.newPage()

  await collaborator.goto(noteUrl)
  const collaboratorEditor = collaborator.locator('.tiptap').first()

  await expect(collaboratorEditor).toContainText(originalText)

  await page.bringToFront()
  await editor.click()
  await editor.selectText()
  await expect.poll(() => page.evaluate(() => window.getSelection()?.toString().trim())).toBe(originalText)
  await page.getByRole('button', { name: 'Edit with AI' }).click()
  await page.getByLabel('Instruction').fill('Make this more concise')
  await page.getByRole('button', { name: 'Suggest edit' }).click()

  await expect.poll(() => aiRequest?.instruction).toBe('Make this more concise')
  await expect
    .poll(() => String((aiRequest?.context as { selected_text?: string } | undefined)?.selected_text).trim())
    .toBe(originalText)
  await expect(page.getByText('1 suggested change')).toBeVisible()
  await expect(collaborator.getByText('1 suggested change')).toBeVisible()
  await expect(collaborator.locator('[data-suggestion-insert]')).toContainText(suggestedText)
  await expect(collaborator.locator('[data-suggestion-delete]')).toContainText(originalText)

  await collaborator.getByRole('button', { name: 'Reject all' }).click()

  await expect(collaboratorEditor).toContainText(originalText)
  await expect(collaboratorEditor).not.toContainText(suggestedText)
  await expect(page.locator('[data-suggestion-insert]')).toHaveCount(0)
  await expect(page.locator('[data-suggestion-delete]')).toHaveCount(0)
  await expect(editor).toContainText(originalText)
})

test('persists a shared note after the collaborator closes and the author reloads', async ({ context, page }) => {
  const text = `Persistence regression ${crypto.randomUUID()}`

  await page.goto(`${ORG_PATH}/notes`)
  await page.getByRole('button', { name: 'New doc', exact: true }).first().click()
  await page.waitForURL(new RegExp(`${ORG_PATH}/notes/[^/]+$`))
  await expect(page.locator('.tiptap').first()).toHaveAttribute('contenteditable', 'true')
  const collaborator = await context.newPage()

  try {
    await collaborator.goto(page.url())
    await expect(page.locator('.tiptap').first()).toHaveAttribute('contenteditable', 'true')
    await page.locator('.tiptap').first().fill(text)
    await expect(collaborator.locator('.tiptap').first()).toContainText(text)
    const noteId = new URL(page.url()).pathname.split('/').pop()

    await expect
      .poll(async () => {
        const response = await context.request.get(`/api/rails/v1/organizations${ORG_PATH}/notes/${noteId}`)

        return (await response.json()).description_html
      })
      .toContain(text)
    await collaborator.close()
    await page.reload()
    await expect(page.locator('.tiptap').first()).toContainText(text)
  } finally {
    if (!collaborator.isClosed()) await collaborator.close()
  }
})
