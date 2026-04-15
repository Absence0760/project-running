import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch workoutManager.state {
                case .idle:
                    PreRunView(workoutManager: workoutManager)
                case .recording:
                    RunningView(workoutManager: workoutManager)
                case .finished:
                    PostRunView(
                        workoutManager: workoutManager,
                        transferState: connectivity.transferState,
                        syncError: syncError,
                        onSync: syncRun,
                        onSyncDirect: syncRunDirect,
                        onDiscard: discardRun
                    )
                }
            }
        }
    }

    private func syncRun() {
        guard let run = workoutManager.finishedRun else { return }
        syncError = nil
        do {
            let fileURL = try workoutManager.writeTrackJSON()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let metadata: [String: Any] = [
                "id": run.id,
                "started_at": formatter.string(from: run.startedAt),
                "duration_s": run.durationSeconds,
                "distance_m": run.distanceMetres,
                "source": "app"
            ]
            connectivity.transferRun(fileURL: fileURL, metadata: metadata)
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

    private func discardRun() {
        connectivity.cancelPendingTransfer()
        syncError = nil
        workoutManager.reset()
    }
}

// MARK: - Pre-Run View

struct PreRunView: View {
    @ObservedObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready to Run")
                .font(.headline)

            Button("Start") {
                workoutManager.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.coralDeep)
        }
    }
}

// MARK: - Running View

struct RunningView: View {
    @ObservedObject var workoutManager: WorkoutManager

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
            }

            Text("\(workoutManager.track.count) GPS pts")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Stop") {
                workoutManager.stop()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.error)
        }
    }
}

// MARK: - Post-Run View

struct PostRunView: View {
    @ObservedObject var workoutManager: WorkoutManager
    let transferState: WatchConnectivityManager.TransferState
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
                        Label("\(workoutManager.track.count) pts", systemImage: "mappin.and.ellipse")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                if case .completed = transferState {
                    Label("Sent to phone", systemImage: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.coral)
                        .font(.body)

                    Button("Done") {
                        onDiscard()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.duskDeep)
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
                        if case .pending = transferState {
                            ProgressView()
                        } else {
                            Label("Sync Run", systemImage: "arrow.up.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.coralDeep)
                    .disabled(transferState == .pending)

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
                }
            }
        }
    }
}
