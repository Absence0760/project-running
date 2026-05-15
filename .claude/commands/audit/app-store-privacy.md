---
description: Verify iOS Privacy Nutrition Labels + Play Data Safety + manifest disclosures match what the binaries actually do
---

Audit App Store + Play Store privacy-disclosure surfaces.

## Goal

Both stores reject submissions on privacy mismatches more often than any other category. The binary collects HR + precise location + photos; the App Store Connect / Play Console privacy form must say so, and the matching `Info.plist` / `AndroidManifest.xml` / `PrivacyInfo.xcprivacy` / `health_permissions.xml` must match.

## What to check

The `app-store-privacy-auditor` agent has the full per-store checklist. The headline items:

### iOS

- Privacy Nutrition Labels (Health & Fitness, Precise Location declared)
- `NSPrivacyAccessedAPITypes` (`PrivacyInfo.xcprivacy`) exists + covers every plugin
- Every required `NSUsageDescription` (Location When In Use + Always, Motion, Bluetooth, HealthKit Share/Update, PhotoLibrary)
- `ITSAppUsesNonExemptEncryption = false`
- `UIBackgroundModes` = location + processing; `BGTaskSchedulerPermittedIdentifiers` lists `com.runonward.backgroundSync`
- In-app account deletion (Guideline 5.1.1(v))
- Sign in with Apple at least as prominent as Google (Guideline 4.8)
- HealthKit data not sent for advertising (Guideline 5.1.3)

### Play

- Data Safety form matches binary
- Target SDK ≥ Play's current floor
- Background-location justification + in-app explainer
- Foreground service types declared (`location`, `dataSync`)
- Health Connect data types declared + Privacy Policy URL set
- In-app + web account deletion
- Wear OS Data Safety form separate from phone app

### Cross-store

- Subscription disclosure: price + period + renewal + cancel + restore-purchases
- Age rating accurate (health data may bump)

## Report

- **Critical** — known reject trigger.
- **High** — disclosure-mismatch with binary behaviour.
- **Medium** — out-of-date string / manifest entry.
- **Low** — sloppy phrasing.

End with **clean** list of disclosure surfaces that look correct.

## Delegate to

Use the `app-store-privacy-auditor` agent: `"Audit App Store + Play Store privacy disclosures across mobile_ios, mobile_android, watch_ios, watch_wear."`

Read-only. Findings only. Always end legal claims with "verify against the current App Review Guidelines / Developer Program Policies" — those evolve quarterly.
