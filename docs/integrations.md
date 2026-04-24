# Run app — data integrations

A reference for every external data source the app connects to, how each integration works, what data it provides, and the implementation approach.

---

## Overview

| Source | Type | Auth | Data | Phase |
|---|---|---|---|---|
| Apple HealthKit | On-device SDK | System permission | All iOS workouts from any app | Phase 1 |
| Android Health Connect | On-device SDK | System permission | All Android workouts from any app | Phase 1 |
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

### Platform notes

- Health Connect comes pre-installed on Android 14+. On Android 9–13, users must install it from the Play Store. Show a prompt if the package is not found.
- Samsung Health writes to Health Connect on Galaxy devices running One UI 6+.
- Garmin Connect writes to Health Connect when the Garmin Connect app is installed.

---

## Strava

### What it gives you

All activities the user has recorded on Strava — including those synced from Garmin, Apple Watch, and other devices. GPS streams, HR data, splits, and segment efforts.

### Auth flow (web, shipped)

Strava uses standard OAuth 2.0. Access tokens expire every 6 hours; refresh tokens are long-lived. The scheduled `refresh-tokens` Edge Function rotates them hourly; `strava-import` also does an on-demand refresh when a `sync` action finds the stored token inside its expiry window.

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

### Webhook (real-time sync)

Register once per app (not per user). Strava pushes a notification within seconds of a user creating, updating, or deleting an activity.

```typescript
// apps/backend/functions/strava-webhook/index.ts
// POST — Strava sends this on every activity event
export async function POST(req: Request) {
  const { object_type, object_id, aspect_type, owner_id } = await req.json();

  if (object_type !== 'activity' || aspect_type !== 'create') return ok();

  // Look up user by Strava athlete ID
  const { data: integration } = await supabase
    .from('integrations')
    .select('user_id, access_token')
    .eq('provider', 'strava')
    .eq('external_id', String(owner_id))
    .single();

  // Fetch full activity from Strava
  const activity = await stravaGet(`/activities/${object_id}`, integration.access_token);
  const stream = await stravaGet(`/activities/${object_id}/streams?keys=latlng,altitude,time`, integration.access_token);

  // Map to Run and upsert
  await supabase.from('runs').upsert(toRun(activity, stream, integration.user_id));
}
```

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
// apps/backend/functions/parkrun-import/index.ts
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

Garmin Connect mobile app syncs to HealthKit (iOS) and Health Connect (Android) automatically. Users who install Garmin Connect alongside your app will have their Garmin runs available via the HealthKit/Health Connect import with no extra work.

---

## Race results (RunSignUp + general scraping)

### RunSignUp

RunSignUp powers a large portion of US road races and has an official REST API.

```
GET https://runsignup.com/Rest/race/{race_id}/results/get-results
  ?format=json
  &tmp_key={API_KEY}
  &user_id={USER_ID}    ← user's RunSignUp account ID
```

Returns: finish time, gun time, chip time, age group place, overall place, splits.

Users connect their RunSignUp account via OAuth, then you can query their race history automatically.

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

## The `health` Flutter package

The single most important integration library in the stack. One Dart package abstracts both Apple HealthKit (iOS) and Android Health Connect behind an identical API.

```yaml
# packages/core_models/pubspec.yaml
dependencies:
  health: ^10.0.0
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
<uses-permission android:name="android.permission.health.WRITE_EXERCISE"/>
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

*Last updated: April 2026*
