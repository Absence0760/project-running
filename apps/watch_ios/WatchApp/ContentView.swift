import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if workoutManager.isRecording {
                    RunningView(workoutManager: workoutManager)
                } else {
                    PreRunView(workoutManager: workoutManager)
                }
            }
        }
    }
}

struct PreRunView: View {
    @ObservedObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready to Run")
                .font(.headline)

            // TODO: Show selected route name if one is loaded

            Button("Start") {
                workoutManager.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}

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
                    Text(workoutManager.formattedDistance)
                        .font(.headline)
                }
                VStack {
                    Text("Pace")
                        .font(.caption2)
                    Text(workoutManager.formattedPace)
                        .font(.headline)
                }
            }

            Button("Stop") {
                workoutManager.stop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}
