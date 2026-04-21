# Watches (Wear OS + Apple Watch) sync + schema audit

## Scope
- Files reviewed: 30 (9 Swift, 20 Kotlin, 1 generated Kotlin)
- Focus: cross-platform sync correctness — row shape, track format, metadata, auth
- Reviewer confidence: high — read every file in scope and cross-referenced against `packages/api_client`, `packages/core_models`, `apps/web/src/lib/data.ts`, `docs/api_database.md`, and `docs/metadata.md`

## Summary

Four HIGH findings, three MED, and two LOW. The two most critical are: (1) both watches write `source = 'app'` instead of `'watch'`, which permanently conflates watch-recorded runs with phone-recorded runs in every downstream filter, the `personal_records()` RPC, and the web source-filter UI; (2) the Wear OS laps format (`number`, `at_ms`, `distance_m`) does not match the `metadata.md` registry format (`index`, `start_offset_s`, `distance_m`, `duration_s`), so the Android run-detail screen's laps table will be empty for any lap-enabled Wear OS run. Apple Watch-specific findings: the phone-handoff metadata dict sends `source = 'app'` (same wrong value); `HealthKitManager.averageBPM` is sourced from `HKLiveWorkoutBuilder.statistics.averageQuantity()` with no 30–230 BPM clamp, so sensor noise during wrist motion can inflate or deflate the stored average. Auth-layer findings: `SupabaseClient.applyCredentials` ignores the `baseUrl` and `anonKey` fields pushed from the phone, so a staging phone paired with a watch whose BuildConfig points at prod will silently write all runs to prod while the phone is writing to staging. Wear OS offline runs also have no `external_id`, so the one-retry-on-401 path in `drainQueue` can POST the same run row twice if the first POST succeeds and the 401 is a stale header race — the second POST will hit a 409 (unique `id`) but that falls into the "permanent, skip" bucket so the run stays permanently in the queue.

---

## Findings

### SOURCE_VALUE — Both watches write `source = 'app'`, not `'watch'`

**Severity:** HIGH
**Platform:** both
**File(s):**
- `apps/watch_ios/WatchApp/ContentView.swift:51` — metadata dict for WCSession transfer
- `apps/watch_ios/WatchApp/SupabaseService.swift:87` — `RunPayload.source = "app"` (DEBUG direct path)
- `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/SupabaseClient.kt:183` — `RunRow.COL_SOURCE to "app"`

**Issue:** Every run recorded on either watch is inserted into the `runs` table with `source = 'app'`. The phone-side run recorder also writes `source = 'app'` (`run_screen.dart:735`). There is no `'watch'` value in the `RunSource` enum on Dart, in the web `RunSource` union (`apps/web/src/lib/types.ts:55-62`), or in the DB `source` values documented in `docs/api_database.md`. Any code that needs to distinguish "recorded on a phone" from "recorded on a watch" has no way to do so after the row is written. The `personal_records()` Postgres function (`apps/backend/supabase/migrations/20260406_001_database_functions.sql:34`) filters `source in ('app', 'strava', ...)` — watch runs will appear in personal-record calculations, which is correct, but the value `'app'` will mislead any future filter that interprets `'app'` as "phone-native recording". The source-filter chips on the web runs list (`/runs` page, `apps/web/src/routes/runs/+page.svelte:30-32`) and dashboard have a "Recorded" chip keyed to `source = 'app'` — watch runs will match it and be indistinguishable.

**Cross-platform impact:** Phone, web, and any analytics that partition by `source` cannot distinguish watch-originated runs from phone-originated runs. Any future "recorded on watch" filter or badge is impossible to backfill correctly.

**Fix sketch:** Add `'watch'` to all three `RunSource` definitions (Dart enum, web type union, DB documentation), then change the write sites:
- `SupabaseClient.kt:183`: `RunRow.COL_SOURCE to "watch"`
- `ContentView.swift:51` metadata dict: `"source": "watch"`
- `SupabaseService.swift:87` `RunPayload.source`: `"watch"` (DEBUG path)

The `personal_records()` migration filter must also be updated to include `'watch'`, otherwise watch runs will silently drop out of PB calculations after the fix:
```diff
- and source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')
+ and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
```

---

### LAPS_FORMAT — Wear OS laps metadata shape diverges from the registry

**Severity:** HIGH
**Platform:** watch_wear
**File(s):** `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/RunViewModel.kt:688-699`

**Issue:** `pushRun` serialises laps as:
```kotlin
addJsonObject {
    put("number", lap.number)
    put("at_ms", lap.atMs)         // epoch-offset milliseconds from recording start
    put("distance_m", lap.distanceM)
}
```
The `metadata.md` registry defines the `laps` key shape as:
```
{ index: int, start_offset_s: int, distance_m: double, duration_s: int }
```
and the phone recorder (`packages/run_recorder`) writes `index` / `start_offset_s` / `duration_s`. The Android run-detail screen reads `laps` by the registered shape. Wear OS uses `number` instead of `index`, `at_ms` (absolute epoch ms offset from recording start) instead of `start_offset_s` (seconds), omits `duration_s` entirely, and `distance_m` is cumulative whereas the registry shows it as per-split.

**Cross-platform impact:** `mobile_android/lib/screens/run_detail_screen.dart` reads `metadata['laps']` using the registered key names. A Wear OS run viewed on the phone will show an empty laps table because the keys don't match. The web run-detail page has the same gap if it ever renders laps.

**Fix sketch:** Change `pushRun` in `RunViewModel.kt` to emit the registered shape. `lap.atMs` is elapsed milliseconds from recording start (it is set as `activeElapsedMs()` in `RunRecordingService.markLap`, which is already the active elapsed — not wall clock), so `start_offset_s = (lap.atMs / 1000).toInt()`. `duration_s` per lap requires knowing the previous lap's `atMs`:
```diff
- put("number", lap.number)
- put("at_ms", lap.atMs)
- put("distance_m", lap.distanceM)
+ put("index", lap.number)
+ put("start_offset_s", (lap.atMs / 1000).toInt())
+ put("distance_m", lap.distanceM)
+ // duration_s requires splitting at the call site; see FinishedLap already computed in buildFinishedLaps
```
The cleanest fix uses the already-computed `FinishedLap` list (built in `buildFinishedLaps`) which has `splitSeconds` and `splitDistanceM` — pass those through `QueuedRun` and use them in `pushRun`. Update `metadata.md` to clarify that `distance_m` is per-split not cumulative if that is the canonical shape.

---

### HR_NO_CLAMP — Apple Watch `avg_bpm` has no sensor-noise clamp

**Severity:** HIGH
**Platform:** watch_ios
**File(s):** `apps/watch_ios/WatchApp/HealthKitManager.swift:95-101`

**Issue:** `averageBPM` is set directly from `HKLiveWorkoutBuilder.statistics(for: hrType).averageQuantity()` with no range validation:
```swift
let avg = stats.averageQuantity()?.doubleValue(for: hrUnit)
// ...
self.averageBPM = avg   // no clamp
```
The `metadata.md` registry documents: "All [sources] clamp to 30–230 BPM before averaging to drop sensor noise." The Wear OS path (`HeartRateMonitor.kt:47-48`) enforces this clamp on every sample before it enters the rolling average. The phone BLE path also clamps (confirmed via `ble_heart_rate.dart`). `HKLiveWorkoutBuilder` will average across the full session duration including moments where HealthKit reports anomalous values (wrist-off can produce 0 or very high readings before the sensor stabilises). A run with a stale or anomalous sensor start can produce an `avg_bpm` well outside 30–230.

**Cross-platform impact:** Web and Android run-detail screens display `avg_bpm` as a number. An Apple Watch run can write a value like 12 or 280 that the UI renders verbatim, while Wear OS and phone BLE runs are clamped. Any analytics comparing average heart rate across sources will be inconsistent.

**Fix sketch:** After the `averageQuantity()` call in `workoutBuilder(_:didCollectDataOf:)`, clamp the result before assigning:
```swift
if let raw = avg, raw >= 30 && raw <= 230 {
    self.averageBPM = raw
}
// else: leave averageBPM unchanged (nil or previous valid value)
```
This also aligns with how `currentBPM` is already handled (implicitly clamped by HealthKit's sensor pipeline, though not explicitly).

---

### DATALAYER_ENV_IGNORED — Wear OS ignores `base_url` + `anon_key` from phone handoff

**Severity:** HIGH
**Platform:** watch_wear
**File(s):** `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/SupabaseClient.kt:54-67`

**Issue:** `applyCredentials` receives `baseUrl` and `anonKey` from the phone's Data Layer push but silently discards them:
```kotlin
fun applyCredentials(
    accessToken: String,
    refreshToken: String,
    userId: String,
    baseUrl: String,
    anonKey: String,
) {
    this.accessToken = accessToken
    this.refreshToken = refreshToken
    this.userId = userId
    // `baseUrl` / `anonKey` are not mutable on this client today — the
    // Gradle BuildConfig value is used.
}
```
`SupabaseClient` is constructed in `RunViewModel` with `baseUrl = BuildConfig.SUPABASE_URL` and `anonKey = BuildConfig.SUPABASE_ANON_KEY`. These BuildConfig values are baked at compile time. The phone can be running against a staging backend (or the developer's local Supabase) while the watch BuildConfig points to production. The phone pushes the correct `base_url` in the session payload — `wear_auth_bridge.dart` sends the `url` parameter passed to `attach()` — but the watch discards it.

**Cross-platform impact:** A development scenario where the phone app is built against staging (e.g. with `SUPABASE_URL` overridden at runtime via an env file) will push staging credentials to the watch. The watch then uses those staging tokens against its hardcoded prod URL. Every Wear OS run during that session will either fail with a 401 (mismatched JWT) or, if the anon key happens to be valid on prod but the tokens belong to a staging account, silently write runs under a non-existent user and be silently dropped by RLS. The comment in the code acknowledges this but categorises it as a future problem. It is a present problem for anyone running the phone on staging.

**Fix sketch:** Make `baseUrl` and `anonKey` mutable fields on `SupabaseClient` and assign them in `applyCredentials`:
```diff
- private val baseUrl: String,
- private val anonKey: String,
+ private var baseUrl: String,
+ private var anonKey: String,

  fun applyCredentials(..., baseUrl: String, anonKey: String) {
      this.accessToken = accessToken
      this.refreshToken = refreshToken
      this.userId = userId
+     this.baseUrl = baseUrl
+     this.anonKey = anonKey
  }
```
No callers need changing — `RunViewModel` still constructs the client with BuildConfig defaults, which remain correct until the phone pushes an override.

---

### QUEUE_NO_EXTERNAL_ID — Wear OS offline queue has no deduplication key; 401-retry can double-insert

**Severity:** MED
**Platform:** watch_wear
**File(s):**
- `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/SupabaseClient.kt:177-198`
- `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/RunViewModel.kt:629-680`

**Issue:** `SupabaseClient.saveRun` does a plain `POST` to `/rest/v1/runs` with `Prefer: return=minimal`. No `external_id` column is set, no `Prefer: resolution=merge-duplicates` header, and no `onConflict` parameter. The `runs` table has a unique index on `external_id` but not on `id` (PostgREST will reject a duplicate `id` as a primary-key violation — HTTP 409). The `drainQueue` 401-retry block in `RunViewModel` refreshes the token and calls `pushRun(run)` a second time without removing the run from the queue first. If the first `pushRun` call succeeded (row inserted, network response received, HTTP 200) but the app then crashed before `store.remove(run.id)` executed, the next drain will POST the same `id` again, which will be a 409. The 409 regex (`Regex("HTTP 4(00|04|09|22)")`) correctly matches and marks it permanent — the run stays in the queue forever and the user sees a persistent sync error. On the 401-retry path specifically: if the first attempt returned 401 but the row had already been inserted server-side (a race between token expiry and the Supabase JWT validator clock skew), the refresh + retry will POST again and hit a 409, which breaks out of the loop with `lastError = "HTTP 409"` displayed to the user.

**Cross-platform impact:** Wear OS only. Phone (`LocalRunStore`) and watch_ios (WCSession deduplication on the phone side) are not affected. But a Wear OS user coming back online after a long offline run will potentially see a permanent "sync error" for a run that is actually in the DB.

**Fix sketch:** Set `external_id` to the run's UUID and add the upsert header to `saveRun`. The `runs` table has `external_id text unique` with a partial index on non-null values:
```diff
  val rowMap = mapOf(
      RunRow.COL_ID to runId,
      RunRow.COL_USER_ID to uid,
      RunRow.COL_STARTED_AT to startedAtIso,
      RunRow.COL_DURATION_S to durationS,
      RunRow.COL_DISTANCE_M to distanceM,
      RunRow.COL_SOURCE to "watch",
      RunRow.COL_TRACK_URL to path,
      RunRow.COL_METADATA to metadata,
+     RunRow.COL_EXTERNAL_ID to runId,
  )
  // ...
  .header("Prefer", "resolution=merge-duplicates,return=minimal")
```
This makes every retry idempotent. The 409 branch in `drainQueue` can then become "remove from queue" rather than "leave permanently".

---

### IOS_HANDOFF_SOURCE — Watch → phone handoff metadata sends `source = 'app'` (distinct from SOURCE_VALUE above but same root cause, different blast radius)

**Severity:** MED
**Platform:** watch_ios
**File(s):** `apps/watch_ios/WatchApp/ContentView.swift:39-58`

**Issue:** The metadata dict sent to the phone via `WCSession.transferFile` includes `"source": "app"`. When the phone-side receiver (not yet built; blocked on `mobile_ios` auth) processes this and inserts the row, it will use `source = 'app'`. This means even when the phone handles the Supabase write on behalf of the watch, the watch origin is invisible. This is the same value problem as `SOURCE_VALUE` but affects the phone-as-proxy path specifically and the phone receiver code that doesn't yet exist — meaning there is a window to fix this before any run is ever actually inserted via this path.

**Cross-platform impact:** Same as SOURCE_VALUE: the watch-recorded run is indistinguishable from a phone-recorded run on the server. The phone receiver that is not yet built must be written to honour the `source` field from the metadata dict rather than hardcoding `'app'`.

**Fix sketch:** Change `ContentView.syncRun()` line 51:
```diff
- "source": "app"
+ "source": "watch"
```
Document in the watch_ios CLAUDE.md that the phone-side `WCSessionDelegate` receiver must forward `metadata["source"]` directly to the Supabase row insert rather than hardcoding any value.

---

### PERSONAL_RECORDS_EXCLUDES_WATCH — `personal_records()` RPC will exclude watch runs even if `source` is fixed

**Severity:** MED
**Platform:** both
**File(s):** `apps/backend/supabase/migrations/20260406_001_database_functions.sql:34`

**Issue:** The `personal_records()` Postgres function filters:
```sql
and source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')
```
`'watch'` is not in this list. This finding depends on `SOURCE_VALUE` being fixed first — once both watches write `source = 'watch'`, every watch-recorded run will be silently excluded from the PB calculation. A user's fastest 5K run on their Apple Watch will not appear in personal records on the web or phone dashboard.

**Cross-platform impact:** Postgres RPC `personal_records()` is called from `apps/web/src/lib/data.ts` (web dashboard PBs) and `packages/api_client` (Flutter phone dashboard PBs). Both surfaces miss watch runs.

**Fix sketch:** New migration adding `'watch'` to the `source in (...)` filter. Can be batched with the `SOURCE_VALUE` fix migration:
```sql
create or replace function personal_records()
returns table (distance text, best_time_s integer, achieved_at timestamptz)
language sql stable
as $$
  select ...
  where
    user_id = auth.uid()
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
  ...
$$;
```

---

### WATCHIOS_NO_ACTIVITY_TYPE — Apple Watch never sets `metadata.activity_type`

**Severity:** LOW
**Platform:** watch_ios
**File(s):** `apps/watch_ios/WatchApp/ContentView.swift:44-54`

**Issue:** The metadata dict sent in the WCSession transfer and in the DEBUG direct-upload path (`SupabaseService.swift:80-88` `RunPayload`) contains no `activity_type` key. The `metadata.md` registry documents that `activity_type` defaults to `'run'` when absent, so consumers will fall back correctly. However, the watch always records a run (the `HKWorkoutConfiguration.activityType` is `.running`), and the phone BLE path, the Wear OS path, and the phone Health Connect importer all explicitly write `activity_type = 'run'`. The omission means the Apple Watch is the only recording path that doesn't write this key. If the watch ever gains walk/hike/cycle modes, there will be no field to set.

**Cross-platform impact:** Low impact today because consumers default to `'run'`. But the activity-type filter chips on the phone runs screen and web runs screen (filtering `metadata.activity_type`) will categorise Apple Watch runs as "untagged" if the filter ever stops defaulting to `'run'` for absent keys.

**Fix sketch:** Add `activity_type` to the WCSession metadata dict and to `RunPayload`:
```swift
// ContentView.swift syncRun()
metadata["activity_type"] = "run"

// SupabaseService.swift RunPayload (DEBUG path)
// Add a `metadata` field to RunPayload and include activity_type: "run"
```

---

### WATCHIOS_UUID_FORMAT — Apple Watch run IDs use uppercase UUID strings

**Severity:** LOW
**Platform:** watch_ios
**File(s):** `apps/watch_ios/WatchApp/WorkoutManager.swift:105`

**Issue:**
```swift
id: UUID().uuidString.lowercased()
```
`.uuidString` on iOS produces uppercase hex (`7F3A...`). `.lowercased()` is called, so the wire value will be lowercase. Confirmed: other platforms use `UUID.randomUUID().toString()` (Kotlin, lowercase) and `const Uuid().v4()` (Dart, lowercase). The DB column is `uuid` type — Postgres normalises UUID comparisons case-insensitively, so there is no functional bug. However, the `local_run_store.dart` on the phone deduplicates by `id` string equality. When the phone receives the WCSession transfer and constructs the row, it will use the `id` from the metadata dict. As long as `.lowercased()` is called consistently (it is), this is fine. Flagged as LOW because the `.lowercased()` call is present; it is a latent risk if a future code path drops that call.

**Cross-platform impact:** None currently. Watch for any future code path that constructs the run ID from `UUID().uuidString` without `.lowercased()`.

**Fix sketch:** No action required if `.lowercased()` is always called. Consider replacing `UUID().uuidString.lowercased()` with an explicit lowercase UUID formatter for clarity:
```swift
id: UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
```
Actually — do not remove the hyphens, Postgres `uuid` type requires them. Leave as-is but document the `.lowercased()` requirement.

---

## Platform parity table

| Field | Android phone writes | Wear OS writes | Apple Watch writes | Issue |
|---|---|---|---|---|
| `source` | `'app'` | `'app'` | `'app'` (via WCSession metadata) | **HIGH** — all three should differ; watch should be `'watch'` |
| `user_id` | auth user id | auth user id from session | phone's auth user id (proxy) | OK |
| `started_at` | ISO 8601 timestamptz | ISO 8601 via `Instant.toString()` | ISO 8601 via `ISO8601DateFormatter` | OK |
| `duration_s` | integer seconds | integer seconds | integer seconds | OK |
| `distance_m` | double metres | double metres | double metres | OK |
| `track_url` | `{user_id}/{run_id}.json.gz` | `{user_id}/{run_id}.json.gz` | `{user_id}/{run_id}.json.gz` (phone sets this after upload) | OK |
| `external_id` | set to run UUID | **not set** | **not set** (phone sets on insert) | MED — Wear OS lacks dedup key |
| `metadata.activity_type` | `'run'`/`'walk'`/etc. | `'run'`/`'walk'`/etc. | **absent** | LOW — Apple Watch omits always |
| `metadata.avg_bpm` | number (clamped 30–230) | number (clamped 30–230) | number (**unclamped**, raw HKLiveWorkoutBuilder average) | **HIGH** — Apple Watch no clamp |
| `metadata.laps` | `{index, start_offset_s, distance_m, duration_s}[]` | `{number, at_ms, distance_m}[]` | not supported | **HIGH** — Wear OS format differs from registry |
| `metadata.steps` | written when pedometer fires | **not written** | **not written** | OK — optional, documented |
| `metadata.last_modified_at` | written by `local_run_store.dart` | **not written** | **not written** | OK — Android-only sync key, documented |
| Track waypoint `lat`/`lng` | present | present | present | OK |
| Track waypoint elevation key | `ele` | `ele` | `ele` (Swift `TrackPoint.ele`) | OK |
| Track waypoint timestamp key | `ts` (ISO 8601 string) | `ts` (ISO 8601 from `Instant.toString()`) | `ts` (ISO 8601 from `ISO8601DateFormatter`) | OK |
| Track gzip format | standard gzip | standard gzip (JDK `GZIPOutputStream`) | hand-rolled gzip envelope (DEFLATE + 10-byte header) | OK functionally — gzip header is valid; readers use standard decompressors |
| `Prefer` header on row insert | `return=minimal` via supabase-dart (upsert) | `return=minimal` | `return=minimal` | OK |
| Dedup on retry | yes — `external_id` upsert | **no** — plain POST | n/a (phone-side proxy) | MED — Wear OS only |
| BPM clamp before averaging | 30–230 (BLE path) | 30–230 (`HeartRateMonitor.kt:47`) | **none** (`HKLiveWorkoutBuilder.averageQuantity`) | HIGH — Apple Watch |

---

## Confirmed-good

- Track waypoint field names (`lat`, `lng`, `ele`, `ts`) match across Wear OS (`TrackWriter.kt`), Apple Watch (`WorkoutManager.TrackPoint`), phone (`api_client._waypointToJson`), and web (`data.ts` — parses without key assumptions via `JSON.parse`).
- Track timestamp format is ISO 8601 string in the `ts` field on all three platforms; the Dart reader parses via `DateTime.tryParse` which accepts the `Instant.toString()` format Wear OS produces (`2025-04-05T08:00:00Z`).
- Track storage path `{user_id}/{run_id}.json.gz` is identical across Wear OS (`SupabaseClient.kt:174`) and the phone (`api_client._uploadTrack`). Apple Watch sends a raw `.json` file and the phone gzips before upload — also correct when the phone receiver is built.
- `track_url` column is set correctly on both watch platforms after upload.
- Wearable Data Layer session payload schema (`access_token`, `refresh_token`, `user_id`, `base_url`, `anon_key`, `expires_at_ms`) matches between writer (`WearAuthBridge.kt`) and reader (`SessionBridge.kt`). String key names are identical.
- `StoredSession.isExpired()` uses a 60-second safety margin, matching the intent described in decisions.md §16.
- `drainQueue` 401-retry correctly refreshes the token and persists the refreshed session back to `SessionStore` so subsequent cold starts use the new token.
- `awaitAuth(3000 ms)` eliminates the cold-start race documented in decisions.md §17.
- Checkpoint recovery (`CheckpointStore` + `recoverCheckpoint`) produces a `QueuedRun` with the same shape as a normally-finished run — no tell-tale key is added to the uploaded row.
- Wear OS `HeartRateMonitor` drops samples where `isAvailable` is false (ACQUIRING / wrist-off), preventing stale sensor data from entering the rolling average. The 30–230 clamp is applied per-sample.
- `TrackWriter` closes and seals the JSON array (`]`) in `onDestroy`, and `sealTrackFile` defensively re-seals on checkpoint recovery if the process was killed mid-flush.
- `LocalRunStore.save` deduplicates by run id: `queue.first().filter { it.id != run.id } + run` — a re-queued run replaces rather than appends.

---

## Out of scope

- `packages/api_client/lib/src/api_client.dart:81` — the phone's `saveRun` re-uploads the full track on every metadata-only edit (noted in decisions.md §2 "Known rough edges"). Not a watch issue.
- `apps/mobile_android/lib/local_run_store.dart` — `LocalRunStore.delete` does not delete the Storage object (same known rough edge). Not a watch issue.
- `apps/backend/supabase/migrations/20260406_001_database_functions.sql:34` — `personal_records()` source filter is documented above as MED and also affects `'healthkit'` / `'healthconnect'` runs from the Apple Watch import path, but that is phone-side behaviour outside this audit's scope.
