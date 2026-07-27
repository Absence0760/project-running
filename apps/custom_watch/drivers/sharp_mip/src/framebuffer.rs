//! In-RAM image of the panel with per-line dirty tracking.
//!
//! Bit convention (shared with the generated font and the wire format under
//! LSB-first SPI): bit 0 of a line byte is the leftmost pixel of its 8-pixel
//! group, and 1 = ink (black). The wire wants 1 = white; the [`display`]
//! layer inverts during encode, so drawing code never thinks about it.
//!
//! [`display`]: crate::display

use crate::bignum;
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

/// Hairlines for [`Framebuffer::draw_text_row_ruled`]: 1-px rules along the
/// band's top and/or bottom pixel row (from pixel column `x0` to the right
/// edge) plus an optional full-height vertical rule at `vline_x`.
#[derive(Clone, Copy, Default)]
pub struct RowRules {
    pub top: bool,
    pub bottom: bool,
    pub vline_x: Option<usize>,
    pub x0: usize,
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

    /// Signed-coordinate wrapper over [`set_pixel`](Self::set_pixel): a negative
    /// coordinate is off-panel to the top/left and clips silently, mirroring the
    /// right/bottom clip `set_pixel` already does. Lets geometry with an
    /// off-panel origin (a circle centre past an edge) stay panic-free.
    fn plot_i32(&mut self, x: i32, y: i32, ink: bool) {
        if x >= 0 && y >= 0 {
            self.set_pixel(x as usize, y as usize, ink);
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
            self.plot_i32(x, y, ink);
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

    /// Horizontal run of `w` pixels from `(x, y)`. Clips at the right edge and
    /// off-panel rows through [`set_pixel`](Self::set_pixel), so redrawing an
    /// identical run dirties nothing.
    pub fn hline(&mut self, x: usize, y: usize, w: usize, ink: bool) {
        for i in 0..w {
            self.set_pixel(x + i, y, ink);
        }
    }

    /// Vertical run of `h` pixels from `(x, y)`.
    pub fn vline(&mut self, x: usize, y: usize, h: usize, ink: bool) {
        for j in 0..h {
            self.set_pixel(x, y + j, ink);
        }
    }

    /// Solid `w`×`h` rectangle anchored at `(x, y)`.
    pub fn fill_rect(&mut self, x: usize, y: usize, w: usize, h: usize, ink: bool) {
        for j in 0..h {
            self.hline(x, y + j, w, ink);
        }
    }

    /// 1-px rectangle border. A `w` or `h` of 1 collapses to a single line and
    /// a 0 dimension draws nothing — no underflow on the `- 1` edges.
    pub fn stroke_rect(&mut self, x: usize, y: usize, w: usize, h: usize, ink: bool) {
        if w == 0 || h == 0 {
            return;
        }
        self.hline(x, y, w, ink);
        self.hline(x, y + h - 1, w, ink);
        self.vline(x, y, h, ink);
        self.vline(x + w - 1, y, h, ink);
    }

    /// Bordered progress box filled left-to-right to `frac` (clamped 0..=1) of
    /// the inner width. The trailing inner span is cleared so a bar that shrinks
    /// between frames erases its old fill instead of leaving a stale tail.
    pub fn draw_progress_bar(&mut self, x: usize, y: usize, w: usize, h: usize, frac: f32) {
        self.stroke_rect(x, y, w, h, true);
        if w < 2 || h < 2 {
            return;
        }
        let inner_w = w - 2;
        let inner_h = h - 2;
        let frac = frac.clamp(0.0, 1.0);
        let filled = (inner_w as f32 * frac) as usize;
        self.fill_rect(x + 1, y + 1, filled, inner_h, true);
        self.fill_rect(x + 1 + filled, y + 1, inner_w - filled, inner_h, false);
    }

    /// Signed "ahead/behind" bar: a bordered box with a 1-px center tick, filled
    /// from the center toward the right for positive `frac` (clamped -1..=1) or
    /// the left for negative, proportional to its magnitude. The inner band is
    /// cleared first so the sign and length erase cleanly between frames.
    pub fn draw_center_bar(&mut self, x: usize, y: usize, w: usize, h: usize, frac: f32) {
        self.stroke_rect(x, y, w, h, true);
        if w < 2 || h < 2 {
            return;
        }
        let inner_h = h - 2;
        let iy = y + 1;
        self.fill_rect(x + 1, iy, w - 2, inner_h, false);
        let cx = x + w / 2;
        let frac = frac.clamp(-1.0, 1.0);
        if frac > 0.0 {
            let right_space = (x + w - 2).saturating_sub(cx);
            let fill_w = (right_space as f32 * frac) as usize;
            self.fill_rect(cx + 1, iy, fill_w, inner_h, true);
        } else if frac < 0.0 {
            let left_space = cx.saturating_sub(x + 1);
            let fill_w = (left_space as f32 * -frac) as usize;
            self.fill_rect(cx - fill_w, iy, fill_w, inner_h, true);
        }
        self.vline(cx, iy, inner_h, true);
    }

    /// Plot `samples` as a baseline-aligned mini-profile inside the `w`×`h` cell
    /// at `(x, y)`: each value is clamped to `[min, max]` and mapped so `min`
    /// sits on the bottom row and `max` on the top, with samples spread evenly
    /// across the width and joined into a polyline via
    /// [`draw_line`](Self::draw_line). Fewer than two samples plot a single
    /// point; an empty slice or a zero dimension draws nothing. A `max <= min`
    /// range flattens every sample onto the baseline instead of dividing by
    /// zero. Like [`draw_line`](Self::draw_line) it plots over
    /// [`set_pixel`](Self::set_pixel) — spans clip to the panel and redrawing an
    /// identical profile dirties nothing; it does not clear a prior profile.
    pub fn draw_sparkline(
        &mut self,
        x: usize,
        y: usize,
        w: usize,
        h: usize,
        samples: &[i32],
        range: (i32, i32),
    ) {
        let (min, max) = range;
        if w == 0 || h == 0 || samples.is_empty() {
            return;
        }
        let span = (max as i64 - min as i64).max(0);
        let plot_y = |v: i32| -> i32 {
            let t = if span > 0 {
                (v.clamp(min, max) as i64 - min as i64) * (h as i64 - 1) / span
            } else {
                0
            };
            y as i32 + (h as i32 - 1) - t as i32
        };
        let n = samples.len();
        let plot_x = |i: usize| -> i32 {
            if n == 1 {
                x as i32
            } else {
                x as i32 + (i as i64 * (w as i64 - 1) / (n as i64 - 1)) as i32
            }
        };
        if n == 1 {
            self.set_pixel(x, plot_y(samples[0]) as usize, true);
            return;
        }
        let (mut px, mut py) = (plot_x(0), plot_y(samples[0]));
        for (i, &v) in samples.iter().enumerate().skip(1) {
            let (cx, cy) = (plot_x(i), plot_y(v));
            self.draw_line(px, py, cx, cy, true);
            (px, py) = (cx, cy);
        }
    }

    /// Dashed variant of [`draw_line`](Self::draw_line): the same Bresenham walk,
    /// but ink is laid down for `dash.0` (on) pixels then skipped for `dash.1`
    /// (off) pixels, repeating along the run. `off == 0` is a solid line;
    /// `on == 0` draws nothing; `on == 0 && off == 0` is a no-op (guards the
    /// modulo). Clips and dirties exactly like [`draw_line`](Self::draw_line).
    pub fn draw_dashed_line(
        &mut self,
        x0: i32,
        y0: i32,
        x1: i32,
        y1: i32,
        dash: (u32, u32),
        ink: bool,
    ) {
        let (on, off) = dash;
        let period = on + off;
        if period == 0 {
            return;
        }
        let (mut x, mut y) = (x0, y0);
        let dx = (x1 - x0).abs();
        let dy = -(y1 - y0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;
        let mut step: u32 = 0;
        loop {
            if step % period < on {
                self.plot_i32(x, y, ink);
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
            step = step.wrapping_add(1);
        }
    }

    /// 1-px circle outline centred at `(cx, cy)`, radius `r`, via the integer
    /// midpoint algorithm over [`plot_i32`](Self::plot_i32) — no trig, no float.
    /// `r == 0` is the single centre pixel; `r < 0` draws nothing. A centre near
    /// or past an edge clips silently instead of panicking.
    pub fn draw_circle(&mut self, cx: i32, cy: i32, r: i32, ink: bool) {
        if r < 0 {
            return;
        }
        if r == 0 {
            self.plot_i32(cx, cy, ink);
            return;
        }
        let mut x = r;
        let mut y = 0;
        let mut err = 1 - r;
        while x >= y {
            self.plot_i32(cx + x, cy + y, ink);
            self.plot_i32(cx - x, cy + y, ink);
            self.plot_i32(cx + x, cy - y, ink);
            self.plot_i32(cx - x, cy - y, ink);
            self.plot_i32(cx + y, cy + x, ink);
            self.plot_i32(cx - y, cy + x, ink);
            self.plot_i32(cx + y, cy - x, ink);
            self.plot_i32(cx - y, cy - x, ink);
            y += 1;
            if err < 0 {
                err += 2 * y + 1;
            } else {
                x -= 1;
                err += 2 * (y - x) + 1;
            }
        }
    }

    /// Filled annulus centred at `(cx, cy)`: every pixel whose distance from the
    /// centre falls in `[r_inner, r_outer]` (a thick outline, or a solid disc
    /// when `r_inner <= 0`). Uses a squared-distance test so it stays integer.
    /// `r_inner` is clamped up to 0; `r_inner > r_outer` and `r_outer < 0` draw
    /// nothing. Pixels off-panel clip through [`plot_i32`](Self::plot_i32).
    pub fn draw_ring(&mut self, cx: i32, cy: i32, r_outer: i32, r_inner: i32, ink: bool) {
        if r_outer < 0 {
            return;
        }
        let inner = r_inner.max(0);
        if inner > r_outer {
            return;
        }
        let ro2 = r_outer * r_outer;
        let ri2 = inner * inner;
        for dy in -r_outer..=r_outer {
            for dx in -r_outer..=r_outer {
                let d2 = dx * dx + dy * dy;
                if d2 <= ro2 && d2 >= ri2 {
                    self.plot_i32(cx + dx, cy + dy, ink);
                }
            }
        }
    }

    /// Circle arc centred at `(cx, cy)`, radius `r`, swept from `start_deg` to
    /// `end_deg`. Angles are degrees with 0 at +x (east) increasing toward +y
    /// (down, so clockwise on-screen); the sweep always runs in the increasing
    /// direction, wrapping through 360 when `end_deg < start_deg`, and a span of
    /// 360 or more is the full circle. Reuses the integer midpoint outline and
    /// keeps only the points whose angle lies in the sweep — no trig table, no
    /// float. `r == 0` plots the centre; `r < 0` draws nothing; an off-panel
    /// centre clips silently.
    pub fn draw_arc(&mut self, cx: i32, cy: i32, r: i32, start_deg: i32, end_deg: i32, ink: bool) {
        if r < 0 {
            return;
        }
        if r == 0 {
            self.plot_i32(cx, cy, ink);
            return;
        }
        let start = start_deg.rem_euclid(360);
        let sweep = if end_deg - start_deg >= 360 {
            360
        } else {
            (end_deg - start_deg).rem_euclid(360)
        };
        let plot_if_in = |fb: &mut Self, dx: i32, dy: i32| {
            let rel = (angle_deg(dy, dx) - start).rem_euclid(360);
            if rel <= sweep {
                fb.plot_i32(cx + dx, cy + dy, ink);
            }
        };
        let mut x = r;
        let mut y = 0;
        let mut err = 1 - r;
        while x >= y {
            plot_if_in(self, x, y);
            plot_if_in(self, -x, y);
            plot_if_in(self, x, -y);
            plot_if_in(self, -x, -y);
            plot_if_in(self, y, x);
            plot_if_in(self, -y, x);
            plot_if_in(self, y, -x);
            plot_if_in(self, -y, -x);
            y += 1;
            if err < 0 {
                err += 2 * y + 1;
            } else {
                x -= 1;
                err += 2 * (y - x) + 1;
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

    /// Like [`Self::draw_text_row`], but with 1-px hairline [`RowRules`]
    /// composed into the band alongside the glyphs, in the same
    /// compare-write. Composition is the point: drawing the text first and a
    /// rule second would leave the rule's pixel row byte-different between
    /// the two passes, latching those lines dirty on every frame — a ruled
    /// row that hasn't changed must still flush zero lines.
    pub fn draw_text_row_ruled(&mut self, row: usize, text: &str, rules: RowRules) {
        if row >= TEXT_ROWS {
            return;
        }
        let y0 = row * font::GLYPH_HEIGHT;
        for dy in 0..font::GLYPH_HEIGHT {
            let mut line = [0u8; LINE_BYTES];
            for (i, ch) in text.chars().take(TEXT_COLS).enumerate() {
                line[i] = glyph_for(ch)[dy];
            }
            if (rules.top && dy == 0) || (rules.bottom && dy == font::GLYPH_HEIGHT - 1) {
                for x in rules.x0..WIDTH {
                    line[x / 8] |= 1 << (x % 8);
                }
            }
            if let Some(vx) = rules.vline_x.filter(|&vx| vx < WIDTH) {
                line[vx / 8] |= 1 << (vx % 8);
            }
            let y = y0 + dy;
            for (bx, &b) in line.iter().enumerate() {
                if self.lines[y][bx] != b {
                    self.lines[y][bx] = b;
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

    /// Full-width inverse-video banner: the two text rows from `row` fill
    /// solid ink with `text` knocked out in background pixels, pixel-doubled
    /// from the 8x16 font and centred — dark band, light text. On a 1-bit
    /// framebuffer inverse video is just fg and bg swapped at draw time, so
    /// this is the visually-loudest treatment the panel gives (the reflective
    /// glass has no backlight or grey to spend). Lines are composed whole and
    /// compare-written, so a standing banner redraws for free. Truncates at
    /// the panel width; clips at the bottom; non-ASCII renders as '?'.
    pub fn draw_banner_2x(&mut self, row: usize, text: &str) {
        if row >= TEXT_ROWS {
            return;
        }
        let n = text.chars().count().min(TEXT_COLS / 2);
        let col0 = (TEXT_COLS - n * 2) / 2;
        let y0 = row * font::GLYPH_HEIGHT;
        for dy in 0..font::GLYPH_HEIGHT {
            for half in 0..2 {
                let y = y0 + dy * 2 + half;
                if y >= HEIGHT {
                    return;
                }
                let mut line = [0xFF_u8; LINE_BYTES];
                for (i, ch) in text.chars().take(n).enumerate() {
                    let (lo, hi) = double_bits(glyph_for(ch)[dy]);
                    line[col0 + i * 2] = !lo;
                    line[col0 + i * 2 + 1] = !hi;
                }
                for (bx, &b) in line.iter().enumerate() {
                    if self.lines[y][bx] != b {
                        self.lines[y][bx] = b;
                        self.dirty[y] = true;
                    }
                }
            }
        }
    }

    /// Draw `text` in the generated 32x48 numeral face ([`bignum`]), centred
    /// in the full-width band whose top pixel row is `y0`. Each affected line
    /// is composed off-screen (background included) and compare-written, so a
    /// redraw of an unchanged clock dirties nothing — the same at-rest
    /// zero-flush property as [`Self::draw_text_row`] — and stale pixels
    /// anywhere in the band are erased without a separate clear pass.
    /// Characters outside the glyph set advance blank; clips at the bottom.
    pub fn draw_bignum_band(&mut self, y0: usize, text: &str) {
        let n = text.len().min(WIDTH / bignum::BIGNUM_WIDTH);
        let x0 = (WIDTH - n * bignum::BIGNUM_WIDTH) / 2;
        for dy in 0..bignum::BIGNUM_HEIGHT {
            let y = y0 + dy;
            if y >= HEIGHT {
                return;
            }
            let mut line = [0u8; LINE_BYTES];
            for (i, ch) in text.bytes().take(n).enumerate() {
                let Some(g) = bignum_index(ch) else {
                    continue;
                };
                for (bx, &byte) in bignum::BIGNUM[g][dy].iter().enumerate() {
                    if byte == 0 {
                        continue;
                    }
                    for bit in 0..8 {
                        if byte >> bit & 1 == 1 {
                            let x = x0 + i * bignum::BIGNUM_WIDTH + bx * 8 + bit;
                            line[x / 8] |= 1 << (x % 8);
                        }
                    }
                }
            }
            for (bx, &b) in line.iter().enumerate() {
                if self.lines[y][bx] != b {
                    self.lines[y][bx] = b;
                    self.dirty[y] = true;
                }
            }
        }
    }

    /// Draw `text` as a run-view hero from the generated numeral faces,
    /// anchored at the left edge of the band whose top pixel row is `y0`:
    /// glyphs before the first `.` or `:` render in the 32x48 face, the
    /// separator and everything after in the 16x32 medium face sharing the
    /// digits' baseline — big integers (or minutes) with smaller decimals
    /// (or seconds), instead of pixel-scaling the 8x16 text font into ragged
    /// strokes. Composes and compare-writes only the pixels the hero spans,
    /// so pixels to its right (the fuel-overdue marker's cells) are never
    /// touched and an unchanged hero dirties nothing; a previously wider
    /// hero is erased by the text pass's row clearing. Characters outside
    /// the glyph set advance blank at the current size; glyphs past the
    /// right edge are dropped; clips at the bottom.
    pub fn draw_bignum_hero(&mut self, y0: usize, text: &str) {
        let med_from = text
            .bytes()
            .position(|b| b == b'.' || b == b':')
            .unwrap_or(text.len());
        let mut span_w = 0;
        let mut n = 0;
        for (i, _) in text.bytes().enumerate() {
            let w = if i < med_from {
                bignum::BIGNUM_WIDTH
            } else {
                bignum::BIGNUM_MED_WIDTH
            };
            if span_w + w > WIDTH {
                break;
            }
            span_w += w;
            n += 1;
        }
        for dy in 0..bignum::BIGNUM_HEIGHT {
            let y = y0 + dy;
            if y >= HEIGHT {
                return;
            }
            let mut line = [0u8; LINE_BYTES];
            let mut x = 0;
            for (i, ch) in text.bytes().take(n).enumerate() {
                if i < med_from {
                    if let Some(g) = bignum_index(ch) {
                        for (bx, &byte) in bignum::BIGNUM[g][dy].iter().enumerate() {
                            line[x / 8 + bx] |= byte;
                        }
                    }
                    x += bignum::BIGNUM_WIDTH;
                } else {
                    let med_dy = dy.wrapping_sub(MED_BASELINE_DROP);
                    if med_dy < bignum::BIGNUM_MED_HEIGHT {
                        if let Some(g) = bignum_index(ch) {
                            for (bx, &byte) in bignum::BIGNUM_MED[g][med_dy].iter().enumerate() {
                                line[x / 8 + bx] |= byte;
                            }
                        }
                    }
                    x += bignum::BIGNUM_MED_WIDTH;
                }
            }
            for (bx, &b) in line.iter().enumerate().take(span_w.div_ceil(8)) {
                if self.lines[y][bx] != b {
                    self.lines[y][bx] = b;
                    self.dirty[y] = true;
                }
            }
        }
    }

    /// Draw `text` as a two-row run-view hero entirely in the generated 16x32
    /// medium numeral face ([`bignum`]), anchored at the left edge of the band
    /// whose top pixel row is `y0`. Same cell size as [`Self::draw_text_2x`]
    /// — so a page whose face puts a label on row 2 keeps its layout — but
    /// natively rasterised instead of pixel-doubled from the 8x16 text font,
    /// which is where the ragged 2-px strokes come from. Composes and
    /// compare-writes only the pixels the hero spans, so the state tag in row
    /// 0's right cells is untouched and an unchanged hero dirties nothing;
    /// characters outside the glyph set advance blank, glyphs past the right
    /// edge are dropped, and it clips at the bottom.
    pub fn draw_bignum_med_hero(&mut self, y0: usize, text: &str) {
        let n = text.len().min(WIDTH / bignum::BIGNUM_MED_WIDTH);
        let span_bytes = (n * bignum::BIGNUM_MED_WIDTH).div_ceil(8);
        for dy in 0..bignum::BIGNUM_MED_HEIGHT {
            let y = y0 + dy;
            if y >= HEIGHT {
                return;
            }
            let mut line = [0u8; LINE_BYTES];
            for (i, ch) in text.bytes().take(n).enumerate() {
                let Some(g) = bignum_index(ch) else {
                    continue;
                };
                let x = i * bignum::BIGNUM_MED_WIDTH;
                for (bx, &byte) in bignum::BIGNUM_MED[g][dy].iter().enumerate() {
                    line[x / 8 + bx] |= byte;
                }
            }
            for (bx, &b) in line.iter().enumerate().take(span_bytes) {
                if self.lines[y][bx] != b {
                    self.lines[y][bx] = b;
                    self.dirty[y] = true;
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

fn bignum_index(ch: u8) -> Option<usize> {
    bignum::BIGNUM_GLYPHS.iter().position(|&c| c == ch)
}

/// Last row of a glyph carrying ink — the shared baseline both numeral faces
/// centre their (descender-free) ink band around.
const fn ink_bottom<const RB: usize, const H: usize>(glyph: &[[u8; RB]; H]) -> usize {
    let mut y = H;
    while y > 0 {
        y -= 1;
        let mut bx = 0;
        while bx < RB {
            if glyph[y][bx] != 0 {
                return y;
            }
            bx += 1;
        }
    }
    0
}

/// Rows the medium face drops below the big face's cell top so a `0` in each
/// lands on the same baseline. Derived from the tables, so a regeneration
/// that re-centres the ink bands keeps the mixed hero aligned.
const MED_BASELINE_DROP: usize =
    ink_bottom(&bignum::BIGNUM[0]) - ink_bottom(&bignum::BIGNUM_MED[0]);

/// Angle of the screen vector `(dx, dy)` in degrees `0..360`, 0 at +x and
/// increasing toward +y (clockwise on-screen). Integer-only: the in-octant
/// angle is a linear ratio of the shorter to the longer leg, good to a few
/// degrees — plenty for classifying midpoint-circle pixels into an arc sweep,
/// where only pixels within a couple of degrees of an endpoint are borderline.
fn angle_deg(dy: i32, dx: i32) -> i32 {
    if dx == 0 && dy == 0 {
        return 0;
    }
    let ax = dx.abs();
    let ay = dy.abs();
    let q = if ax >= ay {
        45 * ay / ax
    } else {
        90 - 45 * ax / ay
    };
    match (dx >= 0, dy >= 0) {
        (true, true) => q,
        (false, true) => 180 - q,
        (false, false) => 180 + q,
        (true, false) => 360 - q,
    }
}

fn glyph_for(ch: char) -> &'static [u8; font::GLYPH_HEIGHT] {
    let index = (ch as usize)
        .checked_sub(font::FIRST_CHAR as usize)
        .filter(|&i| i < font::FONT.len())
        .unwrap_or((b'?' - font::FIRST_CHAR) as usize);
    &font::FONT[index]
}
