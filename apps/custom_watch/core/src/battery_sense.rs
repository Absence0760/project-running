//! SAADC counts → a publishable battery percent — the conversion + gate the
//! app's `battery` task runs on every sample, lifted out of the async task body
//! so the clamp and the park decision are host-tested.
//!
//! [`crate::battery`] owns the discharge curve and the plausibility band. This
//! module owns the two things the task adds on top: turning the raw conversion
//! result into millivolts for whichever internal input the cell is actually
//! reachable through, and folding the conversion's own domain plus that band
//! into an `Option` so *one* decision covers both the boot park (an unreadable
//! first reading means the task never publishes at all) and the mid-stream
//! blank (a reading that leaves the readable domain blanks the gauge rather
//! than rendering a percent off a regulator rail).
//!
//! **Which input sees the cell is a function of the supply mode, so the scale
//! is too.** The nRF52840 has two supply paths, and the cell sits behind a
//! different internal channel in each:
//!
//! - *Normal-voltage mode* — the supply feeds `VDD`, and the rail the SoC runs
//!   on **is** the cell. [`SupplySense::VddDirect`] reads the internal `VDD`
//!   input at the driver's default gain 1/6 against the 0.6 V reference, so
//!   full scale is [`FULL_SCALE_VDD_MV`]. That is *below* a fresh 4.2 V charge,
//!   so a full cell saturates and [`percent_from_raw`] reports it absent: a
//!   full 4.2 V cell and a 3.6 V one land on the same code, so the code is not
//!   3.6 V, it is *unknown*. VDD's own operating maximum is 3.6 V, so a cell on
//!   VDD is out of spec above the rail anyway — refusing is the honest answer
//!   here, not a limitation to design around.
//! - *High-voltage mode* — the supply feeds `VDDH`, and `VDD` becomes the
//!   output of an internal regulator fixed by `UICR.REGOUT0`. Reading `VDD`
//!   there measures the regulator, not the cell: it returns the same ~3.0 V at
//!   every state of charge, which the plausibility band then refuses, so the
//!   gauge is absent at *every* charge level rather than only near the top.
//!   The cell is reachable only through the internal `VDDHDIV5` input, a fifth
//!   of VDDH, so [`SupplySense::VddhDiv5`] carries that ×5 in its full scale.
//!
//! [`FULL_SCALE_VDDHDIV5_MV`] is 6000 mV rather than the 18000 mV the driver's
//! default gain 1/6 would give, because gain 1/2 puts VDDH's whole *legal*
//! range inside one converter span: VDDH's operating maximum is 5.5 V and its
//! absolute maximum 5.8 V, and a fifth of either is under the 1200 mV the
//! converter sees at full scale. So this input cannot saturate anywhere the SoC
//! is allowed to run — exactly the property whose absence was the `VddInput`
//! bug. The narrower span is also four times the resolution: a 4.2 V cell sits
//! at 70 % of the converter at 6000 mV full scale against 23 % at 18000 mV, and
//! every error fixed in LSBs (offset, INL) is that much smaller against the
//! reading.

use crate::battery::{percent_from_mv, plausible_mv};

/// Which internal SAADC input the `battery` task is reading the cell through,
/// and therefore what one conversion count is worth. Chosen at boot from the
/// supply mode the SoC actually came up in — see the module docs.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SupplySense {
    /// The internal `VDD` input at gain 1/6 — normal-voltage mode, where the
    /// cell is the rail.
    VddDirect,
    /// The internal `VDDHDIV5` input at gain 1/2 — high-voltage mode, where the
    /// cell is on VDDH and `VDD` is a regulator output that says nothing about
    /// it.
    VddhDiv5,
}

/// Millivolts of supply at full scale on the `VDD` input at gain 1/6 against
/// the 0.6 V internal reference — the embassy-nrf default.
pub const FULL_SCALE_VDD_MV: u32 = 3600;

/// Millivolts *of VDDH* at full scale on the `VDDHDIV5` input at gain 1/2: the
/// converter sees 1200 mV and the divider makes that a fifth of the rail.
pub const FULL_SCALE_VDDHDIV5_MV: u32 = 6000;

/// Conversion range of the 12-bit SAADC.
pub const ADC_COUNTS: u32 = 4096;

/// The converter's last step. Every input at or above the sense's full scale
/// lands here, so the code carries no information about how far above it the
/// rail actually sits.
pub const ADC_TOP_CODE: i16 = (ADC_COUNTS - 1) as i16;

impl SupplySense {
    /// Millivolts of *supply* this sense's full-scale code corresponds to.
    pub const fn full_scale_mv(self) -> u32 {
        match self {
            SupplySense::VddDirect => FULL_SCALE_VDD_MV,
            SupplySense::VddhDiv5 => FULL_SCALE_VDDHDIV5_MV,
        }
    }

    /// Whether a charger-fresh cell is inside this sense's readable span at
    /// all. False for [`SupplySense::VddDirect`], which is why the tier-1
    /// wiring must read through `VDDHDIV5`.
    pub const fn sees_a_full_cell(self) -> bool {
        self.full_scale_mv() > crate::battery::PLAUSIBLE_MAX_MV as u32
    }
}

/// Whether a conversion saturated, i.e. the input was at or above full scale and
/// its voltage is therefore unknown. Distinct from an implausible millivolt
/// figure ([`plausible_mv`]): on [`SupplySense::VddDirect`] the railed code's
/// millivolts (3599) sit squarely inside the 1S LiPo band, so the band alone
/// cannot catch it.
pub fn railed(raw: i16) -> bool {
    raw >= ADC_TOP_CODE
}

/// One SAADC conversion result → millivolts of supply, for the input it was
/// taken on. Negative counts (ground-noise wobble on an idle input) clamp to
/// zero rather than wrapping into a plausible-looking cell voltage.
pub fn mv_from_raw(sense: SupplySense, raw: i16) -> u16 {
    (i32::from(raw.max(0)) * sense.full_scale_mv() as i32 / ADC_COUNTS as i32) as u16
}

/// The percent this reading may honestly be published as, or `None` when the
/// rail is not a 1S LiPo at all ([`plausible_mv`]).
///
/// `None` is what parks the task at boot and blanks the gauge mid-stream: the
/// nRF52840 DK powered from USB regulates VDD to ~3.0 V, and mapping a
/// regulator rail onto the discharge curve would render a confident 0 % on the
/// face.
pub fn plausible_percent(mv: u16) -> Option<u8> {
    plausible_mv(mv).then(|| percent_from_mv(mv))
}

/// One SAADC conversion result → the percent it may honestly be published as —
/// the whole decision the `battery` task runs on every sample, for the input
/// `sense` says it was taken on.
///
/// `None` is the honest absent state and covers both ways a reading can be
/// unpublishable: the conversion saturated ([`railed`], so the voltage behind it
/// is unknown), or its millivolts are not a 1S LiPo at all
/// ([`plausible_percent`]). Either way nothing is published and every consumer
/// shows its absent state — no gauge icon, no `BAT` row.
pub fn percent_from_raw(sense: SupplySense, raw: i16) -> Option<u8> {
    if railed(raw) {
        return None;
    }
    plausible_percent(mv_from_raw(sense, raw))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::battery::{PLAUSIBLE_MAX_MV, PLAUSIBLE_MIN_MV};

    /// The conversion count a supply of `mv` produces on `sense`, rounded the
    /// way the converter does. Used to state the tests in volts rather than in
    /// codes; the inverse is [`mv_from_raw`], which every assertion still runs.
    fn raw_for(sense: SupplySense, mv: u32) -> i16 {
        (mv * ADC_COUNTS / sense.full_scale_mv()) as i16
    }

    #[test]
    fn the_conversion_spans_the_full_scale_on_both_senses() {
        assert_eq!(mv_from_raw(SupplySense::VddDirect, 0), 0);
        assert_eq!(mv_from_raw(SupplySense::VddDirect, 2048), 1800);
        assert_eq!(mv_from_raw(SupplySense::VddDirect, 4095), 3599);

        // VDDHDIV5 at gain 1/2: the converter sees a fifth of the rail against a
        // 1200 mV span, so one code is worth ~1.5 mV of VDDH.
        assert_eq!(mv_from_raw(SupplySense::VddhDiv5, 0), 0);
        assert_eq!(mv_from_raw(SupplySense::VddhDiv5, 2048), 3000);
        assert_eq!(mv_from_raw(SupplySense::VddhDiv5, 4095), 5998);
    }

    #[test]
    fn only_the_vddh_sense_can_see_a_charged_cell() {
        // The whole reason the tier-1 wiring reads through VDDHDIV5: 4.2 V is
        // above VDD's full scale, and above VDD's own 3.6 V operating maximum.
        assert!(!SupplySense::VddDirect.sees_a_full_cell());
        assert!(SupplySense::VddhDiv5.sees_a_full_cell());
        assert!(FULL_SCALE_VDD_MV < 4200);
        assert!(FULL_SCALE_VDDHDIV5_MV > u32::from(PLAUSIBLE_MAX_MV));
    }

    #[test]
    fn the_vddh_sense_cannot_rail_inside_the_supplys_legal_range() {
        // VDDH's operating maximum is 5.5 V and its absolute maximum 5.8 V. If
        // either could saturate the converter this fix would have reintroduced
        // the bug it exists to close, one rail higher up.
        for vddh_mv in [5500u32, 5800] {
            let raw = raw_for(SupplySense::VddhDiv5, vddh_mv);
            assert!(!railed(raw), "{vddh_mv} mV railed at raw={raw}");
        }
    }

    #[test]
    fn negative_counts_clamp_instead_of_wrapping() {
        // Ground-noise wobble on an idle input reads slightly negative. Casting
        // that straight to u16 would produce a huge millivolt figure — which the
        // plausibility band might not even catch on the way past.
        for sense in [SupplySense::VddDirect, SupplySense::VddhDiv5] {
            for raw in [-1, -100, i16::MIN] {
                assert_eq!(mv_from_raw(sense, raw), 0);
            }
        }
    }

    #[test]
    fn the_conversion_is_monotonic() {
        for sense in [SupplySense::VddDirect, SupplySense::VddhDiv5] {
            let mut prev = 0;
            for raw in (0..=4095i16).step_by(37) {
                let mv = mv_from_raw(sense, raw);
                assert!(mv >= prev, "raw={raw} went backwards");
                prev = mv;
            }
        }
    }

    #[test]
    fn a_usb_regulated_bench_rail_parks_the_task() {
        // ~3.0 V is the DK's regulated VDD, not a cell. Publishing it would
        // render a confident 0 % — the lie this gate exists to prevent.
        assert_eq!(plausible_percent(3000), None);
        assert_eq!(plausible_percent(PLAUSIBLE_MIN_MV - 1), None);
    }

    #[test]
    fn a_rail_above_the_charge_curve_is_refused_too() {
        assert_eq!(plausible_percent(PLAUSIBLE_MAX_MV + 1), None);
        assert_eq!(plausible_percent(u16::MAX), None);
    }

    #[test]
    fn a_real_cell_maps_onto_the_discharge_curve() {
        assert_eq!(plausible_percent(3820), Some(50));
        assert_eq!(plausible_percent(4200), Some(100));
        assert_eq!(plausible_percent(3300), Some(0));
        assert!(plausible_percent(PLAUSIBLE_MIN_MV).is_some());
        assert!(plausible_percent(PLAUSIBLE_MAX_MV).is_some());
    }

    #[test]
    fn a_zeroed_conversion_is_refused_not_read_as_empty() {
        // A silent or unconnected input reads 0 counts; 0 mV is not a cell, so
        // it must blank rather than render 0 %.
        assert_eq!(
            plausible_percent(mv_from_raw(SupplySense::VddDirect, 0)),
            None
        );
    }

    #[test]
    fn the_vdd_full_scale_rails_the_top_of_the_charge_curve() {
        // Why the VDD sense cannot be the tier-1 wiring: a fully-charged 4.2 V
        // cell exceeds the 3.6 V full scale, so it saturates the converter. The
        // band cannot catch that — the railed code's millivolts land INSIDE the
        // 1S LiPo span and read as a confident ~8 % for a full cell, which is
        // the lie the domain gate below exists to prevent.
        assert_eq!(
            plausible_percent(mv_from_raw(SupplySense::VddDirect, ADC_TOP_CODE)),
            Some(8)
        );
        assert!(railed(ADC_TOP_CODE));
    }

    #[test]
    fn a_railed_conversion_reads_as_absent_not_as_a_low_percent() {
        // Unknown, not 8 %. Absent stays the honest answer on either sense: the
        // voltage behind a saturated code is not knowable from the code.
        for sense in [SupplySense::VddDirect, SupplySense::VddhDiv5] {
            assert_eq!(percent_from_raw(sense, ADC_TOP_CODE), None);
            assert_eq!(percent_from_raw(sense, i16::MAX), None);
        }
    }

    #[test]
    fn an_in_domain_reading_keeps_the_plausibility_behaviour() {
        // Everything below the rail is a real measurement: the band gates it and
        // the curve maps it.
        for sense in [SupplySense::VddDirect, SupplySense::VddhDiv5] {
            for raw in [1, 1_000, 3_413, 4_000, ADC_TOP_CODE - 1] {
                assert!(!railed(raw));
                assert_eq!(
                    percent_from_raw(sense, raw),
                    plausible_percent(mv_from_raw(sense, raw)),
                    "sense={sense:?} raw={raw}"
                );
            }
        }
        // ~3.0 V of USB-regulated VDD is in domain but not a cell; ~3.5 V is.
        assert_eq!(percent_from_raw(SupplySense::VddDirect, 3_413), None);
        assert!(percent_from_raw(SupplySense::VddDirect, 4_000).is_some());
    }

    #[test]
    fn a_dead_input_reads_as_absent_too() {
        // 0 counts (silent / unconnected) and a negative wobble are in domain but
        // 0 mV, which is not a cell.
        for sense in [SupplySense::VddDirect, SupplySense::VddhDiv5] {
            assert_eq!(percent_from_raw(sense, 0), None);
            assert_eq!(percent_from_raw(sense, i16::MIN), None);
        }
    }

    #[test]
    fn a_charger_fresh_cell_on_vddh_reads_full_instead_of_blanking() {
        // The user-visible half of the bug: on the VDD sense a 4.2 V cell
        // saturated and the gauge blanked across the whole top of the charge
        // curve. On VDDHDIV5 the same cell reads 100 %.
        let full = raw_for(SupplySense::VddhDiv5, 4200);
        assert!(!railed(full));
        assert_eq!(percent_from_raw(SupplySense::VddhDiv5, full), Some(100));

        // And the rest of the curve still reads, including the anchors the VDD
        // sense could never reach.
        for (vddh_mv, pct) in [
            (4200u32, 100u8),
            (4060, 90),
            (3920, 70),
            (3820, 50),
            (3740, 20),
            (3680, 10),
        ] {
            let raw = raw_for(SupplySense::VddhDiv5, vddh_mv);
            let got = percent_from_raw(SupplySense::VddhDiv5, raw)
                .unwrap_or_else(|| panic!("{vddh_mv} mV read as absent"));
            // One code is ~1.5 mV of VDDH and the steepest curve segment is
            // 2.67 mV per point, so a quantised anchor may land one point below.
            assert!(
                got == pct || got + 1 == pct,
                "{vddh_mv} mV -> {got}%, expected ~{pct}%"
            );
        }
    }

    #[test]
    fn the_regulated_bench_rail_still_reads_absent_on_either_sense() {
        // The DK's default SW9 position is normal-voltage mode off a 3.0 V buck:
        // a regulator rail, not a cell, and it must stay absent rather than
        // become a confident 0 %. The same rail lands on a different code per
        // sense, so each is asserted through its own conversion.
        assert_eq!(
            percent_from_raw(
                SupplySense::VddDirect,
                raw_for(SupplySense::VddDirect, 3000)
            ),
            None
        );
        assert_eq!(
            percent_from_raw(SupplySense::VddhDiv5, raw_for(SupplySense::VddhDiv5, 3000)),
            None
        );
    }

    #[test]
    fn a_usb_or_flat_vddh_supply_reads_absent_rather_than_as_a_cell() {
        // SW9's USB position also runs the high-voltage regulator, so VDDH is
        // then ~5 V: above the charge curve, and the plausibility ceiling is
        // what refuses it — a reachable case for the first time on this sense.
        assert_eq!(
            percent_from_raw(SupplySense::VddhDiv5, raw_for(SupplySense::VddhDiv5, 5000)),
            None
        );
        // VDDH's operating minimum (2.5 V) is below the 3.3 V LiPo cutoff, so a
        // rail that low is not a healthy cell either.
        assert_eq!(
            percent_from_raw(SupplySense::VddhDiv5, raw_for(SupplySense::VddhDiv5, 2500)),
            None
        );
    }

    #[test]
    fn the_vddh_sense_switches_state_exactly_at_the_band_edges() {
        // One code either side of both plausibility bounds, so a change to the
        // band or the scale has to move a test rather than slip through.
        let first_at_or_above = |bound: u16| {
            (0..=ADC_TOP_CODE)
                .find(|&raw| mv_from_raw(SupplySense::VddhDiv5, raw) >= bound)
                .expect("bound is inside the sense's span")
        };

        let at_min = first_at_or_above(PLAUSIBLE_MIN_MV);
        assert_eq!(percent_from_raw(SupplySense::VddhDiv5, at_min), Some(0));
        assert_eq!(percent_from_raw(SupplySense::VddhDiv5, at_min - 1), None);

        let at_max = first_at_or_above(PLAUSIBLE_MAX_MV + 1) - 1;
        assert_eq!(percent_from_raw(SupplySense::VddhDiv5, at_max), Some(100));
        assert_eq!(percent_from_raw(SupplySense::VddhDiv5, at_max + 1), None);
    }

    #[test]
    fn the_vddh_sense_is_monotonic_across_the_whole_cell_range() {
        // Every code from empty cutoff to full charge, so no scale-arithmetic
        // rounding can make the gauge walk backwards as the cell drains.
        let lo = raw_for(SupplySense::VddhDiv5, 3300);
        let hi = raw_for(SupplySense::VddhDiv5, 4200);
        let mut prev = 0;
        for raw in lo..=hi {
            let pct = percent_from_raw(SupplySense::VddhDiv5, raw)
                .unwrap_or_else(|| panic!("raw={raw} inside the cell range read as absent"));
            assert!(pct >= prev, "raw={raw} went backwards: {pct} after {prev}");
            prev = pct;
        }
        assert_eq!(prev, 100);
    }
}
