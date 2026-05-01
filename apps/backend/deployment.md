# Backend deployment plan

How `apps/backend/` (the whole Supabase project — Postgres, Auth, Storage, Realtime, Edge Functions, pg_cron) runs in production.

This file is the operational counterpart of [`apps/backend/CLAUDE.md`](CLAUDE.md) (which describes the schema + EF + helpers) and [`apps/backend/local_testing.md`](local_testing.md) (the local stack). For the cross-service overview see [`docs/deployment.md`](../../docs/deployment.md). Tag-driven release mechanics live in [`docs/releasing.md`](../../docs/releasing.md).

**Status: plan.** Local-only at the time of writing.

---

## Provider and tier

**Provider:** Supabase Cloud.

**Tier: Pro ($25/month).** Required for:

- Daily Point-In-Time Recovery (free tier is project-only snapshots with a 7-day window)
- Custom domain (`api.runonward.app`)
- Larger compute (4 GB RAM minimum) — the materialized-view refresh + the run-write trigger fan-out push the free tier's 1 GB instance into swap fast as soon as bulk Strava imports run
- 8 GB Storage included (raw track gzips are ~10 KB each; 1k users × 200 runs ≈ 2 GB → fits Pro for the foreseeable)
- Removal of the 1-week pause on inactive projects

**Region:** `eu-west-2` (London). Picked because most expected early users are EU/UK and the cross-Atlantic latency adds 70–100 ms to every PostgREST round trip. Switch to `us-east-1` if the user mix shifts; the migration is a one-time `pg_dump | pg_restore` window.

**Compute add-ons:** none at launch. Revisit when:
- p95 query latency on the dashboard query exceeds 500 ms (Supabase Reports → Database → Query Performance)
- The `mv_weekly_mileage` refresh starts taking >30 s (currently ~2 s on dev)

---

## One-time project setup

```bash
# 1. Create the Supabase Cloud project in the dashboard (Pro tier, eu-west-2).
# 2. From a local clone:
cd apps/backend
supabase login                     # opens browser for OAuth
supabase link --project-ref <ref>  # ref is the slug from the dashboard URL
```

The `supabase link` step writes `.temp/project-ref` and `.temp/cli-version` (gitignored). Don't commit them.

```bash
# 3. Push the migration history.
supabase db push
# → applies every file under supabase/migrations/ in order.
# → on a fresh project, expect a few minutes for the PostGIS extension
#   create + the initial seed-shape migrations.
```

After the first push, set up the cron extension and the schedules. They're idempotent:

```bash
supabase db reset --linked   # NEVER on a project with real users.
                             # Use during the initial bring-up only.
```

**`supabase db reset --linked` warning.** It drops every table and replays migrations from scratch. Safe before launch; catastrophic after. The CI workflow that handles `backend@*` does *not* call `--linked` — it uses `db push`, which only applies migrations that haven't been applied yet.

---

## Edge Function deploys

```bash
# Deploy one:
supabase functions deploy parkrun-import --project-ref <ref>

# Deploy all seven at once (this is what the release workflow does):
for fn in parkrun-import refresh-tokens strava-import strava-webhook \
          revenuecat-webhook delete-account export-data; do
  supabase functions deploy "$fn" --project-ref <ref>
done
```

**EF environment variables** are set per-project via `supabase secrets set`. Required:

```bash
cd apps/backend

supabase secrets set --project-ref <ref> \
  PARKRUN_USER_AGENT="run-app/1.0 (+https://runonward.app/bot)" \
  STRAVA_CLIENT_ID="..." \
  STRAVA_CLIENT_SECRET="..." \
  STRAVA_VERIFY_TOKEN="$(openssl rand -hex 16)" \
  STRAVA_WEBHOOK_SECRET="$(openssl rand -hex 32)" \
  REVENUECAT_WEBHOOK_SECRET="..."   # paste from RevenueCat dashboard \
  SENTRY_DSN="..."                  # backend Sentry project DSN; empty disables \
  APP_RELEASE="backend@$(git describe --tags --abbrev=0)"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected by the platform — you don't `supabase secrets set` those.

**Strava OAuth callback URL.** Once the project is live, set the Strava developer dashboard's redirect URL to `https://runonward.app/auth/strava/callback`. The `strava-import` EF expects to receive the OAuth `code` from a client-side POST after the redirect lands on the web app.

**RevenueCat webhook URL.** In the RevenueCat dashboard → Project → Integrations → Webhooks, set:
- URL: `https://<ref>.supabase.co/functions/v1/revenuecat-webhook`
- Auth header: `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`

**Strava webhook URL.** Once you're issuing OAuth tokens you'll need to call `POST https://www.strava.com/api/v3/push_subscriptions` with our callback URL `https://<ref>.supabase.co/functions/v1/strava-webhook?secret=<STRAVA_WEBHOOK_SECRET>` and the `STRAVA_VERIFY_TOKEN`. Strava verifies, persists the subscription, and starts firing events.

---

## Custom domain — `api.runonward.app`

Optional but recommended; lets us migrate Supabase projects (region change, account swap) without invalidating every client's stored URL.

In the Supabase dashboard → Settings → Custom Domains:

1. Add `api.runonward.app`.
2. Supabase prints a CNAME target (`<ref>.supabase.co`) and a TXT verification record.
3. Add both to Cloudflare DNS (or whichever registrar you use). TTL 300.
4. Wait for verification (usually a few minutes; can take up to an hour).
5. Once verified, every client's `SUPABASE_URL` becomes `https://api.runonward.app` instead of `https://<ref>.supabase.co`.

Update the value in:
- Vercel env (`PUBLIC_SUPABASE_URL`)
- Mobile build configs (`apps/mobile_android/.env.production`, `apps/mobile_ios/dart_defines.json` for the production scheme)
- Wear OS Gradle property (`SUPABASE_URL` in `apps/watch_wear/android/.env.local` for prod builds — or pass via `-PSUPABASE_URL=...` in CI)

---

## CI deploy path

Triggered by tagging `backend@*`. The workflow at `.github/workflows/release-backend.yml`:

1. Checks out the tag.
2. Installs the Supabase CLI.
3. `supabase login --token $SUPABASE_ACCESS_TOKEN`.
4. `supabase link --project-ref $SUPABASE_PROJECT_REF`.
5. `supabase db push` — applies any unapplied migrations.
6. Loops over `supabase/functions/*/index.ts` and `supabase functions deploy` each.
7. Creates a GitHub Release pointing at the tag with the migration manifest as a release note.

Required GitHub Secrets (also listed in [releasing.md](../../docs/releasing.md)):

| Secret | Where to get it |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Supabase dashboard → Account → Access Tokens (personal access token) |
| `SUPABASE_PROJECT_REF` | The `<ref>` from the project URL |
| `SUPABASE_DB_PASSWORD` | Set during project creation; can be reset in the dashboard |

---

## Data layout in production

The schema is what local `supabase db reset` builds — see [api_database.md](../../docs/api_database.md) for the table-by-table reference.

**Storage buckets** (configured by migration `20260405_001_initial_schema.sql` and the photos / route-files migrations that came after):

| Bucket | Public? | Path convention | RLS |
|---|---|---|---|
| `runs` | private | `{user_id}/{run_id}.json.gz`, `{user_id}/{run_id}.matched.json.gz` | owner-only via the `runs.user_id = auth.uid()` policy on the parent row |
| `route-files` | private | `{user_id}/{route_id}.gpx` etc. | owner-only |
| `run-photos` | private | `{user_id}/{run_id}/{photo_id}.jpg` | owner-only ([decisions.md § 36](../../docs/decisions.md#36-photos-on-runs-own-table--storage-bucket-visibility-tracks-the-parent-run)) |
| `avatars` | public | `{user_id}.{ext}` | anyone authenticated can SELECT, owner can write |

`/share/run/[id]` and `/share/route/[id]` rendering anonymous tracks works through the `clip_track_for_user` RPC ([decisions.md § 33](../../docs/decisions.md#33-privacy-zones-server-side-clipping)) — the bucket itself stays private, the RPC returns clipped points to anon callers.

---

## Observability

| Surface | Where | What |
|---|---|---|
| Postgres logs | Supabase dashboard → Logs → Postgres | slow queries, deadlocks, errors |
| EF logs | Supabase dashboard → Logs → Edge Functions | invocation count, runtime, console output |
| Auth events | Supabase dashboard → Auth → Logs | sign-in success/failure, JWT issues |
| Realtime | Supabase dashboard → Realtime → Channels | active subscribers, message rate |
| Custom queries | `select * from postgres_log;` from the SQL editor | one-off forensics |

**External uptime probe** (Better Stack or UptimeRobot): hit `https://api.runonward.app/rest/v1/runs?select=count&limit=0`. It's a cheap PostgREST call that returns 200 only if Postgres is up + PostgREST is up + RLS still permits the anon role to read the table count. Set the alarm threshold at 2 consecutive failures (60 s gap).

**Sentry on the EF side:** every EF wraps its `serve` handler in `withSentry('<ef-name>', ...)` from `functions/_shared/sentry.ts`. Unhandled errors are captured with the EF name as a tag, then a 500 is returned so the caller still gets a clean response. Init is gated on `SENTRY_DSN` — set it via `supabase secrets set SENTRY_DSN=... APP_RELEASE=<tag>` against the linked project; an unset DSN makes the wrapper a passthrough so local `supabase functions serve` doesn't need a Sentry account.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Pro plan | base | $25 |
| Compute add-on | none at launch | $0 |
| Storage past 8 GB | $0.021/GB above 8 GB | $0 → modest |
| Egress past 250 GB | $0.09/GB | $0 → modest |
| Daily PITR backup | included | $0 |
| Custom domain | included on Pro | $0 |
| **Subtotal** | | **$25** |

Scaling drivers:

- 10k active users × 200 runs/year × 10 KB tracks ≈ 20 GB Storage → ~$0.25 above included
- Heavy bulk-import users (Strava 5-year backfills, ~30 MB per user) drive Storage faster than recording does
- Coach + dashboard activity drives egress; expect Vercel's Pro bandwidth to tip first

---

## Disaster recovery

### Quarterly drill (mandatory)

Without exercising it, the backup is a fiction. Run this once per quarter, document the timing in a top-comment on this file:

```bash
# 1. Create a fresh staging project at supabase.com (free tier is fine).
# 2. From a local clone of project-running:
cd apps/backend
supabase link --project-ref <staging-ref>

# 3. From the production project's dashboard, download the latest daily backup
#    (Settings → Database → Backups → Download).
# 4. Restore into the staging project.
supabase db reset --linked         # wipe the staging instance
psql "<staging-connection-string>" < backup.sql

# 5. Point a local web build at the staging URL + anon key.
PUBLIC_SUPABASE_URL=https://<staging-ref>.supabase.co \
PUBLIC_SUPABASE_ANON_KEY=<staging-anon-key> \
  npm run dev --workspace=apps/web

# 6. Sign in as a known seed user; verify dashboard / runs list / run detail render.
# 7. Tear down the staging project. Record the timing in this file.
```

Target metrics: end-to-end restore in <30 min, smoke test in <10 min.

### Real-incident playbook

If production Postgres is corrupt / lost / wedged:

1. **Don't push schema changes** — they would propagate to the rebuilt instance.
2. Open the dashboard → Settings → Database → Backups. Pick the most recent good backup.
3. **Point In Time Recovery** lets you restore to any minute in the last 7 days. Use it if the corruption has a known timestamp; use the daily backup otherwise.
4. The restore goes to a new project (Supabase doesn't restore-in-place). The new project gets a new `<ref>`.
5. Update the `api.runonward.app` CNAME to the new project. Within 5 min DNS propagates and clients resume.
6. Edge Functions don't migrate automatically — re-run `supabase functions deploy` for each.
7. Once the new project has been smoke-tested, archive the old one (don't delete for 7 days in case you need to grab additional data).

**RTO ≤ 30 min** as long as DNS is the only client-side knob.
**RPO ≤ 5 min** with PITR; **≤ 24 h** without (daily backup only).

### Storage recovery

Storage objects don't share Postgres's PITR. Two protections:

1. **Bucket versioning.** Enable on the `runs` bucket (`Settings → Storage → Buckets → runs → Object Versions: ON`). Costs ~10% extra storage but makes accidental deletion recoverable for 30 days. Don't enable on `run-photos` — image versioning would balloon the bill.
2. **External cold copy.** A weekly `rclone` sync of the `runs` bucket to S3 / Backblaze B2 covers the case where the entire Supabase project is lost. Cron on the Fly.io worker — see [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) § Cold-storage backup (proposed).

---

## Rollback

Migrations are one-way. We never "roll back" a migration — write a compensating forward migration.

EFs roll back by re-deploying the previous tag's code:

```bash
git checkout backend@1.2.2
cd apps/backend
supabase functions deploy <fn> --project-ref <ref>
git checkout main
```

If a `backend@1.2.3` deploy broke a function, tag `backend@1.2.4` from a revert commit and let the workflow handle it. Avoid the hand-rolled flow above unless the workflow itself is what broke.

---

## Production readiness checklist

Before flipping the row in [`docs/deployment.md`](../../docs/deployment.md) from "Plan" to "Live":

- [ ] Pro tier active, billing alert set in Supabase dashboard
- [ ] `eu-west-2` region (or whichever was picked) confirmed
- [ ] `supabase db push` ran clean against the live project
- [ ] All seven Edge Functions deployed; each logs a successful test invocation
- [ ] EF secrets set (`PARKRUN_USER_AGENT`, Strava env, RevenueCat env)
- [ ] Custom domain `api.runonward.app` verified
- [ ] `pg_cron` schedules confirmed (`SELECT * FROM cron.job;` from SQL editor)
- [ ] Storage versioning on for `runs`
- [ ] External uptime probe live
- [ ] Backup drill performed at least once
- [x] Sentry project + DSN wired into the EF base — every EF wraps `serve` in `withSentry('<ef-name>', ...)` from `functions/_shared/sentry.ts`; `SENTRY_DSN` + `APP_RELEASE` set via `supabase secrets set`. Unset DSN keeps the wrapper a passthrough.
- [ ] `parity.md` rows marked ✓ for the EF-driven features
