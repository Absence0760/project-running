# Job worker + OSRM deployment plan

How the Go worker at `apps/job_worker/` and the OSRM map-matching engine at `apps/job_worker/osrm/` run in production.

Operational counterpart of [`apps/job_worker/CLAUDE.md`](CLAUDE.md) (worker contract, scope, error classification) and [`apps/job_worker/README.md`](README.md) (local dev recipe). For the cross-service overview see [`docs/deployment.md`](../../docs/deployment.md).

**Status: plan.** The worker binary compiles, tests pass, OSRMMatcher is wired behind the `OSRM_URL` env switch, and the live spectator hub (HTTP + WebSocket) is wired into the same binary alongside `/health`. Neither app has been deployed. All config (fly.toml, env examples, secrets list, DNS) is ready — the remaining step is `flyctl deploy --remote-only` from an operator with `FLY_API_TOKEN`.

---

## Two services, one pair

The worker is small (single Go binary, ~9 MB distroless) and the OSRM engine is heavy (~50 MB binary plus a multi-GB graph). They have different sizing, different update cadences, and different failure modes — they want to be separate Fly.io apps even though they always deploy together.

```
Fly.io organisation: runonward
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

Why same Fly.io organisation: 6PN gives them a private network at no cost. The worker calls `http://osrm.internal:5000/match/v1/foot/...` and never goes through public internet.

Why the worker app stays separate from OSRM: independent restart (worker → 5 s, OSRM → 90 s as graph re-mmaps), independent scaling (more workers without paying OSRM RAM each time), independent rollout (engine retune doesn't redeploy the queue drainer).

---

## Provider — Fly.io

**Provider:** Fly.io.

**Why not Cloud Run:** request-response only, no long-lived processes. The worker polls `claim_next_job` continuously; the OSRM container holds graph state in RAM. Both fit Fly.io machines better than serverless functions.

**Why not a dedicated VM:** Fly.io has the same cost-per-RAM as a small DO/Linode/EC2 with batteries-included logging, secrets, and zero-downtime deploys. We'd reach for a dedicated VM only if the OSRM RAM goes past ~64 GB — at which point we're talking continent-scale extracts and the discussion shifts.

**Region:** `lhr` (London) or `cdg` (Paris). Match the Supabase region to keep the worker → Postgres round-trip under 10 ms; OSRM lives in the same region so 6PN traffic is intra-DC.

**Account org**: create a `runonward` Fly.io org. Both apps live under it. Billing is per-org; secrets are per-app.

---

## Worker app — `job_worker`

### Sizing

- `shared-cpu-1x`, 256 MB RAM. The worker is mostly idle on a poll loop; matching is delegated to OSRM. RAM ceiling is during a Storage upload of a matched gzip (~hundreds of KB in flight). The hub's in-process pub/sub state is negligible — a `map[string]*room` with at most a few hundred bytes per active run.
- 1 machine baseline. Add a second when the active set in `jobs.status='queued' AND scheduled_at <= now()` regularly exceeds ~50, or when concurrent live-spectator viewers regularly exceed ~500. (Per-room fan-out is in-process, so a second machine roughly halves the per-machine viewer load.)
- `auto_start_machines = true`, `auto_stop_machines = false`. The worker is supposed to be always-on; auto-stop would just delay the next claim by the cold-start time. Live-hub WS subscribers also drop if the machine stops.

### `fly.toml`

Lives at [`fly.toml`](fly.toml). Shape (matches the actual checked-in file — keep this snippet in sync if you edit it):

```toml
app = "job_worker"
primary_region = "lhr"

[build]
dockerfile = "Dockerfile"

[env]
WORKER_ID = "fly-${FLY_MACHINE_ID}"
OSRM_URL = "http://osrm.internal:5000"
# Comma-separated WS Origin allow-list. Anything not listed gets a 403 at
# the WS handshake. Production clients: apps/web prod + preview.
LIVEHUB_ALLOWED_ORIGINS = "https://app.runapp.com,https://run.app,https://preview.runonward.com"

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

```bash
flyctl secrets set --app job_worker \
  SUPABASE_URL="https://<ref>.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="..."
```

`SUPABASE_SERVICE_ROLE_KEY` is **dual-use**: the worker reads it to claim jobs (PostgREST RPCs `claim_next_job` / `finish_job` / `defer_job` are granted only to `service_role`) AND the live hub reads it via `SupabaseZoneFetcher` to fetch a runner's privacy zones for server-side ping clipping. One secret, one identity — there's no per-concern split.

`OSRM_URL` and `LIVEHUB_ALLOWED_ORIGINS` are in `[env]` (not secrets) because the values themselves are non-sensitive and we want them visible in `flyctl status`.

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
| Worker logs | `flyctl logs --app job_worker` |
| Per-machine metrics (CPU, RAM, restarts) | Fly.io dashboard → Metrics |
| Queue lag | Custom: `select count(*) from jobs where status='queued' and scheduled_at <= now()` — wire to a Better Stack heartbeat that PG-queries every minute and alerts if >50 |
| Worker liveness | Heartbeat: have the worker `update jobs set scheduled_at = ... where ...` once per claim; alert if no claim observed in >10 min while queued > 0 |
| Hub liveness | The `/health` HTTP check above also covers the hub — both concerns share the binary, so a hub crash trips the same probe |
| Hub fan-out / drop counts | Logged on each push (room subscriber count, drops from zone clip). No metrics endpoint yet — `flyctl logs` + a `jq`-friendly filter is the path until Prometheus lands |

The worker exposes a `/health` endpoint on `:8080` (override with `HEALTH_PORT`). Returns 200 + a small JSON body while the poll loop ticks, 503 once the heartbeat ages past 10 s — long enough that a job mid-handle is fine but short enough that a wedged loop is caught. `fly.toml` declares both a TCP check and an HTTP check against `/health`; Fly's auto-restart catches stale machines without a watchdog of our own.

### Rollback

```bash
flyctl releases --app job_worker
flyctl releases rollback <version> --app job_worker
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
flyctl certs add live.runonward.com --app job_worker

# Then add a Route 53 record (managed via infra/dns/) — CNAME to
# job_worker.fly.dev (or A/AAAA to the Fly anycast IPs reported by
# `flyctl ips list --app job_worker`).
```

Once the cert lights up green in `flyctl certs show live.runonward.com`, the hub is reachable at `https://live.runonward.com/v1/live/...`.

### Client env flip

After DNS resolves and a smoke-test push round-trips:

1. **Web** — set `PUBLIC_LIVE_HUB_URL=https://live.runonward.com` in the prod sops blob (`infra/envs/prod/secrets.sops.json` → `runtime.PUBLIC_LIVE_HUB_URL`). Rebuild + redeploy via the `web@*` tag.
2. **Mobile** — set `LIVE_HUB_URL=https://live.runonward.com` in the Android + iOS release `.env` (not committed; injected at build time). Ship a new build through the Play Console / TestFlight.

Both clients pick up the new transport on next launch. Old builds with the env unset stay on the Supabase Realtime path — they continue to work because the trigger-driven `live_run_pings` table still receives pings from any recorder that hasn't been updated. Roll-forward is gradual.

### Privacy zones — fail-closed contract

`Server.shouldDrop` runs `IsInAnyZone(p.lat, p.lng, room.zones)` on every push. Zones are fetched once per room via `SupabaseZoneFetcher` (PostgREST: `runs?id=eq.<id>&select=user_id` then `user_settings?user_id=eq.<owner>&select=prefs`) and cached on the room until garbage collection.

**A Supabase outage drops the ping rather than risk leaking a home coordinate.** The response is `{ok:false, clipped:true, reason:"zone fetch failed"}`. The mobile broadcaster swallows this per the L4 best-effort contract — the run still records locally and uploads when the network recovers; only the live spectator stream goes dark. This mirrors the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger on the Supabase Realtime path so both transports honour the same contract.

### Hub deploy checklist

- [ ] `flyctl deploy --remote-only` from `apps/job_worker/` (or push a `worker@*` tag once `release-worker.yml` lands)
- [ ] `flyctl certs add live.runonward.com --app job_worker` and Route 53 record pointing at it
- [ ] `flyctl certs show live.runonward.com` shows a valid Let's Encrypt cert
- [ ] `curl https://live.runonward.com/health` returns `{"status":"ok"}`
- [ ] Smoke push: `curl -X POST https://live.runonward.com/v1/live/test-run/push -H 'content-type: application/json' -d '{"ts":1700000000,"lat":51.5,"lng":-0.1}'` returns `{"ok":true,"fanout":0}` (or `clipped:true` if test-run sits inside a seed user's zone, which is also a healthy signal)
- [ ] WS Origin allow-list (`LIVEHUB_ALLOWED_ORIGINS` in `[env]`) covers every host that will subscribe (prod web + preview web + any dev tunnel that needs to be tested against prod)
- [ ] `PUBLIC_LIVE_HUB_URL` set in the web prod sops blob, redeployed
- [ ] `LIVE_HUB_URL` set in the next mobile release builds
- [ ] After the cutover, watch `flyctl logs --app job_worker` for a session — confirm zone-clip drop counts look sane (not 100 %, not 0 %)

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
5. Bumps `OSRMMatcher.AlgVersion` (the worker re-matches stale rows on next claim — see [decisions.md § 45](../../docs/decisions.md#45-server-side-map-matching-uses-osrm-not-valhalla-meili-or-graphhopper)).

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
      - run: flyctl deploy --app job_worker --remote-only
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

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| job_worker — `shared-cpu-1x` 256 MB | always-on, single machine | ~$5 |
| OSRM — `performance-2x` 8 GB | always-on, single machine | ~$30 |
| OSRM — 20 GB volume | per Fly volume pricing | ~$3 |
| Bandwidth | mostly internal 6PN (free); Storage egress goes through Supabase | <$5 |
| **Subtotal** | | **~$40** |

Scaling drivers:

- More worker machines ($5 each) once queue lag becomes noticeable.
- OSRM RAM as the extract grows: UK → Europe → planet. Each step ~10× the RAM bill.
- Re-matches against an upgraded engine briefly spike the worker rate; doesn't change the per-call cost.

---

## Disaster recovery

### Worker

Stateless. Deleting and recreating the app loses nothing. Procedure:

```bash
flyctl apps destroy job_worker --yes
flyctl launch --copy-config --no-deploy --name job_worker --region lhr
flyctl secrets set --app job_worker SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=...
flyctl deploy --app job_worker
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

- [ ] Fly.io org `runonward` created, `job_worker` app exists in `lhr`
- [ ] `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` set as secrets
- [ ] `OSRM_URL` set to `http://osrm.internal:5000` in `[env]`
- [ ] Single machine deployed; `flyctl logs` shows `"matcher selected" engine=osrm`
- [ ] Drained at least one real `map_match` job end-to-end (insert test run, watch `run_matched_tracks` flip to matched)
- [ ] Queue-lag alert wired
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
- [ ] [`docs/parity.md`](../../docs/parity.md) "Server-side HMM map matching" row updated to reflect the live engine
