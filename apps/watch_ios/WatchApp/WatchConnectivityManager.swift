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

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Hand a finished run off to the phone. The file is copied into
    /// WCSession's outbox synchronously, so the caller can reset UI state
    /// immediately — WCSession owns delivery from here on.
    func transferRun(fileURL: URL, metadata: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            DispatchQueue.main.async { self.transferState = .failed("WCSession not activated") }
            return
        }
        WCSession.default.transferFile(fileURL, metadata: metadata)
        DispatchQueue.main.async {
            self.queuedCount += 1
            self.transferState = .pending
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if self.queuedCount > 0 { self.queuedCount -= 1 }
            if let error = error {
                self.transferState = .failed(error.localizedDescription)
            } else if self.queuedCount == 0 {
                self.transferState = .completed
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // `preferred_unit` — the user's distance preference on the
        // phone (`'km'` or `'mi'`). Stored in UserDefaults so the
        // pre-run pace presets (see `pacePresets()` in
        // ContentView.swift) and any other unit-sensitive surface can
        // read it synchronously without a `@Published` observation.
        // Phone-side push isn't wired yet — when it lands, this
        // handler is what makes the watch's UI flip to imperial
        // labels in mi-mode users.
        if let unit = message["preferred_unit"] as? String,
           unit == "km" || unit == "mi" {
            UserDefaults.standard.set(unit, forKey: "preferred_unit")
        }
        // Future: handle route pushes from phone.
    }

    // Also handle the alternative `userInfo` transport (queued, durable
    // across watch reboots). The phone may push the unit via either
    // sendMessage (when the watch is reachable) or transferUserInfo
    // (queues until the watch wakes), so honour both.
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        if let unit = userInfo["preferred_unit"] as? String,
           unit == "km" || unit == "mi" {
            UserDefaults.standard.set(unit, forKey: "preferred_unit")
        }
    }
}
