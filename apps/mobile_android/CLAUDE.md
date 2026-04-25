# mobile_android — AI session notes

The most mature Flutter target in the monorepo. Almost every "Android" checkbox in [../../docs/roadmap.md](../../docs/roadmap.md) Phase 1 is ticked. Treat this app as the reference implementation — when in doubt about what a feature *should* look like on mobile, look here first.

## Stack

- **Flutter** stable, Dart 3.x
- **State management:** `StatefulWidget` + `setState` throughout. Stores (`LocalRunStore`, `LocalRouteStore`, `Preferences`) are plain `ChangeNotifier`-style singletons that screens subscribe to via `addListener` in `initState` and unsubscribe in `dispose`. No Provider, no Riverpod, no Bloc. If you add a new screen, follow the same pattern — do not introduce a DI framework.
- **Hot-path exception — `run_screen.dart`:** the per-second `_onSnapshot` handler does NOT call `setState`. It updates mirror fields (for `_saveInProgress`, `_refreshLockScreenNotification`, and the `_formattedX` getters) then publishes to a `ValueNotifier<_LiveStats>`. The affected subtrees (map, off-route banner, route-remaining badge, stats panel) are wrapped in `ValueListenableBuilder`, so the rest of the recording tree (activity chips, GPS-lost / permission-revoked banners, layout) doesn't rebuild at GPS rate. If you add a new stat that updates per snapshot, put it behind the notifier, not in a `setState`. Control-state changes (state transitions, manual pause, lap mark) still go through `setState` — that cadence is low enough that a full rebuild is fine.
- **Maps:** `flutter_map` with a MapLibre-compatible raster tile source. Cached via `flutter_map_cache` + `dio_cache_interceptor` for the disk-backed persistent tile cache. See [decisions.md § 8](../../docs/decisions.md) and [§ 5](../../docs/decisions.md).
- **Recording:** delegates to `packages/run_recorder` — state machine, GPS filter chain, auto-pause, off-route detection, all live there. This app holds the UI and the screens; the recording logic is a package so the iOS and Wear OS apps can eventually reuse it.
- **Auth / backend:** `packages/api_client` for Supabase. Google Sign-In is wired via the native `google_sign_in` package → exchanges the ID token through `ApiClient.signInWithGoogleIdToken`. Apple Sign-In scaffolded but not wired on Android (see the deferred list in `roadmap.md`).

## What's real vs stubbed

Nearly everything under Phase 1 "Android" in `roadmap.md` is implemented. Specifically:

**Live and working:**
- All of the `lib/screens/` files in the list below are wired to real data.
- Background GPS recording with foreground service, auto-pause, lap markers, wakelock.
- Offline-first: runs save to `LocalRunStore` → sync on connectivity change / app foreground / WorkManager periodic background sync → reconcile via `last_modified_at` timestamps.
- Strava ZIP import (GPX/TCX/FIT) and Health Connect import. Batch cloud push via `saveRunsBatch`.
- Disk-backed tile cache.
- Personal bests, weekly goals, edit title/notes, share as GPX, delete.
- Runs filter by activity type (run/walk/cycle/hike filter chips).
- Configurable split interval for voice cues (Settings > Split interval).
- Advanced GPS mode (Settings > Advanced GPS) for higher accuracy under tree cover.

**Stubbed or deferred:**
- OAuth sign-in for providers other than Google (Apple, Strava, parkrun) — UI removed from Settings in the meantime. See the "Deferred from Phase 1" section in `roadmap.md`.

## Files

**Screens** (`lib/screens/`):
- `onboarding_screen.dart` — first-launch permission ask
- `sign_in_screen.dart` — email/password + Google sign-in
- `sign_up_screen.dart` — email/password registration + Google sign-in, linked from sign-in
- `home_screen.dart` — the dashboard + nav tabs host
- `run_screen.dart` — the primary recording screen (countdown, live stats, route overlay, finish summary); hosts the recorder state machine and all the hardening described in [../../docs/run_recording.md](../../docs/run_recording.md)
- `dashboard_screen.dart` — weekly mileage, PBs, goal progress
- `runs_screen.dart` — run list with sorting, FAB opens `add_run_screen`
- `add_run_screen.dart` — manual-entry form: date/time + duration + distance + optional saved route
- `run_detail_screen.dart` — single run map + stats (primary + secondary) + interactive elevation/pace chart + best efforts + pace-bar splits + laps
- `import_screen.dart` — GPX / KML / KMZ / GeoJSON / TCX file picker
- `routes_screen.dart` — saved routes list
- `route_detail_screen.dart` — route map + metadata + reviews + public/private toggle
- `period_summary_screen.dart` — browsable weekly/monthly summary with stats, run list, and share (text or screenshot)
- `explore_routes_screen.dart` — search and browse public routes with filters (distance, surface), save to library
- `settings_screen.dart` — preferences, integrations, data export
- `clubs_screen.dart` — Browse / My clubs, 6th bottom-nav tab
- `club_detail_screen.dart` — feed (threaded), upcoming events, members, join/leave
- `event_detail_screen.dart` — per-instance RSVP + admin update composer + admin-only Race control card (Arm / Fire Go / End / Cancel, gated on `ClubView.isRaceDirector`, backed by `SocialService.armRace` / `startRace` / `endRace`)
- `plans_screen.dart` — Training plans list (accessed from Run tab idle button)
- `plan_new_screen.dart` — Wizard with live pace + week-outline preview
- `plan_detail_screen.dart` — Hero + progress ring + today card + week grid
- `workout_detail_screen.dart` — Structured-interval breakdown + per-kind advice

**Top-level (`lib/`):**
- `main.dart` — app entry, Supabase init, service wiring; calls `WearAuthBridge().attach(...)` so the paired Wear OS watch inherits the Supabase session
- `sync_service.dart` — bulk-sync button, auto-sync on connectivity/foreground, conflict resolution
- `wear_auth_bridge.dart` — forwards Supabase session changes to the paired Wear OS watch via a `run_app/wear_auth` method channel (native `WearAuthBridge.kt` under `android/app/src/main/kotlin/com/betterrunner/app/` writes to the Wearable Data Layer)
- `run_notification_bridge.dart` — replaces geolocator's "Run in progress" foreground-service notification with live time/distance/pace (native `RunNotificationBridge.kt` reposts on the same channel id so the lock-screen row is live instead of static)
- `background_sync.dart` — WorkManager periodic background sync (hourly, network-connected)
- `local_run_store.dart` / `local_route_store.dart` — `ChangeNotifier`-style on-disk stores
- `preferences.dart` — SharedPreferences wrapper for settings
- `tile_cache.dart` — disk-backed map tile cache glue
- `audio_cues.dart` — TTS for splits and pace alerts. Pace alerts are paired with a `HapticFeedback.heavyImpact()` pulse in `run_screen.dart` (two pulses for "speed up", one for "slow down") so the cue registers with headphones paused
- `run_stats.dart` — pace/distance/split formatting helpers (tested)
- `goals.dart` — `RunGoal` model + pure `evaluateGoal` for dashboard goal cards (tested)
- `route_simplify.dart` — Ramer–Douglas–Peucker track simplifier used when saving a run as a route (tested)
- `health_connect_importer.dart` / `strava_importer.dart` — bulk importers
- `mock_data.dart` — fallback data when Supabase returns nothing (dev only)
- `widgets/live_run_map.dart` — live map with route overlay, off-route banner, NRC-style pace heatmap (when `activity` is non-null, falls through to the legacy single gradient polyline otherwise)
- `widgets/pace_segments.dart` — pure helpers `buildPaceSegments` / `paceBucketForSpeed` / `ageBandFor`. Pace-coloured, age-faded segment builder for the live track. No Flutter state — unit-tested in `test/pace_segments_test.dart`
- `widgets/collapsible_panel.dart` — the run screen's expandable stats panel
- `widgets/run_share_card.dart` — portrait share card + modal sheet; captures a PNG via `RepaintBoundary.toImage` and hands it to `share_plus`
- `widgets/goal_editor_sheet.dart` — modal bottom sheet for creating/editing/deleting a `RunGoal` (type + period + target)
- `widgets/upcoming_event_card.dart` — Run tab idle-state card shown when the user has a `going` RSVP within 48h
- `widgets/todays_workout_card.dart` — Run tab idle-state priority card when an active plan has a workout scheduled today
- `widgets/plan_calendar.dart` — Dart port of `apps/web/src/lib/components/PlanCalendar.svelte`. Month-by-month grid with prev/next chevrons, Monday-first DOW row, kind-coloured cells, completed-tick. Renders on `plan_detail_screen` between the today card and the week cards.
- `widgets/workout_edit_sheet.dart` — modal bottom sheet for inline edit of a `PlanWorkoutRow` (kind, target distance, target pace, notes). Opened via the pencil button or long-press on a workout row in `plan_detail_screen`; saves through `TrainingService.updateWorkout`.
- `widgets/workout_execution_band.dart` — top-of-map overlay shown while a structured workout is running. Reads through a `ValueListenable<WorkoutBandState>` so transitions / progress events don't trigger a Stack-wide rebuild. Surfaces the current step label, pace pip with signed delta, progress bar + remaining metres, and Skip / Abandon controls.
- `widgets/workout_review_section.dart` — post-run planned-vs-actual table on `run_detail_screen`. Reads `runs.metadata.workout_step_results` + `workout_adherence`; hidden when those keys are absent. Mirrors the web `/runs/[id]` Workout section. Pure widget + helpers (`paceDeltaOf`, `formatPace`) — no controller state, widget-tested.
- `widgets/fitness_card.dart` — the dashboard's Fitness card (VO₂ max + VDOT + qualifying-run count, then CTL / ATL / TSB, then a recovery-advice line). Renders nothing when `qualifyingRunCount == 0`. Reuses `lib/fitness.dart` for the math; widget-tested.
- `social_service.dart` — `ChangeNotifier` wrapping all Supabase calls for clubs / events / posts
- `training_service.dart` — `ChangeNotifier` wrapping Supabase calls for training plans + workouts
- `ble_heart_rate.dart` — BLE chest-strap GATT client for live BPM stream (tested); wires into the run screen via `BleHeartRate.stream`
- `hr_zones.dart` — pure helpers `hrZoneBreakdown` (time-weighted, 30 s pause cap) and `bpmStatsOf`. No Flutter state — unit-tested. Backs the HR-zone panel on `run_detail_screen` for runs whose track carries per-point `bpm` (Strava, FIT/TCX imports, watch recorders).
- `fitness.dart` — Dart port of `apps/web/src/lib/fitness.ts` (VDOT / VO₂ max from Daniels' formula, EWMA-based ATL/CTL/TSB, `recoveryAdvice`). Pure functions; backs the dashboard's Fitness card. Keep in sync with the web module.
- `race_controller.dart` — live-race orchestration: pings spectator feed, auto-submits finisher time to the leaderboard
- `settings_sync.dart` — reads/writes the user-preferences row so settings roam across devices
- `backup.dart` — export + import of the local run / route stores (troubleshooting + device-swap path)
- `recurrence.dart` — Dart port of `apps/web/src/lib/recurrence.ts`, keep in sync
- `training.dart` — Dart port of `apps/web/src/lib/training.ts` (VDOT, Riegel, plan generator); keep in sync, 17-test mirror suite in `test/training_test.dart`

## Dart analyzer policy — treat `info` as noise

`dart analyze` on this package reports ~90 issues. **Every remaining entry is `info`-level** — the package is clean of `warning`/`error` as of this pass. The noise buckets:

- `always_use_package_imports` — pervasive; every screen imports relative. Not being fixed in a sweep.
- `deprecated_member_use` — mostly `withOpacity` → `withValues` and `share_plus` v13 (`Share.shareXFiles` → `SharePlus.instance.share`). Deferred until we do a theme/deps pass.
- `dangling_library_doc_comments`, `unnecessary_brace_in_string_interps`, `unnecessary_import` — stragglers.

**Do not waste a turn on these.** Only act on `info` if your change touched that specific file. **Do act on any new `warning`/`error`** — the bar is "zero warnings", so a fresh one is a regression your change introduced. The CI `test-packages` job runs `melos run analyze` via `dart analyze`; the exit code is ignored for this package (per roadmap intent, not per CI config — verify before relying on this).

## Tests

Test files in `test/`:
- `run_stats_test.dart` — 13 tests: moving-time helpers + `fastestWindowOf` rolling-window scanner
- `local_run_store_test.dart` — 17 tests: store persistence, sync state, in-progress save/load, deleteMany batch, edge cases
- `period_summary_test.dart` — 23 tests: period boundary computation, stats aggregation, share text generation, formatting helpers
- `goals_test.dart` — 20 tests: goal evaluation (distance/time/pace/run-count, weekly/monthly, multi-target)
- `route_simplify_test.dart` — 8 tests: Ramer-Douglas-Peucker track simplification
- `training_test.dart` — 18 tests: VDOT, Riegel, pace derivation, plan generation (mirrors `apps/web/src/lib/training.test.ts`)
- `ble_heart_rate_test.dart` — 9 tests: BLE HR characteristic 0x2A37 parser (8-bit/16-bit BPM, edge cases)
- `pace_segments_test.dart` — 15 tests: pace-bucket clamping, activity-specific scaling, age-band partitioning, coalescing, vertex-sharing continuity, timestamp-less fallback — backs the NRC-style pace heatmap in `widgets/pace_segments.dart`
- `hr_zones_test.dart` — 8 tests: time-weighted vs sample-count fallback, the 30 s pause cap, custom cutoffs, malformed-input rejection, `bpmStatsOf` aggregation
- `fitness_test.dart` — 17 tests: VDOT range checks (5k, marathon), `currentVdot` 90-day window + qualifying-source filter, `runTss` Coggan reference, EWMA training-load smoke, `recoveryAdvice` thresholds, `computeSnapshot` end-to-end
- `plan_calendar_test.dart` — 3 widget tests: month rendering with kind labels, chevron navigation, completed-tick presence
- `workout_execution_band_test.dart` — 6 widget tests: empty render, header / step counter / remaining-metres formatting, Skip + Abandon callbacks, complete + abandoned shells, em-dash for null pace
- `workout_review_section_test.dart` — 11 tests for `widgets/workout_review_section.dart`: hidden when metadata absent / empty / null, header + adherence pill rendered with one row per step, kind-specific labels (Warmup / Rep i/n / Recovery i/n / Cooldown), strikethrough + "skip" label for skipped steps, em-dash + neutral colour when actual pace is null, signed `+/−Ns` delta label, and tone classification thresholds (`on` / `amber` / `off` against the 10 s tolerance) plus `formatPace` formatting
- `fitness_card_test.dart` — 5 widget tests for `widgets/fitness_card.dart`: hidden with no runs, hidden when no runs qualify (sub-3 km / sub-5 min), populated card renders all six stat labels + the recovery-advice icon + the qualifying-run count, em-dash placeholder when VDOT can't be computed but qualifying runs exist, plus a smoke test for the `FitnessStat` value-over-label primitive
- `metadata_registry_test.dart` — 2 tests: (1) every `runs.metadata` key referenced in Dart source is registered in [docs/metadata.md](../../docs/metadata.md) — catches cross-client drift like `metadata.activityType` vs `metadata.activity_type` at CI time; (2) a soft "dead-key" info log surfacing registered keys that no Dart reader touches (may be web/watch/EF-only). Fails on unknown-key writes; purely informational on the reverse direction.
- `recurrence_test.dart` — 8 tests: weekly / biweekly / monthly `expandInstances`, hour/minute local-tz preservation, `count` cap, `until` cap, non-recurring single-instance
- `importer_external_id_test.dart` — 2 tests: `StravaImporter` ZIP import produces `strava:<id>` prefix; source-text guard confirms `HealthConnectImporter` uses `healthconnect:<uuid>` prefix
- `architecture_guards_test.dart` — 20 tests: static source-level assertions that pin in place the efficiency + layering optimizations (no `setState` in `_onSnapshot`, `markSynced` doesn't rewrite the run file, sync paths use `saveRunsBatch`, `ErrorWidget.builder` override present, RunNotificationBridge pins geolocator channel constants, plus the `LocalRunStore` newer-wins guards — `save`/`update` must stamp `last_modified_at`, `saveFromRemote` must not — added in the Apr 2026 data-sync hardening pass). **When one of these fails, read the `reason:` before rubber-stamping a fix** — a failure means a recent change reversed an optimization we deliberately codified.
- plus `run_recorder`'s own tests in `packages/run_recorder/test/` — 17 behavioural + 7 guards + 13 `workout_runner_test.dart` (step expansion, auto-advance, halfway / last-50m progress, skip / abandon, pace-adherence wayBehind, results JSON shape)

See [../../docs/testing.md](../../docs/testing.md) for how to run them and the patterns they use. Widget tests exist for `FitnessCard`, `WorkoutExecutionBand`, `WorkoutReviewSection`, and `PlanCalendar` (14 `testWidgets` calls total); all other screens and widgets are uncovered.

## Running it locally

See [local_testing.md](local_testing.md). Short version: `cd apps/mobile_android && flutter run -d <device>`. The seed user in local Supabase is `runner@test.com` / `testtest`.

## Before reporting a task done

- Run `dart analyze` on this package and confirm no new `warning`/`error` level issues. `info` are OK per policy above.
- Run `flutter test` for the package if you touched anything under `test/` or the files it covers.
- If you changed anything user-visible, update the corresponding "Android" checkbox in `roadmap.md`.
- If you introduced a new screen, add it to the file list above.
- If you hit a new gotcha, add it here so the next session doesn't re-hit it.
