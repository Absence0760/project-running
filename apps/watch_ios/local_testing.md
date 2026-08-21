# Local testing — Apple Watch app (native Swift)

The Apple Watch app is a native Swift + SwiftUI project at `apps/watch_ios/`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Xcode 15+ | Mac App Store |
| iOS Simulator | Included with Xcode |
| watchOS Simulator | Included with Xcode |
| iOS app running | The watch syncs data via the iOS app — see [../mobile_ios/local_testing.md](../mobile_ios/local_testing.md) |

No Supabase connection is needed directly from the watch — it syncs through the iOS app via WatchConnectivity.

---

## Setup

No package manager needed — the watch app is a standalone Xcode project with no external dependencies.

---

## Running

```bash
open apps/watch_ios/WatchApp.xcodeproj
```

In Xcode:

1. Select scheme: **WatchApp**
2. Select destination: **Apple Watch Series 9 (or later) simulator** paired with your iOS simulator
3. **Cmd+R** to build and run

The watch simulator opens alongside the iOS simulator. Both must be running for WatchConnectivity to work.

---

## Pairing watch and phone simulators

The watch simulator must be paired with an iOS simulator:

1. In Simulator: **File → Open Simulator → watchOS → Apple Watch Series 9 - 45mm**
2. This automatically opens the paired iPhone simulator as well
3. If no pairing exists: **Window → Devices and Simulators → Simulators → +** to create a paired set

To verify pairing: in the watch simulator, you should see the watch face. If it shows a pairing screen, the simulators aren't properly paired.

---

## Testing features

### Run recording

1. Start a workout on the watch
2. The watch uses its own GPS (simulated in the simulator)
3. Tap Stop to end the workout
4. Tap **Sync Run** — the run data transfers to the iPhone app via WatchConnectivity

### Sync fails safely when the phone isn't reachable (issue #372)

`transferRun` only queues a run once `WCSession` is `.activated`; if it isn't, the run must **not** be marked synced.

1. Boot the watch simulator **without** its paired iPhone simulator (or before the companion app has activated its session), or reproduce the cold-launch window (short run immediately after launch).
2. Finish a run and tap **Sync Run**.
3. Expect the error `Phone unavailable — tap Sync Run to retry` (localised) and the **Sync Run** / **Discard** buttons to stay — **not** the "Sent to phone" / "Queued" success state with only "Start next run".
4. Bring the phone up, tap **Sync Run** again — it now queues and shows the queued/sent status. The finished run was preserved the whole time.

### Route navigation

End to end: pick a route on the iPhone, follow it on the wrist.

1. Both simulators running and paired, with the Flutter app (`apps/mobile_ios`) launched on the iPhone at least once so its `WCSession` is activated.
2. On the iPhone, open a saved route → **share icon → Send to Apple Watch**. The row only appears when the phone reports a paired watch with the app installed; if it's missing, launch the WatchApp on the watch simulator once and reopen the route.
3. Expect a banner: "Route sent to Apple Watch (N points)", or "…thinned from M points to N to fit" on a route over the 512-point budget. A route with fewer than two positions is refused outright with "This route has too few points to follow on Apple Watch" — nothing is queued.
4. On the watch, `PreRunView` now shows **Route**, the route name, and its total distance, with a **Clear route** button. The push is `transferUserInfo`, so it may take a few seconds and it survives the watch app being closed — background delivery is normal.
5. Start a run. Under the stat row the run screen shows **X.XX km to go**, counting down as you move along the line.

### In-run mini-map

The run screen is two pages: stats + controls on page one, the live-position mini-map on page two. Swipe left to reach it.

1. Start a run **before** the simulator has a location (Features → Location → None). The map page shows "Waiting for GPS" on an empty field — **not** a position dot, and not a dot in the middle of the map.
2. Set Features → Location → City Run (or Freeway Drive for a faster trail). The dot appears and a coral track grows behind it, the frame re-fitting as the run spreads out. A short run stays a stub near the centre rather than filling the screen with jitter — the frame floors at a 200 m ground span.
3. With a route armed (see above), the route draws as a lilac line with a filled marker at the start; a point-to-point route also carries a hollow marker at the finish, a loop only the one.
4. Swipe back to page one: the elapsed clock, the stats and Pause/Stop are unmoved. Nothing on the map page can stop the recording, and there is no map control there by design.
5. There are **no map tiles** and there is no network call — the map is a `Canvas` polyline, so it behaves identically with the phone simulator shut down. See [decisions.md § 702](../../docs/architecture/decisions.md).
6. Drive the simulated location off the route by more than 40 m (iOS simulator → **Features → Location → Custom Location**): the line turns into a red **Off route · N m** warning. Come back inside 20 m and it clears. On a physical watch the transition also fires one `WKInterfaceDevice` haptic (haptics are no-ops in the simulator).
7. Feed the watch a location it can't project (or arm a degenerate route) and the screen reads **Route position unknown** rather than silently claiming you're on route.
8. Tap **Clear route** on `PreRunView` — the next run records with no guidance block at all.

Unit coverage for the pieces, runnable without a paired pair: `xcodebuild test … -only-testing:WatchAppTests/RouteNavigatorTests -only-testing:WatchAppTests/ArmedRouteTests -only-testing:WatchAppTests/RouteGuidanceTests`. A live position marker / mini-map is still unbuilt — see `reviews/watch-ios/gap-analysis.md` item M4.

### Pause / resume

1. Tap Pause mid-run — elapsed time freezes, GPS and HealthKit session pause
2. Tap Resume — everything continues from where it paused
3. Tap Stop from either running or paused state — produces a `FinishedRun` with active-only duration

### Haptic pace alerts

1. Before starting: tap one of the pace presets (5:00/km through 7:30/km) in `PreRunView`
2. Start the run — once `distanceMetres > 200`, pace deviation of ±15 s/km triggers `WKInterfaceDevice.current().play(.notification)`
3. Debounce: at most once per 30 seconds per direction (too-fast / too-slow are tracked independently)
4. Haptics are no-ops in the watchOS simulator — verify on a physical device

### Crash checkpoint recovery

1. Start a run on a physical watch
2. Force-quit the WatchApp process (Digital Crown + drag up to close)
3. Re-launch — a "Recover unsaved run?" prompt appears with distance + duration from the most recent 15s checkpoint
4. Tap Recover to route into `PostRunView` with the recovered track, or Discard to clear the checkpoint. The point count on `PostRunView` is streamed off the NDJSON, not off the checkpoint's own figure, so it includes fixes appended since the last 15s snapshot
5. Discard leaves the NDJSON in Caches (only the checkpoint is cleared); starting the next run sweeps it. Confirm `~/Library/Caches/.../run_checkpoint/` holds at most the live run's `.ndjson` after a discard-then-start

### Track file lifetime at finish

Since [decisions.md § 467](../../docs/architecture/decisions.md) the finished run's NDJSON *is* its payload — nothing holds the track in memory — so it survives `stop()` and is deleted at `reset()`:

1. Record a short run and stop. `run_checkpoint/<id>.ndjson` must still exist, and re-launching must **not** offer "Recover unsaved run?"
2. Tap Sync Run, then Next. The `.ndjson` must be gone
3. Long-run smoke: record 30+ minutes, stop, sync. Watch memory in Instruments across the stop → Sync transition — the streaming read + streaming serialize should hold flat regardless of track length. This is the measurement the § 467 figures are *derived* rather than taken from

### GPS simulation on watch

The watchOS simulator shares the iOS simulator's location. Set a simulated location in the iOS simulator:

- **Features → Location → Custom Location** — fixed point
- **Features → Location → City Run** — simulated running movement

---

## Troubleshooting

### Watch simulator not appearing

Make sure you have a watchOS simulator installed. In Xcode: **Settings → Platforms → + → watchOS**.

### Watch simulator shows pairing screen

The simulators aren't paired. Open **Window → Devices and Simulators → Simulators** in Xcode and create a new paired iPhone + Watch combination.

### WatchConnectivity not working

Both simulators must be running simultaneously. The iPhone app must be launched and in the foreground (or at least running in background) for the initial WCSession activation. If data doesn't transfer:

1. Check that `WCSession.default.isReachable` returns `true`
2. Try `WCSession.default.transferUserInfo()` for queued (non-real-time) transfers
3. Restart both simulators

### HealthKit workout not saving

HealthKit has limited support in the watchOS simulator. Workout sessions can be started but sensor data (HR, GPS) is simulated. For full HealthKit testing, use a physical Apple Watch.

### Build errors

Make sure the deployment target in the Xcode project matches your watchOS simulator version. The minimum target should be watchOS 10.0 or later.

---

*Last updated: April 2026*
