# Staged script CSP hardening

As built on 2026-11-04. Tracking: `campsite-yt7`. This implements the observation
stage of [TD-5](../reviews/frontend-backend-modernization-2026-11-02.md).

## Implemented behavior

Production builds emit two policies. The existing enforced
`Content-Security-Policy` retains its script/style compatibility allowances.
The additional `Content-Security-Policy-Report-Only` candidate omits
`unsafe-inline` and `unsafe-eval` from **script-src**, and adds
`script-src-attr 'none'`. Existing resource origins, blob workers, desktop scheme
and inline style support are preserved. Development/test builds emit only the
existing enforced policy, avoiding HMR diagnostic noise.

HTTPS deployments advertise the modern `Reporting-Endpoints` header and
`report-to campsite-csp`, using the configured `NEXT_PUBLIC_WEB_URL` origin.
The relative `report-uri /api/security/csp-report` remains an older-browser
fallback. Local HTTP uses only that fallback. Build-time deployment URL settings
therefore need to identify the actual canonical web origin.

The Next.js API route accepts legacy `application/csp-report` and modern
`application/reports+json` POSTs. It has a 16 KiB body limit, at most 20 reports
per batch, explicit cross-site rejection, method/media-type checks and no-store
responses. It does not require a session and changes no application records.

Only report-only script directive/kind categories reach application diagnostics:

```json
{ "event": "csp_violation", "policy": "strict-scripts-v1", "directive": "script-src", "kind": "eval", "sampled": true }
```

The collector discards document/blocked/source URLs, query strings, script
samples, user content, referrers and arbitrary report fields before logging.
It does not request `report-sample`. Incoming browser reports can contain those
fields transiently; the handler does not persist their bodies. The fixed three
directives and four kinds create at most twelve in-memory buckets per process.
Each bucket logs at most once per minute. Sampling is process-local, resets on
restart and does not provide exact violation counts or durable metrics.
Infrastructure request-body logging is outside this handler's control.

Reports are untrusted, can be forged or lost, and are diagnostic hints. They do
not prove an attack or justify automatically widening a policy. Normal ingress
controls remain responsible for overall request-volume limits.

## Compatibility and enforcement boundary

🟡 The candidate is **observational**, not enforced or deployed by this change.
The app has static pages (including public notes) and server-rendered pages.
Existing static HTML contains inline Next.js hydration scripts, so inline reports
are expected. A request nonce cannot safely be invented at build time or reused.
Adding per-request nonces across all pages would alter static rendering/caching.
This change makes no such rendering migration and does not claim full TD-5 closure.

Before promotion, exercise authentication/organization switching, post and note
editing, reconnects, calls with 100ms noise cancellation, embeds and the desktop
application against a report-only deployment. Inspect redacted category logs and
use a scoped browser console when an origin or source needs attribution. Do not
copy credential-bearing URLs or user text into evidence.

After those observations, assess eval separately from inline scripts. Remove an
enforced eval exception only after verifying the SDK/call paths that previously
motivated it. Removing inline script support needs a reviewed nonce/dynamic-rendering
or build-specific hash strategy plus hydration, navigation and caching tests.
Do not promote the entire candidate blindly or expand a global exception to
accommodate one route. Keep an exact image rollback available for an enforcement
rollout.

## Verification

Policy tests cover production/development behavior, preserved desktop/style/network
allowances and both reporting transports. Collector tests cover privacy filtering,
bounded sampling, untrusted formats, rejected requests and input limits.

```sh
pnpm -F @campsite/web exec vitest run config/content-security-policy.test.ts \
  utils/__tests__/cspReports.test.ts utils/__tests__/cspReportHandler.test.ts
```

✅ Thirteen CSP-specific regressions passed. The full JavaScript workspace passed
404 tests with no skips across nine uncached Turbo tasks, run serially. Web lint
and types passed. The production build and isolated Chromium smoke check passed: a
real static app document emitted the candidate; inline scripts, eval and inline
handlers remained executable while the browser delivered all three violation
categories to the actual Next.js route. HTTP checks confirmed both report formats,
405/415/400 rejection and the enforced 413 body limit. The synthetic document query
marker did not reach diagnostics.

Run that production/browser check with the project's existing Chromium installation:

```sh
mise exec -- node script/test-csp.mjs
```

It builds with a restricted environment, starts an owned loopback Next.js server,
uses an isolated headless browser with external requests blocked, and removes its
own temporary build directory. It needs no Rails database or authenticated session.

🟡 No live deployment was performed. Authenticated calls/desktop compatibility and
enforcement remain unverified, tracked as `campsite-ajx2`.

References: [Next.js Pages Router CSP](https://nextjs.org/docs/pages/guides/content-security-policy),
[MDN CSP rollout](https://developer.mozilla.org/en-US/docs/Web/Security/Practical_implementation_guides/CSP),
[Reporting API endpoints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Reporting-Endpoints).
