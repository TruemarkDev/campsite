# PostgreSQL search release — 2026-11-04

✅ API, worker, export worker and styled-text were deployed through Kamal to
Quill (`192.168.10.32`) as operator `prakash` from clean detached revision
`77a7bdc1874bbf40b0244ca83b0d3b446c100a4e`. This revision is pushed to Forgejo.
The web and sync containers were not redeployed. Two unrelated local frontend
edits were excluded. Tracking: `campsite-5nf`.

## Checkpoint and cutover

- pgBackRest incremental checkpoint: `20261031-194502F_20261104-043337I`.
  Backup completed successfully; a subsequent archive check verified WAL
  `00000024000000000000006E` reached the repository. This verifies the backup
  and archive operations; no restore rehearsal was performed during this release.
- API ingress entered maintenance through `kamal app maintenance`; both old
  worker roles stopped through `kamal app stop`. The scheduler remained disabled.
- The dedicated legacy search queue and Searchkick jobs in retry, scheduled,
  and dead sets were empty. No queues were cleared.
- New-image `kamal app exec 'bin/rails db:migrate search:rebuild'` applied the
  three search/index migrations through `20261104020000`, then backfilled
  777 posts, 69 notes and zero calls. `ANALYZE search_documents` completed.
- New workers started before the API deployment. Native `kamal app live`
  explicitly resumed API traffic after deployment; homepage and sign-in checks
  made during maintenance were repeated successfully after resume.
- Styled-text's deployed token initially differed from the API credential.
  The ignored operator profile was aligned to the existing API credential and
  the container recreated through Kamal. No credential values were recorded.
- No Elasticsearch service was started, restored or provisioned. External
  server/volume retirement was outside this release.

## Immutable images

Registry: `builder.home:5555/truemarkdev`. Each image tag equals the full release
revision above. Registry digests and running image IDs were checked separately.

| Service | Registry manifest digest | Running image ID |
| --- | --- | --- |
| API | `sha256:8796851cd3b526206d593671e88d02f8dc343d8af02c525113003cc812c1f1c2` | `sha256:03429fdfb2a56eb425fea997bd4974b5d7b36b9011a11909dfb35f99ca63e23e` |
| Worker and export | `sha256:d21ada5e5229b6cc0edc62aa6a85e9c63c75e31d65d064f26b87f37172363e9a` | `sha256:29832654e784981f6b54cedf7a4f248be007edf52903697f65c710a8eeaaf8c9` |
| Styled-text | `sha256:acb447fc32ec0a4e981cde6ce21573209c56d6c4fa003625c91072409f45ecf3` | `sha256:e3f5954b77e6bf4e562ba50cf7606705db60e622d2c8138a58d322f978ca84c1` |

## Verification

✅ Independent post-deploy checks passed:

- `script/check-campsite-search`: indexed/source counts agree for all three
  models; existing titled post and note are returned by native search.
- Production database identity is PostgreSQL `campsite_production`; the latest
  migration is `20261104020000`. All four optimization indexes exist and are
  valid. The running API connection pool is 10.
- Live post/note checks passed tenant isolation, author filters, available
  project filtering, and Pundit policy scope/show consistency for sampled
  existing resources. These checks made no canonical content changes.
- Both release Sidekiq processes registered; the legacy queue remained empty.
- The deployed API converted Markdown through the deployed styled-text service
  using its existing authenticated client credential.
- Verified private TLS: `https://api.camp.home/up`,
  `https://styled-text.camp.home/up`, `https://auth.camp.home/sign-in`, and
  `https://camp.home` all returned 200 after API resume.
- All four release containers reported zero restarts at the initial observation.
  Prior API/worker revision `91de4dfc92824547e503fe1294a2ba836161019f` containers
  were retained stopped.

Local source validation is recorded in the
[performance report](postgresql-performance-2026-11-04.md): 4,287 Rails tests,
14,041 assertions, zero failures/errors/skips; the subsequent SQL-literal change
passed focused tests. Relevant JavaScript tests and builds passed locally.

🟡 Authenticated browser search/edit/reload, private-resource UI scenarios,
comment/transcript search and mentions were not exercised against the live
browser. There are no live calls to test transcript search. Representative
production latency before/after comparison remains unmeasured; synthetic
measurements in the performance report are not production benchmarks.

## CI findings

❌ Forgejo API run 13 and frontend run 14 at the release revision failed.
The CA bootstrap correction passed on both runners; neither run reached its
application test gates:

- API task 325 failed `bundler-audit check --update`, reporting advisories for
  nine existing gems: addressable, crass, css_parser, loofah, nokogiri, rack,
  rails-html-sanitizer, ruby_llm and trilogy. Review applicability and stable
  patched versions under `campsite-8am`; no audit finding was suppressed.
- Frontend task 326 failed native `re2` installation because the runner lacked
  Python. The workflow follow-up adds `python3` to its system packages.
- The known four local Brakeman warnings remain documented in the source
  review; remote Brakeman was skipped after dependency-audit failure.

CI is not green. Successful live checks do not establish full browser acceptance
or resolution of dependency advisories.

## Rollback custody

The prior API and worker revision is
`91de4dfc92824547e503fe1294a2ba836161019f`; prior running image IDs were
`sha256:7407cd323623147431dcd0acfed61c6c12d69fc1276634cca48a9bc0d7ceaea1`
and `sha256:1b31725cdacdeeb03d396da66194309e9c411ff1d0df88738f0f7237db83a277`.
The additive search table/indexes can remain during code rollback.

The previous application depends on Elasticsearch. Do not restore that service
as an incidental rollback step. For a native-search regression, pause ingress
and workers, retain the checkpoint, and deploy a corrected PostgreSQL revision.
A legacy rollback or database restore requires a separate operator decision;
see the [search runbook](../deployment/postgresql-search.md).
