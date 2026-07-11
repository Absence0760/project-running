//! Face widgets: gauges, bars, the GPS signal meter, and the page indicator.
//!
//! Each public `draw_*_overlay` takes the same `watch_core` state the ui task
//! already holds and paints its pixels onto the shared framebuffer, folding in
//! the pure `gauge` / `statusbar` math so the whole widget — geometry included
//! — is exercised by `cargo test`, not just its arithmetic. Coordinates are
//! derived from the panel's cell grid so they track the text layout the face
//! renders underneath.
//!
//! Placement contract with `watch_core::face`: these overlays draw into cells
//! the face leaves blank on the matching page (the pacer page's row 3, the fuel
//! page's row 3, the gear page's row 5, the trailing bar columns of the zone /
//! split rows, the split page's rows 3..8). Change one side and the other must
//! follow — the tests here pin the columns each overlay owns.

use sharp_mip::{Framebuffer, HEIGHT, TEXT_COLS, TEXT_ROWS, WIDTH};
use watch_core::bar_chart::{bar_chart, Bar};
use watch_core::fix::Fix;
use watch_core::gauge;
use watch_core::record::Snapshot;
use watch_core::statusbar::{self, PageIndicator};

const CELL_W: usize = WIDTH / TEXT_COLS; // 8
const CELL_H: usize = HEIGHT / TEXT_ROWS; // 16

/// Left column (in pixels) where a single-metric page's in-row bar starts —
/// clear of the ~11-char label gutter the pacer / gear / fuel rows carry.
const BAR_X: usize = 11 * CELL_W; // 88
const BAR_W: usize = WIDTH - BAR_X - 3; // to just shy of the right edge
const BAR_H: usize = 8; // sits inside a 16-px row with 4 px of margin above/below

/// Vertical offset of a bar within its text row: centres the 8-px bar in the
/// 16-px cell.
const BAR_DY: usize = (CELL_H - BAR_H) / 2;

fn bar_y(row: usize) -> usize {
    row * CELL_H + BAR_DY
}

// ---------------------------------------------------------------------------
// GPS signal meter (idle status face)
// ---------------------------------------------------------------------------

const SIGNAL_TICKS: usize = statusbar::MAX_BARS as usize;
const TICK_W: usize = 4;
const TICK_GAP: usize = 2;
const TICK_STEP: usize = TICK_W + TICK_GAP;
const TICK_GROW: usize = 3; // each tick is 3 px taller than the one left of it
const TICK_BASE_H: usize = 4;

/// Total pixel width the [`draw_signal_bars`] meter occupies.
pub const SIGNAL_METER_W: usize = SIGNAL_TICKS * TICK_W + (SIGNAL_TICKS - 1) * TICK_GAP;

/// Draw the GPS acquisition-confidence meter: a rising staircase of
/// [`statusbar::MAX_BARS`] ticks whose bottom-right corner sits at
/// `(right_x, baseline_y)`. The leftmost `bars` ticks are filled, the rest are
/// hollow, so "searching" (0) still shows the empty frame and never a blank gap
/// the runner could mistake for "no widget".
pub fn draw_signal_bars(fb: &mut Framebuffer, right_x: usize, baseline_y: usize, bars: u8) {
    let left = (right_x + 1).saturating_sub(SIGNAL_METER_W);
    for i in 0..SIGNAL_TICKS {
        let h = TICK_BASE_H + i * TICK_GROW;
        let x = left + i * TICK_STEP;
        let top = (baseline_y + 1).saturating_sub(h);
        if (i as u8) < bars {
            fb.fill_rect(x, top, TICK_W, h, true);
        } else {
            fb.stroke_rect(x, top, TICK_W, h, true);
        }
    }
}

/// Idle-face GPS signal meter, top-right of the brand row (row 0), from the live
/// fix + its freshness. Drawn only on the idle status face; a run view shows the
/// per-row GPS glance instead.
pub fn draw_idle_signal(
    fb: &mut Framebuffer,
    fix: Option<&Fix>,
    uptime_s: u32,
    stale_after_s: u32,
) {
    let bars = statusbar::gps_bars(fix, uptime_s, stale_after_s);
    draw_signal_bars(fb, WIDTH - 2, CELL_H - 2, bars);
}

// ---------------------------------------------------------------------------
// Page-position indicator (run view, top edge)
// ---------------------------------------------------------------------------

/// The run-view page-position indicator: a full-width track along the top edge
/// with a filled thumb over the active page's segment, so paging is a thumb
/// sliding left-to-right. Sits in the top 4 px — blank on every page because the
/// 2x hero's ink starts well below it and the state tag rides row 0's right cells.
pub fn draw_page_indicator(fb: &mut Framebuffer, indicator: PageIndicator) {
    if indicator.total == 0 {
        return;
    }
    fb.hline(0, 3, WIDTH, true);
    let seg = WIDTH / indicator.total;
    let thumb_w = seg.max(2);
    let x = (indicator.active * WIDTH / indicator.total).min(WIDTH - thumb_w);
    fb.fill_rect(x, 0, thumb_w, 3, true);
}

// ---------------------------------------------------------------------------
// Single-value gauges (pacer / gear / fuel pages)
// ---------------------------------------------------------------------------

/// The pacer page's ahead/behind gauge: a centre-out bar on row 3 fed by
/// [`gauge::pacer_fill`]. No-op without a configured pacer goal, so the honest
/// "NO GOAL SET" text the face draws stands alone.
pub fn draw_pacer_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(status) = snap.pacer {
        fb.draw_center_bar(4, bar_y(3), WIDTH - 8, BAR_H, gauge::pacer_fill(&status));
    }
}

/// The gear page's wear gauge: a progress bar on row 5 fed by
/// [`gauge::gear_fill`], plus an end-of-bar alert block once the shoe is
/// [`gauge::gear_overdue`] so "replace me" reads without counting pixels.
pub fn draw_gear_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(gear) = snap.gear {
        fb.draw_progress_bar(BAR_X, bar_y(5), BAR_W, BAR_H, gauge::gear_fill(&gear));
        if gauge::gear_overdue(&gear) {
            fb.fill_rect(WIDTH - 3, 5 * CELL_H + 2, 2, CELL_H - 4, true);
        }
    }
}

/// The fuel page's carry-load gauge: a progress bar on row 3 fed by
/// [`gauge::fuel_fill`] (share of the plan's carbohydrate riding in the next
/// carry-out). No-op without a loaded fuel plan.
pub fn draw_fuel_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(fuel) = snap.fuel {
        fb.draw_progress_bar(BAR_X, bar_y(3), BAR_W, BAR_H, gauge::fuel_fill(&fuel));
    }
}

// ---------------------------------------------------------------------------
// Zone bars (zones page, rows 3..8)
// ---------------------------------------------------------------------------

/// Left column of the zone / split in-row bar — past the "Z1 12:34" (12-char)
/// label the face writes.
const ZONE_BAR_X: usize = 12 * CELL_W; // 96
const ZONE_BAR_W: usize = WIDTH - ZONE_BAR_X - 3;

/// The zones page's per-zone bars: one horizontal bar per zone row (rows 3..8),
/// each scaled to the fullest zone so the dominant effort reads at full width —
/// the pixel form of the `#` bars the face used to spell out. The live zone
/// (from [`gauge::current_zone`]) gets a hollow frame so a glance finds "where
/// am I now" among the five.
pub fn draw_zones_overlay(fb: &mut Framebuffer, snap: &Snapshot, hr_bpm: Option<u16>) {
    let max = snap.zone_time_s.iter().copied().max().unwrap_or(0);
    let current = hr_bpm.map(|bpm| gauge::current_zone(bpm, &snap.zone_cutoffs));
    for (i, &t) in snap.zone_time_s.iter().enumerate() {
        let row = 3 + i;
        let y = bar_y(row);
        if max > 0 {
            let w = (ZONE_BAR_W as u64 * t as u64 / max as u64) as usize;
            if w > 0 {
                fb.fill_rect(ZONE_BAR_X, y, w, BAR_H, true);
            }
        }
        if current == Some(i) {
            fb.stroke_rect(
                ZONE_BAR_X - 2,
                row * CELL_H + 2,
                ZONE_BAR_W + 4,
                CELL_H - 4,
                true,
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Splits histogram (splits page, rows 3..8)
// ---------------------------------------------------------------------------

const HIST_X: usize = 6;
const HIST_TOP_ROW: usize = 3;
const HIST_W: usize = WIDTH - 2 * HIST_X;
const HIST_H: usize = (TEXT_ROWS - HIST_TOP_ROW - 1) * CELL_H - 4; // rows 3..8, minus baseline gap
const HIST_GAP: usize = 4;

/// The splits page's pace-distribution histogram: the per-bucket banked
/// distance (slowest bucket left, fastest right) as bottom-aligned vertical
/// bars via [`bar_chart`], with a baseline rule. A histogram reads the *shape*
/// of where the run's distance sat, pace-wise, at a glance — what the per-row
/// `#` bars only approximated.
pub fn draw_splits_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    let py = HIST_TOP_ROW * CELL_H;
    let mut bars = [Bar {
        x: 0,
        y: 0,
        w: 0,
        h: 0,
    }; 8];
    let n = bar_chart(
        &snap.pace_bucket_m,
        HIST_W as u16,
        HIST_H as u16,
        HIST_GAP as u16,
        &mut bars,
    );
    fb.hline(HIST_X, py + HIST_H, HIST_W, true);
    for b in &bars[..n] {
        if b.h > 0 {
            fb.fill_rect(
                HIST_X + b.x as usize,
                py + b.y as usize,
                b.w as usize,
                b.h as usize,
                true,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use watch_core::gear_wear::gear_wear;
    use watch_core::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM, ZONE_COUNT};
    use watch_core::pacer::{PaceVerdict, PacerGoal, PacerStatus};
    use watch_core::record::{FuelCarryView, FuelView, RecordState, PACE_BUCKET_COUNT};

    // Count set pixels inside a rectangle — the tests assert *where* ink lands.
    fn ink_in(fb: &Framebuffer, x: usize, y: usize, w: usize, h: usize) -> usize {
        let mut n = 0;
        for yy in y..y + h {
            for xx in x..x + w {
                if fb.pixel(xx, yy) {
                    n += 1;
                }
            }
        }
        n
    }

    // A live-recording base snapshot with every optional overlay input empty;
    // each test sets just the field its overlay reads.
    fn snapshot() -> Snapshot {
        Snapshot {
            state: RecordState::Recording,
            distance_m: 0.0,
            elapsed_s: 0,
            moving_s: 0,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
            gap_s_per_km: None,
            lap: 1,
            lap_distance_m: 0.0,
            lap_elapsed_s: 0,
            last_lap: None,
            pacer: None,
            zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            zone_time_s: [0; ZONE_COUNT],
            cutoff: None,
            race_prediction: None,
            pace_bucket_m: [0.0; PACE_BUCKET_COUNT],
            training_stress: None,
            band: None,
            gear: None,
            roadbook: None,
            fuel: None,
        }
    }

    #[test]
    fn signal_meter_fills_left_to_right() {
        let mut fb = Framebuffer::new();
        let (right_x, baseline_y) = (WIDTH - 2, CELL_H - 2);
        draw_signal_bars(&mut fb, right_x, baseline_y, 2);
        // With 2 bars lit, the left ticks are SOLID (interior inked) and the
        // right ticks are HOLLOW (interior blank, frame inked) — the per-tick
        // fill/frame distinction, independent of the staircase heights.
        let left = (right_x + 1) - SIGNAL_METER_W;
        let interior = |i: usize| {
            let x = left + i * TICK_STEP + TICK_W / 2;
            let y = baseline_y - 2; // a couple of px up from the base, inside every tick
            (x, y)
        };
        let (x0, y0) = interior(0);
        assert!(fb.pixel(x0, y0), "lit tick 0 is solid");
        let (x3, y3) = interior(3);
        assert!(!fb.pixel(x3, y3), "unlit tick 3 is hollow (blank interior)");
        // ...but its frame is drawn: the tick's left edge column carries ink.
        assert!(
            fb.pixel(left + 3 * TICK_STEP, baseline_y),
            "hollow tick keeps its frame"
        );
    }

    #[test]
    fn signal_meter_zero_is_all_frames_not_blank() {
        let mut fb = Framebuffer::new();
        draw_signal_bars(&mut fb, WIDTH - 2, CELL_H - 2, 0);
        let left = WIDTH - 1 - SIGNAL_METER_W;
        assert!(ink_in(&fb, left, 0, SIGNAL_METER_W, CELL_H) > 0);
    }

    #[test]
    fn signal_meter_full_beats_partial() {
        let mut a = Framebuffer::new();
        let mut b = Framebuffer::new();
        draw_signal_bars(&mut a, WIDTH - 2, CELL_H - 2, 4);
        draw_signal_bars(&mut b, WIDTH - 2, CELL_H - 2, 1);
        let left = WIDTH - 1 - SIGNAL_METER_W;
        assert!(
            ink_in(&a, left, 0, SIGNAL_METER_W, CELL_H)
                > ink_in(&b, left, 0, SIGNAL_METER_W, CELL_H)
        );
    }

    #[test]
    fn page_indicator_thumb_moves_with_the_active_page() {
        let mut early = Framebuffer::new();
        let mut late = Framebuffer::new();
        draw_page_indicator(
            &mut early,
            PageIndicator {
                active: 0,
                total: 16,
            },
        );
        draw_page_indicator(
            &mut late,
            PageIndicator {
                active: 15,
                total: 16,
            },
        );
        // Thumb ink (rows 0..3) sits at the left for page 0, the right for the last.
        assert!(ink_in(&early, 0, 0, 12, 3) > 0);
        assert_eq!(ink_in(&early, WIDTH - 12, 0, 12, 3), 0);
        assert!(ink_in(&late, WIDTH - 12, 0, 12, 3) > 0);
        assert_eq!(ink_in(&late, 0, 0, 12, 3), 0);
        // Both draw the full-width track on row 3.
        assert_eq!(ink_in(&late, 0, 3, WIDTH, 1), WIDTH);
    }

    #[test]
    fn page_indicator_zero_total_is_a_noop() {
        let mut fb = Framebuffer::new();
        draw_page_indicator(
            &mut fb,
            PageIndicator {
                active: 0,
                total: 0,
            },
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, CELL_H), 0);
    }

    fn pacer(ahead_s: i32) -> PacerStatus {
        PacerStatus {
            goal: PacerGoal {
                distance_m: 10_000,
                time_s: 3_000,
            },
            ahead_m: 0.0,
            ahead_s,
            projected_finish_s: None,
            verdict: PaceVerdict::OnPace,
            finished: false,
        }
    }

    #[test]
    fn pacer_overlay_leans_right_when_ahead_left_when_behind() {
        let mut ahead = snapshot();
        ahead.pacer = Some(pacer(90));
        let mut behind = snapshot();
        behind.pacer = Some(pacer(-90));
        let (mut fa, mut fb) = (Framebuffer::new(), Framebuffer::new());
        draw_pacer_overlay(&mut fa, &ahead);
        draw_pacer_overlay(&mut fb, &behind);
        let y = bar_y(3);
        let mid = WIDTH / 2;
        // Ahead fills right of centre; behind fills left of centre.
        assert!(ink_in(&fa, mid + 2, y, mid - 6, BAR_H) > ink_in(&fa, 6, y, mid - 8, BAR_H));
        assert!(ink_in(&fb, 6, y, mid - 8, BAR_H) > ink_in(&fb, mid + 2, y, mid - 6, BAR_H));
    }

    #[test]
    fn pacer_overlay_without_goal_draws_nothing() {
        let mut fb = Framebuffer::new();
        draw_pacer_overlay(&mut fb, &snapshot());
        assert_eq!(ink_in(&fb, 0, bar_y(3), WIDTH, BAR_H), 0);
    }

    #[test]
    fn gear_overlay_bar_grows_with_wear_and_flags_overdue() {
        let mut half = snapshot();
        half.gear = Some(gear_wear(Some(400_000.0), Some(800_000.0)));
        let mut worn = snapshot();
        worn.gear = Some(gear_wear(Some(900_000.0), Some(800_000.0)));
        let (mut fh, mut fw) = (Framebuffer::new(), Framebuffer::new());
        draw_gear_overlay(&mut fh, &half);
        draw_gear_overlay(&mut fw, &worn);
        let y = bar_y(5);
        // A worn shoe's bar carries more fill than a half-worn one...
        assert!(ink_in(&fw, BAR_X, y, BAR_W, BAR_H) > ink_in(&fh, BAR_X, y, BAR_W, BAR_H));
        // ...and only the worn one paints the end-of-bar alert block.
        assert!(ink_in(&fw, WIDTH - 3, 5 * CELL_H, 2, CELL_H) > 0);
        assert_eq!(ink_in(&fh, WIDTH - 3, 5 * CELL_H, 2, CELL_H), 0);
    }

    #[test]
    fn fuel_overlay_bar_scales_with_carry_share() {
        let mut full = snapshot();
        full.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 120.0,
                fluid_ml: 0.0,
            }),
            total_carbs_g: 120.0,
            total_fluid_ml: 0.0,
        });
        let mut part = snapshot();
        part.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 30.0,
                fluid_ml: 0.0,
            }),
            total_carbs_g: 120.0,
            total_fluid_ml: 0.0,
        });
        let (mut ff, mut fp) = (Framebuffer::new(), Framebuffer::new());
        draw_fuel_overlay(&mut ff, &full);
        draw_fuel_overlay(&mut fp, &part);
        let y = bar_y(3);
        assert!(ink_in(&ff, BAR_X, y, BAR_W, BAR_H) > ink_in(&fp, BAR_X, y, BAR_W, BAR_H));
    }

    #[test]
    fn zones_overlay_dominant_zone_is_widest_and_current_is_framed() {
        let mut snap = snapshot();
        snap.zone_time_s = [600, 300, 120, 0, 0];
        snap.zone_cutoffs = zone_cutoffs_from_max_hr(190);
        let mut fb = Framebuffer::new();
        draw_zones_overlay(&mut fb, &snap, Some(140)); // ~Z3
                                                       // Z1 (row 3, biggest time) out-fills Z2 (row 4) out-fills Z3 (row 5).
        let w1 = ink_in(&fb, ZONE_BAR_X, bar_y(3), ZONE_BAR_W, BAR_H);
        let w2 = ink_in(&fb, ZONE_BAR_X, bar_y(4), ZONE_BAR_W, BAR_H);
        let w3 = ink_in(&fb, ZONE_BAR_X, bar_y(5), ZONE_BAR_W, BAR_H);
        assert!(w1 > w2 && w2 > w3, "bars scale to the fullest zone");
        // A hollow frame marks the live zone row (Z3 -> row 5); the empty
        // zones 4/5 draw no bar fill.
        assert!(ink_in(&fb, ZONE_BAR_X - 2, 5 * CELL_H + 2, 2, CELL_H - 4) > 0);
    }

    #[test]
    fn zones_overlay_sensorless_run_draws_no_bars() {
        let mut fb = Framebuffer::new();
        draw_zones_overlay(&mut fb, &snapshot(), None);
        assert_eq!(
            ink_in(&fb, ZONE_BAR_X, 3 * CELL_H, ZONE_BAR_W, 5 * CELL_H),
            0
        );
    }

    #[test]
    fn splits_overlay_taller_bar_for_the_bigger_bucket() {
        let mut snap = snapshot();
        snap.pace_bucket_m = [1000.0, 4000.0, 2000.0, 0.0, 0.0, 0.0];
        let mut fb = Framebuffer::new();
        draw_splits_overlay(&mut fb, &snap);
        // The histogram panel carries ink, and the baseline rule spans it.
        let py = HIST_TOP_ROW * CELL_H;
        assert!(ink_in(&fb, HIST_X, py, HIST_W, HIST_H) > 0);
        assert_eq!(ink_in(&fb, HIST_X, py + HIST_H, HIST_W, 1), HIST_W);
    }
}
