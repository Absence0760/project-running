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
//! - [`grade_adjusted_pace`] — the Minetti GAP model (fourth parity port) +
//!   the streaming grade estimator the recorder feeds
//! - [`hr_zones`] — the app's five-zone %-of-max HR ladder (mirrors web
//!   `training/hr_zones.ts`) + the zone-for-BPM lookup
//! - [`face`] — watch-face layout: state in, text rows out
//! - [`page`] — which run-view screen shows + the page-button cycle order
//! - [`link`] — phone-link status frames (sim transport today, BLE GATT
//!   characteristic payload at step 6)
//! - [`pacer`] — even-pace target-time virtual partner (ahead/behind vs a
//!   goal distance + time) the recorder folds into its snapshot
//! - [`race_predictor`] — the 5K/10K/Half/Marathon race-time ladder (parity
//!   port of web `training/race_predictor.ts` + the reused Riegel +
//!   prediction-confidence helpers), recency-weighted anchor, per-rung
//!   confidence
//! - [`record`] — recording state machine: commands + fixes in, run totals out
//! - [`trackback`] — back-to-start: breadcrumb buffer, distance/bearing to
//!   the start, the course-over-ground heading + relative direction arrow
//! - [`button`] — the pure button-press → record-command mapping
//! - [`run_store`] — on-device run wire format + BLE sync framing
//! - [`flash_store`] — tier-1 internal-flash slot layout for finished runs
//! - [`training_load`] — single-run + rolling CTL/ATL/TSB training-load
//!   estimate (port of web `training/training_load.ts`)

#![cfg_attr(not(test), no_std)]

pub mod alerts;
pub mod button;
pub mod course;
pub mod cutoff_eta;
pub mod distance_bands;
pub mod elevation;
pub mod face;
pub mod fix;
pub mod flash_store;
pub mod fuel_plan;
pub mod gear_wear;
pub mod gnss_mode;
pub mod grade_adjusted_pace;
pub mod hr_zones;
pub mod link;
pub mod pace_segments;
pub mod pacer;
pub mod page;
pub mod race_predictor;
pub mod record;
pub mod roadbook;
pub mod run_store;
pub mod trackback;
pub mod training_load;
