//! Where the watch's heart rate comes from: an external BLE chest strap's wire
//! side, and the precedence between that strap and the on-wrist optical sensor.
//!
//! [`crate::hr_duty`] owns *when* the optical part samples and how long any
//! reading may be shown; [`crate::hr_drain`] owns its FIFO. This module owns
//! the second source and the arbitration:
//!
//! - **Discovery.** [`advertises_heart_rate_service`] decides whether one
//!   scanned advertisement belongs to a strap, by looking for the standard
//!   Heart Rate Service ([`HR_SERVICE_UUID16`]) in the advertisement's 16-bit
//!   service-UUID lists. Advertising data is attacker-shaped input — a length
//!   byte that overruns the buffer is the classic parse bug — so the walk is
//!   bounds-checked at every step and a malformed structure aborts the walk
//!   rather than being skipped past.
//! - **The measurement wire.** [`parse_measurement`] decodes the Heart Rate
//!   Measurement characteristic ([`HR_MEASUREMENT_UUID16`]), whose leading
//!   flags byte selects a uint8 or uint16 rate and declares two optional
//!   trailing fields. Getting the flags wrong reads the wrong bytes as the
//!   rate, so the decode is **strict**: every byte the flags account for must
//!   be present and nothing may be left over. A frame that does not add up is
//!   rejected whole — the watch shows no HR rather than a number derived from
//!   a frame it did not understand.
//! - **Precedence.** [`select_hr`] states the rule once: a strap that is
//!   reporting a *trusted* rate ([`HrMeasurement::trusted_bpm`]) no older than
//!   [`STRAP_STALE_AFTER_S`] is authoritative; anything else falls back to the
//!   optical sensor; with neither, the watch blanks. Precedence is by sensor
//!   *class*, decided once, not by a per-sample quality score: a chest strap
//!   measures the cardiac electrical signal directly while wrist PPG is an
//!   optical proxy that is worst exactly where an ultra runner needs it (high-
//!   cadence descents — `docs/custom_watch/vision.md` req #8, and the motion-
//!   artifact line of the tier-1 bench checklist). Neither source publishes a
//!   confidence figure, so a score-based arbiter would have to invent one and
//!   would flap between sources mid-run.
//!
//! **Fail-closed in all three directions.** A malformed advertisement is not a
//! strap. A malformed measurement publishes nothing. A strap that is off the
//! chest (contact supported and not detected), reports a rate outside the
//! physiological band, or goes quiet for longer than [`STRAP_STALE_AFTER_S`]
//! stops being authoritative and the optical sensor takes back over — and when
//! *neither* has a reading, [`hr_to_publish`] emits one explicit blank rather
//! than leaving the last strap number on screen to age out under a
//! duty-cycled mode's much longer [`crate::hr_duty::hold_budget_s`].
//!
//! **Verification ceiling.** Everything in this module is pure and
//! host-tested. That proves the *codec and the rule*, and nothing about the
//! radio: the GATT central role that feeds it lives behind the `ble` feature,
//! which the Renode sim cannot run at all (no S140 SoftDevice — decisions
//! § 210 / § 365), so the transport around this module is **build-verified
//! only**. Host tests here say what the bytes mean, not that any byte ever
//! arrived.

use crate::hr_duty::{should_publish, HrSample};

/// Heart Rate Service — the standard 16-bit UUID a strap advertises.
pub const HR_SERVICE_UUID16: u16 = 0x180D;

/// Heart Rate Measurement — the notify characteristic [`parse_measurement`]
/// decodes.
pub const HR_MEASUREMENT_UUID16: u16 = 0x2A37;

/// Incomplete / complete lists of 16-bit service UUIDs. A strap may put the
/// Heart Rate Service in either, and in the advertisement or its scan
/// response; both arrive as separate reports and are checked separately.
const AD_TYPE_INCOMPLETE_16: u8 = 0x02;
const AD_TYPE_COMPLETE_16: u8 = 0x03;

/// Whether one advertising-data blob offers the Heart Rate Service.
///
/// The blob is a chain of `len | type | payload[len - 1]` structures. `len`
/// comes off the air, so a length that overruns the remaining bytes (or a zero
/// length, which terminates the chain as padding) ends the walk and reports
/// "not a strap": a truncated or hostile report must never index past the
/// scan buffer, and must never be read past its damage as though the rest were
/// intact.
pub fn advertises_heart_rate_service(ad: &[u8]) -> bool {
    let mut rest = ad;
    while let Some((&len, tail)) = rest.split_first() {
        let len = len as usize;
        if len == 0 || tail.len() < len {
            return false;
        }
        let (field, next) = tail.split_at(len);
        rest = next;
        let Some((&ad_type, payload)) = field.split_first() else {
            return false;
        };
        if ad_type != AD_TYPE_INCOMPLETE_16 && ad_type != AD_TYPE_COMPLETE_16 {
            continue;
        }
        if payload
            .chunks_exact(2)
            .any(|u| u16::from_le_bytes([u[0], u[1]]) == HR_SERVICE_UUID16)
        {
            return true;
        }
    }
    false
}

/// Flags byte of the Heart Rate Measurement characteristic, in bit order.
const FLAG_UINT16: u8 = 1 << 0;
const FLAG_CONTACT_DETECTED: u8 = 1 << 1;
const FLAG_CONTACT_SUPPORTED: u8 = 1 << 2;
const FLAG_ENERGY_EXPENDED: u8 = 1 << 3;
const FLAG_RR_INTERVAL: u8 = 1 << 4;

/// What the strap says about skin contact. Most straps do not implement the
/// sensor-contact bits at all, which is [`ContactState::NotSupported`] and
/// must not be read as "off the chest".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ContactState {
    NotSupported,
    NotDetected,
    Detected,
}

/// One decoded Heart Rate Measurement notification.
///
/// `raw_bpm` is exactly what the strap sent — the plausibility rules live in
/// [`HrMeasurement::trusted_bpm`], so a caller cannot accidentally publish an
/// unfiltered value by reading the field.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HrMeasurement {
    pub raw_bpm: u16,
    pub contact: ContactState,
}

/// The physiological band a strap reading must sit inside to be published.
/// Same window the optical detector applies to its own estimate (30 bpm is
/// below any running pulse, 220 is the `220 - age` ceiling at age zero); held
/// separately because `watch_core` is hardware-free and cannot depend on the
/// `max86177` driver crate where the optical copy lives.
pub const STRAP_BPM_MIN: u16 = 30;
pub const STRAP_BPM_MAX: u16 = 220;

impl HrMeasurement {
    /// The rate this measurement may be acted on with, or `None`.
    ///
    /// A strap that supports contact detection and reports none is off the
    /// chest — its number is noise, and must not displace an optical reading
    /// from a wrist that *is* being worn. A rate outside the physiological
    /// band is a sensor artefact (0 is what a strap sends before it settles).
    pub fn trusted_bpm(&self) -> Option<u16> {
        if self.contact == ContactState::NotDetected {
            return None;
        }
        (STRAP_BPM_MIN..=STRAP_BPM_MAX)
            .contains(&self.raw_bpm)
            .then_some(self.raw_bpm)
    }
}

/// Decode one Heart Rate Measurement notification, or `None` if the bytes do
/// not add up.
///
/// The flags byte selects the rate's width and declares the energy-expended
/// and RR-interval fields, so the frame's length is a function of its own
/// first byte. The decode requires that length to be exactly satisfied:
/// missing bytes mean a truncated frame, and leftover bytes mean the flags
/// were not what the sender meant — either way the rate itself was read at an
/// offset we cannot vouch for. Reserved flag bits are ignored (the spec
/// reserves them for future use; rejecting on them would break straps that set
/// them), but they never change where a field starts.
pub fn parse_measurement(bytes: &[u8]) -> Option<HrMeasurement> {
    let (&flags, rest) = bytes.split_first()?;
    let (raw_bpm, rest) = if flags & FLAG_UINT16 != 0 {
        if rest.len() < 2 {
            return None;
        }
        (u16::from_le_bytes([rest[0], rest[1]]), &rest[2..])
    } else {
        let (&v, rest) = rest.split_first()?;
        (u16::from(v), rest)
    };
    let rest = if flags & FLAG_ENERGY_EXPENDED != 0 {
        if rest.len() < 2 {
            return None;
        }
        &rest[2..]
    } else {
        rest
    };
    let accounted = if flags & FLAG_RR_INTERVAL != 0 {
        !rest.is_empty() && rest.len() % 2 == 0
    } else {
        rest.is_empty()
    };
    if !accounted {
        return None;
    }
    let contact = if flags & FLAG_CONTACT_SUPPORTED == 0 {
        ContactState::NotSupported
    } else if flags & FLAG_CONTACT_DETECTED == 0 {
        ContactState::NotDetected
    } else {
        ContactState::Detected
    };
    Some(HrMeasurement { raw_bpm, contact })
}

/// ATT MTU the central requests for the strap link.
///
/// 23 is the mandatory legacy minimum every peripheral supports, and a Heart
/// Rate Measurement never needs more: flags + a uint16 rate + energy expended
/// is 5 bytes, leaving room for RR intervals we do not consume. Requesting the
/// floor also bounds the notification payload, which is what makes
/// [`HR_MEASUREMENT_CAP`] a safe buffer size — the `heapless::Vec` the GATT
/// client decodes into panics rather than truncating if a notification arrives
/// longer than its capacity, so the cap must never be smaller than the
/// negotiated MTU permits.
pub const STRAP_ATT_MTU: u16 = 23;

/// Largest notification payload the strap link can deliver: `ATT_MTU - 3`.
pub const HR_MEASUREMENT_CAP: usize = STRAP_ATT_MTU as usize - 3;

/// One bounded scan window, seconds, and the gap before the next one.
///
/// Scanning is the most radio-expensive thing a watch does, and a strapless
/// runner would otherwise pay for it forever. Ten seconds is several
/// advertising intervals at the ~1 s a HR strap advertises at, so a strap in
/// range is found in the first window; fifty seconds of quiet between windows
/// holds the duty at one sixth. A connected strap costs no scanning at all —
/// these apply only while none is connected. Both are derivations from the
/// advertising cadence, not measurements (decisions § 83: nothing on this
/// device measures power).
pub const SCAN_WINDOW_S: u32 = 10;
pub const SCAN_GAP_S: u32 = 50;

/// How long a strap measurement stays authoritative.
///
/// A Heart Rate Measurement notifies at ~1 Hz, so five seconds absorbs a
/// handful of missed notifications across a connection event without letting a
/// strap that has fallen off, gone out of range, or wedged keep the display
/// while a live optical sensor is ignored beside it.
pub const STRAP_STALE_AFTER_S: u32 = 5;

/// Which sensor a published reading came from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum HrSource {
    Strap,
    Optical,
}

/// The winning sample and the source it came from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HrSelection {
    pub source: HrSource,
    pub sample: HrSample,
}

/// The authoritative reading right now: a fresh strap rate, else the optical
/// sensor's, else nothing. See the module docs for why precedence is by sensor
/// class rather than by a per-sample score.
pub fn select_hr(
    strap: Option<HrSample>,
    optical: Option<HrSample>,
    now_s: u32,
) -> Option<HrSelection> {
    if let Some(sample) = strap {
        if sample.bpm.is_some() && now_s.saturating_sub(sample.at_s) <= STRAP_STALE_AFTER_S {
            return Some(HrSelection {
                source: HrSource::Strap,
                sample,
            });
        }
    }
    optical.map(|sample| HrSelection {
        source: HrSource::Optical,
        sample,
    })
}

/// What the arbitrating task should put on the shared HR watch, or `None` when
/// the current state carries nothing new.
///
/// Two things beyond [`select_hr`]. It deduplicates against the last published
/// sample through [`should_publish`], so the arbitration hop cannot reintroduce
/// the free-running waker that dedup exists to prevent. And when nothing is
/// authoritative it synthesises **one** blank stamped now — a strap that drops
/// while the optical sensor is absent would otherwise leave its last rate on
/// the watch to age out under [`crate::hr_duty::hold_budget_s`], which is up to
/// two minutes in Expedition. The blank is emitted on the down-edge only: once
/// published, the dedup keeps it from repeating, and nothing is ever published
/// for a watch that has had no reading at all.
pub fn hr_to_publish(
    last: Option<HrSample>,
    strap: Option<HrSample>,
    optical: Option<HrSample>,
    now_s: u32,
) -> Option<HrPublication> {
    let (next, source) = match select_hr(strap, optical, now_s) {
        Some(selection) => (selection.sample, Some(selection.source)),
        None => {
            last?.bpm?;
            (
                HrSample {
                    bpm: None,
                    at_s: now_s,
                },
                None,
            )
        }
    };
    should_publish(last, next).then_some(HrPublication {
        sample: next,
        source,
    })
}

/// A sample to publish and the sensor it came from.
///
/// The source rides with the sample because the arbitration used to end at a
/// log line: [`select_hr`] decided a strap outranked the wrist, the winning
/// *rate* reached the panel and the winning *sensor* did not. A runner could
/// then read a BPM with no way to tell whether the strap they buckled on was
/// connected at all — the same blind spot the zones page's `CEIL --` exists to
/// close, and the reason a strap that silently never paired is indistinguishable
/// from one that did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HrPublication {
    pub sample: HrSample,
    /// `None` for the synthesised blank — no sensor produced it, and naming one
    /// there would credit a reading that does not exist.
    pub source: Option<HrSource>,
}

/// Seconds until a currently-authoritative strap sample stops being one, or
/// `None` when no timer is owed.
///
/// The arbitrating task otherwise only wakes when a source publishes — so a
/// strap that simply stops, with no optical sensor to wake anything, would
/// hold the screen indefinitely. This is the one deadline that needs arming,
/// and it is never zero: a zero-duration timer would spin the task instead of
/// parking it (the same rule [`crate::hr_drain::next_window_wait_s`] follows).
pub fn strap_recheck_wait_s(strap: Option<HrSample>, now_s: u32) -> Option<u32> {
    let sample = strap?;
    sample.bpm?;
    let age = now_s.saturating_sub(sample.at_s);
    (age <= STRAP_STALE_AFTER_S).then(|| STRAP_STALE_AFTER_S + 1 - age)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `len | type | payload` advertising structure.
    fn ad_field(ad_type: u8, payload: &[u8]) -> heapless::Vec<u8, 32> {
        let mut v = heapless::Vec::new();
        v.push(payload.len() as u8 + 1).unwrap();
        v.push(ad_type).unwrap();
        v.extend_from_slice(payload).unwrap();
        v
    }

    fn sample(bpm: Option<u16>, at_s: u32) -> Option<HrSample> {
        Some(HrSample { bpm, at_s })
    }

    #[test]
    fn no_advertising_data_is_not_a_strap() {
        assert!(!advertises_heart_rate_service(&[]));
    }

    #[test]
    fn a_complete_16_bit_list_carrying_the_hr_service_is_a_strap() {
        let ad = ad_field(AD_TYPE_COMPLETE_16, &0x180Du16.to_le_bytes());
        assert!(advertises_heart_rate_service(&ad));
    }

    #[test]
    fn an_incomplete_16_bit_list_counts_too() {
        // A strap with more services than fit the payload advertises the list
        // as incomplete; refusing that would ignore real straps.
        let ad = ad_field(AD_TYPE_INCOMPLETE_16, &0x180Du16.to_le_bytes());
        assert!(advertises_heart_rate_service(&ad));
    }

    #[test]
    fn other_services_alone_are_not_a_strap() {
        let mut payload = heapless::Vec::<u8, 8>::new();
        payload.extend_from_slice(&0x180Fu16.to_le_bytes()).unwrap();
        payload.extend_from_slice(&0x1816u16.to_le_bytes()).unwrap();
        let ad = ad_field(AD_TYPE_COMPLETE_16, &payload);
        assert!(!advertises_heart_rate_service(&ad));
    }

    #[test]
    fn the_uuid_only_counts_inside_a_service_list() {
        // The same two bytes inside manufacturer-specific data (0xFF) say
        // nothing about what the peer serves.
        let ad = ad_field(0xFF, &0x180Du16.to_le_bytes());
        assert!(!advertises_heart_rate_service(&ad));
    }

    #[test]
    fn the_service_list_may_come_after_other_structures() {
        let mut ad = heapless::Vec::<u8, 64>::new();
        ad.extend_from_slice(&ad_field(0x01, &[0x06])).unwrap();
        ad.extend_from_slice(&ad_field(0x09, b"Strap")).unwrap();
        ad.extend_from_slice(&ad_field(AD_TYPE_COMPLETE_16, &0x180Du16.to_le_bytes()))
            .unwrap();
        assert!(advertises_heart_rate_service(&ad));
    }

    #[test]
    fn a_length_byte_past_the_end_aborts_instead_of_reading_past_it() {
        // The classic advertising-parse bug: a length that overruns the scan
        // buffer. Must be refused, not indexed.
        let ad = [0x20u8, AD_TYPE_COMPLETE_16, 0x0D, 0x18];
        assert!(!advertises_heart_rate_service(&ad));
    }

    #[test]
    fn a_zero_length_structure_ends_the_walk() {
        let mut ad = heapless::Vec::<u8, 64>::new();
        ad.push(0).unwrap();
        ad.extend_from_slice(&ad_field(AD_TYPE_COMPLETE_16, &0x180Du16.to_le_bytes()))
            .unwrap();
        assert!(!advertises_heart_rate_service(&ad));
    }

    #[test]
    fn a_structure_with_no_payload_is_skipped_not_matched() {
        let mut ad = heapless::Vec::<u8, 64>::new();
        ad.extend_from_slice(&ad_field(AD_TYPE_COMPLETE_16, &[]))
            .unwrap();
        assert!(!advertises_heart_rate_service(&ad));
    }

    #[test]
    fn a_trailing_odd_byte_cannot_forge_a_match() {
        // An odd-length UUID list is malformed; the whole pairs still decide,
        // and a lone byte can never be read as half of 0x180D.
        let ad = ad_field(AD_TYPE_COMPLETE_16, &[0x0D]);
        assert!(!advertises_heart_rate_service(&ad));
        let ad = ad_field(AD_TYPE_COMPLETE_16, &[0x0D, 0x18, 0x0D]);
        assert!(advertises_heart_rate_service(&ad));
    }

    #[test]
    fn an_empty_measurement_is_rejected() {
        assert_eq!(parse_measurement(&[]), None);
    }

    #[test]
    fn a_uint8_rate_decodes() {
        let m = parse_measurement(&[0x00, 72]).unwrap();
        assert_eq!(m.raw_bpm, 72);
        assert_eq!(m.contact, ContactState::NotSupported);
    }

    #[test]
    fn a_uint16_rate_decodes_little_endian() {
        // The whole reason the flags byte exists: the same payload read at the
        // wrong width is a different number.
        let m = parse_measurement(&[FLAG_UINT16, 0x2C, 0x01]).unwrap();
        assert_eq!(m.raw_bpm, 300);
    }

    #[test]
    fn a_uint16_frame_missing_its_second_byte_is_rejected() {
        assert_eq!(parse_measurement(&[FLAG_UINT16, 0x2C]), None);
    }

    #[test]
    fn a_flags_only_frame_is_rejected() {
        assert_eq!(parse_measurement(&[0x00]), None);
    }

    #[test]
    fn energy_expended_is_accounted_for() {
        let m = parse_measurement(&[FLAG_ENERGY_EXPENDED, 150, 0x10, 0x00]).unwrap();
        assert_eq!(m.raw_bpm, 150);
        assert_eq!(parse_measurement(&[FLAG_ENERGY_EXPENDED, 150, 0x10]), None);
        assert_eq!(parse_measurement(&[FLAG_ENERGY_EXPENDED, 150]), None);
    }

    #[test]
    fn rr_intervals_are_accounted_for_in_pairs() {
        let m = parse_measurement(&[FLAG_RR_INTERVAL, 150, 0x00, 0x02, 0x10, 0x02]).unwrap();
        assert_eq!(m.raw_bpm, 150);
        assert_eq!(
            parse_measurement(&[FLAG_RR_INTERVAL, 150, 0x00, 0x02, 0x10]),
            None,
            "an odd trailing byte means the frame was truncated"
        );
        assert_eq!(
            parse_measurement(&[FLAG_RR_INTERVAL, 150]),
            None,
            "the flag claims at least one interval"
        );
    }

    #[test]
    fn every_optional_field_together_decodes() {
        let m = parse_measurement(&[
            FLAG_UINT16 | FLAG_ENERGY_EXPENDED | FLAG_RR_INTERVAL,
            0xA0,
            0x00,
            0x2C,
            0x01,
            0x00,
            0x02,
        ])
        .unwrap();
        assert_eq!(m.raw_bpm, 160);
    }

    #[test]
    fn leftover_bytes_no_flag_accounts_for_are_rejected() {
        // Extra bytes mean the flags are not what the sender meant, so the
        // rate was read at an offset we cannot vouch for.
        assert_eq!(parse_measurement(&[0x00, 72, 0x00]), None);
        assert_eq!(parse_measurement(&[FLAG_UINT16, 0x48, 0x00, 0x99]), None);
    }

    #[test]
    fn reserved_flag_bits_are_ignored() {
        let m = parse_measurement(&[0b1110_0000, 72]).unwrap();
        assert_eq!(m.raw_bpm, 72);
    }

    #[test]
    fn contact_state_reads_both_bits() {
        let states = [
            (0b000, ContactState::NotSupported),
            (0b010, ContactState::NotSupported),
            (0b100, ContactState::NotDetected),
            (0b110, ContactState::Detected),
        ];
        for (flags, want) in states {
            assert_eq!(parse_measurement(&[flags, 72]).unwrap().contact, want);
        }
    }

    #[test]
    fn a_strap_off_the_chest_is_not_trusted() {
        let m = parse_measurement(&[FLAG_CONTACT_SUPPORTED, 72]).unwrap();
        assert_eq!(m.contact, ContactState::NotDetected);
        assert_eq!(m.trusted_bpm(), None);
    }

    #[test]
    fn a_strap_that_does_not_implement_contact_is_still_trusted() {
        // Most straps never set the supported bit; reading that as "off the
        // chest" would refuse every reading from them.
        let m = parse_measurement(&[0x00, 72]).unwrap();
        assert_eq!(m.trusted_bpm(), Some(72));
    }

    #[test]
    fn rates_outside_the_physiological_band_are_not_trusted() {
        let at = |raw_bpm| HrMeasurement {
            raw_bpm,
            contact: ContactState::Detected,
        };
        assert_eq!(at(0).trusted_bpm(), None, "a settling strap sends zero");
        assert_eq!(at(STRAP_BPM_MIN - 1).trusted_bpm(), None);
        assert_eq!(at(STRAP_BPM_MIN).trusted_bpm(), Some(STRAP_BPM_MIN));
        assert_eq!(at(STRAP_BPM_MAX).trusted_bpm(), Some(STRAP_BPM_MAX));
        assert_eq!(at(STRAP_BPM_MAX + 1).trusted_bpm(), None);
    }

    #[test]
    fn a_fresh_strap_outranks_the_optical_sensor() {
        let s = select_hr(sample(Some(150), 100), sample(Some(120), 100), 100).unwrap();
        assert_eq!(s.source, HrSource::Strap);
        assert_eq!(s.sample.bpm, Some(150));
    }

    #[test]
    fn a_strap_with_no_trusted_pulse_yields_to_the_wrist() {
        let s = select_hr(sample(None, 100), sample(Some(120), 100), 100).unwrap();
        assert_eq!(s.source, HrSource::Optical);
        assert_eq!(s.sample.bpm, Some(120));
    }

    #[test]
    fn a_strap_that_went_quiet_yields_to_the_wrist() {
        let strap = sample(Some(150), 100);
        let optical = sample(Some(120), 100);
        let at_limit = select_hr(strap, optical, 100 + STRAP_STALE_AFTER_S).unwrap();
        assert_eq!(at_limit.source, HrSource::Strap);
        let past = select_hr(strap, optical, 100 + STRAP_STALE_AFTER_S + 1).unwrap();
        assert_eq!(past.source, HrSource::Optical);
    }

    #[test]
    fn a_sample_stamped_ahead_of_the_clock_reads_as_fresh() {
        // The strap task stamps on its own read of the uptime and can race the
        // second boundary; that must not blank a genuinely fresh reading.
        let s = select_hr(sample(Some(150), 101), sample(Some(120), 100), 100).unwrap();
        assert_eq!(s.source, HrSource::Strap);
    }

    #[test]
    fn either_source_alone_wins_and_neither_selects_nothing() {
        assert_eq!(
            select_hr(sample(Some(150), 10), None, 10).map(|s| s.source),
            Some(HrSource::Strap)
        );
        assert_eq!(
            select_hr(None, sample(Some(120), 10), 10).map(|s| s.source),
            Some(HrSource::Optical)
        );
        assert_eq!(select_hr(None, None, 10), None);
    }

    #[test]
    fn a_stale_strap_with_no_wrist_sensor_selects_nothing() {
        assert_eq!(
            select_hr(sample(Some(150), 10), None, 10 + STRAP_STALE_AFTER_S + 1),
            None
        );
    }

    #[test]
    fn the_first_reading_publishes_and_a_repeat_does_not() {
        let first = hr_to_publish(None, None, sample(Some(120), 10), 10).unwrap();
        assert_eq!(first.sample.bpm, Some(120));
        assert_eq!(first.source, Some(HrSource::Optical));
        assert_eq!(
            hr_to_publish(Some(first.sample), None, sample(Some(120), 10), 10),
            None
        );
    }

    #[test]
    fn a_strap_arriving_supersedes_the_published_optical_reading() {
        let published = HrSample {
            bpm: Some(120),
            at_s: 10,
        };
        let next = hr_to_publish(
            Some(published),
            sample(Some(150), 11),
            sample(Some(120), 10),
            11,
        )
        .unwrap();
        assert_eq!(next.sample.bpm, Some(150));
        assert_eq!(
            next.source,
            Some(HrSource::Strap),
            "the winning sensor rides with the winning rate"
        );
    }

    #[test]
    fn losing_every_source_publishes_exactly_one_blank() {
        // Without this the last strap rate sits on the watch for a whole
        // hold budget — up to two minutes in Expedition — with nothing left
        // to wake the consumer and correct it.
        let published = HrSample {
            bpm: Some(150),
            at_s: 10,
        };
        let now = 10 + STRAP_STALE_AFTER_S + 1;
        let blank = hr_to_publish(Some(published), sample(Some(150), 10), None, now).unwrap();
        assert_eq!(blank.sample.bpm, None);
        assert_eq!(blank.sample.at_s, now);
        assert_eq!(
            blank.source, None,
            "nothing produced the blank, so nothing may be credited with it"
        );
        assert_eq!(
            hr_to_publish(Some(blank.sample), sample(Some(150), 10), None, now + 1),
            None,
            "the blank must not repeat once per second forever"
        );
    }

    #[test]
    fn a_watch_that_never_had_a_reading_publishes_nothing() {
        assert_eq!(hr_to_publish(None, None, None, 500), None);
        assert_eq!(
            hr_to_publish(None, sample(Some(150), 10), None, 500),
            None,
            "a stale strap on a never-published watch owes no blank"
        );
    }

    #[test]
    fn an_invalid_optical_reading_still_publishes_rather_than_synthesising() {
        // The optical detector's own "no trusted pulse" is a real reading and
        // carries its own timestamp; replacing it with a synthesised blank
        // would move the freshness stamp the consumer ages against.
        let next = hr_to_publish(None, None, sample(None, 42), 100).unwrap();
        assert_eq!(next.sample.at_s, 42);
        assert_eq!(next.sample.bpm, None);
        assert_eq!(
            next.source,
            Some(HrSource::Optical),
            "a real reading of no pulse is still the optical sensor's"
        );
    }

    #[test]
    fn the_recheck_timer_is_only_armed_for_a_held_strap_sample() {
        assert_eq!(strap_recheck_wait_s(None, 100), None);
        assert_eq!(strap_recheck_wait_s(sample(None, 100), 100), None);
        assert_eq!(
            strap_recheck_wait_s(sample(Some(150), 100), 100 + STRAP_STALE_AFTER_S + 1),
            None,
            "an expired sample has no deadline left to wait for"
        );
    }

    #[test]
    fn the_recheck_timer_lands_one_second_past_the_staleness_limit() {
        let s = sample(Some(150), 100);
        assert_eq!(strap_recheck_wait_s(s, 100), Some(STRAP_STALE_AFTER_S + 1));
        assert_eq!(strap_recheck_wait_s(s, 100 + STRAP_STALE_AFTER_S), Some(1));
        for age in 0..=STRAP_STALE_AFTER_S {
            let wait = strap_recheck_wait_s(s, 100 + age).unwrap();
            assert!(wait >= 1, "a zero-duration timer would spin the task");
            assert_eq!(
                select_hr(s, None, 100 + age + wait),
                None,
                "the timer must fire at the moment the sample stops winning"
            );
        }
    }

    #[test]
    fn the_scan_duty_and_link_bounds_are_pinned() {
        // The module docs derive the one-sixth scan duty and the notification
        // buffer size from these; drifting them silently would invalidate the
        // derivation, and shrinking the cap below the negotiated MTU would
        // turn a long notification into a panic.
        assert_eq!((SCAN_WINDOW_S, SCAN_GAP_S), (10, 50));
        assert_eq!(SCAN_WINDOW_S * 6, SCAN_WINDOW_S + SCAN_GAP_S);
        assert_eq!(STRAP_ATT_MTU, 23);
        assert_eq!(HR_MEASUREMENT_CAP, STRAP_ATT_MTU as usize - 3);
    }
}
