import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../mileage_trend.dart';
import '../preferences.dart';

/// Dashboard "Mileage" card — bar chart of total distance per week,
/// month, or year over the most-recent 12 buckets. Mirrors the
/// segmented mileage chart on web's `/dashboard`. Stateful so the
/// week / month / year toggle persists across rebuilds within the
/// same dashboard mount.
///
/// Self-hides when there are no runs. The bar height encodes
/// distance relative to the tallest bucket in the window; the
/// numeric label below each bar honours the user's distance unit.
class MileageTrendCard extends StatefulWidget {
  final List<Run> runs;
  final DistanceUnit unit;
  final DateTime now;

  const MileageTrendCard({
    super.key,
    required this.runs,
    required this.unit,
    required this.now,
  });

  @override
  State<MileageTrendCard> createState() => _MileageTrendCardState();
}

class _MileageTrendCardState extends State<MileageTrendCard> {
  MileageView _view = MileageView.weekly;

  @override
  Widget build(BuildContext context) {
    // No early return on empty runs anymore — user request:
    // "ensure if there is little to no data a minimum of 3
    // weeks, 3 months, and 3 years are shown." Empty input now
    // back-fills 3 empty buckets so the chart frame still
    // renders. Yearly view keeps its 5-year minimum via
    // padYearlyToMin so the prior-years context isn't lost.
    final periods = aggregateMileage(
      widget.runs,
      view: _view,
      now: widget.now,
      minBuckets: 3,
      padYearlyToMin: true,
      localeTag: localeToTag(Localizations.localeOf(context)),
    );
    if (periods.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final maxDistance = periods
        .map((p) => p.distanceM)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final latest = periods.last;
    final latestLabel = _latestLabel(l10n, _view);

    return Card(
      // Never name a horizontal margin here: the dashboard ListView already
      // supplies the 16 px gutter, and an explicit `fromLTRB(16, 8, 16, 8)`
      // doubled it — field report: "the Mileage modal looks less wide
      // (thinner) than the other modals on the dashboard."
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChartCardHeader(
              title: l10n.mileageTitle,
              action: _ViewToggle(
                view: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
            // Spotlight headline — the most-recent bucket's value
            // surfaced once at the top so the bars can drop their
            // per-bar numeric labels (those overflow into next-line
            // wraps on the narrow weekly view + look cramped on the
            // wider yearly view).
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  UnitFormat.distance(latest.distanceM.toDouble(), widget.unit),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    latestLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _BarChart(
              periods: periods,
              maxDistanceM: maxDistance,
              unit: widget.unit,
            ),
          ],
        ),
      ),
    );
  }

  /// "this week" / "this month" / "this year" — the suffix on the
  /// spotlight headline so the user reads the value in context.
  static String _latestLabel(AppLocalizations l10n, MileageView v) =>
      switch (v) {
        MileageView.weekly => l10n.mileageThisWeek,
        MileageView.monthly => l10n.mileageThisMonth,
        MileageView.yearly => l10n.mileageThisYear,
      };
}

class _ViewToggle extends StatelessWidget {
  final MileageView view;
  final ValueChanged<MileageView> onChanged;
  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Chips rather than a SegmentedButton. § 486 exempted SegmentedButton
    // from the narrow-width sweep because it has no knob to bind — which is
    // also why it cannot survive text scaling: the control takes its
    // intrinsic width whatever the parent offers, and at 2x the three
    // French labels want 90 px more than a 360 dp card, more than a line of
    // its own would give it. Chips in a Wrap reflow instead, and the M3
    // checkmark the segmented control suppressed for width is kept, so
    // selection is not signalled by fill colour alone (§ 488).
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (value, label) in [
          (MileageView.weekly, l10n.mileageWeek),
          (MileageView.monthly, l10n.mileageMonth),
          (MileageView.yearly, l10n.mileageYear),
        ])
          ChoiceChip(
            label: Text(label),
            selected: view == value,
            onSelected: (_) => onChanged(value),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<MileagePeriod> periods;
  final int maxDistanceM;
  final DistanceUnit unit;
  const _BarChart({
    required this.periods,
    required this.maxDistanceM,
    required this.unit,
  });

  static const double _barAreaHeight = 110;
  // Headroom under the bar for the axis label only — the per-bar
  // numeric labels are gone (the spotlight headline carries the
  // current value) so the column needs less vertical slack.
  static const double _labelsExtra = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ChartPalette.of(context).bar;
    final dim = theme.colorScheme.onSurfaceVariant;
    // The label lane holds text, so it is a text-derived dimension and has to
    // track the OS text scale: at 2x a labelSmall line needs 32 px, and a
    // fixed 24 px lane let the rotated label paint over the bars instead.
    final labelLane = MediaQuery.textScalerOf(context).scale(_labelsExtra);
    return SizedBox(
      height: _barAreaHeight + labelLane,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in periods)
            Expanded(
              child: _BarColumn(
                period: p,
                fraction: maxDistanceM <= 0
                    ? 0
                    : (p.distanceM / maxDistanceM).clamp(0.0, 1.0),
                accent: accent,
                dim: dim,
                unit: unit,
                barAreaHeight: _barAreaHeight,
                labelLane: labelLane,
              ),
            ),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  final MileagePeriod period;
  final double fraction;
  final Color accent;
  final Color dim;
  final DistanceUnit unit;
  final double barAreaHeight;
  final double labelLane;
  const _BarColumn({
    required this.period,
    required this.fraction,
    required this.accent,
    required this.dim,
    required this.unit,
    required this.barAreaHeight,
    required this.labelLane,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bars with zero distance still render a 2 px marker so an off
    // week is visually distinguishable from a missing one.
    final barHeight = period.distanceM <= 0
        ? 2.0
        : (barAreaHeight * fraction).clamp(2.0, barAreaHeight);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: accent,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 4),
          // Rotate the label -45° so 12 columns × "13 May"-style
          // strings fit without clipping under each ~24 px-wide bar.
          // The vertical headroom (_labelsExtra = 24 px) was sized
          // for diagonal labels; horizontal labels under cramped
          // columns truncated mid-character. Field report: "Mileage
          // -> Week numbers below the vertical lines are cut off."
          SizedBox(
            height: labelLane - 4,
            child: Transform.rotate(
              angle: -0.6,
              alignment: Alignment.center,
              child: Text(
                period.label,
                style: theme.textTheme.labelSmall?.copyWith(color: dim),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
