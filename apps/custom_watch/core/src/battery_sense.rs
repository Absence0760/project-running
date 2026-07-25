//! SAADC counts → a publishable battery percent — the conversion + gate the
//! app's `battery` task runs on every sample, lifted out of the async task body
//! so the clamp and the park decision are host-tested.
//!
//! [`crate::battery`] owns the discharge curve and the plausibility band. This
//! module owns the two things the task adds on top: turning the raw conversion
//! result into millivolts for the driver's default single-ended configuration,
//! and folding the conversion's own domain plus that band into an `Option` so
//! *one* decision covers both the boot park (an unreadable first reading means
//! the task never publishes at all) and the mid-stream blank (a reading that
//! leaves the readable domain blanks the gauge rather than rendering a percent
//! off a regulator rail).
//!
//! Full scale is 3.6 V — gain 1/6 against the 0.6 V internal reference, the
//! embassy-nrf default. The DK bench + tier-1 enclosure run the cell on VDD, so
//! the top of the 4.2 V charge curve is ABOVE full scale and saturates the
//! converter. A saturated code is not 3.6 V, it is *unknown* — a full 4.2 V cell
//! and a 3.6 V one land on the same code — so [`percent_from_raw`] reports it as
//! absent. Publishing it would render ~8 % for a full cell, and a confident
//! wrong number is worse than an admitted gap. Everything below the rail is a
//! real measurement and reads normally; recovering the top of the curve needs
//! the VDDH/5 channel + high-voltage mode (a bench follow-up in the README).

use crate::battery::{percent_from_mv, plausible_mv};

/// Millivolts at full scale for the driver's default single-ended config.
pub const FULL_SCALE_MV: u32 = 3600;

/// Conversion range of the 12-bit SAADC.
pub const ADC_COUNTS: u32 = 4096;

/// The converter's last step. Every input at or above [`FULL_SCALE_MV`] lands
/// here, so the code carries no information about how far above it the rail
/// actually sits.
pub const ADC_TOP_CODE: i16 = (ADC_COUNTS - 1) as i16;

/// Whether a conversion saturated, i.e. the input was at or above full scale and
/// its voltage is therefore unknown. Distinct from an implausible millivolt
/// figure ([`plausible_mv`]): the railed code's millivolts (3599) sit squarely
/// inside the 1S LiPo band, so the band alone cannot catch it.
pub fn railed(raw: i16) -> bool {
    raw >= ADC_TOP_CODE
}

/// One SAADC conversion result → millivolts. Negative counts (ground-noise
/// wobble on an idle input) clamp to zero rather than wrapping into a
/// plausible-looking cell voltage.
pub fn mv_from_raw(raw: i16) -> u16 {
    (i32::from(raw.max(0)) * FULL_SCALE_MV as i32 / ADC_COUNTS as i32) as u16
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
/// the whole decision the `battery` task runs on every sample.
///
/// `None` is the honest absent state and covers both ways a reading can be
/// unpublishable: the conversion saturated ([`railed`], so the voltage behind it
/// is unknown), or its millivolts are not a 1S LiPo at all
/// ([`plausible_percent`]). Either way nothing is published and every consumer
/// shows its absent state — no gauge icon, no `BAT` row.
pub fn percent_from_raw(raw: i16) -> Option<u8> {
    if railed(raw) {
        return None;
    }
    plausible_percent(mv_from_raw(raw))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::battery::{PLAUSIBLE_MAX_MV, PLAUSIBLE_MIN_MV};

    #[test]
    fn the_conversion_spans_the_full_scale() {
        assert_eq!(mv_from_raw(0), 0);
        assert_eq!(mv_from_raw(2048), 1800);
        assert_eq!(mv_from_raw(4095), 3599);
    }

    #[test]
    fn negative_counts_clamp_instead_of_wrapping() {
        // Ground-noise wobble on an idle input reads slightly negative. Casting
        // that straight to u16 would produce a huge millivolt figure — which the
        // plausibility band might not even catch on the way past.
        for raw in [-1, -100, i16::MIN] {
            assert_eq!(mv_from_raw(raw), 0);
        }
    }

    #[test]
    fn the_conversion_is_monotonic() {
        let mut prev = 0;
        for raw in (0..=4095i16).step_by(37) {
            let mv = mv_from_raw(raw);
            assert!(mv >= prev, "raw={raw} went backwards");
            prev = mv;
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
        assert_eq!(plausible_percent(mv_from_raw(0)), None);
    }

    #[test]
    fn the_vdd_full_scale_rails_the_top_of_the_charge_curve() {
        // Known bench limitation: a fully-charged 4.2 V cell exceeds the 3.6 V
        // full scale, so it saturates the converter. The band cannot catch that —
        // the railed code's millivolts land INSIDE the 1S LiPo span and read as a
        // confident ~8 % for a full cell, which is the lie the domain gate below
        // exists to prevent.
        assert_eq!(plausible_percent(mv_from_raw(ADC_TOP_CODE)), Some(8));
        assert!(railed(ADC_TOP_CODE));
    }

    #[test]
    fn a_railed_conversion_reads_as_absent_not_as_a_low_percent() {
        // Unknown, not 8 %. Absent is the honest state until the enclosure build
        // moves to the VDDH/5 channel and can see the top of the charge curve.
        assert_eq!(percent_from_raw(ADC_TOP_CODE), None);
        assert_eq!(percent_from_raw(i16::MAX), None);
    }

    #[test]
    fn an_in_domain_reading_keeps_the_plausibility_behaviour() {
        // Everything below the rail is a real measurement: the band gates it and
        // the curve maps it, exactly as before.
        for raw in [1, 1_000, 3_413, 4_000, ADC_TOP_CODE - 1] {
            assert!(!railed(raw));
            assert_eq!(
                percent_from_raw(raw),
                plausible_percent(mv_from_raw(raw)),
                "raw={raw}"
            );
        }
        // ~3.0 V of USB-regulated VDD is in domain but not a cell; ~3.5 V is.
        assert_eq!(percent_from_raw(3_413), None);
        assert!(percent_from_raw(4_000).is_some());
    }

    #[test]
    fn a_dead_input_reads_as_absent_too() {
        // 0 counts (silent / unconnected) and a negative wobble are in domain but
        // 0 mV, which is not a cell.
        assert_eq!(percent_from_raw(0), None);
        assert_eq!(percent_from_raw(i16::MIN), None);
    }
}
