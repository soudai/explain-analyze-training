#!/usr/bin/env bash
set -euo pipefail

# Configuration (can be overridden via environment)
PG_CONTAINER="${PG_CONTAINER:-pg-demo18}"
PG_DB="${PG_DB:-pgdemo}"
PG_USER="${PG_USER:-pg-demo18}"
PARKING_DIR="$(cd "$(dirname "$0")" && pwd)"
PARKING_TMP="/tmp/design_parking"

echo "[init.sh] Import parking DDLs into DB '${PG_DB}' on container '${PG_CONTAINER}'"

# Ensure container is running (optional soft check)
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
  echo "[init.sh] ERROR: Container '${PG_CONTAINER}' is not running. Start it via 'make up'." >&2
  exit 1
fi

# Create temp directory, copy files, and run psql
docker exec -i "${PG_CONTAINER}" bash -lc "mkdir -p '${PARKING_TMP}'"
docker cp "${PARKING_DIR}/init.sql"  "${PG_CONTAINER}:${PARKING_TMP}/init.sql"
docker cp "${PARKING_DIR}/soudai_ddl.sql" "${PG_CONTAINER}:${PARKING_TMP}/soudai_ddl.sql"
docker cp "${PARKING_DIR}/ai_ddl.sql"    "${PG_CONTAINER}:${PARKING_TMP}/ai_ddl.sql"
docker cp "${PARKING_DIR}/ai2_ddl.sql"   "${PG_CONTAINER}:${PARKING_TMP}/ai2_ddl.sql"

echo "[init.sh] Executing init.sql via psql"
docker exec -i "${PG_CONTAINER}" bash -lc \
  "cd '${PARKING_TMP}' && psql -U '${PG_USER}' -d '${PG_DB}' -f '${PARKING_TMP}/init.sql'"

echo "[init.sh] Done: schemas 'soudai', 'ai', 'ai2' should be populated."
