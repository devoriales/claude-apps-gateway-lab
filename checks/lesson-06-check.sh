#!/usr/bin/env bash
# Lesson 6: the full device-authorization sign-in flow, end to end, as the
# alice user -- device code -> confirm -> Keycloak login -> callback ->
# token exchange -> a gateway session JWT carrying the right claims.
#
# This automates the same steps you just did by hand in a browser, using
# curl's --resolve flag instead of your /etc/hosts entry, so the check works
# even if you haven't (yet) added that entry.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 6: checking the full sign-in flow"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

RESP="$(curl -s -X POST http://localhost:8080/oauth/device_authorization)"
USER_CODE="$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)['user_code'])" 2>/dev/null)"
DEVICE_CODE="$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)['device_code'])" 2>/dev/null)"

if [[ -z "$USER_CODE" ]]; then
  fail "device authorization request failed" "curl -X POST http://localhost:8080/oauth/device_authorization"
  finish
fi
pass "device authorization returned a user code"

curl -s -c cookies.txt -b cookies.txt "http://localhost:8080/device?user_code=$USER_CODE" -o /dev/null

KC_AUTH_URL="$(curl -s -c cookies.txt -b cookies.txt -X POST "http://localhost:8080/device" \
  --data-urlencode "user_code=$USER_CODE" \
  -H "Origin: http://localhost:8080" \
  -H "Referer: http://localhost:8080/device?user_code=$USER_CODE" \
  -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"

if [[ -z "$KC_AUTH_URL" ]]; then
  fail "confirming the device code did not redirect to Keycloak" "hint: if you've been re-running this check a lot, you may have hit the gateway's per-IP device_verify rate limit (10 per 10 minutes) -- wait, or docker compose down -v && docker compose up -d to reset it"
  finish
fi
pass "device confirm redirected to Keycloak"

curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 "$KC_AUTH_URL" -o kc_login.html
FORM_ACTION="$(python3 -c "
import re
html = open('kc_login.html').read()
m = re.search(r'<form[^>]*id=\"kc-form-login\"[^>]*action=\"([^\"]*)\"', html)
print(m.group(1).replace('&amp;','&') if m else '')
")"

if [[ -z "$FORM_ACTION" ]]; then
  fail "could not find Keycloak's login form" "curl --resolve keycloak:8180:127.0.0.1 '<the auth URL>' and inspect the response"
  finish
fi

CALLBACK_LOCATION="$(curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 \
  -X POST "$FORM_ACTION" \
  --data-urlencode "username=alice" \
  --data-urlencode "password=alice-dev-pass1" \
  --data-urlencode "credentialId=" \
  -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"

if [[ "$CALLBACK_LOCATION" != http://localhost:8080/oauth/callback* ]]; then
  fail "Keycloak login did not redirect back to the gateway callback" "check keycloak/realm-export.json: user 'alice' must exist with password 'alice-dev-pass1' and no pending required actions"
  finish
fi
pass "Keycloak accepted alice's credentials and redirected to the gateway callback"

# The gateway binds the callback to the gw_dev session cookie set during the
# /device confirm step; carry the same cookie jar or it rejects as a
# browser-mismatch.
curl -s -c cookies.txt -b cookies.txt "$CALLBACK_LOCATION" -o /dev/null

TOKEN_RESP="$(curl -s -X POST http://localhost:8080/oauth/token \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
  --data-urlencode "device_code=$DEVICE_CODE" \
  --data-urlencode "client_id=claude-code")"

ACCESS_TOKEN="$(echo "$TOKEN_RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)"
if [[ -z "$ACCESS_TOKEN" ]]; then
  fail "token exchange did not return an access token" "response was: $TOKEN_RESP"
  finish
fi
pass "gateway minted a session token for alice"

# Decide pass/fail inside Python itself and report via exit code, rather
# than round-tripping the decoded claim back through a shell variable.
GROUPS_CHECK_OUTPUT="$(python3 -c "
import sys, base64, json
token = sys.argv[1]
payload = token.split('.')[1]
payload += '=' * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
groups = claims.get('groups', [])
if groups == ['developers']:
    print('OK ' + json.dumps(groups))
    sys.exit(0)
else:
    print('MISMATCH ' + json.dumps(groups))
    sys.exit(1)
" "$ACCESS_TOKEN")"
GROUPS_CHECK_STATUS=$?

if [[ "$GROUPS_CHECK_STATUS" -eq 0 ]]; then
  pass "session token carries the correct groups claim: ${GROUPS_CHECK_OUTPUT#OK }"
else
  fail "unexpected groups claim: ${GROUPS_CHECK_OUTPUT#MISMATCH }" "check the group-membership protocol mapper on the claude-gateway client in keycloak/realm-export.json"
fi

finish
