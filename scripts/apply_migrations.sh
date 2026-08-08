#!/usr/bin/env bash
# =============================================================
# apply_migrations.sh — Apply all LocInsight migrations to Supabase
# Usage:
#   SUPABASE_DB_URL="postgresql://..." ./apply_migrations.sh
# Or:
#   SUPABASE_PROJECT_REF="fcyhrzzfvdsghtummizv" SUPABASE_DB_PASSWORD="..." ./apply_migrations.sh
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "${SUPABASE_DB_URL:-}" ]; then
  DB_URL="$SUPABASE_DB_URL"
elif [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
  PROJECT_REF="${SUPABASE_PROJECT_REF:-fcyhrzzfvdsghtummizv}"
  REGION="${SUPABASE_REGION:-ap-southeast-1}"
  DB_URL="postgresql://postgres.${PROJECT_REF}:${SUPABASE_DB_PASSWORD}@aws-0-${REGION}.pooler.supabase.com:6543/postgres"
else
  echo "ERROR: Set either SUPABASE_DB_URL or SUPABASE_DB_PASSWORD"
  exit 1
fi

echo "Applying LocInsight migrations to Supabase..."
echo "Project: ${SUPABASE_PROJECT_REF:-fcyhrzzfvdsghtummizv}"
echo ""

for f in migrations/0*.sql; do
  echo "→ Applying $f..."
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
  echo "✓ $f applied"
  echo ""
done

echo "All migrations applied successfully."
echo ""
echo "Verifying table count..."
psql "$DB_URL" -t -c "
SELECT count(*) AS table_count
FROM information_schema.tables
WHERE table_schema='public' AND table_type='BASE TABLE';
"

echo ""
echo "Done."
