//! Course markers on a route — aid stations, cutoffs, crew/parking access,
//! hazards, notes, climbs.
//!
//! Pure, locale- and unit-agnostic logic shared by the map layer and the
//! course-schedule list: the kind catalogue (one source of truth for pin
//! colour + which detail fields a kind carries), schedule ordering, the
//! aid-service vocabulary, and cutoff parse/validation.
//!
//! Parity port of web `routes/route_markers.ts` (twin of
//! `apps/mobile_android/lib/route_markers.dart`) — keep the kind set, colours,
//! service vocabulary, ordering, cutoff rules, edge cases, and test count in
//! lockstep. The per-kind i18n label *key* is presentation, not part of the
//! parity lockstep; it is carried as a stable `&'static str` so callers can
//! resolve it, never as English text. Distance formatting and the per-platform
//! icon glyph stay at the render layer — this catalogue carries only the
//! shared hex colour + label key so a pin looks identical across platforms.
//!
//! This is the canonical home for [`parse_cutoff`] + [`valid_clock`], reused by
//! [`crate::roadbook`] and [`crate::route_gpx`] rather than re-inlined. Pure
//! logic, no peripherals, no allocator.

use core::cmp::Ordering;

use heapless::Vec;

/// Kinds a course marker can be. Unknown stored values normalise to
/// [`Custom`](RouteMarkerKind::Custom).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RouteMarkerKind {
    AidStation,
    Cutoff,
    CrewAccess,
    Hazard,
    Note,
    Climb,
    Custom,
}

impl RouteMarkerKind {
    /// Stored string key (the DB `kind` value + the web union member).
    pub const fn as_key(self) -> &'static str {
        match self {
            RouteMarkerKind::AidStation => "aid_station",
            RouteMarkerKind::Cutoff => "cutoff",
            RouteMarkerKind::CrewAccess => "crew_access",
            RouteMarkerKind::Hazard => "hazard",
            RouteMarkerKind::Note => "note",
            RouteMarkerKind::Climb => "climb",
            RouteMarkerKind::Custom => "custom",
        }
    }

    /// Parse a stored string key; `None` for an unrecognised value.
    pub fn from_key(key: &str) -> Option<Self> {
        Some(match key {
            "aid_station" => RouteMarkerKind::AidStation,
            "cutoff" => RouteMarkerKind::Cutoff,
            "crew_access" => RouteMarkerKind::CrewAccess,
            "hazard" => RouteMarkerKind::Hazard,
            "note" => RouteMarkerKind::Note,
            "climb" => RouteMarkerKind::Climb,
            "custom" => RouteMarkerKind::Custom,
            _ => return None,
        })
    }
}

/// Which optional detail fields a kind's `meta` bag carries, plus the shared
/// pin colour + i18n label key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RouteMarkerKindSpec {
    pub kind: RouteMarkerKind,
    /// i18n key under `routeMarker.kind.*` (presentation, resolved by callers).
    pub label_key: &'static str,
    /// Shared pin colour (hex) so the map looks identical across platforms.
    pub color: &'static str,
    /// Aid-services checklist (water / food / …) applies.
    pub has_services: bool,
    /// A cutoff time (clock and/or elapsed) applies.
    pub has_cutoff: bool,
}

const CUSTOM_SPEC: RouteMarkerKindSpec = RouteMarkerKindSpec {
    kind: RouteMarkerKind::Custom,
    label_key: "routeMarker.kind.custom",
    color: "#6b7280",
    has_services: false,
    has_cutoff: false,
};

pub const ROUTE_MARKER_KINDS: [RouteMarkerKindSpec; 7] = [
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::AidStation,
        label_key: "routeMarker.kind.aid_station",
        color: "#0e9f6e",
        has_services: true,
        has_cutoff: false,
    },
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::Cutoff,
        label_key: "routeMarker.kind.cutoff",
        color: "#e02424",
        has_services: false,
        has_cutoff: true,
    },
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::CrewAccess,
        label_key: "routeMarker.kind.crew_access",
        color: "#3f83f8",
        has_services: false,
        has_cutoff: false,
    },
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::Hazard,
        label_key: "routeMarker.kind.hazard",
        color: "#ff5a1f",
        has_services: false,
        has_cutoff: false,
    },
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::Note,
        label_key: "routeMarker.kind.note",
        color: "#9061f9",
        has_services: false,
        has_cutoff: false,
    },
    RouteMarkerKindSpec {
        kind: RouteMarkerKind::Climb,
        label_key: "routeMarker.kind.climb",
        color: "#c27803",
        has_services: false,
        has_cutoff: false,
    },
    CUSTOM_SPEC,
];

/// Spec for a stored kind string, falling back to `custom` for an unknown
/// value.
pub fn kind_spec(kind: &str) -> RouteMarkerKindSpec {
    let resolved = RouteMarkerKind::from_key(kind).unwrap_or(RouteMarkerKind::Custom);
    ROUTE_MARKER_KINDS
        .iter()
        .copied()
        .find(|s| s.kind == resolved)
        .unwrap_or(CUSTOM_SPEC)
}

/// Aid-station service vocabulary (stored in `meta.services`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AidService {
    Water,
    Food,
    Medical,
    Toilets,
    DropBag,
}

impl AidService {
    pub const fn as_key(self) -> &'static str {
        match self {
            AidService::Water => "water",
            AidService::Food => "food",
            AidService::Medical => "medical",
            AidService::Toilets => "toilets",
            AidService::DropBag => "drop_bag",
        }
    }
}

pub const AID_SERVICES: [AidService; 5] = [
    AidService::Water,
    AidService::Food,
    AidService::Medical,
    AidService::Toilets,
    AidService::DropBag,
];

/// Maximum markers folded into one ordered schedule; the excess is dropped
/// rather than growing (matching `roadbook`'s fixed-cap discipline).
pub const MAX_MARKERS: usize = 64;

/// Minimal shape the ordering helper needs.
pub trait MarkerLike {
    /// Distance along the route from the start, metres. `None` = no geom yet.
    fn position_m(&self) -> Option<f64>;
    /// Insertion timestamp, an ISO-8601 string that sorts chronologically.
    fn created_at(&self) -> &str;
}

/// Course-schedule comparison: by distance along the route (markers with no
/// `position_m` sort last), then by insertion time so two markers at the same
/// point keep a stable order.
pub fn compare_markers<T: MarkerLike>(a: &T, b: &T) -> Ordering {
    match (a.position_m(), b.position_m()) {
        (None, None) => a.created_at().cmp(b.created_at()),
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(pa), Some(pb)) => match pa.partial_cmp(&pb) {
            Some(Ordering::Equal) | None => a.created_at().cmp(b.created_at()),
            Some(order) => order,
        },
    }
}

/// Course-schedule order as references into `markers`, non-mutating (mirrors
/// the web `sortMarkers` returning a new array). Markers past [`MAX_MARKERS`]
/// are dropped.
pub fn sort_markers<T: MarkerLike>(markers: &[T]) -> Vec<&T, MAX_MARKERS> {
    let mut out: Vec<&T, MAX_MARKERS> = Vec::new();
    for m in markers {
        if out.push(m).is_err() {
            break;
        }
    }
    out.sort_unstable_by(|a, b| compare_markers(*a, *b));
    out
}

/// A validated cutoff. `clock` is the wall-clock "HH:MM" (24h) when set;
/// `elapsed_s` is elapsed seconds from the start, floored, when set.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct CutoffParts<'a> {
    pub clock: Option<&'a str>,
    pub elapsed_s: Option<u32>,
}

/// Validate + normalise a marker's cutoff inputs. Returns `None` when neither a
/// valid clock nor a valid non-negative elapsed is present, so callers render a
/// cutoff chip only for a real cutoff. Both platforms must agree on what counts
/// as valid so a cutoff shows identically.
pub fn parse_cutoff(clock: Option<&str>, elapsed: Option<f64>) -> Option<CutoffParts<'_>> {
    let out_clock = clock.filter(|c| valid_clock(c));
    let out_elapsed = elapsed
        .filter(|e| e.is_finite() && *e >= 0.0)
        .map(|e| libm::floor(e) as u32);
    if out_clock.is_some() || out_elapsed.is_some() {
        Some(CutoffParts {
            clock: out_clock,
            elapsed_s: out_elapsed,
        })
    } else {
        None
    }
}

/// True when `s` is a "HH:MM" 24-hour clock — the web `CLOCK_RE` regex.
pub fn valid_clock(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 5 || b[2] != b':' {
        return false;
    }
    if !(b[0].is_ascii_digit()
        && b[1].is_ascii_digit()
        && b[3].is_ascii_digit()
        && b[4].is_ascii_digit())
    {
        return false;
    }
    let hh = (b[0] - b'0') * 10 + (b[1] - b'0');
    let mm = (b[3] - b'0') * 10 + (b[4] - b'0');
    hh <= 23 && mm <= 59
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    struct Marker {
        id: &'static str,
        position_m: Option<f64>,
        created_at: &'static str,
    }

    impl MarkerLike for Marker {
        fn position_m(&self) -> Option<f64> {
            self.position_m
        }
        fn created_at(&self) -> &str {
            self.created_at
        }
    }

    fn is_hex_color(s: &str) -> bool {
        let b = s.as_bytes();
        b.len() == 7
            && b[0] == b'#'
            && b[1..]
                .iter()
                .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
    }

    #[test]
    fn every_kind_has_a_unique_key_label_key_and_hex_colour() {
        let keys: HashSet<RouteMarkerKind> = ROUTE_MARKER_KINDS.iter().map(|k| k.kind).collect();
        assert_eq!(keys.len(), ROUTE_MARKER_KINDS.len());
        for k in ROUTE_MARKER_KINDS {
            assert!(is_hex_color(k.color));
            assert!(k.label_key.starts_with("routeMarker.kind."));
        }
    }

    #[test]
    fn only_aid_station_carries_services_only_cutoff_carries_a_cutoff() {
        assert!(kind_spec("aid_station").has_services);
        assert!(!kind_spec("aid_station").has_cutoff);
        assert!(kind_spec("cutoff").has_cutoff);
        assert!(!kind_spec("cutoff").has_services);
        assert_eq!(
            ROUTE_MARKER_KINDS.iter().filter(|k| k.has_services).count(),
            1
        );
        assert_eq!(
            ROUTE_MARKER_KINDS.iter().filter(|k| k.has_cutoff).count(),
            1
        );
    }

    #[test]
    fn kind_spec_falls_back_to_custom_for_an_unknown_kind() {
        assert_eq!(kind_spec("gas_station").kind, RouteMarkerKind::Custom);
        assert_eq!(kind_spec("aid_station").kind, RouteMarkerKind::AidStation);
    }

    #[test]
    fn aid_services_vocabulary_is_stable() {
        let keys: [&str; 5] = AID_SERVICES.map(|s| s.as_key());
        assert_eq!(keys, ["water", "food", "medical", "toilets", "drop_bag"]);
    }

    #[test]
    fn sort_markers_orders_by_position_nulls_last_stable_by_created_at() {
        let markers = [
            Marker {
                id: "c",
                position_m: None,
                created_at: "2026-01-01T00:00:02Z",
            },
            Marker {
                id: "a",
                position_m: Some(1500.0),
                created_at: "2026-01-01T00:00:00Z",
            },
            Marker {
                id: "d",
                position_m: None,
                created_at: "2026-01-01T00:00:01Z",
            },
            Marker {
                id: "b",
                position_m: Some(300.0),
                created_at: "2026-01-01T00:00:09Z",
            },
        ];
        let ordered: std::vec::Vec<&str> = sort_markers(&markers).iter().map(|m| m.id).collect();
        assert_eq!(ordered, ["b", "a", "d", "c"]);
    }

    #[test]
    fn sort_markers_breaks_position_ties_by_created_at_and_does_not_mutate_input() {
        let markers = [
            Marker {
                id: "y",
                position_m: Some(500.0),
                created_at: "2026-01-01T00:00:05Z",
            },
            Marker {
                id: "x",
                position_m: Some(500.0),
                created_at: "2026-01-01T00:00:01Z",
            },
        ];
        let ordered: std::vec::Vec<&str> = sort_markers(&markers).iter().map(|m| m.id).collect();
        assert_eq!(ordered, ["x", "y"]);
        assert_eq!(markers[0].id, "y");
    }

    #[test]
    fn parse_cutoff_accepts_a_valid_24h_clock() {
        assert_eq!(
            parse_cutoff(Some("14:30"), None),
            Some(CutoffParts {
                clock: Some("14:30"),
                elapsed_s: None
            })
        );
        assert_eq!(
            parse_cutoff(Some("00:00"), None),
            Some(CutoffParts {
                clock: Some("00:00"),
                elapsed_s: None
            })
        );
        assert_eq!(
            parse_cutoff(Some("23:59"), None),
            Some(CutoffParts {
                clock: Some("23:59"),
                elapsed_s: None
            })
        );
    }

    #[test]
    fn parse_cutoff_rejects_an_invalid_clock() {
        assert_eq!(parse_cutoff(Some("24:00"), None), None);
        assert_eq!(parse_cutoff(Some("9:5"), None), None);
        assert_eq!(parse_cutoff(Some("noon"), None), None);
    }

    #[test]
    fn parse_cutoff_accepts_a_non_negative_elapsed_and_floors_it() {
        assert_eq!(
            parse_cutoff(None, Some(3600.0)),
            Some(CutoffParts {
                clock: None,
                elapsed_s: Some(3600)
            })
        );
        assert_eq!(
            parse_cutoff(None, Some(90.7)),
            Some(CutoffParts {
                clock: None,
                elapsed_s: Some(90)
            })
        );
        assert_eq!(parse_cutoff(None, Some(-5.0)), None);
    }

    #[test]
    fn parse_cutoff_merges_clock_and_elapsed_and_returns_none_for_neither() {
        assert_eq!(
            parse_cutoff(Some("06:00"), Some(1800.0)),
            Some(CutoffParts {
                clock: Some("06:00"),
                elapsed_s: Some(1800)
            })
        );
        assert_eq!(parse_cutoff(None, None), None);
        assert_eq!(parse_cutoff(Some("bogus"), None), None);
    }
}
