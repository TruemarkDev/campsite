import { describe, expect, it } from 'vitest'

import { contentSecurityHeaders } from './content-security-policy'

const directives = {
  'script-src': ["'self'", "'unsafe-inline'", 'todesktop-internal:', 'blob:', "'unsafe-eval'"],
  'style-src': ["'self'", "'unsafe-inline'"],
  'connect-src': ["'self'", 'wss://sync.camp.home'],
  'object-src': ["'none'"]
}

describe('staged CSP headers', () => {
  it('keeps the enforced policy and existing SDK/desktop/style allowances intact', () => {
    const original = structuredClone(directives)
    const headers = Object.fromEntries(
      contentSecurityHeaders(directives, 'production', 'https://camp.home').map(({ key, value }) => [key, value])
    )

    expect(headers['Content-Security-Policy']).toContain("script-src 'self' 'unsafe-inline'")
    expect(headers['Content-Security-Policy']).toContain("'unsafe-eval'")
    expect(headers['Content-Security-Policy-Report-Only']).toContain("script-src 'self' todesktop-internal: blob:;")
    expect(headers['Content-Security-Policy-Report-Only']).toContain("script-src-attr 'none';")
    expect(headers['Content-Security-Policy-Report-Only']).toContain("style-src 'self' 'unsafe-inline';")
    expect(headers['Content-Security-Policy-Report-Only']).toContain("connect-src 'self' wss://sync.camp.home;")
    expect(headers['Content-Security-Policy-Report-Only']).not.toContain('report-sample')
    expect(directives).toEqual(original)
  })

  it('configures modern reporting and a same-origin legacy fallback', () => {
    const headers = Object.fromEntries(
      contentSecurityHeaders(directives, 'production', 'https://camp.home').map(({ key, value }) => [key, value])
    )

    expect(headers['Reporting-Endpoints']).toBe('campsite-csp="https://camp.home/api/security/csp-report"')
    expect(headers['Content-Security-Policy-Report-Only']).toContain('report-to campsite-csp;')
    expect(headers['Content-Security-Policy-Report-Only']).toContain('report-uri /api/security/csp-report;')
  })

  it('uses legacy reporting on local HTTP instead of advertising an insecure Reporting API endpoint', () => {
    const headers = contentSecurityHeaders(directives, 'production', 'http://localhost:3100')

    expect(headers.some(({ key }) => key === 'Reporting-Endpoints')).toBe(false)
    expect(headers.find(({ key }) => key.endsWith('Report-Only'))?.value).not.toContain('report-to')
  })

  it('does not generate noisy report-only diagnostics for development or test builds', () => {
    for (const environment of ['development', 'test']) {
      expect(contentSecurityHeaders(directives, environment, 'https://camp.home').map(({ key }) => key)).toEqual([
        'Content-Security-Policy'
      ])
    }
  })
})
