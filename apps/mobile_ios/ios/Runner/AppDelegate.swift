import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep the on-device GPS/HR run cache out of iCloud / iTunes backups.
    // The Flutter app writes every local run, route, gym and food JSON
    // file under Documents (path_provider's getApplicationDocumentsDirectory
    // → NSDocumentDirectory); all of it is sensitive-but-re-derivable — the
    // durable copy lives server-side and re-syncs. Excluding the directory
    // node excludes its whole subtree from backup. OS Data Protection still
    // encrypts these files at rest; this only closes the cloud-backup-
    // extraction path. See decisions.md (at-rest / backup posture).
    excludeDocumentsFromBackup()

    // Start listening for Apple Watch file transfers before the Flutter
    // engine spins up. Runs that arrive while the engine is still
    // loading are buffered in-process and flushed to Dart once the
    // method channel is attached below.
    WatchIngestBridge.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Best-effort (L4): a failure here must never block launch. Idempotent —
  // setting the flag every cold start is cheap and the directory always
  // exists for an installed app.
  private func excludeDocumentsFromBackup() {
    let fm = FileManager.default
    guard var docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try docs.setResourceValues(values)
    } catch {
      NSLog("Failed to exclude Documents from iCloud backup: \(error)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `FlutterPluginRegistry` conforms to `FlutterBinaryMessenger`, so
    // the registry doubles as the messenger for our custom channel.
    if let messenger = engineBridge.pluginRegistry as? FlutterBinaryMessenger {
      WatchIngestBridge.shared.attach(binaryMessenger: messenger)
    }
  }
}
