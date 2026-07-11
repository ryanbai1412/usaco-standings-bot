# syntax=docker/dockerfile:1

# ---- Base with cargo-chef, used to plan and cook the dependency graph ----
FROM rust:1-bookworm AS chef
RUN cargo install cargo-chef --locked
WORKDIR /app

# ---- Plan: capture just the dependency graph (invalidated only by Cargo.* ) ----
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# ---- Build: cook deps (cached), then compile our code ----
FROM chef AS builder

# openssl-sys (pulled in transitively) needs these at build time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Cook dependencies. This layer is cached and only rebuilds when the dependency
# graph in recipe.json changes, so source-only edits skip recompiling all deps.
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# Now build the actual binary; only our workspace crates recompile here.
COPY . .
RUN cargo build --release --bin usaco-standings-bot

# ---- Runtime: slim image with just the binary ----
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/usaco-standings-bot /app/usaco-standings-bot

# This bot has no web process. Dokku reads this Procfile from the image; scale it
# with `dokku ps:scale <app> bot=1`.
RUN printf 'bot: /app/usaco-standings-bot\n' > /app/Procfile

CMD ["/app/usaco-standings-bot"]
