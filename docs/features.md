# Run app — feature specifications

Detailed specs for every feature across all phases. Each entry covers what it does, why it's included, how it works technically, and what done looks like.

---

## How to read this document

Each feature has:
- **Phase** — which release milestone it belongs to
- **Platform** — which surfaces it appears on
- **Why** — the strategic reason it's included (user need or competitive gap)
- **Spec** — what it actually does
- **Done when** — measurable acceptance criteria

---

## Phase 1 — core loop

---

### GPX / KML import

**Phase:** 1 | **Platform:** iOS, Android, Web

**Why:** The primary differentiator. No competitor provides a clean route import pipeline. Runners plan routes in various tools (Google My Maps, Komoot, AllTrails) — the friction of the current export/import workflow is the gap to fill.

**Spec:**

On mobile, users trigger import via the OS share sheet (sharing a file from Google My Maps, Files app, or email) or by tapping an import button inside the app. On web, users drag-and-drop or click to upload.

Supported formats:
- `.gpx` — standard GPS exchange format
- `.kml` / `.kmz` — Google My Maps / Earth export format
- `.geojson` — web mapping standard

On receipt, the file is parsed into a `Route` object (name, waypoint list, total distance, elevation gain). The route is displayed on the map with a summary card showing distance and elevation. The user can rename it before saving.

Routes are stored locally in SQLite (mobile) and synced to Supabase in the background.

**Done when:**
- User can export a KML from Google My Maps on iPhone and open it in the app via share sheet
- Route appears on map within 2 seconds of opening
- Distance and elevation summary are accurate to ±1%
- Route persists across app restarts

---

### Live GPS run recording

**Phase:** 1 | **Platform:** iOS, Android

**Why:** The core product function. Without this nothing else matters.

**Spec:**

On the idle screen the user picks an activity type (run / walk / cycle / hike) and optionally a saved route, then taps Start. If this is the first launch the app walks through the Android location + activity-recognition + notifications permission dialogs.

Tapping Start kicks off a **3-second countdown**. All expensive setup runs *during* the countdown so the run starts instantly when the timer ends: the `RunRecorder` is created, the pedometer sensor is subscribed, the wakelock is enabled, and the GPS position stream is opened via a foreground service (which posts a persistent "Run in progress" notification). Positions received during the countdown drive the live-map blue dot so the user sees their location immediately, but do not accumulate into the track or distance until the countdown ends.

When the countdown ticks to zero, recording flips on synchronously: a monotonic `Stopwatch` starts, a stable run id is generated, the pedometer baseline is reset so steps taken during the countdown don't count, the auto-pause / GPS-lost / incremental-save / permission watchdogs start, and the "Run started" TTS cue plays.

During recording, the screen shows a dark full-screen map with:
- A Nike-Run-Club-style glowing polyline for the recorded track (three stacked layers, gradient from dim indigo to bright lavender, smoothed at render time to reduce GPS jitter)
- A pulsing blue dot for the current position, **tweened between GPS fixes at 60 fps** so it glides rather than hops
- The planned route underneath if one is selected, with a "X to go" badge and off-route alerts at 40 m of drift
- A collapsible glass-blur stats panel at the bottom containing elapsed time, distance, primary metric (pace for run/walk/hike, speed for cycle), average pace/speed, calories, elevation, steps, cadence, and a button row (discard / pause / hold-to-stop / lap)
- Status banners at the top for auto-pause, off-route, GPS lost, and location permission revoked

**Collapsible stats panel**: tap or flick down the drag handle to collapse the panel to a minimal bar showing the time and a stop button. The map's follow-cam automatically offsets the blue dot by half the panel height so the dot sits in the centre of the *visible* map area above the panel, and re-centres itself when the panel is collapsed.

**Manual pause only — no live auto-pause.** The clock runs continuously during a run. If the runner stops at a traffic light, the elapsed clock keeps ticking. An earlier version had live auto-pause with several layers of hardening, but it was the single most bug-prone feature in the recorder and still produced occasional false pauses at slow walking pace. It was removed in favour of the approach Strava and Nike Run Club use: compute **moving time** as a derived metric on the finished-run screen by walking the GPS track and excluding segments where speed fell below ~0.5 m/s. The user can still manually tap pause/resume mid-run.

**Hold-to-stop**: the red stop button requires an 800 ms press before the run ends. A circular progress ring animates around the button during the hold; releasing early cancels. Prevents accidental one-tap stops mid-run.

**Background recording**: GPS tracking continues when the screen is off or the user switches apps, via the foreground service notification. Requires the user to grant location permission as "Allow all the time" and to disable battery optimisation for the app.

**Crash-safe persistence**: the current run state is serialised to disk every 10 seconds. If the app is killed mid-run (OOM, force-stop, battery), the next launch promotes the partial data to a completed run tagged `recovered_from_crash` and shows a snackbar: *"Recovered unfinished run — X.XX km, Y min"*. Tiny runs (< 3 waypoints or < 50 m) are dropped silently.

**Hardening**: the GPS filter chain rejects fixes with accuracy > 20 m, implausible speeds (per-activity, e.g. > 10 m/s for run), and single-hop jumps > 100 m. The elapsed-time clock is a monotonic `Stopwatch` so NTP sync or timezone changes can't corrupt the duration. The pedometer stream auto-resubscribes on error with exponential backoff. A permission watchdog polls `Geolocator.checkPermission()` every 5 seconds and surfaces a banner if the user revokes location mid-run. Activity type is locked once the user has tapped Start.

On hold-to-stop: the run finalises, the in-progress save file is cleared, and the user sees a summary (distance, time, pace, map of the run) on a finished screen. The run is written to local JSON storage and auto-synced to Supabase if signed in, or stored offline otherwise.

**Done when:**
- Recording continues accurately through a 10km run with the screen locked and the app backgrounded
- The elapsed clock never stops unless the user taps manual pause
- The finished-run screen shows both Time (elapsed) and Moving (derived from the track), with pace computed against moving time
- Hold-to-stop prevents accidental ends and the user can still reach it from the collapsed stats bar
- A force-killed run is recovered on next launch with all its data
- The "Run in progress" foreground service notification appears for the entire duration of the run

See [run_recording.md](run_recording.md) for the full technical reference.

---

### Route overlay during run

**Phase:** 1 | **Platform:** iOS, Android

**Why:** Turns a passive GPS tracker into an active navigation tool. Key for users running unfamiliar routes — the feature that makes importing a route actually useful.

**Spec:**

When a user starts a run with a route selected, the map shows:
- The planned route as a blue polyline
- Their current position as a moving dot
- Distance remaining to the end of the route

Off-route detection: if the user strays more than 50m from the nearest point on the route for more than 15 seconds, a haptic alert fires and a banner appears: "Off route — 60m from path." The banner dismisses when they return within 30m of the route.

The map auto-centres on the user's position during the run. Users can pan away to look ahead, and it re-centres after 5 seconds of inactivity.

**Done when:**
- Route is visible on map from the first GPS fix after starting
- Off-route alert fires correctly at 50m deviation and not before
- Map stays centred on user position during normal running
- No battery drain beyond a 10% increase vs. recording without a route

---

### Run history

**Phase:** 1 | **Platform:** iOS, Android, Web

**Why:** The reason users come back every day. The history screen is what makes the app feel like a training log, not just a timer.

**Spec:**

A chronological list of all runs, newest first. Each row shows: date, distance, duration, pace, and source badge (if imported from Strava, parkrun, etc.).

Tapping a run opens the detail view:
- Full-screen map showing the GPS trace
- Key stats: distance, time, average pace, average HR (if available)
- Source label ("Recorded", "Strava", "parkrun")

A weekly summary card at the top of the history list shows total distance and run count for the current week.

**Done when:**
- All recorded and synced runs appear in list within 1 second of opening
- Map renders correctly for runs with and without GPS tracks (parkrun/race imports have no GPS)
- Weekly summary updates immediately after a run is saved

---

### Cloud sync and auth

**Phase:** 1 | **Platform:** iOS, Android, Web

**Why:** Without this, uninstalling the app loses all data. Cross-device access (phone + watch + web) requires a server-side record of all runs.

**Spec:**

Auth providers: Apple Sign-In (required on iOS per App Store guidelines) and Google Sign-In.

On first launch, users see a sign-in screen. After auth, all subsequent app opens check for a valid session silently — no login screen unless the session has expired (30 days).

Sync strategy: write-to-local-first, sync-in-background. Runs are written to SQLite immediately on save. A background sync process uploads pending runs to Supabase within 60 seconds when on wifi or LTE. Conflicts (same run modified on two devices) resolve in favour of the server copy — last-write-wins.

**Done when:**
- User can uninstall and reinstall the app and all runs reappear after sign-in
- Runs recorded on the phone appear in the web app within 60 seconds
- Auth session persists for 30 days without requiring re-login

---

## Phase 2 — watch parity

---

### Apple Watch standalone GPS recording

**Phase:** 2 | **Platform:** Apple Watch (native Swift)

**Why:** The killer feature gap vs. every competitor. Strava, NRC, and AllTrails all require the phone nearby or produce inferior data when the watch is standalone. Runners who leave their phone at home have no good option today.

**Spec:**

The watch app presents a simple pre-run screen: current time, paired route name (if one was sent from the phone), and a Start button.

On Start, a HealthKit `HKWorkoutSession` begins. GPS and HR are recorded independently of the phone using the watch's own sensors.

During recording, the watch face shows:
- Elapsed time
- Distance
- Current pace
- Heart rate

On Stop: run is saved to watch-local storage as an `HKWorkout`. `WCSession` transfers the run data to the iPhone as soon as Bluetooth range is restored. The iPhone app ingests the transfer, deduplicates against any HealthKit record of the same workout, and saves to Supabase.

**Done when:**
- User can run a full 10km with iPhone left at home and have the run appear in history on their return
- HR and GPS data are within 5% accuracy of a simultaneous Garmin recording
- Run appears in the iOS app within 30 seconds of reconnecting to iPhone

---

### Wear OS standalone GPS recording

**Phase:** 2 | **Platform:** Wear OS (Flutter)

**Why:** NRC dropped Wear OS support. Android users with Pixel Watch or Galaxy Watch have no dedicated standalone running app. A genuine gap in a growing market.

**Spec:**

Functionally identical to the Apple Watch app. Flutter on Wear OS, using `compose_for_wear` for the round-screen-optimised UI.

GPS recording via Android Location APIs. HR via Health Services for Wear OS.

On Stop: run transferred to phone via Wear Data Layer API. Phone app ingests and syncs.

**Done when:**
- Identical acceptance criteria to Apple Watch app
- App passes Wear OS review requirements (swipe-to-dismiss, round layout, battery target <5% per hour)

---

### Route navigation on watch

**Phase:** 2 | **Platform:** Apple Watch, Wear OS

**Why:** The combination of standalone GPS + route navigation is what no single competitor delivers on both watch platforms. It's the feature a trail runner or race-day runner most needs.

**Spec:**

Before a run: user selects a route on the phone. The route is transferred to the watch via Watch Connectivity / Data Layer. The watch shows a route preview: name, distance, elevation gain.

During a run: a simplified map tile shows the route as a line with the user's position as a dot. Distance remaining is shown prominently. When the user deviates more than 50m from the route, the watch produces a distinct haptic pattern (two short pulses).

The map on the watch does not pan or zoom — it auto-scales to always show both the user's position and the next ~500m of the route.

**Done when:**
- Route preview appears on watch within 5 seconds of selection on phone
- Off-route haptic fires reliably at 50m deviation during a test run
- Map remains legible in bright sunlight (verified on physical device, not simulator)

---

### Glanceable tiles and complications

**Phase:** 2 | **Platform:** Apple Watch, Wear OS

**Why:** The watch is most useful when data is available without opening an app. Tiles and complications are how the OS surfaces running data in context.

**Spec:**

**watchOS complication:** Two variants:
- Graphic corner: current pace + distance (for during a run)
- Modular small: weekly mileage (for the watch face when not running)

**Wear OS tile:** Single tile showing:
- Today's distance (if a run has been recorded today)
- Weekly distance vs. weekly goal
- Quick-start button to begin a new run

**Done when:**
- Complications display correct data within 30 seconds of a run completing
- Wear OS tile renders correctly on round display
- Complications/tiles survive watch restart and re-display correct data

---

## Phase 2b — web app

---

### Full-screen route builder (web)

**Phase:** 2b | **Platform:** Web

**Why:** Planning routes is fundamentally a desktop task — you want a large screen, precise mouse control, and the ability to cross-reference maps side by side. The mobile route builder is a convenience; the web route builder is the power tool.

**Spec:**

A full-browser-window MapLibre GL JS instance. Users click to place waypoints; the app auto-draws the road-snapped route between them using OSRM or Valhalla routing. Each click appends a new segment.

Controls panel (left sidebar):
- Mode: road / trail (trail mode uses walking profile routing)
- Total distance (updates live as waypoints are placed)
- Elevation profile chart (below the map, updates live)
- Undo last waypoint
- Clear all
- Route name input
- Save to library / export as GPX

Drag-to-reshape: users can drag any point on the route polyline to redirect it, adding an implicit waypoint.

Saved routes appear immediately in the mobile apps on next open.

**Done when:**
- User can plan a 10km road route with 8 waypoints in under 2 minutes
- Elevation profile accurately reflects the drawn route (within 5% of Strava)
- GPX export opens correctly in Strava, Garmin Connect, and the mobile app
- Route appears in mobile app within 60 seconds of saving on web

---

### Analytics dashboard (web)

**Phase:** 2b | **Platform:** Web

**Why:** Reviewing running data is much better on a large screen. This is the screen a runner opens on Monday morning to review last week and plan ahead.

**Spec:**

**Header row:** four stat cards — total distance this week, total runs this month, longest run ever, current weekly streak.

**Mileage chart:** a 12-week bar chart (one bar per week) showing total distance. Toggle between km and miles. Hover shows the exact figure and number of runs.

**Calendar heatmap:** a GitHub-style contribution graph where each day's square is shaded by distance run. Hovering shows the run(s) on that day. Clicking navigates to the run detail.

**Personal records table:** best times for 5k, 10k, half marathon, and marathon. Shows time, date, and a link to the run.

**Recent runs list:** last 10 runs with source badge, distance, pace. Click to open run detail.

**Done when:**
- Dashboard loads all data in under 2 seconds for a user with 200 runs
- Mileage chart reflects all sources (recorded + Strava + parkrun)
- Personal records update within 60 seconds of a new qualifying run being saved

---

### Deep run analysis (web)

**Phase:** 2b | **Platform:** Web

**Why:** The full GPS trace, split tables, and HR zone breakdowns are the features that make a running app worth paying for. They're much more useful on a big screen.

**Spec:**

Full-page view for a single run:

- **Map (left, ~60% width):** full GPS trace on a MapLibre satellite/terrain hybrid. Start and finish markers. Option to animate the trace (replay the run as a moving dot). Hover on the trace highlights the corresponding point on the elevation and pace charts.
- **Stats sidebar (right, ~40% width):**
  - Distance, duration, average pace, average HR, elevation gain
  - Splits table: one row per km (or mile), showing pace, HR, elevation delta
  - HR zone breakdown: time in each of 5 HR zones as a horizontal stacked bar
  - Comparison: "vs. your best on this route" (if the user has run this route before)

**Done when:**
- Map renders within 3 seconds for a run with 5,000 GPS points
- Splits table is accurate to within 1 second per km vs. Garmin data for the same run
- Trace animation plays at 60fps on a modern laptop

---

## Phase 3 — growth and monetisation

---

### In-app route builder (mobile)

**Phase:** 3 | **Platform:** iOS, Android

**Why:** Users should be able to plan routes on their phone without needing a computer. Strava paywalls this. Komoot does it well on mobile. This is a top acquisition driver.

**Spec:**

A simplified version of the web route builder, optimised for touch:
- Tap to place waypoints
- Road-snap by default, with a trail mode toggle
- Live distance counter as waypoints are placed
- Elevation preview as a small chart below the map
- Save to library or export as GPX

Gesture UX: pinch to zoom, long-press to undo last waypoint, double-tap to finish.

**Done when:**
- User can plan a 5km loop in under 3 minutes on a phone
- Route appears in web app and on watch within 60 seconds of saving

---

### Premium tier

**Phase:** 3 | **Platform:** iOS, Android, Web

**Why:** The business model. Free users generate the user base; premium users generate revenue. The paywall should feel fair — the free app is genuinely great; premium adds intelligence.

**Spec:**

Price: $5.99/month or $49.99/year. Managed via RevenueCat (abstracts App Store + Play Store in-app purchases).

**Free forever:**
- Unlimited run recording
- Route import (GPX, KML, GPX)
- Route builder (mobile + web)
- Run history with map
- Basic stats (distance, pace, time)
- Strava, HealthKit, Health Connect sync
- parkrun import

**Premium:**
- Training plans (5k, 10k, half, full marathon — adaptive based on current fitness)
- VO2 max estimate (calculated from pace and HR data)
- Recovery advisor (days to next hard run, based on training load)
- Race pace calculator
- HR zone analysis
- Splits comparison vs. personal best
- Advanced elevation analysis
- Offline maps

**Done when:**
- In-app purchase flow works on both iOS and Android
- Premium features gate correctly — non-paying users see a paywall prompt, not a crash
- RevenueCat webhook updates `subscription_tier` in Supabase within 60 seconds of purchase

---

### Community route library

**Phase:** 3 | **Platform:** iOS, Android, Web

**Why:** Network effects and organic SEO. Every public route creates an indexed page. Discovery of "popular routes near me" creates engagement loops that keep users returning.

**Spec:**

**Discovery feed:** routes near the user's current location, sorted by popularity (number of runs). Filters: distance range, surface type, elevation gain. Each card shows: route name, map thumbnail, distance, elevation, number of runners who've completed it.

**Route detail page (public):** accessible without login. Shows the route on a map with elevation profile, top-level stats, and a list of recent completions (anonymised unless user has opted into public activity). Open Graph metadata for social sharing.

**User controls:** each saved route has a visibility toggle — private (default) or public. Public routes appear in the community library. Toggling back to private removes them from the library but does not delete the page immediately (48-hour grace period).

**Done when:**
- Public routes for a given location are discoverable without login on the web
- Route pages are indexed by Google within 7 days of creation
- Switching a route to public makes it appear in the community feed within 5 minutes

---

## AI Coach

**Phase:** 3 (shipped) | **Platform:** Web

**Why:** Runners want a "second opinion" on their plan adherence without hiring a human coach. The coach is grounded in the user's actual data (plan, recent runs, settings) and deliberately scoped to avoid liability (no plan generation, no medical/nutrition advice).

**Spec:**

Claude-powered chat embedded in the web app via `CoachChat.svelte`. The server endpoint at `/api/coach/+server.ts` sends the user's active training plan, recent runs, and profile/preferences as cached context, then streams the conversation. Two prompt-cache breakpoints (system prompt + context dump) keep repeat turns cheap.

**Personality tones:** The `coach_personality` user setting (`supportive` / `drill_sergeant` / `analytical`) injects a tone override into the system prompt. Default is `supportive`.

**Usage limits:** 10 messages per user per day, enforced server-side by `increment_coach_usage` RPC. The UI shows "N of M remaining" before the user types. `BYPASS_PAYWALL=true` skips the limit in dev.

**What the coach does:**
- Critique adherence (hitting planned sessions, mileage, pace targets)
- Answer "should I run today?" questions using plan + recent runs
- Explain what a workout is designed to achieve
- Flag red flags (missed sessions, pace drift, back-to-back hard days)
- Use runner context (age, HR zones, weekly goal) when available

**What the coach refuses:**
- Prescribing new plans or rewriting existing ones
- Medical advice (redirects to doctor/physio)
- Nutrition prescriptions
- Inventing stats not in the context

See `decisions.md #12` for the rationale.

**Done when:**
- Coach responds within 3 seconds on a warm cache
- Personality tone is audibly different across the three presets
- Usage limit rejects at 11th message with a clear "come back tomorrow" message
- Context includes the user's plan and last 20 runs

---

## Funding transparency

**Phase:** 3 (shipped) | **Platform:** Web

**Why:** The app uses a free-with-donations model (see `decisions.md #18`). Transparency about costs builds trust and motivates donations.

**Spec:**

The `/settings/upgrade` page shows:
- A line-item cost breakdown (Supabase, Claude API, MapTiler, domain, misc)
- A progress bar for server costs covered this month
- A progress bar for total costs (server + dev time) covered this month
- Donor count for the current month
- Donation tiers with icons and accent colors (gel, day of servers, week, month)
- A full feature list confirming everything is free

Data is read from the `monthly_funding` table (publicly readable, owner-writable).

**Done when:**
- Progress bars reflect the current month's `monthly_funding` row
- Cost breakdown matches actual infrastructure spend
- Donation buttons link to external payment

---

## Custom dialogs and toast system

**Phase:** 3 (shipped) | **Platform:** Web

**Why:** Browser `confirm()`/`alert()`/`prompt()` are unstyled, block the main thread, and break the app's visual language.

**Spec:**

- `ConfirmDialog.svelte` — styled modal for destructive-action confirmations. Focus trap, escape-to-dismiss, configurable title/message/buttons. Resolves a promise so callers can `await` it.
- `ToastContainer.svelte` + `toast.svelte.ts` — corner notification stack for transient success/error/info messages. Auto-dismiss with configurable duration.

Used across: account deletion, run deletion, club leave, event cancel, RSVP changes, and all server-error feedback.

**Done when:**
- No `window.confirm()`, `window.alert()`, or `window.prompt()` calls remain in the codebase
- Toast messages appear for all save/delete/error actions
- Dialogs are keyboard-accessible

---

## Competitor-parity features (backlog — not yet in a phase)

These are stubs. Each closes a gap against a specific competitor (see `docs/competitors.md`) and is listed with its sizing + open decisions in `docs/roadmap.md § Competitor-parity backlog`. Flesh each one out on delivery — do **not** treat the stubs below as a spec.

### Training plan runner
**Closes:** Runna, Garmin Coach.
**Stub:** plan → weeks → workouts data model (already partially sketched in `roadmap.md § Premium tier`); web plan editor; "today's workout" dashboard card; execution loop in the run screen; auto-match planned vs actual.

### External platform sync (OAuth)
**Closes:** Strava, Garmin Connect, Apple Health, Health Connect, parkrun, RunSignUp.
**Stub:** one OAuth Edge Function per provider with token refresh, webhook or polling ingest, bidirectional for Strava. Garmin Connect is gated on business approval — do not block on it.

### Segments + leaderboards
**Closes:** Strava.
**Stub:** user-authored GPS segments; PostGIS line-matching RPC invoked on run insert to produce `segment_efforts`; weekly + all-time boards per segment; KOM/CR equivalent per segment.

### Heatmap / popular-route discovery
**Closes:** Strava, Komoot.
**Stub:** anonymised GPS aggregation into raster or vector tiles served from CDN. Privacy default is opt-out (user data included unless they toggle off) — this is the decision knob worth re-litigating before shipping.

### Trail / offline navigation
**Closes:** AllTrails, Komoot.
**Stub:** turn-by-turn voice cues along a loaded route; offline map-tile packs saved to device; route-condition reports (mud, closure, overgrowth) with timestamp and upvotes.

### Social graph
**Closes:** Strava, Nike Run Club.
**Stub:** `follows` table; activity feed of people you follow; kudos (one-tap); threaded comments on runs; per-user privacy zones that blur start/end within radius.

### Gear tracking
**Closes:** Strava, Garmin.
**Stub:** shoes and bikes as `gear` rows; `run_gear` link table; auto-compute total mileage; retirement reminder at user-chosen threshold (default 500 mi for shoes).

### Photos on runs and routes
**Closes:** Strava, AllTrails.
**Stub:** multi-photo upload, attached either by timestamp match against the GPS track or explicit map pin; server-side thumbnailing via Edge Function or Supabase image-transform; cap at 10 photos per run in v1.

### Audio-coached / guided runs
**Closes:** Nike Run Club.
**Stub:** a library of `audio_workouts` (recorded MP3 coaching + structured intervals); downloaded to device on start; integrated into the run recorder's audio-cue layer. v1 can be TTS-only if voice talent budget is a blocker.

### Race calendar + results import
**Closes:** Garmin, Runna.
**Stub:** `races` table seeded from RunSignUp + parkrun imports; discovery by location; "register" deep-links to the organiser's page; auto-match recorded runs on race day to produce a result entry.

### Advanced analytics
**Closes:** Garmin, Runna.
**Stub:** VDOT computed from recent races; Banister-style training-load / fitness / freshness curves; race-time predictor for 5k/10k/half/full from VDOT; weekly and monthly drill-downs on the web dashboard. No new tables — all derived from `runs`.

### Premium billing
**Closes:** All (any monetised feature needs this).
**Stub:** Stripe Checkout flow, webhook handler Edge Function, `stripe_customer_id` + `stripe_subscription_id` on `user_profiles`; `SubscriptionTier` already exists client-side; customer portal link in Settings; middleware that gates premium features cleanly (not hardcoded checks per screen).

---

*Last updated: April 2026*
