import 'package:flutter_test/flutter_test.dart';
import '../lib/relink_candidates.dart';

RelinkCandidateRun _run(
  String id,
  String startedAt, {
  double distanceM = 5000,
  int durationS = 1800,
}) {
  return RelinkCandidateRun(
    id: id,
    startedAt: DateTime.parse(startedAt),
    distanceM: distanceM,
    durationS: durationS,
  );
}

DateTime _date(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

void main() {
  test('returns in-window runs newest-first', () {
    final out = filterRelinkCandidates(
      runs: [
        _run('a', '2026-04-05T07:00:00Z'),
        _run('b', '2026-04-07T07:00:00Z'),
        _run('c', '2026-04-03T07:00:00Z'),
      ],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
    );
    expect(out.map((r) => r.id).toList(), ['b', 'a', 'c']);
  });

  test('excludes runs outside the ±window', () {
    final out = filterRelinkCandidates(
      runs: [
        _run('near', '2026-04-06T07:00:00Z'),
        _run('far', '2026-04-20T07:00:00Z'),
      ],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
      windowDays: 7,
    );
    expect(out.map((r) => r.id).toList(), ['near']);
  });

  test('boundary day is in-window (inclusive)', () {
    final out = filterRelinkCandidates(
      runs: [_run('edge', '2026-04-12T07:00:00Z')],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
      windowDays: 7,
    );
    expect(out.map((r) => r.id).toList(), ['edge']);
  });

  test('one day past the boundary is excluded', () {
    final out = filterRelinkCandidates(
      runs: [_run('past', '2026-04-13T07:00:00Z')],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
      windowDays: 7,
    );
    expect(out, isEmpty);
  });

  test('excludes a run already linked to another workout (double-count guard)',
      () {
    final out = filterRelinkCandidates(
      runs: [
        _run('linked-elsewhere', '2026-04-05T07:00:00Z'),
        _run('free', '2026-04-05T08:00:00Z'),
      ],
      linkedRunIds: const ['linked-elsewhere'],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
    );
    expect(out.map((r) => r.id).toList(), ['free']);
  });

  test("keeps the workout's OWN current run selectable even though it is linked",
      () {
    final out = filterRelinkCandidates(
      runs: [
        _run('current', '2026-04-05T07:00:00Z'),
        _run('other-linked', '2026-04-05T08:00:00Z'),
      ],
      linkedRunIds: const ['current', 'other-linked'],
      currentRunId: 'current',
      scheduledDate: _date('2026-04-05'),
    );
    expect(out.map((r) => r.id).toList(), ['current']);
  });

  test('the current run stays visible even when out of window', () {
    final out = filterRelinkCandidates(
      runs: [_run('current-far', '2026-05-01T07:00:00Z')],
      linkedRunIds: const ['current-far'],
      currentRunId: 'current-far',
      scheduledDate: _date('2026-04-05'),
      windowDays: 7,
    );
    expect(out.map((r) => r.id).toList(), ['current-far']);
  });

  test('empty runs yields empty', () {
    final out = filterRelinkCandidates(
      runs: const [],
      linkedRunIds: const ['x'],
      currentRunId: 'x',
      scheduledDate: _date('2026-04-05'),
    );
    expect(out, isEmpty);
  });

  test('default window is 7 days', () {
    expect(kDefaultRelinkWindowDays, 7);
    final out = filterRelinkCandidates(
      runs: [
        _run('d8', '2026-04-13T07:00:00Z'),
        _run('d7', '2026-04-12T07:00:00Z'),
      ],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2026-04-05'),
    );
    expect(out.map((r) => r.id).toList(), ['d7']);
  });
}
