# OSRM dev stack

Local-only [OSRM](http://project-osrm.org/) server for map-matching
development. Runs the `foot` profile against a Geofabrik OSM extract;
the Go worker hits its `/match/v1/foot` endpoint when `OSRM_URL`
points at it.

This is a **dev-only** harness. Production deployment (Fly.io / Cloud
Run / dedicated VM) is its own decision and is tracked separately
under [`docs/roadmap.md`](../../../docs/roadmap.md) §515-531.

## One-time setup

```bash
cd apps/job_worker/osrm

# 1. Fetch the OSM extract (~50-200 MB depending on region).
make download
# or override:
# make download REGION_URL=https://download.geofabrik.de/europe/great-britain/england/greater-london-latest.osm.pbf

# 2. Build the routing graph (~5-15 min — three Docker passes).
make build

# 3. Start the server on :5000.
docker compose up -d
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
