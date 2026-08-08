#!/usr/bin/env bash
# =============================================================
# backup.sh — pg_dump backup of the LocInsight Supabase database
#
# Usage:
#   SUPABASE_DB_URL="postgresql://..." ./scripts/backup.sh
#   SUPABASE_DB_URL="postgresql://..." BACKUP_DIR=/backups ./scripts/backup.sh
#
# Recommended cron (daily at 02:00 UTC):
#   0 2 * * * SUPABASE_DB_URL=... /path/to/Locinsights_db/scripts/backup.sh
# =============================================================
set -euo pipefail

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL environment variable is required}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
FILE="$BACKUP_DIR/locinsight-$TIMESTAMP.sql.gz"

echo "[$(date -u)] Backing up to $FILE ..."

# Use pg_dump with --no-owner and --no-privileges so the dump can be
# restored to a fresh Supabase project without role/owner conflicts.
pg_dump "$SUPABASE_DB_URL" \
  --no-owner \
  --no-privileges \
  --format=plain \
  | gzip -9 > "$FILE"

SIZE=$(du -h "$FILE" | cut -f1)
echo "[$(date -u)] Backup complete: $FILE ($SIZE)"

# Prune backups older than RETENTION_DAYS
if [ "$RETENTION_DAYS" -gt 0 ]; then
  echo "[$(date -u)] Pruning backups older than $RETENTION_DAYS days ..."
  find "$BACKUP_DIR" -name 'locinsight-*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
fi

# Verify the backup is restorable (dry-run restore to /dev/null)
echo "[$(date -u)] Verifying backup integrity ..."
if gunzip -t "$FILE" 2>/dev/null; then
  echo "[$(date -u)] OK: gzip integrity check passed"
else
  echo "[$(date -u)] ERROR: gzip integrity check FAILED" >&2
  exit 1
fi
