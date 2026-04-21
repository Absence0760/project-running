# End-to-end flows

Traces of the user journeys that cross multiple files, packages, or platforms. Each section points you at the code that actually runs so you can skip straight past the architecture doc to the lines you need to edit.

**This doc rots faster than anything else in the repo.** Flow docs describe runtime behaviour, which changes without a single file showing a diff. If you're updating one of the flows below, update this file in the same change. If you notice a flow here that doesn't match the code, fix one of them — don't leave both live. See the root [`CLAUDE.md`](../CLAUDE.md) § "Docs hygiene".

## Table of contents

- [Sign in — web](#sign-in--web)
- [Sign in — Android](#sign-in--android)
- [Sign in — Apple Watch](#sign-in--apple-watch)
- [Record a run (Android)](#record-a-run-android)
- [Sync (Android offline → cloud)](#sync-android-offline--cloud)
- [Spectator live tracking](#spectator-live-tracking)

---

## Sign in — web

**Owning doc:** [web_app_auth.md](web_app_auth.md) — this section is a summary.

The web app has **two login paths**:

1. **Demo login** (local dev + preview deploys): bypasses OAuth, creates a mock session in `localStorage`, no Supabase round-trip. Entry point: `src/routes/login/+page.svelte` → `auth.demoLogin(email)`.
2. **Supabase Auth** (production): Google or Apple OAuth. Redirect lands at `/auth/callback`, which exchanges the code and populates the Supabase session cookie.

### Runtime sequence (Supabase path)

```
User → /login                     src/routes/login/+page.svelte
  click "Continue with Google"
  → auth.signInWithGoogle()       src/lib/stores/auth.svelte.ts
  → supabase.auth.signInWithOAuth({ provider: 'google', redirectTo: /auth/callback })
  → browser redirects to Google
Google → /auth/callback?code=…    src/routes/auth/callback/+page.svelte (or +server.ts)
  → supabase.auth.exchangeCodeForSession(code)
  → session cookie set
  → goto('/dashboard')
/dashboard                        src/routes/+layout.svelte
  $effect checks auth.loggedIn — now true — renders sidebar + content
```

### Guard pattern

Every protected route relies on a root-layout `$effect` that calls `goto('/login')` when `auth.loggedIn` is false. Individual `+page.svelte` files never re-check — trust the layout. If you're adding a new protected route, do **not** add your own redirect; let the layout handle it.

### Watch out

- `apps/web/src/lib/supabase.ts` is the browser client. `supabase-server.ts` is the SSR client. They do not share a session object — cookies bridge them.
- The demo login path does not produce a Supabase JWT, so any code that calls an Edge Function or a REST endpoint with `Authorization: Bearer <token>` will fail under demo login. Keep the JWT-dependent calls behind a "real session only" gate or stub them for demo.

---

## Sign in — Android

**Owning files:** `apps/mobile_android/lib/screens/sign_in_screen.dart`, `packages/api_client/lib/src/api_client.dart`.

Two supported paths, plus a third that's scaffolded but not wired:

1. **Email/password** — `supabase_flutter`'s `signInWithPassword`. The seed user `runner@test.com` / `testtest` works for local testing.
2. **Google Sign-In** — native `google_sign_in` package driving the Google picker, then we hand the ID token to Supabase via `signInWithIdToken`.
3. **Apple Sign-In** — scaffolded, not wired up. Needs iOS-side entitlements; see the deferred list in `roadmap.md`.

### Runtime sequence (Google)

```
User → SignInScreen                  apps/mobile_android/lib/screens/sign_in_screen.dart
  taps "Sign in with Google"
  → GoogleSignIn().signIn()          native Google chooser
  → idToken from GoogleSignInAccount.authentication
  → ApiClient.signInWithGoogleIdToken(idToken, accessToken)
                                     packages/api_client/lib/src/api_client.dart:43
  → supabase.auth.signInWithIdToken(provider: google, idToken, accessToken)
  → Supabase session established; SupabaseClient.currentUser populated
  → navigator pushes HomeScreen
```

### Watch out

- The platform channel for `google_sign_in` requires a Google Cloud Console OAuth client matching the app's package signature. See [../apps/mobile_android/local_testing.md](../apps/mobile_android/local_testing.md) for the setup steps.
- The `ApiClient` is a **static singleton** after `ApiClient.initialize(url: ..., anonKey: ...)` runs in `main.dart`. Do not instantiate `ApiClient()` and pass it around — all screens read the same global session via `Supabase.instance.client`.
- When the user signs out, `ApiClient.signOut()` just calls `supabase.auth.signOut()`. It does **not** clear the local `LocalRunStore` — offline data survives sign-out by design.

---

## Sign in — Apple Watch

**Owning files:** `apps/watch_ios/WatchApp/SupabaseService.swift`, `apps/watch_ios/WatchApp/WatchConnectivityManager.swift`.

The watch **does not run a sign-in UI.** Credential entry on a 1.9" screen is a worse experience than every alternative. Instead, the watch receives a Supabase access token from the paired iOS phone app over `WCSession`:

```
iOS phone app signs in normally (user + password or Apple ID)
  → phone app holds a Supabase session
Watch launches
  → WatchConnectivityManager.shared.requestSessionToken()
  → phone receives WCSessionMessage, responds with { access_token, user_id, expires_at }
  → watch's SupabaseService stores the token and uses it on every REST call
```

If the phone isn't reachable (out of range / not yet paired / not signed in), the watch shows a "Sign in on your iPhone" placeholder and all backend-touching features are disabled.

### Watch out

- The watch has its own Supabase client (`SupabaseService.swift`) that does not share code with `packages/api_client`. Any schema change that affects a column referenced from Swift must be ported by hand; the schema generators do not cover Swift. See [apps/watch_ios/CLAUDE.md](../apps/watch_ios/CLAUDE.md).
- Token expiry handling on the watch is minimal. If the phone-side token refresh hasn't landed yet (`refresh-tokens` Edge Function), expect the watch to start returning 401s ~1 hour after sign-in. Resolution: re-launch the phone app, which will refresh and re-push the token.

---

## Record a run (Android)

**Owning doc:** [run_recording.md](run_recording.md) — the full state machine and filter chain. This section is the cross-file summary.

### Runtime sequence

```
1.  Home screen → tap Start
      apps/mobile_android/lib/screens/home_screen.dart
2.  _maybeRequestPermission() — FINE_LOCATION + POST_NOTIFICATIONS
      (ACTIVITY_RECOGNITION is handled at first launch in
      onboarding_screen.dart, not here). Non-blocking: denial drops the
      run into time-only mode rather than aborting.
3.  Navigator pushes RunScreen
      apps/mobile_android/lib/screens/run_screen.dart
4.  initState: 3-second countdown begins, _preload() runs in parallel
      - RunRecorder instantiated (packages/run_recorder)
      - RunRecorder.prepare() flips _prepared = true, starts the GPS
        retry loop, then tries to open the GPS stream. Throws
        LocationServiceDisabledError / LocationPermissionDeniedError on
        failure but _prepared stays true — the run remains usable.
      - pedometer subscribed; wakelock acquired
      - GPS fixes during countdown drive the blue dot but don't accumulate
5.  Countdown hits 0 → _begin()
      - Awaits _prepareFuture — on error, _notifyGpsUnavailable shows a
        snackbar with a Settings shortcut; the run continues as a
        time-only indoor session
      - RunRecorder.begin() flips recording on, starts the Stopwatch
      - Stable run id generated (uuid v4)
      - Incremental-save timer starts (every 10s → runs/in_progress.json)
      - GPS-lost and permission watchdogs start (gated behind first real
        fix, so indoor runs don't nag)
6.  Each GPS fix:
      - accuracy > 20 m → dropped
      - delta/dt > maxSpeedMps → dropped (implausible)
      - delta > minMovementMetres → appended to track, distance added
      - RunSnapshot emitted → screen updates, auto-pause checks fire
7.  User holds Stop for 800 ms → _stop()
      - RunRecorder.stop() closes the stream and returns a Run
      - metadata populated: activity_type, steps, laps (if any)
      - in_progress.json cleared
      - LocalRunStore.save(run) → on-disk file in the runs/ dir
      - SyncService._trySync() kicks off a push attempt if online
8.  Navigator pops back to HomeScreen; dashboard rebuilds from LocalRunStore
```

### Watch out

- **`RunRecorder` is in a package, not the app.** All the filter / auto-pause / state-machine logic lives in `packages/run_recorder/lib/src/run_recorder.dart`. The `apps/mobile_android/lib/screens/run_screen.dart` file is only UI + lifecycle + screen state. If you're fixing a recording bug, start in the package.
- **Auto-pause has been moved from live-state to derived-from-track.** See [decisions.md § 4](decisions.md). Don't add a live "is paused" bit to the recorder — the correct way to know moving time is `movingTimeOf(run)` after the fact.
- **Metadata on the saved run** is the bag described in [metadata.md](metadata.md). `activity_type`, `steps`, `laps`, and (via `LocalRunStore`) `last_modified_at`. The `in_progress_saved_at` key is written during recording and cleared on the final save; `recovered_from_crash` is written when `main.dart` recovers a crashed session on next launch.
- **Crash recovery path**: if the app dies mid-run, `in_progress.json` survives. Next launch, `apps/mobile_android/lib/main.dart` reads it, promotes the partial to a completed run, stamps `recovered_from_crash = true`, saves via `LocalRunStore`, and shows a snackbar. The user never goes through `RunScreen` for the recovery.

---

## Sync (Android offline → cloud)

**Owning files:** `apps/mobile_android/lib/sync_service.dart`, `apps/mobile_android/lib/local_run_store.dart`.

### The model

Every run the Android app handles lives in `LocalRunStore` first. The store is the source of truth on device; Supabase is the source of truth across devices. Reconciliation between the two is the sync service's job.

- **Push-side** is driven by `SyncService._trySync()`: iterate `LocalRunStore.unsyncedRuns`, call `ApiClient.saveRun(run)`, mark synced on success. It's best-effort — failures are logged, not surfaced to the UI.
- **Pull-side** is driven manually from the History screen's "pull from cloud" button. `ApiClient.getRuns()` returns cloud runs, each gets passed to `LocalRunStore.saveFromRemote()`, which applies newer-wins conflict resolution against `metadata.last_modified_at`.

### Triggers for a push

```
SyncService listens for:
  - app lifecycle resumed → _trySync('foreground')
  - connectivity changed to online → _trySync('connectivity')
  - startup → _trySync('startup')

Each _trySync:
  - if apiClient.userId == null: return       (not signed in, stay offline)
  - if unsyncedRuns.isEmpty: return
  - if already syncing: return                (reentrancy guard)
  - for each unsynced run:
      try { ApiClient.saveRun(run); store.markSynced(run.id); pushed++ }
      catch { debugPrint('failed...') }
```

No queuing, no retry-with-backoff. If a push fails (network dies mid-sync, server returns 5xx), the run stays `unsynced` and the next trigger retries.

### Newer-wins conflict resolution (pull side)

```
User taps "Pull" on RunsScreen
  → ApiClient.getRuns() returns cloud runs (track is empty; lazy-loaded later)
  → for each remote run:
      LocalRunStore.saveFromRemote(remote):
        existing = local[remote.id]
        if existing and local.last_modified_at > remote.last_modified_at:
          return                              # local wins, ignore remote
        if remote.track.isEmpty and existing.track.isNotEmpty:
          merged = remote with existing.track  # preserve local GPS
        else:
          merged = remote
        save merged to disk, mark synced
```

The track-preservation step is specifically because cloud rows have empty `track` arrays (tracks live in Storage; see [decisions.md § 2](decisions.md)). If we just took `remote` as-is, pulling would drop the GPS data of every run we already had locally.

### Watch out

- **`last_modified_at` is on `metadata`, not a real column.** See [metadata.md](metadata.md#internal--runtime-only). That means conflict resolution depends on both sides writing it consistently. If a non-Android client (web, watch) starts editing runs, it needs to stamp this key too — or the Android client will ignore its edits as "older than local".
- **WorkManager-based periodic sync is live** (`background_sync.dart`, hourly with a network constraint). A run made offline with the app force-killed still syncs without a manual relaunch, though the hourly cadence means there may be up to 1 hour of delay. Foreground + connectivity-change triggers still cover the fast path.
- **No push from web or watch**. The web app writes directly to Supabase via `supabase-js`; it has no local store, so "sync" doesn't apply. The watch writes directly via `SupabaseService.swift`. Both rely on real-time connectivity and have no offline queue.
- **Pull currently has no auto-trigger.** It only runs when the user taps the History screen's pull button. If you're debugging "why haven't I seen the web's new run on Android?", the answer is almost certainly "pull hasn't been triggered."

---

## Spectator live tracking

**Status as of now:** the web page exists and renders a **simulated** runner. The real WebSocket link to a Go service is Phase 2 work (see [roadmap.md](roadmap.md) § "Live spectator tracking" and § "Phase 2 backend work").

### Runtime sequence (current — simulated)

```
Runner (Android) starts a run (not shared yet — this flow is one-directional)
  ...eventually the runner will flip a "share live" toggle that returns a URL
  ...the URL flow doesn't exist yet

Spectator → /live/{run_id}
  apps/web/src/routes/live/[run_id]/+page.svelte
  → MapLibre GL JS map mounts
  → a JS timer drives a fake runner dot along a hardcoded route
  → UI shows simulated distance, elapsed time, pace
  → pulsing LIVE badge
```

There is no real data source. The page is a visual scaffold so the design is right before the Go service lands.

### Runtime sequence (Phase 2 — planned)

```
Runner (mobile) toggles "share live" before or during a run
  → client generates a share URL: https://app.runapp.com/live/{run_id}
  → client opens WebSocket to Go service at wss://go.runapp.com/live/{run_id}
  → every GPS fix: WebSocket send { lat, lng, ts, distance, elapsed }

Go service
  → accepts WebSocket, writes position to Redis (TTL 24h) for late joiners
  → broadcasts to any spectator WebSockets on the same run_id

Spectator → /live/{run_id}
  → MapLibre map mounts
  → opens WebSocket to Go service
  → receives position updates, moves the runner dot, extends the trace
  → if no runner is connected, reads Redis to show the last known position
```

### Watch out

- **Do not add real WebSocket code to the current page** without also adding the backing Go service. A half-done implementation is worse than the simulation because it looks real and confuses users.
- **Live tracking battery drain** is the main risk of this feature. Every-3-second GPS → WebSocket ≈ 5 % extra battery per hour. Roadmap § "Open risks" says the feature must be opt-in per run, never on by default.
- **The public `/live/{run_id}` page must work without auth.** No user JWT, no session cookie. The Go service will need to treat the `run_id` as a bearer token of sorts — shareability is the feature.
