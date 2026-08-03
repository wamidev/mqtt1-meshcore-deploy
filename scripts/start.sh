#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

[ -f .env ] || { echo "Missing .env (copy .env.example first)." >&2; exit 1; }
[ -s mosquitto/config/passwd ] || { echo "Missing passwd; run scripts/create-mosquitto-users.sh." >&2; exit 1; }
[ -s secrets/nginx/fullchain.pem ] || { echo "Missing secrets/nginx/fullchain.pem." >&2; exit 1; }
[ -s secrets/nginx/privkey.pem ] || { echo "Missing secrets/nginx/privkey.pem." >&2; exit 1; }

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

docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
