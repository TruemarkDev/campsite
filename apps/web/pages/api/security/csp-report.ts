import type { NextApiRequest, NextApiResponse } from 'next'

import { createCspReporter, cspSummaries } from '@/utils/cspReports'

export const config = { api: { bodyParser: { sizeLimit: '16kb' } } }
const report = createCspReporter()

export default function handler(request: NextApiRequest, response: NextApiResponse) {
  response.setHeader('Cache-Control', 'no-store')
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST')
    return response.status(405).end()
  }
  if (request.headers['sec-fetch-site'] === 'cross-site') return response.status(403).end()
  const contentType = request.headers['content-type']?.split(';', 1)[0].trim().toLowerCase()

  if (!['application/csp-report', 'application/reports+json'].includes(contentType || '')) {
    return response.status(415).end()
  }
  try {
    const body = typeof request.body === 'string' ? JSON.parse(request.body) : request.body

    report(cspSummaries(body))
  } catch {
    // Reports are untrusted. Never attach the body or exception to diagnostics.
    return response.status(400).end()
  }
  return response.status(204).end()
}
