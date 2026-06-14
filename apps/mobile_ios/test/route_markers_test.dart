import 'package:flutter_test/flutter_test.dart';
import '../lib/route_markers.dart';

class _M implements MarkerLike {
  @override
  final double? positionM;
  @override
  final DateTime createdAt;
  final String id;
  _M(this.id, this.positionM, String createdAt)
      : createdAt = DateTime.parse(createdAt);
}

void main() {
  test('every kind has a unique key, label key, and hex colour', () {
    final keys = routeMarkerKinds.map((k) => k.kind).toSet();
    expect(keys.length, routeMarkerKinds.length);
    for (final k in routeMarkerKinds) {
      expect(RegExp(r'^#[0-9a-f]{6}$').hasMatch(k.color), isTrue);
      expect(k.labelKey.startsWith('routeMarker.kind.'), isTrue);
    }
  });

  test('only aid_station carries services; only cutoff carries a cutoff', () {
    expect(kindSpec('aid_station').hasServices, isTrue);
    expect(kindSpec('aid_station').hasCutoff, isFalse);
    expect(kindSpec('cutoff').hasCutoff, isTrue);
    expect(kindSpec('cutoff').hasServices, isFalse);
    expect(routeMarkerKinds.where((k) => k.hasServices).length, 1);
    expect(routeMarkerKinds.where((k) => k.hasCutoff).length, 1);
  });

  test('kindSpec falls back to custom for an unknown kind', () {
    expect(kindSpec('gas_station').kind, 'custom');
    expect(kindSpec('aid_station').kind, 'aid_station');
  });

  test('aid services vocabulary is stable', () {
    expect(aidServices, ['water', 'food', 'medical', 'toilets', 'drop_bag']);
  });

  test('sortMarkers orders by position_m, nulls last, stable by created_at', () {
    final markers = [
      _M('c', null, '2026-01-01T00:00:02Z'),
      _M('a', 1500, '2026-01-01T00:00:00Z'),
      _M('d', null, '2026-01-01T00:00:01Z'),
      _M('b', 300, '2026-01-01T00:00:09Z'),
    ];
    expect(sortMarkers(markers).map((m) => m.id).toList(), ['b', 'a', 'd', 'c']);
  });

  test('sortMarkers breaks position ties by created_at and does not mutate input', () {
    final markers = [
      _M('y', 500, '2026-01-01T00:00:05Z'),
      _M('x', 500, '2026-01-01T00:00:01Z'),
    ];
    final sorted = sortMarkers(markers);
    expect(sorted.map((m) => m.id).toList(), ['x', 'y']);
    expect(markers[0].id, 'y'); // original untouched
  });

  test('parseCutoff accepts a valid 24h clock', () {
    expect(parseCutoff({'cutoff_clock': '14:30'}), const CutoffParts(clock: '14:30'));
    expect(parseCutoff({'cutoff_clock': '00:00'}), const CutoffParts(clock: '00:00'));
    expect(parseCutoff({'cutoff_clock': '23:59'}), const CutoffParts(clock: '23:59'));
  });

  test('parseCutoff rejects an invalid clock', () {
    expect(parseCutoff({'cutoff_clock': '24:00'}), isNull);
    expect(parseCutoff({'cutoff_clock': '9:5'}), isNull);
    expect(parseCutoff({'cutoff_clock': 'noon'}), isNull);
  });

  test('parseCutoff accepts a non-negative elapsed and floors it', () {
    expect(parseCutoff({'cutoff_elapsed_s': 3600}), const CutoffParts(elapsedS: 3600));
    expect(parseCutoff({'cutoff_elapsed_s': 90.7}), const CutoffParts(elapsedS: 90));
    expect(parseCutoff({'cutoff_elapsed_s': -5}), isNull);
  });

  test('parseCutoff merges clock + elapsed and returns null for neither', () {
    expect(parseCutoff({'cutoff_clock': '06:00', 'cutoff_elapsed_s': 1800}),
        const CutoffParts(clock: '06:00', elapsedS: 1800));
    expect(parseCutoff({}), isNull);
    expect(parseCutoff(null), isNull);
    expect(parseCutoff('14:30'), isNull);
  });
}
