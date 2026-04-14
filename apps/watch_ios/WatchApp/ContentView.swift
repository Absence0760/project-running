import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @State private var syncing = false
    @State private var synced = false
    @State private var syncError: String?
    @State private var authenticated = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch workoutManager.state {
                case .idle:
                    PreRunView(workoutManager: workoutManager, authenticated: authenticated)
                case .recording:
                    RunningView(workoutManager: workoutManager)
                case .finished:
                    PostRunView(
                        workoutManager: workoutManager,
                        syncing: syncing,
                        synced: synced,
                        syncError: syncError,
                        onSync: syncRun,
                        onDiscard: discardRun
                    )
                }
            }
        }
        .task {
            await autoSignIn()
        }
    }

    private func autoSignIn() async {
        do {
            _ = try await SupabaseService.shared.signIn(
                email: "runner@test.com",
                password: "testtest"
            )
            authenticated = true
        } catch {
            // Will show "not signed in" in UI
            authenticated = false
        }
    }

    private func syncRun() {
        guard let run = workoutManager.finishedRun else { return }
        syncing = true
        syncError = nil

        Task {
            do {
                try await SupabaseService.shared.syncRun(run)
                await MainActor.run {
                    syncing = false
                    synced = true
                }
            } catch {
                await MainActor.run {
                    syncing = false
                    syncError = error.localizedDescription
                }
            }
        }
    }

    private func discardRun() {
        syncing = false
        synced = false
        syncError = nil
        workoutManager.reset()
    }
}

// MARK: - Pre-Run View

struct PreRunView: View {
    @ObservedObject var workoutManager: WorkoutManager
    let authenticated: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready to Run")
                .font(.headline)

            if !authenticated {
                Text("Not signed in")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            Button("Start") {
                workoutManager.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
            .tint(.red)
        }
    }
}

// MARK: - Post-Run View

struct PostRunView: View {
    @ObservedObject var workoutManager: WorkoutManager
    let syncing: Bool
    let synced: Bool
    let syncError: String?
    let onSync: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Run Complete")
                    .font(.headline)

                // Summary stats
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

                if synced {
                    Label("Synced", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.body)

                    Button("Done") {
                        onDiscard()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let error = syncError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        onSync()
                    } label: {
                        if syncing {
                            ProgressView()
                        } else {
                            Label("Sync Run", systemImage: "arrow.up.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(syncing)

                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                    .font(.caption)
                }
            }
        }
    }
}
