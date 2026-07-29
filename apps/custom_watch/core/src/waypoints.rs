//! Mid-run waypoint marking: save the current position — a gear cache, a
//! water stash, where the trail was lost — and read back a distance-and-
//! bearing view to it (the roadmap's "Waypoint marking / save location"
//! parity row).
//!
//! [`Waypoints`] is a fixed-capacity, newest-last store: the mark past
//! [`MAX_WAYPOINTS`] evicts the OLDEST, because a runner marking a ninth
//! point mid-race cares about the new one, not the stalest.
//! [`view`](Waypoints::view) is the same geometry [`crate::trackback`] uses
//! for back-to-start — the canonical [`haversine_metres`] plus the
//! great-circle initial bearing — aimed at the LATEST mark. Pure logic like
//! the rest of `core`: no peripherals, no allocator.
//!
//! The WPT1 codec persists the store so a reboot keeps the marks:
//! `magic("WPT1", 4) | version(1) | count(1) | reserved(2) | entry[count] |
//! crc32(4, u32 LE over everything before it)`, each entry
//! `lat_e7(i32 LE) | lon_e7(i32 LE) | marked_uptime_s(u32 LE)` — the same
//! 1e-7-degree integer scaling as [`crate::run_store`] track points, so a
//! round trip quantises lat/lon to 1e-7 degrees (~1 cm). Fail-closed like
//! the CFG1 record in [`crate::flash_store`]: a short buffer, bad magic,
//! unknown version, oversize count, failed CRC, or an out-of-range point
//! reads as "no saved waypoints" — never a partial store. Bytes past the
//! record are ignored, so the caller hands the whole fixed-length flash read
//! (a [`MAX_WPT1_LEN`] buffer, erased 0xFF tail and all) straight to
//! [`Waypoints::decode`].

use crate::grade_adjusted_pace::haversine_metres;
use crate::run_store::crc32;

pub const MAX_WAYPOINTS: usize = 8;

/// Waypoint record magic — "WPT1".
pub const WPT1_MAGIC: [u8; 4] = *b"WPT1";

pub const WPT1_VERSION: u8 = 1;

/// Header: magic(4) + version(1) + count(1) + reserved(2).
pub const WPT1_HEADER_LEN: usize = 8;

/// One entry: lat_e7(4) + lon_e7(4) + marked_uptime_s(4).
pub const WPT1_ENTRY_LEN: usize = 12;

const WPT1_CRC_LEN: usize = 4;

/// Largest a WPT1 record can be — the caller's encode / flash-read buffer.
pub const MAX_WPT1_LEN: usize = WPT1_HEADER_LEN + MAX_WAYPOINTS * WPT1_ENTRY_LEN + WPT1_CRC_LEN;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Waypoint {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub marked_uptime_s: u32,
}

/// Distance + initial great-circle bearing from the current position to the
/// latest waypoint, published to the UI.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WaypointView {
    pub distance_m: f32,
    /// Degrees clockwise from north in `[0, 360)`.
    pub bearing_deg: f32,
    pub count: u8,
    pub marked_uptime_s: u32,
}

/// Great-circle initial bearing from point 1 toward point 2, degrees clockwise
/// from north in `[0, 360)` — the same formula as [`crate::trackback`]'s.
fn initial_bearing_deg(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let p1 = lat1.to_radians();
    let p2 = lat2.to_radians();
    let dl = (lon2 - lon1).to_radians();
    let y = libm::sin(dl) * libm::cos(p2);
    let x = libm::cos(p1) * libm::sin(p2) - libm::sin(p1) * libm::cos(p2) * libm::cos(dl);
    (libm::atan2(y, x).to_degrees() + 360.0) % 360.0
}

/// Fixed-capacity waypoint store, newest-last.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Waypoints {
    points: heapless::Vec<Waypoint, MAX_WAYPOINTS>,
}

impl Waypoints {
    pub const fn new() -> Self {
        Self {
            points: heapless::Vec::new(),
        }
    }

    /// Mark the current position. A non-finite or out-of-range coordinate
    /// (`|lat| > 90`, `|lon| > 180`) is a no-op returning `false`; a valid
    /// mark appends newest-last, evicting the oldest when full, and returns
    /// `true`.
    pub fn mark(&mut self, lat_deg: f64, lon_deg: f64, uptime_s: u32) -> bool {
        // The range gates double as the finiteness gates: NaN fails every
        // comparison and each infinity falls outside its bound.
        if !(-90.0..=90.0).contains(&lat_deg) || !(-180.0..=180.0).contains(&lon_deg) {
            return false;
        }
        if self.points.is_full() {
            self.points.remove(0);
        }
        self.points
            .push(Waypoint {
                lat_deg,
                lon_deg,
                marked_uptime_s: uptime_s,
            })
            .is_ok()
    }

    pub fn latest(&self) -> Option<&Waypoint> {
        self.points.last()
    }

    pub fn len(&self) -> usize {
        self.points.len()
    }

    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }

    pub fn as_slice(&self) -> &[Waypoint] {
        &self.points
    }

    pub fn clear(&mut self) {
        self.points.clear();
    }

    /// Distance + initial bearing from the current position to the LATEST
    /// waypoint. `None` when the store is empty or the current position is
    /// non-finite — no honest arrow exists in either case.
    pub fn view(&self, cur_lat_deg: f64, cur_lon_deg: f64) -> Option<WaypointView> {
        let wp = self.latest()?;
        if !cur_lat_deg.is_finite() || !cur_lon_deg.is_finite() {
            return None;
        }
        Some(WaypointView {
            distance_m: haversine_metres(cur_lat_deg, cur_lon_deg, wp.lat_deg, wp.lon_deg) as f32,
            bearing_deg: initial_bearing_deg(cur_lat_deg, cur_lon_deg, wp.lat_deg, wp.lon_deg)
                as f32,
            count: self.points.len() as u8,
            marked_uptime_s: wp.marked_uptime_s,
        })
    }

    /// Encode the store as a WPT1 record into `out`, returning the byte
    /// length written, or `None` when `out` is too small. lat/lon are
    /// quantised to 1e-7 degrees (round half away from zero, matching the
    /// course codec), then the CRC32 trailer seals everything before it.
    pub fn encode(&self, out: &mut [u8]) -> Option<usize> {
        let len = WPT1_HEADER_LEN + self.points.len() * WPT1_ENTRY_LEN + WPT1_CRC_LEN;
        if out.len() < len {
            return None;
        }
        out[0..4].copy_from_slice(&WPT1_MAGIC);
        out[4] = WPT1_VERSION;
        out[5] = self.points.len() as u8;
        out[6] = 0;
        out[7] = 0;
        let mut off = WPT1_HEADER_LEN;
        for w in &self.points {
            let lat_e7 = libm::round(w.lat_deg * 1e7) as i32;
            let lon_e7 = libm::round(w.lon_deg * 1e7) as i32;
            out[off..off + 4].copy_from_slice(&lat_e7.to_le_bytes());
            out[off + 4..off + 8].copy_from_slice(&lon_e7.to_le_bytes());
            out[off + 8..off + 12].copy_from_slice(&w.marked_uptime_s.to_le_bytes());
            off += WPT1_ENTRY_LEN;
        }
        let crc = crc32(&out[..off]).to_le_bytes();
        out[off..off + WPT1_CRC_LEN].copy_from_slice(&crc);
        Some(len)
    }

    /// Decode a WPT1 record. `None` on a short buffer, bad magic, unknown
    /// version, a count past [`MAX_WAYPOINTS`], a buffer shorter than the
    /// declared count needs, a CRC that doesn't match the bytes it covers, or
    /// any out-of-range point — never a partial store. Bytes past the record
    /// (an erased flash tail) are ignored.
    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < WPT1_HEADER_LEN || b[0..4] != WPT1_MAGIC || b[4] != WPT1_VERSION {
            return None;
        }
        let count = b[5] as usize;
        if count > MAX_WAYPOINTS {
            return None;
        }
        let len = WPT1_HEADER_LEN + count * WPT1_ENTRY_LEN + WPT1_CRC_LEN;
        if b.len() < len {
            return None;
        }
        let body = len - WPT1_CRC_LEN;
        let stored = u32::from_le_bytes([b[body], b[body + 1], b[body + 2], b[body + 3]]);
        if crc32(&b[..body]) != stored {
            return None;
        }
        let mut points: heapless::Vec<Waypoint, MAX_WAYPOINTS> = heapless::Vec::new();
        let mut off = WPT1_HEADER_LEN;
        for _ in 0..count {
            let lat_e7 = i32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]]);
            let lon_e7 = i32::from_le_bytes([b[off + 4], b[off + 5], b[off + 6], b[off + 7]]);
            if !(-900_000_000..=900_000_000).contains(&lat_e7)
                || !(-1_800_000_000..=1_800_000_000).contains(&lon_e7)
            {
                return None;
            }
            points
                .push(Waypoint {
                    lat_deg: lat_e7 as f64 / 1e7,
                    lon_deg: lon_e7 as f64 / 1e7,
                    marked_uptime_s: u32::from_le_bytes([
                        b[off + 8],
                        b[off + 9],
                        b[off + 10],
                        b[off + 11],
                    ]),
                })
                .ok()?;
            off += WPT1_ENTRY_LEN;
        }
        Some(Self { points })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LAT0: f64 = 40.0;
    const LON0: f64 = -105.0;

    /// 0.001 degrees of great-circle arc on the R = 6371 km sphere:
    /// 6_371_000 * 0.001 * pi / 180 = 111.1949 m.
    const ARC_MDEG_M: f32 = 111.1949;

    fn marked(n: u32) -> Waypoints {
        let mut wpts = Waypoints::new();
        for i in 0..n {
            assert!(wpts.mark(LAT0 + i as f64 * 0.001, LON0 - i as f64 * 0.002, i * 10));
        }
        wpts
    }

    #[test]
    fn mark_appends_newest_last() {
        let wpts = marked(3);
        assert_eq!(wpts.len(), 3);
        assert!(!wpts.is_empty());
        let uptimes: heapless::Vec<u32, 8> =
            wpts.as_slice().iter().map(|w| w.marked_uptime_s).collect();
        assert_eq!(uptimes.as_slice(), &[0, 10, 20]);
        assert_eq!(wpts.latest().unwrap().marked_uptime_s, 20);
    }

    #[test]
    fn mark_rejects_non_finite_and_out_of_range() {
        let mut wpts = marked(2);
        for (lat, lon) in [
            (f64::NAN, LON0),
            (LAT0, f64::NAN),
            (f64::INFINITY, LON0),
            (LAT0, f64::NEG_INFINITY),
            (90.000_001, LON0),
            (-90.000_001, LON0),
            (LAT0, 180.000_001),
            (LAT0, -180.000_001),
        ] {
            assert!(!wpts.mark(lat, lon, 99), "({lat}, {lon}) must be rejected");
        }
        assert_eq!(wpts.len(), 2, "a rejected mark is a no-op");
        assert_eq!(wpts.latest().unwrap().marked_uptime_s, 10);

        assert!(
            wpts.mark(90.0, 180.0, 30),
            "the poles/antimeridian are valid"
        );
        assert!(wpts.mark(-90.0, -180.0, 40));
    }

    #[test]
    fn a_full_store_evicts_the_oldest() {
        let mut wpts = marked(MAX_WAYPOINTS as u32);
        assert_eq!(wpts.len(), MAX_WAYPOINTS);
        assert!(wpts.mark(LAT0, LON0, 999));
        assert_eq!(wpts.len(), MAX_WAYPOINTS, "capacity holds");
        assert_eq!(
            wpts.as_slice()[0].marked_uptime_s,
            10,
            "the oldest mark is the one evicted"
        );
        assert_eq!(wpts.latest().unwrap().marked_uptime_s, 999);
        assert!(wpts.mark(LAT0, LON0, 1000));
        assert_eq!(wpts.as_slice()[0].marked_uptime_s, 20);
    }

    #[test]
    fn clear_empties_the_store() {
        let mut wpts = marked(2);
        wpts.clear();
        assert_eq!(wpts.len(), 0);
        assert!(wpts.is_empty());
        assert!(wpts.latest().is_none());
        assert!(wpts.view(LAT0, LON0).is_none());
    }

    #[test]
    fn view_distance_and_bearing_due_north() {
        let mut wpts = Waypoints::new();
        assert!(wpts.mark(LAT0 + 0.001, LON0, 5));
        let v = wpts.view(LAT0, LON0).unwrap();
        assert!(
            (v.distance_m - ARC_MDEG_M).abs() < 0.5,
            "distance {}",
            v.distance_m
        );
        assert!(v.bearing_deg.abs() < 0.01, "bearing {}", v.bearing_deg);
        assert_eq!(v.count, 1);
        assert_eq!(v.marked_uptime_s, 5);
    }

    #[test]
    fn view_bearing_due_east_at_the_equator() {
        let mut wpts = Waypoints::new();
        assert!(wpts.mark(0.0, 0.001, 1));
        let v = wpts.view(0.0, 0.0).unwrap();
        assert!(
            (v.distance_m - ARC_MDEG_M).abs() < 0.5,
            "distance {}",
            v.distance_m
        );
        assert!(
            (v.bearing_deg - 90.0).abs() < 0.01,
            "bearing {}",
            v.bearing_deg
        );
    }

    #[test]
    fn view_targets_the_latest_waypoint() {
        let mut wpts = Waypoints::new();
        assert!(wpts.mark(LAT0 + 1.0, LON0, 1), "~111 km north");
        assert!(wpts.mark(LAT0, LON0 - 0.001, 2), "~85 m west");
        let v = wpts.view(LAT0, LON0).unwrap();
        assert!(v.distance_m < 100.0, "the latest mark, not the first");
        assert!(
            (v.bearing_deg - 270.0).abs() < 0.1,
            "bearing {}",
            v.bearing_deg
        );
        assert_eq!(v.count, 2);
        assert_eq!(v.marked_uptime_s, 2);
    }

    #[test]
    fn view_none_when_empty_or_position_non_finite() {
        let wpts = Waypoints::new();
        assert!(wpts.view(LAT0, LON0).is_none());

        let wpts = marked(1);
        assert!(wpts.view(f64::NAN, LON0).is_none());
        assert!(wpts.view(LAT0, f64::INFINITY).is_none());
        assert!(wpts.view(LAT0, LON0).is_some());
    }

    #[test]
    fn view_at_the_waypoint_reads_zero_not_nan() {
        let mut wpts = Waypoints::new();
        assert!(wpts.mark(LAT0, LON0, 7));
        let v = wpts.view(LAT0, LON0).unwrap();
        assert_eq!(v.distance_m, 0.0);
        assert_eq!(v.bearing_deg, 0.0);
    }

    #[test]
    fn codec_round_trips() {
        let wpts = marked(3);
        let mut buf = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut buf).expect("encode");
        assert_eq!(n, WPT1_HEADER_LEN + 3 * WPT1_ENTRY_LEN + 4);
        let decoded = Waypoints::decode(&buf[..n]).expect("decode");
        assert_eq!(decoded.len(), 3);
        for (d, w) in decoded.as_slice().iter().zip(wpts.as_slice()) {
            assert!(
                (d.lat_deg - w.lat_deg).abs() <= 5e-8,
                "lat within a half-quantum"
            );
            assert!(
                (d.lon_deg - w.lon_deg).abs() <= 5e-8,
                "lon within a half-quantum"
            );
            assert_eq!(d.marked_uptime_s, w.marked_uptime_s);
        }
    }

    #[test]
    fn codec_round_trips_a_full_store_at_max_len() {
        let wpts = marked(MAX_WAYPOINTS as u32);
        let mut buf = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut buf).expect("encode");
        assert_eq!(n, MAX_WPT1_LEN);
        let decoded = Waypoints::decode(&buf).expect("decode");
        assert_eq!(decoded.len(), MAX_WAYPOINTS);
        assert_eq!(
            decoded.latest().unwrap().marked_uptime_s,
            wpts.latest().unwrap().marked_uptime_s
        );
    }

    #[test]
    fn codec_round_trips_an_empty_store() {
        let wpts = Waypoints::new();
        let mut buf = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut buf).expect("encode");
        assert_eq!(n, WPT1_HEADER_LEN + 4);
        let decoded = Waypoints::decode(&buf[..n]).expect("decode");
        assert!(decoded.is_empty());
    }

    #[test]
    fn encode_rejects_a_short_buffer() {
        let wpts = marked(2);
        let needed = WPT1_HEADER_LEN + 2 * WPT1_ENTRY_LEN + 4;
        let mut buf = [0u8; MAX_WPT1_LEN];
        assert!(wpts.encode(&mut buf[..needed - 1]).is_none());
        assert_eq!(wpts.encode(&mut buf[..needed]), Some(needed));
    }

    #[test]
    fn decode_tolerates_an_erased_flash_tail() {
        // The caller hands decode the whole fixed-length flash read; a
        // shorter-than-max record is followed by erased 0xFF bytes.
        let wpts = marked(2);
        let mut buf = [0xFFu8; MAX_WPT1_LEN];
        wpts.encode(&mut buf).expect("encode");
        let decoded = Waypoints::decode(&buf).expect("decode past the tail");
        assert_eq!(decoded.len(), 2);
    }

    #[test]
    fn decode_rejects_truncation() {
        let wpts = marked(MAX_WAYPOINTS as u32);
        let mut buf = [0u8; MAX_WPT1_LEN];
        wpts.encode(&mut buf).expect("encode");
        for len in 0..MAX_WPT1_LEN {
            assert!(
                Waypoints::decode(&buf[..len]).is_none(),
                "truncation to {len} must be rejected"
            );
        }
    }

    #[test]
    fn decode_rejects_any_flipped_byte() {
        let wpts = marked(3);
        let mut clean = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut clean).expect("encode");
        for at in 0..n {
            let mut buf = clean;
            buf[at] ^= 0x01;
            assert!(
                Waypoints::decode(&buf[..n]).is_none(),
                "byte {at} is unprotected"
            );
        }
    }

    #[test]
    fn decode_rejects_an_unknown_version() {
        let wpts = marked(1);
        let mut buf = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut buf).expect("encode");
        for version in [0u8, 2, 0xFF] {
            let mut b = buf;
            b[4] = version;
            let body = n - 4;
            let crc = crc32(&b[..body]);
            b[body..n].copy_from_slice(&crc.to_le_bytes());
            assert!(
                Waypoints::decode(&b[..n]).is_none(),
                "version {version} must be rejected even with a valid CRC"
            );
        }
    }

    #[test]
    fn decode_rejects_an_oversize_count_even_with_a_valid_crc() {
        const LEN: usize = WPT1_HEADER_LEN + (MAX_WAYPOINTS + 1) * WPT1_ENTRY_LEN + 4;
        let mut buf = [0u8; LEN];
        buf[0..4].copy_from_slice(&WPT1_MAGIC);
        buf[4] = WPT1_VERSION;
        buf[5] = MAX_WAYPOINTS as u8 + 1;
        let crc = crc32(&buf[..LEN - 4]);
        buf[LEN - 4..].copy_from_slice(&crc.to_le_bytes());
        assert!(Waypoints::decode(&buf).is_none());
    }

    fn one_entry_record(lat_e7: i32, lon_e7: i32) -> [u8; WPT1_HEADER_LEN + WPT1_ENTRY_LEN + 4] {
        let mut buf = [0u8; WPT1_HEADER_LEN + WPT1_ENTRY_LEN + 4];
        buf[0..4].copy_from_slice(&WPT1_MAGIC);
        buf[4] = WPT1_VERSION;
        buf[5] = 1;
        buf[8..12].copy_from_slice(&lat_e7.to_le_bytes());
        buf[12..16].copy_from_slice(&lon_e7.to_le_bytes());
        buf[16..20].copy_from_slice(&7u32.to_le_bytes());
        let crc = crc32(&buf[..20]);
        buf[20..24].copy_from_slice(&crc.to_le_bytes());
        buf
    }

    #[test]
    fn decode_rejects_an_out_of_range_point_even_with_a_valid_crc() {
        for (lat_e7, lon_e7) in [
            (900_000_001, 0),
            (-900_000_001, 0),
            (0, 1_800_000_001),
            (0, -1_800_000_001),
            (i32::MAX, 0),
            (0, i32::MIN),
        ] {
            assert!(
                Waypoints::decode(&one_entry_record(lat_e7, lon_e7)).is_none(),
                "({lat_e7}, {lon_e7}) must reject the whole record"
            );
        }
        let decoded =
            Waypoints::decode(&one_entry_record(900_000_000, -1_800_000_000)).expect("boundary");
        let w = decoded.latest().unwrap();
        assert_eq!(w.lat_deg, 90.0);
        assert_eq!(w.lon_deg, -180.0);
        assert_eq!(w.marked_uptime_s, 7);
    }

    #[test]
    fn round_trip_quantises_to_1e7_degrees() {
        let mut wpts = Waypoints::new();
        assert!(wpts.mark(40.123_456_751, -105.987_654_349, 3));
        let mut buf = [0u8; MAX_WPT1_LEN];
        let n = wpts.encode(&mut buf).expect("encode");
        let decoded = Waypoints::decode(&buf[..n]).expect("decode");
        let w = decoded.latest().unwrap();
        assert_eq!(w.lat_deg, 40.123_456_8, "rounded up to the 1e-7 grid");
        assert_eq!(
            w.lon_deg, -105.987_654_3,
            "rounded toward the grid, not truncated"
        );
        assert_eq!(w.marked_uptime_s, 3);

        // A value already on the grid survives the round trip exactly.
        let mut on_grid = Waypoints::new();
        assert!(on_grid.mark(40.015_020_0, -105.270_500_0, 4));
        let n = on_grid.encode(&mut buf).expect("encode");
        let w = *Waypoints::decode(&buf[..n])
            .expect("decode")
            .latest()
            .unwrap();
        assert_eq!(w.lat_deg, 40.015_020_0);
        assert_eq!(w.lon_deg, -105.270_500_0);
    }
}
