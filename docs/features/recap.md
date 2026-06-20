# Year-in-running / "Wrapped" recap

> **Status:** Shipped (web canonical + mobile). Annual recap shipped earlier;
> the monthly variant + public share snapshot + parity-pair registration
> landed 2026-06-19 (migration `20270207_001`). See
> [year_in_review.md](year_in_review.md) for the original gap-closer plan and
> [decisions.md § 163](../architecture/decisions.md) for the snapshot rationale.

## What it is

A Spotify-Wrapped-style recap of a runner's year (or month): total
distance / time / vert, run count, longest run, fastest pace, best streak,
top week, unique routes, photo + PR counts, an earned trophy grid, and a
12-month distance bar chart. Free — privacy-gated, not paywalled.

## The engine (TS↔Dart parity pair `recap`)

`apps/web/src/lib/runs/recap.ts` ↔ `apps/mobile_android/lib/recap.dart` (kept
byte-behaviour-identical; registered in the root `CLAUDE.md` parity list,
31 web mirror tests / 30 Dart).

- `buildYearInRunningRecap(runs, year, extras?)` → `YearInRunningRecap`.
  Pass **all** the user's runs (not just the year's) so the streak can extend
  across the year boundary. Totals + most-used-activity are cross-modal
  (cycling included); **longest run + fastest pace are run-family only** (a bike
  ride can't masquerade as the year's longest run). Filters by **local**
  calendar year so a New Year's Eve evening run files correctly.
- `buildMonthInRunningRecap(runs, year, month, extras?)` → the same shape with
  `month` set, projected off one calendar month via the same per-run rules. The
  `monthly` 12-bucket strip is carried through (the month card hides it in the
  UI).
- `computeRecapBadges(...)` → the earned-only trophy grid: one badge per
  category, highest tier reached wins.
- `RecapExtras { photoCount, personalRecordCount }` — the two counts the engine
  can't derive from `Run` rows; the page fetches them (`fetchRecapExtras` in
  `core/data.ts`) and passes them in. Negative inputs clamp to 0.
- `recapHeadline(recap, 'km'|'mi')` — the one-line share-copy summary.
- `recapSnapshotJson(recap)` (Dart only) — serialises the recap into the
  frozen-snapshot field shape the web `YearInRunningRecap` object carries, so a
  mobile-published `public_recaps` row renders identically on the web share
  page.

## Surfaces

- **Web annual:** `/recap/[year]` — hero + stat-card grid + trophy grid +
  monthly bar chart + closing CTA. Body extracted into the shared
  `lib/components/RecapView.svelte` (so year + month don't duplicate markup).
- **Web monthly:** `/recap/[year]/[month]` — same `RecapView`, month engine,
  no 12-month strip.
- **Web in-app share card:** `lib/share/recap_share_image.ts`
  (`buildRecapShareSvg`, 1080² SVG) → rasterised client-side via
  `lib/share/svg_to_png.ts` → OS share sheet / download. Pass a `periodLabel`
  for the monthly kicker.
- **Mobile:** `RecapScreen` (from the dashboard), annual only; the Dart monthly
  builder ships but a monthly mobile screen is a platform-additive follow-up.

## Public share snapshot (the virality piece)

A recap is otherwise personal data with no public URL. The
`public_recaps` table (migration `20270207_001`) is the **opt-in,
fail-closed-private, revocable** public artifact:

- **Schema:** `(id uuid pk, user_id, period_kind 'year'|'month', period_key
  '2026'|'2026-03', snapshot jsonb, created_at)`, unique on
  `(user_id, period_kind, period_key)`. `period_kind` is a narrow union — TS
  `RecapPeriodKind` + the CHECK stay in lockstep
  (`check_constraint_unions.mjs`).
- **RLS:** owner full CRUD; **anyone may SELECT by id** (the uuid is the
  capability token — that's what lets the share page + og:image render for a
  non-owner / anon viewer). Cascade-deletes with the owner. Pinned by
  `apps/backend/supabase/tests/public_recaps_rls_test.sql`.
- **Snapshot contents:** aggregate-only — totals / badges / monthly strip. **No
  GPS, no per-run rows**, mirroring `og_run_image.ts`'s no-polyline discipline.
- **Publish:** `publishRecap(periodKind, periodKey, snapshot)` in `core/data.ts`
  (web) / `ApiClient.publishRecap(...)` (mobile) — owner-scoped upsert, so
  re-publishing a period refreshes the same link. Revoke = delete the row.
- **Read:** `fetchPublicRecap(id)` (web) / `lookupSharedRecap` (SSR + Lambda).

### Web routes + prod Lambda

- `/recap/share/[id]` (`+page.ts` + `+page.svelte`, `prerender = false`) — reads
  the frozen snapshot, renders the read-only `RecapView`, sets per-recap OG +
  Twitter tags pointing at the og:image.
- `/og/recap/[id].png/+server.ts` (`prerender = false`) — request-time PNG via
  `og_recap_png.ts` → `og_recap_image.ts` (`buildRecapOgSvg`, 1200×630, resvg).
  Always 200 with a branded fallback on a missing/revoked recap (an unfurl must
  never break). 5-min cache so a revoke propagates fast.
- `apps/web/lambda/share-recap/` — the prod Function URL handler owning both
  paths at request time (so a recap published after the last web build still
  unfurls). Mirrors `share-run`. Pure helpers: `share_recap_lookup.ts`,
  `share_recap_meta.ts`, `share_recap_spa_shell.ts`, `recap_period_label.ts`.
  **Deploy-time follow-up:** the CloudFront behaviour + GitHub-OIDC role +
  release-web step in `infra/` are not yet wired (mirror the `share-run` /
  `share-route` Lambda wiring) — the SvelteKit dev routes own the path locally
  meanwhile.

## Gating / compliance

Privacy, not paywall. Free feature; the public artifact is fail-closed-private
(published only by an explicit owner action) and revocable. Only aggregate
non-track numbers are exposed, so no CISO/counsel gate is required — but the
publish action carries a clear "this makes a public link" disclosure
(`recap.makePublicExplain`).
