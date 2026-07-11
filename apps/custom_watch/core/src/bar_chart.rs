//! Scaled distribution bars — the mini bar chart the Zones / Splits glance
//! pages draw.
//!
//! [`bar_chart`] turns a small array of distribution values (HR zone times from
//! `record`'s `zone_time_s`, pace-bucket distances) into bottom-aligned pixel
//! rectangles the UI blits inside a chart box. Pure geometry: no display code,
//! no colour, no labels — the caller owns all of that.
//!
//! Buffer-filling like [`crate::trackback::project_track`]: the `core` crate is
//! `no_std` with no allocator, so the caller passes a fixed [`Bar`] slice this
//! writes into and gets back the count written. It never allocates and never
//! indexes past `out`.

/// One bar as pixel geometry relative to the chart box's top-left corner
/// (x right, y down). A zero-value bar still carries a correct `x`/`w` with
/// `h == 0`, so the caller can draw a baseline/axis under an empty column.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Bar {
    pub x: u16,
    pub y: u16,
    pub w: u16,
    pub h: u16,
}

/// A value's chart-usable magnitude: negatives, NaN, and infinities are noise
/// from a sensorless or mid-init source and count as zero, so they never win
/// the max nor drive a divide-by-zero.
fn magnitude(v: f64) -> f64 {
    if v.is_finite() && v > 0.0 {
        v
    } else {
        0.0
    }
}

/// Lay out `values` as a vertical bar chart inside a `box_w` x `box_h` box,
/// one bar per value left to right, `gap_px` between neighbours. Bars are
/// bottom-aligned (`y = box_h - h`) and their heights scale to the largest
/// value (the tallest reaches full `box_h`); an all-zero input yields all-zero
/// heights with no divide-by-zero. Writes at most `min(values.len(),
/// out.len())` bars and returns that count — a short `out` fills what fits
/// rather than panicking. Returns 0 for an empty input or a zero-area box.
///
/// Widths are integer-tiled: the leftover pixels of an uneven division go to
/// the leftmost bars (each at most 1 px wider), so the bars span the box
/// exactly instead of leaving a ragged right edge. Heights round half-up
/// (`libm::round`) so a bar just over half the max reads as more than half.
pub fn bar_chart(values: &[f64], box_w: u16, box_h: u16, gap_px: u16, out: &mut [Bar]) -> usize {
    let n = values.len().min(out.len());
    if n == 0 || box_w == 0 || box_h == 0 {
        return 0;
    }

    // The chart is sized for the full value set even when `out` truncates it,
    // so the bars that do fit sit where they would in the complete chart.
    let nbars = values.len() as u32;
    let total_gap = (gap_px as u32).saturating_mul(nbars.saturating_sub(1));
    let draw_w = (box_w as u32).saturating_sub(total_gap);
    let base_w = draw_w / nbars;
    let wide_bars = draw_w % nbars;

    let max_v = values.iter().copied().map(magnitude).fold(0.0f64, f64::max);

    let mut x: u32 = 0;
    for (i, &raw) in values.iter().take(n).enumerate() {
        let w = base_w + if (i as u32) < wide_bars { 1 } else { 0 };
        let h = if max_v > 0.0 {
            libm::round(magnitude(raw) / max_v * box_h as f64) as u16
        } else {
            0
        };
        out[i] = Bar {
            x: x.min(u16::MAX as u32) as u16,
            y: box_h - h,
            w: w as u16,
            h,
        };
        x = x.saturating_add(w).saturating_add(gap_px as u32);
    }
    n
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn even_values_tile_the_box_at_full_height() {
        // 4 * 24 + 3 * 2 gap == 102, so widths divide evenly.
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 8];
        let n = bar_chart(&[1.0, 1.0, 1.0, 1.0], 102, 64, 2, &mut out);
        assert_eq!(n, 4);
        for b in &out[..n] {
            assert_eq!(b.w, 24, "equal widths");
            assert_eq!(b.h, 64, "all equal -> all full height");
            assert_eq!(b.y, 0);
        }
        assert_eq!([out[0].x, out[1].x, out[2].x, out[3].x], [0, 26, 52, 78]);
        // Last bar's right edge reaches the box edge: the bars tile box_w.
        assert_eq!(out[3].x + out[3].w, 102);
    }

    #[test]
    fn heights_scale_to_the_max_value() {
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 4];
        let n = bar_chart(&[1.0, 2.0, 4.0], 100, 100, 0, &mut out);
        assert_eq!(n, 3);
        assert_eq!(out[2].h, 100, "the tallest bar is full box_h");
        assert_eq!(out[1].h, 50, "half the max -> half height");
        assert_eq!(out[0].h, 25, "quarter the max -> quarter height");
        // Bottom-aligned: taller bar starts higher up.
        assert_eq!(out[2].y, 0);
        assert_eq!(out[1].y, 50);
        assert_eq!(out[0].y, 75);
    }

    #[test]
    fn all_zero_input_yields_zero_heights_without_dividing_by_zero() {
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 4];
        let n = bar_chart(&[0.0, 0.0, 0.0], 90, 60, 3, &mut out);
        assert_eq!(n, 3);
        for b in &out[..n] {
            assert_eq!(b.h, 0);
            assert_eq!(b.y, 60, "an empty column baselines at box_h");
            assert!(b.w >= 1, "still a drawable column for the baseline");
        }
    }

    #[test]
    fn a_short_output_slice_fills_what_fits() {
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 2];
        let n = bar_chart(&[1.0, 2.0, 3.0, 4.0], 120, 50, 1, &mut out);
        assert_eq!(n, 2, "capped at out.len(), no OOB");
        // Geometry is that of the full 4-bar chart, truncated to two.
        assert_eq!(out[0].x, 0);
        assert!(out[1].x > out[0].x);
    }

    #[test]
    fn empty_values_and_zero_box_dims_return_zero() {
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 4];
        assert_eq!(bar_chart(&[], 100, 100, 2, &mut out), 0);
        assert_eq!(bar_chart(&[1.0, 2.0], 0, 100, 2, &mut out), 0);
        assert_eq!(bar_chart(&[1.0, 2.0], 100, 0, 2, &mut out), 0);
        let mut empty: [Bar; 0] = [];
        assert_eq!(bar_chart(&[1.0], 100, 100, 2, &mut empty), 0);
    }

    #[test]
    fn real_zone_and_pace_bucket_fixtures_lay_out_sanely() {
        // zone_time_s-shaped: five per-zone moving-time seconds.
        let zones = [300.0, 1200.0, 1800.0, 600.0, 120.0];
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 8];
        let n = bar_chart(&zones, 128, 48, 2, &mut out);
        assert_eq!(n, 5);
        assert_eq!(out[2].h, 48, "the busiest zone is full height");
        for b in &out[..n] {
            assert!(b.h <= 48);
            assert!(b.y + b.h == 48, "every bar bottom-aligns to the box floor");
            assert!(b.w >= 1);
        }

        // pace_bucket-shaped: six per-bucket distances, one empty bucket.
        let pace = [1200.0, 3400.0, 5000.0, 2100.0, 800.0, 0.0];
        let n = bar_chart(&pace, 128, 48, 1, &mut out);
        assert_eq!(n, 6);
        assert_eq!(out[2].h, 48);
        assert_eq!(out[5].h, 0, "the empty bucket draws a zero-height bar");
        assert_eq!(out[5].y, 48);
    }

    #[test]
    fn negative_and_nonfinite_values_count_as_zero() {
        let mut out = [Bar { x: 0, y: 0, w: 0, h: 0 }; 4];
        let n = bar_chart(&[-5.0, 10.0], 60, 40, 2, &mut out);
        assert_eq!(n, 2);
        assert_eq!(out[0].h, 0, "a negative value is treated as zero");
        assert_eq!(out[1].h, 40, "the lone positive value drives the max");

        // A NaN neither wins the max nor poisons the scaling.
        let n = bar_chart(&[f64::NAN, 8.0, 4.0], 60, 40, 0, &mut out);
        assert_eq!(n, 3);
        assert_eq!(out[0].h, 0);
        assert_eq!(out[1].h, 40);
        assert_eq!(out[2].h, 20);
    }
}
