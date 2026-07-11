# Deploying

The bot runs on [Dokku](https://dokku.com/) as a prebuilt Docker image. CI builds
the image; you release it with one command. Nothing compiles on the server.

## Deploying a new version

1. Merge to `main` (or open a PR). GitHub Actions builds the image and pushes it to
   `ghcr.io/ryanbai1412/usaco-standings-bot:<commit-sha>`.
2. Open the **Docker image** workflow run → job summary, and run the release
   command it prints (fill in your host):

   ```sh
   ssh <dokku-host> "dokku git:from-image usaco-standings-bot ghcr.io/ryanbai1412/usaco-standings-bot:<sha> && dokku ps:scale usaco-standings-bot bot=1"
   ```

The command pins the commit SHA, so you deploy exactly that build — and rolling
back is the same command with an older SHA.

## First-time setup (once, on the VPS)

```sh
dokku apps:create usaco-standings-bot

# Persistent DB storage. FILE_STORE_PATH is a DIRECTORY; the app stores
# usaco-db.json and stats.json inside it.
dokku storage:ensure-directory usaco-standings-bot
dokku storage:mount usaco-standings-bot /var/lib/dokku/data/storage/usaco-standings-bot:/store
dokku config:set usaco-standings-bot DISCORD_TOKEN=xxxxx FILE_STORE_PATH=/store

# Worker-only bot (no web server): skip the port check.
dokku checks:disable usaco-standings-bot

# If the GHCR package is private, let Dokku pull it:
dokku registry:login ghcr.io <github-username> <github-token>
```

The DB starts empty — run `@bot update` once the bot is online to populate it.

## Running locally

```sh
export DISCORD_TOKEN=... FILE_STORE_PATH=./store
mkdir -p "$FILE_STORE_PATH"
cargo run
```

## Building without CI

`./deploy/deploy.sh` builds the image locally and deploys it (registry-less by
default). See the variables documented at the top of that script.
