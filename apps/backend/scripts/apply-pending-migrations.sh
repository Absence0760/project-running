#!/usr/bin/env bash
#
# Apply pending Supabase migrations to a target database the way this repo's
# mixed 8-digit/14-digit version history requires.
#
# `supabase db push` (and `migration up`) refuse against this project because
# the CLI sorts same-date 8-digit (`20260601`) and 14-digit (`20260601000001`)
# versions differently than the remote ledger recorded them, so its
# history-alignment pre-flight fails even though nothing is actually missing
# (see apps/backend/CLAUDE.md § the mixed-format note). This script is the
# automated form of the documented manual workaround: for every local
# migration whose version is not yet in the remote `schema_migrations` ledger,
# apply its SQL inside a transaction and record the ledger row in the same
# transaction — in version order.
#
# Usage:
#   SUPABASE_DB_URL='postgresql://…' ./scripts/apply-pending-migrations.sh
#
# Run from apps/backend (the migrations dir is resolved relative to CWD).
# Idempotent: already-applied versions are skipped; the ledger insert is
# guarded with ON CONFLICT. On any error the current migration's transaction
# rolls back and the script stops, leaving the ledger honest.

set -euo pipefail

DB_URL="${SUPABASE_DB_URL:?SUPABASE_DB_URL must be set to the target database connection string}"
MIG_DIR="${MIG_DIR:-supabase/migrations}"

# Supabase DB passwords routinely contain %, !, ^, etc. Left inline in the URI,
# psql tries to percent-decode them ("invalid percent-encoded token") and never
# connects. So authenticate via PGPASSWORD (raw, no encoding) and strip the
# password out of the URI. The strip is an exact-substring removal keyed on the
# known SUPABASE_DB_PASSWORD, so it can't mis-parse a password that itself
# contains ':' or '@'. If SUPABASE_DB_PASSWORD is unset we assume the URL is
# already usable as-is.
if [[ -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
  export PGPASSWORD="${SUPABASE_DB_PASSWORD}"
  DB_URL="${DB_URL/:${SUPABASE_DB_PASSWORD}@/@}"
fi

if [[ ! -d "$MIG_DIR" ]]; then
  echo "::error::migrations directory not found: $MIG_DIR (run from apps/backend)" >&2
  exit 1
fi

# Version key = leading digits before the first underscore; name = the rest of
# the basename. This is exactly how the Supabase CLI parses the ledger
# (verified: prod records `20260601_001_runs_metadata_…` as version=20260601,
# name=001_runs_metadata_…).
version_of() { local b; b="$(basename "$1" .sql)"; printf '%s' "${b%%_*}"; }
name_of()    { local b; b="$(basename "$1" .sql)"; printf '%s' "${b#*_}"; }

echo "Reading applied migration versions from the target ledger…"
applied="$(psql "$DB_URL" -tAc \
  "select version from supabase_migrations.schema_migrations")"

# Build a version-sorted work list. Sorting by the parsed VERSION (not the
# filename) is what keeps the mixed 8/14-digit siblings in the correct order —
# '20270402' sorts before '20270402000001' as strings, matching the ledger,
# whereas a filename sort would invert them ('0' < '_').
mapfile -t sorted < <(
  for f in "$MIG_DIR"/*.sql; do printf '%s\t%s\n' "$(version_of "$f")" "$f"; done \
    | sort -t$'\t' -k1,1
)

applied_count=0
skipped=0
for row in "${sorted[@]}"; do
  version="${row%%$'\t'*}"
  file="${row#*$'\t'}"
  name="$(name_of "$file")"

  if grep -qxF "$version" <<<"$applied"; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "Applying ${version} (${name})…"
  # The migration SQL + its ledger row commit atomically. ON_ERROR_STOP makes
  # psql exit non-zero on the first failure so `set -e` halts the loop.
  PGOPTIONS='' psql "$DB_URL" -v ON_ERROR_STOP=1 --quiet <<SQL
begin;
\i ${file}
insert into supabase_migrations.schema_migrations(version, name)
  values ('${version}', '${name}')
  on conflict (version) do nothing;
commit;
SQL
  applied_count=$((applied_count + 1))
done

echo "Done: applied ${applied_count} migration(s), ${skipped} already present."
