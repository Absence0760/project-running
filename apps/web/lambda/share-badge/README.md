# Share-badge Lambda

Production handler for two per-badge share surfaces, both routed to this
Lambda's Function URL by CloudFront:

- `/share/badge/<id>` — per-badge SPA-shell HTML with OG tags
- `/og/badge/<id>.png` — per-badge og:image PNG

Same shape and rationale as the share-run Lambda (`../share-run/README.md`):
per-request SSR so a badge earned between builds still unfurls with the right
`<head>` and a matching og:image, regardless of build cadence. A private /
missing badge returns a 404 for the HTML (clean crawler signal) but a 200
generic-card PNG (an unfurl image must never 404).

Public-row column discipline: the lookup (`lookupSharedBadge`) selects only the
public, milestone-safe columns and filters on `is_public = true`. A badge card
exposes a numeric milestone + a date, never any track/location data.

## Build

Run from `apps/web/`:

```bash
npm run build               # produces build/200.html (the SPA shell)
node lambda/share-badge/build.mjs
```

Output: `apps/web/lambda/share-badge/dist/share-badge.zip`. The `@resvg`
native arm64 binary is copied into the zip's `node_modules` (esbuild can't
inline a `.node` addon); the Lambda runs on arm64 / Node 24.

## Wiring (deploy gate)

CloudFront behaviours for `/share/badge/*` and `/og/badge/*` must route to this
Lambda's Function URL — mirror the share-run behaviours in
`infra/modules/web-stack/main.tf`, and add the zip to the web release workflow.
Until that infra is wired, the SvelteKit dev-server endpoints
(`src/routes/share/badge/[id]` + `src/routes/og/badge/[id].png`) own the path
locally and the static build serves the SPA-shell fallback in prod.
