import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../goals.dart';
import '../local_run_store.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import 'run_detail_screen.dart';

enum PeriodType { week, month }

// ── Pure helpers (testable without widget infrastructure) ────────────────

DateTime periodStart(PeriodType period, DateTime anchor) {
  switch (period) {
    case PeriodType.week:
      return weekStartLocal(anchor);
    case PeriodType.month:
      return DateTime(anchor.year, anchor.month, 1);
  }
}

DateTime periodEnd(PeriodType period, DateTime anchor) {
  switch (period) {
    case PeriodType.week:
      return weekStartLocal(anchor).add(const Duration(days: 7));
    case PeriodType.month:
      final nextMonth = anchor.month == 12 ? 1 : anchor.month + 1;
      final year = anchor.month == 12 ? anchor.year + 1 : anchor.year;
      return DateTime(year, nextMonth, 1);
  }
}

String periodTitle(PeriodType period, DateTime anchor) {
  switch (period) {
    case PeriodType.week:
      return 'Week of ${shortDate(periodStart(period, anchor))}';
    case PeriodType.month:
      return '${monthName(anchor.month)} ${anchor.year}';
  }
}

String periodLabel(PeriodType period, DateTime anchor) {
  final start = periodStart(period, anchor);
  switch (period) {
    case PeriodType.week:
      final end = start.add(const Duration(days: 6));
      return '${shortDate(start)} – ${shortDate(end)}';
    case PeriodType.month:
      return '${monthName(start.month)} ${start.year}';
  }
}

class PeriodStats {
  final int runCount;
  final double totalDistanceMetres;
  final int totalDurationSec;
  final double? avgPaceSecPerKm;

  const PeriodStats({
    required this.runCount,
    required this.totalDistanceMetres,
    required this.totalDurationSec,
    required this.avgPaceSecPerKm,
  });
}

PeriodStats computePeriodStats(List<Run> runs) {
  var totalDistance = 0.0;
  var totalDurationSec = 0;
  for (final r in runs) {
    totalDistance += r.distanceMetres;
    totalDurationSec += r.duration.inSeconds;
  }
  // Compute avg pace from running/walking/hiking only — mixing in cycling
  // distances and durations produces a nonsensical pace figure.
  var paceDistance = 0.0;
  var paceDurationSec = 0;
  for (final r in runs) {
    final activity = r.metadata?['activity_type'] as String?;
    if (activity == 'cycle') continue;
    paceDistance += r.distanceMetres;
    paceDurationSec += r.duration.inSeconds;
  }
  final avgPace = paceDistance > 10
      ? paceDurationSec / (paceDistance / 1000)
      : null;
  return PeriodStats(
    runCount: runs.length,
    totalDistanceMetres: totalDistance,
    totalDurationSec: totalDurationSec,
    avgPaceSecPerKm: avgPace,
  );
}

String buildPeriodShareText({
  required PeriodType period,
  required DateTime anchor,
  required List<Run> runs,
  required DistanceUnit unit,
}) {
  final stats = computePeriodStats(runs);
  final dist = UnitFormat.distance(stats.totalDistanceMetres, unit);
  final dur = formatDurationCoarse(Duration(seconds: stats.totalDurationSec));
  final pace = stats.avgPaceSecPerKm != null
      ? '${UnitFormat.pace(stats.avgPaceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}'
      : null;

  final buf = StringBuffer();
  buf.writeln(periodTitle(period, anchor));
  buf.writeln('${stats.runCount} run${stats.runCount == 1 ? '' : 's'}');
  buf.writeln('$dist  |  $dur');
  if (pace != null) buf.writeln('Avg pace: $pace');

  if (runs.isNotEmpty) {
    buf.writeln();
    for (final r in runs) {
      final d = UnitFormat.distance(r.distanceMetres, unit);
      final t = formatDurationCoarse(r.duration);
      buf.writeln('${shortDate(r.startedAt)}  $d  $t');
    }
  }

  return buf.toString().trimRight();
}

String shortDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

String monthName(int month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[month - 1];
}

String formatDurationCoarse(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  final s = d.inSeconds % 60;
  return '${m}m ${s}s';
}

/// Browsable summary of a week or month of running history.
///
/// Shows aggregate stats (distance, runs, time, avg pace) plus a run list
/// for the selected period. Left/right arrows navigate to adjacent periods.
/// The share button offers plain-text or screenshot sharing.
class PeriodSummaryScreen extends StatefulWidget {
  final PeriodType initialPeriod;
  final DateTime initialAnchor;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  const PeriodSummaryScreen({
    super.key,
    required this.initialPeriod,
    required this.initialAnchor,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
  });

  @override
  State<PeriodSummaryScreen> createState() => _PeriodSummaryScreenState();
}

class _PeriodSummaryScreenState extends State<PeriodSummaryScreen> {
  late PeriodType _period;
  late DateTime _anchor;

  List<Run> _periodRuns = const [];

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _anchor = widget.initialAnchor;
    widget.runStore.addListener(_onChanged);
    widget.preferences.addListener(_onChanged);
    _recompute();
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onChanged);
    widget.preferences.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _recompute();
    setState(() {});
  }

  void _recompute() {
    final start = periodStart(_period, _anchor);
    final end = periodEnd(_period, _anchor);
    _periodRuns = widget.runStore.runs
        .where((r) => !r.startedAt.isBefore(start) && r.startedAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  bool get _isFuture {
    final now = DateTime.now();
    final end = periodEnd(_period, _anchor);
    return end.isAfter(now.add(const Duration(days: 1)));
  }

  void _previous() {
    setState(() {
      switch (_period) {
        case PeriodType.week:
          _anchor = _anchor.subtract(const Duration(days: 7));
        case PeriodType.month:
          _anchor = DateTime(
            _anchor.month == 1 ? _anchor.year - 1 : _anchor.year,
            _anchor.month == 1 ? 12 : _anchor.month - 1,
            1,
          );
      }
      _recompute();
    });
  }

  void _next() {
    if (_isFuture) return;
    setState(() {
      switch (_period) {
        case PeriodType.week:
          _anchor = _anchor.add(const Duration(days: 7));
        case PeriodType.month:
          _anchor = DateTime(
            _anchor.month == 12 ? _anchor.year + 1 : _anchor.year,
            _anchor.month == 12 ? 1 : _anchor.month + 1,
            1,
          );
      }
      _recompute();
    });
  }

  // ── Share ──────────────────────────────────────────────────────────

  void _showShareSheet() {
    final unit = widget.preferences.unit;
    final stats = computePeriodStats(_periodRuns);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PeriodShareSheet(
        periodTitle: periodTitle(_period, _anchor),
        periodLabel: periodLabel(_period, _anchor),
        periodName: _period.name,
        periodStartIso: periodStart(_period, _anchor).toIso8601String(),
        shareText: buildPeriodShareText(
          period: _period,
          anchor: _anchor,
          runs: _periodRuns,
          unit: unit,
        ),
        stats: stats,
        unit: unit,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final stats = computePeriodStats(_periodRuns);

    return Scaffold(
      appBar: AppBar(
        title: Text(_period == PeriodType.week ? 'Weekly Summary' : 'Monthly Summary'),
        actions: [
          if (_periodRuns.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _showShareSheet,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPeriodNav(theme),
          const SizedBox(height: 16),
          _buildStatsCard(theme, unit, stats),
          const SizedBox(height: 24),
          if (_periodRuns.isEmpty)
            _buildEmptyState(theme)
          else ...[
            Text(
              '${_periodRuns.length} run${_periodRuns.length == 1 ? '' : 's'}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final run in _periodRuns)
              _RunTile(
                key: ValueKey(run.id),
                run: run,
                unit: unit,
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RunDetailScreen(
                      run: run,
                      runStore: widget.runStore,
                      routeStore: widget.routeStore,
                      preferences: widget.preferences,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodNav(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous',
          onPressed: _previous,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _switchPeriodType(),
            child: Column(
              children: [
                Text(
                  periodTitle(_period, _anchor),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to switch to ${_period == PeriodType.week ? 'monthly' : 'weekly'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next',
          onPressed: _isFuture ? null : _next,
        ),
      ],
    );
  }

  void _switchPeriodType() {
    setState(() {
      _period = _period == PeriodType.week ? PeriodType.month : PeriodType.week;
      _recompute();
    });
  }

  Widget _buildStatsCard(ThemeData theme, DistanceUnit unit, PeriodStats stats) {
    final dur = formatDurationCoarse(Duration(seconds: stats.totalDurationSec));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryStat(
                  label: 'Distance',
                  value: UnitFormat.distanceValue(stats.totalDistanceMetres, unit),
                  unit: UnitFormat.distanceLabel(unit),
                ),
                _SummaryStat(
                  label: 'Runs',
                  value: '${stats.runCount}',
                ),
                _SummaryStat(
                  label: 'Time',
                  value: dur,
                ),
              ],
            ),
            if (stats.avgPaceSecPerKm != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SummaryStat(
                    label: 'Avg pace',
                    value: UnitFormat.pace(stats.avgPaceSecPerKm, unit),
                    unit: UnitFormat.paceLabel(unit),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.event_busy, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'No runs this ${_period == PeriodType.week ? 'week' : 'month'}',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

}

// ── Reusable widgets ───────────────────────────────────────────────────

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _SummaryStat({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
      ],
    );
  }
}

class _RunTile extends StatelessWidget {
  final Run run;
  final DistanceUnit unit;
  final ThemeData theme;
  final VoidCallback onTap;

  const _RunTile({
    super.key,
    required this.run,
    required this.unit,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dist = UnitFormat.distance(run.distanceMetres, unit);
    final dur = _formatDuration(run.duration);
    final paceSecPerKm = run.distanceMetres < 10
        ? null
        : run.duration.inSeconds / (run.distanceMetres / 1000);
    final activity =
        ActivityType.fromName(run.metadata?['activity_type'] as String?);
    final trailingMetric = activity.usesSpeed
        ? '${UnitFormat.speed(paceSecPerKm, unit)} ${UnitFormat.speedLabel(unit)}'
        : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
    final date = _formatDate(run.startedAt);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(activity.icon, color: theme.colorScheme.primary),
        ),
        title: Text(dist),
        subtitle: Text('$date  •  $dur'),
        trailing: Text(trailingMetric, style: theme.textTheme.bodySmall),
        onTap: onTap,
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

// ── Share sheet ─────────────────────────────────────────────────────────

class _PeriodShareSheet extends StatefulWidget {
  final String periodTitle;
  final String periodLabel;
  final String periodName;
  final String periodStartIso;
  final String shareText;
  final PeriodStats stats;
  final DistanceUnit unit;

  const _PeriodShareSheet({
    required this.periodTitle,
    required this.periodLabel,
    required this.periodName,
    required this.periodStartIso,
    required this.shareText,
    required this.stats,
    required this.unit,
  });

  @override
  State<_PeriodShareSheet> createState() => _PeriodShareSheetState();
}

class _PeriodShareSheetState extends State<_PeriodShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _capturing = false;

  Future<void> _shareImage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 300));
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tmp = await getTemporaryDirectory();
      final file = File(
        '${tmp.path}/period-${widget.periodName}-${widget.periodStartIso}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: widget.periodTitle,
      );
    } catch (e) {
      debugPrint('Failed to capture period share card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create share image')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _shareText() {
    Share.share(widget.shareText);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + mq.viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Share summary', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: _PeriodShareCard(
                      periodTitle: widget.periodTitle,
                      periodLabel: widget.periodLabel,
                      stats: widget.stats,
                      unit: widget.unit,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _capturing ? null : _shareText,
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Text'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _capturing ? null : _shareImage,
                      icon: _capturing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.image_outlined),
                      label: const Text('Image'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share card ──────────────────────────────────────────────────────────

class _PeriodShareCard extends StatelessWidget {
  final String periodTitle;
  final String periodLabel;
  final PeriodStats stats;
  final DistanceUnit unit;

  const _PeriodShareCard({
    required this.periodTitle,
    required this.periodLabel,
    required this.stats,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final dist = UnitFormat.distanceValue(stats.totalDistanceMetres, unit);
    final distLabel = UnitFormat.distanceLabel(unit);
    final dur = formatDurationCoarse(Duration(seconds: stats.totalDurationSec));
    final pace = stats.avgPaceSecPerKm != null
        ? UnitFormat.pace(stats.avgPaceSecPerKm, unit)
        : null;
    final paceLabel = UnitFormat.paceLabel(unit);

    return Container(
      color: const Color(0xFF0B0A1F),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                periodTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                periodLabel,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _shareCardStat(label: 'DISTANCE', value: dist, unitLabel: distLabel),
              _shareCardStat(label: 'RUNS', value: '${stats.runCount}'),
              _shareCardStat(label: 'TIME', value: dur),
              if (pace != null)
                _shareCardStat(label: 'AVG PACE', value: pace, unitLabel: paceLabel),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'BETTER RUNNER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _shareCardStat({
    required String label,
    required String value,
    String? unitLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            if (unitLabel != null) ...[
              const SizedBox(width: 3),
              Text(
                unitLabel,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

}
