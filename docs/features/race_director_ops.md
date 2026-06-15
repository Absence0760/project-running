# Race-director operations — offline aid-station check-in → live results

> **STATUS: handoff spec, not built. LARGEST of the set — slice it.** Read
> [CLAUDE.md](../../CLAUDE.md) + [apps/backend/CLAUDE.md](../../apps/backend/CLAUDE.md)
> for conventions. Web canonical; mobile mirrors; iOS twin byte-identical.
> **Recommend building P1 (schema + offline check-in) as its own deliverable
> before P2+.**

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

## Open decisions for the implementer (ask the user — several are real forks)

- **Bib model:** free-text bib vs link to a registered `event_attendees` row
  (or both, like `event_results`).
- **Offline conflict resolution:** two volunteers stamp the same bib at the same
  checkpoint — last-write-wins vs merge in/out.
- **Compliance:** P3 weigh-in/medical is Art 9 — confirm the consent + sign-off
  gate before building it (build the code, gate it fail-closed, per §150).
- **Overlap with [predictive_live_tracking.md](predictive_live_tracking.md):**
  both project cutoffs — share the helper.
- **Scope of P1** — recommend schema + offline check-in only; defer P2–P4.

## Docs

New decisions ADR(s), a parity row, [api_database.md](../backend/api_database.md)
for the new tables, and likely an update to [club_events.md](club_events.md) /
[instructor_business.md](instructor_business.md) since this extends the events
layer.
