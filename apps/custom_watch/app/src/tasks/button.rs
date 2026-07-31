//! Button task — turns the watch's control buttons into `RecordCommand`s.
//!
//! Thin glue by design: the press → command decision lives in the host-tested
//! `watch_core::button` (which command a button issues in a given run state);
//! this task owns only the hardware that module can't reach — edge detection
//! and contact debounce.
//!
//! Mapping (decisions §350 + §351; see `watch_core::button` /
//! `watch_core::settings_menu`):
//!   BTN1 (upper-right) — start / pause / resume toggle; dismiss from FIN;
//!          confirm the page-grid jump (the START-confirms idiom); settings
//!          menu: edit right (on / increase / fire)
//!   BTN2 (mid-left)    — stop (two-press guard); cancel the grid; settings
//!          menu: cursor up (its §81 slot is literally UP); idle: open the
//!          timer modal (§375); timer: one preset rung longer
//!   BTN3 (lower-left)  — tap pages LEFT in any run view; hold opens the page
//!          grid; idle: tap cycles the GNSS mode, hold requests the QNH
//!          re-zero; settings menu: cursor down (the DOWN slot)
//!   BTN4 (lower-right) — tap pages RIGHT in any run view; hold opens the page
//!          grid; idle: toggles home / diagnostics whatever the duration;
//!          settings menu: exit (the BACK slot)
//!   BTN5 (upper-left)  — manual lap, held past PAGE_HOLD_MS marks a waypoint
//!          (§357); idle: open the settings menu; settings menu: edit left
//!          (off / decrease); swallowed inside the grid
//! The paging pair is spatially congruent with the horizontal page ring (the
//! top-edge position thumb): left key walks left, right key walks right, and
//! the grid cursor moves the same directions. The buttons are active-LOW
//! (idle high, press pulls low), so a press is a falling edge and a held
//! press reads `is_low()`. BTN3/BTN4 carry no recording command — their
//! actions are the host-tested `watch_core::input_flow::paging_action`, which
//! also freezes the GNSS mode and the altitude reference for a run's
//! duration.

use defmt::*;
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select, select4, Either, Either4};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Instant, Timer};
#[cfg(feature = "sim-buttons")]
use watch_core::button::classify_page_hold;
use watch_core::button::{
    btn2_action, command_for, grid_press, lap_press_command, timer_key, Btn2Action, Button,
    GridPress, PageBtnPress, RecordCommand, StopGuard, StopPress, PAGE_HOLD_MS,
    STOP_CONFIRM_WINDOW_S,
};
use watch_core::face::IdleView;
use watch_core::gnss_mode::GnssMode;
#[cfg(feature = "sim-buttons")]
use watch_core::input_flow::{edge, Edge};
use watch_core::input_flow::{
    grid_cursor_key, grid_cursor_op, idle_view_toggled, landing_after, paged, paging_action,
    timer_paging_key, PagingAction, PagingKey,
};
use watch_core::page::Page;
use watch_core::page_grid::{PageGrid, GRID_AUTOSELECT_S};
use watch_core::profiles::{self, ActivityProfile};
use watch_core::record::RecordState;
use watch_core::settings::WatchSettings;
use watch_core::settings_menu::{self, Menu, MenuEdit, ValueDir, MENU_TIMEOUT_S};
use watch_core::timers::{self, TimerKey, TimerPress, TIMER_MENU_TIMEOUT_S};
use watch_core::ui_frame::{pages_mask, record_state};

use crate::run_flash::SharedStore;
use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
#[cfg(not(feature = "sim-buttons"))]
const DEBOUNCE: Duration = Duration::from_millis(20);

/// The tap / hold boundary as a `Duration` (`watch_core::button::PAGE_HOLD_MS`
/// owns the number). A paging key released inside it is a tap — page left or
/// right; at the threshold the hold action fires while the button is still
/// down (the grid appearing is its own feedback), so nobody times a release
/// blind. One boundary, no middle tier (decisions §350).
#[cfg(not(feature = "sim-buttons"))]
const PAGE_HOLD: Duration = Duration::from_millis(PAGE_HOLD_MS as u64);

/// The grid's auto-select window as a `Duration` (see
/// `page_grid::GRID_AUTOSELECT_S` — the pure module owns the number).
const GRID_AUTOSELECT: Duration = Duration::from_secs(GRID_AUTOSELECT_S as u64);

/// The settings menu's inactivity auto-close (`settings_menu::MENU_TIMEOUT_S`
/// owns the number) — the menu covers the home clock, so an abandoned one may
/// not stand forever.
const MENU_TIMEOUT: Duration = Duration::from_secs(MENU_TIMEOUT_S as u64);

/// The timer modal's inactivity auto-close (`timers::TIMER_MENU_TIMEOUT_S` owns
/// the number, which derives from the settings menu's) — it covers the home
/// clock for the same reason and closes for the same one. The instrument keeps
/// running; only the view goes away.
const TIMER_TIMEOUT: Duration = Duration::from_secs(TIMER_MENU_TIMEOUT_S as u64);

/// The view/navigation state both task variants thread through the shared
/// action code: the current run page, the grid modal (this task owns its state
/// machine and auto-select deadline; the ui task only renders the published
/// cursor), the GNSS mode, and which idle face is up.
struct NavState {
    page: Page,
    grid: Option<PageGrid>,
    grid_deadline: Option<Instant>,
    menu: Option<Menu>,
    menu_deadline: Option<Instant>,
    /// The runner's timer (§375). Held whether or not its modal is open — the
    /// instrument outlives the view, and outlives runs.
    timer: timers::Timer,
    timer_open: bool,
    timer_deadline: Option<Instant>,
    mode: GnssMode,
    profile: Option<ActivityProfile>,
    idle_view: IdleView,
}

impl NavState {
    fn new(initial_mode: GnssMode, initial_profile: Option<ActivityProfile>) -> Self {
        Self {
            page: Page::default(),
            grid: None,
            grid_deadline: None,
            menu: None,
            menu_deadline: None,
            timer: timers::Timer::new(),
            timer_open: false,
            timer_deadline: None,
            mode: initial_mode,
            profile: initial_profile,
            idle_view: IdleView::Home,
        }
    }

    /// Commit the grid's cursor and close the modal — the jump.
    fn grid_commit(&mut self, why: &str) {
        if let Some(g) = self.grid.take() {
            self.page = g.cursor();
            info!("button: grid {=str} -> page {}", why, self.page);
            state::PAGE.sender().send(self.page);
        }
        self.grid_deadline = None;
        state::PAGE_GRID.sender().send(None);
    }

    /// Open the idle settings menu (§351) — BTN5's meaning while the lap is
    /// dead, the same dead-key repurposing as §290/§291.
    fn open_menu(&mut self) {
        let m = Menu::new();
        info!("button: BTN5 -> settings menu");
        state::SETTINGS_MENU.sender().send(Some(m.cursor()));
        self.menu = Some(m);
        self.menu_deadline = Some(Instant::now() + MENU_TIMEOUT);
    }

    fn close_menu(&mut self, why: &str) {
        if self.menu.take().is_some() {
            info!("button: settings menu closed ({=str})", why);
            state::SETTINGS_MENU.sender().send(None);
        }
        self.menu_deadline = None;
    }

    /// Open the timer modal (§375) — BTN2's meaning while the stop has no run
    /// to end, the last dead key the §350 grammar had.
    fn open_timer(&mut self) {
        info!("button: BTN2 -> timer");
        self.timer_open = true;
        state::TIMER_MENU.sender().send(true);
        self.timer_deadline = Some(Instant::now() + TIMER_TIMEOUT);
    }

    fn close_timer(&mut self, why: &str) {
        if self.timer_open {
            info!("button: timer closed ({=str})", why);
            self.timer_open = false;
            state::TIMER_MENU.sender().send(false);
        }
        self.timer_deadline = None;
    }

    /// One press inside the modal. Every key is consumed here, so none of them
    /// reaches the recorder.
    fn timer_press(&mut self, key: TimerKey, now_s: u32) {
        match timers::press(&mut self.timer, key, now_s) {
            TimerPress::Exit => self.close_timer("btn4"),
            TimerPress::Changed => {
                state::TIMER.sender().send(self.timer);
                self.timer_deadline = Some(Instant::now() + TIMER_TIMEOUT);
            }
            // A clamped ladder end still defers the close: the runner is
            // present and pressing, they simply asked for a state they are in.
            TimerPress::Nothing => self.timer_deadline = Some(Instant::now() + TIMER_TIMEOUT),
        }
    }

    /// Cursor up — BTN2, the mid-left §81 UP slot, physically above BTN3.
    fn menu_up(&mut self) {
        if let Some(m) = self.menu.as_mut() {
            m.up();
            info!("button: menu cursor -> {}", m.item());
            state::SETTINGS_MENU.sender().send(Some(m.cursor()));
            self.menu_deadline = Some(Instant::now() + MENU_TIMEOUT);
        }
    }

    /// Cursor down — BTN3, the lower-left §81 DOWN slot.
    fn menu_down(&mut self) {
        if let Some(m) = self.menu.as_mut() {
            m.down();
            info!("button: menu cursor -> {}", m.item());
            state::SETTINGS_MENU.sender().send(Some(m.cursor()));
            self.menu_deadline = Some(Instant::now() + MENU_TIMEOUT);
        }
    }
}

/// Set the GNSS recording mode and persist the choice — one implementation
/// for both routes to the same state (the idle BTN3 quick cycle and the
/// menu's directional ladder), so they cannot diverge.
async fn set_gnss_mode(nav: &mut NavState, store: &'static SharedStore, mode: GnssMode) {
    nav.mode = mode;
    info!(
        "button: gnss mode -> {} (fix interval {=u32}s, ~{=u32}h)",
        nav.mode,
        nav.mode.fix_interval_s(),
        nav.mode.battery_est_h()
    );
    state::GNSS_MODE.sender().send(nav.mode);
    // Persist so the choice survives reboot / brown-out. Best-effort / L4: a
    // flash error only warns; the mode switch is never blocked on flash (and
    // it no-ops under a sim with no NVMC).
    store.lock().await.persist_gnss_mode(nav.mode).await;
}

/// An edit press (BTN5 = left / BTN1 = right) on the menu's cursor row.
/// `hide_now` is the snapshot's current hide-empty value, so the pure
/// `settings_menu::edit` resolves the press against exactly the state the
/// runner just read — a clamped ladder end or an idempotent on/on comes back
/// `Nothing` and only refreshes the timeout.
async fn menu_edit(nav: &mut NavState, dir: ValueDir, hide_now: bool, store: &'static SharedStore) {
    let Some(item) = nav.menu.as_ref().map(|m| m.item()) else {
        return;
    };
    match settings_menu::edit(item, dir, nav.mode, hide_now, nav.profile) {
        MenuEdit::SetGnssMode(mode) => set_gnss_mode(nav, store, mode).await,
        MenuEdit::SetProfile(p) => {
            // A profile is a macro over the existing knobs (§353): the pages
            // preset rides the same settings channel a phone push takes, the
            // mode rides the shared `set_gnss_mode` path (which persists it),
            // and the selection itself persists so a reboot re-applies the
            // preset. Last-writer-wins on every knob, exactly like §351.
            let preset = profiles::preset(p);
            info!("button: menu -> profile {} applied", p);
            let s = WatchSettings {
                pages: Some(preset.pages),
                ..Default::default()
            };
            if state::SETTINGS.try_send(s).is_err() {
                warn!("button: settings queue full — profile pages dropped");
            }
            if preset.gnss_mode != nav.mode {
                set_gnss_mode(nav, store, preset.gnss_mode).await;
            }
            nav.profile = Some(p);
            state::PROFILE.sender().send(nav.profile);
            store.lock().await.persist_profile(p).await;
        }
        MenuEdit::SetHideEmpty(hide) => {
            info!("button: menu -> hide empty pages {}", hide);
            // The same channel a phone push rides, so the apply path and the
            // §351 persistence rule cannot diverge. try_send: a full queue
            // only drops this edit; the next press retries.
            let s = WatchSettings {
                hide_empty_pages: Some(hide),
                ..Default::default()
            };
            if state::SETTINGS.try_send(s).is_err() {
                warn!("button: settings queue full — hide-empty edit dropped");
            }
        }
        MenuEdit::RequestQnhRezero => {
            info!("button: menu -> qnh re-zero requested");
            let _ = state::QNH_REZERO_REQ.try_send(());
            // The idle face's transient banner answers the request; the menu
            // hands it the screen.
            nav.close_menu("re-zero");
            return;
        }
        MenuEdit::ShowIce => {
            // Same action-row shape as the re-zero: fire, then hand the
            // screen over — here to the §358 card itself, which is the only
            // useful confirmation that the row did anything.
            info!("button: menu -> medical ID");
            nav.close_menu("medical id");
            nav.idle_view = IdleView::Ice;
            state::IDLE_VIEW.sender().send(nav.idle_view);
            return;
        }
        MenuEdit::Nothing => {}
    }
    // A value row stays open — the row re-rendering with the new value is
    // the confirmation.
    nav.menu_deadline = Some(Instant::now() + MENU_TIMEOUT);
}

fn key_label(key: PagingKey) -> &'static str {
    match key {
        PagingKey::Left => "BTN3",
        PagingKey::Right => "BTN4",
    }
}

/// A paging-key press inside the grid: the cursor steps one cell on a tap and
/// jumps a whole row on a hold, in the same direction the key pages.
fn act_grid_cursor(key: PagingKey, held: bool, mask: u64, nav: &mut NavState) {
    if let Some(g) = nav.grid.as_mut() {
        grid_cursor_op(grid_cursor_key(key), held).apply(g, mask);
        info!("button: grid cursor -> {}", g.cursor());
        state::PAGE_GRID.sender().send(Some(g.cursor()));
    }
}

/// A paging-key press outside the grid — the shared dispatch both task
/// variants feed once they've classified the press. Tap actions arrive on the
/// release, hold actions at the threshold (still held); this code doesn't care
/// which.
async fn act_paging(
    key: PagingKey,
    press: PageBtnPress,
    state: RecordState,
    mask: u64,
    nav: &mut NavState,
    store: &'static SharedStore,
) {
    match paging_action(key, state, press) {
        action @ (PagingAction::PageNext | PagingAction::PagePrev) => {
            // Walk the filtered cycle (data-present ∩ curated, from the
            // snapshot); no snapshot means no filter.
            nav.page = paged(nav.page, action, mask);
            info!("button: {=str} -> page {}", key_label(key), nav.page);
            state::PAGE.sender().send(nav.page);
        }
        PagingAction::OpenGrid => {
            let g = PageGrid::open(nav.page, mask);
            info!(
                "button: {=str} hold -> page grid at {}",
                key_label(key),
                g.cursor()
            );
            state::PAGE_GRID.sender().send(Some(g.cursor()));
            nav.grid = Some(g);
        }
        PagingAction::CycleGnssMode => {
            // The quick path keeps its wrap-around cycle; the menu's ladder
            // is clamped — both land in the same shared setter.
            let next = nav.mode.next();
            set_gnss_mode(nav, store, next).await;
        }
        PagingAction::QnhRezero => {
            info!("button: BTN3 hold -> qnh re-zero requested");
            // try_send: a request already pending covers this press too.
            let _ = state::QNH_REZERO_REQ.try_send(());
        }
        PagingAction::ToggleDiagnostics => {
            nav.idle_view = idle_view_toggled(nav.idle_view);
            info!("button: BTN4 -> idle view {}", nav.idle_view);
            state::IDLE_VIEW.sender().send(nav.idle_view);
        }
    }
}

/// A non-paging press (BTN1 / BTN2 / BTN5) while the grid is open: BTN1
/// confirms the jump, BTN2 cancels, BTN5 is swallowed (its press only defers
/// the auto-select) — and none of them reaches the recorder: a navigation
/// modal must never pause, stop-arm, or lap a run.
fn act_grid_press(button: Button, nav: &mut NavState) {
    match grid_press(button) {
        GridPress::Select => nav.grid_commit("select"),
        GridPress::Cancel => {
            info!("button: grid cancelled");
            nav.grid = None;
            nav.grid_deadline = None;
            state::PAGE_GRID.sender().send(None);
        }
        GridPress::Swallow => {
            nav.grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
        }
    }
}

const BOOT_LINE: &str =
    "button: BTN1 start/pause, BTN2 stop (idle: timer), BTN3 page left (hold: grid), BTN4 page right (hold: grid), BTN5 lap (hold: mark waypoint) / idle settings";

#[cfg(not(feature = "sim-buttons"))]
#[embassy_executor::task]
pub async fn run(
    mut btn1: Input<'static>,
    mut btn2: Input<'static>,
    mut btn3: Input<'static>,
    mut btn4: Input<'static>,
    mut btn5: Input<'static>,
    initial: (GnssMode, Option<ActivityProfile>),
    store: &'static SharedStore,
) {
    let mut record_rx = unwrap!(state::RECORD.receiver());
    let interaction_tx = state::INTERACTION.sender();
    // Seed from the mode + profile main restored from flash at boot so the
    // BTN3 cycle and the menu's PROFILE row continue from the persisted
    // choices rather than the defaults.
    let mut nav = NavState::new(initial.0, initial.1);
    let mut stop_guard = StopGuard::new();
    info!("{=str}", BOOT_LINE);
    loop {
        // Wait for whichever button is pressed first (falling edge = press) —
        // or, while the grid is open, for its auto-select deadline: the
        // no-confirm-press close (hold to open, tap to the target, lower the
        // wrist).
        let edges = select(
            select4(
                btn1.wait_for_falling_edge(),
                btn2.wait_for_falling_edge(),
                btn3.wait_for_falling_edge(),
                btn4.wait_for_falling_edge(),
            ),
            btn5.wait_for_falling_edge(),
        );
        let pressed = if let Some(deadline) = nav
            .grid_deadline
            .or(nav.menu_deadline)
            .or(nav.timer_deadline)
        {
            // The three modal deadlines share the slot — the grid only exists
            // in a run view and the two idle modals only on the idle face,
            // where opening either closes the other, so at most one is armed.
            match select(edges, Timer::at(deadline)).await {
                Either::First(e) => e,
                Either::Second(()) => {
                    if nav.grid.is_some() {
                        nav.grid_commit("auto-select");
                    } else if nav.timer_open {
                        nav.close_timer("timeout");
                    } else {
                        nav.close_menu("timeout");
                    }
                    continue;
                }
            }
        } else {
            edges.await
        };

        // The idle modals only exist on the idle face: if a run started under
        // one (sim-autostart is the one path that can), the press that arrives
        // closes it first and then acts on whatever surface is really up.
        if (nav.menu.is_some() || nav.timer_open)
            && record_state(record_rx.try_get().as_ref()) != RecordState::Idle
        {
            nav.close_menu("run started");
            nav.close_timer("run started");
        }

        // The two paging keys share one timing shape: debounce, then a single
        // select leg to the hold threshold. A release inside it is the tap; the
        // timer winning is the hold, whose action fires NOW (still held) — the
        // grid opening / re-zero banner is the feedback — and whose release is
        // then swallowed. Each timer win drops the losing edge future, so a
        // release landing in the re-arm gap is invisible; firing the hold
        // action anyway is correct because the threshold genuinely elapsed.
        let (key, pin): (PagingKey, &mut Input<'static>) = match pressed {
            Either::First(Either4::Third(())) => (PagingKey::Left, &mut btn3),
            Either::First(Either4::Fourth(())) => (PagingKey::Right, &mut btn4),
            other => {
                let button = match other {
                    Either::First(Either4::First(())) => Button::Primary,
                    Either::First(Either4::Second(())) => Button::Stop,
                    _ => Button::Lap,
                };
                // Debounce: let the contacts settle, then confirm the press
                // held. A bounce that has already released by now is dropped.
                Timer::after(DEBOUNCE).await;
                let held = match button {
                    Button::Primary => btn1.is_low(),
                    Button::Stop => btn2.is_low(),
                    Button::Lap => btn5.is_low(),
                };
                if !held {
                    continue;
                }
                // A confirmed press is an interaction, whether or not it maps
                // to a command in the current state — it wakes the face's
                // animation window.
                let now_s = Instant::now().as_secs() as u32;
                interaction_tx.send(now_s);
                if nav.grid.is_some() {
                    act_grid_press(button, &mut nav);
                    continue;
                }
                let snap = record_rx.try_get();
                let state = record_state(snap.as_ref());
                if nav.menu.is_some() {
                    // Menu modal: BTN2 (the UP slot) steps the cursor up,
                    // BTN1/BTN5 are the right/left edit pair — every press
                    // swallowed, none reaches the recorder.
                    let hide = snap.as_ref().map(|s| s.hide_empty_pages).unwrap_or(true);
                    match button {
                        Button::Primary => menu_edit(&mut nav, ValueDir::Right, hide, store).await,
                        Button::Stop => nav.menu_up(),
                        Button::Lap => menu_edit(&mut nav, ValueDir::Left, hide, store).await,
                    }
                    continue;
                }
                if nav.timer_open {
                    // Timer modal: BTN1 start/stop, BTN2 longer, BTN5 reset —
                    // every press swallowed, none reaches the recorder.
                    nav.timer_press(timer_key(button), now_s);
                    continue;
                }
                if button == Button::Lap && state == RecordState::Idle {
                    // The lap is dead while idle, so the press opens the
                    // settings menu (§351) — the same dead-key repurposing
                    // that gave FIN its page-back and idle BTN4 diagnostics.
                    nav.open_menu();
                    continue;
                }
                if button == Button::Stop && btn2_action(state) == Btn2Action::OpenTimer {
                    // The stop has no run to end while idle, so the press opens
                    // the timer (§375) — the last dead key in the grammar.
                    nav.open_timer();
                    continue;
                }
                // BTN5 mid-run has two tiers (§357), timed exactly like the
                // paging keys: one boundary, the hold's action firing AT the
                // threshold while still held, and its release swallowed. The
                // other two buttons resolve on the press itself.
                let press = if button == Button::Lap {
                    match select(Timer::after(PAGE_HOLD), btn5.wait_for_rising_edge()).await {
                        Either::Second(()) => PageBtnPress::Tap,
                        Either::First(()) => PageBtnPress::Hold,
                    }
                } else {
                    PageBtnPress::Tap
                };
                if let Some(landing) = dispatch(button, press, state, now_s, &mut stop_guard)
                    .await
                    .and_then(landing_after)
                {
                    nav.page = landing.page;
                    state::PAGE.sender().send(nav.page);
                    nav.idle_view = landing.idle_view;
                    state::IDLE_VIEW.sender().send(nav.idle_view);
                }
                // Same guard as the paging keys: only wait on a release that
                // has not already happened, or a release landing in the
                // re-arm gap would hang every button behind a whole new press.
                if press == PageBtnPress::Hold && btn5.is_low() {
                    btn5.wait_for_rising_edge().await;
                }
                continue;
            }
        };

        Timer::after(DEBOUNCE).await;
        if !pin.is_low() {
            continue;
        }
        interaction_tx.send(Instant::now().as_secs() as u32);
        if nav.menu.is_some() {
            // Menu modal: BTN3 (the DOWN slot) steps the cursor down on the
            // press itself, BTN4 (the BACK slot) exits — and the release is
            // swallowed so no timing path runs underneath the modal.
            match key {
                PagingKey::Left => nav.menu_down(),
                PagingKey::Right => nav.close_menu("btn4"),
            }
            if pin.is_low() {
                pin.wait_for_rising_edge().await;
            }
            continue;
        }
        if nav.timer_open {
            // Timer modal: BTN3 shortens the preset, BTN4 exits — the same
            // BACK slot the settings menu uses, and the same swallowed release.
            nav.timer_press(timer_paging_key(key), Instant::now().as_secs() as u32);
            if pin.is_low() {
                pin.wait_for_rising_edge().await;
            }
            continue;
        }
        let press = match select(Timer::after(PAGE_HOLD), pin.wait_for_rising_edge()).await {
            Either::Second(()) => PageBtnPress::Tap,
            Either::First(()) => PageBtnPress::Hold,
        };
        let snap = record_rx.try_get();
        let mask = pages_mask(snap.as_ref());
        if nav.grid.is_some() {
            act_grid_cursor(key, press == PageBtnPress::Hold, mask, &mut nav);
        } else {
            let state = record_state(snap.as_ref());
            act_paging(key, press, state, mask, &mut nav, store).await;
        }
        // Swallow the hold's release (only while actually still held — the
        // timer arm dropped the edge future, so a release landing in the
        // re-arm gap would make a fresh wait_for_rising_edge wait for a whole
        // NEW press, hanging every button).
        if press == PageBtnPress::Hold && pin.is_low() {
            pin.wait_for_rising_edge().await;
        }
        // The auto-select clock runs from the release, so a held button can't
        // burn the window before the runner lets go.
        if nav.grid.is_some() {
            nav.grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
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
///
/// `press` is the tier BTN5 was held for (§357) — the only non-paging key with
/// two of them. BTN1 and BTN2 mean the same thing at any duration and are
/// always fed [`PageBtnPress::Tap`]: an idle gesture must never change meaning
/// mid-press, and a stop that only fires on a release nobody timed would be
/// worse than the double-press guard it already carries.
async fn dispatch(
    button: Button,
    press: PageBtnPress,
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
        Button::Lap => send_cmd(button, lap_press_command(state, press)).await,
        Button::Primary => send_cmd(button, command_for(button, state)).await,
    }
}

async fn send_cmd(button: Button, cmd: Option<RecordCommand>) -> Option<RecordCommand> {
    if let Some(cmd) = cmd {
        info!("button: {} -> {}", button, cmd);
        state::RECORD_CMD.send(cmd).await;
    }
    cmd
}

/// Milliseconds a button has been down, in the unit the host-tested press
/// classifiers speak.
#[cfg(feature = "sim-buttons")]
fn held_ms(since: Instant) -> u32 {
    Instant::now()
        .saturating_duration_since(since)
        .as_millis()
        .min(u32::MAX as u64) as u32
}

/// Sim-only button task — polls the button pin levels instead of waiting on
/// a hardware falling edge.
///
/// The hardware `run` above waits on `wait_for_falling_edge`, which the
/// nRF52840 drives from the GPIO SENSE/DETECT + PORT-event mechanism. Renode's
/// nRF52840 GPIO model implements the IN register (pin level) but not
/// SENSE/DETECT, so that edge future never wakes under the sim. This variant
/// samples the pin levels on a short timer and detects the edges in software,
/// so the `btn1`..`btn5` monitor macros in `sim/watch.resc` (and the bezel
/// clicks in the --gui window) drive the SAME `command_for` / `paging_action`
/// logic the real task uses. Renode has no contact bounce, so a clean edge
/// needs no debounce confirm.
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
    btn5: Input<'static>,
    initial: (GnssMode, Option<ActivityProfile>),
    store: &'static SharedStore,
) {
    /// Poll cadence. The `click` macro holds a press ~0.3 s, so any interval
    /// well under that catches the edge; short enough to feel instant.
    const POLL: Duration = Duration::from_millis(10);

    let mut record_rx = unwrap!(state::RECORD.receiver());
    let interaction_tx = state::INTERACTION.sender();
    let mut nav = NavState::new(initial.0, initial.1);
    let mut stop_guard = StopGuard::new();

    // Active-low: pressed pulls the line low. Track the previous level per
    // button so a release→press transition (high→low) fires exactly once.
    let btns = [btn1, btn2, btn3, btn4, btn5];
    let mut prev = [
        btns[0].is_low(),
        btns[1].is_low(),
        btns[2].is_low(),
        btns[3].is_low(),
        btns[4].is_low(),
    ];
    // The paging keys time their hold from the press; the hold action fires at
    // the threshold while still held — mirroring the hardware task — and marks
    // the press handled so its release is inert. Index 0 = BTN3, 1 = BTN4.
    let mut pg_down_at: [Option<Instant>; 2] = [None, None];
    let mut pg_handled: [bool; 2] = [false, false];
    // BTN5 times its own hold the same way, for the §357 mark tier — only
    // while a run is under way; every other BTN5 meaning (the settings menu,
    // the grid swallow, a menu edit) still resolves on the press itself.
    let mut lap_down_at: Option<Instant> = None;
    let mut lap_handled = false;
    info!("{=str}", BOOT_LINE);

    loop {
        Timer::after(POLL).await;
        // The grid's auto-select deadline — the no-confirm-press close.
        if nav.grid.is_some() && nav.grid_deadline.is_some_and(|dl| Instant::now() >= dl) {
            nav.grid_commit("auto-select");
        }
        // The menu's inactivity auto-close — it covers the home clock, so an
        // abandoned menu hands the screen back on its own.
        if nav.menu.is_some() && nav.menu_deadline.is_some_and(|dl| Instant::now() >= dl) {
            nav.close_menu("timeout");
        }
        if nav.timer_open && nav.timer_deadline.is_some_and(|dl| Instant::now() >= dl) {
            nav.close_timer("timeout");
        }
        for (i, b) in btns.iter().enumerate() {
            let pressed = b.is_low();
            let was = prev[i];
            prev[i] = pressed;
            let transition = edge(was, pressed);
            let falling = transition == Some(Edge::Press);
            let rising = transition == Some(Edge::Release);

            // BTN3 (i == 2) and BTN4 (i == 3): the paging pair.
            if i == 2 || i == 3 {
                let k = i - 2;
                let key = if k == 0 {
                    PagingKey::Left
                } else {
                    PagingKey::Right
                };
                if falling {
                    if nav.timer_open {
                        if record_state(record_rx.try_get().as_ref()) != RecordState::Idle {
                            nav.close_timer("run started");
                        } else {
                            interaction_tx.send(Instant::now().as_secs() as u32);
                            nav.timer_press(timer_paging_key(key), Instant::now().as_secs() as u32);
                            pg_down_at[k] = Some(Instant::now());
                            pg_handled[k] = true;
                            continue;
                        }
                    }
                    if nav.menu.is_some() {
                        // Menu modal: BTN3 (the DOWN slot) steps the cursor
                        // down on the press itself, BTN4 (the BACK slot)
                        // exits (mirroring the hardware task) — unless a run
                        // started under the menu, in which case the press
                        // closes it and falls through to normal handling.
                        if record_state(record_rx.try_get().as_ref()) != RecordState::Idle {
                            nav.close_menu("run started");
                        } else {
                            interaction_tx.send(Instant::now().as_secs() as u32);
                            match key {
                                PagingKey::Left => nav.menu_down(),
                                PagingKey::Right => nav.close_menu("btn4"),
                            }
                            pg_down_at[k] = Some(Instant::now());
                            pg_handled[k] = true;
                            continue;
                        }
                    }
                    pg_down_at[k] = Some(Instant::now());
                    pg_handled[k] = false;
                    continue;
                }
                // The hold action fires at the threshold, while the button is
                // still down — the grid opening / re-zero banner is the
                // feedback, so nobody times a release blind.
                if pressed && !pg_handled[k] {
                    let held = pg_down_at[k].map(held_ms).unwrap_or(0);
                    if held >= PAGE_HOLD_MS {
                        interaction_tx.send(Instant::now().as_secs() as u32);
                        let snap = record_rx.try_get();
                        let mask = pages_mask(snap.as_ref());
                        if nav.grid.is_some() {
                            act_grid_cursor(key, true, mask, &mut nav);
                        } else {
                            let state = record_state(snap.as_ref());
                            act_paging(key, PageBtnPress::Hold, state, mask, &mut nav, store).await;
                        }
                        pg_handled[k] = true;
                    }
                    continue;
                }
                if !rising {
                    continue;
                }
                let held_for_ms = pg_down_at[k].take().map(held_ms).unwrap_or(0);
                if pg_handled[k] {
                    pg_handled[k] = false;
                    // The press already acted (a threshold-fired hold, or a
                    // menu cursor step on the press) — its release only
                    // starts the grid's auto-select clock.
                    if nav.grid.is_some() {
                        nav.grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    }
                    continue;
                }
                interaction_tx.send(Instant::now().as_secs() as u32);
                // Classify by measured duration: normally a tap, but a release
                // that crossed the threshold between polls still earns its
                // hold action here rather than being silently demoted.
                let press = classify_page_hold(held_for_ms);
                let snap = record_rx.try_get();
                let mask = pages_mask(snap.as_ref());
                if nav.grid.is_some() {
                    act_grid_cursor(key, press == PageBtnPress::Hold, mask, &mut nav);
                    nav.grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                } else {
                    let state = record_state(snap.as_ref());
                    act_paging(key, press, state, mask, &mut nav, store).await;
                    if nav.grid.is_some() {
                        nav.grid_deadline = Some(Instant::now() + GRID_AUTOSELECT);
                    }
                }
                continue;
            }

            // BTN5's mark tier (i == 4): the hold fires at the threshold while
            // still down, mirroring the paging keys and the hardware task, and
            // marks the press handled so its release is inert. The timer is
            // armed ONLY by the falling-edge path below, once it has decided
            // the press really is a run-view lap — so a press the grid or the
            // menu swallowed leaves nothing armed, and its release cannot
            // smuggle a lap through here.
            if i == 4 && !falling && lap_down_at.is_some() {
                if pressed
                    && !lap_handled
                    && lap_down_at.is_some_and(|at| held_ms(at) >= PAGE_HOLD_MS)
                {
                    let now_s = Instant::now().as_secs() as u32;
                    interaction_tx.send(now_s);
                    let state = record_state(record_rx.try_get().as_ref());
                    dispatch(
                        Button::Lap,
                        PageBtnPress::Hold,
                        state,
                        now_s,
                        &mut stop_guard,
                    )
                    .await;
                    lap_handled = true;
                    continue;
                }
                if rising {
                    let held_for_ms = lap_down_at.take().map(held_ms).unwrap_or(0);
                    if lap_handled {
                        lap_handled = false;
                        continue;
                    }
                    // A release that crossed the threshold between polls still
                    // earns its hold action rather than being demoted to a tap.
                    let now_s = Instant::now().as_secs() as u32;
                    let state = record_state(record_rx.try_get().as_ref());
                    dispatch(
                        Button::Lap,
                        classify_page_hold(held_for_ms),
                        state,
                        now_s,
                        &mut stop_guard,
                    )
                    .await;
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
            if nav.grid.is_some() {
                act_grid_press(button, &mut nav);
                continue;
            }
            let snap = record_rx.try_get();
            let state = record_state(snap.as_ref());
            if nav.menu.is_some() {
                if state != RecordState::Idle {
                    // A run started under the menu (sim-autostart) — close it
                    // and let the press act on the surface that is really up.
                    nav.close_menu("run started");
                } else {
                    // Menu modal: BTN2 (the UP slot) steps the cursor up,
                    // BTN1/BTN5 are the right/left edit pair — every press
                    // swallowed, none reaches the recorder.
                    let hide = snap.as_ref().map(|s| s.hide_empty_pages).unwrap_or(true);
                    match button {
                        Button::Primary => menu_edit(&mut nav, ValueDir::Right, hide, store).await,
                        Button::Stop => nav.menu_up(),
                        Button::Lap => menu_edit(&mut nav, ValueDir::Left, hide, store).await,
                    }
                    continue;
                }
            }
            if nav.timer_open {
                if state != RecordState::Idle {
                    nav.close_timer("run started");
                } else {
                    // Timer modal: BTN1 start/stop, BTN2 longer, BTN5 reset —
                    // every press swallowed, none reaches the recorder.
                    nav.timer_press(timer_key(button), now_s);
                    continue;
                }
            }
            if button == Button::Lap && state == RecordState::Idle {
                // The lap is dead while idle, so the press opens the settings
                // menu (§351) — the same dead-key repurposing that gave FIN
                // its page-back and idle BTN4 diagnostics.
                nav.open_menu();
                continue;
            }
            if button == Button::Stop && btn2_action(state) == Btn2Action::OpenTimer {
                // The stop has no run to end while idle, so the press opens the
                // timer (§375) — the last dead key in the grammar.
                nav.open_timer();
                continue;
            }
            if button == Button::Lap {
                // A run-view BTN5: hand the press to the hold timer above
                // rather than acting now, so the tier is decided by how long
                // it is held (§357).
                lap_down_at = Some(Instant::now());
                lap_handled = false;
                continue;
            }
            if let Some(landing) =
                dispatch(button, PageBtnPress::Tap, state, now_s, &mut stop_guard)
                    .await
                    .and_then(landing_after)
            {
                nav.page = landing.page;
                state::PAGE.sender().send(nav.page);
                nav.idle_view = landing.idle_view;
                state::IDLE_VIEW.sender().send(nav.idle_view);
            }
        }
    }
}
