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
| **Runs + tracks** (`runs`, Storage `runs/{user_id}/*.json.gz`) | Postgres + Storage (S3) | Until user deletes the run, OR account deletion | `delete-account` walks `{user_id}/*` recursively | Decisions §33 — non-owner viewers see privacy-zone-clipped tracks |
| **Routes** (`routes`, including `geom` LineString) | Postgres | Until user deletes, OR account deletion | `delete-account` cascade | Public routes survive deletion only if explicitly transferred to a club (rare) |
| **Coach chat history** (`coach_messages`) | Postgres | 18 months from `created_at` | `purge-stale-coach-messages` cron (`20260922_001_data_retention_purge_jobs.sql`) | Window chosen for season-on-season recall; tighten via the function body |
| **Live spectator pings** (`live_run_pings`) | Postgres | 48 hours | `cleanup_stale_live_run_pings()` cron (every 15 min; window widened from 4h in `20270119_001_live_run_pings_retention.sql`, schedule from `20260602_001_pg_cron_schedules.sql`) | 48h brackets an ultra-length run while still bounding the table; the Go live-hub path uses a Redis TTL of the same window |
| **Race spectator pings** (`race_pings`) | Postgres | 48 hours | `cleanup-stale-race-pings` cron (every 30 min, `20261213_001_race_pings_retention.sql`) | Event-instance-keyed twin of `live_run_pings`; ephemeral breadcrumbs — the finisher's own GPS track is stored separately in the runs bucket |
| **Notifications** (`notifications`) | Postgres | 90 days from `created_at` | `purge-stale-notifications` cron (`20260922_001_data_retention_purge_jobs.sql`) | Inbox UI doesn't paginate past ~90d anyway |
| **Strava / parkrun / Garmin tokens** (`integrations`) | Postgres (Supabase Vault) | Until user disconnects, OR account deletion | `delete-account` revokes upstream + drops row | Strava `/oauth/deauthorize` is called from `delete-account/index.ts` and the outcome is recorded in `deletion_audit_log.third_party_outcomes.strava_deauth` (Art 17(2) evidence trail) |
| **Run photos** (`run_photos`, Storage `run-photos/{user_id}/...`) | Postgres + Storage | Until user deletes the photo or the run, OR account deletion | `delete-account` walks the bucket | Thumbnails (`thumb_512_path`) drained alongside originals |
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

## Auto-deletion / purge jobs

| Job | Schedule | What it deletes | Migration that defines it |
|---|---|---|---|
| `cleanup-stale-live-run-pings` (`cleanup_stale_live_run_pings()`) | every 15 min (`*/15`) | `live_run_pings` older than 48 h | window: `20270119_001_live_run_pings_retention.sql`; schedule: `20260602_001_pg_cron_schedules.sql` |
| `cleanup-stale-race-pings` (`cleanup_stale_race_pings()`) | every 30 min (`*/30`) | `race_pings` older than 48 h | `20261213_001_race_pings_retention.sql` |
| `cleanup-stale-user-coach-usage` (`cleanup_stale_user_coach_usage()`) | hourly (`17 * * * *`) | `user_coach_usage` buckets older than 7 days | `20261215_001_user_coach_usage_retention.sql` |
| `cleanup-stale-rate-limits` | hourly | `rate_limits` rows older than 24 h | `20260604_001_rate_limits.sql` |
| `cleanup-stale-export-blobs` | 04:23 UTC daily | stale data-export blobs | `20260720_001_cleanup_stale_exports.sql` |
| `cleanup-stale-webhook-events` | 04:17 UTC daily | `webhook_events` older than 30 days | `20260623_001_webhook_event_dedupe.sql` |
| `cleanup-stale-app-quota` | 04:15 UTC daily | `app_quota` older than 2 days | `20261007_001_strava_app_quota.sql` |
| `purge-stale-coach-messages` | 03:17 UTC daily | `coach_messages` older than 18 months | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-notifications` | 03:23 UTC daily | `notifications` older than 90 days | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-device-tokens` | 03:29 UTC daily | `device_tokens` whose `last_seen_at` is over 60 days old | `20260922_001_data_retention_purge_jobs.sql` |
| `purge-stale-jobs` | 03:35 UTC daily | `jobs` rows in terminal state with `finished_at` older than 30 days | `20260928_001_gdpr_dsar_closeouts.sql` |
| `purge-stale-direct-messages` | 03:41 UTC daily | `direct_messages` older than 2 years (`created_at`) | `20261119_001_purge_stale_direct_messages.sql` |

Twelve `cron.schedule`d cleanup/purge jobs are live (every job above
deletes rows; the non-deleting scheduled jobs — MV refresh, token-refresh
enqueue, event-reminder enqueue, and the jobs-stuck / jobs-failed alerts —
are not retention jobs and are excluded). Window tightening is a
single-file edit to the function body. The `gdpr_dsar_closeouts_test.sql`
pgtap suite pins the existence of `purge-stale-jobs`; the matching pins for
the others ride alongside their defining migrations.

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
