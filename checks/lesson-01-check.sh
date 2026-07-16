#!/usr/bin/env bash
# Lesson 1: prerequisites. No stack needs to be running for this check.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 1: checking prerequisites"

require_command docker "install Docker: https://docs.docker.com/get-docker/"
require_command curl
require_command jq "install jq: https://jqlang.org/download/"

if command -v claude >/dev/null 2>&1; then
  pass "claude is installed"
  CLAUDE_VERSION="$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  MIN_VERSION="2.1.195"
  if [[ -z "$CLAUDE_VERSION" ]]; then
    fail "could not parse claude --version output" "run 'claude --version' manually and check the output"
  elif [[ "$(printf '%s\n%s\n' "$MIN_VERSION" "$CLAUDE_VERSION" | sort -V | head -1)" == "$MIN_VERSION" ]]; then
    pass "claude version $CLAUDE_VERSION >= $MIN_VERSION"
  else
    fail "claude version $CLAUDE_VERSION is older than required $MIN_VERSION" "run: claude update"
  fi
else
  fail "claude is not installed or not on PATH" "install the native claude binary, see https://code.claude.com/docs/en/setup"
fi

if docker compose version >/dev/null 2>&1; then
  pass "docker compose plugin is available"
else
  fail "docker compose (v2 plugin) is not available" "update Docker Desktop, or install the compose plugin: https://docs.docker.com/compose/install/"
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  pass "ANTHROPIC_API_KEY is set in this shell"
else
  fail "ANTHROPIC_API_KEY is not set in this shell" "copy .env.example to .env, set the key, then: export \$(grep -v '^#' .env | xargs)"
fi

finish
