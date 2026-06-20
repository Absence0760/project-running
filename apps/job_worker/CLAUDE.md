# job_worker — AI session notes

Generic Go service that drains the `jobs` queue (migration
`20260609_001_run_match_pipeline.sql`). Kinds today: `map_match`
(server-side OSRM map matching), `token_refresh` (Strava OAuth
rotation, replaces the `refresh-tokens` Edge Function), `strava_event`
(per-activity ingest enqueued by the `/v1/strava/webhook` endpoint,
replaces the `strava-webhook` Edge Function), `photo_process` (EXIF
strip on uploaded run photos), `club_photo_process` (the `club_photos`
sibling of `photo_process` — same download → strip → 512w thumbnail →
PATCH against the `club-photos` bucket + `club_photos` table, migration
`20270301_001`), `notification_email` (the email
delivery channel for the notifications inbox + event-day reminders —
roadmap Phase 4b, `decisions.md § 117`), `lifecycle_email`
(transactional/relationship mail with no notifications row — the welcome
on signup today, weekly digest / re-engagement later; keyed by a template
name, `decisions.md § 119`), `safety_email` (safety-contact confirm +
finish alerts, `decisions.md § 131`), and `web_push` (the browser Web Push
delivery channel — sibling of `notification_email` over the same
notifications rows; encrypted RFC 8291 messages signed with a VAPID key,
`decisions.md § 133` / migration `20261219_001`). Data-export will land as an
additional kind in `internal/worker.go`'s dispatch when that Edge
Function moves per
[`../../docs/product/roadmap.md`](../../docs/product/roadmap.md) §214.

## Scope — read before writing code

**Two concerns share this binary:**

1. **Job-queue drain** — claims `jobs` rows, runs the matcher, writes
   `run_matched_tracks`. This is the original concern; the worker is
   the *only* place writes to those tables originate. Both are
   RLS-locked and the SECURITY DEFINER functions
   (`claim_next_job`, `finish_job`, `defer_job`) are revoked from
   PUBLIC and granted only to `service_role`. The worker auths with
   the service role key.
2. **Live spectator hub** — in-process pub/sub keyed by `run_id`. The
   mobile recorder POSTs ping bodies to `POST /v1/live/{run_id}/push`;
   spectators stream pings over `GET /v1/live/{run_id}/subscribe`
   (WebSocket) or fetch the last-known position via
   `GET /v1/live/{run_id}/snapshot`. Implementation lives in
   `internal/livehub/`. Today the buffer is an in-process map keyed
   by run_id; the roadmap calls for Upstash Redis pub/sub with a 24h
   TTL — the swap is mechanical because the Hub's Publish + Subscribe
   surface is the only touchpoint. **Auth** is enforced by
   `livehub.JWTAuthorizer` (HS256 over `SUPABASE_JWT_SECRET`) when
   that env var is set: pushes are owner-only (no anon path even on
   public runs); subscribes/snapshots are anon for `is_public=true`
   runs and owner-only otherwise; missing or expired tokens 403;
   unknown run ids 403; tokens signed with the wrong key 403. The
   `(user_id, is_public)` lookup is cached per-room via
   `Hub.LoadRunMeta` so a hot publisher's per-5s push is one map
   hit after warm-up. When `SUPABASE_JWT_SECRET` is empty the
   authorizer is nil — permissive mode, dev-only. **Privacy zones** are
   enforced server-side: `Server.shouldDrop` runs
   `IsInAnyZone(p.lat, p.lng, room.zones)` on every `/push`. Zones
   are fetched once per room via `SupabaseZoneFetcher` and cached
   on the room until GC. **Fail-closed** on fetch errors — a
   Supabase outage drops the ping rather than risk leaking a home
   coordinate. Mirrors the `live_run_pings_drop_in_zone` BEFORE-INSERT
   trigger on the Supabase Realtime path so both transports honour
   the same contract.

**Build here:**

- New `Matcher` implementations — see the interface in
  [`internal/matcher.go`](internal/matcher.go). `PassthroughMatcher`
  is the smoke-test default; `OSRMMatcher` (in
  [`internal/matcher_osrm.go`](internal/matcher_osrm.go)) is the
  first real engine and is selected in `main.go` when `OSRM_URL` is
  set. Valhalla / GraphHopper would each be a sibling file plus
  another env-driven branch.
- Additional job kinds — extend the switch in `Worker.dispatch`,
  extend the CHECK allowlist on `jobs.kind` (migration
  `20260822_001_jobs_kind_allowlist.sql` is the precedent), and
  extend the pgtap suite at
  `apps/backend/supabase/tests/jobs_kind_allowlist_test.sql`. The
  three steps must land together — the DB rejects an unknown kind
  at INSERT (23514) rather than at the worker's dispatch, so
  shipping a new kind without all three slips it through silently.
  `token_refresh` (sweeps expiring Strava integrations + rotates via
  `/oauth/token`) is in `handler_token_refresh.go` and is the worked
  example for "port a scheduled Edge Function into the queue".
  `notification_email` (`handler_notification_email.go` +
  `mailer.go`) is the worked example for "trigger-enqueued fan-out with
  an external transport": the notifications AFTER-INSERT trigger queues
  one job per recipient, the handler checks the
  `user_settings.prefs.email_notifications` preference, resolves the
  address via the GoTrue admin API, and sends over SMTP. Gated on
  `SMTP_HOST` — unset → jobs finish done but leave rows unstamped so a
  later email-enabled deploy can still send. Local dev points at the
  Supabase Mailpit catcher.
  `lifecycle_email` (`handler_lifecycle_email.go`) is the worked example
  for "transactional mail with no notifications row": a `{user_id,
  template}` payload, a template renderer in `mailer.go`, and a
  `lifecycle_email_log (user_id, template)` send-once guard. The welcome
  is trigger-enqueued on signup (`user_profiles` AFTER INSERT); the Pro
  receipt (`pro_welcome`) + payment-failed dunning (`payment_failed`) are
  trigger-enqueued on `user_profiles` AFTER UPDATE of the subscription
  columns (`decisions.md § 121`) and are RECURRING — they skip the
  once-per-user log (`oncePerUserTemplates` gates it to `welcome`). The
  account-deletion receipt (`account_deleted`, decisions §121) reuses this kind
  but is the one INLINE-ADDRESS template (`inlineAddressTemplates`): its payload
  carries `{email, locale}` and no `user_id` (the user is gone by send time),
  so `handleLifecycleEmail` routes it to `handleAccountDeletionReceipt`, which
  resolves the address from the payload (not GoTrue) and dedups on a SHA-256
  hash of the address via the non-cascading `account_deletion_receipts` table
  (not `lifecycle_email_log`, which cascades away with the user). All templates
  live in `email_i18n.go`, localized across six locales. A future digest reuses
  the kind with a cron enqueue + its own opt-in preference.
  `lifecycle_drip` (`handler_lifecycle_drip.go`) is the engagement sibling of
  `weekly_digest`: a NEW kind (`{user_id, template}` — `drip_onboarding` /
  `drip_reengagement` / `drip_streak`), but the SAME opt-in/suppression/
  unsubscribe rails. Cohort selection lives in SQL (`enqueue_lifecycle_drip()`,
  migration `20270223_001`, a daily pg_cron) — the handler honours a SEPARATE
  opt-IN pref (`email_lifecycle_drip`) + the `email_suppressions` hard-block,
  then renders the per-template copy with a stream-scoped RFC 8058 unsubscribe.
  Fail-closed on the unset SMTP credential, like the digest.
  `web_push` (`handler_web_push.go` + `push_render.go` + `internal/webpush/`)
  is the worked example for "second transport over the same notifications
  rows": the SAME notifications AFTER-INSERT fan-out, but a DIFFERENT enqueue
  trigger (gated on the recipient having a `push_subscription`), a SEPARATE
  preference (`push_notifications`, independent of the email one), a SEPARATE
  send-state column (`web_push_sent_at`), and a fan-out over the user's
  per-device browser subscriptions on `user_device_settings.prefs.push_subscription`.
  The transport is `internal/webpush/` — a dependency-light RFC 8291 (aes128gcm
  message encryption) + RFC 8292 (VAPID JWT) sender on stdlib crypto + the
  existing `golang-jwt`. A dead endpoint (404/410) is pruned via the
  `clear_push_subscription` RPC; a 429/5xx defers; gated on `VAPID_PUBLIC_KEY` +
  `VAPID_PRIVATE_KEY` (unset → rows stay pending). When an FCM/APNs leg lands,
  copy this shape (its own enqueue gate + `*_sent_at` column + handler).
  `strava_event` (per-activity ingest enqueued by the HTTP webhook
  endpoint at `/v1/strava/webhook`) is the worked example for
  "port a webhook Edge Function into HTTP-front + queue-back" — see
  `handler_strava_event.go` for the dispatch and
  `internal/stravahook/server.go` for the request-side validation.
  Data-export follows the request-side pattern; it doesn't fit the
  job-queue shape because the user is waiting on a signed URL.
- Live-hub extensions — Redis-backed storage (swap [`internal/livehub.Hub`](internal/livehub/hub.go)
  with a Redis pub/sub-backed variant), per-run ring buffer for
  late-joiner replay of more than the most recent ping, JWKS-based
  JWT verification if Supabase migrates the project off HS256.
- Operational concerns — backoff tuning, Prometheus metrics, leader
  election if multiple workers don't suffice. None shipped today.

**Don't build here:**

- Anything that should run on the request path. The worker is for
  background work only — synchronous user actions belong in Edge
  Functions or PostgREST.
- A second source of truth for the queue. The `jobs` table + the
  RPC trio (`claim_next_job` / `finish_job` / `defer_job`) is the
  contract; don't add a parallel queue.
- Direct Postgres connections. Everything goes through PostgREST +
  Storage REST so the worker has one transport and zero VPC-peering
  concerns when deployed to Fly.io.

## Layout

```
apps/job_worker/
├── go.mod
├── main.go                  # entrypoint: env → SupabaseClient → Worker.Run
│                            # also wires the livehub.Server alongside /health
├── internal/
│   ├── types.go             # Job, MapMatchPayload, TrackPoint, MatchedTrackRow, IntegrationRow, TokenPair
│   ├── schema/schema.go     # registry: PostgREST table names + Storage bucket names + runs.metadata keys + prefs keys (every package routes its literals through here)
│   ├── supabase.go          # PostgREST + Storage REST client (service role); exportPersonalDataSpecs is the single source of truth for the Art 20 export table list
│   ├── personal_data_export_guard_test.go # parses migrations for user_id tables; fails the build if one is missing from the export spec or the reasoned exclusion list
│   ├── strava.go            # StravaClient — /oauth/token refresh_token grant
│   ├── strava_test.go       # 4 tests: parse, error surface, malformed, default URL
│   ├── matcher.go           # Matcher interface + PassthroughMatcher stub
│   ├── matcher_test.go
│   ├── matcher_osrm.go      # OSRMMatcher — /match/v1/foot, chunked
│   ├── matcher_osrm_test.go
│   ├── worker.go            # claim → handle → finish loop; dispatch by kind
│   ├── handler_token_refresh.go  # kind='token_refresh' sweep + rotate
│   ├── handler_notification_email.go # kind='notification_email' send-or-skip
│   ├── handler_notification_email_test.go # 9 tests on gating / opt-out / idempotency
│   ├── handler_lifecycle_email.go # kind='lifecycle_email' (welcome) render + send-once
│   ├── handler_lifecycle_email_test.go # 6 tests on send / dedup / no-address / nil-sender
│   ├── handler_account_deletion_receipt_test.go # 9 tests on inline-address send / hash send-once / no-address / send-error / nil-sender / locale / no-prefs-link
│   ├── mailer.go            # EmailSender iface + SMTPSender + pure render/preference logic
│   ├── mailer_test.go       # 6 tests on emailMode / shouldEmail / render / MIME
│   ├── handler_safety_email.go # kind='safety_email' confirm + finish alerts (decisions §131)
│   ├── handler_web_push.go  # kind='web_push' — send-or-skip over the notifications rows; prune dead subs
│   ├── handler_web_push_test.go # 14 tests on gating / opt-out / no-sub / prune / transient / idempotency
│   ├── push_render.go       # pushMode / shouldPush (push_notifications pref) + webPushPayload JSON render
│   ├── webpush/             # dependency-light Web Push sender (RFC 8291 aes128gcm + RFC 8292 VAPID)
│   │   ├── webpush.go       # Sender.Send: ECDH+HKDF+AES-GCM encrypt + ES256 VAPID JWT + POST
│   │   └── webpush_test.go  # round-trip decrypt + VAPID-JWT verify + status classification
│   ├── handler_weekly_digest.go # kind='weekly_digest' — opt-in + suppression gate, bounded summary render (GATED on SMTP); engagementUnsubURL helper shared with the drip
│   ├── handler_weekly_digest_test.go # 13 tests on opt-in / suppression hard-block / fail-closed / quiet-week / unsubscribe header
│   ├── handler_lifecycle_drip.go # kind='lifecycle_drip' — onboarding/re-engagement/streak nudges; opt-IN email_lifecycle_drip + suppression gate (GATED on SMTP); cohort selection is in SQL, not here
│   ├── handler_lifecycle_drip_test.go # 14 tests on opt-in / digest-opt-in-does-not-imply-drip / suppression / per-template / fail-closed / unsubscribe
│   ├── digest_builder.go    # EnqueueAllWeeklyDigests — selects opted-in recipients, chunked bulk-enqueues jobs (UNSCHEDULED; pg_cron is the CISO/counsel-gated step)
│   ├── digest_builder_test.go # 5 tests on enqueue / no-candidates / select-error / chunking / failing-chunk skip
│   ├── digesttoken/         # stateless keyed-HMAC RFC 8058 unsubscribe token (no PII, no table, constant-time verify); STREAM-AWARE
│   │   ├── token.go         # Mint(secret, stream, userID) / Verify over (stream, userID) — scopes: StreamWeeklyDigest, StreamLifecycleDrip
│   │   └── token_test.go    # 9 tests: round-trip / wrong-user / wrong-secret / wrong-STREAM / tamper / fail-closed / no-PII
│   ├── unsubscribe/         # unauth RFC 8058 one-click opt-out endpoints; STREAM-AWARE (/unsubscribe/weekly-digest + /unsubscribe/lifecycle-drip off one shared secret)
│   │   ├── server.go        # per-stream verify → flip that stream's pref off + insert suppression; fail-closed on bad/missing/cross-stream token
│   │   └── server_test.go   # 13 tests: valid GET/POST / drip / cross-stream / RegisterRoutes / bad / missing / cross-user / no-secret 503 / no-address / 500
│   ├── bouncehook/          # provider bounce/complaint webhook (POST /v1/email/bounce → email_suppressions)
│   │   ├── server.go        # shared-secret + rate-limited; classify Resend/SES event → suppress hard bounce + complaint (soft bounce no-op)
│   │   └── server_test.go   # 16 tests: resend/ses bounce+complaint / soft-bounce no-op / dedupe / 503 / 403 / 405 / 400 / 500 / classify branches
│   ├── handler_strava_event.go   # kind='strava_event' fetch + insert + upload
│   ├── handler_strava_event_test.go # 10 tests on the ingest dispatch
│   ├── handler_photo_process.go  # kind='photo_process' run-photo EXIF strip + 512w thumbnail
│   ├── handler_club_photo_process.go # kind='club_photo_process' club-photo EXIF strip + 512w thumbnail (sibling of photo_process, against the club-photos bucket + club_photos table)
│   ├── handler_club_photo_process_test.go # 7 tests mirroring the run-photo handler
│   ├── worker_test.go       # table-driven test using a fake Backend; +8 token_refresh tests
│   ├── livehub/             # live spectator pub/sub + HTTP + WebSocket
│   │   ├── types.go         # Ping wire shape
│   │   ├── hub.go           # in-process subscribe / publish / GC + per-room zone + run-meta cache
│   │   ├── hub_test.go      # 10 hub unit tests, race-clean
│   │   ├── privacy.go       # PrivacyZone + IsInAnyZone (haversine)
│   │   ├── privacy_test.go  # 8 privacy unit tests
│   │   ├── zones.go         # ZoneFetcher iface + SupabaseZoneFetcher
│   │   ├── runmeta.go       # RunMeta + RunMetaFetcher + SupabaseRunMetaFetcher (authorizer's lookup)
│   │   ├── auth.go          # JWTAuthorizer — Supabase HS256 JWT verify + owner check
│   │   ├── auth_test.go     # 16 unit + 1 end-to-end test for the authorizer
│   │   ├── server.go        # HTTP routes for /v1/live/{run_id}/* + zone clip
│   │   ├── server_test.go   # 16 httptest + WebSocket integration tests
│   │   ├── iface.go         # LivePubSub interface — both Hub + RedisHub satisfy
│   │   ├── redis_hub.go     # Redis-backed pub/sub variant (multi-replica fan-out + 24h TTL)
│   │   └── redis_hub_test.go # 14 miniredis-backed tests on the Redis path
│   ├── stravahook/          # Strava webhook HTTP endpoint (POST → enqueue strava_event)
│   │   ├── server.go        # GET handshake + POST validate / freshness / dedupe / enqueue
│   │   └── server_test.go   # 13 httptest cases on every gate + the handshake
│   ├── dataexport/          # GDPR data-export HTTP endpoint (POST /v1/export)
│   │   ├── server.go        # JWT auth + tiered rate limit + CSV/GPX-zip builder + signed URL
│   │   └── server_test.go   # 14 tests (9 httptest + 5 pure builder/helpers)
│   └── premium/             # Pro-only HTTP endpoints (POST /v1/premium/{vo2max,race-predictor,recovery,training-plan})
│       ├── server.go        # Shared JWT + Pro-tier gate + 4 handlers; Backend leaf interface
│       ├── compute.go       # Pure helpers — Daniels VDOT, Riegel, EWMA training load, recovery advice, plan generator
│       ├── compute_test.go  # 16 pure-compute tests
│       └── server_test.go   # 20 httptest tests (auth gates + 4 happy paths + validation)
├── osrm/                    # local OSRM dev stack (compose + Makefile)
├── Dockerfile               # multi-stage; final image is distroless
├── README.md                # local-run instructions
└── CLAUDE.md                # this file
```

## Concurrency

Multiple workers can run side by side. `claim_next_job` does
`for update skip locked` so two simultaneous claims each get a
distinct job rather than blocking. No leader election or partitioning
is needed for the foreseeable scale.

## Error classification

The worker reports back to the queue on every job:

- **success** → `finish_job(done, nil)`
- **transient** (5xx, dial timeout, connection refused, deadline) →
  `defer_job(delay_seconds, msg)`. `attempts` is *not* decremented;
  the per-job `max_attempts` ceiling still applies. Once the budget is
  spent, `defer_job` lands the row in `status='failed'` (not back in
  `queued`, where `claim_next_job`'s `attempts < max_attempts` gate
  would strand it un-claimable and invisible) so the `jobs-failed-alert`
  cron sees it — migration `20261201_001_jobs_failed_alert.sql`.
- **permanent** (4xx, malformed payload, missing run, RLS denial) →
  `finish_job(failed, msg)`.

The classifier lives in `isTransient` in `worker.go`. It branches on
`HTTPError.StatusCode` first (typed error from `supabase.go`), then
falls back to substring sniffing the message for network-layer
markers — same shape as the watch's drain classifier in
`apps/watch_wear/.../RunViewModel.kt`.

## Re-upload race

Closed at the DB level via a `source_track_url` CAS (migration
`20260611_001_run_matched_tracks_cas.sql`). The trigger writes
`NEW.track_url` into `run_matched_tracks.source_track_url` on every
insert and every reset; the worker captures `runs.track_url` at job
start and PATCHes the row conditionally on
`?source_track_url=eq.<value>` via `Prefer: return=representation`.
A re-upload that lands between the worker's read and write changes
`source_track_url`, the conditional PATCH affects 0 rows, the worker
client returns `ErrStaleSourceTrackURL`, and the worker logs +
returns `nil` — the OLD job ends cleanly via `finish_job(done)`,
the NEW job already queued by the trigger produces the right
result.

The pre-write `track_url` recheck is kept as a fast path: it skips
the upload + PATCH entirely when the change is already visible at
read time, saving a wasted Storage write. Defence in depth — the
CAS is what closes the actual race; the recheck is for niceness.

Pinned by:
- `TestWorker_ReuploadDuringMatchDiscardsResult` — recheck path.
- `TestWorker_StaleSourceTrackURLDiscardsResult` — CAS path
  (recheck would have passed but the row was reset under the
  worker's feet between recheck and PATCH).

If the matched gz was uploaded before the CAS rejected the PATCH,
the file is now an orphan in Storage. The worker logs the path so
an operator can sweep these later; an automated cleanup job would
be the natural follow-up.

## Deploying to production

See [deployment.md](deployment.md) — three Fly.io apps under one `runonward` org: the worker + OSRM talk over 6PN; GraphHopper (the `foot` round_trip engine for "Generate a route by distance", config in [`graphhopper/`](graphhopper/)) is reached by the generate-route Lambda on AWS over **public https**, not 6PN. Covers fly.toml shapes, Volume + graph build, weekly OSRM rebuild, secrets, rollback, DR, and the proposed `release-worker.yml` / `release-osrm.yml` / `release-graphhopper.yml` workflows.

## Local dev

See [README.md](README.md) for the smoke-test recipe.

```bash
# From apps/job_worker:
go test ./...                   # unit tests, no network
go vet ./...
go build .                      # produce a binary in cwd

# Against a running supabase stack at apps/backend:
SUPABASE_URL=http://127.0.0.1:54321 \
  SUPABASE_SERVICE_ROLE_KEY=$(cd ../backend && supabase status -o env | \
    awk -F= '/^SERVICE_ROLE_KEY=/ {gsub(/"/,"",$2); print $2}') \
  WORKER_ID=dev \
  go run .
```

`main.go` auto-loads `.env.development` (committed, non-secret local
defaults — the loopback Supabase URL + demo service-role key + `WORKER_ID=dev`)
at startup, layered under a gitignored `.env.local` (your real keys) and the
shell env, both of which win. So a bare `go run .` against a running local
stack works out of the box; the explicit-export form above is only needed to
override a value. Repo-wide convention: decisions §137.

Stops on SIGINT / SIGTERM.

### Notification-email env (optional)

`notification_email` jobs send only when `SMTP_HOST` is set. To exercise
the channel against the local Supabase Mailpit catcher, add to the
`go run .` invocation above:

```bash
SMTP_HOST=127.0.0.1 SMTP_PORT=54325 \
  SMTP_FROM='Threkir <noreply@threkir.com>' \
  APP_BASE_URL=http://localhost:7777
```

Then insert a notification (e.g. `psql … -c "insert into notifications
(user_id, kind) values ('<uid>', 'message')"`) and watch it arrive at
`http://127.0.0.1:54324`. Production also sets `SMTP_USERNAME` +
`SMTP_PASSWORD` (Resend / SES SMTP); `SMTP_PORT` defaults to 587 and
`APP_BASE_URL` to `https://threkir.com` when unset. With `SMTP_HOST`
unset the worker drains `notification_email` jobs to done but leaves the
notification rows unstamped (pending) so a later email-enabled deploy
can still send them.

### Web-push env (optional)

`web_push` jobs send only when the VAPID keypair is set. Generate one with any
web-push keygen (`npx web-push generate-vapid-keys`, or `openssl`), put the
public half in apps/web's `PUBLIC_VAPID_PUBLIC_KEY` (so the browser subscribes),
and pass all three to the worker:

```bash
VAPID_PUBLIC_KEY=<base64url-uncompressed-point> \
  VAPID_PRIVATE_KEY=<base64url-32-byte-scalar> \
  VAPID_SUBJECT=mailto:ops@threkir.com \
  APP_BASE_URL=http://localhost:7777
```

Subscribe a browser (web Settings push toggle → stores the subscription on
`user_device_settings.prefs.push_subscription`), insert a notification for that
user, and the system notification appears. `VAPID_SUBJECT` defaults to
`mailto:ops@threkir.com`; a bad keypair fails the worker at startup (exit 2). With
the keypair unset the worker drains `web_push` jobs to done but leaves the rows
unstamped (pending) so a later push-enabled deploy can still send them.

## Before reporting a task done

- `go vet ./...` clean.
- `go test ./...` passes. CI gates this — the `test-worker` job in
  `ci.yml` runs `go vet ./...` + `go test ./...` (working-directory
  `apps/job_worker`) on every PR, so a Go-side guard like
  `internal/personal_data_export_guard_test.go` now fails the build, not
  just your local run. Still run the suite locally before declaring done.
- If you added a new job kind: extended the `Worker.dispatch` switch,
  added a handler test, and updated the `kind` allowlist in any
  client-side enqueue path that reaches into `jobs` directly (only
  the runs trigger does today).
- If you swapped in a real `Matcher`: verified the new implementation
  uploads a valid gzipped JSON array (worker's `parseTrack` will fail
  on invalid bytes, which is the right behaviour — but a regression
  there would surface as queued jobs flipping to `failed`).
- Updated [../../docs/product/roadmap.md](../../docs/product/roadmap.md) §515-531 with
  the engine choice or wiring change.
