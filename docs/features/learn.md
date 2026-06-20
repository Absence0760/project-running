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
  guides.ts            # import.meta.glob index + listGuides/getGuide/guidesByCategory + English-fallback resolver
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
5. `npx tsx --test apps/web/src/lib/learn/guides.test.ts` validates frontmatter / slug / category / CTA.
6. `npm run build --workspace=apps/web` then confirm `build/learn/<slug>.html` exists and `build/sitemap.xml` lists it.

No DB migration; no deploy step beyond the normal web build/release.

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

## Localization (scope still owed)

Two layers:

1. **Chrome / UI strings** (`learn.*` namespace) — shipped in all six locales (`en, de, fr, es, ja, pt-BR`), enforced by `messages_parity.test.ts`.
2. **Guide prose** — **English-only** today. `guides.ts` resolves a `<slug>.<locale>.md` variant and falls back to English when absent; the article page shows a one-line "this guide is in English" notice on fallback. The locale-suffix resolver is wired now; localized prose files are not authored. **Decision owed:** translate the starter set into the five other locales (and on what timeline), or stay English-only.

## Mobile / watch

**Web-only. The twin invariant does not apply** (acquisition/SEO content, like the landing page / `/privacy` / `/compare`). A future single in-app "Learn / Guides" link opening the web hub is a one-link follow-up, not a screen and not a twin obligation.

## Tests

- Unit (`npx tsx --test`): `guides.test.ts`, `learn_meta.test.ts`, `sitemap.test.ts` (extended).
- Playwright (`apps/web/tests-e2e/learn/`): `hub`, `article`, `seo`, `category`, `cta-links-resolve`.
