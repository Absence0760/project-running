import 'dart:ui';

/// Pure locale negotiation + direction helpers — the Dart twin of the web
/// runtime's `apps/web/src/lib/i18n/locale.ts`. No Flutter widget tree, no
/// generated catalogue, so it unit-tests without `pumpWidget`. The reactive
/// side (the `localeNotifier` + `MaterialApp.locale` wiring) lives in
/// `main.dart`; the persisted user choice lives in `preferences.dart`.
///
/// Locale is a per-device setting (mirrors web's localStorage-only model):
/// a stored choice wins, otherwise the device's preferred locales are
/// negotiated, falling back to English.

/// The seven locales we ship. Portuguese ships TWICE, as two real catalogues:
/// European Portuguese and Brazilian, differing on 1164 of their 3793 strings
/// ("partilhar" vs "compartilhar", "em direto" vs "ao vivo", "ecrã" vs "tela").
///
/// European Portuguese is tagged `pt-PT` here, matching web's `pt-PT.ts`, the
/// wrist's `values-b+pt+PT` and iOS's `CFBundleLocalizations`. Its ARB file is
/// nonetheless `app_pt.arb`: gen-l10n REFUSES to generate when a country-coded
/// catalogue exists without a bare base ("Arb file for a fallback, pt, does not
/// exist"), so the base file is the tool's, and the tag is ours. The generated
/// delegate resolves `Locale('pt', 'PT')` through that base, and the
/// locale-reach guard holds the two spellings together through `arbTagOverride`
/// — the same shape it already used for the plist.
const List<Locale> supportedLocales = <Locale>[
  Locale('en'),
  Locale('de'),
  Locale('fr'),
  Locale('es'),
  Locale('ja'),
  Locale('pt', 'PT'),
  Locale('pt', 'BR'),
];

const Locale defaultLocale = Locale('en');

/// Endonyms (each language's own name) for the picker — never translated,
/// always shown in the target language's own script. Keyed by canonical tag.
const Map<String, String> localeLabels = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'ja': '日本語',
  'pt-PT': 'Português (Portugal)',
  'pt-BR': 'Português (Brasil)',
};

// Case-insensitive exact-tag map. Keys are lowercased; values are the
// canonical Locale we actually use (`pt-BR`, not `pt-br`).
const Map<String, Locale> _exact = <String, Locale>{
  'en': Locale('en'),
  'de': Locale('de'),
  'fr': Locale('fr'),
  'es': Locale('es'),
  'ja': Locale('ja'),
  'pt-pt': Locale('pt', 'PT'),
  'pt-br': Locale('pt', 'BR'),
};

// Base-language fallback: a tag we don't carry exactly (fr-CA, de-AT) still
// resolves to the one variant we ship for that language. Portuguese is the
// exception with two variants, and its base maps to the EUROPEAN one, matching
// web's `BASE_TO_LOCALE` (locale.ts): `pt-AO`, `pt-MZ` and `pt-CV` share
// Portugal's orthography and have nowhere else to land, while `pt-BR` — which
// Android, iOS and every browser report with the region — matches `_exact`
// first, so Brazil is unaffected.
const Map<String, Locale> _baseToLocale = <String, Locale>{
  'en': Locale('en'),
  'de': Locale('de'),
  'fr': Locale('fr'),
  'es': Locale('es'),
  'ja': Locale('ja'),
  'pt': Locale('pt', 'PT'),
};

// RTL base languages. None of the current six is RTL, but the switch-point
// exists so dropping in an Arabic/Hebrew catalogue later flips text
// direction with no further plumbing (mirrors web's `RTL_BASES`).
const Set<String> _rtlBases = <String>{'ar', 'he', 'fa', 'ur'};

/// Canonical BCP-47-ish tag for a [Locale]: `en`, `pt-BR`.
String localeToTag(Locale locale) => locale.countryCode == null
    ? locale.languageCode
    : '${locale.languageCode}-${locale.countryCode}';

/// Parse a stored/canonical tag back into a [Locale]. Accepts `-` or `_`
/// separators. Returns null for null/empty input.
Locale? localeFromTag(String? tag) {
  if (tag == null || tag.trim().isEmpty) return null;
  final parts = tag.trim().split(RegExp('[-_]'));
  if (parts.length == 1) return Locale(parts[0]);
  return Locale(parts[0], parts[1].toUpperCase());
}

bool isSupportedTag(String? tag) =>
    tag != null && _exact.containsKey(tag.toLowerCase());

TextDirection dirForLocale(Locale locale) =>
    _rtlBases.contains(locale.languageCode.toLowerCase())
        ? TextDirection.rtl
        : TextDirection.ltr;

Locale? _exactMatch(String tag) => _exact[tag.toLowerCase()];

Locale? _baseMatch(String tag) =>
    _baseToLocale[tag.toLowerCase().split(RegExp('[-_]'))[0]];

/// Resolve the best supported locale. A [stored] preference (our own
/// canonical tag, written by the picker) wins outright; otherwise the
/// device's [devicePreferred] locales are walked in priority order — exact
/// match then base-language match for each, before moving to the next,
/// lower-priority entry — falling back to [defaultLocale].
///
/// Walking exact-then-base per entry (rather than all-exact-first) matters:
/// a device list of `[fr-CA, en]` must resolve to `fr` (the top preference,
/// shipped as the `fr` base), not `en`.
Locale negotiateLocale(String? stored, List<Locale> devicePreferred) {
  if (stored != null && stored.isNotEmpty) {
    final m = _exactMatch(stored) ?? _baseMatch(stored);
    if (m != null) return m;
  }
  for (final locale in devicePreferred) {
    final tag = localeToTag(locale);
    final m = _exactMatch(tag) ?? _baseMatch(tag);
    if (m != null) return m;
  }
  return defaultLocale;
}

// The active app-locale tag, kept in sync by `main.dart` (mirrors the
// `registerActivePreferences` pattern in `preferences.dart`). `main.dart`
// owns the reactive `localeNotifier`; importing it here would cycle, so the
// resolved tag is pushed in via [registerActiveLocaleTag] on every locale
// change instead. Surfaces without a `BuildContext` (share cards,
// notification text, period-summary share text) read [activeLocaleTag];
// where a context exists, prefer `Localizations.localeOf(context)`.
String _activeLocaleTag = localeToTag(defaultLocale);

/// Register the resolved active-locale tag. Called from `main.dart` on
/// startup and whenever `localeNotifier` changes. Idempotent.
void registerActiveLocaleTag(String tag) {
  _activeLocaleTag = tag;
}

/// The current active-locale tag (`en`, `pt-BR`). Falls back to the default
/// locale's tag before `main.dart` has registered one (host-test runner,
/// very early app start). Use this for date formatting on context-free
/// surfaces; with a `BuildContext`, prefer `Localizations.localeOf(context)`.
String get activeLocaleTag => _activeLocaleTag;

/// Resolve the active-locale tag from the user's stored choice (null =
/// follow device) negotiated against the device's preferred locales. Pure —
/// `main.dart` calls this with `localeNotifier.value` + the platform
/// locales to compute the tag it then registers.
String resolveActiveLocaleTag(
        Locale? stored, List<Locale> devicePreferred) =>
    localeToTag(negotiateLocale(
        stored == null ? null : localeToTag(stored), devicePreferred));
