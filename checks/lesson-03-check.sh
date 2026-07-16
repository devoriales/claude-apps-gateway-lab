#!/usr/bin/env bash
# Lesson 3: Postgres is up, healthy, and its data survives a restart.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "Lesson 3: checking the Postgres service"

if docker compose exec -T postgres pg_isready -U gateway -d gateway >/dev/null 2>&1; then
  pass "postgres is accepting connections"
else
  fail "postgres is not reachable" "run: docker compose up -d postgres, then check: docker compose logs postgres"
  finish
fi

MARKER_VALUE="check-$$"
docker compose exec -T postgres psql -U gateway -d gateway -c \
  "CREATE TABLE IF NOT EXISTS lesson03_marker (v text); DELETE FROM lesson03_marker; INSERT INTO lesson03_marker VALUES ('$MARKER_VALUE');" \
  >/dev/null 2>&1

docker compose restart postgres >/dev/null 2>&1

READY=0
for _ in $(seq 1 15); do
  if docker compose exec -T postgres pg_isready -U gateway -d gateway >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done

if [[ "$READY" -ne 1 ]]; then
  fail "postgres did not come back healthy after restart" "check: docker compose logs postgres"
  finish
fi

READBACK="$(docker compose exec -T postgres psql -U gateway -d gateway -tAc "SELECT v FROM lesson03_marker;" 2>/dev/null | tr -d '[:space:]')"
if [[ "$READBACK" == "$MARKER_VALUE" ]]; then
  pass "data persists across a postgres restart (volume is correctly mounted)"
else
  fail "data did not survive the restart" "check the volumes: mount in docker-compose.yml — PostgreSQL 18 images expect the volume at /var/lib/postgresql, not /var/lib/postgresql/data"
fi

finish
