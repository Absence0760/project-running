// Lightweight shared-storage handoff between the WatchApp main target
// (which owns the HKWorkoutSession) and the Complication widget
// extension target (which only needs to render numbers).
//
// Lives under WatchApp/ rather than Complications/ because both
// targets need to compile this type. The complication target is added
// in Xcode (see Complications/README.md) with target-membership on
// this file ticked for both WatchApp and the new ComplicationExtension.
//
// The complication can't pull data directly from `WorkoutManager`
// because each widget extension runs in its own process — they don't
// share memory with the host app. The standard fix on watchOS is an
// **App Group** + a shared `UserDefaults`: the host app writes a tiny
// snapshot whenever the workout state changes, and the complication
// reads it on every timeline request.
//
// Why a 5-field snapshot instead of just `workoutManager.something`:
//
//  - Per-tick GPS deltas would burn complication-refresh budget. We
//    only re-snapshot on stage transitions (start, pause, resume,
//    stop) and at half-km / 30 s ticks.
//  - The complication target stays decoupled from HealthKit /
//    CoreLocation — much smaller binary, simpler entitlements.
//  - The same on-disk shape can later be consumed by an iOS Lock
//    Screen widget without dragging the workout types along.

import Foundation

/// The on-wire representation of the active-run state. Five POD
/// fields, JSON-encoded into shared UserDefaults under one key.
public struct ActiveRunSnapshot: Codable {
    public let isActive: Bool
    public let elapsedSeconds: Int
    public let distanceMeters: Double
    public let paceSecPerKm: Double?
    public let lastUpdatedEpoch: Double

    public static let empty = ActiveRunSnapshot(
        isActive: false,
        elapsedSeconds: 0,
        distanceMeters: 0,
        paceSecPerKm: nil,
        lastUpdatedEpoch: 0,
    )
}

/// Bridge surface used by both the widget extension (read) and the
/// host app (write). The App Group identifier is centralised here so
/// renaming it later only touches one file.
public enum ActiveRunBridge {
    /// The App Group must be registered on **both** the host app
    /// target and the widget-extension target — see the watchOS
    /// Capabilities pane in Xcode and the README in this directory.
    public static let appGroup = "group.com.runapp.watchios.activerun"

    private static let key = "active_run_snapshot_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public static func read() -> ActiveRunSnapshot {
        guard
            let data = defaults?.data(forKey: key),
            let snap = try? JSONDecoder().decode(ActiveRunSnapshot.self, from: data)
        else {
            return .empty
        }
        return snap
    }

    /// Called by the host app's `WorkoutManager` whenever workout
    /// state changes meaningfully. After writing, the host should
    /// also call `WidgetCenter.shared.reloadTimelines(ofKind:)` so
    /// the complication picks up the new state on the next bind —
    /// without that nudge the platform may keep the previous timeline
    /// for up to ~30 minutes.
    public static func write(_ snapshot: ActiveRunSnapshot) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
