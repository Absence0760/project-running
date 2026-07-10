//! In-RAM image of the panel with per-line dirty tracking.
//!
//! Bit convention (shared with the generated font and the wire format under
//! LSB-first SPI): bit 0 of a line byte is the leftmost pixel of its 8-pixel
//! group, and 1 = ink (black). The wire wants 1 = white; the [`display`]
//! layer inverts during encode, so drawing code never thinks about it.
//!
//! [`display`]: crate::display

use crate::font;
use crate::icons::{Icon, ICON_SIZE};

// An icon is exactly one text row tall and `ICON_BYTES_PER_ROW` cells wide, so
// `draw_icon` can blit it cell-aligned like a glyph. These asserts pin that.
const _: () = assert!(ICON_SIZE == font::GLYPH_HEIGHT);

pub const WIDTH: usize = 168;
pub const HEIGHT: usize = 144;
pub const LINE_BYTES: usize = WIDTH / 8;

/// Text grid: 8x16 font cells.
pub const TEXT_COLS: usize = WIDTH / font::GLYPH_WIDTH;
pub const TEXT_ROWS: usize = HEIGHT / font::GLYPH_HEIGHT;

pub struct Framebuffer {
    lines: [[u8; LINE_BYTES]; HEIGHT],
    dirty: [bool; HEIGHT],
}

impl Default for Framebuffer {
    fn default() -> Self {
        Self::new()
    }
}

impl Framebuffer {
    /// Starts cleared with every line dirty, so the first flush paints the
    /// whole panel regardless of what the glass was showing before reset.
    pub const fn new() -> Self {
        Self {
            lines: [[0; LINE_BYTES]; HEIGHT],
            dirty: [true; HEIGHT],
        }
    }

    pub fn clear(&mut self) {
        for y in 0..HEIGHT {
            if self.lines[y] != [0; LINE_BYTES] {
                self.lines[y] = [0; LINE_BYTES];
                self.dirty[y] = true;
            }
        }
    }

    /// Out-of-bounds coordinates are ignored — clipping beats a panic on a
    /// wrist device (layered-resilience: a drawing bug must not kill L0).
    pub fn set_pixel(&mut self, x: usize, y: usize, ink: bool) {
        if x >= WIDTH || y >= HEIGHT {
            return;
        }
        let (byte, bit) = (x / 8, x % 8);
        let old = self.lines[y][byte];
        let new = if ink {
            old | 1 << bit
        } else {
            old & !(1 << bit)
        };
        if new != old {
            self.lines[y][byte] = new;
            self.dirty[y] = true;
        }
    }

    /// Draw a 1-px line from `(x0, y0)` to `(x1, y1)` — Bresenham over
    /// [`set_pixel`](Self::set_pixel), so spans reaching outside the panel
    /// clip instead of panicking, and redrawing an identical line dirties
    /// nothing. Signed coordinates so a clipped polyline can keep endpoints
    /// off-panel.
    pub fn draw_line(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, ink: bool) {
        let (mut x, mut y) = (x0, y0);
        let dx = (x1 - x0).abs();
        let dy = -(y1 - y0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;
        loop {
            if x >= 0 && y >= 0 {
                self.set_pixel(x as usize, y as usize, ink);
            }
            if x == x1 && y == y1 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x += sx;
            }
            if e2 <= dx {
                err += dx;
                y += sy;
            }
        }
    }

    pub fn pixel(&self, x: usize, y: usize) -> bool {
        x < WIDTH && y < HEIGHT && self.lines[y][x / 8] >> (x % 8) & 1 == 1
    }

    /// Draw a string at a text-grid cell. Glyphs are cell-aligned (8 px = 1
    /// byte), so a glyph row is a single byte store. Overwrites the cell —
    /// redrawing the same text is a no-op that dirties nothing. Truncates at
    /// the right edge; non-ASCII renders as '?'.
    pub fn draw_text(&mut self, col: usize, row: usize, text: &str) {
        if row >= TEXT_ROWS {
            return;
        }
        let y0 = row * font::GLYPH_HEIGHT;
        for (i, ch) in text.chars().enumerate() {
            let cell = col + i;
            if cell >= TEXT_COLS {
                break;
            }
            let glyph = glyph_for(ch);
            for (dy, &bits) in glyph.iter().enumerate() {
                let y = y0 + dy;
                if self.lines[y][cell] != bits {
                    self.lines[y][cell] = bits;
                    self.dirty[y] = true;
                }
            }
        }
    }

    /// Draw a full text row, clearing the remainder of the row's cells.
    pub fn draw_text_row(&mut self, row: usize, text: &str) {
        self.draw_text(0, row, text);
        let used = text.chars().count().min(TEXT_COLS);
        for cell in used..TEXT_COLS {
            let y0 = row * font::GLYPH_HEIGHT;
            for dy in 0..font::GLYPH_HEIGHT {
                let y = y0 + dy;
                if y < HEIGHT && self.lines[y][cell] != 0 {
                    self.lines[y][cell] = 0;
                    self.dirty[y] = true;
                }
            }
        }
    }

    /// Draw a string at 2x scale — each 8x16 glyph pixel-doubled into a 16x32
    /// block, so a character spans two grid cells wide and two text rows tall.
    /// Cell-aligned at `(col, row)`; the hero band a glanceable primary metric
    /// needs, with no separate large font to author. Truncates at the right
    /// edge and clips at the bottom; non-ASCII renders as '?'. Overwrites the
    /// covered cells, so redrawing the same text dirties nothing.
    pub fn draw_text_2x(&mut self, col: usize, row: usize, text: &str) {
        if row >= TEXT_ROWS {
            return;
        }
        let y0 = row * font::GLYPH_HEIGHT;
        for (i, ch) in text.chars().enumerate() {
            let cell = col + i * 2;
            if cell >= TEXT_COLS {
                break;
            }
            let glyph = glyph_for(ch);
            for (dy, &bits) in glyph.iter().enumerate() {
                let (lo, hi) = double_bits(bits);
                for half in 0..2 {
                    let y = y0 + dy * 2 + half;
                    if y >= HEIGHT {
                        break;
                    }
                    self.put_cell_byte(cell, y, lo);
                    if cell + 1 < TEXT_COLS {
                        self.put_cell_byte(cell + 1, y, hi);
                    }
                }
            }
        }
    }

    fn put_cell_byte(&mut self, cell: usize, y: usize, bits: u8) {
        if self.lines[y][cell] != bits {
            self.lines[y][cell] = bits;
            self.dirty[y] = true;
        }
    }

    /// Blit a 16x16 [`Icon`] at a text-grid cell — one row tall, two cells
    /// wide. Overwrites those cells (the icon carries its own whitespace as 0
    /// bits, so it also clears prior content), clipping at the right and bottom
    /// edges. Redrawing the same icon dirties nothing.
    pub fn draw_icon(&mut self, col: usize, row: usize, icon: Icon) {
        if row >= TEXT_ROWS {
            return;
        }
        let y0 = row * font::GLYPH_HEIGHT;
        for (dy, cells) in icon.bitmap().iter().enumerate() {
            let y = y0 + dy;
            if y >= HEIGHT {
                break;
            }
            for (bx, &bits) in cells.iter().enumerate() {
                let cell = col + bx;
                if cell >= TEXT_COLS {
                    break;
                }
                if self.lines[y][cell] != bits {
                    self.lines[y][cell] = bits;
                    self.dirty[y] = true;
                }
            }
        }
    }

    pub fn is_dirty(&self, y: usize) -> bool {
        self.dirty[y]
    }

    pub fn line(&self, y: usize) -> &[u8; LINE_BYTES] {
        &self.lines[y]
    }

    pub fn clear_dirty(&mut self) {
        self.dirty = [false; HEIGHT];
    }

    pub fn dirty_count(&self) -> usize {
        self.dirty.iter().filter(|&&d| d).count()
    }
}

/// Pixel-double one 8-bit glyph row into 16 bits (two bytes): source bit `b`
/// (bit 0 = leftmost) lights destination bits `2b` and `2b+1`, keeping the
/// framebuffer's LSB-first-is-leftmost convention.
fn double_bits(src: u8) -> (u8, u8) {
    let mut out: u16 = 0;
    for b in 0..8 {
        if src >> b & 1 != 0 {
            out |= 0b11 << (b * 2);
        }
    }
    ((out & 0xff) as u8, (out >> 8) as u8)
}

fn glyph_for(ch: char) -> &'static [u8; font::GLYPH_HEIGHT] {
    let index = (ch as usize)
        .checked_sub(font::FIRST_CHAR as usize)
        .filter(|&i| i < font::FONT.len())
        .unwrap_or((b'?' - font::FIRST_CHAR) as usize);
    &font::FONT[index]
}
