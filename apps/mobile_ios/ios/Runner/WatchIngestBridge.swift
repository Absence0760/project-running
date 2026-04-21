import Flutter
import Foundation
import WatchConnectivity

/// Receives finished runs from the paired Apple Watch via
/// `WCSession.transferFile(_:metadata:)` and forwards them to Dart via
/// the `run_app/watch_ingest` method channel.
///
/// The singleton is installed in `AppDelegate` at launch (so the
/// delegate is live before the Flutter engine exists) and the method
/// channel is attached as soon as the engine spins up. Any runs that
/// arrive before the engine is ready are queued in memory and flushed
/// when the channel becomes available.
@objc class WatchIngestBridge: NSObject, WCSessionDelegate {
    @objc static let shared = WatchIngestBridge()

    private var methodChannel: FlutterMethodChannel?
    private var pending: [[String: Any]] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @objc func attach(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "run_app/watch_ingest",
            binaryMessenger: binaryMessenger
        )
        flushPending()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required by the protocol on iOS; reactivate so the session
        // keeps working if the user switches paired watches.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata else { return }
        var payload: [String: Any] = [:]
        // Required metadata fields — match what watch_ios writes in
        // `ContentView.syncRun()`.
        for key in ["id", "started_at", "source", "activity_type"] {
            if let v = metadata[key] { payload[key] = v }
        }
        if let v = metadata["duration_s"] { payload["duration_s"] = v }
        if let v = metadata["distance_m"] { payload["distance_m"] = v }
        if let v = metadata["avg_bpm"] { payload["avg_bpm"] = v }

        // The file itself is the raw JSON array of track points the
        // watch wrote. Forward it as a string and let the Dart side
        // decode. `FileManager`-based read because the file URL is a
        // temporary inbox location we may lose access to momentarily.
        if let data = try? Data(contentsOf: file.fileURL),
           let str = String(data: data, encoding: .utf8) {
            payload["track"] = str
        } else {
            payload["track"] = "[]"
        }

        if methodChannel != nil {
            dispatch(payload)
        } else {
            pending.append(payload)
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let snapshot = pending
        pending.removeAll()
        for p in snapshot { dispatch(p) }
    }

    private func dispatch(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod("run", arguments: payload) { result in
                // If Dart returned false, Supabase write failed — re-queue
                // for the next activation so we don't drop the run.
                if let ok = result as? Bool, !ok {
                    self?.pending.append(payload)
                }
            }
        }
    }
}
