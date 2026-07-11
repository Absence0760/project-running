//! Finisher-certificate shaping — the unit/locale-agnostic facts a finisher
//! certificate is built from: an eligibility gate + the time / distance /
//! placing formatters.
//!
//! Parity port of the SHAPING part of web
//! `apps/web/src/lib/runs/finisher_certificate.ts` (twin of
//! `finisher_certificate.dart`). Web builds an SVG string it rasterises to a
//! PNG download and mobile renders the same facts natively, so ONLY this
//! shaping is a true twin. The web SVG builder (`buildFinisherCertificateSvg`),
//! the PNG/rasterisation path, its `escapeHtml` dependency, and the SVG-only
//! date line (`fmtDate`) are web presentation and are deliberately NOT ported.
//! The watch renders its own certificate face from these strings.
//!
//! Pure logic, no peripherals, no allocator: the formatters build short strings
//! in a fixed-capacity [`CertString`].

use core::fmt::Write;

/// Upper bound for every formatted string this module returns. A multi-day
/// "h:mm:ss", a "12345.67 mi" distance, and a "2147483647th" ordinal all fit
/// well inside 24 bytes, leaving headroom without reaching for a heap.
pub const FMT_CAP: usize = 24;

pub type CertString = heapless::String<FMT_CAP>;

/// A finisher result is certificate-eligible iff they actually finished and an
/// organiser approved the result — the same gate web's leaderboard applies
/// before showing its Download-certificate button.
pub fn is_certificate_eligible(finisher_status: &str, organiser_approved: bool) -> bool {
    finisher_status == "finished" && organiser_approved
}

/// Sub-hour times render as `m:ss`, longer ones as `h:mm:ss`. Mirrors web's
/// `fmtTime`: round to the nearest second, then clamp negatives to zero.
pub fn format_certificate_time(seconds: f64) -> CertString {
    let rounded = libm::round(seconds);
    let s: u64 = if rounded > 0.0 { rounded as u64 } else { 0 };
    let h = s / 3600;
    let m = (s % 3600) / 60;
    let sec = s % 60;
    let mut out = CertString::new();
    if h > 0 {
        let _ = write!(out, "{h}:{m:02}:{sec:02}");
    } else {
        let _ = write!(out, "{m}:{sec:02}");
    }
    out
}

/// Distance to two decimals in the finisher's unit. Mirrors web's `fmtDistance`
/// (`.toFixed(2)` on `metres / 1609.344` for miles, `metres / 1000` for km).
pub fn format_certificate_distance(metres: f64, use_miles: bool) -> CertString {
    let mut out = CertString::new();
    if use_miles {
        let _ = write!(out, "{:.2} mi", metres / 1609.344);
    } else {
        let _ = write!(out, "{:.2} km", metres / 1000.0);
    }
    out
}

/// English ordinal — "1st" / "2nd" / "3rd" / "11th" / "21st". Mirrors web's
/// `ordinal`; the placing line is the only ordinal use and web keeps it English
/// on the certificate itself.
pub fn ordinal_place(n: i32) -> CertString {
    const SUFFIXES: [&str; 4] = ["th", "st", "nd", "rd"];
    let v = n % 100;
    // JS `%` keeps the dividend's sign, so `(v - 20) % 10` is negative for
    // v < 20 and indexes out of range -> the web's `?? s[v] ?? s[0]`
    // fallthrough picks "th". Rust `%` matches that sign behaviour.
    let idx = (v - 20) % 10;
    let suffix = if (0..SUFFIXES.len() as i32).contains(&idx) {
        SUFFIXES[idx as usize]
    } else if (0..SUFFIXES.len() as i32).contains(&v) {
        SUFFIXES[v as usize]
    } else {
        SUFFIXES[0]
    };
    let mut out = CertString::new();
    let _ = write!(out, "{n}{suffix}");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eligible_only_when_finished_and_organiser_approved() {
        assert!(is_certificate_eligible("finished", true));
        assert!(!is_certificate_eligible("finished", false));
        assert!(!is_certificate_eligible("dnf", true));
        assert!(!is_certificate_eligible("dns", true));
    }

    #[test]
    fn sub_hour_as_m_ss_with_hour_as_h_mm_ss() {
        assert_eq!(format_certificate_time(22.0 * 60.0 + 9.0).as_str(), "22:09");
        assert_eq!(
            format_certificate_time(3.0 * 3600.0 + 25.0 * 60.0 + 8.0).as_str(),
            "3:25:08"
        );
    }

    #[test]
    fn clamps_negatives_to_zero() {
        assert_eq!(format_certificate_time(-5.0).as_str(), "0:00");
    }

    #[test]
    fn km_and_mi_formatting_matches_web() {
        assert_eq!(
            format_certificate_distance(10000.0, false).as_str(),
            "10.00 km"
        );
        assert_eq!(
            format_certificate_distance(10000.0, true).as_str(),
            "6.21 mi"
        );
    }

    #[test]
    fn ordinal_place_matches_web_across_the_tricky_cases() {
        assert_eq!(ordinal_place(1).as_str(), "1st");
        assert_eq!(ordinal_place(2).as_str(), "2nd");
        assert_eq!(ordinal_place(3).as_str(), "3rd");
        assert_eq!(ordinal_place(4).as_str(), "4th");
        assert_eq!(ordinal_place(11).as_str(), "11th");
        assert_eq!(ordinal_place(12).as_str(), "12th");
        assert_eq!(ordinal_place(13).as_str(), "13th");
        assert_eq!(ordinal_place(21).as_str(), "21st");
        assert_eq!(ordinal_place(22).as_str(), "22nd");
        assert_eq!(ordinal_place(23).as_str(), "23rd");
        assert_eq!(ordinal_place(111).as_str(), "111th");
    }
}
