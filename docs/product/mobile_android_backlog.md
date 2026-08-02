---
name: Mobile Android parity backlog
description: The remaining execution order for closing the few open gaps between web (canonical) and mobile_android. The bulk of the original phased plan has shipped; this is what's left.
---

# Mobile Android parity backlog

[`docs/product/parity.md`](parity.md) is the single source of truth for *which* features are missing — every cell flips there when work lands. This doc is the **execution order** for the handful of Android gaps that remain after the 2026 parity push closed most of the matrix.

## Where we stand

As of 2026-06-14 mobile_android is the most mature surface in the repo and sits at near-complete parity with web. Counting the Android column of `parity.md` (203 feature rows): **159 `✓`, 13 `Partial`, 16 `✗`, 15 `N/A`.** (That tally is a 2026-06-14 snapshot and several rows have flipped since — `parity.md` is the live count, not this line.)

Most of the original backlog has shipped, so it has been removed from this doc (it's in git history). The api_client / domain-model / Riverpod-store / screens phasing is done; the gym, nutrition, gear, safety-contacts, coaching, session/routine, typed-events create-wiring, route-builder (click-to-place + OSRM + elevation-while-drawing), club-owned-route admin transfer, and publish-plan-to-club/template flows are all live on Android.

Of the 16 `✗` Android rows, several are **not Android gaps**: they're web-canonical surfaces (`decisions.md § 24`) that are deliberately web-only, or they're blocked on a third-party credential rather than on code. Filtering those out leaves the genuine web→Android gaps below.

### Genuine remaining gaps (web `✓`/`Partial`, Android `✗`)

| Gap | Section in parity.md | Note |
|---|---|---|
| Direct messages (1:1) | Following and feed | Web `/messages/[[id]]`; mobile has no DM surface and `api_client` has no conversation methods. **The one unambiguous read-surface gap left.** |

### Closed since this list was written (verified on disk 2026-08-02)

| Was listed as a gap | Where it actually lives now |
|---|---|
| Event photo gallery (multi-attendee) | `apps/mobile_android/lib/widgets/event_photos.dart`, mounted from `screens/event_detail_screen.dart`. |
| Display matched track on run detail | `screens/run_detail_screen.dart` — fetches `run_matched_tracks` + the matched gz in the background and can re-queue a `map_match` job. |
| Treadmill BLE live run-screen wiring (C3) | `screens/run_screen.dart` `_toggleTreadmillMode` against the app-owned `BleTreadmill` singleton. See [treadmill_live_mode.md](../features/treadmill_live_mode.md). |
| Per-device "+ Add override" typed editor | `screens/devices_screen.dart` `_addOverride` — the key-catalogue sheet on top of the existing `setDeviceOverride` write path. |
| Native in-app Strava OAuth | `screens/settings_integrations_screen.dart` `_connectStrava` — `FlutterWebAuth2` against `kStravaCallbackScheme`, with state/CSRF checking. The browser hand-off survives only as the fallback when `isStravaConfigured()` is false (no client id compiled in). |

### Partial gaps still worth finishing on Android

| Gap | Section in parity.md | What's left |
|---|---|---|
| Native paywall sheets (RevenueCat / Play Billing) | Paywall and funding | The native path is **built**: `revenuecat.dart` wraps `purchases_flutter` behind an env gate and `screens/settings_pro_screen.dart` drives purchase / restore / manage through it, falling back to the browser only when `isRevenueCatConfigured()` is false. Flips from `Partial` to `✓` once the RevenueCat dashboard / `pro_monthly` product / API keys are provisioned operator-side — **gated on credentials, not on code.** |

### Gaps that are web-canonical or credential-blocked (not Android work)

These are `✗` on Android by design or by external dependency — listed so they aren't re-discovered as drift:

- **AI route request (NL → constraints)**, **bulk results import (chip-timing CSV)**, **claim an imported result** — web-canonical per `decisions.md § 24`; mobile already has the read-side parity. Close by building web, not Android.
- **Garmin Connect** (🔸) — OAuth blocked on the Garmin developer-program approval; not a code gap.
- **Native push notifications (FCM/APNs)** — the code shipped (migration `20270212_001`, the worker's `nativepush` sender, and the mobile `push_messaging_bridge.dart` token registration on both twins); **going live is blocked on Firebase / APNs credentials**, which is a deploy step, not Android work. See [native_push.md](../features/native_push.md).
- **AI Coach context (recent lifts + 7-day nutrition)** — a web-side server feature; the mobile coach already renders the richer answers it produces.

## Sequencing note for the remainder

The structural foundations (`api_client`, `core_models`, stores, `ui_kit`) all exist, so these no longer follow the old foundation-before-screens phasing — each remaining item is self-contained. Items 1, 2 and 4 of the original sequence have since landed (see the closed-gaps table above); what is left is:

1. **Direct messages** — one screen composing `api_client` methods, mirroring the web `/messages/[[id]]` shape. `api_client` has no conversation methods yet, so add those first per the rule below.
2. **Native paywall sheets go-live** — the code is landed and fail-closed; the remaining work is provisioning RevenueCat credentials operator-side, not Android work.

*Shipped since this doc was written:* the **post-signup setup wizard** (`setup_wizard_screen.dart` + the `home_screen.dart` `onboarded_at` gate + `ApiClient.completeOnboarding`/`markOnboarded`), the **personal run-track heatmap** (`run_heatmap_screen.dart` + the pure `run_heatmap.dart` twin), and the **finisher certificate** (`widgets/finisher_certificate_card.dart` on the event-detail leaderboard).

Every item still obeys the rule: **don't fan a screen out into ad-hoc `Supabase.instance.client` queries** — go through the typed `api_client`, adding a method there first if one is missing.

## Device-additive capabilities (mobile-only, not parity gaps)

Beyond the web→mobile gaps above, mobile ships **device-led** capabilities that have no web equivalent (web is not a recording surface — the `decisions.md § 24` physical exception). These are net-new on mobile, not parity rows.

- **BLE chest-strap HR** — shipped (`ble_heart_rate.dart`, wired into the run screen, with mid-run auto-reconnect).
- **Treadmill BLE (FTMS), C3** — shipped end to end: `ble_treadmill.dart` (FTMS 0x1826 / Treadmill Data 0x2ACD parser, status stream, auto-reconnect), the `TreadmillTile` pairing UI in Settings → Integrations, the additive `RunRecorder.setTreadmillSample` distance seam (belt distance overrides GPS only while treadmill mode is on; the run is tagged `metadata.indoor_source = 'treadmill'`), and the live run-screen `_toggleTreadmillMode` over an app-owned `BleTreadmill` singleton. All tested, twin-mirrored to iOS. Remaining follow-up is watch-side (Wear OS / watchOS) BLE, tracked in [integrations.md § Treadmills](../features/integrations.md#treadmills-ble-ftms).

## Cell flips

Every time a feature lands on Android, flip its `parity.md` row in the same PR — the matrix is only useful if it's current. Don't batch.

## Single source of truth

- **What**: [`parity.md`](parity.md) — the matrix.
- **Order**: this doc (for the remaining gaps only).
- **Why**: [`decisions.md § 24`](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive).
