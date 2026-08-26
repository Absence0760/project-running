import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, AppTheme, StatusPill;

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../screens/global_segments_screen.dart';
import '../segments.dart';

/// Per-run segment-effort chips on `run_detail_screen`. Mirrors the
/// web `RunSegmentEfforts.svelte` component (decisions §37), including its
/// second list: the efforts this run earned on the free-standing famous-segment
/// catalogue (decisions §233), each row opening that segment's catalogue page.
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
  List<GlobalSegmentEffortWithSegment> _globalEfforts = const [];

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
    await _loadCatalogueEfforts();
  }

  /// Catalogue efforts are read in their own guarded pass so a failure there
  /// cannot cost the run its route-segment chips — the catalogue list is the
  /// additive layer of this panel, not its floor.
  Future<void> _loadCatalogueEfforts() async {
    if (widget.api.userId == null) return;
    try {
      final globals = await widget.api.fetchGlobalEffortsForRun(widget.runId);
      if (!mounted) return;
      setState(() => _globalEfforts = globals);
    } catch (e) {
      debugPrint('run_segment_efforts: catalogue efforts unavailable: $e');
    }
  }

  void _openCatalogue() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GlobalSegmentsScreen(api: widget.api),
    ));
  }

  void _openCatalogueSegment(String segmentId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GlobalSegmentDetailScreen(
        api: widget.api,
        segmentId: segmentId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          l10n.runSegEffortsChecking,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_efforts.isEmpty && _globalEfforts.isEmpty) {
      final hint = widget.routeId == null
          ? l10n.runSegEffortsNoRoute
          : l10n.runSegEffortsEmpty;
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
          if (_globalEfforts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.segmentCatalogueTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openCatalogue,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(l10n.segmentCatalogueBrowseAll),
                  ),
                ],
              ),
            ),
            for (final e in _globalEfforts)
              _CatalogueEffortRow(
                entry: e,
                onTap: () => _openCatalogueSegment(e.segment.id),
              ),
          ],
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
              formatEffortTime(entry.effort.timeSeconds),
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
}

/// One catalogue-segment effort. Tappable, unlike the route-segment row above:
/// a famous segment has a page of its own to open.
class _CatalogueEffortRow extends StatelessWidget {
  final GlobalSegmentEffortWithSegment entry;
  final VoidCallback onTap;

  const _CatalogueEffortRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final region = entry.segment.region;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                      [
                        formatDistanceForPref(entry.segment.distanceM),
                        if (region != null && region.trim().isNotEmpty) region,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _RankPill(rank: entry.rank),
              const SizedBox(width: 12),
              Text(
                formatEffortTime(entry.effort.timeSeconds),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of "#3" when the standing is unknown. Mirrors the web
/// `UNKNOWN_RANK_TEXT`.
@visibleForTesting
const String kUnknownRankText = '—';

/// Fill and foreground for a leaderboard rank pill, as `(background, text)`.
///
/// Both medal fills are fixed metal hues, so their foregrounds are fixed too —
/// the pill is opaque and what sits under it never reaches the text. Silver is
/// a LIGHT metal: it carries dark ink (6.87:1), not the white it shipped with
/// (2.56:1). Bronze is dark enough for white (5.02:1). Only the crown is
/// theme-aware, through [AppSemanticColors].
///
/// A NULL rank — the RPC did not answer for this effort — takes the same
/// neutral pair as an unplaced rank, never the crown. It is the whole point of
/// the nullable type: an absent standing used to arrive here as `1`, so the
/// most flattering claim the chip can make was what having no answer produced
/// (decisions §746).
@visibleForTesting
(Color, Color) rankPillColors(ThemeData theme, int? rank) {
  if (rank == 1) {
    final semantic = AppSemanticColors.ofTheme(theme);
    return (semantic.crown, semantic.onCrown);
  }
  if (rank != null && rank >= 1) {
    if (rank <= 3) return (const Color(0xFF94A3B8), AppTheme.ink);
    if (rank <= 10) return (const Color(0xFFB45309), Colors.white);
  }
  return (
    theme.colorScheme.surfaceContainerHighest,
    theme.colorScheme.onSurfaceVariant,
  );
}

/// Pill text: the ordinal, or the placeholder when the standing is unknown.
@visibleForTesting
String rankPillText(int? rank) =>
    rank == null || rank < 1 ? kUnknownRankText : '#$rank';

class _RankPill extends StatelessWidget {
  final int? rank;
  const _RankPill({required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = rankPillColors(theme, rank);
    final pill =
        StatusPill(label: rankPillText(rank), foreground: fg, fill: bg);
    if (rank != null && rank! >= 1) return pill;
    // The placeholder is a glyph, so the pill needs a real name spoken in
    // its place rather than an em dash read aloud.
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).runSegEffortsRankUnknown,
      excludeSemantics: true,
      child: pill,
    );
  }
}
