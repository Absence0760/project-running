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

void main() {
  test('no rows yields an empty history the caller can self-hide on', () {
    final h = summariseRoutineHistory(const [], now);
    expect(h.sessionCount, 0);
    expect(h.lastPerformedAt, isNull);
    expect(h.daysSinceLast, isNull);
    expect(h.completedRate, isNull);
    expect(h.gradedCount, 0);
    expect(h.sessions, isEmpty);
  });

  test('sessions are ordered newest first regardless of input order', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-01T10:00:00.000Z'),
      row('c', '2026-08-12T10:00:00.000Z'),
      row('b', '2026-08-05T10:00:00.000Z'),
    ], now);
    expect([for (final s in h.sessions) s.id], ['c', 'b', 'a']);
    expect(h.lastPerformedAt, '2026-08-12T10:00:00.000Z');
  });

  test('an in-flight draft row is not a performed session', () {
    final h = summariseRoutineHistory([
      row('done', '2026-08-10T10:00:00.000Z',
          metadata: {'gym_adherence': 'completed'}),
      row('draft', '2026-08-14T10:00:00.000Z', metadata: {
        'routine_id': 'r1',
        'gym_session_draft': {
          'saved_at': '2026-08-14T10:05:00.000Z',
          'results': <dynamic>[],
        },
      }),
    ], now);
    expect(h.sessionCount, 1);
    expect(h.sessions[0].id, 'done');
    expect(h.lastPerformedAt, '2026-08-10T10:00:00.000Z');
  });

  test('a save-as-is row counts as a session but is ungraded, not completed',
      () {
    final h = summariseRoutineHistory([
      row('x', '2026-08-10T10:00:00.000Z', metadata: {'routine_id': 'r1'}),
    ], now);
    expect(h.sessionCount, 1);
    expect(h.sessions[0].verdict, RoutineSessionVerdict.ungraded);
    expect(h.gradedCount, 0);
    expect(h.completedCount, 0);
    expect(h.completedRate, isNull);
  });

  test('each stored verdict is carried through and counted', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-01T10:00:00.000Z',
          metadata: {'gym_adherence': 'completed'}),
      row('b', '2026-08-02T10:00:00.000Z',
          metadata: {'gym_adherence': 'partial'}),
      row('c', '2026-08-03T10:00:00.000Z',
          metadata: {'gym_adherence': 'abandoned'}),
      row('d', '2026-08-04T10:00:00.000Z',
          metadata: {'gym_adherence': 'completed'}),
    ], now);
    expect([for (final s in h.sessions) s.verdict], [
      RoutineSessionVerdict.completed,
      RoutineSessionVerdict.abandoned,
      RoutineSessionVerdict.partial,
      RoutineSessionVerdict.completed,
    ]);
    expect(h.gradedCount, 4);
    expect(h.completedCount, 2);
    expect(h.completedRate, 0.5);
  });

  test('an ungraded session is excluded from the rate denominator, not counted as a miss',
      () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-01T10:00:00.000Z',
          metadata: {'gym_adherence': 'completed'}),
      row('b', '2026-08-02T10:00:00.000Z', metadata: {'routine_id': 'r1'}),
    ], now);
    expect(h.sessionCount, 2);
    expect(h.gradedCount, 1);
    expect(h.completedRate, 1);
  });

  test('an unrecognised verdict string is ungraded rather than trusted', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-01T10:00:00.000Z',
          metadata: {'gym_adherence': 'crushed_it'}),
    ], now);
    expect(h.sessions[0].verdict, RoutineSessionVerdict.ungraded);
    expect(h.gradedCount, 0);
  });

  test('a null or non-object metadata bag degrades to ungraded', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-01T10:00:00.000Z', metadata: null),
      row('b', '2026-08-02T10:00:00.000Z', metadata: 'nonsense'),
      const RoutineSessionRow(id: 'c', startedAt: '2026-08-03T10:00:00.000Z'),
    ], now);
    expect(h.sessionCount, 3);
    expect(h.gradedCount, 0);
  });

  test('days since last is whole elapsed days, floored', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-12T23:00:00.000Z'),
    ], now);
    expect(h.daysSinceLast, 2);
  });

  test('a session stamped ahead of the clock reads as today, never negative',
      () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-20T10:00:00.000Z'),
    ], now);
    expect(h.daysSinceLast, 0);
  });

  test('an unparseable start time is dropped rather than sorted as NaN', () {
    final h = summariseRoutineHistory([
      row('bad', 'not-a-date'),
      row('good', '2026-08-10T10:00:00.000Z'),
    ], now);
    expect(h.sessionCount, 1);
    expect(h.sessions[0].id, 'good');
  });

  test('a row with no id is dropped rather than rendered as an unlinkable session',
      () {
    final h = summariseRoutineHistory([
      const RoutineSessionRow(id: '', startedAt: '2026-08-10T10:00:00.000Z'),
    ], now);
    expect(h.sessionCount, 0);
  });

  test('the workout title rides along for the session list', () {
    final h = summariseRoutineHistory([
      row('a', '2026-08-10T10:00:00.000Z', title: 'Push day A'),
    ], now);
    expect(h.sessions[0].title, 'Push day A');
  });
}
