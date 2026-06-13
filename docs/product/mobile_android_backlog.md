---
name: Mobile Android parity backlog
description: Sequenced plan for closing the gap between web (canonical) and mobile_android. Structural primitives first, screens second.
---

# Mobile Android parity backlog

[`docs/product/parity.md`](parity.md) is the single source of truth for *which* features are missing — every cell flips there when work lands. This doc is the **execution order**: what to build, in what sequence, and why structural primitives need to land before the screens that consume them.

## Where we stand

As of 2026-04-28 mobile_android sits at **~95% feature parity with web** — 131 of 142 non-physical-exception rows are `✓` and 8 more are `Partial` (covered with a documented follow-up). 3 features remain `✗` on Android while web has them shipped.

By section (drawn from parity.md, `web ✓ ∧ android ✗`):

| Section | Hard gaps | Partials | Notes |
|---|---:|---:|---|
| AI Coach | 0 | 0 | All 12 surface features shipped in `screens/coach_screen.dart` — chat UI, streaming SSE, archives drawer, plan switcher, runs window, context strip, daily-cap banner, markdown rendering, bubble actions (copy / regenerate / edit / thumbs), multi-line composer. Reached from the Coach icon in the Dashboard AppBar. |
| Route management | 3 | 1 | Click-to-place builder, OSRM snap, elevation-preview-while-drawing — all blocked on a MapLibre-Flutter polyline editor (one cohesive surface, ~1500 lines). Club-owned routes is `Partial` — list + view shipped, admin transfer-from-route-detail still pending. |
| Integrations | 0 | 1 | Strava connect/sync/disconnect tile shipped (OAuth happens via `url_launcher` hand-off to web `/settings/integrations`; once connected, sync + disconnect are native via Edge Function + RLS). Native in-app OAuth (deep-link callback or webview) is the Partial. parkrun shipped. |
| Photos / privacy | 0 | 0 | Photos on runs shipped (image_picker). Privacy zones shipped. |
| Plan templates | 0 | 1 | Adopt shipped; publish-to-club from `plan_detail_screen` still pending. |
| Settings | 0 | 1 | Devices screen shipped (rename + remove + edit existing overrides). The "+ Add override" typed editor for new keys is the partial gap. |
| Paywall | 0 | 4 | Manage subscription, Pro checkout, Donate, donation surface — all four open in the system browser via `url_launcher`. Native RevenueCat / Play Billing flows still pending. |

The web-canonical rule from [`decisions.md § 24`](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) means every row above (except where physically impossible — none of these are) is a real gap to close, not a deferred-by-design item.

## Plugin dependencies still needed

Two Pub packages were added to `pubspec.yaml` (run `flutter pub get` once after pulling):

- `image_picker` (^1.1.2) — used by **Photos on runs**. Modern image_picker uses Android's PhotoPicker by default on API 33+, so no manifest permission is required for gallery access.
- `url_launcher` (^6.3.1) — needed for **Strava OAuth live sync** and would upgrade the four paywall link-out tiles from share-sheet to direct browser hand-off.
- (Optional but useful) `webview_flutter` — only needed if we want an in-app OAuth callback handler instead of the deep-link route.

## Sequencing principle

Build foundations before screens. A screen that calls a non-existent `ApiClient` method blocks on the wider plumbing change anyway, and shipping screens that fan out into ad-hoc Supabase queries (bypassing the typed client) creates drift the next session has to undo. Order:

1. **Row classes** — already done. `db_rows.dart` is auto-generated from the SQL schema by `scripts/gen_dart_models.dart`; running the generator after every backend migration keeps it current. Verified rows present for every gap feature: `UserFollowRow`, `RunKudosRow`, `RunCommentRow`, `RunPhotoRow`, `NotificationRow`, `SegmentRow`, `SegmentEffortRow`, `CoachMessageRow`. No work needed here unless a future migration adds a new table.
2. **`api_client` typed methods** — `packages/api_client/lib/src/api_client.dart` currently exposes 26 methods covering auth + runs + routes + route reviews. Every other gap feature needs methods added here first. This is mechanical porting from `apps/web/src/lib/core/data.ts`.
3. **Domain models / state** — anything that doesn't map 1:1 to a row (e.g. `FeedEntry = Run + author profile`, `SegmentLeaderboardEntry`, `NotificationView`). Add to `core_models` so screens consume the same shape on web and android.
4. **Stores / providers** — Riverpod or whatever the android app uses for cross-screen state (notification badge count, follow toggle optimism, kudos count rollup). Mirror the Svelte stores' shape.
5. **Screens** — implement per feature. Each screen should compose api_client + stores + ui_kit widgets. No screen should call `Supabase.instance.client` directly.

The headline rule: **don't open a new screen file before the api_client method that screen will call exists**. Otherwise the screen accumulates ad-hoc queries and the typed client decays into a partial surface.

## Phased plan

### Phase 1 — `api_client` foundation (start here)

Each phase below is a coherent batch — all the methods land together, written in one PR, exercised by a smoke test.

**P1.A — Social engagement primitives (landed)**
Unblocks: profile pages, kudos / comments on run-detail, notifications inbox. Active list (already in `api_client.dart`):
- `followUser`, `unfollowUser`, `fetchFollowers`, `fetchFollowing`, `fetchPublicProfile`, `fetchFollowCounts`, `viewerFollows`
- `giveKudos`, `rescindKudos`, `fetchEngagementSummaries`
- `fetchRunComments`, `addRunComment`, `editRunComment`, `deleteRunComment`
- `fetchNotifications`, `fetchUnreadNotificationCount`, `markNotificationRead`, `markAllNotificationsRead`, `deleteNotification`

`fetchFollowingFeed` is intentionally deferred — it crosses into domain-model territory (`FeedEntry = Run + author UserProfile`), so it lands in Phase 2 alongside the other cross-shapes.

**P1.B — Photos + segments**
Unblocks: per-run photo gallery, segment leaderboards on run / route detail.
- `addRunPhoto`, `fetchRunPhotos`, `deleteRunPhoto`, `updateRunPhotoCaption`
- `createSegment`, `fetchSegmentsForRoute`, `fetchSegmentLeaderboard`, `fetchEffortsForRun`, `computeSegmentEffortsForRun`

**P1.C — Coach + privacy zones**
Unblocks: AI Coach chat, owner-side privacy zones on run share.
- `clipTrackForUser` (RPC wrapper)
- Coach: `fetchCoachMessages`, `sendCoachMessage` (SSE streaming wrapper), `archiveCoachThread`, `loadCoachArchives`, `getCoachUsage`, `setCoachReaction`

**P1.D — Clubs / events / plan-template additions**
Unblocks: create-club, create-event, plan templates, join approval.
- `createClub`, `updateClub`, `joinClubByToken`, `requestJoinClub`, `approveJoinRequest`, `denyJoinRequest`, `fetchPendingRequests`
- `createEvent`, `updateEvent`, `deleteEvent`, `setEventRsvp`, `fetchEventAttendees`
- `publishPlanAsTemplate`, `fetchClubTemplates`, `clonePlanTemplate`

### Phase 2 — Domain models + stores

After P1 the typed surface exists; this phase adds the cross-screen shapes:

- `FeedEntry`, `ProfileSummary`, `NotificationView`, `RunCommentWithAuthor`, `EngagementSummary`, `SegmentLeaderboardEntry` in `core_models`.
- Notification-badge store (mirror `apps/web/src/lib/stores/notifications.svelte.ts`).
- Follow-state store (so the Follow button on profile / feed entries doesn't flicker between reads).
- Kudos optimism helper (decrement / increment / rollback on error).

### Phase 3 — Screens

Order chosen so each screen has its dependencies in place from P1+P2:

1. **Profile page** (`u/[id]`-equivalent screen) — needs `fetchPublicProfile`, `fetchFollowers`, `fetchFollowing`, `fetchPublicRunsByUser`, `followUser`/`unfollowUser`. Honour `?tab=runs|followers|following|notifications` (notifications tab gated to self). **Shipped** as `screens/profile_screen.dart` with TabController, optimistic Follow toggle, and the Notifications tab nested inside (All / Unread filter, mark-all-read, per-row dismiss).
2. **Activity feed** — needs `fetchFollowingFeed`, `fetchEngagementSummaries`, `giveKudos`/`rescindKudos`, `fetchFollowing` (for the author combobox). Card grid + per-entry track preview + 14-day window. **Shipped** as `screens/feed_screen.dart`, mounted on the Dashboard AppBar (feed icon). 14-day server cap, activity-segmented + author-dropdown filters, infinite-scroll on (started_at, id), optimistic kudos toggle. Track-preview map and three-state empty handled inline.
3. **Notifications inbox tab** — already inside the profile page; **shipped** alongside Profile (P3.1).
4. **Run-detail kudos + comments + photos** — needs P1.A + P1.B. Mount on the existing `run_detail_screen.dart`. **Kudos + comments shipped** as `widgets/run_social_section.dart` (kudos pill + one-level comment thread + composer + reply composer + author/owner delete). **Photos still pending** — needs Storage upload + caption + delete UI.
5. **AI Coach chat screen** — large; needs P1.C complete. Plan switcher + runs window + tones + history sidebar all layer on top of the same chat surface, so build the chat first, then layer.
6. **Segment surfaces on route + run detail** — needs P1.B.
7. **Privacy-zone owner picker** — needs `clipTrackForUser` + a MapLibre Flutter equivalent picker.
8. **Plan templates + club owner flows** — needs P1.D.
9. **Route builder (click-to-place + OSRM)** — separate large project; defer until the social loop is closed.
10. **Public share + live spectator pages** — these are web-public surfaces; android can deep-link out, but native equivalents need their own thin screens.

### Phase 4 — Settings + paywall

Smaller surface; can land in parallel with later P3 screens.
- Device list / labels / per-device override editor / remove-device.
- RevenueCat-driven Pro checkout + donation surface (the Android RevenueCat plumbing already exists; just need the UI).
- Strava OAuth live sync (matches web `/settings/integrations` shape — RevenueCat-style hand-off to the Strava OAuth web flow).
- parkrun athlete-number import.

## Device-additive capabilities (mobile-only, not parity gaps)

Beyond closing the web→mobile parity gaps above, mobile also ships **device-led** capabilities that have no web equivalent (web is not a recording surface — the `decisions.md § 24` physical exception). These are net-new on mobile, not parity rows.

- **BLE chest-strap HR** — shipped (`ble_heart_rate.dart`, wired into the run screen).
- **Treadmill BLE (FTMS), C3** — `ble_treadmill.dart` (FTMS 0x1826 / Treadmill Data 0x2ACD parser, status stream, auto-reconnect) + `TreadmillTile` pairing UI in Settings → Integrations + the additive `RunRecorder.setTreadmillSample` distance seam (treadmill-sourced distance overrides GPS only when treadmill mode is active; the run is tagged `metadata.indoor_source = 'treadmill'`). **Built so far:** parser + model + pairing tile + recorder seam, all tested, twin-mirrored to iOS. **Deferred follow-up:** the live run-screen wiring (a mode toggle on the run screen that subscribes the belt stream and calls `setTreadmillSample` during recording, threading a shared `BleTreadmill` through `RunApp` → `run_screen`); the recorder seam it targets is shipped and proven, so this is purely UI wiring, not a recorder change.

## Cell flips

Every time a feature lands on android, flip its `parity.md` row in the same PR — the matrix is only useful if it's current. Don't batch.

## Single source of truth

- **What**: [`parity.md`](parity.md) — the matrix.
- **Order**: this doc.
- **Why**: [`decisions.md § 24`](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive).
