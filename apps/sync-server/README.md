# sync-server

The production image is deployed with Kamal using one of the repository-level
sync-server configurations:

- `config/deploy.sync-server.yml` for `camp-sync.polo-apps.com`
- `config/deploy.campsite-sync.yml` for `camp-sync.tokdio.com`

Render a configuration before deploying:

```sh
mise exec -- kamal config -c config/deploy.campsite-sync.yml
```

To test the production image locally, run this command from the repository root:

```sh
docker build --tag campsite-sync-server --file apps/sync-server/Dockerfile .
docker run --rm --publish 9000:9000 \
  --env API_BASE_URL=https://camp-api.tokdio.com \
  --env NODE_ENV=production \
  campsite-sync-server
```

The Kamal proxy checks `GET /up` on port 9000. A healthy server returns HTTP 200.
