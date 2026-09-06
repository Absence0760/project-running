# Job worker + OSRM deployment plan

How the Go worker at `apps/job_worker/` and the OSRM map-matching engine at `apps/job_worker/osrm/` run in production.

Operational counterpart of [`apps/job_worker/CLAUDE.md`](CLAUDE.md) (worker contract, scope, error classification) and [`apps/job_worker/README.md`](README.md) (local dev recipe). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md).

**Status: worker live, OSRM plan.** The worker deployed 2026-07-21 as Fly app `threkir-worker` (org `project-running`, region `ord`, single machine): the queue backlog drained with SMTP unset, and the live hub passed the full smoke matrix (JWKS auth boundaries, privacy-zone clip, WS fan-out + snapshot replay, origin allow-list, rate limit). Client cutover has NOT happened — `PUBLIC_LIVE_HUB_URL` / `LIVE_HUB_URL` stay unset pending the owner's go. (The former pre-cutover log-redaction gate is closed: subscriber JWTs ride the `Sec-WebSocket-Protocol` header instead of the URL — decisions §281 — and Fly surfaces no per-request access logs anyway.) OSRM remains undeployed (`OSRM_URL` unset → passthrough).

**Deploy with `--ha=false`.** On a first deploy (or scale-from-zero) Fly auto-creates a second machine "for high availability" — wrong for this app: the in-process hub shares no state across machines, so a publisher on one and a subscriber on the other silently never connect. Single machine until `REDIS_URL` lands (which is what makes multi-replica fan-out correct).

---

## Two services, one pair

The worker is small (single Go binary, ~9 MB distroless) and the OSRM engine is heavy (~50 MB binary plus a multi-GB graph). They have different sizing, different update cadences, and different failure modes — they want to be separate Fly.io apps even though they always deploy together.

```
Fly.io organisation: project-running
├── job_worker           (1+ machines, shared-cpu-1x, 256 MB RAM)
│   ├─ Queue drain: claims `jobs` rows over Supabase REST + Storage
│   ├─ Live hub HTTP + WebSocket on :8080 (Fly TLS-terminates at :443)
│   │   └─ public surface: POST /v1/live/{run_id}/push,
│   │                      GET  /v1/live/{run_id}/snapshot,
│   │                      GET  /v1/live/{run_id}/subscribe (WS)
│   │   └─ also serves /health for Fly's HTTP check
│   └─ talks to OSRM over Fly's 6PN private network
└── osrm                 (1 machine, performance-2x, 8 GB RAM)
    └─ Volume mounted at /data — holds the extracted graph
    └─ NO public route
```

The live hub shares the worker's binary by design — both speak the same Supabase REST stack and the hub's in-process pub/sub state is tiny (a map keyed by `run_id` with a few hundred bytes per active room). When the hub's storage moves to Upstash Redis (see `CLAUDE.md`), the binary stays unified; only the `Hub` implementation swaps.

**GDPR before enabling external Redis:** `internal/livehub/redis_hub.go` activates when `REDIS_URL` is set. Live pings carry GPS coordinates (personal data), so pointing `REDIS_URL` at a hosted Upstash instance is a cross-border processor transfer — execute Upstash's DPA from the account console and record the date in [`docs/compliance/sub-processors.md`](../../docs/compliance/sub-processors.md) **before** the prod cutover. The in-process hub (no `REDIS_URL`) has no such transfer.

Why same Fly.io organisation: 6PN gives them a private network at no cost. The worker calls `http://osrm.internal:5000/match/v1/foot/...` and never goes through public internet.

Why the worker app stays separate from OSRM: independent restart (worker → 5 s, OSRM → 90 s as graph re-mmaps), independent scaling (more workers without paying OSRM RAM each time), independent rollout (engine retune doesn't redeploy the queue drainer).

---

## Provider — Fly.io

**Provider:** Fly.io.

**Why not Cloud Run:** request-response only, no long-lived processes. The worker polls `claim_next_job` continuously; the OSRM container holds graph state in RAM. Both fit Fly.io machines better than serverless functions.

**Why not a dedicated VM:** Fly.io has the same cost-per-RAM as a small DO/Linode/EC2 with batteries-included logging, secrets, and zero-downtime deploys. We'd reach for a dedicated VM only if the OSRM RAM goes past ~64 GB — at which point we're talking continent-scale extracts and the discussion shifts.

**Region:** `ord` (Chicago). The rule is *follow Postgres, not the team* — the worker round-trips to Supabase on every job claim, zone lookup, and premium request, so the deciding factor is distance to the database. The Supabase project (`Project Runner`) sits in **East US (Ohio)**, which makes `ord` or `iad` right and `lhr` roughly 80 ms per round trip worse. Spectator WebSocket latency does not enter into it: that terminates at Fly's edge wherever the viewer is.

If the database ever moves to an EU region, this flips back to `lhr`/`cdg` — and the worker should move with it.

> **Sibling services still say `lhr`.** `osrm/fly.toml`, `graphhopper/fly.toml`, and `apps/graph_cycle/fly.toml` were all written against the old assumption. The 6PN intra-DC claim below only holds if they share the worker's region, so reconcile them before any of the three deploys — see the OSM-extract note in the OSRM section, since a UK extract served from a US region is a separate judgement call.

**Account org**: create a `project-running` Fly.io org. Both apps live under it. Billing is per-org; secrets are per-app. The name matches the AWS account slug so the estate reads consistently across providers — Fly org slugs are embedded in billing and token scoping and are painful to change later, so get it right at creation.

---

## Worker app — `job_worker`

### Sizing

- `shared-cpu-1x`, 256 MB RAM. The worker is mostly idle on a poll loop; matching is delegated to OSRM. RAM ceiling is during a Storage upload of a matched gzip (~hundreds of KB in flight). The hub's in-process pub/sub state is negligible — a `map[string]*room` with at most a few hundred bytes per active run.
- 1 machine baseline. Add a second when the active set in `jobs.status='queued' AND scheduled_at <= now()` regularly exceeds ~50, or when concurrent live-spectator viewers regularly exceed ~500. (Per-room fan-out is in-process, so a second machine roughly halves the per-machine viewer load.)
- `auto_start_machines = true`, `auto_stop_machines = false`. The worker is supposed to be always-on; auto-stop would just delay the next claim by the cold-start time. Live-hub WS subscribers also drop if the machine stops.

### `fly.toml`

Lives at [`fly.toml`](fly.toml). Shape (matches the actual checked-in file — keep this snippet in sync if you edit it):

```toml
# Fly app names allow only lowercase letters, numbers and dashes, so the
# name differs from the apps/job_worker directory.
app = "threkir-worker"
primary_region = "ord"

[build]
dockerfile = "Dockerfile"

[env]
# WORKER_ID deliberately absent: Fly does not interpolate variables in
# [env], and main.go's hostname fallback already yields the per-machine
# ID on Fly.
# OSRM_URL deliberately unset while the hub deploys ahead of osrm —
# restore it when the osrm app exists. See "Deploying the hub before
# OSRM" below.
# Comma-separated WS Origin allow-list. Anything not listed gets a 403 at
# the WS handshake. Production clients: apps/web prod + preview.
LIVEHUB_ALLOWED_ORIGINS = "https://threkir.com,https://www.threkir.com,https://preview.threkir.com"

[[services]]
internal_port = 8080
protocol = "tcp"
auto_start_machines = true
auto_stop_machines = false
min_machines_running = 1

[[services.ports]]
port = 443
handlers = ["tls", "http"]   # Fly's "http" handler transparently
                             # upgrades WS frames; the server handles
                             # Sec-WebSocket-Accept via coder/websocket.

[[services.ports]]
port = 80
handlers = ["http"]
force_https = true

[[services.tcp_checks]]
interval = "30s"
timeout = "5s"
grace_period = "10s"

[[services.http_checks]]
# /health JSON body: {"status":"ok"} | {"status":"stale"} when the poll
# loop is wedged. Fly auto-restarts after 3 consecutive failures.
interval = "15s"
timeout = "5s"
grace_period = "20s"
method = "get"
path = "/health"
protocol = "http"
restart_limit = 0

[[vm]]
size = "shared-cpu-1x"
memory = "256mb"
cpus = 1
```

### Secrets

Set them from stdin, never as command arguments — `flyctl secrets set` puts the service-role key into shell history and into `ps` output while it runs. This mirrors the rule `bin/secret-set.sh` already enforces for the sops path.

```bash
flyctl secrets import --app threkir-worker
```

Then paste the following and press Ctrl-D (real values, no quotes):

```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SECRET_KEY=<sb_secret_… key; a legacy service_role JWT also works>
STRAVA_CLIENT_ID=<optional — only for token_refresh jobs>
STRAVA_CLIENT_SECRET=<optional — Strava OAuth rotation>
```

`SUPABASE_JWT_SECRET` is deliberately absent from that list — see below: the prod project signs ES256, so the hub verifies against the JWKS derived from `SUPABASE_URL` and the shared-secret variable only matters for a legacy HS256 project or a local stack.

`flyctl secrets list --app threkir-worker` confirms names and digests afterwards; values are never echoed back.

**Where these live in the Supabase dashboard.** The old single "Settings → API" page has been split, so navigate by direct link rather than by sidebar:

| Value | Page |
|---|---|
| `SUPABASE_URL` | `…/project/<ref>/settings/api-keys` — also just `https://<ref>.supabase.co`, and it is not secret |
| `SUPABASE_SECRET_KEY` | `…/project/<ref>/settings/api-keys` — take the **`sb_secret_…`** key. A legacy `service_role` JWT also works: `internal/supakey` sends an `sb_…` key as `apikey` alone (the docs require new-format keys off the `Authorization` header — decisions §280) and a legacy JWT as both `apikey` and `Authorization: Bearer` |
| `SUPABASE_JWT_SECRET` | `…/project/<ref>/settings/jwt` — the shared HS256 secret |

**`SUPABASE_JWT_SECRET` is optional, and is not the anon key.** The anon key is a *token* signed by the secret; the secret is the signing key itself. A quick tell: the secret has no dots, the anon key is `eyJ…` with two.

**The production project signs with ES256, so there is no shared secret to set.** Its JWKS publishes a single ECC P-256 key. `internal/supajwt` verifies against that JWKS automatically — derived from `SUPABASE_URL`, no extra config — so `SUPABASE_JWT_SECRET` is left unset in production and only matters for a legacy HS256 project or a local stack. See [decisions.md § 276](../../docs/architecture/decisions.md).

Confirm which scheme a project uses before deploying:

```bash
curl -s https://<ref>.supabase.co/auth/v1/.well-known/jwks.json | jq '.keys[] | {alg, kty, crv, kid}'
```

An `ES256` / `RS256` key means JWKS verification and no secret. An empty key set means the project is still on the legacy HS256 secret, which then must be set.

`SUPABASE_SECRET_KEY` is **multi-use**: the worker reads it to claim jobs (PostgREST RPCs `claim_next_job` / `finish_job` / `defer_job` are granted only to `service_role`), the live hub reads it via `SupabaseZoneFetcher` to fetch a runner's privacy zones for server-side ping clipping, AND it powers `SupabaseRunMetaFetcher` (the per-room `(user_id, is_public)` lookup that backs the JWT authorizer). One secret, one identity — there's no per-concern split.

`SUPABASE_JWT_SECRET` is the HS256 signing key a *legacy* Supabase project mints user tokens with. This project is on ES256, so it stays unset and the JWKS path (derived from `SUPABASE_URL`) does the verifying. **The hub refuses to accept production traffic when neither path resolves** — the authorizer goes nil and the hub falls back to permissive mode, which is fine for a local smoke flow and a hard blocker for the public route. `LIVEHUB_REQUIRE_AUTH=1` turns that into a refusal to boot. Confirm the boot log shows `livehub auth: enabled (Supabase JWT)` and a `verification=` value naming the scheme you expect.

`OSRM_URL` and `LIVEHUB_ALLOWED_ORIGINS` belong in `[env]` (not secrets) because the values themselves are non-sensitive and we want them visible in `flyctl status`.

### `LIVEHUB_DISABLE_AUTH` — local / CI only

Setting `LIVEHUB_DISABLE_AUTH=1` discards all token verification and runs the
hub permissively. It exists because the e2e stack
(`apps/web/tests-e2e/scripts/start-livehub.sh`) needs anonymous pushes, and
emptying `SUPABASE_JWT_SECRET` no longer achieves that: the hub also derives a
verifier from `SUPABASE_URL` via JWKS, and `SUPABASE_URL` has to stay set for
zone and run-meta lookups.

**Never set it in production.** `LIVEHUB_REQUIRE_AUTH=1` and
`LIVEHUB_DISABLE_AUTH=1` together make the binary refuse to boot, which is the
intended interaction — the prod sentinel wins.

### Deploying the hub before OSRM

The live spectator hub and the queue drainer share one binary, so the hub can reach production before the `osrm` app exists. When it does, **`OSRM_URL` must be unset** — the checked-in `fly.toml` ships it commented out for exactly this reason.

Pointing at an `osrm.internal` that doesn't resolve would fail every `map_match` job and leave it retrying on a loop. Unset, `main.go:279` selects `PassthroughMatcher`: map-matching becomes a no-op, the boot log reads `"matcher selected" engine=passthrough`, and runs still ship — just without the snapped line. That is the correct degraded state, not a bug.

Restore the line when `osrm` deploys, and expect the boot log to flip to `engine=osrm`.

### Job kinds + cutover from Edge Functions

The worker dispatches by `jobs.kind`. Today:

| Kind | Source | Notes |
|---|---|---|
| `map_match` | `runs` AFTER INSERT/UPDATE trigger | Shipped. OSRM matcher behind `OSRM_URL`. |
| `token_refresh` | pg_cron `enqueue-token-refresh` (migration `20260821_001`) | Replaces the `refresh-tokens` Edge Function. Strava OAuth rotation. Requires `STRAVA_CLIENT_ID` + `STRAVA_CLIENT_SECRET`. |
| `strava_event` | `POST /v1/strava/webhook` on the Go service | Replaces the `strava-webhook` Edge Function. The HTTP endpoint validates URL secret + verify-token + freshness + dedupes via `webhook_events`, then enqueues a job; the worker does the activity fetch + Storage upload + runs insert async. Requires `STRAVA_CLIENT_ID` / `_SECRET` (Strava API) + `STRAVA_WEBHOOK_SECRET` / `STRAVA_VERIFY_TOKEN` (URL-side gates). |
| `photo_process` | `run_photos` AFTER INSERT trigger (migration `20260825_001`) | Server-side EXIF strip + 512w thumbnail for uploaded run photos. Downloads from the `run-photos` bucket, re-uploads the stripped JPEG in place, uploads a `{owner}/{photo_id}_512.jpg` thumbnail, PATCHes `run_photos.thumb_512_path`. No extra env. |
| `route_photo_process` | `route_photos` triggers (migration `20270224_001`) | The route sibling of `photo_process` — same download → strip → 512w thumbnail → PATCH, against the `route-photos` bucket + `route_photos` table. Two enqueue triggers cover the web (insert-with-path) and mobile (insert-placeholder-then-PATCH-path) upload shapes. No extra env. |
| `club_photo_process` | `club_photos` AFTER INSERT + AFTER UPDATE OF `storage_path` triggers (migration `20270301_001`) | The `photo_process` sibling against the `club-photos` bucket + `club_photos` table. Same download → strip → thumbnail → service-role PATCH. The AFTER-UPDATE trigger catches the mobile insert-then-PATCH placeholder path. No extra env. |
| `notification_email` | `notifications` AFTER INSERT trigger `notifications_enqueue_email` (migration `20261130_001`) | One job per notification; the handler re-checks the recipient's per-kind email preference at send time. |
| `web_push` | `notifications` AFTER INSERT trigger (migration `20261219_001`) | Same rows as `notification_email`, own `web_push_sent_at` guard. Enqueued only when the recipient has a browser subscription. |
| `native_push` | `notifications` AFTER INSERT trigger (migration `20270212_001`) | APNs / FCM sibling of `web_push`, own `native_push_sent_at` guard. With the credentials unset the worker drains the jobs to `done` and leaves the rows pending, so a later credentialed deploy can re-send. |
| `lifecycle_email` | SQL at the lifecycle moment — welcome (migration `20261202_001`), subscription state changes (`20261203_001`) | Not a queue-wide sweep: each moment enqueues its own row. |
| `lifecycle_drip` | pg_cron `enqueue-lifecycle-drip` → `enqueue_lifecycle_drip()` (migration `20270223_001`) | The onboarding drip series. Dedupes against already-sent steps. |
| `weekly_digest` | pg_cron `enqueue-weekly-digest` → `enqueue_weekly_digests()` (migration `20270220_001`) | Monday 08:00 UTC, one job per subscribed user. |
| `safety_email` | Safety-contact escalation (migration `20261218_001`) + pg_cron `enqueue-safety-overdue-emails` every 5 min (`20270401_001`) | Trusted-contact notification for an overdue or finished run. |
| `safety_sms` | The SMS sibling of `safety_email` (migration `20270410_001`) | Requires the SMS provider env; without it the handler no-ops rather than failing the job. |
| `data_export` | `enqueue_data_export()`, called by `POST /v1/export/jobs` on this service (migration `20270603_001`) | The Art 20 archive build. See the endpoint table below. |
| `export_blob_reap` | pg_cron `enqueue-export-blob-reap` → `enqueue_export_blob_reap()` at 04:13 UTC (migration `20270708000010`) | The Art 20 retention **erasure**. Lists the `exports` bucket through the Storage API and deletes objects past 7 days, because a `storage.objects` row delete is not an object delete ([decisions § 1049](../../docs/architecture/decisions.md)). Singleton — a night the worker was down leaves one queued job, not a stack. Empty payload = the `exports` bucket at the default window; an operator can scope a run with `{"bucket":"exports"\|"runs","prefix":"<uid>","retention_days":N}`, and no other bucket is accepted. No extra env. |

`Worker.dispatch` in [`internal/worker.go`](internal/worker.go) is the authoritative list; `internal/worker_dispatch_coverage_test.go` fails the build if it and `jobs_kind_chk` disagree in either direction, so this table cannot silently fall behind by a whole kind again.

**Data export** is the other Edge-Function move that lives in the Go service:

| Endpoint | Replaces | Notes |
|---|---|---|
| `POST /v1/export/jobs` on the Go service | `export-data` Edge Function | JWT-authed (same `SUPABASE_JWT_SECRET` the live hub uses). Tiered rate limit (free 2/h, pro 8/h) via `check_rate_limit_tiered`; an export already in flight is returned with `reused: true` and spends no token. Answers **202** with a job id and builds nothing on the caller's connection — the archive is a `data_export` job the worker drains. Body shape: `{format: 'csv'\|'gpx'\|'backup'}`. **No run cap and no per-section row ceiling** since [decisions § 708](../../docs/architecture/decisions.md) — every section is read page by page and written as it arrives, so peak memory is one chunk plus the blob in flight and does not grow with the history. |
| `GET /v1/export/jobs/latest` on the Go service | — | The subject's most recent export: `{status, job_id, format, requested_at}` plus, on `ready`, `{url, expires_in, count, total, complete}`. Streams the archive into `exports/{user_id}/exports/<ts>.{csv,zip}` in 6 MiB tus chunks and mints the 10-min signed URL **here**, so the clock starts when the subject asks rather than when the worker finished. `stalled` is derived at read time, never stored. |

**The synchronous `POST /v1/export` was deleted 2026-08-24** ([decisions § 724](../../docs/architecture/decisions.md)). It held the caller's connection open for the whole build and survived § 717 only for the un-migrated mobile client; both clients enqueue now. A deploy that still has clients calling it will see 404s — the rollback is the `export-data` Edge Function, which is unchanged and still synchronous.

**Operator note — the artifact bucket and its ceiling.** The export writes to the `exports` bucket (migration `20270602_001`), not `runs`: `file_size_limit` is per bucket, and `runs` caps an object at 25 MB, which on a full-history archive was a tighter bound than either of the row caps § 708 deleted. `exports` admits 5 GiB, but Supabase also enforces a **project-level upload limit** (Dashboard → Storage → Settings, 50 MB by default) and the effective ceiling is the lower of the two. Raising the project limit is the one pre-deploy step that is not expressible in SQL; until it is raised, the project setting is the export's honest bound and a subject past it gets a failed upload (a 500 with no artifact), never a short archive.

**Premium endpoints** are the Pro-tier compute surface — VDOT, Riegel, training-load, plan generation. All four mount on the existing health/live-hub listener and gate on `user_profiles.subscription_tier` (`pro` + `lifetime` count; `free` → 402):

| Endpoint | Body | Notes |
|---|---|---|
| `POST /v1/premium/vo2max` | `{}` | Returns the best Daniels VDOT from qualifying runs in the last 90 days. 404 when no qualifying run (distance ≥ 3 km, duration ≥ 5 min, runlike activity). |
| `POST /v1/premium/race-predictor` | `{target_distance_m, exponent?}` | Riegel prediction from the user's best effort to the target. `exponent` defaults to 1.06. |
| `POST /v1/premium/recovery` | `{}` | 90-day daily-aggregated EWMA (CTL halflife 42, ATL halflife 7) → fitness/fatigue/form + advice string. |
| `POST /v1/premium/training-plan` | `{goal_event, goal_distance_m?, recent_5k_sec, weeks?, days_per_week?}` | Phased plan generator. `goal_event` ∈ `distance_5k`, `distance_10k`, `distance_half`, `distance_full`, `custom` (requires `goal_distance_m`). Defaults: weeks per event (8/8/12/16/12), days/week 4. |

All four endpoints share the same auth + Pro-check shape: 503 when `SUPABASE_JWT_SECRET` is unset, 405 on non-POST, 401 on missing/invalid/expired/wrong-key bearer, 402 on free tier, 500 on tier-lookup failure. Boot log reads `premium: enabled (Pro endpoints mounted at /v1/premium/*)` when `SUPABASE_JWT_SECRET` is set; without the secret it reads `premium: DISABLED — SUPABASE_JWT_SECRET unset; Pro endpoints return 503`. The compute is pure (no per-request DB writes; the only Supabase reads are the tier check and a runs projection up to 500 rows).

**Cutover recipe for `token_refresh`.** The Edge Function and the Go path can coexist — they both refresh the same rows; whichever runs first wins, the second one finds nothing expiring within an hour. To migrate:

1. Deploy the worker with the Strava env vars set. Boot log should show `strava: enabled (token_refresh dispatch armed)`. Without that line the dispatch falls through to a permanent failure on every `token_refresh` job — operator-visible in `flyctl logs`.
2. The pg_cron schedule is in source (migration `20260821_001_token_refresh_cron.sql`) — applies automatically with the rest of the schema. The cron command is dedupe-safe: hourly ticks coalesce onto a single backlog row when the worker is behind. To check it's live:
   ```sql
   select jobname, schedule from cron.job where jobname = 'enqueue-token-refresh';
   ```
3. Observe one cycle (`select * from jobs where kind='token_refresh' order by id desc limit 5;`). Confirm rows flip to `done` and that `integrations.token_expiry` for the touched rows moved forward by ~6 hours.
4. Once steady, retire any dashboard-configured cron that POSTed to the `refresh-tokens` Edge Function. Leave the Edge Function deployed for rollback; revisit in a later cleanup PR.

**Cutover recipe for the Strava webhook.** Strava sends events to a single registered URL. Cutover is operator-mediated — the operator updates the subscription URL via Strava's `/api/v3/push_subscriptions` so events flow to the Go endpoint instead of the Edge Function. Both paths write the same row shape + share the `webhook_events` dedupe table so a Strava-side retry that races between the two endpoints during the swap produces one canonical row.

1. Set the four Strava env vars as Fly secrets: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_WEBHOOK_SECRET`, `STRAVA_VERIFY_TOKEN`. Boot log should read `stravahook: enabled (Strava webhook endpoint mounted at /v1/strava/webhook)`. Without all four the endpoint returns 503 and Strava drops events.
2. Smoke-test the GET handshake:
   ```bash
   curl -i 'https://live.threkir.com/v1/strava/webhook?secret=<STRAVA_WEBHOOK_SECRET>&hub.mode=subscribe&hub.challenge=abc123&hub.verify_token=<STRAVA_VERIFY_TOKEN>'
   ```
   Expect 200 echoing `{"hub.challenge":"abc123"}`. A 403 means one of the two secrets is wrong; 503 means env vars didn't land.
3. **Re-register the Strava subscription.** Strava's webhook URL is set once via `POST /api/v3/push_subscriptions` and survives until explicitly deleted. The operator deletes the existing EF-targeted subscription and creates a new one pointing at `https://live.threkir.com/v1/strava/webhook?secret=<STRAVA_WEBHOOK_SECRET>`, with the same `verify_token` you set in the Fly secret. Strava sends the GET handshake to validate; on success the new subscription `id` is authoritative.
4. Watch `flyctl logs --app threkir-worker` for the first few real events — the endpoint enqueues a `strava_event` job in <100ms; the worker runs the activity fetch + Storage upload + runs insert async. The EF stays deployed; it'll just stop seeing traffic once Strava's subscription URL is the new one.
5. Once steady, the `strava-webhook` Edge Function can be marked Deprecated in `apps/backend/CLAUDE.md` (same treatment we gave `refresh-tokens`).

### Deploy

Today, by hand from a maintainer's laptop:

```bash
cd apps/job_worker
flyctl deploy
```

Once the `release-worker.yml` workflow lands (see § CI wiring below), tagging `worker@*` is the canonical path.

### Observability

| What | Where |
|---|---|
| Worker logs | `flyctl logs --app threkir-worker` |
| Per-machine metrics (CPU, RAM, restarts) | Fly.io dashboard → Metrics |
| Queue lag | Custom: `select count(*) from jobs where status='queued' and scheduled_at <= now()` — wire to a Better Stack heartbeat that PG-queries every minute and alerts if >50 |
| Failed jobs | A `jobs-failed-alert` pg_cron entry runs `jobs_failed_summary()` every 10 min (migration `20261201_001_jobs_failed_alert.sql`); its `{failed_count, by_kind, sample}` JSON lands in `cron.job_run_details.return_message`. **This is the safety net the async webhook needs** — a `strava_event` job that fails after the 200 ack surfaces here instead of vanishing. Route a Sentry/Slack scraper on `failed_count > 0`. Note `defer_job` now flips an exhausted-retry job to `status='failed'` so it shows up here rather than stalling un-claimable in `queued`. |
| Backlogged jobs | A `jobs-backlog-alert` pg_cron entry runs `jobs_backlog_summary()` every 10 min (migration `20270710000004`); its `{backlogged_count, by_kind, sample}` JSON lands in `cron.job_run_details.return_message`. Route a scraper on `backlogged_count > 0`. This is the gap the failed-jobs alert cannot see: `find_stuck_jobs` wants `status='running'` with a non-null `locked_at` and `find_failed_jobs` wants `status='failed'`, so a job that was never claimed at all -- `queued`, `locked_at` null, which is what a DOWN worker produces for every kind -- appears in neither. |
| Export retention overrun | An `export-retention-overrun-alert` pg_cron entry runs `export_retention_overrun()` daily at `43 4 * * *` (migration `20270710000004`), after the `13 4 * * *` reap enqueue. Route a scraper on `overrun_count > 0`. [decisions § 1172](../../docs/architecture/decisions.md) took the retention sweep off the clock deliberately, so a worker down long enough to overrun the GDPR retention window otherwise says nothing louder than a queued `jobs` row. |
| Worker liveness | Heartbeat: have the worker `update jobs set scheduled_at = ... where ...` once per claim; alert if no claim observed in >10 min while queued > 0 |
| Hub liveness | The `/health` HTTP check above also covers the hub — both concerns share the binary, so a hub crash trips the same probe |
| Hub fan-out / drop counts | Logged on each push (room subscriber count, drops from zone clip). No metrics endpoint yet — `flyctl logs` + a `jq`-friendly filter is the path until Prometheus lands |

The worker exposes a `/health` endpoint on `:8080` (override with `HEALTH_PORT`). Returns 200 + a small JSON body while the poll loop ticks, 503 once the heartbeat ages past 10 s — long enough that a job mid-handle is fine but short enough that a wedged loop is caught. `fly.toml` declares both a TCP check and an HTTP check against `/health`; Fly's auto-restart catches stale machines without a watchdog of our own.

### Rollback

```bash
flyctl releases --app threkir-worker
flyctl releases rollback <version> --app threkir-worker
```

Drains in-flight jobs and starts the previous image. Takes <60 s. Live-hub WS subscribers are dropped during the swap; clients reconnect automatically (`apps/web/src/lib/live_hub.ts` and `apps/mobile_android/lib/live_hub_client.dart` both have backoff).

---

## Live spectator hub — same binary as the worker

The hub is wired into the worker's binary (`main.go` mounts `livehub.Server.RegisterRoutes(mux)` alongside `/health`) so there's no second deploy artefact. Everything in the "Worker app — `job_worker`" section above also describes the hub. This section covers the bits that are hub-specific: the public surface, DNS, client env flip, and the privacy-zone failure mode.

### Public surface

Three routes under the hub mux:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/live/{run_id}/push` | Mobile recorder publishes a ping. Body: `{ts, lat, lng, accuracy_m?, speed_mps?, heading_deg?, distance_m?, elapsed_s?, source?}` — 4 KiB body cap + `DisallowUnknownFields`. Returns `{ok:true, fanout:N}` or `{ok:false, clipped:true, reason:"..."}` when the ping is dropped server-side (in privacy zone OR fail-closed when zone fetch errored). |
| `GET` | `/v1/live/{run_id}/snapshot` | Spectator (or reconnecting WS client) fetches the last known ping. Returns 204 when empty so a clean reconnect doesn't render stale data. |
| `GET` | `/v1/live/{run_id}/subscribe` | Spectator opens a WebSocket; the server streams every subsequent ping. WS Origin header is checked against `LIVEHUB_ALLOWED_ORIGINS` — anything not listed gets a 403 at handshake. |

The matching client transports:

- Web — `apps/web/src/lib/live_hub.ts` (auto-reconnect WS with snapshot-on-resume) gated on `PUBLIC_LIVE_HUB_URL`.
- Mobile — `apps/mobile_android/lib/live_hub_client.dart` (HTTP push only; the watch-side spectator UI lives on web) gated on `LIVE_HUB_URL`.

When the env var is empty, both clients fall back to the legacy Supabase Realtime path on `live_run_pings`. The env flip is the entire production-cutover gesture — no code change required.

### DNS

Point a subdomain at the Fly app so the public URL doesn't leak the Fly hostname:

```bash
# Tell Fly to provision a Let's Encrypt cert for the subdomain
flyctl certs add live.threkir.com --app threkir-worker

# Then add a Route 53 record (managed via infra/dns/) — CNAME to
# threkir-worker.fly.dev (or A/AAAA to the Fly anycast IPs reported by
# `flyctl ips list --app threkir-worker`).
```

Once the cert lights up green in `flyctl certs show live.threkir.com`, the hub is reachable at `https://live.threkir.com/v1/live/...`.

### Client env flip

After DNS resolves and a smoke-test push round-trips:

1. **Web** — add `PUBLIC_LIVE_HUB_URL=https://live.threkir.com` as a **GitHub Actions repo secret**. Web `PUBLIC_*` values are inlined at CI build time from GitHub Secrets (`release-web.yml` writes them into `apps/web/.env`), not from the sops blob — sops feeds Terraform/Lambda runtime env only. Rebuild + redeploy via the `web@*` tag; unset, the client stays on the Supabase Realtime path.
2. **Mobile** — set `LIVE_HUB_URL=https://live.threkir.com` in the Android + iOS release `.env` (not committed; injected at build time). Ship a new build through the Play Console / TestFlight.

Both clients pick up the new transport on next launch. Old builds with the env unset stay on the Supabase Realtime path — they continue to work because the trigger-driven `live_run_pings` table still receives pings from any recorder that hasn't been updated. Roll-forward is gradual.

### Privacy zones — fail-closed contract

`Server.shouldDrop` runs `IsInAnyZone(p.lat, p.lng, room.zones)` on every push. Zones are fetched once per room via `SupabaseZoneFetcher` (PostgREST: `runs?id=eq.<id>&select=user_id` then `user_settings?user_id=eq.<owner>&select=prefs`) and cached on the room until garbage collection.

**A Supabase outage drops the ping rather than risk leaking a home coordinate.** The response is `{ok:false, clipped:true, reason:"zone fetch failed"}`. The mobile broadcaster swallows this per the L4 best-effort contract — the run still records locally and uploads when the network recovers; only the live spectator stream goes dark. This mirrors the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger on the Supabase Realtime path so both transports honour the same contract.

### Auth contract

Enforced by `apps/job_worker/internal/livehub/auth.go` when `SUPABASE_JWT_SECRET` is set:

| Action | Public run | Private run |
|---|---|---|
| `POST /v1/live/{id}/push` | **Owner-only** (Bearer JWT, `sub == runs.user_id`). No anon path even on public runs — the recorder is the single legitimate publisher. | Owner-only. |
| `GET /v1/live/{id}/subscribe` (WS) | Anon allowed. | Owner-only (Bearer JWT, `sub == runs.user_id`). |
| `GET /v1/live/{id}/snapshot` | Anon allowed. | Owner-only. |

A `runs` row that doesn't exist denies — the hub refuses to register a phantom room for a runID Supabase has never seen. The per-room run-meta cache means the Supabase lookup runs at most once per active run; the hot publisher's per-5s push is a single map hit thereafter.

Token verification runs through `internal/supajwt`, which covers both schemes: the legacy shared HS256 secret and asymmetric ES256/RS256 keys resolved from the project's JWKS by `kid`. The allow-list handed to `golang-jwt/jwt/v5` is built from the key material actually configured, so an algorithm with no key behind it is never accepted — `alg:none` fails before any key is consulted, and a JWKS-only deploy refuses HS256 outright (which is what stops a public JWKS key being replayed as an HMAC secret). Expired tokens and tokens with no `exp` are rejected. The `auth_test.go` cases plus `internal/supajwt/verifier_test.go` pin all of this.

### Hub deploy checklist

- [x] Token verification resolves: `SUPABASE_URL` set (JWKS path) — 2026-07-21
- [x] `flyctl deploy --remote-only --ha=false` from `apps/job_worker/` — 2026-07-21, image 4.4 MB
- [x] Boot log shows `livehub auth: enabled (Supabase JWT)` with `verification="JWKS (ES256/RS256)"` — 2026-07-21
- [x] `flyctl certs add live.threkir.com --app threkir-worker` and Route 53 record (CNAME in `infra/dns`) — 2026-07-21
- [ ] `flyctl certs show live.threkir.com` shows a valid Let's Encrypt cert
- [ ] `curl https://live.threkir.com/health` returns `{"status":"ok"}` (passed against `threkir-worker.fly.dev` 2026-07-21; re-check on the custom domain once DNS + cert land)
- [x] Smoke push without auth → 403 — 2026-07-21, plus the full boundary matrix: wrong-owner 403, garbage token 403, anon-subscribe-private 403, snapshot-no-pings 204
- [x] Smoke push with an owner JWT → 202 `{ok:true}`; inside a privacy zone → 202 `{"clipped":true,"ok":true}` (throwaway fixture users, deleted after) — 2026-07-21
- [x] WS Origin allow-list verified live: `Origin: https://evil.example` → 403 at handshake, `https://threkir.com` → 101 — 2026-07-21
- [ ] `PUBLIC_LIVE_HUB_URL` set as a GitHub Actions repo secret, web redeployed
- [ ] `LIVE_HUB_URL` set in the next mobile release builds
- [ ] After the cutover, watch `flyctl logs --app threkir-worker` for a session — confirm zone-clip drop counts look sane (not 100 %, not 0 %), and that 403s only come from genuinely unauthenticated traffic (curl probes / bots) and not from legit recorders

---

## OSRM app — `osrm`

### Sizing

The driver is OSM extract size:

| Region | PBF | RAM at MLD | Fly machine |
|---|---|---|---|
| United Kingdom | ~1.2 GB | ~3 GB | `performance-2x` 8 GB |
| Greater Europe | ~25 GB | ~50+ GB | `performance-8x` 64 GB (or dedicated VM) |
| Single country (small) | ~200 MB | ~1 GB | `shared-cpu-2x` 4 GB |

**Recommended v1: UK extract on `performance-2x` 8 GB.** Tracks outside the UK return `code=NoMatch` and the worker writes `status='skipped'` — the run still ships, just without the snapped line. This keeps cost modest while we learn from the live skip rate.

### `fly.toml`

Lives at [`osrm/fly.toml`](osrm/fly.toml). Shape:

```toml
app = "osrm"
primary_region = "lhr"

[build]
image = "osrm/osrm-backend:latest"

[env]
# osrm-routed reads /data/region.osrm by default.

[[mounts]]
source = "osrm_data"
destination = "/data"

[[vm]]
size = "performance-2x"
memory = "8gb"
cpus = 2

[[services]]
internal_port = 5000
protocol = "tcp"
auto_stop_machines = false
auto_start_machines = true
min_machines_running = 1

[[services.ports]]
# 6PN-only; the public side is intentionally unreachable.
port = 5000
handlers = ["http"]

# IMPORTANT: do NOT set [[services]] with public IPs. Internal access
# via osrm.internal:5000 is what 6PN gives us. Adding a public IPv4
# would expose /match to the internet — auth-free, abuse-prone.
```

The `osrm-routed` command lives in the image; pass `osrm-routed --algorithm mld /data/region.osrm` via `processes` if Fly's defaults don't pick it up.

### Volume — `osrm_data`

```bash
# 20 GB volume in the same region as the machine
flyctl volumes create osrm_data --app osrm --region lhr --size 20
```

Holds the extracted graph (`region.osrm`, `region.osrm.cell_metrics`, etc. — ~5 GB for UK at MLD). Sized to leave headroom for re-extracting in place + a backup copy during the swap.

### Initial graph build

The graph is built once when the app stands up, then refreshed weekly. Two ways to do the initial build:

**Option A — local build, scp to volume.** Run `make download && make build` on a workstation, then push the resulting `data/region.osrm*` files into the volume:

```bash
# From apps/job_worker/osrm/, after `make build`:
flyctl ssh console --app osrm
# In the SSH'd shell, the volume is at /data
exit

# Push the files in:
flyctl ssh sftp shell --app osrm
put data/region.osrm /data/region.osrm
put data/region.osrm.cell_metrics /data/region.osrm.cell_metrics
# ... every region.osrm.* file
exit
```

Restart the machine: `flyctl machine restart <id>`.

**Option B — build on a dedicated build machine.** Spin a one-off Fly machine with the extra disk + RAM to run `osrm-extract → osrm-partition → osrm-customize` against a fresh PBF, write into the same volume (volumes are not multi-attach, so swap the running machine out, run the build machine, swap back). More moving parts; only worth it once we have a weekly rebuild cron.

### Weekly rebuild cron (proposed)

Fly Machines support cron-via-app. A separate `osrm-rebuilder` app runs once a week:

1. Reads the latest weekly PBF from Geofabrik.
2. Runs the three OSRM passes against `/data/staging/`.
3. Atomically renames `/data/staging/` → `/data/`. (Or symlinks, depending on what `osrm-routed` accepts at runtime.)
4. Triggers a graceful restart of the `osrm` machine.
5. Bumps `OSRMMatcher.AlgVersion` (the worker re-matches stale rows on next claim — see [decisions.md § 45](../../docs/architecture/decisions.md#45-server-side-map-matching-uses-osrm-not-valhalla-meili-or-graphhopper)).

Until that's wired, manual `make download && make build` + `flyctl ssh sftp` is the rebuild path. Note the cadence in this file each time it's done.

### Secrets

None. OSRM has no auth; that's why it can never have a public route.

### Observability

| What | Where |
|---|---|
| OSRM logs | `flyctl logs --app osrm` |
| Per-machine metrics | Fly.io dashboard |
| Match success rate | Custom: `select status, count(*) from run_matched_tracks group by status` from the SQL editor — a sustained `skipped > 5%` signals "wrong PBF region" or "engine retune broke something" |
| Health endpoint | `osrm-routed` exposes `/health`; have Better Stack probe `https://<some-public-proxy-or-ssh-tunnel>/osrm/health` once a minute. The cleanest way is a Fly.io machine with a public IP that proxies just the health endpoint; we do **not** open `/match` |

### Rollback

If a graph rebuild produces a worse-quality match than the previous version:

```bash
# 1. Bump AlgVersion back to the prior value in OSRMMatcher.AlgVersion
#    (or revert the bump commit), redeploy the worker.
# 2. SSH into the OSRM machine and restore the prior /data/ from the
#    backup copy retained during the swap.
# 3. Restart osrm.
```

The worker code is the canonical knob — re-matches happen via `algorithm_version` mismatch on the next claim, not a hand-touched DB update.

---

## GraphHopper app — `graphhopper`

**Status: plan.** Not deployed yet. The config lives in [`graphhopper/`](graphhopper/) ([`Dockerfile`](graphhopper/Dockerfile), [`config.yml`](graphhopper/config.yml), [`fly.toml`](graphhopper/fly.toml), [`README.md`](graphhopper/README.md)); standing it up is the operator's `flyctl deploy` + graph-seed step below.

Serves the `foot` profile's `algorithm=round_trip` endpoint for the **"Generate a route by distance"** feature. The caller is the dedicated **generate-route Lambda** (`apps/web/lambda/generate-route/`), wired to `/api/routes/generate` via CloudFront; its `GRAPHHOPPER_URL` env points at this app.

### Reached over public https — not 6PN

This is the key way it differs from OSRM. OSRM is reached by the Go **worker** (also on Fly), so it stays 6PN-internal with no public IP. GraphHopper is reached by the **Lambda**, which runs on **AWS** — there is no 6PN path from AWS into Fly's private network — so this app exposes a **public https service** (`[http_service]` in `fly.toml`, Fly terminates TLS at the edge). `GRAPHHOPPER_URL = https://graphhopper.fly.dev`. It's one latency-tolerant `round_trip` call per seed (a few per generate request), not a hot path. `GRAPHHOPPER_URL` is server-only in every tier — never `PUBLIC_`, never in the browser bundle.

**Shared-secret guard (shipped).** Because the endpoint is public — unlike OSRM's `/match`, which stays 6PN-internal — a stranger who learned the hostname could hammer `/route` and bypass the CloudFront WAF rate-limit. So a small **Caddy** front (built into [`graphhopper/Dockerfile`](graphhopper/Dockerfile), config [`graphhopper/Caddyfile`](graphhopper/Caddyfile)) owns the public port and proxies to GraphHopper (bound to `127.0.0.1:8990`) only when the `X-Engine-Key` header matches the `GRAPHHOPPER_API_KEY` secret; `/health` stays open for the Fly check. The Lambda sends the header (`apps/web/src/lib/routes/generate/graphhopper.ts`), reading `GRAPHHOPPER_API_KEY` from its env (Terraform pulls just that key from the prod sops file). Set the **same value** as a Fly secret on this app. A missing/wrong key → Caddy 403 → handler 502 → the `generate-route-engine-unreachable` alarm fires, so a misconfig is loud, not silent.

### Sizing

The driver is OSM extract size, same as OSRM. GraphHopper runs in **flexible mode** (no CH — see below), which keeps the import footprint smaller than the speed-mode default:

| Region | PBF | RAM (flexible foot) | Fly machine |
|---|---|---|---|
| Single country (e.g. UK) | ~1.2 GB | ~2-3 GB | `shared-cpu-2x` 4 GB |
| Small region (Victoria seed) | ~200 MB | ~1 GB | `shared-cpu-2x` 4 GB |
| Continent extract | ~25 GB | ~16+ GB | `performance-4x` 16 GB+ |

**Recommended v1: same UK extract as OSRM on `shared-cpu-2x` 4 GB.** The Dockerfile pins the JVM heap (`JAVA_OPTS=-Xmx2500m`); bump the heap and `[[vm]] memory` together for a larger extract. Keep the GraphHopper and OSRM graphs on the **same region extract** so "generatable" and "matchable" cover the same ground — a generate start point outside the imported region returns no path → the core surfaces a 502.

### `Dockerfile` + `config.yml`

There is **no official prebuilt GraphHopper image** (the `graphhopper/graphhopper` Docker Hub org is empty), so [`graphhopper/Dockerfile`](graphhopper/Dockerfile) builds the runnable `graphhopper-web-*.jar` from a pinned source tag (`GH_VERSION`, currently 10.0) in a Maven stage, then runs it on a slim JRE. The routing config is [`graphhopper/config.yml`](graphhopper/config.yml), which we own.

**Flexible mode + Landmarks, no Contraction Hierarchies — load-bearing.** `round_trip` is a core algorithm but it only runs in **flexible** mode; CH (the default speed preparation) cannot serve it. `config.yml` leaves `profiles_ch: []` so a plain `round_trip` request succeeds **without** the caller sending `ch.disable=true` — which is what `apps/web/src/lib/routes/generate/graphhopper.ts` does (it doesn't send that param). It DOES prepare **Landmarks** (`profiles_lm: [{profile: foot}]`, hybrid mode) to accelerate the flexible leg-routing each `round_trip` does — worth the import cost because a generate request fans out several seeds concurrently, so per-query CPU is the bottleneck, not single-call latency. Re-enabling CH breaks generation with "round trip not supported with CH".

**Built-in foot model + explicit encoded values.** The `foot` profile uses GraphHopper's bundled `foot.json` via `custom_model_files: [foot.json]` rather than an inline copy (GH 10 retired names like `foot_road_access`, so a hand-copied model fails to compile). GH 10 does not auto-import the encoded values that model needs, so `config.yml` declares them in `graph.encoded_values` — a missing entry fails the boot with `Encoded values missing: …`.

**No elevation.** The stock foot profile's elevation variant (`foot_elevation.json`) needs SRTM tiles → extra disk + RAM. round_trip distance shaping doesn't need it, so we use the flat `foot.json` and set no elevation provider.

### Volume — `graphhopper_data`

```bash
flyctl volumes create graphhopper_data --app graphhopper --region lhr --size 10
```

Holds the operator-uploaded `region.osm.pbf` plus the `graph-cache/` directory GraphHopper builds on first boot. Both on the volume means a redeploy never rebuilds the graph (same property as OSRM).

### Initial graph build (on first boot from the PBF)

Unlike OSRM, where the operator runs the three extract passes locally and ships the finished `.osrm.*` files, GraphHopper builds its graph **on first boot** from the PBF on the volume. The operator just uploads the PBF:

```bash
# 1. Deploy (builds the jar; machine boots with no graph yet):
cd apps/job_worker/graphhopper && flyctl deploy --app graphhopper

# 2. Upload the SAME region PBF the OSRM graph uses — reuse the one the OSRM
#    Makefile already downloaded:
flyctl ssh sftp shell --app graphhopper
put ../osrm/data/region.osm.pbf /data/region.osm.pbf
exit

# 3. Restart so the first boot imports it into /data/graph-cache (several
#    minutes for a country extract; the /health check grace_period covers it):
flyctl machine list --app graphhopper
flyctl machine restart <id> --app graphhopper
```

Verify: `curl -s https://graphhopper.fly.dev/health` returns 200 once the graph is loaded; a `round_trip` call near a seed-region point returns `paths[0].distance` close to the requested distance.

### Region rebuild

To refresh the graph (newer extract, or a region swap), upload the new `region.osm.pbf`, delete `/data/graph-cache/` over `flyctl ssh console`, and restart — the next boot re-imports. There is no separate algorithm-version re-match concept here (generation is request-time, not a stored derived artefact), so unlike OSRM there's no `AlgVersion` bump to coordinate.

### Secrets

One: `GRAPHHOPPER_API_KEY` — the shared-secret guard key (`flyctl secrets set GRAPHHOPPER_API_KEY=<value> --app graphhopper`). Use the SAME value stored under `GRAPHHOPPER_API_KEY` in the web prod sops file (so the Lambda sends a matching `X-Engine-Key`). Without it the Caddy guard 403s every `/route` and generation degrades to the OSRM fallback (and alarms).

### Observability

| What | Where |
|---|---|
| GraphHopper logs | `flyctl logs --app graphhopper` |
| Per-machine metrics | Fly.io dashboard |
| Health endpoint | `/health` (200 once the graph is loaded) — public https, so Better Stack can probe `https://graphhopper.fly.dev/health` directly (no proxy/tunnel needed, unlike OSRM) |
| Generation success rate | The generate-route Lambda's CloudWatch logs / the 501/502/503 rate at `/api/routes/generate` |

### Rollback

The graph is on the volume, not in the image, so a redeploy is safe at any time — roll back by redeploying the prior `Dockerfile`/`config.yml`. If a fresh graph import is worse, restore the prior `/data/graph-cache/` from a backup copy and restart.

---

## CI wiring

Two workflows live under `.github/workflows/`:

### `.github/workflows/release-worker.yml`

Triggered by `worker@*`:

```yaml
on:
  push:
    tags: [ 'worker@*' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@v1
      - run: flyctl deploy --app threkir-worker --remote-only
        working-directory: apps/job_worker
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

Required secret: `FLY_API_TOKEN` (Fly.io dashboard → Account → Access Tokens, scoped to the org).

### `.github/workflows/release-osrm.yml`

Triggered by `osrm@*`. Doesn't rebuild the graph — just redeploys the container so a config change (e.g. an algorithm flag) propagates without disturbing the graph on the volume:

```yaml
on:
  push:
    tags: [ 'osrm@*' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@v1
      - run: flyctl deploy --app osrm --remote-only
        working-directory: apps/job_worker/osrm
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

The graph itself is on the volume, not in the image, so a redeploy doesn't touch the graph. That's deliberate — image deploys should be safe to do at any time.

### `.github/workflows/release-graphhopper.yml`

**Shipped.** Same shape as `release-osrm.yml` — redeploys the container (which rebuilds the jar from the pinned `GH_VERSION`) without touching the graph on the volume. Read the workflow for the current text; the two things worth knowing here:

- It fires on a **published GitHub Release** whose tag starts `graphhopper@`, not on a bare tag push, and the actions are SHA-pinned — the house convention every Fly release workflow follows. (An earlier sketch in this file showed `on: push: tags:` with floating `@v4` / `@v1` refs; that predates the convention and is not what shipped.)
- After `flyctl status` it **probes the public `/health`** and fails the job if the engine has not answered 200 within 10 minutes. A cold volume imports the graph for minutes while the machine already reads healthy, so status alone can green-light a tag over an engine that is not serving. `/health` is the one path the Caddy front leaves unauthenticated, so this needs no `GRAPHHOPPER_API_KEY` — that secret stays a Fly app secret and never enters a GitHub Actions context.

The graph is on the volume, so a redeploy never re-imports — image deploys are safe at any time.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| job_worker — `shared-cpu-1x` 256 MB | always-on, single machine | ~$5 |
| OSRM — `performance-2x` 8 GB | always-on, single machine | ~$30 |
| OSRM — 20 GB volume | per Fly volume pricing | ~$3 |
| GraphHopper — `shared-cpu-2x` 4 GB | always-on, single machine | ~$15 |
| GraphHopper — 10 GB volume | per Fly volume pricing | ~$1.50 |
| Bandwidth | mostly internal 6PN (free); GraphHopper round_trip calls go out over public https (small JSON, latency-tolerant); Storage egress goes through Supabase | <$5 |
| **Subtotal** | | **~$56** |

Scaling drivers:

- More worker machines ($5 each) once queue lag becomes noticeable.
- OSRM RAM as the extract grows: UK → Europe → planet. Each step ~10× the RAM bill.
- Re-matches against an upgraded engine briefly spike the worker rate; doesn't change the per-call cost.

---

## Disaster recovery

### Worker

Stateless. Deleting and recreating the app loses nothing. Procedure:

```bash
flyctl apps destroy threkir-worker --yes
flyctl launch --copy-config --no-deploy --name threkir-worker --region ord
flyctl secrets import --app threkir-worker   # paste SUPABASE_URL=… and SUPABASE_SECRET_KEY=…, then Ctrl-D
flyctl deploy --app threkir-worker
```

RTO: ~10 min. RPO: 0.

### OSRM

The graph is reproducible, not backed up. Procedure to rebuild from scratch:

```bash
flyctl apps destroy osrm --yes
flyctl launch --copy-config --no-deploy --name osrm --region lhr
flyctl volumes create osrm_data --app osrm --region lhr --size 20
# Then either Option A (build locally + sftp) or Option B (build machine).
```

RTO: ~30 min for build + restart. RPO: N/A (regenerable). The interim — between OSRM being down and being back up — is fine for the product: the worker treats OSRM unreachable as a transient (`defer_job(30s)`), so jobs back up rather than fail.

### GraphHopper

The graph is reproducible from the PBF, not backed up. Procedure to rebuild from scratch:

```bash
flyctl apps destroy graphhopper --yes
flyctl launch --copy-config --no-deploy --name graphhopper --region lhr
flyctl volumes create graphhopper_data --app graphhopper --region lhr --size 10
flyctl deploy --app graphhopper
# Then upload region.osm.pbf + restart (graph imports on first boot — see
# the GraphHopper app § Initial graph build above).
```

RTO: ~20 min (deploy + PBF upload + first-boot import). RPO: N/A (regenerable). The interim is graceful for the product: the generate-route Lambda returns 502 while GraphHopper is unreachable, the web client shows "couldn't generate a route, try again," and every other route-builder capability (manual drawing, search, snapping) keeps working — generation is an additive convenience, not a core path.

### Re-match the world

After a graph rebuild we deliberately re-match in-place. The worker handles this on a row-by-row basis — every `run_matched_tracks` row whose `(algorithm, algorithm_version)` doesn't match the current matcher's values gets re-claimed on the next match cycle.

To force a global re-match (e.g. after a major OSRM upgrade):

```sql
update run_matched_tracks
   set status = 'pending', algorithm_version = null
 where status = 'matched';
```

The trigger queues fresh `map_match` jobs. The worker drains them at its claim rate; expect a multi-hour soak for a sizable backlog.

---

## Production readiness checklist

### Worker

- [ ] Fly.io org `project-running` created, `job_worker` app exists in `ord`
- [ ] `SUPABASE_URL` + `SUPABASE_SECRET_KEY` set as secrets (`SUPABASE_JWT_SECRET` only if the project is still on legacy HS256 — check the JWKS first)
- [ ] `OSRM_URL` set to `http://osrm.internal:5000` in `[env]` — **only once the `osrm` app exists**; leave it unset for a hub-first deploy (see "Deploying the hub before OSRM")
- [ ] Single machine deployed; `flyctl logs` shows `"matcher selected" engine=osrm` (or `engine=passthrough` on a hub-first deploy)
- [ ] Drained at least one real `map_match` job end-to-end (insert test run, watch `run_matched_tracks` flip to matched)
- [ ] Queue-lag alert wired
- [x] Backlogged-jobs alert wired (`jobs-backlog-alert` pg_cron -> `jobs_backlog_summary()`; route a scraper on `backlogged_count > 0`)
- [x] Export-retention-overrun alert wired (`export-retention-overrun-alert` pg_cron -> `export_retention_overrun()`; route a scraper on `overrun_count > 0`)
- [x] Failed-jobs alert wired (`jobs-failed-alert` pg_cron → `jobs_failed_summary()`; route a scraper on `failed_count > 0`)
- [ ] `release-worker.yml` workflow merged
- [ ] `FLY_API_TOKEN` GitHub secret configured

### OSRM

- [ ] `osrm` app exists in `lhr`, region matches the worker
- [ ] 20 GB volume `osrm_data` created
- [ ] Extracted UK graph copied into `/data/`
- [ ] Machine restarted; `flyctl logs` shows `osrm-routed` listening on :5000
- [ ] No public IPv4 / IPv6 attached (`flyctl ips list --app osrm` shows only the 6PN address)
- [ ] Worker successfully calls `/match/v1/foot` (verified via the smoke flow)
- [ ] Health probe wired
- [ ] Weekly rebuild cron designed (even if not yet implemented)
- [ ] `release-osrm.yml` workflow merged
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) "Server-side HMM map matching" row updated to reflect the live engine

### GraphHopper

- [ ] `graphhopper` app exists in `lhr`, same region extract as OSRM
- [ ] 10 GB volume `graphhopper_data` created
- [ ] `region.osm.pbf` (SAME region as the OSRM graph) uploaded to `/data/`
- [ ] Machine restarted; first boot imported the graph (`flyctl logs` shows the import finish, then `/health` 200)
- [ ] Public https service reachable (`curl https://graphhopper.fly.dev/health` 200), TLS terminated by Fly
- [ ] A `round_trip` call near a seed-region point returns a path close to the requested distance
- [ ] `GRAPHHOPPER_URL` set on the generate-route Lambda (Terraform), server-only, not `PUBLIC_`
- [ ] Health probe wired (Better Stack against the public `/health`)
- [ ] Public-abuse posture decided (Lambda-only caller for now; CloudFront+WAF or shared-secret header is the follow-up if needed)
- [x] `release-graphhopper.yml` workflow merged
