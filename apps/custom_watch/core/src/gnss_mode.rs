//! Selectable GNSS recording modes — the tier-1 *software* half of the
//! "Selectable GNSS / battery modes" surface every ultra watch ships
//! (`docs/custom_watch/roadmap.md`).
//!
//! A mode decides how often the GPS task forwards a fix to the recorder /
//! face / phone consumers **while a run is recording**, generalising the
//! existing idle fix de-rate in `app/src/tasks/gps.rs`. Tier-1's u-blox
//! MAX-M10S keeps streaming NMEA regardless — the UART drain is untouched —
//! so on the bench a throttled mode saves only the downstream wakes. Powering
//! the module itself down between fixes (u-blox power-save / backup mode, or
//! a load switch) is the hardware-gated tier-2 win this mode surface plugs
//! into (`docs/custom_watch/performance_path.md` § GNSS, README § Power
//! discipline).
//!
//! Interval choices, from real-watch precedent:
//! - [`Performance`](GnssMode::Performance) — every ~1 s fix, the
//!   every-second recording default of any modern watch. Full track fidelity.
//! - [`Balanced`](GnssMode::Balanced) — one fix per 15 s: ~45 m between fixes
//!   at ultra pace (~3 m/s), so switchbacks stay recognisable while most of
//!   the duty-cycle saving is already banked (the saving saturates quickly —
//!   see the estimate derivation below).
//! - [`Expedition`](GnssMode::Expedition) — one fix per 60 s, the Garmin
//!   UltraTrac / COROS UltraMax class: straight-line legs of 180–240 m at
//!   ultra pace, for multi-day efforts where hours beat track fidelity.
//!
//! Battery estimates are **projections, not measurements** — the tier-1 DK
//! cannot measure ultra-watch power at all (`performance_path.md`; PPK2
//! measurements land with parts). Derivation: the Performance baseline is
//! `vision.md`'s ~110 h single-band tier-2 target (the Enduro-3-matching
//! headline, req #1). For the throttled modes, take the GNSS receiver as
//! roughly half the recording-time draw (`performance_path.md` ranks GNSS
//! duty-cycling a 2–3× lever on GPS power) and charge each duty-cycled fix
//! ~3 s of receiver-on time for re-acquisition: whole-watch factor =
//! 1 / (0.5 + 0.5 · 3 / interval) ≈ 1.7× at 15 s and ≈ 1.9× at 60 s, then
//! round against what the 1-fix-per-60-s class actually ships (Suunto 9:
//! 25 h → 50 h; Garmin Enduro 2: 150 h → 300 h UltraTrac; Fenix 7X:
//! 89 h → 122 h at the conservative end). Hence ~110 / ~180 / ~220 h.

/// A user-selectable GNSS recording mode, cycled by BTN3 on the idle face
/// (mid-run BTN3 cycles the data pages instead — see [`crate::button`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GnssMode {
    /// Every ~1 s fix — full track fidelity, the every-second default.
    #[default]
    Performance,
    /// One fix per 15 s — most of the duty-cycle saving, switchbacks intact.
    Balanced,
    /// One fix per 60 s — UltraTrac-class, multi-day battery over fidelity.
    Expedition,
}

impl GnssMode {
    /// The next mode in BTN3's cycle order, wrapping back to the start.
    pub fn next(self) -> Self {
        match self {
            GnssMode::Performance => GnssMode::Balanced,
            GnssMode::Balanced => GnssMode::Expedition,
            GnssMode::Expedition => GnssMode::Performance,
        }
    }

    /// Minimum seconds between fixes forwarded while recording. `1` means
    /// every fix (fixes arrive ~1 Hz from the MAX-M10S).
    pub const fn fix_interval_s(self) -> u32 {
        match self {
            GnssMode::Performance => 1,
            GnssMode::Balanced => 15,
            GnssMode::Expedition => 60,
        }
    }

    /// Short display tag for the face's mode rows; at most 4 characters so
    /// every row that appends it stays inside the text grid.
    pub const fn label(self) -> &'static str {
        match self {
            GnssMode::Performance => "PERF",
            GnssMode::Balanced => "BAL",
            GnssMode::Expedition => "EXP",
        }
    }

    /// Projected recording hours on the tier-2 target hardware — a *battery
    /// estimate for the mode picker*, not a measurement (see the module docs
    /// for the derivation; the tier-1 DK cannot measure power).
    pub const fn battery_est_h(self) -> u32 {
        match self {
            GnssMode::Performance => 110,
            GnssMode::Balanced => 180,
            GnssMode::Expedition => 220,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_performance() {
        assert_eq!(GnssMode::default(), GnssMode::Performance);
        assert_eq!(GnssMode::default().fix_interval_s(), 1);
    }

    #[test]
    fn next_cycles_every_mode_and_wraps() {
        assert_eq!(GnssMode::Performance.next(), GnssMode::Balanced);
        assert_eq!(GnssMode::Balanced.next(), GnssMode::Expedition);
        assert_eq!(GnssMode::Expedition.next(), GnssMode::Performance);
        let mut m = GnssMode::default();
        let mut seen = [m, m.next(), m.next().next()];
        seen.sort_by_key(|q| *q as u8);
        assert_eq!(
            seen,
            [
                GnssMode::Performance,
                GnssMode::Balanced,
                GnssMode::Expedition
            ]
        );
        for _ in 0..3 {
            m = m.next();
        }
        assert_eq!(m, GnssMode::default());
    }

    #[test]
    fn throttled_modes_trade_fix_rate_for_projected_hours() {
        // The whole point of the picker: a longer interval must never project
        // fewer hours, and vice versa.
        let ordered = [
            GnssMode::Performance,
            GnssMode::Balanced,
            GnssMode::Expedition,
        ];
        for pair in ordered.windows(2) {
            assert!(pair[0].fix_interval_s() < pair[1].fix_interval_s());
            assert!(pair[0].battery_est_h() < pair[1].battery_est_h());
        }
    }

    #[test]
    fn expedition_is_the_ultratrac_class() {
        // Pinned: 60 s is the UltraTrac / UltraMax precedent the module docs
        // derive the estimates from; drifting it silently would invalidate them.
        assert_eq!(GnssMode::Expedition.fix_interval_s(), 60);
        assert_eq!(GnssMode::Balanced.fix_interval_s(), 15);
    }

    #[test]
    fn labels_fit_the_face_rows() {
        for m in [
            GnssMode::Performance,
            GnssMode::Balanced,
            GnssMode::Expedition,
        ] {
            assert!(!m.label().is_empty());
            assert!(m.label().len() <= 4, "label too wide: {}", m.label());
        }
    }
}
