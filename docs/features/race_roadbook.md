# Race roadbook

The **crew sheet** a route's [course markers](route_markers.md) + a goal finish
time imply. Given a route, its markers (aid stations / cutoffs / crew access),
and a goal time, the roadbook produces the per-checkpoint schedule ultra crews
currently build by hand in spreadsheets — cumulative distance, **projected
arrival** (elapsed + wall clock), **cutoff margin** (green/amber/red), per-leg
vert, and aid services. Strava/Garmin don't do this; it's the payoff of the
markers layer and leans into the app's ultra/trail focus.

Web is canonical (`/routes/[id]/roadbook`); mobile mirrors it
(`RoadbookScreen`); iOS stays byte-identical to Android.

## The engine

Pure parity helper `apps/web/src/lib/routes/roadbook.ts` ↔
`apps/mobile_android/lib/roadbook.dart`. `buildRoadbook(waypoints, markers,
{goalSeconds, startClockMin?, model})` returns ordered **legs** (synthetic
start → each marker by distance → synthetic finish), each with:

- `cumDistM`, `legDistM`, `legGainM`, `legLossM`
- `projectedElapsedS` + optional `projectedClockMin` (when a start clock is set,
  wrapping past midnight)
- `cutoff` (`{limitElapsedS, marginS, status}`) on cutoff markers
- `services`

### Effort vs even allocation (the differentiator)

Goal time is allocated across legs by **grade-adjusted effort** by default, not
even pace: each segment's metric is `horizontalDistance × gradeFactor(grade)`
(`gradeFactor` = the Minetti cost multiplier from
`runs/grade_adjusted_pace.ts`), so a climb leg gets proportionally more of the
time budget than a flat one — "slow the climbs, bank the descents." The `even`
model allocates by raw distance. With no elevation data the effort model
**degrades cleanly to even** (`hasElevation = false`), and the web/mobile UI
offers a one-tap **Add elevation** that backfills per-waypoint vert from
Open-Meteo (`routes/elevation.ts`) so effort can fire on any route.

### Cutoff verdict

`parseCutoff(marker.meta)` (reused from `route_markers`) yields a limit:
`cutoff_elapsed_s` directly, or `cutoff_clock − startClock` (needs a start
clock; wraps next-day). `marginS = limit − projectedElapsed`; `status` is
`miss` (negative), `tight` (within `CUTOFF_TIGHT_S` = 30 min), else `safe`.

## Sharing — URL params, no schema

The web page encodes the **goal time, start time, and pacing model in the URL
query params** (`?goal=<seconds>&start=HH:MM&model=effort|even`), so a runner
sends crew the link and they see the identical sheet. There is **no
persistence** in v1 — no `race_plans` table. The page is print-friendly
(`@media print` + a Print button) and offers Copy-as-text (a pasteable table)
for a crew chat. The default goal seeds from route distance at a moderate trail
pace, editable.

Mobile has no URL to encode, so its controls are screen-local; share is a
share-sheet text dump.

## Entry point

A "Roadbook (crew sheet)" link on `/routes/[id]` (web) and a button on
`route_detail_screen` (mobile), shown only when the route has markers.

## Fueling

The roadbook also carries a **fueling layer** — see
[race_fueling_plan.md](race_fueling_plan.md). A "Fueling" toggle adds per-leg
**carbs** + **fluid** columns plus a "carry to next aid" hint, and a "Heat"
toggle bumps fluid only. The `fuel_plan.ts ↔ .dart` engine scales each figure
with the leg's duration off the roadbook timeline; rates come from the universal
prefs `carbs_per_hour` (60 g/hr default) + `fluid_per_hour` (500 ml/hr). Web
encodes the fueling toggle in the URL like the pacing controls; mobile keeps it
screen-local. In-run reminders are a deferred separate phase.

## Deferred (follow-ups)

- **Saved named race plans** — a `race_plans` table (route + goal + start +
  owner) so a runner saves "Moab 240 — sub-100h" and crew load it by name,
  instead of passing a URL. The clean next phase now that the engine + UI exist.
- **Riegel-seeded default goal** — seed the default from the runner's best
  recent effort + a `predictionConfidence` badge (the `RaceDayPanel` pattern),
  instead of a flat default pace.
- **GPX/FIT waypoint export** — push the markers + roadbook to a Garmin/Coros
  (and the `custom_watch`) so they surface mid-race.
