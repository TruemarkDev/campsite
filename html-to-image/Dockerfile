FROM node:22-slim

# uncomment to run on m1 mac
# make sure Docker > Settings > Features in dev > Rosetta is enabled
# and build + run with --platform linux/amd64
# FROM --platform=linux/amd64 node:18

# We don't need the standalone Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true

RUN apt-get update && apt-get install -y curl gnupg ca-certificates --no-install-recommends \
  && curl --location --silent https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list \
  && apt-get update \
  && apt-get install -y google-chrome-stable fonts-inter fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-khmeros fonts-kacst fonts-freefont-ttf fonts-noto-color-emoji libxss1 --no-install-recommends \
  && rm -rf /var/lib/apt/lists/*

ADD https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 /usr/local/bin/dumb-init
RUN chmod +x /usr/local/bin/dumb-init

RUN mkdir /app
WORKDIR /app

RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile --prod && pnpm store prune

COPY . .

# Set production environment
ENV NODE_ENV="production"

EXPOSE 9222
ENV PORT 9222

ENTRYPOINT ["dumb-init", "--"]
CMD ["pnpm", "run", "server"]