import Foundation
import WatchConnectivity

/// Transfers completed runs from the Apple Watch to the paired iPhone over
/// `WCSession.transferFile(_:metadata:)`. The phone owns the Supabase write —
/// the watch just hands over the gzipped track file + a metadata dict.
/// WCSession picks the transport (Bluetooth / Wi-Fi P2P / iCloud relay),
/// queues across app launches, and retries on its own.
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    enum TransferState: Equatable {
        case idle
        case pending
        case completed
        case failed(String)
    }

    @Published var transferState: TransferState = .idle

    private var pendingTransfer: WCSessionFileTransfer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Hand a finished run off to the phone. The phone syncs it to Supabase
    /// the next time it's reachable and online.
    func transferRun(fileURL: URL, metadata: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            DispatchQueue.main.async { self.transferState = .failed("WCSession not activated") }
            return
        }
        DispatchQueue.main.async { self.transferState = .pending }
        pendingTransfer = WCSession.default.transferFile(fileURL, metadata: metadata)
    }

    func cancelPendingTransfer() {
        pendingTransfer?.cancel()
        pendingTransfer = nil
        DispatchQueue.main.async { self.transferState = .idle }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No-op — the watch no longer receives credentials over the session.
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let next: TransferState
        if let error = error {
            next = .failed(error.localizedDescription)
        } else {
            next = .completed
        }
        DispatchQueue.main.async {
            self.pendingTransfer = nil
            self.transferState = next
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Future: handle route pushes from phone.
    }
}
