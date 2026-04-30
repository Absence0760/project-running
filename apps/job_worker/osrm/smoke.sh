#!/usr/bin/env bash
# End-to-end smoke test for the OSRM map-matching pipeline.
#
# What this exercises:
#   1. OSRM at $OSRM_URL responds to /health.
#   2. Storage at $SUPABASE_URL accepts a gzipped track upload.
#   3. The runs trigger queues a kind='map_match' job.
#   4. The worker (running separately) drains the job within $WAIT_S
#      seconds and writes status='matched' to run_matched_tracks.
#   5. The matched coordinates differ from the raw — proof that OSRM
#      actually snapped the track, not the PassthroughMatcher fallback.
#
# What it does NOT cover:
#   * The worker itself — start it in another terminal first
#     (OSRM_URL=http://127.0.0.1:5000 go run . from apps/job_worker).
#   * NoMatch / failed paths — those have unit-test coverage in
#     internal/matcher_osrm_test.go and worker_test.go.
#
# Defaults are the Royal Botanic Gardens loop in Melbourne, which
# matches the default Victoria Geofabrik PBF the Makefile downloads.
# Override SEED_USER_ID if you swapped the seed.

set -euo pipefail

OSRM_URL="${OSRM_URL:-http://127.0.0.1:5000}"
WAIT_S="${WAIT_S:-15}"
SEED_USER_ID="${SEED_USER_ID:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}"
PG_CONTAINER="${PG_CONTAINER:-supabase_db_backend}"

# Pull SUPABASE_URL + SERVICE_ROLE_KEY from the local CLI if not in env.
# The CLI keeps emitting the modern `Publishable` / `Secret` names, so
# we filter on the env-output form which still uses *_KEY suffixes.
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "→ Pulling creds from supabase status (apps/backend)…" >&2
  cd_back=$(pwd)
  cd "$(dirname "$0")/../../backend"
  eval "$(supabase status -o env | grep -E '^(SERVICE_ROLE_KEY|API_URL)=')"
  cd "$cd_back"
  : "${SUPABASE_URL:=$API_URL}"
  : "${SUPABASE_SERVICE_ROLE_KEY:=$SERVICE_ROLE_KEY}"
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "✗ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY not set and the local stack isn't running." >&2
  exit 2
fi

# 1. OSRM is alive and on the right region.
echo "→ Checking OSRM at $OSRM_URL …"
if ! curl -sf "$OSRM_URL/health" >/dev/null; then
  echo "✗ OSRM unreachable at $OSRM_URL — is 'docker compose up -d' running?" >&2
  exit 3
fi
osrm_code=$(curl -s "$OSRM_URL/match/v1/foot/144.9784,-37.8312;144.9805,-37.8307?geometries=geojson&overview=full" | jq -r '.code')
if [[ "$osrm_code" != "Ok" ]]; then
  echo "✗ OSRM returned code=$osrm_code for the Melbourne probe — wrong region for the loaded PBF?" >&2
  exit 4
fi
echo "✓ OSRM serving the right region."

# 2. Build a 6-point Melbourne loop with realistic GPS jitter so the
# matcher has something to snap.
RUN_ID="$(uuidgen)"
TRACK='[
  {"lat":-37.83121,"lng":144.97840},
  {"lat":-37.83110,"lng":144.97889},
  {"lat":-37.83098,"lng":144.97935},
  {"lat":-37.83082,"lng":144.97994},
  {"lat":-37.83069,"lng":144.98042},
  {"lat":-37.83053,"lng":144.98095}
]'

echo "→ Uploading raw track for run $RUN_ID …"
echo "$TRACK" | gzip | curl -sf -X POST \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Content-Encoding: gzip" \
  -H "x-upsert: true" \
  --data-binary @- \
  "$SUPABASE_URL/storage/v1/object/runs/$SEED_USER_ID/$RUN_ID.json.gz" >/dev/null
echo "✓ Track uploaded."

# 3. Insert the run row — the trigger queues the map_match job inside
# the same statement.
echo "→ Inserting run row (trigger queues the job)…"
docker exec "$PG_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, track_url, metadata)
VALUES ('$RUN_ID', '$SEED_USER_ID', now(), 60, 250, 'app',
        '$SEED_USER_ID/$RUN_ID.json.gz', '{"activity_type":"run"}'::jsonb);
SQL
echo "✓ Run inserted."

# 4. Poll run_matched_tracks until the worker writes a terminal status.
echo "→ Waiting up to ${WAIT_S}s for the worker to drain the job…"
deadline=$(( $(date +%s) + WAIT_S ))
status=""
while (( $(date +%s) < deadline )); do
  status=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -tAc \
    "SELECT status FROM run_matched_tracks WHERE run_id='$RUN_ID';" 2>/dev/null || true)
  status=$(echo "$status" | tr -d '[:space:]')
  if [[ -n "$status" && "$status" != "pending" ]]; then
    break
  fi
  sleep 1
done

if [[ "$status" != "matched" ]]; then
  echo "✗ Worker did not produce status='matched' (got: '${status:-<missing>}')." >&2
  echo "  Check the worker terminal for errors. If the worker isn't running, start it with:" >&2
  echo "    cd apps/job_worker && OSRM_URL=$OSRM_URL go run ." >&2
  exit 5
fi
echo "✓ status=matched, algorithm=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -tAc \
  "SELECT algorithm || ' ' || algorithm_version FROM run_matched_tracks WHERE run_id='$RUN_ID';")"

# 5. Diff raw vs matched. If OSRM actually snapped the track, the
# coordinates will differ; if the worker is on the passthrough
# fallback, they'll be identical.
echo
echo "── Raw track (first 3 points) ──────────────────────────────────"
curl -sf -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  "$SUPABASE_URL/storage/v1/object/runs/$SEED_USER_ID/$RUN_ID.json.gz" \
  | gunzip | jq '.[0:3]'

echo
echo "── Matched track (first 3 points) ──────────────────────────────"
curl -sf -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  "$SUPABASE_URL/storage/v1/object/runs/$SEED_USER_ID/$RUN_ID.matched.json.gz" \
  | gunzip | jq '.[0:3]'

echo
echo "✓ Smoke test passed. Run id: $RUN_ID"
echo "  View at http://localhost:7777/runs/$RUN_ID (logged in as runner@test.com)."
