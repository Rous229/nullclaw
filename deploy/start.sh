#!/bin/sh
# Container start script: generate config, sanitize inputs, exec the gateway.
# Keeps fragile quoting out of the Dockerfile CMD and tolerates platforms
# that inject odd PORT values (empty, non-numeric, URLs).
set -eu

/app/generate-config.sh

# ── Boot diagnostics (never print secret values) ──────────────
if [ -f "${NULLCLAW_CONFIG_PATH:-/nullclaw-data/config.json}" ]; then
  BACKEND=$(sed -n 's/.*"backend": "\([^"]*\)".*/\1/p' "${NULLCLAW_CONFIG_PATH:-/nullclaw-data/config.json}" | head -1)
  echo "nullclaw-start: memory backend = ${BACKEND:-<none>}"
else
  echo "nullclaw-start: WARNING no config file found"
fi
if [ -n "${NULLCLAW_MEMORY_POSTGRES_URL:-}" ]; then
  HOSTPORT=$(printf '%s' "$NULLCLAW_MEMORY_POSTGRES_URL" | sed -E 's|^[a-zA-Z]+://[^@]*@||; s|/.*$||')
  PGHOST=${HOSTPORT%%:*}
  PGPORT=${HOSTPORT##*:}
  [ "$PGPORT" = "$PGHOST" ] && PGPORT=5432
  echo "nullclaw-start: PG target $PGHOST:$PGPORT"
  if timeout 6 bash -c "exec 3<>/dev/tcp/$PGHOST/$PGPORT" 2>/dev/null; then
    echo "nullclaw-start: PG reachable"
  else
    echo "nullclaw-start: PG UNREACHABLE"
  fi
else
  echo "nullclaw-start: NULLCLAW_MEMORY_POSTGRES_URL not set"
fi

PORT_NUM="${NULLCLAW_GATEWAY_PORT:-${PORT:-3000}}"
# Accept plain numbers only; anything else falls back to 3000.
case "$PORT_NUM" in
  ''|*[!0-9]*) PORT_NUM=3000 ;;
esac
# Clamp to valid TCP range.
if [ "$PORT_NUM" -lt 1 ] || [ "$PORT_NUM" -gt 65535 ]; then
  PORT_NUM=3000
fi

HOST="${NULLCLAW_GATEWAY_HOST:-::}"
case "$HOST" in
  '') HOST='::' ;;
esac

echo "nullclaw: starting gateway on [$HOST]:$PORT_NUM"
exec nullclaw gateway --port "$PORT_NUM" --host "$HOST"
