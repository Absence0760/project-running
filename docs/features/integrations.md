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

### What an imported workout carries

A session's **summary** (start, duration, distance, type) always imports. Three things ride alongside it, each conditional and each degrading to absence rather than to a wrong value:

- **The GPS route** (`READ_EXERCISE_ROUTES`, #664). An `ExerciseSessionRecord` may carry an `ExerciseRoute`, but reading one written by *another* app needs that grant on top of the session read, and Health Connect withholds it from a background read even when it is held. The plugin renders the refusal as a `WORKOUT_ROUTE` point with **zero locations** and emits nothing at all for a session that genuinely has no route — so an empty point means "there is a route here you may not read", which is the only state worth offering the grant for. `HealthConnectImporter.fetchRoutes` separates the two into `tracks` + `withheldSessionIds`, and carries `readFailure` so a read that *threw* is not reported as a source holding no routes. The grant is asked for only on an explicit tap (never chained onto the import's own permission sheet), via the `HealthRoutePermissionBridge` method channel — the `health` plugin maps route *reads* onto the session read permission alone, so the grant is otherwise unreachable from outside the Health Connect app. Granting it later runs `runsWithBackfilledTracks` over the already-imported runs, because a Health Connect re-import is suppressed by `isCrossSourceDuplicate` and would never reach them.
- **The step count** (`READ_STEPS`, #664). Health Connect has no per-session step field: the plugin builds a workout's `totalSteps` by summing every `StepsRecord` overlapping the session window, whoever wrote it. Without the grant that sub-read yields nothing and the field is always null. `stepsForWorkout` screens what arrives — `cycle` is excluded (the phone counts pocket jostle, and run-detail divides whatever is stored by moving time and calls the result spm), and a count implying a cadence past 300 spm is a foreign record summed into the window rather than a step count. It writes `metadata.steps` and **no** `cadence_spm`: steps is the fact, and the existing `steps / moving_time_minutes` fallback shared by `run_detail_screen.dart` and web's `avgCadence` is the single place that derives a cadence from it.
- **Average heart rate**, meaned over the session window from `HEART_RATE` samples, clamped to 30–230 bpm.

**Laps are not reachable.** `ExerciseSessionRecord` carries `laps` and `segments`, but the `health` package surfaces them only on the **write** path (`HealthDataWriter.kt` preserves them across an update); there is no read binding and no `HealthDataType` for them, so an imported multi-lap session flattens to one interval. Closing that needs a lap read of our own alongside `HealthRoutePermissionBridge`, or an upstream change — filed, not built.

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

### What a sync is allowed to claim

The backfill walks Strava's activity pages until it reaches the end of the lookback window, and has **seven** exits. Five of them leave activities in the window unfetched: Strava throttling us (429/503), an upstream error, a **transport failure** (`fetch` rejecting on DNS / TLS / a dropped connection, or `resp.json()` on an HTML error page from anything in front of Strava), a page body that is JSON but not an array, and the 20-page / 1000-activity safety cap. Only the throttle case ever carried a field — `rate_limited` — and neither client declared it, so all of them rendered as a finished sync ([decisions § 766](../architecture/decisions.md)). The transport pair was worse still: it escaped `backfill` entirely, was answered as a 500 `internal_error`, and **discarded every count the walk had earned** ([decisions § 768](../architecture/decisions.md)).

So `backfill` returns `complete` alongside the counts, raised only on the two end-of-window exits, and `last_sync_at` is stamped only when it is true — a truncated walk leaves the previous, true timestamp rather than claiming the tile just synced. Both clients grade the response through the `strava_sync_result` parity pair (`apps/web/src/lib/integrations/strava_sync_result.ts` ↔ `packages/core_models/lib/src/strava_sync_result.dart`) rather than casting it: only an explicit `complete: true` earns the success copy, and an unrecognised shape, an absent field or an embedded `error` reads as partial. The rate-limited case keeps its own sentence because it is the one cause a runner can act on (wait ~15 minutes) rather than merely retry.

### Resuming a truncated walk

`after=` used to be derived from `Date.now() - lookbackDays` on every call, with `integrations.sync_cursor` written by nothing, so a re-sync re-walked the same window from page 1 — and for the one runner the 20-page cap can reach, "sync again to finish" was an instruction that could never succeed. **A truncated walk now records the window still to walk on `integrations.sync_cursor`** and the next sync resumes it ([decisions § 768](../architecture/decisions.md)).

The cursor is `{"v":1,"from":<epoch s>,"after":<epoch s>,"before":<epoch s|null>}`, and each part is load-bearing:

- **`from`** is the oldest instant the JOB covers, not the oldest still to fetch. `after=` is recomputed from the clock on every call, so it is never equal to the one the previous walk used; a resume test against the frontier alone refuses every same-lookback re-sync there is. A stored cursor is honoured only when the caller's requested floor does not reach further back than `from` — a runner widening `lookbackDays` is asking a question the cursor's window does not answer, and the wider walk subsumes the cursor's remainder anyway.
- **`after` / `before`** bound the remainder. Which end moves depends on the walk direction, which is **measured off the page** rather than assumed: Strava returns the activity list oldest-first when `after` is set and newest-first otherwise. Oldest-first moves the floor up to the newest activity seen; newest-first moves the ceiling down to the oldest.
- A cursor that would not narrow the window is **not written** — a resume making no progress would loop a runner between two syncs forever. A truncation that got nowhere (throttled on page 1) therefore writes nothing, leaving a cursor it could not advance intact for the next attempt.
- A **finished** window clears the cursor and stamps `last_sync_at` in the same update; `connect` and `disconnect` clear it too, so a fresh grant never resumes a window measured against another athlete's list.

The response carries `resumable`, which is what lets a client say "syncing again picks up where it stopped" only when that is true. It is fail-closed like `complete` and never true alongside it.

### Choosing how far back to sync

The Edge Function has always accepted `lookbackDays` up to 365, and until 2026-08-28 **no caller passed anything** — web's `syncStrava(lookbackDays = 90)` and `ApiClient.syncStrava` both defaulted and were both called bare. A runner who dismissed "sync complete" and came back four months later could not reach the missed activities from the app at all; the bulk export below was the only remaining path. Both clients now offer the window: web as a select beside **Sync now** on the connected Strava card, mobile as a **Sync older history…** item in the tile's menu opening a picker. The three windows (90 days / 6 months / a year) and the maximum live in the `strava_sync_result` parity pair, and a guard pins the maximum to the `400 invalid_lookback_days` bound the function itself enforces.

**The default stays at 90 deliberately.** Strava's per-user budget is 100 requests / 15 minutes and the walk spends one request per 50 activities, so raising the default would make every routine sync several times heavier for history the runner already has. Widening is an explicit act, taken once, to recover from a truncation left too long. Anything older than a year still needs the bulk export, and the note under the card says so.

A truncated sync is now a **state of the connection**, not a moment: both surfaces keep a note on the Strava card / tile until a walk reaches the end of the window. A toast or a top banner is said once and dismissed, and the window is measured from now, so the record of "there is more to fetch" has to outlive it.

This is separate from `ImportFailureLog` below, and deliberately so: that vocabulary describes **per-activity** failures inside a client-side archive walk, where every entry names an activity that was seen and refused. A truncated page walk has no such entry — the activities it did not fetch were never seen. The word `rate_limited` is shared; the record is not.

Operational pre-requisites:
- The `threkir://strava-callback` URI must be allow-listed in the Strava developer console **and** in `STRAVA_ALLOWED_REDIRECTS` on the Edge Function. The comparison is **whole-string**, not by origin — Strava's own callback-domain check is path-prefix loose, so any path under our domain would otherwise be exchangeable, and a custom scheme has no origin to compare anyway. An unset or empty allowlist **fails closed** (503 `strava_not_configured`); a claim outside it is 400 `invalid_redirect_uri`. Parse + comparison live in `apps/backend/supabase/functions/_shared/redirect_allowlist.ts`, shared with the three Stripe-events functions, and both branches are covered by `_shared/redirect_allowlist.test.ts` ([decisions § 750](../architecture/decisions.md)). Both `apps/backend/.env.development` and `.env.example` carry the mobile callback alongside the web one since 2026-08-28 — `.env.example` is what an operator copies to configure production, where a missing entry is not inert. A local mobile connect still needs the real `STRAVA_CLIENT_ID` that local dev leaves empty. `strava-import/wiring.test.ts` pins both files against `kStravaCallbackUri` in the Dart client, so moving the scheme moves the guard.
- Falls back to the web browser hand-off on builds where the client ID is unconfigured (matches the existing `url_launcher` path used before native OAuth shipped).
- `lib/strava.dart` mirrors `apps/web/src/lib/integrations/strava.ts` and is unit-tested (16 tests in `test/strava_test.dart` on URL building + callback parsing + configured-state checks).

### Bulk export (ZIP) import

Independent of OAuth, both clients import Strava's "Request your archive" download — a ZIP with a root-level `activities.csv` index plus an `activities/` folder of per-run GPX / TCX / FIT files (modern exports gzip the inner files: `.gpx.gz`, `.tcx.gz`, `.fit.gz`). Web: `apps/web/src/lib/integrations/strava-zip.ts` (+ the pure header map `strava-zip-header.ts`). Mobile: `apps/mobile_android/lib/strava_importer.dart`. The CSV supplies scalar metadata (id, date, name, type, distance, moving time, avg HR) and the per-activity file supplies the GPS track; the two are combined so metadata survives even when a file is missing. Dedup tags each run with `metadata.strava_id` + `external_id = strava:{id}`. **A row with an empty `Filename` is a manually-entered or indoor activity — Strava points at no track file for it — and imports trackless off the CSV's own date / distance / elapsed time on both clients.** Mobile used to `continue` past those rows before any counter, so a migrating runner's whole treadmill history vanished from an import that reported cleanly (fixed 2026-08-18). **A `Filename` that names a file the archive does not hold, or a format neither parser reads, fails the row into the `ImportFailureReport` on BOTH clients** — the export promised something it did not deliver, which is a different fact from never promising one. Web was the lenient one until 2026-08-18 (it fell through to a summary-only run and swallowed a parse throw besides); the decision now lives in the pure `integrations/strava_track_member.ts` ↔ `_parseTrackFile` in `strava_importer.dart`. The one asymmetry is deliberate: a failed gunzip still imports trackless on web, because `gunzipBlob` cannot tell a corrupt member from a browser with no `DecompressionStream`, where Dart's `GZipDecoder` throws. Both refusals are worded (`Malformed export: track file not found in zip: …` / `Unsupported file format: …`) so `classifyImportFailure` reports them as `unparseable`, not `unknown` — see [decisions § 676](../architecture/decisions.md).

**Six columns are mandatory, and the reason is not that the importer cannot proceed without one.** `indexHeader` answers `-1` for a header it cannot find, `row[-1]` is `undefined`, and every read of it in `importOne` FABRICATES a value for every row in the archive rather than failing — a missing `Activity Type` defaults each row to `run` (a migrant's rides and swims imported as runs), a missing `Activity Date` stamps each row with the moment of the import (five years of history on today), a missing `Moving Time` gives every run a zero duration, and no distance column at all gives every run zero distance. So `Activity ID` / `Filename` / `Activity Type` / `Activity Date` / `Moving Time` / `Distance` are refused at the header, naming whichever are missing; `Distance` is satisfied by EITHER numeric block (see the unit quirk below). A blank CELL stays lenient per row — except the date, where an unparseable cell refuses that row into the failure report rather than filing it under today (decisions § 979 + § 1042). The list lives in `missingRequiredStravaColumns` in `strava-zip-header.ts`, not inline in the importer, so both guards over it execute rather than reading the importer as text ([decisions § 1059](../architecture/decisions.md)).

**A refusal of the WHOLE file is translated; a per-row failure keeps its diagnostic English.** The six file-level refusals both web importers can raise — signed out, the 500 MB archive cap, a zip with no root `activities.csv`, an `activities.csv` with no rows, the missing-column list, and Garmin's "choose a .fit or a .zip" — travel as an `ImportRefusedError` carrying a reason IDENTIFIER plus its specifics as data (`integrations/import_refusal.ts`), and `i18n/import_refusal_message.ts` assembles the sentence from the catalogue at the render layer. Nothing else thrown is shown bare either: it is framed inside `settingsIntegrations.stravaZipImportFailed` / `garminImportFailed`'s `{error}` slot, the issue #345 shape. The per-row `detail` in the `ImportFailureReport` stays a raw log-safe string on purpose — it is a diagnostic pasted into a support thread, beside a `reason` that IS keyed ([decisions § 1058](../architecture/decisions.md)).

**Unit quirk (issue #380).** `activities.csv` carries **two** numeric blocks. The first ("summary") block's `Distance` follows the athlete's **display unit at export time** — km for a metric athlete, **miles for an imperial one** — a documented Strava behaviour with no format option. The second ("raw") block repeats `Distance` (~col 18) always in **SI metres**. The importers therefore prefer the raw-block metric column (`stravaDistanceMetres` in `strava-zip-header.ts` ↔ `stravaCsvDistanceMetres` in `strava_importer.dart` — matching logic, both unit-tested), falling back to the display column only when a single `Distance` exists (honouring an explicit `Distance in Miles` / `Distance in Kilometers` header, else assuming km — on mobile the parsed track's distance overrides this fallback anyway). Before the fix both clients treated the display `Distance` as km unconditionally, so every imperial-athlete import came in ~1.609× short, silently corrupting mileage / pace / PRs / VDOT. `Elevation Gain` appears only in the raw SI block, so it is always metres and needs no unit branch.

### Import failure reporting

Both web bulk importers (`strava-zip.ts`, `garmin-zip.ts`) carry a `failures: ImportFailureLog` alongside the `failed` counter. Each caught error is classified by the pure `apps/web/src/lib/integrations/import_failures.ts` into one of `network` / `auth` / `rate_limited` / `too_large` / `unparseable` / `rejected` / `unknown` and recorded with the activity name, its start (Strava, from the CSV cell), and a log-safe `code: message` detail — never the PostgREST `.details` / `.hint`, which echo row fragments (`core/supabase_error.ts`). The list is capped at 200 entries with the overflow counted in `truncated`, so a pathological archive can't turn the failure log itself into the OOM.

`ImportFailureReport.svelte` renders it under each import card on `/settings/integrations`: a reason tally, a per-activity list, and a CSV download (`<provider>-import-failures.csv`, English column headers so two reports merge). It is held in its own state so it outlives the progress bar, which self-clears a few seconds after the walk finishes. **Re-running the import is the retry** — both importers dedupe against what already landed, so nothing duplicates; what the runner was missing is the information to decide whether re-running is worth it.

**Mobile carries the same report.** `apps/mobile_android/lib/import_failures.dart` is the Dart twin (registered as the `import_failures` parity pair, 22 mirror tests each), and `widgets/import_failure_report.dart` renders it on the Import screen — reason chips, an expandable per-activity list, and a CSV handed to the OS share sheet rather than downloaded. All three mobile importers feed it **at the point they catch**: `strava_importer.dart` records the CSV row's activity name and parsed start rather than the archive path, `health_connect_importer.dart` records the workouts it previously dropped into a `debugPrint` with nothing on screen (plus a route read that failed outright, which is otherwise indistinguishable from a source holding no routes), and `csv_run_importer.dart` records each rejected row under its 1-based row number. The shared save loop in `import_screen.dart` appends its own local-save failures to the same log, so the runner reads one list.

One mobile-only disclosure has no web counterpart: web imports one activity at a time, so a push failure IS a per-item failure, whereas mobile saves locally then batch-pushes. That push reported nothing at all — it swallowed its throw, and `saveRunsBatch` signals a PARTIAL failure by returning the ids whose track upload failed rather than by throwing, so a half-landed batch read as a clean import too. Both push sites (the shared save loop and the route backfill) now count the returned set as well as the throw, and `importStatusCloudPushDeferred` carries the number: 3-of-400 pending is a different fact from 400-of-400. It stays a note rather than N `ImportFailureReport` entries, because those name an activity that did not import and exist to decide whether re-running is worth it — these runs DID import, are on the device, and `SyncService` retries them without one. The sidecar write that records the pushed runs as synced is its OWN try/catch, not part of that count: it runs after `saveRunsBatch` returned, so its failure cannot mean the runs are absent from the server — it only leaves this device re-reading them as unsynced on the next cold start, and the re-push upserts onto the same rows. Folding it into the push's catch reported the whole batch as deferred when every upload had succeeded, so it gets a `debugPrint` and no disclosure rather than a borrowed one.

A consequence for Garmin: `importFitFile` / `importRouteFile` no longer return a `'failed'` disposition, they **throw**, so the loop's single catch is the one funnel where a failure gets a reason. A per-activity `.zip` wrapper still falls through to a later `.fit` member if an earlier one throws.

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

// 2. Service-role client (the webhook isn't a user request).
// secretKey() from _shared/api_keys.ts resolves sb_secret_… with a
// legacy service_role fallback — never read the key env vars directly.
const supabase = createClient(Deno.env.get('SUPABASE_URL')!, secretKey());

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

**Web — bulk FIT import.** `/settings/integrations` ships a "Bulk import from a Garmin export" card that accepts either a single `.fit` file (Garmin Connect → activity → "Export Original") or the full `.zip` from `Garmin → Account Management → Request Your Data`. Implementation in `apps/web/src/lib/integrations/garmin-zip.ts` + `garmin-fit.ts`; FIT decoding uses `fit-file-parser` and is dynamic-imported so the binary decoder is only fetched when a user picks a file. Dedupes within a single import on the FIT `file_id` message (`time_created-serial_number`) with a `started_at|distance_m` composite fallback for `.gpx` / `.tcx` originals inside the bundle. A `file_id` missing **either** the `time_created` or the `serial_number` forms **no** dedupe key (a serial alone is the shared device id, not per-activity) — the run is imported rather than dropped against another malformed file sharing that serial (#397). Across imports, the FIT path also persists `runs.external_id = garmin:{file_id}` (via `garminExternalId`) so a later re-import — or a future Garmin OAuth path — is blocked by the per-user `external_id` unique index, not just the in-session set (#18). It additionally applies the [cross-provider near-duplicate guard](#cross-provider-near-duplicate-guard) so a run already imported under another source (e.g. auto-uploaded to Strava) is skipped, and computes [embedded best efforts](#embedded-best-efforts-on-import) from the FIT / GPX / TCX track. The importer also preserves `metadata.sub_sport` (trail / treadmill / track), `metadata.running_dynamics` (vertical oscillation / GCT / stride / power — both surfaced on run-detail), and one-time seeds `user_settings.prefs.hr_zones` from the FIT `hr_zone` messages (via `buildHrZonesFromFit`) **only when the user has no zones set** — it never clobbers a configured set.

**Mobile — HealthKit / Health Connect.** Garmin Connect mobile app syncs to HealthKit (iOS) and Health Connect (Android) automatically. Users who install Garmin Connect alongside your app will have their Garmin runs available via the HealthKit/Health Connect import with no extra work. The Health Connect import also reads the user's latest body-weight sample (`HealthConnectImporter.fetchLatestWeightKg`) and one-time seeds `user_settings.prefs.body_weight_kg` when the user hasn't set one — so the calorie estimate uses a real weight instead of the 70 kg fallback (persona round-5 samsung-watch). It never overwrites an existing weight.

---

## Race results (RunSignUp + general scraping)

> **Status: shipped (2026-06-20, migration `20270214_001`, race_calendar.md).** The race calendar (`race_listings`) + the `race-results-import` / `race-listings-sync` Edge Functions + the auto-match-on-record seam are live on web (`/races`, run-detail) and mobile (`RacesScreen`, run-detail). **`race-listings-sync` stopped being a stub on 2026-09-02** ([decisions § 977](../architecture/decisions.md)): the provider fetch, per-provider row readers, batch reconciliation, service-role insert and differential update are written behind the unchanged fail-closed credential gate. Its field names and endpoints are unverified against a live payload (no credential exists), so every reading is optional-with-drop and the response reports `unusable` — a differently-shaped feed answers `synced: 0` on the first call instead of writing junk into the calendar. The **RunSignUp leg is prod-gated, fail-closed**: with `RUNSIGNUP_API_KEY`/`RUNSIGNUP_API_SECRET` unset (the dev/CI default) both EFs return `503 provider_not_configured` and the UI shows the unavailable explainer — provisioning the key on the deployed project is the only remaining go-live step (record it on the deploy checklist). The **ChronoTrack leg is prod-gated, fail-closed** the same way: with `CHRONOTRACK_CLIENT_ID`/`CHRONOTRACK_USER_ID`/`CHRONOTRACK_PASSWORD` unset (the dev/CI default) the `chronotrack` import branch + the `provider:'chronotrack', probe:true` availability probe both return `503 provider_not_configured` and the Settings card shows the unavailable explainer — provisioning the three CTLive credentials is the only remaining go-live step. The **UltraSignup leg refuses unconditionally**, credential or no credential (2026-09-02, [decisions § 975](../architecture/decisions.md)): `ultraSignUpResultsUrl` reads `/service/events.svc/results/athlete?uid=`, an ATHLETE feed with no race parameter, and `UltraSignUpResult` carries no field naming which race a row is from — so every row it returned was stamped with the target listing's name, date, distance and `race_listing_id`, measured as three unrelated races becoming three identical-looking `runs` rows. `ultraSignUpAttributionGate()` now answers `503 provider_not_configured` with `reason: 'results_unattributable'` on BOTH doors (the per-listing import branch, before the credential read and before the fetch, and the availability probe), so the existing client unavailable-explainer seam disables the tile. Lifting it needs UltraSignup's real payload observed plus a filter on the race identifier against the listing's `provider_race_id` — deleting the gate alone restores the defect. Since 2026-08-30 the leg is surfaced on mobile as well as web — all three credential-gated providers carry a Settings tile and a reachable per-listing import on the phone, generated from the `raceImportProviders` catalogue in `race_service.dart` rather than branched on by name. **parkrun** stays the shipped scraper; **manual paste** is the durable non-API path for every other timing platform, and a `parkrun` / `manual` / `raceresult` listing correctly offers paste alone. RaceResult per-site scraping remains a scoped follow-up — the URL-pattern table below is the reference for when one is built, not a description of shipped behaviour. **Two client-side corrections landed 2026-09-02.** Both clients had been probing `race-listings-sync` to decide whether to offer the UltraSignup **results** tile — a different function, and one that answers on `ULTRASIGNUP_API_KEY` alone, so provisioning the key would have lit up a tile whose very next call 503s with the attribution refusal above. Both now probe `race-results-import` with `{ provider: 'ultrasignup', probe: true }`, the shape ChronoTrack already used ([decisions § 1008](../architecture/decisions.md)). RunSignUp is deliberately still probing the sync: `race-results-import` has no probe/import rate-limit split, so its 8/hour free bucket is shared with real imports and moving the third probe there would exhaust a runner's ability to import after about two settings visits — filed, behind applying [§ 977](../architecture/decisions.md)'s split to that function. Separately, mobile's `isProviderConfigured` had been failing OPEN on anything but a 503 (a 429, any 5xx, a dropped connection, Supabase not yet initialised all read as *configured*) while web was already fail-closed; the phone now uses the same grading ([decisions § 1007](../architecture/decisions.md)).

**Both scrapers now report how much they read, and both clients say so.** `parkrun-import` bounds its result set at `MAX_PARKRUN_ROWS` and `race-results-import` at 2,000 finishers, and each says so with `complete` (plus `total` on the parkrun side). Until 2026-09-02 nothing read either field, so a capped history and a whole one both presented as a successful import of everything that existed. `parseImportCompleteness` grades both, fail-closed in `parseStravaSyncResult`'s direction — an absent `complete` is PARTIAL, because each scraper is one transport shipped from this repo alongside its callers ([decisions § 1014](../architecture/decisions.md)). The `502 upstream_results_truncated` refusal also has its own sentence now on both platforms rather than falling through to a generic import failure; it is not a failure a retry fixes, and the manual paste form beside it is the answer.

See [decisions.md § 168](../architecture/decisions.md#168-race-results-live-on-the-runs-row-sourcerace-a-public-race_listings-calendar-is-its-own-table-and-auto-match-on-record-is-an-inform-tier-layered-resilience-wrapped-post-save-check) + [§ 178](../architecture/decisions.md).

### RunSignUp

RunSignUp powers a large portion of US road races and has an official REST API. The shipped importer calls the results endpoint server-side from `race-results-import/index.ts` (key from the Edge-only `RUNSIGNUP_API_KEY`/`_SECRET` env), maps each finisher through `lib.ts` (`mapRunSignUpResult` → a `source='race'` run with `external_id=race:{name}:{date}:{bib}` + the owner-only race metadata), and upserts with per-user `external_id` dedup. Until the key is provisioned the leg is inert (503).

**Athlete-scoping is required (issue #360).** `get-results` returns the entire finisher field when unfiltered, so the leg is fail-closed: a request that names neither the runner's RunSignUp user id (`runSignUpUserId`, narrows the upstream fetch) nor a bib (`bib`, narrows the mapped field client-side via `filterResultsByBib`) is rejected `400 runsignup_athlete_id_required` before any fetch. In the `matchRunId` enrich path the leg additionally rejects `400 ambiguous_match` unless exactly one result maps — never silently merging `mapped[0]` (usually the winner) onto the caller's run. The web `/races` import modal + run-detail match banner and the mobile import sheet collect the bib — on mobile for every `RaceImportScope.bib` provider, so the ChronoTrack leg is gated identically rather than being unreachable; the gates are the pure `runSignUpScopeGate` / `matchResultGate` in `lib.ts`.

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
7. **Run-screen toggle:** `run_screen.dart` `_toggleTreadmillMode` renders a `SwitchListTile` over the recording view, gated on a paired belt (`pairedName()`). Turning it on subscribes the belt `stream` and pumps each sample into `setTreadmillSample`; turning it off cancels and calls `clearTreadmillMode`. It's an **L4 opt-in** — the subscription + recorder calls each carry their own try/catch + `debugPrint`, a fault shows a banner and reverts the toggle, and the L0 clock / L1 distance path is never disturbed. The belt's `statusStream` drives drop/reconnect disclosure banners (mirroring the HR strap), and `connectFailed` offers a one-tap reconnect. **The toggle's subtitle is switched on `BleTreadmillStatus`, not on whether a speed is known** (2026-08-21, [decisions § 704](../architecture/decisions.md)): `connected` is the only arm that can format a belt speed, and `reconnecting` / `connecting` / `disconnected` / `connectFailed` each state that the belt is not feeding — so a non-feeding belt stays disclosed after the transient banner expires, and no belt-derived figure can survive a drop. The toggle is off by default and never auto-engages, so a belt in range can't hijack an outdoor GPS run. **Hardware-in-the-loop verification against a real FTMS belt is still owed** — a device gate on the decode + reconnect behaviour of actual hardware, not on unwritten code. See [treadmill_live_mode.md](treadmill_live_mode.md).

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
[GPX route export](../product/features.md#gpx--kml-import) (line only, no waypoints),
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

### Same-source re-import: stable local id (mobile) (#361)

On mobile, the offline-first path splits dedupe across two layers, so the server `external_id` unique index alone is **not** enough. `LocalRunStore.save` dedupes by `Run.id`, and `ApiClient.saveRunsBatch` upserts on `(user_id, external_id)` while carrying the local `id` in the payload. If a re-import mints a fresh random `id` for an activity that already carries a stable `external_id`, two things break: the local store saves it as a *new* run (double-counting immediately), and the batch upsert runs `UPDATE runs SET id = <new> WHERE (user_id, external_id) = …` — rewriting the server row's primary key (orphaning the original, or throwing an uncaught FK violation that aborts the whole batch and wedges the sync queue).

Every mobile importer therefore derives the local `id` **deterministically from the stable `external_id`** — `stableRunIdFromExternalId(externalId)` (a v5 UUID over a fixed namespace, in `apps/mobile_android/lib/imported_run_id.dart`). Health Connect (`healthconnect:{uuid}`), Strava ZIP (`strava:{id}`), and CSV (the `csv:…` synthetic external_id, or a preserved server `external_id`) all route through it. A re-import then maps to the *same* local id: the local store replaces the prior copy instead of duplicating, and the upsert's `SET id = <same>` leaves the primary key untouched. The 17-column CSV / backup form that carries an explicit server `id` still preserves it (run-detail deep links survive a round-trip).

### Cross-provider near-duplicate guard

`external_id` (and the Strava `metadata.strava_id` / Garmin `garmin_id` keys) only dedupe **within one provider** — each source mints its own id namespace. They do **not** catch the same physical activity arriving under two providers: a Garmin watch that auto-uploads to Strava lands a `source='strava'` row (`strava:{id}`), and a later Garmin bulk-export ZIP import of the same run mints `garmin:{file_id}` — a different key, so the per-source dedupe never sees the Strava row and the run duplicates.

Every ingest path adds a start-time + distance near-duplicate guard **across all sources**: before inserting, it compares the candidate's start instant and total distance against the user's existing runs. A candidate is skipped when it starts within **180 s** of AND is within **5 %** distance of any existing run. Both axes must match — two genuinely distinct back-to-back runs can't start within a few minutes of each other (you can't record two GPS tracks at once), so gating on start proximity *and* distance similarity skips the same effort across providers without suppressing a warm-up-then-race.

The algorithm is kept byte-identical across every runtime so no provider drifts:

- **Web** — `isCrossProviderDuplicate` in `apps/web/src/lib/integrations/garmin_dedupe.ts` (Garmin ZIP importer).
- **Edge Function** — the same helper in `apps/backend/supabase/functions/_shared/strava.ts` (the `strava-import` backfill / manual sync).
- **Go worker** — `IsCrossProviderDuplicate` in `apps/job_worker/internal/cross_provider.go`. This is the **live production Strava webhook path** (`kind='strava_event'`): a dual-connected runner's Garmin-to-Strava auto-upload fires the webhook in real time, so the guard runs here on every ingest, querying only the runs within ±180 s of the candidate (a bounded index range, not the whole history).
- **Mobile** — `isCrossSourceDuplicate` in `apps/mobile_android/lib/cross_source_dedup.dart` (the Strava ZIP / Health Connect / CSV importers, applied in `import_screen.dart`'s save loop). Same 180 s / 5 %-of-larger math, plus two mobile-specific guards: it compares cross-source only (same-source re-imports are handled by the stable local id above — a re-import maps to the same `Run.id`, so the local store and the server `(user_id, external_id)` upsert both dedupe idempotently) and ignores a zero-distance existing run.

The Strava backfill (`strava-import`) and the Garmin ZIP importer (`garmin-zip.ts`) fetch every existing run's `started_at` + `distance_m` once per import for this check — **paged** in 1000-row chunks (`collectRunIdentities`, mirroring the `fetchRuns` workaround) because PostgREST silently caps an unbounded SELECT at 1000 rows, which for the 1000+-run pros this guard protects would otherwise compare against an arbitrary slice and re-import duplicates anyway.

### Embedded best efforts on import

Every importer that carries a per-point track also computes per-canonical-distance embedded best efforts (`metadata.fastest_{5k,10k,half_marathon,marathon}_s`) from the imported activity's track/stream, matching the live recorder's `fastestWindowOf` algorithm (shared `computeEmbeddedBests` on web/EF; `enrichMetadataWithEmbeddedBests` in `apps/mobile_android/lib/embedded_bests.dart` on mobile — wired into the Strava ZIP importer, the only mobile importer that carries a track; CSV imports are trackless, so there is nothing to compute; a Health Connect import computes them whenever the route grant released a timestamped track, so a backfilled run and a first-time routed import are indistinguishable). Without them, a fast 5k/10k *inside* a long imported run misses every whole-run canonical bracket and never reaches `personal_records` / the dashboard PR card / the public profile. A track with no per-point timestamps (indoor / treadmill / a route file with no times) writes nothing — no fake bests. See [`docs/backend/metadata.md` § Personal-records hints](../backend/metadata.md).

---

*Last updated: 2026-07-02*
