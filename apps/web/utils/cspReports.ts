const directives = new Set(['script-src', 'script-src-elem', 'script-src-attr'])
const kinds = new Set(['eval', 'wasm-eval', 'inline'])

export interface CspSummary {
  directive: string
  kind: string
}

function summary(body: unknown): CspSummary | undefined {
  if (!body || typeof body !== 'object') return
  const fields = body as Record<string, unknown>

  if (fields.disposition !== 'report') return
  const directive = fields['effective-directive'] ?? fields.effectiveDirective

  if (typeof directive !== 'string' || !directives.has(directive)) return
  const blocked = fields['blocked-uri'] ?? fields.blockedURL

  return { directive, kind: typeof blocked === 'string' && kinds.has(blocked) ? blocked : 'other' }
}

export function cspSummaries(body: unknown): CspSummary[] {
  if (!body || typeof body !== 'object') throw new Error('Invalid CSP report')
  const reports: unknown[] = []

  if (Array.isArray(body)) {
    if (body.length > 20) throw new Error('Too many CSP reports')
    for (const report of body) {
      if (report?.type === 'csp-violation') reports.push(report.body)
    }
  } else {
    const fields = body as Record<string, unknown>

    if (!fields['csp-report']) throw new Error('Invalid CSP report')
    reports.push(fields['csp-report'])
  }
  return reports.flatMap((report) => {
    const item = summary(report)

    return item ? [item] : []
  })
}

// At most twelve fixed buckets: three directives times four kinds. Neither
// memory use nor log cardinality grows with URLs, tenants or attacker input.
export function createCspReporter(log = (message: string) => process.stderr.write(`${message}\n`), now = Date.now) {
  const lastLogged = new Map<string, number>()

  return (items: CspSummary[]) => {
    for (const { directive, kind } of items) {
      if (!directives.has(directive) || (!kinds.has(kind) && kind !== 'other')) continue
      const key = `${directive}:${kind}`
      const current = now()
      const last = lastLogged.get(key)

      if (last !== undefined && current - last < 60_000) continue
      lastLogged.set(key, current)
      log(JSON.stringify({ event: 'csp_violation', policy: 'strict-scripts-v1', directive, kind, sampled: true }))
    }
  }
}
