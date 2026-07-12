//! Hardware-free application core for the watch firmware.
//!
//! Everything in this crate is pure logic over plain data: no peripherals,
//! no Embassy, no allocator. The `app/` crate's async tasks are thin glue
//! that move bytes between peripherals and these modules, which keeps the
//! 60-70% host-testable split that `local_testing.md` calls for and means
//! the same core ports unchanged to tier-2 silicon (decisions.md § 90).
//!
//! - [`alerts`] — on-run alerts: drink / eat reminders on the `fuel_plan`
//!   moving-time cadence + the HR-zone ceiling alert
//! - [`auto_segment_effort`] — pick the route a route-less run followed +
//!   batch its segment-effort rows (port of web
//!   `segments/auto_segment_effort.ts`; reuses [`segments`])
//! - [`fix`] — the GPS fix domain model + the RMC/GGA accumulator
//! - [`course`] — breadcrumb course polyline, nearest-point projection,
//!   off-course alert latch, and the panel-fit pixel mapping (fifth parity
//!   port: web `route_snap.ts` / `route_geometry.ts` + the mobile
//!   route-overlay thresholds)
//! - [`cutoff_eta`] — live next-cutoff ETA: on / tight / behind at the nearest
//!   cutoff ahead from distance-along-route + recent pace, honest `Unknown` on
//!   a stale fix (port of web `runs/live_cutoff_eta.ts`)
//! - [`roadbook`] — per-checkpoint race-crew schedule: cumulative distance,
//!   effort-allocated projected arrival, per-leg vert, safe/tight/miss cutoff
//!   verdict (port of web `routes/roadbook.ts`)
//! - [`fuel_plan`] — per-leg carbs/fluid scaled onto the roadbook timeline +
//!   carry-to-next-aid per refill (port of web `routes/fuel_plan.ts`)
//! - [`pace_segments`] — split a track into pace segments with the shared
//!   pace/age colour ramp (port of web `segments/pace_segments.ts`)
//! - [`distance_bands`] — classify a distance into its race-distance band
//!   (port of web `routes/distance_bands.ts`)
//! - [`gear_wear`] — gear/shoe wear state from accumulated mileage
//!   (port of web `gear/gear_wear.ts`)
//! - [`elevation`] — barometric altitude + the cumulative-vert accumulator
//! - [`gnss_mode`] — the selectable GNSS recording modes (fix interval +
//!   projected battery hours) BTN3 cycles on the idle face
//! - [`goals`] — multi-metric run goals: distance / time / pace / run-count
//!   targets over a week or month window (port of web `training/goals.ts`; the
//!   localStorage persistence + UUID id + i18n period label are web-only, dates
//!   collapsed to a day index like [`current_week`])
//! - [`grade_adjusted_pace`] — the Minetti GAP model (fourth parity port) +
//!   the streaming grade estimator the recorder feeds
//! - [`guided_runs`] — scripted coach-voice guided-run library + the
//!   `(prev, now]` tick dispatcher that fires each timed cue (port of web
//!   `training/guided_runs.ts`; cue/title text carried as i18n key identifiers,
//!   the TTS speaking + `GuidedTranslate` injection are web/mobile-only)
//! - [`hr_zones`] — the app's five-zone %-of-max HR ladder (mirrors web
//!   `training/hr_zones.ts`) + the zone-for-BPM lookup
//! - [`face`] — watch-face layout: state in, text rows out
//! - [`page`] — which run-view screen shows + the page-button cycle order
//! - [`statusbar`] — the idle-face GPS signal-strength bars + the run-view
//!   page-position dot indicator (pure 0..=4 / active-of-total counts; the
//!   face draws the pixels)
//! - [`gauge`] — reduce pacer / gear / fuel / HR-zone metrics to normalised
//!   bar-fill fractions the face draws as visual gauges
//! - [`bar_chart`] — scale a distribution (zone times, pace buckets) into
//!   bottom-aligned bar rectangles for a mini chart
//! - [`link`] — phone-link status frames (sim transport today, BLE GATT
//!   characteristic payload at step 6)
//! - [`pacer`] — even-pace target-time virtual partner (ahead/behind vs a
//!   goal distance + time) the recorder folds into its snapshot
//! - [`race_day`] — race-day pacing: days-until, even / negative-split per-unit
//!   splits, the distance-aware pre-race checklist (items as enum ids), goal
//!   feasibility vs a prediction, and the split-time formatter (port of web
//!   `runs/race_day.ts`)
//! - [`race_predictor`] — the 5K/10K/Half/Marathon race-time ladder (parity
//!   port of web `training/race_predictor.ts` + the reused Riegel +
//!   prediction-confidence helpers), recency-weighted anchor, per-rung
//!   confidence
//! - [`readiness`] — readiness-to-run score from form / sleep / resting-HR drift
//!   around a 75 baseline + the dominant-contributor advice (port of web
//!   `training/readiness.ts`; notes/advice carried as enums, not English)
//! - [`record`] — recording state machine: commands + fixes in, run totals out
//! - [`trackback`] — back-to-start: breadcrumb buffer, distance/bearing to
//!   the start, the course-over-ground heading + relative direction arrow
//! - [`button`] — the pure button-press → record-command mapping
//! - [`run_store`] — on-device run wire format + BLE sync framing
//! - [`settings`] — phone→watch settings frame (max HR / pacer goal / gear /
//!   HR-zone ceiling) decoded into the recorder's settings-sync hooks
//! - [`flash_store`] — tier-1 internal-flash slot layout for finished runs
//! - [`training_load`] — single-run + rolling CTL/ATL/TSB training-load
//!   estimate (port of web `training/training_load.ts`)
//! - [`age_grade`] — age-graded performance % for a standard-distance effort
//!   against the USATF-MLDR 2025 factor tables (port of web `runs/age_grade.ts`
//!   + the generated `age_grade_tables.ts`)
//! - [`hydration`] — daily water target + budget from bodyweight + exercise
//!   minutes (port of web `nutrition/hydration.ts`)
//! - [`exercise_calories`] — gross run/gym kcal for the dynamic-TDEE nutrition
//!   goal (port of web `nutrition/exercise_calories.ts`)
//! - [`training_paces`] — the five Daniels intensity-zone paces from a goal
//!   pace, with female + masters calibration (port of the pace-zone surface of
//!   web `training/training.ts`; reuses [`race_predictor::riegel_predict`])
//! - [`fitness`] — VDOT / VO2max / per-run TSS / recovery advice + the
//!   Fitness-card training-load snapshot (port of web `training/fitness.ts`;
//!   the ISO date + `nowMs` collapse to an integer day index like
//!   [`training_load`])
//! - [`route_markers`] — course-marker kind catalogue + `sort_markers` +
//!   `parse_cutoff` + the aid-services vocabulary (port of web
//!   `routes/route_markers.ts`; `parse_cutoff` mirrors the copy inlined in
//!   [`roadbook`]/[`cutoff_eta`], a later de-dup target)
//! - [`checkpoint_projection`] — grade a runner from aid-station crossings:
//!   projected arrival at each remaining checkpoint + safe/tight/miss verdict
//!   (port of web `runs/checkpoint_projection.ts`; reuses
//!   [`roadbook::CutoffStatus`] + [`cutoff_eta::CUTOFF_TIGHT_S`])
//! - [`route_description`] — bucket a route's stats into structured parts + the
//!   canonical English assembler, the offline "describe this route" baseline
//!   (port of web `routes/route_description.ts`; reuses
//!   [`distance_bands::band_for_distance`])
//! - [`route_elevation`] — positive-delta elevation gain + evenly-spaced
//!   coordinate sampling (the pure half of web `routes/elevation.ts`, renamed to
//!   avoid the [`elevation`] barometric-accumulator collision; `fetchElevations`
//!   is a browser network hop and stays web-only)
//! - [`route_geometry`] — interpolate a fraction to a distance-weighted point on
//!   a route polyline + the inverse distance-along-route projection + cumulative
//!   length (port of web `routes/route_geometry.ts`; the self-contained twin of
//!   the [`course`] nav-overlay projection)
//! - [`route_gpx`] — course-waypoint GPX export: the route line as a `<trk>`
//!   plus one `<wpt>` per course marker, kind→`<sym>` + cutoff/services in
//!   `<desc>` (port of web `routes/route_gpx.ts`; reuses
//!   [`route_markers::parse_cutoff`], builds into a `heapless::String`)
//! - [`route_simplify`] — Ramer-Douglas-Peucker track simplification + the
//!   route summary (simplified waypoints + equirectangular distance +
//!   elevation gain) (port of web `routes/route_simplify.ts`; iterative RDP
//!   over a fixed-capacity stack, no recursion)
//! - [`plan_progress`] — base→build→peak→taper phase ordering + longest
//!   completed long run (port of web `training/plan_progress.ts`)
//! - [`plan_adherence`] — weekly drift over/under + missed-workout make-up/skip
//!   advice as enums (port of web `training/plan_adherence.ts`)
//! - [`plan_replan`] — propose future-only make-up / ease-off changes around
//!   missed sessions (port of web `training/plan_replan.ts`; reuses
//!   [`plan_adherence::weekly_drift`] + [`plan_adherence::missed_workout_advice`])
//! - [`plan_adaptive_replan`] — gate a re-plan on a multi-week adherence trend
//!   (2-of-3 trailing completed weeks flagged), then delegate the deltas to
//!   [`plan_replan::replan_remaining`] (port of web
//!   `training/plan_adaptive_replan.ts`; reuses [`plan_adherence::weekly_drift`])
//! - [`current_week`] — bucket activities onto the seven days of the real
//!   calendar week honouring the week-start pref (port of web
//!   `training/current_week.ts`; ISO dates collapsed to a Unix-epoch day index)
//! - [`nutrition_targets`] — Mifflin-St Jeor BMR → calorie + macro targets from
//!   goal (port of web `nutrition/nutrition_targets.ts`)
//! - [`challenge_progress`] — challenge progress fraction / rank / on-pace
//!   projection (port of web `social/challenge_progress.ts`; reuses
//!   [`pacer::ON_PACE_BAND`])
//! - [`badges`] — achievement catalogue + `evaluate_badges` + `tier_for`,
//!   thresholds in lockstep with the SQL awarder (port of web
//!   `social/badges.ts`; i18n label keys carried as identifiers, not strings)
//! - [`locale_defaults`] — locale → default unit + week-start region tables
//!   (port of web `format/locale_defaults.ts`; the `Intl` fallback is web-only)
//! - [`privacy`] — privacy-zone track clipping: trim leading/trailing points
//!   inside a home/work zone (port of web `routes/privacy.ts`
//!   `clipPointsToZones`)
//! - [`segments`] — segment effort from a track + competition-rank (1224) +
//!   the age-band vocabulary + crown-label enum (port of web
//!   `segments/segments.ts`)
//! - [`track_projection`] — project a lat/lng track into panel x/y for a
//!   preview thumbnail (port of web `routes/track_projection.ts`; the Dart twin
//!   `projectTrack` lives inside `track_preview.dart`)
//! - [`run_heatmap`] — grid-quantise many tracks into clamped weighted cells +
//!   the fit box (port of web `routes/run_heatmap.ts`; the MapLibre GeoJSON
//!   emitters are web-only)
//! - [`run_stats`] — on-demand run stats from a GPS track: moving time,
//!   positive elevation gain, per-unit splits (port of web `runs/run_stats.ts`;
//!   reuses [`grade_adjusted_pace::haversine_metres`], epoch-ms timestamps)
//! - [`relink_candidates`] — the runs eligible to re-link to a planned workout
//!   (±7-day window, excluding already-linked) (port of web
//!   `training/relink_candidates.ts`; dates collapsed to a day index)
//! - [`live_freshness`] — spectator staleness: age clamp + stale flag + display
//!   bucket, so a lost-signal runner reads stale (port of web
//!   `runs/live_freshness.ts`)
//! - [`finisher_certificate`] — certificate eligibility + the time / distance /
//!   ordinal-place formatters (port of the shaping half of web
//!   `runs/finisher_certificate.ts`; the SVG/PNG builder is web-only)
//! - [`recap`] — Year / Month-in-Running aggregator: totals, run-family
//!   longest/fastest, top week, streaks, monthly strip + the earned trophy grid
//!   (port of web `runs/recap.ts`; reuses [`current_week::dow_of`] +
//!   [`locale_defaults::DistanceUnit`], ISO timestamps collapsed to day indices)
//! - [`streaks`] — current + best run-streak counts with the Strava grace rule
//!   (port of web `runs/streaks.ts`; ISO local-day keys collapsed to a day
//!   index, so the day-step arithmetic is DST-safe by construction)
//! - [`pr_recency`] — the relative age of a PR date as a language-free bucket
//!   enum, softening an old best for a returning runner (port of web
//!   `runs/pr_recency.ts`; ISO dates collapsed to a day index)
//! - [`turn_cues`] — offline turn-by-turn cues from a route polyline's bearing
//!   deltas at each interior vertex (port of web `routes/turn_cues.ts`)

#![cfg_attr(not(test), no_std)]

pub mod age_grade;
pub mod alerts;
pub mod auto_segment_effort;
pub mod badges;
pub mod bar_chart;
pub mod button;
pub mod challenge_progress;
pub mod checkpoint_projection;
pub mod course;
pub mod course_store;
pub mod current_week;
pub mod cutoff_eta;
pub mod distance_bands;
pub mod elevation;
pub mod exercise_calories;
pub mod face;
pub mod finisher_certificate;
pub mod fitness;
pub mod fix;
pub mod flash_store;
pub mod fuel_plan;
pub mod gauge;
pub mod gear_wear;
pub mod gnss_mode;
pub mod goals;
pub mod grade_adjusted_pace;
pub mod guided_runs;
pub mod hr_zones;
pub mod hydration;
pub mod link;
pub mod live_freshness;
pub mod locale_defaults;
pub mod nutrition_targets;
pub mod pace_segments;
pub mod pacer;
pub mod page;
pub mod plan_adaptive_replan;
pub mod plan_adherence;
pub mod plan_progress;
pub mod plan_replan;
pub mod pr_recency;
pub mod privacy;
pub mod race_day;
pub mod race_predictor;
pub mod readiness;
pub mod recap;
pub mod record;
pub mod relink_candidates;
pub mod roadbook;
pub mod route_description;
pub mod route_elevation;
pub mod route_geometry;
pub mod route_gpx;
pub mod route_markers;
pub mod route_simplify;
pub mod run_heatmap;
pub mod run_stats;
pub mod run_store;
pub mod segments;
pub mod settings;
pub mod statusbar;
pub mod streaks;
pub mod track_projection;
pub mod trackback;
pub mod training_load;
pub mod training_paces;
pub mod turn_cues;
