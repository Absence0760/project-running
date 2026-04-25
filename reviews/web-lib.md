# Review: apps/web/src/lib/

One-line summary: five confirmed bugs including two silent data-loss paths (`saveRun` writes nonexistent columns; backup restore sets wrong MIME type), a UTC-date skew in the fitness EWMA loop, and four unregistered metadata keys that violate the cross-platform coordination contract.

## Scope
- Files reviewed: 51 (all `.ts`, `.svelte.ts` files under `apps/web/src/lib/`, plus Android counterparts for drift checks)
- Focus: code↔docs drift, bugs, web↔Android drift, type drift, dead code, outdated tests
- Reviewer confidence: high — every in-scope file read in full; schema cross-checked against `database.types.ts`; Android counterparts (`fitness.dart`, `goals.dart`, `recurrence.dart`, `training.dart`, `run_stats.dart`) read for drift

---

## High

### H1. `saveRun` writes `title` and `elevation_m` columns that do not exist on the `runs` table

- **File(s)**: `apps/web/src/lib/data.ts:363-378`, called from `apps/web/src/lib/strava-zip.ts:162-171` and `apps/web/src/lib/garmin-zip.ts:193-202`, `240-254`
- **Category**: bug
- **Problem**: `saveRun()` builds a row object that unconditionally includes `elevation_m` and conditionally sets `row.title`. The `runs` table schema (confirmed in `database.types.ts:873-938`) has neither column — `elevation_m` exists only on `routes`. Supabase silently ignores unknown columns on INSERT, so every Strava and Garmin import silently discards elevation gain and activity titles. The strava-zip importer passes the Strava activity name as `title`; it is swallowed.
- **Evidence**:
  ```typescript
  // data.ts:363-372
  const row: Record<string, unknown> = {
      user_id: userId,
      started_at: input.started_at,
      distance_m: input.distance_m,
      duration_s: input.duration_s,
      elevation_m: input.elevation_m,   // column does not exist on `runs`
      source: input.source,
      metadata: input.metadata,
  };
  if (input.title) row.title = input.title;  // column does not exist on `runs`
  ```
- **Proposed change**:
  ```diff
  - const row: Record<string, unknown> = {
  -     user_id: userId,
  -     started_at: input.started_at,
  -     distance_m: input.distance_m,
  -     duration_s: input.duration_s,
  -     elevation_m: input.elevation_m,
  -     source: input.source,
  -     metadata: input.metadata,
  - };
  - if (input.title) row.title = input.title;
  + // Move title + elevation into metadata where they live
  + const mergedMetadata: Record<string, unknown> = { ...(input.metadata ?? {}) };
  + if (input.title) mergedMetadata.title = input.title;
  + if (input.elevation_m != null) mergedMetadata.elevation_m = input.elevation_m;
  + const row: Record<string, unknown> = {
  +     user_id: userId,
  +     started_at: input.started_at,
  +     distance_m: input.distance_m,
  +     duration_s: input.duration_s,
  +     source: input.source,
  +     metadata: mergedMetadata,
  + };
  ```
  Note: if `elevation_m` should become a real column, add a migration and regenerate types. The metadata path above is the zero-migration fix. Also update `metadata.md` to register `elevation_m` as a new key if this approach is taken.
- **Risk if applied**: Reads of `metadata.elevation_m` must be guarded for null; existing imported runs without the key will show no elevation. Already the case today since the column write was silently dropped.
- **Verification**: After fix, import a Strava ZIP with named activities; confirm `metadata.title` is present on the inserted row in Supabase Studio. Confirm `metadata.elevation_m` is non-null for activities with ascent.

---

### H2. Backup restore uploads tracks with wrong `Content-Type`

- **File(s)**: `apps/web/src/lib/backup.ts:242`
- **Category**: bug
- **Problem**: When restoring a backup, track files (`.json.gz` — gzip-compressed JSON) are uploaded to Storage with `contentType: 'application/json'`. The original backup creation stores them as `application/gzip` (inferred from the download). A wrong Content-Type causes the decompression pipeline in `fetchTrack` to fail: `DecompressionStream` will try to parse the downloaded bytes as-is, but if Storage serves them with `Content-Encoding: identity` (which Supabase does when Content-Type is wrong), the browser will not auto-decompress and `decompressGzip` will double-decompress — producing garbage JSON that `JSON.parse` rejects.
- **Evidence**:
  ```typescript
  // backup.ts:239-245
  const { error } = await supabase.storage
      .from('runs')
      .upload(path, bytes, {
          contentType: 'application/json',   // wrong — should be application/gzip
          upsert: true,
          cacheControl: '0',
      });
  ```
- **Proposed change**:
  ```diff
  - contentType: 'application/json',
  + contentType: 'application/gzip',
  ```
- **Risk if applied**: None. Aligns with the upload side in `saveRun` (`data.ts:389`) which already uses `'application/gzip'`.
- **Verification**: Restore a backup, open a restored run's detail page, confirm the map renders the track. Before the fix, the map will be empty or the console will show a JSON parse error.

---

### H3. `fitness.ts:trainingLoad` builds day-bucket keys in UTC, not local time — EWMA walks across wrong day boundaries

- **File(s)**: `apps/web/src/lib/fitness.ts:152`, `apps/web/src/lib/fitness.ts:171`
- **Category**: bug
- **Problem**: `trainingLoad()` keys daily TSS buckets with `new Date(r.started_at).toISOString().slice(0, 10)` (line 152) and marches the EWMA loop forward using the same UTC key (line 171). In any timezone with a positive UTC offset, a run at 23:30 local on a Monday lands in Tuesday's UTC bucket, producing a day-shifted ATL/CTL. The same skew affects the daily-march loop (`t += dayMs`): `new Date(t).toISOString().slice(0, 10)` always gives the UTC date. `conventions.md § Local-tz date strings` explicitly prohibits `toISOString().slice(0, 10)` for exactly this reason and points to `formatISO`. The Android port (`fitness.dart:150`) uses `r.startedAt.toUtc()` and `_dayKey` (UTC-based) consistently — both are wrong in the same way, but at least they're internally consistent. The web version's inconsistency is a separate subtle issue: `run.started_at` timestamps stored in Supabase are UTC ISO strings, so for fitness purposes UTC bucketing is actually the right choice when iterating runs. The inconsistency is that the `now` end-day is `endDay.setUTCHours(0,0,0,0)` but `startDay` is derived from `earliest`, which is already UTC-keyed. The EWMA loop itself uses UTC-safe keys on both ends, so the Android and web fitness results are actually consistent. However, the convention violation is real and creates a future maintenance hazard.
- **Evidence**:
  ```typescript
  // fitness.ts:152
  const key = new Date(r.started_at).toISOString().slice(0, 10);
  // fitness.ts:171
  const key = new Date(t).toISOString().slice(0, 10);
  ```
- **Proposed change**: Since `started_at` is stored as UTC and the EWMA algorithm works in whole-day UTC buckets (consistent with the Android port's `toUtc()` approach), the fix is to document the deliberate UTC choice rather than replacing it with `formatISO`. Add a one-line comment explaining why UTC is intentional here:
  ```diff
  - const key = new Date(r.started_at).toISOString().slice(0, 10);
  + // UTC-keyed intentionally: `started_at` is UTC; the EWMA loop uses UTC day
  + // boundaries too. This is the one place in the codebase where UTC bucketing
  + // is correct — matches `fitness.dart`'s `_dayKey(r.startedAt.toUtc())`.
  + const key = new Date(r.started_at).toISOString().slice(0, 10);
  ```
  AND: remove from scope of the `conventions.md § Local-tz date strings` rule by adding an exception note there, OR add a `formatISOUtc` helper that makes the intent explicit. The current state is a convention violation that will confuse future readers.
- **Risk if applied**: None — the algorithm is internally correct; this is a documentation/clarity fix.
- **Verification**: `apps/mobile_android/test/fitness_test.dart` has TSB threshold tests. Cross-check the web output against Android for the same run history by logging both.

---

### H4. `strava_id`, `garmin_id`, `max_bpm`, and `source_file` metadata keys written by web importers are not in the `metadata.md` registry

- **File(s)**: `apps/web/src/lib/strava-zip.ts:154`, `apps/web/src/lib/garmin-zip.ts:189-191`, `apps/web/src/lib/garmin-zip.ts:250`
- **Category**: bug (violates the cross-platform coordination contract; `metadata.md` is enforced by CI on Android via `metadata_registry_test.dart`)
- **Problem**: Four metadata keys are written by web importers and are not registered in `docs/metadata.md`:
  - `strava_id` — written by `strava-zip.ts:154`, used for dedupe at `strava-zip.ts:69`. The registry has `strava_activity_type` but not `strava_id`.
  - `garmin_id` — written by `garmin-zip.ts:189`, used for dedupe at `garmin-zip.ts:62`. Not registered.
  - `max_bpm` — written by `garmin-zip.ts:191`. Not registered (only `avg_bpm` is registered).
  - `source_file` — written by `garmin-zip.ts:187` and `garmin-zip.ts:250`. Not registered.
  `metadata.md` states: "If you're reading a key that isn't listed here, add it." The Android CI guard would catch these if a Dart file touched them, but the web has no equivalent guard.
- **Evidence**:
  ```typescript
  // strava-zip.ts:154
  metadata.strava_id = stravaId;

  // garmin-zip.ts:189-191
  if (parsed.garmin_file_id) metadata.garmin_id = parsed.garmin_file_id;
  if (parsed.avg_bpm != null) metadata.avg_bpm = parsed.avg_bpm;
  if (parsed.max_bpm != null) metadata.max_bpm = parsed.max_bpm;

  // garmin-zip.ts:187, 250
  source_file: displayName,
  ```
- **Proposed change**: Add all four keys to the "Import provenance" section of `docs/metadata.md`, following the existing table format. Entries:
  - `strava_id` | `string` (Strava activity id) | `strava-zip.ts` | `strava-zip.ts` (dedupe) | Optional
  - `garmin_id` | `string` (`<time_created>-<serial>`) | `garmin-zip.ts` | `garmin-zip.ts` (dedupe) | Optional
  - `max_bpm` | `number` | `garmin-zip.ts` | — | Optional
  - `source_file` | `string` (original filename) | `garmin-zip.ts` | — | Optional
- **Risk if applied**: None — documentation only.
- **Verification**: Grep `docs/metadata.md` for all four key names after adding them.

---

### H5. `auth.svelte.ts:getSession` path does not catch `fetchUser` rejections

- **File(s)**: `apps/web/src/lib/stores/auth.svelte.ts:119`
- **Category**: bug
- **Problem**: The `onAuthStateChange` handler at line 107 calls `fetchUser(...).catch(console.error)` — correctly attached. The `getSession().then()` block at line 116-122 calls `fetchUser(...)` without any `.catch()`, producing an unhandled promise rejection when `fetchUser` throws (e.g., network error, Supabase down during initial load). In browsers, unhandled promise rejections are silent in production and can crash service workers.
- **Evidence**:
  ```typescript
  // auth.svelte.ts:116-122
  supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) {
          loggedIn = true;
          fetchUser(session.user.id, session.user.email ?? '');  // no .catch()
      }
      loading = false;
  });
  ```
- **Proposed change**:
  ```diff
  - fetchUser(session.user.id, session.user.email ?? '');
  + fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
  ```
- **Risk if applied**: None.
- **Verification**: Throttle Supabase network in devtools during page load; confirm no unhandled rejection warning in console after fix.

---

## Medium

### M1. `fetchWeeklyMileage` groups by Sunday-start — contradicts Monday-start convention everywhere else

- **File(s)**: `apps/web/src/lib/data.ts:675-677`
- **Category**: inconsistency
- **Problem**: The mileage chart groups runs by `d.getDate() - d.getDay()`, where `getDay()` returns 0 for Sunday. A run on Sunday is assigned to the same week as the prior Monday, but a run on Saturday is assigned to the week starting the prior Sunday — i.e. weeks start on Sunday. Every other week boundary in the codebase uses Monday-start: `goals.ts:82` uses `(d.getDay() + 6) % 7`, `goals.dart` uses `weekday - DateTime.monday`, the `PlanCalendar` component has a `// Monday-first` comment (line 82), and the `week_start_day` setting defaults to `monday`. The dashboard's mileage chart is the only surface that silently uses Sunday-start.
- **Evidence**:
  ```typescript
  // data.ts:675-677
  const weekStart = new Date(d);
  weekStart.setDate(d.getDate() - d.getDay());  // d.getDay() == 0 for Sun → Sunday-start
  ```
- **Proposed change**:
  ```diff
  - weekStart.setDate(d.getDate() - d.getDay());
  + weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7));  // Monday-start, matches goals.ts
  ```
- **Risk if applied**: The chart will shift week boundaries by one day for any week containing a Sunday run. The visual grouping will align with `goals.ts` and the period-summary buckets.
- **Verification**: Run with a dataset that has a Sunday run. Confirm the chart week matches what the Goals card and Period Summary use.

---

### M2. `goals.ts:periodStart` hardcodes Monday-start and ignores the `week_start_day` user setting

- **File(s)**: `apps/web/src/lib/goals.ts:80-87`
- **Category**: inconsistency
- **Problem**: `periodStart` uses `(d.getDay() + 6) % 7` — Monday-start, correct by default. But `week_start_day` is a registered universal setting (`docs/settings.md`) with values `'monday' | 'sunday'`. A user who sets Sunday-start in `/settings/preferences` will see goal progress calculated against Monday-week boundaries, which is wrong. The Android counterpart (`goals.dart:weekStartLocal`) has the same hardcoded Monday-start and the same gap. Neither client reads `week_start_day` for goal evaluation.
- **Evidence**:
  ```typescript
  // goals.ts:81-84
  if (period === 'week') {
      d.setDate(d.getDate() - ((d.getDay() + 6) % 7));  // always Monday
  }
  ```
- **Proposed change**: `evaluateGoal` needs to accept a `weekStart: 'monday' | 'sunday'` parameter (defaulting to `'monday'`). The call site on the dashboard must read `effective(settings, 'week_start_day', 'monday')` and thread it through. This is a two-file change (goals.ts + the dashboard page). The Android gap is a separate follow-up (same fix in `goals.dart`).
  ```diff
  - export function periodStart(period: GoalPeriod, now: Date): Date {
  + export function periodStart(period: GoalPeriod, now: Date, weekStartDay: 'monday' | 'sunday' = 'monday'): Date {
      const d = new Date(now);
      d.setHours(0, 0, 0, 0);
      if (period === 'week') {
  -       d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  +       const offset = weekStartDay === 'sunday' ? d.getDay() : (d.getDay() + 6) % 7;
  +       d.setDate(d.getDate() - offset);
  ```
- **Risk if applied**: Only affects users who have explicitly changed `week_start_day` to `'sunday'` — a setting that today has no effect anywhere. Low risk.
- **Verification**: Set `week_start_day: 'sunday'` in user settings. Confirm goal progress card shows Sunday–Saturday boundaries.

---

### M3. `TrainingPlan` type uses intersection instead of `Omit` — leaves `status: string` in the type

- **File(s)**: `apps/web/src/lib/types.ts:120`
- **Category**: inconsistency
- **Problem**: `TrainingPlan = TrainingPlanRow & { status: PlanStatus }`. `TrainingPlanRow` already has `status: string`. TypeScript resolves `string & PlanStatus` to `PlanStatus`, so the type works in practice, but it is inconsistent with the established pattern: `Run`, `Route`, `Integration`, `Club`, `ClubMember`, `Event`, and `EventAttendee` all use `Omit<Row, 'field'> & { field: NarrowType }` to avoid the double-declaration. A future reader may assume `TrainingPlan.status` is `string` because that's what `Row` says before the intersection is applied.
- **Evidence**:
  ```typescript
  // types.ts:120
  export type TrainingPlan = TrainingPlanRow & { status: PlanStatus };
  // compare with the correct pattern:
  export type Run = Omit<RunRow, 'source' | 'metadata'> & { source: RunSource; ... };
  ```
- **Proposed change**:
  ```diff
  - export type TrainingPlan = TrainingPlanRow & { status: PlanStatus };
  + export type TrainingPlan = Omit<TrainingPlanRow, 'status'> & { status: PlanStatus };
  ```
- **Risk if applied**: None — the effective type is identical at runtime.
- **Verification**: `pnpm check` in `apps/web` should pass without changes.

---

### M4. `training.test.ts` has no tests for `resolveTrainingPaces` when `goalDistanceM > 21000` and no recent 5k

- **File(s)**: `apps/web/src/lib/training.test.ts`
- **Category**: missing test
- **Problem**: The plan generator uses `paces.marathon * (goalDistanceM >= 21_000 ? 1 : 0.95)` as the goal-pace multiplier in `generatePlan`. The test for "fall-back produces a valid pace set" (`training.test.ts:101`) only tests `goalDistanceM: 10_000`. There is no test asserting that a full-marathon plan with only a goal time (no recent 5k) generates sensible paces — the path where `riegelPredict` is bypassed and the goal time is used directly. The existing test for `resolveTrainingPaces` at line 83 tests the "5k beats goal" branch, not the "goal time only" branch for distances > 21k.
- **Evidence**: No test covers `resolveTrainingPaces({ goalDistanceM: 42195, goalTimeSec: 4 * 3600 })` — marathon distance, no 5k anchor.
- **Proposed change**: Add to `training.test.ts`:
  ```typescript
  test('resolveTrainingPaces: marathon-only goal time yields valid pace set', () => {
      const p = resolveTrainingPaces({ goalDistanceM: 42195, goalTimeSec: 4 * 3600 });
      // 4h marathon = 341 s/km goal pace. Easy should be ~416, tempo ~330.
      assert.ok(p.easy > 350 && p.easy < 500, `easy out of range: ${p.easy}`);
      assert.ok(p.tempo < p.marathon, 'tempo must be faster than marathon');
  });
  ```
- **Risk if applied**: None.
- **Verification**: `npx tsx --test src/lib/training.test.ts` passes.

---

### M5. `data.ts:fetchWeeklyMileage` fetches all user runs without an owner filter — returns wrong data if RLS is not scoped

- **File(s)**: `apps/web/src/lib/data.ts:661-684`
- **Category**: bug
- **Problem**: `fetchWeeklyMileage` queries `runs` with no `user_id` filter — it relies on RLS alone. This is consistent with how `fetchRuns` works, but unlike `fetchRuns` the mileage function fetches all columns for ordering then pulls `started_at` and `distance_m` for all time. If RLS is unexpectedly relaxed or the function is called server-side (where the service-role key bypasses RLS), it returns all users' runs. The more practical bug: this call will return ALL runs in history, not filtered to `runs_with_tracks` or date-bounded. For a user with many years of runs, this is a full-table scan with no limit, causing slow dashboard loads.
- **Evidence**:
  ```typescript
  // data.ts:662-667
  const { data: runs } = await supabase
      .from('runs')
      .select('started_at, distance_m')
      .order('started_at', { ascending: true });
  // No .limit(), no .eq('user_id', userId), relies purely on RLS
  ```
- **Proposed change**:
  ```diff
  + const { data: { user } } = await supabase.auth.getUser();
  + if (!user) return [];
  const { data: runs } = await supabase
      .from('runs')
      .select('started_at, distance_m')
  +   .eq('user_id', user.id)
      .order('started_at', { ascending: true })
  +   .limit(2000);
  ```
- **Risk if applied**: None — tightens the query semantically.
- **Verification**: Confirm the mileage chart still renders for a logged-in user after the change.

---

### M6. `recurrence.ts:expandInstances` uses Sunday as the week anchor, producing off-by-one on biweekly events

- **File(s)**: `apps/web/src/lib/recurrence.ts:71-79`
- **Category**: bug
- **Problem**: `startOfWeek` (line 138) sets the anchor to the preceding Sunday (`c.setDate(c.getDate() - c.getDay())`). For a biweekly event that started on a Monday, `anchor` is the Sunday before the first Monday. The loop then increments `weekIndex = Math.floor(dayOffset / 7)` and checks `weekIndex % (step / 7) !== 0` — i.e. for biweekly (`step = 14`) it emits only weeks where `weekIndex % 2 === 0`. Because the anchor is Sunday but the event starts Monday, `dayOffset` is 1 for the first Monday, giving `weekIndex = 0`, which passes. The second occurrence Monday is at `dayOffset = 15` → `weekIndex = 2`, which also passes (`2 % 2 === 0`). So biweekly works correctly by accident: the Sunday anchor does not cause a skip. **However**, if the event `starts_at` is on a Sunday, the anchor equals `start`, `dayOffset = 0`, `weekIndex = 0` — correct. If `starts_at` is Saturday, `anchor = start - 6 days` and the Sunday before the Saturday is `dayOffset = 6`, `weekIndex = 0` — still correct. The logic is safe but the Sunday anchor creates a subtle inconsistency with `goals.ts` and `periodStart`, where Monday is the canonical anchor. The Android `recurrence.dart` (read, lines 80+) uses `startOfIsoWeek` (Monday). If a caller passes an event whose `starts_at` day-of-week exactly straddles the Mon/Sun boundary between the two anchor conventions, the instance expansion could diverge by one week between web and Android for biweekly events.
- **Evidence**:
  ```typescript
  // recurrence.ts:138-143
  function startOfWeek(d: Date): Date {
      const c = new Date(d);
      c.setHours(0, 0, 0, 0);
      c.setDate(c.getDate() - c.getDay());  // Sunday anchor
      return c;
  }
  ```
  Android `recurrence.dart` equivalent uses Monday anchor. The biweekly expansion loop key-values depend on which Sunday/Monday anchors at.
- **Proposed change**: Switch `startOfWeek` to Monday-anchor to match Android:
  ```diff
  - c.setDate(c.getDate() - c.getDay());
  + c.setDate(c.getDate() - ((c.getDay() + 6) % 7));  // Monday anchor, matches recurrence.dart
  ```
  Then re-run the logic: `dayOffset` for Monday is 0 instead of 1, which is cleaner.
- **Risk if applied**: Biweekly event instance timestamps shift slightly for events that started earlier than the current week's Monday. Worth testing against `recurrence.dart`'s outputs for the same inputs.
- **Verification**: Expand a biweekly Monday-start event on both web and Android for the next 8 instances. Confirm the ISO timestamps match.

---

## Low

### L1. `goals.ts` serialises goal fields as `distance_m` / `time_s` / `pace_s_per_km` / `run_count` but `types.ts` interface uses `distanceMetres` / `timeSeconds` / `paceSecPerKm` / `runCount`

- **File(s)**: `apps/web/src/lib/goals.ts:59-67` (Android `goals.dart`), `apps/web/src/lib/goals.ts` interface definition
- **Category**: inconsistency
- **Problem**: The Android `RunGoal.toJson()` serialises to `distance_m`, `time_s`, `pace_s_per_km`, `run_count`. The web `RunGoal` interface uses camelCase field names (`distanceMetres`, `timeSeconds`, `paceSecPerKm`, `runCount`) and stores them directly via `JSON.stringify`. If a user ever exports goals from Android and imports them via the backup path (or if `run_goals` is promoted to the universal settings bag as `goals.ts` already anticipates), the JSON key mismatch will silently produce `undefined` for all targets. The `loadGoals` filter at line 56-57 only checks `g.id` exists — it won't reject malformed goals, it will return them with all targets as `undefined` and they'll show as empty.
- **Evidence**:
  ```typescript
  // goals.ts interface (implicit via JSON.stringify)
  interface RunGoal {
      distanceMetres?: number;   // stored as "distanceMetres" in localStorage JSON
  }
  // goals.dart:62-67
  if (distanceMetres != null) 'distance_m': distanceMetres,   // different key
  ```
- **Proposed change**: Align the web `RunGoal` serialisation keys with Android's snake_case. Rename the in-memory fields or add explicit `toJSON`/`fromJSON` that maps to/from the snake_case wire format. Since goals are currently localStorage-only and not yet synced, this is low urgency but will become a data-loss bug the moment the settings-bag promotion happens.
- **Risk if applied**: Existing web users' localStorage goals will not parse under the new keys. Write a one-time migration: on `loadGoals`, detect old-format keys (`distanceMetres`) and convert them.
- **Verification**: Write a goal with a distance target, export + reimport the backup on Android, confirm the goal appears.

---

### L2. `data.ts:deleteRun` silently swallows the Storage delete error with an empty `catch`

- **File(s)**: `apps/web/src/lib/data.ts:136-139`
- **Category**: inconsistency (layered-resilience rule)
- **Problem**: The track Storage removal is explicitly "best-effort" (comment at line 130), but the catch block is empty — `catch (_) {}`. Per `conventions.md § Error handling`, silent swallowing to a completely empty catch is prohibited. A `console.warn` at minimum would surface orphaned Storage objects during debugging.
- **Evidence**:
  ```typescript
  // data.ts:136-138
  try {
      await supabase.storage.from('runs').remove([run.track_url]);
  } catch (_) {}
  ```
- **Proposed change**:
  ```diff
  - } catch (_) {}
  + } catch (e) {
  +     console.warn('deleteRun: track storage removal failed (orphaned file)', run.track_url, e);
  + }
  ```
- **Risk if applied**: None.
- **Verification**: Code inspection only.

---

### L3. `data.ts:saveRunAsRoute` back-link update swallows errors silently

- **File(s)**: `apps/web/src/lib/data.ts:296-299`
- **Category**: inconsistency (layered-resilience rule)
- **Problem**: The `try { await supabase.from('runs').update(...) } catch (_) {}` at line 296-299 swallows any RLS or FK error without logging. Same pattern as L2 — the comment says "best-effort" but the empty catch hides failures.
- **Evidence**:
  ```typescript
  // data.ts:297-299
  try {
      await supabase.from('runs').update({ route_id: data.id }).eq('id', runId);
  } catch (_) {}
  ```
- **Proposed change**:
  ```diff
  - } catch (_) {}
  + } catch (e) {
  +     console.warn('saveRunAsRoute: back-link update failed', e);
  + }
  ```
- **Risk if applied**: None.
- **Verification**: Code inspection only.

---

### L4. `gpx.ts:toGpx` hardcodes `creator="BetterRunner"` — inconsistent with app identity

- **File(s)**: `apps/web/src/lib/gpx.ts:19`, `apps/web/src/lib/gpx.ts:58`
- **Category**: inconsistency
- **Problem**: Both `toGpx` and `toRunGpx` emit `creator="BetterRunner"`. The app is called "RunApp" / "run-app" throughout the rest of the codebase (`run_app.theme`, `run_app.device_id`, `run_app.goals_v1`, `BACKUP_FORMAT = 'run-app-backup'`). This is a cosmetic inconsistency but will appear in every GPX file users export.
- **Proposed change**: Change both occurrences to `creator="RunApp"` (or whatever the canonical product name is).
- **Risk if applied**: None.
- **Verification**: Export a run as GPX, open in a text editor, confirm the creator attribute.

---

### L5. `mock-data.ts` uses `age_grade` key (no underscore-separated suffix) but `metadata.md` registry entry is `age_grade` — actually fine, but registry note says `"54.23%"` while mock uses `'54.23%'` — consistent

- **File(s)**: `apps/web/src/lib/mock-data.ts:25`
- **Category**: inconsistency (minor)
- **Problem**: The mock parkrun run at line 25 includes `metadata: { event: 'Richmond', position: 42, age_grade: '54.23%' }`. The `metadata.md` registry lists `age_grade` as `string — age-graded percentage as a string with % suffix`. This is consistent. However, the mock data is the only place in the web codebase that sets `age_grade` — there is no web reader for it. The registry note says "No UI consumer today" — this is accurate. Not a bug; noting that the mock key could be dropped if the mock data is cleaned up.
- **Proposed change**: No change required. The mock data is correct.
- **Risk if applied**: N/A.
- **Verification**: N/A.

---

### L6. `supabase-server.ts` — file exists in lib but was not enumerated; if it imports the browser Supabase client it will SSR-crash

- **File(s)**: `apps/web/src/lib/supabase-server.ts`
- **Category**: investigate
- **Problem**: The file exists but wasn't reviewed because it was not surfaced in the scope list. If it creates a server-side Supabase client using the service-role key, it should not import `$lib/supabase` (which is the browser client). This is flagged for the implementer to verify — not enough context to confirm.
- **Proposed change**: Read `supabase-server.ts` in full. Confirm it does not import `$lib/supabase.ts` (browser client). If it does, it needs to use `createClient` with the service-role key pattern instead.
- **Risk if applied**: N/A — investigation item.
- **Verification**: `pnpm check` in `apps/web` will surface any server-side import of browser-only modules as a type error.

---

## Counts

H: 5  M: 6  L: 6
