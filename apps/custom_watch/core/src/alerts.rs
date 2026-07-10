//! On-run alerts — drink / eat reminders on a moving-time cadence plus an
//! HR-zone ceiling alert (README step 7; the roadmap's "on-run alerts" T1
//! slice — pace / distance / time alerts are T2).
//!
//! The fuel cadences are not invented here: they reduce the main app's race
//! fueling defaults (web `routes/fuel_plan.ts`, canonical, with its Dart twin)
//! to fixed moving-time intervals, per §24 — firmware mirrors the product's
//! numbers rather than pioneering new ones:
//!
//! - `fuel_plan` targets `DEFAULT_CARBS_PER_HOUR_G = 60` at `GEL_CARBS_G = 25`
//!   per gel — one gel every 25 minutes — so the eat reminder fires every
//!   **1500 s** of moving time.
//! - `fuel_plan` targets `DEFAULT_FLUID_PER_HOUR_ML = 500`; at the ~125 ml a
//!   soft-flask sip delivers that is four sips an hour, so the drink reminder
//!   fires every **900 s** of moving time.
//!
//! Intervals bank where the recorder's moving time banks: the engine compares
//! against [`Snapshot::moving_s`], so a manual pause, an auto-pause, and a
//! slow (sub-moving-gate) stretch accrue nothing — exactly like the HR-zone
//! accumulators. An aid-station stop doesn't tick the reminder clock.
//!
//! The HR-zone alert fires when the live zone rises **above** a configured
//! ceiling zone ([`set_zone_ceiling`](AlertEngine::set_zone_ceiling) — off by
//! default, a hook for a future settings sync like `Recorder::set_max_hr`).
//! It fires once per excursion: crossing above the ceiling raises it, and it
//! re-arms only when the zone drops back to the ceiling or below, with a
//! [`ZONE_ALERT_COOLDOWN_S`] gate so a BPM flapping across the boundary can't
//! re-fire every second.
//!
//! At most one alert is on screen at a time, for [`ALERT_TTL_S`] seconds. The
//! zone alert outranks the fuel reminders — over-effort is actionable *now*,
//! a reminder can wait eight seconds — and supersedes an active one, which
//! re-queues (fuel is the ultra-critical reminder; it must never be silently
//! dropped). Queued reminders promote eat-before-drink when a slot frees.
//!
//! Display-only by design: the DK has no vibration motor, and alerts are an
//! L4 auxiliary — the engine is pure and fed *after* the recorder updates, so
//! nothing here can disturb the recording math.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator.

use core::fmt::Write;

use crate::hr_zones;
use crate::record::{RecordState, Snapshot};

/// Drink reminder cadence, seconds of moving time: `fuel_plan`'s 500 ml/hr
/// split into four ~125 ml sips.
pub const DRINK_INTERVAL_MOVING_S: u32 = 900;

/// Eat reminder cadence, seconds of moving time: `fuel_plan`'s 60 g/hr at
/// 25 g per gel — one gel per 25 minutes.
pub const EAT_INTERVAL_MOVING_S: u32 = 1500;

/// How long a raised alert stays on screen.
pub const ALERT_TTL_S: u32 = 8;

/// Minimum seconds between two zone-alert fires, so a BPM flapping across the
/// ceiling boundary (re-arming on each dip) can't re-fire every second.
pub const ZONE_ALERT_COOLDOWN_S: u32 = 60;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Alert {
    /// Take a sip — [`DRINK_INTERVAL_MOVING_S`] of moving time banked.
    Drink,
    /// Take a gel — [`EAT_INTERVAL_MOVING_S`] of moving time banked.
    Eat,
    /// The live HR zone (carried for display) rose above the ceiling.
    ZoneAbove(u8),
}

/// The banner the face draws at 2x over the hero band while an alert is
/// active — `!` plus an all-caps label, the visually-distinct treatment a
/// 1-bit panel with no inverse text can give.
pub type Banner = heapless::String<10>;

pub fn banner(alert: Alert) -> Banner {
    let mut b = Banner::new();
    let _ = match alert {
        Alert::Drink => write!(b, "! DRINK"),
        Alert::Eat => write!(b, "! EAT"),
        Alert::ZoneAbove(zone) => write!(b, "! ZONE {}", zone.min(9)),
    };
    b
}

pub struct AlertEngine {
    drink_interval_s: u32,
    eat_interval_s: u32,
    /// Moving-time thresholds the next reminders fire at. Re-based to
    /// `moving_s + interval` on each fire (rather than `+= interval`) so a
    /// long-suppressed reminder never releases as a catch-up burst.
    next_drink_at_moving_s: u32,
    next_eat_at_moving_s: u32,
    /// Alert when the live zone exceeds this (1..=4). `None` = off, the
    /// hardware default until a settings sync sets it.
    zone_ceiling: Option<u8>,
    /// Set while the zone is at or below the ceiling; a fire disarms until
    /// the zone drops back — the once-per-excursion hysteresis.
    zone_armed: bool,
    last_zone_fire_s: Option<u32>,
    /// The on-screen alert and the uptime it was raised at.
    active: Option<(Alert, u32)>,
    pending_drink: bool,
    pending_eat: bool,
    in_run: bool,
}

impl Default for AlertEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl AlertEngine {
    pub const fn new() -> Self {
        Self {
            drink_interval_s: DRINK_INTERVAL_MOVING_S,
            eat_interval_s: EAT_INTERVAL_MOVING_S,
            next_drink_at_moving_s: DRINK_INTERVAL_MOVING_S,
            next_eat_at_moving_s: EAT_INTERVAL_MOVING_S,
            zone_ceiling: None,
            zone_armed: true,
            last_zone_fire_s: None,
            active: None,
            pending_drink: false,
            pending_eat: false,
            in_run: false,
        }
    }

    /// Configure the fuel cadences — the sim shortens them so a reminder fires
    /// within a bench run, and a future settings sync sets a runner's own
    /// plan. A zero interval is nonsense and ignored (that arm keeps its
    /// current cadence). Takes effect from the next run start.
    pub fn set_fuel_intervals(&mut self, drink_moving_s: u32, eat_moving_s: u32) {
        if drink_moving_s > 0 {
            self.drink_interval_s = drink_moving_s;
        }
        if eat_moving_s > 0 {
            self.eat_interval_s = eat_moving_s;
        }
    }

    /// Configure the zone-ceiling alert: fire when the live zone rises above
    /// `zone`. Only 1..=4 make sense (nothing sits above Z5); anything else
    /// is ignored so garbage can't arm a bogus alert. `None` turns it off —
    /// the default.
    pub fn set_zone_ceiling(&mut self, zone: Option<u8>) {
        match zone {
            None => self.zone_ceiling = None,
            Some(z) if (1..=4).contains(&z) => self.zone_ceiling = Some(z),
            Some(_) => {}
        }
    }

    /// Feed one recorder snapshot (plus the live BPM, which the snapshot does
    /// not carry) and get the alert currently on screen, if any. Call once per
    /// record-task event — the 1 Hz tick bounds how stale an expiry can be.
    pub fn on_update(
        &mut self,
        snap: &Snapshot,
        hr_bpm: Option<u16>,
        uptime_s: u32,
    ) -> Option<Alert> {
        match snap.state {
            RecordState::Idle | RecordState::Finished => {
                self.reset();
                return None;
            }
            RecordState::Recording | RecordState::Paused => {}
        }
        if !self.in_run {
            self.reset();
            self.next_drink_at_moving_s = self.drink_interval_s;
            self.next_eat_at_moving_s = self.eat_interval_s;
            self.in_run = true;
        }

        if let Some((_, raised_at)) = self.active {
            if uptime_s.saturating_sub(raised_at) >= ALERT_TTL_S {
                self.active = None;
            }
        }

        // Zone ceiling — only while actually recording: a paused runner is
        // not over-effort, whatever the sensor reads.
        if snap.state == RecordState::Recording {
            if let (Some(ceiling), Some(bpm)) = (self.zone_ceiling, hr_bpm) {
                let zone = hr_zones::zone_for_bpm(bpm, &snap.zone_cutoffs);
                if zone > ceiling {
                    let cooled = self
                        .last_zone_fire_s
                        .is_none_or(|t| uptime_s.saturating_sub(t) >= ZONE_ALERT_COOLDOWN_S);
                    if self.zone_armed && cooled {
                        match self.active {
                            Some((Alert::Drink, _)) => self.pending_drink = true,
                            Some((Alert::Eat, _)) => self.pending_eat = true,
                            _ => {}
                        }
                        self.active = Some((Alert::ZoneAbove(zone), uptime_s));
                        self.zone_armed = false;
                        self.last_zone_fire_s = Some(uptime_s);
                    }
                } else {
                    self.zone_armed = true;
                }
            }
        }

        if snap.moving_s >= self.next_eat_at_moving_s {
            self.pending_eat = true;
            self.next_eat_at_moving_s = snap.moving_s + self.eat_interval_s;
        }
        if snap.moving_s >= self.next_drink_at_moving_s {
            self.pending_drink = true;
            self.next_drink_at_moving_s = snap.moving_s + self.drink_interval_s;
        }

        if self.active.is_none() {
            if self.pending_eat {
                self.pending_eat = false;
                self.active = Some((Alert::Eat, uptime_s));
            } else if self.pending_drink {
                self.pending_drink = false;
                self.active = Some((Alert::Drink, uptime_s));
            }
        }

        self.active.map(|(alert, _)| alert)
    }

    /// Back to the between-runs state. Configuration (intervals, ceiling)
    /// survives — it is settings, not run state.
    fn reset(&mut self) {
        self.active = None;
        self.pending_drink = false;
        self.pending_eat = false;
        self.zone_armed = true;
        self.last_zone_fire_s = None;
        self.in_run = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM, ZONE_COUNT};

    fn snap(state: RecordState, moving_s: u32) -> Snapshot {
        Snapshot {
            state,
            distance_m: 0.0,
            elapsed_s: moving_s,
            moving_s,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
            gap_s_per_km: None,
            lap: 1,
            lap_distance_m: 0.0,
            lap_elapsed_s: 0,
            last_lap: None,
            zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            zone_time_s: [0; ZONE_COUNT],
        }
    }

    fn rec(moving_s: u32) -> Snapshot {
        snap(RecordState::Recording, moving_s)
    }

    #[test]
    fn cadences_derive_from_the_fuel_plan_defaults() {
        // 60 g/hr at 25 g per gel: one gel every 25 minutes of moving time.
        assert_eq!(EAT_INTERVAL_MOVING_S, 3600 * 25 / 60);
        // 500 ml/hr at ~125 ml per soft-flask sip: four sips an hour.
        assert_eq!(DRINK_INTERVAL_MOVING_S, 3600 * 125 / 500);
    }

    #[test]
    fn drink_fires_on_the_moving_time_cadence() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rec(0), None, 0), None);
        assert_eq!(e.on_update(&rec(899), None, 899), None);
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
    }

    #[test]
    fn eat_fires_on_its_cadence() {
        let mut e = AlertEngine::new();
        // Sit between reminders so the drink alert (due at 900/1800) has
        // expired by the time eat comes due.
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
        assert_eq!(e.on_update(&rec(1400), None, 1400), None);
        assert_eq!(e.on_update(&rec(1500), None, 1500), Some(Alert::Eat));
    }

    #[test]
    fn alert_expires_after_its_ttl() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
        assert_eq!(
            e.on_update(&rec(900 + ALERT_TTL_S - 1), None, 900 + ALERT_TTL_S - 1),
            Some(Alert::Drink)
        );
        assert_eq!(
            e.on_update(&rec(900 + ALERT_TTL_S), None, 900 + ALERT_TTL_S),
            None
        );
    }

    #[test]
    fn reminders_repeat_each_interval() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 1_000_000);
        assert_eq!(e.on_update(&rec(300), None, 300), Some(Alert::Drink));
        assert_eq!(e.on_update(&rec(400), None, 400), None);
        // Re-based from the fire: the next sip is due at 300 + 300.
        assert_eq!(e.on_update(&rec(599), None, 599), None);
        assert_eq!(e.on_update(&rec(600), None, 600), Some(Alert::Drink));
    }

    #[test]
    fn paused_time_banks_nothing_toward_the_cadence() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rec(899), None, 899), None);
        // A long stop (manual or auto pause): moving time frozen while the
        // wall clock runs on — no reminder for standing at an aid station.
        for t in 900..2000 {
            assert_eq!(e.on_update(&snap(RecordState::Paused, 899), None, t), None);
        }
        // The next moving second crosses the threshold.
        assert_eq!(e.on_update(&rec(900), None, 2001), Some(Alert::Drink));
    }

    #[test]
    fn eat_outranks_drink_and_the_loser_requeues() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 300);
        // Both come due on the same update: eat wins the single slot.
        assert_eq!(e.on_update(&rec(300), None, 300), Some(Alert::Eat));
        // The drink reminder was queued, not dropped — it shows after the TTL.
        let after = 300 + ALERT_TTL_S;
        assert_eq!(e.on_update(&rec(after), None, after), Some(Alert::Drink));
    }

    #[test]
    fn zone_alert_is_off_by_default() {
        let mut e = AlertEngine::new();
        // Z5 BPM on the default ladder, no ceiling configured: nothing fires.
        assert_eq!(e.on_update(&rec(10), Some(185), 10), None);
    }

    #[test]
    fn zone_alert_fires_above_the_ceiling_and_carries_the_zone() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        // 152 bpm is Z3 on the 190 ladder — at the ceiling, not above it.
        assert_eq!(e.on_update(&rec(10), Some(152), 10), None);
        assert_eq!(
            e.on_update(&rec(11), Some(153), 11),
            Some(Alert::ZoneAbove(4))
        );
    }

    #[test]
    fn zone_ceiling_setter_rejects_garbage() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(0));
        e.set_zone_ceiling(Some(5));
        e.set_zone_ceiling(Some(200));
        assert_eq!(e.on_update(&rec(10), Some(185), 10), None);
        e.set_zone_ceiling(Some(4));
        assert_eq!(
            e.on_update(&rec(11), Some(185), 11),
            Some(Alert::ZoneAbove(5))
        );
        // None turns it back off.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(4));
        e.set_zone_ceiling(None);
        assert_eq!(e.on_update(&rec(10), Some(185), 10), None);
    }

    #[test]
    fn zone_alert_fires_once_per_excursion() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&rec(10), Some(160), 10),
            Some(Alert::ZoneAbove(4))
        );
        // Still above the ceiling after the TTL: disarmed, no re-fire.
        for t in 11..120 {
            let shown = e.on_update(&rec(t), Some(160), t);
            assert!(
                shown.is_none() || t < 10 + ALERT_TTL_S,
                "re-fired while still above the ceiling at t={}",
                t
            );
        }
    }

    #[test]
    fn zone_alert_rearms_after_dropping_back_but_cooldown_gates_flapping() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&rec(10), Some(160), 10),
            Some(Alert::ZoneAbove(4))
        );
        // Dip back to Z3 (re-arm), recross within the cooldown: no fire.
        let t1 = 10 + ALERT_TTL_S + 1;
        assert_eq!(e.on_update(&rec(t1), Some(150), t1), None);
        assert_eq!(e.on_update(&rec(t1 + 1), Some(160), t1 + 1), None);
        // Dip and recross again past the cooldown: fires.
        let t2 = 10 + ZONE_ALERT_COOLDOWN_S;
        assert_eq!(e.on_update(&rec(t2), Some(150), t2), None);
        assert_eq!(
            e.on_update(&rec(t2 + 1), Some(160), t2 + 1),
            Some(Alert::ZoneAbove(4))
        );
    }

    #[test]
    fn zone_alert_supersedes_an_active_fuel_reminder_which_requeues() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
        // Over-effort mid-reminder: the zone alert takes the slot at once.
        assert_eq!(
            e.on_update(&rec(902), Some(160), 902),
            Some(Alert::ZoneAbove(4))
        );
        // The superseded drink reminder comes back after the zone TTL.
        let after = 902 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&rec(after), Some(150), after),
            Some(Alert::Drink)
        );
    }

    #[test]
    fn no_hr_reading_never_fires_the_zone_alert() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(1));
        for t in 0..30 {
            assert_eq!(e.on_update(&rec(t), None, t), None);
        }
    }

    #[test]
    fn zone_alert_is_gated_to_recording_not_paused() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&snap(RecordState::Paused, 10), Some(160), 10),
            None
        );
        // Back to recording with the same BPM: fires.
        assert_eq!(
            e.on_update(&rec(11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
    }

    #[test]
    fn idle_and_finished_clear_everything_and_a_new_run_rebases() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
        // Stop mid-TTL: the alert clears with the run.
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 900), None, 902),
            None
        );
        assert_eq!(e.on_update(&snap(RecordState::Idle, 0), None, 903), None);
        // A new run measures its cadence from zero moving time again.
        assert_eq!(e.on_update(&rec(0), None, 1000), None);
        assert_eq!(e.on_update(&rec(899), None, 1899), None);
        assert_eq!(e.on_update(&rec(900), None, 1900), Some(Alert::Drink));
    }

    #[test]
    fn set_fuel_intervals_shortens_the_cadence_and_ignores_zero() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(30, 0);
        assert_eq!(e.on_update(&rec(30), None, 30), Some(Alert::Drink));
        // The zero eat interval kept the default: nothing due at 60 s.
        let t = 30 + ALERT_TTL_S;
        assert_eq!(e.on_update(&rec(t), None, t), None);
        assert_eq!(e.on_update(&rec(1500), None, 1500), Some(Alert::Eat));
    }

    #[test]
    fn banner_text_is_the_bang_prefixed_label() {
        assert_eq!(banner(Alert::Drink).as_str(), "! DRINK");
        assert_eq!(banner(Alert::Eat).as_str(), "! EAT");
        assert_eq!(banner(Alert::ZoneAbove(5)).as_str(), "! ZONE 5");
        // A corrupt zone clamps instead of overflowing the banner.
        assert_eq!(banner(Alert::ZoneAbove(200)).as_str(), "! ZONE 9");
        // At 2x every banner must fit the 21-cell panel row.
        for a in [Alert::Drink, Alert::Eat, Alert::ZoneAbove(5)] {
            assert!(banner(a).chars().count() * 2 <= crate::face::COLS);
        }
    }
}
