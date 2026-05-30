# job_worker

Background-job drainer for the `jobs` Postgres queue (migration
[`20260609_001_run_match_pipeline.sql`](../backend/supabase/migrations/20260609_001_run_match_pipeline.sql)).
First registered handler is `kind='map_match'`; additional kinds plug
into `internal/worker.go`'s dispatch switch.

## Required env

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Base URL, e.g. `http://127.0.0.1:54321` for local dev or your project URL in prod. |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role JWT. The worker uses this for every call so it bypasses RLS on `jobs` + `run_matched_tracks`. **Never put this on a client.** |
| `WORKER_ID` | Optional. Stamped on the `jobs.locked_by` column for stuck-job debugging. Defaults to the hostname. |
| `OSRM_URL` | Optional. When set (e.g. `http://127.0.0.1:5000`), the worker uses the OSRM `/match` endpoint instead of the passthrough shim. Local OSRM stack lives at [`./osrm/`](osrm/). |
| `HEALTH_PORT` | Optional. Port for the embedded `/health` HTTP endpoint. Defaults to `8080` (matches `fly.toml`). Health flips to 503 if the worker poll loop hasn't ticked within 10 s — Fly.io's auto-restart catches wedged machines. |

## Run locally

The local Supabase stack must be up (`cd apps/backend && supabase start`).

```bash
cd apps/job_worker

# Unit tests (no network)
go test ./...

# Live drain against the local stack
eval "$(cd ../backend && supabase status -o env | grep -E '^(SERVICE_ROLE_KEY|API_URL)=')"
SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  WORKER_ID=dev \
  go run .
```

Logs are JSON on stdout via `log/slog`. SIGINT / SIGTERM gracefully
shuts down between jobs.

## End-to-end smoke test

For the OSRM-engine path, the easiest way is `make smoke` in
[`./osrm/`](osrm/) — it stands up the run row, polls
`run_matched_tracks` until the worker writes `status='matched'`, and
prints raw vs matched coordinates side-by-side. See
[`./osrm/README.md` § Smoke test](osrm/README.md#smoke-test).

For the passthrough engine (no OSRM running), the bare-hands recipe
below uploads a tiny track, inserts the run, and checks the row:

```bash
eval "$(cd ../backend && supabase status -o env | grep -E '^(SERVICE_ROLE_KEY|API_URL)=')"
USER_ID=a1b2c3d4-e5f6-7890-abcd-ef1234567890   # seed user
RUN_ID=$(uuidgen)

# 1. Upload a tiny track to Storage.
echo '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]' | gzip | \
  curl -s -X POST \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" -H "Content-Encoding: gzip" \
    -H "x-upsert: true" \
    --data-binary @- \
    "$API_URL/storage/v1/object/runs/$USER_ID/$RUN_ID.json.gz"

# 2. Insert the run row — the trigger will queue a map_match job.
docker exec supabase_db_backend psql -U postgres -d postgres -c "
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, track_url, metadata)
VALUES ('$RUN_ID', '$USER_ID', now(), 60, 100, 'app',
        '$USER_ID/$RUN_ID.json.gz', '{\"activity_type\":\"run\"}'::jsonb);
"

# 3. Run the worker for a few seconds.
SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  timeout --signal=TERM 5s go run .

# 4. Confirm the matched track + row landed.
docker exec supabase_db_backend psql -U postgres -d postgres -c "
SELECT status, matched_track_url, algorithm
FROM run_matched_tracks WHERE run_id='$RUN_ID';
"
```

## Production

For the full deployment plan (Fly.io app shape, Volume sizing, weekly OSRM rebuild, observability, rollback, DR), see [deployment.md](deployment.md). The container itself is a single Docker image, distroless final layer (~9 MB):

```bash
docker build -t job_worker:latest .
docker run --rm \
  -e SUPABASE_URL=https://<project>.supabase.co \
  -e SUPABASE_SERVICE_ROLE_KEY=<key> \
  -e OSRM_URL=http://osrm.internal:5000 \
  job_worker:latest
```

Deployment target is Fly.io per [`../../docs/product/roadmap.md`](../../docs/product/roadmap.md) §205. Sized for a single 256 MB VM in v1; horizontal-scale by replicating the same image — the SQL `for update skip locked` in `claim_next_job` makes that safe.

## Map-matching engine

The default `Matcher` is a passthrough that returns the input track
unchanged — useful for exercising the rest of the pipeline without a
running engine.

The first real engine wired in is **OSRM** (`/match/v1/foot`). To use
it, stand up the local stack and point the worker at it:

```bash
# Terminal 1: bring up OSRM (one-time setup; see ./osrm/README.md).
cd osrm
make download && make build && docker compose up -d

# Terminal 2: run the worker with OSRM_URL set.
cd ..
eval "$(cd ../backend && supabase status -o env | grep -E '^(SERVICE_ROLE_KEY|API_URL)=')"
SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  OSRM_URL=http://127.0.0.1:5000 \
  go run .
```

When `OSRM_URL` is unset the worker falls back to the passthrough.

Roadmap-tracked engine evaluation (Valhalla Meili / GraphHopper) lives
at [`../../docs/product/roadmap.md`](../../docs/product/roadmap.md) §515-531. The
`Matcher` interface is stable; adding a new engine means adding a
sibling to `internal/matcher_osrm.go` and another env-driven branch in
`main.go`.
