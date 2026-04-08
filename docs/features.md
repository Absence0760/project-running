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

User taps Start on the home screen. The app requests location permission if not already granted (always-on for background tracking). Recording begins immediately — no countdown.

During recording, the screen shows:
- Elapsed time (large, centre)
- Distance covered (km or miles, based on user preference)
- Current pace (per km or mile, rolling 30-second average)
- Heart rate (if a connected watch is providing data)
- A live map with the user's position and trace

Auto-pause activates when speed drops below 1 km/h for more than 10 seconds (walking to cross a road). Haptic feedback on pause/resume. Auto-pause can be toggled off in settings.

Background location tracking keeps recording if the user locks their phone or switches apps.

On Stop: user sees a summary (distance, time, pace, map of the run). They can discard or save. Save writes to local SQLite and queues a sync to Supabase.

**Done when:**
- Recording continues accurately through a 10km run with the screen locked
- Auto-pause triggers reliably at traffic lights
- GPS trace is accurate to within 5 metres on open streets
- Run appears in history immediately after saving

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

*Last updated: April 2026*
