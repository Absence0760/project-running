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

  // A window that straddles a DST transition (spring-forward 2024-03-10): the
  // run on 03-04 is exactly 8 calendar days before a workout scheduled 03-12,
  // so it is OUT of a ±7-day window. UTC-anchoring the day gap keeps this exact;
  // the previous local-midnight span drifted to 7 d 23 h, which Duration.inDays
  // truncated to 7 (wrongly INCLUDING it). Mirrors web's DST relink test.
  test('DST-straddling window counts exact calendar days (8 d excluded at 7)', () {
    final out = filterRelinkCandidates(
      runs: [
        _run('dst-edge', '2024-03-04T12:00:00Z'),
        _run('inside', '2024-03-06T12:00:00Z'),
      ],
      linkedRunIds: const [],
      currentRunId: null,
      scheduledDate: _date('2024-03-12'),
    );
    expect(out.map((r) => r.id).toList(), ['inside']);
  });

  // decisions § 1241: the tie is broken on `id`, not left to whatever the fetch
  // returned. Both tests below are the same case at the two sizes that matter —
  // the second is past `List.sort`'s 33-element insertion-sort threshold, where
  // it reorders equal elements on every run.
  test('two runs at the identical instant order by id, not by fetch order', () {
    List<String> order(List<RelinkCandidateRun> runs) => filterRelinkCandidates(
          runs: runs,
          linkedRunIds: const [],
          currentRunId: null,
          scheduledDate: _date('2026-04-05'),
        ).map((r) => r.id).toList();

    expect(
      order([
        _run('b', '2026-04-05T07:00:00Z'),
        _run('a', '2026-04-05T07:00:00Z'),
      ]),
      ['a', 'b'],
    );
    expect(
      order([
        _run('a', '2026-04-05T07:00:00Z'),
        _run('b', '2026-04-05T07:00:00Z'),
      ]),
      ['a', 'b'],
    );
  });

  test('a 40-run all-tied list is ordered by id regardless of fetch order', () {
    final ids = [
      for (var i = 0; i < 40; i++) 'run-${i.toString().padLeft(2, '0')}',
    ];
    final runs = [for (final id in ids) _run(id, '2026-04-05T07:00:00Z')];
    List<String> order(List<RelinkCandidateRun> input) =>
        filterRelinkCandidates(
          runs: input,
          linkedRunIds: const [],
          currentRunId: null,
          scheduledDate: _date('2026-04-05'),
        ).map((r) => r.id).toList();

    expect(order(runs), ids);
    expect(order(runs.reversed.toList()), ids);
  });
}
