#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

[ -f .env ] || { echo "Missing .env (copy the mqtt1 or mqtt2 example first)." >&2; exit 1; }
[ -f feed-readers.env ] || { echo "Missing feed-readers.env (copy feed-readers.env.example first)." >&2; exit 1; }

if grep -q 'CHANGE_ME' .env; then
  echo ".env still contains CHANGE_ME placeholders." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

for variable in MONITOR_IMAGE MONITOR_MQTT_PASSWORD MONITOR_RO_PASSWORD; do
  eval "value=\${$variable:-}"
  [ -n "$value" ] || { echo "Missing $variable." >&2; exit 1; }
done

for variable in PUBLIC_BROKER_READER_PASSWORD MQTT_SOURCE_1_PASSWORD MQTT_SOURCE_2_PASSWORD; do
  eval "value=\${$variable:-}"
  case "$value" in
    *:*) echo "$variable must not contain a colon." >&2; exit 1 ;;
  esac
done
[ "$MQTT_LOCAL_DEDUP_READER_PASSWORD" = "$FEED_HEALTH_PASSWORD" ] || {
  echo "MQTT_LOCAL_DEDUP_READER_PASSWORD must equal FEED_HEALTH_PASSWORD." >&2
  exit 1
}
[ "$MQTT_TARGET_PASSWORD" = "$DEDUP_WRITER_PASSWORD" ] || {
  echo "MQTT_TARGET_PASSWORD must equal DEDUP_WRITER_PASSWORD." >&2
  exit 1
}
[ "$MONITOR_MQTT_PASSWORD" = "$MONITOR_RO_PASSWORD" ] || {
  echo "MONITOR_MQTT_PASSWORD must equal MONITOR_RO_PASSWORD." >&2
  exit 1
}

case "${DEPLOY_MODE:-}" in
  mqtt1-tunnel)
    COMPOSE_OVERRIDE=docker-compose.mqtt1.yml
    [ "$AUTH_EXPECTED_AUDIENCE" = "mqtt1.meshcore.node.cz" ] || { echo "MQTT1 audience must be mqtt1.meshcore.node.cz." >&2; exit 1; }
    [ "$PUBLIC_BROKER_READER_PASSWORD" = "$MQTT_SOURCE_1_PASSWORD" ] || { echo "PUBLIC_BROKER_READER_PASSWORD must equal MQTT_SOURCE_1_PASSWORD on MQTT1." >&2; exit 1; }
    [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || { echo "Missing CLOUDFLARE_TUNNEL_TOKEN." >&2; exit 1; }
    [ "${MONITOR_DOMAIN:-}" = "monitor-mqtt1.meshcore.node.cz" ] || { echo "MQTT1 monitor domain must be monitor-mqtt1.meshcore.node.cz." >&2; exit 1; }
    ;;
  mqtt2-tunnel)
    COMPOSE_OVERRIDE=docker-compose.mqtt2.yml
    [ "$AUTH_EXPECTED_AUDIENCE" = "mqtt2.meshcore.website" ] || { echo "MQTT2 audience must be mqtt2.meshcore.website." >&2; exit 1; }
    [ "$PUBLIC_BROKER_READER_PASSWORD" = "$MQTT_SOURCE_2_PASSWORD" ] || { echo "PUBLIC_BROKER_READER_PASSWORD must equal MQTT_SOURCE_2_PASSWORD on MQTT2." >&2; exit 1; }
    [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || { echo "Missing CLOUDFLARE_TUNNEL_TOKEN." >&2; exit 1; }
    [ "${MONITOR_DOMAIN:-}" = "monitor-mqtt2.meshcore.website" ] || { echo "MQTT2 monitor domain must be monitor-mqtt2.meshcore.website." >&2; exit 1; }
    ;;
  *)
    echo "DEPLOY_MODE must be mqtt1-tunnel or mqtt2-tunnel." >&2
    exit 1
    ;;
esac

compose() {
  docker compose -f docker-compose.yml -f "$COMPOSE_OVERRIDE" "$@"
}

if git rev-parse HEAD >/dev/null 2>&1; then
  cat > deploy-meta.json <<META
{"commit":"$(git rev-parse HEAD)","commit_short":"$(git rev-parse --short HEAD)","deployed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
META
fi

FEED_ACCOUNTS_HASH_FILE=mosquitto/config/.feed-accounts.sha256
feed_accounts_before=""
[ -f "$FEED_ACCOUNTS_HASH_FILE" ] && feed_accounts_before=$(cat "$FEED_ACCOUNTS_HASH_FILE")
./scripts/create-mosquitto-users.sh
feed_accounts_after=""
[ -f "$FEED_ACCOUNTS_HASH_FILE" ] && feed_accounts_after=$(cat "$FEED_ACCOUNTS_HASH_FILE")

compose config --quiet
compose pull
compose up -d
if [ "$feed_accounts_before" != "$feed_accounts_after" ]; then
  compose restart feed-broker
fi
compose ps
