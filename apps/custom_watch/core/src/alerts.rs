//! On-run alerts — drink / eat reminders on a moving-time cadence, an HR-zone
//! ceiling alert, and the distance / time / pace kinds every running watch
//! carries (README step 7; the roadmap's "on-run alerts" slice).
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
//! The distance alert fires every [`set_distance_interval`](AlertEngine::set_distance_interval)
//! metres of accumulated distance, the time alert every
//! [`set_time_interval`](AlertEngine::set_time_interval) seconds. Both report
//! **exact multiples** of their interval and skip rather than burst: a fix that
//! carries the run past several milestones at once announces the highest one
//! reached, so the number on the banner is never stale and never drifts off the
//! interval the way a re-based threshold would.
//!
//! The two bank on different clocks, deliberately. Distance banks on
//! [`Snapshot::distance_m`], which only accrues while the runner moves, so a
//! pause contributes nothing for free. The time alert banks on
//! [`Snapshot::elapsed_s`] — the race clock, like [`crate::pacer`] and the
//! cut-off schedule, not the moving clock the fuel cadences use. A periodic
//! reminder means "half an hour of this race has passed"; keyed off moving time
//! it would drift out of any relationship with the cut-offs the runner is
//! actually racing, and would only duplicate the axis the fuel arms already
//! cover. It therefore keeps ticking through a pause, which is the honest
//! reading of a clock that does not stop at an aid station.
//!
//! The pace alert fires when [`Snapshot::current_pace_s_per_km`] leaves a
//! configured band ([`set_pace_band`](AlertEngine::set_pace_band)). Pace noise
//! around a band edge is the same flapping problem BPM has at a zone boundary,
//! so it reuses the zone alert's mechanism rather than a second one: once per
//! excursion, re-arming only on a sample back inside the band, with the
//! [`PACE_ALERT_COOLDOWN_S`] gate on top.
//!
//! At most one alert is on screen at a time, for [`ALERT_TTL_S`] seconds, and
//! the arms are ranked by what an ultra runner cannot afford to lose:
//!
//! 1. **Zone** — over-effort against physiological ground truth. Supersedes
//!    anything below it.
//! 2. **Pace** — the same correct-it-now class one rung down, because pace is a
//!    proxy for the effort HR measures directly. It supersedes a fuel reminder
//!    but never a zone banner; blocked by one, it stays armed and un-cooled so
//!    it retries while the excursion lasts, rather than being swallowed.
//! 3. **Eat**, then **Drink** — a reminder can wait eight seconds, so these
//!    only take a free slot; a superseded one **re-queues** (fuel is the
//!    ultra-critical reminder, it must never be silently dropped) and queued
//!    reminders promote eat-before-drink when a slot frees.
//! 4. **Distance**, then **Time** — milestones, and the only arms that are
//!    *dropped* rather than queued when the slot is busy. A milestone banner is
//!    meaningful only at the moment it is reached; showing "5.0 KM" once the
//!    runner is at 5.4 km is worse than not showing it, and unlike fuel there is
//!    nothing left to act on later — the totals are on the page. Distance leads
//!    the tie because distance is what the race is measured in.
//!
//! Display-only by design: the DK has no vibration motor, and alerts are an
//! L4 auxiliary — the engine is pure and fed *after* the recorder updates, so
//! nothing here can disturb the recording math.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator.

use core::fmt::Write;

use crate::hr_zones;
use crate::record::{RecordState, Snapshot};
use crate::workout::WorkoutStepKind;

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

/// The same anti-flap gate for the pace band. Derived from the zone constant
/// rather than restating 60 because it is the same problem — a noisy signal
/// crossing a configured boundary — and the two must not drift apart by
/// accident.
pub const PACE_ALERT_COOLDOWN_S: u32 = ZONE_ALERT_COOLDOWN_S;

/// Plausibility window for the distance-alert interval, borrowed from the
/// pacer's goal-distance window because the bounds mean the same thing here:
/// below [`crate::pacer::GOAL_DISTANCE_MIN_M`] a value is a tap error rather
/// than a lap, and past [`crate::pacer::GOAL_DISTANCE_MAX_M`] the interval
/// outruns the longest single effort the tier-1 store can hold, so it could
/// never fire.
pub const DISTANCE_INTERVAL_MIN_M: u32 = crate::pacer::GOAL_DISTANCE_MIN_M;
pub const DISTANCE_INTERVAL_MAX_M: u32 = crate::pacer::GOAL_DISTANCE_MAX_M;

/// Plausibility window for the time-alert interval, from the pacer's goal-time
/// window for the same reasons: under a minute an [`ALERT_TTL_S`] banner would
/// occupy more than a tenth of the runner's screen and stop reading as an
/// alert, and past the top of the window the interval outlasts any recordable
/// run.
pub const TIME_INTERVAL_MIN_S: u32 = crate::pacer::GOAL_TIME_MIN_S;
pub const TIME_INTERVAL_MAX_S: u32 = crate::pacer::GOAL_TIME_MAX_S;

/// Plausibility window for either edge of the pace band. The fast edge sits a
/// step beyond any human record over any distance; the slow edge is the app's
/// own live-pace ceiling ([`crate::grade_adjusted_pace::MAX_PACE_S_PER_KM`],
/// 99:00/km), past which a value is a runaway rather than a pace.
pub const PACE_BAND_MIN_S_PER_KM: u32 = 120;
pub const PACE_BAND_MAX_S_PER_KM: u32 = 5_940;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Alert {
    /// Take a sip — [`DRINK_INTERVAL_MOVING_S`] of moving time banked.
    Drink,
    /// Take a gel — [`EAT_INTERVAL_MOVING_S`] of moving time banked.
    Eat,
    /// The live HR zone (carried for display) rose above the ceiling.
    ZoneAbove(u8),
    /// A distance milestone, carried in metres as an exact multiple of the
    /// configured interval.
    Distance(u32),
    /// An elapsed-time milestone, carried in seconds as an exact multiple of
    /// the configured interval. The banner renders it `H:MM` — the truncation
    /// of the elapsed hero, so a half-hour milestone reads `0:30`, not `30:00`.
    Time(u32),
    /// Live pace is below the band's fast edge.
    PaceFast,
    /// Live pace is above the band's slow edge.
    PaceSlow,
    /// The armed structured workout entered a new step — the step now active
    /// ([`crate::workout`]).
    WorkoutStep {
        kind: WorkoutStepKind,
        rep_index: u8,
        rep_total: u8,
    },
    /// The active workout step entered its end-of-step warning window (last
    /// 50 m / last 10 s) — get ready for the change.
    WorkoutEnding,
    /// The structured workout's final step completed.
    WorkoutDone,
}

/// The banner the face draws over the hero band while an alert is active —
/// `!` plus an all-caps label, rendered by the app as an inverse-video band
/// (light 2x text knocked out of solid ink). Inverse video is free on a
/// 1-bit framebuffer — fg and bg simply swap at draw time — making the band
/// the panel's loudest treatment; an earlier claim here that the panel had
/// no inverse text to spend was wrong.
pub type Banner = heapless::String<10>;

pub fn banner(alert: Alert) -> Banner {
    let mut b = Banner::new();
    let _ = match alert {
        Alert::Drink => write!(b, "! DRINK"),
        Alert::Eat => write!(b, "! EAT"),
        Alert::ZoneAbove(zone) => write!(b, "! ZONE {}", zone.min(9)),
        Alert::Distance(milestone_m) => {
            write!(
                b,
                "! {:.1} KM",
                (f64::from(milestone_m) / 1000.0).min(999.9)
            )
        }
        // The trailing H is what separates a 30-minute milestone from a 30-second
        // one: every other banner is a word or a unit-tagged number, so a bare
        // `0:30` is the only one a glance can read on the wrong scale.
        Alert::Time(milestone_s) => write!(
            b,
            "! {}:{:02} H",
            (milestone_s / 3600).min(999),
            milestone_s / 60 % 60
        ),
        Alert::PaceFast => write!(b, "! TOO FAST"),
        Alert::PaceSlow => write!(b, "! TOO SLOW"),
        Alert::WorkoutStep {
            kind,
            rep_index,
            rep_total,
        } => {
            let word = match kind {
                WorkoutStepKind::Warmup => "WARMUP",
                WorkoutStepKind::Rep => "REP",
                // No numbering: RECOVER + any count overflows the band, and
                // the rep the recovery follows already carried the numbers.
                WorkoutStepKind::Recovery => "RECOVER",
                WorkoutStepKind::Walk => "WALK",
                WorkoutStepKind::Steady => "STEADY",
                WorkoutStepKind::Cooldown => "COOLDOWN",
            };
            let numbered =
                matches!(kind, WorkoutStepKind::Rep | WorkoutStepKind::Walk) && rep_total > 0;
            if numbered {
                // The full i/n form when the ten-glyph band fits it, else the
                // index alone — a truncated "! REP 12/2" would read as a
                // different count.
                let mut full = heapless::String::<16>::new();
                let _ = write!(full, "! {word} {rep_index}/{rep_total}");
                if full.len() <= b.capacity() {
                    write!(b, "{full}")
                } else {
                    write!(b, "! {word} {rep_index}")
                }
            } else {
                write!(b, "! {word}")
            }
        }
        Alert::WorkoutEnding => write!(b, "! STEP END"),
        Alert::WorkoutDone => write!(b, "! WKT DONE"),
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
    /// Metres of accumulated distance between milestones. `None` = off, the
    /// hardware default until a settings sync arms it.
    distance_interval_m: Option<u32>,
    /// Seconds of elapsed time between milestones. `None` = off.
    time_interval_s: Option<u32>,
    /// `(fast edge, slow edge)` in seconds per kilometre. `None` = off.
    pace_band: Option<(u32, u32)>,
    /// The last milestone announced on each arm — always an exact multiple of
    /// the interval in force when it fired, so milestones can neither drift nor
    /// repeat.
    last_distance_alert_m: u32,
    last_time_alert_s: u32,
    /// The pace band's half of the once-per-excursion hysteresis, mirroring
    /// [`Self::zone_armed`].
    pace_armed: bool,
    last_pace_fire_s: Option<u32>,
    /// The last workout edge counters seen ([`crate::workout::WorkoutView`]'s
    /// monotonic seqs), so each transition / warning fires exactly once. A
    /// blocked edge is dropped, not owed — a stale step banner is wrong.
    last_workout_transition_seq: u16,
    last_workout_ending_seq: u16,
    workout_done_fired: bool,
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
            distance_interval_m: None,
            time_interval_s: None,
            pace_band: None,
            last_distance_alert_m: 0,
            last_time_alert_s: 0,
            pace_armed: true,
            last_pace_fire_s: None,
            last_workout_transition_seq: 0,
            last_workout_ending_seq: 0,
            workout_done_fired: false,
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

    /// Configure the distance-alert cadence: fire every `interval_m` metres of
    /// accumulated distance — the classic every-kilometre (or every-mile, at
    /// 1609) notify. `None` turns it off, the default. An interval outside
    /// [`DISTANCE_INTERVAL_MIN_M`]`..=`[`DISTANCE_INTERVAL_MAX_M`] is ignored
    /// so garbage can't arm a nonsense cadence.
    pub fn set_distance_interval(&mut self, interval_m: Option<u32>) {
        match interval_m {
            None => self.distance_interval_m = None,
            Some(m) if (DISTANCE_INTERVAL_MIN_M..=DISTANCE_INTERVAL_MAX_M).contains(&m) => {
                self.distance_interval_m = Some(m)
            }
            Some(_) => {}
        }
    }

    /// Configure the time-alert cadence: fire every `interval_s` seconds of
    /// elapsed (race-clock) time. `None` turns it off, the default; an interval
    /// outside [`TIME_INTERVAL_MIN_S`]`..=`[`TIME_INTERVAL_MAX_S`] is ignored.
    pub fn set_time_interval(&mut self, interval_s: Option<u32>) {
        match interval_s {
            None => self.time_interval_s = None,
            Some(s) if (TIME_INTERVAL_MIN_S..=TIME_INTERVAL_MAX_S).contains(&s) => {
                self.time_interval_s = Some(s)
            }
            Some(_) => {}
        }
    }

    /// Configure the pace band: alert when live pace leaves
    /// `(fast_s_per_km, slow_s_per_km)`. `None` turns it off, the default.
    ///
    /// Both edges must sit inside
    /// [`PACE_BAND_MIN_S_PER_KM`]`..=`[`PACE_BAND_MAX_S_PER_KM`] and the fast
    /// edge must be strictly the smaller number — which also rejects a caller
    /// that passed the pair the wrong way round, the one mistake two
    /// same-typed arguments invite. A rejected band leaves the current one
    /// standing, never a half-applied one.
    pub fn set_pace_band(&mut self, band: Option<(u32, u32)>) {
        let plausible_edge =
            |p: u32| (PACE_BAND_MIN_S_PER_KM..=PACE_BAND_MAX_S_PER_KM).contains(&p);
        match band {
            None => self.pace_band = None,
            Some((fast, slow)) if fast < slow && plausible_edge(fast) && plausible_edge(slow) => {
                self.pace_band = Some((fast, slow))
            }
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
                        self.take_slot(Alert::ZoneAbove(zone), uptime_s);
                        self.zone_armed = false;
                        self.last_zone_fire_s = Some(uptime_s);
                    }
                } else {
                    self.zone_armed = true;
                }
            }

            // Pace band, one rung below the zone ceiling: it may take the slot
            // off a fuel reminder (which re-queues) or a milestone, but a zone
            // banner blocks it — and a blocked excursion neither disarms nor
            // stamps the cooldown, so it fires on a later tick while the runner
            // is still outside the band instead of being swallowed.
            if let (Some((fast, slow)), Some(pace)) = (self.pace_band, snap.current_pace_s_per_km) {
                if pace < fast || pace > slow {
                    let cooled = self
                        .last_pace_fire_s
                        .is_none_or(|t| uptime_s.saturating_sub(t) >= PACE_ALERT_COOLDOWN_S);
                    let outranked = matches!(
                        self.active,
                        Some((
                            Alert::ZoneAbove(_)
                                | Alert::WorkoutStep { .. }
                                | Alert::WorkoutEnding
                                | Alert::WorkoutDone,
                            _
                        ))
                    );
                    if self.pace_armed && cooled && !outranked {
                        let alert = if pace < fast {
                            Alert::PaceFast
                        } else {
                            Alert::PaceSlow
                        };
                        self.take_slot(alert, uptime_s);
                        self.pace_armed = false;
                        self.last_pace_fire_s = Some(uptime_s);
                    }
                } else {
                    self.pace_armed = true;
                }
            }
        }

        // Workout edges — the step transition, the end-of-step warning, and
        // completion, read off the snapshot's monotonic counters. NOT gated on
        // Recording: a timed recovery legitimately advances through an
        // auto-pause (a standing rest is that step working as intended), and
        // the next rep's entry banner is exactly what the runner needs then.
        // One rung under the zone ceiling: a workout banner takes the slot
        // from anything below (a displaced fuel reminder re-queues) but never
        // from a zone banner — and a blocked edge is dropped, not owed, the
        // milestone rule: a stale "REP 3" is worse than none, and the page
        // carries the current step regardless.
        match snap.workout {
            Some(w) => {
                let outranked = matches!(self.active, Some((Alert::ZoneAbove(_), _)));
                if w.ending_seq != self.last_workout_ending_seq {
                    self.last_workout_ending_seq = w.ending_seq;
                    if !outranked {
                        self.take_slot(Alert::WorkoutEnding, uptime_s);
                    }
                }
                // After the ending warning so a same-tick advance shows the
                // new step, not the old step's last-metres notice.
                if w.transition_seq != self.last_workout_transition_seq {
                    self.last_workout_transition_seq = w.transition_seq;
                    if w.transition_seq > 0 && !outranked {
                        self.take_slot(
                            Alert::WorkoutStep {
                                kind: w.kind,
                                rep_index: w.rep_index,
                                rep_total: w.rep_total,
                            },
                            uptime_s,
                        );
                    }
                }
                if w.complete && !self.workout_done_fired {
                    self.workout_done_fired = true;
                    if !outranked {
                        self.take_slot(Alert::WorkoutDone, uptime_s);
                    }
                } else if !w.complete {
                    // A fresh workout pushed after one finished re-arms DONE.
                    self.workout_done_fired = false;
                }
            }
            None => {
                self.last_workout_transition_seq = 0;
                self.last_workout_ending_seq = 0;
                self.workout_done_fired = false;
            }
        }

        // Milestones advance whether or not they can be shown: a milestone the
        // busy slot swallows is gone, not owed, so the next one must still be
        // measured from where the run actually is.
        let mut distance_due = None;
        if let Some(interval_m) = self.distance_interval_m {
            let banked_m = snap.distance_m as u32;
            if banked_m >= self.last_distance_alert_m.saturating_add(interval_m) {
                self.last_distance_alert_m = banked_m / interval_m * interval_m;
                distance_due = Some(self.last_distance_alert_m);
            }
        }
        let mut time_due = None;
        if let Some(interval_s) = self.time_interval_s {
            if snap.elapsed_s >= self.last_time_alert_s.saturating_add(interval_s) {
                self.last_time_alert_s = snap.elapsed_s / interval_s * interval_s;
                time_due = Some(self.last_time_alert_s);
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
            } else if let Some(milestone_m) = distance_due {
                self.active = Some((Alert::Distance(milestone_m), uptime_s));
            } else if let Some(milestone_s) = time_due {
                self.active = Some((Alert::Time(milestone_s), uptime_s));
            }
        }

        self.active.map(|(alert, _)| alert)
    }

    /// Put `alert` on the display slot, re-queueing the fuel reminder it may
    /// be displacing (a superseded milestone / pace / workout banner is simply
    /// gone — §214's re-queue rule is fuel's alone).
    fn take_slot(&mut self, alert: Alert, uptime_s: u32) {
        match self.active {
            Some((Alert::Drink, _)) => self.pending_drink = true,
            Some((Alert::Eat, _)) => self.pending_eat = true,
            _ => {}
        }
        self.active = Some((alert, uptime_s));
    }

    /// Back to the between-runs state. Configuration (intervals, ceiling)
    /// survives — it is settings, not run state.
    fn reset(&mut self) {
        self.active = None;
        self.pending_drink = false;
        self.pending_eat = false;
        self.zone_armed = true;
        self.last_zone_fire_s = None;
        self.pace_armed = true;
        self.last_pace_fire_s = None;
        self.last_distance_alert_m = 0;
        self.last_time_alert_s = 0;
        self.last_workout_transition_seq = 0;
        self.last_workout_ending_seq = 0;
        self.workout_done_fired = false;
        self.in_run = false;
    }
}

/// A standing "fuel overdue" marker, distinct from the transient [`Alert`]
/// banner. The DK has no vibration motor, so a drink / eat reminder is only an
/// [`ALERT_TTL_S`]-second banner a heads-down trail runner never sees; this
/// says which fuel a reminder has fired for so the face can keep a small,
/// always-visible tag up until the runner acts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum FuelOverdue {
    #[default]
    None,
    Drink,
    Eat,
    Both,
}

/// Latches [`FuelOverdue`] from the transient alert stream the face already
/// receives on `state::ALERT`, so the persistent marker outlives the 8 s banner.
///
/// It rides the display side (`ui.rs` owns one) rather than living in
/// [`AlertEngine`] because the engine's per-tick verdict reaches the face only
/// as the single `Option<Alert>` banner — the record task publishes exactly
/// that and nothing else. Reconstructing the standing state from the banner the
/// face already sees keeps the whole feature inside that one channel (no second
/// cross-task signal to plumb) and stays pure + host-tested. It never feeds
/// [`AlertEngine::on_update`], so it cannot perturb the transient-banner
/// arbitration (zone still supersedes, fuel still re-queues) or the L4-isolated
/// recording math.
#[derive(Clone, Copy, Debug, Default)]
pub struct FuelOverdueTracker {
    drink: bool,
    eat: bool,
}

impl FuelOverdueTracker {
    pub const fn new() -> Self {
        Self {
            drink: false,
            eat: false,
        }
    }

    /// Fold one frame of watch state into the latch and return what to render.
    ///
    /// - `active` — the transient banner on screen this frame. A fuel banner
    ///   means that reminder just fired, so it latches (and re-latches each new
    ///   interval). Every other kind is ignored: a zone / pace / milestone
    ///   banner supersedes the *banner*, never the standing fuel-overdue marker.
    /// - `run_active` — false between runs (Idle / Finished). Clears the latch,
    ///   mirroring [`AlertEngine`]'s own reset so a new run starts clean, and so
    ///   a reminder that somehow fired outside a run can never latch.
    /// - `acknowledged` — the runner is attending to fuel (the Fuel glance page
    ///   is showing). Clears the latch; the next interval's reminder re-latches.
    pub fn observe(
        &mut self,
        active: Option<Alert>,
        run_active: bool,
        acknowledged: bool,
    ) -> FuelOverdue {
        if !run_active {
            self.drink = false;
            self.eat = false;
            return FuelOverdue::None;
        }
        match active {
            Some(Alert::Drink) => self.drink = true,
            Some(Alert::Eat) => self.eat = true,
            Some(
                Alert::ZoneAbove(_)
                | Alert::Distance(_)
                | Alert::Time(_)
                | Alert::PaceFast
                | Alert::PaceSlow
                | Alert::WorkoutStep { .. }
                | Alert::WorkoutEnding
                | Alert::WorkoutDone,
            )
            | None => {}
        }
        if acknowledged {
            self.drink = false;
            self.eat = false;
        }
        match (self.drink, self.eat) {
            (true, true) => FuelOverdue::Both,
            (true, false) => FuelOverdue::Drink,
            (false, true) => FuelOverdue::Eat,
            (false, false) => FuelOverdue::None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM, ZONE_COUNT};

    fn snap(state: RecordState, moving_s: u32) -> Snapshot {
        Snapshot {
            state,
            manual_paused: false,
            signal_lost: false,
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
            pacer: None,
            cutoff: None,
            race_prediction: None,
            pace_bucket_m: [0.0; crate::record::PACE_BUCKET_COUNT],
            training_stress: None,
            training_stress_trimp: false,
            load_trend: None,
            band: None,
            gear: None,
            roadbook: None,
            fuel: None,
            training_paces: None,
            fitness: None,
            elev_profile: crate::record::ElevProfileView::empty(),
            recap: None,
            streaks: None,
            run_stats: None,
            pr_recency: None,
            plan_replan: None,
            plan_adaptive: None,
            guided_run: None,
            workout: None,
            readiness: None,
            goals: None,
            turn_cue: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            route_position_permille: None,
            race_day: None,
            race_phase: None,
            climb: Default::default(),
            waypoint: None,
            waypoint_count: 0,
            track_thinning: 1,
            pages_mask: u64::MAX,
            hide_empty_pages: true,
        }
    }

    fn rec(moving_s: u32) -> Snapshot {
        snap(RecordState::Recording, moving_s)
    }

    fn dist(distance_m: f64, moving_s: u32) -> Snapshot {
        Snapshot {
            distance_m,
            ..rec(moving_s)
        }
    }

    fn paced(pace_s_per_km: u32, moving_s: u32) -> Snapshot {
        Snapshot {
            current_pace_s_per_km: Some(pace_s_per_km),
            ..rec(moving_s)
        }
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
    fn recording_slow_stretch_banks_only_moving_time_not_elapsed() {
        let mut e = AlertEngine::new();
        // Sub-moving-gate crawl / dropped GPS pulses while still Recording:
        // the wall clock (elapsed) runs to 2000 s but moving is frozen at 899.
        // A cadence keyed off elapsed would fire here; keyed off moving it must
        // not — the guard the shared `snap` helper (elapsed == moving) can't give.
        for t in 0..2000 {
            let s = Snapshot {
                elapsed_s: t,
                ..rec(899)
            };
            assert_eq!(e.on_update(&s, None, t), None, "fired off elapsed at t={t}");
        }
        // The 900th moving second finally crosses.
        assert_eq!(e.on_update(&rec(900), None, 2000), Some(Alert::Drink));
    }

    #[test]
    fn autopause_with_wall_clock_running_banks_nothing() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rec(899), None, 899), None);
        // Auto-pause at an aid station: moving frozen at 899, elapsed climbing.
        for t in 900..2000 {
            let s = Snapshot {
                elapsed_s: t,
                ..snap(RecordState::Paused, 899)
            };
            assert_eq!(
                e.on_update(&s, None, t),
                None,
                "fired while paused at t={t}"
            );
        }
        assert_eq!(e.on_update(&rec(900), None, 2001), Some(Alert::Drink));
    }

    #[test]
    fn zone_alert_supersedes_an_active_eat_which_requeues() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        e.set_fuel_intervals(1_000_000, 300);
        assert_eq!(e.on_update(&rec(300), None, 300), Some(Alert::Eat));
        assert_eq!(
            e.on_update(&rec(302), Some(160), 302),
            Some(Alert::ZoneAbove(4))
        );
        // The superseded eat is re-queued, not dropped — it returns post-TTL.
        let after = 302 + ALERT_TTL_S;
        assert_eq!(e.on_update(&rec(after), Some(150), after), Some(Alert::Eat));
    }

    #[test]
    fn after_zone_clears_eat_promotes_before_the_requeued_drink() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        e.set_fuel_intervals(300, 300);
        // Shared crossing: eat takes the slot, drink queues behind it.
        assert_eq!(e.on_update(&rec(300), None, 300), Some(Alert::Eat));
        // Zone supersedes the active eat: now both eat and drink are queued.
        assert_eq!(
            e.on_update(&rec(301), Some(160), 301),
            Some(Alert::ZoneAbove(4))
        );
        // Zone clears: eat-before-drink holds across the re-queue.
        let a = 301 + ALERT_TTL_S;
        assert_eq!(e.on_update(&rec(a), Some(150), a), Some(Alert::Eat));
        let b = a + ALERT_TTL_S;
        assert_eq!(e.on_update(&rec(b), Some(150), b), Some(Alert::Drink));
    }

    #[test]
    fn an_expiring_alert_does_not_swallow_a_newly_due_one() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(8, 16);
        assert_eq!(e.on_update(&rec(8), None, 8), Some(Alert::Drink));
        // At moving == 16 the drink's TTL expires on the very tick eat comes
        // due; the expiring alert must not block the newly-queued one.
        assert_eq!(e.on_update(&rec(16), None, 16), Some(Alert::Eat));
    }

    #[test]
    fn two_excursions_within_the_cooldown_fire_once_under_a_1hz_feed() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&rec(10), Some(160), 10),
            Some(Alert::ZoneAbove(4))
        );
        // Continuous 1 Hz feed: dip to re-arm at 20, cross again at 30 — all
        // inside the 60 s cooldown. No second alert after the first TTL.
        for t in 11..70 {
            let bpm = if (20..30).contains(&t) { 150 } else { 160 };
            let shown = e.on_update(&rec(t), Some(bpm), t);
            if t >= 10 + ALERT_TTL_S {
                assert_eq!(shown, None, "re-fired inside the cooldown at t={t}");
            }
        }
    }

    #[test]
    fn distance_alert_is_off_by_default() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&dist(5_000.0, 300), None, 300), None);
    }

    #[test]
    fn distance_alert_fires_every_interval() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        assert_eq!(e.on_update(&dist(999.0, 300), None, 300), None);
        assert_eq!(
            e.on_update(&dist(1_000.0, 301), None, 301),
            Some(Alert::Distance(1_000))
        );
        let t = 301 + ALERT_TTL_S;
        assert_eq!(e.on_update(&dist(1_500.0, t), None, t), None);
        assert_eq!(
            e.on_update(&dist(2_000.0, t + 1), None, t + 1),
            Some(Alert::Distance(2_000))
        );
    }

    #[test]
    fn distance_milestones_stay_on_exact_multiples_after_an_overshoot() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        // The 1 Hz feed crosses 1 km mid-tick, so the fire lands at 1009 m.
        assert_eq!(
            e.on_update(&dist(1_009.0, 300), None, 300),
            Some(Alert::Distance(1_000))
        );
        // A threshold re-based off the fire (the fuel arms' rule) would push the
        // next milestone out to 2009 m and drift a little further every time.
        let t = 300 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&dist(2_000.0, t), None, t),
            Some(Alert::Distance(2_000))
        );
    }

    #[test]
    fn a_distance_jump_reports_the_highest_milestone_not_a_burst() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        assert_eq!(
            e.on_update(&dist(3_500.0, 300), None, 300),
            Some(Alert::Distance(3_000))
        );
        // The skipped 1 km / 2 km milestones do not queue up behind it.
        let t = 300 + ALERT_TTL_S;
        assert_eq!(e.on_update(&dist(3_600.0, t), None, t), None);
        assert_eq!(
            e.on_update(&dist(4_000.0, t + 1), None, t + 1),
            Some(Alert::Distance(4_000))
        );
    }

    #[test]
    fn paused_distance_banks_nothing_toward_the_distance_alert() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        assert_eq!(e.on_update(&dist(999.0, 300), None, 300), None);
        // An aid-station stop: distance frozen a metre short while the wall
        // clock runs on. The shared `snap` helper's elapsed == moving can't show
        // this, so the snapshot is built by hand.
        for t in 301..1_400 {
            let s = Snapshot {
                distance_m: 999.0,
                elapsed_s: t,
                ..snap(RecordState::Paused, 300)
            };
            assert_eq!(
                e.on_update(&s, None, t),
                None,
                "fired while paused at t={t}"
            );
        }
        assert_eq!(
            e.on_update(&dist(1_000.0, 301), None, 1_400),
            Some(Alert::Distance(1_000))
        );
    }

    #[test]
    fn distance_interval_setter_rejects_garbage() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(0));
        e.set_distance_interval(Some(DISTANCE_INTERVAL_MIN_M - 1));
        e.set_distance_interval(Some(DISTANCE_INTERVAL_MAX_M + 1));
        assert_eq!(e.on_update(&dist(500_000.0, 300), None, 300), None);
        e.set_distance_interval(Some(DISTANCE_INTERVAL_MIN_M));
        assert_eq!(
            e.on_update(&dist(500_000.0, 301), None, 301),
            Some(Alert::Distance(500_000))
        );
        // None turns it back off.
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        e.set_distance_interval(None);
        assert_eq!(e.on_update(&dist(5_000.0, 300), None, 300), None);
    }

    #[test]
    fn time_alert_is_off_by_default() {
        let mut e = AlertEngine::new();
        let held = Snapshot {
            elapsed_s: 7_200,
            ..rec(100)
        };
        assert_eq!(e.on_update(&held, None, 7_200), None);
    }

    #[test]
    fn time_alert_banks_on_elapsed_not_moving_time() {
        let mut e = AlertEngine::new();
        e.set_time_interval(Some(1_800));
        // Moving time frozen at 100 s while the race clock runs to half an hour
        // — the gap the shared `snap` helper (elapsed == moving) hides. A
        // cadence keyed off moving time would stay silent here; this arm is
        // deliberately the race clock, so it must fire.
        let held = |t: u32| Snapshot {
            elapsed_s: t,
            ..rec(100)
        };
        assert_eq!(e.on_update(&held(1_799), None, 1_799), None);
        assert_eq!(
            e.on_update(&held(1_800), None, 1_800),
            Some(Alert::Time(1_800))
        );
    }

    #[test]
    fn time_alert_keeps_ticking_through_a_pause() {
        let mut e = AlertEngine::new();
        e.set_time_interval(Some(1_800));
        let stopped = |t: u32| Snapshot {
            elapsed_s: t,
            ..snap(RecordState::Paused, 0)
        };
        assert_eq!(e.on_update(&stopped(1_799), None, 1_799), None);
        // A race clock does not stop at an aid station.
        assert_eq!(
            e.on_update(&stopped(1_800), None, 1_800),
            Some(Alert::Time(1_800))
        );
    }

    #[test]
    fn time_milestones_are_exact_multiples_and_a_gap_reports_the_highest() {
        let mut e = AlertEngine::new();
        e.set_time_interval(Some(1_800));
        let held = |t: u32| Snapshot {
            elapsed_s: t,
            ..rec(100)
        };
        assert_eq!(
            e.on_update(&held(5_000), None, 5_000),
            Some(Alert::Time(3_600))
        );
        let t = 5_000 + ALERT_TTL_S;
        assert_eq!(e.on_update(&held(t), None, t), None);
        assert_eq!(
            e.on_update(&held(5_400), None, 5_400),
            Some(Alert::Time(5_400))
        );
    }

    #[test]
    fn time_interval_setter_rejects_garbage() {
        let mut e = AlertEngine::new();
        let held = |t: u32| Snapshot {
            elapsed_s: t,
            ..rec(100)
        };
        e.set_time_interval(Some(0));
        e.set_time_interval(Some(TIME_INTERVAL_MIN_S - 1));
        e.set_time_interval(Some(TIME_INTERVAL_MAX_S + 1));
        assert_eq!(e.on_update(&held(7_200), None, 7_200), None);
        e.set_time_interval(Some(TIME_INTERVAL_MIN_S));
        assert_eq!(
            e.on_update(&held(7_201), None, 7_201),
            Some(Alert::Time(7_200))
        );
        // None turns it back off.
        let mut e = AlertEngine::new();
        e.set_time_interval(Some(1_800));
        e.set_time_interval(None);
        assert_eq!(e.on_update(&held(1_800), None, 1_800), None);
    }

    #[test]
    fn pace_alert_is_off_by_default() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&paced(60, 10), None, 10), None);
    }

    #[test]
    fn pace_alert_fires_outside_either_edge_and_not_on_them() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        // Both edges are inside the band.
        assert_eq!(e.on_update(&paced(300, 10), None, 10), None);
        assert_eq!(e.on_update(&paced(420, 11), None, 11), None);
        assert_eq!(
            e.on_update(&paced(299, 12), None, 12),
            Some(Alert::PaceFast)
        );
        // A fresh engine for the slow side — the first fire disarms this one.
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        assert_eq!(
            e.on_update(&paced(421, 10), None, 10),
            Some(Alert::PaceSlow)
        );
    }

    #[test]
    fn pace_alert_fires_once_per_excursion() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        assert_eq!(
            e.on_update(&paced(250, 10), None, 10),
            Some(Alert::PaceFast)
        );
        // Still outside the band after the TTL: disarmed, no re-fire.
        for t in 11..120 {
            let shown = e.on_update(&paced(250, t), None, t);
            assert!(
                shown.is_none() || t < 10 + ALERT_TTL_S,
                "re-fired while still outside the band at t={t}"
            );
        }
    }

    #[test]
    fn pace_alert_rearms_inside_the_band_but_the_cooldown_gates_flapping() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        assert_eq!(
            e.on_update(&paced(250, 10), None, 10),
            Some(Alert::PaceFast)
        );
        // Back inside (re-arm), out again within the cooldown: no fire.
        let t1 = 10 + ALERT_TTL_S + 1;
        assert_eq!(e.on_update(&paced(360, t1), None, t1), None);
        assert_eq!(e.on_update(&paced(250, t1 + 1), None, t1 + 1), None);
        // Dip back in and out again past the cooldown: fires.
        let t2 = 10 + PACE_ALERT_COOLDOWN_S;
        assert_eq!(e.on_update(&paced(360, t2), None, t2), None);
        assert_eq!(
            e.on_update(&paced(250, t2 + 1), None, t2 + 1),
            Some(Alert::PaceFast)
        );
    }

    #[test]
    fn pace_band_setter_rejects_garbage() {
        let mut e = AlertEngine::new();
        // A swapped pair, a zero-width band, and either edge out of window.
        e.set_pace_band(Some((420, 300)));
        e.set_pace_band(Some((300, 300)));
        e.set_pace_band(Some((0, 420)));
        e.set_pace_band(Some((PACE_BAND_MIN_S_PER_KM - 1, 420)));
        e.set_pace_band(Some((300, PACE_BAND_MAX_S_PER_KM + 1)));
        assert_eq!(e.on_update(&paced(60, 10), None, 10), None);
        e.set_pace_band(Some((PACE_BAND_MIN_S_PER_KM, PACE_BAND_MAX_S_PER_KM)));
        assert_eq!(
            e.on_update(&paced(PACE_BAND_MIN_S_PER_KM - 1, 11), None, 11),
            Some(Alert::PaceFast)
        );
        // None turns it back off.
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        e.set_pace_band(None);
        assert_eq!(e.on_update(&paced(60, 10), None, 10), None);
    }

    #[test]
    fn pace_alert_is_gated_to_recording_not_paused() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        let stale = Snapshot {
            current_pace_s_per_km: Some(250),
            ..snap(RecordState::Paused, 10)
        };
        assert_eq!(e.on_update(&stale, None, 10), None);
        // Back to recording with the same pace: fires.
        assert_eq!(
            e.on_update(&paced(250, 11), None, 11),
            Some(Alert::PaceFast)
        );
    }

    #[test]
    fn no_pace_reading_never_fires_the_pace_alert() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        for t in 0..30 {
            assert_eq!(e.on_update(&rec(t), None, t), None);
        }
    }

    #[test]
    fn zone_outranks_pace_and_a_blocked_excursion_retries() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        e.set_pace_band(Some((300, 420)));
        let hot = |pace: u32, t: u32| Snapshot {
            current_pace_s_per_km: Some(pace),
            ..rec(t)
        };
        // Both come due on the same update: HR is the ground truth pace only
        // proxies, so the zone alert takes the slot.
        assert_eq!(
            e.on_update(&hot(250, 10), Some(160), 10),
            Some(Alert::ZoneAbove(4))
        );
        // The blocked excursion stayed armed and un-cooled, so it fires the
        // moment the zone banner clears — still outside the band.
        let after = 10 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&hot(250, after), Some(150), after),
            Some(Alert::PaceFast)
        );
    }

    #[test]
    fn pace_supersedes_an_active_fuel_reminder_which_requeues() {
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        assert_eq!(e.on_update(&rec(900), None, 900), Some(Alert::Drink));
        assert_eq!(
            e.on_update(&paced(250, 902), None, 902),
            Some(Alert::PaceFast)
        );
        // The superseded reminder comes back after the pace TTL, not lost.
        let after = 902 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&paced(360, after), None, after),
            Some(Alert::Drink)
        );
    }

    #[test]
    fn a_milestone_is_dropped_not_queued_when_fuel_holds_the_slot() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        // The run crosses 1 km on the very update the drink reminder comes due.
        assert_eq!(
            e.on_update(&dist(1_000.0, 900), None, 900),
            Some(Alert::Drink)
        );
        // Unlike fuel, the milestone is gone rather than owed: nothing surfaces
        // when the slot frees, and the next one is measured from 2 km.
        let t = 900 + ALERT_TTL_S;
        assert_eq!(e.on_update(&dist(1_500.0, t), None, t), None);
        assert_eq!(
            e.on_update(&dist(2_000.0, t + 1), None, t + 1),
            Some(Alert::Distance(2_000))
        );
    }

    #[test]
    fn distance_leads_time_when_both_milestones_land_together() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        e.set_time_interval(Some(TIME_INTERVAL_MIN_S));
        let both = |distance_m: f64, elapsed_s: u32| Snapshot {
            distance_m,
            elapsed_s,
            ..rec(30)
        };
        assert_eq!(
            e.on_update(&both(1_000.0, 60), None, 60),
            Some(Alert::Distance(1_000))
        );
        // The time milestone was dropped too, and its next one is measured from
        // where the clock actually is.
        let t = 60 + ALERT_TTL_S;
        assert_eq!(e.on_update(&both(1_100.0, t), None, t), None);
        assert_eq!(
            e.on_update(&both(1_100.0, 120), None, 120),
            Some(Alert::Time(120))
        );
    }

    #[test]
    fn idle_clears_the_milestone_arms_and_a_new_run_rebases_them() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        assert_eq!(
            e.on_update(&dist(1_000.0, 300), None, 300),
            Some(Alert::Distance(1_000))
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 300), None, 302),
            None
        );
        // A new run measures the cadence from zero again; the interval survives
        // because it is settings, not run state.
        assert_eq!(
            e.on_update(&dist(1_000.0, 300), None, 1_000),
            Some(Alert::Distance(1_000))
        );
    }

    #[test]
    fn the_pace_band_ceiling_is_the_apps_own_live_pace_ceiling() {
        assert_eq!(
            f64::from(PACE_BAND_MAX_S_PER_KM),
            crate::grade_adjusted_pace::MAX_PACE_S_PER_KM
        );
    }

    #[test]
    fn banner_text_is_the_bang_prefixed_label() {
        assert_eq!(banner(Alert::Drink).as_str(), "! DRINK");
        assert_eq!(banner(Alert::Eat).as_str(), "! EAT");
        assert_eq!(banner(Alert::ZoneAbove(5)).as_str(), "! ZONE 5");
        assert_eq!(banner(Alert::Distance(5_000)).as_str(), "! 5.0 KM");
        assert_eq!(banner(Alert::Distance(1_609)).as_str(), "! 1.6 KM");
        assert_eq!(banner(Alert::Time(1_800)).as_str(), "! 0:30 H");
        assert_eq!(banner(Alert::Time(3 * 3600 + 45 * 60)).as_str(), "! 3:45 H");
        assert_eq!(banner(Alert::PaceFast).as_str(), "! TOO FAST");
        assert_eq!(banner(Alert::PaceSlow).as_str(), "! TOO SLOW");
        // A corrupt zone / milestone clamps instead of overflowing the banner.
        assert_eq!(banner(Alert::ZoneAbove(200)).as_str(), "! ZONE 9");
        assert_eq!(banner(Alert::Distance(u32::MAX)).as_str(), "! 999.9 KM");
        assert_eq!(banner(Alert::Time(u32::MAX)).as_str(), "! 999:28 H");
        // At 2x every banner must fit the 21-cell panel row, worst case included.
        for a in [
            Alert::Drink,
            Alert::Eat,
            Alert::ZoneAbove(5),
            Alert::Distance(u32::MAX),
            Alert::Time(u32::MAX),
            Alert::PaceFast,
            Alert::PaceSlow,
        ] {
            assert!(banner(a).chars().count() * 2 <= crate::face::COLS);
        }
    }

    #[test]
    fn the_milestone_and_pace_banners_leave_the_fuel_overdue_marker_untouched() {
        let mut ov = FuelOverdueTracker::new();
        assert_eq!(ov.observe(Some(Alert::Eat), true, false), FuelOverdue::Eat);
        for a in [
            Alert::Distance(5_000),
            Alert::Time(1_800),
            Alert::PaceFast,
            Alert::PaceSlow,
        ] {
            assert_eq!(ov.observe(Some(a), true, false), FuelOverdue::Eat);
        }
        // Nor can any of them latch a marker of their own.
        let mut ov2 = FuelOverdueTracker::new();
        for a in [
            Alert::Distance(1_000),
            Alert::Time(60),
            Alert::PaceFast,
            Alert::PaceSlow,
        ] {
            assert_eq!(ov2.observe(Some(a), true, false), FuelOverdue::None);
        }
    }

    #[test]
    fn fuel_overdue_latches_and_survives_the_banner_ttl() {
        let mut ov = FuelOverdueTracker::new();
        // Nothing has fired yet.
        assert_eq!(ov.observe(None, true, false), FuelOverdue::None);
        // The drink reminder fires — its banner is on screen this frame.
        assert_eq!(
            ov.observe(Some(Alert::Drink), true, false),
            FuelOverdue::Drink
        );
        // Long after the 8 s banner has cleared, the standing marker holds.
        for _ in 0..100 {
            assert_eq!(ov.observe(None, true, false), FuelOverdue::Drink);
        }
    }

    #[test]
    fn fuel_overdue_tracks_both_arms_independently() {
        let mut ov = FuelOverdueTracker::new();
        assert_eq!(
            ov.observe(Some(Alert::Drink), true, false),
            FuelOverdue::Drink
        );
        // The eat reminder fires later; both are now standing.
        assert_eq!(ov.observe(Some(Alert::Eat), true, false), FuelOverdue::Both);
        // Both persist through frames with no banner.
        assert_eq!(ov.observe(None, true, false), FuelOverdue::Both);
    }

    #[test]
    fn fuel_overdue_clears_on_acknowledge_then_relatches() {
        let mut ov = FuelOverdueTracker::new();
        ov.observe(Some(Alert::Drink), true, false);
        // The runner opens the Fuel page (acknowledged) — the marker clears.
        assert_eq!(ov.observe(None, true, true), FuelOverdue::None);
        // It stays clear while nothing new fires.
        assert_eq!(ov.observe(None, true, false), FuelOverdue::None);
        // The next interval's reminder re-latches it.
        assert_eq!(
            ov.observe(Some(Alert::Drink), true, false),
            FuelOverdue::Drink
        );
    }

    #[test]
    fn fuel_overdue_clears_when_the_run_ends_and_never_latches_between_runs() {
        let mut ov = FuelOverdueTracker::new();
        ov.observe(Some(Alert::Eat), true, false);
        // Run ends (Idle / Finished -> run_active false): the marker clears.
        assert_eq!(ov.observe(None, false, false), FuelOverdue::None);
        // A banner outside a run can never latch the marker.
        assert_eq!(
            ov.observe(Some(Alert::Drink), false, false),
            FuelOverdue::None
        );
    }

    #[test]
    fn zone_banner_leaves_the_fuel_overdue_marker_untouched() {
        let mut ov = FuelOverdueTracker::new();
        assert_eq!(
            ov.observe(Some(Alert::Drink), true, false),
            FuelOverdue::Drink
        );
        // A superseding zone banner takes the slot; the standing marker holds.
        assert_eq!(
            ov.observe(Some(Alert::ZoneAbove(5)), true, false),
            FuelOverdue::Drink
        );
        assert_eq!(ov.observe(None, true, false), FuelOverdue::Drink);
        // A zone banner with no prior fuel reminder latches nothing.
        let mut ov2 = FuelOverdueTracker::new();
        assert_eq!(
            ov2.observe(Some(Alert::ZoneAbove(4)), true, false),
            FuelOverdue::None
        );
    }

    #[test]
    fn engine_fired_reminder_stays_overdue_past_the_engine_ttl() {
        // Drive the real engine and feed its published banner into the tracker,
        // so the "survives the TTL" property is checked end-to-end, not off a
        // synthetic banner stream.
        let mut e = AlertEngine::new();
        let mut ov = FuelOverdueTracker::new();
        assert_eq!(e.on_update(&rec(899), None, 899), None);
        assert_eq!(ov.observe(None, true, false), FuelOverdue::None);

        let fired = e.on_update(&rec(900), None, 900);
        assert_eq!(fired, Some(Alert::Drink));
        assert_eq!(ov.observe(fired, true, false), FuelOverdue::Drink);

        // The engine banner expires at 900 + ALERT_TTL_S; the marker does not.
        let expired = e.on_update(&rec(900 + ALERT_TTL_S), None, 900 + ALERT_TTL_S);
        assert_eq!(expired, None);
        assert_eq!(ov.observe(expired, true, false), FuelOverdue::Drink);
    }

    // ─────────── workout banners ───────────

    fn wv(transition_seq: u16, ending_seq: u16, complete: bool) -> crate::workout::WorkoutView {
        use crate::workout::{PaceAdherence, WorkoutStepKind, WorkoutView};
        WorkoutView {
            step_index: 0,
            step_total: 2,
            kind: WorkoutStepKind::Rep,
            rep_index: 1,
            rep_total: 6,
            duration_based: false,
            target_distance_m: 400,
            target_duration_s: 0,
            target_pace_s_per_km: 240,
            step_distance_m: 0,
            step_elapsed_s: 0,
            remaining_m: 400,
            remaining_s: 0,
            progress_permille: 0,
            step_pace_s_per_km: None,
            adherence: PaceAdherence::OnPace,
            next: None,
            complete,
            rollup: None,
            transition_seq,
            ending_seq,
        }
    }

    fn rec_workout(view: crate::workout::WorkoutView, moving_s: u32) -> Snapshot {
        Snapshot {
            workout: Some(view),
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_workout_transition_fires_the_step_banner_once() {
        let mut e = AlertEngine::new();
        let fired = e.on_update(&rec_workout(wv(1, 0, false), 10), None, 10);
        assert_eq!(
            fired,
            Some(Alert::WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 1,
                rep_total: 6
            })
        );
        // The same seq past the TTL is not a fresh edge.
        let expired = e.on_update(
            &rec_workout(wv(1, 0, false), 10 + ALERT_TTL_S),
            None,
            10 + ALERT_TTL_S,
        );
        assert_eq!(expired, None);
        // The next seq is.
        let again = e.on_update(
            &rec_workout(wv(2, 0, false), 20 + ALERT_TTL_S),
            None,
            20 + ALERT_TTL_S,
        );
        assert!(matches!(again, Some(Alert::WorkoutStep { .. })));
    }

    #[test]
    fn a_workout_transition_fires_while_auto_paused() {
        // A timed recovery ends while the runner stands at the rail: the next
        // rep's entry banner must not be gated on Recording.
        let mut e = AlertEngine::new();
        // Enter the run first (the engine treats the first in-run update as
        // the run start), then pause.
        assert_eq!(
            e.on_update(&rec_workout(wv(1, 0, false), 1), None, 1),
            Some(Alert::WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 1,
                rep_total: 6
            })
        );
        let paused = Snapshot {
            state: RecordState::Paused,
            ..rec_workout(wv(2, 0, false), 1)
        };
        let fired = e.on_update(&paused, None, 2 + ALERT_TTL_S);
        assert!(matches!(fired, Some(Alert::WorkoutStep { .. })));
    }

    #[test]
    fn a_zone_banner_blocks_a_workout_edge_and_the_edge_is_dropped() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(2));
        let cutoffs = zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM);
        let hot = Snapshot {
            zone_cutoffs: cutoffs,
            ..rec_workout(wv(0, 0, false), 10)
        };
        assert!(matches!(
            e.on_update(&hot, Some(180), 10),
            Some((Alert::ZoneAbove(_))),
        ));
        // The transition lands while the zone banner holds the slot: dropped.
        let hot_step = Snapshot {
            zone_cutoffs: cutoffs,
            ..rec_workout(wv(1, 0, false), 11)
        };
        assert!(matches!(
            e.on_update(&hot_step, Some(180), 11),
            Some(Alert::ZoneAbove(_))
        ));
        // Past the TTL the seq was already consumed — no stale step banner.
        let later = Snapshot {
            zone_cutoffs: cutoffs,
            ..rec_workout(wv(1, 0, false), 11 + ALERT_TTL_S)
        };
        assert_eq!(e.on_update(&later, None, 11 + ALERT_TTL_S), None);
    }

    #[test]
    fn a_workout_banner_displaces_a_fuel_reminder_which_requeues() {
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&rec_workout(wv(0, 0, false), 900), None, 900),
            Some(Alert::Drink)
        );
        let fired = e.on_update(&rec_workout(wv(1, 0, false), 901), None, 901);
        assert!(matches!(fired, Some(Alert::WorkoutStep { .. })));
        // Once the step banner expires the displaced reminder returns.
        let requeued = e.on_update(
            &rec_workout(wv(1, 0, false), 901 + ALERT_TTL_S),
            None,
            901 + ALERT_TTL_S,
        );
        assert_eq!(requeued, Some(Alert::Drink));
    }

    #[test]
    fn the_ending_warning_and_done_each_fire_once() {
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&rec_workout(wv(1, 0, false), 1), None, 1)
                .is_some(),
            true
        );
        let ending = e.on_update(
            &rec_workout(wv(1, 1, false), 1 + ALERT_TTL_S),
            None,
            1 + ALERT_TTL_S,
        );
        assert_eq!(ending, Some(Alert::WorkoutEnding));
        let done_at = 2 * ALERT_TTL_S + 2;
        let done = e.on_update(&rec_workout(wv(1, 1, true), done_at), None, done_at);
        assert_eq!(done, Some(Alert::WorkoutDone));
        // Complete stays complete; DONE does not refire.
        let later = e.on_update(
            &rec_workout(wv(1, 1, true), done_at + ALERT_TTL_S),
            None,
            done_at + ALERT_TTL_S,
        );
        assert_eq!(later, None);
    }

    #[test]
    fn workout_banner_text_fits_the_band() {
        use crate::workout::WorkoutStepKind;
        let step = |kind, rep_index, rep_total| Alert::WorkoutStep {
            kind,
            rep_index,
            rep_total,
        };
        assert_eq!(
            banner(step(WorkoutStepKind::Rep, 3, 6)).as_str(),
            "! REP 3/6"
        );
        // A count the ten-glyph band can't fit degrades to the index alone —
        // never a truncated "! REP 12/2" that reads as a different count.
        assert_eq!(
            banner(step(WorkoutStepKind::Rep, 12, 20)).as_str(),
            "! REP 12"
        );
        assert_eq!(
            banner(step(WorkoutStepKind::Walk, 3, 7)).as_str(),
            "! WALK 3/7"
        );
        assert_eq!(
            banner(step(WorkoutStepKind::Recovery, 3, 5)).as_str(),
            "! RECOVER"
        );
        assert_eq!(
            banner(step(WorkoutStepKind::Warmup, 0, 0)).as_str(),
            "! WARMUP"
        );
        assert_eq!(
            banner(step(WorkoutStepKind::Cooldown, 0, 0)).as_str(),
            "! COOLDOWN"
        );
        assert_eq!(banner(Alert::WorkoutEnding).as_str(), "! STEP END");
        assert_eq!(banner(Alert::WorkoutDone).as_str(), "! WKT DONE");
        for alert in [
            step(WorkoutStepKind::Rep, 255, 255),
            step(WorkoutStepKind::Recovery, 255, 255),
            Alert::WorkoutEnding,
            Alert::WorkoutDone,
        ] {
            assert!(banner(alert).len() <= 10, "{alert:?} overflows the band");
        }
    }
}
