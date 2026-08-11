const assert = require('node:assert/strict')
const { execFileSync } = require('node:child_process')
const { describe, it } = require('node:test')

const CONFIG_KEYS = [
  'WEB_URL',
  'SITE_URL',
  'SYNC_URL',
  'RAILS_API_URL',
  'RAILS_AUTH_URL',
  'RAILS_ADMIN_URL',
  'IMGIX_DOMAIN',
  'LINEAR_CALLBACK_URL'
]

function loadConfig(overrides = {}) {
  const script = `
    const config = require('./dist')
    const keys = ${JSON.stringify(CONFIG_KEYS)}
    console.log(JSON.stringify(Object.fromEntries(keys.map((key) => [key, config[key]]))))
  `

  return JSON.parse(
    execFileSync(process.execPath, ['-e', script], {
      cwd: __dirname + '/..',
      encoding: 'utf8',
      env: { ...process.env, NODE_ENV: 'production', ...overrides }
    })
  )
}

describe('production URL configuration', () => {
  it('preserves the current production defaults', () => {
    const config = loadConfig()

    assert.equal(config.WEB_URL, 'https://camp.polo-apps.com')
    assert.equal(config.SITE_URL, 'https://www.campsite.com')
    assert.equal(config.SYNC_URL, 'wss://camp-sync.polo-apps.com')
    assert.equal(config.RAILS_API_URL, 'https://camp-api.polo-apps.com')
    assert.equal(config.RAILS_AUTH_URL, 'https://camp-auth.polo-apps.com')
    assert.equal(config.RAILS_ADMIN_URL, 'https://camp-admin.polo-apps.com')
    assert.equal(config.IMGIX_DOMAIN, 'https://truecamp.imgix.net')
  })

  it('uses the complete tokdio URL set in a production build', () => {
    const config = loadConfig({
      NEXT_PUBLIC_WEB_URL: 'https://camp.tokdio.com',
      NEXT_PUBLIC_SITE_URL: 'https://camp.tokdio.com',
      NEXT_PUBLIC_SYNC_URL: 'wss://camp-sync.tokdio.com',
      NEXT_PUBLIC_API_URL: 'https://camp-api.tokdio.com',
      NEXT_PUBLIC_AUTH_URL: 'https://camp-auth.tokdio.com',
      NEXT_PUBLIC_ADMIN_URL: 'https://camp-admin.tokdio.com',
      NEXT_PUBLIC_IMGIX_URL: 'https://camp-cdn.tokdio.com'
    })

    assert.equal(config.WEB_URL, 'https://camp.tokdio.com')
    assert.equal(config.SITE_URL, 'https://camp.tokdio.com')
    assert.equal(config.SYNC_URL, 'wss://camp-sync.tokdio.com')
    assert.equal(config.RAILS_API_URL, 'https://camp-api.tokdio.com')
    assert.equal(config.RAILS_AUTH_URL, 'https://camp-auth.tokdio.com')
    assert.equal(config.RAILS_ADMIN_URL, 'https://camp-admin.tokdio.com')
    assert.equal(config.IMGIX_DOMAIN, 'https://camp-cdn.tokdio.com')
    assert.equal(config.LINEAR_CALLBACK_URL, 'https://camp-api.tokdio.com/v1/integrations/linear/callback')
  })
})
