#!/bin/sh
set -e
PUID="${PUID:-99}"; PGID="${PGID:-100}"; UMASK="${UMASK:-022}"
RUN_USER=bun

if [ "$(id -u)" = "0" ]; then
  # group: reuse an existing group with PGID (e.g. 'users' 100), else remap 'bun' group
  if getent group "$PGID" >/dev/null; then
    RUN_GROUP="$(getent group "$PGID" | cut -d: -f1)"
  else
    groupmod -o -g "$PGID" bun; RUN_GROUP=bun
  fi
  # user: remap 'bun' to PUID (-o allows a UID already in use, e.g. 99 'nobody')
  [ "$(id -u bun)" = "$PUID" ] || usermod -o -u "$PUID" bun
  usermod -g "$RUN_GROUP" bun
  mkdir -p /data /data/output /config /home/bun/.bun/install/cache
  # /input is normally a read-only bind mount; create/chown it only when possible
  mkdir -p /input 2>/dev/null || true
  if [ -w /input ] && [ "$(stat -c '%u:%g' /input)" != "$PUID:$PGID" ]; then
    chown "$PUID:$PGID" /input 2>/dev/null || echo "[entrypoint] note: could not chown /input (read-only mount?)"
  fi
  for d in /data /data/output /config /home/bun; do
    if [ "$(stat -c '%u:%g' "$d")" != "$PUID:$PGID" ]; then
      echo "[entrypoint] fixing ownership of $d -> $PUID:$PGID"
      chown -R "$PUID:$PGID" "$d"
    fi
  done
  umask "$UMASK"
  export HOME=/home/bun
  exec setpriv --reuid="$PUID" --regid="$PGID" --init-groups /bin/sh "$0" "$@"
fi

umask "$UMASK"
export HOME="${HOME:-/home/bun}"
mkdir -p "$DATA_DIR" "$DATA_DIR/output" /config
# Persistent defaults for files upstream reads from its working directory / SLEEP_PRIVILEGED_FILE
[ -e /config/mcpl-servers.json ] || { printf '{\n  "mcplServers": {}\n}\n' > /config/mcpl-servers.json; echo "[entrypoint] created /config/mcpl-servers.json"; }
SLEEP_PRIVILEGED_FILE="${SLEEP_PRIVILEGED_FILE:-/config/sleep-privileged.json}"; export SLEEP_PRIVILEGED_FILE
[ -e "$SLEEP_PRIVILEGED_FILE" ] || { printf '[]\n' > "$SLEEP_PRIVILEGED_FILE"; echo "[entrypoint] created $SLEEP_PRIVILEGED_FILE"; }
case "$(echo "${REGENERATE_RECIPE:-false}" | tr A-Z a-z)" in
  true|1|yes)
    if [ -f /config/recipe.json ]; then
      bak="/config/recipe.json.bak.$(date +%Y%m%d-%H%M%S)"
      mv /config/recipe.json "$bak"
      echo "[entrypoint] REGENERATE_RECIPE=true: backed up old recipe to $bak"
    fi ;;
esac
if [ ! -f /config/recipe.json ]; then
  echo "[entrypoint] /config/recipe.json missing; generating default recipe for PROVIDER=${PROVIDER:-anthropic}"
  if ! bun /app/docker/gen-recipe.ts /config/recipe.json; then
    echo "[entrypoint] recipe generation failed; fix the settings above and restart." >&2
    exit 1
  fi
else
  echo "[entrypoint] using existing /config/recipe.json (provider: $(bun -e 'try{const r=JSON.parse(require("fs").readFileSync("/config/recipe.json","utf8"));console.log(r.agent?.provider??"anthropic")}catch{console.log("unreadable")}'))"
fi
RECIPE="${RECIPE:-/config/recipe.json}"
# BASE_URL is a single field for whichever provider is in use: openai-compatible
# gets it as agent.baseUrl in the generated recipe; the others via upstream's env vars.
if [ -n "$BASE_URL" ]; then
  prov="$(bun -e 'try{const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(r.agent?.provider??"anthropic")}catch{console.log(process.env.PROVIDER||"anthropic")}' "$RECIPE" 2>/dev/null || echo "${PROVIDER:-anthropic}")"
  case "$prov" in
    anthropic) : "${ANTHROPIC_BASE_URL:=$BASE_URL}"; export ANTHROPIC_BASE_URL; echo "[entrypoint] ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" ;;
    openai-responses) : "${OPENAI_BASE_URL:=$BASE_URL}"; export OPENAI_BASE_URL; echo "[entrypoint] OPENAI_BASE_URL=$OPENAI_BASE_URL" ;;
    bedrock) : "${BEDROCK_BASE_URL:=$BASE_URL}"; export BEDROCK_BASE_URL; echo "[entrypoint] BEDROCK_BASE_URL=$BEDROCK_BASE_URL" ;;
    openai-compatible) ;;
    *) echo "[entrypoint] note: BASE_URL is ignored for provider $prov" ;;
  esac
fi
[ "$#" -eq 0 ] && set -- "$RECIPE" --headless
echo "[entrypoint] running as $(id -u):$(id -g) umask $(umask)"
exec bun /app/src/index.ts "$@"
