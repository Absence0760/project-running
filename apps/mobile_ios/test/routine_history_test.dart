import 'package:flutter_test/flutter_test.dart';

import '../lib/routine_history.dart';

/// Mirror of `apps/web/src/lib/gym/routine_history.test.ts` — same cases in
/// the same order.

final int now = DateTime.parse('2026-08-15T12:00:00.000Z').millisecondsSinceEpoch;

RoutineSessionRow row(
  String id,
  String startedAt, {
  String? title,
  Object? metadata = const <String, dynamic>{},
}) =>
    RoutineSessionRow(
      id: id,
      startedAt: startedAt,
      title: title,
      metadata: metadata,
    );

/// The RPC's own tallies, defaulted off the page so a case that only cares
/// about row shaping doesn't have to restate them.
RoutineHistoryAggregate agg(
  List<RoutineSessionRow> recentRows, {
  int? sessionCount,
  String? lastPerformedAt,
  int gradedCount = 0,
  int completedCount = 0,
}) =>
    RoutineHistoryAggregate(
      sessionCount: sessionCount ?? recentRows.length,
      lastPerformedAt: lastPerformedAt,
      gradedCount: gradedCount,
      completedCount: completedCount,
      recentRows: recentRows,
    );

void main() {
  test('an empty aggregate yields a history the caller can self-hide on', () {
    final h = routineHistoryFromAggregate(agg(const []), now);
    expect(h.sessionCount, 0);
    expect(h.lastPerformedAt, isNull);
    expect(h.daysSinceLast, isNull);
    expect(h.completedRate, isNull);
    expect(h.gradedCount, 0);
    expect(h.recentSessions, isEmpty);
  });

  test('recent sessions are ordered newest first regardless of input order',
      () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-01T10:00:00.000Z'),
        row('c', '2026-08-12T10:00:00.000Z'),
        row('b', '2026-08-05T10:00:00.000Z'),
      ], lastPerformedAt: '2026-08-12T10:00:00.000Z'),
      now,
    );
    expect([for (final s in h.recentSessions) s.id], ['c', 'b', 'a']);
    expect(h.lastPerformedAt, '2026-08-12T10:00:00.000Z');
  });

  test('an in-flight draft row is not a performed session', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('done', '2026-08-10T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
        row('draft', '2026-08-14T10:00:00.000Z', metadata: {
          'routine_id': 'r1',
          'gym_session_draft': {
            'saved_at': '2026-08-14T10:05:00.000Z',
            'results': <dynamic>[],
          },
        }),
      ],
          sessionCount: 1,
          lastPerformedAt: '2026-08-10T10:00:00.000Z',
          gradedCount: 1,
          completedCount: 1),
      now,
    );
    expect(h.recentSessions.length, 1);
    expect(h.recentSessions[0].id, 'done');
    expect(h.sessionCount, 1);
    expect(h.lastPerformedAt, '2026-08-10T10:00:00.000Z');
  });

  test('a save-as-is row is ungraded, not completed', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('x', '2026-08-10T10:00:00.000Z', metadata: {'routine_id': 'r1'}),
      ], sessionCount: 1, lastPerformedAt: '2026-08-10T10:00:00.000Z'),
      now,
    );
    expect(h.sessionCount, 1);
    expect(h.recentSessions[0].verdict, RoutineSessionVerdict.ungraded);
    expect(h.gradedCount, 0);
    expect(h.completedCount, 0);
    expect(h.completedRate, isNull);
  });

  test('each stored verdict is carried through onto its row', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-01T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
        row('b', '2026-08-02T10:00:00.000Z',
            metadata: {'gym_adherence': 'partial'}),
        row('c', '2026-08-03T10:00:00.000Z',
            metadata: {'gym_adherence': 'abandoned'}),
        row('d', '2026-08-04T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
      ],
          sessionCount: 4,
          lastPerformedAt: '2026-08-04T10:00:00.000Z',
          gradedCount: 4,
          completedCount: 2),
      now,
    );
    expect([for (final s in h.recentSessions) s.verdict], [
      RoutineSessionVerdict.completed,
      RoutineSessionVerdict.abandoned,
      RoutineSessionVerdict.partial,
      RoutineSessionVerdict.completed,
    ]);
    expect(h.gradedCount, 4);
    expect(h.completedCount, 2);
    expect(h.completedRate, 0.5);
  });

  test('the rate is completed-of-GRADED, so an ungraded session is not a miss',
      () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-01T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
        row('b', '2026-08-02T10:00:00.000Z', metadata: {'routine_id': 'r1'}),
      ],
          sessionCount: 2,
          lastPerformedAt: '2026-08-02T10:00:00.000Z',
          gradedCount: 1,
          completedCount: 1),
      now,
    );
    expect(h.sessionCount, 2);
    expect(h.gradedCount, 1);
    expect(h.completedRate, 1);
  });

  test('an unrecognised verdict string is ungraded rather than trusted', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-01T10:00:00.000Z',
            metadata: {'gym_adherence': 'crushed_it'}),
      ], sessionCount: 1, lastPerformedAt: '2026-08-01T10:00:00.000Z'),
      now,
    );
    expect(h.recentSessions[0].verdict, RoutineSessionVerdict.ungraded);
    expect(h.gradedCount, 0);
  });

  test('a null or non-object metadata bag degrades to ungraded', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-01T10:00:00.000Z', metadata: null),
        row('b', '2026-08-02T10:00:00.000Z', metadata: 'nonsense'),
        const RoutineSessionRow(id: 'c', startedAt: '2026-08-03T10:00:00.000Z'),
      ], sessionCount: 3, lastPerformedAt: '2026-08-03T10:00:00.000Z'),
      now,
    );
    expect(h.recentSessions.length, 3);
    expect(h.gradedCount, 0);
  });

  test('days since last is whole elapsed days, floored', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-12T23:00:00.000Z'),
      ], sessionCount: 1, lastPerformedAt: '2026-08-12T23:00:00.000Z'),
      now,
    );
    expect(h.daysSinceLast, 2);
  });

  test('a session stamped ahead of the clock reads as today, never negative',
      () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-20T10:00:00.000Z'),
      ], sessionCount: 1, lastPerformedAt: '2026-08-20T10:00:00.000Z'),
      now,
    );
    expect(h.daysSinceLast, 0);
  });

  test('an unparseable start time is dropped rather than sorted as NaN', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('bad', 'not-a-date'),
        row('good', '2026-08-10T10:00:00.000Z'),
      ], sessionCount: 2, lastPerformedAt: '2026-08-10T10:00:00.000Z'),
      now,
    );
    expect(h.recentSessions.length, 1);
    expect(h.recentSessions[0].id, 'good');
  });

  test('a row with no id is dropped rather than rendered as an unlinkable session',
      () {
    final h = routineHistoryFromAggregate(
      agg([
        const RoutineSessionRow(id: '', startedAt: '2026-08-10T10:00:00.000Z'),
      ], sessionCount: 1),
      now,
    );
    expect(h.recentSessions.length, 0);
  });

  test('the workout title rides along for the session list', () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-10T10:00:00.000Z', title: 'Push day A'),
      ], sessionCount: 1),
      now,
    );
    expect(h.recentSessions[0].title, 'Push day A');
  });

  test('the count is the aggregate, not the page — a bounded page never caps it',
      () {
    final h = routineHistoryFromAggregate(
      agg([
        row('a', '2026-08-14T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
        row('b', '2026-08-07T10:00:00.000Z',
            metadata: {'gym_adherence': 'completed'}),
      ],
          sessionCount: 812,
          lastPerformedAt: '2026-08-14T10:00:00.000Z',
          gradedCount: 800,
          completedCount: 600),
      now,
    );
    expect(h.sessionCount, 812);
    expect(h.recentSessions.length, 2);
    expect(h.gradedCount, 800);
    expect(h.completedRate, 0.75);
    expect(h.daysSinceLast, 1);
  });

  test('an empty page under a real count still reports days since last', () {
    // The date is the aggregate's, so it survives a page the caller bounded to
    // nothing — reading it off the first listed row would lose it.
    final h = routineHistoryFromAggregate(
      agg(const [],
          sessionCount: 40,
          lastPerformedAt: '2026-08-05T12:00:00.000Z',
          gradedCount: 40,
          completedCount: 10),
      now,
    );
    expect(h.sessionCount, 40);
    expect(h.recentSessions, isEmpty);
    expect(h.daysSinceLast, 10);
    expect(h.completedRate, 0.25);
  });

  test('an unparseable last-performed stamp suppresses days-since rather than reading NaN',
      () {
    final h = routineHistoryFromAggregate(
      agg(const [], sessionCount: 3, lastPerformedAt: 'not-a-date'),
      now,
    );
    expect(h.sessionCount, 3);
    expect(h.daysSinceLast, isNull);
  });
}
