---
status: awaiting_human_verify
trigger: "Brave displays Your connection is not private for auth.camp.home with NET::ERR_CERT_DATE_INVALID and HSTS prevents proceeding."
created: 2026-09-04
updated: 2026-09-04T02:15:15Z
---

## Symptoms

- Expected: `https://auth.camp.home/sign-in` presents the Campsite sign-in page on the client device.
- Actual: Brave blocks navigation before HTTP with an HSTS TLS privacy error.
- Errors: `NET::ERR_CERT_DATE_INVALID`.
- Timeline: observed immediately after the 2026-09-04 Campsite maintenance deployment during physical-device authentication acceptance.
- Reproduction: navigate Brave to `https://auth.camp.home` on the affected client.

## Current Focus

- bug_class: bohrbug (provisionally; the reported TLS error occurs before HTTP and is repeatable for the same hostname, chain, and clock).
- known_pattern_candidate: none (no local debug knowledge base exists).
- hypothesis: the screenshot captured a stale Brave certificate-error document or a transient certificate state that is no longer observable; the same running Brave process now accepts the live endpoint in a fresh isolated context.
- candidate_causes:
  - environment: the affected device clock is before `2026-09-03T19:55:47Z` or after `2026-09-04T07:55:47Z`.
  - config: the affected device trusts an obsolete local Caddy root rather than the active 2026 root.
  - code: none; the failure is proved to occur before the request reaches Caddy's HTTP proxy or the Campsite application.
- and_gate: no for the observed `NET::ERR_CERT_DATE_INVALID`: an out-of-window device clock alone produces that error, while a stale root alone produces an authority error. A stale root may be a second, independent follow-on condition for successful connection after time is corrected, so it remains unconfirmed rather than discarded wholesale.
- test: have the user reload the exact stale error tab or open the URL in a fresh normal tab, then perform the original physical iPhone Chrome login acceptance.
- expecting: the Mac sign-in page loads as it did in the isolated Brave context; the iPhone either completes authentication or supplies device-specific TLS/auth evidence.
- next_action: wait for user confirmation after reloading/opening a fresh Mac tab, then run the required physical iPhone Chrome sign-in and authenticated reload check; do not change Caddy, HSTS, certificates, or trust settings, or browser data.

## Evidence

- timestamp: 2026-09-04
  observation: User screenshot proves Brave rejects `auth.camp.home` at TLS with `NET::ERR_CERT_DATE_INVALID`; HSTS prevents bypass, so application login and cookie behavior are not reached.
- timestamp: 2026-09-04
  checked: repository deployment configuration, debug knowledge-base fallback, and active Bead `campsite-vgy`
  found: `auth.camp.home` is a Rails/Kamal proxy host on Odin, while the documented private HTTPS ingress is Heimdall; no project debug knowledge base exists. The active Bead confirms prior HTTP and session checks passed, but this browser failure occurs earlier during TLS validation.
  implication: certificate delivery on the Heimdall ingress and clock consistency must be tested before considering the deployed Rails or cookie logic.
- timestamp: 2026-09-04T01:56:54Z
  checked: local UTC clock, DNS answer, and TLS leaf presented for `auth.camp.home` with SNI
  found: local UTC was `2026-09-04T01:56:54Z`; DNS resolved `auth.camp.home` to `192.168.10.8` (Heimdall); the presented leaf has the critical SAN `DNS:auth.camp.home`, issuer `Caddy Local Authority - ECC Intermediate`, fingerprint `9B:C4:E7:2C:84:10:09:55:1F:F1:5E:D1:31:8C:0B:12:B7:26:8D:A5:9A:28:8F:9B:6C:84:05:96:C7:74:0F:29`, `notBefore=2026-09-03T19:55:47Z`, and `notAfter=2026-09-04T07:55:47Z`.
  implication: at the probe time, the normal resolver path served a hostname-matching leaf valid for another 5 hours 59 minutes; an actively expired or not-yet-valid certificate on that path is not supported.
- timestamp: 2026-09-04
  checked: spectrum-based fault-localization eligibility
  found: no automated test currently fails with the TLS/browser symptom, so no failing-versus-passing coverage spectrum exists.
  implication: SBFL is skipped; direct live chain and clock differential checks are the appropriate Bohrbug route.
- timestamp: 2026-09-04
  checked: direct TLS connection to `192.168.10.8:443` with SNI `auth.camp.home`
  found: the direct connection served the same serial, validity interval, SAN, and SHA-256 fingerprint as the hostname-resolved path.
  implication: the authoritative private DNS answer is not masking a different endpoint or stale leaf certificate.
- timestamp: 2026-09-04
  checked: read-only SSH access using the configured `heimdall` host alias
  found: the alias resolves to user `prakash` on `heimdall:22`, but public-key authentication was denied before any remote command ran.
  implication: no inference about Heimdall's clock, Caddy process, or logs can be made yet; inspect source-controlled inventory before attempting a different identity.
- timestamp: 2026-09-04
  checked: source-controlled homelab inventory and the complete TLS chain presented by `auth.camp.home`
  found: the homelab fleet inventory declares `heimdall` as `debian` at `192.168.10.8`; the chain is a leaf issued by `Caddy Local Authority - ECC Intermediate` plus that intermediate issued by `Caddy Local Authority - 2026 ECC Root`.
  implication: `debian@192.168.10.8` is an explicit host mapping rather than a guessed alternative identity, and the local CA lifecycle is a distinct hypothesis from leaf validity.
- timestamp: 2026-09-04T01:59:23Z
  checked: authorized read-only Heimdall clock, NTP state, and Caddy container status
  found: Heimdall reported `2026-09-04T01:59:23Z`, `NTPSynchronized=yes`, and timezone `Asia/Kathmandu`, aligned with the local UTC clock. The `home-proxy` Caddy container is running (`Up 4 days`) and reports Caddy `v2.11.4`.
  implication: neither a gateway clock error nor a Caddy restart during the maintenance deployment explains an active date-invalid leaf.
- timestamp: 2026-09-04
  checked: Heimdall Caddy lifecycle log for the Campsite certificate group
  found: Caddy queued `auth.camp.home` for renewal at four hours remaining, acquired the lock, renewed it successfully with issuer `local`, and replaced the cache entry with expiration `1788508548`; that timestamp equals the currently served leaf's `notAfter=2026-09-04T07:55:47Z` (within one second).
  implication: the actively served certificate was successfully issued and cached by the live gateway; a Caddy renewal failure or stale in-memory certificate is not supported.
- timestamp: 2026-09-04
  checked: live Caddy local root metadata and active Caddy route on Heimdall
  found: the local root is `Caddy Local Authority - 2026 ECC Root`, valid `2026-08-23T13:29:03Z` through `2036-07-01T13:29:03Z`, with SHA-256 fingerprint `62:4D:24:D1:E0:29:F2:27:F9:87:C8:30:4B:17:F3:DB:1F:C3:B5:87:2F:4F:FF:E3:1F:C9:53:AD:15:0F:B5:F0`. `home-proxy` has restart count `0` since `2026-08-30T18:45:25Z`; its active route explicitly includes `https://auth.camp.home` under `tls internal` and proxies to Odin on port 80.
  implication: the trusted local CA is not expired and Caddy did not restart or adopt a different route during the maintenance deployment.
- timestamp: 2026-09-04
  checked: complete live `auth.camp.home` chain verification against the live Caddy local root
  found: OpenSSL verified the root, intermediate, and leaf (`Verify return code: 0 (ok)`) over TLS 1.3 while connecting with SNI `auth.camp.home`.
  implication: the present gateway chain is trusted, time-valid, and complete when assessed against the authoritative local root.
- timestamp: 2026-09-04T02:17:01Z
  checked: screenshot timestamp, current Mac clock, macOS System keychain Caddy roots, and trust metadata
  found: the screenshot filename is timestamped about 07:38 NPT and the Mac reported 08:02 NPT, both inside the leaf validity window. The System keychain contains the 2023 root and the matching 2026 root fingerprint `62:4D:24:D1:E0:29:F2:27:F9:87:C8:30:4B:17:F3:DB:1F:C3:B5:87:2F:4F:FF:E3:1F:C9:53:AD:15:0F:B5:F0`.
  implication: an incorrect Mac clock is not supported for this screenshot, and the active root is installed locally.
- timestamp: 2026-09-04
  checked: a dedicated isolated background tab in the same running Brave process, without navigating or reloading the user's error tab
  found: `https://auth.camp.home/sign-in` loaded successfully as `Sign in - Campsite`; the task tab was then closed. The original tab remained at `chrome-error://chromewebdata/` and retained no network request or certificate chain for retrospective inspection.
  implication: Brave's current network process accepts the live certificate and reaches Rails. The existing error document is stale; the exact certificate or transient state that produced the earlier screenshot is no longer recoverable.
- timestamp: 2026-09-04
  checked: source-controlled Caddy trust lifecycle records and Chromium certificate-error definitions
  found: the Heimdall Caddyfile documents that `tls internal` requires every client device to trust Caddy's current root and that losing the `caddy-data` volume reissues a new root; the estate inventory treats `/data/caddy/pki/authorities/local/root.crt` as authoritative. Chromium defines `NET::ERR_CERT_DATE_INVALID` specifically for a certificate that is not-yet-valid or expired according to the client clock, while an untrusted issuer maps to `NET::ERR_CERT_AUTHORITY_INVALID`.
  implication: a stale Caddy root remains a possible client-state fault only if the device reports the authority error or also has a separate date condition. The reported date error materially favors an out-of-window device clock; source and live records cannot inspect the affected device's time or installed root.
- timestamp: 2026-09-04T02:11:59Z
  checked: repeat SNI probe of `auth.camp.home`, private-DNS answer, Heimdall time/NTP, and documented Caddy data-volume lifecycle
  found: `auth.camp.home` still resolved to `192.168.10.8` and served the identical hostname-matching leaf fingerprint `9B:C4:E7:2C:84:10:09:55:1F:F1:5E:D1:31:8C:0B:12:B7:26:8D:A5:9A:28:8F:9B:6C:84:05:96:C7:74:0F:29`, valid through `2026-09-04T07:55:47Z`; both the investigator and Heimdall clocks read `2026-09-04T02:11:59Z`, and Heimdall remained NTP-synchronized with `home-proxy` running continuously. The documented `caddy-data` named volume is the sole local-CA store and is explicitly retained to prevent a root rotation.
  implication: the live endpoint has not changed since the original probe and has more than five hours remaining on its leaf. The first root-metadata command could not run OpenSSL inside the minimal Caddy container, so the active public root will be streamed read-only to local OpenSSL instead; this is an observation limitation, not certificate evidence.
- timestamp: 2026-09-04T02:12:00Z
  checked: active Caddy root streamed read-only from `home-proxy` and a fresh full-chain verification for `auth.camp.home`
  found: the active root is `Caddy Local Authority - 2026 ECC Root`, self-issued, valid `2026-08-23T13:29:03Z` through `2036-07-01T13:29:03Z`, SHA-256 `62:4D:24:D1:E0:29:F2:27:F9:87:C8:30:4B:17:F3:DB:1F:C3:B5:87:2F:4F:FF:E3:1F:C9:53:AD:15:0F:B5:F0`. A new SNI connection verified the leaf and intermediate against that root with `Verification: OK` and `Verify return code: 0 (ok)`.
  implication: the exact live issuer chain and root lifecycle are internally consistent. The active root is not near expiry; a device that only trusts an obsolete root would lack this trust anchor and should report an authority failure, not the observed date failure.

## Eliminated

- hypothesis: Heimdall is actively serving an expired, not-yet-valid, stale, or wrong-endpoint leaf certificate for `auth.camp.home`.
  evidence: DNS and direct-IP SNI probes served the same leaf, valid from `2026-09-03T19:55:47Z` through `2026-09-04T07:55:47Z`; live Caddy logs prove that exact leaf was successfully renewed and cached; its full chain validates against the live root.
  timestamp: 2026-09-04
- hypothesis: the Heimdall gateway clock or a deployment-time Caddy restart caused the date-invalid certificate.
  evidence: Heimdall NTP is synchronized and aligned to local UTC; `home-proxy` has restart count zero and has been continuously running since `2026-08-30T18:45:25Z`.
  timestamp: 2026-09-04
- hypothesis: the Mac currently has a clock or trust failure that prevents Brave from reaching `auth.camp.home`.
  evidence: the Mac clock is inside the live leaf window, the matching 2026 Caddy root is installed, and a fresh isolated tab in the same Brave process loaded the sign-in page successfully.
  timestamp: 2026-09-04
- hypothesis: an obsolete Caddy root on the affected device alone explains the observed `NET::ERR_CERT_DATE_INVALID`.
  evidence: the current leaf chains to the active, unexpired 2026 root and verifies successfully; the documented Caddy lifecycle requires that current root for `tls internal`, while Chromium maps a missing/untrusted issuer to `NET::ERR_CERT_AUTHORITY_INVALID`. The device may still hold an obsolete root, but that is not sufficient to cause the reported date-specific error.
  timestamp: 2026-09-04T02:12:00Z

## Resolution

- root_cause:
- fix:
- verification:
- files_changed:
