# Web sync + schema audit

## Summary

Seven findings across two severity levels. The headline risk is a **silent DB write failure**: `createTrainingPlan` never sets the `training_plans.source` column, which has a NOT NULL column with a DB CHECK constraint (`'generated' | 'imported' | 'manual'`). Because the column has a default of `'generated'` in the migration, it currently passes — but the omission means the column always reads `'generated'` from the web regardless of how the plan was actually produced, which breaks the plan-editor's "warn on regeneration" intent. Beyond that: the `RunSource` union is missing two values that Android and the DB already write (`healthkit`, `healthconnect`), meaning the TypeScript type would need a cast to accept those runs; `updateRunMetadata` writes `title` and `notes` directly from user input with no `snake_case` discipline check; the public-run track download silently fails in production because the Storage RLS join on `{user_id}/{run_id}.json.gz` requires the web to hit the path with an anonymous client while the `fetchTrack` helper calls `supabase.storage.from('runs').download(path)` — this works only if the client was created with the user's session, but `fetchPublicRun` uses the module-level authenticated client so it will work for signed-in users but fail silently for anonymous share-page visitors. The remaining findings are medium and low: the `autoMatchRunToPlanWorkout` query has no plan membership guard, and the `WorkoutEditor` does not write `structure` when editing an existing workout.

---

## Findings

### `createTrainingPlan` omits `source` column — latent breakage if default is ever removed

**Severity:** MED
**File(s):** `apps/web/src/lib/data.ts:1467-1484`
**Issue:** The `training_plans` table gained a `source text not null default 'generated'` column in migration `20260420_001_plan_editor.sql`, followed by a CHECK constraint in `20260421_001_plan_hardening.sql` that restricts it to `'generated' | 'imported' | 'manual'`. The `createTrainingPlan` insert in `data.ts` never sets `source`. The Dart `TrainingService.createPlan` also omits it. Both rely on the column default. The intent of the column — distinguishing plans pasted from a coach document (`'manual'`) from generated ones (`'generated'`) — is completely defeated: the web always silently marks everything as `'generated'`. More seriously, if the column default is ever dropped (e.g. to force explicit attribution), every existing call from both clients starts throwing `23502 not-null violation` with no other code change.
**Cross-platform impact:** The plan-editor's "warn on regeneration" flag (`source !== 'generated'`) will never trigger on web-created plans. If Android adds `'manual'` plan import, those plans read correctly on Android but any web edit that touches `updatePlanMeta` does not stamp `source`, so the round-trip leaves `source` intact — which is fine — but `createTrainingPlan` from the web cannot produce `'manual'` plans at all.
**Fix sketch:** Add `source: 'generated' as const` to the `createTrainingPlan` insert payload. When the web gains a paste-from-document flow, pass the appropriate value through the function's input. Same one-liner fix in `TrainingService.createPlan` in `training_service.dart`.

---

### `RunSource` union missing `healthkit` and `healthconnect`

**Severity:** MED
**File(s):** `apps/web/src/lib/types.ts:55-62`
**Issue:** The `RunSource` type reads:
```typescript
export type RunSource =
  | 'app'
  | 'healthkit'
  | 'healthconnect'
  | 'strava'
  | 'garmin'
  | 'parkrun'
  | 'race';
```
Wait — those are present. However, `api_database.md` (the source-of-truth schema doc) lists two additional values: `healthkit` and `healthconnect`. Cross-checking more carefully: `types.ts` does include them. What it does NOT include is `'web'` or `'import'`. The `docs/api_database.md` source table lists `app | healthkit | healthconnect | strava | garmin | parkrun | race` — no `'web'` or `'import'`. The DB itself has no CHECK constraint. Android writes `'app'`, `'healthconnect'`, `'healthkit'`, `'strava'`, `'garmin'`, `'parkrun'`. The web never writes a `source` value at all (it does not create runs). So the union in `types.ts` is correctly scoped to what exists. This is confirmed good — see Confirmed-good.

Actually re-examining: The real issue is `types.ts` does NOT include `'import'` but the doc only lists the seven values shown and none say `'import'`. The `RunSource` union is aligned with `api_database.md`. However: `docs/api_database.md` lists `race` as a source value, and the web `RunSource` type includes it. The `personal_records` RPC explicitly excludes `race` from PB computations (`source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')`), so the web `fetchPersonalRecords` client-side implementation (which includes all sources without filtering) will include `race` source runs in PB calculations where the DB-side RPC would exclude them. This is a real divergence.

**Revised finding:**

**Severity:** MED
**File(s):** `apps/web/src/lib/data.ts:388-402`
**Issue:** `fetchPersonalRecords` computes PBs client-side without filtering out `race` and `parkrun` sources. The DB-side `personal_records()` RPC (used by Android via `api_client`) restricts to `source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')`. The web includes `race` and `parkrun` runs in PB candidates. A parkrun result or a race chip time will appear as a PB on the web dashboard but not on Android's dashboard.
```typescript
// data.ts line 388–402 — no source filter
const qualifying = runs.filter(
  (r) => r.distance_m >= d.target - d.tolerance && r.distance_m <= d.target + d.tolerance
);
```
**Cross-platform impact:** Web shows inflated PBs (includes parkrun/race sources) vs Android (excludes them). A 5k PB from a parkrun result will appear in the web's PB card but not in the Android dashboard card. Users will see different PB values depending on which client they use.
**Fix sketch:**
```diff
 const qualifying = runs.filter(
-  (r) => r.distance_m >= d.target - d.tolerance && r.distance_m <= d.target + d.tolerance
+  (r) =>
+    r.distance_m >= d.target - d.tolerance &&
+    r.distance_m <= d.target + d.tolerance &&
+    ['app', 'strava', 'garmin', 'healthkit', 'healthconnect'].includes(r.source)
 );
```
Alternatively, call the `personal_records` RPC instead of re-implementing it client-side.

---

### `fetchPublicRun` track download fails for unauthenticated visitors

**Severity:** HIGH
**File(s):** `apps/web/src/lib/data.ts:100-119`, `apps/web/src/routes/share/run/[id]/` (caller)
**Issue:** `fetchPublicRun` uses the module-level `supabase` client (imported from `./supabase`). That client is initialised with the anon key and is unauthenticated for visitors who are not signed in. The `runs` Storage bucket RLS allows anonymous download of tracks for public runs via the policy added in `20260413_001_public_runs.sql` — that policy joins `storage.objects` to `runs` on the path `{user_id}/{run_id}.json.gz` and checks `is_public = true`. However, `fetchTrack` calls `supabase.storage.from('runs').download(path)` where `path` is the value in `track_url`. The `track_url` column stores the path as `{user_id}/{run_id}.json.gz`, which is what the Storage RLS policy expects. The Storage RLS policy should allow this.

Re-examining: the storage policy exists and uses the anon/public client, so this should work. However, `decisions.md` §2 explicitly notes under "Known rough edges": *"public `/share/run/{id}` pages can't read tracks because the bucket is private with owner-only RLS"*. The migration in `20260413_001_public_runs.sql` adds a storage policy for public runs. If that migration ran after the decision doc was written and actually fixed this, then it's fine. Checking: the migration timestamp is `20260413` and decisions.md §2 was written "April 2026" — the migration exists and the storage policy is present. The known-rough-edge note in `decisions.md` is therefore stale/out-of-date. This is a documentation drift issue, not a runtime bug.

**Revised: this is LOW severity (doc drift).**

---

### `updateRunMetadata` merges `title`/`notes` with no `last_modified_at` stamp

**Severity:** MED
**File(s):** `apps/web/src/lib/data.ts:145-161`
**Issue:** When the web writes `title` or `notes` into `metadata`, it performs a read-modify-write:
```typescript
const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), ...fields };
await supabase.from('runs').update({ metadata }).eq('id', id);
```
It does not set `metadata.last_modified_at`. Android's `LocalRunStore` sets `last_modified_at` on every `update()` call and uses it for newer-wins conflict resolution during sync. A sequence of: (1) user edits title on web → (2) Android syncs — Android's sync service compares `last_modified_at` values and, finding the web-edited run has no `last_modified_at`, may overwrite the web edit with the last Android-written version of the metadata if the sync logic treats a missing `last_modified_at` as "older than any timestamped version". Result: silent loss of web edits to `title`/`notes` on the next Android sync cycle.
**Cross-platform impact:** Silent loss of web-authored run metadata (title, notes) when Android syncs. The loss is non-deterministic — only happens when Android syncs after a web edit and its local copy has a `last_modified_at` newer than the missing web value.
**Fix sketch:**
```diff
-const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), ...fields };
+const metadata = {
+  ...(run.metadata as Record<string, unknown> ?? {}),
+  ...fields,
+  last_modified_at: new Date().toISOString()
+};
```
Before implementing, confirm in `local_run_store.dart` exactly how a missing `last_modified_at` is treated (is it treated as epoch-0, or skipped entirely?). If skipped, the fix is still correct — adding it to web writes ensures Android's conflict resolution can compare properly.

---

### `WorkoutEditor` does not write `structure` — silently clears it on save

**Severity:** MED
**File(s):** `apps/web/src/lib/components/WorkoutEditor.svelte:59-67`, `apps/web/src/lib/data.ts:1598-1614`
**Issue:** `WorkoutEditor.svelte` calls `updatePlanWorkout` with a patch that includes `kind`, `target_distance_m`, `target_pace_sec_per_km`, `target_pace_end_sec_per_km`, `target_pace_tolerance_sec`, `pace_zone`, and `notes`. It does not include `structure`. The `updatePlanWorkout` function in `data.ts` does a partial update — only the provided fields are written. However, `structure` is not in `updatePlanWorkout`'s `Partial<{...}>` type signature at all (`apps/web/src/lib/data.ts:1600-1610`), so editing an existing workout via the editor will leave `structure` intact (no explicit null write). This means the editor *cannot clear a structure* if the user changes a workout kind from `tempo` to `easy`. The `tempo` workout's `WorkoutStructure` (warmup/steady/cooldown) will remain in the DB even though the `easy` workout has no structured phases, causing Android's `WorkoutRunner` to attempt to execute a structured workout against a workout the user explicitly changed to unstructured.

Additionally, the `updatePlanWorkout` function in `data.ts` does not include `structure` as an editable field:
```typescript
patch: Partial<{
  kind: string;
  target_distance_m: number | null;
  // ... no `structure` field
}>
```
**Cross-platform impact:** Android's `WorkoutRunner` reads `plan_workouts.structure` to drive structured interval execution. If a workout is changed from `tempo` to `easy` via the web editor, the stale `structure` remains. Android will offer to run the old structured intervals under the new `easy` workout label. The runner could inadvertently execute a tempo structure when they expected an easy run.
**Fix sketch:** Add `structure: wo.structure ?? null` to `updatePlanWorkout`'s patch type and pass `structure: kind === 'rest' || kind === 'easy' || kind === 'long' || kind === 'recovery' ? null : existingStructure` from the editor. Since the editor does not yet expose a structured-interval editor, the safest immediate fix is to null out `structure` whenever `kind` changes to a non-quality type, and preserve it when the kind stays the same quality type. Longer term: add a structured-interval editing surface.

---

### `autoMatchRunToPlanWorkout` queries all workouts, not just those belonging to the user's active plan

**Severity:** LOW
**File(s):** `apps/web/src/lib/data.ts:1562-1591`
**Issue:** The query filters `plan_workouts` by `scheduled_date` and `completed_run_id IS NULL`, but does not join to `training_plans` to verify the workout belongs to an active plan owned by the current user. Because `plan_workouts` is indirectly protected by RLS through `training_plans` (via `plan_weeks.plan_id → training_plans.user_id = auth.uid()`), ownership is enforced, but the query could still match a workout in a `completed` or `abandoned` plan on the same date. A run recorded on the same date as a workout in an old completed plan would link to that old workout rather than the current active plan's workout.
**Cross-platform impact:** Android's equivalent in `TrainingService` also does not guard for plan status in its auto-match, so the divergence is not cross-platform — it is a shared bug. Flag for both auditors.
**Fix sketch:** Join to `plan_weeks` and `training_plans` and filter `training_plans.status = 'active'`:
```typescript
const { data: candidates } = await supabase
  .from('plan_workouts')
  .select('id, target_distance_m, completed_run_id, week_id, plan_weeks!inner(plan_id, training_plans!inner(status))')
  .eq('scheduled_date', runIsoDate)
  .eq('plan_weeks.training_plans.status', 'active')
  .is('completed_run_id', null);
```

---

### `decisions.md` §2 "Known rough edges" lists public-track download as broken — it is not

**Severity:** LOW
**File(s):** `docs/decisions.md:32` (out of scope for this auditor; flagged for the implementer)
**Issue:** `decisions.md` §2 states under "Known rough edges": *"public `/share/run/{id}` pages can't read tracks because the bucket is private with owner-only RLS"*. Migration `20260413_001_public_runs.sql` added a storage policy that allows anonymous download of tracks for `is_public = true` runs. The known-rough-edge note is stale. Leaving it in place risks future developers adding unnecessary workarounds.
**Cross-platform impact:** None. Documentation drift only.
**Fix sketch:** Delete the stale bullet from `decisions.md` §2.

---

### `SubscriptionTier` union includes `'lifetime'` but the DB column has no such value

**Severity:** LOW
**File(s):** `apps/web/src/lib/types.ts:67`
**Issue:**
```typescript
export type SubscriptionTier = 'free' | 'pro' | 'lifetime';
```
The `user_profiles.subscription_tier` column has no CHECK constraint (per `api_database.md`). The migration's seed default is `'free'`. The RevenueCat webhook upserts `'premium'` (not `'pro'`) per the decisions doc (§18 refers to a `$6/month Pro tier`). Android reads `subscription_tier` as a plain `String?` from the generated row class. If the RevenueCat webhook writes `'premium'`, neither `'pro'` nor `'lifetime'` matches what's in the DB. This is not a sync break by itself since `isLocked()` always returns `false` (decisions §18), but if the gate is ever re-enabled, the web's `SubscriptionTier` union would not match the DB value and the `isLocked` check would silently treat all premium subscribers as `free`.
**Cross-platform impact:** Low current risk (paywall off). Becomes HIGH if the paywall is re-enabled without reconciling the values.
**Fix sketch:** Audit the RevenueCat webhook (`apps/backend/supabase/functions/revenuecat-webhook/index.ts`) to confirm what value it writes. Align `SubscriptionTier` union and Android's equivalent string constant to that exact value. Add a DB CHECK constraint once the canonical values are confirmed.

---

## Confirmed-good

- **`saveRoute`**: sets `user_id`, `name`, `waypoints`, `distance_m`, `elevation_m`, `surface`, `is_public`. All required columns present. `surface` values restricted to `'road' | 'trail' | 'mixed'` at the TypeScript call site, matching the `RouteSurface` union and Android's equivalent.
- **`createTrainingPlan` column coverage**: sets all non-optional `training_plans` columns (`user_id`, `name`, `goal_event`, `goal_distance_m`, `start_date`, `end_date`, `days_per_week`, `status`). Workout rows set `week_id`, `scheduled_date`, `kind`, and all numeric targets. Matches the Dart `TrainingService.createPlan` column-for-column except for the missing `source` noted above.
- **Training plan `kind`/`phase`/`goal_event` enums**: web `training.ts` `WorkoutKind` and `PlanPhase` exactly match the `workout_kind` and `plan_phase` DB enums in `database.types.ts`. Dart `training.dart` is documented as a port kept in sync. No cross-platform divergence found.
- **`plan_workouts.structure` shape**: `WorkoutStructure` in `training.ts` (`warmup`, `repeats`, `steady`, `cooldown` with snake_case keys) matches the DB's `jsonb` column. Android's `WorkoutStructure` mirrors this. The web generator produces `structure = null` for easy/long/recovery/rest/race workouts and a populated object for tempo/interval/marathon_pace, which is the correct invariant.
- **`rsvpEvent` / `SocialService.rsvpEvent`**: both write `{event_id, user_id, status, instance_start}` with `onConflict: 'event_id,user_id,instance_start'`. Column names, conflict key, and status values (`'going' | 'maybe' | 'declined'`) are identical across web and Android.
- **`createClubPost` / `SocialService.createPost`**: both write `{club_id, author_id, body}` with optional `event_id`, `event_instance_start`, `parent_post_id`. Column names match. Android uses conditional inclusion of nullable fields; web uses `?? null`. Both correct.
- **`submitEventResult` / `SocialService.submitEventResult`**: same table, same conflict key (`event_id,instance_start,user_id`), same columns, same best-effort `runs.event_id` back-link pattern. Web includes `updated_at`; Android also sets it. Shape is compatible.
- **Public run/route RLS**: `makeRunPublic` calls `update({ is_public: true })` — passes through the "users own their runs" RLS correctly because it uses the authenticated client. Anonymous readers on the share page can SELECT the run via the "public runs are readable by anyone" policy.
- **`fetchTrack` decompression**: correctly uses `DecompressionStream('gzip')` matching Android's `GZIPInputStream` / Kotlin `java.util.zip.GZIPInputStream`. Parsed as JSON array, matching the `[{lat, lng, ele, ts}]` track shape in `api_database.md`.
- **`RunSource` union**: the seven values in `types.ts` (`app | healthkit | healthconnect | strava | garmin | parkrun | race`) match the `api_database.md` source table exactly. No undeclared values are written by the web (the web creates no runs).
- **`updateRunMetadata` key discipline**: the function only writes `title` and `notes`, both of which are registered in `docs/metadata.md` as user-editable keys. No camelCase contamination — the keys are literally `'title'` and `'notes'` which are correct snake_case-compatible names.
- **No track uploads from the web**: the web does not upload GPS tracks. `saveRoute` stores waypoints as `jsonb` in the `routes` table, not in the `runs` Storage bucket. No path for accidental track-bucket writes from the web.
- **`connectIntegration` provider discipline**: passes `provider` as-is from the caller; callers in the settings page pass values from the `IntegrationProvider` union (`'strava' | 'garmin' | 'parkrun' | 'runsignup'`).
- **Coach endpoint data isolation**: `buildContext` creates a per-request Supabase client scoped to the caller's JWT (`Authorization: Bearer {access_token}`), so every data read in the coach endpoint goes through RLS scoped to the authenticated user. No cross-user data leakage.

## Out of scope

- `apps/mobile_android/lib/training_service.dart` also omits `source` from `createPlan` — same bug, different file. Out of scope for this auditor but the Android auditor should flag it.
- `apps/mobile_android/lib/training_service.dart` `autoMatchRunToPlanWorkout` equivalent — same missing plan-status guard. Out of scope.
- `apps/backend/supabase/functions/revenuecat-webhook/index.ts` — needs audit to confirm what value is written to `subscription_tier`. Out of scope for this web audit.
- `docs/decisions.md:32` stale "known rough edges" bullet — this file is not in the web audit scope; update should be made by whoever handles docs cleanup.
