//! Depth of the phone→watch settings queue the `app/` `record` task drains,
//! and the reason there is a queue there at all.
//!
//! [`crate::settings`] owns the wire format, [`crate::settings_frame`] where one
//! frame ends and the next begins, and [`crate::settings_apply`] which sink each
//! present field feeds. What is left is the seam between the transport that
//! decodes a frame (the BLE characteristic write, or the sim's phone-link pipe)
//! and the task that applies it — and that seam has to be a FIFO, not a
//! latest-value slot.
//!
//! A `SET1` frame is a **delta**: every field carries a presence bit precisely
//! so the phone can push a new max HR without disturbing the eight settings it
//! did not mention. Deltas do not coalesce. A single-value holder keeps only
//! the newest, so a phone that pushes max HR and then a page mask back-to-back
//! loses the max HR outright — the frame decoded, its CRC checked, its fan-out
//! routed, and the value still never reached the recorder. The `record` task
//! only looks between its own wakes, and in the Expedition GNSS mode that
//! window is up to 60 s, so the two pushes need not be close together to
//! collide. Same defect shape as the `run_chunk` request queue
//! ([`crate::ble_sync::CHUNK_QUEUE_DEPTH`]), and the same fix.
//!
//! Merging successive frames into one cumulative latest value would be the
//! wrong fix: it re-applies every accumulated field on every push, which is
//! exactly the delta semantics the presence bits exist to provide.
//!
//! A FIFO alone only makes the seam lossless, not prompt. The `record` task
//! drains opportunistically at the top of its loop, so with the queue and
//! nothing else a pushed frame still waits for an unrelated wake — a GNSS fix,
//! a button press, or a run-active tick. Indoors, before a treadmill session,
//! there is none of those and the wait is unbounded: a new max HR pushed from
//! the phone takes effect when the runner happens to press a button. So the
//! queue is also a **wake source**, as a fourth `select` arm on
//! `ready_to_receive()`.
//!
//! `ready_to_receive()` rather than `receive()` deliberately: it reports that a
//! frame is waiting without taking it, which leaves the top-of-loop drain the
//! sole consumer. That is what keeps one FIFO order — a woken frame goes
//! through the same drain, behind whatever the drain already holds — and it is
//! why the arm can neither double-apply a frame the drain took nor skip one
//! taken on another arm's wake. The arm sits last so it can never pre-empt a
//! fix or a command, and the drain still runs before the loop's `match event`,
//! so a frame that arrived alongside a `Start` lands before that command
//! reaches the recorder.
//!
//! It costs nothing at idle. The arm registers the task's waker and parks; the
//! only thing that fires it is a publisher's `try_send`. There is no timer and
//! no poll, which is the same discipline as [`crate::elevation::should_publish`]
//! and [`crate::gnss_signal::should_publish`] — shortening the tick or adding a
//! poll interval would have re-introduced exactly the free-running waker the
//! rest of this work removes.

/// Depth of the settings-frame queue `app/src/state.rs` declares and the
/// `record` task drains.
///
/// Four, matching the neighbouring `RECORD_CMD` command queue: the frames are
/// operator-paced pushes from one phone, not a pipeline, so a handful of
/// buffered deltas covers a burst of "change this, and this, and this" from a
/// settings screen while the task is between wakes. Overflow past that is
/// refused and logged rather than silently overwriting a queued frame — losing
/// the newest push visibly beats losing an older one invisibly, which is the
/// whole defect this depth exists to close.
pub const SETTINGS_QUEUE_DEPTH: usize = 4;

#[cfg(test)]
mod tests {
    use super::*;
    use core::future::Future;
    use core::pin::pin;
    use core::sync::atomic::{AtomicUsize, Ordering};
    use core::task::{Context, Poll, Waker};
    use std::sync::Arc;
    use std::task::Wake;

    use embassy_futures::select::{select, select3, select4, Either3, Either4};
    use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
    use embassy_sync::channel::Channel;
    use embassy_sync::watch::Watch;
    use heapless::Vec;

    use crate::button::RecordCommand;
    use crate::fix::Fix;
    use crate::settings::WatchSettings;
    use crate::settings_apply::{plan_apply, EffectKind, SettingsEffect, MAX_SETTINGS_EFFECTS};

    /// The queue the record task actually drains: `app/src/state.rs` declares
    /// this exact type from this exact constant, so what these tests exercise is
    /// the transport, not a stand-in for it.
    type SettingsQueue = Channel<CriticalSectionRawMutex, WatchSettings, SETTINGS_QUEUE_DEPTH>;

    /// The single-latest-value slot the queue replaced, at the width it was
    /// declared with.
    type SettingsSlot = Watch<CriticalSectionRawMutex, Option<WatchSettings>, 1>;

    /// The other two seams the record loop's wait selects over, at the widths
    /// `app/src/state.rs` declares them.
    type CmdQueue = Channel<CriticalSectionRawMutex, RecordCommand, 4>;
    type FixWatch = Watch<CriticalSectionRawMutex, Fix, 5>;

    fn max_hr(bpm: u16) -> WatchSettings {
        WatchSettings {
            max_hr: Some(bpm),
            ..WatchSettings::default()
        }
    }

    fn page_mask(mask: u32) -> WatchSettings {
        WatchSettings {
            pages: Some(mask),
            ..WatchSettings::default()
        }
    }

    /// Every effect a drain applies, in the order the record task's loop would
    /// execute them. Capacity is the worst case: a full queue of fully-populated
    /// frames.
    type AppliedKinds = Vec<EffectKind, { SETTINGS_QUEUE_DEPTH * MAX_SETTINGS_EFFECTS }>;

    fn drain(queue: &SettingsQueue) -> AppliedKinds {
        let mut applied = AppliedKinds::new();
        while let Ok(s) = queue.try_receive() {
            for effect in plan_apply(&s) {
                applied
                    .push(effect.kind())
                    .expect("a drain fits its own bound");
            }
        }
        applied
    }

    #[test]
    fn the_settings_queue_is_four_deep() {
        assert_eq!(SETTINGS_QUEUE_DEPTH, 4);
    }

    #[test]
    fn two_pushes_between_drains_are_both_delivered_in_order() {
        let queue: SettingsQueue = Channel::new();
        queue.try_send(max_hr(185)).expect("within depth");
        queue.try_send(page_mask(0b1010)).expect("within depth");

        assert_eq!(queue.try_receive().expect("queued"), max_hr(185));
        assert_eq!(queue.try_receive().expect("queued"), page_mask(0b1010));
        assert!(queue.try_receive().is_err(), "and nothing else was held");
    }

    #[test]
    fn a_latest_value_slot_loses_the_earlier_push_and_the_queue_does_not() {
        // The defect, stated next to its fix. Both pushes land between two
        // record-task wakes, which in the Expedition GNSS mode is a window of up
        // to 60 s.
        let slot: SettingsSlot = Watch::new();
        let mut slot_rx = slot.receiver().expect("the sole receiver");
        let slot_tx = slot.sender();
        slot_tx.send(Some(max_hr(185)));
        slot_tx.send(Some(page_mask(0b1010)));
        assert_eq!(slot_rx.try_changed(), Some(Some(page_mask(0b1010))));
        assert_eq!(
            slot_rx.try_changed(),
            None,
            "the max-HR push vanished without a trace"
        );

        let queue: SettingsQueue = Channel::new();
        queue.try_send(max_hr(185)).expect("within depth");
        queue.try_send(page_mask(0b1010)).expect("within depth");
        assert_eq!(
            drain(&queue).as_slice(),
            [EffectKind::MaxHr, EffectKind::PagesEnabled],
            "both deltas reach their sinks"
        );
    }

    #[test]
    fn a_drain_of_n_frames_applies_n_plans() {
        // The queue is only half the path: what the fix owes is that every
        // queued frame's fields reach their sinks, so the drain is composed with
        // the fan-out rather than asserted about on its own. Values, not merely
        // the count — a frame applied out of order leaves the recorder on the
        // wrong max HR, and the last one written must be the last one applied.
        let queue: SettingsQueue = Channel::new();
        for bpm in 180..180 + SETTINGS_QUEUE_DEPTH as u16 {
            queue.try_send(max_hr(bpm)).expect("within depth");
        }
        let mut applied = Vec::<SettingsEffect, SETTINGS_QUEUE_DEPTH>::new();
        while let Ok(s) = queue.try_receive() {
            for effect in plan_apply(&s) {
                applied.push(effect).expect("one effect per frame");
            }
        }
        assert_eq!(applied.len(), SETTINGS_QUEUE_DEPTH, "one plan per frame");
        assert_eq!(
            applied.as_slice(),
            [
                SettingsEffect::MaxHr(180),
                SettingsEffect::MaxHr(181),
                SettingsEffect::MaxHr(182),
                SettingsEffect::MaxHr(183),
            ]
        );
    }

    #[test]
    fn the_settings_queue_holds_exactly_settings_queue_depth_frames() {
        let queue: SettingsQueue = Channel::new();
        for bpm in 180..180 + SETTINGS_QUEUE_DEPTH as u16 {
            queue.try_send(max_hr(bpm)).expect("within depth");
        }
        assert!(
            queue.try_send(max_hr(200)).is_err(),
            "the depth+1th frame does not fit"
        );

        queue.try_receive().expect("queued");
        queue
            .try_send(max_hr(200))
            .expect("draining one frees one slot");
        assert!(queue.try_send(max_hr(201)).is_err(), "and exactly one");
    }

    #[test]
    fn an_overflowing_push_is_refused_rather_than_displacing_a_queued_one() {
        let queue: SettingsQueue = Channel::new();
        for bpm in 180..180 + SETTINGS_QUEUE_DEPTH as u16 {
            queue.try_send(max_hr(bpm)).expect("within depth");
        }
        assert!(queue.try_send(page_mask(0b1010)).is_err());

        for bpm in 180..180 + SETTINGS_QUEUE_DEPTH as u16 {
            assert_eq!(
                queue.try_receive().expect("queued"),
                max_hr(bpm),
                "the refused push displaced nothing"
            );
        }
        assert!(queue.try_receive().is_err(), "and added nothing");
    }

    /// Counts what the embassy executor would see as "this task is runnable
    /// again". The settings arm's whole power claim is that this only moves
    /// when the phone actually pushes.
    #[derive(Default)]
    struct WakeCount(AtomicUsize);

    impl WakeCount {
        fn get(&self) -> usize {
            self.0.load(Ordering::SeqCst)
        }
    }

    impl Wake for WakeCount {
        fn wake(self: Arc<Self>) {
            self.wake_by_ref();
        }

        fn wake_by_ref(self: &Arc<Self>) {
            self.0.fetch_add(1, Ordering::SeqCst);
        }
    }

    /// The three seams the record loop waits on, plus the wake counter its
    /// waker feeds. Held together because a wait borrows all of them.
    struct Seams {
        settings: SettingsQueue,
        cmds: CmdQueue,
        fixes: FixWatch,
        wakes: Arc<WakeCount>,
    }

    impl Seams {
        fn new() -> Self {
            Self {
                settings: Channel::new(),
                cmds: Channel::new(),
                fixes: Watch::new(),
                wakes: Arc::new(WakeCount::default()),
            }
        }

        fn waker(&self) -> Waker {
            Waker::from(self.wakes.clone())
        }
    }

    fn a_fix() -> Fix {
        Fix {
            lat_deg: 51.5,
            lon_deg: -0.12,
            speed_mps: 3.0,
            course_deg: None,
            sats: 8,
            alt_m: None,
            time_of_day: None,
            uptime_s: 100,
        }
    }

    #[test]
    fn without_the_settings_arm_a_pushed_frame_wakes_nothing() {
        // The defect, stated next to its fix. This is the wait the record loop
        // ran while no run was active: a fix and a command, nothing subscribed
        // to the settings queue. Indoors before a treadmill session there is no
        // fix and no button press, so the frame sits there for as long as the
        // runner leaves it — the queue turned an unbounded-latency loss into an
        // unbounded-latency delay.
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        let mut wait = pin!(select(fix_rx.changed(), s.cmds.receive()));
        assert!(wait.as_mut().poll(&mut cx).is_pending());

        s.settings.try_send(max_hr(185)).expect("within depth");
        assert_eq!(s.wakes.get(), 0, "nothing in the wait is subscribed to it");
        assert!(
            wait.as_mut().poll(&mut cx).is_pending(),
            "and the task stays asleep with the frame unapplied"
        );
    }

    #[test]
    fn a_pushed_frame_wakes_the_record_task_with_no_fix_and_no_command() {
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        let mut wait = pin!(select3(
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        assert!(wait.as_mut().poll(&mut cx).is_pending());
        assert_eq!(s.wakes.get(), 0, "a quiet phone costs no wakes at all");

        s.settings.try_send(max_hr(185)).expect("within depth");
        assert_eq!(s.wakes.get(), 1, "the push itself is the only wake");

        assert!(
            matches!(wait.as_mut().poll(&mut cx), Poll::Ready(Either3::Third(()))),
            "the frame must wake the task on its own"
        );
        assert_eq!(
            drain(&s.settings).as_slice(),
            [EffectKind::MaxHr],
            "and the drain applies it without a fix or a button press"
        );
    }

    #[test]
    fn a_run_active_wait_wakes_on_a_pushed_frame_without_waiting_for_the_tick() {
        // The four-arm wait, with the ticker slot standing in as "no tick due
        // yet" — the case the arm exists for, since a settings push must not
        // have to wait out the 1 Hz tick either.
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        let mut wait = pin!(select4(
            core::future::pending::<()>(),
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        assert!(wait.as_mut().poll(&mut cx).is_pending());

        s.settings.try_send(max_hr(185)).expect("within depth");
        assert!(matches!(
            wait.as_mut().poll(&mut cx),
            Poll::Ready(Either4::Fourth(()))
        ));
        assert_eq!(drain(&s.settings).as_slice(), [EffectKind::MaxHr]);
    }

    #[test]
    fn a_frame_arriving_with_a_command_is_applied_before_the_command_runs() {
        // The command arm outranks the settings arm in the select, so what
        // orders these is the drain sitting between the wait and the loop's
        // `match event` — not the select. A frame pushed alongside a Start
        // reaches the recorder's setters before the Start opens the run.
        #[derive(Debug, PartialEq)]
        enum Step {
            Applied(EffectKind),
            Ran(RecordCommand),
        }

        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        s.settings.try_send(max_hr(185)).expect("within depth");
        s.cmds.try_send(RecordCommand::Start).expect("within depth");

        let mut wait = pin!(select3(
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        let Poll::Ready(event) = wait.as_mut().poll(&mut cx) else {
            panic!("both seams hold something");
        };

        let mut log = Vec::<Step, 4>::new();
        for kind in drain(&s.settings) {
            log.push(Step::Applied(kind))
                .expect("one frame, one effect");
        }
        match event {
            Either3::Second(cmd) => log.push(Step::Ran(cmd)).expect("one command"),
            _ => panic!("the command arm outranks the settings arm"),
        }

        assert_eq!(
            log.as_slice(),
            [
                Step::Applied(EffectKind::MaxHr),
                Step::Ran(RecordCommand::Start),
            ]
        );
    }

    #[test]
    fn one_wake_drains_every_queued_frame_in_arrival_order() {
        // The arm only says "something is waiting", so a second push while the
        // task is still asleep cannot take a turn ahead of the first: both go
        // through the one drain, oldest first.
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        let mut wait = pin!(select3(
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        assert!(wait.as_mut().poll(&mut cx).is_pending());

        s.settings.try_send(max_hr(185)).expect("within depth");
        s.settings
            .try_send(page_mask(0b1010))
            .expect("within depth");
        assert_eq!(
            s.wakes.get(),
            1,
            "a burst of pushes costs one wake, not one each"
        );

        assert!(matches!(
            wait.as_mut().poll(&mut cx),
            Poll::Ready(Either3::Third(()))
        ));
        assert_eq!(
            drain(&s.settings).as_slice(),
            [EffectKind::MaxHr, EffectKind::PagesEnabled]
        );
    }

    #[test]
    fn a_frame_drained_on_a_fixs_wake_leaves_the_settings_arm_nothing_to_fire_on() {
        // `ready_to_receive` does not consume, so a frame that arrives with a
        // fix is applied once by that wake's drain — and the next wait then has
        // an empty queue, rather than a phantom settings wake for a frame that
        // is already at its sinks.
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        s.settings.try_send(max_hr(185)).expect("within depth");
        s.fixes.sender().send(a_fix());

        {
            let mut wait = pin!(select3(
                fix_rx.changed(),
                s.cmds.receive(),
                s.settings.ready_to_receive(),
            ));
            assert!(
                matches!(wait.as_mut().poll(&mut cx), Poll::Ready(Either3::First(_))),
                "the fix arm outranks the settings arm"
            );
        }
        assert_eq!(drain(&s.settings).as_slice(), [EffectKind::MaxHr]);

        let mut next = pin!(select3(
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        assert!(
            next.as_mut().poll(&mut cx).is_pending(),
            "the drained frame must not wake the task a second time"
        );
    }

    #[test]
    fn the_settings_arm_does_not_re_fire_for_the_frame_its_own_wake_drained() {
        let s = Seams::new();
        let waker = s.waker();
        let mut cx = Context::from_waker(&waker);
        let mut fix_rx = s.fixes.receiver().expect("a receiver");

        s.settings.try_send(max_hr(185)).expect("within depth");

        {
            let mut wait = pin!(select3(
                fix_rx.changed(),
                s.cmds.receive(),
                s.settings.ready_to_receive(),
            ));
            assert!(matches!(
                wait.as_mut().poll(&mut cx),
                Poll::Ready(Either3::Third(()))
            ));
        }
        assert_eq!(drain(&s.settings).as_slice(), [EffectKind::MaxHr]);

        let mut next = pin!(select3(
            fix_rx.changed(),
            s.cmds.receive(),
            s.settings.ready_to_receive(),
        ));
        assert!(
            next.as_mut().poll(&mut cx).is_pending(),
            "one push, one apply — the arm cannot double-apply"
        );
        assert!(
            drain(&s.settings).is_empty(),
            "and nothing is left to apply twice"
        );
    }
}
