import 'package:flutter_test/flutter_test.dart';

import '../lib/gear_rotation_pick.dart';
import '../lib/gear_wear.dart';

RotationMember member({
  required String id,
  num? totalDistanceM = 0,
  num? targetDistanceM = 800000,
  String? retiredAt,
  bool isCurrent = false,
}) =>
    RotationMember(
      id: id,
      totalDistanceM: totalDistanceM,
      targetDistanceM: targetDistanceM,
      retiredAt: retiredAt,
      isCurrent: isCurrent,
    );

void main() {
  test('rotationPick: empty rotation picks nothing and claims nothing', () {
    final p = rotationPick([]);
    expect(p.ranked, isEmpty);
    expect(p.pickId, isNull);
    expect(p.pickIsCurrent, false);
    expect(p.allWorn, false);
  });

  test('rotationPick: least-worn pair comes out next', () {
    final p = rotationPick([
      member(id: 'a', totalDistanceM: 600000),
      member(id: 'b', totalDistanceM: 100000),
      member(id: 'c', totalDistanceM: 350000),
    ]);
    expect(p.pickId, 'b');
    expect(p.ranked.map((r) => r.id).toList(), ['b', 'c', 'a']);
    expect(p.allWorn, false);
  });

  test(
      'rotationPick: shares are relative, not absolute — a big-target pair can lead on more km',
      () {
    final p = rotationPick([
      member(id: 'road', totalDistanceM: 300000, targetDistanceM: 500000),
      member(id: 'trail', totalDistanceM: 400000, targetDistanceM: 1000000),
    ]);
    expect(p.pickId, 'trail');
  });

  test('rotationPick: retired gear is dropped, not ranked last', () {
    final p = rotationPick([
      member(id: 'retired', totalDistanceM: 0, retiredAt: '2026-01-01'),
      member(id: 'live', totalDistanceM: 500000),
    ]);
    expect(p.ranked.map((r) => r.id).toList(), ['live']);
    expect(p.pickId, 'live');
  });

  test('rotationPick: an all-retired rotation picks nothing', () {
    final p = rotationPick([
      member(id: 'a', retiredAt: '2026-01-01'),
      member(id: 'b', retiredAt: '2026-02-01'),
    ]);
    expect(p.pickId, isNull);
    expect(p.allWorn, false);
  });

  test('rotationPick: a worn pair sorts behind every unworn pair even on a lower share',
      () {
    // The worn pair carries the LOWER share of the two, because the untracked
    // pair is measured against a reference target far below its mileage.
    // Recommending the worn one anyway would tell the runner to wear a shoe the
    // app itself flags for replacement.
    final p = rotationPick([
      member(id: 'worn', totalDistanceM: 110000, targetDistanceM: 100000),
      member(id: 'untracked', totalDistanceM: 500000, targetDistanceM: null),
    ]);
    expect(p.ranked[0].share, greaterThan(p.ranked[1].share));
    expect(p.ranked[0].id, 'untracked');
    expect(p.ranked[1].status, GearWearStatus.worn);
    expect(p.pickId, 'untracked');
  });

  test('rotationPick: a worn pair really does sort last', () {
    final p = rotationPick([
      member(id: 'worn', totalDistanceM: 900000),
      member(id: 'due', totalDistanceM: 700000),
      member(id: 'ok', totalDistanceM: 200000),
    ]);
    expect(p.ranked.map((r) => r.id).toList(), ['ok', 'due', 'worn']);
  });

  test('rotationPick: every pair worn is reported, and the pick is still the least-worn',
      () {
    final p = rotationPick([
      member(id: 'a', totalDistanceM: 1200000),
      member(id: 'b', totalDistanceM: 850000),
    ]);
    expect(p.allWorn, true);
    expect(p.pickId, 'b');
  });

  test('rotationPick: an untracked pair is measured against the rotation median, not dropped',
      () {
    final p = rotationPick([
      member(id: 'tracked', totalDistanceM: 400000, targetDistanceM: 800000),
      member(id: 'untracked', totalDistanceM: 100000, targetDistanceM: null),
    ]);
    expect(p.pickId, 'untracked');
    expect(p.ranked.firstWhere((r) => r.id == 'untracked').status,
        GearWearStatus.untracked);
    // 100k against the single tracked target of 800k.
    expect((p.ranked[0].share - 0.125).abs(), lessThan(1e-9));
  });

  test('rotationPick: an untracked pair is never called worn, however far it has run',
      () {
    final p = rotationPick([
      member(id: 'untracked', totalDistanceM: 5000000, targetDistanceM: null),
      member(id: 'tracked', totalDistanceM: 10000, targetDistanceM: 800000),
    ]);
    expect(p.ranked.firstWhere((r) => r.id == 'untracked').status,
        GearWearStatus.untracked);
    expect(p.allWorn, false);
    expect(p.pickId, 'tracked');
  });

  test('rotationPick: with no tracked pair at all the ranking falls back to raw distance',
      () {
    final p = rotationPick([
      member(id: 'a', totalDistanceM: 300000, targetDistanceM: null),
      member(id: 'b', totalDistanceM: 90000, targetDistanceM: null),
    ]);
    expect(p.pickId, 'b');
    expect(p.allWorn, false);
  });

  test('rotationPick: the reference target is the median, so one outlier target cannot swing it',
      () {
    // Medians of [200k, 400k, 5_000k] → 400k. A mean would be ~1_866k and would
    // rank the untracked pair below both tracked ones instead of above them.
    final p = rotationPick([
      member(id: 'short', totalDistanceM: 100000, targetDistanceM: 200000),
      member(id: 'mid', totalDistanceM: 200000, targetDistanceM: 400000),
      member(id: 'long', totalDistanceM: 2500000, targetDistanceM: 5000000),
      member(id: 'untracked', totalDistanceM: 40000, targetDistanceM: null),
    ]);
    expect(p.pickId, 'untracked');
    expect((p.ranked[0].share - 0.1).abs(), lessThan(1e-9));
  });

  test('rotationPick: negative / non-finite distances clamp to zero rather than sorting first by accident',
      () {
    final p = rotationPick([
      member(id: 'bad', totalDistanceM: double.nan),
      member(id: 'worse', totalDistanceM: -50000),
      member(id: 'real', totalDistanceM: 10000),
    ]);
    expect(p.ranked.map((r) => r.id).toList(), ['bad', 'worse', 'real']);
    expect(p.ranked[0].share, 0);
    expect(p.ranked[1].share, 0);
  });

  test('rotationPick: ties break on id so the same rotation never reorders between renders',
      () {
    final first = rotationPick([
      member(id: 'zebra', totalDistanceM: 200000),
      member(id: 'alpha', totalDistanceM: 200000),
    ]);
    final second = rotationPick([
      member(id: 'alpha', totalDistanceM: 200000),
      member(id: 'zebra', totalDistanceM: 200000),
    ]);
    expect(first.pickId, 'alpha');
    expect(first.ranked.map((r) => r.id).toList(),
        second.ranked.map((r) => r.id).toList());
  });

  test('rotationPick: the current pair is reported when it is also the pick', () {
    final p = rotationPick([
      member(id: 'a', totalDistanceM: 100000, isCurrent: true),
      member(id: 'b', totalDistanceM: 400000),
    ]);
    expect(p.pickId, 'a');
    expect(p.pickIsCurrent, true);
  });

  test('rotationPick: the current pair holds no rank advantage', () {
    final p = rotationPick([
      member(id: 'a', totalDistanceM: 400000, isCurrent: true),
      member(id: 'b', totalDistanceM: 100000),
    ]);
    expect(p.pickId, 'b');
    expect(p.pickIsCurrent, false);
    expect(p.ranked.firstWhere((r) => r.id == 'a').isCurrent, true);
  });

  test('rotationPick: ranked.length is the in-service count, so a caller can gate on it',
      () {
    // The affordance renders only when there is a real choice to make. Counting
    // memberships would offer a "wear this next" for a rotation holding one live
    // pair and one retired one; ranked drops the retired member, so it is the
    // count that answers the question.
    final p = rotationPick([
      member(id: 'live', totalDistanceM: 100000),
      member(id: 'retired', totalDistanceM: 0, retiredAt: '2026-01-01'),
    ]);
    expect(p.ranked.length, 1);
    expect(p.pickId, 'live');
  });

  test('rotationPick: a single-member rotation still answers, and answers with that member',
      () {
    final p = rotationPick([member(id: 'only', totalDistanceM: 900000)]);
    expect(p.pickId, 'only');
    expect(p.allWorn, true);
  });
}
