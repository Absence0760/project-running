import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

Waypoint _wp(double lat, double lng, {double? ele}) =>
    Waypoint(lat: lat, lng: lng, elevationMetres: ele);

Run _run(List<Waypoint> track, {double distance = 5000}) => Run(
      id: 'run-1',
      startedAt: DateTime.utc(2026, 1, 1),
      duration: const Duration(minutes: 30),
      distanceMetres: distance,
      track: track,
      source: RunSource.app,
    );

void main() {
  group('finiteWaypoints', () {
    test('a clean track is returned unchanged, not rebuilt', () {
      final track = [_wp(1, 2), _wp(3, 4, ele: 10)];
      expect(identical(finiteWaypoints(track), track), isTrue);
    });

    test('a point that is not a location is dropped', () {
      final track = [
        _wp(1, 2),
        _wp(double.nan, 4),
        _wp(5, double.infinity),
        _wp(-double.infinity, -double.infinity),
        _wp(7, 8),
      ];
      final out = finiteWaypoints(track);
      expect(out.length, 2);
      expect(out.first.lat, 1);
      expect(out.last.lat, 7);
    });

    test('a non-finite elevation drops to null and keeps the location', () {
      final out = finiteWaypoints([_wp(1, 2, ele: double.nan)]);
      expect(out.length, 1);
      expect(out.single.lat, 1);
      expect(out.single.elevationMetres, isNull);
    });
  });

  group('a run is always encodable', () {
    test('a non-finite waypoint no longer makes the run unsaveable', () {
      final run = _run([_wp(1, 2), _wp(double.nan, 4)]);
      final encoded = jsonEncode(run.toJson());
      expect(encoded, isNot(contains('NaN')));
      final back = Run.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(back.track.length, 1);
      expect(back.track.single.lat, 1);
    });

    test('a non-finite distance no longer makes the run unsaveable', () {
      final run = _run([_wp(1, 2)], distance: double.nan);
      final back = Run.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(back.distanceMetres, 0.0);
    });

    test('a clean run round-trips unchanged', () {
      final run = _run([_wp(1, 2, ele: 10), _wp(3, 4)]);
      final back = Run.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(back.track.length, 2);
      expect(back.track.first.elevationMetres, 10);
      expect(back.distanceMetres, 5000);
    });

    test('the failure this replaces was an Error, not an Exception', () {
      // `on Exception` never saw it, so every caller that classified failures
      // by type read a permanent refusal as a transient one.
      expect(
        () => jsonEncode(<Object>[double.nan]),
        throwsA(
          allOf(isA<Error>(), isA<JsonUnsupportedObjectError>()),
        ),
      );
    });
  });
}
