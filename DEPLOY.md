# Deploying to Dokku (build in CI, not on the VPS)

The bot used to deploy via a Heroku-style buildpack (`Procfile` + `git push dokku`),
which compiles the whole Rust project **on the VPS** — slow and resource-hungry.

Instead, GitHub Actions builds a Docker image and hands Dokku the **prebuilt
image**, so the VPS never compiles anything.

## How it works

- **`.github/workflows/ci.yml`** — runs on every push to `main` and every PR:
  `rustfmt` (nightly), `clippy -D warnings`, and `cargo test`, with Rust caching.
- **`.github/workflows/docker.yml`** — runs on every push to `main` and every PR:
  builds the `Dockerfile` and (for non-fork builds) pushes it to GHCR as
  `ghcr.io/ryanbai1412/usaco-standings-bot:<commit-sha>` (plus `:latest` on `main`).
  The job summary prints a ready-to-run **release command** for that exact image.

Nothing compiles on the VPS or your laptop.

## Releasing a build to Dokku

After a build finishes, open the `Docker image` workflow run → job summary. It shows:

```sh
ssh <your-dokku-host> "dokku git:from-image usaco-standings-bot ghcr.io/ryanbai1412/usaco-standings-bot:<sha> && dokku ps:scale usaco-standings-bot bot=1"
```

Copy it (fill in your host) and run it. Because it pins the commit SHA, you deploy
exactly the image you reviewed, and rolling back is just re-running the command
with an older SHA.

If the GHCR package is **private**, the VPS needs to authenticate once so Dokku
can pull it:

```sh
dokku registry:login ghcr.io <github-username> <github-personal-access-token>
```

(or make the package public in GitHub → Packages settings).

## One-time Dokku setup (on the VPS)

```sh
dokku apps:create usaco-standings-bot

# Secrets / config (the app reads these at runtime)
dokku config:set usaco-standings-bot DISCORD_TOKEN=xxxxx FILE_STORE_PATH=/store/db.json

# Persistent storage for the file store (survives redeploys)
dokku storage:mount usaco-standings-bot /var/lib/dokku/data/storage/usaco-standings-bot:/store

# This is a worker-only bot with no web process. Disable the zero-downtime
# port check so deploys aren't marked failed for not listening on a port.
dokku checks:disable usaco-standings-bot
dokku ports:clear usaco-standings-bot 2>/dev/null || true
```

To seed the database, copy `data-12-24.json` onto the mounted volume as your
`FILE_STORE_PATH` (or just run `@bot update` once the bot is online).

## Local build fallback

If you ever need to build and ship without CI (e.g. GHCR is down), `deploy/deploy.sh`
builds the image locally and deploys it — either registry-less
(`docker save | ssh docker load`) or via a registry:

```sh
SSH_HOST=root@your-vps ./deploy/deploy.sh                          # registry-less
SSH_HOST=root@your-vps REGISTRY=ghcr.io/ryanbai1412 ./deploy/deploy.sh  # via registry
```

| Variable         | Default                        | Meaning                                                       |
| ---------------- | ------------------------------ | ------------------------------------------------------------ |
| `SSH_HOST`       | (required)                     | SSH target with `docker` + `dokku` access, e.g. `root@vps`   |
| `DOKKU_APP`      | `usaco-standings-bot`          | Dokku app name                                               |
| `IMAGE_TAG`      | `usaco-standings-bot:latest`   | Local image tag                                              |
| `REGISTRY`       | (unset → registry-less)        | Registry host/namespace to push to, e.g. `ghcr.io/ryanbai1412` |
| `REGISTRY_IMAGE` | `$REGISTRY/$IMAGE_TAG`          | Full image ref Dokku deploys from                           |

## Notes

- The image bakes in `data-12-24.json` at `/app/data-12-24.json` as a seed; the
  live database is whatever `FILE_STORE_PATH` points at on the mounted volume.
- `SSH_HOST` for the local fallback must be able to run both `docker load` and
  `dokku`. If your setup separates these (restricted `dokku` user vs a root/docker
  user), split the last steps of `deploy/deploy.sh` across the two SSH targets.
