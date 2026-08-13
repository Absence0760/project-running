import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../lib/roadbook.dart';

List<RoadbookWaypoint> course() {
  final pts = <RoadbookWaypoint>[];
  for (var i = 0; i <= 18; i++) {
    final climbing = i > 9;
    final ele = climbing ? (i - 9) * 30.0 : 0.0;
    pts.add(RoadbookWaypoint(lat: i * 0.001, lng: 0, ele: ele));
  }
  return pts;
}

RoadbookMarker marker(double? pos, String kind, String label, [dynamic meta]) =>
    RoadbookMarker(positionM: pos, kind: kind, label: label, meta: meta ?? {});

double half(List<RoadbookWaypoint> wp) =>
    buildRoadbook(wp, const [], goalSeconds: 1, model: PacingModel.even)
            .totalDistM /
        2;

void main() {
  test('legs run start -> markers (ordered) -> finish', () {
    final wp = course();
    final rb = buildRoadbook(
      wp,
      [marker(1500, 'aid_station', 'Aid 2'), marker(500, 'aid_station', 'Aid 1')],
      goalSeconds: 3600,
      model: PacingModel.even,
    );
    expect(rb.legs.length, 4);
    expect(rb.legs[0].isStart, isTrue);
    expect(rb.legs[1].label, 'Aid 1');
    expect(rb.legs[2].label, 'Aid 2');
    expect(rb.legs[3].isFinish, isTrue);
    expect(rb.legs[1].cumDistM < rb.legs[2].cumDistM, isTrue);
    expect(rb.legs[3].cumDistM, rb.totalDistM);
  });

  test('even model splits goal time proportional to distance', () {
    final wp = course();
    final rb = buildRoadbook(wp, [marker(half(wp), 'aid_station', 'Mid')],
        goalSeconds: 4000, model: PacingModel.even);
    expect((rb.legs[1].projectedElapsedS - 2000).abs() < 50, isTrue);
    expect(rb.legs[2].projectedElapsedS.round(), 4000);
  });

  test('effort model gives the climb leg more time than even pace', () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 3600, model: PacingModel.even)
            .totalDistM;
    final mid = total / 2;
    final even = buildRoadbook(wp, [marker(mid, 'aid_station', 'Mid')],
        goalSeconds: 3600, model: PacingModel.even);
    final effort = buildRoadbook(wp, [marker(mid, 'aid_station', 'Mid')],
        goalSeconds: 3600, model: PacingModel.effort);
    expect(
        effort.legs[1].projectedElapsedS < even.legs[1].projectedElapsedS,
        isTrue);
    expect(effort.legs[2].projectedElapsedS.round(), 3600);
  });

  test('effort degrades to even when there is no elevation', () {
    final flat = List.generate(11, (i) => RoadbookWaypoint(lat: i * 0.001, lng: 0));
    final mid = half(flat);
    final even = buildRoadbook(flat, [marker(mid, 'aid_station', 'Mid')],
        goalSeconds: 3600, model: PacingModel.even);
    final effort = buildRoadbook(flat, [marker(mid, 'aid_station', 'Mid')],
        goalSeconds: 3600, model: PacingModel.effort);
    expect(effort.hasElevation, isFalse);
    expect(effort.legs[1].projectedElapsedS.round(),
        even.legs[1].projectedElapsedS.round());
  });

  test('cutoff from cutoff_elapsed_s yields a margin and status', () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 3600, model: PacingModel.even)
            .totalDistM;
    final rb = buildRoadbook(
        wp, [marker(total / 2, 'cutoff', 'Gate', {'cutoff_elapsed_s': 2000})],
        goalSeconds: 3600, model: PacingModel.even);
    final gate = rb.legs[1];
    expect(gate.cutoff, isNotNull);
    expect(gate.cutoff!.limitElapsedS, 2000);
    expect(gate.cutoff!.marginS > 0 && gate.cutoff!.marginS < 30 * 60, isTrue);
    expect(gate.cutoff!.status, CutoffStatus.tight);
  });

  test('a too-slow goal turns a cutoff red (miss)', () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 3600, model: PacingModel.even)
            .totalDistM;
    final rb = buildRoadbook(
        wp, [marker(total / 2, 'cutoff', 'Gate', {'cutoff_elapsed_s': 600})],
        goalSeconds: 7200, model: PacingModel.even);
    expect(rb.legs[1].cutoff!.status, CutoffStatus.miss);
    expect(rb.legs[1].cutoff!.marginS < 0, isTrue);
  });

  test('cutoff from cutoff_clock needs a start clock', () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 3600, model: PacingModel.even)
            .totalDistM;
    final rb = buildRoadbook(
        wp, [marker(total / 2, 'cutoff', 'Gate', {'cutoff_clock': '06:45'})],
        goalSeconds: 3600, startClockMin: 360, model: PacingModel.even);
    expect(rb.legs[1].cutoff!.limitElapsedS, 2700);
    final noStart = buildRoadbook(
        wp, [marker(total / 2, 'cutoff', 'Gate', {'cutoff_clock': '06:45'})],
        goalSeconds: 3600, model: PacingModel.even);
    expect(noStart.legs[1].cutoff, isNull);
  });

  test('cutoff_clock equal to the start clock resolves to a 24h limit, not 0s',
      () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 3600, model: PacingModel.even)
            .totalDistM;
    // Start 06:00, overall cutoff expressed as the same wall clock one day on
    // ('06:00') must be 86400 s, not a 0-second window that misses every
    // runner from the gun.
    final rb = buildRoadbook(
        wp, [marker(total / 2, 'cutoff', 'Gate', {'cutoff_clock': '06:00'})],
        goalSeconds: 3600, startClockMin: 360, model: PacingModel.even);
    expect(rb.legs[1].cutoff!.limitElapsedS, 86400);
    expect(rb.legs[1].cutoff!.status, CutoffStatus.safe);
  });

  test('cutoff_clock resolves from the start alone, never from the projection',
      () {
    final wp = course();
    final total =
        buildRoadbook(wp, const [], goalSeconds: 1, model: PacingModel.even)
            .totalDistM;
    // Start 08:00, cutoff clock 14:00 -> the limit is hour 6, whoever is
    // running and however slowly. Snapping the day to the nearest projection
    // made the limit move with the goal time: a 40h goal put the projected
    // arrival at hour 30, which pulled the limit out to 14:00 the NEXT day and
    // reported a 24h-blown cutoff as merely tight.
    final limits = [4 * 3600, 10 * 3600, 40 * 3600, 100 * 3600]
        .map((goalSeconds) => buildRoadbook(wp,
                [marker(total * 0.75, 'cutoff', 'Gate', {'cutoff_clock': '14:00'})],
                goalSeconds: goalSeconds.toDouble(),
                startClockMin: 480,
                model: PacingModel.even)
            .legs[1]
            .cutoff!
            .limitElapsedS)
        .toList();
    expect(limits, [21600, 21600, 21600, 21600]);

    // And the blown cutoff reads as blown: 40h goal -> arrival ~hour 30
    // against an hour-6 limit.
    final slow = buildRoadbook(
        wp, [marker(total * 0.75, 'cutoff', 'Gate', {'cutoff_clock': '14:00'})],
        goalSeconds: 40 * 3600, startClockMin: 480, model: PacingModel.even);
    expect(slow.legs[1].cutoff!.status, CutoffStatus.miss);
    expect(slow.legs[1].cutoff!.marginS < -20 * 3600, isTrue);
  });

  test('projected clock advances from the start and wraps past midnight', () {
    final wp = course();
    final rb = buildRoadbook(wp, const [],
        goalSeconds: 3600, startClockMin: 23 * 60 + 30, model: PacingModel.even);
    expect(rb.legs[1].projectedClockMin!.round(), 30);
  });

  test('markers with null positionM are dropped from the schedule', () {
    final wp = course();
    final rb = buildRoadbook(
      wp,
      [marker(null, 'aid_station', 'Floating'), marker(500, 'aid_station', 'Real')],
      goalSeconds: 3600,
      model: PacingModel.even,
    );
    expect(rb.legs.length, 3);
    expect(rb.legs[1].label, 'Real');
  });

  test('aid services flow through to the leg', () {
    final wp = course();
    final rb = buildRoadbook(
      wp,
      [marker(500, 'aid_station', 'Aid', {'services': ['water', 'food']})],
      goalSeconds: 3600,
      model: PacingModel.even,
    );
    expect(rb.legs[1].services, ['water', 'food']);
  });

  test('effort allocation survives a densely-sampled course', () {
    // Every point-pair is under minSegmentM here, so grading each pair on its
    // own read the whole climb as flat and effort collapsed onto even pace.
    final dense = climbCourse(3);
    final effort = midArrivalS(dense, PacingModel.effort);
    final even = midArrivalS(dense, PacingModel.even);
    expect(effort > even * 1.4, isTrue, reason: 'effort $effort vs even $even');
  });

  test('effort allocation is a property of the terrain, not the sampling density',
      () {
    final coarse = midArrivalS(climbCourse(20), PacingModel.effort);
    for (final spacing in [10.0, 3.0, 1.0]) {
      final dense = midArrivalS(climbCourse(spacing), PacingModel.effort);
      expect((dense - coarse).abs() / coarse < 0.01, isTrue,
          reason: 'spacing ${spacing}m gave ${dense}s vs ${coarse}s at 20m');
    }
  });

  test('a trailing sub-threshold segment is graded flat, not amplified', () {
    // 1 km of flat at 20 m spacing, then one last point 3 m on with a 1 m rise:
    // a 33 % grade no altimeter can support over 3 m. That trailing window never
    // clears minSegmentM, so it must stay flat — grading it on its own span
    // would bill it as ~3.9x effort and pull every arrival before it earlier.
    final wp = <RoadbookWaypoint>[];
    for (var d = 0.0; d <= 1000; d += 20) {
      wp.add(RoadbookWaypoint(lat: 45 + d / 111320, lng: 7, ele: 0));
    }
    wp.add(RoadbookWaypoint(lat: 45 + 1003 / 111320, lng: 7, ele: 1));
    final mid = [marker(500, 'aid_station', 'Mid')];
    final effort =
        buildRoadbook(wp, mid, goalSeconds: 5400, model: PacingModel.effort);
    final even =
        buildRoadbook(wp, mid, goalSeconds: 5400, model: PacingModel.even);
    expect(effort.hasElevation, isTrue,
        reason: 'the effort model must actually be in play');
    expect(
      (effort.legs[1].projectedElapsedS - even.legs[1].projectedElapsedS).abs() <
          1e-6,
      isTrue,
      reason: 'effort ${effort.legs[1].projectedElapsedS} vs even '
          '${even.legs[1].projectedElapsedS}',
    );
  });
}

// A 4 km 25 % climb then 4 km flat, sampled every [spacingM] metres. The
// terrain is fixed; only the file's point density changes.
List<RoadbookWaypoint> climbCourse(double spacingM) {
  final pts = <RoadbookWaypoint>[];
  const mPerDegLat = 111320.0;
  const climbM = 4000.0;
  for (var d = 0.0; d <= climbM * 2; d += spacingM) {
    pts.add(RoadbookWaypoint(
        lat: 45 + d / mPerDegLat, lng: 7, ele: math.min(d, climbM) * 0.25));
  }
  return pts;
}

double midArrivalS(List<RoadbookWaypoint> wp, PacingModel model) {
  final rb = buildRoadbook(wp, [marker(4000, 'aid_station', 'Top')],
      goalSeconds: 5400, model: model);
  return rb.legs[1].projectedElapsedS;
}
