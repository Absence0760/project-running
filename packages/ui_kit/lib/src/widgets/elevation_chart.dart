import 'package:flutter/material.dart';

/// Post-run elevation and pace chart.
class ElevationChart extends StatelessWidget {
  final List<double> elevations;

  const ElevationChart({super.key, this.elevations = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (elevations.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('No elevation data', style: theme.textTheme.bodySmall),
        ),
      );
    }
    return SizedBox(
      height: 120,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ElevationPainter(
          elevations: elevations,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> elevations;
  final Color color;

  _ElevationPainter({required this.elevations, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.isEmpty) return;
    final minElev = elevations.reduce((a, b) => a < b ? a : b);
    final maxElev = elevations.reduce((a, b) => a > b ? a : b);
    final range = maxElev - minElev;
    if (range == 0) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final linePath = Path();
    final stepX = size.width / (elevations.length - 1);

    for (var i = 0; i < elevations.length; i++) {
      final x = i * stepX;
      final y = size.height - ((elevations[i] - minElev) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, size.height);
        path.lineTo(x, y);
        linePath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        linePath.lineTo(x, y);
      }
    }
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) =>
      oldDelegate.elevations != elevations;
}
