# Phase 2 local PostgreSQL test target

The disposable test container is `campsite-pg-verify`, using `postgres:18` and
host port `5434` mapped to container port `5432`. The Rails test configuration
uses `DB_ADAPTER=postgresql` and reads the port from `PG_TEST_PORT` (default
`5434`). No production database configuration is selected.

To create the container when it is absent, set `POSTGRES_PASSWORD` in the
invoking shell to the test-only password configured in `api/config/database.yml`,
then run:

```sh
docker run -d --name campsite-pg-verify -p 5434:5432 -e POSTGRES_PASSWORD postgres:18
```

Load only the PostgreSQL test database with the explicit test environment:

```sh
cd api
env -u RAILS_MASTER_KEY RAILS_ENV=test PGGSSENCMODE=disable DB_ADAPTER=postgresql \
  ELASTICSEARCH_URL=http://localhost:9200 S3_REGION=us-east-1 \
  mise exec -- ruby bin/rails db:drop db:create db:schema:load db:schema:dump
```

The loaded schema dumped without a diff. `RAILS_ENV=test` is required here:
without it, Rails' development database tasks also target the local MySQL
development database.
