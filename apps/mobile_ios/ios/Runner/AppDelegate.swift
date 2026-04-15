import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Start listening for Apple Watch file transfers before the Flutter
    // engine spins up. Runs that arrive while the engine is still
    // loading are buffered in-process and flushed to Dart once the
    // method channel is attached below.
    WatchIngestBridge.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
