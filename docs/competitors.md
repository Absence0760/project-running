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
| Map tile cache (disk-backed) | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| **Fully offline mode — works with no account** | ✓ | — | — | — | — | — |
| **Full backup ZIP (lossless) — runs + routes + tracks + profile** | ✓ | CSV (Premium) | — | TCX export | GPX | — |
| **Backup restore on a freshly installed phone with no account** | ✓ | — | — | — | — | — |
| **CSV summary re-import (round-trips the Settings CSV export)** | ✓ | — | — | — | — | — |
| **Save individual routes for offline use (per-route pin)** | ✓ | — | — | Garmin device only | Region packs (paid) | — |
| **Phone → watch route sync without watch internet (DataLayer)** | ✓ Wear OS | — | — | — | — | — |
| Auto-sync on wifi reconnect | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Conflict resolution (newer-wins) | ✓ | ✓ | ✓ | ✓ | ? | ✓ |
| Edit run title and notes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Share run as GPX via system share sheet | ✓ | Premium | — | ✓ | ✓ | — |
| Dark mode + system theme | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Adaptive training plans | ✓ | Paywalled | Guided runs | ✓ | — | **Native** |

### What's deliberately not in the app yet (and why)

Most of what this section used to gate has shipped — OAuth (Google + Apple sign-in), Strava live OAuth + webhook sync, parkrun athlete-number import, BLE chest-strap HR, persistent disk tile cache, premium training endpoints + the matching UI (training plans, VDOT / VO₂ max, training load, recovery advice), live spectator (Supabase Realtime path), segments + leaderboards (v1 + v2 tiered with KOM/QOM crowns), follows + kudos + comments + notifications inbox, clubs + events + posts, gear tracking, photos on runs, web heatmap v1. Today's genuinely deferred items, sourced from the `[ ]` rows in [roadmap.md](roadmap.md) Phase 3 + the unphased competitor-parity backlog:

- **Live workout-execution loop** — specced in [workout_execution.md](workout_execution.md), ~4 dev-days, zero new schema. Lights up the structured-workout band overlay on the run screen and the post-run planned-vs-actual review. Plan + workout *data* is shipped; live execution against it isn't.
- **Push notifications (FCM / APNs)** — `device_tokens` table is shipped; the sender + client-side token registration are blocked on user-supplied Firebase / APNs credentials.
- **Garmin Connect OAuth** — hard-blocked on the multi-day Garmin Developer Program application.
- **Live spectator transport upgrade** — the Realtime fallback is live and shipping; the Go WebSocket hub at `apps/job_worker/internal/livehub/` is code-complete and awaits a Fly deploy.
- **Offline tile packs + turn-by-turn voice nav** — partial. Per-route "Save for offline" pin shipped (decisions.md § 64) — flags individual routes to keep on the phone — and the disk-backed tile cache is shipped for normal browsing. **Still pending:** pre-downloading a region's raster tiles before a no-signal trail run, plus turn-by-turn voice cues against a loaded route. The pin reserves the route data side; tile packs + cues are the remaining work.
- **Audio-coached / guided runs** — NRC-style curated coached workouts (separate from the existing TTS audio-cue layer).
- **Race calendar + results** — needs a RunSignUp API key; otherwise patterned after the existing parkrun import.
- **Phase 4: gym + nutrition modules** — see the [multi-modal section below](#multi-modal-competitive-landscape-phase-4--run--lift--meal) and [roadmap.md § Phase 4](roadmap.md#phase-4--multi-modal-gym--nutrition).

### Migration paths shipped today

Bringing your existing run history with you is the single biggest barrier to switching apps. The Android app now ships with four paths on the Import screen, alongside the lossless Backup ZIP round-trip:

- **Strava ZIP import** — every Strava user can request a full data export from Settings → My Account → Download or Delete Your Account. The exporter unzips it, parses `activities.csv`, walks each `.gpx`/`.tcx`/`.gpx.gz` track file, and bulk-creates runs in the local store. Pushes to the cloud automatically if signed in. FIT files are skipped (re-export from Strava as GPX).
- **Health Connect import** — on Android 14+, every fitness app syncs into Health Connect: Google Fit, Samsung Health, Garmin Connect, Fitbit, Runna, even Nike Run Club via the Strava bridge. The importer reads workout summaries from the last year. The trade-off is that Health Connect doesn't expose GPS routes for workouts written by other apps, so imported runs from this path don't have a map trace.
- **CSV summary re-import** — accepts both the 5-column mobile/web Settings CSV export and the 17-column backend GDPR export from `/v1/export?format=csv`. Each row becomes a manual-entry run (no GPS); idempotent on re-import via a stable `external_id`. The card copy says "won't have a route line" so the user isn't surprised by trackless rows. See `decisions.md § 65`.
- **Full Backup ZIP restore** — the lossless round-trip. Manifest + `runs.json` + `routes.json` + `profile.json` + per-run gzipped tracks. **Works without signing in** — runs hydrate into `LocalRunStore` + `LocalRouteStore` and ride the next `SyncService` cycle to Supabase. Surfaces on the Import screen alongside the other three paths AND on Settings → "Restore from backup". See `decisions.md § 66`.

Together these cover the realistic migration cases. A user migrating from Strava gets full GPS tracks; a user migrating from any other app gets workout summaries with no map; a user moving between this app's own devices gets the lossless Backup ZIP path. Either way, they walk in with their full history on day one.

Storage was redesigned in the same release: GPS tracks now live as gzipped JSON files in Supabase Storage instead of inline `jsonb` columns. A 5-year power-user import (≈600 MB raw) compresses to ~75 MB and costs cents per user per year instead of dollars. **Bulk import would have been economically unviable on the old schema.**

Backup at scale was rebuilt in May 2026 to stream to disk via `ZipFileEncoder` (mobile) / `@zip.js/zip.js` `BlobWriter` (web), with bounded-concurrency track downloads (6× in flight). Peak heap drops from ~300 MB to ~5 MB at 5 000 runs — the OOM ceiling that bricks every other client-side ZIP builder at scale is gone. For typical sub-5 000-run users, mobile prefers the Go service's `POST /v1/export?format=backup` path (server does the fan-out, mobile streams the signed URL straight to disk); falls back to the local writer on any failure or library size beyond the server cap. See `decisions.md § 66`.

### Lines worth defending

Five differentiators are already real on Android and are the strongest pitches:

1. **Free GPX/KML import** — Strava paywalls this. Most runners who plan routes outside their app hit this wall.
2. **Fully offline mode without an account** — every other major app forces sign-in before you can record. Run app records to local JSON, syncs later if you ever sign in.
3. **Activity types that actually differ** — picking "Cycle" swaps pace for speed, switches calorie multipliers, uses 5km splits, and adapts the GPS jitter filter. Most apps treat activity type as a label only.
4. **Lossless round-trip backup that works offline** — every other client-side ZIP builder OOMs the device at thousands of runs; ours streams to disk and handles 10 000+ without breaking a sweat. **Restore works on a freshly installed phone with no account** — rows queue locally and ride the next sync cycle once the user signs in. No other major app's backup story does both.
5. **Phone → watch route sync via DataLayer without watch internet** — star a route on the phone, it lands on the paired Wear OS watch the moment the phone has wifi, with no watch-side LTE required at run-start. NRC has no Wear OS at all; Strava's Wear OS app doesn't proactively push the user's starred set; Garmin requires a Garmin watch. A clean hardware-agnostic gap.

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
| Coached running (curated audio workouts) | Backlog | — | Training plans | **Native** | — | — | ✓ |
| Adaptive training plans | ✓ (web, Android) | Paywalled | ✓ | — | — | — | **Native** |
| Social segments | ✓ (web, Android) | ✓ | — | — | — | — | — |
| Community routes | ✓ (web, Android) | ✓ | — | — | ✓ | ✓ | — |
| Live structured workout execution | Phase 3 (pending) | Paywalled | ✓ | — | — | — | **Native** |
| Offline maps | Partial (disk tile cache shipped; offline packs pending) | ✓ (premium) | ✓ | — | ✓ (premium) | ✓ | — |
| Segments + leaderboards | ✓ (web, Android — v1 + v2 tiered) | **Native** | — | — | — | — | — |
| Heatmaps / popular-route tiles | ✓ (web v1; mobile read pending) | ✓ (premium) | — | — | — | ✓ | — |
| Route-condition reports | Backlog | — | — | — | ✓ | ✓ | — |
| Social graph (follows, kudos, comments) | ✓ (web, Android) | ✓ | Limited | ✓ | — | ✓ | — |
| Gear tracking (shoe mileage) | ✓ (web, Android) | ✓ | ✓ | — | — | — | — |
| Photos on runs / routes | ✓ (web, Android) | ✓ | Partial | — | ✓ | ✓ | — |
| Audio-coached / guided runs | Backlog | — | — | **Native** | — | — | Partial |
| Race calendar + results | Backlog | Limited | ✓ | — | — | — | ✓ |
| VDOT + training load + recovery analytics | ✓ (web, Android) | ✓ (premium) | ✓ | — | — | — | ✓ |
| Clubs + events | ✓ (web, Android) | ✓ | Limited | ✓ | — | — | — |
| Notifications inbox (kudos / comments / RSVPs) | ✓ (web, Android) | ✓ | ✓ | ✓ | — | — | ✓ |
| Lossless full backup ZIP (round-trip restore) | ✓ (web, Android — streaming + scales to 10 000+ runs) | Export-only (GDPR archive — no in-app re-import) | Export-only (TCX-per-run) | — | Export-only (GPX-per-run) | Export-only (GPX) | — |
| Backup restore on a freshly installed device, no account | ✓ (Android — offline-first) | — | — | — | — | — | — |
| CSV summary re-import | ✓ (Android — round-trips Settings export) | — | — | — | — | — | — |
| Per-route "Save for offline" pin | ✓ (Android) | — | — | Course push to Garmin watch | Region tile packs (paid) | — | — |
| Phone → Wear OS route sync without watch internet | ✓ (Wear OS — DataLayer push) | — | — | Garmin watch only | — | — | — |

Backlog items are tracked in `docs/roadmap.md § Competitor-parity backlog` with rough sizing and open decisions. No ordering implied — the user still owes three prioritisation decisions before any of these start.

---

## Pricing comparison

| App | Free tier | Paid tier | What's paywalled |
|---|---|---|---|
| **This app** | Full core features incl. training plans + 5 / day AI coach | ~$9.99/month (Pro) | Unlimited AI coach + priority job-queue processing (see [decisions.md § 23](decisions.md)) |
| Strava | Basic tracking + social | ~$11.99/month | Route builder, GPX, segment leaderboards, training plans |
| Garmin Connect | Everything | N/A (hardware cost) | Nothing — hardware is the business model |
| Nike Run Club | Everything | N/A | Nothing |
| AllTrails | Basic trails | ~$35.99/year | Offline maps, GPX downloads, detailed trail info |
| Komoot | Local region free | ~$3.99/region | Maps in other regions |
| Runna | None — 7-day trial | ~$19.99/month or ~$119.99/year | Everything |

The pricing sweet spot is keeping everything Strava paywalls as free in this app, while monetising on coaching and intelligence that genuinely costs compute.

---

## Multi-modal competitive landscape (Phase 4 — run + lift + meal)

Forward-looking. Phase 4 expands the product from running-only to running + gym + nutrition ([roadmap.md § Phase 4](roadmap.md#phase-4--multi-modal-gym--nutrition), [decisions.md § 63](decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)). The competitive set is entirely different from the running incumbents profiled above — no major player has the run + lift + meal combination as a first-class product. The space stays fragmented because each app's DNA prevents the next modality: nutrition apps treat exercise as "calories burned," strength apps don't understand cardio, running apps treat strength as cross-training rather than a parallel discipline, and the OS-level aggregators (Apple Health, Google Fit) treat everything as data rather than a guided experience.

### Ecosystem aggregators — the "data layer" play

- **Apple Health + Fitness+** — Health is the read-aggregator (logs all three modalities via third-party writes or native Apple Watch capture), Fitness+ is the workout-content product (~$9.99/month), Apple Watch is the capture hardware. Closest thing on the market to "everything in one place," but Health isn't really an active-use product — it's a data layer that surfaces other apps' writes. Nutrition surface is anaemic; users still pair it with MyFitnessPal.
- **Google Fit / Samsung Health** — the same play with weaker execution. Both deprioritised by their parent companies.

**Verdict:** Strong as a *data hub*, weak as an active-use product. The defensible angle isn't to compete with the aggregator — it's to be the *better source* that writes into the aggregator while owning the user-facing experience.

### Content / coaching-led — "do all three" via prescription

- **Centr** (Chris Hemsworth, ~$30/month) — explicitly pitches strength + cardio + meal plans + mindfulness. Celebrity-content-led, not a logging tool. Closest pitch overlap with multi-modal threkir, but the model is "follow our workouts and recipes" rather than "log what you actually did."
- **Future** (~$150/month) — 1:1 human coaching across modalities. Coach-mediated, not self-service.
- **Caliber** — strength + nutrition + cardio with coaching. Running is the weak point.

**Verdict:** The pitch overlaps but the model is opposite — they're content / coaching products that *happen to* span modalities; threkir is a logging / data product that *happens to* span modalities. Different buyer.

### Deep in one modality, weak bolt-on of another

- **MyFitnessPal** — nutrition-first, ~$19.99/month Premium. Workout logging has existed for years but runners don't use it for runs. Still the dominant nutrition player by a wide margin.
- **Hevy** — strength-first, ~$5.99/month Hevy Pro. Added nutrition tracking in 2024 but it's secondary. Running is not native.
- **Strong** — strength training only; deliberately scoped.
- **Garmin Connect** — strong across run / ride / swim / strength; nutrition is essentially absent.
- **Strava** — running / cycling; nutrition absent, strength logging exists but is barely used.
- **Fitbit (Google)** — wearable-first; nutrition logging is famously bad and Google's ownership has stalled investment since the acquisition.

**Verdict:** Each is locked in by its DNA. The bolt-ons exist but don't pull users from the dominant app in the other modality. A serious runner using MyFitnessPal for food is *also* using Strava or Garmin for runs — the bolt-on doesn't displace.

### B2B coaching platforms

- **Trainerize** — supports run + lift + nutrition but it's trainer-facing, not consumer-facing. Users log under their trainer's roof; trainers pay the subscription.

**Verdict:** Different market. Relevant only as evidence that the multi-modal data model is solvable.

### Where threkir slots in

The defensible position is **runner-led, with gym + nutrition as the natural complement to running performance** — a position no current player owns:

- **Strava and Runna** won't add nutrition as first-class (wrong DNA — Strava is social-graph-led, Runna is plan-led).
- **MyFitnessPal** can't get running right; improving it would cannibalise its Strava-pair-up audience.
- **Centr / Future** are content-led, not data-led — runners who care about pace, splits, and HR zones don't get what they need from a coaching app.
- **Aggregators (Apple / Google)** are data layers, not active-use products. Users still need a destination app that surfaces and reasons about the combined view.

The realistic upside is being the runner's chosen destination across all three modalities, with the cross-domain view (mileage + lift volume + protein intake on one Home) as the wedge against any one-modality incumbent.

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

### Friction-free migration off existing apps
"Move my Strava data to another app", "Export Garmin runs to another app", and similar queries are high-intent and underserved. With the four-path import surface (Strava ZIP, Health Connect / Apple Health, CSV summary, Backup ZIP) plus an offline-first restore that doesn't even need an account, the migration message — "bring your full history on day one, no sign-in required" — is unmatched. NRC has no import path; Strava's import is limited to single GPX files; Runna only takes Strava feed. The friction at the *front door* of every competitor is real, and the migration story is now first-class on our Import screen.

---

## Risks and watch items

**Strava + Runna bundling.** Strava acquired Runna in 2025. The most likely move is bundling Runna into Strava Premium at the existing $11.99 price point, which would undercut a $19.99 Runna standalone subscription and pressure any independent training-plan competitor — including Phase 3 of this app. Counter-positioning: stay free for the core experience, charge less than Strava Premium for our training tier, and emphasise platform independence (Strava locks plans behind their account).

**Strava could open their route builder to free users.** They've done it before on some features. Monitor announcements. If this happens, the free route builder is no longer a differentiator — lean harder on open-source maps and watch parity instead.

**Nike Run Club could add Wear OS.** NRC is free and well-resourced. If they add Wear OS support, the Android watch gap closes. The response is to be deeper on route planning and data sync — areas NRC will never prioritise.

**Map tile costs at scale.** MapTiler has a generous free tier. At scale, migrate to Protomaps (self-hosted PMTiles on S3/R2) to eliminate per-request tile costs entirely.

**Strava API rate limits at scale.** The default Strava API quota is 2,000 requests per day across all users. With many connected users this gets tight quickly. Apply for a quota increase early — Strava reviews these individually.

**Multi-modal incumbents could squeeze the niche (Phase 4 risk).** Apple Health, MyFitnessPal, and Strava could each add the missing two modalities to their stack. Apple is the most likely — Health is already the data layer, Apple Watch the capture hardware, and adding a first-class nutrition logging surface is months of work, not years. Mitigation: stay runner-led from the data shape down, so even if Apple adds nutrition, runners still need a destination that surfaces and reasons about the combined view in a runner-specific way. Stay light on lock-in (full export of every modality in standard formats) so a user who eventually defaults to Apple Health doesn't feel trapped here.

**Acquisition over build is the historical pattern in this space.** Strava acquired Runna (2025); Under Armour acquired then divested MyFitnessPal; Google acquired Fitbit and then stalled it. A specific, runner-led multi-modal product is acquisition-target shape, which is upside if priced into the plan and downside if user-trust suffers from a sale signal. No action needed today; pin once Phase 4 lights start showing real DAU.

---

*Last updated: May 2026*
