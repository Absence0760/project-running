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

Each segment's grade is measured over an **anchored window** that accumulates
horizontal distance until it clears `MIN_SEGMENT_M` (5 m), the same walk
`gradeAdjustedPaceSecPerKm` performs — a short segment is carried forward, not
graded on its own and not discarded. Grading each point-pair in isolation made
effort allocation collapse onto even pace on any course sampled finer than 5 m,
silently, since `hasElevation` and `totalGainM` kept reporting the full climb
(decisions § 600). A trailing window that never clears the threshold is graded
flat. The allocation is therefore a property of the terrain, not of the GPX's
sampling interval.

The per-leg **target pace** — the pace that leg has to be run at to hold the
goal — is what the effort model actually produces, and it is a column on the
web crew sheet (and in the copied text) beside the arrival. The `even` model
prints the same pace on every leg; the effort model prints a slower one on the
climbs. Mobile shows cumulative arrival only; the mirror is in `followups.md`.

### Cutoff verdict

`parseCutoff(marker.meta)` (reused from `route_markers`) yields a limit:
`cutoff_elapsed_s` directly, or `cutoff_clock − startClock` (needs a start
clock). A bare clock carries no day, so it resolves to that wall clock's **first
occurrence after the start** and nothing else — `14:00` on an `08:00` start is
hour 6, and a clock equal to the start reads as the 24h limit it is meant to
express rather than a 0-second window. A limit past 24h has to be authored as
`cutoff_elapsed_s`, the only field that carries a day.

The limit used to snap to whichever whole day sat nearest that leg's projected
arrival, which made it a function of the goal time: a slower goal pushed the
projection over a day boundary and turned a blown cutoff into "safe, 12h to
spare", and two spectators of the same live run saw different limits for the
same checkpoint. A cutoff is a property of the race, so it may not depend on how
fast anyone is expected to run.

`marginS = limit − projectedElapsed`; `status` is
`miss` (negative), `tight` (within `CUTOFF_TIGHT_S` = 30 min), else `safe`.

**Every caller must pass `startClockMin`.** `cutoff_clock` is the only cut-off
field the web and mobile marker editors can author (`cutoff_elapsed_s` has no
input on either), so a caller that omits the start clock gets `cutoff: null` on
every leg — not a wrong verdict but *no cut-off at all*, and any surface gated
on "does this route have cut-offs" silently disappears. The callers and where
each gets its start: the web + mobile roadbook screens (user-picked start
time), the web `/live/[id]` page and the mobile spectator screen (the run's
`started_at`, read as local time of day), and the mobile run screen (the
recording's own wall-clock start, re-anchored when the run starts and when a
partial run resumes, since the legs are first built while staging). The
`goalSeconds` a live caller passes never reaches the card — the projection
comes from the runner's own pace — but it does choose which day a clock lands
on, per the snapping rule above.

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

## Marker target times (#608, 2026-07-22)

Any marker may carry a **target time** — `meta.target_elapsed_s` (+ optional
`target_clock`), parsed by the `route_markers` pair's `parseTarget`, the
cutoff vocabulary's shape. Both editors (web `RouteMarkerEditor`, mobile
markers panel) take h:mm:ss / mm:ss / bare-minutes input with matched
validation — a two-part value reads as mm:ss unless the marker's position
makes the h:mm reading the plausible pace (an 80 km aid station's "4:30"
is 4 h 30) — and both course-schedule lists show a "Target h:mm:ss" chip.
The roadbook page grows an owner-only **"Save as marker targets"** button
that writes each positioned marker's projected arrival into its meta —
the one-click seed, hand-tunable per marker afterwards. During a mobile
recording that follows the route, crossing a targeted marker speaks
ahead/behind-plan (run_recording.md, `voice_cue_types.marker_targets`).

## Deferred (follow-ups)

- **Saved named race plans** — a `race_plans` table (route + goal + start +
  owner) so a runner saves "Moab 240 — sub-100h" and crew load it by name,
  instead of passing a URL. The clean next phase now that the engine + UI exist.
- **Riegel-seeded default goal** — seed the default from the runner's best
  recent effort + a `predictionConfidence` badge (the `RaceDayPanel` pattern),
  instead of a flat default pace.
- **GPX/FIT waypoint export** — push the markers + roadbook to a Garmin/Coros
  (and the `custom_watch`) so they surface mid-race.
