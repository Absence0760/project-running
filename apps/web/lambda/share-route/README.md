# Share-route Lambda

Production handler for two per-route share surfaces, both routed to
this Lambda's Function URL by CloudFront:

- `/share/route/<id>` — per-route SPA-shell HTML with OG tags + JSON-LD
- `/og/route/<id>.png` — per-route og:image PNG (privacy-clipped track)

Symmetric mirror of the [share-run Lambda](../share-run/README.md).
Pre-fix, both routes were prerendered at build time via
`adapter-static` (`entries()` from `public_routes`, capped at 5k). A
route made public *after* a build — or beyond the cap — served the
SPA-shell fallback `<head>` (generic "Threkir" title, no per-route OG)
AND a 404 for the og:image until the next deploy; a public→private
flip stayed served from S3 until overwritten. Widening the prerender
cap was a workaround; the real fix is per-request SSR via this Lambda
— every URL gets the right per-route head AND a matching image,
regardless of build cadence.

## og:image PNG

`/og/route/<id>.png` is rendered at request time by `handlePng` in
`src/index.ts`, which calls the shared `renderRouteOgPng` helper
(`src/lib/share/og_route_png.ts`) — the same helper the SvelteKit dev
endpoint uses. A route that can't be loaded (private / deleted / never
existed) renders a generic branded card and returns **HTTP 200**, so a
social unfurl never breaks with a 404 image.

The track polyline comes from the `clip_track_for_user` SECURITY
DEFINER RPC (the same path non-owner route viewers use) so privacy
zones are applied server-side — a runner's home / work coordinate
never leaks into a public unfurl image.

The renderer (`@resvg/resvg-js`) is a native addon. esbuild can't
inline a `.node` binary, so `build.mjs` keeps the loader package + the
arm64 native binary external and copies both into the zip's
`node_modules`. The Lambda runs on **arm64** (`architectures =
["arm64"]` in `infra/modules/web-stack/main.tf`), so the build host
must have `@resvg/resvg-js-linux-arm64-gnu` resolvable.

**Operator / CI note:** on a linux/x64 build host (incl. GitHub
Actions `ubuntu-latest`), `npm ci` downloads optional deps for other
platforms by default, so the arm64 package is normally present. If
`build.mjs` fails with a missing-`@resvg/resvg-js-linux-arm64-gnu`
error, install it explicitly before building the zip:

```bash
npm install --force --workspace=apps/web --cpu=arm64 --os=linux @resvg/resvg-js-linux-arm64-gnu
```

The SvelteKit dev-server still owns `/share/route/*` and
`/og/route/*.png` under `npm run dev` (see
`src/routes/share/route/[id]/+page.ts` and
`src/routes/og/route/[id].png/+server.ts`) so local dev doesn't need
the Lambda standing up.

## HTML head

`/share/route/<id>` injects per-route tags into the SvelteKit SPA
shell at request time via `injectShareRouteMeta`
(`src/lib/share/share_route_spa_shell.ts`). The tag set is built by
`buildShareRouteHead` (`src/lib/share/share_route_meta.ts`) reusing the
shared `buildRouteShareTitle` / `buildRouteShareDescription` /
`buildRouteShareCanonical` / `buildRouteJsonLd` helpers — so the
Lambda head and the dev-server `<svelte:head>` stay in lockstep. A
route that isn't public returns the not-found shell (HTTP 404) — the
public share page is for public routes; owners view their own routes
at `/routes/<id>`.

## Layout

```
src/index.ts      Lambda Function URL handler (HTML + PNG routing).
build.mjs         esbuild bundler — produces dist/index.mjs + share-route.zip.
                  Reads apps/web/build/index.html (built by `npm run build`)
                  and embeds the SPA shell as a string constant so the
                  Lambda can inject OG tags + serve the same bundle the
                  static-rendered routes load. Copies the @resvg loader +
                  arm64 native binary into dist/node_modules before zipping.
dist/             generated (gitignored)
```

## Build locally

```bash
cd apps/web
npm run build                              # produces apps/web/build/
node lambda/share-route/build.mjs          # → dist/share-route.zip
```

The CI workflow (`.github/workflows/release-web.yml`) runs both in
sequence — the Lambda artifact is rebuilt on every web tag so the
embedded SPA shell stays in sync with the deployed bundle.

## Runtime env (set by Terraform)

- `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` — non-secret,
  written by Terraform from variables. The Lambda uses the anon key to
  read `public_routes` (anon-readable view) + the `clip_track_for_user`
  RPC, mirroring the dev-server's RLS posture.
- `PUBLIC_SITE_URL` — env-specific canonical origin for the absolute
  `og:url` / `og:image` / canonical / JSON-LD URLs.

The Lambda holds no secrets — every read is via the public anon key
against anon-readable views + the privacy-clipping RPC.

## Caching

Responses set `Cache-Control: public, max-age=300, s-maxage=300,
stale-while-revalidate=60` so CloudFront caches each
`/share/route/<id>` and `/og/route/<id>.png` for ~5 min. A crawler
storm against a single share URL costs one Lambda invocation per cache
window, not per crawler. The 5-min TTL caps how long a public→private
visibility flip stays visible on the unfurl. The CloudFront
`share_route` cache policy's `default_ttl`/`max_ttl` are pinned to 300
to match.

## Why this isn't part of the share-run Lambda

Each share surface keeps its own Lambda so a deploy / rollback /
concurrency limit on one can't affect the other, and the IAM /
CloudWatch / alarm surface stays one-resource-per-function. The two
share bundles are near-identical in shape but independent in
lifecycle.
