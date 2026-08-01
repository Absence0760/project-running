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
//!
//! # Surviving a power cycle
//!
//! `now_s` is *uptime*, and uptime restarts at zero. So the instrument cannot be
//! persisted as "42 seconds remaining": on the way back there is no way to tell
//! whether ten seconds or ten hours went past, and a reading that resumed as
//! though nothing had happened would be the one thing this module refuses to do.
//! [`Timer::to_record`] / [`Timer::from_record`] therefore split the instrument
//! by what each half can honestly reconstruct:
//!
//! - **A stopped reading needs no anchor at all.** It does not advance, so the
//!   banked seconds *are* the reading, before and after the reboot, exactly.
//! - **A running leg is anchored on the wall clock, never on uptime.** The
//!   record carries the UTC stamp ([`wall_stamp`], off the GPS receiver's date +
//!   time-of-day) the save happened at; the elapsed across the gap is then
//!   `wall_now - wall_then`, which is a measurement rather than a guess. The
//!   same wall-clock-not-elapsed anchor § 372's corral bell rests on.
//! - **When the gap genuinely cannot be known** — no fix at save, no fix on the
//!   way back, or a clock that ran backwards — the instrument comes back
//!   **stopped and marked** [`Timer::gap_unknown`] rather than resuming a lie.
//!   A marked reading reports *elapsed*, never remaining, prefixed `>` because
//!   it is a floor, and its state word says `GAP UNKNOWN`: § 373 withholds a nap
//!   budget it cannot compute and § 376 refuses a tendency with no altitude
//!   reference, and an unknowable reboot gap is the same class of answer. The
//!   mark survives its own re-persist, so a second reboot with a good fix cannot
//!   launder a floor into an exact reading, and it clears only on [`Timer::reset`]
//!   — a fresh arming, which is the one thing that genuinely has no gap.
//!
//! Nothing here writes on the tick. The record changes only when the instrument
//! does — armed, stopped, resumed, cleared — which is a handful of flash erases
//! per race against a page rated ~10,000.

use core::fmt::Write;

use crate::daylight::{day_of_year, Date};
use crate::face::{Row, ROWS};
use crate::run_store::crc32;

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

/// First year [`wall_stamp`] can express. Chosen, not arbitrary: a u-blox
/// receiver mid-cold-start emits a garbage year, and a stamp is worth nothing
/// unless an implausible one is refused outright rather than folded into a gap.
const WALL_EPOCH_YEAR: u16 = 2000;

/// Last year a u32 second count from [`WALL_EPOCH_YEAR`] can hold.
const WALL_MAX_YEAR: u16 = 2130;

/// Leap days in the years strictly before `year`.
fn leap_days_before(year: u16) -> u32 {
    let y = u32::from(year) - 1;
    y / 4 - y / 100 + y / 400
}

/// The absolute UTC instant a countdown is anchored to across a power cycle:
/// seconds since 2000-01-01T00:00:00Z, from a GPS fix's `date` + `time_of_day`.
///
/// `None` for a year the receiver cannot plausibly mean — a stamp that is
/// wrong is worse than no stamp, because the whole point of the anchor is that
/// the gap it measures is a measurement.
///
/// Deliberately absolute rather than a time-of-day: a nap started at 23:30 and
/// a reboot of unknown length both cross midnight, and a time-of-day alone
/// cannot tell ten minutes from twenty-four hours and ten minutes.
pub fn wall_stamp(date: Date, tod_utc_s: u32) -> Option<u32> {
    if !(WALL_EPOCH_YEAR..=WALL_MAX_YEAR).contains(&date.year) {
        return None;
    }
    let years = u32::from(date.year - WALL_EPOCH_YEAR);
    let leaps = leap_days_before(date.year) - leap_days_before(WALL_EPOCH_YEAR);
    let days = years * 365 + leaps + u32::from(day_of_year(date).saturating_sub(1));
    Some(days * 86_400 + tod_utc_s % 86_400)
}

/// Length of the persisted timer record (`TMR1`). A multiple of the NVMC 4-byte
/// write word, so it commits in one write.
pub const TIMER_RECORD_LEN: usize = 20;

/// Version of the `TMR1` wire format. Bumped only if the field layout after the
/// magic changes; an unrecognised version reads as "no saved timer".
pub const TMR1_VERSION: u8 = 1;

const TMR1_MAGIC: [u8; 4] = *b"TMR1";

const _: () = assert!(TIMER_RECORD_LEN.is_multiple_of(4));

/// The instrument was running when the record was written, so its reading needs
/// the reboot gap before it means anything.
const TMR1_FLAG_RUNNING: u8 = 0b0000_0001;
/// The record's `wall_s` is a real [`wall_stamp`] rather than a placeholder.
const TMR1_FLAG_WALL_ANCHOR: u8 = 0b0000_0010;
/// The reading was ALREADY a floor when it was written — see
/// [`Timer::gap_unknown`]. Persisted so a second reboot that happens to have a
/// good fix cannot present an inherited floor as an exact reading.
const TMR1_FLAG_GAP_UNKNOWN: u8 = 0b0000_0100;

/// The persisted instrument (§ 375). Lives in its own record on the config page
/// rather than in `CFG1`'s flags byte, which § 372 spent the last free bit of —
/// and a `CONFIG_VERSION` bump would have made every existing record decode as
/// "no saved config", costing a runner the GNSS mode, profile, backyard arm and
/// auto-lap rung they had set. A new record at a new offset costs none of them,
/// which is the same trade `WPT1` / `ICE1` / `SCR1` already made.
///
/// Layout: `magic(4) | version(1) | flags(1) | preset_idx(1) | pad(1) |
/// elapsed_s(4) | wall_s(4) | crc32(4)`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TimerRecord {
    flags: u8,
    preset_idx: u8,
    /// Seconds the instrument had run when the record was written.
    elapsed_s: u32,
    /// The [`wall_stamp`] that elapsed was measured at, when one was known and
    /// the instrument was running; 0 otherwise.
    wall_s: u32,
}

impl TimerRecord {
    pub fn encode(&self) -> [u8; TIMER_RECORD_LEN] {
        let mut b = [0u8; TIMER_RECORD_LEN];
        b[0..4].copy_from_slice(&TMR1_MAGIC);
        b[4] = TMR1_VERSION;
        b[5] = self.flags;
        b[6] = self.preset_idx;
        // b[7] pad, zero, CRC-covered.
        b[8..12].copy_from_slice(&self.elapsed_s.to_le_bytes());
        b[12..16].copy_from_slice(&self.wall_s.to_le_bytes());
        let crc = crc32(&b[0..TIMER_RECORD_LEN - 4]);
        b[TIMER_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());
        b
    }

    /// Fail-closed like every other record on the page: too short, the wrong
    /// magic or version, a torn write, or a preset rung this build does not have
    /// all read as "no saved timer" — the watch comes back with a cleared
    /// instrument, never a partly-applied one.
    pub fn decode(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < TIMER_RECORD_LEN || bytes[0..4] != TMR1_MAGIC || bytes[4] != TMR1_VERSION {
            return None;
        }
        let stored = u32::from_le_bytes([
            bytes[TIMER_RECORD_LEN - 4],
            bytes[TIMER_RECORD_LEN - 3],
            bytes[TIMER_RECORD_LEN - 2],
            bytes[TIMER_RECORD_LEN - 1],
        ]);
        if crc32(&bytes[0..TIMER_RECORD_LEN - 4]) != stored {
            return None;
        }
        let preset_idx = bytes[6];
        if preset_idx as usize >= PRESETS_S.len() {
            return None;
        }
        Some(Self {
            flags: bytes[5],
            preset_idx,
            elapsed_s: u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]),
            wall_s: u32::from_le_bytes([bytes[12], bytes[13], bytes[14], bytes[15]]),
        })
    }
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
    /// The reading is a **floor** — see [`Timer::gap_unknown`]. Carried on the
    /// view, not just on the instrument, so the run-view page and the modal make
    /// the same claim about the same number.
    pub gap_unknown: bool,
}

impl TimerView {
    /// The reading, signed on an overrun: `+2:14` is two minutes past zero, and
    /// `>` in place of the sign when the number is only a floor. Both surfaces
    /// call this, so the modal and the page cannot show the same instrument two
    /// ways.
    ///
    /// `>` outranks `+` because it qualifies the digits themselves: an overrun of
    /// *at least* 2:14 is `>2:14`, and a `+` there would read as a measured one.
    pub fn display(&self) -> Clock {
        let mut out = Clock::new();
        if self.gap_unknown {
            let _ = out.push('>');
        } else if self.expired {
            let _ = out.push('+');
        }
        let _ = out.push_str(&format_clock(self.display_s));
        out
    }

    /// The word under the reading. `TIME UP` outranks the run state: a runner
    /// who has overrun needs that before they need to know the clock is still
    /// moving. And it outranks the unmeasured gap too — a lapse the floor already
    /// proves is a fact about the countdown, where `GAP UNKNOWN` is a fact about
    /// the digits, which the `>` on them is already carrying.
    pub fn state_word(&self) -> &'static str {
        if self.expired {
            "TIME UP"
        } else if self.gap_unknown {
            "GAP UNKNOWN"
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

/// Whether the instrument holds anything, and whether its clock is moving — the
/// only two facts a persisted record cannot reconstruct for itself. See
/// [`Timer::persist_key`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TimerPersistKey {
    armed: bool,
    running: bool,
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
    /// The reading is a **floor**: this instrument was running across a reboot
    /// whose duration could not be measured (see the module docs). Every
    /// surface must report elapsed rather than remaining while this is set, and
    /// it clears only on [`Self::reset`].
    ///
    /// Both surfaces say so: the modal ([`timer_rows`]) names the limit on a row
    /// of its own, and the run-view `TIMR` page reads it off
    /// [`TimerView::gap_unknown`] for the `>` prefix and the state word.
    gap_unknown: bool,
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
            gap_unknown: false,
        }
    }

    /// See [`Self::gap_unknown`] — the reading is a floor, not a measurement.
    pub fn reading_is_a_floor(&self) -> bool {
        self.gap_unknown
    }

    /// The state a flash write is owed for. The caller persists exactly when
    /// this moves across a press, and never otherwise.
    ///
    /// It deliberately excludes the reading. An armed instrument's elapsed grows
    /// every second, so a caller that compared the *record* would erase the
    /// config page once per tick — 5,400 erases in one 90-minute countdown,
    /// against a page rated ~10,000. Nothing is lost by leaving it: the record
    /// stores the anchor, and an anchor does not drift. The ladder is reachable
    /// only while nothing is armed, so walking every rung moves this not at all
    /// and costs no erase.
    pub fn persist_key(&self) -> TimerPersistKey {
        TimerPersistKey {
            armed: self.is_armed(),
            running: self.running(),
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
    /// or stopped holding a reading, or carrying an unmeasurable reboot gap. A
    /// preset dialled but never started is deliberately *not* armed — the runner
    /// is standing at the watch with the modal open, and a page for a timer they
    /// have not started is a page for nothing.
    ///
    /// A restored floor of zero still counts: a runner who armed a nap timer one
    /// second before the brown-out is owed the tell most of all, and dropping
    /// the seat because the floor rounded to nothing is the vanishing this whole
    /// record exists to stop.
    pub fn is_armed(&self) -> bool {
        self.running() || self.banked_s > 0 || self.gap_unknown
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
    ///
    /// This is also the only thing that clears [`Self::gap_unknown`]: a fresh
    /// arming is the one state that genuinely has no gap, whereas resuming a
    /// floor keeps every second the floor was already missing.
    pub fn reset(&mut self) -> bool {
        if self.running() || (self.banked_s == 0 && !self.gap_unknown) {
            return false;
        }
        self.banked_s = 0;
        self.gap_unknown = false;
        true
    }

    pub fn view(&self, now_s: u32) -> TimerView {
        let elapsed_s = self.elapsed_s(now_s);
        let preset_s = self.preset_s();
        // A floor above the target still proves the countdown lapsed — that much
        // is certain even when the gap is not.
        let expired = preset_s > 0 && elapsed_s >= preset_s;
        TimerView {
            preset_s,
            elapsed_s,
            display_s: if preset_s == 0 {
                elapsed_s
            } else if expired {
                elapsed_s - preset_s
            } else if self.gap_unknown {
                // A floor reports ELAPSED, because the remaining is exactly the
                // number the unmeasured gap destroyed. `gap_unknown` rides along
                // on the view so a consumer can never read this as a remaining.
                elapsed_s
            } else {
                preset_s - elapsed_s
            },
            running: self.running(),
            expired,
            expiry_seq: if expired { self.arm_seq } else { 0 },
            gap_unknown: self.gap_unknown,
        }
    }

    /// The view the recorder is fed — `None` while nothing is armed, which is
    /// what keeps the page out of the cycle and its metric honestly unfed.
    pub fn snapshot_view(&self, now_s: u32) -> Option<TimerView> {
        self.is_armed().then(|| self.view(now_s))
    }

    /// The record to persist, or `None` when nothing is armed — the caller
    /// clears the stored record rather than writing an idle instrument, so a
    /// cleared timer cannot be resurrected by the next boot.
    ///
    /// `wall_now_s` is a [`wall_stamp`] for right now, or `None` when the
    /// receiver has no plausible date/time. It is read only for a **running**
    /// leg: a stopped reading does not advance, so it needs no anchor and is
    /// reconstructed exactly whatever the clock was doing.
    ///
    /// Call this on a state change only — armed, stopped, resumed, cleared —
    /// never on the tick. The instrument's reading moves every second and
    /// nothing about it needs re-writing for that; the record holds the anchor,
    /// and an anchor does not drift.
    pub fn to_record(&self, now_s: u32, wall_now_s: Option<u32>) -> Option<TimerRecord> {
        if !self.is_armed() {
            return None;
        }
        let anchor = if self.running() { wall_now_s } else { None };
        let mut flags = 0;
        if self.running() {
            flags |= TMR1_FLAG_RUNNING;
        }
        if anchor.is_some() {
            flags |= TMR1_FLAG_WALL_ANCHOR;
        }
        if self.gap_unknown {
            flags |= TMR1_FLAG_GAP_UNKNOWN;
        }
        Some(TimerRecord {
            flags,
            preset_idx: self.preset_idx,
            elapsed_s: self.elapsed_s(now_s),
            wall_s: anchor.unwrap_or(0),
        })
    }

    /// Rebuild the instrument from a persisted record at boot. `now_s` is the
    /// current uptime (the new leg's stamp, if it keeps running) and
    /// `wall_now_s` a [`wall_stamp`] for right now, or `None` while the receiver
    /// has nothing plausible.
    ///
    /// Three outcomes, and which one you get is the whole point of the record:
    ///
    /// - It was **stopped**: restored exactly, still stopped. No gap to measure.
    /// - It was **running** and both wall stamps are known: the gap is
    ///   `wall_now - wall_then`, banked, and the leg keeps running. Exact.
    /// - It was **running** and the gap cannot be measured — no stamp at save,
    ///   none now, or a clock that went backwards: restored **stopped and
    ///   marked** [`Self::gap_unknown`], reporting a floor. Never resumed as
    ///   though the gap were zero, which is the lie this exists to refuse.
    pub fn from_record(rec: &TimerRecord, now_s: u32, wall_now_s: Option<u32>) -> Self {
        let mut t = Self {
            preset_idx: rec.preset_idx,
            banked_s: rec.elapsed_s,
            running_since_s: None,
            // The arming this reading belongs to is over; 1 is simply "armed
            // once", which cannot alias `arm_seq`'s never-armed zero. The alert
            // engine's own once-per-edge memory reset with the reboot, so a
            // countdown that lapsed during it still gets its one banner.
            arm_seq: 1,
            gap_unknown: rec.flags & TMR1_FLAG_GAP_UNKNOWN != 0,
        };
        if rec.flags & TMR1_FLAG_RUNNING == 0 {
            return t;
        }
        let anchor = (rec.flags & TMR1_FLAG_WALL_ANCHOR != 0).then_some(rec.wall_s);
        match (anchor, wall_now_s) {
            (Some(then), Some(now)) if now >= then => {
                t.banked_s = t.banked_s.saturating_add(now - then);
                t.running_since_s = Some(now_s);
            }
            _ => t.gap_unknown = true,
        }
        t
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

/// First row of the modal's body. Row 0 is the legend and row 1 the title,
/// mirroring the settings menu's chrome, and row 2 is held blank so that title
/// band reads as chrome rather than as a third body line — the layout
/// `settings_menu` also had until § 378 spent its own spacer on a seventh item.
///
/// The body then runs rows 3-6 (the reading, the state word, and either the
/// armed preset or the ladder / reset row), and row 7 carries the reboot-gap
/// disclosure when there is one — the first draw on the tail this comment used
/// to call unspent, leaving row 8 as what is left of it.
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
    if timer.gap_unknown {
        // Says what the `>` on the reading means, in the register § 373's
        // `WATCH CANNOT WAKE YOU` and § 376's `TENDENCY NOT FORECAST` set: name
        // the limit on the surface that carries the number.
        let _ = rows[TIMER_TOP_ROW + 4].push_str("REBOOT GAP UNKNOWN");
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

    fn date(year: u16, month: u8, day: u8) -> Date {
        Date { year, month, day }
    }

    /// A timer armed at rung `idx` and started at uptime 0.
    fn armed(idx: usize) -> Timer {
        let mut t = Timer::new();
        for _ in 0..idx {
            t.preset_up();
        }
        t.start_stop(0);
        t
    }

    #[test]
    fn the_wall_stamp_is_absolute_leap_aware_and_refuses_an_implausible_year() {
        assert_eq!(wall_stamp(date(2000, 1, 1), 0), Some(0));
        assert_eq!(wall_stamp(date(2000, 1, 1), 3_600), Some(3_600));
        // 2000 was a leap year, so 2001-01-01 is day 366.
        assert_eq!(wall_stamp(date(2001, 1, 1), 0), Some(366 * 86_400));
        // 26 whole years plus the 7 leap days 2000-2024, then day-of-year 189.
        let jul_8_2026 = (26 * 365 + 7 + 188) * 86_400 + 27_000;
        assert_eq!(wall_stamp(date(2026, 7, 8), 27_000), Some(jul_8_2026));
        // Strictly increasing across a midnight — the whole reason the stamp is
        // absolute rather than a time-of-day.
        let before = wall_stamp(date(2026, 7, 8), 86_399).unwrap();
        let after = wall_stamp(date(2026, 7, 9), 0).unwrap();
        assert_eq!(after, before + 1);
        // A receiver mid-cold-start: a stamp that is wrong is worse than none.
        assert_eq!(wall_stamp(date(1980, 1, 1), 0), None);
        assert_eq!(wall_stamp(date(0, 1, 1), 0), None);
        assert_eq!(wall_stamp(date(9999, 1, 1), 0), None);
    }

    #[test]
    fn nothing_armed_persists_nothing() {
        let t = Timer::new();
        assert_eq!(t.to_record(0, Some(1_000)), None);
        // A preset dialled but never started is not armed, so walking the whole
        // ladder costs the config page no erase at all.
        let mut t = Timer::new();
        for _ in 0..PRESETS_S.len() {
            t.preset_up();
            assert_eq!(t.to_record(0, Some(1_000)), None, "a ladder press is free");
        }
    }

    #[test]
    fn a_stopped_reading_round_trips_exactly_with_no_clock_at_all() {
        // The honest asymmetry: a stopped reading does not advance, so it needs
        // no anchor and the reboot gap cannot touch it.
        let mut t = armed(3);
        assert_eq!(t.preset_s(), 300);
        t.start_stop(120);
        let rec = t.to_record(120, None).expect("armed");
        let bytes = rec.encode();
        let back = Timer::from_record(&TimerRecord::decode(&bytes).expect("decode"), 7, None);
        assert!(!back.running());
        assert!(!back.reading_is_a_floor(), "no gap was ever in question");
        assert_eq!(back.preset_s(), 300);
        assert_eq!(back.elapsed_s(9_999), 120);
        let v = back.view(9_999);
        assert_eq!(v.display().as_str(), "3:00", "180 s left, exactly");
        assert_eq!(v.state_word(), "STOPPED");
    }

    #[test]
    fn a_running_countdown_reconstructs_the_gap_from_the_wall_clock() {
        let t = armed(9);
        assert_eq!(t.preset_s(), 3_600);
        let saved_wall = wall_stamp(date(2026, 7, 8), 3 * 3_600).unwrap();
        let rec = t.to_record(600, Some(saved_wall)).expect("armed");
        // The brown-out lasted 25 minutes; uptime came back at 4 s.
        let back = Timer::from_record(&rec, 4, Some(saved_wall + 1_500));
        assert!(back.running(), "a measured gap resumes, it does not stop");
        assert!(!back.reading_is_a_floor());
        assert_eq!(back.elapsed_s(4), 600 + 1_500);
        let v = back.view(4);
        assert_eq!(v.display().as_str(), "25:00", "3600 - 2100 remaining");
        assert_eq!(v.state_word(), "RUNNING");
        // And the new leg keeps running off the fresh uptime.
        assert_eq!(back.elapsed_s(64), 600 + 1_500 + 60);
    }

    #[test]
    fn a_running_countdown_with_no_measurable_gap_is_marked_not_resumed() {
        let t = armed(8);
        assert_eq!(t.preset_s(), 2_700);
        let wall = wall_stamp(date(2026, 7, 8), 3_600).unwrap();
        // No fix when it was saved: the anchor was never written.
        let no_anchor = t.to_record(723, None).expect("armed");
        let back = Timer::from_record(&no_anchor, 5, Some(wall + 99_999));
        assert!(!back.running(), "an unknown gap may not keep counting");
        assert!(back.reading_is_a_floor());
        assert_eq!(back.elapsed_s(5), 723, "the floor is what was banked");
        // No fix on the way back: the anchor is there and unusable.
        let anchored = t.to_record(723, Some(wall)).expect("armed");
        let back = Timer::from_record(&anchored, 5, None);
        assert!(!back.running());
        assert!(back.reading_is_a_floor());
        assert_eq!(back.elapsed_s(5), 723);
    }

    #[test]
    fn a_backwards_wall_clock_is_refused_rather_than_wrapped() {
        // A receiver that re-acquires with an earlier date than the one the
        // anchor was taken against cannot bound the gap either way.
        let t = armed(4);
        let wall = wall_stamp(date(2026, 7, 8), 40_000).unwrap();
        let rec = t.to_record(60, Some(wall)).expect("armed");
        let back = Timer::from_record(&rec, 1, Some(wall - 1));
        assert!(!back.running());
        assert!(back.reading_is_a_floor());
        assert_eq!(back.elapsed_s(1), 60, "never a wrapped century of elapsed");
        // Zero gap is measurable, though — the same instant is a real answer.
        let back = Timer::from_record(&rec, 1, Some(wall));
        assert!(back.running());
        assert!(!back.reading_is_a_floor());
        assert_eq!(back.elapsed_s(1), 60);
    }

    #[test]
    fn a_marked_reading_reports_elapsed_and_never_a_remaining() {
        let t = armed(8);
        let rec = t.to_record(723, None).expect("armed");
        let back = Timer::from_record(&rec, 0, None);
        let v = back.view(0);
        assert!(!v.expired);
        assert_eq!(
            v.display_s, 723,
            "the remaining is exactly what the unmeasured gap destroyed"
        );
        // `>` qualifies the digits, on BOTH surfaces — the view carries the flag
        // so the run-view page cannot show 12:03 as a measured stopped reading.
        assert_eq!(v.display().as_str(), ">12:03");
        assert_eq!(v.state_word(), "GAP UNKNOWN");
        // And the modal additionally names the limit in words.
        let rows = timer_rows(&back, 0);
        assert_eq!(rows[TIMER_TOP_ROW].as_str(), ">12:03");
        assert_eq!(rows[TIMER_TOP_ROW + 1].as_str(), "GAP UNKNOWN");
        assert_eq!(rows[TIMER_TOP_ROW + 2].as_str(), "SET 45:00");
        assert_eq!(rows[TIMER_TOP_ROW + 4].as_str(), "REBOOT GAP UNKNOWN");
    }

    #[test]
    fn a_floor_above_the_target_still_proves_the_countdown_lapsed() {
        // Certainty runs one way: the gap is unknown, so elapsed is a floor, and
        // a floor past the target means it lapsed for sure. The overrun is then
        // itself a floor, so it reads `>` and NOT `+` — a `+` would claim the
        // overrun had been measured — while the word stays the lapse itself.
        let mut t = armed(1);
        assert_eq!(t.preset_s(), 60);
        t.start_stop(200);
        let rec = t.to_record(200, None).expect("armed");
        let mut running = Timer::from_record(&rec, 0, None);
        running.gap_unknown = true;
        let v = running.view(0);
        assert!(v.expired, "200 s banked against a 60 s target");
        assert_eq!(v.display().as_str(), ">2:20");
        assert_eq!(v.state_word(), "TIME UP");
        assert_ne!(v.expiry_seq, 0, "a restored lapse is still owed its banner");
    }

    #[test]
    fn a_zero_floor_still_owes_a_page_seat_and_the_tell() {
        // The cruellest case: armed one second before the brown-out. Dropping
        // the seat because the floor rounded to nothing is the vanishing this
        // record exists to stop.
        let t = armed(8);
        let rec = t.to_record(0, None).expect("armed");
        let back = Timer::from_record(&rec, 0, None);
        assert_eq!(back.elapsed_s(0), 0);
        assert!(back.is_armed(), "a marked instrument holds a page seat");
        assert!(back.snapshot_view(0).is_some());
        assert_eq!(
            timer_rows(&back, 0)[TIMER_TOP_ROW + 4].as_str(),
            "REBOOT GAP UNKNOWN"
        );
    }

    #[test]
    fn the_mark_survives_its_own_re_persist() {
        // A second reboot that happens to have a good fix must not launder an
        // inherited floor into an exact reading.
        let t = armed(8);
        let first = Timer::from_record(&t.to_record(723, None).expect("armed"), 0, None);
        assert!(first.reading_is_a_floor());
        let wall = wall_stamp(date(2026, 7, 9), 100).unwrap();
        let again = first.to_record(0, Some(wall)).expect("still armed");
        let back = Timer::from_record(
            &TimerRecord::decode(&again.encode()).unwrap(),
            0,
            Some(wall),
        );
        assert!(
            back.reading_is_a_floor(),
            "a floor stays a floor across every later reboot"
        );
        assert_eq!(back.elapsed_s(0), 723);
    }

    #[test]
    fn resetting_is_the_only_thing_that_clears_the_mark() {
        let t = armed(8);
        let mut back = Timer::from_record(&t.to_record(723, None).expect("armed"), 0, None);
        // Resuming keeps it: every second the floor was already missing is still
        // missing.
        back.start_stop(0);
        assert!(back.reading_is_a_floor());
        assert!(
            !back.preset_up(),
            "the target is still the one being measured"
        );
        back.start_stop(30);
        assert!(back.reading_is_a_floor());
        // A fresh arming genuinely has no gap.
        assert!(back.reset());
        assert!(!back.reading_is_a_floor());
        assert!(!back.is_armed());
        assert!(back.preset_up(), "the ladder is live again");
        // And a zero floor is still something to clear, or the tell would be
        // stuck on the watch with no way to dismiss it.
        let mut zero = Timer::from_record(&armed(8).to_record(0, None).unwrap(), 0, None);
        assert!(zero.reset());
        assert!(!zero.is_armed());
    }

    #[test]
    fn the_anchor_is_what_carries_the_time_so_the_tick_needs_no_rewrite() {
        // The flash-wear argument, as an invariant rather than a promise: a
        // record written at any point in a running leg reconstructs the SAME
        // reading, because the elapsed it stores and the anchor it stores move
        // together. Rewriting per tick would buy nothing.
        let t = armed(9);
        let base = wall_stamp(date(2026, 7, 8), 3_600).unwrap();
        let restore_at = base + 4_000;
        let mut readings = heapless::Vec::<u32, 8>::new();
        for tick in [0u32, 1, 59, 600, 1_800] {
            let rec = t.to_record(tick, Some(base + tick)).expect("armed");
            let back = Timer::from_record(&rec, 0, Some(restore_at));
            readings.push(back.elapsed_s(0)).unwrap();
        }
        for r in readings.iter() {
            assert_eq!(*r, 4_000, "every tick's record rebuilds one reading");
        }
    }

    /// The button task's rule, reproduced exactly: walk a press sequence and
    /// count how many of them the `persist_key` gate lets through to flash.
    fn erases_for(presses: &[(TimerKey, u32)]) -> usize {
        let mut t = Timer::new();
        let mut erases = 0;
        for (key, now_s) in presses {
            let before = t.persist_key();
            if press(&mut t, *key, *now_s) == TimerPress::Changed && t.persist_key() != before {
                // The task would call `persist_timer(t.to_record(..))` here.
                erases += 1;
            }
        }
        erases
    }

    #[test]
    fn the_write_gate_fires_on_a_state_change_and_never_on_a_tick() {
        use TimerKey::*;
        // One nap: dial 45 min, start, stop, clear. Only the last three move the
        // state, so the eight ladder presses cost the config page nothing.
        let mut presses: heapless::Vec<(TimerKey, u32), 32> = heapless::Vec::new();
        for _ in 0..8 {
            presses.push((Longer, 0)).unwrap();
        }
        assert_eq!(erases_for(&presses), 0, "walking the ladder is free");
        presses.push((StartStop, 0)).unwrap();
        presses.push((StartStop, 2_700)).unwrap();
        presses.push((Reset, 2_700)).unwrap();
        assert_eq!(erases_for(&presses), 3, "arm, stop, clear");
        // A pause and resume mid-timing is two more, and nothing else is.
        let mut with_pause = presses.clone();
        with_pause.clear();
        for p in presses.iter().take(9) {
            with_pause.push(*p).unwrap();
        }
        with_pause.push((StartStop, 600)).unwrap();
        with_pause.push((StartStop, 900)).unwrap();
        with_pause.push((StartStop, 2_700)).unwrap();
        with_pause.push((Reset, 2_700)).unwrap();
        assert_eq!(
            erases_for(&with_pause),
            5,
            "arm, pause, resume, stop, clear"
        );
        // And the tick itself is not a press, so it cannot reach the gate at all:
        // an armed instrument's key is identical at every second of its run.
        let armed = armed(8);
        let key = armed.persist_key();
        for now_s in [0u32, 1, 60, 1_349, 2_699, 2_700, 100_000] {
            assert_eq!(armed.persist_key(), key);
            // ...while the record it WOULD write moves every one of those
            // seconds, which is exactly why the gate cannot read the record.
            assert_eq!(armed.to_record(now_s, None).unwrap().elapsed_s, now_s);
        }
    }

    #[test]
    fn a_realistic_race_stays_far_inside_the_pages_erase_endurance() {
        // ~16 crew-access aid stations plus ~6 sleep-station naps on a 240-mile
        // race, three erases each (arm, stop, clear). The point of the number is
        // that it is two orders of magnitude under the ~10,000 erase-cycle page
        // rating `record_cadence` quotes — per-tick writing would be 5,400 for a
        // single 90-minute countdown.
        let per_timing = erases_for(&[
            (TimerKey::StartStop, 0),
            (TimerKey::StartStop, 300),
            (TimerKey::Reset, 300),
        ]);
        assert_eq!(per_timing, 3);
        assert!(
            (16 + 6) * per_timing < 100,
            "a race's timers should cost well under 100 erases"
        );
    }

    #[test]
    fn a_corrupt_truncated_or_future_record_reads_as_no_saved_timer() {
        let good = armed(4).to_record(90, Some(1_000)).unwrap().encode();
        assert!(TimerRecord::decode(&good).is_some());
        // An erased page.
        assert_eq!(TimerRecord::decode(&[0xFF; TIMER_RECORD_LEN]), None);
        assert_eq!(TimerRecord::decode(&[0x00; TIMER_RECORD_LEN]), None);
        // Truncated — including one byte short of the CRC.
        for n in 0..TIMER_RECORD_LEN {
            assert_eq!(TimerRecord::decode(&good[..n]), None, "{n} bytes");
        }
        // Wrong magic.
        let mut bad = good;
        bad[0] = b'X';
        assert_eq!(TimerRecord::decode(&bad), None);
        // A version this build does not know, CRC and all — the version gate has
        // to refuse it on its own, not be covered for by a CRC that happens to
        // fail. A future writer with a wider record would produce exactly this.
        let mut future = good;
        future[4] = TMR1_VERSION + 1;
        let crc = crate::run_store::crc32(&future[0..TIMER_RECORD_LEN - 4]);
        future[TIMER_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());
        assert_eq!(TimerRecord::decode(&future), None, "a valid CRC over v2");
        // Every single-byte flip in the CRC-covered span is refused.
        for i in 0..TIMER_RECORD_LEN - 4 {
            let mut torn = good;
            torn[i] ^= 0x01;
            assert_eq!(TimerRecord::decode(&torn), None, "byte {i}");
        }
        // A preset rung this build does not have: the record is CRC-valid and
        // still refused, because clamping would silently measure the reading
        // against a different duration than the runner set.
        let mut rung = TimerRecord::decode(&good).unwrap();
        rung.preset_idx = PRESETS_S.len() as u8;
        assert_eq!(TimerRecord::decode(&rung.encode()), None);
    }

    #[test]
    fn a_valid_record_never_half_applies_over_a_longer_buffer() {
        // The record shares its page with five others, so `decode` is handed a
        // read that runs past its own extent.
        let good = armed(2).to_record(45, None).unwrap();
        let mut page = [0xFFu8; TIMER_RECORD_LEN + 64];
        page[..TIMER_RECORD_LEN].copy_from_slice(&good.encode());
        assert_eq!(TimerRecord::decode(&page), Some(good));
    }

    #[test]
    fn every_modal_row_still_fits_the_face_while_a_reading_is_a_floor() {
        for idx in 0..PRESETS_S.len() {
            for elapsed in [0u32, 1, 59, 3_600, 100_000, u32::MAX / 2] {
                let rec = {
                    let mut t = armed(idx);
                    t.start_stop(elapsed);
                    t.to_record(elapsed, None)
                };
                let Some(rec) = rec else { continue };
                let mut floor = Timer::from_record(&rec, 0, None);
                floor.gap_unknown = true;
                for running in [false, true] {
                    if running {
                        floor.start_stop(elapsed);
                    }
                    for row in timer_rows(&floor, elapsed).iter() {
                        assert!(row.len() <= COLS, "row too wide: {row:?}");
                    }
                }
            }
        }
    }
}
