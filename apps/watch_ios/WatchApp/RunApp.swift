import SwiftUI
#if canImport(Sentry)
import Sentry
#endif

@main
struct RunApp: App {
    init() {
        #if canImport(Sentry)
        // Crash reporting + breadcrumb trail for production builds.
        // Add the `sentry-cocoa` SwiftPM package to the watchOS target
        // and define `SENTRY_DSN` + `APP_RELEASE` in the Xcode build
        // settings (Other Swift Flags: `-DSENTRY_DSN=...`) — or read
        // from Info.plist. Off when DSN is empty (dev / debug).
        let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        if !dsn.isEmpty {
            let release = (Bundle.main.object(forInfoDictionaryKey: "APP_RELEASE") as? String) ?? "dev"
            SentrySDK.start { options in
                options.dsn = dsn
                options.releaseName = release
                options.environment = release == "dev" ? "development" : "production"
                options.tracesSampleRate = 0.1
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
