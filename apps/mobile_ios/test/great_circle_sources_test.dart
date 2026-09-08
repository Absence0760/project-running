// Where the Dart tree is allowed to compute a great-circle distance, and why
// each remaining place still does. The mirror of the web's
// `routes/great_circle_sources.test.ts`, and the reason this class of
// divergence survived as long as it did: the web tree has been guarded since
// § 1470 while the phone had no guard at all, so `route_snap.dart` importing
// the clamped helper and `route_snap.ts` computing its own unclamped arc read
// as healthy from either side alone.
//
// The tree carried FOURTEEN arcs across thirteen files when this was written,
// counted: two took the `atan2` form and twelve an `asin`, of which six
// clamped with `min(1, …)`, one (the canonical) clamped through a variable,
// and five clamped nothing at all. Where rounding pushes the haversine `a` a
// hair above 1, `sqrt(1 - a)` is NaN and `asin` of a root above 1 is NaN too,
// so seven of the fourteen answered NaN there and seven answered half a
// circumference — § 305's recorded near-miss, live on the platform nothing
// was watching, and split down the middle.
//
// ANCHORING. Keyed on the ARC, not on a name, a radius literal or a body
// fingerprint: a great-circle distance has to take an `asin` or an `atan2` of
// a square root, and no rename, reformat or re-derivation removes that. A
// bearing's `atan2(y, x)` carries no square root, so `turn_cues.dart`'s
// bearing and `track_decorations.dart`'s screen angle are outside the anchor
// by construction rather than by exclusion.
//
// TEST FILES are outside the scan on purpose: a suite that reimplements the
// distance as an independent oracle is the one place a second copy is the
// point rather than the defect.
//
// The table is one row long: the canonical, and nothing else. A row added to
// admit a second one has to say why it cannot import `run_stats.dart`.

import 'package:flutter_test/flutter_test.dart';

import '../lib/run_stats.dart' show haversineMetres;
import 'source_scan.dart';

const _root = 'lib';

/// An `asin`/`atan2` applied to a square root, with at most one wrapping call
/// (the `min(1, …)` clamp) between them. Whitespace is stripped first, so a
/// reformat cannot hide one, and the `math.` prefix is optional because the
/// tree imports `dart:math` both ways.
final _arcOfASquareRoot = RegExp(
  r'(?<![A-Za-z0-9_$])(?:math\.)?(?:asin|atan2)\([^;]{0,80}?(?:math\.)?sqrt\(',
);

class _Source {
  final String file;
  final int arcs;
  final String reason;
  const _Source(this.file, this.arcs, this.reason);
}

const _greatCircleSources = <_Source>[
  _Source(
    'lib/run_stats.dart',
    1,
    'THE canonical. Exported as `haversineMetres`, clamps `a` into [0, 1] '
        'before the arc, and is what `run_stats.ts` computes point for point '
        '— so it is the one form both platforms already agree on. Every other '
        'module in this tree that needs a great-circle distance imports it.',
  ),
];

Map<String, int> _arcCounts() {
  final found = <String, int>{};
  for (final file in dartFiles(_root)) {
    final rel = file.path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');
    final stripped =
        blankNonCode(file.readAsStringSync()).replaceAll(RegExp(r'\s+'), '');
    final hits = _arcOfASquareRoot.allMatches(stripped).length;
    if (hits > 0) found[rel] = hits;
  }
  return found;
}

void main() {
  test('no module computes a great-circle distance the table does not know about',
      () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    final declared = _greatCircleSources.map((s) => s.file).toSet();
    final undeclared = _arcCounts().keys.where((f) => !declared.contains(f)).toList()
      ..sort();
    expect(
      undeclared,
      isEmpty,
      reason: 'a new copy of the great-circle distance. Import '
          '`haversineMetres` from `run_stats.dart` instead; if the module '
          'genuinely cannot, add it to _greatCircleSources with the reason:\n'
          '${undeclared.join('\n')}',
    );
  });

  test('every table entry still computes one, and only as many as it claims', () {
    final found = _arcCounts();
    for (final source in _greatCircleSources) {
      expect(
        found[source.file] ?? 0,
        source.arcs,
        reason: '${source.file} computes ${found[source.file] ?? 0} '
            'great-circle arcs, table says ${source.arcs}. If it now imports '
            'the shared one, delete the entry — a stale reason outlives the '
            'condition it describes. Reason on record: ${source.reason}',
      );
    }
  });

  test('the canonical clamps before the arc, which is why it is the canonical',
      () {
    // A behavioural pin, not a reading of the source: every unclamped form the
    // tree carried answers NaN where `a` rounds past 1, and consolidating onto
    // an unclamped canonical would have propagated that everywhere at once
    // instead of removing it. The same pair the web guard uses.
    final d = haversineMetres(-87.5, 0, 87.5, 180);
    expect(d.isFinite, isTrue, reason: 'near-antipodal distance must be a number');
    expect(d, greaterThan(20010000));
    expect(d, lessThan(20020000));
  });

  test('the guard still sees the shape it exists to catch', () {
    // A scan that silently matches nothing — a moved root, a regex broken by a
    // refactor — passes the tests above for the wrong reason (§ 510).
    const sample =
        'asin(sqrt(h))math.asin(math.min(1,math.sqrt(h)))atan2(sqrt(a),sqrt(1-a))';
    expect(_arcOfASquareRoot.allMatches(sample).length, 3);
    // A bearing takes an atan2 of no square root and must not be reported.
    expect(_arcOfASquareRoot.hasMatch('atan2(y,x)'), isFalse);
    // Nor may a longer name ending in the same letters be mistaken for one.
    expect(_arcOfASquareRoot.hasMatch(r'_myasin(sqrt(h))'), isFalse);
  });
}
