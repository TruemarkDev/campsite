import { describe, expect, it, vi } from 'vitest'

import { createCspReporter, cspSummaries } from '../cspReports'

describe('CSP diagnostics', () => {
  it('discards document URLs, credentials, user content, samples and attacker-controlled fields', () => {
    const items = cspSummaries({
      'csp-report': {
        disposition: 'report',
        'effective-directive': 'script-src-elem',
        'blocked-uri': 'https://private.example/customer?token=synthetic-secret',
        'document-uri': 'https://camp.home/private-note?token=synthetic-secret',
        'script-sample': 'private user content',
        'source-file': 'private user content',
        arbitrary: 'private user content'
      }
    })

    expect(items).toEqual([{ directive: 'script-src-elem', kind: 'other' }])
    const log = vi.fn()

    createCspReporter(log)(items)
    expect(JSON.parse(log.mock.calls[0][0])).toEqual({
      event: 'csp_violation',
      policy: 'strict-scripts-v1',
      directive: 'script-src-elem',
      kind: 'other',
      sampled: true
    })
  })

  it('accepts modern CSP batches while ignoring unrelated report types and enforced-policy events', () => {
    expect(
      cspSummaries([
        {
          type: 'csp-violation',
          body: { disposition: 'report', effectiveDirective: 'script-src', blockedURL: 'eval' }
        },
        { type: 'deprecation', body: { arbitrary: 'ignored' } },
        {
          type: 'csp-violation',
          body: { disposition: 'enforce', effectiveDirective: 'script-src', blockedURL: 'eval' }
        },
        { type: 'csp-violation', body: { disposition: 'report', effectiveDirective: 'img-src', blockedURL: 'inline' } }
      ])
    ).toEqual([{ directive: 'script-src', kind: 'eval' }])
  })

  it('bounds the report batch and rejects invalid envelopes', () => {
    for (const value of [null, 'text', {}, Array(21).fill({})]) {
      expect(() => cspSummaries(value)).toThrow()
    }
    expect(cspSummaries([{ type: 'csp-violation', body: null }, null])).toEqual([])
  })

  it('bounds logging by fixed category and minute without retaining attacker input', () => {
    const log = vi.fn()
    let time = 0
    const report = createCspReporter(log, () => time)
    const items = [{ directive: 'script-src', kind: 'eval' }]

    report(items)
    for (let index = 0; index < 100; index++) report(items)
    report([
      { directive: 'attacker-controlled', kind: 'eval' },
      { directive: 'script-src', kind: 'attacker-controlled' }
    ])
    expect(log).toHaveBeenCalledTimes(1)
    time = 59_999
    report(items)
    expect(log).toHaveBeenCalledTimes(1)
    time = 60_000
    report(items)
    expect(log).toHaveBeenCalledTimes(2)
  })
})
