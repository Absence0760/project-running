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
4. The run data transfers to the iPhone app via WatchConnectivity

### Route navigation

1. Select a route in the iOS app and send it to the watch
2. Start a run on the watch with the route loaded
3. The watch shows a simplified map with position and remaining distance
4. Off-route deviation triggers a haptic alert at 50m

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
