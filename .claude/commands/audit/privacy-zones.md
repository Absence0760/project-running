---
description: Verify every non-owner surface routes tracks/waypoints through clipTrackForUser
---

Audit every surface that renders a track or polyline owned by another user. Every one must route through `clipTrackForUser` (decisions §33) — or have a documented reason not to.

## Goal

We've fixed three of these — the web feed thumbnail (eb02194), the bound thumbnail caches (fb66e99), and the mobile public run/route screens (48dd4e9). This command exists so a future regression — a new screen, a new component, a new feed surface — gets caught.

## What to check

1. **Inventory every track/waypoint render site.** The pattern: a screen receives a `track`, `waypoints`, `polyline`, `points`, or `route_geom` prop and hands it to a map component. Grep for:
   - Web: `<RunMap`, `<TrackPreview`, `<RunTrackPreview`, `track={`, `waypoints={`, `polyline={` across `apps/web/src/`
   - Mobile: `LiveRunMap(`, `TrackPreview(`, `RunTrackPreview(`, `plannedRoute:`, `track:` across `apps/mobile_android/lib/`
2. **Classify each render site.**
   - **Owner-only** (e.g. `/runs/[id]`, `runs_screen`, `run_detail_screen`) — never clip. Flag if it does.
   - **Owner-or-other** (feed cards, profile recent runs, share pages, public run/route screens, club routes tab) — must clip when viewer ≠ owner.
   - **Owner-only-by-RLS** — the row is only fetchable by the owner. Document this and confirm the RLS policy actually enforces it (cross-check with `audit/rls`).
3. **Verify the gate.** For every owner-or-other site, the gate should be: viewer id from the auth store / `api.userId`, owner id from the row's `user_id`, **anon treated as non-owner** (`null` viewer id → clip). The exact predicate is:
   ```
   isOwner = viewerId != null && viewerId == ownerId
   ```
   A `viewerId == ownerId` comparison without the null-check is a bug — anon viewers compare `null == null` and are treated as owner.
4. **Verify fail-closed.** `clipTrackForUser` returns `[]` on RPC error. Owner-callsites that always need the unclipped track should bypass the RPC, not call it and fall through on `[]` — otherwise a transient outage blanks the owner's own map.
5. **Cache key prefix.** When a thumbnail caches the result, the key must include a `raw:` vs `clip:` prefix so an owner viewing their own card and a follower viewing the same card don't pollute each other's session cache.

## Report

- **High** — a non-owner surface renders the unclipped track.
- **Medium** — owner gate exists but treats anon as owner (privacy leak for unauthenticated public-share traffic).
- **Low** — cache pollution (one viewer's clipped result reused for another, or vice versa).

For each: file:line, the missing call or the broken gate, the surface it affects.

## Useful starting points

- `docs/architecture/decisions.md` §33 — the canonical contract
- `apps/web/src/lib/components/RunTrackPreview.svelte` — reference web implementation
- `apps/mobile_android/lib/widgets/run_track_preview.dart` — reference mobile implementation
- `apps/mobile_android/lib/screens/public_run_screen.dart` + `public_route_screen.dart` — the most recent fix
- `apps/web/src/lib/components/RunShareView.svelte` + `apps/web/src/routes/share/route/[id]/+page.svelte` — the owner-bypass-RPC pattern
- `apps/mobile_android/test/architecture_guards_test.dart` — the `thumbnail privacy-zone clipping` group; new render sites should grow this group

## Delegate to

Use the `repo-security-auditor` agent: `"Audit every track / waypoint render site for privacy-zone clipping coverage per decisions §33."`

Read-only audit. Don't patch a leak without flagging it for the user first.

## Output → `reviews/`

Persist the findings to `reviews/audit-privacy-zones.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
