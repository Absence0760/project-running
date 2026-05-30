# apps/mobile_android

Flutter Android app — the most mature Flutter target in the monorepo. Mirrors the web app's feature surface and adds device-only capabilities (live GPS recording + foreground service, auto-pause, BLE chest-strap HR, pedometer, haptic / TTS pace alerts, OS share sheets + share-target intents, Health Connect import, disk-backed tile cache, WorkManager background sync).

**Byte-identical twin invariant.** `apps/mobile_android/lib/` and `apps/mobile_ios/lib/` (plus `test/`) are kept byte-for-byte identical — every change here must be mirrored to the iOS twin in the same commit. Platform-specific runtime behaviour dispatches via `Platform.isAndroid` / `Platform.isIOS` inside the unified files. See [decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase). The `mobile-twin-mirror` agent under `.claude/agents/` runs this check after any Dart edit.

## Run locally

```bash
cd apps/mobile_android
cp .env.example .env.local                 # if you haven't already
flutter pub get
flutter run                                # picks a running emulator / connected device
```

The local Supabase stack must be up first (`cd apps/backend && supabase start`). Seed user is `runner@test.com` / `testtest`.

## See also

- [CLAUDE.md](CLAUDE.md) — full session notes: scope rule, state-management contract, file inventory, test list, analyzer policy
- [local_testing.md](local_testing.md) — every feature, how to verify on a device / emulator
- [deployment.md](deployment.md) — Play Console signing, release workflow, observability, rollback
- [`../../docs/features/run_recording.md`](../../docs/features/run_recording.md) — the L0–L4 layered-resilience contract on the recording stack
- [`../../docs/product/parity.md`](../../docs/product/parity.md) — feature × platform matrix; rows with `✗` or `Partial` for this app are the backlog
