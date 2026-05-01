# Manual testing guide

What to test, on which platform, and how. This guide covers the **shipped** features only — see [parity.md](parity.md) for the full feature × platform matrix and [roadmap.md](roadmap.md) for what's still pending.

For the unit / widget test suites that run automatically, see [testing.md](testing.md). This file is for hands-on verification — what you'd run before shipping a release, after a refactor, or when a bug report needs reproducing.

---

## Index

- [Setup once, before anything else](#setup-once-before-anything-else)
- [Platform-by-platform launch checklist](#platform-by-platform-launch-checklist)
- [Auth and onboarding](#auth-and-onboarding)
- [Recording a run](#recording-a-run)
- [Run detail and history](#run-detail-and-history)
- [Routes — create, follow, share, star](#routes--create-follow-share-star)
- [Map matching (server-side snap)](#map-matching-server-side-snap)
- [Sync and offline](#sync-and-offline)
- [Watch ↔ phone handoff](#watch--phone-handoff)
- [Training plans and workout execution](#training-plans-and-workout-execution)
- [Coach (Claude / OpenAI-compatible)](#coach-claude--openai-compatible)
- [Clubs, events, and the social layer](#clubs-events-and-the-social-layer)
- [Notifications inbox](#notifications-inbox)
- [Segments](#segments)
- [Photos on runs](#photos-on-runs)
- [Live race spectator + race mode](#live-race-spectator--race-mode)
- [Imports — Strava, Garmin, parkrun, Health Connect, HealthKit](#imports--strava-garmin-parkrun-health-connect-healthkit)
- [Privacy zones](#privacy-zones)
- [Paywall and RevenueCat](#paywall-and-revenuecat)
- [Backup, restore, account deletion, GDPR export](#backup-restore-account-deletion-gdpr-export)
- [Cross-platform fixture contract](#cross-platform-fixture-contract)

---

## Setup once, before anything else

Local Supabase stack must be up before any client can do meaningful work.

```bash
# 1. Start Supabase
cd apps/backend && supabase start
# Note the env keys (the local stack uses Publishable + Secret keys, not anon/service_role)
supabase status -o env
```

The local stack ports: API `54321`, DB `54322`, Studio `54323`, Mailpit `54324`. The web dev server runs on `7777`, preview on `8888`. The seed user is **`runner@test.com` / `testtest`**, with 12 seeded runs and 5 routes (Melbourne-area; matches the OSRM dev region).

For each app the canonical environment-setup guide is its own `local_testing.md`:

- [apps/backend/local_testing.md](../apps/backend/local_testing.md)
- [apps/web/local_testing.md](../apps/web/local_testing.md)
- [apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md) — also covers most of iOS (the iOS doc just defers to it for shared setup)
- [apps/mobile_ios/local_testing.md](../apps/mobile_ios/local_testing.md) — Mac-specific bits only
- [apps/watch_wear/local_testing.md](../apps/watch_wear/local_testing.md)
- [apps/watch_ios/local_testing.md](../apps/watch_ios/local_testing.md)

---

## Platform-by-platform launch checklist

Smoke test that each surface can come up at all. Do this first when something feels broken — most "feature X is broken" bug reports collapse to "I never had a session in the first place".

### Web

```bash
cd apps/web && pnpm dev
# Open http://localhost:7777
```

**Pass:**
- Login page renders.
- Sign in as `runner@test.com` / `testtest` succeeds.
- Dashboard loads with at least one weekly mileage row populated from seed runs.
- Sidebar shows the unread-notifications bell + the user's display name.

If `pnpm dev` errors on a missing module, run `pnpm install` once. The repo is npm-canonical at the workspace root but `apps/web` itself still uses pnpm.

### Mobile (Flutter — Android / iOS twin)

```bash
cd apps/mobile_android && flutter run -d <device>
# or for iOS:
cd apps/mobile_ios && flutter run -d <iOS simulator or device>
```

**Pass:**
- Onboarding permission ask renders.
- Email/password sign-in succeeds against the local stack.
- Home screen lists the 12 seed runs.
- Tapping a run opens run detail with map + splits + elevation.

The two Flutter apps share `lib/` byte-for-byte ([decisions.md §39](decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)) — every behavioural test you do on one should produce the same result on the other unless platform-specific (Apple Sign-In on iOS, Google Sign-In on Android, Health Connect vs HealthKit).

### Wear OS

```bash
cd apps/watch_wear/android
./gradlew installDebug
```

**Pass:**
- App launches, shows pre-run screen.
- With `BYPASS_LOGIN=true` in `.env.local` it auto-signs in to the seed account.
- Tapping `Start` countdowns 3-2-1, then begins recording.
- Stopping queues a sync; if Supabase is reachable, the queued-count badge clears.

### Apple Watch

```bash
cd apps/watch_ios && open WatchApp.xcodeproj
# Select the Watch scheme + simulator, ⌘R
```

**Pass:**
- App launches in simulator.
- Pre-run screen renders.
- Start → countdown → recording. The Watch Connectivity bridge to the paired-phone Flutter app receives the run on stop (verify in `mobile_ios` logs: `WatchIngestBridge: received WCSessionFile`).

---

## Auth and onboarding

| Surface | What to test | How |
|---|---|---|
| Web — email/password | New account + existing account, password reset email lands in Mailpit | `/login`, then check `http://localhost:54324`. |
| Web — Google OAuth | One-tap sign-in returns to the dashboard | `/login` → Continue with Google. Needs a real Google client id (won't work on stock seed). |
| Web — Apple OAuth | Same as Google | `/login` → Continue with Apple. Needs the Apple Services ID. |
| Mobile — Google Sign-In | One-tap exchanges ID token through `ApiClient.signInWithGoogleIdToken` | `sign_in_screen.dart`. Needs the Google client id baked into `dart_defines.json`. |
| Mobile — Apple Sign-In | Same shape, returns to home | iOS: needs the Apple Sign-In capability + Services ID configured. Android: works against any Apple ID; the button is rendered on both platforms ([decisions.md §39](decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). |
| Mobile — email/password | Same | Same screen. Always works against local stack. |
| Wear OS — phone handoff | Phone signs in, watch picks up the session via the Wearable Data Layer | After signing in on the Android phone with the watch paired, force-stop the watch app and re-open — pre-run loads without the sign-in chip. |
| Wear OS — direct sign-in | Watch-only email/password for LTE watches with no paired phone | Press the **Sign in** chip on pre-run, type the seed creds. |
| Apple Watch — phone handoff | iPhone signs in, watch reads via WatchConnectivity `applicationContext` | Sign in on `mobile_ios`, then on the simulator launch the Watch app. |

**Onboarding gotchas:**
- Mobile permission ask must fire before any GPS feature works. If location permission is `whileInUse` only, background recording will silently stop when the screen locks; the app surfaces an inline banner asking to upgrade.
- iOS needs `NSLocationAlwaysAndWhenInUseUsageDescription` in Info.plist (real device) for background recording — simulator works without it.
- Watch onboarding paths require the corresponding phone permission already granted, otherwise the bridge buffers payloads forever.

---

## Recording a run

The most-tested surface in the codebase. The recording state machine + filter chain lives in `packages/run_recorder/lib/src/run_recorder.dart`; see [run_recording.md](run_recording.md) for the L0–L4 layering and what each layer guarantees. Manual coverage:

### Mobile (Android / iOS)

| Scenario | Steps | Pass criteria |
|---|---|---|
| Cold start, simple loop | Open app → Record → Start → walk a small loop → Stop → Save | Map renders the path; distance > 0; duration ticks at ~1 Hz; splits table populated; run lands on the home screen. |
| Auto-pause | Stop moving for 8 s mid-run | Status pip flips to `Paused`; resumes automatically when motion resumes; the paused gap is not counted in distance or moving time. |
| Manual pause | Tap pause → wait 30 s → resume | Same as auto-pause. Pause segments are gapped on the map polyline. |
| Lap mark | Tap Lap mid-run twice | Two laps appear in the splits table with correct deltas; `metadata.laps` is written to the run; the per-lap shape matches [metadata.md](metadata.md) (1-based `index`, cumulative-BEFORE `start_offset_s`, per-lap `distance_m` + `duration_s` deltas). |
| GPS lost mid-run | Disable location → wait 30 s → re-enable | "GPS lost" banner appears with the dropout count; resuming GPS clears it; track has a small gap, total distance excludes the no-fix interval. |
| Permission revoked mid-run | Background-pull location permission → return to app | "Location permission revoked" banner; recording continues against last-known until permission returns. |
| Audio cues at split | Set split interval to 1 km in Settings → record a 2 km run | TTS announces "1 kilometre. Pace 5 minutes 30 seconds per kilometre" at the 1 km split. |
| Activity-type filter | Switch chip to Walk, record a slow 200 m | Run saves with `metadata.activity_type='walk'`; the home filter chip surfaces it under Walk, not Run. |
| Off-route detection | Pick a route in pre-run, run perpendicular to it | "Off route · N m" banner with hysteresis at 40 m on, 20 m off; haptic on entry. |
| Workout execution | Start a `plans/[id]/workouts/[wid]` from the home Today card | Live workout band shows current step; Skip / Abandon work; finished metadata carries `plan_workout_id` + `workout_step_results` (see [workout_execution.md](workout_execution.md)). |
| Crash recovery | Open run, get to ~1 km, force-kill the process, re-open | Home screen surfaces a "Recover unsaved run?" prompt; accepting saves a run reconstructed from the incremental snapshot with `metadata.recovered_from_crash=true`. |

**GPS simulation in the emulator:** Android Studio → emulator controls (`...` button) → Location → Routes → import a GPX or draw a path; play it back. iOS Simulator → Features → Location → Custom Location / Freeway Drive.

### Wear OS

| Scenario | Steps | Pass criteria |
|---|---|---|
| Standalone recording | Watch alone (no phone), Start → walk → Stop | Run records, queues to `LocalRunStore`, syncs when WiFi/cell is available. |
| 3-second countdown | Tap Start | Full-screen `CountdownOverlay` shows 3 → 2 → 1 (cancel by tapping anywhere). The recording service isn't live during the countdown. |
| Hold-to-stop | Tap stop briefly, then hold for 800 ms | Brief tap doesn't end the run; the 800 ms hold (with progress ring fill) does. Prevents accidental stops on long runs. |
| Lap haptic | Tap Lap mid-run | Haptic confirmation pulse fires; lap appears on PostRun summary. |
| Pace alert | Pre-run set Pace target to 5:30/km, run faster or slower than target | After ~50 m stabilisation, double-pulse haptic for "speed up", single-pulse for "slow down"; rate-limited to one alert per 30 s; TTS nudge accompanies. |
| Route follow + active-run tile | Pre-run pick a route → Start → swipe to the tile carousel | Active-run tile shows status pip (RUNNING/PAUSED), elapsed time as headline, distance + pace stat row. Route polyline rendered on the round canvas with track-so-far fade-in. |
| Connectivity drain | Stop Supabase → record a run → restart Supabase → wait | Run uploads via `RunViewModel.observeConnectivity` watching `system/NetworkWatcher.kt`'s offline → online edge. Queued-count badge clears without user action. |
| Indoor mode (no GPS) | Toggle off Location on the watch → Start | Elapsed clock ticks regardless; distance stays 0; banner reads "No GPS — time only". Stopping produces a valid empty `[]` track that uploads + renders cleanly. |

### Apple Watch

| Scenario | Steps | Pass criteria |
|---|---|---|
| Standalone recording | Watch app → Start → walk → Stop | Run records via `HKWorkoutSession` + `CLLocationManager`; transfers to phone on stop via WatchConnectivity. |
| BPM stream | Wear the watch → record a run | `metadata.avg_bpm` is set on the run; track points carry per-point `bpm` (the recorder pulls `HKLiveWorkoutBuilder` HR samples). |
| Phone ingest | After Stop, open the iOS Flutter app | Run appears in the home list within a few seconds; `lib/watch_ingest_queue.dart` decoded the payload via the `run_app/watch_ingest` method channel and saved through `LocalRunStore.save`. |

---

## Run detail and history

| Surface | What to test |
|---|---|
| Web `/runs` | List paginates, source + activity-type filters narrow the list, the timeline ordering is descending. |
| Web `/runs/[id]` | Map renders the track (raw or matched — see [§ Map matching](#map-matching-server-side-snap)), elevation profile + splits + segments are populated, edit Title / Notes / Activity type round-trips through `data.ts:updateRun`. |
| Web run share | Toggle `is_public` → copy link → open in incognito → page loads, track is privacy-clipped (see [§ Privacy zones](#privacy-zones)). |
| Mobile run detail | Same map + splits + elevation; share-as-GPX produces a valid file; delete confirms then removes the run from the list and Storage. |
| Mobile edit | Edit title + notes through the bottom sheet → reopens with values; offline edits sync when connectivity returns. |
| Personal records | Sign in → check `/dashboard` PB card on web or the home PB row on mobile. Importing a fast run should bump the relevant PB. |

---

## Routes — create, follow, share, star

| Scenario | Surface | Steps | Pass criteria |
|---|---|---|---|
| Browse my routes | Mobile + Web `/routes` | Default tab lists owned routes | Card per route with distance + thumbnail; tap opens detail. |
| Explore community routes | Web `/routes?tab=explore` | Search a tag, browse the cards | `RouteExplorer` populates from `search_public_routes` RPC; clicking opens the detail screen. |
| Create a route | Web `/routes/new` | Click points on the map, save with a name | Route saves; OSRM-snapped polyline (Web uses OSRM client-side for the planner — separate from the server-side run-match OSRM) appears in the saved-routes list. |
| Import a route file | Mobile + Web | Upload a GPX / KML / KMZ / GeoJSON | `gpx_parser` decodes it, route appears in the list, distance + waypoint count look right. |
| Follow a route | Mobile run pre-screen | Pick a saved route → Start | Live banner shows distance-to-go; off-route detection fires if you stray. |
| Star a route for the watch | Web `/routes/[id]` header or mobile route detail | Tap the star toggle | Watch route picker (Wear OS) shows the route at the top, ordered by `updated_at` desc, capped at 30. Un-starring removes it. See [decisions.md §44](decisions.md#44-watch-route-picker-is-gated-by-an-owner-curated-is_starred-flag-not-recents-or-all-routes). |
| Public route share | Web | Toggle `is_public` on `/routes/[id]` → copy `/share/route/[id]` link → open in incognito | Page renders without auth; map shows a privacy-clipped trace if owner has zones. |
| Auto-link a recorded run | Any client that completes a recording near a saved route | Record a run that mostly overlaps a saved route | After the worker completes (see [§ Map matching](#map-matching-server-side-snap)), the run shows a "Suggested route" banner; accept links the run via `data.ts:linkRunToRoute`. |
| Route history | Web | Open a route's detail | "Past efforts" panel lists every prior run on this route with date + time. Sourced from `route_history.ts` (10 unit tests). |

---

## Map matching (server-side snap)

The Go worker at `apps/job_worker/` drains the `jobs` queue. Default matcher is the passthrough shim; set `OSRM_URL` to swap to OSRM. Full local recipe: [apps/job_worker/osrm/README.md § Smoke test](../apps/job_worker/osrm/README.md#smoke-test) — `make smoke` is the one-line driver.

| Scenario | Steps | Pass criteria |
|---|---|---|
| End-to-end OSRM smoke | `cd apps/job_worker/osrm && make smoke` (with OSRM up + worker running with `OSRM_URL` set) | Inserts a Melbourne run; polls until `run_matched_tracks.status='matched'`; prints raw vs matched coords side-by-side. Coordinates differ — that's the snap. |
| Web display of matched track | Open `/runs/[id]` on web for a run whose match has finished | Corner pill says **Snapped to roads**; `RunMap.track` is the matched line, not the raw zig-zag. |
| Pending state | Open `/runs/[id]` immediately after creating a run | Pill says **Snap pending**; raw track renders. Refresh after the worker finishes (1–2 s) and the matched line takes over. |
| Failed / skipped | Insert a run with a track outside the OSRM region (e.g. London coords against the Victoria PBF) | `status='skipped'`; pill flips to absent; raw track keeps rendering. The run is preserved. |
| Re-match on engine bump | Bump `OSRMMatcher.AlgVersion` and force a re-match (`update run_matched_tracks set status='pending', algorithm_version=null where run_id='...'`) | Worker picks the row up via the trigger, produces a new matched blob, web reads the fresher line. |
| Mobile read path | Open run detail on mobile for a matched run | `_matchInfo` populated; `RunMap` shows the matched line; `_RouteSuggestBanner` surfaces if a candidate scored above the auto-link threshold. |

---

## Sync and offline

| Scenario | Steps | Pass criteria |
|---|---|---|
| Mobile offline → online | Stop Supabase, record + save 2 runs, restart Supabase, foreground the app | Both runs upload via `LocalRunStore` drain; counter on the home screen reaches zero; runs appear on web. |
| WorkManager periodic sync | Background the app for >15 min | `Workmanager.registerPeriodicTask` should drain the queue; check `adb shell dumpsys jobscheduler` for the scheduled job. iOS runs the same path through `BGTaskScheduler`. |
| Conflict (newer-wins) | Edit a run's title on mobile while offline; edit the same run on web | When mobile reconciles, `last_modified_at` decides the winner. Verify via `metadata.last_modified_at` on the row. |
| Bulk re-push | Mobile Settings → Resync all runs | All runs re-upload; existing rows should be a no-op, new local-only rows insert. |
| Watch ↔ phone | Record on Wear OS while phone is offline | Run queues on the watch; uploads when watch reconnects (independent of the phone). |
| Apple Watch ↔ phone | Record on Apple Watch with phone in airplane mode | `WatchIngestQueue` on iOS Flutter persists the payload to disk; replays after sign-in / connectivity returns. No runs lost across restarts. |

---

## Watch ↔ phone handoff

| Scenario | Surface | Steps | Pass |
|---|---|---|---|
| Wear OS session push | Wear OS + Android phone, paired | Sign in on phone → watch app reads `{access_token, refresh_token, user_id, base_url, anon_key, expires_at_ms}` from `/supabase_session` data layer | Watch pre-run shows the user's display name without the Sign-in chip. |
| Wear OS token refresh | Wear OS | Let the watch sit until the access token expires, then drain the queue | `RunViewModel.refreshIfExpired` exchanges the refresh token; `drainQueue` retries once on HTTP 401 by refreshing then re-pushing. Sync succeeds. |
| Apple Watch run ingest | Apple Watch + iOS Flutter | Record on the watch, stop, foreground iOS Flutter | Watch transfers a `WCSessionFile` (gzipped JSON track + metadata); `WatchIngestBridge.swift` posts to Dart via `run_app/watch_ingest`; `LocalRunStore.save` persists; run appears in the home list. |
| Pre-Flutter buffering | Apple Watch | Send a watch payload while the iOS Flutter app is force-stopped | `WatchIngestBridge` buffers in-process; flushes on next attach. |
| iOS WatchIngestQueue persistence | iOS Flutter | Receive a watch payload, then sign out before sync, then sign in | The queue persists to disk and replays on sign-in — no run lost. |

---

## Training plans and workout execution

See [training.md](training.md) for the engine + week phasing logic, and [workout_execution.md](workout_execution.md) for the live execution loop.

| Scenario | Steps | Pass criteria |
|---|---|---|
| Generate a plan | Web `/plans/new` → wizard | Plan creates with N weeks of phased volume; week grid editable; submit persists `training_plans` + `plan_weeks` + `plan_workouts`. |
| Edit a plan's meta | Web `/plans/[id]` → Edit-plan button | Owner-only `PlanMetaEditor` modal; non-owners get a 403 from RLS. |
| Execute a workout | Mobile Today card → Start | Live workout band shows current step; Skip / Abandon callbacks work; finished run carries `plan_workout_id` + `workout_step_results` + `workout_adherence` per [metadata.md](metadata.md). |
| Workout review | Mobile run detail of a plan run | "Workout review" section renders one row per step; on / amber / off tones based on the 10 s tolerance; em-dash for null pace. |
| Auto-link to plan workout | Record a run on the same date as a scheduled workout | `autoMatchRunToPlanWorkout` ties the run to the workout; the workout flips to completed. |
| Clone from template | Web → `clone_plan_template` RPC via club-shared template | New plan owned by caller, dates shifted by `(new_start - template_start)`; `parent_template_id` points back at the source. See [decisions.md §35](decisions.md). |
| Pace anchoring | Provide a `current_5k_seconds` on the wizard | Plan workouts use VDOT-derived paces; without 5k anchor, falls back to volume-only structure. |

---

## Coach (Claude / OpenAI-compatible)

The Coach endpoint at `/api/coach/+server.ts` is the only server-runtime web route — Vercel adapter, not static. Defaults to Claude (`ANTHROPIC_API_KEY`); set `COACH_PROVIDER=openai` + `OPENAI_BASE_URL` to point at a local Ollama or OpenAI-compatible proxy.

| Scenario | Steps | Pass |
|---|---|---|
| Send a message | `/coach` page → type a question | Streams a response; grounded-in context strip lists which runs/plans were sent. |
| Plan switcher | `?plan=<id>` query param | Coach context is scoped to the picked plan only. |
| Runs window | Adjust the 10/20/50/100 selector | More history loaded into context; visible in the strip. |
| Rate limit | Send >N requests as a free user (config in `check_rate_limit_tiered`) | 429 with Retry-After; pro users see a higher ceiling. |
| Pro-only paths | `/api/coach` calls `is_pro()` to gate paywalled features per [paywall.md](paywall.md) | Free users hit the hard ceiling; pro users get the higher one. |

---

## Clubs, events, and the social layer

See [clubs.md](clubs.md) for the deferred items.

| Scenario | Steps | Pass |
|---|---|---|
| Create a club | Web `/clubs/new` | Club created with visibility + join policy; creator becomes admin. |
| Invite link | Club → Invite | Generate token; `/clubs/join/[token]` redeems via `join_club_by_token` RPC. Atomic — partial failures roll back. |
| Club feed | `/clubs/[slug]/feed` | Threaded posts; admins can pin / delete; per-event update threads. |
| Create event | `/clubs/[slug]/events/new` | One-off OR weekly/biweekly/monthly recurrence (see `recurrence_test.dart` — 8 tests pin the expansion). RSVP per-instance. |
| Event detail | `/clubs/[slug]/events/[id]` | RSVP toggles `event_attendees` row; updates list under the event; recurring events render the next instance with its own state. |
| Approve event result | Admin on `/clubs/[slug]/events/[id]` | `approve_event_result` RPC flips the row visibility (decisions.md mentions the role separation). |
| Club-owned route | Admin on `/routes/[id]` → Transfer to club | `routes.club_id` set; non-members can't see the route in My routes but can see it under the club's Routes tab. |

---

## Notifications inbox

| Scenario | Steps | Pass |
|---|---|---|
| Bell badge | Web sidebar | Badge shows unread count; tapping opens the popover with recent items. |
| Full inbox | `/u/[me]?tab=notifications` | All / Unread tabs; per-row dismiss; bulk Mark-all-read. Only visible when `isSelf`. |
| Generation triggers | On another account: kudos, comment, follow `runner@test.com` | New rows appear under the bell; mark-as-read clears the unread badge. Triggers are SECURITY DEFINER (notify_run_kudos / notify_run_comment / notify_user_follow). See [decisions.md §38](decisions.md#38-notifications-inbox-is-a-notifications-table-fed-by-security-definer-triggers). |
| Push subscription | `/settings/devices` → Enable push | Browser prompts for permission; subscription persists to `user_device_settings.prefs.push_subscription`. Triggering a notification fires a real push to that browser via `apps/web/static/sw.js`. |

---

## Segments

See [decisions.md §37](decisions.md#37-segments-v1-are-slices-of-a-saved-route-not-arbitrary-geometry).

| Scenario | Steps | Pass |
|---|---|---|
| Segment leaderboard | Web `/routes/[id]` → Segments panel | `SegmentsPanel` renders the segment list with leaderboard. |
| Segment efforts on a run | Web `/runs/[id]` → run-segment-efforts strip | Auto-effort generation from the matched (or raw) track; pure compute via `lib/segments.ts` (8 unit tests pin haversine distance + timestamp interpolation). |
| Manual segment creation | Owner on `/routes/[id]` | Define a segment by start/end on the route; new segment writes to `segments` + automatically creates `segment_efforts` for prior runs on that route. |

---

## Photos on runs

See [decisions.md §36](decisions.md#36-photos-on-runs-own-table--storage-bucket-visibility-tracks-the-parent-run).

| Scenario | Steps | Pass |
|---|---|---|
| Add photo | Web run detail (owner) | Upload via `RunPhotos` widget; appears in the gallery. |
| Public run photos | View `/share/run/[id]` for a public run with photos | Gallery renders for anonymous viewers; non-public runs return 404 to non-owners. |
| Delete photo | Owner only | Button visible only when owner; delete removes the row and Storage object. |

---

## Live race spectator + race mode

| Scenario | Steps | Pass |
|---|---|---|
| Spectator (web) | Open `/live/event/[id]/[instance]` while a race is running | Realtime map updates every few seconds with each runner's position from `race_pings`. |
| Race mode start | Race director on `/clubs/[slug]/events/[id]` → Start race | `race_sessions.status` transitions `armed → running`; pings start flowing from connected watches. |
| Race mode finish | Director or auto-finalize | `running → finished`; `event_results` rows are created for finishers; `recompute_event_ranks` orders them. |
| Cleanup | Wait or trigger | `cleanup-stale-live-run-pings` cron purges `race_pings` older than the configured window. |

(Live race recording on the watch is roadmap-pending in some cells; see [parity.md "Live race mode"](parity.md).)

---

## Imports — Strava, Garmin, parkrun, Health Connect, HealthKit

| Source | Surface | Steps | Pass |
|---|---|---|---|
| Strava ZIP (web) | `/settings/integrations` → Strava bulk import | Upload the export ZIP | Activities import; `metadata.strava_id` set for dedupe; tracks land in Storage. |
| Strava OAuth (Edge Function) | OAuth flow then `strava-import` EF | `{action: 'connect', code, scope}` after redirect, then `{action: 'sync'}` for backfill | Activities import; tokens land in Vault via `set_integration_tokens`; `metadata.title` + `metadata.elevation_m` populated when present (recently-fixed bug — these used to be written as columns that don't exist). |
| Strava webhook | `strava-webhook` EF | Send a verification GET, then a POST event | Verification responds with the challenge; activity events are TODO (the EF is partial — see [api_database.md § strava-webhook](api_database.md)). |
| Garmin ZIP (web) | `/settings/integrations` → Garmin bulk | Upload either a single `.fit` or the Account Data `.zip` | Activities import via `garmin-zip.ts`; `metadata.garmin_id` set; routed inner GPX/TCX go through `parseRouteFile`. |
| parkrun (mobile) | Settings → Import parkrun results → enter athlete number | Calls `parkrun-import` EF | New results land as runs with `source='parkrun'`; `metadata.event` + `metadata.position` + `metadata.age_grade` set. |
| Health Connect (Android) | Settings → Import from Health Connect | Pick a date range | Workouts come in via `health_connect_importer.dart`; `metadata.health_connect_type` preserves the original enum. |
| HealthKit (iOS) | Settings → Import from HealthKit | Same | Same shape via the `health` package's HealthKit backend. |

---

## Privacy zones

See [decisions.md §33](decisions.md#33-privacy-zones-server-side-clipping).

| Scenario | Steps | Pass |
|---|---|---|
| Configure zones | Web `/settings/account` → Privacy zones | `PrivacyZonePicker` (MapLibre) lets you draw circular zones; persists to `user_settings.prefs.privacy_zones`. |
| Owner view | Open `/runs/[id]` of a clipped run as the owner | Full track visible — owner is exempt. |
| Public viewer | Same run via `/share/run/[id]` in incognito | Track is clipped: leading + trailing in-zone points removed via the `clip_track_for_user` RPC, contiguous middle returned. Zones never leave the database. |
| Cap | Run with >50 000 points (synthetic) | RPC truncates to bound the dense-grid probe attack. |

---

## Paywall and RevenueCat

See [paywall.md](paywall.md) for the full tier matrix and feature gates.

| Scenario | Steps | Pass |
|---|---|---|
| Pro check | Sign in as a free user; sign in as a pro user | `is_pro()` returns false / true accordingly; pro-gated features (Coach high ceiling, advanced exports) reflect the difference. |
| Upgrade flow (web) | Free user → `/settings/upgrade` → Get Pro | RevenueCat web SDK opens checkout; on success, `revenuecat-webhook` updates `user_profiles.subscription_tier='pro'` + `subscription_at`. |
| Manage subscription | Pro user on `/settings/upgrade` → Manage | `managementUrl(userId)` (lib/revenuecat.ts) opens the billing portal in a new tab. Falls back to "manage where you bought it" toast for App Store / Play Store originated subs. |
| Webhook signing | Send a `revenuecat-webhook` POST without the HMAC header | EF returns 401. |
| Idempotency | Replay the same `event.id` | Second call is a no-op; tier doesn't double-grant. |
| `BYPASS_PAYWALL` | Local dev only — set the env flag | Treats every user as Pro; never enable in prod. |

---

## Backup, restore, account deletion, GDPR export

| Scenario | Steps | Pass |
|---|---|---|
| Web full backup ZIP | `/settings/account` → Create backup | Downloads a `run-app-backup` v1 ZIP with `runs.json` + `routes.json` + `profile.json` + `manifest.json` + per-run gzipped tracks. |
| Web restore | Same screen → Restore | Round-trips the same ZIP; idempotent on `external_id`. |
| Web single-file export | Same screen → Export runs JSON | Downloads `runs-{ts}.json` (no tracks, `user_id` stripped). Identical row shape to the ZIP's `runs.json`. |
| GDPR export (Edge Function) | `export-data` EF call | EF is currently a stub — every step is a TODO. Expect 501-ish behaviour until it ships. |
| Account deletion | Web `/settings/account` → Delete account | `delete-account` EF runs admin delete (User JWT + service role); cascading FKs clear `runs`, `routes`, `clubs` membership, etc. |

---

## Cross-platform fixture contract

The single most important thing to keep aligned across all five clients (mobile_android, mobile_ios, web, watch_wear, watch_ios). One JSON fixture, four tests:

```
fixtures/watch_run_payload.json
├── apps/mobile_android/test/watch_payload_fixture_test.dart
├── apps/mobile_ios/test/watch_payload_fixture_test.dart  (byte-identical twin)
├── apps/web/src/lib/watch_payload_fixture.test.ts
└── apps/watch_wear/.../WatchRunPayloadFixtureTest.kt
```

If you edit the fixture, **all four tests must update** in the same commit. The CI guard runs all four; missing any one is a deliberate hard-fail.

To verify locally:

```bash
# Dart side
cd apps/mobile_android && flutter test test/watch_payload_fixture_test.dart

# Web side
cd apps/web && npx tsx --test src/lib/watch_payload_fixture.test.ts

# Wear OS side
cd apps/watch_wear/android && ./gradlew :app:testDebugUnitTest --tests "*WatchRunPayloadFixtureTest"
```

The contract is precise about lap shape: 1-based `index`, cumulative-BEFORE `start_offset_s`, per-lap-delta `distance_m` + `duration_s`. Every writer must conform. The Apr 2026 audit caught a Wear OS bug here (`start_offset_s` was cumulative-AFTER); the fixture test pinned the fix.

---

## When in doubt

- **Where does this feature live?** Start with [parity.md](parity.md) — every shipped feature is a row with the file pointer in Notes.
- **Why was it built this way?** [decisions.md](decisions.md) is the ADR log.
- **What's still pending?** [roadmap.md](roadmap.md) is the canonical backlog.
- **Per-app local quirks?** That app's own `local_testing.md`.

If a manual test produces a result that contradicts this guide, the guide is wrong. Edit it in the same turn.
