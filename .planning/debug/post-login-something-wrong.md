---
status: verifying
trigger: "i logged in, now it says something went wrong"
created: 2026-09-04
updated: 2026-09-04T11:02:55Z
---

## Symptoms

- Expected: after successful authentication, Campsite loads the authenticated organization home and remains signed in.
- Actual: authentication succeeds, then the destination UI displays `Something went wrong`.
- Errors: only the generic user-facing message has been reported so far.
- Timeline: observed immediately after retrying the 2026-09-04 homelab release and clearing the earlier stale TLS error page.
- Reproduction: sign in through `https://auth.camp.home/sign-in` and follow the post-login redirect.

## Current Focus

- bug_class: heisenbug-mandelbug (physical iPhone/WebKit-only client startup failure; server, redirect, asset, and desktop paths are healthy).
- hypothesis: revision `cc519b2` fixes the reproduced immutable-WebRTC crash but the physical iPhone still encounters a separate client startup or renderer failure before `AuthProvider`.
- test: capture the exact on-device error surface or the first remote WebKit console exception for the current page.
- expecting: evidence distinguishes a browser renderer/load failure from Campsite's React error boundary and identifies the next falsifiable source path.
- next_action: obtain an exact screenshot; alternatively connect/trust the iPhone and enable Web Inspector so the first exception can be captured without credentials or browsing state.

## Evidence

- timestamp: 2026-09-04
  observation: User reports successful login followed by a generic `Something went wrong` page; this proves TLS and credential submission now complete and moves the failure boundary into the authenticated application path.
- timestamp: 2026-09-04
  observation: Repository HEAD is `main` at `be9c575`; the worktree has pre-existing Beads changes and two untracked debug sessions. No source or deployment mutation has been made during this investigation.
- timestamp: 2026-09-04
  checked: semantic debug knowledge-base recall and durable fallback
  found: `mempalace` is unavailable and `.planning/debug/knowledge-base.md` does not exist.
  implication: no prior resolution is available as a hypothesis candidate; this investigation proceeds from direct observations.
- timestamp: 2026-09-04
  checked: related `auth-camp-home-cert-date` debug session
  found: after the earlier pre-HTTP `NET::ERR_CERT_DATE_INVALID` report, a fresh isolated tab in the same running Brave process loaded `https://auth.camp.home/sign-in`; the prior error document was stale and the TLS session has not identified an application defect.
  implication: the reported successful sign-in establishes a later failure boundary in the authenticated web/API path; certificate diagnosis must remain separate unless live evidence reconnects them.
- timestamp: 2026-09-04
  checked: source-controlled web/API deployment configuration and active Bead `campsite-vgy`
  found: `campsite-web-home-staging` and `campsite-api-staging` are both configured on Odin (`192.168.10.7`) as SSH user `debian`; the web build points to `https://api.camp.home` and `https://auth.camp.home`. The active Bead records a previously observed iPhone Chrome flow where auth accepted the session but `/v1/users/me` was anonymous on the API subdomain, while desktop succeeded.
  implication: web and API logs from the same Odin host can distinguish server-render failure from the known cross-subdomain session candidate. The Bead is a hypothesis candidate, not confirmation for this user/device.
- timestamp: 2026-09-04T02:49:01Z
  checked: live Odin container inventory and exact error-string search
  found: both `campsite-web-home-staging` and `campsite-api-staging` run deployed image `be9c575a0d0a8c9575621435d46db57eaecf1b17` and have been up for two hours. The exact text `Something went wrong.` is rendered by `apps/web/app/global-error.tsx`; other source hits are contextual component errors with different messages.
  implication: a report matching the period-bearing string is evidence of a Next global error boundary, so server/client runtime exception evidence is now the leading code candidate; deployment revision mismatch is not supported.
- timestamp: 2026-09-04T02:49:01Z
  checked: Brave CDP safety prerequisites
  found: port 9223 belongs to the user's running Brave profile. A task-specific agent-browser session ID was derived, but no pre-bound task target was supplied; enumerating user tabs would expose unrelated URLs/titles and is not permitted.
  implication: do not attach to or infer a browser tab. Live log and source evidence can proceed without browser interaction; a user-designated task tab would be required for client console/network evidence.
- timestamp: 2026-09-04T02:50:00Z
  checked: complete Next global-error source and redacted Odin runtime state/logs
  found: `global-error.tsx` captures only App Router routes (currently `app/api/*`), so it cannot itself explain the legacy web route. Both deployed containers have restart count zero. The web container produced no exception/error line in the report window. One sign-in flow proceeded to `/v1/users/me` and related bootstrap requests, all 200; the separately observed post-login sign-in recorded `signed_in=true` but made no following `/v1/users/me` request in the same window.
  implication: a Rails 5xx, container restart, or the known API-anonymous session mismatch does not explain the no-bootstrap flow. Investigation shifts to the legacy Pages Router/client initialization immediately after the Rails redirect.
- timestamp: 2026-09-04T02:51:00Z
  checked: legacy web error/startup module inventory and proxy-log capability
  found: the private web app uses the legacy Pages Router (`pages/_app.tsx`, `_error.tsx`, and `index.tsx`) plus `AuthProvider`/`useGetCurrentUser`; the specific legacy fallback and startup implementations remain to be read. Heimdall lacks `jq`, and emitting raw Caddy JSON could expose cookie-bearing headers.
  implication: proxy access logs are intentionally not inspected without a safe server-side redaction path. The existing Odin timeline is retained; source tracing is the next safe discriminating test.
- timestamp: 2026-09-04T02:52:00Z
  checked: complete legacy error/root/auth bootstrap source
  found: `pages/_error.tsx` renders `pages/500.tsx`, which uses `FullPageError`'s default title `Something went wrong`. After Rails redirects to `/`, `pages/index.tsx` server-side fetches organization memberships with forwarded request cookies; only authentication and not-found errors are handled, while any other error is rethrown into that error page. Client `AuthProvider` normally starts `/v1/users/me`, but the reported sign-in flow did not reach it.
  implication: a failing server-side organization-memberships call exactly accounts for the user-visible page and the absent browser API bootstrap. This is now a falsifiable leading hypothesis rather than a generic client-error theory.
- timestamp: 2026-09-04T02:53:00Z
  checked: server-side cookie/API configuration and a bounded organization-membership log correlation
  found: SSR forwards only the encoded `_campsite_api_session` cookie plus an SSR-secret header; the API client targets the configured Rails API with JSON credentials. During 02:42:30–02:44:30 UTC, three organization-memberships requests completed 200; the first redaction omitted timestamps but exposed no request data.
  implication: the index-page server-call hypothesis is no longer favored. A timestamp-aligned repetition and broader failure count will determine whether to eliminate it or trace a downstream organization-route error.
- timestamp: 2026-09-04T02:54:00Z
  checked: timestamp-aligned organization-membership correlation, aggregate API status count, and deployed web-image diff
  found: the exact post-login flow made `organization_memberships` at `02:42:44.660Z` and completed 200 at `02:42:44.700Z`; two subsequent calls also completed 200. The same 02:42:30–02:44:30 window contains 21 API 4xx/5xx completions whose paths have not been exposed. Deployed commit `be9c575` changes only production image tool removal, not application login or request logic.
  implication: the index `getServerSideProps` failure is contradicted for the reported sign-in and will be eliminated if route-family redaction shows those non-2xx requests are downstream. The deployment change is an environment candidate but currently lacks a mechanism linking it specifically to post-login navigation.
- timestamp: 2026-09-04T02:55:00Z
  checked: server-side category/status redaction and complete post-redirect page code
  found: all 21 non-2xx completions were 404, with none mapped to the organization, organization-memberships, current-user, sign-in, or health families. The root-page membership call at the precise post-login timestamp completed 200. The organization redirect selects `/[org]/home` for mobile and `/[org]/posts` for desktop; those routes use `AuthAppProviders` and client queries.
  implication: no observed API error accounts for the generic page, so the index-request hypothesis is eliminated. The remaining evidence points to a client-only throw or an unclassified API route; safely identifying the device path and browser exception is the highest-value next discriminator.
- timestamp: 2026-09-04T02:56:00Z
  checked: timestamped safe-prefix categorization and mobile-diagnostic guard
  found: the 21 non-2xx completions are 404s only: one uncorrelated request at `02:42:30Z` and 20 requests beginning at `02:43:37Z`; none has a `/v1`, `/api`, `/_next`, assets, Rails, favicon, well-known, or cable prefix. The successful `02:42:44Z` sign-in's `mobile_session_diagnostic` is emitted only for iPhone, iPad, or CriOS user agents; its subsequent expected `/v1/users/me` diagnostic is absent.
  implication: the reported authentication path is an iPhone Chrome flow. The unclassified 404s have no demonstrated causal link and do not explain a missing current-user bootstrap. Root cause is not confirmed: client-side exception/route evidence is required before a safe fix can be proposed.
- timestamp: 2026-09-04T03:00:26Z
  checked: investigation continuation scope
  found: manager-directed continuation defers device reproduction and explicitly authorizes safe route-independent source and runtime evidence. The worktree remains dirty only with pre-existing Beads records and debug-session files; no application/deployment mutation has occurred.
  implication: tracing the mobile boot/provider order and redacted exact-time deployed logs is the next falsifiable test; browser-tab enumeration and sensitive browser state remain out of scope.
- timestamp: 2026-09-04T03:02:40Z
  checked: complete legacy redirect, mobile-home route, authentication bootstrap, and direct mobile child implementations
  found: the iPhone redirect is intentionally `/<org>/home`. `AuthProvider` calls `useGetCurrentUser` before it can render `AppLayout` or the mobile-home content, and that query requests `/v1/users/me` with `Intl.DateTimeFormat().resolvedOptions().timeZone`. The home route has no server data fetcher; it is wrapped in `AuthAppProviders`, whose pre-auth stack is LazyMotion → History → Hotkeys → query normalization → QueryClient → scope → theme/meta → 100ms room provider/state subscriber.
  implication: an exception in mobile-home content cannot explain a missing current-user request. The next source branch is the pre-auth provider stack; otherwise, the failure must happen before React mounts (for example, route/asset loading) and requires client-side evidence.
- timestamp: 2026-09-04T03:04:08Z
  checked: pre-auth History/query-normalizer/scope/theme/meta startup code and live credential-free CORS preflight
  found: History guards `window` on SSR; query normalization defers subscription to an effect; scope uses browser APIs only in an effect; no unsafe mobile-only browser access was found in those paths. A live `OPTIONS /v1/users/me` from `Origin: https://camp.home` returned 200 with `Access-Control-Allow-Origin: https://camp.home`, `Access-Control-Allow-Credentials: true`, and `Access-Control-Allow-Headers: content-type`.
  implication: normal Campsite-web-to-API CORS negotiation is directly contradicted as the cause. The pre-auth stack remains only partially examined because the 100ms subscriber path is unresolved; exact redacted deployed exception aggregates are the next strongest discriminator.
- timestamp: 2026-09-04T03:05:54Z
  checked: remaining pre-auth 100ms subscriber and application startup hooks; live response policy and timestamp-bounded, redacted container-log aggregates
  found: the 100ms subscriber only writes its already-provided room state in an effect; `_app` storage cleanup also runs in an effect. The live `GET /v1/users/me` response policy from `Origin: https://camp.home` allows that origin and credentials, and the live `camp.home` CSP explicitly includes `https://api.camp.home`. From 02:42–02:45 UTC, web/API logs had no 5xx, Next error, Rails exception, TypeError, ReferenceError, SyntaxError, fatal, or panic aggregate; each had one unclassified `error` text mention, without a matching exception marker.
  implication: CORS, CSP, server rendering, and the known pre-auth providers lack a demonstrated mechanism. A failure before the current-user request remains possible only in route/asset loading or a device-local client bootstrap path; the asset manifest is the last safe route-independent discriminator before client evidence is required.
- timestamp: 2026-09-04T03:07:00Z
  checked: validity of the redacted container-log aggregation
  found: the assumed Docker container name `campsite-web-home-staging` now returns `No such container` on Odin. Because the prior aggregation piped Docker stderr into `awk`, its one `error` count was Docker's target-resolution message, not application output; its zero-exception conclusion is invalid.
  implication: runtime log evidence at 03:05:54Z is revoked pending exact current-container discovery. The directly observed CORS and CSP results remain valid because they came from live HTTPS responses, not Docker logs.
- timestamp: 2026-09-04T03:07:41Z
  checked: current Odin Docker inventory
  found: the exact web and API service containers are `campsite-web-home-staging-web-be9c575a0d0a8c9575621435d46db57eaecf1b17` and `campsite-api-staging-web-be9c575a0d0a8c9575621435d46db57eaecf1b17`. Both run deployed image tag `be9c575a0d0a8c9575621435d46db57eaecf1b17` and have been up about three hours.
  implication: target identity is now verified. Subsequent build-manifest and log tests can safely interrogate the actual deployed web/API processes; no image-revision mismatch is observed.
- timestamp: 2026-09-04T03:09:54Z
  checked: deployed mobile-home build assets and exact current web/API log aggregates
  found: the web container's build ID is `BbWil7Ys6wZEjPrM0LLDY`; all 16 manifest-listed `/[org]/home` JavaScript/CSS assets and `/_buildManifest.js` returned 200 without credentials. The exact web container emitted no records in the post-login window; the exact API container emitted 796 records with no `Exception`, JavaScript error, fatal/panic, or 5xx marker and 12 `/users/me` mentions, but the aggregate cannot associate any request with the affected iPhone without exposing request data.
  implication: missing deployed mobile-route chunks are eliminated. The API has no observed server-failure signature but its aggregate cannot prove the reported device's `/users/me` outcome; a user-designated client observation is now indispensable.
- timestamp: 2026-09-04T03:31:27Z
  checked: user-authorized exact Brave task-page evidence for `https://camp.home/<org>/posts`
  found: the page is fully rendered and authenticated. `/v1/users/me`, organization membership/bootstrap, and Pusher authentication completed successfully (200/304); no Next error boundary or JavaScript exception was observed. The only reported client noise was fallback-avatar 404s and a transient Pusher-close warning.
  implication: the reported Mac Brave post-login failure is not currently reproducible on the deployed application, and a general post-login outage or a Mac `/[org]/posts` bootstrap exception is contradicted. The fallback-avatar and transient Pusher observations do not account for a rendered page with no error boundary. This evidence does not establish the physical iPhone Chrome/WebKit `/[org]/home` outcome, so no code or deployment mutation is warranted.
- timestamp: 2026-09-04T07:34:01Z
  checked: bounded redacted iPhone watcher evidence plus complete deployed sign-in/redirect/bootstrap source
  found: the final iPhone `POST auth.camp.home/sign-in` had one session cookie and `signed_in=true`; no `api.camp.home/v1/users/me` diagnostic occurred in the following approximately two minutes. On a successful non-OTP sign-in, `Users::SessionsController#create` redirects to `Campsite.base_app_url` (`https://camp.home/` in the deployed configuration). The root page server-fetches organization memberships and redirects mobile user agents to `/<org>/home`; that page has no server fetcher and installs `AuthAppProviders`, where `AuthProvider` calls `useGetCurrentUser` first.
  implication: authentication succeeded, but the observation proves only that the normal current-user bootstrap did not commit. It rules out neither a failed/abandoned top-level redirect nor an SSR document error before the home route, and it cannot establish a cross-subdomain cookie/API-response failure because no `/v1/users/me` request was made. The strongest safe discriminator is a same-attempt redacted redirect-chain status/path-class capture, not cookie inspection or a source/deployment change.
- timestamp: 2026-09-04T07:28:05Z
  checked: bounded redacted Kamal-proxy route-chain evidence for the same physical iPhone attempt
  found: the `camp.home` root document redirected (307); the organization-home document returned HTML 200; the matching manifest returned 200; all 21 initial Next JavaScript chunks, five stylesheets, and the font returned 200. The Rails SSR organization-memberships request returned 200 at the same timestamp. No `/v1/users/me` diagnostic or monitoring-tunnel request followed. The proxy classified the browser as iOS 26.6.1 CriOS 152.0.7977.64. The homelab web container has no public Sentry DSN, so missing browser telemetry is expected rather than evidence of a telemetry outage.
  implication: failed navigation, SSR-document failure, missing initial assets, and the old iOS syntax-baseline hypothesis are eliminated as leading explanations. The remaining boundary is client startup before `AuthProvider`; an uncaught pre-Sentry exception or a browser process-level abort remains plausible but unproven.
- timestamp: 2026-09-04T07:28:00Z
  checked: local Playwright WebKit probe feasibility
  found: the WebKit browser binary is absent. A `pnpm exec` installation attempt was immediately terminated; subsequent Git status confirmed no dependency or application-source changes.
  implication: no synthetic WebKit result exists and no project state was changed. Physical-iPhone task-page-only console/inspector evidence remains the next safe discriminator.
- timestamp: 2026-09-04T07:56:42Z
  checked: focused browser-storage fault injection against the pre-auth startup hooks
  found: before the fix, a `SecurityError` from the `window.localStorage` getter crashed `useStoredState` synchronously during render, and the same denial crashed the legacy empty-draft cleanup effect. This exactly reproduces a failure before `AuthProvider` and `/v1/users/me`. Revision `5b62b88` resolves storage through a guarded accessor, makes cleanup best-effort, and prevents rejected storage writes/removals from escaping.
  implication: the source now has a demonstrated mechanism matching the live iPhone boundary and regression coverage for property denial, quota rejection, and operation denial. Physical-iPhone verification after deployment remains required.
- timestamp: 2026-09-04T07:56:42Z
  checked: local verification for revision `5b62b88`
  found: focused storage tests pass 7/7; the complete web suite passes 43 files and 169 tests; changed-file ESLint and Prettier pass; the Next 16 production build completes; staged Gitleaks scans 4.31 KB with no leaks.
  implication: the fix is locally release-ready. Existing non-fatal build warnings are unchanged and do not block this maintenance patch.
- timestamp: 2026-09-04T08:17:16Z
  checked: exact homelab web deployment and post-deploy service health
  found: Kamal deployed only `campsite-web-home-staging` at exact revision `5b62b88fe6114ff79656e902e930aa4fe3be17ab`; the public build ID matches, image digest is `sha256:69062262a1b142b19798f5324fbf38dccddad35d6496085223fa02fffe43d2a2`, restart count is zero, and post-deploy web logs contain no fatal, error, or exception markers. Public API `/up` returns `OK`; API, worker, and export containers remain running with zero restarts; Sidekiq has three fresh process heartbeats (maximum age six seconds), zero busy, and zero enqueued.
  implication: code rollout and server health are proven without widening deployment scope. The previous `be9c575` web image remains the rollback revision.
- timestamp: 2026-09-04T08:17:16Z
  checked: five-minute redacted physical-iPhone acceptance watcher after deployment
  found: no iPhone/CriOS sign-in or `/v1/users/me` event reached the API during the bounded window.
  implication: this is a verified wait, not a failed authentication result. One user-triggered physical-iPhone retry is still required to close acceptance.
- timestamp: 2026-09-04T08:25:06Z
  checked: isolated live-bundle fault injection with and without agent-browser WebRTC containment
  found: without WebRTC containment, both a baseline browser and a browser whose storage writes/removals throw reached `/v1/users/me` (OPTIONS 200 and GET 200) and redirected normally to sign-in, proving deployed `5b62b88` tolerates the realistic operation-denial case. With the browser tool's deliberate WebRTC lockdown enabled, the 100ms dependency's bundled `webrtc-adapter@8.2.3` threw `TypeError: Cannot define property ontrack, object is not extensible` during module evaluation before `/v1/users/me`. The same test without containment did not throw.
  implication: the WebRTC exception is a harness-induced reproduction and not evidence that the iPhone has the same object model. It does expose another pre-auth failure candidate because `HMSRoomProvider` is imported before `AuthProvider`, but changing its loading order without physical evidence would be speculative. The storage fix is proven for denied operations but is not yet proven to resolve the reported device failure.
- timestamp: 2026-09-04T08:46:18Z
  checked: physical-iPhone reload against deployed revision `5b62b88`
  found: the user reopened the browser with an existing iPhone login and the application still failed. The matching proxy trace loaded organization-home HTML, manifest, service worker, sound, and all initial Next assets with 200 responses twice, but the API emitted zero mobile-session diagnostics and no `/v1/users/me` request.
  implication: the storage patch is retained as valid hardening but eliminated as the complete remedy. The failure boundary remains pre-auth client startup, making the eagerly evaluated optional 100ms/WebRTC SDK the strongest demonstrated remaining candidate.
- timestamp: 2026-09-04T08:46:18Z
  checked: lazy optional-media implementation and local verification
  found: `AuthProvider` now gates a dynamically imported 100ms room provider; failed SDK import or module evaluation is captured and falls through to the application without call support. Focused regressions pass 4/4 across lazy-media and storage behavior; the full web suite passes 44 files and 171 tests; changed-file ESLint, Prettier, `git diff --check`, TypeScript, and the Next production build pass.
  implication: the web-only patch is locally release-ready. Exact homelab deployment and physical-iPhone acceptance remain outstanding; root cause is not confirmed until the device succeeds.
- timestamp: 2026-09-04T10:06:55Z
  checked: two staged lazy-loading deployments and repeated synthetic WebRTC containment
  found: revisions `32d5794` and `74d576c` remained healthy but still crashed before `/v1/users/me` with `Cannot define property ontrack, object is not extensible`. Static 100ms imports exist throughout the initial route graph, and `AuthProvider` could also mount children before the current-user query settled. Revision `3e2cb9a` now gates children on current-user loading, with a direct regression test.
  implication: provider-level lazy loading alone cannot prevent the dependency module from evaluating. The exact failing operation is the compatibility layer's unconditional mutation of an immutable browser host prototype.
- timestamp: 2026-09-04T10:06:55Z
  checked: patched dependency regression, full validation, exact deployment, and repeated synthetic containment
  found: revision `cc519b237a4f0f7dae8a94c3f73776883a769d18` patches both source and compiled entrypoints of `webrtc-adapter@8.2.3` to skip shimming when `RTCPeerConnection.prototype` is non-extensible. The direct public-SDK regression passes; frozen offline pnpm install reproduces; full web suite passes 46 files/173 tests; lint, format, TypeScript, production build, diff check, and staged Gitleaks pass. Homelab web reports the exact build ID and image digest `sha256:a0f2ffd803a32492687659866d26fb067c8ba01122fcafcc4170776cd3d8a54b`, with zero restarts/errors and API `/up` `OK`. Under the same WebRTC containment that crashed all prior revisions, the live app now makes `/v1/users/me` OPTIONS/GET 200, has zero client errors, and redirects normally to sign-in.
  implication: the previously reproduced pre-auth crash is fixed in the exact live revision. Physical-iPhone rendering remains the final acceptance boundary before confirming this mechanism as the device root cause.
- timestamp: 2026-09-04T11:02:55Z
  checked: physical-iPhone acceptance against exact live revision `cc519b2`
  found: acceptance failed again. The phone fetched organization-home HTML 200, manifest 200, font, CSS, and every initial JavaScript chunk 200 at `11:00:59Z`; a second reload fetched HTML and manifest again at `11:01:11Z`. No mobile `/v1/users/me` event followed. API had no 5xx; the web container remained running with zero restarts or error markers. Xcode sees zero physical iOS devices on this Mac, so remote WebKit inspection is unavailable.
  implication: the WebRTC patch is valid but not the complete physical-device fix. Network, deployment, SSR, and initial assets remain eliminated; the next required discriminator is the exact on-device error surface or first client exception.

## Eliminated

- hypothesis: `pages/index.tsx` throws from its server-side organization-memberships request after the reported sign-in.
  evidence: the request starting at `2026-09-04T02:42:44.660Z`, immediately after the successful sign-in, completed 200 in 39ms; none of the report-window 404s belonged to the organization-memberships family.
  timestamp: 2026-09-04T02:55:00Z
- hypothesis: the deployed `/[org]/home` JavaScript/CSS assets or Next build manifest are missing or non-200, preventing the iPhone from mounting React before `/v1/users/me`.
  evidence: build ID `BbWil7Ys6wZEjPrM0LLDY`, all 16 route-manifest assets, and the matching `_buildManifest.js` returned 200 from `https://camp.home` without credentials.
  timestamp: 2026-09-04T03:09:54Z
- hypothesis: browser CORS or the web Content Security Policy blocks the first cross-origin current-user request from `https://camp.home` to `https://api.camp.home`.
  evidence: live preflight and unauthenticated `GET` responses explicitly allow `https://camp.home` with credentials, and the live web CSP includes `https://api.camp.home` in `connect-src`.
  timestamp: 2026-09-04T03:09:54Z
- hypothesis: the current deployed revision has a general Mac Brave post-login failure on `/[org]/posts`.
  evidence: the user-authorized exact Brave task page at `https://camp.home/<org>/posts` is authenticated and fully rendered; current-user, organization bootstrap, and Pusher-auth requests succeeded with no Next error boundary or JavaScript exception.
  timestamp: 2026-09-04T03:31:27Z
- hypothesis: the affected iPhone failed or abandoned the post-auth `auth.camp.home` -> `camp.home` navigation, failed the organization-home SSR document, or could not fetch initial Next assets.
  evidence: the same-attempt route chain reached root 307, organization-home HTML 200, organization-memberships 200, manifest 200, all 21 initial JavaScript chunks 200, five stylesheets 200, and a font 200.
  timestamp: 2026-09-04T07:28:05Z

## Resolution

- root_cause: unresolved for the physical iPhone. An immutable-WebRTC module crash was reproduced and fixed, but device acceptance still fails before `/v1/users/me`.
- fix: retain storage hardening, defer optional media initialization, gate authenticated providers until current-user loading settles, and skip legacy WebRTC shims when the browser's peer-connection prototype is immutable.
- verification: Full local gates, reproducible patched install, exact web-only deployment, service health, and the formerly failing synthetic containment path pass. Physical-iPhone authentication/rendering against `cc519b2` fails before `/v1/users/me`.
- files_changed: prior storage files; auth/media provider files and tests; `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `patches/webrtc-adapter@8.2.3.patch`, and `apps/web/utils/webrtcAdapterCompatibility.test.ts`.
