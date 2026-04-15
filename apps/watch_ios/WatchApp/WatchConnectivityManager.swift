import Foundation
import WatchConnectivity

/// Syncs recorded runs and routes between Apple Watch and iPhone, and receives
/// the current Supabase auth state (access token, user id, base URL, anon key)
/// from the phone over `WCSession.updateApplicationContext(_:)`.
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var hasPhoneCredentials = false

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
            WCSession.default.transferUserInfo(runData)
            return
        }
        WCSession.default.sendMessage(runData, replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Future: handle route pushes from phone.
    }

    private func apply(_ ctx: [String: Any]) {
        guard let token = ctx["access_token"] as? String, !token.isEmpty,
              let userId = ctx["user_id"] as? String, !userId.isEmpty,
              let baseURL = ctx["base_url"] as? String, !baseURL.isEmpty,
              let anonKey = ctx["anon_key"] as? String, !anonKey.isEmpty else {
            return
        }
        Task {
            await SupabaseService.shared.applyCredentials(
                accessToken: token,
                userId: userId,
                baseURL: baseURL,
                anonKey: anonKey
            )
            await MainActor.run {
                WatchConnectivityManager.shared.hasPhoneCredentials = true
            }
        }
    }
}
