const reportPath = '/api/security/csp-report'

function serialize(directives) {
  return Object.entries(directives)
    .map(([name, values]) => `${name} ${values.filter(Boolean).join(' ')};`)
    .join(' ')
}

function contentSecurityHeaders(directives, environment, webUrl) {
  const headers = [{ key: 'Content-Security-Policy', value: serialize(directives) }]

  if (environment !== 'production') return headers

  // Observe incompatibilities before changing enforcement. Static Next.js
  // documents still contain inline hydration scripts without per-request nonces.
  const candidate = {
    ...directives,
    'script-src': directives['script-src'].filter((value) => !["'unsafe-inline'", "'unsafe-eval'"].includes(value)),
    'script-src-attr': ["'none'"],
    'report-uri': [reportPath]
  }
  const origin = new URL(webUrl)

  if (origin.protocol === 'https:') {
    candidate['report-to'] = ['campsite-csp']
    headers.push({
      key: 'Reporting-Endpoints',
      value: `campsite-csp="${new URL(reportPath, origin.origin).href}"`
    })
  }
  headers.push({ key: 'Content-Security-Policy-Report-Only', value: serialize(candidate) })
  return headers
}

module.exports = { contentSecurityHeaders }
