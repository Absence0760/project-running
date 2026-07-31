//! Tier-1 internal-flash run-store layout — the pure, host-tested half of the
//! `app/` flash driver (`app/src/run_flash.rs`).
//!
//! The nRF52840's 1 MB internal flash is tiny, so tier 1 reserves a small fixed
//! region of `SLOT_COUNT` equal-sized slots at the very top of flash, carved
//! out of both `app/memory.x` and `app/memory-ble.x`. Each finished run's blob
//! ([`crate::run_store`]) lives in one slot; a new run round-robins into the
//! next free slot, evicting the oldest when all are full. A full ultra needs
//! far more than this holds (see [`MAX_POINTS_PER_RUN`]) — that is the tier-2
//! external QSPI flash job, deliberately not solved here.
//!
//! Two invariants the [`SlotDir`] enforces and the rest of the run-sync vertical
//! depends on: a run is advertised or served only once it is **finished**, and a
//! run's successive flash writes **ping-pong** between two slots so the erase
//! window can never take the last good copy with it.
//!
//! Everything in this module is pure arithmetic plus a small in-RAM directory,
//! so it is `cargo test`-able on the host; the actual flash reads / erases /
//! writes live in the `app/` crate over embassy-nrf's NVMC.

use heapless::Vec;

use crate::run_store::{
    crc32, ManifestEntry, RunFooter, RunHeader, FLAG_FINISHED, FOOTER_CRC_OFFSET, FOOTER_LEN,
    FORMAT_VERSION, HEADER_LEN, MIN_FORMAT_VERSION, POINT_LEN,
};

/// One nRF52840 erase page (4 KiB) per run slot, so evicting a run is a single
/// page erase that never disturbs a neighbouring slot.
pub const SLOT_LEN: usize = 4096;

/// How many finished runs the tier-1 region holds at once.
pub const SLOT_COUNT: usize = 4;

/// Total reserved flash region. MUST equal the top-of-flash carve-out in BOTH
/// `app/memory.x` and `app/memory-ble.x`.
pub const REGION_LEN: usize = SLOT_LEN * SLOT_COUNT;

/// Track points that fit one slot: `HEADER + N*POINT + FOOTER <= SLOT_LEN`. At
/// roughly one accepted fix per second this is only a few minutes of a run —
/// the tier-1 internal-flash budget. A real ultra needs tier-2 external QSPI
/// flash; do not raise this to paper over that.
pub const MAX_POINTS_PER_RUN: u32 = ((SLOT_LEN - HEADER_LEN - FOOTER_LEN) / POINT_LEN) as u32;

/// Absolute flash offset of `slot` within a region beginning at `region_offset`.
pub const fn slot_offset(region_offset: u32, slot: usize) -> u32 {
    region_offset + (slot as u32) * (SLOT_LEN as u32)
}

/// One nRF52840 erase page reserved for the tiny persisted-config record, sat
/// immediately BELOW the run-store region (its absolute offset is one page under
/// [`crate::run_flash::REGION_OFFSET`] — see `app/src/run_flash::CONFIG_OFFSET`).
/// A dedicated page keeps a config rewrite — a single page erase — from ever
/// touching a run slot, and leaves every run-store slot offset undisturbed.
/// MUST match the config carve-out in BOTH `app/memory.x` and `app/memory-ble.x`.
pub const CONFIG_LEN: usize = SLOT_LEN;

/// Length of the fixed config record written at the base of the config page. A
/// multiple of the NVMC 4-byte write word, so it commits in one write.
pub const CONFIG_RECORD_LEN: usize = 12;

/// Version of the config-record wire format. Bumped only if the field layout
/// after the magic changes; an unrecognised version reads as "no saved config".
pub const CONFIG_VERSION: u8 = 1;

/// Magic prefixing a valid config record — distinguishes a written record from
/// an erased (all-`0xFF`) or zeroed page.
const CONFIG_MAGIC: [u8; 4] = *b"CFG1";

/// Bit 0 of the config flags byte: the hide-empty-pages setting has been
/// explicitly persisted (menu edit or phone push); clear = no stored choice,
/// the recorder keeps its default. Pre-§351 records wrote this byte as a
/// reserved zero, so they decode as "no stored choice" with no version bump.
pub const CONFIG_FLAG_HIDE_EMPTY_SET: u8 = 0b0000_0001;
/// Bit 1: the persisted hide-empty value itself (only meaningful when
/// [`CONFIG_FLAG_HIDE_EMPTY_SET`] is set).
pub const CONFIG_FLAG_HIDE_EMPTY_ON: u8 = 0b0000_0010;
/// Bit 2 (§353): an activity profile has been explicitly selected; its
/// discriminant lives in the record's profile byte. Pre-§353 records wrote
/// that byte as a reserved zero with this bit clear, so they decode as "no
/// profile" with no version bump — the §351 flags-byte drill again.
pub const CONFIG_FLAG_PROFILE_SET: u8 = 0b0000_0100;
/// Bit 3 (§374): an auto-lap trigger has been explicitly pushed; bits 4-6 carry
/// its [`crate::auto_lap::AutoLap::to_byte`] discriminant. Pre-§374 records left
/// all four clear, so they decode as "no stored trigger" and the recorder keeps
/// its default — the §351 flags-byte drill a third time.
pub const CONFIG_FLAG_AUTO_LAP_SET: u8 = 0b0000_1000;
const CONFIG_AUTO_LAP_MASK: u8 = 0b0111_0000;
const CONFIG_AUTO_LAP_SHIFT: u8 = 4;

const _: () =
    assert!(crate::auto_lap::AUTO_LAP_MAX_BYTE <= CONFIG_AUTO_LAP_MASK >> CONFIG_AUTO_LAP_SHIFT);

/// Bit 7 (§372): backyard-ultra mode is armed. No companion "set" bit, unlike
/// hide-empty: the default is off, so a clear bit already means exactly what
/// an unset choice means, and every pre-§372 record decodes as disarmed. **This
/// is the last free bit** — §374 took bits 3-6, so the setting after this one
/// needs a [`CONFIG_VERSION`] bump and a wider record.
pub const CONFIG_FLAG_BACKYARD_ON: u8 = 0b1000_0000;

/// The flags byte with an explicit hide-empty choice folded in — every other
/// bit (the profile marker, future flags) carried forward, so persisting one
/// setting can no longer erase another's.
pub fn set_hide_empty_flags(flags: u8, hide: bool) -> u8 {
    (flags & !CONFIG_FLAG_HIDE_EMPTY_ON)
        | CONFIG_FLAG_HIDE_EMPTY_SET
        | if hide { CONFIG_FLAG_HIDE_EMPTY_ON } else { 0 }
}

/// The persisted hide-empty choice carried by a flags byte, or `None` when
/// the record never stored one (every pre-§351 record).
pub fn hide_empty_from_flags(flags: u8) -> Option<bool> {
    (flags & CONFIG_FLAG_HIDE_EMPTY_SET != 0).then_some(flags & CONFIG_FLAG_HIDE_EMPTY_ON != 0)
}

/// The flags byte with the backyard-mode arm folded in, every other bit
/// carried forward — the [`set_hide_empty_flags`] rule.
pub fn set_backyard_flags(flags: u8, armed: bool) -> u8 {
    (flags & !CONFIG_FLAG_BACKYARD_ON) | if armed { CONFIG_FLAG_BACKYARD_ON } else { 0 }
}

/// Whether the persisted record has backyard-ultra mode armed (§372).
pub fn backyard_from_flags(flags: u8) -> bool {
    flags & CONFIG_FLAG_BACKYARD_ON != 0
}

/// The persisted profile byte carried by a record, or `None` when no profile
/// was ever selected (every pre-§353 record). The byte itself only speaks
/// through `profiles::ActivityProfile::from_byte`, so a CRC-valid but unknown
/// discriminant still reads as "no profile".
pub fn profile_from_flags(flags: u8, profile_byte: u8) -> Option<u8> {
    (flags & CONFIG_FLAG_PROFILE_SET != 0).then_some(profile_byte)
}

/// The flags byte with an explicit auto-lap trigger folded in — every other bit
/// carried forward, like [`set_hide_empty_flags`]. A discriminant wider than the
/// three-bit field is masked to fit; the const assert above is what keeps that
/// unreachable for a real rung.
pub fn set_auto_lap_flags(flags: u8, trigger_byte: u8) -> u8 {
    (flags & !CONFIG_AUTO_LAP_MASK)
        | CONFIG_FLAG_AUTO_LAP_SET
        | ((trigger_byte << CONFIG_AUTO_LAP_SHIFT) & CONFIG_AUTO_LAP_MASK)
}

/// The persisted auto-lap discriminant carried by a flags byte, or `None` when
/// the record never stored one (every pre-§374 record). The byte only speaks
/// through [`crate::auto_lap::AutoLap::from_byte`], so a CRC-valid but unknown
/// discriminant still reads as "no stored trigger".
pub fn auto_lap_from_flags(flags: u8) -> Option<u8> {
    (flags & CONFIG_FLAG_AUTO_LAP_SET != 0)
        .then_some((flags & CONFIG_AUTO_LAP_MASK) >> CONFIG_AUTO_LAP_SHIFT)
}

/// Encode the persisted-config record — `magic | version | gnss_mode | flags |
/// profile | crc32` — for the flash config page. The CRC covers every byte
/// before it, so a torn, erased, or garbage page fails [`decode_config`] and
/// the caller falls back to defaults (same fail-closed rule as
/// [`recover_slot`]).
pub fn encode_config(gnss_mode: u8, flags: u8, profile: u8) -> [u8; CONFIG_RECORD_LEN] {
    let mut buf = [0u8; CONFIG_RECORD_LEN];
    buf[0..4].copy_from_slice(&CONFIG_MAGIC);
    buf[4] = CONFIG_VERSION;
    buf[5] = gnss_mode;
    buf[6] = flags;
    buf[7] = profile;
    let crc = crc32(&buf[0..8]);
    buf[8..12].copy_from_slice(&crc.to_le_bytes());
    buf
}

/// Decode the persisted-config record, returning the stored `(gnss_mode,
/// flags, profile)` bytes, or `None` when the bytes are too short, carry the
/// wrong magic or version, or fail the CRC — an erased or corrupt page reads
/// as "no saved config". The mode byte itself is validated by the caller
/// ([`crate::gnss_mode::GnssMode::from_byte`]), so a CRC-valid but unknown
/// byte still falls back to the default; the flags byte likewise only speaks
/// through [`hide_empty_from_flags`] / [`profile_from_flags`], so an unknown
/// bit is ignored rather than misread.
pub fn decode_config(bytes: &[u8]) -> Option<(u8, u8, u8)> {
    if bytes.len() < CONFIG_RECORD_LEN {
        return None;
    }
    if bytes[0..4] != CONFIG_MAGIC {
        return None;
    }
    if bytes[4] != CONFIG_VERSION {
        return None;
    }
    let stored = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);
    if crc32(&bytes[0..8]) != stored {
        return None;
    }
    Some((bytes[5], bytes[6], bytes[7]))
}

/// Offset of the persisted BLE bond record within the config page — clear of
/// the [`CONFIG_RECORD_LEN`] config record at the base, word-aligned. The two
/// records share the page (one erase covers both), so a rewrite of either
/// must carry the other forward (`run_flash::rewrite_config_page`).
pub const BOND_RECORD_OFFSET: usize = 64;

/// Offset of the persisted waypoint record ([`crate::waypoints`] `WPT1`,
/// §357) within the config page — past the bond record's extent, word-
/// aligned, carried forward by the same shared-page rewrite.
pub const WAYPOINT_RECORD_OFFSET: usize = 128;

/// Offset of the persisted ICE / medical-ID record ([`crate::ice`] `ICE1`,
/// §358) within the config page — past the waypoint record's worst case,
/// word-aligned, carried forward by the same shared-page rewrite. A medic
/// reads the wrist of a watch that may have power-cycled, so the card cannot
/// live only in the RAM a `SET1` push fills.
pub const ICE_RECORD_OFFSET: usize = 256;

/// Offset of the persisted composed-screens record ([`crate::screens`] `SCR1`,
/// §364) within the config page — past the ICE card's extent, word-aligned,
/// carried forward by the same shared-page rewrite. A runner who built their
/// screens the night before a race must still have them after the battery pull
/// at the start line, so the set cannot live only in the RAM a push fills.
pub const SCREENS_RECORD_OFFSET: usize = 512;

const _: () = assert!(BOND_RECORD_OFFSET + BOND_RECORD_LEN <= WAYPOINT_RECORD_OFFSET);
const _: () = assert!(WAYPOINT_RECORD_OFFSET + crate::waypoints::MAX_WPT1_LEN <= ICE_RECORD_OFFSET);
const _: () = assert!(ICE_RECORD_OFFSET + crate::ice::ICE1_RECORD_LEN <= SCREENS_RECORD_OFFSET);
const _: () = assert!(SCREENS_RECORD_OFFSET + crate::screens::MAX_SCR1_LEN <= CONFIG_LEN);

/// `magic(4) | version(1) | enc_flags(1) | ediv(2) | rand(8) | ltk(16) |
/// addr_flags(1) | addr(6) | irk(16) | pad(1) | crc32(4)` — 60 bytes, a
/// multiple of the 4-byte NVMC write word.
pub const BOND_RECORD_LEN: usize = 60;

pub const BOND_VERSION: u8 = 1;

const BOND_MAGIC: [u8; 4] = *b"BND1";

/// The one persisted BLE bond (issue #598): everything the peripheral needs
/// to re-encrypt with a previously-paired phone across a power cycle. Plain
/// bytes — the `ble` task maps to/from the SoftDevice's key types, keeping
/// this crate hardware-free and the codec host-testable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BondRecord {
    /// The peer's encrypted diversifier + random number — the lookup key the
    /// central presents when re-establishing encryption.
    pub master_ediv: u16,
    pub master_rand: [u8; 8],
    /// The long-term key plus the SoftDevice's `ble_gap_enc_info_t` flag
    /// byte (lesc / auth / ltk_len bitfield), carried opaquely.
    pub ltk: [u8; 16],
    pub enc_flags: u8,
    /// The peer's identity address (`Address` flags byte + 6 address bytes)
    /// and identity-resolution key, for matching a resolvable private
    /// address on reconnect.
    pub addr_flags: u8,
    pub addr: [u8; 6],
    pub irk: [u8; 16],
}

impl BondRecord {
    pub fn encode(&self) -> [u8; BOND_RECORD_LEN] {
        let mut b = [0u8; BOND_RECORD_LEN];
        b[0..4].copy_from_slice(&BOND_MAGIC);
        b[4] = BOND_VERSION;
        b[5] = self.enc_flags;
        b[6..8].copy_from_slice(&self.master_ediv.to_le_bytes());
        b[8..16].copy_from_slice(&self.master_rand);
        b[16..32].copy_from_slice(&self.ltk);
        b[32] = self.addr_flags;
        b[33..39].copy_from_slice(&self.addr);
        b[39..55].copy_from_slice(&self.irk);
        // b[55] pad, zero, CRC-covered.
        let crc = crc32(&b[0..BOND_RECORD_LEN - 4]);
        b[BOND_RECORD_LEN - 4..].copy_from_slice(&crc.to_le_bytes());
        b
    }

    /// Fail-closed like [`decode_config`]: an erased page, wrong magic /
    /// version, or a torn write reads as "no bond" — the watch simply
    /// re-pairs, it never encrypts against a corrupt key.
    pub fn decode(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < BOND_RECORD_LEN || bytes[0..4] != BOND_MAGIC || bytes[4] != BOND_VERSION {
            return None;
        }
        let stored = u32::from_le_bytes([
            bytes[BOND_RECORD_LEN - 4],
            bytes[BOND_RECORD_LEN - 3],
            bytes[BOND_RECORD_LEN - 2],
            bytes[BOND_RECORD_LEN - 1],
        ]);
        if crc32(&bytes[0..BOND_RECORD_LEN - 4]) != stored {
            return None;
        }
        let mut rec = BondRecord {
            master_ediv: u16::from_le_bytes([bytes[6], bytes[7]]),
            master_rand: [0; 8],
            ltk: [0; 16],
            enc_flags: bytes[5],
            addr_flags: bytes[32],
            addr: [0; 6],
            irk: [0; 16],
        };
        rec.master_rand.copy_from_slice(&bytes[8..16]);
        rec.ltk.copy_from_slice(&bytes[16..32]);
        rec.addr.copy_from_slice(&bytes[33..39]);
        rec.irk.copy_from_slice(&bytes[39..55]);
        Some(rec)
    }
}

const _: () = assert!(BOND_RECORD_OFFSET >= CONFIG_RECORD_LEN);
const _: () = assert!(BOND_RECORD_OFFSET + BOND_RECORD_LEN <= CONFIG_LEN);
const _: () = assert!(BOND_RECORD_LEN.is_multiple_of(4));

/// Bytes to return for a phone chunk request: the smallest of what is left in
/// the blob from `offset`, the phone's `requested` length, and the notify
/// `mtu`. Zero once `offset` reaches (or passes) the blob end, so a request off
/// the end returns nothing rather than wrapping or over-reading.
pub fn chunk_len(size: u32, offset: u32, requested: u16, mtu: u16) -> u16 {
    if offset >= size {
        return 0;
    }
    let remaining = size - offset;
    remaining.min(requested as u32).min(mtu as u32) as u16
}

/// A run recovered from one slot's raw flash bytes at boot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RecoveredRun {
    pub run_seq: u32,
    pub size: u32,
    pub start_uptime_s: u32,
    /// The blob carried [`FLAG_FINISHED`]: it is a committed run rather than a
    /// mid-run checkpoint snapshot. A finished blob always supersedes an
    /// unfinished one for the same `run_seq` — see
    /// [`SlotDir::from_recovered`](SlotDir::from_recovered).
    pub finished: bool,
    /// The footer's elapsed seconds. Monotonic across a run's successive
    /// checkpoints (the totals only grow), so it orders two same-run blobs when
    /// neither is finished. Blob *size* cannot: a post-thinning checkpoint holds
    /// half the points of the one before it.
    pub elapsed_s: u32,
}

/// Recover the run persisted in one slot's raw flash bytes, or `None` if the
/// slot is erased, holds an unrecognised / newer-format blob, or holds a torn
/// write whose footer + CRC never line up.
///
/// A CRC-valid blob is reported whether or not it carries [`FLAG_FINISHED`] —
/// after a reset a mid-run checkpoint is a run that will never grow again, and
/// surfacing it is the entire purpose of checkpointing. The flag rides along on
/// [`RecoveredRun::finished`] so a run whose two ping-pong slots both survived
/// resolves to its authoritative copy. Refusing to advertise an unfinished blob
/// is the *live* recorder's job, held in RAM by [`SlotDir`], not this scan's.
///
/// The blob does not store its own length, so the footer position is found by
/// scanning each point-aligned offset for the footer magic *and* a CRC32 that
/// verifies everything up to that candidate footer's own CRC field. The CRC is
/// what makes this safe: a byte sequence inside the track data that happens to
/// equal the footer magic fails the CRC check, so the scan reads past it to the
/// real footer. (A false early stop would need a genuine CRC32 collision at a
/// point boundary — and since v3 the colliding window includes the decoy's own
/// would-be totals, so the scan is strictly harder to fool than it was.)
pub fn recover_slot(bytes: &[u8]) -> Option<RecoveredRun> {
    let header = RunHeader::decode(bytes)?;
    // v1 blobs already on flash (all-point, untagged) still recover; anything
    // NEWER than the current writer is a format we can't parse — fail closed.
    if !(MIN_FORMAT_VERSION..=FORMAT_VERSION).contains(&header.version) {
        return None;
    }
    for n in 0..=MAX_POINTS_PER_RUN {
        let footer_at = HEADER_LEN + n as usize * POINT_LEN;
        if footer_at + FOOTER_LEN > bytes.len() {
            break;
        }
        if let Some(footer) = RunFooter::decode(&bytes[footer_at..]) {
            if crc32(&bytes[..footer_at + FOOTER_CRC_OFFSET]) == footer.crc32 {
                return Some(RecoveredRun {
                    run_seq: header.run_seq,
                    size: (footer_at + FOOTER_LEN) as u32,
                    start_uptime_s: header.start_uptime_s,
                    finished: header.flags & FLAG_FINISHED != 0,
                    elapsed_s: footer.elapsed_s,
                });
            }
        }
    }
    None
}

/// Whether `new` is the copy to keep when both it and `old` recovered for the
/// same `run_seq`: a committed blob beats a mid-run checkpoint, then the later
/// elapsed time, then the larger blob. Equal on all three keeps `old`, so the
/// boot scan is order-independent.
fn supersedes(new: &RecoveredRun, old: &RecoveredRun) -> bool {
    (new.finished, new.elapsed_s, new.size) > (old.finished, old.elapsed_s, old.size)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SlotMeta {
    run_seq: u32,
    size: u32,
    start_uptime_s: u32,
    /// The phone has pulled this run's whole blob. Eviction sacrifices a synced
    /// run before a still-unsynced one, so a finished-but-unsynced run is not
    /// silently overwritten. RAM-only — not persisted across a reboot (that is a
    /// wire-format v2 job), so a run recovered from a prior power cycle starts
    /// unsynced and is protected until the phone re-pulls it.
    synced: bool,
    /// The run is no longer being written: it either committed this session
    /// ([`SlotDir::reserve_commit`]) or was recovered from a prior boot, whose
    /// recording ended with the power. **Only a finished slot is advertised in
    /// the manifest or resolved by [`SlotDir::find`]** — the live run's mid-run
    /// checkpoints must never reach a connected phone as a complete run, because
    /// the eventual commit would then re-advertise the same `run_seq` with
    /// larger, disagreeing bytes (and a transfer straddling a checkpoint would
    /// reassemble bytes from two different blobs).
    finished: bool,
    /// Write ordinal within this run: 1 for its first flash write, incrementing
    /// per checkpoint. A run's writes ping-pong between two slots, so the higher
    /// ordinal is the fresher copy and the lower one is what the next write may
    /// safely erase.
    write_no: u32,
    /// The bytes in this slot are a mid-run checkpoint, not a commit: the run
    /// ended without one and will never grow. Only ever set on a slot that is
    /// ALSO `finished`, i.e. at the two points a run can end that way — the boot
    /// scan ([`SlotDir::from_recovered`]) and a failed commit
    /// ([`SlotDir::commit_failed`]). A live run's checkpoints are never marked:
    /// the run may still commit, and while it records it is not a run at all as
    /// far as every consumer here is concerned.
    partial: bool,
}

/// In-RAM index of which slot holds which run, and which of those runs are
/// finished (and therefore advertisable).
///
/// Rebuilt each boot by [`from_recovered`](Self::from_recovered) scanning every
/// slot's flash bytes with [`recover_slot`], so a run recorded in a prior power
/// cycle is re-advertised rather than lost until overwritten. Run ids
/// (`run_seq`) are assigned by the caller (the `record` task), which is the
/// single writer and resumes numbering from [`next_run_seq`](Self::next_run_seq)
/// so a fresh run can't collide with a recovered one.
///
/// **Ping-pong.** A run's flash writes alternate between two slots
/// ([`reserve_checkpoint`](Self::reserve_checkpoint) /
/// [`reserve_commit`](Self::reserve_commit)): each write targets the slot that is
/// NOT holding the run's freshest copy, so the erase+write window can never
/// destroy the last good copy of the run-so-far. The cost is that a run in
/// progress reserves up to two of the [`SLOT_COUNT`] slots, so at most
/// `SLOT_COUNT - 2` finished runs are retained while recording. Raising that
/// ceiling is the tier-2 external-QSPI job, same as the point budget.
pub struct SlotDir {
    slots: [Option<SlotMeta>; SLOT_COUNT],
}

impl Default for SlotDir {
    fn default() -> Self {
        Self::new()
    }
}

impl SlotDir {
    pub const fn new() -> Self {
        Self {
            slots: [None; SLOT_COUNT],
        }
    }

    /// Rebuild the directory from what each physical slot actually holds on
    /// flash at boot (each entry the result of [`recover_slot`] on that slot),
    /// so a run recorded in a prior power cycle is advertised again instead of
    /// being lost until its slot is overwritten. Each recovered run keeps ITS
    /// OWN slot index — not round-robined — so [`find`](Self::find) maps it back
    /// to the flash offset its bytes physically occupy.
    ///
    /// **Reconciles the ping-pong pair.** A run interrupted mid-write leaves both
    /// of its slots populated: the copy that was being written (possibly torn,
    /// in which case [`recover_slot`] already rejected it) and the previous good
    /// one. When both recover, [`supersedes`] keeps the authoritative copy —
    /// committed over mid-run checkpoint, then later elapsed time — and frees the
    /// other slot, so one run is never advertised twice with disagreeing sizes.
    ///
    /// Every survivor is marked finished: the reset ended its recording, so even
    /// a mid-run checkpoint is as complete as the watch will ever know, and
    /// surfacing it is exactly what checkpointing exists for.
    ///
    /// **This is the only place an unfinished blob is promoted at boot, and it is
    /// a constructor.** It runs once, from the flash driver's own construction,
    /// before any run can be live — so every blob it sees is from a PRIOR power
    /// cycle and is terminal by the reset that orphaned it. The live recorder's
    /// checkpoints reach flash through
    /// [`reserve_checkpoint`](Self::reserve_checkpoint) instead, which hard-codes
    /// `finished: false` and is never re-run through this scan, so a run started
    /// after the promotion cannot inherit it. A survivor promoted here also
    /// carries [`SlotMeta::partial`] when its header lacked [`FLAG_FINISHED`],
    /// which is what [`pending_partial_count`](Self::pending_partial_count)
    /// surfaces on the wrist.
    pub fn from_recovered(slots: [Option<RecoveredRun>; SLOT_COUNT]) -> Self {
        let mut kept: [Option<RecoveredRun>; SLOT_COUNT] = [None; SLOT_COUNT];
        for (i, r) in slots.into_iter().enumerate() {
            let Some(r) = r else { continue };
            let held = kept
                .iter()
                .enumerate()
                .find_map(|(j, k)| k.filter(|k| k.run_seq == r.run_seq).map(|k| (j, k)));
            if let Some((j, prev)) = held {
                if !supersedes(&r, &prev) {
                    continue;
                }
                kept[j] = None;
            }
            kept[i] = Some(r);
        }
        let mut dir = Self::new();
        for (i, r) in kept.into_iter().enumerate() {
            dir.slots[i] = r.map(|r| SlotMeta {
                run_seq: r.run_seq,
                size: r.size,
                start_uptime_s: r.start_uptime_s,
                synced: false,
                finished: true,
                write_no: 0,
                partial: !r.finished,
            });
        }
        dir
    }

    /// The `run_seq` a freshly-started run should take so it never collides with
    /// a recovered run: one past the highest seq currently on flash, else 0.
    /// The record task seeds its counter with this at boot; because eviction
    /// picks the lowest seq, resuming above the max keeps recovered (older) runs
    /// as the first evicted.
    pub fn next_run_seq(&self) -> u32 {
        self.slots
            .iter()
            .flatten()
            .map(|m| m.run_seq)
            .max()
            .map_or(0, |s| s.wrapping_add(1))
    }

    /// Reserve the slot a mid-run checkpoint of `run_seq` writes into, leaving
    /// the run's freshest existing copy untouched, and return the slot index.
    ///
    /// The slot is recorded as NOT finished, so the snapshot is invisible to the
    /// manifest and to [`find`](Self::find) while the run is still recording. The
    /// caller erases + writes that slot and, if either fails,
    /// [`forget`](Self::forget)s it — the previous copy is still on flash either
    /// way, which is the whole point of alternating.
    pub fn reserve_checkpoint(&mut self, run_seq: u32, size: u32, start_uptime_s: u32) -> usize {
        let (slot, write_no) = self.next_write(run_seq);
        self.slots[slot] = Some(SlotMeta {
            run_seq,
            size,
            start_uptime_s,
            synced: false,
            finished: false,
            write_no,
            partial: false,
        });
        slot
    }

    /// Reserve the slot a finished run's commit writes into — again the slot NOT
    /// holding the run's freshest copy, so a torn commit leaves the newest
    /// checkpoint intact — and mark it finished.
    ///
    /// The checkpoint this commit supersedes keeps its directory entry: the
    /// caller releases it with [`commit_written`](Self::commit_written) once the
    /// blob is actually on flash. Between the reservation and that confirmation
    /// the checkpoint's bytes are the run's only durable copy, so dropping its
    /// entry up front would leave the directory claiming less than flash holds —
    /// and a commit that then failed would lose the run from RAM entirely until
    /// the next boot rescanned for it. A failed commit calls
    /// [`commit_failed`](Self::commit_failed) instead.
    pub fn reserve_commit(&mut self, run_seq: u32, size: u32, start_uptime_s: u32) -> usize {
        let (slot, write_no) = self.next_write(run_seq);
        self.slots[slot] = Some(SlotMeta {
            run_seq,
            size,
            start_uptime_s,
            synced: false,
            finished: true,
            write_no,
            partial: false,
        });
        slot
    }

    /// Release the slots a landed commit superseded, leaving the run held only by
    /// the slot the commit wrote. Called once those bytes are durable — the seal
    /// half of the seal-then-drop ordering [`reserve_commit`](Self::reserve_commit)
    /// sets up. The superseded bytes themselves are left alone; the next
    /// reservation erases that page when it takes it.
    pub fn commit_written(&mut self, slot: usize) {
        let Some(run_seq) = self.slots.get(slot).copied().flatten().map(|m| m.run_seq) else {
            return;
        };
        for (i, s) in self.slots.iter_mut().enumerate() {
            if i != slot && s.is_some_and(|m| m.run_seq == run_seq) {
                *s = None;
            }
        }
    }

    /// Drop a failed commit's reservation and hand the run back to the copy of it
    /// still on flash.
    ///
    /// The commit ended the recording, so — exactly as the boot scan treats a
    /// survivor ([`from_recovered`](Self::from_recovered)) — a surviving
    /// checkpoint is as complete as the watch will ever know and becomes
    /// advertisable. Merely [`forget`](Self::forget)ting the target would leave
    /// that checkpoint unreachable until a reboot rediscovered it, even though
    /// its bytes never moved.
    pub fn commit_failed(&mut self, slot: usize) {
        let run_seq = self.slots.get(slot).copied().flatten().map(|m| m.run_seq);
        self.forget(slot);
        let Some(run_seq) = run_seq else { return };
        for s in self.slots.iter_mut().flatten() {
            if s.run_seq == run_seq {
                s.finished = true;
                s.partial = true;
            }
        }
    }

    /// Mark a finished run as fully pulled by the phone, so a later reservation
    /// evicts it before a still-unsynced run. No-op if the id isn't held.
    pub fn mark_synced(&mut self, run_seq: u32) {
        for s in self.slots.iter_mut().flatten() {
            if s.run_seq == run_seq {
                s.synced = true;
            }
        }
    }

    /// The slot the next flash write for `run_seq` targets, and the write ordinal
    /// to stamp on it.
    ///
    /// Once the run holds both of its ping-pong slots the target is the STALER of
    /// the two (lowest `write_no`), so the erase can only ever destroy the copy
    /// we no longer need. Before that it is a fresh slot — the run's first write
    /// has nothing to protect, and its second must not land on top of its first.
    fn next_write(&self, run_seq: u32) -> (usize, u32) {
        let mut held = 0;
        let mut latest = 0;
        let mut stalest: Option<(usize, u32)> = None;
        for (i, m) in self
            .slots
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.map(|m| (i, m)))
        {
            if m.run_seq != run_seq {
                continue;
            }
            held += 1;
            latest = latest.max(m.write_no);
            if stalest.is_none_or(|(_, no)| m.write_no < no) {
                stalest = Some((i, m.write_no));
            }
        }
        let slot = match stalest {
            Some((i, _)) if held >= 2 => i,
            _ => self.victim(run_seq),
        };
        (slot, latest.saturating_add(1))
    }

    /// Choose the slot a new reservation takes: the first free slot, else an
    /// eviction victim. Never a slot holding `keep_run` — that is the run being
    /// written, and its other copy is the fallback a torn write relies on.
    fn victim(&self, keep_run: u32) -> usize {
        for (i, s) in self.slots.iter().enumerate() {
            if s.is_none() {
                return i;
            }
        }
        // All full. Evict the oldest SYNCED run (lowest seq the phone has already
        // pulled) so a finished-but-unsynced run is never silently overwritten
        // while any synced run still occupies a slot.
        let mut synced_victim: Option<(usize, u32)> = None;
        let mut oldest: Option<(usize, u32)> = None;
        for (i, m) in self
            .slots
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.map(|m| (i, m)))
        {
            if m.run_seq == keep_run {
                continue;
            }
            if m.synced && synced_victim.is_none_or(|(_, seq)| m.run_seq < seq) {
                synced_victim = Some((i, m.run_seq));
            }
            if oldest.is_none_or(|(_, seq)| m.run_seq < seq) {
                oldest = Some((i, m.run_seq));
            }
        }
        // Nothing synced: fall back to the oldest run overall — the region can't
        // hold more than SLOT_COUNT, so an unsynced run must go. Best-effort.
        synced_victim.or(oldest).map_or(0, |(i, _)| i)
    }

    /// Drop a slot's record — used when a checkpoint's flash write failed, so the
    /// directory never claims a slot that is now an erased page. A failed *commit*
    /// uses [`commit_failed`](Self::commit_failed), which additionally hands the
    /// run back to the checkpoint that survived it.
    pub fn forget(&mut self, slot: usize) {
        if slot < SLOT_COUNT {
            self.slots[slot] = None;
        }
    }

    /// How many finished runs the region holds — the length of the manifest. A
    /// live run's checkpoint slots are deliberately not counted: they are not
    /// runs the phone may pull.
    pub fn run_count(&self) -> u8 {
        self.slots.iter().flatten().filter(|m| m.finished).count() as u8
    }

    /// How many of the advertised runs are a mid-run checkpoint the phone has not
    /// pulled yet — the runs whose recording ended with the power rather than with
    /// a stop, recovered by [`from_recovered`](Self::from_recovered) (or handed
    /// back by [`commit_failed`](Self::commit_failed)). The wrist marker's input:
    /// after a brown-out the idle face otherwise looks exactly like a normal boot,
    /// so the runner has no way to know the interrupted run is sitting on flash
    /// waiting to be synced.
    ///
    /// A subset of [`run_count`](Self::run_count) by construction — `partial` is
    /// only ever set together with `finished` — and it drops to zero as the phone
    /// pulls each one, so the marker clears itself rather than standing until the
    /// next reboot. A live run's checkpoints are never counted: they are not
    /// `partial` (the run may still commit) and not `finished`.
    pub fn pending_partial_count(&self) -> u8 {
        self.slots
            .iter()
            .flatten()
            .filter(|m| m.finished && m.partial && !m.synced)
            .count() as u8
    }

    /// Manifest entries for every committed run, in slot order.
    pub fn manifest(&self) -> Vec<ManifestEntry, SLOT_COUNT> {
        self.manifest_at(u32::MAX)
    }

    /// Manifest entries with each run's `start_uptime_s` clamped to the current
    /// `watch_uptime_s`.
    ///
    /// The watch has no RTC, so the phone dates a run as
    /// `now - (watch_uptime_s - start_uptime_s)`. A run recovered from a PRIOR
    /// power cycle carries a `start_uptime_s` from that boot's epoch, which can
    /// exceed the current (post-reboot) uptime and date the run in the FUTURE.
    /// Clamping `start_uptime_s <= watch_uptime_s` makes the offset non-negative,
    /// so a recovered run reads as "around this power-on" (under-aged) rather than
    /// in the future. The phone detects the clamp (offset shorter than the blob
    /// footer's elapsed time) and falls back to dating the run as ending now-ish
    /// via that elapsed time (`sim_watch_sync.dart`'s `payloadFromBlob`).
    /// Only FINISHED slots are listed: a mid-run checkpoint of the live run is
    /// held here so the next write knows to alternate away from it, never so the
    /// phone can pull it.
    pub fn manifest_at(&self, watch_uptime_s: u32) -> Vec<ManifestEntry, SLOT_COUNT> {
        let mut out = Vec::new();
        for s in self.slots.iter().flatten().filter(|m| m.finished) {
            let _ = out.push(ManifestEntry {
                run_seq: s.run_seq,
                size: s.size,
                start_uptime_s: s.start_uptime_s.min(watch_uptime_s),
            });
        }
        out
    }

    /// Locate a FINISHED run by its id → `(slot index, blob size)`. An
    /// in-progress run's checkpoint slot resolves to `None`, so it is never
    /// served over BLE and never marked synced, however the phone asks for it.
    pub fn find(&self, run_seq: u32) -> Option<(usize, u32)> {
        self.slots.iter().enumerate().find_map(|(i, s)| {
            s.and_then(|m| (m.run_seq == run_seq && m.finished).then_some((i, m.size)))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::run_store::{blob_len, verify_blob, RunWriter, TrackPoint, RUN_MAGIC};

    /// Build a full 4 KiB slot image: a finished run's blob followed by erased
    /// (0xFF) flash, exactly what a committed-then-power-cycled slot looks like.
    fn slot_image(run_seq: u32, start_uptime_s: u32, points: &[TrackPoint]) -> [u8; SLOT_LEN] {
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
        for p in points {
            w.push_point(p).expect("push");
        }
        let blob = w.finalize(1234, 600, 620).expect("finalize");
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..blob.len()].copy_from_slice(&blob);
        slot
    }

    fn a_point(t: u32) -> TrackPoint {
        TrackPoint {
            lat_e7: 400_150_200 + t as i32,
            lon_e7: -1_052_705_000,
            t_offset_s: t,
            ele_dm: Some(16_240),
            bpm: Some(120),
        }
    }

    /// A committed run recovered from a prior boot, for the cases where the
    /// ping-pong tiebreakers don't matter.
    fn recovered(run_seq: u32, size: u32, start_uptime_s: u32) -> RecoveredRun {
        RecoveredRun {
            run_seq,
            size,
            start_uptime_s,
            finished: true,
            elapsed_s: 0,
        }
    }

    #[test]
    fn max_points_blob_fits_one_slot() {
        assert_eq!(MAX_POINTS_PER_RUN, 253);
        assert!(blob_len(MAX_POINTS_PER_RUN) as usize <= SLOT_LEN);
        // One more point would overflow the slot.
        assert!(blob_len(MAX_POINTS_PER_RUN + 1) as usize > SLOT_LEN);
    }

    #[test]
    fn slot_offsets_are_page_spaced_within_the_region() {
        let base = 0x000F_C000;
        assert_eq!(slot_offset(base, 0), base);
        assert_eq!(slot_offset(base, 1), base + SLOT_LEN as u32);
        assert_eq!(slot_offset(base, 3), base + 3 * SLOT_LEN as u32);
        // The last slot still ends inside the region.
        assert_eq!(
            slot_offset(base, SLOT_COUNT - 1) + SLOT_LEN as u32,
            base + REGION_LEN as u32
        );
    }

    #[test]
    fn chunk_len_clamps_to_the_smallest_bound() {
        // Well inside the blob: the request is honoured.
        assert_eq!(chunk_len(1000, 0, 244, 244), 244);
        // Near the end: clamped to what remains.
        assert_eq!(chunk_len(1000, 900, 244, 244), 100);
        // The MTU is the smallest bound.
        assert_eq!(chunk_len(1000, 0, 244, 20), 20);
        // The request is the smallest bound.
        assert_eq!(chunk_len(1000, 0, 8, 244), 8);
    }

    #[test]
    fn chunk_len_is_zero_at_or_past_the_end() {
        assert_eq!(chunk_len(1000, 1000, 244, 244), 0);
        assert_eq!(chunk_len(1000, 1001, 244, 244), 0);
        assert_eq!(chunk_len(0, 0, 244, 244), 0);
    }

    #[test]
    fn place_fills_free_slots_in_order_then_evicts_oldest() {
        let mut dir = SlotDir::new();
        assert_eq!(dir.reserve_commit(0, 100, 10), 0);
        assert_eq!(dir.reserve_commit(1, 100, 11), 1);
        assert_eq!(dir.reserve_commit(2, 100, 12), 2);
        assert_eq!(dir.reserve_commit(3, 100, 13), 3);
        assert_eq!(dir.run_count(), 4);
        // Region full → the lowest-seq run (0, in slot 0) is evicted.
        assert_eq!(dir.reserve_commit(4, 100, 14), 0);
        assert_eq!(dir.run_count(), 4);
        assert_eq!(dir.find(0), None, "evicted run is gone");
        assert_eq!(dir.find(4), Some((0, 100)));
        assert_eq!(dir.find(1), Some((1, 100)));
    }

    #[test]
    fn checkpoints_ping_pong_between_two_slots_and_are_never_advertised() {
        // Rewriting ONE slot in place is what made a brownout mid-checkpoint blank
        // the slot and lose the whole run-so-far. Successive checkpoints must
        // alternate, so the erase can only ever land on the copy we no longer
        // need — and neither copy may be advertised while the run records.
        let mut dir = SlotDir::new();
        let s0 = dir.reserve_checkpoint(7, 100, 41);
        let s1 = dir.reserve_checkpoint(7, 260, 41);
        assert_ne!(s0, s1, "the second checkpoint must not erase the first");
        let s2 = dir.reserve_checkpoint(7, 400, 41);
        assert_eq!(
            s2, s0,
            "the third reuses the staler of the two, not a third slot"
        );
        let s3 = dir.reserve_checkpoint(7, 520, 41);
        assert_eq!(s3, s1, "and alternates back");

        assert_eq!(dir.find(7), None, "an in-progress run is never served");
        assert!(dir.manifest().is_empty(), "nor advertised");
        assert_eq!(dir.run_count(), 0, "nor counted as a stored run");
        assert_eq!(dir.next_run_seq(), 8, "but its id is still reserved");
    }

    #[test]
    fn a_commit_supersedes_the_checkpoints_and_lands_on_the_staler_slot() {
        let mut dir = SlotDir::new();
        let fresh = {
            dir.reserve_checkpoint(7, 100, 41);
            dir.reserve_checkpoint(7, 260, 41)
        };
        let committed = dir.reserve_commit(7, 400, 41);
        assert_ne!(
            committed, fresh,
            "the commit write must not erase the freshest checkpoint"
        );
        assert_eq!(
            dir.find(7),
            Some((committed, 400)),
            "the committed blob is what gets served"
        );
        assert_eq!(dir.run_count(), 1, "the checkpoints are not advertised");
        assert_eq!(dir.manifest().len(), 1, "and the run is advertised once");
        dir.commit_written(committed);
        assert_eq!(
            dir.find(7),
            Some((committed, 400)),
            "confirming the write changes nothing about what is served"
        );
        assert_eq!(dir.run_count(), 1);
    }

    #[test]
    fn a_commit_keeps_the_superseded_slot_until_the_write_is_confirmed() {
        // Seal, then drop. Between reserving the commit's slot and its bytes
        // landing, the superseded checkpoint is the run's only durable copy, so
        // the directory must go on owning that slot — releasing it up front made
        // the directory claim less than flash actually held for the whole window.
        let mut dir = SlotDir::new();
        dir.reserve_checkpoint(7, 100, 41);
        let fresh = dir.reserve_checkpoint(7, 260, 41);
        let committed = dir.reserve_commit(7, 400, 41);
        assert_ne!(committed, fresh);
        assert_ne!(
            dir.reserve_commit(8, 100, 50),
            fresh,
            "an unconfirmed commit has not freed the superseded slot"
        );
    }

    #[test]
    fn a_confirmed_commit_releases_exactly_the_superseded_slot() {
        let mut dir = SlotDir::new();
        dir.reserve_checkpoint(7, 100, 41);
        let fresh = dir.reserve_checkpoint(7, 260, 41);
        let committed = dir.reserve_commit(7, 400, 41);
        dir.commit_written(committed);
        assert_eq!(dir.find(7), Some((committed, 400)));
        assert_eq!(dir.run_count(), 1);
        assert_eq!(
            dir.reserve_commit(8, 100, 50),
            fresh,
            "the one released slot is the first free one the next run takes"
        );
        assert_eq!(dir.find(7), Some((committed, 400)), "and only that one");
    }

    #[test]
    fn a_failed_commit_hands_the_run_back_to_the_checkpoint_still_on_flash() {
        // The commit's erase or write failed, so its slot is now a blank page —
        // but the checkpoint it superseded never moved. The run ended with that
        // commit, so the surviving snapshot is as complete as the watch will ever
        // know and must be servable now, not only after a reboot rescans flash.
        let mut dir = SlotDir::new();
        dir.reserve_checkpoint(7, 100, 41);
        let fresh = dir.reserve_checkpoint(7, 260, 41);
        let committed = dir.reserve_commit(7, 400, 41);
        dir.commit_failed(committed);
        assert_eq!(
            dir.find(7),
            Some((fresh, 260)),
            "the surviving checkpoint is what the phone may pull"
        );
        assert_eq!(dir.run_count(), 1);
        assert_eq!(dir.manifest().len(), 1);
        assert_eq!(dir.manifest()[0].size, 260);
    }

    #[test]
    fn a_failed_commit_of_a_checkpoint_free_run_leaves_nothing_behind() {
        // No checkpoint ever fired, so a failed commit really did lose the run:
        // nothing of it is on flash and nothing may be advertised.
        let mut dir = SlotDir::new();
        let slot = dir.reserve_commit(7, 400, 41);
        dir.commit_failed(slot);
        assert_eq!(dir.find(7), None);
        assert_eq!(dir.run_count(), 0);
        assert_eq!(
            dir.reserve_commit(8, 100, 50),
            slot,
            "and the slot is free again"
        );
    }

    #[test]
    fn confirming_a_slot_the_directory_does_not_hold_is_a_no_op() {
        let mut dir = SlotDir::new();
        let slot = dir.reserve_commit(7, 100, 41);
        dir.commit_written(SLOT_COUNT);
        dir.commit_failed(SLOT_COUNT + 3);
        dir.commit_written(slot + 1);
        dir.commit_failed(slot + 1);
        assert_eq!(dir.find(7), Some((slot, 100)), "the held run is untouched");
        assert_eq!(dir.run_count(), 1);
    }

    #[test]
    fn a_checkpoint_free_run_commits_into_one_slot() {
        // A run short enough that no checkpoint ever fired costs exactly one slot,
        // as it always did — the two-slot cost is only paid while recording.
        let mut a = SlotDir::new();
        let mut b = SlotDir::new();
        assert_eq!(a.reserve_commit(3, 100, 10), b.reserve_commit(3, 100, 10));
        assert_eq!(a.find(3), b.find(3));
        assert_eq!(a.run_count(), 1);
    }

    #[test]
    fn a_recording_run_never_evicts_its_own_other_copy() {
        // Region full of finished runs, then a run starts checkpointing. Each
        // reservation must sacrifice someone else's slot — never the sibling
        // holding this run's only good copy.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            dir.reserve_commit(seq, 100, seq);
            dir.mark_synced(seq);
        }
        let first = dir.reserve_checkpoint(9, 100, 500);
        let second = dir.reserve_checkpoint(9, 200, 500);
        assert_ne!(first, second);
        // Two slots of history were spent to hold the live run's pair — the
        // explicit price of never losing the run in progress to a torn write.
        assert_eq!(dir.run_count(), (SLOT_COUNT - 2) as u8);
    }

    #[test]
    fn recover_slot_reads_back_a_checkpoint_blob_as_a_partial_run() {
        // A mid-run checkpoint (partial track + totals-so-far) written into a
        // slot and power-cycled recovers exactly like a finished run — the whole
        // point of checkpointing: a reset mid-run recovers a slightly-stale
        // partial run instead of nothing.
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 9, 77).expect("start");
        for t in 0..5 {
            w.push_point(&a_point(t)).expect("push");
        }
        let ckpt = w.checkpoint_blob(321, 200, 210).expect("checkpoint");
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..ckpt.len()].copy_from_slice(&ckpt);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 9,
                size: blob_len(5),
                start_uptime_s: 77,
                finished: false,
                elapsed_s: 210,
            }),
            "the partial run recovers with the totals-so-far, flagged unfinished"
        );
    }

    #[test]
    fn manifest_lists_every_committed_run() {
        let mut dir = SlotDir::new();
        dir.reserve_commit(7, blob_len(3), 41);
        dir.reserve_commit(8, blob_len(5), 700);
        let m = dir.manifest();
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].run_seq, 7);
        assert_eq!(m[0].size, blob_len(3));
        assert_eq!(m[0].start_uptime_s, 41);
        assert_eq!(m[1].run_seq, 8);
    }

    #[test]
    fn forget_removes_a_slot_from_the_directory() {
        let mut dir = SlotDir::new();
        let slot = dir.reserve_commit(7, 100, 41);
        assert_eq!(dir.find(7), Some((slot, 100)));
        dir.forget(slot);
        assert_eq!(dir.find(7), None);
        assert_eq!(dir.run_count(), 0);
        // The freed slot is reused first.
        assert_eq!(dir.reserve_commit(9, 200, 50), slot);
    }

    #[test]
    fn recover_slot_reads_back_a_finished_run() {
        let pts = [a_point(0), a_point(1), a_point(2)];
        let slot = slot_image(7, 41, &pts);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 7,
                size: blob_len(3),
                start_uptime_s: 41,
                finished: true,
                elapsed_s: 620,
            }),
            "the footer is found past the erased 0xFF tail and the size is the blob, not the slot"
        );
    }

    #[test]
    fn recover_slot_reads_back_the_max_length_run() {
        let pts: heapless::Vec<TrackPoint, { MAX_POINTS_PER_RUN as usize }> =
            (0..MAX_POINTS_PER_RUN).map(a_point).collect();
        let slot = slot_image(3, 9, &pts);
        let r = recover_slot(&slot).expect("max-length run recovers");
        assert_eq!(r.run_seq, 3);
        assert_eq!(r.size, blob_len(MAX_POINTS_PER_RUN));
    }

    #[test]
    fn recover_slot_rejects_an_erased_slot() {
        assert_eq!(recover_slot(&[0xFFu8; SLOT_LEN]), None);
        assert_eq!(recover_slot(&[0x00u8; SLOT_LEN]), None);
    }

    #[test]
    fn recover_slot_rejects_a_never_finalised_blob() {
        // Header + points but no footer (power lost mid-run): the tail past the
        // points is erased 0xFF, so no footer magic + CRC ever matches.
        let mut staged: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        staged
            .extend_from_slice(
                &RunHeader {
                    version: FORMAT_VERSION,
                    flags: 0,
                    run_seq: 5,
                    start_uptime_s: 12,
                }
                .encode(),
            )
            .unwrap();
        for t in 0..4 {
            staged.extend_from_slice(&a_point(t).encode()).unwrap();
        }
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..staged.len()].copy_from_slice(&staged);
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_rejects_a_newer_format_version() {
        let mut slot = slot_image(7, 41, &[a_point(0)]);
        slot[4] = FORMAT_VERSION + 1; // header version byte
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_reads_past_footer_magic_inside_point_data() {
        // A track point whose first bytes equal the footer magic "END1" must not
        // fool the scan: the CRC at that offset won't match, so recovery reads
        // on to the real footer. lat_e7's LE bytes are the point's first four.
        let magic_lat = i32::from_le_bytes(*b"END1");
        let sneaky = TrackPoint {
            lat_e7: magic_lat,
            lon_e7: 5,
            t_offset_s: 0,
            ele_dm: None,
            bpm: None,
        };
        let pts = [sneaky, a_point(1), a_point(2)];
        let slot = slot_image(21, 8, &pts);
        // Sanity: the decoy footer magic really is sitting at the point-0 offset.
        assert_eq!(&slot[HEADER_LEN..HEADER_LEN + 4], b"END1");
        let r = recover_slot(&slot).expect("recovers despite the decoy magic");
        assert_eq!(r.run_seq, 21);
        assert_eq!(r.size, blob_len(3), "found the real footer, not the decoy");
    }

    #[test]
    fn from_recovered_places_runs_at_their_own_slots() {
        let mut slots = [None; SLOT_COUNT];
        slots[0] = Some(recovered(5, blob_len(3), 40));
        slots[2] = Some(recovered(9, blob_len(7), 900));
        let dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.run_count(), 2);
        // Each run maps back to the physical slot its bytes occupy.
        assert_eq!(dir.find(5), Some((0, blob_len(3))));
        assert_eq!(dir.find(9), Some((2, blob_len(7))));
        let m = dir.manifest();
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].run_seq, 5);
        assert_eq!(m[1].run_seq, 9);
    }

    #[test]
    fn from_recovered_keeps_one_copy_of_a_ping_ponged_run() {
        // Both of a run's ping-pong slots survived the reset. Advertising both
        // would offer the phone one run_seq twice at two different sizes.
        for (a, b) in [(0usize, 2usize), (2, 0)] {
            let mut slots = [None; SLOT_COUNT];
            slots[a] = Some(RecoveredRun {
                run_seq: 7,
                size: 200,
                start_uptime_s: 41,
                finished: false,
                elapsed_s: 100,
            });
            slots[b] = Some(RecoveredRun {
                run_seq: 7,
                size: 400,
                start_uptime_s: 41,
                finished: false,
                elapsed_s: 200,
            });
            let dir = SlotDir::from_recovered(slots);
            assert_eq!(dir.run_count(), 1, "scan order {a} then {b}");
            assert_eq!(
                dir.find(7),
                Some((b, 400)),
                "the later-elapsed checkpoint wins, whichever slot it sits in"
            );
        }
    }

    #[test]
    fn from_recovered_prefers_a_committed_blob_over_a_longer_checkpoint() {
        // Thinning means a commit can be SHORTER than an earlier checkpoint of the
        // same run, so the finished flag has to outrank both size and elapsed time.
        let mut slots = [None; SLOT_COUNT];
        slots[0] = Some(RecoveredRun {
            run_seq: 7,
            size: 4_000,
            start_uptime_s: 41,
            finished: false,
            elapsed_s: 9_999,
        });
        slots[1] = Some(RecoveredRun {
            run_seq: 7,
            size: 100,
            start_uptime_s: 41,
            finished: true,
            elapsed_s: 1,
        });
        let dir = SlotDir::from_recovered(slots);
        assert_eq!(
            dir.find(7),
            Some((1, 100)),
            "the committed blob is authoritative"
        );
        assert_eq!(dir.run_count(), 1);
    }

    /// A mid-run checkpoint of `run_seq` recovered from a prior power cycle.
    fn recovered_partial(run_seq: u32, size: u32, start_uptime_s: u32) -> RecoveredRun {
        RecoveredRun {
            run_seq,
            size,
            start_uptime_s,
            finished: false,
            elapsed_s: 900,
        }
    }

    #[test]
    fn from_recovered_counts_only_the_unfinished_survivors_as_pending() {
        // Both are advertised — the reset ended both recordings — but only the
        // one that never got its commit is the run the runner needs telling
        // about: the other ended with a stop they made themselves.
        let mut slots = [None; SLOT_COUNT];
        slots[0] = Some(recovered(5, blob_len(3), 40));
        slots[2] = Some(recovered_partial(9, blob_len(7), 900));
        let dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.run_count(), 2);
        assert_eq!(dir.pending_partial_count(), 1);
        assert_eq!(dir.find(9), Some((2, blob_len(7))), "and it is servable");
    }

    #[test]
    fn a_pending_partial_clears_once_the_phone_has_pulled_it() {
        // The marker has to retire itself. Standing until the next reboot would
        // make it a permanent decoration rather than a signal.
        let mut slots = [None; SLOT_COUNT];
        slots[1] = Some(recovered_partial(4, blob_len(9), 60));
        let mut dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.pending_partial_count(), 1);
        dir.mark_synced(4);
        assert_eq!(dir.pending_partial_count(), 0);
        assert_eq!(dir.run_count(), 1, "still stored, just no longer pending");
    }

    #[test]
    fn a_run_started_after_a_reboot_never_inherits_the_boot_promotion() {
        // The boundary the whole design turns on. A blob recovered at boot may be
        // surfaced because no run was live when it was found; the run the runner
        // then starts must stay exactly as invisible as it was before the reboot,
        // however many checkpoints it writes. The promotion is the constructor's,
        // and the constructor does not run again.
        let mut slots = [None; SLOT_COUNT];
        slots[0] = Some(recovered_partial(7, blob_len(20), 41));
        let mut dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.find(7), Some((0, blob_len(20))));
        assert_eq!(dir.pending_partial_count(), 1);

        let seq = dir.next_run_seq();
        assert_eq!(seq, 8);
        dir.reserve_checkpoint(seq, 100, 500);
        dir.reserve_checkpoint(seq, 260, 500);
        assert_eq!(dir.find(seq), None, "the live run is not servable");
        assert_eq!(
            dir.manifest()
                .iter()
                .map(|e| e.run_seq)
                .collect::<Vec<u32, SLOT_COUNT>>()[..],
            [7][..],
            "nor advertised — only the recovered run is"
        );
        assert_eq!(dir.run_count(), 1);
        assert_eq!(
            dir.pending_partial_count(),
            1,
            "a live checkpoint is not a pending partial run"
        );

        // And when the new run does end properly it is advertised as a finished
        // run, not as another interrupted one.
        let slot = dir.reserve_commit(seq, 400, 500);
        dir.commit_written(slot);
        assert_eq!(dir.find(seq), Some((slot, 400)));
        assert_eq!(dir.run_count(), 2);
        assert_eq!(
            dir.pending_partial_count(),
            1,
            "still just the recovered one"
        );
    }

    #[test]
    fn a_failed_commit_leaves_the_run_pending_like_a_reboot_would() {
        // The run ended and its bytes are a checkpoint, which is the same state a
        // reboot would rebuild from those bytes — so the wrist must say the same
        // thing without waiting for one.
        let mut dir = SlotDir::new();
        dir.reserve_checkpoint(7, 100, 41);
        dir.reserve_checkpoint(7, 260, 41);
        assert_eq!(dir.pending_partial_count(), 0, "not while it records");
        let committed = dir.reserve_commit(7, 400, 41);
        assert_eq!(dir.pending_partial_count(), 0, "nor on the reservation");
        dir.commit_failed(committed);
        assert_eq!(dir.pending_partial_count(), 1);
        assert_eq!(dir.run_count(), 1);
    }

    #[test]
    fn a_landed_commit_is_never_pending() {
        let mut dir = SlotDir::new();
        dir.reserve_checkpoint(7, 100, 41);
        let committed = dir.reserve_commit(7, 400, 41);
        dir.commit_written(committed);
        assert_eq!(dir.run_count(), 1);
        assert_eq!(dir.pending_partial_count(), 0);
    }

    #[test]
    fn next_run_seq_resumes_past_the_highest_recovered() {
        assert_eq!(SlotDir::new().next_run_seq(), 0);
        let mut slots = [None; SLOT_COUNT];
        slots[0] = Some(recovered(5, 100, 40));
        slots[3] = Some(recovered(9, 100, 90));
        let dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.next_run_seq(), 10);
    }

    #[test]
    fn a_new_run_after_recovery_evicts_the_oldest_recovered() {
        // All four slots recovered with seqs 0..=3; a fresh run resumes at 4 and,
        // the region being full, evicts the lowest seq (the oldest recovered).
        let slots = [
            Some(recovered(0, 100, 1)),
            Some(recovered(1, 100, 2)),
            Some(recovered(2, 100, 3)),
            Some(recovered(3, 100, 4)),
        ];
        let mut dir = SlotDir::from_recovered(slots);
        let seq = dir.next_run_seq();
        assert_eq!(seq, 4);
        assert_eq!(dir.reserve_commit(seq, 200, 5), 0, "evicts slot 0 (seq 0)");
        assert_eq!(dir.find(0), None);
        assert_eq!(dir.find(4), Some((0, 200)));
    }

    #[test]
    fn recover_ignores_a_zeroed_magic() {
        // Guard that recovery keys on the magic, not just non-erased bytes.
        assert_ne!(RUN_MAGIC, [0u8; 4]);
    }

    /// A CRC-internally-consistent blob at an arbitrary header `version`, so a
    /// test can present exactly what a future firmware would write: a valid
    /// footer whose CRC covers a header carrying a version we don't understand.
    /// Only a v2-or-later writer stamps [`FLAG_FINISHED`] — byte 5 was reserved
    /// and left zero in v1, which is why a v1 commit is indistinguishable from a
    /// v1 checkpoint.
    fn slot_image_version(
        version: u8,
        run_seq: u32,
        start_uptime_s: u32,
        points: &[TrackPoint],
    ) -> [u8; SLOT_LEN] {
        let mut prefix: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        prefix
            .extend_from_slice(
                &RunHeader {
                    version,
                    flags: FLAG_FINISHED,
                    run_seq,
                    start_uptime_s,
                }
                .encode(),
            )
            .unwrap();
        for p in points {
            prefix.extend_from_slice(&p.encode()).unwrap();
        }
        let mut footer = RunFooter {
            distance_m: 1234,
            moving_s: 600,
            elapsed_s: 620,
            crc32: 0,
        }
        .encode();
        prefix
            .extend_from_slice(&footer[..FOOTER_CRC_OFFSET])
            .unwrap();
        footer[FOOTER_CRC_OFFSET..].copy_from_slice(&crc32(&prefix).to_le_bytes());
        prefix.truncate(prefix.len() - FOOTER_CRC_OFFSET);
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..prefix.len()].copy_from_slice(&prefix);
        slot[prefix.len()..prefix.len() + FOOTER_LEN].copy_from_slice(&footer);
        slot
    }

    #[test]
    fn recover_slot_reads_past_a_mid_track_decoy_magic() {
        // The decoy magic sits mid-run, not at point 0: the scan must still walk
        // past it (CRC mismatch there) and land on the true footer at the end.
        let sneaky = TrackPoint {
            lat_e7: i32::from_le_bytes(*b"END1"),
            lon_e7: 5,
            t_offset_s: 2,
            ele_dm: None,
            bpm: None,
        };
        let pts = [a_point(0), a_point(1), sneaky, a_point(3), a_point(4)];
        let slot = slot_image(30, 8, &pts);
        assert_eq!(
            &slot[HEADER_LEN + 2 * POINT_LEN..HEADER_LEN + 2 * POINT_LEN + 4],
            b"END1",
            "the decoy magic is planted at the point-2 boundary"
        );
        let r = recover_slot(&slot).expect("recovers past the mid-track decoy");
        assert_eq!(r.run_seq, 30);
        assert_eq!(r.size, blob_len(5), "found the real footer, not the decoy");
    }

    #[test]
    fn recover_slot_reads_past_a_decoy_magic_in_the_last_point() {
        // Nastiest placement: the decoy is the LAST point, so its would-be CRC
        // field overlaps the true footer's own magic bytes. The CRC still fails
        // there and the true footer one point later wins.
        let sneaky = TrackPoint {
            lat_e7: i32::from_le_bytes(*b"END1"),
            lon_e7: 9,
            t_offset_s: 2,
            ele_dm: None,
            bpm: None,
        };
        let pts = [a_point(0), a_point(1), sneaky];
        let slot = slot_image(31, 8, &pts);
        assert_eq!(
            &slot[HEADER_LEN + 2 * POINT_LEN..HEADER_LEN + 2 * POINT_LEN + 4],
            b"END1"
        );
        let r = recover_slot(&slot).expect("recovers past the last-point decoy");
        assert_eq!(r.run_seq, 31);
        assert_eq!(r.size, blob_len(3));
    }

    #[test]
    fn recover_slot_rejects_a_crc_valid_newer_version_blob() {
        // A future firmware writes a blob with an internally-correct CRC. The
        // version gate must reject it BEFORE the footer scan — the CRC being
        // valid is exactly why this can't lean on CRC failure to filter it.
        let pts = [a_point(0), a_point(1)];
        let newer = slot_image_version(FORMAT_VERSION + 1, 7, 41, &pts);
        assert!(
            verify_blob(&newer[..blob_len(2) as usize]),
            "the newer blob's CRC is valid"
        );
        assert_eq!(recover_slot(&newer), None, "rejected by the version gate");

        // Same builder at the understood version DOES recover, so the version is
        // the only thing that changed and the gate is what rejected the newer one.
        let ours = slot_image_version(FORMAT_VERSION, 7, 41, &pts);
        assert_eq!(
            recover_slot(&ours),
            Some(RecoveredRun {
                run_seq: 7,
                size: blob_len(2),
                start_uptime_s: 41,
                finished: true,
                elapsed_s: 620,
            })
        );
    }

    fn a_bond() -> BondRecord {
        BondRecord {
            master_ediv: 0xBEEF,
            master_rand: [1, 2, 3, 4, 5, 6, 7, 8],
            ltk: [0xAA; 16],
            enc_flags: 0b0000_0101,
            addr_flags: 0x02,
            addr: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
            irk: [0xCC; 16],
        }
    }

    #[test]
    fn bond_record_round_trips() {
        let rec = a_bond();
        assert_eq!(BondRecord::decode(&rec.encode()), Some(rec));
    }

    #[test]
    fn bond_record_rejects_erased_corrupt_and_wrong_version() {
        assert_eq!(BondRecord::decode(&[0xFF; BOND_RECORD_LEN]), None, "erased");
        assert_eq!(BondRecord::decode(&[0x00; BOND_RECORD_LEN]), None, "zeroed");
        let enc = a_bond().encode();
        assert_eq!(
            BondRecord::decode(&enc[..BOND_RECORD_LEN - 1]),
            None,
            "short"
        );
        let mut flipped = enc;
        flipped[20] ^= 0x01; // inside the LTK: a corrupt key must never load
        assert_eq!(BondRecord::decode(&flipped), None, "CRC catches a torn key");
        let mut newer = enc;
        newer[4] = BOND_VERSION + 1;
        assert_eq!(BondRecord::decode(&newer), None, "unknown version");
    }

    #[test]
    fn bond_and_config_records_share_the_page_without_overlap() {
        // Both records written into one config page image read back
        // independently — the layout invariant rewrite_config_page relies on.
        let mut page = [0xFFu8; CONFIG_LEN];
        page[..CONFIG_RECORD_LEN].copy_from_slice(&encode_config(
            2,
            set_hide_empty_flags(0, true),
            1,
        ));
        page[BOND_RECORD_OFFSET..BOND_RECORD_OFFSET + BOND_RECORD_LEN]
            .copy_from_slice(&a_bond().encode());
        assert_eq!(
            decode_config(&page),
            Some((2, set_hide_empty_flags(0, true), 1))
        );
        assert_eq!(
            BondRecord::decode(&page[BOND_RECORD_OFFSET..]),
            Some(a_bond())
        );
    }

    /// The whole shared page at once, every record written where
    /// `rewrite_config_page` puts it.
    ///
    /// The const asserts above prove the offsets do not overlap; this proves the
    /// decoders agree — each reads its own record from the middle of a populated
    /// page and none is fooled by a neighbour's bytes or by the erased gaps
    /// between them. `SCR1` sits last and is the one whose extent had not been
    /// exercised: it is handed the whole tail of the page, `0xFF` run-out and
    /// all, exactly as `read_screens` hands it the fixed-length flash read.
    #[test]
    fn every_config_page_record_reads_back_from_a_populated_page() {
        use crate::screens::{Layout, Screen, Screens};
        let mut page = [0xFFu8; CONFIG_LEN];
        page[..CONFIG_RECORD_LEN].copy_from_slice(&encode_config(1, 0, 0));
        page[BOND_RECORD_OFFSET..BOND_RECORD_OFFSET + BOND_RECORD_LEN]
            .copy_from_slice(&a_bond().encode());

        let set = Screens::from_slice(&[
            Screen::new(
                Layout::Duo,
                &[crate::face::Metric::Distance, crate::face::Metric::AvgPace],
            )
            .unwrap(),
            Screen::new(Layout::Single, &[crate::face::Metric::HeartRate]).unwrap(),
        ])
        .unwrap();
        let mut rec = [0u8; crate::screens::MAX_SCR1_LEN];
        let n = set.encode(&mut rec).unwrap();
        page[SCREENS_RECORD_OFFSET..SCREENS_RECORD_OFFSET + n].copy_from_slice(&rec[..n]);

        assert_eq!(decode_config(&page), Some((1, 0, 0)));
        assert_eq!(
            BondRecord::decode(&page[BOND_RECORD_OFFSET..]),
            Some(a_bond())
        );
        assert_eq!(Screens::decode(&page[SCREENS_RECORD_OFFSET..]), Some(set));
    }

    /// An erased page hands back no screens rather than a set of zero-byte
    /// metrics — the fail-closed boot a watch that has never been pushed gets.
    #[test]
    fn an_erased_page_yields_no_screens() {
        let page = [0xFFu8; CONFIG_LEN];
        assert_eq!(
            crate::screens::Screens::decode(&page[SCREENS_RECORD_OFFSET..]),
            None
        );
    }

    #[test]
    fn recover_slot_rejects_a_pre_v3_blob() {
        // A run committed by the v1/v2 firmware sits on a bench board's flash
        // across the upgrade. v3 moved the CRC window to take in the footer
        // totals, so those blobs cannot be re-checked without re-opening the
        // hole v3 closed: the version gate rejects them, the slot reads as
        // free, and the next run overwrites it (decisions §321).
        let pts = [a_point(0), a_point(1), a_point(2)];
        for version in 1..MIN_FORMAT_VERSION {
            let old = slot_image_version(version, 9, 17, &pts);
            assert_eq!(recover_slot(&old), None, "v{version} must not recover");
        }
    }

    #[test]
    fn recover_slot_rejects_a_half_written_header() {
        // Only the magic landed before power loss; the rest of the page is still
        // erased, so the version byte reads 0xFF and fails the gate.
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..4].copy_from_slice(&RUN_MAGIC);
        assert_eq!(recover_slot(&slot), None);

        // A fully-written header with nothing after it (zero points, no footer)
        // is a never-finalised slot and recovers nothing.
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..HEADER_LEN].copy_from_slice(
            &RunHeader {
                version: FORMAT_VERSION,
                flags: 0,
                run_seq: 2,
                start_uptime_s: 9,
            }
            .encode(),
        );
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_never_reads_out_of_bounds_on_a_short_slice() {
        // Slices too short to hold a header, or a header but no room for a
        // footer, must return None without panicking or over-reading.
        assert_eq!(recover_slot(&[]), None);
        assert_eq!(recover_slot(&[0xFFu8; 8]), None);
        assert_eq!(recover_slot(&[0xFFu8; HEADER_LEN]), None);

        let header = RunHeader {
            version: FORMAT_VERSION,
            flags: 0,
            run_seq: 1,
            start_uptime_s: 3,
        }
        .encode();
        // Header exactly, no bytes for a footer: the loop breaks on the first n.
        assert_eq!(recover_slot(&header), None);

        // Header + a footer magic but the footer itself is truncated (10 of 20
        // bytes). The `footer_at + FOOTER_LEN > len` guard must skip the decode
        // rather than slice past the end.
        let mut truncated: heapless::Vec<u8, 64> = heapless::Vec::new();
        truncated.extend_from_slice(&header).unwrap();
        truncated.extend_from_slice(b"END1123456").unwrap();
        assert_eq!(recover_slot(&truncated), None);
    }

    #[test]
    fn recover_slot_reads_back_a_zero_point_run() {
        // Header + footer, no points: the footer sits at n == 0.
        let slot = slot_image(4, 15, &[]);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 4,
                size: blob_len(0),
                start_uptime_s: 15,
                finished: true,
                elapsed_s: 620,
            })
        );
    }

    #[test]
    fn next_run_seq_with_a_full_directory_resumes_above_the_max() {
        // Four recovered runs whose seqs are out of slot order: the next id is
        // one past the maximum, never one past slot 3's or the count.
        let slots = [
            Some(recovered(12, 100, 1)),
            Some(recovered(7, 100, 2)),
            Some(recovered(30, 100, 3)),
            Some(recovered(3, 100, 4)),
        ];
        let dir = SlotDir::from_recovered(slots);
        assert_eq!(dir.run_count(), 4);
        assert_eq!(dir.next_run_seq(), 31);
    }

    #[test]
    fn config_round_trips_every_mode_byte_and_flags() {
        for mode in [0u8, 1, 2] {
            for flags in [
                0u8,
                set_hide_empty_flags(0, true),
                set_hide_empty_flags(0, false),
                CONFIG_FLAG_PROFILE_SET,
            ] {
                for profile in [0u8, 3] {
                    let rec = encode_config(mode, flags, profile);
                    assert_eq!(rec.len(), CONFIG_RECORD_LEN);
                    assert_eq!(decode_config(&rec), Some((mode, flags, profile)));
                }
            }
        }
    }

    #[test]
    fn hide_empty_flags_round_trip_and_a_pre_351_record_reads_as_unset() {
        assert_eq!(
            hide_empty_from_flags(set_hide_empty_flags(0, true)),
            Some(true)
        );
        assert_eq!(
            hide_empty_from_flags(set_hide_empty_flags(0, false)),
            Some(false)
        );
        // Pre-§351 records wrote byte 6 as a reserved zero — they must decode
        // (same magic, same version, CRC still valid) and read as "no stored
        // choice", not as a confident OFF.
        let old = encode_config(1, 0, 0);
        assert_eq!(decode_config(&old), Some((1, 0, 0)));
        assert_eq!(hide_empty_from_flags(0), None);
    }

    #[test]
    fn setting_one_flag_carries_the_others_forward() {
        // §353's whole point: persisting hide-empty must not erase the stored
        // profile marker, and vice versa — the flags byte is shared state.
        let with_profile = CONFIG_FLAG_PROFILE_SET;
        let both = set_hide_empty_flags(with_profile, true);
        assert_eq!(hide_empty_from_flags(both), Some(true));
        assert_eq!(profile_from_flags(both, 2), Some(2));
        // Flipping hide-empty off keeps the profile marker standing.
        let flipped = set_hide_empty_flags(both, false);
        assert_eq!(hide_empty_from_flags(flipped), Some(false));
        assert_eq!(profile_from_flags(flipped, 2), Some(2));
        // And §372's arm joins them without disturbing either.
        let armed = set_backyard_flags(flipped, true);
        assert!(backyard_from_flags(armed));
        assert_eq!(hide_empty_from_flags(armed), Some(false));
        assert_eq!(profile_from_flags(armed, 2), Some(2));
        let disarmed = set_hide_empty_flags(armed, true);
        assert!(backyard_from_flags(disarmed), "hide-empty kept the arm");
        assert!(!backyard_from_flags(set_backyard_flags(disarmed, false)));
    }

    #[test]
    fn a_pre_372_record_reads_as_disarmed_rather_than_as_no_choice() {
        // Unlike hide-empty there is no companion "set" bit: backyard mode's
        // default IS off, so a clear bit already says everything an unset
        // choice would, and every record written before §372 decodes as a
        // watch that is not in a backyard.
        assert!(!backyard_from_flags(0));
        assert!(!backyard_from_flags(CONFIG_FLAG_PROFILE_SET));
        assert!(!backyard_from_flags(set_hide_empty_flags(0, true)));
    }

    #[test]
    fn profile_flags_round_trip_and_a_pre_353_record_reads_as_unset() {
        assert_eq!(profile_from_flags(CONFIG_FLAG_PROFILE_SET, 3), Some(3));
        // Pre-§353 records wrote the profile byte as a reserved zero with the
        // marker clear — "no profile", never a confident RUN.
        assert_eq!(profile_from_flags(0, 0), None);
        assert_eq!(profile_from_flags(set_hide_empty_flags(0, true), 0), None);
    }

    #[test]
    fn auto_lap_flags_round_trip_and_a_pre_374_record_reads_as_unset() {
        use crate::auto_lap::AutoLap;
        for t in [
            AutoLap::Off,
            AutoLap::Km1,
            AutoLap::Mi1,
            AutoLap::Km5,
            AutoLap::Mi5,
            AutoLap::Min5,
            AutoLap::Min10,
            AutoLap::Min30,
        ] {
            let flags = set_auto_lap_flags(0, t.to_byte());
            assert_eq!(auto_lap_from_flags(flags), Some(t.to_byte()));
            assert_eq!(
                AutoLap::from_byte(auto_lap_from_flags(flags).unwrap()),
                Some(t)
            );
            // A stored Off must not read as "no stored trigger": the runner
            // turning auto-lap off is a choice a reboot has to honour, not the
            // absence of one.
            assert!(flags & CONFIG_FLAG_AUTO_LAP_SET != 0);
        }
        // Pre-§374 records left bits 3-6 clear — "no stored trigger", never a
        // confident OFF.
        assert_eq!(auto_lap_from_flags(0), None);
        assert_eq!(auto_lap_from_flags(set_hide_empty_flags(0, true)), None);
    }

    #[test]
    fn persisting_the_trigger_carries_the_other_flags_forward() {
        // The shared flags byte again: writing a trigger must not erase the
        // hide-empty choice or the profile marker, and neither may erase it.
        let base = set_hide_empty_flags(CONFIG_FLAG_PROFILE_SET, true);
        let with_trigger = set_auto_lap_flags(base, 6);
        assert_eq!(auto_lap_from_flags(with_trigger), Some(6));
        assert_eq!(hide_empty_from_flags(with_trigger), Some(true));
        assert_eq!(profile_from_flags(with_trigger, 2), Some(2));
        let flipped = set_hide_empty_flags(with_trigger, false);
        assert_eq!(auto_lap_from_flags(flipped), Some(6));
        assert_eq!(hide_empty_from_flags(flipped), Some(false));
        // And a re-push of a different trigger replaces the discriminant
        // wholesale rather than OR-ing bits into the old one.
        assert_eq!(
            auto_lap_from_flags(set_auto_lap_flags(with_trigger, 1)),
            Some(1)
        );
        assert_eq!(
            auto_lap_from_flags(set_auto_lap_flags(with_trigger, 0)),
            Some(0)
        );
    }

    #[test]
    fn config_record_is_write_word_aligned_and_page_sized() {
        // NVMC writes a 4-byte word; the record must be a whole number of them,
        // and it must fit inside the one reserved erase page.
        assert_eq!(CONFIG_RECORD_LEN % 4, 0);
        const { assert!(CONFIG_RECORD_LEN <= CONFIG_LEN) }
        assert_eq!(CONFIG_LEN, SLOT_LEN, "config page is one erase page");
    }

    #[test]
    fn decode_config_rejects_an_erased_or_zeroed_page() {
        assert_eq!(decode_config(&[0xFFu8; CONFIG_LEN]), None);
        assert_eq!(decode_config(&[0x00u8; CONFIG_LEN]), None);
    }

    #[test]
    fn decode_config_rejects_a_corrupt_crc() {
        // Flip the stored mode byte without recomputing the CRC — exactly a
        // single-bit flash bit-rot — and the record must read as absent.
        let mut rec = encode_config(2, 0, 0);
        rec[5] ^= 0xFF;
        assert_eq!(decode_config(&rec), None);
        // Corrupting the CRC-covered flags byte is caught too.
        let mut rec = encode_config(1, set_hide_empty_flags(0, true), 0);
        rec[6] ^= 0x80;
        assert_eq!(decode_config(&rec), None);
    }

    #[test]
    fn decode_config_rejects_wrong_magic_and_version() {
        let mut rec = encode_config(1, 0, 0);
        rec[0] = b'X';
        assert_eq!(decode_config(&rec), None);
        let mut rec = encode_config(1, 0, 0);
        rec[4] = CONFIG_VERSION + 1;
        assert_eq!(decode_config(&rec), None);
    }

    #[test]
    fn decode_config_never_reads_out_of_bounds_on_a_short_slice() {
        assert_eq!(decode_config(&[]), None);
        assert_eq!(decode_config(&[0xFFu8; 4]), None);
        let rec = encode_config(0, 0, 0);
        assert_eq!(decode_config(&rec[..CONFIG_RECORD_LEN - 1]), None);
    }

    #[test]
    fn eviction_picks_the_lowest_seq_regardless_of_slot_index() {
        // The oldest run (lowest seq) is NOT in slot 0, so this proves eviction
        // keys on seq, not on a slot-0 bias.
        let slots = [
            Some(recovered(3, 100, 1)),
            Some(recovered(1, 100, 2)),
            Some(recovered(2, 100, 3)),
            Some(recovered(0, 100, 4)),
        ];
        let mut dir = SlotDir::from_recovered(slots);
        let seq = dir.next_run_seq();
        assert_eq!(seq, 4);
        assert_eq!(dir.reserve_commit(seq, 200, 5), 3, "evicts slot 3 (seq 0)");
        assert_eq!(dir.find(0), None);
        assert_eq!(dir.find(4), Some((3, 200)));
    }

    #[test]
    fn eviction_sacrifices_a_synced_run_before_an_unsynced_one() {
        // Four runs, seqs 0..=3. The oldest (seq 0) is UNSYNCED; a newer run
        // (seq 2) has been fully pulled by the phone. A fifth run must evict the
        // synced seq 2, NOT the older-but-unsynced seq 0.
        let mut dir = SlotDir::new();
        dir.reserve_commit(0, 100, 10);
        dir.reserve_commit(1, 100, 11);
        dir.reserve_commit(2, 100, 12);
        dir.reserve_commit(3, 100, 13);
        dir.mark_synced(2);
        assert_eq!(
            dir.reserve_commit(4, 100, 14),
            2,
            "evicts the synced run, not the oldest"
        );
        assert_eq!(dir.find(2), None, "the synced run was the victim");
        assert_eq!(
            dir.find(0),
            Some((0, 100)),
            "the unsynced oldest run survives"
        );
        assert_eq!(dir.find(4), Some((2, 100)));
    }

    #[test]
    fn eviction_prefers_the_oldest_synced_run() {
        // Two synced runs (seqs 1 and 3): eviction picks the lower-seq synced one.
        let mut dir = SlotDir::new();
        for seq in 0..4 {
            dir.reserve_commit(seq, 100, seq);
        }
        dir.mark_synced(3);
        dir.mark_synced(1);
        assert_eq!(
            dir.reserve_commit(4, 100, 14),
            1,
            "lowest-seq synced run is the victim"
        );
        assert_eq!(dir.find(1), None);
        assert_eq!(
            dir.find(3),
            Some((3, 100)),
            "the newer synced run survives this round"
        );
    }

    #[test]
    fn eviction_falls_back_to_oldest_when_nothing_is_synced() {
        // With no synced run to sacrifice, the region is physically full, so the
        // oldest (lowest-seq) run must go — the unchanged best-effort fallback.
        let mut dir = SlotDir::new();
        for seq in 0..4 {
            dir.reserve_commit(seq, 100, seq);
        }
        assert_eq!(
            dir.reserve_commit(4, 100, 14),
            0,
            "no synced run → evict the oldest"
        );
        assert_eq!(dir.find(0), None);
    }

    #[test]
    fn recovered_runs_start_unsynced_and_are_protected() {
        // A run recovered from a prior power cycle carries no synced bit, so it
        // is protected: a fresh run can't evict it while it stays unsynced —
        // unless every slot is an unsynced recovered run (the fallback).
        let slots = [
            Some(recovered(0, 100, 1)),
            Some(recovered(1, 100, 2)),
            Some(recovered(2, 100, 3)),
            None,
        ];
        let mut dir = SlotDir::from_recovered(slots);
        // Slot 3 is free, so a new run fills it — nothing evicted.
        assert_eq!(dir.reserve_commit(3, 100, 4), 3);
        // Now full and all unsynced: the next run falls back to the oldest.
        assert_eq!(dir.reserve_commit(4, 100, 5), 0);
        assert_eq!(dir.find(0), None);
    }

    #[test]
    fn mark_synced_ignores_an_unknown_run() {
        let mut dir = SlotDir::new();
        dir.reserve_commit(7, 100, 10);
        dir.mark_synced(999); // not held — no panic, no effect
        dir.reserve_commit(8, 100, 11);
        dir.mark_synced(8); // 8 is the only synced run
        dir.reserve_commit(9, 100, 12);
        dir.reserve_commit(10, 100, 13);
        let slot_of_8 = dir.find(8).expect("8 is held").0;
        // Full: the synced run (8) is the victim, and the unknown mark_synced(999)
        // left seq 7 unsynced and therefore protected.
        assert_eq!(dir.reserve_commit(11, 100, 14), slot_of_8);
        assert_eq!(dir.find(8), None);
        assert_eq!(
            dir.find(7),
            Some((0, 100)),
            "the unsynced oldest run survives"
        );
    }

    #[test]
    fn manifest_at_clamps_a_prior_boot_start_out_of_the_future() {
        // A run recovered from a prior boot carries start=3600; the post-reboot
        // uptime is only 100. Unclamped, the phone would date it in the future.
        let slots = [Some(recovered(5, 200, 3600)), None, None, None];
        let dir = SlotDir::from_recovered(slots);
        // manifest_at clamps start to the current uptime → never > watch_uptime_s.
        let clamped = dir.manifest_at(100);
        assert_eq!(
            clamped[0].start_uptime_s, 100,
            "clamped to the current uptime"
        );
        // The unclamped manifest still carries the raw (prior-boot) start.
        assert_eq!(dir.manifest()[0].start_uptime_s, 3600);
    }

    #[test]
    fn manifest_at_leaves_a_same_session_start_untouched() {
        // A run recorded THIS session has start <= uptime, so the clamp is a no-op
        // and it dates correctly; only the future-dating recovered case is changed.
        let mut dir = SlotDir::new();
        dir.reserve_commit(1, 100, 40);
        dir.reserve_commit(2, 100, 900);
        let m = dir.manifest_at(1000);
        assert_eq!(m[0].start_uptime_s, 40);
        assert_eq!(m[1].start_uptime_s, 900);
    }
}
