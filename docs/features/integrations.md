# Run app — data integrations

A reference for every external data source the app connects to, how each integration works, what data it provides, and the implementation approach.

---

**Contents:** [Overview](#overview) · [Apple HealthKit](#apple-healthkit) · [Android Health Connect](#android-health-connect) · [Strava](#strava) · [parkrun](#parkrun) · [Garmin Connect](#garmin-connect) · [Race results (RunSignUp + general scraping)](#race-results-runsignup--general-scraping) · [Treadmills (BLE FTMS)](#treadmills-ble-ftms) · [The `health` Flutter package](#the-health-flutter-package) · [Deduplication strategy](#deduplication-strategy)

> The Treadmills (BLE FTMS) integration has **shipped on mobile**, including the live run-screen treadmill-mode toggle. The watch (Wear OS / watchOS) BLE plumbing is the remaining follow-up.

## Overview

| Source | Type | Auth | Data | Phase |
|---|---|---|---|---|
| Apple HealthKit | On-device SDK | System permission | All iOS workouts from any app | Phase 1 |
| Android Health Connect | On-device SDK | System permission | All Android workouts from any app (read) + writes finished runs back (opt-in) | Phase 1 |
| Strava | Official REST API | OAuth 2.0 + webhook | Activities, routes, GPS streams | Phase 3 |
| parkrun | HTML scrape | Athlete number (public) | 5k times, event history | Phase 3 |
| Garmin Connect | Official developer program | OAuth 2.0 + webhook | .FIT files, HR, training data | Phase 3 |
| RunSignUp | Official REST API | API key | Race results by participant | Phase 3 |
| Race results (general) | HTML scrape | Bib number (public) | Finishing times, splits | Phase 3 |

---

## Apple HealthKit

### What it gives you

Every workout stored on iPhone or Apple Watch — regardless of which app recorded it. This includes runs from Apple Fitness, Nike Run Club, Strava, Garmin Connect mobile, and your own app. A single integration covers the entire iOS fitness ecosystem.

### How it works

HealthKit is an on-device framework. There is no server involved and no OAuth flow. The user grants permission on first launch; you then query the local HealthKit store.

```dart
// packages/core_models — shared HealthKit read logic via health package
import 'package:health/health.dart';

final health = HealthFactory();

// Request permission on first launch
final granted = await health.requestAuthorization([
  HealthDataType.WORKOUT,
  HealthDataType.HEART_RATE,
]);

// Query all running workouts in the past year
final data = await health.getHealthDataFromTypes(
  startTime: DateTime.now().subtract(const Duration(days: 365)),
  endTime: DateTime.now(),
  types: [HealthDataType.WORKOUT],
);

final runs = data
    .where((d) => d.value is WorkoutHealthValue)
    .where((d) {
      final v = d.value as WorkoutHealthValue;
      return v.workoutActivityType == HealthWorkoutActivityType.RUNNING;
    })
    .map((d) => Run.fromHealthKit(d))
    .toList();
```

### Deduplication

Runs recorded by your own app will also appear in HealthKit (because you write them there). Deduplicate using `external_id = healthkit:{uuid}` stored on the `runs` table. On import, skip any run where this `external_id` already exists.

### Platform notes

- iOS only. Android uses Health Connect (separate SDK, same `health` package).
- User can revoke permission at any time in iOS Settings → Privacy → Health.
- Background delivery (push on new workout) is available via `HKObserverQuery` but optional — polling on app open is sufficient for Phase 1.

---

## Android Health Connect

### What it gives you

The Android equivalent of HealthKit. Replaced Google Fit (which is deprecated as of 2024). Aggregates workouts from Strava, Nike Run Club, Samsung Health, Garmin Connect, and any other app that writes to Health Connect.

### How it works

Same `health` Flutter package as HealthKit — the package abstracts the platform difference behind a single Dart API.

```dart
// Identical call to HealthKit — package handles the platform switch
final data = await health.getHealthDataFromTypes(
  startTime: DateTime.now().subtract(const Duration(days: 365)),
  endTime: DateTime.now(),
  types: [HealthDataType.WORKOUT],
);
```

### Write-back (persona #36)

Read is not the only direction — Threkir also **writes finished runs back** to Health Connect so they flow on to Google Fit / Samsung Health / Fitbit / anything that reads it. `lib/health_connect_exporter.dart#writeRun` maps `metadata.activity_type` → `HealthWorkoutActivityType` and calls `health.writeWorkoutData` (an `ExerciseSessionRecord` + a `DistanceRecord`), plus best-effort heart rate (per-point chest-strap BPM from the track, else a single `metadata.avg_bpm` sample; selection in the pure `heartRateSamplesForRun`), needing the `WRITE_EXERCISE` + `WRITE_DISTANCE` + `WRITE_HEART_RATE` permissions (added to `AndroidManifest.xml` + `res/xml/health_permissions.xml`). The HR write is wrapped separately so a missing grant can't roll back the workout write. It's **opt-in per device**: off by default, toggled from Settings → Integrations (which requests the write grant and only flips the local `Preferences.writeToHealthConnect` flag if granted). When on, `run_screen` fires a best-effort, fire-and-forget `writeRun` after the local save (Android-only, never blocks the finish flow). The flag is local-only (Health Connect is an on-device capability, not a roaming account pref) and the write path is gated on `Platform.isAndroid`, so iOS/HealthKit is unaffected (HealthKit write would need separate entitlements — deferred).

### Platform notes

- Health Connect comes pre-installed on Android 14+. On Android 9–13, users must install it from the Play Store. Show a prompt if the package is not found.
- Samsung Health writes to Health Connect on Galaxy devices running One UI 6+.
- Garmin Connect writes to Health Connect when the Garmin Connect app is installed.

---

## Strava

### What it gives you

All activities the user has recorded on Strava — including those synced from Garmin, Apple Watch, and other devices. GPS streams, HR data, splits, and segment efforts.

### Auth flow (web, shipped)

Strava uses standard OAuth 2.0. Access tokens expire every 6 hours; refresh tokens are long-lived. Hourly token rotation has migrated to the Go worker (`kind='token_refresh'` in `apps/job_worker/internal/handler_token_refresh.go`, enqueued by the pg_cron schedule in migration `20260821_001_token_refresh_cron.sql`); the scheduled `refresh-tokens` Edge Function stays deployed as a rollback path until the operator cutover completes. `strava-import` (still an Edge Function) also does an on-demand refresh when a `sync` action finds the stored token inside its expiry window.

```
1. User clicks "Connect" next to Strava on /settings/integrations
2. Browser redirected to:
     https://www.strava.com/oauth/authorize
       ?client_id={PUBLIC_STRAVA_CLIENT_ID}
       &response_type=code
       &redirect_uri={origin}/settings/integrations
       &approval_prompt=auto
       &scope=activity:read_all,read
3. User approves on Strava
4. Strava redirects back to /settings/integrations?code=...&scope=...
5. Web calls `supabase.functions.invoke('strava-import', { action: 'connect', code, scope })`
6. Edge Function exchanges code for tokens, stores in `integrations`,
   and triggers an immediate 90-day backfill
7. Subsequent "Sync now" button on the integrations card calls
   `invoke('strava-import', { action: 'sync', lookbackDays })`
```

Web env vars:
- `PUBLIC_STRAVA_CLIENT_ID` — public client ID baked into the OAuth URL.
- `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET` — Edge Function only.

### Auth flow (mobile, shipped)

Native in-app OAuth via `flutter_web_auth_2` — Chrome Custom Tabs on Android, `ASWebAuthenticationSession` on iOS. The mobile flow ends up at the same `strava-import` Edge Function as web; only the OAuth round-trip differs. The user never leaves the app and never sees a browser tab.

```
1. User taps Strava tile in Settings → Integrations.
2. `_connectStrava` (settings_integrations_screen.dart) builds the same /oauth/authorize
   URL via `stravaAuthUrl(redirectUri)` in `lib/strava.dart`. Redirect URI
   uses the `threkir://strava-callback` custom scheme.
3. `WebAuth.authenticate(url)` opens Chrome Custom Tabs (Android) or
   ASWebAuthenticationSession (iOS); user approves on Strava.
4. The custom-scheme redirect lands back in the app; the session closes
   and returns the callback URL.
5. `parseStravaCallback` extracts code + scope; `ApiClient.completeStravaOAuth`
   POSTs to `strava-import` with `action: 'connect'` — same code-for-token
   exchange + 90-day backfill as web.
6. "Sync now" tile calls `ApiClient.syncStrava` (`action: 'sync'`).
   "Disconnect" deletes the integrations row.
```

Operational pre-requisites:
- The `threkir://strava-callback` URI must be allow-listed in the Strava developer console **and** in `STRAVA_ALLOWED_REDIRECTS` on the Edge Function.
- Falls back to the web browser hand-off on builds where the client ID is unconfigured (matches the existing `url_launcher` path used before native OAuth shipped).
- `lib/strava.dart` mirrors `apps/web/src/lib/integrations/strava.ts` and is unit-tested (16 tests in `test/strava_test.dart` on URL building + callback parsing + configured-state checks).

### Webhook (real-time sync)

Register once per app (not per user). Strava pushes a notification within seconds of a user creating, updating, or deleting an activity.

Webhook handling has migrated to the Go worker: `apps/job_worker/internal/stravahook/server.go` (POST `/v1/strava/webhook`) validates the URL secret + verify-token + freshness, dedupes via `webhook_events`, and enqueues a `kind='strava_event'` job that the worker drains asynchronously (`internal/handler_strava_event.go`) — matching Strava's "ack within 2s" requirement, which the old synchronous Edge Function regularly missed on a cold activity-detail fetch. The deprecated Edge Function `apps/backend/supabase/functions/strava-webhook/index.ts` stays deployed as a rollback path until the operator repoints Strava's `push_subscriptions` URL. Both paths share the ingest helpers in `apps/backend/supabase/functions/_shared/strava.ts` / the Go equivalents and the `webhook_events` dedupe table. Sketch of the (Edge Function) flow — auth, retries, refresh, sport-type filtering elided; read the source for the full version:

```typescript
// 1. URL-secret guard (Strava doesn't sign POSTs)
const secret = new URL(req.url).searchParams.get('secret');
if (secret !== Deno.env.get('STRAVA_WEBHOOK_SECRET')) return new Response('forbidden', {status: 403});

const { object_type, object_id, aspect_type, owner_id } = await req.json();
if (object_type !== 'activity') return new Response('OK');           // ack non-run events
if (aspect_type !== 'create' && aspect_type !== 'update') return new Response('OK');

// 2. Service-role client (the webhook isn't a user request)
const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// 3. Look up the integration WITHOUT joining secrets — tokens live in Vault
const { data: integration } = await supabase
  .from('integrations').select('user_id')
  .eq('provider', 'strava').eq('external_id', String(owner_id))
  .single();
if (!integration) return new Response('OK');                          // unknown athlete: ack and drop

// 4. Dedupe before refresh — repeated webhooks are common
if (await isAlreadyImported(supabase, integration.user_id, object_id)) return new Response('OK');

// 5. Fetch tokens from Vault; refresh if within 5 min of expiry
let { accessToken, expiresAt } = await getTokens(supabase, integration.user_id);
if (expiresAt - Date.now() < 5 * 60_000) ({accessToken} = await refreshStravaToken(supabase, integration.user_id));

// 6. Fetch + filter + ingest via the same code path as backfill
const activity = await fetchStravaActivity(accessToken, object_id);
if (!isRunOrWalkOrHike(activity.sport_type)) return new Response('OK');
await ingestActivity(supabase, integration.user_id, accessToken, activity);

// 7. ALWAYS 200 — Strava retries on non-2xx and a retry storm would re-trigger ingest
return new Response('OK');
```

Important properties of the real implementation:

- **Always 200 on the success and the swallow paths.** Returning 5xx invites Strava's retry policy (~5 retries over an hour); since the function de-dupes on `metadata.strava_id`, a retry just costs us a token refresh + a fetch. We log to Sentry via `withSentry` instead.
- **Tokens live in Vault** (decisions §41). The integration row exposes `user_id` + `external_id` + `scope`; the actual `access_token` / `refresh_token` go through `get_integration_tokens` / `set_integration_tokens` SECURITY DEFINER RPCs.
- **Dedupe key is `metadata.strava_id`** (jsonb), not a column, not `external_id`. The shared `isAlreadyImported` helper checks both the legacy `external_id LIKE 'strava:%'` shape and the metadata shape so historic and current rows both block re-ingestion.
- **Sport-type filter narrows to run / walk / hike.** A user's bike ride or swim is acknowledged but not ingested.

### Key endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/athlete/activities` | GET | Backfill historical activities (paginated) |
| `/activities/{id}` | GET | Full activity detail (splits, gear, HR) |
| `/activities/{id}/streams` | GET | Raw GPS track, altitude, HR timeseries |
| `/push_subscriptions` | POST | Register webhook endpoint |
| `/oauth/token` | POST | Exchange auth code or refresh token |

### Rate limits

- 200 requests per 15 minutes
- 2,000 requests per day
- Per-app limits, not per-user — plan the backfill carefully (batch across users)
- Request a quota increase via Strava developer portal once you have active users

### Data mapping

```typescript
function toRun(activity: StravaActivity, stream: StravaStream, userId: string): Run {
  return {
    id: crypto.randomUUID(),
    user_id: userId,
    started_at: activity.start_date,
    duration_s: activity.elapsed_time,
    distance_m: activity.distance,
    track: decodePolyline(stream.latlng),   // Google encoded polyline → [{lat, lng}]
    source: 'strava',
    external_id: `strava:${activity.id}`,
  };
}
```

---

## parkrun

### What it gives you

A runner's complete parkrun history — every 5k time, event location, position, and age grade percentage.

### How it works

parkrun has no official public API. Results are scraped from their public HTML results pages using the athlete's public ID number (e.g. `A123456`). No password or OAuth required — results are publicly accessible.

```
User enters athlete number: A123456
  → Edge Function fetches:
    https://www.parkrun.org.uk/results/athleteresultshistory/?athleteNumber=A123456
  → Parse HTML <table> with Cheerio
  → Extract rows: event name, date, run number, time, position, age grade
  → Map to Run objects with source='parkrun'
  → Upsert, deduplicating on external_id = 'parkrun:{event}:{date}'
```

### Edge Function

```typescript
// apps/backend/supabase/functions/parkrun-import/index.ts
import * as cheerio from 'cheerio';

export async function POST(req: Request) {
  const { athleteNumber, userId } = await req.json();

  const url = `https://www.parkrun.org.uk/results/athleteresultshistory/?athleteNumber=${athleteNumber}`;
  const html = await fetch(url).then(r => r.text());
  const $ = cheerio.load(html);

  const runs: Run[] = [];
  $('table tbody tr').each((_, row) => {
    const cells = $(row).find('td');
    runs.push({
      id: crypto.randomUUID(),
      user_id: userId,
      started_at: parseDate($(cells[0]).text()),   // e.g. "05/04/2025"
      duration_s: parseTime($(cells[4]).text()),   // e.g. "24:31"
      distance_m: 5000,                            // always 5k
      source: 'parkrun',
      external_id: `parkrun:${$(cells[1]).text()}:${$(cells[0]).text()}`,
      metadata: {
        event: $(cells[1]).text(),                 // e.g. "Richmond"
        position: parseInt($(cells[5]).text()),
        age_grade: $(cells[6]).text(),             // e.g. "54.23%"
        run_number: parseInt($(cells[2]).text()),  // user's nth parkrun
      },
    });
  });

  await supabase.from('runs').upsert(runs, { onConflict: 'external_id' });
  return Response.json({ imported: runs.length });
}
```

### Fragility warning

parkrun can change their HTML structure without notice. This scraper will silently return zero results if the table format changes. Mitigations:

- Store the raw HTML in Supabase Storage on each import (for debugging)
- Alert if imported count drops to zero unexpectedly
- Build graceful degradation into the UI — show "parkrun sync unavailable" rather than an error
- The importer skips any scraped row that doesn't yield BOTH a valid finish time and a valid calendar date (`isUsableParkrunResult` in `parkrun-import/lib.ts`). This drops sub-header / footer rows and `--:--` assisted/unknown times, so one junk row can neither fail the whole batch on an unparseable `started_at` nor import a corrupt 5000 m / 0 s run.

### Finding athlete numbers

Every parkrun participant has a public athlete page at `parkrun.org.uk/parkrunner/{number}`. Users can find their number from their parkrun barcode or results email. Display a link to `parkrun.org.uk/register/` for users who don't know their number.

---

## Garmin Connect

### What it gives you

Full .FIT files from every Garmin device sync — the richest data format in the running world (every sensor, every data field, cadence, ground contact time, vertical oscillation, power).

### Access requirements

Garmin Connect requires **business approval** before granting API access. This is not a self-service integration.

1. Apply at `developer.garmin.com/gc-developer-program`
2. Garmin reviews within 2 business days
3. On approval: access to evaluation environment
4. Integration call with Garmin team before production access

**Do not block roadmap on this.** For Phase 3 launch, route Garmin data through HealthKit/Health Connect — the Garmin Connect mobile app writes to both on iOS and Android. Full Garmin API integration is a post-launch enhancement.

### Auth flow (when approved)

OAuth 2.0, identical pattern to Strava.

```typescript
// Same Edge Function pattern as Strava
// OAuth callback → token exchange → store in integrations table → webhook registered
```

### Available APIs

| API | Purpose |
|---|---|
| Activity API | .FIT, GPX, TCX files per activity |
| Health API | Steps, HR, sleep, stress, HRV (all-day metrics) |
| Training API | Push workouts and plans to Garmin devices |
| Courses API | Push routes to Garmin devices for navigation |

### Interim approach (pre-approval)

Two paths today, both unblocked:

**Web — bulk FIT import.** `/settings/integrations` ships a "Bulk import from a Garmin export" card that accepts either a single `.fit` file (Garmin Connect → activity → "Export Original") or the full `.zip` from `Garmin → Account Management → Request Your Data`. Implementation in `apps/web/src/lib/integrations/garmin-zip.ts` + `garmin-fit.ts`; FIT decoding uses `fit-file-parser` and is dynamic-imported so the binary decoder is only fetched when a user picks a file. Dedupes within a single import on the FIT `file_id` message (`time_created-serial_number`) with a `started_at|distance_m` composite fallback for `.gpx` / `.tcx` originals inside the bundle. Across imports, the FIT path also persists `runs.external_id = garmin:{file_id}` (via `garminExternalId`) so a later re-import — or a future Garmin OAuth path — is blocked by the per-user `external_id` unique index, not just the in-session set (#18). The importer also preserves `metadata.sub_sport` (trail / treadmill / track), `metadata.running_dynamics` (vertical oscillation / GCT / stride / power — both surfaced on run-detail), and one-time seeds `user_settings.prefs.hr_zones` from the FIT `hr_zone` messages (via `buildHrZonesFromFit`) **only when the user has no zones set** — it never clobbers a configured set.

**Mobile — HealthKit / Health Connect.** Garmin Connect mobile app syncs to HealthKit (iOS) and Health Connect (Android) automatically. Users who install Garmin Connect alongside your app will have their Garmin runs available via the HealthKit/Health Connect import with no extra work. The Health Connect import also reads the user's latest body-weight sample (`HealthConnectImporter.fetchLatestWeightKg`) and one-time seeds `user_settings.prefs.body_weight_kg` when the user hasn't set one — so the calorie estimate uses a real weight instead of the 70 kg fallback (persona round-5 samsung-watch). It never overwrites an existing weight.

---

## Race results (RunSignUp + general scraping)

> **Status: shipped (2026-06-20, migration `20270214_001`, race_calendar.md).** The race calendar (`race_listings`) + the `race-results-import` / `race-listings-sync` Edge Functions + the auto-match-on-record seam are live on web (`/races`, run-detail) and mobile (`RacesScreen`, run-detail). The **RunSignUp leg is prod-gated, fail-closed**: with `RUNSIGNUP_API_KEY`/`RUNSIGNUP_API_SECRET` unset (the dev/CI default) both EFs return `503 provider_not_configured` and the UI shows the unavailable explainer — provisioning the key on the deployed project is the only remaining go-live step (record it on the deploy checklist). The **ChronoTrack leg is prod-gated, fail-closed** the same way: with `CHRONOTRACK_CLIENT_ID`/`CHRONOTRACK_USER_ID`/`CHRONOTRACK_PASSWORD` unset (the dev/CI default) the `chronotrack` import branch + the `provider:'chronotrack', probe:true` availability probe both return `503 provider_not_configured` and the Settings card shows the unavailable explainer — provisioning the three CTLive credentials is the only remaining go-live step. **parkrun** stays the shipped scraper; **manual paste** is the durable non-API path for every other timing platform. RaceResult / UltraSignup per-site scrapers remain scoped follow-ups — the URL-pattern table below is the reference for when one is built, not a description of shipped behaviour. See [decisions.md § 168](../architecture/decisions.md#168-race-results-live-on-the-runs-row-sourcerace-a-public-race_listings-calendar-is-its-own-table-and-auto-match-on-record-is-an-inform-tier-layered-resilience-wrapped-post-save-check) + [§ 178](../architecture/decisions.md).

### RunSignUp

RunSignUp powers a large portion of US road races and has an official REST API. The shipped importer calls the results endpoint server-side from `race-results-import/index.ts` (key from the Edge-only `RUNSIGNUP_API_KEY`/`_SECRET` env), maps each finisher through `lib.ts` (`mapRunSignUpResult` → a `source='race'` run with `external_id=race:{name}:{date}:{bib}` + the owner-only race metadata), and upserts with per-user `external_id` dedup. Until the key is provisioned the leg is inert (503).

```
GET https://runsignup.com/Rest/race/{race_id}/results/get-results
  ?format=json
  &tmp_key={API_KEY}
  &user_id={USER_ID}    ← user's RunSignUp account ID
```

Returns: finish time, gun time, chip time, age group place, overall place, splits.

Users connect their RunSignUp account via OAuth, then you can query their race history automatically.

### ChronoTrack

ChronoTrack times many US majors and large road events and exposes the ChronoTrack Live (CTLive) REST API. The shipped importer calls the results endpoint server-side from `race-results-import/index.ts` behind the `provider:'chronotrack'` branch (credentials from the Edge-only `CHRONOTRACK_CLIENT_ID` / `CHRONOTRACK_USER_ID` / `CHRONOTRACK_PASSWORD` env), maps each finisher through `lib.ts` (`mapChronoTrackResult`, which delegates to the same `mapRunSignUpResult` shaping → an identical `source='race'` run with `external_id=race:{name}:{date}:{bib}` + the owner-only race metadata), and dedupes per-user on `external_id` exactly like the RunSignUp + paste paths. Until all three credentials are provisioned the leg is inert (`503 provider_not_configured`).

```
GET https://api.chronotrack.com/api/event/{event_id}/results
  ?format=json
  &client_id={CLIENT_ID}
  &user_id={USER_ID}      ← CTLive account
  &user_pass={PASSWORD}   ← CTLive account password
  &bib={BIB}              ← optional: filter to one finisher
```

Returns: bib, net (chip) time, gun time, overall rank, division (age-group) rank, division label — mapped onto the same race metadata keys the other providers write. The listing's `provider_race_id` carries the ChronoTrack `event_id`. CTLive results are nested under `event_results[]` (the extractor tolerates a top-level `results[]` too) and capped at `MAX_RESULTS_ROWS`.

### General race results scraping

For races not on RunSignUp (ChronoTrack, RaceResult, local timing systems):

```
User workflow:
  1. User pastes their result URL or enters bib number + race name
  2. Edge Function fetches the results page
  3. Parse finishing time and splits from HTML table
  4. Import as Run with source='race', distance from race metadata
```

Common timing platforms and their URL patterns:

| Platform | Powers | Result URL pattern |
|---|---|---|
| ChronoTrack | Many majors (Chicago, Boston qualifier events) | `results.chronotrack.com/r/...` |
| RaceResult | European races, some US | `my.raceresult.com/...` |
| UltraSignup | Trail + ultra events | `ultrasignup.com/results_athlete.aspx?uid=...` |
| FindMyMarathon | Large marathon aggregator | `findmymarathon.com/results/...` |

### Data mapping for race runs

```typescript
{
  source: 'race',
  distance_m: raceDistanceMetres,    // from race metadata (5000, 10000, 21097, 42195)
  duration_s: chipTimeSeconds,
  metadata: {
    race_name: 'Richmond Half Marathon',
    race_date: '2025-09-21',
    bib: '1234',
    overall_place: 142,
    age_group_place: 12,
    age_group: 'M35-39',
    chip_time: '1:47:23',
    gun_time: '1:48:01',
  }
}
```

---

## Treadmills (BLE FTMS)

**Status:** **shipped on mobile** (Android + the byte-identical iOS twin; iOS unverified on Mac runtime per [decisions.md § 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)), now including the **live run-screen treadmill-mode toggle** (`run_screen.dart` `_toggleTreadmillMode`, gated on a paired belt, L4 opt-in; the belt is the app-owned `BleTreadmill` singleton paired in Settings and read by the run screen, mirroring the HR strap — see [treadmill_live_mode.md](treadmill_live_mode.md)). Web is N/A: it's the canonical *feature* surface, not a recording surface ([decisions.md § 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). Matches the `parity.md` Treadmill row and roadmap item 13.

### What it gives you

A real-time speed / distance stream from the treadmill itself, replacing the GPS-derived numbers that don't exist on a treadmill. The indoor fallback path is `pedometer × stride` distance (`distance_source = "pedometer"`, `indoor_estimated = true` — see [docs/backend/metadata.md](../backend/metadata.md) and [docs/features/run_recording.md § Layering](run_recording.md#layering) layer 14); a paired treadmill replaces that estimate with the authoritative belt distance.

### How it works

The Bluetooth SIG **Fitness Machine Service (FTMS, `0x1826`)** is the standardised GATT profile for cardio equipment. The Treadmill Data characteristic (`0x2ACD`) emits a notification every ~1 s carrying instantaneous speed (uint16, 0.01 km/h), instantaneous pace (uint16, 0.1 s/km), total distance (uint24, m), inclination (sint16, 0.1 %), elevation gain (uint16, 0.1 m), and optional cadence / HR / energy fields gated by the leading flags bitfield. There is also an FTMS Control Point (`0x2AD9`) for write-back commands (start, stop, set speed, set incline) — the read path is what shipped; control is a follow-up.

The mobile implementation mirrors the existing BLE chest-strap pattern in `apps/mobile_android/lib/ble_heart_rate.dart`:

1. **BLE backend:** `flutter_reactive_ble` — the same backend the HR reader uses (**not** `flutter_blue_plus`).
2. **Reader module:** `apps/mobile_android/lib/ble_treadmill.dart` exposes a `Stream<TreadmillSample>` (`BleTreadmill`). The pure `parseTreadmillData(raw)` function decodes the FTMS `0x2ACD` payload per its leading flags bitfield, and `statusStream` surfaces a `BleTreadmillStatus` (`disconnected` / `connecting` / `connected` / `reconnecting` / `connectFailed`) with backoff auto-reconnect after a working connection drops — mirroring the HR reader's reconnect contract. ~20 unit tests in `apps/mobile_android/test/ble_treadmill_test.dart`.
3. **Settings tile:** `TreadmillTile` in `apps/mobile_android/lib/screens/settings_integrations_screen.dart` (Settings → Integrations) runs an FTMS-filtered scan, lets the user pick a device, and pairs it. It takes the app-owned `BleTreadmill` **singleton** (constructed in `main.dart`, `connectCached` kicked at startup, threaded through `HomeScreen` → `YouScreen` → `SettingsScreen` → integrations, mirroring the HR strap) so the belt paired here is the same instance the run screen reads — no second GATT client. The paired belt's id + name persist to the reader's **own `SharedPreferences` keys** (`treadmill_device_id` / `treadmill_device_name`), **not** `user_device_settings.prefs` — pairing is an on-device capability that doesn't roam (same reasoning as the Health Connect write-back flag), so subsequent sessions auto-reconnect silently.
4. **Recorder seam:** `packages/run_recorder/lib/src/run_recorder.dart` exposes an additive opt-in seam — `setTreadmillSample(speedMps, {totalDistanceMetres})` flips the recorder into treadmill mode (belt distance overrides the GPS-accumulated headline distance), and `clearTreadmillMode()` reverts to the GPS path. Belt distance only influences a run while treadmill mode is on; the GPS L0/L1 + auto-pause path is untouched, paused belt-advance is excluded, and a dropped BLE link falls back to the L0 clock. On `stop()` the recorder writes `metadata['indoor_source'] = 'treadmill'` (and `metadata['distance_source'] = 'treadmill'`).
5. **Metadata flag:** `metadata.indoor_source = "treadmill"` sits alongside the existing `indoor_estimated` / `distance_source` keys; no new union. Registered in [docs/backend/metadata.md](../backend/metadata.md).
6. Map / off-route / privacy-zone surfaces are skipped automatically because the run carries no track points — the same code path indoor pedometer runs already use.
7. **Run-screen toggle:** `run_screen.dart` `_toggleTreadmillMode` renders a `SwitchListTile` over the recording view, gated on a paired belt (`pairedName()`). Turning it on subscribes the belt `stream` and pumps each sample into `setTreadmillSample`; turning it off cancels and calls `clearTreadmillMode`. It's an **L4 opt-in** — the subscription + recorder calls each carry their own try/catch + `debugPrint`, a fault shows a banner and reverts the toggle, and the L0 clock / L1 distance path is never disturbed. The belt's `statusStream` drives drop/reconnect disclosure banners (mirroring the HR strap), and `connectFailed` offers a one-tap reconnect. The toggle is off by default and never auto-engages, so a belt in range can't hijack an outdoor GPS run. See [treadmill_live_mode.md](treadmill_live_mode.md).

**Still deferred:** the watch (Wear OS / watchOS) BLE plumbing — Wear OS has its own `BluetoothGatt` API and Apple Watch can pair FTMS via `CBCentralManager`; watch pairing is downstream of phone pairing, not a parallel item.

### The catch

FTMS coverage is roughly **60 % of the consumer treadmill market**. The big-brand exceptions all run proprietary protocols:

- **Peloton Tread** — proprietary, not BLE-advertised at all in Tread+; reverse-engineered libraries exist but break across firmware updates.
- **NordicTrack / iFit** — iFit-app-only, no public BLE service.
- **Echelon Stride** — proprietary characteristic UUIDs, partially reverse-engineered.
- **Older Life Fitness / Precor** — pre-FTMS, often expose nothing or a vendor-specific service.

Standards-compliant: most newer Sole, Horizon, Bowflex, Matrix, Reebok, Schwinn, plus most commercial gym fleets shipped post-~2020. A v1 that only promises FTMS will work for ~60 % of users and present a clear "we couldn't read this treadmill — your run will fall back to pedometer distance" banner for the rest. Per-vendor integrations are out of scope for v1; if the user base concentrates on a specific brand, treat that as a separate scoped follow-up.

### Schema impact

Minimal — and no migration was needed:

- Paired-belt identity lives in the reader's own on-device `SharedPreferences` keys (`treadmill_device_id` / `treadmill_device_name`), not the database — pairing doesn't roam.
- `runs.metadata.indoor_source: "treadmill"` — registered in [docs/backend/metadata.md](../backend/metadata.md). No CHECK constraint needed (metadata is unschemaed).

No new table; no narrow union to update; no codegen pass needed.

---

## Course export to a watch (GPX with course markers)

A route's course markers (aid stations, cutoffs, crew access, hazards) only
matter when the runner is on a watch mid-race with no phone. The
**GPX-with-course-markers** export bridges that: it emits the route line as a
`<trk>` **plus one `<wpt>` per marker**, so a Garmin/Coros/Suunto (and
eventually the `custom_watch`) surfaces "Aid 2 in 1.3 km" on the wrist. GPX is
imported by every device, so this is the universal first cut. (FIT *Course*
export with native `CoursePoint` records is the deferred v2 — see
[course_waypoint_export.md](course_waypoint_export.md).)

Each `<wpt>` carries the marker's `<name>`, its `<type>` (the raw
`RouteMarkerKind`), a Garmin-recognised `<sym>` where one maps
(`aid_station` → `Water Source`; `cutoff`/`hazard` → `Danger Area`;
`crew_access` → `Parking Area`; `note` → `Information`; `climb` → `Summit`;
`custom` → none), and a `<desc>` holding the cutoff time and the aid-station
services. Waypoints are emitted before the `<trk>` per the GPX 1.1 schema and
the exported markers are **privacy-clipped** (in-privacy-zone pins are
redacted, same as the on-screen pins).

Pure emitter: `apps/web/src/lib/routes/route_gpx.ts`
(`toRouteGpxWithMarkers`) ↔ `apps/mobile_android/lib/route_gpx.dart`
(`routeGpxFromRoute`, iOS twin), a TS↔Dart parity pair. Surfaces: the
**"GPX + markers"** download on `/routes/[id]` + `/routes/[id]/roadbook`
(web, shown only when the route has ≥1 marker) and the **"Share as GPX +
markers"** route-detail action on mobile. Distinct from the plain
[GPX route export](features.md#gpx--kml-import) (line only, no waypoints),
which both still offer.

---

## The `health` Flutter package

The single most important integration library in the stack. One Dart package abstracts both Apple HealthKit (iOS) and Android Health Connect behind an identical API.

```yaml
# apps/mobile_android/pubspec.yaml
dependencies:
  health: ^13.0.0
```

### Permissions required

**iOS** — add to `Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>Read your running workouts to display them alongside your planned routes.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Save your runs to Apple Health.</string>
```

**Android** — add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.health.READ_EXERCISE"/>
<uses-permission android:name="android.permission.health.READ_DISTANCE"/>
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.WRITE_EXERCISE"/>
<uses-permission android:name="android.permission.health.WRITE_DISTANCE"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
```

---

## Deduplication strategy

Runs can arrive from multiple sources simultaneously (e.g. a Garmin run syncs via HealthKit AND via the Garmin Connect API). The `external_id` column on the `runs` table prevents duplicates.

| Source | `external_id` format |
|---|---|
| Recorded in app | `app:{uuid}` |
| Apple HealthKit | `healthkit:{hk-uuid}` |
| Android Health Connect | `healthconnect:{hc-uuid}` |
| Strava | `strava:{activity-id}` |
| Garmin Connect | `garmin:{activity-id}` |
| parkrun | `parkrun:{event-name}:{date}` |
| Race results | `race:{race-name}:{date}:{bib}` |

All upserts use `ON CONFLICT (external_id) DO NOTHING` — the first-written record wins, subsequent duplicates are silently ignored.

---

*Last updated: 2026-06-14*
