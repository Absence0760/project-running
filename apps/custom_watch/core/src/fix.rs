//! GPS fix domain model.
//!
//! [`FixAccumulator`] reduces the NMEA sentence stream into [`Fix`] values:
//! RMC carries validity + position + speed + course, GGA carries quality +
//! satellite count + altitude, and a usable fix needs the union. The
//! accumulator keeps the latest of each and emits a merged `Fix` whenever a
//! sentence completes one.

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

    /// Apply one parsed sentence; returns a merged fix when the accumulated
    /// state amounts to one. A void RMC (receiver lost the fix) clears the
    /// accumulator so a stale position can't leak into the next valid fix.
    pub fn apply(&mut self, sentence: &Sentence, uptime_s: u32) -> Option<Fix> {
        match sentence {
            Sentence::Rmc(rmc) if rmc.valid => self.rmc = Some(*rmc),
            Sentence::Rmc(_) => {
                self.rmc = None;
                self.gga = None;
                return None;
            }
            Sentence::Gga(gga) if gga.quality > 0 => self.gga = Some(*gga),
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

    fn void_rmc() -> String {
        let body = "GPRMC,073000.00,V,,,,,,,080726,,,N";
        let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
        format!("${}*{:02X}\r\n", body, cksum)
    }

    #[test]
    fn rmc_alone_is_a_fix_without_gga_extras() {
        let mut acc = FixAccumulator::new();
        let fix = acc.apply(&parse(RMC), 5).expect("fix");
        assert!((fix.lat_deg - 40.015).abs() < 1e-9);
        assert_eq!(fix.sats, 0);
        assert_eq!(fix.alt_m, None);
        assert_eq!(fix.uptime_s, 5);
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
        acc.apply(&parse(RMC), 1);
        assert!(acc.apply(&parse(gsv), 2).is_none());
        // ...and don't clear accumulated state.
        assert!(acc.apply(&parse(GGA), 3).is_some());
    }
}
