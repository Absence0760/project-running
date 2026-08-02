//! `RCF1` — the persisted half of a phone-pushed race configuration.
//!
//! A `SET1` push ([`crate::settings`]) is the only way a runner tells the watch
//! their pacer goal, HR-zone ceiling, QNH reference and fuel cadence, and until
//! this record existed every one of those lived in RAM alone: a brown-out on a
//! cold battery at hour 30 handed the rest of the race a watch with no goal, no
//! ceiling, an altitude referenced to standard pressure and the temperate
//! default fuel cadence — with nothing on the wrist saying so. The three fields
//! a push could already persist (`hide_empty_pages`, the ICE card, the auto-lap
//! trigger) each earned it individually; this record is the general answer.
//!
//! **The record body IS a `SET1` frame.** The alternative — an `RCF1` of its own
//! typed fields — was rejected: it would be a second codec over the same
//! fourteen values, so every future settings field would have to be added to
//! both or silently stop being persisted, and each side would need its own
//! sentinel conventions for the doubly-optional disarms (`Some(None)`) that half
//! these fields carry. Embedding the frame means the restore path is
//! byte-for-byte the push path, [`WatchSettings::decode`]'s
//! accept-v3-through-current rule is already the decode-compat obligation an
//! older stored record needs, and the frame's own field guards are the only
//! guards there are.
//!
//! **A new config record, not a `CONFIG_VERSION` bump.** `CFG1`'s flags byte
//! spent its last free bit on § 372's backyard arm, and bumping
//! [`crate::flash_store::CONFIG_VERSION`] makes every existing record decode as
//! "no saved config" — costing the runner the GNSS mode, profile, backyard arm
//! and auto-lap rung they had already set, to store a pacer goal. That is the
//! same trade `WPT1` / `ICE1` / `SCR1` / `TMR1` each made, and the reason the
//! config page is a page of records rather than one growing struct.
//!
//! **What is deliberately NOT here** ([`persistable`] drops each, and names it
//! in an exhaustive destructure so a new settings field cannot slip past):
//!
//! - `pages` — the persisted activity profile (§ 353) already re-derives the
//!   run-view mask at boot. A second writer of one recorder setting is two
//!   sources of truth that can disagree about which one boot applied last.
//! - `hide_empty_pages`, `ice`, `auto_lap` — each already has a persistent home
//!   (`CFG1`'s flags byte, `ICE1`). Storing them twice is the same defect from
//!   the other direction.
//!
//! The pushed **course**, **workout** and **roadbook** are absent for a
//! different reason: they are not settings fields at all but multi-kilobyte
//! chunked frames of their own, and a course alone is most of a 4 KiB erase
//! page. Persisting them is a flash-layout job (a page each, outside the shared
//! config page), not a settings-record job.
//!
//! **Values their guard rejects are stored, and dropped on the way out.** A
//! restore feeds [`crate::settings_apply::plan_apply`], so an implausible QNH or
//! fuel cadence is refused by exactly the guard that refused it on the wire.
//! Filtering at write time instead would bake today's threshold into flash,
//! where a firmware whose guard later widened could never re-evaluate it.

use crate::run_store::crc32;
use crate::settings::{WatchSettings, MAX_SETTINGS_LEN};

pub const RCF1_MAGIC: [u8; 4] = *b"RCF1";

/// Version of the `RCF1` **wrapper**. The body's version is the `SET1` frame's
/// own, so a settings-format bump does not reach this byte; bumping it here
/// would orphan every stored config, so it changes only if the wrapper's
/// `magic | version | pad | len | frame | crc32` shape does.
pub const RCF1_VERSION: u8 = 1;

/// Offset of the embedded `SET1` frame within the record.
const FRAME_OFFSET: usize = 8;

/// `magic(4) | version(1) | pad(1) | frame_len(2) | frame(MAX_SETTINGS_LEN,
/// zero-padded) | crc32(4)`.
///
/// Fixed rather than sized to the frame it holds, so the record's extent on the
/// config page never moves when [`persistable`] changes which fields ride it,
/// and every write is the same shape. A multiple of the NVMC 4-byte write word.
pub const RACE_CONFIG_RECORD_LEN: usize = FRAME_OFFSET + MAX_SETTINGS_LEN + 4;

const _: () = assert!(RACE_CONFIG_RECORD_LEN.is_multiple_of(4));

/// The settings a `RCF1` record carries, with every field that has a persistent
/// home of its own dropped.
///
/// The destructure names all eighteen fields with no `..` rest pattern, so a new
/// `WatchSettings` field is a missing-field compile error here — the same
/// discipline [`crate::settings_apply::plan_apply`] uses, and for the same
/// reason: a field that silently stops being persisted is invisible until a
/// runner's brown-out loses it.
pub fn persistable(s: &WatchSettings) -> WatchSettings {
    let WatchSettings {
        max_hr,
        pacer,
        gear,
        zone_ceiling,
        sea_level_pa,
        fuel,
        tz_offset_min,
        distance_interval_m,
        time_interval_s,
        pace_band,
        race_phases,
        guided_run,
        resting_hr,
        storm_alert,
        // Each of these already persists elsewhere — module docs carry which.
        pages: _,
        hide_empty_pages: _,
        ice: _,
        auto_lap: _,
    } = *s;
    WatchSettings {
        max_hr,
        pacer,
        gear,
        zone_ceiling,
        sea_level_pa,
        fuel,
        tz_offset_min,
        distance_interval_m,
        time_interval_s,
        pace_band,
        race_phases,
        guided_run,
        resting_hr,
        storm_alert,
        pages: None,
        hide_empty_pages: None,
        ice: None,
        auto_lap: None,
    }
}

/// The stored config after `pushed` lands on top of `base`.
///
/// A `SET1` frame is a delta: a present field overrides, an absent one leaves
/// what the runner set before standing. That is exactly what the accumulated
/// record has to hold, or a phone that pushes one new max HR would erase the
/// pacer goal it did not mention — which is the failure the presence bits exist
/// to prevent, reappearing at the flash layer.
pub fn merged(base: &WatchSettings, pushed: &WatchSettings) -> WatchSettings {
    let p = persistable(pushed);
    WatchSettings {
        max_hr: p.max_hr.or(base.max_hr),
        pacer: p.pacer.or(base.pacer),
        gear: p.gear.or(base.gear),
        zone_ceiling: p.zone_ceiling.or(base.zone_ceiling),
        sea_level_pa: p.sea_level_pa.or(base.sea_level_pa),
        fuel: p.fuel.or(base.fuel),
        tz_offset_min: p.tz_offset_min.or(base.tz_offset_min),
        distance_interval_m: p.distance_interval_m.or(base.distance_interval_m),
        time_interval_s: p.time_interval_s.or(base.time_interval_s),
        pace_band: p.pace_band.or(base.pace_band),
        race_phases: p.race_phases.or(base.race_phases),
        guided_run: p.guided_run.or(base.guided_run),
        resting_hr: p.resting_hr.or(base.resting_hr),
        storm_alert: p.storm_alert.or(base.storm_alert),
        pages: None,
        hide_empty_pages: None,
        ice: None,
        auto_lap: None,
    }
}

/// Encode the record. Only [`persistable`] fields reach the body, so a caller
/// cannot smuggle an ICE card onto this record by handing over a whole frame.
pub fn encode(cfg: &WatchSettings) -> [u8; RACE_CONFIG_RECORD_LEN] {
    let mut b = [0u8; RACE_CONFIG_RECORD_LEN];
    b[0..4].copy_from_slice(&RCF1_MAGIC);
    b[4] = RCF1_VERSION;
    // b[5] pad, zero, CRC-covered.
    let len = persistable(cfg)
        .encode(&mut b[FRAME_OFFSET..FRAME_OFFSET + MAX_SETTINGS_LEN])
        .unwrap_or(0);
    b[6..8].copy_from_slice(&(len as u16).to_le_bytes());
    let crc = crc32(&b[0..RACE_CONFIG_RECORD_LEN - 4]);
    b[RACE_CONFIG_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());
    b
}

/// Decode the record. Fail-closed like every other record on the config page:
/// too short, the wrong magic or wrapper version, a declared frame length past
/// the body, a torn write, or a body the settings decoder refuses all read as
/// "no saved race config" — the watch keeps whatever defaults it booted with,
/// never a half-applied push.
///
/// The result is filtered through [`persistable`] rather than refused when it
/// carries something it should not: a record from a build whose persistable set
/// was wider must cost the runner only the field that left the set, not the
/// whole configuration.
pub fn decode(bytes: &[u8]) -> Option<WatchSettings> {
    if bytes.len() < RACE_CONFIG_RECORD_LEN || bytes[0..4] != RCF1_MAGIC || bytes[4] != RCF1_VERSION
    {
        return None;
    }
    let stored = u32::from_le_bytes([
        bytes[RACE_CONFIG_RECORD_LEN - 4],
        bytes[RACE_CONFIG_RECORD_LEN - 3],
        bytes[RACE_CONFIG_RECORD_LEN - 2],
        bytes[RACE_CONFIG_RECORD_LEN - 1],
    ]);
    if crc32(&bytes[0..RACE_CONFIG_RECORD_LEN - 4]) != stored {
        return None;
    }
    let len = usize::from(u16::from_le_bytes([bytes[6], bytes[7]]));
    if len > MAX_SETTINGS_LEN {
        return None;
    }
    let frame = &bytes[FRAME_OFFSET..FRAME_OFFSET + len];
    Some(persistable(&WatchSettings::decode(frame)?))
}

/// Whether persisting `next` would put different bytes on the page than
/// `current` already holds — the gate the persist path gives the config page.
///
/// Compared as the RECORD rather than with `PartialEq`, because a
/// [`WatchSettings`] holds floats and a pushed NaN QNH is never equal to
/// itself: a struct comparison would report a change on every repeated push of
/// one unchanged frame and erase the whole config page each time. The bytes are
/// what flash holds, so the bytes are what "changed" has to mean.
pub fn record_differs(current: &WatchSettings, next: &WatchSettings) -> bool {
    encode(current) != encode(next)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ice::IceCard;
    use crate::settings::{
        FuelCfg, GearCfg, GuidedRunId, PaceBandCfg, PacerGoalCfg, RacePhasesCfg,
    };
    use crate::settings_apply::{plan_apply, EffectKind};

    /// A frame with every field set, so a test that claims a field survives (or
    /// is dropped) is asserting against something that was actually there. An
    /// exhaustive struct literal on purpose: a new `WatchSettings` field is a
    /// compile error here, so the fixture cannot quietly stop being full.
    fn full() -> WatchSettings {
        WatchSettings {
            max_hr: Some(185),
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 12_600,
            }),
            gear: Some(GearCfg {
                baseline_m: 700_000.0,
                target_m: Some(800_000.0),
            }),
            zone_ceiling: Some(Some(3)),
            sea_level_pa: Some(101_325.0),
            fuel: Some(FuelCfg {
                drink_interval_s: 900,
                eat_interval_s: 1_800,
            }),
            pages: Some(0b1010),
            hide_empty_pages: Some(true),
            tz_offset_min: Some(-420),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(PaceBandCfg {
                fast_s_per_km: 300,
                slow_s_per_km: 420,
            })),
            race_phases: Some(RacePhasesCfg {
                distance_m: Some(42_195),
                goal_time_s: Some(12_600),
                preset: 0,
            }),
            guided_run: Some(GuidedRunId::new("easy-30")),
            resting_hr: Some(48),
            ice: Some(IceCard::new(
                "ALEX MORGAN",
                "O NEG",
                "PENICILLIN, ASTHMA",
                "JAMIE MORGAN",
                "+1 555 0134",
            )),
            auto_lap: Some(3),
            storm_alert: Some(Some(3.0)),
        }
    }

    /// How many fields a frame carries, counted off the wire's own presence
    /// bitfields rather than off a list kept here — the same oracle
    /// `settings_apply`'s routing test uses, so it grows with the format.
    fn present_field_count(s: &WatchSettings) -> usize {
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        s.encode(&mut buf).expect("the fixture encodes");
        (buf[5].count_ones() + buf[6].count_ones() + buf[7].count_ones()) as usize
    }

    #[test]
    fn persistable_drops_exactly_the_four_fields_with_a_home_of_their_own() {
        let kept = persistable(&full());
        assert_eq!(kept.pages, None);
        assert_eq!(kept.hide_empty_pages, None);
        assert_eq!(kept.ice, None);
        assert_eq!(kept.auto_lap, None);
        // Negative control: the fixture really did carry all four, so the four
        // assertions above are not passing on a frame that never had them.
        assert!(full().pages.is_some());
        assert!(full().hide_empty_pages.is_some());
        assert!(full().ice.is_some());
        assert!(full().auto_lap.is_some());
        // And exactly four went: every other field survived untouched.
        assert_eq!(present_field_count(&kept), present_field_count(&full()) - 4);
        assert_eq!(kept.max_hr, Some(185));
        assert_eq!(kept.sea_level_pa, Some(101_325.0));
        assert_eq!(kept.storm_alert, Some(Some(3.0)));
    }

    #[test]
    fn persistable_is_idempotent() {
        let once = persistable(&full());
        assert_eq!(persistable(&once), once);
    }

    #[test]
    fn a_record_round_trips_the_persistable_half_of_a_frame() {
        let record = encode(&full());
        assert_eq!(decode(&record), Some(persistable(&full())));
        // Negative control: the whole frame is NOT what comes back.
        assert_ne!(decode(&record), Some(full()));
    }

    #[test]
    fn an_erased_or_zeroed_page_reads_as_no_saved_config() {
        assert_eq!(decode(&[0xFF; RACE_CONFIG_RECORD_LEN]), None);
        assert_eq!(decode(&[0x00; RACE_CONFIG_RECORD_LEN]), None);
        // Negative control: a real record at the same length does decode, so
        // the two above are rejected for their content, not their size.
        assert!(decode(&encode(&full())).is_some());
    }

    #[test]
    fn a_bad_magic_or_wrapper_version_reads_as_no_saved_config() {
        for at in 0..4 {
            let mut b = encode(&full());
            b[at] ^= 0xFF;
            assert_eq!(decode(&b), None, "magic byte {at}");
        }
        let mut b = encode(&full());
        b[4] = RCF1_VERSION.wrapping_add(1);
        assert_eq!(decode(&b), None);
    }

    #[test]
    fn a_truncated_record_reads_as_no_saved_config() {
        let record = encode(&full());
        for cut in 0..RACE_CONFIG_RECORD_LEN {
            assert_eq!(decode(&record[..cut]), None, "prefix {cut}");
        }
        assert!(decode(&record).is_some(), "the whole record still decodes");
    }

    #[test]
    fn a_declared_length_past_the_body_reads_as_no_saved_config() {
        // The length field addresses inside the record, so a corrupt one must
        // not be able to reach past the CRC-covered body — and must not be
        // repaired into a shorter frame that decodes to a different config.
        for len in [
            MAX_SETTINGS_LEN + 1,
            RACE_CONFIG_RECORD_LEN,
            u16::MAX as usize,
        ] {
            let mut b = encode(&full());
            b[6..8].copy_from_slice(&(len as u16).to_le_bytes());
            let crc = crc32(&b[0..RACE_CONFIG_RECORD_LEN - 4]);
            b[RACE_CONFIG_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());
            assert_eq!(decode(&b), None, "declared length {len}");
        }
    }

    #[test]
    fn a_torn_write_reads_as_no_saved_config() {
        // Power lost partway through the record: the leading bytes landed on an
        // erased page and the rest is still 0xFF. The CRC is what catches it.
        let record = encode(&full());
        for landed in [
            FRAME_OFFSET,
            RACE_CONFIG_RECORD_LEN / 2,
            RACE_CONFIG_RECORD_LEN - 4,
        ] {
            let mut torn = [0xFFu8; RACE_CONFIG_RECORD_LEN];
            torn[..landed].copy_from_slice(&record[..landed]);
            assert_eq!(decode(&torn), None, "{landed} bytes landed");
        }
    }

    #[test]
    fn a_record_carrying_a_non_persistable_field_drops_only_that_field() {
        // A record a build with a wider persistable set could have written: the
        // body is a full frame, ICE card and all. The card must not reach the
        // responder face from here — that path is `ICE1`'s — but the pacer goal
        // beside it must survive.
        let mut b = [0u8; RACE_CONFIG_RECORD_LEN];
        b[0..4].copy_from_slice(&RCF1_MAGIC);
        b[4] = RCF1_VERSION;
        let len = full()
            .encode(&mut b[FRAME_OFFSET..FRAME_OFFSET + MAX_SETTINGS_LEN])
            .expect("the full frame fits");
        b[6..8].copy_from_slice(&(len as u16).to_le_bytes());
        let crc = crc32(&b[0..RACE_CONFIG_RECORD_LEN - 4]);
        b[RACE_CONFIG_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());

        let out = decode(&b).expect("a well-formed record decodes");
        assert_eq!(out.ice, None);
        assert_eq!(out.auto_lap, None);
        assert_eq!(out.pacer, full().pacer);
        // Negative control: the body really did carry the card, so the drop is
        // this decoder's doing and not the fixture's.
        let body = WatchSettings::decode(&b[FRAME_OFFSET..FRAME_OFFSET + len]).expect("body");
        assert!(body.ice.is_some());
    }

    #[test]
    fn a_pushed_field_overrides_and_an_absent_one_leaves_the_stored_value() {
        let stored = persistable(&full());
        let push = WatchSettings {
            max_hr: Some(190),
            ..WatchSettings::default()
        };
        let next = merged(&stored, &push);
        assert_eq!(next.max_hr, Some(190), "the push wins its own field");
        assert_eq!(next.pacer, stored.pacer, "and disturbs nothing else");
        assert_eq!(next.fuel, stored.fuel);
        assert_eq!(next.sea_level_pa, stored.sea_level_pa);
        // Negative control: the stored value really was different, so the
        // override is observable.
        assert_ne!(stored.max_hr, Some(190));
    }

    #[test]
    fn merging_never_lets_a_push_smuggle_a_non_persistable_field_in() {
        let next = merged(&WatchSettings::default(), &full());
        assert_eq!(next.ice, None);
        assert_eq!(next.auto_lap, None);
        assert_eq!(next.pages, None);
        assert_eq!(next.hide_empty_pages, None);
        assert_eq!(next.max_hr, Some(185), "the rest of the push still lands");
    }

    #[test]
    fn an_explicit_disarm_is_stored_as_a_disarm_not_as_an_absence() {
        // `Some(None)` is the runner switching an alert off. Collapsing it to
        // `None` on the way to flash would restore a ceiling at the next boot
        // that they had turned off — the whole distinction the doubly-optional
        // fields carry, at the flash layer.
        let off = WatchSettings {
            zone_ceiling: Some(None),
            distance_interval_m: Some(None),
            time_interval_s: Some(None),
            pace_band: Some(None),
            guided_run: Some(None),
            storm_alert: Some(None),
            ..WatchSettings::default()
        };
        let back = decode(&encode(&off)).expect("the record decodes");
        assert_eq!(back, off);
        // Negative control: an absent field is a different record entirely.
        assert_ne!(back, WatchSettings::default());
    }

    #[test]
    fn a_restored_config_routes_through_the_same_guards_a_push_does() {
        // The restore path is `plan_apply`, so a stored value the wire's own
        // guard rejects is dropped exactly as it was on arrival — and the
        // fields beside it still land.
        let mut s = persistable(&full());
        s.sea_level_pa = Some(f32::NAN);
        let plan = plan_apply(&decode(&encode(&s)).expect("decodes"));
        let kinds: heapless::Vec<EffectKind, 32> = plan.iter().map(|e| e.kind()).collect();
        assert!(!kinds.contains(&EffectKind::SeaLevelPa));
        assert!(kinds.contains(&EffectKind::PacerGoal));
        assert!(kinds.contains(&EffectKind::MaxHr));
    }

    #[test]
    fn a_repeated_push_of_one_unchanged_frame_never_rewrites_the_page() {
        // The wear gate. A NaN QNH is not equal to itself, so a `PartialEq`
        // comparison would report a change on every push of the same frame and
        // erase the whole config page each time.
        let mut s = persistable(&full());
        s.sea_level_pa = Some(f32::NAN);
        let stored = merged(&WatchSettings::default(), &s);
        let again = merged(&stored, &s);
        assert!(!record_differs(&stored, &again));
        // Negative control: `PartialEq` really does disagree, which is why this
        // gate exists at all — and a genuine change is still reported.
        assert_ne!(stored, again);
        assert!(record_differs(
            &stored,
            &merged(
                &stored,
                &WatchSettings {
                    max_hr: Some(191),
                    ..WatchSettings::default()
                }
            )
        ));
    }

    #[test]
    fn a_frame_carrying_nothing_persistable_leaves_the_page_alone() {
        // A phone that pushes only an ICE card must not cost a page erase.
        let only_ice = WatchSettings {
            ice: full().ice,
            hide_empty_pages: Some(false),
            auto_lap: Some(1),
            pages: Some(0b11),
            ..WatchSettings::default()
        };
        let stored = WatchSettings::default();
        assert!(!record_differs(&stored, &merged(&stored, &only_ice)));
    }

    #[test]
    fn the_record_fits_the_config_page_alongside_every_other_record() {
        assert!(RACE_CONFIG_RECORD_LEN.is_multiple_of(4));
        assert_eq!(RACE_CONFIG_RECORD_LEN, FRAME_OFFSET + MAX_SETTINGS_LEN + 4);
        assert!(
            crate::flash_store::RACE_CONFIG_RECORD_OFFSET + RACE_CONFIG_RECORD_LEN
                <= crate::flash_store::CONFIG_LEN
        );
    }
}
