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
    use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
    use embassy_sync::channel::Channel;
    use embassy_sync::watch::Watch;
    use heapless::Vec;

    use crate::settings::WatchSettings;
    use crate::settings_apply::{plan_apply, EffectKind, SettingsEffect, MAX_SETTINGS_EFFECTS};

    /// The queue the record task actually drains: `app/src/state.rs` declares
    /// this exact type from this exact constant, so what these tests exercise is
    /// the transport, not a stand-in for it.
    type SettingsQueue = Channel<CriticalSectionRawMutex, WatchSettings, SETTINGS_QUEUE_DEPTH>;

    /// The single-latest-value slot the queue replaced, at the width it was
    /// declared with.
    type SettingsSlot = Watch<CriticalSectionRawMutex, Option<WatchSettings>, 1>;

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
}
