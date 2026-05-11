# mobile_android — AI session notes

The most mature Flutter target in the monorepo. Almost every "Android" checkbox in [../../docs/roadmap.md](../../docs/roadmap.md) Phase 1 is ticked. Treat this app as the reference implementation — when in doubt about what a feature *should* look like on mobile, look here first.

## Scope — read before writing code

**Web is the canonical feature surface. This app mirrors web and adds device-only capabilities.** See [../../docs/decisions.md § 24](../../docs/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) and the live matrix at [../../docs/parity.md](../../docs/parity.md).

**One-Dart-codebase rule.** `apps/mobile_android/lib/` and `apps/mobile_ios/lib/` are kept byte-for-byte identical, plus `apps/mobile_android/test/` and `apps/mobile_ios/test/`. Every change you make under `lib/` or `test/` must be applied to the iOS twin in the same commit. Platform-specific runtime behaviour goes inside the unified files via `Platform.isAndroid` / `Platform.isIOS`. The pubspec deltas between the two apps are limited to `name` and `description` — every dependency, version, and asset stays in lockstep. Verify with `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` (should be empty).

**Build here:**

- **Device-led features** (the physical-exception list in §24): live GPS recording + foreground service, auto-pause, on-device crash recovery, BLE chest-strap HR, pedometer / cadence, haptic / TTS pace alerts, OS share sheets, OS share-target intents (GPX / KML import), Health Connect import, disk-backed tile cache, background sync via WorkManager.
- **Mirroring** of an already-shipped web feature into a Flutter screen + api_client method + (when needed) a domain model in `core_models`. Driven by `parity.md` rows where web is `✓` and android is `✗` / `Partial`.

**Don't build here first:**

- A user-facing feature that doesn't yet exist on web — build it on web first, mirror after. This applies even when the request lands on an Android session ("can you add X to Android?"); push back, ship X on web, then mirror. The exception is the device-led list above.
- New abstractions / DI frameworks. `StatefulWidget + setState + ChangeNotifier` is the entire UI stack. No Provider, no Riverpod, no Bloc. If a screen needs cross-cutting state, add a `ChangeNotifier` and wire `addListener` / `removeListener` in `initState` / `dispose`.
- Direct `Supabase.instance.client.from(...)` calls in screens. Route through `packages/api_client` so the typed client stays the single Supabase entry point. (Realtime channels are the documented exception.)
- Comments, decision docs, READMEs, or "removed X" markers under `lib/`. Conventions in [../../docs/conventions.md](../../docs/conventions.md) apply here in full — comments only for non-obvious *why*.

When closing a parity gap, the order is: row classes (already generated) → `api_client` typed methods → domain model in `core_models` if the shape isn't 1:1 → ChangeNotifier or screen-local state → screen. See [../../docs/mobile_android_backlog.md](../../docs/mobile_android_backlog.md) for the live execution order.

## Stack

- **Flutter** stable, Dart 3.x
- **State management:** `StatefulWidget` + `setState` throughout. Stores (`LocalRunStore`, `LocalRouteStore`, `Preferences`) are plain `ChangeNotifier`-style singletons that screens subscribe to via `addListener` in `initState` and unsubscribe in `dispose`. No Provider, no Riverpod, no Bloc. If you add a new screen, follow the same pattern — do not introduce a DI framework.
- **Hot-path exception — `run_screen.dart`:** the per-second `_onSnapshot` handler does NOT call `setState`. It updates mirror fields (for `_saveInProgress`, `_refreshLockScreenNotification`, and the `_formattedX` getters) then publishes to a `ValueNotifier<_LiveStats>`. The affected subtrees (map, off-route banner, route-remaining badge, stats panel) are wrapped in `ValueListenableBuilder`, so the rest of the recording tree (activity chips, GPS-lost / permission-revoked banners, layout) doesn't rebuild at GPS rate. If you add a new stat that updates per snapshot, put it behind the notifier, not in a `setState`. Control-state changes (state transitions, manual pause, lap mark) still go through `setState` — that cadence is low enough that a full rebuild is fine.
- **Maps:** `flutter_map` with a MapLibre-compatible raster tile source. Cached via `flutter_map_cache` + `dio_cache_interceptor` for the disk-backed persistent tile cache. See [decisions.md § 8](../../docs/decisions.md) and [§ 5](../../docs/decisions.md).
- **Recording:** delegates to `packages/run_recorder` — state machine, GPS filter chain, auto-pause, off-route detection, all live there. This app holds the UI and the screens; the recording logic is a package so the iOS and Wear OS apps can eventually reuse it.
- **Auth / backend:** `packages/api_client` for Supabase. Google Sign-In is wired via the native `google_sign_in` package → exchanges the ID token through `ApiClient.signInWithGoogleIdToken`. Apple Sign-In is wired via `sign_in_with_apple` → `ApiClient.signInWithAppleIdToken`. Both buttons render on `sign_in_screen.dart` and `sign_up_screen.dart`. parkrun athlete-number import lives behind a Settings tile rather than a true OAuth flow (parkrun has no public OAuth surface).

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
- Strava live OAuth (the ZIP import path is shipped). The OAuth surface is a Settings → Connect Strava button that's still scaffolded behind the same `apps/web` flow that ADR §41 covers.

## Files

**Screens** (`lib/screens/`):
- `onboarding_screen.dart` — first-launch permission ask
- `sign_in_screen.dart` — email/password + Google sign-in
- `sign_up_screen.dart` — email/password registration + Google sign-in, linked from sign-in
- `home_screen.dart` — the dashboard + nav tabs host
- `run_screen.dart` — the primary recording screen (countdown, live stats, route overlay, finish summary); hosts the recorder state machine and all the hardening described in [../../docs/run_recording.md](../../docs/run_recording.md)
- `dashboard_screen.dart` — weekly mileage, PBs, goal progress; AppBar actions push `coach_screen.dart` (AI Coach), `feed_screen.dart` (activity feed) and `profile_screen.dart` (own profile)
- `coach_screen.dart` — AI Coach chat. Mirrors web `CoachChat.svelte` + `/coach/+page.svelte`. Plan switcher in the AppBar (when >1 plan), end-Drawer archive sidebar, context strip (plan / runs window 10|20|50|100 / HR pill / weekly-goal pill), markdown bubbles via `flutter_markdown`, inline edit / regenerate / copy / thumbs actions, multi-line composer with circular send button, daily-cap banner driven by `get_coach_usage` + `is_pro`. Streams from the web `/api/coach` endpoint via `dart:io` HttpClient + UTF-8 SSE parser; Realtime subscription on `coach_messages` stitches in messages persisted by other tabs.
- `feed_screen.dart` — activity feed of public runs from people you follow (14-day window, mirrors web `/feed`); activity-segmented filter + author dropdown + infinite-scroll. Tapping a card body pushes `public_run_screen.dart`
- `profile_screen.dart` — public user profile (`/u/[id]` mirror): header, Follow toggle, and tabs for Runs / Followers / Following / Notifications (notifications tab gated to self)
- `public_run_screen.dart` — read-only mirror of web `/share/run/[id]`. Reads via `ApiClient.fetchRunById` (RLS hides private), reuses `LiveRunMap` + segment chips + social section. Routes the fetched track through `clipTrackForUser` for non-owner viewers (anon included) before render — owner is detected by `api.userId == row.userId` (decisions §33). Reachable from feed-card body taps
- `public_route_screen.dart` — read-only mirror of web `/share/route/[id]`. Reads via `ApiClient.fetchRouteById` (returns `({Route? route, String? ownerId})` so the screen can clip for non-owner viewers); renders the planned-route polyline + stats + segments panel (read-only). Same owner gate as `public_run_screen` (decisions §33). Reachable from the Routes tab on `club_detail_screen`
- `live_spectator_screen.dart` — read-only mirror of web `/live/[run_id]`. Hydrates existing `live_run_pings`, then subscribes via `Supabase.channel.onPostgresChanges(insert)` filtered by `run_id`; renders the trace on `LiveRunMap` (follow-runner) with a Live / Idle / Connecting badge
- `devices_screen.dart` — Settings → Devices: lists `user_device_settings` rows with Rename / Edit overrides… / Remove popup actions. Mirrors web `/settings/devices`
- `privacy_zones_screen.dart` — Settings → Privacy zones: tap-to-add geofence picker on `flutter_map`. Persists to `user_settings.prefs.privacy_zones` via `SettingsService.updateUniversal`. Mirrors web `PrivacyZonePicker`
- `runs_screen.dart` — run list with sorting, FAB opens `add_run_screen`
- `add_run_screen.dart` — manual-entry form: date/time + duration + distance + optional saved route
- `run_detail_screen.dart` — single run map + stats (primary + secondary) + interactive elevation/pace chart + best efforts + pace-bar splits + laps
- `import_screen.dart` — GPX / KML / KMZ / GeoJSON / TCX file picker
- `routes_screen.dart` — saved routes list with per-row star toggle (owner-only) that drives the watch's starred-only route picker (see `docs/decisions.md § 44`)
- `route_detail_screen.dart` — route map + metadata + reviews + public/private toggle + star-for-watch toggle (owner-only)
- `route_builder_screen.dart` — full-screen in-app route builder MVP (Phase 3). Tap-to-place waypoints with OSRM road / trail / straight modes, undo, clear, save dialog (name + public toggle) → `ApiClient.saveRoute` + `LocalRouteStore.save`. Reached from the second "Build" FAB on `routes_screen`. Pure routing helpers live in `routing.dart` (Dart port of `apps/web/src/lib/routing.ts`). Deferred for parity with web: draggable marker reshape, elevation-while-drawing, snap-to-start, MapTiler place search, overlap detection, geolocate auto-center.
- `period_summary_screen.dart` — browsable weekly/monthly summary with stats, run list, and share (text or screenshot)
- `explore_routes_screen.dart` — search and browse public routes with filters (distance, surface), save to library
- `settings_screen.dart` — preferences, integrations (Strava connect/sync/disconnect via `url_launcher` hand-off + native sync via Edge Function; parkrun athlete-number import), data export
- `clubs_screen.dart` — Browse / My clubs, 6th bottom-nav tab. FAB opens `widgets/club_form_sheet.dart` (Create club)
- `club_detail_screen.dart` — five tabs: Feed (threaded posts) · Events (admin Create button + RSVP cards) · Members (admin pending-requests panel + count) · Routes (club-owned routes via `routes.club_id`, lazy-loaded; tap → `public_route_screen.dart`) · Templates (admin/member-visible plan templates with per-row Adopt → `clone_plan_template` RPC)
- `event_detail_screen.dart` — per-instance RSVP + admin update composer + admin-only Race control card (Arm / Fire Go / End / Cancel, gated on `ClubView.isRaceDirector`, backed by `SocialService.armRace` / `startRace` / `endRace`)
- `plans_screen.dart` — Training plans list (accessed from Run tab idle button)
- `plan_new_screen.dart` — Wizard with live pace + week-outline preview
- `plan_detail_screen.dart` — Hero + progress ring + today card + week grid
- `workout_detail_screen.dart` — Structured-interval breakdown + per-kind advice

**Top-level (`lib/`):**
- `main.dart` — app entry, Supabase init, service wiring; calls `WearAuthBridge().attach(...)` so the paired Wear OS watch inherits the Supabase session
- `sync_service.dart` — bulk-sync button, auto-sync on connectivity/foreground, conflict resolution
- `wear_auth_bridge.dart` — forwards Supabase session changes to the paired Wear OS watch via a `run_app/wear_auth` method channel (native `WearAuthBridge.kt` under `android/app/src/main/kotlin/com/runonward/app/` writes to the Wearable Data Layer)
- `run_notification_bridge.dart` — replaces geolocator's "Run in progress" foreground-service notification with live time/distance/pace (native `RunNotificationBridge.kt` reposts on the same channel id so the lock-screen row is live instead of static)
- `background_sync.dart` — WorkManager periodic background sync (hourly, network-connected)
- `local_run_store.dart` / `local_route_store.dart` — `ChangeNotifier`-style on-disk stores
- `preferences.dart` — SharedPreferences wrapper for settings
- `tile_cache.dart` — disk-backed map tile cache glue
- `audio_cues.dart` — TTS for splits and pace alerts. Pace alerts are paired with a `HapticFeedback.heavyImpact()` pulse in `run_screen.dart` (two pulses for "speed up", one for "slow down") so the cue registers with headphones paused
- `run_stats.dart` — pace/distance/split formatting helpers (tested)
- `goals.dart` — `RunGoal` model + pure `evaluateGoal` for dashboard goal cards (tested)
- `route_simplify.dart` — Ramer–Douglas–Peucker track simplifier used when saving a run as a route (tested)
- `routing.dart` — Dart port of `apps/web/src/lib/routing.ts`. OSRM client for the in-app route builder: `snapToRoad(point, profile: foot|car)` for the nearest-road service + `fetchRouteThrough(points, profile)` for a road-snapped polyline through N waypoints. Pluggable `OsrmFetcher` callback so unit tests can replay canned bodies (`test/routing_test.dart`, 9 tests). Default fetcher uses dart:io's `HttpClient` (no new package dep). The public OSRM endpoint is unauthenticated and free for low volumes; if usage grows past the demo server's quota, swap the base URL for a self-hosted instance.
- `health_connect_importer.dart` / `strava_importer.dart` — bulk importers
- `widgets/live_run_map.dart` — live map with route overlay, off-route banner, NRC-style pace heatmap (when `activity` is non-null, falls through to the legacy single gradient polyline otherwise). On the run-detail surface (`showDecorations: true`) it also overlays the per-km / per-mile distance pins and the direction-arrow chevrons via `widgets/track_decorations.dart` so the trace mirrors the web run-detail map. Live recording leaves these off — the pulsing dot already makes direction implicit.
- `widgets/track_decorations.dart` — pure helpers `computeDistanceMarkers` + `computeChevrons` that walk a polyline and emit km-/mile-boundary pins and direction arrows along the track. Mirrors the `computeDistanceMarkers` + `trace-arrows` symbol layer on `apps/web/src/lib/components/RunMap.svelte`. 10 unit tests in `test/track_decorations_test.dart`.
- `widgets/track_segment.dart` — pure helpers backing the tap-to-select segment popup on the run-detail map. `nearestTrackIdx` is a linear scan, `buildSegmentAt` expands ±150 m around a click index and aggregates distance / duration / pace / avg BPM / elevation gain + loss for the slice. Mirrors `buildSegment` in `apps/web/src/lib/components/RunMap.svelte` — keep both paths in sync so a click on web and a tap on mobile produce identical stats. 9 unit tests in `test/track_segment_test.dart`.
- `widgets/pace_segments.dart` — pure helpers `buildPaceSegments` / `paceBucketForSpeed` / `ageBandFor`. Pace-coloured, age-faded segment builder for the live track. No Flutter state — unit-tested in `test/pace_segments_test.dart`
- `widgets/track_preview.dart` — pure `CustomPainter` thumbnail mirroring the SVG geometry of `apps/web/src/lib/components/TrackPreview.svelte` (viewBox short axis = 100, PAD = 4, four directional chevrons, green-start / red-end caps). `projectTrack` is the testable pure-math projection (cos(midLat) longitude correction so a square loop renders square at any latitude — see [decisions.md § 51](../../docs/decisions.md)); `isTrackRenderable` ports the web `isMoving` 5 m jitter guard. Mounted on `routes_screen`, `explore_routes_screen`, and the Routes tab of `club_detail_screen` (routes carry waypoints inline) and as the inner renderer for `RunTrackPreview`. See [decisions.md § 49](../../docs/decisions.md).
- `widgets/run_track_preview.dart` — lazy track-fetcher around `ApiClient.fetchTrackByPath` with a static URL→`List<Waypoint>?` cache (the `null` entry is a "fetch failed" sentinel so broken Storage objects don't get retried on every rebuild). Mounted on the run-list rows in `runs_screen` and the per-card thumbnail strip in `feed_screen`. Mirrors `apps/web/src/lib/components/RunTrackPreview.svelte`.
- `widgets/collapsible_panel.dart` — the run screen's expandable stats panel
- `widgets/run_share_card.dart` — portrait share card + modal sheet; captures a PNG via `RepaintBoundary.toImage` and hands it to `share_plus`
- `widgets/goal_editor_sheet.dart` — modal bottom sheet for creating/editing/deleting a `RunGoal` (type + period + target)
- `widgets/upcoming_event_card.dart` — Run tab idle-state card shown when the user has a `going` RSVP within 48h
- `widgets/todays_workout_card.dart` — Run tab idle-state priority card when an active plan has a workout scheduled today
- `widgets/plan_calendar.dart` — Dart port of `apps/web/src/lib/components/PlanCalendar.svelte`. Month-by-month grid with prev/next chevrons, Monday-first DOW row, kind-coloured cells, completed-tick. Renders on `plan_detail_screen` between the today card and the week cards.
- `widgets/workout_edit_sheet.dart` — modal bottom sheet for inline edit of a `PlanWorkoutRow` (kind, target distance, target pace, notes). Opened via the pencil button or long-press on a workout row in `plan_detail_screen`; saves through `TrainingService.updateWorkout`.
- `widgets/workout_execution_band.dart` — top-of-map overlay shown while a structured workout is running. Reads through a `ValueListenable<WorkoutBandState>` so transitions / progress events don't trigger a Stack-wide rebuild. Surfaces the current step label, pace pip with signed delta, progress bar + remaining metres, and Skip / Abandon controls.
- `widgets/workout_review_section.dart` — post-run planned-vs-actual table on `run_detail_screen`. Reads `runs.metadata.workout_step_results` + `workout_adherence`; hidden when those keys are absent. Mirrors the web `/runs/[id]` Workout section. Pure widget + helpers (`paceDeltaOf`, `formatPace`) — no controller state, widget-tested.
- `widgets/run_social_section.dart` — kudos pill + one-level comment thread + composer for `run_detail_screen`. Self-fetches engagement and `fetchRunCommentsWithAuthors` on mount. Optimistic kudos toggle with rollback. Replies bucket client-side; author/owner gate the Delete affordance. Mirrors `apps/web/src/lib/components/RunSocial.svelte`.
- `widgets/run_photos.dart` — run-detail photo gallery. Owner gates Add photo (uses `image_picker` to pick from gallery, uploads via `ApiClient.addRunPhoto` to the `run-photos` Storage bucket), inline caption edit + delete. Tap a tile for a full-screen `InteractiveViewer` lightbox. Mounted on both `run_detail_screen` (owner: full controls) and `public_run_screen` (read-only when viewer is not the owner). Mirrors `apps/web/src/lib/components/RunPhotos.svelte`.
- `widgets/club_form_sheet.dart` — modal create-club form (name, description, location, public/private, join policy). Auto-slugifies the name; visibility ↔ policy linking matches web `ClubEditor.svelte`. Mounted from the FAB on `clubs_screen.dart`.
- `widgets/event_form_sheet.dart` — modal create-event form (title, starts-at picker, description, meet label, distance / duration, recurrence none/weekly/biweekly/monthly with auto-byday from the picked DOW). Mounted from the admin Create button on the Events tab of `club_detail_screen`.
- `widgets/run_segment_efforts.dart` — per-run segment-effort chips on `run_detail_screen`. On mount, when the viewer owns the run and it's linked to a saved route, walks the track via `lib/segments.dart#autoComputeEffortsForRun` to insert any new efforts (idempotent against the unique(segment_id, run_id) constraint), then fetches the joined effort + segment + rank rows via `ApiClient.fetchEffortsForRunWithSegments`. Mirrors `apps/web/src/lib/components/RunSegmentEfforts.svelte`.
- `widgets/segments_panel.dart` — route-detail segments panel on `route_detail_screen`: lists every segment, expand-on-tap to a per-segment leaderboard via `fetchSegmentLeaderboardWithAthletes`. Route owner gets a "New segment" form (name + start_m + end_m, ≥100 m enforcement) and a per-row delete button (uses `ApiClient.deleteSegment`). Mirrors `apps/web/src/lib/components/SegmentsPanel.svelte`.
- `widgets/training_load_chart.dart` — dashboard "Fitness, Fatigue & Form" `CustomPaint` chart. Reads HR prefs from `SettingsService` (`resting_hr_bpm` + `max_hr_bpm`); renders three line series (CTL / ATL / TSB) over the last 90 days plus a dashed zero line, a legend, and a one-line reading. Mirrors `apps/web/src/lib/components/TrainingLoadChart.svelte`.
- `training_load.dart` — pure Dart port of `apps/web/src/lib/training_load.ts` (decisions §34). Same TRIMP-when-HR / distance-fallback stress ladder, same daily aggregation, same EWMA trio (ATL halflife 7, CTL halflife 42); `hasTrimpSignal` drives the "HR-based" vs "volume-based" subtitle.
- `segments.dart` — pure Dart port of `apps/web/src/lib/segments.ts` (decisions §37). `computeEffortFromTrack` walks a track once, accumulates haversine distance, and interpolates timestamps at the start / end crossings; `autoComputeEffortsForRun` fans the walker over every segment on a route and posts new efforts. Sparsity guard mirrors web (median sample step must be ≤ segLen / 5). 8-test mirror suite in `test/segments_test.dart`.
- `privacy.dart` — pure Dart port of `apps/web/src/lib/privacy.ts` (decisions §33). `PrivacyZone` shape, `isInAnyZone` haversine check, `clipPointsToZones` walks-from-each-end clipper. Owner-side preview only — non-owner tracks go through the `clip_track_for_user` SECURITY DEFINER RPC server-side. 8-test mirror suite in `test/privacy_test.dart`.
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
- `backend_timeout.dart` — guarded `Future.timeout` wrapper for every PostgREST + Storage call so a single hung request can't lock the UI for the system default. Used by the home screen's pull-to-refresh and the sync paths.
- `watch_ingest_queue.dart` — disk-backed buffer for incoming watch payloads. iOS only writes to it (the Android-side method channel is a no-op); replays on sign-in / connectivity return so a phone restart doesn't lose a run that landed from the watch while the user was signed out.
- `widgets/error_state.dart` — reusable empty/error/retry surface used by every screen that fetches from Supabase. Widget-tested.
- `widgets/route_share_card.dart` — portrait-orientation share card for routes (sibling of `widgets/run_share_card.dart`). Same `RepaintBoundary.toImage` → `share_plus` flow.
- `widgets/top_banner.dart` — top-anchored notification pill, the canonical replacement for `ScaffoldMessenger.showSnackBar` across the mobile app. Renders via `Overlay`, auto-positions below the nearest `AppBar`, and coalesces to a single banner at a time. See [../../docs/conventions.md § Mobile in-app notifications](../../docs/conventions.md#mobile-in-app-notifications--showtopbanner).
- `fit_export.dart` — FIT-binary writer for runs, used by Settings → Export run. Sibling of `lib/gpx_export.dart`. 3 tests in `test/fit_export_test.dart`.

## Dart analyzer policy — treat `info` as noise

`dart analyze` on this package reports ~480 issues. **Every remaining entry is `info`-level** — the package is clean of `warning`/`error` as of this pass. The noise buckets (top categories from `dart analyze | grep -oE ' - [a-z_]+$' | sort | uniq -c | sort -rn`):

- `always_use_package_imports` (~220) and `avoid_relative_lib_imports` (~140) — these two interact with [decisions.md § 39](../../docs/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase): tests use relative imports so the same file resolves on both targets. Not being fixed.
- `deprecated_member_use` (~46) — mostly `withOpacity` → `withValues` and `share_plus` v13 (`Share.shareXFiles` → `SharePlus.instance.share`). Deferred until we do a theme/deps pass.
- `unnecessary_underscores` / `use_null_aware_elements` / `prefer_single_quotes` / `use_build_context_synchronously` — small stragglers.

**Do not waste a turn on these.** Only act on `info` if your change touched that specific file. **Do act on any new `warning`/`error`** — the bar is "zero warnings", so a fresh one is a regression your change introduced. The CI `test-packages` job runs `melos exec -- dart analyze`; the exit code is ignored for this package (per roadmap intent, not per CI config — verify before relying on this).

## Tests

Test files in `test/`:
- `run_stats_test.dart` — 13 tests: moving-time helpers + `fastestWindowOf` rolling-window scanner
- `local_run_store_test.dart` — 23 tests: store persistence, sync state, in-progress save/load, deleteMany batch, newer-wins guards, edge cases
- `period_summary_test.dart` — 23 tests: period boundary computation, stats aggregation, share text generation, formatting helpers
- `goals_test.dart` — 20 tests: goal evaluation (distance/time/pace/run-count, weekly/monthly, multi-target)
- `route_simplify_test.dart` — 8 tests: Ramer-Douglas-Peucker track simplification
- `training_test.dart` — 18 tests: VDOT, Riegel, pace derivation, plan generation (mirrors `apps/web/src/lib/training.test.ts`)
- `ble_heart_rate_test.dart` — 9 tests: BLE HR characteristic 0x2A37 parser (8-bit/16-bit BPM, edge cases)
- `pace_segments_test.dart` — 15 tests: pace-bucket clamping, activity-specific scaling, age-band partitioning, coalescing, vertex-sharing continuity, timestamp-less fallback — backs the NRC-style pace heatmap in `widgets/pace_segments.dart`
- `track_preview_test.dart` — 8 tests for `widgets/track_preview.dart`: 4 for `isTrackRenderable` (rejects empty / single-point / sub-5 m jitter tracks, accepts genuine tiny laps + multi-km loops), 4 for `projectTrack` (square 100 m loop at 51 °N renders square within 2 %, longitude scale matches `cos(midLat)` at high latitudes, horizontal segments stay on the x-axis, empty input). Mirrors the `isMoving` + projection helpers on the web `track_projection.ts` module.
- `track_decorations_test.dart` — 10 tests for `widgets/track_decorations.dart`: 6 for `computeDistanceMarkers` (one pin per km / mile, empty short tracks, miles produces fewer pins, `totalDistanceM` rescales sparse-polyline runs, mid-segment interpolation), 4 for `computeChevrons` (right cadence, north-bound segments rotate to point up, empty for invalid stepMetres). Mirrors the `computeDistanceMarkers` + `trace-arrows` layer on web's `RunMap.svelte`.
- `track_segment_test.dart` — 9 tests for `widgets/track_segment.dart`: `buildCumulativeDistances` is monotonic, `nearestTrackIdx` finds the closest waypoint, `buildSegmentAt` expands ±150 m, computes pace + duration from timestamps, returns null pace under 10 m, aggregates avg BPM and elevation gain on the slice, widens past a degenerate single-point selection at the track edge. Mirrors `buildSegment` on web's `RunMap.svelte`.
- `hr_zones_test.dart` — 8 tests: time-weighted vs sample-count fallback, the 30 s pause cap, custom cutoffs, malformed-input rejection, `bpmStatsOf` aggregation
- `fitness_test.dart` — 17 tests: VDOT range checks (5k, marathon), `currentVdot` 90-day window + qualifying-source filter, `runTss` Coggan reference, EWMA training-load smoke, `recoveryAdvice` thresholds, `computeSnapshot` end-to-end
- `training_load_test.dart` — 10 tests for `lib/training_load.dart`: distance-fallback stress (~50 for an easy 5k), TRIMP path lights up with avg_bpm + resting + max, zero-input → 0, daily aggregation sums same-day runs, series emits exactly windowDays entries, TSB rises during a 14-day taper, all-zero with no runs, `hasTrimpSignal` gating (no avg_bpm / has avg_bpm + prefs / prefs missing). Mirrors `apps/web/src/lib/training_load.test.ts`.
- `segments_test.dart` — 8 tests for `lib/segments.dart`: clean segment, run shorter than segment end, ≤2-point tracks, zero / negative segment windows, sparse-sampling guard (median step > segLen / 5), missing timestamps in the interpolation bracket, mid-segment interpolation, sample-aligned endpoints. Mirrors `apps/web/src/lib/segments.test.ts`.
- `privacy_test.dart` — 8 tests for `lib/privacy.dart`: `isInAnyZone` (empty / centre / far), `clipPointsToZones` (empty zones returns input, drops leading + trailing in-zone, keeps interior, every-point-in-zone returns empty, multi-zone union). Mirrors `apps/web/src/lib/privacy.test.ts`.
- `plan_calendar_test.dart` — 3 widget tests: month rendering with kind labels, chevron navigation, completed-tick presence
- `workout_execution_band_test.dart` — 6 widget tests: empty render, header / step counter / remaining-metres formatting, Skip + Abandon callbacks, complete + abandoned shells, em-dash for null pace
- `workout_review_section_test.dart` — 11 tests for `widgets/workout_review_section.dart`: hidden when metadata absent / empty / null, header + adherence pill rendered with one row per step, kind-specific labels (Warmup / Rep i/n / Recovery i/n / Cooldown), strikethrough + "skip" label for skipped steps, em-dash + neutral colour when actual pace is null, signed `+/−Ns` delta label, and tone classification thresholds (`on` / `amber` / `off` against the 10 s tolerance) plus `formatPace` formatting
- `fitness_card_test.dart` — 5 widget tests for `widgets/fitness_card.dart`: hidden with no runs, hidden when no runs qualify (sub-3 km / sub-5 min), populated card renders all six stat labels + the recovery-advice icon + the qualifying-run count, em-dash placeholder when VDOT can't be computed but qualifying runs exist, plus a smoke test for the `FitnessStat` value-over-label primitive
- `metadata_registry_test.dart` — 2 tests: (1) every `runs.metadata` key referenced in Dart source is registered in [docs/metadata.md](../../docs/metadata.md) — catches cross-client drift like `metadata.activityType` vs `metadata.activity_type` at CI time; (2) a soft "dead-key" info log surfacing registered keys that no Dart reader touches (may be web/watch/EF-only). Fails on unknown-key writes; purely informational on the reverse direction.
- `recurrence_test.dart` — 8 tests: weekly / biweekly / monthly `expandInstances`, hour/minute local-tz preservation, `count` cap, `until` cap, non-recurring single-instance
- `importer_external_id_test.dart` — 2 tests: `StravaImporter` ZIP import produces `strava:<id>` prefix; source-text guard confirms `HealthConnectImporter` uses `healthconnect:<uuid>` prefix
- `routing_test.dart` — 9 tests for `lib/routing.dart` (OSRM client used by the in-app route builder): snapToRoad parses + falls back to input on non-Ok / network error, builds /foot vs /car path correctly; fetchRouteThrough returns empty on <2 points, parses routes[0].geometry + distance, semicolon-joins lng,lat pairs, throws StateError on non-Ok code, throws on missing/empty routes.
- `route_builder_screen_test.dart` — 4 tests for `lib/screens/route_builder_screen.dart` (mobile in-app route builder MVP): initial state shows "Tap the map" hint + Save disabled; mode toggle renders Trail / Road / Straight segments; `straightLineDistance` sums haversine legs (~2 km for two ~1 km legs at the equator); returns 0 for <2 points.
- `live_broadcaster_test.dart` — 8 tests for `lib/live_broadcaster.dart`: starts inactive; `pushPing` is a no-op when inactive; `attach` flips `isActive`; first ping after attach goes through with the full field set; back-to-back pings within the 5 s window are throttled; `detach` silences future pings; api errors are swallowed (L4); re-attach resets the throttle so the next run's first ping fires immediately. Pure Dart, fake `ApiClient`.
- `services_integration_test.dart` — 5 wire-level tests against a real local Supabase via the seed user (gated on `SUPABASE_TEST_URL`). Drives `SocialService.browseClubs` / `fetchMyClubs` and `TrainingService.fetchMyPlans` / `fetchActiveOverview` through the `withClient(SupabaseClient)` DI seam — the same shape as `ApiClient.withClient`. Closes the previously-uncovered "Supabase-touching methods on SocialService + TrainingService" gap from `docs/testing.md`. CI runs this file from the `api-client-integration` job.
- `architecture_guards_test.dart` — 42 tests: static source-level assertions that pin in place the efficiency + layering optimizations (no `setState` in `_onSnapshot`, `markSynced` doesn't rewrite the run file, sync paths use `saveRunsBatch`, `ErrorWidget.builder` override present, RunNotificationBridge pins geolocator channel constants, plus the `LocalRunStore` newer-wins guards — `save`/`update` must stamp `last_modified_at`, `saveFromRemote` must not — added in the Apr 2026 data-sync hardening pass; the May 2026 UI-freeze guards: `StravaImporter.importFromZip` must dispatch to `compute()`, `BackupService` must keep the `_encodeArchiveInIsolate` / `_decodeArchiveInIsolate` helpers, `routes_screen._importFile` must wrap `RouteParser` in `compute()`, and both stores' `_loadAll` must keep the directory walk on `listSync` (the async stream form deadlocks `RunsScreen` widget tests under flutter_test — see [decisions.md § 48](../../docs/decisions.md#48-heavy-import--backup-parsers-run-in-compute-isolates-never-on-the-ui-thread)); and the May 2026 notification-primitive guards: no direct `showSnackBar` or `ScaffoldMessenger.of(context)` calls anywhere under `lib/screens/` or `lib/widgets/` — the canonical primitive is `showTopBanner` from `widgets/top_banner.dart` (see [../../docs/conventions.md § Mobile in-app notifications](../../docs/conventions.md#mobile-in-app-notifications--showtopbanner))). **When one of these fails, read the `reason:` before rubber-stamping a fix** — a failure means a recent change reversed an optimization we deliberately codified.
- plus `run_recorder`'s own tests in `packages/run_recorder/test/` — 18 behavioural in `run_recorder_test.dart` + 7 guards in `architecture_guards_test.dart` + 6 in `laps_serialiser_test.dart` (canonical `metadata.laps` round-trip) + 13 in `workout_runner_test.dart` (step expansion, auto-advance, halfway / last-50m progress, skip / abandon, pace-adherence wayBehind, results JSON shape)

See [../../docs/testing.md](../../docs/testing.md) for how to run them and the patterns they use. Widget tests exist for every screen and widget, including `RunScreen` (`run_screen_test.dart`) and `LiveRunMap` (`live_run_map_test.dart`) (~178 `testWidgets` calls across ~48 files); see `test/` for the full list.

## Running it locally

See [local_testing.md](local_testing.md). Short version: `cd apps/mobile_android && flutter run -d <device>`. The seed user in local Supabase is `runner@test.com` / `testtest`.

## Deploying to production

See [deployment.md](deployment.md) — Play Console signing, GitHub Secrets, release workflow, observability, rollback, DR.

## Before reporting a task done

- Run `dart analyze` on this package and confirm no new `warning`/`error` level issues. `info` are OK per policy above.
- Run `flutter test` for the package if you touched anything under `test/` or the files it covers.
- If you changed anything user-visible, update the corresponding "Android" checkbox in `roadmap.md`.
- If you introduced a new screen, add it to the file list above.
- If you hit a new gotcha, add it here so the next session doesn't re-hit it.
