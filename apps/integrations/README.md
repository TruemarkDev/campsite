# Campsite Integrations

This project contains integrations for third-party services, such as webhook handlers and our daily standup cron script.

## Running the app

Configure the required local environment variables, then run the app from the workspace root:

```shell
pnpm -F @campsite/integrations dev
```

This is intended to be a "headless" project, so you shouldn't see any UI, but you can access the project at [http://localhost:3004](http://localhost:3004).
