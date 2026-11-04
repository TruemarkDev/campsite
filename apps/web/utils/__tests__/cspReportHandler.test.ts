import type { NextApiRequest, NextApiResponse } from 'next'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import handler, { config } from '@/pages/api/security/csp-report'

const { report } = vi.hoisted(() => ({ report: vi.fn() }))

vi.mock('@/utils/cspReports', async () => ({
  ...(await vi.importActual<typeof import('../cspReports')>('@/utils/cspReports')),
  createCspReporter: () => report
}))

function invoke(method: string, body: unknown, headers = { 'content-type': 'application/csp-report' }) {
  const response = { setHeader: vi.fn(), status: vi.fn(), end: vi.fn() }

  response.status.mockReturnValue(response)
  handler({ method, body, headers } as NextApiRequest, response as unknown as NextApiResponse)
  return response
}

describe('CSP report endpoint', () => {
  beforeEach(() => report.mockClear())

  it('accepts a browser report without reflecting or retaining its body', () => {
    const response = invoke(
      'POST',
      JSON.stringify({
        'csp-report': { disposition: 'report', 'effective-directive': 'script-src', 'blocked-uri': 'eval' }
      })
    )

    expect(response.status).toHaveBeenCalledWith(204)
    expect(response.end).toHaveBeenCalledWith()
    expect(response.setHeader).toHaveBeenCalledWith('Cache-Control', 'no-store')
    expect(report).toHaveBeenCalledWith([{ directive: 'script-src', kind: 'eval' }])
  })

  it('accepts the modern Reporting API media type and batch shape', () => {
    const response = invoke(
      'POST',
      [
        { type: 'csp-violation', body: { disposition: 'report', effectiveDirective: 'script-src', blockedURL: 'eval' } }
      ],
      { 'content-type': 'application/reports+json; charset=utf-8' }
    )

    expect(response.status).toHaveBeenCalledWith(204)
  })

  it('rejects unsupported methods and media types without diagnostics', () => {
    const method = invoke('GET', null)

    expect(method.status).toHaveBeenCalledWith(405)
    expect(method.setHeader).toHaveBeenCalledWith('Allow', 'POST')
    expect(invoke('POST', {}, { 'content-type': 'text/plain' }).status).toHaveBeenCalledWith(415)
    expect(report).not.toHaveBeenCalled()
  })

  it('rejects malformed or excessive input without logging it', () => {
    for (const body of ['{invalid', null, {}, Array(21).fill({})]) {
      expect(invoke('POST', body).status).toHaveBeenCalledWith(400)
    }
    expect(report).not.toHaveBeenCalled()
    expect(config.api.bodyParser.sizeLimit).toBe('16kb')
  })

  it('rejects explicit cross-site browser submissions', () => {
    const response = { setHeader: vi.fn(), status: vi.fn(), end: vi.fn() }

    response.status.mockReturnValue(response)
    handler(
      { method: 'POST', headers: { 'sec-fetch-site': 'cross-site' } } as NextApiRequest,
      response as unknown as NextApiResponse
    )
    expect(response.status).toHaveBeenCalledWith(403)
    expect(report).not.toHaveBeenCalled()
  })
})
