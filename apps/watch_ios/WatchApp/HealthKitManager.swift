import Foundation
import HealthKit

/// What a finished run may say about its heart rate.
///
/// The watchOS half of Wear OS's `HeartRateClaim` / `heartRateClaim`
/// (`apps/watch_wear/.../recording/HeartRateCoverage.kt`). Deliberately NOT a
/// registered parity pair: the registries pair web with mobile, the two watch
/// clients are additive surfaces under decisions § 24, and there is no
/// enforcement rail between them. What has to match is the MEANING of the
/// number, because both clients write the same row — see the `hr_coverage`
/// registry entry in `docs/backend/metadata.md` (decisions § 1156).
struct HeartRateClaim: Equatable {
    /// The mean of the run's samples, or nil when there were none — or when
    /// there were, but over too little of the run to call it the run's
    /// average.
    let averageBPM: Double?
    /// Fraction of ACTIVE elapsed time the sensor was delivering, 0..1 to two
    /// decimals. Nil when nothing measured it.
    let coverage: Double?
}

enum HeartRateCoverage {
    /// The share of a run's active time the wrist sensor must have been
    /// delivering for the mean of its samples to be saved as THE RUN'S average
    /// heart rate.
    ///
    /// Half, and the number is the sentence rather than a tuning knob: a mean
    /// taken over less of the run than not is not the run's average, and
    /// `avg_bpm` is read everywhere — run detail, the coach context, the
    /// export — as though it were. Same figure as Wear's
    /// `MIN_AVG_BPM_COVERAGE`, because a threshold that differed by platform
    /// would mean one number with two meanings on one column
    /// (decisions § 1083).
    static let minAverageBPMCoverage = 0.5

    /// A sample older than this is not evidence that the sensor is delivering
    /// NOW. Thirty seconds is loose enough that HealthKit's batching is not
    /// punished — it delivers heart rate in bursts a few seconds apart — and
    /// short enough that a silence measured in minutes is not credited.
    static let sampleFreshInterval: TimeInterval = 30

    /// The active seconds one recorder tick may credit to coverage: the step
    /// since the last tick, and only while the newest sample is still fresh
    /// at that moment.
    ///
    /// Pure, and separated from the accumulator that calls it, because this is
    /// the arithmetic that GATES a shipped field and a real `HKWorkoutSession`
    /// cannot be constructed in the test host — an accumulator whose only
    /// exercise is a wrist is one nobody can check before it deletes an
    /// `avg_bpm` (decisions § 1156).
    ///
    /// A nil `sampleAgeSeconds` is "no sample has ever arrived", which credits
    /// nothing: the run has not started delivering yet. A NEGATIVE age is
    /// credited — a sample stamped slightly ahead of the reader's clock is a
    /// clock disagreement, not a stale sensor.
    static func creditedStep(
        activeElapsedSeconds: TimeInterval,
        lastTickSeconds: TimeInterval,
        sampleAgeSeconds: TimeInterval?
    ) -> TimeInterval {
        guard activeElapsedSeconds.isFinite, lastTickSeconds.isFinite else { return 0 }
        let step = activeElapsedSeconds - lastTickSeconds
        guard step > 0,
              let sampleAgeSeconds,
              sampleAgeSeconds.isFinite,
              sampleAgeSeconds <= sampleFreshInterval else { return 0 }
        return step
    }

    /// Grade the run's mean against how much of the run it covered.
    ///
    /// A nil `coveredSeconds` is **unmeasured, not zero**. The absence of a
    /// measurement is no evidence of absent coverage, so the mean passes
    /// through unqualified exactly as it did before coverage existed — which
    /// is what keeps a run whose `HKWorkoutSession` never started (HealthKit
    /// unavailable, the entitlement missing, a simulator) carrying the
    /// average it would have carried anyway. Every unusable input lands on
    /// that same branch on purpose: this figure GATES a shipped field, and a
    /// measurement that fails toward zero would delete a good `avg_bpm` on
    /// every run rather than on the runs it is about.
    static func claim(
        mean: Double?,
        coveredSeconds: TimeInterval?,
        activeElapsedSeconds: TimeInterval
    ) -> HeartRateClaim {
        guard let coveredSeconds,
              coveredSeconds.isFinite,
              activeElapsedSeconds.isFinite,
              activeElapsedSeconds > 0 else {
            return HeartRateClaim(averageBPM: mean, coverage: nil)
        }
        let raw = min(max(coveredSeconds / activeElapsedSeconds, 0), 1)
        // Rounded first, then compared: grading the raw fraction lets a run
        // report a coverage of 0.5 beside a suppressed average, and a record
        // that contradicts itself is worse than either answer.
        let coverage = (raw * 100).rounded() / 100
        return HeartRateClaim(
            averageBPM: coverage >= minAverageBPMCoverage ? mean : nil,
            coverage: coverage
        )
    }
}

/// The coverage measurement itself, as a value: how many of the run's active
/// seconds the sensor was delivering for.
///
/// Lifted out of `HealthKitManager` because the manager's copy of this state
/// was reachable only through a live `HKWorkoutSession`, and one cannot be
/// constructed in the test host — so the glue between a sample's timestamp
/// and `creditedStep` had never executed anywhere, on any machine, while
/// already deciding whether shipped runs keep their `avg_bpm`. § 1156
/// extracted the arithmetic for exactly that reason and stopped at the state
/// it runs over; this carries the extraction the rest of the way
/// (decisions § 1299).
///
/// A value type rather than another object: the manager owns exactly one, the
/// recorder drives it, and nothing else may hold a reference to a
/// half-advanced measurement.
struct HeartRateCoverageAccumulator {
    /// Active seconds credited so far, or nil when nothing is measuring.
    ///
    /// Nil is **unmeasured, not zero** — see `HeartRateCoverage.claim`. It
    /// becomes zero at `begin()`, which is the moment a sensor exists to have
    /// a duty cycle, and a zero from then on is a real answer.
    private(set) var coveredSeconds: TimeInterval?

    /// The active clock reading the last credit was measured to.
    private var lastTickSeconds: TimeInterval = 0

    /// `timeIntervalSinceReferenceDate` of the newest usable sample, 0 for
    /// none yet.
    ///
    /// A bare `TimeInterval` with a sentinel rather than an `Optional`,
    /// deliberately: this is the one field written from HealthKit's own
    /// delivery queue while the recorder's ticker reads it on the main one,
    /// and a single word is the shape that race was accepted in. An
    /// `Optional<Double>` is a word plus a tag, and a torn read of THAT is a
    /// plausible-looking age rather than a wrong one by a fraction.
    private var lastSampleAtEpoch: TimeInterval = 0

    /// The session started: from here a zero is a measurement.
    mutating func begin() {
        coveredSeconds = 0
        lastTickSeconds = 0
        lastSampleAtEpoch = 0
    }

    /// Back to nothing measuring. Not the same as `begin()`: a run that never
    /// starts a session must claim nothing rather than claim zero.
    mutating func reset() {
        coveredSeconds = nil
        lastTickSeconds = 0
        lastSampleAtEpoch = 0
    }

    /// A usable sample arrived, stamped with the SAMPLE's own time.
    ///
    /// Recorded even before `begin()` so the ordering of the two callbacks
    /// cannot matter; nothing is credited until a measurement is running.
    mutating func noteSample(atEpoch epoch: TimeInterval) {
        lastSampleAtEpoch = epoch
    }

    /// Credit the tick's active seconds when the newest sample is still fresh
    /// at `nowEpoch`.
    ///
    /// `nowEpoch` is passed rather than read, which is the whole point of the
    /// type: a test can walk a whole run through this in a millisecond, and
    /// the freshness decision it makes is the shipped one.
    mutating func advance(activeElapsedSeconds: TimeInterval, nowEpoch: TimeInterval) {
        guard let covered = coveredSeconds else { return }
        let age: TimeInterval? = lastSampleAtEpoch > 0
            ? nowEpoch - lastSampleAtEpoch
            : nil
        let step = HeartRateCoverage.creditedStep(
            activeElapsedSeconds: activeElapsedSeconds,
            lastTickSeconds: lastTickSeconds,
            sampleAgeSeconds: age
        )
        // Advanced even on a tick that credits nothing, so a silence is
        // charged to the run exactly once rather than re-credited the moment
        // the sensor comes back.
        if activeElapsedSeconds.isFinite { lastTickSeconds = activeElapsedSeconds }
        coveredSeconds = covered + step
    }
}

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

    /// How much of the run the sensor has been delivering for.
    ///
    /// Its `noteSample` runs on whatever queue HealthKit pleases while the
    /// recorder's ticker drives `advance` on the main one — the same
    /// cross-queue shape `sessionDidFail` above already carries, and the same
    /// one Wear's `lastHrSampleAtMs` has. The two touch disjoint fields.
    private var coverage = HeartRateCoverageAccumulator()

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
            // From here a zero is a real measurement. Before it — and in the
            // catch below — there is no sensor to have a duty cycle.
            coverage.begin()
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
        coverage.reset()
        DispatchQueue.main.async {
            self.currentBPM = nil
            self.averageBPM = nil
            self.heartRateUnavailable = false
        }
    }

    /// The UNGRADED mean of the session's samples. A failed session's average
    /// covers only the minutes before the sensor stream died, so it is
    /// withheld rather than written to the row as the whole run's — 20
    /// minutes of a 4-hour run is a wrong number, not a partial one.
    ///
    /// **What this average is scoped to, because the row does not say.**
    /// It is `HKLiveWorkoutBuilder`'s own average over the
    /// `HKWorkoutSession`, so it is workout-scoped by construction: HealthKit
    /// holds the sensor for the life of the session, not for the life of the
    /// foreground app. That is exactly the failure Wear OS's `hr_coverage`
    /// measures against — `MeasureClient` there is documented foreground-only,
    /// so its mean can be the minutes the runner spent looking at the watch
    /// (decisions § 1015 / § 1083).
    ///
    /// **What being workout-scoped does NOT establish** is that every second
    /// of the session produced a sample. A session that stays alive while the
    /// sensor goes quiet — the watch loosened on the wrist, water lock, a
    /// sleeve pushed over it at an aid station — still averages what it got,
    /// and § 1106 recorded that as unquantified. It is quantified now:
    /// `advanceCoverage` measures it, and `heartRateClaim(activeElapsedSeconds:)`
    /// is what a saved run must go through. Nothing may read this property
    /// straight onto a row.
    ///
    /// **The measurement is now SENT as well as spent.** `ContentView.syncRun`
    /// packs `hr_coverage` into the `WCSession.transferFile(_:metadata:)`
    /// envelope whenever the claim carries one, and
    /// `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` lifts it back out
    /// — both ends, because claim (6) of `scripts/check_watch_ios_source.mjs`
    /// reads both and a key one end sends that the other never lifts is
    /// dropped in silence, which is exactly how Apple-Watch runs once arrived
    /// with no `activity_type` (decisions § 1207). Only a MEASURED figure is
    /// written: nil is unmeasured and omits the key rather than sending a
    /// zero, which would claim the sensor delivered nothing.
    ///
    /// The absence of the key is still not self-addressing, because both watch
    /// clients write `source = 'watch'` — there is no `watch_ios` value — so a
    /// `source = 'watch'` run with no coverage figure is an Apple-Watch run
    /// whose `HKWorkoutSession` never started, a Wear run from a build
    /// predating the key, or either client recovered from a checkpoint that
    /// never carried it. `docs/backend/metadata.md`'s `hr_coverage` row states
    /// the population.
    var summaryAverageBPM: Double? {
        sessionDidFail ? nil : averageBPM
    }

    /// Credit the tick's active seconds to coverage when the newest usable
    /// sample is still fresh.
    ///
    /// Driven from the recorder's own 1 s ticker rather than from
    /// `didCollectDataOf`, because the gap this exists to measure is a stream
    /// that has GONE QUIET — there is no delivery to hang it on, and an
    /// interval left open across the silence would credit the whole of it.
    ///
    /// `activeElapsedSeconds` is the recorder's own active clock, so time
    /// spent paused is neither credited nor charged: the ticker does not
    /// advance while paused, the step is the difference between two of its
    /// readings, and `pauseSession()` stops the sensor anyway.
    func advanceCoverage(activeElapsedSeconds: TimeInterval) {
        coverage.advance(
            activeElapsedSeconds: activeElapsedSeconds,
            nowEpoch: Date().timeIntervalSinceReferenceDate
        )
    }

    /// What a run ending now may claim about its heart rate. The one way a
    /// saved run — finished or checkpointed — may take an average from here.
    func heartRateClaim(activeElapsedSeconds: TimeInterval) -> HeartRateClaim {
        HeartRateCoverage.claim(
            mean: summaryAverageBPM,
            coveredSeconds: coverage.coveredSeconds,
            activeElapsedSeconds: activeElapsedSeconds
        )
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

        if most != nil {
            // The SAMPLE's own timestamp, not this delivery's. HealthKit
            // batches, so grading arrivals would measure its scheduling
            // rather than the sensor — a burst of five one-second samples
            // handed over at once is the sensor working, not failing.
            //
            // The fallback is deliberately the delivery instant and not
            // "no evidence": a sample HealthKit handed us with an
            // unreadable interval is still evidence the sensor is
            // delivering NOW, and the other reading would drive coverage
            // to zero and suppress a good average on every run rather
            // than on the runs this measures (decisions § 1156).
            coverage.noteSample(
                atEpoch: stats.mostRecentQuantityDateInterval()?.end
                    .timeIntervalSinceReferenceDate
                    ?? Date().timeIntervalSinceReferenceDate
            )
        }

        DispatchQueue.main.async {
            if let most = most { self.currentBPM = Int(most.rounded()) }
            if let raw = avg, raw >= 30 && raw <= 230 {
                self.averageBPM = raw
            }
        }
    }
}
