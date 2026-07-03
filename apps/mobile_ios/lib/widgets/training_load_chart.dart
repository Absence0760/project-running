import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../training_load.dart';

/// Dashboard "Fitness / Fatigue / Form" chart. Mirrors
/// `apps/web/src/lib/components/TrainingLoadChart.svelte` (decisions §34).
class TrainingLoadChart extends StatelessWidget {
  final List<TrainingLoadPoint> points;
  final bool hasHr;

  /// Honest signal that gym load is folded into these curves — true when any
  /// day in the window carries lift stress, so the trio reflects more than
  /// running (multi_modal.md Tier-1 lift→load).
  final bool includesLifts;

  const TrainingLoadChart({
    super.key,
    required this.points,
    required this.hasHr,
    this.includesLifts = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final last = points.isEmpty ? null : points.last;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.trainingLoadTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              hasHr
                  ? l10n.trainingLoadSubtitleHr(points.length)
                  : l10n.trainingLoadSubtitleVolume,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (includesLifts) ...[
              const SizedBox(height: 4),
              Text(
                l10n.trainingLoadIncludesLifts,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l10n.trainingLoadEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              _Legend(last: last!),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ChartPainter(
                    points: points,
                    axisColor: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDateShort(points.first.date,
                        localeToTag(Localizations.localeOf(context))),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatDateShort(points.last.date,
                        localeToTag(Localizations.localeOf(context))),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _readingFor(l10n, last.tsb),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _readingFor(AppLocalizations l10n, double tsb) {
    if (tsb < -10) return l10n.trainingLoadReadingLoaded;
    if (tsb > 10) return l10n.trainingLoadReadingTapered;
    return l10n.trainingLoadReadingBalanced;
  }
}

class _Legend extends StatelessWidget {
  final TrainingLoadPoint last;
  const _Legend({required this.last});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formColor =
        last.tsb >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _LegendKey(
          color: const Color(0xFF4F46E5),
          label: l10n.trainingLoadLegendFitness,
          value: last.ctl,
        ),
        _LegendKey(
          color: const Color(0xFFF59E0B),
          label: l10n.trainingLoadLegendFatigue,
          value: last.atl,
        ),
        _LegendKey(
            color: formColor,
            label: l10n.trainingLoadLegendForm,
            value: last.tsb),
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  const _LegendKey({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          AppLocalizations.of(context)
              .trainingLoadLegendEntry(label, value.round()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<TrainingLoadPoint> points;
  final Color axisColor;

  static const _fitness = Color(0xFF4F46E5);
  static const _fatigue = Color(0xFFF59E0B);
  static const _form = Color(0xFFEF4444);

  _ChartPainter({required this.points, required this.axisColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padL = 8.0;
    const padR = 4.0;
    const padT = 6.0;
    const padB = 6.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;

    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (final p in points) {
      if (p.atl < minV) minV = p.atl;
      if (p.ctl < minV) minV = p.ctl;
      if (p.tsb < minV) minV = p.tsb;
      if (p.atl > maxV) maxV = p.atl;
      if (p.ctl > maxV) maxV = p.ctl;
      if (p.tsb > maxV) maxV = p.tsb;
    }
    // Always include zero so the TSB sign is visible.
    if (minV > 0) minV = 0;
    if (maxV < 0) maxV = 0;
    var span = maxV - minV;
    if (span < 10) span = 10;
    minV -= span * 0.1;
    maxV += span * 0.1;

    double xAt(int i) {
      if (points.length <= 1) return padL;
      return padL + (i / (points.length - 1)) * plotW;
    }

    double yAt(double v) {
      if (maxV == minV) return padT + plotH / 2;
      return padT + plotH * (1 - (v - minV) / (maxV - minV));
    }

    // Zero line — dashed.
    final zeroPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final zeroY = yAt(0);
    _drawDashedLine(
      canvas,
      Offset(padL, zeroY),
      Offset(size.width - padR, zeroY),
      zeroPaint,
    );

    void drawSeries(double Function(TrainingLoadPoint) get, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final pt = Offset(xAt(i), yAt(get(points[i])));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawSeries((p) => p.ctl, _fitness);
    drawSeries((p) => p.atl, _fatigue);
    drawSeries((p) => p.tsb, _form);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    var x = a.dx;
    var on = true;
    while (x < b.dx) {
      final step = on ? dash : gap;
      final raw = x + step;
      final next = raw > b.dx ? b.dx : raw;
      if (on) canvas.drawLine(Offset(x, a.dy), Offset(next, b.dy), paint);
      x = next;
      on = !on;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      !identical(old.points, points) || old.axisColor != axisColor;
}
