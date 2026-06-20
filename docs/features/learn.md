# Learn / guides public content

> **Status:** Shipped web (2026-06-19). Implementation-handoff spec: [learn_pages.md](learn_pages.md). ADR: [decisions.md § 161](../architecture/decisions.md#161-learn-guides-are-repo-committed-markdownmdsvex-prerendered-to-static-html-not-a-db-backed-cms).

A public, no-auth **Learn** surface of evergreen new-runner guides that lives alongside the landing page. Each guide teaches a topic and funnels the reader into the matching in-app feature plus a sign-up CTA. Read-only, anonymous, **statically prerendered** — zero DB, zero runtime cost, served by CloudFront from S3 ([decisions.md § 53](../architecture/decisions.md)).

## Content-source decision

Each guide is a markdown / MDsvex file committed in the repo, loaded by a build-time `import.meta.glob` — **not** a DB-backed CMS. Version-controlled, reviewed in PRs, prerender-perfect, no new attack surface. Trade-off: adding/editing a guide is a code change + deploy, not a web form. See [decisions.md § 161](../architecture/decisions.md#161-learn-guides-are-repo-committed-markdownmdsvex-prerendered-to-static-html-not-a-db-backed-cms).

## Route map

| URL | Route | Prerender |
|---|---|---|
| `/learn` | `routes/learn/+page.{svelte,ts}` — the hub (category sections of guide cards) | `prerender = true` |
| `/learn/<slug>` | `routes/learn/[slug]/+page.{svelte,ts}` — a single article (mdsvex body) | `true` + `entries()` over guide slugs |
| `/learn/category/<id>` | `routes/learn/category/[category]/+page.{svelte,ts}` — guides in one category | `true` + `entries()` over `CATEGORIES` |

`/learn` is **shell-less + anon** in `routes/+layout.svelte` (a marketing surface, never wrapped in the app sidebar — the `path.startsWith('/learn')` prefix in `isShellless`, which `isAnonAllowed` is a superset of).

## Where the code lives

```
apps/web/src/lib/learn/
  guides/*.md          # one .md per guide; filename stem = slug; YAML frontmatter
  guides.ts            # import.meta.glob index + listGuides/getGuide/guidesByCategory + the English-fallback resolver (getGuide / localizedGuideMeta / isEnglishFallback)
  guides/<slug>.<locale>.md  # optional per-locale prose variants (de/fr/es/ja/pt-BR); resolver falls back to English when absent
  guides.test.ts       # frontmatter / slug-uniqueness / category / CTA guard (reads .md off disk; tsx-runnable)
  categories.ts        # CATEGORIES catalogue + CTA_TARGETS map (pure; labelKeys typed MessageKey)
  learn_meta.ts        # pure SEO builders (title / desc / canonical / Article+BreadcrumbList JSON-LD)
  learn_meta.test.ts
apps/web/src/lib/components/
  GuideCard.svelte     # hub/category preview card (.card-elevated)
  LearnCta.svelte      # end-of-article CTA card (feature link + sign-up)
apps/web/static/og-default.png   # 1200x630 branded OG fallback card
```

Sitemap entries (hub 0.8 / category 0.6 / guide 0.7 + frontmatter lastmod) are built by `learnEntries()` in `lib/share/sitemap.ts` and concatenated in `routes/sitemap.xml/+server.ts` from the build-time guide index, so they ship even if the Supabase routes/runs fetch fails.

## How to add a guide

1. Create `apps/web/src/lib/learn/guides/<slug>.md`.
2. Frontmatter: `title`, `description`, `category` (one of `CATEGORIES`), `slug` (= filename stem), `order`, `updated` (ISO date), optional `heroImage`, optional `cta.feature` (one of `CTA_TARGETS`).
3. Write the body in markdown (`##`/`###`, lists, links). The end-of-article CTA is auto-appended from `cta.feature`.
4. New category? Add it to `categories.ts` + its `labelKey` to `en.ts` and all five other locales.
5. `npx tsx --test apps/web/src/lib/learn/guides.test.ts` validates frontmatter / slug / category / CTA (and, for localized files, sibling agreement — see below).
6. `npm run build --workspace=apps/web` then confirm `build/learn/<slug>.html` exists and `build/sitemap.xml` lists it.

No DB migration; no deploy step beyond the normal web build/release.

### How to translate a guide

1. Copy `apps/web/src/lib/learn/guides/<slug>.md` to `apps/web/src/lib/learn/guides/<slug>.<locale>.md` (`<locale>` ∈ `de/fr/es/ja/pt-BR`). The dash-bearing `pt-BR` is fine — the resolver splits on the FIRST dot, so `road-running-101.pt-BR.md` parses to slug `road-running-101`, locale `pt-BR`.
2. Translate the `title`, `description`, and body. Keep `slug`, `category`, `order`, and `cta.feature` **identical to the English source** — `guides.test.ts` fails the build if they drift (the hub card route + section are driven off the English index, so a localized file under a different category/order would mis-file the card).
3. `import.meta.glob` picks the new file up automatically; no registration. `getGuide(slug, locale)` serves it, `localizedGuideMeta(slug, locale)` localizes its hub/category card, and `isEnglishFallback` stops showing the notice for that locale.
4. Re-run the guides test + a dev-mode build (`npx vite build --mode development --workspace=apps/web`) — the localized prose compiles into a client chunk; the English body still prerenders into the static `build/learn/<slug>.html` (canonical), with the localized component lazy-resolved client-side after hydration.

## Cross-linking (CTA targets)

Driven by frontmatter `cta.feature`, mapped to a route + i18n label in `categories.ts`:

| `cta.feature` | Route | Status |
|---|---|---|
| `training-plans` | `/plans/new` | shipped |
| `route-builder` | `/routes/new` | shipped |
| `gear` | `/settings` | shipped (no dedicated `/gear` route) |
| `nutrition` | `/nutrition` | shipped |
| `ai-coach` | `/coach` | shipped |
| `clubs` | `/social?tab=clubs` | shipped |
| `racing` | `/social?tab=clubs` | **interim — race calendar PLANNED** |
| `explore` | `/routes?tab=explore` | shipped |

All targets are auth-gated app routes; an anon reader who clicks is sent through the layout auth guard to `/login?return_to=...`, the intended acquisition funnel. Every guide also shows a "Create a free account" → `/login?signup=1` button.

### Race-calendar dependency

There is no public race-finder feature yet (clubs have events, but no aggregated calendar). The **"your first race"** guide (`your-first-race.md`) links to the closest shipped surface, `/social?tab=clubs`, and flags the dependency in its body. When a race calendar ships, repoint the `racing` entry in `categories.ts` and update this table.

## Localization

Two layers:

1. **Chrome / UI strings** (`learn.*` namespace) — shipped in all six locales (`en, de, fr, es, ja, pt-BR`), enforced by `messages_parity.test.ts`.
2. **Guide prose** — **per-locale lookup with English fallback, shipped** (2026-06-20). `guides.ts` indexes every `<slug>.<locale>.md` variant from the same `import.meta.glob`. The resolution surface:
   - `getGuide(slug, locale)` → the localized article body when a `<slug>.<locale>.md` exists, else the English entry. Drives the article `<GuideBody/>` + H1.
   - `localizedGuideMeta(slug, locale)` → the localized `title` + `description`, **falling back field-by-field** to the English frontmatter. Drives the hub + category cards (`GuideCard.svelte`) AND the article H1, so a non-English visitor reads a consistent localized listing → body and never an English title above a localized body.
   - `isEnglishFallback(slug, locale)` → drives the one-line "this guide is in English" notice, shown only when the active locale has no file for that slug.
   - The English body still **prerenders** into the static `build/learn/<slug>.html` (the canonical, SEO-indexed copy — `<head>` meta is English by design); the localized component is lazy-resolved client-side after `initLocale` swaps the active locale.
   - `guides.test.ts` guards the localized files: the suffix must be a supported non-default locale, an English source must exist to fall back to, `(slug, locale)` is unique, and the localized frontmatter agrees with its English sibling on `slug`/`category`/`order`/`cta.feature` (only `title`/`description` differ).

   **Localized today:** all eight guides — `road-running-101`, `couch-to-5k`, `choosing-running-shoes`, `weekly-running-routine`, `how-to-pace-your-first-race`, `trail-running-basics`, `what-to-eat-before-a-long-run`, `your-first-race` — in all six locales (`en` source + `de/fr/es/ja/pt-BR`). The prose-localization content is **complete** (2026-06-20); the resolver's field-by-field English fallback stays wired for any future guide added before its translations land. See [decisions.md § 179](../architecture/decisions.md).

## Mobile / watch

**Web-only. The twin invariant does not apply** (acquisition/SEO content, like the landing page / `/privacy` / `/compare`). A future single in-app "Learn / Guides" link opening the web hub is a one-link follow-up, not a screen and not a twin obligation.

## Tests

- Unit (`npx tsx --test`): `guides.test.ts`, `learn_meta.test.ts`, `sitemap.test.ts` (extended).
- Playwright (`apps/web/tests-e2e/learn/`): `hub`, `article`, `seo`, `category`, `cta-links-resolve`, `localized-prose` (localized body + H1, English fallback + notice, localized hub-card title).
