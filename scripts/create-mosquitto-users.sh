#!/usr/bin/env sh
set -eu

# Regenerates mosquitto/config/passwd and mosquitto/config/acl from .env (the
# three fixed internal accounts) and feed-readers.env (an arbitrary list of
# read-only feed accounts). Idempotent: skips the (destructive) regeneration
# when neither input changed since the last run, so routine deploys don't
# bounce feed-broker for no reason.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

ENV_FILE=.env
READERS_FILE=feed-readers.env
CONFIG_DIR=mosquitto/config
PASSWD_FILE="$CONFIG_DIR/passwd"
ACL_FILE="$CONFIG_DIR/acl"
HASH_FILE="$CONFIG_DIR/.feed-accounts.sha256"
IMAGE=eclipse-mosquitto:2.1.2-alpine

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE (copy the mqtt1 or mqtt2 example first)." >&2
  exit 1
fi
if [ ! -f "$READERS_FILE" ]; then
  echo "Missing $READERS_FILE. Copy feed-readers.env.example to feed-readers.env first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./"$ENV_FILE"
set +a

for variable in FEED_HEALTH_PASSWORD DEDUP_WRITER_PASSWORD MONITOR_RO_PASSWORD; do
  eval "value=\${$variable:-}"
  case "$value" in
    ""|CHANGE_ME*) echo "Set a real value for $variable in .env." >&2; exit 1 ;;
  esac
done

new_hash=$(
  { printf '%s\n' "$FEED_HEALTH_PASSWORD" "$DEDUP_WRITER_PASSWORD" "$MONITOR_RO_PASSWORD"; cat "$READERS_FILE"; } \
    | sha256sum | cut -d' ' -f1
)
old_hash=""
[ -f "$HASH_FILE" ] && old_hash=$(cat "$HASH_FILE")
if [ "$new_hash" = "$old_hash" ] && [ -s "$PASSWD_FILE" ]; then
  echo "Feed accounts unchanged; skipping regeneration."
  exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# First pass: validate feed-readers.env completely before touching anything
# live, so a typo never leaves passwd/acl half-written.
PAIRS_FILE="$WORK_DIR/pairs"
: > "$PAIRS_FILE"
name=""
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  line=$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] && continue
  case "$line" in
    '#'*) continue ;;
  esac
  if [ -z "$name" ]; then
    name="$line"
    case "$name" in
      *[!A-Za-z0-9_-]*)
        echo "Invalid account name '$name' in $READERS_FILE (use only letters, digits, '-' or '_')." >&2
        exit 1
        ;;
    esac
    continue
  fi
  printf '%s\n%s\n' "$name" "$line" >> "$PAIRS_FILE"
  name=""
done < "$READERS_FILE"
if [ -n "$name" ]; then
  echo "$READERS_FILE has an odd number of non-empty lines (missing password for '$name')." >&2
  exit 1
fi
if [ ! -s "$PAIRS_FILE" ]; then
  echo "$READERS_FILE defines no accounts." >&2
  exit 1
fi

NEW_PASSWD="$WORK_DIR/passwd"
NEW_ACL="$WORK_DIR/acl"

add_user() {
  username=$1
  password=$2
  if [ -s "$NEW_PASSWD" ]; then
    docker run --rm -v "$WORK_DIR:/work" "$IMAGE" \
      mosquitto_passwd -b /work/passwd "$username" "$password" >/dev/null
  else
    docker run --rm -v "$WORK_DIR:/work" "$IMAGE" \
      mosquitto_passwd -c -b /work/passwd "$username" "$password" >/dev/null
  fi
}

add_user feed-health "$FEED_HEALTH_PASSWORD"
add_user dedup-writer "$DEDUP_WRITER_PASSWORD"
add_user monitor-ro "$MONITOR_RO_PASSWORD"

{
  printf 'user feed-health\ntopic read $SYS/broker/version\n'
  printf '\nuser dedup-writer\ntopic write meshcore/#\ntopic write meshcore-monitor/#\n'
  printf '\nuser monitor-ro\ntopic read meshcore-monitor/#\ntopic read $SYS/#\n'
} > "$NEW_ACL"

reader_count=0
while IFS= read -r reader_name && IFS= read -r reader_password; do
  add_user "$reader_name" "$reader_password"
  printf '\nuser %s\ntopic read meshcore/#\n' "$reader_name" >> "$NEW_ACL"
  reader_count=$((reader_count + 1))
done < "$PAIRS_FILE"

mkdir -p "$CONFIG_DIR"
cp "$NEW_PASSWD" "$PASSWD_FILE"
cp "$NEW_ACL" "$ACL_FILE"

docker run --rm --user 0:0 --entrypoint sh \
  -v "$DEPLOY_DIR/$CONFIG_DIR:/mosquitto/config" "$IMAGE" \
  -c 'chown root:root /mosquitto/config/passwd && chmod 644 /mosquitto/config/passwd'
chmod 644 "$ACL_FILE"
printf '%s' "$new_hash" > "$HASH_FILE"

echo "Regenerated $PASSWD_FILE and $ACL_FILE ($reader_count feed reader account(s) + 3 internal accounts)."
