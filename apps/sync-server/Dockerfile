# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89

FROM node:22.21.0-bookworm-slim@sha256:f9f7f95dcf1f007b007c4dcd44ea8f7773f931b71dc79d57c216e731c87a090b AS base

# configure pnpm
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

LABEL fly_launch_runtime="Node.js"

# Throw-away build stage to reduce size of final image
FROM base AS builder
# Install packages needed to build node modules
RUN apt-get update -qq && \
  apt-get install -y build-essential pkg-config python-is-python3 ca-certificates
WORKDIR /app
RUN pnpm install turbo@2.0.9 --global
COPY . .
RUN turbo prune @campsite/sync-server --docker
WORKDIR /app


FROM base AS installer
WORKDIR /app
COPY --from=builder /app/out/json/ .
COPY --from=builder /app/out/pnpm-lock.yaml ./pnpm-lock.yaml

RUN --mount=type=secret,id=TIPTAP_PRIVATE_REGISTRY_KEY \
    pnpm config set "@tiptap-pro:registry" https://registry.tiptap.dev/ && \
    pnpm config set "//registry.tiptap.dev/:_authToken" "$(cat /run/secrets/TIPTAP_PRIVATE_REGISTRY_KEY)" && \
    pnpm install --frozen-lockfile && \
    pnpm config delete "//registry.tiptap.dev/:_authToken"

COPY --from=builder /app/out/full/ .

RUN npx turbo run build --filter=@campsite/sync-server

FROM base AS runner

# Set production environment
ENV NODE_ENV="production"

WORKDIR /app/apps/sync-server

# Copy built application
COPY --from=installer --chown=node:node /app /app

USER node

# Start the server by default, this can be overwritten at runtime
EXPOSE 9000
ENV PORT=9000

ENTRYPOINT [ "node", "dist/index.mjs" ]
