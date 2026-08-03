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
//! 2. **The backyard corral whistle** (§ 372) — the only arm here that is not
//!    about the runner's body or their kit. Missing the bell ends the race
//!    outright, with nothing left to correct afterwards, so it yields to a zone
//!    banner and to nothing else. It is a milestone in kind, though, so a
//!    blocked one is dropped rather than owed: `3 MIN` shown at 1:40 is a lie
//!    about the clock, and the Backyard page carries the live countdown anyway.
//! 3. **The structured workout's edges** ([`crate::workout`], § 354) and **the
//!    waypoint hold's answer** ([`crate::waypoints`], § 382) — a step
//!    transition, its end-of-step warning, the plan completing, and the saved
//!    or refused mark. One rung, because both are the runner's own action
//!    answering at the one moment it can be acted on, and both yield to a zone
//!    banner and to the bell and to nothing else. Milestones in kind like the
//!    whistle, so a blocked one is dropped rather than owed: a stale `! REP 3`
//!    is worse than none, a confirmation shown late confirms the wrong thing,
//!    and the Workout and Waypoint pages carry the live truth regardless.
//! 4. **Pace** — the same correct-it-now class as the zone alert two rungs
//!    down, because pace is a proxy for the effort HR measures directly. It
//!    supersedes a fuel reminder but never a zone banner, a corral whistle, a
//!    workout edge or a waypoint answer; blocked by one, it stays armed and
//!    un-cooled so it retries while the excursion lasts, rather than being
//!    swallowed. That asymmetry is *why* it sits below the dropped arms above
//!    it — the excursion can come back, their one banner cannot.
//! 5. **Off-course** — the nav task's 40 m / 20 m hysteresis latched. Until
//!    2026-07-31 that verdict lived only as a steady banner over the Nav
//!    page's own map panel; a runner parked on any of the other forty pages
//!    learned about a wrong turn only by paging there. The engine
//!    edge-detects the already-de-flapped latch, so it fires once per
//!    excursion by construction, and it is **re-queued** when displaced:
//!    every unseen minute banks wrong-way distance. Its release fires the
//!    `ON COURSE` affirmation down in the dropped class.
//! 6. **Cutoff** — the projection on the CUT page fell to `BEHIND`: at the
//!    current pace the runner misses the next cutoff. Like the corral whistle
//!    it warns of the race ending, but it is a *projection off recent pace*,
//!    not the race director's own clock, so it ranks with the correct-it-now
//!    pair above rather than beside the bell. It fires once per excursion —
//!    re-arming only on a MEASURED recovery to `ON` or `TIGHT`, never on
//!    `UNKNOWN` (a stale fix is the watch losing sight of the runner, not the
//!    runner catching up) — and it is **re-queued** when displaced: there is
//!    no later reminder, and the thing it warns of only gets worse.
//! 7. **Course-push rejected** — the ble task refused a course push (bad
//!    chunk, failed CRC, undecodable frame) and `state::COURSE` kept the
//!    stale course. Race-critical navigation state: the runner watched their
//!    phone say "sent" and now trusts a course the watch never accepted, and
//!    the mistake surfaces at the next fork — minutes away, not the hour a
//!    front allows — so it sits under the cutoff (which warns the race is
//!    being lost *now*) and above storm. **Re-queued** when displaced: no
//!    later reminder exists, and no page carries the rejection.
//! 8. **Storm** ([`crate::storm`], § 376) — the first arm on this engine about
//!    the world rather than the runner, and it sits here because of *when* the
//!    thing it warns of arrives. A zone excursion, a corral bell, a workout
//!    step and a pace drift all want a decision inside seconds; a front
//!    measured over three
//!    hours wants one inside the next hour, so it yields to all of them. But it
//!    fires perhaps once in a race and there is no later reminder, so it is in
//!    the **re-queued** class rather than the dropped one — ahead of fuel: a
//!    missed gel is re-offered a cadence later, a missed front is not. It rides
//!    the run's own alert slot, so like every other arm it is silent between
//!    runs.
//! 9. **Run lost** — a flash eviction destroyed a finished run the phone had
//!    never pulled: hours of a race, gone forever, and honesty demands the
//!    wrist say so rather than a `warn!` down a cable. It asks for no
//!    decision — the data is already gone — so it sits at the bottom of the
//!    re-queued class, below every arm that still has something to act on;
//!    above fuel only because a reminder comes round again and this never
//!    does. **Re-queued** when displaced, for exactly that reason.
//! 10. **Track resolution dropped** — the flash slot filled and
//!     [`crate::run_store::RunWriter::push_point_bounded`] thinned the staged
//!     track in place, so the record the runner is creating is permanently
//!     coarser than it was. It asks even less of them than the lost run does —
//!     nothing was destroyed, the whole run is still represented, at half the
//!     fidelity again — so it takes the re-queued class's bottom rung, under
//!     the loss notice. It is above fuel for the one reason the loss is: a gel
//!     comes round a cadence later, a halving is announced once or never.
//!     **Re-queued** rather than dropped, which is where it parts company with
//!     the signal-void pair below: the `AUTO` tag rides the state tag on
//!     *every* page, so a swallowed GPS LOST loses only the announcement,
//!     whereas the thinning factor lives on row 7 of the Distance page alone
//!     (the Pace page spends that row on GAP) — which is the blind spot the
//!     arm exists to close. It carries no factor precisely so a queued banner
//!     cannot go stale: `1/2` released after the slot has thinned to `1/4`
//!     would contradict the page it is sending the runner to.
//! 11. **Eat**, then **Drink** — a reminder can wait eight seconds, so these
//!     only take a free slot; a superseded one **re-queues** (fuel is the
//!     ultra-critical reminder, it must never be silently dropped) and queued
//!     reminders promote eat-before-drink when a slot frees.
//! 12. **GPS lost / GPS back**, then **Back-on-course**, then **Timer**, then
//!     **Distance**, then **Time** — milestones, and the only
//!     arms that are *dropped* rather than queued when the slot is busy. A
//!     milestone banner is meaningful only at the moment it is reached; showing
//!     "5.0 KM" once the runner is at 5.4 km is worse than not showing it, and
//!     unlike fuel there is nothing left to act on later — the totals are on the
//!     page. The [`crate::timers`] expiry leads the group because it is the one
//!     the runner set themselves, and the two automatic ones tie-break on
//!     distance, which is what the race is measured in. The timer sits *below*
//!     fuel deliberately: a missed timer banner costs nothing recoverable (the
//!     Timer page counts the overrun up), whereas §214 says a missed gel is the
//!     one reminder that must never be silently dropped — and below the corral
//!     whistle for the same asymmetry, one rung sharper. The signal-void pair
//!     (§367) heads the group — distance not accruing while the runner moves
//!     is the costliest thing in it, and the AUTO tag carries the persistent
//!     truth so a swallowed banner loses only the announcement — with the
//!     `ON COURSE` affirmation next: for a runner who just corrected a wrong
//!     turn by feel it is the answer to a live question, where the milestones
//!     are wallpaper — but it is still in the dropped class, because a stale
//!     all-clear shown after the runner drifted off again is a lie the Nav
//!     page would contradict.
//!
//! The order the arms are *evaluated* in [`AlertEngine::on_update`] is
//! load-bearing, not cosmetic. Each arm refuses a higher rung by inspecting the
//! slot, and the slot can only hold what has already run — so an arm evaluated
//! ahead of the one that outranks it sees a free slot, fires, banks its
//! once-per-excursion state, and is then overwritten before the caller reads a
//! thing. The banner never reaches a frame and (unlike fuel) is not re-queued,
//! so a pace excursion collided with a whistle used to be lost for the whole
//! excursion. Two rules follow, and both are load-bearing: the blocks run in
//! ladder order, and every arm's `outranked` set names *everything* above it.
//!
//! Display-only by design: the DK has no vibration motor, and alerts are an
//! L4 auxiliary — the engine is pure and fed *after* the recorder updates, so
//! nothing here can disturb the recording math.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator.

use core::fmt::Write;

use crate::ble_sync::PushKind;
use crate::cutoff_eta::CutoffEtaStatus;
use crate::hr_zones;
use crate::record::{RecordState, Snapshot};
use crate::storm::StormTrend;
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
    /// The runner's countdown reached zero ([`crate::timers`], §375). Carries
    /// nothing: the duration is on the Timer page and the banner's whole job is
    /// to say *now*.
    TimerDone,
    /// A backyard corral whistle (§ 372) — the minutes left to the bell,
    /// one of [`crate::backyard::BELL_WARNING_MIN`].
    BackyardBell(u8),
    /// The sea-level-reduced pressure has fallen past the storm threshold over
    /// the trend window ([`crate::storm`], § 376). Carries nothing: the number
    /// is on the Storm page and a ten-cell banner cannot say `-5.2 HPA/3H`
    /// legibly anyway — the banner's job is to send the runner to the page.
    Storm,
    /// The next-cutoff projection fell to [`CutoffEtaStatus::Behind`] — at the
    /// current pace the runner misses the cutoff. Carries nothing: the margin
    /// and the pace still sufficient are on the CUT page, and the banner's job
    /// is to send the runner there while there is still time to act.
    CutoffBehind,
    /// The nav task's off-course hysteresis latched
    /// ([`Snapshot::nav_off_course`]) — until now that verdict rendered only
    /// over the Nav page's own map panel, invisible from the other forty
    /// pages. Carries nothing: the offset and the breadcrumb are on the Nav
    /// page, and the banner's job is to send the runner there before the
    /// wrong trail banks another kilometre.
    OffCourse,
    /// The latch released — a live projection put the runner back on the
    /// line. The one affirmation on this engine, and the only banner without
    /// the `!` prefix: it asks for nothing, it closes the loop the OFF CRS
    /// banner opened, so a runner who corrected by feel knows it worked
    /// without paging to Nav.
    BackOnCourse,
    /// BTN5's hold saved a waypoint ([`Snapshot::waypoint_mark_seq`], §357).
    /// The mark itself was screen-silent — persist + a RAM slot — so the one
    /// deliberate mid-run press with a durable result gave no answer. An
    /// affirmation like [`Alert::BackOnCourse`]: no `!` prefix.
    WaypointMarked,
    /// BTN5's hold marked nothing — no position anchor yet
    /// ([`Snapshot::waypoint_refuse_seq`]). The label names the cause, not
    /// the failure: the fix is to wait for one.
    WaypointNoFix,
    /// The recorder auto-paused because the fixes dried up
    /// ([`Snapshot::signal_lost`], §367) — until now only the corner tag
    /// flipped to `AUTO`, a change a heads-down runner reads minutes later.
    /// Distance is not accruing; the runner may still be moving.
    SignalLost,
    /// Fixes returned and the recorder resumed. An affirmation like
    /// [`Alert::BackOnCourse`]: no `!` prefix, it closes the loop GPS LOST
    /// opened.
    SignalBack,
    /// A flash eviction destroyed a finished run the phone had never pulled
    /// ([`Snapshot::run_lost_seq`]). Carries nothing: there is nothing left
    /// to carry — the run's coordinates and heart rates are gone forever,
    /// and the banner's whole job is to say so instead of softening it.
    RunLost,
    /// The radio task refused a phone push ([`Snapshot::push_outcome`]) — the
    /// value on the watch is STILL THE OLD ONE, whichever of the five it was.
    /// The label conveys rejection, not vague error: the runner's phone said
    /// "sent", and the next fork (or the next interval, or the next cut-off)
    /// is where believing it gets expensive. Carries the kind because the five
    /// pushes fail independently and "something didn't land" is not actionable
    /// — a refused course and a refused roadbook want different re-pushes. An
    /// accepted push needs no banner of its own: the pages re-announce what
    /// they hold, and a confirmation banner would teach runners to wait for
    /// one that failure also never showed.
    PushRejected(PushKind),
    /// The flash slot filled and [`Snapshot::track_thinning`] rose: the staged
    /// track was thinned in place, so the whole run is still recorded but at a
    /// coarser resolution than the runner was last told. Carries nothing — the
    /// factor is on row 7 of the Distance page, and a queued banner naming
    /// `1/2` after the slot has thinned to `1/4` would contradict it.
    TrackThinned,
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
        // Not "ALARM": nothing on this device can wake anyone, and the word
        // would promise exactly that (§375).
        Alert::TimerDone => write!(b, "! TIME UP"),
        // `MIN` rather than a bare number: every other banner is a word or a
        // unit-tagged value, and `! 3` on a wrist at hour 30 says nothing.
        Alert::BackyardBell(min) => write!(b, "! {} MIN", min.min(9)),
        Alert::Storm => write!(b, "! STORM"),
        Alert::CutoffBehind => write!(b, "! CUTOFF"),
        // CRS is the course wire frame's own abbreviation (`CRS1`) — the full
        // phrase overflows the ten-cell band the `!` convention leaves.
        Alert::OffCourse => write!(b, "! OFF CRS"),
        // The all-clear fits whole, and drops the `!` deliberately: on this
        // face `!` means act, and an affirmation asks for nothing.
        Alert::BackOnCourse => write!(b, "ON COURSE"),
        Alert::WaypointMarked => write!(b, "WPT SAVED"),
        Alert::WaypointNoFix => write!(b, "! NO FIX"),
        Alert::SignalLost => write!(b, "! GPS LOST"),
        Alert::SignalBack => write!(b, "GPS BACK"),
        // LOST, not "dropped" or "evicted": the data is gone forever and the
        // word must not soften it.
        Alert::RunLost => write!(b, "! RUN LOST"),
        // FAIL, not a vague error word: the push was rejected and the watch
        // kept the old value. The kind is its wire frame's own abbreviation,
        // as CRS is on the OFF CRS banner — and all five are three letters, so
        // the phrase fills the ten-cell band exactly whichever push failed.
        Alert::PushRejected(kind) => write!(b, "! {} FAIL", kind.abbrev()),
        // TRK, not TRACK: `! TRACK RES` is eleven glyphs against the band's
        // ten, and abbreviating the noun to keep the phrase's shape is what
        // `! OFF CRS` already does.
        Alert::TrackThinned => write!(b, "! TRK RES"),
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
    /// The last [`crate::timers::TimerView::expiry_seq`] announced. Deliberately
    /// NOT cleared by [`Self::reset`]: the instrument outlives the run, so a
    /// countdown that expired during one run must not re-announce itself at the
    /// start of the next. It is configuration-lifetime, like the intervals.
    last_timer_expiry_seq: u16,
    /// The backyard whistle counter last seen ([`crate::backyard::BackyardView`]'s
    /// monotonic seq). A blocked whistle is dropped, not owed — the milestone
    /// rule: `3 MIN` shown at 1:40 is worse than nothing, and the page carries
    /// the countdown regardless.
    last_backyard_warning_seq: u16,
    /// Whether the storm arm is armed at all. `false` = off, the hardware
    /// default until a `SET1` push arms it.
    storm_alert: bool,
    /// Set while the trend is not a storm; a fire disarms it until a MEASURED
    /// trend says the front has passed — the once-per-front hysteresis. There
    /// is deliberately no cooldown beside it: unlike a BPM crossing a zone
    /// boundary, the signal is already hysteretic
    /// ([`crate::storm::STORM_CLEAR_FRACTION`]) and moves over hours, so a
    /// second timer would guard nothing.
    storm_armed: bool,
    /// The on-screen alert and the uptime it was raised at.
    active: Option<(Alert, u32)>,
    pending_drink: bool,
    pending_eat: bool,
    /// A raised storm waiting for the slot. Like [`Self::storm_armed`] and
    /// unlike the fuel pair, it is NOT cleared by [`Self::reset`]: the weather
    /// outlives the run, so a front raised between runs is still owed when the
    /// next one starts — the same reasoning [`Self::last_timer_expiry_seq`]
    /// carries in the opposite direction.
    pending_storm: bool,
    /// Set while the cutoff projection is not `Behind`; a fire disarms it
    /// until a MEASURED status (`On` / `Tight`) says the runner recovered —
    /// the once-per-excursion hysteresis. `Unknown` neither fires nor re-arms:
    /// a stale fix is the watch losing sight of the runner, not the runner
    /// catching up, and re-arming on it would turn one canyon into two banners
    /// (the same reasoning [`Self::storm_armed`] carries).
    cutoff_armed: bool,
    /// A raised cutoff warning waiting for the slot. Cleared by
    /// [`Self::reset`], unlike the storm pair: a cutoff is a property of the
    /// run's course, not of the world between runs.
    pending_cutoff: bool,
    /// Whether the last MEASURED [`Snapshot::nav_off_course`] said off-course
    /// — the edge detector for both course banners. A `None` sample (no
    /// course, no projection yet) clears it silently: losing the projection
    /// is absence of knowledge, so it must neither fire the recovery banner
    /// nor leave a stale excursion armed against a freshly-pushed course.
    was_off_course: bool,
    /// A raised off-course warning waiting for the slot. Cleared by
    /// [`Self::reset`] with the same run-scoped reasoning as the cutoff pair.
    pending_off_course: bool,
    /// The last waypoint mark / refuse counters seen
    /// ([`Snapshot::waypoint_mark_seq`] / [`Snapshot::waypoint_refuse_seq`]).
    /// `None` = not yet baselined: the first sample of a run adopts the
    /// counters without firing, so marks banked before this run (or before a
    /// reboot) can't replay as a banner at the start line.
    last_waypoint_mark_seq: Option<u8>,
    last_waypoint_refuse_seq: Option<u8>,
    /// The last [`Snapshot::run_lost_seq`] seen, with the waypoint pair's
    /// `None`-baseline: an eviction taken by a previous run's commit must not
    /// replay as a banner at this run's start line — between runs the idle
    /// face's unsynced-pressure row carries the standing truth.
    last_run_lost_seq: Option<u8>,
    /// A raised run-lost notice waiting for the slot. Re-queued when
    /// displaced — the loss is permanent and no page carries it mid-run, so
    /// dropping it would return the event to the silence it came from.
    /// Cleared by [`Self::reset`]: between runs the idle surfaces own the
    /// story.
    pending_run_lost: bool,
    /// The last [`Snapshot::push_outcome`] sequence seen, same `None`-baseline:
    /// a push that resolved while the watch sat idle must not replay mid-race.
    /// The sequence moves on an ACCEPTED push too, which this adopts in
    /// silence — only a refusal raises anything.
    last_push_seq: Option<u8>,
    /// A raised push-rejection warning waiting for the slot, and which push it
    /// was. Re-queued when displaced — there is no later reminder, and the
    /// runner is running against a value they believe was replaced. Cleared by
    /// [`Self::reset`] with the cutoff pair's run-scoped reasoning.
    pending_push_reject: Option<PushKind>,
    /// Whether the last sample said the fixes had dried up — the edge
    /// detector for the GPS LOST / GPS BACK pair. Plain, not tri-state:
    /// unlike the nav projection, `signal_lost` is always meaningful during
    /// a run, and it is false at the start line.
    was_signal_lost: bool,
    /// The last [`Snapshot::track_thinning`] seen — the edge detector for the
    /// track-resolution notice. Plain rather than the waypoint pair's
    /// `None`-baseline, for [`Self::was_signal_lost`]'s reason: this is not a
    /// wrapping counter carrying pre-run history but a state
    /// [`crate::record::Recorder::start`] resets, so it is provably 1 at the
    /// start line.
    last_track_thinning: u8,
    /// A raised track-resolution notice waiting for the slot. Re-queued when
    /// displaced — row 7 of the Distance page is the only one of the
    /// forty-one that carries the factor, so a dropped banner is the
    /// announcement gone. Cleared by [`Self::reset`]: decimation is a property
    /// of THIS run's flash slot, not of the world between runs.
    pending_track_thinned: bool,
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
            last_timer_expiry_seq: 0,
            last_backyard_warning_seq: 0,
            storm_alert: false,
            storm_armed: true,
            active: None,
            pending_drink: false,
            pending_eat: false,
            pending_storm: false,
            cutoff_armed: true,
            pending_cutoff: false,
            was_off_course: false,
            pending_off_course: false,
            last_waypoint_mark_seq: None,
            last_waypoint_refuse_seq: None,
            last_run_lost_seq: None,
            pending_run_lost: false,
            last_push_seq: None,
            pending_push_reject: None,
            was_signal_lost: false,
            last_track_thinning: 1,
            pending_track_thinned: false,
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

    /// The armed zone ceiling, if any — read back by the record task to
    /// mirror the arm into [`crate::record::Snapshot`], so the Zones page can
    /// say whether the over-effort alert is armed at all. The engine stays
    /// the single owner: only a value [`Self::set_zone_ceiling`] accepted can
    /// ever be mirrored, so the page and the alert cannot drift.
    pub const fn zone_ceiling(&self) -> Option<u8> {
        self.zone_ceiling
    }

    /// The armed pace band, if any — the Pace page's mirror, same contract as
    /// [`Self::zone_ceiling`].
    pub const fn pace_band(&self) -> Option<(u32, u32)> {
        self.pace_band
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

    /// Arm or disarm the storm banner. Off by default — the watch never warns
    /// about the weather until a runner asks it to, because the arm's whole
    /// value is that it is rare.
    ///
    /// A bool rather than a threshold: the threshold lives with the
    /// measurement ([`crate::storm::StormTracker::set_fall_threshold_hpa`],
    /// which is where its plausibility guard and its release hysteresis are),
    /// so this engine only ever reads a verdict it did not compute — the same
    /// shape the workout, timer and backyard arms have.
    pub fn set_storm_alert(&mut self, on: bool) {
        self.storm_alert = on;
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
        }

        // The corral whistles (§ 372). The race director's own 3/2/1 warnings,
        // and the one alert on this engine that is not about the runner's body
        // or their kit: missing the bell ends the race outright, so it outranks
        // every milestone and every reminder and is blocked only by a zone
        // banner — the one thing an ultra runner can afford even less to lose.
        // Not gated on `Recording`: a runner standing in the corral is exactly
        // who the whistle is for, which is why it sits between the two gated
        // blocks rather than inside either.
        //
        // It sits above §375's `timer_due` for the same reason it sits above the
        // milestones: `timer_due` is only a flag until the tail of this function,
        // so a whistle that takes the slot here drops the countdown's banner —
        // which the Timer page's own count-up survives, and a missed bell does
        // not. Fuel is displaced rather than dropped, per `take_slot`.
        if let Some(b) = snap.backyard {
            if b.warning_seq != self.last_backyard_warning_seq {
                self.last_backyard_warning_seq = b.warning_seq;
                if b.warning_min > 0 && !matches!(self.active, Some((Alert::ZoneAbove(_), _))) {
                    self.take_slot(Alert::BackyardBell(b.warning_min), uptime_s);
                }
            }
        } else {
            self.last_backyard_warning_seq = 0;
        }

        // Workout edges — the step transition, the end-of-step warning, and
        // completion, read off the snapshot's monotonic counters. NOT gated on
        // Recording: a timed recovery legitimately advances through an
        // auto-pause (a standing rest is that step working as intended), and
        // the next rep's entry banner is exactly what the runner needs then.
        // Two rungs under the zone ceiling: a workout banner takes the slot
        // from anything below (a displaced fuel reminder re-queues) but never
        // from a zone banner or a corral whistle — and a blocked edge is
        // dropped, not owed, the milestone rule: a stale "REP 3" is worse than
        // none, and the page carries the current step regardless.
        match snap.workout {
            Some(w) => {
                let outranked = matches!(
                    self.active,
                    Some((Alert::ZoneAbove(_) | Alert::BackyardBell(_), _))
                );
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

        // Waypoint feedback (§357). BTN5's hold is the one deliberate mid-run
        // press with a durable result, and until now its answer was a flash
        // write and a defmt line — invisible on the wrist that asked. Both
        // counters get the workout edges' precedence (blocked only by a zone
        // banner or the corral whistle, displaced fuel re-queues) because the
        // runner is looking at the screen at exactly this moment; a blocked
        // one is dropped, not owed — a confirmation shown late confirms the
        // wrong thing. The first sample after a reset baselines without
        // firing, so marks banked before this run can't replay at the start
        // line.
        {
            let outranked = matches!(
                self.active,
                Some((Alert::ZoneAbove(_) | Alert::BackyardBell(_), _))
            );
            match self.last_waypoint_mark_seq {
                None => self.last_waypoint_mark_seq = Some(snap.waypoint_mark_seq),
                Some(last) if snap.waypoint_mark_seq != last => {
                    self.last_waypoint_mark_seq = Some(snap.waypoint_mark_seq);
                    if !outranked {
                        self.take_slot(Alert::WaypointMarked, uptime_s);
                    }
                }
                Some(_) => {}
            }
            match self.last_waypoint_refuse_seq {
                None => self.last_waypoint_refuse_seq = Some(snap.waypoint_refuse_seq),
                Some(last) if snap.waypoint_refuse_seq != last => {
                    self.last_waypoint_refuse_seq = Some(snap.waypoint_refuse_seq);
                    if !outranked {
                        self.take_slot(Alert::WaypointNoFix, uptime_s);
                    }
                }
                Some(_) => {}
            }
        }

        // Pace band, the last of the correct-it-now arms and so the last one
        // evaluated: it may take the slot off a fuel reminder (which re-queues)
        // or a milestone, but every arm above it blocks it — and a blocked
        // excursion neither disarms nor stamps the cooldown, so it fires on a
        // later tick while the runner is still outside the band instead of being
        // swallowed. Gated on `Recording` like the zone ceiling above, for the
        // same reason.
        //
        // The waypoint pair is in that list because a confirmation is *dropped*
        // when blocked while an excursion can still retry, so letting pace win
        // would lose the one of the two that cannot come back.
        if snap.state == RecordState::Recording {
            if let (Some((fast, slow)), Some(pace)) = (self.pace_band, snap.current_pace_s_per_km) {
                if pace < fast || pace > slow {
                    let cooled = self
                        .last_pace_fire_s
                        .is_none_or(|t| uptime_s.saturating_sub(t) >= PACE_ALERT_COOLDOWN_S);
                    let outranked = matches!(
                        self.active,
                        Some((
                            Alert::ZoneAbove(_)
                                | Alert::BackyardBell(_)
                                | Alert::WorkoutStep { .. }
                                | Alert::WorkoutEnding
                                | Alert::WorkoutDone
                                | Alert::WaypointMarked
                                | Alert::WaypointNoFix,
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

        // The run-lost and push-verdict counters, on the waypoint pair's
        // seam: a wrapping seq the app bumps, edge-detected here, with the
        // first sample of a run adopting the counter so pre-run history can't
        // replay at the start line. Both set pending flags rather than taking
        // the slot — the precedence chain at the tail places them in the
        // re-queued class, so neither can be swallowed by a busy slot the way
        // the defmt warns they replace were swallowed by the missing cable.
        //
        // The push seam carries a KIND as well as a seq because all five
        // phone→watch pushes share it, and it moves on acceptance too — which
        // is adopted silently here, so only the phone's half of the record
        // reads a successful push.
        match self.last_run_lost_seq {
            None => self.last_run_lost_seq = Some(snap.run_lost_seq),
            Some(last) if snap.run_lost_seq != last => {
                self.last_run_lost_seq = Some(snap.run_lost_seq);
                self.pending_run_lost = true;
            }
            Some(_) => {}
        }
        match self.last_push_seq {
            None => self.last_push_seq = Some(snap.push_outcome.seq),
            Some(last) if snap.push_outcome.seq != last => {
                self.last_push_seq = Some(snap.push_outcome.seq);
                if !snap.push_outcome.accepted {
                    self.pending_push_reject = Some(snap.push_outcome.kind);
                }
            }
            Some(_) => {}
        }

        // The timer edge is consumed whether or not it can be shown — the
        // milestone rule, and the reason it is safe here: the Timer page counts
        // the overrun up, so a dropped banner loses nothing the runner cannot
        // still read. Not gated on Recording: a countdown set at an aid station
        // is running precisely while the recorder is paused.
        let mut timer_due = false;
        if let Some(t) = snap.timer {
            if t.expiry_seq != 0 && t.expiry_seq != self.last_timer_expiry_seq {
                self.last_timer_expiry_seq = t.expiry_seq;
                timer_due = true;
            }
        }

        // The signal-void pair (§367). The recorder's own auto-pause verdict:
        // the face's corner tag flips to AUTO, but a tag is a state, not an
        // event — a heads-down runner learns about it minutes later, with a
        // kilometre unrecorded. Both edges land in the dropped class at its
        // head: the tag carries the truth persistently, so a banner the slot
        // swallows loses only the announcement — and a stale GPS LOST shown
        // after the fixes returned would be the banner lying about the tag.
        let mut signal_lost_due = false;
        let mut signal_back_due = false;
        if snap.signal_lost != self.was_signal_lost {
            self.was_signal_lost = snap.signal_lost;
            if snap.signal_lost {
                signal_lost_due = true;
            } else {
                signal_back_due = true;
            }
        }

        // The off-course arm. The nav task's hysteresis
        // ([`crate::course::OffCourseAlert`], 40 m latch / 20 m release)
        // already de-flaps the signal, so the engine only edge-detects it:
        // the latch closing raises the warning (re-queued when displaced —
        // there is no later reminder and every unseen minute banks wrong-way
        // distance), the latch releasing raises the ON COURSE affirmation
        // (dropped when the slot is busy — the milestone rule: a stale
        // all-clear is worse than none, and the Nav page carries the truth).
        // A `None` sample clears the edge detector silently: no course or no
        // projection is absence of knowledge, not a recovery.
        let mut back_on_course_due = false;
        match snap.nav_off_course {
            Some(true) => {
                if !self.was_off_course {
                    self.was_off_course = true;
                    self.pending_off_course = true;
                }
            }
            Some(false) => {
                if self.was_off_course {
                    self.was_off_course = false;
                    back_on_course_due = true;
                }
            }
            None => self.was_off_course = false,
        }

        // The cutoff arm. Not gated on `Recording`: the race clock keeps
        // running through an aid-station pause, and a paused runner drifting
        // behind the cutoff is exactly who the warning is for. Like storm it
        // sets a pending flag rather than taking the slot, so the precedence
        // chain at the tail places it — leading storm in the re-queued class:
        // the front wants a decision inside the hour, the cutoff sooner.
        if let Some(eta) = snap.cutoff {
            match eta.status {
                CutoffEtaStatus::Behind => {
                    if self.cutoff_armed && eta.has_cutoff {
                        self.pending_cutoff = true;
                        self.cutoff_armed = false;
                    }
                }
                // Only a measured recovery re-arms — `Unknown` is the watch
                // losing sight of the runner, not the runner catching up.
                CutoffEtaStatus::On | CutoffEtaStatus::Tight => self.cutoff_armed = true,
                CutoffEtaStatus::Unknown => {}
            }
        }

        // The storm arm (§ 376). Not gated on `Recording`: a runner standing at
        // an aid station deciding whether to go back up onto the ridge is
        // exactly who the warning is for. It sets a pending flag rather than
        // taking the slot, so the precedence chain at the tail places it — one
        // rung under pace, one above fuel — and a displaced one re-queues.
        //
        // Only a MEASURED recovery re-arms it. A trend withdrawn because the
        // GPS reference went stale is the watch losing sight of the weather,
        // not the weather clearing, and re-arming on that would let one canyon
        // turn one front into two banners.
        if let Some(storm) = snap.storm {
            if storm.trend == StormTrend::Storm {
                if self.storm_armed && self.storm_alert {
                    self.pending_storm = true;
                    self.storm_armed = false;
                }
            } else if storm.trend.is_measured() {
                self.storm_armed = true;
            }
        }

        // The track-resolution arm, in ladder position under storm and the loss
        // notice: like them it only sets a pending flag, so the tail chain is
        // what actually places it. Not gated on `Recording` — the slot fills
        // from the staged track, which a manual pause does not rewind.
        //
        // `track_thinning` is a state rather than an event (the store's
        // `keep_every`, fed back per `PushOutcome::Thinned`), so the engine
        // edge-detects an INCREASE. Only an increase: a stored track never
        // recovers its resolution, so a fall is `Recorder::start`'s reset and
        // announcing it would invent a recovery. Every step fires, and there is
        // deliberately no cooldown beside it — each doubling needs the slot to
        // fill again, which takes about as long as the run so far, so the arm
        // is rate-limited by construction (the storm arm's reasoning) and the
        // whole geometric ladder is at most the eight steps a `u8` can name.
        if snap.track_thinning > self.last_track_thinning {
            self.pending_track_thinned = true;
        }
        self.last_track_thinning = snap.track_thinning;

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
            if self.pending_off_course {
                self.pending_off_course = false;
                self.active = Some((Alert::OffCourse, uptime_s));
            } else if self.pending_cutoff {
                self.pending_cutoff = false;
                self.active = Some((Alert::CutoffBehind, uptime_s));
            } else if let Some(kind) = self.pending_push_reject.take() {
                self.active = Some((Alert::PushRejected(kind), uptime_s));
            } else if self.pending_storm {
                self.pending_storm = false;
                self.active = Some((Alert::Storm, uptime_s));
            } else if self.pending_run_lost {
                self.pending_run_lost = false;
                self.active = Some((Alert::RunLost, uptime_s));
            } else if self.pending_track_thinned {
                self.pending_track_thinned = false;
                self.active = Some((Alert::TrackThinned, uptime_s));
            } else if self.pending_eat {
                self.pending_eat = false;
                self.active = Some((Alert::Eat, uptime_s));
            } else if self.pending_drink {
                self.pending_drink = false;
                self.active = Some((Alert::Drink, uptime_s));
            } else if signal_lost_due {
                self.active = Some((Alert::SignalLost, uptime_s));
            } else if signal_back_due {
                self.active = Some((Alert::SignalBack, uptime_s));
            } else if back_on_course_due {
                self.active = Some((Alert::BackOnCourse, uptime_s));
            } else if timer_due {
                self.active = Some((Alert::TimerDone, uptime_s));
            } else if let Some(milestone_m) = distance_due {
                self.active = Some((Alert::Distance(milestone_m), uptime_s));
            } else if let Some(milestone_s) = time_due {
                self.active = Some((Alert::Time(milestone_s), uptime_s));
            }
        }

        self.active.map(|(alert, _)| alert)
    }

    /// Put `alert` on the display slot, re-queueing the fuel reminder or the
    /// storm banner it may be displacing (a superseded milestone / pace /
    /// workout banner is simply gone — §214's re-queue rule is fuel's, and
    /// § 376 extends it to the one warning that never comes round again).
    fn take_slot(&mut self, alert: Alert, uptime_s: u32) {
        match self.active {
            Some((Alert::Drink, _)) => self.pending_drink = true,
            Some((Alert::Eat, _)) => self.pending_eat = true,
            Some((Alert::Storm, _)) => self.pending_storm = true,
            Some((Alert::CutoffBehind, _)) => self.pending_cutoff = true,
            Some((Alert::OffCourse, _)) => self.pending_off_course = true,
            Some((Alert::RunLost, _)) => self.pending_run_lost = true,
            Some((Alert::PushRejected(kind), _)) => self.pending_push_reject = Some(kind),
            Some((Alert::TrackThinned, _)) => self.pending_track_thinned = true,
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
        self.last_backyard_warning_seq = 0;
        self.cutoff_armed = true;
        self.pending_cutoff = false;
        self.was_off_course = false;
        self.pending_off_course = false;
        self.last_waypoint_mark_seq = None;
        self.last_waypoint_refuse_seq = None;
        self.last_run_lost_seq = None;
        self.pending_run_lost = false;
        self.last_push_seq = None;
        self.pending_push_reject = None;
        self.was_signal_lost = false;
        self.last_track_thinning = 1;
        self.pending_track_thinned = false;
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
    /// - `acknowledged` — the runner is attending to fuel. Clears the latch;
    ///   the next interval's reminder re-latches. What earns the flag is the
    ///   caller's ([`FuelAckDwell`] — a held Fuel page, never a fly-by).
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
                | Alert::WorkoutDone
                | Alert::TimerDone
                | Alert::BackyardBell(_)
                | Alert::Storm
                | Alert::CutoffBehind
                | Alert::OffCourse
                | Alert::BackOnCourse
                | Alert::WaypointMarked
                | Alert::WaypointNoFix
                | Alert::SignalLost
                | Alert::SignalBack
                | Alert::RunLost
                | Alert::PushRejected(_)
                | Alert::TrackThinned,
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

/// How long the Fuel glance must stay the current page before the standing
/// overdue marker reads it as the runner attending to fuel. The marker exists
/// precisely because a heads-down runner misses the 8 s banner — and a
/// one-second fly-by over the Fuel page on the way to Nav is the same miss,
/// so a bare `page == Fuel` test let ordinary ring-paging silently defeat the
/// one backstop built for it.
pub const FUEL_ACK_DWELL_S: u32 = 3;

/// Turns "which page is showing" into the `acknowledged` input
/// [`FuelOverdueTracker::observe`] wants: true only once the Fuel page has
/// been held [`FUEL_ACK_DWELL_S`] continuously. Leaving the page resets the
/// dwell — three separate fly-bys are three misses, not an acknowledgement.
///
/// Pure and display-side like the tracker it feeds; the ui task owns one and
/// samples it per frame. Frames are event-driven rather than periodic, so the
/// dwell is measured against the frame clock (`uptime_s`) and a late frame
/// simply reads the threshold as already met.
#[derive(Default)]
pub struct FuelAckDwell {
    on_page_since_s: Option<u32>,
}

impl FuelAckDwell {
    pub const fn new() -> Self {
        Self {
            on_page_since_s: None,
        }
    }

    /// Fold one frame in and report whether the dwell earns the ack.
    pub fn observe(&mut self, on_fuel_page: bool, uptime_s: u32) -> bool {
        if !on_fuel_page {
            self.on_page_since_s = None;
            return false;
        }
        let since = *self.on_page_since_s.get_or_insert(uptime_s);
        uptime_s.saturating_sub(since) >= FUEL_ACK_DWELL_S
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ble_sync::PushOutcome;
    use crate::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM, ZONE_COUNT};

    fn snap(state: RecordState, moving_s: u32) -> Snapshot {
        Snapshot {
            state,
            manual_paused: false,
            signal_lost: false,
            backyard: None,
            distance_m: 0.0,
            elapsed_s: moving_s,
            moving_s,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
            gap_s_per_km: None,
            gap_held: false,
            lap: 1,
            lap_distance_m: 0.0,
            lap_elapsed_s: 0,
            last_lap: None,
            auto_lap: crate::auto_lap::AUTO_LAP_DEFAULT,
            zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            hr_source: None,
            zone_ceiling: None,
            pace_band: None,
            zone_time_s: [0; ZONE_COUNT],
            pacer: None,
            cutoffs_loaded: false,
            cutoff: None,
            sleep: None,
            race_prediction: None,
            pace_bucket_m: [0.0; crate::record::PACE_BUCKET_COUNT],
            training_stress: None,
            training_stress_trimp: false,
            load_trend: None,
            band: None,
            gear: None,
            roadbook_loaded: false,
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
            nav_off_course: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            route_position_permille: None,
            race_day: None,
            race_phase: None,
            climb: Default::default(),
            waypoint: None,
            waypoint_count: 0,
            waypoint_mark_seq: 0,
            waypoint_refuse_seq: 0,
            run_lost_seq: 0,
            push_outcome: PushOutcome::DEFAULT,
            timer: None,
            storm: None,
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

    /// A recording snapshot carrying a timer that has expired on arming `seq`
    /// (0 = armed but still counting).
    fn timed(seq: u16, moving_s: u32) -> Snapshot {
        Snapshot {
            timer: Some(crate::timers::TimerView {
                preset_s: 300,
                elapsed_s: 300,
                display_s: 0,
                running: true,
                expired: seq != 0,
                expiry_seq: seq,
                gap_unknown: false,
            }),
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_timer_expiry_raises_one_banner_and_never_says_alarm() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&timed(0, 10), None, 10), None);
        assert_eq!(e.on_update(&timed(1, 11), None, 11), Some(Alert::TimerDone));
        assert_eq!(banner(Alert::TimerDone).as_str(), "! TIME UP");
        // Still expired on every later tick, and silent: one countdown, one
        // banner.
        for t in 12..200 {
            let shown = e.on_update(&timed(1, t), None, t);
            assert!(
                shown.is_none() || t < 11 + ALERT_TTL_S,
                "re-fired for the same arming at t={t}"
            );
        }
        // A fresh arming is a different edge and does fire again.
        assert_eq!(
            e.on_update(&timed(2, 200), None, 200),
            Some(Alert::TimerDone)
        );
    }

    #[test]
    fn a_timer_expiry_is_dropped_by_a_busy_slot_never_queued() {
        // The milestone rule: the Timer page counts the overrun up, so a banner
        // the runner missed costs nothing that cannot still be read.
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 1_000_000);
        assert_eq!(e.on_update(&rec(300), None, 300), Some(Alert::Drink));
        let mut busy = timed(1, 301);
        busy.moving_s = 301;
        assert_eq!(
            e.on_update(&busy, None, 301),
            Some(Alert::Drink),
            "fuel keeps the slot — §214 says a gel is the one thing never dropped"
        );
        // The edge was consumed, not owed: nothing surfaces once the slot frees.
        let after = 301 + ALERT_TTL_S;
        assert_eq!(e.on_update(&timed(1, after), None, after), None);
    }

    #[test]
    fn a_timer_expiry_outranks_the_automatic_milestones() {
        let mut e = AlertEngine::new();
        e.set_distance_interval(Some(1_000));
        let mut both = timed(1, 300);
        both.distance_m = 1_000.0;
        assert_eq!(
            e.on_update(&both, None, 300),
            Some(Alert::TimerDone),
            "the milestone the runner set themselves leads the group"
        );
    }

    #[test]
    fn a_timer_that_expired_in_a_previous_run_does_not_re_announce() {
        // The instrument outlives the run, so the edge tracker has to as well —
        // a nap timer left expired must not greet the next run with a banner.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&timed(1, 10), None, 10), Some(Alert::TimerDone));
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 10), None, 30),
            None
        );
        assert_eq!(e.on_update(&snap(RecordState::Idle, 0), None, 31), None);
        assert_eq!(e.on_update(&timed(1, 0), None, 100), None);
    }

    #[test]
    fn a_timer_expiry_fires_through_a_pause() {
        // An aid-station countdown is running precisely while the recorder is
        // not, so gating this arm on Recording would silence it exactly when it
        // is the reason the timer exists.
        let mut e = AlertEngine::new();
        let paused = Snapshot {
            timer: timed(1, 0).timer,
            ..snap(RecordState::Paused, 0)
        };
        assert_eq!(e.on_update(&paused, None, 10), Some(Alert::TimerDone));
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
        assert_eq!(banner(Alert::CutoffBehind).as_str(), "! CUTOFF");
        assert_eq!(banner(Alert::OffCourse).as_str(), "! OFF CRS");
        // The affirmations: no bang, they ask for nothing.
        assert_eq!(banner(Alert::BackOnCourse).as_str(), "ON COURSE");
        assert_eq!(banner(Alert::WaypointMarked).as_str(), "WPT SAVED");
        // The refusal names the cause, not the failure.
        assert_eq!(banner(Alert::WaypointNoFix).as_str(), "! NO FIX");
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
            Alert::CutoffBehind,
            Alert::OffCourse,
            Alert::BackOnCourse,
            Alert::WaypointMarked,
            Alert::WaypointNoFix,
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
            Some(Alert::ZoneAbove(_)),
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

    /// A snapshot carrying a backyard whistle at `min` minutes with counter
    /// `seq`.
    fn backyard_snap(state: RecordState, seq: u16, min: u8) -> Snapshot {
        Snapshot {
            backyard: Some(crate::backyard::BackyardView {
                loops: 12,
                to_bell_s: Some(u32::from(min) * 60),
                in_corral: false,
                loop_distance_m: Some(6_706.0),
                loop_progress_m: 5_000.0,
                return_margin_s: None,
                warning_seq: seq,
                warning_min: min,
            }),
            ..snap(state, 0)
        }
    }

    #[test]
    fn a_corral_whistle_fires_once_per_counter_change() {
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 0, 0), None, 0),
            None
        );
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 1, 3), None, 1),
            Some(Alert::BackyardBell(3))
        );
        // The same counter on the next tick is the same whistle still on
        // screen, not a second one.
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 1, 3), None, 2),
            Some(Alert::BackyardBell(3))
        );
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 2, 2), None, 3),
            Some(Alert::BackyardBell(2))
        );
    }

    #[test]
    fn a_whistle_reaches_a_runner_standing_in_the_corral() {
        // The one alert deliberately not gated on Recording: the runner it is
        // most for is the one auto-paused in the corral with 60 s left.
        let mut e = AlertEngine::new();
        let mut s = backyard_snap(RecordState::Paused, 1, 1);
        s.backyard = s.backyard.map(|b| crate::backyard::BackyardView {
            in_corral: true,
            ..b
        });
        assert_eq!(
            e.on_update(&s, None, 0),
            Some(Alert::BackyardBell(1)),
            "a paused runner is exactly who the bell is calling"
        );
    }

    #[test]
    fn a_whistle_takes_the_slot_from_a_fuel_reminder_which_re_queues() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(10, 10);
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 0, 0), None, 0),
            None
        );
        let mut fuelled = backyard_snap(RecordState::Recording, 0, 0);
        fuelled.moving_s = 20;
        assert_eq!(e.on_update(&fuelled, None, 1), Some(Alert::Eat));
        assert_eq!(
            e.on_update(&backyard_snap(RecordState::Recording, 1, 3), None, 2),
            Some(Alert::BackyardBell(3))
        );
        // Fuel is never silently dropped — the displaced reminder comes back
        // once the whistle's TTL expires.
        assert_eq!(
            e.on_update(
                &backyard_snap(RecordState::Recording, 1, 3),
                None,
                2 + ALERT_TTL_S
            ),
            Some(Alert::Eat)
        );
    }

    #[test]
    fn a_whistle_outranks_a_timer_expiry_on_the_same_tick() {
        // §372 and §375 arrived on separate branches and each stated its own
        // rung against arms that existed then; this is the pair they never met
        // in. The bell wins: a missed corral ends the race outright, while the
        // Timer page counts its own overrun up, so the countdown's banner is
        // the one of the two that costs nothing to lose.
        let mut e = AlertEngine::new();
        let mut both = backyard_snap(RecordState::Recording, 1, 2);
        both.timer = timed(1, 0).timer;
        assert_eq!(e.on_update(&both, None, 5), Some(Alert::BackyardBell(2)));
        // And the timer edge was consumed, not owed: it never resurfaces.
        let mut after = backyard_snap(RecordState::Recording, 1, 2);
        after.timer = both.timer;
        assert_eq!(e.on_update(&after, None, 5 + ALERT_TTL_S), None);
    }

    #[test]
    fn a_whistle_on_the_same_tick_never_swallows_a_pace_excursion() {
        // Every arm refuses a higher rung by inspecting the slot, so the slot
        // has to already hold it. Evaluated after pace, the whistle overwrote a
        // `PaceFast` that had already banked `pace_armed = false` and stamped
        // the cooldown — so an excursion that collided with a whistle was lost
        // for the whole excursion without ever reaching a frame.
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        let mut both = backyard_snap(RecordState::Recording, 1, 3);
        both.current_pace_s_per_km = Some(250);
        assert_eq!(e.on_update(&both, None, 5), Some(Alert::BackyardBell(3)));
        // Still outside the band and no new whistle edge: the blocked excursion
        // stayed armed and un-cooled, so it surfaces once the bell's TTL lapses.
        let after = 5 + ALERT_TTL_S;
        let mut still = backyard_snap(RecordState::Recording, 1, 3);
        still.current_pace_s_per_km = Some(250);
        assert_eq!(e.on_update(&still, None, after), Some(Alert::PaceFast));
    }

    #[test]
    fn a_workout_edge_on_the_same_tick_never_swallows_a_pace_excursion() {
        // The same collision one rung down: a workout banner outranks pace, so
        // a pace excursion blocked by one must retry rather than burn its
        // once-per-excursion state on a banner the workout edge overwrites.
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        let mut both = rec_workout(wv(1, 0, false), 5);
        both.current_pace_s_per_km = Some(250);
        assert!(matches!(
            e.on_update(&both, None, 5),
            Some(Alert::WorkoutStep { .. })
        ));
        let after = 5 + ALERT_TTL_S;
        let mut still = rec_workout(wv(1, 0, false), after);
        still.current_pace_s_per_km = Some(250);
        assert_eq!(e.on_update(&still, None, after), Some(Alert::PaceFast));
    }

    #[test]
    fn a_waypoint_confirmation_on_the_same_tick_never_swallows_a_pace_excursion() {
        // §382's waypoint arm carries the workout edges' rung, so it outranks
        // pace for the same reason: the confirmation is dropped if blocked,
        // where the excursion can still retry.
        let mut e = AlertEngine::new();
        e.set_pace_band(Some((300, 420)));
        // The first sample only baselines the mark counter, and it is taken
        // INSIDE the band so pace reaches the collision tick un-cooled — a
        // pace alert already gated by [`PACE_ALERT_COOLDOWN_S`] would let this
        // pass without the precedence being what held it back.
        let mut base = marked(0, 0, 4);
        base.current_pace_s_per_km = Some(360);
        assert_eq!(e.on_update(&base, None, 4), None);
        let mut both = marked(1, 0, 5);
        both.current_pace_s_per_km = Some(250);
        assert_eq!(
            e.on_update(&both, None, 5),
            Some(Alert::WaypointMarked),
            "the confirmation the runner is looking for wins the slot"
        );
        let after = 5 + ALERT_TTL_S;
        let mut still = marked(1, 0, after);
        still.current_pace_s_per_km = Some(250);
        assert_eq!(e.on_update(&still, None, after), Some(Alert::PaceFast));
    }

    #[test]
    fn a_whistle_outranks_a_workout_edge_on_the_same_tick() {
        let mut e = AlertEngine::new();
        let mut both = backyard_snap(RecordState::Recording, 1, 2);
        both.workout = Some(wv(1, 0, false));
        assert_eq!(e.on_update(&both, None, 5), Some(Alert::BackyardBell(2)));
        // A workout edge is a milestone in kind, so the blocked transition is
        // dropped rather than owed — nothing stale surfaces at the TTL.
        let mut after = backyard_snap(RecordState::Recording, 1, 2);
        after.workout = Some(wv(1, 0, false));
        assert_eq!(e.on_update(&after, None, 5 + ALERT_TTL_S), None);
    }

    #[test]
    fn a_whistle_outranks_a_waypoint_confirmation_on_the_same_tick() {
        let mut e = AlertEngine::new();
        let mut base = backyard_snap(RecordState::Recording, 0, 0);
        base.waypoint_mark_seq = 0;
        assert_eq!(e.on_update(&base, None, 4), None);
        let mut both = backyard_snap(RecordState::Recording, 1, 2);
        both.waypoint_mark_seq = 1;
        assert_eq!(e.on_update(&both, None, 5), Some(Alert::BackyardBell(2)));
        // Dropped, not owed, exactly as a zone banner already leaves it.
        let mut after = backyard_snap(RecordState::Recording, 1, 2);
        after.waypoint_mark_seq = 1;
        assert_eq!(e.on_update(&after, None, 5 + ALERT_TTL_S), None);
    }

    #[test]
    fn a_zone_banner_blocks_a_whistle_and_the_whistle_is_dropped_not_owed() {
        // The milestone rule: a whistle shown late is a lie about the clock,
        // and the page carries the live countdown anyway.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(2));
        let cutoffs = zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM);
        let mut hot = backyard_snap(RecordState::Recording, 0, 0);
        hot.zone_cutoffs = cutoffs;
        assert!(matches!(
            e.on_update(&hot, Some(190), 0),
            Some(Alert::ZoneAbove(_))
        ));
        let mut whistling = backyard_snap(RecordState::Recording, 1, 3);
        whistling.zone_cutoffs = cutoffs;
        assert!(
            matches!(
                e.on_update(&whistling, Some(190), 1),
                Some(Alert::ZoneAbove(_))
            ),
            "over-effort against ground truth outranks even the bell"
        );
        // The counter was consumed, so the blocked whistle never resurfaces.
        assert_eq!(
            e.on_update(&whistling, None, 1 + ALERT_TTL_S),
            None,
            "a stale whistle is dropped, not owed"
        );
    }

    #[test]
    fn an_unarmed_watch_never_whistles() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&snap(RecordState::Recording, 0), None, 0), None);
        assert_eq!(e.on_update(&snap(RecordState::Recording, 1), None, 1), None);
    }

    /// A recording snapshot carrying a storm trend.
    fn stormy(trend: StormTrend, moving_s: u32) -> Snapshot {
        Snapshot {
            storm: Some(crate::storm::StormView {
                trend,
                sea_level_hpa: Some(1_006.0),
                delta_hpa: trend.is_measured().then_some(-5.2),
                span_s: 10_800,
            }),
            ..rec(moving_s)
        }
    }

    #[test]
    fn the_storm_arm_is_off_by_default() {
        // The whole value of this banner is that it is rare, so the watch does
        // not volunteer it.
        let mut e = AlertEngine::new();
        for t in 0..30 {
            assert_eq!(e.on_update(&stormy(StormTrend::Storm, t), None, t), None);
        }
    }

    #[test]
    fn an_armed_storm_raises_one_banner_per_front() {
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 10), None, 10),
            Some(Alert::Storm)
        );
        assert_eq!(banner(Alert::Storm).as_str(), "! STORM");
        // The trend stays latched for the rest of the front; one front, one
        // banner.
        for t in 11..600 {
            let shown = e.on_update(&stormy(StormTrend::Storm, t), None, t);
            assert!(
                shown.is_none() || t < 10 + ALERT_TTL_S,
                "re-fired inside one front at t={t}"
            );
        }
    }

    #[test]
    fn a_measured_recovery_re_arms_the_banner_and_a_withdrawn_trend_does_not() {
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 10), None, 10),
            Some(Alert::Storm)
        );
        // Losing the GPS reference is the watch losing sight of the weather,
        // not the weather clearing — re-arming on it would turn one front into
        // two banners every time the runner enters a canyon.
        let mut t = 10 + ALERT_TTL_S;
        for withdrawn in [StormTrend::NoReference, StormTrend::Building] {
            assert_eq!(e.on_update(&stormy(withdrawn, t), None, t), None);
            t += 1;
            assert_eq!(e.on_update(&stormy(StormTrend::Storm, t), None, t), None);
            t += 1;
        }
        // A measured recovery is the front passing, and the next one is news.
        assert_eq!(e.on_update(&stormy(StormTrend::Steady, t), None, t), None);
        t += 1;
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, t), None, t),
            Some(Alert::Storm)
        );
    }

    #[test]
    fn a_storm_banner_leads_the_fuel_reminders() {
        // One rung above eat: a missed gel is re-offered a cadence later, a
        // missed front is not.
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        e.set_fuel_intervals(300, 300);
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 300), None, 300),
            Some(Alert::Storm)
        );
        let a = 300 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, a), None, a),
            Some(Alert::Eat)
        );
        let b = a + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, b), None, b),
            Some(Alert::Drink)
        );
    }

    #[test]
    fn a_zone_banner_displaces_a_storm_which_re_queues_rather_than_dropping() {
        // The §214 re-queue rule, extended to the one warning that never comes
        // round again: over-effort still outranks it, but it must not vanish.
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 10), None, 10),
            Some(Alert::Storm)
        );
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let after = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, after), Some(150), after),
            Some(Alert::Storm),
            "the displaced storm came back"
        );
    }

    #[test]
    fn a_storm_fires_through_a_pause() {
        // A runner standing at an aid station deciding whether to go back up
        // onto the ridge is exactly who this is for.
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        let paused = Snapshot {
            storm: stormy(StormTrend::Storm, 0).storm,
            ..snap(RecordState::Paused, 0)
        };
        assert_eq!(e.on_update(&paused, None, 10), Some(Alert::Storm));
    }

    #[test]
    fn a_storm_raised_before_a_run_boundary_is_still_owed_after_it() {
        // The sky did not reset when the runner pressed stop. Unlike the fuel
        // cadences — which re-base per run — the pending storm and its arming
        // are configuration-lifetime, like the timer's expiry counter.
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        e.set_zone_ceiling(Some(3));
        // Raised, then immediately displaced, then the run ends before the TTL.
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 10), None, 10),
            Some(Alert::Storm)
        );
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 11), None, 12),
            None
        );
        assert_eq!(e.on_update(&snap(RecordState::Idle, 0), None, 13), None);
        assert_eq!(
            e.on_update(&stormy(StormTrend::Storm, 0), None, 100),
            Some(Alert::Storm),
            "the front the runner was never shown is still out there"
        );
        // ...and it is still one banner per front, not one per run.
        let t = 100 + ALERT_TTL_S;
        assert_eq!(e.on_update(&stormy(StormTrend::Storm, t), None, t), None);
    }

    #[test]
    fn a_watch_with_no_barometer_never_storms() {
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        for t in 0..30 {
            assert_eq!(e.on_update(&rec(t), None, t), None);
        }
    }

    #[test]
    fn a_storm_banner_never_latches_the_fuel_marker() {
        let mut t = FuelOverdueTracker::new();
        assert_eq!(t.observe(Some(Alert::Eat), true, false), FuelOverdue::Eat);
        assert_eq!(
            t.observe(Some(Alert::Storm), true, false),
            FuelOverdue::Eat,
            "a storm supersedes the banner, never the standing fuel marker"
        );
    }

    fn cut(status: CutoffEtaStatus, moving_s: u32) -> Snapshot {
        Snapshot {
            cutoff: Some(crate::cutoff_eta::CutoffEta {
                has_cutoff: true,
                distance_to_m: 2_000.0,
                projected_arrival_elapsed_s: Some(moving_s + 900),
                margin_s: Some(if status == CutoffEtaStatus::Behind {
                    -120
                } else {
                    600
                }),
                required_pace_s_per_km: Some(330.0),
                limit_passed: false,
                status,
            }),
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_behind_projection_raises_one_banner_per_excursion() {
        // No arming call: unlike storm, the presence of cutoff legs on the
        // loaded course is the opt-in.
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 10), None, 10),
            Some(Alert::CutoffBehind)
        );
        assert_eq!(banner(Alert::CutoffBehind).as_str(), "! CUTOFF");
        // Still behind is not news — one excursion, one banner.
        for t in 11..600 {
            let shown = e.on_update(&cut(CutoffEtaStatus::Behind, t), None, t);
            assert!(
                shown.is_none() || t < 10 + ALERT_TTL_S,
                "re-fired inside one excursion at t={t}"
            );
        }
    }

    #[test]
    fn a_measured_recovery_re_arms_the_cutoff_and_unknown_does_not() {
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 10), None, 10),
            Some(Alert::CutoffBehind)
        );
        // A stale fix is the watch losing sight of the runner, not the runner
        // catching up — Unknown must not re-arm.
        let mut t = 10 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Unknown, t), None, t),
            None
        );
        t += 1;
        assert_eq!(e.on_update(&cut(CutoffEtaStatus::Behind, t), None, t), None);
        t += 1;
        // A measured recovery is the runner back on schedule; falling behind
        // again is news.
        for measured in [CutoffEtaStatus::On, CutoffEtaStatus::Tight] {
            assert_eq!(e.on_update(&cut(measured, t), None, t), None);
            t += 1;
            assert_eq!(
                e.on_update(&cut(CutoffEtaStatus::Behind, t), None, t),
                Some(Alert::CutoffBehind)
            );
            t += ALERT_TTL_S;
        }
    }

    #[test]
    fn a_cutoff_banner_leads_the_fuel_reminders() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 300);
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 300), None, 300),
            Some(Alert::CutoffBehind)
        );
        let a = 300 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, a), None, a),
            Some(Alert::Eat)
        );
    }

    #[test]
    fn a_zone_banner_displaces_a_cutoff_which_re_queues_rather_than_dropping() {
        // There is no later reminder, and the thing it warns of only gets
        // worse — the §214 re-queue rule.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 10), None, 10),
            Some(Alert::CutoffBehind)
        );
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let after = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, after), Some(150), after),
            Some(Alert::CutoffBehind),
            "the displaced cutoff warning came back"
        );
    }

    #[test]
    fn a_cutoff_warning_fires_through_a_pause() {
        // The race clock keeps running through an aid-station stop; a paused
        // runner drifting behind the cutoff is exactly who this is for.
        let mut e = AlertEngine::new();
        let paused = Snapshot {
            cutoff: cut(CutoffEtaStatus::Behind, 0).cutoff,
            ..snap(RecordState::Paused, 0)
        };
        assert_eq!(e.on_update(&paused, None, 10), Some(Alert::CutoffBehind));
    }

    #[test]
    fn a_run_boundary_clears_the_cutoff_arm() {
        // Unlike storm, a cutoff is a property of the run's course — one
        // raised at the end of a run is not owed to the next.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 10), None, 10),
            Some(Alert::CutoffBehind)
        );
        // Displace it so it is pending, then end the run while it waits.
        assert_eq!(
            e.on_update(&cut(CutoffEtaStatus::Behind, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 13), None, 13),
            None
        );
        assert_eq!(e.on_update(&rec(14), None, 30), None);
    }

    #[test]
    fn a_cutoff_banner_never_latches_the_fuel_marker() {
        let mut t = FuelOverdueTracker::new();
        assert_eq!(t.observe(Some(Alert::Eat), true, false), FuelOverdue::Eat);
        assert_eq!(
            t.observe(Some(Alert::CutoffBehind), true, false),
            FuelOverdue::Eat,
            "a cutoff warning supersedes the banner, never the standing fuel marker"
        );
    }

    fn off(off_course: Option<bool>, moving_s: u32) -> Snapshot {
        Snapshot {
            nav_off_course: off_course,
            ..rec(moving_s)
        }
    }

    #[test]
    fn going_off_course_raises_one_banner_per_excursion() {
        // The nav latch is already hysteretic (40 m on / 20 m off), so the
        // engine's edge detector fires exactly once per excursion.
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        for t in 11..120 {
            let shown = e.on_update(&off(Some(true), t), None, t);
            assert!(
                shown.is_none() || t < 10 + ALERT_TTL_S,
                "re-fired inside one excursion at t={t}"
            );
        }
    }

    #[test]
    fn a_recovery_raises_the_on_course_affirmation_once() {
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        let t = 10 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&off(Some(false), t), None, t),
            Some(Alert::BackOnCourse)
        );
        // Staying on course is not news.
        let t = t + ALERT_TTL_S;
        assert_eq!(e.on_update(&off(Some(false), t), None, t), None);
    }

    #[test]
    fn a_lost_projection_is_not_a_recovery() {
        // No course / no fix is absence of knowledge: it must not fire the
        // affirmation, and a projection that comes back still off-course is a
        // fresh excursion worth a fresh warning.
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        let mut t = 10 + ALERT_TTL_S;
        assert_eq!(e.on_update(&off(None, t), None, t), None);
        t += 1;
        assert_eq!(e.on_update(&off(Some(false), t), None, t), None);
        t += 1;
        assert_eq!(
            e.on_update(&off(Some(true), t), None, t),
            Some(Alert::OffCourse)
        );
    }

    #[test]
    fn a_zone_banner_displaces_off_course_which_re_queues_rather_than_dropping() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        assert_eq!(
            e.on_update(&off(Some(true), 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let after = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&off(Some(true), after), Some(150), after),
            Some(Alert::OffCourse),
            "the displaced off-course warning came back"
        );
    }

    #[test]
    fn off_course_leads_the_re_queued_class() {
        // Both raised on the same tick: the wrong turn beats the cutoff
        // projection (which the wrong turn invalidates anyway), and the
        // displaced cutoff is owed the next slot.
        let mut e = AlertEngine::new();
        let both = Snapshot {
            cutoff: cut(CutoffEtaStatus::Behind, 10).cutoff,
            ..off(Some(true), 10)
        };
        assert_eq!(e.on_update(&both, None, 10), Some(Alert::OffCourse));
        let t = 10 + ALERT_TTL_S;
        assert_eq!(e.on_update(&both, None, t), Some(Alert::CutoffBehind));
    }

    #[test]
    fn a_busy_slot_drops_the_on_course_affirmation() {
        // The milestone rule: a stale all-clear shown after the runner
        // drifted off again is a lie the Nav page would contradict.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        let t = 10 + ALERT_TTL_S;
        // The recovery edge lands while a zone banner owns the slot.
        assert_eq!(
            e.on_update(&off(Some(false), t), Some(160), t),
            Some(Alert::ZoneAbove(4))
        );
        let t = t + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&off(Some(false), t), Some(150), t),
            None,
            "a dropped affirmation is not owed"
        );
    }

    #[test]
    fn a_run_boundary_clears_the_off_course_arm() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&off(Some(true), 10), None, 10),
            Some(Alert::OffCourse)
        );
        // Displace it so it is pending, then end the run while it waits.
        assert_eq!(
            e.on_update(&off(Some(true), 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 13), None, 13),
            None
        );
        assert_eq!(e.on_update(&rec(14), None, 30), None);
    }

    fn marked(mark_seq: u8, refuse_seq: u8, moving_s: u32) -> Snapshot {
        Snapshot {
            waypoint_mark_seq: mark_seq,
            waypoint_refuse_seq: refuse_seq,
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_saved_mark_answers_on_screen_once() {
        let mut e = AlertEngine::new();
        // First sample baselines; the press lands on the next tick.
        assert_eq!(e.on_update(&marked(0, 0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&marked(1, 0, 11), None, 11),
            Some(Alert::WaypointMarked)
        );
        // A steady counter is not news.
        let t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&marked(1, 0, t), None, t), None);
    }

    #[test]
    fn marks_banked_before_the_run_do_not_replay_at_the_start_line() {
        // The store survives runs and reboots; the counter arrives non-zero.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&marked(5, 2, 10), None, 10), None);
        let t = 10 + ALERT_TTL_S;
        assert_eq!(e.on_update(&marked(5, 2, t), None, t), None);
    }

    #[test]
    fn a_refused_mark_says_no_fix() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&marked(0, 0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&marked(0, 1, 11), None, 11),
            Some(Alert::WaypointNoFix)
        );
    }

    #[test]
    fn a_zone_banner_blocks_waypoint_feedback_and_it_is_dropped_not_owed() {
        // A confirmation shown late confirms the wrong thing.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&marked(0, 0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&marked(0, 0, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&marked(1, 0, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let t = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&marked(1, 0, t), Some(150), t),
            None,
            "a blocked confirmation is not owed"
        );
    }

    #[test]
    fn a_waypoint_confirmation_displaces_a_fuel_reminder_which_requeues() {
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 0);
        assert_eq!(e.on_update(&marked(0, 0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&marked(0, 0, 300), None, 300),
            Some(Alert::Drink)
        );
        assert_eq!(
            e.on_update(&marked(1, 0, 301), None, 301),
            Some(Alert::WaypointMarked)
        );
        let t = 301 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&marked(1, 0, t), None, t),
            Some(Alert::Drink),
            "the displaced reminder came back"
        );
    }

    #[test]
    fn a_fly_by_over_the_fuel_page_is_not_an_acknowledgement() {
        // Ring-paging crosses Fuel for a second on the way to Nav — the same
        // miss the standing marker exists for, so it must not clear it.
        let mut d = FuelAckDwell::new();
        assert!(!d.observe(true, 100));
        assert!(!d.observe(true, 101));
        assert!(!d.observe(false, 102));
        // Three separate fly-bys are three misses, not a dwell.
        assert!(!d.observe(true, 110));
        assert!(!d.observe(false, 111));
        assert!(!d.observe(true, 120));
        assert!(!d.observe(false, 121));
    }

    #[test]
    fn holding_the_fuel_page_earns_the_ack_and_leaving_resets_it() {
        let mut d = FuelAckDwell::new();
        assert!(!d.observe(true, 100));
        assert!(d.observe(true, 100 + FUEL_ACK_DWELL_S));
        // Event-driven frames: a late frame reads the threshold as met.
        let mut d = FuelAckDwell::new();
        assert!(!d.observe(true, 200));
        assert!(d.observe(true, 230));
        // Leaving resets the dwell entirely.
        assert!(!d.observe(false, 231));
        assert!(!d.observe(true, 232));
        assert!(!d.observe(true, 233));
    }

    fn voided(signal_lost: bool, moving_s: u32) -> Snapshot {
        Snapshot {
            state: if signal_lost {
                RecordState::Paused
            } else {
                RecordState::Recording
            },
            signal_lost,
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_signal_void_announces_itself_once_and_so_does_the_recovery() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&voided(false, 10), None, 10), None);
        assert_eq!(
            e.on_update(&voided(true, 11), None, 11),
            Some(Alert::SignalLost)
        );
        assert_eq!(banner(Alert::SignalLost).as_str(), "! GPS LOST");
        // A void that persists is a state, not a second event.
        let mut t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&voided(true, t), None, t), None);
        t += 1;
        assert_eq!(
            e.on_update(&voided(false, t), None, t),
            Some(Alert::SignalBack)
        );
        assert_eq!(banner(Alert::SignalBack).as_str(), "GPS BACK");
        let t = t + ALERT_TTL_S;
        assert_eq!(e.on_update(&voided(false, t), None, t), None);
    }

    #[test]
    fn a_busy_slot_drops_the_signal_banners_and_the_tag_carries_the_truth() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&voided(false, 10), None, 10), None);
        // The void lands while a zone banner owns the slot. Zone alerts only
        // fire while Recording, so drive the excursion first, then the void.
        assert_eq!(
            e.on_update(&voided(false, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&voided(true, 12), None, 12),
            Some(Alert::ZoneAbove(4))
        );
        let t = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&voided(true, t), None, t),
            None,
            "a dropped announcement is not owed — the AUTO tag persists"
        );
    }

    #[test]
    fn a_run_boundary_resets_the_signal_edge() {
        // A run ended mid-void must not announce GPS BACK at the next start.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&voided(false, 10), None, 10), None);
        assert_eq!(
            e.on_update(&voided(true, 11), None, 11),
            Some(Alert::SignalLost)
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 12), None, 12),
            None
        );
        assert_eq!(e.on_update(&voided(false, 20), None, 30), None);
    }

    fn lost(seq: u8, moving_s: u32) -> Snapshot {
        Snapshot {
            run_lost_seq: seq,
            ..rec(moving_s)
        }
    }

    fn pushed(kind: PushKind, seq: u8, accepted: bool, moving_s: u32) -> Snapshot {
        Snapshot {
            push_outcome: PushOutcome {
                seq,
                kind,
                accepted,
            },
            ..rec(moving_s)
        }
    }

    fn rejected(seq: u8, moving_s: u32) -> Snapshot {
        pushed(PushKind::Course, seq, false, moving_s)
    }

    #[test]
    fn a_lost_run_announces_itself_once_and_a_second_loss_again() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&lost(0, 10), None, 10), None);
        assert_eq!(e.on_update(&lost(1, 11), None, 11), Some(Alert::RunLost));
        assert_eq!(banner(Alert::RunLost).as_str(), "! RUN LOST");
        // A steady counter is not news — the loss already happened.
        let t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&lost(1, t), None, t), None);
        // Two evictions in one run are two losses; each is announced.
        assert_eq!(
            e.on_update(&lost(2, t + 1), None, t + 1),
            Some(Alert::RunLost)
        );
    }

    #[test]
    fn counters_banked_before_the_run_do_not_replay_at_the_start_line() {
        // Both counters survive between runs; the first sample of a run
        // adopts them without firing, like the waypoint pair.
        let mut e = AlertEngine::new();
        let pre = Snapshot {
            run_lost_seq: 3,
            ..rejected(7, 10)
        };
        assert_eq!(e.on_update(&pre, None, 10), None);
        let t = 10 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(
                &Snapshot {
                    run_lost_seq: 3,
                    ..rejected(7, t)
                },
                None,
                t
            ),
            None
        );
    }

    #[test]
    fn an_eviction_at_a_stop_time_commit_waits_for_the_idle_face() {
        // The commit that ends a short run can itself evict; the engine has
        // already reset by the time that counter moves, so the next start
        // adopts it silently — the home face's unsynced-pressure row is the
        // surface that owns the story between runs.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&lost(0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 11), None, 11),
            None
        );
        assert_eq!(e.on_update(&lost(1, 100), None, 100), None);
    }

    #[test]
    fn a_zone_banner_displaces_a_lost_run_notice_which_re_queues_rather_than_dropping() {
        // The loss is permanent and no page carries it mid-run; dropping the
        // notice would return it to the silence it came from.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&lost(0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&lost(1, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        let after = 11 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&lost(1, after), Some(150), after),
            Some(Alert::RunLost),
            "the displaced loss notice came back"
        );
    }

    #[test]
    fn a_lost_run_notice_yields_to_a_storm_but_leads_the_fuel_reminders() {
        // The bottom of the re-queued class: every arm above it still has a
        // decision to make, fuel below it comes round again.
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        e.set_fuel_intervals(300, 300);
        assert_eq!(e.on_update(&lost(0, 10), None, 10), None);
        let both = Snapshot {
            run_lost_seq: 1,
            ..stormy(StormTrend::Storm, 300)
        };
        assert_eq!(e.on_update(&both, None, 300), Some(Alert::Storm));
        let t = 300 + ALERT_TTL_S;
        let hold = Snapshot {
            run_lost_seq: 1,
            ..stormy(StormTrend::Storm, t)
        };
        assert_eq!(e.on_update(&hold, None, t), Some(Alert::RunLost));
        let t = t + ALERT_TTL_S;
        let hold = Snapshot {
            run_lost_seq: 1,
            ..stormy(StormTrend::Storm, t)
        };
        assert_eq!(e.on_update(&hold, None, t), Some(Alert::Eat));
    }

    #[test]
    fn a_course_rejection_says_crs_fail_once_per_rejection() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rejected(0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&rejected(1, 11), None, 11),
            Some(Alert::PushRejected(PushKind::Course))
        );
        assert_eq!(
            banner(Alert::PushRejected(PushKind::Course)).as_str(),
            "! CRS FAIL"
        );
        // A steady counter is not news; the next failed retry is.
        let t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&rejected(1, t), None, t), None);
        assert_eq!(
            e.on_update(&rejected(2, t + 1), None, t + 1),
            Some(Alert::PushRejected(PushKind::Course))
        );
    }

    #[test]
    fn every_refused_push_reaches_the_wrist_naming_its_own_frame() {
        // The defect this seam closed: only `course` had a banner, so a
        // refused workout / roadbook / screens / settings push left the OLD
        // value armed with nothing but a `warn!` down a cable no runner
        // carries. Each kind must both fire AND say which push it was — "one
        // of your pushes failed" is not something a runner can act on.
        for (kind, expected) in [
            (PushKind::Settings, "! SET FAIL"),
            (PushKind::Course, "! CRS FAIL"),
            (PushKind::Workout, "! WKT FAIL"),
            (PushKind::Screens, "! SCR FAIL"),
            (PushKind::Roadbook, "! RBK FAIL"),
        ] {
            let mut e = AlertEngine::new();
            assert_eq!(e.on_update(&pushed(kind, 0, false, 10), None, 10), None);
            assert_eq!(
                e.on_update(&pushed(kind, 1, false, 11), None, 11),
                Some(Alert::PushRejected(kind)),
                "{expected} never fired"
            );
            assert_eq!(banner(Alert::PushRejected(kind)).as_str(), expected);
        }
    }

    #[test]
    fn an_accepted_push_is_adopted_in_silence_and_still_baselines_the_next() {
        // The sequence moves on acceptance too — the phone needs a positive
        // answer, or an unmoved counter would be indistinguishable from a
        // watch that never replied. The wrist must stay quiet for it (§400's
        // rule: a confirmation banner teaches runners to wait for one that
        // failure also never showed), AND the adoption must leave the engine
        // able to catch the very next refusal.
        let mut e = AlertEngine::new();
        assert_eq!(
            e.on_update(&pushed(PushKind::Roadbook, 4, true, 10), None, 10),
            None
        );
        assert_eq!(
            e.on_update(&pushed(PushKind::Roadbook, 5, true, 11), None, 11),
            None,
            "an accepted push is not news"
        );
        assert_eq!(
            e.on_update(&pushed(PushKind::Roadbook, 6, false, 12), None, 12),
            Some(Alert::PushRejected(PushKind::Roadbook))
        );
    }

    #[test]
    fn a_second_rejection_of_a_different_push_replaces_the_queued_kind() {
        // One slot, one pending kind. A workout refusal queued behind a zone
        // banner then followed by a roadbook refusal must show the ROADBOOK —
        // the newer truth, and the one whose re-push is still owed. Showing
        // the stale kind would send the runner to re-push the wrong thing.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(
            e.on_update(&pushed(PushKind::Workout, 0, false, 10), None, 10),
            None
        );
        assert_eq!(
            e.on_update(&pushed(PushKind::Workout, 1, false, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&pushed(PushKind::Roadbook, 2, false, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let after = 11 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(
                &pushed(PushKind::Roadbook, 2, false, after),
                Some(150),
                after
            ),
            Some(Alert::PushRejected(PushKind::Roadbook))
        );
    }

    #[test]
    fn a_cutoff_banner_leads_a_course_rejection_which_is_owed_the_next_slot() {
        // The cutoff warns the race is being lost now; the stale course gets
        // expensive at the next fork — sooner than a front, later than the
        // cutoff. Both raised on one tick: cutoff first, rejection re-queued.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&rejected(0, 10), None, 10), None);
        let both = Snapshot {
            cutoff: cut(CutoffEtaStatus::Behind, 11).cutoff,
            ..rejected(1, 11)
        };
        assert_eq!(e.on_update(&both, None, 11), Some(Alert::CutoffBehind));
        let t = 11 + ALERT_TTL_S;
        let hold = Snapshot {
            cutoff: cut(CutoffEtaStatus::Behind, t).cutoff,
            ..rejected(1, t)
        };
        assert_eq!(
            e.on_update(&hold, None, t),
            Some(Alert::PushRejected(PushKind::Course))
        );
    }

    #[test]
    fn a_course_rejection_leads_the_storm_and_never_loses_to_fuel() {
        let mut e = AlertEngine::new();
        e.set_storm_alert(true);
        e.set_fuel_intervals(300, 300);
        assert_eq!(e.on_update(&rejected(0, 10), None, 10), None);
        let both = Snapshot {
            push_outcome: rejected(1, 300).push_outcome,
            ..stormy(StormTrend::Storm, 300)
        };
        assert_eq!(
            e.on_update(&both, None, 300),
            Some(Alert::PushRejected(PushKind::Course))
        );
        let t = 300 + ALERT_TTL_S;
        let hold = Snapshot {
            push_outcome: rejected(1, t).push_outcome,
            ..stormy(StormTrend::Storm, t)
        };
        assert_eq!(e.on_update(&hold, None, t), Some(Alert::Storm));
    }

    #[test]
    fn a_zone_banner_displaces_a_course_rejection_which_re_queues_rather_than_dropping() {
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&rejected(0, 10), None, 10), None);
        assert_eq!(
            e.on_update(&rejected(1, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        let after = 11 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&rejected(1, after), Some(150), after),
            Some(Alert::PushRejected(PushKind::Course)),
            "the displaced rejection came back"
        );
    }

    #[test]
    fn a_run_boundary_clears_a_pending_loss_and_rejection() {
        // Both are run-scoped like the cutoff pair: between runs the idle
        // surfaces carry the standing truth, so nothing raised in one run is
        // owed to the next.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&rec(10), None, 10), None);
        let both = Snapshot {
            run_lost_seq: 1,
            ..rejected(1, 11)
        };
        assert_eq!(e.on_update(&both, Some(160), 11), Some(Alert::ZoneAbove(4)));
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 12), None, 12),
            None
        );
        assert_eq!(e.on_update(&rec(20), None, 30), None);
    }

    fn thinned(factor: u8, moving_s: u32) -> Snapshot {
        Snapshot {
            track_thinning: factor,
            ..rec(moving_s)
        }
    }

    #[test]
    fn a_thinned_track_announces_itself_and_every_further_halving_again() {
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&thinned(1, 10), None, 10), None);
        assert_eq!(
            e.on_update(&thinned(2, 11), None, 11),
            Some(Alert::TrackThinned)
        );
        assert_eq!(banner(Alert::TrackThinned).as_str(), "! TRK RES");
        // A steady factor is not news — the resolution already dropped, and
        // the Distance page carries it from here.
        let t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&thinned(2, t), None, t), None);
        // The next halving is a new fact and gets its own banner: the record
        // is coarser again, and each doubling costs about as long as the run so
        // far, so there is nothing left to rate-limit.
        assert_eq!(
            e.on_update(&thinned(4, t + 1), None, t + 1),
            Some(Alert::TrackThinned)
        );
    }

    #[test]
    fn a_thinning_factor_falling_back_to_full_never_fires() {
        // A stored track never recovers its resolution, so a fall is
        // `Recorder::start`'s reset and never a recovery to announce.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&thinned(1, 10), None, 10), None);
        assert_eq!(
            e.on_update(&thinned(4, 11), None, 11),
            Some(Alert::TrackThinned)
        );
        let t = 11 + ALERT_TTL_S;
        assert_eq!(e.on_update(&thinned(1, t), None, t), None);
        assert_eq!(e.on_update(&thinned(1, t + 1), None, t + 1), None);
    }

    #[test]
    fn a_lost_run_notice_outranks_a_thinned_track_which_is_owed_the_next_slot() {
        // Both are irreversible and ask for no decision, so the order is what
        // was lost: run-lost is a whole race gone, a thin keeps the whole run
        // at half the fidelity. Raised on one tick, the loss shows first.
        let mut e = AlertEngine::new();
        assert_eq!(e.on_update(&lost(0, 10), None, 10), None);
        let both = Snapshot {
            track_thinning: 2,
            ..lost(1, 11)
        };
        assert_eq!(e.on_update(&both, None, 11), Some(Alert::RunLost));
        let t = 11 + ALERT_TTL_S;
        let hold = Snapshot {
            track_thinning: 2,
            ..lost(1, t)
        };
        assert_eq!(e.on_update(&hold, None, t), Some(Alert::TrackThinned));
    }

    #[test]
    fn a_thinned_track_notice_leads_the_fuel_reminders() {
        // The new bottom of the re-queued class: above fuel for run-lost's one
        // reason — a gel comes round a cadence later, a halving is announced
        // once or never.
        let mut e = AlertEngine::new();
        e.set_fuel_intervals(300, 300);
        assert_eq!(e.on_update(&thinned(1, 10), None, 10), None);
        assert_eq!(
            e.on_update(&thinned(2, 300), None, 300),
            Some(Alert::TrackThinned)
        );
        let t = 300 + ALERT_TTL_S;
        assert_eq!(e.on_update(&thinned(2, t), None, t), Some(Alert::Eat));
    }

    #[test]
    fn a_zone_banner_displaces_a_thinned_track_notice_which_re_queues_rather_than_dropping() {
        // Where it parts from the signal-void pair: the `AUTO` tag rides every
        // page, the thinning factor rides row 7 of one — so dropping the
        // banner would return the change to the silence a runner parked on Nav
        // was already in.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&thinned(1, 10), None, 10), None);
        assert_eq!(
            e.on_update(&thinned(2, 11), None, 11),
            Some(Alert::TrackThinned)
        );
        assert_eq!(
            e.on_update(&thinned(2, 12), Some(160), 12),
            Some(Alert::ZoneAbove(4))
        );
        let t = 12 + ALERT_TTL_S;
        assert_eq!(
            e.on_update(&thinned(2, t), Some(150), t),
            Some(Alert::TrackThinned),
            "the displaced resolution notice came back"
        );
    }

    #[test]
    fn a_run_boundary_clears_a_pending_thinned_track_notice() {
        // Run-scoped like the cutoff pair and unlike the storm: decimation is a
        // property of THIS run's flash slot. The next run stages into its own
        // slot at full resolution, so re-announcing the last one's factor would
        // describe storage nothing is writing to any more.
        let mut e = AlertEngine::new();
        e.set_zone_ceiling(Some(3));
        assert_eq!(e.on_update(&thinned(1, 10), None, 10), None);
        // Raised but blocked, so it is still queued at the boundary.
        assert_eq!(
            e.on_update(&thinned(2, 11), Some(160), 11),
            Some(Alert::ZoneAbove(4))
        );
        assert_eq!(
            e.on_update(&snap(RecordState::Finished, 12), None, 12),
            None
        );
        assert_eq!(e.on_update(&thinned(1, 20), None, 30), None);
        // The baseline reset with it, so the new run's OWN first thin fires.
        assert_eq!(
            e.on_update(&thinned(2, 31), None, 31),
            Some(Alert::TrackThinned)
        );
    }
}
