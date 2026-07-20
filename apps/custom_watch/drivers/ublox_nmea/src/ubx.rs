//! UBX binary frame encoding — the transmit side of talking to the u-blox
//! receiver (the rest of this crate parses its NMEA output).
//!
//! Only the frames the firmware actually sends are provided; this is not a
//! generic UBX message catalogue. Today that is one message:
//! **UBX-RXM-PMREQ** — the tier-1 breakout's software power-down path (no
//! load switch): put the receiver into backup mode between the selected
//! recording mode's fixes. `watch_core::gnss_power` decides the windows; the
//! gps task sends the frame.
//!
//! Frame layout (u-blox interface description, "UBX frame structure"): sync
//! chars `0xB5 0x62`, message class, message id, little-endian u16 payload
//! length, payload, then a two-byte 8-bit Fletcher checksum computed over
//! class..payload (sync chars excluded).
//!
//! **PMREQ form: the extended 16-byte payload** (`version 0x00` + 3 reserved
//! bytes + `duration` ms + `flags` + `wakeupSources`), not the legacy 8-byte
//! duration+flags form. Two reasons: the M10 interface description (the
//! MAX-M10S's generation) documents the extended form, and it makes the wake
//! source explicit — [`PMREQ_WAKE_UARTRX`] — instead of leaving wake
//! behaviour to the legacy form's implicit defaults. Flags carry only
//! `backup` (bit 1); `force` (bit 2) is deliberately NOT set — it exists to
//! force backup while USB is connected, the tier-1 breakout wires no USB to
//! the module, and leaving the interlock intact costs nothing.
//!
//! Wake is any activity on the module's RX line: the sender writes
//! [`WAKE_BYTE`] (`0xFF`, the u-blox-documented dummy byte the receiver
//! consumes without parsing), then allows a reacquire window before the next
//! fix is owed. A bounded `duration` is always encoded too, as the self-wake
//! backstop for a lost wake byte — never 0, which the spec reads as "no time
//! limit" (i.e. asleep forever if the byte is lost).

/// First UBX sync char.
pub const SYNC1: u8 = 0xB5;
/// Second UBX sync char.
pub const SYNC2: u8 = 0x62;

/// UBX-RXM message class.
pub const CLASS_RXM: u8 = 0x02;
/// UBX-RXM-PMREQ message id.
pub const ID_PMREQ: u8 = 0x41;

/// Framing bytes around a payload: sync (2) + class + id + length (2) +
/// checksum (2).
pub const FRAME_OVERHEAD: usize = 8;

/// The extended PMREQ payload: version + reserved[3] + duration + flags +
/// wakeupSources, each of the last three a little-endian u32.
pub const PMREQ_PAYLOAD_LEN: usize = 16;
/// A complete PMREQ frame.
pub const PMREQ_FRAME_LEN: usize = FRAME_OVERHEAD + PMREQ_PAYLOAD_LEN;

/// The dummy byte that wakes a receiver sleeping on UART-RX activity: the
/// receiver discards `0xFF` rather than trying to parse it as the start of a
/// message, so it can never corrupt the frame that follows.
pub const WAKE_BYTE: u8 = 0xFF;

/// PMREQ `flags` bit 1: enter backup mode for the requested duration.
pub const PMREQ_FLAG_BACKUP: u32 = 1 << 1;
/// PMREQ `wakeupSources` bit 3: wake on UART RX activity.
pub const PMREQ_WAKE_UARTRX: u32 = 1 << 3;

/// 8-bit Fletcher checksum over `body` — class..payload, sync chars excluded.
pub fn checksum(body: &[u8]) -> (u8, u8) {
    let mut ck_a: u8 = 0;
    let mut ck_b: u8 = 0;
    for &b in body {
        ck_a = ck_a.wrapping_add(b);
        ck_b = ck_b.wrapping_add(ck_a);
    }
    (ck_a, ck_b)
}

/// Assemble one UBX frame into `out`; returns the frame length, or `None`
/// when `out` is too small or the payload is longer than the u16 length
/// field can carry. No allocation — callers hand a stack buffer sized by the
/// message constants above.
pub fn write_frame(class: u8, id: u8, payload: &[u8], out: &mut [u8]) -> Option<usize> {
    let frame_len = FRAME_OVERHEAD.checked_add(payload.len())?;
    if payload.len() > u16::MAX as usize || out.len() < frame_len {
        return None;
    }
    out[0] = SYNC1;
    out[1] = SYNC2;
    out[2] = class;
    out[3] = id;
    out[4..6].copy_from_slice(&(payload.len() as u16).to_le_bytes());
    out[6..6 + payload.len()].copy_from_slice(payload);
    let (ck_a, ck_b) = checksum(&out[2..6 + payload.len()]);
    out[6 + payload.len()] = ck_a;
    out[7 + payload.len()] = ck_b;
    Some(frame_len)
}

/// A ready-to-send UBX-RXM-PMREQ frame: backup mode for `duration_ms`,
/// waking on UART RX activity or the duration expiring, whichever comes
/// first.
///
/// A `duration_ms` of 0 is never encoded — the spec reads 0 as "no time
/// limit", which would strand a receiver whose wake byte got lost — so a 0
/// request becomes the shortest bounded sleep (1 ms) instead.
pub fn pmreq_backup(duration_ms: u32) -> [u8; PMREQ_FRAME_LEN] {
    let mut payload = [0u8; PMREQ_PAYLOAD_LEN];
    // payload[0] = version 0x00; payload[1..4] reserved — all already zero.
    payload[4..8].copy_from_slice(&duration_ms.max(1).to_le_bytes());
    payload[8..12].copy_from_slice(&PMREQ_FLAG_BACKUP.to_le_bytes());
    payload[12..16].copy_from_slice(&PMREQ_WAKE_UARTRX.to_le_bytes());
    let mut frame = [0u8; PMREQ_FRAME_LEN];
    let written = write_frame(CLASS_RXM, ID_PMREQ, &payload, &mut frame);
    debug_assert_eq!(written, Some(PMREQ_FRAME_LEN));
    frame
}
