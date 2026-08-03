#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

[ -f .env ] || { echo "Missing .env (copy the mqtt1 or mqtt2 example first)." >&2; exit 1; }
[ -s mosquitto/config/passwd ] || { echo "Missing passwd; run scripts/create-mosquitto-users.sh." >&2; exit 1; }

if grep -q 'CHANGE_ME' .env; then
  echo ".env still contains CHANGE_ME placeholders." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a
[ "$MQTT_LOCAL_DEDUP_READER_PASSWORD" = "$DEDUP_READER_PASSWORD" ] || {
  echo "MQTT_LOCAL_DEDUP_READER_PASSWORD must equal DEDUP_READER_PASSWORD." >&2
  exit 1
}
[ "$MQTT_TARGET_PASSWORD" = "$DEDUP_WRITER_PASSWORD" ] || {
  echo "MQTT_TARGET_PASSWORD must equal DEDUP_WRITER_PASSWORD." >&2
  exit 1
}

case "${DEPLOY_MODE:-}" in
  mqtt1-proxy)
    COMPOSE_OVERRIDE=docker-compose.mqtt1.yml
    ;;
  mqtt2-tunnel)
    COMPOSE_OVERRIDE=docker-compose.mqtt2.yml
    [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || { echo "Missing CLOUDFLARE_TUNNEL_TOKEN." >&2; exit 1; }
    ;;
  *)
    echo "DEPLOY_MODE must be mqtt1-proxy or mqtt2-tunnel." >&2
    exit 1
    ;;
esac

compose() {
  docker compose -f docker-compose.yml -f "$COMPOSE_OVERRIDE" "$@"
}

compose config --quiet
compose pull
compose up -d
compose ps
