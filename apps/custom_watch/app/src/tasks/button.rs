//! Button task — turns the DK's control buttons into `RecordCommand`s.
//!
//! Thin glue by design: the press → command decision lives in the host-tested
//! `watch_core::button` (which command a button issues in a given run state);
//! this task owns only the hardware that module can't reach — edge detection
//! and contact debounce.
//!
//! Mapping (see `watch_core::button::command_for`):
//!   BTN1 — start / pause / resume toggle
//!   BTN2 — stop
//!   BTN3 — cycle the run-view page (dashboard / distance / pace / ... —
//!          `watch_core::page` owns the frequency-ordered cycle) while a run
//!          is under way;
//!          cycle the GNSS recording mode (Performance / Balanced /
//!          Expedition) on the idle face; long-press = page back in a run,
//!          manual QNH re-zero on the idle face
//!   BTN4 — manual lap (the Fenix layout's lower-right Lap, decisions §81);
//!          once a run is finished the lap is dead and a tap pages the
//!          review backward instead (`watch_core::button::btn4_action`), so
//!          the post-run pages move both ways on taps
//! The buttons are active-LOW (idle high, press pulls low), so a press is a
//! falling edge and a held press reads `is_low()`. BTN3 carries no recording
//! command — what a press does is the host-tested
//! `watch_core::button::btn3_action` (idle = mode / re-zero, any run view =
//! pages, so a run's mode and altitude reference are frozen for its duration).

use defmt::*;
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select, Either};
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select4, Either4};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Instant, Timer};
#[cfg(feature = "sim-buttons")]
use watch_core::button::classify_btn3_hold;
use watch_core::button::{
    btn3_action, btn4_action, command_for, grid_press, Btn3Action, Btn3Press, Btn4Action, Button,
    GridPress, RecordCommand, StopGuard, StopPress, BTN3_GRID_HOLD_MS, BTN3_LONG_PRESS_MS,
    STOP_CONFIRM_WINDOW_S,
};
use watch_core::gnss_mode::GnssMode;
use watch_core::page::Page;
use watch_core::page_grid::{PageGrid, GRID_AUTOSELECT_S};
use watch_core::record::RecordState;

use crate::run_flash::SharedStore;
use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
#[cfg(not(feature = "sim-buttons"))]
const DEBOUNCE: Duration = Duration::from_millis(20);

/// How long BTN3 must be held to count as a long-press. A short BTN3 press
/// still cycles forward (page next / GNSS mode); a long-press cycles the run
/// pages *backward*, so a late page in the cycle is one press away instead of
/// many, and on the idle face requests the manual QNH re-zero. A deliberate
/// hold, not a chord — inside decisions §81's five-button, no-chord budget.
/// Both directions walk the snapshot's `pages_mask` (data-present ∩ curated),
/// so BTN3 never lands on an empty glance unless the runner turned the
/// hide-empty filter off. The threshold itself lives host-tested in
/// `watch_core::button`.
const BTN3_LONG_PRESS: Duration = Duration::from_millis(BTN3_LONG_PRESS_MS as u64);

/// Holding BTN3 past this in a run view opens the page-grid overview
/// (`watch_core::page_grid`) — the third press tier. It fires while the button
/// is still held (the grid appearing IS the feedback), which moves the
/// page-back long-press from fire-at-threshold to fire-on-release: releasing
/// anywhere in the second between the two thresholds is a page back, a full
/// deliberate hold is the grid. The idle face keeps its two tiers — a hold of
/// any length stays the QNH re-zero, so duration never changes an idle
/// gesture mid-press.
const BTN3_GRID_HOLD: Duration = Duration::from_millis(BTN3_GRID_HOLD_MS as u64);

/// The grid's auto-select window as a `Duration` (see
/// `page_grid::GRID_AUTOSELECT_S` — the pure module owns the number).
const GRID_AUTOSELECT: Duration = Duration::from_secs(GRID_AUTOSELECT_S as u64);

#[cfg(not(feature = "sim-buttons"))]
#[embassy_executor::task]
pub async fn run(
    mut btn1: Input<'static>,
    mut btn2: Input<'static>,
    mut btn3: Input<'static>,
    mut btn4: Input<'static>,
    initial_mode: GnssMode,
    store: &'static SharedStore,
) {
    let mut record_rx = unwrap!(state::RECORD.receiver());
    let page_tx = state::PAGE.sender();
    let grid_tx = state::PAGE_GRID.sender();
    let mode_tx = state::GNSS_MODE.sender();
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    // Seed from the mode main restored from flash at boot so the BTN3 cycle
    // continues from the persisted choice rather than the default.
    let mut mode = initial_mode;
    let mut stop_guard = StopGuard::new();
    // The page-grid overview: this task owns the state machine and its
    // auto-select deadline; the ui task only renders the published cursor.
    let mut grid: Option<PageGrid> = None;
    let mut grid_deadline: Option<Instant> = None;
    info!("button: BTN1 start/pause, BTN2 stop, BTN3 page/mode (hold: grid), BTN4 lap/back");
    loop {
        // Wait for whichever button is pressed first (falling edge = press) —
        // or, while the grid is open, for its auto-select deadline: the
        // no-confirm-press close (hold to open, tap to the target, lower the
        // wrist).
        let edges = select4(
            btn1.wait_for_falling_edge(),
            btn2.wait_for_falling_edge(),
            btn3.wait_for_falling_edge(),
            btn4.wait_for_falling_edge(),
        );
        let pressed = if let Some(deadline) = grid_deadline {
            match select(edges, Timer::at(deadline)).await {
                Either::First(e) => e,
                Either::Second(()) => {
                    if let Some(g) = grid.take() {
                        page = g.cursor();
                        info!("button: grid auto-select -> page {}", page);
                        page_tx.send(page);
                    }
                    grid_deadline = None;
                    grid_tx.send(None);
                    continue;
                }
            }
        } else {
            edges.await
        };
        let button = match pressed {
            Either4::First(()) => Button::Primary,
            Either4::Second(()) => Button::Stop,
            Either4::Third(()) => {
                // BTN3 is its own concern — no recording command. Debounce,
                // confirm the press held, then act on whichever surface the
                // state puts it on (grid open = cursor, run view = pages,
                // idle = GNSS mode / re-zero).
                Timer::after(DEBOUNCE).await;
                if btn3.is_low() {
                    interaction_tx.send(Instant::now().as_secs() as u32);
                    if let Some(g) = grid.as_mut() {
                        // In-grid: tap steps the cursor, a hold drops a whole
                        // grid row — the long jump.
                        let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                        match select(Timer::after(BTN3_LONG_PRESS), btn3.wait_for_rising_edge())
                            .await
                        {
                            Either::Second(()) => g.tap(mask),
                            Either::First(()) => {
                                g.row_down(mask);
                                // The timer arm dropped the edge future (and
                                // its SENSE arm), so a release landing in the
                                // re-arm gap would make a fresh
                                // wait_for_rising_edge wait for a whole NEW
                                // press — hanging every button. Only wait out
                                // the release while the pin is still held.
                                if btn3.is_low() {
                                    btn3.wait_for_rising_edge().await;
                                }
                            }
                        }
                        info!("button: grid cursor -> {}", g.cursor());
                        grid_tx.send(Some(g.cursor()));
                        // Deadline runs from the release, so a held button
                        // can't burn the window before the runner lets go.
                        grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                        continue;
                    }
                    let snap = record_rx.try_get();
                    let state = snap.map(|s| s.state).unwrap_or(RecordState::Idle);
                    // Idle keeps its two-tier timing (the re-zero fires at the
                    // long threshold, as always); a run view times three tiers:
                    // release before the long threshold = page next, release
                    // between the thresholds = page back, still held at the
                    // grid threshold = the grid opens (while held — the grid
                    // appearing is the feedback that the hold registered).
                    // Each timer-won select drops its losing edge future, so a
                    // release landing in the gap before the next select arms
                    // would go unseen and stretch the classification a full
                    // tier (or hang the release swallow). A level check after
                    // every timer win keeps a lost edge classified by what the
                    // pin actually says.
                    let press = if state == RecordState::Idle {
                        match select(Timer::after(BTN3_LONG_PRESS), btn3.wait_for_rising_edge())
                            .await
                        {
                            Either::Second(()) => Btn3Press::Short,
                            Either::First(()) => Btn3Press::Long,
                        }
                    } else {
                        match select(Timer::after(BTN3_LONG_PRESS), btn3.wait_for_rising_edge())
                            .await
                        {
                            Either::Second(()) => Btn3Press::Short,
                            Either::First(()) if !btn3.is_low() => Btn3Press::Long,
                            Either::First(()) => match select(
                                Timer::after(BTN3_GRID_HOLD - BTN3_LONG_PRESS),
                                btn3.wait_for_rising_edge(),
                            )
                            .await
                            {
                                Either::Second(()) => Btn3Press::Long,
                                Either::First(()) if !btn3.is_low() => Btn3Press::Long,
                                Either::First(()) => Btn3Press::GridHold,
                            },
                        }
                    };
                    match btn3_action(state, press) {
                        Btn3Action::PageNext | Btn3Action::PagePrev => {
                            // Walk the filtered cycle (data-present ∩ curated,
                            // from the snapshot); no snapshot means no filter.
                            let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
                            page = if press == Btn3Press::Long {
                                page.prev_in(mask)
                            } else {
                                page.next_in(mask)
                            };
                            info!("button: BTN3 -> page {}", page);
                            page_tx.send(page);
                        }
                        Btn3Action::OpenGrid => {
                            let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
                            let g = PageGrid::open(page, mask);
                            info!("button: BTN3 hold -> page grid at {}", g.cursor());
                            grid_tx.send(Some(g.cursor()));
                            grid = Some(g);
                            // Swallow the release of the opening hold (only
                            // while actually still held — see the level-check
                            // note above), then start the auto-select clock.
                            if btn3.is_low() {
                                btn3.wait_for_rising_edge().await;
                            }
                            grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                        }
                        Btn3Action::CycleGnssMode => {
                            mode = mode.next();
                            info!(
                                "button: BTN3 -> gnss mode {} (fix interval {=u32}s, ~{=u32}h)",
                                mode,
                                mode.fix_interval_s(),
                                mode.battery_est_h()
                            );
                            mode_tx.send(mode);
                            // Persist so the choice survives reboot / brown-out.
                            // Best-effort / L4: a flash error only warns; the
                            // mode switch is never blocked on flash.
                            store.lock().await.persist_gnss_mode(mode).await;
                        }
                        Btn3Action::QnhRezero => {
                            info!("button: BTN3 long -> qnh re-zero requested");
                            // try_send: a request already pending covers this
                            // press too.
                            let _ = state::QNH_REZERO_REQ.try_send(());
                        }
                    }
                }
                continue;
            }
            Either4::Fourth(()) => Button::Lap,
        };

        // Debounce: let the contacts settle, then confirm the press held. A
        // bounce that has already released by now is dropped.
        Timer::after(DEBOUNCE).await;
        let held = match button {
            Button::Primary => btn1.is_low(),
            Button::Stop => btn2.is_low(),
            Button::Lap => btn4.is_low(),
        };
        if !held {
            continue;
        }
        // A confirmed press is an interaction, whether or not it maps to a
        // command in the current state — it wakes the face's animation window.
        let now_s = Instant::now().as_secs() as u32;
        interaction_tx.send(now_s);

        // While the grid is open every button belongs to it: BTN4 confirms the
        // jump, BTN1 drives the cursor backward, BTN2 cancels — and none of
        // them reaches the recorder: a navigation modal must never pause,
        // stop-arm, or lap a run.
        if grid.is_some() {
            match grid_press(button) {
                GridPress::CursorBack => {
                    if let Some(g) = grid.as_mut() {
                        // The backward mirror of the in-grid BTN3: tap = one
                        // cell back, hold = one row up, with the same lost-
                        // release level check.
                        let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                        match select(Timer::after(BTN3_LONG_PRESS), btn1.wait_for_rising_edge())
                            .await
                        {
                            Either::Second(()) => g.back(mask),
                            Either::First(()) => {
                                g.row_up(mask);
                                if btn1.is_low() {
                                    btn1.wait_for_rising_edge().await;
                                }
                            }
                        }
                        info!("button: grid cursor -> {}", g.cursor());
                        grid_tx.send(Some(g.cursor()));
                        grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    }
                    continue;
                }
                GridPress::Select => {
                    if let Some(g) = grid.take() {
                        page = g.cursor();
                        info!("button: grid select -> page {}", page);
                        page_tx.send(page);
                    }
                }
                GridPress::Cancel => {
                    info!("button: grid cancelled");
                    grid = None;
                }
            }
            grid_deadline = None;
            grid_tx.send(None);
            continue;
        }

        // The toggle keys off the latest published run state. `try_get` never
        // waits: before the first snapshot the run is idle, which is correct.
        let snap = record_rx.try_get();
        let state = snap.map(|s| s.state).unwrap_or(RecordState::Idle);
        // A finished run turns the dead lap key into a tap page-back (the
        // host-tested btn4_action): the post-run review pages both ways on
        // taps — BTN3 forward, BTN4 back.
        if button == Button::Lap && btn4_action(state) == Some(Btn4Action::PageBack) {
            let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
            page = page.prev_in(mask);
            info!("button: BTN4 -> page {} (back)", page);
            page_tx.send(page);
            continue;
        }
        if dispatch(button, state, now_s, &mut stop_guard).await == Some(RecordCommand::Reset) {
            // Dismissed home: the next run opens on the Dashboard, not on
            // whatever page the last one was parked on.
            page = Page::default();
            page_tx.send(page);
        }
    }
}

/// Turn a confirmed press into a recording command, gating the terminal `Stop`
/// behind the host-tested [`StopGuard`] double-press so a single cold/gloved
/// mis-press can't end a multi-hour recording. Publishes the guard's armed
/// state so the face can show the "press again" prompt — an invisible arm
/// reads as a dead button. Returns the command it sent, if any, so a caller
/// can react (the page reset on a dismissed run). Shared by the hardware and
/// sim button tasks.
async fn dispatch(
    button: Button,
    state: RecordState,
    now_s: u32,
    stop_guard: &mut StopGuard,
) -> Option<RecordCommand> {
    match button {
        Button::Stop => {
            match stop_guard.press(state, now_s) {
                StopPress::Confirmed => {
                    info!("button: BTN2 -> stop (confirmed)");
                    state::STOP_ARMED.sender().send(None);
                    state::RECORD_CMD.send(RecordCommand::Stop).await;
                    return Some(RecordCommand::Stop);
                }
                StopPress::Armed => {
                    info!(
                        "button: BTN2 armed — press again within {=u32}s to stop",
                        STOP_CONFIRM_WINDOW_S
                    );
                    state::STOP_ARMED.sender().send(Some(now_s));
                }
                StopPress::Inert => state::STOP_ARMED.sender().send(None),
            }
            None
        }
        _ => {
            if let Some(cmd) = command_for(button, state) {
                info!("button: {} -> {}", button, cmd);
                state::RECORD_CMD.send(cmd).await;
                return Some(cmd);
            }
            None
        }
    }
}

/// Sim-only button task — polls the DK button pin levels instead of waiting on
/// a hardware falling edge.
///
/// The hardware `run` above waits on `wait_for_falling_edge`, which the
/// nRF52840 drives from the GPIO SENSE/DETECT + PORT-event mechanism. Renode's
/// nRF52840 GPIO model implements the IN register (pin level) but not
/// SENSE/DETECT, so that edge future never wakes under the sim. This variant
/// samples the pin levels on a short timer and detects the falling edge in
/// software, so the `btn1`/`btn2`/`btn3`/`btn4` monitor macros in
/// `sim/watch.resc` drive the SAME `command_for` / page logic the real task
/// uses. The mapping is identical (BTN1 start/pause/resume, BTN2 stop, BTN3
/// page / idle GNSS mode, BTN4 lap / finished-run page back). Renode has no contact bounce, so a clean
/// edge needs no debounce confirm.
///
/// Feature-gated to the sim build; the hardware task keeps the low-power SENSE
/// path (docs/custom_watch/performance_path.md — "every wake justifiable").
#[cfg(feature = "sim-buttons")]
#[embassy_executor::task]
pub async fn run(
    btn1: Input<'static>,
    btn2: Input<'static>,
    btn3: Input<'static>,
    btn4: Input<'static>,
    initial_mode: GnssMode,
    store: &'static SharedStore,
) {
    /// Poll cadence. The `click` macro holds a press ~0.3 s, so any interval
    /// well under that catches the edge; short enough to feel instant.
    const POLL: Duration = Duration::from_millis(10);

    let mut record_rx = unwrap!(state::RECORD.receiver());
    let page_tx = state::PAGE.sender();
    let grid_tx = state::PAGE_GRID.sender();
    let mode_tx = state::GNSS_MODE.sender();
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    let mut mode = initial_mode;
    let mut stop_guard = StopGuard::new();
    let mut grid: Option<PageGrid> = None;
    let mut grid_deadline: Option<Instant> = None;

    // Active-low: pressed pulls the line low. Track the previous level per
    // button so a release→press transition (high→low) fires exactly once.
    let btns = [btn1, btn2, btn3, btn4];
    let mut prev = [
        btns[0].is_low(),
        btns[1].is_low(),
        btns[2].is_low(),
        btns[3].is_low(),
    ];
    // BTN3 times its hold from the press; threshold-crossing actions (the
    // in-grid row jump, the grid open) fire while still held — mirroring the
    // hardware task — and mark the press handled so its release is inert.
    let mut btn3_down_at: Option<Instant> = None;
    let mut btn3_handled = false;
    // BTN1 gets the same treatment, but only while the grid is open (its
    // backward cursor role); a grid-closed BTN1 keeps acting on the falling
    // edge so pause stays instant.
    let mut btn1_down_at: Option<Instant> = None;
    let mut btn1_handled = false;
    info!(
        "button(sim): polling BTN1 start/pause, BTN2 stop, BTN3 page/mode (hold: grid), BTN4 lap/back"
    );

    loop {
        Timer::after(POLL).await;
        // The grid's auto-select deadline — the no-confirm-press close.
        if grid.is_some() && grid_deadline.is_some_and(|dl| Instant::now() >= dl) {
            if let Some(g) = grid.take() {
                page = g.cursor();
                info!("button: grid auto-select -> page {}", page);
                page_tx.send(page);
            }
            grid_deadline = None;
            grid_tx.send(None);
        }
        for (i, b) in btns.iter().enumerate() {
            let pressed = b.is_low();
            let was = prev[i];
            prev[i] = pressed;
            let falling = pressed && !was;
            let rising = !pressed && was;

            if i == 2 {
                if falling {
                    btn3_down_at = Some(Instant::now());
                    btn3_handled = false;
                    continue;
                }
                // Threshold-fired holds, checked while the button is down: an
                // in-grid hold drops a grid row at the long threshold; a
                // run-view hold opens the grid at the grid threshold.
                if pressed && !btn3_handled {
                    if let Some(t) = btn3_down_at {
                        let held_for = Instant::now().saturating_duration_since(t);
                        if let Some(g) = grid.as_mut() {
                            if held_for >= BTN3_LONG_PRESS {
                                let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                                g.row_down(mask);
                                info!("button: grid cursor -> {}", g.cursor());
                                grid_tx.send(Some(g.cursor()));
                                interaction_tx.send(Instant::now().as_secs() as u32);
                                btn3_handled = true;
                            }
                        } else if held_for >= BTN3_GRID_HOLD {
                            let snap = record_rx.try_get();
                            let state = snap.map(|s| s.state).unwrap_or(RecordState::Idle);
                            if btn3_action(state, Btn3Press::GridHold) == Btn3Action::OpenGrid {
                                let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
                                let g = PageGrid::open(page, mask);
                                info!("button: BTN3 hold -> page grid at {}", g.cursor());
                                grid_tx.send(Some(g.cursor()));
                                grid = Some(g);
                                interaction_tx.send(Instant::now().as_secs() as u32);
                                btn3_handled = true;
                            }
                        }
                    }
                    continue;
                }
                if !rising {
                    continue;
                }
                let held_for = btn3_down_at
                    .take()
                    .map(|t| Instant::now().saturating_duration_since(t))
                    .unwrap_or(Duration::from_ticks(0));
                if btn3_handled {
                    btn3_handled = false;
                    // The hold already acted; its release only starts the
                    // grid's auto-select clock.
                    if grid.is_some() {
                        grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    }
                    continue;
                }
                let now_s = Instant::now().as_secs() as u32;
                interaction_tx.send(now_s);
                if let Some(g) = grid.as_mut() {
                    // Any unhandled release while the grid is open is a tap —
                    // a longer hold would have row-jumped at its threshold.
                    let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                    g.tap(mask);
                    info!("button: grid cursor -> {}", g.cursor());
                    grid_tx.send(Some(g.cursor()));
                    grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    continue;
                }
                let snap = record_rx.try_get();
                let state = snap.map(|s| s.state).unwrap_or(RecordState::Idle);
                // The host-tested boundaries. A run-view GridHold never
                // reaches here (it threshold-fires above); an idle one does
                // and maps to the re-zero like any idle hold.
                let press = classify_btn3_hold(held_for.as_millis().min(u32::MAX as u64) as u32);
                match btn3_action(state, press) {
                    Btn3Action::PageNext | Btn3Action::PagePrev => {
                        // Same filtered walk as the hardware task above.
                        let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
                        page = if press == Btn3Press::Long {
                            page.prev_in(mask)
                        } else {
                            page.next_in(mask)
                        };
                        info!("button: BTN3 -> page {}", page);
                        page_tx.send(page);
                    }
                    Btn3Action::OpenGrid => {}
                    Btn3Action::CycleGnssMode => {
                        mode = mode.next();
                        info!(
                            "button: BTN3 -> gnss mode {} (fix interval {=u32}s, ~{=u32}h)",
                            mode,
                            mode.fix_interval_s(),
                            mode.battery_est_h()
                        );
                        mode_tx.send(mode);
                        // Persist so the choice survives reboot / brown-out
                        // (no-ops under the sim, which has no NVMC).
                        store.lock().await.persist_gnss_mode(mode).await;
                    }
                    Btn3Action::QnhRezero => {
                        info!("button: BTN3 long -> qnh re-zero requested");
                        let _ = state::QNH_REZERO_REQ.try_send(());
                    }
                }
                continue;
            }

            // BTN1 while the grid is open mirrors BTN3's in-grid timing —
            // backward cursor: tap = one cell back, hold = one row up — so it
            // classifies on release / at the hold threshold instead of the
            // falling edge its normal dispatch uses.
            if i == 0 && (grid.is_some() || btn1_down_at.is_some()) {
                if falling {
                    btn1_down_at = Some(Instant::now());
                    btn1_handled = false;
                    continue;
                }
                if pressed && !btn1_handled {
                    if let (Some(t), Some(g)) = (btn1_down_at, grid.as_mut()) {
                        if Instant::now().saturating_duration_since(t) >= BTN3_LONG_PRESS {
                            let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                            g.row_up(mask);
                            info!("button: grid cursor -> {}", g.cursor());
                            grid_tx.send(Some(g.cursor()));
                            interaction_tx.send(Instant::now().as_secs() as u32);
                            btn1_handled = true;
                        }
                    }
                    continue;
                }
                if !rising {
                    continue;
                }
                btn1_down_at = None;
                let was_handled = btn1_handled;
                btn1_handled = false;
                if was_handled {
                    if grid.is_some() {
                        grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    }
                    continue;
                }
                if let Some(g) = grid.as_mut() {
                    let now_s = Instant::now().as_secs() as u32;
                    interaction_tx.send(now_s);
                    let mask = record_rx.try_get().map_or(u32::MAX, |s| s.pages_mask);
                    g.back(mask);
                    info!("button: grid cursor -> {}", g.cursor());
                    grid_tx.send(Some(g.cursor()));
                    grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                }
                continue;
            }

            if !falling {
                continue;
            }
            // A press is an interaction whether or not it issues a command —
            // it wakes the face's animation window, same as the hardware task.
            let now_s = Instant::now().as_secs() as u32;
            interaction_tx.send(now_s);
            let button = match i {
                0 => Button::Primary,
                1 => Button::Stop,
                _ => Button::Lap,
            };
            // Grid open: BTN4 confirms the jump, BTN2 cancels — all swallowed,
            // none reaches the recorder. BTN1 never lands here while the grid
            // is open (the backward-cursor block above owns it).
            if grid.is_some() {
                match grid_press(button) {
                    GridPress::CursorBack => {}
                    GridPress::Select => {
                        if let Some(g) = grid.take() {
                            page = g.cursor();
                            info!("button: grid select -> page {}", page);
                            page_tx.send(page);
                        }
                    }
                    GridPress::Cancel => {
                        info!("button: grid cancelled");
                        grid = None;
                    }
                }
                grid_deadline = None;
                grid_tx.send(None);
                continue;
            }
            let snap = record_rx.try_get();
            let state = snap.map(|s| s.state).unwrap_or(RecordState::Idle);
            // Same finished-run page-back as the hardware task above.
            if button == Button::Lap && btn4_action(state) == Some(Btn4Action::PageBack) {
                let mask = snap.map_or(u32::MAX, |s| s.pages_mask);
                page = page.prev_in(mask);
                info!("button: BTN4 -> page {} (back)", page);
                page_tx.send(page);
                continue;
            }
            if dispatch(button, state, now_s, &mut stop_guard).await == Some(RecordCommand::Reset) {
                // Dismissed home: the next run opens on the Dashboard, not on
                // whatever page the last one was parked on.
                page = Page::default();
                page_tx.send(page);
            }
        }
    }
}
