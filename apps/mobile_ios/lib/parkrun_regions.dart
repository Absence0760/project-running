/// parkrun regional footprint — Dart twin of web
/// `apps/web/src/lib/integrations/parkrun_regions.ts` (keep in lockstep).
///
/// parkrun operates in a limited set of countries (~20 as of 2026);
/// outside them the integrations tile keeps working (an expat with a
/// parkrun athlete ID can still import) but discloses that there may be
/// no events nearby. An unknown region shows nothing rather than a
/// false warning.
library;

import 'locale_defaults.dart';

const Set<String> parkrunRegions = {
  'AU', 'AT', 'CA', 'DK', 'DE', 'FI', 'IE', 'IT', 'JP', 'LT', 'MY',
  'NA', 'NL', 'NO', 'NZ', 'PL', 'SE', 'SG', 'GB', 'US', 'ZA',
};

bool parkrunLikelyUnavailable(String locale) {
  final region = regionOfLocale(locale);
  return region.isNotEmpty && !parkrunRegions.contains(region);
}
