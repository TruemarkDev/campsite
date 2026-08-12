# Styled Text Server

Transform text to a usable format in other services like Campsite or Slack.

## Development

Run `script/dev` like normal from the workspace root. If you need to run this service in isolation, from the workspace root run:

```sh
pnpm turbo run dev --filter=@campsite/styled-text-server
```

## Authentication

This service uses bearer authentication. The consumer must provide the token stored in the API's `AUTHTOKEN` environment variable in an `Authorization` header like this:

```
Authorization: Bearer <token>
```

## Deployment

The production image is deployed with Kamal using one of the repository-level
styled-text configurations:

- `config/deploy.styled-text-server.yml` for `camp-styled-text.polo-apps.com`
- `config/deploy.campsite-styled-text.yml` for `camp-styled-text.tokdio.com`

Render a configuration before deploying:

```sh
mise exec -- kamal config -c config/deploy.campsite-styled-text.yml
```

To test the production image locally, run this command from the repository root:

```sh
docker build --tag campsite-styled-text-server \
  --file apps/styled-text-server/Dockerfile .
docker run --rm --publish 9000:9000 \
  --env AUTHTOKEN=local-smoke-token \
  --env NODE_ENV=production \
  campsite-styled-text-server
```

The Kamal proxy checks `GET /up` on port 9000. A healthy server returns HTTP 200.
