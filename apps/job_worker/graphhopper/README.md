# GraphHopper round_trip engine — `graphhopper`

Self-hosted [GraphHopper](https://www.graphhopper.com/) instance serving the
`foot` profile, used by the **"Generate a route by distance"** feature. The
web core (`apps/web/src/lib/routes/generate/graphhopper.ts`) calls its
`/route?algorithm=round_trip&profile=foot&...` endpoint to turn a start point +
target distance into a loop, varying `round_trip.seed` to get differently
shaped candidates.

It replaces the old in-browser radial heuristic (`route_loop.ts`) that
overshot target distances on lopsided road networks. The engine is **server-only**:
the browser never sees `GRAPHHOPPER_URL`, so user start-coordinates never leave
our infra — privacy parity with the OSRM self-host ([decisions §45](../../../docs/architecture/decisions.md#45-server-side-map-matching-uses-osrm-not-valhalla-meili-or-graphhopper)).

This is the **production Fly.io app**. There is no separate local dev stack for
generation — point `GRAPHHOPPER_URL` at this app (or a locally-run jar) when
developing `/api/routes/generate`.

## Why a custom Dockerfile (no upstream image)

GraphHopper publishes **no official prebuilt Docker image** — the
`graphhopper/graphhopper` Docker Hub org is empty. So, unlike the OSRM app next
door (which runs the upstream `osrm/osrm-backend` image), the
[`Dockerfile`](Dockerfile) here builds the runnable `graphhopper-web-*.jar`
from a pinned source tag (`GH_VERSION`, currently 10.0) in a Maven stage, then
runs it on a slim JRE. The routing config lives in [`config.yml`](config.yml),
which we own.

## The graph is built on first boot from the PBF

Like OSRM, the routable graph is **not** baked into the image — it is built
once, on the first boot, from an OSM PBF on the mounted volume, and reused on
every later boot. Two load-bearing details:

- **Same region as OSRM.** GraphHopper must import the **same OSM region PBF**
  the OSRM graph uses (`apps/job_worker/osrm`): Victoria, Australia for the seed
  data, the UK extract for the v1 prod plan. A generation request whose start
  point falls outside the imported region returns no path → the core surfaces a
  502. Keep the two graphs on the same extract so "matchable" and "generatable"
  cover the same ground.

- **Flexible mode, no CH.** `round_trip` is a core GraphHopper algorithm but it
  only runs in **flexible mode** — Contraction Hierarchies (the default speed
  preparation) cannot serve it. `config.yml` leaves `profiles_ch: []` so the
  `foot` profile is import-prepared for flexible routing and a plain
  `round_trip` request succeeds **without** the caller passing `ch.disable=true`
  (the core doesn't send it). If you ever re-enable CH, generation breaks with a
  "round trip not supported with CH" error.

## Build / seed the graph

```bash
# 1. Create the volume (one-time):
flyctl volumes create graphhopper_data --app graphhopper --region lhr --size 10

# 2. Deploy the app (builds the jar; the machine boots with no graph yet):
cd apps/job_worker/graphhopper
flyctl deploy --app graphhopper

# 3. Upload the SAME region PBF the OSRM graph uses. You can reuse the file the
#    OSRM Makefile already downloaded at apps/job_worker/osrm/data/region.osm.pbf:
flyctl ssh sftp shell --app graphhopper
put ../osrm/data/region.osm.pbf /data/region.osm.pbf
exit

# 4. Restart so the first boot imports the PBF into /data/graph-cache
#    (several minutes for a country extract — the /health check's grace_period
#    covers it):
flyctl machine list --app graphhopper        # get the machine id
flyctl machine restart <id> --app graphhopper
```

Verify once it's up:

```bash
# Health (200 once the graph is loaded):
curl -s https://graphhopper.fly.dev/health && echo

# A round_trip loop near the start point (lat,lng), ~3 km:
curl -s 'https://graphhopper.fly.dev/route?profile=foot&point=-37.81,144.96&algorithm=round_trip&round_trip.distance=3000&round_trip.seed=1&points_encoded=false&instructions=false' \
  | jq '.paths[0].distance'
```

The second call should return a distance near 3000. A `400`/empty `paths`
either means the point is outside the imported region or CH is still enabled.

## How the generate-route Lambda points at it

The production caller is the dedicated **generate-route Lambda**
(`apps/web/lambda/generate-route/`), wired via CloudFront to `/api/routes/generate`.
Its `GRAPHHOPPER_URL` env (set by Terraform) points at this app's public URL:

```
GRAPHHOPPER_URL = https://graphhopper.fly.dev
```

**Networking differs from OSRM on purpose.** OSRM is reached by the Go *worker*,
which also runs on Fly, so OSRM stays 6PN-internal (`osrm.internal:5000`, no
public IP). GraphHopper is reached by the *Lambda*, which runs on **AWS** — there
is no 6PN path from AWS into Fly's private network, so this app exposes a
**public https service** (see [`fly.toml`](fly.toml)'s `[http_service]`). It's
one latency-tolerant `round_trip` call per seed, not a hot path. `GRAPHHOPPER_URL`
is server-only in every tier — never `PUBLIC_`, never bundled into the browser.

`GRAPHHOPPER_URL` unset → the core throws `GraphHopperError('unconfigured')` and
the Lambda returns **501**. Engine down / no loop → **502**.

## Machine sizing

| Region | PBF | RAM (flexible foot) | Fly machine |
|---|---|---|---|
| Single country (e.g. UK) | ~1.2 GB | ~2-3 GB | `shared-cpu-2x` 4 GB |
| Small region (Victoria seed) | ~200 MB | ~1 GB | `shared-cpu-2x` 4 GB |
| Continent extract | ~25 GB | ~16+ GB | `performance-4x` 16 GB+ |

The `Dockerfile` pins the JVM heap (`JAVA_OPTS=-Xmx2500m`) for the 4 GB box;
bump both the heap and `[[vm]] memory` together for a larger extract. Flexible
mode (no CH preparation) trades a little per-request latency for a much smaller
import footprint than the speed-mode default — the right trade for a handful of
latency-tolerant generation calls.
