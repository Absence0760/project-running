# Learn / guides public content pages — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

Handoff target: a fresh Claude Code session that has not seen this analysis. Everything below is grounded in the actual repo (paths verified June 2026). Follow it literally; cite the real patterns it points at rather than improvising generic SvelteKit.

## Goal & user value

Give a new or aspiring runner a public, no-auth **Learn** surface — evergreen educational guides ("Road running 101", "Couch to 5K", "Choosing your first running shoes", "What to eat before a long run") — that lives alongside the existing landing page. It is a marketing / SEO / new-user-acquisition surface: each guide teaches a topic and ends by funnelling the reader into the matching in-app feature (training plans, route builder, gear tracking, AI coach, nutrition) and the sign-up CTA. It is **read-only, anonymous, and statically prerendered** — zero DB, zero runtime cost, perfect for SEO and for the S3 + CloudFront hosting model (decisions §53).

## What already exists to build on (verified)

- **Landing page** — `apps/web/src/routes/+page.svelte`. The marketing/home page. It redirects logged-in users to `/dashboard` via an `$effect`, renders the hero only for anon visitors, and is a **shell-less** route (no app sidebar). All copy is i18n'd through `m('landing.*')` (36 keys in `en.ts`). It links sign-up via `href="/login"` (and `/login?signup=1` is used elsewhere as the explicit-signup variant). Footer links to `/privacy`, `/terms`, `/cookie-notice`. This is the styling + structure template for the Learn hub.
- **Public, no-auth, SEO-complete pages** — the share routes:
  - `apps/web/src/routes/share/route/[id]/+page.svelte` — the canonical template for a public page's `<svelte:head>`: `<title>`, `<meta name="description">`, `<link rel="canonical">`, full Open Graph (`og:title/description/type/url/site_name/image` + `og:image:width/height`), Twitter card, and JSON-LD injected via `{@html `<script type="application/ld+json">${jsonLd}</script>`}`. It also shows the **anon sign-up CTA** pattern (`{#if !auth.loggedIn}` → `/login?signup=1`).
  - `apps/web/src/lib/share/share_meta.ts` — pure builders for title / description / canonical / JSON-LD (`buildRouteJsonLd` builds a `WebPage` + `BreadcrumbList`, escaping user content via `escapeJsonLd`). This is the pure-helper + unit-test pattern to mirror for Learn meta.
- **Sitemap** — `apps/web/src/routes/sitemap.xml/+server.ts` (prerendered at build) + pure helpers in `apps/web/src/lib/share/sitemap.ts` (`composeEntries`, `buildSitemap`, `SitemapEntry`). `composeEntries` is where top-level + per-entity URLs are assembled. Learn URLs get added here.
- **Existing public marketing page with a data module** — `apps/web/src/routes/compare/+page.svelte` reads a typed data module `$lib/settings/compare_features.ts` and renders i18n'd copy via `m('compare.*')`. This is the closest existing analog to "structured marketing content rendered from a code module" and the model for how guide *metadata* (titles, descriptions, slugs) is held.
- **Anon-allowed routing** — `apps/web/src/routes/+layout.svelte`. Two lists govern public access:
  - `shellLessExact` (line ~135) — routes rendered with **no app sidebar** (`/`, `/login`, `/onboarding`, …) plus prefix matches (`/share/`, `/live/`, …).
  - `anonExtraExact` (line ~157) = `['/privacy', '/terms', '/cookie-notice', '/compare', '/guided']` — routes reachable without auth where, for a signed-in user, the **app shell still wraps the page**.
  - The auth guard (`$effect` at line ~186) redirects to `/login` for any path not in `isAnonAllowed(...)`. **Learn must be added to the anon set or every anon visitor is bounced to login.**
  - Decision to make (see Mobile / IA below): Learn should be **shell-less + anon** like the landing page — a marketing surface shouldn't be wrapped in the dashboard sidebar even for logged-in visitors. Add a `/learn` prefix to `isShellless` and to `isAnonAllowed`.
- **i18n** — six locales (`en, de, fr, es, ja, pt-BR`) under `apps/web/src/lib/i18n/locales/*.ts`. `en.ts` is the source of truth; every other locale must define exactly the same keys (`satisfies Messages` + `messages_parity.test.ts` enforce parity — adding a key to `en.ts` without adding it to all five others **fails the build/test**). Strings used at call sites via `m('key', params)`. Detection is client-side (the site is statically prerendered — no Accept-Language SSR).
- **Prerendering / static hosting** — `apps/web/svelte.config.js`: `@sveltejs/adapter-static` with `prerender: { default: true }`. Every route prerenders to static HTML at build unless it opts out with `export const prerender = false` (the share pages do, because they're per-id and Lambda-rendered). **Learn pages are finite, evergreen, and known at build time → they prerender to static HTML and ship in `build/`, served by CloudFront from S3 with zero runtime cost.** This is exactly the SEO-optimal shape decisions §53 makes cheap. `mdsvex` is **already wired** in `svelte.config.js` (`extensions: ['.svelte', '.md']`, `mdsvex({ extensions: ['.md'] })`) but currently **unused** — no `.md` content routes exist yet. Learn is the first consumer.
- **In-app features that exist to cross-link to** (verified routes): `/plans` + `/plans/new` (training plans), `/routes/new` (route builder), gear lives under `/settings` integrations / run-gear (no dedicated `/gear` route — link to `/runs` gear or `/settings`; see Cross-linking), `/coach` (AI coach), `/nutrition`, `/social` (clubs/events), `/routes?tab=explore` (route discovery). **Planned, NOT shipped: a race / event calendar** — clubs have events (`/clubs/[slug]/events/*`) but there is no public race-calendar feature. Link to "find a club / event" via `/social?tab=clubs` and note the race-calendar dependency rather than inventing a route.

## Content architecture (source-of-truth decision)

**Recommendation (durable): author each guide as a markdown / MDsvex file committed in the repo, loaded by a build-time `import.meta.glob`. No DB, no CMS.**

Why this is the durable choice, not a shortcut:
- **Version-controlled** — guides live in git, reviewed in PRs, diffable, revertable. A solo dev's "CMS" is the repo.
- **Prerender-perfect** — content is known at build time, so every guide becomes a static HTML file. Best possible SEO (full HTML in the initial response, crawlable without JS) and literally zero runtime/DB cost — it rides the S3 + CloudFront path with no Lambda.
- **No new attack surface** — a DB-backed CMS means new tables, RLS policies, an editor UI, and a runtime read path on a page meant to be public and cacheable. All avoided.
- **mdsvex is already configured** — `svelte.config.js` already preprocesses `.md`. Markdown lets the author write prose with headings/lists/links naturally, and MDsvex allows embedding the occasional Svelte component (e.g. a CTA card) inside an article.

Trade-off (state it honestly): adding/editing a guide requires a code change + deploy, not a web form. For a solo-dev evergreen-content site that is a *feature* (review gate, no drift), not a cost. If the product ever needs non-engineer authors editing live, revisit with a headless CMS feeding the same prerender step — but do **not** build that now (YAGNI; it adds RLS + an editor surface for a hypothetical).

**Where content lives and how it's loaded:**

```
apps/web/src/lib/learn/
  guides/                        # one .md file per guide; filename = slug
    road-running-101.md
    couch-to-5k.md
    choosing-running-shoes.md
    ...
  guides.ts                      # glob-loads + indexes the .md modules; pure-ish (no runes)
  guides.test.ts                 # unit tests: every guide has required frontmatter, slugs unique, category valid
  categories.ts                  # the fixed category catalogue (id + i18n label key + order)
  learn_meta.ts                  # pure SEO builders (title/desc/canonical/JSON-LD Article) — sibling of share_meta.ts
  learn_meta.test.ts
```

Each `.md` file carries **YAML frontmatter** (mdsvex parses it and exposes it as the module's `metadata` export):

```md
---
title: Road running 101
description: The complete beginner's guide to starting road running — gear, pacing, and your first weeks.
category: getting-started
slug: road-running-101            # must equal the filename stem; tested
order: 1                          # sort order within hub/category
updated: 2026-06-15               # ISO date → sitemap <lastmod> + "Last updated" line
heroImage: /learn/road-running-101.png   # optional; OG image fallback to a generic branded card
cta:                              # the contextual in-app CTA (see Cross-linking)
  feature: training-plans
---

Body prose in markdown...
```

`guides.ts` uses `import.meta.glob('./guides/*.md', { eager: true })` to build a typed index of `{ slug, metadata, render }`. `render` is the compiled Svelte component the article page mounts. Keep `guides.ts` free of runes so its pure index logic is `npx tsx --test`-able (the repo's documented constraint: runes can't be unit-tested under raw tsx — see `apps/web/CLAUDE.md` § "Pure logic in `.svelte.ts`"). The glob + `metadata` access is plain TS, so this works.

## Routing & information architecture

Exact routes under `apps/web/src/routes/learn/`:

```
learn/
  +page.svelte            # /learn  — the hub: intro + category sections + guide cards
  +page.ts                # provides the guide index to the hub (prerender = true)
  [slug]/
    +page.svelte          # /learn/<slug>  — a single article (renders the .md component)
    +page.ts              # resolves the guide by slug, exposes metadata + siteUrl; entries() for prerender
  category/
    [category]/
      +page.svelte        # /learn/category/<category> — guides filtered to one category
      +page.ts            # entries() over the category catalogue
```

**Slug scheme:** lowercase kebab-case, stable, human-readable, matches the `.md` filename stem (e.g. `/learn/road-running-101`). No date prefixes, no IDs. Categories use short kebab ids (`getting-started`, `gear`, `training`, `nutrition`, `racing`, `trail`). URLs:
- Hub: `/learn`
- Category: `/learn/category/getting-started`
- Article: `/learn/road-running-101`

**Prerendering:** all three route files set (or inherit) `prerender = true`. For the dynamic segments, supply `entries()` so adapter-static knows every page to bake:
- `learn/[slug]/+page.ts` → `export const entries = () => listGuideSlugs().map((slug) => ({ slug }))`
- `learn/category/[category]/+page.ts` → `entries` over `CATEGORIES`.

This makes every guide a real static HTML file in `build/` (verifiable with `npm run build --workspace=apps/web` then checking `build/learn/`).

## SEO

Mirror the `/share/route/[id]` head exactly, swapping the per-entity builders for Learn ones in `learn_meta.ts`:

- `<title>` — `"<guide title> — Threkir"`; hub gets a dedicated `m('learn.hubPageTitle')`.
- `<meta name="description">` — from frontmatter `description`.
- `<link rel="canonical">` — absolute, built from `PUBLIC_SITE_URL` (default `https://threkir.com`, same fallback as `sitemap.xml` and `share/route/[id]/+page.ts`) + `/learn/<slug>`.
- Open Graph: `og:title`, `og:description`, `og:type` = `article` (article pages) / `website` (hub + category), `og:url` (canonical), `og:site_name` = `Threkir`, `og:image` (frontmatter `heroImage` or a generic `/og-default.png` branded card), `og:image:width/height`.
- Twitter `summary_large_image` card mirroring OG.
- **JSON-LD `Article`** per article via `buildGuideJsonLd` in `learn_meta.ts` — `@type: Article` with `headline`, `description`, `datePublished`/`dateModified` (frontmatter `updated`), `author`/`publisher` (`Organization` "Threkir"), `mainEntityOfPage` (canonical), plus a `BreadcrumbList` (Home → Learn → [category] → article). Inject via `{@html `<script type="application/ld+json">${jsonLd}</script>`}` using the **`escapeJsonLd` escaping pattern from `share_meta.ts`** (guide content is repo-authored, not user input, but keep the escape for consistency + defence-in-depth, and because the article body never goes through `{@html}` raw — mdsvex compiles it to safe Svelte).
- **Sitemap inclusion** — extend `composeEntries` in `apps/web/src/lib/share/sitemap.ts` to push `/learn` (priority ~0.8, changefreq weekly), each `/learn/category/<id>` (priority ~0.6), and each `/learn/<slug>` (priority ~0.7, `<lastmod>` from frontmatter `updated`, changefreq monthly). Pass the guide index into `composeEntries` (or a sibling `learnEntries(base, guides)` it concatenates). The endpoint `sitemap.xml/+server.ts` imports the static guide index from `$lib/learn/guides` directly (no DB call — these are build-time constants), so the Learn entries always ship even if the Supabase fetch for routes/runs fails. Update `sitemap.test.ts` accordingly.

**Prerender confirmation:** because all Learn routes prerender (`prerender = true` + `entries()`), the full per-guide `<head>` is baked into static HTML at build — crawlers see correct title/OG/JSON-LD with no JS execution and no per-request Lambda (unlike `/share/*`, which needs the share-route Lambda *because* its content is per-id and mutable; Learn content is finite and known at build, so plain adapter-static is correct and simpler).

## Cross-linking into the app

Each guide ends with a contextual CTA block: a short "Ready to do this in the app?" card linking to the relevant feature **plus** the sign-up CTA. Drive the CTA from frontmatter `cta.feature`, mapped to a route + i18n'd label in `apps/web/src/lib/learn/categories.ts` (or a small `cta_targets.ts`). Verified target routes:

| Guide topic | `cta.feature` | Target in-app route | Status |
|---|---|---|---|
| Couch to 5K / first plan | `training-plans` | `/plans/new` | shipped |
| Road running 101 / build a route | `route-builder` | `/routes/new` | shipped |
| Choosing running shoes / gear | `gear` | `/settings` (gear/integrations) or `/runs` (run-gear) | shipped (no dedicated `/gear` route — link `/settings`) |
| What to eat before a long run | `nutrition` | `/nutrition` | shipped |
| Train smarter / get coached | `ai-coach` | `/coach` | shipped |
| Find people to run with | `clubs` | `/social?tab=clubs` | shipped |
| Your first race: how to sign up | `racing` | `/social?tab=clubs` (find a club/event) | **race calendar PLANNED, not shipped** — see note |
| Explore routes near you | `explore` | `/routes?tab=explore` | shipped |

- **Sign-up CTA**: every guide also shows a "Create a free account" button → `/login?signup=1` (the explicit-signup variant used by the share pages). Reuse the share-page CTA copy pattern but with Learn-specific i18n keys.
- **Planned-vs-shipped note**: there is **no public race-calendar feature today** (clubs have private/public events, but no aggregated race-finder). The "first race" guide must link to the closest *shipped* surface (find a club / browse events via `/social?tab=clubs`) and the plan flags the race-calendar as a future dependency — do **not** link a route that doesn't exist. When a race calendar ships, point this guide's CTA at it and update the mapping table.
- All CTA targets are auth-gated app routes; an anon reader clicking them hits the layout auth guard → `/login?return_to=...`, which is the desired acquisition funnel (sign in, land on the feature).

## Sample initial guide set (English first, ~8 starter guides)

1. **Road running 101** (`getting-started`) — what road running is, what you need, your first four weeks. CTA → training plans.
2. **Couch to 5K: your first month** (`getting-started`) — the classic walk/run progression, how to follow it in-app. CTA → `/plans/new`.
3. **Choosing your first running shoes** (`gear`) — neutral vs stability, fit, when to replace. CTA → gear tracking.
4. **What to eat before a long run** (`nutrition`) — timing, carbs, hydration, what to avoid. CTA → `/nutrition`.
5. **How to pace your first race** (`racing`) — even splits, going out too fast, course recon. CTA → route builder / coach.
6. **Your first race: how to find and sign up** (`racing`) — finding events, what to expect on race day. CTA → find a club/event (note: race calendar planned).
7. **Trail running basics** (`trail`) — terrain, footing, kit differences, safety. CTA → explore routes.
8. **Building a weekly running routine** (`training`) — frequency, easy/hard balance, recovery, how a plan helps. CTA → training plans / coach.

(Two-three more — "Understanding pace and heart-rate zones", "Avoiding common beginner injuries", "How to track your runs" — are easy follow-ups once the template exists.)

## Web implementation

All under `apps/web/`. Reuse global primitives from `app.css` (`.btn`, `.btn-primary`, `.card-elevated`) — **do not** redeclare them (conventions § Web buttons / cards).

Components / files:
- `src/lib/learn/guides/*.md` — content (frontmatter + prose).
- `src/lib/learn/guides.ts` — `import.meta.glob('./guides/*.md', { eager: true })` → typed `GuideIndexEntry[]` (`{ slug, title, description, category, order, updated, heroImage?, cta?, component }`); exports `listGuides()`, `listGuideSlugs()`, `getGuide(slug)`, `guidesByCategory(cat)`. Pure (no runes) → unit-testable.
- `src/lib/learn/categories.ts` — `CATEGORIES` array (`{ id, labelKey, order }`) + CTA target map. Pure.
- `src/lib/learn/learn_meta.ts` — `buildGuideTitle`, `buildGuideDescription`, `buildLearnCanonical(base, path)`, `buildGuideJsonLd(...)`, `buildLearnBreadcrumbJsonLd(...)`. Pure; mirror `share_meta.ts` shape and reuse its `escapeJsonLd`/`normaliseSiteUrl` idiom (extract a tiny shared helper only if it's a clean lift; otherwise duplicate the 3-line escape — conventions discourage premature abstraction).
- `src/lib/components/LearnCta.svelte` — the end-of-article CTA card (feature link + sign-up button), driven by `cta.feature`. Reusable across all guides.
- `src/lib/components/GuideCard.svelte` — a guide preview card for the hub + category pages (title, description, category pill), styled with `.card-elevated`.
- `src/routes/learn/+page.svelte` + `+page.ts` — hub. Layout modelled on the landing page's section grid: a header (`m('learn.hubTitle')` / `m('learn.hubSub')`), then category sections each listing their `GuideCard`s, then a closing sign-up CTA. Shell-less marketing chrome (own header/footer like the share pages), not the app sidebar.
- `src/routes/learn/[slug]/+page.svelte` + `+page.ts` — article. `+page.ts` resolves the guide by `params.slug` (404 → SvelteKit `error(404)`), returns `{ guide metadata, siteUrl }`, sets `prerender = true` + `entries()`. `+page.svelte` renders the `<svelte:head>` SEO block (mirroring `share/route/[id]`), a breadcrumb (Home → Learn → category → title), the compiled mdsvex `<svelte:component this={guide.component} />` body inside a `.legal-page`-style prose container (reuse the typographic container the `/privacy` page uses, or a new `.learn-article` scoped style), `<LearnCta>`, then the marketing footer.
- `src/routes/learn/category/[category]/+page.svelte` + `+page.ts` — category index; `entries()` over `CATEGORIES`; `error(404)` on unknown category.
- `src/routes/+layout.svelte` — add `/learn` to `isShellless` (prefix match: `path.startsWith('/learn')`) **and** to `isAnonAllowed` (it's a superset, but add the prefix explicitly so the auth-guard `$effect` and the onboarding-gate `$effect` both treat it as public). One-line change in each predicate.
- `src/routes/+page.svelte` (landing) — add a "Learn" link to the landing nav + footer (`href="/learn"`, i18n key `landing.navLearn`), so the marketing surface is discoverable. Optional but recommended for the acquisition funnel.
- `src/routes/sitemap.xml/+server.ts` + `src/lib/share/sitemap.ts` — add Learn entries (see SEO).

prerender: all `learn/*` routes prerender; confirm with a build and inspect `build/learn/`.

## Mobile

**Web-only. The twin invariant does NOT apply.** Justification:
- This is a marketing / SEO / new-user-acquisition surface, exactly like the landing page, `/privacy`, `/terms`, `/compare` — none of which have a mobile twin. Decisions §24 makes web the canonical surface and mobile *additive* for in-hand capabilities; evergreen acquisition content is not an in-app capability.
- SEO is the whole point, and SEO is a web property — there is no App Store SEO benefit to native guide screens.
- Building native Flutter guide screens (×2 byte-identical twins) for static prose would be pure cost with no user value the web pages don't already deliver, and would create a content-duplication maintenance burden across three surfaces.

What mobile *may* add later (not in this plan, note as a follow-up): a single in-app entry point — e.g. a "Learn / Guides" link in Settings or the Home empty-state that opens the web `/learn` hub in an in-app browser / external tab. That is one link, not a screen, and not a twin obligation. If/when added it follows the existing "open web URL" idiom; flag it in `followups.md`, don't build it here.

Because there is no Dart code in this feature, the `mobile-twin-mirror` and `shared-library-syncer` agents do not apply.

## i18n approach (phased — and the decision the user owes)

Two distinct i18n layers:

1. **Chrome / UI strings** (hub title, category labels, CTA button text, "Last updated", breadcrumb labels, nav/footer "Learn" link) — these **must** go through the i18n system from day one. Add keys under a `learn.*` namespace to `en.ts` **and all five other locales** (`de, fr, es, ja, pt-BR`), or `messages_parity.test.ts` + `satisfies Messages` fail the build. There are only ~15-20 such keys; translate or stub them in all six locales in the same commit as the UI. (Stub = a real translation; do not leave English in non-English catalogues — the parity test checks non-empty + placeholder parity, and English-in-`de.ts` is exactly the i18n drift the project guards against. For the initial ship, machine-translate the short chrome strings and mark them for review, OR — if the user prefers — ship the chrome English-only by keeping the `learn.*` values identical across locales, which passes the parity test but is honest English-everywhere; flag this as the decision owed.)

2. **Guide prose** (the article bodies) — six-locale long-form translation is a real, ongoing cost. **Recommended phased approach: ship English prose first, structured so translation is a drop-in later.** Concretely:
   - Filename convention reserves a locale suffix: `road-running-101.md` (English) with future `road-running-101.de.md` etc.; `guides.ts` resolves the active locale's file and **falls back to English** when a localized file is absent. Build this fallback into `guides.ts` now (cheap) but author only English `.md` files in this phase.
   - The article page shows a small "This guide is in English" notice when serving the fallback to a non-English locale (one i18n'd chrome string).

**Decision owed by the user (flag explicitly):** (a) for the *chrome* strings, machine-translate into all six locales now, or ship English-in-all-six and translate later? (b) for the *prose*, English-only indefinitely, or commit to translating the starter set into the five other locales (and on what timeline)? Long-form prose translation is the durable-but-expensive option; English-first with the locale-suffix fallback wired is the recommended pragmatic path. Note in the end-of-turn summary that this localization scope is unresolved.

## Tests

Per conventions § Test hygiene (review → unit → e2e; tests ship in the **same commit** as the piece).

**Unit tests** (`npx tsx --test`, pure modules only):
- `src/lib/learn/guides.test.ts` — glob index loads; every guide has required frontmatter (title, description, category, slug); `slug === filename stem`; slugs unique; every `category` is in `CATEGORIES`; every `cta.feature` (when present) maps to a known CTA target. This is the guard that a malformed new guide fails CI rather than shipping broken.
- `src/lib/learn/learn_meta.test.ts` — title/description/canonical/JSON-LD builders produce the expected wire shape (mirror `share_meta` tests); JSON-LD is valid JSON and escapes `<`/`>`/`&`; canonical respects `PUBLIC_SITE_URL` + trailing-slash normalisation.
- `src/lib/share/sitemap.test.ts` — extend: assert `/learn`, a sample `/learn/category/<id>`, and a sample `/learn/<slug>` appear with the right priority/lastmod.

**Playwright e2e** under `apps/web/tests-e2e/learn/` (new dir; model on `tests-e2e/landing/page.spec.ts`, anon `storageState: { cookies: [], origins: [] }`):
- `hub.spec.ts` — anon visitor loads `/learn`, sees the hub heading + at least one guide card; a guide-card link resolves to `/learn/<slug>` (no 404).
- `article.spec.ts` — `/learn/road-running-101` renders the article body (an `h1`/known prose marker), the breadcrumb, and the CTA block; the in-app CTA link has the expected `href` (e.g. `/plans/new`) and the sign-up link points at `/login?signup=1`.
- `seo.spec.ts` — on an article page, assert `<title>` contains the guide title + "Threkir", `<link rel="canonical">` is present and absolute, `og:title`/`og:description`/`og:type=article`/`og:image` meta exist, and a `<script type="application/ld+json">` with `"@type":"Article"` is in the DOM. (Read meta via `page.locator('meta[property="og:title"]').getAttribute('content')`.)
- `cta-links-resolve.spec.ts` — click-through pin: the article's feature CTA navigates to its app route (anon → redirected to `/login?return_to=...`, which is the expected funnel); assert the redirect lands on `/login` rather than a hard 404.
- `category.spec.ts` — `/learn/category/getting-started` lists only that category's guides; unknown category → 404.

(No mobile / watch e2e — none exists by design; web-only feature.)

## Docs to update (same turn as the code, per Docs hygiene rule)

- `docs/product/roadmap.md` — add a "Learn / guides public content" entry under the relevant marketing/SEO area; tick it when merged.
- `docs/features/` — add a short `learn.md` (or fold into an existing marketing/SEO doc if one exists) describing the surface: content-source decision, route map, how to add a guide, the localization decision still owed, and the race-calendar dependency for the "first race" guide. Add the CLAUDE.md index-table row pointing at it.
- `docs/architecture/decisions.md` — append one ADR paragraph: "Learn guides are repo-committed markdown/MDsvex prerendered to static HTML — not a DB-backed CMS — for version control, SEO, and zero runtime cost on S3+CloudFront (§53)." One paragraph, new number, don't rewrite history.
- `apps/web/CLAUDE.md` — add the `learn/` route + `lib/learn/` folder to the structure notes, and note `/learn` is shell-less + anon in the layout.
- `docs/product/parity.md` — add a row only if the matrix tracks marketing surfaces; otherwise note explicitly that Learn is web-only (no twin), like the landing page, so a future session doesn't flag it as drift.
- `docs/testing/testing.md` / `test_inventory.md` — note the new `tests-e2e/learn/` suite + the `lib/learn` unit tests.

## Authoring workflow (how to add a new guide in N steps)

1. Create `apps/web/src/lib/learn/guides/<slug>.md`.
2. Fill the YAML frontmatter: `title`, `description`, `category` (must be one of `CATEGORIES`), `slug` (= filename stem), `order`, `updated` (ISO date), optional `heroImage`, optional `cta.feature` (must map to a known CTA target).
3. Write the body in markdown (headings, lists, links). To embed the CTA card mid-article, import/use `LearnCta` (otherwise it's auto-appended by the article template).
4. If introducing a new category, add it to `apps/web/src/lib/learn/categories.ts` and add its `labelKey` to `en.ts` + all five other locale files.
5. Run `npx tsx --test src/lib/learn/guides.test.ts` — the guard validates frontmatter, slug uniqueness, category + CTA validity.
6. Run `npm run build --workspace=apps/web` and confirm `build/learn/<slug>/index.html` exists (prerendered) and `build/sitemap.xml` lists it.
7. Commit path-scoped (the `.md` + any new category/i18n keys, plus a guide-index test update if the guide is asserted by name).

No DB migration, no deploy step beyond the normal web build/release.

## Commit plan (ordered, path-scoped, one piece per commit)

Each commit includes its tests (conventions § Commit cadence). Commit with explicit paths (`git commit -m "…" -- <paths>`), never `git add -A`.

1. **Scaffold + hub + routing wiring** — `lib/learn/{guides.ts,categories.ts}` + `guides.test.ts`, `routes/learn/+page.{svelte,ts}`, `GuideCard.svelte`, the `+layout.svelte` anon/shell-less prefix additions, the `learn.*` i18n keys (hub/category/nav) across all six locales, `tests-e2e/learn/hub.spec.ts`. (Add one or two placeholder `.md` guides so the hub isn't empty and the test has data.)
2. **Article template + SEO** — `routes/learn/[slug]/+page.{svelte,ts}`, `routes/learn/category/[category]/+page.{svelte,ts}`, `lib/learn/learn_meta.ts` + `learn_meta.test.ts`, `LearnCta.svelte` + CTA target map, the article/category i18n keys (all six locales), `tests-e2e/learn/{article,seo,category,cta-links-resolve}.spec.ts`.
3. **Sitemap inclusion** — `lib/share/sitemap.ts` (Learn entries) + `sitemap.test.ts` update + `routes/sitemap.xml/+server.ts` wiring.
4. **Starter content** — the ~8 English `.md` guides (replace placeholders), any `heroImage` assets under `static/learn/`, plus the landing-page "Learn" nav/footer link + its i18n keys. (Content + the one landing-link change; the guide-index test already guards them.)
5. **Docs sweep** — roadmap tick, `docs/features/learn.md`, decisions ADR, `apps/web/CLAUDE.md`, parity note, testing inventory. (After the code commits it documents.)

## Open questions / decisions owed by the user

1. **Localization scope** (the big one): (a) chrome strings — machine-translate into all six locales now, or ship English-in-all-six (parity-passing) and translate later? (b) guide prose — English-only with the locale-suffix fallback wired (recommended), or commit to translating the starter set into the five other locales, and on what timeline?
2. **Race-calendar dependency**: the "Your first race" guide currently has no shipped race-finder to point at (only `/social?tab=clubs`). Confirm that's the right interim CTA, and whether a public race-calendar feature is on the roadmap (which would change this guide's CTA later).
3. **Shell-less vs app-shell for logged-in visitors**: recommendation is shell-less (marketing chrome like the landing page) for everyone. Confirm — the alternative is wrapping `/learn` in the app sidebar for signed-in users (like `/privacy` does via `anonExtraExact`). Shell-less is recommended because Learn is an acquisition surface, not an in-app destination.
4. **Gear CTA target**: there's no dedicated `/gear` route; the "choosing shoes" guide CTA points at `/settings` (gear/integrations) or `/runs` (run-gear). Confirm which is the better funnel destination.
5. **OG images**: ship a single generic branded `/og-default.png` for all guides initially, or author a per-guide hero/OG image? (Generic is the cheap, durable start; per-guide images are a later polish.)
6. **Discoverability from inside the app**: should a "Learn / Guides" link appear anywhere in the signed-in app (Settings, Home empty-state), or stay purely a logged-out marketing surface? (Recommendation: logged-out only for now; a single Settings link is a trivial follow-up if wanted.)
