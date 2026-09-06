# Share-run Lambda

Production handler for two per-run share surfaces, both routed to this
Lambda's Function URL by CloudFront:

- `/share/run/<id>` — per-run SPA-shell HTML with OG tags
- `/og/run/<id>.png` — per-run og:image PNG

Persona-hunt finding Casual #4 (HTML) + round-5 very-social (PNG):
pre-fix, both routes were prerendered at build time via
`adapter-static`. Any public run created between builds served the
SPA-shell fallback `<head>` (generic title) AND a 404 for the
og:image, so Slack / FB / X / LinkedIn unfurls of a brand-new run
showed the homepage card with a broken image. Widening the prerender
cap was a workaround; the real fix is per-request SSR via this Lambda
— every URL gets the right per-run head AND a matching image,
regardless of build cadence.

## og:image PNG (round-5 very-social)

`/og/run/<id>.png` is rendered at request time by `handlePng` in
`src/index.ts`, which calls the shared `renderRunOgPng` helper
(`src/lib/share/og_run_png.ts`) — the same helper the SvelteKit dev
endpoint uses. A run that can't be loaded (private / deleted / never
existed) renders a generic branded card and returns **HTTP 200**, so
a social unfurl never breaks with a 404 image.

The renderer (`@resvg/resvg-js`) is a native addon. esbuild can't
inline a `.node` binary, so `build.mjs` keeps the loader package + the
arm64 native binary external and copies both into the zip's
`node_modules`. The Lambda runs on **arm64** (`architectures =
["arm64"]` in `infra/modules/web-stack/main.tf`), so the build host
must have `@resvg/resvg-js-linux-arm64-gnu` resolvable.

**Operator / CI note:** on a linux/x64 build host (incl. GitHub
Actions `ubuntu-latest`), `npm ci` installs only the optional native
deps matching the HOST platform, so the arm64 package is NOT present
after a plain install (this failed the first `web@*` release;
`release-web.yml` now carries an explicit install step). If
`build.mjs` fails with a missing-`@resvg/resvg-js-linux-arm64-gnu`
error, install it explicitly before building the zip:

```bash
ver="$(node -p "require('@resvg/resvg-js/package.json').version")"
npm pack "@resvg/resvg-js-linux-arm64-gnu@${ver}" --pack-destination /tmp
mkdir -p node_modules/@resvg/resvg-js-linux-arm64-gnu
tar -xzf "/tmp/resvg-resvg-js-linux-arm64-gnu-${ver}.tgz" -C node_modules/@resvg/resvg-js-linux-arm64-gnu --strip-components=1
```

(Do **not** `npm install --cpu=arm64 --os=linux` it: that re-evaluates the
whole tree's optional deps for arm64 and prunes the x64 native bindings
the build toolchain itself needs — rolldown lost its host binding this
way on the `web@1.0.2` release.)

The SvelteKit dev-server still owns `/share/run/*` and
`/og/run/*.png` under `npm run dev` (see
`src/routes/share/run/[id]/+page.ts` and
`src/routes/og/run/[id].png/+server.ts`) so local dev doesn't need
the Lambda standing up.

## Layout

```
src/index.ts      Lambda Function URL handler (HTML + PNG routing).
build.mjs         esbuild bundler — produces dist/index.mjs + share-run.zip.
                  Reads apps/web/build/200.html (built by `npm run build`)
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

Responses set `Cache-Control: public, max-age=300, s-maxage=300,
stale-while-revalidate=60` so CloudFront caches each `/share/run/<id>`
and `/og/run/<id>.png` for ~5 min. A crawler storm against a single
share URL costs one Lambda invocation per cache window, not per
crawler. The 5-min TTL (down from the original 1h) caps how long a
public→private visibility flip stays visible on the unfurl —
persona-hunt Round 3 finding Privacy #3. The CloudFront `share_run`
cache policy's `default_ttl`/`max_ttl` are pinned to 300 to match.

## Why this isn't part of the coach Lambda

The coach Lambda streams SSE responses via `awslambda.streamifyResponse`
+ has the Anthropic SDK bundled (~500 KB). Share-run renders a static
HTML response with no streaming and doesn't need any AI deps.
Keeping the two surfaces in separate Lambdas keeps each bundle small +
makes cold-start latency predictable for both.
