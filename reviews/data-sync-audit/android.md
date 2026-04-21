# Android sync + schema audit

## Summary

Seven findings across three severity levels. The two HIGH items are silent production bugs today: `last_modified_at` is stamped as a **local-timezone ISO string** (no UTC suffix) by `LocalRunStore._withLastModified`, causing the delta-fetch query to silently skip runs for users outside UTC; and `saveRunsBatch` uses a **mixed-batch `onConflict` heuristic** that will destroy duplicate-row detection when a batch contains even one run that lacks an `external_id`. Three MED findings cover the timezone issue propagating to waypoint timestamps, an undeclared metadata key (`laps`) from Wear OS not matching the phone's `laps` schema, and the `add_run_screen.dart` local-clock `started_at`. Two LOW findings cover discipline gaps (`device` column noted in audit brief but does not exist in schema; settings roaming is deliberately narrow but the registry lists 10 keys Android doesn't push).

---

## Findings

### `last_modified_at` stamped as local-timezone ISO string
**Severity:** HIGH
**File(s):** `apps/mobile_android/lib/local_run_store.dart:145`

**Issue:** `_withLastModified` calls `DateTime.now().toIso8601String()`. On a device in UTC+5, Dart's `DateTime.now()` is a local-timezone object and `toIso8601String()` emits `"2026-04-21T13:30:00.000"` — no `Z` suffix, no offset. Postgres receives this for a `jsonb` text field and the `getRuns(updatedSince:)` query in `api_client.dart:232` compares it lexicographically against `updatedSince.toIso8601String()` (which IS UTC because `fetchStartedAt = DateTime.now().toUtc()`). A UTC timestamp like `"2026-04-21T08:30:00.000Z"` is lexicographically less than the naive local `"2026-04-21T13:30:00.000"` when the user is UTC+5, so every run modified in UTC+5 will be treated as "modified after the next fetch window" — until the cursor catches up 5 hours later. The opposite happens in UTC-N: runs appear to the fetch filter as older than they are and are skipped on the delta path until the full-refresh cycle catches them.

**Evidence:**
```dart
// local_run_store.dart:145
metadata['last_modified_at'] = ts.toIso8601String();   // ts = DateTime.now() — local tz, no Z
```
```dart
// api_client.dart:232-234
query = query.gt(
  "${RunRow.colMetadata}->>'last_modified_at'",
  updatedSince.toIso8601String(),   // updatedSince is UTC (toUtc() called at call site)
);
```

**Cross-platform impact:** The Postgres lexicographic comparison of ISO strings only works correctly when both strings carry the same tz marker. Android users outside UTC will see stale data (edits made on one device not reflected on another) until a full refresh runs. Web reads `last_modified_at` out of the same field; any web audit tooling that parses it will produce wrong timestamps.

**Fix sketch:**
```diff
- metadata['last_modified_at'] = ts.toIso8601String();
+ metadata['last_modified_at'] = ts.toUtc().toIso8601String();
```
Apply this one-line change in `_withLastModified`. The `ts` parameter is always `DateTime.now()` at both call sites (`save` and `update`); add `.toUtc()` there or inside `_withLastModified`. The existing stored values with naive strings will sort wrong only until they are next written; no migration is needed.

**Risk if applied:** None. Existing stored naive strings remain in the DB but will be overwritten on the next local mutation. The lexicographic comparison works correctly as soon as both sides carry `Z`.

**Verification:** `flutter test apps/mobile_android/test/local_run_store_test.dart` — add a test that calls `store.save(run)` and asserts `run.metadata!['last_modified_at'].endsWith('Z')`. Also check that `store.update(run)` does the same.

---

### `saveRunsBatch` uses a per-batch `onConflict` heuristic that silently writes wrong rows
**Severity:** HIGH
**File(s):** `packages/api_client/lib/src/api_client.dart:170-182`

**Issue:** `saveRunsBatch` builds one list of all rows, then checks `runs.any((r) => r.externalId != null && r.externalId!.isNotEmpty)` to decide whether to add `onConflict: RunRow.colExternalId`. If _any_ run in the batch has an `external_id`, **every** row in that chunk upserts on `external_id` — including `app`-source runs (recorded on the phone) that have `externalId == null`. When `external_id` is null, the partial unique index `runs_external_id` (`where external_id is not null`) is not matched, so Postgres falls through to a plain insert and, combined with a second upload attempt, can create a duplicate row. Conversely, when mixed with Strava/Health Connect runs that _do_ have `external_id`, the upsert spec is misapplied to rows where it is meaningless.

The normal use case is `SyncService` pushing `unsyncedRuns`, which typically contains a mix of live-recorded runs (no `external_id`) and imported runs (with `external_id`). Both kinds land in one `saveRunsBatch` call.

**Evidence:**
```dart
// api_client.dart:170-181
final hasExternalIds =
    runs.any((r) => r.externalId != null && r.externalId!.isNotEmpty);
// ...
if (hasExternalIds) {
  await _client
      .from(RunRow.table)
      .upsert(chunk, onConflict: RunRow.colExternalId);  // applied to ALL rows in chunk
} else {
  await _client.from(RunRow.table).upsert(chunk);
}
```

**Cross-platform impact:** A second sync of a mixed batch after a failed first attempt can write duplicate `app`-source rows visible to web and Wear OS. Web's run list uses `getRuns` ordered by `started_at`; duplicates appear as twin cards for the same run with the same timestamp.

**Fix sketch:** Split the batch at the call site — upsert rows that have `external_id` with `onConflict: external_id`, and upsert rows without `external_id` without the conflict column (Postgres will match on the primary key `id` by default, which is the correct dedup for app-recorded runs).
```dart
// Replace the single loop with two passes:
final withExtId = rows.where((r) => (r['external_id'] as String?) != null
    && (r['external_id'] as String)!.isNotEmpty).toList();
final withoutExtId = rows.where((r) {
  final id = r['external_id'] as String?;
  return id == null || id.isEmpty;
}).toList();

if (withExtId.isNotEmpty) {
  await _client.from(RunRow.table).upsert(withExtId, onConflict: RunRow.colExternalId);
}
if (withoutExtId.isNotEmpty) {
  await _client.from(RunRow.table).upsert(withoutExtId);
}
```
Split across chunk boundaries too — the chunk loop wraps these two upserts.

**Risk if applied:** None for the normal path. The dedup key behaviour changes from "wrong for app-source runs in a mixed batch" to "correct for all rows". Verify on a test account with a mixed offline queue.

**Verification:** Add an integration or store test that calls `saveRunsBatch` with two runs — one `RunSource.app` (no `externalId`) and one `RunSource.strava` (with `externalId`) — twice in a row, and asserts only two rows exist in the table.

---

### Waypoint timestamps in the track are emitted as local-timezone ISO strings
**Severity:** MED
**File(s):** `packages/api_client/lib/src/api_client.dart:336`

**Issue:** `_waypointToJson` serialises `w.timestamp?.toIso8601String()` without `.toUtc()`. GPS timestamps come from geolocator, which returns local-tz `DateTime` objects on Android. The stored track in Storage will contain entries like `"ts": "2026-04-21T09:15:00.000"`. The web `fetchTrack` uses `DateTime.tryParse(m['ts'])`, which on the browser (V8) parses a naive ISO string as _local_ browser time — correct only if the browser and Android phone happen to be in the same timezone. The `docs/api_database.md` canonical shape shows `"ts": "2025-04-05T08:00:00Z"` (UTC with Z).

**Evidence:**
```dart
// api_client.dart:332-337
static Map<String, dynamic> _waypointToJson(Waypoint w) => {
  'lat': w.lat,
  'lng': w.lng,
  'ele': w.elevationMetres,
  'ts': w.timestamp?.toIso8601String(),   // no .toUtc()
};
```

**Cross-platform impact:** The web `fastestWindowOf` and pace-chart calculations depend on waypoint timestamps for correct segment durations. A user in UTC+9 running at 9:00 AM local time stores `"09:00:00.000"`. A web viewer in UTC will parse that as 09:00 UTC = 18:00 local for them — the timeline renders wrong but doesn't crash. Wear OS (`TrackWriter.kt`) writes its own track file independently and also doesn't show this bug, but the watch-produced track will be UTC (`Instant.now()` in Kotlin) while phone-produced tracks are local — so a run split across phone start and watch continuation would have mixed-tz waypoints in the same track file (edge case, but possible in the relay-to-phone-proxy architecture).

**Fix sketch:**
```diff
- 'ts': w.timestamp?.toIso8601String(),
+ 'ts': w.timestamp?.toUtc().toIso8601String(),
```

**Risk if applied:** Tracks already stored in S3 are not retroactively fixed. New uploads will be UTC. The reader (`_waypointFromJson`) uses `DateTime.tryParse` which handles both forms. No data loss; old tracks display with mild timestamp drift.

**Verification:** Check one stored track JSON in the `runs` bucket and confirm it has `Z`-suffixed timestamps after the fix.

---

### Wear OS `laps` metadata schema differs from the phone's registered schema
**Severity:** MED
**File(s):** `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/RunViewModel.kt:689-699`

**Issue:** The Wear OS watch writes `metadata.laps` with shape `{ number: int, at_ms: long, distance_m: double }`. The `docs/metadata.md` registry for `laps` (written by `run_recorder`) defines the shape as `{ index: int, start_offset_s: int, distance_m: double, duration_s: int }`. The web reader (`run_detail_screen.dart`) and any future web lap display will find the watch-produced rows have different key names (`number` vs `index`, `at_ms` (milliseconds) vs `start_offset_s` (seconds)), causing the lap section to render blank or throw.

**Evidence:**
```kotlin
// RunViewModel.kt:690-698
put("laps", buildJsonArray {
    for (lap in run.laps) {
        addJsonObject {
            put("number", lap.number)       // registry expects "index"
            put("at_ms", lap.atMs)          // registry expects "start_offset_s" (seconds)
            put("distance_m", lap.distanceM)
            // missing "duration_s"
        }
    }
})
```
The `docs/metadata.md` laps schema:
```
{ index: int, start_offset_s: int, distance_m: double, duration_s: int }
```

**Cross-platform impact:** `mobile_android/lib/screens/run_detail_screen.dart` reads the `laps` key and renders a laps table. For Wear OS-produced runs the read will silently produce wrong data (e.g. `lap.index` = null, `lap.start_offset_s` = null) rather than crashing. Users will see an empty laps section on their watch runs.

**Fix sketch:** Align the Wear OS emitter to the registered schema:
```kotlin
// RunViewModel.kt — replace the laps block
put("laps", buildJsonArray {
    var prevMs = 0L
    var prevDist = 0.0
    for ((idx, lap) in run.laps.withIndex()) {
        addJsonObject {
            put("index", idx + 1)
            put("start_offset_s", (lap.atMs / 1000).toInt())
            put("distance_m", lap.distanceM - prevDist)
            put("duration_s", ((lap.atMs - prevMs) / 1000).toInt())
        }
        prevMs = lap.atMs
        prevDist = lap.distanceM
    }
})
```
Also update `docs/metadata.md` to note Wear OS as a writer.

**Risk if applied:** Watch runs already stored keep the old schema; those laps will remain blank on the detail screen. New watch runs will display correctly. No data loss.

**Verification:** Write a Wear OS run with two lap marks; open it in `run_detail_screen.dart` and confirm the laps table renders the correct split distances and times.

---

### `add_run_screen.dart` constructs `startedAt` as a local-timezone `DateTime` with no UTC conversion before cloud write
**Severity:** MED
**File(s):** `apps/mobile_android/lib/screens/add_run_screen.dart:53-54`

**Issue:** `_startedAt = DateTime(now.year, now.month, now.day, now.hour)` constructs a local-tz `DateTime`. The `Run` is passed to `LocalRunStore.save` (which doesn't touch `startedAt`) and eventually to `ApiClient.saveRun` where `run.startedAt.toUtc()` is correctly called before writing to the DB. So the `runs.started_at` column is fine.

However, `_withLastModified` also calls `ts.toIso8601String()` without UTC (HIGH finding above), and within the run's local-store representation the `startedAt` value stays local-tz through the entire lifetime of the in-memory `Run` object — `run.startedAt.compareTo(b.startedAt)` in `_runs.sort` in `LocalRunStore._loadAll` compares local vs UTC objects if runs from different sources are mixed (manual-entry = local, cloud-fetched = UTC after Supabase returns `timestamptz` as UTC ISO). This can produce wrong sort order in the runs list for manual-entry runs.

**Evidence:**
```dart
// add_run_screen.dart:53-54
final now = DateTime.now();          // local tz
_startedAt = DateTime(now.year, now.month, now.day, now.hour);  // still local tz
```
`_runFromRow` in `api_client.dart` returns `Run(startedAt: r.startedAt, ...)` where `r.startedAt` is parsed from a Postgres `timestamptz` response (always UTC string) — so cloud-fetched runs have UTC `startedAt`, while manually-added runs have local-tz `startedAt`.

**Cross-platform impact:** Sort order of the runs list on Android is wrong when a manual-entry run is inserted near a cloud-synced run and the phone is outside UTC. The cloud `runs.started_at` column value is correct (UTC normalization in `saveRun`).

**Fix sketch:**
```diff
// add_run_screen.dart:54
- _startedAt = DateTime(now.year, now.month, now.day, now.hour);
+ _startedAt = DateTime(now.year, now.month, now.day, now.hour).toUtc();
```
Also apply to the `_pickDate` and `_pickTime` reconstructions (lines 77 and 94).

**Risk if applied:** The date/time pickers use `TimeOfDay.fromDateTime(_startedAt)` — this is display-only and works correctly regardless of tz. The form labels call `_formatDate` / `_formatTime` which read the local-tz fields; if `_startedAt` is UTC, users outside UTC will see the time displayed in UTC rather than local time. Correct fix requires keeping the picker in local tz but converting to UTC only when constructing the `Run`. Use `_startedAt.toUtc()` at the `Run(startedAt: _startedAt.toUtc(), ...)` call site on line 175 rather than converting the field itself.

**Verification:** Set device to UTC+5, add a manual run at 09:00 local, fetch from cloud, confirm the run appears sorted correctly relative to a cloud run that started at 09:30 UTC.

---

### Settings roaming covers only `preferred_unit` while the registry defines 10 universally-roamed keys
**Severity:** LOW
**File(s):** `apps/mobile_android/lib/settings_sync.dart:56-73`

**Issue:** `SettingsSyncService.pushPreferredUnit()` writes only `preferred_unit` to the universal bag. `_applyUniversal` reads only `preferred_unit` back. The `docs/settings.md` registry lists 10 Universal or Universal-overridable keys that other clients (web, future iOS) both read and write: `default_activity_type`, `hr_zones`, `resting_hr_bpm`, `max_hr_bpm`, `date_of_birth`, `privacy_default`, `strava_auto_share`, `coach_personality`, `weekly_mileage_goal_m`, `week_start_day`. Android ignores all of them on sign-in. A user who sets `weekly_mileage_goal_m` on the web will not see their goal on Android's dashboard goal card.

**Evidence:**
```dart
// settings_sync.dart:65-73
void _applyUniversal(Map<String, dynamic> prefs) {
  final unit = prefs['preferred_unit'];
  if (unit is String) {
    final useMiles = unit == 'mi';
    if (useMiles != preferences.useMiles) {
      preferences.setUseMiles(useMiles);
    }
  }
  // All other registry keys are silently ignored
}
```

**Cross-platform impact:** Web-set goals don't roam to Android. Android-set goals (stored only in `SharedPreferences`, not synced at all) don't roam to web. `weekly_mileage_goal_m` is the most user-visible gap — the dashboard goal card on Android reads only local `SharedPreferences`.

**Fix sketch:** This is intentional today based on phasing. Confirm with the project owner which keys should round-trip before implementing. The wiring is trivial — `_applyUniversal` can be extended to read the additional keys and forward them to `Preferences`, and a `pushAllSettings()` call can write them on change. Mark as tech debt in `settings_sync.dart` with a comment referencing the full registry key list.

**Risk if applied:** Low. Adding reads from the universal bag cannot overwrite user-set local values incorrectly as long as `_applyUniversal` only applies values that differ from local defaults.

**Verification:** Set `weekly_mileage_goal_m` on the web, sign in on Android, confirm the goal bar appears on the dashboard.

---

### `strava_importer.dart` sets `externalId` to the raw Strava CSV Activity ID, while the server-side `strava-webhook` uses a namespaced format
**Severity:** LOW
**File(s):** `apps/mobile_android/lib/strava_importer.dart:73,169`

**Issue:** `StravaImporter` sets `externalId: activityId` where `activityId` is the raw string from the CSV `activity id` column (e.g. `"12345678"`). The server-side `strava-webhook` function (once its TODO `upsert` is implemented) is documented in `docs/api_database.md` as using `external_id = strava:{activity_id}` (namespaced). If both paths are ever live simultaneously, the same Strava activity would produce two rows — one with `external_id = "12345678"` from the Android ZIP importer and one with `external_id = "strava:12345678"` from the webhook — because the unique index would not match them.

The webhook function body today has only a `// TODO: Map to Run and upsert into runs table` comment, so this is not a live conflict yet, but the design contract is inconsistent.

**Evidence:**
```dart
// strava_importer.dart:73
final activityId = idIdx >= 0 ? row[idIdx].toString() : _uuid.v4();
// ...
externalId: stravaId,   // = "12345678"
```
`docs/api_database.md` (strava-webhook section):
> `external_id = strava:{activity_id}`

**Cross-platform impact:** Once the strava-webhook TODO is implemented, duplicate rows will appear for any activity the user imported from a ZIP before also having the webhook active. Web and Android would both display the duplicate.

**Fix sketch:** Align the Android importer to the namespaced format:
```diff
- externalId: stravaId,
+ externalId: 'strava:$stravaId',
```
Verify the webhook's intended format before making this change — the webhook is a TODO so the namespaced format in the doc may also be aspirational.

**Risk if applied:** Any existing rows written by the Android importer with un-namespaced IDs will not be matched on the next import (the un-namespaced key won't collide with `strava:{id}`) — a one-time duplicate per run on re-import. Accept this or run a one-time migration to prefix existing rows.

**Verification:** Import the same Strava ZIP twice; confirm only one row per activity exists in the `runs` table.

---

## Confirmed-good

- **`user_id` always set on every write path.** `saveRun`, `saveRunsBatch`, `deleteRun`, and `SupabaseClient.saveRun` (Wear OS) all guard with `if (userId == null) throw`. No nullable slip-through found.
- **`started_at` UTC-normalised in the cloud write.** `ApiClient.saveRun` and `saveRunsBatch` both call `.toUtc()` before constructing `RunRow`. The comment at line 88-92 in `api_client.dart` is correct and complete.
- **`source` values are within the registered enum.** `RunSource.app`, `.healthconnect`, `.strava` are the only values Android writes, all matching `api_database.md`'s table. The `.name` accessor on Dart enums produces lowercase, matching the DB's lowercase strings.
- **`activity_type` values are consistent across Android and web.** Android writes `'run'`, `'walk'`, `'cycle'`, `'hike'` via `_activityType.name`. The web reader (`runs/[id]/+page.svelte:93-96`) expects exactly those four strings. Wear OS defaults to `"run"`. No divergence found.
- **`health_connect_importer.dart` `activity_type` mapping.** `BIKING` → `'cycle'` matches the web-side `activityMeta['cycle']` entry. No `'bike'` vs `'cycle'` mismatch.
- **Track storage path matches the spec.** Both `ApiClient._uploadTrack` (Dart) and `SupabaseClient.uploadTrack` (Kotlin/Wear) use `$userId/$runId.json.gz` in the `runs` bucket. `deleteRun` reads `metadata['track_url']` and removes the same path.
- **Gzip + content-type.** Both clients gzip before uploading with `contentType: 'application/json'`. The download path decodes correctly.
- **`last_modified_at` stamped on all Android local mutations.** `LocalRunStore.save`, `LocalRunStore.update`, and `LocalRunStore.saveFromRemote` (only when writing a new remote run) all go through `_withLastModified`. The crash-recovery path in `main.dart` calls `store.save(recovered)` which also stamps it. The in-progress save (`saveInProgress`) deliberately does NOT stamp `last_modified_at` (it writes its own `in_progress_saved_at` instead), which is correct — the in-progress file is not a finalised run.
- **`recovered_from_crash` flag shape.** The crash-recovery path in `main.dart:122-135` sets `metadata['recovered_from_crash'] = true` (bool, as registered), then calls `store.save(recovered)` which stamps `last_modified_at`. The shape matches the registry.
- **`external_id` for Health Connect imports.** `HealthConnectImporter` sets `externalId: point.uuid` (a string UUID from the Health platform). It is never empty. The `saveRunsBatch` `onConflict: external_id` path will correctly dedup re-imports.
- **`deleteRun` attempts Storage removal before row delete.** The Storage removal is wrapped in a try/catch labelled "best-effort"; the row delete always runs. This means a Storage orphan is possible if the Storage delete fails, but the row is never orphaned without Storage. This matches the known rough edge documented in `decisions.md §2`.
- **No `track_url` leak into persisted metadata.** `_runFromRow` stuffs `metadata['track_url']` for in-memory use only. `saveRun` and `saveRunsBatch` pass `run.metadata` directly to the `RunRow` constructor; `track_url` will be present in the metadata sent to Postgres. This is mentioned as a known synthetic key and while it leaks a redundant key into the `metadata` jsonb, it does not cause functional damage — the canonical `track_url` column is what `_downloadTrack` uses.
- **`manual_entry`, `indoor_estimated`, `distance_source` metadata keys.** All match the registry (bool, bool, string). Written only when applicable; omitted when not.
- **Waypoint `ele` field.** Serialised as `w.elevationMetres` (nullable double); the canonical shape in `api_database.md` shows `"ele": 12.4`. The field name matches. Null is serialised as `null` (JSON), which the reader handles with `(m['ele'] as num?)?.toDouble()`.

---

## Out of scope

- **`strava-webhook/index.ts` — Strava activity sync is a TODO.** The webhook receives activity events but does not map them to runs or upsert into the DB. Once this is implemented it must set `external_id = 'strava:{activity_id}'` and include `source`, `user_id`, `started_at`, `distance_m`, `duration_s` — otherwise it will produce incomplete rows. The web auditor should flag this; it is a server-side concern, not Android.
- **`strava-import/index.ts` — backfill is a TODO.** The Edge Function stores tokens but does not fetch activity history. The `imported: 0` response hardcoded at line 46 confirms nothing is written to `runs`. Not an Android problem.
- **`export-data/index.ts` — entirely stubbed.** All steps are `// TODO`. Not an Android problem.
- **Web `+page.svelte` does not push any `metadata` keys.** `docs/metadata.md` acknowledges this. No Android impact from the absence, but a future "edit run" page on the web needs to handle all registered keys carefully to avoid clobbering Android-written metadata. Flag for the web auditor.
- **`watch_ios` `SupabaseService.swift` under `#if DEBUG` only.** Production watch-iOS runs go through the phone proxy via `WCSession.transferFile`; the phone side (Android or iOS) does the actual Supabase write. The phone-side receive path on `mobile_ios` is scaffold-only (per `CLAUDE.md`). Until `mobile_ios` gains real Supabase auth, Apple Watch runs cannot sync. Not an Android bug.
- **`metadata.steps` wire type is a known unverified issue.** `docs/metadata.md` explicitly flags this as `investigate`. Android writes it as `int` from `_steps` (Dart `int`). The web reader uses it as-is. The JSON wire format is an integer literal. No active bug observed in Android code; the investigation is a web/interop concern.
