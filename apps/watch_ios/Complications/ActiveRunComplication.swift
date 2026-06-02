// Active-run complication for watchOS 10+. Renders the live workout
// stats (elapsed time, distance, current pace) on the runner's watch
// face. Reads from `WorkoutManager.shared` — the same singleton that
// owns the HKWorkoutSession — so the complication and the in-app run
// screen always agree on what to show.
//
// Belongs to its own Widget Extension target. See README.md in this
// directory for the one-time Xcode wiring step that adds the target,
// links HealthKit, and shares WorkoutManager via an App Group.
//
// The `accessoryCircular`, `accessoryCorner`, `accessoryRectangular`,
// and `accessoryInline` families cover Modular, Infograph, X-Large,
// and most other watch faces. Each family gets its own variant so a
// runner who picks the X-Large face sees the full stat trio while
// the Infograph corner just shows pace.

import SwiftUI
import WidgetKit

// MARK: - Provider

/// Hands the system fresh entries on a coarse cadence. We can't
/// `requestUpdate` on every GPS tick from a workout session — the
/// platform throttles complication refreshes to ~50/day per app.
/// Strategy: emit one entry per 30 seconds while a run is active,
/// and a single static entry when idle. The Run app explicitly
/// reloads the timeline on workout state transitions (start, pause,
/// resume, stop) via `WidgetCenter.shared.reloadTimelines(...)`.
struct ActiveRunProvider: TimelineProvider {
    typealias Entry = ActiveRunEntry

    func placeholder(in context: Context) -> Entry {
        ActiveRunEntry(
            date: .now,
            isActive: false,
            elapsedSeconds: 0,
            distanceMeters: 0,
            paceSecPerKm: nil,
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(snapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = snapshotEntry()
        // Inactive — single static entry; the app calls reloadTimelines
        // on the next state change so we don't have to budget refreshes.
        guard snap.isActive else {
            completion(Timeline(entries: [snap], policy: .never))
            return
        }
        // Active — 10 entries 30 s apart, then ask the system to come
        // back. Each entry advances the elapsed-time *display* without
        // the complication consuming a real refresh per tick. The app
        // reloads the timeline on stage transitions to overwrite this
        // schedule with fresher data.
        let now = Date()
        let entries = (0..<10).map { i -> ActiveRunEntry in
            let dt = TimeInterval(i * 30)
            return ActiveRunEntry(
                date: now.addingTimeInterval(dt),
                isActive: true,
                elapsedSeconds: snap.elapsedSeconds + Int(dt),
                distanceMeters: snap.distanceMeters,
                paceSecPerKm: snap.paceSecPerKm,
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func snapshotEntry() -> Entry {
        let snap = ActiveRunBridge.read()
        return ActiveRunEntry(
            date: .now,
            isActive: snap.isActive,
            elapsedSeconds: snap.elapsedSeconds,
            distanceMeters: snap.distanceMeters,
            paceSecPerKm: snap.paceSecPerKm,
        )
    }
}

// MARK: - Entry

struct ActiveRunEntry: TimelineEntry {
    let date: Date
    let isActive: Bool
    let elapsedSeconds: Int
    let distanceMeters: Double
    let paceSecPerKm: Double?
}

// MARK: - Views

/// One entry view; SwiftUI's `widgetFamily` environment value picks
/// the right rendering. Keeping all variants in one file makes it
/// trivial to keep them visually consistent (same accent colour,
/// same number formatting, same fall-back state).
struct ActiveRunEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ActiveRunEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryCorner:
            CornerView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        @unknown default:
            CircularView(entry: entry)
        }
    }
}

private struct CircularView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            VStack(spacing: 0) {
                Text("RUN")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tint)
                Text(formatPaceSecPerKm(entry.paceSecPerKm))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else {
            VStack(spacing: 0) {
                Image(systemName: "figure.run")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CornerView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            Text(formatPaceSecPerKm(entry.paceSecPerKm))
                .font(.body.weight(.semibold))
                .widgetCurvesContent()
                .widgetLabel("Pace")
        } else {
            Image(systemName: "figure.run")
                .widgetLabel("Run")
        }
    }
}

private struct InlineView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            Label(
                "\(formatDistanceKm(entry.distanceMeters)) · \(formatPaceSecPerKm(entry.paceSecPerKm))",
                systemImage: "figure.run",
            )
        } else {
            Label("Tap to start", systemImage: "figure.run")
        }
    }
}

private struct RectangularView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run").font(.caption2)
                    Text("RUNNING")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(formatElapsed(entry.elapsedSeconds))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(formatDistanceKm(entry.distanceMeters)) · \(formatPaceSecPerKm(entry.paceSecPerKm))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run").font(.caption2)
                    Text("RUN ONWARD")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text("Tap to start")
                    .font(.body.weight(.medium))
                Text("Open the Run app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget

@main
struct ActiveRunComplicationBundle: WidgetBundle {
    var body: some Widget {
        ActiveRunComplication()
    }
}

struct ActiveRunComplication: Widget {
    let kind: String = "ActiveRunComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveRunProvider()) { entry in
            ActiveRunEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Run")
        .description("Live pace, distance, and elapsed time during a run.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Pure formatters
// Mirrors apps/watch_wear/.../tiles/ActiveRunTileService.kt so the two
// platforms render identical strings. Pure functions; the test target
// can pin them without booting WidgetKit.

func formatElapsed(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}

func formatDistanceKm(_ meters: Double) -> String {
    let miles = UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    let metresPerMile = 1609.344
    let value = miles ? meters / metresPerMile : meters / 1000.0
    let digits = value >= 10.0 ? 1 : 2

    let number = NumberFormatter()
    number.locale = Locale.current
    number.numberStyle = .decimal
    number.minimumFractionDigits = digits
    number.maximumFractionDigits = digits
    number.usesGroupingSeparator = false
    let numberStr = number.string(from: NSNumber(value: value)) ?? "\(value)"

    let measurement = MeasurementFormatter()
    measurement.locale = Locale.current
    measurement.unitOptions = .providedUnit
    let unitStr = measurement.string(from: miles ? UnitLength.miles : UnitLength.kilometers)
    return "\(numberStr) \(unitStr)"
}

func formatPaceSecPerKm(_ secPerKm: Double?) -> String {
    let miles = UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    guard let p = secPerKm, p.isFinite, p > 0 else {
        return miles ? "—:—/mi" : "—:—/km"
    }
    let metresPerMile = 1609.344
    let perUnit = miles ? p * (metresPerMile / 1000.0) : p
    let total = Int(perUnit.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d%@", m, s, miles ? "/mi" : "/km")
}
