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
    ├── migrations/
    │   ├── 20260405_001_initial_schema.sql
    │   ├── 20260406_001_database_functions.sql
    │   ├── 20260407_001_performance.sql
    │   └── 20260410_001_runs_to_storage.sql
    └── functions/
        ├── export-data/index.ts
        ├── parkrun-import/index.ts
        ├── refresh-tokens/index.ts
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

CI's `parity-types` job runs `npm run gen:types:check` and fails the build if the committed TS file is out of sync with the schema. There is no equivalent CI gate for the Dart generator yet — rely on `dart analyze` to flag stale references in `packages/api_client`.

Details, troubleshooting, and drift-detection test recipe: [../../docs/schema_codegen.md](../../docs/schema_codegen.md).

## Migrations

### Naming convention

`{YYYYMMDD}_{NNN}_{description}.sql` — date, three-digit ordinal within the day, underscore-separated description. Matches the existing files exactly.

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

Five functions live under `supabase/functions/`. Two are wired up and shippable; three are skeletons with `TODO` markers. None currently have tests.

| Function | Status | Trigger | Auth | Env vars |
|---|---|---|---|---|
| `parkrun-import` | **Working** (scraper) | Client POST with `{ athleteNumber }` | User JWT → `supabase.auth.getUser()` | `PARKRUN_USER_AGENT` |
| `refresh-tokens` | **Working** | Scheduled (pg_cron) every hour | Service role (`SUPABASE_SERVICE_ROLE_KEY`) | `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` |
| `strava-import` | **Partial** — OAuth + token store works, backfill is a TODO | Client POST with `{ code, scope }` from OAuth redirect | User JWT | `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` |
| `strava-webhook` | **Partial** — verification works, activity sync is a TODO | GET verification from Strava + POST activity events | Service role (webhook is public) | `STRAVA_VERIFY_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY` |
| `export-data` | **Stub** — every step is a TODO | Client POST with `{ format }` | User JWT | — |

All five are short — 25 to 70 lines each. Read the file, not an abstraction; they don't share helpers.

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

For Phase 1, option 4 is what's been done (or nothing). If you're about to write a test for an Edge Function, flag it to the user before going down a rabbit hole — the honest truth is that nothing in the existing CI exercises Edge Functions end-to-end.

### Deploying functions to production

Handled by CI in `.github/workflows/ci.yml`'s `deploy-functions` job on push to `main`. Do not deploy manually in dev — you'll clobber whatever's live. If you need to run a one-off deploy, ask first.

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
- `STRAVA_VERIFY_TOKEN` — shared secret for the webhook GET handshake.
- `PARKRUN_USER_AGENT` — identifies us to parkrun's server. Be polite.

## CLI gotchas I've hit

- **Run every `supabase` command from `apps/backend/`.** The CLI looks for `config.toml` in the cwd and fails or misleads otherwise.
- **`supabase db reset` blows away local data.** The seed repopulates it. If you had manual experiments in the local DB, export them first — the seed will not restore them.
- **`supabase gen types typescript --local` writes `Connecting to db 5432` to stdout** before the real output. The `gen:types` npm script pipes through `grep -v '^Connecting to db'` to strip it. Don't remove that filter.
- **`supabase functions serve` does not autoload `.env.local`**. You must pass `--env-file .env.local` explicitly. A missing env var shows up as a `Deno.env.get('X')!` assertion failure at runtime — the `!` eats the error.
- **Docker must be running.** All local Supabase services run under Docker. If `supabase start` hangs or errors weirdly, check `docker ps`.

## Before reporting a task done

- If you added or changed a migration: run `supabase db reset` locally, then regenerate both row-type files, then commit the migration + both generated files in one change.
- If you added or changed an Edge Function: deploy-ability has not been tested locally. The user will notice on `main` deploy. Leave a note in the PR description about what you couldn't verify.
- If you added a new env var: update `.env.example` and this file's "Variables currently used" list.
- If you added a new function: update the table in the "Edge Functions" section above. Status column should be honest — stub, partial, or working.
- If you changed `runs.metadata` key usage: update [../../docs/metadata.md](../../docs/metadata.md). The schema generators can't catch drift in there.
