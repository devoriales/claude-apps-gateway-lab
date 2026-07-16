#!/usr/bin/env bash
# Lesson 7: RBAC via managed.policies. alice (developers) is denied
# claude-opus-4-8 with a 400 before the request ever reaches the upstream;
# bob (platform-admins) is granted it (a 401 here just means our placeholder
# ANTHROPIC_API_KEY was rejected upstream -- the policy gate already passed).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 7: checking RBAC policy enforcement"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

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

request_model() {
  local token="$1" model="$2"
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/v1/messages \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"$model\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
}

ALICE_TOKEN="$(sign_in alice alice-dev-pass1)"
if [[ -z "$ALICE_TOKEN" ]]; then
  fail "could not sign in as alice" "run lesson-06's check first to confirm sign-in works at all"
  finish
fi
pass "signed in as alice"

STATUS="$(request_model "$ALICE_TOKEN" claude-opus-4-8)"
if [[ "$STATUS" == "400" ]]; then
  pass "alice (developers) is denied claude-opus-4-8: 400"
else
  fail "expected 400 denying alice claude-opus-4-8, got $STATUS" "check managed.policies match: {groups: [developers]} in gateway/gateway.yaml"
fi

STATUS="$(request_model "$ALICE_TOKEN" claude-haiku-4-5)"
if [[ "$STATUS" != "400" ]]; then
  pass "alice (developers) passes the policy gate for claude-haiku-4-5 (got $STATUS, not 400)"
else
  fail "alice was denied claude-haiku-4-5, which should be in her allowlist" "check availableModels for the developers policy"
fi

rm -f cookies.txt kc_cookies.txt

BOB_TOKEN="$(sign_in bob bob-dev-pass1)"
if [[ -z "$BOB_TOKEN" ]]; then
  fail "could not sign in as bob" "check keycloak/realm-export.json: user 'bob' in group /platform-admins"
  finish
fi
pass "signed in as bob"

STATUS="$(request_model "$BOB_TOKEN" claude-opus-4-8)"
if [[ "$STATUS" != "400" ]]; then
  pass "bob (platform-admins) passes the policy gate for claude-opus-4-8 (got $STATUS, not 400)"
else
  fail "bob was denied claude-opus-4-8, which should be in his allowlist" "check availableModels for the platform-admins policy"
fi

finish
