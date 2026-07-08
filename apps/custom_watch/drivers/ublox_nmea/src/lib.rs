//! Streaming NMEA-0183 parser for u-blox MAX-M10S output.
//!
//! `no_std`, no allocations — feed bytes from a UART buffer and get parsed
//! `Sentence` values back. Designed for host testability: the parser itself
//! doesn't touch peripherals, so `bin/watch-test.sh` (which excludes
//! embedded-only crates) covers it without a board.
//!
//! Talker-agnostic: `$GPRMC`, `$GNRMC`, `$GLRMC` all parse as RMC — the
//! MAX-M10S emits `GN` talkers in multi-GNSS mode, older fixtures use `GP`.
//! Sentences carried: RMC (validity + position + speed + course) and GGA
//! (fix quality + satellite count + altitude). Everything else, including
//! GSV, returns `Sentence::Other` so callers can count-but-ignore it.

#![no_std]

/// NMEA 0183 caps sentences at 82 chars including `$` and CRLF; leave slack
/// for out-of-spec receivers.
const BUF_LEN: usize = 100;

/// Seconds since midnight UTC, from the hhmmss.ss field (fraction dropped).
pub type TimeOfDay = u32;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RmcData {
    pub time: Option<TimeOfDay>,
    /// Receiver marked the fix valid (`A` status).
    pub valid: bool,
    pub lat_deg: Option<f64>,
    pub lon_deg: Option<f64>,
    pub speed_mps: Option<f32>,
    pub course_deg: Option<f32>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GgaData {
    pub time: Option<TimeOfDay>,
    pub lat_deg: Option<f64>,
    pub lon_deg: Option<f64>,
    /// 0 = no fix, 1 = GPS, 2 = DGPS, ...
    pub quality: u8,
    pub sats: u8,
    pub alt_m: Option<f32>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Sentence {
    Rmc(RmcData),
    Gga(GgaData),
    /// Valid checksum, but a type we don't decode (GSV, VTG, ...).
    Other,
}

/// Byte-at-a-time NMEA assembler + parser.
///
/// Bytes before the `$` framing character are discarded, so the parser can
/// be handed a UART stream mid-sentence and recovers on the next frame.
/// Oversized or checksum-failing sentences are dropped silently — on a noisy
/// UART that's routine, not exceptional.
pub struct Parser {
    buf: [u8; BUF_LEN],
    len: usize,
    in_sentence: bool,
}

impl Default for Parser {
    fn default() -> Self {
        Self::new()
    }
}

impl Parser {
    pub const fn new() -> Self {
        Self { buf: [0; BUF_LEN], len: 0, in_sentence: false }
    }

    /// Feed one byte; returns a parsed sentence when this byte completes one.
    pub fn feed(&mut self, byte: u8) -> Option<Sentence> {
        match byte {
            b'$' => {
                self.len = 0;
                self.in_sentence = true;
                None
            }
            b'\r' | b'\n' => {
                if !self.in_sentence {
                    return None;
                }
                self.in_sentence = false;
                let result = parse_sentence(&self.buf[..self.len]);
                self.len = 0;
                result
            }
            _ => {
                if self.in_sentence {
                    if self.len == BUF_LEN {
                        // Oversized: not NMEA. Drop and resync on next '$'.
                        self.in_sentence = false;
                        self.len = 0;
                    } else {
                        self.buf[self.len] = byte;
                        self.len += 1;
                    }
                }
                None
            }
        }
    }
}

/// Parse one sentence body (between `$` and CRLF, checksum still attached).
fn parse_sentence(body: &[u8]) -> Option<Sentence> {
    let star = body.iter().position(|&b| b == b'*')?;
    let (payload, tail) = body.split_at(star);
    let expected = hex_byte(tail.get(1..3)?)?;
    let actual = payload.iter().fold(0u8, |c, &b| c ^ b);
    if expected != actual {
        return None;
    }

    let mut fields = Fields::new(payload);
    let kind = fields.next()?;
    // Strip the two-char talker prefix: "GPRMC"/"GNRMC" -> "RMC".
    let kind = kind.get(kind.len().saturating_sub(3)..)?;
    match kind {
        b"RMC" => parse_rmc(&mut fields).map(Sentence::Rmc),
        b"GGA" => parse_gga(&mut fields).map(Sentence::Gga),
        _ => Some(Sentence::Other),
    }
}

fn parse_rmc(f: &mut Fields) -> Option<RmcData> {
    let time = parse_time(f.next()?);
    let valid = f.next()? == b"A";
    let lat_deg = parse_coord(f.next()?, f.next()?, 2);
    let lon_deg = parse_coord(f.next()?, f.next()?, 3);
    let speed_mps = parse_f32(f.next()?).map(|kn| kn * 0.514_444);
    let course_deg = parse_f32(f.next()?);
    Some(RmcData { time, valid, lat_deg, lon_deg, speed_mps, course_deg })
}

fn parse_gga(f: &mut Fields) -> Option<GgaData> {
    let time = parse_time(f.next()?);
    let lat_deg = parse_coord(f.next()?, f.next()?, 2);
    let lon_deg = parse_coord(f.next()?, f.next()?, 3);
    let quality = parse_u32(f.next()?).unwrap_or(0) as u8;
    let sats = parse_u32(f.next()?).unwrap_or(0) as u8;
    let _hdop = f.next()?;
    let alt_m = parse_f32(f.next()?);
    Some(GgaData { time, lat_deg, lon_deg, quality, sats, alt_m })
}

/// Comma-separated field iterator over the payload after the type field.
struct Fields<'a> {
    rest: &'a [u8],
    done: bool,
}

impl<'a> Fields<'a> {
    fn new(payload: &'a [u8]) -> Self {
        Self { rest: payload, done: false }
    }

    #[allow(clippy::should_implement_trait)]
    fn next(&mut self) -> Option<&'a [u8]> {
        if self.done {
            return None;
        }
        match self.rest.iter().position(|&b| b == b',') {
            Some(i) => {
                let field = &self.rest[..i];
                self.rest = &self.rest[i + 1..];
                Some(field)
            }
            None => {
                self.done = true;
                Some(self.rest)
            }
        }
    }
}

fn hex_byte(two: &[u8]) -> Option<u8> {
    fn nibble(b: u8) -> Option<u8> {
        match b {
            b'0'..=b'9' => Some(b - b'0'),
            b'A'..=b'F' => Some(b - b'A' + 10),
            b'a'..=b'f' => Some(b - b'a' + 10),
            _ => None,
        }
    }
    Some(nibble(*two.first()?)? << 4 | nibble(*two.get(1)?)?)
}

/// hhmmss.ss -> seconds since midnight. Fraction dropped.
fn parse_time(field: &[u8]) -> Option<TimeOfDay> {
    if field.len() < 6 {
        return None;
    }
    let d = |i: usize| -> Option<u32> {
        match field[i] {
            b @ b'0'..=b'9' => Some((b - b'0') as u32),
            _ => None,
        }
    };
    let h = d(0)? * 10 + d(1)?;
    let m = d(2)? * 10 + d(3)?;
    let s = d(4)? * 10 + d(5)?;
    Some(h * 3600 + m * 60 + s)
}

/// NMEA coordinate: `ddmm.mmmm` (lat, deg_digits = 2) or `dddmm.mmmm`
/// (lon, deg_digits = 3) plus a hemisphere field (N/S/E/W).
fn parse_coord(value: &[u8], hemi: &[u8], deg_digits: usize) -> Option<f64> {
    if value.len() < deg_digits + 2 {
        return None;
    }
    let deg = parse_u32(&value[..deg_digits])? as f64;
    let min = parse_f64(&value[deg_digits..])?;
    let unsigned = deg + min / 60.0;
    match hemi {
        b"N" | b"E" => Some(unsigned),
        b"S" | b"W" => Some(-unsigned),
        _ => None,
    }
}

fn parse_u32(field: &[u8]) -> Option<u32> {
    if field.is_empty() {
        return None;
    }
    let mut v: u32 = 0;
    for &b in field {
        match b {
            b'0'..=b'9' => v = v.checked_mul(10)?.checked_add((b - b'0') as u32)?,
            _ => return None,
        }
    }
    Some(v)
}

fn parse_f64(field: &[u8]) -> Option<f64> {
    if field.is_empty() {
        return None;
    }
    let (neg, digits) = match field[0] {
        b'-' => (true, &field[1..]),
        _ => (false, field),
    };
    let mut int: f64 = 0.0;
    let mut frac: f64 = 0.0;
    let mut scale: f64 = 1.0;
    let mut seen_dot = false;
    let mut seen_digit = false;
    for &b in digits {
        match b {
            b'.' if !seen_dot => seen_dot = true,
            b'0'..=b'9' => {
                seen_digit = true;
                let d = (b - b'0') as f64;
                if seen_dot {
                    scale *= 10.0;
                    frac += d / scale;
                } else {
                    int = int * 10.0 + d;
                }
            }
            _ => return None,
        }
    }
    if !seen_digit {
        return None;
    }
    let v = int + frac;
    Some(if neg { -v } else { v })
}

fn parse_f32(field: &[u8]) -> Option<f32> {
    parse_f64(field).map(|v| v as f32)
}
