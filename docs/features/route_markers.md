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
| `target_clock` | any | `"HH:MM"` (24h) | wall-clock target arrival (#608) |
| `target_elapsed_s` | any | integer ≥ 0 | elapsed-from-start target arrival (#608) |
| `note` | `note`, `hazard` | string | free-text note |

**Both concepts are authorable in either form.** Each editor shows ONE field per concept with a clock-vs-elapsed switch, opening in whichever form the marker was saved in, and writes only the selected one — the two are alternatives, and a marker holding both is contradictory (`_cutoffLimitS` silently prefers the elapsed value). Saving normalises a both-forms marker down to the one the readers already honoured, so nothing in use is lost. Before this, `cutoff_elapsed_s` and `target_clock` were in the registry with no input on either platform, so an ultra whose cut-offs are stated as "22 hours in" could not be described at all.

The pure helpers `parseCutoff(meta)` / `parseTarget(meta)` validate / normalise
those keys so a cut-off or target chip renders identically on both platforms.
They are also the **write** gate: an editor asks `parseCutoff` whether a typed
clock is acceptable rather than re-deriving the rule, because a value the
readers reject is silently invisible everywhere afterwards (schedule list,
roadbook, GPX export, live cut-off ETA).

## Visibility + privacy

- **Base RLS.** SELECT returns a marker on a route you can see IF it's your own
  OR it's the route owner's OFFICIAL marker (`private.route_owner_id` SECURITY
  DEFINER helper) — a viewer's personal overlay never leaks to others via a direct
  read. INSERT: any signed-in viewer may add a marker AS THEMSELVES to a route
  they can see (public / club / own — `private.is_route_visible_to`).
  UPDATE/DELETE are **own-markers-only**, so a viewer can't touch the owner's
  official markers and the owner can't touch a viewer's (migration
  `20270428_001`; was owner-only before).
- **Viewer contributions (personal overlay, decisions §296).** A marker is
  **official** when `user_id == route.user_id` (dropped by the owner) and
  **personal** otherwise (a viewer's own). Personal markers are private to their
  author — invisible to the owner and to other viewers. Web + mobile render
  official markers read-only + badged for non-owners; a viewer edits/deletes only
  their own (`isOfficialMarker`, `route_markers.ts ↔ .dart`).
- **Canonical display read** is the `route_markers_for_viewer(p_route_id)`
  SECURITY DEFINER RPC. It returns each caller's OWN markers plus the owner's
  OFFICIAL markers, redacting for a **non-owner** any official pin inside one of
  the owner's privacy zones — the marker analogue of `clip_route_for_viewer` for
  waypoints (decisions §33). A public course therefore can't leak a pin dropped at
  the owner's home. The web + mobile read paths (`fetchRouteMarkers`) call this RPC
  and fail closed (empty list) on error.
- **Placement by distance.** Besides map-tap and typed lat/lng, the editor accepts
  a "distance along route" (mi/km) that resolves to a point on the polyline via
  `markerPointAtDistance` (`route_geometry.ts ↔ .dart`); the server still derives
  `position_m`.

## Surfaces

- **Web** — `RouteMarkerEditor.svelte` on `/routes/[id]`: an ordered course-
  schedule list (kind, distance, aid services / cut-off detail) plus an owner-
  only add/edit/delete flow. `RunMap.svelte` paints the pins and, for the owner,
  makes them **interactive**:
  - **Click to place** — with the add/edit form open the map shows a crosshair
    cursor; a click drops the pin (or moves the in-flight draft).
  - **Type coordinates** — the form carries labelled Latitude / Longitude
    inputs (validated to ±90 / ±180) wired to the same draft position a map
    click fills, so a keyboard-only or screen-reader user can place or move a
    marker without the map (WCAG 2.1.1). A map click / draft-pin drag syncs
    the fields; typing a valid pair moves the draft pin live; save re-parses
    the fields and rejects out-of-range values with an inline `role="alert"`
    error.
  - **Snap to the route line** — a "Snap to route line" toggle (default on, in
    the form) projects every placement + drag onto the nearest point of the
    course so a marker sticks to the line. The snap is render-only: `position_m`
    is still derived server-side from `routes.geom`. Pure projection in
    `routes/route_snap.ts` (`snapToPolyline`, 12 unit tests) with a byte-identical
    Dart twin `route_snap.dart` (12 mirror tests each); the perpendicular
    foot on the closest segment, not the nearest vertex. The projection frame
    takes its longitude deltas through `routes/geo.ts` so a course near 180 deg
    snaps onto itself rather than ~40,000 km away (decisions §468).
  - **Drag to move** — saved pins render as draggable DOM markers (a coloured
    dot + label, `grab`/`grabbing` cursor). Dragging one persists the new
    position immediately ("Marker moved." toast); the marker being edited
    renders instead as a single pulsing **draft** pin that the form tracks.
    Non-owner viewers keep the lightweight static circle layer.
- **Mobile** — `widgets/route_markers_panel.dart` on `route_detail_screen.dart`,
  same schedule list + owner editor sheet; `LiveRunMap` renders the pins +
  tap-to-place. `api_client` exposes the marker CRUD. **Snap-on-tap-placement
  now ships**: a "Snap to route line" toggle (default on, shown while placing —
  mirrors web's `snapEnabled = true`) projects the tapped point through
  `route_snap.dart` (`snapToPolyline`, parity pair) onto the nearest point of
  the course before the marker is placed; render-only, `position_m` stays
  server-derived. **Coordinate entry ships too**: the editor sheet carries
  Latitude / Longitude fields (prefilled from the tap or the existing marker,
  validated to ±90 / ±180; an edit persists the typed position), and placing
  mode offers an "Enter location instead" button that opens the sheet
  without a map tap — the keyboard / screen-reader placement path matching
  web (widget tests in `route_markers_panel_test.dart`). Placing mode also
  **scrolls the map back into view** (the panel sits below the fold, so the
  "tap the map" instruction otherwise arrived with no map on screen) and
  carries a **Cancel** — the Add button hides while placing, so without one a
  placement was a one-way trip. A tap on an existing pin while placing places
  there rather than opening that marker, so a pin is never a dead zone for the
  placement tap. Both time fields take digits on a numeric keypad and
  auto-insert their separators (`TextInputFormatter`); the cut-off is
  **validated through `parseCutoff` before save** and the target time's
  two-part h:mm-vs-mm:ss reading uses the distance-along the sheet just placed
  at, not only a server-derived `position_m` the new marker doesn't have yet.
  The
  **draggable-symbol drag-to-move** affordance on `LiveRunMap` still needs
  on-device maplibre `SymbolManager` work and stays a followup (followups.md).
- **Shared helper** — `route_markers.ts` ↔ `route_markers.dart` (parity pair):
  the kind catalogue (shared pin colour + i18n label key + which `meta` fields a
  kind carries), `sortMarkers` (schedule order), `parseCutoff`, and the
  `AID_SERVICES` vocabulary. `route_snap.ts` ↔ `route_snap.dart` (parity pair):
  `snapToPolyline` projects a point onto the nearest on-line foot + its
  along-route distance preview, 12 mirror tests each.

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
