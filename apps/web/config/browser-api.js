const browserApiPrefix = '/api/rails'

function browserApiUrl(apiUrl, enabled, isBrowser) {
  return enabled === 'true' && isBrowser ? browserApiPrefix : apiUrl
}

function browserApiRewrites(apiUrl, enabled) {
  if (enabled !== 'true') return []

  const upstream = new URL(apiUrl)

  if (!['http:', 'https:'].includes(upstream.protocol) || upstream.username || upstream.password) {
    throw new Error('Browser API proxy requires an HTTP(S) upstream without credentials')
  }
  if (upstream.pathname !== '/' || upstream.search || upstream.hash) {
    throw new Error('Browser API proxy upstream must be an origin')
  }

  // Proxy only Rails REST endpoints; never expose an arbitrary upstream URL.
  return [{ source: `${browserApiPrefix}/v1/:path*`, destination: `${upstream.origin}/v1/:path*` }]
}

module.exports = { browserApiUrl, browserApiRewrites }
