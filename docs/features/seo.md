# SEO & social-unfurl architecture

How the web app (the only SEO-relevant surface — mobile/watch have none)
gets indexed and unfurled. Single source of truth for the per-surface
render mode, structured-data types, and the crawl/redirect contract.
Rationale in [decisions.md §205](../architecture/decisions.md) (+ §53
hosting, §147 event-meet-point privacy, §161 learn prerendering).

## The core problem

`apps/web` is a statically-prerendered SPA (`@sveltejs/adapter-static`).
Any route rendered **client-side** serves the empty `200.html` shell to:

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
| `/learn/[slug]` | prerendered (`entries()`) | inline `<svelte:head>` + `buildGuideJsonLd` | `Article` (with an embedded `BreadcrumbList`) |
| `/learn` | prerendered | inline `<svelte:head>` + `buildLearnCollectionJsonLd` | `CollectionPage` (with an embedded `BreadcrumbList` + an `ItemList` of the guides listed) |
| `/learn/category/[category]` | prerendered (`entries()`) | inline `<svelte:head>` + `buildLearnCollectionJsonLd` | `CollectionPage` (with an embedded `BreadcrumbList` + an `ItemList` of the guides listed) |
| `/sitemap.xml` | prerendered | — | — |
| `/share/run/[id]`, `/og/run/[id].png` | Lambda-SSR (`share-run`) | `share_run_meta` | `WebPage` + breadcrumb |
| `/share/route/[id]`, `/og/route/[id].png` | Lambda-SSR (`share-route`) | `share_route_meta` | `WebPage` + breadcrumb |
| `/share/badge/[id]`, `/og/badge/[id].png` | Lambda-SSR (`share-badge`) | `share_badge_meta` | — |
| `/recap/share/[id]`, `/og/recap/[id].png` | Lambda-SSR (`share-recap`) | `share_recap_meta` | — |
| `/share/event/[id]` | Lambda-SSR (`share-entity`) | `share_event_meta` | `SportsEvent`/`Event` |
| `/share/profile/[id]` | Lambda-SSR (`share-entity`) | `share_profile_meta` | `ProfilePage` + `Person` |
| `/share/club/[slug]` | Lambda-SSR (`share-entity`) | `share_club_meta` | `SportsOrganization` |
| `/share/race/[id]` | Lambda-SSR (`share-entity`) | `share_race_meta` | `SportsEvent` |
| `/share/session/[id]` | Lambda-SSR (`share-entity`) | `share_session_meta` | `WebPage` + breadcrumb |
| `/share/workout/[id]` | Lambda-SSR (`share-entity`) | `share_workout_meta` | `WebPage` + breadcrumb |
| `/runs/[id]`, `/routes/[id]`, `/u/[id]`, `/races` | CSR (app shell) | generic shell + canonical | — (auth-gated) |
| `/segments` | CSR (app shell, **anon-reachable**) | inline `<svelte:head>` title | — (in the sitemap; see below) |
| `/segments/[id]` | CSR (app shell) | generic shell | — (auth-gated, NOT in the sitemap) |
| `/clubs/[slug]`, `/clubs/[slug]/events/[id]`, `/events/[id]`, `/live/[id]`, `/recap/[year]` | CSR (app shell) | generic shell + canonical | — (anon-reachable, shell-only) |
| dashboard / feed / settings / … | CSR (app shell) | generic shell | — (auth-gated) |

**The `/` row is measured, not intended.** It was intent for as long as the
surface existed: `build/index.html` was adapter-static's SPA *fallback* — no
`<title>` (since [§ 1167](../architecture/decisions.md) moved the default into
the root layout, where a fallback rendering no components cannot reach it), no
canonical, no `og:`/`twitter:`/`description`, no `Organization`/`WebSite`
JSON-LD. Two things were wrong at once and each hid the other: `+page.ts`
exported no `prerender`, so nothing was ever written to that path; and the
adapter's fallback was *named* `index.html`, so switching prerendering on alone
would have written the landing page and then replaced it. Both are closed by
[§ 1268](../architecture/decisions.md) — `/` prerenders, and the shell moved to
`build/200.html`.

`src/lib/seo/prerendered_head_contract.test.ts` asserts the row against the
emitted HTML: the landing page's title, canonical, description, `og:`/
`twitter:` set and both JSON-LD types, plus — for every prerendered page,
`/learn` included — a canonical naming the path that page is actually served
at. `src/lib/share/spa_shell_head_signals.test.ts` measures the shell's four
head signals, all still zero, so the four strips in the share injectors are
still acting on nothing.

Two rows above are easy to misread, and both were wrong in this table before:

- **`/clubs/*`, `/events/[id]`, `/live/[id]`, `/recap/*` are NOT auth-gated.**
  The layout's `isAnonAllowed` lets anon through (public clubs + their events
  are RLS-visible to anon), so a crawler *does* reach them — they stay out of
  the index because they serve the empty shell and canonical to their share
  twin, not because a gate turns the crawler away. Do not "simplify" these
  back into the auth-gated row.
- **`/segments` is in the sitemap; `/segments/[id]` is not.** The catalogue
  index is curated, world-readable content (`global_segments` grants select to
  anon, migration `20270512_001`) and the page is in `anonExtraExact` so the
  URL the manifest advertises answers with the catalogue rather than a login
  form. A per-segment page is a leaderboard of *named runners*, which is the
  same people-directory objection that keeps profiles out — and it is CSR, so
  a crawler would only ever be handed the empty shell. Making one genuinely
  indexable is the step-2 `share-entity` path below, not a sitemap append
  (`decisions.md § 677`).
- **`/share/session/[id]` + `/share/workout/[id]` are NOT in the sitemap**,
  unlike their four `share-entity` siblings. A public gym workout is the
  athlete's own training record, and enumerating every one of them would build
  a crawlable training-log directory — the same objection that keeps profiles
  out (see *Crawl & redirect contract*). Session plans are held to the same
  line for now: link-discoverable, not crawl-enumerated. They were also the
  one pair of share routes that no Lambda served (round 11 found it, round 12
  finished them per step 2 of *Adding a new indexable surface*);
  `share_entity_dispatch_guard.test.ts` now fails if a `/share/<x>` route
  loses its CloudFront behaviour or its dispatcher branch.

### What the SPA shell carries in its `<head>`

The five share Lambdas each embed `apps/web/build/200.html` at bundle time and
splice their own head into it per request, stripping whatever stale signals the
shell carries first. Which signals those are is a fact about the artifact, so it
is measured rather than asserted: `share/spa_shell_head_signals.test.ts` pins the
counts (`{title: 0, social: 0, canonical: 0, jsonLd: 0}` as of 2026-09-05)
against `src/app.html` unconditionally, and against `build/200.html` whenever a
build is present. All four strips therefore act on nothing today; they
stay because a single `og:` default added to `app.html`, or a Lambda left
embedding `build/index.html` — the prerendered landing page since
[§ 1268](../architecture/decisions.md), which carries all four — makes them
load-bearing again in one edit; and `injectEntityHead` also serves
`notFoundShell`, where nothing about the entity may survive onto a page that
says it is gone.

The strip and splice steps live once, in `share/head_splice.ts`. It takes a
signal LIST rather than doing everything, because two heads emit no JSON-LD
block — the recap head, and the badge head that reuses the run injector — and
stripping it for them would delete the shell's own node and put nothing back
([decisions § 1114](../architecture/decisions.md) +
[§ 1115](../architecture/decisions.md)).

The canonical is not in that class, and treating it as though it were was a
defect: `renderShareRecapHeadTags` has emitted a self-referential canonical
since [§ 1090](../architecture/decisions.md), so leaving `canonical` out of the
recap injector's list kept the shell's and spliced the recap's in after it — two
conflicting `rel=canonical` links, which a crawler honours neither of. Nothing
shipped broken only because the shell carries none today, and the list above is
what says that state is provisional. The rule is per-HEAD, and for the run
injector per-CALL, because `ShareRunMeta.jsonLd` is optional
([§ 1190](../architecture/decisions.md)).

### Deploying a change to the shell filename

The shell's filename is named in three trees, and
`src/lib/seo/spa_shell_filename.test.ts` fails the PR when they disagree:

| Tree | Rail |
|---|---|
| `apps/web/svelte.config.js` | the adapter's `fallback` — writes the file |
| `apps/web/lambda/*/build.mjs` | `spaShellPath` — embeds it in each share Lambda at bundle time |
| `infra/modules/web-stack/main.tf` | the 403 `custom_error_response`'s `response_page_path` — the body of every deep link |

Those three agreeing is a repo property. Getting from one filename to another
in a LIVE distribution is not: the CloudFront apply and the artifact deploy are
separate acts, and each order leaves a window where the 403 body is wrong.
Deploy first and the bucket holds the landing page at `index.html` while the
live 403 still points there, so every deep link serves it — with its asset URLs
(`./_app/…`) resolved against the deep link's own directory, so nothing loads.
Apply first and the 403 points at a `200.html` that is not in the bucket yet.

A one-off bucket pre-seed closes the window, because the two files are
byte-identical at the moment it runs:

1. `aws s3 cp s3://<bucket>/index.html s3://<bucket>/200.html` — the live
   object is still the shell, so this adds a duplicate and changes nothing for
   anyone.
2. `terraform apply` the 403 → `/200.html`. Deep links now read the copy, which
   is the same bytes they were reading a moment ago.
3. Deploy the tag. `index.html` becomes the landing page and `200.html` is
   overwritten with the fresh shell; deep links never stop resolving.

Step 1 survives step 3's `aws s3 sync --delete` because that sync excludes
`*.html` (`.github/workflows/release-web.yml`), and an excluded destination key
is not a deletion candidate. **This sequence has never been executed against
AWS** — no CI lane holds credentials — so confirm each step at the edge before
taking the next. See [decisions § 1269](../architecture/decisions.md).

## Canonical consolidation (in-app → share twin)

Several entities have both an **in-app** page (CSR, inside the app shell,
often login-gated) and a **public share** page built for indexing. To stop
the two URLs splitting ranking signal, each in-app page emits a
`<link rel="canonical">` pointing at its public twin:

| In-app page | canonical → |
|---|---|
| `/runs/[id]` | `/share/run/[id]` |
| `/routes/[id]` | `/share/route/[id]` |
| `/u/[id]` | `/share/profile/[id]` |
| `/clubs/[slug]` | `/share/club/[slug]` |
| `/clubs/[slug]/events/[id]` | `/share/event/[id]` |
| `/sessions/[id]` | `/share/session/[id]` |
| `/gym/[id]` | `/share/workout/[id]` |

The canonical derives from the URL param (via `build<X>ShareCanonical`),
so it's present even before/without the client data load.

**An auth-gated in-app page still emits one.** Five of the seven rows sit
behind the layout auth-gate, so the crawler-consolidation argument does not
by itself carry them — but the tag is not only for crawlers. It is the
machine-readable statement of "the public home of this content is *there*",
which is what a link-preview fetcher reads, what a future prerendered or
anon-reachable variant of the surface inherits for free, and what keeps one
rule instead of a per-route judgement about who can reach what. It costs one
`$derived` string and no data load. `/runs/[id]` was the one row where the
doc claimed a fold that no code performed; §508 (a signed-in non-owner now
sees a public run there, so the URL circulates like a share URL) is the
merits case, but consistency with the four siblings would have been enough.
`seo_render_map_guard.test.ts` now fails if this table and the routes drift
apart in either direction.

**Calling a share-canonical builder is not a fold.** The builder takes its base
as a parameter precisely so the same one path definition serves a `<head>`
canonical (against `PUBLIC_SITE_URL`) *and* a copy-to-clipboard link (against
`location.origin`) — decisions §520. `/recap/[year]` and `/recap/[year]/[month]`
call `buildRecapShareCanonical` for the copy-link only and belong in **no** row
above: a recap has no share id until the runner publishes one, so there is
nothing to canonical onto. The guard's fold predicate therefore requires the
`<link rel="canonical">` as well as the builder call (§546).

## Share and unfurl-image paths

Every entity's public path is defined **once**, in a builder that takes the base
as a parameter. That covers two paths per entity, not one:

| Path | Builder | Home |
|---|---|---|
| `/share/run/[id]` | `buildRunShareCanonical` | `share_meta.ts` |
| `/og/run/[id].png` | `buildRunOgImageUrl` | `share_meta.ts` |
| `/share/route/[id]` | `buildRouteShareCanonical` | `share_meta.ts` |
| `/og/route/[id].png` | `buildRouteOgImageUrl` | `share_meta.ts` |
| `/share/badge/[id]` | `buildBadgeShareCanonical` | `share_badge_meta.ts` |
| `/og/badge/[id].png` | `buildBadgeOgImageUrl` | `share_badge_meta.ts` |
| `/recap/share/[id]` | `buildRecapShareCanonical` | `share_recap_meta.ts` |
| `/og/recap/[id].png` | `buildRecapOgImageUrl` | `share_recap_meta.ts` |
| `/share/{event,profile,club,race,session,workout}/…` | `build<X>ShareCanonical` | `share_<x>_meta.ts` |

Note the recap asymmetry: its share page is `/recap/share/[id]` (it predates the
`/share/<entity>/` family) while its unfurl image *is* under `/og/<entity>/`.
The two paths are independent — flattening either onto the other's shape 404s.

**An `og:image` must be absolute.** It is fetched by a remote crawler off-site,
so unlike an in-app `href` it genuinely can get the origin wrong; a page that
advertises the same image at two URLs (absolute in its JSON-LD, root-relative in
its `og:image`) fails invisibly. `share_url_source_guard.test.ts` registers every
site that assembles a share **or** unfurl-image path with an exact count, and
separately fails any root-relative `/og/<entity>/` in markup. Root-relative
`/share/…` **hrefs** stay out of scope (they are in-app navigations and cannot
get the origin wrong — decisions §531), pinned by a must-spare fixture.

The two rasterised card palettes both share builders paint with live in
`lib/share/og_card_palette.ts` — one light (run / route / badge unfurls) and one
dark (recap unfurl + the in-app recap share PNG), each ink carrying its measured
ratio and the ground it was measured against.

## The shared entity-SSR Lambda

`apps/web/lambda/share-entity/` — **one HTML-only Lambda** dispatching the
six `/share/{event,profile,club,race,session,workout}` paths (vs cloning the
~10-resource share-badge stack 6×, decision §205). Each path resolves the same
shape:

```
share_<x>_lookup (anon-readable rows only)
  → build<X>Head (pure: title/desc/canonical/ogImage/jsonLd)
  → render<X>HeadTags (pure: escaped <head> string)
  → injectEntityHead (generic: strips shell's stale title/og/canonical/
    JSON-LD, splices the per-entity tags before </head>)
```

No per-entity `og:image` PNG — the OG image is the branded `og-default.png`
(events/races/sessions/workouts) or the entity's avatar URL (profiles/clubs) —
so the Lambda needs no native rasteriser and runs at 256 MB. Fail-open: a private /
missing / deleted entity returns **404 HTML with `noindex`**, never a 5xx.

**What a crawler actually receives is the distribution's answer, not the
Lambda's.** `custom_error_response` is modelled per DISTRIBUTION on CloudFront,
so the SPA fallback in `infra/modules/web-stack/main.tf` replaces the BODY of
every origin's 4xx with the shell (`/200.html` since
[§ 1268](../architecture/decisions.md); `/index.html` before it, when that
filename was the shell rather than the landing page). Until [decisions § 1022](../architecture/decisions.md)
it also replaced the 404 STATUS with **200**, which made all ten
`/share/{run,route,recap,badge,event,profile,club,race,session,workout}/<id>`
paths soft 404s for a private, deleted or never-existing entity: a generic shell
at 200, with the `noindex` above sitting in a body that never shipped. The 404
mapping now answers **404** and keeps the shell body, so a crawler gets the
honest status (which is what actually de-indexes a URL — a `noindex` on a 200 is
the weaker instrument) and a human still lands on the SPA's own localized
not-found card. The 403 mapping still answers 200 and must: every dynamic client
route is a missing S3 key, so the deep-link path arrives as a 403.
`scripts/check_infra_coverage.mjs` fails a PR that maps any 4xx/5xx to a 2xx
other than that declared 403.

**Since [decisions § 1036](../architecture/decisions.md) the handlers return
that same shell themselves.** Each of the five used to carry its own unstyled
English not-found paragraph, unreachable behind the mapping and carrying the
only copy of the `noindex`; all five now answer `notFoundShell()` — the SPA
shell through `injectEntityHead`, so the stale `og:*` / canonical / JSON-LD are
stripped from a 404 exactly as they are from a 200. The reader gets the designed
card whether the edge substitutes or not, and the `noindex` survives. That makes
the 404 mapping redundant rather than load-bearing: dropping it (`infra/`, still
owed — see `followups.md`) is what finally puts the tag on the wire.

The matching SvelteKit routes carry `prerender = false` and run the same
lookup + meta under `vite dev`, so every surface works locally and is
e2e-tested without standing up the Lambda.

### Privacy invariants (do not regress)

- **Events**: JSON-LD `location` is the club's coarse `location_label`
  only — never the precise `meet_lat/meet_lng` (§147).
- **Races**: only `location_label` is surfaced; the `location_point`
  geometry is never selected.
- **Workouts**: read only through the redacted `public_gym_workouts` +
  `public_gym_sets` views (migrations 20270313_001 / 20270327_001), which omit
  `gym_workouts.notes` (1000 chars of free text) and per-set `rpe`. The meta
  says how many exercises / sets / kilograms and when — never what the owner
  wrote. Volume is canonical **kg** and the date is UTC: `formatWeight` reads
  the viewer's `preferred_unit`, so an unfurl built from it would change with
  whoever's scraper touched the link first.
- **Sessions**: the plan's authored fields only. Per-item `cue` + `tempo` are
  fetched (the visible sequence renders them) but stay out of the `<head>` —
  an og:description is handed to every unfurler, out of context.
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
  the parent club) as belt-and-braces. Profiles are covered at both layers
  too: `public_profile_by_id` filters it, and since migration 20270329_001
  the `user_profiles` base SELECT policy + the `public_profiles` view do as
  well; routes' direct-by-id paths (`is_route_visible_to` /
  `clip_route_for_viewer`, which back the route share/detail reads) are
  filtered by the same migration. The RLS backstop means adding a new
  club/event/profile/route read is safe by default, but keep filtering
  explicitly on any new public surface for defense in depth.

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
  — build-time, anon-fetched: the top-level surfaces (`/`, `/feed`,
  `/routes?tab=explore`, `/segments`), public routes + runs
  (popularity-weighted), learn pages, and public **events + clubs + races**
  (`entityEntries`).
  Graceful-degrades to top-level-only if Supabase is unreachable at build.
- **`www` → apex redirect** — a viewer-request CloudFront Function
  (`infra/modules/web-stack/functions/www_redirect.js`, gated on
  `redirect_www_to_apex`, prod-only) redirects any `www.*` host to the bare
  apex, preserving path + query, on every cache behavior. Consolidates the
  duplicate host that otherwise split ranking signal. The host is **lowercased
  before the test**, or a `WWW.` host escapes the redirect and serves the whole
  site at the second host; GET and HEAD get a **301**, every other method a
  **308**, because the function is on the `/api/*` behaviours too and a 301
  lets a client rewrite a POST into a bodiless GET
  ([decisions § 894](../architecture/decisions.md)). Behaviour is pinned by
  `www_redirect.test.mjs` beside the function, in the `parity-types` job.
- **The five share Lambdas answer GET and HEAD only.** Anything else is a
  `405` carrying `Allow: GET, HEAD` and `Cache-Control: no-store`, from
  `$lib/share/share_method_gate` — which since
  [decisions § 1035](../architecture/decisions.md) is `$lib/core/method_gate`
  instantiated at GET/HEAD, the same refusal the coach, generate-route and
  osrm-proxy Lambdas now answer with at their own allowed sets. Their CloudFront behaviours declare
  `allowed_methods = ["GET", "HEAD", "OPTIONS"]` and `cached_methods =
  ["GET", "HEAD"]`, so OPTIONS was the one method that reached the origin
  uncached — and on an `/og/*` path it ran a full resvg render before answering
  `200 image/png`, on paths no WAF rate-limit rule scopes. Nothing could rely on
  that: no handler and no response-headers policy emits any `access-control-*`
  header, so a browser preflight against these paths already failed
  ([decisions § 1005](../architecture/decisions.md)). The Terraform half is
  still asserted separately ([§ 972](../architecture/decisions.md)) — only the
  behaviour can stop a POST body being uploaded before a handler runs.
- **The absolute origin every `<head>` resolves against** is
  `PUBLIC_SITE_URL`, folded through `siteOrigin` (`$lib/core/site_url`) by
  **every** caller — the five share Lambdas and all twenty-two in-app reads
  under `src/routes/` (the `+page.ts` loaders for `/learn*`, `/recap/share/*`
  and the nine `/share/*` routes, the canonical `<svelte:head>` blocks, the
  root loader and `sitemap.xml`). Neither hand-rolled fold was safe.
  `?? DEFAULT_SITE_URL` fires only on null/undefined, so an empty env var
  survives as the origin and every `og:url` / `og:image` comes out
  root-relative ([decisions § 895](../architecture/decisions.md)).
  `|| DEFAULT_SITE_URL` catches the empty string but not a whitespace-only
  value, which is truthy and yields a canonical of `   /share/run/<id>`, and
  neither trims a trailing slash — `PUBLIC_SITE_URL=https://threkir.com/`
  produced `https://threkir.com//share/run/<id>` in every canonical, `og:url`
  and `<loc>` ([decisions § 970](../architecture/decisions.md)). The register
  that keeps all twenty-seven folded lives in `core/site_url.test.ts`.
- **The share Lambdas' two JSON responses declare their own caching.** The
  catch-all 404 — reached only when CloudFront sends a path the handler's
  regexes do not claim — carries the same
  `public, max-age=300, s-maxage=300, stale-while-revalidate=60` window as
  every other response on those behaviours. The 503 from the outer envelope is
  `no-store`: caching a transient failure for five minutes at the edge turns a
  blip into a five-minute outage for every viewer behind the same cache node
  ([decisions § 969](../architecture/decisions.md)).

## Deploy gate

The `share-entity` Lambda + its CloudFront/OIDC/release wiring and the www
redirect are **landed but deploy-gated** — they need a `terraform apply`
(prod) + a first `web@*` deploy to go live, the same posture the other
share Lambdas shipped under. Until then the SvelteKit dev/build path serves
the routes; prod serves the SPA shell for the new `/share/*` paths.

The `/share/session/*` + `/share/workout/*` behaviours ride that same pending
apply — no new Lambda, no new release step (the existing `share-entity` zip
already carries their dispatcher branches), just two more
`ordered_cache_behavior` blocks on the distribution.

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
  views/RLS, all present on Supabase Free. So the six `/share/*` surfaces
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
3. **Make an outage on it visible.** The lookup must inspect Supabase's
   `error` and log `[share-<x>] upstream_unreachable`, and `<x>` must be
   registered in `share_log_groups` in `infra/modules/web-stack/alarms.tf`.
   Every fallback here is a *handled* response, so the AWS `Errors` metric
   never moves: without both halves a Supabase outage degrades the surface
   silently and pages nobody, which is how `/share/session` and
   `/share/workout` shipped. `share_upstream_alarm_guard.test.ts` derives the
   surface set from the lookups and fails when either half is missing.
4. Add it to `sitemap.xml` via a `sitemap.ts` builder (unless it's a
   people-directory — don't enumerate those).
5. Unit-test the meta builder; e2e the not-found head (deterministic).

**Export a `build<X>ShareCanonical(base, id)` and never spell the path
again.** Every consumer of a share URL passes the base its use needs and
takes the path from that one function: the in-app canonical resolves it
against `PUBLIC_SITE_URL`, a copy-to-clipboard link against
`location.origin` (a preview host has to yield a preview link), the
sitemap `<loc>` against the endpoint's site URL, and the entity's own
JSON-LD `url` against the same. Getting the *origin* right per use was
never the problem; three copy-links and five sitemap rows spelling the
*path* by hand was, and a `<loc>` that disagrees with the page's own
canonical hands the crawler a manifest pointing somewhere else.
`share_url_source_guard.test.ts` registers every place a share path is
assembled with an exact count, so a new hand-spelled one fails. Note the
one path that is not under `/share/`: a recap's public page is
`/recap/share/[id]`, from `buildRecapShareCanonical`.
