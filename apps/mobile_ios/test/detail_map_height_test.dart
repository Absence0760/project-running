// Issue #666 C9: four detail screens each picked a fixed hero-map height —
// 320 (route_detail), 320 (public_route), 300 (public_run), 280 (run_detail,
// the same map as public_run). None of them reflowed, and the wide branch only
// fires at >= 840dp, so a 667x375 landscape phone kept the compact layout with
// a ~295dp viewport that a 320dp map filled outright.
//
// Per §500 these tests pin the DERIVATION, never an absolute fit: the ratios,
// the monotonicity, the invariant that content always peeks, and the clamps.
// The source guard is the other half — §502's lesson is that a layout constant
// true of one Flutter version decays silently, so the durable form is a helper
// plus a guard against the next screen hard-coding a number.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/detail_map_height.dart';

/// Every scroll view that hosts a map, and the token its map is built from.
const _mapHosts = <String>[
  'lib/screens/route_detail_screen.dart',
  'lib/screens/public_route_screen.dart',
  'lib/screens/public_run_screen.dart',
  'lib/screens/run_detail_screen.dart',
];

/// Widgets whose height, when it is a literal, is the defect this closed.
const _mapBuilders = <String>['LiveRunMap(', '_buildMapStack(', 'FlutterMap('];

/// A `height:` on a plain number — `height: 320,` — as opposed to a derived
/// one. Anchored on the digit so `height: detailMapHeight(...)` cannot match.
final _literalHeight = RegExp(r'height:\s*[\d.]+\s*,');

void main() {
  group('detailMapHeight derivation', () {
    test('the reference phone keeps the hero the screens had shipped', () {
      // 360x800 with a 24dp status bar and a 56dp app bar leaves 720dp, where
      // the four screens had settled on 280-320.
      final h = detailMapHeight(720);
      expect(h, greaterThanOrEqualTo(280));
      expect(h, lessThanOrEqualTo(340));
    });

    test('content always peeks below the map', () {
      for (final viewport in [240.0, 295.0, 375.0, 480.0, 720.0, 1200.0]) {
        expect(detailMapHeight(viewport),
            lessThanOrEqualTo(viewport - kDetailMapMinPeek),
            reason: 'a $viewport dp viewport left no body below the map');
      }
    });

    test('the landscape phone that motivated this no longer fills its body',
        () {
      // 667x375 landscape, 24dp status bar, 56dp app bar.
      const viewport = 375.0 - 24 - 56;
      final h = detailMapHeight(viewport);
      expect(h, lessThan(320), reason: 'the shipped 320 exceeded the viewport');
      expect(viewport - h, greaterThanOrEqualTo(kDetailMapMinPeek));
    });

    test('is a share of the viewport, not a constant', () {
      // Below the cap, doubling the viewport doubles the map.
      expect(detailMapHeight(800) / detailMapHeight(400),
          closeTo(800 / 400, 0.001));
    });

    test('never shrinks as the viewport grows', () {
      var previous = 0.0;
      for (var viewport = 200.0; viewport <= 2000; viewport += 17) {
        final h = detailMapHeight(viewport);
        expect(h, greaterThanOrEqualTo(previous), reason: 'at $viewport dp');
        previous = h;
      }
    });

    test('a tall viewport spends its extra height on content', () {
      expect(detailMapHeight(4000), kDetailMapMaxHeight);
    });

    test('stays legible until the peek invariant outbids it', () {
      // 356dp is where the fraction crosses the legibility floor.
      expect(detailMapHeight(356), closeTo(kDetailMapMinHeight, 0.5));
      expect(detailMapHeight(300), kDetailMapMinHeight);
      // Past here the peek wins, because a body nobody can see is worse than
      // a short map.
      expect(detailMapHeight(260), lessThan(kDetailMapMinHeight));
    });

    test('a degenerate viewport degrades rather than throwing', () {
      expect(detailMapHeight(0), kDetailMapMinHeight);
      expect(detailMapHeight(-1), kDetailMapMinHeight);
      expect(detailMapHeight(double.nan), kDetailMapMinHeight);
      expect(detailMapHeight(double.infinity), kDetailMapMaxHeight);
    });
  });

  group('no screen hard-codes a map height', () {
    test('every listed map host still exists', () {
      for (final path in _mapHosts) {
        expect(File(path).existsSync(), isTrue,
            reason: '$path is guarded but missing — if it moved, move the '
                'entry rather than dropping the guard');
      }
    });

    test('every map host derives its hero height', () {
      for (final path in _mapHosts) {
        expect(File(path).readAsStringSync(), contains('detailMapHeight('),
            reason: '$path hosts a map but picks its own height');
      }
    });

    test('no file under lib/ sizes a map with a literal', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!_literalHeight.hasMatch(lines[i])) continue;
          // The map is the sized box's child, so it lands on the next line or
          // the one after it once a `child:` wrapper intervenes.
          final window = lines.sublist(i + 1, (i + 3).clamp(0, lines.length));
          if (_mapBuilders.any((b) => window.any((l) => l.contains(b)))) {
            offenders.add('${entity.path}:${i + 1} ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a map sized by a literal does not reflow — wrap the scroll '
              'view in a LayoutBuilder and take detailMapHeight(viewport'
              '.maxHeight) instead:\n${offenders.join('\n')}');
    });
  });
}
