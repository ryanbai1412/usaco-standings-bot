# syntax=docker/dockerfile:1

# ---- Build stage: compile the release binary ----
FROM rust:1-bookworm AS builder

# openssl-sys (pulled in transitively) needs these at build time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# BuildKit cache mounts keep the cargo registry and target dir warm across
# builds, so incremental rebuilds are fast. The binary is copied out of the
# (cache-mounted) target dir within the same layer so it survives.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    cargo build --release --bin usaco-standings-bot \
    && cp target/release/usaco-standings-bot /usr/local/bin/usaco-standings-bot

# ---- Runtime stage: slim image with just the binary ----
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local/bin/usaco-standings-bot /app/usaco-standings-bot

# This bot has no web process. Dokku reads this Procfile from the image; scale it
# with `dokku ps:scale <app> bot=1`.
RUN printf 'bot: /app/usaco-standings-bot\n' > /app/Procfile

CMD ["/app/usaco-standings-bot"]
