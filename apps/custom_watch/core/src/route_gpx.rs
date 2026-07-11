//! Course-waypoint GPX export — the route line as a `<trk>` plus one `<wpt>`
//! per course marker (aid station, cutoff, crew access, hazard, …). Imported by
//! every Garmin/Coros/Suunto so the runner sees "Aid 2 in 1.3 km" on the wrist
//! mid-race; on this device it is the "export the course" path.
//!
//! Parity port of web `routes/route_gpx.ts` (twin of
//! `apps/mobile_android/lib/route_gpx.dart`) — keep the element order, the
//! kind→`<sym>` mapping, the `<desc>` construction, the escaping, and the ten
//! twin tests in lockstep. Pure + deterministic (no clock): the `<metadata>`
//! carries only a `<name>`, so the output is byte-stable. GPX 1.1 requires
//! `<wpt>` elements BEFORE `<trk>`, so waypoints are emitted first.
//!
//! Reuses [`crate::route_markers::parse_cutoff`] for cutoff validation rather
//! than re-porting it — the watch feeds the marker's `cutoff_clock` /
//! `cutoff_elapsed_s` straight in. The web `RouteGpxMarker.meta` bag becomes
//! explicit typed fields here (the watch has no untyped jsonb). The Dart-only
//! `routeGpxFromRoute` is row-mapping glue over a `Route` row type this crate
//! does not carry, so it has no watch port.
//!
//! `no_std`, no allocator: the document is built into a caller-sized
//! `heapless::String<N>` and the builder returns [`GpxOverflow`] when the buffer
//! is too small — never a panic, never a silent truncation. Budget roughly
//! ~440 bytes of scaffold, ~120 bytes per waypoint, and ~55 bytes per
//! trackpoint when sizing `N`.

use core::fmt::Write;

use heapless::String;

use crate::route_markers::parse_cutoff;

/// One course marker to emit as a `<wpt>`. The web `meta` bag is unpacked into
/// explicit fields; `services` is the (possibly empty) aid-service list.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RouteGpxMarker<'a> {
    pub label: &'a str,
    pub lat: f64,
    pub lng: f64,
    /// `RouteMarkerKind` stored key (e.g. `"aid_station"`).
    pub kind: &'a str,
    /// Wall-clock "HH:MM" cutoff, when set.
    pub cutoff_clock: Option<&'a str>,
    /// Elapsed-seconds cutoff, when set.
    pub cutoff_elapsed_s: Option<f64>,
    /// Aid-service names (`"water"`, `"food"`, …), in display order.
    pub services: &'a [&'a str],
}

/// One `[lng, lat]` coordinate of the route line (same order as web `toGpx`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackPoint {
    pub lng: f64,
    pub lat: f64,
    /// Elevation in metres; `None` falls back to `0` in the emitted `<ele>`.
    pub ele: Option<f64>,
}

/// The output buffer was too small to hold the whole document.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GpxOverflow;

/// Garmin-recognised `<sym>` name per marker kind; `None` → no `<sym>` element.
/// Mirrors web `SYM_BY_KIND` exactly.
fn sym_for_kind(kind: &str) -> Option<&'static str> {
    Some(match kind {
        "aid_station" => "Water Source",
        "cutoff" => "Danger Area",
        "crew_access" => "Parking Area",
        "hazard" => "Danger Area",
        "note" => "Information",
        "climb" => "Summit",
        _ => return None,
    })
}

/// Append `raw` to `s` with the five XML entity escapes web `escapeXml` uses.
fn write_escaped<const N: usize>(s: &mut String<N>, raw: &str) -> Result<(), GpxOverflow> {
    for ch in raw.chars() {
        match ch {
            '&' => write_str(s, "&amp;")?,
            '<' => write_str(s, "&lt;")?,
            '>' => write_str(s, "&gt;")?,
            '"' => write_str(s, "&quot;")?,
            '\'' => write_str(s, "&apos;")?,
            _ => s.push(ch).map_err(|_| GpxOverflow)?,
        }
    }
    Ok(())
}

fn write_str<const N: usize>(s: &mut String<N>, raw: &str) -> Result<(), GpxOverflow> {
    s.push_str(raw).map_err(|_| GpxOverflow)
}

fn write_num<const N: usize>(s: &mut String<N>, n: f64) -> Result<(), GpxOverflow> {
    write!(s, "{n}").map_err(|_| GpxOverflow)
}

/// True when the marker carries anything the `<desc>` would render — a valid
/// cutoff (clock or elapsed) or a non-empty service list.
fn has_desc(m: &RouteGpxMarker) -> bool {
    let cutoff = parse_cutoff(m.cutoff_clock, m.cutoff_elapsed_s);
    let cutoff_present = cutoff
        .map(|c| c.clock.is_some() || c.elapsed_s.is_some())
        .unwrap_or(false);
    cutoff_present || !m.services.is_empty()
}

/// Write the `<desc>…</desc>` body (locale-agnostic canonical English) for a
/// marker, mirroring web `buildDesc`: `Cutoff HH:MM | Cutoff HhMMm elapsed |
/// Services: a, b`. Callers must only invoke this when [`has_desc`] is true.
fn write_desc<const N: usize>(s: &mut String<N>, m: &RouteGpxMarker) -> Result<(), GpxOverflow> {
    let mut first = true;
    let mut sep = |s: &mut String<N>| -> Result<(), GpxOverflow> {
        if first {
            first = false;
            Ok(())
        } else {
            write_str(s, " | ")
        }
    };

    if let Some(cutoff) = parse_cutoff(m.cutoff_clock, m.cutoff_elapsed_s) {
        if let Some(clock) = cutoff.clock {
            sep(s)?;
            write_str(s, "Cutoff ")?;
            write_escaped(s, clock)?;
        }
        if let Some(elapsed) = cutoff.elapsed_s {
            sep(s)?;
            let h = elapsed / 3600;
            let mm = (elapsed % 3600) / 60;
            write_str(s, "Cutoff ")?;
            write_num(s, h as f64)?;
            write_str(s, "h")?;
            if mm < 10 {
                write_str(s, "0")?;
            }
            write_num(s, mm as f64)?;
            write_str(s, "m elapsed")?;
        }
    }

    if !m.services.is_empty() {
        sep(s)?;
        write_str(s, "Services: ")?;
        for (i, svc) in m.services.iter().enumerate() {
            if i > 0 {
                write_str(s, ", ")?;
            }
            write_escaped(s, svc)?;
        }
    }
    Ok(())
}

fn write_waypoint<const N: usize>(
    s: &mut String<N>,
    m: &RouteGpxMarker,
) -> Result<(), GpxOverflow> {
    write_str(s, "  <wpt lat=\"")?;
    write_num(s, m.lat)?;
    write_str(s, "\" lon=\"")?;
    write_num(s, m.lng)?;
    write_str(s, "\"><name>")?;
    write_escaped(s, m.label)?;
    write_str(s, "</name><type>")?;
    write_escaped(s, m.kind)?;
    write_str(s, "</type>")?;
    if let Some(sym) = sym_for_kind(m.kind) {
        write_str(s, "<sym>")?;
        write_str(s, sym)?;
        write_str(s, "</sym>")?;
    }
    if has_desc(m) {
        write_str(s, "<desc>")?;
        write_desc(s, m)?;
        write_str(s, "</desc>")?;
    }
    write_str(s, "</wpt>")
}

/// Generate a GPX 1.1 document for a route line plus its course markers into a
/// caller-sized buffer. `coordinates` are the route line (`[lng, lat]` order);
/// `markers` are emitted as `<wpt>` before the `<trk>`.
pub fn to_route_gpx_with_markers<const N: usize>(
    name: &str,
    coordinates: &[TrackPoint],
    markers: &[RouteGpxMarker],
) -> Result<String<N>, GpxOverflow> {
    let mut s: String<N> = String::new();
    write_str(
        &mut s,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
<gpx version=\"1.1\" creator=\"Threkir\"\n  \
xmlns=\"http://www.topografix.com/GPX/1/1\"\n  \
xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n  \
xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n  \
<metadata>\n    <name>",
    )?;
    write_escaped(&mut s, name)?;
    write_str(&mut s, "</name>\n  </metadata>\n")?;

    for m in markers {
        write_waypoint(&mut s, m)?;
        write_str(&mut s, "\n")?;
    }

    write_str(&mut s, "  <trk>\n    <name>")?;
    write_escaped(&mut s, name)?;
    write_str(&mut s, "</name>\n    <trkseg>\n")?;
    for p in coordinates {
        write_str(&mut s, "      <trkpt lat=\"")?;
        write_num(&mut s, p.lat)?;
        write_str(&mut s, "\" lon=\"")?;
        write_num(&mut s, p.lng)?;
        write_str(&mut s, "\"><ele>")?;
        write_num(&mut s, p.ele.unwrap_or(0.0))?;
        write_str(&mut s, "</ele></trkpt>\n")?;
    }
    write_str(&mut s, "    </trkseg>\n  </trk>\n</gpx>")?;
    Ok(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CAP: usize = 4096;

    fn coords_3() -> [TrackPoint; 3] {
        [
            TrackPoint {
                lng: 8.54,
                lat: 47.37,
                ele: Some(400.0),
            },
            TrackPoint {
                lng: 8.541,
                lat: 47.371,
                ele: Some(410.0),
            },
            TrackPoint {
                lng: 8.542,
                lat: 47.372,
                ele: Some(420.0),
            },
        ]
    }

    fn marker<'a>(
        label: &'a str,
        lat: f64,
        lng: f64,
        kind: &'a str,
        cutoff_clock: Option<&'a str>,
        cutoff_elapsed_s: Option<f64>,
        services: &'a [&'a str],
    ) -> RouteGpxMarker<'a> {
        RouteGpxMarker {
            label,
            lat,
            lng,
            kind,
            cutoff_clock,
            cutoff_elapsed_s,
            services,
        }
    }

    fn aid(kind: &str) -> RouteGpxMarker<'_> {
        marker("Aid 1", 47.371, 8.541, kind, None, None, &[])
    }

    fn gen(name: &str, coords: &[TrackPoint], markers: &[RouteGpxMarker]) -> String<CAP> {
        to_route_gpx_with_markers::<CAP>(name, coords, markers).unwrap()
    }

    fn count(hay: &str, needle: &str) -> usize {
        hay.matches(needle).count()
    }

    #[test]
    fn has_gpx_1_1_namespace_and_creator() {
        let xml = gen("Loop", &coords_3(), &[]);
        assert!(xml.contains("<gpx version=\"1.1\" creator=\"Threkir\""));
        assert!(xml.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""));
    }

    #[test]
    fn emits_one_wpt_per_marker_with_lat_lon_name_type() {
        let markers = [
            marker("Aid 2", 47.37, 8.54, "aid_station", None, None, &[]),
            marker("Cut 1", 47.372, 8.542, "cutoff", None, None, &[]),
        ];
        let xml = gen("Loop", &coords_3(), &markers);
        assert_eq!(count(&xml, "<wpt "), 2);
        assert!(xml.contains(
            "<wpt lat=\"47.37\" lon=\"8.54\"><name>Aid 2</name><type>aid_station</type>"
        ));
        assert!(
            xml.contains("<wpt lat=\"47.372\" lon=\"8.542\"><name>Cut 1</name><type>cutoff</type>")
        );
    }

    #[test]
    fn cutoff_clock_elapsed_and_services_land_in_desc() {
        let markers = [marker(
            "Aid 1",
            47.371,
            8.541,
            "aid_station",
            Some("14:30"),
            Some(16200.0),
            &["water", "food", "medical"],
        )];
        let xml = gen("Loop", &coords_3(), &markers);
        assert!(xml.contains(
            "<desc>Cutoff 14:30 | Cutoff 4h30m elapsed | Services: water, food, medical</desc>"
        ));
    }

    #[test]
    fn elapsed_minutes_are_zero_padded() {
        let markers = [marker(
            "Aid 1",
            47.371,
            8.541,
            "cutoff",
            None,
            Some(3660.0),
            &[],
        )];
        let xml = gen("Loop", &coords_3(), &markers);
        assert!(xml.contains("<desc>Cutoff 1h01m elapsed</desc>"));
    }

    #[test]
    fn no_desc_when_no_cutoff_and_no_services() {
        let xml = gen("Loop", &coords_3(), &[aid("note")]);
        assert!(!xml.contains("<desc>"));
    }

    #[test]
    fn maps_kind_to_a_garmin_sym_omits_for_custom_unknown() {
        let cases: [(&str, Option<&str>); 8] = [
            ("aid_station", Some("Water Source")),
            ("cutoff", Some("Danger Area")),
            ("crew_access", Some("Parking Area")),
            ("hazard", Some("Danger Area")),
            ("note", Some("Information")),
            ("climb", Some("Summit")),
            ("custom", None),
            ("gas_station", None),
        ];
        for (kind, sym) in cases {
            let xml = gen("Loop", &coords_3(), &[aid(kind)]);
            match sym {
                None => assert!(!xml.contains("<sym>"), "no <sym> for kind {kind}"),
                Some(s) => {
                    let mut needle: String<32> = String::new();
                    write!(needle, "<sym>{s}</sym>").unwrap();
                    assert!(xml.contains(needle.as_str()), "kind {kind} -> {s}");
                }
            }
        }
    }

    #[test]
    fn escapes_xml_metacharacters_in_name_and_desc() {
        let markers = [marker(
            "Tom & \"Jerry\" <aid>",
            47.371,
            8.541,
            "aid_station",
            None,
            None,
            &["water & ice"],
        )];
        let xml = gen("Loop", &coords_3(), &markers);
        assert!(!xml.contains("<aid>"));
        assert!(xml.contains("<name>Tom &amp; &quot;Jerry&quot; &lt;aid&gt;</name>"));
        assert!(xml.contains("<desc>Services: water &amp; ice</desc>"));
    }

    #[test]
    fn empty_marker_list_still_emits_the_line_and_zero_wpt() {
        let xml = gen("Loop", &coords_3(), &[]);
        assert_eq!(count(&xml, "<wpt "), 0);
        assert_eq!(count(&xml, "<trkpt "), 3);
        assert!(xml.contains("<trkpt lat=\"47.37\" lon=\"8.54\"><ele>400</ele>"));
    }

    #[test]
    fn missing_elevation_falls_back_to_zero() {
        let coords = [TrackPoint {
            lng: 8.54,
            lat: 47.37,
            ele: None,
        }];
        let xml = gen("Loop", &coords, &[]);
        assert!(xml.contains("<ele>0</ele>"));
    }

    #[test]
    fn wpt_elements_precede_the_trk() {
        let xml = gen("Loop", &coords_3(), &[aid("aid_station")]);
        let wpt = xml.find("<wpt ");
        let trk = xml.find("<trk>");
        assert!(wpt.is_some() && trk.is_some());
        assert!(wpt.unwrap() < trk.unwrap());
    }

    #[test]
    fn overflows_when_the_buffer_is_too_small() {
        let too_small = to_route_gpx_with_markers::<64>("Loop", &coords_3(), &[]);
        assert_eq!(too_small, Err(GpxOverflow));
    }
}
