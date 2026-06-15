# Race-director operations — offline aid-station check-in → live results

> **STATUS: building.** The data foundation is shipped (migration
> `20270201_001`): both tables, both RPCs, RLS + the column-lock, and the shared
> `checkpoint_projection` helper. P1 schema + offline volunteer check-in, P2
> organiser live-results / cutoff board (web), P3 weigh-in (Art 9, built
> fail-closed per decisions §150), and P4 public results are landing on top of
> it. Web canonical; mobile mirrors; iOS twin byte-identical. Read
> [CLAUDE.md](../../CLAUDE.md) + [apps/backend/CLAUDE.md](../../apps/backend/CLAUDE.md)
> for conventions.

## What shipped (data foundation — migration `20270201_001`)

- **`event_checkpoints`** — a race's ordered checkpoints (aid stations /
  cutoffs). Per-event `ordinal` (UNIQUE on `(event_id, ordinal)`), an optional
  `route_marker_id` link, an optional position + cutoff (`cutoff_elapsed_s` /
  `cutoff_clock`), and `requires_weigh_in` (default false) — the per-checkpoint
  switch that arms the Art 9 health path. RLS: SELECT per `is_event_visible`,
  writes gated on `private.is_event_organiser(club_id)`.
- **`checkpoint_crossings`** — a runner's in/out stamp at one checkpoint for one
  event instance, written offline by volunteers and synced in batches.
  **Account-optional** identity (`user_id` OR `bib` + `runner_name`, CHECK +
  two NULLs-distinct UNIQUE keys), mirroring `event_results`. SELECT per
  `is_event_visible`; **no direct write policy — writes are RPC-only.** The Art
  9 health columns (`body_weight_kg`, `body_weight_pct`, `medical_hold`,
  `medical_note`) and `recorded_by` are **column-SELECT-locked**: the table
  default is revoked and only the non-health columns are re-granted to
  `anon` / `authenticated`, so the public results surface can never read them.
- **`upsert_checkpoint_crossing(...)`** — the SOLE writer (SECURITY DEFINER).
  Authorises the caller as an organiser (else 42501), validates the event
  (42704) + that the checkpoint belongs to it (23503) + the identity rule
  (23514), then inserts or **merges in/out**: a second call for the same
  `(checkpoint, instance, identity)` reconciles to ONE row with
  `in_time = least(existing, new)` and `out_time = greatest(existing, new)`
  (Postgres `least`/`greatest` ignore NULLs → earliest-in, latest-out,
  fill-the-gap). This is how two client-minted UUIDs on two volunteers' phones
  collapse onto the canonical row.
- **Fail-closed health gate** (decisions §150): the health fields persist ONLY
  when the checkpoint's `requires_weigh_in = true` AND the caller passes
  `p_health_consent = true`; otherwise they are dropped to NULL. Production
  enablement is an owner + CISO + counsel deploy-checklist sign-off, not missing
  code.
- **`fetch_checkpoint_crossings_for_organiser(...)`** — the organiser read path
  (SECURITY DEFINER, 42501 for non-organisers). Returns every crossing for an
  event instance **including** the column-locked health fields, so health data
  only ever reaches a race official.
- **`checkpoint_projection`** — the shared cutoff-projection helper
  (`apps/web/src/lib/runs/checkpoint_projection.ts` ↔
  `apps/mobile_android/lib/checkpoint_projection.dart`). From a runner's actual
  crossings it projects arrival at every remaining checkpoint and grades each
  cutoff safe / tight / miss on the **same scale as `roadbook.ts`** (it imports
  `CUTOFF_TIGHT_S` + `CutoffStatus` rather than redefining them). Backs the P2
  organiser board and the predictive live tracker — one helper, two surfaces.
- **pgtap:** `apps/backend/supabase/tests/checkpoint_crossings_test.sql`
  (17 tests) pins organiser-only writes, event-visibility reads, the offline
  merge dedupe, the identity rule, the health column-lock, the fail-closed
  health gate, and the organiser read path.

## Context / why

The aid-station-volunteer personas (Moab 240 / UTMB / WS100) point at the
biggest gap: an event's volunteers logging each runner's bib **in/out** at each
aid station — **fully offline, no signal** — then syncing to a live results +
cutoff board. This turns "a club hosts an event" into "a race director runs a
race," and is monetizable through the **Stripe Connect events rail already
built** (`events-*` functions, `event_pricing`/`event_orders`). It also dovetails
with markers (which define the checkpoints) and the roadbook cutoff math.

## Reuse (don't re-implement)

- **Events + results:** typed `run`/`class` events, `event_results`
  (**account-optional** since `20261028_001` — surrogate `id`, nullable
  `user_id`, `bib` + `finisher_name`, organiser bulk-insert policy). Race
  control (Arm/Fire/End) already exists on event detail. Stripe Connect host
  payouts already shipped.
- **Markers:** a route's aid stations/cutoffs are the checkpoint definitions
  ([route_markers.md](route_markers.md)); cutoff verdict math is in
  `roadbook.ts`.
- **Offline-first store pattern:** the mobile `OfflineSyncStore` /
  `local_*_store.dart` family (client-minted UUIDs, per-row sync state, batched
  drain) — this is *exactly* the no-signal aid-station data-entry need.

## Design — sliced P1 → P4

### P1 — schema + offline volunteer check-in (ship first)
- **Migration:** `event_checkpoints` (per event: ordered checkpoints, optional
  `route_marker_id` link, optional cutoff) + `checkpoint_crossings`
  (`event_id`, `bib` or `attendee_id`, `checkpoint_id`, `in_time`, `out_time`,
  `recorded_by`, dedupe key). RLS: event organisers write; visibility per event.
  pgtap + both type regens + narrow-union pairs if any.
- **Mobile volunteer screen (offline-first):** pick event + your checkpoint →
  scan/enter bib → stamp in/out → works fully offline via a new
  `local_crossings_store` (mirror `OfflineSyncStore`), syncs in batches when
  signal returns. This is the persona's core surface.

### P2 — live results + cutoff board (web, organiser)
- Organiser dashboard ingesting crossings → per-runner progress + projected /
  blown cutoffs (reuse the roadbook cutoff math) + DNF marking.

### P3 — weigh-in / medical fields (WS100 persona)
- Per-checkpoint body-weight % + a medical-hold flag. **Art 9 health data —
  gate behind consent + CISO/counsel sign-off** (see decisions §150: build the
  code behind a fail-closed gate, don't stub it).

### P4 — public results page
- Finisher list + per-checkpoint splits, account-optional, per event visibility.

## Commit cadence (P1)

1. Migration + RLS + pgtap + both type regens.
2. `api_client` crossing CRUD + the offline `local_crossings_store` + tests.
3. Mobile volunteer check-in screen (+ iOS twin) + Flutter tests + ARB/i18n.
4. (P2) Web organiser board + Playwright.
5. Docs.

## Tests

- pgtap: organiser-only writes; results readable per event visibility;
  offline-then-sync dedupe (two volunteers stamp the same bib → one crossing).
- Unit: cutoff projection from crossings (reuse roadbook math); offline store
  drain + conflict resolution.
- Flutter: offline check-in survives a restart + syncs; Playwright for P2.

## Decisions (resolved — see ADR for the rationale)

- **Bib model:** **both**, like `event_results` — a crossing names its runner by
  an account (`user_id`) OR a `bib` + `runner_name`, never fully anonymous.
- **Offline conflict resolution:** **merge in/out** (earliest-in, latest-out),
  done inside the single `upsert_checkpoint_crossing` RPC so two client-minted
  UUIDs collapse onto the canonical row. Not last-write-wins.
- **Compliance:** P3 weigh-in/medical is Art 9 — **built fail-closed** per §150
  (`requires_weigh_in` + `p_health_consent` gate + column-lock); prod enablement
  is an owner + CISO + counsel deploy-checklist sign-off, not unwritten code.
- **Overlap with [predictive_live_tracking.md](predictive_live_tracking.md):**
  **shared** — both project cutoffs through the one `checkpoint_projection`
  helper, which grades on the same scale as `roadbook.ts`.

## Docs

New decisions ADR(s), a parity row, [api_database.md](../backend/api_database.md)
for the new tables, and likely an update to [club_events.md](club_events.md) /
[instructor_business.md](instructor_business.md) since this extends the events
layer.
