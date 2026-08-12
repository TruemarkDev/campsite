# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89

FROM node:24.19.0-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03 AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS pruner
WORKDIR /app
COPY . .
RUN pnpm dlx turbo@2.10.9 prune @campsite/styled-text-server --docker

FROM base AS builder
WORKDIR /app
COPY --from=pruner /app/out/json/ .
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml

RUN --mount=type=cache,id=campsite-styled-text-pnpm,target=/pnpm/store \
  pnpm install --frozen-lockfile

COPY --from=pruner /app/out/full/ .

RUN pnpm turbo run build --filter=@campsite/styled-text-server && \
  CI=true pnpm install --prod --offline --frozen-lockfile

FROM base AS runner

ENV NODE_ENV=production
ENV PORT=9000

WORKDIR /app/apps/styled-text-server

COPY --from=builder --chown=node:node /app /app

USER node

EXPOSE 9000

CMD ["node", "dist/index.mjs"]
