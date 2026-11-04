# PostgreSQL search migration

Source implementation: 2026-11-04. Tracking: `campsite-6qq`.
✅ Live PostgreSQL search cutover completed on 2026-11-04 at revision
`77a7bdc1874bbf40b0244ca83b0d3b446c100a4e`.
See the [release evidence](../reviews/postgresql-search-release-2026-11-04.md)
for verification and remaining acceptance gaps. External server retirement was
not part of this release and remains unverified.

The subsequent [security follow-up](../reviews/security-ci-follow-up-2026-11-04.md)
deployed API and workers at `039d0fe39642f892d73ce0203f12def4bb1c3448` and
verified the authenticated browser collaboration/search lifecycle.

Search documents are derived rows in the application's PostgreSQL database.
`Post`, `Note`, and `Call` save/delete callbacks maintain them transactionally.
Comments, recordings, taggings, and author/project renames refresh affected
resources. Bulk SQL writes bypass callbacks and require a rebuild afterward.
No search text is sent to an external search service. Existing policy scopes
continue to authorize results after candidate retrieval.

Generated `simple`-configuration vectors use GIN indexes for prefix queries.
Title matches and title phrases rank above body matches; creation time breaks
ties. Sparse queries use indexed title and deduplicated body-lexeme word similarity
as a typo fallback. See the [measured optimization report](../reviews/postgresql-performance-2026-11-04.md).
English stemming is not enabled. This keeps identifiers and multilingual
terms available but is a deliberate relevance change to evaluate in acceptance.
Highlights are bounded plain-text fragments escaped before fixed markup is added.
The existing API response shape remains unchanged.

## Local verification

Use the existing local PostgreSQL 18 service; Docker and Elasticsearch are not
required. `script/test-postgresql db:migrate` creates the derived table and indexes.
`script/test-postgresql search:rebuild` backfills existing canonical rows.
`script/test-postgresql test test/controllers/api/v1/search test/models/search_document_test.rb`
checks search behavior and update/rollback guarantees.

## Release procedure (operator-run)

1. Take the normal database rollback checkpoint and record the exact release revision.
2. Pause writers, workers, and the scheduler; old workers must not continue writing
   after the backfill. Keep the old release available for rollback.
3. Run the additive database migration from the new revision. `pg_trgm` extension
   creation requires the appropriate database privilege; provision it with the
   database owner first if the application role cannot create trusted extensions.
4. Run `bin/rails search:rebuild` using the new code against the intended production
   database. This task is repeatable and locks each source row while snapshotting it.
   Run `ANALYZE search_documents` after the backfill so expression-index statistics
   reflect the populated corpus.
5. Deploy API and worker revisions through the existing Kamal procedure. Resume
   writers only after API and worker revisions agree.
6. Run `script/check-campsite-search` and exercise tenant filtering, private
   resources, author/project/tag filters, comment/transcript search and mentions.
   Compare representative searches and query latency before accepting the release.
7. Old search jobs in Redis are no longer executable after removing the gem.
   Inventory the dedicated legacy queue and retries before cutover; remove only
   identified legacy indexing jobs under an explicit release decision. Do not
   clear unrelated queues or retries. The new worker does not consume that queue.
8. Retire the external Elasticsearch service only after acceptance and a separate
   operator decision. Removing its Kamal declaration does not stop an existing
   container or delete its volumes.

Rollback: retain the database checkpoint and use the release-specific evidence.
The security follow-up can roll back to native PostgreSQL revision
`77a7bdc1874bbf40b0244ca83b0d3b446c100a4e` without changing the database schema.
The first cutover's pre-native revision `91de4dfc92824547e503fe1294a2ba836161019f`
still depends on Elasticsearch; reverting to that code alone does not provide
working PostgreSQL search. Do not restore Elasticsearch as an incidental rollback
step. For a native-search regression, pause writers and deploy a corrected native
revision; any legacy rollback requires an explicit operator decision.
The additive `search_documents` table can remain in place; no canonical source
rows are transformed or deleted by this migration.

The dated homelab-production and Elasticsearch recovery documents describe the
previous deployment and remain historical evidence until live cutover is verified.

## Design references

Native prefix queries and ranking use [PostgreSQL text search](https://www.postgresql.org/docs/current/textsearch.html).
Typo fallback uses [pg_trgm word similarity and GIN support](https://www.postgresql.org/docs/current/pgtrgm.html).
These references describe database capabilities; local tests and source inspection,
not the references alone, establish this application's behavior.

## Local verification evidence (2026-11-04)

- Migration applied to local PostgreSQL 18; final schema loaded into a separate
  disposable test database. Eight search-document tests passed there.
- Search/controller/version regression run: 45 tests, 259 assertions, all passed.
- MCP suite: 128 tests, 879 assertions, all passed.
- Corrected comment/resolution/recording/version query-budget suites: 84 tests,
  321 assertions, all passed; call/note visibility suites: 38 tests, 134 assertions,
  all passed. Recording lifecycle/model checks: 13 tests, 34 assertions, all passed.
- Latest full run: 4,281 tests, 14,024 assertions, one failure, zero errors. The
  failure was the note-create SQL budget (22 versus 28 queries), loaded before
  its expectation was corrected. After correction its full controller suite
  passed: 56 tests, 216 assertions. The entire suite was not repeated after
  that final assertion-only change.
- Two-process local PostgreSQL testing completed with `PGGSSENCMODE=disable`;
  earlier macOS native-pg connections crashed across fork without that override.
  The wrapper retains the conservative one-worker default. To use two workers:
  `PGGSSENCMODE=disable PARALLEL_WORKERS=2 script/test-postgresql test`.
- Brakeman reported four warnings in unchanged files and no warnings in the new
  search implementation. Changed Ruby files pass RuboCop; YAML/ERB and shell
  syntax checks pass. No generated API contract changed.
- The rebuild was tested for missing rows, orphan cleanup and repeatability.
  An EXPLAIN check on the disposable schema confirmed the content trigram GIN
  index supports the fallback predicate. Production-scale latency and index
  size have not been benchmarked. Synchronous refresh adds SQL work to writes,
  especially author/project renames; release acceptance includes that cost.

At the initial source-verification checkpoint, no production migration, live
backfill, deployment, external server retirement, commit or push had been
performed. The 2026-11-04 live release above supersedes that deployment status.
The PostgreSQL-only application revision cannot
be deployed against a MySQL database. Legacy MySQL client gems remain because
existing import/rollback tooling still uses them; application search no longer
uses them or Elasticsearch.

Optimization follow-up: the full 2026-11-04 suite subsequently passed 4,287 tests
and 14,041 assertions, with zero failures/errors/skips. The earlier failed-count
run above remains a historical record. See the optimization report for current
index, refresh, pool and performance evidence.
