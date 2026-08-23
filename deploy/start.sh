#!/bin/sh
# Container start script: generate config, sanitize inputs, exec the gateway.
# Keeps fragile quoting out of the Dockerfile CMD and tolerates platforms
# that inject odd PORT values (empty, non-numeric, URLs).
set -eu

/app/generate-config.sh

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
