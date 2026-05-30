# apps/mobile_ios

Flutter iOS app. Mirrors the web app's feature surface and adds iOS-only capabilities (Apple Sign-In, HealthKit import, BLE chest-strap HR, pedometer / cadence, haptic / TTS pace alerts, OS share sheets, Watch Connectivity ingest from the paired `watch_ios` companion).

**Byte-identical twin invariant.** `apps/mobile_ios/lib/` and `apps/mobile_ios/test/` are kept byte-for-byte identical to `apps/mobile_android/`. Platform-specific runtime behaviour dispatches via `Platform.isIOS` / `Platform.isAndroid` inside the unified files. See [decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase). Verify with `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` (should be empty).

## Run locally

```bash
cd apps/mobile_ios
flutter pub get
cd ios && pod install && cd ..

# Secrets pass via dart_defines.json (gitignored). See decisions.md §13.
flutter run --dart-define-from-file=dart_defines.json
```

The local Supabase stack must be up first (`cd apps/backend && supabase start`). Seed user is `runner@test.com` / `testtest`. An iOS simulator or paired device is required.

## See also

- [CLAUDE.md](CLAUDE.md) — full session notes: twin rule, platform-divergence table, iOS-only native files, Info.plist requirements
- [local_testing.md](local_testing.md) — every feature, how to verify on simulator / device
- [deployment.md](deployment.md) — App Store Connect setup, signing, watch bundling, observability, rollback
- [`../watch_ios/`](../watch_ios/) — the native SwiftUI Apple Watch app that ships inside this IPA
- [`../../docs/product/parity.md`](../../docs/product/parity.md) — feature × platform matrix; rows with `✗` or `Partial` for this app are the backlog
