//! In-Case-of-Emergency / medical ID: the few lines a responder needs off a
//! collapsed runner's wrist — who they are, blood type, allergies or
//! conditions, and who to call (the roadmap's "ICE / medical-ID idle screen"
//! parity row).
//!
//! Ultras print this on the back of a bib; the wrist is where a responder
//! looks first, and no incumbent makes it a first-class surface. The card is
//! phone-authored: the watch has no text entry, so [`IceCard`] is only ever
//! built from a `SET1` push or read back from flash, and both routes come
//! through [`IceCard::from_bytes`] — one fail-closed gate.
//!
//! **Every field fails closed rather than degrading.** A card is refused
//! whole if any field carries a byte outside printable ASCII, or any byte
//! after its NUL terminator. Truncating or blanking one field instead would
//! be worse than showing nothing: a half-rendered phone number dials the
//! wrong person, and a clipped allergy line ("PENICILL") reads as complete.
//! [`IceCard::new`] refuses an over-long field for the same reason.
//!
//! Fields are sized to the face's [`crate::face::COLS`] so each renders whole
//! on its own row — the layout is one label row above one value row, not a
//! label and value sharing 21 cells, because a responder reading a stranger's
//! wrist has no context to reconstruct an abbreviation from.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator. The
//! `ICE1` flash record ([`IceCard::encode_record`] / [`decode_record`]) keeps
//! the card across a power cycle — a medic reads the wrist of a watch that may
//! have rebooted, so the card must not live only in the RAM a push fills.

use crate::run_store::crc32;

/// Width of a text field, in bytes — one full face row, so a value never
/// needs abbreviating to fit.
pub const ICE_FIELD_LEN: usize = crate::face::COLS;

/// Width of the blood-type field. The longest real value is `AB NEG` (6);
/// the slack absorbs a spelled-out `AB NEG+` variant without a version bump.
pub const ICE_BLOOD_LEN: usize = 8;

/// The card on the wire: holder, blood, conditions, contact, phone — in that
/// order, each NUL-padded to its field width.
pub const ICE_WIRE_LEN: usize =
    ICE_FIELD_LEN + ICE_BLOOD_LEN + ICE_FIELD_LEN + ICE_FIELD_LEN + ICE_FIELD_LEN;

/// Flash record magic — "ICE1".
pub const ICE1_MAGIC: [u8; 4] = *b"ICE1";

pub const ICE1_VERSION: u8 = 1;

/// `magic(4) | version(1) | reserved(3) | payload(ICE_WIRE_LEN) | crc32(4)`.
/// A multiple of the NVMC 4-byte write word.
pub const ICE1_HEADER_LEN: usize = 8;
pub const ICE1_RECORD_LEN: usize = ICE1_HEADER_LEN + ICE_WIRE_LEN + 4;

const _: () = assert!(ICE1_RECORD_LEN.is_multiple_of(4));

/// A responder-facing medical ID. `Copy` and fixed-size so it rides the
/// settings frame and the flash record without an allocator.
///
/// Deliberately NOT `derive(defmt::Format)`: the card is a name, a blood
/// type, a medical history and a next-of-kin phone number, and a derived
/// impl would spill all four into the defmt stream every time a settings
/// frame is logged — a log a cable, a CI artifact, or a bug report then
/// carries. The hand-written impl below says only whether a card is there.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct IceCard {
    holder: [u8; ICE_FIELD_LEN],
    blood: [u8; ICE_BLOOD_LEN],
    conditions: [u8; ICE_FIELD_LEN],
    contact: [u8; ICE_FIELD_LEN],
    phone: [u8; ICE_FIELD_LEN],
}

#[cfg(feature = "defmt")]
impl defmt::Format for IceCard {
    fn format(&self, f: defmt::Formatter) {
        // Presence only — never the fields. See the type's doc.
        defmt::write!(
            f,
            "IceCard({=str})",
            if self.is_blank() { "blank" } else { "set" }
        )
    }
}

/// Copy `src` into a NUL-padded fixed field, or `None` when it does not fit
/// or carries a byte the face cannot render. Refusing beats truncating: see
/// the module doc.
fn pack<const N: usize>(src: &str) -> Option<[u8; N]> {
    let b = src.as_bytes();
    if b.len() > N || !b.iter().all(|c| printable(*c)) {
        return None;
    }
    let mut out = [0u8; N];
    out[..b.len()].copy_from_slice(b);
    Some(out)
}

/// Whether a byte is one the 1-bit face's ASCII font can draw. Control codes
/// and anything past 0x7E would render as blanks or garbage, and a medical
/// field that silently loses characters is the failure this guard exists for.
const fn printable(c: u8) -> bool {
    c >= 0x20 && c <= 0x7E
}

/// A field's text, or `None` when the bytes are not a NUL-padded run of
/// printable ASCII. The whole-card gates already reject those, so this only
/// ever answers `None` for a struct built by unsafe means — but it is the
/// same rule, spelled once.
fn unpack(field: &[u8]) -> Option<&str> {
    let end = field.iter().position(|&b| b == 0).unwrap_or(field.len());
    if !field[..end].iter().all(|c| printable(*c)) || field[end..].iter().any(|&b| b != 0) {
        return None;
    }
    core::str::from_utf8(&field[..end]).ok()
}

impl IceCard {
    /// Build a card, or `None` if any field is over-long or carries an
    /// unrenderable byte. Every field may be empty — a runner with no known
    /// allergies has an empty conditions line, which is information.
    pub fn new(
        holder: &str,
        blood: &str,
        conditions: &str,
        contact: &str,
        phone: &str,
    ) -> Option<Self> {
        Some(Self {
            holder: pack(holder)?,
            blood: pack(blood)?,
            conditions: pack(conditions)?,
            contact: pack(contact)?,
            phone: pack(phone)?,
        })
    }

    pub fn holder(&self) -> &str {
        unpack(&self.holder).unwrap_or("")
    }

    pub fn blood(&self) -> &str {
        unpack(&self.blood).unwrap_or("")
    }

    pub fn conditions(&self) -> &str {
        unpack(&self.conditions).unwrap_or("")
    }

    pub fn contact(&self) -> &str {
        unpack(&self.contact).unwrap_or("")
    }

    pub fn phone(&self) -> &str {
        unpack(&self.phone).unwrap_or("")
    }

    /// Whether every field is blank. An all-blank card is how a push CLEARS
    /// the ID — the card is still "present", it just says nothing, which the
    /// face renders as its unfed state rather than as five empty rows.
    pub fn is_blank(&self) -> bool {
        self.holder[0] == 0
            && self.blood[0] == 0
            && self.conditions[0] == 0
            && self.contact[0] == 0
            && self.phone[0] == 0
    }

    /// The card's [`ICE_WIRE_LEN`] payload, field order as documented.
    pub fn to_bytes(&self) -> [u8; ICE_WIRE_LEN] {
        let mut out = [0u8; ICE_WIRE_LEN];
        let mut off = 0;
        for src in [
            &self.holder[..],
            &self.blood[..],
            &self.conditions[..],
            &self.contact[..],
            &self.phone[..],
        ] {
            out[off..off + src.len()].copy_from_slice(src);
            off += src.len();
        }
        out
    }

    /// Parse a payload. `None` on a short buffer or ANY field that is not a
    /// NUL-padded run of printable ASCII — the whole card is refused, never a
    /// card with one field quietly blanked.
    pub fn from_bytes(b: &[u8]) -> Option<Self> {
        if b.len() < ICE_WIRE_LEN {
            return None;
        }
        let mut card = Self {
            holder: [0; ICE_FIELD_LEN],
            blood: [0; ICE_BLOOD_LEN],
            conditions: [0; ICE_FIELD_LEN],
            contact: [0; ICE_FIELD_LEN],
            phone: [0; ICE_FIELD_LEN],
        };
        let mut off = 0;
        let mut take = |n: usize| {
            let s = &b[off..off + n];
            off += n;
            unpack(s).map(|_| s)
        };
        card.holder.copy_from_slice(take(ICE_FIELD_LEN)?);
        card.blood.copy_from_slice(take(ICE_BLOOD_LEN)?);
        card.conditions.copy_from_slice(take(ICE_FIELD_LEN)?);
        card.contact.copy_from_slice(take(ICE_FIELD_LEN)?);
        card.phone.copy_from_slice(take(ICE_FIELD_LEN)?);
        Some(card)
    }

    /// Encode the `ICE1` flash record — the CRC32 trailer seals every byte
    /// before it, so a torn or erased page fails [`decode_record`].
    pub fn encode_record(&self) -> [u8; ICE1_RECORD_LEN] {
        let mut out = [0u8; ICE1_RECORD_LEN];
        out[0..4].copy_from_slice(&ICE1_MAGIC);
        out[4] = ICE1_VERSION;
        let body = ICE1_HEADER_LEN + ICE_WIRE_LEN;
        out[ICE1_HEADER_LEN..body].copy_from_slice(&self.to_bytes());
        let crc = crc32(&out[..body]).to_le_bytes();
        out[body..].copy_from_slice(&crc);
        out
    }
}

/// Decode an `ICE1` flash record. `None` on a short buffer, bad magic,
/// unknown version, a failed CRC, or a payload any field of which is not
/// printable ASCII — an erased or corrupt page reads as "no medical ID", the
/// same fail-closed rule as the `CFG1` record. Bytes past the record (an
/// erased flash tail) are ignored, so the caller can hand the whole fixed
/// flash read straight in.
pub fn decode_record(b: &[u8]) -> Option<IceCard> {
    if b.len() < ICE1_RECORD_LEN || b[0..4] != ICE1_MAGIC || b[4] != ICE1_VERSION {
        return None;
    }
    let body = ICE1_HEADER_LEN + ICE_WIRE_LEN;
    let stored = u32::from_le_bytes([b[body], b[body + 1], b[body + 2], b[body + 3]]);
    if crc32(&b[..body]) != stored {
        return None;
    }
    IceCard::from_bytes(&b[ICE1_HEADER_LEN..body])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn card() -> IceCard {
        IceCard::new(
            "ALEX MORGAN",
            "O NEG",
            "PENICILLIN, ASTHMA",
            "JAMIE MORGAN",
            "+1 555 0134",
        )
        .unwrap()
    }

    #[test]
    fn a_card_round_trips_through_the_wire_payload() {
        let c = card();
        let back = IceCard::from_bytes(&c.to_bytes()).unwrap();
        assert_eq!(back, c);
        assert_eq!(back.holder(), "ALEX MORGAN");
        assert_eq!(back.blood(), "O NEG");
        assert_eq!(back.conditions(), "PENICILLIN, ASTHMA");
        assert_eq!(back.contact(), "JAMIE MORGAN");
        assert_eq!(back.phone(), "+1 555 0134");
    }

    #[test]
    fn an_over_long_field_is_refused_not_truncated() {
        // A clipped allergy line reads as complete and a clipped number dials
        // someone else, so neither may be silently shortened.
        let too_long = "X".repeat(ICE_FIELD_LEN + 1);
        assert!(IceCard::new(&too_long, "O NEG", "", "", "").is_none());
        assert!(IceCard::new("", "", &too_long, "", "").is_none());
        assert!(IceCard::new("", "", "", "", &too_long).is_none());
        // Exactly the field width still fits.
        let exact = "Y".repeat(ICE_FIELD_LEN);
        assert_eq!(
            IceCard::new(&exact, "", "", "", "").unwrap().holder(),
            exact
        );
        // The blood field is narrower and holds its own line.
        assert!(IceCard::new("", &"A".repeat(ICE_BLOOD_LEN + 1), "", "", "").is_none());
    }

    #[test]
    fn an_unrenderable_byte_refuses_the_whole_card() {
        // The 1-bit face's font is ASCII; a byte it cannot draw would blank or
        // garble a medical line, and a garbled line still LOOKS authoritative.
        assert!(IceCard::new("ALEX\u{7}", "", "", "", "").is_none());
        assert!(IceCard::new("ALEX", "", "PENICILLIN\u{0}", "", "").is_none());
        let mut raw = card().to_bytes();
        raw[2] = 0x1F;
        assert!(IceCard::from_bytes(&raw).is_none());
        // Not one field blanked — the whole card is refused.
        raw[2] = b'E';
        assert!(IceCard::from_bytes(&raw).is_some());
    }

    #[test]
    fn a_field_with_bytes_past_its_terminator_is_refused() {
        // The tail is where a torn write or a shorter overwrite leaves the
        // previous card's bytes; reading past the NUL would show a name that
        // is half one runner and half the last one.
        let mut raw = card().to_bytes();
        raw[ICE_FIELD_LEN - 1] = b'X';
        assert!(IceCard::from_bytes(&raw).is_none());
    }

    #[test]
    fn a_short_payload_decodes_to_nothing() {
        let raw = card().to_bytes();
        assert!(IceCard::from_bytes(&raw[..ICE_WIRE_LEN - 1]).is_none());
        assert!(IceCard::from_bytes(&[]).is_none());
    }

    #[test]
    fn a_blank_card_is_representable_and_says_so() {
        let blank = IceCard::new("", "", "", "", "").unwrap();
        assert!(blank.is_blank());
        assert!(!card().is_blank());
        // A runner with no known allergies has an empty conditions line and a
        // full card — blankness is about the WHOLE card.
        assert!(!IceCard::new("ALEX", "", "", "", "").unwrap().is_blank());
    }

    #[test]
    fn the_flash_record_round_trips_and_fails_closed() {
        let c = card();
        let rec = c.encode_record();
        assert_eq!(decode_record(&rec), Some(c));
        // An erased page, a short read, a wrong magic, an unknown version and
        // a flipped payload byte all read as "no medical ID".
        assert_eq!(decode_record(&[0xFF; ICE1_RECORD_LEN]), None);
        assert_eq!(decode_record(&rec[..ICE1_RECORD_LEN - 1]), None);
        let mut bad = rec;
        bad[0] = b'X';
        assert_eq!(decode_record(&bad), None);
        let mut bad = rec;
        bad[4] = ICE1_VERSION + 1;
        assert_eq!(decode_record(&bad), None);
        let mut bad = rec;
        bad[ICE1_HEADER_LEN] ^= 0x01;
        assert_eq!(decode_record(&bad), None, "the CRC covers the payload");
    }

    #[test]
    fn an_erased_flash_tail_past_the_record_is_ignored() {
        let c = card();
        let mut buf = [0xFFu8; ICE1_RECORD_LEN + 32];
        buf[..ICE1_RECORD_LEN].copy_from_slice(&c.encode_record());
        assert_eq!(decode_record(&buf), Some(c));
    }
}
