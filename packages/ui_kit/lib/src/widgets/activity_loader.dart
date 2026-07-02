import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which animated athlete figure the loader shows.
enum ActivityLoaderKind { run, train, fuel }

/// Animated side-profile athlete used as a loading indicator. Flutter twin of
/// the web `ActivityLoader.svelte` — the geometry (viewBox 120x170) and every
/// animation angle are ported 1:1 so the two platforms match.
///
/// [size] is the figure WIDTH; the height is `size * 170 / 120`. [color]
/// defaults to the theme's primary. Honours `disableAnimations` (reduced
/// motion) by painting the static rest pose.
class ActivityLoader extends StatefulWidget {
  final ActivityLoaderKind kind;
  final double size;
  final Color? color;
  final String? label;

  const ActivityLoader({
    super.key,
    required this.kind,
    this.size = 48,
    this.color,
    this.label,
  });

  @override
  State<ActivityLoader> createState() => _ActivityLoaderState();
}

class _ActivityLoaderState extends State<ActivityLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.kind),
  );

  static Duration _durationFor(ActivityLoaderKind kind) => switch (kind) {
        ActivityLoaderKind.run => const Duration(milliseconds: 720),
        ActivityLoaderKind.train => const Duration(milliseconds: 1050),
        ActivityLoaderKind.fuel => const Duration(milliseconds: 1500),
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final width = widget.size;
    final height = widget.size * 170 / 120;
    return Semantics(
      label: widget.label ?? 'Loading',
      liveRegion: true,
      container: true,
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _ActivityLoaderPainter(
              kind: widget.kind,
              t: _controller.value,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

enum _HandStyle { hand, apple, dumbbell }

class _ActivityLoaderPainter extends CustomPainter {
  final ActivityLoaderKind kind;
  final double t;
  final Color color;

  _ActivityLoaderPainter({
    required this.kind,
    required this.t,
    required this.color,
  });

  static const _appleBody = Color(0xFFFF6B5B);
  static const _appleStem = Color(0xFF7C5A3A);
  static const _appleLeaf = Color(0xFF4FB477);
  static const _appleHighlight = Color(0xFFFF8C7E);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 120);
    switch (kind) {
      case ActivityLoaderKind.run:
        _paintRun(canvas);
      case ActivityLoaderKind.train:
        _paintTrain(canvas);
      case ActivityLoaderKind.fuel:
        _paintFuel(canvas);
    }
  }

  // ---- RUN ----
  static const _runThigh = [
    [0.0, -22.0],
    [25.0, 6.0],
    [50.0, 34.0],
    [75.0, -30.0],
    [100.0, -22.0],
  ];
  static const _runShin = [
    [0.0, 16.0],
    [22.0, 5.0],
    [50.0, 14.0],
    [74.0, 112.0],
    [100.0, 16.0],
  ];
  static const _runUpperArm = [
    [0.0, 30.0],
    [50.0, -26.0],
    [100.0, 30.0],
  ];
  static const _runForearm = [
    [0.0, -102.0],
    [50.0, -120.0],
    [100.0, -102.0],
  ];
  static const _runBob = [
    [0.0, 1.0],
    [50.0, -11.0],
    [100.0, 1.0],
  ];

  void _paintRun(Canvas canvas) {
    _drawShadow(canvas, 30);
    final phaseFront = t;
    final phaseBack = (t + 0.5) % 1;

    canvas.save();
    _rotate(canvas, 60, 150, 9); // static lean
    final bob = _interp(_runBob, (t * 2) % 1);
    canvas.translate(0, bob);

    // back leg (delay -d/2)
    _drawLeg(
      canvas,
      thighDeg: _interp(_runThigh, phaseBack, linear: true),
      shinDeg: _interp(_runShin, phaseBack, linear: true),
      shoeX: 57,
      opacity: 0.5,
    );
    // back arm (delay 0)
    _drawArm(
      canvas,
      upperArmDeg: _interp(_runUpperArm, phaseFront),
      forearmDeg: _interp(_runForearm, phaseFront),
      style: _HandStyle.hand,
      opacity: 0.5,
    );
    _drawCore(canvas);
    // front leg (delay 0)
    _drawLeg(
      canvas,
      thighDeg: _interp(_runThigh, phaseFront, linear: true),
      shinDeg: _interp(_runShin, phaseFront, linear: true),
      shoeX: 57,
      opacity: 1,
    );
    // front arm (delay -d/2)
    _drawArm(
      canvas,
      upperArmDeg: _interp(_runUpperArm, phaseBack),
      forearmDeg: _interp(_runForearm, phaseBack),
      style: _HandStyle.hand,
      opacity: 1,
    );
    canvas.restore();
  }

  // ---- TRAIN ----
  static const _trainCurl = [
    [0.0, -12.0],
    [50.0, -150.0],
    [100.0, -12.0],
  ];
  static const _trainEffort = [
    [0.0, 0.0],
    [50.0, -2.0],
    [100.0, 0.0],
  ];

  void _paintTrain(Canvas canvas) {
    _drawShadow(canvas, 26);
    canvas.save();
    canvas.translate(0, _interp(_trainEffort, t));

    _drawLeg(canvas, thighDeg: -6, shinDeg: 4, shoeX: 55, opacity: 0.5);
    _drawArm(
      canvas,
      upperArmDeg: 7,
      forearmDeg: _interp(_trainCurl, (t + 0.5) % 1),
      style: _HandStyle.dumbbell,
      opacity: 0.5,
    );
    _drawCore(canvas);
    _drawLeg(canvas, thighDeg: 5, shinDeg: -4, shoeX: 57, opacity: 1);
    _drawArm(
      canvas,
      upperArmDeg: 7,
      forearmDeg: _interp(_trainCurl, t),
      style: _HandStyle.dumbbell,
      opacity: 1,
    );
    canvas.restore();
  }

  // ---- FUEL ----
  static const _fuelUpperArm = [
    [0.0, -6.0],
    [34.0, -30.0],
    [72.0, -30.0],
    [100.0, -6.0],
  ];
  static const _fuelForearm = [
    [0.0, -18.0],
    [34.0, -150.0],
    [72.0, -150.0],
    [100.0, -18.0],
  ];
  static const _fuelNod = [
    [0.0, 0.0],
    [28.0, 0.0],
    [38.0, 8.0],
    [72.0, 8.0],
    [100.0, 0.0],
  ];

  void _paintFuel(Canvas canvas) {
    _drawShadow(canvas, 26);

    _drawLeg(canvas, thighDeg: -7, shinDeg: 5, shoeX: 55, opacity: 0.5);
    _drawArm(
      canvas,
      upperArmDeg: -3,
      forearmDeg: -12,
      style: _HandStyle.hand,
      opacity: 0.5,
    );
    _drawCore(canvas, nodDeg: _interp(_fuelNod, t));
    _drawLeg(canvas, thighDeg: 6, shinDeg: -5, shoeX: 57, opacity: 1);
    _drawArm(
      canvas,
      upperArmDeg: _interp(_fuelUpperArm, t),
      forearmDeg: _interp(_fuelForearm, t),
      style: _HandStyle.apple,
      opacity: 1,
    );
  }

  // ---- figure parts ----

  void _drawLeg(
    Canvas canvas, {
    required double thighDeg,
    required double shinDeg,
    required double shoeX,
    required double opacity,
  }) {
    final skin = _fill(color.withValues(alpha: opacity));
    final shoe = _fill(
      Color.lerp(color, Colors.black, 0.45)!.withValues(alpha: opacity),
    );
    canvas.save();
    _rotate(canvas, 60, 96, thighDeg);
    canvas.drawRRect(_rr(55.5, 96, 9, 28, 4.5), skin);
    canvas.save();
    _rotate(canvas, 60, 124, shinDeg);
    canvas.drawRRect(_rr(56.25, 124, 7.5, 28, 3.75), skin);
    canvas.drawRRect(_rr(shoeX, 149, 13, 6, 3), shoe);
    canvas.restore();
    canvas.restore();
  }

  void _drawArm(
    Canvas canvas, {
    required double upperArmDeg,
    required double forearmDeg,
    required _HandStyle style,
    required double opacity,
  }) {
    final skin = _fill(color.withValues(alpha: opacity));
    canvas.save();
    _rotate(canvas, 60, 52, upperArmDeg);
    canvas.drawRRect(_rr(56.5, 52, 7, 24, 3.5), skin);
    canvas.save();
    _rotate(canvas, 60, 76, forearmDeg);
    canvas.drawRRect(_rr(56.75, 76, 6.5, 22, 3.25), skin);
    switch (style) {
      case _HandStyle.hand:
        canvas.drawCircle(const Offset(60, 99), 3.6, skin);
      case _HandStyle.apple:
        canvas.drawCircle(const Offset(60, 98), 3.6, skin);
        _drawApple(canvas, upperArmDeg, forearmDeg);
      case _HandStyle.dumbbell:
        final gear = _fill(
          Color.lerp(color, Colors.white, 0.38)!.withValues(alpha: opacity),
        );
        canvas.drawRRect(_rr(52, 96.5, 16, 4.5, 2.2), gear);
        canvas.drawCircle(const Offset(52, 98.7), 4.2, gear);
        canvas.drawCircle(const Offset(68, 98.7), 4.2, gear);
    }
    canvas.restore();
    canvas.restore();
  }

  void _drawCore(Canvas canvas, {double? nodDeg}) {
    final skin = _fill(color);
    canvas.drawRRect(_rr(52, 48, 16, 50, 8), skin);
    canvas.drawRRect(_rr(56.5, 42, 7, 8, 3), skin);
    if (nodDeg != null) {
      canvas.save();
      _rotate(canvas, 60, 44, nodDeg); // pivot = head bottom
      canvas.drawCircle(const Offset(60, 31), 13, skin);
      canvas.restore();
    } else {
      canvas.drawCircle(const Offset(60, 31), 13, skin);
    }
  }

  /// The apple is a child of the eating forearm; counter-rotating by the
  /// negated cumulative arm angle keeps it upright (bite toward the mouth),
  /// reproducing the web's `.apple` counter-rotation exactly.
  void _drawApple(Canvas canvas, double upperArmDeg, double forearmDeg) {
    canvas.save();
    _rotate(canvas, 60, 105, -(upperArmDeg + forearmDeg));
    canvas.drawRRect(_rr(59.2, 98, 1.6, 4, 0.8), _fill(_appleStem));

    canvas.save();
    _rotate(canvas, 64, 99.5, 26);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(64, 99.5), width: 6, height: 3),
      _fill(_appleLeaf),
    );
    canvas.restore();

    final body = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 105), radius: 6.3));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: const Offset(56.1, 99.8), radius: 3.9));
    canvas.drawPath(
      Path.combine(PathOperation.difference, body, bite),
      _fill(_appleBody),
    );

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(62.6, 106.6), width: 3.2, height: 4.4),
      _fill(_appleHighlight.withValues(alpha: 0.7)),
    );
    canvas.restore();
  }

  void _drawShadow(Canvas canvas, double rx) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(60, 162), width: rx * 2, height: 12),
      _fill(color.withValues(alpha: 0.16)),
    );
  }

  // ---- helpers ----

  Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

  void _rotate(Canvas canvas, double px, double py, double deg) {
    canvas
      ..translate(px, py)
      ..rotate(deg * math.pi / 180)
      ..translate(-px, -py);
  }

  double _interp(List<List<double>> stops, double p, {bool linear = false}) {
    for (var i = 0; i < stops.length - 1; i++) {
      final aP = stops[i][0] / 100.0;
      final bP = stops[i + 1][0] / 100.0;
      if (p >= aP && p <= bP) {
        final span = bP - aP;
        final lp = span <= 0 ? 0.0 : (p - aP) / span;
        final e = linear ? lp : _easeInOut(lp);
        return stops[i][1] + (stops[i + 1][1] - stops[i][1]) * e;
      }
    }
    return stops.last[1];
  }

  double _easeInOut(double x) =>
      const Cubic(0.42, 0, 0.58, 1).transform(x.clamp(0.0, 1.0));

  @override
  bool shouldRepaint(_ActivityLoaderPainter old) =>
      old.t != t || old.color != color || old.kind != kind;
}
