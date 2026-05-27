import 'package:core_models/core_models.dart' as cm;
import 'package:flutter_test/flutter_test.dart';

import '../lib/gear_backfill.dart';

cm.Run _run({
  required String id,
  required DateTime startedAt,
  String? activityType,
  double distanceMetres = 5000.0,
}) {
  return cm.Run(
    id: id,
    startedAt: startedAt,
    duration: const Duration(minutes: 30),
    distanceMetres: distanceMetres,
    track: const [],
    source: cm.RunSource.app,
    metadata: activityType == null
        ? null
        : <String, dynamic>{'activity_type': activityType},
  );
}

void main() {
  group('gearBackfillCandidates — pure helper', () {
    final purchased = DateTime.utc(2026, 1, 1);

    test('returns empty for empty input', () {
      expect(
        gearBackfillCandidates(
          gearKind: 'shoe',
          since: purchased,
          runs: const [],
        ),
        isEmpty,
      );
    });

    test('shoe gear matches running activities (run / walk / hike)', () {
      final runs = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5), activityType: 'run'),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 5), activityType: 'walk'),
        _run(id: 'r3', startedAt: DateTime.utc(2026, 1, 5), activityType: 'hike'),
        _run(id: 'r4', startedAt: DateTime.utc(2026, 1, 5), activityType: 'cycle'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['r1', 'r2', 'r3']);
    });

    test('bike gear matches only cycle activities', () {
      final runs = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5), activityType: 'run'),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 5), activityType: 'cycle'),
        _run(id: 'r3', startedAt: DateTime.utc(2026, 1, 5), activityType: 'walk'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'bike',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['r2']);
    });

    test('runs missing activity_type default to "run" — included for shoes',
        () {
      final runs = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5)),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['r1']);
    });

    test('runs before "since" are excluded', () {
      final runs = [
        _run(id: 'before', startedAt: DateTime.utc(2025, 12, 28), activityType: 'run'),
        _run(id: 'after', startedAt: DateTime.utc(2026, 1, 5), activityType: 'run'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['after']);
    });

    test('a run started exactly at "since" is included (boundary)', () {
      final runs = [
        _run(id: 'exact', startedAt: DateTime.utc(2026, 1, 1), activityType: 'run'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['exact']);
    });

    test('results are sorted newest-first', () {
      final runs = [
        _run(id: 'mid', startedAt: DateTime.utc(2026, 1, 5), activityType: 'run'),
        _run(id: 'old', startedAt: DateTime.utc(2026, 1, 2), activityType: 'run'),
        _run(id: 'new', startedAt: DateTime.utc(2026, 1, 10), activityType: 'run'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['new', 'mid', 'old']);
    });

    test('case-insensitive activity_type match', () {
      final runs = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5), activityType: 'Run'),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 5), activityType: 'CYCLE'),
      ];
      final shoe = gearBackfillCandidates(
        gearKind: 'shoe',
        since: purchased,
        runs: runs,
      );
      final bike = gearBackfillCandidates(
        gearKind: 'bike',
        since: purchased,
        runs: runs,
      );
      expect(shoe.map((r) => r.id), ['r1']);
      expect(bike.map((r) => r.id), ['r2']);
    });

    test('unknown gear kind falls through to shoe semantics', () {
      // Defensive — keeps the helper from silently returning empty
      // if a future gear kind ("strap"?) leaks into the call.
      final runs = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5), activityType: 'run'),
      ];
      final candidates = gearBackfillCandidates(
        gearKind: 'unknown',
        since: purchased,
        runs: runs,
      );
      expect(candidates.map((r) => r.id), ['r1']);
    });
  });
}
