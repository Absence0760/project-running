# Route course markers

Lets a route owner annotate a saved route line with **course markers** — the
per-point detail a race / ultra course needs that the bare geometry can't carry:
aid stations, cut-offs, crew / parking access, hazards, notes, climbs. Markers
**follow the route's visibility**: private routes keep them private; on a public
or club-shared route, anyone who can see the route sees the markers (so a race
director or club can publish an annotated course).

Web is the canonical surface (`/routes/[id]`); mobile mirrors it; iOS stays
byte-identical to Android.

## Data model

Migration `20270129_001_route_markers.sql`. One table:

```
route_markers
  id, route_id → routes(id) on delete cascade, user_id (= route owner),
  kind        text   -- narrow union (CHECK + RouteMarkerKind TS union)
  label       text   -- 1..120 chars
  lat, lng    double precision
  position_m  numeric(10,2)  -- DERIVED, see below
  meta        jsonb default '{}'
  created_at, updated_at
```

- **`kind`** ∈ `aid_station | cutoff | crew_access | hazard | note | climb |
  custom`. Enforced by a CHECK constraint, mirrored as the `RouteMarkerKind` TS
  union in `apps/web/src/lib/types.ts`, and registered in the `PAIRS` array of
  `apps/web/scripts/check_constraint_unions.mjs` so the `parity-types` CI job
  fails on drift. Dart treats it as a raw `String`.
- **`position_m`** (distance along the route from the start) is **derived
  server-side** by the `route_markers_set_position()` trigger via
  `ST_LineLocatePoint(routes.geom, point) * ST_Length(routes.geom)`. The client
  never computes it, so it can't drift from the geometry. A route with fewer
  than two valid waypoints (no `geom`) leaves it null; the schedule list then
  falls back to insertion order.

### `meta` keys

Per-kind extras live in the `meta` jsonb bag (no schema codegen — this list is
the registry):

| key | kinds | shape | meaning |
|---|---|---|---|
| `services` | `aid_station` | `string[]` of `water`/`food`/`medical`/`toilets`/`drop_bag` | what the aid station offers |
| `cutoff_clock` | `cutoff` | `"HH:MM"` (24h) | wall-clock cut-off time |
| `cutoff_elapsed_s` | `cutoff` | integer ≥ 0 | elapsed-from-start cut-off (alternative to the clock) |
| `note` | `note`, `hazard` | string | free-text note |

The pure helper `parseCutoff(meta)` validates / normalises the cutoff keys so a
cut-off chip renders identically on both platforms.

## Visibility + privacy

- **Base RLS** (defence in depth): SELECT is gated by
  `private.is_route_visible_to(route_id, auth.uid())` (owner / public / club
  member — the same helper `route_photos` / `route_reviews` / `segments` use).
  INSERT/UPDATE/DELETE require owning the parent route.
- **Canonical display read** is the `route_markers_for_viewer(p_route_id)`
  SECURITY DEFINER RPC. It gates visibility AND, for a **non-owner**, redacts any
  marker whose point falls inside one of the owner's privacy zones — the marker
  analogue of `clip_route_for_viewer` for waypoints (decisions §33). A public
  course therefore can't leak a pin dropped at the owner's home. The web + mobile
  read paths (`fetchRouteMarkers`) call this RPC and fail closed (empty list) on
  error.

## Surfaces

- **Web** — `RouteMarkerEditor.svelte` on `/routes/[id]`: an ordered course-
  schedule list (kind, distance, aid services / cut-off detail) plus an owner-
  only add/edit/delete flow. `RunMap.svelte` paints the pins and, for the owner,
  makes them **interactive**:
  - **Click to place** — with the add/edit form open the map shows a crosshair
    cursor; a click drops the pin (or moves the in-flight draft).
  - **Snap to the route line** — a "Snap to route line" toggle (default on, in
    the form) projects every placement + drag onto the nearest point of the
    course so a marker sticks to the line. The snap is render-only: `position_m`
    is still derived server-side from `routes.geom`. Pure projection in
    `routes/route_snap.ts` (`snapToPolyline`, 10 unit tests); the perpendicular
    foot on the closest segment, not the nearest vertex.
  - **Drag to move** — saved pins render as draggable DOM markers (a coloured
    dot + label, `grab`/`grabbing` cursor). Dragging one persists the new
    position immediately ("Marker moved." toast); the marker being edited
    renders instead as a single pulsing **draft** pin that the form tracks.
    Non-owner viewers keep the lightweight static circle layer.
- **Mobile** — `widgets/route_markers_panel.dart` on `route_detail_screen.dart`,
  same schedule list + owner editor sheet; `LiveRunMap` renders the pins +
  tap-to-place. `api_client` exposes the marker CRUD. Snap-to-line + drag-to-move
  are web-only so far (followups.md).
- **Shared helper** — `route_markers.ts` ↔ `route_markers.dart` (parity pair):
  the kind catalogue (shared pin colour + i18n label key + which `meta` fields a
  kind carries), `sortMarkers` (schedule order), `parseCutoff`, and the
  `AID_SERVICES` vocabulary. `route_snap.ts` is web-only (no Dart twin yet).

## Consumers

- **[Race roadbook](race_roadbook.md)** — the markers + a goal time produce a
  per-checkpoint crew sheet (projected arrival, cutoff margin, services). The
  markers' `position_m` + cutoff `meta` are the roadbook's spine.
- **[Course waypoint export](course_waypoint_export.md)** — the markers are
  what the GPX export emits: one `<wpt>` per marker (kind → `<sym>`, cutoff +
  services in `<desc>`) alongside the route line, so a watch surfaces them
  mid-race. Shipped on web (route-detail + roadbook download) + mobile share.

## Deferred

- **Club-defined custom marker kinds** — a `club_marker_kinds` catalogue a club
  can author so members place club-specific markers (`kind = 'custom'` +
  `club_marker_kind_id`). Specced, not built; gated on the core landing.
- Placing markers from the route **builder** (`/routes/new`) — markers attach to
  a saved line, so v1 only edits them on the detail page.
