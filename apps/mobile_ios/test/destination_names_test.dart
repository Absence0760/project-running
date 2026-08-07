// The Dart twin of web's `destination_names.test.ts` (decisions §539/§547).
//
// A destination's name is the thing a user searches for, so two destinations
// whose names differ only by a suffix are a contradiction on one surface. Web
// shipped exactly that — the sidebar's "Coach" beside the popover's "Coaching",
// one letter apart and not a sub-page of it — and grew a standing guard.
//
// Mobile got the fix but never the guard: round 16 hand-scanned these names
// across seven catalogues and fixed the one collision it found (German
// "Einstellungen" naming both Settings and its own Preferences tab), then
// recorded that "there is no standing Dart guard". A hand scan does not survive
// the next translation, which is the whole reason web's runs per locale.
//
// The predicate is web's, deliberately character-for-character: same folding,
// same `MAX_ENDING`, same no-space rule, and the fixtures below carry web's
// cases plus the mobile-only pair. Two platforms disagreeing about what counts
// as a collision would be worse than neither having a guard.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every key that names a top-level DESTINATION — a place the user navigates
/// to by name. The four bottom-nav slots plus every Settings landing tile.
/// Not page headings inside a destination, and not action labels.
const _destinationKeys = <String>[
  'navHome',
  'navFitness',
  'navSocial',
  'navYou',
  'settingsAccountTitle',
  'prefsTitle',
  'safetyTitle',
  'coachingTitle',
  'guidedRunsTitle',
  'integrationsTitle',
  'devicesTitle',
  'gearTitle',
  'proTitle',
  'aboutTitle',
];

const _locales = <String>['en', 'de', 'fr', 'es', 'ja', 'pt', 'pt_BR'];

/// Diacritic folding. Web gets this from `normalize('NFD')` + stripping the
/// combining marks; Dart's core has no `normalize`, so the Latin letters the
/// seven shipped catalogues actually use are mapped explicitly. Dropping this
/// would leave the twin diverging on "A propos" vs "À propos" — one of web's
/// own pinned cases.
const _diacritics = <String, String>{
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y',
};

/// Normalised for comparison: case, accents and separators are not what
/// distinguishes two destinations to a reader.
String _fold(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_diacritics[ch] ?? ch);
  }
  return buf.toString().replaceAll(RegExp(r'[\s&·/-]+'), ' ').trim();
}

/// A collision is either identical names, or one being the other plus a short
/// MORPHOLOGICAL ending — "coach" + "ing", "Trainer" + "in". The two limits are
/// what keep it from firing on unrelated names that merely start alike: the
/// extra is at most [_maxEnding] characters, and contains no space, because a
/// whole extra WORD is a token the reader sees before the name ends.
const _maxEnding = 6;

bool _collides(String a, String b) {
  final x = _fold(a);
  final y = _fold(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final short = x.length < y.length ? x : y;
  final long = x.length < y.length ? y : x;
  if (!long.startsWith(short)) return false;
  final ending = long.substring(short.length);
  return ending.length <= _maxEnding && !ending.contains(' ');
}

Map<String, dynamic> _catalogue(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  // Must-flag / must-spare in both directions, because the guard IS this
  // predicate. Web's fixture table, plus the pair only mobile ever had.
  test('the collision predicate matches web\'s, case for case', () {
    const fixtures = <(bool, String, String)>[
      (true, 'Coach', 'Coaching'),
      (true, 'Coaching', 'Coach'),
      (true, 'Trainer', 'Trainerin'),
      (true, 'Treinador', 'Treinadores'),
      (true, 'コーチ', 'コーチング'),
      (true, 'Gear', 'Gear'),
      (true, 'Gear', 'gear'),
      (true, 'Pro support', 'Pro & support'),
      // Accents do not distinguish two destinations. Web folds these through
      // NFD; without the map above this pair would pass here and fail there.
      (true, 'A propos', 'À propos'),
      (true, 'Configuracao', 'Configuração'),
      (true, 'Über', 'Übersicht'),
      // Mobile's own: German named Settings and its Preferences tab the same
      // word, which is the degenerate case rather than a suffix.
      (true, 'Einstellungen', 'Einstellungen'),
      (false, 'AI Coach', 'Athletes & coaches'),
      (false, 'Preferences', 'Pro & support'),
      (false, 'Conta', 'Contatos de segurança'),
      (false, 'Gear', 'Gear rotations'),
      // The distinguishing syllable at the FRONT is not a suffix.
      (false, 'Einstellungen', 'Voreinstellungen'),
    ];
    for (final (want, a, b) in fixtures) {
      expect(_collides(a, b), want,
          reason: 'collides("$a", "$b") should be $want');
    }
  });

  test('every destination name is distinguishable, in every locale', () {
    final offenders = <String>[];
    var compared = 0;

    for (final locale in _locales) {
      final arb = _catalogue(locale);
      final names = <String, String>{};
      for (final key in _destinationKeys) {
        final v = arb[key];
        expect(v, isA<String>(),
            reason: '$locale is missing the destination key $key');
        names[key] = v as String;
      }
      final keys = names.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          compared++;
          if (!_collides(names[keys[i]]!, names[keys[j]]!)) continue;
          offenders.add('$locale: ${keys[i]} "${names[keys[i]]}" vs '
              '${keys[j]} "${names[keys[j]]}"');
        }
      }
    }

    // Population: §534 — a key list that stopped resolving would satisfy the
    // assertion below over an empty comparison set.
    expect(
      compared,
      _locales.length * _destinationKeys.length * (_destinationKeys.length - 1) ~/ 2,
      reason: 'expected every pair in every locale to be compared',
    );

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'these destinations carry names a reader cannot tell apart. '
          'Rename one — a second word before either name ends is what '
          'separates them (§539).',
    );
  });
}
