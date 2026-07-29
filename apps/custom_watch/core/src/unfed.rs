//! The words a page uses when it has nothing to show.
//!
//! The watch's honesty rule is that a surface with no data says so rather than
//! rendering zeros a runner would read as a real measurement. Keeping that rule
//! needs one vocabulary, not one phrase per page: a runner who meets
//! `NO CUTOFFS` on one page and `NO COURSE` on the next cannot tell whether the
//! two mean the same thing. So every empty body's reason line comes from here
//! and no page in [`crate::face`] spells its own.
//!
//! The classes are cut by **what the runner can do about it**, because that is
//! the only distinction the words have to carry:
//!
//! - [`UnfedClass::PhoneFed`] — act on the phone. Note what the watch does NOT
//!   know here: it sees an absent field and nothing more, so it cannot tell
//!   "never configured" from "configured but not pushed yet" and must claim
//!   neither. That is why there is one [`Unfed::NotSynced`] rather than a
//!   `NO GOAL SET` beside it asserting a cause the firmware cannot observe.
//! - [`UnfedClass::Sensor`] — wait; a local sensor has not produced a first
//!   reading and will without the runner doing anything.
//! - [`UnfedClass::RunGate`] — run on; the page needs more of *this* run.
//! - [`UnfedClass::Settled`] — nothing to do. The page IS fed and the honest
//!   answer is none, so the wording must not read as a failed sync.
//! - [`UnfedClass::WatchAction`] — act on the watch. The one class whose datum
//!   neither the phone nor a sensor nor the run itself supplies: the runner
//!   creates it with a button. Its hint therefore names the gesture, because a
//!   surface that only says "empty" about a thing only a hidden press can fill
//!   is a surface nobody ever fills.
//!
//! An absent *value* inside an otherwise-fed row keeps the `--` marker instead
//! (`HR --`, `ETA --`, `WEAR --`); this module governs whole reason LINES.

/// What a runner can do about an empty page — the axis the wording follows.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum UnfedClass {
    /// The phone owns the datum and the watch has not been given it.
    PhoneFed,
    /// A local sensor has not produced its first reading yet.
    Sensor,
    /// The run has not yet met the gate the page needs.
    RunGate,
    /// Fed and computed; the honest answer is none.
    Settled,
    /// The runner fills this one from the watch itself.
    WatchAction,
}

/// The remedy line that follows every [`UnfedClass::PhoneFed`] reason.
pub const PHONE_SYNC_HINT: &str = "SET VIA PHONE SYNC";

/// The remedy line for [`Unfed::NoWaypoints`] — the §357 gesture spelled out.
/// A hold has no discoverable affordance on a five-button watch, so the empty
/// page is the only place the runner can learn it exists.
pub const WAYPOINT_MARK_HINT: &str = "HOLD BTN5 TO MARK";

/// The complete set of reasons a page may give for an empty body.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Unfed {
    /// The phone has not given the watch this datum.
    NotSynced,
    /// No altitude sample has landed yet (no barometer, or pre-first-sample).
    AwaitingBaro,
    /// No position has been projected onto the loaded course yet.
    AwaitingFix,
    /// The run has banked no distance to derive from.
    NeedDistance,
    /// The run is shorter than the projection's minimum anchor.
    NeedOneKm,
    /// The run's distance falls between race-distance bands.
    NoRaceBand,
    /// The course carries cut-offs, and the runner is past the last one.
    NoCutoffAhead,
    /// The fuel plan's final refill is behind the runner.
    LastAidPassed,
    /// A course was pushed, without per-point elevation.
    NoCourseElevation,
    /// The sun does not set at this latitude today — there is no sunset to
    /// count down to.
    MidnightSun,
    /// The sun does not rise at this latitude today — there is no sunrise to
    /// count down to.
    PolarNight,
    /// Nothing has been marked, so there is no position to navigate back to.
    NoWaypoints,
    /// Neither underfoot nor ahead is there an ascent to report.
    NoClimb,
}

impl Unfed {
    /// Every sanctioned reason. The register a drift test asserts against, so
    /// a new page cannot invent wording without adding a variant here and
    /// choosing its class.
    pub const ALL: [Unfed; 13] = [
        Unfed::NotSynced,
        Unfed::AwaitingBaro,
        Unfed::AwaitingFix,
        Unfed::NeedDistance,
        Unfed::NeedOneKm,
        Unfed::NoRaceBand,
        Unfed::NoCutoffAhead,
        Unfed::LastAidPassed,
        Unfed::NoCourseElevation,
        Unfed::MidnightSun,
        Unfed::PolarNight,
        Unfed::NoWaypoints,
        Unfed::NoClimb,
    ];

    /// What the runner can do about it.
    pub const fn class(self) -> UnfedClass {
        match self {
            Unfed::NotSynced => UnfedClass::PhoneFed,
            Unfed::AwaitingBaro | Unfed::AwaitingFix => UnfedClass::Sensor,
            Unfed::NeedDistance | Unfed::NeedOneKm => UnfedClass::RunGate,
            Unfed::NoRaceBand
            | Unfed::NoCutoffAhead
            | Unfed::LastAidPassed
            | Unfed::NoCourseElevation
            | Unfed::MidnightSun
            | Unfed::PolarNight
            | Unfed::NoClimb => UnfedClass::Settled,
            Unfed::NoWaypoints => UnfedClass::WatchAction,
        }
    }

    /// The reason line, in the face's all-caps register and inside its column
    /// budget (pinned by the const assert below).
    pub const fn reason(self) -> &'static str {
        match self {
            Unfed::NotSynced => "NOT SYNCED",
            Unfed::AwaitingBaro => "AWAITING BARO",
            Unfed::AwaitingFix => "AWAITING FIX",
            Unfed::NeedDistance => "NEED DISTANCE",
            Unfed::NeedOneKm => "NEED 1 KM",
            Unfed::NoRaceBand => "NO RACE BAND",
            Unfed::NoCutoffAhead => "NO CUTOFF AHEAD",
            Unfed::LastAidPassed => "LAST AID PASSED",
            Unfed::NoCourseElevation => "NO COURSE ELEV",
            Unfed::MidnightSun => "MIDNIGHT SUN",
            Unfed::PolarNight => "POLAR NIGHT",
            Unfed::NoWaypoints => "NO WAYPOINTS",
            Unfed::NoClimb => "NO CLIMB",
        }
    }

    /// The follow-up line, present only where the runner has something to do
    /// off the watch — the three other classes resolve themselves, and telling
    /// a runner to sync a course that IS synced would be a lie.
    pub const fn hint(self) -> Option<&'static str> {
        match self.class() {
            UnfedClass::PhoneFed => Some(PHONE_SYNC_HINT),
            UnfedClass::WatchAction => Some(WAYPOINT_MARK_HINT),
            UnfedClass::Sensor | UnfedClass::RunGate | UnfedClass::Settled => None,
        }
    }
}

const _: () = {
    assert!(PHONE_SYNC_HINT.len() <= crate::face::COLS);
    assert!(WAYPOINT_MARK_HINT.len() <= crate::face::COLS);
    let mut i = 0;
    while i < Unfed::ALL.len() {
        assert!(Unfed::ALL[i].reason().len() <= crate::face::COLS);
        i += 1;
    }
};
