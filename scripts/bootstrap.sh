#!/usr/bin/env sh
set -eu

# One-shot bootstrap for a fresh Ubuntu server. Usage:
#
#   git clone git@github.com:wamidev/mqtt1-meshcore-deploy.git /opt/meshcore-mqtt-stack
#   cd /opt/meshcore-mqtt-stack
#   sudo ./scripts/bootstrap.sh
#
# Installs Docker, generates every internal service password, asks only for
# the handful of values that genuinely can't be generated locally (the
# Cloudflare Tunnel token and the other node's dedup-reader password), sets
# up feed-readers.env interactively, brings the stack up, and prepares the
# local half of the self-hosted GitHub Actions runner (user, groups, SSH
# deploy key). Only meant for a brand-new install: refuses to run if .env
# already exists.

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root, e.g. 'sudo ./scripts/bootstrap.sh'." >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$DEPLOY_DIR"

if [ -f .env ]; then
  echo ".env already exists - this looks like an already-configured install." >&2
  echo "Remove .env (and feed-readers.env, if you want to redo those too) to re-run this." >&2
  exit 1
fi

# ---------------------------------------------------------------- node ---

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
case "$REMOTE_URL" in
  *mqtt1-meshcore-deploy*) NODE=mqtt1 ;;
  *mqtt2-meshcore-deploy*) NODE=mqtt2 ;;
  *)
    printf 'Nepoznal jsem uzel z "git remote origin" (%s).\n' "$REMOTE_URL"
    printf 'Zadej mqtt1 nebo mqtt2: '
    read -r NODE
    ;;
esac
case "$NODE" in
  mqtt1) OTHER_NODE=mqtt2; SELF_SOURCE=1; OTHER_SOURCE=2 ;;
  mqtt2) OTHER_NODE=mqtt1; SELF_SOURCE=2; OTHER_SOURCE=1 ;;
  *) echo "Neplatný uzel '$NODE' (očekávám mqtt1 nebo mqtt2)." >&2; exit 1 ;;
esac
echo "==> Instaluji uzel: $NODE"

# --------------------------------------------------------- prerequisites ---

apt-get update -qq
apt-get install -y -qq openssl >/dev/null

echo "==> Instaluji Docker..."
./scripts/install-docker-ubuntu.sh

# ------------------------------------------------------------- helpers ---

genpass() { openssl rand -hex 20; }

set_env() {
  # set_env KEY VALUE - rewrites the "KEY=..." line in .env. Uses awk (not
  # sed) so the value is never interpreted as a regex/replacement pattern,
  # and passes it through ENVIRON rather than -v so awk doesn't decode
  # backslash escape sequences in it either - tokens and passwords can
  # safely contain any character.
  key=$1
  SET_ENV_VALUE=$2
  export SET_ENV_VALUE
  awk -v k="$key" '
    BEGIN { v = ENVIRON["SET_ENV_VALUE"]; done = 0 }
    $0 ~ "^" k "=" { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' .env > .env.tmp
  mv .env.tmp .env
  unset SET_ENV_VALUE
}

read_secret() {
  # read_secret PROMPT - reads a line without echoing it to the terminal.
  prompt=$1
  printf '%s' "$prompt" >&2
  stty -echo 2>/dev/null || true
  read -r REPLY_VALUE
  stty echo 2>/dev/null || true
  echo >&2
}

# ------------------------------------------------------------------ .env ---

cp ".env.${NODE}.example" .env

LOCAL_READER_PASSWORD=$(genpass)
LOCAL_WRITER_PASSWORD=$(genpass)
MONITOR_PASSWORD=$(genpass)
OWN_READER_PASSWORD=$(genpass)

set_env FEED_HEALTH_PASSWORD "$LOCAL_READER_PASSWORD"
set_env MQTT_LOCAL_DEDUP_READER_PASSWORD "$LOCAL_READER_PASSWORD"
set_env DEDUP_WRITER_PASSWORD "$LOCAL_WRITER_PASSWORD"
set_env MQTT_TARGET_PASSWORD "$LOCAL_WRITER_PASSWORD"
set_env MONITOR_MQTT_PASSWORD "$MONITOR_PASSWORD"
set_env MONITOR_RO_PASSWORD "$MONITOR_PASSWORD"
set_env PUBLIC_BROKER_READER_PASSWORD "$OWN_READER_PASSWORD"
set_env "MQTT_SOURCE_${SELF_SOURCE}_PASSWORD" "$OWN_READER_PASSWORD"

echo
echo "==> Potřebuju heslo dedup-reader z uzlu $OTHER_NODE - to je hodnota"
echo "    PUBLIC_BROKER_READER_PASSWORD v jeho .env. Pokud $OTHER_NODE ještě"
echo "    neběží, nech prázdné a doplň to do .env později ručně."
read_secret "Heslo dedup-reader pro $OTHER_NODE: "
OTHER_READER_PASSWORD_SET=0
if [ -n "$REPLY_VALUE" ]; then
  set_env "MQTT_SOURCE_${OTHER_SOURCE}_PASSWORD" "$REPLY_VALUE"
  OTHER_READER_PASSWORD_SET=1
fi

echo
read_secret "Cloudflare Tunnel token: "
set_env CLOUDFLARE_TUNNEL_TOKEN "$REPLY_VALUE"

# ------------------------------------------------------- feed-readers.env ---

: > feed-readers.env

echo
echo "==> Účty pro read-only přístup k deduplikovanému feedu (corescope-ro,"
echo "    map-ro, další) - hesla se vygenerují sama. Prázdné jméno = konec."
GENERATED_READERS=""
while :; do
  printf 'Jméno účtu (Enter pro konec): '
  read -r reader_name
  [ -z "$reader_name" ] && break
  case "$reader_name" in
    *[!A-Za-z0-9_-]*)
      echo "Jméno může obsahovat jen písmena, číslice, '-' a '_'." >&2
      continue
      ;;
  esac
  reader_password=$(genpass)
  printf '%s\n%s\n\n' "$reader_name" "$reader_password" >> feed-readers.env
  GENERATED_READERS="${GENERATED_READERS}  ${reader_name}: ${reader_password}
"
done

# --------------------------------------------------- deploy user & group ---

DEPLOY_GROUP=meshcore-deploy
getent group "$DEPLOY_GROUP" >/dev/null 2>&1 || groupadd "$DEPLOY_GROUP"
chgrp -R "$DEPLOY_GROUP" "$DEPLOY_DIR"
find "$DEPLOY_DIR" -type d -exec chmod g+rwx {} +
chmod 640 .env feed-readers.env

# So whoever ran this via sudo can keep editing .env/feed-readers.env
# afterwards without needing sudo for every read/edit.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  usermod -aG "$DEPLOY_GROUP" "$SUDO_USER"
fi

RUNNER_USER=gh-runner
RUNNER_HOME=/opt/github
if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "$RUNNER_HOME" --shell /usr/sbin/nologin "$RUNNER_USER"
fi
usermod -aG "$DEPLOY_GROUP" "$RUNNER_USER"
usermod -aG docker "$RUNNER_USER"
sudo -u "$RUNNER_USER" -H git config --global --add safe.directory "$DEPLOY_DIR"

mkdir -p "$RUNNER_HOME/.ssh"
chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/.ssh"
chmod 700 "$RUNNER_HOME/.ssh"
if [ ! -f "$RUNNER_HOME/.ssh/id_ed25519" ]; then
  sudo -u "$RUNNER_USER" -H ssh-keygen -t ed25519 -C "$NODE-deploy" -f "$RUNNER_HOME/.ssh/id_ed25519" -N ""
fi
sudo -u "$RUNNER_USER" -H sh -c "ssh-keyscan -t ed25519 github.com >> '$RUNNER_HOME/.ssh/known_hosts'"
chmod 600 "$RUNNER_HOME/.ssh/known_hosts"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/.ssh"
git remote set-url origin "git@github.com:wamidev/${NODE}-meshcore-deploy.git"

# --------------------------------------------------------------- deploy ---

echo
echo "==> Vytvářím účty Mosquitta a spouštím stack..."
./scripts/create-mosquitto-users.sh
./scripts/start.sh

# --------------------------------------------------------------- report ---

echo
echo "=============================================================="
echo " HOTOVO (automatická část). Ulož si vygenerovaná hesla feedu:"
echo "=============================================================="
if [ -n "$GENERATED_READERS" ]; then
  printf '%s' "$GENERATED_READERS"
else
  echo "  (žádný feed reader účet nebyl zadán)"
fi

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  echo
  echo "Uživatel $SUDO_USER byl přidán do skupiny $DEPLOY_GROUP (čtení/zápis"
  echo ".env a feed-readers.env bez sudo) - projeví se až po novém přihlášení."
fi

echo
echo "=============================================================="
echo " ZBÝVÁ RUČNĚ NA GITHUBU (repo wamidev/${NODE}-meshcore-deploy):"
echo "=============================================================="
echo
echo "1) Přidej SSH deploy key (READ-ONLY - nezatrhávej 'Allow write access'):"
echo "   https://github.com/wamidev/${NODE}-meshcore-deploy/settings/keys"
echo "   Veřejný klíč:"
echo
cat "$RUNNER_HOME/.ssh/id_ed25519.pub"
echo
echo "2) Zaregistruj self-hosted runner:"
echo "   https://github.com/wamidev/${NODE}-meshcore-deploy/settings/actions/runners/new"
echo "   Zvol Linux/x64, zkopíruj příkazy 'Download' a 'Configure', spusť je"
echo "   pod uživatelem $RUNNER_USER, např.:"
echo
echo "     sudo -u $RUNNER_USER -H sh -c '"
echo "       mkdir -p $RUNNER_HOME/actions-runner && cd $RUNNER_HOME/actions-runner"
echo "       <sem vlož curl/tar příkazy z GitHubu>"
echo "       ./config.sh --url https://github.com/wamidev/${NODE}-meshcore-deploy --token <TOKEN_Z_GITHUBU>"
echo "     '"
echo "     cd $RUNNER_HOME/actions-runner && ./svc.sh install $RUNNER_USER && ./svc.sh start"
if [ "$OTHER_READER_PASSWORD_SET" -eq 0 ]; then
  echo
  echo "3) Nezadal(a) jsi heslo dedup-reader pro $OTHER_NODE - doplň ho v .env"
  echo "   (MQTT_SOURCE_${OTHER_SOURCE}_PASSWORD) a spusť znovu:"
  echo "     ./scripts/start.sh"
fi
