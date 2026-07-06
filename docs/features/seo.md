# SEO & social-unfurl architecture

How the web app (the only SEO-relevant surface — mobile/watch have none)
gets indexed and unfurled. Single source of truth for the per-surface
render mode, structured-data types, and the crawl/redirect contract.
Rationale in [decisions.md §205](../architecture/decisions.md) (+ §53
hosting, §147 event-meet-point privacy, §161 learn prerendering).

## The core problem

`apps/web` is a statically-prerendered SPA (`@sveltejs/adapter-static`).
Any route rendered **client-side** serves the empty `index.html` shell to:

- **Non-Google crawlers + every social link-unfurler** (Slack, iMessage,
  WhatsApp, Facebook, LinkedIn, X) — they run **no JS**, so they only ever
  see the shell's generic `<head>`.
- **Googlebot** — indexes eventually via a deferred JS-render pass, but
  never sees a page-specific title/description/canonical in the raw HTML.

The fix is per-surface: **prerender** what's static, **Lambda-SSR** what's
dynamic-but-public, and leave the auth-gated app CSR (it shouldn't be
indexed anyway).

## Per-surface render map

| Surface | Mode | `<head>` owner | Structured data |
|---|---|---|---|
| `/` landing | prerendered | `SeoHead.svelte` + `+page.ts` | `Organization` + `WebSite` |
| `/learn`, `/learn/[slug]`, `/learn/category/[c]` | prerendered (`entries()`) | inline `<svelte:head>` | `Article` + `BreadcrumbList` |
| `/sitemap.xml` | prerendered | — | — |
| `/share/run/[id]`, `/og/run/[id].png` | Lambda-SSR (`share-run`) | `share_run_meta` | `WebPage` + breadcrumb |
| `/share/route/[id]`, `/og/route/[id].png` | Lambda-SSR (`share-route`) | `share_route_meta` | `WebPage` + breadcrumb |
| `/share/badge/[id]`, `/og/badge/[id].png` | Lambda-SSR (`share-badge`) | `share_badge_meta` | — |
| `/recap/share/[id]`, `/og/recap/[id].png` | Lambda-SSR (`share-recap`) | `share_recap_meta` | — |
| `/share/event/[id]` | Lambda-SSR (`share-entity`) | `share_event_meta` | `SportsEvent`/`Event` |
| `/share/profile/[id]` | Lambda-SSR (`share-entity`) | `share_profile_meta` | `ProfilePage` + `Person` |
| `/share/club/[slug]` | Lambda-SSR (`share-entity`) | `share_club_meta` | `SportsOrganization` |
| `/share/race/[id]` | Lambda-SSR (`share-entity`) | `share_race_meta` | `SportsEvent` |
| dashboard / runs / `/u/[id]` / `/clubs/*` / `/races` / feed / … | CSR (app shell) | generic shell | — (auth-gated, not indexed) |

## Canonical consolidation (in-app → share twin)

Several entities have both an **in-app** page (CSR, inside the app shell,
often login-gated) and a **public share** page built for indexing. To stop
the two URLs splitting ranking signal, each in-app page emits a
`<link rel="canonical">` pointing at its public twin:

| In-app page | canonical → |
|---|---|
| `/routes/[id]` | `/share/route/[id]` |
| `/u/[id]` | `/share/profile/[id]` |
| `/clubs/[slug]` | `/share/club/[slug]` |
| `/clubs/[slug]/events/[id]` | `/share/event/[id]` |

The canonical derives from the URL param (via `build<X>ShareCanonical`),
so it's present even before/without the client data load. Runs already
carry this on `/runs/[id]` → `/share/run/[id]`.

## The shared entity-SSR Lambda

`apps/web/lambda/share-entity/` — **one HTML-only Lambda** dispatching the
four `/share/{event,profile,club,race}` paths (vs cloning the ~10-resource
share-badge stack 4×, decision §205). Each path resolves the same shape:

```
share_<x>_lookup (anon-readable rows only)
  → build<X>Head (pure: title/desc/canonical/ogImage/jsonLd)
  → render<X>HeadTags (pure: escaped <head> string)
  → injectEntityHead (generic: strips shell's stale title/og/canonical/
    JSON-LD, splices the per-entity tags before </head>)
```

No per-entity `og:image` PNG — the OG image is the branded `og-default.png`
(events/races) or the entity's avatar URL (profiles/clubs) — so the Lambda
needs no native rasteriser and runs at 256 MB. Fail-open: a private /
missing / deleted entity returns **404 HTML with `noindex`**, never a 5xx.

The matching SvelteKit routes carry `prerender = false` and run the same
lookup + meta under `vite dev`, so every surface works locally and is
e2e-tested without standing up the Lambda.

### Privacy invariants (do not regress)

- **Events**: JSON-LD `location` is the club's coarse `location_label`
  only — never the precise `meet_lat/meet_lng` (§147).
- **Races**: only `location_label` is surfaced; the `location_point`
  geometry is never selected.
- **Profiles**: only the anon-safe display name + avatar (via the
  `public_profile_by_id` SECURITY DEFINER RPC) — no email / private field.
- **Profiles are NOT in the sitemap** — no people-directory crawl
  manifest; profiles are link-discoverable only.
- **Shadow-hidden (moderation auto-hidden) targets must not surface.**
  `shadow_hidden` (migration 20270218_001) drops a target from every
  public/search/discovery surface. This is now enforced at **two layers**:
  (1) the base-table RLS SELECT policies for `clubs` + `events` exclude
  shadow-hidden rows for anon/non-members (migration 20270328_001 — the
  backstop, so a NEW anon read can't silently leak), while owner/admins
  keep visibility; and (2) the SEO surfaces still carry their own explicit
  `shadow_hidden = false` filter (club/sitemap directly; event/sitemap via
  the parent club) as belt-and-braces. Profiles are covered because
  `public_profile_by_id` already filters it. The RLS backstop means adding
  a new club/event read is safe by default, but keep filtering explicitly
  on any new public surface for defense in depth.

## Shared marketing/brand pieces

- **`$lib/components/SeoHead.svelte`** — reusable `<svelte:head>` (title,
  description, canonical, OG, Twitter, JSON-LD) for prerendered pages, so
  they stop hand-rolling — and drifting — their head. Per-entity share
  pages keep inline heads (their prod path is the Lambda injector).
- **`$lib/share/site_meta.ts`** — `Organization` + `WebSite` JSON-LD.
  `WebSite` carries **no** `SearchAction` (no public search endpoint to
  target); `Organization` carries no `sameAs` until real profiles exist.
- **First paint** (under the hash-based CSP, which forbids a hand-written
  inline theme-bootstrap `<script>`): `<meta name="color-scheme">` in
  `app.html` (correct UA default background before CSS) + a per-env
  Supabase `preconnect` in the layout head.

## Crawl & redirect contract

- **`static/robots.txt`** — allows `/`, disallows the auth-gated app paths
  (`/dashboard`, `/settings`, …), points at `/sitemap.xml`. `/share/*` is
  allowed.
- **`/sitemap.xml`** (`sitemap.xml/+server.ts` + `$lib/share/sitemap.ts`)
  — build-time, anon-fetched: public routes + runs (popularity-weighted),
  learn pages, and public **events + clubs + races** (`entityEntries`).
  Graceful-degrades to top-level-only if Supabase is unreachable at build.
- **`www` → apex 301** — a viewer-request CloudFront Function
  (`infra/modules/web-stack/functions/www_redirect.js`, gated on
  `redirect_www_to_apex`, prod-only) 301s any `www.*` host to the bare
  apex, preserving path + query, on every cache behavior. Consolidates the
  duplicate host that otherwise split ranking signal.

## Deploy gate

The `share-entity` Lambda + its CloudFront/OIDC/release wiring and the www
redirect are **landed but deploy-gated** — they need a `terraform apply`
(prod) + a first `web@*` deploy to go live, the same posture the other
share Lambdas shipped under. Until then the SvelteKit dev/build path serves
the routes; prod serves the SPA shell for the new `/share/*` paths.

### Fit with the minimal (Lean / Rock-bottom) deploy

All of this rides **every** cost tier, including Rock-bottom (~$10–11/mo,
web-only, Supabase Free) — see [deployment_lean.md](../ops/deployment_lean.md):

- The `share-entity` Lambda is an **unconditional** resource in the
  web-stack module, exactly like `share-run/route/badge/recap` — it
  deploys on the same first `terraform apply` and costs **~nothing idle**
  (Lambda is pay-per-invocation; no provisioned/idle cost). Until the first
  `web@*` release swaps in real code it runs the placeholder zip (same as
  every share/coach Lambda on first apply).
- It needs **no deferred service** — only the anon key + the public
  views/RLS, all present on Supabase Free. So the four `/share/*` surfaces
  work at Rock-bottom even with the worker, engines, and coach all off.
- The **www→apex CloudFront Function** is prod-only (`redirect_www_to_apex`)
  and CloudFront Functions bill per-invocation at negligible cost.
- The **sitemap** is a build-time static artifact; its entity fetches sit
  in the same try/catch as the route/run fetches, so a paused Supabase Free
  instance at build time degrades to a top-level-only sitemap rather than
  failing the build.
- Reserved concurrency: `share-entity` uses the shared
  `lambda_reserved_concurrency` cap (prod 20), so the six reserved-
  concurrency Lambdas total 120 in prod — far under the account's
  keep-100-unreserved floor. Worth a glance only if that account limit is
  ever lowered.

## Adding a new indexable surface

1. Prerenderable (finite, evergreen)? Add `prerender = true` + `entries()`
   and set the head via `SeoHead` — no Lambda. (Pattern: `/learn`.)
2. Dynamic but public? Add a `share_<x>_lookup` (anon rows only) +
   `share_<x>_meta` (pure builder + `render<X>HeadTags`), a
   `/share/<x>/[id]` route (`prerender = false`), and a branch in the
   `share-entity` Lambda dispatcher + a CloudFront `/share/<x>/*` behavior.
3. Add it to `sitemap.xml` via a `sitemap.ts` builder (unless it's a
   people-directory — don't enumerate those).
4. Unit-test the meta builder; e2e the not-found head (deterministic).
