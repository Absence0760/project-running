// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/track_preview.dart';

/// Issue #666 round 7, S14. `_TrackSparkPainter` on the run screen — the
/// finish card's thumbnail and the following-route card's — carried its own
/// projection that scaled latitude and longitude by one factor, while its
/// sibling `_TrackPreviewPainter` on the routes list projected through
/// `projectTrack` and its `cos(midLat)` correction (`decisions.md § 51`).
/// The same run therefore drew two different shapes depending on which card
/// you looked at.
///
/// These tests compute the distortion rather than restating it, then pin the
/// spark painter to the shared helper so the duplicate can't grow back.

Waypoint _w(double lat, double lng) => Waypoint(lat: lat, lng: lng);

/// A metrically square loop of [sideM] on a side, centred near [lat].
List<Waypoint> _metricSquare(double lat, {double sideM = 100}) {
  const mPerLatDeg = 111320.0;
  final dLat = sideM / mPerLatDeg;
  final dLng = sideM / (mPerLatDeg * math.cos(lat * math.pi / 180));
  return [
    _w(lat, 0),
    _w(lat + dLat, 0),
    _w(lat + dLat, dLng),
    _w(lat, dLng),
    _w(lat, 0),
  ];
}

/// The aspect an *uncorrected* equal-scale projection renders [points] at:
/// raw degree spans, one shared scale, so the ratio is the horizontal
/// stretch the correction removes.
double _uncorrectedAspect(List<Waypoint> points) {
  var minLat = points.first.lat, maxLat = points.first.lat;
  var minLng = points.first.lng, maxLng = points.first.lng;
  for (final p in points) {
    minLat = math.min(minLat, p.lat);
    maxLat = math.max(maxLat, p.lat);
    minLng = math.min(minLng, p.lng);
    maxLng = math.max(maxLng, p.lng);
  }
  return (maxLng - minLng) / (maxLat - minLat);
}

double _projectedAspect(List<Waypoint> points) {
  final projected = projectTrack(points, 240, 100);
  var minX = projected.first.dx, maxX = projected.first.dx;
  var minY = projected.first.dy, maxY = projected.first.dy;
  for (final o in projected) {
    minX = math.min(minX, o.dx);
    maxX = math.max(maxX, o.dx);
    minY = math.min(minY, o.dy);
    maxY = math.max(maxY, o.dy);
  }
  return (maxX - minX) / (maxY - minY);
}

void main() {
  group('the distortion the spark painter used to draw', () {
    test('an uncorrected projection stretches a square loop by 1/cos(lat)', () {
      // Computed, not quoted: the audit claimed 1.61x at 51.5 N and exactly
      // 2.0x at 60 N. Both hold.
      expect(
        _uncorrectedAspect(_metricSquare(51.5)),
        closeTo(1 / math.cos(51.5 * math.pi / 180), 1e-6),
      );
      expect(_uncorrectedAspect(_metricSquare(51.5)), closeTo(1.6064, 1e-3));
      expect(_uncorrectedAspect(_metricSquare(60)), closeTo(2.0, 1e-6));
    });

    test('projectTrack renders the same loop square at both latitudes', () {
      for (final lat in const [51.5, 60.0]) {
        expect(
          _projectedAspect(_metricSquare(lat)),
          closeTo(1.0, 0.02),
          reason: 'a 100 m x 100 m loop at $lat N must render square',
        );
      }
    });

    test('the correction survives the sub-100-px sizes the spark cards use',
        () {
      // The finish card paints at 72x56 logical px with pad 4 — the same
      // call shape `_TrackSparkPainter.paint` now makes.
      final projected = projectTrack(_metricSquare(60), 72, 56, pad: 4);
      var minX = projected.first.dx, maxX = projected.first.dx;
      var minY = projected.first.dy, maxY = projected.first.dy;
      for (final o in projected) {
        minX = math.min(minX, o.dx);
        maxX = math.max(maxX, o.dx);
        minY = math.min(minY, o.dy);
        maxY = math.max(maxY, o.dy);
      }
      expect((maxX - minX) / (maxY - minY), closeTo(1.0, 0.02));
      // And it stays inside the padded box.
      expect(minX, greaterThanOrEqualTo(4 - 1e-9));
      expect(maxX, lessThanOrEqualTo(72 - 4 + 1e-9));
      expect(minY, greaterThanOrEqualTo(4 - 1e-9));
      expect(maxY, lessThanOrEqualTo(56 - 4 + 1e-9));
    });
  });

  group('_TrackSparkPainter delegates to the shared projection', () {
    String sparkPainterSource() {
      final src = File('lib/screens/run_screen.dart').readAsStringSync();
      final start = src.indexOf('class _TrackSparkPainter');
      expect(start, greaterThan(0),
          reason: '_TrackSparkPainter moved — move this guard with it.');
      final end = src.indexOf('\nclass ', start + 1);
      return end == -1 ? src.substring(start) : src.substring(start, end);
    }

    test('it projects through projectTrack', () {
      expect(
        sparkPainterSource()
            .contains('projectTrack(track, size.width, size.height, pad: 4)'),
        isTrue,
        reason: 'The spark painter must reuse projectTrack so the finish '
            'card and the routes list draw one shape for one run.',
      );
    });

    test('it holds no bounding-box scan of its own', () {
      final body = sparkPainterSource();
      for (final marker in const ['maxLng', 'minLng', 'maxLat', 'minLat']) {
        expect(body.contains(marker), isFalse,
            reason: 'A local $marker scan means the cos(midLat) correction '
                'has been duplicated (or dropped) again.');
      }
    });
  });
}
