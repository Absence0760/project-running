# `runs.metadata` key registry

The `runs.metadata` column is `jsonb` — a schema-less bag that any client can write into. Schema codegen ([schema_codegen.md](schema_codegen.md)) cannot catch drift in here: a mobile client can write `metadata.activity_type` and a web client can read `metadata.activityType` and nothing in the type system notices. This file is the coordination point.

**Rule:** If you add, rename, remove, or change the shape of a metadata key, update this file in the same change. If you're reading a key that isn't listed here, add it. If you find a key in the registry that isn't used anywhere in code, delete it.

---

## Key registry

Each row: what the key is, its shape, which platforms *write* it, which platforms *read* it, whether the client must tolerate its absence, and whether the key is **public-safe** (preserved by the `public_runs` view) or **owner-only** (stripped from the view's `metadata` projection — see migration `20260626_001_public_runs_view.sql` and decisions §33's wire-leak follow-up). "Optional" means "a consumer must be safe with it missing." All keys are optional unless explicitly required. **When you add a new key, classify it.** If the public_runs strip-list and this column drift, the next public-rows audit will catch it; we'd rather catch it at PR review.

### Core run properties

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `activity_type` | `string` — one of `run`, `walk`, `hike`, `cycle` | `mobile_android/screens/run_screen.dart` (recording), `mobile_android/health_connect_importer.dart`, `mobile_android/strava_importer.dart`, `apps/backend/supabase/functions/parkrun-import`, `apps/backend/supabase/functions/strava-import`, `apps/web/src/lib/strava-zip.ts`, `apps/web/src/lib/garmin-zip.ts`, `apps/web/src/lib/data.ts` (createManualRun), `apps/watch_wear/.../WatchRunMetadata.kt`, `apps/watch_ios/.../ContentView.swift` | `mobile_android` (dashboard, history, run detail), `apps/web/src/routes/runs/[id]/+page.svelte` | **Required** — enforced by `runs_metadata_activity_type_check` (see `apps/backend/supabase/migrations/20260601_001_runs_metadata_activity_type_required.sql`). Postgres rejects rows with null/missing/empty `metadata->>'activity_type'`. Reads still tolerate the key being absent for back-compat. | Backfilled to `'run'` for legacy rows. The Android recorder writes this on every save. Health Connect imports map through `_mapWorkoutType`. Strava imports map walk/hike/run from the activity type string. Backup restores coalesce to `'run'` when the original ZIP predates the requirement. |
| `steps` | `int` (stringified on the wire? — **investigate**) | `mobile_android/screens/run_screen.dart` (pedometer); `apps/watch_wear/android/.../RunRecordingService.kt` (via `Pedometer.kt` → `Sensor.TYPE_STEP_COUNTER`) | `apps/web/src/routes/runs/[id]/+page.svelte` | Optional; only present when pedometer data is available | Only written when `steps > 0`. Android + Wear OS omit the key entirely if the pedometer never fired. Wear OS requires `ACTIVITY_RECOGNITION` at runtime; if the user denies, the Pedometer flow is silent and `metadata.steps` stays absent. |
| `laps` | `array` of `{ index: int, start_offset_s: int, distance_m: double, duration_s: int }` | `packages/run_recorder/lib/src/run_recorder.dart` (final save only, via `lapsToCanonicalJson`); `apps/watch_wear/.../WatchRunMetadata.kt` (`buildRunMetadata`, called from `RunViewModel.pushRun`) | `mobile_android/screens/run_detail_screen.dart` | Optional; only present if the runner marked laps | The recorder sets `metadata = null` entirely when `_laps.isEmpty`, so readers must check for both a null `metadata` and a missing `laps` key. `index` is 1-based (matches `lap.number` on both platforms). `distance_m` and `duration_s` are *per-lap* deltas (not cumulative); `start_offset_s` is the cumulative duration up to the **start** of this lap (so the first lap has `start_offset_s = 0`). The Apr 2026 cross-platform audit caught the Dart recorder writing the older `{ number, timestamp, cumulative_distance_m, cumulative_duration_s }` shape; both writer and `run_detail_screen.dart` reader were migrated to the registered per-lap shape in the same change. The cross-platform fixture test (`fixtures/watch_run_payload.json` consumed by `apps/mobile_android/test/watch_payload_fixture_test.dart`, `apps/mobile_ios/test/watch_payload_fixture_test.dart`, `apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`, and `apps/web/src/lib/watch_payload_fixture.test.ts`) caught a separate Wear OS bug where `start_offset_s` was emitted as cumulative-AFTER (`lap.atMs / 1000`) instead of cumulative-BEFORE — fixed in `buildRunMetadata`. `watch_ingest_queue.dart` forwards the field verbatim when a watch payload includes it. |

### User-editable fields

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `title` | `string` — user-entered display title | `mobile_android/screens/run_detail_screen.dart` (edit dialog), `mobile_android/strava_importer.dart` (default from Strava activity name), `apps/web/src/lib/data.ts` (`saveRun`, via Strava and Garmin importers) | `mobile_android/screens/run_detail_screen.dart` | Optional; falls back to the formatted start date when absent | Strava imports default to the Strava activity name. Android also writes it; not currently editable on the web. |
| `notes` | `string` — free-form user notes | `mobile_android/screens/run_detail_screen.dart` (edit dialog) | `mobile_android/screens/run_detail_screen.dart` | Optional; empty string when absent | Not currently read on the web. |

### Import provenance

Set by importers when bulk-loading runs from third parties. None of these are read by any current UI — they're audit/debug data.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `imported_from` | `string` — one of `strava`, `health_connect`, `garmin` | `mobile_android/health_connect_importer.dart`, `mobile_android/strava_importer.dart`, `apps/web/src/lib/garmin-zip.ts` | — | Optional, audit-only | No UI consumer today; keep writing it so future audit tooling has a source. |
| `imported_at` | `string` (ISO 8601) | Same as above | — | Optional, audit-only | Client wall-clock time of the import, not the original run time. |
| `health_connect_type` | `string` — a `HealthWorkoutActivityType` enum name | `mobile_android/health_connect_importer.dart` | — | Optional, audit-only | Preserves the raw Health Connect type even after `activity_type` narrows it to our enum. Useful if we ever want to recover the original classification. |
| `strava_activity_type` | `string` — raw Strava activity type (e.g. `Run`, `Hike`, `Ride`) | `mobile_android/strava_importer.dart` | — | Optional, audit-only | Same rationale as `health_connect_type`. |
| `strava_id` | `string` — Strava activity id | `apps/web/src/lib/strava-zip.ts` | `apps/web/src/lib/strava-zip.ts` (dedupe check) | Optional | Used by the web Strava ZIP importer to skip already-imported activities. |
| `garmin_id` | `string` — Garmin file id (`<time_created>-<serial>`) | `apps/web/src/lib/garmin-zip.ts` | `apps/web/src/lib/garmin-zip.ts` (dedupe check) | Optional | Used by the web Garmin ZIP importer to skip already-imported activities. |
| `max_bpm` | `number` — peak heart rate in BPM for the run | `apps/web/src/lib/garmin-zip.ts` | — | Optional, audit-only | Written by the Garmin ZIP importer when `maxBpm` is present in the parsed FIT data. No UI consumer yet. |
| `source_file` | `string` — original filename from the ZIP archive | `apps/web/src/lib/garmin-zip.ts` | — | Optional, audit-only | Written by the Garmin ZIP importer for both FIT and GPX files. Audit/debug aid. |
| `elevation_m` | `number` — total elevation gain in metres | `apps/web/src/lib/data.ts` (`saveRun`, via Strava and Garmin importers) | — | Optional, audit-only | Stored here because the `runs` table has no `elevation_m` column; that column exists only on `routes`. Populated for Strava and Garmin imports when ascent data is present. |

### Parkrun fields

Written by the `parkrun-import` Edge Function when scraping a runner's results page. See [../apps/backend/CLAUDE.md](../apps/backend/CLAUDE.md) § Edge Functions.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `event` | `string` — the parkrun event name (e.g. `Richmond`, `Bushy Park`) | `apps/backend/supabase/functions/parkrun-import/index.ts` | `apps/web/src/routes/runs/+page.svelte` | Required when `source = 'parkrun'` | Displayed on the web runs list as a source badge. |
| `position` | `number` — finishing position in the event | Same | `apps/web/src/routes/runs/+page.svelte` | Required when `source = 'parkrun'` | Displayed next to the event name on the web runs list. |
| `age_grade` | `string` — age-graded percentage as a string with `%` suffix (e.g. `"54.23%"`) | Same | — | Optional, audit-only | No UI consumer today. Kept so future analytics can use it. |
| `avg_bpm` | `number` — mean heart rate in BPM across the run | `apps/watch_ios/WatchApp/ContentView.swift` (forwards `FinishedRun.averageBPM` from `HealthKitManager`); `apps/watch_wear/android/.../RunRecordingService.kt` (averages from `HeartRateMonitor`); `apps/mobile_android/lib/screens/run_screen.dart` (averages BLE chest-strap samples from `BleHeartRate`); `apps/mobile_android/lib/health_connect_importer.dart` (averages `HEART_RATE` samples inside the workout window) | `apps/web/src/routes/runs/[id]/+page.svelte` (post-run detail); `apps/mobile_android/lib/screens/run_detail_screen.dart`; watch apps' own post-run summaries | Optional; only present when HR was captured | Recording sources: Apple Watch → HealthKit `HKLiveWorkoutBuilder`; Wear OS → `androidx.health:health-services-client`; Android phone → BLE Heart Rate Service (0x180D) via `flutter_blue_plus`; Health Connect import → averages `HEART_RATE` samples from the importing app's writes. All clamp to 30–230 BPM before averaging to drop sensor noise. **Scalar companion:** per-point BPM lives on the track (`track[].bpm`, not `runs.metadata`) — see [api_database.md](api_database.md#runs) for the shape. Web's run-detail HR-zone panel uses `track[].bpm` when populated and falls back to this scalar when only `avg_bpm` is set. The Dart `Waypoint` model carries an optional `bpm` field too, so `apps/mobile_android` renders the same time-weighted breakdown for runs whose track arrived with per-point HR (Strava, FIT/TCX, future watch streams). The watch-ingest decoder (`apps/mobile_*/lib/watch_ingest_queue.dart`) extracts per-point `bpm` off each waypoint that arrives from the watch payload, so an Apple Watch that streams HR samples through the phone bridge preserves the trace end-to-end. No mobile recorder writes per-point `bpm` yet — added when the recorder gains streaming-HR support. |

### Training plan linkage

Written when a run was recorded under a structured plan workout. See [workout_execution.md](workout_execution.md) for the full loop.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `plan_workout_id` | `string` (uuid) — the linked `plan_workouts` row | `mobile_android/lib/screens/run_screen.dart` (`_finishRun`, when a workout was active) | `apps/web/src/routes/runs/[id]/+page.svelte`, `mobile_android/lib/screens/run_detail_screen.dart` (both surface a "Workout" section when set) | Optional | Presence implies an explicit link — the auto-matcher (`autoMatchRunToPlanWorkout`) skips runs that already carry it. |
| `workout_step_results` | `array<{ step_index: int, kind: string, rep_index?: int, rep_total?: int, target_distance_m: double, actual_distance_m: double, target_pace_sec_per_km: int, actual_pace_sec_per_km: int?, duration_s: int, status: 'completed' \| 'skipped' }>` | `mobile_android/lib/screens/run_screen.dart` (`_finishRun`, from `WorkoutRunner.snapshotResults`) | `apps/web/src/routes/runs/[id]/+page.svelte`, `mobile_android/lib/screens/run_detail_screen.dart` (planned-vs-actual table) | Optional; always present alongside `plan_workout_id` | `actual_pace_sec_per_km` is null for steps where `actual_distance_m < ~10 m` (the user skipped almost immediately). One row per expanded step, including skipped ones, so readers can render the full planned sequence. |
| `workout_adherence` | `string` — `completed` \| `partial` \| `abandoned` | Same as above | Same as above | Optional; always present alongside `plan_workout_id` | `completed` = every step hit target ± tolerance. `partial` = any step skipped or more than 20 % short. `abandoned` = user explicitly abandoned mid-workout. |

### Internal / runtime-only

Keys that carry transient or platform-internal state. Treat these as implementation detail — do not expose them in the UI, and do not depend on them across platforms.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `last_modified_at` | `string` (ISO 8601) | `mobile_android/lib/local_run_store.dart` (on every `update()`); `watch_wear/.../WatchRunMetadata.kt` (on every direct upload) | `mobile_android/lib/local_run_store.dart` (newer-wins conflict resolution during sync); `mobile_android/lib/screens/runs_screen.dart` (delta-fetch `updatedSince` filter, `metadata->>'last_modified_at' > since`) | **Required** on every cloud-bound row — without it, the row is invisible to mobile's delta refresh after the first ever fetch | Set by the local store on Android/iOS and by the watch encoder on Wear OS direct uploads. The Apple-Watch-via-WCSession path inherits the stamp from `LocalRunStore.save()` after the phone ingests. |
| `recovered_from_crash` | `bool` — always `true` when present | `mobile_android/lib/main.dart` (app launch, when it detects an in-progress crash-time save) | — | Optional, audit-only | Marks a run that was reconstructed from the incremental-save snapshot after a crash mid-recording. No UI consumer yet — would be useful for a "we saved what we had" toast. |
| `in_progress_saved_at` | `string` (ISO 8601) | `mobile_android/lib/screens/run_screen.dart` (periodic incremental save during recording) | — | Optional, audit-only | Timestamp of the last incremental save. Cleared when the run is finalised. Survival indicator for crash recovery. |
| `in_progress` | `bool` — `true` only on the live-broadcast stub | `packages/api_client/lib/src/api_client.dart` (`beginLiveBroadcast`) — written into the stub `runs` row created when the user taps "Share live link" so the FK + RLS on `live_run_pings` accept inserts before the real run is saved | — | Optional, audit-only | The stub is overwritten on stop by `saveRun`'s upsert (which omits this key), so the value flips from `true` to absent for finished runs. Useful for distinguishing stubs in forensics; readers should treat absence as the normal case. |
| `manual_entry` | `bool` — always `true` when present | `mobile_android/lib/screens/add_run_screen.dart` | — | Optional, audit-only | Marks a run created via the "Add run" form rather than a live recording or an import. Present on runs with an empty `track` and a `routeId` that the user picked by hand. No UI consumer yet — useful when computing PBs, since a user-estimated time shouldn't outrank a GPS-recorded one. |
| `indoor_estimated` | `bool` — always `true` when present | `mobile_android/lib/screens/run_screen.dart` (`_stop`, `_saveInProgress`) when `_everHadGpsFix` stayed false and the pedometer produced distance | — | Optional, audit-only | Marks a treadmill / indoor run where `distanceMetres` came from `steps × stride` rather than GPS. Pairs with `distance_source = "pedometer"`. PB calculations should probably exclude these. |
| `distance_source` | `string` — `"pedometer"` (extendable) | `mobile_android/lib/screens/run_screen.dart` when saving an indoor-estimated run | — | Optional, audit-only | Explicit tag for *where* the distance came from when it isn't GPS. Present together with `indoor_estimated`. Leaving room for future sources (e.g. `"strava_import"`, `"user_entered"`) without adding new booleans. |

### Client-side synthetic

**Not persisted.** These keys exist only in in-memory `Run.metadata` maps after deserialisation, added by the client to work around API ergonomics. Do not write them in a `saveRun` call — the DB round-trip will strip them from anywhere that matters, but they'll leak into re-uploads if you're not careful.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `track_url` | `string` — Storage path like `{user_id}/{run_id}.json.gz` | `packages/api_client/lib/src/api_client.dart` → `_runFromRow` (copies the `runs.track_url` column into `metadata`) | `packages/api_client/lib/src/api_client.dart` → `fetchTrack(run)`, `mobile_android/lib/screens/run_detail_screen.dart` | Optional; present whenever the run has an uploaded track | This is a **cross-wiring trick**. The real `runs.track_url` column is not exposed on the Dart domain `Run` class, so `_runFromRow` stuffs the value into `metadata['track_url']` so that downstream callers can pass a `Run` back to `fetchTrack` without also threading the URL separately. If you refactor `Run` to have a real `trackUrl` field, delete this key from the synth code AND from any reader — otherwise both paths will silently diverge. |

---

## Conventions

When adding a new metadata key:

1. **Use `snake_case`.** Every existing key does. Don't mix camelCase in.
2. **Prefer a real column.** `metadata` is for data we're not ready to schema-ise yet, or that's genuinely free-form (like `notes`). If a new field is shaped and queried, it belongs in its own column with a migration.
3. **Name it for what it is, not what writes it.** `activity_type` not `recorded_activity_type`. The writer is obvious from the data flow.
4. **Be explicit about absence.** "Optional" is the default. If a reader can't tolerate the key being missing, call that out in the notes column and ask whether it should be a real NOT NULL column instead.
5. **Update this file and remove the key here when you remove it from code.** The schema generators can't do this for you.

## Public-safe vs owner-only classification

When a run's `is_public = true`, the row's `metadata` jsonb travels alongside it. The `public_runs` view (migration `20260626_001_public_runs_view.sql`) projects a *redacted* version that drops the owner-only keys before they cross the wire. The classification:

**Public-safe** (kept by the view's projection):

- `activity_type`, `steps`, `laps` — core run properties (cadence is derived client-side from `steps / moving_time_minutes`, not stored)
- `title`, `notes` — user-editable display fields
- `event`, `position`, `age_grade` — parkrun fields
- `avg_bpm` — scalar HR
- `elevation_m` — total elevation gain

**Owner-only** (stripped by the view's projection — denylist in the migration body):

- `imported_from`, `imported_at`, `health_connect_type`, `strava_activity_type`, `strava_id`, `garmin_id`, `source_file`, `max_bpm` — import provenance / third-party-id-cross-walks
- `plan_workout_id`, `workout_step_results`, `workout_adherence` — training-plan linkage; leaks the runner's structured-workout paces and adherence
- `last_modified_at` — sync-state internal; leaks device-upload cadence
- `recovered_from_crash`, `in_progress_saved_at`, `in_progress`, `manual_entry`, `indoor_estimated`, `distance_source` — recorder internals

When you add a new key, classify it explicitly — and update the strip list in `20260626_001_public_runs_view.sql` if it lands on the owner-only side. The seed assertions in `apps/backend/supabase/seed.sql` for `public_runs` exercise the projection; an unclassified key that's accidentally dropped (or accidentally exposed) will fail the seed.

## Enforcement

**Dart side (mobile + packages):** `apps/mobile_android/test/metadata_registry_test.dart` greps every `.dart` file under `apps/mobile_android/lib/`, `packages/api_client/lib/`, and `packages/run_recorder/lib/` for subscript access (`metadata['xxx']`) and map-literal writes (`metadata: { 'xxx': ... }`), and asserts every key is a row in this file. Runs in the `test-packages` CI job — a PR that adds an unregistered key fails there.

**Web, watch_wear, watch_ios:** no equivalent guard yet. Parity tests on those platforms are a TODO — until then, this file plus PR review is the coordination point and the Dart-side discipline catches most cross-platform drift because the phone is the dominant writer.

## Known issues

- **Web doesn't write any metadata today.** Route builder, integrations management, and account settings never touch the key. If the web gains an "edit run" page, it needs to know every key in this registry and which ones a user can edit.
- **Apple Watch has its own Supabase client** (`apps/watch_ios/WatchApp/SupabaseService.swift`) that does not share this registry. Any metadata keys written from the watch have to be manually reconciled with this file. See [../apps/watch_ios/CLAUDE.md](../apps/watch_ios/CLAUDE.md).
- **No runtime validation.** Nothing checks that an incoming `metadata` blob matches this registry. The check is purely social — this doc — plus whatever type assertions the reader writes at the call site. The Dart-side CI guard above is a static analogue that at least catches writes that drop into a grep.
- **`steps` wire type is unverified.** The Android code writes it as an `int` from the pedometer; the web reader indexes it as-is. `Json` on both clients will accept either a number or a string, so if a writer ever coerces it, both platforms will silently drift. Worth a future audit — or a cast at the write site.
