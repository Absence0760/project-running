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
}
