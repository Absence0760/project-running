# Challenges & competitions — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value

Let runners join time-boxed **challenges** — "run 100 km in June", "20,000 m of vert this quarter", "run 20 days this month", "longest streak", "30 activities" — and watch a live leaderboard + personal progress bar fill as their logged activities accrue. Three social shapes: **individual** (everyone competes solo on one board), **club-vs-club** (each club's members pool a combined total, clubs ranked against each other), and **group-goal** (a club or ad-hoc cohort works toward one shared target — a co-op bar, not a ranking). It is the flagship engagement loop: it reuses the existing activity log, clubs, and follow graph rather than introducing a parallel data world, and it **self-hides entirely** when the user is in no challenge so non-joiners never see clutter. Completion fires a notification + records a durable badge.

## What already exists to build on (verified)

Backend / schema:
- `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql` — `clubs`, `club_members`, the `is_club_admin(uuid)` SECURITY DEFINER helper, the `club_members` SELECT/INSERT/UPDATE RLS pattern to copy. Member roles + status: `club_members.role` / `status` (`active`/`pending`). Helpers `is_event_organiser` / `is_race_director` live in the `private` schema (moved by `20261120_001`).
- `apps/backend/supabase/migrations/20261209_001_activities_view_is_public.sql` — the **`activities` UNION view** (`id, user_id, kind ∈ {run,lift,meal}, started_at, summary jsonb, is_public`), `security_invoker = true`. `summary` carries `distance_m` / `duration_s` / `activity_type` (runs), `volume_kg` / `set_count` (lifts). This is the single read-time spine challenge progress is computed from.
- `runs` table: `started_at`, `distance_m`, `duration_s`, `metadata.activity_type`, and `runs.metadata` jsonb (vert is NOT a first-class column — see Open Questions; total elevation gain is not currently projected into `activities.summary`). `apps/backend/supabase/migrations/20260601_001_runs_metadata_activity_type_required.sql` enforces `metadata.activity_type`.
- RPC patterns to copy: `event_next_instance_going_counts` (`20270122_001_event_next_instance_going_counts.sql`) — the canonical "push the per-row aggregate into SQL, return a `table(...)`, `security invoker`, `grant execute ... to authenticated, anon`" shape that kills the N+1. `mark_attendance` (`20270102_001_event_attendance.sql`) — the SECURITY DEFINER write-path-RPC + column-grant lockdown idiom.
- `notifications` table (`20260528000001_notifications.sql`): `user_id`, `actor_id`, `kind` (CHECK widened most recently in `20270107_001_notify_plan_assigned.sql` to 12 values — **a new kind means re-stating the full CHECK at the chain end**), nullable source FKs, `read_at`. SECURITY DEFINER triggers insert (regular users can't). The notification email/push channels are opt-in allowlists, so a new in-app kind stays bell-only by default.
- Narrow-union pattern: `apps/web/src/lib/types.ts` carries `ClubRole`, `RsvpStatus`, `EventCategory`, etc. as TS unions overlaid via `Omit<Row, ...> & {...}`, each paired with a DB CHECK. The CHECK↔union guard is `apps/web/scripts/check_constraint_unions.mjs` (`PAIRS` array — append new pairs here).

Web:
- `apps/web/src/lib/core/data.ts` — all Supabase queries. Existing social helpers to mirror in style: `browseClubs` / `fetchMyClubs` / `fetchClubBySlug` / `enrichClubs` (client-side enrichment join, `1665`), `createClub` (`1704`), `joinClub` (`1833`). `fetchEventResults` / `submitEventResult`. Engagement counts via the `run_engagement_counts` RPC (`4660`) — the no-N+1 precedent.
- `apps/web/src/lib/runs/race_leaderboard.ts#compareLeaderboard` — deterministic leaderboard tie-break (value desc → tiebreak → id). Reuse the **shape**; challenge ranking is a sibling pure helper.
- `apps/web/src/lib/runs/streaks.ts#computeRunStreaks` (parity pair with `apps/mobile_android/lib/streaks.dart`) — pure streak math, reuse directly for the streak challenge metric.
- `/social` hub: `apps/web/src/routes/social/+page.svelte` — ARIA tab strip (Feed / People / Clubs / Discover) with `?tab=` URL state, panels `SocialFeed` / `SocialPeople` / `SocialClubs` / `SocialDiscover` in `apps/web/src/lib/components/`.
- Create-flow modal pattern + `.modal` / `.editor-form` / `.btn-*` / `.card-elevated` global classes (`app.css`).

Mobile:
- `apps/mobile_android/lib/screens/social_screen.dart` — the Social tab host with sub-tabs (Feed / People / Clubs / Discover), each child `embedded: true`. `apps/mobile_android/lib/screens/clubs_screen.dart`, `club_detail_screen.dart`.
- `apps/mobile_android/lib/social_service.dart` — `SocialService` ChangeNotifier singleton, the mobile mirror of web `data.ts` social calls (`fetchMyClubs`, `createClub`, realtime `subscribeToEvent`).
- `apps/mobile_android/lib/local_activities.dart#buildLocalActivities` — offline cross-modal timeline from `LocalRunStore` + `LocalGymStore` + `LocalFoodStore`. Useful for an **offline-optimistic** local progress estimate.
- `packages/api_client` typed methods; `packages/core_models` generated row DTOs (`lib/src/generated/db_rows.dart`).
- i18n: web `src/lib/i18n/locales/{en,de,fr,es,ja,pt-BR}.ts` (parity enforced by `messages_parity.test.ts`); mobile `apps/mobile_android/lib/l10n/app_<locale>.arb` (parity by `test/l10n_parity_test.dart`), regen via `flutter gen-l10n`, mirror to iOS twin.

Verified that **no challenges/competitions feature exists today** (grep of roadmap, parity, clubs.md, code returned nothing). This is greenfield on top of the social layer.

## Data model / migrations

Two consecutive-date migrations (same-day `_NNN` does NOT disambiguate — walk dates per `apps/backend/CLAUDE.md`). Latest existing is `20270202_001`; use `20270203_001` then `20270204_001`.

### `20270203_001_challenges.sql` — core schema + RLS

```sql
-- challenges: a time-boxed competition over the activities spine.
create table challenges (
  id            uuid primary key default gen_random_uuid(),
  creator_id    uuid references auth.users(id) on delete set null not null,
  club_id       uuid references clubs(id) on delete cascade,   -- null = open/global
  title         text not null check (char_length(title) between 1 and 120),
  description   text check (char_length(description) <= 2000),
  metric        text not null,   -- CHECK below (ChallengeMetric union)
  scope         text not null,   -- CHECK below (ChallengeScope union)
  goal_value    numeric,         -- target in metric base unit; null for pure-ranking individual boards
  activity_type text,            -- null = any; else one of ActivityType ('run'|'walk'|'hike'|'cycle'|'stroller')
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  is_public     boolean not null default true,
  created_at    timestamptz not null default now(),
  constraint challenges_window_ck check (ends_at > starts_at),
  constraint challenges_metric_ck check (
    metric in ('distance','duration','vert','activity_count','streak_days')),
  constraint challenges_scope_ck check (
    scope in ('individual','club_vs_club','group_goal')),
  constraint challenges_activity_type_ck check (
    activity_type is null or activity_type in ('run','walk','hike','cycle','stroller')),
  -- club_vs_club + group_goal that pool by club require a club anchor only for
  -- group_goal-of-one-club; club_vs_club aggregates across many clubs so club_id
  -- stays null there. Enforce: group_goal with a single-club target sets club_id.
  constraint challenges_scope_club_ck check (
    scope <> 'club_vs_club' or club_id is null)
);
create index challenges_window on challenges (starts_at, ends_at);
create index challenges_club on challenges (club_id) where club_id is not null;

-- challenge_participants: who's in. For individual + group_goal this is the
-- person; for club_vs_club a row still belongs to a user, and team_club_id
-- records which club their total pools into.
create table challenge_participants (
  challenge_id  uuid references challenges(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  team_club_id  uuid references clubs(id) on delete set null,   -- club_vs_club only
  joined_at     timestamptz not null default now(),
  completed_at  timestamptz,    -- stamped by the completion path when goal met
  primary key (challenge_id, user_id)
);
create index challenge_participants_user on challenge_participants (user_id);
create index challenge_participants_team on challenge_participants (challenge_id, team_club_id);

-- challenge_badges: durable completion record (badge hook). One per
-- (user, challenge); insert is the completion side effect.
create table challenge_badges (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete cascade not null,
  challenge_id  uuid references challenges(id) on delete cascade not null,
  metric        text not null,
  final_value   numeric not null,
  awarded_at    timestamptz not null default now(),
  unique (user_id, challenge_id)
);
create index challenge_badges_user on challenge_badges (user_id, awarded_at desc);
```

RLS shape (copy `club_members` / `events` policies):
- `challenges` SELECT: `is_public = true` OR caller is creator OR (club_id is not null AND caller is an active member of that club via the `club_members` exists-subquery) OR caller is a participant. Fail-closed.
- `challenges` INSERT: `auth.uid() = creator_id` AND, when `club_id is not null`, `is_club_admin(club_id)` (only club admins create club-anchored challenges; open challenges anyone may create — revisit in Open Questions). UPDATE/DELETE: creator or `is_club_admin(club_id)`.
- `challenge_participants` SELECT: anyone who can SELECT the parent challenge (exists-subquery on `challenges` visibility — single source of truth, mirrors the event_attendees-inherits-events idiom). INSERT: `auth.uid() = user_id` AND the parent challenge is visible AND (for club-anchored / club_vs_club) the user is an active member of `team_club_id`. DELETE (leave): `auth.uid() = user_id`. `completed_at` is **column-locked** and written only by the SECURITY DEFINER progress RPC (copy the `event_attendees` attendance column-grant lockdown from `20270102_001`).
- `challenge_badges` SELECT: `auth.uid() = user_id` OR the badge's challenge is public (so a profile can show earned badges). INSERT: closed to clients — only the SECURITY DEFINER completion path. No client UPDATE/DELETE.

### `20270204_001_challenge_progress_rpc.sql` — the no-N+1 progress + completion engine

Two RPCs, both `security invoker` for reads (RLS on `activities`/base tables governs) and one SECURITY DEFINER writer for completion:

1. `challenge_leaderboard(p_challenge_id uuid) returns table(user_id uuid, display_name text, team_club_id uuid, value numeric, rank bigint)` — `security invoker`, `stable`. ONE query: join `challenge_participants` to a per-user aggregate over the `activities` view filtered to `started_at` within `[starts_at, ends_at)`, `kind = 'run'` (and `summary->>'activity_type'` when `activity_type` set), summing the metric expression:
   - distance: `sum((summary->>'distance_m')::numeric)`
   - duration: `sum((summary->>'duration_s')::numeric)`
   - activity_count: `count(*)`
   - vert: `sum((summary->>'vert_m')::numeric)` — **requires projecting vert into the view** (see migration note below + Open Questions)
   - streak_days: computed server-side from per-user distinct activity days in window (a `count(distinct date_trunc('day', started_at))`-style measure within the window; full Strava-grace streak math can also be done client-side by reusing `streaks.ts`/`streaks.dart` over the participant's in-window day set — pick the simpler distinct-day measure for the board, document the choice).
   For `club_vs_club`, a second grouping path aggregates by `team_club_id` (returned via a sibling RPC `challenge_team_leaderboard` or a `p_by_team boolean` arg). The key property: **N participants → 1 round trip, 0 client-side per-user fetches.** `rank` via `rank() over (order by value desc)`.

2. `my_active_challenges() returns table(... challenge fields ..., my_value numeric, my_rank bigint, participant_count bigint)` — `security invoker`, the **self-hiding driver**: returns only challenges the caller has joined that are currently live (`now() between starts_at and ends_at`) OR recently ended/completed (small window). An empty result set is the signal to render nothing.

3. `recompute_challenge_completion(p_challenge_id uuid, p_user_id uuid) returns void` — SECURITY DEFINER. Recomputes the caller's value via the same aggregate, and when `goal_value` is met and no badge row exists, inserts `challenge_badges` + stamps `challenge_participants.completed_at` + inserts a `challenge_complete` notification. Idempotent (the `unique(user_id, challenge_id)` badge row guards double-award). Called opportunistically by the client after a run saves (cheap, fail-closed) and/or by a daily pg_cron sweep (`enqueue`-style) for robustness. **Do not** put completion in a per-run trigger that fans out across all challenges — keep it on the explicit RPC + cron sweep to bound write amplification.

The `activities` view does NOT currently project elevation. The `vert` metric requires `create or replace view public.activities` appending `'vert_m', <expr>` into the runs branch's `summary jsonb_build_object`. Source of truth for elevation gain today: confirm whether it lives as a `runs` column or only in `metadata` before writing the expr (Open Question 1). **CREATE OR REPLACE can only append to the view's tail / can't reorder existing keys inside a jsonb_build_object** — but `summary` is one column, so editing its builder is fine; just keep the existing keys.

CHECK↔union pairs to register in `apps/web/scripts/check_constraint_unions.mjs` `PAIRS`: `ChallengeMetric` ↔ `challenges_metric_ck`, `ChallengeScope` ↔ `challenges_scope_ck`. (`activity_type` reuses the existing `ActivityType` pair.)

Codegen after `supabase db reset` (both committed, same commit as the migration):
```
cd apps/backend && npm run gen:types        # apps/web/src/lib/database.types.ts
cd ../.. && dart run scripts/gen_dart_models.dart   # packages/core_models/lib/src/generated/db_rows.dart
```

Seed: add one live open `distance` challenge + one club-anchored `group_goal` for Richmond Run Club to `apps/backend/supabase/seed.sql` (now()-relative window) so `/challenges` is populated on reset.

## Web implementation (canonical)

Routes (new, under the run-vs-social split — challenges are a social/engagement surface, mount in the `/social` hub + a dedicated detail route):
- `apps/web/src/routes/challenges/+page.svelte` — list/browse: My challenges (live + upcoming + completed) and a Browse (public) section. Thin; reuses the panel.
- `apps/web/src/routes/challenges/[id]/+page.svelte` — detail: hero (title, metric, window countdown), the user's **progress bar** (value vs `goal_value`, `prefers-reduced-motion`-safe), live leaderboard (individual rows or club-vs-club team cards or a single co-op group-goal bar), Join/Leave button, creator/admin edit + delete.
- `apps/web/src/routes/challenges/new/` — thin page wrapper around the `ChallengeEditor` modal component (create-flow modal pattern; deep-link parity).

Components (`apps/web/src/lib/components/`):
- `ChallengeEditor.svelte` — create/edit form (title, description, metric select, scope select, optional goal, optional activity-type filter, club anchor select from `fetchMyClubs` admin subset, start/end pickers). `class="editor-form"`, `oncreated`/`oncancel` callbacks. Hosted by the modal on `/challenges` AND the `/challenges/new` wrapper.
- `ChallengeLeaderboard.svelte` — renders the `challenge_leaderboard` rows; switches layout by scope.
- `ChallengeProgressBar.svelte` — the pure progress bar (value/goal → pct + label).
- `ChallengesPanel.svelte` — **the self-hiding entry point**: calls `myActiveChallenges()`; renders `null`/nothing when the result is empty. Mounted as a strip on `/dashboard` (above or below the stat grid) AND as a new `?tab=challenges` panel in `/social`.

`/social` integration: add a `challenges` tab to `apps/web/src/routes/social/+page.svelte`'s ARIA tab strip (`?tab=challenges`) hosting the browse list. (Keeps the 4→5 social sub-tab; this is a sub-tab, not a top-level nav item — no sidebar ceiling concern on web.)

`data.ts` helpers (`apps/web/src/lib/core/data.ts`):
- `fetchChallenges(opts)`, `fetchChallengeById(id)`, `createChallenge(input)`, `updateChallenge(id, patch)`, `deleteChallenge(id)`, `joinChallenge(id, teamClubId?)`, `leaveChallenge(id)`.
- `fetchChallengeLeaderboard(id, byTeam?)` → wraps `challenge_leaderboard` RPC.
- `myActiveChallenges()` → wraps `my_active_challenges` RPC (the self-hide driver).
- `recomputeChallengeCompletion(id)` → wraps the SECURITY DEFINER RPC; call it from the run-save success path (best-effort, swallow-to-debug like other auxiliary effects) so a finished run that crosses the line awards the badge promptly.
- Route all `.from('challenges' | 'challenge_participants' | 'challenge_badges')` through `core/schema.ts` TABLES registry (add the three names) so the `core/schema.test.ts` bare-string guard stays green.

Pure logic (`apps/web/src/lib/social/`):
- `challenge_progress.ts` — see parity section.

types.ts overlays (`apps/web/src/lib/types.ts`):
```ts
export type ChallengeMetric = 'distance' | 'duration' | 'vert' | 'activity_count' | 'streak_days';
export type ChallengeScope = 'individual' | 'club_vs_club' | 'group_goal';
export type Challenge = Omit<ChallengeRow, 'metric' | 'scope' | 'activity_type'> & {
  metric: ChallengeMetric; scope: ChallengeScope; activity_type: ActivityType | null;
};
export type ChallengeParticipant = ChallengeParticipantRow;
export type ChallengeBadge = ChallengeBadgeRow;
export type ChallengeLeaderboardRow = { user_id: string; display_name: string | null; team_club_id: string | null; value: number; rank: number };
export type ChallengeWithMeta = Challenge & { participant_count: number; my_value: number | null; my_rank: number | null; joined: boolean };
```

## Mobile implementation (Android + iOS twin)

Mirror after web lands. The mobile nav is at its 5-slot ceiling (`Home / Fitness / Log / Social / You`) — **do not add a 6th tab.** Mount challenges as a **sub-tab inside the Social hub** (`social_screen.dart`), matching how web puts it in `/social`, plus a self-hiding card on the Home dashboard.

Files (under `apps/mobile_android/lib/`, then mirror byte-identical to `apps/mobile_ios/lib/` in the **same commit**):
- `screens/challenges_screen.dart` — Social hub's new Challenges sub-tab (`embedded: true` mode, body-only). Browse + My challenges.
- `screens/challenge_detail_screen.dart` — hero + progress bar + leaderboard + Join/Leave; admin/creator edit + delete behind `AlertDialog` (destructive-confirm idiom).
- `widgets/challenge_form_sheet.dart` — create/edit bottom sheet (mirror `club_form_sheet.dart` / `event_form_sheet.dart`).
- `widgets/challenge_progress_card.dart` — the self-hiding Home dashboard card; renders nothing when `myActiveChallenges` is empty (data-presence self-hide, matching the gym/nutrition cards).
- `social_service.dart` — add `fetchChallenges`, `fetchChallengeById`, `createChallenge`, `joinChallenge`, `leaveChallenge`, `fetchChallengeLeaderboard`, `myActiveChallenges`, `recomputeChallengeCompletion` (route through `packages/api_client`, not direct `.from`).
- `social_screen.dart` — register the Challenges sub-tab + its FAB (Create challenge, admin/eligible only) in the hoisted-FAB slot.
- `dashboard_screen.dart` — mount `challenge_progress_card.dart` (best-effort hydrate on mount like the gym/nutrition cards).

Add the leaderboard/challenge DTOs to `packages/core_models` only if the RPC return shape isn't 1:1 with a generated row (the leaderboard rows aren't a table, so a hand model `ChallengeLeaderboardEntry` in core_models is expected).

Verify twin parity: `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` empty; same for `test/`.

## TS↔Dart parity helpers

One new pair (register it in the conventions parity list + watch with `shared-library-syncer`):
- **`challenge_progress`** — web `apps/web/src/lib/social/challenge_progress.ts` ↔ mobile `apps/mobile_android/lib/challenge_progress.dart`. Pure functions: `progressFraction(value, goal)` (clamp 0..1, null-goal → null), `formatProgressLabel`-feeding parts (locale/unit-agnostic structured parts, NOT formatted strings — the caller localises), `rankParticipants(entries)` (deterministic sort mirroring `compareLeaderboard`: value desc → user_id asc, assigning dense ranks), and `metricFromActivity(summary, metric, activityTypeFilter)` (the SAME metric-extraction math the SQL aggregate uses — so an offline-optimistic client estimate from local stores can't drift from the server board). Matching test counts both sides (target ~12 each, keep identical).
- Reuse the existing `streaks` pair for the `streak_days` metric — do not re-implement streak math.

## Tests

Playwright (`apps/web/tests-e2e/challenges/` — new dir; follow `tests-e2e/clubs/` fixture style, `fixtures/seeded-data.ts` + `fixtures/auth.ts`):
- `create.spec.ts` — create an individual distance challenge via the editor; appears in My challenges.
- `join-leave.spec.ts` — join → participant count increments → leave → removed.
- `leaderboard.spec.ts` — two seeded users with in-window runs rank correctly; ranks deterministic on reload.
- `progress-completion.spec.ts` — a run that crosses `goal_value` flips the progress bar to complete + a badge/notification appears.
- `club-vs-club.spec.ts` — team aggregation ranks clubs.
- `self-hide.spec.ts` — a user in no challenge sees no challenges strip on `/dashboard` and an empty My-challenges section.
- `visibility-rls.spec.ts` — a private/club-only challenge is invisible to a non-member (negative test, mirrors `private-rls-negative.spec.ts`).

pgtap (`apps/backend/supabase/tests/`):
- `challenges_rls_test.sql` — SELECT/INSERT/UPDATE/DELETE policy matrix (creator vs member vs outsider vs anon); fail-closed on private. Use the double-quoted `set local "request.jwt.claims"` idiom; seed `runs` rows WITH `metadata.activity_type`; valid hex UUIDs.
- `challenge_leaderboard_test.sql` — the aggregate returns correct sums/counts/ranks for a fixture of participants + in-window/out-of-window runs (proves the window filter + the single-query shape).
- `challenge_completion_test.sql` — `recompute_challenge_completion` awards exactly one badge, is idempotent, and respects `goal_value`.
- `challenge_participants_completed_lockdown_test.sql` — direct client UPDATE of `completed_at` is rejected (column-grant lockdown); the RPC succeeds.

Mobile (Flutter, in the same commit as each Dart piece, mirrored to iOS twin):
- `test/challenge_progress_test.dart` — the parity helper (count matches the TS side).
- `test/challenges_screen_test.dart` — list renders, self-hide when empty (use `tester.runAsync` for store I/O; dialog-scoped finders for duplicate labels per the mobile-test gotchas).
- `test/challenge_detail_screen_test.dart` — progress bar + Join/Leave + destructive-confirm dialog.
- `test/social_service_test.dart` — extend with challenge methods (the file is already in the modified set).

Web unit (`apps/web/src/lib/social/challenge_progress.test.ts`) — `npx tsx --test`, count matches Dart.

CHECK↔union guard: `apps/web/scripts/check_constraint_unions.mjs` extended (covered by the existing `parity-types` job).

## i18n keys to add (all six web locales + all mobile ARBs)

Representative web keys (`src/lib/i18n/locales/en.ts` template + de/fr/es/ja/pt-BR, real translations — parity test enforces non-empty + placeholder fidelity):
- `challenges.title`, `challenges.myChallenges`, `challenges.browse`, `challenges.empty`
- `challenges.create`, `challenges.join`, `challenges.leave`, `challenges.joined`
- `challenges.metricDistance`, `challenges.metricDuration`, `challenges.metricVert`, `challenges.metricActivityCount`, `challenges.metricStreak`
- `challenges.scopeIndividual`, `challenges.scopeClubVsClub`, `challenges.scopeGroupGoal`
- `challenges.goalProgress` (`"{value} of {goal}"`), `challenges.progressComplete`, `challenges.endsIn` (`"ends in {n} days"`), `challenges.leaderboardRank` (`"#{rank}"`)
- `challenges.completeNotification` (`"You completed {title}!"`), `challenges.badgeEarned`
- `challenges.deleteConfirm`, `challenges.leaveConfirm`

Mobile ARB equivalents camelCased (`challengesTitle`, `challengesJoin`, `challengesMetricDistance`, `challengesGoalProgress` with `{value}`/`{goal}` placeholders, …) in `app_en.arb` (with `@` metadata) + the other five; `flutter gen-l10n`; mirror `lib/l10n/gen/` to the iOS twin.

## Docs to update (same turns as the code)

- `docs/product/roadmap.md` — add a "Challenges & competitions" entry under Phase 3 social / the competitor-parity backlog with a `[x]` checkbox per slice as it lands (it's a Strava/Nike parity feature).
- `docs/product/parity.md` — add a Challenges row, flip web/android/ios cells as each platform lands.
- `docs/features/clubs.md` — add a "Challenges" subsection (the social layer doc) describing the tables, the activities-view-driven progress, the self-hide contract, scopes, and the badge hook; OR create `docs/features/challenges.md` and link it from `CLAUDE.md`'s doc index table (preferred given the feature's size — add the index row).
- `docs/backend/api_database.md` — document `challenges` / `challenge_participants` / `challenge_badges` tables + RLS + the three RPCs.
- `docs/architecture/conventions.md` — append the `challenge_progress` parity pair to the TS↔Dart lockstep list; also add it to `CLAUDE.md`'s parity-pair enumeration.
- `docs/architecture/decisions.md` — one entry: "Challenge progress is computed at read time from the `activities` view via a single GROUP-BY RPC (no per-participant fetch, no denormalised progress counter), and completion is an explicit RPC + cron sweep, not a per-run fan-out trigger." Note the badge as a durable side-effect table.
- `docs/backend/metadata.md` — only if a new `runs.metadata` key is touched for vert (likely not; vert should be a column/view expr, not a new metadata key).

## Gating / compliance

**None blocking.** No paywall (challenges are a free engagement feature — do not gate behind Pro; if a "Pro-only private challenges" idea surfaces, that's a later, separate decision). No Stripe / payouts. No Art 9 health data beyond what `activities` already exposes under existing RLS. No CISO/counsel sign-off gate. Standard RLS fail-closed is the only safety requirement: private/club challenges and badges must not leak to non-members — pin that with the negative pgtap + Playwright tests above. The leaderboard reveals participant `display_name`; participants opted in by joining, so showing their name to co-participants is consistent with the existing event-results board (no `runner_handle` anonymisation needed — unlike the anon-accessible live spectator page).

## Commit plan (ordered, path-scoped per-piece)

1. `git commit -- apps/backend/supabase/migrations/20270203_001_challenges.sql apps/backend/supabase/tests/challenges_rls_test.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart apps/web/scripts/check_constraint_unions.mjs apps/web/src/lib/types.ts` — schema + RLS + both regenerated type files + union guard + TS overlays + the RLS pgtap.
2. `git commit -- apps/backend/supabase/migrations/20270204_001_challenge_progress_rpc.sql apps/backend/supabase/tests/challenge_leaderboard_test.sql apps/backend/supabase/tests/challenge_completion_test.sql apps/backend/supabase/tests/challenge_participants_completed_lockdown_test.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart` — RPCs + activities-view vert append + completion/notification + pgtap (+ re-gen if the view change alters types).
3. `git commit -- apps/web/src/lib/social/challenge_progress.ts apps/web/src/lib/social/challenge_progress.test.ts` — the pure helper + unit tests (web side of the pair).
4. `git commit -- apps/web/src/lib/core/data.ts apps/web/src/lib/core/schema.ts` — data.ts helpers + schema registry table names.
5. `git commit -- apps/web/src/lib/components/Challenge*.svelte apps/web/src/lib/components/ChallengesPanel.svelte apps/web/src/routes/challenges/** apps/web/src/routes/social/+page.svelte apps/web/src/routes/dashboard/+page.svelte apps/web/src/lib/i18n/locales/*.ts apps/web/tests-e2e/challenges/*.spec.ts` — web UI + /social tab + dashboard strip + i18n + Playwright. (Split if large: editor+create, then detail+leaderboard, then self-hiding panel each its own commit with its spec.)
6. `git commit -- apps/backend/supabase/seed.sql` — seed challenges.
7. `git commit -- apps/mobile_android/lib/challenge_progress.dart apps/mobile_ios/lib/challenge_progress.dart apps/mobile_android/test/challenge_progress_test.dart apps/mobile_ios/test/challenge_progress_test.dart` — Dart parity helper + tests, both twins.
8. `git commit -- apps/mobile_android/lib/social_service.dart apps/mobile_ios/lib/social_service.dart apps/mobile_android/test/social_service_test.dart apps/mobile_ios/test/social_service_test.dart` — service methods + tests, both twins.
9. `git commit -- apps/mobile_android/lib/screens/challenges_screen.dart apps/mobile_android/lib/screens/challenge_detail_screen.dart apps/mobile_android/lib/widgets/challenge_form_sheet.dart apps/mobile_android/lib/widgets/challenge_progress_card.dart apps/mobile_android/lib/screens/social_screen.dart apps/mobile_android/lib/screens/dashboard_screen.dart apps/mobile_android/lib/l10n/*.arb apps/mobile_android/lib/l10n/gen/** <same paths under apps/mobile_ios/...> apps/mobile_android/test/challenge*_test.dart apps/mobile_ios/test/challenge*_test.dart` — mobile UI + nav + i18n + tests, both twins in one commit.
10. `git commit -- docs/** CLAUDE.md` — roadmap checkbox, parity cells, feature doc, api_database, conventions/decisions, doc index.

(Per house rule: commit only when the user asks; never `git push`; no AI attribution. The path-scoped form is mandatory in this shared checkout.)

## Open questions / decisions owed by the user

1. **Elevation/vert source.** Is total elevation gain a `runs` column or only in `runs.metadata`? The `vert` metric needs a real numeric to sum into `activities.summary`. If neither exists reliably per-run, either (a) ship vert in a later slice once elevation is first-classed, or (b) derive from track (too expensive at read time). Recommend deferring the `vert` metric to a follow-on slice unless a per-run elevation column exists — ship distance/duration/activity_count/streak first.
2. **Who can create open (non-club) challenges?** Anyone, or gated (e.g. to reduce spam, only club admins or verified users)? Plan assumes anyone can create an open challenge; club-anchored requires `is_club_admin`. If spam is a concern, add a rate-limit (`check_rate_limit` bucket) on `createChallenge`.
3. **club_vs_club team membership at completion.** If a user leaves their club mid-challenge, does their in-window contribution stay with the old team or move? Plan stamps `team_club_id` at join and keeps contributions on that team (simplest, deterministic). Confirm.
4. **streak_days metric definition** — full Strava-grace streak (reuse `streaks.ts`) vs. simple distinct-active-days-in-window count. Plan recommends distinct-active-days for the leaderboard (cheap, unambiguous ranking) and notes the grace-rule streak is a display nicety. Confirm.
5. **Lifts/meals in challenges?** The `activities` view also carries `lift`/`meal`. v1 scopes challenges to runs (`kind='run'`) only. Confirm runs-only for v1; a future "training-minutes" or "activity-count across modalities" metric is an easy extension.
6. **Completion trigger cadence** — opportunistic client RPC on run-save + a daily pg_cron sweep is the plan. Confirm a cron sweep is acceptable (it needs a `pg_cron` schedule like `enqueue_event_reminders`), or whether client-only recompute is sufficient for v1.

## Sequencing for the implementer

1. Read `apps/backend/CLAUDE.md` (migration gotchas), `docs/architecture/schema_codegen.md`, and `20270102_001_event_attendance.sql` + `20270122_001_event_next_instance_going_counts.sql` (the two idioms you'll copy).
2. Resolve Open Questions 1 + 5 with the user (they change the view edit + the metric set). Default to runs-only, vert deferred, if no answer.
3. Write `20270203_001_challenges.sql`; `cd apps/backend && supabase db reset` to confirm it applies; run both type generators; write `challenges_rls_test.sql`; `supabase test db`. Append the two CHECK↔union pairs to `check_constraint_unions.mjs`; add the TS overlays to `types.ts`. Commit (piece 1).
4. Write `20270204_001_challenge_progress_rpc.sql` (the leaderboard + my_active + completion RPCs, and the activities-view vert append if Q1 says vert ships now); reset + regen; write the three pgtap files. Commit (piece 2).
5. Write `apps/web/src/lib/social/challenge_progress.ts` + tests (`npx tsx --test`). Commit (piece 3).
6. Add `data.ts` helpers + `schema.ts` table names. Commit (piece 4).
7. Build the web UI (editor → detail/leaderboard → self-hiding panel + /social tab + dashboard strip), i18n keys in all six locales, Playwright specs. Verify `npm run check --workspace=apps/web` and the specs pass. Commit per-sub-piece (piece 5).
8. Seed challenges (piece 6).
9. Mirror to mobile: parity helper + tests (piece 7), service methods (piece 8), screens + nav + ARBs + gen-l10n + tests, **mirrored byte-identical to the iOS twin and verified with `diff -rq`** (piece 9).
10. Docs sweep — roadmap/parity/feature doc/api_database/conventions/decisions/index (piece 10).
11. Run `/check` (code-reviewer + test-gap + doc-hygiene) before declaring done.
