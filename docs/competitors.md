# Run app — competitor analysis

A reference for understanding the competitive landscape, where each major app falls short, and the strategic gaps this app is built to fill.

> See also:
> - [roadmap.md](roadmap.md) — what's planned per phase
> - [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md) — every feature actually shipped on Android today

---

## What's shipped today (Android)

The Android app already covers a surprising amount of ground for an in-development product. The table below is "shipped right now", not aspirational.

| Capability | Run app (Android) | Strava | Nike Run Club | Garmin Connect | Komoot | Runna |
|---|---|---|---|---|---|---|
| Free GPX/KML import | ✓ | Paywalled | — | ✓ | ✓ | — |
| Free GPX export | ✓ | Paywalled | — | ✓ | ✓ | — |
| Live GPS recording with map | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Background recording (foreground service) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Auto-pause | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Manual pause / resume | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Lap markers | ✓ | ✓ | ✓ | ✓ | — | Auto (workout-driven) |
| Route following with off-route alerts | ✓ | Premium | — | ✓ | ✓ | — |
| Distance remaining on route | ✓ | ✓ | — | ✓ | ✓ | — |
| Audio cues (TTS splits + pace alerts) | ✓ | ✓ | ✓ | ✓ | Limited | ✓ (workout coaching) |
| Activity types with per-type behaviour (run/walk/cycle/hike) | ✓ | ✓ | Run only | ✓ | ✓ | Run only |
| Cadence and step count | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Elevation chart per run | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| Weekly distance goal with progress | ✓ | ✓ (Premium) | ✓ | ✓ | — | ✓ (plan-driven) |
| Personal Bests (longest, fastest pace, fastest 5k) | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Map tile cache (in-memory) | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| **Fully offline mode — works with no account** | ✓ | — | — | — | — | — |
| **JSON backup of all runs** | ✓ | CSV (Premium) | — | TCX export | GPX | — |
| Auto-sync on wifi reconnect | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Conflict resolution (newer-wins) | ✓ | ✓ | ✓ | ✓ | ? | ✓ |
| Edit run title and notes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Share run as GPX via system share sheet | ✓ | Premium | — | ✓ | ✓ | — |
| Dark mode + system theme | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Adaptive training plans | Phase 3 | Paywalled | Guided runs | ✓ | — | **Native** |

### What's deliberately not in the app yet (and why)

These are tracked in [roadmap.md](roadmap.md) and intentionally pushed to a later phase:

- **OAuth sign-in (Google, Apple)** — only email/password right now. Needs deep link and signing config.
- **Strava and parkrun sync** — placeholder buttons removed from Settings to avoid lying. Comes back in Phase 3 with real OAuth + scraping.
- **Bluetooth heart rate strap** — needs flutter_blue_plus and per-device GATT handling.
- **Persistent disk tile cache** — currently in-memory only; tiles re-download after app restart. Trail running with no signal still works during a single session.
- **Premium training features** — Phase 3, requires the Go service for training-load and VDOT calculations.
- **Live spectator tracking** — Phase 2, needs the Go service WebSocket.
- **Social features, segments, leaderboards** — explicitly not in scope for v1. These are Strava's moat; we differentiate on free planning and watch parity.

### Migration paths shipped today

Bringing your existing run history with you is the single biggest barrier to switching apps. The Android app now ships with two paths:

- **Strava ZIP import** — every Strava user can request a full data export from Settings → My Account → Download or Delete Your Account. The exporter unzips it, parses `activities.csv`, walks each `.gpx`/`.tcx`/`.gpx.gz` track file, and bulk-creates runs in the local store. Pushes to the cloud automatically if signed in. FIT files are skipped (re-export from Strava as GPX).
- **Health Connect import** — on Android 14+, every fitness app syncs into Health Connect: Google Fit, Samsung Health, Garmin Connect, Fitbit, Runna, even Nike Run Club via the Strava bridge. The importer reads workout summaries from the last year. The trade-off is that Health Connect doesn't expose GPS routes for workouts written by other apps, so imported runs from this path don't have a map trace.

Together these cover the realistic migration cases. A user migrating from Strava gets full GPS tracks; a user migrating from any other app gets workout summaries with no map. Either way, they walk in with their full history on day one.

Storage was redesigned in the same release: GPS tracks now live as gzipped JSON files in Supabase Storage instead of inline `jsonb` columns. A 5-year power-user import (≈600 MB raw) compresses to ~75 MB and costs cents per user per year instead of dollars. **Bulk import would have been economically unviable on the old schema.**

### Lines worth defending

Three differentiators are already real on Android and are the strongest pitches:

1. **Free GPX/KML import** — Strava paywalls this. Most runners who plan routes outside their app hit this wall.
2. **Fully offline mode without an account** — every other major app forces sign-in before you can record. Run app records to local JSON, syncs later if you ever sign in.
3. **Activity types that actually differ** — picking "Cycle" swaps pace for speed, switches calorie multipliers, uses 5km splits, and adapts the GPS jitter filter. Most apps treat activity type as a label only.

---

## Market overview

The running app market is dominated by a small number of well-funded incumbents. None covers all platforms cleanly, and all of them gate meaningful features behind subscriptions. The opportunity is a free-first, watch-parity, open-source-maps alternative.

---

## Competitor profiles

### Strava

**Positioning:** The social network for runners and cyclists. Strongest brand recognition in the space.

**Strengths:**
- Huge community and segment ecosystem — the "Local Legend" and KOM system creates real competitive motivation
- Strong watch support: Apple Watch, Wear OS, Garmin, Polar, Suunto, COROS, Wahoo
- Official API with webhooks — the de facto data hub that other apps sync to
- Route builder and community-suggested routes
- Live segment tracking on supported Garmin devices

**Weaknesses:**
- Route builder is paywalled (Strava Premium ~$11.99/month)
- GPX download of your own routes is paywalled
- No streamlined route import — users must export KML and re-import manually
- Watch apps are thin — Strava is a companion to Garmin, not a replacement
- Wear OS app exists but is not feature-complete compared to Apple Watch
- UI has become cluttered; onboarding experience is poor for non-athletes

**Verdict:** The benchmark to beat on features. The paywall on route building is the clearest opening.

---

### Garmin Connect

**Positioning:** The companion ecosystem for Garmin hardware. Not trying to be a general running app.

**Strengths:**
- Deepest data of any platform — every Garmin sensor field available
- Excellent route building and course push to watch
- Training load, VO2 max, recovery advisor all built in
- Free to use (hardware purchase is the business model)
- Strava integration built-in

**Weaknesses:**
- Completely useless without a Garmin device
- No Apple Watch or Wear OS app
- UI is functional but dated — clearly built by engineers
- No social features worth using
- Route builder is desktop-only (web app), no mobile builder

**Verdict:** Not a direct competitor — it serves a hardware-specific audience. Relevant as a data source (via API or HealthKit/Health Connect sync) not as an app to displace.

---

### Nike Run Club

**Positioning:** Guided coaching runs and community challenges. Nike's marketing vehicle disguised as a fitness app.

**Strengths:**
- Best-in-class guided run audio coaching (Coach Bennett)
- Completely free — no subscription, no paywall
- Clean, polished UI
- Apple Watch app with reasonable feature set
- Strong Strava and Garmin sync for users who want to aggregate data

**Weaknesses:**
- No route planning whatsoever — you run where you want and it tracks it
- No GPX import
- No Wear OS app — Android users with watches get nothing
- No post-run analysis beyond basic stats
- No community discovery features (you can't find routes other NRC users have run)
- Heavily Nike-branded — off-putting to non-Nike users

**Verdict:** Serves coached running well, ignores everything else. Users who want to plan specific routes actively look for alternatives.

---

### AllTrails

**Positioning:** The go-to app for hiking and trail running. Not a road running app.

**Strengths:**
- Enormous library of trail routes with user reviews and photos
- GPX download (free tier has limits, Pro removes them)
- Strong offline map support
- Apple Watch app (limited — recording only, no navigation)

**Weaknesses:**
- No Wear OS app
- Route builder is very trail-focused — poor for road runners
- No social running features (segments, challenges, leaderboards)
- No platform integrations (Strava sync exists but is one-way and limited)
- No coached running or training plan features
- Apple Watch app cannot do turn-by-turn navigation

**Verdict:** Dominates trails, irrelevant for road runners.

---

### Runna

**Positioning:** Training plans first, GPS app second. The Strava acquisition target — Strava bought Runna in 2025. Aimed squarely at runners training for a specific race distance.

**Strengths:**
- Best-in-class adaptive training plans for 5k, 10k, half marathon, marathon, and ultras
- Plans adjust automatically based on missed sessions and recent performance
- Strong onboarding flow that captures fitness level, goals, and race date
- Apple Watch app with workout-of-the-day push and live pacing prompts
- Audio coaching during structured workouts (intervals, tempo, fartlek)
- Strava sync built in (now official since the acquisition)
- Garmin Connect sync (push planned workouts to the watch)
- Clean, modern UI — clearly built with design as a priority

**Weaknesses:**
- Subscription-only — no free tier at all (~$19.99/month or ~$119.99/year)
- Pricey relative to Strava Premium
- Limited route planning — built for "follow the workout" not "follow the route"
- No GPX import for ad-hoc runs
- No Wear OS app — Android watch users get nothing
- Heart-rate-zone training requires a chest strap or watch
- Plans assume access to a track or measured loop — limited adaptation for trail or treadmill
- No social features at all (deliberate, but a gap if Strava starts pulling features over)

**Verdict:** The most credible threat in the "training plans" space and the closest analogue to what Phase 3 of this app aims at. Their weakness is the lack of free tier and no route planning — both of which this app addresses. Watch the Strava integration carefully: if Strava bundles Runna into Premium, the pricing argument changes overnight.

---

### Komoot

**Positioning:** Route discovery and turn-by-turn navigation for cycling, running, and hiking. Popular in Europe.

**Strengths:**
- Excellent route builder with surface-aware routing
- Turn-by-turn voice navigation during runs
- Strong GPX export/import
- Good Garmin, Wahoo, and Apple Watch integration
- One-time regional map purchase model (no monthly subscription)

**Weaknesses:**
- Weak social features compared to Strava
- No Wear OS app
- Navigation on Apple Watch is limited
- Less popular in North America
- UI is functional but not polished

**Verdict:** The closest thing to what this app aims to be, but without watch parity and with a narrower audience.

---

## Platform coverage matrix

| Feature | This app | Strava | Garmin Connect | Nike Run Club | AllTrails | Komoot | Runna |
|---|---|---|---|---|---|---|---|
| iOS app | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Android app | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Web app | ✓ | ✓ | Partial | — | ✓ | ✓ | — |
| Apple Watch | ✓ | ✓ | — | ✓ | Limited | Limited | ✓ |
| Wear OS | ✓ | ✓ | — | — | — | — | — |
| Garmin sync | ✓ | ✓ | Native | ✓ | Partial | ✓ | ✓ |

---

## Feature gap matrix

| Feature | This app | Strava | Garmin Connect | Nike Run Club | AllTrails | Komoot | Runna |
|---|---|---|---|---|---|---|---|
| Route builder | ✓ Free | Paywalled | Web only | — | Limited | ✓ | — |
| GPX import | ✓ Free | Paywalled | ✓ | — | ✓ | ✓ | — |
| GPX export | ✓ | Paywalled | ✓ | — | Paywalled | ✓ | — |
| Open-source maps (MapLibre) | ✓ | — | — | — | — | — | — |
| Turn-by-turn navigation | ✓ | — | ✓ | — | Limited | ✓ | — |
| parkrun sync | ✓ | — | — | — | — | — | — |
| Strava import | ✓ | Native | ✓ | ✓ | Limited | ✓ | ✓ |
| HealthKit sync | ✓ | ✓ | ✓ | ✓ | — | — | ✓ |
| Health Connect sync | ✓ | ✓ | ✓ | — | — | — | Partial |
| Coached running | Phase 3 | — | Training plans | ✓ | — | — | ✓ |
| Adaptive training plans | Phase 3 | Paywalled | ✓ | — | — | — | **Native** |
| Social segments | Phase 3 | ✓ | — | — | — | — | — |
| Community routes | Phase 3 | ✓ | — | — | ✓ | ✓ | — |
| Offline maps | Phase 3 | ✓ (premium) | ✓ | — | ✓ (premium) | ✓ | — |
| Segments + leaderboards | Backlog | **Native** | — | — | — | — | — |
| Heatmaps / popular-route tiles | Backlog | ✓ (premium) | — | — | — | ✓ | — |
| Route-condition reports | Backlog | — | — | — | ✓ | ✓ | — |
| Social graph (follows, kudos) | Backlog | ✓ | Limited | ✓ | — | ✓ | — |
| Gear tracking (shoe mileage) | Backlog | ✓ | ✓ | — | — | — | — |
| Photos on runs / routes | Backlog | ✓ | Partial | — | ✓ | ✓ | — |
| Audio-coached / guided runs | Backlog | — | — | **Native** | — | — | Partial |
| Race calendar + results | Backlog | Limited | ✓ | — | — | — | ✓ |
| VDOT + training load analytics | Backlog | ✓ (premium) | ✓ | — | — | — | ✓ |
| Clubs + events | ✓ (web, Android) | ✓ | Limited | ✓ | — | — | — |

Backlog items are tracked in `docs/roadmap.md § Competitor-parity backlog` with rough sizing and open decisions. No ordering implied — the user still owes three prioritisation decisions before any of these start.

---

## Pricing comparison

| App | Free tier | Paid tier | What's paywalled |
|---|---|---|---|
| **This app** | Full core features | ~$6/month | Training plans, AI coaching, advanced analytics |
| Strava | Basic tracking + social | ~$11.99/month | Route builder, GPX, segment leaderboards, training plans |
| Garmin Connect | Everything | N/A (hardware cost) | Nothing — hardware is the business model |
| Nike Run Club | Everything | N/A | Nothing |
| AllTrails | Basic trails | ~$35.99/year | Offline maps, GPX downloads, detailed trail info |
| Komoot | Local region free | ~$3.99/region | Maps in other regions |
| Runna | None — 7-day trial | ~$19.99/month or ~$119.99/year | Everything |

The pricing sweet spot is keeping everything Strava paywalls as free in this app, while monetising on coaching and intelligence that genuinely costs compute.

---

## User acquisition opportunities

### SEO — public route pages
Strava profile pages are not well-indexed by Google. A public route library with proper metadata (location, distance, surface type, elevation) can rank for "[city] running routes" searches. Each user who shares a route creates an indexed page.

### parkrun community
parkrun has millions of registered participants worldwide and a famously engaged community. Being "the app that actually tracks your parkrun history alongside your other runs" is a specific, shareable hook that no major app delivers.

### Wear OS users with no good option
NRC dropping Wear OS support leaves a gap. Android users with a Pixel Watch or Galaxy Watch running Wear OS have no dedicated running app with standalone GPS. This is a specific, searchable pain point.

### GPX/KML import workflow
"Plan a run on Google Maps" is a common search query. Positioning around a smooth import workflow — "plan anywhere, run with [app name]" — is a differentiated SEO angle that no competitor owns.

### Free route builder
"Free Strava route builder alternative" is a high-intent search that converts well. Users who've hit the Strava paywall are actively looking for alternatives.

---

## Risks and watch items

**Strava + Runna bundling.** Strava acquired Runna in 2025. The most likely move is bundling Runna into Strava Premium at the existing $11.99 price point, which would undercut a $19.99 Runna standalone subscription and pressure any independent training-plan competitor — including Phase 3 of this app. Counter-positioning: stay free for the core experience, charge less than Strava Premium for our training tier, and emphasise platform independence (Strava locks plans behind their account).

**Strava could open their route builder to free users.** They've done it before on some features. Monitor announcements. If this happens, the free route builder is no longer a differentiator — lean harder on open-source maps and watch parity instead.

**Nike Run Club could add Wear OS.** NRC is free and well-resourced. If they add Wear OS support, the Android watch gap closes. The response is to be deeper on route planning and data sync — areas NRC will never prioritise.

**Map tile costs at scale.** MapTiler has a generous free tier. At scale, migrate to Protomaps (self-hosted PMTiles on S3/R2) to eliminate per-request tile costs entirely.

**Strava API rate limits at scale.** The default Strava API quota is 2,000 requests per day across all users. With many connected users this gets tight quickly. Apply for a quota increase early — Strava reviews these individually.

---

*Last updated: April 2026*
