import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

/// Compact static thumbnail of a GPS track. Mirrors
/// `apps/web/src/lib/components/TrackPreview.svelte` so a route saved on
/// the web shows the same shape on the mobile list. No tiles, no
/// interaction — just a polyline with start (green) / end (red) caps and
/// a few directional chevrons so out-and-backs and overlapping loops
/// stay readable at thumbnail scale.
class TrackPreview extends StatelessWidget {
  final List<Waypoint> points;
  final Color color;
  final double aspect;

  const TrackPreview({
    super.key,
    required this.points,
    this.color = const Color(0xFF4F46E5),
    this.aspect = 2.4,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const _Placeholder();
    }
    return CustomPaint(
      painter: _TrackPreviewPainter(points: points, color: color),
      size: Size.infinite,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.map_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _TrackPreviewPainter extends CustomPainter {
  static const double _pad = 4;
  static const int _arrowCount = 4;
  // Stroke widths and marker sizes are expressed in the same "viewBox
  // units" the web SVG uses (short axis = 100), then scaled to the
  // canvas. Keeping the geometry identical means the mobile thumbnail
  // is visually indistinguishable from the web one.
  static const double _viewBoxShort = 100;

  final List<Waypoint> points;
  final Color color;

  _TrackPreviewPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    final aspect = size.width / size.height;
    final vbW = aspect >= 1 ? _viewBoxShort * aspect : _viewBoxShort;
    final vbH = aspect < 1 ? _viewBoxShort / aspect : _viewBoxShort;
    final pxPerVb = size.width / vbW;
    // Projection lives in projectTrack so the cos(midLat) correction can
    // be unit-tested without instantiating a Flutter canvas.
    final projected = [
      for (final o in projectTrack(points, vbW, vbH, pad: _pad))
        Offset(o.dx * pxPerVb, o.dy * pxPerVb),
    ];

    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (int i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }

    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * pxPerVb
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(path, casing);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * pxPerVb
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, line);

    if (projected.length >= 4) {
      for (int i = 1; i <= _arrowCount; i++) {
        final t = i / (_arrowCount + 1);
        final idx = max(1, (projected.length * t).floor());
        if (idx >= projected.length) continue;
        final a = projected[idx - 1];
        final b = projected[idx];
        final angle = atan2(b.dy - a.dy, b.dx - a.dx);
        _drawChevron(canvas, b, angle, pxPerVb);
      }
    }

    final startCap = Paint()..color = const Color(0xFF22C55E);
    final endCap = Paint()..color = const Color(0xFFEF4444);
    final capBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * pxPerVb
      ..color = Colors.white;
    canvas.drawCircle(projected.first, 2.6 * pxPerVb, startCap);
    canvas.drawCircle(projected.first, 2.6 * pxPerVb, capBorder);
    canvas.drawCircle(projected.last, 2.6 * pxPerVb, endCap);
    canvas.drawCircle(projected.last, 2.6 * pxPerVb, capBorder);
  }

  void _drawChevron(Canvas canvas, Offset at, double angle, double pxPerVb) {
    final cos_ = cos(angle);
    final sin_ = sin(angle);
    Offset rot(double x, double y) => Offset(
          at.dx + (x * cos_ - y * sin_) * pxPerVb,
          at.dy + (x * sin_ + y * cos_) * pxPerVb,
        );
    final p = Path()
      ..moveTo(rot(-1.8, -1.8).dx, rot(-1.8, -1.8).dy)
      ..lineTo(rot(1.6, 0).dx, rot(1.6, 0).dy)
      ..lineTo(rot(-1.8, 1.8).dx, rot(-1.8, 1.8).dy)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * pxPerVb
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPreviewPainter old) =>
      old.points != points || old.color != color;
}

/// Project `points` into a `[0, vbW] × [0, vbH]` viewBox with the same
/// `cos(midLat)` longitude correction the painter uses. Pure helper
/// extracted so the projection can be unit-tested without spinning up
/// a Flutter canvas. Mirrors `apps/web/src/lib/components/TrackPreview.svelte`
/// — keep them in lockstep.
@visibleForTesting
List<Offset> projectTrack(List<Waypoint> points, double vbW, double vbH,
    {double pad = 4}) {
  if (points.length < 2) return const [];
  double minLat = points.first.lat, maxLat = points.first.lat;
  double minLng = points.first.lng, maxLng = points.first.lng;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  final midLat = (minLat + maxLat) / 2;
  final lngScale = cos(midLat * pi / 180).abs();
  final dLat = max(maxLat - minLat, 1e-6);
  final dLng = max((maxLng - minLng) * lngScale, 1e-6);
  final scaleX = (vbW - pad * 2) / dLng;
  final scaleY = (vbH - pad * 2) / dLat;
  final scale = min(scaleX, scaleY);
  final offX = pad + ((vbW - pad * 2) - dLng * scale) / 2;
  final offY = pad + ((vbH - pad * 2) - dLat * scale) / 2;
  return [
    for (final p in points)
      Offset(
        offX + (p.lng - minLng) * lngScale * scale,
        offY + (maxLat - p.lat) * scale,
      ),
  ];
}

/// True iff the track's bounding-box diagonal is large enough to be
/// worth drawing at thumbnail scale. Mirrors `isMoving` in
/// `RunTrackPreview.svelte` — catches GPS jitter from a runner standing
/// still without throwing away genuinely tiny laps.
bool isTrackRenderable(List<Waypoint> track) {
  if (track.length < 2) return false;
  double minLat = track.first.lat, maxLat = track.first.lat;
  double minLng = track.first.lng, maxLng = track.first.lng;
  for (final p in track) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  final dLatM = (maxLat - minLat) * 111320;
  final dLngM = (maxLng - minLng) * 111320 * cos(minLat * pi / 180);
  return sqrt(dLatM * dLatM + dLngM * dLngM) > 5;
}
