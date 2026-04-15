# mobile_android — AI session notes

The most mature Flutter target in the monorepo. Almost every "Android" checkbox in [../../docs/roadmap.md](../../docs/roadmap.md) Phase 1 is ticked. Treat this app as the reference implementation — when in doubt about what a feature *should* look like on mobile, look here first.

## Stack

- **Flutter** stable, Dart 3.x
- **State management:** `StatefulWidget` + `setState` throughout. Stores (`LocalRunStore`, `LocalRouteStore`, `Preferences`) are plain `ChangeNotifier`-style singletons that screens subscribe to via `addListener` in `initState` and unsubscribe in `dispose`. No Provider, no Riverpod, no Bloc. If you add a new screen, follow the same pattern — do not introduce a DI framework.
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
- History filter by activity type (run/walk/cycle/hike filter chips).
- Configurable split interval for voice cues (Settings > Split interval).
- Advanced GPS mode (Settings > Advanced GPS) for higher accuracy under tree cover.

**Stubbed or deferred:**
- OAuth sign-in for providers other than Google (Apple, Strava, parkrun) — UI removed from Settings in the meantime. See the "Deferred from Phase 1" section in `roadmap.md`.
- Heart-rate from Bluetooth devices.

## Files

**Screens** (`lib/screens/`):
- `onboarding_screen.dart` — first-launch permission ask
- `sign_in_screen.dart` — email/password + Google sign-in
- `home_screen.dart` — the dashboard + nav tabs host
- `dashboard_screen.dart` — weekly mileage, PBs, goal progress
- `history_screen.dart` — run list with sorting, FAB opens `add_run_screen`
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
- `event_detail_screen.dart` — per-instance RSVP + admin update composer
- `plans_screen.dart` — Training plans list (accessed from Run tab idle button)
- `plan_new_screen.dart` — Wizard with live pace + week-outline preview
- `plan_detail_screen.dart` — Hero + progress ring + today card + week grid
- `workout_detail_screen.dart` — Structured-interval breakdown + per-kind advice

**Top-level (`lib/`):**
- `main.dart` — app entry, Supabase init, service wiring
- `sync_service.dart` — bulk-sync button, auto-sync on connectivity/foreground, conflict resolution
- `background_sync.dart` — WorkManager periodic background sync (hourly, network-connected)
- `local_run_store.dart` / `local_route_store.dart` — `ChangeNotifier`-style on-disk stores
- `preferences.dart` — SharedPreferences wrapper for settings
- `tile_cache.dart` — disk-backed map tile cache glue
- `audio_cues.dart` — TTS for splits and pace alerts
- `run_stats.dart` — pace/distance/split formatting helpers (tested)
- `goals.dart` — `RunGoal` model + pure `evaluateGoal` for dashboard goal cards (tested)
- `route_simplify.dart` — Ramer–Douglas–Peucker track simplifier used when saving a run as a route (tested)
- `health_connect_importer.dart` / `strava_importer.dart` — bulk importers
- `mock_data.dart` — fallback data when Supabase returns nothing (dev only)
- `widgets/live_run_map.dart` — live map with route overlay, off-route banner
- `widgets/collapsible_panel.dart` — the run screen's expandable stats panel
- `widgets/run_share_card.dart` — portrait share card + modal sheet; captures a PNG via `RepaintBoundary.toImage` and hands it to `share_plus`
- `widgets/goal_editor_sheet.dart` — modal bottom sheet for creating/editing/deleting a `RunGoal` (type + period + target)
- `widgets/upcoming_event_card.dart` — Run tab idle-state card shown when the user has a `going` RSVP within 48h
- `widgets/todays_workout_card.dart` — Run tab idle-state priority card when an active plan has a workout scheduled today
- `social_service.dart` — `ChangeNotifier` wrapping all Supabase calls for clubs / events / posts
- `training_service.dart` — `ChangeNotifier` wrapping Supabase calls for training plans + workouts
- `recurrence.dart` — Dart port of `apps/web/src/lib/recurrence.ts`, keep in sync
- `training.dart` — Dart port of `apps/web/src/lib/training.ts` (VDOT, Riegel, plan generator); keep in sync, 17-test mirror suite in `test/training_test.dart`

## Dart analyzer policy — treat `info` as noise

`dart analyze` on this package reports ~90 issues. **Every remaining entry is `info`-level** — the package is clean of `warning`/`error` as of this pass. The noise buckets:

- `always_use_package_imports` — pervasive; every screen imports relative. Not being fixed in a sweep.
- `deprecated_member_use` — mostly `withOpacity` → `withValues` and `share_plus` v13 (`Share.shareXFiles` → `SharePlus.instance.share`). Deferred until we do a theme/deps pass.
- `dangling_library_doc_comments`, `unnecessary_brace_in_string_interps`, `unnecessary_import` — stragglers.

**Do not waste a turn on these.** Only act on `info` if your change touched that specific file. **Do act on any new `warning`/`error`** — the bar is "zero warnings", so a fresh one is a regression your change introduced. The CI `test-packages` job runs `melos run analyze` via `dart analyze`; the exit code is ignored for this package (per roadmap intent, not per CI config — verify before relying on this).

## Tests

Test files in `test/` (80 tests total):
- `run_stats_test.dart` — 13 tests: moving-time helpers + `fastestWindowOf` rolling-window scanner
- `local_run_store_test.dart` — 16 tests: store persistence, sync state, in-progress save/load, edge cases
- `period_summary_test.dart` — 23 tests: period boundary computation, stats aggregation, share text generation, formatting helpers
- `goals_test.dart` — 20 tests: goal evaluation (distance/time/pace/run-count, weekly/monthly, multi-target)
- `route_simplify_test.dart` — 8 tests: Ramer-Douglas-Peucker track simplification
- plus `run_recorder`'s own 14 tests in `packages/run_recorder/test/`

See [../../docs/testing.md](../../docs/testing.md) for how to run them and the patterns they use. No widget tests exist on this app — that's the biggest coverage gap.

## Running it locally

See [../../docs/local_testing_android_app.md](../../docs/local_testing_android_app.md). Short version: `cd apps/mobile_android && flutter run -d <device>`. The seed user in local Supabase is `runner@test.com` / `testtest`.

## Before reporting a task done

- Run `dart analyze` on this package and confirm no new `warning`/`error` level issues. `info` are OK per policy above.
- Run `flutter test` for the package if you touched anything under `test/` or the files it covers.
- If you changed anything user-visible, update the corresponding "Android" checkbox in `roadmap.md`.
- If you introduced a new screen, add it to the file list above.
- If you hit a new gotcha, add it here so the next session doesn't re-hit it.
