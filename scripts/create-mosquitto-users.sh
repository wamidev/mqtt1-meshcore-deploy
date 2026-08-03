#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$DEPLOY_DIR/.env"
CONFIG_DIR="$DEPLOY_DIR/mosquitto/config"
PASSWD_FILE="$CONFIG_DIR/passwd"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE. Copy .env.mqtt1.example or .env.mqtt2.example to .env first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

for variable in FEED_HEALTH_PASSWORD DEDUP_WRITER_PASSWORD CORESCOPE_RO_PASSWORD MAP_RO_PASSWORD; do
  eval "value=\${$variable:-}"
  case "$value" in
    ""|CHANGE_ME*) echo "Set a real value for $variable in .env." >&2; exit 1 ;;
  esac
done

mkdir -p "$CONFIG_DIR"
if [ -e "$PASSWD_FILE" ]; then
  echo "$PASSWD_FILE already exists; refusing to overwrite it." >&2
  exit 1
fi
touch "$PASSWD_FILE"
chmod 600 "$PASSWD_FILE"

add_user() {
  username=$1
  password=$2
  printf '%s\n%s\n' "$password" "$password" | docker run --rm -i \
    -v "$CONFIG_DIR:/mosquitto/config" eclipse-mosquitto:2 \
    mosquitto_passwd /mosquitto/config/passwd "$username"
}

add_user feed-health "$FEED_HEALTH_PASSWORD"
add_user dedup-writer "$DEDUP_WRITER_PASSWORD"
add_user corescope-ro "$CORESCOPE_RO_PASSWORD"
add_user map-ro "$MAP_RO_PASSWORD"

docker run --rm --user 0:0 --entrypoint sh \
  -v "$CONFIG_DIR:/mosquitto/config" eclipse-mosquitto:2 \
  -c 'chown root:root /mosquitto/config/passwd && chmod 644 /mosquitto/config/passwd'

echo "Created $PASSWD_FILE with mode 644 so the unprivileged Mosquitto process can read it."
