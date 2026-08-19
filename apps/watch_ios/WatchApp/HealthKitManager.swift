import Foundation
import HealthKit

/// Live heart-rate readings during a run. Apple Watch only samples HR
/// continuously inside an active `HKWorkoutSession`, so we start one
/// alongside the `CLLocationManager`-based recording even though GPS
/// and distance still come from CoreLocation. `HKLiveWorkoutBuilder`
/// drives the HR subscription.
class HealthKitManager: NSObject, ObservableObject {
    @Published var currentBPM: Int?
    @Published var averageBPM: Double?

    /// Drives the "heart rate unavailable" notice on the run and summary
    /// screens once the workout session has died. See `handleSessionFailure`.
    @Published private(set) var heartRateUnavailable = false

    /// The same fact as `heartRateUnavailable`, readable without waiting for
    /// a main-queue hop: HealthKit delivers `didFailWithError` on whatever
    /// queue it pleases, while `WorkoutManager.stop()` reads the summary
    /// synchronously, so a flag set only inside the hop can land after the
    /// run has already been stamped.
    private(set) var sessionDidFail = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let hrUnit = HKUnit.count().unitDivided(by: .minute())

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        let toRead: Set<HKObjectType> = [hrType]
        let toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        try? await healthStore.requestAuthorization(toShare: toShare, read: toRead)
    }

    func startWorkout() {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
        } catch {
            // HealthKit unavailable (simulator edge cases, missing entitlement).
            // HR display stays at "—"; the rest of the run records normally.
        }
    }

    func pauseSession() {
        session?.pause()
    }

    func resumeSession() {
        session?.resume()
    }

    func stopWorkout() {
        guard let session, let builder else { return }
        let endDate = Date()
        session.end()
        builder.endCollection(withEnd: endDate) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self?.session = nil
                    self?.builder = nil
                }
            }
        }
    }

    func reset() {
        sessionDidFail = false
        DispatchQueue.main.async {
            self.currentBPM = nil
            self.averageBPM = nil
            self.heartRateUnavailable = false
        }
    }

    /// The average a finished run may carry. A failed session's average
    /// covers only the minutes before the sensor stream died, so it is
    /// withheld rather than written to the row as the whole run's — 20
    /// minutes of a 4-hour run is a wrong number, not a partial one.
    var summaryAverageBPM: Double? {
        sessionDidFail ? nil : averageBPM
    }

    /// A workout session that reports a failure is dead: it delivers no
    /// further samples, so without this the last reading stays on screen as
    /// a plausible live heart rate for the rest of the run and its average
    /// is stamped on the run as if it had covered all of it.
    ///
    /// Drops the session, the reading and the average, and raises the flag
    /// the run / summary screens render. Deliberately touches nothing else:
    /// the GPS stream, the distance, the on-disk track and the timers are
    /// all `WorkoutManager`'s and keep recording, because losing the heart
    /// rate must never cost the run.
    func handleSessionFailure() {
        sessionDidFail = true
        session = nil
        builder = nil
        DispatchQueue.main.async {
            self.currentBPM = nil
            self.averageBPM = nil
            self.heartRateUnavailable = true
        }
    }
}

extension HealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // Left empty on purpose. `.ended` is not a failure: `stopWorkout()`
        // ends the session itself, so discarding the average here would wipe
        // it moments before `WorkoutManager.stop()` reads it into the
        // finished run.
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // The runner is told the heart rate is gone; the reason is only ever
        // useful to us, and nothing else records it.
        print("HealthKitManager: workout session failed: \(error)")
        handleSessionFailure()
    }
}

extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // A sample arriving after the session failed would put a number back
        // on a screen that has already told the runner it has none.
        guard !sessionDidFail else { return }
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType) else { return }

        let most = stats.mostRecentQuantity()?.doubleValue(for: hrUnit)
        let avg = stats.averageQuantity()?.doubleValue(for: hrUnit)

        DispatchQueue.main.async {
            if let most = most { self.currentBPM = Int(most.rounded()) }
            if let raw = avg, raw >= 30 && raw <= 230 {
                self.averageBPM = raw
            }
        }
    }
}
