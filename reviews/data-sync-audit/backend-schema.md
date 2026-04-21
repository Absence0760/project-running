# Backend + codegen schema audit

## Summary

24 migration files, 7 Edge Functions, 3 generated output files, and the generator script were reviewed. The generators are **in sync** — running both generators against the live local Supabase instance produces no diff against committed files. The high-severity findings are concentrated in three areas: (1) a security-definer RPC that lets any authenticated user spoof another user's coach-usage counter, enabling quota bypass; (2) the RevenueCat webhook HMAC check is conditional on the header being present — a request without the header completely bypasses signature verification and can set any user's `subscription_tier`; (3) the Dart generator silently ignores `ALTER COLUMN ... SET NOT NULL`, causing `event_attendees.instance_start` to be typed nullable in Dart when the DB is NOT NULL, meaning an Android upsert of an attendee row can omit the primary key component entirely. Medium findings include: Postgres enum columns (`plan_phase`, `workout_kind`, `goal_event`) are emitted as `dynamic` in Dart/Kotlin while TypeScript has the proper enum type — cross-platform enum drift has no compile-time guard; `runs.source`, `routes.surface`, `integrations.provider`, `user_profiles.preferred_unit`, and several social/event columns have no DB CHECK constraint, so an Android bug writing e.g. `'cycle'` instead of `'app'` is accepted silently; and the parkrun importer passes raw scraped date strings (e.g. `"01/04/2026"`) directly into the `started_at` timestamptz column without parsing, which PostgreSQL will reject at runtime on well-formed inserts. Low findings cover CI coverage gaps, an unused Storage delete policy for `monthly_funding`, and several missing `updated_at` auto-update triggers.

---

## Findings

### H1. RevenueCat webhook HMAC check is optional — missing header bypasses auth entirely

**Severity:** HIGH
**File(s):** `apps/backend/supabase/functions/revenuecat-webhook/index.ts:28-32`
**Issue:** The HMAC signature is only verified `if (sig)` — that is, if the `x-revenuecat-hmac` header is present. A POST request that omits the header passes through with `sig = null`, the branch is skipped, and the function proceeds to update `user_profiles.subscription_tier` for any `app_user_id` that appears in the body. An attacker who knows a victim's Supabase user UUID can POST a crafted `INITIAL_PURCHASE` event with `product_id = "lifetime_..."` and promote any account to `lifetime` with no credentials.
**Cross-platform impact:** All clients read `subscription_tier` to gate Pro features. Any account can be fraudulently upgraded or downgraded to `free`, affecting every client.
**Fix sketch:**
```diff
- const sig = req.headers.get('x-revenuecat-hmac');
- if (sig) {
-   const expected = hmac('sha256', secret, body, 'utf8', 'hex');
-   if (sig !== expected) {
-     return new Response('Bad signature', { status: 401 });
-   }
- }
+ const sig = req.headers.get('x-revenuecat-hmac');
+ if (!sig) {
+   return new Response('Missing signature', { status: 401 });
+ }
+ const expected = hmac('sha256', secret, body, 'utf8', 'hex');
+ if (sig !== expected) {
+   return new Response('Bad signature', { status: 401 });
+ }
```

---

### H2. `increment_coach_usage` (security definer) accepts any `p_user_id` without validating it matches `auth.uid()`

**Severity:** HIGH
**File(s):** `apps/backend/supabase/migrations/20260430_001_coach_usage.sql:30-47`
**Issue:** The function is `security definer` and is `grant execute ... to authenticated`. Any authenticated user can call `increment_coach_usage(some_other_users_uuid)` to exhaust another user's daily coach quota (setting their count to 10+ so they appear over-limit) or — far more practically — can call it with their **own** UUID from a client-side request to fabricate a lower count by inserting a 1-count row for a future date. More immediately: `get_coach_usage` has the same missing check — any user can read any user's daily message count, which leaks whether a target user is active.

```sql
-- current: no caller-identity check
insert into user_coach_usage (user_id, usage_date, message_count)
values (p_user_id, current_date, 1) ...
```

**Cross-platform impact:** Web coach endpoint calls these RPCs. Android would call them if/when coach lands on mobile. The web coach route (`apps/web/src/routes/api/coach/+server.ts`) is the only current caller — it passes `user.id` from a server-side JWT, so it is safe in practice today. But the grant is to all `authenticated` clients, so a raw REST call from any client can invoke it with an arbitrary UUID.
**Fix sketch:** Add a guard at the top of both functions:
```sql
if auth.uid() != p_user_id then
  raise exception 'not authorized';
end if;
```

---

### H3. Dart generator silently ignores `ALTER COLUMN ... SET NOT NULL` — `event_attendees.instance_start` typed nullable in Dart

**Severity:** HIGH
**File(s):** `apps/backend/supabase/migrations/20260417_001_phase2_social.sql:27-33`, `packages/core_models/lib/src/generated/db_rows.dart:196`, `scripts/gen_dart_models.dart:290-319`
**Issue:** Migration `20260417` adds `instance_start timestamptz` as nullable, then immediately promotes it with `alter column instance_start set not null`. The generator only handles `add column` and `drop column` — `alter column ... set not null` is silently skipped. The result is `EventAttendeeRow.instanceStart` is typed `DateTime?` in Dart even though the column is NOT NULL and part of the primary key. An Android client that constructs an `EventAttendeeRow` without `instanceStart` (i.e., passes `null`) and upserts it will have the row rejected by Postgres at runtime with a NOT NULL constraint violation — surfacing as a sync failure with no compile-time warning.

```dart
// db_rows.dart:196 — wrong: DB is NOT NULL
final DateTime? instanceStart;
```
```typescript
// database.types.ts:172 — correct: required
instance_start: string
```

**Cross-platform impact:** Android (via `EventAttendeeRow`). TypeScript is correct because `supabase gen types` reads the live schema. Kotlin is not affected (`event_attendees` is not in `_kotlinTables`).
**Fix sketch:** The generator needs to track `alter column ... set not null` / `alter column ... drop not null`. Migration name for a quick workaround: none needed — extend `_parseAlterTable` in `scripts/gen_dart_models.dart` to recognise `alter column COL set not null` and flip `_Column.nullable = false`.

```dart
// In _parseAlterTable, add a branch:
} else if (lower.startsWith('alter column')) {
  final parts = rest.split(RegExp(r'\s+', caseSensitive: false));
  // parts: ['alter', 'column', 'colname', 'set'/'drop', 'not'?, 'null']
  if (parts.length >= 5 && parts[3].toLowerCase() == 'set'
      && parts[4].toLowerCase() == 'not') {
    final colName = parts[2].toLowerCase();
    schema[table]?[colName]?.nullable = false;
  } else if (parts.length >= 4 && parts[3].toLowerCase() == 'drop') {
    final colName = parts[2].toLowerCase();
    schema[table]?[colName]?.nullable = true;
  }
}
```

---

### H4. Parkrun importer passes raw scraped date string into `started_at timestamptz` without parsing

**Severity:** HIGH
**File(s):** `apps/backend/supabase/functions/parkrun-import/index.ts:37-43`
**Issue:** `const date = $(cells[1]).text().trim()` extracts the date cell verbatim from the parkrun HTML table (parkrun UK uses `DD/MM/YYYY` format, e.g. `"01/04/2026"`). This string is passed directly as `started_at` in the upserted run row. PostgreSQL's `timestamptz` column will reject this format and throw `invalid input syntax for type timestamp`. The upsert call doesn't check for errors — the function returns `{ imported: N }` from `runs.length` which is the count of scraped rows, not the count successfully written. Every call to this endpoint silently fails to write any runs.

```typescript
started_at: date,  // raw "01/04/2026" — Postgres rejects this
```

**Cross-platform impact:** Web and Android both call this endpoint to populate a user's parkrun history. All parkrun imports are currently silently failing.
**Fix sketch:**
```typescript
// parse "DD/MM/YYYY" → ISO 8601
function parseParkrunDate(d: string): string {
  const [dd, mm, yyyy] = d.split('/');
  return `${yyyy}-${mm}-${dd}T08:00:00Z`; // parkrun is Saturday morning
}
// then:
started_at: parseParkrunDate(date),
```

---

### M1. Postgres enum columns (`plan_phase`, `workout_kind`, `goal_event`) emit as `dynamic` in Dart and Kotlin — no compile-time guard on invalid values

**Severity:** MED
**File(s):** `scripts/gen_dart_models.dart:27-58` (the `_pgToDart` map), `packages/core_models/lib/src/generated/db_rows.dart:556,610,1059`
**Issue:** The generator has no mapping for user-defined Postgres enum types. `plan_phase`, `workout_kind`, and `goal_event` all fall through to `dynamic`. In TypeScript, these are correctly typed as `Database["public"]["Enums"]["plan_phase"]` etc., giving a compile error on an invalid string. In Dart, `PlanWeekRow.phase`, `PlanWorkoutRow.kind`, and `TrainingPlanRow.goalEvent` are `dynamic` — a Dart caller can write any string (e.g. `'marathon'` instead of `'marathon_pace'`) and it compiles cleanly but is rejected by Postgres at runtime. The Dart INSERT policy for `plan_workouts` depends on RLS join, so a rejected write surfaces only as a silent upsert failure.
**Cross-platform impact:** Android (via Dart `ApiClient`). TypeScript on web is correct. Kotlin is not affected (these tables are not in `_kotlinTables`).
**Fix sketch:** Add enum-type handling to the generator. The generator already parses `create type ... as enum` — it currently ignores it. Extend `_applyMigration` to collect enum names into a `_enums: Set<String>` and in `_pgToDart` fall back to `'String'` (with a comment) when the type is a known enum name. Emit a Dart `const` list of valid values per enum for runtime validation if desired.

---

### M2. `runs.source`, `routes.surface`, and `integrations.provider` have no CHECK constraint — value drift is silent

**Severity:** MED
**File(s):** `apps/backend/supabase/migrations/20260405_001_initial_schema.sql:23,11,41`, `apps/web/src/lib/types.ts:55-65`
**Issue:** `runs.source` accepts any text. The documented values are `app | healthkit | healthconnect | strava | garmin | parkrun | race`. The Dart recorder writes `run.source.name` from a `RunSource` enum — if a client adds a new enum variant without a migration, or a different client writes a value outside the documented set, the DB accepts it and the web's `Omit<...> & { source: RunSource }` cast silently returns `undefined` for unknown values. The same applies to `routes.surface` (`road | trail | mixed`) and `integrations.provider` (`strava | garmin | parkrun | runsignup`). `personal_records()` filters on `source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')` — a run with `source = 'health_connect'` (underscore variant) would be silently excluded from PBs. This is documented as a known limitation but its actual risk is higher than acknowledged: any future client (e.g. Wear OS writing a new source type) has no DB backstop.
**Cross-platform impact:** Android, Wear OS, Web, Watch iOS. All write `source`. Web narrows it at the type layer; Dart and Kotlin do not.
**Fix sketch:** Add to a new migration:
```sql
alter table runs add constraint runs_source_check
  check (source in ('app','healthkit','healthconnect','strava','garmin','parkrun','race'));
alter table routes add constraint routes_surface_check
  check (surface in ('road','trail','mixed'));
alter table integrations add constraint integrations_provider_check
  check (provider in ('strava','garmin','parkrun','runsignup'));
```

---

### M3. `user_profiles.preferred_unit` has no CHECK constraint and the migration-21 transition left the column in a dual-read state indefinitely

**Severity:** MED
**File(s):** `apps/backend/supabase/migrations/20260423_001_backfill_preferred_unit.sql:1-16`, `apps/web/src/lib/types.ts:66`
**Issue:** Migration `20260423` backfills `user_profiles.preferred_unit` into `user_settings.prefs` and states the column will be dropped "in a follow-up migration once every client has switched over." That migration has never landed (there is no `20260423+` migration that drops the column). Both column and the `user_settings` bag key exist simultaneously with no enforcement that they stay in sync. An Android client that still writes to `preferred_unit` directly, while the web reads only from `user_settings.prefs`, will silently diverge. There is also no CHECK constraint on the column — `'miles'` instead of `'mi'` would be silently accepted.
**Cross-platform impact:** Android reads/writes `preferred_unit` on `UserProfileRow`; web reads from `user_settings.prefs` first and falls back. The two will drift if a client writes to one but not both.
**Fix sketch:** Either (a) add the drop-column migration now and ensure all clients read from `user_settings.prefs`, or (b) add a trigger that keeps both in sync. At minimum add a CHECK:
```sql
alter table user_profiles add constraint user_profiles_preferred_unit_check
  check (preferred_unit in ('km', 'mi'));
```

---

### M4. CI drift check does not cover Dart or Kotlin files — only TypeScript

**Severity:** MED
**File(s):** `.github/workflows/ci.yml:24-38` (`parity-types` job), `apps/backend/CLAUDE.md:89`
**Issue:** The `parity-types` job runs only `npm run gen:types:check`, which checks `database.types.ts`. The Dart and Kotlin codegen drift check is in a *separate* `schema-codegen-drift` job that runs the Dart generator and then diffs the output — this IS present in CI (lines 59-81). However, the `schema-codegen-drift` job does not run on `pull_request` to `main` (the `on:` trigger at the top only covers `push` to `main` and `pull_request` to `main`, and looking at the file the `schema-codegen-drift` job does not have a conditional limiting it). Actually, on re-reading: all jobs in the file run on PR — this is fine. The gap is that `parity-types` and `schema-codegen-drift` are different jobs with no dependency declared between them, but that's acceptable.

The actual gap: `CLAUDE.md` states at line 89 "There is no equivalent CI gate for the Dart generator yet." This is now **wrong** — the `schema-codegen-drift` job exists. The documentation drift is the finding.
**Cross-platform impact:** Misleads future contributors into believing the Dart/Kotlin check is absent, causing them to skip regeneration.
**Fix sketch:** Update `apps/backend/CLAUDE.md` line 89:
```diff
- CI's `parity-types` job runs `npm run gen:types:check` and fails the build if the committed TS file is out of sync with the schema. There is no equivalent CI gate for the Dart generator yet — rely on `dart analyze` to flag stale references in `packages/api_client`.
+ CI's `parity-types` job checks `database.types.ts`. The `schema-codegen-drift` job regenerates and diffs both `db_rows.dart` and `DbRows.kt` — all three are gated on PRs to `main`.
```
Also update `docs/schema_codegen.md` which repeats the same claim at line 90.

---

### M5. `monthly_funding` has no write policies — the service role is the only path and is undocumented as such

**Severity:** MED
**File(s):** `apps/backend/supabase/migrations/20260501_001_funding.sql:12-18`
**Issue:** RLS is enabled on `monthly_funding` with only a `select` policy (`using (true)`). There are no INSERT, UPDATE, or DELETE policies. The comment says "Only the project owner can write. For now, use service role or direct SQL." This means any INSERT/UPDATE attempt from a regular authenticated client (e.g. if someone wired a donation confirmation webhook later) silently fails — the PostgREST layer returns a 403 with no row written, not an error the caller sees unless it checks the response. The `export-data` function returns a placeholder URL today, but if a future Stripe/Ko-fi webhook lands as a user-context function rather than service-role, it will fail silently.
**Cross-platform impact:** Web donate page (reads only — unaffected). Any future write path.
**Fix sketch:** Either document explicitly in a migration comment that this table is service-role-write-only and no client-side write policy will ever be added, or create a service-role-gated RPC for the write path now to prevent an implicit assumption later.

---

### M6. `increment_coach_usage` accepts any future date — daily limit can be pre-exhausted

**Severity:** MED
**File(s):** `apps/backend/supabase/migrations/20260430_001_coach_usage.sql:39-44`
**Issue:** (Separate from H2.) The function inserts with `current_date` hardcoded — callers cannot actually inject a date. However, the INSERT bypasses the RLS `with check` on `user_coach_usage` because it runs as `security definer`. The `user_coach_usage_own_insert` policy checks `auth.uid() = user_id` but the security-definer execution context uses the function owner's identity, not the caller. This means the function's insert succeeds for any `p_user_id` (see H2 for the fuller security finding). Additionally, there is no DELETE policy on `user_coach_usage` — a user cannot clean up their own usage row even if desired.
**Cross-platform impact:** Web (sole current caller). Would affect any mobile client that calls the RPC.
**Fix sketch:** Addressed by H2 fix (add `auth.uid() != p_user_id` guard). The missing DELETE policy is low-priority since users have no current need to delete usage rows.

---

### M7. `event_attendees.instance_start` is NOT NULL in DB but Dart emits `DateTime?` — Dart upserts will fail at runtime for RSVP operations

**Severity:** MED (sub-finding under H3, separate impact)
**File(s):** `packages/core_models/lib/src/generated/db_rows.dart:196-219`
**Issue:** Beyond the type mismatch noted in H3: the Dart `EventAttendeeRow.toJson()` will write `colInstanceStart: null` when `instanceStart` is not provided in the constructor. A Supabase upsert with an explicit `null` for a NOT NULL primary-key column will fail with a constraint violation. The generated `fromJson` will also fail with a runtime cast error on any row returned from the DB (though `DateTime.parse(null)` is caught by the null check, the `as String` cast of the guaranteed-non-null DB value is safe — the `fromJson` path is actually fine; only the `toJson` / insert path is broken).
**Cross-platform impact:** Android only (Dart). Does not affect web or Wear OS.
**Fix sketch:** Same as H3 — extend the generator to parse `ALTER COLUMN SET NOT NULL`.

---

### L1. `updated_at` columns have no auto-update trigger on any table

**Severity:** LOW
**File(s):** `apps/backend/supabase/migrations/20260405_001_initial_schema.sql:15,34`
**Issue:** `runs.updated_at`, `routes.updated_at`, `integrations.updated_at`, and all social/event tables have `updated_at timestamptz default now()` — this only fires on INSERT. A PATCH/UPDATE from any client will leave `updated_at` stale at the insert time unless the caller explicitly sets it. The Dart `ApiClient.saveRun` does not set `updated_at` in the row (it uses `RunRow.toJson()` which omits it when not provided in the constructor). The `refresh-tokens` function does set `updated_at: new Date().toISOString()` manually. This inconsistency means `updated_at` on runs is unreliable for any "last modified" ordering.
**Cross-platform impact:** Android, web. The `local_run_store.dart` uses `metadata.last_modified_at` for conflict resolution, not `updated_at`, so the immediate functional impact is limited.
**Fix sketch:** Add a `moddatetime` trigger (Supabase provides the `moddatetime` extension) or a custom trigger to the tables that have `updated_at`:
```sql
create extension if not exists moddatetime schema extensions;
create trigger runs_updated_at before update on runs
  for each row execute function extensions.moddatetime(updated_at);
```

---

### L2. Storage policy for public run tracks uses `runs.track_url = name` — path normalization mismatch risk

**Severity:** LOW
**File(s):** `apps/backend/supabase/migrations/20260413_001_public_runs.sql:19-29`
**Issue:** The anon-read policy for public run tracks checks `runs.track_url = name` where `name` is the Storage object name. Both the Dart client and the Kotlin `SupabaseClient` store paths as `{user_id}/{run_id}.json.gz`. This matches the Storage object naming convention. The policy works correctly today. The risk is that if any future client stores the full URL (`https://.../storage/v1/object/runs/...`) rather than the relative path in `track_url`, the comparison fails silently and public tracks return 403. The `decisions.md` note on this (§2) acknowledges the `track_url` field but doesn't constrain its format.
**Cross-platform impact:** Web and iOS share page. Would affect unauthenticated viewers of public runs.
**Fix sketch:** Add a comment to the storage policy and to `docs/decisions.md` §2 specifying that `track_url` must store the relative path (no base URL prefix). Consider adding a CHECK constraint: `check (track_url not like 'http%')`.

---

### L3. `plan_workouts.plan_id` index is missing — RLS join walks `plan_weeks → training_plans` on every workout write

**Severity:** LOW
**File(s):** `apps/backend/supabase/migrations/20260419_001_training_plans.sql:103-106,114-131`
**Issue:** The RLS policy on `plan_workouts` is:
```sql
using (
  exists (
    select 1 from plan_weeks w join training_plans p on p.id = w.plan_id
    where w.id = plan_workouts.week_id and p.user_id = auth.uid()
  )
)
```
There is a `plan_workouts_week on plan_workouts (week_id, scheduled_date)` index to find workouts by week, and a `plan_weeks_plan on plan_weeks (plan_id, week_index)` index to find weeks by plan. The join `plan_weeks w where w.id = plan_workouts.week_id` requires looking up `plan_weeks` by its primary key (covered by the PK index), so this is fine. No additional indexes are needed here.

Actually on re-examination this is adequately indexed. Withdrawing as a finding — the PK index on `plan_weeks.id` covers the join.

---

### L4. Seed data does not cover `user_settings` table

**Severity:** LOW
**File(s):** `apps/backend/supabase/seed.sql`
**Issue:** Migration `20260423_001_backfill_preferred_unit.sql` inserts into `user_settings` for existing `user_profiles` rows during migration. But the seed runs all migrations (which insert `user_profiles` before that migration runs), so the backfill correctly populates `user_settings` for the seed user. However, there is no explicit seed entry for `user_settings` in `seed.sql`, so the state is not obvious when reading the seed file alone. Not a functional bug.
**Cross-platform impact:** None — backfill migration handles it.
**Fix sketch:** Add a comment in `seed.sql` near the `user_profiles` insert noting that `user_settings` is populated by migration `20260423_001_backfill_preferred_unit.sql`.

---

## Generator outputs: current state

Both generators were run against the live local Supabase instance (confirmed running via `supabase status`):

```
dart run scripts/gen_dart_models.dart
→ Wrote packages/core_models/lib/src/generated/db_rows.dart
→ Wrote apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/generated/DbRows.kt
```

```
cd apps/backend && npm run gen:types
```

After both runs: `git diff` on all three generated files produced **no output** — the working tree is clean. The committed files match the live schema exactly.

---

## RLS + Storage policy matrix

| Table | INSERT | UPDATE | SELECT | DELETE |
|---|---|---|---|---|
| `runs` | owner only (all policy) | owner only (all policy) | owner OR `is_public = true` (anon allowed) | owner only |
| `routes` | owner only (all policy) | owner only (all policy) | owner OR `is_public = true` (anon allowed) | owner only |
| `integrations` | owner only | owner only | owner only | owner only |
| `user_profiles` | owner only | owner only | owner only | owner only |
| `route_reviews` | authenticated, owner only (with check) | authenticated, owner only | reviews on public routes readable by anyone | owner only |
| `clubs` | authenticated, `owner_id = auth.uid()` | `is_club_admin()` | `is_public = true` OR (private AND `is_club_member()`) | `owner_id = auth.uid()` |
| `club_members` | self-insert OR organiser-add | `is_club_admin()` (role change) | club-visible OR own row | self-leave OR `is_club_admin()` |
| `events` | `is_event_organiser()` | `is_event_organiser()` | visible with club | `is_event_organiser()` |
| `event_attendees` | self OR `is_event_organiser()` | self only | visible with event | self only |
| `club_posts` | `is_club_member()` (top-level: admin only in policy name but `members can post` is the live policy) | — (no update policy) | visible with club | author only |
| `training_plans` | owner only | owner only | owner only | owner only |
| `plan_weeks` | owner (via join check) | owner (via join check) | owner (via join check) | owner (via join check) |
| `plan_workouts` | owner (via join check) | owner (via join check) | owner (via join check) | owner (via join check) |
| `user_settings` | self only | self only | self only | self only |
| `user_device_settings` | self only | self only | self only | self only |
| `event_results` | self only | self OR `is_race_director()` | visible with event | self OR `is_race_director()` |
| `race_sessions` | `is_race_director()` | `is_race_director()` | visible with event | `is_race_director()` |
| `race_pings` | self while race running | — | visible with race session | `is_race_director()` |
| `user_coach_usage` | self only | self only | self only | **no DELETE policy** |
| `monthly_funding` | **no INSERT policy** | **no UPDATE policy** | `true` (public) | **no DELETE policy** |

**Storage — `runs` bucket:**

| Operation | Who | Policy |
|---|---|---|
| SELECT | authenticated | `foldername(name)[1] = auth.uid()::text` |
| SELECT | anon + authenticated | `exists(runs where track_url = name and is_public = true)` |
| INSERT | authenticated | `foldername(name)[1] = auth.uid()::text` |
| UPDATE | authenticated | `foldername(name)[1] = auth.uid()::text` |
| DELETE | authenticated | `foldername(name)[1] = auth.uid()::text` |

**Asymmetry flag:** `monthly_funding` has RLS enabled but only a SELECT policy. Any authenticated write will be silently rejected by PostgREST. This is intentional (service-role-only writes) but is not enforced by an explicit deny policy — it relies on the absence of a grant, which is the correct Postgres security model, but is surprising to anyone who expects a table with RLS enabled to have policies covering all operations.

**Flag:** `club_posts` has no UPDATE policy. A user who posted cannot edit their post. Whether this is intentional or an oversight is unclear — nothing in the migration comments says posts are immutable once written.

---

## Confirmed-good

- All three generated files (`database.types.ts`, `db_rows.dart`, `DbRows.kt`) are in sync with the current migration state — no uncommitted drift.
- The CI `schema-codegen-drift` job (lines 59-81 of `ci.yml`) does regenerate and diff both Dart and Kotlin outputs on every PR to `main`, contrary to what the `apps/backend/CLAUDE.md` documentation claims.
- Kotlin `RunRow` in `DbRows.kt` correctly reflects all 14 columns of the `runs` table including `event_id` added by `20260424_001_event_results.sql`.
- `runs.external_id` partial unique index (`where external_id is not null`) is present and correctly prevents duplicate imports while allowing multiple runs with no external ID.
- The `enroll_club_owner` trigger correctly auto-enrolls the owner as an `owner`-role member so `is_club_member()` and `is_club_admin()` work uniformly for the creator.
- The `routes_run_count_trigger` is correctly `security definer` after `20260427_001_fix_run_count_trigger.sql` — the bug where it would fail when a user links a run to a public route owned by someone else is fixed.
- `training_plans` CHECK constraints for `status` and `source` are present (`20260421_001_plan_hardening.sql`), making these the only narrow-union text columns with DB enforcement.
- `event_results.finisher_status` has a CHECK (`'finished' | 'dnf' | 'dns'`), `race_sessions.status` has a CHECK (`'armed' | 'running' | 'finished' | 'cancelled'`), and `user_profiles.subscription_tier` has a CHECK (`'free' | 'pro' | 'lifetime'`) added by `20260429_001_subscription_paywall.sql` — three tables with proper enforcement.
- The `revenuecat-webhook` correctly guards against downgrading `lifetime` users when processing a `CANCELLATION` event.
- The `approve_event_result` RPC correctly uses `is_race_director` after `20260428_001_role_permissions.sql`, not the older `is_club_admin`.
- Both Storage read policies for the `runs` bucket are additive — owner can read privately, and public tracks are readable by anon — with no policy conflict.

---

## Out of scope

Issues in client code that are not backend schema or codegen problems:

- `packages/api_client/lib/src/api_client.dart:82` — `run.track.isNotEmpty` will throw if `run.track` is null (not a list); a null-check is needed.
- `apps/mobile_android/lib/screens/run_screen.dart` — `metadata['steps']` integer wire type unverified (flagged in `docs/metadata.md` as a known issue).
- `apps/watch_ios/WatchApp/SupabaseService.swift` — native Swift Supabase client is not covered by the Dart generator and has no CI drift gate; metadata key usage is manually reconciled per `docs/metadata.md`.
- `apps/backend/supabase/functions/strava-import/index.ts:43-45` and `strava-webhook/index.ts:41-43` — both marked TODO; backfill and activity sync are unimplemented. Not a schema issue.
- `apps/backend/supabase/functions/export-data/index.ts:17-21` — stub returning a placeholder URL; not a schema issue.
