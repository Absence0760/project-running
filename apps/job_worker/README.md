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

To prove the pipeline works against the local stack, upload a test
track + insert a run, then watch the worker drain it:

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

Single Docker image, distroless final layer (~9 MB):

```bash
docker build -t job_worker:latest .
docker run --rm \
  -e SUPABASE_URL=https://<project>.supabase.co \
  -e SUPABASE_SERVICE_ROLE_KEY=<key> \
  job_worker:latest
```

Deployment target is Fly.io per [`../../docs/roadmap.md`](../../docs/roadmap.md) §205. Sized for a single 256 MB VM in v1; horizontal-scale by replicating the same image — the SQL `for update skip locked` in `claim_next_job` makes that safe.

## What's not done

The shipped `Matcher` is a passthrough that returns the input track
unchanged. The roadmap calls for evaluating Valhalla Meili / OSRM /
GraphHopper before committing to a real engine
([`../../docs/roadmap.md`](../../docs/roadmap.md) §515-531). Swap the
implementation in `main.go` when chosen; the `Matcher` interface
shouldn't need to change.
