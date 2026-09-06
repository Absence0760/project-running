---
description: Verify every non-owner surface routes tracks/waypoints through the server-side clipping path
---

Audit every surface that renders a track or polyline owned by another user. Every one must route through the SERVER-SIDE clipping path (decisions §33) — or have a documented reason not to.

**There are two such paths, and they are not the same call.** No client holds a `clipTrackForUser` method; the client-side "fetch the blob then clip the points" pattern was removed by migration `20260619_001`, and `20270521_001` then withdrew `clip_track_for_user` from `authenticated` outright, because a caller who can run it can binary-search the owner's zone centres. What a client has today is:

- **A run's track** — `fetchClippedTrackForRun(runId)`, on both clients (`apps/web/src/lib/core/data.ts`, `packages/api_client/lib/src/api_client.dart`). It invokes the `clip-public-track` Edge Function, which downloads the gzipped track with the service role and passes the points through the SQL `clip_track_for_user`.
- **A route's waypoints** — web `fetchClippedRouteForViewer(routeId)`, mobile `ApiClient.clipRouteForViewer(routeId)`. Routes carry their waypoints inline as a jsonb column, so this is a straight `clip_route_for_viewer` RPC with no Edge Function and no Storage indirection.

An audit whose acceptance criterion names a symbol the tree does not have reports a clean result having checked nothing, so check for THESE two, per surface kind.

## Goal

We've fixed three of these — the web feed thumbnail (eb02194), the bound thumbnail caches (fb66e99), and the mobile public run/route screens (48dd4e9). This command exists so a future regression — a new screen, a new component, a new feed surface — gets caught.

## What to check

1. **Inventory every track/waypoint render site.** The pattern: a screen receives a `track`, `waypoints`, `polyline`, `points`, or `route_geom` prop and hands it to a map component. Grep for:
   - Web: `<RunMap`, `<TrackPreview`, `<RunTrackPreview`, `track={`, `waypoints={`, `polyline={` across `apps/web/src/`
   - Mobile: `LiveRunMap(`, `TrackPreview(`, `RunTrackPreview(`, `plannedRoute:`, `track:` across `apps/mobile_android/lib/`
2. **Classify each render site.**
   - **Owner-only** (e.g. `runs_screen`, `run_detail_screen`, the owner branch of `/runs/[id]`) — never clip. Flag if it does.
   - **Owner-or-other** (feed cards, profile recent runs, share pages, public run/route screens, club routes tab, **and the non-owner branch of `/runs/[id]`** — issue #666 gave the canonical run page a second branch that mounts `RunShareView` when the viewer doesn't own a publicly-readable run) — must clip when viewer ≠ owner. A page can be BOTH: `/runs/[id]` renders the unclipped owner track in one `{#if}` branch and the clipped non-owner track in its sibling, so classify per branch, not per route.
   - **Owner-only-by-RLS** — the row is only fetchable by the owner. Document this and confirm the RLS policy actually enforces it (cross-check with `audit/rls`).
3. **Verify the gate.** For every owner-or-other site, the gate should be: viewer id from the auth store / `api.userId`, owner id from the row's `user_id`, **anon treated as non-owner** (`null` viewer id → clip). The exact predicate is:
   ```
   isOwner = viewerId != null && viewerId == ownerId
   ```
   A `viewerId == ownerId` comparison without the null-check is a bug — anon viewers compare `null == null` and are treated as owner.
4. **Verify fail-closed, and know which way each helper fails.** They are not uniform, so a finding has to name the one it is about. `fetchClippedRouteForViewer` (web) and `clipRouteForViewer` (mobile) both swallow the failure and return `[]`. `fetchClippedTrackForRun` THROWS on web (an `error` from `functions.invoke`, or a payload with no `points` array) and returns `[]` on mobile for a malformed payload while letting an invoke failure propagate. In every case the answer to a failure is an empty polyline or an error — never the unclipped input. Owner call sites that always need the unclipped track should bypass the clipping path entirely rather than call it and fall through on `[]`, or a transient outage blanks the owner's own map.
5. **Cache key prefix.** When a thumbnail caches the result, the key must include a `raw:` vs `clip:` prefix so an owner viewing their own card and a follower viewing the same card don't pollute each other's session cache.

## Report

- **High** — a non-owner surface renders the unclipped track.
- **Medium** — owner gate exists but treats anon as owner (privacy leak for unauthenticated public-share traffic).
- **Low** — cache pollution (one viewer's clipped result reused for another, or vice versa).

For each: file:line, the missing call or the broken gate, the surface it affects.

## Useful starting points

- `docs/architecture/decisions.md` §33 — the canonical contract
- `apps/web/src/lib/core/data.ts` — both web helpers, with the migration history in their doc comments
- `packages/api_client/lib/src/api_client.dart` — both mobile helpers
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
