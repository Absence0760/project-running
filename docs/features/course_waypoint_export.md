# Course waypoint export — markers onto the watch (GPX, then FIT)

> **STATUS: handoff spec, not built.** Self-contained brief for an implementing
> session. Read [CLAUDE.md](../../CLAUDE.md) for conventions. Web is canonical;
> mobile mirrors; iOS twin byte-identical.

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

1. `route_gpx.ts/.dart` waypoint emitter + unit/mirror tests.
2. Web download actions (route detail + roadbook) + i18n + Playwright.
3. Mobile share action (+ iOS twin) + Flutter test.
4. Docs.
5. (Later) FIT Course export.

## Tests

- Unit: the GPX contains one `<wpt>` per marker with correct coords/name/type;
  cutoff time + services land in `<desc>`; output is well-formed XML; a route
  with no markers still exports the line.
- Playwright: the download action produces a file containing the waypoints.
- Flutter: the share action builds the same GPX.

## Open decisions for the implementer (ask the user if unsure)

- GPX-only v1 vs also shipping FIT Course now (recommend GPX first — universal).
- `kind` → GPX `<sym>` / FIT `CoursePoint` type mapping.
- Whether to export the full line + waypoints, or waypoints-only.

## Docs

Extend [integrations.md](integrations.md) (export formats), add a parity row in
[parity.md](../product/parity.md), and link from [route_markers.md](route_markers.md).
