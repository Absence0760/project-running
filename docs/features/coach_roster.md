# Multi-athlete coach view — implementation plan

> **Status:** Shipped 2026-06-19 — web (`/coaching` roster table) + mobile (`coaching_screen.dart` roster card), migration `20270206_001_coach_roster_summary.sql` (the spec's planned `20270203_001` slot was taken by the time of landing — next free sequential date assigned). The body below is the implementation handoff plan it was built from; the only deviations from spec are the migration number and that the roster table/card sort is in-memory client-side (no saved sort yet). Tracked in [roadmap.md](../product/roadmap.md).

## Goal & user value

A coach who manages several athletes today must open one athlete review page at a time
(`/coaching/athletes/[id]`) to see runs and plan compliance — there is no single roster
dashboard. This feature adds a **roster dashboard** that shows, in one scrollable table/grid,
every linked athlete with their **last-7-day load**, **plan-compliance %**, **injury-risk flag**,
and **last-run recency**, each row drilling into the existing athlete review page. It lets a coach
triage "who's overcooked / who's slacking / who hasn't run in a week" at a glance, which is the
single most-requested missing piece of the runner-coach persona. All data is gated by the
**existing athlete-granted consent model** (the active `coach_athletes` link), fail-closed.

## What already exists to build on (verified)

The consent + authorization spine is fully built — this feature is a **read-only aggregation layer
on top of it**, not new plumbing:

- **`coach_athletes` table + link model** — `apps/backend/supabase/migrations/20261102_001_coach_athletes.sql`.
  An athlete redeems a coach's invite token → `status='active'` row. *That redemption is the consent.*
  Ending the link (`status='ended'`) revokes everything immediately.
- **`private.is_active_coach_of(coach, athlete)`** SECURITY DEFINER helper — `apps/backend/supabase/migrations/20261103_001_coach_run_visibility.sql`.
  The single authoritative "is this caller an active coach of this athlete" predicate. Reuse it verbatim.
- **Coach run-read RLS** — `runs` SELECT policy `"active coach reads athlete runs"` (same migration) grants an
  active coach SELECT on the athlete's run rows (public AND private), column-narrowed (no track bytes — track stays owner-only, decisions §98).
- **Coach plan-read RLS** — `apps/backend/supabase/migrations/20261116_001_coach_plan_access.sql` grants SELECT on
  `training_plans` / `plan_weeks` / `plan_workouts` for active-linked athletes (templates excluded).
- **Web data helpers** in `apps/web/src/lib/core/data.ts`:
  - `fetchMyAthletesWithError()` / `fetchMyAthletes()` (lines ~6274–6312) — the roster (active links + profile enrichment). `CoachAthleteLink` interface.
  - `fetchAthleteRuns(athleteId, limit)` (line ~6335) — `AthleteRunSummary[]` (no track), already RLS-scoped.
  - `fetchAthletePlanOverview(athleteId)` (line ~6367) — `ActivePlanOverview` with `completionPct` already computed.
- **Web routes**: `apps/web/src/routes/coaching/+page.svelte` (roster hub: invites + athlete/coach lists),
  `apps/web/src/routes/coaching/athletes/[id]/+page.svelte` (the per-athlete drill-in — the click target).
- **Mobile**: `apps/mobile_android/lib/screens/coaching_screen.dart` (roster hub) + `coaching_athlete_screen.dart` (drill-in).
  api_client coaching methods: `fetchMyAthletes` / `fetchAthleteRuns` / `fetchAthletePlanOverview`.
- **Load math already exists and is reusable**: `apps/web/src/lib/training/training_load.ts`
  (`computeTrainingLoadSeries` → fitness/fatigue/form trio; TRIMP/distance-proxy stress) and
  `apps/web/src/lib/training/fitness.ts`. The injury-risk flag derives from the **acute:chronic workload ratio (ACWR)**
  computable from the same daily-stress series (7-day acute ÷ 28-day chronic; >1.5 = elevated risk, the sports-science standard).
- **Recency / streak helpers**: `apps/web/src/lib/runs/streaks.ts` (`computeRunStreaks`), used for last-run recency framing.
- **Schema registry**: `coach_athletes`, `runs`, `personal_records` are all in `TABLES` in `apps/web/src/lib/core/schema.ts`.

## Data model / migrations

**No new table is strictly required for a correct V1** — the roster can be assembled client-side from existing
RLS-scoped reads (`fetchMyAthletes` + per-athlete `fetchAthleteRuns` + `fetchAthletePlanOverview`). That is an
N+1 fan-out (one runs query + one plan query per athlete), acceptable for the realistic roster size (a coach has
tens of athletes, not thousands) and keeps the consent model exactly as-is (every read already goes through the
proven RLS policies).

**The durable design, recommended, is a single SECURITY DEFINER roster RPC** that does the aggregation server-side
in one round-trip and re-checks consent per athlete inside the function — this is the long-term solution and is what
to build:

- **New migration**: `apps/backend/supabase/migrations/20270203_001_coach_roster_summary.sql` (next free date after
  the current latest `20270202_001`; one migration per day — keep `_001`).
- **RPC**: `coach_roster_summary()` — `language plpgsql`, `security definer`, `set search_path = public`, returns
  `setof` a row type `(athlete_id uuid, display_name text, avatar_url text, last_run_at timestamptz,
  runs_7d int, distance_7d_m double precision, load_acute double precision, load_chronic double precision,
  acwr double precision, active_plan_id uuid, plan_completion_pct int)`.
  - Body: `with mine as (select athlete_id from coach_athletes where coach_id = auth.uid() and status='active')`,
    then LEFT JOIN aggregates over `runs` (last 7d + last 28d windows for ACWR; `is_dnf=false`) and the athlete's
    active `training_plans` + a completion count over `plan_workouts` mirroring `fetchAthletePlanOverview`'s logic.
  - **Fail-closed**: `if auth.uid() is null then raise exception 'not authenticated'`. The `mine` CTE is the only
    membership gate — a non-coach gets zero rows. Re-checking consent **inside** the definer body (not relying on the
    caller's RLS, since SECURITY DEFINER bypasses it) is the load-bearing security property; mirror how
    `private.is_active_coach_of` is used as the gate.
  - `grant execute on function coach_roster_summary() to authenticated;` (NOT anon).
- **No CHECK/union pair** is added (no new narrow-string column).
- **Two codegen commands after the migration** (required even though this is an RPC, not a table — `db_rows.dart`
  won't change but run both for the drift gate):
  - `cd apps/backend && npm run gen:types` (the RPC appears under `Database['public']['Functions']`)
  - `cd ../.. && dart run scripts/gen_dart_models.dart`
- **pgtap** for the RPC lives at `apps/backend/supabase/tests/coach_roster_summary_test.sql` (see Tests).

ACWR threshold constant lives in the parity helper, NOT the SQL, so web + mobile + the RPC's display agree
(the RPC returns raw `acute`/`chronic`; the client computes the ratio + verdict via the shared helper — keeps the
risk policy in one testable place).

## Web implementation (canonical)

- **Route**: `apps/web/src/routes/coaching/+page.svelte` already exists as the coaching hub. Add the roster as a
  **new section / tab on that page** (the page already lists athletes as plain rows) — do NOT make a separate
  top-level sidebar item (on web `/coaching` is reached from the profile/logout popover in `+layout.svelte`, distinct
  from the standalone `/coach` chat sidebar item; keep that entry point). Render the
  roster as a sortable table when `athletes.length > 0`. Columns: Athlete (Avatar + name) · Last run (relative) ·
  7-day load · Plan % · Risk flag. Each row is a link to `/coaching/athletes/[id]`.
  - Reuse the page's existing flat `.card` panel (coaching is a flat-card page — there is deliberately no global
    `.card`, and `.card-elevated` is for the dashboard-style elevated panels only; see conventions § Web cards) and the
    global button classes. No local `.modal`/`.btn` redefs.
  - Sort defaults to "risk flag desc, then last-run-recency desc" so the athletes who need attention float up.
  - Empty / error / loading states mirror the existing page (it already has `loadError` + `loading`).
- **data.ts helper**: add `fetchCoachRosterSummary(): Promise<CoachRosterRow[]>` to `apps/web/src/lib/core/data.ts`
  in the coach-athlete section (~line 6224). Calls `supabase.rpc('coach_roster_summary')`, maps to a `CoachRosterRow`
  interface, and for each row computes the risk verdict + load label via the parity helper below. Return `[]` on
  error/unauthenticated (matches the section's existing fail-soft convention, but expose a
  `fetchCoachRosterSummaryWithError()` twin like `fetchMyAthletesWithError` so the page can show a retry state — that
  is the durable shape, follow it).
- **types.ts**: no overlay needed (the RPC return type is bespoke, declared as `CoachRosterRow` in data.ts; it isn't a
  base-table row). Keep it in data.ts next to `CoachAthleteLink`.

## Mobile implementation (Android + iOS twin)

Build **after** web ships and is reviewed (decisions §24). Every Dart change under `lib/` and `test/` is mirrored
byte-for-byte to `apps/mobile_ios` in the same commit.

- **api_client method**: add `fetchCoachRosterSummary()` to the coaching methods in
  `packages/api_client` (the same file holding `fetchMyAthletes`/`fetchAthleteRuns`). Returns a small
  `CoachRosterRow` model (add to `packages/core_models` if the shape isn't 1:1 with a generated row — it isn't, it's
  an RPC projection, so add a hand-written model class there).
- **Screen**: extend `apps/mobile_android/lib/screens/coaching_screen.dart` — add a roster summary list above/within the
  existing athlete list (each tile shows name + 7-day load + plan % + a risk chip, tapping pushes
  `coaching_athlete_screen.dart`, the existing drill-in). Use `showTopBanner` for any error, never `ScaffoldMessenger`.
  Follow the `StatefulWidget + setState` + `addListener`/`removeListener` pattern; no new DI.
- **Nav placement**: none added. Coaching is reached via Settings → Coaching tile (You tab → Settings). The 5-slot
  bottom-nav ceiling is untouched.

## TS↔Dart parity helpers

One new pure-logic pair (the injury-risk + load-band classification — shared so web, mobile, and the RPC-display
agree):

- **`coach_load` (web `apps/web/src/lib/training/coach_load.ts` ↔ mobile `apps/mobile_android/lib/coach_load.dart`)**:
  - `acwr(acute7d, chronic28dAvg): number` — acute:chronic workload ratio.
  - `injuryRiskBand(acwr): 'low' | 'optimal' | 'elevated' | 'high'` — buckets the ratio (sports-science "sweet spot"
    0.8–1.3 = optimal; <0.8 = detraining/low; 1.3–1.5 = elevated; >1.5 = high). Constants exported so tests pin them.
  - `loadTrend(acute, chronic): 'ramping' | 'steady' | 'tapering'` for the load column label.
  - Reuse the stress-score primitive from `training_load.ts` if the RPC ever returns raw daily stress; V1 the RPC
    returns acute/chronic sums so the helper just classifies.
  - **Matching test counts**: `coach_load.test.ts` (web) and `coach_load_test.dart` (mobile) with the SAME number of
    cases (target ~10 each — boundary cases at every band edge: 0.79/0.8/1.3/1.5 etc.). The shared-library-syncer agent
    watches this pair; add it to the parity-pair list in `docs/architecture/conventions.md` and the agent table.

## Tests

- **Backend (pgtap)** — `apps/backend/supabase/tests/coach_roster_summary_test.sql`:
  - Seed coach C, athlete A (active link), athlete B (link `ended`), stranger S (no link).
  - As C: roster returns A's row only (NOT B's ended link, NOT S). Assert `runs_7d` / `distance_7d_m` /
    `plan_completion_pct` match the seeded data.
  - As S (no athletes): roster returns zero rows.
  - As anon / unauthenticated: function raises (fail-closed). Use the double-quoted
    `set local "request.jwt.claims"` + `set local role` idiom; synthetic UUIDs hex-only; every `runs` insert carries
    `metadata.activity_type` (the CHECK from `20260601_001`).
  - End A's link mid-test → roster no longer returns A (consent revocation).
- **Web (Playwright)** — `apps/web/tests-e2e/coaching/roster.spec.ts`:
  - Sign in as the seed coach (seed must gain an active athlete link — extend `seed.sql`, see below), assert the roster
    section renders a row, the load/plan/risk columns are present, and clicking a row navigates to
    `/coaching/athletes/[id]`. A cross-user isolation case: a non-coach account sees an empty roster.
  - Seed change: add an active `coach_athletes` link in `apps/backend/supabase/seed.sql` so the e2e has a populated
    roster. The seed already provisions several users (`runner@test.com`, `alex@test.com`, `morgan@test.com`, plus
    others), so reuse two of those as coach + athlete rather than adding a fresh pair; there is no `coach_athletes`
    row in the seed today. Keep ids fixed for idempotency.
- **Web (unit)** — `coach_load.test.ts` (~10 cases, band boundaries).
- **Mobile (Flutter)** — `apps/mobile_android/test/coach_load_test.dart` (~10 cases, mirrors web) + a widget test for the
  roster section in `coaching_screen_test.dart` (renders rows from a fake api). Mirror both to iOS twin.

## i18n keys to add (all six web locales + ARBs)

Web (`apps/web/src/lib/i18n/locales/{en,de,fr,es,ja,pt-BR}.ts`), dotted keys; mobile ARBs camelCase
(`apps/mobile_android/lib/l10n/app_*.arb`, all six + base `pt`, real translations):

- `coaching.roster.title` → "Athlete roster"
- `coaching.roster.colLastRun` → "Last run"
- `coaching.roster.colLoad` → "7-day load"
- `coaching.roster.colPlan` → "Plan %"
- `coaching.roster.colRisk` → "Risk"
- `coaching.roster.riskLow` / `riskOptimal` / `riskElevated` / `riskHigh`
- `coaching.roster.loadRamping` / `loadSteady` / `loadTapering`
- `coaching.roster.empty` → "No athletes on your roster yet."
- `coaching.roster.loadError` → "Couldn't load your roster — retry."
- `coaching.roster.neverRun` → "No runs yet"

Run `flutter gen-l10n` after ARB edits and mirror `lib/l10n/gen/` to the iOS twin.

## Docs to update

- `docs/product/roadmap.md` — tick / add the runner-coach "multi-athlete roster dashboard" item.
- `docs/product/parity.md` — add a "Coach roster dashboard" row; mark Web `✓`, Android/iOS `✓` after the mobile commit,
  Wear/Apple Watch `—` (not applicable).
- `docs/features/training.md` (the runner-coach persona lives here) — document the roster surface + the consent model +
  the ACWR risk flag + that track bytes stay owner-only.
- `docs/backend/api_database.md` — document the `coach_roster_summary` RPC (SECURITY DEFINER, consent-gated, returns
  no track).
- `docs/architecture/conventions.md` — add `coach_load` to the TS↔Dart parity-pair list; mirror into the
  `shared-library-syncer` agent table.
- `docs/architecture/decisions.md` — one short ADR entry: "coach roster is a read-only SECURITY DEFINER aggregation
  re-checking consent per athlete inside the definer body; injury-risk flag is ACWR with the band thresholds in the
  shared `coach_load` helper, not the SQL; raw track stays owner-only (no new privacy surface)."

## Gating / compliance

- **Consent is the gate, and it already exists** — every read is scoped to an `active` `coach_athletes` link
  (athlete-granted, revocable, fail-closed). No new privacy boundary is opened: this feature surfaces only data the
  coach can *already* read under `20261103_001` / `20261116_001` (run stats minus track, plan compliance).
- **Raw GPS track stays owner-only** — the roster shows aggregates and recency only; it never downloads or exposes the
  track bytes. Do not add a track read here.
- **No paywall gate** in V1 (coaching is not a paywalled surface today). If a future decision paywalls multi-athlete
  coaching, gate the roster section behind the existing `ProGate` component with a default-off flag — but that is not in
  scope and should not be stubbed in.
- **No CISO/counsel sign-off gate** — no new personal-data exposure beyond the already-shipped consent grant. (If the
  reviewer disagrees because the *aggregation* is a new surface, the ADR entry is the artifact they review on `main`.)

## Commit plan (ordered, path-scoped)

1. `feat(backend): coach_roster_summary SECURITY DEFINER aggregation RPC` — migration `20270203_001_*.sql` +
   regenerated `apps/web/src/lib/database.types.ts` + `packages/core_models/lib/src/generated/db_rows.dart` +
   `apps/backend/supabase/tests/coach_roster_summary_test.sql` + seed link.
   Paths: `apps/backend/supabase/migrations/20270203_001_coach_roster_summary.sql apps/backend/supabase/tests/coach_roster_summary_test.sql apps/backend/supabase/seed.sql apps/web/src/lib/database.types.ts packages/core_models/lib/src/generated/db_rows.dart`
2. `feat(web): coach_load injury-risk + load-band helper` — `apps/web/src/lib/training/coach_load.ts` +
   `coach_load.test.ts`.
3. `feat(web): coach roster dashboard on /coaching` — `+page.svelte` + `fetchCoachRosterSummary` in `data.ts` +
   i18n keys in all six locales + `apps/web/tests-e2e/coaching/roster.spec.ts`.
   Paths: `apps/web/src/routes/coaching/+page.svelte apps/web/src/lib/core/data.ts apps/web/src/lib/i18n/locales/*.ts apps/web/tests-e2e/coaching/roster.spec.ts`
4. `feat(mobile): coach_load helper + roster on coaching screen` — Dart helper + tests + `coaching_screen.dart` +
   api_client method + core_models model + ARBs + gen-l10n. **Mirror every path to `apps/mobile_ios` in the same
   commit.**
5. `docs: document coach roster dashboard + ACWR risk flag` — roadmap, parity, training.md, api_database.md,
   conventions.md, decisions.md.

## Open questions / decisions owed by the user

1. **Injury-risk model**: ACWR (acute:chronic workload ratio) is the proposed, defensible, computable-from-existing-data
   signal. Confirm it's acceptable vs. something heavier (HRV / sleep — neither of which we collect). ACWR needs ≥28 days
   of history to be meaningful; for newer athletes the flag should read "insufficient data" rather than a false "low."
2. **N+1 fan-out vs. RPC**: plan recommends the SECURITY DEFINER RPC (one round-trip, server-side consent recheck).
   Confirm we want the RPC now vs. the cheaper client fan-out (acceptable at small roster size but N queries). The plan
   assumes RPC.
3. **Load window**: 7-day acute is proposed for the visible "load" column. Confirm 7d (vs 14d) for the headline number.
4. **Roster placement**: proposed as a section/tab on the existing `/coaching` page (no new sidebar item). Confirm vs. a
   dedicated `/coaching/roster` route.

## Sequencing for the implementer

1. Author migration `20270203_001_coach_roster_summary.sql`; `supabase db reset`; verify the RPC returns correct
   aggregates for the seed link you add.
2. Run both codegen commands; commit the migration + generated files + pgtap + seed (commit 1).
3. Write `coach_load.ts` + tests; commit (commit 2).
4. Add `fetchCoachRosterSummary` + the roster section to `/coaching/+page.svelte`; add i18n keys to all six locales;
   write the Playwright spec; `npm run check`; commit (commit 3).
5. Mirror to mobile: api_client method, core_models model, `coach_load.dart` + tests, `coaching_screen.dart` roster
   section, ARBs (+ gen-l10n); diff-verify the iOS twin is byte-identical; commit (commit 4).
6. Docs sweep; commit (commit 5).
7. Run `/check` against the working diff before each commit on the non-trivial pieces.
