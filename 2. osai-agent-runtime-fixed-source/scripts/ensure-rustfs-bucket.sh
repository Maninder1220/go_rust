#!/usr/bin/env bash
# =============================================================================
# File: scripts/ensure-rustfs-bucket.sh
# Purpose:
#   Ensures the RustFS bucket used by OSAI exists before the storage worker uploads snapshots.
#
# Where this fits in OSAI:
#   Run this before osai-storage-worker, or let osai-all run the same rustfs-init service automatically.
#
# Topics to know before editing:
#   Docker Compose services, RustFS S3-compatible buckets, and MinIO mc as an S3 client.
#
# Important operational notes:
#   RustFS is the storage server. minio/mc is only the S3-compatible client used by the rustfs-init service.
# =============================================================================

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.storage.yml}"

docker compose -f "${COMPOSE_FILE}" up -d rustfs
docker compose -f "${COMPOSE_FILE}" rm -f rustfs-init >/dev/null 2>&1 || true
docker compose -f "${COMPOSE_FILE}" run --rm --no-deps rustfs-init
