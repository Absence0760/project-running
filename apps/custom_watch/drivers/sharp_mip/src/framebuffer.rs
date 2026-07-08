//! In-RAM image of the panel with per-line dirty tracking.
//!
//! Bit convention (shared with the generated font and the wire format under
//! LSB-first SPI): bit 0 of a line byte is the leftmost pixel of its 8-pixel
//! group, and 1 = ink (black). The wire wants 1 = white; the [`display`]
//! layer inverts during encode, so drawing code never thinks about it.
//!
//! [`display`]: crate::display

use crate::font;

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

fn glyph_for(ch: char) -> &'static [u8; font::GLYPH_HEIGHT] {
    let index = (ch as usize)
        .checked_sub(font::FIRST_CHAR as usize)
        .filter(|&i| i < font::FONT.len())
        .unwrap_or((b'?' - font::FIRST_CHAR) as usize);
    &font::FONT[index]
}
