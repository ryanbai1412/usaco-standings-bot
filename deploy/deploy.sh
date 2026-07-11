#!/usr/bin/env bash
#
# Build the bot image locally and deploy it to Dokku as a prebuilt image, so
# nothing is compiled on the VPS.
#
# Two modes:
#   * Registry-less (default): `docker save` the image and pipe it over SSH into
#     the VPS's Docker daemon, then `dokku git:from-image`.
#   * Registry: set REGISTRY (+ optionally REGISTRY_IMAGE) to push to a registry
#     the VPS can pull from, then `dokku git:from-image`.
#
# Config via environment variables:
#   SSH_HOST       (required) SSH target with docker + dokku access, e.g. root@vps
#   DOKKU_APP      Dokku app name                (default: usaco-standings-bot)
#   IMAGE_TAG      Local image tag               (default: usaco-standings-bot:latest)
#   REGISTRY       Registry host/namespace to push to, e.g. ghcr.io/ryanbai1412
#                  (unset => registry-less save/load)
#   REGISTRY_IMAGE Full image ref to deploy from (default: $REGISTRY/$IMAGE_TAG)
#
# Examples:
#   SSH_HOST=root@vps ./deploy/deploy.sh
#   SSH_HOST=root@vps REGISTRY=ghcr.io/ryanbai1412 ./deploy/deploy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

: "${SSH_HOST:?set SSH_HOST to your VPS ssh target (needs docker + dokku access), e.g. root@vps}"
DOKKU_APP="${DOKKU_APP:-usaco-standings-bot}"
IMAGE_TAG="${IMAGE_TAG:-usaco-standings-bot:latest}"

echo ">> Building image $IMAGE_TAG locally"
DOCKER_BUILDKIT=1 docker build -t "$IMAGE_TAG" .

if [[ -n "${REGISTRY:-}" ]]; then
  REGISTRY_IMAGE="${REGISTRY_IMAGE:-$REGISTRY/$IMAGE_TAG}"
  echo ">> Pushing $REGISTRY_IMAGE to registry"
  docker tag "$IMAGE_TAG" "$REGISTRY_IMAGE"
  docker push "$REGISTRY_IMAGE"
  DEPLOY_IMAGE="$REGISTRY_IMAGE"
else
  echo ">> Shipping image to $SSH_HOST via docker save | docker load"
  docker save "$IMAGE_TAG" | gzip | ssh "$SSH_HOST" "gunzip | docker load"
  DEPLOY_IMAGE="$IMAGE_TAG"
fi

echo ">> Deploying $DEPLOY_IMAGE to dokku app $DOKKU_APP"
ssh "$SSH_HOST" "dokku git:from-image $DOKKU_APP $DEPLOY_IMAGE"

echo ">> Ensuring the worker process is running (bot=1, no web process)"
ssh "$SSH_HOST" "dokku ps:scale $DOKKU_APP bot=1"

echo ">> Done."
