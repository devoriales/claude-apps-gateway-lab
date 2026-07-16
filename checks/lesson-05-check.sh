#!/usr/bin/env bash
# Lesson 5: the gateway image builds, boots fail-closed, and serves its own
# OIDC discovery document.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 5: checking the gateway's boot sequence"

LOGS="$(docker compose logs gateway 2>&1)"

if echo "$LOGS" | grep -q "migration.*applied"; then
  pass "Postgres migrations applied"
else
  fail "no migration log lines found" "docker compose up -d gateway, then: docker compose logs gateway"
fi

if echo "$LOGS" | grep -q "claude gateway listening on"; then
  pass "gateway is listening"
else
  fail "gateway never logged 'listening on'" "the gateway boots fail-closed -- read the last line of: docker compose logs gateway"
  finish
fi

DISCOVERY="$(curl -s http://localhost:8080/.well-known/oauth-authorization-server 2>/dev/null)"
DEVICE_EP="$(echo "$DISCOVERY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('device_authorization_endpoint',''))" 2>/dev/null)"
if [[ "$DEVICE_EP" == "http://localhost:8080/oauth/device_authorization" ]]; then
  pass "gateway discovery document is correct"
else
  fail "gateway discovery document missing or wrong" "curl http://localhost:8080/.well-known/oauth-authorization-server"
fi

finish
