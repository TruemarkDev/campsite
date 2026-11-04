import { describe, expect, it } from 'vitest'

import { browserApiRewrites, browserApiUrl } from './browser-api'

describe('same-origin browser API transport', () => {
  const upstream = 'https://api.camp.home'

  it('uses a first-party path in the browser while SSR keeps the canonical API origin', () => {
    expect(browserApiUrl(upstream, 'true', true)).toBe('/api/rails')
    expect(browserApiUrl(upstream, 'true', false)).toBe(upstream)
  })

  it('leaves deployments unchanged unless explicitly enabled', () => {
    for (const setting of [undefined, '', 'false']) {
      expect(browserApiUrl(upstream, setting, true)).toBe(upstream)
      expect(browserApiRewrites(upstream, setting)).toEqual([])
    }
  })

  it('exposes only v1 REST routes on the fixed upstream', () => {
    expect(browserApiRewrites(upstream, 'true')).toEqual([
      { source: '/api/rails/v1/:path*', destination: 'https://api.camp.home/v1/:path*' }
    ])
  })

  it('rejects credential-bearing URLs, non-HTTP protocols and upstream paths', () => {
    for (const url of [
      'file:///etc/passwd',
      'https://user:password@api.camp.home',
      `${upstream}/v1`,
      `${upstream}?x=1`
    ]) {
      expect(() => browserApiRewrites(url, 'true')).toThrow()
    }
  })
})
