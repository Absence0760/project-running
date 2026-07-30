//! GPS fix domain model.
//!
//! [`FixAccumulator`] reduces the NMEA sentence stream into [`Fix`] values:
//! RMC carries validity + position + speed + course, GGA carries quality +
//! satellite count + altitude, and a usable fix needs the union. The
//! accumulator keeps the latest of each and emits a merged `Fix` whenever an
//! **RMC** completes one.
//!
//! Only the position-bearing sentence may complete a fix. A GGA enriches the
//! accumulator for the next merge and returns nothing of its own, because a
//! `Fix` is a claim about where the runner is *now*: [`Fix::uptime_s`] is what
//! every consumer ages staleness against, so emitting on a GGA stamped the
//! last RMC's position with the current uptime and laundered an arbitrarily
//! old position into a fresh-looking one. Two things fell out of that on the
//! wrist. The receiver leads each 1 Hz epoch with GGA, so the accumulator
//! re-published the *previous* epoch's position before the current one
//! arrived — a zero-displacement sample the recorder reads as a stop, so a
//! runner at 5 m/s under a clear sky alternated `Recording`/`Paused` every
//! second. And across any stretch where RMC is absent — the receiver's
//! power-down window between throttled fixes, a lost sentence — the first
//! GGA back re-published the pre-gap position as current, which is exactly
//! what [`crate::elevation::rezero_reference`]'s freshness gate exists to
//! refuse.

use crate::daylight;
use ublox_nmea::{GgaData, RmcData, Sentence};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Fix {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub speed_mps: f32,
    pub course_deg: Option<f32>,
    pub sats: u8,
    pub alt_m: Option<f32>,
    /// hhmmss from the receiver, as seconds since midnight UTC.
    pub time_of_day: Option<u32>,
    /// ddmmyy from the RMC sentence, as a UTC civil date. Gated for
    /// plausibility here (day 1-31, month 1-12) so downstream date math
    /// ([`crate::daylight`]) never sees a month 0 the parser's digit check
    /// cannot reject.
    pub date: Option<daylight::Date>,
    /// Local uptime second the fix was assembled — consumers judge
    /// staleness against this, never against wall time.
    pub uptime_s: u32,
}

#[derive(Default)]
pub struct FixAccumulator {
    rmc: Option<RmcData>,
    gga: Option<GgaData>,
}

impl FixAccumulator {
    pub const fn new() -> Self {
        Self {
            rmc: None,
            gga: None,
        }
    }

    /// Apply one parsed sentence; returns a merged fix when a valid RMC
    /// completes one. A void RMC (receiver lost the fix) clears the
    /// accumulator so a stale position can't leak into the next valid fix; a
    /// GGA only enriches the accumulator for the next merge (see the module
    /// docs for why it may not complete a fix of its own).
    pub fn apply(&mut self, sentence: &Sentence, uptime_s: u32) -> Option<Fix> {
        match sentence {
            Sentence::Rmc(rmc) if rmc.valid => self.rmc = Some(*rmc),
            Sentence::Rmc(_) => {
                self.rmc = None;
                self.gga = None;
                return None;
            }
            Sentence::Gga(gga) if gga.quality > 0 => {
                self.gga = Some(*gga);
                return None;
            }
            _ => return None,
        }
        self.merge(uptime_s)
    }

    fn merge(&self, uptime_s: u32) -> Option<Fix> {
        let rmc = self.rmc.as_ref()?;
        Some(Fix {
            lat_deg: rmc.lat_deg?,
            lon_deg: rmc.lon_deg?,
            speed_mps: rmc.speed_mps.unwrap_or(0.0),
            course_deg: rmc.course_deg,
            sats: self.gga.map(|g| g.sats).unwrap_or(0),
            alt_m: self.gga.and_then(|g| g.alt_m),
            time_of_day: rmc.time,
            date: rmc.date_dmy.and_then(|(day, month, year)| {
                ((1..=31).contains(&day) && (1..=12).contains(&month)).then_some(daylight::Date {
                    year,
                    month,
                    day,
                })
            }),
            uptime_s,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ublox_nmea::Parser;

    fn parse(text: &str) -> Sentence {
        let mut p = Parser::new();
        text.bytes().find_map(|b| p.feed(b)).expect("sentence")
    }

    const GGA: &str =
        "$GPGGA,073000.00,4000.9000,N,10516.2300,W,1,08,1.02,1624.0,M,-21.3,M,,*52\r\n";
    const RMC: &str = "$GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A*4B\r\n";

    /// Wrap a sentence body in the `$` framing and its XOR-8 checksum.
    fn sentence(body: &str) -> String {
        let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
        format!("${}*{:02X}\r\n", body, cksum)
    }

    fn void_rmc() -> String {
        sentence("GPRMC,073000.00,V,,,,,,,080726,,,N")
    }

    #[test]
    fn rmc_alone_is_a_fix_without_gga_extras() {
        let mut acc = FixAccumulator::new();
        let fix = acc.apply(&parse(RMC), 5).expect("fix");
        assert!((fix.lat_deg - 40.015).abs() < 1e-9);
        assert_eq!(fix.sats, 0);
        assert_eq!(fix.alt_m, None);
        assert_eq!(fix.uptime_s, 5);
        assert_eq!(
            fix.date,
            Some(daylight::Date {
                year: 2026,
                month: 7,
                day: 8
            })
        );
    }

    #[test]
    fn an_implausible_rmc_date_reads_as_absent() {
        // A receiver mid-cold-start can emit a valid position with a garbage
        // date field; the digits parse, so the gate here is the only thing
        // between month 0 and the date math.
        for date_field in ["320726", "081326", "000726", "080026"] {
            let body =
                format!("GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,{date_field},,,A");
            let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
            let text = format!("${}*{:02X}\r\n", body, cksum);
            let mut acc = FixAccumulator::new();
            let fix = acc.apply(&parse(&text), 5).expect("fix");
            assert_eq!(fix.date, None, "date field {date_field:?}");
        }
    }

    #[test]
    fn gga_enriches_the_next_merge() {
        let mut acc = FixAccumulator::new();
        acc.apply(&parse(GGA), 4);
        let fix = acc.apply(&parse(RMC), 5).expect("fix");
        assert_eq!(fix.sats, 8);
        assert!((fix.alt_m.unwrap() - 1624.0).abs() < 1e-3);
    }

    #[test]
    fn gga_before_any_rmc_is_not_a_fix() {
        let mut acc = FixAccumulator::new();
        assert_eq!(acc.apply(&parse(GGA), 1), None);
    }

    #[test]
    fn void_rmc_clears_accumulated_state() {
        let mut acc = FixAccumulator::new();
        acc.apply(&parse(GGA), 1);
        acc.apply(&parse(RMC), 2);
        assert_eq!(acc.apply(&parse(&void_rmc()), 3), None);
        // A fresh GGA alone can't resurrect the stale RMC position.
        assert_eq!(acc.apply(&parse(GGA), 4), None);
    }

    #[test]
    fn other_sentences_are_ignored() {
        let gsv = "$GPGSV,2,1,08,05,55,120,42,07,34,210,38,13,21,300,35,15,60,045,44*7D\r\n";
        let mut acc = FixAccumulator::new();
        acc.apply(&parse(GGA), 1);
        acc.apply(&parse(RMC), 2);
        assert!(acc.apply(&parse(gsv), 3).is_none());
        // ...and don't clear accumulated state: the next RMC still merges, and
        // still carries the GGA's extras. Probed with an RMC rather than a GGA
        // because a GGA no longer completes a fix at all.
        let fix = acc.apply(&parse(RMC), 4).expect("fix");
        assert_eq!(fix.sats, 8);
    }

    #[test]
    fn a_gga_never_restamps_the_last_position_as_current() {
        // The receiver goes quiet — a power-down window between throttled
        // fixes, or lost sentences — and comes back leading its epoch with a
        // GGA. Emitting there stamped the pre-gap position with the current
        // uptime, so nothing downstream could tell a 45-second-old position
        // from a live one.
        let mut acc = FixAccumulator::new();
        assert!(acc.apply(&parse(RMC), 10).is_some());
        assert_eq!(acc.apply(&parse(GGA), 55), None);
    }

    #[test]
    fn a_moving_runners_epochs_never_read_as_a_stop() {
        // A 1 Hz epoch leads with GGA and closes with RMC, so re-publishing on
        // the GGA handed the recorder the PREVIOUS epoch's position stamped a
        // second later: zero displacement over a full second, which the
        // min-move filter reads as a stop. A runner at ~5 m/s under a clear sky
        // alternated Recording/Paused every second because of it.
        use crate::record::{RecordState, Recorder};

        let mut acc = FixAccumulator::new();
        let mut rec = Recorder::new();
        rec.start(0);
        for t in 1..=6u32 {
            // ~0.0027 minutes of latitude per second is ~5 m.
            let lat_min = 0.9 + 0.0027 * f64::from(t);
            for text in [
                sentence(&format!(
                    "GPGGA,0730{t:02}.00,40{lat_min:07.4},N,10516.2300,W,1,08,1.02,1624.0,M,-21.3,M,,"
                )),
                sentence(&format!(
                    "GPRMC,0730{t:02}.00,A,40{lat_min:07.4},N,10516.2300,W,9.7,0.0,080726,,,A"
                )),
            ] {
                if let Some(fix) = acc.apply(&parse(&text), t) {
                    rec.on_fix(&fix);
                }
                assert_eq!(
                    rec.state(),
                    RecordState::Recording,
                    "a moving runner read as stopped at t={t}"
                );
            }
        }
        assert!(rec.snapshot().distance_m > 20.0);
    }
}
