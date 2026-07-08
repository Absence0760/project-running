//! Phone-link status frames.
//!
//! One newline-terminated JSON object per second, watch -> phone. This is
//! the transport-agnostic payload: in the simulator it travels over UARTE1
//! bridged to a TCP socket; on hardware it becomes the read/notify
//! characteristic of the step-6 BLE GATT service. Keeping the payload
//! identical across transports is the point — the phone-side decoder
//! (mobile `sim_watch_link.dart`) must not care which one it rode in on.
//!
//! Schema (`"v": 1`):
//! `{"v":1,"uptime_s":42,"fix":{"lat":..,"lon":..,"speed_mps":..,
//!   "course_deg":..|null,"sats":..,"alt_m":..|null,"tod_s":..|null,
//!   "age_s":..}}` — `"fix"` is `null` before the first fix.

use core::fmt::Write;

use crate::fix::Fix;

pub const PROTOCOL_VERSION: u8 = 1;

/// Generous over the ~160-char worst case; an overflowing write would
/// truncate the frame and the trailing-newline test below would catch it.
pub type Frame = heapless::String<192>;

pub fn status_frame(fix: Option<&Fix>, uptime_s: u32) -> Frame {
    let mut out = Frame::new();
    let _ = write!(
        out,
        "{{\"v\":{},\"uptime_s\":{},\"fix\":",
        PROTOCOL_VERSION, uptime_s
    );
    match fix {
        None => {
            let _ = write!(out, "null");
        }
        Some(fix) => {
            let _ = write!(
                out,
                "{{\"lat\":{:.6},\"lon\":{:.6},\"speed_mps\":{:.2},\"course_deg\":",
                fix.lat_deg, fix.lon_deg, fix.speed_mps
            );
            let _ = match fix.course_deg {
                Some(c) => write!(out, "{:.1}", c),
                None => write!(out, "null"),
            };
            let _ = write!(out, ",\"sats\":{},\"alt_m\":", fix.sats);
            let _ = match fix.alt_m {
                Some(a) => write!(out, "{:.1}", a),
                None => write!(out, "null"),
            };
            let _ = write!(out, ",\"tod_s\":");
            let _ = match fix.time_of_day {
                Some(t) => write!(out, "{}", t),
                None => write!(out, "null"),
            };
            let _ = write!(
                out,
                ",\"age_s\":{}}}",
                uptime_s.saturating_sub(fix.uptime_s)
            );
        }
    }
    let _ = writeln!(out, "}}");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fix() -> Fix {
        Fix {
            lat_deg: 40.01502,
            lon_deg: -105.2705,
            speed_mps: 3.0,
            course_deg: Some(90.0),
            sats: 8,
            alt_m: Some(1624.0),
            time_of_day: Some(27015),
            uptime_s: 41,
        }
    }

    #[test]
    fn frame_is_valid_json_with_expected_fields() {
        let frame = status_frame(Some(&fix()), 42);
        let v: serde_json::Value = serde_json::from_str(frame.trim_end()).expect("valid JSON");
        assert_eq!(v["v"], 1);
        assert_eq!(v["uptime_s"], 42);
        assert!((v["fix"]["lat"].as_f64().unwrap() - 40.01502).abs() < 1e-6);
        assert!((v["fix"]["lon"].as_f64().unwrap() - -105.2705).abs() < 1e-6);
        assert_eq!(v["fix"]["sats"], 8);
        assert_eq!(v["fix"]["age_s"], 1);
        assert_eq!(v["fix"]["tod_s"], 27015);
    }

    #[test]
    fn no_fix_is_null_not_absent() {
        let frame = status_frame(None, 7);
        let v: serde_json::Value = serde_json::from_str(frame.trim_end()).unwrap();
        assert!(v["fix"].is_null());
        assert_eq!(v["uptime_s"], 7);
    }

    #[test]
    fn optional_fields_render_as_null() {
        let mut f = fix();
        f.course_deg = None;
        f.alt_m = None;
        f.time_of_day = None;
        let frame = status_frame(Some(&f), 42);
        let v: serde_json::Value = serde_json::from_str(frame.trim_end()).unwrap();
        assert!(v["fix"]["course_deg"].is_null());
        assert!(v["fix"]["alt_m"].is_null());
        assert!(v["fix"]["tod_s"].is_null());
    }

    #[test]
    fn frame_is_newline_terminated_and_untruncated() {
        // Worst-case magnitudes must still fit the heapless capacity.
        let f = Fix {
            lat_deg: -89.999999,
            lon_deg: -179.999999,
            speed_mps: 99.99,
            course_deg: Some(359.9),
            sats: 255,
            alt_m: Some(-9999.9),
            time_of_day: Some(86399),
            uptime_s: 0,
        };
        let frame = status_frame(Some(&f), u32::MAX);
        assert!(frame.ends_with('\n'));
        serde_json::from_str::<serde_json::Value>(frame.trim_end()).expect("valid JSON");
    }
}
