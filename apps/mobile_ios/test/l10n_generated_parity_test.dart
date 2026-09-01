// The ARB catalogues against the CHECKED-IN generated catalogues.
//
// `l10n_parity_test.dart` measures the seven `.arb` files against each other;
// `architecture_guards_test.dart` measures the locale SET the generated
// delegate carries. Between them sits the step neither one takes: `gen-l10n`
// is run by hand and its output is committed, so an ARB whose wording changed
// without a regeneration ships the OLD sentence, in every locale, with nothing
// failing. A key ADDED without regenerating only fails if some caller reaches
// for it; a key whose VALUE changed fails nothing at all; and a hand-edit to a
// `gen/` file — several thousand lines of which landed across the #789 sweep —
// is invisible from both directions.
//
// So this reads the generated Dart back and compares it to the ARB it was
// generated from: the member set in both directions, and, for every message
// that is not an ICU plural/select, the wording itself.
//
// The comparison is on the SOURCE rather than through the delegate because
// there is no reflection here — no way to ask an `AppLocalizations` for the
// value of a getter named at runtime.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One shipped catalogue: its ARB tag, the generated file, and the class
/// inside it. `pt` and `pt_BR` share one file (gen-l10n emits the regional
/// class as a subclass in the same library), so the class name is what
/// separates them.
class _Catalogue {
  final String tag;
  final String file;
  final String className;
  const _Catalogue(this.tag, this.file, this.className);
}

const _catalogues = <_Catalogue>[
  _Catalogue('en', 'app_localizations_en.dart', 'AppLocalizationsEn'),
  _Catalogue('de', 'app_localizations_de.dart', 'AppLocalizationsDe'),
  _Catalogue('fr', 'app_localizations_fr.dart', 'AppLocalizationsFr'),
  _Catalogue('es', 'app_localizations_es.dart', 'AppLocalizationsEs'),
  _Catalogue('ja', 'app_localizations_ja.dart', 'AppLocalizationsJa'),
  _Catalogue('pt', 'app_localizations_pt.dart', 'AppLocalizationsPt'),
  _Catalogue('pt_BR', 'app_localizations_pt.dart', 'AppLocalizationsPtBr'),
];

/// A Dart identifier. Deliberately spelled out in ASCII: it is what keeps the
/// placeholder rewrite correct against the Japanese catalogue, where a
/// generated interpolation is the identifier followed immediately by a
/// character no identifier may contain.
const _id = r'[A-Za-z_][A-Za-z0-9_]*';

/// An escaped dollar in the generated source is a literal dollar, not the
/// start of an interpolation. Carrying it through unescaping as a plain one
/// would let [_toArbPlaceholders] read the text after it as a placeholder
/// name, so it travels as a sentinel and is restored last. NUL cannot occur
/// in either input.
const _dollarSentinel = '\u0000';

/// The body of the string literal starting at [from], plus the offset just
/// past its closing quote.
List<Object> _readLiteral(String src, int from) {
  final quote = src[from];
  final buf = StringBuffer();
  var i = from + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == r'\') {
      final next = src[i + 1];
      buf.write(switch (next) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        r'$' => _dollarSentinel,
        _ => next,
      });
      i += 2;
      continue;
    }
    if (c == quote) return [buf.toString(), i + 1];
    buf.write(c);
    i++;
  }
  throw StateError('unterminated string literal at offset $from');
}

/// The concatenation of the adjacent string literals starting at [from], up to
/// the terminating `;`. Null when anything other than a literal appears —
/// which is how a message assembled through `NumberFormat` or `pluralLogic`
/// excludes itself rather than being reported as drift.
String? _literalChain(String src, int from) {
  final buf = StringBuffer();
  var i = from;
  while (i < src.length) {
    final c = src[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      final read = _readLiteral(src, i);
      buf.write(read[0] as String);
      i = read[1] as int;
      continue;
    }
    return c == ';' ? buf.toString() : null;
  }
  return null;
}

/// The source of one class body, from its opening brace to the next top-level
/// `class` (or the end of the file).
String _classBody(String src, String className) {
  final open = RegExp('class $className extends $_id \\{').firstMatch(src);
  if (open == null) {
    throw StateError('class $className not found — did gen-l10n rename it?');
  }
  final rest = src.substring(open.end);
  final next = RegExp(r'\nclass ').firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

/// Every message member the class declares: `String get x` getters and
/// `String x(...)` methods alike.
Set<String> _members(String body) => <String>{
      for (final m in RegExp('\\n  String get ($_id)').allMatches(body))
        m.group(1)!,
      for (final m in RegExp('\\n  String ($_id)\\(').allMatches(body))
        m.group(1)!,
    };

/// Every member whose value is a plain literal chain, keyed by name. A member
/// built from anything else is absent rather than wrong.
Map<String, String> _literalValues(String body) {
  final out = <String, String>{};
  for (final m in RegExp('\\n  String get ($_id) =>').allMatches(body)) {
    final value = _literalChain(body, m.end);
    if (value != null) out[m.group(1)!] = value;
  }
  for (final m in RegExp('\\n  String ($_id)\\([^)]*\\) \\{\\s*return ')
      .allMatches(body)) {
    final value = _literalChain(body, m.end);
    if (value != null) out[m.group(1)!] = value;
  }
  return out;
}

/// A generated literal rewritten into the ARB's own placeholder spelling.
String _toArbPlaceholders(String generated) => generated
    .replaceAllMapped(
        RegExp(r'\$\{(' '$_id' r')\}'), (m) => '{${m.group(1)}}')
    .replaceAllMapped(RegExp(r'\$(' '$_id' r')'), (m) => '{${m.group(1)}}')
    .replaceAll(_dollarSentinel, r'$');

Map<String, dynamic> _readArb(String tag) => jsonDecode(
    File('lib/l10n/app_$tag.arb').readAsStringSync()) as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// An ICU plural or select compiles to `Intl.pluralLogic` / `selectLogic`
/// rather than to one literal, so its wording is out of this guard's reach.
bool _isIcu(String value) =>
    value.contains('plural,') || value.contains('select,');

void main() {
  final enKeys = _messageKeys(_readArb('en'));

  test('the abstract base declares exactly the template key set', () {
    // The base is what every screen calls through, so a key missing here is a
    // key no caller can reach whatever the catalogues hold.
    final src = File('lib/l10n/gen/app_localizations.dart').readAsStringSync();
    final open = RegExp(r'abstract class AppLocalizations \{').firstMatch(src);
    expect(open, isNotNull, reason: 'the generated base class has moved');
    final body = src.substring(open!.end);
    final members = <String>{
      for (final m in RegExp('\\n  String get ($_id);').allMatches(body))
        m.group(1)!,
      for (final m in RegExp('\\n  String ($_id)\\(').allMatches(body))
        m.group(1)!,
    };
    expect(members.length, greaterThan(3000),
        reason: 'only ${members.length} members parsed out of the generated '
            'base — the scanner broke and this test checks nothing');
    expect((members.difference(enKeys).toList()..sort()), isEmpty,
        reason: 'the generated base declares members app_en.arb does not — '
            'gen/ is ahead of the catalogue, or was edited by hand');
    expect((enKeys.difference(members).toList()..sort()), isEmpty,
        reason: 'app_en.arb declares keys the generated base does not — run '
            '`flutter gen-l10n` and commit lib/l10n/gen/');
  });

  for (final catalogue in _catalogues) {
    group('${catalogue.tag} to ${catalogue.className}', () {
      late Map<String, dynamic> arb;
      late String body;

      setUpAll(() {
        arb = _readArb(catalogue.tag);
        body = _classBody(
          File('lib/l10n/gen/${catalogue.file}').readAsStringSync(),
          catalogue.className,
        );
      });

      test('the scan still sees the file it is reading', () {
        // Without this the two tests below would pass against an empty scan
        // the moment gen-l10n changed the shape it emits.
        expect(_members(body).length, greaterThan(3000),
            reason: 'only ${_members(body).length} members parsed out of '
                '${catalogue.className} — the scanner broke and this group is '
                'checking nothing');
      });

      test('carries exactly the catalogue keys', () {
        final members = _members(body);
        final keys = _messageKeys(arb);
        expect((keys.difference(members).toList()..sort()), isEmpty,
            reason: 'app_${catalogue.tag}.arb declares keys '
                '${catalogue.className} does not — run `flutter gen-l10n` and '
                'commit lib/l10n/gen/');
        expect((members.difference(keys).toList()..sort()), isEmpty,
            reason: '${catalogue.className} declares members '
                'app_${catalogue.tag}.arb does not — the generated file is '
                'stale, or was edited by hand');
      });

      test('every non-ICU message carries the catalogue wording', () {
        // The failure this exists for: an ARB value edited without a
        // regeneration ships the previous sentence, and nothing else in the
        // tree can tell.
        final values = _literalValues(body);
        var checked = 0;
        final drifted = <String>[];
        for (final entry in arb.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key.startsWith('@') || value is! String) continue;
          if (_isIcu(value)) continue;
          final generated = values[key];
          if (generated == null) continue;
          checked++;
          if (_toArbPlaceholders(generated) != value) {
            drifted.add('$key\n  arb: ${jsonEncode(value)}\n  gen: '
                '${jsonEncode(_toArbPlaceholders(generated))}');
          }
        }
        expect(checked, greaterThan(3000),
            reason: 'only $checked messages were comparable in '
                '${catalogue.className} — the literal scan broke');
        expect(drifted, isEmpty,
            reason: 'the checked-in ${catalogue.className} does not say what '
                'app_${catalogue.tag}.arb says. Run `flutter gen-l10n` and '
                'commit lib/l10n/gen/:\n${drifted.join('\n')}');
      });
    });
  }
}
