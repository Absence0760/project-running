import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../preferences.dart';
import '../segments.dart';

/// Per-run segment-effort chips on `run_detail_screen`. Mirrors the
/// web `RunSegmentEfforts.svelte` component (decisions §37).
class RunSegmentEfforts extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final String? runOwnerId;
  final String? routeId;
  final List<Waypoint> track;

  const RunSegmentEfforts({
    super.key,
    required this.api,
    required this.runId,
    required this.routeId,
    required this.track,
    this.runOwnerId,
  });

  @override
  State<RunSegmentEfforts> createState() => _RunSegmentEffortsState();
}

class _RunSegmentEffortsState extends State<RunSegmentEfforts> {
  bool _loading = true;
  List<SegmentEffortWithSegment> _efforts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final viewerId = widget.api.userId;
      final isOwner = widget.runOwnerId != null &&
          viewerId != null &&
          viewerId == widget.runOwnerId;
      if (isOwner && widget.routeId != null && widget.track.length > 1) {
        await autoComputeEffortsForRun(
          api: widget.api,
          runId: widget.runId,
          userId: widget.runOwnerId!,
          routeId: widget.routeId!,
          track: widget.track,
        );
      }
      final efforts =
          await widget.api.fetchEffortsForRunWithSegments(widget.runId);
      if (!mounted) return;
      setState(() {
        _efforts = efforts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          'Checking segments…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_efforts.isEmpty) {
      final hint = widget.routeId == null
          ? 'Segments are matched per route — link this run to a saved route to compete on its leaderboards.'
          : 'No segment efforts on this run.';
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _efforts) _EffortRow(entry: e),
        ],
      ),
    );
  }
}

class _EffortRow extends StatelessWidget {
  final SegmentEffortWithSegment entry;
  const _EffortRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = entry.segment.lengthM ??
        (entry.segment.endDistanceM - entry.segment.startDistanceM);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.segment.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtKm(length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _RankPill(rank: entry.rank),
            const SizedBox(width: 12),
            Text(
              _fmtTime(entry.effort.timeSeconds),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtKm(double m) {
    // The function name is legacy ("_fmtKm" predates the unit-aware
    // sweep); the implementation now honours the user's active unit
    // pref. Sub-1 unit values render in metres / yards so a 500 m
    // segment doesn't display as "0.50 km" / "0.31 mi" — the
    // shorter unit reads more naturally for segments.
    final unit = activeDistanceUnit;
    if (unit == DistanceUnit.mi) {
      const metresPerMile = 1609.344;
      if (m >= metresPerMile) return UnitFormat.distance(m, unit);
      return '${(m * 1.09361).round()} yd';
    }
    if (m >= 1000) return UnitFormat.distance(m, unit);
    return '${m.round()} m';
  }

  static String _fmtTime(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _RankPill extends StatelessWidget {
  final int rank;
  const _RankPill({required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = _colors(theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$rank',
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color, Color) _colors(ThemeData theme) {
    if (rank == 1) return (const Color(0xFFF59E0B), Colors.white);
    if (rank <= 3) return (const Color(0xFF94A3B8), Colors.white);
    if (rank <= 10) return (const Color(0xFFB45309), Colors.white);
    return (
      theme.colorScheme.surfaceContainerHighest,
      theme.colorScheme.onSurfaceVariant,
    );
  }
}
