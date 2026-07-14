# osrm-proxy Lambda

AWS Lambda Function URL handler for **`/api/routes/osrm/*`** — the server-side
proxy in front of the self-hosted OSRM engine for the route builder's manual
waypoint snapping/routing. CloudFront routes that path to this Lambda's
Function URL (see `infra/modules/web-stack/main.tf` and
[decisions §242](../../../../docs/architecture/decisions.md)).

## What it does

Accepts OSRM-shaped GET paths (`/nearest/v1/{foot|car}/{lng,lat}` and
`/route/v1/{foot|car}/{lng,lat;...}`), validates every part (service, profile,
coordinate ranges and counts, allowlisted query params), requires a signed-in
Supabase user, and re-issues the request against `OSRM_URL`, returning the
OSRM JSON verbatim. The validation + auth core is transport-agnostic at
`apps/web/src/lib/routes/osrm_proxy/handler.ts`, also wrapped by the dev-only
SvelteKit route `src/routes/api/routes/osrm/[...path]/+server.ts`.

## Why a server-side hop

The route builder's pins are user-chosen map points — the first is very often
the user's home. The old client path fetched the OSRM host directly from the
browser over a `PUBLIC_` env, so precise location + client IP left our client
with no server boundary in between (issue #198). `OSRM_URL` is server-only
here, matching `GRAPHHOPPER_URL` on the generate path: the browser can't
reach the engine and the coordinates never leave our infra unproxied. The
proxy rebuilds the upstream URL from validated parts, so it can't be used as
an open relay, and it requires a user JWT so it isn't a free public OSRM.

## Build

```
node lambda/osrm-proxy/build.mjs    # from apps/web/
```

Output: `dist/osrm-proxy.zip` (esbuild bundle, no native deps). CI's
`release-web.yml` rebuilds + updates the Lambda on every `web@*` tag.

## Env

| Var | Required | Notes |
|-----|----------|-------|
| `OSRM_URL` | yes (prod) | Self-hosted OSRM base URL (`apps/job_worker/osrm/`). Unset → the handler returns 501; the builder degrades to straight-line segments. The demo fallback (`router.project-osrm.org`) is dev-wrapper-only and hard-disabled here. |
| `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_ANON_KEY` | yes | Back the auth gate's `auth.getUser` check. Missing → the gate fails closed (500). |

## Fallback contract

The web client treats any non-200 as "this snap/segment failed": snapping
returns the un-snapped pin, per-segment routing falls back to a straight line
with the existing warning banner. An engine outage degrades route-builder
quality, it never breaks the page.
