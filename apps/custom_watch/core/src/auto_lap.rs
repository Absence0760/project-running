//! The auto-lap trigger: what closes a lap when nobody presses BTN5.
//!
//! The recorder shipped with a hard-coded 1 km boundary. This turns it into a
//! chosen one — a closed catalogue of rungs rather than an arbitrary distance,
//! for two reasons that are specific to this device:
//!
//! - **The flash lap budget is 64 records** ([`crate::run_store::MAX_STORED_LAPS`]).
//!   A 1 km auto-lap on a 100 km run asks for 100 laps and loses the last 36 to
//!   the cap, so an ultra runner needs coarser rungs (and `Off`) to keep the
//!   splits they do bank. An open "any distance" field would let a runner set
//!   50 m and exhaust the budget inside 3.2 km with nothing warning them.
//! - **The byte has to fit the places the choice is carried**: one wire byte in
//!   the `SET1` frame and three spare bits of the `CFG1` flags byte, so the
//!   trigger survives a mid-race power cycle without a config-record version
//!   bump.
//!
//! Each rung names its own unit. The watch has no km/mi display preference to
//! derive one from — every render surface is metric today — so a mile rung is
//! an explicit rung, and it is the phone (which does hold `preferred_unit`)
//! that picks which one to push.
//!
//! **A paused runner never triggers an auto-lap on either axis.** Distance is
//! structural: it only accrues on a fix the recorder accepts as movement.
//! Time is a choice — the budget is *moving* time, the same axis the fuel arms
//! bank on (§ 214), not the elapsed clock. An elapsed-clock auto-lap turns a
//! 40-minute sleep-station stop into eight empty laps at the 5-minute rung, and
//! on a 64-record budget those empty laps *displace real ones*. See § 374.

use crate::race_day::MILE_METRES;

/// Largest wire byte any rung encodes to. The `CFG1` flags byte carries the
/// trigger in three bits, so this is the ceiling that keeps that packing valid.
pub const AUTO_LAP_MAX_BYTE: u8 = 7;

/// The trigger a watch that was never pushed one runs — what the recorder did
/// before the trigger was configurable. Named separately from
/// [`AutoLap::default`] only because `Recorder::new` is a `const fn`.
pub const AUTO_LAP_DEFAULT: AutoLap = AutoLap::Km1;

/// What closes a lap without a button press.
///
/// [`AutoLap::Km1`] is the default because it is what the recorder did before
/// the trigger was configurable, and what every watch on the market ships with.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AutoLap {
    /// Only BTN5 closes a lap. The rung an ultra runner picks when the 64-lap
    /// store is worth spending on the splits they choose by hand.
    Off,
    #[default]
    Km1,
    Mi1,
    Km5,
    Mi5,
    /// Moving-time rungs. A paused or auto-paused stretch banks nothing toward
    /// them, so a stationary runner closes no laps at all.
    Min5,
    Min10,
    Min30,
}

impl AutoLap {
    /// Metres of ground a lap covers, or `None` for [`AutoLap::Off`] and every
    /// time rung. Exactly one of this and [`moving_s`](Self::moving_s) is
    /// `Some` for an armed trigger.
    pub const fn distance_m(self) -> Option<f64> {
        match self {
            Self::Km1 => Some(1000.0),
            Self::Mi1 => Some(MILE_METRES),
            Self::Km5 => Some(5000.0),
            Self::Mi5 => Some(5.0 * MILE_METRES),
            Self::Off | Self::Min5 | Self::Min10 | Self::Min30 => None,
        }
    }

    /// Seconds of **moving** time a lap covers, or `None` for [`AutoLap::Off`]
    /// and every distance rung.
    pub const fn moving_s(self) -> Option<u32> {
        match self {
            Self::Min5 => Some(300),
            Self::Min10 => Some(600),
            Self::Min30 => Some(1800),
            Self::Off | Self::Km1 | Self::Mi1 | Self::Km5 | Self::Mi5 => None,
        }
    }

    /// The face's label for the rung. Five columns at most: the Lap page pins
    /// it beside a split that can be nine columns wide (`999:59:59`), and a
    /// wider label would be silently dropped off the end of the row rather
    /// than wrapped.
    pub const fn label(self) -> &'static str {
        match self {
            Self::Off => "OFF",
            Self::Km1 => "1KM",
            Self::Mi1 => "1MI",
            Self::Km5 => "5KM",
            Self::Mi5 => "5MI",
            Self::Min5 => "5MIN",
            Self::Min10 => "10MIN",
            Self::Min30 => "30MIN",
        }
    }

    /// The wire / flash discriminant. Stable: the `SET1` frame and the `CFG1`
    /// record both key on it, so a reorder would silently re-point every
    /// trigger a phone has already pushed.
    pub const fn to_byte(self) -> u8 {
        match self {
            Self::Off => 0,
            Self::Km1 => 1,
            Self::Mi1 => 2,
            Self::Km5 => 3,
            Self::Mi5 => 4,
            Self::Min5 => 5,
            Self::Min10 => 6,
            Self::Min30 => 7,
        }
    }

    /// The rung a discriminant names, `None` for a byte that names none — a
    /// corrupt push or a stale flash record then leaves the current trigger
    /// standing rather than arming an arbitrary neighbour.
    pub const fn from_byte(b: u8) -> Option<Self> {
        match b {
            0 => Some(Self::Off),
            1 => Some(Self::Km1),
            2 => Some(Self::Mi1),
            3 => Some(Self::Km5),
            4 => Some(Self::Mi5),
            5 => Some(Self::Min5),
            6 => Some(Self::Min10),
            7 => Some(Self::Min30),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: [AutoLap; 8] = [
        AutoLap::Off,
        AutoLap::Km1,
        AutoLap::Mi1,
        AutoLap::Km5,
        AutoLap::Mi5,
        AutoLap::Min5,
        AutoLap::Min10,
        AutoLap::Min30,
    ];

    #[test]
    fn every_rung_round_trips_its_byte_and_stays_inside_the_flash_packing() {
        for t in ALL {
            assert_eq!(AutoLap::from_byte(t.to_byte()), Some(t));
            assert!(
                t.to_byte() <= AUTO_LAP_MAX_BYTE,
                "{t:?} overflows the CFG1 three-bit field"
            );
        }
    }

    #[test]
    fn a_byte_naming_no_rung_is_refused() {
        // Fail closed: a garbage byte must not resolve to a neighbouring rung,
        // or a bit-flip in flash silently changes how a race is split.
        for b in (AUTO_LAP_MAX_BYTE + 1)..=u8::MAX {
            assert_eq!(AutoLap::from_byte(b), None, "byte {b} resolved");
        }
    }

    #[test]
    fn an_armed_rung_answers_on_exactly_one_axis() {
        // The recorder runs both checks unconditionally, so a rung that
        // answered on both would close two laps per boundary.
        for t in ALL {
            let armed = t.distance_m().is_some() as u8 + t.moving_s().is_some() as u8;
            match t {
                AutoLap::Off => assert_eq!(armed, 0, "Off must arm nothing"),
                _ => assert_eq!(armed, 1, "{t:?} arms {armed} axes"),
            }
        }
    }

    #[test]
    fn the_mile_rungs_are_the_real_mile() {
        // Shared with `race_day::MILE_METRES` rather than re-typed, so a mile
        // lap and a mile split can never disagree about how long a mile is.
        assert_eq!(AutoLap::Mi1.distance_m(), Some(1609.344));
        assert_eq!(AutoLap::Mi5.distance_m(), Some(8046.72));
    }

    #[test]
    fn the_time_rungs_are_whole_minutes() {
        assert_eq!(AutoLap::Min5.moving_s(), Some(5 * 60));
        assert_eq!(AutoLap::Min10.moving_s(), Some(10 * 60));
        assert_eq!(AutoLap::Min30.moving_s(), Some(30 * 60));
    }

    #[test]
    fn the_default_is_the_kilometre_the_recorder_always_had() {
        assert_eq!(AutoLap::default(), AutoLap::Km1);
        assert_eq!(AUTO_LAP_DEFAULT, AutoLap::default());
        assert_eq!(AUTO_LAP_DEFAULT.distance_m(), Some(1000.0));
    }

    #[test]
    fn every_label_fits_the_lap_pages_trailing_field() {
        for t in ALL {
            assert!(!t.label().is_empty());
            assert!(t.label().len() <= 5, "{t:?} label too wide: {}", t.label());
        }
    }

    #[test]
    fn the_coarse_rungs_keep_an_ultra_inside_the_flash_lap_budget() {
        // The reason the catalogue is not just {off, 1 km, 1 mi}: a 100 km run
        // at 1 km loses laps to the 64-record cap, at 5 km it does not.
        let hundred_km = 100_000.0;
        let laps = |t: AutoLap| (hundred_km / t.distance_m().unwrap()) as u32;
        assert!(laps(AutoLap::Km1) > crate::run_store::MAX_STORED_LAPS);
        assert!(laps(AutoLap::Km5) <= crate::run_store::MAX_STORED_LAPS);
        assert!(laps(AutoLap::Mi5) <= crate::run_store::MAX_STORED_LAPS);
    }
}
