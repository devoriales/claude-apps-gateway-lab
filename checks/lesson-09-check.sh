#!/usr/bin/env bash
# Lesson 9: telemetry fan-out. Signs in as alice, posts one OTLP metric to
# the gateway's /v1/metrics ingestion endpoint (the same endpoint the real
# claude CLI posts to once telemetry is on), and confirms it shows up in
# the collector's debug output -- proving the full relay path works.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 9: checking telemetry fan-out"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

RESP="$(curl -s -X POST http://localhost:8080/oauth/device_authorization)"
USER_CODE="$(python3 -c "import json,sys;print(json.load(sys.stdin)['user_code'])" <<< "$RESP")"
DEVICE_CODE="$(python3 -c "import json,sys;print(json.load(sys.stdin)['device_code'])" <<< "$RESP")"

curl -s -c cookies.txt -b cookies.txt "http://localhost:8080/device?user_code=$USER_CODE" -o /dev/null

KC_AUTH_URL="$(curl -s -c cookies.txt -b cookies.txt -X POST "http://localhost:8080/device" \
  --data-urlencode "user_code=$USER_CODE" \
  -H "Origin: http://localhost:8080" \
  -H "Referer: http://localhost:8080/device?user_code=$USER_CODE" \
  -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"

if [[ -z "$KC_AUTH_URL" ]]; then
  fail "could not start a sign-in flow" "run lesson-06's check first"
  finish
fi

curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 "$KC_AUTH_URL" -o kc_login.html
FORM_ACTION="$(python3 -c "
import re
html = open('kc_login.html').read()
m = re.search(r'<form[^>]*id=\"kc-form-login\"[^>]*action=\"([^\"]*)\"', html)
print(m.group(1).replace('&amp;','&') if m else '')
")"

CALLBACK_LOCATION="$(curl -s -c kc_cookies.txt -b kc_cookies.txt --resolve keycloak:8180:127.0.0.1 \
  -X POST "$FORM_ACTION" \
  --data-urlencode "username=alice" \
  --data-urlencode "password=alice-dev-pass1" \
  --data-urlencode "credentialId=" \
  -o /dev/null -D - | grep -i '^location:' | tr -d '\r' | sed -E 's/^[Ll]ocation: //')"

curl -s -c cookies.txt -b cookies.txt "$CALLBACK_LOCATION" -o /dev/null

TOKEN_RESP="$(curl -s -X POST http://localhost:8080/oauth/token \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
  --data-urlencode "device_code=$DEVICE_CODE" \
  --data-urlencode "client_id=claude-code")"
ACCESS_TOKEN="$(python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))" <<< "$TOKEN_RESP")"

if [[ -z "$ACCESS_TOKEN" ]]; then
  fail "could not sign in as alice" "run lesson-06's check first to confirm sign-in works at all"
  finish
fi
pass "signed in as alice"

MARKER="lesson09-$$-$(date +%s)"
cat > otlp_metrics.json <<EOF
{
  "resourceMetrics": [
    {
      "resource": {"attributes": []},
      "scopeMetrics": [
        {
          "scope": {"name": "$MARKER"},
          "metrics": [
            {
              "name": "claude_code.token.usage",
              "sum": {
                "dataPoints": [{"asInt": "1", "timeUnixNano": "1752300000000000000"}],
                "aggregationTemporality": 2,
                "isMonotonic": true
              }
            }
          ]
        }
      ]
    }
  ]
}
EOF

STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/v1/metrics \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @otlp_metrics.json)"

if [[ "$STATUS" != "200" ]]; then
  fail "gateway rejected the OTLP metrics POST: $STATUS" "check telemetry.forward_to in gateway/gateway.yaml"
  finish
fi
pass "gateway accepted the OTLP metrics POST"

FOUND=0
for _ in $(seq 1 10); do
  if (cd "$PROJECT_DIR" && docker compose logs otel-collector) 2>&1 | grep -q "$MARKER"; then
    FOUND=1
    break
  fi
  sleep 1
done

if [[ "$FOUND" -eq 1 ]]; then
  pass "the metric reached the otel-collector's debug exporter"
else
  fail "metric never showed up in otel-collector logs" "check: docker compose logs gateway | grep -i otel -- the gateway's SSRF guard blocks loopback connections unless CLAUDE_GATEWAY_ALLOW_LOOPBACK=1 is set"
fi

finish
