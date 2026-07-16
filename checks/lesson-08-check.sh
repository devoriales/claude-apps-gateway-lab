#!/usr/bin/env bash
# Lesson 8: spend limits admin API. Sets a deterministic zero-cap ("amount":
# "0" blocks every request in that period) on alice only, and confirms it
# blocks her with 429 while leaving bob untouched -- no real inference spend
# needed to prove enforcement works.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 8: checking spend-limit enforcement"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

ADMIN_KEY="${GATEWAY_ADMIN_KEY:-dev-only-gateway-admin-write-key-32ch}"

sign_in() {
  local username="$1" password="$2"
  local resp user_code device_code kc_auth_url form_action callback_location token_resp

  resp="$(curl -s -X POST http://localhost:8080/oauth/device_authorization)"
  user_code="$(python3 -c "import json,sys;print(json.load(sys.stdin)['user_code'])" <<< "$resp")"
  device_code="$(python3 -c "import json,sys;print(json.load(sys.stdin)['device_code'])" <<< "$resp")"

  curl -s -c cookies.txt -b cookies.txt "http://localhost:8080/device?user_code=$user_code" -o /dev/null

  kc_auth_url="$(curl -s -c cookies.txt -b cookies.txt -X POST "http://localhost:8080/device" \
    --data-urlencode "user_code=$user_code" \
    -H "Origin: http://localhost:8080" \
    -H "Referer: http://localhost:8080/device?user_code=$user_code" \
    -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"
  [[ -z "$kc_auth_url" ]] && return 1

  curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 "$kc_auth_url" -o kc_login.html
  form_action="$(python3 -c "
import re
html = open('kc_login.html').read()
m = re.search(r'<form[^>]*id=\"kc-form-login\"[^>]*action=\"([^\"]*)\"', html)
print(m.group(1).replace('&amp;','&') if m else '')
")"
  [[ -z "$form_action" ]] && return 1

  callback_location="$(curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 \
    -X POST "$form_action" \
    --data-urlencode "username=$username" \
    --data-urlencode "password=$password" \
    --data-urlencode "credentialId=" \
    -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"
  [[ "$callback_location" != http://localhost:8080/oauth/callback* ]] && return 1

  curl -s -c cookies.txt -b cookies.txt "$callback_location" -o /dev/null

  token_resp="$(curl -s -X POST http://localhost:8080/oauth/token \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
    --data-urlencode "device_code=$device_code" \
    --data-urlencode "client_id=claude-code")"
  python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))" <<< "$token_resp"
}

request_status() {
  local token="$1"
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/v1/messages \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
}

ALICE_TOKEN="$(sign_in alice alice-dev-pass1)"
if [[ -z "$ALICE_TOKEN" ]]; then
  fail "could not sign in as alice" "run lesson-06's check first to confirm sign-in works at all"
  finish
fi
pass "signed in as alice"

STATUS="$(request_status "$ALICE_TOKEN")"
if [[ "$STATUS" != "429" ]]; then
  pass "alice is not spend-limited before setting a cap (got $STATUS)"
else
  fail "alice was already blocked with 429 before any cap was set" "check for a leftover cap: GET /v1/organizations/spend_limits"
fi

ALICE_SUB="$(python3 -c "
import sys, base64, json
token = sys.argv[1]
payload = token.split('.')[1]
payload += '=' * (-len(payload) % 4)
print(json.loads(base64.urlsafe_b64decode(payload))['sub'])
" "$ALICE_TOKEN")"

CAP_RESP="$(curl -s -X POST http://localhost:8080/v1/organizations/spend_limits \
  -H "x-api-key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"scope\": {\"type\": \"user\", \"user_id\": \"$ALICE_SUB\"}, \"amount\": \"0\", \"period\": \"daily\"}")"
CAP_ID="$(python3 -c "import json,sys;print(json.load(sys.stdin).get('id',''))" <<< "$CAP_RESP")"

if [[ -z "$CAP_ID" ]]; then
  fail "admin API did not return a spend_limit id" "response was: $CAP_RESP -- check admin.write_keys in gateway/gateway.yaml matches GATEWAY_ADMIN_KEY"
  finish
fi
pass "admin API created a zero-cap for alice: $CAP_ID"

STATUS="$(request_status "$ALICE_TOKEN")"
if [[ "$STATUS" == "429" ]]; then
  pass "alice is now blocked with 429 (spend limit reached)"
else
  fail "expected 429 after setting alice's zero-cap, got $STATUS" "check the admin block and enforcement logic"
fi

rm -f cookies.txt kc_cookies.txt
BOB_TOKEN="$(sign_in bob bob-dev-pass1)"
if [[ -n "$BOB_TOKEN" ]]; then
  STATUS="$(request_status "$BOB_TOKEN")"
  if [[ "$STATUS" != "429" ]]; then
    pass "bob is unaffected by alice's per-user cap (got $STATUS, not 429)"
  else
    fail "bob was unexpectedly blocked by alice's cap" "spend_limits scope should be user-specific, not organization-wide"
  fi
else
  fail "could not sign in as bob to verify cap scoping" ""
fi

curl -s -X DELETE "http://localhost:8080/v1/organizations/spend_limits/$CAP_ID" \
  -H "x-api-key: $ADMIN_KEY" -o /dev/null

finish
