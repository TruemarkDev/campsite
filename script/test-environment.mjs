// Fixture/build processes must not inherit unrelated operator credentials.
export function testEnvironment(source = process.env) {
  const allowed = new Set([
    'PATH',
    'HOME',
    'USER',
    'LOGNAME',
    'SHELL',
    'TMPDIR',
    'TMP',
    'TEMP',
    'LANG',
    'TZ',
    'CI',
    'GEM_HOME',
    'GEM_PATH',
    'BUNDLE_PATH',
    'BUNDLE_APP_CONFIG',
    'BUNDLE_WITH',
    'BUNDLE_WITHOUT',
    'SSL_CERT_FILE',
    'SSL_CERT_DIR',
    'NODE_EXTRA_CA_CERTS'
  ])
  return Object.fromEntries(
    Object.entries(source).filter(
      ([name, value]) =>
        typeof value === 'string' && (allowed.has(name) || name.startsWith('LC_') || name.startsWith('PG_TEST_'))
    )
  )
}
