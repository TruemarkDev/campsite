# Phase 1 MySQL baseline

Date: 2026-09-23
Command: `env -u RAILS_MASTER_KEY ELASTICSEARCH_URL=http://localhost:9200 mise exec -- ruby bin/rails test` from `api/` (Ruby 4.0.6 via mise; credentials key unset; local Elasticsearch endpoint override).

Result: 4,226 runs, 13,814 assertions, 0 failures, 0 errors, 0 skips. No failing test names.
