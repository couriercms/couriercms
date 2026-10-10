# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.1
ARG DEBIAN_VERSION=bookworm-20260918-slim
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY extensions/sdk /app/extensions/sdk
COPY platform/mix.exs platform/mix.lock /app/platform/
WORKDIR /app/platform
RUN mix deps.get --only prod
COPY platform/config/config.exs platform/config/prod.exs /app/platform/config/
RUN mix deps.compile

COPY extensions/wordpress /app/extensions/wordpress
COPY extensions/sanity /app/extensions/sanity
RUN cd /app/extensions/wordpress \
  && mix deps.get --only prod \
  && mix couriercms.extension.build
RUN cd /app/extensions/sanity \
  && mix deps.get --only prod \
  && mix couriercms.extension.build

COPY platform/priv /app/platform/priv
COPY platform/lib /app/platform/lib
COPY platform/assets /app/platform/assets
WORKDIR /app/platform
RUN mix assets.deploy
RUN mix compile

COPY platform/config/runtime.exs /app/platform/config/
COPY platform/rel /app/platform/rel
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true \
    COURIERCMS_EXTENSIONS_PATH=/var/lib/couriercms/extensions \
    COURIERCMS_EXTENSION_CACHE_DIR=/var/lib/couriercms/extension-cache

WORKDIR /app
RUN mkdir -p /var/lib/couriercms/extensions /var/lib/couriercms/extension-cache \
  && chown -R nobody:root /app /var/lib/couriercms

COPY --from=builder --chown=nobody:root /app/platform/_build/prod/rel/couriercms ./
COPY --from=builder --chown=nobody:root /app/extensions/wordpress/dist/couriercms_wordpress-0.1.0.couriercms /var/lib/couriercms/extensions/
COPY --from=builder --chown=nobody:root /app/extensions/sanity/dist/couriercms_sanity-0.1.0.couriercms /var/lib/couriercms/extensions/
RUN chmod +x /app/bin/server /app/bin/migrate

USER nobody
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:4000/health/ready || exit 1

CMD ["/app/bin/server"]
