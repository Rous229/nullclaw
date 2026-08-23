#!/bin/sh
# Container start script.
#
# Startup strategy for platforms with aggressive health probes:
#   Phase 1: a health shim answers instantly on the public port while the
#            gateway initializes (WAN Postgres connections take seconds).
#   Phase 2: once the gateway listens on the internal port, the shim is
#            replaced by a TCP proxy forwarding public port -> gateway.
# Secrets are never logged. All timeouts are bounded so startup can hang
# only on nullclaw itself, never on our diagnostics.
set -eu

/app/generate-config.sh

PORT_NUM="${NULLCLAW_GATEWAY_PORT:-${PORT:-3000}}"
case "$PORT_NUM" in
  ''|*[!0-9]*) PORT_NUM=3000 ;;
esac
if [ "$PORT_NUM" -lt 1 ] || [ "$PORT_NUM" -gt 65535 ]; then
  PORT_NUM=3000
fi
INTERNAL_PORT=$((PORT_NUM + 1))
[ "$INTERNAL_PORT" -gt 65535 ] && INTERNAL_PORT=3001

# ── Diagnostics (no secret values) ────────────────────────────
CONFIG="${NULLCLAW_CONFIG_PATH:-/nullclaw-data/config.json}"
if [ -f "$CONFIG" ]; then
  BACKEND=$(sed -n 's/.*"backend": "\([^"]*\)".*/\1/p' "$CONFIG" | head -1)
  echo "nullclaw-start: memory backend = ${BACKEND:-<none>}"
fi
if [ -n "${NULLCLAW_MEMORY_POSTGRES_URL:-}" ]; then
  HOSTPORT=$(printf '%s' "$NULLCLAW_MEMORY_POSTGRES_URL" | sed -E 's|^[a-zA-Z]+://[^@]*@||; s|/.*$||')
  PGHOST=${HOSTPORT%%:*}
  PGPORT=${HOSTPORT##*:}
  [ "$PGPORT" = "$PGHOST" ] && PGPORT=5432
  echo "nullclaw-start: PG target $PGHOST:$PGPORT"
  if command -v getent >/dev/null 2>&1 && [ -n "$PGHOST" ]; then
    PGIP=$(getent ahostsv4 "$PGHOST" 2>/dev/null | awk '{print $1; exit}')
    if [ -n "$PGIP" ]; then
      printf '%s %s\n' "$PGIP" "$PGHOST" >> /etc/hosts 2>/dev/null || true
      echo "nullclaw-start: pinned $PGHOST -> $PGIP"
    fi
  fi
else
  echo "nullclaw-start: NULLCLAW_MEMORY_POSTGRES_URL not set"
fi

cleanup() {
  [ -n "${SHIM_PID:-}" ] && kill "$SHIM_PID" 2>/dev/null || true
  [ -n "${GW_PID:-}" ] && kill "$GW_PID" 2>/dev/null || true
  [ -n "${PROXY_PID:-}" ] && kill "$PROXY_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── Phase 1: instant health shim on the public port ───────────
socat "TCP-LISTEN:$PORT_NUM,bind=0.0.0.0,fork,reuseaddr" SYSTEM:'/app/health-shim.sh' &
SHIM_PID=$!
echo "nullclaw-start: health shim live on :$PORT_NUM"

# ── Gateway on the internal port ──────────────────────────────
nullclaw gateway --port "$INTERNAL_PORT" --host 127.0.0.1 &
GW_PID=$!

# ── Wait until the gateway answers locally (bounded) ──────────
i=0
while [ "$i" -lt 120 ]; do
  if ! kill -0 "$GW_PID" 2>/dev/null; then
    echo "nullclaw-start: gateway process exited early"
    exit 1
  fi
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:$INTERNAL_PORT/health" || true)
  [ "$CODE" = "200" ] && break
  i=$((i + 1))
  sleep 1
done

if [ "$CODE" != "200" ]; then
  echo "nullclaw-start: gateway did not become ready within 120s"
  exit 1
fi
echo "nullclaw-start: gateway ready after ${i}s (internal :$INTERNAL_PORT)"

# ── Phase 2: swap shim for the TCP proxy ──────────────────────
kill "$SHIM_PID" 2>/dev/null || true
wait "$SHIM_PID" 2>/dev/null || true
socat "TCP-LISTEN:$PORT_NUM,bind=0.0.0.0,fork,reuseaddr" "TCP4:127.0.0.1:$INTERNAL_PORT" &
PROXY_PID=$!
echo "nullclaw-start: proxying :$PORT_NUM -> :$INTERNAL_PORT"

wait "$GW_PID"
