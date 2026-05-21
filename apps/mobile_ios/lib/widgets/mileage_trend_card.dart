import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

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
    if (widget.runs.isEmpty) return const SizedBox.shrink();
    final periods = aggregateMileage(
      widget.runs,
      view: _view,
      now: widget.now,
      // Padding ON so the yearly view backfills empty prior years
      // when the user only has a single year of data — fixes "the
      // Mileage -> year looks ugly with just one year." Pure-logic
      // aggregateMileage callers default to false so the change
      // doesn't surprise non-rendering consumers.
      padYearlyToMin: true,
    );
    if (periods.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final maxDistance = periods
        .map((p) => p.distanceM)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final latest = periods.last;
    final latestLabel = _latestLabel(_view);

    return Card(
      // Use the Card default margin (EdgeInsets.all(4)) so this card
      // matches the width of every other Card in the dashboard
      // ListView (which itself supplies 16 px horizontal padding).
      // The earlier explicit `fromLTRB(16, 8, 16, 8)` doubled the
      // gutter and made this card visibly narrower than its siblings
      // — field report: "the Mileage modal looks less wide (thinner)
      // than the other modals on the dashboard."
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'MILEAGE',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.06,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                _ViewToggle(
                  view: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ],
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
                      color: theme.colorScheme.outline,
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
  static String _latestLabel(MileageView v) => switch (v) {
        MileageView.weekly => 'this week',
        MileageView.monthly => 'this month',
        MileageView.yearly => 'this year',
      };
}

class _ViewToggle extends StatelessWidget {
  final MileageView view;
  final ValueChanged<MileageView> onChanged;
  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MileageView>(
      segments: const [
        ButtonSegment(value: MileageView.weekly, label: Text('Week')),
        ButtonSegment(value: MileageView.monthly, label: Text('Month')),
        ButtonSegment(value: MileageView.yearly, label: Text('Year')),
      ],
      selected: {view},
      onSelectionChanged: (s) => onChanged(s.first),
      // Compact density so the toggle fits next to the section header
      // without forcing the card into two rows on narrow phones.
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
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
    final accent = theme.colorScheme.primary;
    final dim = theme.colorScheme.outline;
    return SizedBox(
      height: _barAreaHeight + _labelsExtra,
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
  const _BarColumn({
    required this.period,
    required this.fraction,
    required this.accent,
    required this.dim,
    required this.unit,
    required this.barAreaHeight,
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
                  const BorderRadius.vertical(top: Radius.circular(3)),
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
            height: 20,
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
