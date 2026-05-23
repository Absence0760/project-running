import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../route_simplify.dart' show simplifyTrack;

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

  /// Module-level guard so the diagnostic log fires only once per
  /// process lifetime — a list of 20 thumbnails shouldn't print
  /// 20 identical lines on scroll.
  static bool _loggedKeyState = false;

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
    final mapTilerKey = dotenv.env['MAPTILER_KEY'] ?? '';
    // ONE-TIME diagnostic so the user can confirm which branch
    // ran when they see "thumbnails aren't loading the map." The
    // log says either:
    //   "TrackPreview build: points=N, mapTilerKey=set" →
    //       _StaticMapPreview mounted; check Image.network logs.
    //   "TrackPreview build: points=N, mapTilerKey=EMPTY" →
    //       env var didn't reach this build context; rebuild OR
    //       set MAPTILER_KEY in .env.local + asset bundle.
    // Static printed-once guard so a 20-thumbnail list doesn't
    // spam the log on every scroll.
    if (!_loggedKeyState) {
      _loggedKeyState = true;
      debugPrint(
        'TrackPreview build: points=${points.length}, '
        'mapTilerKey=${mapTilerKey.isEmpty ? "EMPTY" : "set"}',
      );
    }
    if (mapTilerKey.isEmpty) {
      // Fallback for builds without a MapTiler key configured —
      // polyline-only render but with a subtle slate background
      // (not pure white) so the thumbnail still reads as a map
      // surface. Without this paint, dev / offline builds showed
      // pure white cards which the user flagged as "the preview
      // doesn't show a map background."
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: const Color(0xFF1F2937), // slate-800, subtle terrain tint
          child: CustomPaint(
            painter: _TrackPreviewPainter(points: points, color: color),
            size: Size.infinite,
          ),
        ),
      );
    }
    // Map-backed preview via MapTiler's Static Maps API. We hit a
    // SINGLE PNG endpoint that bakes basemap + path-overlay into
    // one image, then render it with `Image.network` + Flutter's
    // built-in image cache. Pre-fix, the thumbnails mounted a
    // full `FlutterMap` at 72×40 — `flutter_map` has known
    // rendering quirks at sub-100-px sizes (tiles either don't
    // load or load partially-cropped). The static-image path is
    // bulletproof at any size and matches the visual the user
    // sees on the route detail screen, just baked at request
    // time instead of composed client-side.
    return _StaticMapPreview(
      points: points,
      color: color,
      mapTilerKey: mapTilerKey,
    );
  }
}

/// Static-image track preview — hits MapTiler's Static Maps API
/// for a single PNG (basemap + path overlay baked together) and
/// renders via `Image.network`. Used by [TrackPreview] when
/// `MAPTILER_KEY` is set.
///
/// Why static-image vs interactive FlutterMap: the user reported
/// "the route detail map works but the list thumbnails don't."
/// Root cause — `flutter_map` has known rendering quirks at sub-
/// 100-px sizes (the same widget renders fine at 320-px on the
/// route detail screen). MapTiler's Static Maps API bakes the
/// basemap + the path into one PNG, sized exactly to the
/// requested width × height — guaranteed-rendering at any size.
///
/// Falls through to the polyline-only CustomPaint render on a
/// network error so a missing internet connection doesn't blank
/// the thumbnail.
class _StaticMapPreview extends StatelessWidget {
  final List<Waypoint> points;
  final Color color;
  final String mapTilerKey;

  const _StaticMapPreview({
    required this.points,
    required this.color,
    required this.mapTilerKey,
  });

  /// MapTiler's Static Maps URL has a practical length cap around
  /// ~8 KB. For a typical run (1000+ track points × 16 chars per
  /// point) we'd blow past that on the first kilometre. Simplify
  /// the polyline first — Ramer-Douglas-Peucker preserves the
  /// shape but drops noise. 60 points is enough resolution for a
  /// 72-px wide thumbnail (each polyline edge averaging ~1 px).
  static const int _maxPolylinePoints = 60;

  List<Waypoint> _simplifiedPath() {
    if (points.length <= _maxPolylinePoints) return points;
    // Bump epsilon until the count drops below the cap. Starting
    // at 10 m (the recorder's default) and doubling keeps the loop
    // bounded — 6 iterations cover 10 m → 320 m which is enough
    // for any sensible polyline.
    var epsilon = 10.0;
    var simplified = simplifyTrack(points, epsilonMetres: epsilon);
    for (var i = 0; i < 6 && simplified.length > _maxPolylinePoints; i++) {
      epsilon *= 2;
      simplified = simplifyTrack(points, epsilonMetres: epsilon);
    }
    return simplified;
  }

  /// Build the MapTiler Static Maps URL with the polyline path
  /// overlay. `auto` for centre + zoom means MapTiler fits the
  /// path bbox automatically — no client-side projection math
  /// needed (the API computes it server-side).
  ///
  /// Encoding subtlety: MapTiler's path param expects LITERAL pipes
  /// (`|`) and commas (`,`) as part of its syntax. The previous
  /// implementation used `Uri.encodeQueryComponent`, which turns
  /// those into `%7C` / `%2C` — MapTiler's URL parser doesn't
  /// decode them back, so the request 4xx'd and Image.network's
  /// errorBuilder kicked in, falling through to the polyline-only
  /// slate fallback. User-visible failure: "I see the route detail
  /// map but list thumbnails don't load." Only `#` (HTTP fragment
  /// delimiter) needs encoding inside a query string.
  String _buildUrl(int width, int height) {
    final path = _simplifiedPath();
    final stroke = (color.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    // Canonical MapTiler path syntax: `fill:#hex|stroke:#hex|width:N|
    // lng,lat|lng,lat|...`. The `#` becomes `%23` (HTTP fragment
    // delimiter must be encoded in a query string); pipes + commas
    // stay literal because MapTiler\'s path parser uses them as
    // grammar separators and doesn\'t decode percent-encoded forms
    // back. Pre-fix the value was wrapped in `Uri.encodeQueryComponent`
    // which turned every pipe + comma into %7C / %2C → MapTiler
    // 4xx\'d every request.
    //
    // Fill is a fully-transparent hex8 (`#ffffff00`) rather than
    // `none` — MapTiler\'s path syntax doesn\'t recognise `none`, so
    // closed loops (first coord ≈ last coord) get the default black
    // polygon fill and a "hole" appears inside the loop on the
    // thumbnail. Caught by the May 2026 audit on the web twin.
    final pathParam = StringBuffer(
      'fill:%23ffffff00|stroke:%23$stroke|width:3',
    );
    for (final p in path) {
      // lng,lat per the API (MapTiler reverses the typical Leaflet
      // lat,lng order).
      pathParam.write('|${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}');
    }
    return 'https://api.maptiler.com/maps/streets-v2-dark/static/auto/${width}x$height@2x.png'
        '?key=$mapTilerKey'
        '&path=$pathParam'
        '&padding=8';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth.round().clamp(40, 1024)
              : 256;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight.round().clamp(40, 1024)
              : 144;
          final url = _buildUrl(w, h);
          return Image.network(
            url,
            width: w.toDouble(),
            height: h.toDouble(),
            fit: BoxFit.cover,
            // Loading + error fallbacks both fall back to the
            // polyline-only paint so the thumbnail always reads as
            // a route preview — never a blank box.
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _polylineOnlyFallback();
            },
            errorBuilder: (context, error, stack) {
              // Surface the URL + error to the device log so a user
              // who's seeing the polyline-only fallback can paste
              // the URL into a browser to see MapTiler's 4xx body
              // (the most common cause of an opaque "thumbnail
              // doesn't load" failure). Without this, the only
              // signal is the fallback rendering.
              debugPrint(
                'TrackPreview: static-map failed → $error\n  url: $url',
              );
              return _polylineOnlyFallback();
            },
          );
        },
      ),
    );
  }

  Widget _polylineOnlyFallback() {
    return ColoredBox(
      color: const Color(0xFF1F2937),
      child: CustomPaint(
        painter: _TrackPreviewPainter(points: points, color: color),
        size: Size.infinite,
      ),
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
