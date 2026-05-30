# OSRM dev stack

Local-only [OSRM](http://project-osrm.org/) server for map-matching
development. Runs the `foot` profile against a Geofabrik OSM extract;
the Go worker hits its `/match/v1/foot` endpoint when `OSRM_URL`
points at it.

This is a **dev-only** harness. Production deployment (Fly.io / Cloud
Run / dedicated VM) is its own decision and is tracked separately
under [`docs/product/roadmap.md`](../../../docs/product/roadmap.md) §515-531.

## One-time setup

The routing graph is too large (multi-GB intermediates) to check into
git, so it has to be built locally before the server can start.
`pnpm dev:run:osrm` preflight-checks for the graph and bails out
with a clear message if it isn't there — don't `docker compose up`
directly until the build has run.

```bash
# From the repo root — downloads the default region + builds the
# graph in one step. ~50-200 MB download + ~5-15 min build.
pnpm dev:setup:osrm

# Or directly via Make if you want to override the region:
cd apps/job_worker/osrm
make download REGION_URL=https://download.geofabrik.de/europe/great-britain/england/greater-london-latest.osm.pbf
make build

# Day-to-day, once the graph exists:
pnpm dev:run:osrm
```

Verify with:

```bash
curl -s 'http://127.0.0.1:5000/health' && echo
# {"status":"running","memory_in_use":..., ...}

# Smoke a /match call against a couple of points
curl -s 'http://127.0.0.1:5000/match/v1/foot/144.96,-37.81;144.965,-37.812' | jq .matchings[0].confidence
```

## Region default

`REGION_URL` defaults to **Victoria, Australia** — the seed routes
all live in Melbourne, so the seed runs become genuine end-to-end
test fixtures without downloading the whole continent.

To swap regions, re-run with an explicit URL and rebuild:

```bash
make clean
make download REGION_URL=https://download.geofabrik.de/europe/great-britain/england/greater-london-latest.osm.pbf
make build
docker compose restart
```

## Profiles

The Makefile uses `/opt/foot.lua` (bundled in the OSRM image) so the
graph is built for pedestrians: pedestrian-permitted ways included,
motorway-only excluded, one-way restrictions ignored on shared
paths. Don't switch to `car.lua` — about half the parks and trails
runners care about disappear from the graph.

## Wiring the worker

Set `OSRM_URL` when running the worker; the entrypoint switches
matchers automatically:

```bash
cd ../  # apps/job_worker
OSRM_URL=http://127.0.0.1:5000 \
  SUPABASE_URL=$API_URL \
  SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY \
  go run .
```

Without `OSRM_URL`, the worker stays on `PassthroughMatcher` (raw
track in, raw track out) so the rest of the pipeline can be exercised
without a running OSRM stack.

## Smoke test

Once OSRM is up, the local Supabase stack is running, and the worker
is draining with `OSRM_URL` set, `make smoke` runs an end-to-end check:

```bash
# Terminal 1: OSRM
cd apps/job_worker/osrm && docker compose up -d

# Terminal 2: worker
cd apps/job_worker
eval "$(cd ../backend && supabase status -o env | grep -E '^(SERVICE_ROLE_KEY|API_URL)=')"
SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  OSRM_URL=http://127.0.0.1:5000 go run .

# Terminal 3: smoke test
cd apps/job_worker/osrm
make smoke
```

What `make smoke` does, in order:

1. Probes OSRM `/health` and a Melbourne-region `/match` call to
   confirm the right PBF is loaded.
2. Pulls `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` from
   `supabase status -o env` if they aren't in the environment.
3. Uploads a 6-point Royal Botanic Gardens track to Storage as
   `runs/<seed user>/<new run id>.json.gz`.
4. Inserts a `runs` row, which fires the trigger that queues a
   `kind='map_match'` job.
5. Polls `run_matched_tracks` for up to `WAIT_S` (default 15) seconds,
   waiting for `status='matched'`.
6. Pretty-prints the first three points of the raw and matched
   tracks side-by-side. If OSRM is wired correctly the coordinates
   are different — that's the snap.

Tunables (set them before `make smoke`):

| Variable | Default | When to change |
|---|---|---|
| `OSRM_URL` | `http://127.0.0.1:5000` | Different host/port. |
| `WAIT_S` | `15` | Slow laptop or sub-2 s `PollInterval` retune on the worker. |
| `SEED_USER_ID` | the seed `runner@test.com` UUID | If you replaced the seed. |
| `PG_CONTAINER` | `supabase_db_backend` | If your local Supabase isn't using the default container name. |

Failure modes the script reports clearly:

- OSRM unreachable → "is `docker compose up -d` running?"
- OSRM returns `code != "Ok"` for the Melbourne probe → "wrong region for the loaded PBF"
- `run_matched_tracks.status` never leaves `pending` → "is the worker running?"
- `status='matched'` but raw and matched coords identical → matcher is on `PassthroughMatcher`; `OSRM_URL` wasn't picked up by the worker

## Troubleshooting

- **`Could not access /data/region.osrm`** — `make build` didn't run
  cleanly. Check for partial files in `data/` and re-run.
- **Port 5000 already in use** — change the host port in
  `docker-compose.yml` and update `OSRM_URL`.
- **Match calls return `NoMatch` for every track** — wrong region for
  the points you're feeding. Verify your seed routes' coordinates
  fall inside the OSM extract's bounding box.
- **Slow builds on Apple Silicon** — the `osrm/osrm-backend` image is
  amd64 by default; pull `osrm/osrm-backend:latest --platform=linux/amd64`
  is fine but slow. The first build is the painful one; subsequent
  iterations are fast.
