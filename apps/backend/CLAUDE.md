# backend — AI session notes

Supabase project for the Run app. Postgres schema, Row-Level Security, Storage buckets, Edge Functions (Deno), and the TypeScript / Dart row-type generators all anchor here. **If you're about to run any `supabase` CLI command, your working directory must be this folder** — the CLI resolves migrations, functions, and config relative to `supabase/config.toml`, which only lives here. The top-level `supabase/` directory at the repo root is the CLI's local state (`.branches`, `.temp`); never write migrations there.

## Layout

```
apps/backend/
├── package.json              # scripts: gen:types, gen:types:check
├── .env.example              # strava + parkrun env vars (public)
├── .env.local                # real values (gitignored)
└── supabase/
    ├── config.toml           # local-stack config — ports, auth, email
    ├── seed.sql              # test user + 12 runs + 5 routes + integrations
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
        └── strava-webhook/index.ts
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

Details, troubleshooting, and drift-detection test recipe: [../../docs/schema_codegen.md](../../docs/schema_codegen.md).

## Migrations

### Naming convention

`{YYYYMMDD}_{NNN}_{description}.sql` — date, three-digit ordinal within the day, underscore-separated description. Matches the existing files exactly.

**Gotcha with multiple migrations on the same day:** Supabase's CLI parses the migration *version* as the longest numeric prefix before the first underscore — i.e. `YYYYMMDD` only. The `_NNN_` ordinal is purely cosmetic and does **not** disambiguate. Two files with different `NNN` on the same day both register as version `YYYYMMDD` and the second `supabase db reset` fails with `duplicate key value violates unique constraint "schema_migrations_pkey"`. Until we introduce more migrations on a single day than the convention was designed for, walk across consecutive dates instead (`20260506_001_*`, `20260507_001_*`, `20260508_001_*`). If you genuinely need same-day disambiguation in one PR, swap to a time-suffix scheme (`YYYYMMDDhhmmss_description.sql` is what `supabase migration new` emits by default) and update this doc.

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

## Edge Functions

Eight functions live under `supabase/functions/`. All are wired up. Test coverage breakdown:

- **Pure helpers** — `_shared/webhook_security.ts`, `_shared/body_limit.ts`, and `revenuecat-webhook/lib.ts` are covered by 45 deno tests across three `*.test.ts` files. Gated in CI by the `edge-functions` job.
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
| `delete-account` | **Working** — recursive Storage prefix walk drains `{user_id}/exports/` blobs alongside top-level tracks. | Client POST (user action) | User JWT + service role for admin delete | `SUPABASE_SERVICE_ROLE_KEY` |
| `clip-public-track` | **Working** — server-side privacy-zone clipping for non-owner viewers. Downloads the gzipped track via service-role, runs `clip_track_for_user`, returns clipped points. Replaces the dropped public-runs Storage policy (decisions §33, audit/storage High). | Anon or user JWT POST with `{ run_id }` | Anon JWT accepted (RLS gates the row read); per-IP rate limit for anon, per-user for authenticated | — |

All seven are short — 25 to 115 lines each. Read the file, not an abstraction; they don't share helpers (other than `_shared/rate_limit.ts` for the throttle).

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
supabase functions serve --env-file .env.local

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

`.env.local` (gitignored) holds real values. `.env.example` holds placeholder values and is committed. Keep the two in sync when you add a new variable.

Supabase Edge Functions read env vars via `Deno.env.get('NAME')`. At runtime in local dev, `--env-file .env.local` on `supabase functions serve` is what populates them. In production, variables are set via `supabase secrets set` against the linked project — a separate flow from `.env.local`.

Variables currently used:

- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — injected by the runtime; you do not set these in `.env.local` for local dev.
- `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` — Strava OAuth credentials.
- `STRAVA_VERIFY_TOKEN` — shared secret for the webhook GET handshake (sent by Strava in `hub.verify_token`).
- `STRAVA_WEBHOOK_SECRET` — shared secret embedded in the callback URL's query string (`?secret=...`). Strava preserves URL query strings on both GET and POST, so this is the only auth available on POST events (Strava doesn't sign payloads). Required: function fails closed without it.
- `CRON_SECRET` — shared bearer token the pg_cron schedule passes to `refresh-tokens` so an unauthenticated caller can't trigger Strava token-refresh churn on every integration in the table. Required: function fails closed without it.
- `PARKRUN_USER_AGENT` — identifies us to parkrun's server. Be polite.

## CLI gotchas I've hit

- **Run every `supabase` command from `apps/backend/`.** The CLI looks for `config.toml` in the cwd and fails or misleads otherwise.
- **`supabase db reset` blows away local data.** The seed repopulates it. If you had manual experiments in the local DB, export them first — the seed will not restore them.
- **`supabase gen types typescript --local` writes `Connecting to db 5432` to stdout** before the real output. The `gen:types` npm script pipes through `grep -v '^Connecting to db'` to strip it. Don't remove that filter.
- **`supabase functions serve` does not autoload `.env.local`**. You must pass `--env-file .env.local` explicitly. A missing env var shows up as a `Deno.env.get('X')!` assertion failure at runtime — the `!` eats the error.
- **Docker must be running.** All local Supabase services run under Docker. If `supabase start` hangs or errors weirdly, check `docker ps`.
- **`deno.lock` lives at the repo root and is committed.** Newer Supabase CLIs write it during `supabase db reset` / `functions serve` to pin Edge Function dependency resolutions (e.g. `https://esm.sh/@supabase/supabase-js@2 → 2.105.1` plus integrity hashes for every transitive Deno URL). The file is created inside the CLI's Docker container as `root:root`, so after a fresh resolution you may need to `sudo chown` it before staging. Treat it like `package-lock.json`: review the diff on dependency-version changes, but otherwise let it ride.

## Before reporting a task done

- If you added or changed a migration: run `supabase db reset` locally, then regenerate both row-type files, then commit the migration + both generated files in one change.
- If you added or changed an Edge Function: deploy-ability has not been tested locally. The user will notice on `main` deploy. Leave a note in the PR description about what you couldn't verify.
- If you added a new env var: update `.env.example` and this file's "Variables currently used" list.
- If you added a new function: update the table in the "Edge Functions" section above. Status column should be honest — stub, partial, or working.
- If you changed `runs.metadata` key usage: update [../../docs/metadata.md](../../docs/metadata.md). The schema generators can't catch drift in there.
