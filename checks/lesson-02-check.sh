#!/usr/bin/env bash
# Lesson 2: container runtime introduction. Conceptual lesson -- the check
# just confirms whatever OCI-compatible engine the student has can pull and
# inspect an image, regardless of whether it's Docker or Podman.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 2: checking your container engine"

ENGINE=""
if command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
elif command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
fi

if [[ -z "$ENGINE" ]]; then
  fail "neither docker nor podman found on PATH" "install one: https://docs.docker.com/get-docker/ or https://podman.io/docs/installation"
  finish
fi
pass "found container engine: $ENGINE"

if "$ENGINE" image inspect postgres:18.4-alpine >/dev/null 2>&1; then
  pass "$ENGINE can inspect an already-pulled OCI image"
elif "$ENGINE" pull postgres:18.4-alpine >/dev/null 2>&1; then
  pass "$ENGINE pulled and can inspect an OCI image"
else
  fail "$ENGINE could not pull postgres:18.4-alpine" "check your network connection and that $ENGINE's daemon/service is running"
fi

finish
