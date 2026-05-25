import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var syncError: String?
    @State private var thisRunSynced = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch workoutManager.state {
                case .idle:
                    PreRunView(
                        workoutManager: workoutManager,
                        queuedCount: connectivity.queuedCount
                    )
                case .recovering:
                    RecoveryView(workoutManager: workoutManager, onRecover: recoverRun, onDiscard: discardRecovery)
                case .recording:
                    RunningView(
                        workoutManager: workoutManager,
                        healthKit: workoutManager.healthKit
                    )
                case .paused:
                    PausedView(workoutManager: workoutManager)
                case .finished:
                    PostRunView(
                        workoutManager: workoutManager,
                        transferState: connectivity.transferState,
                        thisRunSynced: thisRunSynced,
                        syncError: syncError,
                        onSync: syncRun,
                        onSyncDirect: syncRunDirect,
                        onDiscard: startNextRun
                    )
                }
            }
        }
        .task {
            await workoutManager.healthKit.requestAuthorization()
            workoutManager.checkForPendingRecovery()
        }
    }

    private func syncRun() {
        guard let run = workoutManager.finishedRun else { return }
        syncError = nil
        do {
            let fileURL = try workoutManager.writeTrackJSON()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var metadata: [String: Any] = [
                "id": run.id,
                "started_at": formatter.string(from: run.startedAt),
                "duration_s": run.durationSeconds,
                "distance_m": run.distanceMetres,
                "source": "watch",
                // Apr 2026 cross-client audit caught Apple-Watch runs
                // arriving on the phone with no `activity_type` set,
                // even though `WatchIngestBridge.swift` filters for it.
                // Hardcode "run" to match Wear OS until the watch app
                // grows an activity picker.
                "activity_type": "run"
            ]
            if let bpm = run.averageBPM { metadata["avg_bpm"] = bpm }
            connectivity.transferRun(fileURL: fileURL, metadata: metadata)
            thisRunSynced = true
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Watch-sim-alone dev path: no phone, upload straight to local Supabase.
    /// No-op in Release builds — the corresponding button is also hidden.
    private func syncRunDirect() {
        #if DEBUG
        guard let run = workoutManager.finishedRun else { return }
        syncError = nil
        Task {
            do {
                try await syncRunDirectDebug(run)
                await MainActor.run {
                    thisRunSynced = true
                    connectivity.transferState = .completed
                }
            } catch {
                await MainActor.run {
                    syncError = error.localizedDescription
                }
            }
        }
        #endif
    }

    private func recoverRun() {
        guard let run = workoutManager.recoverRun() else {
            discardRecovery()
            return
        }
        workoutManager.clearRecovery()
        workoutManager.finishedRun = run
        workoutManager.distanceMetres = run.distanceMetres
        workoutManager.elapsedSeconds = TimeInterval(run.durationSeconds)
        workoutManager.state = .finished
    }

    private func discardRecovery() {
        workoutManager.clearRecovery()
        workoutManager.state = .idle
    }

    /// Return to the idle screen. Leaves any WCSession-queued transfers
    /// intact — they continue delivering in the background when the phone
    /// is next reachable.
    private func startNextRun() {
        syncError = nil
        thisRunSynced = false
        workoutManager.reset()
    }
}

// MARK: - Pre-Run View

/// Round-number pace presets surfaced in the pre-run picker.
///
/// The DB / `WorkoutManager` store the target pace in seconds-per-km
/// (the schema is unit-agnostic). The watch presets surface in the
/// user's preferred unit so an mi-mode runner picks from 8:00/mi /
/// 8:30/mi etc. instead of doing the conversion in their head.
///
/// Reads `UserDefaults.standard.string(forKey: "preferred_unit")`,
/// defaulting to km. The companion `WatchConnectivityManager`
/// receive-message handler writes that key when the phone pushes a
/// `preferred_unit` change (see `didReceiveMessage`). Phone-side
/// push isn't yet wired — this watch-side scaffolding lets the
/// signal flow the moment that lands. Until then mi-mode users
/// who paired their watch fresh see km presets; they can manually
/// poke the UserDefaults via `defaults write` in a debugger.
private func pacePresets() -> [(label: String, secondsPerKm: Double)] {
    let isMiles = UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    if isMiles {
        // 7:30 to 12:30 per mile in 30-second steps — covers easy
        // through 5k-fast for typical recreational runners. Stored
        // value remains sec/km via the metresPerMile conversion so
        // the recording stack's pace-alert math stays unit-agnostic.
        let metresPerMile = 1609.344
        let secsPerMile: [Int] = [450, 480, 510, 540, 570, 600, 630, 660, 690, 720, 750]
        return secsPerMile.map { secMi in
            let m = secMi / 60
            let s = secMi % 60
            let label = String(format: "%d:%02d/mi", m, s)
            // Convert sec/mi to sec/km: time per km = time per mi × (km / mi)
            let secPerKm = Double(secMi) * (1000.0 / metresPerMile)
            return (label: label, secondsPerKm: secPerKm)
        }
    }
    return [
        ("5:00/km", 300),
        ("5:30/km", 330),
        ("6:00/km", 360),
        ("6:30/km", 390),
        ("7:00/km", 420),
        ("7:30/km", 450),
    ]
}

struct PreRunView: View {
    @ObservedObject var workoutManager: WorkoutManager
    let queuedCount: Int
    @State private var selectedPaceIndex: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Ready to Run")
                    .font(.headline)

                if queuedCount > 0 {
                    Text("\(queuedCount) run\(queuedCount == 1 ? "" : "s") queued to sync")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target pace")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Recompute presets each render so a unit-pref flip
                    // mid-session (rare — phone push is the only writer)
                    // is honoured without a separate observation step.
                    let presets = pacePresets()
                    ForEach(presets.indices, id: \.self) { i in
                        Button(presets[i].label) {
                            if selectedPaceIndex == i {
                                selectedPaceIndex = nil
                                workoutManager.targetPaceSecondsPerKm = nil
                            } else {
                                selectedPaceIndex = i
                                workoutManager.targetPaceSecondsPerKm = presets[i].secondsPerKm
                            }
                        }
                        .font(.caption)
                        .foregroundColor(selectedPaceIndex == i ? AppTheme.coral : .primary)
                        .buttonStyle(.plain)
                    }

                    if selectedPaceIndex == nil {
                        Text("None — tap to set")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Button("Start") {
                    workoutManager.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coralDeep)
                // audit/accessibility (May 2026) High — EU EAA deadline
                // (2025-06-28) has passed. SwiftUI Button auto-derives
                // the VoiceOver name from "Start"; the hint adds the
                // usage cue that name alone doesn't carry.
                .accessibilityHint("Begins a new run, starting GPS and heart-rate recording")
            }
        }
    }
}

// MARK: - Running View

struct RunningView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        VStack(spacing: 8) {
            Text(workoutManager.formattedElapsed)
                .font(.system(.title, design: .monospaced))

            HStack {
                VStack {
                    Text("Distance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(workoutManager.formattedDistance)
                        .font(.headline)
                }
                VStack {
                    Text("Pace")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(workoutManager.formattedPace)
                        .font(.headline)
                }
                VStack {
                    Text("HR")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(healthKit.currentBPM.map { "\($0)" } ?? "—")
                        .font(.headline)
                        .foregroundColor(AppTheme.coral)
                }
            }

            Text("\(workoutManager.track.count) GPS pts")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Pause") {
                    workoutManager.pause()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.duskDeep)
                .accessibilityHint("Pauses the recording without ending it")

                Button("Stop") {
                    workoutManager.stop()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.error)
                .accessibilityHint("Ends the run and opens the summary")
            }
        }
    }
}

// MARK: - Paused View

struct PausedView: View {
    @ObservedObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Paused")
                .font(.headline)

            VStack(spacing: 4) {
                Text(workoutManager.formattedElapsed)
                    .font(.system(.title3, design: .monospaced))
                Text(workoutManager.formattedDistance)
                    .font(.body)
            }

            Button("Resume") {
                workoutManager.resume()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.coralDeep)
            .accessibilityHint("Resumes the paused recording")

            Button("Stop", role: .destructive) {
                workoutManager.stop()
            }
            .font(.caption)
            .accessibilityHint("Ends the run and opens the summary")
        }
    }
}

// MARK: - Recovery View

struct RecoveryView: View {
    let workoutManager: WorkoutManager
    let onRecover: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Unsaved Run")
                    .font(.headline)

                if let cp = CheckpointStore.peekCheckpoint() {
                    let dateStr = Self.formatDate(cp.startedAt)
                    let distStr = String(format: "%.1f km", cp.distanceMetres / 1000)
                    let durStr = Self.formatDuration(cp.activeDurationSeconds)
                    Text("Recover unsaved run from \(dateStr), \(distStr), \(durStr)?")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }

                Button("Recover") {
                    onRecover()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coralDeep)
                .accessibilityHint("Restores the unsaved run from the last checkpoint")

                Button("Discard", role: .destructive) {
                    onDiscard()
                }
                .font(.caption)
                .accessibilityHint("Deletes the unsaved run permanently")
            }
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }
}

// MARK: - Post-Run View

struct PostRunView: View {
    @ObservedObject var workoutManager: WorkoutManager
    let transferState: WatchConnectivityManager.TransferState
    let thisRunSynced: Bool
    let syncError: String?
    let onSync: () -> Void
    let onSyncDirect: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Run Complete")
                    .font(.headline)

                VStack(spacing: 6) {
                    HStack {
                        Label(workoutManager.formattedDistance, systemImage: "figure.run")
                        Spacer()
                        Label(workoutManager.formattedElapsed, systemImage: "clock")
                    }
                    .font(.body)

                    HStack {
                        Label(workoutManager.formattedPace, systemImage: "speedometer")
                        Spacer()
                        if let bpm = workoutManager.finishedRun?.averageBPM {
                            Label("\(Int(bpm.rounded())) bpm", systemImage: "heart.fill")
                        } else {
                            Label("\(workoutManager.track.count) pts", systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                if thisRunSynced {
                    Label(syncedStatusText, systemImage: syncedStatusIcon)
                        .foregroundColor(AppTheme.coral)
                        .font(.body)
                        .multilineTextAlignment(.center)

                    Button("Start next run") {
                        onDiscard()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.duskDeep)
                    .accessibilityHint("Clears this synced run from the watch and returns to the start screen")
                } else {
                    if let error = syncError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(AppTheme.error)
                            .multilineTextAlignment(.center)
                    } else if case .failed(let msg) = transferState {
                        Text(msg)
                            .font(.caption2)
                            .foregroundColor(AppTheme.error)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        onSync()
                    } label: {
                        Label("Sync Run", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.coralDeep)
                    .accessibilityHint("Sends the completed run to your iPhone over Watch Connectivity")

                    #if DEBUG
                    Button("DEBUG: Sync Direct") {
                        onSyncDirect()
                    }
                    .font(.caption2)
                    #endif

                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                    .font(.caption)
                    .accessibilityHint("Throws away the unsynced run permanently")
                }
            }
        }
    }

    private var syncedStatusText: String {
        switch transferState {
        case .completed: return "Sent to phone"
        case .failed: return "Queued — will retry"
        default: return "Queued for sync"
        }
    }

    private var syncedStatusIcon: String {
        if case .completed = transferState { return "checkmark.circle.fill" }
        return "clock.arrow.circlepath"
    }
}
