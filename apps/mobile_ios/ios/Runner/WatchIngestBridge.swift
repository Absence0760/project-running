import Flutter
import Foundation
import WatchConnectivity

/// Receives finished runs from the paired Apple Watch via
/// `WCSession.transferFile(_:metadata:)` and forwards them to Dart via
/// the `run_app/watch_ingest` method channel, and carries the opposite
/// direction — a route the runner picked on the phone, pushed to the watch
/// over `run_app/watch_route`.
///
/// Both directions live here because `WCSession.delegate` is a single slot:
/// a second class claiming its own session would take this one's delegate
/// away and silently stop run ingest.
///
/// The singleton is installed in `AppDelegate` at launch (so the
/// delegate is live before the Flutter engine exists) and the method
/// channel is attached as soon as the engine spins up. Any runs that
/// arrive before the engine is ready are queued in memory and flushed
/// when the channel becomes available.
@objc class WatchIngestBridge: NSObject, WCSessionDelegate {
    @objc static let shared = WatchIngestBridge()

    /// Positions one route push may carry. Must match `ArmedRoute.maxPoints`
    /// in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
    /// `kMaxAppleWatchRoutePoints` in `apple_watch_route_bridge.dart` — the
    /// watch drops an over-cap payload whole, so a phone that queued one
    /// would burn a durable transfer on a route that can never land.
    static let maxRoutePoints = 512

    private var methodChannel: FlutterMethodChannel?
    private var routeChannel: FlutterMethodChannel?
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
        let routes = FlutterMethodChannel(
            name: "run_app/watch_route",
            binaryMessenger: binaryMessenger
        )
        // Strong capture: `shared` is a permanent singleton, so there is no
        // cycle to break — and a weak self going nil would leave the Dart
        // future unanswered forever instead of failing.
        routes.setMethodCallHandler { call, result in
            self.handleRouteCall(call, result: result)
        }
        routeChannel = routes
        flushPending()
    }

    // MARK: - Route push (phone -> watch)

    /// `transferUserInfo`, not `sendMessage`: the runner picks a route while
    /// the watch is on a charger in another room, so the push has to outlive
    /// an unreachable counterpart. WCSession queues user-info transfers
    /// across app launches and watch reboots and delivers them in order,
    /// waking the watch app in the background to hand them over.
    private func handleRouteCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "available":
            result(Self.canPushRoute())
        case "push":
            guard let args = call.arguments as? [String: Any],
                  let payload = Self.routeUserInfo(from: args) else {
                result(FlutterError(
                    code: "bad_route",
                    message: "Route payload rejected",
                    details: nil
                ))
                return
            }
            guard Self.canPushRoute() else {
                result(FlutterError(
                    code: "watch_unavailable",
                    message: "No paired Apple Watch running the app",
                    details: nil
                ))
                return
            }
            WCSession.default.transferUserInfo(payload)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func canPushRoute() -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    /// Re-check the shape here as well as on the watch. A malformed payload
    /// that reaches `transferUserInfo` is queued durably and retried by the
    /// system forever against a watch that will reject it every time; the
    /// runner sees a success they never got.
    private static func routeUserInfo(from args: [String: Any]) -> [String: Any]? {
        guard let id = args["route_id"] as? String, !id.isEmpty,
              let name = args["route_name"] as? String,
              let distance = args["route_distance_m"] as? Double,
              distance.isFinite, distance >= 0,
              let latitudes = args["route_lat"] as? [Double],
              let longitudes = args["route_lng"] as? [Double],
              latitudes.count == longitudes.count,
              latitudes.count >= 2, latitudes.count <= maxRoutePoints
        else { return nil }
        return [
            "route_id": id,
            "route_name": name,
            "route_distance_m": distance,
            "route_lat": latitudes,
            "route_lng": longitudes,
        ]
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
        for key in ["id", "started_at", "source", "activity_type", "last_modified_at"] {
            if let v = metadata[key] { payload[key] = v }
        }
        if let v = metadata["duration_s"] { payload["duration_s"] = v }
        if let v = metadata["distance_m"] { payload["distance_m"] = v }
        if let v = metadata["avg_bpm"] { payload["avg_bpm"] = v }
        if let v = metadata["hr_coverage"] { payload["hr_coverage"] = v }

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
