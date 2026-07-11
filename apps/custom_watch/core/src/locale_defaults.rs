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

/// Sunday-first-week regions. Europe / ISO-8601 is Monday-first; the Americas,
/// much of East Asia, and Israel start on Sunday. A region-less locale stays on
/// the neutral ISO/Monday default (mirrors the km default above) rather than
/// letting a maximization step promote `en` to `en-US` to Sunday.
const SUNDAY_FIRST_REGIONS: [&str; 16] = [
    "US", "CA", "JP", "IL", "KR", "TW", "HK", "IN", "PH", "BR", "MX", "ZA", "CO", "AR", "PE", "VE",
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
    fn default_week_start_monday_for_regionless_locale() {
        assert_eq!(default_week_start_for_locale("en"), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale(""), WeekStart::Monday);
        assert_eq!(default_week_start_for_locale("fr"), WeekStart::Monday);
    }
}
