# watch_ios — AI session notes

> **Deferred.** The public landing page lists Apple Watch as "Coming soon" and the team is not actively pushing it forward right now. Keep the project building and don't break the existing Swift code, but **don't start net-new watch work** (HealthKit workout sessions, complications, App Store submission prep, etc.) until the deferral is lifted. See [../../docs/product/parity.md](../../docs/product/parity.md) for the current per-feature state and [decisions.md § 1](../../docs/architecture/decisions.md) for why this is a native target.

**Native Swift / SwiftUI watchOS app.** Separate Xcode project (`WatchApp.xcodeproj`) — **not** a Flutter target. None of Melos, `flutter analyze`, or `dart pub` apply here. You edit `.swift` files and build through Xcode or `xcodebuild`.

## Why native Swift instead of Flutter

See [decisions.md § 1](../../docs/architecture/decisions.md). Flutter's watchOS story isn't production-ready, and a running watch app needs direct access to `HKWorkoutSession`, `CLLocationManager` background modes, and `WKExtendedRuntimeSession` — all of which are cleaner through native APIs than through a Flutter channel.

## Scope — read before writing code

**Web is the canonical feature surface; the watch is a wrist-only complement,
not a parallel client.** See [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)
and the live matrix at [../../docs/product/parity.md](../../docs/product/parity.md). Watch
columns in `parity.md` are `N/A` for almost everything by design — the watch
is **not** trying to mirror web's feature surface.

**Build here:**

- **Wrist-only capabilities**: `HKWorkoutSession` standalone workouts,
  `CLLocationManager` background GPS, `WKExtendedRuntimeSession` for long
  recordings, `HKLiveWorkoutBuilder` HR streams, haptic pace alerts via
  `WKInterfaceDevice`, on-watch crash recovery, watch faces / complications,
  Always-On (ambient) rendering.
- **Watch Connectivity** push to the paired iPhone (`WCSession.transferFile`)
  + DEBUG-only direct Supabase REST as a fallback (`SupabaseService.swift`).
  The phone is the durable sync target.

**Don't build here:**

- Anything that belongs in a pocket app: history browse, settings, social
  feed, club detail, plan editing, OAuth setup. The watch is a recording
  surface and a status surface — not a phone in a smaller form factor. If a
  feature can wait for the runner to be near their phone, it doesn't go on
  the watch.
- A feature that doesn't exist on web yet. Same web-first rule as the rest
  of the monorepo per §24.
- A Flutter or React-Native UI layer (see [§ 1](../../docs/architecture/decisions.md)).
  Don't reintroduce Flutter even for "shared code" reasons.
- A new direct-to-Supabase code path in `SupabaseService.swift` for any
  feature beyond completing a workout. The watch is not the place to grow
  the Supabase surface — that lives in `packages/api_client` (Dart) and
  `apps/web/src/lib/data.ts` (TS).
- New layout abstractions or DI frameworks. `@StateObject` / `@ObservedObject`
  / `@Published` is the whole UI stack.

## Source files

All under `WatchApp/` inside `WatchApp.xcodeproj`:

- `RunApp.swift` — SwiftUI app entry (`@main`)
- `ContentView.swift` — root view, run state routing (idle / recovering / recording / paused / finished)
- `WorkoutManager.swift` — `HKWorkoutSession` wrapper, workout lifecycle (start / pause / resume / stop / recovery)
- `RunPayloadStorage.swift` — where an unsynced run's payload lives: `Application Support/run_checkpoint/`, **not** `Caches`. Until the phone has the run, the NDJSON track and the JSON export built from it are the only copies of the trace, and the system reclaims `Caches` under storage pressure without asking. Owns the directory (created, and `isExcludedFromBackup` — a GPS trace has no business in an iCloud device backup), the one-time `Caches` → Application Support migration run from `WorkoutManager.init` so an upgrade over an install with an unsynced run doesn't orphan it, the stale-export sweep (keyed on `WCSession.outstandingFileTransfers`, so an export a transfer is still reading is never deleted), and `payloadIsMissing` — the decision behind telling the runner when a recorded trace is gone instead of shipping an empty track
- `CheckpointStore.swift` — 15s crash checkpoint to `UserDefaults` + incremental track NDJSON to `Application Support/run_checkpoint/<id>.ndjson` (see `RunPayloadStorage.swift`). The track file is written through one long-lived `FileHandle` (opened once per run, not re-opened per GPS batch), one self-contained JSON object per line, `synchronize()`d every 32 points and on each 15s metadata checkpoint — so a crash can only truncate the final partial line (which the loader skips) and loses at most ~15s of GPS. The checkpoint carries `averageBPM` and `hrCoverage` so a recovered run keeps its heart-rate summary and the share that average was taken over
- `WatchConnectivityManager.swift` — Watch Connectivity framework, two-way messaging with the iOS phone app. `session(_:didReceiveMessage:)` and `session(_:didReceiveUserInfo:)` both funnel into one `receive(_:)` that applies each known key independently (`preferred_unit`, and the route push — see `ArmedRoute.swift`)
- `MiniMap.swift` — the pure half of the in-run mini-map, testable with no device: `MiniMapFrame` (auto-fit + projection over a local planar metre frame, folded longitude deltas, a 200 m minimum ground span so jitter is not stretched across the screen), `MiniMapTrail` (the fixed-capacity 20 m-spaced breadcrumb that halves geometrically on overflow — a Swift port of the firmware's `trackback` + `route_simplify::simplify_to_budget`, so a switchback's apexes survive thinning), `MiniMapThinning`, and `MiniMapContent` (the display decision: nil when there is nothing honest to draw, `awaitingFix` when there is a course but no position, `routeIsLoop` for the one-marker case)
- `RunMiniMapView.swift` — the `Canvas` that draws it: trail, route, start/finish markers, position dot with a halo. Reads published recorder state and calls nothing back
- `RouteNavigator.swift` — off-route detection engine: `RouteGeometry` (Swift port of web `route_geometry.ts` `distanceAlongRoute` / `route_snap.ts` — nearest perpendicular foot per segment in a local planar frame, haversine along-distance, remaining = total − along), `OffRouteLatch` (the cross-platform 40 m trigger / 20 m re-arm hysteresis shared with the mobile run screen, Wear's banner, and the custom watch's `OffCourseAlert`), the `RouteNavigator` ObservableObject that publishes `isOffRoute` / `deviationMetres?` / `remainingMetres?` and fires the `WKInterfaceDevice` haptic once per off-route transition (injectable auxiliary seam), and `RouteGuidance` — the pure display shaping `RouteGuidanceView` renders (`status` three-way, `remainingText`, `deviationText`). Degenerate routes / non-finite fixes publish nil, never bogus zeros
- `ArmedRoute.swift` — the phone → watch route push: the `ArmedRoute` model (`route_id` / `route_name` / `route_distance_m` / two parallel `[Double]` coordinate arrays), its fail-closed `decode(_:)` of a `WCSession` payload, and the `ArmedRouteStore` UserDefaults slot it survives in between the push and the run that follows it
- `HealthKitManager.swift` — `HKWorkoutSession` + `HKLiveWorkoutBuilder` wrapper that publishes live heart rate from the watch's sensor. A session that reports `didFailWithError` is dead, so `handleSessionFailure()` nils the session, clears the reading (a frozen plausible HR is worse than none), raises `heartRateUnavailable` for the run + summary screens, and withholds `summaryAverageBPM` — the average covered only the minutes before the sensor died and must not be stamped on the row as the whole run's. Synchronous, because HealthKit calls back off-main while `stop()` reads the summary on main. The recording is untouched: losing HR never costs the run
- `SupabaseService.swift` — DEBUG-only direct Supabase REST calls from the watch (no shared Dart/JS code)
- `ActiveRunBridge.swift` — App-Group-backed `UserDefaults` write/read shared with the active-run complication target. `WorkoutManager.publishComplicationSnapshot()` writes here on every workout state transition. See `apps/watch_ios/Complications/README.md` for the one-time Xcode wiring
- `AppTheme.swift` — `Color` palette + reusable text styles for the watch UI (single source of truth so the SwiftUI subviews — `PreRunView`, `RunningView`, `PausedView`, `RecoveryView`, `PostRunView` — share dimensions and colours rather than each redefining their own)

## Localization

The watch UI is localised to seven locales:
**en, de, fr, es, ja, pt-BR, pt-PT**. There is **no in-app language picker** — the
watch follows the device / paired-iPhone locale (`Locale.current`), as Apple
intends. European Portuguese landed 2026-08-27 alongside the server-side mail
catalogues (decisions § 761); web, Flutter and Wear OS had shipped it the day
before (§ 755), and until this it was the one surface where a Lisbon wrist fell
back to Brazilian.

- **String Catalog**: `WatchApp/Localizable.xcstrings` (modern `.xcstrings`, source
  string is the key). SwiftUI `Text("Ready to Run")` is a `LocalizedStringKey` and
  localises automatically against the catalog with no code change. Non-`Text` surfaces
  (the sync-status strings in `ContentView.syncedStatusText`) are wrapped in
  `String(localized:)` so they pull from the catalog too. Translations match the
  dialect / wording already used in `apps/mobile_android/lib/l10n/app_*.arb` and
  `apps/watch_wear/.../res/values-*/strings.xml`. "Threkir" stays untranslated.
- **Number / unit formatting**: `WatchApp/RunFormat.swift` is the single source of
  truth — `RunFormat.distance(...)` and `RunFormat.pace(...)`. Distance uses
  `NumberFormatter` (locale decimal separator: `5,12 km` on a German watch) +
  `MeasurementFormatter` (localised unit word) and honours the km/mi preference
  (`UserDefaults preferred_unit`, same key the pre-run pace presets read). Pace is
  `m:ss` + a `/km`|`/mi` suffix (the m:ss part is a stopwatch reading, not a decimal,
  so it isn't locale-separated — matching Wear OS / Flutter). `formattedElapsed`
  stays `%d:%02d:%02d` for the same reason. The complication
  (`Complications/ActiveRunComplication.swift`) carries its own copy of the same
  formatting logic because it builds in a **separate** Widget Extension target that
  can't link `RunFormat.swift`; keep the two in lockstep.
- **`CFBundleLocalizations`** lists every shipped locale in `WatchApp/Info.plist`;
  the same set is in the project's `knownRegions`
  (`WatchApp.xcodeproj/project.pbxproj`). Both matter: a translated string the
  bundle does not declare is never loaded, so the app shows English and nothing
  fails. `SWIFT_EMIT_LOC_STRINGS = YES` is already set so Xcode keeps the catalog
  populated from source on build.
- **Parity check (no Xcode needed)**: `scripts/check_xcstrings_parity.sh` **derives**
  the shipped locale set from the catalog — it does not restate it — then fails if
  any string lacks a non-empty translation for one of them (ja is exempt from the
  plural `one` category by design), or if either declaration site above disagrees
  with that set. Pure `python3` — runs on Linux / CI without a Mac. It is wired into
  the `watch-ios-locale-parity` job in `.github/workflows/ci.yml`; before 2026-08-27
  it ran nowhere but a developer's own shell. Run it after editing the catalog.
- **Source-vs-catalog check (also no Xcode)**: `node scripts/check_watch_ios_source.mjs`
  reads the other direction — every literal handed to a localizing API must have a
  catalog entry, and every catalog entry must still be referenced. **A `Text("…")`
  with no entry is not an error anywhere**: `LocalizedStringKey` falls back to the
  key, so every locale renders the English literal, nothing throws, and both
  `xcodebuild` and the guard above pass. It cost two literals in the complication
  ([decisions § 884](../../docs/architecture/decisions.md)). The same guard holds
  `Info.plist` / `WatchApp.entitlements` against the calls that need them, the
  complication's duplicated formatters against their `RunFormat.swift` copies, the
  run hand-off metadata envelope against the phone's end of it, and the route-push
  envelope across all three of its ends (`apple_watch_route_bridge.dart` →
  `WatchIngestBridge.routeUserInfo` → `ArmedRoute.decode`) — see the file's
  own header. **A literal that only stitches already-formatted values together is
  not a translatable string**: pass it as a `String` (or `Text(verbatim:)`) so it is
  not a key at all, the way `statLine(_:)` does.
- **Complication caveat**: the complication's `.xcstrings` localisation only takes
  effect once `Localizable.xcstrings` is added to the Widget Extension target's bundle
  — see step 5 in `Complications/README.md`. Until that target exists in Xcode the
  complication source isn't built at all.
- **Remaining verification**: the localisation work was authored on a Linux workstation
  with no Xcode. It is **compiled and tested** as of 2026-08-18 — `xcodebuild test
  -project apps/watch_ios/WatchApp.xcodeproj -scheme WatchApp -destination
  'platform=watchOS Simulator,id=<sim>'` runs the whole `WatchAppTests` suite green on
  a Mac (Xcode 26.4, watchOS 26.4). Target the simulator by **id**: the `Apple Watch
  Series 9` this file used to name no longer exists, and `Series 11 (46mm)` is
  ambiguous when two are paired. What is still outstanding is the visual spot-check
  of each locale in the simulator, and — since 2026-09-02 — the Swift and
  entitlement edits of [decisions § 884 – § 888](../../docs/architecture/decisions.md),
  which no compiler, signer or simulator has seen. Both are filed in
  `docs/product/followups.md`.
- **The permission prompts are not localized.** `Info.plist`'s four
  `NS*UsageDescription` strings are English-only — there is no `InfoPlist.xcstrings`
  in this app or the phone's — so the HealthKit and location consent dialogs read
  English on a wrist whose other 56 strings do not. Filed, with what closing it
  costs, in `docs/product/followups.md`.

## What's real vs stubbed

More than a stub — there's a multi-file architecture with `@StateObject` / `@ObservedObject` / `@Published` state flow, a working Supabase client, and cross-device sync via Watch Connectivity. Specific "real" features: workout session start/stop, GPS tracking with background location updates, pause/resume, crash checkpoint recovery, haptic pace alerts, phone-to-watch message passing, and route following end to end — a phone-pushed route (`WCSession.transferUserInfo`), the pre-run route card, the off-route / distance-remaining readouts during the run, and a live-position mini-map on the run screen's second page.

Per [`roadmap.md` § Phase 2](../../docs/product/roadmap.md), the current checkbox status is:

- [x] Standalone workout session (no phone required) — background GPS via `allowsBackgroundLocationUpdates = true`; crash checkpoint recovery in `CheckpointStore.swift` writes a 15s snapshot to UserDefaults + streams the track to NDJSON in the durable payload directory; on next launch the user is offered "Recover unsaved run?" (recovery restores the avg HR from the checkpoint). The run keeps **one UUID end-to-end** — the id minted at `start()` is the one the checkpoint, the on-disk track file, and the finished run row all share (a finished run no longer mints a second UUID). `WorkoutManager.track` is a **bounded rolling window** (`maxInMemoryTrackPoints`); the full track lives on disk and is never materialised, so an all-day ultra holds flat memory instead of a 360k-point array. `trackPointCount` carries the authoritative count. The read side streams to match the save (`CheckpointStore.forEachTrackPoint`, 64 KiB at a time, one point yielded at a time), and `FinishedRun` carries the track's **file URL + point count** rather than a `[TrackPoint]` so no consumer can reintroduce the peak — `writeTrackJSON` streams NDJSON → wire point → a staged file it renames, and the DEBUG direct upload maps that file. The NDJSON therefore outlives the UserDefaults checkpoint: `stop()` drops only the recovery prompt, `reset()` deletes the finished run's file, and `start()` sweeps any stranded by a discarded recovery. See [decisions.md § 467](../../docs/architecture/decisions.md)
- [x] Heart rate via HealthKit sensor — a failed workout session degrades honestly rather than freezing on the last reading: "Heart rate unavailable" during the run, "Heart rate unavailable — run saved without it" on the summary, and no `avg_bpm` on the synced row. The mean is also graded against COVERAGE — the share of the run's active time the sensor was actually delivering, measured on the recorder's own tick — and suppressed below 0.5, because a mean over less of the run than not is not the run's average. The figure travels as `hr_coverage`, so "present, with no `avg_bpm`" is a run whose sensor was mostly quiet rather than one recorded without a strap (decisions § 1156 / § 1207)
- [x] Haptic pace alerts — target pace set via preset list in `PreRunView`; `WKInterfaceDevice.current().play(.notification)` fires when pace leaves the ±15 s/km band, debounced to once per 30s per direction
- [ ] Syncs run data via Watch Connectivity framework — watch side wired (`WCSession.transferFile`); phone-side receiver + sign-in UI live; checkbox remains unticked pending end-to-end verification on paired physical devices
- [x] Route preview on watch face before starting — `PreRunView` shows the armed route's name + total distance with a **Clear route** button. The route arrives from the phone (see "Route push" below); there is no on-watch picker by design (the phone owns route selection)
- [x] Live position on mini-map during run — `RunMiniMapView.swift` is the second page of a paged `RunningView` (page one keeps the stats and the Pause/Stop buttons exactly where they were). Drawn in SwiftUI `Canvas` with **no basemap**: MapKit was considered and refused, because a standalone workout out of signal renders MapKit as a grey grid a runner cannot tell apart from a wedged app. The track-so-far is `MiniMapTrail`, the map's own fixed-capacity distance-decimated breadcrumb — `WorkoutManager.track` is a 600-fix rolling window and no longer holds the start of a long run. No usable fix renders "Waiting for GPS", never a dot. **Build-verified + host-tested, not device-verified** — see [decisions.md § 702](../../docs/architecture/decisions.md)
- [x] Off-route haptic + "recalculating" indicator — `RouteGuidanceView` in `ContentView.swift` renders the `RouteNavigator` outputs during a run: a red "Off route · N m" line on the latched off-route state, a dim "Route position unknown" when the geometry can't project the current fix (distinct from on-route by design), and "X.XX km to go" whenever a projection exists. Fed by `WorkoutManager.routeNavigator`, built at `start()` from `ArmedRouteStore.load()`. **Not sim/device-verified** — no Mac in the loop yet
- [ ] watchOS complication: pace + distance — Swift source (provider + four `widgetFamily` views) ships in `apps/watch_ios/Complications/`. `WorkoutManager.publishComplicationSnapshot` writes the active-run state to an App-Group `UserDefaults` on every transition (start / pause / resume / stop / reset) and nudges `WidgetCenter.shared.reloadTimelines`. Checkbox stays `[ ]` until the Widget Extension target is added in Xcode — see `apps/watch_ios/Complications/README.md`

`WorkoutManager.State` now has five cases: `idle`, `recovering`, `recording`, `paused`, `finished`.

`LocationManager.swift` has been deleted — it was dead code; `WorkoutManager` owns the embedded `CLLocationManager`.

## Sync architecture: phone-as-proxy

In Release builds the watch does **not** talk to Supabase directly. On run finish, `WorkoutManager.writeTrackJSON()` serialises the track to a file in the durable payload directory (`RunPayloadStorage.directory`) and `WatchConnectivityManager.transferRun(fileURL:metadata:)` hands it off via `WCSession.transferFile(_:metadata:)`. WCSession reads that file off disk for as long as the transfer is outstanding — days, with the phone switched off — and by then `reset()` has deleted the NDJSON it was built from, so it cannot live anywhere the system may reclaim. `session(_:didFinish:)` deletes it on a successful delivery; `start()` sweeps any stranded by a crash, excluding whatever is still in `outstandingFileTransfers`. The paired iPhone is responsible for gzipping, uploading to the `runs` Storage bucket, and inserting the row via the shared `packages/api_client`. WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay), queues across app launches, and retries on its own — so the watch needs no Supabase credentials, no anon key, and no internet connectivity. Because that outbox outlives the app **and** the watch reboot, `queuedCount` and `transferState` are re-seeded from `WCSession.outstandingFileTransfers` in `activationDidCompleteWith` and on each hand-off, never carried as a private tally: a count that starts at zero every launch showed nothing on the pre-run screen while the platform was still holding a run, and that line is the only place the watch says a run is still waiting (decisions § 1209).

**Fail-closed hand-off (issue #372):** `transferRun` **returns `Bool`** — `true` only once the file is actually in WCSession's outbox, `false` when the session isn't `.activated` yet (the activation guard, decided by the pure `WatchConnectivityManager.canTransfer(activationState:)`) and nothing was queued. `WCSession.activate()` is async at launch, so a short run right after a cold launch can reach the sync tap before the session is ready. `ContentView.syncRun()` sets `thisRunSynced = true` **only** when `transferRun` returns `true`; a `false` leaves the run in the `finished` state showing a retry-able error (`Phone unavailable — tap Sync Run to retry`, localised in `Localizable.xcstrings`) so `PostRunView` keeps `finishedRun` and re-offers **Sync Run**. Never mark a run synced when it wasn't queued.

The phone-side receiver is **built**: `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner/` implements `session(_:didReceive file:)` and calls the `run_app/watch_ingest` Flutter method channel; `main.dart` `WatchIngest.attach(api)` saves the run via `api_client`. `mobile_ios` now has email/password sign-in (Apple Sign-In scaffolded behind a compile flag). Payloads received before the user signs in are persisted by `WatchIngestQueue` (`apps/mobile_ios/lib/watch_ingest_queue.dart`) and replayed on the next `AuthChangeEvent.signedIn` — see [`docs/architecture/decisions.md § 22`](../../docs/architecture/decisions.md).

### Route push: phone → watch

The opposite direction of the run hand-off. On iOS, the route-detail share menu carries **Send to Apple Watch** (`_sendRouteToAppleWatch` in `route_detail_screen.dart`, shown only when `AppleWatchRouteBridge.isAvailable()` reports a paired watch with the app installed). The Dart bridge shapes the route, the phone-side `WatchIngestBridge.swift` queues it, and this app decodes it into an `ArmedRoute`.

- **Transport: `WCSession.transferUserInfo(_:)`**, not `sendMessage`. A runner picks a route on the phone while the watch is on a charger in another room — `sendMessage` needs a reachable counterpart with the watch app running and fails in exactly the common case. User-info transfers queue across app launches and watch reboots, deliver in order, and wake the watch app in the background to hand them over. `updateApplicationContext` would also survive, but it is one clobber-prone dictionary slot shared with the (already-anticipated) `preferred_unit` push.
- **Point budget: 512 positions**, the same number in all three languages — `kMaxAppleWatchRoutePoints` (Dart), `WatchIngestBridge.maxRoutePoints` (phone), `ArmedRoute.maxPoints` (watch). ~8 KB of coordinate data, far inside the transport ceiling, and a per-fix `RouteGeometry.project` (linear in the point count, run at ~1 Hz) that costs nothing on a watch CPU. Deliberately looser than the custom watch's 256-point `CRS1` cap, which is a flash-capacity limit this device doesn't have.
- **Fail closed at every hop.** A denser route is thinned by priority Douglas–Peucker (`simplifyToBudget`), never cut at the cap — a polyline that stopped at position 512 would make `RouteNavigator` call the runner off route against geometry the route does not have, and announce the finish early. Under two positions, the phone refuses with a reason the runner sees. `WatchIngestBridge` re-checks the shape before queueing (a malformed payload in the durable queue is retried forever against a watch that rejects it every time), and `ArmedRoute.decode` drops the whole payload on any mismatched / over-cap / non-finite / out-of-range value rather than loading part of it.
- **Privacy**: the push reads `_displayWaypoints` — the privacy-zone-clipped polyline the map and the GPX exporter use — so a non-owner sending a public route to their own watch can't carry the owner's unclipped trace out over Watch Connectivity (decisions §33).
- The armed route is written to `UserDefaults` on arrival (deliveries land while the app is backgrounded), read back at `WorkoutManager.start()`, and cleared either by the next push or by **Clear route** on `PreRunView` — the phone is the only writer, so without that button a route the runner no longer wants can only be replaced from the phone.

**Companion status.** `WatchApp/Info.plist` declares `WKWatchOnly` — "no iOS companion" — which is true of the Xcode project (a standalone `WatchApp.xcodeproj` that `Runner.xcodeproj` does not reference) and false of the app (whose Release sync is `WCSession` to `com.threkir.app`, and whose bundle id `com.threkir.app.watchapp` is the companion naming rule). Do NOT flip the key on its own: it would declare a companion nothing bundles, and `test-watch-ios` installs on an unpaired watch simulator. The build integration comes first; [decisions § 1256](../../docs/architecture/decisions.md) lists the five steps a Mac must run in order. Also note the target sets `GENERATE_INFOPLIST_FILE = NO`, so **every `INFOPLIST_KEY_*` build setting here is inert** — put Info.plist keys in the Info.plist; claim (10) of the source guard enforces it.

`SupabaseService.swift` still exists but is wrapped in `#if DEBUG` — it gives watch-sim-alone developers a direct upload path via the "DEBUG: Sync Direct" button, signing in with seed creds against `http://127.0.0.1:54321`. Release builds compile that file out entirely: the watch binary ships without any Supabase client, anon key, or credential-handling code. Rationale: [decisions.md § 14](../../docs/architecture/decisions.md).

Metadata dict sent with each run file: `{id, started_at, duration_s, distance_m, source, activity_type, last_modified_at, avg_bpm?, hr_coverage?}` — the phone supplies `user_id` from its own authenticated session when inserting the row. `activity_type` is hardcoded to `"run"` (the watch only records runs) so the row passes the `runs_metadata_activity_type_check` CHECK constraint without depending on the phone's defaulting. `last_modified_at` is a UTC ISO-8601 stamp (set at sync time) that mobile's delta-fetch (`runs_screen._fetchRemote`) filters on — without it an Apple-Watch run never resurfaces on another device after the first full pull, matching Wear's `WatchRunMetadata.buildRunMetadata`. **Caveat:** for the WCSession phone-proxy path a key only reaches the row once the phone-side ingest (`apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` forwarding, then `runFromWatchPayload` in `watch_ingest_queue.dart`) also carries it through — those files are outside this app. `hr_coverage` now travels both hops: the bridge lifts it (claim (6) of `scripts/check_watch_ios_source.mjs` requires both ends of the envelope to agree) and the Dart decoder forwards it onto the row (decisions § 1207 + § 1254). There is ONE Dart decoder now — `main.dart`'s `WatchIngest` used to carry a second copy for the signed-in branch, which is where the key was actually being dropped, and which also never learned that this bridge sends `track` as JSON text. The DEBUG-only direct path in `SupabaseService.swift` writes the row itself and so carries every field immediately — including the two heart-rate ones, which its `[String: String]` metadata type used to make UNSENDABLE rather than merely unsent (decisions § 1255). Claim (9) of the source guard holds the two write paths against each other so the field lists cannot drift again; `user_id` and `track_url` are registered in `DIRECT_ONLY_FIELDS` as the two the phone supplies on the WCSession path. `steps` and `laps` (present in the Wear payload) stay omitted — this watch captures neither, and Wear likewise omits them when absent. The file contents are a raw JSON array of `{lat, lng, ele, ts}` points; the phone compresses before upload.

## Building and testing

See [local_testing.md](local_testing.md). You need:

- Xcode with watchOS simulators installed
- A paired iOS simulator + Apple Watch simulator, or a physical paired pair

From CI, the build is driven by `xcodebuild`:

```bash
xcodebuild -project apps/watch_ios/WatchApp.xcodeproj \
  -scheme WatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9' \
  build
```

This is exactly what `.github/workflows/ci.yml`'s `build-watch-swift` job runs on a macOS runner.

**Unit tests: `WatchAppTests` XCTest target.** `apps/watch_ios/WatchAppTests/`
holds the first automated coverage for the watch app — a host-bundle unit-test
target wired into `WatchApp.xcodeproj` (product type
`com.apple.product-type.bundle.unit-test`, `TEST_HOST` = the WatchApp binary,
depends on the WatchApp target). The app's Debug config already sets
`ENABLE_TESTABILITY = YES`, so `@testable import WatchApp` works. The test files
exercise the pure / serialisation surfaces (the Android-bound pieces —
`HKWorkoutSession`, `CLLocationManager`, timers, WidgetKit — are not driven):

- `RunFormatTests.swift` — `RunFormat.distance` / `.pace` km↔mi conversion, m:ss decomposition, `--:--` placeholder, fraction-digit handling.
- `ComplicationFormatterTests.swift` — the complication's own copy of the formatters (`formatElapsed` / `formatDistanceKm` / `formatPaceSecPerKm`), kept in lockstep with `RunFormat`; mirrors Wear's `ActiveRunTileFormattersTest.kt`.
- `ActiveRunBridgeTests.swift` — `ActiveRunSnapshot` Codable round-trip, App-Group write/read fallback to `.empty`, and the 24 h staleness ceiling the complication provider applies to a crash-orphaned snapshot.
- `RunCheckpointCodableTests.swift` — the hand-written `RunCheckpoint.init(from:)` back/forward-compat decode (absent `version`→1, absent `averageBPM`→nil, `{}`→safe defaults, unknown future keys ignored); mirrors Wear's `CheckpointSerializationTest.kt`.
- `CheckpointStoreTrackTests.swift` — NDJSON append/load round-trip, the crash-truncated-final-line skip, garbage-line tolerance, `clear()`, and metadata-checkpoint UserDefaults round-trip; mirrors Wear's `TrackWriterTest.kt`.
- `WatchRunPayloadFixtureTests.swift` — the cross-platform `fixtures/watch_run_payload.json` contract (the Swift slice that closes the loop alongside the Dart / Kotlin / TS fixture tests), plus that the watch's `TrackPoint` encodes the canonical `lat/lng/ele/ts` field names with no stray keys.
- `WorkoutManagerTrackJSONTests.swift` — `writeTrackJSON()` file naming + round-trip + empty-track validity + the no-finished-run guard, and `TrackPoint` codec edge cases (nil ts/ele, negative coords).
- `WorkoutManagerRecoveryTests.swift` — `recoverRun()` rebuilds a `FinishedRun` keeping the same id end-to-end + restoring avg HR, and `formattedElapsed` mm:ss↔h:mm:ss crossover (the elapsed analogue of Wear's `ElapsedMathTest.kt`).
- `TransferStateTests.swift` — `WatchConnectivityManager.TransferState` Equatable (two `.failed` with different messages must differ) + associated-value extraction, plus the pure `canTransfer(activationState:)` activation guard that fixes issue #372 (true only when `.activated`; false when `.notActivated` / `.inactive`, so `transferRun` returns false and `syncRun` never marks an un-queued run synced).
- `RouteNavigatorTests.swift` — the off-route detection engine: `RouteGeometry.project` mirrors the web `distanceAlongRoute` cases (nil on <2 points / non-finite input, vertex + mid-segment along-distance, perpendicular offset maps to the right along-distance, start/end clamps, nearest-of-two-segments, duplicate-vertex tolerance), the `OffRouteLatch` 40 m / 20 m hysteresis cases (fires once, stays latched, strict boundaries, no flap — mirrors `course.rs`'s `OffCourseAlert` tests), and the `RouteNavigator` wiring (haptic exactly once per transition via the injected seam, nil-neutral degenerate route, a non-finite fix keeps the latch).
- `ArmedRouteTests.swift` — the phone → watch route push's decode + store: what a well-formed payload yields, the two-points and at-the-cap boundaries, and every fail-closed rejection (absent/empty id, absent name, a distance that is NaN / infinite / negative / not a number, mismatched coordinate array lengths, fewer than two points, one point over the cap — refused rather than truncated — and a non-finite or out-of-range coordinate). Plus the `ArmedRouteStore` round-trip, its nil-on-garbage read, replace-on-save, and that a decoded route actually drives `RouteNavigator`.
- `RouteGuidanceTests.swift` — the pure shaping behind `RouteGuidanceView`: the `status` three-way (a missing deviation is `.unknown`, never `.onRoute`; a latched off-route outranks a missing deviation so one bad fix can't downgrade a live alert), `remainingText` in the preferred unit with nil on no-projection and a rendered zero at the finish, and `deviationText` staying metric in mi-mode and rounding to whole metres.
- `WorkoutManagerPaceTests.swift` — the rolling pace window across a pause: `resume()` seals it (`sealPaceWindow`), so the ~200 m look-back cannot be timed against a span containing the stop. Drives the real `pause()` / `resume()` (safe: without a `CheckpointStore` the frozen-checkpoint write is a no-op and the HealthKit session is nil). Pinned against the pre-fix reading of 4594 s/km after a 12-minute aid stop where the runner is holding 300 s/km, plus that the pace is withheld until the resumed window refills rather than borrowing the pre-pause tail.
- `HealthKitFailureTests.swift` — the dead-`HKWorkoutSession` contract: `handleSessionFailure()` drops the frozen live reading, raises `heartRateUnavailable`, and withholds `summaryAverageBPM` **synchronously** (HealthKit calls back on its own queue while `stop()` reads the summary on main, so a guard that only takes effect after a main-queue hop lands after the run is stamped). Plus the layering half — the GPS stream, the distance and the track keep going across the failure, and a healthy session's average is still stamped.
- `RunPayloadStorageTests.swift` — the durable payload directory (not under `Caches`, excluded from backup, and where `CheckpointStore.trackFile` resolves), the `Caches` migration (moves everything, never overwrites a durable payload with a cached one, never deletes a payload a failed move left behind, refuses a directory onto itself, idempotent), the export sweep's keep-set (a still-outstanding transfer and a fresh export both survive; an aged unreferenced one goes; an `.ndjson` track is never touched), and `payloadIsMissing`.
- `WorkoutManagerDistanceTests.swift` — the per-fix distance accumulation: the pure `WorkoutManager.distanceDelta(from:to:)` `2..<100 m` filter band (in-band adds, jitter below 2 m and reacquisition jumps over 100 m contribute zero), normal consecutive-fix accumulation, and the pause -> wander -> resume regression (#371) — `resume()` clears `lastLocationForDistance` so the first post-resume fix establishes a fresh reference and an aid-station wander while paused is not banked as post-resume distance. Drives `didUpdateLocations` directly (safe: it touches no live `CLLocationManager` / HealthKit / timers).

Run from a Mac: `xcodebuild test -project apps/watch_ios/WatchApp.xcodeproj -scheme WatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 9'`. **These tests were authored on a Linux workstation with no Xcode — correct-by-construction against the source APIs but NOT yet compiled or run.** A Mac/Xcode `xcodebuild test` pass is the outstanding verification step (same situation as the localisation work above).

Still uncovered (Android-bound, not unit-testable without a simulator/host harness): `WorkoutManager`'s `start()` (it spins timers + `CLLocationManager` + `HKWorkoutSession`; `pause()` / `resume()` ARE driven, see `WorkoutManagerPaceTests`), `HealthKitManager` HR averaging (driven by `HKLiveWorkoutBuilder` delegate callbacks — the failure path is covered via `handleSessionFailure()`, which is all `didFailWithError` does besides logging the error), `WatchConnectivityManager`'s real `WCSession.transferFile`, and `SupabaseService.swift`'s network path. Follow Wear's extract-then-test pattern if those grow non-trivial branches.

## Conventions for Swift code

- SwiftUI-first. Don't mix in UIKit-on-watchOS / WatchKit ObjC unless a framework genuinely requires it.
- State flow: `@StateObject` in the view that owns the lifecycle, `@ObservedObject` in views that consume it, `@Published` on the manager properties. No Combine `Subject`s in the public API if a `@Published` will do.
- File-per-concern, not file-per-view. `WorkoutManager`, `HealthKitManager`, `CheckpointStore`, etc. are each their own file; views can group.
- Swift conventions follow [Apple's API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) — same case style, same parameter labelling.

## Before reporting a task done

- Build the Xcode project (`xcodebuild` command above) and confirm zero errors — warnings are acceptable if they match the baseline.
- Tick the matching Phase 2 checkbox in `roadmap.md`.
- If you touched `SupabaseService.swift`, re-check every other Supabase call site — the watch doesn't have a compiler-enforced link between the generated row types and its own models.
- If you added a new native capability (HealthKit, haptics, background runtime), confirm the entitlements and `Info.plist` keys are set on the watch target, not just the phone.
