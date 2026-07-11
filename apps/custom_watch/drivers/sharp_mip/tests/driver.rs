//! Host-side driver tests: framebuffer semantics + exact wire encoding
//! against mock SPI/CS. Run via `bin/watch-test.sh`.

use std::convert::Infallible;

use embedded_hal::digital::{ErrorType as PinErrorType, OutputPin};
use embedded_hal::spi::{ErrorType as SpiErrorType, SpiBus};
use sharp_mip::{
    font, Framebuffer, Icon, SharpMip, HEIGHT, ICON_SIZE, LINE_BYTES, TEXT_COLS, TEXT_ROWS, WIDTH,
};

#[derive(Default)]
struct MockSpi {
    written: Vec<u8>,
}

impl SpiErrorType for MockSpi {
    type Error = Infallible;
}

impl SpiBus for MockSpi {
    fn read(&mut self, _words: &mut [u8]) -> Result<(), Infallible> {
        unimplemented!("display is write-only")
    }
    fn write(&mut self, words: &[u8]) -> Result<(), Infallible> {
        self.written.extend_from_slice(words);
        Ok(())
    }
    fn transfer(&mut self, _r: &mut [u8], _w: &[u8]) -> Result<(), Infallible> {
        unimplemented!("display is write-only")
    }
    fn transfer_in_place(&mut self, _words: &mut [u8]) -> Result<(), Infallible> {
        unimplemented!("display is write-only")
    }
    fn flush(&mut self) -> Result<(), Infallible> {
        Ok(())
    }
}

#[derive(Default)]
struct MockCs {
    transitions: Vec<bool>,
}

impl PinErrorType for MockCs {
    type Error = Infallible;
}

impl OutputPin for MockCs {
    fn set_low(&mut self) -> Result<(), Infallible> {
        self.transitions.push(false);
        Ok(())
    }
    fn set_high(&mut self) -> Result<(), Infallible> {
        self.transitions.push(true);
        Ok(())
    }
}

fn display() -> SharpMip<MockSpi, MockCs> {
    SharpMip::new(MockSpi::default(), MockCs::default())
}

const MODE_WRITE: u8 = 0x01;
const MODE_VCOM: u8 = 0x02;
const MODE_CLEAR: u8 = 0x04;
const PACKET: usize = 2 + LINE_BYTES;

#[test]
fn first_flush_paints_every_line() {
    let mut fb = Framebuffer::new();
    let mut d = display();
    d.flush(&mut fb).unwrap();
    let (spi, cs) = d.into_parts();

    // mode + 144 line packets + final trailer
    assert_eq!(spi.written.len(), 1 + HEIGHT * PACKET + 1);
    assert_eq!(spi.written[0], MODE_WRITE | MODE_VCOM);
    assert_eq!(*spi.written.last().unwrap(), 0x00);
    // Line addresses are 1-based and ascending.
    assert_eq!(spi.written[1], 1);
    assert_eq!(spi.written[1 + PACKET], 2);
    assert_eq!(spi.written[1 + (HEIGHT - 1) * PACKET], HEIGHT as u8);
    // Cleared framebuffer = all white on the wire (1 = white).
    assert!(spi.written[2..2 + LINE_BYTES].iter().all(|&b| b == 0xFF));
    // Per-line trailer.
    assert_eq!(spi.written[1 + PACKET - 1], 0x00);
    // CS wrapped the frame: high then low.
    assert_eq!(cs.transitions, vec![true, false]);
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn quiescent_flush_is_vcom_only_and_alternates() {
    let mut fb = Framebuffer::new();
    let mut d = display();
    d.flush(&mut fb).unwrap(); // paints, vcom=1
    d.flush(&mut fb).unwrap(); // nothing dirty, vcom=0
    d.flush(&mut fb).unwrap(); // nothing dirty, vcom=1
    let (spi, _) = d.into_parts();
    let tail = &spi.written[spi.written.len() - 4..];
    assert_eq!(tail, [0x00, 0x00, MODE_VCOM, 0x00]);
}

#[test]
fn single_pixel_change_flushes_exactly_one_line() {
    let mut fb = Framebuffer::new();
    let mut d = display();
    d.flush(&mut fb).unwrap();

    fb.set_pixel(10, 70, true);
    assert_eq!(fb.dirty_count(), 1);
    d.flush(&mut fb).unwrap();
    let (spi, _) = d.into_parts();

    let frame_start = 1 + HEIGHT * PACKET + 1;
    let frame = &spi.written[frame_start..];
    assert_eq!(frame.len(), 1 + PACKET + 1);
    assert_eq!(frame[1], 71); // 1-based line address
                              // Pixel x=10 -> byte 1, bit 2; ink inverts to 0 on the wire.
    assert_eq!(frame[2 + 1], !(1u8 << 2));
}

#[test]
fn external_vcom_skips_the_clean_flush_entirely() {
    let mut fb = Framebuffer::new();
    let mut d = SharpMip::new_external_vcom(MockSpi::default(), MockCs::default());
    d.flush(&mut fb).unwrap(); // first flush paints the whole panel
    let painted = {
        let mut probe = SharpMip::new_external_vcom(MockSpi::default(), MockCs::default());
        let mut fb2 = Framebuffer::new();
        probe.flush(&mut fb2).unwrap();
        probe.into_parts().0.written.len()
    };
    assert!(painted > 0);
    // Now nothing is dirty: a clean flush must send zero bytes (EXTCOMIN drives
    // the bias, so there's no VCOM-maintenance frame).
    d.flush(&mut fb).unwrap();
    d.flush(&mut fb).unwrap();
    let (spi, cs) = d.into_parts();
    assert_eq!(
        spi.written.len(),
        painted,
        "clean external-vcom flush sent bytes"
    );
    // And no chip-select toggles for the skipped frames (only the first frame).
    assert_eq!(cs.transitions, vec![true, false]);
}

#[test]
fn external_vcom_holds_the_vcom_bit_low() {
    let mut fb = Framebuffer::new();
    let mut d = SharpMip::new_external_vcom(MockSpi::default(), MockCs::default());
    d.flush(&mut fb).unwrap(); // paint: a fresh framebuffer is all-dirty
    let (spi, _) = d.into_parts();
    // The mode byte leads the frame. External VCOM keeps it MODE_WRITE with no
    // M1 bit — where the software path's first flush is MODE_WRITE | MODE_VCOM
    // (asserted in first_flush_paints_every_line).
    assert_eq!(spi.written[0], MODE_WRITE);
}

#[test]
fn clear_all_sends_clear_frame() {
    let mut d = display();
    d.clear_all().unwrap();
    let (spi, _) = d.into_parts();
    assert_eq!(spi.written, vec![MODE_CLEAR | MODE_VCOM, 0x00]);
}

#[test]
fn draw_text_writes_cell_aligned_glyph_bytes() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_text(3, 1, "A");
    let glyph = &font::FONT[(b'A' - font::FIRST_CHAR) as usize];
    for (dy, &bits) in glyph.iter().enumerate() {
        assert_eq!(fb.line(font::GLYPH_HEIGHT + dy)[3], bits);
    }
    // Only the glyph's non-empty rows can be dirty, all within the cell row.
    assert!(fb.dirty_count() > 0);
    assert!((0..HEIGHT)
        .filter(|&y| fb.is_dirty(y))
        .all(|y| { (font::GLYPH_HEIGHT..2 * font::GLYPH_HEIGHT).contains(&y) }));
}

#[test]
fn redrawing_identical_text_dirties_nothing() {
    let mut fb = Framebuffer::new();
    fb.draw_text_row(2, "LAT 40.01502");
    fb.clear_dirty();
    fb.draw_text_row(2, "LAT 40.01502");
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn draw_text_row_clears_leftover_cells() {
    let mut fb = Framebuffer::new();
    fb.draw_text_row(0, "WIDE OLD CONTENT");
    fb.draw_text_row(0, "NEW");
    // Cell 4 (the 'E' of "WIDE") must be blank again.
    for dy in 0..font::GLYPH_HEIGHT {
        assert_eq!(fb.line(dy)[4], 0);
    }
}

#[test]
fn draw_text_2x_pixel_doubles_a_glyph() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_text_2x(2, 0, "1");
    let glyph = &font::FONT[(b'1' - font::FIRST_CHAR) as usize];
    // Each source row maps to two dest rows; each source bit b lights dest bits
    // 2b and 2b+1 across the two-byte-wide doubled cell.
    for (dy, &bits) in glyph.iter().enumerate() {
        let mut wide: u16 = 0;
        for b in 0..8 {
            if bits >> b & 1 != 0 {
                wide |= 0b11 << (b * 2);
            }
        }
        let (lo, hi) = ((wide & 0xff) as u8, (wide >> 8) as u8);
        for half in 0..2 {
            let y = dy * 2 + half;
            assert_eq!(fb.line(y)[2], lo, "row {y} lo");
            assert_eq!(fb.line(y)[3], hi, "row {y} hi");
        }
    }
    // A 2x glyph spans 32 rows; every dirty line is inside that band.
    assert!((0..HEIGHT)
        .filter(|&y| fb.is_dirty(y))
        .all(|y| y < 2 * font::GLYPH_HEIGHT));
}

#[test]
fn redrawing_identical_2x_text_dirties_nothing() {
    let mut fb = Framebuffer::new();
    fb.draw_text_2x(0, 0, "3:24:07");
    fb.clear_dirty();
    fb.draw_text_2x(0, 0, "3:24:07");
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn draw_text_2x_clips_at_the_edges_without_panicking() {
    let mut fb = Framebuffer::new();
    fb.draw_text_2x(0, 99, "X"); // past the bottom
    fb.draw_text_2x(TEXT_COLS - 1, 0, "X"); // second cell falls off the right
    fb.draw_text_2x(0, 0, &"8".repeat(TEXT_COLS)); // more chars than fit
}

#[test]
fn draw_icon_blits_the_bitmap_cell_aligned() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_icon(4, 2, Icon::Heart);
    let bitmap = Icon::Heart.bitmap();
    let y0 = 2 * font::GLYPH_HEIGHT;
    for (dy, cells) in bitmap.iter().enumerate() {
        assert_eq!(fb.line(y0 + dy)[4], cells[0]);
        assert_eq!(fb.line(y0 + dy)[5], cells[1]);
    }
    // Every dirtied line sits inside the icon's one-row band.
    assert!(fb.dirty_count() > 0);
    assert!((0..HEIGHT)
        .filter(|&y| fb.is_dirty(y))
        .all(|y| (y0..y0 + ICON_SIZE).contains(&y)));
}

#[test]
fn draw_icon_overwrites_prior_cell_content() {
    let mut fb = Framebuffer::new();
    // A glyph then an icon over the same cells: the icon fully replaces it.
    fb.draw_text(4, 2, "HR");
    fb.draw_icon(4, 2, Icon::Heart);
    let bitmap = Icon::Heart.bitmap();
    let y0 = 2 * font::GLYPH_HEIGHT;
    for (dy, cells) in bitmap.iter().enumerate() {
        assert_eq!(fb.line(y0 + dy)[4], cells[0]);
        assert_eq!(fb.line(y0 + dy)[5], cells[1]);
    }
}

#[test]
fn redrawing_identical_icon_dirties_nothing() {
    let mut fb = Framebuffer::new();
    fb.draw_icon(0, 0, Icon::Satellite);
    fb.clear_dirty();
    fb.draw_icon(0, 0, Icon::Satellite);
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn draw_icon_out_of_bounds_is_clipped_not_panics() {
    let mut fb = Framebuffer::new();
    fb.draw_icon(0, 99, Icon::Vert);
    fb.draw_icon(TEXT_COLS - 1, 0, Icon::Vert); // second cell falls off the right
}

#[test]
fn out_of_bounds_draws_are_clipped_not_panics() {
    let mut fb = Framebuffer::new();
    fb.set_pixel(9999, 3, true);
    fb.set_pixel(3, 9999, true);
    fb.draw_text(0, 9999, "X");
    let wide = "W".repeat(TEXT_COLS + 10);
    fb.draw_text(0, 0, &wide);
    fb.draw_text(TEXT_COLS + 5, 0, "X");
}

#[test]
fn non_ascii_renders_as_question_mark() {
    let mut fb = Framebuffer::new();
    fb.draw_text(0, 0, "\u{00e9}");
    let mut expected = Framebuffer::new();
    expected.draw_text(0, 0, "?");
    for dy in 0..font::GLYPH_HEIGHT {
        assert_eq!(fb.line(dy)[0], expected.line(dy)[0]);
    }
}

#[test]
fn draw_line_horizontal_sets_exactly_the_span() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_line(10, 40, 20, 40, true);
    for x in 10..=20 {
        assert!(fb.pixel(x, 40), "missing pixel at x={x}");
    }
    assert!(!fb.pixel(9, 40));
    assert!(!fb.pixel(21, 40));
    // A horizontal line dirties exactly its one panel line.
    assert_eq!(fb.dirty_count(), 1);
    assert!(fb.is_dirty(40));
}

#[test]
fn draw_line_vertical_and_diagonal_hit_both_endpoints() {
    let mut fb = Framebuffer::new();
    fb.draw_line(5, 10, 5, 30, true);
    assert!(fb.pixel(5, 10) && fb.pixel(5, 30));
    fb.draw_line(0, 0, 30, 20, true);
    assert!(fb.pixel(0, 0) && fb.pixel(30, 20));
    // The diagonal is connected: every row it crosses has at least one pixel.
    for y in 0..=20 {
        assert!((0..=30).any(|x| fb.pixel(x, y)), "gap at row {y}");
    }
    // Direction-independent: the reverse line draws the same pixels.
    let mut rev = Framebuffer::new();
    rev.draw_line(30, 20, 0, 0, true);
    for y in 0..=20 {
        for x in 0..=30 {
            if fb.pixel(x, y) && !fb.pixel(5, y) {
                assert_eq!(rev.pixel(x, y), fb.pixel(x, y), "asymmetry at ({x},{y})");
            }
        }
    }
}

#[test]
fn draw_line_clips_offscreen_spans_without_panicking() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_line(-20, -10, 10, 5, true); // enters from the top-left
    assert!(fb.pixel(10, 5));
    fb.draw_line(160, 140, 400, 300, true); // exits bottom-right
    fb.draw_line(-5, 50, -1, 60, true); // entirely off-panel
    assert!(fb.dirty_count() > 0);
}

#[test]
fn redrawing_an_identical_line_dirties_nothing() {
    let mut fb = Framebuffer::new();
    fb.draw_line(3, 3, 60, 47, true);
    fb.clear_dirty();
    fb.draw_line(3, 3, 60, 47, true);
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn hline_sets_the_span_and_clips_at_the_right_edge() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.hline(10, 40, 5, true);
    assert!(!fb.pixel(9, 40));
    for x in 10..15 {
        assert!(fb.pixel(x, 40), "missing pixel at x={x}");
    }
    assert!(!fb.pixel(15, 40));
    assert_eq!(fb.dirty_count(), 1);
    assert!(fb.is_dirty(40));
    // A run reaching past the right edge clips instead of panicking.
    fb.hline(WIDTH - 3, 41, 20, true);
    assert!(fb.pixel(WIDTH - 1, 41));
    // Entirely off-panel row is a silent no-op.
    fb.hline(0, 9999, 10, true);
}

#[test]
fn vline_sets_the_span_and_clips_at_the_bottom() {
    let mut fb = Framebuffer::new();
    fb.vline(5, 10, 6, true);
    assert!(!fb.pixel(5, 9));
    for y in 10..16 {
        assert!(fb.pixel(5, y), "missing pixel at y={y}");
    }
    assert!(!fb.pixel(5, 16));
    // Runs off the bottom / right clip without panicking.
    fb.vline(6, HEIGHT - 2, 20, true);
    assert!(fb.pixel(6, HEIGHT - 1));
    fb.vline(9999, 0, 10, true);
}

#[test]
fn fill_rect_fills_its_interior_and_clips() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.fill_rect(20, 30, 4, 3, true);
    let mut count = 0;
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            if fb.pixel(x, y) {
                count += 1;
                assert!(
                    (20..24).contains(&x) && (30..33).contains(&y),
                    "stray at ({x},{y})"
                );
            }
        }
    }
    assert_eq!(count, 4 * 3);
    assert_eq!(fb.dirty_count(), 3);
    // A rect straddling the corner clips to the panel, no panic.
    fb.fill_rect(WIDTH - 2, HEIGHT - 2, 10, 10, true);
    assert!(fb.pixel(WIDTH - 1, HEIGHT - 1));
}

#[test]
fn stroke_rect_draws_only_the_border() {
    let mut fb = Framebuffer::new();
    fb.stroke_rect(10, 10, 6, 5, true);
    // Corners + edges are ink.
    for x in 10..16 {
        assert!(fb.pixel(x, 10) && fb.pixel(x, 14), "top/bottom edge x={x}");
    }
    for y in 10..15 {
        assert!(fb.pixel(10, y) && fb.pixel(15, y), "left/right edge y={y}");
    }
    // The interior is untouched.
    for y in 11..14 {
        for x in 11..15 {
            assert!(!fb.pixel(x, y), "interior ink at ({x},{y})");
        }
    }
}

#[test]
fn stroke_rect_degenerate_sizes_still_draw_without_panic() {
    let mut fb = Framebuffer::new();
    // Height 1 collapses to a horizontal line.
    fb.stroke_rect(4, 4, 5, 1, true);
    for x in 4..9 {
        assert!(fb.pixel(x, 4));
    }
    // Width 1 collapses to a vertical line.
    fb.stroke_rect(20, 20, 1, 4, true);
    for y in 20..24 {
        assert!(fb.pixel(20, y));
    }
    // Zero dimension draws nothing and does not panic.
    fb.stroke_rect(0, 0, 0, 5, true);
    fb.stroke_rect(0, 0, 5, 0, true);
}

#[test]
fn progress_bar_frac_zero_is_border_only() {
    let mut fb = Framebuffer::new();
    fb.draw_progress_bar(10, 10, 20, 8, 0.0);
    // Border present.
    assert!(fb.pixel(10, 10) && fb.pixel(29, 17));
    // Inner area entirely empty.
    for y in 11..17 {
        for x in 11..29 {
            assert!(!fb.pixel(x, y), "inner ink at ({x},{y})");
        }
    }
}

#[test]
fn progress_bar_half_fills_about_half_the_inner_width() {
    let mut fb = Framebuffer::new();
    fb.draw_progress_bar(0, 0, 22, 6, 0.5);
    // inner_w = 20, filled = 10: columns 1..11 ink on an inner row, 11..21 empty.
    let y = 2;
    for x in 1..11 {
        assert!(fb.pixel(x, y), "expected fill at x={x}");
    }
    for x in 11..21 {
        assert!(!fb.pixel(x, y), "expected empty at x={x}");
    }
}

#[test]
fn progress_bar_full_and_over_range_clamp_to_full_inner() {
    let mut full = Framebuffer::new();
    full.draw_progress_bar(0, 0, 12, 6, 1.0);
    let mut over = Framebuffer::new();
    over.draw_progress_bar(0, 0, 12, 6, 5.0);
    // inner_w = 10: every inner column filled, and >1 clamps to the same image.
    for y in 1..5 {
        for x in 1..11 {
            assert!(full.pixel(x, y), "full missing ({x},{y})");
            assert_eq!(
                over.pixel(x, y),
                full.pixel(x, y),
                "clamp mismatch ({x},{y})"
            );
        }
    }
    // Negative clamps to empty inner.
    let mut neg = Framebuffer::new();
    neg.draw_progress_bar(0, 0, 12, 6, -3.0);
    for y in 1..5 {
        for x in 1..11 {
            assert!(!neg.pixel(x, y), "neg-clamp ink at ({x},{y})");
        }
    }
}

#[test]
fn progress_bar_shrinking_clears_prior_fill() {
    let mut fb = Framebuffer::new();
    fb.draw_progress_bar(0, 0, 22, 6, 1.0);
    // Redraw smaller: the trailing inner span must erase.
    fb.draw_progress_bar(0, 0, 22, 6, 0.25);
    let y = 2;
    // inner_w = 20, filled = 5.
    for x in 1..6 {
        assert!(fb.pixel(x, y), "expected retained fill at x={x}");
    }
    for x in 6..21 {
        assert!(!fb.pixel(x, y), "stale fill left at x={x}");
    }
}

#[test]
fn center_bar_frac_zero_is_just_the_center_tick() {
    let mut fb = Framebuffer::new();
    fb.draw_center_bar(0, 0, 21, 6, 0.0);
    let cx = 21 / 2; // 10
    for y in 1..5 {
        assert!(fb.pixel(cx, y), "center tick missing at y={y}");
        for x in 1..20 {
            if x != cx {
                assert!(!fb.pixel(x, y), "unexpected ink at ({x},{y})");
            }
        }
    }
}

#[test]
fn center_bar_positive_fills_right_negative_fills_left() {
    let cx = 21 / 2; // 10
    let y = 2;
    let mut pos = Framebuffer::new();
    pos.draw_center_bar(0, 0, 21, 6, 0.5);
    // right_space = (0+21-2) - 10 = 9, fill_w = 4: columns cx+1..cx+5 ink, left empty.
    for x in (cx + 1)..(cx + 5) {
        assert!(pos.pixel(x, y), "positive fill missing at x={x}");
    }
    for x in 1..cx {
        assert!(!pos.pixel(x, y), "positive bar leaked left at x={x}");
    }

    let mut neg = Framebuffer::new();
    neg.draw_center_bar(0, 0, 21, 6, -0.5);
    // left_space = 10 - 1 = 9, fill_w = 4: columns cx-4..cx ink, right empty.
    for x in (cx - 4)..cx {
        assert!(neg.pixel(x, y), "negative fill missing at x={x}");
    }
    for x in (cx + 1)..20 {
        assert!(!neg.pixel(x, y), "negative bar leaked right at x={x}");
    }
}

#[test]
fn center_bar_clamps_magnitude() {
    let cx = 21 / 2;
    let y = 2;
    let mut full = Framebuffer::new();
    full.draw_center_bar(0, 0, 21, 6, 1.0);
    let mut over = Framebuffer::new();
    over.draw_center_bar(0, 0, 21, 6, 9.0);
    for x in 1..20 {
        assert_eq!(
            over.pixel(x, y),
            full.pixel(x, y),
            "clamp mismatch at x={x}"
        );
    }
    // Full-positive reaches the last inner column right of the tick.
    assert!(full.pixel(19, y));
    assert!(full.pixel(cx, y));
}

#[test]
fn sparkline_empty_and_zero_dimension_draw_nothing() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_sparkline(0, 0, 40, 20, &[], (0, 100));
    fb.draw_sparkline(0, 0, 0, 20, &[1, 2, 3], (0, 100));
    fb.draw_sparkline(0, 0, 40, 0, &[1, 2, 3], (0, 100));
    assert_eq!(fb.dirty_count(), 0);
}

#[test]
fn sparkline_single_sample_plots_one_point_at_its_height() {
    let mut fb = Framebuffer::new();
    // h = 11 so the baseline is y+10 and the top is y; the midpoint value 50 of
    // 0..100 lands on the middle row, at the left column.
    fb.draw_sparkline(5, 10, 30, 11, &[50], (0, 100));
    let mut lit = Vec::new();
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            if fb.pixel(x, y) {
                lit.push((x, y));
            }
        }
    }
    assert_eq!(lit, vec![(5, 15)]);
}

#[test]
fn sparkline_flat_series_draws_a_horizontal_line() {
    let mut fb = Framebuffer::new();
    // value 5 of 0..10 over h=11 -> row = (h-1) - 5*(h-1)/10 = 10 - 5 = 5.
    fb.draw_sparkline(0, 0, 20, 11, &[5, 5, 5, 5], (0, 10));
    for x in 0..20 {
        assert!(fb.pixel(x, 5), "missing flat-line pixel at x={x}");
    }
    for y in 0..11 {
        if y != 5 {
            for x in 0..20 {
                assert!(!fb.pixel(x, y), "stray at ({x},{y})");
            }
        }
    }
}

#[test]
fn sparkline_rising_ramp_climbs_from_baseline_to_top() {
    let mut fb = Framebuffer::new();
    fb.draw_sparkline(0, 0, 30, 11, &[0, 5, 10], (0, 10));
    // The min sample sits on the baseline (row h-1 = 10); the max on the top row.
    assert!(fb.pixel(0, 10), "ramp should start on the baseline");
    assert!(fb.pixel(29, 0), "ramp should reach the top row"); // plot_x(2) = 2*29/2
                                                               // Monotonic climb: the highest lit row (smallest index) only rises left->right.
    let top_at = |col: usize| (0..11).find(|&y| fb.pixel(col, y));
    assert!(top_at(0).unwrap() >= top_at(29).unwrap());
}

#[test]
fn sparkline_clamps_values_outside_the_range() {
    let mut over = Framebuffer::new();
    over.draw_sparkline(0, 0, 20, 11, &[200, 200], (0, 100));
    let mut under = Framebuffer::new();
    under.draw_sparkline(0, 0, 20, 11, &[-50, -50], (0, 100));
    // 200 clamps to max -> top row 0; -50 clamps to min -> baseline row 10.
    assert!(over.pixel(0, 0) && over.pixel(19, 0));
    assert!(under.pixel(0, 10) && under.pixel(19, 10));
    for x in 0..20 {
        assert!(
            !over.pixel(x, 10),
            "over-range leaked to the baseline at x={x}"
        );
        assert!(!under.pixel(x, 0), "under-range leaked to the top at x={x}");
    }
}

#[test]
fn draw_text_3x_triples_a_glyph() {
    let mut fb = Framebuffer::new();
    fb.clear_dirty();
    fb.draw_text_3x(0, 0, "1");
    let glyph = &font::FONT[(b'1' - font::FIRST_CHAR) as usize];
    // Each source row maps to three dest rows; each source bit b lights dest
    // bits 3b..3b+3 across the three-byte-wide tripled cell.
    for (dy, &bits) in glyph.iter().enumerate() {
        let mut wide: u32 = 0;
        for b in 0..8 {
            if bits >> b & 1 != 0 {
                wide |= 0b111 << (b * 3);
            }
        }
        let bytes = [
            (wide & 0xff) as u8,
            (wide >> 8 & 0xff) as u8,
            (wide >> 16 & 0xff) as u8,
        ];
        for third in 0..3 {
            let y = dy * 3 + third;
            if y >= HEIGHT {
                break;
            }
            for (c, &want) in bytes.iter().enumerate() {
                assert_eq!(fb.line(y)[c], want, "row {y} cell {c}");
            }
        }
    }
    // A tripled glyph spans 48 rows and dirtied at least the non-empty ones.
    assert!(fb.dirty_count() > 0);
    assert!((0..HEIGHT)
        .filter(|&y| fb.is_dirty(y))
        .all(|y| y < 3 * font::GLYPH_HEIGHT));
}

#[test]
fn draw_text_3x_block_is_24_wide_and_48_tall() {
    let mut fb = Framebuffer::new();
    fb.draw_text_3x(0, 0, "8"); // a dense glyph
    let mut max_x = 0;
    let mut max_y = 0;
    let mut any = false;
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            if fb.pixel(x, y) {
                any = true;
                if x > max_x {
                    max_x = x;
                }
                if y > max_y {
                    max_y = y;
                }
            }
        }
    }
    assert!(any, "glyph rendered nothing");
    // 24 px wide (3 cells) and 48 px tall (3 rows) upper bounds.
    assert!(max_x < 24, "wider than 24 px: {max_x}");
    assert!(max_y < 48, "taller than 48 px: {max_y}");
}

#[test]
fn draw_text_3x_truncates_and_clips_without_panicking() {
    let mut fb = Framebuffer::new();
    fb.draw_text_3x(0, 99, "X"); // past the bottom text row
    fb.draw_text_3x(TEXT_COLS - 2, 0, "X"); // 2nd/3rd cells fall off the right
    fb.draw_text_3x(0, TEXT_ROWS - 1, "X"); // bottom row: lower two-thirds clip off-panel
    fb.draw_text_3x(0, 0, &"8".repeat(TEXT_COLS)); // more chars than fit
}
