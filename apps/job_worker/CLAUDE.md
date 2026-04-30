# job_worker — AI session notes

Generic Go service that drains the `jobs` queue (migration
`20260609_001_run_match_pipeline.sql`). First and only kind today is
`map_match`; strava-webhook / token-refresh / data-export will land as
additional kinds in `internal/worker.go`'s dispatch when those
Edge Functions move per [`../../docs/roadmap.md`](../../docs/roadmap.md) §214.

## Scope — read before writing code

**This service is the *only* place writes to `jobs` and
`run_matched_tracks` should originate from on the worker side.** Both
tables are RLS-locked and the SECURITY DEFINER worker functions
(`claim_next_job`, `finish_job`, `defer_job`) are revoked from PUBLIC and
granted only to `service_role`. The worker authenticates with the service
role key.

**Build here:**

- New `Matcher` implementations — see the interface in
  [`internal/matcher.go`](internal/matcher.go). `PassthroughMatcher`
  is the smoke-test default; `OSRMMatcher` (in
  [`internal/matcher_osrm.go`](internal/matcher_osrm.go)) is the
  first real engine and is selected in `main.go` when `OSRM_URL` is
  set. Valhalla / GraphHopper would each be a sibling file plus
  another env-driven branch.
- Additional job kinds — extend the switch in `Worker.dispatch` and
  add the matching trigger / migration in `apps/backend/`.
- Operational concerns — backoff tuning, Prometheus metrics, leader
  election if multiple workers don't suffice. None shipped today.

**Don't build here:**

- Anything that should run on the request path. The worker is for
  background work only — synchronous user actions belong in Edge
  Functions or PostgREST.
- A second source of truth for the queue. The `jobs` table + the
  RPC trio (`claim_next_job` / `finish_job` / `defer_job`) is the
  contract; don't add a parallel queue.
- Direct Postgres connections. Everything goes through PostgREST +
  Storage REST so the worker has one transport and zero VPC-peering
  concerns when deployed to Fly.io.

## Layout

```
apps/job_worker/
├── go.mod
├── main.go                  # entrypoint: env → SupabaseClient → Worker.Run
├── internal/
│   ├── types.go             # Job, MapMatchPayload, TrackPoint, MatchedTrackRow
│   ├── supabase.go          # PostgREST + Storage REST client (service role)
│   ├── matcher.go           # Matcher interface + PassthroughMatcher stub
│   ├── matcher_test.go
│   ├── matcher_osrm.go      # OSRMMatcher — /match/v1/foot, chunked
│   ├── matcher_osrm_test.go
│   ├── worker.go            # claim → handle → finish loop
│   └── worker_test.go       # table-driven test using a fake Backend
├── osrm/                    # local OSRM dev stack (compose + Makefile)
├── Dockerfile               # multi-stage; final image is distroless
├── README.md                # local-run instructions
└── CLAUDE.md                # this file
```

## Concurrency

Multiple workers can run side by side. `claim_next_job` does
`for update skip locked` so two simultaneous claims each get a
distinct job rather than blocking. No leader election or partitioning
is needed for the foreseeable scale.

## Error classification

The worker reports back to the queue on every job:

- **success** → `finish_job(done, nil)`
- **transient** (5xx, dial timeout, connection refused, deadline) →
  `defer_job(delay_seconds, msg)`. `attempts` is *not* decremented;
  the per-job `max_attempts` ceiling still applies.
- **permanent** (4xx, malformed payload, missing run, RLS denial) →
  `finish_job(failed, msg)`.

The classifier lives in `isTransient` in `worker.go`. It branches on
`HTTPError.StatusCode` first (typed error from `supabase.go`), then
falls back to substring sniffing the message for network-layer
markers — same shape as the watch's drain classifier in
`apps/watch_wear/.../RunViewModel.kt`.

## Re-upload race

Closed at the DB level via a `source_track_url` CAS (migration
`20260611_001_run_matched_tracks_cas.sql`). The trigger writes
`NEW.track_url` into `run_matched_tracks.source_track_url` on every
insert and every reset; the worker captures `runs.track_url` at job
start and PATCHes the row conditionally on
`?source_track_url=eq.<value>` via `Prefer: return=representation`.
A re-upload that lands between the worker's read and write changes
`source_track_url`, the conditional PATCH affects 0 rows, the worker
client returns `ErrStaleSourceTrackURL`, and the worker logs +
returns `nil` — the OLD job ends cleanly via `finish_job(done)`,
the NEW job already queued by the trigger produces the right
result.

The pre-write `track_url` recheck is kept as a fast path: it skips
the upload + PATCH entirely when the change is already visible at
read time, saving a wasted Storage write. Defence in depth — the
CAS is what closes the actual race; the recheck is for niceness.

Pinned by:
- `TestWorker_ReuploadDuringMatchDiscardsResult` — recheck path.
- `TestWorker_StaleSourceTrackURLDiscardsResult` — CAS path
  (recheck would have passed but the row was reset under the
  worker's feet between recheck and PATCH).

If the matched gz was uploaded before the CAS rejected the PATCH,
the file is now an orphan in Storage. The worker logs the path so
an operator can sweep these later; an automated cleanup job would
be the natural follow-up.

## Local dev

See [README.md](README.md) for the smoke-test recipe.

```bash
# From apps/job_worker:
go test ./...                   # unit tests, no network
go vet ./...
go build .                      # produce a binary in cwd

# Against a running supabase stack at apps/backend:
SUPABASE_URL=http://127.0.0.1:54321 \
  SUPABASE_SERVICE_ROLE_KEY=$(cd ../backend && supabase status -o env | \
    awk -F= '/^SERVICE_ROLE_KEY=/ {gsub(/"/,"",$2); print $2}') \
  WORKER_ID=dev \
  go run .
```

Stops on SIGINT / SIGTERM.

## Before reporting a task done

- `go vet ./...` clean.
- `go test ./...` passes.
- If you added a new job kind: extended the `Worker.dispatch` switch,
  added a handler test, and updated the `kind` allowlist in any
  client-side enqueue path that reaches into `jobs` directly (only
  the runs trigger does today).
- If you swapped in a real `Matcher`: verified the new implementation
  uploads a valid gzipped JSON array (worker's `parseTrack` will fail
  on invalid bytes, which is the right behaviour — but a regression
  there would surface as queued jobs flipping to `failed`).
- Updated [../../docs/roadmap.md](../../docs/roadmap.md) §515-531 with
  the engine choice or wiring change.
