import { describe, expect, it } from 'vitest'

import { buildDeploymentConfig } from './deployment'

describe('web deployment origins', () => {
  it('preserves the polo-apps production defaults', () => {
    const config = buildDeploymentConfig({} as NodeJS.ProcessEnv)

    expect(config.deploymentUrls.web).toBe('https://camp.polo-apps.com')
    expect(config.deploymentOrigins).toContain('wss://camp-sync.polo-apps.com')
    expect(config.deploymentImageDomains).toContain('camp-cdn.polo-apps.com')
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
    } as unknown as NodeJS.ProcessEnv)

    expect(JSON.stringify(config)).not.toContain('polo-apps.com')
    expect(config.deploymentOrigins.sort()).toEqual([
      'https://camp-admin.tokdio.com',
      'https://camp-api.tokdio.com',
      'https://camp-auth.tokdio.com',
      'https://camp-cdn.tokdio.com',
      'https://camp-objects.tokdio.com',
      'https://camp.tokdio.com',
      'wss://camp-sync.tokdio.com'
    ])
  })

  it('renders the private HTTP camp.home origin set', () => {
    const config = buildDeploymentConfig({
      NEXT_PUBLIC_WEB_URL: 'http://camp.home',
      NEXT_PUBLIC_API_URL: 'http://api.camp.home',
      NEXT_PUBLIC_AUTH_URL: 'http://auth.camp.home',
      NEXT_PUBLIC_ADMIN_URL: 'http://admin.camp.home',
      NEXT_PUBLIC_SYNC_URL: 'ws://sync.camp.home',
      NEXT_PUBLIC_CDN_URL: 'http://cdn.camp.home',
      NEXT_PUBLIC_IMGIX_URL: 'http://cdn.camp.home',
      NEXT_PUBLIC_OBJECT_STORAGE_URL: 'http://cdn.camp.home'
    } as unknown as NodeJS.ProcessEnv)

    expect(JSON.stringify(config)).not.toContain('https://')
    expect(config.deploymentOrigins.sort()).toEqual([
      'http://admin.camp.home',
      'http://api.camp.home',
      'http://auth.camp.home',
      'http://camp.home',
      'http://cdn.camp.home',
      'ws://sync.camp.home'
    ])
  })
})
