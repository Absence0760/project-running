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
        DispatchQueue.main.async {
            self.currentBPM = nil
            self.averageBPM = nil
        }
    }
}

extension HealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
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
