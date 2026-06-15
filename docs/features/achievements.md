# Achievements / badges — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value

A badge system that recognises milestones the app already tracks — **PRs** (`personal_records`),
**segment efforts**, **run streaks**, **distance milestones** (first 5K, 100 km lifetime, etc.), and
**challenge/plan completion** — and surfaces them on the **profile**, in the **feed**, and on a
public **share page**. It turns latent achievements (the data exists, but the user never gets a
"you did it" moment) into shareable, motivating recognition. The badge **catalogue is defined as
code** (the guided-runs cue-library pattern), award derivation is deterministic and replayable, and
the surfaces mirror web → mobile twin.

## What already exists to build on (verified)

- **Catalogue-as-code precedent**: `apps/web/src/lib/training/guided_runs.ts` ↔
  `apps/mobile_android/lib/guided_runs.dart` — a pure module exporting an ordered, i18n-aware library
  of typed entries + a pure dispatcher (`cuesDue`). The badge catalogue copies this shape exactly
  (typed entries + a pure `evaluate` dispatcher; titles/descriptions via the i18n `m(key)` /
  `AppLocalizations` lookup so the catalogue re-renders on locale switch).
- **Trophy precedent**: `apps/web/src/lib/runs/recap.ts` already defines a `RecapTrophy` concept
  (`earnedTrophies` at ~line 93, tiers high→low, `icon`/`label`/`detail`) for the year-in-running
  recap. This is the *display* shape to model the badge tile on, but recap trophies are recomputed
  per-recap and not persisted — badges ARE persisted (an award is a durable event).
- **Data sources, all present**:
  - PRs: `personal_records` table (`apps/backend/supabase/migrations/20260508_001_personal_records_cache.sql`) —
    one row per `(user_id, distance ∈ 5k|10k|half_marathon|marathon|mile)`, trigger-maintained, in `TABLES`.
  - Streaks: `apps/web/src/lib/runs/streaks.ts` (`computeRunStreaks` → `{current, best}`) ↔ `streaks.dart`.
  - Segments: `segments` / `segment_efforts` (`20260526_001_segments.sql`, `20260829_001` tiered leaderboards).
  - Distance milestones: derivable from `runs` (lifetime sum, single-run max) — `runs` in `TABLES`.
  - Challenge/plan completion: `training_plans` (`status`, completion via `plan_workouts.manually_completed` /
    `completed_run_id`, the exact logic in `fetchActivePlanOverview` / `fetchAthletePlanOverview` in `data.ts`).
- **Notifications spine** for the "you earned a badge" alert: `notifications` table
  (`apps/backend/supabase/migrations/20260528000001_notifications.sql`) — `kind` CHECK currently
  `('kudos','comment','comment_reply','follow')`, extended polymorphically in `20261212_001`. Adding an
  `'achievement'` kind is the natural alert path. SECURITY DEFINER triggers are the only writers.
- **Feed**: `apps/web/src/routes/feed/` → `/social?tab=feed` (`SocialFeed.svelte`), `fetchFollowingFeed` cursor
  shape in `data.ts`. Mobile `feed_screen.dart`.
- **Profile**: `apps/web/src/routes/u/[id]/+page.svelte` (tabs runs/followers/following/notifications) ↔
  `apps/mobile_android/lib/screens/profile_screen.dart`.
- **Share page precedent**: `apps/web/src/routes/share/run/[id]/` + the `lambda/share-run/` SSR/OG path — the exact
  pattern a public `share/badge/[id]` page + OG image follows.
- **Schema registry**: add `achievements` (and any award table) to `TABLES` in `apps/web/src/lib/core/schema.ts`,
  `metadata_keys.dart`, and the Go `schema.go` if the worker ever writes it (it won't in V1).
- **Latest migration**: `20270202_001` — next free date is `20270203_001` (one per day).

## Data model / migrations

The catalogue (the *definition* of each badge) lives in **code**, not the DB. The DB stores only
**awards** (which user earned which badge, when, off which source row) — this keeps the catalogue
versionable/testable and avoids a DB round-trip to know what badges exist.

- **Migration** `apps/backend/supabase/migrations/20270203_001_achievements.sql`:
  ```sql
  create table achievements (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid references auth.users(id) on delete cascade not null,
    badge_key   text not null,              -- matches a catalogue entry id, e.g. 'distance_100k'
    tier        text not null default 'bronze'
                  check (tier in ('bronze','silver','gold','platinum')),
    source_kind text not null
                  check (source_kind in ('pr','segment','streak','distance','plan')),
    source_id   uuid,                       -- the run/segment_effort/plan row that triggered it (nullable for aggregates like lifetime distance)
    value_num   double precision,           -- the numeric that earned it (e.g. 100000 metres, 30 streak days) — display + dedupe
    earned_at   timestamptz not null default now(),
    is_public   boolean not null default true,
    constraint achievements_user_badge_uk unique (user_id, badge_key, tier)
  );
  create index achievements_user_earned on achievements (user_id, earned_at desc);
  alter table achievements enable row level security;
  ```
  - **RLS**: `achievements_self_select` (`user_id = auth.uid()`) + a public-read path so the share page + a follower's
    feed/profile can read **public** badges of others:
    `create policy achievements_public_select on achievements for select using (is_public = true);`
    (mirror the `is_public`-gated read pattern used elsewhere). **Owner-only UPDATE** for the `is_public` toggle.
    **No client INSERT/DELETE** — awards are written only by the SECURITY DEFINER award function below (mirrors
    `personal_records`: "writes come only from the trigger").
  - `grant select, insert, update, delete on achievements to postgres;` (the definer-owner grant pattern from
    `coach_athletes`).
- **`tier`** is a narrow string domain → **CHECK + TS union in lockstep**. Add `AchievementTier` and
  `AchievementSourceKind` unions to `apps/web/src/lib/types.ts` and append BOTH pairs to the `PAIRS` array in
  `apps/web/scripts/check_constraint_unions.mjs` (the `parity-types` guard). Dart treats them as raw `String`.
- **Award function (SECURITY DEFINER)**: `award_achievements_for_user(p_user uuid)` — recomputes the user's full
  earned set from `personal_records` + `runs` aggregates + `segment_efforts` + plan completion, and `insert ... on
  conflict (user_id, badge_key, tier) do nothing` for any newly-earned badge, returning the rows newly inserted.
  Mirror the `personal_records` "full rebuild is simpler to reason about" approach — each user owns at most hundreds
  of source rows, so a full re-derive is flat-cost and idempotent. A `do nothing` conflict makes re-runs safe.
  - **Award trigger**: AFTER INSERT/UPDATE/DELETE on `runs` (and `personal_records`, and `segment_efforts`) calling
    `award_achievements_for_user(NEW.user_id)`. To avoid recursive/duplicate-notification storms, the function returns
    only *newly* inserted rows; an AFTER INSERT trigger on `achievements` then writes the `notifications` row
    (`kind='achievement'`) for each new award (and, optionally, a feed-visible marker — see Feed below).
  - **Notification kind**: extend the `notifications` kind CHECK to include `'achievement'` in the same migration
    (re-emit the full latest CHECK body — `grep` the latest `notifications` kind constraint first;
    `20261212_001_notifications_polymorphic_activity_ref.sql` is the latest to touch it — and add `achievement_id uuid
    references achievements(id) on delete cascade` if the polymorphic ref column doesn't already cover it).
- **Two codegen commands** after the migration (mandatory): `cd apps/backend && npm run gen:types`, then
  `cd ../.. && dart run scripts/gen_dart_models.dart`. Add `achievements` to the `_tables` allowlist in
  `scripts/gen_dart_models.dart` so `AchievementRow` is generated.
- **pgtap** at `apps/backend/supabase/tests/achievements_test.sql` (see Tests).

## Web implementation (canonical)

- **Catalogue (parity helper, pure)**: `apps/web/src/lib/social/badges.ts` — exports `BADGE_CATALOGUE`
  (ordered, typed `Badge` entries: `id`, `sourceKind`, ordered `tiers` with a `threshold` + `icon` + i18n
  `labelKey`/`descKey`), and a pure `evaluateBadges(input): EarnedBadge[]` that takes primitives
  (PRs, lifetime/max distance, best streak, segment-effort counts, completed-plan count) and returns the earned set
  with tier. This is the single source of truth the SQL award function's thresholds must match — keep the **threshold
  constants in the helper** and have the migration's award function use the same numeric literals (documented as the
  contract; the pgtap pins them so drift fails CI). The display layer reads labels via `m(labelKey)`.
- **Component**: `apps/web/src/lib/components/BadgeGrid.svelte` — renders earned badges as a tier-coloured tile grid
  (model the tile on `recap.ts`'s trophy tiles + Material Symbols icons via the `material-symbols` ligature class).
  A `BadgeTile` shows icon + label + earned-date + tier ring.
- **Profile surface**: mount `BadgeGrid` on `apps/web/src/routes/u/[id]/+page.svelte` — a new "Achievements" section
  (or tab) showing the profile owner's **public** badges (own profile shows all incl. private + an is_public toggle per
  badge). `fetchUserBadges(userId)` in `data.ts`.
- **Feed surface**: when a badge is newly earned, surface it in the following-feed. Simplest durable approach: a
  feed item type rendered by `SocialFeed.svelte` sourced from public `achievements` rows of followed users
  (`fetchFollowingBadgeAwards` cursor-paged like `fetchFollowingFeed`). Render a compact "X earned the Y badge" card
  with the tile. Reuse the existing feed pagination contract (page 20, cursor over `earned_at,id`).
- **Share page**: `apps/web/src/routes/share/badge/[id]/+page.svelte` (public, no auth, `prerender=false`) +
  `apps/web/src/routes/og/badge/[id].png/+server.ts` for the OG card — mirror `share/run/[id]` + `lambda/share-run/`
  exactly (per-request SSR shell + rendered OG image; generic branded card at 200 for private/missing ids). Add the
  matching `lambda/share-badge/` handler following `lambda/share-run/`'s `build.mjs` + resvg pattern.
- **data.ts helpers**: `fetchUserBadges(userId)`, `fetchMyBadges()`, `setBadgeVisibility(id, isPublic)`,
  `fetchBadgeForShare(id)` (public read), `fetchFollowingBadgeAwards(cursor?)`. All in a new
  `// --- Achievements/badges ---` section.
- **types.ts**: add `AchievementTier` + `AchievementSourceKind` unions and an `Achievement` overlay over the generated
  `AchievementRow` if any field needs narrowing (the two CHECK columns).

## Mobile implementation (Android + iOS twin)

Build after web ships + review (decisions §24). Byte-identical iOS twin in the same commit.

- **Catalogue parity twin**: `apps/mobile_android/lib/badges.dart` — exact mirror of `badges.ts`
  (`BADGE_CATALOGUE` + `evaluateBadges`), i18n via `AppLocalizations`. Add to the parity-pair list.
- **api_client**: `fetchUserBadges` / `fetchMyBadges` / `setBadgeVisibility` methods returning an `Achievement`
  model (hand-written in `core_models` since it overlays the generated `AchievementRow` with the narrow unions / a
  resolved catalogue entry).
- **Widget**: `apps/mobile_android/lib/widgets/badge_grid.dart` (mirror `BadgeGrid.svelte`) — a tier-coloured tile grid.
- **Profile**: add the Achievements section to `apps/mobile_android/lib/screens/profile_screen.dart`.
- **Feed**: render the badge-award card in `apps/mobile_android/lib/screens/feed_screen.dart` (mirror the web feed card).
- **Notifications**: the existing notifications inbox + bell already render the `notifications` table; add an icon/label
  branch for `kind='achievement'` in `notification_bell` / `NotificationsList` mirror (web first).
- **Nav placement**: none added (badges live inside Profile + Feed + Notifications — all existing surfaces). 5/6-tab
  ceiling untouched. Share uses the OS share sheet (`Share.share` of the `/share/badge/[id]` URL).

## TS↔Dart parity helpers

- **`badges` (web `apps/web/src/lib/social/badges.ts` ↔ mobile `apps/mobile_android/lib/badges.dart`)**:
  `BADGE_CATALOGUE` + `evaluateBadges(input) → EarnedBadge[]` + the tier-threshold constants. The catalogue ids,
  thresholds, tiers, and dispatcher output must be identical on both platforms (and consistent with the SQL award
  function's thresholds). **Matching test counts** — `badges.test.ts` and `badges_test.dart` with the same number of
  cases (target ~15 each: each source kind's tier boundaries, the "no badges" empty case, the "already at gold doesn't
  re-award bronze" tiering case). Register the pair in `docs/architecture/conventions.md` + the
  `shared-library-syncer` agent table.

## Tests

- **Backend (pgtap)** — `apps/backend/supabase/tests/achievements_test.sql`:
  - Insert runs / a `personal_records` row / a completed plan for user U; call `award_achievements_for_user(U)`;
    assert the expected `achievements` rows exist with correct `badge_key`/`tier`/`value_num`.
  - Idempotency: call twice → no duplicate rows (the unique constraint + `on conflict do nothing`).
  - RLS: U reads own badges (incl. private); another user reads only U's `is_public=true` badges; anon reads only
    public; no client INSERT/DELETE succeeds (42501); only owner can flip `is_public`.
  - Notification: a new award writes a `notifications` row with `kind='achievement'` for the owner.
  - Use the double-quoted `set local "request.jwt.claims"` idiom; hex-only synthetic UUIDs; every `runs` insert carries
    `metadata.activity_type`.
- **Web (unit)** — `apps/web/src/lib/social/badges.test.ts` (~15 cases; pins thresholds + tiering + empty).
- **Web (Playwright)** — `apps/web/tests-e2e/social/badges.spec.ts`: seed an earned badge (extend `seed.sql` so the
  seed user has at least one public badge), assert it renders on `/u/[id]` Achievements, the share page
  `/share/badge/[id]` loads publicly, and a cross-user case shows only public badges.
- **Mobile (Flutter)** — `apps/mobile_android/test/badges_test.dart` (~15, mirrors web) + a widget test for
  `BadgeGrid` and the profile section. Mirror to iOS twin.
- **CHECK↔union guard**: the two new pairs in `check_constraint_unions.mjs` are exercised by the existing
  `parity-types` job.

## i18n keys to add (all six web locales + ARBs)

Web dotted / mobile ARB camelCase. Representative subset (one `label` + `desc` per badge family, plus chrome):

- `badges.section.title` → "Achievements"
- `badges.empty` → "No badges yet — keep running."
- `badges.earnedOn` → "Earned {date}"
- `badges.makePublic` / `badges.makePrivate`
- `badges.share` → "Share badge"
- `badges.feedEarned` → "{name} earned the {badge} badge"
- `badges.notif` → "You earned a new badge: {badge}"
- Per badge family (each with `.label` + `.desc`): `badges.distance5k`, `badges.distance100k`,
  `badges.distanceMarathon`, `badges.streak7`, `badges.streak30`, `badges.streak100`, `badges.pr5k`, `badges.prAll`,
  `badges.segmentKing`, `badges.planFinisher` … (every catalogue entry gets a key pair in all six locales — real
  translations, `test/l10n_parity_test.dart` + `messages_parity.test.ts` enforce parity).

Run `flutter gen-l10n` after ARB edits; mirror `lib/l10n/gen/` to the iOS twin.

## Docs to update

- `docs/product/roadmap.md` — add/tick "Achievements / badges".
- `docs/product/parity.md` — new "Achievements / badges" row; Web `✓`, Android/iOS `✓` after the mobile commit,
  watches `—`.
- `docs/features/` — new `achievements.md` deep dive: the catalogue-as-code contract, the award-derivation function,
  the threshold-in-helper-and-SQL lockstep contract, the three surfaces + share page, the `is_public` privacy default.
- `docs/backend/api_database.md` — `achievements` table + RLS + the `award_achievements_for_user` function +
  the `notifications` `'achievement'` kind.
- `docs/architecture/conventions.md` — add `badges` to the TS↔Dart parity-pair list + the shared-library-syncer table.
- `docs/architecture/decisions.md` — ADR: "badge catalogue defined in code (guided-runs pattern), awards persisted in
  `achievements`, derivation a SECURITY DEFINER full-rebuild trigger mirroring `personal_records`; thresholds live in
  the shared `badges` helper and are duplicated into the SQL award function with the pgtap pinning the contract;
  badges default public but per-badge `is_public` toggle is owner-only."
- `docs/architecture/schema_codegen.md` — note the two new CHECK↔union pairs (already covered generically).

## Gating / compliance

- **Privacy default**: badges default `is_public = true` (they are achievements, meant to be shared) but the owner can
  flip any badge private; non-owner reads are gated to `is_public = true` by RLS (fail-closed — no public policy means
  no leak). The share page + feed read only public rows.
- **No paywall** — achievements are a free engagement feature (no `ProGate`). If a future decision paywalls a premium
  badge tier, gate that tier's *award* behind a default-off flag; not in scope.
- **No PII beyond what's already public** — a badge exposes a numeric milestone + a date, not a track. The share/OG
  card must not embed any private location/track data (it's a badge, not a run). No CISO sign-off gate required; the ADR
  is the review artifact.
- **No backwards-compat concern** — pre-launch; the award function back-fills every user's earned badges on first
  trigger fire (or a one-shot `award_achievements_for_user` over all users in the migration's tail, gated to keep the
  reset fast).

## Commit plan (ordered, path-scoped)

1. `feat(web): badge catalogue + evaluateBadges helper` — `apps/web/src/lib/social/badges.ts` + `badges.test.ts`.
2. `feat(backend): achievements table + award trigger + notification kind` — migration `20270203_001_achievements.sql`
   + regenerated `database.types.ts` + `db_rows.dart` (after adding `achievements` to `_tables`) + the two
   `check_constraint_unions.mjs` pairs + `achievements_test.sql` + `seed.sql` badge fixture.
3. `feat(web): badges on profile + share page + feed` — `BadgeGrid.svelte`, `u/[id]/+page.svelte`,
   `share/badge/[id]/+page.svelte`, `og/badge/[id].png/+server.ts`, `lambda/share-badge/`, data.ts helpers, types.ts
   unions, i18n in all six locales, `apps/web/tests-e2e/social/badges.spec.ts`.
4. `feat(mobile): badge catalogue twin + grid + profile/feed surfaces` — `badges.dart` + `badges_test.dart`,
   `badge_grid.dart`, profile/feed/notification branches, api_client + core_models model, ARBs + gen-l10n.
   **Mirror every `lib/`+`test/` path to `apps/mobile_ios` in the same commit.**
5. `docs: document achievements/badges system` — features/achievements.md, roadmap, parity, api_database,
   conventions, decisions.

## Open questions / decisions owed by the user

1. **Badge catalogue scope for V1**: which families ship first? Proposed: distance milestones (first 5K → lifetime
   100k/marathon-single-run), streaks (7/30/100 days), PRs (first PR / all-4-distances), plan finisher. Segment
   "course record / top-10" is appealing but its tiered-leaderboard rank is more volatile — confirm whether segment
   badges are in V1 or deferred.
2. **Tier thresholds**: confirm the numeric thresholds (e.g. lifetime distance bronze/silver/gold/platinum at
   100/500/1000/5000 km). These become a lockstep contract (helper + SQL).
3. **Threshold duplication helper↔SQL**: the plan duplicates thresholds in the `badges` helper AND the SQL award
   function (with pgtap pinning the contract) rather than reading the catalogue from JS in SQL. Confirm this trade-off
   (the alternative — a single SQL-side definition — loses the testable pure-helper). Recommended: duplicate + pin.
4. **Feed visibility**: should a newly-earned badge always appear in followers' feeds, or only when the user opts to
   share it? Proposed: auto-appear for public badges (with the per-badge private toggle as the opt-out). Confirm.
5. **Back-fill on migration**: run `award_achievements_for_user` over all existing users in the migration tail
   (pre-launch, so the set is tiny), or lazily on first trigger? Proposed: back-fill in the migration tail.

## Sequencing for the implementer

1. Write the `badges.ts` catalogue + `evaluateBadges` + tests; lock the thresholds (commit 1).
2. Author migration `20270203_001_achievements.sql` (table + RLS + `award_achievements_for_user` + triggers +
   `notifications` kind extension), using the catalogue thresholds; add `achievements` to `_tables`; `supabase db
   reset`; run both codegen commands; add the two CHECK↔union pairs; write pgtap + seed fixture (commit 2).
3. Build the web surfaces: `BadgeGrid`, profile section, share page + OG + lambda, feed card, data.ts helpers,
   types.ts unions, i18n in all six locales, Playwright spec; `npm run check` (commit 3).
4. Mirror to mobile: `badges.dart` + tests, `badge_grid.dart`, profile/feed/notification branches, api_client +
   core_models model, ARBs + gen-l10n; diff-verify iOS twin byte-identical (commit 4).
5. Docs sweep (commit 5).
6. Run `/check` (and `/safe-edit` for the migration commit, since it's schema + SECURITY DEFINER) before committing the
   non-trivial pieces.
