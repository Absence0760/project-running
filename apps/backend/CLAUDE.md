# backend — AI session notes

Supabase project for the Run app. Postgres schema, Row-Level Security, Storage buckets, Edge Functions (Deno), and the TypeScript / Dart row-type generators all anchor here. **If you're about to run any `supabase` CLI command, your working directory must be this folder** — the CLI resolves migrations, functions, and config relative to `supabase/config.toml`, which only lives here. The top-level `supabase/` directory at the repo root is the CLI's local state (`.branches`, `.temp`); never write migrations there.

## Layout

```
apps/backend/
├── package.json              # scripts: gen:types, gen:types:check
├── .env.example              # placeholder template (committed)
├── .env.development          # ready-to-run local defaults (committed, non-secret)
├── .env.local                # your real secrets / overrides (gitignored, wins)
└── supabase/
    ├── config.toml           # local-stack config — ports, auth, email
    ├── seed.sql              # test user + 12 runs + 5 routes + integrations + gym/nutrition
    ├── migrations/                # ~50 files; full list at `ls supabase/migrations/`.
    │   │                          # Apr 2026 batch laid the schema foundation
    │   │                          # (initial_schema → funding); May 2026 added the
    │   │                          # social layer (notifications, kudos/comments,
    │   │                          # photos, segments, follows, privacy zones, plan
    │   │                          # templates) plus subscription paywall + coach
    │   │                          # messages; June 2026 brought the route + run-
    │   │                          # match pipeline (geom LineString, is_starred,
    │   │                          # routes_within_box, run_match_pipeline,
    │   │                          # routes_intersecting_track, source_track_url
    │   │                          # CAS) and the pg_cron + rate-limit + Vault
    │   │                          # tooling.
    │   └── 20260611_001_run_matched_tracks_cas.sql  # latest at time of writing
    └── functions/
        ├── _shared/{rate_limit,sentry,strava,body_limit}.ts
        ├── clip-public-track/index.ts
        ├── delete-account/index.ts
        ├── export-data/index.ts
        ├── parkrun-import/index.ts
        ├── refresh-tokens/index.ts
        ├── revenuecat-webhook/index.ts
        ├── strava-import/index.ts
        ├── strava-webhook/index.ts
        ├── events-connect-onboard/{index,lib}.ts   # Stripe Connect host onboarding
        ├── events-checkout/{index,lib}.ts           # destination-charge Checkout
        └── stripe-events-webhook/{index,lib}.ts     # the one idempotent order webhook
```

## Local stack

Start every session with `supabase start` in this directory. Ports are fixed via `config.toml`:

| Service | URL |
|---|---|
| REST API | `http://127.0.0.1:54321/rest/v1` |
| Edge Functions | `http://127.0.0.1:54321/functions/v1/{name}` |
| Database | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Studio | `http://127.0.0.1:54323` |
| Mailpit (sent-email inspector) | `http://127.0.0.1:54324` |

Confirm it's running with `supabase status`. The gotcha I keep hitting: `supabase status` returns an error if you run it from the repo root (it looks for `config.toml` in the cwd). `cd` here first.

**Reset the database** with `supabase db reset`. This drops and recreates the local DB, replays every migration in `supabase/migrations/`, runs `seed.sql`, and leaves you at a known-good state. Use this between destructive experiments.

## The test user

`seed.sql` provisions exactly one user:

- Email: `runner@test.com`
- Password: `testtest`
- 12 runs across `app`, `strava`, `parkrun`, `healthkit` sources
- 5 routes, 2 connected integrations, a profile with `preferred_unit = 'km'`
- Phase 4 multi-modal data: 3 gym workouts (23 sets, progressive overload so PR badges fire), 17 food-log entries spanning today + the prior 6 days, a 4-point body-metrics weight series, and `height_cm` / `date_of_birth` / `gender` + `nutrition_activity_level` / `nutrition_goal` prefs so `/nutrition` macro targets compute. These rows are `now()`-relative (unlike the fixed-date runs) so `/gym` + `/nutrition` stay populated on any reset.
- Owns **Richmond Run Club** with one club-owned template of each kind so the club's Templates tab is populated: a training plan (`Beginner 5K — Club Plan`, `is_template` + `club_id`, 2 weeks of workouts), a session plan (`Post-Run Recovery Flow`, blocks + items), and a gym routine (`Club Strength — Lower Body`, exercises + planned sets). Fixed ids → idempotent across resets.

Use it for any manual testing that needs authenticated data. The web app auto-fills the email on the login page in dev mode (see `apps/web/src/routes/login/+page.svelte`).

## Schema and row-type codegen

**Every migration in `supabase/migrations/` must be followed by regenerating both client row-type files.** Do it before committing the migration, not as a follow-up:

```bash
# 1. After `supabase db reset` picks up the new migration:
cd apps/backend
npm run gen:types                       # apps/web/src/lib/database.types.ts
# 2. From repo root:
cd ../..
dart run scripts/gen_dart_models.dart   # packages/core_models/lib/src/generated/db_rows.dart
```

CI's `parity-types` job checks `database.types.ts`. The `schema-codegen-drift` job regenerates and diffs both `db_rows.dart` and `DbRows.kt` — all three are gated on PRs to `main`.

Details, troubleshooting, and drift-detection test recipe: [../../docs/architecture/schema_codegen.md](../../docs/architecture/schema_codegen.md).

## Migrations

### Naming convention

`{YYYYMMDD}_{NNN}_{description}.sql` — date, three-digit ordinal within the day, underscore-separated description. Matches the existing files exactly.

**Gotcha with multiple migrations on the same day:** Supabase's CLI parses the migration *version* as the longest numeric prefix before the first underscore — i.e. `YYYYMMDD` only. The `_NNN_` ordinal is purely cosmetic and does **not** disambiguate. Two files with different `NNN` on the same day both register as version `YYYYMMDD` and the second `supabase db reset` fails with `duplicate key value violates unique constraint "schema_migrations_pkey"`. Walk across consecutive dates instead (`20260506_001_*`, `20260507_001_*`, `20260508_001_*`). If you genuinely need same-day disambiguation in one PR, swap to a 14-digit `YYYYMMDDhhmmss_description.sql` scheme — `supabase migration new` emits this by default — and rename **every** sibling on the same date so each parses to a unique numeric version (e.g. `20260528000001_notifications.sql`, `20260528000002_personal_records_widen_brackets.sql`, `20260528000003_runs_external_id_per_user_unique.sql`). Mixing the two schemes on the same date breaks alphabetical sort: `20260528000002` (14-digit) sorts *before* `20260528_001` (8-digit underscore form) because `0` (48) < `_` (95) at position 9, so the rename must be all-or-nothing per date.

This bit again in run 26820381977: `20260601_001_notifications_realtime.sql` (added 2026-06-01) collided with the pre-existing `20260601_001_runs_metadata_activity_type_required.sql` and took down all five stack-starting jobs at the slow `supabase start` step. The fix renamed *only the new* file to `20260601000001_notifications_realtime.sql` — the runs_metadata sibling was left at `20260601` because it had already been applied to prod under that version, and renaming an already-applied migration makes the next `db push` try to re-run it. That forces the one tolerated exception to "all-or-nothing per date": a 14-digit file coexisting with an 8-digit `_001` sibling on the same date. It is safe here only because the two migrations are independent (a `notifications` publication change vs a `runs` CHECK constraint), so the apply-order/version-order mismatch the mixing creates is harmless; the 14-digit version is also deliberately *greater* than `20260601` so it never re-orders relative to that already-applied sibling (it still sorts below the later `20260602…` migrations, but this repo forward-dates routinely, so applying a not-yet-recorded migration that pre-dates the remote's max is the normal deploy path, not a hazard). **A new guard makes this fail in milliseconds instead of at `supabase start`:** `apps/backend/scripts/check_migration_versions.mjs` parses every migration's version key the way the CLI does and fails on any collision; it runs as the "Migration version keys are unique" step ahead of the stack start in the `parity-types` CI job, and `check_migration_versions.test.mjs` pins the parse + detection logic. Run it locally with `node apps/backend/scripts/check_migration_versions.mjs` before pushing a new migration.

### Creating one

```bash
cd apps/backend
supabase migration new add_activity_type_to_runs
# Opens nothing — just creates the empty file. Edit it, then:
supabase db reset    # replays everything from scratch, including the new one
```

### What belongs where

- **Table changes** (`create table`, `alter table ... add/drop column`, constraints, indexes): in a migration. Both row-type generators rely on these files.
- **RLS policies and grants**: in a migration. These are schema-level state.
- **Storage buckets and their RLS**: in a migration, via `insert into storage.buckets` + `create policy on storage.objects`. See `20260410_001_runs_to_storage.sql` for the canonical example.
- **Test data / fixtures**: in `seed.sql`, not a migration. `supabase db reset` runs `seed.sql` after migrations.
- **Functions / views**: in a migration (`create or replace function ...`). See `20260406_001_database_functions.sql` for `weekly_mileage` and `personal_records`.

### The Dart generator's parser is narrow

It understands `create table`, `alter table ... add column`, and `alter table ... drop column`. It ignores everything else (indexes, policies, RPCs, storage, `$$...$$` function bodies). If you use a SQL form the parser doesn't cover — a `create type ... as enum`, an `alter table ... alter column ... type`, a column-renaming `alter table ... rename column` — the generator will silently skip it and your Dart row classes will drift. Two options:

1. Reorganise the migration into a `drop column` + `add column` pair that the generator *can* parse. Works for renames in this pre-launch codebase.
2. Grow `_parseAlterTable` in `scripts/gen_dart_models.dart` to handle the new form. Add a test case if the parser is getting complex.

### Bare-body `create or replace function` strips prior fixes

**Whenever a migration does `create or replace function X`, write the COMPLETE desired body — do NOT write from scratch as if `X` had just been created.** PostgreSQL replaces the entire function definition every time, so any guard / clause / rate-limit call added by an earlier migration gets silently dropped when a later migration bare-bodies the function with a partial rewrite.

How this bites: `20260904_001_pr_refresh_restore_auth_guard` restored a JWT-role guard on `refresh_personal_records_for_user` by writing a fresh body — and unwittingly dropped the widened brackets (`20260528000002`), embedded-best efforts (`20260529000002`), and DNF exclusion (`20260530000001`) that earlier persona-fix migrations had added. Same cascade hit `clone_plan_template`: `20260721_001` legitimately stripped publisher fitness data from the clone, but in doing so dropped the auto-complete-active-plan UPDATE (`20260529000004`). The Round 3 cleanup commit `f134c807` added two consolidation migrations (`20261009_001` + `20261010_001`) to roll everything together — that's the pattern to follow. Same trap, again: `20261107_001` hardened `lock_subscription_columns` (session_user bypass) by re-emitting the body and dropped the `billing_issue_at` write-lock that `20260729_001` had added — letting a user clear their own renewal-failure banner. Repaired by the forward migration `20261112_001` (full body restored) and pinned at the pgtap layer in `rls_paywall_test.sql` so the cheap backend job catches the next drop, not just the web e2e.

**Before writing `create or replace function X`:**

1. `grep -ln "function X" apps/backend/supabase/migrations/*.sql` to find every prior touch.
2. Read the LATEST one — that's the live body in the DB.
3. Patch what you need on top of that body; don't go back to the original.
4. If the function is well-trodden (PR refresher, kudos / comments policies, `is_run_visible_to`, etc.), strongly consider whether your fix should be a brand-new sibling migration at the end of the chain rather than threading through the existing rewrites.

This same trap applies to bare-body `drop policy + create policy` replacements where a sibling migration's policy gets lost — see the RLS gotcha below.

### `drop policy if exists "wrong-name"` is a silent no-op

When you replace an RLS policy, the `drop policy if exists "name"` is keyed by EXACT name. A wrong name (typo, stale guess, name that was changed by a later migration) silently does nothing — your new policy then gets created ALONGSIDE the original, and at evaluation Postgres OR's them: the more permissive policy wins. The restrictive new policy you thought you added is bypassed.

**Before replacing a policy, grep the current authoritative name:**

```bash
grep -B 1 "on user_follows for insert" apps/backend/supabase/migrations/*.sql | tail
```

Pick the latest `create policy "..." on user_follows for insert` you find — that's the name to drop. Don't guess. Cost me an extra iteration on Round 3 W1 (the user_blocks finding): I dropped `"user_follows owner insert"` thinking that was the name; the real one was `"users follow on their own behalf"` from `20260521_001_user_follows.sql`. Both policies coexisted afterwards and the test that expected a block-induced 42501 saw the insert succeed via the un-touched original.

### CI green ≠ migration applied

Older `supabase/setup-cli` versions on CI **silently skip** migrations that collide on the `YYYYMMDD` version key (rather than erroring like the local CLI). A `Result: PASS` on the pgtap CI job does NOT prove your migration ran. The Round 2 persona-fix migrations sat in `main` for weeks "passing" CI before anyone noticed they hadn't been applied in any environment. **Always verify a new migration with `cd apps/backend && supabase db reset --local` locally before trusting CI.** If the local CLI errors with `duplicate key value violates unique constraint "schema_migrations_pkey"`, CI is probably just hiding the same error.

## pgtap test gotchas

### UUIDs must be 32 valid hex chars (0-9 a-f) in 8-4-4-4-12 layout

Synthetic UUID literals like `'99999999-9999-9999-9999-99999dnfaaaa'` (contains non-hex `n`) or `'11111111-1111-1111-1111-111111ddd01'` (trailing segment is only 11 chars) error at first insert with `invalid input syntax for type uuid`. The whole test then reports "Bad plan: you planned N tests but ran 0" — easy to miss in a long pgtap summary because no individual test is marked as failing. **Use only `0-9 a-f` in synthetic UUIDs, and count the trailing segment** (12 hex chars). Patterns I've used safely: `99999999-9999-9999-9999-9999ddddaa01`, `88888888-8888-8888-8888-888888aaaaaa`, `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01`.

### `INSERT INTO runs (...)` needs `metadata.activity_type`

Migration `20260601_001_runs_metadata_activity_type_required.sql` added a CHECK constraint that rejects runs without `metadata.activity_type`. Any pgtap test that seeds a row in `runs` must include `metadata` with at least `{"activity_type":"run"}`:

```sql
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (..., 'app', '{"activity_type":"run"}');
```

Or with `jsonb_build_object`: `jsonb_build_object('activity_type', 'run', ...other keys...)`. Forgetting it errors test setup before any assertion runs → "Bad plan" again.

### `set local "request.jwt.claims"` needs double quotes

The parameter name contains a dot, so PostgreSQL requires double quotes around it in `SET LOCAL`. Unquoted form `set local request.jwt.claims = '...'` is parsed differently and silently fails to set the JWT context — `auth.uid()` returns NULL, your RLS test passes (or fails) for the wrong reason. Always:

```sql
set local "request.jwt.claims" = '{"sub":"...","role":"authenticated"}';
```

Companion line: `set local role authenticated;` (or `anon` / `service_role`). The double-quoted form is what every working RLS pgtap test in `apps/backend/supabase/tests/` uses — copy that pattern.

### Common column-name typos that cost a `db reset`

- `user_follows` columns are `follower_id` + `followee_id` — **not** `followed_id`.
- `run_comments` author is `author_id` — **not** `user_id`.
- `clubs` visibility lives on `is_public` (boolean) — **not** a `visibility` text column. The owner is `owner_id` — **not** `created_by`.
- `events` has no `kind` column. Don't add one in test fixtures.
- `race_sessions` has a temporal-invariant CHECK: `status='running'` requires `started_at IS NOT NULL`. A test fixture inserting `running` without `started_at` errors at first insert.

When in doubt, `grep "create table $TABLE" apps/backend/supabase/migrations/*.sql` and read the latest schema before writing the test.

## Edge Functions

Twelve functions live under `supabase/functions/`. All are wired up. Test coverage breakdown:

- **Pure helpers** — `_shared/webhook_security.ts`, `_shared/body_limit.ts`, `revenuecat-webhook/lib.ts`, and the four paid-events libs (`events-connect-onboard/lib.ts`, `events-checkout/lib.ts`, `events-cancel/lib.ts`, `stripe-events-webhook/lib.ts`) are covered by deno tests across the `*.test.ts` files. The `edge-functions` CI job runs `deno test --no-check supabase/functions/` which recurses and picks up every `*.test.ts`, so the new files are gated automatically.
- **HTTP-level handler envelopes** — `_shared/handler_envelope.test.ts` covers the auth-rejection branches of the three webhook / cron handlers that bypass the platform `verify_jwt` gate (refresh-tokens / strava-webhook / revenuecat-webhook). 9 tests, gated on `SUPABASE_TEST_URL`. The same `edge-functions` CI job stops the auto-started edge runtime (which ignores `.env.local`) and re-launches `supabase functions serve --env-file` so the rejection branches are reachable instead of 503'ing.
- **Happy-path with valid HMAC / freshness / dedupe** — not covered. Needs real secret values in the test config; deferred.

| Function | Status | Trigger | Auth | Env vars |
|---|---|---|---|---|
| `parkrun-import` | **Working** (scraper) | Client POST with `{ athleteNumber }` | User JWT → `supabase.auth.getUser()` | `PARKRUN_USER_AGENT` |
| `refresh-tokens` | **Deprecated** — kept deployed as a rollback path. Production has been migrated to the Go worker's `kind='token_refresh'` dispatch (`apps/job_worker/internal/handler_token_refresh.go`, scheduled by migration `20260821_001_token_refresh_cron.sql`). | Same as before if invoked directly. | Same shared `CRON_SECRET` (timing-safe compare); service role for DB writes. `verify_jwt = false` in `config.toml`. | `CRON_SECRET`, `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` |
| `strava-import` | **Working** — OAuth exchange + 90-day backfill + `sync` action for already-connected users; GPS streams uploaded to the `runs` Storage bucket and deduped against existing Strava activity IDs. The `connect` path also pins `redirect_uri` against `STRAVA_ALLOWED_REDIRECTS` (required — function returns 503 if unset) and rejects scope grants missing `activity:read_all`. | Client POST with `{ action: 'connect', code, scope, redirect_uri }` (after the OAuth redirect) or `{ action: 'sync', lookbackDays? }` | User JWT | `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_ALLOWED_REDIRECTS` (required for `connect`) |
| `strava-webhook` | **Deprecated** — kept deployed as a rollback path. Production has been migrated to the Go service's `POST /v1/strava/webhook` endpoint (`apps/job_worker/internal/stravahook/server.go`) which validates + dedupes + enqueues a `kind='strava_event'` job; the worker handler (`handler_strava_event.go`) does the activity fetch + Storage upload + runs insert async. Same `webhook_events` dedupe table on the `provider='strava'` partition, same `metadata.strava_id` dedupe key — the two paths can co-exist during cutover. | Same as before if hit directly. | Shared `?secret=` URL guard, `hub.verify_token` on GET, service role for DB writes. `verify_jwt = false`. | `STRAVA_VERIFY_TOKEN`, `STRAVA_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |
| `export-data` | **Deprecated** — kept deployed as a rollback path. Production traffic now hits the Go service's `POST /v1/export` endpoint (`apps/job_worker/internal/dataexport/server.go`) — same JWT auth, same tiered rate limit, same Storage path + signed-URL response. | Same as before if invoked directly. | User JWT | — |
| `revenuecat-webhook` | **Working** — replay-protected (7-day freshness window via `validateFreshness` default + `event.id` dedupe via `webhook_events`, migration `20260623_001`). RevenueCat retries an undelivered event for up to 3 days, so the 7-day window comfortably brackets every legitimate retry; both webhooks share the same default to keep the security model uniform. | POST from RevenueCat (INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION) | HMAC-SHA256 of raw body in `x-revenuecat-hmac` (timing-safe compare against `REVENUECAT_WEBHOOK_SECRET`). `verify_jwt = false` in `config.toml`. | `REVENUECAT_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |
| `delete-account` | **Working** — recursive Storage prefix walk drains `{user_id}/exports/` blobs alongside top-level tracks. Records per-table deleted-row counts (jobs / rate_limits / reports / segments + the two Storage buckets) into `deletion_audit_log.notes` as compact JSON on the `ok` path — `result='ok'` disambiguates notes-as-counts from notes-as-error, so no schema change. After the cascade it also enqueues the account-deletion **receipt** email (a `lifecycle_email` `account_deleted` job carrying `{email, locale}` inline, **no `user_id`** so the pre-cascade job-drain doesn't sweep it; worker dedups via the non-cascading `account_deletion_receipts` table, migration `20270217_001`, decisions §121). | Client POST (user action) | User JWT + service role for admin delete | `SUPABASE_SERVICE_ROLE_KEY` |
| `clip-public-track` | **Working** — server-side privacy-zone clipping for non-owner viewers. Downloads the gzipped track via service-role, runs `clip_track_for_user`, returns clipped points. Replaces the dropped public-runs Storage policy (decisions §33, audit/storage High). | Anon or user JWT POST with `{ run_id }` | Anon JWT accepted (RLS gates the row read); per-IP rate limit for anon, per-user for authenticated | — |
| `events-connect-onboard` | **Working** (pure libs tested; **live Connect onboarding UNVERIFIED — needs operator sk_test_ keys**). Creates/reuses a Stripe Express account for the host, persists its id in `instructor_payout_accounts`, returns a hosted Account Link URL. `charges_enabled` flips later via `stripe-events-webhook` `account.updated` — never written here. SAQ A (Stripe-hosted onboarding). club_events.md slice P1. | Client POST (host) | User JWT → `auth.getUser()`; service role for the own-row write; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `STRIPE_EVENTS_ALLOWED_REDIRECTS`, `SUPABASE_SERVICE_ROLE_KEY` |
| `events-checkout` | **Working** (pure libs tested; **live Checkout round-trip UNVERIFIED — needs operator sk_test_ keys**). Validates visibility + `event_pricing` (modality `in_person` only; `virtual` → 400) + not-cancelled + sales window + host `charges_enabled` + capacity precheck (going + non-expired pending), then opens a **destination-charge** Checkout Session (`application_fee_amount` + `transfer_data.destination` = host account) with a stable idempotency key, and inserts a `pending` `event_orders` row holding a 15-min soft reservation. Returns `{ checkout_url, order_id }`. SAQ A (no card form). | Client POST (buyer) `{ event_id, instance_start }` | User JWT → `auth.getUser()`; service role for the ledger write; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `STRIPE_EVENTS_ALLOWED_REDIRECTS`, `SUPABASE_SERVICE_ROLE_KEY` |
| `events-cancel` | **Working** (pure libs tested; **live refund round-trip UNVERIFIED — needs operator sk_test_ keys**). Buyer self-cancel of their OWN paid/pending registration (slice P2). **INITIATES only — never writes `event_orders.status`** (the webhook stays the sole writer). Pure `lib.ts` decides via `resolveRefundEligibility` + `cancelAction`: `pending` → expire the Checkout Session at Stripe (→ `checkout.session.expired`); refund-eligible `paid` → create a Stripe refund (`refund_application_fee: true`, stable idempotency key `events-cancel:<order_id>`, → `charge.refunded`) and stamp `event_orders.refund_initiated_at`; `paid` inside the no-refund window → 409 `policy_no_refund` (keeps the seat). 503 `stripe_not_configured` when the key is unset (fail-closed). On a Stripe refund error it clears the optimistic stamp + 502s. SAQ A. | Client POST (buyer) `{ event_id, instance_start }` | User JWT → `auth.getUser()`; service role for the own-row lookup + the refund stamp; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY` |
| `stripe-events-webhook` | **Working** (pure libs tested incl. signature/idempotency/CAS; **live signed delivery UNVERIFIED — needs operator whsec_ keys**). The SOLE, idempotent, service-role-only writer of `event_orders.status`. HMAC-verified on the **raw** body (Stripe-Signature `t=…,v1=…` over `${t}.${body}`, 5-min freshness/replay gate). Insert-first dedupe into `webhook_events` (provider `'stripe'`, `event.id`) → 23505 = 200 skip. Handles exactly four types: `checkout.session.completed` (CAS pending→paid + confirm-time capacity recheck + seat the `going` attendee with `order_id`; oversold → leave paid + log + flag for MANUAL refund), `checkout.session.expired` (CAS pending→canceled, release slot), `charge.refunded` (CAS paid→refunded + release the seat — the P2 self-cancel coupling; a replayed event finds it already refunded and no-ops), `account.updated` (mirror `charges_enabled`/`payouts_enabled`/`details_submitted`). Unknown types → 200 ignored. | POST from Stripe | HMAC-SHA256 over raw body in `Stripe-Signature` vs `STRIPE_EVENTS_WEBHOOK_SECRET`. `verify_jwt = false` in `config.toml`. | `STRIPE_EVENTS_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |

The original eight are short — 25 to 115 lines each. Read the file, not an abstraction; they don't share helpers (other than `_shared/rate_limit.ts` for the throttle). The three paid-events functions follow the `revenuecat-webhook` precedent precisely: a pure `lib.ts` (param builders / decisions / signature verifier, dependency-free) + a thin `index.ts` that holds all Stripe SDK calls (`https://esm.sh/stripe@17.5.0?target=deno`, constructed with `Stripe.createFetchHttpClient()`). `events-checkout/lib.ts` owns the ONE `capacityDecision` helper; `stripe-events-webhook/lib.ts` re-exports it so the create-time precheck and the confirm-time recheck use identical capacity math (divergence would oversell).

**`webhook_events` provider partitions:** `revenuecat`, `strava`, and now `stripe` (the `stripe-events-webhook` dedupe key — insert-first on `(provider='stripe', event_id)` where `event_id` is the Stripe event id). The provider-agnostic 30-day prune (`cleanup-stale-webhook-events`, migration `20260623_001`) already bounds the new partition — no per-provider cleanup needed.

### Rate limiting

User-facing functions guard with `check_rate_limit` via the shared helper:

```ts
import { checkRateLimit } from '../_shared/rate_limit.ts';
// ...after auth.getUser():
const denied = await checkRateLimit(supabase, user.id, 'parkrun-import', 4, 3600);
if (denied) return denied; // 429 with Retry-After header
```

Backed by `rate_limits (user_id, bucket, window_start, count)` (migration `20260604_001`) with fixed-window bucketing — `floor(epoch / window) * window` keys all hits in the same wall-clock window to the same row. `check_rate_limit` is SECURITY DEFINER so EFs only need the function grant, not direct table access. Cron job `cleanup-stale-rate-limits` sweeps rows >24 h old hourly.

For paywalled paths use the tiered variant (migration `20260605_001`):

```ts
const denied = await checkRateLimitTiered(supabase, user.id, 'parkrun-import',
  /* free */ 4, /* pro */ 16, 3600);
```

The SQL function reads `user_profiles.subscription_tier` and the rate-limit row in one transaction, so EF latency stays constant. Lifetime is treated as pro; missing or unknown tier values fall back to free as the conservative default.

The helper fails open on RPC error — a transient DB blip won't manifest as a wave of 429s — and only emits 429 on a real deny.

Don't apply this to `refresh-tokens` (cron, no user.id), `revenuecat-webhook` (HMAC-validated, RC-side), or `strava-webhook` (Strava-side, URL-secret guarded).

### Common shape

Every function that takes a user request follows the same pattern:

```ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
  const authHeader = req.headers.get('Authorization')!;
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // ... work ...
  return Response.json({ ok: true });
});
```

The client in the function is authenticated *as the user* (RLS applies) because the request's `Authorization` header is forwarded. If you need to bypass RLS — background jobs, webhooks from third parties, cross-user lookups — use `SUPABASE_SERVICE_ROLE_KEY` instead of `SUPABASE_ANON_KEY`. `refresh-tokens` and `strava-webhook` are the two functions that do this.

### Running a function locally

```bash
# Start the stack + function host (from apps/backend)
supabase start
supabase functions serve --env-file .env.development   # or .env.local for your real keys

# Hit one
curl -X POST http://127.0.0.1:54321/functions/v1/parkrun-import \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -d '{"athleteNumber": "A123456"}'
```

Getting a JWT for the seed user:

```bash
curl -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" \
  -H "apikey: $(supabase status -o json | jq -r .ANON_KEY)" \
  -H "Content-Type: application/json" \
  -d '{"email":"runner@test.com","password":"testtest"}' \
  | jq -r .access_token
```

`supabase functions serve` reloads on file change. Logs go to the terminal it's running in.

### Testing without real credentials

Strava, parkrun, and Google each require real API credentials to test their happy paths. Options:

1. **Mock the upstream HTTP call.** Deno's `fetch` can be stubbed — wrap it in a helper, import from a conditional module. Fiddly for a 40-line function; usually not worth it.
2. **Point at a local fixture server.** Drop a tiny `python -m http.server` in a fixtures directory and override `STRAVA_OAUTH_URL` (doesn't exist yet — the functions hardcode `https://www.strava.com/...`). Would need a small refactor to make URLs injectable.
3. **Use a sandbox Strava account.** Strava has a real sandbox but registration is a multi-day process.
4. **Don't test the happy path locally; test only the auth rejection branch.** Send a request with a bogus JWT and assert 401. Covers the common shape; skips the integration detail.

The `edge-functions` CI job now exercises the three handler envelopes (refresh-tokens / strava-webhook / revenuecat-webhook) end-to-end on every PR — see the "Edge Functions" section above. The five JWT-gated handlers (clip-public-track / delete-account / export-data / parkrun-import / strava-import) are 401'd by the platform gateway before the handler body runs, so option 4 is degenerate for them and there's no equivalent CI coverage. The happy paths (valid HMACs / fresh event timestamps / real OAuth) still fall through to options 1-3 above when you need them.

### Deploying functions to production

For the full production plan — Supabase Cloud project setup, region, custom domain, secrets, observability, DR — see [deployment.md](deployment.md).

Handled by CI in `.github/workflows/ci.yml`'s `deploy-functions` job on GitHub release (published). Do not deploy manually in dev — you'll clobber whatever's live. If you need to run a one-off deploy, ask first.

Manual deploy syntax (for reference):

```bash
supabase functions deploy parkrun-import --project-ref "${SUPABASE_PROJECT_REF}"
# Requires SUPABASE_ACCESS_TOKEN in the env.
```

## Secrets and env vars

Three committed-vs-local files, the repo-wide convention (decisions §137): `.env.example` is the placeholder template; `.env.development` is the committed, non-secret, ready-to-run local defaults you serve `--env-file .env.development` against; `.env.local` (gitignored) holds your real keys and is the file you point `--env-file` at when you need them — it wins. Keep all three in sync when you add a new variable.

Supabase Edge Functions read env vars via `Deno.env.get('NAME')`. At runtime in local dev, `--env-file .env.development` (or `.env.local`) on `supabase functions serve` is what populates them. In production, variables are set via `supabase secrets set` against the linked project — a separate flow from `.env.local`.

Variables currently used:

- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — injected by the runtime; you do not set these in `.env.local` for local dev.
- `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` — Strava OAuth credentials.
- `STRAVA_VERIFY_TOKEN` — shared secret for the webhook GET handshake (sent by Strava in `hub.verify_token`).
- `STRAVA_WEBHOOK_SECRET` — shared secret embedded in the callback URL's query string (`?secret=...`). Strava preserves URL query strings on both GET and POST, so this is the only auth available on POST events (Strava doesn't sign payloads). Required: function fails closed without it.
- `CRON_SECRET` — shared bearer token the pg_cron schedule passes to `refresh-tokens` so an unauthenticated caller can't trigger Strava token-refresh churn on every integration in the table. Required: function fails closed without it.
- `PARKRUN_USER_AGENT` — identifies us to parkrun's server. Be polite.
- `REVENUECAT_WEBHOOK_SECRET` — HMAC secret the `revenuecat-webhook` verifies the request body against. Required: function fails closed without it.
- `STRIPE_SECRET_KEY` — Stripe platform secret key (sk_test_ in P1 — **TEST MODE ONLY, never a live key**). Used by `events-connect-onboard` (account + Account Link create), `events-checkout` (destination-charge Checkout Session), and `events-cancel` (refund create / Checkout Session expire — slice P2 buyer self-cancel). Required: all fail closed (503 `stripe_not_configured`) without it. Server-only; never client-readable.
- `STRIPE_CONNECT_CLIENT_ID` — Stripe Connect application id (ca_…). Configured on the platform account for Express + Account Links; held as an env var for any future Standard-OAuth path (open question #4). Not passed per-call in P1.
- `STRIPE_EVENTS_WEBHOOK_SECRET` — Stripe webhook signing secret (whsec_…) the `stripe-events-webhook` verifies the Stripe-Signature HMAC against. SEPARATE from `REVENUECAT_WEBHOOK_SECRET` and a separate endpoint. Required: function fails closed (503 `webhook_not_configured`) without it.
- `STRIPE_EVENTS_ALLOWED_REDIRECTS` — comma-separated allow-list of origins accepted for Account Link return/refresh + Checkout success/cancel URLs (the strava-import open-redirect defence). Required: `events-connect-onboard` + `events-checkout` 503 when empty.
- `REVENUECAT_SECRET_API_KEY` — RevenueCat REST secret key `delete-account` uses to DELETE the subscriber on erasure. Optional — unset → `revenuecat_delete: 'skipped'`.
- `FCM_SERVER_KEY` — Firebase Cloud Messaging server key `delete-account` uses to batch-invalidate Android push tokens. Optional — unset → `fcm_remove: 'skipped'`.
- `DELETION_AUDIT_KEY` — HMAC key for the `deletion_audit_log` pseudonymous user-id hash. Optional but recommended; unset → legacy salted SHA-256.
- `VAPID_PRIVATE_KEY` — web-push private signing key (public half is `PUBLIC_VAPID_PUBLIC_KEY` in `apps/web/.env.example`). **Consumed by the Go worker, not an Edge Function:** the `web_push` job handler (migration `20261219_001`) signs encrypted Web Push messages with it. Set on the **worker** as `VAPID_PRIVATE_KEY` + `VAPID_PUBLIC_KEY` + `VAPID_SUBJECT` (see `apps/job_worker/CLAUDE.md`); unset → `web_push` jobs finish done while leaving the notification rows pending.
- `SENTRY_DSN`, `APP_RELEASE` — Sentry error reporting (every EF via `_shared/sentry.ts`). Optional in local dev.

## CLI gotchas I've hit

- **Run every `supabase` command from `apps/backend/`.** The CLI looks for `config.toml` in the cwd and fails or misleads otherwise.
- **`supabase db reset` blows away local data.** The seed repopulates it. If you had manual experiments in the local DB, export them first — the seed will not restore them.
- **`supabase gen types typescript --local` writes `Connecting to db 5432` to stdout** before the real output. The `gen:types` npm script pipes through `grep -v '^Connecting to db'` to strip it. Don't remove that filter.
- **`supabase functions serve` does not autoload any env file**. You must pass `--env-file .env.development` (or `.env.local` for your real keys) explicitly. A missing env var shows up as a `Deno.env.get('X')!` assertion failure at runtime — the `!` eats the error.
- **Docker must be running.** All local Supabase services run under Docker. If `supabase start` hangs or errors weirdly, check `docker ps`.
- **`deno.lock` lives at the repo root and is committed.** Newer Supabase CLIs write it during `supabase db reset` / `functions serve` to pin Edge Function dependency resolutions (e.g. `https://esm.sh/@supabase/supabase-js@2 → 2.105.1` plus integrity hashes for every transitive Deno URL). The file is created inside the CLI's Docker container as `root:root`, so after a fresh resolution you may need to `sudo chown` it before staging. Treat it like `package-lock.json`: review the diff on dependency-version changes, but otherwise let it ride.

## Before reporting a task done

- If you added or changed a migration: run `supabase db reset` locally, then regenerate both row-type files, then commit the migration + both generated files in one change.
- If you added or changed an Edge Function: deploy-ability has not been tested locally. The user will notice on `main` deploy. Leave a note in the PR description about what you couldn't verify.
- If you added a new env var: update `.env.example` and this file's "Variables currently used" list.
- If you added a new function: update the table in the "Edge Functions" section above. Status column should be honest — stub, partial, or working.
- If you changed `runs.metadata` key usage: update [../../docs/backend/metadata.md](../../docs/backend/metadata.md). The schema generators can't catch drift in there.
