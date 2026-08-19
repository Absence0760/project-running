//! Backyard-ultra mode — the bell-anchored last-person-standing format.
//!
//! A backyard ultra sends every runner off on the same loop (classically
//! 4.167 mi / 6.706 km) every hour **on the hour**. A runner must complete the
//! loop *and* be back in the corral before the next bell; whistles sound at 3,
//! 2 and 1 minutes to it. The event has no scheduled end — it runs until one
//! runner remains — and the stat that decides it is the **loop count**, not
//! pace, not total distance, not a finish time.
//!
//! Three things fall out of that, and each is a decision this module makes
//! rather than a number it computes (decisions § 372):
//!
//! - **The bell is wall-clock-anchored, never elapsed-anchored.** A runner who
//!   crawls in at 59:30 and starts loop 7 thirty seconds late gets the same
//!   bell as everyone else. So the countdown is derived from the *hour
//!   boundary* of the runner's local clock — [`BELL_INTERVAL_S`] minus the
//!   seconds already spent in the current hour — and never from the lap's
//!   start or the run's. Anchoring on elapsed time would drift a little every
//!   loop and be minutes wrong by loop 20, which in this format is the
//!   difference between a rest and an elimination.
//! - **It rides the recorder's existing lap, it does not count loops itself.**
//!   A loop boundary IS a lap close — the same `close_lap` that banks a split
//!   to flash and syncs to the phone — and in this mode the *bell* drives the
//!   auto-lap in place of the 1 km boundary. [`Backyard`] is told when the
//!   recorder closed one ([`Backyard::on_corral_return`] for the runner's own
//!   BTN5 press, [`Backyard::on_bell_lap`] for the backstop) and does no
//!   deciding of its own about when a loop ended.
//! - **At most one loop per bell window.** Two loops cannot fit in an hour, so
//!   a second press inside the same window still closes a lap (BTN5's meaning
//!   is not redefined) but adds no loop. At hour 30 a fat-fingered double
//!   press must not corrupt the one number the whole format is scored on.
//!
//! **What it refuses to answer.** It never declares a runner in or out. The
//! corral is the race director's, the timing mat is theirs, and a watch that
//! announced `DNF` at hour 30 off a missed button press would be lying about
//! the only thing that matters. [`BackyardView::loops`] is therefore "bells
//! this run has closed a loop on" — which, for a runner still in the race, is
//! their loop count, and for one who is out is simply the last number the
//! watch saw. It also refuses a return margin it cannot support: without a
//! learned loop length or a live pace the margin is [`None`], never a
//! confident wrong number (the same rule [`crate::cutoff_eta`] applies to a
//! stale fix).
//!
//! **The loop length is learned, not configured.** A five-button watch is a
//! poor place to enter 6706 metres, and events differ. The runner runs loop 1;
//! the mean of the loops closed so far is the loop from then on. Loop 1
//! therefore has no projected margin and says so.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator. There is
//! no web helper to port — the app models the *format*'s consequences
//! (`is_dnf`, the backyard personas) but has no live bell engine, so this is
//! watch-native firmware work (roadmap § Differentiation backlog).

/// Seconds between corral bells. The format's one fixed constant: every
/// backyard sends the loop off on the hour.
pub const BELL_INTERVAL_S: u32 = 3600;

/// The minutes before the bell the race director whistles at, longest first.
/// Announced as milestones — the *highest* level a fold has reached fires and
/// the ones it skipped are dropped, never burst (the [`crate::alerts`]
/// milestone rule), because a `3 MIN` banner read at 1:40 is worse than none.
pub const BELL_WARNING_MIN: [u8; 3] = [3, 2, 1];

/// A corral return the runner marked, and the run distance at it.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Return {
    uptime_s: u32,
    distance_m: f64,
}

/// What the Backyard page shows. Present exactly while the mode is armed —
/// an unarmed watch has no such page in its cycle at all.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BackyardView {
    /// Loops the bell has closed this run. The format's primary stat.
    pub loops: u16,
    /// Seconds to the next bell, or `None` while the local wall clock is
    /// unknown. The page's honesty gate: no timezone pushed, or no fix
    /// carrying the receiver's clock, and there is no hour boundary to count
    /// down to — the countdown would be against the wrong midnight, which on a
    /// half-hour-offset timezone is thirty minutes of a runner's rest.
    pub to_bell_s: Option<u32>,
    /// Whether the runner has marked a corral return since the last bell.
    /// False until they press, and false again the instant the bell rings —
    /// the state flips on the clock alone, with no event to miss.
    pub in_corral: bool,
    /// The loop's length, meaned over the loops closed so far. `None` on loop
    /// 1, when the watch has not yet been shown the loop.
    pub loop_distance_m: Option<f64>,
    /// Ground covered since the last loop closed.
    pub loop_progress_m: f64,
    /// Projected seconds to spare at the bell if the runner holds their
    /// current pace — negative means the projection misses it. `None` in the
    /// corral (there is nothing left to project), on an unlearned loop, and
    /// without a live pace.
    pub return_margin_s: Option<i32>,
    /// Monotonic counter, bumped once per whistle. The alert engine fires on
    /// the change and drops a blocked one rather than owing it.
    pub warning_seq: u16,
    /// The whistle [`warning_seq`](Self::warning_seq) last announced, in
    /// minutes; 0 before any.
    pub warning_min: u8,
}

/// How long after the bell a corral press can still be the runner walking in
/// from the loop the backstop banked — equivalently, the shortest time in which
/// a *new* loop could have been run, since those are the same question asked
/// from two sides.
///
/// Sized as the second: 6.706 km in fifteen minutes is 2:14/km, faster than the
/// 10 km world record, so no press this soon can be a loop nobody has counted
/// yet. The old five minutes was sized only as "a late walk-in", which left the
/// ten minutes after it counting a bell-banked loop a second time — the runner
/// crossing at bell+7 min and pressing as they always do added a loop they had
/// not run.
pub const BANK_CONSUME_WINDOW_S: u32 = 900;

/// How far into the window the clock must step back before it is a bell rather
/// than a clock.
///
/// Half a window. The fold runs at 1 Hz for as long as a run is live, so a real
/// rollover always presents as a drop of nearly [`BELL_INTERVAL_S`] and no two
/// bells can hide between two folds; anything smaller is the local-time
/// extrapolation being re-disciplined, which no runner should be eliminated by.
pub const BELL_ROLLOVER_MIN_DROP_S: u32 = BELL_INTERVAL_S / 2;

/// The mode's state machine. Armed from the idle settings menu, so a run
/// starts either wholly inside the mode or wholly outside it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Backyard {
    armed: bool,
    loops: u16,
    /// Run distance when the mode's bookkeeping started, so a mid-run arm
    /// measures its loops from where it was armed and not from the run's
    /// start.
    distance_base_m: f64,
    /// Run distance at the most recent loop close — the anchor both the
    /// learned loop length and the current loop's progress measure from.
    distance_at_close_m: f64,
    last_return: Option<Return>,
    /// Seconds into the bell window at the last fold. A new window is
    /// detected by this going backwards by most of a window, which needs no
    /// date and cannot be confused by midnight — a backyard runs for days.
    since_bell_s: u32,
    /// Whether any local clock has ever been folded in.
    clock_seen: bool,
    /// A loop has already closed inside the current window.
    closed_this_window: bool,
    /// The bell has already banked a loop the runner is still walking in from.
    ///
    /// `on_clock` clears `closed_this_window` FOR THE NEW WINDOW before the
    /// recorder calls `on_bell_lap`, so the backstop's loop left the new window
    /// looking un-closed. A runner who crossed a few seconds after the bell and
    /// pressed BTN5 as they always do then counted the SAME physical loop
    /// twice, and the learned loop length halved with it — which then poisons
    /// `return_margin_s` for every later loop.
    ///
    /// Setting `closed_this_window` in `on_bell_lap` instead would be wrong: it
    /// would read as "the runner closed this window" at the next rollover and
    /// disarm the backstop for the window they are actually out on.
    bell_banked_pending: bool,
    /// A bank has already been walked in from in THIS window, so a repeat press
    /// inside the consume window is a fat finger, not a second loop.
    ///
    /// `closed_this_window` cannot serve here: the consumed press does not close
    /// the current window (the runner is about to run it, and that loop's own
    /// return must still count), so the ordinary double-press guard is not armed
    /// during exactly the seconds a double press is most likely.
    bank_consumed_this_window: bool,
    warned_min: u8,
    warning_seq: u16,
}

impl Default for Backyard {
    fn default() -> Self {
        Self::new()
    }
}

impl Backyard {
    pub const fn new() -> Self {
        Self {
            armed: false,
            loops: 0,
            distance_base_m: 0.0,
            distance_at_close_m: 0.0,
            last_return: None,
            since_bell_s: 0,
            clock_seen: false,
            closed_this_window: false,
            bell_banked_pending: false,
            bank_consumed_this_window: false,
            warned_min: 0,
            warning_seq: 0,
        }
    }

    pub fn armed(&self) -> bool {
        self.armed
    }

    /// Arm or disarm the mode, anchoring the bookkeeping at `distance_m`.
    /// Re-arming an already-armed mode is a no-op so a repeated menu press (or
    /// a boot-time re-seed of the persisted flag) cannot wipe a race in
    /// progress.
    pub fn set_armed(&mut self, armed: bool, distance_m: f64) {
        if armed == self.armed {
            return;
        }
        let seq = self.warning_seq;
        *self = Self::new();
        self.armed = armed;
        // The alert engine keys on a CHANGE, so the counter has to survive the
        // reset or a disarm/re-arm could land back on the value it last fired.
        self.warning_seq = seq;
        if armed {
            self.distance_base_m = distance_m;
            self.distance_at_close_m = distance_m;
        }
    }

    /// Clear the per-run state for a fresh run, keeping the armed flag. The
    /// loop count, the learned loop and the corral state all belong to one
    /// race.
    pub fn on_run_start(&mut self) {
        let armed = self.armed;
        let seq = self.warning_seq;
        *self = Self::new();
        self.armed = armed;
        self.warning_seq = seq;
    }

    /// Fold the local wall clock forward. `local_tod_s` is seconds since the
    /// runner's local midnight — the receiver's UTC clock shifted by the pushed
    /// timezone offset.
    ///
    /// Returns `true` when a bell has just passed with no loop closed inside
    /// the window it ended — the caller takes a lap, which is the mode's
    /// per-loop auto-reset. The bell is the *backstop*: a runner who marked
    /// their return already closed that loop themselves.
    ///
    /// Only the modulus of `local_tod_s` matters, so it needs no date and
    /// survives midnight, a leap second, and a multi-day race. A window is
    /// recognised by that modulus dropping by at least
    /// [`BELL_ROLLOVER_MIN_DROP_S`], which is sound because the recorder folds
    /// this at 1 Hz for as long as a run is live (through both pause kinds) —
    /// no window can pass unobserved, so a real rollover always drops by nearly
    /// a whole window.
    ///
    /// The size of the drop is load-bearing, not decoration. `local_tod_s` is
    /// an extrapolation off the last receiver clock, so it retreats a second
    /// whenever the oscillator is re-disciplined — about seven times over a
    /// 100-hour backyard at 20 ppm. Reading *any* backward step as a bell rang
    /// a phantom one: it cleared `closed_this_window`, so the return the runner
    /// had already marked was forgotten and the real bell banked the same
    /// physical loop a second time, and it re-armed the whistles.
    pub fn on_clock(&mut self, local_tod_s: u32) -> bool {
        if !self.armed {
            return false;
        }
        let since = local_tod_s % BELL_INTERVAL_S;
        let mut bell_lap_due = false;
        if !self.clock_seen {
            self.clock_seen = true;
            self.since_bell_s = since;
        } else if self.since_bell_s.saturating_sub(since) >= BELL_ROLLOVER_MIN_DROP_S {
            // The window rolled over: the bell rang between the last fold and
            // this one.
            bell_lap_due = !self.closed_this_window;
            self.closed_this_window = false;
            // A bank that was never walked in from must not swallow a return in
            // the window after next.
            self.bell_banked_pending = false;
            self.bank_consumed_this_window = false;
            self.warned_min = 0;
            self.since_bell_s = since;
        } else {
            // Held monotonic inside the window: a clock that stepped back a
            // second is not a countdown that gained one.
            self.since_bell_s = self.since_bell_s.max(since);
        }

        let to_bell = BELL_INTERVAL_S - self.since_bell_s;
        // Tightest level first (the array reads longest-first for the reader),
        // so a fold that has passed several announces the one it reached.
        let due = BELL_WARNING_MIN
            .iter()
            .copied()
            .rev()
            .find(|m| to_bell <= u32::from(*m) * 60)
            .unwrap_or(0);
        if due > 0 && (self.warned_min == 0 || due < self.warned_min) {
            self.warned_min = due;
            self.warning_seq = self.warning_seq.wrapping_add(1);
        }
        bell_lap_due
    }

    /// The runner marked a corral return — their own BTN5 lap press, which has
    /// already closed the recorder's lap. Counts a loop only when none has
    /// closed in this window yet.
    pub fn on_corral_return(&mut self, uptime_s: u32, distance_m: f64) {
        if !self.armed {
            return;
        }
        // A bank is only "walked in from" for the few minutes AFTER the bell.
        //
        // Without the time bound the consumption was open for the whole hour, so
        // one press the watch never saw poisoned the rest of the race: the bell
        // banks loop N, the runner runs loop N+1 in full and presses at +55 min,
        // and that press — their own, for a loop the bell never counted — was
        // swallowed as "walking in from the bank". `closed_this_window` then
        // stayed false, the next bell banked again and re-armed the flag, and
        // the latch sustained itself. A loop cannot be run inside
        // BANK_CONSUME_WINDOW_S, so a press this soon can only be the previous
        // loop arriving late.
        let within_consume_window = self.since_bell_s <= BANK_CONSUME_WINDOW_S;
        if self.bank_consumed_this_window && within_consume_window {
            // Repeat press seconds after the one that consumed the bank.
            return;
        }
        if self.bell_banked_pending && within_consume_window {
            // This press is the runner walking in from the loop the bell
            // already banked. Record the return, but do NOT count it again —
            // and leave `closed_this_window` alone, because the loop they are
            // now starting is still open and its own return must still count.
            self.bell_banked_pending = false;
            self.bank_consumed_this_window = true;
            self.last_return = Some(Return {
                uptime_s,
                distance_m,
            });
            return;
        }
        self.close_loop(distance_m);
        self.last_return = Some(Return {
            uptime_s,
            distance_m,
        });
        self.closed_this_window = true;
    }

    /// The bell closed the loop because the runner did not. Same loop
    /// accounting, but it marks no return: the watch was not told the runner
    /// is back, and it will not assume it.
    pub fn on_bell_lap(&mut self, distance_m: f64) {
        if !self.armed {
            return;
        }
        self.close_loop(distance_m);
        self.bell_banked_pending = true;
    }

    fn close_loop(&mut self, distance_m: f64) {
        if self.closed_this_window {
            // Two loops cannot fit inside one hour, so this is a repeat press,
            // not a second loop. The lap still closed in the recorder; only
            // the scored count is protected.
            return;
        }
        self.loops = self.loops.saturating_add(1);
        self.distance_at_close_m = distance_m;
    }

    /// The page's view. `distance_m` is the run total, `pace_s_per_km` the
    /// recorder's live pace (`None` without one).
    pub fn view(&self, distance_m: f64, pace_s_per_km: Option<u32>, uptime_s: u32) -> BackyardView {
        let to_bell_s = self.clock_seen.then(|| BELL_INTERVAL_S - self.since_bell_s);
        let in_corral = match (self.last_return, self.clock_seen) {
            // Returned since the bell that opened the current window. Derived
            // from the clock, so the bell puts the runner back on the loop
            // without an event of its own.
            (Some(r), true) => uptime_s.saturating_sub(r.uptime_s) <= self.since_bell_s,
            _ => false,
        };
        let loop_distance_m = (self.loops > 0)
            .then(|| (self.distance_at_close_m - self.distance_base_m) / f64::from(self.loops))
            .filter(|m| m.is_finite() && *m > 0.0);
        let loop_progress_m = (distance_m - self.distance_at_close_m).max(0.0);
        BackyardView {
            loops: self.loops,
            to_bell_s,
            in_corral,
            loop_distance_m,
            loop_progress_m,
            return_margin_s: self.margin(
                to_bell_s,
                in_corral,
                loop_distance_m,
                loop_progress_m,
                pace_s_per_km,
            ),
            warning_seq: self.warning_seq,
            warning_min: self.warned_min,
        }
    }

    /// Projected slack at the bell. Every input it cannot supply collapses to
    /// `None` rather than to a zero a runner would read as "exactly on time".
    fn margin(
        &self,
        to_bell_s: Option<u32>,
        in_corral: bool,
        loop_distance_m: Option<f64>,
        loop_progress_m: f64,
        pace_s_per_km: Option<u32>,
    ) -> Option<i32> {
        if in_corral {
            return None;
        }
        let to_bell = to_bell_s?;
        let loop_m = loop_distance_m?;
        let pace = pace_s_per_km.filter(|p| *p > 0)?;
        let remaining_m = (loop_m - loop_progress_m).max(0.0);
        let projected_s = remaining_m / 1000.0 * f64::from(pace);
        if !projected_s.is_finite() {
            return None;
        }
        Some(
            (f64::from(to_bell) - projected_s).clamp(f64::from(i32::MIN), f64::from(i32::MAX))
                as i32,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const H: u32 = BELL_INTERVAL_S;

    fn armed() -> Backyard {
        let mut b = Backyard::new();
        b.set_armed(true, 0.0);
        b
    }

    /// Fold across a bell the way the recorder does — at 1 Hz, so the window's
    /// modulus drops by nearly a whole window rather than by a handful of
    /// seconds. `into_s` is seconds into the new window; the return is the
    /// backstop verdict for the window that just ended.
    fn roll(b: &mut Backyard, hour: u32, into_s: u32) -> bool {
        b.on_clock(hour * H - 1);
        b.on_clock(hour * H + into_s)
    }

    #[test]
    fn an_unarmed_mode_ignores_every_feed() {
        let mut b = Backyard::new();
        assert!(!b.on_clock(9 * H + 5));
        b.on_corral_return(10, 6_700.0);
        b.on_bell_lap(6_700.0);
        assert_eq!(b.view(6_700.0, Some(300), 10).loops, 0);
        assert_eq!(b.view(6_700.0, Some(300), 10).to_bell_s, None);
    }

    #[test]
    fn the_countdown_runs_to_the_hour_not_from_the_run() {
        // The whole point of the wall-clock anchor: a runner who started the
        // watch at 09:12:30 still gets the 10:00 bell, not one an hour after
        // they pressed start.
        let mut b = armed();
        b.on_clock(9 * H + 12 * 60 + 30);
        assert_eq!(b.view(0.0, None, 0).to_bell_s, Some(47 * 60 + 30));
        b.on_clock(9 * H + 59 * 60);
        assert_eq!(b.view(0.0, None, 100).to_bell_s, Some(60));
    }

    #[test]
    fn a_late_start_on_the_next_loop_gets_the_same_bell() {
        // Loop 7 begun 40 s late is still 40 s shorter, not a fresh hour.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_clock(9 * H + 40);
        assert_eq!(b.view(0.0, None, 40).to_bell_s, Some(H - 40));
    }

    #[test]
    fn an_unknown_clock_withholds_the_countdown_rather_than_guessing() {
        let b = armed();
        let v = b.view(1_000.0, Some(300), 50);
        assert_eq!(v.to_bell_s, None);
        assert_eq!(v.return_margin_s, None);
        assert!(!v.in_corral);
    }

    #[test]
    fn the_bell_closes_a_loop_the_runner_did_not() {
        let mut b = armed();
        assert!(!b.on_clock(9 * H + 30 * 60), "the first fold has no bell");
        assert!(!b.on_clock(9 * H + 59 * 60));
        assert!(
            b.on_clock(10 * H + 1),
            "the window rolled over with nothing closed in it"
        );
        b.on_bell_lap(6_706.0);
        assert_eq!(b.view(6_706.0, None, 1_802).loops, 1);
    }

    #[test]
    fn a_marked_return_stands_the_bells_lap_down() {
        // The bell is the backstop, not a second close: a runner who pressed
        // at the corral must not be given two loops for one hour.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_clock(9 * H + 52 * 60);
        b.on_corral_return(3_120, 6_700.0);
        assert!(
            !b.on_clock(10 * H + 1),
            "a loop already closed in that window"
        );
        assert_eq!(b.view(6_700.0, None, 3_601).loops, 1);
    }

    #[test]
    fn a_second_press_in_one_window_is_not_a_second_loop() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(10, 6_700.0);
        b.on_corral_return(12, 6_705.0);
        let v = b.view(6_705.0, None, 12);
        assert_eq!(v.loops, 1, "two loops cannot fit inside one hour");
        // ...and the anchor stays at the first close, so the second press does
        // not silently lengthen the learned loop either.
        assert_eq!(v.loop_distance_m, Some(6_700.0));
    }

    #[test]
    fn a_press_just_after_the_bell_is_the_same_loop_not_a_second() {
        // The runner is still out when the bell sounds, so the backstop banks
        // the loop; they cross 29 s later and press BTN5 as they always do.
        // That is ONE physical loop.
        //
        // on_clock clears closed_this_window FOR THE NEW WINDOW before the
        // recorder calls on_bell_lap, so the banked loop used to leave the new
        // window looking un-closed and the press counted it again — doubling
        // the one number the format is scored on, and halving the learned loop
        // length with it, which then poisons return_margin_s for every later
        // loop.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        assert!(roll(&mut b, 10, 1), "runner still out: the backstop is due");
        b.on_bell_lap(6_706.0);
        assert_eq!(b.view(6_706.0, None, 3_600).loops, 1);

        b.on_corral_return(3_629, 6_712.0);
        let v = b.view(6_712.0, None, 3_629);
        assert_eq!(v.loops, 1, "the bell already banked this loop");
        assert_eq!(
            v.loop_distance_m,
            Some(6_706.0),
            "and the learned loop is not halved"
        );
        assert!(v.in_corral, "the return still registers");
    }

    #[test]
    fn a_one_second_clock_retreat_is_not_a_bell() {
        // local_tod_s is extrapolated off the last receiver clock, so it steps
        // back a second whenever the oscillator is re-disciplined — about seven
        // times over a 100-hour backyard at 20 ppm. Reading that as a bell
        // forgot the return the runner had already marked, and the real bell
        // then banked the same physical loop a second time.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_706.0);
        assert_eq!(b.view(6_706.0, None, 100).loops, 1);

        let before = b.view(6_706.0, None, 100).to_bell_s;
        b.on_clock(9 * H + 1_800);
        b.on_clock(9 * H + 1_799);
        assert_eq!(
            b.view(6_706.0, None, 1_799).loops,
            1,
            "a retreating clock rang a phantom bell"
        );
        assert!(
            b.view(6_706.0, None, 1_799).to_bell_s < before,
            "and the countdown must not gain a second back"
        );

        // The real bell now stands down, because the runner did close the
        // window — which the phantom had erased.
        assert!(
            !roll(&mut b, 10, 1),
            "the marked return survived the retreat"
        );
        assert_eq!(b.view(6_706.0, None, 3_601).loops, 1);
    }

    #[test]
    fn a_late_walk_in_from_a_banked_loop_is_never_a_second_loop() {
        // bell-then-press, past the old five-minute bound. The runner crosses
        // seven minutes after the bell that banked their loop and presses as
        // they always do. They cannot have run a 6.7 km loop in seven minutes,
        // so this is the banked loop arriving late — the guard has to be sized
        // as "the fastest a loop could be run", not as "how long a walk-in
        // takes".
        let mut b = armed();
        b.on_clock(9 * H + 5);
        assert!(roll(&mut b, 10, 1));
        b.on_bell_lap(6_706.0);
        assert_eq!(b.view(6_706.0, None, 3_600).loops, 1);

        b.on_clock(10 * H + 7 * 60);
        b.on_corral_return(4_020, 6_760.0);
        let v = b.view(6_760.0, None, 4_020);
        assert_eq!(v.loops, 1, "a loop nobody ran was counted");
        assert_eq!(
            v.loop_distance_m,
            Some(6_706.0),
            "and the learned loop is not halved"
        );
        assert!(v.in_corral, "the return still registers");

        // ...while the loop they go on to run still counts on its own return.
        b.on_clock(10 * H + 55 * 60);
        b.on_corral_return(6_900, 13_418.0);
        assert_eq!(b.view(13_418.0, None, 6_900).loops, 2);
    }

    #[test]
    fn the_loop_after_a_banked_one_still_counts_on_its_own_return() {
        // The consumed bank must not stand in for the NEXT loop's close, or a
        // runner who takes the bell backstop once would stop being counted.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        assert!(roll(&mut b, 10, 1));
        b.on_bell_lap(6_706.0);
        b.on_corral_return(3_629, 6_712.0); // walks in from the banked loop
        assert_eq!(b.view(6_712.0, None, 3_629).loops, 1);

        // ...then runs loop 2 and returns inside its own window.
        b.on_clock(10 * H + 55 * 60);
        b.on_corral_return(6_900, 13_418.0);
        assert_eq!(b.view(13_418.0, None, 6_900).loops, 2);

        // The runner closed that window themselves, so the backstop stands down.
        assert!(!roll(&mut b, 11, 1), "no backstop after a real return");
    }

    #[test]
    fn a_bank_nobody_walked_in_from_does_not_swallow_a_later_return() {
        // The pending bank is cleared at the next rollover: if the runner never
        // pressed for the banked loop, a return two windows later is their own
        // and must count.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        assert!(roll(&mut b, 10, 1));
        b.on_bell_lap(6_706.0);
        assert_eq!(b.view(6_706.0, None, 3_600).loops, 1);

        // No press at all this window; the bell banks again.
        b.on_clock(10 * H + 30 * 60);
        assert!(roll(&mut b, 11, 1));
        b.on_bell_lap(13_412.0);
        assert_eq!(b.view(13_412.0, None, 7_200).loops, 2);

        // Now they press, in the third window.
        b.on_corral_return(7_230, 13_420.0);
        assert_eq!(
            b.view(13_420.0, None, 7_230).loops,
            2,
            "the second bank is the loop they walked in from"
        );
    }

    #[test]
    fn a_missed_press_does_not_swallow_the_next_loops_own_return() {
        // The hole the unbounded bank left. Loop 1's press never registers, so
        // the bell banks it. The runner then runs loop 2 IN FULL and presses at
        // the end of it — their own press, for a loop the bell never counted.
        // With no time bound that press was consumed as "walking in from the
        // bank", closed_this_window stayed false, the next bell banked again and
        // re-armed the flag, and the latch sustained itself: the runner's presses
        // stopped counting for the rest of the race.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_clock(9 * H + 30 * 60);
        assert!(roll(&mut b, 10, 1), "no press in window 1: backstop is due");
        b.on_bell_lap(6_706.0);
        assert_eq!(b.view(6_706.0, None, 3_600).loops, 1);

        // Loop 2, run in full, pressed 55 minutes after the bell.
        b.on_clock(10 * H + 55 * 60);
        b.on_corral_return(6_900, 13_412.0);
        assert_eq!(
            b.view(13_412.0, None, 6_900).loops,
            2,
            "a press an hour after the bell is a new loop, not the banked one"
        );

        // ...and because it closed the window, the backstop stands down.
        assert!(
            !roll(&mut b, 11, 1),
            "the runner closed window 2 themselves"
        );
    }

    #[test]
    fn a_double_press_right_after_consuming_a_bank_is_not_a_loop() {
        // The module promises "a fat-fingered double press must not corrupt the
        // one number the whole format is scored on". The consumed press does not
        // close the current window — the runner is about to run it — so the
        // ordinary closed_this_window guard is not armed during exactly the
        // seconds a double press is most likely.
        let mut b = armed();
        b.on_clock(9 * H + 5);
        assert!(roll(&mut b, 10, 1));
        b.on_bell_lap(6_706.0);
        b.on_corral_return(3_629, 6_712.0); // walks in from the bank
        assert_eq!(b.view(6_712.0, None, 3_629).loops, 1);

        b.on_clock(10 * H + 40);
        b.on_corral_return(3_640, 6_713.0); // fat finger, 11 s later
        let v = b.view(6_713.0, None, 3_640);
        assert_eq!(v.loops, 1, "a repeat press is not a second loop");
        assert_eq!(
            v.loop_distance_m,
            Some(6_706.0),
            "and the learned loop is not halved"
        );

        // The loop they are now running still counts on its own return.
        b.on_clock(10 * H + 55 * 60);
        b.on_corral_return(6_900, 13_418.0);
        assert_eq!(b.view(13_418.0, None, 6_900).loops, 2);
    }

    #[test]
    fn the_corral_state_flips_on_the_bell_with_no_event() {
        let mut b = armed();
        b.on_clock(9 * H + 52 * 60);
        b.on_corral_return(3_120, 6_700.0);
        b.on_clock(9 * H + 59 * 60);
        assert!(b.view(6_700.0, None, 3_540).in_corral, "still resting");
        // The bell rings: the next loop has been sent off, so the runner is on
        // it whether or not anything told the watch.
        b.on_clock(10 * H + 5);
        assert!(!b.view(6_700.0, None, 3_600).in_corral);
    }

    #[test]
    fn a_runner_who_never_marks_a_return_is_never_in_the_corral() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_clock(9 * H + 30 * 60);
        assert!(!b.view(3_000.0, Some(300), 1_800).in_corral);
    }

    #[test]
    fn the_loop_length_is_learned_from_the_runners_own_loops() {
        let mut b = armed();
        b.on_clock(9 * H + 51 * 60);
        assert_eq!(
            b.view(3_000.0, Some(300), 100).loop_distance_m,
            None,
            "loop 1 has nothing to learn from"
        );
        b.on_corral_return(3_100, 6_700.0);
        assert_eq!(b.view(6_700.0, None, 3_100).loop_distance_m, Some(6_700.0));
        roll(&mut b, 10, 1);
        b.on_clock(10 * H + 50 * 60);
        b.on_corral_return(6_800, 13_420.0);
        // The mean over both loops, so one long GPS loop does not become the
        // course.
        assert_eq!(b.view(13_420.0, None, 6_800).loop_distance_m, Some(6_710.0));
    }

    #[test]
    fn a_mid_run_arm_measures_from_where_it_was_armed() {
        let mut b = Backyard::new();
        b.set_armed(true, 5_000.0);
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 11_700.0);
        assert_eq!(
            b.view(11_700.0, None, 100).loop_distance_m,
            Some(6_700.0),
            "the 5 km run before arming is not part of the loop"
        );
    }

    #[test]
    fn the_margin_projects_the_rest_of_the_loop_at_the_current_pace() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_000.0);
        // Second loop: 30 min in, 3 km covered of the learned 6 km, 6:00/km.
        b.on_clock(10 * H + 30 * 60);
        let v = b.view(9_000.0, Some(360), 5_500);
        assert_eq!(v.loop_progress_m, 3_000.0);
        // 3 km left at 360 s/km = 1080 s; 1800 s to the bell.
        assert_eq!(v.return_margin_s, Some(720));
    }

    #[test]
    fn a_projection_that_misses_the_bell_reports_a_negative_margin() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_000.0);
        b.on_clock(10 * H + 55 * 60);
        // 3 km still to run with five minutes left.
        let v = b.view(9_000.0, Some(360), 7_000);
        assert_eq!(v.return_margin_s, Some(300 - 1_080));
    }

    #[test]
    fn the_margin_withholds_rather_than_guessing_on_a_missing_input() {
        let mut b = armed();
        b.on_clock(9 * H + 30 * 60);
        // Loop 1: nothing learned yet.
        assert_eq!(b.view(3_000.0, Some(300), 1_800).return_margin_s, None);
        b.on_corral_return(1_900, 6_000.0);
        b.on_clock(10 * H + 5);
        // No live pace — a stopped or signal-less runner gets no projection.
        assert_eq!(b.view(6_000.0, None, 3_700).return_margin_s, None);
        assert_eq!(b.view(6_000.0, Some(0), 3_700).return_margin_s, None);
    }

    #[test]
    fn the_corral_has_no_margin_because_there_is_nothing_left_to_project() {
        let mut b = armed();
        b.on_clock(9 * H + 50 * 60);
        b.on_corral_return(3_000, 6_700.0);
        b.on_clock(9 * H + 51 * 60);
        let v = b.view(6_700.0, Some(300), 3_060);
        assert!(v.in_corral);
        assert_eq!(v.return_margin_s, None);
        // The rest available is the countdown itself, which is the hero.
        assert_eq!(v.to_bell_s, Some(9 * 60));
    }

    #[test]
    fn a_loop_run_long_never_reports_a_negative_remaining() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_000.0);
        b.on_clock(10 * H + 30 * 60);
        // Already 7 km into a 6 km loop — the remaining distance floors at 0,
        // so the margin is the whole countdown rather than a bonus.
        let v = b.view(13_000.0, Some(360), 5_500);
        assert_eq!(v.return_margin_s, Some(1_800));
    }

    #[test]
    fn the_whistles_fire_once_each_at_three_two_and_one_minutes() {
        let mut b = armed();
        b.on_clock(9 * H + 55 * 60);
        assert_eq!(b.view(0.0, None, 0).warning_min, 0);
        let mut fired = heapless::Vec::<(u8, u16), 8>::new();
        let mut last_seq = b.view(0.0, None, 0).warning_seq;
        for s in (56 * 60)..=(59 * 60 + 59) {
            b.on_clock(9 * H + s);
            let v = b.view(0.0, None, s);
            if v.warning_seq != last_seq {
                last_seq = v.warning_seq;
                let _ = fired.push((v.warning_min, v.warning_seq));
            }
        }
        assert_eq!(fired.len(), 3, "one whistle per level: {fired:?}");
        assert_eq!(fired[0].0, 3);
        assert_eq!(fired[1].0, 2);
        assert_eq!(fired[2].0, 1);
    }

    #[test]
    fn a_coarse_fold_announces_the_level_it_reached_and_skips_the_rest() {
        // Expedition mode folds the clock a minute at a time; the milestone
        // rule is to announce the highest level reached rather than burst
        // three stale banners.
        let mut b = armed();
        b.on_clock(9 * H + 55 * 60);
        let before = b.view(0.0, None, 0).warning_seq;
        b.on_clock(9 * H + 59 * 60 + 30);
        let v = b.view(0.0, None, 270);
        assert_eq!(v.warning_min, 1);
        assert_eq!(v.warning_seq, before.wrapping_add(1), "one fire, not three");
    }

    #[test]
    fn the_whistles_re_arm_for_the_next_bell() {
        let mut b = armed();
        b.on_clock(9 * H + 59 * 60);
        let after_first = b.view(0.0, None, 0).warning_seq;
        assert_eq!(b.view(0.0, None, 0).warning_min, 1);
        b.on_clock(10 * H + 5);
        assert_eq!(b.view(0.0, None, 65).warning_min, 0, "a new window");
        b.on_clock(10 * H + 58 * 60);
        let v = b.view(0.0, None, 3_540);
        assert_eq!(v.warning_min, 2);
        assert_ne!(v.warning_seq, after_first);
    }

    #[test]
    fn a_disarm_and_re_arm_cannot_land_on_the_sequence_it_last_fired() {
        // The alert engine keys on the counter CHANGING; a reset to zero after
        // a fire at zero would silently swallow the next whistle.
        let mut b = armed();
        b.on_clock(9 * H + 59 * 60);
        let seq = b.view(0.0, None, 0).warning_seq;
        b.set_armed(false, 0.0);
        b.set_armed(true, 0.0);
        assert_eq!(b.view(0.0, None, 0).warning_seq, seq);
        b.on_run_start();
        assert_eq!(b.view(0.0, None, 0).warning_seq, seq);
    }

    #[test]
    fn a_run_start_clears_the_race_but_keeps_the_mode() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_700.0);
        assert_eq!(b.view(6_700.0, None, 100).loops, 1);
        b.on_run_start();
        assert!(b.armed());
        let v = b.view(0.0, None, 100);
        assert_eq!(v.loops, 0);
        assert_eq!(v.loop_distance_m, None);
        assert_eq!(v.to_bell_s, None, "the clock re-seeds from the next fold");
    }

    #[test]
    fn re_arming_an_armed_mode_does_not_wipe_a_race_in_progress() {
        let mut b = armed();
        b.on_clock(9 * H + 5);
        b.on_corral_return(100, 6_700.0);
        b.set_armed(true, 12_000.0);
        assert_eq!(b.view(6_700.0, None, 100).loops, 1);
    }

    #[test]
    fn the_bell_window_survives_midnight() {
        // A backyard runs for days. The window is a modulus of the local
        // clock, so the 23:00 → 00:00 roll is the same roll as any other.
        let mut b = armed();
        b.on_clock(23 * H + 59 * 60);
        assert_eq!(b.view(0.0, None, 0).to_bell_s, Some(60));
        assert!(b.on_clock(30), "midnight is a bell like any other");
        assert_eq!(b.view(0.0, None, 90).to_bell_s, Some(H - 30));
    }

    #[test]
    fn a_timezone_with_a_half_hour_offset_still_counts_to_its_own_hour() {
        // The reason the countdown needs the pushed offset at all: in a
        // +05:30 zone the local hour boundary is thirty minutes off UTC's, and
        // a runner told they had forty minutes when they had ten would lose
        // the race to a rounding assumption.
        let mut b = armed();
        b.on_clock(9 * H + 30 * 60);
        assert_eq!(b.view(0.0, None, 0).to_bell_s, Some(30 * 60));
    }
}
