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

impl UnfedClass {
    /// Every class, for the drift guards below.
    pub const ALL: [UnfedClass; 5] = [
        UnfedClass::PhoneFed,
        UnfedClass::Sensor,
        UnfedClass::RunGate,
        UnfedClass::Settled,
        UnfedClass::WatchAction,
    ];

    /// The word a slot on a runner-composed screen ([`crate::screens`]) shows
    /// in place of a value it does not have.
    ///
    /// A glance page answers "why is this empty" with a whole [`Unfed::reason`]
    /// line and, where there is something to do, a [`Unfed::hint`] under it. A
    /// slot has neither — it is one value and a five-cell label in a layout
    /// drawing two or three of them — so the question is not *which reason* but
    /// *how much of one survives*. The answer is the class, because this enum is
    /// already cut by what the runner can do, and that is the only part of a
    /// reason a runner acts on.
    ///
    /// The alternative was a bare `--` in all five cases, and it is wrong on
    /// exactly the surface that cannot afford it: it collapses "your phone never
    /// sent this", "keep running", and "there is genuinely no climb here" into
    /// one shrug, with no body text to tell them apart. A runner who cannot
    /// separate a broken sync from a settled answer either chases a fault that
    /// does not exist or ignores one that does.
    ///
    /// These are words, so they draw in the text face rather than a numeral one
    /// — [`crate::ui_frame::hero_band`] picks on glyphs, and `DONE` on a
    /// finished workout step is the precedent. That is the point: a slot showing
    /// a word is visibly not a slot showing a measurement, before it is read.
    pub const fn slot_token(self) -> &'static str {
        match self {
            UnfedClass::PhoneFed => "SYNC",
            UnfedClass::Sensor => "WAIT",
            UnfedClass::RunGate => "RUN",
            UnfedClass::Settled => "NONE",
            UnfedClass::WatchAction => "MARK",
        }
    }
}

/// The remedy line that follows every [`UnfedClass::PhoneFed`] reason.
pub const PHONE_SYNC_HINT: &str = "SET VIA PHONE SYNC";

/// The remedy line for [`Unfed::NoWaypoints`] — the §357 gesture spelled out.
/// A hold has no discoverable affordance on a five-button watch, so the empty
/// page is the only place the runner can learn it exists.
pub const WAYPOINT_MARK_HINT: &str = "HOLD BTN5 TO MARK";

/// The remedy line for [`Unfed::NoTimer`] — the §375 modal, named with the key
/// that opens it and the surface it opens on. Both halves are load-bearing: the
/// timer is armed from the idle face and nowhere else, so a runner told only
/// "BTN2" would hunt for it mid-run, where that key arms the stop.
pub const TIMER_SET_HINT: &str = "BTN2 ON IDLE FACE";

/// The complete set of reasons a page may give for an empty body.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Unfed {
    /// The phone has not given the watch this datum.
    NotSynced,
    /// No altitude sample has landed yet (no barometer, or pre-first-sample).
    AwaitingBaro,
    /// The optical sensor has not produced a first beat (off-wrist, or still
    /// acquiring). A glance page never needed this one — the zones page draws
    /// `HR --` inside an otherwise-fed body — but a slot that IS the pulse has
    /// no body to be fed, so it needs a reason of its own.
    AwaitingPulse,
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
    /// No countdown or stopwatch has been started, so there is no clock to
    /// read (§375).
    NoTimer,
    /// No GPS altitude has corroborated the barometer recently, so the pressure
    /// tendency has nothing independent to compensate against and a climb would
    /// be indistinguishable from a front (§376).
    NoStormReference,
    /// The barometer is corroborated, but too little of the trend window is
    /// banked to state a tendency from (§376).
    StormBuilding,
}

impl Unfed {
    /// Every sanctioned reason. The register a drift test asserts against, so
    /// a new page cannot invent wording without adding a variant here and
    /// choosing its class.
    pub const ALL: [Unfed; 17] = [
        Unfed::NotSynced,
        Unfed::AwaitingBaro,
        Unfed::AwaitingPulse,
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
        Unfed::NoTimer,
        Unfed::NoStormReference,
        Unfed::StormBuilding,
    ];

    /// What the runner can do about it.
    pub const fn class(self) -> UnfedClass {
        match self {
            Unfed::NotSynced => UnfedClass::PhoneFed,
            Unfed::AwaitingBaro
            | Unfed::AwaitingPulse
            | Unfed::AwaitingFix
            | Unfed::NoStormReference
            | Unfed::StormBuilding => UnfedClass::Sensor,
            Unfed::NeedDistance | Unfed::NeedOneKm => UnfedClass::RunGate,
            Unfed::NoRaceBand
            | Unfed::NoCutoffAhead
            | Unfed::LastAidPassed
            | Unfed::NoCourseElevation
            | Unfed::MidnightSun
            | Unfed::PolarNight
            | Unfed::NoClimb => UnfedClass::Settled,
            Unfed::NoWaypoints | Unfed::NoTimer => UnfedClass::WatchAction,
        }
    }

    /// The reason line, in the face's all-caps register and inside its column
    /// budget (pinned by the const assert below).
    pub const fn reason(self) -> &'static str {
        match self {
            Unfed::NotSynced => "NOT SYNCED",
            Unfed::AwaitingBaro => "AWAITING BARO",
            Unfed::AwaitingPulse => "AWAITING PULSE",
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
            Unfed::NoTimer => "NO TIMER SET",
            Unfed::NoStormReference => "NO ALT REFERENCE",
            Unfed::StormBuilding => "TREND BUILDING",
        }
    }

    /// The follow-up line, present only where the runner has something to do
    /// off the watch — the three other classes resolve themselves, and telling
    /// a runner to sync a course that IS synced would be a lie.
    /// A [`UnfedClass::WatchAction`] hint names the gesture, so it is per-reason
    /// rather than per-class: the two watch actions live on different keys and
    /// different surfaces, and one hint for both would send half the runners to
    /// the wrong button.
    pub const fn hint(self) -> Option<&'static str> {
        match self {
            Unfed::NoWaypoints => Some(WAYPOINT_MARK_HINT),
            Unfed::NoTimer => Some(TIMER_SET_HINT),
            _ => match self.class() {
                UnfedClass::PhoneFed => Some(PHONE_SYNC_HINT),
                UnfedClass::Sensor
                | UnfedClass::RunGate
                | UnfedClass::Settled
                | UnfedClass::WatchAction => None,
            },
        }
    }
}

const _: () = {
    assert!(PHONE_SYNC_HINT.len() <= crate::face::COLS);
    assert!(WAYPOINT_MARK_HINT.len() <= crate::face::COLS);
    assert!(TIMER_SET_HINT.len() <= crate::face::COLS);
    let mut i = 0;
    while i < Unfed::ALL.len() {
        assert!(Unfed::ALL[i].reason().len() <= crate::face::COLS);
        i += 1;
    }
    // A token stands where a slot's value stands, so it may be no wider than
    // the label sharing that row — the budget a slot is built around.
    let mut i = 0;
    while i < UnfedClass::ALL.len() {
        assert!(!UnfedClass::ALL[i].slot_token().is_empty());
        assert!(UnfedClass::ALL[i].slot_token().len() <= crate::screens::SLOT_LABEL_CELLS);
        i += 1;
    }
};

#[cfg(test)]
mod tests {
    use super::*;

    /// This module's own source, so the two hand-written `ALL` arrays can be
    /// held against the enums they claim to enumerate. `class()`, `reason()`
    /// and `slot_token()` are exhaustive matches, so a new variant forces those
    /// to be updated; `ALL` is a plain array and forces nothing, while the
    /// `const` block asserting every reason fits the panel walks it. A variant
    /// added and not registered is therefore one whose width nothing measures,
    /// on the module whose entire purpose is that every empty page speaks one
    /// vocabulary.
    const SRC: &str = include_str!("unfed.rs");

    /// The variant names inside `<decl> { … }`, as spelled in the source.
    /// Doc comments, attributes and blank lines are dropped; anything left that
    /// is not a bare identifier is a shape this parse cannot speak for, and is
    /// returned as-is so the caller's own assertion fails loudly rather than
    /// the parse silently reporting fewer variants than there are.
    fn variant_names(decl: &str) -> Vec<&'static str> {
        let at = SRC
            .find(decl)
            .expect("enum declaration not found in source");
        let open = at + SRC[at..].find('{').expect("no brace after the declaration");
        let mut depth = 0usize;
        let mut end = None;
        for (i, c) in SRC[open..].char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(open + i);
                        break;
                    }
                }
                _ => {}
            }
        }
        SRC[open + 1..end.expect("unbalanced enum body")]
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with("//") && !l.starts_with('#'))
            .map(|l| l.trim_end_matches(','))
            .collect()
    }

    /// The `Enum::Variant` names listed inside the body of an `ALL` array.
    fn registered_names(decl: &str, prefix: &str) -> Vec<&'static str> {
        let at = SRC.find(decl).expect("ALL declaration not found in source");
        let end = at + SRC[at..].find("];").expect("unterminated ALL array");
        SRC[at..end]
            .lines()
            .map(str::trim)
            .filter_map(|l| l.strip_prefix(prefix))
            .map(|l| l.trim_end_matches(','))
            .collect()
    }

    fn is_identifier(s: &str) -> bool {
        !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric())
    }

    #[test]
    fn every_unfed_variant_is_registered_in_all() {
        let declared = variant_names("pub enum Unfed {");
        let registered = registered_names("pub const ALL: [Unfed;", "Unfed::");
        assert!(
            declared.len() >= 17 && declared.iter().all(|n| is_identifier(n)),
            "the enum body no longer parses as a list of bare variants ({declared:?}) — \
             this check would report agreement it cannot see"
        );
        assert_eq!(
            declared, registered,
            "`Unfed::ALL` does not list every variant of `enum Unfed`, in order. \
             The width assertion in the const block walks ALL, so an unregistered \
             variant ships a reason of any width and draws off the panel."
        );
        assert_eq!(declared.len(), Unfed::ALL.len());
    }

    #[test]
    fn every_unfed_class_variant_is_registered_in_all() {
        let declared = variant_names("pub enum UnfedClass {");
        let registered = registered_names("pub const ALL: [UnfedClass;", "UnfedClass::");
        assert!(
            declared.len() >= 5 && declared.iter().all(|n| is_identifier(n)),
            "the enum body no longer parses as a list of bare variants ({declared:?})"
        );
        assert_eq!(declared, registered);
        assert_eq!(declared.len(), UnfedClass::ALL.len());
    }

    #[test]
    fn no_two_reasons_read_the_same() {
        // The module exists so one situation has one wording. Two variants
        // sharing a line defeats that from the other direction: the runner
        // reads the same sentence for two different causes and cannot act on
        // either.
        for (i, a) in Unfed::ALL.iter().enumerate() {
            for b in &Unfed::ALL[i + 1..] {
                assert_ne!(
                    a.reason(),
                    b.reason(),
                    "{a:?} and {b:?} share a reason line"
                );
                assert_ne!(a, b, "{a:?} is listed twice in Unfed::ALL");
            }
            assert!(!a.reason().is_empty(), "{a:?} has no reason line");
        }
    }

    #[test]
    fn no_two_classes_share_a_slot_token() {
        for (i, a) in UnfedClass::ALL.iter().enumerate() {
            for b in &UnfedClass::ALL[i + 1..] {
                assert_ne!(
                    a.slot_token(),
                    b.slot_token(),
                    "{a:?} and {b:?} share a slot token"
                );
                assert_ne!(a, b, "{a:?} is listed twice in UnfedClass::ALL");
            }
        }
    }

    #[test]
    fn a_hint_is_offered_exactly_where_the_runner_has_something_to_do() {
        for r in Unfed::ALL {
            match r.class() {
                UnfedClass::PhoneFed => assert_eq!(r.hint(), Some(PHONE_SYNC_HINT)),
                UnfedClass::WatchAction => assert!(
                    r.hint().is_some_and(|h| h != PHONE_SYNC_HINT),
                    "{r:?} is a watch action, so its hint must name the gesture"
                ),
                UnfedClass::Sensor | UnfedClass::RunGate | UnfedClass::Settled => assert_eq!(
                    r.hint(),
                    None,
                    "{r:?} resolves itself, so telling the runner to act is a lie"
                ),
            }
        }
    }
}
