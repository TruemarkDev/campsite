# Synthetic data-copy rehearsal

This runbook operates only on disposable `campsite-copy-mysql` at 127.0.0.1:3307 and `campsite-copy-pg` at 127.0.0.1:5436. It uses no homelab or production data. pgloader was removed after its MySQL 8.4 handshake failure; the Ruby copier uses the Gemfile's `mysql2` and `pg` gems.

## Start and load schemas

```sh
docker run -d --name campsite-copy-mysql -p 3307:3306 -e MYSQL_ROOT_PASSWORD=copy-only-root -e MYSQL_DATABASE=campsite_copy -e MYSQL_USER=campsite_copy -e MYSQL_PASSWORD=copy-only-user mysql:8.4
docker run -d --name campsite-copy-pg -p 5436:5432 -e POSTGRES_PASSWORD=copy-only-pg -e POSTGRES_DB=campsite_copy postgres:18
cd api
RAILS_ENV=test DATABASE_URL='mysql2://campsite_copy:copy-only-user@127.0.0.1:3307/campsite_copy' bundle exec rails db:schema:load
RAILS_ENV=test DB_ADAPTER=postgresql PG_TEST_PORT=5436 DATABASE_URL='postgresql://postgres:copy-only-pg@127.0.0.1:5436/campsite_copy' bundle exec rails db:schema:load
cd ..
docker exec -i campsite-copy-mysql mysql -ucampsite_copy -pcopy-only-user campsite_copy < script/pgloader/generate-synthetic-data.sql
```

Verify both container names and published ports before loading schemas. Never use Rails database reset/drop/create or schema load against development or normal test databases. For a real MySQL dump rehearsal, restore only into the same disposable MySQL container with `docker exec -i ... mysql ... < dump.sql`; the evidence below uses synthetic fixtures only.

## Copy and verify

From `api/`, using the repo's mise Ruby:

```sh
SOURCE_MYSQL_URL='mysql2://campsite_copy:copy-only-user@127.0.0.1:3307/campsite_copy' TARGET_PG_URL='postgresql://postgres:copy-only-pg@127.0.0.1:5436/campsite_copy' bundle exec ruby ../script/pg-copy
SOURCE_MYSQL_URL='mysql2://campsite_copy:copy-only-user@127.0.0.1:3307/campsite_copy' TARGET_PG_URL='postgresql://postgres:copy-only-pg@127.0.0.1:5436/campsite_copy' bundle exec ruby ../script/check-campsite-pg-parity --check-sequences
```

The copier truncates all public target tables, copies PostgreSQL columns except generated `product_logs.device_info_*` columns (PostgreSQL recomputes them), then resets id sequences. It includes `schema_migrations` and `ar_internal_metadata`. The checker excludes those same generated columns for that reason only; all other shared columns are checked. Both tools print table names, counts, hashes, and sequence values only.

## Evidence, 2026-09-24

Clean copy: parity exited 0, with zero `MISMATCH` and zero `SEQUENCE_MISMATCH` lines. Representative rows:

```text
MATCH ar_internal_metadata mysql_count=2 mysql_sha256=b6ecbaa47d61134427030a5e8b5906938b2b13c72dbb207b90c90e1043b52896 postgres_count=2 postgres_sha256=b6ecbaa47d61134427030a5e8b5906938b2b13c72dbb207b90c90e1043b52896
MATCH product_logs mysql_count=1 mysql_sha256=a1c71041a2e5971fcf964837d8ddcb79eaafde369abd2f170c33fc537782f037 postgres_count=1 postgres_sha256=a1c71041a2e5971fcf964837d8ddcb79eaafde369abd2f170c33fc537782f037
MATCH schema_migrations mysql_count=418 mysql_sha256=a3ab35c8765a8240e986dfd5ed9ced39713084048f7a38cb725db919a096606a postgres_count=418 postgres_sha256=a3ab35c8765a8240e986dfd5ed9ced39713084048f7a38cb725db919a096606a
MATCH users mysql_count=1 mysql_sha256=17bb14d2210f4839c8c4c1838eabefa92cf2672fafc10d6e016f3b6d0d0e5443 postgres_count=1 postgres_sha256=17bb14d2210f4839c8c4c1838eabefa92cf2672fafc10d6e016f3b6d0d0e5443
SEQUENCE_MATCH users max_id=900000001 next_id=900000002
```

Tamper: after changing one synthetic PostgreSQL `users` row, parity exited 1 and named `users`:

```text
MISMATCH users mysql_count=1 mysql_sha256=17bb14d2210f4839c8c4c1838eabefa92cf2672fafc10d6e016f3b6d0d0e5443 postgres_count=1 postgres_sha256=ee2e51eee04eb9b9f4d9f0a2d9c832989de2a45ffcc02d1ff6de2462eec3cf12
```

## Teardown

```sh
docker rm -f campsite-copy-mysql campsite-copy-pg
```
