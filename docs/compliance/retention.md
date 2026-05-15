# Data retention policy

How long the project keeps each category of personal data, and when auto-deletion fires.

**Status**: scaffold. The `TODO:` cells need real values from product / legal before publishing.

## Principle

The GDPR Art 5(1)(e) storage-limitation principle requires retention to be "no longer than necessary for the purposes". Per category:

| Category | Storage | Retention | Trigger | Notes |
|---|---|---|---|---|
| **Account** (`auth.users`, `user_profiles`) | Supabase Postgres | Until user deletes the account | `delete-account` Edge Function | Recovery email is also deleted; re-signup creates a fresh account |
| **Runs + tracks** (`runs`, Storage `runs/{user_id}/*.json.gz`) | Postgres + Storage (S3) | Until user deletes the run, OR account deletion | `delete-account` walks `{user_id}/*` recursively | Decisions §33 — non-owner viewers see privacy-zone-clipped tracks |
| **Routes** (`routes`, including `geom` LineString) | Postgres | Until user deletes, OR account deletion | `delete-account` cascade | Public routes survive deletion only if explicitly transferred to a club (rare) |
| **Coach chat history** (`coach_messages`) | Postgres | TODO: 12 months default? User-toggleable in Settings? | TODO: `pg_cron` purge job not yet present | High-PII pile; needs an explicit decision |
| **Live spectator pings** (`live_run_pings`) | Postgres | 24 hours | TODO: `pg_cron` purge job — verify it exists | Roadmap calls for Redis 24h TTL on the live-hub path; the Postgres fallback path needs a matching sweep |
| **Notifications** (`notifications`) | Postgres | TODO: 90 days from read OR 1 year hard cap? | TODO: scheduled job | Currently unbounded |
| **Strava / parkrun / Garmin tokens** (`integrations`) | Postgres (Supabase Vault) | Until user disconnects, OR account deletion | `delete-account` revokes upstream + drops row | Strava token revoke via `/oauth/deauthorize`; document non-revoked path as a known gap |
| **Run photos** (`run_photos`, Storage `run-photos/{user_id}/...`) | Postgres + Storage | Until user deletes the photo or the run, OR account deletion | `delete-account` walks the bucket | Thumbnails (`thumb_512_path`) drained alongside originals |
| **Push tokens** (`device_tokens`) | Postgres | TODO: 90 days from last seen? On every app-uninstall ping? | TODO | Currently unbounded → wasted FCM/APNs send budget on dead tokens |
| **Coach usage counter** (`user_coach_usage`) | Postgres | TODO: roll over monthly, hard delete after 24 months | TODO | Pseudonymous per-user counter for the daily-cap paywall |
| **Sentry events** | Sentry (US-hosted by default) | 90 days (Sentry default) | Sentry-side retention | Sub-processor; users opt out by disabling client telemetry |
| **CloudFront / S3 access logs** | AWS | TODO: 30 days? | S3 lifecycle rule | Source IP + request path — modest PII |
| **Auth session logs** | Supabase | Per Supabase's defaults | Supabase | Can't change without enterprise plan |
| **Email** (sent via Supabase Auth provider) | Supabase + email provider | Provider's default | Provider | TODO: confirm provider + DPA terms |
| **Personal records** (`personal_records`) | Postgres | Until account deletion | `delete-account` cascade | Derived from runs; not strictly needed but UX-expected |
| **Fitness snapshots / training load** (`fitness_snapshots`) | Postgres | Until account deletion | `delete-account` cascade | Derived; CTL/ATL/TSB curves |

## Auto-deletion / purge jobs

| Job | Schedule | What it deletes | Migration that defines it |
|---|---|---|---|
| `cleanup-stale-rate-limits` | hourly | `rate_limits` rows older than 24 h | `20260604_001_rate_limits.sql` |
| TODO: `purge-stale-live-pings` | hourly | `live_run_pings` older than 24 h | TODO |
| TODO: `purge-stale-coach-messages` | nightly | `coach_messages` older than retention period | TODO |
| TODO: `purge-stale-notifications` | nightly | `notifications` older than retention period | TODO |
| TODO: `purge-stale-device-tokens` | weekly | `device_tokens` not seen in N days | TODO |

The first row exists today; the rest are documented gaps surfaced by `/audit/gdpr` and `/audit/account-deletion-completeness`. Each needs a `pg_cron` job + a migration + a pgtap test that confirms a row inserted with `created_at = now() - interval 'X+1 day'` is removed on the next run.

## Backups

| Backup | What's in it | Retention | Restore path |
|---|---|---|---|
| Supabase Postgres point-in-time recovery | Everything | 7 days (Pro), 28 days (Team) | Supabase support |
| Manual `pg_dump` (per `apps/backend/local_testing.md`) | TODO: do we run any periodic dump? | TODO | TODO |
| AWS S3 versioning on the `runs` bucket | Last N versions of every track | TODO: disabled? per-bucket policy | `aws s3api get-bucket-versioning` |

Retention applies to live data; backups retain a copy for a longer window by design. The Privacy Policy must disclose this — a user "deleted" today reappears in any restore-from-backup the next day. GDPR is consistent with this when documented.

## When this changes

A retention change is a regulator-visible product change. Procedure:

1. Update this doc.
2. Update the `pg_cron` job (migration).
3. Update the Privacy Policy retention paragraph.
4. Notify existing users via in-app banner if the change is material (shortened retention; new auto-deletion category).
