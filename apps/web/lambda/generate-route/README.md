# generate-route Lambda

AWS Lambda Function URL handler for **`/api/routes/generate`** — the server-side
"Generate a route by distance" loop generator. CloudFront routes that path to
this Lambda's Function URL (see `infra/modules/web-stack/main.tf` and
[decisions §53](../../../../docs/architecture/decisions.md)).

## What it does

Takes `{ start: { lat, lng }, targetDistanceM, seeds? }`, fans out a few
GraphHopper `round_trip` seeds against the self-hosted engine
(`GRAPHHOPPER_URL`), and returns the best-shaped loop as
`{ coordinates: [lng,lat][], distanceM }`. The shape-aware selection (maximise
enclosed-area efficiency) lives in the transport-agnostic core at
`apps/web/src/lib/routes/generate/`, which is also wrapped by the dev-only
SvelteKit route `src/routes/api/routes/generate/+server.ts`.

## Why a server-side engine call

The old in-browser heuristic (`route_loop.ts`) planted a fixed radial scaffold,
snapped each seed to a road via OSRM, and bisected a single radius knob over ~4
latency-bound iterations. On a lopsided road network it overshot badly (a 5 km
target → an 8.22 km lasso with a long spur). GraphHopper's `round_trip`
algorithm hits the target distance in one engine call per seed; running it
server-side removes the browser's per-request batching/CORS budget so we can
race several seeds and keep the best-shaped one. `GRAPHHOPPER_URL` is a
server-only env — the browser never calls the engine directly, so user
start-coordinates never leave our infra.

## Build

```
node lambda/generate-route/build.mjs    # from apps/web/
```

Output: `dist/generate-route.zip` (esbuild bundle, no native/SDK deps). CI's
`release-web.yml` rebuilds + updates the Lambda on every `web@*` tag.

## Env

| Var | Required | Notes |
|-----|----------|-------|
| `GRAPHHOPPER_URL` | yes (prod) | Self-hosted GraphHopper base URL (`apps/job_worker/graphhopper/`). Unset → the handler returns 501 and the client falls back to its in-browser OSRM heuristic. |

## Fallback contract

The web client treats any non-200 (501 unconfigured / 502 engine down / 503
unhandled) as a signal to fall back to the legacy in-browser OSRM loop
generator, so generate-by-distance keeps working through an engine outage or in
local dev without GraphHopper running.
