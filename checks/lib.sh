#!/usr/bin/env bash
# Shared helpers for lesson check scripts. Source this, don't execute it.

CHECK_FAILED=0

pass() {
  echo "  PASS: $1"
}

fail() {
  echo "  FAIL: $1"
  if [[ -n "${2:-}" ]]; then
    echo "        hint: $2"
  fi
  CHECK_FAILED=1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is not installed or not on PATH" "${2:-install $1 and re-run this check}"
    return 1
  fi
  pass "$1 is installed"
  return 0
}

finish() {
  if [[ "$CHECK_FAILED" -eq 0 ]]; then
    echo ""
    echo "All checks passed."
    exit 0
  else
    echo ""
    echo "One or more checks failed. Fix the issues above and re-run this script."
    exit 1
  fi
}
