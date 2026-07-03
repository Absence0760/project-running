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

const Set<String> _sundayFirstRegions = {
  'US', 'CA', 'JP', 'IL', 'KR', 'TW', 'HK', 'IN', 'PH', 'BR', 'MX', 'ZA',
  'CO', 'AR', 'PE', 'VE',
};

String defaultWeekStartForLocale(String locale) =>
    _sundayFirstRegions.contains(regionOfLocale(locale))
        ? 'sunday'
        : 'monday';
