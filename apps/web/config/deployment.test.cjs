const assert = require('node:assert/strict')
const { describe, it } = require('node:test')

const { buildDeploymentConfig } = require('./deployment')

describe('web deployment origins', () => {
  it('preserves the polo-apps production defaults', () => {
    const config = buildDeploymentConfig({})

    assert.equal(config.deploymentUrls.web, 'https://camp.polo-apps.com')
    assert.ok(config.deploymentOrigins.includes('wss://camp-sync.polo-apps.com'))
    assert.ok(config.deploymentImageDomains.includes('camp-cdn.polo-apps.com'))
  })

  it('renders a tokdio canary without polo-apps deployment origins', () => {
    const config = buildDeploymentConfig({
      NEXT_PUBLIC_WEB_URL: 'https://camp.tokdio.com',
      NEXT_PUBLIC_API_URL: 'https://camp-api.tokdio.com',
      NEXT_PUBLIC_AUTH_URL: 'https://camp-auth.tokdio.com',
      NEXT_PUBLIC_ADMIN_URL: 'https://camp-admin.tokdio.com',
      NEXT_PUBLIC_SYNC_URL: 'wss://camp-sync.tokdio.com',
      NEXT_PUBLIC_CDN_URL: 'https://camp-cdn.tokdio.com',
      NEXT_PUBLIC_IMGIX_URL: 'https://camp-cdn.tokdio.com',
      NEXT_PUBLIC_OBJECT_STORAGE_URL: 'https://camp-objects.tokdio.com'
    })

    assert.equal(JSON.stringify(config).includes('polo-apps.com'), false)
    assert.deepEqual(config.deploymentOrigins.sort(), [
      'https://camp-admin.tokdio.com',
      'https://camp-api.tokdio.com',
      'https://camp-auth.tokdio.com',
      'https://camp-cdn.tokdio.com',
      'https://camp-objects.tokdio.com',
      'https://camp.tokdio.com',
      'wss://camp-sync.tokdio.com'
    ])
  })
})
