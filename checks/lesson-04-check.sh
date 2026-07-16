#!/usr/bin/env bash
# Lesson 4: Keycloak realm is up and its issuer is identical whether reached
# from the host (localhost) or from inside the compose network (keycloak
# hostname) -- the exact issuer-consistency point this lesson teaches.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 4: checking the Keycloak realm"

HOST_DISCOVERY="$(curl -s http://localhost:8180/realms/gateway-lab/.well-known/openid-configuration 2>/dev/null)"
if [[ -z "$HOST_DISCOVERY" ]]; then
  fail "no response from http://localhost:8180" "run: docker compose up -d keycloak, then check: docker compose logs keycloak"
  finish
fi

HOST_ISSUER="$(echo "$HOST_DISCOVERY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('issuer',''))" 2>/dev/null)"
if [[ "$HOST_ISSUER" == "http://localhost:8180/realms/gateway-lab" ]]; then
  pass "realm reachable from host at http://localhost:8180, issuer: $HOST_ISSUER"
else
  fail "unexpected issuer from host: '$HOST_ISSUER'" "check keycloak/realm-export.json and that the realm imported cleanly"
fi

CONTAINER_ISSUER="$(docker run --rm --network "$(basename "$(pwd)")_gateway-net" curlimages/curl:latest -s \
  http://keycloak:8180/realms/gateway-lab/.well-known/openid-configuration 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('issuer',''))" 2>/dev/null)"

if [[ "$CONTAINER_ISSUER" == "http://keycloak:8180/realms/gateway-lab" ]]; then
  pass "realm reachable from the compose network via hostname 'keycloak', issuer: $CONTAINER_ISSUER"
else
  fail "unexpected issuer from the compose network: '$CONTAINER_ISSUER'" "check that the keycloak service is on gateway-net and healthy: docker compose ps"
fi

echo ""
echo "Both issuers must be reachable for the gateway's OIDC discovery and"
echo "the browser sign-in redirect to agree. If you haven't yet, add this"
echo "line to /etc/hosts so your browser resolves 'keycloak' the same way"
echo "the gateway container does:"
echo "  127.0.0.1 keycloak"

finish
