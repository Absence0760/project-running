# Local testing — Backend (Supabase)

The backend must be running before any client app can authenticate or sync data. Start this first.

---

## Prerequisites

| Tool | Install |
|---|---|
| Docker Desktop | `docker.com/products/docker-desktop` |
| Supabase CLI | `brew install supabase/tap/supabase` |

---

## Starting the local stack

```bash
cd apps/backend

# Start Postgres, Auth, Storage, and REST API
supabase start
```

On first run this pulls Docker images — takes a few minutes. On success it prints:

```
API URL:       http://localhost:54321
anon key:      eyJ...
service_role:  eyJ...
DB URL:        postgresql://postgres:postgres@localhost:54322/postgres
Studio URL:    http://localhost:54323
```

**Save the `anon key`** — every client app needs it.

---

## Apply database migrations

```bash
supabase db reset
```

This drops and recreates the local database using the migration files in `supabase/migrations/`. Run this whenever you pull new migration files.

---

## Start Edge Functions

```bash
# Create .env.local from the example
cp .env.example .env.local
# Fill in STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET (optional for basic testing)

supabase functions serve --env-file .env.local
```

Functions are now available at `http://localhost:54321/functions/v1/{function-name}`.

You can test them with curl:

```bash
# Example: test parkrun import
curl -X POST http://localhost:54321/functions/v1/parkrun-import \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"athleteNumber": "A123456"}'
```

---

## Supabase Studio

Open `http://localhost:54323` in your browser to:

- Browse and edit table data
- Run SQL queries
- Inspect auth users and sessions
- View storage buckets

---

## Environment variables

| Variable | Where to set | Value |
|---|---|---|
| `STRAVA_CLIENT_ID` | `apps/backend/.env.local` | From Strava developer portal (optional) |
| `STRAVA_CLIENT_SECRET` | `apps/backend/.env.local` | From Strava developer portal (optional) |
| `PARKRUN_USER_AGENT` | `apps/backend/.env.local` | Any user agent string |

---

## Stopping

```bash
cd apps/backend
supabase stop
```

To stop and remove all local data (full reset):

```bash
supabase stop --no-backup
```

---

## Troubleshooting

### "Port 54321 already in use"

A previous Supabase instance is still running:

```bash
supabase stop
supabase start
```

### Docker not running

`supabase start` requires Docker Desktop to be running. Open Docker Desktop and wait for it to finish starting before retrying.

### Migrations fail

Check the SQL syntax in `supabase/migrations/`. Run `supabase db reset` to apply all migrations from scratch. Look at the error output — it usually points to the exact line number.

---

*Last updated: April 2026*
