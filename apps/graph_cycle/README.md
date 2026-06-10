# graph_cycle map sidecar

Standalone Go service that powers the **v3 graph-cycle loop generator** for
"Generate a route by distance"
([docs/features/graph_cycle_loop_generation.md](../../docs/features/graph_cycle_loop_generation.md)).
It parses an OSM PBF into an in-memory **foot-routable graph** and searches the
real street network for a clean loop near a target distance — tracing the
neighbourhood loop that pure geometry (the v2 polygon generator + GraphHopper
`round_trip`) can't find on irregular grids, and honestly reporting the largest
clean loop where none near target exists.

Deployed to Fly alongside OSRM + GraphHopper, reached by the generate-route
Lambda over **public https** with an `X-Engine-Key` guard (same posture as
GraphHopper — the Lambda runs on AWS with no 6PN path into Fly). Unlike
GraphHopper, the guard is **in-process** (`internal/api/guard.go`), so there's no
Caddy sidecar and the image stays distroless.

## HTTP API

| Route | Method | Purpose |
|---|---|---|
| `/health` | GET | Open (no key). `{"status":"ok","nodes":N,"edges":M,"ways":W}` once the graph is built. |
| `/cycle` | POST | The loop search. Body `{"start":{"lat","lng"},"targetDistanceM"}`. |
| `/route` | POST | Shortest foot path `{"from","to"}` — for validating the graph against OSRM. |
| `/nearest` | GET | `?lat=&lng=` → nearest graph node. Debug. |

`/cycle` returns `{"found":true,"coordinates":[[lng,lat]…],"distanceM","areaEfficiency","largestClean":{…}}`
when a clean loop exists, or `{"found":false,"largestClean":…}` when the start is
loop-poor (the web client turns `found:false` into a round_trip fallback).

## One-time setup

The routing graph is built in memory from a PBF on boot, so the only setup is
getting the extract onto `./data`:

```bash
cd apps/graph_cycle
make seed     # copies region.osm.pbf from ../job_worker/osrm/data, or downloads the default
```

`make seed` reuses the OSRM dev stack's extract when present so all three engines
(OSRM, GraphHopper, graph_cycle) share one download and one coverage area.
Override the region:

```bash
make seed REGION_URL=https://download.geofabrik.de/north-america/us/virginia-latest.osm.pbf
```

## Local run

Two ways:

```bash
# Fastest inner loop — run the binary directly against the seeded PBF.
# (GOTOOLCHAIN=auto if your local Go is older than go.mod's pin.)
make dev

# Or the container that matches prod:
make build && make serve
```

Verify (override START for your seeded region — the default is Melbourne):

```bash
curl -s 'http://127.0.0.1:8989/health' | jq .
# {"status":"ok","nodes":...,"edges":...,"ways":...}

make smoke START=-37.81,144.96
```

The web dev server reaches the sidecar via `GRAPH_CYCLE_URL=http://127.0.0.1:8989`
+ `GRAPH_CYCLE_API_KEY=dev-graph-cycle-key` (set in `apps/web/.env.local`; see
`apps/web/.env.development` for the opt-in note). Without `GRAPH_CYCLE_URL` the
generate handler skips graph-cycle and uses round_trip.

## Tests

```bash
go test ./...   # pure unit tests, no PBF, no network
```

The graph build, Dijkstra, penalty rerouting, cycle search, the guard, and the
HTTP handlers are all covered. Synthetic lattice/line graphs
(`graph.BuildTestGrid` / `BuildTestLine`) stand in for a PBF.

## Deploying to production

```bash
# 1. Volume (one-time)
flyctl volumes create graph_cycle_data --app graph-cycle --region lhr --size 10

# 2. Deploy
cd apps/graph_cycle && flyctl deploy --app graph-cycle

# 3. Seed the PBF (the SAME extract OSRM uses)
flyctl ssh sftp shell --app graph-cycle
put data/region.osm.pbf /data/region.osm.pbf
exit

# 4. Shared secret (must equal the Lambda's GRAPH_CYCLE_API_KEY from sops)
flyctl secrets set GRAPH_CYCLE_API_KEY=<value> --app graph-cycle

# 5. Restart to parse the PBF
flyctl machine restart <id> --app graph-cycle
```

Sizing: the in-memory node-level foot graph fits a metro / single-country
extract in a few GB; bump `[[vm]]` memory + the machine for a continent. The
graph is rebuilt from the PBF on every boot (no persisted graph-cache) —
`grace_period` in `fly.toml` covers the parse. A serialized-graph cache is the
natural future optimization if boot time on a large extract becomes a problem.

## Troubleshooting

- **`graph has zero nodes`** at startup → the PBF is missing, empty, or the
  wrong file. Re-run `make seed` and confirm `data/region.osm.pbf` exists.
- **`/cycle` always `found:false`** → the start coordinate falls outside the
  seeded extent (wrong region for the PBF), or the start is genuinely loop-poor.
  Check `/nearest` returns a node close to your start.
- **403 from every route except `/health`** → `GRAPH_CYCLE_API_KEY` is unset or
  the `X-Engine-Key` header doesn't match. The guard fails closed by design.
- **Older local Go than `go.mod`** → prefix commands with `GOTOOLCHAIN=auto` so
  the pinned toolchain resolves (matches CI's `setup-go` reading `go.mod`).
