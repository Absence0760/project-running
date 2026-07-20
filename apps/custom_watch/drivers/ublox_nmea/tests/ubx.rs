//! Host-side UBX encoder tests. Run via `bin/watch-test.sh` from the repo
//! root, or `cargo test --target <HOST_TRIPLE> -p ublox_nmea` from anywhere.

use ublox_nmea::ubx;

/// A published known-good UBX frame, independent of any byte this crate
/// produces: the UBX-CFG-RATE example (1000 ms measurement rate, nav rate 1,
/// UTC aligned) that appears across u-blox integration guides —
/// `B5 62 06 08 06 00 E8 03 01 00 01 00` with Fletcher checksum `01 39`.
const CFG_RATE_1HZ: [u8; 14] = [
    0xB5, 0x62, 0x06, 0x08, 0x06, 0x00, 0xE8, 0x03, 0x01, 0x00, 0x01, 0x00, 0x01, 0x39,
];

#[test]
fn checksum_matches_the_published_cfg_rate_vector() {
    // Checksum runs over class..payload — sync chars and the checksum itself
    // excluded.
    assert_eq!(ubx::checksum(&CFG_RATE_1HZ[2..12]), (0x01, 0x39));
}

#[test]
fn write_frame_reproduces_the_published_vector() {
    let mut out = [0u8; CFG_RATE_1HZ.len()];
    let n = ubx::write_frame(0x06, 0x08, &CFG_RATE_1HZ[6..12], &mut out);
    assert_eq!(n, Some(CFG_RATE_1HZ.len()));
    assert_eq!(out, CFG_RATE_1HZ);
}

#[test]
fn write_frame_encodes_the_length_little_endian() {
    // A 300-byte payload exercises both length bytes: 300 = 0x012C.
    let payload = [0u8; 300];
    let mut out = [0u8; 308];
    assert_eq!(ubx::write_frame(0x01, 0x02, &payload, &mut out), Some(308));
    assert_eq!(&out[4..6], &[0x2C, 0x01]);
}

#[test]
fn write_frame_handles_an_empty_payload() {
    // Smallest legal frame: framing + checksum only. Checksum still covers
    // class/id/length.
    let mut out = [0u8; ubx::FRAME_OVERHEAD];
    assert_eq!(
        ubx::write_frame(0x0A, 0x04, &[], &mut out),
        Some(ubx::FRAME_OVERHEAD)
    );
    let (ck_a, ck_b) = ubx::checksum(&out[2..6]);
    assert_eq!(&out[..6], &[0xB5, 0x62, 0x0A, 0x04, 0x00, 0x00]);
    assert_eq!(&out[6..], &[ck_a, ck_b]);
}

#[test]
fn write_frame_refuses_a_too_small_buffer() {
    let mut out = [0u8; ubx::PMREQ_FRAME_LEN - 1];
    assert_eq!(ubx::write_frame(0x02, 0x41, &[0; 16], &mut out), None);
}

#[test]
fn write_frame_refuses_a_payload_past_the_length_field() {
    // The u16 length field caps a payload at 65535 bytes; longer must be
    // refused, never silently truncated into a valid-looking frame.
    let payload = vec![0u8; u16::MAX as usize + 1];
    let mut out = vec![0u8; payload.len() + ubx::FRAME_OVERHEAD];
    assert_eq!(ubx::write_frame(0x02, 0x41, &payload, &mut out), None);
}

#[test]
fn pmreq_frame_bytes_are_pinned() {
    // Derived by hand from the UBX protocol spec (M10 interface description):
    // extended 16-byte RXM-PMREQ payload — version 0 + reserved, duration
    // 10 000 ms, flags = backup (bit 1), wakeupSources = uartrx (bit 3) —
    // with the 8-bit Fletcher checksum computed over class..payload.
    let expected: [u8; ubx::PMREQ_FRAME_LEN] = [
        0xB5, 0x62, // sync
        0x02, 0x41, // class RXM, id PMREQ
        0x10, 0x00, // length 16, little-endian
        0x00, 0x00, 0x00, 0x00, // version 0 + reserved[3]
        0x10, 0x27, 0x00, 0x00, // duration 10 000 ms, little-endian
        0x02, 0x00, 0x00, 0x00, // flags: backup
        0x08, 0x00, 0x00, 0x00, // wakeupSources: uartrx
        0x94, 0xB8, // Fletcher checksum
    ];
    assert_eq!(ubx::pmreq_backup(10_000), expected);
}

#[test]
fn pmreq_duration_is_little_endian() {
    let frame = ubx::pmreq_backup(0x0102_0304);
    assert_eq!(&frame[10..14], &[0x04, 0x03, 0x02, 0x01]);
}

#[test]
fn pmreq_never_encodes_an_unbounded_sleep() {
    // Duration 0 means "no time limit" to the receiver — with a lost wake
    // byte that is a receiver asleep forever. A zero request must clamp to
    // the shortest bounded sleep instead.
    let frame = ubx::pmreq_backup(0);
    assert_eq!(&frame[10..14], &[0x01, 0x00, 0x00, 0x00]);
}

#[test]
fn pmreq_checksum_stays_consistent_for_any_duration() {
    for duration_ms in [1, 999, 57_000, u32::MAX] {
        let frame = ubx::pmreq_backup(duration_ms);
        let (ck_a, ck_b) = ubx::checksum(&frame[2..ubx::PMREQ_FRAME_LEN - 2]);
        assert_eq!(
            &frame[ubx::PMREQ_FRAME_LEN - 2..],
            &[ck_a, ck_b],
            "checksum drifted at duration {duration_ms}"
        );
    }
}

#[test]
fn wake_byte_is_the_documented_dummy() {
    // 0xFF is what u-blox documents as the byte a sleeping receiver consumes
    // without parsing; it must also never look like NMEA or UBX framing.
    assert_eq!(ubx::WAKE_BYTE, 0xFF);
    assert_ne!(ubx::WAKE_BYTE, b'$');
    assert_ne!(ubx::WAKE_BYTE, ubx::SYNC1);
}
