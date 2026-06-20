---
name: Mobile Android parity backlog
description: The remaining execution order for closing the few open gaps between web (canonical) and mobile_android. The bulk of the original phased plan has shipped; this is what's left.
---

# Mobile Android parity backlog

[`docs/product/parity.md`](parity.md) is the single source of truth for *which* features are missing — every cell flips there when work lands. This doc is the **execution order** for the handful of Android gaps that remain after the 2026 parity push closed most of the matrix.

## Where we stand

As of 2026-06-14 mobile_android is the most mature surface in the repo and sits at near-complete parity with web. Counting the Android column of `parity.md` (203 feature rows): **159 `✓`, 13 `Partial`, 16 `✗`, 15 `N/A`.**

Most of the original backlog has shipped, so it has been removed from this doc (it's in git history). The api_client / domain-model / Riverpod-store / screens phasing is done; the gym, nutrition, gear, safety-contacts, coaching, session/routine, typed-events create-wiring, route-builder (click-to-place + OSRM + elevation-while-drawing), club-owned-route admin transfer, and publish-plan-to-club/template flows are all live on Android.

Of the 16 `✗` Android rows, several are **not Android gaps**: they're web-canonical surfaces (`decisions.md § 24`) that are deliberately web-only, or they're blocked on a third-party credential rather than on code. Filtering those out leaves the genuine web→Android gaps below.

### Genuine remaining gaps (web `✓`/`Partial`, Android `✗`)

| Gap | Section in parity.md | Note |
|---|---|---|
| Event photo gallery (multi-attendee) | Clubs and events | Web ships the per-event gallery; mobile mirror deferred. |
| Direct messages (1:1) | Following and feed | Web `/messages`; mobile deferred. |
| Display matched track on run detail | Map matching | Web `/runs/[id]` renders the HMM-matched line; mobile not yet wired. |

### Partial gaps still worth finishing on Android

| Gap | Section in parity.md | What's left |
|---|---|---|
| Treadmill BLE live run-screen wiring (C3) | Following / activity feed | Parser + pairing tile + `RunRecorder.setTreadmillSample` seam are shipped and proven; only the live run-screen mode toggle that subscribes the belt stream during recording is left (UI wiring, not a recorder change). See below. |
| Per-device "+ Add override" typed editor | Settings → Device management | The edit-overrides sheet lists existing keys with per-row clear, and `setDeviceOverride` exists; the "+ Add override" typed key-catalogue picker for new keys is the remaining piece. |
| Native in-app Strava OAuth | Integrations | Connect hands off to web via `url_launcher`; sync + disconnect are already native. A native deep-link-callback / webview OAuth flow (`webview_flutter`) is the remaining upgrade. |
| Native paywall sheets (RevenueCat / Play Billing) | Paywall and funding | `purchases_flutter` is wired behind an env-gate; Pro checkout, manage-subscription, and donate currently fall back to the browser. These flip from `Partial` to `✓` once the RevenueCat dashboard / `pro_monthly` product / API keys are provisioned operator-side — **gated on credentials, not on code.** |

### Gaps that are web-canonical or credential-blocked (not Android work)

These are `✗` on Android by design or by external dependency — listed so they aren't re-discovered as drift:

- **AI route request (NL → constraints)**, **bulk results import (chip-timing CSV)**, **claim an imported result** — web-canonical per `decisions.md § 24`; mobile already has the read-side parity. Close by building web, not Android.
- **Garmin Connect** (🔸) — OAuth blocked on the Garmin developer-program approval; not a code gap.
- **Native push notifications (FCM/APNs)** — blocked on Firebase / APNs credentials; web subscribe + email + web-push already ship.
- **AI Coach context (recent lifts + 7-day nutrition)** — a web-side server feature; the mobile coach already renders the richer answers it produces.

## Sequencing note for the remainder

The structural foundations (`api_client`, `core_models`, stores, `ui_kit`) all exist, so these no longer follow the old foundation-before-screens phasing — each remaining item is self-contained:

1. **Treadmill C3 run-screen wiring** — smallest, highest-confidence: thread a shared `BleTreadmill` through `RunApp` → `run_screen`, add a treadmill-mode toggle that subscribes the belt stream and calls the already-shipped `setTreadmillSample`. No new plumbing.
2. **Per-device "+ Add override" editor** — bounded Settings change on top of the existing write-path.
3. **The read-path screens** (event photo gallery, direct messages, matched-track on run detail) — each is one screen composing existing `api_client` methods; mirror the web shape.
4. **Native Strava OAuth + native paywall sheets** — land the code behind the existing env-gates; the paywall sheets only *go live* once RevenueCat credentials are provisioned (fail-closed until then, per the compliance/credential-gate rule).

*Shipped since this doc was written:* the **post-signup setup wizard** (`setup_wizard_screen.dart` + the `home_screen.dart` `onboarded_at` gate + `ApiClient.completeOnboarding`/`markOnboarded`), the **personal run-track heatmap** (`run_heatmap_screen.dart` + the pure `run_heatmap.dart` twin), and the **finisher certificate** (`widgets/finisher_certificate_card.dart` on the event-detail leaderboard).

Every item still obeys the rule: **don't fan a screen out into ad-hoc `Supabase.instance.client` queries** — go through the typed `api_client`, adding a method there first if one is missing.

## Device-additive capabilities (mobile-only, not parity gaps)

Beyond the web→mobile gaps above, mobile ships **device-led** capabilities that have no web equivalent (web is not a recording surface — the `decisions.md § 24` physical exception). These are net-new on mobile, not parity rows.

- **BLE chest-strap HR** — shipped (`ble_heart_rate.dart`, wired into the run screen, with mid-run auto-reconnect).
- **Treadmill BLE (FTMS), C3** — `ble_treadmill.dart` (FTMS 0x1826 / Treadmill Data 0x2ACD parser, status stream, auto-reconnect) + `TreadmillTile` pairing UI in Settings → Integrations + the additive `RunRecorder.setTreadmillSample` distance seam (treadmill-sourced distance overrides GPS only when treadmill mode is active; the run is tagged `metadata.indoor_source = 'treadmill'`). **Built so far:** parser + model + pairing tile + recorder seam, all tested, twin-mirrored to iOS. **Deferred follow-up (the only open piece):** the live run-screen wiring — a mode toggle on the run screen that subscribes the belt stream and calls `setTreadmillSample` during recording, threading a shared `BleTreadmill` through `RunApp` → `run_screen`. The recorder seam it targets is shipped and proven, so this is purely UI wiring, not a recorder change.

## Cell flips

Every time a feature lands on Android, flip its `parity.md` row in the same PR — the matrix is only useful if it's current. Don't batch.

## Single source of truth

- **What**: [`parity.md`](parity.md) — the matrix.
- **Order**: this doc (for the remaining gaps only).
- **Why**: [`decisions.md § 24`](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive).
