//! Host-side driver tests: framebuffer semantics + exact wire encoding
//! against mock SPI/CS. Run via `bin/watch-test.sh`.

use std::convert::Infallible;

use embedded_hal::digital::{ErrorType as PinErrorType, OutputPin};
use embedded_hal::spi::{ErrorType as SpiErrorType, SpiBus};
use sharp_mip::{font, Framebuffer, Icon, SharpMip, HEIGHT, ICON_SIZE, LINE_BYTES, TEXT_COLS};

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
