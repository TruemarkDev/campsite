# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
FROM node:24.19.0-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03

# uncomment to run on m1 mac
# make sure Docker > Settings > Features in dev > Rosetta is enabled
# and build + run with --platform linux/amd64
# FROM --platform=linux/amd64 node:18

# We don't need the standalone Chromium
ENV PUPPETEER_SKIP_DOWNLOAD=true

RUN apt-get update && apt-get install -y curl gnupg ca-certificates dumb-init --no-install-recommends \
  && curl --location --silent https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list \
  && apt-get update \
  && apt-get install -y google-chrome-stable fonts-inter fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-khmeros fonts-kacst fonts-freefont-ttf fonts-noto-color-emoji libxss1 --no-install-recommends \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir /app && chown node:node /app
WORKDIR /app

RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile --prod && pnpm store prune

COPY --chown=node:node . .

# Set production environment
ENV NODE_ENV="production"

USER node

EXPOSE 9222
ENV PORT=9222

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
