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
//! Blob layout: `header (16) | point[N] (16 each) | footer (20)`.
//! Manifest + chunk-request wire formats live here too so both ends agree.

/// Track blob magic — "TRK1".
pub const RUN_MAGIC: [u8; 4] = *b"TRK1";
/// Footer magic — "END1".
pub const FOOTER_MAGIC: [u8; 4] = *b"END1";
/// Manifest magic — "MAN1".
pub const MANIFEST_MAGIC: [u8; 4] = *b"MAN1";

pub const FORMAT_VERSION: u8 = 1;

pub const HEADER_LEN: usize = 16;
pub const POINT_LEN: usize = 16;
pub const FOOTER_LEN: usize = 20;

/// `flags` bit: the run reached `stop()` (a footer follows). Unfinished blobs
/// are never listed in the manifest.
pub const FLAG_FINISHED: u8 = 0x01;

/// Altitude sentinel meaning "no barometric/GPS altitude for this point".
pub const ELE_NONE: i16 = i16::MIN;

/// Total blob length for a run with `point_count` points.
pub const fn blob_len(point_count: u32) -> u32 {
    HEADER_LEN as u32 + point_count * POINT_LEN as u32 + FOOTER_LEN as u32
}

/// Point count implied by a full blob length, or `None` if the length can't be
/// a valid blob (too short, or the body isn't a whole number of points).
pub fn point_count(blob_len: u32) -> Option<u32> {
    let body = blob_len.checked_sub((HEADER_LEN + FOOTER_LEN) as u32)?;
    if body % POINT_LEN as u32 != 0 {
        return None;
    }
    Some(body / POINT_LEN as u32)
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
        b[15] = 0;
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < POINT_LEN {
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

// ---- Streaming writer -----------------------------------------------------

/// A byte destination the run writer streams into — the flash driver on the
/// watch, a growable buffer in host tests. Errors are the sink's own.
pub trait ByteSink {
    type Error;
    fn write(&mut self, bytes: &[u8]) -> Result<(), Self::Error>;
}

impl<const N: usize> ByteSink for heapless::Vec<u8, N> {
    type Error = ();
    fn write(&mut self, bytes: &[u8]) -> Result<(), ()> {
        self.extend_from_slice(bytes).map_err(|_| ())
    }
}

/// Frames a run as it records: header on [`start`](RunWriter::start), a 16-byte
/// record per [`push_point`](RunWriter::push_point), a CRC-stamped footer on
/// [`finalize`](RunWriter::finalize). The running CRC covers header + points,
/// so a truncated (never-finalised) blob fails verification on the phone.
pub struct RunWriter<S> {
    sink: S,
    crc: Crc32,
    points: u32,
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
        })
    }

    pub fn push_point(&mut self, point: &TrackPoint) -> Result<(), S::Error> {
        let bytes = point.encode();
        self.sink.write(&bytes)?;
        self.crc.update(&bytes);
        self.points = self.points.saturating_add(1);
        Ok(())
    }

    pub fn point_count(&self) -> u32 {
        self.points
    }

    /// Write the footer and return the sink. `elapsed_s`/`moving_s`/`distance_m`
    /// are the finished run's totals (from `record::Snapshot`).
    pub fn finalize(
        mut self,
        distance_m: u32,
        moving_s: u32,
        elapsed_s: u32,
    ) -> Result<S, S::Error> {
        let footer = RunFooter {
            distance_m,
            moving_s,
            elapsed_s,
            crc32: self.crc.finish(),
        }
        .encode();
        self.sink.write(&footer)?;
        Ok(self.sink)
    }
}

/// Verify a reassembled blob: magics present, length a whole number of points,
/// and the stored CRC matches a recompute over header + points. The phone
/// calls this before trusting a synced run.
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
    crc32(&blob[..footer_at]) == footer.crc32
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

    /// Golden vector: the exact bytes a fixed run produces. The Dart decoder
    /// (`sim_watch_sync.dart`) pins this same hex, so a format drift on either
    /// side fails a test rather than silently corrupting a synced run.
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
            "54524b31010000000700000029000000b8ced91718ff40c100000000703f7800e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000454e4431d2040000580200006c02000077fdfebd",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/sim_watch_sync.dart"
        );
    }
}
