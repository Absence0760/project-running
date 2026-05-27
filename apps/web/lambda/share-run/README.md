# Share-run Lambda

Production handler for `/share/run/*` (per-run SPA-shell HTML with
OG tags). CloudFront routes that path to this Lambda's Function URL.

Persona-hunt finding Casual #4: pre-fix, the route was prerendered at
build time via `adapter-static`. Any public run created between
builds served the SPA-shell fallback `<head>` (generic title) so
Slack / FB / X / LinkedIn unfurls of a brand-new run showed the
homepage card. Widening the prerender cap was a workaround; the real
fix is per-request SSR via this Lambda — every URL gets the right
per-run head, regardless of build cadence.

## Scope: HTML only

`/og/run/<id>.png` is intentionally NOT served by this Lambda. The
PNG renderer (`@resvg/resvg-js`) ships a native arm64 binary that
would need a Lambda Layer or `--arch=arm64 --platform=linux` build-
time install to run in the Lambda runtime — a deployment slice of
its own. Instead, `/og/run/<id>.png` stays adapter-static-prerendered
on the S3 origin with a 50k cap (covers the realistic worldwide
user base for months). For runs beyond the cap, the og:image returns
404 and crawlers degrade to text-only unfurls — but the per-run
title + description (from THIS Lambda) still land correctly. The
text fix is the critical-path fix; the missing image is cosmetic.

The SvelteKit dev-server still owns `/share/run/*` under `npm run
dev` (see `src/routes/share/run/[id]/+page.ts`) so local dev doesn't
need the Lambda standing up.

## Layout

```
src/index.ts      Lambda Function URL handler.
build.mjs         esbuild bundler — produces dist/index.mjs + share-run.zip.
                  Reads apps/web/build/index.html (built by `npm run build`)
                  and embeds the SPA shell as a string constant so the
                  Lambda can inject OG tags + serve the same bundle the
                  static-rendered routes load.
dist/             generated (gitignored)
```

## Build locally

```bash
cd apps/web
npm run build                              # produces apps/web/build/
node lambda/share-run/build.mjs            # → dist/share-run.zip
```

The CI workflow (`.github/workflows/release-web.yml`) runs both
in sequence — the Lambda artifact is rebuilt on every web tag so the
embedded SPA shell stays in sync with the deployed bundle.

## Runtime env (set by Terraform)

- `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` — non-secret,
  written by Terraform from variables. The Lambda uses the anon key
  to read `public_runs` + `public_profiles` (both anon-readable
  views), mirroring the dev-server's RLS posture.
- `APP_RELEASE`, `SENTRY_DSN` — optional, for telemetry.

The Lambda holds no secrets — every read is via the public anon key
against anon-readable views.

## Caching

Responses set `Cache-Control: public, max-age=3600` so CloudFront
caches each `/share/run/<id>` for an hour. A crawler storm against a
single share URL costs one Lambda invocation per cache window, not
per crawler. The 1h TTL means a private→public visibility flip takes
up to an hour to propagate; acceptable trade for the cache savings
on a feature that's overwhelmingly read-heavy.

## Why this isn't part of the coach Lambda

The coach Lambda streams SSE responses via `awslambda.streamifyResponse`
+ has the Anthropic SDK bundled (~500 KB). Share-run renders a static
HTML response with no streaming and doesn't need any AI deps.
Keeping the two surfaces in separate Lambdas keeps each bundle small +
makes cold-start latency predictable for both.
