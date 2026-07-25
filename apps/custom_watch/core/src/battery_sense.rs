//! SAADC counts → a publishable battery percent — the conversion + gate the
//! app's `battery` task runs on every sample, lifted out of the async task body
//! so the clamp and the park decision are host-tested.
//!
//! [`crate::battery`] owns the discharge curve and the plausibility band. This
//! module owns the two things the task adds on top: turning the raw conversion
//! result into millivolts for the driver's default single-ended configuration,
//! and folding the band into an `Option` so *one* decision covers both the boot
//! park (an implausible first reading means the task never publishes at all) and
//! the mid-stream blank (a reading that leaves the band blanks the gauge rather
//! than rendering a percent off a regulator rail).
//!
//! Full scale is 3.6 V — gain 1/6 against the 0.6 V internal reference, the
//! embassy-nrf default. The DK bench + tier-1 enclosure run the cell on VDD, so
//! the top of the 4.2 V charge curve rails until the build moves to the
//! VDDH/5 channel + high-voltage mode (a bench follow-up in the README).
//! Everything below the rail reads correctly.

use crate::battery::{percent_from_mv, plausible_mv};

/// Millivolts at full scale for the driver's default single-ended config.
pub const FULL_SCALE_MV: u32 = 3600;

/// Conversion range of the 12-bit SAADC.
pub const ADC_COUNTS: u32 = 4096;

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
        // full scale, so it reads as the rail and maps low. It must still be a
        // plausible percent (the gauge works, it just under-reads at the top)
        // until the enclosure build moves to the VDDH/5 channel.
        let railed = plausible_percent(mv_from_raw(4095));
        assert!(railed.is_some(), "the rail must not blank the gauge");
        assert!(railed.unwrap() < 100, "the rail cannot read as a full cell");
    }
}
