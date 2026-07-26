//! The GSV/GSA signal-meter side channel — what the app's `gps` task does with
//! the two NMEA sentences that carry no position, only how the sky looks.
//!
//! [`crate::gnss_cadence`] answers "which *fixes* do we forward, and may the
//! receiver nap". This is the other, independent question the same task
//! answers: satellites-in-view and the GNSS fix mode are not fixes, they never
//! reach the recorder, and their sole consumer is the idle face's four-bar
//! signal meter. They therefore belong to the meter's own ladder
//! ([`crate::statusbar::bars_for_fix`]), not to the fix cadence — folding them
//! into `gnss_cadence` would make the fix-cadence seam depend on a render
//! module.
//!
//! Both sentences arrive far faster than they say anything. `ublox_nmea`'s
//! parser emits one `Sentence::Gsv` **per GSV sentence, not per group** — it
//! reads the same repeated in-view total out of each — so a receiver reporting
//! 12 satellites in a three-sentence group publishes three times, once a
//! second, forever; GSA adds a fourth. The parser also strips the talker
//! prefix, so a multi-constellation receiver's per-constellation groups land on
//! the same channel and each other's heels. Sending each one woke the screen
//! task, which waits on the channel, for a value that had not moved.
//!
//! [`should_publish`] closes that by gating on the only thing downstream can
//! see: the bar count. Repeats inside a group are identical and drop out; a
//! per-constellation count that lands in the same band drops out too; a real
//! acquisition, loss, or 3D→2D degrade goes through on the sentence that
//! caused it.
//!
//! The pair travels as one [`SignalSample`] rather than two channels because
//! the bars are a function of *both*: gating two independent channels against
//! their own last-published values lets a suppressed satellite count become
//! visible later through a fix-mode change, and the meter would then draw bars
//! for a sky that had already gone.

use crate::statusbar::bars_for_fix;

/// The GSV satellites-in-view count and GSA fix mode behind the idle face's
/// signal meter. Defaults to the honest "nothing acquired" pair: no satellites,
/// fix mode 0 (unknown), which [`bars_for_fix`] reads as zero bars.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct SignalSample {
    pub sats: u8,
    /// NMEA GSA fix type: 1 = no fix, 2 = 2D, 3 = 3D.
    pub fix_type: u8,
}

impl SignalSample {
    /// The 0..=4 meter bars this pair draws.
    pub fn bars(&self) -> u8 {
        bars_for_fix(self.sats, self.fix_type)
    }
}

/// Whether the latest observed pair is worth publishing, given the last pair
/// published.
///
/// The gate is the rendered bar count, which is everything the pair is used
/// for: a sample that would draw the same meter is not news, however different
/// its raw numbers. Same shape as [`crate::hr_duty::should_publish`] — the one
/// idiom every free-running sensor channel is throttled with.
pub fn should_publish(last: Option<SignalSample>, next: SignalSample) -> bool {
    last.map(|s| s.bars()) != Some(next.bars())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statusbar::MAX_BARS;

    fn sample(sats: u8, fix_type: u8) -> SignalSample {
        SignalSample { sats, fix_type }
    }

    /// Drive `should_publish` the way the gps task does — anchored on the last
    /// pair actually published — and count what got through.
    fn publishes(samples: impl IntoIterator<Item = SignalSample>) -> usize {
        let mut published: Option<SignalSample> = None;
        let mut n = 0;
        for s in samples {
            if should_publish(published, s) {
                published = Some(s);
                n += 1;
            }
        }
        n
    }

    #[test]
    fn the_default_pair_is_searching() {
        assert_eq!(SignalSample::default(), sample(0, 0));
        assert_eq!(SignalSample::default().bars(), 0);
    }

    #[test]
    fn the_first_sample_always_publishes() {
        assert!(should_publish(None, SignalSample::default()));
        assert!(should_publish(None, sample(12, 3)));
    }

    #[test]
    fn a_repeated_gsv_group_publishes_once() {
        // The defect: `ublox_nmea` emits one Gsv per sentence, so a 12-satellite
        // group is three identical sends a second, each waking the screen task.
        let group = [sample(12, 3), sample(12, 3), sample(12, 3)];
        let epochs = (0..30).flat_map(|_| group);
        assert_eq!(publishes(epochs), 1);
    }

    #[test]
    fn per_constellation_counts_in_one_band_publish_once() {
        // The parser strips the talker prefix, so GPS / GLONASS / Galileo groups
        // all land here with their own in-view totals. 10, 12 and 14 are all the
        // top band, so the meter never moves and neither should the channel.
        let epoch = [sample(10, 3), sample(12, 3), sample(14, 3)];
        assert_eq!(epoch.map(|s| s.bars()), [MAX_BARS; 3]);
        assert_eq!(publishes((0..30).flat_map(|_| epoch)), 1);
    }

    #[test]
    fn acquisition_and_loss_publish_on_the_sentence_that_caused_them() {
        // Cold start climbing out of "searching", then the sky closing again.
        let acquiring = [
            sample(0, 1),
            sample(3, 1),
            sample(3, 3),
            sample(6, 3),
            sample(11, 3),
        ];
        assert_eq!(acquiring.map(|s| s.bars()), [0, 0, 1, 2, 4]);
        assert_eq!(publishes(acquiring), 4);
    }

    #[test]
    fn losing_the_fix_under_a_full_sky_publishes() {
        // The honest-meter case: satellites still in view, but the receiver has
        // no solution, so the meter must fall to searching.
        assert!(should_publish(Some(sample(12, 3)), sample(12, 1)));
    }

    #[test]
    fn a_three_d_to_two_d_degrade_publishes() {
        assert!(should_publish(Some(sample(12, 3)), sample(12, 2)));
    }

    #[test]
    fn a_count_change_inside_one_band_is_not_news() {
        // 7, 8 and 9 satellites all draw three bars; nothing downstream can tell
        // them apart, so none of them is worth a wake.
        for sats in [7, 8, 9] {
            assert!(!should_publish(Some(sample(7, 3)), sample(sats, 3)));
        }
    }

    #[test]
    fn a_steady_sky_never_wakes_a_consumer_twice() {
        // A stationary wrist under an unchanging sky: GSV x3 + GSA every second
        // for ten minutes, one publish total.
        let epoch = [
            sample(9, 3),
            sample(9, 3),
            sample(9, 3),
            sample(9, 3),
            sample(8, 3),
        ];
        assert_eq!(publishes((0..600).flat_map(|_| epoch)), 1);
    }

    #[test]
    fn the_meter_never_lags_the_latest_sky() {
        let mut published: Option<SignalSample> = None;
        for (sats, fix_type) in [(12, 3), (4, 3), (4, 2), (12, 2), (12, 3), (0, 1), (9, 3)] {
            let observed = sample(sats, fix_type);
            if should_publish(published, observed) {
                published = Some(observed);
            }
            assert_eq!(
                published.map_or(0, |s| s.bars()),
                observed.bars(),
                "meter is a step behind at {observed:?}"
            );
        }
    }

    #[test]
    fn a_suppressed_count_cannot_resurface_through_a_fix_mode_change() {
        // The reason the pair is one channel. Under a 2D cap the drop from 12
        // to 4 satellites draws the same two bars and is suppressed; when the
        // receiver then reaches 3D, publishing the CURRENT pair draws two bars,
        // whereas two independently-gated channels would have paired the fresh
        // fix mode with the stale count and drawn four.
        let capped = sample(12, 2);
        let thinned = sample(4, 2);
        assert!(!should_publish(Some(capped), thinned));
        let locked = sample(4, 3);
        assert_eq!(locked.bars(), 2);
        assert_eq!(sample(capped.sats, locked.fix_type).bars(), MAX_BARS);
    }
}
