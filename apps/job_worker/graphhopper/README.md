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

This directory is both the **production Fly.io app** and a **local dev stack**
(`docker-compose.yml` + `Makefile`) — see [Run locally](#run-locally) to bring
the engine up on your machine and point the web dev server at it.

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

- **Flexible mode + Landmarks, no CH.** `round_trip` is a core GraphHopper
  algorithm but it only runs in **flexible mode** — Contraction Hierarchies (the
  default speed preparation) cannot serve it. `config.yml` leaves
  `profiles_ch: []` so a plain `round_trip` request succeeds **without** the
  caller passing `ch.disable=true` (the core doesn't send it). It DOES prepare
  **Landmarks** (`profiles_lm: [{profile: foot}]`, hybrid mode), which accelerate
  the flexible leg-routing each `round_trip` does — worth the import cost because
  a generate request fans out several seeds concurrently, so per-query CPU is the
  bottleneck. If you re-enable CH, generation breaks with a "round trip not
  supported with CH" error.

- **Encoded values must be declared.** The `foot` profile uses GraphHopper's
  built-in `foot.json` custom model via `custom_model_files: [foot.json]`. GH 10
  does **not** auto-import the encoded values that model references, so
  `config.yml` lists them explicitly in `graph.encoded_values` (`foot_access,
  foot_priority, foot_average_speed, hike_rating, mtb_rating`). A missing entry
  fails the boot with `Encoded values missing: …`; an inline hand-copied model is
  worse still (GH 10 retired names like `foot_road_access`). Let the bundled
  model own the weighting.

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

# 4. Set the shared-secret guard key (the Caddy front rejects /route without it):
flyctl secrets set GRAPHHOPPER_API_KEY=<same value as the sops GRAPHHOPPER_API_KEY> --app graphhopper

# 5. Restart so the first boot imports the PBF into /data/graph-cache
#    (several minutes for a country extract — the /health check's grace_period
#    covers it):
flyctl machine list --app graphhopper        # get the machine id
flyctl machine restart <id> --app graphhopper
```

Verify once it's up (`/route` needs the key; `/health` is open):

```bash
# Health (200 once the graph is loaded; no key needed):
curl -s https://graphhopper.fly.dev/health && echo

# A round_trip loop near the start point (lat,lng), ~3 km — WITH the guard key:
curl -s -H "X-Engine-Key: $GRAPHHOPPER_API_KEY" \
  'https://graphhopper.fly.dev/route?profile=foot&point=-37.81,144.96&algorithm=round_trip&round_trip.distance=3000&round_trip.seed=1&points_encoded=false&instructions=false' \
  | jq '.paths[0].distance'
```

The second call should return a distance near 3000. A `403` means the key is
missing/wrong; a `400`/empty `paths` means the point is outside the imported
region or CH is still enabled.

## Run locally

Mirrors the OSRM local stack next door. The `docker-compose.yml` builds the same
`Dockerfile` the Fly app ships (so local == prod, at the cost of a one-time
from-source Maven build), mounts `./data`, and serves on `127.0.0.1:8989`.

```bash
# From the repo root:
npm run dev:setup:graphhopper    # one-time: seed the PBF (reuses the OSRM
                                 # extract if present) + build the image
npm run dev:run:graphhopper      # boots it; first run imports the graph + LM
                                 # (a few min for the Victoria seed), then caches
```

`dev:run:graphhopper` preflight-checks the PBF and prints the setup recipe if
it's missing. Equivalent raw commands (from `apps/job_worker/graphhopper`):
`make seed && docker compose up --build`.

Then point the web dev server at it by adding to your gitignored
`apps/web/.env.local` (higher priority than the committed `.env.development`,
which leaves it empty so a fresh `vite dev` / CI uses the OSRM fallback):

```
GRAPHHOPPER_URL=http://127.0.0.1:8989
```

Restart `vite dev` and the route builder's "Generate a route by distance" now
exercises the real server path. Without it, `/api/routes/generate` returns 501
and the builder falls back to the in-browser OSRM heuristic — generation still
works either way. Smoke-test the engine directly with `make smoke` (a `foot`
`round_trip` near the Melbourne seed coords). After a `config.yml` change
(profile, LM, encoded values), `make clean` wipes the graph so the next boot
re-imports.

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
the Lambda returns **501**. Engine down / no loop / guard rejection → **502**.

### Shared-secret guard

Because the engine is **public** (no 6PN path from AWS), it would otherwise be an
open denial-of-wallet surface — anyone who learns the hostname could hammer
`/route` and bypass the CloudFront WAF rate-limit. So a tiny **Caddy** front
([`Caddyfile`](Caddyfile)) owns the public port and only proxies to GraphHopper
(localhost-bound on 8990) when the `X-Engine-Key` header matches the
`GRAPHHOPPER_API_KEY` secret. `/health` stays open for Fly's machine check.

- **Sender:** the generate core (`apps/web/src/lib/routes/generate/graphhopper.ts`)
  sends the header. The Lambda reads `GRAPHHOPPER_API_KEY` from its env, injected
  by Terraform from the sops secrets file (only that one key, not the whole bag).
- **Engine:** set the SAME value as a Fly app secret (step 4 above). Caddy reads
  it from the environment.
- **Fail-closed + loud:** a missing/mismatched key → Caddy 403 → the handler
  returns 502 → the `generate-route-engine-unreachable` CloudWatch alarm fires.
  A key set on the engine but not in sops is a misconfiguration that pages, not
  one that silently breaks.

Locally this is transparent: `docker-compose.yml` defaults the container to
`dev-graphhopper-key` and `apps/web/.env.development` sends the same value, so the
opt-in local engine works without extra setup.

## Machine sizing

| Region | PBF | RAM (flexible foot) | Fly machine |
|---|---|---|---|
| Single country (e.g. UK) | ~1.2 GB | ~2-3 GB | `shared-cpu-2x` 4 GB |
| Small region (Victoria seed) | ~200 MB | ~1 GB | `shared-cpu-2x` 4 GB |
| Continent extract | ~25 GB | ~16+ GB | `performance-4x` 16 GB+ |

The `Dockerfile` pins the JVM heap (`JAVA_OPTS=-Xmx2500m`) for the 4 GB box;
bump both the heap and `[[vm]] memory` together for a larger extract. Flexible
mode (no CH) keeps the import footprint far below the speed-mode default; the
Landmarks (LM) preparation adds a little import time + RAM in exchange for much
lower per-query CPU, which is what matters when a generate request fans out
several `round_trip` seeds at once.
