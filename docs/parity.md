---
name: Cross-platform feature parity matrix
description: Single table listing every user-visible feature with a per-platform status cell (shipped / partial / not started / N/A).
---

# Cross-platform feature parity matrix

The app ships on five surfaces — **Android**, **iOS**, **Web**, **Wear OS**, **Apple Watch** — and features drift between them. This doc is the single place where that drift is visible. Every user-facing feature has a row, every platform has a column, and every cell is either `✓`, `✗`, `Partial`, or `N/A`.

See [roadmap § Cross-platform parity enforcement](roadmap.md#future--cross-platform-parity-enforcement) for why this exists, and [decisions.md § 24](decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) for the web-canonical rule that shapes how gaps get closed.

## Legend

| Symbol | Meaning |
|---|---|
| `✓` | Shipped and working end-to-end on that platform. |
| `Partial` | Scaffold, mock-data screen, or wired for read-only but missing the full flow. Expand in the **Notes** column. |
| `✗` | Not started. May be a genuine gap (drift) or a planned future item. |
| `N/A` | Intentionally not applicable — the platform cannot reasonably provide the feature (e.g. pedometer in a browser). Expand in the **Notes** column so it isn't rediscovered as "missing". |
| 🔸 in Notes | This row is a **gap against the web-canonical principle** ([decisions.md § 24](decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)) — web is `✗` or `Partial` on a feature that is *not* a physical exception. Close these by building the web version, not by adding to the matrix's tail. |

**Columns:**

- **Android** — `apps/mobile_android` (Flutter). Most mature surface.
- **iOS** — `apps/mobile_ios` (Flutter). Phase 1 structural work only; most screens scaffold-only. See [apps/mobile_ios/CLAUDE.md](../apps/mobile_ios/CLAUDE.md).
- **Web** — `apps/web` (SvelteKit 2 + Svelte 5).
- **Wear OS** — `apps/watch_wear` (native Kotlin + Compose-for-Wear). Recording-only by design.
- **Apple Watch** — `apps/watch_ios` (native SwiftUI). Recording-only by design.

## How to use this doc

- Reviewing a PR that adds or changes a user-visible feature? Check the matrix. If the PR ships on one platform only, the other cells should stay `✗` (or flip to a planned follow-up), not silently stay empty.
- Opening a new feature? Add a row here before you merge. It's much cheaper to promise `✗` for four platforms than to discover a year later that one of them half-implemented the feature from a different angle.
- Auditing for drift? Scan for rows where `Android` and `Web` disagree. That's the most common source of the silent desync bugs this matrix exists to prevent (`activity_type`, `surface`, `moving_time`, `source` have all burned us before).
- A mismatch is acceptable only if the **Notes** column explains the gap. If it doesn't, it is drift and should be either fixed or documented-as-intentional in the same PR.

## Auth and onboarding

See [features § Cloud sync and auth](features.md#cloud-sync-and-auth).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Email / password sign-in | ✓ | ✓ | ✓ | ✗ | ✗ | Watches authenticate by piggy-backing on the paired phone's Supabase session (handed over via Watch Connectivity / companion app), not through a native sign-in UI. |
| Google OAuth | ✓ | Partial | ✓ | ✗ | ✗ | iOS: scaffolded, needs provider credentials. |
| Apple OAuth | ✓ | Partial | ✓ | ✗ | ✗ | iOS: behind `_kAppleSignInEnabled = false` pending Services ID setup. |
| Auth callback / deep-link handler | ✓ | ✓ | ✓ | N/A | N/A | Watches never handle the OAuth redirect directly. |
| Onboarding flow (first launch permissions) | ✓ | Partial | N/A | N/A | N/A | Web has no location permission pre-gate; the browser prompts per-feature. |
| Offline-only mode (no auth required) | ✓ | ✗ | ✗ | N/A | N/A | Web requires auth because all views read from Supabase. Mobile keeps runs local first and syncs opportunistically. |

## Route management

### Import

See [features § GPX / KML import](features.md#gpx--kml-import).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| GPX import | ✓ | ✗ | ✓ | N/A | N/A | iOS roadmap item unticked. |
| KML / KMZ import | ✓ | ✗ | ✓ | N/A | N/A | |
| GeoJSON import | ✓ | ✗ | ✓ | N/A | N/A | |
| TCX import | ✓ | ✗ | ✓ | N/A | N/A | Web: `parseTcx` added to `lib/import.ts`; the import drop-zone accepts `.tcx` alongside GPX/KML/KMZ/GeoJSON. Preserves per-point elevation + timestamp. |
| Strava ZIP bulk import | ✓ | ✗ | ✓ | N/A | N/A | Shipped on web: `/settings/integrations` → "Bulk import from a Strava export" — parses `activities.csv` + per-activity GPX/TCX files, dedupes against already-imported Strava IDs, reports live progress. iOS still pending. |

### Builder and library

See [features § Full-screen route builder](features.md#full-screen-route-builder-web) and [features § In-app route builder (mobile)](features.md#in-app-route-builder-mobile).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Full-screen click-to-place route builder | ✗ | ✗ | ✓ | N/A | N/A | Mobile builder is Phase 3, not started. Wrist screens too small by design. |
| Snap-to-road / trail (OSRM) | ✗ | ✗ | ✓ | N/A | N/A | |
| Elevation preview while drawing | ✗ | ✗ | ✓ | N/A | N/A | |
| Route library (list saved routes) | ✓ | Partial | ✓ | ✗ | ✗ | iOS: screen exists with mock data; no API fetch. |
| Route detail (map + stats) | ✓ | Partial | ✓ | ✗ | ✗ | iOS: scaffold only. |
| Public / private toggle per route | ✓ | ✗ | ✓ | N/A | N/A | Bidirectional on both: Android's globe icon on `route_detail_screen.dart`; web's owner-only `Public` / `Private` button on `/routes/[id]` (added in parallel with the explicit Share button; `setRoutePublic(id, bool)` in `data.ts` with optimistic UI + rollback). |
| Shareable route link | ✓ | ✗ | ✓ | N/A | N/A | Web makes the route public and copies the link in one action. |
| Export route as GPX | Partial | ✗ | ✓ | N/A | N/A | Android: share-run-as-GPX is shipped; share-route-as-GPX not yet. |
| Export route as KML | ✗ | ✗ | ✓ | N/A | N/A | |

### Discovery

See [features § Community route library](features.md#community-route-library).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Explore public routes (search + filters) | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Popular / near-me feed (PostGIS) | ✓ | ✗ | ✓ | ✗ | ✗ | Uses `nearby_routes` RPC. |
| Route ratings and comments | ✓ | ✗ | ✓ | ✗ | ✗ | Shared `route_reviews` table; one review per user per route. |

## Run recording

See [features § Live GPS run recording](features.md#live-gps-run-recording), [features § Apple Watch standalone GPS recording](features.md#apple-watch-standalone-gps-recording), and [features § Wear OS standalone GPS recording](features.md#wear-os-standalone-gps-recording).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Live GPS recording | ✓ | Partial | N/A | ✓ | ✓ | iOS: `RunScreen` scaffolded but `RunRecorder` not wired. Web: browsers cannot record a run reliably — reviewing only. |
| Background location tracking | ✓ | Partial | N/A | ✓ | ✓ | iOS recorder has background mode wired in Info.plist but recording loop not end-to-end. |
| 3-second start countdown | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS shows a full-screen 3-2-1 overlay between permission grant and `vm.start()` (tap to cancel). Apple Watch still starts immediately. |
| Manual pause / resume | ✓ | ✗ | N/A | ✓ | ✓ | |
| Hold-to-stop (prevents accidental stop) | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS requires an 800 ms press on the Stop button; a circular progress ring fills during the hold and releasing early cancels. |
| Lap markers | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS exposes a Lap button during recording; splits render on the PostRun screen and persist into `run.metadata.laps` on sync. |
| Wakelock during run | ✓ | N/A | N/A | N/A | N/A | watchOS / Wear OS handle their own wake policies. |
| Activity types (run / walk / cycle / hike) | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS has a CompactChip on the PreRun screen that cycles run → walk → hike → cycle; the choice stamps into `metadata.activity_type` on save. Apple Watch still records as "run". |
| TTS audio cues (splits + pace alerts) | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: `recording/TtsAnnouncer.kt` wraps `android.speech.tts.TextToSpeech`; `RunRecordingService` announces "Run started", each completed kilometre ("1 kilometre. Pace 5 minutes 30 seconds per kilometre"), pace-drift alerts, and a finish summary. Gated on `BuildConfig.ENABLE_TTS` (defaults on; `DISABLE_TTS=true` in `.env.local` silences it for dev). |
| Haptic pace alerts | ✓ | ✗ | N/A | ✓ | ✓ | All three clients: when live pace drifts >30 s off target, a rate-limited (1/30 s) haptic fires — two pulses for "speed up", one for "slow down". Wear OS: pre-run **Pace** chip sets the target (off / 4:00 / 4:30 / 5:00 / 5:30 / 6:00 / 6:30 / 7:00 per km); `RunRecordingService.firePaceAlert` uses `VibratorManager` with a matching `VibrationEffect.createWaveform` pattern and pairs it with a TTS nudge. |
| Step count via pedometer | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: `Pedometer.kt` wraps `Sensor.TYPE_STEP_COUNTER` with a per-run baseline; `RunRecordingService` forwards step counts into `RecordingRepository.Metrics.steps`; the save path writes `run.metadata.steps`. Requires `ACTIVITY_RECOGNITION` at runtime (requested alongside `ACCESS_FINE_LOCATION` + `BODY_SENSORS` by `permissionLauncher`). Browsers have no pedometer sensor. |
| Heart rate via device sensor | ✓ | ✗ | N/A | ✓ | ✓ | Android pairs with an external BLE chest strap (HR Service `0x180D` / characteristic `0x2A37`) via `lib/ble_heart_rate.dart`; live BPM appears on the run screen and `avg_bpm` writes to `run.metadata` on save. iOS chest-strap pairing not wired. Watches use the built-in wrist sensor. |
| Live HTTP tile cache (offline revisits) | ✓ | ✗ | N/A | N/A | N/A | Watches render pure stats during recording — no live map, so there's nothing to cache. Tracked as a follow-up of the *Route navigation on watch* roadmap row rather than a recording feature. |
| GPS self-heal retry | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: `RunRecordingService.gpsRetryJob` mirrors Android's `_startGpsRetryLoop` in `packages/run_recorder/lib/src/run_recorder.dart` — polls every 10 s and re-subscribes when the job has died (same shape as Android's `_positionSub == null`). Additionally re-subscribes when the stream has been silent for >30 s mid-run, a Wear-specific trigger because `FusedLocationProviderClient` doesn't error when a callback goes silent. Initial no-fix is not a stall — that's indoor mode. |
| Indoor / no-GPS mode (time-only) | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: the recorder's elapsed clock ticks unconditionally; `TrackWriter` produces a valid empty `[]` track when no points arrive, so upload works. The RunningScreen banner reads "No GPS — time only" when no fix has landed yet (vs. "GPS lost" mid-run). |
| Live lock-screen / ongoing notification | ✓ | ✗ | N/A | ✓ | ✓ | Watches post persistent workout notifications via their platform workout session APIs. |
| Crash checkpoint recovery | ✓ | ✗ | N/A | ✓ | ✓ | |
| Ultra-length (10h+) run support | ✗ | ✗ | N/A | ✓ | ✗ | Streaming track writer + rolling HR shipped on Wear OS. Apple Watch hasn't been stress-tested at ultra length. |
| Live race mode (Arm / Go / End + pings) | ✓ | ✗ | ✓ | ✓ | ✗ | **Participant side:** Android (`RaceController` + run_screen), Wear OS (`RaceSessionClient` + `RunViewModel.maybePushRacePing`) — both stamp the recorded run with `event_id`, post `race_pings` at 10 s cadence, submit the finisher time to `event_results`. **Organiser Arm/Go/End:** web (`apps/web/src/lib/data.ts:armRace/startRace/endRace` → admin panel on event detail page) and Android (`SocialService.armRace/startRace/endRace` → admin-only Race control card on `event_detail_screen.dart`, gated on `ClubView.isRaceDirector`, with realtime updates via the existing `subscribeToEvent` channel). Wear OS and Apple Watch stay participant-only — typing admin actions on a wrist is a bad UX. **Web spectator surface:** `/live/event/{id}/{instance}` is a public Realtime page subscribed to `race_pings` / `race_sessions` / `event_results`, with a MapLibre map showing each runner as a coloured dot + recent trail (latest 30 samples) and a leaderboard sorted by distance. Web has no live recording (physical exception per `decisions.md § 24`), so participation flows through the mobile / watch clients. The unrelated per-run `/live/{run_id}` page is tracked separately under "Live spectator tracking". |

## Route overlay during run

See [features § Route overlay during run](features.md#route-overlay-during-run).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Live position marker on planned route | ✓ | ✗ | N/A | ✗ | Partial | Apple Watch has `RouteNavigator` scaffolded; not wired to a planned route yet. Wear OS still has no live map during recording — the marker row is blocked behind the live-map initiative, which is genuinely multi-day work and intentionally not in scope yet. |
| Off-route detection and alert | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: the pre-run Route chip opens a picker; the selected route's waypoints flow through `ACTION_START` into `RunRecordingService`, which calls `RouteMath.offRouteDistanceM` per GPS sample. `RunningScreen` shows an "Off route · N m" banner above the distance readout; entering the off-route state fires a double `HapticFeedback.LongPress`. Hysteresis (alert >40 m, clear <20 m) prevents boundary chatter. |
| Distance remaining to end of route | ✓ | ✗ | N/A | ✓ | ✗ | Wear OS: `RouteMath.routeRemainingM` runs alongside off-route per GPS sample; `RunningScreen` renders "X.XX km to go" under the elapsed-distance line whenever a route is loaded. Hidden when `selectedRoute` is null. |

## Run history and analytics

See [features § Run history](features.md#run-history), [features § Analytics dashboard (web)](features.md#analytics-dashboard-web), and [features § Deep run analysis (web)](features.md#deep-run-analysis-web).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Run list | ✓ | Partial | ✓ | ✗ | ✗ | iOS: screen exists with mock data; no API fetch. |
| Run detail (map + stats) | ✓ | Partial | ✓ | ✗ | ✗ | |
| Elevation chart on run detail | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Lap splits table | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Heart-rate zone breakdown | ✗ | ✗ | ✓ | ✗ | ✗ | Web's `/runs/[id]` computes a **time-weighted** zone distribution from per-point `track[].bpm` samples — each sample's slice is half the gap to the previous + half to the next (capped at 30 s either side so a paused recording can't dominate). Falls back to sample-count weighting if any sample is missing a timestamp. Cutoffs come from the user's `hr_zones` settings bag, defaulting to 60/70/80/90/100 % of HR-max when unset. The panel surfaces avg / min / max BPM, the stacked bar, and a legend with both **time-in-zone** and **% of run** per band. When no per-point BPM is present, the card renders an honest empty state (with scalar `metadata.avg_bpm` when available). **Inputs**: Strava live OAuth + ZIP imports both populate `track[].bpm` (live via the streams API; ZIP via GPX `<extensions>/<gpxtpx:hr>` and TCX `<HeartRateBpm><Value>`). Mobile/watch BLE recorders are an additional input path tracked separately under "Live HR via device sensor". |
| Interactive elevation + pace chart | ✓ | ✗ | ✓ | ✗ | ✗ | Android: `run_detail_screen.dart` renders a tap/drag crosshair chart with pace-zone colouring (matches the roadmap's Phase 3 spec). Web equivalent on `/runs/[id]`. |
| Trace animation replay | ✓ | ✗ | ✓ | ✗ | ✗ | Android: FAB on the run-detail map drives an `AnimationController` that advances a pointer along `run.track`; a moving marker renders on `LiveRunMap` via the existing `currentPosition` param. Duration fixed at 15 s regardless of run length. |
| Best-effort auto-detection (1k / 5k / 10k / HM / FM within a run) | ✓ | ✗ | ✓ | ✗ | ✗ | Android: dashboard `_bestEffortCache` + run-detail best-efforts section. |
| PB comparison on same route | ✓ | ✗ | ✓ | ✗ | ✗ | Android: run-detail "Personal best on \{route name\}" section shows PB, time delta, attempt ranking when the run is stamped with a `route_id`. |
| Edit run title / notes | ✓ | ✗ | ✓ | ✗ | ✗ | Web: `updateRunMetadata(id, { title, notes })` on `/runs/[id]`. |
| Manual run entry | ✓ | ✗ | ✓ | ✗ | ✗ | Web: `/runs/new` form (date-time, activity type, distance km, duration min + sec, notes) → `createManualRun` inserts with `source='app'` + `metadata.manual_entry=true`. |
| Delete run | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Bulk delete / multi-select | ✓ | ✗ | ✓ | ✗ | ✗ | Web: `Select` button on the runs list enters selection mode (checkbox cards, sticky "N selected / Delete" bar). Confirm dialog guards the destructive write; `deleteRuns(ids)` runs per-item deletes in parallel so a single 4xx doesn't kill the batch. |
| History sort (newest / oldest / longest / fastest) | ✓ | ✗ | ✓ | ✗ | ✗ | Web: `<select>` in the runs list header. Client-side sort on the already-filtered list so the chosen key persists through filter flips. |
| Date filter | ✓ | ✗ | ✓ | ✗ | ✗ | Web: chip row on `/runs` matching Android's buckets (All time / Today / This week / Last 30 days / This year), composes with source + activity-type + sort. `rangeCutoff(range)` mirrors Android's `_rangeCutoff` with a Monday-start week. |
| Activity-type filter | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Source filter (All / Recorded / Strava / parkrun / HealthKit) | ✓ | ✗ | ✓ | ✗ | ✗ | Android: source chip row on `runs_screen.dart` (All / Recorded / Watch / Strava / parkrun / HealthKit / Health Connect), composes with the activity-type and date filters. |
| Share run as GPX | ✓ | ✗ | ✓ | ✗ | ✗ | Web: Download button on run detail → `toRunGpx` builds GPX 1.1 with per-point `<time>` so the trace round-trips into Strava / Garmin / Komoot as a real activity, not just a route. |
| Share run as image card | ✓ | ✗ | ✓ | ✗ | ✗ | Shipped on web (`/runs/[id]` → "Share as image") — uses `html-to-image` to render a 1080×1080 gradient card with stats and falls back to a PNG download when the Web Share API is unavailable. Android has its own share-sheet integration. 🔸 gap vs web-canonical — watch surfaces to follow if ever needed. |
| Save history run as a reusable route | ✓ | ✗ | ✓ | ✗ | ✗ | Web: "Save as route" icon on run detail prompts for a name, runs the track through Douglas-Peucker (10 m ε, port of `apps/mobile_android/lib/route_simplify.dart` → `apps/web/src/lib/route_simplify.ts`), writes a `routes` row, and back-links `runs.route_id` to the new route. |
| Weekly mileage summary | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Calendar heatmap of runs | ✓ | ✗ | ✓ | ✗ | ✗ | Android: `_RunHeatmap` on the dashboard — 7 × 20-week grid, colour intensity scales by per-day run count, theme-aware primary tint. |
| Personal records table (5k / 10k / HM / FM) | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Multi-goal dashboard (distance / time / pace / count) | ✓ | ✗ | ✓ | ✗ | ✗ | Web: dashboard Goals section with inline editor; `lib/goals.ts` ports the Android `RunGoal` model end-to-end — distance / time / **avg pace** / run count, week or month period. Pace targets are distance-weighted, exclude `metadata.activity_type === 'cycle'`, and use the lower-is-better progress fraction (`target / current`, clamped to 1.0) so a sub-target avg fills the bar. Editor accepts `mm:ss/km` or `mm:ss/mi` per the user's display unit; canonical storage is seconds-per-km. Stored in localStorage. Scalar `weekly_mileage_goal_m` from the settings bag still drives the separate "Weekly goal" progress card above. |
| Week / month / year mileage toggle | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Browsable period summary (prev / next + share) | ✓ | ✗ | ✓ | ✗ | ✗ | Web: `/dashboard/period/[type]/[date]` — prev/next arrows shift by week or month, type toggle switches period, share button uses Web Share API with clipboard fallback. Linked from the This-Week stat card on the dashboard. |

## Sync and backup

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Pull remote runs from Supabase | ✓ | ✗ | ✓ | N/A | N/A | Watches hand off to the phone rather than maintaining their own synced history. |
| Bulk sync button (manual re-push) | ✓ | ✗ | N/A | N/A | N/A | Web has no unsynced-queue concept — it's always online. |
| Auto-sync on connectivity change | ✓ | ✗ | N/A | ✗ | ✓ | Apple Watch syncs on reconnect; Wear OS `drainQueue` is manual / app-start today. |
| Background periodic sync (WorkManager etc.) | ✓ | ✗ | N/A | ✗ | ✗ | |
| Conflict resolution (newer-wins) | ✓ | ✗ | ✓ | N/A | N/A | |
| Backup all runs as JSON | ✓ | ✗ | ✓ | N/A | N/A | Two surfaces on web. (1) **Full backup ZIP** on `/settings/account` (`createBackup()` in `lib/backup.ts`) — same `run-app-backup` v1 wire format as Android, contains `runs.json` + `routes.json` + `profile.json` + `manifest.json` + per-run gzipped tracks; round-trip restores via the same UI. (2) **Single-file `runs-{ts}.json` quick export** in the same Data Export card as the existing CSV — identical row shape to the `runs.json` inside the ZIP (so scripts consume them interchangeably), no tracks, `user_id` stripped. |
| Download all data as CSV (GDPR) | ✗ | ✗ | ✓ | N/A | N/A | |

## Integrations

See [features § External platform sync (OAuth)](features.md#external-platform-sync-oauth).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Connect / disconnect integrations UI | ✓ | Partial | ✓ | N/A | N/A | iOS: settings screen present; flows mocked. |
| Strava OAuth live sync | ✗ | ✗ | ✓ | N/A | N/A | Shipped on web: connect button on `/settings/integrations` redirects to Strava's `/oauth/authorize`, the callback POSTs the code to the `strava-import` Edge Function, and the function exchanges it for tokens + backfills the last 90 days of run/walk/hike activities (GPS streams included). A "Sync now" button re-triggers the backfill. Webhook-driven realtime sync (`strava-webhook`) still needs the activity-detail branch wired; manual sync is the current path. |
| parkrun athlete-number import | ✗ | ✗ | ✓ | N/A | N/A | Web: "Pull latest parkrun results" button on `/settings/account` shows once the athlete number is set. Calls the existing `parkrun-import` Edge Function, surfaces an imported-count toast. |
| HealthKit (iOS / Apple Watch) | ✗ | ✗ | N/A | N/A | ✓ | Apple Watch reads HR and forwards `avg_bpm`. Phone HealthKit importer not started. |
| Health Connect (Android) | ✓ | N/A | N/A | N/A | N/A | Summary-only — no GPS routes. |
| Garmin Connect | ✗ | ✗ | Partial | N/A | N/A | **Live OAuth + webhook sync** is still blocked on Garmin's developer-program approval (NDA, multi-week review, integration call) — neither side can be implemented client-side. **Bulk-import path shipped on web** (`/settings/integrations` → "Bulk import from a Garmin export"): accepts a single `.fit` from "Export Original" or the full `.zip` from `Garmin → Account Management → Request Your Data`. Parses FIT via `fit-file-parser` (lazy-loaded so it only ships when triggered), routes user-uploaded `.gpx` / `.tcx` originals through the existing `parseRouteFile`, dedupes on `metadata.garmin_id` (`<file_id.time_created>-<file_id.serial>`) with a `started_at|distance_m` composite fallback. 🔸 OAuth flow remains the gap; flip to ✓ when Garmin grants developer-program access. |

## Social — clubs and events

See [docs/clubs.md](clubs.md). No features.md section yet — update this row-block when one is added.

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Browse clubs | ✓ | ✗ | ✓ | N/A | N/A | |
| Create club | ✗ | ✗ | ✓ | N/A | N/A | Intentional: admins create clubs on the web. |
| Club detail (feed / events / members tabs) | ✓ | ✗ | ✓ | N/A | N/A | |
| Club posts with threaded replies | ✓ | ✗ | ✓ | N/A | N/A | |
| Create event | ✗ | ✗ | ✓ | N/A | N/A | Intentional: event creation is a web-only admin surface. |
| Event detail + RSVP | ✓ | ✗ | ✓ | N/A | N/A | |
| Recurring events (per-instance RSVP) | ✓ | ✗ | ✓ | N/A | N/A | |
| Invite tokens / join links | ✓ | ✗ | ✓ | N/A | N/A | |
| Join-request approval flow | ✗ | ✗ | ✓ | N/A | N/A | Web-only admin surface. |
| Upcoming-event card on home (within 48h) | ✓ | ✗ | ✓ | N/A | N/A | Web: `fetchNextRsvpedEvent(48)` on dashboard mount; card renders above stats when a matching RSVP exists, links to the event detail page. |
| Realtime subscriptions (posts / RSVPs / members) | ✓ | ✗ | ✓ | N/A | N/A | |
| Push notifications (event reminders, admin updates) | ✗ | ✗ | ✗ | ✗ | ✗ | Phase 4b, blocked on FCM / APNs credentials. |

## Training plans and workouts

See [docs/training.md](training.md) and [docs/workout_execution.md](workout_execution.md). No features.md section yet.

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Plans list | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Create plan (goal race, date, target time) | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Plan detail with weekly grid | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Plan detail with month-by-month calendar | ✗ | ✗ | ✓ | ✗ | ✗ | Web `/plans/[id]` renders `PlanCalendar.svelte` above the weekly grid — projects every workout onto its real date, shades completed days, color-codes by kind. 🔸 gap vs web-canonical. |
| Edit per-day workouts | Partial | ✗ | ✓ | ✗ | ✗ | Android plan editor is still basic. |
| Workout detail screen | ✓ | ✗ | ✓ | ✗ | ✗ | |
| "Today's workout" card on home / dashboard | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Structured-workout execution loop (live rep targets) | ✗ | ✗ | ✗ | ✗ | ✗ | Specced in workout_execution.md; not started. *Physical exception for the live-rep-tracking part* (needs the recorder) but the planner / review UI belongs on web first. |
| Auto-link completed run to planned workout | ✓ | ✗ | ✓ | ✗ | ✗ | |
| Adherence % + weekly summary | ✓ | ✗ | ✓ | ✗ | ✗ | |
| VDOT / Riegel pace derivation | ✓ | ✗ | ✓ | ✗ | ✗ | Derivation engine shared via `core_models`. |
| Adaptive plan generator (phase-banded) | ✗ | ✗ | ✓ | ✗ | ✗ | Shipped on web at `/plans/new` — `lib/training.ts` holds the generator (VDOT + Riegel derivations, phase-banded workout templates) and the wizard persists via `training_plans` + `plan_weeks` + `plan_workouts`. Mobile consumes the generated plan read-side (Android plan detail screen) but cannot yet kick off generation. 🔸 gap vs web-canonical — mobile "new plan" flow to follow. |
| VO2 max estimate | ✗ | ✗ | ✓ | ✗ | ✗ | Shipped on web: `lib/fitness.ts` computes VDOT/VO2 max from the user's best recent qualifying run; the dashboard card renders the latest snapshot plus a sparkline trend from `fitness_snapshots`. 🔸 gap vs web-canonical — mobile dashboard card to follow. |
| Recovery advisor (ATL / CTL / TSB) | ✗ | ✗ | ✓ | ✗ | ✗ | Shipped on web: `lib/fitness.ts` exposes EWMA-based ATL (7-day) / CTL (42-day) / TSB; dashboard renders the numbers plus a rule-based recovery advice string. 🔸 gap vs web-canonical — mobile dashboard card to follow. |

## AI Coach

See [features § AI Coach](features.md#ai-coach).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Chat UI | ✗ | ✗ | ✓ | N/A | N/A | Web-only by design — runners use the coach from a big screen with their plan open. Surface: top-level `/coach` page (sidebar nav) plus a deep-link card on the dashboard and `/plans/[id]`. |
| Plan switcher (multi-plan users) | ✗ | ✗ | ✓ | N/A | N/A | `/coach` exposes a `<select>` listing every plan; choice is round-tripped via `?plan=<id>` in the URL. |
| Configurable runs window (10 / 20 / 50 / 100) | ✗ | ✗ | ✓ | N/A | N/A | Chip selector in the "Grounded in:" strip; sent as `recent_runs_limit` and clamped to `[1, 100]` server-side. |
| Grounded-in context strip | ✗ | ✗ | ✓ | N/A | N/A | Shows the plan, run count, HR-zones-loaded indicator, and weekly goal that `buildContext()` actually loaded. |
| Personality tones (supportive / drill / analytical) | ✗ | ✗ | ✓ | N/A | N/A | |
| Daily usage cap (10 / day) | ✗ | ✗ | ✓ | N/A | N/A | |
| OpenAI-compatible provider switch (local Ollama, etc.) | N/A | N/A | ✓ | N/A | N/A | Dev-only convenience: `COACH_PROVIDER=openai` + `OPENAI_BASE_URL` plumbing in `/api/coach/+server.ts` for testing without Anthropic tokens. Production stays on Claude with prompt caching. |

## Spectating and public sharing

See [features § Deep run analysis (web)](features.md#deep-run-analysis-web) and [roadmap § Live spectator tracking](roadmap.md#live-spectator-tracking).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Public run share page (`/share/run/{id}`) | ✗ | ✗ | ✓ | N/A | N/A | Link generation is web-only; the page renders anywhere. |
| Public route share page (`/share/route/{id}`) | ✗ | ✗ | ✓ | N/A | N/A | |
| Live spectator page (`/live/{run_id}`) | ✗ | ✗ | ✓ | N/A | N/A | Shipped on web: `live_run_pings` table (migration `20260509_001`) streams GPS samples via Supabase Realtime; `/live/{run_id}` subscribes, hydrates any backlog on join, and renders the trace + stats in real time. Falls back to a "demo" animation after 5 s of silence so the page is still useful for previews. Mobile recorder writes are a follow-up — the contract is: insert one `{run_id, user_id, lat, lng, elapsed_s, distance_m, bpm?, ele?}` row per sample, delete on finish. |
| Runner shares a live-tracking link before start | ✗ | ✗ | ✗ | ✗ | ✗ | Not started. *Physical exception for the trigger* (it's during recording, which is mobile-led) but the shareable landing page lives on web. |

## Paywall and funding

See [docs/paywall.md](paywall.md), [features § Pro tier](features.md#pro-tier), and [features § One-off donations](features.md#one-off-donations).

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Pro tier ($9.99 / mo) — server enforcement | N/A | N/A | ✓ | N/A | N/A | `is_user_pro(uid)` RPC + `subscription_tier` column are shared; all clients read `user_profiles` the same way. Server rule lives on the web because the coach endpoint is web-owned. |
| Pro "Get Pro" checkout UI | ✗ | ✗ | ✓ | N/A | N/A | Shipped on web: `/settings/upgrade` "Get Pro" button now calls the RevenueCat web SDK when `PUBLIC_REVENUECAT_WEB_API_KEY` is set; unconfigured builds fall back to the placeholder toast. Mobile purchase flow still pending. |
| Unlimited AI Coach for Pro users | N/A | N/A | ✓ | N/A | N/A | `/api/coach/+server.ts` skips the 10/day cap when `is_user_pro(uid)` is true. Coach chat is web-only today. |
| Priority processing for Pro users | N/A | N/A | Partial | N/A | N/A | Marketing claim backed by the coach-cap bypass; concrete per-endpoint enforcement (queue priority, rate-limit hints) is a follow-up. 🔸 gap vs web-canonical — tier-aware rate limits on Edge Functions first, then the Go service when it lands. |
| One-off Donate button | ✗ | ✗ | ✓ | N/A | N/A | Web `/settings/upgrade` has a single Donate button linking to an external provider. Mobile has no in-app donation flow. |
| Paywall feature gate (registry-driven) | ✓ | ✓ | ✓ | N/A | N/A | `isLocked()` still returns `false` for every key — no feature is hidden behind Pro today. Infra kept so a future Pro-only feature can flip one return. |
| RevenueCat subscription wiring (web) | N/A | N/A | ✓ | N/A | N/A | Shipped on web: `@revenuecat/purchases-js` wired via `$lib/revenuecat.ts`; `/settings/upgrade` "Get Pro" CTA calls `Purchases.purchase(...)` with the Supabase user id as the app user id. Manage-subscription button redirects to `CustomerInfo.managementURL`. Env-gated by `PUBLIC_REVENUECAT_WEB_API_KEY`; builds without a key still compile and fall back to the placeholder toast, so local dev / previews work end-to-end. |
| RevenueCat subscription wiring (mobile) | ✗ | ✗ | N/A | N/A | N/A | `purchases_flutter` package not added; `main.dart` initialisation + `PurchasesConfiguration` pending on both platforms. |

## Settings and preferences

See [docs/settings.md](settings.md) for the full registry of known keys (`user_settings.prefs` + `user_device_settings.prefs`). A cell is `✓` only if the client actually exposes an editor — not if the key merely survives a round-trip through the settings bag.

### Account and identity

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Display name | ✓ | ✓ | ✓ | N/A | N/A | Mobile shows the signed-in email; dedicated display-name editor is web-only. |
| Email address (view) | ✓ | ✓ | ✓ | N/A | N/A | |
| Change password | ✓ | ✓ | ✓ | N/A | N/A | All three call `supabase.auth.updateUser`. |
| Delete account | ✓ | ✓ | ✓ | N/A | N/A | All three call the `delete-account` Edge Function. |
| Sign out | ✓ | ✓ | ✓ | N/A | N/A | Watches sign out when the paired phone does. |

### Universal preferences (U / UD scope)

Written to `user_settings.prefs` and propagate across devices.

| Key | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| [`preferred_unit`](settings.md#keys) (km / mi) | ✓ | ✓ | ✓ | N/A | N/A | Android dual-writes the legacy `profiles.preferred_unit` column through `SettingsSyncService`. Watches inherit from the paired phone. |
| [`default_activity_type`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Editor shipped on all three clients. Neither mobile run screen's activity picker consumes the bag value yet. |
| [`hr_zones`](settings.md#keys) (5-band editor) | ✓ | ✓ | ✓ | ✗ | ✗ | |
| [`resting_hr_bpm`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | |
| [`max_hr_bpm`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | |
| [`date_of_birth`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | |
| [`privacy_default`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Editor shipped; no per-run visibility selector is wired on mobile yet, so the value is set-and-roam only. |
| [`strava_auto_share`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Toggle shipped on all three; enforcement lands when Strava OAuth sync ships. |
| [`coach_personality`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Only consumed by the web coach; mobile edits it for cross-device roaming. |
| [`weekly_mileage_goal_m`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Settings editor writes straight to the bag. The Android dashboard's multi-goal UI still uses a separate local `RunGoal` list — reconciling them is a follow-up. |
| [`week_start_day`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | |
| [`map_style`](settings.md#keys) (UD) | ✓ | ✓ | ✓ | ✗ | ✗ | Editor shipped on all three; mobile's map tile layer doesn't yet swap based on this value. |
| [`units_pace_format`](settings.md#keys) (UD) | ✓ | ✓ | ✓ | ✗ | ✗ | Editor shipped; mobile still derives pace format from `preferred_unit` at render time. |
| [`auto_pause_enabled`](settings.md#keys) (UD) | ✓ | ✓ | ✓ | ✗ | ✗ | Editor shipped. Android removed live auto-pause (derived post-run); the key is still valid for iOS run recording and future watch use. |
| [`auto_pause_speed_mps`](settings.md#keys) (UD) | ✓ | ✓ | ✓ | ✗ | ✗ | |

### Device-scoped preferences (D)

Written to `user_device_settings.prefs`; a dedicated per-device editor is not wired on any client yet.

| Key | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| [`voice_feedback_enabled`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Web editor on `/settings/preferences` writes to the universal bag — mobile/watch recorders pick it up via the existing settings overlay. Mobile's "Spoken split announcements" toggle dual-writes the device bag (overlay-on-signin + push-on-change in `SettingsSyncService`). |
| [`voice_feedback_interval_km`](settings.md#keys) | ✓ | ✓ | ✓ | ✗ | ✗ | Web editor on `/settings/preferences`. Mobile's "Split interval" control dual-writes; unit conversion metres ↔ km happens in `SettingsSyncService`. |
| [`haptic_feedback_enabled`](settings.md#keys) | N/A | N/A | N/A | N/A | Partial | Apple Watch ships haptic pace alerts but the on/off toggle isn't surfaced yet. Wear OS has no haptics ([decisions.md § 15](decisions.md)). |
| [`keep_screen_on`](settings.md#keys) | ✓ | ✗ | N/A | N/A | N/A | Android wakelock during a run is unconditional; the toggle UI is still TODO. |

### Device management

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Device ID mint + `user_device_settings` row on first launch | ✓ | ✓ | ✓ | ✗ | ✗ | Both mobile clients mint a UUID on first launch via `Preferences` and upsert the device row on sign-in through `SettingsService.load`. See [settings.md § Client responsibilities](settings.md#client-responsibilities). |
| Device list / labels screen | ✗ | ✗ | ✓ | N/A | N/A | Web: `/settings/devices`. No mobile equivalent yet. |
| Per-device override editor UI | ✗ | ✗ | Partial | ✗ | ✗ | Web: expanding a device row on `/settings/devices` lists its current `prefs` key/value pairs with a per-row Clear button. Read + delete only today; adding a new override (with key picker + typed value input) is a follow-up. |
| Remove a device / wipe local settings | ✗ | ✗ | ✓ | ✗ | ✗ | Web: resetting the current device deletes its `user_device_settings` row, clears the cached `run_app.device_id` localStorage key, and reloads so the stores reinitialise with a fresh device id. Removing another device just deletes the server row. |

### App-level settings (not in the registry)

Controls that live on a settings screen but aren't part of `user_settings.prefs` — they're either platform-only or stored in a client-local key-value store.

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Dark mode / theme toggle | ✓ | ✗ | ✓ | N/A | N/A | Web: three-way `Auto / Light / Dark` toggle in `/settings/preferences`. Applied via `html[data-theme]` (CSS duplicates the dark block for the explicit override; media query still fires for auto). Persisted to localStorage, per-browser (intentional — a dark laptop + light tablet is common). |
| Offline-only mode switch | ✓ | ✗ | N/A | N/A | N/A | Mirror of the offline-only sync behaviour. |
| HR monitor pairing (BLE) | ✓ | ✗ | N/A | N/A | N/A | External chest-strap pairing; watches use their built-in sensor instead. |
| Advanced GPS filter tuning | ✓ | ✗ | N/A | ✗ | ✗ | Per-activity-type speed / accuracy thresholds. |
| Licenses / open-source notices | ✓ | ✓ | ✓ | ✗ | ✗ | Web: `/legal/licenses` with dep + licence list and map-data / OSM attribution. Linked from the settings sidebar. |
| App version display | ✓ | ✓ | ✓ | ✗ | ✗ | |
| Manage premium subscription | ✗ | ✗ | Partial | N/A | N/A | Web: "Manage subscription" button on `/settings/upgrade` when the user is Pro. Currently a toast explaining the App Store / Play Store / billing-portal flow — swaps for a real `managementURL` deep-link once the RevenueCat web SDK is wired. |
| Funding / donation surface | ✗ | ✗ | ✓ | N/A | N/A | Web-only; see row under *Paywall and funding*. |

## Map and tile layer

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| MapLibre (MapTiler) base tiles | ✓ | ✓ | ✓ | ✗ | ✗ | Watches render pre-downloaded tiles only. |
| Offline tile cache (HTTP replay) | ✓ | ✗ | ✗ | ✗ | ✗ | Browsers rely on HTTP cache headers; iOS not wired. |
| Self-hosted Protomaps tiles | ✗ | ✗ | ✗ | ✗ | ✗ | Deferred — see roadmap § Future — Protomaps. |

## Map matching (post-run clean-up)

| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|
| Server-side HMM map matching | ✗ | ✗ | ✗ | N/A | N/A | Deferred — see roadmap § Future — Map matching. Runs server-side, so all clients would benefit equally when shipped. |

---

## Updating this matrix

1. **When adding a feature**, add a row in the most relevant section (or create a new section). Set every platform cell explicitly — don't leave blanks.
2. **Intentional gaps** (e.g. pedometer on web) go in as `N/A` with a one-line Notes entry. The point is that a reviewer can tell the difference between "we haven't built it" and "we can't build it".
3. **Partial** cells should either link to the follow-up ticket in Notes, or state what's missing, so the next visitor can act on it.
4. **When removing a feature**, delete the row — don't mark it `✗` everywhere. The matrix is a living reflection of the product, not a graveyard.
5. **PR hygiene**: the repo's PR template asks you to confirm this doc is up to date when the PR is user-visible. If you skipped the update because the change was internal only, say so in the PR description.
