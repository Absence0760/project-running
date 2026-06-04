# End-to-end flows

Traces of the user journeys that cross multiple files, packages, or platforms. Each section points you at the code that actually runs so you can skip straight past the architecture doc to the lines you need to edit.

**This doc rots faster than anything else in the repo.** Flow docs describe runtime behaviour, which changes without a single file showing a diff. If you're updating one of the flows below, update this file in the same change. If you notice a flow here that doesn't match the code, fix one of them — don't leave both live. See the root [`CLAUDE.md`](../../CLAUDE.md) § "Docs hygiene".

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

The web app has **one login path**:

1. **Supabase Auth**: Google or Apple OAuth. Redirect lands at `/auth/callback`, which exchanges the code and populates the Supabase session in `localStorage`.

### Runtime sequence

```
User → /login                     src/routes/login/+page.svelte
  click "Continue with Google"
  → auth.signInWithGoogle()       src/lib/stores/auth.svelte.ts
  → supabase.auth.signInWithOAuth({ provider: 'google', redirectTo: /auth/callback })
  → browser redirects to Google
Google → /auth/callback?code=…    src/routes/auth/callback/+page.svelte
  → supabase.auth.exchangeCodeForSession(code)
  → session stored in localStorage
  → goto('/dashboard')
/dashboard                        src/routes/+layout.svelte
  $effect checks auth.loggedIn — now true — renders sidebar + content
```

### Guard pattern

Every protected route relies on a root-layout `$effect` that calls `goto('/login')` when `auth.loggedIn` is false. Individual `+page.svelte` files never re-check — trust the layout. If you're adding a new protected route, do **not** add your own redirect; let the layout handle it.

### Watch out

- `apps/web/src/lib/core/supabase.ts` is the only Supabase client. It is a browser-side client (`createBrowserClient` from `@supabase/ssr`). There is no SSR client; the app is fully static (`adapter-static` with `fallback: index.html`). The JWT lives in `localStorage`.

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

- The platform channel for `google_sign_in` requires a Google Cloud Console OAuth client matching the app's package signature. See [../apps/mobile_android/local_testing.md](../../apps/mobile_android/local_testing.md) for the setup steps.
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

- The watch has its own Supabase client (`SupabaseService.swift`) that does not share code with `packages/api_client`. Any schema change that affects a column referenced from Swift must be ported by hand; the schema generators do not cover Swift. See [apps/watch_ios/CLAUDE.md](../../apps/watch_ios/CLAUDE.md).
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
      - activity_type / is_dnf columns set; metadata bag populated: steps, laps (if any)
      - in_progress.json cleared
      - LocalRunStore.save(run) → on-disk file in the runs/ dir
      - SyncService._trySync() kicks off a push attempt if online
8.  Navigator pops back to HomeScreen; dashboard rebuilds from LocalRunStore
```

### Watch out

- **`RunRecorder` is in a package, not the app.** All the filter / auto-pause / state-machine logic lives in `packages/run_recorder/lib/src/run_recorder.dart`. The `apps/mobile_android/lib/screens/run_screen.dart` file is only UI + lifecycle + screen state. If you're fixing a recording bug, start in the package.
- **Auto-pause has been moved from live-state to derived-from-track.** See [decisions.md § 4](../architecture/decisions.md). Don't add a live "is paused" bit to the recorder — the correct way to know moving time is `movingTimeOf(run)` after the fact.
- **Metadata on the saved run** is the bag described in [metadata.md](../backend/metadata.md). `activity_type`, `steps`, `laps`, and (via `LocalRunStore`) `last_modified_at`. The `in_progress_saved_at` key is written during recording and cleared on the final save; `recovered_from_crash` is written when `main.dart` recovers a crashed session on next launch.
- **Crash recovery path**: if the app dies mid-run, `in_progress.json` survives. Next launch, `apps/mobile_android/lib/main.dart` reads it, promotes the partial to a completed run, stamps `recovered_from_crash = true`, saves via `LocalRunStore`, and shows a snackbar. The user never goes through `RunScreen` for the recovery.

---

## Sync (Android offline → cloud)

**Owning files:** `apps/mobile_android/lib/sync_service.dart`, `apps/mobile_android/lib/local_run_store.dart`.

### The model

Every run the Android app handles lives in `LocalRunStore` first. The store is the source of truth on device; Supabase is the source of truth across devices. Reconciliation between the two is the sync service's job.

- **Push-side** is driven by `SyncService._trySync()`: take `LocalRunStore.unsyncedRuns`, run it through `filterRunsForCurrentUser(unsynced, api.userId)` (drops runs whose `metadata.created_by_user_id` names a *different* user — the shared-device owner-tag guard, see [decisions.md § 67](../architecture/decisions.md#67-offline-saved-runs-carry-a-created_by_user_id-owner-tag--defends-shared-device-sign-out--sign-in)), call `ApiClient.saveRunsBatch(filtered)`, mark synced on success. It's best-effort — failures arm an exponential backoff (60 s → 2 min → … capped at 30 min) but don't surface to the UI.
- **Pull-side** is driven manually from the History screen's "pull from cloud" button. `ApiClient.getRuns()` returns cloud runs, each gets passed to `LocalRunStore.saveFromRemote()`, which applies newer-wins conflict resolution against `metadata.last_modified_at`.

### Triggers for a push

```
SyncService listens for:
  - app lifecycle resumed → _trySync('foreground')
  - connectivity changed to online → _trySync('connectivity')
  - startup → _trySync('startup')
  - manual "Sync all" tap on runs_screen → triggerSync('manual')
  - main.dart auth-state listener fires signedIn → triggerSync('signin')

Each _trySync:
  - if already syncing: return                (reentrancy guard)
  - if reason ∉ {'manual', 'signin'} and in backoff: return
  - if apiClient.userId == null: return       (not signed in, stay offline)
  - filter unsyncedRuns by metadata.created_by_user_id
  - if filtered.isEmpty + no pending deletes + no unsynced routes: return
  - api.saveRunsBatch(filtered) → mark only the ids NOT in the
    returned failed-track set as synced; arm backoff on any failure
```

`{'manual', 'signin'}` is the bypass set: a user-initiated retry from the runs screen always fires, and a fresh auth session is a strong signal that any prior auth-rejection backoff is stale (the session that produced the 401 is gone). Without the signin bypass, a user who signs out, the queue piles up, then signs back in is stuck waiting out a 30-min window from the dead session — their freshly-recorded offline run sits unsynced.

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

The track-preservation step is specifically because cloud rows have empty `track` arrays (tracks live in Storage; see [decisions.md § 2](../architecture/decisions.md)). If we just took `remote` as-is, pulling would drop the GPS data of every run we already had locally.

### Watch out

- **`last_modified_at` is on `metadata`, not a real column.** See [metadata.md](../backend/metadata.md#internal--runtime-only). That means conflict resolution depends on both sides writing it consistently. If a non-Android client (web, watch) starts editing runs, it needs to stamp this key too — or the Android client will ignore its edits as "older than local".
- **Pending remote-deletes are per-user tagged.** `LocalRunStore.markManyPendingRemoteDelete(ids, ownerUserId: api.userId)` stamps each queued failure with the user_id who queued it. `SyncService._drainPendingDeletes` filters via `runStore.pendingRemoteDeletesForUser(api.userId)` so on a shared device, User A's queued deletes aren't attempted under User B's session (RLS would reject every one and the queue would get stuck failing forever). Untagged entries (legacy / queued-while-signed-out) adopt to whichever user is signed in next, mirroring the run owner-adoption rule. The persistence file upgrades from the legacy `{"ids": [...]}` shape to `{"deletes": {id: owner_or_null}}` on the next mutation. Pinned by `architecture_guards_test.dart#_drainPendingDeletes uses the per-user filter` + `runs_screen passes the current user id when queuing pending deletes`.
- **WorkManager-based periodic sync is live** (`background_sync.dart`, hourly with a network constraint). A run made offline with the app force-killed still syncs without a manual relaunch, though the hourly cadence means there may be up to 1 hour of delay. Foreground + connectivity-change triggers still cover the fast path. The WorkManager callback routes the unsynced queue through `filterRunsForCurrentUser` so the background path applies the same shared-device owner-tag guard as the foreground `SyncService` — without that mirror, the periodic fire would push User A's runs under User B's account on a shared device. Pinned by `architecture_guards_test.dart#background_sync applies the owner-tag filter before push`.
- **No push from web or watch**. The web app writes directly to Supabase via `supabase-js`; it has no local store, so "sync" doesn't apply. The watch writes directly via `SupabaseService.swift`. Both rely on real-time connectivity and have no offline queue.
- **Pull currently has no auto-trigger.** It only runs when the user taps the History screen's pull button. If you're debugging "why haven't I seen the web's new run on Android?", the answer is almost certainly "pull hasn't been triggered."

---

## Spectator live tracking

**Status:** shipped on Supabase Realtime today; the WebSocket transport on the Go worker is code-complete and awaits a Fly deploy + DNS flip. The transport is selected by env at runtime — see "Switching transports" below. The pre-start share flow (mint `run_id` on share button so the link is stable across "share now → tap GO later") is live across web + mobile per [decisions.md § 25](../architecture/decisions.md#25-live-spectator-tracking-uses-supabase-realtime-not-a-custom-websocket-service).

### Runtime sequence (default — Supabase Realtime)

```
Runner (mobile or web) taps "Share live link" (pre-start or in-run)
  → run row created with is_live = true, run_id stable for the link
  → during recording, every GPS fix INSERTs into live_run_pings
    (apps/mobile_android/lib/services/live_broadcast.dart,
     apps/web/src/lib/live_broadcast.ts)

Spectator → /live/{run_id}
  apps/web/src/routes/live/[id]/+page.svelte
  → MapLibre GL JS map mounts
  → supabase.channel(`live:{run_id}`).on('postgres_changes', ...)
    subscribes to inserts on live_run_pings filtered by run_id
  → each ping moves the runner dot, extends the trace
  → privacy-zone segments clipped via clip_track_for_user RPC
    before the row reaches the spectator (decisions §33)
```

### Runtime sequence (opt-in — Go WebSocket hub)

```
Runner client reads PUBLIC_LIVE_HUB_URL / LIVE_HUB_URL
  unset → Supabase Realtime (above)
  set   → wss://<hub>/run/{run_id} (apps/job_worker/internal/livehub/)
            • SupabaseZoneFetcher fetches the runner's privacy zones once
              on join, applies clipping per ping before broadcasting
            • RedisHub (Upstash) fans out across hub replicas for late joiners

Spectator client reads PUBLIC_LIVE_HUB_URL (same envs)
  unset → Supabase Realtime
  set   → wss://<hub>/live/{run_id}
```

### Switching transports

Both runner + spectator must agree. Flip both envs (`PUBLIC_LIVE_HUB_URL` on web, `LIVE_HUB_URL` on mobile) in the same release. See `apps/job_worker/deployment.md § Live spectator hub` for the cutover walkthrough. The Realtime path is the rollback target — kept live until the hub deploy is stable.

### Watch out

- **Privacy-zone clipping must happen before the spectator sees the ping.** Realtime path: the RLS policy on `live_run_pings` invokes `clip_track_for_user`. WS path: `SupabaseZoneFetcher` clips on the hub before broadcast. Both routes are owner-blind by design (decisions §33).
- **Live tracking battery drain** is the main risk of this feature. Every-3-second GPS → INSERT/send ≈ 5% extra battery per hour. Roadmap § "Open risks" says the feature must be opt-in per run, never on by default.
- **The public `/live/{run_id}` page works without auth.** No user JWT, no session cookie. The hub treats `run_id` as a bearer token; the Realtime channel name is `live:{run_id}` (anyone with the run id can subscribe — shareability is the feature).
