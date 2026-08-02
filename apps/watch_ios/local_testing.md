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

The detection engine in `RouteNavigator.swift` is implemented and unit-tested (`RouteNavigatorTests.swift`): nearest-perpendicular-foot projection onto the route polyline (the web `route_geometry.ts` / `route_snap.ts` math), deviation + distance-remaining, the cross-platform 40 m / 20 m off-route hysteresis, and a `WKInterfaceDevice` haptic on the off-route rising edge. There is **no UI or route source wired to it yet** — no phone-side push of a route to the watch and no screen consuming the published values — so it isn't manually testable end-to-end; exercise it via `xcodebuild test` (`-only-testing:WatchAppTests/RouteNavigatorTests`). See `reviews/watch-ios/gap-analysis.md` items M3 (route preview) and M4 (mini-map) for the planned surface.

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
4. Tap Recover to route into `PostRunView` with the recovered track, or Discard to clear the checkpoint

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
