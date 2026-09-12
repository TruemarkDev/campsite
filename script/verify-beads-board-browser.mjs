import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const require = createRequire(`${root}/apps/web/package.json`)
const { chromium, expect } = require('@playwright/test')
const ruby = process.env.BEADS_BOARD_RUBY || 'ruby'
const password = randomBytes(24).toString('hex')
const fixtureRepo = process.env.BEADS_BOARD_FIXTURE_REPOSITORY
const database = process.env.BEADS_BOARD_UAT_DATABASE
assert(
  fixtureRepo && basename(fixtureRepo).startsWith('campsite-beads-fixture-'),
  'Select a disposable campsite-beads-fixture-* repository'
)
assert(
  database && /^campsite_beads_board_[a-z0-9_]+$/.test(database),
  'Select a disposable campsite_beads_board_* database'
)
const evidenceDirectory =
  process.env.BEADS_BOARD_EVIDENCE_DIR || mkdtempSync(join(tmpdir(), 'campsite-beads-board-uat-'))
mkdirSync(evidenceDirectory, { recursive: true })
const env = {
  ...process.env,
  RAILS_ENV: 'test',
  PRIMARY_DATABASE_URL: `trilogy://root@127.0.0.1/${database}`,
  PRIMARY_REPLICA_DATABASE_URL: `trilogy://root@127.0.0.1/${database}`,
  OTEL_SDK_DISABLED: 'true',
  BOARD_FIXTURE_PASSWORD: password
}
const seed = `
Sidekiq.testing!(:fake)
Searchkick.disable_callbacks
Flipper.new(Flipper::Adapters::ActiveRecord.new).enable(:channel_beads_board)
include FactoryBot::Syntax::Methods
admin_user = User.find_by(email: "board-admin@example.test") || create(:user, email: "board-admin@example.test", username: "board_admin", name: "Board Admin")
admin_user.update!(password: ENV.fetch("BOARD_FIXTURE_PASSWORD"))
org = Organization.find_by(slug: "beads-board-uat") || create(:organization, :pro, name: "Beads Board Review", slug: "beads-board-uat", creator: admin_user)
admin = create(:organization_membership, :admin, organization: org, user: admin_user)
app = org.oauth_applications.find_by(name: "Fixture publisher") || create(:oauth_application, owner: org, creator: admin, name: "Fixture publisher", agent_capable: true)
projects = [false, true].map do |chat|
  name = chat ? "Board chat fixture" : "Board post fixture"
  project = org.projects.find_by(name: name) || create(:project, *(chat ? [:chat_project] : []), organization: org, creator: admin, name: name, private: true)
  project.add_member!(admin) unless project.kept_project_memberships.exists?(organization_membership: admin)
  project.add_oauth_application!(app, event_actor: admin) unless project.kept_project_memberships.exists?(oauth_application: app)
  project.project_beads_source&.destroy!
  project
end
guest_user = User.find_by(email: "board-guest@example.test") || create(:user, email: "board-guest@example.test", username: "board_guest", name: "Board Guest")
guest_user.update!(password: ENV.fetch("BOARD_FIXTURE_PASSWORD"))
guest = create(:organization_membership, :guest, organization: org, user: guest_user)
projects.each { |project| project.add_member!(guest) unless project.kept_project_memberships.exists?(organization_membership: guest) }
outsider_user = User.find_by(email: "board-outsider@example.test") || create(:user, email: "board-outsider@example.test", username: "board_outsider", name: "Board Outsider")
outsider_user.update!(password: ENV.fetch("BOARD_FIXTURE_PASSWORD"))
create(:organization_membership, :admin, organization: org, user: outsider_user)
token = create(:access_token, resource_owner: org, application: app)
puts "BOARD_FIXTURE=" + { org: org.slug, projects: projects.map(&:public_id), application: app.public_id, token: token.plaintext_token }.to_json
`
const seedOutput = execFileSync(ruby, ['-S', 'bundle', 'exec', 'rails', 'runner', seed], {
  cwd: `${root}/api`,
  env,
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'pipe']
})
const fixture = JSON.parse(
  seedOutput
    .split('\n')
    .find((line) => line.startsWith('BOARD_FIXTURE='))
    .slice('BOARD_FIXTURE='.length)
)
console.log('Disposable API fixtures prepared')
const browser = await chromium.launch({
  headless: true,
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
    ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
    : {})
})
const web = 'http://app.campsite.test:13000'
const api = 'http://api.campsite.test:13001'
const evidence = []
async function context(email, viewport = { width: 1440, height: 1000 }) {
  const context = await browser.newContext({ viewport, reducedMotion: 'reduce' })
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url())
    return url.hostname.endsWith('.campsite.test') ? route.continue() : route.abort()
  })
  const login = await context.request.post('http://auth.campsite.test:13001/sign-in', {
    form: { 'user[email]': email, 'user[password]': password },
    maxRedirects: 0
  })
  assert.equal(login.status(), 302, 'fixture sign-in failed')
  return context
}
function publish(project, args, challenge, expectedStatus = 0) {
  const result = spawnSync(
    ruby,
    [
      `${root}/script/publish-beads-board`,
      '--api-base-url',
      api,
      '--org',
      fixture.org,
      '--project-id',
      project,
      '--repository',
      fixtureRepo,
      '--beads-bin',
      process.env.BEADS_BOARD_BIN || 'bd',
      ...args
    ],
    {
      env: { ...env, CAMPSITE_BEADS_OAUTH_TOKEN: fixture.token },
      input: challenge ? `${challenge}\n` : undefined,
      encoding: 'utf8'
    }
  )
  assert.equal(result.status, expectedStatus, `Unexpected publisher result: ${result.stderr}`)
}
function runRails(code) {
  return execFileSync(ruby, ['-S', 'bundle', 'exec', 'rails', 'runner', code], {
    cwd: `${root}/api`,
    env,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  })
}
const sourceState = () =>
  ['vc status --json', 'export'].map((command) =>
    execFileSync(process.env.BEADS_BOARD_BIN || 'bd', ['--readonly', ...command.split(' ')], {
      cwd: fixtureRepo,
      encoding: 'utf8'
    })
  )
const initialSourceState = sourceState()
try {
  const admin = await context('board-admin@example.test')
  const page = await admin.newPage()
  page.on('pageerror', (error) => console.log('Page error:', error.message.slice(0, 160)))
  for (const [index, project] of fixture.projects.entries()) {
    const path = `/${fixture.org}/projects/${project}`
    await page.goto(`${web}${path}`, { waitUntil: 'domcontentloaded', timeout: 120000 })
    await expect(
      page.getByText(index ? 'Board chat fixture' : 'Board post fixture', { exact: true }).first()
    ).toBeVisible({ timeout: 120000 })
    if (!(await page.getByLabel('Publisher application').isVisible()))
      await page.getByRole('button', { name: 'Open sidebar', exact: true }).click()
    await expect(page.getByLabel('Publisher application')).toBeVisible()
    await page.getByLabel('Publisher application').selectOption(fixture.application)
    const pairingResponse = page.waitForResponse(
      (response) => response.url().endsWith('/beads_source/pairings') && response.request().method() === 'POST'
    )
    await page.getByRole('button', { name: 'Start pairing', exact: true }).click()
    const pairing = await (await pairingResponse).json()
    assert(pairing.challenge, 'pairing challenge missing')
    await expect(page.getByRole('link', { name: 'Board', exact: true })).toHaveCount(0)
    publish(project, ['--pair'], pairing.challenge)
    await expect(page.getByRole('link', { name: 'Board', exact: true }).first()).toBeVisible({ timeout: 15000 })
    await page.evaluate(() => document.activeElement?.blur())
    await page.keyboard.press(index ? '3' : '4')
    await page.waitForURL(`${web}${path}/board`, { waitUntil: 'domcontentloaded', timeout: 90000 })
    await expect(page.getByText('Waiting for the first snapshot')).toBeVisible()
    const response = await admin.request.get(`${api}/v1/organizations/${fixture.org}/projects/${project}/beads_board`)
    assert.equal(response.status(), 200)
    const board = await response.json()
    publish(project, ['--source-id', board.source_id, '--source-project-id', board.source_project_id])
    await page.reload()
    await expect(page.getByRole('article', { name: /Ready fixture/ })).toBeVisible({ timeout: 30000 })
    for (const name of ['Ready', 'In progress', 'Blocked', 'Deferred'])
      await expect(page.getByRole('region', { name, exact: true })).toBeVisible()
    await page.getByRole('checkbox', { name: 'Include Closed' }).click()
    await expect(page.getByRole('article', { name: /Closed fixture/ })).toBeAttached()
    await page.getByRole('searchbox').fill('Working fixture')
    await expect(page.getByRole('article')).toHaveCount(1)
    await expect(page.getByRole('article', { name: /Working fixture/ })).toBeVisible()
    await page.getByRole('searchbox').fill('')
    for (const label of ['Issue type', 'Priority', 'Assignee', 'Label'])
      await expect(page.getByRole('combobox', { name: label, exact: true })).toBeInViewport()
    await expect(page.getByText('Agent · Beads publisher · Attached', { exact: true }).first()).toBeVisible()
    await page.screenshot({ path: join(evidenceDirectory, `${index ? 'chat' : 'post'}-desktop.png`) })
    evidence.push(
      `${index ? 'Chat' : 'Post'} channel: UI pairing, native publisher, waiting state, keyboard navigation, columns, Closed filter, title filter, attached roster passed`
    )
    console.log(evidence.at(-1))
  }
  await page.setViewportSize({ width: 390, height: 844 })
  for (const label of ['Issue type', 'Priority', 'Assignee', 'Label'])
    await expect(page.getByRole('combobox', { name: label, exact: true })).toBeInViewport()
  await page.screenshot({ path: join(evidenceDirectory, 'mobile.png') })
  await expect(page.getByRole('region', { name: 'Ready', exact: true })).toBeVisible()
  evidence.push('Mobile Board renders at 390x844 with reduced motion')
  const guest = await context('board-guest@example.test')
  const guestResponse = await guest.request.get(
    `${api}/v1/organizations/${fixture.org}/projects/${fixture.projects[0]}/beads_board`
  )
  assert.equal(guestResponse.status(), 200)
  const outsider = await context('board-outsider@example.test')
  const outsiderResponse = await outsider.request.get(
    `${api}/v1/organizations/${fixture.org}/projects/${fixture.projects[0]}/beads_board`
  )
  assert.equal(outsiderResponse.status(), 403)
  evidence.push('Explicit guest read and nonmember denial passed via authenticated API')
  const postProject = fixture.projects[0]
  const sourceUrl = `${api}/v1/organizations/${fixture.org}/projects/${postProject}/beads_board`
  const current = await (await admin.request.get(sourceUrl)).json()
  const publisherArgs = ['--source-id', current.source_id, '--source-project-id', current.source_project_id]
  assert.equal(
    (await admin.request.put(`${api}/v1/organizations/${fixture.org}/projects/${postProject}/archive`)).status(),
    200
  )
  publish(postProject, publisherArgs, undefined, 1)
  assert.equal(
    (await (await admin.request.get(sourceUrl)).json()).current_snapshot.digest,
    current.current_snapshot.digest
  )
  assert.equal(
    (await admin.request.put(`${api}/v1/organizations/${fixture.org}/projects/${postProject}/unarchive`)).status(),
    200
  )
  publish(postProject, publisherArgs)
  evidence.push('Archive rejects publication and retains the snapshot; unarchive restores publication')
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(`${web}/${fixture.org}/projects/${postProject}/board`)
  await expect(page.getByRole('article', { name: /Ready fixture/ })).toBeVisible()
  await page.route(sourceUrl, (route) =>
    route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"Fixture refresh failure"}' })
  )
  await page.getByRole('button', { name: 'Refresh board', exact: true }).click()
  await expect(page.getByRole('status')).toContainText('Showing the last published snapshot', { timeout: 15000 })
  await expect(page.getByRole('article', { name: /Ready fixture/ })).toBeVisible()
  await page.unroute(sourceUrl)
  evidence.push('A browser refresh failure keeps the last good cards and displays the failure state')
  runRails(`Project.find_by!(public_id: ${JSON.stringify(postProject)}).update!(private: false)`)
  assert.equal(
    (await outsider.request.get(`${api}/v1/organizations/${fixture.org}/projects/${postProject}`)).status(),
    200
  )
  assert.equal((await outsider.request.get(sourceUrl)).status(), 403)
  evidence.push('Public-channel nonmembers can read the channel but cannot read its Board')
  await page.reload()
  await page.getByRole('button', { name: 'Detach source', exact: true }).click()
  await page.getByRole('button', { name: 'Confirm detach', exact: true }).click()
  await page.waitForURL(`${web}/${fixture.org}/projects/${postProject}`)
  await expect(page.getByRole('link', { name: 'Board', exact: true })).toHaveCount(0)
  assert.equal((await admin.request.get(sourceUrl)).status(), 404)
  evidence.push('UI detach removes source data and returns the viewer to the channel root')
  runRails('Flipper.new(Flipper::Adapters::ActiveRecord.new).disable(:channel_beads_board)')
  assert.equal(
    (
      await admin.request.get(`${api}/v1/organizations/${fixture.org}/projects/${fixture.projects[1]}/beads_board`)
    ).status(),
    404
  )
  await page.goto(`${web}/${fixture.org}/projects/${fixture.projects[1]}/board`)
  await page.waitForURL(`${web}/${fixture.org}/projects/${fixture.projects[1]}`)
  await expect(page.getByRole('link', { name: 'Board', exact: true })).toHaveCount(0)
  assert.deepEqual(sourceState(), initialSourceState)
  evidence.push(
    'Disabling the feature hides the route and blocks reads while Beads revision and export remain unchanged'
  )
  writeFileSync(
    join(evidenceDirectory, 'proof.json'),
    JSON.stringify({ evidence, projects: fixture.projects }, null, 2)
  )
  console.log(`Browser acceptance probe passed; evidence: ${evidenceDirectory}`)
} finally {
  await browser.close()
}
