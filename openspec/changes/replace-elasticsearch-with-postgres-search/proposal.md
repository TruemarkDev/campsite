# Replace Elasticsearch with PostgreSQL search

User authorization: migrate all Campsite search out of Elasticsearch (2026-11-04).
Tracking: campsite-6qq. This supersedes the search-replacement exclusion in the
completed database migration for this new scope. Existing API contracts remain authoritative.

The application SHALL query PostgreSQL for post, note, call and mention search
(Verification: controller/model tests). It SHALL preserve tenant filtering,
resource policies, recorded-call filtering, author/project/tag filtering,
blank-query browsing, pagination and escaped highlights (Verification: Test).
It SHOULD support word-prefix matching, phrase preference and typo fallback
(Verification: Test). Exact Elasticsearch scores and tokenization are not a contract.

Derived search documents SHALL update transactionally with source writes and be
rebuildable from canonical rows (Verification: rollback/update/delete and rebuild tests).
The repository SHALL no longer require an Elasticsearch service for development,
tests, CI or newly deployed application revisions (Verification: Inspection and Test).

Deployment, live backfill and retirement of existing servers are not performed by
this source change. Historical deployment documents remain dated evidence.


## Measured performance follow-up

The implementation SHOULD avoid rewriting unchanged search snapshots and avoid
unused total-count queries (Verification: Test). Pool capacity SHOULD cover
foreground plus configured async concurrency (Verification: Test/Inspection).
The measured SQL plans and advisory indexes are recorded in
`docs/reviews/postgresql-performance-2026-11-04.md`; no latency SLA is implied.
