import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/route_match.dart';

RouteMatchCandidate _c({
  required String id,
  required double distanceM,
  required double startOffsetM,
  required double endOffsetM,
}) =>
    RouteMatchCandidate(
      id: id,
      name: 'route-$id',
      distanceM: distanceM,
      startOffsetM: startOffsetM,
      endOffsetM: endOffsetM,
    );

void main() {
  group('bestStrongRouteMatch', () {
    test('returns null on an empty candidate list', () {
      expect(
        bestStrongRouteMatch(const <RouteMatchCandidate>[],
            runDistanceMetres: 5000),
        isNull,
      );
    });

    test('returns null when runDistanceMetres is zero or negative', () {
      // A run with zero/negative distance never auto-links — division
      // by zero would balloon the length ratio.
      final cs = [
        _c(id: 'a', distanceM: 5000, startOffsetM: 10, endOffsetM: 10),
      ];
      expect(
        bestStrongRouteMatch(cs, runDistanceMetres: 0),
        isNull,
      );
      expect(
        bestStrongRouteMatch(cs, runDistanceMetres: -1),
        isNull,
      );
    });

    test('returns the first candidate that passes both gates', () {
      final cs = [
        _c(id: 'a', distanceM: 5100, startOffsetM: 30, endOffsetM: 40),
      ];
      final hit = bestStrongRouteMatch(cs, runDistanceMetres: 5000);
      expect(hit, isNotNull);
      expect(hit!.id, 'a');
    });

    test('rejects when endpoint budget is exceeded', () {
      // sum of offsets = 250 > 200 budget.
      final cs = [
        _c(id: 'a', distanceM: 5000, startOffsetM: 200, endOffsetM: 50),
      ];
      expect(bestStrongRouteMatch(cs, runDistanceMetres: 5000), isNull);
    });

    test('rejects exactly at the endpoint budget (strict <)', () {
      // sum of offsets = 200, NOT under budget — the gate uses `<`.
      final cs = [
        _c(id: 'a', distanceM: 5000, startOffsetM: 100, endOffsetM: 100),
      ];
      expect(bestStrongRouteMatch(cs, runDistanceMetres: 5000), isNull);
    });

    test('rejects when length ratio exceeds the max', () {
      // 30% length difference; ratio = 0.30, gate is < 0.20.
      final cs = [
        _c(id: 'a', distanceM: 6500, startOffsetM: 10, endOffsetM: 10),
      ];
      expect(bestStrongRouteMatch(cs, runDistanceMetres: 5000), isNull);
    });

    test('rejects exactly at the length-ratio max (strict <)', () {
      // 20% length difference; ratio = 0.20, gate is `<` so reject.
      final cs = [
        _c(id: 'a', distanceM: 6000, startOffsetM: 10, endOffsetM: 10),
      ];
      expect(bestStrongRouteMatch(cs, runDistanceMetres: 5000), isNull);
    });

    test(
        'walks past a borderline candidate to pick the next one that '
        'actually passes', () {
      // The RPC orders by spatial overlap; if the spatially-best
      // candidate fails a gate, fall through. This pins the "first
      // passing wins" loop instead of accidentally re-ranking.
      final cs = [
        // Endpoint budget bust.
        _c(id: 'spatial-best-but-bad', distanceM: 5000,
            startOffsetM: 150, endOffsetM: 80),
        // Both gates pass.
        _c(id: 'second-but-good', distanceM: 5100,
            startOffsetM: 20, endOffsetM: 20),
      ];
      final hit = bestStrongRouteMatch(cs, runDistanceMetres: 5000);
      expect(hit, isNotNull);
      expect(hit!.id, 'second-but-good');
    });

    test('returns null when every candidate fails one gate or the other', () {
      final cs = [
        _c(id: 'a', distanceM: 5000, startOffsetM: 150, endOffsetM: 100), // ep
        _c(id: 'b', distanceM: 7000, startOffsetM: 10, endOffsetM: 10),   // len
        _c(id: 'c', distanceM: 5000, startOffsetM: 100, endOffsetM: 100), // ep tie
      ];
      expect(bestStrongRouteMatch(cs, runDistanceMetres: 5000), isNull);
    });

    test('shorter route still matches symmetrically (abs length diff)', () {
      // 5 km recorded vs 4500 m route → ratio = 500/5000 = 0.10 < 0.20.
      final cs = [
        _c(id: 'a', distanceM: 4500, startOffsetM: 30, endOffsetM: 30),
      ];
      final hit = bestStrongRouteMatch(cs, runDistanceMetres: 5000);
      expect(hit, isNotNull);
      expect(hit!.id, 'a');
    });
  });
}
