import Foundation
import WatchConnectivity

/// Syncs recorded runs and routes between Apple Watch and iPhone.
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Send a completed run to the iPhone for syncing to Supabase.
    func transferRun(_ runData: [String: Any]) {
        guard WCSession.default.isReachable else {
            // Queue for transfer when connection is restored
            WCSession.default.transferUserInfo(runData)
            return
        }
        WCSession.default.sendMessage(runData, replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // TODO: Handle activation state
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // TODO: Handle incoming route data from iPhone
    }
}
