# mobile_ios — AI session notes

Flutter iOS app. **Almost entirely a scaffold** — the hard work in Phase 1 has been done on Android first. See the Phase 1 section of [../../docs/roadmap.md](../../docs/roadmap.md) for the unchecked iOS-specific boxes (iOS background location, iOS GPX/KML parsing, etc.).

## Current state

Seven Dart files under `lib/`:

- `main.dart` — app entry, contains TODO comments for Supabase and local-database initialisation
- `mock_data.dart` — fallback UI data
- `screens/home_screen.dart`
- `screens/run_screen.dart`
- `screens/history_screen.dart`
- `screens/routes_screen.dart`
- `screens/settings_screen.dart`

The screens are minimal shells. There is no sync service, no local store, no importer, no tile cache, no audio cues, no widgets beyond what the screens render inline — compare with the Android file list in [../mobile_android/CLAUDE.md](../mobile_android/CLAUDE.md) to see the gap.

## What this app will look like when it's done

Structurally identical to `mobile_android` (same stack, same `StatefulWidget + setState` pattern, same dependence on `packages/run_recorder` and `packages/api_client`). Every module in `mobile_android/lib/` that isn't Android-specific is a candidate to hoist into a shared package before the iOS port — ask before doing that; the team may prefer copy-then-converge.

Android-specific concerns that don't port:
- Foreground service for background GPS → iOS uses `BGProcessingTask` + `CLLocationManager.allowsBackgroundLocationUpdates`.
- Health Connect importer → replaced by HealthKit importer.
- Google Sign-In flow → replaced by Apple Sign-In.
- Disk-backed tile cache → the same `flutter_map_cache` + `dio_cache_interceptor` combo works.

## Recommended approach for a new task here

1. **Don't mirror Android file-by-file.** Port only what the task needs. The gap is large enough that a greenfield port of every screen is more churn than the task is worth.
2. **Prefer lifting shared code into a package** (`packages/ui_kit`, a new `packages/local_stores`, etc.) over copying Dart files between the two app directories. Two divergent copies of the same screen is the drift problem the parity-enforcement initiative is trying to prevent.
3. **Check Android first** for the pattern being asked for. If it exists there, port; if not, design on Android first and port second — Android is where the fast iteration happens.

## Dart analyzer

No known lint tech debt on this app (there's barely any code). Keep it clean as you add files.

## Running it locally

See [../../docs/local_testing_ios_app.md](../../docs/local_testing_ios_app.md). You need an iOS simulator or a paired device.

## Before reporting a task done

- Update the iOS checkbox in `roadmap.md` (there are several — "Parse on iOS", "Background location tracking (iOS)", etc.).
- If you ported a screen from `mobile_android`, note the source commit in the PR description so future drift fixes can find the twin.
- If the ported screen pulled in a dependency that isn't in Android, add it here so the divergence is visible.
