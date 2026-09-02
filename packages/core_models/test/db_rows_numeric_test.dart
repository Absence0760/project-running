import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

Map<String, dynamic> _segment({Object? distanceM, Object? elevationM}) =>
    <String, dynamic>{
      'id': 'seg-1',
      'name': 'Col du Galibier',
      'waypoints': <Map<String, dynamic>>[],
      'distance_m': distanceM,
      'elevation_m': elevationM,
      'surface': 'road',
      'is_active': true,
      'created_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('generated double columns decode the wire shapes Postgres emits', () {
    test('a numeric NaN arrives as a JSON string and does not throw', () {
      // Measured against the local stack: `json_agg` — the shape PostgREST
      // builds its response body with — renders `'NaN'::numeric` as `"NaN"`,
      // and `global_segments_distance_m_check` admits NaN because
      // `'NaN'::numeric >= 100` is true.
      final row = GlobalSegmentRow.fromJson(
        _segment(distanceM: 'NaN', elevationM: 'NaN'),
      );
      expect(row.distanceM.isNaN, isTrue);
      expect(row.elevationM, isNull);
    });

    test('a numeric Infinity arrives as a JSON string and does not throw', () {
      final row = GlobalSegmentRow.fromJson(
        _segment(distanceM: 'Infinity', elevationM: '-Infinity'),
      );
      expect(row.distanceM.isFinite, isFalse);
      expect(row.elevationM, isNull);
    });

    test('a numeric handed over as a decimal string parses', () {
      final row = GlobalSegmentRow.fromJson(
        _segment(distanceM: '1234.5', elevationM: '42'),
      );
      expect(row.distanceM, 1234.5);
      expect(row.elevationM, 42.0);
    });

    test('a plain JSON number still decodes, int included', () {
      final row = GlobalSegmentRow.fromJson(
        _segment(distanceM: 1234.5, elevationM: 42),
      );
      expect(row.distanceM, 1234.5);
      expect(row.elevationM, 42.0);
    });

    test('an unusable value is no number, never zero', () {
      final row = GlobalSegmentRow.fromJson(
        _segment(distanceM: 'not a number', elevationM: <String, dynamic>{}),
      );
      expect(row.distanceM.isNaN, isTrue);
      expect(row.elevationM, isNull);
    });

    test('an absent nullable column stays null and an absent required one '
        'is no number rather than a crash', () {
      final row = GlobalSegmentRow.fromJson(_segment());
      expect(row.distanceM.isNaN, isTrue);
      expect(row.elevationM, isNull);
    });
  });

  test('no generated double column reads through a bare `as num` cast', () {
    final source = File(
      'lib/src/generated/db_rows.dart',
    ).readAsStringSync();
    expect(source.contains('as num).toDouble()'), isFalse);
    expect(source.contains('as num?)?.toDouble()'), isFalse);
    expect(source.contains('double _toDouble(Object? value)'), isTrue);
  });
}
