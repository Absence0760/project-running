# `runs.metadata` key registry

The `runs.metadata` column is `jsonb` — a schema-less bag that any client can write into. Schema codegen ([schema_codegen.md](schema_codegen.md)) cannot catch drift in here: a mobile client can write `metadata.activity_type` and a web client can read `metadata.activityType` and nothing in the type system notices. This file is the coordination point.

**Rule:** If you add, rename, remove, or change the shape of a metadata key, update this file in the same change. If you're reading a key that isn't listed here, add it. If you find a key in the registry that isn't used anywhere in code, delete it.

---

## Key registry

Each row: what the key is, its shape, which platforms *write* it, which platforms *read* it, and whether the client must tolerate its absence. "Optional" means "a consumer must be safe with it missing." All keys are optional unless explicitly required.

### Core run properties

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `activity_type` | `string` — one of `run`, `walk`, `hike`, `cycle` | `mobile_android/screens/run_screen.dart` (recording), `mobile_android/health_connect_importer.dart` | `mobile_android` (dashboard, history, run detail), `apps/web/src/routes/runs/[id]/+page.svelte` | Optional; defaults to `run` when absent | The Android recorder writes this on every save. Health Connect imports map through `_mapWorkoutType`. Parkrun imports and older `app`-source runs may not have it. |
| `steps` | `int` (stringified on the wire? — **investigate**) | `mobile_android/screens/run_screen.dart` (pedometer) | `apps/web/src/routes/runs/[id]/+page.svelte` | Optional; only present when pedometer data is available | Only written when `_steps > 0`. Android omits the key entirely if the pedometer never fired. |
| `laps` | `array` of `{ index: int, start_offset_s: int, distance_m: double, duration_s: int }` | `packages/run_recorder/lib/src/run_recorder.dart` (final save only) | `mobile_android/screens/run_detail_screen.dart` | Optional; only present if the runner marked laps | The recorder sets `metadata = null` entirely when `_laps.isEmpty`, so readers must check for both a null `metadata` and a missing `laps` key. |

### User-editable fields

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `title` | `string` — user-entered display title | `mobile_android/screens/run_detail_screen.dart` (edit dialog), `mobile_android/strava_importer.dart` (default from Strava activity name) | `mobile_android/screens/run_detail_screen.dart` | Optional; falls back to the formatted start date when absent | Strava imports default to the Strava activity name or `"Strava import"`. Not currently editable on the web — only Android. |
| `notes` | `string` — free-form user notes | `mobile_android/screens/run_detail_screen.dart` (edit dialog) | `mobile_android/screens/run_detail_screen.dart` | Optional; empty string when absent | Not currently read on the web. |

### Import provenance

Set by importers when bulk-loading runs from third parties. None of these are read by any current UI — they're audit/debug data.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `imported_from` | `string` — one of `strava`, `health_connect` | `mobile_android/health_connect_importer.dart`, `mobile_android/strava_importer.dart` | — | Optional | No consumer today; keep writing it so future audit tooling has a source. |
| `imported_at` | `string` (ISO 8601) | Same as above | — | Optional | Client wall-clock time of the import, not the original run time. |
| `health_connect_type` | `string` — a `HealthWorkoutActivityType` enum name | `mobile_android/health_connect_importer.dart` | — | Optional | Preserves the raw Health Connect type even after `activity_type` narrows it to our enum. Useful if we ever want to recover the original classification. |
| `strava_activity_type` | `string` — raw Strava activity type (e.g. `Run`, `Hike`, `Ride`) | `mobile_android/strava_importer.dart` | — | Optional | Same rationale as `health_connect_type`. |

### Parkrun fields

Written by the `parkrun-import` Edge Function when scraping a runner's results page. See [../apps/backend/CLAUDE.md](../apps/backend/CLAUDE.md) § Edge Functions.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `event` | `string` — the parkrun event name (e.g. `Richmond`, `Bushy Park`) | `apps/backend/supabase/functions/parkrun-import/index.ts` | `apps/web/src/routes/runs/+page.svelte` | Required when `source = 'parkrun'` | Displayed on the web runs list as a source badge. |
| `position` | `number` — finishing position in the event | Same | `apps/web/src/routes/runs/+page.svelte` | Required when `source = 'parkrun'` | Displayed next to the event name on the web runs list. |
| `age_grade` | `string` — age-graded percentage as a string with `%` suffix (e.g. `"54.23%"`) | Same | — | Optional | No UI consumer today. Kept so future analytics can use it. |
| `avg_bpm` | `number` — mean heart rate in BPM across the run | `apps/watch_ios/WatchApp/ContentView.swift` (forwards `FinishedRun.averageBPM` from `HealthKitManager`); `apps/watch_wear/lib/run_watch_screen.dart` (averages samples from `HeartRateService`, writes via `ApiClient.saveRun`) | `apps/watch_ios/WatchApp/ContentView.swift`, `apps/watch_wear/lib/run_watch_screen.dart` (both post-run summaries) | Optional; only present for watch-recorded runs where the HR sensor delivered samples | Apple Watch uses `HKLiveWorkoutBuilder` inside an `HKWorkoutSession`; Wear OS uses `androidx.health:health-services-client` (`MeasureClient` + `HEART_RATE_BPM`). Future web/mobile read sites can surface it alongside pace. |

### Internal / runtime-only

Keys that carry transient or platform-internal state. Treat these as implementation detail — do not expose them in the UI, and do not depend on them across platforms.

| Key | Shape | Writers | Readers | Required? | Notes |
|---|---|---|---|---|---|
| `last_modified_at` | `string` (ISO 8601) | `mobile_android/lib/local_run_store.dart` (on every `update()`) | `mobile_android/lib/local_run_store.dart` (newer-wins conflict resolution during sync) | Optional, but **required for correct sync conflict resolution** | Set by the local store, not by the user. The sync service compares this against the cloud row's value and keeps the newer one. Android-only today. |
| `recovered_from_crash` | `bool` — always `true` when present | `mobile_android/lib/main.dart` (app launch, when it detects an in-progress crash-time save) | — | Optional | Marks a run that was reconstructed from the incremental-save snapshot after a crash mid-recording. No UI consumer yet — would be useful for a "we saved what we had" toast. |
| `in_progress_saved_at` | `string` (ISO 8601) | `mobile_android/lib/screens/run_screen.dart` (periodic incremental save during recording) | — | Optional | Timestamp of the last incremental save. Cleared when the run is finalised. Survival indicator for crash recovery. |
| `manual_entry` | `bool` — always `true` when present | `mobile_android/lib/screens/add_run_screen.dart` | — | Optional | Marks a run created via the "Add run" form rather than a live recording or an import. Present on runs with an empty `track` and a `routeId` that the user picked by hand. No UI consumer yet — useful when computing PBs, since a user-estimated time shouldn't outrank a GPS-recorded one. |

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

## Known issues

- **Web doesn't write any metadata today.** Route builder, integrations management, and account settings never touch the key. If the web gains an "edit run" page, it needs to know every key in this registry and which ones a user can edit.
- **Apple Watch has its own Supabase client** (`apps/watch_ios/WatchApp/SupabaseService.swift`) that does not share this registry. Any metadata keys written from the watch have to be manually reconciled with this file. See [../apps/watch_ios/CLAUDE.md](../apps/watch_ios/CLAUDE.md).
- **No runtime validation.** Nothing checks that an incoming `metadata` blob matches this registry. The check is purely social — this doc — plus whatever type assertions the reader writes at the call site.
- **`steps` wire type is unverified.** The Android code writes it as an `int` from the pedometer; the web reader indexes it as-is. `Json` on both clients will accept either a number or a string, so if a writer ever coerces it, both platforms will silently drift. Worth a future audit — or a cast at the write site.
