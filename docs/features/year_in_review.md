# Year-in-review / "Wrapped" recap — implementation plan

> **Status:** SHIPPED 2026-06-19 (migration `20270206_001`). This was the
> implementation handoff plan; the gap-closers (public OG-unfurlable share
> snapshot, monthly variant, `recap.ts`↔`recap.dart` parity-pair registration)
> all landed. The live feature reference is now [recap.md](recap.md); this file
> is kept as the design record. One deploy-time follow-up remains: wiring the
> `share-recap` Lambda's CloudFront/OIDC/release steps in `infra/`.

## Goal & user value
Give every runner a first-class, highly shareable annual (and new: monthly)
"Wrapped"-style recap — total distance/vert/time, PRs, longest run, best
streak, top week, favourite routes, consistency — that they *want* to post.
The annual recap already ships end-to-end; this plan **closes the real gaps**:
(1) a public, OG-unfurlable share artifact so a posted recap link renders a
rendered card (today the card is browser-only personal data with no shareable
URL — the single biggest virality miss), (2) a **monthly** recap variant
reusing the same engine, and (3) wiring the existing `recap.ts`↔`recap.dart`
parity pair into the house lockstep registry so it stops drifting.

## What already exists to build on (verified)
**This feature is ~80% shipped already — do NOT rebuild it.** Verified real:

- **Web engine (canonical):** `apps/web/src/lib/runs/recap.ts` (358 lines) —
  `buildYearInRunningRecap(runs, year, extras)` → `YearInRunningRecap`
  (`runCount`, `totalDistanceM/DurationS/ElevationM`, `longestRunM`,
  `fastestPaceSecPerKm`, `bestStreakDays`, `monthly: RecapMonthBucket[12]`,
  `topWeek`, `uniqueRouteCount`, `photoCount`, `personalRecordCount`,
  `badges: RecapBadge[]` via `computeRecapBadges`). Reuses
  `apps/web/src/lib/runs/streaks.ts#computeRunStreaks`. Tested in
  `apps/web/src/lib/runs/recap.test.ts` (332 lines).
- **Web share card:** `apps/web/src/lib/share/recap_share_image.ts` —
  `buildRecapShareSvg(recap, unit)` → 1080×1080 SVG, **client-rendered only**
  (offscreen canvas → PNG, never an og:image; see its own header comment).
  Tested in `recap_share_image.test.ts`.
- **Web page:** `apps/web/src/routes/recap/[year]/+page.svelte` — hero +
  stat-card grid + badge grid + monthly bar chart + closing CTA + `shareRecap()`
  (Web Share API w/ image file → download → text fallback). Fully i18n'd
  (`recap.*` keys). Entry points already wired in
  `apps/web/src/routes/+layout.svelte` + `apps/web/src/routes/dashboard/+page.svelte`.
- **Web data helper:** `fetchRecapExtras(year)` in
  `apps/web/src/lib/core/data.ts:157` (photo + personal-record counts).
- **Web e2e:** `apps/web/tests-e2e/recap/page.spec.ts`.
- **Mobile twin:** `apps/mobile_android/lib/recap.dart` (239 lines) +
  `apps/mobile_android/lib/screens/recap_screen.dart`, test
  `apps/mobile_android/test/recap_test.dart` (344 lines), entry from
  `apps/mobile_android/lib/screens/dashboard_screen.dart`. iOS twin
  byte-identical under `apps/mobile_ios/`.
- **Aggregates available:** `personal_records` table + the
  `gym_exercise_records`-style server roll-up pattern; `mv_weekly_mileage`
  (materialized view, refreshed every 15 min — `20260706_001`,
  revoked from clients in `20260517_001` so it is **server/RPC-only**, not
  client-readable). `run_photos` table. The recap engine derives most of its
  numbers from `Run` rows directly; only photo + PR counts need
  `fetchRecapExtras`.
- **OG/share infra to copy:** `apps/web/src/lib/share/og_run_image.ts`
  (`buildRunOgSvg`), `og_run_png.ts` (`renderRunOgPng` via resvg),
  `share_run_lookup.ts` (`lookupSharedRun`, the shape used by both the SvelteKit
  `+page.ts` and the prod Lambda), the route
  `apps/web/src/routes/og/run/[id].png/+server.ts` (request-time, `prerender =
  false`, 200-on-missing fallback), and the prod Lambda `apps/web/lambda/share-run/`.

**Important divergence to verify first:** `recap.ts` is 358 lines, `recap.dart`
is 239 — confirm whether the Dart twin already mirrors `computeRecapBadges` +
all `YearInRunningRecap` fields before doing anything else. The pair is **NOT**
registered in the parity-pair list in the root `CLAUDE.md` (grep: 0 hits for
`recap`). Treat closing that registration + any drift as step 1.

## Data model / migrations
**No new table required for the core gaps.** The annual recap reads `Run` rows +
`fetchRecapExtras`. Two decisions:

1. **Public share artifact (the virality piece).** A recap is personal data and
   today has no public URL. To make a posted link unfurl, add a **per-user
   opt-in, tokenised public recap** so sharing is explicit and revocable
   (fail-closed: private by default). Recommended durable shape — a new table:

   ```sql
   -- migration: apps/backend/supabase/migrations/<NEXT>_001_public_recap.sql
   -- (placeholder — assign the next free YYYYMMDD_001 sequentially at landing;
   --  do NOT hardcode a number, the migration tree advances daily)
   create table public_recaps (
     id           uuid primary key default gen_random_uuid(),
     user_id      uuid not null references auth.users(id) on delete cascade,
     period_kind  text not null check (period_kind in ('year','month')),
     period_key   text not null,          -- '2026' or '2026-03'
     snapshot     jsonb not null,         -- frozen YearInRunningRecap-shaped payload
     created_at   timestamptz not null default now(),
     unique (user_id, period_kind, period_key)
   );
   alter table public_recaps enable row level security;
   -- owner full CRUD
   create policy public_recaps_owner on public_recaps
     for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
   -- anon/auth read by id (the share link) — token is the uuid id itself
   create policy public_recaps_public_read on public_recaps
     for select using (true);
   create index public_recaps_user_idx on public_recaps (user_id);
   ```

   Rationale for snapshotting into `snapshot jsonb` rather than recomputing on
   read: the share page + og:image must render without the viewer being the
   owner (RLS would hide the owner's private runs), and a recap shouldn't change
   under the reader after it was posted. The owner "publishes" → freezes the
   recap. Only **aggregate, non-track** numbers go in `snapshot` (no GPS, no
   per-run rows) — there is nothing privacy-sensitive in totals/badges, but keep
   `og_run_image.ts`'s no-track discipline.

   `period_kind` is a **narrow union → TS union + CHECK in lockstep** (house
   rule): add `RecapPeriodKind = 'year' | 'month'` to
   `apps/web/src/lib/types.ts` and append the pair to the `PAIRS` array in
   `apps/web/scripts/check_constraint_unions.mjs`.

   Migration number: follow the `YYYYMMDD_NNN` pattern (latest at spec time was
   `20270202_001`, but the tree advances daily — verify the real latest with
   `ls apps/backend/supabase/migrations/ | sort | tail -1` and use the next free
   `YYYYMMDD_001` at landing; do NOT hardcode `20270201_001`, it is already taken
   by `race_director_checkpoints`).

2. **Codegen — the two-regeneration rule (mandatory after the migration):**
   - `cd apps/backend && npm run gen:types` (or `npm run gen:types` from the repo
     root, which delegates to the backend workspace) — writes
     `apps/web/src/lib/database.types.ts`, committed
   - `dart run scripts/gen_dart_models.dart` from the repo root — writes
     `packages/core_models/lib/src/generated/db_rows.dart`, committed
   Both in the same commit as the migration. CI `parity-types` enforces.

**Alternative considered (cheaper, weaker):** skip the table and render the
og:image purely from the URL-encoded recap numbers (no DB). Rejected — an
unauthenticated unfurl bot can't recompute from `Run` rows (RLS), URL-encoding
the whole recap is fragile, and there's no revoke. The table is the durable
answer; flag it as an open question for the user if they want the cheap path.

## Web implementation (canonical)
- **Monthly recap:** generalise the engine, don't fork it. Add
  `buildMonthInRunningRecap(runs, year, month, extras)` to
  `apps/web/src/lib/runs/recap.ts` (reuse `computeRecapBadges` with month-scaled
  tiers, or keep badges year-only — decide in the open questions). Add route
  `apps/web/src/routes/recap/[year]/[month]/+page.svelte` that mirrors the
  annual page (reuse the same card/markup; extract the shared hero+grid into a
  `RecapView.svelte` component under `src/lib/components/` so year + month don't
  duplicate, per the "extract the shared helper" rule).
- **Publish + public share:**
  - `core/data.ts`: `publishRecap(periodKind, periodKey, snapshot)` (upsert into
    `public_recaps`, owner-scoped) + `fetchPublicRecap(id)` (anon-readable).
  - New public page `apps/web/src/routes/recap/share/[id]/+page.svelte` +
    `+page.ts` (`prerender = false`) — reads the frozen `snapshot`, renders the
    same `RecapView`, sets per-recap `<svelte:head>` OG tags pointing at the
    og:image below. Mirror the `share/run/[id]` shape exactly.
  - og:image: new `apps/web/src/lib/share/og_recap_image.ts`
    (`buildRecapOgSvg(snapshot, unit)`, 1200×630 — distinct from the 1080² card,
    matches `og_run_image.ts` dimensions) + `og_recap_png.ts`
    (`renderRecapOgPng` via the same resvg path as `og_run_png.ts`) + route
    `apps/web/src/routes/og/recap/[id].png/+server.ts` (request-time,
    200-on-missing branded fallback, 5-min cache header — copy `og/run` server
    verbatim). Add a `share_recap_lookup.ts` mirroring `share_run_lookup.ts`.
  - Wire the existing `recap/[year]` page's `shareRecap()` to optionally
    "Publish & copy link" (calls `publishRecap`, then shares the
    `/recap/share/[id]` URL) alongside the existing image-file share.
  - Prod Lambda: add a `share-recap/` sibling under `apps/web/lambda/` mirroring
    `share-run/` (SSR + og:image) so a posted link unfurls in production. (Note
    in the plan: the SvelteKit dev routes own the path locally; the Lambda owns
    it in prod, same split as share-run.)
- **types.ts overlays:** `RecapPeriodKind` union; a `PublicRecapRow` overlay if
  the generated row needs the `snapshot` typed as `YearInRunningRecap`.

## Mobile implementation (Android + iOS twin)
- **Parity-pair sync first:** bring `apps/mobile_android/lib/recap.dart` to byte-
  parity in *behaviour* with `recap.ts` (badges + all fields + monthly builder),
  mirror to `apps/mobile_ios/lib/recap.dart` in the **same commit**. Update
  `apps/mobile_android/test/recap_test.dart` (+ iOS twin) so the test count
  matches `recap.test.ts`.
- **Monthly screen:** the existing `recap_screen.dart` takes a year; add a month
  variant (param or a `RecapPeriod` arg) reusing the same widget tree. Mirror to
  iOS twin.
- **Share:** mobile already shares via the OS share sheet (recap_screen). Add a
  "Publish & share link" action that calls a new `api_client` method
  `publishRecap(...)` (route through `packages/api_client`, not raw Supabase)
  and shares the `/recap/share/[id]` web URL via the OS share sheet — the device
  capability (OS share sheet) is the mobile-additive part; the page it links to
  is web-canonical.
- **Nav placement:** no new tab. Recap is reached from Home/dashboard (already
  wired) — keep it there; respect the 5-slot bottom-nav ceiling
  (`home_screen.dart`). Add the monthly entry as a secondary action on the
  existing recap entry, not a nav destination.

## TS↔Dart parity helpers
- **`recap` (web `runs/recap.ts` ↔ mobile `recap.dart`)** — `buildYearInRunningRecap`
  + `buildMonthInRunningRecap` + `computeRecapBadges`. **ADD this pair to the
  parity-pair list in the root `CLAUDE.md`** (it is currently missing) and run
  the `shared-library-syncer` agent after any edit.
- The share-image builders (`recap_share_image.ts`, `og_recap_image.ts`) are
  **web-only** (the mobile share path renders natively / links to the web page) —
  do not create Dart twins for those; note that explicitly.

## Tests (ship in the same commit as each piece)
- **Playwright (web):**
  - extend `apps/web/tests-e2e/recap/page.spec.ts` for the monthly route.
  - new `apps/web/tests-e2e/recap/public-share.spec.ts` — publish → load
    `/recap/share/[id]` anon → asserts OG tags + card render; private-by-default
    (unpublished id 404/fallback).
- **Unit (web, `npx tsx --test`):**
  - extend `recap.test.ts` for `buildMonthInRunningRecap`.
  - extend `recap_share_image.test.ts`; new `og_recap_image.test.ts` (pin the
    SVG wire shape, mirroring `og_run_image.test.ts`).
- **pgtap (backend):** new `apps/backend/supabase/tests/public_recaps_rls_test.sql`
  — owner CRUD, anon read-by-id, non-owner cannot write, cascade on user delete.
- **Flutter (mobile):** extend `apps/mobile_android/test/recap_test.dart`
  (+ iOS twin) for the monthly builder; keep the test count in lockstep with
  `recap.test.ts`.

## i18n keys to add (all six web locales + all mobile ARBs)
Representative new keys (the `recap.*` namespace already exists; add monthly +
publish):
- `recap.monthHeroKicker` ("My March 2026 in running")
- `recap.monthPageTitle`, `recap.publishAndShare`, `recap.publishedLinkCopied`,
  `recap.makePublicExplain` (privacy note on the publish action),
  `recap.viewMonthly`, `recap.recapShareLinkLabel`.
Web: add to `apps/web/src/lib/i18n/locales/{en,de,fr,es,ja,pt-BR}.ts`
(`satisfies Messages` + `messages_parity.test.ts` enforce parity).
Mobile: add camelCase keys (`recapMonthHeroKicker`, …) to all six ARBs
(`app_en.arb` is the template carrying `@key` metadata), run `flutter gen-l10n`,
mirror `lib/l10n/gen/` to the iOS twin. `l10n_parity_test.dart` enforces.

## Docs to update
- `docs/product/roadmap.md` — tick the recap/Wrapped item; note monthly +
  public-share shipped.
- `docs/product/parity.md` — flip the recap row cells (web + android + ios) for
  the monthly + public-share additions.
- `docs/features/` — add or extend the recap feature doc (no dedicated one
  exists today; a short `docs/features/recap.md` is warranted given the new
  public-share surface + the snapshot/RLS contract).
- Root `CLAUDE.md` — **add the `recap` parity pair** to the parity-pair list.
- `apps/web/CLAUDE.md` — note `og_recap_*` + `share-recap` Lambda alongside the
  existing `share-run`/`og/run` entries.
- `docs/architecture/decisions.md` — one entry: "Public recap is an opt-in
  frozen `public_recaps` snapshot, not a live recompute (RLS + immutability +
  revoke)".

## Gating / compliance
- **Privacy, not paywall.** Recap is free. The public-share artifact is
  **fail-closed: private by default**, published only by an explicit owner
  action, revocable (delete the `public_recaps` row). Only aggregate non-track
  numbers are exposed — no GPS, no per-run rows, mirroring `og_run_image.ts`'s
  no-polyline discipline. No CISO/counsel gate required for aggregates, but the
  publish action must carry a clear "this makes a public link" disclosure
  (`recap.makePublicExplain`). No external credential blocks this.

## Commit plan (ordered, path-scoped per-piece)
1. `git commit -- CLAUDE.md apps/web/src/lib/runs/recap.ts apps/web/src/lib/runs/recap.test.ts apps/mobile_android/lib/recap.dart apps/mobile_ios/lib/recap.dart apps/mobile_android/test/recap_test.dart apps/mobile_ios/test/recap_test.dart`
   — register the parity pair + close any year-recap drift (engine only).
2. Monthly engine + route + tests:
   `git commit -- apps/web/src/lib/runs/recap.ts apps/web/src/lib/runs/recap.test.ts apps/web/src/routes/recap/[year]/[month]/ apps/web/src/lib/components/RecapView.svelte apps/web/tests-e2e/recap/page.spec.ts apps/web/src/lib/i18n/locales/*.ts`
3. Migration + codegen + RLS test:
   `git commit -- apps/backend/supabase/migrations/2027MMDD_001_public_recap.sql apps/backend/supabase/tests/public_recaps_rls_test.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart apps/web/src/lib/types.ts apps/web/scripts/check_constraint_unions.mjs`
4. Public-share web (page + og:image + lookup + data helpers + e2e + i18n):
   `git commit -- apps/web/src/routes/recap/share/ apps/web/src/routes/og/recap/ apps/web/src/lib/share/og_recap_image.ts apps/web/src/lib/share/og_recap_image.test.ts apps/web/src/lib/share/og_recap_png.ts apps/web/src/lib/share/share_recap_lookup.ts apps/web/src/lib/core/data.ts apps/web/tests-e2e/recap/public-share.spec.ts apps/web/src/lib/i18n/locales/*.ts`
5. Prod Lambda: `git commit -- apps/web/lambda/share-recap/`
6. Mobile monthly + publish/share (+ iOS twin + ARBs + gen):
   `git commit -- apps/mobile_android/lib/screens/recap_screen.dart apps/mobile_ios/lib/screens/recap_screen.dart packages/api_client/... apps/mobile_android/lib/l10n/ apps/mobile_ios/lib/l10n/ apps/mobile_android/test/recap_test.dart apps/mobile_ios/test/recap_test.dart`
7. Docs sweep:
   `git commit -- docs/product/roadmap.md docs/product/parity.md docs/features/recap.md docs/architecture/decisions.md apps/web/CLAUDE.md`

## Open questions / decisions owed by the user
1. **Public share: frozen-snapshot table (recommended, durable) vs. no-DB
   URL-encoded card (cheap, fragile, no revoke)?** Plan assumes the table.
2. **Badges on monthly recaps** — reuse year tiers (most won't trigger
   monthly) or define month-scaled tiers, or hide badges on monthly?
3. **Favourite routes** — recap exposes `uniqueRouteCount`; do you want a named
   "most-run route" card (needs a route-name join, adds a query)?
4. **Auto-promote in December** — surface a banner/notification nudging users to
   their year recap (drives the viral moment). In scope now or follow-up?

## Sequencing for the implementer
1. Diff `recap.ts` vs `recap.dart`; close any drift; register the `recap`
   parity pair in root `CLAUDE.md` (commit 1).
2. Generalise the engine to monthly (`buildMonthInRunningRecap`) + extract
   `RecapView.svelte`; add the `[year]/[month]` route + tests (commit 2).
3. Write the `public_recaps` migration; apply locally
   (`cd apps/backend && supabase db reset` — the repo's canonical replay-all idiom,
   which also re-runs `seed.sql`); pick a date with no existing migration (the CLI
   parses only the `YYYYMMDD` prefix as the version, so two same-day files collide —
   see apps/backend/CLAUDE.md); run **both** codegen commands;
   add the `RecapPeriodKind` union + CHECK pair to `check_constraint_unions.mjs`;
   write the pgtap RLS test (commit 3).
4. Build the web public-share page + og:image (copy the `share-run`/`og/run`
   files), `publishRecap`/`fetchPublicRecap` in `data.ts`, e2e + i18n (commit 4).
5. Add the `share-recap` prod Lambda (commit 5).
6. Mirror monthly + publish/share to mobile (Android + iOS twin), ARBs +
   gen-l10n, tests (commit 6).
7. Docs sweep (commit 7). Run `/check` before each commit.
