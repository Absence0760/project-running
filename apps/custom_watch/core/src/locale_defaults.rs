//! Locale-derived defaults for first-run settings — parity port of web
//! `format/locale_defaults.ts` (twin of mobile `locale_defaults.dart`).
//!
//! Pure functions over a BCP-47 (`"en-US"`, `"zh-Hant-TW"`) or POSIX
//! (`"en_US"`, `"en_US.UTF-8"`) locale string, so the watch can seed a
//! sensible units + week-start default from the phone-supplied locale
//! without a browser or an allocator.
//!
//! Web additionally consults CLDR week data via `Intl.Locale.getWeekInfo()`
//! when the runtime exposes it; a `no_std` core has no `Intl`, so — like the
//! Dart twin — only the shared region tables are ported. Those tables are the
//! lockstep contract, and they agree with `Intl` for every pinned test case.

/// Distance-unit default. Web's `'km' | 'mi'` union.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum DistanceUnit {
    Km,
    Mi,
}

/// Week-start default. Web's `'monday' | 'sunday'` union (Sunday = day 0,
/// Monday = day 1 in the app's day numbering).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WeekStart {
    Sunday,
    Monday,
}

/// Region subtag: 2 ASCII letters or 3 ASCII digits, hence at most 3 bytes.
pub type Region = heapless::String<3>;

/// Extract the uppercase region subtag from a locale string, or an empty
/// string when none is present — mirroring web's `regionOfLocale` (which
/// returns `''` for a region-less or unparseable input).
pub fn region_of_locale(locale: &str) -> Region {
    let cleaned = locale.split(['.', '@']).next().unwrap_or("");
    for part in cleaned.split(['-', '_']).skip(1) {
        if is_region_subtag(part) {
            let mut out = Region::new();
            for b in part.bytes() {
                let _ = out.push(b.to_ascii_uppercase() as char);
            }
            return out;
        }
    }
    Region::new()
}

fn is_region_subtag(part: &str) -> bool {
    let bytes = part.as_bytes();
    (bytes.len() == 2 && bytes.iter().all(u8::is_ascii_alphabetic))
        || (bytes.len() == 3 && bytes.iter().all(u8::is_ascii_digit))
}

/// Regions that use imperial distance for everyday + running use: United
/// States, United Kingdom, Liberia, Myanmar.
const IMPERIAL_REGIONS: [&str; 4] = ["US", "GB", "LR", "MM"];

pub fn default_unit_for_locale(locale: &str) -> DistanceUnit {
    if IMPERIAL_REGIONS.contains(&region_of_locale(locale).as_str()) {
        DistanceUnit::Mi
    } else {
        DistanceUnit::Km
    }
}

/// Regions whose CLDR week data starts the week on SUNDAY. Derived from Intl
/// week data (`firstDay === 7`) over every assigned ISO 3166-1 alpha-2 region,
/// so the table cannot disagree with the `Intl` lookup web consults first.
///
/// Kept identical to web's `SUNDAY_FIRST_REGIONS` and the Dart
/// `_sundayFirstRegions`. The hand-written 16-region version all three once
/// shared disagreed with CLDR for 19 of them — it wrongly listed AR (Argentina
/// is Monday-first) and omitted PT, TH, ID, SG, SA, DO, GT, HN, SV, NI, PA, PY,
/// KE, ET, PK, BD, YE, NP and LA. Web and mobile were corrected on 2026-08-11;
/// this port was taken a month earlier and kept the old list, which is the
/// whole reason to write the table's provenance down rather than its contents.
///
/// A region-less locale stays on the neutral ISO/Monday default (mirroring the
/// km default above) rather than letting a maximization step promote `en` to
/// `en-US` to Sunday. Saturday-first regions (`firstDay === 6`: EG, JO, KW, IR,
/// AF, the Gulf states) are deliberately absent — the setting models only
/// sunday | monday and every platform falls through to monday for them.
const SUNDAY_FIRST_REGIONS: [&str; 56] = [
    "AG", "AS", "BD", "BR", "BS", "BT", "BW", "BZ", "CA", "CO", "DM", "DO", "ET", "GT", "GU", "HK",
    "HN", "ID", "IL", "IN", "IS", "JM", "JP", "KE", "KH", "KR", "LA", "MH", "MM", "MO", "MT", "MX",
    "MZ", "NI", "NP", "PA", "PE", "PH", "PK", "PR", "PT", "PY", "SA", "SG", "SV", "TH", "TT", "TW",
    "UM", "US", "VE", "VI", "WS", "YE", "ZA", "ZW",
];

pub fn default_week_start_for_locale(locale: &str) -> WeekStart {
    if SUNDAY_FIRST_REGIONS.contains(&region_of_locale(locale).as_str()) {
        WeekStart::Sunday
    } else {
        WeekStart::Monday
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_unit_mi_for_imperial_regions_km_otherwise() {
        assert_eq!(default_unit_for_locale("en-US"), DistanceUnit::Mi);
        assert_eq!(default_unit_for_locale("en-GB"), DistanceUnit::Mi);
        assert_eq!(default_unit_for_locale("en-LR"), DistanceUnit::Mi);
        assert_eq!(default_unit_for_locale("my-MM"), DistanceUnit::Mi);
        assert_eq!(default_unit_for_locale("de-DE"), DistanceUnit::Km);
        assert_eq!(default_unit_for_locale("fr-FR"), DistanceUnit::Km);
        assert_eq!(default_unit_for_locale("en-AU"), DistanceUnit::Km);
        assert_eq!(default_unit_for_locale("ja-JP"), DistanceUnit::Km);
    }

    #[test]
    fn default_unit_km_for_unparseable_or_regionless_locale() {
        assert_eq!(default_unit_for_locale("en"), DistanceUnit::Km);
        assert_eq!(default_unit_for_locale(""), DistanceUnit::Km);
        assert_eq!(default_unit_for_locale("not-a-locale!!"), DistanceUnit::Km);
    }

    #[test]
    fn default_week_start_sunday_for_us_monday_for_europe() {
        assert_eq!(default_week_start_for_locale("en-US"), WeekStart::Sunday);
        assert_eq!(default_week_start_for_locale("en-CA"), WeekStart::Sunday);
        assert_eq!(default_week_start_for_locale("de-DE"), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale("fr-FR"), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale("en-GB"), WeekStart::Monday);
    }

    #[test]
    fn default_week_start_matches_cldr_where_the_hand_written_table_did_not() {
        // The 16-region table these three platforms once shared was wrong for
        // 19 regions. Argentina is Monday-first and was listed; the rest were
        // Sunday-first and were missing.
        assert_eq!(default_week_start_for_locale("es-AR"), WeekStart::Monday);
        for tag in [
            "pt-PT", "th-TH", "id-ID", "en-SG", "ar-SA", "es-DO", "es-GT", "es-HN", "es-SV",
            "es-NI", "es-PA", "es-PY", "sw-KE", "am-ET", "ur-PK", "bn-BD", "ar-YE", "ne-NP",
            "lo-LA",
        ] {
            assert_eq!(
                default_week_start_for_locale(tag),
                WeekStart::Sunday,
                "{tag}"
            );
        }
    }

    #[test]
    fn the_sunday_first_table_is_sorted_and_holds_no_duplicate() {
        // The table is transcribed from web's; a sort-and-dedupe check is what
        // makes a transcription slip visible rather than silently narrowing the
        // set by one region.
        for w in SUNDAY_FIRST_REGIONS.windows(2) {
            assert!(w[0] < w[1], "{} must sort before {}", w[0], w[1]);
        }
    }

    #[test]
    fn default_week_start_monday_for_regionless_locale() {
        assert_eq!(default_week_start_for_locale("en"), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale(""), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale("fr"), WeekStart::Monday);
    }
}
