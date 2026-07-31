//! Countdown timer + stopwatch — one instrument, honest about the fact that
//! nothing on this device can interrupt anyone (decisions § 375).
//!
//! The tier-1 BOM has **no vibration motor and no buzzer**. Every alert in this
//! firmware is display-only ([`crate::alerts`] says so in its own module doc),
//! and the roadmap's sleep-station wedge already records the consequence: a nap
//! timer "needs the tier-2 haptic channel to actually wake anyone". So there is
//! no alarm here and the word never appears on the device — a surface whose
//! whole contract is *this will interrupt you at a time you are not watching*
//! cannot be built out of a screen nobody is looking at. What can be built
//! honestly is an instrument the runner **consults**, and that shapes three
//! things:
//!
//! - **An expired countdown counts up past zero rather than freezing at 0:00.**
//!   A kitchen timer may stop at zero because its beep said when. This one
//!   cannot say when, so the runner's first question on looking down is *how
//!   long ago*, and the page answers it: `+2:14`. Freezing at zero would throw
//!   away the only part of the expiry that survives being missed.
//! - **The expiry banner rides the one shared alert slot** ([`crate::alerts`]),
//!   at the milestone rung and **dropped rather than queued** when the slot is
//!   busy — the milestone rule for the milestone reason: the page carries the
//!   overtime, so a banner the runner missed costs nothing recoverable. It never
//!   outranks fuel, which is the one reminder § 214 says must never be lost.
//! - **The alert slot is a run surface, so an idle expiry raises no banner.**
//!   The instrument is still correct — the modal and the page both read the
//!   overtime — it simply makes no claim it cannot keep.
//!
//! One instrument, one ladder. [`PRESETS_S`] starts at zero, and zero *is* the
//! stopwatch: with nothing to count down to it counts up. That is why there is
//! no mode switch and no second key — a stopwatch is a countdown from nothing.
//!
//! Every reading is derived from the caller's `now_s` against a stored start
//! stamp, so an armed timer needs no tick of its own: nothing here is a standing
//! wake (§ 328), and the two consumers (the record task's 1 Hz snapshot, the ui
//! task's redraw) each read it at whatever cadence they already pay for.

use core::fmt::Write;

use crate::face::{Row, ROWS};

/// The preset ladder, seconds. Index 0 is the stopwatch (nothing to count down
/// to). Every other rung is a duration this project's own personas or roadmap
/// name: 1 / 3 / 5 min is an aid-station turnaround, 10 through 90 covers the
/// documented 20-90 minute sleep-station nap, and 60 min is the backyard-ultra
/// bell the roadmap's backyard-mode wedge is built around.
pub const PRESETS_S: [u32; 11] = [0, 60, 180, 300, 600, 900, 1_200, 1_800, 2_700, 3_600, 5_400];

/// Seconds of inactivity before an open timer modal closes itself, deriving
/// from the settings menu's deadline rather than restating 30: both modals
/// cover the home clock, "the home face always tells the time" is one
/// navigation invariant, and two numbers for one rule would drift.
pub const TIMER_MENU_TIMEOUT_S: u32 = crate::settings_menu::MENU_TIMEOUT_S;

/// Longest reading the clock formatter renders before clamping — the point past
/// which a wrist timer is measuring something it was not set for.
pub const CLOCK_MAX_S: u32 = 99 * 3600 + 59 * 60 + 59;

/// A formatted clock reading: `M:SS` under an hour, `H:MM:SS` over it, with a
/// leading `+` on an overrun.
pub type Clock = heapless::String<9>;

/// `s` as `M:SS` / `H:MM:SS`, clamped at [`CLOCK_MAX_S`].
pub fn format_clock(s: u32) -> Clock {
    let mut out = Clock::new();
    let s = s.min(CLOCK_MAX_S);
    let _ = if s >= 3600 {
        write!(out, "{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        write!(out, "{}:{:02}", s / 60, s % 60)
    };
    out
}

/// What the face and the modal draw for one instant of the instrument.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TimerView {
    /// The duration the countdown was armed with; 0 = stopwatch.
    pub preset_s: u32,
    /// Seconds the instrument has run, counting up, across every start/stop.
    pub elapsed_s: u32,
    /// The number to show: seconds remaining before expiry, seconds *past* zero
    /// after it, and simply [`Self::elapsed_s`] for a stopwatch.
    pub display_s: u32,
    /// The clock is advancing right now.
    pub running: bool,
    /// A countdown that has reached zero. Always false for a stopwatch — a
    /// stopwatch has no zero to reach.
    pub expired: bool,
    /// Non-zero exactly once per arming that has expired, and different on each
    /// arming — the once-per-edge counter [`crate::alerts`] keys the banner on,
    /// the same shape the workout runner's `transition_seq` uses. 0 while the
    /// countdown has not expired (and always, for a stopwatch).
    pub expiry_seq: u16,
}

impl TimerView {
    /// The reading, signed on an overrun: `+2:14` is two minutes past zero.
    /// Both surfaces call this, so the modal and the page cannot show the same
    /// instrument two ways.
    pub fn display(&self) -> Clock {
        let mut out = Clock::new();
        if self.expired {
            let _ = out.push('+');
        }
        let _ = out.push_str(&format_clock(self.display_s));
        out
    }

    /// The word under the reading. `TIME UP` outranks the run state: a runner
    /// who has overrun needs that before they need to know the clock is still
    /// moving.
    pub fn state_word(&self) -> &'static str {
        if self.expired {
            "TIME UP"
        } else if self.running {
            "RUNNING"
        } else if self.elapsed_s > 0 {
            "STOPPED"
        } else {
            "READY"
        }
    }

    /// `STOPWATCH` when there is nothing to count down to, else `TIMER`. The two
    /// read completely differently and the title is the only thing that says
    /// which.
    pub fn title(&self) -> &'static str {
        if self.preset_s == 0 {
            "STOPWATCH"
        } else {
            "TIMER"
        }
    }
}

/// The instrument. Small and `Copy` so the owning task can publish it whole and
/// each consumer derive its own view at its own cadence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Timer {
    preset_idx: u8,
    /// Seconds banked by previous legs (stop / resume).
    banked_s: u32,
    /// Uptime the current leg started at; `None` while stopped.
    running_since_s: Option<u32>,
    /// Bumped on each start from a cleared instrument, never on a resume, so one
    /// arming raises at most one expiry edge. 0 until first armed; a wrap lands
    /// on 1, never back on 0, so it cannot alias "never armed".
    arm_seq: u16,
}

impl Default for Timer {
    fn default() -> Self {
        Self::new()
    }
}

impl Timer {
    pub const fn new() -> Self {
        Self {
            preset_idx: 0,
            banked_s: 0,
            running_since_s: None,
            arm_seq: 0,
        }
    }

    pub fn preset_s(&self) -> u32 {
        PRESETS_S[self.preset_idx as usize]
    }

    pub fn running(&self) -> bool {
        self.running_since_s.is_some()
    }

    /// Seconds run so far. A `now_s` behind the start stamp saturates to zero
    /// rather than wrapping into a century.
    pub fn elapsed_s(&self, now_s: u32) -> u32 {
        match self.running_since_s {
            Some(since) => self.banked_s.saturating_add(now_s.saturating_sub(since)),
            None => self.banked_s,
        }
    }

    /// Whether the instrument holds anything worth a page seat: it is running,
    /// or stopped holding a reading. A preset dialled but never started is
    /// deliberately *not* armed — the runner is standing at the watch with the
    /// modal open, and a page for a timer they have not started is a page for
    /// nothing.
    pub fn is_armed(&self) -> bool {
        self.running() || self.banked_s > 0
    }

    /// One rung up the ladder (longer). Refused once armed: moving the target
    /// under a running countdown would silently shift an expiry the runner is
    /// already timing against. Returns whether anything moved.
    pub fn preset_up(&mut self) -> bool {
        if self.is_armed() || self.preset_idx as usize + 1 >= PRESETS_S.len() {
            return false;
        }
        self.preset_idx += 1;
        true
    }

    /// One rung down (shorter), clamped at the stopwatch. Same arming refusal.
    pub fn preset_down(&mut self) -> bool {
        if self.is_armed() || self.preset_idx == 0 {
            return false;
        }
        self.preset_idx -= 1;
        true
    }

    /// Start, or stop and bank the current leg. A start from a cleared
    /// instrument is a fresh arming and takes a new [`TimerView::expiry_seq`]; a
    /// resume keeps the arming it is resuming, so a countdown stopped and
    /// restarted across its own expiry still raises exactly one banner.
    pub fn start_stop(&mut self, now_s: u32) {
        match self.running_since_s {
            Some(since) => {
                self.banked_s = self.banked_s.saturating_add(now_s.saturating_sub(since));
                self.running_since_s = None;
            }
            None => {
                if self.banked_s == 0 {
                    self.arm_seq = self.arm_seq.checked_add(1).unwrap_or(1);
                }
                self.running_since_s = Some(now_s);
            }
        }
    }

    /// Back to the preset with the clock cleared. Refused while running, so a
    /// brushed sleeve cannot zero a timing the runner is in the middle of — the
    /// stop guard's one-extra-press shape, for a much cheaper loss. Returns
    /// whether anything was cleared.
    pub fn reset(&mut self) -> bool {
        if self.running() || self.banked_s == 0 {
            return false;
        }
        self.banked_s = 0;
        true
    }

    pub fn view(&self, now_s: u32) -> TimerView {
        let elapsed_s = self.elapsed_s(now_s);
        let preset_s = self.preset_s();
        let expired = preset_s > 0 && elapsed_s >= preset_s;
        TimerView {
            preset_s,
            elapsed_s,
            display_s: if preset_s == 0 {
                elapsed_s
            } else if expired {
                elapsed_s - preset_s
            } else {
                preset_s - elapsed_s
            },
            running: self.running(),
            expired,
            expiry_seq: if expired { self.arm_seq } else { 0 },
        }
    }

    /// The view the recorder is fed — `None` while nothing is armed, which is
    /// what keeps the page out of the cycle and its metric honestly unfed.
    pub fn snapshot_view(&self, now_s: u32) -> Option<TimerView> {
        self.is_armed().then(|| self.view(now_s))
    }
}

/// A press inside the timer modal, by what the key means rather than by which
/// pin it arrived on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum TimerKey {
    /// BTN1, the § 81 START slot — start / stop / resume, the same context verb
    /// that key carries everywhere else on this device.
    StartStop,
    /// BTN2, the UP slot — one rung longer.
    Longer,
    /// BTN3, the DOWN slot — one rung shorter.
    Shorter,
    /// BTN5 — clear the reading back to the preset.
    Reset,
    /// BTN4, the § 81 BACK slot — leave the modal. The instrument keeps running;
    /// the modal is a view of it, not its container.
    Exit,
}

/// What the owning task does with a press.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum TimerPress {
    /// The instrument moved — republish and re-arm the inactivity deadline.
    Changed,
    /// Close the modal.
    Exit,
    /// A clamped ladder end, or a reset with nothing to clear. Nothing moved,
    /// exactly like § 351's idempotent edits: a press that asks for the state it
    /// is already in is a no-op, never an overshoot.
    Nothing,
}

/// Apply a press. Pure, so both button-task variants and the tests read one
/// truth — and every press is consumed here, so none of them can reach the
/// recorder from inside the modal.
pub fn press(timer: &mut Timer, key: TimerKey, now_s: u32) -> TimerPress {
    match key {
        TimerKey::Exit => TimerPress::Exit,
        TimerKey::StartStop => {
            timer.start_stop(now_s);
            TimerPress::Changed
        }
        TimerKey::Longer => {
            if timer.preset_up() {
                TimerPress::Changed
            } else {
                TimerPress::Nothing
            }
        }
        TimerKey::Shorter => {
            if timer.preset_down() {
                TimerPress::Changed
            } else {
                TimerPress::Nothing
            }
        }
        TimerKey::Reset => {
            if timer.reset() {
                TimerPress::Changed
            } else {
                TimerPress::Nothing
            }
        }
    }
}

/// First row of the modal's body — rows 0 and 1 are chrome, mirroring the
/// settings menu's legend + title band.
const TIMER_TOP_ROW: usize = 3;

/// The modal's text rows.
///
/// The legend names what § 337 demands: the exit (on BTN4 here, where the
/// settings menu also puts it, and *not* where the grid puts it), and BTN1's
/// verb, which changes with the state it is about to produce. The two ladder
/// keys and the reset are named on a contextual row instead of the legend,
/// because each is live only in one state and a legend that lists a key doing
/// nothing is worse than one that omits it.
pub fn timer_rows(timer: &Timer, now_s: u32) -> [Row; ROWS] {
    let v = timer.view(now_s);
    let mut rows: [Row; ROWS] = Default::default();
    let start = if v.running { "B1 STOP" } else { "B1 START" };
    let _ = write!(rows[0], "{:<14}B4 EXIT", start);
    let _ = rows[1].push_str(v.title());
    let _ = write!(rows[TIMER_TOP_ROW], "{}", v.display());
    let _ = rows[TIMER_TOP_ROW + 1].push_str(v.state_word());
    if timer.is_armed() {
        // The preset the reading is measured against, once it can no longer be
        // read off the ladder row.
        if v.preset_s > 0 {
            let _ = write!(rows[TIMER_TOP_ROW + 2], "SET {}", format_clock(v.preset_s));
        }
        if !v.running {
            let _ = rows[TIMER_TOP_ROW + 3].push_str("B5 RESET");
        }
    } else {
        let _ = rows[TIMER_TOP_ROW + 3].push_str("B2 LONGER B3 SHORTER");
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::COLS;

    #[test]
    fn the_ladder_starts_at_the_stopwatch_and_only_climbs() {
        assert_eq!(PRESETS_S[0], 0, "rung zero IS the stopwatch");
        for w in PRESETS_S.windows(2) {
            assert!(w[1] > w[0], "the ladder must be strictly increasing: {w:?}");
        }
        // The backyard-ultra bell and the top of the documented nap range are
        // both reachable rungs — the two durations the roadmap names.
        assert!(PRESETS_S.contains(&3_600));
        assert!(PRESETS_S.contains(&5_400));
    }

    #[test]
    fn a_fresh_timer_is_a_stopwatch_and_is_not_armed() {
        let t = Timer::new();
        assert_eq!(t.preset_s(), 0);
        assert!(!t.is_armed(), "a page seat is not owed before a start");
        assert_eq!(t.snapshot_view(0), None);
        let v = t.view(0);
        assert_eq!(v.title(), "STOPWATCH");
        assert_eq!(v.state_word(), "READY");
        assert!(!v.expired, "a stopwatch has no zero to reach");
    }

    #[test]
    fn the_preset_ladder_clamps_at_both_ends() {
        let mut t = Timer::new();
        assert!(!t.preset_down(), "already at the bottom rung");
        for expected in &PRESETS_S[1..] {
            assert!(t.preset_up());
            assert_eq!(t.preset_s(), *expected);
        }
        assert!(!t.preset_up(), "no wrap-teleport off the top rung");
        assert_eq!(t.preset_s(), *PRESETS_S.last().unwrap());
    }

    #[test]
    fn the_ladder_is_refused_once_armed() {
        let mut t = Timer::new();
        t.preset_up();
        let target = t.preset_s();
        t.start_stop(100);
        assert!(!t.preset_up());
        assert!(!t.preset_down());
        assert_eq!(t.preset_s(), target);
        // Still refused while stopped-but-holding a reading.
        t.start_stop(130);
        assert!(t.is_armed());
        assert!(!t.preset_up());
        // Cleared, and the ladder is live again.
        assert!(t.reset());
        assert!(t.preset_up());
    }

    #[test]
    fn a_stopwatch_counts_up_from_the_start() {
        let mut t = Timer::new();
        t.start_stop(1_000);
        assert!(t.is_armed());
        let v = t.view(1_042);
        assert_eq!(v.elapsed_s, 42);
        assert_eq!(v.display_s, 42);
        assert_eq!(v.display().as_str(), "0:42");
        assert_eq!(v.state_word(), "RUNNING");
    }

    #[test]
    fn a_countdown_counts_down_then_over_rather_than_freezing() {
        // The whole honesty argument in one test: with nothing able to notify
        // the runner, the reading past zero must say HOW LONG AGO.
        let mut t = Timer::new();
        for _ in 0..3 {
            t.preset_up();
        }
        assert_eq!(t.preset_s(), 300);
        t.start_stop(0);
        let v = t.view(60);
        assert_eq!(v.display_s, 240);
        assert_eq!(v.display().as_str(), "4:00");
        assert!(!v.expired);
        let at_zero = t.view(300);
        assert!(at_zero.expired);
        assert_eq!(at_zero.display_s, 0);
        assert_eq!(at_zero.display().as_str(), "+0:00");
        let over = t.view(434);
        assert_eq!(over.display_s, 134);
        assert_eq!(over.display().as_str(), "+2:14");
        assert_eq!(over.state_word(), "TIME UP");
    }

    #[test]
    fn stop_banks_the_leg_and_resume_continues_it() {
        let mut t = Timer::new();
        t.start_stop(10);
        t.start_stop(40);
        assert!(!t.running());
        assert_eq!(t.elapsed_s(10_000), 30, "a stopped clock does not drift");
        t.start_stop(100);
        assert_eq!(t.elapsed_s(105), 35);
    }

    #[test]
    fn reset_is_refused_while_running_and_clears_once_stopped() {
        let mut t = Timer::new();
        t.start_stop(0);
        assert!(!t.reset(), "a brushed sleeve may not zero a live timing");
        assert_eq!(t.elapsed_s(50), 50);
        t.start_stop(50);
        assert!(t.reset());
        assert_eq!(t.elapsed_s(999), 0);
        assert!(
            !t.is_armed(),
            "a cleared instrument gives its page seat back"
        );
        assert!(!t.reset(), "nothing left to clear");
    }

    #[test]
    fn one_arming_raises_exactly_one_expiry_edge() {
        let mut t = Timer::new();
        t.preset_up();
        assert_eq!(t.preset_s(), 60);
        t.start_stop(0);
        let seq = t.view(60).expiry_seq;
        assert_ne!(seq, 0, "an expired countdown carries an edge");
        assert_eq!(t.view(90).expiry_seq, seq, "the same arming, the same edge");
        // Stopping and resuming across the expiry keeps the arming — the banner
        // must not fire a second time for one countdown.
        t.start_stop(90);
        assert_eq!(t.view(90).expiry_seq, seq);
        t.start_stop(200);
        assert_eq!(t.view(260).expiry_seq, seq);
    }

    #[test]
    fn a_re_arming_takes_a_new_edge() {
        let mut t = Timer::new();
        t.preset_up();
        t.start_stop(0);
        let first = t.view(60).expiry_seq;
        t.start_stop(60);
        assert!(t.reset());
        t.start_stop(100);
        let second = t.view(160).expiry_seq;
        assert_ne!(second, 0);
        assert_ne!(second, first, "a fresh arming owes a fresh banner");
    }

    #[test]
    fn an_unexpired_countdown_carries_no_edge() {
        let mut t = Timer::new();
        t.preset_up();
        t.start_stop(0);
        assert_eq!(t.view(59).expiry_seq, 0);
        // And a stopwatch never carries one, however long it runs.
        let mut s = Timer::new();
        s.start_stop(0);
        assert_eq!(s.view(100_000).expiry_seq, 0);
    }

    #[test]
    fn the_arm_counter_never_aliases_never_armed() {
        // 0 means "never armed"; a wrap must land on 1, or a 65536th arming
        // would look like a watch that had never timed anything.
        let mut t = Timer::new();
        t.preset_up();
        t.arm_seq = u16::MAX;
        t.start_stop(0);
        assert_eq!(t.arm_seq, 1);
        assert_ne!(t.view(60).expiry_seq, 0);
    }

    #[test]
    fn a_backwards_clock_saturates_instead_of_wrapping() {
        let mut t = Timer::new();
        t.start_stop(500);
        assert_eq!(t.elapsed_s(100), 0);
    }

    #[test]
    fn the_clock_formatter_switches_face_at_an_hour_and_clamps() {
        assert_eq!(format_clock(0).as_str(), "0:00");
        assert_eq!(format_clock(59).as_str(), "0:59");
        assert_eq!(format_clock(3_599).as_str(), "59:59");
        assert_eq!(format_clock(3_600).as_str(), "1:00:00");
        assert_eq!(format_clock(5_400).as_str(), "1:30:00");
        assert_eq!(format_clock(CLOCK_MAX_S).as_str(), "99:59:59");
        assert_eq!(
            format_clock(u32::MAX).as_str(),
            "99:59:59",
            "a runaway reading clamps rather than truncating into nonsense"
        );
    }

    #[test]
    fn presses_map_to_the_instrument_and_report_idempotence() {
        let mut t = Timer::new();
        assert_eq!(press(&mut t, TimerKey::Shorter, 0), TimerPress::Nothing);
        assert_eq!(press(&mut t, TimerKey::Longer, 0), TimerPress::Changed);
        assert_eq!(t.preset_s(), 60);
        assert_eq!(press(&mut t, TimerKey::Reset, 0), TimerPress::Nothing);
        assert_eq!(press(&mut t, TimerKey::StartStop, 0), TimerPress::Changed);
        assert!(t.running());
        assert_eq!(press(&mut t, TimerKey::Reset, 5), TimerPress::Nothing);
        assert_eq!(press(&mut t, TimerKey::StartStop, 5), TimerPress::Changed);
        assert_eq!(press(&mut t, TimerKey::Reset, 5), TimerPress::Changed);
        assert_eq!(press(&mut t, TimerKey::Exit, 5), TimerPress::Exit);
    }

    #[test]
    fn exit_leaves_the_instrument_running() {
        // The modal is a view of the timer, not its container: a runner who
        // exits to watch the run pages has not cancelled anything.
        let mut t = Timer::new();
        press(&mut t, TimerKey::StartStop, 0);
        assert_eq!(press(&mut t, TimerKey::Exit, 10), TimerPress::Exit);
        assert!(t.running());
        assert_eq!(t.elapsed_s(30), 30);
    }

    #[test]
    fn the_legend_names_the_exit_and_the_start_verb_it_is_about_to_produce() {
        let mut t = Timer::new();
        let rows = timer_rows(&t, 0);
        assert_eq!(rows[0].as_str(), "B1 START      B4 EXIT");
        assert_eq!(rows[0].len(), COLS, "the legend should fill the row");
        t.start_stop(0);
        let rows = timer_rows(&t, 0);
        assert_eq!(rows[0].as_str(), "B1 STOP       B4 EXIT");
        assert_eq!(rows[0].len(), COLS);
    }

    #[test]
    fn the_ladder_row_shows_only_while_the_ladder_is_live() {
        let mut t = Timer::new();
        let rows = timer_rows(&t, 0);
        assert_eq!(rows[TIMER_TOP_ROW + 3].as_str(), "B2 LONGER B3 SHORTER");
        // Armed: the ladder is refused, so naming its keys would be a lie — the
        // reset that IS live takes the row instead.
        t.preset_up();
        t.start_stop(0);
        t.start_stop(30);
        let rows = timer_rows(&t, 30);
        assert_eq!(rows[TIMER_TOP_ROW + 3].as_str(), "B5 RESET");
        // Running: neither is live, and no key is named.
        t.start_stop(30);
        let rows = timer_rows(&t, 40);
        assert!(rows[TIMER_TOP_ROW + 3].is_empty());
    }

    #[test]
    fn the_modal_reads_the_instrument_and_names_its_target() {
        let mut t = Timer::new();
        for _ in 0..3 {
            t.preset_up();
        }
        t.start_stop(0);
        let rows = timer_rows(&t, 100);
        assert_eq!(rows[1].as_str(), "TIMER");
        assert_eq!(rows[TIMER_TOP_ROW].as_str(), "3:20");
        assert_eq!(rows[TIMER_TOP_ROW + 1].as_str(), "RUNNING");
        assert_eq!(rows[TIMER_TOP_ROW + 2].as_str(), "SET 5:00");
        // A stopwatch has no target, so no SET row is written.
        let mut s = Timer::new();
        s.start_stop(0);
        let rows = timer_rows(&s, 100);
        assert_eq!(rows[1].as_str(), "STOPWATCH");
        assert!(rows[TIMER_TOP_ROW + 2].is_empty());
    }

    #[test]
    fn every_modal_row_fits_the_face_at_every_rung_and_state() {
        for idx in 0..PRESETS_S.len() {
            for elapsed in [0u32, 1, 59, 60, 3_599, 3_600, 100_000, u32::MAX / 2] {
                for running in [false, true] {
                    let mut t = Timer::new();
                    for _ in 0..idx {
                        t.preset_up();
                    }
                    t.start_stop(0);
                    if !running {
                        t.start_stop(elapsed);
                    }
                    for row in timer_rows(&t, elapsed).iter() {
                        assert!(row.len() <= COLS, "row too wide: {row:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn the_modal_timeout_tracks_the_settings_menus() {
        // Same rule, one number: both modals cover the home clock.
        assert_eq!(TIMER_MENU_TIMEOUT_S, crate::settings_menu::MENU_TIMEOUT_S);
    }
}
