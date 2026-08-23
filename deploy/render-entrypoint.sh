#!/bin/sh
# Generate NullClaw config.json on boot when no config file exists yet.
#
# Design (Render deployment):
# - Non-secret defaults live in this script; secrets are injected by the
#   platform as environment variables and NEVER logged nor committed.
# - If a config file already exists (persistent disk, manual setup), it is
#   left untouched.
#
# Environment variables (all optional unless noted):
#   NULLCLAW_CONFIG_PATH            target file (default /nullclaw-data/config.json)
#   NULLCLAW_MODEL                  primary model (default agnes/agnes-2.5-flash)
#   AGNES_BASE_URL                  Agnes AI endpoint (default https://apihub.agnes-ai.com/v1)
#   NULLCLAW_API_KEY                resolved by nullclaw itself at request time (not written here)
#   NULLCLAW_MEMORY_POSTGRES_URL    when set: switch memory backend to postgres (Supabase)
#   NULLCLAW_TELEGRAM_BOT_TOKEN     when set: enable the Telegram channel
#   NULLCLAW_TELEGRAM_WEBHOOK_SECRET  optional Telegram webhook secret
#   NULLCLAW_TELEGRAM_ALLOW_FROM    comma-separated Telegram user IDs allowlist
set -eu

CONFIG="${NULLCLAW_CONFIG_PATH:-/nullclaw-data/config.json}"

# An existing config is respected EXCEPT when platform-injected secrets are
# present: those must take effect at every boot.
if [ -f "$CONFIG" ]; then
  case "${NULLCLAW_MEMORY_POSTGRES_URL:-}${NULLCLAW_TELEGRAM_BOT_TOKEN:-}" in
    "") exit 0 ;;
    *) rm -f "$CONFIG" ;;
  esac
fi

MODEL=$(printf '%s' "${NULLCLAW_MODEL:-agnes/agnes-2.5-flash}" | sed 's/\\/\\\\/g; s/"/\\"/g')
AGNES_URL=$(printf '%s' "${AGNES_BASE_URL:-https://apihub.agnes-ai.com/v1}" | sed 's/\\/\\\\/g; s/"/\\"/g')

mkdir -p "$(dirname "$CONFIG")"

{
  printf '{\n'
  printf '  "agents": {"defaults": {"model": {"primary": "%s"}}},\n' "$MODEL"
  printf '  "models": {"providers": {"agnes": {"base_url": "%s"}, "openrouter": {}}},\n' "$AGNES_URL"
  printf '  "gateway": {"port": 3000, "host": "::", "allow_public_bind": true}'

  if [ -n "${NULLCLAW_MEMORY_POSTGRES_URL:-}" ]; then
    PG_URL=$(printf '%s' "$NULLCLAW_MEMORY_POSTGRES_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf ',\n  "memory": {"backend": "postgres", "auto_save": true, "postgres": {"url": "%s", "schema": "public", "table": "memories"}}' "$PG_URL"
  fi

  if [ -n "${NULLCLAW_TELEGRAM_BOT_TOKEN:-}" ]; then
    TG_TOKEN=$(printf '%s' "$NULLCLAW_TELEGRAM_BOT_TOKEN" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf ',\n  "channels": {"cli": true, "telegram": {"accounts": {"main": {"bot_token": "%s"' "$TG_TOKEN"
    if [ -n "${NULLCLAW_TELEGRAM_WEBHOOK_SECRET:-}" ]; then
      TG_SECRET=$(printf '%s' "$NULLCLAW_TELEGRAM_WEBHOOK_SECRET" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf ', "webhook_secret": "%s"' "$TG_SECRET"
    fi
    if [ -n "${NULLCLAW_TELEGRAM_ALLOW_FROM:-}" ]; then
      printf ', "allow_from": ['
      OLD_IFS=$IFS
      IFS=','
      first=1
      for id in $NULLCLAW_TELEGRAM_ALLOW_FROM; do
        id=$(printf '%s' "$id" | tr -d ' \t')
        [ -n "$id" ] || continue
        [ "$first" -eq 1 ] || printf ', '
        printf '"%s"' "$id"
        first=0
      done
      IFS=$OLD_IFS
      printf ']'
    fi
    printf '}}}}'
  fi

  printf '\n}\n'
} > "$CONFIG"

echo "nullclaw: generated $CONFIG"
