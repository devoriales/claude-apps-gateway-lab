#!/usr/bin/env bash
# Lesson 11: full clean-state validation. Tears the stack down (including
# volumes), rebuilds it from scratch, and re-runs every automated check
# from Lesson 1 through Lesson 9 in order. Lesson 10 (Bedrock) is optional
# and requires your own AWS credentials, so it's excluded here -- run it
# separately if you did that lesson.
#
# What this script can't automate: signing in with your own browser via
# `claude /login` and running one real `claude` prompt. Do that manually
# after this script passes -- see the "Manual steps" note at the end.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 11: full end-to-end validation from a clean state"
echo ""

cd "$PROJECT_DIR"

echo "Tearing down (including volumes)..."
docker compose down -v >/dev/null 2>&1

echo "Building and starting the full stack..."
if ! docker compose up -d --build >/tmp/lesson11-up.log 2>&1; then
  fail "docker compose up failed" "see /tmp/lesson11-up.log"
  finish
fi

echo "Waiting for Postgres and Keycloak to report healthy..."
READY=0
for _ in $(seq 1 40); do
  PG_STATUS="$(docker inspect --format='{{.State.Health.Status}}' gateway-postgres 2>/dev/null)"
  KC_STATUS="$(docker inspect --format='{{.State.Health.Status}}' gateway-keycloak 2>/dev/null)"
  if [[ "$PG_STATUS" == "healthy" && "$KC_STATUS" == "healthy" ]]; then
    READY=1
    break
  fi
  sleep 3
done

if [[ "$READY" -ne 1 ]]; then
  fail "postgres and/or keycloak never became healthy" "docker compose ps; docker compose logs"
  finish
fi
pass "stack is up: postgres and keycloak healthy"

# Give the gateway a moment to finish its own boot after its dependencies
# reported healthy.
sleep 3

echo ""
echo "Running lessons 1-9 checks in order..."
echo ""

ANY_FAILED=0
for n in 01 02 03 04 05 06 07 08 09; do
  echo "--- lesson-$n ---"
  if ! "$SCRIPT_DIR/lesson-$n-check.sh"; then
    ANY_FAILED=1
  fi
  echo ""
done

if [[ "$ANY_FAILED" -eq 0 ]]; then
  pass "all automated checks (lessons 1-9) passed from a clean state"
else
  fail "one or more lesson checks failed" "scroll up to find which lesson failed and why"
fi

echo ""
echo "Manual steps (not automated by this script):"
echo "  1. Add '127.0.0.1 keycloak' to /etc/hosts if you haven't already."
echo "  2. Set forceLoginMethod: \"gateway\" and forceLoginGatewayUrl:"
echo "     \"http://localhost:8080\" in your managed-settings.json (see Lesson 6"
echo "     for the per-OS path)."
echo "  3. Run 'claude', then '/login', and approve the device code in your"
echo "     browser as alice."
echo "  4. Run 'claude -p \"say hi\"' and confirm you get a real response."
echo ""
echo "To tear everything down when you're done: docker compose down -v"

finish
