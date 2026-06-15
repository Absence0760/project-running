# Course waypoint export — markers onto the watch (GPX, then FIT)

> **STATUS: GPX-with-waypoints (v1) SHIPPED; FIT Course (v2) DEFERRED.**
> The GPX export — the route line plus one `<wpt>` per course marker — ships on
> web (route-detail + roadbook download) and mobile (route-detail share, iOS
> twin). The FIT Course file (§ v2 below) remains a follow-up; nothing in this
> doc claims it's built. Read [CLAUDE.md](../../CLAUDE.md) for conventions. Web
> is canonical; mobile mirrors; iOS twin byte-identical.
>
> **Shipped surfaces / names:**
> - Pure emitter: `apps/web/src/lib/routes/route_gpx.ts`
>   (`toRouteGpxWithMarkers(name, coordinates[lng,lat], elevations, markers)`)
>   ↔ `apps/mobile_android/lib/route_gpx.dart` (`routeGpxFromRoute`), iOS twin —
>   a TS↔Dart parity pair, 10 mirror tests each.
> - Web download: `routeDetail.exportGpxMarkers` ("GPX + markers") action on
>   `/routes/[id]` + `/routes/[id]/roadbook`, shown only when the route has ≥1
>   marker; exports the privacy-clipped `displayWaypoints`. Playwright in
>   `tests-e2e/routes/roadbook.spec.ts`.
> - Mobile share: `routeDetailShareAsGpxMarkers` ("Share as GPX + markers")
>   PopupMenu action on `route_detail_screen.dart`, 3 Flutter tests.

## Context / why

Markers + the roadbook live in the app, but the runner is on a **watch** mid-
race with no phone. Export a route's aid stations + cutoffs as GPX/FIT
**waypoints** so a Garmin/Coros (and eventually the `custom_watch`) surfaces
"Aid 2 in 1.3 km" on the wrist. This is the bridge that makes the whole course-
planning layer (markers + roadbook) matter when it counts.

## Reuse (don't re-implement)

- **Existing route export:** the route-detail page already builds GPX/KML for
  the line — `toGpx(name, coords, eles)` / `toKml(...)` (web; see
  `/routes/[id]/+page.svelte` download actions). Mobile has `fit_export.dart`
  (runs) + the `gpx_parser` package.
- **Markers:** `fetchRouteMarkers` (RPC). Each marker carries lat/lng +
  `position_m` + `meta` (cutoff time, aid services) + `kind`.

## Design

1. **GPX-with-waypoints (v1 — universal).** A pure `route_gpx.ts ↔ .dart`
   (or extend `toGpx`): emit the route line as `<trk>`/`<rte>` **plus** one
   `<wpt lat lon><name>Aid 2</name><type>aid_station</type><desc>…</desc></wpt>`
   per marker. Put the cutoff time / aid services in `<desc>`; map `kind` →
   a GPX `<sym>` where a sensible symbol exists. GPX is imported by every
   Garmin/Coros/Suunto device, so this is the high-value first cut.
2. **Surfaces:** a "Download GPX (with markers)" action on `/routes/[id]` +
   the roadbook page (web); share the `.gpx` via the share sheet on
   `route_detail_screen` (mobile).
3. **FIT Course (v2 — watch-native, stretch).** A FIT *Course* file with
   `CoursePoint` records (Garmin's native aid-station/water/danger types) gives
   the true on-watch experience (turn-by-turn + course points). Format-heavy;
   spec as a follow-up. Mobile's `fit_export.dart` is the starting point.

No new schema.

## Commit cadence

1. ✅ `route_gpx.ts/.dart` waypoint emitter + unit/mirror tests.
2. ✅ Web download actions (route detail + roadbook) + i18n + Playwright.
3. ✅ Mobile share action (+ iOS twin) + Flutter test.
4. ✅ Docs.
5. (Deferred) FIT Course export — v2 below.

## Tests

- Unit: the GPX contains one `<wpt>` per marker with correct coords/name/type;
  cutoff time + services land in `<desc>`; output is well-formed XML; a route
  with no markers still exports the line.
- Playwright: the download action produces a file containing the waypoints.
- Flutter: the share action builds the same GPX.

## Open decisions — resolved (v1)

- **GPX-only v1; FIT Course deferred to v2.** Shipped the universal GPX path
  first; the FIT Course file is the remaining follow-up below.
- **`kind` → GPX `<sym>` mapping (shipped):** `aid_station` → `Water Source`,
  `cutoff` → `Danger Area`, `hazard` → `Danger Area`, `crew_access` →
  `Parking Area`, `note` → `Information`, `climb` → `Summit`; `custom` → no
  `<sym>`. Source of truth is `SYM_BY_KIND` in `route_gpx.ts` (mirrored in the
  Dart twin).
- **Export the full route line + waypoints**, not waypoints-only — the `<trk>`
  carries the line, one `<wpt>` per marker (waypoints emitted first per the
  GPX 1.1 schema). The cutoff time + aid services land in each `<wpt>`'s
  `<desc>` (`buildDesc`).
- **Waypoints are privacy-clipped.** Web exports the privacy-clipped
  `displayWaypoints` (markers inside a privacy zone are redacted by the
  `route_markers_for_viewer` path); mobile exports against the clipped route.

## Docs

Extend [integrations.md](integrations.md) (export formats), add a parity row in
[parity.md](../product/parity.md), and link from [route_markers.md](route_markers.md).
