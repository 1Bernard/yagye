# Versions are pinned to match .tool-versions at the repo root.
# To update: change the ARGs here and in .tool-versions together.
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=bookworm-20260803

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}-slim"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

# ── Stage 1: build ────────────────────────────────────────────────────────────
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Fetch deps before copying source — this layer is cached as long as
# mix.exs and mix.lock do not change.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Now copy source and compile
COPY lib lib
COPY priv priv
RUN mix compile

# runtime.exs is read at startup, not at compile time — copy it last
COPY config/runtime.exs config/
RUN mix release

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE} AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set UTF-8 locale — required by the Erlang VM
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app

RUN chown nobody /app

# Copy only the compiled release — no compiler, no source, no Mix
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/yagye_core ./

USER nobody

# PHX_SERVER=true tells runtime.exs to start the HTTP listener
ENV PHX_SERVER=true

CMD ["/app/bin/yagye_core", "start"]
