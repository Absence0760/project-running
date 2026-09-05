# share-recap Lambda

AWS Lambda Function URL handler for the public recap share surface. Sibling of
`../share-run/` — read that README for the full rationale; this one is the same
shape applied to recaps.

## Paths owned (in production)

CloudFront routes these two behaviours to this Lambda's Function URL:

- `/recap/share/<id>` — per-recap SPA-shell HTML with the right per-recap
  `<title>` + Open Graph / Twitter tags baked in before a crawler sees it.
- `/og/recap/<id>.png` — the per-recap og:image PNG (1200×630, rendered via
  resvg from the frozen aggregate snapshot — no GPS, no per-run rows).

Both render at request time. Under `adapter-static` the matching SvelteKit
routes carry `prerender = false`; the dev server owns the path locally, the
Lambda owns it in prod. A recap published after the last web build still
unfurls correctly because the Lambda fetches the snapshot per request.

Missing / revoked recaps get a 404 HTML (crawler-honest) and a 200 branded
fallback PNG (an unfurl must never show a broken image).

## Build

```bash
cd apps/web
npm run build                 # produces build/200.html (the SPA shell)
node lambda/share-recap/build.mjs
# → apps/web/lambda/share-recap/dist/share-recap.zip
```

The zip bundles `src/index.ts` + its `$lib` imports (supabase-js inlined) and
copies the arm64 `@resvg/resvg-js` native package into `node_modules`. Needs
`@resvg/resvg-js-linux-arm64-gnu` resolvable — npm ci only installs
host-platform optional deps, so on x64 fetch it via `npm pack` + untar into
`node_modules` (recipe in `share-run/README.md`; never
`npm install --cpu=arm64`, which prunes the host toolchain's own bindings).

## Env vars (set on the Lambda)

- `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` — anon read of a recap
  by id via the `public_recap_by_id` RPC (the bare table is not enumerable —
  migration `20270305_001`).
- `PUBLIC_SITE_URL` — og:url base (defaults to `https://threkir.com`).
