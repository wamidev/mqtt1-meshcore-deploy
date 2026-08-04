#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$DEPLOY_DIR/.env"
CONFIG_DIR="$DEPLOY_DIR/mosquitto/config"
PASSWD_FILE="$CONFIG_DIR/passwd"

[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }
[ -s "$PASSWD_FILE" ] || { echo "Missing $PASSWD_FILE." >&2; exit 1; }

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

case "${MONITOR_RO_PASSWORD:-}" in
  ""|CHANGE_ME*) echo "Set a real MONITOR_RO_PASSWORD in .env." >&2; exit 1 ;;
esac

printf '%s\n%s\n' "$MONITOR_RO_PASSWORD" "$MONITOR_RO_PASSWORD" | docker run --rm -i \
  -v "$CONFIG_DIR:/mosquitto/config" eclipse-mosquitto:2.1.2-alpine \
  mosquitto_passwd /mosquitto/config/passwd monitor-ro

docker run --rm --user 0:0 --entrypoint sh \
  -v "$CONFIG_DIR:/mosquitto/config" eclipse-mosquitto:2.1.2-alpine \
  -c 'chown root:root /mosquitto/config/passwd && chmod 644 /mosquitto/config/passwd'

echo "Added or updated monitor-ro in $PASSWD_FILE."
