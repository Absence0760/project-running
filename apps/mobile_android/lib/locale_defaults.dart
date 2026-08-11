/// Locale-derived defaults for first-run settings — Dart twin of web
/// `apps/web/src/lib/format/locale_defaults.ts` (keep in lockstep).
///
/// Pure functions over a locale tag so they unit-test without a widget
/// tree; callers pass `Localizations.localeOf(context).toLanguageTag()`
/// (or `Platform.localeName`, hence the underscore tolerance below).
/// Web additionally consults `Intl.Locale.getWeekInfo()` when the
/// runtime exposes it; the Dart twin carries only the shared CLDR
/// region table, which agrees with it for every pinned test case.
library;

/// Extracts the uppercase region subtag from a BCP-47 ('en-US',
/// 'zh-Hant-TW') or POSIX ('en_US', 'en_US.UTF-8') locale string.
/// Returns '' when no region is present — mirroring web's `regionOfLocale`,
/// which returns '' for region-less or unparseable input.
String regionOfLocale(String locale) {
  final cleaned = locale.split('.').first.split('@').first;
  final parts = cleaned.split(RegExp('[-_]'));
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part) ||
        RegExp(r'^[0-9]{3}$').hasMatch(part)) {
      return part.toUpperCase();
    }
  }
  return '';
}

const Set<String> _imperialRegions = {'US', 'GB', 'LR', 'MM'};

String defaultUnitForLocale(String locale) =>
    _imperialRegions.contains(regionOfLocale(locale)) ? 'mi' : 'km';

// Regions whose CLDR week data starts the week on SUNDAY. Derived from
// Intl week data (firstDay === 7) over every assigned ISO 3166-1 alpha-2
// region, so the table and the Intl lookup above can never disagree.
//
// Kept identical to `SUNDAY_FIRST_REGIONS` in `locale_defaults.ts`. Dart has no
// Intl week-data equivalent, so this table is the ONLY source here. The hand-written 16-region
// version they shared disagreed with CLDR for 19 of them — it wrongly listed AR
// (Argentina is Monday-first) and omitted PT, TH, ID, SG, SA, DO, GT, HN, SV,
// NI, PA, PY, KE, ET, PK, BD, YE, NP and LA — so web (which consults Intl
// first) and mobile (which cannot) seeded different week starts, and
// `current_week` then bucketed the dashboard onto different seven days.
//
// Saturday-first regions (firstDay === 6: EG, JO, KW, SA-adjacent Gulf states,
// IR, AF …) are deliberately absent: the setting models only sunday | monday,
// and both platforms fall through to monday for them, which already agrees.
const Set<String> _sundayFirstRegions = {
  'AG', 'AS', 'BD', 'BR', 'BS', 'BT', 'BW', 'BZ',
  'CA', 'CO', 'DM', 'DO', 'ET', 'GT', 'GU', 'HK',
  'HN', 'ID', 'IL', 'IN', 'IS', 'JM', 'JP', 'KE',
  'KH', 'KR', 'LA', 'MH', 'MM', 'MO', 'MT', 'MX',
  'MZ', 'NI', 'NP', 'PA', 'PE', 'PH', 'PK', 'PR',
  'PT', 'PY', 'SA', 'SG', 'SV', 'TH', 'TT', 'TW',
  'UM', 'US', 'VE', 'VI', 'WS', 'YE', 'ZA', 'ZW',
};

String defaultWeekStartForLocale(String locale) =>
    _sundayFirstRegions.contains(regionOfLocale(locale))
        ? 'sunday'
        : 'monday';
