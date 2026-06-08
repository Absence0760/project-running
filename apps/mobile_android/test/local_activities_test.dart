// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_activities.dart';
import '../lib/local_gym_store.dart';
import '../lib/offline_sync_store.dart';

void main() {
  Run run(String id, DateTime at, {double dist = 5000, int dur = 1500}) => Run(
        id: id,
        startedAt: at,
        duration: Duration(seconds: dur),
        distanceMetres: dist,
        source: RunSource.app,
      );

  StoredGymWorkout lift(
    String id,
    DateTime at, {
    String? title,
    List<Map<String, dynamic>> sets = const [],
  }) =>
      StoredGymWorkout(
        row: {'id': id, 'title': title, 'started_at': at.toIso8601String()},
        sets: sets,
        syncState: SyncState.synced,
      );

  Map<String, dynamic> meal(String id, DateTime at,
          {String name = 'Oats', num cal = 300}) =>
      {
        'id': id,
        'started_at': at.toIso8601String(),
        'item_name': name,
        'calories': cal,
      };

  test('merges all three modalities newest-first with the right summary keys',
      () {
    final now = DateTime(2026, 6, 8, 12);
    final out = buildLocalActivities(
      runs: [run('r1', now.subtract(const Duration(hours: 2)))],
      workouts: [
        lift('l1', now.subtract(const Duration(hours: 1)), title: 'Leg day', sets: [
          {'reps': 5, 'weight_kg': 100},
          {'reps': 5, 'weight_kg': 100},
          {'reps': 5}, // incomplete set: counted, but adds no volume
        ]),
      ],
      foods: [meal('m1', now)],
    );

    // Newest-first across modalities.
    expect(out.map((a) => a.kind).toList(), ['meal', 'lift', 'run']);

    final l = out.firstWhere((a) => a.kind == 'lift');
    expect(l.summary['title'], 'Leg day');
    expect(l.summary['set_count'], 3);
    expect(l.summary['volume_kg'], 1000.0);

    final r = out.firstWhere((a) => a.kind == 'run');
    expect(r.summary['distance_m'], 5000);
    expect(r.summary['duration_s'], 1500);

    final m = out.firstWhere((a) => a.kind == 'meal');
    expect(m.summary['item_name'], 'Oats');
    expect(m.summary['calories'], 300);
  });

  test('drops a workout with no started_at and a meal with an unparseable date',
      () {
    final out = buildLocalActivities(
      runs: const [],
      workouts: [
        StoredGymWorkout(
            row: {'id': 'l1', 'title': 'x'}, // no started_at
            sets: const [],
            syncState: SyncState.synced),
      ],
      foods: [
        {'id': 'm1', 'started_at': 'not-a-date', 'item_name': 'x', 'calories': 1},
      ],
    );
    expect(out, isEmpty);
  });

  test('caps at the limit, keeping the newest', () {
    final base = DateTime(2026, 6, 8, 12);
    final runs = [
      for (var i = 0; i < 250; i++)
        run('r$i', base.subtract(Duration(minutes: i))),
    ];
    final out =
        buildLocalActivities(runs: runs, workouts: const [], foods: const [], limit: 200);
    expect(out.length, 200);
    expect(out.first.id, 'r0'); // r0 is the newest (base)
    expect(out.last.id, 'r199');
  });

  test('per-source cap keeps the global newest across all three modalities', () {
    // Each source is longer than `limit` and interleaved in time, so the
    // bounded-build optimisation (cap each newest-first source at `limit`
    // before merging) must still surface the true global newest — a newer run
    // can't be dropped just because another source also has `limit` entries.
    final base = DateTime(2026, 6, 8, 12);
    DateTime t(int min) => base.subtract(Duration(minutes: min));
    final runs = [for (var i = 0; i < 6; i++) run('r$i', t(i * 6))]; // 0,6,12,...
    final workouts = [for (var i = 0; i < 6; i++) lift('l$i', t(i * 6 + 2))]; // 2,8,...
    final foods = [for (var i = 0; i < 6; i++) meal('m$i', t(i * 6 + 4))]; // 4,10,...

    final out = buildLocalActivities(
        runs: runs, workouts: workouts, foods: foods, limit: 4);
    expect(out.length, 4);
    // Newest four by time: r0(0) < l0(2) < m0(4) < r1(6).
    expect(out.map((a) => a.id).toList(), ['r0', 'l0', 'm0', 'r1']);
    expect(out.map((a) => a.kind).toList(), ['run', 'lift', 'meal', 'run']);
  });
}
