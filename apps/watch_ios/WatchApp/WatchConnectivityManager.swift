import Foundation
import WatchConnectivity

/// Transfers completed runs from the Apple Watch to the paired iPhone over
/// `WCSession.transferFile(_:metadata:)`. The phone owns the Supabase write —
/// the watch just hands over the JSON track file + a metadata dict.
/// WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay),
/// queues across app launches, and retries on its own. Queued transfers
/// survive app closure and watch reboot, so a day of offline runs will all
/// drain to Supabase the moment the phone companion app next activates its
/// own `WCSession`.
///
/// The same session carries the inbound direction: the phone's unit
/// preference and the route it armed for this watch to follow (`ArmedRoute`).
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    enum TransferState: Equatable {
        case idle
        case pending
        case completed
        case failed(String)
    }

    @Published var transferState: TransferState = .idle
    @Published var queuedCount: Int = 0

    /// The route the phone last pushed, restored from disk so it survives the
    /// gap between arriving (often while the app is backgrounded) and the
    /// runner opening the app to start.
    @Published var armedRoute: ArmedRoute? = ArmedRouteStore.load()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// A run may only be handed off once WCSession has finished activating.
    /// `WCSession.activate()` is async at launch, so a short run right after a
    /// cold launch (or a session gone `.inactive`) can reach the sync tap
    /// before this is true. Pure so the caller-side decision is unit-testable
    /// without constructing the manager (its `init` activates a real session).
    static func canTransfer(activationState: WCSessionActivationState) -> Bool {
        activationState == .activated
    }

    /// What the watch may say about its own outbox the moment the session
    /// finishes activating.
    ///
    /// `queuedCount` and `transferState` are in-memory, and WCSession's outbox
    /// is not: a queued transfer survives app closure AND watch reboot, and
    /// waits days for a phone that is switched off. So on every relaunch the
    /// two disagreed — the watch came up saying `.idle` with a count of zero
    /// while the platform was still holding runs, and the pre-run screen's
    /// "N run queued to sync" line, the only place the watch ever says a run is
    /// still waiting, was simply absent (decisions § 1209).
    ///
    /// Pure because `WCSession` cannot be constructed in the unit-test host —
    /// the same reason `canTransfer` above is pure.
    static func stateOnActivation(outstanding: Int) -> TransferState {
        outstanding > 0 ? .pending : .idle
    }

    /// Hand a finished run off to the phone. Returns `true` only when the file
    /// was handed to WCSession's outbox (queued for delivery); `false` when the
    /// session isn't activated yet and nothing was queued. A `false` MUST be
    /// read by the caller as "not synced" — the finished run has to be kept for
    /// a retry, never marked done, or it is silently and irrecoverably dropped.
    func transferRun(fileURL: URL, metadata: [String: Any]) -> Bool {
        guard Self.canTransfer(activationState: WCSession.default.activationState) else {
            let message = String(localized: "Phone unavailable — tap Sync Run to retry")
            DispatchQueue.main.async { self.transferState = .failed(message) }
            return false
        }
        WCSession.default.transferFile(fileURL, metadata: metadata)
        DispatchQueue.main.async {
            // Read off the platform rather than incremented: the outbox
            // already holds the transfer just handed to it, and a private
            // tally seeded at zero on every launch is what made the count a
            // claim about this app session rather than about the queue.
            self.queuedCount = WCSession.default.outstandingFileTransfers.count
            self.transferState = .pending
        }
        return true
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard Self.canTransfer(activationState: activationState) else { return }
        let outstanding = session.outstandingFileTransfers.count
        DispatchQueue.main.async {
            self.queuedCount = outstanding
            self.transferState = Self.stateOnActivation(outstanding: outstanding)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil {
            // Only now is the run somewhere other than this watch. Deleting
            // the export any earlier — at reset(), say — would pull the file
            // out from under a transfer WCSession is still reading.
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
        DispatchQueue.main.async {
            if self.queuedCount > 0 { self.queuedCount -= 1 }
            if let error = error {
                self.transferState = .failed(error.localizedDescription)
            } else if self.queuedCount == 0 {
                self.transferState = .completed
            }
        }
    }

    /// Files WCSession is still holding for delivery. Survives app launches,
    /// so it is the authoritative keep-set for the stale-export sweep.
    func pendingTransferURLs() -> Set<URL> {
        guard WCSession.isSupported() else { return [] }
        return Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL })
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    // Also handle the alternative `userInfo` transport (queued, durable
    // across watch reboots). The phone may push via either sendMessage
    // (when the watch is reachable) or transferUserInfo (queues until the
    // watch wakes), so honour both. Routes always arrive this way — the
    // phone has no reason to expect a reachable watch when the runner
    // picks a route.
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        receive(userInfo)
    }

    /// Apply whatever the phone put in a payload. Every key is independent:
    /// a payload carrying only one of them leaves the rest untouched.
    private func receive(_ payload: [String: Any]) {
        // `preferred_unit` — the user's distance preference on the
        // phone (`'km'` or `'mi'`). Stored in UserDefaults so the
        // pre-run pace presets (see `pacePresets()` in
        // ContentView.swift) and any other unit-sensitive surface can
        // read it synchronously without a `@Published` observation.
        // Phone-side push isn't wired yet — when it lands, this
        // handler is what makes the watch's UI flip to imperial
        // labels in mi-mode users.
        if let unit = payload["preferred_unit"] as? String,
           unit == "km" || unit == "mi" {
            UserDefaults.standard.set(unit, forKey: "preferred_unit")
        }
        // A malformed or over-budget route is dropped whole rather than
        // trimmed — see `ArmedRoute.decode`. Persist before publishing so a
        // route that arrives while the app is backgrounded is still there
        // when the runner next opens it.
        if let route = ArmedRoute.decode(payload) {
            ArmedRouteStore.save(route)
            DispatchQueue.main.async { self.armedRoute = route }
        }
    }

    /// Drop the armed route from the wrist. The phone is the only writer, so
    /// without this the runner's only way out of a route they no longer want
    /// is to go back to the phone.
    func clearArmedRoute() {
        ArmedRouteStore.clear()
        armedRoute = nil
    }
}
