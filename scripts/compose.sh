#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

[ -f .env ] || { echo "Missing .env." >&2; exit 1; }

set -a
# shellcheck disable=SC1091
. ./.env
set +a

case "${DEPLOY_MODE:-}" in
  mqtt1-tunnel) COMPOSE_OVERRIDE=docker-compose.mqtt1.yml ;;
  mqtt2-tunnel) COMPOSE_OVERRIDE=docker-compose.mqtt2.yml ;;
  *) echo "DEPLOY_MODE must be mqtt1-tunnel or mqtt2-tunnel." >&2; exit 1 ;;
esac

exec docker compose -f docker-compose.yml -f "$COMPOSE_OVERRIDE" "$@"
