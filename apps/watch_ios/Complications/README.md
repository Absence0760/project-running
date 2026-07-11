# Active-run complication — Xcode setup

The complication source ships in this directory but the **Widget Extension target** that hosts it has to be added in Xcode by hand — `xcodebuild` can't synthesise a watchOS widget extension from a source-only diff. Without the target, `ActiveRunComplication.swift` won't build and the complication won't appear in the watch face customisation UI.

This note is the one-time wiring. Once it's done, the complication ticks up in [`docs/product/roadmap.md` § Phase 2 → Glanceable tiles and complications](../../../docs/product/roadmap.md#glanceable-tiles-and-complications) and the matching cell in `docs/product/parity.md` flips from `✗` to `✓`.

## What's already done in this PR

- `ActiveRunComplication.swift` — the `Widget` definition, `TimelineProvider`, four `widgetFamily` views (Circular / Corner / Inline / Rectangular), and pure formatters that mirror the Wear OS tile.
- `WatchApp/ActiveRunBridge.swift` — the App-Group-backed handoff between the host app and the widget extension. Wired into the existing WatchApp target's `project.pbxproj` so the host build keeps compiling on `xcodebuild`.
- `WatchApp/WorkoutManager.swift` — `publishComplicationSnapshot()` is called on every state transition (`start`, `pause`, `resume`, `stop`, `reset`); writes the snapshot and nudges `WidgetCenter.shared.reloadTimelines(ofKind: "ActiveRunComplication")`.

## Manual steps in Xcode

1. **Add the widget extension target.**
   - File → New → Target… → **Watch App Complication**.
   - Product Name: `WatchAppComplication`.
   - Bundle Identifier: `com.threkir.app.watchapp.WatchAppComplication`.
   - Embed in Application: `WatchApp`.
   - Language: Swift.
   - Activate the scheme when prompted.
2. **Replace the auto-generated source.**
   - Xcode generates a stub `WatchAppComplication.swift`. Delete it (move to trash).
   - Drag `apps/watch_ios/Complications/ActiveRunComplication.swift` into the new `WatchAppComplication` group; **target membership** = `WatchAppComplication` only.
   - Drag `apps/watch_ios/WatchApp/ActiveRunBridge.swift` into the same group as a *reference* (don't copy); **target membership** = both `WatchApp` and `WatchAppComplication`.
3. **Configure App Groups.**
   - Select the `WatchApp` target → Signing & Capabilities → `+ Capability` → **App Groups** → add `group.com.threkir.app.activerun`.
   - Repeat on the `WatchAppComplication` target. The identifier must match `ActiveRunBridge.appGroup` exactly.
4. **Set deployment target.**
   - WatchAppComplication → General → Minimum Deployments → watchOS 10.0 (or whatever the host app uses; staying in lockstep avoids `@available` annotations).
5. **Add the String Catalog to the extension's bundle.**
   - Drag `apps/watch_ios/WatchApp/Localizable.xcstrings` into the `WatchAppComplication` group as a *reference* (don't copy); **target membership** = both `WatchApp` and `WatchAppComplication`.
   - This is required: the complication's `Text("RUN")` / `Text("Tap to start")` / `configurationDisplayName("Active Run")` strings localise against the catalog only if it lives in the extension's own bundle. Without it the complication renders English regardless of locale even though the host app is localised.
6. **Build for watchOS Simulator.** First build will pull `WidgetKit`. The complication shows up in the watch face customisation UI under "Active Run" (localised) with a circular preview; tap to add to a face.

After step 5, `xcodebuild -scheme WatchApp build` from CI should still pass (the new scheme `WatchAppComplication` is built as a target dependency of WatchApp).

## How it ties together at runtime

```
WorkoutManager (host app)
  ├─ start / pause / resume / stop / reset
  └─ publishComplicationSnapshot()
        ├─ ActiveRunBridge.write(snapshot)            ── App Group UserDefaults
        └─ WidgetCenter.reloadTimelines(ofKind: ...)  ── nudges the OS

ActiveRunProvider (widget extension)
  └─ getTimeline()
        └─ ActiveRunBridge.read()                     ── reads same UserDefaults
              └─ ActiveRunEntryView                   ── renders for current widgetFamily
```

The complication doesn't poll on its own — every meaningful change comes from the host app's `publishComplicationSnapshot`. Per-tick GPS deltas during a run aren't pushed; the timeline includes 10 entries 30 s apart so the elapsed-time string ticks up between explicit reloads without burning the platform's complication-refresh budget.

## Symmetry with Wear OS

The Wear OS tile (`apps/watch_wear/.../tiles/ActiveRunTileService.kt`) ships the same shape: idle ↔ active, the same three numbers, the same formatting (km / min:ss/km, `formatElapsed` mirrored verbatim). When the wording or layout changes on one platform, the other follows in the same PR — see `docs/product/parity.md`.
