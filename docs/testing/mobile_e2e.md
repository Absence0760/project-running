# Mobile e2e in CI — short answer

**Yes for Android, conditional yes for iOS, with caveats.** Both are doable. Neither is free. Pick the strategy that matches what you actually want to catch.

This doc exists because "can we run mobile e2e in CI?" is the right question to ask, and the answer depends on what you mean by "e2e" and how much money you want to spend per PR.

## Today

The mobile apps have ~178 widget tests in `apps/mobile_android/test/` (mirrored to `apps/mobile_ios/test/`). Each spins up a Flutter widget tree in a headless `flutter test` runner and asserts on rendered widgets. **These run on every PR** in the `test-packages` CI job — see `.github/workflows/ci.yml`. They are *fast* (~4 min for the whole suite) and don't need a device.

What they don't catch:
- Whether a real emulator can install + cold-launch the APK / IPA.
- Whether the OS-level permission prompts fire in the right order.
- Whether the foreground-service notification + wakelock survive the screen-off transition.
- Whether the OS picks up our deep links from Strava / Garmin OAuth redirects.
- Whether Health Connect / HealthKit imports actually surface real workouts.
- Visual regressions (we have no golden tests today — separate issue).

Closing those gaps is the job of integration tests + e2e tests on a real device or emulator. None are wired up today.

## What "e2e" can mean

Three increasingly expensive tiers:

| Tier | What it is | Where it runs | Per-PR cost |
|---|---|---|---|
| **A. Build smoke** | `flutter build apk` / `flutter build ios --no-codesign` succeeds. | Ubuntu / macOS runner. | Already runs on `main` push (`build-android`, `build-ios` jobs). ~7 min Android, ~10 min iOS macOS. |
| **B. Integration tests** | `flutter integration_test` against a headless emulator / simulator. Real app on real OS. No device farm. | Ubuntu (Android) / macOS (iOS) runner. | ~10–20 min Android, ~15–25 min iOS macOS. |
| **C. Real-device farm** | Same tests, on real devices via Firebase Test Lab / BrowserStack / Sauce / EAS Build. | Cloud farm. | $0.05–$0.25 per device-minute; ~5–15 min per device per PR. |

## Tier A — already in CI

The release-track build smoke is the cheapest defence against "I broke the gradle build". It's running. Keep it running.

Cost: a few minutes of free GitHub Actions Ubuntu compute on every push to `main`, plus macOS minutes (which are billed 10x Ubuntu — verify against the current Actions pricing) for the iOS build.

## Tier B — viable, recommended for Android, expensive for iOS

### Android: `flutter integration_test` on a KVM-accelerated emulator

Wiring:

1. `apps/mobile_android/pubspec.yaml`: add `integration_test:` to `dev_dependencies` (it's bundled with Flutter SDK).
2. `apps/mobile_android/integration_test/` directory with `*_test.dart` files. Same `testWidgets(...)` API; the binding is `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`.
3. GitHub Actions: add a `mobile-android-e2e` job using `reactivecircus/android-emulator-runner@v2` (KVM-accelerated on Ubuntu). The matrix runs `api-level: [29, 34]` or similar.

Sample test scope (start small):
- App cold-launches to onboarding.
- Permission rationale dialog renders.
- Sign-in flow completes with the seed user against a `--dart-define=SUPABASE_URL=http://10.0.2.2:54321` stack started by the CI workflow.
- Tap "Start run" → expect run-screen widget tree.

Per-PR cost: ~15–20 min on an Ubuntu runner (free quota), one full APK build + one emulator boot + the test run. The biggest single time-sink is the emulator boot — `reactivecircus/android-emulator-runner` caches AVD snapshots between runs to amortise that.

**Recommendation:** Add a `mobile-android-e2e` job with 3–5 critical smoke tests. Skip the full widget-test scope; the integration tests should hit code that widget tests *can't* hit (real GPS permissions, real foreground service, real Health Connect query).

### iOS: `flutter integration_test` on macOS

Same Flutter wiring as Android. The CI changes:

1. Job runs on `macos-latest`. macOS minutes are billed 10x Ubuntu on GitHub-hosted runners.
2. Boot an iOS Simulator (`xcrun simctl boot ...`) before the run.
3. `flutter test integration_test/` with `-d <simulator-id>`.

Per-PR cost: ~20–30 min on macOS runner. At $0.08/min that's ~$1.60–$2.40 *per PR*. For a project with 10–20 PRs / month that's ~$30/month, which is fine; for a high-throughput team it gets expensive.

**Recommendation:** Run iOS e2e on a nightly schedule + on every release tag, not on every PR. Set up a `release-ios.yml` extension that runs the same 3–5 critical tests.

## Tier C — cloud device farms

When you need *real device* coverage (sensor quirks, vendor-specific OEM behaviour, OS versions older than the runner image supports), use a farm. Three options at a similar tier:

| Provider | Pricing model | Strengths |
|---|---|---|
| **Firebase Test Lab** | Per-device-minute; cheapest virtual devices ($1/device-hour); physical devices $5/h | Excellent Android coverage; integrates with Google APIs; the *only* place with rare Pixel + Samsung S-series + non-Google OEM combos at scale |
| **BrowserStack** | Per-user-month subscription | Both Android + iOS; quick to provision; good IDE integration; pricier per minute than FTL but no per-test ceiling |
| **AWS Device Farm** | Per-device-minute; ~$0.17/min | Good iOS coverage; AWS-native; deep integration if the rest of the infra is on AWS |
| **EAS Build (Expo)** | Bundled into EAS pricing | Cheapest *managed* path; less control over device matrix |

Anti-recommendation for this project specifically: BitBar/Sauce Labs are fine but more expensive without compensating features for our scope.

**Recommendation:** Adopt Firebase Test Lab for the Android device matrix (Pixel 6/7/8, Samsung S22/S23, OneUI quirks), nightly schedule, post-release-tag. iOS: defer until we have a specific bug class the simulator misses; iOS simulators are unusually close to real-device behaviour.

## Frameworks worth knowing about

| Tool | What it adds | Verdict for this project |
|---|---|---|
| **Flutter integration_test** | The official, in-tree e2e binding. Same API as widget tests. | Use this. |
| **Patrol** | Wraps integration_test with native-side helpers — tap OS dialogs, swipe notifications, control Bluetooth. Resolves the "can't tap the permission dialog" pain. | Strong yes for any test that needs real OS permission dialogs (we have several: location-always, Bluetooth, Health Connect). |
| **Maestro** | YAML-defined flows that work against installed builds. Cloud or local. | Worth a look for handoff to QA. Less coverage of widget state assertions than integration_test. |
| **Detox** | React-Native-first; works for Flutter but the JS bridge fights us. | Skip. |
| **WebDriverIO / Appium** | Generic mobile automation. | Skip for Flutter — integration_test is strictly better. |

## Practical proposal

If we adopt one thing in the next sprint, it's this:

1. **Per-PR**: keep current widget tests (already there). Add a `mobile-android-e2e` job with 5 smoke tests via integration_test + `reactivecircus/android-emulator-runner`. ~20 min, free-tier quota.
2. **Nightly**: extend to 20+ tests, plus iOS via macOS runner.
3. **Pre-release**: Firebase Test Lab matrix run on Android + manual smoke on iOS Simulator at minimum.

If we adopt two things, add **Patrol** the moment we want to exercise the permission-dialog or Bluetooth-pairing flows. Native dialog tapping is genuinely impossible without it.

If we adopt three things, the third is **golden tests** (Flutter's snapshot-image testing) for visual regressions — that's a separate concern from e2e but commonly bundled in the conversation.

## What it would cost

Estimated monthly CI spend, assuming ~30 PRs / month + nightly + 2 releases:

| Tier | Where | Cost |
|---|---|---|
| Current widget tests | Ubuntu free quota | ~$0 |
| + Android integration_test on PR | Ubuntu free quota (KVM-accelerated) | ~$0 (within free 2k-min quota) |
| + iOS integration_test nightly | macOS runner ~30 min/night | ~$70/month |
| + Firebase Test Lab pre-release on 8 device-min × 4 devices × 2 releases | FTL physical $5/h | ~$5/month |
| **Total** | | **~$75/month** |

If iOS goes on PR instead of nightly: ~$700/month. Defer until clear ROI.

## What this looks like in `.github/workflows/`

A future-state addition (not built today):

```yaml
mobile-android-e2e:
  runs-on: ubuntu-24.04
  needs: [build-android]
  steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
    - uses: reactivecircus/android-emulator-runner@v2
      with:
        api-level: 34
        target: google_apis
        arch: x86_64
        profile: pixel_8
        avd-name: ci-pixel-8
        emulator-options: -no-window -gpu swiftshader_indirect -no-snapshot-save -noaudio -no-boot-anim
        script: |
          cd apps/mobile_android
          flutter test integration_test/
```

The matching `integration_test/onboarding_smoke_test.dart` would be ~30 LoC.

## TL;DR

- **Can mobile e2e run in CI?** Yes.
- **Is it too resource-heavy?** Android: no, fits in free tier. iOS on PR: yes for any non-trivial volume; do it nightly.
- **What blocks adoption today?** The `integration_test/` directory + Patrol dep + the CI job don't exist yet. ~1–2 days of work to land the first 5 smoke tests.
- **Pick this next** when the manual-testing burden of "did GPS / permissions / Health Connect still work?" outweighs ~1 day of integration-test wiring.
