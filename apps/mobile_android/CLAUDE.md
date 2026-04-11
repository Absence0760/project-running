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
- Offline-first: runs save to `LocalRunStore` → sync on connectivity change / app foreground → reconcile via `last_modified_at` timestamps.
- Strava ZIP import and Health Connect import. FIT files are skipped (GPX/TCX only).
- Disk-backed tile cache.
- Personal bests, weekly goals, edit title/notes, share as GPX, delete.

**Stubbed or deferred:**
- OAuth sign-in for providers other than Google (Apple, Strava, parkrun) — UI removed from Settings in the meantime. See the "Deferred from Phase 1" section in `roadmap.md`.
- WorkManager-based periodic background sync (current sync covers foreground + connectivity change only).
- Heart-rate from Bluetooth devices.
- History filter by activity type (date-range filter shipped).

## Files

**Screens** (`lib/screens/`):
- `onboarding_screen.dart` — first-launch permission ask
- `sign_in_screen.dart` — email/password + Google sign-in
- `home_screen.dart` — the dashboard + nav tabs host
- `dashboard_screen.dart` — weekly mileage, PBs, goal progress
- `history_screen.dart` — run list with sorting
- `run_detail_screen.dart` — single run map + stats + splits + elevation
- `import_screen.dart` — GPX / KML / KMZ / GeoJSON / TCX file picker
- `routes_screen.dart` — saved routes list
- `route_detail_screen.dart` — route map + metadata
- `settings_screen.dart` — preferences, integrations, data export

**Top-level (`lib/`):**
- `main.dart` — app entry, Supabase init, service wiring
- `sync_service.dart` — bulk-sync button, auto-sync on connectivity/foreground, conflict resolution
- `local_run_store.dart` / `local_route_store.dart` — `ChangeNotifier`-style on-disk stores
- `preferences.dart` — SharedPreferences wrapper for settings
- `tile_cache.dart` — disk-backed map tile cache glue
- `audio_cues.dart` — TTS for splits and pace alerts
- `run_stats.dart` — pace/distance/split formatting helpers (tested)
- `goals.dart` — `RunGoal` model + pure `evaluateGoal` for dashboard goal cards (tested)
- `health_connect_importer.dart` / `strava_importer.dart` — bulk importers
- `mock_data.dart` — fallback data when Supabase returns nothing (dev only)
- `widgets/live_run_map.dart` — live map with route overlay, off-route banner
- `widgets/collapsible_panel.dart` — the run screen's expandable stats panel
- `widgets/run_share_card.dart` — portrait share card + modal sheet; captures a PNG via `RepaintBoundary.toImage` and hands it to `share_plus`
- `widgets/goal_editor_sheet.dart` — modal bottom sheet for creating/editing/deleting a `RunGoal` (type + period + target)

## Dart analyzer policy — treat `info` as noise

`dart analyze` on this package reports ~76 issues. All but three are `info`-level:

- `always_use_package_imports` — pervasive; every screen imports relative. Not being fixed in a sweep.
- `deprecated_member_use` — mostly `withOpacity` → `withValues`. Deferred until we do a theme pass.
- `dangling_library_doc_comments`, `unnecessary_brace_in_string_interps`, `unnecessary_import` — stragglers.

The three `warning`-level entries (unused `theme` local, unused `_avgPaceSecPerKm` field, unused `flutter/foundation.dart` import) are also acknowledged tech debt, not regressions.

**Do not waste a turn on these.** Only act on `info`/`warning` if your change touched that specific file. The CI `test-packages` job runs `melos run analyze` via `dart analyze`; the exit code is ignored for this package (per roadmap intent, not per CI config — verify before relying on this).

## Tests

Three test files in `test/`:
- `run_stats_test.dart` — 8 tests for pace / distance / split formatting helpers
- `local_run_store_test.dart` — 14 tests exercising the store with a `Directory.systemTemp` tempDir injection
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
