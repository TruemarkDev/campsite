# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
ARG RUBY_VERSION=4.0.6

FROM node:24.19.0-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03 AS node_runtime
FROM ruby:${RUBY_VERSION}-slim-bookworm@sha256:c5650da02325ecb3e7dd96e7074772c3ae2ecd093a9acf2cdbcf1a2fdc680726 AS base

ARG BUNDLER_VERSION

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}

ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_LOG_TO_STDOUT=true

ARG BUNDLE_WITHOUT=development:test
ARG BUNDLE_PATH=vendor/bundle
ENV BUNDLE_PATH=${BUNDLE_PATH}
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}

RUN mkdir /app
WORKDIR /app
RUN mkdir -p tmp/pids

SHELL ["/bin/bash", "-c"]

FROM base AS build_deps

ARG DEV_PACKAGES="git build-essential libpq-dev wget vim curl gzip xz-utils libsqlite3-dev default-libmysqlclient-dev ruby-mysql2"
ENV DEV_PACKAGES=${DEV_PACKAGES}

RUN --mount=type=cache,id=dev-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=dev-apt-lib,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y ${DEV_PACKAGES} \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

FROM build_deps AS gems

RUN gem install -N bundler -v ${BUNDLER_VERSION}

COPY Gemfile* ./
COPY .ruby-version ./
RUN bundle install &&  rm -rf vendor/bundle/ruby/*/cache

FROM node_runtime AS node_modules

WORKDIR /app
RUN corepack enable pnpm

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN if [ -f "pnpm-lock.yaml" ]; then \
    pnpm install --frozen-lockfile; \
    else \
    mkdir node_modules; \
    fi

FROM build_deps AS assets

COPY --from=node_runtime /usr/local/ /usr/local/
RUN corepack enable pnpm

COPY --from=gems /app /app
COPY --from=node_modules /app/node_modules /app/node_modules
COPY . .

RUN SECRET_KEY_BASE=dummy \
    S3_REGION=us-east-1 \
    S3_ENDPOINT=http://127.0.0.1:9000 \
    S3_ACCESS_KEY_ID=dummy \
    S3_SECRET_ACCESS_KEY=dummy \
    S3_BUCKET=dummy \
    bundle exec rails assets:precompile

FROM base

ARG PROD_PACKAGES="postgresql-client file vim curl gzip zip libsqlite3-0 default-libmysqlclient-dev ruby-mysql2 libjemalloc2 ffmpeg"
ENV PROD_PACKAGES=${PROD_PACKAGES}

RUN --mount=type=cache,id=prod-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=prod-apt-lib,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    ${PROD_PACKAGES} \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --from=gems /app /app
COPY . .
COPY --from=assets /app/public/assets /app/public/assets

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
ENV MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true

RUN groupadd --system rails && \
    useradd --system --gid rails --create-home rails && \
    chown -R rails:rails /app

USER rails

EXPOSE 8080
ENV PORT=8080

ARG SERVER_COMMAND="bundle exec puma"
ENV SERVER_COMMAND=${SERVER_COMMAND}
CMD ${SERVER_COMMAND}
