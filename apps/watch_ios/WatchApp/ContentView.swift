import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var syncing = false
    @State private var synced = false
    @State private var syncError: String?
    @State private var authenticated = false
    @State private var awaitingPhone = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch workoutManager.state {
                case .idle:
                    PreRunView(
                        workoutManager: workoutManager,
                        authenticated: authenticated,
                        awaitingPhone: awaitingPhone
                    )
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
        .task { await waitForCredentials() }
        .onChange(of: connectivity.hasPhoneCredentials) { _, hasCreds in
            if hasCreds {
                authenticated = true
                awaitingPhone = false
            }
        }
    }

    /// Wait briefly for the paired iPhone to hand over Supabase credentials
    /// via WCSession. In DEBUG, fall back to the seed user so the watch sim
    /// can be exercised without a phone. In Release, leave the UI in the
    /// "Not signed in" state until the phone responds.
    private func waitForCredentials() async {
        if connectivity.hasPhoneCredentials {
            authenticated = true
            awaitingPhone = false
            return
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if connectivity.hasPhoneCredentials { return }
        awaitingPhone = false
        #if DEBUG
        do {
            _ = try await SupabaseService.shared.signIn(
                email: "runner@test.com",
                password: "testtest"
            )
            authenticated = true
        } catch {
            authenticated = false
        }
        #endif
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
    let awaitingPhone: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready to Run")
                .font(.headline)

            if awaitingPhone {
                Text("Waiting for phone…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if !authenticated {
                Text("Not signed in")
                    .font(.caption2)
                    .foregroundColor(AppTheme.coral)
            }

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
                    .tint(AppTheme.coralDeep)
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
