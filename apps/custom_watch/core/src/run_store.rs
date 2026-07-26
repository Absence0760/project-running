//! On-device run wire format + BLE sync framing (README step 7 / decisions §211).
//!
//! A finished run is a self-describing little-endian blob the watch writes to
//! flash while recording and streams to the phone over BLE in chunks. The
//! phone reassembles the whole blob, verifies it, and decodes it into the
//! JSON payload the mobile `WatchIngestQueue` / `runFromWatchPayload` already
//! ingests — so the watch reuses the existing phone→Supabase upload path with
//! zero backend change (firmware.md § Sync protocol).
//!
//! Pure logic, like every other module here: framing + a CRC + an abstract
//! [`ByteSink`] the flash driver implements. Host-tested against a golden
//! vector the Dart decoder ([`sim_watch_sync.dart`]) asserts byte-for-byte, so
//! a Rust-encode ↔ Dart-decode drift is caught at CI on both sides.
//!
//! Blob layout: `header (16) | record[N] (16 each) | footer (20)`. Version 1
//! records were all track points; version 2 (2026-07-21, issue #599) made the
//! point's reserved byte 15 a **record tag** — `0` = track point, `1` = a
//! closed lap — with lap records interleaved in recording order, and let the
//! slot-bounded writer **decimate instead of truncate**: when the staging sink
//! fills, every second stored point is dropped (laps never are) and the
//! incoming stream is thinned to match, so a full slot holds the WHOLE run at
//! coarser resolution rather than only its first minutes
//! ([`RunWriter::push_point_bounded`]).
//!
//! **Version 3 (2026-07-25) puts the footer's totals under the CRC.** Through
//! v2 the checksum covered only the header+records prefix, so the run's
//! summary — distance, moving time, elapsed time — sat outside it: bit-rot
//! there produced a blob that verified and synced as a valid run carrying
//! silently wrong numbers, which is worse than one that is rejected. From v3
//! the CRC covers every byte of the blob except the four it occupies itself
//! ([`FOOTER_CRC_OFFSET`]), so there is no unprotected region left. v1 and v2
//! blobs are **not** decodable by a v3 reader: their stored CRC is over a
//! narrower window and cannot match, and [`MIN_FORMAT_VERSION`] rejects them
//! explicitly rather than letting them read as corrupt (decisions §321).
//!
//! Manifest + chunk-request wire formats live here too so both ends agree.

/// Track blob magic — "TRK1".
pub const RUN_MAGIC: [u8; 4] = *b"TRK1";
/// Footer magic — "END1".
pub const FOOTER_MAGIC: [u8; 4] = *b"END1";
/// Manifest magic — "MAN1".
pub const MANIFEST_MAGIC: [u8; 4] = *b"MAN1";

/// What the writer emits today.
pub const FORMAT_VERSION: u8 = 3;
/// The oldest version a reader still decodes. Equal to [`FORMAT_VERSION`]
/// because v3 redefined what the CRC covers: a v1/v2 blob's checksum is over a
/// narrower window and cannot be re-checked without also re-admitting the
/// unprotected-totals hole v3 closed. Keeping the range explicit means an old
/// blob left on a bench board is rejected by version rather than reported as
/// corrupt bytes.
pub const MIN_FORMAT_VERSION: u8 = 3;

pub const HEADER_LEN: usize = 16;
pub const POINT_LEN: usize = 16;
/// Every record — point or lap — is one 16-byte cell, so the footer scan in
/// [`crate::flash_store::recover_slot`] stays record-aligned across versions.
pub const RECORD_LEN: usize = POINT_LEN;
pub const FOOTER_LEN: usize = 20;

/// Where the CRC field starts inside the footer, and therefore how much of the
/// footer the CRC itself covers: the magic plus all three totals. A blob's
/// checksum is taken over `blob[..blob.len() - 4]` — everything but the four
/// bytes holding it.
pub const FOOTER_CRC_OFFSET: usize = FOOTER_LEN - 4;

/// Record tags, at byte 15 of every record.
pub const RECORD_TAG_POINT: u8 = 0;
pub const RECORD_TAG_LAP: u8 = 1;

/// `flags` bit, stamped by [`RunWriter::finalize`]: this blob is a committed
/// run, not a mid-run [`checkpoint_blob`](RunWriter::checkpoint_blob) snapshot
/// of a run that is still recording. Both forms carry a valid footer + CRC, so
/// the flag is the ONLY thing separating them on flash — it is what stops a
/// partial blob being advertised to the phone as a complete run, and it is the
/// tiebreaker when both of a run's ping-pong slots survive a reset
/// ([`crate::flash_store::SlotDir::from_recovered`]).
///
/// It sits inside the CRC-covered header prefix, so a bit-rotted flag fails
/// verification rather than promoting a checkpoint.
pub const FLAG_FINISHED: u8 = 0x01;

/// Altitude sentinel meaning "no barometric/GPS altitude for this point".
pub const ELE_NONE: i16 = i16::MIN;

/// The most closed laps a run persists — beyond it new lap records are
/// dropped from STORAGE (the RAM display state is unaffected). 64 records =
/// 1 KiB of the 4 KiB slot: enough for a 60 km run's 1 km auto-laps, bounded
/// so a lap-heavy ultra can't crowd the track out of the slot. Real multi-day
/// capacity is the tier-2 external-QSPI item, same as the point budget.
pub const MAX_STORED_LAPS: u32 = 64;

/// Total blob length for a run with `record_count` 16-byte records.
pub const fn blob_len(record_count: u32) -> u32 {
    HEADER_LEN as u32 + record_count * RECORD_LEN as u32 + FOOTER_LEN as u32
}

/// Record count implied by a full blob length, or `None` if the length can't
/// be a valid blob (too short, or the body isn't a whole number of records).
/// Counts every 16-byte record — points AND laps; split by tag to count one
/// kind.
pub fn point_count(blob_len: u32) -> Option<u32> {
    let body = blob_len.checked_sub((HEADER_LEN + FOOTER_LEN) as u32)?;
    if body % RECORD_LEN as u32 != 0 {
        return None;
    }
    Some(body / RECORD_LEN as u32)
}

// ---- CRC32 (IEEE, reflected, poly 0xEDB88320) -----------------------------

/// Incremental CRC32 so the writer can hash header+points as it streams them
/// to flash without buffering the whole run.
#[derive(Clone, Copy)]
pub struct Crc32 {
    state: u32,
}

impl Default for Crc32 {
    fn default() -> Self {
        Self::new()
    }
}

impl Crc32 {
    pub const fn new() -> Self {
        Self { state: 0xFFFF_FFFF }
    }

    pub fn update(&mut self, bytes: &[u8]) {
        let mut crc = self.state;
        for &b in bytes {
            crc ^= b as u32;
            let mut k = 0;
            while k < 8 {
                let mask = (crc & 1).wrapping_neg();
                crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
                k += 1;
            }
        }
        self.state = crc;
    }

    pub fn finish(&self) -> u32 {
        self.state ^ 0xFFFF_FFFF
    }
}

/// One-shot CRC32 over a byte slice.
pub fn crc32(bytes: &[u8]) -> u32 {
    let mut c = Crc32::new();
    c.update(bytes);
    c.finish()
}

// ---- Track points ---------------------------------------------------------

/// One recorded fix in the wire format's fixed-point units: lat/lon in 1e-7
/// degrees (standard GPS integer scaling), altitude in decimetres, time as
/// whole seconds since the run started.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TrackPoint {
    pub lat_e7: i32,
    pub lon_e7: i32,
    pub t_offset_s: u32,
    pub ele_dm: Option<i16>,
    pub bpm: Option<u8>,
}

impl TrackPoint {
    pub fn encode(&self) -> [u8; POINT_LEN] {
        let mut b = [0u8; POINT_LEN];
        b[0..4].copy_from_slice(&self.lat_e7.to_le_bytes());
        b[4..8].copy_from_slice(&self.lon_e7.to_le_bytes());
        b[8..12].copy_from_slice(&self.t_offset_s.to_le_bytes());
        b[12..14].copy_from_slice(&self.ele_dm.unwrap_or(ELE_NONE).to_le_bytes());
        b[14] = self.bpm.unwrap_or(0);
        b[15] = RECORD_TAG_POINT;
        b
    }

    /// Decode a point record. `None` when the record carries a different tag
    /// (a lap) — callers walking a v2 blob dispatch on [`record_tag`] or just
    /// try both decoders.
    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < POINT_LEN || b[15] != RECORD_TAG_POINT {
            return None;
        }
        let ele = i16::from_le_bytes([b[12], b[13]]);
        let bpm = b[14];
        Some(Self {
            lat_e7: i32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            lon_e7: i32::from_le_bytes([b[4], b[5], b[6], b[7]]),
            t_offset_s: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
            ele_dm: (ele != ELE_NONE).then_some(ele),
            bpm: (bpm != 0).then_some(bpm),
        })
    }
}

/// The tag of a 16-byte record ([`RECORD_TAG_POINT`] / [`RECORD_TAG_LAP`]).
pub fn record_tag(b: &[u8]) -> Option<u8> {
    (b.len() >= RECORD_LEN).then(|| b[15])
}

/// One closed lap, persisted in recording order between the points it closed
/// over (version 2): its 1-based index, the lap's own distance (decimetres —
/// the display shows hundredths of a km), and the run's elapsed + the lap's
/// moving seconds at the close.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LapRecord {
    pub index: u16,
    pub lap_distance_dm: u32,
    pub split_s: u32,
    pub moving_s: u32,
}

impl LapRecord {
    pub fn encode(&self) -> [u8; RECORD_LEN] {
        let mut b = [0u8; RECORD_LEN];
        b[0..2].copy_from_slice(&self.index.to_le_bytes());
        b[2..6].copy_from_slice(&self.lap_distance_dm.to_le_bytes());
        b[6..10].copy_from_slice(&self.split_s.to_le_bytes());
        b[10..14].copy_from_slice(&self.moving_s.to_le_bytes());
        // b[14] reserved
        b[15] = RECORD_TAG_LAP;
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < RECORD_LEN || b[15] != RECORD_TAG_LAP {
            return None;
        }
        Some(Self {
            index: u16::from_le_bytes([b[0], b[1]]),
            lap_distance_dm: u32::from_le_bytes([b[2], b[3], b[4], b[5]]),
            split_s: u32::from_le_bytes([b[6], b[7], b[8], b[9]]),
            moving_s: u32::from_le_bytes([b[10], b[11], b[12], b[13]]),
        })
    }
}

// ---- Header / footer ------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RunHeader {
    pub version: u8,
    pub flags: u8,
    pub run_seq: u32,
    pub start_uptime_s: u32,
}

impl RunHeader {
    pub fn encode(&self) -> [u8; HEADER_LEN] {
        let mut b = [0u8; HEADER_LEN];
        b[0..4].copy_from_slice(&RUN_MAGIC);
        b[4] = self.version;
        b[5] = self.flags;
        // b[6..8] reserved
        b[8..12].copy_from_slice(&self.run_seq.to_le_bytes());
        b[12..16].copy_from_slice(&self.start_uptime_s.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < HEADER_LEN || b[0..4] != RUN_MAGIC {
            return None;
        }
        Some(Self {
            version: b[4],
            flags: b[5],
            run_seq: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
            start_uptime_s: u32::from_le_bytes([b[12], b[13], b[14], b[15]]),
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RunFooter {
    pub distance_m: u32,
    pub moving_s: u32,
    pub elapsed_s: u32,
    pub crc32: u32,
}

impl RunFooter {
    pub fn encode(&self) -> [u8; FOOTER_LEN] {
        let mut b = [0u8; FOOTER_LEN];
        b[0..4].copy_from_slice(&FOOTER_MAGIC);
        b[4..8].copy_from_slice(&self.distance_m.to_le_bytes());
        b[8..12].copy_from_slice(&self.moving_s.to_le_bytes());
        b[12..16].copy_from_slice(&self.elapsed_s.to_le_bytes());
        b[16..20].copy_from_slice(&self.crc32.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < FOOTER_LEN || b[0..4] != FOOTER_MAGIC {
            return None;
        }
        Some(Self {
            distance_m: u32::from_le_bytes([b[4], b[5], b[6], b[7]]),
            moving_s: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
            elapsed_s: u32::from_le_bytes([b[12], b[13], b[14], b[15]]),
            crc32: u32::from_le_bytes([b[16], b[17], b[18], b[19]]),
        })
    }
}

/// Build the footer for a blob whose header+records prefix has already been
/// hashed into `prefix_crc`, continuing that hash across the footer's own magic
/// and totals so the stamped CRC covers them. Both blob-emitting paths
/// ([`RunWriter::finalize`] and [`RunWriter::checkpoint_blob`]) go through here
/// — they differ only in the prefix they hand in, and a second hand-rolled copy
/// is exactly how the two CRC domains would drift apart again.
fn stamped_footer(
    mut prefix_crc: Crc32,
    distance_m: u32,
    moving_s: u32,
    elapsed_s: u32,
) -> [u8; FOOTER_LEN] {
    let mut footer = RunFooter {
        distance_m,
        moving_s,
        elapsed_s,
        crc32: 0,
    }
    .encode();
    prefix_crc.update(&footer[..FOOTER_CRC_OFFSET]);
    footer[FOOTER_CRC_OFFSET..].copy_from_slice(&prefix_crc.finish().to_le_bytes());
    footer
}

// ---- Streaming writer -----------------------------------------------------

/// A byte destination the run writer streams into — the flash driver on the
/// watch, a growable buffer in host tests. Errors are the sink's own.
pub trait ByteSink {
    type Error;
    fn write(&mut self, bytes: &[u8]) -> Result<(), Self::Error>;
}

/// The slot-sized staging buffer has no room left for the bytes offered — the
/// only way a write into it can fail.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SinkFull;

impl<const N: usize> ByteSink for heapless::Vec<u8, N> {
    type Error = SinkFull;
    fn write(&mut self, bytes: &[u8]) -> Result<(), SinkFull> {
        self.extend_from_slice(bytes).map_err(|_| SinkFull)
    }
}

/// Frames a run as it records: header on [`start`](RunWriter::start), a 16-byte
/// record per [`push_point`](RunWriter::push_point), a CRC-stamped footer on
/// `finalize`. The running CRC covers header + points, so a truncated
/// (never-finalised) blob fails verification on the phone.
pub struct RunWriter<S> {
    sink: S,
    crc: Crc32,
    points: u32,
    laps: u32,
    /// Decimation state ([`push_point_bounded`](Self::push_point_bounded)):
    /// only every `keep_every`-th incoming point is stored. 1 = full
    /// resolution; doubles on each in-place thinning.
    keep_every: u32,
    /// Incoming accepted-point ordinal, counted whether or not stored — the
    /// phase reference `keep_every` filters against.
    point_ordinal: u32,
}

impl<S: ByteSink> RunWriter<S> {
    pub fn start(mut sink: S, run_seq: u32, start_uptime_s: u32) -> Result<Self, S::Error> {
        let header = RunHeader {
            version: FORMAT_VERSION,
            flags: 0,
            run_seq,
            start_uptime_s,
        }
        .encode();
        sink.write(&header)?;
        let mut crc = Crc32::new();
        crc.update(&header);
        Ok(Self {
            sink,
            crc,
            points: 0,
            laps: 0,
            keep_every: 1,
            point_ordinal: 0,
        })
    }

    pub fn push_point(&mut self, point: &TrackPoint) -> Result<(), S::Error> {
        let bytes = point.encode();
        self.sink.write(&bytes)?;
        self.crc.update(&bytes);
        self.points = self.points.saturating_add(1);
        Ok(())
    }

    /// Persist a closed lap in stream order. Laps past [`MAX_STORED_LAPS`]
    /// are dropped from storage (never from the RAM display state) so a
    /// lap-heavy ultra can't crowd the track out of the slot; returns whether
    /// the lap was stored.
    pub fn push_lap(&mut self, lap: &LapRecord) -> Result<bool, S::Error> {
        if self.laps >= MAX_STORED_LAPS {
            return Ok(false);
        }
        let bytes = lap.encode();
        self.sink.write(&bytes)?;
        self.crc.update(&bytes);
        self.laps += 1;
        Ok(true)
    }

    pub fn point_count(&self) -> u32 {
        self.points
    }

    pub fn lap_count(&self) -> u32 {
        self.laps
    }

    /// The current decimation factor: 1 = full resolution, `k` = one stored
    /// point per `k` accepted fixes.
    pub fn thinning(&self) -> u32 {
        self.keep_every
    }
}

/// What [`RunWriter::push_point_bounded`] did with an incoming point.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PushOutcome {
    /// Stored at the current resolution.
    Stored,
    /// The sink was full: the staged track was thinned in place to this new
    /// `keep_every` factor first, then the point stored (or dropped if it
    /// fell out of the new phase). The whole run is still represented.
    Thinned(u32),
    /// Dropped — either pre-filtered by the current decimation phase, or the
    /// sink is full of undroppable records (laps) and cannot thin further.
    Dropped,
}

impl<const N: usize> RunWriter<heapless::Vec<u8, N>> {
    /// Stamp [`FLAG_FINISHED`] into the staged header, write the footer, and
    /// return the sink. `elapsed_s`/`moving_s`/`distance_m` are the finished
    /// run's totals (from `record::Snapshot`).
    ///
    /// Stamping the flag mutates a byte the running CRC already covered, so the
    /// CRC is recomputed over the whole stamped prefix — the flag stays inside
    /// the CRC'd region, and a checkpoint of the same prefix (which leaves the
    /// flag clear) is a different, equally-honest blob. That random access is
    /// why this lives on the `heapless::Vec` staging sink rather than on the
    /// append-only [`ByteSink`]; the on-device writer stages into exactly that.
    pub fn finalize(
        mut self,
        distance_m: u32,
        moving_s: u32,
        elapsed_s: u32,
    ) -> Result<heapless::Vec<u8, N>, SinkFull> {
        // Indexing byte 5 would panic — a device reset on this target — if the
        // header somehow never reached the sink. Then the CRC below covers a
        // header-less buffer, so the blob fails verification: fail closed.
        if let Some(flags) = self.sink.get_mut(5) {
            *flags |= FLAG_FINISHED;
        }
        let mut prefix_crc = Crc32::new();
        prefix_crc.update(&self.sink);
        let footer = stamped_footer(prefix_crc, distance_m, moving_s, elapsed_s);
        self.sink.write(&footer)?;
        Ok(self.sink)
    }

    /// [`push_point`](Self::push_point) for the slot-bounded RAM staging
    /// buffer, decimating instead of truncating (issue #599): when the next
    /// point + footer would no longer fit `N`, every second stored point is
    /// dropped in place (laps are always kept), the incoming stream is
    /// thinned to match (`keep_every` doubles), and recording continues — so
    /// a full slot holds the WHOLE run at coarser resolution rather than only
    /// its first minutes at full resolution. Totals are unaffected (they live
    /// in the footer); the CRC is rebuilt over the compacted prefix.
    pub fn push_point_bounded(&mut self, point: &TrackPoint) -> PushOutcome {
        let ordinal = self.point_ordinal;
        self.point_ordinal = self.point_ordinal.saturating_add(1);
        if !ordinal.is_multiple_of(self.keep_every) {
            return PushOutcome::Dropped;
        }
        let mut thinned = None;
        while self.sink.len() + RECORD_LEN + FOOTER_LEN > N {
            if !self.thin_in_place() {
                return PushOutcome::Dropped;
            }
            thinned = Some(self.keep_every);
        }
        if let Some(k) = thinned {
            if !ordinal.is_multiple_of(k) {
                // The triggering point falls out of the new phase; the thin
                // itself still happened and is worth reporting.
                return PushOutcome::Thinned(k);
            }
        }
        if self.push_point(point).is_err() {
            return PushOutcome::Dropped;
        }
        match thinned {
            Some(k) => PushOutcome::Thinned(k),
            None => PushOutcome::Stored,
        }
    }

    /// Drop every second stored point in place (first kept, laps untouched),
    /// compact the staged buffer, rebuild the CRC, and double `keep_every`.
    /// `false` when there is nothing left to gain (fewer than two stored
    /// points — the slot is full of laps + header, which never happens within
    /// [`MAX_STORED_LAPS`]).
    fn thin_in_place(&mut self) -> bool {
        if self.points < 2 {
            return false;
        }
        let buf: &mut [u8] = &mut self.sink;
        let mut write = HEADER_LEN;
        let mut read = HEADER_LEN;
        let mut point_pos = 0u32;
        let mut kept_points = 0u32;
        while read + RECORD_LEN <= buf.len() {
            let keep = if buf[read + RECORD_LEN - 1] == RECORD_TAG_LAP {
                true
            } else {
                let keep = point_pos.is_multiple_of(2);
                point_pos += 1;
                if keep {
                    kept_points += 1;
                }
                keep
            };
            if keep {
                buf.copy_within(read..read + RECORD_LEN, write);
                write += RECORD_LEN;
            }
            read += RECORD_LEN;
        }
        self.sink.truncate(write);
        self.points = kept_points;
        self.keep_every = self.keep_every.saturating_mul(2);
        let mut crc = Crc32::new();
        crc.update(&self.sink);
        self.crc = crc;
        true
    }

    /// Emit a recoverable checkpoint blob of the run staged so far WITHOUT
    /// consuming the writer: the staged `header|points` prefix plus a footer
    /// stamped with the totals-so-far. It reuses the running CRC, which covers
    /// the header with [`FLAG_FINISHED`] still clear — so the blob verifies
    /// through [`verify_blob`] exactly like a committed run, but says on its face
    /// that the run was still recording. That is the one byte separating it from
    /// what [`finalize`](Self::finalize) would write for the same prefix, and it
    /// is what keeps a mid-run snapshot out of the phone's manifest.
    ///
    /// This lets the recorder persist a mid-run snapshot to flash while
    /// continuing to stream into the same writer, so a reset mid-run recovers a
    /// (slightly stale) partial run instead of nothing. `None` only if the blob
    /// doesn't fit `N` (the sink is already `N`-bounded, so this can't happen
    /// once a run staged into the same-sized sink).
    pub fn checkpoint_blob(
        &self,
        distance_m: u32,
        moving_s: u32,
        elapsed_s: u32,
    ) -> Option<heapless::Vec<u8, N>> {
        let mut out = heapless::Vec::<u8, N>::new();
        out.extend_from_slice(&self.sink).ok()?;
        let footer = stamped_footer(self.crc, distance_m, moving_s, elapsed_s);
        out.extend_from_slice(&footer).ok()?;
        Some(out)
    }
}

/// Verify a reassembled blob: magics present, length a whole number of points,
/// and the stored CRC matches a recompute over every byte the CRC covers —
/// header, records, and the footer's magic + totals. The phone calls this
/// before trusting a synced run.
///
/// Because the totals are inside the window, a blob either checks out whole or
/// is rejected whole; there is no state where the track is trusted but the
/// summary quietly is not.
pub fn verify_blob(blob: &[u8]) -> bool {
    let Some(n) = point_count(blob.len() as u32) else {
        return false;
    };
    if RunHeader::decode(blob).is_none() {
        return false;
    }
    let footer_at = HEADER_LEN + n as usize * POINT_LEN;
    let Some(footer) = RunFooter::decode(&blob[footer_at..]) else {
        return false;
    };
    crc32(&blob[..footer_at + FOOTER_CRC_OFFSET]) == footer.crc32
}

// ---- Manifest + chunk request ---------------------------------------------

pub const MANIFEST_HEADER_LEN: usize = 12;
pub const MANIFEST_ENTRY_LEN: usize = 12;

/// The manifest header: run count + the watch's current uptime, the anchor the
/// phone uses to turn each entry's `start_uptime_s` into an absolute time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ManifestHeader {
    pub run_count: u8,
    pub watch_uptime_s: u32,
}

impl ManifestHeader {
    pub fn encode(&self) -> [u8; MANIFEST_HEADER_LEN] {
        let mut b = [0u8; MANIFEST_HEADER_LEN];
        b[0..4].copy_from_slice(&MANIFEST_MAGIC);
        b[4] = FORMAT_VERSION;
        b[5] = self.run_count;
        // b[6..8] reserved
        b[8..12].copy_from_slice(&self.watch_uptime_s.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < MANIFEST_HEADER_LEN || b[0..4] != MANIFEST_MAGIC {
            return None;
        }
        Some(Self {
            run_count: b[5],
            watch_uptime_s: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
        })
    }
}

/// One finished run advertised in the manifest: its watch-local id, its blob
/// size (so the phone knows how many chunks to pull), and the uptime it began
/// (so the phone can anchor `started_at` against the live link's uptime).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ManifestEntry {
    pub run_seq: u32,
    pub size: u32,
    pub start_uptime_s: u32,
}

impl ManifestEntry {
    pub fn encode(&self) -> [u8; MANIFEST_ENTRY_LEN] {
        let mut b = [0u8; MANIFEST_ENTRY_LEN];
        b[0..4].copy_from_slice(&self.run_seq.to_le_bytes());
        b[4..8].copy_from_slice(&self.size.to_le_bytes());
        b[8..12].copy_from_slice(&self.start_uptime_s.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < MANIFEST_ENTRY_LEN {
            return None;
        }
        Some(Self {
            run_seq: u32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            size: u32::from_le_bytes([b[4], b[5], b[6], b[7]]),
            start_uptime_s: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
        })
    }
}

pub const CHUNK_REQUEST_LEN: usize = 10;

/// The phone's request on the `run_chunk` characteristic: give me `len` bytes
/// of run `run_seq` starting at `offset`. The watch replies by notifying that
/// slice of the blob.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChunkRequest {
    pub run_seq: u32,
    pub offset: u32,
    pub len: u16,
}

impl ChunkRequest {
    pub fn encode(&self) -> [u8; CHUNK_REQUEST_LEN] {
        let mut b = [0u8; CHUNK_REQUEST_LEN];
        b[0..4].copy_from_slice(&self.run_seq.to_le_bytes());
        b[4..8].copy_from_slice(&self.offset.to_le_bytes());
        b[8..10].copy_from_slice(&self.len.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < CHUNK_REQUEST_LEN {
            return None;
        }
        Some(Self {
            run_seq: u32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            offset: u32::from_le_bytes([b[4], b[5], b[6], b[7]]),
            len: u16::from_le_bytes([b[8], b[9]]),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_points() -> [TrackPoint; 3] {
        [
            TrackPoint {
                lat_e7: 400_150_200,
                lon_e7: -1_052_705_000,
                t_offset_s: 0,
                ele_dm: Some(16_240),
                bpm: Some(120),
            },
            TrackPoint {
                lat_e7: 400_150_500,
                lon_e7: -1_052_704_500,
                t_offset_s: 1,
                ele_dm: Some(16_242),
                bpm: Some(122),
            },
            TrackPoint {
                lat_e7: 400_150_900,
                lon_e7: -1_052_704_000,
                t_offset_s: 2,
                ele_dm: None,
                bpm: None,
            },
        ]
    }

    fn build() -> heapless::Vec<u8, 4096> {
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 7, 41).expect("start");
        for p in sample_points() {
            w.push_point(&p).expect("push");
        }
        w.finalize(1234, 600, 620).expect("finalize")
    }

    #[test]
    fn round_trips_header_points_footer() {
        let blob = build();
        assert_eq!(blob.len() as u32, blob_len(3));
        assert_eq!(point_count(blob.len() as u32), Some(3));

        let header = RunHeader::decode(&blob).expect("header");
        assert_eq!(header.version, FORMAT_VERSION);
        assert_eq!(header.run_seq, 7);
        assert_eq!(header.start_uptime_s, 41);

        for (i, expected) in sample_points().iter().enumerate() {
            let at = HEADER_LEN + i * POINT_LEN;
            assert_eq!(&TrackPoint::decode(&blob[at..]).unwrap(), expected);
        }

        let footer_at = HEADER_LEN + 3 * POINT_LEN;
        let footer = RunFooter::decode(&blob[footer_at..]).expect("footer");
        assert_eq!(footer.distance_m, 1234);
        assert_eq!(footer.moving_s, 600);
        assert_eq!(footer.elapsed_s, 620);
    }

    #[test]
    fn checkpoint_blob_differs_from_a_finalize_only_in_the_finished_flag() {
        // A mid-run checkpoint and the commit of the same staged prefix must be
        // TELLABLE APART on flash — otherwise a partial run is advertised to the
        // phone as complete, and a later commit re-advertises the same run_seq
        // with disagreeing bytes. The whole difference is the header flag (and
        // the CRC that covers it); every other byte, including the totals, is
        // identical.
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 7, 41).expect("start");
        for p in sample_points() {
            w.push_point(&p).expect("push");
        }
        let ckpt = w.checkpoint_blob(1234, 600, 620).expect("checkpoint");
        assert!(
            verify_blob(&ckpt),
            "a checkpoint is still a well-formed blob"
        );
        assert_eq!(ckpt.len() as u32, blob_len(3));
        assert_eq!(
            RunHeader::decode(&ckpt).unwrap().flags & FLAG_FINISHED,
            0,
            "a mid-run checkpoint must not claim to be finished"
        );

        // Identically-staged second writer, finalised.
        let sink2: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w2 = RunWriter::start(sink2, 7, 41).expect("start");
        for p in sample_points() {
            w2.push_point(&p).expect("push");
        }
        let finalised = w2.finalize(1234, 600, 620).expect("finalize");
        assert!(verify_blob(&finalised));
        assert_eq!(
            RunHeader::decode(&finalised).unwrap().flags & FLAG_FINISHED,
            FLAG_FINISHED,
            "finalize stamps the finished flag"
        );
        assert_eq!(ckpt.len(), finalised.len());
        // Byte 5 is the flag; the last four are the CRC that covers it. Nothing
        // else moved.
        let differs: heapless::Vec<usize, 8> = (0..ckpt.len())
            .filter(|&i| ckpt[i] != finalised[i])
            .collect();
        let footer_crc_at = finalised.len() - 4;
        assert_eq!(
            differs.as_slice(),
            &[
                5,
                footer_crc_at,
                footer_crc_at + 1,
                footer_crc_at + 2,
                footer_crc_at + 3
            ][..],
            "only the flag byte and the CRC over it differ"
        );
    }

    #[test]
    fn a_checkpoint_flag_flip_fails_verification() {
        // Fail-closed: the flag lives inside the CRC-covered prefix, so bit-rot
        // (or a tamper) that promotes a checkpoint to "finished" is caught, not
        // trusted.
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 7, 41).expect("start");
        for p in sample_points() {
            w.push_point(&p).expect("push");
        }
        let mut ckpt = w.checkpoint_blob(1234, 600, 620).expect("checkpoint");
        ckpt[5] |= FLAG_FINISHED;
        assert!(!verify_blob(&ckpt));
    }

    #[test]
    fn checkpoint_blob_does_not_consume_the_writer_and_later_supersedes() {
        // The writer keeps streaming after a checkpoint, and a later checkpoint
        // carries the newer points + totals (the eventual commit supersedes it).
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 1, 0).expect("start");
        for i in 0..3u32 {
            w.push_point(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            })
            .expect("push");
        }
        let early = w.checkpoint_blob(100, 50, 60).expect("early checkpoint");
        assert!(verify_blob(&early));
        assert_eq!(point_count(early.len() as u32), Some(3));

        for i in 3..10u32 {
            w.push_point(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            })
            .expect("push");
        }
        let later = w.checkpoint_blob(400, 300, 320).expect("later checkpoint");
        assert!(verify_blob(&later));
        assert_eq!(point_count(later.len() as u32), Some(10));
        assert!(later.len() > early.len(), "later checkpoint has more track");

        // And the writer still finalises cleanly afterwards.
        let fin = w.finalize(500, 400, 420).expect("finalize");
        assert!(verify_blob(&fin));
        assert_eq!(point_count(fin.len() as u32), Some(10));
    }

    #[test]
    fn checkpoint_blob_zero_points_round_trips() {
        let sink: heapless::Vec<u8, 64> = heapless::Vec::new();
        let w = RunWriter::start(sink, 2, 9).expect("start");
        let ckpt = w.checkpoint_blob(0, 0, 0).expect("checkpoint");
        assert!(verify_blob(&ckpt));
        assert_eq!(point_count(ckpt.len() as u32), Some(0));
    }

    #[test]
    fn verify_accepts_a_clean_blob_and_rejects_tampering() {
        let mut blob = build();
        assert!(verify_blob(&blob));
        // Flip a byte in the first point: CRC must catch it.
        blob[HEADER_LEN] ^= 0xFF;
        assert!(!verify_blob(&blob));
    }

    #[test]
    fn verify_rejects_truncation() {
        let blob = build();
        // Drop the footer — an unfinalised / cut-off transfer.
        assert!(!verify_blob(&blob[..blob.len() - FOOTER_LEN]));
        // A non-point-aligned length is impossible for a real blob.
        assert!(!verify_blob(&blob[..blob.len() - 1]));
    }

    #[test]
    fn ele_and_bpm_sentinels_round_trip_as_none() {
        let p = TrackPoint {
            lat_e7: 1,
            lon_e7: 2,
            t_offset_s: 3,
            ele_dm: None,
            bpm: None,
        };
        let decoded = TrackPoint::decode(&p.encode()).unwrap();
        assert_eq!(decoded.ele_dm, None);
        assert_eq!(decoded.bpm, None);
    }

    #[test]
    fn manifest_header_round_trips() {
        let h = ManifestHeader {
            run_count: 2,
            watch_uptime_s: 3600,
        };
        assert_eq!(ManifestHeader::decode(&h.encode()), Some(h));
        // Wrong magic is rejected.
        assert_eq!(ManifestHeader::decode(&[0u8; MANIFEST_HEADER_LEN]), None);
    }

    #[test]
    fn manifest_entry_round_trips() {
        let e = ManifestEntry {
            run_seq: 7,
            size: blob_len(3),
            start_uptime_s: 41,
        };
        assert_eq!(ManifestEntry::decode(&e.encode()), Some(e));
    }

    #[test]
    fn chunk_request_round_trips() {
        let r = ChunkRequest {
            run_seq: 7,
            offset: 32,
            len: 244,
        };
        assert_eq!(ChunkRequest::decode(&r.encode()), Some(r));
    }

    #[test]
    fn crc32_matches_known_vector() {
        // Standard CRC32/IEEE check value for "123456789".
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    /// Golden vector: the exact bytes a fixed run produces. Byte 4 is the
    /// format version, byte 5 is [`FLAG_FINISHED`] — set, because this is a
    /// committed run — and the trailing CRC covers both, every record, and the
    /// footer's totals.
    #[test]
    fn golden_blob_is_stable() {
        let blob = build();
        let hex = blob
            .iter()
            .fold(heapless::String::<512>::new(), |mut s, b| {
                let _ = core::fmt::write(&mut s, format_args!("{:02x}", b));
                s
            });
        assert_eq!(
            hex.as_str(),
            "54524b31030100000700000029000000b8ced91718ff40c100000000703f7800e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000454e4431d2040000580200006c02000039e3c091",
            "wire format changed — update this vector, and the Dart mirror in \
             apps/mobile_android/test/sim_watch_sync_test.dart if the layout moved"
        );
    }

    /// Golden vector for a blob carrying a lap record between its points —
    /// pinned byte-for-byte in the Dart mirror's test so the two codecs can't
    /// drift, exactly like the point-only golden above.
    #[test]
    fn golden_blob_with_a_lap_is_stable() {
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 7, 41).expect("start");
        let pts = sample_points();
        w.push_point(&pts[0]).expect("push");
        w.push_point(&pts[1]).expect("push");
        w.push_lap(&LapRecord {
            index: 1,
            lap_distance_dm: 10_000,
            split_s: 300,
            moving_s: 290,
        })
        .expect("lap");
        w.push_point(&pts[2]).expect("push");
        let blob = w.finalize(1234, 600, 620).expect("finalize");
        let hex = blob
            .iter()
            .fold(heapless::String::<512>::new(), |mut s, b| {
                let _ = core::fmt::write(&mut s, format_args!("{:02x}", b));
                s
            });
        assert_eq!(
            hex.as_str(),
            "54524b31030100000700000029000000b8ced91718ff40c100000000703f7800e4cfd9170c0141c101000000723f7a000100102700002c01000022010000000174d1d917000341c10200000000800000454e4431d2040000580200006c0200008d2b643c",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/test/sim_watch_sync_test.dart"
        );
    }

    fn from_hex(hex: &str) -> heapless::Vec<u8, 256> {
        let mut out: heapless::Vec<u8, 256> = heapless::Vec::new();
        let bytes = hex.as_bytes();
        for i in (0..bytes.len()).step_by(2) {
            let hi = (bytes[i] as char).to_digit(16).unwrap() as u8;
            let lo = (bytes[i + 1] as char).to_digit(16).unwrap() as u8;
            out.push((hi << 4) | lo).unwrap();
        }
        out
    }

    /// The v1 and v2 golden vectors as prior firmware wrote them. v3 moved the
    /// CRC window to include the footer totals, so their stored checksums no
    /// longer describe the bytes they precede: both are rejected. That is the
    /// compat decision, pinned — a v3 reader must not accept a blob whose
    /// summary is unprotected, and the version gate must name the reason.
    #[test]
    fn pre_v3_golden_blobs_are_rejected() {
        const V1_HEX: &str = "54524b31010000000700000029000000b8ced91718ff40c100000000703f7800e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000454e4431d2040000580200006c02000077fdfebd";
        const V2_HEX: &str = "54524b31020100000700000029000000b8ced91718ff40c100000000703f7800e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000454e4431d2040000580200006c020000566db750";
        for (label, hex) in [("v1", V1_HEX), ("v2", V2_HEX)] {
            let blob = from_hex(hex);
            assert!(
                !verify_blob(&blob),
                "{label}: a pre-v3 CRC covers a narrower window and must not check out"
            );
            let header = RunHeader::decode(&blob).unwrap();
            assert!(
                header.version < MIN_FORMAT_VERSION,
                "{label}: below the decodable range"
            );
        }
    }

    #[test]
    fn laps_interleave_round_trip_and_never_thin() {
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 3, 0).expect("start");
        let pts = sample_points();
        w.push_point(&pts[0]).unwrap();
        w.push_point(&pts[1]).unwrap();
        let lap = LapRecord {
            index: 1,
            lap_distance_dm: 10_000,
            split_s: 300,
            moving_s: 290,
        };
        assert!(w.push_lap(&lap).unwrap());
        w.push_point(&pts[2]).unwrap();
        assert_eq!(w.point_count(), 3);
        assert_eq!(w.lap_count(), 1);
        let blob = w.finalize(2_000, 590, 600).expect("finalize");
        assert!(verify_blob(&blob));
        assert_eq!(point_count(blob.len() as u32), Some(4), "4 records");

        // Records read back in stream order, dispatched by tag.
        let tags: [u8; 4] =
            core::array::from_fn(|i| record_tag(&blob[HEADER_LEN + i * RECORD_LEN..]).unwrap());
        assert_eq!(
            tags,
            [
                RECORD_TAG_POINT,
                RECORD_TAG_POINT,
                RECORD_TAG_LAP,
                RECORD_TAG_POINT
            ]
        );
        let at = HEADER_LEN + 2 * RECORD_LEN;
        assert_eq!(LapRecord::decode(&blob[at..]), Some(lap));
        assert_eq!(
            TrackPoint::decode(&blob[at..]),
            None,
            "a lap record must not decode as a GPS point"
        );
    }

    #[test]
    fn stored_laps_are_budgeted() {
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 3, 0).expect("start");
        for i in 0..MAX_STORED_LAPS {
            assert!(w
                .push_lap(&LapRecord {
                    index: (i + 1) as u16,
                    lap_distance_dm: 10_000,
                    split_s: 300 * (i + 1),
                    moving_s: 290,
                })
                .unwrap());
        }
        // The budget-crossing lap is dropped from storage, not an error.
        assert!(!w
            .push_lap(&LapRecord {
                index: (MAX_STORED_LAPS + 1) as u16,
                lap_distance_dm: 10_000,
                split_s: 300,
                moving_s: 290,
            })
            .unwrap());
        assert_eq!(w.lap_count(), MAX_STORED_LAPS);
    }

    #[test]
    fn bounded_push_decimates_instead_of_truncating() {
        // A tiny 1 KiB "slot": header(16) + footer(20) leaves room for 61
        // records. Feed 200 points — far past capacity.
        const N: usize = 1024;
        let sink: heapless::Vec<u8, N> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 5, 0).expect("start");
        let mut thins = 0;
        for i in 0..200u32 {
            let outcome = w.push_point_bounded(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            });
            if let PushOutcome::Thinned(_) = outcome {
                thins += 1;
            }
        }
        assert!(thins >= 1, "the slot must have thinned at least once");
        let k = w.thinning();
        assert!(k >= 4, "200 points into ~61 slots needs 1/4");
        let blob = w.finalize(1_000, 200, 210).expect("finalize");
        assert!(verify_blob(&blob), "CRC rebuilt correctly across thinning");

        // The WHOLE run is represented: first stored point is ordinal 0 and
        // the last stored point is from the final stretch, not minute one.
        let n = point_count(blob.len() as u32).unwrap();
        let first = TrackPoint::decode(&blob[HEADER_LEN..]).unwrap();
        assert_eq!(first.t_offset_s, 0);
        let last = TrackPoint::decode(&blob[HEADER_LEN + (n as usize - 1) * RECORD_LEN..]).unwrap();
        assert!(
            last.t_offset_s > 150,
            "tail of the run survives: t={}",
            last.t_offset_s
        );
        // Stored points are evenly strided at the final factor.
        let second = TrackPoint::decode(&blob[HEADER_LEN + RECORD_LEN..]).unwrap();
        assert_eq!(second.t_offset_s, k, "stride matches the reported factor");
    }

    #[test]
    fn checkpoint_blob_still_verifies_after_thinning() {
        // The mid-run checkpoint path reuses the writer's running CRC, and
        // thinning REBUILDS that CRC over the compacted buffer — this pins
        // that a checkpoint taken after one or more thins reads back as a
        // valid blob (the exact sequence app record's checkpoint cadence
        // produces on a long run).
        const N: usize = 1024;
        let sink: heapless::Vec<u8, N> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 6, 0).expect("start");
        for i in 0..200u32 {
            w.push_point_bounded(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            });
        }
        assert!(w.thinning() > 1, "the slot must have thinned");
        let ckpt = w.checkpoint_blob(900, 190, 200).expect("checkpoint");
        assert!(verify_blob(&ckpt), "post-thin checkpoint verifies");
        // And the writer keeps recording + finalises cleanly afterwards.
        for i in 200..220u32 {
            w.push_point_bounded(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            });
        }
        let fin = w.finalize(1_000, 210, 220).expect("finalize");
        assert!(verify_blob(&fin));
    }

    #[test]
    fn bounded_push_keeps_laps_across_thinning() {
        const N: usize = 1024;
        let sink: heapless::Vec<u8, N> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 5, 0).expect("start");
        // Two laps early, then flood with points to force thinning.
        w.push_point_bounded(&TrackPoint {
            lat_e7: 0,
            lon_e7: 0,
            t_offset_s: 0,
            ele_dm: None,
            bpm: None,
        });
        for i in 1..=2u16 {
            assert!(w
                .push_lap(&LapRecord {
                    index: i,
                    lap_distance_dm: 10_000,
                    split_s: 300 * i as u32,
                    moving_s: 290,
                })
                .unwrap());
        }
        for i in 1..300u32 {
            w.push_point_bounded(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            });
        }
        assert!(w.thinning() > 1, "thinning happened");
        assert_eq!(w.lap_count(), 2, "laps never thin");
        let blob = w.finalize(3_000, 290, 300).expect("finalize");
        assert!(verify_blob(&blob));
        let n = point_count(blob.len() as u32).unwrap() as usize;
        let laps: usize = (0..n)
            .filter(|i| record_tag(&blob[HEADER_LEN + i * RECORD_LEN..]) == Some(RECORD_TAG_LAP))
            .count();
        assert_eq!(laps, 2, "both lap records survive every thinning pass");
    }

    /// A run staged into a slot-sized sink, as the on-device recorder does
    /// (`app/run_flash.rs` stages into a `heapless::Vec<u8, SLOT_LEN>`). Returns
    /// the finalised blob, or `Err` if any push or the footer overran the sink.
    fn build_n(n: u32) -> Result<heapless::Vec<u8, 4096>, SinkFull> {
        let sink: heapless::Vec<u8, 4096> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 1, 0)?;
        for i in 0..n {
            w.push_point(&TrackPoint {
                lat_e7: i as i32,
                lon_e7: 0,
                t_offset_s: i,
                ele_dm: None,
                bpm: None,
            })?;
        }
        w.finalize(0, 0, 0)
    }

    #[test]
    fn point_cap_matches_a_slot_sized_sink() {
        // 253 is the most points that still leave room for the 20-byte footer in
        // one 4096-byte flash slot: HEADER(16) + 253*POINT(16) + FOOTER(20) =
        // 4084 (this is flash_store::MAX_POINTS_PER_RUN).
        let ok = build_n(253).expect("253 points + footer fit a slot");
        assert_eq!(ok.len(), 4084);
        assert_eq!(ok.len() as u32, blob_len(253));
        assert!(verify_blob(&ok));

        // 254 points still stage as raw records (16 + 254*16 = 4080 <= 4096) but
        // leave no room for the footer — so finalize, not push_point, is what
        // rejects the over-long run.
        assert!(build_n(254).is_err(), "no slot room for the footer");

        // 256 points can't even be staged; push_point returns the sink's error
        // rather than overrunning the buffer.
        assert!(build_n(256).is_err());
    }

    #[test]
    fn verify_rejects_header_and_footer_corruption() {
        // A flipped byte in the header body (run_seq, inside the CRC'd prefix) is
        // caught by the CRC recompute even though the magic still decodes.
        let mut blob = build();
        blob[8] ^= 0xFF;
        assert!(!verify_blob(&blob));

        // A corrupted header magic fails the header decode outright.
        let mut blob = build();
        blob[0] ^= 0xFF;
        assert!(!verify_blob(&blob));

        // A corrupted footer magic fails the footer decode.
        let mut blob = build();
        let footer_at = blob.len() - FOOTER_LEN;
        blob[footer_at] ^= 0xFF;
        assert!(!verify_blob(&blob));

        // A corrupted stored CRC (footer's last four bytes) mismatches the
        // recompute over header + points.
        let mut blob = build();
        let last = blob.len() - 1;
        blob[last] ^= 0xFF;
        assert!(!verify_blob(&blob));
    }

    #[test]
    fn verify_rejects_a_corrupted_footer_total() {
        // The v3 reason for existing: through v2 the summary sat outside the
        // CRC, so bit-rot in distance / moving / elapsed produced a blob that
        // verified and synced as a real run with wrong numbers — a worse
        // outcome than a rejected run, because nothing tells the runner.
        let footer_totals = HEADER_LEN + 3 * RECORD_LEN + 4..HEADER_LEN + 3 * RECORD_LEN + 16;
        for at in footer_totals {
            let mut blob = build();
            blob[at] ^= 0x01;
            assert!(!verify_blob(&blob), "flip at byte {at} must be caught");
        }
    }

    #[test]
    fn no_byte_of_a_blob_is_outside_the_integrity_check() {
        // Exhaustive over the golden blob: there is no unprotected region left
        // anywhere — magic, version, flags, records, totals, and the stored CRC
        // itself all fail verification when disturbed.
        let clean = build();
        for at in 0..clean.len() {
            let mut blob = build();
            blob[at] ^= 0x01;
            assert!(!verify_blob(&blob), "byte {at} is unprotected");
        }
    }

    #[test]
    fn zero_point_blob_verifies_and_round_trips() {
        let sink: heapless::Vec<u8, 64> = heapless::Vec::new();
        let w = RunWriter::start(sink, 1, 2).expect("start");
        let blob = w.finalize(0, 0, 0).expect("finalize");
        assert_eq!(blob.len() as u32, blob_len(0));
        assert_eq!(point_count(blob.len() as u32), Some(0));
        assert!(verify_blob(&blob));
    }

    #[test]
    fn point_count_round_trips_and_rejects_bad_lengths() {
        for n in [0u32, 1, 2, 253] {
            assert_eq!(point_count(blob_len(n)), Some(n));
        }
        // Shorter than a bare header + footer.
        assert_eq!(point_count(0), None);
        assert_eq!(point_count((HEADER_LEN + FOOTER_LEN) as u32 - 1), None);
        // A body that isn't a whole number of points.
        assert_eq!(point_count((HEADER_LEN + FOOTER_LEN + 1) as u32), None);
        assert_eq!(point_count(blob_len(3) - 1), None);
    }

    #[test]
    fn decoders_reject_short_buffers_and_wrong_magic() {
        let z = [0u8; 32];
        for len in 0..POINT_LEN {
            assert_eq!(TrackPoint::decode(&z[..len]), None);
        }
        for len in 0..HEADER_LEN {
            assert_eq!(RunHeader::decode(&z[..len]), None);
        }
        for len in 0..FOOTER_LEN {
            assert_eq!(RunFooter::decode(&z[..len]), None);
        }
        // Correct length, wrong magic.
        assert_eq!(RunHeader::decode(&[0u8; HEADER_LEN]), None);
        assert_eq!(RunFooter::decode(&[0u8; FOOTER_LEN]), None);
    }

    #[test]
    fn chunk_request_decode_is_bounds_safe_and_carries_extremes() {
        let buf = [0u8; CHUNK_REQUEST_LEN];
        for len in 0..CHUNK_REQUEST_LEN {
            assert_eq!(ChunkRequest::decode(&buf[..len]), None);
        }
        // Trailing bytes past the fixed 10 are ignored, never over-read.
        let padded = [0xABu8; CHUNK_REQUEST_LEN + 4];
        assert!(ChunkRequest::decode(&padded).is_some());

        // The wire struct never clamps — a len past the blob end or above the
        // notify MTU round-trips untouched; clamping to a valid slice is
        // flash_store::chunk_len's job, exercised there.
        let r = ChunkRequest {
            run_seq: u32::MAX,
            offset: u32::MAX,
            len: u16::MAX,
        };
        assert_eq!(ChunkRequest::decode(&r.encode()), Some(r));
    }
}
