# Data retention policy

How long the project keeps each category of personal data, and when auto-deletion fires.

**Status**: live (2026-05-26). Code-side retention is implemented; the
remaining `TODO:` cells are operator/legal tasks (DPA confirmation,
backup-schedule decisions).

## Principle

The GDPR Art 5(1)(e) storage-limitation principle requires retention to be "no longer than necessary for the purposes". Per category:

| Category | Storage | Retention | Trigger | Notes |
|---|---|---|---|---|
| **Account** (`auth.users`, `user_profiles`) | Supabase Postgres | Until user deletes the account | `delete-account` Edge Function | Recovery email is also deleted; re-signup creates a fresh account |
| **Account-deletion receipt guard** (`account_deletion_receipts`) | Postgres | 30 days from `sent_at` | `cleanup-account-deletion-receipts` cron (hourly, `20270217_001_account_deletion_receipt.sql`) | **Personal data, and deliberately outlives the deleted account.** It is the send-once guard for the deletion-receipt email, so it must survive the `auth.users` cascade that takes a `lifecycle_email_log` row with it, and it carries no FK. One row per receipt: a hash of the lowercased, trimmed address (`handler_lifecycle_email.go`) and a timestamp. **The digest has a keyed mode since 2026-09-08** ([decisions § 1600](../architecture/decisions.md)): with `DELETION_AUDIT_KEY` set on the Go worker it is HMAC-SHA256 over a domain-separated address, which an adversary cannot reproduce from a candidate address; unset, it is the legacy **unsalted, unkeyed** hex SHA-256, which they can. The unkeyed form is pseudonymisation, not anonymisation — an email address is a guessable input, so anyone holding a candidate address can compute the digest and test membership, which Recital 26 puts squarely in scope, and the migration's "not a directory of deleted-account addresses" is true only of *enumeration*: the table cannot be read out, but it can be asked. Keying it ENDS that test rather than time-bounding it, so **provisioning the key on the worker is the operator task this row now depends on** (`apps/job_worker/CLAUDE.md`); it is absent by default so nothing changes until it is set, and a keyed worker reads both digests so the changeover re-sends no receipt. 30 days remains the Art 5(1)(e) answer either way, and it is generous — the guard only has to outlive a job's retry budget |
| **Deletion evidence trail** (`deletion_audit_log`) | Postgres | **7 years from `deleted_at`** (Art 17(2) + Art 5(2) accountability evidence) | `cleanup-deletion-audit-log` cron (03:53 UTC daily, `20270713000002_deletion_evidence_retention.sql`); written by `delete-account`; service-role read only, no user-side read path | A hash of the **user id**, a timestamp, a result code and the per-table deleted-row counts. Not the same shape as the receipt guard above, despite the migration saying it mirrors it: the input is a 122-bit random UUID, so there is no candidate to guess even though the legacy salt is a source constant in this public repo, and setting `DELETION_AUDIT_KEY` upgrades new rows to HMAC (operator task, `deployment.md`). Kept so "did you delete user X on date Y" can be answered after the auth row is gone. **The window was unbounded until 2026-09-08** and that was a decision nobody had taken ([decisions § 1551](../architecture/decisions.md), settled in [§ 1602](../architecture/decisions.md)): what bounds the need is the period in which a failure-to-erase claim can still be asserted, and the longest ordinary civil limitation period among the jurisdictions served is six years (UK Limitation Act 1980 ss. 2/5; Ireland's Statute of Limitations 1957 s. 11; several US states), plus a year of margin for a claim issued at the limit and served after it. Past seven years we can evidence the policy but not the individual erasure, which is the trade Art 5(1)(e) asks for. `deleted_at` defaults to `now()` and nothing backdates it, so the oldest row this schema can hold dates from `20260917_001` (2026-09-17) and the sweep removes nothing before September 2033 — the number is a live decision with seven years of runway to revise, not an irreversible act |
| **Runs + tracks** (`runs`, Storage `runs/{user_id}/*.json.gz`) | Postgres + Storage (S3) | Until user deletes the run, OR account deletion | `delete-account` walks `{user_id}/*` recursively | Decisions §33 — non-owner viewers see privacy-zone-clipped tracks |
| **Routes** (`routes`, including `geom` LineString) | Postgres | Until user deletes, OR account deletion | `delete-account` cascade | Public routes survive deletion only if explicitly transferred to a club (rare) |
| **Coach chat history** (`coach_messages`) | Postgres | 18 months from `created_at` | `purge-stale-coach-messages` cron (`20260922_001_data_retention_purge_jobs.sql`) | Window chosen for season-on-season recall; tighten via the function body |
| **Live spectator pings** (`live_run_pings`) | Postgres | 48 hours | `cleanup_stale_live_run_pings()` cron (every 15 min; window widened from 4h in `20270119_001_live_run_pings_retention.sql`, schedule from `20260602_001_pg_cron_schedules.sql`) | 48h brackets an ultra-length run while still bounding the table. The Go live-hub path uses a **shorter** Redis TTL — `RedisHub.ttl()` defaults to **24 h**, mirroring the in-process hub's `IdleRoomTTL`, not this window. Shorter is the safe direction for storage limitation; the two are deliberately different numbers, so nothing should restate one as the other |
| **Race spectator pings** (`race_pings`) | Postgres | 48 hours | `cleanup-stale-race-pings` cron (every 30 min, `20261213_001_race_pings_retention.sql`) | Event-instance-keyed twin of `live_run_pings`; ephemeral breadcrumbs — the finisher's own GPS track is stored separately in the runs bucket |
| **Notifications** (`notifications`) | Postgres | 90 days from `created_at` | `purge-stale-notifications` cron (`20260922_001_data_retention_purge_jobs.sql`) | Inbox UI doesn't paginate past ~90d anyway |
| **Strava / parkrun / Garmin tokens** (`integrations`) | Postgres (Supabase Vault) | Until user disconnects, OR account deletion | `delete-account` revokes upstream + drops row | Strava `/oauth/deauthorize` is called from `delete-account/index.ts` and the outcome is recorded in `deletion_audit_log.third_party_outcomes.strava_deauth` (Art 17(2) evidence trail) |
| **Run photos** (`run_photos`, Storage `run-photos/{user_id}/...`) | Postgres + Storage | Until user deletes the photo or the run, OR account deletion | `delete-account` walks the bucket | Thumbnails (`thumb_512_path`) drained alongside originals |
| **Art 20 export artifacts** (Storage `exports/{user_id}/exports/...`; legacy `runs/{user_id}/exports/...`) | Storage | **Reachability**: 7 days from creation. **Bytes**: account deletion only | `enqueue-export-blob-reap` (04:13) enqueues one `export_blob_reap` job per prefix and the Go worker erases through the Storage API ([decisions § 1144](../architecture/decisions.md)); the nightly `cleanup-stale-export-blobs` row delete was **unscheduled** by `20270709000001` ([decisions § 1172](../architecture/decisions.md)) and the function kept only as a `service_role` break-glass; `delete-account` walks both buckets through the Storage API and is what erases on request | **These are two different guarantees and this row used to state only the stronger one.** Measured ([decisions § 1049](../architecture/decisions.md), re-measured 2026-09-03): a probe uploaded through the Storage API, aged past the window and swept by the shipped `cleanup_stale_export_blobs()`, loses its row and stops being listable — and its bytes stay on the backend with a matching `sha256`. Deleting the same object through the **Storage API** does remove the backend file (measured on the same bucket in the same session: 1 file → 0), which is the path `delete-account` uses, so the deletion leg is a real erasure and the nightly leg is not. The signed URL is 10 minutes, so the sweep does bound who can reach the archive; it is not an Art 17 erasure and nothing may call it one. That durable fix — the sweep moved onto the Storage API as a Go-worker job kind — was half built and inert under [§ 1112](../architecture/decisions.md) and is **routed now** ([decisions § 1144](../architecture/decisions.md)): the CHECK, the enqueue function, the `cron.schedule` and the dispatch case landed together, and the enqueue expires the `data_export_jobs` rows itself so that leg runs whether or not a worker claims the job. The row delete then came off the clock entirely ([§ 1172](../architecture/decisions.md)), because a night the worker is down was the one case where it turned a bounded retention overrun into permanent residue. Separately, the bytes ALREADY orphaned by past sweeps are invisible to that reaper by construction — it lists `storage.objects`, and those rows are gone. **The remedy previously named here does not exist for this project** ([§ 1173](../architecture/decisions.md)): on Cloud the backend bucket is Supabase's, so there is no bucket to attach an S3 lifecycle rule to, and the S3-compatible endpoint is itself a `SELECT ... FROM storage.objects`, so it can neither show an orphan nor erase one. On Cloud the route is a Supabase support request; on a stack the operator owns, a diff of the raw backend against `storage.objects` — not a prefix rule, which would take live objects with it |
| **Route photos** (`route_photos`, Storage `route-photos/{owner_id}/...`) | Postgres + Storage | Until user deletes the photo or the route, OR account deletion | `delete-account` walks the bucket (drain added 2026-07-03; rows cascade) | Same shape as run photos |
| **Club photos** (`club_photos`, Storage `club-photos/{owner_id}/...`) | Postgres + Storage | Until uploader deletes, OR account deletion | `delete-account` walks the bucket (drain added 2026-07-03; rows cascade) | Same shape as run photos |
| **Stripe Connect payout mapping** (`instructor_payout_accounts`) | Postgres (+ the live Express account at Stripe) | Until account deletion | Row cascades; `delete-account` first calls Stripe `DELETE /v1/accounts/{id}` to close the connected account, outcome in `third_party_outcomes.stripe_connect_delete` | Stripe retains transaction records under its own legal-obligation basis; the platform-side account is closed |
| **Push tokens** (`device_tokens`) | Postgres | 60 days of inactivity (`last_seen_at`) | `purge-stale-device-tokens` cron (`20260922_001_data_retention_purge_jobs.sql`) | Stale FCM/APNs tokens silently rot; this cleans them at the source |
| **Background-job records** (`jobs`) | Postgres | 30 days after terminal state (`finished_at`) | `purge-stale-jobs` cron (`20260928_001_gdpr_dsar_closeouts.sql`) | Holds the user's UUID inside `payload`; `delete-account` also drains synchronously at deletion |
| **Coach usage counter** (`user_coach_usage`) | Postgres | 7 days from `usage_date` (cron) + `delete-account` cascade | `cleanup-stale-user-coach-usage` cron (hourly, `20261215_001_user_coach_usage_retention.sql`) | Pseudonymous per-(user, UTC day) counter. The cap RPCs only read a rolling ~24h window, so buckets are purged at 7 days (a generous margin); `delete-account` also cascades immediately |
| **Rate-limit counters** (`rate_limits`) | Postgres | 24 hours from window start (cron) + immediate ON DELETE CASCADE on account deletion (`20260928_001_gdpr_dsar_closeouts.sql`) | `cleanup-stale-rate-limits` cron + FK | Two layers so a deletion is reflected immediately, not 24h late |
| **Direct messages** (`direct_messages`) | Postgres | 2 years from `created_at`, OR until either party deletes their account (whichever first) | `purge-stale-direct-messages` cron (`20261119_001_purge_stale_direct_messages.sql`) + ON DELETE CASCADE on `sender_id` + `recipient_id` | User correspondence; the FK cascade erases on account deletion and the 2-year cron is the storage-limitation backstop for the case where neither party deletes (e.g. a suspended account). Window lives in the function body |
| **Block list** (`user_blocks`) | Postgres | Until the blocker deletes their account | ON DELETE CASCADE on `blocker_id` (+ `blocked_id`) | The block is the blocker's own data; cascades on their deletion. Kept indefinitely while active because removing it silently un-blocks |
| **Heatmap aggregates** | n/a — no persistent store | Inherits **Runs + tracks** retention | n/a | The personal + community heatmaps are computed on demand from `runs` / tracks (there is no `heatmap_points` table). They hold no independent personal data, so they're covered by the runs/account retention above. (The 2026-05-30 audit cited a `heatmap_points` table that doesn't exist.) |
| **AI-coach prompts/responses (provider-side)** | Anthropic / OpenAI | ~30 days (provider abuse-monitoring retention), then deleted by the provider | Provider-side; not under our control | We send the runner profile + recent-run JSON to the model provider per request; the providers retain inputs/outputs ~30 days for abuse monitoring under their DPAs, then delete. Disclosed in the Privacy Policy + the coach-consent gate |
| **Sentry events** | Sentry (US-hosted by default) | 90 days (Sentry default) | Sentry-side retention | Sub-processor; users opt out by disabling client telemetry |
| **CloudFront access logs** | AWS | Not collected by design — Trivy AWS-0010 is suppressed in `.trivyignore`; per-Lambda CloudWatch alarms cover operational needs | n/a | If access logging is ever enabled, ship a 30-day S3 lifecycle rule alongside the same change |
| **Lambda CloudWatch logs** (`/aws/lambda/<prefix>-coach`) | AWS CloudWatch | 30 days (`retention_in_days = 30` in `infra/modules/web-stack/main.tf`) | CloudWatch retention policy | KMS-encrypted with the same CMK as the Lambda env vars |
| **Auth session logs** | Supabase | Per Supabase's defaults | Supabase | Can't change without enterprise plan |
| **Email** (sent via Supabase Auth provider) | Supabase + email provider | Provider's default | Provider | TODO: confirm provider + DPA terms |
| **Personal records** (`personal_records`) | Postgres | Until account deletion | `delete-account` cascade | Derived from runs; not strictly needed but UX-expected |
| **Fitness snapshots / training load** (`fitness_snapshots`) | Postgres | Until account deletion | `delete-account` cascade | Derived; CTL/ATL/TSB curves |
| **Checkpoint weigh-in / medical fields** (`checkpoint_crossings.body_weight_kg` / `body_weight_pct` / `medical_hold` / `medical_note` — Art 9) | Postgres | 90 days from `recorded_at` (columns scrubbed, row kept) | `purge-stale-checkpoint-health-data` cron (`20270317_001_checkpoint_health_retention.sql`) | The in/out split times ARE the race results (same permanence as `event_results`), so the purge nulls only the health columns; 90 days covers post-race medical/incident review |

## Auto-deletion / purge jobs

| Job | Schedule | What it deletes | Migration that defines it |
|---|---|---|---|
| `cleanup-stale-live-run-pings` (`cleanup_stale_live_run_pings()`) | every 15 min (`*/15`) | `live_run_pings` older than 48 h | window: `20270119_001_live_run_pings_retention.sql`; schedule: `20260602_001_pg_cron_schedules.sql` |
| `cleanup-stale-race-pings` (`cleanup_stale_race_pings()`) | every 30 min (`*/30`) | `race_pings` older than 48 h | `20261213_001_race_pings_retention.sql` |
| `cleanup-stale-user-coach-usage` (`cleanup_stale_user_coach_usage()`) | hourly (`17 * * * *`) | `user_coach_usage` buckets older than 7 days | `20261215_001_user_coach_usage_retention.sql` |
| `cleanup-stale-rate-limits` | hourly | `rate_limits` rows older than 24 h | `20260604_001_rate_limits.sql` |
| `enqueue-export-blob-reap` | 04:13 UTC daily | enqueues one `export_blob_reap` job per export prefix; the Go worker then erases the archive BYTES older than 7 days through the Storage API, in the `exports` bucket **and** the legacy `runs/{user_id}/exports/` prefix. This is the Art 20 retention job — see the Art 20 row above | `20270708000010_route_export_blob_reap.sql` ([decisions § 1144](../architecture/decisions.md)) |
| `cleanup-account-deletion-receipts` | hourly (`17 * * * *`) | `account_deletion_receipts` rows older than 30 days (the send-once guard only has to outlive a job's retry budget; keeping deleted-account hashes past that is data-minimisation debt) | `20270217_001_account_deletion_receipt.sql` |
| `cleanup-stale-export-blobs` | **NOT SCHEDULED** — `20270709000001` ran `cron.unschedule` and kept the function as a `service_role` break-glass | would delete the `storage.objects` ROWS of export blobs older than 7 days, which orphans the bytes rather than erasing them; the reap job above owns this window now ([decisions § 1172](../architecture/decisions.md)) | `20260720_001_cleanup_stale_exports.sql`, widened by `20270602_001_exports_storage_bucket.sql`, unblocked by `20270703000002_export_sweep_survives_storage_delete_guard.sql`, unscheduled by `20270709000001_export_reap_owns_the_retention_sweep.sql` |
| `cleanup-stale-webhook-events` | 04:17 UTC daily | `webhook_events` older than 30 days | `20260623_001_webhook_event_dedupe.sql` |
| `cleanup-stale-app-quota` | 04:15 UTC daily | `app_quota` older than 2 days | `20261007_001_strava_app_quota.sql` |
| `purge-stale-coach-messages` | 03:17 UTC daily | `coach_messages` older than 18 months | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-notifications` | 03:23 UTC daily | `notifications` older than 90 days | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-device-tokens` | 03:29 UTC daily | `device_tokens` whose `last_seen_at` is over 60 days old | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-jobs` | 03:35 UTC daily | `jobs` rows in terminal state with `finished_at` older than 30 days | `20260928_001_gdpr_dsar_closeouts.sql` |
| `purge-stale-direct-messages` | 03:41 UTC daily | `direct_messages` older than 2 years (`created_at`) | `20261119_001_purge_stale_direct_messages.sql` |
| `purge-stale-checkpoint-health-data` | 03:47 UTC daily | Scrubs (nulls) the Art 9 weigh-in / medical columns on `checkpoint_crossings` older than 90 days (`recorded_at`); the split-time rows survive | `20270317_001_checkpoint_health_retention.sql` |
| `cleanup-deletion-audit-log` | 03:53 UTC daily | `deletion_audit_log` rows whose `deleted_at` is over 7 years old (six years being the longest ordinary civil limitation period among the jurisdictions served, plus a year of margin; nothing becomes eligible before September 2033) | `20270713000002_deletion_evidence_retention.sql` |

Fifteen `cron.schedule`d retention jobs are live — every row above except
`cleanup-stale-export-blobs`, which is deliberately unscheduled and is listed
so nobody re-derives it as missing. Each live one deletes rows, except the
checkpoint health job (scrubs columns) and the export reap (enqueues the job
that erases Storage bytes). The other ten live schedules are not retention
jobs and are excluded: `enqueue-token-refresh`, `enqueue-event-reminders`,
`enqueue-weekly-digest`, `enqueue-lifecycle-drip`,
`enqueue-safety-overdue-emails`, `sweep-challenge-completions`,
`jobs-stuck-alert`, `jobs-failed-alert`, `jobs-backlog-alert` and
`export-retention-overrun-alert`. (`refresh-mv-weekly-mileage` is gone
entirely — `20270530_001` dropped the materialized view and unscheduled it.) Window tightening is a
single-file edit to the function body. The `gdpr_dsar_closeouts_test.sql`
pgtap suite pins the existence of `purge-stale-jobs`; the matching pins for
the others ride alongside their defining migrations.

Both counts, every job name and every schedule above are re-derived from the
migration tree by `scripts/check_retention_cron_register.mjs`, which fails the
PR when a `cron.schedule` or `cron.unschedule` lands without this table moving
with it. That guard exists because nothing did: `20270709000001` unscheduled
`cleanup-stale-export-blobs` and this table went on advertising it as a nightly
sweep for nine migrations ([decisions § 1507](../architecture/decisions.md)).
The ten exclusions are declared **by name** in the guard, so a new schedule
cannot join them by being forgotten — an unclassified job fails.

## Backups

| Backup | What's in it | Retention | Restore path |
|---|---|---|---|
| Supabase Postgres point-in-time recovery | Everything | 7 days (Pro), 28 days (Team) | Supabase support |
| Manual `pg_dump` (per `apps/backend/local_testing.md`) | Local dev only — no production schedule | n/a | n/a |
| AWS S3 versioning on the `runs` bucket | Disabled by default — confirm via `aws s3api get-bucket-versioning` per environment | n/a (kept off so deletion is immediate) | `aws s3api get-bucket-versioning` |

Retention applies to live data; backups retain a copy for a longer window by design. The Privacy Policy must disclose this — a user "deleted" today reappears in any restore-from-backup the next day. GDPR is consistent with this when documented.

## When this changes

A retention change is a regulator-visible product change. Procedure:

1. Update this doc.
2. Update the `pg_cron` job (migration).
3. Update the Privacy Policy retention paragraph.
4. Notify existing users via in-app banner if the change is material (shortened retention; new auto-deletion category).
