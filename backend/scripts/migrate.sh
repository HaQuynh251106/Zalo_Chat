#!/usr/bin/env bash
# Apply SQL migrations to $DATABASE_URL (default: docker-compose Postgres).
set -euo pipefail

DB_URL="${DATABASE_URL:-postgres://zalo:zalo@localhost:5432/zalo?sslmode=disable}"
MIG_DIR="$(cd "$(dirname "$0")/.." && pwd)/migrations"

echo "Applying migrations from $MIG_DIR to $DB_URL"
for f in "$MIG_DIR"/*.sql; do
  echo " -> $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done
echo "Done."
